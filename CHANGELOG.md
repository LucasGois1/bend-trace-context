# Changelog

## 0.1.0-dev — unreleased

Development toward the complete 0.1.0 Trace Context propagator. This version
currently provides the strict v00 codec, contexts created from supplied or
generated IDs, Level 2 tracestate parsing within validated limits, tracestate
updates and emission within the output budget, context extraction from a
received message's fields, participant injection and transparent forwarding
into the fields of a message to send, the continue-or-start and sending
operations of a service, an adapter for bend-kit's native HTTP package
qualified against the W3C Trace Context harness, a JavaScript facade for Node
with `node:http` integration qualified against the same harness, Fetch
integration for browser pages qualified in Playwright's builds of Chromium,
Firefox and WebKit, and
qualified JavaScript/entropy boundaries; it is not a published release.

- Preserve the pure Bend codec, dependent ID representation, universal
  round-trip and fixed-length proofs, independent protocol corpus and
  negative-construction examples.
- Prove the strict codec's inverse law: formatting every accepted text
  reproduces it exactly. The hexadecimal decoder now searches the encoder's
  alphabet; the accepted characters are unchanged.
- Add validated `TraceId` and `SpanId` constructors for supplied IDs, an
  explicit randomness assertion, separate `RemoteContext` and `LocalContext`
  types, and `Context.root_from_ids`, `Context.from_ids`,
  `Context.child_from_id` (from a remote or local parent) and
  `Context.restart_from_ids`. Roots start unsampled; children keep the trace ID
  and its randomness assertion and inherit sampled unless it is set
  explicitly; restarts apply the root defaults. A child whose span ID equals
  its parent's and a restart whose trace ID equals the received one fail with a
  `ContextError`. Local contexts emit version `00` with only the known flags.
  The lifecycle guarantees, including acceptance of every other ID, are proved
  as laws.
- Add `TraceParentV00.is_random` for the random-trace-id bit.
- Generate contexts on the host's cryptographic source with
  `Context.root`, `Context.child` and `Context.restart` in the new
  `packages/trace-context/generation.bend` entry, natively and in Bend programs
  compiled to Node. Four words per trace ID candidate and two per span ID
  candidate are read most significant first; each identifier gets eight
  candidates, zero and reused IDs are rejected, and the first source error ends
  generation without fallback. Generated roots emit flags `02`.
  `trace_context.bend` adds `Context.root_with` and its siblings for a caller's
  source, `Source.tape` for replay, `GenerationError`, and
  `TraceId.from_words`, `SpanId.from_words` and `U32.to_hex`, which make no
  randomness assertion. Validity, conversion and consumption bounds are proved
  as laws over replayed tapes; the host source's path is tested and its quality
  is not proved. A runnable generation example is added.
- `entropy.bend` gains a native twin reading the host primitive of Base's
  `IO.random_u32`, so native programs can use it too.
- Parse, query and format Level 2 tracestate with `TraceState.parse` and
  `TraceState.parse_fields`, `TraceState.get`, `TraceState.format` and
  `TraceState.entries`, over validated `StateKey`, `StateValue` and
  `StateEntry` values. Optional whitespace and empty members are ignored,
  leading value spaces are kept, every nonempty member is validated and counted
  before duplicates are dropped, the first entry of a key is kept and a 33rd
  member discards the state. Repeated fields are read as their comma-joined
  combination. Failures are `StateError` diagnostics: `StateTooLarge`,
  `TooManyMembers` or `InvalidEntry{member, error}` with an `EntryError`.
- Add validated `Limits` with `Limits.new` and `Limits.default()`: traceparent
  and tracestate input budgets of 32 KiB and a tracestate output budget of 512
  octets by default, in UTF-8 octets. A configuration needs at least 55 octets
  of traceparent input, at least 512 of output and no less tracestate input
  than output; `LimitsError` names the first rule broken. A tracestate value
  over its input budget is refused before any member is read, without
  measuring the rest. Laws prove the rules of limits, keys, values and states,
  lookups by key, the round trip of a normalized value with optional whitespace
  around it, the parse of two joined states (the first entry of a key kept,
  order preserved, 32 members counted before duplicates are dropped), repeated
  fields and the budget. Whitespace between members and other inputs that are
  not normalized values are tested by the corpus. A runnable tracestate example
  is added.
- Update and emit tracestate. `TraceState.set` puts an entry first with its
  new value and keeps the other entries in order: updating a key evicts
  nothing, even from a full state, and a new 33rd key removes the last entry.
  `TraceState.remove` deletes an entry. `TraceState.truncate` fits a state to
  the output budget by removing whole entries, the rightmost larger than 128
  octets first and then from the right, stopping as soon as the value fits;
  `Truncation` reports the keys it dropped. `TraceState.size` counts the
  emitted octets, commas included. `OutgoingContext` pairs a local context
  with the state it sends, and `OutgoingContext.emit` gives its traceparent
  and truncated tracestate values. Laws prove the exact entries of every
  update, the exact size, and that truncation is spec #1's procedure: it
  keeps a fitting state whole, keeps entries in order, fits the budget and
  reports exactly the keys dropped. A runnable outgoing example is added.
- Extract the trace context of a received message with `Context.extract`,
  from its fields in order as `Header{name, value}` values and a base context
  to keep. Field names are compared without regard to ASCII case. More than
  one traceparent field, or a value joining several with a comma, is refused.
  `TraceParent.read` reads one value by the rules of a participant: within its
  own input budget, without the optional whitespace around it, version 00
  exactly as the strict codec reads it, ff refused, and versions 01 to fe by
  their known prefix, followed by the end or a dash and fields that are not
  read, other than to refuse a control character, which no field value may
  hold (`ControlCharacter{offset}`). An accepted message gives an
  `IncomingContext`: the sender's operation, the state of its tracestate
  fields read in arrival order, and the `ReceivedPair` of original fields
  when the whole pair was accepted, for forwarding. Refused tracestate is
  discarded whole while the traceparent stays accepted; without an accepted
  traceparent the base, a `BaseContext`, is kept and the tracestate is not
  read. `TraceParentOutcome` and
  `StateOutcome` report absence, rejection, discard and neglect without
  received values. Laws prove how each version is read, the budget, comma and
  repetition rules, the kept base, the incoming context, the independence of
  the traceparent from the tracestate and the bounds of the kept pair. A
  runnable extraction example is added.
- Inject and forward context into the fields of a message to send. All
  three operations remove every traceparent and tracestate field, whatever
  the ASCII case of its name, keep the other fields in their order and write
  lowercase names. `Context.inject` writes an outgoing context's emission,
  leaving out an empty tracestate, and `Injection` reports the keys that
  truncation dropped apart from the carrier. `Context.clear` removes the
  context fields of a message sent without context. `Context.forward` sends
  the received pair of an incoming context as it came, whatever its version,
  flags and unknown fields, with its tracestate fields joined into one
  field; a pair that cannot be sent whole is refused with a `ForwardError`
  (`NothingToForward`, `ForwardTooLarge`, `InvalidForwardParent` or
  `InvalidForwardState`) and nothing is written. Laws prove the carriers
  written, the dropped keys, idempotence, that a receiver of an injection
  continues the injected operation with the truncated state, and that the
  pair of an extracted context is refused only for the output budget. A
  runnable injection example is added.
- Continue or start a service's operation with `Context.continue_or_start`
  and give each message it sends a child with `Context.send`, on the host's
  source in `generation.bend`, or with `Context.continue_or_start_with` and
  `Context.send_with` on a caller's source. The `Reception` decides what
  happens to the context that extraction keeps, the message's or the base:
  `Continue{}` continues it with a child that sends its state, and
  `Restart{}`, at a trust boundary, replaces it with a new trace that never
  reuses its trace ID and keeps none of its state; without a kept context a
  root starts the trace. Roots and restarts take the root default, not
  sampled, unless `SetSampled` says otherwise. The result is a `Service`,
  `Operating` with its `Origin` or `Untraced` with the `GenerationError`;
  `Service.set` and `Service.remove` edit the state its operation sends.
  `Context.send` generates a new child for every call, whose span ID is
  never the service's, and injects it; when none can be generated, the
  message forwards the received pair unchanged if it can (`Forwarded`) and
  carries no context fields otherwise (`NoContext`, with an `Unforwarded`
  reason), and it never reports a new operation. `Lenient{}` lets the
  business operation proceed with diagnostics that hold no received value,
  truncation included; `Strict{}` returns `Fail{GenerationError}` instead.
  Laws prove, for every tape and under both policies, which generation each
  operation performs and what its outcome gives, that a restart keeps
  nothing of a received context, and that a message reports a new operation
  exactly when one was generated for it. A runnable example is added.
- Add the native HTTP adapter `packages/trace-context/native_http.bend` for
  bend-kit's header maps, a Base `Map` from each field name to its values in
  arrival order. `NativeHttp.carrier` and `NativeHttp.headers` translate a
  map to the package's carrier and back; `NativeHttp.continue_or_start_with`
  and `NativeHttp.send_with` take a service's operation from a received
  request's map and give each request to send a new child, on a caller's
  source, returning an `Outbound` with the `Sent` diagnostics and the header
  map to send. `NativeHttp.continue_or_start` and `NativeHttp.send` of
  generation.bend do the same on the host's source. The adapter imports only
  `Base` and trace_context.bend, and decides no Trace Context rule: laws
  prove that its carrier
  keeps every value of every name in order, that the map it writes for a
  carrier does too given the contract of Base's `Map`, and that its
  shortcuts are the package's operations on that carrier. Its translations
  are loops, so a head of 64 KiB needs no deep stack. `scripts/qualify-propagation.sh`
  builds a service and the new gateway example from a pinned checkout, runs
  them over bend-kit against an independent observer, and runs the W3C
  harness at commit `acab820` with `SPEC_LEVEL=2` and `STRICT_LEVEL=2`: 41
  tests, none failed or skipped. Native CI jobs run it on macOS ARM64 and
  Linux x86_64.
- Add a JavaScript facade for Node 22 and 24, the `bend-trace-context`
  package in `packages/trace-context`, installed from a pinned checkout with
  `npm install` and run on Node alone: it carries the package as the ES
  module that the pinned compiler builds. It mirrors the package's
  operations with plain JavaScript data:
  - `extract`, `continueOrStart` and `send`;
  - `inject`, `forward`, `clear` and `outgoing`;
  - `getState`, `setState` and `removeState`;
  - `root`, `child`, `restart` and `limits`;
  - `rootFromIds`, `fromIds`, `childFromId` and `restartFromIds` for
    identifiers that the application supplies.

  The package's values stay behind frozen handles that only the facade
  creates, named after the package's types, so copied or forged objects are
  refused, and arguments are read once. It needs Node 22.18.0 or later, or
  Node 24. Generation reads WebCrypto words one at a time, and the policies
  follow the package: the lenient path proceeds with diagnostics, and the
  strict one throws a `GenerationError`. `bend-trace-context/node` reads
  received `node:http` requests from their raw header lines and writes the
  headers of requests to send; `fetch` takes the fields directly.
- Add Fetch integration for browser pages, `bend-trace-context/fetch`:
  - `documentFields(document)` reads the context that a page's server
    rendered as `<meta name="traceparent">` and `<meta name="tracestate">`
    elements;
  - `tracedFetch(service, input, init, options)` sends one request with a
    new child of the service's operation and returns `{ response, sent }`.

  Only the page's own origin, and origins or URLs that `propagateTo`
  allows, receive the context fields. Any other request, and every
  `no-cors` request, goes without them, so that a CORS preflight that does
  not allow them cannot fail the business request. A redirect that `fetch`
  follows keeps the fields, and the guide shows how to control it. Pages are
  bundled with the official Bend bundler from a pinned checkout; bundling
  the same checkout again gives byte-identical files. The browser
  qualification runs in Playwright's builds of Chromium, Firefox and WebKit,
  with exact versions, against an independent cross-origin observer:
  - headers joined by Fetch;
  - stale fields;
  - intact forwarding;
  - actual WebCrypto exceptions;
  - allowed, unlisted and refused cross-origin calls;
  - `no-cors` and redirects.

  `scripts/test-consumer.sh browser` bundles an independent page from a
  pinned clone and runs it in the three engines. The facade's handle
  registry and option checks moved into internal modules shared by its
  entries.
- Give hosts that feed words themselves a pure form of the generating
  operations in `trace_context.bend`: `Generation` with `needs`, `feed` and
  `result`, and the plans `ServicePlan` and `SendPlan`, on which
  `Context.continue_or_start_with` and `Context.send_with` now run. Prove 3
  new laws, 115 in all: a host's loop reads the words that the pure driver
  reads and gets its result, and a host that drives the plans gets what the
  IO operations give, for every tape and under both policies.
- `scripts/qualify-propagation.sh` takes a mode, `native` or `node`. The
  `node` mode installs the facade from a pinned checkout into a Node service
  and runs the same propagation checks, a JavaScript twin of the gateway
  example and the W3C harness, 41 tests; Node CI jobs run it on Node 22 and
  24. `scripts/test-consumer.sh node` also installs and runs the facade from
  the pinned clone, with the root README's JavaScript example.
- Document the sources for developers new to Bend. Every law in `LAWS.bend`
  states its claim in words, the W3C or specification requirement it verifies,
  its motivation and how to read it; `PROOF.bend` explains how to read a Bend
  proof; every definition of the package and every helper law under `proofs/`
  has a comment. The proof modules drop unused imports and lemmas and keep
  general lemmas in the shared libraries; law statements and code are
  unchanged.
- Establish reproducible Bend 2.0.27 setup, Git-pinned consumption, MIT licensing
  and baseline validation on native and Node targets.
- Move to Bend 2.0.32. The proof gate reads its verdict, `ALL PROOFS CHECK`,
  which also requires that nothing `PROOF.bend` imports relies on `@unsafe`
  or foreign code. The host shortcuts of the native HTTP adapter therefore
  moved to generation.bend, so native_http.bend has no host effect, and the
  validation pins the host operations that rely on the entropy effect. Both
  entropy effects register with `io_eff(CID(read_u32), ...)`, as Bend's
  effect interface now requires. The JavaScript facade imports
  `javascript/trace_context.mjs`, the ES module that `scripts/build-js.sh`
  builds with the pinned compiler and that the qualification requires to be
  current, instead of loading `.bend` files through Bend's Node module
  loader: the loader of 2.0.32 uses TypeScript syntax that Node 22 and 24 do
  not strip by default. `scripts/setup-bend-source.sh` is removed. The
  native HTTP programs move from paymog/bend-net, which does not build on
  Bend 2.0.32, to its successor bend-kit, `bend-kit-http` 0.23.0.1 with
  `bend-kit-json` 0.5.0.1, which they import from BendHub by content hash;
  the `vendor/bend-net` submodule is removed.
- Standardize documentation and package paths in English, including the public
  entry `packages/trace-context/trace_context.bend` and `examples/` directory.
- Qualify pure module consumption in Node 22/24 and Chromium/Firefox/WebKit
  with the package's compiled ES module and the official HTML bundler. Add
  primitive-string inspection and a shared WebCrypto source whose explicit
  Bend JS effect returns structured failures. HTTP/Fetch integration remains
  a separate planned capability.
- Qualify bend-kit's native HTTP client/server, `bend-kit-http` 0.23.0.1
  from BendHub (paymog/bend-net at `274591f1d1fcca2e4aa39ba65e505b32e2dbff21`
  before Bend 2.0.32), on macOS ARM64 and Linux x86_64 with a
  real loopback observer, repeated trace-header values, whitespace handling,
  no-redirect behavior and the listener's header-size limit. This is a
  development transport fixture, not Trace Context propagation or a tracer.

The remaining work toward 0.1.0 is planned under
[specification #1](https://github.com/LucasGois1/bend-trace-context/issues/1).

**Migration within 0.1.0-dev:** `Field` gains `SpanIdField{}`, so
`Error.ZeroId` can now name a supplied span ID. Code that matches every `Field`
constructor, or every `ZeroId{...}` case of `Error`, without a default case
must handle it. Context creation reports the new `ContextError` type; `Error`
itself gains no constructor. Tracestate, limits, updates, extraction,
injection, forwarding, continue-or-start, the native HTTP adapter and
host-driven generation add new types and functions only; no public name or
behavior changes. Internal helpers behind continue-or-start and sending
changed, as internal helpers may. `scripts/qualify-propagation.sh` now takes
the mode before the commit, and its evidence moved to
`build/propagation-native/`. With Bend 2.0.32, `NativeHttp.continue_or_start`
and `NativeHttp.send` moved from native_http.bend to generation.bend, with
the same names, parameters and results: prefix them with generation.bend's
alias, as in `Generate.NativeHttp.send`. Bend 2.0.32 answers
`SOME PROOFS FAIL` for a file that imports generation.bend, whose host
operations rely on the entropy effect's foreign code, so an application's
proof gate should not import it: state the laws over a caller's source, as
this package's laws do. A JavaScript
application runs with `node` alone: drop the `--import` of Bend's loader and
`scripts/setup-bend-source.sh`. A native service imports bend-kit's HTTP
package instead of bend-net: its bodies are bytes (`Http.Body()`, with
`Http.from_string` and `Http.to_string`), `Http.fetch.how` answers
`Result<&1, &1, Http.Err, Http.Res>`, and no submodule is needed.

## Versioning and compatibility

`VERSION` identifies the source's development/release status. Before 0.1.0 is
released, use a full Git commit SHA as the installation identity; a branch name
or `0.1.0-dev` does not identify an immutable artifact. No registry release or
version tag has been published by this baseline.

The documented Bend entries are `packages/trace-context/trace_context.bend`,
which performs no host effect of its own,
`packages/trace-context/generation.bend`, which generates on the host's
cryptographic source, and `packages/trace-context/native_http.bend`, which
adapts the header maps of bend-kit's native HTTP package. Their documented
types, constructors, functions and error behavior form the current API
contract. Internal parsing, generation
machine (`Draw`/`Step`), tracestate reading machine (`Scan`/`Member`),
extraction steps (`Carrier`, `Text`, `Read`, `Extract`), forwarding steps
(`Forward`), continue-or-start and sending steps (`Policy`, `Serve`, `Send`),
the native HTTP adapter's `Headers` steps and proof helpers are not
compatibility promises, even where Bend makes their names importable.

The additional JavaScript inspection and entropy entries and their error
contracts are documented in the [qualification guide](packages/trace-context/JAVASCRIPT.md).

Future releases will record API, wire-policy and toolchain changes here, including
migration steps for incompatible changes. Development toward 0.1.0 does not
silently turn the strict codec into a normalizing propagator. When upgrading an
earlier development snapshot, update the dependency pin and imports together
to use `packages/trace-context/trace_context.bend`. The protocol, public types
and functions are unchanged by this directory migration.
