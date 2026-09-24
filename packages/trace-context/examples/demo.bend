import Base
import ../trace_context.bend as TC

def show(result: Result<&2, &2, TC.Error, TC.TraceParentV00>) -> IO(Unit):
  match result:
    case Fail{error}:
      IO.die(Unit, 1, TC.Error.show(error))
    case Done{+context}:
      do IO<Unit>:
        Unit <- IO.print(TC.TraceParentV00.format(context))
        IO.print("sampled: " ++ Bool.show(TC.TraceParentV00.is_sampled(context)))

def main() -> IO(Unit):
  show(TC.TraceParentV00.parse(
    "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"))
