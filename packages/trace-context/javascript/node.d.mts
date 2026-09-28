// Types of bend-trace-context/node, the facade's node:http integration.
import type { ContinueOptions, Extraction, ExtractOptions, Fields, Service } from './index.mjs';

// A received request as node:http gives it: an IncomingMessage, or anything
// with its raw header lines, such as an Express request or a Fastify
// request's `raw`.
export interface ReceivedRequest {
  readonly rawHeaders: readonly string[];
}

// The fields of a received request, from its raw header lines: every line
// in arrival order, with its name as it came.
export function requestFields(request: ReceivedRequest): Array<[name: string, value: string]>;

// extract of the request's fields.
export function extractRequest(request: ReceivedRequest, options?: ExtractOptions): Extraction;

// extractRequest, then continueOrStart, with the options of both.
export function continueOrStartRequest(request: ReceivedRequest,
  options?: ExtractOptions & ContinueOptions): Service;

// The headers of a request to send with node:http, for the `headers` option
// of http.request: each name once, its values in order, as an array when it
// repeats, so that node:http writes one header line per field.
export function requestHeaders(fields: Fields): Record<string, string | string[]>;
