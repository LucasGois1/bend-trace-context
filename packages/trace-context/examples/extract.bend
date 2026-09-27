import Base
import ../trace_context.bend as TC

# A service extracts the trace context of the requests it receives. The first
# request carries the W3C example with two tracestate fields whose names a
# client wrote in different cases. The service continues that trace with a
# child operation of its own, which sends the received state with the
# service's entry first. A request of a later version is read by its known
# prefix. A request with an invalid traceparent keeps the context the service
# already had, its base, and its tracestate is not read.
#
# Extraction never generates an identifier. The child's span ID here is
# supplied, as an integration that manages its own IDs does; generation.bend
# creates one otherwise (Context.child).

def need(-A: Data, -E: Data, what: String, result: Result<&2, &2, E, A>) -> IO(A):
  match result:
    case Fail{error}:
      IO.die(A, 1, "invalid " ++ what)
    case Done{value}:
      IO.pure(A, value)

def present(-A: Data, what: String, value: Maybe<&2, A>) -> IO(A):
  match value:
    case None{}:
      IO.die(A, 1, "no " ++ what)
    case Some{found}:
      IO.pure(A, found)

# The fields of the first request, as a host hands them over.
def request() -> List<&2, TC.Header>:
  [TC.Header{"Host", "api.example.com"},
    TC.Header{"TraceParent", "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"},
    TC.Header{"tracestate", "congo=t61rcWkgMzE"},
    TC.Header{"TRACESTATE", "rojo=00f067aa0ba902b7"}]

def fields.rest(fields: List<&2, String>) -> String:
  match fields:
    case Nil{}:
      ""
    case Con{field, rest}:
      " | " ++ field ++ fields.rest(rest)

# The received tracestate fields, as they came.
def fields(fields: List<&2, String>) -> String:
  match fields:
    case Nil{}:
      "none"
    case Con{field, rest}:
      field ++ fields.rest(rest)

def pair(received: Maybe<&2, TC.ReceivedPair>) -> String:
  match received:
    case None{}:
      "nothing"
    case Some{TC.ReceivedPair{traceparent, tracestate}}:
      traceparent ++ " | " ++ fields(tracestate)

def send(emission: TC.Emission) -> IO(Unit):
  match emission:
    case TC.Emission{traceparent, tracestate, dropped}:
      do IO<Unit>:
        Unit <- IO.print("child traceparent: " ++ traceparent)
        IO.print("child tracestate: " ++ tracestate)

# Continue the received trace with a child operation that sends the received
# state, with this service's entry first.
def continue(+limits: TC.Limits, +incoming: TC.IncomingContext) -> IO(Unit):
  do IO<Unit>:
    span : TC.SpanId <- need(TC.SpanId, TC.Error, "span ID", TC.SpanId.parse("53995c3f42cd8ad8"))
    child : TC.LocalContext <- need(TC.LocalContext, TC.ContextError, "child",
      TC.Context.child_from_id(TC.IncomingContext.parent(incoming), span, TC.InheritSampled{}))
    key : TC.StateKey <- need(TC.StateKey, TC.EntryError, "key", TC.StateKey.parse("fw529a3039"))
    value : TC.StateValue <- need(TC.StateValue, TC.EntryError, "value", TC.StateValue.parse("cHJpbWFyeQ"))
    send(TC.OutgoingContext.emit(limits,
      TC.OutgoingContext.set(TC.OutgoingContext.with_state(child, TC.IncomingContext.state(incoming)), key, value)))

def received(+limits: TC.Limits, +extraction: TC.Extraction) -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.print("request: " ++ TC.Extraction.show(extraction))
    +incoming : TC.IncomingContext <- present(TC.IncomingContext, "incoming context",
      TC.Extraction.incoming(extraction))
    Unit <- IO.print("received state: " ++ TC.TraceState.format(TC.IncomingContext.state(incoming)))
    Unit <- IO.print("kept for forwarding: " ++ pair(TC.IncomingContext.received(incoming)))
    continue(limits, incoming)

# The sender's operation of a later version's request.
def future(+extraction: TC.Extraction) -> IO(Unit):
  do IO<Unit>:
    incoming : TC.IncomingContext <- present(TC.IncomingContext, "incoming context",
      TC.Extraction.incoming(extraction))
    IO.print("later version: " ++ TC.Extraction.show(extraction) ++ ", parent " ++
      TC.SpanId.to_string(TC.RemoteContext.span_id(TC.IncomingContext.context(incoming))))

def base_text(context: Maybe<&2, TC.BaseContext>) -> String:
  match context:
    case Some{TC.OutgoingBase{outgoing}}:
      TC.TraceParentV00.format(TC.LocalContext.to_traceparent(TC.OutgoingContext.context(outgoing)))
    case _:
      "another context"

def refused(+extraction: TC.Extraction) -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.print("invalid request: " ++ TC.Extraction.show(extraction))
    IO.print("kept base: " ++ base_text(TC.Extraction.context(extraction)))

def main() -> IO(Unit):
  +limits = TC.Limits.default()
  do IO<Unit>:
    Unit <- received(limits, TC.Context.extract(limits, request(), None{}))
    Unit <- future(TC.Context.extract(limits,
      [TC.Header{"traceparent", "cc-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01-future"}], None{}))
    trace : TC.TraceId <- need(TC.TraceId, TC.Error, "trace ID", TC.TraceId.parse("5b8efff798038103d269b633813fc60c"))
    span : TC.SpanId <- need(TC.SpanId, TC.Error, "span ID", TC.SpanId.parse("eee19b7ec3c1b174"))
    refused(TC.Context.extract(limits,
      [TC.Header{"traceparent", "00-00000000000000000000000000000000-00f067aa0ba902b7-01"},
        TC.Header{"tracestate", "congo=t61rcWkgMzE"}],
      Some{TC.OutgoingBase{TC.OutgoingContext.new(TC.Context.root_from_ids(trace, span))}}))
