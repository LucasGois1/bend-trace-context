import { webcrypto } from 'node:crypto';

// The quota/type modes call actual WebCrypto with intentionally invalid requests.
// They test exception translation, not spontaneous failure of a one-word request.
const mode = process.env.BEND_ENTROPY_CASE;
if (mode === 'unavailable') {
  delete globalThis.crypto;
} else if (mode === 'getter') {
  Object.defineProperty(globalThis, 'crypto', {
    configurable: true,
    get() { throw new Error('controlled global lookup failure'); },
  });
} else {
  Object.defineProperty(globalThis, 'crypto', {
    configurable: true,
    value: { getRandomValues(words) {
      switch (mode) {
        case 'fixed': words[0] = 0xffffffff; return words;
        case 'quota': return webcrypto.getRandomValues(new Uint8Array(65537));
        case 'type': return webcrypto.getRandomValues(new Float32Array(1));
        case 'controlled': throw new Error('controlled source failure');
        case 'invalid': return [-1];
        default: throw new Error(`Unknown entropy qualification case: ${mode}`);
      }
    } },
  });
}
