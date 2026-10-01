# Bend API reference

This reference lists every public operation and type of the Bend package,
and what its laws prove. Start with the [guide](GUIDE.md) for the ideas and
recipes; [Errors and diagnostics](ERRORS.md) lists every error and log name,
and the [JavaScript guide](JAVASCRIPT.md) covers the facade.

The package has three public modules, and no dependency beyond the
compiler's bundled `Base`:

- [trace_context.bend](trace_context.bend), imported as `TC` below, decides
  every Trace Context rule and performs no host effect of its own;
- [generation.bend](generation.bend), `Generate` below, runs its generating
  operations on the host's cryptographic source;
- [native_http.bend](native_http.bend), `NativeHttp` below, adapts the header
  maps of bend-kit's HTTP package, without any host effect.

Names that this reference does not list, such as the `Headers`, `Scan` or
`Draw` helpers, are internal: Bend lets any module import them, but they
are not a compatibility contract. The [root README](../../README.md#install)
shows how to add the package to a project.

Most services need three operations: `TC.Context.extract`,
`Generate.Context.continue_or_start` and `Generate.Context.send`, in
[Extracting context](#extracting-context) and
[Continuing or starting a trace](#continuing-or-starting-a-trace). The
sections below build up to them from the codec. The package has two approved
specifications: "spec #1", its
[specification](https://github.com/LucasGois1/bend-trace-context/issues/1),
and "spec #41", which adds the
[building blocks](https://github.com/LucasGois1/bend-trace-context/issues/41)
that an OpenTelemetry SDK composes.

- [Codec API](#codec-api)
- [Supplied IDs and contexts](#supplied-ids-and-contexts)
- [Generated contexts](#generated-contexts)
- [Tracestate](#tracestate)
- [Updating and emitting tracestate](#updating-and-emitting-tracestate)
- [Extracting context](#extracting-context)
- [Injecting and forwarding context](#injecting-and-forwarding-context)
- [Continuing or starting a trace](#continuing-or-starting-a-trace), the
  operations that most services use
- [Host-driven generation](#host-driven-generation)
- [Native HTTP integration](#native-http-integration)
- [Parsing contract](#parsing-contract) and [representation](#representation)
- [Proofs](#proofs)

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

Context.root_from_ids(trace_id: TraceId, span_id: SpanId, sampled: Bool) -> LocalContext
Context.from_ids(trace_id: TraceId, span_id: SpanId, sampled: Bool) -> LocalContext
Context.child_from_id(parent: Parent, span_id: SpanId, sampling: Sampling) ->
  Result<&2, &2, ContextError, LocalContext>
Context.restart_from_ids(previous: RemoteContext, trace_id: TraceId, span_id: SpanId, sampled: Bool) ->
  Result<&2, &2, ContextError, LocalContext>
ContextError.show(error: ContextError) -> String

RemoteContext.from_traceparent(value: TraceParentV00) -> RemoteContext
RemoteContext.from_ids(trace_id: TraceId, span_id: SpanId, sampled: Bool) -> RemoteContext
LocalContext.to_traceparent(context: LocalContext) -> TraceParentV00
RemoteContext.flags(context: RemoteContext) -> U32
LocalContext.flags(context: LocalContext) -> U32
```

The `_from_ids` operations take identifiers the caller already has. The
operations that generate identifiers are `Context.root`, `Context.child` and
`Context.restart` in [generation.bend](#generated-contexts), and, one
identifier alone, `TraceId.generate` and `SpanId.generate`.

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

- `Context.root_from_ids` starts a trace with the sampled indication that
  the caller decided
  ([spec #41](https://github.com/LucasGois1/bend-trace-context/issues/41),
  "Sampling decision when starting a trace"): `False{}` for a root that is
  not sampled, spec #1's default for new roots, and `True{}` to sample it.
  It carries the random-trace-id flag only when its trace ID asserts it.
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
  where a received context is not continued: the root of the supplied IDs,
  with the sampled indication that it is given, so `False{}` applies the
  root defaults, including sampled `0`. It takes only the received context,
  none of its state. A trace ID equal to the received one fails with
  `ReusedTraceId{}`, even when only the randomness assertion differs.
  [`Context.continue_or_start`](#continuing-or-starting-a-trace) restarts at a
  trust boundary with a sampling policy of the caller's choice.

No operation that starts a trace, from supplied IDs or
[generated](#generated-contexts), applies a default of its own: the default
of new traces, not sampled, lives in
[`continue_or_start`](#continuing-or-starting-a-trace), which resolves its
`sampling` over it and passes the result to root and restart generation.
`False{}` gives an unsampled root or restart, as `continue_or_start` starts
one by default.

`RemoteContext.from_traceparent` receives a strictly parsed v00 value. It keeps
the trace ID, the sender's span ID, sampled and random-trace-id; reserved flag
bits are not part of a remote context. The strict codec rejects versions `01`
to `fe`, which [extraction](#extracting-context) reads by their known prefix.
`RemoteContext.from_ids` builds the sender's context from its parts instead,
as an OpenTelemetry SDK does for a link or for a propagator of another
format ([spec #41](https://github.com/LucasGois1/bend-trace-context/issues/41)).
It is total, since the IDs are valid by construction, and it keeps them and
the sampled indication as they are. Its random-trace-id bit is its trace
ID's assertion: a parsed trace ID makes none, and `TraceId.assert_random`
adds one when the sender asserted it. It is still a received context, with
no received pair to forward: it never leaves the participant as itself, and
only a child of it does ([Sending a remote context](#sending-a-remote-context)).
`LocalContext.to_traceparent` gives the participating
representation: version `00` and flags `00` to `03`, with every reserved bit
zero. [Injection](#injecting-and-forwarding-context) writes that
representation into a message, and forwarding sends a received value
unchanged.

`RemoteContext.flags` and `LocalContext.flags` give a context's trace flags
as a number from 0 to 3, which an exporter writes into OTLP's `Span.flags`
field, for example: bit 0 is sampled, and bit 1 is random-trace-id, from the
trace ID's assertion. A local context's value is the flag byte of the
traceparent that it emits, `00` to `03`, and a remote context's is the known
flags that it was received or built with, never its reserved bits. The
Booleans stay the canonical form, `is_sampled` and `TraceId.is_random`:
there is no trace flags type.

`RemoteContext` and `LocalContext` are separate types, so a received context,
parsed or built from parts, cannot be passed where a local one is expected (the
[negative fixture](tests/reject/remote_as_local.bend) checks this). Bend
constructors are not private, however: code that builds a `LocalContext{...}`
value directly bypasses these operations, and no type can reject that.

The [consumer example](../../tests/consumer/main.bend) receives a context,
creates a server operation and sampled and unsampled client operations,
rejects a reused span ID, restarts a trace and starts a root, each unsampled
and sampled, and represents an existing operation with `Context.from_ids`.

### Identifiers as bytes

A trace or span ID has two forms: its lowercase hexadecimal text, which
`to_string` gives, `parse` reads and a traceparent carries, and its bytes.
OTLP, which exporters speak, writes the bytes in its protobuf encoding and
the text in its JSON encoding.

```bend
TraceId.to_bytes(id: TraceId) -> List<&2, U32>
TraceId.from_bytes(bytes: List<&2, U32>) -> Result<&2, &2, Error, TraceId>
SpanId.to_bytes(id: SpanId) -> List<&2, U32>
SpanId.from_bytes(bytes: List<&2, U32>) -> Result<&2, &2, Error, SpanId>
```

Bytes follow Base's convention, the one of `TCP.send_bytes` and
`TCP.recv_bytes`: a list of `U32` cells, one per byte, each from 0 to 255.
A trace ID is 16 bytes and a span ID 8, most significant first: the first
byte holds the first two digits of the text, the first of them high. The
W3C example trace ID `4bf92f3577b34da6a3ce929d0e0e4736` is the bytes
`75, 249, 47, 53, 119, 179, 77, 166, 163, 206, 146, 157, 14, 14, 71, 54`,
and the span ID `00f067aa0ba902b7` the bytes
`0, 240, 103, 170, 11, 169, 2, 183`.

`from_bytes` checks bytes from another system as `parse` checks text. It
reads the cells in order and reports the first problem as an `Error`, with
an offset that counts cells from the start of the list:

- `UnexpectedEnd{offset}` when the list ends before the ID's last byte;
- `InvalidByte{offset}` for a cell above 255;
- `TrailingInput{}` for a cell after the ID's last byte, whatever it and the
  cells after it hold;
- `ZeroId{TraceIdField{}}` or `ZeroId{SpanIdField{}}` when every byte is
  zero.

Every other list of 16 or 8 bytes is accepted, and gives the ID whose bytes
it is. Like a parsed trace ID, a trace ID read from bytes makes no
randomness assertion: a caller who knows that its IDs are random, because
its own generator made them, adds it with `TraceId.assert_random`.
`to_bytes` leaves the assertion out, so a trace ID and its asserted copy
have the same bytes. The guide's
[SDK building blocks](GUIDE.md#identifiers-as-bytes-and-as-hex) show both
forms in an exporter.

## Generated contexts

[generation.bend](generation.bend) generates identifiers on the host's
cryptographic source: the operating system's generator natively
(`arc4random_buf` on macOS, `getrandom` on Linux, as Base's `IO.random_u32`)
and WebCrypto in JavaScript. Qualified here for native programs and for Bend
programs compiled to Node. JavaScript applications and browser pages generate
through the [JavaScript facade](JAVASCRIPT.md), which feeds WebCrypto words
to the same machine. Names below are qualified by the aliases `Generate` for
generation.bend and `TC` for trace_context.bend:

```bend
Generate.Context.root(sampled: Bool) -> IO(Result<&2, &2, TC.GenerationError, TC.LocalContext>)
Generate.Context.child(parent: TC.Parent, sampling: TC.Sampling) ->
  IO(Result<&2, &2, TC.GenerationError, TC.LocalContext>)
Generate.Context.restart(previous: TC.RemoteContext, sampled: Bool) ->
  IO(Result<&2, &2, TC.GenerationError, TC.LocalContext>)
TC.GenerationError.show(error: TC.GenerationError) -> String
```

The [generation example](examples/generate.bend) starts a trace that is not
sampled and creates the operation that calls another service. From the
repository root:

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
  random-trace-id. A root or restart has the sampled indication that it is
  given, as `Context.root_from_ids` does, so it is emitted with flags `02`
  for `False{}` and `03` for `True{}`. A child keeps its parent's trace ID and
  randomness assertion and resolves sampled as `Context.child_from_id` does,
  so generating its span ID never changes a received random bit.

A generation fails with a `GenerationError`: `SourceFailure{code, message}`
when the source fails, and `ExhaustedTraceId{}` or `ExhaustedSpanId{}` after
eight rejected candidates. [Errors and diagnostics](ERRORS.md#generation)
lists the failures of each source; the tests induce the JavaScript failures
but not the native one.

The same operations take a caller's source in trace_context.bend:

```bend
TC.Context.root_with(~S: Type, ~read: S -> IO(S & Result<&1, &1, U32 & String, U32>), source: S, sampled: Bool) ->
  IO(S & Result<&2, &2, TC.GenerationError, TC.LocalContext>)
TC.Context.child_with(~S, ~read, source: S, parent: TC.Parent, sampling: TC.Sampling) -> ...
TC.Context.restart_with(~S, ~read, source: S, previous: TC.RemoteContext, sampled: Bool) -> ...
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
`TraceId.assert_random` only when the words are random. The machine that the
operations share is stated in the laws but is internal, like the parsing
helpers: its trace ID and span ID draws (`TraceDraw` and `SpanDraw`), the
generation that composes them (`Draw`, `Step`, `SpanPlan` and `TracePlan`,
the plan of a root or a restart) and the driver that runs all three
(`Drive`) are not a compatibility contract. A host that
feeds words itself drives it through `Generation`, described in
[Host-driven generation](#host-driven-generation).

### A trace ID or a span ID alone

An OpenTelemetry SDK starts a span in three steps: it generates a trace ID,
asks its sampler about it, and only then generates the span ID. These
operations generate one identifier alone, on the host's cryptographic source
or on a caller's:

```bend
Generate.TraceId.generate(excluded: Maybe<&2, TC.TraceId>) -> IO(Result<&2, &2, TC.GenerationError, TC.TraceId>)
Generate.SpanId.generate(excluded: Maybe<&2, TC.SpanId>) -> IO(Result<&2, &2, TC.GenerationError, TC.SpanId>)
TC.TraceId.generate_with(~S, ~read, source: S, excluded: Maybe<&2, TC.TraceId>) ->
  IO(S & Result<&2, &2, TC.GenerationError, TC.TraceId>)
TC.SpanId.generate_with(~S, ~read, source: S, excluded: Maybe<&2, TC.SpanId>) ->
  IO(S & Result<&2, &2, TC.GenerationError, TC.SpanId>)
```

They follow the rules above, one identifier at a time: a trace ID reads at
most 32 words and a span ID 16. A candidate equal to `excluded`, when it is
`Some{id}`, is rejected as a child's candidate equal to its parent's span ID
is, and only that identifier is compared: an SDK passes a parent's span ID
when it generates a child's, and siblings get different span IDs as long as
the source's words differ.

The `_with` forms take a source as the operations above do and return its
final state, so a test replays a tape with `Source.tape`. A context of the
generated IDs is `Context.from_ids(trace_id, span_id, sampled)`, with the
sampled indication that the caller's sampler decided; the
[guide](GUIDE.md#building-blocks-for-an-opentelemetry-sdk) shows an SDK's
steps.

Root, child and restart generation are compositions of these operations: a
root is a trace ID, then a span ID from the source's next state, and the
context of both with the sampled indication that the root is given; a child
is a span ID that excludes the parent's; a restart is a trace ID that
excludes the received one, then a span ID, as for a root.
`Context.root_with`, `child_with` and `restart_with` are these
compositions, and `Generate.Context.root` and its siblings run them on the
host's source, with the word order, budgets and results described above. A
root or a restart takes its sampled indication before its trace ID exists,
so an SDK whose sampler decides on the trace ID composes the steps itself.

## Tracestate

`TraceState` holds the vendor entries of a received `tracestate` in order: at
most 32 entries with distinct keys, the leftmost first. It follows the Level 2
grammar of the pinned publication. Names below are qualified by the alias `TC`
for trace_context.bend:

```bend
TC.TraceState.parse(limits: TC.Limits, text: String) -> Result<&2, &2, TC.StateError, TC.TraceState>
TC.TraceState.parse_fields(limits: TC.Limits, fields: List<&2, String>) ->
  Result<&2, &2, TC.StateError, TC.TraceState>
TC.TraceState.get(state: TC.TraceState, key: TC.StateKey) -> Maybe<&2, TC.StateValue>
TC.TraceState.format(state: TC.TraceState) -> String
TC.TraceState.entries(state: TC.TraceState) -> List<&2, TC.StateEntry>
TC.TraceState.is_empty(state: TC.TraceState) -> Bool
TC.TraceState.empty() -> TC.TraceState
TC.StateEntry.key(entry: TC.StateEntry) -> TC.StateKey
TC.StateEntry.key_text(entry: TC.StateEntry) -> String
TC.StateEntry.value(entry: TC.StateEntry) -> TC.StateValue
TC.StateEntry.format(entry: TC.StateEntry) -> String
TC.StateKey.parse(text: String) -> Result<&2, &2, TC.EntryError, TC.StateKey>
TC.StateKey.to_string(key: TC.StateKey) -> String
TC.StateValue.parse(text: String) -> Result<&2, &2, TC.EntryError, TC.StateValue>
TC.StateValue.to_string(value: TC.StateValue) -> String
TC.StateError.show(error: TC.StateError) -> String
TC.EntryError.show(error: TC.EntryError) -> String
```

`parse_fields` takes the repeated `tracestate` field values of a message in
arrival order and reads them as their comma-joined combination, so member
numbers run across fields. Read a message's tracestate only once its
traceparent has been accepted: the standard gives tracestate no meaning
without a valid traceparent, and [extraction](#extracting-context) applies
that rule itself. `parse` reads one combined value. `format` returns
the normalized value: the entries in order, as `key=value`, joined by commas
without optional whitespace. The empty state formats as `""`, which
[injection](#injecting-and-forwarding-context) does not write. `get` takes a
validated key: the application parses its own key once with
`StateKey.parse`, as it does its IDs.

The [tracestate example](examples/tracestate.bend) reads two received fields,
looks up its own entry and shows a discarded value. From the repository root:

```sh
./bend packages/trace-context/examples/tracestate.bend
```

```text
tracestate: congo=t61rcWkgMzE,rojo=00f067aa0ba902b7
congo: t61rcWkgMzE
discarded: InvalidEntry 1 InvalidKey
```

### Grammar and reading rules

- A key has 1 to 256 characters: a lowercase ASCII letter or a digit, then
  lowercase letters, digits, `_`, `-`, `*`, `/` or `@`. The Level 1
  `tenant@system` restriction does not apply.
- A value has 1 to 256 printable ASCII characters (`0x20` to `0x7E`) other
  than `,` and `=`, and does not end with a space. Leading spaces are part of
  the value.
- Spaces and horizontal tabs around a member are optional whitespace: before a
  key they are skipped, and after a value they are not part of it. No
  whitespace may separate a key from its `=`. Other whitespace, such as
  newlines, is refused.
- Empty and whitespace-only members are ignored and are not counted.
- The value is read left to right, and reading stops at the first problem.
  Every nonempty member is validated when it is reached, before duplicates are
  considered, so a malformed duplicate is never dropped silently. It then
  counts toward the 32 members allowed, whether or not its key is new: a 33rd
  member fails with `TooManyMembers{}` even when it repeats a key.
- The first entry of each key is kept; later entries with that key are
  dropped.
- Any invalid member or a 33rd member discards the whole state.
  [Extraction](#extracting-context) keeps a valid traceparent when its state is
  discarded.

### Limits

`Limits` bounds what a received message may make the package read and what it
emits. Every budget counts UTF-8 octets; Bend characters are Unicode code
points, measured by their UTF-8 encoding.

```bend
TC.Limits.default() -> TC.Limits
TC.Limits.new(traceparent_input: Nat, tracestate_input: Nat, tracestate_output: Nat) ->
  Result<&2, &2, TC.LimitsError, TC.Limits>
TC.Limits.traceparent_input(limits: TC.Limits) -> Nat
TC.Limits.tracestate_input(limits: TC.Limits) -> Nat
TC.Limits.tracestate_output(limits: TC.Limits) -> Nat
TC.LimitsError.show(error: TC.LimitsError) -> String
```

| Budget | Default | Rule |
| --- | --- | --- |
| `traceparent_input` | 32768 | At least 55, the size of an emitted traceparent |
| `tracestate_input` | 32768 | At least `tracestate_output`, so a configuration accepts what it emits |
| `tracestate_output` | 512 | At least 512 |

The 512-octet output budget is this package's capacity policy, not a W3C
maximum; emission truncates to it (see
[Updating and emitting tracestate](#updating-and-emitting-tracestate)). The
traceparent input budget bounds a received traceparent value (see
[Extracting context](#extracting-context)). `Limits.new` reports the first
rule a configuration breaks.

The tracestate input budget bounds the combined value, its whitespace and the
commas that join repeated fields included. A value over the budget fails with
`StateTooLarge{}` before any member is read, whatever it contains; measuring
stops at the first character past the budget, so the rest of an oversized
input is never read. Limits applied by a transport before the package remain
the transport's responsibility.

### Diagnostics

`TraceState.parse` and `parse_fields` fail with a `StateError`,
`StateKey.parse` and `StateValue.parse` with an `EntryError`, and
`Limits.new` with a `LimitsError`; Errors and diagnostics lists each
[tracestate error](ERRORS.md#tracestate) and
[limits error](ERRORS.md#limits) with its name. `StateKey.parse` and
`StateValue.parse` fail with `InvalidKey{}` and `InvalidValue{}`; they trim
nothing, so a value with a trailing space is refused there. Diagnostics carry positions and categories, never the received
text, and the package does not log.

Parsing does not attach state to a context, and a parsed state gives no
permission to change the state sent with an unchanged remote traceparent;
[Updating and emitting tracestate](#updating-and-emitting-tracestate)
explains how state travels with a local operation. As with the
contexts, Bend constructors are not private: `StateKey`, `StateValue` and
`TraceState` values carry proofs of their rules, so direct construction must
supply them (the [negative fixture](tests/reject/invalid_state_key.bend) is
refused). The reading machine behind `parse` (`Scan`, `Member`) and the
measuring helpers (`Utf8`, `Budget`) are internal; the laws state budgets with
`Utf8.length`.

## Updating and emitting tracestate

A participant edits the state it sends with an operation of its own: a
changed entry moves to the front and the other entries keep their order (W3C
Level 2, section 3.5). The state it emits must fit the output budget of its
limits.

```bend
TC.TraceState.set(state: TC.TraceState, key: TC.StateKey, value: TC.StateValue) -> TC.TraceState
TC.TraceState.remove(state: TC.TraceState, key: TC.StateKey) -> TC.TraceState
TC.TraceState.size(state: TC.TraceState) -> Nat
TC.TraceState.truncate(limits: TC.Limits, state: TC.TraceState) -> TC.Truncation
TC.Truncation.kept(truncation: TC.Truncation) -> TC.TraceState
TC.Truncation.dropped(truncation: TC.Truncation) -> List<&2, TC.StateKey>
TC.StateEntry.size(entry: TC.StateEntry) -> Nat
```

- `set` adds or updates the entry of a key: it goes first with the new
  value, and at most 31 of the other entries follow, in their order.
  Updating a key that the state has evicts nothing, even from a full state;
  adding a new key to a full state removes the last entry.
- `remove` deletes the entry of a key, if there is one, and keeps the others
  in order. W3C asks participants not to delete keys that other vendors
  generated; the package cannot tell who generated a key, so that choice is
  the caller's.
- `size` is the number of UTF-8 octets of `format(state)`: each entry's key,
  `=` and value, and the commas between entries.
- `truncate` fits a state to the tracestate output budget by removing whole
  entries (section 3.3.3.1 and spec #1): while the value is over the budget,
  it removes the rightmost entry larger than 128 octets, or the rightmost
  entry when none is, and it stops as soon as the value fits. The surviving
  entries keep their order. `dropped` lists the keys of the removed entries
  in their original order, and is empty when nothing was removed. It reports
  keys, not the opaque values.

### Outgoing contexts

An `OutgoingContext` is a local context together with the state its participant
sends with it:

```bend
TC.OutgoingContext.new(context: TC.LocalContext) -> TC.OutgoingContext
TC.OutgoingContext.with_state(context: TC.LocalContext, state: TC.TraceState) -> TC.OutgoingContext
TC.OutgoingContext.context(outgoing: TC.OutgoingContext) -> TC.LocalContext
TC.OutgoingContext.state(outgoing: TC.OutgoingContext) -> TC.TraceState
TC.OutgoingContext.get(outgoing: TC.OutgoingContext, key: TC.StateKey) -> Maybe<&2, TC.StateValue>
TC.OutgoingContext.set(outgoing: TC.OutgoingContext, key: TC.StateKey, value: TC.StateValue) -> TC.OutgoingContext
TC.OutgoingContext.remove(outgoing: TC.OutgoingContext, key: TC.StateKey) -> TC.OutgoingContext
TC.OutgoingContext.emit(limits: TC.Limits, outgoing: TC.OutgoingContext) -> TC.Emission
TC.Emission.traceparent(emission: TC.Emission) -> String
TC.Emission.tracestate(emission: TC.Emission) -> String
TC.Emission.dropped(emission: TC.Emission) -> List<&2, TC.StateKey>
```

`OutgoingContext.new` gives a context with no state, as for a new root;
`OutgoingContext.with_state` attaches a state, such as the state received with the
parent of a child operation. Editing an outgoing context changes only its
state. `emit` gives the two header values to send: the participating
traceparent of the local context, and the normalized value of its state
truncated to the output budget, `""` when there is no state. The same limits
always accept the emitted value when parsing it.

Editing a `TraceState` value is a pure operation, and it does not authorize
sending the result with a received traceparent: the standard forbids
changing or truncating the state of a traceparent that is sent unchanged (W3C
Level 2, section 3.4). A service that changes the state it passes on creates
a child operation first, so the new traceparent identifies its own
operation. An outgoing context holds a local context, so a `RemoteContext`
cannot be passed to it; a local context built with `Context.from_ids` must
carry the IDs of the caller's own operation, which the package cannot check.
[Forwarding](#injecting-and-forwarding-context) sends a received pair
unchanged, and refuses when it cannot.

The [outgoing example](examples/outgoing.bend) continues a received trace with
a child operation, puts its own entry first and emits both fields, then shows
the truncation of a state that exceeds 512 octets. From the repository root:

```sh
./bend packages/trace-context/examples/outgoing.bend
```

```text
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-53995c3f42cd8ad8-01
tracestate: fw529a3039=cHJpbWFyeQ,congo=t61rcWkgMzE,rojo=00f067aa0ba902b7
dropped: none
large state: 298 octets sent, dropped: b
```

## Extracting context

`Context.extract` reads the trace context of a received message from its
carrier: the message's fields in their order, each a `Header`. Names below are
qualified by the alias `TC` for trace_context.bend:

```bend
TC.Context.extract(limits: TC.Limits, carrier: List<&2, TC.Header>, base: Maybe<&2, TC.BaseContext>) ->
  TC.Extraction
TC.TraceParent.read(limits: TC.Limits, value: String) -> Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>
TC.Header.name(header: TC.Header) -> String
TC.Header.value(header: TC.Header) -> String
TC.Extraction.context(extraction: TC.Extraction) -> Maybe<&2, TC.BaseContext>
TC.Extraction.incoming(extraction: TC.Extraction) -> Maybe<&2, TC.IncomingContext>
TC.Extraction.parent(extraction: TC.Extraction) -> TC.TraceParentOutcome
TC.Extraction.state(extraction: TC.Extraction) -> TC.StateOutcome
TC.Extraction.show(extraction: TC.Extraction) -> String
TC.IncomingContext.context(incoming: TC.IncomingContext) -> TC.RemoteContext
TC.IncomingContext.state(incoming: TC.IncomingContext) -> TC.TraceState
TC.IncomingContext.received(incoming: TC.IncomingContext) -> Maybe<&2, TC.ReceivedPair>
TC.IncomingContext.parent(incoming: TC.IncomingContext) -> TC.Parent
TC.IncomingContext.from_remote(context: TC.RemoteContext, state: TC.TraceState) -> TC.IncomingContext
TC.ReceivedPair.traceparent(pair: TC.ReceivedPair) -> String
TC.ReceivedPair.tracestate(pair: TC.ReceivedPair) -> List<&2, String>
TC.BaseContext.parent(base: TC.BaseContext) -> TC.Parent
TC.BaseContext.state(base: TC.BaseContext) -> TC.TraceState
TC.TraceParentError.show(error: TC.TraceParentError) -> String
TC.TraceParentOutcome.show(outcome: TC.TraceParentOutcome) -> String
TC.StateOutcome.show(outcome: TC.StateOutcome) -> String
```

| Type | Meaning |
| --- | --- |
| `Header` | `Header{name, value}`: one field of a message. A carrier is a `List<&2, Header>` in the message's order |
| `IncomingContext` | The sender's `RemoteContext` together with the state that goes with it: one extracted from a message, which also keeps the received pair when the whole pair was accepted, or one built from parts, which keeps none |
| `ReceivedPair` | The accepted traceparent value, without the whitespace around it, and the tracestate field values as they came |
| `BaseContext` | `IncomingBase{incoming}` or `OutgoingBase{outgoing}`: the context to continue from when a message has no usable traceparent |
| `Extraction` | The context to continue from, if any, with a `TraceParentOutcome` and a `StateOutcome` |

Extraction follows these rules:

- Field names are compared without regard to ASCII case (W3C Level 2,
  sections 3.2.1 and 3.3.1): `TraceParent`, `TRACEPARENT` and `traceparent`
  name the same field, while `trace-parent`, or a name that differs by a
  non-ASCII letter such as `traceſtate`, names another field.
- No traceparent field keeps the base. More than one traceparent field,
  whatever the case of their names, is refused with `RepeatedTraceParent{}`,
  and so is a single value that contains a comma: a host may join repeated
  fields into one value with commas (RFC 9110, section 5.3). This includes a
  comma in the unknown fields of a later version. W3C asks not to assume
  anything about those fields; the package accepts that small departure so
  that a joined pair of traceparent fields is never read as one parent. No
  version defines a comma.
- A single value is read by `TraceParent.read`:
  - its UTF-8 octets, whitespace and unknown fields included, must fit the
    traceparent input budget, or it is refused with `TraceParentTooLarge{}`
    without being read further;
  - the optional whitespace around it, spaces and tabs, is removed (RFC 9110,
    section 5.5);
  - version `00` is read exactly by the strict codec: 55 characters and
    nothing after them;
  - version `ff` is refused with `ForbiddenVersion` (section 3.2.2.1);
  - versions `01` to `fe` are read by their known prefix: the trace ID, parent
    ID and flags of version 00, followed by the end of the value or by a dash
    and fields that are not read, whatever they hold other than a comma or a
    control character (sections 3.2.4 and 4.1.2);
  - a control character other than a tab in those fields, which no field
    value may hold (RFC 9110, section 5.5), is refused with
    `ControlCharacter{offset}`. A carriage return or a line feed would end the
    field, so a value forwarded unchanged could add fields to the message;
    this is a second small departure from W3C's advice not to look at unknown
    fields;
  - any other problem is reported with the codec's `Error`, its offset
    counted from the first character after the whitespace.
- An accepted value gives an incoming context, which replaces the base. Its
  sender's operation keeps the sampled and random-trace-id flags of the value.
  Its tracestate fields, whatever the case of their names, are read in
  arrival order as their comma-joined combination within the tracestate input
  budget, as `TraceState.parse_fields` reads them. Refused fields are
  discarded as a whole with `StateDiscarded{error}`: the traceparent stays
  accepted, the incoming context has no state, and no received pair is kept,
  since the pair was not accepted whole.
- Without an accepted traceparent the tracestate fields are not read
  (section 3.3): `StateIgnored{}` reports that there were some.
- Extraction generates no identifier and performs no effect, and no
  diagnostic contains a received value.

`Extraction.parent` gives the traceparent's outcome: accepted, absent, or
rejected with a `TraceParentError`. `Extraction.state` gives the
tracestate's: absent, accepted, discarded with a `StateError`, or ignored
without an accepted traceparent.
[Errors and diagnostics](ERRORS.md#extraction) lists each outcome and
error. `Extraction.show` joins both outcomes for a log line, such as
`TraceParentAccepted, StateDiscarded InvalidEntry 1 MissingEquals`.

An incoming context identifies the sender's operation, not one of this
participant's. A service continues it with a child operation,
`Context.child_from_id(IncomingContext.parent(incoming), span_id, sampling)`
with a supplied span ID or `Context.child` of generation.bend with a generated
one, and sends the received state with the child in an `OutgoingContext`.
`BaseContext.parent` and `BaseContext.state` give the same for a base.
[`Context.continue_or_start`](#continuing-or-starting-a-trace) does this for
a message and its base in one step. The received pair is what
[forwarding](#injecting-and-forwarding-context) sends unchanged; it is
`None{}` when the tracestate was discarded. Only the pairs that
extraction keeps are known to be accepted and within the input budgets: as
with the contexts, Bend constructors are not private, and an
`IncomingContext` or `ReceivedPair` built directly carries no such
guarantee, so forwarding checks what it sends.

`IncomingContext.from_remote` builds an incoming context from its parts: a
remote context, such as one of `RemoteContext.from_ids`, and the tracestate
that goes with it, which may be `TraceState.empty()`. An OpenTelemetry SDK
gives its remote span contexts this one shape, whatever format they came
from ([spec #41](https://github.com/LucasGois1/bend-trace-context/issues/41)).
It keeps both parts as they are and no received pair, since no message's
fields were accepted: a child continues it as any incoming context, and
forwarding refuses it with `NothingToForward{}`, as
[Sending a remote context](#sending-a-remote-context) describes.

The carrier holds what the host hands over. A host that joins repeated fields
into one value turns a repeated traceparent into a value with a comma, which
is refused, and a joined tracestate reads as its separate fields would. What a
host does to names and whitespace before extraction is documented by its
adapter.

The [extraction example](examples/extract.bend) extracts a request with two
tracestate fields, continues it with a child, reads a later version and keeps
a base for an invalid request. From the repository root:

```sh
./bend packages/trace-context/examples/extract.bend
```

```text
request: TraceParentAccepted, StateAccepted
received state: congo=t61rcWkgMzE,rojo=00f067aa0ba902b7
kept for forwarding: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01 | congo=t61rcWkgMzE | rojo=00f067aa0ba902b7
child traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-53995c3f42cd8ad8-01
child tracestate: fw529a3039=cHJpbWFyeQ,congo=t61rcWkgMzE,rojo=00f067aa0ba902b7
later version: TraceParentAccepted, StateAbsent, parent 00f067aa0ba902b7
invalid request: TraceParentRejected InvalidTraceParent ZeroTraceId, StateIgnored
kept base: 00-5b8efff798038103d269b633813fc60c-eee19b7ec3c1b174-00
```

## Injecting and forwarding context

A service writes a context into the carrier of a message it sends in one of
two ways: as a participant, it injects an operation of its own; as an
intermediary that takes no part in the trace, it forwards a received context
unchanged. Names below are qualified by the alias `TC` for trace_context.bend:

```bend
TC.Context.inject(limits: TC.Limits, outgoing: TC.OutgoingContext, carrier: List<&2, TC.Header>) -> TC.Injection
TC.Context.clear(carrier: List<&2, TC.Header>) -> List<&2, TC.Header>
TC.Context.forward(limits: TC.Limits, incoming: TC.IncomingContext, carrier: List<&2, TC.Header>) ->
  Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>
TC.Injection.carrier(injection: TC.Injection) -> List<&2, TC.Header>
TC.Injection.dropped(injection: TC.Injection) -> List<&2, TC.StateKey>
TC.ForwardError.show(error: TC.ForwardError) -> String
TC.Context.field_names() -> List<&2, String>
```

All three remove every `traceparent` and `tracestate` field of the carrier,
whatever the ASCII case of its name, keep the other fields in their order, and
add their own fields at the end with lowercase names (W3C Level 2, sections
3.2.1 and 3.3.1). Injecting or forwarding the same context into the carrier
it wrote gives that carrier again, so a reused container or a retried request
does not accumulate fields.

- `inject` writes what the outgoing context emits: the participating
  traceparent, version `00` with only the sampled and random-trace-id flags,
  and the state truncated to the output budget, left out when it is empty.
  `Injection.dropped` gives the keys that truncation removed, apart from the
  carrier. A receiver that extracts the carrier with the same limits
  continues exactly the injected operation, with the truncated state.
- `clear` removes the context fields alone, for a message sent without
  context.
- `forward` writes the received pair of an incoming context as it came: the
  traceparent value without the whitespace around it, whatever its version,
  reserved flag bits and unknown fields, and the tracestate fields joined
  into one field by commas, as W3C
  section 3.3.2 recommends, byte for byte; the tracestate field is left out
  when that joined value is empty, as injection leaves out an empty state.
  It never normalizes flags, downgrades a version or edits the tracestate
  (section 3.4). When the pair cannot be sent whole, it fails and writes
  nothing.

`Context.field_names()` gives the names of the context fields as `inject`
writes them, and as extraction and cleanup read them: `traceparent`, then
`tracestate`. A propagator that lists the fields it writes, as
OpenTelemetry's propagators do, returns them. An OpenTelemetry SDK's W3C
propagator stays thin: it passes `Context.extract` a carrier built from what
OpenTelemetry's getter reads, and writes the values of `OutgoingContext.emit`
under these names through OpenTelemetry's setter, the tracestate only when it
is not empty, as `inject` does.

`forward` fails with a `ForwardError`: `NothingToForward{}` when the
context keeps no received pair, `ForwardTooLarge{}` over the output budget,
or `InvalidForwardParent{error}` and `InvalidForwardState{error}`; see
[Errors and diagnostics](ERRORS.md#forwarding). The last two refuse a pair
built directly, or one that extraction accepted under larger input budgets:
under the limits of its extraction, the pair of a context that extraction
accepted passes them, so the output budget is the only reason it is refused. A received tracestate within the 32 KiB input
budget may exceed the 512-octet default output budget. A service that cannot
forward such a pair, or that changes the state it passes on, continues the
trace with a child operation of its own and injects it instead: the child's
traceparent lets its state be truncated. Limits with a larger output budget
forward the pair whole.

The [injection example](examples/inject.bend) continues a handled request with
a child and injects it into a reused container, forwards a later version with
every flag bit set, clears a message sent without context, and continues a
request whose state is too large to forward. From the repository root:

```sh
./bend packages/trace-context/examples/inject.bend
```

```text
sent on: Host: inventory.internal | Content-Type: application/json | traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-53995c3f42cd8ad8-01 | tracestate: fw529a3039=cHJpbWFyeQ,congo=t61rcWkgMzE,rojo=00f067aa0ba902b7
relayed: Host: billing.internal | traceparent: cc-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-ff-future | tracestate: congo=t61rcWkgMzE,rojo=00f067aa0ba902b7
without context: Host: metrics.internal
not forwarded: ForwardTooLarge
continued instead: 00-4bf92f3577b34da6a3ce929d0e0e4736-b7ad6b7169203331-01, dropped b
```

### Sending a remote context

A remote context, however it was built, leaves the participant in one way
only: `forward` sends the received pair of the incoming context that holds
it, unchanged
([spec #41](https://github.com/LucasGois1/bend-trace-context/issues/41)).
W3C Level 2, section 3.4, lets a traceparent go out unchanged only with its
tracestate unchanged. A traceparent written again from a remote context's
IDs names the sender's operation as the received one did, but it is not the
received pair: its version and flags may be normalized, and its tracestate
dropped or rewritten. No operation of the package writes one.

An incoming context without a received pair, one that
[`IncomingContext.from_remote`](#extracting-context) builds from parts or
one whose tracestate extraction discarded, has nothing to forward: `forward`
fails with `NothingToForward{}` and nothing is written. A relay, which
forwards transparently, then sends the message without context, and `clear`
removes the context fields that it still holds, such as those of a reused
container. A service that takes part in the trace continues the context with
a child and injects the child instead. The
[consumer example](../../tests/consumer/main.bend) builds a remote and an
incoming context from parts, and shows forwarding refused with
`NothingToForward` and the message's context fields cleared.

OpenTelemetry JavaScript does otherwise. The code of its
`W3CTraceContextPropagator.inject` in `@opentelemetry/core` 2.11.0, the
version that `package-lock.json` pins
(`build/src/trace/W3CTraceContextPropagator.js`), writes a new traceparent
from any valid span context, remote ones included: version `00`, the span
context's trace ID, span ID and trace flags, with the tracestate that it
holds. A relay built on it therefore sends a context where one built on this
package sends none, and a traceparent received with a later version goes out
as version `00`. This description comes from reading that code: no test of
this repository injects a remote span context with it.

## Continuing or starting a trace

A service needs an operation of its own for each message it receives, and
each message it sends needs an operation too. `Context.continue_or_start` and
`Context.send` of generation.bend give both on the host's cryptographic
source, once [extraction](#extracting-context) has read the received
message's fields. Names below are qualified by the aliases `Generate` for
generation.bend and `TC` for trace_context.bend:

```bend
Generate.Context.continue_or_start(extraction: TC.Extraction, reception: TC.Reception, sampling: TC.Sampling,
  policy: TC.FailurePolicy) -> IO(TC.FailurePolicy.result(policy, TC.Service))
Generate.Context.send(limits: TC.Limits, service: TC.Service, sampling: TC.Sampling, policy: TC.FailurePolicy,
  carrier: List<&2, TC.Header>) -> IO(TC.FailurePolicy.result(policy, TC.Sent))
TC.FailurePolicy.result(policy: TC.FailurePolicy, A: Data) -> Data
TC.Service.origin(service: TC.Service) -> Maybe<&2, TC.Origin>
TC.Service.outgoing(service: TC.Service) -> Maybe<&2, TC.OutgoingContext>
TC.Service.error(service: TC.Service) -> Maybe<&2, TC.GenerationError>
TC.Service.set(service: TC.Service, key: TC.StateKey, value: TC.StateValue) -> TC.Service
TC.Service.remove(service: TC.Service, key: TC.StateKey) -> TC.Service
TC.Service.show(service: TC.Service) -> String
TC.Origin.show(origin: TC.Origin) -> String
TC.Sent.carrier(sent: TC.Sent) -> List<&2, TC.Header>
TC.Sent.operation(sent: TC.Sent) -> Maybe<&2, TC.LocalContext>
TC.Sent.error(sent: TC.Sent) -> Maybe<&2, TC.GenerationError>
TC.Sent.dropped(sent: TC.Sent) -> List<&2, TC.StateKey>
TC.Sent.show(sent: TC.Sent) -> String
TC.Unforwarded.show(reason: TC.Unforwarded) -> String
```

The common path extracts each received request, calls `continue_or_start`
with `TC.Continue{}`, `TC.InheritSampled{}` and `TC.Lenient{}`, and calls
`send` once for every request the service makes, with that request's fields.

`continue_or_start` takes the context that extraction keeps, the message's
accepted traceparent or, when the message has none, the base, as
`reception` says:

- `Continue{}` continues it. The operation is a generated child of it, as
  `Generate.Context.child` creates one, with that context's state: the
  received tracestate or the base's. Its origin is `Continued{}`.
- `Restart{}` is for a trust boundary, where the context is not continued.
  A generated restart, as `Generate.Context.restart` creates one, replaces
  it: its trace ID is never the replaced one, the state is discarded, no
  received pair is kept and the root defaults apply. Its origin is
  `Restarted{}`. An outgoing base, an operation of this service, is replaced
  as another participant would receive it, so its trace ID is not reused
  either.

When extraction keeps no context, a generated root starts the trace with no
state, whatever `reception` says, and its origin is `Started{}`.

`sampling` gives the operation's sampled indication. With
`InheritSampled{}`, a child inherits its parent's, and a root or restart,
which has nothing to inherit, takes the root default, not sampled, so it is
emitted with flags `02`. `SetSampled{value}` sets `value` in every case.
This default is the ready path's own: `continue_or_start` resolves it and
passes the resulting `Bool` to root and restart generation, which take the
indication as they are given it.

| `Service` | Meaning |
| --- | --- |
| `Operating{origin, outgoing, received}` | The service's operation with the state it sends. `received` is the message's incoming context when the service continued it, kept so that a message it sends can forward it if generating fails; it is `None{}` for a root, a restart or a continued base |
| `Untraced{error, received}` | No identifier could be generated, for `error`; `received` is as above |

`Service.set` adds or updates an entry of the state that the service's
operation sends, as `OutgoingContext.set` does: a participant puts its own
entry first, and a restarted operation takes a new state this way.
`Service.remove` deletes an entry. A service without an operation sends no
state of its own, so both leave it unchanged.

`send` gives one message an operation of its own: a child of the service's
operation, generated anew for every call, so that each request of a fan-out
is a separate operation. Its span ID is never the service's; siblings get
different span IDs as long as the source's words differ, since only the
parent's span ID is excluded. `send` injects the child, with the service's
state, into `carrier`, the message's fields, as
[`Context.inject`](#injecting-and-forwarding-context) does: the old context
fields go and the new ones come last. When the child cannot be generated,
or the service has no operation, in which case `send` reads no word, no new
operation is reported. The message then forwards the received pair
unchanged if it can be sent whole, and otherwise carries no context fields.
`Sent.carrier` gives the fields to send in every case.

| `Sent` | Meaning |
| --- | --- |
| `Fresh{operation, injection}` | A new operation, injected with the service's state; `Sent.dropped` gives the keys that truncation to the output budget removed |
| `Forwarded{carrier, error}` | No operation could be generated, for `error`; the carrier forwards the received pair unchanged, as `Context.forward` writes it |
| `NoContext{carrier, error, reason}` | No operation could be generated, and no pair was forwarded, for `reason`. The carrier's context fields are removed, as `Context.clear` removes them |

| `Unforwarded` | Meaning |
| --- | --- |
| `NothingKept{}` | The service keeps no received context: its operation is, or was to be, a root, a restart or a child of a base |
| `ForwardFailed{error}` | `Context.forward` refused the received context under the limits of `send`, with its `ForwardError`: `NothingToForward{}` when its tracestate was discarded at extraction, `ForwardTooLarge{}` over the output budget, or `InvalidForwardParent{TraceParentTooLarge{}}` under a traceparent input budget smaller than that of extraction |

### Failure policies

`policy` decides what a failed generation returns:

- `Lenient{}` returns the `Service` or the `Sent` itself, so the business
  operation proceeds without a new operation, as spec #1 asks of the
  convenience path. `Service.show` and `Sent.show` name what happened, such
  as `Untraced SourceFailure 5 entropy unavailable`, `Fresh, truncated` or
  `NoContext after ExhaustedSpanId, NothingKept`, without any received value,
  so that a service may log them. The package logs nothing itself.
- `Strict{}` returns `Result<&2, &2, TC.GenerationError, TC.Service>`, or the
  same for `TC.Sent`: `Done{}` with a new operation, and `Fail{error}`
  whenever no new operation was generated, so that the caller can refuse the
  operation. `FailurePolicy.result` names the type for either policy.

The same operations take a caller's source in trace_context.bend, as the
other generating operations do:

```bend
TC.Context.continue_or_start_with(~S, ~read, source: S, extraction: TC.Extraction, reception: TC.Reception,
  sampling: TC.Sampling, policy: TC.FailurePolicy) -> IO(S & TC.FailurePolicy.result(policy, TC.Service))
TC.Context.send_with(~S, ~read, source: S, limits: TC.Limits, service: TC.Service, sampling: TC.Sampling,
  policy: TC.FailurePolicy, carrier: List<&2, TC.Header>) -> IO(S & TC.FailurePolicy.result(policy, TC.Sent))
```

Each call reads what its generation reads: at most 48 words for a root or a
restart, 16 for a child, and none for a service without an operation.

The [continue example](examples/continue.bend) continues a traced request and
sends two requests on, starts a trace for a request without context, restarts
a partner's request at a trust boundary and, with a source that fails, lets
the request proceed or refuses it. From the repository root:

```sh
./bend packages/trace-context/examples/continue.bend
```

Each run prints new IDs. Below, `T1` and `T2` stand for generated trace IDs
and `S1` to `S7` for generated span IDs, each different from the others, as
[validate.sh](../../scripts/validate.sh) checks the output:

```text
traced request: Continued 00-0af7651916cd43dd8448eb211c80319c-S1-01
sent: Fresh | Host: inventory.internal | traceparent: 00-0af7651916cd43dd8448eb211c80319c-S2-01 | tracestate: congo=t61rcWkgMzE
sent: Fresh | Host: billing.internal | traceparent: 00-0af7651916cd43dd8448eb211c80319c-S3-01 | tracestate: congo=t61rcWkgMzE
request without context: Started 00-T1-S4-02
sent: Fresh | Host: inventory.internal | traceparent: 00-T1-S5-02
partner request: Restarted 00-T2-S6-02
sent: Fresh | Host: inventory.internal | traceparent: 00-T2-S7-02
without entropy: Untraced SourceFailure 5 entropy unavailable
sent: Forwarded after SourceFailure 5 entropy unavailable | Host: inventory.internal | traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01 | tracestate: congo=t61rcWkgMzE
strict, without entropy: refused after SourceFailure 5 entropy unavailable
```

## Host-driven generation

The operations above read their words from a source that they drive
themselves: the host's, or one that a caller passes as a template. A host
that cannot pass a source as a template feeds the words itself, as
JavaScript code calling the package's compiled ES module does: the module
runs no IO operation and exports no definition that takes a template. The
[JavaScript facade](JAVASCRIPT.md) is such a host. The package gives
such a host a pure form of each generating operation. Names below are
qualified by the alias `TC` for trace_context.bend:

```bend
TC.Generation.root(sampled: Bool) -> TC.Generation
TC.Generation.child(parent: TC.Parent, sampling: TC.Sampling) -> TC.Generation
TC.Generation.restart(previous: TC.RemoteContext, sampled: Bool) -> TC.Generation
TC.Generation.needs(generation: TC.Generation) -> Bool
TC.Generation.feed(generation: TC.Generation, word: Result<&1, &1, U32 & String, U32>) -> TC.Generation
TC.Generation.result(generation: TC.Generation) -> Result<&2, &2, TC.GenerationError, TC.LocalContext>
TC.ServicePlan.new(extraction: TC.Extraction, reception: TC.Reception, sampling: TC.Sampling) -> TC.ServicePlan
TC.ServicePlan.generation(plan: TC.ServicePlan) -> TC.Generation
TC.ServicePlan.service(plan: TC.ServicePlan, result: Result<&2, &2, TC.GenerationError, TC.LocalContext>) ->
  TC.Service
TC.SendPlan.new(limits: TC.Limits, service: TC.Service, sampling: TC.Sampling, carrier: List<&2, TC.Header>) ->
  TC.SendPlan
TC.SendPlan.generation(plan: TC.SendPlan) -> TC.Generation
TC.SendPlan.sent(plan: TC.SendPlan, result: Result<&2, &2, TC.GenerationError, TC.LocalContext>) -> TC.Sent
```

- A `Generation` holds the machine's step with the words it may still read:
  48 for a root or a restart and 16 for a child. Its fields are internal,
  like the machine's, so a host builds one only with `Generation.root`,
  `Generation.child` or `Generation.restart`; a root and a restart take the
  sampled indication of the context they create, as `Context.root_with`
  does. While `Generation.needs` says
  it needs a word, the host reads one word result from its source and
  passes it to `Generation.feed`; `Generation.result` then gives the
  context or the `GenerationError`. A generation that has ended ignores
  further words, and one whose budget is spent needs none.
- `ServicePlan.new` decides what `Context.continue_or_start_with` does for a
  message before it reads any word: which generation to drive, whose root
  or restart has the sampled indication that `sampling` resolves from the
  root default, and what its result makes of the service.
  `ServicePlan.service` gives that service, before the policy applies.
- `SendPlan.new` decides the same for a message to send. A service without an
  operation has nothing to generate: its plan's generation has already
  failed with the service's error, so the host reads no word, and
  `SendPlan.sent` gives the fallback.
- Under `Strict{}`, a host applies the policy as the operations do: a
  service without an operation, or a message without a new one, becomes the
  `GenerationError` that caused it.

`Context.continue_or_start_with` and `Context.send_with` run on these plans
themselves. `Context.root_with` and its siblings compose the
[separate generation](#a-trace-id-or-a-span-id-alone) instead, and laws
`root_tape`, `child_tape` and `restart_tape` show that they give what the
machine of `Generation.root` and its siblings gives. Law `generation_drive`
shows that a host's loop reads the same words, in order, and gets the same
result as the pure driver that the other generation laws describe. Laws `hosted_service` and `hosted_send`
show that a host that drives the plans gets what the IO operations give, for
every sequence of words.

## Native HTTP integration

[native_http.bend](native_http.bend) connects the package to the HTTP
package of [bend-kit](https://github.com/paymog/bend-kit/tree/main/http),
`bend-kit-http` on BendHub, the native HTTP transport that this repository
[qualifies](NATIVE-HTTP.md) at version 0.23.0.1. bend-kit keeps the header
fields of a request or response in a Base `Map` from each field name to its
values in arrival order; its parser lowercases the names and trims the
values. The
adapter turns such a map into the package's carrier and back, and gives a
service two shortcuts on a caller's source; generation.bend gives the same
shortcuts on the host's source. The adapter decides no Trace Context rule
itself, and it imports only `Base` and trace_context.bend, so it builds
wherever the package builds and has no host effect; the service imports
bend-kit for the transport. Names below are qualified by the aliases
`NativeHttp` for native_http.bend, `Generate` for generation.bend, `TC` for
trace_context.bend and `Http` for bend-kit's `http.bend`:

```bend
NativeHttp.HeaderMap() -> Data   # Map<&2, List<&2, String>>, as bend-kit's Req and Res hold
NativeHttp.carrier(headers: NativeHttp.HeaderMap()) -> List<&2, TC.Header>
NativeHttp.headers(carrier: List<&2, TC.Header>) -> NativeHttp.HeaderMap()
Generate.NativeHttp.continue_or_start(limits: TC.Limits, headers: NativeHttp.HeaderMap(),
  base: Maybe<&2, TC.BaseContext>, reception: TC.Reception, sampling: TC.Sampling, policy: TC.FailurePolicy) ->
  IO(TC.FailurePolicy.result(policy, TC.Service))
Generate.NativeHttp.send(limits: TC.Limits, service: TC.Service, sampling: TC.Sampling, policy: TC.FailurePolicy,
  headers: NativeHttp.HeaderMap()) -> IO(TC.FailurePolicy.result(policy, NativeHttp.Outbound))
NativeHttp.Outbound{sent: TC.Sent, headers: NativeHttp.HeaderMap()}
NativeHttp.Outbound.sent(outbound: NativeHttp.Outbound) -> TC.Sent
NativeHttp.Outbound.headers(outbound: NativeHttp.Outbound) -> NativeHttp.HeaderMap()
NativeHttp.continue_or_start_with(~S, ~read, source: S, limits: TC.Limits, headers: NativeHttp.HeaderMap(),
  base: Maybe<&2, TC.BaseContext>, reception: TC.Reception, sampling: TC.Sampling, policy: TC.FailurePolicy) ->
  IO(S & TC.FailurePolicy.result(policy, TC.Service))
NativeHttp.send_with(~S, ~read, source: S, limits: TC.Limits, service: TC.Service, sampling: TC.Sampling,
  policy: TC.FailurePolicy, headers: NativeHttp.HeaderMap()) ->
  IO(S & TC.FailurePolicy.result(policy, NativeHttp.Outbound))
```

- `carrier` gives every value of every name, in arrival order within each
  name, so that extraction refuses a repeated traceparent and combines
  repeated tracestate fields in order. The order between different names is
  the map's own, and no Trace Context rule depends on it.
- `headers` builds a map from a carrier that holds, under each name, the
  carrier's values of that name in order, as bend-kit's `Http.add` would add
  them one by one, with the names as the carrier spells them. bend-kit writes
  one header line per value.
- Both are loops, so the thousands of values that a head of 64 KiB can hold
  need no deep stack.
- `continue_or_start_with` gives the service's operation for a received
  request from the request's header map: `TC.Context.extract` of the map's
  carrier, followed by
  [`Context.continue_or_start_with`](#continuing-or-starting-a-trace) on a
  caller's source.
- `send_with` gives one request to send a new child of the service's
  operation: `Context.send_with` on the carrier of the request's own header
  map, followed by the map of the carrier the package gives back. The
  request's old context fields go, whatever the case of their names. The
  `Outbound` holds the `TC.Sent` diagnostics and the header map to send the
  request with.
- `Generate.NativeHttp.continue_or_start` and `Generate.NativeHttp.send`
  are the same on the host's cryptographic source, which is what a service
  normally uses.

A service handles each request in three steps: its operation from the
request's header map with `Generate.NativeHttp.continue_or_start`, a child
of it for each request that it sends with `Generate.NativeHttp.send`, and
the call with bend-kit's `Http.fetch.how` and
`NativeHttp.Outbound.headers(outbound)`. The guide's
[native HTTP service](GUIDE.md#a-native-http-service) is a complete program.

`Generate.NativeHttp.continue_or_start` returns only the service. A service
that also logs why it continued or started a trace, which spec #1's
diagnostics distinguish (an absent or a rejected traceparent, a discarded
state), extracts first with `TC.Context.extract` on
`NativeHttp.carrier(headers)`, passes the extraction to
`Generate.Context.continue_or_start`, and logs `TC.Extraction.show`, as that
program and the [gateway example](examples/gateway.bend) do.

Errors are handled at three levels:

- Tracing never fails a request under `TC.Lenient{}`. Without entropy, the
  request sent on forwards the received pair unchanged or carries no context
  fields, and `TC.Sent.show` says which. Under `TC.Strict{}` both shortcuts
  return `Fail{GenerationError}`, so that the service can refuse the request,
  for example with a 503.
- The transport reports its own failures: `Http.fetch.how` returns an
  `Http.Err`, which the adapter plays no part in.
- A service logs `TC.Service.show` and `TC.Sent.show`, which hold no received
  value. Neither the package nor the adapter logs anything.

Support boundaries:

- The supported path is native Bend 2.0.34 on macOS ARM64 and Linux x86_64,
  with `bend-kit-http` 0.23.0.1. bend-kit's own JavaScript transport, which
  runs on Bun, is not qualified. JavaScript applications on Node use
  the [facade's `node:http` integration](JAVASCRIPT.md#node-http-integration)
  instead, and browser pages its
  [Fetch integration](JAVASCRIPT.md#browser-integration).
- An application that uses the adapter imports bend-kit itself, by content
  hash as the [gateway example](examples/gateway.bend) does,
  `import 0x1cef8a5fb1d9142ca5c6b2cb43629b21/http.bend as Http`, or by name,
  `import bend-kit-http@0.23.0.1/http.bend as Http`. Bend fetches it from
  BendHub on the first build and checks its files against the hash; its own
  dependencies come by name and version, which BendHub resolves, as the
  [native HTTP guide](NATIVE-HTTP.md) describes. A check of such a program
  answers `SOME PROOFS FAIL`, since bend-kit relies on foreign code and
  `@unsafe` definitions of its own.
- bend-kit's server lowercases names and trims values before the package
  sees them; extraction reads the rest. It refuses a request head over
  64 KiB with 431 before any Trace Context code runs, whatever the package's
  input budgets allow.
- bend-kit's client lowercases the names of the map it sends, so of two keys
  that differ only in case it sends one, and it drops `host`, `connection`,
  `content-length` and `transfer-encoding`, which it writes itself. The
  context fields that the package writes have lowercase names already.
- bend-kit follows redirects by default. `Http.ModeManual{}` keeps each call a
  single operation, so that a redirect is not sent with the same child.

The gateway listens on port 18777 of every interface, as bend-kit's
`Http.serve` does, and calls `http://127.0.0.1:18776/downstream`. From the
repository root, build it and start an observer that prints what reaches
downstream:

```sh
./bend packages/trace-context/examples/gateway.bend -o build/gateway
OBSERVER_PORT=18776 node tests/native/fixtures/observer.mjs
```

Then, in two more terminals, start `build/gateway` and send it a traced
request and an untraced one:

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

`./scripts/qualify-propagation.sh` builds a service on the adapter from a
pinned checkout and runs the
[W3C Trace Context harness](https://github.com/w3c/trace-context/tree/acab820be9db7b3433668baa5cdd43f57f4c4be0/test)
against it, together with the repository's own checks; the
[native HTTP guide](NATIVE-HTTP.md) describes both.

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
`TrailingInput{}`. IDs read from [bytes](#identifiers-as-bytes) follow them
cell by cell, with `InvalidByte{offset}` for a cell above 255.

Errors are constructors of `Error`, such as `InvalidHex{offset}` or
`ZeroId{TraceIdField{}}`; callers may match on them rather than read the
name that `Error.show` gives, `InvalidHex at 3` or `ZeroTraceId`.
[Errors and diagnostics](ERRORS.md#traceparent-and-identifiers) lists them
all.

Creating a context from valid IDs can only fail with a `ContextError`:
`ReusedSpanId{}` when a child uses its parent's span ID, and `ReusedTraceId{}`
when a restart uses the received trace ID.

These are the strict codec's errors. [Extraction](#extracting-context)
applies a participant's policy on top of them: `TraceParent.read` reads
versions `01` to `fe` by their known prefix where the strict codec reports
`UnsupportedVersion`, and refuses a control character in the fields after that
prefix with `ControlCharacter{offset}`, which the strict codec never reports.

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
every value of their types, not over examples. From the repository root,

```sh
./bend packages/trace-context/PROOF.bend
```

prints `ALL PROOFS CHECK`: Bend's checker accepts a proof of every law, and
no definition PROOF.bend imports relies on `@unsafe` or foreign code. The
host operations of generation.bend rely on the foreign effect of
entropy.bend, so no law imports them: the laws state the same operations on
a caller's source, and a check of a file that imports generation.bend
answers `SOME PROOFS FAIL`, naming those operations, which the validation
pins.

Bend offers a second check, `--verdict`, which rechecks the proofs with
BendTT, a small kernel that has a proof in Lean. That recheck has not run on
this package: its translation has no model for the template assumptions
about Base's `Map` that law `http_headers` takes, which the end of this
section describes, and the kernel needs Lean 4.34.

- **Codec:** `String.length(format(context)) == 55n`;
  `parse(format(context)) == Done{context}`, including the IDs, their evidence
  and all flag bits; and the inverse: for every `String` the parser accepts,
  formatting the result reproduces exactly that text.
- **Supplied IDs:** an accepted trace or span ID is exactly the text that was
  accepted, and a parsed trace ID makes no randomness assertion. Conversely,
  every trace ID's text is accepted and every span ID's text parses back to
  that span ID. `assert_random` changes only the assertion.
- **Construction:** `from_ids` keeps its IDs and sampled indication, and a root
  is `from_ids` with the sampled indication that it is given: sampled `0` for
  `False{}`. `RemoteContext.from_ids` keeps its IDs and sampled indication
  too, so its randomness assertion is its trace ID's.
- **Children:** a successful child keeps the parent's trace ID and randomness
  assertion, uses the supplied span ID, whose text differs from the parent's,
  and takes sampled from `Sampling.resolve`: the parent's indication for
  `InheritSampled{}`, or the value of `SetSampled{value}`. A span ID with the
  parent's text fails with `ReusedSpanId{}`, and every other span ID creates
  the child.
- **Restarts:** a successful restart is the root of its supplied IDs with the
  sampled indication that it is given, and its trace ID text differs from the
  received one. The received trace ID fails with `ReusedTraceId{}`, and every
  other trace ID creates the restart, whatever the indication.
- **Flags:** every local context is emitted as version `00` with its IDs and
  one of `00`, `01`, `02`, `03`; receiving that value recovers its trace ID,
  randomness assertion, span ID and sampled indication; and a received context
  keeps the bits that `TraceParentV00.is_sampled` and `is_random` read. The
  corpus checks those two readers on all 256 flag bytes; no law restates them
  for the reserved bit patterns. A context's trace flags are the number of
  its sampled indication and randomness assertion, from 0 to 3: a local
  context's are those of the traceparent that it emits, and a remote
  context's the known flags that it was received or built with, those of the
  value received for a received one.
- **Conversion:** a candidate trace ID's text is `U32.to_hex` of its four words
  in reading order and a span ID's of its two. Read as a base-16 numeral,
  `U32.to_hex(word)` is the number Base's `U32.to_nat` assigns to the word, so
  digits are big-endian within each word too. `U32.to_hex` is injective, so no
  source information is lost, and converting words makes no randomness
  assertion.
- **Bytes:** the bytes of a trace or span ID are, in order, the numbers that
  the pairs of digits of its text denote in hexadecimal, so they are most
  significant first and each from 0 to 255. Reading back the bytes of a span
  ID gives that span ID, and those of a trace ID its digits without the
  randomness assertion, which no trace ID read from bytes makes. Every list
  that `from_bytes` accepts is the bytes of the ID it gives, and two IDs with
  the same bytes have the same digits. Each refusal that
  [Identifiers as bytes](#identifiers-as-bytes) lists is a law, and so is the
  acceptance of every other list of 16 or 8 bytes.
- **Generation:** a source error ends generation at once. Reading a tape, the
  IO operations compute exactly the pure tape driver, word for word. For every
  tape, a root or restart ends within 48 words and a child within 16. Eight
  zero candidates exhaust a root's trace ID or a child's span ID without
  reading a ninth; the other exhaustion paths are tested. A generated root
  asserts randomness and has the sampled indication that it was given, so,
  with the **Flags** laws above, it is emitted with flags `02` or `03`; a
  generated child keeps the parent's trace ID and randomness assertion,
  resolves sampled and never reuses the parent's span ID; a generated
  restart's trace ID differs from the received one, asserts randomness and
  has the sampled indication that it was given. These laws hold for every
  indication; with `False{}`, a root or a restart is unsampled, as
  `continue_or_start` starts one by default.
- **Separate generation:** a source error ends a trace ID or span ID draw at
  once, and over a tape the IO operations compute the pure drivers word for
  word. When the first four words, or two, make an identifier, generation
  without one to exclude reads exactly those words and gives it, a trace ID
  with its randomness asserted. For every tape a trace ID ends within 32
  words and a span ID within 16, eight zero candidates exhaust either without
  a ninth read, a generated trace ID asserts randomness, and neither is ever
  the identifier that it excludes. For every tape, root, child and restart
  generation are the compositions of the two operations.
- **Limits:** a validated configuration has a traceparent input budget of at
  least 55, an output budget of at least 512 and an input budget no smaller
  than its output budget; `Limits.new` accepts exactly those configurations,
  keeps their budgets, and the defaults are 32768, 32768 and 512.
- **Keys and values:** an accepted key or value is exactly the text accepted,
  every key's and value's text is accepted back, and neither contains `,` or
  `=`.
- **States:** every state, parsed or not, has distinct keys and at most 32
  entries. Distinct keys are stated independently of the package: no entry's
  key appears in a later entry.
- **Queries:** every entry of a state is found by its key, and a key that no
  entry has is absent.
- **Parsing:** parsing a state's normalized value gives back that state
  whenever the value fits the budget, and optional whitespace before and after
  it changes nothing. Two states' values joined by a comma give the first
  state's entries followed, in order, by the second's entries whose keys the
  first lacks, whenever the value fits and they have at most 32 entries
  together. In particular, an entry repeating a key of the state before it is
  dropped and an entry with a new key follows the others. After 32 entries any
  further entry is refused, even a repeated one, because members are counted
  before duplicates are dropped. A value over the budget fails with
  `StateTooLarge{}` whatever it holds, and within the budget its size changes
  nothing. Repeated fields parse exactly as their comma-joined combination.
- **Updates:** setting a key puts its new entry first, followed by at most 31
  of the other entries in their order; updating a present key keeps all the
  others, and adding a new key keeps the state's first 31 entries. A lookup
  finds the value just set, and removing a key leaves the other entries in
  order and the key absent.
- **Emission:** a state's size is exactly the UTF-8 octets of its normalized
  value, commas included. Truncation keeps exactly what spec #1's procedure
  keeps, restated independently in LAWS.bend; in particular it keeps a state
  that fits whole, keeps entries in their order otherwise, fits the output
  budget and reports exactly the keys it dropped. An outgoing context emits the traceparent of
  its local context and its truncated state, which fits the output budget and
  which the same limits parse back into that state.
- **Extraction:** a message without a traceparent field keeps the base, more
  than one is refused as repeated, and a single value that `TraceParent.read`
  refuses keeps the base with the reason; in all three cases the tracestate is
  not read, only whether there is any. A single accepted value gives the
  incoming context: the sender's operation from the value's known fields, the
  state its tracestate fields parse to together in arrival order, or none when
  there are none or they are refused, and the received pair unless the state
  was refused. Two messages with the same traceparent fields give the same
  outcome and the same sender's operation whatever their tracestate, and a
  kept pair fits the input budgets. An incoming context built with
  `IncomingContext.from_remote` keeps its remote context and tracestate, and
  no received pair. `TraceParent.read` reads every strict v00
  text, with any optional whitespace around it, as its value, refuses a
  strict v00 text followed by more characters, reads versions `01` to `fe` by
  their known prefix, refuses `ff` and any value with a comma, and refuses a
  value over the traceparent budget, which otherwise changes nothing. Field
  names are selected by a statement written with Base's ASCII lowercase,
  independently of the package's comparison.
- **Injection:** cleanup keeps exactly the fields that are not context fields,
  in their order. Injection writes those fields followed by the emitted
  traceparent and, unless it is empty, the emitted tracestate, named by
  `Context.field_names` in its order; it reports the emission's dropped keys
  apart and gives the same carrier when repeated. A receiver that extracts
  an injected carrier with the same limits accepts its traceparent, finds the
  injected local context's trace ID with its randomness assertion, span ID
  and sampled indication as the sender's operation, and receives the entries
  of the truncated state.
- **Forwarding:** a successful forwarding writes the other fields followed by
  the received traceparent value and the received tracestate fields joined by
  commas, left out when empty. A context without a received pair, every
  context built from parts among them, is refused with `NothingToForward{}`,
  and a pair whose joined tracestate exceeds the output budget with
  `ForwardTooLarge{}`. The pair of a context that extraction accepted is
  forwarded whenever it fits, and forwarding into the carrier written gives
  that carrier again.
- **Continuing or starting:** for every tape of words, extraction and
  sampling, and under both policies, `continue_or_start_with` generates one
  context and returns what that generation's outcome gives. With
  `Continue{}`, it is a child of the context that extraction keeps, with that
  context's state and the message's incoming context; with `Restart{}`, it is
  a restart of that context, generated with the sampled indication resolved
  from the root default, no state and no received pair; and without a kept
  context it is a root generated with that indication. A failed generation
  gives a service without an operation under
  `Lenient{}` and `Fail{error}` under `Strict{}`. With the generation laws, a
  child keeps its parent's trace and never reuses its span ID, and a
  restart's trace ID differs from the replaced one. Stated on its own, a
  restart keeps nothing of a received context, whatever the words: no
  received pair and no state.
- **Sending:** for every tape, service, limits and carrier, `send_with`
  generates a child of the service's operation and injects it with the
  service's state; when that fails, it forwards the received pair or clears
  the carrier, and fails under `Strict{}`. A service without an operation
  reads no word. Stated on its own, a message reports a new operation
  exactly when one was generated for it, and that is the operation it
  reports, whatever the policy.
- **Native HTTP headers:** the carrier that `NativeHttp.carrier` reads from a
  header map holds, under every name, exactly the values that the map's
  entries hold under it, in the same order, and the map that
  `NativeHttp.headers` writes for a carrier holds, under every name, the
  carrier's values of that name, given the contract of Base's `Map` as
  hypotheses. For every tape,
  `NativeHttp.continue_or_start_with` is the package's continue-or-start on
  the extraction of that carrier, and `NativeHttp.send_with` is the package's
  send on it followed by `NativeHttp.headers` of the carrier that the package
  gives back, so the adapter adds no Trace Context behavior of its own.
- **Host-driven generation:** for every generation and tape, a host that feeds
  the next word while `Generation.needs` says so reads the same words and
  gets the same result as the pure driver with the generation's budget,
  whatever bound its loop has beyond that budget. For every tape, a host that
  drives the plans of `ServicePlan.new` and `SendPlan.new` and applies the
  policy gets the service and the message that `continue_or_start_with` and
  `send_with` give, under both policies, so the laws of both operations hold
  of that host path. The JavaScript facade follows it; its own code is
  tested, not proved.

The generation laws quantify over tapes, that is, over every sequence of word
results. The host source runs through the same driver with its effect in
`read`, and the JavaScript facade feeds WebCrypto words to the host-driven
form, whose loop and plans the laws cover; what a host source gives is
tested, not proved. The tracestate laws quantify over
every state, entry and limits, and over any optional whitespace around a
normalized value. Whitespace and empty members between members, other inputs
that are not normalized values, the character classes, the octet width of each
character and the member numbers in diagnostics are covered by the corpus, not
by laws. Truncation is stated as spec #1's procedure itself: while over the
budget, the rightmost entry larger than 128 octets goes, or the rightmost
entry when none is, and removal stops as soon as the value fits. The
extraction laws quantify over every carrier, base, limits and value; the
offsets in diagnostics, whitespace, control characters and other characters
inside unknown fields, names with non-ASCII letters and exact budget
boundaries are covered by the corpus. The injection and forwarding laws quantify over every carrier,
outgoing and incoming context, base and limits; the texts written for
particular contexts, lookalike names, pairs built directly and exact budget
boundaries are covered by the corpus. The continue-or-start and sending laws
quantify over every tape, extraction, service, limits and carrier, and over
both policies; each states its result as the outcome of the generation it
performs. That sibling messages get different span IDs rests on the words
the source gives: the corpus shows it for replayed words and the example and
the consumer for the host's, but no law states it. The fields a message
sends follow from these laws with those of injection, forwarding and
cleanup. What Base's `Map` stores, lists and looks up is Base's behavior,
which Base proves nothing about: the native HTTP laws take the map's list of
entries as given, and assume that a list set under a key is found under it
and leaves the other keys as they were. The adapter's corpus and the HTTP
qualification exercise Base's side.

Auxiliary universal proofs cover hexadecimal and character decoding, encoded
lengths, reading an encoded sequence while preserving its suffix, recovery of a
nonzero ID, string comparison, the word-to-digit round trip and the bits of a
byte. Proofs use structural induction/composition, without local axioms or
`@unsafe` shortcuts. The laws do not cover the origin of supplied IDs, the truth of a
randomness assertion, the quality of a source or global uniqueness.

The sources are written to be read by developers new to Bend. Each law in
[LAWS.bend](LAWS.bend) is preceded by a comment that states its claim in
words, the requirement it verifies (a section of W3C Trace Context Level 2 or
of an approved specification, spec #1 or spec #41), why it matters and how to
read its statement.
[PROOF.bend](PROOF.bend) opens with a guide to reading Bend proofs and a map of
the modules under [proofs](proofs), each of which starts with a summary of what
it proves. [trace_context.bend](trace_context.bend) opens with notes on the
Bend features the implementation relies on, and documents every definition.

## Standards and scope

The strict v00 format follows
[W3C Trace Context Level 1](https://www.w3.org/TR/2021/REC-trace-context-1-20211123/#traceparent-header).
The propagator targets the pinned
[Level 2 Candidate Recommendation Draft](https://www.w3.org/TR/2024/CRD-trace-context-2-20240328/).
The random-trace-id flag `0x02` still uses wire version `00`.

The codec's faithful formatter does not mask reserved bits of a parsed
value; `LocalContext.to_traceparent` emits only known flags. There is no
claim of complete W3C propagator conformance or a full OpenTelemetry SDK.

[VALIDATION.md](VALIDATION.md) describes what each test corpus covers and
records the validation runs, and [CHANGELOG.md](../../CHANGELOG.md) covers
versioning and migration.
