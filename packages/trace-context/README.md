# Trace Context in Bend

A pure, strict codec for the version `00` `traceparent` value. This local
implementation uses Bend 2.0.27 and has not been published. The package entry is
[trace_context.bend](trace_context.bend).

```text
External text
     | TraceParentV00.parse
     +-- Fail{error}
     +-- Done{typed context}
                  | TraceParentV00.format
                  +-- 55-character text
```

## Representation and invariants

| Type | What it expresses |
| --- | --- |
| `Hex.Digit` | One of the 16 hexadecimal values; its text representation is lowercase |
| `Digits.Digits(n)` | Exactly `n` digits; the length is part of the type |
| `Digits.NonZero<n>` | A sequence of length `n` with proof that it is not all zero |
| `TraceParentV00` | A 32-digit trace ID, a 16-digit parent ID and two flag digits |

The `Digits(n)` family follows Base's `Word(n)` pattern: zero length selects an
empty sequence type; a successor selects a constructor with a head and a shorter
tail. The sequence ends with `DNil{}`, and each element uses `DCon{head, tail}`.

**`format` is total and returns `String` directly.** It does not need to reject an
already typed context. Even direct construction must satisfy the lengths and
supply proof that the ID is nonzero.

The two flag digits represent exactly one byte. The codec preserves all bits;
`is_sampled` reads the least significant bit.

In this Bend version, the equality field `evidence` remains available for proof
composition. It is not marked with `-`, which would prevent its reuse in an
ordinary proof. Compilation replaces the proof body with a null value; we
observed one slot per ID in generated JavaScript and C. The proof is therefore
not executed, but its field does not have zero representation cost.

## API and example

Actual signatures, available under the chosen import alias:

```bend
TraceParentV00.parse(text: String) -> Result<&2, &2, Error, TraceParentV00>
TraceParentV00.format(context: TraceParentV00) -> String
TraceParentV00.is_sampled(context: TraceParentV00) -> Bool
Error.show(error: Error) -> String
```

The [example consumer](examples/demo.bend) imports only the public entry. It
handles `Fail` and uses `Done{+context}` to explicitly reuse the context for
formatting and reading `sampled`.

From the repository root:

```sh
./bend packages/trace-context/examples/demo.bend
```

Output:

```text
00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01
sampled: True
```

## Parsing, errors and termination

The parser consumes a known number of characters for each field and preserves
the remaining input. Recursion decreases a `Nat`, allowing the checker to verify
termination. `do Result` chains the stages and propagates the first failure.
Helpers match parameters, following Bend's restrictions.

Errors are `Error` variants, not strings used as a protocol:

- `UnexpectedEnd{offset}`, `InvalidHex{offset}` and `ExpectedSeparator{offset}`;
- `TrailingInput{}`, `ForbiddenVersion{}` and `UnsupportedVersion{version}`;
- `ZeroId{TraceIdField{}}` and `ZeroId{ParentIdField{}}`.

`offset` is zero-based and counts `String` characters, not UTF-8 bytes. When
several problems exist, the first failure in parsing order wins. There is no
trimming, lowercase conversion or partial acceptance. Any additional character
after the final field is rejected. The parser inspects at most the prefix needed
by the format and checks for remaining input without traversing a long suffix.

## Laws, proofs and tests

The [PROOF.bend](PROOF.bend) gate imports public laws and supporting proofs.
The proofs are general, using quantifiers and induction over recursive structures:

- Round-trip conversion for every `Hex.Digit`.
- Serialized length of every indexed sequence.
- Parsing the serialization of every sequence while preserving its suffix.
- Recovering every nonzero ID through its validated constructor.
- A 55-character formatted length for every `TraceParentV00`.
- `parse(format(context)) == Done{context}` for every typed context, preserving
  IDs, their evidence and every flag bit.

The public round-trip law is in [LAWS.bend](LAWS.bend); its
[compositional proof](proofs/context.bend) uses the smaller properties. The
inverse direction, where reformatting every accepted text exactly reproduces
the input, has test coverage but still lacks a universal proof in this package.
The tests are not presented as a substitute for that proof.

The [protocol tests](tests/TEST.bend) use inputs and expected errors independent
of the parser and enumerate all 256 possible flag bytes. The fixtures in
[tests/reject](tests/reject) must fail checking: an incorrect length or zero ID
cannot be constructed with valid evidence.

```sh
./bend packages/trace-context/PROOF.bend --check-only
./bend packages/trace-context/tests/TEST.bend
```

The laws specify precise properties; tests also compare the chosen specification
with the protocol. A round trip alone would not prevent the encoder and decoder
from sharing an incorrect convention.

## Package limits

The format reference is [W3C Trace Context Level 1](https://www.w3.org/TR/2021/REC-trace-context-1-20211123/#traceparent-header).
This module interprets v00 only. It does not implement `tracestate`, future-version
processing, ID generation, sampling decisions or HTTP transport; it is therefore
not a complete W3C propagator or OpenTelemetry SDK.

`format` faithfully represents the codec value. When creating an outgoing header,
a propagation layer must still apply the reserved-bit policy of the chosen
specification. The [published Level 2 document](https://www.w3.org/TR/2024/CRD-trace-context-2-20240328/)
is a Candidate Recommendation Draft and assigns bit `0x02` to the random trace ID
flag. This bit still uses format `00`; it does not change the version to `02`.

The package code is pure and uses no `@unsafe`, FFI or explicit parallelism.
The fields are short and have sequential dependencies; no work justifying
parallelism has been identified at this stage.

## Dependencies and organization

Only `Base` and local modules are used. We evaluated `bend-codec` at commit
`981583d2e11700faa260449f738ca37d63d3db37`: its
[hexadecimal decoder](https://github.com/777genius/bend-codec/blob/981583d2e11700faa260449f738ca37d63d3db37/hex.bend)
accepts uppercase, and its [laws](https://github.com/777genius/bend-codec/blob/981583d2e11700faa260449f738ca37d63d3db37/LAWS.bend)
are closed examples. The core remains small, with types and properties matching
this contract; a future byte adapter could reuse that package. This was a source
review, without running the third-party tests.

- `trace_context.bend`: public API, parser and errors.
- `src/hex.bend` and `src/digits.bend`: basic types and functions.
- `LAWS.bend`, `PROOF.bend` and `proofs/`: specifications and proofs.
- `tests/` and `examples/`: validation and module consumer.

See the [proposal](PROPOSAL.md) for remaining work before publication.
Executed commands and results are recorded in [VALIDATION.md](VALIDATION.md).
