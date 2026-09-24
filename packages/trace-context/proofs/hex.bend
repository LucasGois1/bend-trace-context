import Base
import ../src/hex.bend as Hex

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
