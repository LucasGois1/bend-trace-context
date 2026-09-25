import Base
import ../trace_context.bend as TC
import ../generation.bend as Generate

# Start a trace on the host's cryptographic source, then create the operation
# that calls another service. Both lines end in flags 02: the generated trace
# ID asserts random-trace-id and the child inherits the root's unsampled
# indication. Each run prints new IDs.
def emit(context: TC.LocalContext) -> IO(Unit):
  IO.print(TC.TraceParentV00.format(TC.LocalContext.to_traceparent(context)))

def call(result: Result<&2, &2, TC.GenerationError, TC.LocalContext>) -> IO(Unit):
  match result:
    case Fail{error}:
      IO.die(Unit, 1, TC.GenerationError.show(error))
    case Done{context}:
      emit(context)

def start(result: Result<&2, &2, TC.GenerationError, TC.LocalContext>) -> IO(Unit):
  match result:
    case Fail{error}:
      IO.die(Unit, 1, TC.GenerationError.show(error))
    case Done{+root}:
      do IO<Unit>:
        Unit <- emit(root)
        child : Result<&2, &2, TC.GenerationError, TC.LocalContext> <-
          Generate.Context.child(TC.LocalParent{root}, TC.InheritSampled{})
        call(child)

def main() -> IO(Unit):
  do IO<Unit>:
    root : Result<&2, &2, TC.GenerationError, TC.LocalContext> <- Generate.Context.root()
    start(root)
