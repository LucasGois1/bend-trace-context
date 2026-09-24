# Traceparent v00 codec

The currently implemented part of **bend-trace-context 0.1.0-dev** is a pure,
strict v00 codec for Bend 2.0.27. It has no external package dependencies beyond
the compiler's bundled `Base`. The public entry is
[trace_context.bend](trace_context.bend). See the root
[installation guide](../../README.md) to consume it from a pinned Git checkout.

## Public API

Names below are qualified by the alias chosen for the public entry, such as `TC`:

```bend
TraceParentV00.parse(text: String) -> Result<&2, &2, Error, TraceParentV00>
TraceParentV00.format(context: TraceParentV00) -> String
TraceParentV00.is_sampled(context: TraceParentV00) -> Bool
Error.show(error: Error) -> String
```

`parse` returns `Done{context}` for a valid input or `Fail{error}`. Ordinary
consumers receive a validated context directly; no proof terms are needed.
`format` is total for the typed argument and preserves every flag bit.
`is_sampled` reads the least significant flag bit. It does not decide whether
to record or export a span.

Use `Done{+context}` when reusing the context for both formatting and inspection,
as in the [executable example](examples/demo.bend). Run it from the repository
root with `./bend packages/trace-context/examples/demo.bend`.

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

Structured errors are constructors of `Error`; callers may pattern-match on
them rather than parsing the human-readable result of `Error.show`:

| Error | Meaning |
| --- | --- |
| `UnexpectedEnd{offset}` | A required character is missing |
| `InvalidHex{offset}` | A character is not lowercase ASCII hexadecimal |
| `ExpectedSeparator{offset}` | A required dash is absent |
| `TrailingInput{}` | Extra characters follow the flag byte |
| `ForbiddenVersion{}` | The version is `ff` |
| `UnsupportedVersion{version}` | A syntactically valid version is neither `00` nor `ff` |
| `ZeroId{TraceIdField{}}` | The trace ID is all zero |
| `ZeroId{ParentIdField{}}` | The parent ID is all zero |

These strict-codec errors are not the future propagator's extraction policy.
A valid future-version header can be rejected here while a participating
propagator would process its known prefix.

## Representation and proofs

`TraceParentV00` contains a `Digits.NonZero<32n>` trace ID, a
`Digits.NonZero<16n>` parent ID and `Digits.Digits(2n)` flags. Internally,
`Hex.Digit` has exactly 16 constructors and the digit sequence's length is
part of its type. Nonzero IDs carry checked evidence. Formatting cannot
encounter a typed ID with the wrong length or all zero digits.

The parser is the current convenient public constructor. Low-level direct
construction requires the matching indexed values and evidence; validated
supplied-ID lifecycle constructors are planned in
[issue #5](https://github.com/LucasGois1/bend-trace-context/issues/5).

[LAWS.bend](LAWS.bend) declares, and [PROOF.bend](PROOF.bend) checks:

- `String.length(format(context)) == 55n` for every typed context.
- `parse(format(context)) == Done{context}` for every typed context, including
  the IDs, their evidence and all flag bits.

Auxiliary universal proofs cover hexadecimal conversion, encoded lengths,
reading an encoded sequence while preserving its suffix and recovery of a
nonzero ID. Proofs use structural induction/composition, without local axioms
or `@unsafe` shortcuts.

The inverse property—formatting every successfully parsed text reproduces that
exact text—has example coverage but **does not yet have a universal proof**.
Issue #5 owns that obligation. Tests do not replace it.

In this compiler version the equality evidence stays available while composing
proofs. Compilation erases the proof body, but generated C/JS retains one
placeholder field per ID. There is no claim of zero representation overhead.

## Validation and scope

The [public corpus](tests/TEST.bend) uses eight valid inputs, 26 malformed inputs
with expected errors/positions, and all 256 flag bytes with an independent
numeric sampled-bit oracle. The [negative fixtures](tests/reject) must fail
typechecking for the intended nonzero/length mismatch. The
[validation guide](../../packages/trace-context/VALIDATION.md) describes reproducible commands
and the separate clean consumer.

The strict v00 format follows
[W3C Trace Context Level 1](https://www.w3.org/TR/2021/REC-trace-context-1-20211123/#traceparent-header).
The planned propagator targets the pinned
[Level 2 Candidate Recommendation Draft](https://www.w3.org/TR/2024/CRD-trace-context-2-20240328/).
The random-trace-id flag `0x02` still uses wire version `00`.

This codec does not yet implement tracestate, generation, sampling policy,
future-version participation or HTTP/browser integration. Its faithful formatter
does not mask reserved bits as participant injection will. There is no claim of
complete W3C propagator conformance or a full OpenTelemetry SDK.

See the [initial codec validation record](VALIDATION.md) for the original
execution evidence and [CHANGELOG.md](../../CHANGELOG.md) for versioning
and migration.
