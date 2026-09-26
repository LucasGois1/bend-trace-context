# Proofs: parsing a formatted traceparent
# =======================================
#
# Proves law roundtrip: parsing the text of any strict v00 value gives back
# exactly that value, including the proofs stored in it that its IDs are not
# all zero. PROOF.bend's Laws.roundtrip calls roundtrip, and
# proofs/inverse.bend (law inverse) reuses flags_result, parent_result and
# trace_result. trace_context.bend is imported as TC.
#
# The proof follows the parser forward over the formatted text. The prefix
# "00-" and the "-" before the parent ID and before the flags are literal
# characters, read by computation. The digits of each field are read back
# with ParserProof.digits_roundtrip, the rest of the text being the suffix,
# and the nonzero check of each ID gives back that very ID, its stored proof
# included, by DigitsProof.new_recovery. The `*_result` defs name the rest of
# the parser after one step, as a function of that step's result, so that a
# rewrite motive (the P of `%e : P`) can mark the result with `_`; unfolded,
# they are the parser's own steps. A def may only call the defs written above
# it, so the lemmas appear in reverse reading order: roundtrip, trace_valid,
# parent_roundtrip, parent_valid and flags_roundtrip.

import Base
import ../trace_context.bend as TC
import ../src/digits.bend as Digits
import ./digits.bend as DigitsProof
import ./parser.bend as ParserProof

# The last step of Parse.parent, as a function of the read of the two flag
# digits: Parse.flags on its success.
def flags_result(trace_id: Digits.NonZero<32n>, parent_id: Digits.NonZero<16n>,
  parsed: Result<&2, &2, TC.Error, TC.Parsed<2n>>) -> Result<&2, &2, TC.Error, TC.TraceParentV00>:
  do Result<&2, &2, TC.Error, TC.TraceParentV00>:
    flags : TC.Parsed<2n> <- parsed
    TC.Parse.flags(trace_id, parent_id, flags)

# The last step of Parse.trace, as a function of the read of the sixteen
# parent ID digits: Parse.parent on its success.
def parent_result(trace_id: Digits.NonZero<32n>,
  parsed: Result<&2, &2, TC.Error, TC.Parsed<16n>>) -> Result<&2, &2, TC.Error, TC.TraceParentV00>:
  do Result<&2, &2, TC.Error, TC.TraceParentV00>:
    parent : TC.Parsed<16n> <- parsed
    TC.Parse.parent(trace_id, parent)

# The last step of Parse.start, as a function of the read of the thirty-two
# trace ID digits: Parse.trace on its success.
def trace_result(parsed: Result<&2, &2, TC.Error, TC.Parsed<32n>>) ->
  Result<&2, &2, TC.Error, TC.TraceParentV00>:
  do Result<&2, &2, TC.Error, TC.TraceParentV00>:
    trace : TC.Parsed<32n> <- parsed
    TC.Parse.trace(trace)

# What Parse.parent computes when the parent ID's digits are followed by "-"
# and the flags' text, as a function of `result`, which stands for
# Digits.NonZero.new of those digits. parent_valid rewrites `result` into
# Some{parent_id}.
def parent_valid_result(trace_id: Digits.NonZero<32n>, flags: Digits.Digits(2n),
  result: Maybe<&2, Digits.NonZero<16n>>) -> Result<&2, &2, TC.Error, TC.TraceParentV00>:
  do Result<&2, &2, TC.Error, TC.TraceParentV00>:
    parent_id : Digits.NonZero<16n> <- TC.Parse.nonzero_result(16n, result, TC.ParentIdField{})
    flags_result(trace_id, parent_id, TC.Parse.digits(2n, Digits.Digits.to_string(2n, flags), 53n))

# What Parse.trace computes when the trace ID's digits are followed by "-",
# the parent ID's text, "-" and the flags' text, as a function of `result`,
# which stands for Digits.NonZero.new of those digits. trace_valid rewrites
# `result` into Some{trace_id}.
def trace_valid_result(parent_id: Digits.NonZero<16n>, flags: Digits.Digits(2n),
  result: Maybe<&2, Digits.NonZero<32n>>) -> Result<&2, &2, TC.Error, TC.TraceParentV00>:
  do Result<&2, &2, TC.Error, TC.TraceParentV00>:
    trace_id : Digits.NonZero<32n> <- TC.Parse.nonzero_result(32n, result, TC.TraceIdField{})
    parent_result(trace_id, TC.Parse.digits(16n,
      Digits.NonZero.to_string(16n, parent_id) ++ "-" ++ Digits.Digits.to_string(2n, flags), 36n))

# When only the text of the flag digits remains, reading it from offset 53
# and finishing the parse gives the value with the given IDs and exactly
# those flags. parent_valid uses it.
law flags_roundtrip:
  for trace_id: Digits.NonZero<32n>
  for parent_id: Digits.NonZero<16n>
  for flags: Digits.Digits(2n)
  {flags_result(trace_id, parent_id, TC.Parse.digits(2n, Digits.Digits.to_string(2n, flags), 53n)) ==
    Done{TC.TraceParentV00{trace_id, parent_id, flags}} : Result<&2, &2, TC.Error, TC.TraceParentV00>}

# Splits the flags so that digits_roundtrip's text ++ "" computes to their text.
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

# When the parent ID's digits have been read and "-" and the flags' text
# remain, Parse.parent gives back the value with `parent_id` itself: its
# nonzero check returns the stored value, evidence included
# (DigitsProof.new_recovery). parent_roundtrip uses it.
law parent_valid:
  for trace_id: Digits.NonZero<32n>
  for +parent_id: Digits.NonZero<16n>
  for flags: Digits.Digits(2n)
  {TC.Parse.parent(trace_id, TC.Parsed{Digits.NonZero.digits(16n, parent_id), "-" ++ Digits.Digits.to_string(2n, flags)}) ==
    Done{TC.TraceParentV00{trace_id, parent_id, flags}} : Result<&2, &2, TC.Error, TC.TraceParentV00>}

def parent_valid(trace_id, parent_id, flags):
  %Equal.sym(Maybe<&2, Digits.NonZero<16n>>,
    Digits.NonZero.new(16n, Digits.NonZero.digits(16n, parent_id)), Some{parent_id},
    DigitsProof.new_recovery(16n, parent_id)) : {
      parent_valid_result(trace_id, flags, _) == Done{TC.TraceParentV00{trace_id, parent_id, flags}} :
      Result<&2, &2, TC.Error, TC.TraceParentV00>}
  flags_roundtrip(trace_id, parent_id, flags)

# Reading the parent ID's text followed by "-" and the flags' text, from
# offset 36, and finishing the parse gives the value with these fields.
# trace_valid uses it.
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

# When the trace ID's digits have been read and "-", the parent ID's text,
# "-" and the flags' text remain, Parse.trace gives back the value with
# `trace_id` itself, evidence included. roundtrip uses it.
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
    DigitsProof.new_recovery(32n, trace_id)) : {
      trace_valid_result(parent_id, flags, _) == Done{TC.TraceParentV00{trace_id, parent_id, flags}} :
      Result<&2, &2, TC.Error, TC.TraceParentV00>}
  parent_roundtrip(trace_id, parent_id, flags)

# Parsing the text of any strict v00 value gives back exactly that value. It
# is law roundtrip of LAWS.bend, which PROOF.bend's Laws.roundtrip proves by
# calling it.
law roundtrip:
  for context: TC.TraceParentV00
  {TC.TraceParentV00.parse(TC.TraceParentV00.format(context)) == Done{context} : Result<&2, &2, TC.Error, TC.TraceParentV00>}

# The prefix "00-" is read by computation; the trace ID is read by rewriting.
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
