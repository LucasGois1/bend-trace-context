# bend-trace-context

A pure, strict `traceparent` v00 codec for **Bend 2.0.27**, using dependent ID
types and checked proofs. Licensed under [MIT](LICENSE).

**Status: 0.1.0-dev.** The complete Trace Context propagator is being developed
under [specification #1](https://github.com/LucasGois1/bend-trace-context/issues/1).
The current package parses, formats and inspects strict v00 values, creates
root, child and restarted local contexts from validated IDs that the caller
supplies or from IDs generated on the host's cryptographic source, natively and
in Bend programs compiled to Node, parses, queries and formats Level 2
`tracestate` within validated limits, and updates the state a local operation
sends and emits it within the output budget. Header extraction/injection,
browser generation and HTTP/Fetch propagation are not implemented yet. Native
HTTP transport is separately qualified as a development harness;
it does not add a Trace Context propagator or tracer. Pure JavaScript module
consumption and a WebCrypto source are qualified separately below. No BendHub
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

To read the vendor state of a received request whose traceparent you have
accepted, pass its `tracestate` field values in arrival order to
`TC.TraceState.parse_fields(TC.Limits.default(), fields)`; tracestate has no
meaning without a valid traceparent.
The [tracestate example](packages/trace-context/examples/tracestate.bend) looks
up its own entry and prints the state's normalized value. To send state, pair
it with a local operation in a `TC.OutgoingContext`, set your entry and emit both
fields with `TC.OutgoingContext.emit`; the
[outgoing example](packages/trace-context/examples/outgoing.bend) continues a
received trace this way.

Read the [API and error reference](packages/trace-context/README.md) for strict
parsing semantics, typed values, generation rules and proof scope. See
[versioning and migration policy](CHANGELOG.md) before updating a dependency pin.

## Validation

```sh
./scripts/validate.sh native
./scripts/validate.sh node
./scripts/test-installer.sh
./scripts/test-consumer.sh native
./scripts/test-consumer.sh node
```

The consumer commands test the current **committed HEAD** in a separate fresh
clone; they do not test uncommitted edits. To select a source and revision, run
`./scripts/test-consumer.sh native REPOSITORY_SOURCE FULL_COMMIT_SHA` (or use
`node` as the first argument).

Baseline gates cover proofs, independent protocol vectors, all 256 flag bytes,
expected static rejections, deterministic generation from replayed tapes,
real-source generation smoke checks, the tracestate and outgoing corpora, the examples, the
exact README example above and a consumer outside the repository. Consumer logs and outputs are saved under
`build/consumer-native/` or `build/consumer-node/`. CI exercises
native macOS ARM64/Linux x86_64 and Node 22/24, recording exact runtime versions.
Configuring a job is distinct from observing a successful run.

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
lifecycle, generation, limits, tracestate and emission laws listed in the
[package reference](packages/trace-context/README.md#proofs). The generation
laws cover every sequence of words replayed from a tape; the host source's
path through the same driver is tested, and its quality is not proved.
Neither these laws nor the finite corpus establish full W3C propagator
conformance.

## JavaScript and browser consumers

The [JavaScript qualification guide](packages/trace-context/JAVASCRIPT.md)
provides executable Node and browser examples, an input-validating adapter over
the real Bend codec, and a shared WebCrypto source with structured failures.
It explains the official Node loader, Bend HTML bundler and foreign-value/proof
boundary. A JavaScript generation facade, browser generation and HTTP/Fetch
propagation remain later deliverables.

The [native HTTP transport guide](packages/trace-context/NATIVE-HTTP.md)
documents the pinned `bend-net` route, native macOS/Linux checks and its scope
boundary. Its W3C action/callback envelope and opaque header relay are transport
fixtures; they do not implement or claim propagator conformance.

## Development

The [parent specification](https://github.com/LucasGois1/bend-trace-context/issues/1)
and its linked issues record dependencies and acceptance criteria. Each slice
includes its applicable laws, tests and consumer documentation. English is the
repository language for code, comments, documentation and file/directory names.

The package targets [Bend 2](https://bend-lang.com/), maintained at
[bendlang/bend](https://github.com/bendlang/bend). See [Validation](#validation)
for reproducible checks and the [installer](scripts/setup-bend.sh) for the
pinned toolchain.
