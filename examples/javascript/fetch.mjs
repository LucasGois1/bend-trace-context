// A page that takes part in a trace with the package's facade: it continues
// the context that its server rendered into <meta> elements, or starts a
// trace without one, and calls APIs with tracedFetch, which gives each call a
// child of the page's operation. The page's own API receives the context
// fields; the partner API, on another origin, receives them because it is
// allowed and its CORS preflight accepts them.
import * as TC from '../../packages/trace-context/javascript/index.mjs';
import { documentFields, tracedFetch } from '../../packages/trace-context/javascript/fetch.mjs';

const partner = 'http://127.0.0.1:4174';
const extraction = TC.extract(documentFields(document));
const service = TC.continueOrStart(extraction);
document.getElementById('operation').textContent = `${extraction.show}; ${service.show}`;

// Call an API and show what happened, without any received value.
async function call(url) {
  try {
    const { response, sent } = await tracedFetch(service, url, {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}',
    }, { propagateTo: [partner] });
    return `${response.status}, ${sent === null ? 'no context' : sent.show}`;
  } catch (error) {
    return `${error.name}: ${error.message}`;
  }
}

const result = document.getElementById('result');
document.getElementById('same-origin').addEventListener('click', async () => {
  result.textContent = await call('/api/echo');
});
document.getElementById('partner').addEventListener('click', async () => {
  result.textContent = await call(`${partner}/allowed/example`);
});
// Fetch's Headers joins the values of a repeated name before the package
// sees them: two traceparent values become one, which extraction refuses.
document.getElementById('joined').addEventListener('click', () => {
  const headers = new Headers();
  headers.append('x-seen', 'a');
  headers.append('X-Seen', 'b');
  for (const [name, value] of documentFields(document)) headers.append(name, value);
  headers.append('traceparent', '00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01');
  const fields = [...headers].map(([name, value]) => `${name}: ${value}`).join('\n');
  result.textContent = `${fields}\n${TC.extract([...headers]).show}`;
});

// The facade and the page's service, for callers in the page and the
// browser console.
globalThis.traceContext = { ...TC, documentFields, tracedFetch, extraction, service };
