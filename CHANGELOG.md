# Changelog

## 0.1.0-dev — unreleased

Development toward the complete 0.1.0 Trace Context propagator. This version
currently provides the strict v00 codec, contexts created from supplied or
generated IDs, Level 2 tracestate parsing within validated limits, tracestate
updates and emission within the output budget, context extraction from a
received message's fields, participant injection and transparent forwarding
into the fields of a message to send, the continue-or-start and sending
operations of a service, and qualified JavaScript/entropy boundaries; it is
not a published release.

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
- Document the sources for developers new to Bend. Every law in `LAWS.bend`
  states its claim in words, the W3C or specification requirement it verifies,
  its motivation and how to read it; `PROOF.bend` explains how to read a Bend
  proof; every definition of the package and every helper law under `proofs/`
  has a comment. The proof modules drop unused imports and lemmas and keep
  general lemmas in the shared libraries; law statements and code are
  unchanged.
- Establish reproducible Bend 2.0.27 setup, Git-pinned consumption, MIT licensing
  and baseline validation on native and Node targets.
- Standardize documentation and package paths in English, including the public
  entry `packages/trace-context/trace_context.bend` and `examples/` directory.
- Qualify pure module consumption in Node 22/24 and Chromium/Firefox/WebKit with
  the official Bend loader and HTML bundler. Add primitive-string inspection and
  a shared WebCrypto source whose explicit Bend JS effect returns structured
  failures. HTTP/Fetch integration remains a separate planned capability.
- Pin `paymog/bend-net` at `274591f1d1fcca2e4aa39ba65e505b32e2dbff21` and
  qualify its native HTTP client/server on macOS ARM64 and Linux x86_64 with a
  real loopback observer, repeated trace-header values, whitespace handling,
  no-redirect behavior and the listener's header-size limit. This is a
  development transport fixture, not Trace Context propagation or a tracer.

Browser generation and HTTP/Fetch propagation are planned under
[specification #1](https://github.com/LucasGois1/bend-trace-context/issues/1).

**Migration within 0.1.0-dev:** `Field` gains `SpanIdField{}`, so
`Error.ZeroId` can now name a supplied span ID. Code that matches every `Field`
constructor, or every `ZeroId{...}` case of `Error`, without a default case
must handle it. Context creation reports the new `ContextError` type; `Error`
itself gains no constructor. Tracestate, limits, updates, extraction,
injection, forwarding and continue-or-start add new types and functions only;
no existing name or behavior changes.

## Versioning and compatibility

`VERSION` identifies the source's development/release status. Before 0.1.0 is
released, use a full Git commit SHA as the installation identity; a branch name
or `0.1.0-dev` does not identify an immutable artifact. No registry release or
version tag has been published by this baseline.

The documented Bend entries are `packages/trace-context/trace_context.bend`,
which performs no host effect of its own, and
`packages/trace-context/generation.bend`, which generates on the host's
cryptographic source. Their documented types, constructors, functions and
error behavior form the current API contract. Internal parsing, generation
machine (`Draw`/`Step`), tracestate reading machine (`Scan`/`Member`),
extraction steps (`Carrier`, `Text`, `Read`, `Extract`), forwarding steps
(`Forward`), continue-or-start and sending steps (`Policy`, `Serve`, `Send`)
and proof helpers are not compatibility promises, even where Bend makes their
names importable.

The additional JavaScript inspection and entropy entries and their error
contracts are documented in the [qualification guide](packages/trace-context/JAVASCRIPT.md).

Future releases will record API, wire-policy and toolchain changes here, including
migration steps for incompatible changes. Development toward 0.1.0 does not
silently turn the strict codec into a normalizing propagator. When upgrading an
earlier development snapshot, update the dependency pin and imports together
to use `packages/trace-context/trace_context.bend`. The protocol, public types
and functions are unchanged by this directory migration.
