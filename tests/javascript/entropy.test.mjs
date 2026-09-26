import assert from 'node:assert/strict';
import test from 'node:test';
import { webcrypto } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import entropy from '../../packages/trace-context/entropy/webcrypto.js';

const root = fileURLToPath(new URL('../../', import.meta.url));

function compileFixture(name) {
  const directory = join(root, 'build/effect-programs');
  mkdirSync(directory, { recursive: true });
  writeFileSync(join(directory, 'package.json'), '{"type":"commonjs"}\n');
  const output = join(directory, `${name}.js`);
  const compile = spawnSync(join(root, 'bend'), [
    `tests/javascript/fixtures/${name}.bend`, '-o', output,
  ], { cwd: root, encoding: 'utf8', timeout: 30000 });
  assert.equal(compile.status, 0, `${name}: ${compile.stdout}\n${compile.stderr}`);
  return output;
}

function runFixture(output, mode) {
  const args = mode ? [
    '--import', join(root, 'tests/javascript/fixtures/entropy-source.mjs'), output,
  ] : [output];
  return spawnSync(process.execPath, args, {
    cwd: root, encoding: 'utf8', timeout: 30000,
    env: mode ? { ...process.env, BEND_ENTROPY_CASE: mode } : process.env,
  });
}

test('the default source returns one real WebCrypto U32 without a uniqueness claim', () => {
  const result = entropy.readRandomU32();
  assert.equal(result.$, 'Done');
  assert.ok(Number.isInteger(result.value));
  assert.ok(result.value >= 0 && result.value <= 0xffffffff);
});

test('a compiled Bend consumer receives the real entropy Result', () => {
  const output = compileFixture('entropy-consumer');
  const result = runFixture(output);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout.trim(), /^done:\d+$/);
  for (const [mode, expected] of [
    ['fixed', 'done:4294967295'],
    ['unavailable', 'fail:1:unavailable'],
    ['quota', 'fail:2:source-failure'],
    ['type', 'fail:2:source-failure'],
    ['controlled', 'fail:2:source-failure'],
    ['getter', 'fail:2:source-failure'],
    ['invalid', 'fail:2:source-failure'],
  ]) {
    const controlled = runFixture(output, mode);
    assert.equal(controlled.status, 0, `${mode}: ${controlled.stderr}`);
    assert.equal(controlled.stdout.trim(), expected, mode);
  }
});

test('generated roots read the WebCrypto boundary and report structured failures', () => {
  const output = compileFixture('generation-consumer');
  const real = runFixture(output);
  assert.equal(real.status, 0, real.stderr);
  assert.match(real.stdout.trim(), /^created:00-[0-9a-f]{32}-[0-9a-f]{16}-02$/);
  for (const [mode, expected, reads] of [
    ['fixed', 'created:00-ffffffffffffffffffffffffffffffff-ffffffffffffffff-02', 6],
    ['zero', 'fail:ExhaustedTraceId', 32],
    ['third-fails', 'fail:SourceFailure 2 source-failure', 3],
    ['unavailable', 'fail:SourceFailure 1 unavailable', 0],
    ['quota', 'fail:SourceFailure 2 source-failure', 1],
    ['type', 'fail:SourceFailure 2 source-failure', 1],
    ['controlled', 'fail:SourceFailure 2 source-failure', 1],
    ['getter', 'fail:SourceFailure 2 source-failure', 0],
    ['invalid', 'fail:SourceFailure 2 source-failure', 1],
  ]) {
    const result = runFixture(output, mode);
    assert.equal(result.status, 0, `${mode}: ${result.stderr}`);
    assert.equal(result.stdout.trim(), expected, mode);
    assert.match(result.stderr, new RegExp(`entropy-reads=${reads}\\n`), mode);
  }
});

test('the pinned Base effect reproducibly exposes uncaught JS source failures', () => {
  const output = compileFixture('base-entropy');
  for (const [mode, error] of [
    ['unavailable', /ReferenceError/],
    ['quota', /QuotaExceededError/],
    ['type', /TypeMismatchError/],
    ['controlled', /controlled source failure/],
  ]) {
    const result = runFixture(output, mode);
    assert.equal(result.status, 1, mode);
    assert.equal(result.stdout, '', mode);
    assert.match(result.stderr, error, mode);
  }
});

test('actual WebCrypto quota errors become structured source failures', () => {
  let observed;
  const source = { getRandomValues() {
    try {
      return webcrypto.getRandomValues(new Uint8Array(65537));
    } catch (error) {
      observed = error.name;
      throw error;
    }
  } };
  assert.deepEqual(entropy.readRandomU32(source), {
    $: 'Fail', error: { $: 'Tuple', fst: 2, snd: 'source-failure' },
  });
  assert.equal(observed, 'QuotaExceededError');
});

test('unavailable global WebCrypto is a structured result', () => {
  const descriptor = Object.getOwnPropertyDescriptor(globalThis, 'crypto');
  try {
    delete globalThis.crypto;
    assert.deepEqual(entropy.readRandomU32(), {
      $: 'Fail', error: { $: 'Tuple', fst: 1, snd: 'unavailable' },
    });
  } finally {
    Object.defineProperty(globalThis, 'crypto', descriptor);
  }
});

test('provider success cannot forge an invalid U32', () => {
  for (const value of [undefined, null, -1, 0x100000000, 1.5, NaN, Infinity, '1', 1n]) {
    assert.deepEqual(entropy.readRandomU32({ getRandomValues: () => [value] }), {
      $: 'Fail', error: { $: 'Tuple', fst: 2, snd: 'source-failure' },
    });
  }
});

test('actual WebCrypto type errors become structured source failures', () => {
  let observed;
  const source = { getRandomValues() {
    try {
      return webcrypto.getRandomValues(new Float32Array(1));
    } catch (error) {
      observed = error.name;
      throw error;
    }
  } };
  assert.deepEqual(entropy.readRandomU32(source), {
    $: 'Fail', error: { $: 'Tuple', fst: 2, snd: 'source-failure' },
  });
  assert.equal(observed, 'TypeMismatchError');
});

test('controlled source errors, missing methods and malformed responses stay structured', () => {
  for (const source of [null, {}, { getRandomValues: 5 }]) {
    assert.deepEqual(entropy.readRandomU32(source), {
      $: 'Fail', error: { $: 'Tuple', fst: 1, snd: 'unavailable' },
    });
  }
  for (const source of [
    { getRandomValues() { throw new Error('controlled source failure'); } },
    { get getRandomValues() { throw new Error('controlled property failure'); } },
    { getRandomValues: () => undefined },
    { getRandomValues: () => null },
    { getRandomValues: () => [] },
    { getRandomValues: () => ({ get 0() { throw new Error('controlled result failure'); } }) },
  ]) {
    assert.deepEqual(entropy.readRandomU32(source), {
      $: 'Fail', error: { $: 'Tuple', fst: 2, snd: 'source-failure' },
    });
  }
});

test('accessing unavailable host state cannot escape before the error boundary', () => {
  const descriptor = Object.getOwnPropertyDescriptor(globalThis, 'crypto');
  try {
    Object.defineProperty(globalThis, 'crypto', {
      configurable: true,
      get() { throw new Error('controlled global lookup failure'); },
    });
    assert.deepEqual(entropy.readRandomU32(), {
      $: 'Fail', error: { $: 'Tuple', fst: 2, snd: 'source-failure' },
    });
  } finally {
    Object.defineProperty(globalThis, 'crypto', descriptor);
  }
});

test('an explicit source receives exactly one fresh word and retains its receiver', () => {
  const buffers = [];
  const source = { getRandomValues(words) {
    assert.equal(this, source);
    assert.ok(words instanceof Uint32Array);
    assert.equal(words.length, 1);
    buffers.push(words);
    words[0] = buffers.length === 1 ? 0 : 0xffffffff;
    return words;
  } };
  assert.deepEqual(entropy.readRandomU32(source), { $: 'Done', value: 0 });
  assert.deepEqual(entropy.readRandomU32(source), { $: 'Done', value: 0xffffffff });
  assert.equal(buffers.length, 2);
  assert.notEqual(buffers[0], buffers[1]);
});
