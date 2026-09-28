// A page of the browser qualification, not an example: it gives
// entropy.spec.mjs the package's shared WebCrypto source, an internal module
// that applications reach only through the facade's `crypto` option.
import entropy from '../../../packages/trace-context/entropy/webcrypto.js';

globalThis.traceContext = { readRandomU32: entropy.readRandomU32 };
