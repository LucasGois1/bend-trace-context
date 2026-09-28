import Base
import ../trace_context.bend as TC
import ../native_http.bend as NativeHttp

# The native HTTP adapter through its public names, with header maps as
# bend-kit builds them: one entry per field name, lowercased by its parser,
# with the values in arrival order. Expected values are literal fixtures
# written from W3C Trace Context Level 2 and spec #1, not recomputed by
# package helpers.
def Test.assert(name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "FAIL: " ++ name)

def Test.same(name: String, +got: String, expected: String) -> IO(Unit):
  Test.assert(name ++ ", got " ++ got, String.eq(got, expected))

def Test.map() -> Map<&2, List<&2, String>>:
  Map.new(&2, List<&2, String>)

def Test.with(+map: Map<&2, List<&2, String>>, name: String, values: List<&2, String>) -> Map<&2, List<&2, String>>:
  Map.set(&2, List<&2, String>, map, name, values)

def Test.extracted(+headers: Map<&2, List<&2, String>>) -> String:
  TC.Extraction.show(TC.Context.extract(TC.Limits.default(), NativeHttp.carrier(headers), None{}))

def Test.values.rest(values: List<&2, String>) -> String:
  match values:
    case Nil{}:
      ""
    case Con{value, rest}:
      " | " ++ value ++ Test.values.rest(rest)

# Values joined by " | ", or "none".
def Test.values(values: List<&2, String>) -> String:
  match values:
    case Nil{}:
      "none"
    case Con{value, rest}:
      value ++ Test.values.rest(rest)

def Test.named.kept(same: Bool, value: String, rest: List<&2, String>) -> List<&2, String>:
  match same:
    case True{}:
      Con{value, rest}
    case False{}:
      rest

# The values of the fields named exactly `name`, in order.
def Test.named(+name: String, carrier: List<&2, TC.Header>) -> List<&2, String>:
  match carrier:
    case Nil{}:
      Nil{}
    case Con{TC.Header{+field, value}, rest}:
      Test.named.kept(String.eq(field, name), value, Test.named(name, rest))

# A received message's header map becomes a carrier with every value of every
# name, in arrival order within each name, so that extraction sees repeated
# fields as they came (spec #1, "Preserve an ordered multi-value carrier";
# W3C 3.2.1 and 3.3.1).
def Test.received() -> IO(Unit):
  +traced = Test.with(Test.with(Test.with(Test.map(), "traceparent",
    ["00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"]), "tracestate",
    ["rojo=00f067aa0ba902b7", "congo=t61rcWkgMzE"]), "content-type", ["application/json"])
  do IO<Unit>:
    Unit <- Test.same("a received request is extracted", Test.extracted(traced), "TraceParentAccepted, StateAccepted")
    Unit <- Test.same("its tracestate values keep their order",
      Test.values(Test.named("tracestate", NativeHttp.carrier(traced))), "rojo=00f067aa0ba902b7 | congo=t61rcWkgMzE")
    Unit <- Test.same("its other fields stay in the carrier",
      Test.values(Test.named("content-type", NativeHttp.carrier(traced))), "application/json")
    Unit <- Test.same("two traceparent values stay two fields", Test.extracted(Test.with(Test.map(), "traceparent",
      ["00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01",
        "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"])), "TraceParentRejected RepeatedTraceParent, StateAbsent")
    Unit <- Test.same("an empty map carries nothing", Test.values(Test.named("traceparent", NativeHttp.carrier(Test.map()))),
      "none")
    IO.print("OK: a received header map keeps every value")

# The values a map holds under `name`, as bend-kit's Http.fields reads them.
def Test.get(+map: Map<&2, List<&2, String>>, name: String) -> List<&2, String>:
  Pair.snd(Map<&2, List<&2, String>>, List<&2, String>, Map.get(List<&2, String>, Nil{}, map, name))

# A carrier becomes a header map with each value added at the end of its
# name's values, as bend-kit's Http.add does, so that repeated fields stay
# repeated and keep their order.
def Test.written() -> IO(Unit):
  +written = NativeHttp.headers([TC.Header{"accept", "application/json"}, TC.Header{"x-request-id", "42"},
    TC.Header{"accept", "text/plain"}, TC.Header{"traceparent", "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"},
    TC.Header{"tracestate", "congo=t61rcWkgMzE"}])
  do IO<Unit>:
    Unit <- Test.same("repeated values stay in order", Test.values(Test.get(written, "accept")),
      "application/json | text/plain")
    Unit <- Test.same("each other name keeps its value", Test.values(Test.get(written, "x-request-id")), "42")
    Unit <- Test.same("the traceparent is written", Test.values(Test.get(written, "traceparent")),
      "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01")
    Unit <- Test.same("the tracestate is written", Test.values(Test.get(written, "tracestate")), "congo=t61rcWkgMzE")
    Unit <- Test.same("names are kept as the carrier spells them",
      Test.values(Test.get(NativeHttp.headers([TC.Header{"X-Custom", "1"}]), "X-Custom")), "1")
    Unit <- Test.same("an empty carrier writes nothing", Test.values(Test.get(NativeHttp.headers([]), "traceparent")),
      "none")
    IO.print("OK: a carrier becomes a header map")

def Test.tape() -> Type:
  List<&1, Result<&1, &1, U32 & String, U32>>

# The words of 00f067aa0ba902b7.
def Test.other_span(tail: Test.tape()) -> Test.tape():
  Con{Done{15755178}, Con{Done{195625655}, tail}}

# The words of 53995c3f42cd8ad8.
def Test.third_span(tail: Test.tape()) -> Test.tape():
  Con{Done{1402559551}, Con{Done{1120766680}, tail}}

def Test.failing() -> Test.tape():
  [Fail{(9, "controlled")}]

# A request this service receives, as bend-kit parses it.
def Test.request() -> Map<&2, List<&2, String>>:
  Test.with(Test.with(Test.with(Test.map(), "traceparent",
    ["00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"]), "tracestate", ["rojo=00f067aa0ba902b7",
      "congo=t61rcWkgMzE"]), "host", ["api.example.com"])

# A request container the service reuses: old context fields, one of them
# spelled as an application might set it, among other fields.
def Test.reused() -> Map<&2, List<&2, String>>:
  Test.with(Test.with(Test.with(Test.map(), "TraceParent",
    ["00-5b8efff798038103d269b633813fc60c-eee19b7ec3c1b174-01"]), "tracestate", ["stale=1"]), "content-type",
    ["application/json"])

def Test.service.of(outcome: Test.tape() & TC.Service) -> TC.Service:
  (rest, service) = outcome
  service

def Test.served(tape: Test.tape()) -> IO(TC.Service):
  do IO<TC.Service>:
    outcome : Test.tape() & TC.Service <- NativeHttp.continue_or_start_with(~Test.tape(), ~TC.Source.tape, tape,
      TC.Limits.default(), Test.request(), None{}, TC.Continue{}, TC.InheritSampled{}, TC.Lenient{})
    return Test.service.of(outcome)

def Test.served_without(tape: Test.tape()) -> IO(TC.Service):
  do IO<TC.Service>:
    outcome : Test.tape() & TC.Service <- NativeHttp.continue_or_start_with(~Test.tape(), ~TC.Source.tape, tape,
      TC.Limits.default(), Test.map(), None{}, TC.Continue{}, TC.InheritSampled{}, TC.Lenient{})
    return Test.service.of(outcome)

def Test.traceparent(context: TC.LocalContext) -> String:
  TC.TraceParentV00.format(TC.LocalContext.to_traceparent(context))

def Test.operation(outgoing: Maybe<&2, TC.OutgoingContext>) -> String:
  match outgoing:
    case None{}:
      "none"
    case Some{context}:
      Test.traceparent(TC.OutgoingContext.context(context))

# The values under each name that matters here.
def Test.map_text(+map: Map<&2, List<&2, String>>) -> String:
  "traceparent " ++ Test.values(Test.get(map, "traceparent")) ++ "; TraceParent " ++
    Test.values(Test.get(map, "TraceParent")) ++ "; tracestate " ++ Test.values(Test.get(map, "tracestate")) ++
    "; content-type " ++ Test.values(Test.get(map, "content-type"))

# What a request to send carries: its diagnostic, then its map's values.
def Test.sent_text(outbound: NativeHttp.Outbound) -> String:
  match outbound:
    case NativeHttp.Outbound{sent, +map}:
      TC.Sent.show(sent) ++ " | " ++ Test.map_text(map)

def Test.sent.of(outcome: Test.tape() & NativeHttp.Outbound) -> NativeHttp.Outbound:
  (rest, done) = outcome
  done

def Test.send(tape: Test.tape(), service: TC.Service) -> IO(NativeHttp.Outbound):
  do IO<NativeHttp.Outbound>:
    outcome : Test.tape() & NativeHttp.Outbound <- NativeHttp.send_with(~Test.tape(),
      ~TC.Source.tape, tape, TC.Limits.default(), service, TC.InheritSampled{}, TC.Lenient{}, Test.reused())
    return Test.sent.of(outcome)

def Test.strict_text(result: Result<&2, &2, TC.GenerationError, NativeHttp.Outbound>) -> String:
  match result:
    case Fail{error}:
      "Fail " ++ TC.GenerationError.show(error)
    case Done{done}:
      "Done " ++ Test.sent_text(done)

def Test.send_strictly(tape: Test.tape(), service: TC.Service) -> IO(String):
  do IO<String>:
    outcome : Test.tape() & Result<&2, &2, TC.GenerationError, NativeHttp.Outbound> <-
      NativeHttp.send_with(~Test.tape(), ~TC.Source.tape, tape, TC.Limits.default(), service, TC.InheritSampled{},
        TC.Strict{}, Test.reused())
    return Test.strict_text(Pair.snd(Test.tape(), Result<&2, &2, TC.GenerationError,
      NativeHttp.Outbound>, outcome))

# The shortcuts are the package's operations on the carrier of a map: a
# received request's context is continued, and each request sent has its old
# context fields, whatever their case, replaced by those the package writes,
# or cleared when it writes none (spec #1, "replace old outgoing fields").
def Test.shortcuts() -> IO(Unit):
  do IO<Unit>:
    +service : TC.Service <- Test.served(Test.other_span([]))
    Unit <- Test.same("a received request is continued", TC.Service.show(service) ++ " " ++
      Test.operation(TC.Service.outgoing(service)), "Continued 00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-01")
    fresh : NativeHttp.Outbound <- Test.send(Test.third_span([]), service)
    Unit <- Test.same("a sent request gets a child in place of its old context", Test.sent_text(fresh),
      "Fresh | traceparent 00-0af7651916cd43dd8448eb211c80319c-53995c3f42cd8ad8-01; TraceParent none; " ++
      "tracestate rojo=00f067aa0ba902b7,congo=t61rcWkgMzE; content-type application/json")
    forwarded : NativeHttp.Outbound <- Test.send(Test.failing(), service)
    Unit <- Test.same("without a child, the received pair is forwarded", Test.sent_text(forwarded),
      "Forwarded after SourceFailure 9 controlled | traceparent " ++
      "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01; TraceParent none; " ++
      "tracestate rojo=00f067aa0ba902b7,congo=t61rcWkgMzE; content-type application/json")
    +untraced : TC.Service <- Test.served(Test.failing())
    Unit <- Test.same("a service without an operation", TC.Service.show(untraced), "Untraced SourceFailure 9 controlled")
    root : TC.Service <- Test.served_without(Test.failing())
    cleared : NativeHttp.Outbound <- Test.send([], root)
    Unit <- Test.same("without a pair to forward, the old context is cleared", Test.sent_text(cleared),
      "NoContext after SourceFailure 9 controlled, NothingKept | traceparent none; TraceParent none; tracestate none; " ++
      "content-type application/json")
    strict : String <- Test.send_strictly(Test.failing(), untraced)
    Unit <- Test.same("a strict send fails with the error", strict, "Fail SourceFailure 9 controlled")
    IO.print("OK: the shortcuts are the package's operations on a header map")

def Test.many(count: Nat, values: List<&2, String>) -> List<&2, String>:
  match count:
    case 0n:
      values
    case 1n+p:
      Test.many(p, Con{"v", values})

def Test.fields(carrier: List<&2, TC.Header>, count: Nat) -> Nat:
  match carrier:
    case Nil{}:
      count
    case Con{header, rest}:
      Test.fields(rest, 1n+count)

def Test.counted(values: List<&2, String>, count: Nat) -> Nat:
  match values:
    case Nil{}:
      count
    case Con{value, rest}:
      Test.counted(rest, 1n+count)

# Ten thousand values of one name, as a received head of 64 KiB can hold:
# the carrier and the map are loops, so they need no deep stack, in
# JavaScript either.
def Test.large() -> IO(Unit):
  +carrier = NativeHttp.carrier(Test.with(Test.map(), "x-many", Test.many(10000n, Nil{})))
  do IO<Unit>:
    Unit <- Test.assert("ten thousand values become ten thousand fields", Nat.is_eq(Test.fields(carrier, 0n), 10000n))
    Unit <- Test.assert("and ten thousand values again",
      Nat.is_eq(Test.counted(Test.get(NativeHttp.headers(carrier), "x-many"), 0n), 10000n))
    IO.print("OK: many values need no deep stack")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.received()
    Unit <- Test.written()
    Unit <- Test.shortcuts()
    Test.large()
