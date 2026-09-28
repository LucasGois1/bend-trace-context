import { inspectTraceparent } from 'bend-trace-context';

document.getElementById('inspect').addEventListener('click', () => {
  const result = inspectTraceparent(document.getElementById('traceparent').value);
  document.getElementById('result').textContent = JSON.stringify(result);
});

// Also available to callers in the page and the browser console.
globalThis.traceContext = { inspectTraceparent };
