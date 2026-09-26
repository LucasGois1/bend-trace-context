# Proofs: general lemmas on Bool
# ==============================
#
# General lemmas on Base's Bool. true_ne_false shows that True and False
# differ, and absurd closes a case whose hypothesis computes to
# {False{} == True{}}. The others take apart a hypothesis saying a check
# returned True or False: each half of a true Bool.and, each half of a false
# Bool.or and the argument of a true Bool.not; or_assoc and or_false regroup
# a chain of Bool.or. The package's checks are chains of Bool.and
# (TraceState.is_valid, TC.Entries.unique, the key and value grammars, the
# rules of Limits) and its lookups are chains of Bool.or, so the proofs of
# the Limits and tracestate laws use these lemmas throughout:
# proofs/limits.bend, tracestate.bend, distinct.bend, merge.bend, normal.bend
# and first.bend. proofs/strings.bend, nats.bend and generation.bend use
# true_ne_false or absurd.
#
# Bool.and, Bool.or and Bool.not inspect only their first argument, so each
# law is proved by cases on `a`, and a second argument `b` is erased (`-b`).
# In each case the conclusion holds by computation ({==}), is the hypothesis
# itself once it computes, or follows from a hypothesis that computes to a
# clash. true_ne_false refutes such a clash by rewriting it through the
# motive BoolClash, which sends False to Empty and True to Unit.

import Base

# The motive that refutes {True{} == False{}}: Empty for False and Unit for
# True. Rewriting with the clash turns the goal Empty, which is
# BoolClash(False{}), into BoolClash(True{}), which is Unit. Used by
# true_ne_false.
def BoolClash(value: Bool) -> Type:
  match value:
    case False{}:
      Empty
    case True{}:
      Unit

# True and False are different: an equation {True{} == False{}} yields
# Empty, the type without values, so a case that assumes it cannot happen.
# Used here by absurd and or_right_false, and by StringsProof.distinct
# (proofs/strings.bend), GenerationProof.ended_stays (proofs/generation.bend)
# and StateProof.read_over (proofs/tracestate.bend).
law true_ne_false:
  for clash: {True{} == False{} : Bool}
  Empty

def true_ne_false(clash):
  %clash : BoolClash(_)
  Unit{}

# From the impossible equation {False{} == True{}}, anything follows: absurd
# proves any goal `A`, which the caller passes and which is erased. It closes
# a case whose hypothesis computes to that clash, such as
# {Nat.is_le(1n+n, 0n) == True{}}. Used by first.bend, merge.bend,
# normal.bend and tracestate.bend, and here by not_true and and_right.
def absurd(-A: Type, clash: {False{} == True{} : Bool}) -> A:
  Empty.absurd(A, true_ne_false(Equal.sym(Bool, False{}, True{}, clash)))

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
      Empty.absurd({b == False{} : Bool}, true_ne_false(both))

# Bool.or is associative. Bool.or inspects only its first argument, so the
# proof matches on `a` alone, and `b` and `c` are erased.
# FirstProof.has_key_append (proofs/first.bend) uses it to regroup the
# lookups in the two parts of a list.
law or_assoc:
  for a: Bool
  for -b: Bool
  for -c: Bool
  {Bool.or(a, Bool.or(b, c)) == Bool.or(Bool.or(a, b), c) : Bool}

def or_assoc(a, b, c):
  match a:
    case False{}:
      {==}
    case True{}:
      {==}

# False is a right identity of Bool.or: Bool.or(a, False{}) is `a`, by cases
# on `a`. FirstProof.machine_key (proofs/first.bend) uses it once the lookup
# in the entries kept from the second state is known to be False.
law or_false:
  for a: Bool
  {Bool.or(a, False{}) == a : Bool}

def or_false(a):
  match a:
    case False{}:
      {==}
    case True{}:
      {==}
