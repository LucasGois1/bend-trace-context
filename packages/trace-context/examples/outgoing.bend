import Base
import ../trace_context.bend as TC

# A service received a request with this traceparent and tracestate. It
# continues the trace with a child operation of its own, records its vendor
# entry in the state it sends, and emits both fields within the default
# 512-octet output budget.
#
# The edited state travels with the child, whose traceparent identifies the
# new operation. Sending an edited or truncated tracestate under the received
# traceparent unchanged is not allowed (W3C 3.4, spec #1). An outgoing context
# holds a local context, which a RemoteContext is not; a local context built
# with Context.from_ids must use the IDs of the caller's own operation, never
# the received ones. A received pair that is not continued is forwarded as it
# came (#10).

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

def fail(-A: Data, what: String) -> IO(A):
  IO.die(A, 1, "invalid " ++ what)

def need(-A: Data, -E: Data, what: String, result: Result<&2, &2, E, A>) -> IO(A):
  match result:
    case Fail{error}:
      fail(A, what)
    case Done{value}:
      IO.pure(A, value)

# This participant's entry goes first in the state its child sends.
def send(limits: TC.Limits, child: TC.LocalContext, state: TC.TraceState, key: TC.StateKey,
  value: TC.StateValue) -> TC.Emission:
  TC.OutgoingContext.emit(limits, TC.OutgoingContext.set(TC.OutgoingContext.with_state(child, state), key, value))

def show(emission: TC.Emission) -> IO(Unit):
  match emission:
    case TC.Emission{traceparent, tracestate, dropped}:
      do IO<Unit>:
        Unit <- IO.print("traceparent: " ++ traceparent)
        Unit <- IO.print("tracestate: " ++ tracestate)
        IO.print("dropped: " ++ keys(dropped))

# Two received entries of 258 octets: with this participant's entry, the state
# takes 557 octets, so the rightmost large entry, b, is not sent.
def show_large(+emission: TC.Emission) -> IO(Unit):
  IO.print("large state: " ++ Nat.show(String.length(TC.Emission.tracestate(emission))) ++
    " octets sent, dropped: " ++ keys(TC.Emission.dropped(emission)))

def main() -> IO(Unit):
  +limits = TC.Limits.default()
  do IO<Unit>:
    received : TC.TraceParentV00 <- need(TC.TraceParentV00, TC.Error, "traceparent",
      TC.TraceParentV00.parse("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"))
    state : TC.TraceState <- need(TC.TraceState, TC.StateError, "tracestate",
      TC.TraceState.parse(limits, "congo=t61rcWkgMzE,rojo=00f067aa0ba902b7"))
    span : TC.SpanId <- need(TC.SpanId, TC.Error, "span ID", TC.SpanId.parse("53995c3f42cd8ad8"))
    +child : TC.LocalContext <- need(TC.LocalContext, TC.ContextError, "child",
      TC.Context.child_from_id(TC.RemoteParent{TC.RemoteContext.from_traceparent(received)}, span,
        TC.InheritSampled{}))
    +key : TC.StateKey <- need(TC.StateKey, TC.EntryError, "key", TC.StateKey.parse("fw529a3039"))
    +value : TC.StateValue <- need(TC.StateValue, TC.EntryError, "value", TC.StateValue.parse("cHJpbWFyeQ"))
    Unit <- show(send(limits, child, state, key, value))
    large : TC.TraceState <- need(TC.TraceState, TC.StateError, "large tracestate",
      TC.TraceState.parse(limits, "a=" ++ String.repeat("x", 256n) ++ ",b=" ++ String.repeat("x", 256n) ++
        ",congo=t61rcWkgMzE"))
    show_large(send(limits, child, large, key, value))
