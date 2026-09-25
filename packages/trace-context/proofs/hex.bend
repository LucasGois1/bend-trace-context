import Base
import ../src/hex.bend as Hex
import ./chars.bend as CharsProof

# Quantified over the complete datatype, not a set of numeric fixtures.
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

# A decoded digit is exactly the digit whose encoding was read.
def DecodedView(char: Char, decoded: Maybe<&2, Hex.Digit>) -> Type:
  match decoded:
    case None{}:
      Unit
    case Some{digit}:
      {Hex.Digit.to_char(digit) == char : Char}

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

# Quantified over every character, including those the decoder rejects.
law decoded_view:
  for char: Char
  DecodedView(char, Hex.Digit.from_char(char))

def decoded_view(char):
  find_view(Hex.Digit.all(), char)
