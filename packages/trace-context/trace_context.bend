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
