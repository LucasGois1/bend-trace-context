// The JavaScript facade of bend-trace-context. Every Trace Context rule runs
// in the Bend package (trace_context.bend, compiled by the pinned Bend
// compiler into trace_context.mjs): this module only converts JavaScript
// values at the boundary, feeds WebCrypto words to the package's generation
// machine and wraps the package's values in handles.
//
// A handle is a frozen object that only the facade creates. It carries wire
// text and diagnostics as plain properties, and it stands for a package value
// kept in the private registry of handles.mjs, so an object that merely
// looks like a handle is refused wherever a handle is expected. Handle kinds
// are named after the package's types: LocalContext, IncomingContext,
// OutgoingContext, Extraction, Service, Sent and Limits.
import TC from './trace_context.mjs';
import entropy from '../entropy/webcrypto.js';
import { copyFields } from './fields.mjs';
import { entryOf, handle, unwrap } from './handles.mjs';
import {
  DEFAULT_LIMITS, RECEPTIONS, SAMPLINGS, STRICT, choice, cryptoOf, flag, limitsOf, optionsOf, sendOptions,
} from './options.mjs';

export { inspectTraceparent } from './codec.mjs';

// Why generating an identifier failed where no lenient fallback applies:
// `reason` is the package's GenerationError, such as ExhaustedSpanId or
// SourceFailure 2 source-failure.
export class GenerationError extends Error {
  constructor(reason) {
    super(`Trace context generation failed: ${reason}`);
    this.name = 'GenerationError';
    this.reason = reason;
  }
}

// Handles
// =======

function localHandle(context) {
  const traceId = TC['LocalContext.trace_id'](context);
  return handle('LocalContext', context, {
    traceparent: TC['TraceParentV00.format'](TC['LocalContext.to_traceparent'](context)),
    traceId: TC['TraceId.to_string'](traceId),
    spanId: TC['SpanId.to_string'](TC['LocalContext.span_id'](context)),
    sampled: TC['LocalContext.is_sampled'](context),
    random: TC['TraceId.is_random'](traceId),
  });
}

function outgoingHandle(outgoing) {
  return handle('OutgoingContext', outgoing, {
    context: localHandle(TC['OutgoingContext.context'](outgoing)),
    tracestate: TC['TraceState.format'](TC['OutgoingContext.state'](outgoing)),
  });
}

function incomingHandle(incoming) {
  const context = TC['IncomingContext.context'](incoming);
  const traceId = TC['RemoteContext.trace_id'](context);
  return handle('IncomingContext', incoming, {
    traceId: TC['TraceId.to_string'](traceId),
    spanId: TC['SpanId.to_string'](TC['RemoteContext.span_id'](context)),
    sampled: TC['RemoteContext.is_sampled'](context),
    random: TC['TraceId.is_random'](traceId),
    tracestate: TC['TraceState.format'](TC['IncomingContext.state'](incoming)),
    received: maybe(TC['IncomingContext.received'](incoming), (pair) => Object.freeze({
      traceparent: TC['ReceivedPair.traceparent'](pair),
      tracestate: array(TC['ReceivedPair.tracestate'](pair), (field) => field),
    })),
  });
}

function baseHandle(base) {
  return base.$ === 'IncomingBase' ? incomingHandle(base.incoming) : outgoingHandle(base.outgoing);
}

function extractionHandle(extraction) {
  return handle('Extraction', extraction, {
    show: TC['Extraction.show'](extraction),
    parent: TC['TraceParentOutcome.show'](TC['Extraction.parent'](extraction)),
    state: TC['StateOutcome.show'](TC['Extraction.state'](extraction)),
    incoming: maybe(TC['Extraction.incoming'](extraction), incomingHandle),
    context: maybe(TC['Extraction.context'](extraction), baseHandle),
  });
}

function serviceHandle(service) {
  return handle('Service', service, {
    show: TC['Service.show'](service),
    origin: maybe(TC['Service.origin'](service), (origin) => TC['Origin.show'](origin)),
    error: maybe(TC['Service.error'](service), (error) => TC['GenerationError.show'](error)),
    outgoing: maybe(TC['Service.outgoing'](service), outgoingHandle),
  });
}

function sentHandle(sent) {
  return handle('Sent', sent, {
    show: TC['Sent.show'](sent),
    fields: fieldsOf(TC['Sent.carrier'](sent)),
    operation: maybe(TC['Sent.operation'](sent), localHandle),
    error: maybe(TC['Sent.error'](sent), (error) => TC['GenerationError.show'](error)),
    dropped: keysOf(TC['Sent.dropped'](sent)),
  });
}

function limitsHandle(limits) {
  return handle('Limits', limits, {
    traceparentInput: Number(TC['Limits.traceparent_input'](limits)),
    tracestateInput: Number(TC['Limits.tracestate_input'](limits)),
    tracestateOutput: Number(TC['Limits.tracestate_output'](limits)),
  });
}

// Values at the boundary
// ======================

function maybe(value, convert) {
  return value.$ === 'Some' ? convert(value.value) : null;
}

function array(list, convert) {
  const items = [];
  for (let rest = list; rest.$ === 'Con'; rest = rest.tail) items.push(convert(rest.head));
  return Object.freeze(items);
}

// The package's carrier for the fields of a message (see copyFields).
function carrier(fields) {
  const copy = copyFields(fields);
  let list = { $: 'Nil' };
  for (let index = copy.length - 1; index >= 0; index -= 1) {
    list = { $: 'Con', head: { $: 'Header', name: copy[index][0], value: copy[index][1] }, tail: list };
  }
  return list;
}

function fieldsOf(list) {
  return array(list, (header) => Object.freeze([TC['Header.name'](header), TC['Header.value'](header)]));
}

function keysOf(list) {
  return array(list, (key) => TC['StateKey.to_string'](key));
}

// Generation
// ==========

// Feed the generation words from `crypto` (see cryptoOf), one at a time
// while the package says that it needs one.
function generate(generation, crypto) {
  let current = generation;
  while (TC['Generation.needs'](current)) {
    current = TC['Generation.feed'](current, entropy.readRandomU32(crypto));
  }
  return TC['Generation.result'](current);
}

function orThrow(result) {
  if (result.$ === 'Fail') throw new GenerationError(TC['GenerationError.show'](result.error));
  return result.value;
}

function parentOf(object) {
  const { kind, value } = entryOf(['IncomingContext', 'LocalContext'], object, 'parent');
  return kind === 'IncomingContext' ? { $: 'RemoteParent', context: TC['IncomingContext.context'](value) }
    : { $: 'LocalParent', context: value };
}

// Start a trace: a root operation, not sampled, whose trace ID asserts
// random-trace-id.
export function root(options) {
  const { crypto } = optionsOf(options);
  const source = cryptoOf(crypto);
  return localHandle(orThrow(generate(TC['Generation.root'](), source)));
}

// A new operation continuing `parent`, an IncomingContext or a LocalContext
// of this participant.
export function child(parent, options) {
  const { sampling, crypto } = optionsOf(options);
  const source = cryptoOf(crypto);
  const generation = TC['Generation.child'](parentOf(parent), choice(sampling, 'inherit', SAMPLINGS,
    'options.sampling'));
  return localHandle(orThrow(generate(generation, source)));
}

// A new trace in place of the IncomingContext `previous`, whose trace ID it
// never reuses.
export function restart(previous, options) {
  const { crypto } = optionsOf(options);
  const source = cryptoOf(crypto);
  const context = TC['IncomingContext.context'](unwrap('IncomingContext', previous, 'previous'));
  return localHandle(orThrow(generate(TC['Generation.restart'](context), source)));
}

// Supplied identifiers
// ====================

function parsedId(parse, text, name) {
  if (typeof text !== 'string') throw new TypeError(`${name} must be a string`);
  const result = TC[parse](text);
  if (result.$ === 'Fail') throw new RangeError(TC['Error.show'](result.error));
  return result.value;
}

// A trace ID that the caller supplies; `random` records the caller's
// assertion that its digits were generated randomly.
function traceIdOf(text, random) {
  const id = parsedId('TraceId.parse', text, 'traceId');
  return flag(random, 'options.random') ? TC['TraceId.assert_random'](id) : id;
}

function created(result) {
  if (result.$ === 'Fail') throw new RangeError(TC['ContextError.show'](result.error));
  return localHandle(result.value);
}

// A root operation with identifiers that the caller already has.
export function rootFromIds(traceId, spanId, options) {
  const { random } = optionsOf(options);
  return localHandle(TC['Context.root_from_ids'](traceIdOf(traceId, random), parsedId('SpanId.parse', spanId,
    'spanId')));
}

// An existing operation of this participant with its own identifiers and
// sampled indication, such as one that another tracer created.
export function fromIds(traceId, spanId, options) {
  const { sampled, random } = optionsOf(options);
  return localHandle(TC['Context.from_ids'](traceIdOf(traceId, random), parsedId('SpanId.parse', spanId, 'spanId'),
    flag(sampled, 'options.sampled')));
}

// A new operation continuing `parent` with a span ID that the caller
// supplies; its parent's span ID is refused with ReusedSpanId.
export function childFromId(parent, spanId, options) {
  const { sampling } = optionsOf(options);
  return created(TC['Context.child_from_id'](parentOf(parent), parsedId('SpanId.parse', spanId, 'spanId'),
    choice(sampling, 'inherit', SAMPLINGS, 'options.sampling')));
}

// A new trace in place of `previous` with identifiers that the caller
// supplies; the received trace ID is refused with ReusedTraceId.
export function restartFromIds(previous, traceId, spanId, options) {
  const { random } = optionsOf(options);
  const context = TC['IncomingContext.context'](unwrap('IncomingContext', previous, 'previous'));
  return created(TC['Context.restart_from_ids'](context, traceIdOf(traceId, random),
    parsedId('SpanId.parse', spanId, 'spanId')));
}

// Limits
// ======

function budget(options, name, fallback) {
  const value = options[name];
  if (value === undefined) return fallback;
  if (typeof value !== 'number') throw new TypeError(`options.${name} must be a number`);
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new RangeError(`options.${name} must be a non-negative safe integer`);
  }
  return BigInt(value);
}

// The budgets, in UTF-8 octets, of what the package reads from a received
// message and emits: the package's defaults unless `options` sets them. A
// combination the package refuses throws a RangeError with its LimitsError.
export function limits(options) {
  const given = optionsOf(options);
  const result = TC['Limits.new'](
    budget(given, 'traceparentInput', TC['Limits.traceparent_input'](DEFAULT_LIMITS)),
    budget(given, 'tracestateInput', TC['Limits.tracestate_input'](DEFAULT_LIMITS)),
    budget(given, 'tracestateOutput', TC['Limits.tracestate_output'](DEFAULT_LIMITS)));
  if (result.$ === 'Fail') throw new RangeError(TC['LimitsError.show'](result.error));
  return limitsHandle(result.value);
}

// Receiving and sending
// =====================

function baseOf(object) {
  const { kind, value } = entryOf(['IncomingContext', 'OutgoingContext'], object, 'options.base');
  return { $: 'Some', value: kind === 'IncomingContext' ? { $: 'IncomingBase', incoming: value }
    : { $: 'OutgoingBase', outgoing: value } };
}

// The trace context of a received message, from its fields in their order.
// `options.base` is the IncomingContext or OutgoingContext to continue when
// the message carries no usable traceparent.
export function extract(fields, options) {
  const { limits: given, base } = optionsOf(options);
  const kept = base === undefined || base === null ? { $: 'None' } : baseOf(base);
  return extractionHandle(TC['Context.extract'](limitsOf(given), carrier(fields), kept));
}

// The service's own operation for a received message: a child of the
// context that extraction kept, a root without one, or a restart at a trust
// boundary. Under the strict policy a failed generation throws a
// GenerationError.
export function continueOrStart(extraction, options) {
  const { reception, sampling, policy, crypto } = optionsOf(options);
  const source = cryptoOf(crypto);
  const plan = TC['ServicePlan.new'](unwrap('Extraction', extraction, 'extraction'),
    choice(reception, 'continue', RECEPTIONS, 'options.reception'),
    choice(sampling, 'inherit', SAMPLINGS, 'options.sampling'));
  const strict = choice(policy, 'lenient', STRICT, 'options.policy');
  const service = TC['ServicePlan.service'](plan, generate(TC['ServicePlan.generation'](plan), source));
  return serviceHandle(strict ? orThrow(TC['Serve.strict'](service)) : service);
}

// One message that the service sends, from the message's own fields: a new
// child of the service's operation injected into them, or the fallback.
// Under the strict policy a message without a new operation throws a
// GenerationError.
export function send(service, fields, options) {
  const { limits, sampling, strict, crypto } = sendOptions(options);
  const plan = TC['SendPlan.new'](limits, unwrap('Service', service, 'service'), sampling, carrier(fields));
  const sent = TC['SendPlan.sent'](plan, generate(TC['SendPlan.generation'](plan), crypto));
  return sentHandle(strict ? orThrow(TC['Send.strict'](sent)) : sent);
}

// Tracestate
// ==========

function entryPart(parse, text, name) {
  if (typeof text !== 'string') throw new TypeError(`${name} must be a string`);
  const result = TC[parse](text);
  if (result.$ === 'Fail') throw new RangeError(TC['EntryError.show'](result.error));
  return result.value;
}

function stateKey(key) {
  return entryPart('StateKey.parse', key, 'key');
}

// The state of an IncomingContext or OutgoingContext, or the one a
// Service's operation sends; a service without an operation sends none.
function stateOf(kind, value) {
  if (kind === 'IncomingContext') return TC['IncomingContext.state'](value);
  if (kind === 'OutgoingContext') return TC['OutgoingContext.state'](value);
  const kept = TC['Service.outgoing'](value);
  return kept.$ === 'Some' ? TC['OutgoingContext.state'](kept.value) : TC['TraceState.empty']();
}

// The value of the tracestate entry `key` in the state of an
// IncomingContext or OutgoingContext or of a Service's operation, or null
// without one.
export function getState(target, key) {
  const { kind, value } = entryOf(['IncomingContext', 'OutgoingContext', 'Service'], target, 'target');
  const found = TC['TraceState.get'](stateOf(kind, value), stateKey(key));
  return maybe(found, (entry) => TC['StateValue.to_string'](entry));
}

// Add or update the entry `key` of the state that an OutgoingContext or a
// Service's operation sends: it goes first. A service without an operation
// is returned unchanged.
export function setState(target, key, value) {
  const { kind, value: current } = entryOf(['OutgoingContext', 'Service'], target, 'target');
  const parsedKey = stateKey(key);
  const parsedValue = entryPart('StateValue.parse', value, 'value');
  return kind === 'OutgoingContext' ? outgoingHandle(TC['OutgoingContext.set'](current, parsedKey, parsedValue))
    : serviceHandle(TC['Service.set'](current, parsedKey, parsedValue));
}

// Delete the entry `key` of the state that an OutgoingContext or a
// Service's operation sends.
export function removeState(target, key) {
  const { kind, value: current } = entryOf(['OutgoingContext', 'Service'], target, 'target');
  const parsedKey = stateKey(key);
  return kind === 'OutgoingContext' ? outgoingHandle(TC['OutgoingContext.remove'](current, parsedKey))
    : serviceHandle(TC['Service.remove'](current, parsedKey));
}

// Injecting and forwarding
// ========================

// An OutgoingContext: `context`, a LocalContext of this participant, with
// the state of `options.state`, an IncomingContext, an OutgoingContext or a
// Service, or with none.
export function outgoing(context, options) {
  const { state } = optionsOf(options);
  const local = unwrap('LocalContext', context, 'context');
  if (state === undefined || state === null) return outgoingHandle(TC['OutgoingContext.new'](local));
  const { kind, value } = entryOf(['IncomingContext', 'OutgoingContext', 'Service'], state, 'options.state');
  return outgoingHandle(TC['OutgoingContext.with_state'](local, stateOf(kind, value)));
}

// Write an OutgoingContext into the fields of a message to send: the old
// context fields go and the new ones come last. `dropped` lists the
// tracestate keys that truncation to the output budget removed.
export function inject(context, fields, options) {
  const { limits: given } = optionsOf(options);
  const injection = TC['Context.inject'](limitsOf(given), unwrap('OutgoingContext', context, 'outgoing'),
    carrier(fields));
  return Object.freeze({
    fields: fieldsOf(TC['Injection.carrier'](injection)),
    dropped: keysOf(TC['Injection.dropped'](injection)),
  });
}

// Write the pair that an IncomingContext was received with, unchanged, into
// the fields of a message to send, or say why it cannot be sent whole.
export function forward(context, fields, options) {
  const { limits: given } = optionsOf(options);
  const result = TC['Context.forward'](limitsOf(given), unwrap('IncomingContext', context, 'incoming'),
    carrier(fields));
  return result.$ === 'Done' ? Object.freeze({ ok: true, fields: fieldsOf(result.value) })
    : Object.freeze({ ok: false, error: TC['ForwardError.show'](result.error) });
}

// The fields of a message without its context fields.
export function clear(fields) {
  return fieldsOf(TC['Context.clear'](carrier(fields)));
}
