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

**Tracestate member**:
One comma-separated item of a tracestate value: an entry, or nothing but optional whitespace.

**Tracestate entry**:
One vendor's key and opaque value in tracestate. The key names the vendor.
_Avoid_: Tracestate header, span attribute

**Outgoing context**:
A local context together with the tracestate its participant sends with it. Its state may be edited, because its traceparent identifies an operation of this participant.
_Avoid_: Forwarded context

**Output truncation**:
Removing whole tracestate entries until the emitted value fits the output budget: the rightmost entry larger than 128 octets while there is one, then the rightmost entry. The entries that remain keep their order.
_Avoid_: Cutting an entry

**Input budget**:
The most UTF-8 octets of a received traceparent value or combined tracestate value that the package reads. A larger value is refused before it is interpreted.

**Output budget**:
The most UTF-8 octets of tracestate the package emits. It is a capacity policy of the package, not a limit set by the standard.

**Trace flags**:
The traceparent byte that carries the sampling indication and the randomness assertion. A context keeps only those two known flags, so its trace flags are 00, 01, 02 or 03.
_Avoid_: Span flags

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

**Header map**:
A transport's own grouping of a message's fields by name, such as bend-kit's map from each name to its values in arrival order. A transport adapter turns it into a carrier and back.
_Avoid_: Carrier

**Transport adapter**:
Code that translates between a transport's representation of message fields and the carrier, without deciding any Trace Context rule.
_Avoid_: Propagator

**Carrier**:
The fields of a message in their order, each a name and a value, from which trace context is extracted and into which it is injected. Repeated fields stay separate unless the host joined them.
_Avoid_: Header map

**Context field**:
A traceparent or tracestate field of a carrier, whatever the ASCII case of its name. The other fields of the carrier are its unrelated fields.

**Context cleanup**:
Removing the context fields of a carrier for a message sent without trace context.

**Incoming context**:
A remote context together with the tracestate that goes with it: one extracted from a message, which also keeps the received pair unless that tracestate was refused, or one built from its parts, which keeps none.
_Avoid_: Local context

**Received pair**:
The traceparent and tracestate field values of a message as they were accepted, kept so that the context can be forwarded unchanged.

**Base context**:
The context that extraction keeps when a message carries no usable traceparent: a context received earlier, or an operation of this participant.

**Known prefix**:
The trace ID, parent ID and flags at the start of a traceparent of a later version, read as those of version 00. The fields after them are not interpreted.

**Trace continuation**:
Adding a new operation to an existing trace, preserving its trace ID and identifying the new operation.

**Trace restart**:
Creating a new trace with new identifiers at a boundary where the received context will not be continued.
_Avoid_: Trace continuation

**Trust boundary**:
A point where a participant does not continue the contexts it receives and restarts their traces instead, keeping none of their tracestate.

**Service operation**:
The operation a participant creates for a message it receives: a child of the context that the message or the base supplies, a root when there is neither, or a trace restart at a trust boundary. Each message the participant sends gets a child of it.
_Avoid_: Incoming context

**JavaScript facade**:
The package's interface for JavaScript applications. It converts JavaScript values at the boundary and feeds the package's generation words from WebCrypto, without deciding any Trace Context rule.
_Avoid_: JavaScript SDK, second implementation

**Propagation allowlist**:
The origins or URLs, beyond a page's own origin, to which a page's requests carry context fields. A cross-origin request carrying them needs a CORS preflight that allows them.
_Avoid_: Trusted origins

**Handle**:
A frozen JavaScript object that only the facade creates, standing for a value of the package. An object that merely looks like a handle is refused.
_Avoid_: Wrapper object, raw module value

**Failure policy**:
How an operation that needs a new identifier reports a generation failure: leniently, letting the business operation proceed without a new operation, or strictly, returning the error so that the caller can refuse the operation.
_Avoid_: Retry policy

**Log correlation**:
Associating application logs with an operation's trace context. This association alone does not transmit context to another service.
_Avoid_: Context propagation
