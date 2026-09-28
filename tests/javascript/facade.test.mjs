import assert from 'node:assert/strict';
import test from 'node:test';
import { webcrypto } from 'node:crypto';
import * as TC from '../../packages/trace-context/javascript/index.mjs';
import Package from '../../packages/trace-context/trace_context.bend';
import Generate from '../../packages/trace-context/generation.bend';

const TRACEPARENT = '00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01';

// A deterministic source with WebCrypto's getRandomValues interface: each
// call returns the next word of the list and counts the words read.
function words(...list) {
  const source = {
    reads: 0,
    getRandomValues(array) {
      if (source.reads >= list.length) throw new Error('the test source ran out of words');
      array[0] = list[source.reads];
      source.reads += 1;
      return array;
    },
  };
  return source;
}

// Sources that call actual WebCrypto with requests it refuses: a buffer over
// its 65536-byte quota, and a float array. They exercise the translation of
// real host exceptions, not a spontaneous failure of a one-word request.
function refusing(kind) {
  const source = {
    observed: [],
    getRandomValues() {
      try {
        return kind === 'quota' ? webcrypto.getRandomValues(new Uint8Array(65537))
          : webcrypto.getRandomValues(new Float32Array(1));
      } catch (error) {
        source.observed.push(error.name);
        throw error;
      }
    },
  };
  return source;
}

function zeros(count) {
  return words(...Array(count).fill(0));
}

test('a traced request is continued and each request sent gets a child of its own', () => {
  const extraction = TC.extract([
    ['Host', 'api.example'],
    ['traceparent', TRACEPARENT],
    ['tracestate', 'congo=t61rcWkgMzE'],
    ['TraceState', 'rojo=00f067aa0ba902b7'],
  ]);
  assert.equal(extraction.show, 'TraceParentAccepted, StateAccepted');
  assert.equal(extraction.incoming.traceId, '0af7651916cd43dd8448eb211c80319c');
  assert.equal(extraction.incoming.spanId, 'b7ad6b7169203331');
  assert.equal(extraction.incoming.sampled, true);
  assert.equal(extraction.incoming.tracestate, 'congo=t61rcWkgMzE,rojo=00f067aa0ba902b7');
  assert.deepEqual(extraction.incoming.received, {
    traceparent: TRACEPARENT, tracestate: ['congo=t61rcWkgMzE', 'rojo=00f067aa0ba902b7'],
  });

  const source = words(0x00f067aa, 0x0ba902b7, 0x53995c3f, 0x42cd8ad8, 0xa3ce929d, 0x0e0e4736);
  const service = TC.continueOrStart(extraction, { crypto: source });
  assert.equal(service.show, 'Continued');
  assert.equal(service.origin, 'Continued');
  assert.equal(service.error, null);
  assert.equal(service.outgoing.context.traceparent, '00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-01');
  assert.equal(source.reads, 2);

  const first = TC.send(service, [['Content-Type', 'application/json'], ['TRACEPARENT', 'stale']], { crypto: source });
  assert.equal(first.show, 'Fresh');
  assert.equal(first.operation.spanId, '53995c3f42cd8ad8');
  assert.deepEqual(first.fields, [
    ['Content-Type', 'application/json'],
    ['traceparent', '00-0af7651916cd43dd8448eb211c80319c-53995c3f42cd8ad8-01'],
    ['tracestate', 'congo=t61rcWkgMzE,rojo=00f067aa0ba902b7'],
  ]);
  const second = TC.send(service, [['Content-Type', 'application/json']], { crypto: source });
  assert.equal(second.operation.traceparent, '00-0af7651916cd43dd8448eb211c80319c-a3ce929d0e0e4736-01');
  assert.equal(source.reads, 6);
});

test('the facade also exports the codec adapter', () => {
  assert.deepEqual(TC.inspectTraceparent(TRACEPARENT), { ok: true, traceparent: TRACEPARENT, sampled: true });
  assert.deepEqual(TC.inspectTraceparent(new String(TRACEPARENT)), { ok: false, error: 'InvalidInputType' });
});

test('objects that only look like handles cannot stand for package values', () => {
  const extraction = TC.extract([['traceparent', TRACEPARENT]]);
  const service = TC.continueOrStart(extraction, { crypto: words(1, 2) });
  assert.ok(Object.isFrozen(extraction) && Object.isFrozen(service) && Object.isFrozen(service.outgoing));
  const forgedExtraction = { ...extraction };
  const forgedService = Object.freeze({ ...service });
  const tagged = { $: 'Operating', origin: { $: 'Continued' }, outgoing: {}, received: { $: 'None' } };
  for (const forged of [forgedExtraction, Object.create(extraction), tagged, null, undefined, 'Continued', 1]) {
    assert.throws(() => TC.continueOrStart(forged), TypeError);
  }
  for (const forged of [forgedService, Object.create(service), tagged, extraction, service.outgoing]) {
    assert.throws(() => TC.send(forged, []), TypeError);
  }
  assert.throws(() => TC.extract([], { base: { ...extraction.incoming } }), TypeError);
  assert.throws(() => TC.extract([], { limits: { traceparentInput: 55 } }), TypeError);
});

test('malformed fields and options are refused before any package code runs', () => {
  const service = TC.continueOrStart(TC.extract([]), { crypto: words(1, 2, 3, 4, 5, 6) });
  for (const fields of [undefined, null, 'traceparent', {}, [['traceparent']], [['a', 'b', 'c']],
    [['traceparent', 1]], [[new String('traceparent'), TRACEPARENT]], [{ 0: 'a', 1: 'b', length: 2 }]]) {
    assert.throws(() => TC.extract(fields), TypeError);
    assert.throws(() => TC.send(service, fields), TypeError);
  }
  assert.throws(() => TC.extract([], 'strict'), TypeError);
  assert.throws(() => TC.continueOrStart(TC.extract([]), { policy: 1 }), TypeError);
  assert.throws(() => TC.continueOrStart(TC.extract([]), { policy: 'Strict' }), RangeError);
  assert.throws(() => TC.continueOrStart(TC.extract([]), { reception: 'resume' }), RangeError);
  assert.throws(() => TC.send(service, [], { sampling: true }), TypeError);
  assert.throws(() => TC.send(service, [], { sampling: 'toString' }), RangeError);
});

test('real WebCrypto exceptions leave a lenient service untraced, forwarding the received pair', () => {
  for (const [kind, name] of [['quota', 'QuotaExceededError'], ['type', 'TypeMismatchError']]) {
    const source = refusing(kind);
    const extraction = TC.extract([['traceparent', TRACEPARENT], ['tracestate', 'congo=t61rcWkgMzE']]);
    const service = TC.continueOrStart(extraction, { crypto: source });
    assert.equal(service.show, 'Untraced SourceFailure 2 source-failure');
    assert.equal(service.origin, null);
    assert.equal(service.outgoing, null);
    assert.equal(service.error, 'SourceFailure 2 source-failure');
    const sent = TC.send(service, [['Accept', 'application/json']], { crypto: source });
    assert.equal(sent.show, 'Forwarded after SourceFailure 2 source-failure');
    assert.equal(sent.operation, null);
    assert.equal(sent.error, 'SourceFailure 2 source-failure');
    assert.deepEqual(sent.fields, [
      ['Accept', 'application/json'], ['traceparent', TRACEPARENT], ['tracestate', 'congo=t61rcWkgMzE'],
    ]);
    // The service's generation stopped at its first word; the send read none.
    assert.deepEqual(source.observed, [name]);
  }
});

test('a strict service or send refuses with a GenerationError instead of carrying on', () => {
  const extraction = TC.extract([['traceparent', TRACEPARENT]]);
  assert.throws(() => TC.continueOrStart(extraction, { policy: 'strict', crypto: refusing('quota') }),
    (error) => error instanceof TC.GenerationError && error.name === 'GenerationError'
      && error.reason === 'SourceFailure 2 source-failure');
  assert.throws(() => TC.continueOrStart(extraction, { policy: 'strict', crypto: null }),
    { name: 'GenerationError', reason: 'SourceFailure 1 unavailable' });
  const service = TC.continueOrStart(extraction, { crypto: words(1, 2) });
  const exhausted = zeros(16);
  assert.throws(() => TC.send(service, [], { policy: 'strict', crypto: exhausted }), { reason: 'ExhaustedSpanId' });
  assert.equal(exhausted.reads, 16);
  assert.equal(TC.send(service, [], { crypto: zeros(16) }).show, 'Forwarded after ExhaustedSpanId');
  const strict = TC.send(service, [], { policy: 'strict', crypto: words(3, 4) });
  assert.equal(strict.show, 'Fresh');
  const started = TC.continueOrStart(TC.extract([]), { crypto: words(1, 2, 3, 4, 5, 6) });
  assert.deepEqual(TC.send(started, [['traceparent', TRACEPARENT]], { crypto: null }).fields, []);
  assert.equal(TC.send(started, [], { crypto: null }).show, 'NoContext after SourceFailure 1 unavailable, NothingKept');
});

test('a request without context starts a trace, and a trust boundary restarts one', () => {
  const started = TC.continueOrStart(TC.extract([['Host', 'api.example']]),
    { crypto: words(0x4bf92f35, 0x77b34da6, 0xa3ce929d, 0x0e0e4736, 0x00f067aa, 0x0ba902b7) });
  assert.equal(started.show, 'Started');
  assert.equal(started.outgoing.context.traceparent, '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-02');
  assert.equal(started.outgoing.tracestate, '');
  const extraction = TC.extract([['traceparent', TRACEPARENT], ['tracestate', 'congo=t61rcWkgMzE']]);
  // The first trace ID candidate repeats the received one and is drawn again.
  const source = words(0x0af76519, 0x16cd43dd, 0x8448eb21, 0x1c80319c,
    0x4bf92f35, 0x77b34da6, 0xa3ce929d, 0x0e0e4736, 0x00f067aa, 0x0ba902b7);
  const restarted = TC.continueOrStart(extraction, { reception: 'restart', sampling: 'sampled', crypto: source });
  assert.equal(restarted.show, 'Restarted');
  assert.equal(restarted.outgoing.context.traceparent, '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-03');
  assert.equal(restarted.outgoing.tracestate, '');
  assert.equal(source.reads, 10);
  const unsampled = TC.continueOrStart(extraction, { sampling: 'unsampled', crypto: words(1, 2) });
  assert.equal(unsampled.outgoing.context.traceparent, '00-0af7651916cd43dd8448eb211c80319c-0000000100000002-00');
  assert.equal(unsampled.outgoing.tracestate, 'congo=t61rcWkgMzE');
});

test('an extraction without a usable traceparent continues the base it is given', () => {
  const previous = TC.extract([['traceparent', TRACEPARENT], ['tracestate', 'congo=t61rcWkgMzE']]).incoming;
  const extraction = TC.extract([['traceparent', '00-00000000000000000000000000000000-b7ad6b7169203331-01'],
    ['tracestate', 'rojo=00f067aa0ba902b7']], { base: previous });
  assert.equal(extraction.show, 'TraceParentRejected InvalidTraceParent ZeroTraceId, StateIgnored');
  assert.equal(extraction.parent, 'TraceParentRejected InvalidTraceParent ZeroTraceId');
  assert.equal(extraction.state, 'StateIgnored');
  assert.equal(extraction.incoming, null);
  assert.equal(extraction.context.spanId, 'b7ad6b7169203331');
  const service = TC.continueOrStart(extraction, { crypto: words(0x53995c3f, 0x42cd8ad8) });
  assert.equal(service.outgoing.context.traceparent, '00-0af7651916cd43dd8448eb211c80319c-53995c3f42cd8ad8-01');
  assert.equal(service.outgoing.tracestate, 'congo=t61rcWkgMzE');
  const own = TC.extract([], { base: service.outgoing });
  assert.equal(own.context.context.traceparent, service.outgoing.context.traceparent);
  assert.equal(TC.extract([['traceparent', 'a'], ['TraceParent', 'b']]).show,
    'TraceParentRejected RepeatedTraceParent, StateAbsent');
});

test('roots, children and restarts are generated from the source words by the package', () => {
  const root = TC.root({ crypto: words(0x4bf92f35, 0x77b34da6, 0xa3ce929d, 0x0e0e4736, 0x00f067aa, 0x0ba902b7) });
  assert.equal(root.traceparent, '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-02');
  assert.equal(root.traceId, '4bf92f3577b34da6a3ce929d0e0e4736');
  assert.equal(root.spanId, '00f067aa0ba902b7');
  assert.equal(root.random, true);
  assert.equal(root.sampled, false);
  const incoming = TC.extract([['traceparent', TRACEPARENT]]).incoming;
  assert.equal(incoming.random, false);
  // A candidate equal to the parent's span ID is drawn again.
  const retried = words(0xb7ad6b71, 0x69203331, 0x53995c3f, 0x42cd8ad8);
  const child = TC.child(incoming, { crypto: retried });
  assert.equal(child.traceparent, '00-0af7651916cd43dd8448eb211c80319c-53995c3f42cd8ad8-01');
  assert.equal(retried.reads, 4);
  assert.equal(TC.child(child, { sampling: 'unsampled', crypto: words(5, 6) }).traceparent,
    '00-0af7651916cd43dd8448eb211c80319c-0000000500000006-00');
  const restart = TC.restart(incoming, { crypto: words(0x4bf92f35, 0x77b34da6, 0xa3ce929d, 0x0e0e4736, 7, 8) });
  assert.equal(restart.traceparent, '00-4bf92f3577b34da6a3ce929d0e0e4736-0000000700000008-02');
  const exhausted = zeros(40);
  assert.throws(() => TC.root({ crypto: exhausted }), { name: 'GenerationError', reason: 'ExhaustedTraceId' });
  assert.equal(exhausted.reads, 32);
  assert.throws(() => TC.child(incoming, { crypto: zeros(16) }), { reason: 'ExhaustedSpanId' });
  assert.throws(() => TC.child(TC.extract([]), {}), TypeError);
  assert.throws(() => TC.restart(child), TypeError);
});

test('a root reads at most 48 words and a child 16: seven rejected candidates of each identifier, then the eighth', () => {
  const root = words(...Array(28).fill(0), 0x4bf92f35, 0x77b34da6, 0xa3ce929d, 0x0e0e4736,
    ...Array(14).fill(0), 0x00f067aa, 0x0ba902b7);
  assert.equal(TC.root({ crypto: root }).traceparent, '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-02');
  assert.equal(root.reads, 48);
  const incoming = TC.extract([['traceparent', TRACEPARENT]]).incoming;
  const child = words(...Array(14).fill(0), 0x53995c3f, 0x42cd8ad8);
  assert.equal(TC.child(incoming, { crypto: child }).spanId, '53995c3f42cd8ad8');
  assert.equal(child.reads, 16);
});

test('every flag byte of a received traceparent reaches the facade as the package reads it', () => {
  for (let byte = 0; byte < 256; byte += 1) {
    const flags = byte.toString(16).padStart(2, '0');
    const received = `00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-${flags}`;
    const { incoming } = TC.extract([['traceparent', received]]);
    assert.equal(incoming.sampled, (byte & 1) === 1, flags);
    assert.equal(incoming.random, (byte & 2) === 2, flags);
    // A child emits only the known flags, and forwarding keeps every bit.
    assert.equal(TC.child(incoming, { crypto: words(0x53995c3f, 0x42cd8ad8) }).traceparent,
      `00-0af7651916cd43dd8448eb211c80319c-53995c3f42cd8ad8-0${byte & 3}`, flags);
    assert.deepEqual(TC.forward(incoming, []).fields, [['traceparent', received]], flags);
  }
});

test('a tracestate of 32 members is read, and a 33rd member discards the whole state', () => {
  const members = Array.from({ length: 33 }, (_, index) => `k${index}=v${index}`);
  const full = TC.extract([['traceparent', TRACEPARENT], ['tracestate', members.slice(0, 32).join(',')]]);
  assert.equal(full.show, 'TraceParentAccepted, StateAccepted');
  assert.equal(full.incoming.tracestate, members.slice(0, 32).join(','));
  assert.equal(TC.extract([['traceparent', TRACEPARENT], ['tracestate', members.join(',')]]).show,
    'TraceParentAccepted, StateDiscarded TooManyMembers');
  // Members are counted before duplicates are dropped.
  assert.equal(TC.extract([['traceparent', TRACEPARENT], ['tracestate', [...members.slice(0, 32), 'k0=again'].join(',')]]).show,
    'TraceParentAccepted, StateDiscarded TooManyMembers');
});

test('the traceparent budget counts UTF-8 octets, not JavaScript characters', () => {
  const limits = TC.limits({ traceparentInput: 60 });
  // A later version with an unknown field: 56 characters before it.
  const prefix = 'cc-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01-';
  assert.equal(TC.extract([['traceparent', `${prefix}ab\u00e9`]], { limits }).parent, 'TraceParentAccepted');
  assert.equal(TC.extract([['traceparent', `${prefix}\u00e9\u00e9`]], { limits }).parent, 'TraceParentAccepted');
  assert.equal(TC.extract([['traceparent', `${prefix}\u20acx`]], { limits }).parent, 'TraceParentAccepted');
  assert.equal(TC.extract([['traceparent', `${prefix}\u00e9\u00e9x`]], { limits }).parent,
    'TraceParentRejected TraceParentTooLarge');
  assert.equal(TC.extract([['traceparent', `${prefix}\u20acxy`]], { limits }).parent,
    'TraceParentRejected TraceParentTooLarge');
});

test('limits are checked by the package and bound what extraction reads', () => {
  assert.deepEqual({ ...TC.limits() }, { traceparentInput: 32768, tracestateInput: 32768, tracestateOutput: 512 });
  assert.deepEqual({ ...TC.limits({ tracestateOutput: 1024 }) },
    { traceparentInput: 32768, tracestateInput: 32768, tracestateOutput: 1024 });
  assert.throws(() => TC.limits({ traceparentInput: 54 }), { name: 'RangeError', message: 'TraceParentInputTooSmall' });
  assert.throws(() => TC.limits({ tracestateOutput: 511 }), { name: 'RangeError', message: 'TraceStateOutputTooSmall' });
  assert.throws(() => TC.limits({ tracestateInput: 600, tracestateOutput: 1024 }),
    { name: 'RangeError', message: 'TraceStateInputTooSmall' });
  for (const value of [-1, 1.5, NaN, Infinity, 2 ** 53]) {
    assert.throws(() => TC.limits({ traceparentInput: value }), RangeError);
  }
  for (const value of ['55', 55n, null, new Number(55)]) {
    assert.throws(() => TC.limits({ traceparentInput: value }), TypeError);
  }
  const small = TC.limits({ tracestateInput: 512 });
  // 514 octets: over the 512 of `small`, within the default 32768.
  const state = `a=${'x'.repeat(256)},b=${'y'.repeat(253)}`;
  assert.equal(TC.extract([['traceparent', TRACEPARENT], ['tracestate', state]], { limits: small }).show,
    'TraceParentAccepted, StateDiscarded StateTooLarge');
  assert.equal(TC.extract([['traceparent', TRACEPARENT], ['tracestate', state]]).show,
    'TraceParentAccepted, StateAccepted');
});

test('the state a service sends is edited through validated keys and values', () => {
  const extraction = TC.extract([['traceparent', TRACEPARENT], ['tracestate', 'congo=t61rcWkgMzE,rojo=00f067aa0ba902b7']]);
  assert.equal(TC.getState(extraction.incoming, 'rojo'), '00f067aa0ba902b7');
  assert.equal(TC.getState(extraction.incoming, 'absent'), null);
  let service = TC.continueOrStart(extraction, { crypto: words(1, 2) });
  service = TC.setState(service, 'fw529a3039', 'cHJpbWFyeQ');
  assert.equal(service.outgoing.tracestate, 'fw529a3039=cHJpbWFyeQ,congo=t61rcWkgMzE,rojo=00f067aa0ba902b7');
  service = TC.removeState(service, 'rojo');
  assert.equal(service.outgoing.tracestate, 'fw529a3039=cHJpbWFyeQ,congo=t61rcWkgMzE');
  assert.equal(TC.getState(service, 'congo'), 't61rcWkgMzE');
  assert.equal(TC.getState(service.outgoing, 'fw529a3039'), 'cHJpbWFyeQ');
  assert.equal(TC.setState(service.outgoing, 'congo', 'updated').tracestate,
    'congo=updated,fw529a3039=cHJpbWFyeQ');
  assert.throws(() => TC.setState(service, 'Congo', 'x'), { name: 'RangeError', message: 'InvalidKey' });
  assert.throws(() => TC.setState(service, 'congo', 'a,b'), { name: 'RangeError', message: 'InvalidValue' });
  assert.throws(() => TC.setState(service, 'congo', 'trailing '), { name: 'RangeError', message: 'InvalidValue' });
  assert.throws(() => TC.getState(service, ''), { name: 'RangeError', message: 'InvalidKey' });
  assert.throws(() => TC.setState(service, 1, 'x'), TypeError);
  assert.throws(() => TC.setState(service, 'congo', new String('x')), TypeError);
  assert.throws(() => TC.setState(extraction.incoming, 'congo', 'x'), TypeError);
  assert.throws(() => TC.removeState(extraction, 'congo'), TypeError);
  const untraced = TC.continueOrStart(extraction, { crypto: null });
  assert.equal(TC.setState(untraced, 'congo', 'x').show, 'Untraced SourceFailure 1 unavailable');
  assert.equal(TC.getState(untraced, 'congo'), null);
});

test('contexts are injected, received pairs forwarded unchanged and context fields cleared', () => {
  const later = 'cc-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-ff-future';
  const extraction = TC.extract([['traceparent', later], ['tracestate', 'congo=t61rcWkgMzE'],
    ['tracestate', 'rojo=00f067aa0ba902b7']]);
  assert.deepEqual(TC.forward(extraction.incoming, [['Host', 'billing.internal'], ['Traceparent', 'stale']]), {
    ok: true,
    fields: [['Host', 'billing.internal'], ['traceparent', later], ['tracestate', 'congo=t61rcWkgMzE,rojo=00f067aa0ba902b7']],
  });
  const child = TC.child(extraction.incoming, { crypto: words(0x53995c3f, 0x42cd8ad8) });
  assert.deepEqual(TC.inject(TC.outgoing(child, { state: extraction.incoming }), [['Host', 'inventory.internal']]), {
    fields: [['Host', 'inventory.internal'], ['traceparent', '00-0af7651916cd43dd8448eb211c80319c-53995c3f42cd8ad8-03'],
      ['tracestate', 'congo=t61rcWkgMzE,rojo=00f067aa0ba902b7']],
    dropped: [],
  });
  assert.deepEqual(TC.inject(TC.outgoing(child), [['tracestate', 'stale']]).fields,
    [['traceparent', '00-0af7651916cd43dd8448eb211c80319c-53995c3f42cd8ad8-03']]);
  // 518 octets: over the default output budget of 512; dropping b fits it.
  const large = TC.extract([['traceparent', TRACEPARENT],
    ['tracestate', `a=${'x'.repeat(250)},b=${'y'.repeat(250)},c=${'z'.repeat(10)}`]]);
  assert.deepEqual(TC.forward(large.incoming, []), { ok: false, error: 'ForwardTooLarge' });
  // Forwarding with a traceparent budget smaller than extraction's.
  assert.deepEqual(TC.forward(extraction.incoming, [], { limits: TC.limits({ traceparentInput: 55 }) }),
    { ok: false, error: 'InvalidForwardParent TraceParentTooLarge' });
  const truncated = TC.inject(TC.outgoing(child, { state: large.incoming }), []);
  assert.deepEqual(truncated.dropped, ['b']);
  const discarded = TC.extract([['traceparent', TRACEPARENT], ['tracestate', 'invalid']]);
  assert.deepEqual(TC.forward(discarded.incoming, []), { ok: false, error: 'NothingToForward' });
  assert.deepEqual(TC.clear([['Host', 'metrics.internal'], ['TraceParent', TRACEPARENT], ['TRACESTATE', 'a=b']]),
    [['Host', 'metrics.internal']]);
  const service = TC.setState(TC.continueOrStart(extraction, { crypto: words(1, 2) }), 'fw529a3039', 'cHJpbWFyeQ');
  assert.equal(TC.outgoing(child, { state: service }).tracestate,
    'fw529a3039=cHJpbWFyeQ,congo=t61rcWkgMzE,rojo=00f067aa0ba902b7');
  assert.throws(() => TC.inject(child, []), TypeError);
  assert.throws(() => TC.forward(child, []), TypeError);
  assert.throws(() => TC.outgoing(child, { state: child }), TypeError);
});

test('operations with supplied identifiers are checked by the package', () => {
  const traceId = '4bf92f3577b34da6a3ce929d0e0e4736';
  assert.equal(TC.rootFromIds(traceId, '00f067aa0ba902b7').traceparent, `00-${traceId}-00f067aa0ba902b7-00`);
  assert.equal(TC.rootFromIds(traceId, '00f067aa0ba902b7', { random: true }).traceparent,
    `00-${traceId}-00f067aa0ba902b7-02`);
  const existing = TC.fromIds('0af7651916cd43dd8448eb211c80319c', 'b7ad6b7169203331', { sampled: true });
  assert.equal(existing.traceparent, TRACEPARENT);
  assert.equal(existing.random, false);
  const { incoming } = TC.extract([['traceparent', TRACEPARENT]]);
  assert.equal(TC.childFromId(incoming, '53995c3f42cd8ad8').traceparent,
    '00-0af7651916cd43dd8448eb211c80319c-53995c3f42cd8ad8-01');
  assert.equal(TC.childFromId(existing, '53995c3f42cd8ad8', { sampling: 'unsampled' }).traceparent,
    '00-0af7651916cd43dd8448eb211c80319c-53995c3f42cd8ad8-00');
  assert.throws(() => TC.childFromId(incoming, 'b7ad6b7169203331'), { name: 'RangeError', message: 'ReusedSpanId' });
  assert.equal(TC.restartFromIds(incoming, traceId, '00f067aa0ba902b7').traceparent,
    `00-${traceId}-00f067aa0ba902b7-00`);
  // The received trace ID is refused even when only the randomness assertion differs.
  assert.throws(() => TC.restartFromIds(incoming, '0af7651916cd43dd8448eb211c80319c', '00f067aa0ba902b7',
    { random: true }), { name: 'RangeError', message: 'ReusedTraceId' });
  assert.throws(() => TC.fromIds('00000000000000000000000000000000', '00f067aa0ba902b7'),
    { name: 'RangeError', message: 'ZeroTraceId' });
  assert.throws(() => TC.rootFromIds(traceId, '0000000000000000'), { name: 'RangeError', message: 'ZeroSpanId' });
  assert.throws(() => TC.rootFromIds('4BF92F3577B34DA6A3CE929D0E0E4736', '00f067aa0ba902b7'),
    { name: 'RangeError', message: 'InvalidHex at 1' });
  assert.throws(() => TC.rootFromIds(traceId, '00f067aa0ba902b7 '), { name: 'RangeError', message: 'TrailingInput' });
  for (const [trace, span, options] of [[1, '00f067aa0ba902b7'], [traceId, new String('00f067aa0ba902b7')],
    [traceId, '00f067aa0ba902b7', { sampled: 'yes' }], [traceId, '00f067aa0ba902b7', { random: 1 }]]) {
    assert.throws(() => TC.fromIds(trace, span, options), TypeError);
  }
  assert.throws(() => TC.childFromId({ ...incoming }, '53995c3f42cd8ad8'), TypeError);
  assert.throws(() => TC.restartFromIds(existing, traceId, '00f067aa0ba902b7'), TypeError);
  assert.deepEqual(TC.inject(TC.outgoing(existing), []).fields, [['traceparent', TRACEPARENT]]);
});

test('the crypto option takes an object with getRandomValues, or null', () => {
  const service = TC.continueOrStart(TC.extract([]), { crypto: words(1, 2, 3, 4, 5, 6) });
  for (const crypto of [webcrypto.subtle, {}, 'webcrypto', 1, true]) {
    assert.throws(() => TC.root({ crypto }), TypeError);
    assert.throws(() => TC.continueOrStart(TC.extract([]), { crypto }), TypeError);
    assert.throws(() => TC.send(service, [], { crypto }), TypeError);
  }
  assert.match(TC.root({ crypto: webcrypto }).traceparent, /^00-[0-9a-f]{32}-[0-9a-f]{16}-02$/);
  // A getter that fails still reaches the WebCrypto adapter, as a source failure.
  const failing = { get getRandomValues() { throw new Error('controlled getter failure'); } };
  assert.throws(() => TC.root({ crypto: failing }), { name: 'GenerationError', reason: 'SourceFailure 2 source-failure' });
  assert.throws(() => TC.root({ crypto: null }), { name: 'GenerationError', reason: 'SourceFailure 1 unavailable' });
});

test('fields are read once, so that what the facade checks is what reaches the package', () => {
  let reads = 0;
  const fields = [];
  Object.defineProperty(fields, 0, {
    enumerable: true,
    get() { reads += 1; return reads === 1 ? ['traceparent', TRACEPARENT] : ['traceparent', 1]; },
  });
  assert.equal(TC.extract(fields).show, 'TraceParentAccepted, StateAbsent');
  let valueReads = 0;
  const pair = ['traceparent'];
  Object.defineProperty(pair, 1, {
    enumerable: true,
    get() { valueReads += 1; return valueReads === 1 ? TRACEPARENT : 42; },
  });
  assert.equal(TC.extract([pair]).show, 'TraceParentAccepted, StateAbsent');
  assert.equal(reads, 1);
  assert.equal(valueReads, 1);
});

test('the loader runs no IO operation and exports no template, so the facade drives the pure form', () => {
  // Definitions that take a template are not exported at all.
  for (const name of ['Context.root_with', 'Context.child_with', 'Context.restart_with', 'Context.continue_or_start_with',
    'Context.send_with', 'Generation.run_with']) {
    assert.equal(Package[name], undefined, name);
  }
  // An IO operation without parameters is not exported either, and one with
  // parameters comes back as an unrun IO action: it reads no word.
  assert.equal(Generate['Context.root'], undefined);
  const descriptor = Object.getOwnPropertyDescriptor(globalThis, 'crypto');
  let reads = 0;
  try {
    Object.defineProperty(globalThis, 'crypto', {
      configurable: true,
      value: { getRandomValues(array) { reads += 1; array[0] = 7; return array; } },
    });
    const action = Generate['Context.continue_or_start'](Package['Context.extract'](Package['Limits.default'](),
      { $: 'Nil' }, { $: 'None' }), { $: 'Continue' }, { $: 'InheritSampled' }, { $: 'Lenient' });
    assert.equal(typeof action, 'function');
    assert.equal(reads, 0);
  } finally {
    Object.defineProperty(globalThis, 'crypto', descriptor);
  }
  for (const name of ['Generation.root', 'Generation.needs', 'Generation.feed', 'Generation.result', 'ServicePlan.new',
    'ServicePlan.generation', 'ServicePlan.service', 'SendPlan.new', 'SendPlan.generation', 'SendPlan.sent']) {
    assert.equal(typeof Package[name], 'function', name);
  }
});

test('a message with ten thousand fields needs no deep stack', () => {
  const fields = Array.from({ length: 10000 }, (_, index) => ['x-field', String(index)]);
  const extraction = TC.extract([...fields, ['traceparent', TRACEPARENT]]);
  assert.equal(extraction.show, 'TraceParentAccepted, StateAbsent');
  const service = TC.continueOrStart(extraction, { crypto: words(1, 2) });
  const sent = TC.send(service, fields, { crypto: words(3, 4) });
  assert.equal(sent.fields.length, 10001);
  assert.deepEqual(sent.fields[9999], ['x-field', '9999']);
});

test('the default source is the host WebCrypto, and its absence is a structured failure', () => {
  assert.match(TC.root().traceparent, /^00-[0-9a-f]{32}-[0-9a-f]{16}-02$/);
  assert.equal(TC.send(TC.continueOrStart(TC.extract([])), []).show, 'Fresh');
  const descriptor = Object.getOwnPropertyDescriptor(globalThis, 'crypto');
  try {
    delete globalThis.crypto;
    assert.throws(() => TC.root(), { name: 'GenerationError', reason: 'SourceFailure 1 unavailable' });
    assert.equal(TC.continueOrStart(TC.extract([])).show, 'Untraced SourceFailure 1 unavailable');
  } finally {
    Object.defineProperty(globalThis, 'crypto', descriptor);
  }
});

test('the facade reaches no system binding, so it needs no Bun FFI', () => {
  const descriptor = Object.getOwnPropertyDescriptor(globalThis, 'BEND_SYS');
  let reached = 0;
  Object.defineProperty(globalThis, 'BEND_SYS', {
    configurable: true,
    get() { reached += 1; throw new Error('the facade must not reach a system binding'); },
  });
  try {
    const extraction = TC.extract([['traceparent', TRACEPARENT], ['tracestate', 'congo=t61rcWkgMzE']]);
    const service = TC.setState(TC.continueOrStart(extraction), 'fw529a3039', 'cHJpbWFyeQ');
    assert.equal(TC.send(service, [['Accept', '*/*']]).show, 'Fresh');
    assert.equal(TC.forward(extraction.incoming, []).ok, true);
    assert.equal(TC.inject(service.outgoing, []).fields.length, 2);
    assert.match(TC.restart(extraction.incoming).traceparent, /-02$/);
    assert.equal(reached, 0);
    assert.equal(typeof globalThis.Bun, 'undefined');
    assert.equal(process.versions.bun, undefined);
  } finally {
    if (descriptor === undefined) delete globalThis.BEND_SYS;
    else Object.defineProperty(globalThis, 'BEND_SYS', descriptor);
  }
});
