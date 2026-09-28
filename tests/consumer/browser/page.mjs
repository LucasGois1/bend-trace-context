// An independent browser application that installs the package from a
// pinned checkout (npm install of packages/trace-context), imports only its
// public entries and is bundled by the checkout's official Bend bundler. It
// runs once when loaded and prints what happened; browser-expected.txt
// holds the output that W3C Trace Context Level 2 and spec #1 give.
import * as TC from 'bend-trace-context';
import { documentFields, tracedFetch } from 'bend-trace-context/fetch';

const partner = 'http://127.0.0.1:4174';
// The key under which the observer records this run's calls: one per engine.
const key = new URL(location.href).searchParams.get('key');

// A source with WebCrypto's interface that returns the given words in order.
function words(...list) {
  let read = 0;
  return { getRandomValues(array) { array[0] = list[read++]; return array; } };
}

// The context lines of a request's raw headers, by name: engines may send
// lines of different names in another order, as WebKit does.
function contextLines(rawHeaders) {
  const values = (name) => rawHeaders.filter((item, index) => index % 2 === 1 && rawHeaders[index - 1].toLowerCase() === name);
  return ['traceparent', 'tracestate'].map((name) => `${name}: ${values(name).join(' / ')}`).join(' | ');
}

const lines = [];
const extraction = TC.extract(documentFields(document));
lines.push(`extracted: ${extraction.show}`);
const service = TC.continueOrStart(extraction, { crypto: words(0x00f067aa, 0x0ba902b7) });
lines.push(`service: ${service.show} ${service.outgoing.context.traceparent}`);

const same = await tracedFetch(service, '/api/echo', { method: 'POST', headers: [['traceparent', 'stale'], ['x-seen', 'a']] },
  { crypto: words(0x53995c3f, 0x42cd8ad8) });
lines.push(`same origin: ${same.sent.show} | ${contextLines((await same.response.json()).rawHeaders)}`);

const allowed = await tracedFetch(service, `${partner}/allowed/${key}`, {
  method: 'POST', headers: { 'content-type': 'application/json' }, body: '{"order":1}',
}, { propagateTo: [partner], crypto: words(0xa3ce929d, 0x0e0e4736) });
lines.push(`partner: ${allowed.response.status} ${allowed.sent.show} ${allowed.sent.operation.traceparent}`);

const unlisted = await tracedFetch(service, `${partner}/refused/${key}`, {
  method: 'POST', headers: [['content-type', 'text/plain'], ['traceparent', 'stale']], body: 'order',
});
lines.push(`unlisted origin: ${unlisted.response.status} ${unlisted.sent === null ? 'no context' : unlisted.sent.show}`);

try {
  await tracedFetch(service, `${partner}/allowed/${key}-strict`, { method: 'POST' },
    { propagateTo: [partner], policy: 'strict', crypto: null });
  lines.push('strict: sent');
} catch (error) {
  lines.push(`strict: ${error.name} ${error.reason}`);
}

try {
  await tracedFetch({ ...service }, '/api/echo');
} catch (error) {
  lines.push(`copied handle: ${error.name}`);
}

lines.push(`generated root: ${/^00-[0-9a-f]{32}-[0-9a-f]{16}-02$/.test(TC.root().traceparent)}`);
document.getElementById('result').textContent = lines.join('\n');
