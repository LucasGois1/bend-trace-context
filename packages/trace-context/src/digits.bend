# Digit sequences of a known length
# =================================
#
# Digits(n) is a sequence of exactly n hexadecimal digits: the length is part
# of the type, so a trace ID is a Digits(32n) and a flag byte a Digits(2n).
# NonZero<n> adds the proof that the digits are not all zero, which W3C 3.2.2.3
# and 3.2.2.4 require of trace and parent IDs. This module is internal to the
# package. proofs/digits.bend proves that n digits always format as n
# characters.

import Base
import ./hex.bend as Hex

# The length is part of the type. A Digits(32n) cannot contain 31 or 33 digits.
# This is the same type-family pattern that Base uses for Word(n).
#
# The empty sequence: the only value of Digits(0n).
type Digits.Nil is Data:
  DNil{}

# A first digit followed by a sequence of p digits: a value of Digits(1n+p).
type Digits.Con<-p: Nat> is Data:
  DCon{head: Hex.Digit, tail: Digits(p)}

# The type of sequences of exactly n digits, computed from n: Digits(0n) is
# Digits.Nil and Digits(1n+p) is Digits.Con<p>.
def Digits(n: Nat) -> Data:
  match n:
    case 0n:
      Digits.Nil
    case 1n+p:
      Digits.Con<p>

# The n lowercase characters of the digits, in order.
def Digits.to_string(n: Nat, digits: Digits(n)) -> String:
  match n:
    case 0n:
      ""
    case 1n+p:
      match digits:
        case DCon{head, tail}:
          SCon{Hex.Digit.to_char(head), Digits.to_string(p, tail)}

# Whether every digit is 0. The empty sequence counts as zero.
def Digits.is_zero(n: Nat, digits: Digits(n)) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+p:
      match digits:
        case DCon{head, tail}:
          Bool.and(Hex.Digit.is_zero(head), Digits.is_zero(p, tail))

# The eight digits of a word, most significant first: the first digit holds
# bits 31 to 28 and the last digit bits 3 to 0.
def Digits.of_u32(word: U32) -> Digits(8n):
  match word:
    case U32{WCon{b0, WCon{b1, WCon{b2, WCon{b3, WCon{b4, WCon{b5, WCon{b6, WCon{b7, WCon{b8, WCon{b9, WCon{b10, WCon{b11, WCon{b12, WCon{b13, WCon{b14, WCon{b15, WCon{b16, WCon{b17, WCon{b18, WCon{b19, WCon{b20, WCon{b21, WCon{b22, WCon{b23, WCon{b24, WCon{b25, WCon{b26, WCon{b27, WCon{b28, WCon{b29, WCon{b30, WCon{b31, WNil{}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}:
      DCon{Hex.Digit.from_bits(b28, b29, b30, b31), DCon{Hex.Digit.from_bits(b24, b25, b26, b27), DCon{Hex.Digit.from_bits(b20, b21, b22, b23), DCon{Hex.Digit.from_bits(b16, b17, b18, b19), DCon{Hex.Digit.from_bits(b12, b13, b14, b15), DCon{Hex.Digit.from_bits(b8, b9, b10, b11), DCon{Hex.Digit.from_bits(b4, b5, b6, b7), DCon{Hex.Digit.from_bits(b0, b1, b2, b3), DNil{}}}}}}}}}

# The word whose eight digits these are, most significant first.
def Digits.to_u32(digits: Digits(8n)) -> U32:
  match digits:
    case DCon{+d7, DCon{+d6, DCon{+d5, DCon{+d4, DCon{+d3, DCon{+d2, DCon{+d1, DCon{+d0, DNil{}}}}}}}}}:
      U32{WCon{Hex.Digit.is_odd(d0), WCon{Hex.Digit.has_bit1(d0), WCon{Hex.Digit.has_bit2(d0), WCon{Hex.Digit.has_bit3(d0), WCon{Hex.Digit.is_odd(d1), WCon{Hex.Digit.has_bit1(d1), WCon{Hex.Digit.has_bit2(d1), WCon{Hex.Digit.has_bit3(d1), WCon{Hex.Digit.is_odd(d2), WCon{Hex.Digit.has_bit1(d2), WCon{Hex.Digit.has_bit2(d2), WCon{Hex.Digit.has_bit3(d2), WCon{Hex.Digit.is_odd(d3), WCon{Hex.Digit.has_bit1(d3), WCon{Hex.Digit.has_bit2(d3), WCon{Hex.Digit.has_bit3(d3), WCon{Hex.Digit.is_odd(d4), WCon{Hex.Digit.has_bit1(d4), WCon{Hex.Digit.has_bit2(d4), WCon{Hex.Digit.has_bit3(d4), WCon{Hex.Digit.is_odd(d5), WCon{Hex.Digit.has_bit1(d5), WCon{Hex.Digit.has_bit2(d5), WCon{Hex.Digit.has_bit3(d5), WCon{Hex.Digit.is_odd(d6), WCon{Hex.Digit.has_bit1(d6), WCon{Hex.Digit.has_bit2(d6), WCon{Hex.Digit.has_bit3(d6), WCon{Hex.Digit.is_odd(d7), WCon{Hex.Digit.has_bit1(d7), WCon{Hex.Digit.has_bit2(d7), WCon{Hex.Digit.has_bit3(d7), WNil{}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}

# The digits of `left` followed by those of `right`: m + n digits. Identifiers
# are built from source words this way, eight digits per word.
def Digits.append(m: Nat, -n: Nat, left: Digits(m), right: Digits(n)) -> Digits(Nat.add(m, n)):
  match m:
    case 0n:
      match left:
        case DNil{}:
          right
    case 1n+p:
      match left:
        case DCon{head, tail}:
          DCon{head, Digits.append(p, n, tail, right)}

# n digits that are not all zero. `evidence` is the proof. The equality is
# checked statically; compiled evidence is a null placeholder. Keeping its
# binder usable lets later proofs recover and reuse this guarantee. Even direct
# construction must supply a proof that these digits are not zero.
type NonZero<-n: Nat> is Data:
  NonZero{digits: Digits(n), evidence: {Digits.is_zero(n, digits) == False{} : Bool}}

# Carry the equation into the branch: matching status refines its right side.
# The value is built only in the False case, where the equation is the proof.
def NonZero.new.checked(-n: Nat, digits: Digits(n), status: Bool,
  evidence: {Digits.is_zero(n, digits) == status : Bool}) -> Maybe<&2, NonZero<n>>:
  match status:
    case True{}:
      None{}
    case False{}:
      Some{NonZero{digits, evidence}}

# Attach the proof that the digits are not all zero, or None when they are.
def NonZero.new(+n: Nat, +digits: Digits(n)) -> Maybe<&2, NonZero<n>>:
  NonZero.new.checked(n, digits, Digits.is_zero(n, digits), {==})

# The digits, without their proof.
def NonZero.digits(-n: Nat, value: NonZero<n>) -> Digits(n):
  match value:
    case NonZero{digits, evidence}:
      digits

# The n lowercase characters of the digits.
def NonZero.to_string(n: Nat, value: NonZero<n>) -> String:
  Digits.to_string(n, NonZero.digits(n, value))
