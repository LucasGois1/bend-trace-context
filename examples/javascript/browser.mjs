import { inspectTraceparent } from '../../packages/trace-context/javascript/codec.mjs';
import entropy from '../../packages/trace-context/entropy/webcrypto.js';

document.getElementById('inspect').addEventListener('click', () => {
  const result = inspectTraceparent(document.getElementById('traceparent').value);
  document.getElementById('result').textContent = JSON.stringify(result);
});

// Also available to callers in the page and the browser console.
globalThis.traceContext = { inspectTraceparent, readRandomU32: entropy.readRandomU32 };
