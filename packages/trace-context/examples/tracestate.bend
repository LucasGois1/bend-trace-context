import Base
import ../trace_context.bend as TC

# Read the tracestate fields of a received request with the default limits,
# look up this vendor's entry and print the state's normalized value. The
# second field repeats the congo key, so its value is dropped. A real service
# reads tracestate only after accepting the request's traceparent.
def lookup(state: TC.TraceState, key: Result<&2, &2, TC.EntryError, TC.StateKey>) -> IO(Unit):
  match key:
    case Fail{error}:
      IO.die(Unit, 1, "invalid key: " ++ TC.EntryError.show(error))
    case Done{found}:
      IO.print("congo: " ++ Maybe.default(&2, String,
        Maybe.map(&2, TC.StateValue, String, value => TC.StateValue.to_string(value), TC.TraceState.get(state, found)),
        "absent"))

def show(result: Result<&2, &2, TC.StateError, TC.TraceState>) -> IO(Unit):
  match result:
    case Fail{error}:
      IO.print("discarded: " ++ TC.StateError.show(error))
    case Done{+state}:
      do IO<Unit>:
        Unit <- IO.print("tracestate: " ++ TC.TraceState.format(state))
        lookup(state, TC.StateKey.parse("congo"))

def main() -> IO(Unit):
  +limits = TC.Limits.default()
  do IO<Unit>:
    Unit <- show(TC.TraceState.parse_fields(limits, ["congo=t61rcWkgMzE, rojo=00f067aa0ba902b7", "congo=stale"]))
    show(TC.TraceState.parse(limits, "congo=t61rcWkgMzE,Rojo=1"))
