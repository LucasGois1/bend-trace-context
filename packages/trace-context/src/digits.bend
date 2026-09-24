import Base
import ./hex.bend as Hex

# The length is part of the type. A Digits(32n) cannot contain 31 or 33 digits.
# This is the same type-family pattern that Base uses for Word(n).
type Digits.Nil is Data:
  DNil{}

type Digits.Con<-p: Nat> is Data:
  DCon{head: Hex.Digit, tail: Digits(p)}

def Digits(n: Nat) -> Data:
  match n:
    case 0n:
      Digits.Nil
    case 1n+p:
      Digits.Con<p>

def Digits.to_string(n: Nat, digits: Digits(n)) -> String:
  match n:
    case 0n:
      ""
    case 1n+p:
      match digits:
        case DCon{head, tail}:
          SCon{Hex.Digit.to_char(head), Digits.to_string(p, tail)}

def Digits.is_zero(n: Nat, digits: Digits(n)) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+p:
      match digits:
        case DCon{head, tail}:
          Bool.and(Hex.Digit.is_zero(head), Digits.is_zero(p, tail))

# The equality is checked statically; compiled evidence is a null placeholder.
# Keeping its binder usable lets later proofs recover and reuse this guarantee.
# Even direct construction must supply a proof that these digits are not zero.
type NonZero<-n: Nat> is Data:
  NonZero{digits: Digits(n), evidence: {Digits.is_zero(n, digits) == False{} : Bool}}

# Carry the equation into the branch: matching status refines its right side.
def NonZero.new.checked(-n: Nat, digits: Digits(n), status: Bool,
  evidence: {Digits.is_zero(n, digits) == status : Bool}) -> Maybe<&2, NonZero<n>>:
  match status:
    case True{}:
      None{}
    case False{}:
      Some{NonZero{digits, evidence}}

def NonZero.new(+n: Nat, +digits: Digits(n)) -> Maybe<&2, NonZero<n>>:
  NonZero.new.checked(n, digits, Digits.is_zero(n, digits), {==})

def NonZero.digits(-n: Nat, value: NonZero<n>) -> Digits(n):
  match value:
    case NonZero{digits, evidence}:
      digits

def NonZero.to_string(n: Nat, value: NonZero<n>) -> String:
  Digits.to_string(n, NonZero.digits(n, value))
