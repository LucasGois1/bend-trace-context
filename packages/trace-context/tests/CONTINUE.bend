import Base
import ../trace_context.bend as TC

# Continuing or starting a received message's trace, and sending the result,
# through the public operations with replayed tapes. Expected values are
# literal fixtures written from spec #1 ("Context lifecycle and flags",
# "Generation and failure contracts") and W3C Trace Context Level 2, not
# recomputed by package helpers. Identifiers are the W3C example words:
# 0af7651916cd43dd8448eb211c80319c, b7ad6b7169203331 and 00f067aa0ba902b7.
def Test.assert(name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "FAIL: " ++ name)

def Test.zeros(count: Nat) -> List<&1, Result<&1, &1, U32 & String, U32>>:
  match count:
    case 0n:
      Nil{}
    case 1n+p:
      Con{Done{0}, Test.zeros(p)}

# The words of 0af7651916cd43dd8448eb211c80319c.
def Test.w3c_trace(tail: List<&1, Result<&1, &1, U32 & String, U32>>) -> List<&1, Result<&1, &1, U32 & String, U32>>:
  Con{Done{183985433}, Con{Done{382551005}, Con{Done{2219371297}, Con{Done{478163356}, tail}}}}

# The words of 4bf92f3577b34da6a3ce929d0e0e4736.
def Test.other_trace(tail: List<&1, Result<&1, &1, U32 & String, U32>>) -> List<&1, Result<&1, &1, U32 & String, U32>>:
  Con{Done{1274621749}, Con{Done{2008239526}, Con{Done{2748224157}, Con{Done{235816758}, tail}}}}

# The words of b7ad6b7169203331.
def Test.w3c_span(tail: List<&1, Result<&1, &1, U32 & String, U32>>) -> List<&1, Result<&1, &1, U32 & String, U32>>:
  Con{Done{3081595761}, Con{Done{1763717937}, tail}}

# The words of 00f067aa0ba902b7.
def Test.other_span(tail: List<&1, Result<&1, &1, U32 & String, U32>>) -> List<&1, Result<&1, &1, U32 & String, U32>>:
  Con{Done{15755178}, Con{Done{195625655}, tail}}

# The words of 53995c3f42cd8ad8.
def Test.third_span(tail: List<&1, Result<&1, &1, U32 & String, U32>>) -> List<&1, Result<&1, &1, U32 & String, U32>>:
  Con{Done{1402559551}, Con{Done{1120766680}, tail}}

# The words of a3ce929d0e0e4736.
def Test.fourth_span(tail: List<&1, Result<&1, &1, U32 & String, U32>>) -> List<&1, Result<&1, &1, U32 & String, U32>>:
  Con{Done{2748224157}, Con{Done{235816758}, tail}}

# The words of 5b8efff798038103d269b633813fc60c, the trace of Test.own_base.
def Test.own_trace(tail: List<&1, Result<&1, &1, U32 & String, U32>>) -> List<&1, Result<&1, &1, U32 & String, U32>>:
  Con{Done{1536098295}, Con{Done{2550366467}, Con{Done{3530143283}, Con{Done{2168440332}, tail}}}}

def Test.sentinel() -> List<&1, Result<&1, &1, U32 & String, U32>>:
  [Done{7}]

def Test.left(rest: List<&1, Result<&1, &1, U32 & String, U32>>) -> Nat:
  List.length(&1, Result<&1, &1, U32 & String, U32>, rest)

def Test.traceparent(context: TC.LocalContext) -> String:
  TC.TraceParentV00.format(TC.LocalContext.to_traceparent(context))

def Test.kept(received: Maybe<&2, TC.IncomingContext>) -> String:
  match received:
    case None{}:
      "no pair"
    case Some{incoming}:
      "pair kept"

# The service's operation and state as "show | traceparent | tracestate |
# pair", or its diagnostic when it has none.
def Test.service_text(service: TC.Service) -> String:
  match service:
    case TC.Operating{origin, +outgoing, received}:
      TC.Origin.show(origin) ++ " | " ++ Test.traceparent(TC.OutgoingContext.context(outgoing)) ++ " | " ++
        TC.TraceState.format(TC.OutgoingContext.state(outgoing)) ++ " | " ++ Test.kept(received)
    case TC.Untraced{error, received}:
      "Untraced " ++ TC.GenerationError.show(error) ++ " | " ++ Test.kept(received)

def Test.served(+name: String, expected: String, left: Nat,
  outcome: List<&1, Result<&1, &1, U32 & String, U32>> & TC.Service) -> IO(Unit):
  (rest, service) = outcome
  do IO<Unit>:
    +text : String = Test.service_text(service)
    Unit <- Test.assert(name ++ ", got " ++ text, String.eq(text, expected))
    Test.assert(name ++ ": the words read", Nat.is_eq(Test.left(rest), left))

def Test.extracted(carrier: List<&2, TC.Header>, base: Maybe<&2, TC.BaseContext>) -> TC.Extraction:
  TC.Context.extract(TC.Limits.default(), carrier, base)

# A request that carries the W3C example context and state.
def Test.traced() -> List<&2, TC.Header>:
  [TC.Header{"traceparent", "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"},
    TC.Header{"tracestate", "congo=t61rcWkgMzE"}]

# A message's accepted context is continued by a child: the same trace ID and
# flags, a new span ID and the received state (spec #1, "Continue-or-start
# creates a child when extraction or the retained base supplies a usable
# context").
def Test.continued() -> IO(Unit):
  do IO<Unit>:
    child : List<&1, Result<&1, &1, U32 & String, U32>> & TC.Service <-
      TC.Context.continue_or_start_with(~List<&1, Result<&1, &1, U32 & String, U32>>, ~TC.Source.tape,
        Test.other_span(Test.sentinel()), Test.extracted(Test.traced(), None{}), TC.Continue{}, TC.InheritSampled{},
        TC.Lenient{})
    Unit <- Test.served("a message's context is continued by a child", "Continued | " ++
      "00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-01 | congo=t61rcWkgMzE | pair kept", 1n, child)
    IO.print("OK: a usable context is continued")

def Test.id(-A: Data, result: Result<&2, &2, TC.Error, A>) -> IO(A):
  match result:
    case Fail{error}:
      IO.die(A, 1, "FAIL: ID fixture: " ++ TC.Error.show(error))
    case Done{value}:
      IO.pure(A, value)

def Test.state.of(result: Result<&2, &2, TC.StateError, TC.TraceState>) -> IO(TC.TraceState):
  match result:
    case Fail{error}:
      IO.die(TC.TraceState, 1, "FAIL: state fixture: " ++ TC.StateError.show(error))
    case Done{state}:
      IO.pure(TC.TraceState, state)

def Test.state(text: String) -> IO(TC.TraceState):
  Test.state.of(TC.TraceState.parse(TC.Limits.default(), text))

def Test.incoming.of(incoming: Maybe<&2, TC.IncomingContext>) -> IO(TC.IncomingContext):
  match incoming:
    case None{}:
      IO.die(TC.IncomingContext, 1, "FAIL: no incoming context")
    case Some{context}:
      IO.pure(TC.IncomingContext, context)

# An operation of this service that a message without a usable traceparent
# falls back to: 5b8efff798038103d269b633813fc60c-eee19b7ec3c1b174, not
# sampled, with the service's own state.
def Test.own_base() -> IO(TC.BaseContext):
  do IO<TC.BaseContext>:
    trace : TC.TraceId <- Test.id(TC.TraceId, TC.TraceId.parse("5b8efff798038103d269b633813fc60c"))
    span : TC.SpanId <- Test.id(TC.SpanId, TC.SpanId.parse("eee19b7ec3c1b174"))
    state : TC.TraceState <- Test.state("fw529a3039=cHJpbWFyeQ")
    return TC.OutgoingBase{TC.OutgoingContext.with_state(TC.Context.root_from_ids(trace, span), state)}

def Test.tape() -> Type:
  List<&1, Result<&1, &1, U32 & String, U32>>

def Test.serve(tape: Test.tape(), extraction: TC.Extraction, reception: TC.Reception, sampling: TC.Sampling) ->
  IO(Test.tape() & TC.Service):
  TC.Context.continue_or_start_with(~Test.tape(), ~TC.Source.tape, tape, extraction, reception, sampling, TC.Lenient{})

# Without a usable traceparent, the base is continued: its parent and state
# (spec #1, "or the retained base supplies a usable context"). The message's
# pair was not accepted, so none is kept.
def Test.bases() -> IO(Unit):
  do IO<Unit>:
    +own : TC.BaseContext <- Test.own_base()
    invalid : Test.tape() & TC.Service <- Test.serve(Test.other_span(Test.sentinel()),
      Test.extracted([TC.Header{"traceparent", "00-00000000000000000000000000000000-b7ad6b7169203331-01"}], Some{own}),
      TC.Continue{}, TC.InheritSampled{})
    Unit <- Test.served("an invalid traceparent continues this service's operation", "Continued | " ++
      "00-5b8efff798038103d269b633813fc60c-00f067aa0ba902b7-00 | fw529a3039=cHJpbWFyeQ | no pair", 1n, invalid)
    earlier : TC.IncomingContext <- Test.incoming.of(TC.Extraction.incoming(Test.extracted(Test.traced(), None{})))
    absent : Test.tape() & TC.Service <- Test.serve(Test.other_span(Test.sentinel()),
      Test.extracted([TC.Header{"Accept", "*/*"}], Some{TC.IncomingBase{earlier}}), TC.Continue{}, TC.InheritSampled{})
    Unit <- Test.served("a message without context continues a context received earlier", "Continued | " ++
      "00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-01 | congo=t61rcWkgMzE | no pair", 1n, absent)
    unsampled : Test.tape() & TC.Service <- Test.serve(Test.other_span(Test.sentinel()), Test.extracted(Test.traced(),
      None{}), TC.Continue{}, TC.SetSampled{False{}})
    Unit <- Test.served("a child takes a sampling override", "Continued | " ++
      "00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-00 | congo=t61rcWkgMzE | pair kept", 1n, unsampled)
    IO.print("OK: the base is continued without a usable traceparent")

# Without any context, a root starts the trace: random and unsampled by
# default, flags 02, with no state (spec #1, "creates a root otherwise",
# "New roots default to sampled 0").
def Test.roots() -> IO(Unit):
  do IO<Unit>:
    root : Test.tape() & TC.Service <- Test.serve(Test.w3c_trace(Test.w3c_span(Test.sentinel())),
      Test.extracted([TC.Header{"Accept", "*/*"}], None{}), TC.Continue{}, TC.InheritSampled{})
    Unit <- Test.served("no context starts a root", "Started | " ++
      "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-02 |  | no pair", 1n, root)
    sampled : Test.tape() & TC.Service <- Test.serve(Test.w3c_trace(Test.w3c_span(Test.sentinel())),
      Test.extracted([TC.Header{"traceparent", "ff-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"}], None{}),
      TC.Continue{}, TC.SetSampled{True{}})
    Unit <- Test.served("a refused traceparent without a base starts a root, which takes a sampling override",
      "Started | 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-03 |  | no pair", 1n, sampled)
    IO.print("OK: a root starts a trace without context")

# At a boundary, the context that extraction keeps is not continued: a new
# trace replaces it, with a trace ID other than the replaced one and the root
# defaults, and its state is discarded (spec #1, "Explicit restart creates a
# new trace identity, discards previous tracestate and applies root defaults
# ... unless the caller explicitly supplies a new policy"). This holds for
# the message's context and for a base, received earlier or this service's
# own; without any context, a root starts the trace.
def Test.restarts() -> IO(Unit):
  do IO<Unit>:
    +own : TC.BaseContext <- Test.own_base()
    restarted : Test.tape() & TC.Service <- Test.serve(Test.w3c_trace(Test.other_trace(Test.other_span(Test.sentinel()))),
      Test.extracted(Test.traced(), Some{own}), TC.Restart{}, TC.InheritSampled{})
    Unit <- Test.served("a restart never reuses the received trace ID", "Restarted | " ++
      "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-02 |  | no pair", 1n, restarted)
    sampled : Test.tape() & TC.Service <- Test.serve(Test.other_trace(Test.other_span(Test.sentinel())),
      Test.extracted(Test.traced(), None{}), TC.Restart{}, TC.SetSampled{True{}})
    Unit <- Test.served("a restart takes a sampling override", "Restarted | " ++
      "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-03 |  | no pair", 1n, sampled)
    based : Test.tape() & TC.Service <- Test.serve(Test.own_trace(Test.w3c_trace(Test.w3c_span(Test.sentinel()))),
      Test.extracted([TC.Header{"Accept", "*/*"}], Some{own}), TC.Restart{}, TC.InheritSampled{})
    Unit <- Test.served("at a boundary, this service's base is replaced, never reusing its trace ID", "Restarted | " ++
      "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-02 |  | no pair", 1n, based)
    earlier : TC.IncomingContext <- Test.incoming.of(TC.Extraction.incoming(Test.extracted(Test.traced(), None{})))
    received : Test.tape() & TC.Service <- Test.serve(Test.w3c_trace(Test.other_trace(Test.other_span(Test.sentinel()))),
      Test.extracted([TC.Header{"Accept", "*/*"}], Some{TC.IncomingBase{earlier}}), TC.Restart{}, TC.InheritSampled{})
    Unit <- Test.served("at a boundary, a context received earlier is replaced and its state discarded",
      "Restarted | 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-02 |  | no pair", 1n, received)
    without : Test.tape() & TC.Service <- Test.serve(Test.w3c_trace(Test.w3c_span(Test.sentinel())),
      Test.extracted([TC.Header{"Accept", "*/*"}], None{}), TC.Restart{}, TC.InheritSampled{})
    Unit <- Test.served("at a boundary, a message without any context starts a root", "Started | " ++
      "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-02 |  | no pair", 1n, without)
    IO.print("OK: a boundary restarts the trace")

def Test.strict_text(result: Result<&2, &2, TC.GenerationError, TC.Service>) -> String:
  match result:
    case Fail{error}:
      "Fail " ++ TC.GenerationError.show(error)
    case Done{service}:
      "Done " ++ Test.service_text(service)

def Test.strict(+name: String, expected: String, left: Nat,
  outcome: Test.tape() & Result<&2, &2, TC.GenerationError, TC.Service>) -> IO(Unit):
  (rest, result) = outcome
  do IO<Unit>:
    +text : String = Test.strict_text(result)
    Unit <- Test.assert(name ++ ", got " ++ text, String.eq(text, expected))
    Test.assert(name ++ ": the words read", Nat.is_eq(Test.left(rest), left))

def Test.serve_strictly(tape: Test.tape(), extraction: TC.Extraction, reception: TC.Reception) ->
  IO(Test.tape() & Result<&2, &2, TC.GenerationError, TC.Service>):
  TC.Context.continue_or_start_with(~Test.tape(), ~TC.Source.tape, tape, extraction, reception, TC.InheritSampled{},
    TC.Strict{})

# When an identifier cannot be generated, a lenient service has no
# operation and says why, keeping the message's pair for forwarding; a strict
# one returns the error (spec #1, "Exhaustion and source failure are
# structured outcomes"; "a strict integration option lets the caller fail
# the operation"). No word is read after the failure.
def Test.failures() -> IO(Unit):
  do IO<Unit>:
    failed : Test.tape() & TC.Service <- Test.serve(Con{Fail{(9, "controlled")}, Test.sentinel()},
      Test.extracted(Test.traced(), None{}), TC.Continue{}, TC.InheritSampled{})
    Unit <- Test.served("a source failure leaves the service without an operation",
      "Untraced SourceFailure 9 controlled | pair kept", 1n, failed)
    exhausted : Test.tape() & TC.Service <- Test.serve(List.append(&1, Result<&1, &1, U32 & String, U32>,
      Test.zeros(16n), Test.sentinel()), Test.extracted(Test.traced(), None{}), TC.Continue{}, TC.InheritSampled{})
    Unit <- Test.served("eight zero span ID candidates exhaust the child", "Untraced ExhaustedSpanId | pair kept", 1n,
      exhausted)
    empty : Test.tape() & TC.Service <- Test.serve(Nil{}, Test.extracted([], None{}), TC.Continue{},
      TC.InheritSampled{})
    Unit <- Test.served("a root without words", "Untraced SourceFailure 1 tape-exhausted | no pair", 0n, empty)
    boundary : Test.tape() & TC.Service <- Test.serve(List.append(&1, Result<&1, &1, U32 & String, U32>,
      Test.zeros(32n), Test.sentinel()), Test.extracted(Test.traced(), None{}), TC.Restart{}, TC.InheritSampled{})
    Unit <- Test.served("an exhausted restart keeps no pair", "Untraced ExhaustedTraceId | no pair", 1n, boundary)
    strict : Test.tape() & Result<&2, &2, TC.GenerationError, TC.Service> <-
      Test.serve_strictly(Con{Fail{(9, "controlled")}, Test.sentinel()}, Test.extracted(Test.traced(), None{}),
        TC.Continue{})
    Unit <- Test.strict("a strict service fails with the error", "Fail SourceFailure 9 controlled", 1n, strict)
    served : Test.tape() & Result<&2, &2, TC.GenerationError, TC.Service> <-
      Test.serve_strictly(Test.other_span(Test.sentinel()), Test.extracted(Test.traced(), None{}), TC.Continue{})
    Unit <- Test.strict("a strict service that succeeds", "Done Continued | " ++
      "00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-01 | congo=t61rcWkgMzE | pair kept", 1n, served)
    IO.print("OK: generation failures under both policies")

def Test.header(header: TC.Header) -> String:
  match header:
    case TC.Header{name, value}:
      name ++ ": " ++ value

def Test.carrier.rest(carrier: List<&2, TC.Header>) -> String:
  match carrier:
    case Nil{}:
      ""
    case Con{header, rest}:
      " | " ++ Test.header(header) ++ Test.carrier.rest(rest)

# A carrier as "name: value" fields joined by " | ", in order; "" for none.
def Test.carrier(carrier: List<&2, TC.Header>) -> String:
  match carrier:
    case Nil{}:
      ""
    case Con{header, rest}:
      Test.header(header) ++ Test.carrier.rest(rest)

# What an outgoing message carries: "Fresh traceparent | fields" for a new
# operation, or the fallback with its diagnostics and fields.
def Test.sent_text(sent: TC.Sent) -> String:
  match sent:
    case TC.Fresh{operation, injection}:
      "Fresh " ++ Test.traceparent(operation) ++ " | " ++ Test.carrier(TC.Injection.carrier(injection))
    case TC.Forwarded{carrier, error}:
      "Forwarded after " ++ TC.GenerationError.show(error) ++ " | " ++ Test.carrier(carrier)
    case TC.NoContext{carrier, error, reason}:
      "NoContext after " ++ TC.GenerationError.show(error) ++ ", " ++ TC.Unforwarded.show(reason) ++ " | " ++
        Test.carrier(carrier)

def Test.sent(+name: String, expected: String, left: Nat, outcome: Test.tape() & TC.Sent) -> IO(Unit):
  (rest, sent) = outcome
  do IO<Unit>:
    +text : String = Test.sent_text(sent)
    Unit <- Test.assert(name ++ ", got " ++ text, String.eq(text, expected))
    Test.assert(name ++ ": the words read", Nat.is_eq(Test.left(rest), left))

# A request container a client reuses: an old context in mixed case among
# other fields.
def Test.stale() -> List<&2, TC.Header>:
  [TC.Header{"Host", "inventory.internal"}, TC.Header{"TraceParent", "00-5b8efff798038103d269b633813fc60c-eee19b7ec3c1b174-01"},
    TC.Header{"Content-Type", "application/json"}, TC.Header{"TRACESTATE", "stale=1"}]

def Test.send(tape: Test.tape(), service: TC.Service, sampling: TC.Sampling) -> IO(Test.tape() & TC.Sent):
  TC.Context.send_with(~Test.tape(), ~TC.Source.tape, tape, TC.Limits.default(), service, sampling, TC.Lenient{},
    Test.stale())

def Test.service.of(outcome: Test.tape() & TC.Service) -> TC.Service:
  (rest, service) = outcome
  service

# Each outgoing message gets its own child of the service's operation, which
# sends the service's state and replaces the container's old context fields
# (spec #1, "each distinct outgoing operation obtains its own child before
# injection"; ticket #11, "a distinct operation for each outgoing
# operation/fan-out branch").
def Test.fan_out() -> IO(Unit):
  do IO<Unit>:
    outcome : Test.tape() & TC.Service <- Test.serve(Test.other_span(Test.sentinel()),
      Test.extracted(Test.traced(), None{}), TC.Continue{}, TC.InheritSampled{})
    +service : TC.Service = Test.service.of(outcome)
    first : Test.tape() & TC.Sent <- Test.send(Test.w3c_span(Test.sentinel()), service, TC.InheritSampled{})
    Unit <- Test.sent("the first request gets its own child", "Fresh " ++
      "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01 | Host: inventory.internal | " ++
      "Content-Type: application/json | traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01 | " ++
      "tracestate: congo=t61rcWkgMzE", 1n, first)
    second : Test.tape() & TC.Sent <- Test.send(Test.third_span(Test.sentinel()), service, TC.InheritSampled{})
    Unit <- Test.sent("the second request gets another child", "Fresh " ++
      "00-0af7651916cd43dd8448eb211c80319c-53995c3f42cd8ad8-01 | Host: inventory.internal | " ++
      "Content-Type: application/json | traceparent: 00-0af7651916cd43dd8448eb211c80319c-53995c3f42cd8ad8-01 | " ++
      "tracestate: congo=t61rcWkgMzE", 1n, second)
    reused : Test.tape() & TC.Sent <- Test.send(Test.other_span(Test.fourth_span(Test.sentinel())), service,
      TC.SetSampled{False{}})
    Unit <- Test.sent("a child never reuses the service's span ID, and takes a sampling override", "Fresh " ++
      "00-0af7651916cd43dd8448eb211c80319c-a3ce929d0e0e4736-00 | Host: inventory.internal | " ++
      "Content-Type: application/json | traceparent: 00-0af7651916cd43dd8448eb211c80319c-a3ce929d0e0e4736-00 | " ++
      "tracestate: congo=t61rcWkgMzE", 1n, reused)
    IO.print("OK: each outgoing message gets its own child")

# A received state of 600 octets, within the input budget but over the
# output budget of 512 (spec #1's example): entries of 256, 256 and 86 octets.
def Test.six_hundred() -> String:
  "a=" ++ String.repeat("x", 254n) ++ ",b=" ++ String.repeat("y", 254n) ++ ",c=" ++ String.repeat("z", 84n)

def Test.served_by(tape: Test.tape(), carrier: List<&2, TC.Header>, base: Maybe<&2, TC.BaseContext>,
  reception: TC.Reception) -> IO(TC.Service):
  do IO<TC.Service>:
    outcome : Test.tape() & TC.Service <- Test.serve(tape, Test.extracted(carrier, base), reception, TC.InheritSampled{})
    return Test.service.of(outcome)

def Test.strict_sent_text(result: Result<&2, &2, TC.GenerationError, TC.Sent>) -> String:
  match result:
    case Fail{error}:
      "Fail " ++ TC.GenerationError.show(error)
    case Done{sent}:
      "Done " ++ Test.sent_text(sent)

def Test.sent_strictly(+name: String, expected: String, left: Nat,
  outcome: Test.tape() & Result<&2, &2, TC.GenerationError, TC.Sent>) -> IO(Unit):
  (rest, result) = outcome
  do IO<Unit>:
    +text : String = Test.strict_sent_text(result)
    Unit <- Test.assert(name ++ ", got " ++ text, String.eq(text, expected))
    Test.assert(name ++ ": the words read", Nat.is_eq(Test.left(rest), left))

def Test.send_strictly(tape: Test.tape(), service: TC.Service) ->
  IO(Test.tape() & Result<&2, &2, TC.GenerationError, TC.Sent>):
  TC.Context.send_with(~Test.tape(), ~TC.Source.tape, tape, TC.Limits.default(), service, TC.InheritSampled{},
    TC.Strict{}, Test.stale())

def Test.failing() -> Test.tape():
  Con{Fail{(9, "controlled")}, Test.sentinel()}

# The message that a service serving `carrier` sends: its text and the words
# the send left unread.
def Test.falls_back(+name: String, served: Test.tape(), carrier: List<&2, TC.Header>,
  base: Maybe<&2, TC.BaseContext>, reception: TC.Reception, sent: Test.tape(), expected: String, left: Nat) -> IO(Unit):
  do IO<Unit>:
    service : TC.Service <- Test.served_by(served, carrier, base, reception)
    outcome : Test.tape() & TC.Sent <- Test.send(sent, service, TC.InheritSampled{})
    Test.sent(name, expected, left, outcome)

# The same with a strict send.
def Test.strictly(+name: String, served: Test.tape(), carrier: List<&2, TC.Header>, base: Maybe<&2, TC.BaseContext>,
  sent: Test.tape(), expected: String) -> IO(Unit):
  do IO<Unit>:
    service : TC.Service <- Test.served_by(served, carrier, base, TC.Continue{})
    outcome : Test.tape() & Result<&2, &2, TC.GenerationError, TC.Sent> <- Test.send_strictly(sent, service)
    Test.sent_strictly(name, expected, 1n, outcome)

# A strict send fails with the error whenever no new operation was
# generated, whether the received pair was forwarded or there was none.
def Test.strict_sends(+own: TC.BaseContext) -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.strictly("a strict send fails with the error", Test.other_span(Test.sentinel()), Test.traced(),
      None{}, Test.failing(), "Fail SourceFailure 9 controlled")
    Unit <- Test.strictly("a strict send without a pair to forward fails with the error",
      Test.other_span(Test.sentinel()), [], Some{own}, Test.failing(), "Fail SourceFailure 9 controlled")
    Test.strictly("a strict send that succeeds", Test.other_span(Test.sentinel()), Test.traced(), None{},
      Test.w3c_span(Test.sentinel()), "Done Fresh " ++
      "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01 | Host: inventory.internal | " ++
      "Content-Type: application/json | traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01 | " ++
      "tracestate: congo=t61rcWkgMzE")

# When no operation can be generated, no new operation is reported: the
# message forwards the received pair unchanged if it was accepted whole and
# fits the output budget, and carries no context fields otherwise (spec #1,
# "It may forward only an entirely accepted original pair that can be sent
# intact within bounds; otherwise clear outgoing context fields. Never
# report a newly created operation after generation failed").
def Test.fallbacks() -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.falls_back("a child that cannot be generated forwards the received pair",
      Test.other_span(Test.sentinel()), Test.traced(), None{}, TC.Continue{}, Test.failing(),
      "Forwarded after SourceFailure 9 controlled | Host: inventory.internal | Content-Type: application/json | " ++
      "traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01 | tracestate: congo=t61rcWkgMzE", 1n)
    Unit <- Test.falls_back("a service without an operation forwards without reading the source", Test.failing(),
      Test.traced(), None{}, TC.Continue{}, Test.w3c_span(Test.sentinel()),
      "Forwarded after SourceFailure 9 controlled | Host: inventory.internal | Content-Type: application/json | " ++
      "traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01 | tracestate: congo=t61rcWkgMzE", 3n)
    Unit <- Test.falls_back("a boundary never forwards the received pair", List.append(&1,
      Result<&1, &1, U32 & String, U32>, Test.zeros(32n), Test.sentinel()), Test.traced(), None{}, TC.Restart{},
      Test.sentinel(),
      "NoContext after ExhaustedTraceId, NothingKept | Host: inventory.internal | Content-Type: application/json",
      1n)
    Unit <- Test.falls_back("a root has no pair to forward", Test.w3c_trace(Test.w3c_span(Test.sentinel())), [], None{},
      TC.Continue{}, List.append(&1, Result<&1, &1, U32 & String, U32>, Test.zeros(16n), Test.sentinel()),
      "NoContext after ExhaustedSpanId, NothingKept | Host: inventory.internal | Content-Type: application/json",
      1n)
    +own : TC.BaseContext <- Test.own_base()
    Unit <- Test.falls_back("a continued base has no pair of this message to forward", Test.other_span(Test.sentinel()),
      [], Some{own}, TC.Continue{}, Test.failing(), "NoContext after SourceFailure 9 controlled, NothingKept | " ++
      "Host: inventory.internal | Content-Type: application/json", 1n)
    Unit <- Test.falls_back("a discarded state leaves no pair to forward", Test.other_span(Test.sentinel()),
      [TC.Header{"traceparent", "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"},
        TC.Header{"tracestate", "rojo"}], None{}, TC.Continue{}, Test.failing(),
      "NoContext after SourceFailure 9 controlled, NothingToForward | Host: inventory.internal | " ++
      "Content-Type: application/json", 1n)
    Unit <- Test.falls_back("a pair too large to send whole is not forwarded", Test.other_span(Test.sentinel()),
      [TC.Header{"traceparent", "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"},
        TC.Header{"tracestate", Test.six_hundred()}], None{}, TC.Continue{}, Test.failing(),
      "NoContext after SourceFailure 9 controlled, ForwardTooLarge | Host: inventory.internal | " ++
      "Content-Type: application/json", 1n)
    Unit <- Test.strict_sends(own)
    IO.print("OK: no new operation after a failed generation")

def Test.maybe_span(context: Maybe<&2, TC.LocalContext>) -> String:
  match context:
    case None{}:
      "none"
    case Some{operation}:
      TC.SpanId.to_string(TC.LocalContext.span_id(operation))

def Test.maybe_error(error: Maybe<&2, TC.GenerationError>) -> String:
  match error:
    case None{}:
      "none"
    case Some{reason}:
      TC.GenerationError.show(reason)

def Test.maybe_origin(origin: Maybe<&2, TC.Origin>) -> String:
  match origin:
    case None{}:
      "none"
    case Some{how}:
      TC.Origin.show(how)

def Test.maybe_operation(outgoing: Maybe<&2, TC.OutgoingContext>) -> String:
  match outgoing:
    case None{}:
      "none"
    case Some{operation}:
      TC.SpanId.to_string(TC.LocalContext.span_id(TC.OutgoingContext.context(operation)))

# The accessors of a service: its origin, operation and error.
def Test.service_parts(+service: TC.Service) -> String:
  Test.maybe_origin(TC.Service.origin(service)) ++ " " ++ Test.maybe_operation(TC.Service.outgoing(service)) ++ " " ++
    Test.maybe_error(TC.Service.error(service))

# The accessors of an outgoing message: its operation, error and fields.
def Test.sent_parts(+sent: TC.Sent) -> String:
  Test.maybe_span(TC.Sent.operation(sent)) ++ " " ++ Test.maybe_error(TC.Sent.error(sent)) ++ " | " ++
    Test.carrier(TC.Sent.carrier(sent))

def Test.sent.of(outcome: Test.tape() & TC.Sent) -> TC.Sent:
  (rest, sent) = outcome
  sent

def Test.same(name: String, +got: String, expected: String) -> IO(Unit):
  Test.assert(name ++ ", got " ++ got, String.eq(got, expected))

# The diagnostic and the parts of the service a message gives.
def Test.service_named(+name: String, tape: Test.tape(), carrier: List<&2, TC.Header>, reception: TC.Reception,
  show: String, parts: String) -> IO(Unit):
  do IO<Unit>:
    +service : TC.Service <- Test.served_by(tape, carrier, None{}, reception)
    Unit <- Test.same(name, TC.Service.show(service), show)
    Test.same(name ++ ": its parts", Test.service_parts(service), parts)

# The diagnostic and the parts of what a service sends.
def Test.sent_named(+name: String, tape: Test.tape(), service: TC.Service, show: String, parts: String) ->
  IO(Unit):
  do IO<Unit>:
    outcome : Test.tape() & TC.Sent <- Test.send(tape, service, TC.InheritSampled{})
    +sent : TC.Sent = Test.sent.of(outcome)
    Unit <- Test.same(name, TC.Sent.show(sent), show)
    Test.same(name ++ ": its parts", Test.sent_parts(sent), parts)

def Test.entry.of(-A: Data, result: Result<&2, &2, TC.EntryError, A>) -> IO(A):
  match result:
    case Fail{error}:
      IO.die(A, 1, "FAIL: entry fixture: " ++ TC.EntryError.show(error))
    case Done{value}:
      IO.pure(A, value)

# A service puts its own entry first in the state it sends, as a participant
# does, or removes one, and a restarted service takes a new state of its own
# (W3C 3.3.1.3; spec #1, "unless the caller explicitly supplies a new
# policy/state"). A service without an operation sends no state of its own,
# so it is unchanged.
def Test.own_entries() -> IO(Unit):
  do IO<Unit>:
    +key : TC.StateKey <- Test.entry.of(TC.StateKey, TC.StateKey.parse("fw529a3039"))
    +value : TC.StateValue <- Test.entry.of(TC.StateValue, TC.StateValue.parse("cHJpbWFyeQ"))
    congo : TC.StateKey <- Test.entry.of(TC.StateKey, TC.StateKey.parse("congo"))
    +continued : TC.Service <- Test.served_by(Test.other_span(Test.sentinel()), Test.traced(), None{}, TC.Continue{})
    Unit <- Test.same("a continued service sets its own entry first",
      Test.service_text(TC.Service.set(continued, key, value)), "Continued | " ++
      "00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-01 | fw529a3039=cHJpbWFyeQ,congo=t61rcWkgMzE | pair kept")
    Unit <- Test.same("a continued service removes an entry", Test.service_text(TC.Service.remove(continued, congo)),
      "Continued | 00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-01 |  | pair kept")
    restarted : TC.Service <- Test.served_by(Test.other_trace(Test.other_span(Test.sentinel())), Test.traced(), None{},
      TC.Restart{})
    Unit <- Test.same("a restarted service takes a new state of its own",
      Test.service_text(TC.Service.set(restarted, key, value)),
      "Restarted | 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-02 | fw529a3039=cHJpbWFyeQ | no pair")
    untraced : TC.Service <- Test.served_by(Test.failing(), Test.traced(), None{}, TC.Continue{})
    Unit <- Test.same("a service without an operation is unchanged",
      Test.service_text(TC.Service.set(untraced, key, value)), "Untraced SourceFailure 9 controlled | pair kept")
    IO.print("OK: a service sets its own entries")

def Test.keys.rest(keys: List<&2, TC.StateKey>) -> String:
  match keys:
    case Nil{}:
      ""
    case Con{key, rest}:
      "," ++ TC.StateKey.to_string(key) ++ Test.keys.rest(rest)

# Keys joined by commas, or "none".
def Test.keys(keys: List<&2, TC.StateKey>) -> String:
  match keys:
    case Nil{}:
      "none"
    case Con{key, rest}:
      TC.StateKey.to_string(key) ++ Test.keys.rest(rest)

# A new operation whose state had to be truncated says so, and gives the
# keys dropped; a fallback sends no state of its own and drops none (spec #1,
# "Diagnostics distinguish absence, rejection, state discard, truncation").
def Test.truncation() -> IO(Unit):
  do IO<Unit>:
    +large : TC.Service <- Test.served_by(Test.other_span(Test.sentinel()),
      [TC.Header{"traceparent", "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"},
        TC.Header{"tracestate", Test.six_hundred()}], None{}, TC.Continue{})
    outcome : Test.tape() & TC.Sent <- Test.send(Test.w3c_span(Test.sentinel()), large, TC.InheritSampled{})
    +sent : TC.Sent = Test.sent.of(outcome)
    Unit <- Test.same("a truncated state is reported", TC.Sent.show(sent), "Fresh, truncated")
    Unit <- Test.same("a truncated state: the keys dropped", Test.keys(TC.Sent.dropped(sent)), "b")
    failed : Test.tape() & TC.Sent <- Test.send(Test.failing(), large, TC.InheritSampled{})
    Test.same("a fallback drops no key", Test.keys(TC.Sent.dropped(Test.sent.of(failed))), "none")

# Diagnostics name what happened without any received value, so that a
# caller may log them (spec #1, "Diagnostics distinguish absence, rejection,
# state discard, truncation, entropy-source failure and generation
# exhaustion. They do not automatically log raw fields").
def Test.service_diagnostics() -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.service_named("a continued service", Test.other_span(Test.sentinel()), Test.traced(), TC.Continue{},
      "Continued", "Continued 00f067aa0ba902b7 none")
    Unit <- Test.service_named("a started service", Test.w3c_trace(Test.w3c_span(Test.sentinel())), [],
      TC.Continue{}, "Started", "Started b7ad6b7169203331 none")
    Unit <- Test.service_named("a restarted service", Test.w3c_trace(Test.other_trace(Test.other_span(
      Test.sentinel()))), Test.traced(), TC.Restart{}, "Restarted", "Restarted 00f067aa0ba902b7 none")
    Test.service_named("a service without an operation", Test.failing(), Test.traced(), TC.Continue{},
      "Untraced SourceFailure 9 controlled", "none none SourceFailure 9 controlled")

def Test.sent_diagnostics() -> IO(Unit):
  do IO<Unit>:
    +continued : TC.Service <- Test.served_by(Test.other_span(Test.sentinel()), Test.traced(), None{}, TC.Continue{})
    started : TC.Service <- Test.served_by(Test.w3c_trace(Test.w3c_span(Test.sentinel())), [], None{}, TC.Continue{})
    Unit <- Test.sent_named("a fresh operation", Test.w3c_span(Test.sentinel()), continued, "Fresh",
      "b7ad6b7169203331 none | Host: inventory.internal | Content-Type: application/json | " ++
      "traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01 | tracestate: congo=t61rcWkgMzE")
    Unit <- Test.sent_named("a forwarded pair", Test.failing(), continued, "Forwarded after SourceFailure 9 controlled",
      "none SourceFailure 9 controlled | Host: inventory.internal | Content-Type: application/json | " ++
      "traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01 | tracestate: congo=t61rcWkgMzE")
    Test.sent_named("no context", Test.sentinel(), started,
      "NoContext after SourceFailure 1 tape-exhausted, NothingKept",
      "none SourceFailure 1 tape-exhausted | Host: inventory.internal | Content-Type: application/json")

def Test.diagnostics() -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.service_diagnostics()
    Unit <- Test.sent_diagnostics()
    Unit <- Test.truncation()
    IO.print("OK: diagnostics without received values")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.continued()
    Unit <- Test.bases()
    Unit <- Test.roots()
    Unit <- Test.restarts()
    Unit <- Test.failures()
    Unit <- Test.fan_out()
    Unit <- Test.own_entries()
    Unit <- Test.fallbacks()
    Test.diagnostics()
