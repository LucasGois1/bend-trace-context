function readRandomU32(provider) {
  try {
    const source = provider === undefined ? globalThis.crypto : provider;
    if (!source || typeof source.getRandomValues !== 'function') {
      return { $: 'Fail', error: { $: 'Tuple', fst: 1, snd: 'unavailable' } };
    }
    const word = source.getRandomValues(new Uint32Array(1))[0];
    if (!Number.isInteger(word) || word < 0 || word > 0xffffffff) {
      return { $: 'Fail', error: { $: 'Tuple', fst: 2, snd: 'source-failure' } };
    }
    return { $: 'Done', value: word };
  } catch (_) {
    return { $: 'Fail', error: { $: 'Tuple', fst: 2, snd: 'source-failure' } };
  }
}

// Bend's effect loader finds this exact name inside its generated closure.
function read_u32() {
  return readRandomU32();
}

// The browser bundler and Node import the same implementation as CommonJS.
// In a compiled CLI this assigns unused CLI exports; it does not run an effect.
if (typeof module !== 'undefined') {
  module.exports = { readRandomU32 };
}
