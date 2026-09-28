// The options that the facade's operations take, checked before any package
// code runs.
import TC from '../trace_context.bend';
import { unwrap } from './handles.mjs';

export function optionsOf(options) {
  if (options === undefined) return {};
  if (typeof options !== 'object' || options === null) throw new TypeError('options must be an object');
  return options;
}

// The package value that an option names, or the fallback's.
export function choice(value, fallback, choices, name) {
  if (value === undefined) return choices[fallback];
  if (typeof value !== 'string') throw new TypeError(`${name} must be a string`);
  if (!Object.hasOwn(choices, value)) {
    throw new RangeError(`${name} must be ${Object.keys(choices).map((option) => `'${option}'`).join(' or ')}`);
  }
  return choices[value];
}

export function flag(value, name) {
  if (value === undefined) return false;
  if (typeof value !== 'boolean') throw new TypeError(`${name} must be a boolean`);
  return value;
}

export const RECEPTIONS = { continue: { $: 'Continue' }, restart: { $: 'Restart' } };
export const SAMPLINGS = {
  inherit: { $: 'InheritSampled' },
  sampled: { $: 'SetSampled', sampled: true },
  unsampled: { $: 'SetSampled', sampled: false },
};
export const STRICT = { lenient: false, strict: true };
export const DEFAULT_LIMITS = TC['Limits.default']();

export function limitsOf(value) {
  return value === undefined ? DEFAULT_LIMITS : unwrap('Limits', value, 'options.limits');
}

// The `crypto` option: undefined for the host's globalThis.crypto, null for
// an unavailable source, or an object with WebCrypto's getRandomValues. The
// method is only looked up, not read, so that a failing getter still reaches
// the WebCrypto adapter, which reports it as a source failure.
export function cryptoOf(value) {
  if (value === undefined || value === null) return value;
  if ((typeof value !== 'object' && typeof value !== 'function') || !('getRandomValues' in value)) {
    throw new TypeError('options.crypto must be an object with getRandomValues, or null');
  }
  return value;
}

// The options of send, checked: the limits, the sampling, whether the
// policy is strict, and the source.
export function sendOptions(options) {
  const { limits, sampling, policy, crypto } = optionsOf(options);
  return {
    limits: limitsOf(limits),
    sampling: choice(sampling, 'inherit', SAMPLINGS, 'options.sampling'),
    strict: choice(policy, 'lenient', STRICT, 'options.policy'),
    crypto: cryptoOf(crypto),
  };
}
