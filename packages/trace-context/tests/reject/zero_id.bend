# Expected compile-time rejection: no proof that an all-zero ID is nonzero.
import Base
import ../../src/digits.bend as Digits
import ../../src/hex.bend as Hex

def invalid() -> Digits.NonZero<2n>:
  Digits.NonZero{
    Digits.DCon{Hex.H0{}, Digits.DCon{Hex.H0{}, Digits.DNil{}}},
    {==}
  }
