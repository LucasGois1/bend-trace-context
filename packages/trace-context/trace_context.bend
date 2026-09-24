import Base
import ./src/hex.bend as Hex
import ./src/digits.bend as Digits

type Field is Data:
  TraceIdField{}
  ParentIdField{}

type Error is Data:
  UnexpectedEnd{offset: Nat}
  InvalidHex{offset: Nat}
  ExpectedSeparator{offset: Nat}
  TrailingInput{}
  ForbiddenVersion{}
  UnsupportedVersion{version: String}
  ZeroId{field: Field}

# Length and alphabet are structural. The IDs carry checked nonzero proofs.
type TraceParentV00 is Data:
  TraceParentV00{
    trace_id: Digits.NonZero<32n>,
    parent_id: Digits.NonZero<16n>,
    flags: Digits.Digits(2n)
  }

type Parsed<-n: Nat> is Data:
  Parsed{digits: Digits.Digits(n), rest: String}

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
