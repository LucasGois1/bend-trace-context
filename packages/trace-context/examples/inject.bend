import Base
import ../trace_context.bend as TC

# A service takes part in the traces of the requests it handles and passes on
# those it only relays. For a request it handles, it continues the received
# trace with a child operation and injects that operation into the request it
# sends on, reusing a container that still holds an older context: the old
# context fields go, whatever the case of their names, the application's
# fields keep their order, and the new fields come last with lowercase names.
# A request it relays is forwarded unchanged: a later version with a field
# this package does not know, and every flag bit set, travels as it came,
# with its tracestate fields joined into one. A message sent without context
# has its old context fields removed. A received state too large for the
# output budget cannot be forwarded whole, so the service continues that
# trace with a child instead, whose state is truncated to the budget.
#
# The children's span IDs here are supplied, as an integration that manages
# its own IDs does; generation.bend creates them otherwise (Context.child).

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

def field(header: TC.Header) -> String:
  match header:
    case TC.Header{name, value}:
      name ++ ": " ++ value

def fields.rest(carrier: List<&2, TC.Header>) -> String:
  match carrier:
    case Nil{}:
      ""
    case Con{header, rest}:
      " | " ++ field(header) ++ fields.rest(rest)

# The fields of a carrier, in their order.
def fields(carrier: List<&2, TC.Header>) -> String:
  match carrier:
    case Nil{}:
      "no fields"
    case Con{header, rest}:
      field(header) ++ fields.rest(rest)

def keys.rest(keys: List<&2, TC.StateKey>) -> String:
  match keys:
    case Nil{}:
      ""
    case Con{key, rest}:
      "," ++ TC.StateKey.to_string(key) ++ keys.rest(rest)

# The dropped keys joined by commas, or "none".
def keys(keys: List<&2, TC.StateKey>) -> String:
  match keys:
    case Nil{}:
      "none"
    case Con{key, rest}:
      TC.StateKey.to_string(key) ++ keys.rest(rest)

# The context a received request carries.
def incoming(+limits: TC.Limits, request: List<&2, TC.Header>) -> IO(TC.IncomingContext):
  present(TC.IncomingContext, "incoming context", TC.Extraction.incoming(TC.Context.extract(limits, request, None{})))

# A child of a received operation, with a supplied span ID.
def child(+received: TC.IncomingContext, span_text: String) -> IO(TC.LocalContext):
  do IO<TC.LocalContext>:
    span : TC.SpanId <- need(TC.SpanId, TC.Error, "span ID", TC.SpanId.parse(span_text))
    need(TC.LocalContext, TC.ContextError, "child",
      TC.Context.child_from_id(TC.IncomingContext.parent(received), span, TC.InheritSampled{}))

# A request this service handles, with the W3C example context in two
# tracestate fields.
def handled() -> List<&2, TC.Header>:
  [TC.Header{"Host", "api.example.com"},
    TC.Header{"traceparent", "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"},
    TC.Header{"tracestate", "congo=t61rcWkgMzE"},
    TC.Header{"tracestate", "rojo=00f067aa0ba902b7"}]

# The container of the request it sends on, which still holds the context of
# an earlier request.
def reused() -> List<&2, TC.Header>:
  [TC.Header{"Host", "inventory.internal"},
    TC.Header{"TraceParent", "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"},
    TC.Header{"Content-Type", "application/json"},
    TC.Header{"TRACESTATE", "stale=1"}]

# Continue the handled request's trace with a child that puts this service's
# entry first, and inject it into the reused container.
def handle(+limits: TC.Limits) -> IO(Unit):
  do IO<Unit>:
    +received : TC.IncomingContext <- incoming(limits, handled())
    operation : TC.LocalContext <- child(received, "53995c3f42cd8ad8")
    key : TC.StateKey <- need(TC.StateKey, TC.EntryError, "key", TC.StateKey.parse("fw529a3039"))
    value : TC.StateValue <- need(TC.StateValue, TC.EntryError, "value", TC.StateValue.parse("cHJpbWFyeQ"))
    IO.print("sent on: " ++ fields(TC.Injection.carrier(TC.Context.inject(limits,
      TC.OutgoingContext.set(TC.OutgoingContext.with_state(operation, TC.IncomingContext.state(received)), key, value),
      reused()))))

# A request this service only relays: a later version, every flag bit set and
# a field this package does not know.
def relayed() -> List<&2, TC.Header>:
  [TC.Header{"traceparent", "cc-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-ff-future"},
    TC.Header{"tracestate", "congo=t61rcWkgMzE"},
    TC.Header{"tracestate", "rojo=00f067aa0ba902b7"}]

# Forward the relayed request's context unchanged into the next request.
def relay(+limits: TC.Limits) -> IO(Unit):
  do IO<Unit>:
    received : TC.IncomingContext <- incoming(limits, relayed())
    forwarded : List<&2, TC.Header> <- need(List<&2, TC.Header>, TC.ForwardError, "forwarding",
      TC.Context.forward(limits, received, [TC.Header{"Host", "billing.internal"}]))
    IO.print("relayed: " ++ fields(forwarded))

# A received state of 600 octets, over the default output budget of 512:
# entries of 256, 256 and 86 octets.
def large() -> String:
  "a=" ++ String.repeat("x", 254n) ++ ",b=" ++ String.repeat("y", 254n) ++ ",c=" ++ String.repeat("z", 84n)

# Why forwarding refused a pair.
def refusal(result: Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>) -> String:
  match result:
    case Fail{error}:
      TC.ForwardError.show(error)
    case Done{carrier}:
      "nothing: it was forwarded"

# The traceparent value a carrier sends.
def traceparent(carrier: List<&2, TC.Header>) -> String:
  match carrier:
    case Nil{}:
      "none"
    case Con{TC.Header{+name, value}, rest}:
      Bool.pick(String, String.eq(name, "traceparent"), value, traceparent(rest))

def continued(injection: TC.Injection) -> IO(Unit):
  match injection:
    case TC.Injection{carrier, dropped}:
      IO.print("continued instead: " ++ traceparent(carrier) ++ ", dropped " ++ keys(dropped))

# The large state cannot travel whole with the sender's traceparent, so the
# service sends it with a child of its own, truncated to the budget.
def refuse(+limits: TC.Limits) -> IO(Unit):
  do IO<Unit>:
    +received : TC.IncomingContext <- incoming(limits,
      [TC.Header{"traceparent", "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"},
        TC.Header{"tracestate", large()}])
    Unit <- IO.print("not forwarded: " ++ refusal(TC.Context.forward(limits, received, [])))
    operation : TC.LocalContext <- child(received, "b7ad6b7169203331")
    continued(TC.Context.inject(limits, TC.OutgoingContext.with_state(operation, TC.IncomingContext.state(received)),
      []))

def main() -> IO(Unit):
  +limits = TC.Limits.default()
  do IO<Unit>:
    Unit <- handle(limits)
    Unit <- relay(limits)
    Unit <- IO.print("without context: " ++ fields(TC.Context.clear([TC.Header{"Host", "metrics.internal"},
      TC.Header{"traceparent", "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"},
      TC.Header{"Tracestate", "stale=1"}])))
    refuse(limits)
