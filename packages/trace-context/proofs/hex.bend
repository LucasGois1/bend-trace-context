# Proofs: hexadecimal digits
# ==========================
#
# Hex.Digit (src/hex.bend) encodes each of its sixteen digits as a lowercase
# character, and decodes a character by searching the encoder's own
# alphabet. This module proves that encoding and decoding agree in both
# directions: every digit's character decodes back to that digit
# (roundtrip), and a decoded character is the encoding of the digit returned
# (decoded_view). PROOF.bend does not call it directly: proofs/parser.bend
# uses roundtrip to read back the digits that the formatter wrote (laws
# roundtrip, trace_id_accepts, span_id_roundtrip, hex_injective), and
# decoded_view to rebuild an accepted text from its digits (laws inverse,
# trace_id_parse, span_id_parse).
#
# Strategy: roundtrip is a case analysis on the sixteen digits, each case by
# computation. decoded_view is a view: DecodedView is Unit for a rejected
# character and the equation to_char(digit) == char for a decoded one.
# find_view proves it for a search through any list of digits, by induction
# on the list, with find_step as the step and CharsProof.char_view
# (proofs/chars.bend) for each comparison.

import Base
import ../src/hex.bend as Hex
import ./chars.bend as CharsProof

# Decoding inverts encoding: the character of every digit decodes back to
# that digit. Quantified over the complete datatype, not a set of fixtures.
# ParserProof.digit_roundtrip (proofs/parser.bend) uses it to read back the
# digits that the formatter wrote.
law roundtrip:
  for digit: Hex.Digit
  {Hex.Digit.from_char(Hex.Digit.to_char(digit)) == Some{digit} : Maybe<&2, Hex.Digit>}

def roundtrip(digit):
  match digit:
    case Hex.H0{}:
      {==}
    case Hex.H1{}:
      {==}
    case Hex.H2{}:
      {==}
    case Hex.H3{}:
      {==}
    case Hex.H4{}:
      {==}
    case Hex.H5{}:
      {==}
    case Hex.H6{}:
      {==}
    case Hex.H7{}:
      {==}
    case Hex.H8{}:
      {==}
    case Hex.H9{}:
      {==}
    case Hex.Ha{}:
      {==}
    case Hex.Hb{}:
      {==}
    case Hex.Hc{}:
      {==}
    case Hex.Hd{}:
      {==}
    case Hex.He{}:
      {==}
    case Hex.Hf{}:
      {==}

# The view of a decoding result: Unit for None (the character was rejected),
# and for Some{digit} the equation {Hex.Digit.to_char(digit) == char}: a
# decoded digit is exactly the digit whose encoding was read.
def DecodedView(char: Char, decoded: Maybe<&2, Hex.Digit>) -> Type:
  match decoded:
    case None{}:
      Unit
    case Some{digit}:
      {Hex.Digit.to_char(digit) == char : Char}

# One step of the search Hex.Digit.from_char.find: when `rest` is the view
# of the search in `tail`, the view holds for the search in the list that
# starts with `digit`. `same` compares char with digit's character, and
# `same_view` is its view. When `same` is False, Bool.pick continues in the
# tail and `rest` answers; when True, the result is Some{digit}, and
# `same_view` turned around is the view.
law find_step:
  for -char: Char
  for -digit: Hex.Digit
  for -tail: List<&2, Hex.Digit>
  for same: Bool
  for same_view: CharsProof.CharView(char, Hex.Digit.to_char(digit), same)
  for rest: DecodedView(char, Hex.Digit.from_char.find(tail, char))
  DecodedView(char, Bool.pick(Maybe<&2, Hex.Digit>, same, Some{digit},
    Hex.Digit.from_char.find(tail, char)))

def find_step(char, digit, tail, same, same_view, rest):
  match same:
    case False{}:
      rest
    case True{}:
      Equal.sym(Char, char, Hex.Digit.to_char(digit), same_view)

# Searching any list of digits satisfies the view: a digit found for char is
# one whose character is char. Induction on the list, with find_step as the
# step and CharsProof.char_view (proofs/chars.bend) for each comparison.
law find_view:
  for digits: List<&2, Hex.Digit>
  for +char: Char
  DecodedView(char, Hex.Digit.from_char.find(digits, char))

def find_view(digits, char):
  match digits:
    case Nil{}:
      Unit{}
    case Con{+digit, tail}:
      find_step(char, digit, tail, Char.is_eq(char, Hex.Digit.to_char(digit)),
        CharsProof.char_view(char, Hex.Digit.to_char(digit)), find_view(tail, char))

# Every decoding satisfies its view: when Hex.Digit.from_char accepts char,
# the digit returned encodes back to char. Quantified over every character,
# including those the decoder rejects, for which the view is Unit.
# Hex.Digit.from_char searches Hex.Digit.all(), so find_view applies.
# ParserProof.digit_view (proofs/parser.bend) builds on it.
law decoded_view:
  for char: Char
  DecodedView(char, Hex.Digit.from_char(char))

def decoded_view(char):
  find_view(Hex.Digit.all(), char)
