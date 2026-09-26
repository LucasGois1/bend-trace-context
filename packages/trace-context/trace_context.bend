import Base
import ./src/hex.bend as Hex
import ./src/digits.bend as Digits

type Field is Data:
  TraceIdField{}
  ParentIdField{}
  SpanIdField{}

type Error is Data:
  UnexpectedEnd{offset: Nat}
  InvalidHex{offset: Nat}
  ExpectedSeparator{offset: Nat}
  TrailingInput{}
  ForbiddenVersion{}
  UnsupportedVersion{version: String}
  ZeroId{field: Field}

# Why creating a context from supplied IDs was refused.
type ContextError is Data:
  ReusedSpanId{}
  ReusedTraceId{}

type Parsed<-n: Nat> is Data:
  Parsed{digits: Digits.Digits(n), rest: String}

# Length and alphabet are structural. The IDs carry checked nonzero proofs.
type TraceParentV00 is Data:
  TraceParentV00{
    trace_id: Digits.NonZero<32n>,
    parent_id: Digits.NonZero<16n>,
    flags: Digits.Digits(2n)
  }

# A validated trace ID. `random` records whether the random-trace-id flag may
# be emitted for it. A parsed ID makes no such assertion; only its origin can
# justify one.
type TraceId is Data:
  TraceId{value: Digits.NonZero<32n>, random: Bool}

# A validated span ID: the nonzero identifier of one operation.
type SpanId is Data:
  SpanId{value: Digits.NonZero<16n>}

# How a child operation obtains its sampled indication.
type Sampling is Data:
  InheritSampled{}
  SetSampled{sampled: Bool}

# A context received from another participant. It identifies the sender's
# operation and keeps only the known flags: sampled and random-trace-id.
type RemoteContext is Data:
  RemoteContext{trace_id: TraceId, span_id: SpanId, sampled: Bool}

# A context that identifies an operation of this participant.
type LocalContext is Data:
  LocalContext{trace_id: TraceId, span_id: SpanId, sampled: Bool}

# The context whose trace a child operation continues.
type Parent is Data:
  RemoteParent{context: RemoteContext}
  LocalParent{context: LocalContext}

# Why generating identifiers failed. A source failure carries the source's own
# code and message; exhaustion names the identifier whose eight candidates
# were all rejected.
type GenerationError is Data:
  SourceFailure{code: U32, message: String}
  ExhaustedTraceId{}
  ExhaustedSpanId{}

# The words read so far for the current trace ID candidate, in arrival order.
type TraceWords is Data:
  NoTraceWord{}
  OneTraceWord{first: U32}
  TwoTraceWords{first: U32, second: U32}
  ThreeTraceWords{first: U32, second: U32, third: U32}

# The words read so far for the current span ID candidate.
type SpanWords is Data:
  NoSpanWord{}
  OneSpanWord{first: U32}

# The generation machine below is shared by the IO operations and stated in
# the laws. Its types and `Draw` functions are internal: callers use the
# `Context.*_with` operations or generation.bend.

# What a new local context needs besides its span ID. `parent` is the span ID
# that a child must not reuse.
type SpanPlan is Data:
  SpanPlan{trace_id: TraceId, sampled: Bool, parent: Maybe<&2, SpanId>}

# A generation in progress. `remaining` counts the further candidates allowed
# after the current one, so each identifier gets eight candidates in all.
# `previous` is the received trace ID that a restart must not reuse.
type Draw is Data:
  DrawTrace{remaining: Nat, words: TraceWords, previous: Maybe<&2, TraceId>}
  DrawSpan{remaining: Nat, words: SpanWords, plan: SpanPlan}

# The state of a generation after each source word.
type Step is Data:
  NeedWord{draw: Draw}
  Created{context: LocalContext}
  Failed{error: GenerationError}

def Parsed.prepend(-n: Nat, digit: Hex.Digit, parsed: Parsed<n>) -> Parsed<1n+n>:
  match parsed:
    case Parsed{digits, rest}:
      Parsed{Digits.DCon{digit, digits}, rest}

def Parse.digit_result(value: Maybe<&2, Hex.Digit>, offset: Nat) ->
  Result<&2, &2, Error, Hex.Digit>:
  match value:
    case None{}:
      Fail{InvalidHex{offset}}
    case Some{digit}:
      Done{digit}

def Parse.digit(char: Char, offset: Nat) -> Result<&2, &2, Error, Hex.Digit>:
  Parse.digit_result(Hex.Digit.from_char(char), offset)

# Consume exactly n characters, retaining the unconsumed input.
# Recursion decreases n; no fuel guess or unchecked conversion is needed.
def Parse.digits(n: Nat, text: String, offset: Nat) ->
  Result<&2, &2, Error, Parsed<n>>:
  match n:
    case 0n:
      Done{Parsed{Digits.DNil{}, text}}
    case 1n+p:
      match text:
        case SNil{}:
          Fail{UnexpectedEnd{offset}}
        case SCon{char, tail}:
          +at = offset
          do Result<&2, &2, Error, Parsed<1n+p>>:
            digit : Hex.Digit <- Parse.digit(char, at)
            parsed : Parsed<p> <- Parse.digits(p, tail, 1n+at)
            return Parsed.prepend(p, digit, parsed)

def Parse.separator_result(tail: String, ok: Bool, offset: Nat) ->
  Result<&2, &2, Error, String>:
  match ok:
    case False{}:
      Fail{ExpectedSeparator{offset}}
    case True{}:
      Done{tail}

def Parse.separator(text: String, offset: Nat) -> Result<&2, &2, Error, String>:
  match text:
    case SNil{}:
      Fail{UnexpectedEnd{offset}}
    case SCon{char, tail}:
      Parse.separator_result(tail, Char.is_eq(char, '-'), offset)

def Parse.end(text: String) -> Result<&2, &2, Error, Unit>:
  match text:
    case SNil{}:
      Done{Unit{}}
    case SCon{char, tail}:
      Fail{TrailingInput{}}

def Parse.version(digits: Digits.Digits(2n)) -> Result<&2, &2, Error, Unit>:
  match digits:
    case Digits.DCon{Hex.H0{}, Digits.DCon{Hex.H0{}, Digits.DNil{}}}:
      Done{Unit{}}
    case Digits.DCon{Hex.Hf{}, Digits.DCon{Hex.Hf{}, Digits.DNil{}}}:
      Fail{ForbiddenVersion{}}
    case other:
      Fail{UnsupportedVersion{Digits.Digits.to_string(2n, other)}}

def Parse.nonzero_result(-n: Nat, result: Maybe<&2, Digits.NonZero<n>>, field: Field) ->
  Result<&2, &2, Error, Digits.NonZero<n>>:
  match result:
    case None{}:
      Fail{ZeroId{field}}
    case Some{id}:
      Done{id}

def Parse.nonzero(n: Nat, digits: Digits.Digits(n), field: Field) ->
  Result<&2, &2, Error, Digits.NonZero<n>>:
  Parse.nonzero_result(n, Digits.NonZero.new(n, digits), field)

def Parse.flags(trace_id: Digits.NonZero<32n>, parent_id: Digits.NonZero<16n>,
  parsed: Parsed<2n>) -> Result<&2, &2, Error, TraceParentV00>:
  match parsed:
    case Parsed{flags, rest}:
      do Result<&2, &2, Error, TraceParentV00>:
        end : Unit <- Parse.end(rest)
        return TraceParentV00{trace_id, parent_id, flags}

def Parse.parent(trace_id: Digits.NonZero<32n>, parsed: Parsed<16n>) ->
  Result<&2, &2, Error, TraceParentV00>:
  match parsed:
    case Parsed{parent_digits, rest}:
      do Result<&2, &2, Error, TraceParentV00>:
        parent_id : Digits.NonZero<16n> <- Parse.nonzero(16n, parent_digits, ParentIdField{})
        after : String <- Parse.separator(rest, 52n)
        flags : Parsed<2n> <- Parse.digits(2n, after, 53n)
        Parse.flags(trace_id, parent_id, flags)

def Parse.trace(parsed: Parsed<32n>) -> Result<&2, &2, Error, TraceParentV00>:
  match parsed:
    case Parsed{trace_digits, rest}:
      do Result<&2, &2, Error, TraceParentV00>:
        trace_id : Digits.NonZero<32n> <- Parse.nonzero(32n, trace_digits, TraceIdField{})
        after : String <- Parse.separator(rest, 35n)
        parent : Parsed<16n> <- Parse.digits(16n, after, 36n)
        Parse.parent(trace_id, parent)

def Parse.start(parsed: Parsed<2n>) -> Result<&2, &2, Error, TraceParentV00>:
  match parsed:
    case Parsed{version, rest}:
      do Result<&2, &2, Error, TraceParentV00>:
        version_ok : Unit <- Parse.version(version)
        after : String <- Parse.separator(rest, 2n)
        trace : Parsed<32n> <- Parse.digits(32n, after, 3n)
        Parse.trace(trace)

# This is the strict v00 wire codec, not a complete W3C propagator.
def TraceParentV00.parse(text: String) -> Result<&2, &2, Error, TraceParentV00>:
  do Result<&2, &2, Error, TraceParentV00>:
    version : Parsed<2n> <- Parse.digits(2n, text, 0n)
    Parse.start(version)

# Total: validity is carried by the argument's type.
# All flag bits are preserved; this does not apply an outgoing-header policy.
def TraceParentV00.format(context: TraceParentV00) -> String:
  match context:
    case TraceParentV00{trace_id, parent_id, flags}:
      "00-" ++ Digits.NonZero.to_string(32n, trace_id) ++ "-" ++
        Digits.NonZero.to_string(16n, parent_id) ++ "-" ++
        Digits.Digits.to_string(2n, flags)

def TraceParentV00.is_sampled(context: TraceParentV00) -> Bool:
  match context:
    case TraceParentV00{trace_id, parent_id,
      Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}}:
      Hex.Digit.is_odd(low)

# Reads the random-trace-id flag (bit 1). It records the sender's assertion;
# it does not prove how the trace ID was generated.
def TraceParentV00.is_random(context: TraceParentV00) -> Bool:
  match context:
    case TraceParentV00{trace_id, parent_id,
      Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}}:
      Hex.Digit.has_bit1(low)

def Parse.id.finish(n: Nat, parsed: Parsed<n>, field: Field) ->
  Result<&2, &2, Error, Digits.NonZero<n>>:
  match parsed:
    case Parsed{digits, rest}:
      do Result<&2, &2, Error, Digits.NonZero<n>>:
        end : Unit <- Parse.end(rest)
        Parse.nonzero(n, digits, field)

# A supplied ID is exactly n lowercase hexadecimal digits, not all zero.
def Parse.id(+n: Nat, text: String, field: Field) ->
  Result<&2, &2, Error, Digits.NonZero<n>>:
  do Result<&2, &2, Error, Digits.NonZero<n>>:
    parsed : Parsed<n> <- Parse.digits(n, text, 0n)
    Parse.id.finish(n, parsed, field)

def TraceId.parse(text: String) -> Result<&2, &2, Error, TraceId>:
  do Result<&2, &2, Error, TraceId>:
    value : Digits.NonZero<32n> <- Parse.id(32n, text, TraceIdField{})
    return TraceId{value, False{}}

# Record the caller's assertion that these digits were generated randomly.
# The caller is responsible for it; validation cannot establish it.
def TraceId.assert_random(id: TraceId) -> TraceId:
  match id:
    case TraceId{value, random}:
      TraceId{value, True{}}

def TraceId.is_random(id: TraceId) -> Bool:
  match id:
    case TraceId{value, random}:
      random

def TraceId.to_string(id: TraceId) -> String:
  match id:
    case TraceId{value, random}:
      Digits.NonZero.to_string(32n, value)

# Compares identifiers; a randomness assertion is not part of the identifier.
def TraceId.is_eq(a: TraceId, b: TraceId) -> Bool:
  String.eq(TraceId.to_string(a), TraceId.to_string(b))

def SpanId.parse(text: String) -> Result<&2, &2, Error, SpanId>:
  do Result<&2, &2, Error, SpanId>:
    value : Digits.NonZero<16n> <- Parse.id(16n, text, SpanIdField{})
    return SpanId{value}

def SpanId.to_string(id: SpanId) -> String:
  match id:
    case SpanId{value}:
      Digits.NonZero.to_string(16n, value)

def SpanId.is_eq(a: SpanId, b: SpanId) -> Bool:
  String.eq(SpanId.to_string(a), SpanId.to_string(b))

def Sampling.resolve(sampling: Sampling, inherited: Bool) -> Bool:
  match sampling:
    case InheritSampled{}:
      inherited
    case SetSampled{sampled}:
      sampled

# Interpret a received strict-v00 value. Bit 0 is sampled and bit 1 is
# random-trace-id; the reserved bits are not interpreted.
def RemoteContext.from_traceparent(value: TraceParentV00) -> RemoteContext:
  match value:
    case TraceParentV00{trace_id, parent_id,
      Digits.DCon{high, Digits.DCon{+low, Digits.DNil{}}}}:
      RemoteContext{TraceId{trace_id, Hex.Digit.has_bit1(low)}, SpanId{parent_id},
        Hex.Digit.is_odd(low)}

def RemoteContext.trace_id(context: RemoteContext) -> TraceId:
  match context:
    case RemoteContext{trace_id, span_id, sampled}:
      trace_id

def RemoteContext.span_id(context: RemoteContext) -> SpanId:
  match context:
    case RemoteContext{trace_id, span_id, sampled}:
      span_id

def RemoteContext.is_sampled(context: RemoteContext) -> Bool:
  match context:
    case RemoteContext{trace_id, span_id, sampled}:
      sampled

def LocalContext.trace_id(context: LocalContext) -> TraceId:
  match context:
    case LocalContext{trace_id, span_id, sampled}:
      trace_id

def LocalContext.span_id(context: LocalContext) -> SpanId:
  match context:
    case LocalContext{trace_id, span_id, sampled}:
      span_id

def LocalContext.is_sampled(context: LocalContext) -> Bool:
  match context:
    case LocalContext{trace_id, span_id, sampled}:
      sampled

# The participating representation: version 00, and flags limited to sampled
# (bit 0) and random-trace-id (bit 1), with every reserved bit zero.
def LocalContext.to_traceparent(context: LocalContext) -> TraceParentV00:
  match context:
    case LocalContext{TraceId{trace_id, random}, SpanId{span_id}, sampled}:
      TraceParentV00{trace_id, span_id,
        Digits.DCon{Hex.H0{}, Digits.DCon{Hex.Digit.from_bits(sampled, random, False{}, False{}), Digits.DNil{}}}}

def Parent.trace_id(parent: Parent) -> TraceId:
  match parent:
    case RemoteParent{context}:
      RemoteContext.trace_id(context)
    case LocalParent{context}:
      LocalContext.trace_id(context)

def Parent.span_id(parent: Parent) -> SpanId:
  match parent:
    case RemoteParent{context}:
      RemoteContext.span_id(context)
    case LocalParent{context}:
      LocalContext.span_id(context)

def Parent.is_sampled(parent: Parent) -> Bool:
  match parent:
    case RemoteParent{context}:
      RemoteContext.is_sampled(context)
    case LocalParent{context}:
      LocalContext.is_sampled(context)

# Represent an operation the caller owns, using supplied IDs and an explicit
# sampled indication. Validation cannot establish where the IDs came from.
def Context.from_ids(trace_id: TraceId, span_id: SpanId, sampled: Bool) -> LocalContext:
  LocalContext{trace_id, span_id, sampled}

# Start a trace with supplied IDs. A new root is not sampled. generation.bend
# provides Context.root, Context.child and Context.restart for generated IDs.
def Context.root_from_ids(trace_id: TraceId, span_id: SpanId) -> LocalContext:
  Context.from_ids(trace_id, span_id, False{})

def Context.child_from_id.checked(trace_id: TraceId, span_id: SpanId, sampled: Bool, reused: Bool) ->
  Result<&2, &2, ContextError, LocalContext>:
  match reused:
    case True{}:
      Fail{ReusedSpanId{}}
    case False{}:
      Done{Context.from_ids(trace_id, span_id, sampled)}

# Continue the parent's trace with a new operation identified by a supplied
# span ID. The child keeps the trace ID and its randomness assertion, and its
# span ID must differ from the parent's. Sampling is inherited unless set.
def Context.child_from_id(+parent: Parent, +span_id: SpanId, sampling: Sampling) ->
  Result<&2, &2, ContextError, LocalContext>:
  Context.child_from_id.checked(Parent.trace_id(parent), span_id,
    Sampling.resolve(sampling, Parent.is_sampled(parent)),
    SpanId.is_eq(span_id, Parent.span_id(parent)))

def Context.restart_from_ids.checked(trace_id: TraceId, span_id: SpanId, reused: Bool) ->
  Result<&2, &2, ContextError, LocalContext>:
  match reused:
    case True{}:
      Fail{ReusedTraceId{}}
    case False{}:
      Done{Context.root_from_ids(trace_id, span_id)}

# Start a new trace with supplied IDs instead of continuing a received context.
# The new trace ID must differ from the received one, and the root defaults
# apply.
def Context.restart_from_ids(previous: RemoteContext, +trace_id: TraceId, span_id: SpanId) ->
  Result<&2, &2, ContextError, LocalContext>:
  Context.restart_from_ids.checked(trace_id, span_id,
    TraceId.is_eq(trace_id, RemoteContext.trace_id(previous)))

# The eight lowercase hexadecimal digits of a word, most significant first.
def U32.to_hex(word: U32) -> String:
  Digits.Digits.to_string(8n, Digits.Digits.of_u32(word))

# Identifiers from 32-bit words. Words are read most significant first: the
# first word supplies the first eight hexadecimal digits.
def TraceId.from_digits(value: Maybe<&2, Digits.NonZero<32n>>) -> Maybe<&2, TraceId>:
  match value:
    case None{}:
      None{}
    case Some{digits}:
      Some{TraceId{digits, False{}}}

# A trace ID from four words. Like a parsed ID it makes no randomness
# assertion; assert one with TraceId.assert_random when the words are random.
# An all-zero candidate is None.
def TraceId.from_words(first: U32, second: U32, third: U32, fourth: U32) -> Maybe<&2, TraceId>:
  TraceId.from_digits(Digits.NonZero.new(32n,
    Digits.Digits.append(8n, 24n, Digits.Digits.of_u32(first),
      Digits.Digits.append(8n, 16n, Digits.Digits.of_u32(second),
        Digits.Digits.append(8n, 8n, Digits.Digits.of_u32(third), Digits.Digits.of_u32(fourth))))))

def SpanId.from_digits(value: Maybe<&2, Digits.NonZero<16n>>) -> Maybe<&2, SpanId>:
  match value:
    case None{}:
      None{}
    case Some{digits}:
      Some{SpanId{digits}}

# A span ID from two words. An all-zero candidate is None.
def SpanId.from_words(first: U32, second: U32) -> Maybe<&2, SpanId>:
  SpanId.from_digits(Digits.NonZero.new(16n,
    Digits.Digits.append(8n, 8n, Digits.Digits.of_u32(first), Digits.Digits.of_u32(second))))

# A root draws its trace ID, then its span ID, and starts unsampled.
def Draw.root() -> Step:
  NeedWord{DrawTrace{7n, NoTraceWord{}, None{}}}

# A restart draws like a root but must not reuse the received trace ID.
def Draw.restart(previous: RemoteContext) -> Step:
  NeedWord{DrawTrace{7n, NoTraceWord{}, Some{RemoteContext.trace_id(previous)}}}

# A child keeps the parent's trace ID and draws a span ID other than the parent's.
def Draw.child(+parent: Parent, sampling: Sampling) -> Step:
  NeedWord{DrawSpan{7n, NoSpanWord{},
    SpanPlan{Parent.trace_id(parent), Sampling.resolve(sampling, Parent.is_sampled(parent)),
      Some{Parent.span_id(parent)}}}}

def Draw.retry_trace(remaining: Nat, previous: Maybe<&2, TraceId>) -> Step:
  match remaining:
    case 0n:
      Failed{ExhaustedTraceId{}}
    case 1n+p:
      NeedWord{DrawTrace{p, NoTraceWord{}, previous}}

# An accepted trace ID is followed by the span ID, with the root default
# sampled indication.
def Draw.accept_trace(trace_id: TraceId) -> Step:
  NeedWord{DrawSpan{7n, NoSpanWord{}, SpanPlan{trace_id, False{}, None{}}}}

def Draw.reuse_trace(reused: Bool, id: TraceId, previous: TraceId, remaining: Nat) -> Step:
  match reused:
    case True{}:
      Draw.retry_trace(remaining, Some{previous})
    case False{}:
      Draw.accept_trace(id)

def Draw.check_trace(candidate: Maybe<&2, TraceId>, previous: Maybe<&2, TraceId>, remaining: Nat) -> Step:
  match candidate:
    case None{}:
      Draw.retry_trace(remaining, previous)
    case Some{+id}:
      match previous:
        case None{}:
          Draw.accept_trace(id)
        case Some{+old}:
          Draw.reuse_trace(TraceId.is_eq(id, old), id, old, remaining)

def Draw.retry_span(remaining: Nat, plan: SpanPlan) -> Step:
  match remaining:
    case 0n:
      Failed{ExhaustedSpanId{}}
    case 1n+p:
      NeedWord{DrawSpan{p, NoSpanWord{}, plan}}

def Draw.accept_span(id: SpanId, plan: SpanPlan) -> Step:
  match plan:
    case SpanPlan{trace_id, sampled, parent}:
      Created{Context.from_ids(trace_id, id, sampled)}

def Draw.reuse_span(reused: Bool, id: SpanId, plan: SpanPlan, remaining: Nat) -> Step:
  match reused:
    case True{}:
      Draw.retry_span(remaining, plan)
    case False{}:
      Draw.accept_span(id, plan)

def Draw.check_span(candidate: Maybe<&2, SpanId>, plan: SpanPlan, remaining: Nat) -> Step:
  match candidate:
    case None{}:
      Draw.retry_span(remaining, plan)
    case Some{+id}:
      match plan:
        case SpanPlan{+trace_id, +sampled, None{}}:
          Draw.accept_span(id, SpanPlan{trace_id, sampled, None{}})
        case SpanPlan{+trace_id, +sampled, Some{+old}}:
          Draw.reuse_span(SpanId.is_eq(id, old), id, SpanPlan{trace_id, sampled, Some{old}}, remaining)

# Generation reads its words from a source trusted to be random, so each
# trace ID candidate asserts random-trace-id.
def Draw.asserted(candidate: Maybe<&2, TraceId>) -> Maybe<&2, TraceId>:
  match candidate:
    case None{}:
      None{}
    case Some{id}:
      Some{TraceId.assert_random(id)}

# Feed the next source word. A source error ends the generation at once.
def Draw.feed(word: Result<&1, &1, U32 & String, U32>, draw: Draw) -> Step:
  match word:
    case Fail{(code, message)}:
      Failed{SourceFailure{code, message}}
    case Done{next}:
      match draw:
        case DrawTrace{remaining, NoTraceWord{}, previous}:
          NeedWord{DrawTrace{remaining, OneTraceWord{next}, previous}}
        case DrawTrace{remaining, OneTraceWord{first}, previous}:
          NeedWord{DrawTrace{remaining, TwoTraceWords{first, next}, previous}}
        case DrawTrace{remaining, TwoTraceWords{first, second}, previous}:
          NeedWord{DrawTrace{remaining, ThreeTraceWords{first, second, next}, previous}}
        case DrawTrace{remaining, ThreeTraceWords{first, second, third}, previous}:
          Draw.check_trace(Draw.asserted(TraceId.from_words(first, second, third, next)), previous, remaining)
        case DrawSpan{remaining, NoSpanWord{}, plan}:
          NeedWord{DrawSpan{remaining, OneSpanWord{next}, plan}}
        case DrawSpan{remaining, OneSpanWord{first}, plan}:
          Draw.check_span(SpanId.from_words(first, next), plan, remaining)

# A generation that has not finished would report the identifier it was
# drawing. The root_ends, child_ends and restart_ends laws show that the
# budgets of the operations below make those cases unreachable.
def Step.result(step: Step) -> Result<&2, &2, GenerationError, LocalContext>:
  match step:
    case Created{context}:
      Done{context}
    case Failed{error}:
      Fail{error}
    case NeedWord{DrawTrace{remaining, words, previous}}:
      Fail{ExhaustedTraceId{}}
    case NeedWord{DrawSpan{remaining, words, plan}}:
      Fail{ExhaustedSpanId{}}

# Whether a generation has ended, with or without a context.
def Step.is_finished(step: Step) -> Bool:
  match step:
    case NeedWord{draw}:
      False{}
    case Created{context}:
      True{}
    case Failed{error}:
      True{}

# A deterministic word source for tests and replay: each read takes the next
# result, and an empty tape fails with code 1, tape-exhausted.
def Tape.next(tape: List<&1, Result<&1, &1, U32 & String, U32>>) ->
  List<&1, Result<&1, &1, U32 & String, U32>> & Result<&1, &1, U32 & String, U32>:
  match tape:
    case Nil{}:
      (Nil{}, Fail{(1, "tape-exhausted")})
    case Con{word, rest}:
      (rest, word)

def Draw.fed_by(-S: Type, got: S & Result<&1, &1, U32 & String, U32>, draw: Draw) -> S & Step:
  (state, word) = got
  (state, Draw.feed(word, draw))

# Whether the generation in a driver's result has ended.
def Draw.ended(result: List<&1, Result<&1, &1, U32 & String, U32>> & Step) -> Bool:
  (tape, step) = result
  Step.is_finished(step)

# Drive a generation from a tape, reading one word at a time and stopping as
# soon as it ends; unread words stay on the tape.
def Draw.run(fuel: Nat, current: List<&1, Result<&1, &1, U32 & String, U32>> & Step) ->
  List<&1, Result<&1, &1, U32 & String, U32>> & Step:
  match fuel current:
    case _ Tuple{tape, Created{context}}:
      (tape, Created{context})
    case _ Tuple{tape, Failed{error}}:
      (tape, Failed{error})
    case 0n Tuple{tape, NeedWord{draw}}:
      (tape, NeedWord{draw})
    case 1n+p Tuple{tape, NeedWord{draw}}:
      Draw.run(p, Draw.fed_by(List<&1, Result<&1, &1, U32 & String, U32>>, Tape.next(tape), draw))

# Words from a source reach a generation through `read`, which returns the
# source's next state with each word. A generation reads one word at a time and
# stops as soon as it ends; the final source state is handed back, so a caller
# can see what was read. Templates keep this driver free of any host effect:
# the effect, if any, lives in the source.
def Draw.read(~S: Type, ~read: S -> IO(S & Result<&1, &1, U32 & String, U32>), fuel: Nat,
  current: S & Step) -> IO(S & Step):
  match fuel current:
    case _ Tuple{state, Created{context}}:
      IO.pure(S & Step, (state, Created{context}))
    case _ Tuple{state, Failed{error}}:
      IO.pure(S & Step, (state, Failed{error}))
    case 0n Tuple{state, NeedWord{draw}}:
      IO.pure(S & Step, (state, NeedWord{draw}))
    case 1n+p Tuple{state, NeedWord{draw}}:
      IO.bind(S & Result<&1, &1, U32 & String, U32>, S & Step, read(state),
        got => Draw.read(~S, ~read, p, Draw.fed_by(S, got, draw)))

def Draw.outcome(-S: Type, done: S & Step) -> S & Result<&2, &2, GenerationError, LocalContext>:
  (state, step) = done
  (state, Step.result(step))

def Draw.finished(~S: Type, action: IO(S & Step)) -> IO(S & Result<&2, &2, GenerationError, LocalContext>):
  IO.bind(S & Step, S & Result<&2, &2, GenerationError, LocalContext>, action,
    done => IO.pure(S & Result<&2, &2, GenerationError, LocalContext>, Draw.outcome(S, done)))

# Generated contexts from a caller's source. `read` returns the source's next
# state with each word result. The source is trusted to be random: a
# generated trace ID asserts random-trace-id. A root or restart reads at most
# 48 words: eight trace ID candidates of four words and eight span ID
# candidates of two. A child reads at most 16.
def Context.root_with(~S: Type, ~read: S -> IO(S & Result<&1, &1, U32 & String, U32>), source: S) ->
  IO(S & Result<&2, &2, GenerationError, LocalContext>):
  Draw.finished(~S, Draw.read(~S, ~read, 48n, (source, Draw.root())))

def Context.child_with(~S: Type, ~read: S -> IO(S & Result<&1, &1, U32 & String, U32>), source: S,
  parent: Parent, sampling: Sampling) -> IO(S & Result<&2, &2, GenerationError, LocalContext>):
  Draw.finished(~S, Draw.read(~S, ~read, 16n, (source, Draw.child(parent, sampling))))

def Context.restart_with(~S: Type, ~read: S -> IO(S & Result<&1, &1, U32 & String, U32>), source: S,
  previous: RemoteContext) -> IO(S & Result<&2, &2, GenerationError, LocalContext>):
  Draw.finished(~S, Draw.read(~S, ~read, 48n, (source, Draw.restart(previous))))

# A deterministic source that replays a tape of word results.
def Source.tape(tape: List<&1, Result<&1, &1, U32 & String, U32>>) ->
  IO(List<&1, Result<&1, &1, U32 & String, U32>> & Result<&1, &1, U32 & String, U32>):
  IO.pure(List<&1, Result<&1, &1, U32 & String, U32>> & Result<&1, &1, U32 & String, U32>, Tape.next(tape))

def Error.show(error: Error) -> String:
  match error:
    case UnexpectedEnd{offset}:
      "UnexpectedEnd at " ++ Nat.show(offset)
    case InvalidHex{offset}:
      "InvalidHex at " ++ Nat.show(offset)
    case ExpectedSeparator{offset}:
      "ExpectedSeparator at " ++ Nat.show(offset)
    case TrailingInput{}:
      "TrailingInput"
    case ForbiddenVersion{}:
      "ForbiddenVersion"
    case UnsupportedVersion{version}:
      "UnsupportedVersion " ++ version
    case ZeroId{TraceIdField{}}:
      "ZeroTraceId"
    case ZeroId{ParentIdField{}}:
      "ZeroParentId"
    case ZeroId{SpanIdField{}}:
      "ZeroSpanId"

def ContextError.show(error: ContextError) -> String:
  match error:
    case ReusedSpanId{}:
      "ReusedSpanId"
    case ReusedTraceId{}:
      "ReusedTraceId"

def GenerationError.show(error: GenerationError) -> String:
  match error:
    case SourceFailure{code, message}:
      "SourceFailure " ++ U32.show(code) ++ " " ++ message
    case ExhaustedTraceId{}:
      "ExhaustedTraceId"
    case ExhaustedSpanId{}:
      "ExhaustedSpanId"

# Why a limit configuration was refused. The first failing rule is reported.
type LimitsError is Data:
  TraceParentInputTooSmall{}
  TraceStateOutputTooSmall{}
  TraceStateInputTooSmall{}

# A configuration must accept its own emitted representation: a traceparent
# input budget of at least 55 octets, and a tracestate input budget no smaller
# than an output budget of at least 512 octets.
def Limits.is_valid(traceparent_input: Nat, tracestate_input: Nat, +tracestate_output: Nat) -> Bool:
  Bool.and(Nat.is_ge(traceparent_input, 55n),
    Bool.and(Nat.is_ge(tracestate_output, 512n), Nat.is_ge(tracestate_input, tracestate_output)))

# Budgets in UTF-8 octets. The input budgets bound a received traceparent value
# and a combined tracestate value; the output budget is the most an emitted
# tracestate may take.
type Limits is Data:
  Limits{
    traceparent_input: Nat,
    tracestate_input: Nat,
    tracestate_output: Nat,
    evidence: {Limits.is_valid(traceparent_input, tracestate_input, tracestate_output) == True{} : Bool}
  }

def Limits.error(traceparent_input: Nat, tracestate_output: Nat) -> LimitsError:
  Bool.pick(LimitsError, Nat.is_lt(traceparent_input, 55n), TraceParentInputTooSmall{},
    Bool.pick(LimitsError, Nat.is_lt(tracestate_output, 512n), TraceStateOutputTooSmall{},
      TraceStateInputTooSmall{}))

def Limits.new.checked(traceparent_input: Nat, tracestate_input: Nat, tracestate_output: Nat, valid: Bool,
  evidence: {Limits.is_valid(traceparent_input, tracestate_input, tracestate_output) == valid : Bool}) ->
  Result<&2, &2, LimitsError, Limits>:
  match valid:
    case True{}:
      Done{Limits{traceparent_input, tracestate_input, tracestate_output, evidence}}
    case False{}:
      Fail{Limits.error(traceparent_input, tracestate_output)}

# Validate a configuration. Budgets count UTF-8 octets.
def Limits.new(+traceparent_input: Nat, +tracestate_input: Nat, +tracestate_output: Nat) ->
  Result<&2, &2, LimitsError, Limits>:
  Limits.new.checked(traceparent_input, tracestate_input, tracestate_output,
    Limits.is_valid(traceparent_input, tracestate_input, tracestate_output), {==})

# 32 KiB for each received value and 512 octets for an emitted tracestate. The
# 512-octet output budget is this package's capacity policy, not a W3C maximum.
def Limits.default() -> Limits:
  Limits{32768n, 32768n, 512n, {==}}

def Limits.traceparent_input(limits: Limits) -> Nat:
  match limits:
    case Limits{traceparent_input, tracestate_input, tracestate_output, evidence}:
      traceparent_input

def Limits.tracestate_input(limits: Limits) -> Nat:
  match limits:
    case Limits{traceparent_input, tracestate_input, tracestate_output, evidence}:
      tracestate_input

def Limits.tracestate_output(limits: Limits) -> Nat:
  match limits:
    case Limits{traceparent_input, tracestate_input, tracestate_output, evidence}:
      tracestate_output

def LimitsError.show(error: LimitsError) -> String:
  match error:
    case TraceParentInputTooSmall{}:
      "TraceParentInputTooSmall"
    case TraceStateOutputTooSmall{}:
      "TraceStateOutputTooSmall"
    case TraceStateInputTooSmall{}:
      "TraceStateInputTooSmall"

# Why a tracestate key, value or received member was refused.
type EntryError is Data:
  MissingEquals{}
  InvalidKey{}
  InvalidValue{}

def StateChar.in_range(+code: U32, low: U32, high: U32) -> Bool:
  Bool.and(U32.is_ge(code, low), U32.is_le(code, high))

# lcalpha / DIGIT: a lowercase ASCII letter (%x61-7A) or a digit (%x30-39).
def StateChar.is_key_start(char: Char) -> Bool:
  match char:
    case Chr{+code}:
      Bool.or(StateChar.in_range(code, 97, 122), StateChar.in_range(code, 48, 57))

# keychar: lcalpha / DIGIT / "_" / "-" / "*" / "/" / "@".
def StateChar.is_key(+char: Char) -> Bool:
  Bool.or(StateChar.is_key_start(char), Bool.or(Char.is_eq(char, '_'), Bool.or(Char.is_eq(char, '-'),
    Bool.or(Char.is_eq(char, '*'), Bool.or(Char.is_eq(char, '/'), Char.is_eq(char, '@'))))))

# nblk-chr: %x21-2B / %x2D-3C / %x3E-7E, printable ASCII other than space, ","
# and "=".
def StateChar.is_value_end(char: Char) -> Bool:
  match char:
    case Chr{+code}:
      Bool.or(StateChar.in_range(code, 33, 43), Bool.or(StateChar.in_range(code, 45, 60),
        StateChar.in_range(code, 62, 126)))

# chr: %x20 / nblk-chr.
def StateChar.is_value(+char: Char) -> Bool:
  Bool.or(Char.is_eq(char, ' '), StateChar.is_value_end(char))

# OWS: a space or a horizontal tab.
def StateChar.is_ows(+char: Char) -> Bool:
  Bool.or(Char.is_eq(char, ' '), Char.is_eq(char, '\t'))

# Every remaining character is a key character, and at most `room` remain.
def StateKey.valid.rest(text: String, room: Nat) -> Bool:
  match text:
    case SNil{}:
      True{}
    case SCon{char, tail}:
      match room:
        case 0n:
          False{}
        case 1n+left:
          Bool.and(StateChar.is_key(char), StateKey.valid.rest(tail, left))

# key = ( lcalpha / DIGIT ) 0*255( keychar ): 1 to 256 characters.
def StateKey.is_valid(text: String) -> Bool:
  match text:
    case SNil{}:
      False{}
    case SCon{char, tail}:
      Bool.and(StateChar.is_key_start(char), StateKey.valid.rest(tail, 255n))

# `char` is a value character followed by `tail`, of which at most `room`
# characters are allowed; the last character is not a space.
def StateValue.valid.go(tail: String, char: Char, room: Nat) -> Bool:
  match tail:
    case SNil{}:
      StateChar.is_value_end(char)
    case SCon{next, rest}:
      match room:
        case 0n:
          False{}
        case 1n+left:
          Bool.and(StateChar.is_value(char), StateValue.valid.go(rest, next, left))

# value = 0*255( chr ) nblk-chr: 1 to 256 printable ASCII characters other
# than "," and "=", the last of which is not a space.
def StateValue.is_valid(text: String) -> Bool:
  match text:
    case SNil{}:
      False{}
    case SCon{char, tail}:
      StateValue.valid.go(tail, char, 255n)

# A tracestate key, naming the vendor that owns an entry. The text carries a
# checked proof of the Level 2 key grammar.
type StateKey is Data:
  StateKey{text: String, evidence: {StateKey.is_valid(text) == True{} : Bool}}

# A tracestate value, opaque to every other vendor. Leading spaces are part of
# the value.
type StateValue is Data:
  StateValue{text: String, evidence: {StateValue.is_valid(text) == True{} : Bool}}

def StateKey.parse.checked(text: String, valid: Bool, evidence: {StateKey.is_valid(text) == valid : Bool}) ->
  Result<&2, &2, EntryError, StateKey>:
  match valid:
    case True{}:
      Done{StateKey{text, evidence}}
    case False{}:
      Fail{InvalidKey{}}

# Accept exactly a Level 2 key.
def StateKey.parse(+text: String) -> Result<&2, &2, EntryError, StateKey>:
  StateKey.parse.checked(text, StateKey.is_valid(text), {==})

def StateKey.to_string(key: StateKey) -> String:
  match key:
    case StateKey{text, evidence}:
      text

def StateValue.parse.checked(text: String, valid: Bool, evidence: {StateValue.is_valid(text) == valid : Bool}) ->
  Result<&2, &2, EntryError, StateValue>:
  match valid:
    case True{}:
      Done{StateValue{text, evidence}}
    case False{}:
      Fail{InvalidValue{}}

# Accept exactly a Level 2 value, leading spaces included. No whitespace is
# trimmed here: a trailing space is refused.
def StateValue.parse(+text: String) -> Result<&2, &2, EntryError, StateValue>:
  StateValue.parse.checked(text, StateValue.is_valid(text), {==})

def StateValue.to_string(value: StateValue) -> String:
  match value:
    case StateValue{text, evidence}:
      text

def EntryError.show(error: EntryError) -> String:
  match error:
    case MissingEquals{}:
      "MissingEquals"
    case InvalidKey{}:
      "InvalidKey"
    case InvalidValue{}:
      "InvalidValue"

# Why a received tracestate value was discarded: the combined value exceeds
# its input budget, it has more than 32 nonempty members, or one of its
# members is invalid. `member` numbers the comma-separated members of the
# combined value from zero, empty members included.
type StateError is Data:
  StateTooLarge{}
  TooManyMembers{}
  InvalidEntry{member: Nat, error: EntryError}

# One vendor's entry: a key and its value.
type StateEntry is Data:
  StateEntry{key: StateKey, value: StateValue}

def StateEntry.key(entry: StateEntry) -> StateKey:
  match entry:
    case StateEntry{key, value}:
      key

def StateEntry.value(entry: StateEntry) -> StateValue:
  match entry:
    case StateEntry{key, value}:
      value

def StateEntry.key_text(entry: StateEntry) -> String:
  StateKey.to_string(StateEntry.key(entry))

# `key=value`, as the entry is sent.
def StateEntry.format(entry: StateEntry) -> String:
  match entry:
    case StateEntry{key, value}:
      StateKey.to_string(key) ++ "=" ++ StateValue.to_string(value)

# Whether one of the entries has this key.
def Entries.has_key(entries: List<&2, StateEntry>, +key: String) -> Bool:
  match entries:
    case Nil{}:
      False{}
    case Con{entry, rest}:
      Bool.or(String.eq(StateEntry.key_text(entry), key), Entries.has_key(rest, key))

# No entry repeats the key of an entry before it; `seen` holds the entries
# already passed.
def Entries.unique(entries: List<&2, StateEntry>, +seen: List<&2, StateEntry>) -> Bool:
  match entries:
    case Nil{}:
      True{}
    case Con{+entry, rest}:
      Bool.and(Bool.not(Entries.has_key(seen, StateEntry.key_text(entry))),
        Entries.unique(rest, List.append(&2, StateEntry, seen, Con{entry, Nil{}})))

# Distinct keys and at most 32 entries.
def TraceState.is_valid(+entries: List<&2, StateEntry>) -> Bool:
  Bool.and(Entries.unique(entries, Nil{}), Nat.is_le(List.length(&2, StateEntry, entries), 32n))

# Ordered vendor state: at most 32 entries with distinct keys, leftmost first.
# The list carries a checked proof of both properties.
type TraceState is Data:
  TraceState{entries: List<&2, StateEntry>, evidence: {TraceState.is_valid(entries) == True{} : Bool}}

def TraceState.empty() -> TraceState:
  TraceState{Nil{}, {==}}

def TraceState.entries(state: TraceState) -> List<&2, StateEntry>:
  match state:
    case TraceState{entries, evidence}:
      entries

def TraceState.is_empty(state: TraceState) -> Bool:
  List.is_empty(&2, StateEntry, TraceState.entries(state))

def Entries.get.put(entry: StateEntry, rest: Maybe<&2, StateValue>, hit: Bool) -> Maybe<&2, StateValue>:
  match hit:
    case True{}:
      Some{StateEntry.value(entry)}
    case False{}:
      rest

def Entries.get(entries: List<&2, StateEntry>, +key: String) -> Maybe<&2, StateValue>:
  match entries:
    case Nil{}:
      None{}
    case Con{+entry, rest}:
      Entries.get.put(entry, Entries.get(rest, key), String.eq(StateEntry.key_text(entry), key))

# The value of the entry with this key, if there is one.
def TraceState.get(state: TraceState, key: StateKey) -> Maybe<&2, StateValue>:
  Entries.get(TraceState.entries(state), StateKey.to_string(key))

def Entries.format.rest(entries: List<&2, StateEntry>) -> String:
  match entries:
    case Nil{}:
      ""
    case Con{entry, rest}:
      "," ++ StateEntry.format(entry) ++ Entries.format.rest(rest)

def Entries.format(entries: List<&2, StateEntry>) -> String:
  match entries:
    case Nil{}:
      ""
    case Con{entry, rest}:
      StateEntry.format(entry) ++ Entries.format.rest(rest)

# The normalized value: the entries in order, joined by commas, with no
# optional whitespace. The empty state formats as "".
def TraceState.format(state: TraceState) -> String:
  Entries.format(TraceState.entries(state))

# The UTF-8 octets of a character. Bend characters are Unicode code points.
def Utf8.width(char: Char) -> Nat:
  match char:
    case Chr{+code}:
      Bool.pick(Nat, U32.is_lt(code, 128), 1n,
        Bool.pick(Nat, U32.is_lt(code, 2048), 2n,
          Bool.pick(Nat, U32.is_lt(code, 65536), 3n, 4n)))

# The UTF-8 octets of a text, in which the laws state every budget. Parsing
# measures with Utf8.left instead, which stops counting past the budget.
def Utf8.length(text: String) -> Nat:
  match text:
    case SNil{}:
      0n
    case SCon{char, tail}:
      Nat.add(Utf8.width(char), Utf8.length(tail))

# What is left of a budget after taking `need` octets, or None when less remains.
def Budget.take(need: Nat, budget: Nat) -> Maybe<&2, Nat>:
  match need budget:
    case 0n _:
      Some{budget}
    case 1n+more 0n:
      None{}
    case 1n+more 1n+left:
      Budget.take(more, left)

# What is left of a budget after a text, or None once the text exceeds it.
# Measuring stops at the first character beyond the budget.
def Utf8.left(text: String, budget: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match text budget:
    case _ None{}:
      None{}
    case SNil{} Some{left}:
      Some{left}
    case SCon{char, tail} Some{left}:
      Utf8.left(tail, Budget.take(Utf8.width(char), left))

# Fields after the first are measured with the comma that joins them. Once the
# budget is exceeded, no further field is visited.
def Utf8.left_more(fields: List<&2, String>, budget: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match fields budget:
    case Nil{} _:
      budget
    case Con{field, rest} None{}:
      None{}
    case Con{field, rest} Some{left}:
      Utf8.left_more(rest, Utf8.left(field, Utf8.left(",", Some{left})))

def Utf8.left_fields(fields: List<&2, String>, budget: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match fields:
    case Nil{}:
      budget
    case Con{field, rest}:
      Utf8.left_more(rest, Utf8.left(field, budget))

# Where reading the current member stands: before its key, with only optional
# whitespace so far; inside its key; or inside its value. Characters read are
# kept most recent first.
type Member is Data:
  Blank{}
  InKey{text: String}
  InValue{key: String, text: String}

# A tracestate being read: the members ended so far, empty ones included; how
# many more nonempty members are allowed; the current member; and the first
# entry of each key, in reading order. The scan and its helpers are internal.
type Scan is Data:
  Scanning{member: Nat, room: Nat, current: Member, entries: List<&2, StateEntry>}
  Stopped{error: StateError}

# A value's characters arrive most recent first. Restoring them skips optional
# whitespace until the first other character, then keeps every character, so
# the value comes back in reading order without its trailing whitespace.
def Value.restore.step(kept: Bool, ows: Bool, char: Char, value: String) -> Bool & String:
  match kept:
    case True{}:
      (True{}, SCon{char, value})
    case False{}:
      match ows:
        case True{}:
          (False{}, value)
        case False{}:
          (True{}, SCon{char, value})

def Value.restore.go(text: String, state: Bool & String) -> String:
  match text:
    case SNil{}:
      (kept, value) = state
      value
    case SCon{+char, tail}:
      (kept, value) = state
      Value.restore.go(tail, Value.restore.step(kept, StateChar.is_ows(char), char, value))

def Value.restore(text: String) -> String:
  Value.restore.go(text, (False{}, ""))

def Member.start(ows: Bool, equals: Bool, char: Char) -> Member:
  match ows:
    case True{}:
      Blank{}
    case False{}:
      match equals:
        case True{}:
          InValue{"", ""}
        case False{}:
          InKey{SCon{char, SNil{}}}

def Member.key(equals: Bool, char: Char, text: String) -> Member:
  match equals:
    case True{}:
      InValue{String.reverse(text), ""}
    case False{}:
      InKey{SCon{char, text}}

# A character other than a comma: optional whitespace before the key is
# skipped, and the first "=" ends the key.
def Member.push(+char: Char, current: Member) -> Member:
  match current:
    case Blank{}:
      Member.start(StateChar.is_ows(char), Char.is_eq(char, '='), char)
    case InKey{text}:
      Member.key(Char.is_eq(char, '='), char, text)
    case InValue{key, text}:
      InValue{key, SCon{char, text}}

def Scan.validate(key: String, value: String) -> Result<&2, &2, EntryError, StateEntry>:
  do Result<&2, &2, EntryError, StateEntry>:
    parsed_key : StateKey <- StateKey.parse(key)
    parsed_value : StateValue <- StateValue.parse(value)
    return StateEntry{parsed_key, parsed_value}

def Entries.add.if(entries: List<&2, StateEntry>, entry: StateEntry, present: Bool) -> List<&2, StateEntry>:
  match present:
    case True{}:
      entries
    case False{}:
      List.append(&2, StateEntry, entries, Con{entry, Nil{}})

# Keep only the first entry of each key.
def Entries.add(+entries: List<&2, StateEntry>, +entry: StateEntry) -> List<&2, StateEntry>:
  Entries.add.if(entries, entry, Entries.has_key(entries, StateEntry.key_text(entry)))

# A valid member counts toward the 32 allowed before duplicates are dropped.
def Scan.keep(room: Nat, member: Nat, entry: StateEntry, entries: List<&2, StateEntry>) -> Scan:
  match room:
    case 0n:
      Stopped{TooManyMembers{}}
    case 1n+left:
      Scanning{1n+member, left, Blank{}, Entries.add(entries, entry)}

def Scan.entry(parsed: Result<&2, &2, EntryError, StateEntry>, member: Nat, room: Nat,
  entries: List<&2, StateEntry>) -> Scan:
  match parsed:
    case Fail{error}:
      Stopped{InvalidEntry{member, error}}
    case Done{entry}:
      Scan.keep(room, member, entry, entries)

# The current member ends at a comma or with the value. An empty member is
# ignored; trailing optional whitespace is not part of a value.
def Scan.close(member: Nat, room: Nat, current: Member, entries: List<&2, StateEntry>) -> Scan:
  match current:
    case Blank{}:
      Scanning{1n+member, room, Blank{}, entries}
    case InKey{text}:
      Stopped{InvalidEntry{member, MissingEquals{}}}
    case InValue{key, text}:
      Scan.entry(Scan.validate(key, Value.restore(text)), member, room, entries)

def Scan.read(comma: Bool, char: Char, member: Nat, room: Nat, current: Member,
  entries: List<&2, StateEntry>) -> Scan:
  match comma:
    case True{}:
      Scan.close(member, room, current, entries)
    case False{}:
      Scanning{member, room, Member.push(char, current), entries}

def Scan.char(+char: Char, scan: Scan) -> Scan:
  match scan:
    case Stopped{error}:
      Stopped{error}
    case Scanning{member, room, current, entries}:
      Scan.read(Char.is_eq(char, ','), char, member, room, current, entries)

# Read a text one character at a time, stopping at the first problem.
def Scan.text(text: String, scan: Scan) -> Scan:
  match text scan:
    case _ Stopped{error}:
      Stopped{error}
    case SNil{} Scanning{member, room, current, entries}:
      Scanning{member, room, current, entries}
    case SCon{char, tail} Scanning{member, room, current, entries}:
      Scan.text(tail, Scan.char(char, Scanning{member, room, current, entries}))

# Fields after the first are read after the comma that joins them.
def Scan.more(fields: List<&2, String>, scan: Scan) -> Scan:
  match fields:
    case Nil{}:
      scan
    case Con{field, rest}:
      Scan.more(rest, Scan.text(field, Scan.char(',', scan)))

def Scan.fields(fields: List<&2, String>, scan: Scan) -> Scan:
  match fields:
    case Nil{}:
      scan
    case Con{field, rest}:
      Scan.more(rest, Scan.text(field, scan))

def Scan.start() -> Scan:
  Scanning{0n, 32n, Blank{}, Nil{}}

# The scan keeps only the first entry of each key and stops at a 33rd member,
# so this check is not expected to fail: the laws prove it passes for
# normalized values, and the corpus exercises the rest. A failure would be
# reported as too many members.
def Scan.state(entries: List<&2, StateEntry>, valid: Bool,
  evidence: {TraceState.is_valid(entries) == valid : Bool}) -> Result<&2, &2, StateError, TraceState>:
  match valid:
    case True{}:
      Done{TraceState{entries, evidence}}
    case False{}:
      Fail{TooManyMembers{}}

def Scan.result(scan: Scan) -> Result<&2, &2, StateError, TraceState>:
  match scan:
    case Stopped{error}:
      Fail{error}
    case Scanning{member, room, current, +entries}:
      Scan.state(entries, TraceState.is_valid(entries), {==})

# The last member ends with the value.
def Scan.finish(scan: Scan) -> Result<&2, &2, StateError, TraceState>:
  match scan:
    case Stopped{error}:
      Fail{error}
    case Scanning{member, room, current, entries}:
      Scan.result(Scan.close(member, room, current, entries))

def Scan.within(fits: Maybe<&2, Nat>, fields: List<&2, String>) -> Result<&2, &2, StateError, TraceState>:
  match fits:
    case None{}:
      Fail{StateTooLarge{}}
    case Some{left}:
      Scan.finish(Scan.fields(fields, Scan.start()))

# Parse repeated tracestate field values, in arrival order, as their
# comma-joined combination. The combined value, joining commas included, must
# fit the tracestate input budget; a larger one is refused before any member
# is read, without measuring the rest. Empty members are ignored; every
# nonempty member must be a valid entry and counts toward the 32 allowed; the
# first entry of each key is kept.
def TraceState.parse_fields(limits: Limits, +fields: List<&2, String>) -> Result<&2, &2, StateError, TraceState>:
  Scan.within(Utf8.left_fields(fields, Some{Limits.tracestate_input(limits)}), fields)

# Parse one combined tracestate value.
def TraceState.parse(limits: Limits, text: String) -> Result<&2, &2, StateError, TraceState>:
  TraceState.parse_fields(limits, Con{text, Nil{}})

def StateError.show(error: StateError) -> String:
  match error:
    case StateTooLarge{}:
      "StateTooLarge"
    case TooManyMembers{}:
      "TooManyMembers"
    case InvalidEntry{member, reason}:
      "InvalidEntry " ++ Nat.show(member) ++ " " ++ EntryError.show(reason)
