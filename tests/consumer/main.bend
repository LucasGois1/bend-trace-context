import Base
import ./deps/bend-trace-context/packages/trace-context/trace_context.bend as TC
import ./deps/bend-trace-context/packages/trace-context/generation.bend as Generate

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

# The application's IDs come from its own system; invalid ones stop the program.
def valid(-A: Data, what: String, result: Result<&2, &2, TC.Error, A>) -> IO(A):
  match result:
    case Fail{error}:
      IO.die(A, 1, "invalid " ++ what ++ ": " ++ TC.Error.show(error))
    case Done{value}:
      IO.pure(A, value)

def trace_id(text: String) -> IO(TC.TraceId):
  valid(TC.TraceId, "trace ID", TC.TraceId.parse(text))

def span_id(text: String) -> IO(TC.SpanId):
  valid(TC.SpanId, "span ID", TC.SpanId.parse(text))

# A strictly parsed v00 value received from another service.
def received(text: String) -> IO(TC.RemoteContext):
  do IO<TC.RemoteContext>:
    traceparent : TC.TraceParentV00 <- valid(TC.TraceParentV00, "traceparent", TC.TraceParentV00.parse(text))
    return TC.RemoteContext.from_traceparent(traceparent)

def emit(label: String, context: TC.LocalContext) -> IO(Unit):
  IO.print(label ++ ": " ++ TC.TraceParentV00.format(TC.LocalContext.to_traceparent(context)))

def created(+label: String, result: Result<&2, &2, TC.ContextError, TC.LocalContext>) -> IO(TC.LocalContext):
  match result:
    case Fail{error}:
      IO.die(TC.LocalContext, 1, label ++ ": " ++ TC.ContextError.show(error))
    case Done{+context}:
      do IO<TC.LocalContext>:
        Unit <- emit(label, context)
        return context

def refused(label: String, result: Result<&2, &2, TC.ContextError, TC.LocalContext>) -> IO(Unit):
  match result:
    case Done{_}:
      IO.die(Unit, 1, "FAIL: accepted " ++ label)
    case Fail{error}:
      IO.print(label ++ " rejected: " ++ TC.ContextError.show(error))

def refused_span(result: Result<&2, &2, TC.Error, TC.SpanId>) -> IO(Unit):
  match result:
    case Done{_}:
      IO.die(Unit, 1, "FAIL: accepted an all-zero span ID")
    case Fail{error}:
      IO.print("supplied span rejected: " ++ TC.Error.show(error))

# Receive a request, handle it in a server operation, call other services from
# child operations, and restart instead where the received trace is not continued.
def lifecycle() -> IO(Unit):
  do IO<Unit>:
    +incoming : TC.RemoteContext <- received("00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01")
    server_span : TC.SpanId <- span_id("00f067aa0ba902b7")
    +server : TC.LocalContext <- created("server",
      TC.Context.child_from_id(TC.RemoteParent{incoming}, server_span, TC.InheritSampled{}))
    client_span : TC.SpanId <- span_id("53995c3f42cd8ad8")
    client : TC.LocalContext <- created("client",
      TC.Context.child_from_id(TC.LocalParent{server}, client_span, TC.InheritSampled{}))
    audit_span : TC.SpanId <- span_id("a3ce929d0e0e4736")
    audit : TC.LocalContext <- created("unsampled client",
      TC.Context.child_from_id(TC.LocalParent{server}, audit_span, TC.SetSampled{False{}}))
    Unit <- refused("reused span",
      TC.Context.child_from_id(TC.LocalParent{server}, TC.LocalContext.span_id(server), TC.InheritSampled{}))
    fresh : TC.TraceId <- trace_id("4bf92f3577b34da6a3ce929d0e0e4736")
    restart_span : TC.SpanId <- span_id("b9c7c989f97918e1")
    restarted : TC.LocalContext <- created("restart",
      TC.Context.restart_from_ids(incoming, TC.TraceId.assert_random(fresh), restart_span))
    root_trace : TC.TraceId <- trace_id("5b8efff798038103d269b633813fc60c")
    root_span : TC.SpanId <- span_id("eee19b7ec3c1b174")
    Unit <- emit("root", TC.Context.root_from_ids(root_trace, root_span))
    existing_trace : TC.TraceId <- trace_id("5b8efff798038103d269b633813fc60c")
    existing_span : TC.SpanId <- span_id("2f1c8a36d5e97b40")
    Unit <- emit("existing sampled operation", TC.Context.from_ids(existing_trace, existing_span, True{}))
    refused_span(TC.SpanId.parse("0000000000000000"))

# Generated identifiers come from the host's cryptographic source, so only
# their properties are printed; a replayed tape shows exact values.
def generated(label: String, result: Result<&2, &2, TC.GenerationError, TC.LocalContext>) -> IO(TC.LocalContext):
  match result:
    case Fail{error}:
      IO.die(TC.LocalContext, 1, label ++ ": " ++ TC.GenerationError.show(error))
    case Done{context}:
      IO.pure(TC.LocalContext, context)

def emitted_flags(context: TC.LocalContext) -> String:
  String.drop(TC.TraceParentV00.format(TC.LocalContext.to_traceparent(context)), 53n)

def replayed.show(result: Result<&2, &2, TC.GenerationError, TC.LocalContext>) -> IO(Unit):
  match result:
    case Fail{error}:
      IO.die(Unit, 1, "replayed root: " ++ TC.GenerationError.show(error))
    case Done{context}:
      emit("replayed root", context)

def replayed(outcome: List<&1, Result<&1, &1, U32 & String, U32>> & Result<&2, &2, TC.GenerationError, TC.LocalContext>) ->
  IO(Unit):
  (rest, result) = outcome
  replayed.show(result)

def generation() -> IO(Unit):
  do IO<Unit>:
    root_result : Result<&2, &2, TC.GenerationError, TC.LocalContext> <- Generate.Context.root()
    +root : TC.LocalContext <- generated("generated root", root_result)
    Unit <- IO.print("generated root flags: " ++ emitted_flags(root))
    child_result : Result<&2, &2, TC.GenerationError, TC.LocalContext> <-
      Generate.Context.child(TC.LocalParent{root}, TC.InheritSampled{})
    +child : TC.LocalContext <- generated("generated child", child_result)
    Unit <- IO.print("generated child keeps the trace: " ++
      Bool.show(TC.TraceId.is_eq(TC.LocalContext.trace_id(child), TC.LocalContext.trace_id(root))))
    Unit <- IO.print("generated child has its own span: " ++
      Bool.show(Bool.not(TC.SpanId.is_eq(TC.LocalContext.span_id(child), TC.LocalContext.span_id(root)))))
    outcome : List<&1, Result<&1, &1, U32 & String, U32>> & Result<&2, &2, TC.GenerationError, TC.LocalContext> <-
      TC.Context.root_with(~List<&1, Result<&1, &1, U32 & String, U32>>, ~TC.Source.tape,
        [Done{183985433}, Done{382551005}, Done{2219371297}, Done{478163356}, Done{3081595761}, Done{1763717937}])
    replayed(outcome)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- show(TC.TraceParentV00.parse(
      "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"))
    Unit <- reject(TC.TraceParentV00.parse(
      "00-00000000000000000000000000000000-b7ad6b7169203331-01"))
    Unit <- lifecycle()
    generation()
