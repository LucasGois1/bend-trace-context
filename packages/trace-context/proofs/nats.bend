# Proofs: Nat sums and comparisons
# ================================
#
# General lemmas on Base's Nat. le_succ says that the check a + 1 <= b gives
# the same Bool as a < b; proofs/merge.bend uses it for the law later_new_key
# of LAWS.bend, whose hypothesis `room` says that the state has fewer than 32
# entries, while TraceState.is_valid asks that the state with the new entry
# have at most 32. add_succ and add_zero move a successor or a zero out of a
# sum, and le_weaken and le_drop relax a bound; proofs/first.bend uses them
# to count the entries of two joined states (count_step, merge_rest).
# le_trans, le_refl, zero_le and ge_le compare numbers, add_assoc regroups a
# sum and pred takes a successor off; proofs/update.bend, order.bend and
# emit.bend use them to bound and measure tracestate updates and emission.
#
# Nat.add recurses on its first argument, and Nat.is_le and Nat.is_lt both
# read Nat.cmp, which removes one from each side until one of them is zero,
# so the proofs are inductions on the first argument or on both at once.

import Base
import ./bools.bend as BoolsProof

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

# Adding a successor on the right: a + (1 + b) is 1 + (a + b). Nat.add
# recurses on its first argument, so the proof is an induction on `a`, and
# `b` is erased because the proof never inspects it. FirstProof.count_step
# (proofs/first.bend) uses it to move the 1 that counts the entry being read
# out of the sum.
law add_succ:
  for a: Nat
  for -b: Nat
  {Nat.add(a, 1n+b) == 1n+Nat.add(a, b) : Nat}

def add_succ(a, b):
  match a:
    case 0n:
      {==}
    case 1n+less:
      %add_succ(less, b) : {1n+Nat.add(less, 1n+b) == 1n+_ : Nat}
      {==}

# Adding zero on the right: a + 0 is a, by induction on `a`.
# FirstProof.merge_rest (proofs/first.bend) uses it at the last entry of the
# second state, where count_step bounds the kept entries plus 0 entries left:
# the kept entries are then at most 32, as TraceState.is_valid requires.
law add_zero:
  for a: Nat
  {Nat.add(a, 0n) == a : Nat}

def add_zero(a):
  match a:
    case 0n:
      {==}
    case 1n+less:
      %add_zero(less) : {1n+Nat.add(less, 0n) == 1n+_ : Nat}
      {==}

# When a <= b, also a <= 1 + b. By induction on `a` and `b` together; b = 0
# with a > 0 contradicts `holds`. le_drop uses it.
law le_weaken:
  for a: Nat
  for b: Nat
  for holds: {Nat.is_le(a, b) == True{} : Bool}
  {Nat.is_le(a, 1n+b) == True{} : Bool}

def le_weaken(a, b, holds):
  match a:
    case 0n:
      {==}
    case 1n+less:
      match b:
        case 0n:
          BoolsProof.absurd({Nat.is_le(1n+less, 1n) == True{} : Bool}, holds)
        case 1n+more:
          le_weaken(less, more, holds)

# When 1 + a <= b, also a <= b. FirstProof.count_step (proofs/first.bend)
# uses it for a duplicate entry: the kept entries do not grow, and one fewer
# entry is left to count. proofs/order.bend uses it to bound kept entries.
law le_drop:
  for a: Nat
  for b: Nat
  for holds: {Nat.is_le(1n+a, b) == True{} : Bool}
  {Nat.is_le(a, b) == True{} : Bool}

def le_drop(a, b, holds):
  match b:
    case 0n:
      BoolsProof.absurd({Nat.is_le(a, 0n) == True{} : Bool}, holds)
    case 1n+more:
      le_weaken(a, more, holds)

# The check <= is transitive: when a <= b and b <= c, then a <= c. By
# induction on the three numbers together; a case where the first check has
# a successor on the left and zero on the right computes to
# {False{} == True{}}, which BoolsProof.absurd refutes. proofs/update.bend
# and proofs/emit.bend use it to bound the entries an update or a truncation
# keeps by the 32 of a state, and emit.bend to compare the budgets.
law le_trans:
  for a: Nat
  for b: Nat
  for c: Nat
  for ab: {Nat.is_le(a, b) == True{} : Bool}
  for bc: {Nat.is_le(b, c) == True{} : Bool}
  {Nat.is_le(a, c) == True{} : Bool}

def le_trans(a, b, c, ab, bc):
  match a b c:
    case 0n _ 0n:
      {==}
    case 0n _ 1n+cp:
      {==}
    case 1n+ap 0n _:
      BoolsProof.absurd({Nat.is_le(1n+ap, c) == True{} : Bool}, ab)
    case 1n+ap 1n+bp 0n:
      BoolsProof.absurd({Nat.is_le(1n+ap, 0n) == True{} : Bool}, bc)
    case 1n+ap 1n+bp 1n+cp:
      le_trans(ap, bp, cp, ab, bc)

# a >= b gives the same Bool as b <= a: both read Nat.cmp, which removes one
# from each side until one of them is zero. By induction on both numbers.
# proofs/emit.bend uses it to read the rule of Limits, input >= output, as a
# bound on the emitted value.
law ge_le:
  for a: Nat
  for b: Nat
  {Nat.is_ge(a, b) == Nat.is_le(b, a) : Bool}

def ge_le(a, b):
  match a b:
    case 0n 0n:
      {==}
    case 0n 1n+bp:
      {==}
    case 1n+ap 0n:
      {==}
    case 1n+ap 1n+bp:
      ge_le(ap, bp)

# Addition is associative: a + (b + c) is (a + b) + c. Nat.add recurses on
# its first argument, so the proof is an induction on `a`, and `b` and `c`
# are erased. proofs/emit.bend uses it to add up the octets of a text
# character by character.
law add_assoc:
  for a: Nat
  for -b: Nat
  for -c: Nat
  {Nat.add(a, Nat.add(b, c)) == Nat.add(Nat.add(a, b), c) : Nat}

def add_assoc(a, b, c):
  match a:
    case 0n:
      {==}
    case 1n+p:
      %add_assoc(p, b, c) : {1n+Nat.add(p, Nat.add(b, c)) == 1n+_ : Nat}
      {==}

# Every number is at most itself. By induction on `a`. proofs/emit.bend uses
# it to start truncation with one step per entry.
law le_refl:
  for a: Nat
  {Nat.is_le(a, a) == True{} : Bool}

def le_refl(a):
  match a:
    case 0n:
      {==}
    case 1n+p:
      le_refl(p)

# Zero is at most every number: Nat.cmp(0n, b) is EQ or LT, by cases on `b`.
# proofs/emit.bend uses it for the empty state, which fits every budget.
law zero_le:
  for b: Nat
  {Nat.is_le(0n, b) == True{} : Bool}

def zero_le(b):
  match b:
    case 0n:
      {==}
    case 1n+p:
      {==}

# The predecessor of a number, zero for zero. Applied to both sides of an
# equation between successors (Equal.cong), it takes the successor off both;
# proofs/emit.bend uses it so.
def pred(n: Nat) -> Nat:
  match n:
    case 0n:
      0n
    case 1n+p:
      p
