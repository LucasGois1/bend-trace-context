// The server recipes of JAVASCRIPT.md, as an application runs them:
// scripts/test-consumer.sh node extracts each into a fresh project that
// installed the facade and the frameworks, and BEND_RECIPES names that
// project's recipe files. Each recipe runs on its own port and calls an
// independent observer, which records the header lines as they arrive, and
// then a downstream service that cannot be reached. Expected values follow
// W3C Trace Context Level 2 and spec #1.
import assert from 'node:assert/strict';
import test from 'node:test';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { createServer } from 'node:http';
import { connect } from 'node:net';
import { basename, dirname } from 'node:path';

const recipes = (process.env.BEND_RECIPES ?? '').split(' ').filter((path) => path !== '');
const TRACEPARENT = '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01';

// The values of the context lines of a request's raw headers.
function lines(rawHeaders, name) {
  return rawHeaders.filter((item, index) => index % 2 === 1 && rawHeaders[index - 1].toLowerCase() === name);
}

async function observer() {
  const seen = [];
  const server = createServer((request, response) => {
    request.resume();
    request.on('end', () => {
      seen.push(request.rawHeaders);
      response.writeHead(200, { 'content-type': 'application/json' }).end('{"observed":true}');
    });
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  return { seen, url: `http://127.0.0.1:${server.address().port}/items`, close: () => server.close() };
}

// A port on which nothing listens.
async function closedPort() {
  const server = createServer();
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const { port } = server.address();
  server.close();
  await once(server, 'close');
  return port;
}

// Whether something listens on the port.
function listening(port) {
  return new Promise((resolve) => {
    const probe = connect(port, '127.0.0.1');
    probe.on('connect', () => { probe.destroy(); resolve(true); }).on('error', () => resolve(false));
  });
}

// Start a recipe on a free port and wait until it listens.
async function started(path, port, downstream) {
  const child = spawn(process.execPath, [basename(path)], {
    cwd: dirname(path), env: { ...process.env, PORT: String(port), DOWNSTREAM: downstream },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let output = '';
  child.stdout.setEncoding('utf8').on('data', (chunk) => { output += chunk; });
  child.stderr.setEncoding('utf8').on('data', (chunk) => { output += chunk; });
  const deadline = Date.now() + 15000;
  for (;;) {
    if (child.exitCode !== null) throw new Error(`${basename(path)} exited: ${output}`);
    if (await listening(port)) return child;
    if (Date.now() > deadline) throw new Error(`${basename(path)} did not start: ${output}`);
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
}

test('the recipes to check are given', () => {
  assert.ok(recipes.length > 0, 'BEND_RECIPES names no recipe');
});

recipes.forEach((path, index) => {
  test(`${basename(path)} continues or starts each request's trace downstream`, async (t) => {
    const downstream = await observer();
    t.after(() => downstream.close());
    const port = 18790 + index;
    const recipe = await started(path, port, downstream.url);
    t.after(() => recipe.kill('SIGTERM'));

    const traced = await fetch(`http://127.0.0.1:${port}/orders`, {
      method: 'POST', body: '{"order":1}',
      headers: { 'content-type': 'application/json', traceparent: TRACEPARENT, tracestate: 'congo=t61rcWkgMzE' },
    });
    assert.equal(traced.status, 200);
    assert.deepEqual(await traced.json(), { observed: true });
    const untraced = await fetch(`http://127.0.0.1:${port}/orders`, {
      method: 'POST', body: '{"order":2}', headers: { 'content-type': 'application/json' },
    });
    assert.equal(untraced.status, 200);

    assert.equal(downstream.seen.length, 2);
    const [first, second] = downstream.seen;
    const [child] = lines(first, 'traceparent');
    assert.match(child, /^00-4bf92f3577b34da6a3ce929d0e0e4736-[0-9a-f]{16}-01$/);
    assert.notEqual(child.split('-')[2], '00f067aa0ba902b7');
    assert.deepEqual(lines(first, 'tracestate'), ['congo=t61rcWkgMzE']);
    assert.equal(lines(second, 'traceparent').length, 1);
    assert.match(lines(second, 'traceparent')[0], /^00-[0-9a-f]{32}-[0-9a-f]{16}-02$/);
    assert.deepEqual(lines(second, 'tracestate'), []);
  });
});

recipes.forEach((path, index) => {
  test(`${basename(path)} answers 502 while downstream cannot be reached, and keeps serving`, async (t) => {
    const port = 18800 + index;
    const recipe = await started(path, port, `http://127.0.0.1:${await closedPort()}/items`);
    t.after(() => recipe.kill('SIGTERM'));
    for (const order of [1, 2]) {
      const answer = await fetch(`http://127.0.0.1:${port}/orders`, {
        method: 'POST', body: `{"order":${order}}`,
        headers: { 'content-type': 'application/json', traceparent: TRACEPARENT },
      });
      assert.equal(answer.status, 502);
    }
    assert.equal(recipe.exitCode, null);
  });
});
