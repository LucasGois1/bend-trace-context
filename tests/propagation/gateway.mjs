// The adoption example packages/trace-context/examples/gateway.bend,
// compiled from a pinned checkout, or its JavaScript twin gateway.mjs, run
// from one, between a client and an independent downstream observer: the
// gateway continues the client's trace, calls downstream with a new child
// and returns the downstream response, logging only diagnostics.
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { createServer, request as httpRequest } from 'node:http';
import test from 'node:test';
import { launch } from './launch.mjs';

const gatewayPath = process.env.BEND_GATEWAY;
assert.ok(gatewayPath, 'pass the gateway program path in BEND_GATEWAY');

test('the gateway continues a request and calls downstream with its own child', async t => {
  const observations = [];
  const downstream = createServer((request, response) => {
    const chunks = [];
    request.on('data', chunk => chunks.push(chunk));
    request.on('end', () => {
      observations.push({ path: request.url, headers: request.headers, body: Buffer.concat(chunks).toString() });
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end('{"downstream":true}');
    });
  });
  downstream.listen(18776, '127.0.0.1');
  await once(downstream, 'listening');
  t.after(() => downstream.close());

  const gateway = await launch(gatewayPath, 'http://127.0.0.1:18777');
  t.after(() => gateway.stop());

  const response = await new Promise((resolve, reject) => {
    const outgoing = httpRequest({
      host: '127.0.0.1',
      port: 18777,
      method: 'POST',
      path: '/orders',
      headers: {
        traceparent: '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01',
        tracestate: 'congo=t61rcWkgMzE',
        'content-type': 'application/json',
      },
    }, incoming => {
      const chunks = [];
      incoming.on('data', chunk => chunks.push(chunk));
      incoming.on('end', () => resolve({ status: incoming.statusCode, body: Buffer.concat(chunks).toString() }));
    });
    outgoing.on('error', reject);
    outgoing.end('{"order":1}');
  });

  assert.equal(response.status, 200);
  assert.equal(response.body, '{"downstream":true}');
  assert.equal(observations.length, 1);
  const [call] = observations;
  assert.equal(call.path, '/downstream');
  assert.equal(call.body, '{"order":1}');
  const match = /^00-4bf92f3577b34da6a3ce929d0e0e4736-([0-9a-f]{16})-01$/.exec(call.headers.traceparent);
  assert.ok(match, `a child of the client's operation, got ${call.headers.traceparent}`);
  assert.notEqual(match[1], '00f067aa0ba902b7');
  assert.equal(call.headers.tracestate, 'congo=t61rcWkgMzE');
  await new Promise(resolve => setTimeout(resolve, 50));
  assert.match(gateway.stdout(), /POST \/orders: TraceParentAccepted, StateAccepted; Continued, downstream Fresh/);
  assert.ok(!gateway.stdout().includes('4bf92f3577b34da6a3ce929d0e0e4736'), 'the log holds no header value');
});
