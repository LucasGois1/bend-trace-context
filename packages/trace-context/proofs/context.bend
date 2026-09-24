import Base
import ../trace_context.bend as TC
import ../src/digits.bend as Digits
import ./digits.bend as DigitProof
import ./parser.bend as ParserProof

# These helpers name the existing Result continuations for rewrite motives.
# Unfolding them is definitionally the same computation as the public parser.
def flags_result(trace_id: Digits.NonZero<32n>, parent_id: Digits.NonZero<16n>,
  parsed: Result<&2, &2, TC.Error, TC.Parsed<2n>>) -> Result<&2, &2, TC.Error, TC.TraceParentV00>:
  do Result<&2, &2, TC.Error, TC.TraceParentV00>:
    flags : TC.Parsed<2n> <- parsed
    TC.Parse.flags(trace_id, parent_id, flags)

def parent_result(trace_id: Digits.NonZero<32n>,
  parsed: Result<&2, &2, TC.Error, TC.Parsed<16n>>) -> Result<&2, &2, TC.Error, TC.TraceParentV00>:
  do Result<&2, &2, TC.Error, TC.TraceParentV00>:
    parent : TC.Parsed<16n> <- parsed
    TC.Parse.parent(trace_id, parent)

def trace_result(parsed: Result<&2, &2, TC.Error, TC.Parsed<32n>>) ->
  Result<&2, &2, TC.Error, TC.TraceParentV00>:
  do Result<&2, &2, TC.Error, TC.TraceParentV00>:
    trace : TC.Parsed<32n> <- parsed
    TC.Parse.trace(trace)

def parent_valid_result(trace_id: Digits.NonZero<32n>, flags: Digits.Digits(2n),
  result: Maybe<&2, Digits.NonZero<16n>>) -> Result<&2, &2, TC.Error, TC.TraceParentV00>:
  do Result<&2, &2, TC.Error, TC.TraceParentV00>:
    parent_id : Digits.NonZero<16n> <- TC.Parse.nonzero_result(16n, result, TC.ParentIdField{})
    flags_result(trace_id, parent_id, TC.Parse.digits(2n, Digits.Digits.to_string(2n, flags), 53n))

def trace_valid_result(parent_id: Digits.NonZero<16n>, flags: Digits.Digits(2n),
  result: Maybe<&2, Digits.NonZero<32n>>) -> Result<&2, &2, TC.Error, TC.TraceParentV00>:
  do Result<&2, &2, TC.Error, TC.TraceParentV00>:
    trace_id : Digits.NonZero<32n> <- TC.Parse.nonzero_result(32n, result, TC.TraceIdField{})
    parent_result(trace_id, TC.Parse.digits(16n,
      Digits.NonZero.to_string(16n, parent_id) ++ "-" ++ Digits.Digits.to_string(2n, flags), 36n))

law flags_roundtrip:
  for trace_id: Digits.NonZero<32n>
  for parent_id: Digits.NonZero<16n>
  for flags: Digits.Digits(2n)
  {flags_result(trace_id, parent_id, TC.Parse.digits(2n, Digits.Digits.to_string(2n, flags), 53n)) ==
    Done{TC.TraceParentV00{trace_id, parent_id, flags}} : Result<&2, &2, TC.Error, TC.TraceParentV00>}

def flags_roundtrip(trace_id, parent_id, flags):
  match flags:
    case Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}:
      %Equal.sym(Result<&2, &2, TC.Error, TC.Parsed<2n>>,
        TC.Parse.digits(2n, Digits.Digits.to_string(2n, Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}), 53n),
        Done{TC.Parsed{Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}, ""}},
        ParserProof.digits_roundtrip(2n, Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}, "", 53n)) : {
          flags_result(trace_id, parent_id, _) ==
          Done{TC.TraceParentV00{trace_id, parent_id, Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}}} :
          Result<&2, &2, TC.Error, TC.TraceParentV00>}
      {==}

law parent_valid:
  for trace_id: Digits.NonZero<32n>
  for +parent_id: Digits.NonZero<16n>
  for flags: Digits.Digits(2n)
  {TC.Parse.parent(trace_id, TC.Parsed{Digits.NonZero.digits(16n, parent_id), "-" ++ Digits.Digits.to_string(2n, flags)}) ==
    Done{TC.TraceParentV00{trace_id, parent_id, flags}} : Result<&2, &2, TC.Error, TC.TraceParentV00>}

def parent_valid(trace_id, parent_id, flags):
  %Equal.sym(Maybe<&2, Digits.NonZero<16n>>,
    Digits.NonZero.new(16n, Digits.NonZero.digits(16n, parent_id)), Some{parent_id},
    DigitProof.new_recovery(16n, parent_id)) : {
      parent_valid_result(trace_id, flags, _) == Done{TC.TraceParentV00{trace_id, parent_id, flags}} :
      Result<&2, &2, TC.Error, TC.TraceParentV00>}
  flags_roundtrip(trace_id, parent_id, flags)

law parent_roundtrip:
  for trace_id: Digits.NonZero<32n>
  for +parent_id: Digits.NonZero<16n>
  for +flags: Digits.Digits(2n)
  {parent_result(trace_id, TC.Parse.digits(16n,
    Digits.NonZero.to_string(16n, parent_id) ++ "-" ++ Digits.Digits.to_string(2n, flags), 36n)) ==
    Done{TC.TraceParentV00{trace_id, parent_id, flags}} : Result<&2, &2, TC.Error, TC.TraceParentV00>}

def parent_roundtrip(trace_id, parent_id, flags):
  %Equal.sym(Result<&2, &2, TC.Error, TC.Parsed<16n>>,
    TC.Parse.digits(16n, Digits.NonZero.to_string(16n, parent_id) ++ "-" ++ Digits.Digits.to_string(2n, flags), 36n),
    Done{TC.Parsed{Digits.NonZero.digits(16n, parent_id), "-" ++ Digits.Digits.to_string(2n, flags)}},
    ParserProof.digits_roundtrip(16n, Digits.NonZero.digits(16n, parent_id), "-" ++ Digits.Digits.to_string(2n, flags), 36n)) : {
      parent_result(trace_id, _) == Done{TC.TraceParentV00{trace_id, parent_id, flags}} :
      Result<&2, &2, TC.Error, TC.TraceParentV00>}
  parent_valid(trace_id, parent_id, flags)

law trace_valid:
  for +trace_id: Digits.NonZero<32n>
  for parent_id: Digits.NonZero<16n>
  for flags: Digits.Digits(2n)
  {TC.Parse.trace(TC.Parsed{Digits.NonZero.digits(32n, trace_id),
    "-" ++ Digits.NonZero.to_string(16n, parent_id) ++ "-" ++ Digits.Digits.to_string(2n, flags)}) ==
    Done{TC.TraceParentV00{trace_id, parent_id, flags}} : Result<&2, &2, TC.Error, TC.TraceParentV00>}

def trace_valid(trace_id, parent_id, flags):
  %Equal.sym(Maybe<&2, Digits.NonZero<32n>>,
    Digits.NonZero.new(32n, Digits.NonZero.digits(32n, trace_id)), Some{trace_id},
    DigitProof.new_recovery(32n, trace_id)) : {
      trace_valid_result(parent_id, flags, _) == Done{TC.TraceParentV00{trace_id, parent_id, flags}} :
      Result<&2, &2, TC.Error, TC.TraceParentV00>}
  parent_roundtrip(trace_id, parent_id, flags)

law roundtrip:
  for context: TC.TraceParentV00
  {TC.TraceParentV00.parse(TC.TraceParentV00.format(context)) == Done{context} : Result<&2, &2, TC.Error, TC.TraceParentV00>}

def roundtrip(context):
  match context:
    case TC.TraceParentV00{+trace_id, +parent_id, +flags}:
      %Equal.sym(Result<&2, &2, TC.Error, TC.Parsed<32n>>,
        TC.Parse.digits(32n, Digits.NonZero.to_string(32n, trace_id) ++ "-" ++
          Digits.NonZero.to_string(16n, parent_id) ++ "-" ++ Digits.Digits.to_string(2n, flags), 3n),
        Done{TC.Parsed{Digits.NonZero.digits(32n, trace_id),
          "-" ++ Digits.NonZero.to_string(16n, parent_id) ++ "-" ++ Digits.Digits.to_string(2n, flags)}},
        ParserProof.digits_roundtrip(32n, Digits.NonZero.digits(32n, trace_id),
          "-" ++ Digits.NonZero.to_string(16n, parent_id) ++ "-" ++ Digits.Digits.to_string(2n, flags), 3n)) : {
          trace_result(_) == Done{TC.TraceParentV00{trace_id, parent_id, flags}} :
          Result<&2, &2, TC.Error, TC.TraceParentV00>}
      trace_valid(trace_id, parent_id, flags)
