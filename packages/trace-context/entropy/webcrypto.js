// The JavaScript twin of entropy/native.c: one word from WebCrypto's
// getRandomValues, as the Result of entropy.bend's read_u32. The failure is
// (1, "unavailable") when the host has no WebCrypto and (2,
// "source-failure") when the call throws or answers anything but one U32.
//
// A compiled Bend program runs this file as a script and registers the
// effect with io_eff(CID(read_u32), ...), as the pinned compiler's effect
// guide (guide/EFFECTS.md) describes; a compiler update must requalify it.
// The JavaScript facade imports the same file as CommonJS for readRandomU32,
// with a caller's provider, and no effect exists there to register.
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

function read_u32() {
  return readRandomU32();
}

if (typeof io_eff === 'function') {
  io_eff(CID(read_u32), read_u32);
}

// In a compiled program this assigns unused exports; it runs no effect.
if (typeof module !== 'undefined') {
  module.exports = { readRandomU32 };
}
