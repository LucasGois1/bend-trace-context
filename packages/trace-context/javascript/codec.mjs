import Codec from '../trace_context.bend';

// Keep proof-carrying values inside Bend. Foreign callers receive wire data only.
export function inspectTraceparent(text) {
  if (typeof text !== 'string') {
    return { ok: false, error: 'InvalidInputType' };
  }
  const parsed = Codec['TraceParentV00.parse'](text);
  if (parsed.$ === 'Fail') {
    return { ok: false, error: Codec['Error.show'](parsed.error) };
  }
  return {
    ok: true,
    traceparent: Codec['TraceParentV00.format'](parsed.value),
    sampled: Codec['TraceParentV00.is_sampled'](parsed.value),
  };
}
