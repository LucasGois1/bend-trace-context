// The facade and OpenTelemetry's W3C Trace Context propagator
// (@opentelemetry/core) read each other's fields: a context that OpenTelemetry
// injects is extracted by the package, and a child that the package sends is
// extracted by OpenTelemetry, with its tracestate. Both refuse what the
// standard refuses. OpenTelemetry is an independent implementation of the
// same fields, so neither side checks itself.
import assert from 'node:assert/strict';
import test from 'node:test';
import { ROOT_CONTEXT, trace, TraceFlags, defaultTextMapGetter, defaultTextMapSetter } from '@opentelemetry/api';
import { TraceState, W3CTraceContextPropagator } from '@opentelemetry/core';
import * as TC from '../../packages/trace-context/javascript/index.mjs';

const propagator = new W3CTraceContextPropagator();

function words(...list) {
  let read = 0;
  return { getRandomValues(array) { array[0] = list[read++]; return array; } };
}

// The fields that OpenTelemetry injects for a span context.
function injected(spanContext) {
  const carrier = {};
  propagator.inject(trace.setSpanContext(ROOT_CONTEXT, spanContext), carrier, defaultTextMapSetter);
  return carrier;
}

// The span context that OpenTelemetry extracts from fields, or undefined.
function extracted(fields) {
  const carrier = Object.fromEntries(fields.map(([name, value]) => [name.toLowerCase(), value]));
  return trace.getSpanContext(propagator.extract(ROOT_CONTEXT, carrier, defaultTextMapGetter));
}

test('the package continues a context that OpenTelemetry injects', () => {
  const carrier = injected({
    traceId: '4bf92f3577b34da6a3ce929d0e0e4736', spanId: '00f067aa0ba902b7', traceFlags: TraceFlags.SAMPLED,
    traceState: new TraceState('congo=t61rcWkgMzE,rojo=00f067aa0ba902b7'),
  });
  assert.deepEqual(Object.keys(carrier).sort(), ['traceparent', 'tracestate']);
  const extraction = TC.extract(Object.entries(carrier));
  assert.equal(extraction.show, 'TraceParentAccepted, StateAccepted');
  assert.equal(extraction.incoming.traceId, '4bf92f3577b34da6a3ce929d0e0e4736');
  assert.equal(extraction.incoming.spanId, '00f067aa0ba902b7');
  assert.equal(extraction.incoming.sampled, true);
  assert.equal(extraction.incoming.tracestate, 'congo=t61rcWkgMzE,rojo=00f067aa0ba902b7');
  const service = TC.continueOrStart(extraction, { crypto: words(0x53995c3f, 0x42cd8ad8) });
  assert.equal(service.outgoing.context.traceparent, '00-4bf92f3577b34da6a3ce929d0e0e4736-53995c3f42cd8ad8-01');
});

test('OpenTelemetry continues a child that the package sends, with its tracestate', () => {
  const service = TC.continueOrStart(TC.extract([
    ['traceparent', '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01'],
    ['tracestate', 'congo=t61rcWkgMzE'],
  ]), { crypto: words(1, 2) });
  const own = TC.setState(service, 'fw529a3039', 'cHJpbWFyeQ');
  const sent = TC.send(own, [['content-type', 'application/json']], { crypto: words(0x53995c3f, 0x42cd8ad8) });
  const context = extracted(sent.fields);
  assert.ok(context !== undefined, 'OpenTelemetry extracts the fields');
  assert.equal(context.traceId, '4bf92f3577b34da6a3ce929d0e0e4736');
  assert.equal(context.spanId, sent.operation.spanId);
  assert.equal(context.spanId, '53995c3f42cd8ad8');
  assert.equal(context.traceFlags & TraceFlags.SAMPLED, TraceFlags.SAMPLED);
  assert.equal(context.isRemote, true);
  assert.equal(context.traceState.serialize(), 'fw529a3039=cHJpbWFyeQ,congo=t61rcWkgMzE');
});

test('a new trace that the package starts is read by OpenTelemetry as unsampled', () => {
  const service = TC.continueOrStart(TC.extract([]), { crypto: words(1, 2, 3, 4, 5, 6) });
  const sent = TC.send(service, [], { crypto: words(7, 8) });
  const context = extracted(sent.fields);
  assert.equal(context.traceId, service.outgoing.context.traceId);
  assert.equal(context.spanId, sent.operation.spanId);
  assert.equal(context.traceFlags & TraceFlags.SAMPLED, 0);
});

test('both refuse a traceparent that the standard refuses', () => {
  for (const value of [
    '00-00000000000000000000000000000000-00f067aa0ba902b7-01',
    '00-4bf92f3577b34da6a3ce929d0e0e4736-0000000000000000-01',
    'ff-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01',
    '00-4BF92F3577B34DA6A3CE929D0E0E4736-00f067aa0ba902b7-01',
  ]) {
    assert.equal(extracted([['traceparent', value]]), undefined, value);
    assert.match(TC.extract([['traceparent', value]]).show, /^TraceParentRejected /, value);
  }
});
