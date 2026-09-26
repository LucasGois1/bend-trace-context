import Base
import ../trace_context.bend as TC

# Deterministic generation through the public operations with replayed tapes.
# Expected identifiers are the W3C example split into big-endian words:
# 0af76519 16cd43dd 8448eb21 1c80319c and b7ad6b71 69203331, written in decimal.
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

# The words of 0af7651916cd43dd8448eb211c80319c, then a sentinel tail.
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

def Test.sentinel() -> List<&1, Result<&1, &1, U32 & String, U32>>:
  [Done{7}]

def Test.error_text(error: TC.GenerationError) -> String:
  TC.GenerationError.show(error)

def Test.created.check(+name: String, expected: String, consumed: Bool,
  result: Result<&2, &2, TC.GenerationError, TC.LocalContext>) -> IO(Unit):
  match result:
    case Fail{error}:
      IO.die(Unit, 1, "FAIL: " ++ name ++ ": " ++ Test.error_text(error))
    case Done{context}:
      do IO<Unit>:
        Unit <- Test.assert(name, String.eq(TC.TraceParentV00.format(TC.LocalContext.to_traceparent(context)), expected))
        Test.assert(name ++ " reads only the words it needs", consumed)

# A generation that must create `expected`, leaving `left` unread words.
def Test.created(+name: String, expected: String, left: Nat,
  outcome: List<&1, Result<&1, &1, U32 & String, U32>> & Result<&2, &2, TC.GenerationError, TC.LocalContext>) -> IO(Unit):
  (rest, result) = outcome
  Test.created.check(name, expected, Nat.is_eq(List.length(&1, Result<&1, &1, U32 & String, U32>, rest), left), result)

# A generation that must fail with `expected`, leaving `left` unread words.
def Test.failed.check(+name: String, expected: String, consumed: Bool,
  result: Result<&2, &2, TC.GenerationError, TC.LocalContext>) -> IO(Unit):
  match result:
    case Done{context}:
      IO.die(Unit, 1, "FAIL: generated " ++ name)
    case Fail{error}:
      do IO<Unit>:
        Unit <- Test.assert(name, String.eq(Test.error_text(error), expected))
        Test.assert(name ++ " stops reading", consumed)

def Test.failed(+name: String, expected: String, left: Nat,
  outcome: List<&1, Result<&1, &1, U32 & String, U32>> & Result<&2, &2, TC.GenerationError, TC.LocalContext>) -> IO(Unit):
  (rest, result) = outcome
  Test.failed.check(name, expected, Nat.is_eq(List.length(&1, Result<&1, &1, U32 & String, U32>, rest), left), result)

def Test.trace_text(value: Maybe<&2, TC.TraceId>) -> String:
  match value:
    case None{}:
      "none"
    case Some{id}:
      TC.TraceId.to_string(id)

def Test.span_text(value: Maybe<&2, TC.SpanId>) -> String:
  match value:
    case None{}:
      "none"
    case Some{id}:
      TC.SpanId.to_string(id)

def Test.trace_random(value: Maybe<&2, TC.TraceId>) -> Bool:
  match value:
    case None{}:
      False{}
    case Some{id}:
      TC.TraceId.is_random(id)

def Test.conversion() -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.assert("four words, most significant first",
      String.eq(Test.trace_text(
        TC.TraceId.from_words(183985433, 382551005, 2219371297, 478163356)), "0af7651916cd43dd8448eb211c80319c"))
    Unit <- Test.assert("two words, most significant first",
      String.eq(Test.span_text(TC.SpanId.from_words(3081595761, 1763717937)),
        "b7ad6b7169203331"))
    Unit <- Test.assert("digit order within a word",
      String.eq(Test.span_text(TC.SpanId.from_words(305419896, 2596069104)),
        "123456789abcdef0"))
    Unit <- Test.assert("the lowest word sets the last digits",
      String.eq(Test.trace_text(TC.TraceId.from_words(0, 0, 0, 1)),
        "00000000000000000000000000000001"))
    Unit <- Test.assert("the highest words",
      String.eq(Test.trace_text(
        TC.TraceId.from_words(4294967295, 4294967295, 4294967295, 4294967295)), "ffffffffffffffffffffffffffffffff"))
    Unit <- Test.assert("an all-zero trace ID candidate is rejected",
      String.eq(Test.trace_text(TC.TraceId.from_words(0, 0, 0, 0)), "none"))
    Unit <- Test.assert("an all-zero span ID candidate is rejected",
      String.eq(Test.span_text(TC.SpanId.from_words(0, 0)), "none"))
    Unit <- Test.assert("converting words makes no randomness assertion",
      Bool.not(Test.trace_random(TC.TraceId.from_words(183985433, 382551005, 2219371297, 478163356))))
    IO.print("OK: big-endian word conversion and zero rejection")

def Test.roots() -> IO(Unit):
  do IO<Unit>:
    first : List<&1, Result<&1, &1, U32 & String, U32>> & Result<&2, &2, TC.GenerationError, TC.LocalContext> <-
      TC.Context.root_with(~List<&1, Result<&1, &1, U32 & String, U32>>, ~TC.Source.tape,
        Test.w3c_trace(Test.w3c_span(Test.sentinel())))
    Unit <- Test.created("a generated root is random and unsampled",
      "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-02", 1n, first)
    retried : List<&1, Result<&1, &1, U32 & String, U32>> & Result<&2, &2, TC.GenerationError, TC.LocalContext> <-
      TC.Context.root_with(~List<&1, Result<&1, &1, U32 & String, U32>>, ~TC.Source.tape,
        List.append(&1, Result<&1, &1, U32 & String, U32>, Test.zeros(4n),
          Test.w3c_trace(List.append(&1, Result<&1, &1, U32 & String, U32>, Test.zeros(2n),
            Test.w3c_span(Test.sentinel())))))
    Unit <- Test.created("zero candidates are replaced",
      "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-02", 1n, retried)
    IO.print("OK: generated roots")

def Test.exhaustion() -> IO(Unit):
  do IO<Unit>:
    trace : List<&1, Result<&1, &1, U32 & String, U32>> & Result<&2, &2, TC.GenerationError, TC.LocalContext> <-
      TC.Context.root_with(~List<&1, Result<&1, &1, U32 & String, U32>>, ~TC.Source.tape,
        List.append(&1, Result<&1, &1, U32 & String, U32>, Test.zeros(32n), Test.sentinel()))
    Unit <- Test.failed("eight zero trace ID candidates", "ExhaustedTraceId", 1n, trace)
    span : List<&1, Result<&1, &1, U32 & String, U32>> & Result<&2, &2, TC.GenerationError, TC.LocalContext> <-
      TC.Context.root_with(~List<&1, Result<&1, &1, U32 & String, U32>>, ~TC.Source.tape,
        Test.w3c_trace(List.append(&1, Result<&1, &1, U32 & String, U32>, Test.zeros(16n), Test.sentinel())))
    Unit <- Test.failed("eight zero span ID candidates", "ExhaustedSpanId", 1n, span)
    IO.print("OK: eight candidates and no ninth")

def Test.source_failures() -> IO(Unit):
  do IO<Unit>:
    middle : List<&1, Result<&1, &1, U32 & String, U32>> & Result<&2, &2, TC.GenerationError, TC.LocalContext> <-
      TC.Context.root_with(~List<&1, Result<&1, &1, U32 & String, U32>>, ~TC.Source.tape,
        Con{Done{183985433}, Con{Done{382551005}, Con{Fail{(9, "controlled")}, Test.w3c_span(Test.sentinel())}}})
    Unit <- Test.failed("a source error in the middle of a candidate", "SourceFailure 9 controlled", 3n, middle)
    empty : List<&1, Result<&1, &1, U32 & String, U32>> & Result<&2, &2, TC.GenerationError, TC.LocalContext> <-
      TC.Context.root_with(~List<&1, Result<&1, &1, U32 & String, U32>>, ~TC.Source.tape, Nil{})
    Unit <- Test.failed("an empty tape", "SourceFailure 1 tape-exhausted", 0n, empty)
    IO.print("OK: source errors end generation at once")

def Test.received.valid(result: Result<&2, &2, TC.Error, TC.TraceParentV00>) -> IO(TC.RemoteContext):
  match result:
    case Fail{error}:
      IO.die(TC.RemoteContext, 1, "FAIL: traceparent fixture: " ++ TC.Error.show(error))
    case Done{traceparent}:
      IO.pure(TC.RemoteContext, TC.RemoteContext.from_traceparent(traceparent))

def Test.received(text: String) -> IO(TC.RemoteContext):
  Test.received.valid(TC.TraceParentV00.parse(text))

def Test.children() -> IO(Unit):
  do IO<Unit>:
    +incoming : TC.RemoteContext <- Test.received("00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01")
    reused : List<&1, Result<&1, &1, U32 & String, U32>> & Result<&2, &2, TC.GenerationError, TC.LocalContext> <-
      TC.Context.child_with(~List<&1, Result<&1, &1, U32 & String, U32>>, ~TC.Source.tape,
        Test.w3c_span(Test.other_span(Test.sentinel())), TC.RemoteParent{incoming}, TC.InheritSampled{})
    Unit <- Test.created("a child never reuses the parent span ID",
      "00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-01", 1n, reused)
    unsampled : List<&1, Result<&1, &1, U32 & String, U32>> & Result<&2, &2, TC.GenerationError, TC.LocalContext> <-
      TC.Context.child_with(~List<&1, Result<&1, &1, U32 & String, U32>>, ~TC.Source.tape,
        Test.other_span(Test.sentinel()), TC.RemoteParent{incoming}, TC.SetSampled{False{}})
    Unit <- Test.created("a generated child keeps the received random bit and takes a sampling override",
      "00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-00", 1n, unsampled)
    exhausted : List<&1, Result<&1, &1, U32 & String, U32>> & Result<&2, &2, TC.GenerationError, TC.LocalContext> <-
      TC.Context.child_with(~List<&1, Result<&1, &1, U32 & String, U32>>, ~TC.Source.tape,
        Test.w3c_span(Test.w3c_span(Test.w3c_span(Test.w3c_span(List.append(&1, Result<&1, &1, U32 & String, U32>,
          Test.zeros(8n), Test.sentinel()))))), TC.RemoteParent{incoming}, TC.InheritSampled{})
    Unit <- Test.failed("eight reused or zero span ID candidates", "ExhaustedSpanId", 1n, exhausted)
    IO.print("OK: generated children")

def Test.restarts() -> IO(Unit):
  do IO<Unit>:
    incoming : TC.RemoteContext <- Test.received("00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-03")
    restarted : List<&1, Result<&1, &1, U32 & String, U32>> & Result<&2, &2, TC.GenerationError, TC.LocalContext> <-
      TC.Context.restart_with(~List<&1, Result<&1, &1, U32 & String, U32>>, ~TC.Source.tape,
        Test.w3c_trace(Test.other_trace(Test.other_span(Test.sentinel()))), incoming)
    Unit <- Test.created("a restart never reuses the received trace ID",
      "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-02", 1n, restarted)
    IO.print("OK: generated restarts")

def Test.worst_case() -> IO(Unit):
  do IO<Unit>:
    longest : List<&1, Result<&1, &1, U32 & String, U32>> & Result<&2, &2, TC.GenerationError, TC.LocalContext> <-
      TC.Context.root_with(~List<&1, Result<&1, &1, U32 & String, U32>>, ~TC.Source.tape,
        List.append(&1, Result<&1, &1, U32 & String, U32>, Test.zeros(28n),
          Test.w3c_trace(List.append(&1, Result<&1, &1, U32 & String, U32>, Test.zeros(14n),
            Test.w3c_span(Test.sentinel())))))
    Unit <- Test.created("the eighth candidate of each identifier is still accepted",
      "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-02", 1n, longest)
    IO.print("OK: a root may read all 48 words")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.conversion()
    Unit <- Test.roots()
    Unit <- Test.exhaustion()
    Unit <- Test.worst_case()
    Unit <- Test.source_failures()
    Unit <- Test.children()
    Test.restarts()
