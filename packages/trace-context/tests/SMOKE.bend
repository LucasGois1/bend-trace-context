import Base
import ../trace_context.bend as TC
import ../generation.bend as Generate

# Real-source smoke checks. They show that the host source is reachable and
# that generated contexts are well formed; they are not evidence of
# cryptographic strength or of global uniqueness.
def Smoke.assert(name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "FAIL: " ++ name)

def Smoke.valid(-A: Data, name: String, result: Result<&2, &2, TC.GenerationError, A>) -> IO(A):
  match result:
    case Fail{error}:
      IO.die(A, 1, "FAIL: " ++ name ++ ": " ++ TC.GenerationError.show(error))
    case Done{value}:
      IO.pure(A, value)

def Smoke.text(context: TC.LocalContext) -> String:
  TC.TraceParentV00.format(TC.LocalContext.to_traceparent(context))

def Smoke.flags(text: String) -> String:
  String.drop(text, 53n)

def Smoke.received(result: Result<&2, &2, TC.Error, TC.TraceParentV00>) -> IO(TC.RemoteContext):
  match result:
    case Fail{error}:
      IO.die(TC.RemoteContext, 1, "FAIL: traceparent fixture: " ++ TC.Error.show(error))
    case Done{traceparent}:
      IO.pure(TC.RemoteContext, TC.RemoteContext.from_traceparent(traceparent))

def Smoke.root(+root: TC.LocalContext) -> IO(Unit):
  do IO<Unit>:
    Unit <- Smoke.assert("a generated root has 55 characters", Nat.is_eq(String.length(Smoke.text(root)), 55n))
    Smoke.assert("a generated root is emitted with flags 02", String.eq(Smoke.flags(Smoke.text(root)), "02"))

def Smoke.child(+root: TC.LocalContext, +child: TC.LocalContext) -> IO(Unit):
  do IO<Unit>:
    Unit <- Smoke.assert("a generated child keeps the trace ID",
      TC.TraceId.is_eq(TC.LocalContext.trace_id(child), TC.LocalContext.trace_id(root)))
    Smoke.assert("a generated child has its own span ID",
      Bool.not(TC.SpanId.is_eq(TC.LocalContext.span_id(child), TC.LocalContext.span_id(root))))

def Smoke.restart(+incoming: TC.RemoteContext, +restarted: TC.LocalContext) -> IO(Unit):
  do IO<Unit>:
    Unit <- Smoke.assert("a generated restart starts a new trace",
      Bool.not(TC.TraceId.is_eq(TC.LocalContext.trace_id(restarted), TC.RemoteContext.trace_id(incoming))))
    Smoke.assert("a generated restart is emitted with flags 02", String.eq(Smoke.flags(Smoke.text(restarted)), "02"))

def main() -> IO(Unit):
  do IO<Unit>:
    root_result : Result<&2, &2, TC.GenerationError, TC.LocalContext> <- Generate.Context.root()
    +root : TC.LocalContext <- Smoke.valid(TC.LocalContext, "root", root_result)
    Unit <- Smoke.root(root)
    child_result : Result<&2, &2, TC.GenerationError, TC.LocalContext> <-
      Generate.Context.child(TC.LocalParent{root}, TC.InheritSampled{})
    child : TC.LocalContext <- Smoke.valid(TC.LocalContext, "child", child_result)
    Unit <- Smoke.child(root, child)
    +incoming : TC.RemoteContext <- Smoke.received(TC.TraceParentV00.parse(
      "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"))
    restart_result : Result<&2, &2, TC.GenerationError, TC.LocalContext> <- Generate.Context.restart(incoming)
    restarted : TC.LocalContext <- Smoke.valid(TC.LocalContext, "restart", restart_result)
    Unit <- Smoke.restart(incoming, restarted)
    IO.print("OK: real-source root, child and restart are well formed")
