import assert from 'node:assert/strict';
import test from 'node:test';
import http from 'node:http';
import * as TC from '../../packages/trace-context/javascript/index.mjs';
import {
  continueOrStartRequest, extractRequest, requestFields, requestHeaders,
} from '../../packages/trace-context/javascript/node.mjs';

const TRACEPARENT = '00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01';

function words(...list) {
  let read = 0;
  return { getRandomValues(array) { array[0] = list[read++]; return array; } };
}

// A server that answers every request with `handle`. A handler that throws
// answers 500 with the error, so that a failure fails the test instead of
// leaving the client waiting.
async function listen(handle) {
  const server = http.createServer(async (request, response) => {
    try {
      await handle(request, response);
    } catch (error) {
      response.writeHead(500, { 'content-type': 'text/plain' });
      response.end(String(error?.stack ?? error));
    }
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  return { url: `http://127.0.0.1:${server.address().port}`, close: () => new Promise((resolve) => server.close(resolve)) };
}

// An independent observer: it records the raw header lines of each request
// it receives, as they arrived.
async function observer() {
  const received = [];
  const server = await listen((request, response) => {
    received.push(request.rawHeaders);
    request.resume();
    request.on('end', () => response.end('ok'));
  });
  return { ...server, received };
}

function lines(raw, name) {
  const found = [];
  for (let index = 0; index < raw.length; index += 2) {
    if (raw[index].toLowerCase() === name) found.push(raw[index + 1]);
  }
  return found;
}

function post(url, headers, body = '') {
  return new Promise((resolve, reject) => {
    const request = http.request(url, { method: 'POST', headers, timeout: 5000 }, (response) => {
      let text = '';
      response.setEncoding('utf8');
      response.on('data', (chunk) => { text += chunk; });
      response.on('end', () => resolve({ status: response.statusCode, text }));
    });
    request.on('timeout', () => request.destroy(new Error(`no answer from ${url}`)));
    request.on('error', reject);
    request.end(body);
  });
}

test('a node:http service continues a received request and sends a child through ClientRequest headers', async () => {
  const downstream = await observer();
  const diagnostics = [];
  const service = await listen(async (request, response) => {
    const extraction = extractRequest(request);
    const context = continueOrStartRequest(request, { crypto: words(0x00f067aa, 0x0ba902b7) });
    const sent = TC.send(context, [['Content-Type', 'application/json'], ['X-Seen', 'a'], ['x-seen', 'b']],
      { crypto: words(0x53995c3f, 0x42cd8ad8) });
    diagnostics.push(`${extraction.show}; ${context.show}, downstream ${sent.show}`);
    await post(`${downstream.url}/downstream`, requestHeaders(sent.fields), '{}');
    response.end(context.outgoing.context.traceparent);
  });
  try {
    const answer = await post(`${service.url}/orders`, {
      TraceParent: TRACEPARENT, tracestate: ['congo=t61rcWkgMzE', 'rojo=00f067aa0ba902b7'],
    });
    assert.equal(answer.status, 200, answer.text);
    assert.equal(answer.text, '00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-01');
    assert.deepEqual(diagnostics, ['TraceParentAccepted, StateAccepted; Continued, downstream Fresh']);
    const [raw] = downstream.received;
    assert.deepEqual(lines(raw, 'traceparent'), ['00-0af7651916cd43dd8448eb211c80319c-53995c3f42cd8ad8-01']);
    assert.deepEqual(lines(raw, 'tracestate'), ['congo=t61rcWkgMzE,rojo=00f067aa0ba902b7']);
    assert.deepEqual(lines(raw, 'x-seen'), ['a', 'b']);
  } finally {
    await service.close();
    await downstream.close();
  }
});

test('the raw header lines keep repeated fields, so a repeated traceparent is refused', async () => {
  const seen = [];
  const service = await listen((request, response) => {
    seen.push(requestFields(request).filter(([name]) => name.toLowerCase().startsWith('trace')));
    seen.push(extractRequest(request).show);
    response.end();
  });
  try {
    await post(service.url, { traceparent: [TRACEPARENT, TRACEPARENT], TraceState: 'congo=t61rcWkgMzE' });
    assert.deepEqual(seen, [
      [['traceparent', TRACEPARENT], ['traceparent', TRACEPARENT], ['TraceState', 'congo=t61rcWkgMzE']],
      'TraceParentRejected RepeatedTraceParent, StateIgnored',
    ]);
  } finally {
    await service.close();
  }
});

test('fetch sends the context fields whole and joins other repeated values', async () => {
  const downstream = await observer();
  try {
    const extraction = TC.extract([['traceparent', TRACEPARENT], ['tracestate', 'congo=t61rcWkgMzE']]);
    const context = TC.continueOrStart(extraction, { crypto: words(1, 2) });
    const sent = TC.send(context, [['X-Seen', 'a'], ['x-seen', 'b']], { crypto: words(0x53995c3f, 0x42cd8ad8) });
    const response = await fetch(downstream.url, { method: 'POST', headers: sent.fields, body: '{}' });
    assert.equal(await response.text(), 'ok');
    const [raw] = downstream.received;
    assert.deepEqual(lines(raw, 'traceparent'), ['00-0af7651916cd43dd8448eb211c80319c-53995c3f42cd8ad8-01']);
    assert.deepEqual(lines(raw, 'tracestate'), ['congo=t61rcWkgMzE']);
    assert.deepEqual(lines(raw, 'x-seen'), ['a, b']);
  } finally {
    await downstream.close();
  }
});

test('ClientRequest headers group each name once, in order, with its first spelling', () => {
  const expected = Object.assign(Object.create(null), {
    'X-Seen': ['a', 'b', 'c'], Host: 'example', traceparent: TRACEPARENT, ['__proto__']: 'kept',
  });
  assert.deepEqual(requestHeaders([['X-Seen', 'a'], ['Host', 'example'], ['x-seen', 'b'], ['traceparent', TRACEPARENT],
    ['X-SEEN', 'c'], ['__proto__', 'kept']]), expected);
  assert.deepEqual(Object.keys(expected), ['X-Seen', 'Host', 'traceparent', '__proto__']);
  for (const fields of [undefined, 'x', [['a']], [['a', 1]], [[new String('a'), 'b']]]) {
    assert.throws(() => requestHeaders(fields), TypeError);
  }
  for (const request of [undefined, null, {}, { rawHeaders: 'traceparent' }, { rawHeaders: ['traceparent'] },
    { rawHeaders: ['traceparent', 1] }]) {
    assert.throws(() => requestFields(request), TypeError);
  }
});
