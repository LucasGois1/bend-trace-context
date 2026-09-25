import { webcrypto } from 'node:crypto';

// The quota/type modes call actual WebCrypto with intentionally invalid requests.
// They test exception translation, not spontaneous failure of a one-word request.
// Every getRandomValues call is counted and reported on stderr at exit, so
// tests can assert how many words a program consumed.
const mode = process.env.BEND_ENTROPY_CASE;
let reads = 0;
process.on('exit', () => { process.stderr.write(`entropy-reads=${reads}\n`); });
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
      reads += 1;
      switch (mode) {
        case 'fixed': words[0] = 0xffffffff; return words;
        case 'zero': words[0] = 0; return words;
        case 'third-fails':
          if (reads === 3) throw new Error('controlled failure at the third word');
          words[0] = 0x0af76519; return words;
        case 'quota': return webcrypto.getRandomValues(new Uint8Array(65537));
        case 'type': return webcrypto.getRandomValues(new Float32Array(1));
        case 'controlled': throw new Error('controlled source failure');
        case 'invalid': return [-1];
        default: throw new Error(`Unknown entropy qualification case: ${mode}`);
      }
    } },
  });
}
