// The facade's handles: frozen objects that only the facade creates, each
// standing for a package value kept in this module-private WeakMap. The
// facade's modules share this one registry, so that an object that merely
// looks like a handle is refused wherever a handle is expected.
const handles = new WeakMap();

// A new handle of `kind` for the package value `value`, with `properties`.
export function handle(kind, value, properties) {
  const object = { ...properties };
  Object.defineProperty(object, Symbol.toStringTag, { value: kind });
  handles.set(Object.freeze(object), { kind, value });
  return object;
}

// The kind and package value of a handle of one of `kinds`.
export function entryOf(kinds, object, name) {
  const entry = typeof object === 'object' && object !== null ? handles.get(object) : undefined;
  if (entry === undefined || !kinds.includes(entry.kind)) {
    throw new TypeError(`${name} must be ${kinds.join(' or ')} returned by bend-trace-context`);
  }
  return entry;
}

// The package value of a handle of `kind`.
export function unwrap(kind, object, name) {
  return entryOf([kind], object, name).value;
}
