// Types of bend-trace-context, the JavaScript facade of the Bend package.
// Every function also checks its arguments at run time, since JavaScript
// callers need not use these types: a wrong type throws a TypeError, and a
// value that the package refuses throws a RangeError. See JAVASCRIPT.md.

// The fields of a message: [name, value] string pairs in the message's
// order. The functions below read an array of them once and copy it.
export type Fields = ReadonlyArray<readonly [name: string, value: string]>;

// Fields that the facade returns: a frozen array of frozen pairs.
export type FrozenFields = ReadonlyArray<readonly [name: string, value: string]>;

// How a service takes the context that extraction kept: it continues it, or
// restarts the trace, as at a trust boundary.
export type Reception = 'continue' | 'restart';

// How a new operation obtains its sampled flag: a child inherits its
// parent's and a root or a restart takes the root default, not sampled; or
// it is set.
export type Sampling = 'inherit' | 'sampled' | 'unsampled';

// What a failed generation gives: the business operation proceeds without a
// new operation, or the function throws a GenerationError.
export type Policy = 'lenient' | 'strict';

// A source of random words with WebCrypto's getRandomValues, such as
// globalThis.crypto or node:crypto's webcrypto. The facade passes it one
// Uint32Array of one element at a time; the parameter is typed loosely so
// that the signature of every WebCrypto implementation fits.
export interface RandomSource {
  getRandomValues(array: never): unknown;
}

// Handles: frozen objects that only the facade creates. Each stands for a
// value of the package, and a function that takes a handle refuses any
// other object, including a copy.

// An operation of this participant.
export interface LocalContext {
  readonly [Symbol.toStringTag]: 'LocalContext';
  // The value to send: version 00 with the sampled and random-trace-id flags.
  readonly traceparent: string;
  readonly traceId: string;
  readonly spanId: string;
  readonly sampled: boolean;
  readonly random: boolean;
}

// The pair a context was received with, as it was accepted.
export interface ReceivedPair {
  readonly traceparent: string;
  // The tracestate field values as they came.
  readonly tracestate: readonly string[];
}

// A context received from another participant: its operation's identifiers
// and flags, and the state received with it.
export interface IncomingContext {
  readonly [Symbol.toStringTag]: 'IncomingContext';
  readonly traceId: string;
  // The span ID of the sender's operation.
  readonly spanId: string;
  readonly sampled: boolean;
  readonly random: boolean;
  // The normalized tracestate received with it.
  readonly tracestate: string;
  // The accepted pair, or null when the tracestate was discarded.
  readonly received: ReceivedPair | null;
}

// An operation of this participant with the state it sends.
export interface OutgoingContext {
  readonly [Symbol.toStringTag]: 'OutgoingContext';
  readonly context: LocalContext;
  // The normalized tracestate it sends, before truncation.
  readonly tracestate: string;
}

// The context of a received message, and what extraction made of its fields.
export interface Extraction {
  readonly [Symbol.toStringTag]: 'Extraction';
  // Both outcomes, for a log line: "TraceParentAccepted, StateAccepted".
  readonly show: string;
  // The traceparent outcome, such as "TraceParentRejected RepeatedTraceParent".
  readonly parent: string;
  // The tracestate outcome, such as "StateDiscarded TooManyMembers".
  readonly state: string;
  // The message's own context, or null.
  readonly incoming: IncomingContext | null;
  // The context kept: the message's, or the base when it has none usable.
  readonly context: IncomingContext | OutgoingContext | null;
}

// How a service's operation came about.
export type Origin = 'Continued' | 'Started' | 'Restarted';

// A service's own operation for a received message, or its absence.
export interface Service {
  readonly [Symbol.toStringTag]: 'Service';
  // "Continued", "Started", "Restarted", or "Untraced" with its error.
  readonly show: string;
  readonly origin: Origin | null;
  // Why the service has no operation, such as "SourceFailure 1 unavailable".
  readonly error: string | null;
  readonly outgoing: OutgoingContext | null;
}

// One message that a service sends.
export interface Sent {
  readonly [Symbol.toStringTag]: 'Sent';
  // "Fresh", "Fresh, truncated", "Forwarded after ..." or "NoContext after ...".
  readonly show: string;
  // The fields to send the message with, in every case.
  readonly fields: FrozenFields;
  // The message's new operation, or null.
  readonly operation: LocalContext | null;
  // Why no operation was generated, or null.
  readonly error: string | null;
  // The tracestate keys that truncation to the output budget removed.
  readonly dropped: readonly string[];
}

// Budgets, in UTF-8 octets, for what the package reads and emits.
export interface Limits {
  readonly [Symbol.toStringTag]: 'Limits';
  readonly traceparentInput: number;
  readonly tracestateInput: number;
  readonly tracestateOutput: number;
}

// Why no new identifier could be generated where no lenient fallback
// applies. `reason` is the package's GenerationError: "SourceFailure 1
// unavailable", "SourceFailure 2 source-failure", "ExhaustedTraceId" or
// "ExhaustedSpanId".
export class GenerationError extends Error {
  constructor(reason: string);
  name: 'GenerationError';
  readonly reason: string;
}

export interface GenerationOptions {
  // The source of words: globalThis.crypto by default; null models an
  // unavailable source.
  crypto?: RandomSource | null;
}

export interface ChildOptions extends GenerationOptions {
  sampling?: Sampling;
}

export interface LimitsOption {
  limits?: Limits;
}

export interface ExtractOptions extends LimitsOption {
  // The context to keep when the message carries no usable traceparent.
  base?: IncomingContext | OutgoingContext | null;
}

export interface ContinueOptions extends GenerationOptions {
  reception?: Reception;
  sampling?: Sampling;
  policy?: Policy;
}

export interface SendOptions extends LimitsOption, GenerationOptions {
  sampling?: Sampling;
  policy?: Policy;
}

export interface LimitsOptions {
  traceparentInput?: number;
  tracestateInput?: number;
  tracestateOutput?: number;
}

export interface SuppliedTraceOptions {
  // The application's assertion that the trace ID's digits are random.
  random?: boolean;
}

export interface FromIdsOptions extends SuppliedTraceOptions {
  sampled?: boolean;
}

export interface ChildFromIdOptions {
  sampling?: Sampling;
}

export interface OutgoingOptions {
  // The context whose state the outgoing context sends.
  state?: IncomingContext | OutgoingContext | Service | null;
}

export interface Injection {
  readonly fields: FrozenFields;
  readonly dropped: readonly string[];
}

export type Forwarding =
  | { readonly ok: true; readonly fields: FrozenFields }
  | { readonly ok: false; readonly error: string };

export type Inspection =
  | { readonly ok: true; readonly traceparent: string; readonly sampled: boolean }
  | { readonly ok: false; readonly error: string };

// Receiving and sending.
export function extract(fields: Fields, options?: ExtractOptions): Extraction;
export function continueOrStart(extraction: Extraction, options?: ContinueOptions): Service;
export function send(service: Service, fields: Fields, options?: SendOptions): Sent;

// Generation on a random source.
export function root(options?: GenerationOptions): LocalContext;
export function child(parent: IncomingContext | LocalContext, options?: ChildOptions): LocalContext;
export function restart(previous: IncomingContext, options?: GenerationOptions): LocalContext;

// Operations with identifiers that the application supplies, as text.
export function rootFromIds(traceId: string, spanId: string, options?: SuppliedTraceOptions): LocalContext;
export function fromIds(traceId: string, spanId: string, options?: FromIdsOptions): LocalContext;
export function childFromId(parent: IncomingContext | LocalContext, spanId: string,
  options?: ChildFromIdOptions): LocalContext;
export function restartFromIds(previous: IncomingContext, traceId: string, spanId: string,
  options?: SuppliedTraceOptions): LocalContext;

// Tracestate entries.
export function getState(target: IncomingContext | OutgoingContext | Service, key: string): string | null;
export function setState<T extends OutgoingContext | Service>(target: T, key: string, value: string): T;
export function removeState<T extends OutgoingContext | Service>(target: T, key: string): T;

// Injection, forwarding and cleanup.
export function outgoing(context: LocalContext, options?: OutgoingOptions): OutgoingContext;
export function inject(outgoing: OutgoingContext, fields: Fields, options?: LimitsOption): Injection;
export function forward(incoming: IncomingContext, fields: Fields, options?: LimitsOption): Forwarding;
export function clear(fields: Fields): FrozenFields;

export function limits(options?: LimitsOptions): Limits;

// The strict v00 codec on an untrusted value: only a string can be valid.
export function inspectTraceparent(text: unknown): Inspection;
