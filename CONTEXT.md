# Trace Context

Distributed tracing domain vocabulary used to plan this package.

## Language

**Trace**:
A set of related operations that makes it possible to follow an activity across services. Its shared identifier is the trace ID.

**Span**:
A unit of work within a trace, with its own identity and a possible parent relationship to another operation.

**Trace ID**:
The identifier shared by the operations in a trace. In Trace Context, it has 128 bits and cannot consist entirely of zeros.

**Span ID**:
The nonzero 64-bit identifier of an operation within a trace. When transmitting the context of that operation, its identifier occupies the parent ID field in traceparent.

**Trace context**:
Information carried between participants to associate their operations with the same trace. In the W3C standard, it is represented by the traceparent and tracestate fields.
_Avoid_: Log, complete trace

**Root context**:
The context of the operation that starts a trace, with a new trace ID and its own span ID.

**Child context**:
The context of a new operation linked to a previous operation in the same trace, preserving the trace ID and using its own span ID.

**Remote context**:
A context received from another participant that identifies the sender's operation.

**Local context**:
A context that identifies an operation of the current participant, to be represented in messages sent by that participant.

**Parent context**:
The remote or local context whose trace a child context continues. Its span ID identifies the previous operation.

**Transparent forwarding**:
Transmitting received context fields without representing a new operation or changing the traceparent/tracestate pair.
_Avoid_: Child context creation

**Traceparent**:
A standardized field carrying the version, trace ID, parent ID, and flags. The parent ID identifies the sender's operation represented in the received context.

**Tracestate**:
A standardized field carrying an ordered list of information specific to tracing vendors, associated with traceparent.

**Sampling indication (sampled)**:
The trace-flags bit used to communicate the sampling indication between participants. Its value does not guarantee that operations have been or will be recorded.
_Avoid_: Proof of collection, exporter activation

**Randomness assertion (random-trace-id)**:
The trace-flags bit stating that a trace ID was generated randomly. It is made by whoever produced the trace ID and travels with it; it is not evidence of how the ID was generated.
_Avoid_: Proof of entropy, uniqueness guarantee

**Identifier source**:
Where generation reads the words that become new trace and span IDs: the host's cryptographic generator, or a caller-provided source such as a replayed tape.
_Avoid_: Random number guarantee

**Candidate identifier**:
An ID built from source words before validation. A candidate that is all zero or reuses an excluded ID is rejected; an identifier whose allowed candidates are all rejected is exhausted.

**Traceparent codec**:
The ability to convert between the textual representation of traceparent and its structured values according to a declared format.
_Avoid_: Complete propagator, telemetry SDK

**Trace Context propagator**:
The ability to extract and inject trace context in messages, applying the processing and emission rules of the declared standard.
_Avoid_: Traceparent codec, span exporter

**Context extraction**:
Reading tracing information from an incoming message and interpreting its fields according to the declared format.

**Context injection**:
Writing trace context information into the fields of an outgoing message.

**Trace continuation**:
Adding a new operation to an existing trace, preserving its trace ID and identifying the new operation.

**Trace restart**:
Creating a new trace with new identifiers at a boundary where the received context will not be continued.
_Avoid_: Trace continuation

**Log correlation**:
Associating application logs with an operation's trace context. This association alone does not transmit context to another service.
_Avoid_: Context propagation
