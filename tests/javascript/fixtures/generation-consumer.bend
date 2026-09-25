import Base
import ../../../packages/trace-context/trace_context.bend as TC
import ../../../packages/trace-context/generation.bend as Generate

def describe(result: Result<&2, &2, TC.GenerationError, TC.LocalContext>) -> String:
  match result:
    case Done{context}:
      "created:" ++ TC.TraceParentV00.format(TC.LocalContext.to_traceparent(context))
    case Fail{error}:
      "fail:" ++ TC.GenerationError.show(error)

def main() -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, TC.GenerationError, TC.LocalContext> <- Generate.Context.root()
    IO.print(describe(result))
