import Base
import ../trace_context.bend as TC

# Injection, cleanup and forwarding through the public API. Expected values
# are literal fixtures written from W3C Trace Context Level 2 (sections 3.2.1,
# 3.3.1, 3.4 and 3.5) and the approved policy of spec #1, not recomputed by
# package helpers.
def Test.assert(name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "FAIL: " ++ name)

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

def Test.same_carrier(+name: String, carrier: List<&2, TC.Header>, expected: String) -> IO(Unit):
  +text = Test.carrier(carrier)
  Test.assert(name ++ ", got " ++ text, String.eq(text, expected))

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

# The context fields are removed whatever the ASCII case of their names, and
# every other field keeps its place (spec #1, "Provide explicit
# context-field cleanup for the no-context path, including differently cased
# old fields").
def Test.clear() -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.same_carrier("an empty carrier", TC.Context.clear([]), "")
    Unit <- Test.same_carrier("no context field", TC.Context.clear([TC.Header{"Content-Type", "application/json"}]),
      "Content-Type: application/json")
    Unit <- Test.same_carrier("old fields in any case", TC.Context.clear([TC.Header{"Accept", "*/*"},
      TC.Header{"traceparent", "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"}, TC.Header{"X-One", "1"},
      TC.Header{"TraceState", "congo=t61rcWkgMzE"}, TC.Header{"TRACEPARENT", "invalid"}, TC.Header{"X-Two", "2"},
      TC.Header{"tracestate", ""}]), "Accept: */* | X-One: 1 | X-Two: 2")
    Test.same_carrier("names that differ by more than case stay", TC.Context.clear([TC.Header{"trace-parent", "1"},
      TC.Header{"trace\u{17f}tate", "2"}, TC.Header{"traceparents", "3"}]),
      "trace-parent: 1 | trace\u{17f}tate: 2 | traceparents: 3")

def Test.local(-A: Data, result: Result<&2, &2, TC.ContextError, A>) -> IO(A):
  match result:
    case Fail{error}:
      IO.die(A, 1, "FAIL: context fixture: " ++ TC.ContextError.show(error))
    case Done{value}:
      IO.pure(A, value)

# A carrier a client reuses: stale context fields of an earlier request, in
# any case, among other fields.
def Test.stale() -> List<&2, TC.Header>:
  [TC.Header{"Accept", "application/json"}, TC.Header{"TraceParent", "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"},
    TC.Header{"X-Request", "7"}, TC.Header{"tracestate", "rojo=1"}, TC.Header{"TRACESTATE", "congo=2"}]

def Test.dropped.rest(keys: List<&2, TC.StateKey>) -> String:
  match keys:
    case Nil{}:
      ""
    case Con{key, rest}:
      "," ++ TC.StateKey.to_string(key) ++ Test.dropped.rest(rest)

def Test.dropped(keys: List<&2, TC.StateKey>) -> String:
  match keys:
    case Nil{}:
      "none"
    case Con{key, rest}:
      TC.StateKey.to_string(key) ++ Test.dropped.rest(rest)

def Test.injected(+name: String, +injection: TC.Injection, expected: String, dropped: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.same_carrier(name, TC.Injection.carrier(injection), expected)
    Test.assert(name ++ ": the keys dropped", String.eq(Test.dropped(TC.Injection.dropped(injection)), dropped))

# A new root has no state: its traceparent alone is written.
def Test.inject_root(+limits: TC.Limits, +root: TC.OutgoingContext) -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.injected("a root into an empty carrier", TC.Context.inject(limits, root, []),
      "traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-53995c3f42cd8ad8-00", "none")
    Test.injected("a root without state replaces the old fields and omits tracestate",
      TC.Context.inject(limits, root, Test.stale()),
      "Accept: application/json | X-Request: 7 | traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-53995c3f42cd8ad8-00",
      "none")

# A child of a received context with every flag bit set sends only the known
# flags, with the state it carries, truncated to the output budget.
def Test.inject_child(+limits: TC.Limits, +child: TC.LocalContext, state: TC.TraceState, large: TC.TraceState) ->
  IO(Unit):
  do IO<Unit>:
    Unit <- Test.injected("a child with the received state masks the reserved flag bits",
      TC.Context.inject(limits, TC.OutgoingContext.with_state(child, state), Test.stale()),
      "Accept: application/json | X-Request: 7 | traceparent: 00-0af7651916cd43dd8448eb211c80319c-53995c3f42cd8ad8-03 | " ++
        "tracestate: congo=t61rcWkgMzE,rojo=00f067aa0ba902b7", "none")
    Test.injected("a state over the output budget is truncated, and the keys dropped are reported apart",
      TC.Context.inject(limits, TC.OutgoingContext.with_state(child, large), []),
      "traceparent: 00-0af7651916cd43dd8448eb211c80319c-53995c3f42cd8ad8-03 | tracestate: a=" ++ String.repeat("x", 256n),
      "b,c")

# Injection writes the participating traceparent, version 00 with only the
# known flags, and the state truncated to the output budget; it replaces
# every old context field, omits an empty tracestate, keeps the other fields
# in their order and writes lowercase names (spec #1).
def Test.inject() -> IO(Unit):
  +limits = TC.Limits.default()
  do IO<Unit>:
    trace : TC.TraceId <- Test.id(TC.TraceId, TC.TraceId.parse("4bf92f3577b34da6a3ce929d0e0e4736"))
    +span : TC.SpanId <- Test.id(TC.SpanId, TC.SpanId.parse("53995c3f42cd8ad8"))
    Unit <- Test.inject_root(limits, TC.OutgoingContext.new(TC.Context.root_from_ids(trace, span, False{})))
    received : TC.TraceParentV00 <- Test.id(TC.TraceParentV00,
      TC.TraceParentV00.parse("00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-ff"))
    child : TC.LocalContext <- Test.local(TC.LocalContext, TC.Context.child_from_id(
      TC.RemoteParent{TC.RemoteContext.from_traceparent(received)}, span, TC.InheritSampled{}))
    state : TC.TraceState <- Test.state("congo=t61rcWkgMzE,rojo=00f067aa0ba902b7")
    large : TC.TraceState <- Test.state("a=" ++ String.repeat("x", 256n) ++ ",b=" ++ String.repeat("x", 256n) ++
      ",c=" ++ String.repeat("x", 256n))
    Test.inject_child(limits, child, state, large)

# Injecting the same context again gives the same carrier (spec #1,
# "Injection is idempotent on the resulting carrier").
def Test.idempotent(+limits: TC.Limits, +outgoing: TC.OutgoingContext) -> IO(Unit):
  +once = TC.Injection.carrier(TC.Context.inject(limits, outgoing, Test.stale()))
  Test.assert("injecting twice gives the carrier of one injection",
    String.eq(Test.carrier(TC.Injection.carrier(TC.Context.inject(limits, outgoing, once))), Test.carrier(once)))

def Test.twice() -> IO(Unit):
  do IO<Unit>:
    trace : TC.TraceId <- Test.id(TC.TraceId, TC.TraceId.parse("4bf92f3577b34da6a3ce929d0e0e4736"))
    span : TC.SpanId <- Test.id(TC.SpanId, TC.SpanId.parse("53995c3f42cd8ad8"))
    state : TC.TraceState <- Test.state("congo=t61rcWkgMzE")
    Test.idempotent(TC.Limits.default(), TC.OutgoingContext.with_state(TC.Context.from_ids(trace, span, True{}), state))

def Test.incoming.of(incoming: Maybe<&2, TC.IncomingContext>) -> IO(TC.IncomingContext):
  match incoming:
    case None{}:
      IO.die(TC.IncomingContext, 1, "FAIL: incoming fixture: not accepted")
    case Some{found}:
      IO.pure(TC.IncomingContext, found)

def Test.incoming(+limits: TC.Limits, carrier: List<&2, TC.Header>) -> IO(TC.IncomingContext):
  Test.incoming.of(TC.Extraction.incoming(TC.Context.extract(limits, carrier, None{})))

def Test.forward_error(error: TC.ForwardError) -> String:
  match error:
    case TC.NothingToForward{}:
      "nothing to forward"
    case TC.ForwardTooLarge{}:
      "too large"
    case TC.InvalidForwardParent{error}:
      "invalid traceparent " ++ TC.TraceParentError.show(error)
    case TC.InvalidForwardState{error}:
      "invalid tracestate " ++ TC.StateError.show(error)

def Test.forwarded_text(result: Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>) -> String:
  match result:
    case Fail{error}:
      "refused: " ++ Test.forward_error(error)
    case Done{carrier}:
      Test.carrier(carrier)

def Test.forwarded(+name: String, result: Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>, expected: String) ->
  IO(Unit):
  +text = Test.forwarded_text(result)
  Test.assert(name ++ ", got " ++ text, String.eq(text, expected))

# Forward the context extracted from `carrier` into Test.stale().
def Test.forward_from(+name: String, +limits: TC.Limits, carrier: List<&2, TC.Header>, expected: String) -> IO(Unit):
  do IO<Unit>:
    +incoming : TC.IncomingContext <- Test.incoming(limits, carrier)
    Test.forwarded(name, TC.Context.forward(limits, incoming, Test.stale()), expected)

# `count` characters `char` before `tail`, built by a loop.
def Test.fill(count: Nat, +char: Char, tail: String) -> String:
  match count:
    case 0n:
      tail
    case 1n+more:
      Test.fill(more, char, SCon{char, tail})

def Test.others() -> String:
  "Accept: application/json | X-Request: 7 | "

def Test.limits(result: Result<&2, &2, TC.LimitsError, TC.Limits>) -> IO(TC.Limits):
  match result:
    case Fail{error}:
      IO.die(TC.Limits, 1, "FAIL: limits fixture: " ++ TC.LimitsError.show(error))
    case Done{limits}:
      IO.pure(TC.Limits, limits)

# The tracestate of spec #1's example: 600 octets, three entries of 256, 256
# and 86 octets and two commas.
def Test.six_hundred_state() -> String:
  "a=" ++ Test.fill(254n, 'x', "") ++ ",b=" ++ Test.fill(254n, 'y', "") ++ ",c=" ++ Test.fill(84n, 'z', "")

def Test.received_600() -> List<&2, TC.Header>:
  [TC.Header{"traceparent", "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"},
    TC.Header{"tracestate", Test.six_hundred_state()}]

# A received 600-octet tracestate exceeds the default output budget, so its
# pair is not forwarded: sending the traceparent unchanged with a truncated
# tracestate is not allowed (W3C 3.4; spec #1). A child operation sends it
# instead, truncated under its own traceparent: b, the rightmost large
# entry, goes. A larger configured budget forwards the pair whole.
def Test.six_hundred_child(+limits: TC.Limits, +incoming: TC.IncomingContext) -> IO(Unit):
  do IO<Unit>:
    span : TC.SpanId <- Test.id(TC.SpanId, TC.SpanId.parse("53995c3f42cd8ad8"))
    child : TC.LocalContext <- Test.local(TC.LocalContext, TC.Context.child_from_id(TC.IncomingContext.parent(incoming),
      span, TC.InheritSampled{}))
    Test.injected("a child sends the state truncated under its own traceparent",
      TC.Context.inject(limits, TC.OutgoingContext.with_state(child, TC.IncomingContext.state(incoming)), []),
      "traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-53995c3f42cd8ad8-01 | tracestate: a=" ++ Test.fill(254n, 'x', "") ++
        ",c=" ++ Test.fill(84n, 'z', ""), "b")

def Test.six_hundred() -> IO(Unit):
  +limits = TC.Limits.default()
  do IO<Unit>:
    +incoming : TC.IncomingContext <- Test.incoming(limits, Test.received_600())
    Unit <- Test.forwarded("a 600-octet tracestate is not forwarded under the default budget",
      TC.Context.forward(limits, incoming, []), "refused: too large")
    Unit <- Test.six_hundred_child(limits, incoming)
    wide : TC.Limits <- Test.limits(TC.Limits.new(55n, 1024n, 1024n))
    Test.forward_from("a larger output budget forwards the 600-octet tracestate", wide, Test.received_600(),
      Test.others() ++ "traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01 | tracestate: " ++
        Test.six_hundred_state())

# Forwarding sends an accepted pair as it came (W3C 3.4, "Unmodified header
# propagation"; spec #1): no flag normalization, no version downgrade and no
# change to the tracestate, whose fields are joined into one field
# (W3C 3.3.2). Old context fields are replaced, as by injection.
def Test.forward() -> IO(Unit):
  +limits = TC.Limits.default()
  do IO<Unit>:
    Unit <- Test.forward_from("a later version with unknown fields and every flag bit", limits,
      [TC.Header{"TraceParent", " cc-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-ff-future "},
        TC.Header{"tracestate", "congo=t61rcWkgMzE , rojo=00f067aa0ba902b7"}, TC.Header{"TRACESTATE", ""},
        TC.Header{"tracestate", "vendor= opaque"}],
      Test.others() ++ "traceparent: cc-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-ff-future | " ++
        "tracestate: congo=t61rcWkgMzE , rojo=00f067aa0ba902b7,,vendor= opaque")
    Unit <- Test.forward_from("version 00 keeps its reserved flag bits", limits,
      [TC.Header{"traceparent", "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-fe"}],
      Test.others() ++ "traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-fe")
    Unit <- Test.forward_from("an empty tracestate is not written", limits,
      [TC.Header{"traceparent", "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"}, TC.Header{"tracestate", ""}],
      Test.others() ++ "traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01")
    Unit <- Test.forward_from("a tracestate of exactly 512 octets, joining comma included", limits,
      [TC.Header{"traceparent", "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"},
        TC.Header{"tracestate", "a=" ++ Test.fill(254n, 'x', "")}, TC.Header{"tracestate", "b=" ++ Test.fill(253n, 'y', "")}],
      Test.others() ++ "traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01 | tracestate: a=" ++
        Test.fill(254n, 'x', "") ++ ",b=" ++ Test.fill(253n, 'y', ""))
    Unit <- Test.forward_from("a tracestate of 513 octets is not forwarded", limits,
      [TC.Header{"traceparent", "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"},
        TC.Header{"tracestate", "a=" ++ Test.fill(254n, 'x', "")}, TC.Header{"tracestate", "b=" ++ Test.fill(254n, 'y', "")}],
      "refused: too large")
    Unit <- Test.forward_from("a discarded tracestate leaves nothing to forward", limits,
      [TC.Header{"traceparent", "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"}, TC.Header{"tracestate", "rojo"}],
      "refused: nothing to forward")
    Test.six_hundred()

# A pair built directly carries no guarantee, so forwarding checks it: it
# must be there, fit the output budget and read back (spec #1).
def Test.checked() -> IO(Unit):
  +limits = TC.Limits.default()
  do IO<Unit>:
    +incoming : TC.IncomingContext <- Test.incoming(limits,
      [TC.Header{"traceparent", "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"}])
    Unit <- Test.forwarded("a context without a received pair",
      TC.Context.forward(limits, TC.IncomingContext{TC.IncomingContext.context(incoming), TC.TraceState.empty(), None{}},
        []), "refused: nothing to forward")
    Unit <- Test.forwarded("a traceparent that does not read back",
      TC.Context.forward(limits, TC.IncomingContext{TC.IncomingContext.context(incoming), TC.TraceState.empty(),
        Some{TC.ReceivedPair{"00-4bf92f3577b34da6a3ce929d0e0e4736-0000000000000000-01", []}}}, []),
      "refused: invalid traceparent InvalidTraceParent ZeroParentId")
    Unit <- Test.forwarded("a traceparent with a line break",
      TC.Context.forward(limits, TC.IncomingContext{TC.IncomingContext.context(incoming), TC.TraceState.empty(),
        Some{TC.ReceivedPair{"00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01\r\nx: 1", []}}}, []),
      "refused: invalid traceparent InvalidTraceParent TrailingInput")
    Unit <- Test.forwarded("a later version with a line break in the fields it does not read",
      TC.Context.forward(limits, TC.IncomingContext{TC.IncomingContext.context(incoming), TC.TraceState.empty(),
        Some{TC.ReceivedPair{"cc-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01-x\r\nInjected: 1", []}}}, []),
      "refused: invalid traceparent InvalidTraceParent ControlCharacter at 57")
    Test.forwarded("tracestate fields that do not parse",
      TC.Context.forward(limits, TC.IncomingContext{TC.IncomingContext.context(incoming), TC.TraceState.empty(),
        Some{TC.ReceivedPair{"00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01", ["a=1", "b"]}}}, []),
      "refused: invalid tracestate InvalidEntry 1 MissingEquals")

def Test.forward_ok(result: Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>) -> IO(List<&2, TC.Header>):
  match result:
    case Fail{error}:
      IO.die(List<&2, TC.Header>, 1, "FAIL: forwarding fixture: " ++ Test.forward_error(error))
    case Done{carrier}:
      IO.pure(List<&2, TC.Header>, carrier)

def Test.forward_twice(+limits: TC.Limits, +incoming: TC.IncomingContext, +once: List<&2, TC.Header>) -> IO(Unit):
  Test.forwarded("forwarding twice gives the carrier of one forwarding",
    TC.Context.forward(limits, incoming, once), Test.carrier(once))

# Forwarding the same context again gives the same carrier.
def Test.forward_idempotent() -> IO(Unit):
  +limits = TC.Limits.default()
  do IO<Unit>:
    +incoming : TC.IncomingContext <- Test.incoming(limits,
      [TC.Header{"traceparent", "cc-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-03-x"},
        TC.Header{"tracestate", "congo=1"}, TC.Header{"tracestate", "rojo=2"}])
    once : List<&2, TC.Header> <- Test.forward_ok(TC.Context.forward(limits, incoming, Test.stale()))
    Test.forward_twice(limits, incoming, once)

# The test's own spelling of a flag byte: sampled in bit 0, random-trace-id in
# bit 1.
def Test.flags(sampled: Bool, random: Bool) -> String:
  match sampled random:
    case False{} False{}:
      "00"
    case True{} False{}:
      "01"
    case False{} True{}:
      "02"
    case True{} True{}:
      "03"

def Test.remote(context: TC.RemoteContext) -> String:
  match context:
    case TC.RemoteContext{+trace_id, span_id, sampled}:
      TC.TraceId.to_string(trace_id) ++ "-" ++ TC.SpanId.to_string(span_id) ++ "-" ++
        Test.flags(sampled, TC.TraceId.is_random(trace_id))

def Test.projected(+name: String, +incoming: TC.IncomingContext, sender: String, state: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.assert(name ++ ": the sender", String.eq(Test.remote(TC.IncomingContext.context(incoming)), sender))
    Test.assert(name ++ ": the state", String.eq(TC.TraceState.format(TC.IncomingContext.state(incoming)), state))

# A receiver that extracts what an outgoing context injected recovers its
# trace ID with its randomness assertion, its span ID as the sender's
# operation, its sampled indication and the state it sent (spec #1,
# "Extraction after participant injection recovers the normalized remotely
# observable projection of the local context").
def Test.projection_of(+name: String, +limits: TC.Limits, +outgoing: TC.OutgoingContext, sender: String, state: String) ->
  IO(Unit):
  do IO<Unit>:
    incoming : TC.IncomingContext <- Test.incoming(limits,
      TC.Injection.carrier(TC.Context.inject(limits, outgoing, Test.stale())))
    Test.projected(name, incoming, sender, state)

def Test.projection() -> IO(Unit):
  +limits = TC.Limits.default()
  do IO<Unit>:
    trace : TC.TraceId <- Test.id(TC.TraceId, TC.TraceId.parse("4bf92f3577b34da6a3ce929d0e0e4736"))
    +span : TC.SpanId <- Test.id(TC.SpanId, TC.SpanId.parse("53995c3f42cd8ad8"))
    +random : TC.TraceId <- Test.id(TC.TraceId, TC.TraceId.parse("0af7651916cd43dd8448eb211c80319c"))
    state : TC.TraceState <- Test.state("congo=t61rcWkgMzE , rojo=00f067aa0ba902b7")
    large : TC.TraceState <- Test.state(Test.six_hundred_state())
    Unit <- Test.projection_of("an unsampled root without state", limits,
      TC.OutgoingContext.new(TC.Context.root_from_ids(trace, span, False{})),
      "4bf92f3577b34da6a3ce929d0e0e4736-53995c3f42cd8ad8-00", "")
    Unit <- Test.projection_of("a sampled operation with a random trace ID and a state", limits,
      TC.OutgoingContext.with_state(TC.Context.from_ids(TC.TraceId.assert_random(random), span, True{}), state),
      "0af7651916cd43dd8448eb211c80319c-53995c3f42cd8ad8-03", "congo=t61rcWkgMzE,rojo=00f067aa0ba902b7")
    Test.projection_of("a truncated state", limits,
      TC.OutgoingContext.with_state(TC.Context.from_ids(TC.TraceId.assert_random(random), span, False{}), large),
      "0af7651916cd43dd8448eb211c80319c-53995c3f42cd8ad8-02", "a=" ++ Test.fill(254n, 'x', "") ++ ",c=" ++
        Test.fill(84n, 'z', ""))

# A receiver that extracts a forwarded carrier finds the sender and the state
# that the forwarder received: the trace ID with its randomness assertion,
# the parent ID and the sampled flag of the value, and the first entry of each
# key of the joined fields.
def Test.forwarded_back(+limits: TC.Limits, +incoming: TC.IncomingContext) -> IO(Unit):
  do IO<Unit>:
    +carrier : List<&2, TC.Header> <- Test.forward_ok(TC.Context.forward(limits, incoming, []))
    Unit <- Test.same_carrier("the forwarded fields", carrier,
      "traceparent: cc-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-ff-x | tracestate:  congo=1 , congo=2,rojo=3")
    again : TC.IncomingContext <- Test.incoming(limits, carrier)
    Test.projected("forwarding then extracting", again, "4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-03",
      "congo=1,rojo=3")

def Test.round_trip() -> IO(Unit):
  +limits = TC.Limits.default()
  do IO<Unit>:
    +incoming : TC.IncomingContext <- Test.incoming(limits,
      [TC.Header{"TraceParent", "cc-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-ff-x"},
        TC.Header{"tracestate", " congo=1 , congo=2"}, TC.Header{"TRACESTATE", "rojo=3"}])
    Test.forwarded_back(limits, incoming)

# `count` unrelated fields before `tail`, built by a loop.
def Test.headers(count: Nat, tail: List<&2, TC.Header>) -> List<&2, TC.Header>:
  match count:
    case 0n:
      tail
    case 1n+more:
      Test.headers(more, Con{TC.Header{"x-field", "value"}, tail})

# The number of fields, counted by a loop: Base's List.length recurses once
# per field.
def Test.count(carrier: List<&2, TC.Header>, +count: Nat) -> Nat:
  match carrier:
    case Nil{}:
      count
    case Con{header, rest}:
      Test.count(rest, 1n+count)

def Test.length(carrier: List<&2, TC.Header>) -> Nat:
  Test.count(carrier, 0n)

# Base's String.eq and `++` recurse once per character of their first
# argument, which a 32768-character text takes beyond the JavaScript stack;
# this comparison is a loop.
def Test.same(a: String, b: String, same: Bool) -> Bool:
  match a b:
    case SNil{} SNil{}:
      same
    case SNil{} SCon{y, ys}:
      False{}
    case SCon{x, xs} SNil{}:
      False{}
    case SCon{x, xs} SCon{y, ys}:
      Test.same(xs, ys, Bool.and(same, Char.is_eq(x, y)))

def Test.last_value(carrier: List<&2, TC.Header>) -> String:
  match carrier:
    case Nil{}:
      ""
    case Con{header, Nil{}}:
      TC.Header.value(header)
    case Con{header, rest}:
      Test.last_value(rest)

def Test.first_value(carrier: List<&2, TC.Header>) -> String:
  match carrier:
    case Nil{}:
      ""
    case Con{header, rest}:
      TC.Header.value(header)

# Carriers and values are walked by loops: 100000 fields, a 32768-octet
# traceparent and a 32768-octet tracestate need no deep stack.
def Test.large_carriers(+limits: TC.Limits, +outgoing: TC.OutgoingContext) -> IO(Unit):
  +carrier = Test.headers(100000n, Test.stale())
  do IO<Unit>:
    Unit <- Test.assert("cleanup keeps 100002 other fields", Nat.is_eq(Test.length(TC.Context.clear(carrier)), 100002n))
    Test.assert("injection keeps them and adds the traceparent of a context without state",
      Nat.is_eq(Test.length(TC.Injection.carrier(TC.Context.inject(limits, outgoing, carrier))), 100003n))

def Test.large_sent(+carrier: List<&2, TC.Header>, value: String, field: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.assert("a 32768-octet traceparent is forwarded as it came",
      Test.same(Test.first_value(carrier), value, True{}))
    Test.assert("a 32768-octet tracestate is forwarded as it came", Test.same(Test.last_value(carrier), field, True{}))

def Test.large_forward(+value: String, +field: String) -> IO(Unit):
  do IO<Unit>:
    +wide : TC.Limits <- Test.limits(TC.Limits.new(32768n, 32768n, 32768n))
    +incoming : TC.IncomingContext <- Test.incoming(wide, [TC.Header{"traceparent", value}, TC.Header{"tracestate", field}])
    carrier : List<&2, TC.Header> <- Test.forward_ok(TC.Context.forward(wide, incoming, []))
    Test.large_sent(carrier, value, field)

def Test.large() -> IO(Unit):
  do IO<Unit>:
    trace : TC.TraceId <- Test.id(TC.TraceId, TC.TraceId.parse("4bf92f3577b34da6a3ce929d0e0e4736"))
    span : TC.SpanId <- Test.id(TC.SpanId, TC.SpanId.parse("53995c3f42cd8ad8"))
    Unit <- Test.large_carriers(TC.Limits.default(),
      TC.OutgoingContext.with_state(TC.Context.root_from_ids(trace, span, False{}), TC.TraceState.empty()))
    Test.large_forward("cc-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01-" ++ Test.fill(32712n, 'x', ""),
      "k=v" ++ Test.fill(32765n, ' ', ""))

# Diagnostics name the reason without the received values.
def Test.diagnostics() -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.assert("NothingToForward", String.eq(TC.ForwardError.show(TC.NothingToForward{}), "NothingToForward"))
    Unit <- Test.assert("ForwardTooLarge", String.eq(TC.ForwardError.show(TC.ForwardTooLarge{}), "ForwardTooLarge"))
    Unit <- Test.assert("InvalidForwardParent", String.eq(TC.ForwardError.show(TC.InvalidForwardParent{
      TC.RepeatedTraceParent{}}), "InvalidForwardParent RepeatedTraceParent"))
    Test.assert("InvalidForwardState", String.eq(TC.ForwardError.show(TC.InvalidForwardState{TC.TooManyMembers{}}),
      "InvalidForwardState TooManyMembers"))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.clear()
    Unit <- IO.print("OK: explicit cleanup of context fields")
    Unit <- Test.inject()
    Unit <- Test.twice()
    Unit <- IO.print("OK: participant injection")
    Unit <- Test.forward()
    Unit <- Test.checked()
    Unit <- Test.forward_idempotent()
    Unit <- IO.print("OK: transparent forwarding")
    Unit <- Test.projection()
    Unit <- Test.round_trip()
    Unit <- IO.print("OK: extraction after injection and after forwarding")
    Unit <- Test.large()
    Unit <- IO.print("OK: large carriers and values")
    Unit <- Test.diagnostics()
    IO.print("OK: forwarding diagnostics")
