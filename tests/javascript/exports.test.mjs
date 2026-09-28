import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { webcrypto } from 'node:crypto';
import { root } from './compile.mjs';

const javascript = join(root, 'packages/trace-context/javascript');

// The functions and classes that a declaration file declares.
function declared(file) {
  const source = readFileSync(join(javascript, file), 'utf8');
  return [...source.matchAll(/^export (?:function|class) (\w+)/gm)].map((match) => match[1]).sort();
}

test('each entry declares exactly the functions and classes that it exports', async () => {
  for (const [module, declarations] of [['index.mjs', 'index.d.mts'], ['node.mjs', 'node.d.mts'],
    ['fetch.mjs', 'fetch.d.mts']]) {
    const exported = Object.keys(await import(join(javascript, module))).sort();
    assert.deepEqual(declared(declarations), exported, module);
  }
});

// The properties that each interface of a declaration file lists, and the
// kind that a handle's interface names in its Symbol.toStringTag.
function interfaces(file) {
  const source = readFileSync(join(javascript, file), 'utf8');
  return new Map([...source.matchAll(/^export interface (\w+)(?: extends [^{]+)? \{\n([\s\S]*?)^\}/gm)]
    .map(([, name, body]) => [name, {
      kind: /readonly \[Symbol\.toStringTag\]: '(\w+)'/.exec(body)?.[1] ?? null,
      properties: [...body.matchAll(/^ {2}readonly (\w+)\??:/gm)].map((match) => match[1]).sort(),
    }]));
}

test('each handle and result has exactly the properties that its declaration lists', async () => {
  const TC = await import(join(javascript, 'index.mjs'));
  const extraction = TC.extract([['traceparent', '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01'],
    ['tracestate', 'congo=t61rcWkgMzE']]);
  const service = TC.continueOrStart(extraction, { crypto: webcrypto });
  const local = TC.root({ crypto: webcrypto });
  const values = {
    Extraction: extraction, IncomingContext: extraction.incoming, ReceivedPair: extraction.incoming.received,
    LocalContext: local, OutgoingContext: TC.outgoing(local), Service: service,
    Sent: TC.send(service, [], { crypto: webcrypto }), Limits: TC.limits(), Injection: TC.inject(TC.outgoing(local), []),
  };
  const declared = interfaces('index.d.mts');
  for (const [name, value] of Object.entries(values)) {
    const { kind, properties } = declared.get(name);
    assert.deepEqual(Object.keys(value).sort(), properties, name);
    assert.equal(value[Symbol.toStringTag], kind ?? undefined, name);
  }
});

test('the package names a declaration file for each entry', () => {
  const { exports } = JSON.parse(readFileSync(join(root, 'packages/trace-context/package.json'), 'utf8'));
  for (const [entry, target] of Object.entries(exports)) {
    assert.match(target.types, /\.d\.mts$/, entry);
    assert.equal(target.types.replace(/\.d\.mts$/, '.mjs'), target.default, entry);
  }
});
