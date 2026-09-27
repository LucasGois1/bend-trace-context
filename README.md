# bend-trace-context

A pure, strict `traceparent` v00 codec for **Bend 2.0.27**, using dependent ID
types and checked proofs. Licensed under [MIT](LICENSE).

**Status: 0.1.0-dev.** The complete Trace Context propagator is being developed
under [specification #1](https://github.com/LucasGois1/bend-trace-context/issues/1).
The current package parses, formats and inspects strict v00 values, creates
root, child and restarted local contexts from validated IDs that the caller
supplies or from IDs generated on the host's cryptographic source, natively and
in Bend programs compiled to Node, parses, queries and formats Level 2
`tracestate` within validated limits, updates the state a local operation
sends and emits it within the output budget, extracts the context of a
received message from its fields, keeping a base context when the message has
no usable traceparent, injects a local operation into the fields of a
message to send or forwards a received context unchanged, and gives a service
its own operation for each message it receives, a child for each message it
sends, and a lenient or strict outcome when an identifier cannot be
generated. Over the native HTTP transport bend-net, a service built on the
package's adapter passes the W3C Trace Context harness at its pinned commit.
On Node 22 and 24, a JavaScript facade gives JavaScript applications the same
operations, with WebCrypto as the identifier source and `node:http`
integration, and a Node service built on it passes the same harness. Browser
generation and propagation are not implemented yet. No BendHub or npm
package has been published.

## Try the codec

Prerequisites: Git, POSIX shell, curl, tar, a SHA-256 utility (`sha256sum` or
`shasum`), and Clang 14+ for native builds. Node 22 or 24 is needed to run
generated JavaScript. The pinned compiler installer supports macOS ARM64 and
Linux x86_64.

From a checkout of this repository:

```sh
./scripts/setup-bend.sh
./bend version
./bend packages/trace-context/examples/demo.bend
```

Expected output from the example:

```text
00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01
sampled: True
```

Setup downloads the exact official release, verifies its SHA-256 before
extraction and installs it under `.tools/bend-2.0.27/`. It does not install
global shell configuration.
The [installer](scripts/setup-bend.sh) records the platform archive hashes for
the official [Bend 2.0.27 release](https://github.com/bendlang/bend/releases/tag/v2.0.27),
whose tag resolves to `63bee70b55a71024d6bdcb49a745111bc54b114e`. Setup rejects
an existing destination that differs from the verified release.

## Use it from another project

Choose a reviewed **full commit SHA** from this repository and substitute it for
`FULL_COMMIT_SHA` below. This source pin is separate from the compiler pin.
Keep that SHA in your application's dependency record so another checkout uses
the same code; a moving branch or `0.1.0-dev` is not a reproducible version.

```sh
mkdir -p deps
git clone https://github.com/LucasGois1/bend-trace-context.git deps/bend-trace-context
git -C deps/bend-trace-context checkout --detach FULL_COMMIT_SHA
./deps/bend-trace-context/scripts/setup-bend.sh
```

Create `main.bend` in your project:

<!-- test:readme-consumer:start -->
```bend
import Base
import ./deps/bend-trace-context/packages/trace-context/trace_context.bend as TC

def print_context(result: Result<&2, &2, TC.ContextError, TC.LocalContext>) -> IO(Unit):
  match result:
    case Fail{error}:
      IO.die(Unit, 1, TC.ContextError.show(error))
    case Done{context}:
      IO.print(TC.TraceParentV00.format(TC.LocalContext.to_traceparent(context)))

# Start a trace with IDs from an existing system, then create the operation
# that calls another service.
def start(trace: Result<&2, &2, TC.Error, TC.TraceId>, root: Result<&2, &2, TC.Error, TC.SpanId>,
  call: Result<&2, &2, TC.Error, TC.SpanId>) -> IO(Unit):
  match trace root call:
    case Done{trace_id} Done{root_span} Done{call_span}:
      print_context(TC.Context.child_from_id(TC.LocalParent{TC.Context.root_from_ids(trace_id, root_span)},
        call_span, TC.InheritSampled{}))
    case Fail{error} _ _:
      IO.die(Unit, 1, TC.Error.show(error))
    case _ Fail{error} _:
      IO.die(Unit, 1, TC.Error.show(error))
    case _ _ Fail{error}:
      IO.die(Unit, 1, TC.Error.show(error))

def main() -> IO(Unit):
  start(TC.TraceId.parse("4bf92f3577b34da6a3ce929d0e0e4736"),
    TC.SpanId.parse("00f067aa0ba902b7"), TC.SpanId.parse("53995c3f42cd8ad8"))
```
<!-- test:readme-consumer:end -->

Then run `./deps/bend-trace-context/bend main.bend`. No implementation files need
to be copied into the application. The documented public entry is the file
imported above; internal helpers are not a compatibility contract.

Expected output: the trace ID, the calling operation's span ID and the root's
unsampled default, as they would be sent to the called service.

```text
00-4bf92f3577b34da6a3ce929d0e0e4736-53995c3f42cd8ad8-00
```

To generate the IDs instead, import
`./deps/bend-trace-context/packages/trace-context/generation.bend` and call
`Context.root()`, `Context.child(parent, sampling)` or `Context.restart(previous)`
from it; a generated root is emitted with flags `02`. The
[generation example](packages/trace-context/examples/generate.bend) starts a
trace and creates a child on the host's source, and the
[consumer example](tests/consumer/main.bend) shows both paths.

To read the context of a received request, pass its fields in their order,
each a `TC.Header{name, value}`, to
`TC.Context.extract(TC.Limits.default(), fields, base)`. It reads the
traceparent, and the tracestate only with an accepted traceparent; `base`, a
context the application already has or `None{}`, is kept when the request has
no usable traceparent. The
[extraction example](packages/trace-context/examples/extract.bend) continues a
received trace with a child and keeps a base for an invalid request. The
[tracestate example](packages/trace-context/examples/tracestate.bend) looks
up its own entry and prints the state's normalized value. To send state, pair
it with a local operation in a `TC.OutgoingContext`, set your entry and emit both
fields with `TC.OutgoingContext.emit`; the
[outgoing example](packages/trace-context/examples/outgoing.bend) continues a
received trace this way. To send the fields, pass the outgoing context and the
fields of the message to `TC.Context.inject(limits, outgoing, fields)`, whose
carrier replaces any old context fields; to relay a request unchanged, pass
its incoming context to `TC.Context.forward(limits, incoming, fields)`, which
refuses a pair it cannot send whole. The
[injection example](packages/trace-context/examples/inject.bend) does both.

A service can do all of this with two calls of generation.bend. For each
request it receives, `Context.continue_or_start(extraction, TC.Continue{},
TC.InheritSampled{}, TC.Lenient{})` gives its own operation: a child of the
received context or of the base, or a root without either. For each request
it sends, `Context.send(limits, service, TC.InheritSampled{}, TC.Lenient{},
fields)` gives a child of that operation, injected into the request's fields.
When no identifier can be generated, the request still proceeds, forwarding
the received context unchanged if it can; `TC.Strict{}` returns the error
instead, and `TC.Restart{}` starts a new trace at a trust boundary.
`TC.Service.set` puts the service's own tracestate entry first. The
[continue example](packages/trace-context/examples/continue.bend) shows both
policies and a trust boundary, and the
[consumer example](tests/consumer/main.bend) also sets its own entry.

On the native HTTP transport bend-net, pinned as the `vendor/bend-net`
submodule, `packages/trace-context/native_http.bend` takes these steps from a
request's header map: `NativeHttp.continue_or_start(limits, headers, base,
TC.Continue{}, TC.InheritSampled{}, TC.Lenient{})` for the service's
operation, and `NativeHttp.send(limits, service, TC.InheritSampled{},
TC.Lenient{}, headers)` for the header map of each request it sends. The
[gateway example](packages/trace-context/examples/gateway.bend) is a complete
service on it.

Read the [API and error reference](packages/trace-context/README.md) for strict
parsing semantics, typed values, generation rules and proof scope. See
[versioning and migration policy](CHANGELOG.md) before updating a dependency pin.

### From JavaScript

The package's JavaScript facade runs on Node 22.18.0 or later, or Node 24,
through the official Bend module loader. In the pinned checkout above, install the loader, then
install the facade into your project as the `bend-trace-context` package:

```sh
./deps/bend-trace-context/scripts/setup-bend-source.sh
npm install ./deps/bend-trace-context/packages/trace-context
```

Create `main.mjs` in your project:

<!-- test:readme-javascript:start -->
```js
import * as TC from 'bend-trace-context';

// The fields of a received request, in their order.
const extraction = TC.extract([
  ['traceparent', '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01'],
  ['tracestate', 'congo=t61rcWkgMzE'],
]);
// The service's own operation for the request, and a child of it for a
// request that the service sends, with that request's own fields.
const service = TC.continueOrStart(extraction);
const sent = TC.send(service, [['content-type', 'application/json']]);
console.log(extraction.show);
console.log(service.show, service.outgoing.context.traceId);
console.log(sent.show, sent.fields.map(([name]) => name).join(' '));
```
<!-- test:readme-javascript:end -->

Then run
`node --import ./deps/bend-trace-context/.tools/bend-source-2.0.27/bend2/main.ts main.mjs`.
The service continues the received trace, and the request it sends carries a
child of the service's operation with the received state. The span IDs are
generated anew on each run, so the example prints only what does not change:

```text
TraceParentAccepted, StateAccepted
Continued 4bf92f3577b34da6a3ce929d0e0e4736
Fresh content-type traceparent tracestate
```

`bend-trace-context/node` reads the fields of a `node:http` request and
writes the headers of one to send. The
[JavaScript guide](packages/trace-context/JAVASCRIPT.md) documents the facade,
its errors, its Node HTTP integration, its runtime requirements and the
[gateway example](packages/trace-context/examples/gateway.mjs).

## Validation

```sh
./scripts/validate.sh native
./scripts/validate.sh node
./scripts/test-installer.sh
./scripts/test-consumer.sh native
./scripts/test-consumer.sh node
./scripts/qualify-js.sh node
./scripts/qualify-native-http.sh
./scripts/qualify-propagation.sh native
./scripts/qualify-propagation.sh node
```

The consumer commands test the current **committed HEAD** in a separate fresh
clone; they do not test uncommitted edits. To select a source and revision, run
`./scripts/test-consumer.sh native REPOSITORY_SOURCE FULL_COMMIT_SHA` (or use
`node` as the first argument).

Baseline gates cover proofs, independent protocol vectors, all 256 flag bytes,
expected static rejections, deterministic generation from replayed tapes,
real-source generation smoke checks, the tracestate, outgoing, extraction,
injection, continue-or-start and native HTTP header corpora, the examples,
the exact README examples above and a consumer outside the repository; in
`node` mode, the consumer also installs and runs the JavaScript facade. The
native HTTP transport script and the `native` propagation mode need the
`vendor/bend-net` submodule. Both propagation modes run the W3C harness: over
bend-net natively, and over `node:http` through the JavaScript facade.
Consumer logs and outputs are saved under `build/consumer-native/` or
`build/consumer-node/`. CI exercises native macOS ARM64/Linux x86_64 and
Node 22/24, recording exact runtime versions. Configuring a job is distinct
from observing a successful run.

The installer suite covers fresh/repeated installation, corrupt and interrupted
downloads, and preservation of existing directories, files and symlinks. It
downloads the official release once and controls only its delivery; checksum,
extraction and installation checks remain real.

CI also requires actionlint, ShellCheck, zizmor and local-link checks. Logs,
proof diagnostics, expected/actual outputs and runtime versions are uploaded
as artifacts retained for 14 days, including after failures. A separate weekly
workflow checks external links. Dependabot proposes weekly GitHub Actions
updates with a seven-day release cooldown. These schedules activate from the
default branch. GitHub secret scanning and push protection are enabled.

The universal fixed-length, `parse(format(context)) == Done{context}` and
inverse laws of the strict codec are proved, as are the supplied-ID, context
lifecycle, generation, limits, tracestate, emission, extraction, injection,
forwarding, continue-or-start, sending and host-driven generation laws listed
in the [package reference](packages/trace-context/README.md#proofs). The
generation laws cover every sequence of words replayed from a tape, including
the loop of a host that feeds its own words, as the JavaScript facade does;
the host source's path through the same driver is tested, and its quality is
not proved.
Neither these laws nor the finite corpus establish full W3C propagator
conformance.

## JavaScript and browser consumers

The [JavaScript guide](packages/trace-context/JAVASCRIPT.md) documents the
facade for Node: extraction, continue-or-start, sending, injection,
forwarding, tracestate edits and generation with explicit failure policies,
with `node:http` integration and a harness-qualified service. It also covers
the input-validating codec adapter, the shared WebCrypto source with
structured failures, the official Node loader, the Bend HTML bundler and the
boundary between JavaScript values and the package's proof-carrying values.
Browser generation and propagation remain in
[#14](https://github.com/LucasGois1/bend-trace-context/issues/14).

The [native HTTP guide](packages/trace-context/NATIVE-HTTP.md) documents the
pinned `bend-net` route and its native macOS/Linux checks. Its transport
fixtures relay header values opaquely and claim nothing about Trace Context.
Its propagation qualification builds a service on the package's
[native HTTP adapter](packages/trace-context/README.md#native-http-integration)
from a pinned checkout and runs the W3C Trace Context harness against it with
`SPEC_LEVEL=2` and `STRICT_LEVEL=2`: 41 tests, none failed or skipped.

## Development

The [parent specification](https://github.com/LucasGois1/bend-trace-context/issues/1)
and its linked issues record dependencies and acceptance criteria. Each slice
includes its applicable laws, tests and consumer documentation. English is the
repository language for code, comments, documentation and file/directory names.

The package targets [Bend 2](https://bend-lang.com/), maintained at
[bendlang/bend](https://github.com/bendlang/bend). See [Validation](#validation)
for reproducible checks and the [installer](scripts/setup-bend.sh) for the
pinned toolchain.
