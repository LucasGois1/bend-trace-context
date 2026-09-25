import Base
import ./trace_context.bend as Trace

# This is a statement about every value of the type, not just parsed examples.
law formatted_length:
  for context: Trace.TraceParentV00
  {String.length(Trace.TraceParentV00.format(context)) == 55n : Nat}

# The IDs, their evidence and all flag bits survive the complete codec.
law roundtrip:
  for context: Trace.TraceParentV00
  {Trace.TraceParentV00.parse(Trace.TraceParentV00.format(context)) ==
    Done{context} : Result<&2, &2, Trace.Error, Trace.TraceParentV00>}

# Quantified over every String: whenever the strict parser accepts a text,
# formatting the result reproduces exactly that text.
law inverse:
  for text: String
  for context: Trace.TraceParentV00
  for accepted: {Trace.TraceParentV00.parse(text) == Done{context} :
    Result<&2, &2, Trace.Error, Trace.TraceParentV00>}
  {Trace.TraceParentV00.format(context) == text : String}

# A supplied trace ID is exactly the text that was accepted, and parsing it
# makes no randomness assertion.
law trace_id_parse:
  for text: String
  for id: Trace.TraceId
  for accepted: {Trace.TraceId.parse(text) == Done{id} : Result<&2, &2, Trace.Error, Trace.TraceId>}
  {Trace.TraceId.to_string(id) == text : String} & {Trace.TraceId.is_random(id) == False{} : Bool}

law span_id_parse:
  for text: String
  for id: Trace.SpanId
  for accepted: {Trace.SpanId.parse(text) == Done{id} : Result<&2, &2, Trace.Error, Trace.SpanId>}
  {Trace.SpanId.to_string(id) == text : String}

# Conversely, the text of every trace ID is accepted, and every span ID's text
# parses back to that span ID.
law trace_id_accepts:
  for id: Trace.TraceId
  {Result.is_done(&2, &2, Trace.Error, Trace.TraceId, Trace.TraceId.parse(Trace.TraceId.to_string(id))) ==
    True{} : Bool}

law span_id_roundtrip:
  for id: Trace.SpanId
  {Trace.SpanId.parse(Trace.SpanId.to_string(id)) == Done{id} : Result<&2, &2, Trace.Error, Trace.SpanId>}

# Asserting randomness changes only the assertion, never the identifier.
law assert_random:
  for trace_id: Trace.TraceId
  {Trace.TraceId.is_random(Trace.TraceId.assert_random(trace_id)) == True{} : Bool} &
  {Trace.TraceId.to_string(Trace.TraceId.assert_random(trace_id)) == Trace.TraceId.to_string(trace_id) : String}

# Explicit construction keeps the supplied IDs and sampled indication.
law from_ids:
  for trace_id: Trace.TraceId
  for span_id: Trace.SpanId
  for sampled: Bool
  {Trace.LocalContext.trace_id(Trace.Context.from_ids(trace_id, span_id, sampled)) == trace_id : Trace.TraceId} &
  {Trace.LocalContext.span_id(Trace.Context.from_ids(trace_id, span_id, sampled)) == span_id : Trace.SpanId} &
  {Trace.LocalContext.is_sampled(Trace.Context.from_ids(trace_id, span_id, sampled)) == sampled : Bool}

# A root is the explicit construction of its supplied IDs with sampled 0.
law root:
  for trace_id: Trace.TraceId
  for span_id: Trace.SpanId
  {Trace.Context.root_from_ids(trace_id, span_id) == Trace.Context.from_ids(trace_id, span_id, False{}) : Trace.LocalContext}

# The only flag bytes a participant emits, from sampled (bit 0) and
# random-trace-id (bit 1).
def emitted_flags(sampled: Bool, random: Bool) -> String:
  match sampled random:
    case False{} False{}:
      "00"
    case True{} False{}:
      "01"
    case False{} True{}:
      "02"
    case True{} True{}:
      "03"

# Every local context is emitted as version 00 with its IDs and known flags;
# every reserved flag bit is zero.
law emitted_traceparent:
  for context: Trace.LocalContext
  {Trace.TraceParentV00.format(Trace.LocalContext.to_traceparent(context)) ==
    "00-" ++ Trace.TraceId.to_string(Trace.LocalContext.trace_id(context)) ++ "-" ++
    Trace.SpanId.to_string(Trace.LocalContext.span_id(context)) ++ "-" ++
    emitted_flags(Trace.LocalContext.is_sampled(context),
      Trace.TraceId.is_random(Trace.LocalContext.trace_id(context))) : String}

# Receiving an emitted local context recovers its trace ID, including the
# randomness assertion, its span ID and its sampled indication.
law emitted_projection:
  for context: Trace.LocalContext
  {Trace.RemoteContext.trace_id(Trace.RemoteContext.from_traceparent(Trace.LocalContext.to_traceparent(context))) ==
    Trace.LocalContext.trace_id(context) : Trace.TraceId} &
  {Trace.RemoteContext.span_id(Trace.RemoteContext.from_traceparent(Trace.LocalContext.to_traceparent(context))) ==
    Trace.LocalContext.span_id(context) : Trace.SpanId} &
  {Trace.RemoteContext.is_sampled(Trace.RemoteContext.from_traceparent(Trace.LocalContext.to_traceparent(context))) ==
    Trace.LocalContext.is_sampled(context) : Bool}

# A received context keeps the sender's sampled and random-trace-id flags.
law received_flags:
  for traceparent: Trace.TraceParentV00
  {Trace.RemoteContext.is_sampled(Trace.RemoteContext.from_traceparent(traceparent)) ==
    Trace.TraceParentV00.is_sampled(traceparent) : Bool} &
  {Trace.TraceId.is_random(Trace.RemoteContext.trace_id(Trace.RemoteContext.from_traceparent(traceparent))) ==
    Trace.TraceParentV00.is_random(traceparent) : Bool}

# A child either inherits its parent's sampled indication or takes the one set.
law sampling:
  for inherited: Bool
  for sampled: Bool
  {Trace.Sampling.resolve(Trace.InheritSampled{}, inherited) == inherited : Bool} &
  {Trace.Sampling.resolve(Trace.SetSampled{sampled}, inherited) == sampled : Bool}

# A successful child keeps the parent's trace ID and its randomness assertion,
# uses the supplied span ID, which differs from the parent's, and takes its
# sampled indication from the parent unless the caller sets it.
law child:
  for parent: Trace.Parent
  for span_id: Trace.SpanId
  for sampling: Trace.Sampling
  for created: Trace.LocalContext
  for accepted: {Trace.Context.child_from_id(parent, span_id, sampling) == Done{created} :
    Result<&2, &2, Trace.ContextError, Trace.LocalContext>}
  {Trace.LocalContext.trace_id(created) == Trace.Parent.trace_id(parent) : Trace.TraceId} &
  {Trace.LocalContext.span_id(created) == span_id : Trace.SpanId} &
  {Trace.LocalContext.is_sampled(created) ==
    Trace.Sampling.resolve(sampling, Trace.Parent.is_sampled(parent)) : Bool} &
  {Trace.SpanId.to_string(span_id) != Trace.SpanId.to_string(Trace.Parent.span_id(parent)) : String}

# A child reusing its parent's span ID is rejected.
law child_reuse:
  for parent: Trace.Parent
  for span_id: Trace.SpanId
  for sampling: Trace.Sampling
  for reused: {Trace.SpanId.to_string(span_id) == Trace.SpanId.to_string(Trace.Parent.span_id(parent)) : String}
  {Trace.Context.child_from_id(parent, span_id, sampling) == Fail{Trace.ReusedSpanId{}} :
    Result<&2, &2, Trace.ContextError, Trace.LocalContext>}

# Every other span ID is accepted: reuse is the only reason to refuse a child.
law child_accepts:
  for parent: Trace.Parent
  for span_id: Trace.SpanId
  for sampling: Trace.Sampling
  for distinct: {Trace.SpanId.to_string(span_id) != Trace.SpanId.to_string(Trace.Parent.span_id(parent)) : String}
  {Trace.Context.child_from_id(parent, span_id, sampling) ==
    Done{Trace.Context.from_ids(Trace.Parent.trace_id(parent), span_id,
      Trace.Sampling.resolve(sampling, Trace.Parent.is_sampled(parent)))} :
    Result<&2, &2, Trace.ContextError, Trace.LocalContext>}

# A successful restart is the root of its supplied IDs, and its trace ID
# differs from the received one.
law restart:
  for previous: Trace.RemoteContext
  for trace_id: Trace.TraceId
  for span_id: Trace.SpanId
  for restarted: Trace.LocalContext
  for accepted: {Trace.Context.restart_from_ids(previous, trace_id, span_id) == Done{restarted} :
    Result<&2, &2, Trace.ContextError, Trace.LocalContext>}
  {restarted == Trace.Context.root_from_ids(trace_id, span_id) : Trace.LocalContext} &
  {Trace.TraceId.to_string(trace_id) != Trace.TraceId.to_string(Trace.RemoteContext.trace_id(previous)) : String}

# A restart reusing the received trace ID is rejected.
law restart_reuse:
  for previous: Trace.RemoteContext
  for trace_id: Trace.TraceId
  for span_id: Trace.SpanId
  for reused: {Trace.TraceId.to_string(trace_id) ==
    Trace.TraceId.to_string(Trace.RemoteContext.trace_id(previous)) : String}
  {Trace.Context.restart_from_ids(previous, trace_id, span_id) == Fail{Trace.ReusedTraceId{}} :
    Result<&2, &2, Trace.ContextError, Trace.LocalContext>}

# Every other trace ID is accepted: reuse is the only reason to refuse a restart.
law restart_accepts:
  for previous: Trace.RemoteContext
  for trace_id: Trace.TraceId
  for span_id: Trace.SpanId
  for distinct: {Trace.TraceId.to_string(trace_id) !=
    Trace.TraceId.to_string(Trace.RemoteContext.trace_id(previous)) : String}
  {Trace.Context.restart_from_ids(previous, trace_id, span_id) ==
    Done{Trace.Context.root_from_ids(trace_id, span_id)} : Result<&2, &2, Trace.ContextError, Trace.LocalContext>}

# Identifiers from words. Words are converted most significant first: a
# candidate trace ID's text is its four words' texts in order, and a span ID's
# its two. No information is lost converting a word.
law trace_words:
  for first: U32
  for second: U32
  for third: U32
  for fourth: U32
  for id: Trace.TraceId
  for made: {Trace.TraceId.from_words(first, second, third, fourth) == Some{id} : Maybe<&2, Trace.TraceId>}
  {Trace.TraceId.to_string(id) ==
    Trace.U32.to_hex(first) ++ Trace.U32.to_hex(second) ++ Trace.U32.to_hex(third) ++ Trace.U32.to_hex(fourth) : String}

law span_words:
  for first: U32
  for second: U32
  for id: Trace.SpanId
  for made: {Trace.SpanId.from_words(first, second) == Some{id} : Maybe<&2, Trace.SpanId>}
  {Trace.SpanId.to_string(id) == Trace.U32.to_hex(first) ++ Trace.U32.to_hex(second) : String}

law hex_injective:
  for left: U32
  for right: U32
  for same: {Trace.U32.to_hex(left) == Trace.U32.to_hex(right) : String}
  {left == right : U32}

# The value of a lowercase hexadecimal digit: its position in `alphabet`,
# counted from `index`.
def hex_digit_value(alphabet: String, +char: Char, +index: Nat) -> Nat:
  match alphabet:
    case SNil{}:
      index
    case SCon{candidate, rest}:
      Bool.pick(Nat, Char.is_eq(char, candidate), index, hex_digit_value(rest, char, 1n+index))

def times16(value: Nat) -> Nat:
  Nat.double(Nat.double(Nat.double(Nat.double(value))))

# The value of a hexadecimal numeral, its first digit most significant.
def hex_numeral(text: String, value: Nat) -> Nat:
  match text:
    case SNil{}:
      value
    case SCon{char, rest}:
      hex_numeral(rest, Nat.add(hex_digit_value("0123456789abcdef", char, 0n), times16(value)))

# Digits are big-endian within a word too: a word's text is the base-16
# numeral of the number Base assigns to the word.
law word_hex:
  for word: U32
  {hex_numeral(Trace.U32.to_hex(word), 0n) == U32.to_nat(word) : Nat}

# Converting words makes no randomness assertion, as parsing makes none;
# generation makes it (generated_root, generated_restart).
law words_unasserted:
  for first: U32
  for second: U32
  for third: U32
  for fourth: U32
  for id: Trace.TraceId
  for made: {Trace.TraceId.from_words(first, second, third, fourth) == Some{id} : Maybe<&2, Trace.TraceId>}
  {Trace.TraceId.is_random(id) == False{} : Bool}

# A source error ends a generation at once.
law feed_failure:
  for code: U32
  for message: String
  for draw: Trace.Draw
  {Trace.Draw.feed(Fail{(code, message)}, draw) == Trace.Failed{Trace.SourceFailure{code, message}} : Trace.Step}

# A tape of source results, and what reading it leaves.
def Tape() -> Type:
  List<&1, Result<&1, &1, U32 & String, U32>>

def TapeStep() -> Type:
  Tape() & Trace.Step

def TapeOutcome() -> Type:
  Tape() & Result<&2, &2, Trace.GenerationError, Trace.LocalContext>

# The value an IO action produces when every effect in it is pure.
def Observe(-A: Type, action: IO(A)) -> IO.OP<A>:
  action(A, value => Emit{value})

def zeros(count: Nat) -> Tape():
  match count:
    case 0n:
      Nil{}
    case 1n+p:
      Con{Done{0}, zeros(p)}

# Generating from a tape performs exactly the pure tape driver: the same words
# are read, in order, and the unread words are handed back.
law root_tape:
  for tape: Tape()
  {Observe(TapeOutcome(), Trace.Context.root_with(~Tape(), ~Trace.Source.tape, tape)) ==
    Emit{Trace.Draw.outcome(Tape(), Trace.Draw.run(48n, (tape, Trace.Draw.root())))} : IO.OP<TapeOutcome()>}

law child_tape:
  for tape: Tape()
  for parent: Trace.Parent
  for sampling: Trace.Sampling
  {Observe(TapeOutcome(), Trace.Context.child_with(~Tape(), ~Trace.Source.tape, tape, parent, sampling)) ==
    Emit{Trace.Draw.outcome(Tape(), Trace.Draw.run(16n, (tape, Trace.Draw.child(parent, sampling))))} :
    IO.OP<TapeOutcome()>}

law restart_tape:
  for tape: Tape()
  for previous: Trace.RemoteContext
  {Observe(TapeOutcome(), Trace.Context.restart_with(~Tape(), ~Trace.Source.tape, tape, previous)) ==
    Emit{Trace.Draw.outcome(Tape(), Trace.Draw.run(48n, (tape, Trace.Draw.restart(previous))))} :
    IO.OP<TapeOutcome()>}

# Whatever a tape holds, a root or restart ends within 48 words and a child
# within 16: eight candidates of four words and eight of two.
law root_ends:
  for tape: Tape()
  {Trace.Draw.ended(Trace.Draw.run(48n, (tape, Trace.Draw.root()))) == True{} : Bool}

law child_ends:
  for tape: Tape()
  for +parent: Trace.Parent
  for +sampling: Trace.Sampling
  {Trace.Draw.ended(Trace.Draw.run(16n, (tape, Trace.Draw.child(parent, sampling)))) == True{} : Bool}

law restart_ends:
  for tape: Tape()
  for +previous: Trace.RemoteContext
  {Trace.Draw.ended(Trace.Draw.run(48n, (tape, Trace.Draw.restart(previous)))) == True{} : Bool}

# Eight all-zero candidates exhaust a root's trace ID or a child's span ID
# without reading a ninth: the words after them stay on the tape.
law root_exhaustion:
  for rest: Tape()
  {Trace.Draw.run(48n, (List.append(&1, Result<&1, &1, U32 & String, U32>, zeros(32n), rest), Trace.Draw.root())) ==
    (rest, Trace.Failed{Trace.ExhaustedTraceId{}}) : TapeStep()}

law child_exhaustion:
  for parent: Trace.Parent
  for sampling: Trace.Sampling
  for rest: Tape()
  {Trace.Draw.run(16n, (List.append(&1, Result<&1, &1, U32 & String, U32>, zeros(16n), rest),
    Trace.Draw.child(parent, sampling))) == (rest, Trace.Failed{Trace.ExhaustedSpanId{}}) : TapeStep()}

# A generated root asserts random-trace-id and is not sampled: flags 02.
law generated_root:
  for tape: Tape()
  for rest: Tape()
  for created: Trace.LocalContext
  for generated: {Trace.Draw.run(48n, (tape, Trace.Draw.root())) == (rest, Trace.Created{created}) : TapeStep()}
  {Trace.TraceId.is_random(Trace.LocalContext.trace_id(created)) == True{} : Bool} &
  {Trace.LocalContext.is_sampled(created) == False{} : Bool}

# A generated child keeps the parent's trace ID and randomness assertion, takes
# sampled from the parent unless set, and never reuses the parent's span ID.
law generated_child:
  for tape: Tape()
  for +parent: Trace.Parent
  for +sampling: Trace.Sampling
  for rest: Tape()
  for created: Trace.LocalContext
  for generated: {Trace.Draw.run(16n, (tape, Trace.Draw.child(parent, sampling))) ==
    (rest, Trace.Created{created}) : TapeStep()}
  {Trace.LocalContext.trace_id(created) == Trace.Parent.trace_id(parent) : Trace.TraceId} &
  {Trace.LocalContext.is_sampled(created) == Trace.Sampling.resolve(sampling, Trace.Parent.is_sampled(parent)) : Bool} &
  {Trace.SpanId.to_string(Trace.LocalContext.span_id(created)) !=
    Trace.SpanId.to_string(Trace.Parent.span_id(parent)) : String}

# A generated restart starts a new trace: its trace ID differs from the
# received one and asserts randomness, and it is not sampled.
law generated_restart:
  for tape: Tape()
  for +previous: Trace.RemoteContext
  for rest: Tape()
  for created: Trace.LocalContext
  for generated: {Trace.Draw.run(48n, (tape, Trace.Draw.restart(previous))) ==
    (rest, Trace.Created{created}) : TapeStep()}
  {Trace.TraceId.to_string(Trace.LocalContext.trace_id(created)) !=
    Trace.TraceId.to_string(Trace.RemoteContext.trace_id(previous)) : String} &
  {Trace.TraceId.is_random(Trace.LocalContext.trace_id(created)) == True{} : Bool} &
  {Trace.LocalContext.is_sampled(created) == False{} : Bool}
