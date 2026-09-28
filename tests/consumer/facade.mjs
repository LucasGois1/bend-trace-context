// An independent JavaScript application that installs the package's facade
// from a pinned checkout (npm install of packages/trace-context) and uses
// only its public entries. The expected output, facade-expected.txt, follows
// W3C Trace Context Level 2 and spec #1; it is not computed by the package.
import http from 'node:http';
import { webcrypto } from 'node:crypto';
import * as TC from 'bend-trace-context';
import { continueOrStartRequest, requestHeaders } from 'bend-trace-context/node';

const received = '00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01';

// A source with WebCrypto's interface that returns the given words in order.
function words(...list) {
  let read = 0;
  return { getRandomValues(array) { array[0] = list[read++]; return array; } };
}

const line = (fields) => fields.map(([name, value]) => `${name}: ${value}`).join(' | ');

const extraction = TC.extract([['Host', 'api.example'], ['traceparent', received],
  ['tracestate', 'congo=t61rcWkgMzE'], ['TraceState', 'rojo=00f067aa0ba902b7']]);
console.log(`extracted: ${extraction.show}`);
const { received: pair } = extraction.incoming;
console.log(`received pair: ${pair.traceparent} | ${pair.tracestate.join(' | ')}`);

let service = TC.continueOrStart(extraction, { crypto: words(0x00f067aa, 0x0ba902b7) });
console.log(`service: ${service.show} ${service.outgoing.context.traceparent}`);
service = TC.setState(service, 'fw529a3039', 'cHJpbWFyeQ');
console.log(`own entry: ${service.outgoing.tracestate}`);
const sent = TC.send(service, [['Accept', 'application/json'], ['traceparent', 'stale']],
  { crypto: words(0x53995c3f, 0x42cd8ad8) });
console.log(`sent: ${sent.show} | ${line(sent.fields)}`);

const started = TC.continueOrStart(TC.extract([['Host', 'api.example']]),
  { crypto: words(0x4bf92f35, 0x77b34da6, 0xa3ce929d, 0x0e0e4736, 0x00f067aa, 0x0ba902b7) });
console.log(`started: ${started.show} ${started.outgoing.context.traceparent}`);
const restarted = TC.continueOrStart(extraction, { reception: 'restart', sampling: 'sampled',
  crypto: words(0x4bf92f35, 0x77b34da6, 0xa3ce929d, 0x0e0e4736, 0x53995c3f, 0x42cd8ad8) });
console.log(`restarted: ${restarted.show} ${restarted.outgoing.context.traceparent} state "${restarted.outgoing.tracestate}"`);

console.log(`rejected: ${TC.extract([['traceparent', '00-00000000000000000000000000000000-b7ad6b7169203331-01']]).show}`);
console.log(`repeated: ${TC.extract([['traceparent', received], ['Traceparent', received]]).show}`);
const discarded = TC.extract([['traceparent', received], ['tracestate', 'congo']]);
console.log(`discarded: ${discarded.show}`);

// A source that calls actual WebCrypto with a request over its quota.
const refusing = { getRandomValues() { return webcrypto.getRandomValues(new Uint8Array(65537)); } };
const untraced = TC.continueOrStart(extraction, { crypto: refusing });
console.log(`without entropy: ${untraced.show}`);
console.log(`fallback: ${TC.send(untraced, [['Accept', 'application/json']]).show}`);
try {
  TC.continueOrStart(extraction, { policy: 'strict', crypto: refusing });
} catch (error) {
  console.log(`strict: ${error.name} ${error.reason}`);
}
try {
  TC.root({ crypto: words(...Array(32).fill(0)) });
} catch (error) {
  console.log(`exhausted: ${error.reason}`);
}

console.log(`forwarded: ${line(TC.forward(extraction.incoming, [['Host', 'billing.internal']]).fields)}`);
console.log(`not forwarded: ${TC.forward(discarded.incoming, []).error}`);
const child = TC.child(extraction.incoming, { sampling: 'unsampled', crypto: words(0xa3ce929d, 0x0e0e4736) });
console.log(`injected: ${line(TC.inject(TC.outgoing(child), [['Host', 'metrics.internal']]).fields)}`);
console.log(`cleared: ${line(TC.clear([['Host', 'metrics.internal'], ['TRACEPARENT', received]]))}`);
try {
  TC.limits({ traceparentInput: 54 });
} catch (error) {
  console.log(`limits refused: ${error.name} ${error.message}`);
}
try {
  TC.send({ ...service }, []);
} catch (error) {
  console.log(`copied handle refused: ${error.name}`);
}
const supplied = TC.fromIds('5b8efff798038103d269b633813fc60c', 'eee19b7ec3c1b174', { sampled: true });
console.log(`supplied operation: ${supplied.traceparent}`);
console.log(`supplied child: ${TC.childFromId(supplied, '2f1c8a36d5e97b40').traceparent}`);
try {
  TC.childFromId(supplied, 'eee19b7ec3c1b174');
} catch (error) {
  console.log(`reused span refused: ${error.name} ${error.message}`);
}
try {
  TC.rootFromIds('00000000000000000000000000000000', 'eee19b7ec3c1b174');
} catch (error) {
  console.log(`supplied trace refused: ${error.name} ${error.message}`);
}
const root = TC.root();
console.log(`generated root: ${/^00-[0-9a-f]{32}-[0-9a-f]{16}-02$/.test(root.traceparent)} random ${root.random}`);

// A node:http service between a client and an independent observer.
const seen = [];
const observer = http.createServer((request, response) => {
  seen.push(request.rawHeaders);
  request.resume();
  request.on('end', () => response.end());
});
const gateway = http.createServer((request, response) => {
  const operation = continueOrStartRequest(request, { crypto: words(0x00f067aa, 0x0ba902b7) });
  const call = TC.send(operation, [['content-type', 'application/json']], { crypto: words(0x53995c3f, 0x42cd8ad8) });
  const downstream = http.request(`http://127.0.0.1:${observer.address().port}/`,
    { method: 'POST', headers: requestHeaders(call.fields) }, (answer) => {
      answer.resume();
      answer.on('end', () => response.end(operation.show));
    });
  downstream.end('{}');
});
await Promise.all([observer, gateway].map((server) => new Promise((resolve) => server.listen(0, '127.0.0.1', resolve))));
const answer = await new Promise((resolve, reject) => {
  const request = http.request(`http://127.0.0.1:${gateway.address().port}/`,
    { method: 'POST', headers: { TraceParent: received, tracestate: ['congo=t61rcWkgMzE', 'rojo=00f067aa0ba902b7'] } },
    (response) => {
      let text = '';
      response.on('data', (chunk) => { text += chunk; });
      response.on('end', () => resolve(text));
    });
  request.on('error', reject);
  request.end();
});
const traceLines = [];
for (let index = 0; index < seen[0].length; index += 2) {
  if (seen[0][index].startsWith('trace')) traceLines.push(`${seen[0][index]}: ${seen[0][index + 1]}`);
}
console.log(`http: ${answer} | ${traceLines.join(' | ')}`);
gateway.close();
observer.close();
