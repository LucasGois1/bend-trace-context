# JavaScript

The package's JavaScript facade gives a Node application the package's
operations:

- extraction;
- continuing or starting a service's operation, and sending;
- injection, forwarding and context cleanup;
- tracestate edits;
- generation, with WebCrypto as the identifier source and explicit failure
  policies, and operations with identifiers that the application supplies.

Its `node:http` integration reads received requests and writes the headers of
requests to send. Every Trace Context rule runs in the Bend package, the same
[`trace_context.bend`](trace_context.bend) that native programs use. The
facade converts JavaScript values at the boundary, feeds WebCrypto words to
the package's generation machine, and wraps the package's values in
[handles](#handles). It is qualified on Node 22 and 24. Browser generation
and propagation belong to
[#14](https://github.com/LucasGois1/bend-trace-context/issues/14).

This guide also covers the [codec adapter](#codec-adapter-and-foreign-values),
the [WebCrypto source](#webcrypto-and-explicit-effects) and their browser
qualification.

## Install and run

An application uses an exact commit of this repository, as the
[root README](../../README.md#from-javascript) shows:

```sh
mkdir -p deps
git clone https://github.com/LucasGois1/bend-trace-context.git deps/bend-trace-context
git -C deps/bend-trace-context checkout --detach FULL_COMMIT_SHA
./deps/bend-trace-context/scripts/setup-bend-source.sh
npm install ./deps/bend-trace-context/packages/trace-context
```

`setup-bend-source.sh` installs the official Bend module loader,
[`bend2/main.ts`](https://github.com/bendlang/bend/blob/63bee70b55a71024d6bdcb49a745111bc54b114e/bend2/main.ts)
of release commit `63bee70b55a71024d6bdcb49a745111bc54b114e`, into the
checkout. It verifies the commit and refuses an existing destination that
differs from it. The loader compiles `.bend` files when they are imported, so
the facade needs neither the Bend binary nor Bun. `npm install` links the
package directory into `node_modules` as `bend-trace-context`; the package
has no dependencies. Run the application with the loader:

```sh
node --import ./deps/bend-trace-context/.tools/bend-source-2.0.27/bend2/main.ts main.mjs
```

The package offers two entries:

- `bend-trace-context`: the facade;
- `bend-trace-context/node`: the [`node:http` integration](#node-http-integration).

Both are ES modules.

A service handles each request in three steps:

```js
import http from 'node:http';
import * as TC from 'bend-trace-context';
import { continueOrStartRequest, requestHeaders } from 'bend-trace-context/node';

http.createServer((request, response) => {
  const service = continueOrStartRequest(request);
  const sent = TC.send(service, [['content-type', 'application/json']]);
  const call = http.request('http://inventory.internal/items',
    { method: 'POST', headers: requestHeaders(sent.fields) }, (answer) => answer.pipe(response));
  call.on('error', () => {
    response.writeHead(502);
    response.end();
  });
  call.end(JSON.stringify({ order: 1 }));
}).listen(8080);
```

The [gateway example](examples/gateway.mjs) is a complete service, described
[below](#gateway-walkthrough).

## Facade reference

Values cross the boundary as ordinary JavaScript data:

- the fields of a message are an array of `[name, value]` string pairs in the
  message's order, the package's carrier;
- wire text, such as traceparent and tracestate values, is a string;
- diagnostics are the package's names, such as
  `TraceParentAccepted, StateAccepted` or `Untraced SourceFailure 2 source-failure`.

Diagnostics contain no received value. Every function takes its options as an
optional last argument.

### Receiving and sending

```js
extract(fields, { limits, base }) -> Extraction
continueOrStart(extraction, { reception, sampling, policy, crypto }) -> Service
send(service, fields, { limits, sampling, policy, crypto }) -> Sent
```

- `extract` reads the context of a received message, as
  [`Context.extract`](README.md#extracting-context) does. `base`, an
  `IncomingContext` or `OutgoingContext`, is kept when the message has no
  usable traceparent.
- `continueOrStart` gives the service its own operation for the message, as
  [`Context.continue_or_start`](README.md#continuing-or-starting-a-trace)
  does:
  - a child of the context that extraction kept, with its state;
  - a root when extraction kept none;
  - with `reception: 'restart'`, a new trace in place of the kept context, as
    at a trust boundary.
- `send` gives one message that the service sends an operation of its own: a
  new child of the service's operation, injected into the message's own
  fields. The old context fields go and the new ones come last. When no child
  can be generated, the message forwards the received pair unchanged if it
  can, and carries no context fields otherwise. Call it once for each
  message: each request of a fan-out gets a child of its own.

| Option | Values | Default |
| --- | --- | --- |
| `reception` | `'continue'`, or `'restart'` at a trust boundary | `'continue'` |
| `sampling` | `'inherit'`: a child inherits its parent's sampled flag, and a root or a restart takes the root default, not sampled; `'sampled'` or `'unsampled'` sets it | `'inherit'` |
| `policy` | `'lenient'`, or `'strict'` (see [Failure handling](#failure-handling)) | `'lenient'` |
| `crypto` | An object with WebCrypto's `getRandomValues`, such as `node:crypto`'s `webcrypto`; `null` models an unavailable source. Any other value is a `TypeError` | `globalThis.crypto`, when called |
| `limits` | A `Limits` handle from `limits()` | the package's defaults |

### Handles

A handle is a frozen object that only the facade creates, with the package
value it stands for kept in a module-private `WeakMap`. Its kind is named
after the package's type, and its properties are plain data. A function that takes a handle refuses any other object with a
`TypeError`, including a copy of a handle, an object that inherits from one,
and a tagged object shaped like the package's own values. JavaScript code
therefore cannot build a context, a service or a limit that the package's
constructors did not check.

| Handle | Properties |
| --- | --- |
| `Extraction` | `show`, the log line of both outcomes; `parent`, the traceparent outcome; `state`, the tracestate outcome; `incoming`, the message's `IncomingContext` or `null`; `context`, the `IncomingContext` or `OutgoingContext` that extraction kept, the message's or the base, or `null` |
| `IncomingContext` | `traceId`, `spanId`, the sender's span ID, `sampled` and `random`; `tracestate`, the normalized state received with it; `received`, the accepted pair `{ traceparent, tracestate }`, the tracestate as an array of the field values as they came, or `null` when the tracestate was discarded |
| `LocalContext` | an operation of this participant: `traceparent`, its participating value; `traceId`, `spanId`, `sampled` and `random` |
| `OutgoingContext` | `context`, a `LocalContext`; `tracestate`, the normalized state that it sends, before truncation |
| `Service` | `show`; `origin`, `'Continued'`, `'Started'`, `'Restarted'` or `null`; `error`, why it has no operation, or `null`; `outgoing`, its `OutgoingContext` or `null` |
| `Sent` | `fields`, the fields to send the message with, in every case; `show`; `operation`, its new `LocalContext` or `null`; `error`, why none was generated, or `null`; `dropped`, the tracestate keys that truncation to the output budget removed |
| `Limits` | `traceparentInput`, `tracestateInput` and `tracestateOutput`, in UTF-8 octets |

`Service.show` and `Sent.show` name what happened, for a log line:
`Continued`, `Untraced SourceFailure 2 source-failure`, `Fresh, truncated` or
`NoContext after ExhaustedSpanId, NothingKept`. The package's
[tables](README.md#continuing-or-starting-a-trace) define each name.

### Generation

```js
root({ crypto }) -> LocalContext
child(parent, { sampling, crypto }) -> LocalContext
restart(previous, { crypto }) -> LocalContext
```

`parent` is an `IncomingContext` or a `LocalContext`, and `previous` an
`IncomingContext`. The package's rules apply, as in
[Generated contexts](README.md#generated-contexts):

- four words per trace ID candidate and two per span ID candidate;
- at most eight candidates per identifier;
- no all-zero identifier, no reuse of the parent's span ID or of a received
  trace ID;
- an immediate stop at the first source error, without retry or fallback.

A root or a restart is not sampled and asserts random-trace-id, so it is sent
with flags `02`. A child keeps its parent's trace ID and randomness
assertion. When generation fails, these functions throw a `GenerationError`.

The facade reads one word at a time from `crypto` through the package's
[WebCrypto adapter](#webcrypto-and-explicit-effects), and only while the
package says that the generation needs one, so it never reads more than the
package's rules use. A source is trusted to be random: nothing checks the
quality of its words.

### Supplied identifiers

```js
rootFromIds(traceId, spanId, { random }) -> LocalContext
fromIds(traceId, spanId, { sampled, random }) -> LocalContext
childFromId(parent, spanId, { sampling }) -> LocalContext
restartFromIds(previous, traceId, spanId, { random }) -> LocalContext
```

An application that already has identifiers, such as those of another
tracer, passes them as text, as the package's
[supplied-ID operations](README.md#supplied-ids-and-contexts) take them:

- `rootFromIds` starts a trace: not sampled, and asserting random-trace-id
  only with `random: true`.
- `fromIds` represents an operation that the application owns, with its
  sampled indication, `false` by default. Its identifiers must belong to that
  operation: validating their format does not establish where they came
  from.
- `childFromId` continues `parent`, an `IncomingContext` or a `LocalContext`,
  with its own span ID; the parent's span ID is refused.
- `restartFromIds` starts a new trace in place of `previous`, an
  `IncomingContext`; its trace ID is refused, even when only the randomness
  assertion differs.

`random: true` records the application's assertion that the trace ID's
digits were generated randomly; the application is responsible for it, and
validation cannot establish it. An identifier that the codec refuses throws a
`RangeError` with the codec's error, such as `ZeroTraceId` or
`InvalidHex at 1`, and a reused one `ReusedSpanId` or `ReusedTraceId`.

### Failure handling

- `GenerationError` has `name` `'GenerationError'` and `reason`, the
  package's [`GenerationError`](README.md#generated-contexts):
  `SourceFailure 1 unavailable` or `SourceFailure 2 source-failure` from
  WebCrypto, `ExhaustedTraceId` or `ExhaustedSpanId`.
- Under the lenient policy, `continueOrStart` and `send` never throw for a
  generation failure. The business operation proceeds: the service is
  `Untraced`, and each message it sends forwards the received pair unchanged
  or carries no context fields. `show` and `error` say why.
- Under the strict policy they throw a `GenerationError` whenever no new
  operation was generated, so that the application can refuse the request,
  for example with a 503.
- A `TypeError` reports an argument of the wrong type: fields that are not
  string pairs, a boxed string, an object that is not a handle of the
  expected kind, a `crypto` option without `getRandomValues`, or options that
  are not an object.
- A `RangeError` reports a value that the package refuses. Its `message` is
  the package's error name:
  - `InvalidKey` or `InvalidValue` for a tracestate entry;
  - `TraceParentInputTooSmall`, `TraceStateOutputTooSmall` or
    `TraceStateInputTooSmall` for limits;
  - the codec's error, `ReusedSpanId` or `ReusedTraceId` for
    [supplied identifiers](#supplied-identifiers);
  - a description for an unknown option value or a budget that is not a
    non-negative safe integer.

The facade reads each argument once and converts it before any package code
runs, so an array with getters or a proxy cannot pass one value to the check
and another to the package.

The facade logs nothing.

### Tracestate

```js
getState(target, key) -> string | null
setState(target, key, value) -> target's kind
removeState(target, key) -> target's kind
```

- `getState` reads the entry of `key` in the state of an `IncomingContext`
  or `OutgoingContext`, or of a `Service`'s operation.
- `setState` adds or updates the entry of `key` in the state that an
  `OutgoingContext` or a `Service` sends. The entry goes first, as a
  participant puts its own entry, and the others keep their order.
- `removeState` deletes the entry of `key` from that state.

The edits return new handles; handles never change. A service without an
operation sends no state, so both edits return it unchanged. The state
received with an `IncomingContext` is not edited: a service that changes the
state it passes on continues the trace with an operation of its own. Keys and
values follow the package's
[grammar](README.md#grammar-and-reading-rules), and nothing is trimmed.

### Injection, forwarding and cleanup

```js
outgoing(context, { state }) -> OutgoingContext
inject(outgoing, fields, { limits }) -> { fields, dropped }
forward(incoming, fields, { limits }) -> { ok: true, fields } | { ok: false, error }
clear(fields) -> fields
```

- `outgoing` pairs a `LocalContext` with the state of `state`, an
  `IncomingContext`, an `OutgoingContext` or a `Service`, or with none.
- `inject` writes the outgoing context into the fields of a message to send,
  as [`Context.inject`](README.md#injecting-and-forwarding-context) does.
  `dropped` lists the keys that truncation removed.
- `forward` writes the pair an `IncomingContext` was received with,
  unchanged, or refuses with a
  [`ForwardError`](README.md#injecting-and-forwarding-context) name:
  `NothingToForward` when the tracestate was discarded, and
  `ForwardTooLarge` over the output budget. With limits smaller than those
  it was extracted with, a pair may also exceed an input budget:
  `InvalidForwardParent TraceParentTooLarge`, for example.
- `clear` removes the context fields alone, for a message sent without
  context.

`send` does a child and its injection in one step. These functions serve an
application that manages its operations itself, such as an intermediary that
relays requests unchanged.

### Limits

```js
limits({ traceparentInput, tracestateInput, tracestateOutput }) -> Limits
```

`limits()` gives the package's defaults: 32768, 32768 and 512 octets. Each
option replaces one budget, and the package's
[rules](README.md#limits) decide whether the combination is valid.

`inspectTraceparent`, the [codec adapter](#codec-adapter-and-foreign-values),
is exported too.

## Node HTTP integration

```js
requestFields(request) -> fields
extractRequest(request, { limits, base }) -> Extraction
continueOrStartRequest(request, { limits, base, reception, sampling, policy, crypto }) -> Service
requestHeaders(fields) -> headers
```

- `requestFields` reads the fields of a received `node:http` request, an
  `IncomingMessage`, from its `rawHeaders`: every header line in arrival
  order, with its name as it came. Extraction therefore refuses a repeated
  traceparent and reads repeated tracestate lines in order. `IncomingMessage.headers`
  joins repeated values, so it is not used for incoming requests.
- `extractRequest` is `extract(requestFields(request), options)`.
- `continueOrStartRequest` is `continueOrStart(extractRequest(request, options), options)`.
  A service that logs why it continued or started a trace extracts first and
  passes the extraction on, as the gateway example does.
- `requestHeaders` gives the headers of a request to send, for the `headers`
  option of `http.request` or `ClientRequest`. It holds each name once, with
  the spelling of its first field, and the values of that name in order, as
  an array when the name repeats. `node:http` writes one header line per
  value, and a name's lines follow one another at the place of its first
  field. The lines of each name keep their order; RFC 9110 gives the order
  of different names no meaning, and no Trace Context rule depends on it.
  The object has no prototype, so a field named `__proto__` is kept.

An application that needs every line in the fields' own order passes them
as an array in the format of `rawHeaders`:
`http.request(url, { method: 'POST', headers: sent.fields.flat() })`. Node
then writes the lines as given and adds only `Connection`, so the fields
must include `Host` and the body's `Content-Length` or `Transfer-Encoding`.

Outgoing requests can also use `fetch`:
`fetch(url, { method: 'POST', headers: sent.fields, body })`. `Headers`
lowercases names and joins the repeated values of a name with `, `. The
package writes one traceparent and one tracestate field, so the context
fields arrive whole. Other repeated fields arrive joined, which RFC 9110
permits only for fields defined as lists.

What Node does before and after the package:

- Its parser trims the whitespace around header values, and refuses a
  request head over `maxHeaderSize`, 16 KiB by default, with 431 before any
  Trace Context code runs, whatever the package's input budgets allow.
- It decodes header bytes as Latin-1. A byte above `0x7F`, which only the
  unknown fields of a later traceparent version may hold, therefore counts
  as two UTF-8 octets toward the input budgets. Node writes such a character
  back as the same byte, so forwarding sends the value as it came.
- `ClientRequest` writes names as given and adds `Host`, `Connection` and
  the body's framing itself.

### Gateway walkthrough

The [gateway](examples/gateway.mjs) listens on `127.0.0.1:18777` and calls
`http://127.0.0.1:18776/downstream`. From the repository root, after
`./scripts/setup-bend-source.sh`, start an observer that prints what reaches
downstream:

```sh
OBSERVER_PORT=18776 node tests/native/fixtures/observer.mjs
```

Then, in two more terminals, start the gateway and send it a traced request
and an untraced one:

```sh
node --import ./.tools/bend-source-2.0.27/bend2/main.ts packages/trace-context/examples/gateway.mjs
```

```sh
curl -X POST http://127.0.0.1:18777/orders -H 'traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01' -H 'tracestate: congo=t61rcWkgMzE' -d '{"order":1}'
curl -X POST http://127.0.0.1:18777/orders -d '{"order":2}'
```

The gateway logs its diagnostics, and the observer receives children of the
client's operation and of a new root. Each run prints new span IDs:

```text
POST /orders: TraceParentAccepted, StateAccepted; Continued, downstream Fresh
POST /orders: TraceParentAbsent, StateAbsent; Started, downstream Fresh
```

```text
POST /downstream {"order":1}
  traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-<new span ID>-01
  tracestate: congo=t61rcWkgMzE
POST /downstream {"order":2}
  traceparent: 00-<new trace ID>-<new span ID>-02
```

## How the facade reaches the package

The official loader exports a `.bend` module's definitions as JavaScript
functions, but it runs no IO operation. An IO operation without parameters,
such as `Context.root` of generation.bend, is not exported. One with
parameters, such as `Context.continue_or_start`, returns an unrun IO action:
calling it reads no word and performs nothing. A definition that takes a
template, such as `Context.continue_or_start_with`, is not exported at all.
A test in the facade corpus shows each of these. The package therefore gives
a host that feeds words itself a pure form of each generating operation,
described in [Host-driven generation](README.md#host-driven-generation):

1. `Generation.needs`, `Generation.feed` and `Generation.result` drive one
   generation, a word at a time.
2. `ServicePlan` and `SendPlan` record what continuing or starting and
   sending decide before they read a word.

The package's own IO operations run on those same plans. Law
`generation_drive` proves that a host's loop reads the same words and gets
the same result as the pure driver that the other generation laws describe.
Laws `hosted_service` and `hosted_send` prove that a host that drives the
plans itself gets what the IO operations give, for every sequence of words.
The facade is such a host: it only chooses what to wrap and what to throw.
The laws hold of that host path in Bend; that the facade's JavaScript follows
it is tested, not proved.

The facade reaches no system binding. The Bend runtime keeps its
`bun:ffi` bindings behind `globalThis.BEND_SYS`, and a test traps that global
while the facade extracts, continues, sends, forwards, injects and generates.
bend-net's JavaScript transport, which runs on Bun, plays no part here.

## Runtime requirements and support boundaries

- Node 22.18.0 or a later Node 22 release, or Node 24. Node runs the
  loader's TypeScript by stripping its types, which Node enables by default
  from 22.18.0 and in every Node 24 release. Node 22.17.1 refuses the loader
  with `ERR_UNKNOWN_FILE_EXTENSION`; 22.18.0 and 24.0.0 pass the facade's
  tests. CI qualifies the current patch release of each line and records its
  exact version.
- The loader of the pinned release commit, installed in the checkout by
  `setup-bend-source.sh`.
- The loader compiles the package when the facade is first imported, which
  adds a fraction of a second to startup.
- Node warns that the loader's package type is unspecified
  (`MODULE_TYPELESS_PACKAGE_JSON`). The warning is harmless, and
  `node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON` silences it.
- The facade is not qualified in browsers; the codec adapter and the
  WebCrypto source are, as described below.
- Node's HTTP limits and transformations apply as described
  [above](#node-http-integration).

## Qualification

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
  - what the loader exports, and the absence of any system binding.
- `tests/javascript/node-http.test.mjs` runs `node:http` servers against an
  independent observer that records header lines as they arrive, and checks
  `fetch` as well.
- `./scripts/test-consumer.sh node` installs the facade from a fresh pinned
  clone into an independent application. It runs
  [`tests/consumer/facade.mjs`](../../tests/consumer/facade.mjs) and the
  [root README example](../../README.md#from-javascript) against expected
  outputs.
- `./scripts/qualify-propagation.sh node` installs the facade from a pinned
  checkout into the Node propagation service,
  [`tests/propagation/service.mjs`](../../tests/propagation/service.mjs), as
  an application would. It then runs the repository's 13 propagation checks
  against an independent observer, the gateway example, and the
  [W3C Trace Context harness](https://github.com/w3c/trace-context/tree/acab820be9db7b3433668baa5cdd43f57f4c4be0/test)
  at commit `acab820` with `SPEC_LEVEL=2` and `STRICT_LEVEL=2`. It requires
  all 41 tests to run and pass. The [native HTTP guide](NATIVE-HTTP.md#propagation)
  describes the checks and the harness run; evidence goes to
  `build/propagation-node/`.

CI runs all of them on Node 22 and 24.

## Codec adapter and foreign values

`inspectTraceparent(value)`, also available from
[`javascript/codec.mjs`](javascript/codec.mjs), accepts only a primitive
JavaScript string. It returns:

- `{ ok: true, traceparent: string, sampled: boolean }` on success, preserving
  every flag bit according to the strict codec.
- `{ ok: false, error: string }` on failure. Non-string values produce
  `InvalidInputType`; malformed strings use the Bend codec's [error names](README.md).

Numbers, arrays, boxed strings and tagged constructor objects are rejected
without coercion. Parsing, formatting, nonzero-ID checks and sampled-bit
inspection run in the existing Bend implementation.

From this repository's checkout, with Node 22 or 24:

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

The raw Bend loader exports compiler representations, including tagged objects
and erased proof fields. A JavaScript object shaped like `TraceParentV00` with
`evidence: null` is not evidence of validity. The adapter and the facade
therefore accept only wire or scalar inputs and their own handles, and return
values that the package constructed. Code that calls the raw loader's exports
directly bypasses that boundary.

The package's proofs apply to its typed domain. The facade's conversions,
its handle checks and the host effects are tested boundaries of foreign code,
not additional formal proofs.

For a browser application, use the official Bend HTML build path:

```sh
./bend examples/javascript/index.html -o build/browser
node tests/browser/server.mjs
```

Open `http://127.0.0.1:4173/` and inspect a traceparent. Stop the local server
before running browser tests. The
[page](../../examples/javascript/index.html) imports the same codec adapter
used by Node. Bend bundles the real `.bend` module; no JavaScript codec is
maintained separately. A compiled CLI program is not treated as a browser
module, and the HTML bundle's script is not used as a Node library export.

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
validation and the bounded candidate rules belong to generation. The facade
reads its words through this function, with the `crypto` option as the
provider.

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
./scripts/test-consumer.sh node
./scripts/qualify-propagation.sh node
npx --no-install playwright install chromium firefox webkit
npm run build:browser
./scripts/qualify-js.sh browser
./tests/installer-source/test.sh
```

`./scripts/qualify-propagation.sh node` also needs Python 3.13 for the
harness, whose aiohttp version and hashes `tests/propagation/requirements.txt`
pins. On Linux CI, Playwright uses `install --with-deps` for its system
libraries. Playwright is locked to `1.63.0` in `package-lock.json`; its browser
builds are recorded with each test. Node 22 and 24 run the facade, the module
and actual compiled Bend effect consumers. Chromium, Firefox and WebKit run the
bundled page and shared source. The required aggregate CI gate includes every
target and rejects skips.

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
