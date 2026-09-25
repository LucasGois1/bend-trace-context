import Base

# A hexadecimal digit has exactly these sixteen values. Encoding is lowercase.
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

# Whether bit 1 (value 2) of the digit is set.
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

# The digit whose value is bit0 + 2 * bit1.
def Digit.from_low_bits(bit0: Bool, bit1: Bool) -> Digit:
  match bit0 bit1:
    case False{} False{}:
      H0{}
    case True{} False{}:
      H1{}
    case False{} True{}:
      H2{}
    case True{} True{}:
      H3{}

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

# Uppercase and every non-hexadecimal character are rejected.
def Digit.from_char(char: Char) -> Maybe<&2, Digit>:
  Digit.from_char.find(Digit.all(), char)
