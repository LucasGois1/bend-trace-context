import Base
import ./deps/bend-trace-context/packages/trace-context/trace_context.bend as TC
import ./deps/bend-trace-context/packages/trace-context/generation.bend as Generate
import ./deps/bend-trace-context/packages/trace-context/native_http.bend as NativeHttp

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

# Provider state received in two tracestate fields, read with the package's
# default limits and with a smaller configured budget.
def state(label: String, result: Result<&2, &2, TC.StateError, TC.TraceState>) -> IO(TC.TraceState):
  match result:
    case Fail{error}:
      IO.die(TC.TraceState, 1, label ++ ": " ++ TC.StateError.show(error))
    case Done{parsed}:
      IO.pure(TC.TraceState, parsed)

def discarded(label: String, result: Result<&2, &2, TC.StateError, TC.TraceState>) -> IO(Unit):
  match result:
    case Done{_}:
      IO.die(Unit, 1, "FAIL: accepted " ++ label)
    case Fail{error}:
      IO.print(label ++ " discarded: " ++ TC.StateError.show(error))

def entry_value(found: Maybe<&2, TC.StateValue>) -> String:
  match found:
    case None{}:
      "absent"
    case Some{value}:
      "\"" ++ TC.StateValue.to_string(value) ++ "\""

def lookup.key(state: TC.TraceState, result: Result<&2, &2, TC.EntryError, TC.StateKey>) -> IO(Unit):
  match result:
    case Fail{error}:
      IO.die(Unit, 1, "invalid state key: " ++ TC.EntryError.show(error))
    case Done{+key}:
      IO.print(TC.StateKey.to_string(key) ++ ": " ++ entry_value(TC.TraceState.get(state, key)))

# The application's own key is validated once, like its IDs.
def lookup(state: TC.TraceState, text: String) -> IO(Unit):
  lookup.key(state, TC.StateKey.parse(text))

def limits(result: Result<&2, &2, TC.LimitsError, TC.Limits>) -> IO(TC.Limits):
  match result:
    case Fail{error}:
      IO.die(TC.Limits, 1, "limits: " ++ TC.LimitsError.show(error))
    case Done{configured}:
      IO.pure(TC.Limits, configured)

def refused_limits(result: Result<&2, &2, TC.LimitsError, TC.Limits>) -> IO(Unit):
  match result:
    case Done{_}:
      IO.die(Unit, 1, "FAIL: accepted a 54-octet traceparent budget")
    case Fail{error}:
      IO.print("limits refused: " ++ TC.LimitsError.show(error))

def tracestate() -> IO(Unit):
  do IO<Unit>:
    +received : TC.TraceState <- state("received state", TC.TraceState.parse_fields(TC.Limits.default(),
      ["rojo=00f067aa0ba902b7,congo=t61rcWkgMzE", " congo=later ,, vendor@system= opaque value  "]))
    Unit <- IO.print("received state: " ++ TC.TraceState.format(received))
    Unit <- IO.print("entries: " ++ Nat.show(List.length(&2, TC.StateEntry, TC.TraceState.entries(received))))
    Unit <- lookup(received, "congo")
    Unit <- lookup(received, "vendor@system")
    Unit <- lookup(received, "absent")
    Unit <- discarded("state without a value", TC.TraceState.parse(TC.Limits.default(), "rojo=1,rojo"))
    +small : TC.Limits <- limits(TC.Limits.new(55n, 512n, 512n))
    Unit <- discarded("513-octet state", TC.TraceState.parse(small, "rojo=1" ++ String.repeat(" ", 507n)))
    refused_limits(TC.Limits.new(54n, 512n, 512n))

# The state a local operation sends: its own entry goes first, and the
# emitted value fits the output budget. The edited state goes with a child of
# the received context, never with the received traceparent unchanged.
def entry(what: String, result: Result<&2, &2, TC.EntryError, TC.StateKey>) -> IO(TC.StateKey):
  match result:
    case Fail{error}:
      IO.die(TC.StateKey, 1, what ++ ": " ++ TC.EntryError.show(error))
    case Done{key}:
      IO.pure(TC.StateKey, key)

def entry_text(result: Result<&2, &2, TC.EntryError, TC.StateValue>) -> IO(TC.StateValue):
  match result:
    case Fail{error}:
      IO.die(TC.StateValue, 1, "state value: " ++ TC.EntryError.show(error))
    case Done{value}:
      IO.pure(TC.StateValue, value)

def dropped.rest(keys: List<&2, TC.StateKey>) -> String:
  match keys:
    case Nil{}:
      ""
    case Con{key, rest}:
      "," ++ TC.StateKey.to_string(key) ++ dropped.rest(rest)

def dropped(keys: List<&2, TC.StateKey>) -> String:
  match keys:
    case Nil{}:
      "none"
    case Con{key, rest}:
      TC.StateKey.to_string(key) ++ dropped.rest(rest)

def local(result: Result<&2, &2, TC.ContextError, TC.LocalContext>) -> IO(TC.LocalContext):
  match result:
    case Fail{error}:
      IO.die(TC.LocalContext, 1, "local context: " ++ TC.ContextError.show(error))
    case Done{context}:
      IO.pure(TC.LocalContext, context)

def outgoing.show(+limits: TC.Limits, +outgoing: TC.OutgoingContext, rojo: TC.StateKey) -> IO(Unit):
  +emission = TC.OutgoingContext.emit(limits, outgoing)
  do IO<Unit>:
    Unit <- IO.print("outgoing: " ++ TC.Emission.traceparent(emission))
    Unit <- IO.print("outgoing state: " ++ TC.Emission.tracestate(emission))
    IO.print("without rojo: " ++ TC.Emission.tracestate(TC.OutgoingContext.emit(limits, TC.OutgoingContext.remove(outgoing, rojo))))

def outgoing() -> IO(Unit):
  +limits = TC.Limits.default()
  do IO<Unit>:
    parent : TC.RemoteContext <- received("00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01")
    span : TC.SpanId <- span_id("53995c3f42cd8ad8")
    +child : TC.LocalContext <- local(TC.Context.child_from_id(TC.RemoteParent{parent}, span, TC.InheritSampled{}))
    fixture : TC.TraceState <- state("outgoing fixture",
      TC.TraceState.parse(limits, "rojo=00f067aa0ba902b7,congo=t61rcWkgMzE"))
    +own : TC.StateKey <- entry("own key", TC.StateKey.parse("fw529a3039"))
    +value : TC.StateValue <- entry_text(TC.StateValue.parse("cHJpbWFyeQ"))
    rojo : TC.StateKey <- entry("rojo key", TC.StateKey.parse("rojo"))
    Unit <- outgoing.show(limits, TC.OutgoingContext.set(TC.OutgoingContext.with_state(child, fixture), own, value), rojo)
    large : TC.TraceState <- state("large fixture", TC.TraceState.parse(limits,
      "a=" ++ String.repeat("x", 256n) ++ ",b=" ++ String.repeat("x", 256n) ++ ",c=" ++ String.repeat("x", 256n)))
    IO.print("large state dropped: " ++ dropped(TC.Emission.dropped(TC.OutgoingContext.emit(limits,
      TC.OutgoingContext.set(TC.OutgoingContext.with_state(child, large), own, value)))))

# A received request's context, extracted from its fields as the host hands
# them over: names in any case and the tracestate in two fields. The service
# continues it with a child; a request it cannot continue keeps the context
# the service already had.
def incoming(-A: Data, what: String, value: Maybe<&2, A>) -> IO(A):
  match value:
    case None{}:
      IO.die(A, 1, "no " ++ what)
    case Some{found}:
      IO.pure(A, found)

def forwardable(received: Maybe<&2, TC.ReceivedPair>) -> String:
  match received:
    case None{}:
      "none"
    case Some{pair}:
      TC.ReceivedPair.traceparent(pair)

def extracted(+incoming: TC.IncomingContext) -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.print("extracted parent: " ++ TC.SpanId.to_string(TC.RemoteContext.span_id(TC.IncomingContext.context(incoming))) ++
      " sampled: " ++ Bool.show(TC.RemoteContext.is_sampled(TC.IncomingContext.context(incoming))))
    Unit <- IO.print("extracted state: " ++ TC.TraceState.format(TC.IncomingContext.state(incoming)))
    Unit <- IO.print("forwardable traceparent: " ++ forwardable(TC.IncomingContext.received(incoming)))
    span : TC.SpanId <- span_id("53995c3f42cd8ad8")
    child : TC.LocalContext <- local(TC.Context.child_from_id(TC.IncomingContext.parent(incoming), span,
      TC.InheritSampled{}))
    emit("extracted child", child)

def kept(context: Maybe<&2, TC.BaseContext>) -> String:
  match context:
    case Some{TC.OutgoingBase{outgoing}}:
      TC.TraceParentV00.format(TC.LocalContext.to_traceparent(TC.OutgoingContext.context(outgoing)))
    case _:
      "another context"

def extraction() -> IO(Unit):
  +limits = TC.Limits.default()
  +extraction = TC.Context.extract(limits, [TC.Header{"Accept", "application/json"},
    TC.Header{"TraceParent", "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"},
    TC.Header{"TRACESTATE", "rojo=00f067aa0ba902b7"}, TC.Header{"tracestate", "congo=t61rcWkgMzE"}], None{})
  do IO<Unit>:
    Unit <- IO.print("extracted: " ++ TC.Extraction.show(extraction))
    +found : TC.IncomingContext <- incoming(TC.IncomingContext, "incoming context", TC.Extraction.incoming(extraction))
    Unit <- extracted(found)
    Unit <- IO.print("repeated traceparent: " ++ TC.Extraction.show(TC.Context.extract(limits,
      [TC.Header{"traceparent", "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"},
        TC.Header{"Traceparent", "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"}], None{})))
    Unit <- IO.print("discarded state: " ++ TC.Extraction.show(TC.Context.extract(limits,
      [TC.Header{"traceparent", "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"},
        TC.Header{"tracestate", "rojo"}], None{})))
    base_trace : TC.TraceId <- trace_id("5b8efff798038103d269b633813fc60c")
    base_span : TC.SpanId <- span_id("eee19b7ec3c1b174")
    IO.print("kept base: " ++ kept(TC.Extraction.context(TC.Context.extract(limits,
      [TC.Header{"traceparent", "ff-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"}],
      Some{TC.OutgoingBase{TC.OutgoingContext.new(TC.Context.root_from_ids(base_trace, base_span))}}))))

# The service's outgoing requests: it forwards unchanged the context of a
# request it only relays, a later version with every flag bit set and a field
# the package does not read; it continues that trace with a child and injects
# it into a request container it reuses, whose old context fields go whatever
# the case of their names; it clears the context of a message sent without
# one; and it learns why a context whose state was discarded is not
# forwarded.
def field(header: TC.Header) -> String:
  match header:
    case TC.Header{name, value}:
      name ++ ": " ++ value

def carrier.rest(fields: List<&2, TC.Header>) -> String:
  match fields:
    case Nil{}:
      ""
    case Con{header, rest}:
      " | " ++ field(header) ++ carrier.rest(rest)

def carrier(fields: List<&2, TC.Header>) -> String:
  match fields:
    case Nil{}:
      "no fields"
    case Con{header, rest}:
      field(header) ++ carrier.rest(rest)

def forwarded(result: Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>) -> String:
  match result:
    case Fail{error}:
      "refused: " ++ TC.ForwardError.show(error)
    case Done{fields}:
      carrier(fields)

def injected(injection: TC.Injection) -> IO(Unit):
  match injection:
    case TC.Injection{fields, keys}:
      do IO<Unit>:
        Unit <- IO.print("injected: " ++ carrier(fields))
        IO.print("injection dropped: " ++ dropped(keys))

def injection() -> IO(Unit):
  +limits = TC.Limits.default()
  do IO<Unit>:
    +relayed : TC.IncomingContext <- incoming(TC.IncomingContext, "relayed context", TC.Extraction.incoming(
      TC.Context.extract(limits, [TC.Header{"traceparent",
        "fe-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-ff-extension"},
        TC.Header{"tracestate", "rojo=00f067aa0ba902b7"}, TC.Header{"tracestate", "congo=t61rcWkgMzE"}], None{})))
    Unit <- IO.print("forwarded: " ++ forwarded(TC.Context.forward(limits, relayed,
      [TC.Header{"Accept", "application/json"}])))
    span : TC.SpanId <- span_id("53995c3f42cd8ad8")
    child : TC.LocalContext <- local(TC.Context.child_from_id(TC.IncomingContext.parent(relayed), span,
      TC.InheritSampled{}))
    Unit <- injected(TC.Context.inject(limits, TC.OutgoingContext.with_state(child, TC.IncomingContext.state(relayed)),
      [TC.Header{"Accept", "application/json"}, TC.Header{"TRACEPARENT", "stale"}, TC.Header{"X-Request-Id", "42"},
        TC.Header{"TraceState", "old=1"}]))
    Unit <- IO.print("cleared: " ++ carrier(TC.Context.clear([TC.Header{"Accept", "application/json"},
      TC.Header{"traceparent", "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"},
      TC.Header{"Tracestate", "rojo=00f067aa0ba902b7"}])))
    discarded : TC.IncomingContext <- incoming(TC.IncomingContext, "context with a discarded state",
      TC.Extraction.incoming(TC.Context.extract(limits,
        [TC.Header{"traceparent", "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"},
          TC.Header{"tracestate", "rojo"}], None{})))
    IO.print("discarded state forwarded: " ++ forwarded(TC.Context.forward(limits, discarded, [])))

# The service's own operation for each request it receives, and the
# requests it sends on. On the host's source, it continues a traced request
# and sends two requests on, each with a child of its own. With replayed
# words, it shows every outcome it handles: a continued request, its own
# entry put first in the state it sends, a source failure after which the
# request sent on forwards the received context unchanged, exhausted
# candidates without a context to forward, an invalid traceparent that
# continues its own base, a partner's request restarted at its trust
# boundary, and the strict policy, which refuses the request.
def received_request() -> List<&2, TC.Header>:
  [TC.Header{"traceparent", "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"},
    TC.Header{"tracestate", "rojo=00f067aa0ba902b7"}, TC.Header{"tracestate", "congo=t61rcWkgMzE"}]

def request_fields() -> List<&2, TC.Header>:
  [TC.Header{"Accept", "application/json"}]

def service_operation(outgoing: Maybe<&2, TC.OutgoingContext>) -> String:
  match outgoing:
    case None{}:
      ""
    case Some{context}:
      " " ++ TC.TraceParentV00.format(TC.LocalContext.to_traceparent(TC.OutgoingContext.context(context)))

def service_line(+service: TC.Service) -> String:
  TC.Service.show(service) ++ service_operation(TC.Service.outgoing(service))

def sent_line(+sent: TC.Sent) -> String:
  TC.Sent.show(sent) ++ " | " ++ carrier(TC.Sent.carrier(sent))

def own_operation(outgoing: Maybe<&2, TC.OutgoingContext>) -> IO(TC.LocalContext):
  match outgoing:
    case None{}:
      IO.die(TC.LocalContext, 1, "FAIL: the host service has no operation")
    case Some{context}:
      IO.pure(TC.LocalContext, TC.OutgoingContext.context(context))

def sent_operation(operation: Maybe<&2, TC.LocalContext>) -> IO(TC.LocalContext):
  match operation:
    case None{}:
      IO.die(TC.LocalContext, 1, "FAIL: a host request has no operation")
    case Some{context}:
      IO.pure(TC.LocalContext, context)

def host_send(service: TC.Service) -> IO(TC.LocalContext):
  do IO<TC.LocalContext>:
    sent : TC.Sent <- Generate.Context.send(TC.Limits.default(), service, TC.InheritSampled{}, TC.Lenient{},
      request_fields())
    sent_operation(TC.Sent.operation(sent))

def same_trace(+a: TC.LocalContext, +b: TC.LocalContext) -> Bool:
  TC.TraceId.is_eq(TC.LocalContext.trace_id(a), TC.LocalContext.trace_id(b))

def other_span(+a: TC.LocalContext, +b: TC.LocalContext) -> Bool:
  Bool.not(TC.SpanId.is_eq(TC.LocalContext.span_id(a), TC.LocalContext.span_id(b)))

def host_service() -> IO(Unit):
  do IO<Unit>:
    +service : TC.Service <- Generate.Context.continue_or_start(TC.Context.extract(TC.Limits.default(),
      received_request(), None{}), TC.Continue{}, TC.InheritSampled{}, TC.Lenient{})
    Unit <- IO.print("host service: " ++ TC.Service.show(service))
    +own : TC.LocalContext <- own_operation(TC.Service.outgoing(service))
    Unit <- IO.print("host service keeps the received trace: " ++
      Bool.show(String.eq(TC.TraceId.to_string(TC.LocalContext.trace_id(own)), "0af7651916cd43dd8448eb211c80319c")))
    +first : TC.LocalContext <- host_send(service)
    +second : TC.LocalContext <- host_send(service)
    Unit <- IO.print("host requests keep the trace: " ++
      Bool.show(Bool.and(same_trace(first, own), same_trace(second, own))))
    IO.print("host requests have their own spans: " ++
      Bool.show(Bool.and(other_span(first, own), Bool.and(other_span(second, own), other_span(first, second)))))

def Words() -> Type:
  List<&1, Result<&1, &1, U32 & String, U32>>

def zero_words(count: Nat) -> Words():
  match count:
    case 0n:
      Nil{}
    case 1n+p:
      Con{Done{0}, zero_words(p)}

def replayed_service(words: Words(), +extraction: TC.Extraction, reception: TC.Reception) -> IO(TC.Service):
  do IO<TC.Service>:
    done : Words() & TC.Service <- TC.Context.continue_or_start_with(~Words(), ~TC.Source.tape, words, extraction,
      reception, TC.InheritSampled{}, TC.Lenient{})
    return Pair.snd(Words(), TC.Service, done)

def replayed_send(words: Words(), service: TC.Service) -> IO(TC.Sent):
  do IO<TC.Sent>:
    done : Words() & TC.Sent <- TC.Context.send_with(~Words(), ~TC.Source.tape, words, TC.Limits.default(),
      service, TC.InheritSampled{}, TC.Lenient{}, request_fields())
    return Pair.snd(Words(), TC.Sent, done)

# The service a received request gives with replayed words, and the request
# it sends on.
def flow(+label: String, service_words: Words(), send_words: Words(), +extraction: TC.Extraction,
  reception: TC.Reception) -> IO(Unit):
  do IO<Unit>:
    +service : TC.Service <- replayed_service(service_words, extraction, reception)
    Unit <- IO.print(label ++ " service: " ++ service_line(service))
    sent : TC.Sent <- replayed_send(send_words, service)
    IO.print(label ++ " request: " ++ sent_line(sent))

# The service puts its own entry first in the state it sends.
def own_entry(+extraction: TC.Extraction) -> IO(Unit):
  do IO<Unit>:
    own : TC.StateKey <- entry("own key", TC.StateKey.parse("fw529a3039"))
    value : TC.StateValue <- entry_text(TC.StateValue.parse("cHJpbWFyeQ"))
    service : TC.Service <- replayed_service([Done{15755178}, Done{195625655}], extraction, TC.Continue{})
    sent : TC.Sent <- replayed_send([Done{1402559551}, Done{1120766680}], TC.Service.set(service, own, value))
    IO.print("own entry request: " ++ sent_line(sent))

def refusal(result: Result<&2, &2, TC.GenerationError, TC.Service>) -> String:
  match result:
    case Fail{error}:
      "refused after " ++ TC.GenerationError.show(error)
    case Done{service}:
      "handled: " ++ TC.Service.show(service)

def strict_service(words: Words(), +extraction: TC.Extraction) -> IO(Unit):
  do IO<Unit>:
    done : Words() & Result<&2, &2, TC.GenerationError, TC.Service> <- TC.Context.continue_or_start_with(~Words(),
      ~TC.Source.tape, words, extraction, TC.Continue{}, TC.InheritSampled{}, TC.Strict{})
    IO.print("strict service: " ++ refusal(Pair.snd(Words(), Result<&2, &2, TC.GenerationError, TC.Service>, done)))

# A bend-kit header map through the native HTTP adapter: the received
# request's context is continued, and the request sent on gets a child in
# place of a reused container's old context fields.
def http_joined.rest(values: List<&2, String>) -> String:
  match values:
    case Nil{}:
      ""
    case Con{value, rest}:
      "," ++ value ++ http_joined.rest(rest)

def http_joined(values: List<&2, String>) -> String:
  match values:
    case Nil{}:
      "none"
    case Con{value, rest}:
      value ++ http_joined.rest(rest)

# The values a header map holds under `name`, joined by commas.
def http_values(+headers: Map<&2, List<&2, String>>, name: String) -> String:
  http_joined(Pair.snd(Map<&2, List<&2, String>>, List<&2, String>, Map.get(List<&2, String>, Nil{}, headers, name)))

def http_request(outbound: NativeHttp.Outbound) -> String:
  match outbound:
    case NativeHttp.Outbound{sent, +headers}:
      TC.Sent.show(sent) ++ " | traceparent " ++ http_values(headers, "traceparent") ++ " | tracestate " ++
        http_values(headers, "tracestate") ++ " | TraceParent " ++ http_values(headers, "TraceParent") ++
        " | accept " ++ http_values(headers, "accept")

def http_adapter() -> IO(Unit):
  +limits = TC.Limits.default()
  +received = Map.set(&2, List<&2, String>, Map.set(&2, List<&2, String>, Map.new(&2, List<&2, String>),
    "traceparent", ["00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"]), "tracestate",
    ["rojo=00f067aa0ba902b7", "congo=t61rcWkgMzE"])
  do IO<Unit>:
    served : Words() & TC.Service <- NativeHttp.continue_or_start_with(~Words(), ~TC.Source.tape,
      [Done{15755178}, Done{195625655}], limits, received, None{}, TC.Continue{}, TC.InheritSampled{}, TC.Lenient{})
    +service : TC.Service = Pair.snd(Words(), TC.Service, served)
    Unit <- IO.print("http service: " ++ service_line(service))
    sent : Words() & NativeHttp.Outbound <- NativeHttp.send_with(~Words(), ~TC.Source.tape,
      [Done{1402559551}, Done{1120766680}], limits, service, TC.InheritSampled{}, TC.Lenient{},
      Map.set(&2, List<&2, String>, Map.set(&2, List<&2, String>, Map.new(&2, List<&2, String>), "TraceParent",
        ["00-5b8efff798038103d269b633813fc60c-eee19b7ec3c1b174-01"]), "accept", ["application/json"]))
    IO.print("http request: " ++ http_request(Pair.snd(Words(), NativeHttp.Outbound, sent)))

def continuation() -> IO(Unit):
  +limits = TC.Limits.default()
  do IO<Unit>:
    Unit <- host_service()
    Unit <- flow("continued", [Done{15755178}, Done{195625655}], [Done{1402559551}, Done{1120766680}],
      TC.Context.extract(limits, received_request(), None{}), TC.Continue{})
    Unit <- own_entry(TC.Context.extract(limits, received_request(), None{}))
    Unit <- flow("source failure", [Fail{(3, "no entropy")}], [], TC.Context.extract(limits, received_request(),
      None{}), TC.Continue{})
    Unit <- flow("exhausted", zero_words(32n), [], TC.Context.extract(limits, request_fields(), None{}),
      TC.Continue{})
    base_trace : TC.TraceId <- trace_id("5b8efff798038103d269b633813fc60c")
    base_span : TC.SpanId <- span_id("eee19b7ec3c1b174")
    +base : TC.BaseContext = TC.OutgoingBase{TC.OutgoingContext.new(TC.Context.root_from_ids(base_trace, base_span))}
    Unit <- flow("invalid traceparent", [Done{15755178}, Done{195625655}], [Done{1402559551}, Done{1120766680}],
      TC.Context.extract(limits, [TC.Header{"traceparent", "00-00000000000000000000000000000000-b7ad6b7169203331-01"}],
        Some{base}), TC.Continue{})
    Unit <- flow("boundary", [Done{1274621749}, Done{2008239526}, Done{2748224157}, Done{235816758},
      Done{15755178}, Done{195625655}], [Done{1402559551}, Done{1120766680}],
      TC.Context.extract(limits, received_request(), Some{base}), TC.Restart{})
    strict_service([Fail{(3, "no entropy")}], TC.Context.extract(limits, received_request(), None{}))

# An OpenTelemetry SDK's remote span context from its parts, as a link or a
# propagator of another format gives them: a remote context from its IDs and
# sampled indication, whose random-trace-id bit is its trace ID's own
# assertion, and an incoming context from it and a tracestate. Built from
# parts, the incoming context keeps no received pair, so forwarding refuses
# it and writes nothing, and the SDK's pass-through clears the stale context
# fields of the message it sends instead.
def sdk_parts.remote(+context: TC.RemoteContext) -> String:
  TC.TraceId.to_string(TC.RemoteContext.trace_id(context)) ++ " " ++
    TC.SpanId.to_string(TC.RemoteContext.span_id(context)) ++ " sampled: " ++
    Bool.show(TC.RemoteContext.is_sampled(context)) ++ " random: " ++
    Bool.show(TC.TraceId.is_random(TC.RemoteContext.trace_id(context)))

def sdk_parts() -> IO(Unit):
  +limits = TC.Limits.default()
  do IO<Unit>:
    +trace : TC.TraceId <- trace_id("4bf92f3577b34da6a3ce929d0e0e4736")
    +span : TC.SpanId <- span_id("00f067aa0ba902b7")
    +remote : TC.RemoteContext = TC.RemoteContext.from_ids(trace, span, True{})
    Unit <- IO.print("sdk parts: remote context: " ++ sdk_parts.remote(remote))
    Unit <- IO.print("sdk parts: remote context of a random trace ID: " ++ sdk_parts.remote(
      TC.RemoteContext.from_ids(TC.TraceId.assert_random(trace), span, False{})))
    vendor : TC.TraceState <- state("sdk parts state", TC.TraceState.parse(limits, "congo=t61rcWkgMzE"))
    +incoming : TC.IncomingContext = TC.IncomingContext.from_remote(remote, vendor)
    Unit <- IO.print("sdk parts: incoming context: " ++ sdk_parts.remote(TC.IncomingContext.context(incoming)) ++
      " state: " ++ TC.TraceState.format(TC.IncomingContext.state(incoming)) ++ " received pair: " ++
      forwardable(TC.IncomingContext.received(incoming)))
    +message : List<&2, TC.Header> = [TC.Header{"Accept", "application/json"},
      TC.Header{"TraceParent", "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"},
      TC.Header{"X-Request-Id", "42"}, TC.Header{"tracestate", "rojo=00f067aa0ba902b7"}]
    Unit <- IO.print("sdk parts: forwarded: " ++ forwarded(TC.Context.forward(limits, incoming, message)))
    IO.print("sdk parts: cleared: " ++ carrier(TC.Context.clear(message)))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- show(TC.TraceParentV00.parse(
      "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"))
    Unit <- reject(TC.TraceParentV00.parse(
      "00-00000000000000000000000000000000-b7ad6b7169203331-01"))
    Unit <- lifecycle()
    Unit <- generation()
    Unit <- tracestate()
    Unit <- outgoing()
    Unit <- extraction()
    Unit <- injection()
    Unit <- continuation()
    Unit <- sdk_parts()
    http_adapter()
