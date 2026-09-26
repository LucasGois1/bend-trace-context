# Hexadecimal digits
# ==================
#
# The sixteen lowercase hexadecimal digits as a closed type, with their
# characters, values and bits. The codec reads identifiers and flags into this
# type, so anything other than a lowercase hexadecimal digit (W3C 3.2.2,
# HEXDIGLC) cannot appear in a parsed value. This module is internal: callers
# handle identifiers as text through trace_context.bend. proofs/hex.bend proves
# that decoding inverts encoding: every digit's character decodes back to it,
# and an accepted character is exactly the encoding of the digit returned.

import Base

# A hexadecimal digit has exactly these sixteen values, H0 to Hf, in value
# order. Encoding is lowercase.
type Digit is Data:
  H0{}
  H1{}
  H2{}
  H3{}
  H4{}
  H5{}
  H6{}
  H7{}
  H8{}
  H9{}
  Ha{}
  Hb{}
  Hc{}
  Hd{}
  He{}
  Hf{}

# The lowercase character of a digit: '0' to '9', then 'a' to 'f'.
def Digit.to_char(digit: Digit) -> Char:
  match digit:
    case H0{}:
      '0'
    case H1{}:
      '1'
    case H2{}:
      '2'
    case H3{}:
      '3'
    case H4{}:
      '4'
    case H5{}:
      '5'
    case H6{}:
      '6'
    case H7{}:
      '7'
    case H8{}:
      '8'
    case H9{}:
      '9'
    case Ha{}:
      'a'
    case Hb{}:
      'b'
    case Hc{}:
      'c'
    case Hd{}:
      'd'
    case He{}:
      'e'
    case Hf{}:
      'f'

# The value of a digit, 0 to 15.
def Digit.to_u32(digit: Digit) -> U32:
  match digit:
    case H0{}:
      0
    case H1{}:
      1
    case H2{}:
      2
    case H3{}:
      3
    case H4{}:
      4
    case H5{}:
      5
    case H6{}:
      6
    case H7{}:
      7
    case H8{}:
      8
    case H9{}:
      9
    case Ha{}:
      10
    case Hb{}:
      11
    case Hc{}:
      12
    case Hd{}:
      13
    case He{}:
      14
    case Hf{}:
      15

# Whether the digit is 0. An identifier is all zero when every digit is.
def Digit.is_zero(digit: Digit) -> Bool:
  match digit:
    case H0{}:
      True{}
    case H1{}:
      False{}
    case H2{}:
      False{}
    case H3{}:
      False{}
    case H4{}:
      False{}
    case H5{}:
      False{}
    case H6{}:
      False{}
    case H7{}:
      False{}
    case H8{}:
      False{}
    case H9{}:
      False{}
    case Ha{}:
      False{}
    case Hb{}:
      False{}
    case Hc{}:
      False{}
    case Hd{}:
      False{}
    case He{}:
      False{}
    case Hf{}:
      False{}

# Whether bit 0 (value 1) of the digit is set. In the last digit of the flags
# this is the sampled flag (W3C 3.2.2.5.1).
def Digit.is_odd(digit: Digit) -> Bool:
  match digit:
    case H0{}:
      False{}
    case H1{}:
      True{}
    case H2{}:
      False{}
    case H3{}:
      True{}
    case H4{}:
      False{}
    case H5{}:
      True{}
    case H6{}:
      False{}
    case H7{}:
      True{}
    case H8{}:
      False{}
    case H9{}:
      True{}
    case Ha{}:
      False{}
    case Hb{}:
      True{}
    case Hc{}:
      False{}
    case Hd{}:
      True{}
    case He{}:
      False{}
    case Hf{}:
      True{}

# Whether bit 1 (value 2) of the digit is set. In the last digit of the flags
# this is the random-trace-id flag (W3C 3.2.2.5.2).
def Digit.has_bit1(digit: Digit) -> Bool:
  match digit:
    case H0{}:
      False{}
    case H1{}:
      False{}
    case H2{}:
      True{}
    case H3{}:
      True{}
    case H4{}:
      False{}
    case H5{}:
      False{}
    case H6{}:
      True{}
    case H7{}:
      True{}
    case H8{}:
      False{}
    case H9{}:
      False{}
    case Ha{}:
      True{}
    case Hb{}:
      True{}
    case Hc{}:
      False{}
    case Hd{}:
      False{}
    case He{}:
      True{}
    case Hf{}:
      True{}

# Whether bit 2 (value 4) of the digit is set.
def Digit.has_bit2(digit: Digit) -> Bool:
  match digit:
    case H0{}:
      False{}
    case H1{}:
      False{}
    case H2{}:
      False{}
    case H3{}:
      False{}
    case H4{}:
      True{}
    case H5{}:
      True{}
    case H6{}:
      True{}
    case H7{}:
      True{}
    case H8{}:
      False{}
    case H9{}:
      False{}
    case Ha{}:
      False{}
    case Hb{}:
      False{}
    case Hc{}:
      True{}
    case Hd{}:
      True{}
    case He{}:
      True{}
    case Hf{}:
      True{}

# Whether bit 3 (value 8) of the digit is set.
def Digit.has_bit3(digit: Digit) -> Bool:
  match digit:
    case H0{}:
      False{}
    case H1{}:
      False{}
    case H2{}:
      False{}
    case H3{}:
      False{}
    case H4{}:
      False{}
    case H5{}:
      False{}
    case H6{}:
      False{}
    case H7{}:
      False{}
    case H8{}:
      True{}
    case H9{}:
      True{}
    case Ha{}:
      True{}
    case Hb{}:
      True{}
    case Hc{}:
      True{}
    case Hd{}:
      True{}
    case He{}:
      True{}
    case Hf{}:
      True{}

# The digit whose value is bit0 + 2 * bit1 + 4 * bit2 + 8 * bit3.
def Digit.from_bits(bit0: Bool, bit1: Bool, bit2: Bool, bit3: Bool) -> Digit:
  match bit0 bit1 bit2 bit3:
    case False{} False{} False{} False{}:
      H0{}
    case True{} False{} False{} False{}:
      H1{}
    case False{} True{} False{} False{}:
      H2{}
    case True{} True{} False{} False{}:
      H3{}
    case False{} False{} True{} False{}:
      H4{}
    case True{} False{} True{} False{}:
      H5{}
    case False{} True{} True{} False{}:
      H6{}
    case True{} True{} True{} False{}:
      H7{}
    case False{} False{} False{} True{}:
      H8{}
    case True{} False{} False{} True{}:
      H9{}
    case False{} True{} False{} True{}:
      Ha{}
    case True{} True{} False{} True{}:
      Hb{}
    case False{} False{} True{} True{}:
      Hc{}
    case True{} False{} True{} True{}:
      Hd{}
    case False{} True{} True{} True{}:
      He{}
    case True{} True{} True{} True{}:
      Hf{}

# Every digit, in encoding order.
def Digit.all() -> List<&2, Digit>:
  [H0{}, H1{}, H2{}, H3{}, H4{}, H5{}, H6{}, H7{},
   H8{}, H9{}, Ha{}, Hb{}, Hc{}, Hd{}, He{}, Hf{}]

# Search the encoder's own alphabet, so an accepted character is exactly the
# encoding of the digit returned for it.
def Digit.from_char.find(digits: List<&2, Digit>, +char: Char) -> Maybe<&2, Digit>:
  match digits:
    case Nil{}:
      None{}
    case Con{+digit, tail}:
      Bool.pick(Maybe<&2, Digit>, Char.is_eq(char, Digit.to_char(digit)),
        Some{digit}, Digit.from_char.find(tail, char))

# The digit a character encodes. Uppercase and every non-hexadecimal character
# are rejected with None.
def Digit.from_char(char: Char) -> Maybe<&2, Digit>:
  Digit.from_char.find(Digit.all(), char)
