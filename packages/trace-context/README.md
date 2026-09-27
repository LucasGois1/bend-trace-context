# Traceparent codec, contexts and tracestate

The currently implemented part of **bend-trace-context 0.1.0-dev** is a pure,
strict v00 codec for Bend 2.0.27, validated trace and span IDs, root, child
and restarted local contexts, either from IDs the caller supplies or from IDs
generated on a cryptographic source, a bounded Level 2 `tracestate` parser
with validated limits, the operations that update a local operation's
tracestate and emit it within the output budget, the extraction of a received
message's context from its fields, the injection and forwarding of a context
into the fields of a message to send, and the operations that continue or
start a service's own operation for each message it receives and give each
message it sends a child of that operation, with an adapter for the header
maps of the native HTTP transport bend-net. It has no external package
dependencies beyond the compiler's bundled `Base`. The public entries are
[trace_context.bend](trace_context.bend), which performs no host effect of its
own, [generation.bend](generation.bend), which adds the host's cryptographic
source, and [native_http.bend](native_http.bend), which adapts bend-net's
header maps.
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
  `ReusedTraceId{}`, even when only the randomness assertion differs.
  [`Context.continue_or_start`](#continuing-or-starting-a-trace) restarts at a
  trust boundary with a sampling policy of the caller's choice.

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
`BaseContext.parent` and `BaseContext.state` give the same for a base.
[`Context.continue_or_start`](#continuing-or-starting-a-trace) does this for
a message and its base in one step. The received pair is what
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
| `ForwardFailed{error}` | `Context.forward` refused the received context: `NothingToForward{}` when its tracestate was discarded at extraction, or `ForwardTooLarge{}` over the output budget |

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

## Native HTTP integration

[native_http.bend](native_http.bend) connects the package to bend-net, the
native HTTP transport that this repository pins as the `vendor/bend-net`
submodule and [qualifies](NATIVE-HTTP.md). bend-net keeps the header fields of
a request or response in a Base `Map` from each field name to its values in
arrival order; its parser lowercases the names and trims the values. The
adapter turns such a map into the package's carrier and back, and gives a
service two shortcuts. It decides no Trace Context rule itself, and it
imports only `Base` and the package, so it builds wherever the package
builds; the service imports bend-net for the transport. Names below are
qualified by the aliases `NativeHttp` for native_http.bend, `TC` for
trace_context.bend and `Http` for bend-net's `http.bend`:

```bend
NativeHttp.HeaderMap() -> Data   # Map<&2, List<&2, String>>, as bend-net's Req and Res hold
NativeHttp.carrier(headers: NativeHttp.HeaderMap()) -> List<&2, TC.Header>
NativeHttp.headers(carrier: List<&2, TC.Header>) -> NativeHttp.HeaderMap()
NativeHttp.continue_or_start(limits: TC.Limits, headers: NativeHttp.HeaderMap(), base: Maybe<&2, TC.BaseContext>,
  reception: TC.Reception, sampling: TC.Sampling, policy: TC.FailurePolicy) ->
  IO(TC.FailurePolicy.result(policy, TC.Service))
NativeHttp.send(limits: TC.Limits, service: TC.Service, sampling: TC.Sampling, policy: TC.FailurePolicy,
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
  carrier's values of that name in order, as bend-net's `Http.add` would add
  them one by one, with the names as the carrier spells them. bend-net writes
  one header line per value.
- Both are loops, so the thousands of values that a head of 64 KiB can hold
  need no deep stack.
- `continue_or_start` gives the service's operation for a received request
  from the request's header map: `TC.Context.extract` of the map's carrier,
  followed by [`Context.continue_or_start`](#continuing-or-starting-a-trace).
- `send` gives one request to send a new child of the service's operation:
  `Context.send` on the carrier of the request's own header map, followed by
  the map of the carrier the package gives back. The request's old context
  fields go, whatever the case of their names. The `Outbound` holds the
  `TC.Sent` diagnostics and the header map to send the request with.
- `continue_or_start_with` and `send_with` take a caller's source, as the
  package's own operations do.

A service handles each request in three steps:

```bend
+service : TC.Service <- NativeHttp.continue_or_start(TC.Limits.default(), headers, None{}, TC.Continue{},
  TC.InheritSampled{}, TC.Lenient{})
+outbound : NativeHttp.Outbound <- NativeHttp.send(TC.Limits.default(), service, TC.InheritSampled{},
  TC.Lenient{}, Http.set(Http.empty(), "content-type", "application/json"))
result : Result<&2, &2, Http.Err, Http.Res> <- Http.fetch.how("POST", url,
  NativeHttp.Outbound.headers(outbound), body, 3000, Http.ModeManual{})
```

`continue_or_start` returns only the service. A service that also logs why
it continued or started a trace, which spec #1's diagnostics distinguish
(an absent or a rejected traceparent, a discarded state), extracts first and
passes the extraction on, as the [gateway example](examples/gateway.bend)
does:

```bend
+extraction = TC.Context.extract(TC.Limits.default(), NativeHttp.carrier(headers), None{})
+service : TC.Service <- Generate.Context.continue_or_start(extraction, TC.Continue{}, TC.InheritSampled{},
  TC.Lenient{})
```

and logs `TC.Extraction.show(extraction)` with the other diagnostics.

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

- The supported path is native Bend 2.0.27 on macOS ARM64 and Linux x86_64,
  with bend-net at the pinned commit. bend-net's own JavaScript transport,
  which runs on Bun, is not qualified. JavaScript HTTP integration belongs to
  [#13](https://github.com/LucasGois1/bend-trace-context/issues/13) and the
  browser to [#14](https://github.com/LucasGois1/bend-trace-context/issues/14).
- An application that uses the adapter clones the repository with its
  submodules: `git clone --recurse-submodules`, or
  `git submodule update --init --recursive` in an existing checkout.
- bend-net's server lowercases names and trims values before the package
  sees them; extraction reads the rest. It refuses a request head over
  64 KiB with 431 before any Trace Context code runs, whatever the package's
  input budgets allow.
- bend-net's client lowercases the names of the map it sends, so of two keys
  that differ only in case it sends one, and it drops `host`, `connection`,
  `content-length` and `transfer-encoding`, which it writes itself. The
  context fields that the package writes have lowercase names already.
- bend-net follows redirects by default. `Http.ModeManual{}` keeps each call a
  single operation, so that a redirect is not sent with the same child.

The gateway listens on `127.0.0.1:18777` and calls
`http://127.0.0.1:18776/downstream`. From the repository root, build it and
start an observer that prints what reaches downstream:

```sh
git submodule update --init --recursive
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
- **Continuing or starting:** for every tape of words, extraction and
  sampling, and under both policies, `continue_or_start_with` generates one
  context and returns what that generation's outcome gives. With
  `Continue{}`, it is a child of the context that extraction keeps, with that
  context's state and the message's incoming context; with `Restart{}`, it is
  a restart of that context, with the sampled indication resolved from the
  root default, no state and no received pair; and without a kept context it
  is a root. A failed generation gives a service without an operation under
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

The [continue-or-start corpus](tests/CONTINUE.bend) replays tapes through
both operations. It continues a message's context and, without a usable
traceparent, a base of this service and a context received earlier; it
starts roots and restarts, with and without a sampling override, and at a
boundary replaces the message's context, a base of this service and a
context received earlier with trace IDs other than theirs; and it meets a
source failure and exhausted candidates under both policies. It sends a
fan-out of three requests with different span IDs into a reused container,
puts the service's own entry first, and checks what a message carries when
no operation can be generated: the received pair forwarded, and no context
at a boundary, for a root, for a base, after a discarded state and for
spec #1's 600-octet state. Each case checks how many words were left unread,
and the diagnostics, truncation included, contain no received value.

The [native HTTP header corpus](tests/NATIVE-HTTP.bend) reads received header
maps with repeated traceparent and tracestate values, writes carriers with
repeated and mixed-case names back into maps, and runs both shortcuts over
replayed tapes: a continued request, a child sent in place of a reused
container's old context fields, whatever the case of their names, the
forwarded pair, the cleared fields and a strict failure.

The [propagation qualification](../../scripts/qualify-propagation.sh) builds
a service on the adapter and the gateway example from a pinned checkout of
the repository, and runs them over the real bend-net transport. Its own
checks, against an independent Node observer, cover:

- sampled `0` and every combination of the sampled and random-trace-id flags;
- roots, restarts and fan-out;
- repeated injection into reused containers with stale context fields;
- a discarded state, with diagnostics that hold no received value;
- source failures for the service's operation and for each child, and
  exhausted candidates, which forward the received pair or clear the
  context;
- strict refusals;
- the gateway example.

It then runs the W3C harness at commit `acab820` with `SPEC_LEVEL=2` and
`STRICT_LEVEL=2`: `TraceContextTest`, `AdvancedTest` and `TraceContext2Test`,
41 tests, of which none may fail, error or be skipped. Passing this finite
harness shows interoperability in the scenarios it runs, not conformance to
the whole W3C publication.

The [generation corpus](tests/GENERATION.bend) replays tapes through the public
operations: conversion vectors in decimal for the W3C example words, the digit
order within a word, zero then valid candidates, eight zero candidates with no ninth read, a 48-word
worst case, a source error in the middle of a candidate, an empty tape, a
child that must not reuse the parent's span ID and a restart that must not
reuse the received trace ID, each checking how many words were left unread.
The [smoke check](tests/SMOKE.bend), the
[generation example](examples/generate.bend) and the
[continue example](examples/continue.bend) generate on the real host source;
they check only that the results are well formed and that generated IDs are
new where they must be. The JavaScript suite runs a compiled
root through WebCrypto with real host exceptions and counts the words read.
The [validation guide](../../README.md#validation) describes reproducible
commands and the separate clean consumer.

The strict v00 format follows
[W3C Trace Context Level 1](https://www.w3.org/TR/2021/REC-trace-context-1-20211123/#traceparent-header).
The planned propagator targets the pinned
[Level 2 Candidate Recommendation Draft](https://www.w3.org/TR/2024/CRD-trace-context-2-20240328/).
The random-trace-id flag `0x02` still uses wire version `00`.

This package does not yet implement browser generation, or HTTP
integration in JavaScript and in browsers. Its faithful formatter does not mask reserved bits of a parsed
value; `LocalContext.to_traceparent` emits only known flags. There is no claim of
complete W3C propagator conformance or a full OpenTelemetry SDK.

See the [initial codec validation record](VALIDATION.md) for the original
execution evidence and [CHANGELOG.md](../../CHANGELOG.md) for versioning
and migration.
