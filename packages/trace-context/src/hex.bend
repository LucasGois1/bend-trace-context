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

# Internal entries for the finite decoder table.
type Entry is Data:
  Entry{char: Char, digit: Digit}

def Digit.from_char.lookup(table: List<&2, Entry>, +char: Char) -> Maybe<&2, Digit>:
  match table:
    case Nil{}:
      None{}
    case Con{Entry{candidate, digit}, tail}:
      Bool.pick(Maybe<&2, Digit>, Char.is_eq(char, candidate),
        Some{digit}, Digit.from_char.lookup(tail, char))

# Uppercase and every non-hexadecimal character are rejected.
def Digit.from_char(char: Char) -> Maybe<&2, Digit>:
  Digit.from_char.lookup([
    Entry{'0', H0{}}, Entry{'1', H1{}}, Entry{'2', H2{}}, Entry{'3', H3{}},
    Entry{'4', H4{}}, Entry{'5', H5{}}, Entry{'6', H6{}}, Entry{'7', H7{}},
    Entry{'8', H8{}}, Entry{'9', H9{}}, Entry{'a', Ha{}}, Entry{'b', Hb{}},
    Entry{'c', Hc{}}, Entry{'d', Hd{}}, Entry{'e', He{}}, Entry{'f', Hf{}}
  ], char)
