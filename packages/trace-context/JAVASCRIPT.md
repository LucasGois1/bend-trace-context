# JavaScript and browser qualification

This slice qualifies the existing strict v00 codec as an imported pure Bend
module, plus a shared WebCrypto source and an explicit Bend JavaScript effect.
Bend programs compiled to Node also generate contexts through that effect, as
described in the [package reference](README.md#generated-contexts). A
JavaScript facade for generation, Fetch/HTTP propagation and a complete
JavaScript SDK remain in issues
[#13](https://github.com/LucasGois1/bend-trace-context/issues/13) and
[#14](https://github.com/LucasGois1/bend-trace-context/issues/14).

## Install and run

Use an exact repository commit as described in the [root README](../../README.md).
From that checkout, use Node 22 or 24 and run:

```sh
./scripts/setup-bend.sh
./scripts/setup-bend-source.sh
npm ci --ignore-scripts
node --import ./.tools/bend-source-2.0.27/bend2/main.ts examples/javascript/node.mjs
```

The output is:

```json
{"ok":true,"traceparent":"00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01","sampled":true}
```

The Node loader is the unmodified official
[`bend2/main.ts`](https://github.com/bendlang/bend/blob/63bee70b55a71024d6bdcb49a745111bc54b114e/bend2/main.ts).
The binary archive omits this TypeScript source. The separate source installer
fetches and verifies release commit `63bee70b55a71024d6bdcb49a745111bc54b114e`;
it refuses existing divergent destinations. No Bun installation is needed for
the Node loader or the release binary. Current Node 22/24 patch versions are
required because Node runs the loader's TypeScript directly; older patch versions
are not qualified. CI records the exact versions used.

For a browser application, use the official Bend HTML build path:

```sh
./bend examples/javascript/index.html -o build/browser
node tests/browser/server.mjs
```

Open `http://127.0.0.1:4173/` and inspect a traceparent. Stop the local server
before running browser tests. The
[page](../../examples/javascript/index.html) imports the same
[codec adapter](javascript/codec.mjs) used by Node. Bend bundles the real
`.bend` module; no JavaScript codec is maintained separately. A compiled CLI
program is not treated as a browser module, and the HTML bundle's script is not
used as a Node library export.

## Foreign values and proof scope

`inspectTraceparent(value)` accepts only a primitive JavaScript string. It returns:

- `{ ok: true, traceparent: string, sampled: boolean }` on success, preserving
  every flag bit according to the strict codec.
- `{ ok: false, error: string }` on failure. Non-string values produce
  `InvalidInputType`; malformed strings use the Bend codec's [error names](README.md).

Numbers, arrays, boxed strings and tagged constructor objects are rejected
without coercion. Parsing, formatting, nonzero-ID checks and sampled-bit
inspection run in the existing Bend implementation. Its dependent values remain
inside the adapter; foreign callers receive ordinary wire data and metadata.

The raw Bend loader exports compiler representations, including tagged objects
and erased proof fields. A JavaScript object shaped like `TraceParentV00` with
`evidence: null` is not evidence of validity. Do not pass foreign tagged values
to typed internal functions. Future lifecycle adapters must accept validated
wire/scalar inputs and return values constructed by Bend, rather than trusting
an external object's shape or a previously returned mutable object.

Existing Bend round-trip, fixed-length and inverse accepted-text proofs still
apply to their typed domain. The JavaScript guard and host effects are tested
foreign-code boundaries; they are not additional formal proofs.

## WebCrypto and explicit effects

JavaScript consumers can import the shared source:

```js
import entropy from './packages/trace-context/entropy/webcrypto.js';
const result = entropy.readRandomU32();
```

`readRandomU32(provider?)` requests one word from `getRandomValues` on a fresh
`Uint32Array(1)`. By default it resolves `globalThis.crypto` when called. An
explicit provider has the same `getRandomValues(array)` interface; it is useful
for integration and deterministic tests. Passing `null` models unavailability.
Providers are trusted to supply entropy: validating a returned integer cannot
prove its cryptographic origin. There is no time, counter or `Math.random`
fallback, and no implicit retries. Zero is valid at this source boundary: ID
validation and the bounded candidate rules belong to generation.

| Result | Meaning |
| --- | --- |
| `{ $: 'Done', value: number }` | An integer in `0..4294967295` |
| `{ $: 'Fail', error: { $: 'Tuple', fst: 1, snd: 'unavailable' } }` | Missing source or `getRandomValues` method |
| `{ $: 'Fail', error: { $: 'Tuple', fst: 2, snd: 'source-failure' } }` | Host lookup/call failure or an invalid returned word |

Bend programs compiled to JavaScript call the same implementation through the
explicit [`entropy.bend`](entropy.bend) effect:

```bend
import Base
import ./packages/trace-context/entropy.bend as Entropy

def display(result: Result<&1, &1, U32 & String, U32>) -> IO(Unit):
  match result:
    case Done{word}:
      IO.print(U32.show(word))
    case Fail{(code, message)}:
      IO.print(message)

def main() -> IO(Unit):
  do IO<Unit>:
    result : Result<&1, &1, U32 & String, U32> <- Entropy.read_u32()
    display(result)
```

Save this as `entropy-example.bend` at the repository root, then run
`./bend entropy-example.bend -o build/entropy-example.cjs` followed by
`node build/entropy-example.cjs`.

The same effect has a native twin, [`entropy/native.c`](entropy/native.c), which
reads one word from the host primitive Base's `IO.random_u32` uses:
`arc4random_buf` on macOS, which cannot fail, and `getrandom` on Linux,
returning its error as `Fail` with the `errno` and its `strerror` text. The
tests do not induce that native failure. The twin uses the pinned compiler's
documented [C effect interface](https://github.com/bendlang/bend/blob/63bee70b55a71024d6bdcb49a745111bc54b114e/guide/EFFECTS.md),
so a compiler update must requalify it.

The shared JavaScript file uses CommonJS because Bend embeds foreign effect
functions in a generated closure, where ESM declarations are invalid. Node and the official
browser bundler import that same file. Its conditional `module.exports` also
assigns unused exports inside a compiled CLI; that CLI has no library interface.

The pinned Base [`random_u32.js`](https://github.com/bendlang/bend/blob/63bee70b55a71024d6bdcb49a745111bc54b114e/bend2/effs/random_u32.js)
lets WebCrypto exceptions escape instead of returning its declared `Fail`.
The [reproducer](../../tests/javascript/fixtures/base-entropy.bend) and the
[qualification tests](../../tests/javascript/entropy.test.mjs) demonstrate that
behavior alongside the package adapter, whose Bend continuation receives
`Done` or `Fail`. This adapter resolves the qualification requirement without
patching the compiler; it does not qualify Base's uncaught failure behavior as
supported. [Generation](README.md#generated-contexts) reads its words through
this adapter. The qualification tests compile a generated root to JavaScript
and run it on real WebCrypto, on each induced host failure (reported as a
structured `SourceFailure` without fallback), on constant providers and on a
provider that fails at the third word, counting the words read: six for a
root, 32 before exhaustion when every word is zero, and three when the third
fails. Browser generation remains in
[#14](https://github.com/LucasGois1/bend-trace-context/issues/14).

## Reproduce the qualification

```sh
./scripts/qualify-js.sh node
npx --no-install playwright install chromium firefox webkit
npm run build:browser
./scripts/qualify-js.sh browser
./tests/installer-source/test.sh
```

On Linux CI, Playwright uses `install --with-deps` for its system libraries.
Playwright is locked to `1.63.0` in `package-lock.json`; its browser builds are
recorded with each test. Node 22 and 24 run the module and actual compiled Bend
effect consumers. Chromium, Firefox and WebKit run the bundled page and shared
source. The required aggregate CI gate includes every target and rejects skips.

Tests exercise genuine WebCrypto success and native `TypeMismatchError` and
`QuotaExceededError` exceptions induced through providers calling the real host
API with invalid buffers. Separate fixtures remove the host global or inject
controlled provider failures. Random smoke checks establish only execution and
the returned range, not uniqueness or cryptographic strength.

Diagnostics, exact package/compiler/host versions, TAP results, browser JSON
results and failure traces are retained under `build/javascript/`; source
installer reports use `build/installer-source/`. CI artifacts expire after
14 days. Generated programs and downloaded tools are excluded from those
reports. Advertised qualification requires a successful run for the exact
candidate; workflow configuration alone is not evidence of success.
