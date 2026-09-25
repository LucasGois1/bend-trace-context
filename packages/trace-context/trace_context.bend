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
        Digits.DCon{Hex.H0{}, Digits.DCon{Hex.Digit.from_low_bits(sampled, random), Digits.DNil{}}}}

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

# Start a trace with supplied IDs. A new root is not sampled. The names
# Context.root, Context.child and Context.restart are left for generated IDs.
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
