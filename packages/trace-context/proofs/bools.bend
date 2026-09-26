# Proofs: general lemmas on Bool
# ==============================
#
# General lemmas on Base's Bool that take apart a hypothesis saying a check
# returned True or False: each half of a true Bool.and, each half of a false
# Bool.or, the argument of a true Bool.not, and absurd, which closes a case
# whose hypothesis computes to {False{} == True{}}. The package's checks are
# chains of Bool.and (TraceState.is_valid, TC.Entries.unique, the key and
# value grammars, the rules of Limits) and its lookups are chains of Bool.or,
# so the proofs of the Limits and tracestate laws use these lemmas
# throughout: proofs/limits.bend, tracestate.bend, distinct.bend,
# merge.bend, normal.bend and first.bend.
#
# Bool.and, Bool.or and Bool.not inspect only their first argument, so each
# law is proved by cases on `a`, and a second argument `b` is erased (`-b`).
# In each case the conclusion holds by computation ({==}), is the hypothesis
# itself once it computes, or follows from a hypothesis that computes to a
# clash. absurd refutes such a clash with StringsProof.true_ne_false, which
# rewrites it through a motive that sends False to Empty and True to Unit.

import Base
import ./strings.bend as StringsProof

# From the impossible equation {False{} == True{}}, anything follows: absurd
# proves any goal `A`, which the caller passes and which is erased. It closes
# a case whose hypothesis computes to that clash, such as
# {Nat.is_le(1n+n, 0n) == True{}}. Used by first.bend, merge.bend,
# normal.bend and tracestate.bend, and here by not_true and and_right.
def absurd(-A: Type, clash: {False{} == True{} : Bool}) -> A:
  Empty.absurd(A, StringsProof.true_ne_false(Equal.sym(Bool, False{}, True{}, clash)))

# When Bool.not(a) is True, `a` is False. Used by distinct.bend, first.bend,
# merge.bend and normal.bend to read the first check of TC.Entries.unique,
# Bool.not(TC.Entries.has_key(seen, key)): the key of the next entry is not
# among the keys of the entries before it.
law not_true:
  for a: Bool
  for holds: {Bool.not(a) == True{} : Bool}
  {a == False{} : Bool}

def not_true(a, holds):
  match a:
    case False{}:
      {==}
    case True{}:
      absurd({True{} == False{} : Bool}, holds)

# When Bool.and(a, b) is True, `a` is True: the first check of a chain of
# Bool.and, such as TraceState.is_valid or TC.Entries.unique. Used by
# distinct.bend, first.bend, limits.bend, merge.bend, normal.bend and
# tracestate.bend.
law and_left:
  for a: Bool
  for -b: Bool
  for both: {Bool.and(a, b) == True{} : Bool}
  {a == True{} : Bool}

# In the False case the goal {False{} == True{}} is the hypothesis itself.
def and_left(a, b, both):
  match a:
    case False{}:
      both
    case True{}:
      {==}

# When Bool.and(a, b) is True, `b` is True: the rest of a chain of Bool.and
# after its first check. Used by the same modules as and_left: distinct.bend,
# first.bend, limits.bend, merge.bend, normal.bend and tracestate.bend.
law and_right:
  for a: Bool
  for -b: Bool
  for both: {Bool.and(a, b) == True{} : Bool}
  {b == True{} : Bool}

def and_right(a, b, both):
  match a:
    case False{}:
      absurd({b == True{} : Bool}, both)
    case True{}:
      both

# When Bool.or(a, b) is False, `a` is False. With or_right_false it splits a
# lookup that returned False, such as TC.Entries.has_key or key_among, into
# the comparison with the first entry's key and the lookup in the rest. Used
# by distinct.bend and first.bend.
law or_left_false:
  for a: Bool
  for -b: Bool
  for both: {Bool.or(a, b) == False{} : Bool}
  {a == False{} : Bool}

# In the True case the goal {True{} == False{}} is the hypothesis itself.
def or_left_false(a, b, both):
  match a:
    case False{}:
      {==}
    case True{}:
      both

# When Bool.or(a, b) is False, `b` is False: the lookup in the rest of the
# list returned False too (see or_left_false). Used by distinct.bend and
# first.bend.
law or_right_false:
  for a: Bool
  for -b: Bool
  for both: {Bool.or(a, b) == False{} : Bool}
  {b == False{} : Bool}

# The True case refutes {True{} == False{}} with true_ne_false directly.
def or_right_false(a, b, both):
  match a:
    case False{}:
      both
    case True{}:
      Empty.absurd({b == False{} : Bool}, StringsProof.true_ne_false(both))
