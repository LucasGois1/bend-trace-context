import Base
import ../src/digits.bend as Digits

# Every indexed sequence serializes to exactly its indexed length.
law encoded_length:
  for n: Nat
  for digits: Digits.Digits(n)
  {String.length(Digits.Digits.to_string(n, digits)) == n : Nat}

def encoded_length(n, digits):
  match n:
    case 0n:
      {==}
    case 1n+p:
      match digits:
        case Digits.DCon{head, tail}:
          %encoded_length(p, tail) : {1n+String.length(Digits.Digits.to_string(p, tail)) == 1n+_ : Nat}
          {==}

law nonzero_encoded_length:
  for n: Nat
  for value: Digits.NonZero<n>
  {String.length(Digits.NonZero.to_string(n, value)) == n : Nat}

def nonzero_encoded_length(n, value):
  match value:
    case Digits.NonZero{digits, evidence}:
      encoded_length(n, digits)

# The equality stored in NonZero is available to downstream proofs.
law nonzero_evidence:
  for n: Nat
  for value: Digits.NonZero<n>
  {Digits.Digits.is_zero(n, Digits.NonZero.digits(n, value)) == False{} : Bool}

def nonzero_evidence(n, value):
  match value:
    case Digits.NonZero{digits, evidence}:
      evidence

law new_valid:
  for n: Nat
  for digits: Digits.Digits(n)
  for evidence: {Digits.Digits.is_zero(n, digits) == False{} : Bool}
  {Digits.NonZero.new(n, digits) == Some{Digits.NonZero{digits, evidence}} : Maybe<&2, Digits.NonZero<n>>}

def new_valid(n, digits, evidence):
  %q@evidence : {
    Digits.NonZero.new(n, digits) == Digits.NonZero.new.checked(n, digits, _, q) : Maybe<&2, Digits.NonZero<n>>}
  {==}

law new_recovery:
  for n: Nat
  for value: Digits.NonZero<n>
  {Digits.NonZero.new(n, Digits.NonZero.digits(n, value)) == Some{value} : Maybe<&2, Digits.NonZero<n>>}

def new_recovery(n, value):
  match value:
    case Digits.NonZero{digits, evidence}:
      new_valid(n, digits, evidence)
