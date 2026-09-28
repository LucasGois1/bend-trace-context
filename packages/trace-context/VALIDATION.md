# Validation

This record describes what the package's tests cover, and the validation
runs made on a developer machine; CI runs the same gates on every commit.
[CONTRIBUTING.md](../../CONTRIBUTING.md#gates) shows how to run them.

## What the tests cover

The [public corpus](tests/TEST.bend) uses eight valid traceparent inputs, 26
malformed traceparent inputs with expected errors/positions, 14 malformed
supplied IDs, roots and children for all four known flag combinations, both
restart outcomes (`00` and `02`), and all 256 flag bytes. For each flag byte
it checks the codec, the received sampled and random bits and the flags a child
emits against independent numeric oracles. The [negative fixtures](tests/reject)
must fail typechecking for the intended nonzero, length and remote/local
mismatch.

The [tracestate corpus](tests/TRACESTATE.bend) uses literal fixtures for keys
and values at every character-class boundary and length limit, optional
whitespace, empty members, member errors and their numbers, duplicates,
exactly 32 and 33 members, repeated fields, every limit rule, and inputs at and
past the budget with one-, two-, three- and four-octet characters, up to a
mebibyte that must be refused without being read. It also parses the largest
valid state, 16447 octets, within the default budget.

The [outgoing corpus](tests/OUTGOING.bend) sets and removes entries of
literal states, including full states that must evict nothing or exactly the
last entry, checks emitted sizes, and truncates states at 512 and 513 octets,
with entries of 128 and 129 octets, several large entries, a single entry
larger than the budget and a larger configured budget, checking the entries
kept and the keys dropped. It also emits outgoing contexts for a root and for
a child of a received context.

The [extraction corpus](tests/EXTRACT.bend) uses the inputs of the pinned W3C
harness for field names, repeated fields, versions, IDs, flags and
whitespace. It checks the precedence of a message's context over the base,
repeated traceparent fields apart and joined by a host, the combination,
discard and neglect of tracestate fields, strict version 00, `ff` and later
versions with and without unknown fields, control characters in those fields
at each edge of their range, the exact traceparent budget with
one-, two- and three-octet characters and a mebibyte refused without being
read, the tracestate budget with its joining commas, a carrier of 100000
fields, incoming and base contexts and their parents and states, and
diagnostics that never contain the received values.

The [injection corpus](tests/INJECT.bend) cleans and injects into carriers
with old context fields in every case, lookalike names and unrelated fields,
for roots, children of a context with every flag bit set, empty and truncated
states, and repeated injection. It forwards a later version with unknown
fields, every flag bit set and whitespace around it, whose three tracestate
fields, one of them empty, are joined as they came; a version 00 with
reserved flag bits; empty and discarded states; joined tracestates of 512 and
513 octets; [spec #1](https://github.com/LucasGois1/bend-trace-context/issues/1)'s
600-octet state under the default and a larger output
budget; and pairs built directly that forwarding must refuse, a line break
in a later version's unknown fields among them. It extracts again the
carriers of three injections and of a forwarding, and it handles carriers of
100000 fields and values of 32 KiB.

The [continue-or-start corpus](tests/CONTINUE.bend) replays tapes through
both operations. It continues a message's context and, without a usable
traceparent, a base of this service and a context received earlier; it
starts roots and restarts, with and without a sampling override, and at a
boundary replaces the message's context, a base of this service and a
context received earlier with trace IDs other than theirs; and it meets a
source failure and exhausted candidates under both policies. It sends a
fan-out of three requests with different span IDs into a reused container,
puts the service's own entry first, and checks what a message carries when
no operation can be generated: the received pair forwarded, and no context
at a boundary, for a root, for a base, after a discarded state and for
spec #1's 600-octet state. Each case checks how many words were left unread,
and the diagnostics, truncation included, contain no received value.

The [native HTTP header corpus](tests/NATIVE-HTTP.bend) reads received header
maps with repeated traceparent and tracestate values, writes carriers with
repeated and mixed-case names back into maps, and runs both shortcuts over
replayed tapes: a continued request, a child sent in place of a reused
container's old context fields, whatever the case of their names, the
forwarded pair, the cleared fields and a strict failure.

The [propagation qualification](../../scripts/qualify-propagation.sh) takes a
service and the gateway example from a pinned checkout of the repository, as
an application would: in `native` mode it builds them on the adapter and
runs them over bend-kit's real transport, and in `node` mode it installs
the [JavaScript facade](JAVASCRIPT.md) into a Node service and runs them over
`node:http`. Its own checks, against an independent Node observer, cover:

- sampled `0` and every combination of the sampled and random-trace-id flags;
- roots, restarts and fan-out;
- repeated injection into reused containers with stale context fields;
- a discarded state, with diagnostics that hold no received value;
- source failures for the service's operation and for each child, and
  exhausted candidates, which forward the received pair or clear the
  context;
- strict refusals;
- the gateway example.

In both modes it then runs the W3C harness at commit `acab820` with
`SPEC_LEVEL=2` and `STRICT_LEVEL=2`: `TraceContextTest`, `AdvancedTest` and
`TraceContext2Test`, 41 tests, of which none may fail, error or be
skipped. Passing this finite harness shows interoperability in the scenarios
it runs, not conformance to the whole W3C publication.

The [generation corpus](tests/GENERATION.bend) replays tapes through the public
operations: conversion vectors in decimal for the W3C example words, the digit
order within a word, zero then valid candidates, eight zero candidates with
no ninth read, a 48-word worst case, a source error in the middle of a
candidate, an empty tape, a
child that must not reuse the parent's span ID and a restart that must not
reuse the received trace ID, each checking how many words were left unread.
The [smoke check](tests/SMOKE.bend), the
[generation example](examples/generate.bend) and the
[continue example](examples/continue.bend) generate on the real host source;
they check only that the results are well formed and that generated IDs are
new where they must be. The JavaScript suite runs a compiled
root through WebCrypto with real host exceptions and counts the words read,
and runs the facade's generations on deterministic sources, counting the
words they read, and on actual WebCrypto exceptions.
[CONTRIBUTING.md](../../CONTRIBUTING.md#gates) describes the commands that
run them, and the separate clean consumer.

## JavaScript

The [JavaScript guide](JAVASCRIPT.md) describes the facade; these tests
qualify it, its WebCrypto source and Bend programs compiled to JavaScript.

- `tests/javascript/facade.test.mjs` exercises the facade with independent
  vectors from W3C Trace Context Level 2 and spec #1:
  - deterministic sources whose reads it counts;
  - forged handles and malformed inputs;
  - the lenient and strict policies under actual WebCrypto
    `QuotaExceededError` and `TypeMismatchError` exceptions, an unavailable
    source and exhausted candidates;
  - the worst-case word budgets of 48 and 16 words;
  - every flag byte, 32 and 33 tracestate members, and octet budgets with
    multibyte characters;
  - supplied identifiers, limits, tracestate edits, injection, forwarding and
    cleanup;
  - arguments read once, even through getters;
  - a message of ten thousand fields;
  - what the compiler's modules export, and the absence of any system
    binding, which it traps while the facade works.
- `tests/javascript/node-http.test.mjs` runs `node:http` servers against an
  independent observer that records header lines as they arrive, and checks
  `fetch`, `tracedFetch` and `documentFields` outside a page as well.
- `tests/javascript/entropy.test.mjs` checks the shared WebCrypto source, and
  compiles a generated root to JavaScript and runs it on real WebCrypto, on
  each induced host failure, reported as a structured `SourceFailure`
  without fallback, on constant providers and on a provider that fails at
  the third word. It counts the words read: six for a root, 32 before
  exhaustion when every word is zero, and three when the third fails.
- `tests/javascript/exports.test.mjs` requires each entry's declaration file
  to declare exactly the functions and classes that the entry exports, and
  each handle to have exactly the properties that its declaration lists.
- `tests/browser/fetch.spec.mjs` runs the bundled Fetch page in each engine.
  The page's server renders its context as `<meta>` elements, and an
  independent observer on another origin records header lines and
  preflights. It covers:
  - generation through WebCrypto;
  - same-origin and cross-origin calls that replace stale fields;
  - values joined by `Headers`, and repeated or differently cased elements;
  - allowed, unlisted and refused cross-origin calls, and origins allowed by
    a `RegExp`;
  - `no-cors`, redirects, `Request` inputs and a page without an origin of
    its own;
  - actual WebCrypto exceptions under both policies;
  - intact forwarding;
  - the example page's buttons;
  - forged values and invalid arguments, refused before any request.
- `tests/browser/codec.spec.mjs` runs the inspector page, and
  `tests/browser/entropy.spec.mjs` the shared source on a test page,
  `tests/browser/pages/entropy.html`, on real WebCrypto and its actual
  exceptions in each engine.

  `./scripts/qualify-js.sh browser` also bundles the pages a second time and
  requires identical files, and bundles a copy of the sources at another
  path and requires the same scripts.
- `./scripts/test-consumer.sh browser` installs the facade from a fresh
  pinned clone into an independent page,
  [`tests/consumer/browser`](../../tests/consumer/browser/page.mjs), which it
  bundles twice with the clone's bundler and requires identical bundles, and
  into the page of the root README's
  [browser quick start](../../README.md#quick-start-browser-page), served by
  the server of [Serving a page](JAVASCRIPT.md#serving-a-page). It runs both
  in the three engines, against the observer and the output that the README
  shows, and checks that the quick start's request belongs to the trace that
  the server rendered, with a span ID of its own.
- `./scripts/test-consumer.sh node` installs the facade from a fresh pinned
  clone into an independent application, which links the recipes'
  frameworks and TypeScript from the repository's locked tooling. It runs [`tests/consumer/facade.mjs`](../../tests/consumer/facade.mjs),
  the [root README example](../../README.md#quick-start-javascript) and the
  JavaScript guide's log correlation, OpenTelemetry and inspection programs
  against the output that the documents show. It runs the
  [server recipes](JAVASCRIPT.md#recipes) against an independent observer,
  [`tests/consumer/recipes.mjs`](../../tests/consumer/recipes.mjs), with a
  traced request, an untraced one and an unreachable downstream each. It
  checks the declarations with TypeScript 5.9.3 and 7.0.2: on
  [`tests/consumer/types.ts`](../../tests/consumer/types.ts) and the guide's
  TypeScript example without the DOM library, and on
  [`tests/consumer/fetch-types.ts`](../../tests/consumer/fetch-types.ts) with
  it.
- `./scripts/qualify-propagation.sh node` installs the facade from a pinned
  checkout into the Node propagation service,
  [`tests/propagation/service.mjs`](../../tests/propagation/service.mjs), as
  an application would, and runs the propagation checks, the gateway example
  and the W3C harness, as for native services above.

CI runs the Node checks on Node 22 and 24, and the browser checks in the
three engines. Diagnostics, exact package, compiler and host versions, TAP
results, browser JSON results and failure traces are kept under
`build/javascript/`, and CI keeps them for 14 days. Random smoke checks
establish only execution and the returned range, not uniqueness or
cryptographic strength.

### The WebCrypto source

The facade and the Bend programs compiled to JavaScript read their words
through one source, [`entropy/webcrypto.js`](entropy/webcrypto.js), which
applications reach only through the facade's `crypto` option.
`readRandomU32(provider?)` requests one word from `getRandomValues` on a
fresh `Uint32Array(1)`, from `globalThis.crypto` when called or from the
provider. Zero is valid at this boundary: ID validation and the bounded
candidate rules belong to generation.

| Result | Meaning |
| --- | --- |
| `{ $: 'Done', value: number }` | An integer in `0..4294967295` |
| `{ $: 'Fail', error: { $: 'Tuple', fst: 1, snd: 'unavailable' } }` | Missing source or `getRandomValues` method |
| `{ $: 'Fail', error: { $: 'Tuple', fst: 2, snd: 'source-failure' } }` | Host lookup or call failure, or an invalid returned word |

Bend programs compiled to JavaScript call it through the package's
[`entropy.bend`](entropy.bend) effect, whose native twin,
[`entropy/native.c`](entropy/native.c), reads one word from the primitive
that Base's `IO.random_u32` uses: `arc4random_buf` on macOS, which cannot
fail, and `getrandom` on Linux, which returns its error as `Fail` with the
`errno` and its `strerror` text. The tests do not induce that native
failure. Both files register the effect as the pinned compiler's
[effect guide](https://github.com/bendlang/bend/blob/573002f01ec6c52416d44489543f69a9625facf8/guide/EFFECTS.md)
describes, with `io_eff(CID(read_u32), ...)`, on runtime interfaces that
carry no compatibility promise, so a compiler update must requalify them.

The JavaScript file uses CommonJS because Bend runs a foreign effect's file
as a script in a closure of its own, where ESM declarations are invalid.
Node and the official browser bundler import that same file, where no
effect exists to register.

The pinned Base [`random_u32.js`](https://github.com/bendlang/bend/blob/573002f01ec6c52416d44489543f69a9625facf8/bend2/effs/random_u32.js)
lets WebCrypto exceptions escape instead of returning its declared `Fail`.
The [reproducer](../../tests/javascript/fixtures/base-entropy.bend) and the
[tests](../../tests/javascript/entropy.test.mjs) show that behavior
alongside the package's source, whose Bend continuation receives `Done` or
`Fail`; the package does not rely on Base's.

### Reproducing the JavaScript qualification

```sh
npm ci --ignore-scripts
./scripts/qualify-js.sh node
./scripts/test-consumer.sh node
./scripts/qualify-propagation.sh node
npx --no-install playwright install chromium firefox webkit
npm run build:browser
./scripts/qualify-js.sh browser
./scripts/test-consumer.sh browser
```

`./scripts/qualify-propagation.sh node` also needs Python 3.13 for the
harness, whose aiohttp version and hashes `tests/propagation/requirements.txt`
pins. On Linux CI, Playwright uses `install --with-deps` for its system
libraries. Playwright is locked to `1.63.0` in `package-lock.json`, and its
browser builds are recorded with each test.

## 2026-09-28 — User documentation, macOS ARM64

The completion of the user documentation ran every repository gate from the
repository root, on the same machine and versions as the record below, and
with TypeScript 5.9.3 and 7.0.2.

| Gate | Result |
| --- | --- |
| `./scripts/validate.sh native` and `node` | as below |
| `./scripts/test-installer.sh` | 9 installer cases pass |
| `./scripts/qualify-js.sh node` | the committed ES module is the pinned compiler's build; 47 tests, none failed or skipped |
| `./scripts/qualify-js.sh browser` | 75 tests in Chromium, Firefox and WebKit; a rebuild is byte-identical, and a relocated build gives the same scripts |
| `./scripts/test-consumer.sh native`, `node` and `browser` | the independent consumer, every program of the README and the guides, 9 recipe tests, the declarations with both TypeScript versions, and the independent page and the README's browser quick start in the three engines, from a fresh clone |
| `./scripts/qualify-native-http.sh` | 2 transport tests on `bend-kit-http` 0.23.0.1 |
| `./scripts/qualify-propagation.sh native` and `node` | 13 propagation checks, the gateway check with a traced and an untraced request, and the W3C harness: 41 tests, none failed or skipped |

## 2026-09-28 — Bend 2.0.32, macOS ARM64

The move to Bend 2.0.32, at commit `45604de`, ran every repository gate from
the repository root, on macOS 26.7 ARM64 with Apple clang 21, Node 24.16.0, Python 3.13 and
Playwright 1.63.0. CI runs the same gates on Linux x86_64 and on Node 22 and
24 for each commit, and records their exact versions.

| Gate | Result |
| --- | --- |
| `./scripts/validate.sh native` and `node` | `PROOF.bend` prints `ALL PROOFS CHECK`; the host operations of `generation.bend`, and only those, rely on foreign code; the static rejections, corpora and examples give their expected outputs |
| `./scripts/test-installer.sh` | 9 installer cases pass |
| `./scripts/qualify-js.sh node` | the committed ES module is the pinned compiler's build; 43 tests, none failed or skipped |
| `./scripts/qualify-js.sh browser` | 75 tests in Chromium, Firefox and WebKit; a rebuild is byte-identical, and a relocated build gives the same scripts |
| `./scripts/test-consumer.sh native`, `node` and `browser` | the independent consumer, the README programs, the facade and the page from a fresh clone; the page's bundle is reproducible |
| `./scripts/qualify-native-http.sh` | 2 transport tests on `bend-kit-http` 0.23.0.1 |
| `./scripts/qualify-propagation.sh native` and `node` | 13 propagation checks, the gateway check and the W3C harness: 41 tests, none failed or skipped |

The facade's tests also pass on Node 22.17.1, 22.18.0 and 24.0.0. Bend's
`--verdict` does not cover the package yet, as the
[package reference](README.md#proofs) explains.

## 2026-09-24 — Bend 2.0.27, macOS ARM64

The first validation of the codec. The results below correspond to the final
ID representation: an `evidence` field is available for composing proofs.
Run the commands from the repository root. Bend 2.0.32 prints
`ALL PROOFS CHECK` where 2.0.27 printed `All terms check.`.

### Proofs

```sh
./bend packages/trace-context/PROOF.bend --check-only
```

Result: `All terms check.`, exit status 0, with no `@unsafe` dependency warning.
The gate imports proofs for hexadecimal, indexed sequences, strings, sequence
reading and the complete context. Public laws: length 55 and
`parse(format(context)) == Done{context}` for any typed context.

### Tests and consumer

```sh
./bend packages/trace-context/tests/TEST.bend
./bend packages/trace-context/examples/demo.bend
./bend packages/trace-context/tests/TEST.bend -o build/trace-context-test.js
node build/trace-context-test.js
./bend packages/trace-context/tests/TEST.bend -o build/trace-context-test
./build/trace-context-test
./bend packages/trace-context/examples/demo.bend -o build/trace-context-demo.js
node build/trace-context-demo.js
./bend packages/trace-context/examples/demo.bend -o build/trace-context-demo
./build/trace-context-demo
```

All passed with exit status 0. In a fresh checkout, create `build/` before
compiling; generated artifacts stay out of Git.

The suite contains 8 explicit valid inputs, 26 invalid inputs with expected
errors/positions and all 256 flag values, and also checks the literal
hexadecimal alphabet. The `sampled` oracle uses a numeric counter independent
of the package function. All three execution modes produced:

```text
OK: W3C example and reserved flag bits
OK: lengths, suffixes and version policy
OK: lowercase ASCII alphabet and character offsets
OK: separators and nonzero IDs
OK: all 256 flag bytes preserve format and sampled bit
```

The separate consumer produced this output in all three modes:

```text
00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01
sampled: True
```

### Expected static rejections

These commands **must exit with status 1**:

```sh
./bend packages/trace-context/tests/reject/zero_id.bend --check-only
./bend packages/trace-context/tests/reject/wrong_length.bend --check-only
```

The first was rejected with `expected: True{}` / `observed: False{}` when trying
to supply `{==}` for a zero ID. The second was rejected for supplying
`Digits.Nil` where `Digits.Con<0n>` was required. We use two positions to keep
the examples readable; these are the same type families used for 32- and
16-position IDs.

### Scope

We did not run the complete W3C HTTP suite, GPU execution, other operating
systems, benchmarks or performance assessments. The current consumer is local,
without HTTP package integration yet. The universal inverse property, covering
every accepted text, was then a future obligation; it has since been proved in
[#5](https://github.com/LucasGois1/bend-trace-context/issues/5) and is listed
in the [package reference](README.md#proofs).
