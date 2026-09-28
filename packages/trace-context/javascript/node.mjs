// node:http integration for the facade: the fields of a received
// IncomingMessage, and the headers of a request to send with node:http.
// Like the facade, it decides no Trace Context rule.
import { continueOrStart, extract } from './index.mjs';
import { copyFields } from './fields.mjs';

// The fields of a received request (a node:http IncomingMessage), from its
// raw header lines: every line in arrival order, with its name as it came,
// so that extraction refuses a repeated traceparent and reads repeated
// tracestate lines in order.
export function requestFields(request) {
  const raw = typeof request === 'object' && request !== null ? request.rawHeaders : undefined;
  const length = Array.isArray(raw) ? raw.length : 1;
  if (length % 2 !== 0) throw new TypeError('request must be a node:http IncomingMessage');
  const fields = [];
  for (let index = 0; index < length; index += 2) {
    const name = raw[index];
    const value = raw[index + 1];
    if (typeof name !== 'string' || typeof value !== 'string') {
      throw new TypeError('request must be a node:http IncomingMessage');
    }
    fields.push([name, value]);
  }
  return fields;
}

// The extraction of a received request (extract of its requestFields).
export function extractRequest(request, options) {
  return extract(requestFields(request), options);
}

// The service's operation for a received request: extractRequest, then
// continueOrStart. `options` holds the options of both.
export function continueOrStartRequest(request, options) {
  return continueOrStart(extractRequest(request, options), options);
}

// The headers of a request to send with node:http, for the `headers` option
// of http.request or ClientRequest: each name once, with the spelling of its
// first field, and its values in order, as an array when it repeats, so
// that node:http writes one header line per field. A name's lines follow
// one another at the place of its first field: RFC 9110 gives the order of
// fields with different names no meaning, and no Trace Context rule depends
// on it. The object has no prototype, so a field named __proto__ is kept.
export function requestHeaders(fields) {
  const headers = Object.create(null);
  const spellings = new Map();
  for (const [name, value] of copyFields(fields)) {
    const spelling = spellings.get(name.toLowerCase());
    if (spelling === undefined) {
      spellings.set(name.toLowerCase(), name);
      headers[name] = value;
    } else {
      headers[spelling] = [].concat(headers[spelling], value);
    }
  }
  return headers;
}
