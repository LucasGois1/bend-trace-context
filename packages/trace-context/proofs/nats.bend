# Proofs: Nat comparisons
# =======================
#
# A general lemma on the comparisons of Base's Nat: the check a + 1 <= b
# gives the same Bool as a < b. proofs/merge.bend uses it for the law
# later_new_key of LAWS.bend, whose hypothesis `room` says that the state has
# fewer than 32 entries, while TraceState.is_valid asks that the state with
# the new entry have at most 32.
#
# Nat.is_le and Nat.is_lt both read Nat.cmp, which removes one from each
# side until one of them is zero, so the proof is an induction on both
# arguments at once.

import Base

# Nat.is_le(1n+a, b) equals Nat.is_lt(a, b) for every a and b: a + 1 <= b
# exactly when a < b. Used by merge.bend (valid_snoc) to turn `room`, a
# state's length below 32, into the bound on the length after one more entry.
law le_succ:
  for a: Nat
  for b: Nat
  {Nat.is_le(1n+a, b) == Nat.is_lt(a, b) : Bool}

# With a = 0n, `more` is matched only so that Nat.cmp(0n, more) computes.
def le_succ(a, b):
  match a:
    case 0n:
      match b:
        case 0n:
          {==}
        case 1n+more:
          match more:
            case 0n:
              {==}
            case 1n+rest:
              {==}
    case 1n+less:
      match b:
        case 0n:
          {==}
        case 1n+more:
          le_succ(less, more)
