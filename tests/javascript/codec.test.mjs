import assert from 'node:assert/strict';
import test from 'node:test';
import { inspectTraceparent } from '../../packages/trace-context/javascript/codec.mjs';

test('a Node application imports the real Bend codec and inspects a W3C value', () => {
  const wire = '00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01';
  assert.deepEqual(inspectTraceparent(wire), {
    ok: true, traceparent: wire, sampled: true,
  });
});

test('foreign objects cannot forge proof-carrying contexts or coerce into wire text', () => {
  const forged = { $: 'TraceParentV00', trace_id: { evidence: null } };
  const coercion = { toString() { throw new Error('must not coerce'); } };
  for (const value of [null, undefined, 123, 1n, false, [], forged, coercion,
    new String('00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01')]) {
    assert.deepEqual(inspectTraceparent(value), { ok: false, error: 'InvalidInputType' });
  }
});

test('malformed wire text is rejected by Bend with its public error names', () => {
  const prefix = '00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-';
  for (const [wire, error] of [
    ['', 'UnexpectedEnd at 0'],
    ['00-00000000000000000000000000000000-b7ad6b7169203331-01', 'ZeroTraceId'],
    [prefix + '0A', 'InvalidHex at 54'],
    [prefix + '０1', 'InvalidHex at 53'],
    [prefix + '\ud8001', 'InvalidHex at 53'],
    [prefix + '01suffix', 'TrailingInput'],
  ]) {
    assert.deepEqual(inspectTraceparent(wire), { ok: false, error });
  }
});

test('inspection preserves reserved flag bits and reports sampled independently', () => {
  const wire = '00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-fe';
  assert.deepEqual(inspectTraceparent(wire), { ok: true, traceparent: wire, sampled: false });
});
