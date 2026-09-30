# Errors and diagnostics

Every error of the package is a constructor that Bend code can match on,
and every outcome and error has a `show` function that gives its log name.
The names never contain a received value, apart from the two hexadecimal
digits of an unsupported version, so they can be logged as they are. The
[JavaScript facade](JAVASCRIPT.md#failure-handling) reports the same names.
The operations that return each type are in the
[Bend API reference](README.md).

- [Log lines](#log-lines)
- [Traceparent and identifiers](#traceparent-and-identifiers)
- [Contexts from supplied identifiers](#contexts-from-supplied-identifiers)
- [Generation](#generation)
- [Limits](#limits)
- [Tracestate](#tracestate)
- [Extraction](#extraction)
- [Forwarding](#forwarding)
- [Continuing or starting, and sending](#continuing-or-starting-and-sending)
- [JavaScript](#javascript)

## Log lines

The three names that a service usually logs are composed of the ones below:

| Name | Form | Example |
| --- | --- | --- |
| `TC.Extraction.show` | traceparent outcome, `, `, tracestate outcome | `TraceParentAccepted, StateDiscarded InvalidEntry 1 MissingEquals` |
| `TC.Service.show` | the origin, or `Untraced` and the generation error | `Continued`, `Untraced SourceFailure 5 entropy unavailable` |
| `TC.Sent.show` | `Fresh`, or the fallback and why | `Fresh, truncated`, `Forwarded after ExhaustedSpanId`, `NoContext after SourceFailure 1 unavailable, NothingKept` |

## Traceparent and identifiers

`TC.Error`, from `TC.TraceParentV00.parse`, `TC.TraceId.parse`,
`TC.SpanId.parse`, `TC.TraceId.from_bytes`, `TC.SpanId.from_bytes` and,
inside `InvalidTraceParent`, extraction. The first error in reading order is
reported. An offset counts characters from the start of the value, after the
optional whitespace that extraction removes, or, for an ID read from bytes,
cells from the start of the list.

| Constructor | `show` | Meaning |
| --- | --- | --- |
| `UnexpectedEnd{offset}` | `UnexpectedEnd at 12` | A required character is missing, or a byte of an ID read from bytes: the list is too short |
| `InvalidHex{offset}` | `InvalidHex at 3` | A character is not lowercase ASCII hexadecimal |
| `InvalidByte{offset}` | `InvalidByte at 3` | A cell of the bytes of an ID is above 255, so it is not a byte |
| `ExpectedSeparator{offset}` | `ExpectedSeparator at 2` | A required `-` is absent |
| `TrailingInput{}` | `TrailingInput` | Characters follow the flags or a supplied ID, or cells follow the bytes of an ID: the list is too long |
| `ForbiddenVersion{}` | `ForbiddenVersion` | The version is `ff` |
| `UnsupportedVersion{version}` | `UnsupportedVersion 01` | The strict codec reads only version `00`; extraction reads later versions by their known prefix instead |
| `ZeroId{TraceIdField{}}` | `ZeroTraceId` | The trace ID is all zero, as text or as bytes |
| `ZeroId{ParentIdField{}}` | `ZeroParentId` | The parent ID is all zero |
| `ZeroId{SpanIdField{}}` | `ZeroSpanId` | A supplied span ID is all zero, as text or as bytes |
| `ControlCharacter{offset}` | `ControlCharacter at 60` | A control character other than a tab in the unknown fields of a later version; only extraction reads those |

## Contexts from supplied identifiers

`TC.ContextError`, from `TC.Context.child_from_id` and
`TC.Context.restart_from_ids`.

| Constructor | `show` | Meaning |
| --- | --- | --- |
| `ReusedSpanId{}` | `ReusedSpanId` | A child's span ID equals its parent's |
| `ReusedTraceId{}` | `ReusedTraceId` | A restart's trace ID equals the received one |

## Generation

`TC.GenerationError`, from every operation that generates an identifier.

| Constructor | `show` | Meaning |
| --- | --- | --- |
| `SourceFailure{code, message}` | `SourceFailure 1 unavailable` | The source failed with its own code and message; generation stopped at that word |
| `ExhaustedTraceId{}` | `ExhaustedTraceId` | Eight trace ID candidates were rejected: all zero, or the trace ID to exclude, such as the received one for a restart |
| `ExhaustedSpanId{}` | `ExhaustedSpanId` | Eight span ID candidates were rejected: all zero, or the span ID to exclude, such as the parent's for a child |

| Source | Failures |
| --- | --- |
| The host, natively on Linux | `getrandom`'s `errno` with its `strerror` text |
| The host, natively on macOS | None: `arc4random_buf` cannot fail |
| The host, in JavaScript (WebCrypto) | `1 unavailable` without `getRandomValues`; `2 source-failure` when it throws or answers anything but a 32-bit word |
| `TC.Source.tape` | `1 tape-exhausted` when its words run out, and each `Fail{(code, message)}` on the tape |
| A source that you supply | Its own codes |

Exhaustion needs eight rejected candidates in a row, which a working random
source practically never gives: in practice it points at a broken source.

## Limits

`TC.LimitsError`, from `TC.Limits.new`, which reports the first rule broken.

| Constructor | `show` | Meaning |
| --- | --- | --- |
| `TraceParentInputTooSmall{}` | `TraceParentInputTooSmall` | The traceparent input budget is below 55 |
| `TraceStateOutputTooSmall{}` | `TraceStateOutputTooSmall` | The tracestate output budget is below 512 |
| `TraceStateInputTooSmall{}` | `TraceStateInputTooSmall` | The tracestate input budget is below the output budget |

## Tracestate

`TC.StateError`, from `TC.TraceState.parse` and `parse_fields` and, inside
`StateDiscarded`, extraction; and `TC.EntryError`, from `TC.StateKey.parse`,
`TC.StateValue.parse` and inside `InvalidEntry`.

| `StateError` | `show` | Meaning |
| --- | --- | --- |
| `StateTooLarge{}` | `StateTooLarge` | The combined value exceeds the tracestate input budget; nothing was read |
| `TooManyMembers{}` | `TooManyMembers` | A 33rd nonempty member was reached |
| `InvalidEntry{member, error}` | `InvalidEntry 1 MissingEquals` | The member numbered `member`, counting every comma-separated member from zero, is invalid |

| `EntryError` | `show` | Meaning |
| --- | --- | --- |
| `MissingEquals{}` | `MissingEquals` | A nonempty member has no `=` |
| `InvalidKey{}` | `InvalidKey` | The text before the first `=` is not a key |
| `InvalidValue{}` | `InvalidValue` | The text after it, without trailing optional whitespace, is not a value |

## Extraction

`TC.Extraction.parent` gives a `TC.TraceParentOutcome`, which may hold a
`TC.TraceParentError`, and `TC.Extraction.state` a `TC.StateOutcome`.

| `TraceParentOutcome` | `show` | Meaning |
| --- | --- | --- |
| `TraceParentAccepted{}` | `TraceParentAccepted` | The traceparent was read; the message's context is kept |
| `TraceParentAbsent{}` | `TraceParentAbsent` | The message has no traceparent field; the base, if any, is kept |
| `TraceParentRejected{error}` | `TraceParentRejected RepeatedTraceParent` | The traceparent was refused; the base, if any, is kept |

| `TraceParentError` | `show` | Meaning |
| --- | --- | --- |
| `RepeatedTraceParent{}` | `RepeatedTraceParent` | More than one traceparent field, or one value that joins several with a comma |
| `TraceParentTooLarge{}` | `TraceParentTooLarge` | The value exceeds the traceparent input budget; nothing was read |
| `InvalidTraceParent{error}` | `InvalidTraceParent ZeroTraceId` | The value breaks the rules of its version; `error` is a [codec error](#traceparent-and-identifiers) |

| `StateOutcome` | `show` | Meaning |
| --- | --- | --- |
| `StateAbsent{}` | `StateAbsent` | The message has no tracestate field |
| `StateAccepted{}` | `StateAccepted` | The fields were read into the context's state, which may be empty |
| `StateDiscarded{error}` | `StateDiscarded TooManyMembers` | The fields were refused as a whole, with a [tracestate error](#tracestate); the traceparent stays accepted |
| `StateIgnored{}` | `StateIgnored` | The fields were not read, because the message has no accepted traceparent |

## Forwarding

`TC.ForwardError`, from `TC.Context.forward`, which then writes nothing.

| Constructor | `show` | Meaning |
| --- | --- | --- |
| `NothingToForward{}` | `NothingToForward` | The context keeps no received pair: its tracestate was discarded at extraction, or `TC.IncomingContext.from_remote` built it from parts |
| `ForwardTooLarge{}` | `ForwardTooLarge` | The tracestate fields, joined by commas, exceed the tracestate output budget |
| `InvalidForwardParent{error}` | `InvalidForwardParent TraceParentTooLarge` | The traceparent is not one that extraction accepts under these limits |
| `InvalidForwardState{error}` | `InvalidForwardState InvalidEntry 0 MissingEquals` | The tracestate is not one that extraction accepts under these limits |

The last two refuse a pair built directly, or one extracted under larger
input budgets: a pair that extraction accepted passes them under the same
limits.

## Continuing or starting, and sending

| `Service` | `show` | Meaning |
| --- | --- | --- |
| `Operating{origin, outgoing, received}` | `Continued`, `Started` or `Restarted` | The service's operation, and how it came about |
| `Untraced{error, received}` | `Untraced ExhaustedSpanId` | No identifier could be generated, for a [generation error](#generation) |

| `Origin` | `show` | Meaning |
| --- | --- | --- |
| `Continued{}` | `Continued` | A child of the context that extraction kept |
| `Started{}` | `Started` | A root: extraction kept no context |
| `Restarted{}` | `Restarted` | A new trace in place of the kept context, at a trust boundary |

| `Sent` | `show` | Meaning |
| --- | --- | --- |
| `Fresh{operation, injection}` | `Fresh`, or `Fresh, truncated` when entries were removed to fit the output budget | A new child, injected into the message's fields |
| `Forwarded{carrier, error}` | `Forwarded after ExhaustedSpanId` | No child could be generated; the message forwards the received pair unchanged |
| `NoContext{carrier, error, reason}` | `NoContext after SourceFailure 1 unavailable, NothingKept` | No child could be generated and no pair was forwarded; the message carries no context fields |

| `Unforwarded` | `show` | Meaning |
| --- | --- | --- |
| `NothingKept{}` | `NothingKept` | The service keeps no received context: its operation is, or was to be, a root, a restart or a child of a base |
| `ForwardFailed{error}` | Its [forwarding error](#forwarding): `NothingToForward`, `ForwardTooLarge`, or `InvalidForwardParent TraceParentTooLarge` | Forwarding refused the received context under the limits of `send`; the last when their traceparent input budget is smaller than that of extraction |

Under `TC.Strict{}`, `continue_or_start` and `send` return
`Fail{GenerationError}` in place of `Untraced`, `Forwarded` and `NoContext`.

## JavaScript

The facade checks its arguments before any package code runs:

| Exception | When | `message` or property |
| --- | --- | --- |
| `TypeError` | An argument of the wrong type: fields that are not `[name, value]` string pairs, an object that is not a handle of the expected kind (a copy of a handle included), options that are not an object, a `crypto` without `getRandomValues` | A description |
| `RangeError` | A value that the package refuses | The package's name: `InvalidKey`, `InvalidValue`, a `LimitsError`, a codec error such as `ZeroTraceId` or `InvalidHex at 1`, `ReusedSpanId` or `ReusedTraceId`; or a description of an unknown option value or a budget that is not a non-negative safe integer |
| `GenerationError` | No identifier could be generated: from `root`, `child` and `restart` always, and from `continueOrStart`, `send` and `tracedFetch` under the strict policy | `reason`: the `GenerationError` name, such as `SourceFailure 1 unavailable` |

Handles carry the names above as data: `Extraction` has `show`, `parent`
and `state`; `Service` has `show`, `origin` and `error`; `Sent` has `show`
and `error`; `forward` returns `{ ok: false, error }` with a
`ForwardError` name. `inspectTraceparent` returns `{ ok: false, error }` with
a codec error name, or `InvalidInputType` for a value that is not a string.
`tracedFetch` passes through a rejection of `fetch` itself, such as a
refused CORS preflight, unchanged.
