# Proofs: tracestate updates
# ==========================
#
# What TraceState.set and TraceState.remove of trace_context.bend do to a
# state's entries. PROOF.bend proves the laws set_entries, update_keeps_all,
# insert_entries, set_get, remove_entries and remove_get of LAWS.bend with
# the lemmas of the same names; proofs/emit.bend reuses the lemmas that turn
# distinct keys into the package's own check (valid_of_distinct,
# checked_entries).
#
# Both updates build a list and let TraceState.from_entries verify it, keeping
# the state given as a fallback when the check fails. The proofs show that the
# check never fails: the list has distinct keys and at most 32 entries, so the
# state's entries are exactly that list (checked_entries). Distinct keys are
# handled in LAWS.bend's forward form, keys_distinct, which is easier to carry
# through `without` and List.take than the package's backward form,
# Entries.unique; unique_of_distinct converts between them.
#
# In reading order: Laws.without and the package's Entries.without agree
# (pick_unless, without_law); removing a key keeps the other entries in
# order (without_order), removes the key (without_lacks) and shortens the
# list when the key is present (without_present); a prefix keeps entries in
# order (take_order); proofs/order.bend reads distinct keys, absent keys and
# lengths off entries kept in order; then the conversion to the package's
# check (unseen, unique_of_distinct, valid_of_distinct, checked_entries) and
# the laws.

import Base
import ../LAWS.bend as Laws
import ../trace_context.bend as TC
import ./strings.bend as StringsProof
import ./bools.bend as BoolsProof
import ./nats.bend as NatsProof
import ./lists.bend as ListsProof
import ./order.bend as OrderProof
import ./distinct.bend as DistinctProof
import ./first.bend as FirstProof

# Removing a key
# ==============

# Bool.pick between `rest` and Con{item, rest} is what the package's filter
# step Entries.unless gives for the same answer, by cases on it. without_law
# and proofs/emit.bend's dropped_missing use it to match the package's
# filters with LAWS.bend's definitions.
law pick_unless:
  for -A: Data
  for c: Bool
  for -item: A
  for -rest: List<&2, A>
  {Bool.pick(List<&2, A>, c, rest, Con{item, rest}) == TC.Entries.unless(A, c, item, rest) : List<&2, A>}

def pick_unless(A, c, item, rest):
  match c:
    case True{}:
      {==}
    case False{}:
      {==}

# LAWS.bend's `without` and the package's Entries.without remove the same
# entries: they compare the key with each entry's key in opposite orders,
# which StringsProof.eq_symmetric reconciles. Induction on the entries. The
# update laws are stated with `without` and proved through this lemma.
law without_law:
  for +key: String
  for entries: List<&2, TC.StateEntry>
  {Laws.without(key, entries) == TC.Entries.without(entries, key) : List<&2, TC.StateEntry>}

def without_law(key, entries):
  match entries:
    case Nil{}:
      {==}
    case Con{+entry, +rest}:
      %Equal.sym(List<&2, TC.StateEntry>, Laws.without(key, rest), TC.Entries.without(rest, key),
        without_law(key, rest)) :
        {Bool.pick(List<&2, TC.StateEntry>, String.eq(key, TC.StateEntry.key_text(entry)), _, Con{entry, _}) ==
          TC.Entries.unless(TC.StateEntry, String.eq(TC.StateEntry.key_text(entry), key), entry,
            TC.Entries.without(rest, key)) : List<&2, TC.StateEntry>}
      %StringsProof.eq_symmetric(key, TC.StateEntry.key_text(entry)) :
        {Bool.pick(List<&2, TC.StateEntry>, String.eq(key, TC.StateEntry.key_text(entry)), TC.Entries.without(rest, key),
          Con{entry, TC.Entries.without(rest, key)}) ==
          TC.Entries.unless(TC.StateEntry, _, entry, TC.Entries.without(rest, key)) : List<&2, TC.StateEntry>}
      pick_unless(TC.StateEntry, String.eq(key, TC.StateEntry.key_text(entry)), entry, TC.Entries.without(rest, key))

# When no entry has the key, removing it changes nothing. Induction on the
# entries: each comparison is False (BoolsProof.or_left_false), so each entry
# stays. insert_entries uses it.
law without_absent:
  for +key: String
  for entries: List<&2, TC.StateEntry>
  for +absent: {Laws.key_among(key, entries) == False{} : Bool}
  {Laws.without(key, entries) == entries : List<&2, TC.StateEntry>}

def without_absent(key, entries, absent):
  match entries:
    case Nil{}:
      {==}
    case Con{+entry, +rest}:
      +here = BoolsProof.or_left_false(String.eq(key, TC.StateEntry.key_text(entry)), Laws.key_among(key, rest), absent)
      +later = BoolsProof.or_right_false(String.eq(key, TC.StateEntry.key_text(entry)), Laws.key_among(key, rest), absent)
      %Equal.sym(Bool, String.eq(key, TC.StateEntry.key_text(entry)), False{}, here) :
        {Bool.pick(List<&2, TC.StateEntry>, _, Laws.without(key, rest), Con{entry, Laws.without(key, rest)}) ==
          Con{entry, rest} : List<&2, TC.StateEntry>}
      %Equal.sym(List<&2, TC.StateEntry>, Laws.without(key, rest), rest, without_absent(key, rest, later)) :
        {Con{entry, _} == Con{entry, rest} : List<&2, TC.StateEntry>}
      {==}

# The step of without_lacks for one entry, given the answer `same` of the
# comparison of `key` with the entry's key and the lemma for the rest. When
# `same` is True the entry is removed; otherwise the entry stays, and its key
# differs from `key`.
law without_lacks_step:
  for +key: String
  for +entry: TC.StateEntry
  for +rest: List<&2, TC.StateEntry>
  for same: Bool
  for evidence: {String.eq(key, TC.StateEntry.key_text(entry)) == same : Bool}
  for later: {Laws.key_among(key, Laws.without(key, rest)) == False{} : Bool}
  {Laws.key_among(key, Bool.pick(List<&2, TC.StateEntry>, same, Laws.without(key, rest),
    Con{entry, Laws.without(key, rest)})) == False{} : Bool}

def without_lacks_step(key, entry, rest, same, evidence, later):
  match same:
    case True{}:
      later
    case False{}:
      %Equal.sym(Bool, String.eq(key, TC.StateEntry.key_text(entry)), False{}, evidence) :
        {Bool.or(_, Laws.key_among(key, Laws.without(key, rest))) == False{} : Bool}
      later

# After removing a key, no entry has it. Induction on the entries, with
# without_lacks_step. set_entries uses it to put the key's new entry first
# without repeating it, and remove_get to find nothing.
law without_lacks:
  for +key: String
  for entries: List<&2, TC.StateEntry>
  {Laws.key_among(key, Laws.without(key, entries)) == False{} : Bool}

def without_lacks(key, entries):
  match entries:
    case Nil{}:
      {==}
    case Con{+entry, +rest}:
      without_lacks_step(key, entry, rest, String.eq(key, TC.StateEntry.key_text(entry)), {==},
        without_lacks(key, rest))

# The step of without_order for one entry: an entry that removal takes out
# leaves the rest kept in order behind it (OrderProof.order_extend); an entry
# that stays stays in front (OrderProof.order_cons).
law without_order_step:
  for +key: String
  for +entry: TC.StateEntry
  for +rest: List<&2, TC.StateEntry>
  for same: Bool
  for later: {Laws.in_order(rest, Laws.without(key, rest)) == True{} : Bool}
  {Laws.in_order(Con{entry, rest}, Bool.pick(List<&2, TC.StateEntry>, same, Laws.without(key, rest),
    Con{entry, Laws.without(key, rest)})) == True{} : Bool}

def without_order_step(key, entry, rest, same, later):
  match same:
    case True{}:
      OrderProof.order_extend(entry, rest, Laws.without(key, rest), later)
    case False{}:
      OrderProof.order_cons(entry, rest, Laws.without(key, rest), later)

# Removing a key keeps the other entries in order. Induction on the entries,
# with without_order_step. The updates read distinct keys, absent keys and
# lengths off it with OrderProof.order_distinct, order_among and
# order_length.
law without_order:
  for +key: String
  for entries: List<&2, TC.StateEntry>
  {Laws.in_order(entries, Laws.without(key, entries)) == True{} : Bool}

def without_order(key, entries):
  match entries:
    case Nil{}:
      {==}
    case Con{+entry, +rest}:
      without_order_step(key, entry, rest, String.eq(key, TC.StateEntry.key_text(entry)), without_order(key, rest))

# The step of without_present for one entry: `present` is stated with the
# answer `same` of this entry's comparison, so matching on `same` gives
# either the removed entry or a key found in the rest.
law without_present_step:
  for +key: String
  for -entry: TC.StateEntry
  for +rest: List<&2, TC.StateEntry>
  for same: Bool
  for present: {Bool.or(same, Laws.key_among(key, rest)) == True{} : Bool}
  for later: {Laws.key_among(key, rest) == True{} : Bool} ->
    {Nat.is_le(1n+List.length(&2, TC.StateEntry, Laws.without(key, rest)), List.length(&2, TC.StateEntry, rest)) ==
      True{} : Bool}
  {Nat.is_le(1n+List.length(&2, TC.StateEntry, Bool.pick(List<&2, TC.StateEntry>, same, Laws.without(key, rest),
    Con{entry, Laws.without(key, rest)})), 1n+List.length(&2, TC.StateEntry, rest)) == True{} : Bool}

def without_present_step(key, entry, rest, same, present, later):
  match same:
    case True{}:
      OrderProof.order_length(rest, Laws.without(key, rest), without_order(key, rest))
    case False{}:
      later(present)

# When an entry has the key, removing it leaves at least one entry fewer.
# Induction on the entries, with without_present_step. update_keeps_all uses
# it: the other entries of a state of at most 32 are at most 31, so none of
# them is evicted.
law without_present:
  for +key: String
  for entries: List<&2, TC.StateEntry>
  for present: {Laws.key_among(key, entries) == True{} : Bool}
  {Nat.is_le(1n+List.length(&2, TC.StateEntry, Laws.without(key, entries)), List.length(&2, TC.StateEntry, entries)) ==
    True{} : Bool}

def without_present(key, entries, present):
  match entries:
    case Nil{}:
      BoolsProof.absurd({Nat.is_le(1n, 0n) == True{} : Bool}, present)
    case Con{+entry, +rest}:
      without_present_step(key, entry, rest, String.eq(key, TC.StateEntry.key_text(entry)), present,
        found => without_present(key, rest, found))

# Taking a prefix
# ===============

# A prefix keeps entries in order. Induction on the list and `n`, with
# OrderProof.order_cons. set_valid reads the prefix's keys off it.
law take_order:
  for entries: List<&2, TC.StateEntry>
  for +n: Nat
  {Laws.in_order(entries, List.take(&2, TC.StateEntry, entries, n)) == True{} : Bool}

def take_order(entries, n):
  match entries n:
    case Nil{} _:
      {==}
    case Con{entry, rest} 0n:
      {==}
    case Con{+entry, +rest} 1n+m:
      OrderProof.order_cons(entry, rest, List.take(&2, TC.StateEntry, rest, m), take_order(rest, m))

# The package's check
# ===================

# No entry of `entries` has a key among the entries of `seen`: the condition
# under which the package's backward check, Entries.unique, agrees with
# keys_distinct.
def unseen(+seen: List<&2, TC.StateEntry>, entries: List<&2, TC.StateEntry>) -> Bool:
  match entries:
    case Nil{}:
      True{}
    case Con{entry, rest}:
      Bool.and(Bool.not(TC.Entries.has_key(seen, TC.StateEntry.key_text(entry))), unseen(seen, rest))

# Nothing is among no entries. Induction on the entries.
# valid_of_distinct uses it to start unique_of_distinct with no entry seen.
law unseen_nil:
  for entries: List<&2, TC.StateEntry>
  {unseen(Nil{}, entries) == True{} : Bool}

def unseen_nil(entries):
  match entries:
    case Nil{}:
      {==}
    case Con{entry, rest}:
      unseen_nil(rest)

# When no later entry's key is among `seen` or equal to the key of `entry`,
# none is among `seen` followed by `entry` either (FirstProof.has_key_append
# splits the lookup). Induction on the later entries. unique_of_distinct uses
# it at each entry it passes.
law unseen_snoc:
  for +seen: List<&2, TC.StateEntry>
  for +entry: TC.StateEntry
  for rest: List<&2, TC.StateEntry>
  for +before: {unseen(seen, rest) == True{} : Bool}
  for +fresh: {Laws.key_among(TC.StateEntry.key_text(entry), rest) == False{} : Bool}
  {unseen(List.append(&2, TC.StateEntry, seen, Con{entry, Nil{}}), rest) == True{} : Bool}

def unseen_snoc(seen, entry, rest, before, fresh):
  match rest:
    case Nil{}:
      {==}
    case Con{+next, +more}:
      +old = BoolsProof.not_true(TC.Entries.has_key(seen, TC.StateEntry.key_text(next)),
        BoolsProof.and_left(Bool.not(TC.Entries.has_key(seen, TC.StateEntry.key_text(next))), unseen(seen, more), before))
      +other = BoolsProof.or_left_false(String.eq(TC.StateEntry.key_text(entry), TC.StateEntry.key_text(next)),
        Laws.key_among(TC.StateEntry.key_text(entry), more), fresh)
      %Equal.sym(Bool, TC.Entries.has_key(List.append(&2, TC.StateEntry, seen, Con{entry, Nil{}}),
          TC.StateEntry.key_text(next)),
        Bool.or(TC.Entries.has_key(seen, TC.StateEntry.key_text(next)),
          TC.Entries.has_key(Con{entry, Nil{}}, TC.StateEntry.key_text(next))),
        FirstProof.has_key_append(seen, Con{entry, Nil{}}, TC.StateEntry.key_text(next))) :
        {Bool.and(Bool.not(_), unseen(List.append(&2, TC.StateEntry, seen, Con{entry, Nil{}}), more)) == True{} : Bool}
      %Equal.sym(Bool, TC.Entries.has_key(seen, TC.StateEntry.key_text(next)), False{}, old) :
        {Bool.and(Bool.not(Bool.or(_, Bool.or(String.eq(TC.StateEntry.key_text(entry), TC.StateEntry.key_text(next)),
          False{}))), unseen(List.append(&2, TC.StateEntry, seen, Con{entry, Nil{}}), more)) == True{} : Bool}
      %Equal.sym(Bool, String.eq(TC.StateEntry.key_text(entry), TC.StateEntry.key_text(next)), False{}, other) :
        {Bool.and(Bool.not(Bool.or(False{}, Bool.or(_, False{}))),
          unseen(List.append(&2, TC.StateEntry, seen, Con{entry, Nil{}}), more)) == True{} : Bool}
      unseen_snoc(seen, entry, more,
        BoolsProof.and_right(Bool.not(TC.Entries.has_key(seen, TC.StateEntry.key_text(next))), unseen(seen, more), before),
        BoolsProof.or_right_false(String.eq(TC.StateEntry.key_text(entry), TC.StateEntry.key_text(next)),
          Laws.key_among(TC.StateEntry.key_text(entry), more), fresh))

# Distinct keys pass the package's check: when no key repeats a later one and
# none is among `seen`, Entries.unique(entries, seen) is True. Induction on
# the entries, `seen` growing by one entry at each step as in the check
# itself; unseen_snoc carries the condition along. This is the converse of
# DistinctProof.distinct.
law unique_of_distinct:
  for entries: List<&2, TC.StateEntry>
  for +seen: List<&2, TC.StateEntry>
  for +distinct: {Laws.keys_distinct(entries) == True{} : Bool}
  for +fresh: {unseen(seen, entries) == True{} : Bool}
  {TC.Entries.unique(entries, seen) == True{} : Bool}

def unique_of_distinct(entries, seen, distinct, fresh):
  match entries:
    case Nil{}:
      {==}
    case Con{+entry, +rest}:
      +first = BoolsProof.and_left(Bool.not(TC.Entries.has_key(seen, TC.StateEntry.key_text(entry))), unseen(seen, rest),
        fresh)
      +later = BoolsProof.and_right(Bool.not(TC.Entries.has_key(seen, TC.StateEntry.key_text(entry))), unseen(seen, rest),
        fresh)
      +apart = BoolsProof.not_true(Laws.key_among(TC.StateEntry.key_text(entry), rest),
        BoolsProof.and_left(Bool.not(Laws.key_among(TC.StateEntry.key_text(entry), rest)), Laws.keys_distinct(rest),
          distinct))
      +rest_distinct = BoolsProof.and_right(Bool.not(Laws.key_among(TC.StateEntry.key_text(entry), rest)),
        Laws.keys_distinct(rest), distinct)
      %Equal.sym(Bool, Bool.not(TC.Entries.has_key(seen, TC.StateEntry.key_text(entry))), True{}, first) :
        {Bool.and(_, TC.Entries.unique(rest, List.append(&2, TC.StateEntry, seen, Con{entry, Nil{}}))) == True{} :
          Bool}
      unique_of_distinct(rest, List.append(&2, TC.StateEntry, seen, Con{entry, Nil{}}), rest_distinct,
        unseen_snoc(seen, entry, rest, later, apart))

# Entries with distinct keys, at most 32 of them, pass TraceState.is_valid,
# the check of every state.
law valid_of_distinct:
  for +entries: List<&2, TC.StateEntry>
  for distinct: {Laws.keys_distinct(entries) == True{} : Bool}
  for bound: {Nat.is_le(List.length(&2, TC.StateEntry, entries), 32n) == True{} : Bool}
  {TC.TraceState.is_valid(entries) == True{} : Bool}

def valid_of_distinct(entries, distinct, bound):
  %Equal.sym(Bool, TC.Entries.unique(entries, Nil{}), True{},
    unique_of_distinct(entries, Nil{}, distinct, unseen_nil(entries))) :
    {Bool.and(_, Nat.is_le(List.length(&2, TC.StateEntry, entries), 32n)) == True{} : Bool}
  bound

# TraceState.from_entries of entries that pass the check is the state of those
# entries with `evidence` as its proof: the named rewrite `%q@evidence`
# replaces the answer of the check and the proof it carries together. The
# updates and truncation rely on it through checked_entries; truncate_whole
# uses it directly.
law checked_state:
  for +entries: List<&2, TC.StateEntry>
  for fallback: TC.TraceState
  for evidence: {TC.TraceState.is_valid(entries) == True{} : Bool}
  {TC.TraceState.from_entries(entries, fallback) == TC.TraceState{entries, evidence} : TC.TraceState}

# Rewrites the check's answer and its proof with `%q@evidence`.
def checked_state(entries, fallback, evidence):
  %q@evidence : {TC.TraceState.from_entries.checked(entries, fallback, TC.TraceState.is_valid(entries), {==}) ==
    TC.TraceState.from_entries.checked(entries, fallback, _, q) : TC.TraceState}
  {==}

# The entries of TraceState.from_entries of entries that pass the check are
# those entries: the fallback is never used.
law checked_entries:
  for +entries: List<&2, TC.StateEntry>
  for fallback: TC.TraceState
  for evidence: {TC.TraceState.is_valid(entries) == True{} : Bool}
  {TC.TraceState.entries(TC.TraceState.from_entries(entries, fallback)) == entries : List<&2, TC.StateEntry>}

def checked_entries(entries, fallback, evidence):
  Equal.cong(TC.TraceState, List<&2, TC.StateEntry>, state => TC.TraceState.entries(state),
    TC.TraceState.from_entries(entries, fallback), TC.TraceState{entries, evidence}, checked_state(entries, fallback, evidence))

# The two halves of DistinctProof.state_valid for one state: its keys are
# distinct, and it has at most 32 entries. A pair returned by a call cannot
# be taken apart with a pattern, so Pair.fst and Pair.snd select the halves.
law state_distinct:
  for +state: TC.TraceState
  {Laws.keys_distinct(TC.TraceState.entries(state)) == True{} : Bool}

def state_distinct(state):
  Pair.fst({Laws.keys_distinct(TC.TraceState.entries(state)) == True{} : Bool},
    {Nat.is_le(List.length(&2, TC.StateEntry, TC.TraceState.entries(state)), 32n) == True{} : Bool},
    DistinctProof.state_valid(state))

# The second half: a state has at most 32 entries.
law state_bound:
  for +state: TC.TraceState
  {Nat.is_le(List.length(&2, TC.StateEntry, TC.TraceState.entries(state)), 32n) == True{} : Bool}

def state_bound(state):
  Pair.snd({Laws.keys_distinct(TC.TraceState.entries(state)) == True{} : Bool},
    {Nat.is_le(List.length(&2, TC.StateEntry, TC.TraceState.entries(state)), 32n) == True{} : Bool},
    DistinctProof.state_valid(state))

# Setting and removing
# ====================

# The list that TraceState.set builds passes the check: the new entry's key
# is not among the other entries (without_lacks, take_among), those keep
# distinct keys (without_distinct, take_distinct) and there are at most 31 of
# them (take_length). without_law turns LAWS.bend's `without` into the
# package's Entries.without.
law set_valid:
  for state: TC.TraceState
  for +key: TC.StateKey
  for value: TC.StateValue
  {TC.TraceState.is_valid(Con{TC.StateEntry{key, value}, List.take(&2, TC.StateEntry,
    TC.Entries.without(TC.TraceState.entries(state), TC.StateKey.to_string(key)), 31n)}) == True{} : Bool}

def set_valid(state, key, value):
  match state:
    case TC.TraceState{+entries, +evidence}:
      +text = TC.StateKey.to_string(key)
      +distinct = state_distinct(TC.TraceState{entries, evidence})
      +others = Laws.without(text, entries)
      +first = List.take(&2, TC.StateEntry, others, 31n)
      %without_law(text, entries) :
        {TC.TraceState.is_valid(Con{TC.StateEntry{key, value}, List.take(&2, TC.StateEntry, _, 31n)}) == True{} : Bool}
      valid_of_distinct(Con{TC.StateEntry{key, value}, first},
        (%Equal.sym(Bool, Laws.key_among(text, first), False{},
            OrderProof.order_among(others, first, text, take_order(others, 31n), without_lacks(text, entries))) :
          {Bool.and(Bool.not(_), Laws.keys_distinct(first)) == True{} : Bool}
          OrderProof.order_distinct(others, first, take_order(others, 31n),
            OrderProof.order_distinct(entries, others, without_order(text, entries), distinct))),
        ListsProof.take_length(TC.StateEntry, others, 31n))

# The entries of TraceState.set in the package's own terms, before
# without_law turns them into the statement of set_entries.
law set_entries_package:
  for +state: TC.TraceState
  for +key: TC.StateKey
  for +value: TC.StateValue
  {TC.TraceState.entries(TC.TraceState.set(state, key, value)) == Con{TC.StateEntry{key, value},
    List.take(&2, TC.StateEntry, TC.Entries.without(TC.TraceState.entries(state), TC.StateKey.to_string(key)), 31n)} :
    List<&2, TC.StateEntry>}

def set_entries_package(state, key, value):
  checked_entries(Con{TC.StateEntry{key, value}, List.take(&2, TC.StateEntry,
    TC.Entries.without(TC.TraceState.entries(state), TC.StateKey.to_string(key)), 31n)}, state,
    set_valid(state, key, value))

# Law set_entries: the new entry first, then at most 31 of the others, in
# their order. PROOF.bend's Laws.set_entries returns this proof.
law set_entries:
  for +state: TC.TraceState
  for +key: TC.StateKey
  for value: TC.StateValue
  {TC.TraceState.entries(TC.TraceState.set(state, key, value)) ==
    Con{TC.StateEntry{key, value}, List.take(&2, TC.StateEntry,
      Laws.without(TC.StateKey.to_string(key), TC.TraceState.entries(state)), 31n)} : List<&2, TC.StateEntry>}

def set_entries(state, key, value):
  %Equal.sym(List<&2, TC.StateEntry>, Laws.without(TC.StateKey.to_string(key), TC.TraceState.entries(state)),
    TC.Entries.without(TC.TraceState.entries(state), TC.StateKey.to_string(key)),
    without_law(TC.StateKey.to_string(key), TC.TraceState.entries(state))) :
    {TC.TraceState.entries(TC.TraceState.set(state, key, value)) ==
      Con{TC.StateEntry{key, value}, List.take(&2, TC.StateEntry, _, 31n)} : List<&2, TC.StateEntry>}
  set_entries_package(state, key, value)

# Law update_keeps_all: with the key present, the other entries are at most
# 31 (without_present, NatsProof.le_trans with the bound of 32), so List.take
# keeps them all (take_all).
law update_keeps_all:
  for +state: TC.TraceState
  for +key: TC.StateKey
  for value: TC.StateValue
  for present: {Laws.key_among(TC.StateKey.to_string(key), TC.TraceState.entries(state)) == True{} : Bool}
  {TC.TraceState.entries(TC.TraceState.set(state, key, value)) ==
    Con{TC.StateEntry{key, value}, Laws.without(TC.StateKey.to_string(key), TC.TraceState.entries(state))} :
    List<&2, TC.StateEntry>}

def update_keeps_all(state, key, value, present):
  +text = TC.StateKey.to_string(key)
  +entries = TC.TraceState.entries(state)
  +bound = state_bound(state)
  %ListsProof.take_all(TC.StateEntry, Laws.without(text, entries), 31n,
    NatsProof.le_trans(1n+List.length(&2, TC.StateEntry, Laws.without(text, entries)),
      List.length(&2, TC.StateEntry, entries), 32n, without_present(text, entries, present), bound)) :
    {TC.TraceState.entries(TC.TraceState.set(state, key, value)) == Con{TC.StateEntry{key, value}, _} :
      List<&2, TC.StateEntry>}
  set_entries(state, key, value)

# Law insert_entries: with the key absent, removing it changes nothing
# (without_absent), so set_entries keeps the first 31 entries of the state.
law insert_entries:
  for +state: TC.TraceState
  for +key: TC.StateKey
  for value: TC.StateValue
  for absent: {Laws.key_among(TC.StateKey.to_string(key), TC.TraceState.entries(state)) == False{} : Bool}
  {TC.TraceState.entries(TC.TraceState.set(state, key, value)) ==
    Con{TC.StateEntry{key, value}, List.take(&2, TC.StateEntry, TC.TraceState.entries(state), 31n)} :
    List<&2, TC.StateEntry>}

def insert_entries(state, key, value, absent):
  %without_absent(TC.StateKey.to_string(key), TC.TraceState.entries(state), absent) :
    {TC.TraceState.entries(TC.TraceState.set(state, key, value)) ==
      Con{TC.StateEntry{key, value}, List.take(&2, TC.StateEntry, _, 31n)} : List<&2, TC.StateEntry>}
  set_entries(state, key, value)

# Law set_get: the lookup meets the new entry first, and its key equals the
# key sought (StringsProof.eq_refl).
law set_get:
  for +state: TC.TraceState
  for +key: TC.StateKey
  for +value: TC.StateValue
  {TC.TraceState.get(TC.TraceState.set(state, key, value), key) == Some{value} : Maybe<&2, TC.StateValue>}

def set_get(state, key, value):
  +text = TC.StateKey.to_string(key)
  +others = List.take(&2, TC.StateEntry, TC.Entries.without(TC.TraceState.entries(state), text), 31n)
  %Equal.sym(List<&2, TC.StateEntry>, TC.TraceState.entries(TC.TraceState.set(state, key, value)),
    Con{TC.StateEntry{key, value}, others}, set_entries_package(state, key, value)) :
    {TC.Entries.get(_, text) == Some{value} : Maybe<&2, TC.StateValue>}
  %Equal.sym(Bool, String.eq(text, text), True{}, StringsProof.eq_refl(text)) :
    {TC.Entries.get.put(TC.StateEntry{key, value}, TC.Entries.get(others, text), _) == Some{value} :
      Maybe<&2, TC.StateValue>}
  {==}

# The list that TraceState.remove builds passes the check: removing a key
# keeps the other keys distinct (without_distinct) and adds no entry
# (without_length, within the state's 32).
law remove_valid:
  for state: TC.TraceState
  for +key: TC.StateKey
  {TC.TraceState.is_valid(TC.Entries.without(TC.TraceState.entries(state), TC.StateKey.to_string(key))) ==
    True{} : Bool}

def remove_valid(state, key):
  match state:
    case TC.TraceState{+entries, +evidence}:
      +text = TC.StateKey.to_string(key)
      +distinct = state_distinct(TC.TraceState{entries, evidence})
      +bound = state_bound(TC.TraceState{entries, evidence})
      %without_law(text, entries) : {TC.TraceState.is_valid(_) == True{} : Bool}
      valid_of_distinct(Laws.without(text, entries),
        OrderProof.order_distinct(entries, Laws.without(text, entries), without_order(text, entries), distinct),
        NatsProof.le_trans(List.length(&2, TC.StateEntry, Laws.without(text, entries)),
          List.length(&2, TC.StateEntry, entries), 32n,
          OrderProof.order_length(entries, Laws.without(text, entries), without_order(text, entries)), bound))

# The entries of TraceState.remove in the package's own terms.
law remove_entries_package:
  for +state: TC.TraceState
  for +key: TC.StateKey
  {TC.TraceState.entries(TC.TraceState.remove(state, key)) ==
    TC.Entries.without(TC.TraceState.entries(state), TC.StateKey.to_string(key)) : List<&2, TC.StateEntry>}

def remove_entries_package(state, key):
  checked_entries(TC.Entries.without(TC.TraceState.entries(state), TC.StateKey.to_string(key)), state,
    remove_valid(state, key))

# Law remove_entries: the other entries, in their order. PROOF.bend's
# Laws.remove_entries returns this proof.
law remove_entries:
  for +state: TC.TraceState
  for +key: TC.StateKey
  {TC.TraceState.entries(TC.TraceState.remove(state, key)) ==
    Laws.without(TC.StateKey.to_string(key), TC.TraceState.entries(state)) : List<&2, TC.StateEntry>}

def remove_entries(state, key):
  %Equal.sym(List<&2, TC.StateEntry>, Laws.without(TC.StateKey.to_string(key), TC.TraceState.entries(state)),
    TC.Entries.without(TC.TraceState.entries(state), TC.StateKey.to_string(key)),
    without_law(TC.StateKey.to_string(key), TC.TraceState.entries(state))) :
    {TC.TraceState.entries(TC.TraceState.remove(state, key)) == _ : List<&2, TC.StateEntry>}
  remove_entries_package(state, key)

# Law remove_get: the entries left lack the key (without_lacks), so the
# lookup finds nothing (DistinctProof.get_missing).
law remove_get:
  for +state: TC.TraceState
  for +key: TC.StateKey
  {TC.TraceState.get(TC.TraceState.remove(state, key), key) == None{} : Maybe<&2, TC.StateValue>}

def remove_get(state, key):
  +text = TC.StateKey.to_string(key)
  +entries = TC.TraceState.entries(state)
  %Equal.sym(List<&2, TC.StateEntry>, TC.TraceState.entries(TC.TraceState.remove(state, key)),
    TC.Entries.without(entries, text), remove_entries_package(state, key)) :
    {TC.Entries.get(_, text) == None{} : Maybe<&2, TC.StateValue>}
  DistinctProof.get_missing(TC.Entries.without(entries, text), text,
    (%without_law(text, entries) : {Laws.key_among(text, _) == False{} : Bool}
      without_lacks(text, entries)))
