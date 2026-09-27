# Traceparent codec, contexts and tracestate

The currently implemented part of **bend-trace-context 0.1.0-dev** is a pure,
strict v00 codec for Bend 2.0.27, validated trace and span IDs, root, child
and restarted local contexts, either from IDs the caller supplies or from IDs
generated on a cryptographic source, a bounded Level 2 `tracestate` parser
with validated limits, the operations that update a local operation's
tracestate and emit it within the output budget, the extraction of a received
message's context from its fields, and the injection and forwarding of a
context into the fields of a message to send. It has no external package
dependencies beyond the compiler's bundled `Base`. The public entries are
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
to `fe`, which [extraction](#extracting-context) reads by their known prefix.
`LocalContext.to_traceparent` gives the participating
representation: version `00` and flags `00` to `03`, with every reserved bit
zero. [Injection](#injecting-and-forwarding-context) writes that
representation into a message, and forwarding sends a received value
unchanged.

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

| `StateError` | Meaning |
| --- | --- |
| `StateTooLarge{}` | The combined value exceeds the tracestate input budget |
| `TooManyMembers{}` | A 33rd nonempty member was reached |
| `InvalidEntry{member, error}` | The member numbered `member`, counting every comma-separated member from zero, is invalid |

| `EntryError` | Meaning |
| --- | --- |
| `MissingEquals{}` | A nonempty member has no `=` |
| `InvalidKey{}` | The text before the first `=` is not a key |
| `InvalidValue{}` | The text after it, without trailing optional whitespace, is not a value |

| `LimitsError` | Meaning |
| --- | --- |
| `TraceParentInputTooSmall{}` | The traceparent input budget is below 55 |
| `TraceStateOutputTooSmall{}` | The tracestate output budget is below 512 |
| `TraceStateInputTooSmall{}` | The tracestate input budget is below the output budget |

`StateKey.parse` and `StateValue.parse` fail with `InvalidKey{}` and
`InvalidValue{}`; they trim nothing, so a value with a trailing space is
refused there. Diagnostics carry positions and categories, never the received
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
| `IncomingContext` | A context extracted from a message: the sender's `RemoteContext`, the state received with it, and the received pair when the whole pair was accepted |
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

| `TraceParentOutcome` | Meaning |
| --- | --- |
| `TraceParentAccepted{}` | The message's traceparent was read; `Extraction.incoming` gives its context |
| `TraceParentAbsent{}` | The message has no traceparent field; the base is kept |
| `TraceParentRejected{error}` | The traceparent was refused; the base is kept |

| `TraceParentError` | Meaning |
| --- | --- |
| `RepeatedTraceParent{}` | More than one traceparent field, or a value joining several with a comma |
| `TraceParentTooLarge{}` | The value exceeds the traceparent input budget |
| `InvalidTraceParent{error}` | The value breaks the rules of its version; `error` is a codec `Error` |

| `StateOutcome` | Meaning |
| --- | --- |
| `StateAbsent{}` | The message has no tracestate field |
| `StateAccepted{}` | The fields were read into the incoming context's state, which may be empty |
| `StateDiscarded{error}` | The fields were refused as a whole; the traceparent stays accepted |
| `StateIgnored{}` | The fields were not read, because the message has no accepted traceparent |

`Extraction.show` joins both outcomes for a log line, such as
`TraceParentAccepted, StateDiscarded InvalidEntry 1 MissingEquals`.

An incoming context identifies the sender's operation, not one of this
participant's. A service continues it with a child operation,
`Context.child_from_id(IncomingContext.parent(incoming), span_id, sampling)`
with a supplied span ID or `Context.child` of generation.bend with a generated
one, and sends the received state with the child in an `OutgoingContext`.
`BaseContext.parent` and `BaseContext.state` give the same for a base. The
continue-or-start operation of
[#11](https://github.com/LucasGois1/bend-trace-context/issues/11) will do this
for a message and its base. The received pair is what
[forwarding](#injecting-and-forwarding-context) sends unchanged; it is
`None{}` when the tracestate was discarded. Only the pairs that
extraction keeps are known to be accepted and within the input budgets: as
with the contexts, Bend constructors are not private, and an
`IncomingContext` or `ReceivedPair` built directly carries no such
guarantee, so forwarding checks what it sends.

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
  traceparent value, whatever its version, reserved flag bits and unknown
  fields, and the tracestate fields joined into one field by commas, as W3C
  section 3.3.2 recommends, byte for byte; the tracestate field is left out
  when that joined value is empty, as injection leaves out an empty state.
  It never normalizes flags, downgrades a version or edits the tracestate
  (section 3.4). When the pair cannot be sent whole, it fails and writes
  nothing.

| `ForwardError` | Meaning |
| --- | --- |
| `NothingToForward{}` | The context keeps no received pair: its tracestate was discarded when it was extracted |
| `ForwardTooLarge{}` | The tracestate fields, joined by commas, exceed the tracestate output budget |
| `InvalidForwardParent{error}` | The traceparent value is not one that `TraceParent.read` accepts |
| `InvalidForwardState{error}` | The tracestate fields are not ones that `TraceState.parse_fields` accepts |

The last two refuse only a pair built directly: the pair of a context that
extraction accepted passes them under the same limits, so the output budget is
the only reason it is refused. A received tracestate within the 32 KiB input
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
| `ControlCharacter{offset}` | A control character other than a tab in the unknown fields of a later version, reported by `TraceParent.read` only |

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
  kept pair fits the input budgets. `TraceParent.read` reads every strict v00
  text, with any optional whitespace around it, as its value, refuses a
  strict v00 text followed by more characters, reads versions `01` to `fe` by
  their known prefix, refuses `ff` and any value with a comma, and refuses a
  value over the traceparent budget, which otherwise changes nothing. Field
  names are selected by a statement written with Base's ASCII lowercase,
  independently of the package's comparison.
- **Injection:** cleanup keeps exactly the fields that are not context fields,
  in their order. Injection writes those fields followed by the emitted
  traceparent and, unless it is empty, the emitted tracestate; it reports the
  emission's dropped keys apart and gives the same carrier when repeated. A
  receiver that extracts an injected carrier with the same limits accepts its
  traceparent, finds the injected local context's trace ID with its
  randomness assertion, span ID and sampled indication as the sender's
  operation, and receives the entries of the truncated state.
- **Forwarding:** a successful forwarding writes the other fields followed by
  the received traceparent value and the received tracestate fields joined by
  commas, left out when empty. A context without a received pair is refused
  with `NothingToForward{}`, and a pair whose joined tracestate exceeds the
  output budget with `ForwardTooLarge{}`. The pair of a context that
  extraction accepted is forwarded whenever it fits, and forwarding into the
  carrier written gives that carrier again.

The generation laws quantify over tapes, that is, over every sequence of word
results. The host source runs through the same driver with its effect in
`read`; that path is tested, not proved. The tracestate laws quantify over
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
boundaries are covered by the corpus.

Auxiliary universal proofs cover hexadecimal and character decoding, encoded
lengths, reading an encoded sequence while preserving its suffix, recovery of a
nonzero ID, string comparison and the word-to-digit round trip. Proofs use
structural induction/composition, without local axioms or `@unsafe`
shortcuts. The laws do not cover the origin of supplied IDs, the truth of a
randomness assertion, the quality of a source or global uniqueness.

The sources are written to be read by developers new to Bend. Each law in
[LAWS.bend](LAWS.bend) is preceded by a comment that states its claim in
words, the requirement it verifies (a section of W3C Trace Context Level 2 or
of the approved specification), why it matters and how to read its statement.
[PROOF.bend](PROOF.bend) opens with a guide to reading Bend proofs and a map of
the modules under [proofs](proofs), each of which starts with a summary of what
it proves. [trace_context.bend](trace_context.bend) opens with notes on the
Bend features the implementation relies on, and documents every definition.

## Validation and scope

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
513 octets; spec #1's 600-octet state under the default and a larger output
budget; and pairs built directly that forwarding must refuse, a line break
in a later version's unknown fields among them. It extracts again the
carriers of three injections and of a forwarding, and it handles carriers of
100000 fields and values of 32 KiB.

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

This package does not yet implement the continue-or-start operation, browser
generation or HTTP/browser integration. Its faithful formatter does not mask reserved bits of a parsed
value; `LocalContext.to_traceparent` emits only known flags. There is no claim of
complete W3C propagator conformance or a full OpenTelemetry SDK.

See the [initial codec validation record](VALIDATION.md) for the original
execution evidence and [CHANGELOG.md](../../CHANGELOG.md) for versioning
and migration.
