import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { connect } from 'node:net';
import test from 'node:test';
import { once } from 'node:events';

const servicePath = process.env.BEND_NATIVE_HTTP_SERVICE;
assert.ok(servicePath, 'pass the compiled Bend HTTP service path');

test('native Bend service issues W3C-shaped JSON callbacks through bend-net', async t => {
  const observations = [];
  const observer = createServer((request, response) => {
    const chunks = [];
    request.on('data', chunk => chunks.push(chunk));
    request.on('end', () => {
      observations.push({
        path: request.url,
        rawHeaders: request.rawHeaders,
        body: Buffer.concat(chunks).toString('utf8'),
      });
      if (request.url === '/redirect') {
        response.writeHead(302, { location: '/redirected' });
        response.end();
      } else {
        response.writeHead(200, { 'content-type': 'application/json' });
        response.end('null');
      }
    });
  });
  observer.listen(18774, '127.0.0.1');
  await once(observer, 'listening');
  t.after(() => observer.close());

  const service = spawn(servicePath, [], { stdio: ['ignore', 'pipe', 'pipe'] });
  let stdout = '';
  let stderr = '';
  service.stdout.setEncoding('utf8').on('data', chunk => { stdout += chunk; });
  service.stderr.setEncoding('utf8').on('data', chunk => { stderr += chunk; });
  t.after(() => service.kill('SIGTERM'));
  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error(`Bend listener did not start: ${stderr}`)), 10000);
    const poll = () => {
      if (stdout.includes('http://127.0.0.1:18773')) {
        clearTimeout(timeout);
        resolve();
      } else if (service.exitCode !== null) {
        clearTimeout(timeout);
        reject(new Error(`Bend listener exited (${service.exitCode}): ${stderr}`));
      } else {
        setTimeout(poll, 20);
      }
    };
    poll();
  });

  const request = async (path, body, headers = []) => new Promise((resolve, reject) => {
    const socket = connect(18773, '127.0.0.1');
    let response = '';
    socket.setEncoding('latin1');
    socket.on('connect', () => {
      const lines = [
        `POST ${path} HTTP/1.1`,
        'Host: 127.0.0.1:18773',
        'Connection: close',
        'Content-Type: application/json',
        ...headers,
        `Content-Length: ${Buffer.byteLength(body)}`,
        '',
        body,
      ];
      socket.write(lines.join('\r\n'));
    });
    socket.on('data', chunk => { response += chunk; });
    socket.on('end', () => resolve(response));
    socket.on('error', reject);
  });

  const actionBody = JSON.stringify([
    { url: 'http://127.0.0.1:18774/callback/0', arguments: [{ id: 0 }] },
    { url: 'http://127.0.0.1:18774/callback/1', arguments: [] },
  ]);
  const actionResponse = await request('/test', actionBody);
  assert.match(actionResponse, /^HTTP\/1\.1 200 /, actionResponse);
  assert.deepEqual(observations.map(x => x.path), ['/callback/0', '/callback/1']);
  assert.deepEqual(observations.map(x => JSON.parse(x.body)), [[{ id: 0 }], []]);
  assert.ok(observations.every(x => x.rawHeaders.some((v, i) =>
    v.toLowerCase() === 'content-type' && x.rawHeaders[i + 1] === 'application/json')));

  observations.length = 0;
  const relayResponse = await request('/relay', '{"probe":true}', [
    'TraceParent: first-parent-value',
    'TRACEPARENT: second-parent-value',
    'TrAcEsTaTe: one=1',
    'tracestate:\t two=2 \t',
  ]);
  assert.match(relayResponse, /^HTTP\/1\.1 200 /, relayResponse);
  assert.equal(observations.length, 1);
  const fields = new Map();
  for (let i = 0; i < observations[0].rawHeaders.length; i += 2) {
    const name = observations[0].rawHeaders[i].toLowerCase();
    fields.set(name, [...(fields.get(name) ?? []), observations[0].rawHeaders[i + 1]]);
  }
  assert.deepEqual(fields.get('traceparent'), ['first-parent-value', 'second-parent-value']);
  assert.deepEqual(fields.get('tracestate'), ['one=1', 'two=2']);
  assert.equal(observations[0].body, '{"probe":true}');

  observations.length = 0;
  const redirectResponse = await request('/test', JSON.stringify([
    { url: 'http://127.0.0.1:18774/redirect', arguments: [] },
  ]));
  assert.match(redirectResponse, /^HTTP\/1\.1 502 /, redirectResponse);
  assert.deepEqual(observations.map(x => x.path), ['/redirect']);
});

test('pinned native listener rejects a header block beyond its documented limit', async t => {
  const observer = createServer((request, response) => response.end('unexpected'));
  observer.listen(18774, '127.0.0.1');
  await once(observer, 'listening');
  t.after(() => observer.close());
  const service = spawn(servicePath, [], { stdio: ['ignore', 'ignore', 'pipe'] });
  let stderr = '';
  service.stderr.setEncoding('utf8').on('data', chunk => { stderr += chunk; });
  t.after(() => service.kill('SIGTERM'));
  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error(`Bend listener did not start: ${stderr}`)), 10000);
    const poll = () => {
      if (service.exitCode !== null) {
        clearTimeout(timeout);
        reject(new Error(`Bend listener exited (${service.exitCode}): ${stderr}`));
      } else {
        const probe = connect(18773, '127.0.0.1');
        probe.on('connect', () => {
          probe.destroy();
          clearTimeout(timeout);
          resolve();
        }).on('error', () => setTimeout(poll, 20));
      }
    };
    poll();
  });
  const socket = connect(18773, '127.0.0.1');
  let response = '';
  socket.setEncoding('latin1');
  socket.on('data', chunk => { response += chunk; });
  const completed = once(socket, 'end');
  await once(socket, 'connect');
  socket.write(`GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Large: ${'a'.repeat(70000)}\r\n\r\n`);
  await completed;
  assert.match(response, /^HTTP\/1\.1 431 /, response.slice(0, 200));

  const bodySocket = connect(18773, '127.0.0.1');
  let bodyResponse = '';
  bodySocket.setEncoding('latin1');
  bodySocket.on('data', chunk => { bodyResponse += chunk; });
  const bodyCompleted = once(bodySocket, 'end');
  await once(bodySocket, 'connect');
  bodySocket.write('POST /test HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 1048577\r\nConnection: close\r\n\r\n');
  await bodyCompleted;
  assert.match(bodyResponse, /^HTTP\/1\.1 413 /, bodyResponse.slice(0, 200));
});
