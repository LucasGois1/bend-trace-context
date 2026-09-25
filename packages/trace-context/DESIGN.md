# Propagator usage design

The design, validation strategy and distribution plan were approved by the
project owner at the end of `grill-with-docs` on 2026-09-24. This document records
the decisions that inform the specification; it does not claim that the API is
implemented. The existing code remains the v00 codec documented in the README.
The names below express conceptual contracts; final signatures must be checked
against Bend's capabilities.

The published summary is [specification #1](https://github.com/LucasGois1/bend-trace-context/issues/1).
The breakdown into 14 tickets was approved and published with native issue
dependencies. The specification links the execution tickets; the first
available ticket is
[#2: reproducible codec installation](https://github.com/LucasGois1/bend-trace-context/issues/2).

## Agreed direction

Deliver a complete propagator and make it easy to adopt. ID generation and
creation of root and child contexts are part of the first planned version.
The supplied-ID path must also serve applications that already have a generator.

**Approved sampling policy:** root contexts start with `sampled=0`; child contexts
preserve the received context's indication by default. Callers may explicitly
choose a different indication, subject to the standard's mutation rules.
This decision is part of the
[approved specification](https://github.com/LucasGois1/bend-trace-context/issues/1).

## Workflows and operations

| Workflow | Conceptual operations | Expected result |
| --- | --- | --- |
| Start a trace | `Context.root` | A context with a new trace ID and span ID, obtained from Base's cryptographic source |
| Continue a received operation | `Propagator.extract` and `Context.child` | The same trace ID, a new span ID, and flags/state handled according to the declared policy |
| Send to another service as a participant | `Propagator.inject` | Emit the local context with valid headers, preserving HTTP fields unrelated to the package |
| Forward without creating an operation | `Propagator.forward` | Forward the context field pair unchanged, or return a diagnostic when it cannot fit within the limits |
| Integrate existing IDs | `TraceId.parse`, `SpanId.parse`, `Context.from_ids` | Validation returns types carrying the invariants, or structured errors |
| Manage vendor state | Lookup, insert, update and remove operations on `TraceState` | Valid keys, uniqueness and ordering consistent with the standard; context changes follow the mutation rules |
| Diagnose an input | Extraction with a structured result and diagnostic | Distinguish absence, an invalid field, discarded state and an exceeded limit |
| Integrate a server/client | HTTP adapter and executable example | An incoming request can continue or start a context and make an outgoing call |

The common-use API must not require consumers to construct indexed digits or
write proofs. Validated constructors and generation functions produce those
values. Advanced contracts remain available for composition. No extraction
function may generate IDs implicitly; creation belongs to an explicit
start/continue operation or an integration convenience function.

## Execution model

```text
incoming headers
        |
        v
pure extraction + diagnostic
        |
        +-- valid context ----> continue with a new operation --+
        |                                                      |
        +-- absent/invalid ---> start/restart policy ------------+
                                                               |
                                         ID generation with IO --+
                                                               v
                                                        local context
                                                               |
                                            pure injection + HTTP adaptation
                                                               |
                                                               v
                                                      outgoing request
```

The generator must return explicit failures, reject zero and have a defined
attempt limit. Tests must be able to supply a deterministic source to exercise
failures and rejected values. Proofs must cover deterministic operations and
their invariants; the environment's entropy source is a documented dependency,
not a property proved by the package.

## Approved contracts

Baseline: W3C Trace Context Level 2, the CR Draft published on 2024-03-28, with
Bend initially pinned to 2.0.27. The technical choices in this section were
approved together with the direction on completeness, adoption and sampling.

### Extraction, creation and injection

- `extract` is pure: valid input produces a remote context; an absent or invalid
  traceparent preserves the supplied base context, with a diagnostic.
- `continue_or_start` uses the extracted context or a still-valid base to create
  a child; it creates a root only when no usable context exists. Each new
  operation gets its own ID; deliberate restart is an explicit operation.
  Restart discards the previous state and applies root defaults, including
  sampled `0`, unless a new policy/state is explicitly supplied.
- Distinguish remote and local contexts in public contracts. `inject` takes a
  local context produced by root creation, child creation or explicit
  construction of a local operation with supplied IDs; it does not generate
  IDs. It replaces all previous occurrences of traceparent/tracestate, uses
  lowercase names and preserves other headers and their relative order. An
  explicit clearing operation removes stale context when the integration
  proceeds without context.
- The carrier preserves repeated values and their order. Header name comparison
  is ASCII case-insensitive; repeated traceparent fields are invalid. Adapters
  must document when the host API has already combined values before extraction.
- The v00 codec remains strict. The propagator accepts a valid known prefix of
  future versions without interpreting unknown extensions, and participation
  emits v00. Emission applies the known Level 2 flags; transparent forwarding
  is a separate path from creating a new participating operation.
- `forward` preserves the received pair without normalizing flags, downgrading
  the version or editing/truncating state. If it cannot forward the pair intact
  within the limits, it returns a diagnostic: the caller may create a child
  before injection or handle the failure. A remote context cannot be reinjected
  with altered tracestate while traceparent remains unchanged. Construction
  with external IDs requires callers to associate them with the local operation
  they represent.

### Tracestate and limits

- Ignore empty members; keep the first occurrence of repeated keys. Validate
  every entry's grammar before deduplication; other errors discard the entire
  state while preserving a valid traceparent.
- Count members before deduplication, after ignoring empty members. More than
  32 entries discards the state. Inserting/updating moves the key to the front
  and preserves the relative order of the others; inserting a 33rd removes the
  last one. Changes to state associated with a context follow the standard's
  mutation rules, including their relationship to traceparent changes.
- Input budget: 32 KiB per traceparent value and 32 KiB for the combined
  tracestate values, including whitespace/extensions. Exceeding the tracestate
  budget does not invalidate traceparent. HTTP adapter limits applied before
  the library remain the transport's responsibility.
- Emitted tracestate limit: 512 bytes by default, configurable through a
  validated value of at least 512. This is a local policy, not a normative W3C
  maximum. Truncate whole entries, first removing those longer than 128
  characters from the right, then removing the remaining entries from the
  right. Preserve the surviving entries' order and report discards in the
  diagnostic.
- Validate limit configuration before use. Measure the input budget in UTF-8
  octets; the content accepted by the format is ASCII. Do not traverse an
  already oversized input indefinitely to prepare error messages. The
  traceparent input limit must allow at least 55 bytes; the tracestate input
  limit must allow at least the configured output budget so that the same
  configuration accepts its emitted normalized representation.

### Generation and failures

- The default cryptographic source comes from the environment through Base, or
  through a WebCrypto bridge in the browser. A replaceable boundary supports
  controlled test sources and integrations with caller-provided sources.
- Convert four U32 values into a trace ID and two into a span ID, with words and
  digits in big-endian order. Allow up to eight candidates per ID; reject zero
  and, for a child, equality with the previous span ID. A source failure stops
  generation immediately with a structured error. There is no clock/counter
  fallback.
- Supplied IDs must satisfy length/alphabet/nonzero requirements; child
  creation also rejects reuse of the previous ID. The random origin of external
  IDs is an explicit caller assertion; the default makes no such assertion.
  Internal cryptographic generation sets random; continuation preserves that
  bit while preserving the trace ID. This does not prove global absence of
  collisions.

- **Absent/invalid input:** extraction distinguishes these cases and does not
  alter a valid supplied base context. The convenience integration may start a
  new trace when no usable context exists.
- **Failure to obtain IDs:** return a structured error from the generation API.
  For the convenience integration, the recommendation is to let the application
  operation proceed with a diagnostic indicating that tracing is unavailable;
  applications requiring traceability may explicitly choose to fail. Forwarding
  the original pair intact is an alternative only when it was fully accepted
  and can be sent without transformation or truncation; otherwise, the
  convenience integration clears outgoing context fields. The diagnostic
  distinguishes forwarding, absence of context and creation of a new operation,
  without reporting successful generation when it failed.
- **Sampling (approved):** preserve the received indication when continuing and
  use `sampled=0` when starting, with explicit caller control. The library must
  distinguish carrying the indication from actually recording operations.
- **Diagnostics:** typed results distinguish absence, rejection, discarding,
  truncation and generation failure. Extraction first determines traceparent
  eligibility; without a valid traceparent, it does not interpret tracestate.
  Do not log headers automatically; callers choose how to observe these results.

These contracts are approved but still need implementation and validation.
The library does not collect spans on its own.

## Adoption and compatibility to demonstrate

- A new consumer project can install/import an identified version and run the
  examples without copying implementation files.
- A short guide to starting, receiving and sending contexts, an API reference,
  error diagnostics and a compatibility matrix accompany the release.
- An HTTP integration preserves relevant header repetitions/order and allows
  receiving a request and calling another service within the same operation.
  The adapter is separate from the core so that other HTTP packages can use it.
- Standard target: W3C Level 2 with a pinned publication. Current OpenTelemetry
  propagator requirements serve as an interoperability reference; promised
  compatibility must be described precisely.
- Execution targets: native Linux/macOS and Bend programs compiled to
  JavaScript/Node. Browsers require a separate assessment of module exports,
  effects and HTTP integration before inclusion in the release's support
  promise. Research found an official browser loader that exports pure
  functions but excludes `IO` functions. Evaluate a WebCrypto/Fetch bridge that
  provides ready-to-use generation and routes inputs through validated
  constructors.
- The public name, license, version and compatibility policy are defined below;
  the account/namespace and distribution artifact will be checked before
  publication.

### Support matrix and feasibility experiments

| Environment/capability | Integration path | Required evidence |
| --- | --- | --- |
| Native macOS ARM64 and Linux x86_64 | Base IO; reference paymog/bend-net pinned to `274591f1d1fcca2e4aa39ba65e505b32e2dbff21` | Installed consumer, corpus, real/controlled source, incoming and outgoing HTTP |
| Bend programs compiled to JS/Node | Node 22 and 24, with exact versions recorded in CI | Core, generation and error contracts, including a real JS bridge failure |
| Consumption by a JS application | Pure module exports and conversion/validation at the boundaries | Actual import and host integration, without trusting externally constructed JS objects |
| Browser | Official loader, WebCrypto bridge and Fetch adapter | Reproducible bundle, root/child contexts, observing server, failures and CORS in Chromium/Firefox/WebKit with recorded versions |

This is the target matrix, not a claim of support already achieved. The paymog
HTTP integration uses Bun FFI in its JS backend and must not be advertised as a
Node transport. For Node/browser, investigate integration through the host's
HTTP/Fetch facilities and the pure module. Actually supported versions and
architectures must appear in the documentation and required jobs.

Feasibility experiments must establish module export/import, JS boundary
validation, entropy failure translation and HTTP adapter execution with the
pinned release. A demonstrated technical blocker must be reported with an
alternative and its consequence for the release; it cannot become a silent
skip. If a platform requires a change outside the package's scope, review the
plan using that evidence before promising support.

Approved distribution: public name `bend-trace-context`, initial version
`0.1.0` and [MIT](https://opensource.org/license/mit) license. Public documentation
is in English. Maintain a changelog and explicitly identify breaking changes;
using a 0.x version does not remove the need for migration documentation.
BendHub account/namespace availability and publication will be checked during
release preparation. This does not change repository visibility at this stage.

## Evidence required by the plan

1. A matrix linking rules from the adopted publication, local policies,
   proposed laws and external tests. The final law list will be part of the
   specification.
2. Core proofs and independent protocol tests, including inputs that the
   formatter itself would never produce.
3. An external HTTP suite pinned by SHA, with explicit results and discrepancies.
4. ID generation tests: success, zero, entropy failure, attempt limit and
   conversions between words/bytes/digits on supported backends.
5. An independent consumer and an end-to-end workflow, validating the
   system/runtime matrix that the release declares.

### Approved test boundaries

The primary surface is the package's installed public API, exercised by a
separate consumer. A minimal HTTP service uses that same API and is tested by
the W3C harness; neither the adapter nor the harness may reimplement context
rules. The entropy source is the controllable boundary needed to trigger rare
failures without relying on chance. Do not create a suite coupled to every
helper.

Pin the W3C suite to `acab820be9db7b3433668baa5cdd43f57f4c4be0`, with
`SPEC_LEVEL=2` and `STRICT_LEVEL=2`. Run `TraceContextTest`, `AdvancedTest` and
`TraceContext2Test`; acceptance requires no failures, errors or unexpected
skips. Record counts and all skips; explicitly reconcile any demonstrated
discrepancy between the suite and the standard before acceptance, without
treating the report alone as approval. Supplement coverage with the sampled=0
default, random on/off, repeated injection, clearing stale fields and generation
failures. Passing finite tests will not be described as a complete proof of
the standard.

### Planned core laws

- Extracting an injected context recovers its normalized propagatable
  projection, accounting for its remote origin, emitted flags and tracestate
  limits.
- Injecting the same context is idempotent and preserves unrelated headers.
- Creating a child preserves trace ID/random and applies sampled inheritance
  or an override.
- State operations preserve grammar, uniqueness, limits and the order of
  unmodified entries; discarding state does not alter a valid traceparent.
- Successful generation produces valid IDs; the deterministic algorithm
  respects the candidate budget. The entropy source remains an external
  assumption.
- Preserve/complete the codec laws, including the inverse direction (proved in
  [#5](https://github.com/LucasGois1/bend-trace-context/issues/5)). The strict
  codec's exact textual equivalence is not the right
  equivalence for the entire propagation layer, which normalizes representations.

Final statements must make preconditions and normalizations explicit. Critical
proofs cannot be replaced by closed examples or local axioms.

The normative baseline is the
[W3C Trace Context Level 2 CR Draft](https://www.w3.org/TR/2024/CRD-trace-context-2-20240328/).
The [approved specification](https://github.com/LucasGois1/bend-trace-context/issues/1)
records the conformance and integration contracts.
