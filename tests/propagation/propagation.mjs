// Complementary propagation checks for a service on real HTTP: the native
// service (tests/propagation/service.bend, compiled from a pinned checkout)
// over bend-net, or the Node service (tests/propagation/service.mjs, on the
// JavaScript facade installed from a pinned checkout) over node:http. The
// service receives requests from this driver and sends its callbacks to an
// independent Node observer, which records the header lines exactly as they
// arrive. Expected values follow W3C Trace Context Level 2 and spec #1; they
// are not computed by the package. BEND_PROPAGATION_SOURCE_FAILURE is the
// failure the service's unavailable source gives, as its host reports it.
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { createServer } from 'node:http';
import { connect } from 'node:net';
import test from 'node:test';
import { launch } from './launch.mjs';

const servicePath = process.env.BEND_PROPAGATION_SERVICE;
assert.ok(servicePath, 'pass the propagation service path in BEND_PROPAGATION_SERVICE');
const failure = process.env.BEND_PROPAGATION_SOURCE_FAILURE;
assert.ok(failure, 'pass the unavailable source failure in BEND_PROPAGATION_SOURCE_FAILURE');

const servicePort = 18775;
const observerPort = 18776;
const received = '00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331';
const traceparentFormat = /^([0-9a-f]{2})-([0-9a-f]{32})-([0-9a-f]{16})-([0-9a-f]{2})$/;

const observations = [];
const observer = createServer((request, response) => {
  const chunks = [];
  request.on('data', chunk => chunks.push(chunk));
  request.on('end', () => {
    observations.push({ path: request.url, rawHeaders: request.rawHeaders, body: Buffer.concat(chunks).toString() });
    response.writeHead(200, { 'content-type': 'application/json' });
    response.end('null');
  });
});
let service;

test.before(async () => {
  observer.listen(observerPort, '127.0.0.1');
  await once(observer, 'listening');
  service = await launch(servicePath, `http://127.0.0.1:${servicePort}`);
});

test.after(() => {
  service?.stop();
  observer.close();
});

// Send one request with exact header lines, as the harness does, and read
// the whole response.
const post = (path, headers, callbacks = 1) => new Promise((resolve, reject) => {
  const body = JSON.stringify(Array.from({ length: callbacks }, (_, index) => ({
    url: `http://127.0.0.1:${observerPort}/callback/${index}`,
    arguments: [{ index }],
  })));
  const socket = connect(servicePort, '127.0.0.1');
  let response = '';
  socket.setEncoding('latin1');
  socket.on('connect', () => {
    socket.write([
      `POST ${path} HTTP/1.1`,
      `Host: 127.0.0.1:${servicePort}`,
      'Connection: close',
      'Content-Type: application/json',
      ...headers,
      `Content-Length: ${Buffer.byteLength(body)}`,
      '',
      body,
    ].join('\r\n'));
  });
  socket.on('data', chunk => { response += chunk; });
  socket.on('end', () => {
    const [head, ...rest] = response.split('\r\n\r\n');
    resolve({ status: Number(head.split(' ')[1]), body: JSON.parse(rest.join('\r\n\r\n')) });
  });
  socket.on('error', reject);
});

// The values of each header name a callback carried, in arrival order.
const fields = observation => {
  const byName = new Map();
  for (let index = 0; index < observation.rawHeaders.length; index += 2) {
    const name = observation.rawHeaders[index].toLowerCase();
    byName.set(name, [...(byName.get(name) ?? []), observation.rawHeaders[index + 1]]);
  }
  return byName;
};

// The one traceparent a callback carried, split into its fields.
const traceparent = observation => {
  const values = fields(observation).get('traceparent') ?? [];
  assert.equal(values.length, 1, `one traceparent per callback, got ${JSON.stringify(values)}`);
  const match = traceparentFormat.exec(values[0]);
  assert.ok(match, `a version 00 traceparent, got ${values[0]}`);
  const [, version, trace, parent, flags] = match;
  return { version, trace, parent, flags, value: values[0] };
};

const exchange = async (path, headers, callbacks = 1) => {
  observations.length = 0;
  const response = await post(path, headers, callbacks);
  return { response, callbacks: [...observations] };
};

test('a sampled 0 request is continued by an unsampled child', async () => {
  const { response, callbacks } = await exchange('/test', [`traceparent: ${received}-00`]);
  assert.equal(response.status, 200);
  assert.equal(response.body.service, 'Continued');
  const sent = traceparent(callbacks[0]);
  assert.equal(sent.version, '00');
  assert.equal(sent.trace, '0af7651916cd43dd8448eb211c80319c');
  assert.notEqual(sent.parent, 'b7ad6b7169203331');
  assert.equal(sent.flags, '00');
});

test('the random-trace-id and sampled flags are kept as received', async () => {
  for (const flags of ['01', '02', '03']) {
    const { callbacks } = await exchange('/test', [`traceparent: ${received}-${flags}`]);
    assert.equal(traceparent(callbacks[0]).flags, flags, `flags ${flags}`);
  }
});

test('a request without context starts a random, unsampled trace', async () => {
  const { response, callbacks } = await exchange('/test', [], 2);
  assert.equal(response.body.service, 'Started');
  const [first, second] = callbacks.map(traceparent);
  assert.equal(first.flags, '02');
  assert.equal(first.trace, second.trace);
  assert.notEqual(first.parent, second.parent);
});

test('a trust boundary restarts the trace and discards the received state', async () => {
  const { response, callbacks } = await exchange('/test/restart', [
    `traceparent: ${received}-01`,
    'tracestate: congo=t61rcWkgMzE',
  ]);
  assert.equal(response.body.service, 'Restarted');
  const sent = traceparent(callbacks[0]);
  assert.notEqual(sent.trace, '0af7651916cd43dd8448eb211c80319c');
  assert.equal(sent.flags, '02');
  assert.equal(fields(callbacks[0]).get('tracestate'), undefined);
});

test('each request of a fan-out carries its own child', async () => {
  const { callbacks } = await exchange('/test', [`traceparent: ${received}-01`], 3);
  const sent = callbacks.map(traceparent);
  assert.deepEqual(new Set(sent.map(x => x.trace)), new Set(['0af7651916cd43dd8448eb211c80319c']));
  assert.equal(new Set(sent.map(x => x.parent)).size, 3);
});

test('repeated injection into a reused container replaces the old context fields', async () => {
  const { response, callbacks } = await exchange('/test/stale', [
    `TraceParent: ${received}-01`,
    'TRACESTATE: congo=t61rcWkgMzE',
    'X-Request-Id: 42',
  ], 2);
  assert.equal(response.status, 200);
  assert.deepEqual(response.body.sent, ['Fresh', 'Fresh']);
  const [first, second] = callbacks.map(traceparent);
  assert.equal(first.trace, '0af7651916cd43dd8448eb211c80319c');
  assert.notEqual(first.parent, second.parent);
  for (const callback of callbacks) {
    assert.deepEqual(fields(callback).get('tracestate'), ['congo=t61rcWkgMzE']);
    assert.deepEqual(fields(callback).get('x-request-id'), ['42']);
  }
});

test('a discarded state is not sent, and the diagnostics hold no received value', async () => {
  const { response, callbacks } = await exchange('/test', [`traceparent: ${received}-01`, 'tracestate: foo=,bar=3']);
  assert.match(response.body.extraction, /^TraceParentAccepted, StateDiscarded /);
  assert.ok(!JSON.stringify(response.body).includes('bar=3'));
  assert.equal(traceparent(callbacks[0]).trace, '0af7651916cd43dd8448eb211c80319c');
  assert.equal(fields(callbacks[0]).get('tracestate'), undefined);
});

test('without entropy, the received pair is forwarded unchanged', async () => {
  const { response, callbacks } = await exchange('/test/unavailable', [
    `traceparent: ${received}-01`,
    'tracestate: rojo=00f067aa0ba902b7',
    'tracestate: congo=t61rcWkgMzE',
    'X-Request-Id: 42',
  ]);
  assert.equal(response.status, 200);
  assert.equal(response.body.service, `Untraced ${failure}`);
  assert.deepEqual(response.body.sent, [`Forwarded after ${failure}`]);
  assert.deepEqual(fields(callbacks[0]).get('traceparent'), [`${received}-01`]);
  assert.deepEqual(fields(callbacks[0]).get('tracestate'), ['rojo=00f067aa0ba902b7,congo=t61rcWkgMzE']);
  assert.deepEqual(fields(callbacks[0]).get('x-request-id'), ['42']);
});

test('without entropy or a pair to forward, the old context fields are cleared', async () => {
  const discarded = await exchange('/test/unavailable', [
    `traceparent: ${received}-01`,
    'tracestate: foo=,bar=3',
    'X-Request-Id: 42',
  ]);
  assert.deepEqual(discarded.response.body.sent, [`NoContext after ${failure}, NothingToForward`]);
  assert.equal(fields(discarded.callbacks[0]).get('traceparent'), undefined);
  assert.equal(fields(discarded.callbacks[0]).get('tracestate'), undefined);
  assert.deepEqual(fields(discarded.callbacks[0]).get('x-request-id'), ['42']);
  const absent = await exchange('/test/unavailable', ['X-Request-Id: 42']);
  assert.deepEqual(absent.response.body.sent, [`NoContext after ${failure}, NothingKept`]);
  assert.equal(fields(absent.callbacks[0]).get('traceparent'), undefined);
});

test('the strict policy refuses the request without any callback', async () => {
  const { response, callbacks } = await exchange('/test/unavailable/strict', [`traceparent: ${received}-01`]);
  assert.equal(response.status, 503);
  assert.deepEqual(response.body, { refused: failure });
  assert.equal(callbacks.length, 0);
});

test('a child that cannot be generated forwards the received pair unchanged', async () => {
  const { response, callbacks } = await exchange('/test/unavailable/send', [
    `traceparent: ${received}-01`,
    'tracestate: congo=t61rcWkgMzE',
    'X-Request-Id: 42',
  ], 2);
  assert.equal(response.status, 200);
  assert.equal(response.body.service, 'Continued');
  assert.deepEqual(response.body.sent, [
    `Forwarded after ${failure}`,
    `Forwarded after ${failure}`,
  ]);
  for (const callback of callbacks) {
    assert.deepEqual(fields(callback).get('traceparent'), [`${received}-01`]);
    assert.deepEqual(fields(callback).get('tracestate'), ['congo=t61rcWkgMzE']);
    assert.deepEqual(fields(callback).get('x-request-id'), ['42']);
  }
});

test('a strict send refuses the request when no child can be generated', async () => {
  const { response, callbacks } = await exchange('/test/unavailable/send/strict', [`traceparent: ${received}-01`]);
  assert.equal(response.status, 503);
  assert.deepEqual(response.body, { refused: failure });
  assert.equal(callbacks.length, 0);
});

test('exhausted candidates leave the service without an operation', async () => {
  const continued = await exchange('/test/exhausted', [`traceparent: ${received}-01`]);
  assert.equal(continued.response.body.service, 'Untraced ExhaustedSpanId');
  assert.deepEqual(continued.response.body.sent, ['Forwarded after ExhaustedSpanId']);
  assert.deepEqual(fields(continued.callbacks[0]).get('traceparent'), [`${received}-01`]);
  const started = await exchange('/test/exhausted', []);
  assert.equal(started.response.body.service, 'Untraced ExhaustedTraceId');
  assert.deepEqual(started.response.body.sent, ['NoContext after ExhaustedTraceId, NothingKept']);
  assert.equal(fields(started.callbacks[0]).get('traceparent'), undefined);
});
