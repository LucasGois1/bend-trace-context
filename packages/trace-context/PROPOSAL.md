# Trace Context for Bend — initial proposal

**Status on 2026-09-24:** a v00 codec is implemented locally in Bend 2.0.27, with
dependent types, proofs and tests. Approved name: `bend-trace-context`; the
package has not been published.
See the [API and code guide](README.md).

**Chosen direction for the first publishable version:** a complete W3C Trace
Context propagator, including extraction and injection, `tracestate`, future
version handling, processing and emission rules, ID generation and creation of
root and child contexts. The project owner approved the design, validation
strategy and distribution plan at the end of `grill-with-docs`.
[Specification #1](https://github.com/LucasGois1/bend-trace-context/issues/1) and
its 14 approved tickets are published. Execution begins with
[#2: reproducible codec installation](https://github.com/LucasGois1/bend-trace-context/issues/2).
The sections below describe the existing codec and its original proposal;
exclusions from that initial scope do not limit the newly chosen scope.

## Criteria for the new scope

The project owner established the direction as the most complete technically
feasible implementation, with ease of adoption, usability and maintainability.
ID generation and context creation are part of the planned delivery; each
consumer will not be required to implement them independently.

The default sampling policy is approved: new traces start with `sampled=0`;
continuation preserves the received indication by default, with an explicit
option for callers to change it through permitted operations. This decision is
part of the [approved specification](https://github.com/LucasGois1/bend-trace-context/issues/1).

The approved design combines pure validation and propagation operations with
convenience functions that obtain randomness through Base using `IO`. Consumers
will be able to create contexts through the ready-to-use path or supply valid
IDs when integrating with an existing system. Public constructors and functions
must produce typed values with their evidence, without requiring ordinary
users to write proofs to use the package.

Applying these criteria, the plan must cover:

- The complete workflow of receiving, extracting, continuing or starting a
  context and injecting it into an outgoing request, with explicit failure rules.
- Trace ID and span ID generation using Base's cryptographic source, failure
  handling and zero rejection, alongside the supplied-ID path.
- A `tracestate` API, invalid-input diagnostics and caller control over policies,
  with a documented path for common use.
- A reference HTTP integration, reproducible installation, end-to-end examples,
  API and compatibility documentation, and a license and version defined before
  publication.
- Laws and proofs for core invariants and transitions, independent protocol
  tests and external HTTP validation, each with its scope stated.

The approved baseline is a pinned W3C Level 2 revision, and the target matrix
must validate the core and generation in native Linux/macOS Bend programs and
JavaScript/Node. Browser support must also be assessed; its feasibility depends
on the generated program and integration, not merely the availability of
`crypto.getRandomValues`. These support targets are not yet validation results
or published compatibility promises.

The normative baseline is the
[W3C Trace Context Level 2 CR Draft](https://www.w3.org/TR/2024/CRD-trace-context-2-20240328/).
The [usage design](DESIGN.md) consolidates the workflows, invalid-input policies,
operational limits, public surface, laws and validation criteria approved in the
joint review. The public name `bend-trace-context`, initial version `0.1.0`, MIT
license and English public documentation were also approved.

## Problem and first consumer

Enable Bend applications to read tracing context received from other services.
The first consumer will be a community HTTP client or server; the concrete
integration will be chosen after the pure core stabilizes. The initial
assessment did not identify a specialized package, but the need still has to
be validated with the community.

## Existing module contract

The existing module implements only the version `00` `traceparent` value codec:

```text
00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
│  └────────── trace-id ──────────┘ └── parent-id ──┘ │
version         32 hex                  16 hex       flags
 2 hex                                               2 hex
```

The trace ID identifies the distributed trace; the parent ID identifies the
sender's operation. The v00 format is 55 ASCII characters, with lowercase
hexadecimal and fixed separators. Both IDs must be nonzero. The stable reference
is [W3C Trace Context Level 1, §§3.2.2–3.2.4](https://www.w3.org/TR/2021/REC-trace-context-1-20211123/#traceparent-header),
the Recommendation published on 2021-11-23.

Implemented API, summarized in contract notation:

```text
TraceParentV00 = {
  trace_id: NonZero<32n>,
  parent_id: NonZero<16n>,
  flags: Digits(2n)
}

TraceParentV00.parse(String)          -> Result<Error, TraceParentV00>
TraceParentV00.format(TraceParentV00)  -> String
TraceParentV00.is_sampled(TraceParentV00) -> Bool
```

**Representation decision:** field lengths and alphabets participate in the
types; IDs carry proofs that they are nonzero. This allows a total formatter
without revalidating typed contexts. A public constructor must also satisfy
these invariants. Names follow Base's `Type.verb` convention.

Implemented errors: premature end, incorrect separator, invalid hexadecimal,
excess input, zero ID, forbidden version (`ff`) and unsupported version. Read
errors include a position; the zero-ID error identifies the field. Flags outside
a single byte's range are not representable in `Digits(2n)`. Future versions are
outside the explicitly named `TraceParentV00` type.

The codec will preserve all flag bits; `is_sampled` will inspect the `0x01` mask.
**Faithful formatting is not an emission policy for a new header.** Level 1
requires reserved bits to be cleared on emission. That policy belongs in a
later layer; its round-trip law must account for normalization.

The [published Level 2](https://www.w3.org/TR/2024/CRD-trace-context-2-20240328/)
is a Candidate Recommendation Draft dated 2024-03-28: it adds the
`random-trace-id` flag (`0x02`) while retaining format version `00`. Preserving
the byte avoids losing this information; interpreting the flag cannot prove
that an ID was generated randomly. The existing codec does not claim
conformance to that draft; the propagator baseline is part of the new plan above.

## What to demonstrate and test

| Property | Evidence |
| --- | --- |
| For a typed context `c`, `parse(format(c))` recovers `Done{c}` | Proved universal law, with no external validity precondition |
| If `parse(s)` succeeds, reformatting recovers exactly `s` | Covered by test cases; the universal proof of this direction is still pending |
| Formatting produces 55 characters | Universal law and a proof by composition of indexed lengths |
| IDs have the correct length and are nonzero | Dependent types and evidence required by constructors; negative compilation fixtures |
| Reading digits preserves their values and the suffix | Universal law, proved by induction on length |
| Flags survive the codec, including unknown bits | All 256 values exercised, with an independent sampled oracle |
| The implementation matches the selected portion of the standard | Independent vectors and rejection tests |

Parser cases: lengths 54/55/56, incorrect separators, uppercase, Unicode, zero
IDs, flags `00/01/02/03/ff`, version `ff`, a future version and a suffix after
the flags. The [W3C suite](https://github.com/w3c/trace-context/blob/main/test/test.py)
is a reference for case categories; its harness tests services and has not
been run against this codec.

## Boundaries and next milestone

This first module does not claim conformance as a W3C propagator: it lacks
`tracestate`, future-version processing and propagation rules. ID generation,
a span SDK, exporters and HTTP adapters belong to later stages.

1. **Implemented:** `TraceParentV00`, parser, total formatter, errors and sampled
   lookup. A separate consumer and tests passed in direct, JavaScript and native
   execution. The [assessment of `bend-codec`](https://github.com/777genius/bend-codec/tree/981583d2e11700faa260449f738ca37d63d3db37)
   motivated keeping the core small with a specific contract.
2. **Before publication:** complete the universal proof for every accepted text,
   align the scope with a real consumer, define a license and version, and
   document actually supported backends. Current validation covers macOS ARM64.
   Community consultation remains an adoption step to complete.

No compiler changes were needed for the implementation.
