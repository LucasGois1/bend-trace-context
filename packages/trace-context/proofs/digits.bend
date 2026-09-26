# Proofs: digit sequences
# =======================
#
# Digits(n) (src/digits.bend) is a sequence of exactly n hexadecimal digits,
# and NonZero<n> pairs such a sequence with a proof that it is not all zero.
# This module proves that n digits always format as n characters, and that
# NonZero.new accepts the digits of a nonzero sequence and keeps its proof.
# Laws.formatted_length (PROOF.bend) adds up the field lengths with
# encoded_length and nonzero_encoded_length. The constructor lemmas serve the
# parser proofs, since the parser checks the digits it read with
# NonZero.new: new_valid in proofs/ids.bend (laws trace_id_accepts and
# span_id_roundtrip), new_recovery in proofs/context.bend (law roundtrip).
#
# Strategy: encoded_length is an induction on n, and nonzero_encoded_length
# opens the NonZero value to apply it. new_valid rewrites the zero check and
# its stored proof with `%q@`, which leaves an equation that holds by the
# definition of NonZero.new; new_recovery opens the value and applies
# new_valid.

import Base
import ../src/digits.bend as Digits

# A sequence of n digits formats as exactly n characters, for every n and
# every sequence. Induction on n: each digit adds one character.
# Laws.formatted_length (PROOF.bend) uses it for the two flag digits.
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

# The same for a nonzero sequence: an ID of n digits formats as n
# characters. Laws.formatted_length (PROOF.bend) uses it for the trace ID
# (32 digits) and the parent ID (16 digits).
law nonzero_encoded_length:
  for n: Nat
  for value: Digits.NonZero<n>
  {String.length(Digits.NonZero.to_string(n, value)) == n : Nat}

def nonzero_encoded_length(n, value):
  match value:
    case Digits.NonZero{digits, evidence}:
      encoded_length(n, digits)

# When the digits are not all zero, NonZero.new accepts them, and the value
# it returns carries exactly the given proof `evidence`: the equation
# compares whole values, stored proof included. Used by new_recovery below
# and by IdsProof.id_roundtrip (proofs/ids.bend).
law new_valid:
  for n: Nat
  for digits: Digits.Digits(n)
  for evidence: {Digits.Digits.is_zero(n, digits) == False{} : Bool}
  {Digits.NonZero.new(n, digits) == Some{Digits.NonZero{digits, evidence}} : Maybe<&2, Digits.NonZero<n>>}

# Rewrites with `%q@`: the goal becomes NonZero.new(n, digits) == its body.
def new_valid(n, digits, evidence):
  %q@evidence : {
    Digits.NonZero.new(n, digits) == Digits.NonZero.new.checked(n, digits, _, q) : Maybe<&2, Digits.NonZero<n>>}
  {==}

# Validating the digits of a nonzero sequence again gives back the same
# value, its proof included. ContextProof.trace_valid and
# ContextProof.parent_valid (proofs/context.bend) use it: when the parser
# checks the digits of a formatted ID, it rebuilds the original value.
law new_recovery:
  for n: Nat
  for value: Digits.NonZero<n>
  {Digits.NonZero.new(n, Digits.NonZero.digits(n, value)) == Some{value} : Maybe<&2, Digits.NonZero<n>>}

def new_recovery(n, value):
  match value:
    case Digits.NonZero{digits, evidence}:
      new_valid(n, digits, evidence)
