# Proofs: distinct keys and lookups
# =================================
#
# The package checks distinct keys backward: Entries.unique compares each
# entry's key with the entries before it. LAWS.bend states the property
# forward: keys_distinct says that no entry's key appears after it. This
# module proves that the check implies keys_distinct, which gives the law
# state_valid, and it proves the lookup laws get_entry and get_absent:
# PROOF.bend calls its lemmas of those three names. It also proves
# has_key_among, which equates the package's Entries.has_key with LAWS.bend's
# key_among: PROOF.bend uses it for later_duplicate and later_new_key, and
# proofs/first.bend for first_wins.
#
# The main lemmas are inductions on a list of entries. The uniqueness proofs
# generalize the `seen` list of Entries.unique: seen_key and fresh follow one
# seen entry while the later entries are checked against it, and distinct
# applies fresh at each step. The package compares an entry's key with the
# key sought, and key_among compares them the other way around, so the
# lookup lemmas turn comparisons around with StringsProof.eq_symmetric. For
# lookups, unique_split shows that no entry before a given one has its key,
# and get_first and get_missing walk Entries.get past such entries.

import Base
import ../LAWS.bend as Laws
import ../trace_context.bend as TC
import ./strings.bend as StringsProof
import ./bools.bend as BoolsProof
import ./lists.bend as ListsProof
# When no entry of a list has the key `key`, and `entry` is one of its
# entries (the list is `before`, then `entry`, then `after`), the key of
# `entry` differs from `key`. In fresh, the list is the `seen` list of
# Entries.unique and `key` is a later entry's key: an entry already seen has
# a key other than every later key checked. Induction on `before`.
law seen_key:
  for before: List<&2, TC.StateEntry>
  for +entry: TC.StateEntry
  for after: List<&2, TC.StateEntry>
  for +key: String
  for absent: {TC.Entries.has_key(List.append(&2, TC.StateEntry, before, Con{entry, after}), key) == False{} : Bool}
  {String.eq(TC.StateEntry.key_text(entry), key) == False{} : Bool}

def seen_key(before, entry, after, key, absent):
  match before:
    case Nil{}:
      BoolsProof.or_left_false(String.eq(TC.StateEntry.key_text(entry), key), TC.Entries.has_key(after, key), absent)
    case Con{first, rest}:
      seen_key(rest, entry, after, key,
        BoolsProof.or_right_false(String.eq(TC.StateEntry.key_text(first), key),
          TC.Entries.has_key(List.append(&2, TC.StateEntry, rest, Con{entry, after}), key), absent))

# A key already seen appears in no later entry: when Entries.unique accepts
# `later` after a seen list holding `entry`, Laws.key_among finds the key of
# `entry` in no entry of `later`. Induction on `later`: each entry checked
# joins the seen list at its end, so `after` grows while `before` and
# `entry` stay in place (ListsProof.append_assoc). distinct uses it.
law fresh:
  for later: List<&2, TC.StateEntry>
  for +before: List<&2, TC.StateEntry>
  for +entry: TC.StateEntry
  for +after: List<&2, TC.StateEntry>
  for +unique: {TC.Entries.unique(later, List.append(&2, TC.StateEntry, before, Con{entry, after})) == True{} : Bool}
  {Laws.key_among(TC.StateEntry.key_text(entry), later) == False{} : Bool}

def fresh(later, before, entry, after, unique):
  match later:
    case Nil{}:
      {==}
    case Con{+next, rest}:
      +seen = {List.append(&2, TC.StateEntry, before, Con{entry, after}) : List<&2, TC.StateEntry>}
      +absent = BoolsProof.not_true(TC.Entries.has_key(seen, TC.StateEntry.key_text(next)),
        BoolsProof.and_left(Bool.not(TC.Entries.has_key(seen, TC.StateEntry.key_text(next))),
          TC.Entries.unique(rest, List.append(&2, TC.StateEntry, seen, Con{next, Nil{}})), unique))
      +rest_unique = BoolsProof.and_right(Bool.not(TC.Entries.has_key(seen, TC.StateEntry.key_text(next))),
        TC.Entries.unique(rest, List.append(&2, TC.StateEntry, seen, Con{next, Nil{}})), unique)
      %Equal.sym(Bool, String.eq(TC.StateEntry.key_text(entry), TC.StateEntry.key_text(next)), False{},
        seen_key(before, entry, after, TC.StateEntry.key_text(next), absent)) :
        {Bool.or(_, Laws.key_among(TC.StateEntry.key_text(entry), rest)) == False{} : Bool}
      +later_seen = {List.append(&2, TC.StateEntry, before, Con{entry, List.append(&2, TC.StateEntry, after,
        Con{next, Nil{}})}) : List<&2, TC.StateEntry>}
      fresh(rest, before, entry, List.append(&2, TC.StateEntry, after, Con{next, Nil{}}),
        Equal.trans(Bool, TC.Entries.unique(rest, later_seen),
          TC.Entries.unique(rest, List.append(&2, TC.StateEntry, seen, Con{next, Nil{}})), True{},
          Equal.sym(Bool, TC.Entries.unique(rest, List.append(&2, TC.StateEntry, seen, Con{next, Nil{}})),
            TC.Entries.unique(rest, later_seen),
            Equal.cong(List<&2, TC.StateEntry>, Bool, list => TC.Entries.unique(rest, list),
              List.append(&2, TC.StateEntry, seen, Con{next, Nil{}}), later_seen,
              ListsProof.append_assoc(TC.StateEntry, before, Con{entry, after}, Con{next, Nil{}}))),
          rest_unique))

# The package's backward check implies the forward property of LAWS.bend:
# when Entries.unique accepts `entries` after any seen list,
# Laws.keys_distinct holds of `entries`. Induction on `entries`, the seen
# list growing by the entry just checked, whose key fresh excludes from the
# rest. state_valid applies it with the empty seen list, as
# TraceState.is_valid does.
law distinct:
  for entries: List<&2, TC.StateEntry>
  for +seen: List<&2, TC.StateEntry>
  for +unique: {TC.Entries.unique(entries, seen) == True{} : Bool}
  {Laws.keys_distinct(entries) == True{} : Bool}

def distinct(entries, seen, unique):
  match entries:
    case Nil{}:
      {==}
    case Con{+entry, +rest}:
      +rest_unique = BoolsProof.and_right(Bool.not(TC.Entries.has_key(seen, TC.StateEntry.key_text(entry))),
        TC.Entries.unique(rest, List.append(&2, TC.StateEntry, seen, Con{entry, Nil{}})), unique)
      %Equal.sym(Bool, Laws.key_among(TC.StateEntry.key_text(entry), rest), False{},
        fresh(rest, seen, entry, Nil{}, rest_unique)) :
        {Bool.and(Bool.not(_), Laws.keys_distinct(rest)) == True{} : Bool}
      distinct(rest, List.append(&2, TC.StateEntry, seen, Con{entry, Nil{}}), rest_unique)

# Every state has distinct keys, in the sense of Laws.keys_distinct, and at
# most 32 entries: the law state_valid, which PROOF.bend proves with it. The
# proof splits the state's evidence and applies distinct to its first half.
law state_valid:
  for state: TC.TraceState
  {Laws.keys_distinct(TC.TraceState.entries(state)) == True{} : Bool} &
  {Nat.is_le(List.length(&2, TC.StateEntry, TC.TraceState.entries(state)), 32n) == True{} : Bool}

def state_valid(state):
  match state:
    case TC.TraceState{+entries, +evidence}:
      (distinct(entries, Nil{}, BoolsProof.and_left(TC.Entries.unique(entries, Nil{}),
          Nat.is_le(List.length(&2, TC.StateEntry, entries), 32n), evidence)),
        BoolsProof.and_right(TC.Entries.unique(entries, Nil{}),
          Nat.is_le(List.length(&2, TC.StateEntry, entries), 32n), evidence))

# The package's Entries.has_key and LAWS.bend's key_among agree on every
# list and key. Induction on the entries, with StringsProof.eq_symmetric at
# each one. PROOF.bend uses it to restate the hypotheses of the laws
# later_duplicate and later_new_key for proofs/merge.bend, and
# proofs/first.bend uses it for first_wins.
law has_key_among:
  for entries: List<&2, TC.StateEntry>
  for +key: String
  {TC.Entries.has_key(entries, key) == Laws.key_among(key, entries) : Bool}

def has_key_among(entries, key):
  match entries:
    case Nil{}:
      {==}
    case Con{+entry, rest}:
      %Equal.sym(Bool, TC.Entries.has_key(rest, key), Laws.key_among(key, rest), has_key_among(rest, key)) :
        {Bool.or(String.eq(TC.StateEntry.key_text(entry), key), _) ==
          Bool.or(String.eq(key, TC.StateEntry.key_text(entry)), Laws.key_among(key, rest)) : Bool}
      %StringsProof.eq_symmetric(TC.StateEntry.key_text(entry), key) :
        {Bool.or(String.eq(TC.StateEntry.key_text(entry), key), Laws.key_among(key, rest)) ==
          Bool.or(_, Laws.key_among(key, rest)) : Bool}
      {==}

# Querying
# ========

# When Laws.key_among finds `key` in no entry, Entries.get finds nothing:
# each entry's key differs from `key` (StringsProof.eq_symmetric turns the
# comparison around), so the lookup passes it by. Induction on the entries.
# get_absent uses it.
law get_missing:
  for entries: List<&2, TC.StateEntry>
  for +key: String
  for +absent: {Laws.key_among(key, entries) == False{} : Bool}
  {TC.Entries.get(entries, key) == None{} : Maybe<&2, TC.StateValue>}

def get_missing(entries, key, absent):
  match entries:
    case Nil{}:
      {==}
    case Con{+entry, +rest}:
      %Equal.sym(Bool, String.eq(TC.StateEntry.key_text(entry), key), False{},
        Equal.trans(Bool, String.eq(TC.StateEntry.key_text(entry), key), String.eq(key, TC.StateEntry.key_text(entry)),
          False{}, StringsProof.eq_symmetric(TC.StateEntry.key_text(entry), key),
          BoolsProof.or_left_false(String.eq(key, TC.StateEntry.key_text(entry)), Laws.key_among(key, rest), absent))) :
        {TC.Entries.get.put(entry, TC.Entries.get(rest, key), _) == None{} : Maybe<&2, TC.StateValue>}
      get_missing(rest, key,
        BoolsProof.or_right_false(String.eq(key, TC.StateEntry.key_text(entry)), Laws.key_among(key, rest), absent))

# When no entry of the state has the key, looking it up gives None{}: the
# law get_absent, which PROOF.bend proves with it. It is get_missing on the
# state's entries.
law get_absent:
  for state: TC.TraceState
  for +key: TC.StateKey
  for absent: {Laws.key_among(TC.StateKey.to_string(key), TC.TraceState.entries(state)) == False{} : Bool}
  {TC.TraceState.get(state, key) == None{} : Maybe<&2, TC.StateValue>}

def get_absent(state, key, absent):
  get_missing(TC.TraceState.entries(state), TC.StateKey.to_string(key), absent)

# Before an entry whose key they lack, lookups pass every entry by: when no
# entry of `before` has the key of `entry`, looking up that key in `before`,
# then `entry`, then `after` gives the value of `entry`. Induction on
# `before`. get_entry uses it.
law get_first:
  for before: List<&2, TC.StateEntry>
  for +entry: TC.StateEntry
  for +after: List<&2, TC.StateEntry>
  for +absent: {TC.Entries.has_key(before, TC.StateEntry.key_text(entry)) == False{} : Bool}
  {TC.Entries.get(List.append(&2, TC.StateEntry, before, Con{entry, after}), TC.StateEntry.key_text(entry)) ==
    Some{TC.StateEntry.value(entry)} : Maybe<&2, TC.StateValue>}

def get_first(before, entry, after, absent):
  match before:
    case Nil{}:
      %Equal.sym(Bool, String.eq(TC.StateEntry.key_text(entry), TC.StateEntry.key_text(entry)), True{},
        StringsProof.eq_refl(TC.StateEntry.key_text(entry))) :
        {TC.Entries.get.put(entry, TC.Entries.get(after, TC.StateEntry.key_text(entry)), _) ==
          Some{TC.StateEntry.value(entry)} : Maybe<&2, TC.StateValue>}
      {==}
    case Con{+first, +rest}:
      %Equal.sym(Bool, String.eq(TC.StateEntry.key_text(first), TC.StateEntry.key_text(entry)), False{},
        BoolsProof.or_left_false(String.eq(TC.StateEntry.key_text(first), TC.StateEntry.key_text(entry)),
          TC.Entries.has_key(rest, TC.StateEntry.key_text(entry)), absent)) :
        {TC.Entries.get.put(first, TC.Entries.get(List.append(&2, TC.StateEntry, rest, Con{entry, after}),
          TC.StateEntry.key_text(entry)), _) == Some{TC.StateEntry.value(entry)} : Maybe<&2, TC.StateValue>}
      get_first(rest, entry, after,
        BoolsProof.or_right_false(String.eq(TC.StateEntry.key_text(first), TC.StateEntry.key_text(entry)),
          TC.Entries.has_key(rest, TC.StateEntry.key_text(entry)), absent))

# In distinct keys, no entry before another has its key: when
# Entries.unique accepts `before`, then `entry`, then `after`, starting from
# `seen`, neither `seen` nor `before` has the key of `entry`. Induction on
# `before`, which moves into `seen` one entry at a time. get_entry uses it
# with an empty `seen`.
law unique_split:
  for before: List<&2, TC.StateEntry>
  for +entry: TC.StateEntry
  for +after: List<&2, TC.StateEntry>
  for +seen: List<&2, TC.StateEntry>
  for +unique: {TC.Entries.unique(List.append(&2, TC.StateEntry, before, Con{entry, after}), seen) == True{} : Bool}
  {TC.Entries.has_key(List.append(&2, TC.StateEntry, seen, before), TC.StateEntry.key_text(entry)) == False{} : Bool}

def unique_split(before, entry, after, seen, unique):
  match before:
    case Nil{}:
      %Equal.sym(List<&2, TC.StateEntry>, List.append(&2, TC.StateEntry, seen, Nil{}), seen,
        ListsProof.append_nil(TC.StateEntry, seen)) :
        {TC.Entries.has_key(_, TC.StateEntry.key_text(entry)) == False{} : Bool}
      BoolsProof.not_true(TC.Entries.has_key(seen, TC.StateEntry.key_text(entry)),
        BoolsProof.and_left(Bool.not(TC.Entries.has_key(seen, TC.StateEntry.key_text(entry))),
          TC.Entries.unique(after, List.append(&2, TC.StateEntry, seen, Con{entry, Nil{}})), unique))
    case Con{+first, +rest}:
      %ListsProof.append_assoc(TC.StateEntry, seen, Con{first, Nil{}}, rest) :
        {TC.Entries.has_key(_, TC.StateEntry.key_text(entry)) == False{} : Bool}
      unique_split(rest, entry, after, List.append(&2, TC.StateEntry, seen, Con{first, Nil{}}),
        BoolsProof.and_right(Bool.not(TC.Entries.has_key(seen, TC.StateEntry.key_text(first))),
          TC.Entries.unique(List.append(&2, TC.StateEntry, rest, Con{entry, after}),
            List.append(&2, TC.StateEntry, seen, Con{first, Nil{}})), unique))

# When `split` places `entry` in a state, between `before` and `after`,
# looking up the key of `entry` gives its value: the law get_entry, which
# PROOF.bend proves with it. unique_split shows that no entry of `before`
# has the key, and get_first then finds `entry`.
law get_entry:
  for state: TC.TraceState
  for +before: List<&2, TC.StateEntry>
  for +entry: TC.StateEntry
  for +after: List<&2, TC.StateEntry>
  for +split: {TC.TraceState.entries(state) == List.append(&2, TC.StateEntry, before, Con{entry, after}) :
    List<&2, TC.StateEntry>}
  {TC.TraceState.get(state, TC.StateEntry.key(entry)) == Some{TC.StateEntry.value(entry)} :
    Maybe<&2, TC.StateValue>}

def get_entry(state, before, entry, after, split):
  match state:
    case TC.TraceState{entries, evidence}:
      %Equal.sym(List<&2, TC.StateEntry>, entries, List.append(&2, TC.StateEntry, before, Con{entry, after}), split) :
        {TC.Entries.get(_, TC.StateEntry.key_text(entry)) == Some{TC.StateEntry.value(entry)} :
          Maybe<&2, TC.StateValue>}
      get_first(before, entry, after,
        unique_split(before, entry, after, Nil{},
          %split : {TC.Entries.unique(_, Nil{}) == True{} : Bool}
          BoolsProof.and_left(TC.Entries.unique(entries, Nil{}),
            Nat.is_le(List.length(&2, TC.StateEntry, entries), 32n), evidence)))
