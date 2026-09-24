import Base
import ./deps/bend-trace-context/packages/trace-context/trace_context.bend as TC

# Independent W3C example; this file belongs to the application, not the package.
def show(result: Result<&2, &2, TC.Error, TC.TraceParentV00>) -> IO(Unit):
  match result:
    case Fail{error}:
      IO.die(Unit, 1, TC.Error.show(error))
    case Done{+context}:
      do IO<Unit>:
        Unit <- IO.print(TC.TraceParentV00.format(context))
        IO.print("sampled: " ++ Bool.show(TC.TraceParentV00.is_sampled(context)))

def reject(result: Result<&2, &2, TC.Error, TC.TraceParentV00>) -> IO(Unit):
  match result:
    case Done{_}:
      IO.die(Unit, 1, "FAIL: accepted an all-zero trace ID")
    case Fail{error}:
      IO.print("rejected: " ++ TC.Error.show(error))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- show(TC.TraceParentV00.parse(
      "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"))
    reject(TC.TraceParentV00.parse(
      "00-00000000000000000000000000000000-b7ad6b7169203331-01"))
