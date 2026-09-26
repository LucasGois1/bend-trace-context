# Changelog

## 0.1.0-dev — unreleased

Development toward the complete 0.1.0 Trace Context propagator. This version
currently provides the strict v00 codec, contexts created from supplied or
generated IDs, Level 2 tracestate parsing within validated limits and
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
- Document the sources for developers new to Bend. Every law in `LAWS.bend`
  states its claim in words, the W3C or specification requirement it verifies,
  its motivation and how to read it; `PROOF.bend` explains how to read a Bend
  proof; every definition of the package and every helper law under `proofs/`
  has a comment. Law statements, proofs and code are unchanged.
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

Tracestate editing and emission, header extraction/injection, browser
generation, propagation and HTTP/Fetch integration are planned under
[specification #1](https://github.com/LucasGois1/bend-trace-context/issues/1).

**Migration within 0.1.0-dev:** `Field` gains `SpanIdField{}`, so
`Error.ZeroId` can now name a supplied span ID. Code that matches every `Field`
constructor, or every `ZeroId{...}` case of `Error`, without a default case
must handle it. Context creation reports the new `ContextError` type; `Error`
itself gains no constructor. Tracestate and limits add new types and functions
only; no existing name or behavior changes.

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
machine (`Draw`/`Step`), tracestate reading machine (`Scan`/`Member`) and
proof helpers are not compatibility promises, even where Bend makes their names
importable.

The additional JavaScript inspection and entropy entries and their error
contracts are documented in the [qualification guide](packages/trace-context/JAVASCRIPT.md).

Future releases will record API, wire-policy and toolchain changes here, including
migration steps for incompatible changes. Development toward 0.1.0 does not
silently turn the strict codec into a normalizing propagator. When upgrading an
earlier development snapshot, update the dependency pin and imports together
to use `packages/trace-context/trace_context.bend`. The protocol, public types
and functions are unchanged by this directory migration.
