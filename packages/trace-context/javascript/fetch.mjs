// Fetch integration for the facade, for browser pages: the context that a
// page's server rendered into it, and one traced request per call. It is
// qualified in browsers and in Node, where no page origin exists; other
// hosts are not. Like the facade, it decides no Trace Context rule. Which
// destinations may receive the context fields is its only policy: the
// page's own origin, and the origins or URLs that the caller allows, because
// a cross-origin request carrying them needs a CORS preflight that allows
// them.
import { clear, send } from './index.mjs';
import { copyFields } from './fields.mjs';
import { unwrap } from './handles.mjs';
import { optionsOf, sendOptions } from './options.mjs';

// The fields of the context that a page's server rendered into it, as
// <meta name="traceparent" content="..."> and <meta name="tracestate">
// elements, in document order: the fields to extract the page's context
// from. The names are compared without regard to ASCII case; the <meta>
// convention is OpenTelemetry's, not the W3C's. The selection may be any
// array-like, as a NodeList is in every DOM library.
export function documentFields(document) {
  if (typeof document !== 'object' || document === null || typeof document.querySelectorAll !== 'function') {
    throw new TypeError('document must be a DOM document');
  }
  const fields = [];
  for (const meta of Array.from(document.querySelectorAll('meta[name]'))) {
    const name = String(meta.getAttribute('name')).toLowerCase();
    if (name === 'traceparent' || name === 'tracestate') fields.push([name, String(meta.getAttribute('content') ?? '')]);
  }
  return fields;
}

// The fields of a request's headers, from a HeadersInit, read and converted
// as the Fetch standard reads it: an iterable of [name, value] pairs, such as
// a Headers object or an array, or else a record of names to values, each
// name and value converted to a string. A Headers object gives its names in
// lowercase and sorted, each once with its values joined by ", ". Fetch's
// own Headers then checks the fields, so that an invalid name or value is
// refused before any child is generated.
function headerFields(headers) {
  if (headers === undefined || headers === null) return [];
  if (typeof headers !== 'object') throw new TypeError('init.headers must be a Headers object, pairs or a record');
  const pairs = typeof headers[Symbol.iterator] === 'function'
    ? [...headers].map((pair) => {
      if (typeof pair !== 'object' || pair === null || typeof pair[Symbol.iterator] !== 'function') {
        throw new TypeError('init.headers must hold [name, value] pairs');
      }
      return [...pair];
    })
    : Object.entries(headers);
  const fields = copyFields(pairs.map((pair) => (pair.length === 2 ? [String(pair[0]), String(pair[1])] : pair)));
  if (typeof Headers === 'function') new Headers(fields);
  return fields;
}

// The allowlist: an origin as a string, such as 'https://api.example.com',
// or a RegExp searched in the whole URL. Searching ignores a g or y flag's
// lastIndex, so a RegExp matches the same URLs on every call.
function allowlist(value) {
  const entries = value === undefined || value === null ? [] : Array.isArray(value) ? value : [value];
  return entries.map((entry) => {
    if (entry instanceof RegExp) return entry;
    if (typeof entry !== 'string') throw new TypeError('options.propagateTo entries must be origins or RegExp objects');
    let origin;
    try {
      origin = new URL(entry).origin;
    } catch {
      origin = undefined;
    }
    if (origin !== entry) throw new RangeError(`options.propagateTo entry ${JSON.stringify(entry)} is not an origin`);
    return entry;
  });
}

// Whether a request to `url` in `mode` may carry the context fields: the
// page's own origin, as its document has it (an opaque origin has none), or
// an allowed one. A no-cors request cannot: the browser would drop them.
function propagates(url, mode, allowed) {
  if (mode === 'no-cors') return false;
  const own = globalThis.origin;
  if (typeof own === 'string' && own !== 'null' && url.origin === own) return true;
  return allowed.some((entry) => (typeof entry === 'string' ? entry === url.origin : url.href.search(entry) !== -1));
}

// Send one request with fetch, carrying a new child of the service's
// operation when its destination may receive the context fields (see
// propagates), as `send` gives it: `sent` is its Sent. For any other
// destination, the request goes without context fields and `sent` is null.
// `options` takes propagateTo, the allowlist, `fetch`, the function to send
// with, and send's limits, sampling, policy and crypto, all checked before
// anything is sent. Under the strict policy, a request that may carry the
// context fields is not sent when no new child can be generated, and the
// GenerationError rejects the promise. `init` is copied once, as fetch reads
// it, and a Request keeps its referrer and referrer policy. A redirect that
// fetch follows repeats the request with the same fields at the new URL,
// which the allowlist does not check; `init.redirect` controls it, as for
// any fetch.
export async function tracedFetch(service, input, init, options) {
  unwrap('Service', service, 'service');
  if (init !== undefined && init !== null && typeof init !== 'object') throw new TypeError('init must be an object');
  const requestInit = { ...init };
  const { propagateTo, fetch: sender = globalThis.fetch, ...sendingOptions } = optionsOf(options);
  if (typeof sender !== 'function') throw new TypeError('options.fetch must be a function');
  sendOptions(sendingOptions);
  const allowed = allowlist(propagateTo);
  const request = typeof Request === 'function' && input instanceof Request ? input : undefined;
  const url = new URL(request === undefined ? String(input) : request.url, globalThis.document?.baseURI
    ?? globalThis.location?.href);
  const fields = headerFields(requestInit.headers ?? request?.headers);
  const mode = requestInit.mode ?? request?.mode;
  const sent = propagates(url, mode, allowed) ? send(service, fields, sendingOptions) : null;
  const headers = sent === null ? clear(fields) : sent.fields;
  const kept = request === undefined ? {} : { referrer: request.referrer, referrerPolicy: request.referrerPolicy };
  const response = await sender(request ?? url.href, { ...kept, ...requestInit, headers });
  return Object.freeze({ response, sent });
}
