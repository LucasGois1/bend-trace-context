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

# A trace ID and a span ID generated alone on the real source, as an
# OpenTelemetry SDK generates them: each avoids the identifier it excludes,
# and the trace ID asserts random-trace-id.
def Smoke.alone(+root: TC.LocalContext, +trace_id: TC.TraceId, +span_id: TC.SpanId) -> IO(Unit):
  do IO<Unit>:
    Unit <- Smoke.assert("a trace ID generated alone has 32 digits",
      Nat.is_eq(String.length(TC.TraceId.to_string(trace_id)), 32n))
    Unit <- Smoke.assert("a trace ID generated alone asserts random-trace-id", TC.TraceId.is_random(trace_id))
    Unit <- Smoke.assert("a trace ID generated alone avoids the one it excludes",
      Bool.not(TC.TraceId.is_eq(trace_id, TC.LocalContext.trace_id(root))))
    Unit <- Smoke.assert("a span ID generated alone has 16 digits",
      Nat.is_eq(String.length(TC.SpanId.to_string(span_id)), 16n))
    Smoke.assert("a span ID generated alone avoids the one it excludes",
      Bool.not(TC.SpanId.is_eq(span_id, TC.LocalContext.span_id(root))))

def Smoke.operation(+name: String, context: Maybe<&2, TC.LocalContext>) -> IO(TC.LocalContext):
  match context:
    case None{}:
      IO.die(TC.LocalContext, 1, "FAIL: " ++ name ++ " has no operation")
    case Some{operation}:
      IO.pure(TC.LocalContext, operation)

def Smoke.service_operation(outgoing: Maybe<&2, TC.OutgoingContext>) -> Maybe<&2, TC.LocalContext>:
  match outgoing:
    case None{}:
      None{}
    case Some{context}:
      Some{TC.OutgoingContext.context(context)}

# A service continuing a received request, and the request it sends on, on
# the real source: the same trace, and an operation of their own each.
def Smoke.served(+received: TC.RemoteContext, +service: TC.LocalContext, +sent: TC.LocalContext) -> IO(Unit):
  do IO<Unit>:
    Unit <- Smoke.assert("a continued service keeps the received trace ID",
      TC.TraceId.is_eq(TC.LocalContext.trace_id(service), TC.RemoteContext.trace_id(received)))
    Unit <- Smoke.assert("a continued service has its own span ID",
      Bool.not(TC.SpanId.is_eq(TC.LocalContext.span_id(service), TC.RemoteContext.span_id(received))))
    Unit <- Smoke.assert("a sent operation keeps the trace ID",
      TC.TraceId.is_eq(TC.LocalContext.trace_id(sent), TC.LocalContext.trace_id(service)))
    Smoke.assert("a sent operation has its own span ID",
      Bool.not(TC.SpanId.is_eq(TC.LocalContext.span_id(sent), TC.LocalContext.span_id(service))))

def Smoke.flow(+received: TC.RemoteContext) -> IO(Unit):
  do IO<Unit>:
    +service : TC.Service <- Generate.Context.continue_or_start(TC.Context.extract(TC.Limits.default(),
      [TC.Header{"traceparent", "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"}], None{}), TC.Continue{},
      TC.InheritSampled{}, TC.Lenient{})
    operation : TC.LocalContext <- Smoke.operation("the service", Smoke.service_operation(TC.Service.outgoing(service)))
    sent_on : TC.Sent <- Generate.Context.send(TC.Limits.default(), service, TC.InheritSampled{}, TC.Lenient{}, [])
    sent : TC.LocalContext <- Smoke.operation("the outgoing request", TC.Sent.operation(sent_on))
    Smoke.served(received, operation, sent)

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
    Unit <- IO.print("OK: real-source root, child and restart are well formed")
    trace_result : Result<&2, &2, TC.GenerationError, TC.TraceId> <-
      Generate.TraceId.generate(Some{TC.LocalContext.trace_id(root)})
    trace_id : TC.TraceId <- Smoke.valid(TC.TraceId, "trace ID", trace_result)
    span_result : Result<&2, &2, TC.GenerationError, TC.SpanId> <-
      Generate.SpanId.generate(Some{TC.LocalContext.span_id(root)})
    span_id : TC.SpanId <- Smoke.valid(TC.SpanId, "span ID", span_result)
    Unit <- Smoke.alone(root, trace_id, span_id)
    Unit <- IO.print("OK: real-source trace IDs and span IDs generated alone are well formed")
    Unit <- Smoke.flow(incoming)
    IO.print("OK: real-source continue-or-start and send are well formed")
