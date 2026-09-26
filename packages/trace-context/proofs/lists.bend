# Proofs: general lemmas on List
# ==============================
#
# General lemmas on Base's List.append, List.length and List.take, for lists
# of any element type `A`: appending is associative, Nil{} is a right
# identity of appending, appending one element adds one to the length, and
# List.take keeps at most `n` elements, all of them when there are no more.
# The tracestate proofs need them because the reading machine and
# TC.Entries.unique grow their lists at the end, one entry at a time
# (List.append(&2, TC.StateEntry, seen, Con{entry, Nil{}})), and because an
# update keeps at most 31 other entries. Used by proofs/distinct.bend,
# first.bend, merge.bend, normal.bend, update.bend and emit.bend.
#
# List.append, List.length and List.take recurse on their first list, so each
# lemma is proved by induction on that list (and on `n` for List.take). In the
# Con case the induction hypothesis rewrites the part computed from the tail,
# under Con{head, _} (or 1n+_ for a length), and both sides then compute to the
# same term. The element type is erased (`-A`): the proofs never look at the
# elements.

import Base
import ./bools.bend as BoolsProof

# List.append is associative: `a` followed by `b`, then `c`, is `a` followed
# by `b` and `c`. Used by distinct.bend, first.bend, merge.bend, normal.bend
# and emit.bend to regroup a list that grew by one entry at its end.
law append_assoc:
  for -A: Data
  for a: List<&2, A>
  for b: List<&2, A>
  for c: List<&2, A>
  {List.append(&2, A, List.append(&2, A, a, b), c) == List.append(&2, A, a, List.append(&2, A, b, c)) : List<&2, A>}

def append_assoc(A, a, b, c):
  match a:
    case Nil{}:
      {==}
    case Con{head, tail}:
      %append_assoc(A, tail, b, c) : {Con{head, List.append(&2, A, List.append(&2, A, tail, b), c)} == Con{head, _} :
        List<&2, A>}
      {==}

# Nil{} is a right identity of List.append: `list` followed by Nil{} is
# `list`; the left identity holds by computation. Used by distinct.bend,
# first.bend and merge.bend to drop an empty list at the end, such as the
# Nil{} that `missing` gives for a dropped duplicate.
law append_nil:
  for -A: Data
  for list: List<&2, A>
  {List.append(&2, A, list, Nil{}) == list : List<&2, A>}

def append_nil(A, list):
  match list:
    case Nil{}:
      {==}
    case Con{head, tail}:
      %append_nil(A, tail) : {Con{head, List.append(&2, A, tail, Nil{})} == Con{head, _} : List<&2, A>}
      {==}

# Appending one element adds one to the length: List.length of `list`
# followed by Con{last, Nil{}} is 1 + List.length of `list`. Used by
# first.bend (count_step) and merge.bend (valid_snoc) to count a state's
# entries after an entry with a new key is added at the end.
law length_snoc:
  for -A: Data
  for list: List<&2, A>
  for -last: A
  {List.length(&2, A, List.append(&2, A, list, Con{last, Nil{}})) == 1n+List.length(&2, A, list) : Nat}

def length_snoc(A, list, last):
  match list:
    case Nil{}:
      {==}
    case Con{head, tail}:
      %length_snoc(A, tail, last) : {1n+List.length(&2, A, List.append(&2, A, tail, Con{last, Nil{}})) == 1n+_ : Nat}
      {==}

# List.take of a list no longer than `n` is the whole list. Induction on the
# list and `n`; a nonempty list with n = 0 contradicts `fits`.
# proofs/update.bend uses it for update_keeps_all.
law take_all:
  for -A: Data
  for list: List<&2, A>
  for +n: Nat
  for fits: {Nat.is_le(List.length(&2, A, list), n) == True{} : Bool}
  {List.take(&2, A, list, n) == list : List<&2, A>}

def take_all(A, list, n, fits):
  match list n:
    case Nil{} _:
      {==}
    case Con{item, rest} 0n:
      BoolsProof.absurd({Nil{} == Con{item, rest} : List<&2, A>}, fits)
    case Con{+item, +rest} 1n+m:
      %Equal.sym(List<&2, A>, List.take(&2, A, rest, m), rest, take_all(A, rest, m, fits)) :
        {Con{item, _} == Con{item, rest} : List<&2, A>}
      {==}

# List.take keeps at most `n` entries. Induction on the list and `n`.
# proofs/update.bend uses it for the bound of 32 entries after a set.
law take_length:
  for -A: Data
  for list: List<&2, A>
  for n: Nat
  {Nat.is_le(List.length(&2, A, List.take(&2, A, list, n)), n) == True{} : Bool}

def take_length(A, list, n):
  match list n:
    case Nil{} 0n:
      {==}
    case Nil{} 1n+m:
      {==}
    case Con{item, rest} 0n:
      {==}
    case Con{item, rest} 1n+m:
      take_length(A, rest, m)
