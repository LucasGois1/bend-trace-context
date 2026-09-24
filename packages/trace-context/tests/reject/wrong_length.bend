# Expected compile-time rejection: one digit cannot inhabit Digits(2n).
import Base
import ../../src/digits.bend as Digits
import ../../src/hex.bend as Hex

def invalid() -> Digits.Digits(2n):
  Digits.DCon{Hex.H1{}, Digits.DNil{}}
