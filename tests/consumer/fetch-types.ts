// The types of bend-trace-context/fetch as a page sees them: they use the
// Fetch API's own types, so tsconfig.dom.json checks this file with the DOM
// library. The checker must accept every use below and refuse each line
// marked @ts-expect-error. Nothing here runs.
import * as TC from 'bend-trace-context';
import { documentFields, tracedFetch } from 'bend-trace-context/fetch';

// The DOM's own document and WebCrypto are what a page passes.
const service: TC.Service = TC.continueOrStart(TC.extract(documentFields(document)), { crypto: globalThis.crypto });
// Anything whose selection is array-like, as a NodeList is.
declare const page: { querySelectorAll(selectors: string): ArrayLike<{ getAttribute(name: string): string | null }> };
const pageFields: Array<[string, string]> = documentFields(page);

const traced: Promise<TC.Sent | null> = tracedFetch(service, '/api/orders', { method: 'POST' },
  { propagateTo: ['https://api.example.com', /\.example\.org\//], policy: 'lenient' })
  .then(({ response, sent }) => (response.ok ? sent : null));
const withRequest: Promise<Response> = tracedFetch(service, new Request('https://api.example.com/items'), null,
  { propagateTo: 'https://api.example.com', fetch: (input, init) => fetch(input, init) })
  .then(({ response }) => response);

// @ts-expect-error: an allowlist entry is an origin or a RegExp.
tracedFetch(service, '/api/orders', {}, { propagateTo: [4174] });
// @ts-expect-error: a page's fields come from a document.
documentFields({});

export { pageFields, traced, withRequest };
