# Proofs: general lemmas on List
# ==============================
#
# General lemmas on Base's List.append and List.length, for lists of any
# element type `A`: appending is associative, Nil{} is a right identity of
# appending, and appending one element adds one to the length. The
# tracestate proofs need them because the reading machine and
# TC.Entries.unique grow their lists at the end, one entry at a time
# (List.append(&2, TC.StateEntry, seen, Con{entry, Nil{}})). Used by
# proofs/distinct.bend, first.bend, merge.bend and normal.bend.
#
# List.append and List.length recurse on their first list, so each lemma is
# proved by induction on that list. In the Con case the induction hypothesis
# rewrites the part computed from the tail, under Con{head, _} (or 1n+_ for
# a length), and both sides then compute to the same term. The element type
# is erased (`-A`): the proofs never look at the elements.

import Base

# List.append is associative: `a` followed by `b`, then `c`, is `a` followed
# by `b` and `c`. Used by distinct.bend, first.bend, merge.bend and
# normal.bend to regroup a list that grew by one entry at its end.
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
