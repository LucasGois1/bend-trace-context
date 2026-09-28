// Types of bend-trace-context/fetch, the facade's Fetch integration.
import type { SendOptions, Sent, Service } from './index.mjs';

// An element as documentFields reads it.
export interface MetaElement {
  getAttribute(name: string): string | null;
}

// A DOM document, or anything that selects its <meta> elements.
export interface DocumentLike {
  querySelectorAll(selectors: string): ArrayLike<MetaElement>;
}

// The fields of the context that the page's server rendered as
// <meta name="traceparent"> and <meta name="tracestate"> elements, in
// document order, for extract.
export function documentFields(document: DocumentLike): Array<[name: string, value: string]>;

export interface TracedFetchOptions extends SendOptions {
  // Origins, such as 'https://api.example.com', or RegExps searched in the
  // whole URL, that may receive the context fields besides the page's own
  // origin.
  propagateTo?: string | RegExp | ReadonlyArray<string | RegExp> | null;
  // The function that sends, globalThis.fetch by default.
  fetch?: (input: string | Request, init: RequestInit) => Promise<Response>;
}

export interface TracedResponse {
  readonly response: Response;
  // The request's context, or null when its destination may not receive
  // the context fields and it went without them.
  readonly sent: Sent | null;
}

// Send one request with fetch, with a new child of the service's operation
// when its destination may receive the context fields.
export function tracedFetch(service: Service, input: string | URL | Request, init?: RequestInit | null,
  options?: TracedFetchOptions): Promise<TracedResponse>;
