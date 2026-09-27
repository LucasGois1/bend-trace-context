import Base
import ../trace_context.bend as TC

# Context extraction through the public API. Expected values are literal
# fixtures written from W3C Trace Context Level 2 (sections 3.2, 3.3 and 4.1),
# the pinned W3C test harness and the approved policy of spec #1, not
# recomputed by package helpers.
def Test.assert(name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "FAIL: " ++ name)

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

def Test.local(context: TC.LocalContext) -> String:
  match context:
    case TC.LocalContext{+trace_id, span_id, sampled}:
      TC.TraceId.to_string(trace_id) ++ "-" ++ TC.SpanId.to_string(span_id) ++ "-" ++
        Test.flags(sampled, TC.TraceId.is_random(trace_id))

def Test.fields.rest(fields: List<&2, String>) -> String:
  match fields:
    case Nil{}:
      ""
    case Con{field, rest}:
      "|" ++ field ++ Test.fields.rest(rest)

# The received tracestate fields, separated by "|" so that the fields stay
# visible; "none" for no field.
def Test.fields(fields: List<&2, String>) -> String:
  match fields:
    case Nil{}:
      "none"
    case Con{field, rest}:
      field ++ Test.fields.rest(rest)

def Test.received(received: Maybe<&2, TC.ReceivedPair>) -> String:
  match received:
    case None{}:
      "not forwardable"
    case Some{TC.ReceivedPair{traceparent, tracestate}}:
      "[" ++ traceparent ++ "] [" ++ Test.fields(tracestate) ++ "]"

def Test.context(context: Maybe<&2, TC.BaseContext>) -> String:
  match context:
    case None{}:
      "none"
    case Some{TC.OutgoingBase{TC.OutgoingContext{local, state}}}:
      "outgoing " ++ Test.local(local) ++ " state " ++ TC.TraceState.format(state)
    case Some{TC.IncomingBase{TC.IncomingContext{remote, state, received}}}:
      "incoming " ++ Test.remote(remote) ++ " state " ++ TC.TraceState.format(state) ++ " received " ++
        Test.received(received)

def Test.parent_error(error: TC.TraceParentError) -> String:
  match error:
    case TC.RepeatedTraceParent{}:
      "repeated"
    case TC.TraceParentTooLarge{}:
      "too large"
    case TC.InvalidTraceParent{error}:
      "invalid " ++ TC.Error.show(error)

def Test.parent(outcome: TC.TraceParentOutcome) -> String:
  match outcome:
    case TC.TraceParentAccepted{}:
      "accepted"
    case TC.TraceParentAbsent{}:
      "absent"
    case TC.TraceParentRejected{error}:
      "rejected " ++ Test.parent_error(error)

def Test.state(outcome: TC.StateOutcome) -> String:
  match outcome:
    case TC.StateAbsent{}:
      "absent"
    case TC.StateAccepted{}:
      "accepted"
    case TC.StateDiscarded{error}:
      "discarded " ++ TC.StateError.show(error)
    case TC.StateIgnored{}:
      "ignored"

def Test.extracted(+name: String, +extraction: TC.Extraction, context: String, parent: String, state: String) ->
  IO(Unit):
  do IO<Unit>:
    Unit <- Test.assert(name ++ ": the context, got " ++ Test.context(TC.Extraction.context(extraction)),
      String.eq(Test.context(TC.Extraction.context(extraction)), context))
    Unit <- Test.assert(name ++ ": the traceparent outcome, got " ++ Test.parent(TC.Extraction.parent(extraction)),
      String.eq(Test.parent(TC.Extraction.parent(extraction)), parent))
    Test.assert(name ++ ": the tracestate outcome, got " ++ Test.state(TC.Extraction.state(extraction)),
      String.eq(Test.state(TC.Extraction.state(extraction)), state))

# Extract `carrier` with the default limits and no base.
def Test.extract(name: String, carrier: List<&2, TC.Header>, context: String, parent: String, state: String) ->
  IO(Unit):
  Test.extracted(name, TC.Context.extract(TC.Limits.default(), carrier, None{}), context, parent, state)

def Test.id(-A: Data, result: Result<&2, &2, TC.Error, A>) -> IO(A):
  match result:
    case Fail{error}:
      IO.die(A, 1, "FAIL: ID fixture: " ++ TC.Error.show(error))
    case Done{value}:
      IO.pure(A, value)

# An outgoing context to keep as the base: a local root with no state.
def Test.base() -> IO(TC.BaseContext):
  do IO<TC.BaseContext>:
    trace : TC.TraceId <- Test.id(TC.TraceId, TC.TraceId.parse("5b8efff798038103d269b633813fc60c"))
    span : TC.SpanId <- Test.id(TC.SpanId, TC.SpanId.parse("eee19b7ec3c1b174"))
    return TC.OutgoingBase{TC.OutgoingContext.new(TC.Context.root_from_ids(trace, span))}

def Test.w3c() -> String:
  "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

def Test.accepted_w3c() -> String:
  "incoming 4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01 state  received [" ++ Test.w3c() ++ "] [none]"

# A message's own context takes precedence over the base; without a
# traceparent, or with a refused one, the base is kept as it was.
def Test.precedence() -> IO(Unit):
  do IO<Unit>:
    +base : TC.BaseContext <- Test.base()
    Unit <- Test.extract("no field", [], "none", "absent", "absent")
    Unit <- Test.extract("unrelated fields only", [TC.Header{"content-type", "application/json"}], "none", "absent",
      "absent")
    Unit <- Test.extract("the W3C example", [TC.Header{"traceparent", Test.w3c()}], Test.accepted_w3c(), "accepted",
      "absent")
    Unit <- Test.extracted("no traceparent keeps the base",
      TC.Context.extract(TC.Limits.default(), [TC.Header{"accept", "*/*"}], Some{base}),
      "outgoing 5b8efff798038103d269b633813fc60c-eee19b7ec3c1b174-00 state ", "absent", "absent")
    Unit <- Test.extracted("a refused traceparent keeps the base",
      TC.Context.extract(TC.Limits.default(),
        [TC.Header{"traceparent", "00-00000000000000000000000000000000-00f067aa0ba902b7-01"}], Some{base}),
      "outgoing 5b8efff798038103d269b633813fc60c-eee19b7ec3c1b174-00 state ", "rejected invalid ZeroTraceId",
      "absent")
    Test.extracted("an accepted traceparent replaces the base",
      TC.Context.extract(TC.Limits.default(), [TC.Header{"traceparent", Test.w3c()}], Some{base}),
      Test.accepted_w3c(), "accepted", "absent")

def Test.harness() -> String:
  "00-12345678901234567890123456789012-1234567890123456-01"

def Test.accepted_harness() -> String:
  "incoming 12345678901234567890123456789012-1234567890123456-01 state  received [" ++ Test.harness() ++ "] [none]"

# Field names are compared without regard to ASCII case (W3C 3.2.1): only
# the letters A to Z are folded, and a name with any other difference names
# another field (as in the harness's test_traceparent_header_name).
def Test.names() -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.extract("TraceParent", [TC.Header{"TraceParent", Test.harness()}], Test.accepted_harness(),
      "accepted", "absent")
    Unit <- Test.extract("TRACEPARENT", [TC.Header{"TRACEPARENT", Test.harness()}], Test.accepted_harness(),
      "accepted", "absent")
    Unit <- Test.extract("tRaCePaReNt", [TC.Header{"tRaCePaReNt", Test.harness()}], Test.accepted_harness(),
      "accepted", "absent")
    Unit <- Test.extract("trace-parent is another field", [TC.Header{"trace-parent", Test.harness()}], "none",
      "absent", "absent")
    Unit <- Test.extract("trace.parent is another field", [TC.Header{"trace.parent", Test.harness()}], "none",
      "absent", "absent")
    Unit <- Test.extract("a longer name is another field", [TC.Header{"traceparents", Test.harness()}], "none",
      "absent", "absent")
    Unit <- Test.extract("a shorter name is another field", [TC.Header{"traceparen", Test.harness()}], "none",
      "absent", "absent")
    Unit <- Test.extract("a trailing space makes another name", [TC.Header{"traceparent ", Test.harness()}], "none",
      "absent", "absent")
    Test.extract("the empty name is another field", [TC.Header{"", Test.harness()}], "none", "absent", "absent")

# More than one traceparent field is refused (W3C harness,
# test_traceparent_duplicated; spec #1), whatever the values and their names'
# case. A host that joined repeated fields into one value with commas (RFC
# 9110, section 5.3) is refused the same way.
def Test.repeated() -> IO(Unit):
  do IO<Unit>:
    +base : TC.BaseContext <- Test.base()
    Unit <- Test.extract("two traceparent fields", [
      TC.Header{"traceparent", "00-12345678901234567890123456789011-1234567890123456-01"},
      TC.Header{"traceparent", "00-12345678901234567890123456789012-1234567890123456-01"}],
      "none", "rejected repeated", "absent")
    Unit <- Test.extract("the same value twice", [TC.Header{"traceparent", Test.w3c()},
      TC.Header{"traceparent", Test.w3c()}], "none", "rejected repeated", "absent")
    Unit <- Test.extract("two names that differ in case", [TC.Header{"TraceParent", Test.w3c()},
      TC.Header{"traceparent", Test.w3c()}], "none", "rejected repeated", "absent")
    Unit <- Test.extract("an invalid field before a valid one", [TC.Header{"traceparent", "invalid"},
      TC.Header{"traceparent", Test.w3c()}], "none", "rejected repeated", "absent")
    Unit <- Test.extract("repeated fields apart", [TC.Header{"traceparent", Test.w3c()},
      TC.Header{"accept", "*/*"}, TC.Header{"TRACEPARENT", Test.w3c()}], "none", "rejected repeated", "absent")
    Unit <- Test.extract("three fields", [TC.Header{"traceparent", Test.w3c()}, TC.Header{"traceparent", Test.w3c()},
      TC.Header{"traceparent", Test.w3c()}], "none", "rejected repeated", "absent")
    Unit <- Test.extract("two values joined by a host", [TC.Header{"traceparent", Test.w3c() ++ ", " ++ Test.w3c()}],
      "none", "rejected repeated", "absent")
    Unit <- Test.extract("two values joined without a space", [TC.Header{"traceparent", Test.w3c() ++ "," ++
      Test.harness()}], "none", "rejected repeated", "absent")
    Unit <- Test.extract("a joined value with a future version and an extension", [TC.Header{"traceparent",
      "cc-12345678901234567890123456789012-1234567890123456-01-ext, " ++ Test.harness()}],
      "none", "rejected repeated", "absent")
    Test.extracted("repeated fields keep the base",
      TC.Context.extract(TC.Limits.default(), [TC.Header{"traceparent", Test.w3c()},
        TC.Header{"traceparent", Test.w3c()}], Some{base}),
      "outgoing 5b8efff798038103d269b633813fc60c-eee19b7ec3c1b174-00 state ", "rejected repeated", "absent")

# The context extracted from `harness()` with the state `state` and the
# received tracestate fields `fields`, as Test.context writes it.
def Test.with_state(state: String, fields: String) -> String:
  "incoming 12345678901234567890123456789012-1234567890123456-01 state " ++ state ++ " received [" ++
    Test.harness() ++ "] [" ++ fields ++ "]"

# `harness()` followed by tracestate fields with these values.
def Test.carrier.rest(values: List<&2, String>) -> List<&2, TC.Header>:
  match values:
    case Nil{}:
      Nil{}
    case Con{value, rest}:
      Con{TC.Header{"tracestate", value}, Test.carrier.rest(rest)}

def Test.carrier(values: List<&2, String>) -> List<&2, TC.Header>:
  Con{TC.Header{"traceparent", Test.harness()}, Test.carrier.rest(values)}

def Test.members.rest(count: Nat, +index: Nat) -> String:
  match count:
    case 0n:
      ""
    case 1n+more:
      ",k" ++ Nat.show(index) ++ "=v" ++ Test.members.rest(more, 1n+index)

# `count` members `k<i>=v`, numbered from `first`, joined by commas.
def Test.members(count: Nat, +first: Nat) -> String:
  match count:
    case 0n:
      ""
    case 1n+more:
      "k" ++ Nat.show(first) ++ "=v" ++ Test.members.rest(more, 1n+first)

# Repeated tracestate fields are read in arrival order as their comma-joined
# combination, whatever the case of their names (W3C 3.3.1 and 3.3.2; the
# harness's test_tracestate_multiple_headers_different_keys and
# test_tracestate_empty_header). The received fields are kept as they came.
def Test.state_fields() -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.extract("one field", Test.carrier(["foo=1,bar=2"]), Test.with_state("foo=1,bar=2", "foo=1,bar=2"),
      "accepted", "accepted")
    Unit <- Test.extract("three fields in arrival order", Test.carrier(["foo=1,bar=2", "rojo=1,congo=2", "baz=3"]),
      Test.with_state("foo=1,bar=2,rojo=1,congo=2,baz=3", "foo=1,bar=2|rojo=1,congo=2|baz=3"), "accepted",
      "accepted")
    Unit <- Test.extract("names that differ in case", [TC.Header{"TraceState", "a=1"},
      TC.Header{"traceparent", Test.harness()}, TC.Header{"tracestate", "b=2"}, TC.Header{"TRACESTATE", "a=3"}],
      Test.with_state("a=1,b=2", "a=1|b=2|a=3"), "accepted", "accepted")
    Unit <- Test.extract("values joined by a host", Test.carrier(["foo=1, bar=2"]),
      Test.with_state("foo=1,bar=2", "foo=1, bar=2"), "accepted", "accepted")
    Unit <- Test.extract("optional whitespace around members", Test.carrier(["foo=1 \t , \t bar=2, \t baz=3"]),
      Test.with_state("foo=1,bar=2,baz=3", "foo=1 \t , \t bar=2, \t baz=3"), "accepted", "accepted")
    Unit <- Test.extract("an empty field", Test.carrier([""]), Test.with_state("", ""), "accepted", "accepted")
    Unit <- Test.extract("an empty field after a member", Test.carrier(["foo=1", ""]),
      Test.with_state("foo=1", "foo=1|"), "accepted", "accepted")
    Unit <- Test.extract("an empty field before a member", Test.carrier(["", "foo=1"]),
      Test.with_state("foo=1", "|foo=1"), "accepted", "accepted")
    Unit <- Test.extract("the first entry of a key wins across fields", Test.carrier(["foo=1", "foo=2"]),
      Test.with_state("foo=1", "foo=1|foo=2"), "accepted", "accepted")
    Unit <- Test.extract("32 members across fields", Test.carrier([Test.members(10n, 1n), Test.members(22n, 11n)]),
      Test.with_state(Test.members(32n, 1n), Test.members(10n, 1n) ++ "|" ++ Test.members(22n, 11n)), "accepted",
      "accepted")
    Unit <- Test.extract("a long s does not fold to s", [TC.Header{"traceparent", Test.harness()},
      TC.Header{"trace\u{17f}tate", "a=1"}], Test.accepted_harness(), "accepted", "absent")
    Unit <- Test.extract("trace-state is another field", [TC.Header{"traceparent", Test.harness()},
      TC.Header{"trace-state", "a=1"}], Test.accepted_harness(), "accepted", "absent")
    Test.extract("trace.state is another field", [TC.Header{"traceparent", Test.harness()},
      TC.Header{"trace.state", "a=1"}], Test.accepted_harness(), "accepted", "absent")

# `count` copies of a character before `tail`, built by a loop.
def Test.fill(count: Nat, +char: Char, tail: String) -> String:
  match count:
    case 0n:
      tail
    case 1n+more:
      Test.fill(more, char, SCon{char, tail})

# An invalid or oversized tracestate is discarded as a whole, and the valid
# traceparent stays accepted (W3C 3.3; spec #1). A discarded pair cannot be
# forwarded unchanged.
def Test.discarded() -> IO(Unit):
  +discarded : String = "incoming 12345678901234567890123456789012-1234567890123456-01 state  received not forwardable"
  do IO<Unit>:
    Unit <- Test.extract("a value with two equals signs", Test.carrier(["foo=bar=baz"]), discarded, "accepted",
      "discarded InvalidEntry 0 InvalidValue")
    Unit <- Test.extract("an empty value", Test.carrier(["foo=,bar=3"]), discarded, "accepted",
      "discarded InvalidEntry 0 InvalidValue")
    Unit <- Test.extract("a 257-character key in a second field",
      Test.carrier(["foo=1", String.repeat("z", 257n) ++ "=1"]), discarded, "accepted",
      "discarded InvalidEntry 1 InvalidKey")
    Unit <- Test.extract("an uppercase key", Test.carrier(["FOO=1"]), discarded, "accepted",
      "discarded InvalidEntry 0 InvalidKey")
    Unit <- Test.extract("33 members across fields",
      Test.carrier([Test.members(10n, 1n), Test.members(10n, 11n), Test.members(13n, 21n)]), discarded, "accepted",
      "discarded TooManyMembers")
    Test.extract("a field past the input budget", Test.carrier([Test.fill(32769n, 'a', "")]), discarded, "accepted",
      "discarded StateTooLarge")

# Without an accepted traceparent the tracestate is not read (W3C 3.3 and
# 4.1.1): only its presence is reported, and the base stays.
def Test.ignored() -> IO(Unit):
  do IO<Unit>:
    +base : TC.BaseContext <- Test.base()
    Unit <- Test.extract("a tracestate alone", [TC.Header{"tracestate", "foo=1"}], "none", "absent", "ignored")
    Unit <- Test.extract("an invalid tracestate alone is not read", [TC.Header{"tracestate", "not a member"}], "none",
      "absent", "ignored")
    Unit <- Test.extract("a tracestate after a refused traceparent", [
      TC.Header{"traceparent", "00-00000000000000000000000000000000-1234567890123456-01"},
      TC.Header{"tracestate", "foo=1"}], "none", "rejected invalid ZeroTraceId", "ignored")
    Unit <- Test.extract("a tracestate with repeated traceparent fields", [TC.Header{"traceparent", Test.w3c()},
      TC.Header{"traceparent", Test.w3c()}, TC.Header{"tracestate", "foo=1"}], "none", "rejected repeated",
      "ignored")
    Test.extracted("a tracestate alone keeps the base",
      TC.Context.extract(TC.Limits.default(), [TC.Header{"tracestate", "foo=1"}], Some{base}),
      "outgoing 5b8efff798038103d269b633813fc60c-eee19b7ec3c1b174-00 state ", "absent", "ignored")

# The context extracted from a single traceparent value `value`, which the
# message sent as it is.
def Test.from_value(value: String, context: String) -> String:
  "incoming " ++ context ++ " state  received [" ++ value ++ "] [none]"

def Test.accepts(name: String, +value: String, context: String) -> IO(Unit):
  Test.extract(name, [TC.Header{"traceparent", value}], Test.from_value(value, context), "accepted", "absent")

def Test.refuses(name: String, value: String, error: String) -> IO(Unit):
  Test.extract(name, [TC.Header{"traceparent", value}], "none", "rejected invalid " ++ error, "absent")

# The IDs of the harness's fixtures, after the version.
def Test.ids() -> String:
  "-12345678901234567890123456789012-1234567890123456-"

# Version 00 is read strictly, exactly 55 characters; version ff is
# forbidden; any other version is read by its known prefix, which may be
# followed by a dash and fields that are not read, other than to refuse a
# comma or a control character (W3C 3.2.2.1, 3.2.4 and 4.1.2; the harness's
# test_traceparent_version_* tests; RFC 9110, section 5.5). Offsets count
# from the start of the value.
def Test.versions() -> IO(Unit):
  +known : String = "12345678901234567890123456789012-1234567890123456-01"
  do IO<Unit>:
    Unit <- Test.accepts("a future version", "cc" ++ Test.ids() ++ "01", known)
    Unit <- Test.accepts("a future version with fields it does not know",
      "cc" ++ Test.ids() ++ "01-what-the-future-will-be-like", known)
    Unit <- Test.accepts("the lowest future version", "01" ++ Test.ids() ++ "01", known)
    Unit <- Test.accepts("the highest future version", "fe" ++ Test.ids() ++ "01", known)
    Unit <- Test.accepts("a dash with nothing after it", "cc" ++ Test.ids() ++ "01-", known)
    Unit <- Test.accepts("unknown fields are not read, whatever characters other than a comma they hold",
      "cc" ++ Test.ids() ++ "01-\u{e9}t\u{e9}", known)
    Unit <- Test.accepts("whitespace inside unknown fields is kept",
      "cc" ++ Test.ids() ++ "01-a b\tc", known)
    Unit <- Test.extract("a comma inside unknown fields makes repeated fields",
      [TC.Header{"traceparent", "cc" ++ Test.ids() ++ "01-a,b"}], "none", "rejected repeated", "absent")
    Unit <- Test.refuses("a line break inside unknown fields, which would end the field when sent",
      "cc" ++ Test.ids() ++ "01-x\r\ny: 1", "ControlCharacter at 57")
    Unit <- Test.refuses("a null character inside unknown fields", "cc" ++ Test.ids() ++ "01-\u{0}",
      "ControlCharacter at 56")
    Unit <- Test.refuses("the control character before a tab", "cc" ++ Test.ids() ++ "01-a\u{8}",
      "ControlCharacter at 57")
    Unit <- Test.refuses("the control character after a tab", "cc" ++ Test.ids() ++ "01-a\tb\u{a}c",
      "ControlCharacter at 59")
    Unit <- Test.refuses("the control character before a space", "cc" ++ Test.ids() ++ "01-\u{1f}",
      "ControlCharacter at 56")
    Unit <- Test.refuses("delete inside unknown fields", "cc" ++ Test.ids() ++ "01-a-\u{7f}", "ControlCharacter at 58")
    Unit <- Test.refuses("only the first control character is reported", "cc" ++ Test.ids() ++ "01-\u{1}\u{2}",
      "ControlCharacter at 56")
    Unit <- Test.extract("a comma comes before a control character",
      [TC.Header{"traceparent", "cc" ++ Test.ids() ++ "01-,\r"}], "none", "rejected repeated", "absent")
    Unit <- Test.accepts("a tilde and characters past delete are not control characters",
      "cc" ++ Test.ids() ++ "01-~\u{80}\u{a0}", known)
    Unit <- Test.accepts("a future version keeps only the known flags", "cc" ++ Test.ids() ++ "ff",
      "12345678901234567890123456789012-1234567890123456-03")
    Unit <- Test.accepts("a future version with random-trace-id", "cc" ++ Test.ids() ++ "02",
      "12345678901234567890123456789012-1234567890123456-02")
    Unit <- Test.refuses("a future version followed by another character",
      "cc" ++ Test.ids() ++ "01.what-the-future-will-be-like", "ExpectedSeparator at 55")
    Unit <- Test.refuses("version 00 followed by fields", "00" ++ Test.ids() ++ "01-what-the-future-will-be-like",
      "TrailingInput")
    Unit <- Test.refuses("version 00 followed by another character", "00" ++ Test.ids() ++ "01.", "TrailingInput")
    Unit <- Test.refuses("version ff", "ff" ++ Test.ids() ++ "01", "ForbiddenVersion")
    Unit <- Test.refuses("version ff with fields", "ff" ++ Test.ids() ++ "01-future", "ForbiddenVersion")
    Unit <- Test.refuses("an uppercase version", "CC" ++ Test.ids() ++ "01", "InvalidHex at 0")
    Unit <- Test.refuses("a version with an illegal first character", ".0" ++ Test.ids() ++ "01", "InvalidHex at 0")
    Unit <- Test.refuses("a version with an illegal second character", "0." ++ Test.ids() ++ "01", "InvalidHex at 1")
    Unit <- Test.refuses("a three-digit version", "000" ++ Test.ids() ++ "01", "ExpectedSeparator at 2")
    Unit <- Test.refuses("a four-digit future version", "cccc" ++ Test.ids() ++ "01", "ExpectedSeparator at 2")
    Unit <- Test.refuses("a one-digit version", "0" ++ Test.ids() ++ "01", "InvalidHex at 1")
    Unit <- Test.refuses("a future version one character short", "cc" ++ Test.ids() ++ "0", "UnexpectedEnd at 54")
    Unit <- Test.refuses("a future version alone", "cc", "UnexpectedEnd at 2")
    Unit <- Test.refuses("the empty value", "", "UnexpectedEnd at 0")
    Unit <- Test.refuses("a future version with a zero trace ID",
      "cc-00000000000000000000000000000000-1234567890123456-01", "ZeroTraceId")
    Unit <- Test.refuses("a future version with a zero parent ID",
      "cc-12345678901234567890123456789012-0000000000000000-01", "ZeroParentId")
    Unit <- Test.refuses("a future version with an uppercase ID",
      "cc-1234567890123456789012345678901A-1234567890123456-01", "InvalidHex at 34")
    Unit <- Test.refuses("a trace ID one digit too long", "00-123456789012345678901234567890123-1234567890123456-01",
      "ExpectedSeparator at 35")
    Unit <- Test.refuses("a future trace ID one digit too long",
      "cc-123456789012345678901234567890123-1234567890123456-01", "ExpectedSeparator at 35")
    Unit <- Test.refuses("a trace ID one digit too short", "00-1234567890123456789012345678901-1234567890123456-01",
      "InvalidHex at 34")
    Unit <- Test.refuses("a parent ID one digit too long", "00-12345678901234567890123456789012-12345678901234567-01",
      "ExpectedSeparator at 52")
    Unit <- Test.refuses("flags one digit too long", "00" ++ Test.ids() ++ "001", "TrailingInput")
    Unit <- Test.refuses("future flags one digit too long", "cc" ++ Test.ids() ++ "001", "ExpectedSeparator at 55")
    Unit <- Test.refuses("flags one digit too short", "00" ++ Test.ids() ++ "1", "UnexpectedEnd at 54")
    Test.refuses("illegal flags", "00" ++ Test.ids() ++ ".0", "InvalidHex at 53")

# Optional whitespace around a traceparent value is not part of it (RFC 9110,
# section 5.5; the harness's test_traceparent_ows_handling): it is removed
# before the value is read, and the received pair keeps the value without it.
# Whitespace inside the value is refused.
def Test.ows() -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.extract("a leading space", [TC.Header{"traceparent", " " ++ Test.harness()}],
      Test.accepted_harness(), "accepted", "absent")
    Unit <- Test.extract("a leading tab", [TC.Header{"traceparent", "\t" ++ Test.harness()}],
      Test.accepted_harness(), "accepted", "absent")
    Unit <- Test.extract("a trailing space", [TC.Header{"traceparent", Test.harness() ++ " "}],
      Test.accepted_harness(), "accepted", "absent")
    Unit <- Test.extract("a trailing tab", [TC.Header{"traceparent", Test.harness() ++ "\t"}],
      Test.accepted_harness(), "accepted", "absent")
    Unit <- Test.extract("whitespace on both sides", [TC.Header{"traceparent", "\t " ++ Test.harness() ++ " \t"}],
      Test.accepted_harness(), "accepted", "absent")
    Unit <- Test.extract("whitespace after unknown fields",
      [TC.Header{"traceparent", "cc" ++ Test.ids() ++ "01-future \t "}],
      Test.from_value("cc" ++ Test.ids() ++ "01-future", "12345678901234567890123456789012-1234567890123456-01"),
      "accepted", "absent")
    Unit <- Test.refuses("whitespace inside the value", "00" ++ Test.ids() ++ " 01", "InvalidHex at 53")
    Unit <- Test.refuses("a newline is not optional whitespace", Test.harness() ++ "\n", "TrailingInput")
    Unit <- Test.refuses("only whitespace", " \t ", "UnexpectedEnd at 0")
    Test.refuses("offsets count after leading whitespace", "  00-1234567890123456789012345678901G" ++
      "-1234567890123456-01", "InvalidHex at 34")

def Test.limits(result: Result<&2, &2, TC.LimitsError, TC.Limits>) -> IO(TC.Limits):
  match result:
    case Fail{error}:
      IO.die(TC.Limits, 1, "FAIL: limits fixture: " ++ TC.LimitsError.show(error))
    case Done{limits}:
      IO.pure(TC.Limits, limits)

def Test.extract_with(name: String, limits: TC.Limits, carrier: List<&2, TC.Header>, context: String, parent: String,
  state: String) -> IO(Unit):
  Test.extracted(name, TC.Context.extract(limits, carrier, None{}), context, parent, state)

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

def Test.kept(received: Maybe<&2, TC.ReceivedPair>) -> String:
  match received:
    case None{}:
      ""
    case Some{pair}:
      TC.ReceivedPair.traceparent(pair)

def Test.received_text(incoming: Maybe<&2, TC.IncomingContext>) -> String:
  match incoming:
    case None{}:
      ""
    case Some{context}:
      Test.kept(TC.IncomingContext.received(context))

# A long value is accepted and kept exactly as received.
def Test.accepts_long(+name: String, +value: String) -> IO(Unit):
  +extraction = TC.Context.extract(TC.Limits.default(), [TC.Header{"traceparent", value}], None{})
  do IO<Unit>:
    Unit <- Test.assert(name ++ ": accepted", String.eq(Test.parent(TC.Extraction.parent(extraction)), "accepted"))
    Test.assert(name ++ ": kept as received",
      Test.same(Test.received_text(TC.Extraction.incoming(extraction)), value, True{}))

# A future-version value of exactly `size` octets: the known prefix, a dash
# and `size - 56` characters of unknown fields.
def Test.sized(size: Nat) -> String:
  "cc" ++ Test.ids() ++ "01-" ++ Test.fill(Nat.sub(size, 56n), 'x', "")

# The traceparent value is measured in UTF-8 octets, whitespace and unknown
# fields included, against its own input budget, before it is read (spec #1).
# The tracestate budget is separate: a state over its budget is discarded and
# the traceparent stays.
def Test.budgets() -> IO(Unit):
  do IO<Unit>:
    +tight : TC.Limits <- Test.limits(TC.Limits.new(55n, 512n, 512n))
    Unit <- Test.extract_with("a 55-octet value within a 55-octet budget", tight,
      [TC.Header{"traceparent", Test.harness()}], Test.accepted_harness(), "accepted", "absent")
    Unit <- Test.extract_with("one space over a 55-octet budget", tight,
      [TC.Header{"traceparent", Test.harness() ++ " "}], "none", "rejected too large", "absent")
    +roomy : TC.Limits <- Test.limits(TC.Limits.new(56n, 512n, 512n))
    Unit <- Test.extract_with("the same value within a 56-octet budget", roomy,
      [TC.Header{"traceparent", Test.harness() ++ " "}], Test.accepted_harness(), "accepted", "absent")
    Unit <- Test.extract_with("a two-octet character in unknown fields at the budget", roomy,
      [TC.Header{"traceparent", "cc" ++ Test.ids() ++ "01\u{e9}"}], "none", "rejected too large", "absent")
    Unit <- Test.accepts_long("a value of exactly 32768 octets", Test.sized(32768n))
    Unit <- Test.extract("a value of 32769 octets", [TC.Header{"traceparent", Test.sized(32769n)}], "none",
      "rejected too large", "absent")
    Unit <- Test.extract("a mebibyte value is refused without being read",
      [TC.Header{"traceparent", Test.fill(1048576n, 'x', "")}], "none", "rejected too large", "absent")
    Unit <- Test.extract("a three-octet character one octet over the budget",
      [TC.Header{"traceparent", Test.sized(32766n) ++ "\u{20ac}"}], "none", "rejected too large", "absent")
    Unit <- Test.accepts_long("a three-octet character at the budget", Test.sized(32765n) ++ "\u{20ac}")
    Unit <- Test.extract("a state at its budget", Test.carrier(["a=" ++ Test.fill(32766n, 'v', "")]),
      "incoming 12345678901234567890123456789012-1234567890123456-01 state  received not forwardable",
      "accepted", "discarded InvalidEntry 0 InvalidValue")
    Unit <- Test.extract_with("a state one octet past its budget keeps the traceparent", tight,
      Test.carrier(["a=1", Test.fill(509n, ' ', "")]),
      "incoming 12345678901234567890123456789012-1234567890123456-01 state  received not forwardable",
      "accepted", "discarded StateTooLarge")
    Test.extract_with("a state at its budget, joining comma included", tight,
      Test.carrier(["a=1", Test.fill(508n, ' ', "")]), Test.with_state("a=1", "a=1|" ++ Test.fill(508n, ' ', "")),
      "accepted", "accepted")

def Test.or_die(-A: Data, name: String, value: Maybe<&2, A>) -> IO(A):
  match value:
    case None{}:
      IO.die(A, 1, "FAIL: " ++ name ++ ": nothing")
    case Some{found}:
      IO.pure(A, found)

def Test.context_of(result: Result<&2, &2, TC.ContextError, TC.LocalContext>) -> IO(TC.LocalContext):
  match result:
    case Fail{error}:
      IO.die(TC.LocalContext, 1, "FAIL: child fixture: " ++ TC.ContextError.show(error))
    case Done{context}:
      IO.pure(TC.LocalContext, context)

def Test.span(parent: TC.Parent) -> String:
  TC.SpanId.to_string(TC.Parent.span_id(parent))

# A child of the received context sends the received state with its own
# traceparent.
def Test.child(child: TC.LocalContext, state: TC.TraceState) -> IO(Unit):
  +emission = TC.OutgoingContext.emit(TC.Limits.default(), TC.OutgoingContext.with_state(child, state))
  do IO<Unit>:
    Unit <- Test.assert("a child continues the received trace",
      String.eq(TC.Emission.traceparent(emission), "00-4bf92f3577b34da6a3ce929d0e0e4736-53995c3f42cd8ad8-01"))
    Test.assert("a child sends the received state, normalized",
      String.eq(TC.Emission.tracestate(emission), "congo=t61rcWkgMzE,rojo=00f067aa0ba902b7"))

# An incoming context gives the sender's operation, the state received with
# it and the original pair; it continues as the parent of a child, which
# carries the received state. A base, incoming or outgoing, gives its parent
# and its state the same way.
def Test.incoming(+incoming: TC.IncomingContext, +base: TC.BaseContext) -> IO(Unit):
  +kept = TC.Context.extract(TC.Limits.default(), [TC.Header{"accept", "*/*"}], Some{TC.IncomingBase{incoming}})
  do IO<Unit>:
    Unit <- Test.assert("the sender's operation",
      String.eq(Test.remote(TC.IncomingContext.context(incoming)), "4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"))
    Unit <- Test.assert("the state received",
      String.eq(TC.TraceState.format(TC.IncomingContext.state(incoming)), "congo=t61rcWkgMzE,rojo=00f067aa0ba902b7"))
    +pair : TC.ReceivedPair <- Test.or_die(TC.ReceivedPair, "the received pair", TC.IncomingContext.received(incoming))
    Unit <- Test.assert("the received traceparent", String.eq(TC.ReceivedPair.traceparent(pair), Test.w3c()))
    Unit <- Test.assert("the received tracestate fields, as they came",
      String.eq(Test.fields(TC.ReceivedPair.tracestate(pair)), "congo=t61rcWkgMzE| rojo=00f067aa0ba902b7 "))
    Unit <- Test.assert("the parent of a child", String.eq(Test.span(TC.IncomingContext.parent(incoming)),
      "00f067aa0ba902b7"))
    Unit <- Test.assert("a message without a context keeps an incoming base",
      String.eq(Test.context(TC.Extraction.context(kept)), Test.context(Some{TC.IncomingBase{incoming}})))
    Unit <- Test.assert("the kept base is not this message's context",
      Maybe.is_none(&2, TC.IncomingContext, TC.Extraction.incoming(kept)))
    Unit <- Test.assert("an incoming base continues from the received operation",
      String.eq(Test.span(TC.BaseContext.parent(TC.IncomingBase{incoming})), "00f067aa0ba902b7"))
    Unit <- Test.assert("an incoming base carries the received state",
      String.eq(TC.TraceState.format(TC.BaseContext.state(TC.IncomingBase{incoming})),
        "congo=t61rcWkgMzE,rojo=00f067aa0ba902b7"))
    Unit <- Test.assert("an outgoing base continues from the local operation",
      String.eq(Test.span(TC.BaseContext.parent(base)), "eee19b7ec3c1b174"))
    Unit <- Test.assert("an outgoing base carries its state", TC.TraceState.is_empty(TC.BaseContext.state(base)))
    span : TC.SpanId <- Test.id(TC.SpanId, TC.SpanId.parse("53995c3f42cd8ad8"))
    child : TC.LocalContext <- Test.context_of(TC.Context.child_from_id(TC.IncomingContext.parent(incoming), span,
      TC.InheritSampled{}))
    Test.child(child, TC.IncomingContext.state(incoming))

def Test.contexts() -> IO(Unit):
  +extraction = TC.Context.extract(TC.Limits.default(), [TC.Header{"traceparent", Test.w3c()},
    TC.Header{"tracestate", "congo=t61rcWkgMzE"}, TC.Header{"tracestate", " rojo=00f067aa0ba902b7 "}], None{})
  do IO<Unit>:
    incoming : TC.IncomingContext <- Test.or_die(TC.IncomingContext, "the incoming context",
      TC.Extraction.incoming(extraction))
    +base : TC.BaseContext <- Test.base()
    Test.incoming(incoming, base)

# `count` unrelated fields before `tail`, built by a loop.
def Test.headers(count: Nat, tail: List<&2, TC.Header>) -> List<&2, TC.Header>:
  match count:
    case 0n:
      tail
    case 1n+more:
      Test.headers(more, Con{TC.Header{"x-field", "value"}, tail})

def Test.first_field(received: Maybe<&2, TC.ReceivedPair>) -> String:
  match received:
    case Some{TC.ReceivedPair{traceparent, Con{field, rest}}}:
      field
    case _:
      ""

def Test.state_text(incoming: Maybe<&2, TC.IncomingContext>) -> String:
  match incoming:
    case None{}:
      "none"
    case Some{context}:
      TC.TraceState.format(TC.IncomingContext.state(context))

def Test.field_text(incoming: Maybe<&2, TC.IncomingContext>) -> String:
  match incoming:
    case None{}:
      ""
    case Some{context}:
      Test.first_field(TC.IncomingContext.received(context))

# A state of exactly 32768 octets, mostly trailing whitespace, is read, and
# its field is kept exactly as received.
def Test.long_state() -> IO(Unit):
  +field : String = "k=v" ++ Test.fill(32765n, ' ', "")
  +incoming = TC.Extraction.incoming(TC.Context.extract(TC.Limits.default(), Test.carrier([field]), None{}))
  do IO<Unit>:
    Unit <- Test.assert("a 32768-octet state is read", String.eq(Test.state_text(incoming), "k=v"))
    Test.assert("a 32768-octet field is kept as received", Test.same(Test.field_text(incoming), field, True{}))

# Reading a carrier is a loop: a message with many fields needs no deep stack.
def Test.many() -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.extract("a traceparent after 100000 other fields",
      Test.headers(100000n, [TC.Header{"TraceParent", Test.harness()}]), Test.accepted_harness(), "accepted", "absent")
    Test.long_state()

# Diagnostics name what happened with the codec's and the tracestate's error
# names; they never include a received value.
def Test.diagnostics() -> IO(Unit):
  +rejected = TC.Context.extract(TC.Limits.default(), [
    TC.Header{"traceparent", "00-secret0secret0secret0secret0se-1234567890123456-01"},
    TC.Header{"tracestate", "secret=1"}], None{})
  +discarded = TC.Context.extract(TC.Limits.default(), Test.carrier(["secret=1,"]), None{})
  do IO<Unit>:
    Unit <- Test.assert("RepeatedTraceParent",
      String.eq(TC.TraceParentError.show(TC.RepeatedTraceParent{}), "RepeatedTraceParent"))
    Unit <- Test.assert("TraceParentTooLarge",
      String.eq(TC.TraceParentError.show(TC.TraceParentTooLarge{}), "TraceParentTooLarge"))
    Unit <- Test.assert("InvalidTraceParent",
      String.eq(TC.TraceParentError.show(TC.InvalidTraceParent{TC.InvalidHex{3n}}), "InvalidTraceParent InvalidHex at 3"))
    Unit <- Test.assert("TraceParentAccepted",
      String.eq(TC.TraceParentOutcome.show(TC.TraceParentAccepted{}), "TraceParentAccepted"))
    Unit <- Test.assert("TraceParentAbsent", String.eq(TC.TraceParentOutcome.show(TC.TraceParentAbsent{}), "TraceParentAbsent"))
    Unit <- Test.assert("TraceParentRejected", String.eq(TC.TraceParentOutcome.show(
      TC.TraceParentRejected{TC.RepeatedTraceParent{}}), "TraceParentRejected RepeatedTraceParent"))
    Unit <- Test.assert("StateAbsent", String.eq(TC.StateOutcome.show(TC.StateAbsent{}), "StateAbsent"))
    Unit <- Test.assert("StateAccepted", String.eq(TC.StateOutcome.show(TC.StateAccepted{}), "StateAccepted"))
    Unit <- Test.assert("StateDiscarded", String.eq(TC.StateOutcome.show(
      TC.StateDiscarded{TC.InvalidEntry{1n, TC.MissingEquals{}}}), "StateDiscarded InvalidEntry 1 MissingEquals"))
    Unit <- Test.assert("StateIgnored", String.eq(TC.StateOutcome.show(TC.StateIgnored{}), "StateIgnored"))
    Unit <- Test.assert("a rejected traceparent with an ignored state", String.eq(TC.Extraction.show(rejected),
      "TraceParentRejected InvalidTraceParent InvalidHex at 3, StateIgnored"))
    Unit <- Test.assert("the rejected value is not shown",
      Bool.not(String.contains(TC.Extraction.show(rejected), "secret")))
    Unit <- Test.assert("an accepted traceparent with an accepted state", String.eq(TC.Extraction.show(discarded),
      "TraceParentAccepted, StateAccepted"))
    Test.assert("an accepted traceparent with no state", String.eq(TC.Extraction.show(
      TC.Context.extract(TC.Limits.default(), [TC.Header{"traceparent", Test.w3c()}], None{})),
      "TraceParentAccepted, StateAbsent"))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.precedence()
    Unit <- IO.print("OK: precedence of the message's context over the base")
    Unit <- Test.names()
    Unit <- Test.repeated()
    Unit <- IO.print("OK: field names and repeated traceparent fields")
    Unit <- Test.state_fields()
    Unit <- Test.discarded()
    Unit <- Test.ignored()
    Unit <- IO.print("OK: tracestate fields, their discard and their neglect without a traceparent")
    Unit <- Test.versions()
    Unit <- IO.print("OK: strict version 00, forbidden ff and later versions by their known prefix")
    Unit <- Test.ows()
    Unit <- Test.budgets()
    Unit <- IO.print("OK: optional whitespace and the traceparent and tracestate input budgets")
    Unit <- Test.contexts()
    Unit <- Test.many()
    Unit <- IO.print("OK: incoming and base contexts, their parents and states")
    Unit <- Test.diagnostics()
    IO.print("OK: diagnostics without received values")
