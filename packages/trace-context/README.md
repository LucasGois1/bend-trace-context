# Traceparent v00 codec and local contexts

The currently implemented part of **bend-trace-context 0.1.0-dev** is a pure,
strict v00 codec for Bend 2.0.27, validated trace and span IDs, and root, child
and restarted local contexts, either from IDs the caller supplies or from IDs
generated on a cryptographic source. It has no external package dependencies
beyond the compiler's bundled `Base`. The public entries are
[trace_context.bend](trace_context.bend), which performs no host effect of its
own, and [generation.bend](generation.bend), which adds the host's
cryptographic source.
See the root [installation guide](../../README.md) to consume them from a pinned
Git checkout.

## Codec API

Names below are qualified by the alias chosen for the public entry, such as `TC`:

```bend
TraceParentV00.parse(text: String) -> Result<&2, &2, Error, TraceParentV00>
TraceParentV00.format(context: TraceParentV00) -> String
TraceParentV00.is_sampled(context: TraceParentV00) -> Bool
TraceParentV00.is_random(context: TraceParentV00) -> Bool
Error.show(error: Error) -> String
```

`parse` returns `Done{context}` for a valid input or `Fail{error}`. Ordinary
consumers receive a validated context directly; no proof terms are needed.
`format` is total for the typed argument and preserves every flag bit.
`is_sampled` reads flag bit 0 and `is_random` reads the random-trace-id bit 1.
Neither decides whether to record or export a span, and a random bit is the
sender's assertion, not evidence of how its trace ID was generated.

Use `Done{+context}` when reusing the context for both formatting and inspection,
as in the [executable example](examples/demo.bend). Run it from the repository
root with `./bend packages/trace-context/examples/demo.bend`.

## Supplied IDs and contexts

```bend
TraceId.parse(text: String) -> Result<&2, &2, Error, TraceId>
TraceId.assert_random(id: TraceId) -> TraceId
TraceId.is_random(id: TraceId) -> Bool
TraceId.to_string(id: TraceId) -> String
TraceId.is_eq(a: TraceId, b: TraceId) -> Bool
SpanId.parse(text: String) -> Result<&2, &2, Error, SpanId>
SpanId.to_string(id: SpanId) -> String
SpanId.is_eq(a: SpanId, b: SpanId) -> Bool

Context.root_from_ids(trace_id: TraceId, span_id: SpanId) -> LocalContext
Context.from_ids(trace_id: TraceId, span_id: SpanId, sampled: Bool) -> LocalContext
Context.child_from_id(parent: Parent, span_id: SpanId, sampling: Sampling) ->
  Result<&2, &2, ContextError, LocalContext>
Context.restart_from_ids(previous: RemoteContext, trace_id: TraceId, span_id: SpanId) ->
  Result<&2, &2, ContextError, LocalContext>
ContextError.show(error: ContextError) -> String

RemoteContext.from_traceparent(value: TraceParentV00) -> RemoteContext
LocalContext.to_traceparent(context: LocalContext) -> TraceParentV00
```

The `_from_ids` operations take identifiers the caller already has. The
operations that generate identifiers are `Context.root`, `Context.child` and
`Context.restart` in [generation.bend](#generated-contexts).

The types that carry these values are:

| Type | Meaning |
| --- | --- |
| `TraceId` | 32 lowercase hexadecimal digits, not all zero, plus whether its random origin is asserted |
| `SpanId` | 16 lowercase hexadecimal digits, not all zero: one operation |
| `RemoteContext` | A received context identifying the sender's operation: trace ID, span ID, sampled |
| `LocalContext` | A context identifying an operation of this participant, with the same fields |
| `Parent` | `RemoteParent{context}` or `LocalParent{context}`, wrapping the context a child continues |
| `Sampling` | `InheritSampled{}` or `SetSampled{sampled}`: how a child obtains sampled |
| `ContextError` | `ReusedSpanId{}` or `ReusedTraceId{}`: why creation from supplied IDs was refused |

Each context type has `trace_id`, `span_id` and `is_sampled` accessors, and so
does `Parent`. `Sampling.resolve(sampling, inherited)` returns the sampled
indication a child receives.

`TraceId.parse` and `SpanId.parse` accept exactly 32 and 16 lowercase
hexadecimal characters and reject an all-zero ID. A parsed trace ID makes no
randomness assertion. `TraceId.assert_random` records the caller's assertion
that the digits were generated randomly; the caller is responsible for it, and
validation cannot establish it. `is_eq` compares identifiers, so a randomness
assertion does not change which trace an ID names.

- `Context.root_from_ids` starts a trace. A new root is not sampled; it
  carries the random-trace-id flag only when its trace ID asserts it.
- `Context.from_ids` represents an operation the caller owns with an explicit
  sampled indication. The IDs must belong to that operation: validating their
  format does not establish where they came from.
- `Context.child_from_id` continues a remote or local parent with a new
  operation. The child keeps the parent's trace ID and randomness assertion,
  and it inherits sampled unless the caller passes `SetSampled{value}`. A span
  ID equal to the parent's fails with `ReusedSpanId{}`; every other one is
  accepted. Only the parent is compared: siblings may share a span ID, so each
  distinct operation needs its own.
- `Context.restart_from_ids` deliberately starts a new trace at a boundary
  where a received context is not continued. It applies the root defaults,
  including sampled `0`. A trace ID equal to the received one fails with
  `ReusedTraceId{}`, even when only the randomness assertion differs. An
  explicit sampling policy for restarts is left to the continue-or-start
  operation of [#11](https://github.com/LucasGois1/bend-trace-context/issues/11).

`RemoteContext.from_traceparent` receives a strictly parsed v00 value. It keeps
the trace ID, the sender's span ID, sampled and random-trace-id; reserved flag
bits are not part of a remote context. The strict codec rejects versions `01`
to `fe`, which header extraction
([#9](https://github.com/LucasGois1/bend-trace-context/issues/9)) will accept by
their known prefix. `LocalContext.to_traceparent` gives the participating
representation: version `00` and flags `00` to `03`, with every reserved bit
zero. Header injection and transparent forwarding of the original header pair
belong to [#10](https://github.com/LucasGois1/bend-trace-context/issues/10).

`RemoteContext` and `LocalContext` are separate types, so a received context
cannot be passed where a local one is expected (the
[negative fixture](tests/reject/remote_as_local.bend) checks this). Bend
constructors are not private, however: code that builds a `LocalContext{...}`
value directly bypasses these operations, and no type can reject that.

The [consumer example](../../tests/consumer/main.bend) receives a context,
creates a server operation and sampled and unsampled client operations,
rejects a reused span ID, restarts a trace, starts a root and represents an
existing operation with `Context.from_ids`.

## Generated contexts

[generation.bend](generation.bend) generates identifiers on the host's
cryptographic source: the operating system's generator natively
(`arc4random_buf` on macOS, `getrandom` on Linux, as Base's `IO.random_u32`)
and WebCrypto in JavaScript. Qualified here for native programs and for Bend
programs compiled to Node; browser generation belongs to
[#14](https://github.com/LucasGois1/bend-trace-context/issues/14). Names below
are qualified by the aliases `Generate` for generation.bend and `TC` for
trace_context.bend:

```bend
Generate.Context.root() -> IO(Result<&2, &2, TC.GenerationError, TC.LocalContext>)
Generate.Context.child(parent: TC.Parent, sampling: TC.Sampling) ->
  IO(Result<&2, &2, TC.GenerationError, TC.LocalContext>)
Generate.Context.restart(previous: TC.RemoteContext) ->
  IO(Result<&2, &2, TC.GenerationError, TC.LocalContext>)
TC.GenerationError.show(error: TC.GenerationError) -> String
```

The [generation example](examples/generate.bend) starts a trace and creates
the operation that calls another service. From the repository root:

```sh
./bend packages/trace-context/examples/generate.bend
```

Each run prints new IDs. Both lines share the trace ID and end in `-02`:

```text
00-<32 random hexadecimal digits>-<16 random hexadecimal digits>-02
00-<the same trace ID>-<16 other random hexadecimal digits>-02
```

Every operation follows the same rules:

- A trace ID candidate takes four 32-bit source words and a span ID candidate
  two, most significant first: the first word gives the first eight digits.
  A root or restart draws its trace ID before its span ID.
- Each identifier gets at most eight candidates. An all-zero candidate is
  rejected, a child's candidate equal to the parent's span ID is rejected, and
  a restart's candidate equal to the received trace ID is rejected. After the
  eighth rejection the operation fails with `ExhaustedTraceId{}` or
  `ExhaustedSpanId{}` and reads no further word.
- The first source error ends the operation with
  `SourceFailure{code, message}`; the remaining words are not read. There is no
  retry and no time, counter or other fallback.
- Generation trusts its source to be random, so a generated trace ID asserts
  random-trace-id. A root or restart is not sampled, so it is emitted with
  flags `02`. A child keeps its parent's trace ID and randomness assertion and
  resolves sampled as `Context.child_from_id` does, so generating its span ID
  never changes a received random bit.

| Error | Meaning |
| --- | --- |
| `SourceFailure{code, message}` | The source failed with its own code and message |
| `ExhaustedTraceId{}` | Eight trace ID candidates were rejected |
| `ExhaustedSpanId{}` | Eight span ID candidates were rejected |

The host source fails with `1 unavailable` or `2 source-failure` in JavaScript,
as the [WebCrypto adapter](JAVASCRIPT.md#webcrypto-and-explicit-effects)
documents. Natively, a Linux `getrandom` error gives its `errno` and
`strerror` text, and `arc4random_buf` on macOS cannot fail. The tests induce
the JavaScript failures but not the native one. `Source.tape` fails with
`1 tape-exhausted` when its words run out.

The same operations take a caller's source in trace_context.bend:

```bend
TC.Context.root_with(~S: Type, ~read: S -> IO(S & Result<&1, &1, U32 & String, U32>), source: S) ->
  IO(S & Result<&2, &2, TC.GenerationError, TC.LocalContext>)
TC.Context.child_with(~S, ~read, source: S, parent: TC.Parent, sampling: TC.Sampling) -> ...
TC.Context.restart_with(~S, ~read, source: S, previous: TC.RemoteContext) -> ...
TC.Source.tape(tape: List<&1, Result<&1, &1, U32 & String, U32>>) -> ...
```

A source is a template: `read` receives the source's state and returns the next
state with one word result, and the operation returns the final state. It reads
one word at a time and never more than it needs: at most 48 words for a root or
restart and 16 for a child. `Source.tape` replays a list of word results, so
tests and integrations can exercise zero words, reuse, failures and
exhaustion, and can check which words were read. Every source is trusted to be
random: a generated trace ID asserts random-trace-id whatever the source, and
the package cannot check the words' unpredictability.

The conversion is available on its own:

```bend
TC.TraceId.from_words(first: U32, second: U32, third: U32, fourth: U32) -> Maybe<&2, TC.TraceId>
TC.SpanId.from_words(first: U32, second: U32) -> Maybe<&2, TC.SpanId>
TC.U32.to_hex(word: U32) -> String
```

`U32.to_hex` gives a word's eight lowercase digits, most significant first,
and `from_words` returns `None{}` for an all-zero candidate. Like parsing,
`TraceId.from_words` makes no randomness assertion; add one with
`TraceId.assert_random` only when the words are random. The `Draw`/`Step`
machine that the operations share is stated in the laws but is internal, like
the parsing helpers: it is not a compatibility contract.

## Parsing contract

- Exactly 55 characters, version `00`, lowercase ASCII hexadecimal, and dashes
  at zero-based positions 2, 35 and 52.
- A 32-digit nonzero trace ID, a 16-digit nonzero parent ID and a two-digit
  flag byte. All 256 flag values are accepted and preserved by the codec.
- No trimming, case folding, suffix acceptance or header-name processing.
- The first error in parsing order is returned. Offsets count Bend `String`
  characters, not UTF-8 bytes.
- Parsing consumes bounded field widths and checks for trailing input without
  scanning an arbitrarily long suffix.

Supplied IDs follow the same rules for their single field: offsets count from
the start of the ID text, and extra characters after the last digit are
`TrailingInput{}`.

Structured errors are constructors of `Error`; callers may pattern-match on
them rather than parsing the human-readable result of `Error.show`:

| Error | Meaning |
| --- | --- |
| `UnexpectedEnd{offset}` | A required character is missing |
| `InvalidHex{offset}` | A character is not lowercase ASCII hexadecimal |
| `ExpectedSeparator{offset}` | A required dash is absent |
| `TrailingInput{}` | Extra characters follow the flag byte or a supplied ID |
| `ForbiddenVersion{}` | The version is `ff` |
| `UnsupportedVersion{version}` | A syntactically valid version is neither `00` nor `ff` |
| `ZeroId{TraceIdField{}}` | A trace ID is all zero |
| `ZeroId{ParentIdField{}}` | The parent ID is all zero |
| `ZeroId{SpanIdField{}}` | A supplied span ID is all zero |

Creating a context from valid IDs can only fail with a `ContextError`:
`ReusedSpanId{}` when a child uses its parent's span ID, and `ReusedTraceId{}`
when a restart uses the received trace ID.

These strict-codec errors are not the future propagator's extraction policy.
A valid future-version header can be rejected here while a participating
propagator would process its known prefix.

## Representation

`TraceParentV00` contains a `Digits.NonZero<32n>` trace ID, a
`Digits.NonZero<16n>` parent ID and `Digits.Digits(2n)` flags. Internally,
`Hex.Digit` has exactly 16 constructors and the digit sequence's length is
part of its type. Nonzero IDs carry checked evidence. Formatting cannot
encounter a typed ID with the wrong length or all zero digits. The public
constructors validate supplied text and create these indexed values
internally; direct construction requires matching indexed values and evidence.

In this compiler version the equality evidence stays available while composing
proofs. Compilation erases the proof body, but generated C/JS retains one
placeholder field per ID. There is no claim of zero representation overhead.

## Proofs

[LAWS.bend](LAWS.bend) states, and [PROOF.bend](PROOF.bend) proves, laws over
every value of their types, not over examples:

- **Codec:** `String.length(format(context)) == 55n`;
  `parse(format(context)) == Done{context}`, including the IDs, their evidence
  and all flag bits; and the inverse: for every `String` the parser accepts,
  formatting the result reproduces exactly that text.
- **Supplied IDs:** an accepted trace or span ID is exactly the text that was
  accepted, and a parsed trace ID makes no randomness assertion. Conversely,
  every trace ID's text is accepted and every span ID's text parses back to
  that span ID. `assert_random` changes only the assertion.
- **Construction:** `from_ids` keeps its IDs and sampled indication, and a root
  is `from_ids` with sampled `0`.
- **Children:** a successful child keeps the parent's trace ID and randomness
  assertion, uses the supplied span ID, whose text differs from the parent's,
  and takes sampled from `Sampling.resolve`: the parent's indication for
  `InheritSampled{}`, or the value of `SetSampled{value}`. A span ID with the
  parent's text fails with `ReusedSpanId{}`, and every other span ID creates
  the child.
- **Restarts:** a successful restart is the root of its supplied IDs, and its
  trace ID text differs from the received one. The received trace ID fails with
  `ReusedTraceId{}`, and every other trace ID creates the restart.
- **Flags:** every local context is emitted as version `00` with its IDs and
  one of `00`, `01`, `02`, `03`; receiving that value recovers its trace ID,
  randomness assertion, span ID and sampled indication; and a received context
  keeps the bits that `TraceParentV00.is_sampled` and `is_random` read. The
  corpus checks those two readers on all 256 flag bytes; no law restates them
  for the reserved bit patterns.
- **Conversion:** a candidate trace ID's text is `U32.to_hex` of its four words
  in reading order and a span ID's of its two. Read as a base-16 numeral,
  `U32.to_hex(word)` is the number Base's `U32.to_nat` assigns to the word, so
  digits are big-endian within each word too. `U32.to_hex` is injective, so no
  source information is lost, and converting words makes no randomness
  assertion.
- **Generation:** a source error ends generation at once. Reading a tape, the
  IO operations compute exactly the pure tape driver, word for word. For every
  tape, a root or restart ends within 48 words and a child within 16. Eight
  zero candidates exhaust a root's trace ID or a child's span ID without
  reading a ninth; the other exhaustion paths are tested. A generated root
  asserts randomness and is unsampled; a generated child keeps the parent's
  trace ID and randomness assertion, resolves sampled and never reuses the
  parent's span ID; a generated restart's trace ID differs from the received
  one, asserts randomness and is unsampled.

The generation laws quantify over tapes, that is, over every sequence of word
results. The host source runs through the same driver with its effect in
`read`; that path is tested, not proved.

Auxiliary universal proofs cover hexadecimal and character decoding, encoded
lengths, reading an encoded sequence while preserving its suffix, recovery of a
nonzero ID, string comparison and the word-to-digit round trip. Proofs use
structural induction/composition, without local axioms or `@unsafe`
shortcuts. The laws do not cover the origin of supplied IDs, the truth of a
randomness assertion, the quality of a source or global uniqueness.

## Validation and scope

The [public corpus](tests/TEST.bend) uses eight valid traceparent inputs, 26
malformed traceparent inputs with expected errors/positions, 14 malformed
supplied IDs, roots and children for all four known flag combinations, both
restart outcomes (`00` and `02`), and all 256 flag bytes. For each flag byte
it checks the codec, the received sampled and random bits and the flags a child
emits against independent numeric oracles. The [negative fixtures](tests/reject)
must fail typechecking for the intended nonzero, length and remote/local
mismatch.

The [generation corpus](tests/GENERATION.bend) replays tapes through the public
operations: conversion vectors in decimal for the W3C example words, the digit
order within a word, zero then valid candidates, eight zero candidates with no ninth read, a 48-word
worst case, a source error in the middle of a candidate, an empty tape, a
child that must not reuse the parent's span ID and a restart that must not
reuse the received trace ID, each checking how many words were left unread.
The [smoke check](tests/SMOKE.bend) and the
[generation example](examples/generate.bend) generate on the real host source;
they check only that the results are well formed. The JavaScript suite runs a compiled
root through WebCrypto with real host exceptions and counts the words read.
The [validation guide](../../README.md#validation) describes reproducible
commands and the separate clean consumer.

The strict v00 format follows
[W3C Trace Context Level 1](https://www.w3.org/TR/2021/REC-trace-context-1-20211123/#traceparent-header).
The planned propagator targets the pinned
[Level 2 Candidate Recommendation Draft](https://www.w3.org/TR/2024/CRD-trace-context-2-20240328/).
The random-trace-id flag `0x02` still uses wire version `00`.

This package does not yet implement tracestate, header extraction/injection,
future-version participation, browser generation or HTTP/browser
integration. Its faithful formatter does not mask reserved bits of a parsed
value; `LocalContext.to_traceparent` emits only known flags. There is no claim of
complete W3C propagator conformance or a full OpenTelemetry SDK.

See the [initial codec validation record](VALIDATION.md) for the original
execution evidence and [CHANGELOG.md](../../CHANGELOG.md) for versioning
and migration.
