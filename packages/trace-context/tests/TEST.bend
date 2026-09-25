import Base
import ../trace_context.bend as TC
import ../src/hex.bend as Hex

# The expected wire strings and errors below are independent protocol fixtures.
def Test.assert(name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "FAIL: " ++ name)

def Test.error_equal(actual: TC.Error, expected: TC.Error) -> Bool:
  match actual expected:
    case TC.UnexpectedEnd{a} TC.UnexpectedEnd{b}:
      Nat.is_eq(a, b)
    case TC.InvalidHex{a} TC.InvalidHex{b}:
      Nat.is_eq(a, b)
    case TC.ExpectedSeparator{a} TC.ExpectedSeparator{b}:
      Nat.is_eq(a, b)
    case TC.TrailingInput{} TC.TrailingInput{}:
      True{}
    case TC.ForbiddenVersion{} TC.ForbiddenVersion{}:
      True{}
    case TC.UnsupportedVersion{a} TC.UnsupportedVersion{b}:
      String.eq(a, b)
    case TC.ZeroId{TC.TraceIdField{}} TC.ZeroId{TC.TraceIdField{}}:
      True{}
    case TC.ZeroId{TC.ParentIdField{}} TC.ZeroId{TC.ParentIdField{}}:
      True{}
    case TC.ZeroId{TC.SpanIdField{}} TC.ZeroId{TC.SpanIdField{}}:
      True{}
    case _ _:
      False{}

def Test.context_error_equal(actual: TC.ContextError, expected: TC.ContextError) -> Bool:
  match actual expected:
    case TC.ReusedSpanId{} TC.ReusedSpanId{}:
      True{}
    case TC.ReusedTraceId{} TC.ReusedTraceId{}:
      True{}
    case _ _:
      False{}

# Checks a rejection by any of the validating parsers.
def Test.rejected(-A: Data, name: String, result: Result<&2, &2, TC.Error, A>,
  expected: TC.Error) -> IO(Unit):
  match result:
    case Done{_}:
      IO.die(Unit, 1, "FAIL: accepted " ++ name)
    case Fail{actual}:
      Test.assert(name, Test.error_equal(actual, expected))

def Test.reject(name: String, text: String, expected: TC.Error) -> IO(Unit):
  Test.rejected(TC.TraceParentV00, name, TC.TraceParentV00.parse(text), expected)

def Test.accept_result(+name: String, text: String, sampled: Bool,
  result: Result<&2, &2, TC.Error, TC.TraceParentV00>) -> IO(Unit):
  match result:
    case Fail{error}:
      IO.die(Unit, 1, "FAIL: " ++ name ++ ": " ++ TC.Error.show(error))
    case Done{+context}:
      do IO<Unit>:
        Unit <- Test.assert(name ++ " preserves bytes",
          String.eq(TC.TraceParentV00.format(context), text))
        Test.assert(name ++ " sampled bit",
          Bool.not(Bool.xor(TC.TraceParentV00.is_sampled(context), sampled)))

def Test.accept(name: String, +text: String, sampled: Bool) -> IO(Unit):
  Test.accept_result(name, text, sampled, TC.TraceParentV00.parse(text))

# Replace one character without depending on the parser's field helpers.
def Test.replace(text: String, offset: Nat, char: Char) -> String:
  match text offset:
    case SNil{} 0n:
      SNil{}
    case SCon{_, tail} 0n:
      SCon{char, tail}
    case SNil{} 1n+rest:
      SNil{}
    case SCon{head, tail} 1n+rest:
      SCon{head, Test.replace(tail, rest, char)}

def Test.w3c() -> String:
  "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"

def Test.prefix() -> String:
  "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-"

def Test.digits() -> List<&2, Hex.Digit>:
  [Hex.H0{}, Hex.H1{}, Hex.H2{}, Hex.H3{},
   Hex.H4{}, Hex.H5{}, Hex.H6{}, Hex.H7{},
   Hex.H8{}, Hex.H9{}, Hex.Ha{}, Hex.Hb{},
   Hex.Hc{}, Hex.Hd{}, Hex.He{}, Hex.Hf{}]

def Test.render_digits(digits: List<&2, Hex.Digit>) -> String:
  match digits:
    case Nil{}:
      SNil{}
    case Con{digit, tail}:
      SCon{Hex.Digit.to_char(digit), Test.render_digits(tail)}

# Supplied IDs and contexts are exercised only through the public API. Each
# expected value is a literal wire string or error, not a recomputation.
def Test.valid(-A: Data, name: String, result: Result<&2, &2, TC.Error, A>) -> IO(A):
  match result:
    case Fail{error}:
      IO.die(A, 1, "FAIL: " ++ name ++ " fixture: " ++ TC.Error.show(error))
    case Done{value}:
      IO.pure(A, value)

def Test.trace_id(text: String) -> IO(TC.TraceId):
  Test.valid(TC.TraceId, "trace ID", TC.TraceId.parse(text))

def Test.span_id(text: String) -> IO(TC.SpanId):
  Test.valid(TC.SpanId, "span ID", TC.SpanId.parse(text))

def Test.remote(text: String) -> IO(TC.RemoteContext):
  do IO<TC.RemoteContext>:
    traceparent : TC.TraceParentV00 <- Test.valid(TC.TraceParentV00, "traceparent", TC.TraceParentV00.parse(text))
    return TC.RemoteContext.from_traceparent(traceparent)

def Test.reject_trace_id(name: String, text: String, expected: TC.Error) -> IO(Unit):
  Test.rejected(TC.TraceId, name, TC.TraceId.parse(text), expected)

def Test.reject_span_id(name: String, text: String, expected: TC.Error) -> IO(Unit):
  Test.rejected(TC.SpanId, name, TC.SpanId.parse(text), expected)

def Test.emits(name: String, context: TC.LocalContext, expected: String) -> IO(Unit):
  Test.assert(name, String.eq(TC.TraceParentV00.format(TC.LocalContext.to_traceparent(context)), expected))

def Test.created(+name: String, result: Result<&2, &2, TC.ContextError, TC.LocalContext>,
  expected: String) -> IO(Unit):
  match result:
    case Fail{error}:
      IO.die(Unit, 1, "FAIL: " ++ name ++ ": " ++ TC.ContextError.show(error))
    case Done{context}:
      Test.emits(name, context, expected)

def Test.refused(name: String, result: Result<&2, &2, TC.ContextError, TC.LocalContext>,
  expected: TC.ContextError) -> IO(Unit):
  match result:
    case Done{_}:
      IO.die(Unit, 1, "FAIL: accepted " ++ name)
    case Fail{actual}:
      Test.assert(name, Test.context_error_equal(actual, expected))

def Test.supplied_ids() -> IO(Unit):
  do IO<Unit>:
    +trace : TC.TraceId <- Test.trace_id("0af7651916cd43dd8448eb211c80319c")
    span : TC.SpanId <- Test.span_id("b7ad6b7169203331")
    Unit <- Test.assert("trace ID keeps its text",
      String.eq(TC.TraceId.to_string(trace), "0af7651916cd43dd8448eb211c80319c"))
    Unit <- Test.assert("span ID keeps its text", String.eq(TC.SpanId.to_string(span), "b7ad6b7169203331"))
    Unit <- Test.assert("a parsed trace ID makes no randomness assertion", Bool.not(TC.TraceId.is_random(trace)))
    Unit <- Test.assert("randomness is asserted explicitly", TC.TraceId.is_random(TC.TraceId.assert_random(trace)))
    Unit <- Test.assert("the assertion keeps the identifier",
      String.eq(TC.TraceId.to_string(TC.TraceId.assert_random(trace)), "0af7651916cd43dd8448eb211c80319c"))
    Unit <- Test.reject_trace_id("empty trace ID", "", TC.UnexpectedEnd{0n})
    Unit <- Test.reject_trace_id("31-digit trace ID", "0af7651916cd43dd8448eb211c80319", TC.UnexpectedEnd{31n})
    Unit <- Test.reject_trace_id("33-digit trace ID", "0af7651916cd43dd8448eb211c80319c0", TC.TrailingInput{})
    Unit <- Test.reject_trace_id("uppercase trace ID", "0AF7651916cd43dd8448eb211c80319c", TC.InvalidHex{1n})
    Unit <- Test.reject_trace_id("non-hexadecimal trace ID", "0af7651916cd43dg8448eb211c80319c", TC.InvalidHex{15n})
    Unit <- Test.reject_trace_id("traceparent as trace ID", Test.w3c(), TC.InvalidHex{2n})
    Unit <- Test.reject_trace_id("all-zero trace ID", "00000000000000000000000000000000", TC.ZeroId{TC.TraceIdField{}})
    Unit <- Test.reject_span_id("empty span ID", "", TC.UnexpectedEnd{0n})
    Unit <- Test.reject_span_id("15-digit span ID", "b7ad6b716920333", TC.UnexpectedEnd{15n})
    Unit <- Test.reject_span_id("17-digit span ID", "b7ad6b71692033310", TC.TrailingInput{})
    Unit <- Test.reject_span_id("trace-length span ID", "0af7651916cd43dd8448eb211c80319c", TC.TrailingInput{})
    Unit <- Test.reject_span_id("uppercase span ID", "b7ad6b716920333F", TC.InvalidHex{15n})
    Unit <- Test.reject_span_id("leading space in span ID", " 7ad6b7169203331", TC.InvalidHex{0n})
    Unit <- Test.reject_span_id("all-zero span ID", "0000000000000000", TC.ZeroId{TC.SpanIdField{}})
    IO.print("OK: supplied trace and span IDs")

def Test.roots() -> IO(Unit):
  do IO<Unit>:
    +trace : TC.TraceId <- Test.trace_id("0af7651916cd43dd8448eb211c80319c")
    +span : TC.SpanId <- Test.span_id("b7ad6b7169203331")
    Unit <- Test.emits("a root starts unsampled", TC.Context.root_from_ids(trace, span),
      "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-00")
    Unit <- Test.assert("a root reports unsampled", Bool.not(TC.LocalContext.is_sampled(TC.Context.root_from_ids(trace, span))))
    Unit <- Test.emits("a root with an asserted random trace ID", TC.Context.root_from_ids(TC.TraceId.assert_random(trace), span),
      "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-02")
    Unit <- Test.emits("explicit sampled construction", TC.Context.from_ids(trace, span, True{}),
      "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01")
    Unit <- Test.emits("explicit sampled construction with random",
      TC.Context.from_ids(TC.TraceId.assert_random(trace), span, True{}),
      "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-03")
    IO.print("OK: roots and explicit construction")

# Kept apart from the other received-context cases: one larger IO block
# exceeds the native backend's arity limit.
def Test.inherited_children() -> IO(Unit):
  do IO<Unit>:
    +child : TC.SpanId <- Test.span_id("00f067aa0ba902b7")
    sampled : TC.RemoteContext <- Test.remote("00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01")
    random : TC.RemoteContext <- Test.remote("00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-03")
    unsampled_random : TC.RemoteContext <- Test.remote("00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-02")
    Unit <- Test.created("a child inherits sampled without random",
      TC.Context.child_from_id(TC.RemoteParent{sampled}, child, TC.InheritSampled{}),
      "00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-01")
    Unit <- Test.created("a child inherits sampled and random",
      TC.Context.child_from_id(TC.RemoteParent{random}, child, TC.InheritSampled{}),
      "00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-03")
    Test.created("a child inherits unsampled with random",
      TC.Context.child_from_id(TC.RemoteParent{unsampled_random}, child, TC.InheritSampled{}),
      "00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-02")

def Test.remote_children() -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.inherited_children()
    +child : TC.SpanId <- Test.span_id("00f067aa0ba902b7")
    received_span : TC.SpanId <- Test.span_id("b7ad6b7169203331")
    sampled : TC.RemoteContext <- Test.remote("00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01")
    random : TC.RemoteContext <- Test.remote("00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-03")
    unflagged : TC.RemoteContext <- Test.remote("00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-00")
    +reserved : TC.RemoteContext <- Test.remote("00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-ff")
    Unit <- Test.created("a sampling override keeps random",
      TC.Context.child_from_id(TC.RemoteParent{random}, child, TC.SetSampled{False{}}),
      "00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-02")
    Unit <- Test.created("a sampling override sets sampled",
      TC.Context.child_from_id(TC.RemoteParent{unflagged}, child, TC.SetSampled{True{}}),
      "00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-01")
    Unit <- Test.created("a child emits only known flags",
      TC.Context.child_from_id(TC.RemoteParent{reserved}, child, TC.InheritSampled{}),
      "00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-03")
    Unit <- Test.created("an override on reserved flags",
      TC.Context.child_from_id(TC.RemoteParent{reserved}, child, TC.SetSampled{False{}}),
      "00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-02")
    Unit <- Test.refused("a child reusing the received span ID",
      TC.Context.child_from_id(TC.RemoteParent{sampled}, received_span, TC.InheritSampled{}), TC.ReusedSpanId{})
    IO.print("OK: children of received contexts")

def Test.grandchildren(created: Result<&2, &2, TC.ContextError, TC.LocalContext>, +second: TC.SpanId, first: TC.SpanId) -> IO(Unit):
  match created:
    case Fail{error}:
      IO.die(Unit, 1, "FAIL: local child fixture: " ++ TC.ContextError.show(error))
    case Done{+child}:
      do IO<Unit>:
        Unit <- Test.created("a child of a child continues the trace",
          TC.Context.child_from_id(TC.LocalParent{child}, second, TC.InheritSampled{}),
          "00-0af7651916cd43dd8448eb211c80319c-53995c3f42cd8ad8-01")
        Test.refused("a child of a child reusing its parent span ID",
          TC.Context.child_from_id(TC.LocalParent{child}, first, TC.InheritSampled{}), TC.ReusedSpanId{})

def Test.local_children() -> IO(Unit):
  do IO<Unit>:
    +trace : TC.TraceId <- Test.trace_id("0af7651916cd43dd8448eb211c80319c")
    +root_span : TC.SpanId <- Test.span_id("b7ad6b7169203331")
    +first : TC.SpanId <- Test.span_id("00f067aa0ba902b7")
    second : TC.SpanId <- Test.span_id("53995c3f42cd8ad8")
    +root : TC.LocalContext = TC.Context.root_from_ids(trace, root_span)
    Unit <- Test.created("a local child inherits unsampled",
      TC.Context.child_from_id(TC.LocalParent{root}, first, TC.InheritSampled{}),
      "00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-00")
    Unit <- Test.created("a local child with a sampling override",
      TC.Context.child_from_id(TC.LocalParent{root}, first, TC.SetSampled{True{}}),
      "00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-01")
    Unit <- Test.created("a local child keeps the random assertion",
      TC.Context.child_from_id(TC.LocalParent{TC.Context.root_from_ids(TC.TraceId.assert_random(trace), root_span)},
        first, TC.InheritSampled{}),
      "00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-02")
    Unit <- Test.refused("a local child reusing its parent span ID",
      TC.Context.child_from_id(TC.LocalParent{root}, root_span, TC.InheritSampled{}), TC.ReusedSpanId{})
    Unit <- Test.grandchildren(TC.Context.child_from_id(TC.LocalParent{root}, first, TC.SetSampled{True{}}), second, first)
    IO.print("OK: children of local operations")

def Test.restarts() -> IO(Unit):
  do IO<Unit>:
    +received : TC.RemoteContext <- Test.remote("00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-03")
    +fresh : TC.TraceId <- Test.trace_id("4bf92f3577b34da6a3ce929d0e0e4736")
    +same : TC.TraceId <- Test.trace_id("0af7651916cd43dd8448eb211c80319c")
    +span : TC.SpanId <- Test.span_id("00f067aa0ba902b7")
    Unit <- Test.created("a restart applies the root defaults", TC.Context.restart_from_ids(received, fresh, span),
      "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00")
    Unit <- Test.created("a restart with an asserted random trace ID",
      TC.Context.restart_from_ids(received, TC.TraceId.assert_random(fresh), span),
      "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-02")
    Unit <- Test.refused("a restart reusing the received trace ID",
      TC.Context.restart_from_ids(received, same, span), TC.ReusedTraceId{})
    Unit <- Test.refused("a restart reusing it with a random assertion",
      TC.Context.restart_from_ids(received, TC.TraceId.assert_random(same), span), TC.ReusedTraceId{})
    IO.print("OK: explicit restarts")

# All 256 flag bytes. The oracles use an independent numeric counter, not the
# package's digit helpers, and the alphabet is checked against a literal.
def Test.flag_suffix(high: Hex.Digit, low: Hex.Digit) -> String:
  SCon{Hex.Digit.to_char(high), SCon{Hex.Digit.to_char(low), SNil{}}}

# The only flag bytes a participant may emit, indexed by the two known bits.
def Test.known_flags(+bits: U32) -> String:
  Bool.pick(String, U32.is_eq(bits, 0), "00",
    Bool.pick(String, U32.is_eq(bits, 1), "01",
      Bool.pick(String, U32.is_eq(bits, 2), "02", "03")))

def Test.received_flags(+suffix: String, +bits: U32,
  parsed: Result<&2, &2, TC.Error, TC.TraceParentV00>, child: TC.SpanId) -> IO(Unit):
  match parsed:
    case Fail{error}:
      IO.die(Unit, 1, "FAIL: flags " ++ suffix ++ ": " ++ TC.Error.show(error))
    case Done{traceparent}:
      +remote = TC.RemoteContext.from_traceparent(traceparent)
      do IO<Unit>:
        Unit <- Test.assert("received sampled bit " ++ suffix,
          Bool.not(Bool.xor(TC.RemoteContext.is_sampled(remote), U32.is_eq(U32.mod(bits, 2), 1))))
        Unit <- Test.assert("received random bit " ++ suffix,
          Bool.not(Bool.xor(TC.TraceId.is_random(TC.RemoteContext.trace_id(remote)), U32.is_ge(bits, 2))))
        Test.created("child flags for " ++ suffix,
          TC.Context.child_from_id(TC.RemoteParent{remote}, child, TC.InheritSampled{}),
          "00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-" ++ Test.known_flags(bits))

def Test.flag_lows(+high: Hex.Digit, lows: List<&2, Hex.Digit>, +low_value: U32, +child: TC.SpanId) -> IO(Unit):
  match lows:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{low, tail}:
      +suffix = Test.flag_suffix(high, low)
      do IO<Unit>:
        Unit <- Test.accept("flags " ++ suffix, Test.prefix() ++ suffix, U32.is_eq(U32.mod(low_value, 2), 1))
        Unit <- Test.received_flags(suffix, U32.mod(low_value, 4),
          TC.TraceParentV00.parse(Test.prefix() ++ suffix), child)
        Test.flag_lows(high, tail, U32.add(low_value, 1), child)

def Test.flag_highs(highs: List<&2, Hex.Digit>, +child: TC.SpanId) -> IO(Unit):
  match highs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{high, tail}:
      do IO<Unit>:
        Unit <- Test.flag_lows(high, Test.digits(), 0, child)
        Test.flag_highs(tail, child)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.accept("W3C example, 55 characters", Test.w3c(), True{})
    Unit <- Test.accept("flags 00", Test.prefix() ++ "00", False{})
    Unit <- Test.accept("flags 01", Test.prefix() ++ "01", True{})
    Unit <- Test.accept("flags 02", Test.prefix() ++ "02", False{})
    Unit <- Test.accept("flags 03", Test.prefix() ++ "03", True{})
    Unit <- Test.accept("flags ff", Test.prefix() ++ "ff", True{})
    Unit <- IO.print("OK: W3C example and reserved flag bits")

    Unit <- Test.reject("empty", "", TC.UnexpectedEnd{0n})
    Unit <- Test.reject("one version digit", "0", TC.UnexpectedEnd{1n})
    Unit <- Test.reject("version without separator", "00", TC.UnexpectedEnd{2n})
    Unit <- Test.reject("54 characters", String.take(Test.w3c(), 54n), TC.UnexpectedEnd{54n})
    Unit <- Test.reject("56 characters", Test.w3c() ++ "0", TC.TrailingInput{})
    Unit <- Test.reject("v00 extension", Test.w3c() ++ "-vendor", TC.TrailingInput{})
    Unit <- Test.reject("suffix whitespace", Test.w3c() ++ " ", TC.TrailingInput{})
    Unit <- Test.reject("suffix newline", Test.w3c() ++ "\n", TC.TrailingInput{})
    Unit <- Test.reject("version ff", "ff" ++ String.drop(Test.w3c(), 2n), TC.ForbiddenVersion{})
    Unit <- Test.reject("future version 01", "01" ++ String.drop(Test.w3c(), 2n),
      TC.UnsupportedVersion{"01"})
    Unit <- IO.print("OK: lengths, suffixes and version policy")

    Unit <- Test.reject("uppercase version", Test.replace(Test.w3c(), 1n, 'A'), TC.InvalidHex{1n})
    Unit <- Test.reject("uppercase trace ID", Test.replace(Test.w3c(), 4n, 'A'), TC.InvalidHex{4n})
    Unit <- Test.reject("uppercase parent ID", Test.replace(Test.w3c(), 36n, 'B'), TC.InvalidHex{36n})
    Unit <- Test.reject("uppercase flag high", Test.replace(Test.w3c(), 53n, 'F'), TC.InvalidHex{53n})
    Unit <- Test.reject("uppercase flag low", Test.replace(Test.w3c(), 54n, 'F'), TC.InvalidHex{54n})
    Unit <- Test.reject("invalid ASCII", Test.replace(Test.w3c(), 12n, 'g'), TC.InvalidHex{12n})
    Unit <- Test.reject("embedded space", Test.replace(Test.w3c(), 12n, ' '), TC.InvalidHex{12n})
    Unit <- Test.reject("embedded tab", Test.replace(Test.w3c(), 12n, '\t'), TC.InvalidHex{12n})
    Unit <- Test.reject("fullwidth digit", Test.replace(Test.w3c(), 3n, '０'), TC.InvalidHex{3n})
    Unit <- Test.reject("fullwidth letter", Test.replace(Test.w3c(), 4n, 'ａ'), TC.InvalidHex{4n})
    Unit <- Test.reject("non-BMP character", Test.replace(Test.w3c(), 36n, '😀'), TC.InvalidHex{36n})
    Unit <- IO.print("OK: lowercase ASCII alphabet and character offsets")

    Unit <- Test.reject("separator at 2", Test.replace(Test.w3c(), 2n, ':'), TC.ExpectedSeparator{2n})
    Unit <- Test.reject("separator at 35", Test.replace(Test.w3c(), 35n, ':'), TC.ExpectedSeparator{35n})
    Unit <- Test.reject("separator at 52", Test.replace(Test.w3c(), 52n, ':'), TC.ExpectedSeparator{52n})
    Unit <- Test.reject("zero trace ID",
      "00-00000000000000000000000000000000-b7ad6b7169203331-01",
      TC.ZeroId{TC.TraceIdField{}})
    Unit <- Test.reject("zero parent ID",
      "00-0af7651916cd43dd8448eb211c80319c-0000000000000000-01",
      TC.ZeroId{TC.ParentIdField{}})
    Unit <- Test.accept("last digits establish nonzero IDs",
      "00-00000000000000000000000000000001-0000000000000001-00", False{})
    Unit <- Test.accept("first digits establish nonzero IDs",
      "00-10000000000000000000000000000000-1000000000000000-00", False{})
    Unit <- IO.print("OK: separators and nonzero IDs")

    Unit <- Test.supplied_ids()
    Unit <- Test.roots()
    Unit <- Test.remote_children()
    Unit <- Test.local_children()
    Unit <- Test.restarts()

    child : TC.SpanId <- Test.span_id("00f067aa0ba902b7")
    Unit <- Test.assert("hexadecimal alphabet",
      String.eq(Test.render_digits(Test.digits()), "0123456789abcdef"))
    Unit <- Test.flag_highs(Test.digits(), child)
    IO.print("OK: all 256 flag bytes: codec, received flags and emitted child flags")
