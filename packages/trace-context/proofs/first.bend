# Proofs: two states' values joined by a comma
# ============================================
#
# Proves the package law first_wins of LAWS.bend (PROOF.bend's
# Laws.first_wins calls first_wins below): when two states have at most 32
# entries in all and their values joined by a comma fit the tracestate input
# budget, parsing the joined value gives the first state's entries followed,
# in order, by the second state's entries whose keys the first lacks
# (`missing`, defined in LAWS.bend). It is the general form of
# later_duplicate and later_new_key, and reuses the reading lemmas of
# proofs/merge.bend.
#
# MergeProof.parse_scan turns parsing into a run of the reading machine
# (TC.Scan), and MergeProof.read_state_then reads the first state's value and
# the comma, keeping all of its entries. merge_second then reads the second
# state's value, and merge_rest reads its entries by induction on those still
# to read. merge_rest is generalized over the scan's member number, room and
# kept entries, and over `seen`, the second state's entries already read, so
# that its induction hypothesis applies at the next entry. At the entry being
# read, `current`, followed by `rest`, it assumes five invariants, which are
# its hypotheses:
#
#   split   the kept entries are `earlier`, the first state's entries,
#           followed by missing(earlier, seen)
#   unique  no entry from `current` on repeats the key of an earlier entry
#           of the second state
#   valid   the kept entries have distinct keys
#   count   the kept entries, `current` and `rest` are at most 32 in all
#   fits    `current` and `rest` fit the members the scan still allows
#
# In reading order: after_room and has_key_append, which bound the room left
# and look keys up in two joined lists, with the general Nat and Bool lemmas
# of proofs/nats.bend and proofs/bools.bend; `missing` one entry at a time
# (missing_snoc, missing_subset); machine_key, where the scan's duplicate
# check meets the law's check on the first state's keys; split_step,
# valid_step and count_step, which carry split, valid and count to the next
# entry (unique passes on through BoolsProof.and_right, and fits by
# computation), and result_step, which does the same for the claim; then
# merge_rest, merge_second and first_wins.

import Base
import ../LAWS.bend as Laws
import ../trace_context.bend as TC
import ./bools.bend as BoolsProof
import ./lists.bend as ListsProof
import ./nats.bend as NatsProof
import ./tracestate.bend as StateProof
import ./distinct.bend as DistinctProof
import ./merge.bend as MergeProof

# Room left
# =========

# When a + b <= room, then b <= MergeProof.after(a, room), the members still
# allowed once `a` more are counted. By induction on `a` and `room`; a room
# of 0 with a > 0 contradicts `fits`. merge_second uses it to show that the
# second state's entries fit the room that the first state's entries leave
# of the 32 members allowed.
law after_room:
  for a: Nat
  for b: Nat
  for room: Nat
  for fits: {Nat.is_le(Nat.add(a, b), room) == True{} : Bool}
  {Nat.is_le(b, MergeProof.after(a, room)) == True{} : Bool}

def after_room(a, b, room, fits):
  match a:
    case 0n:
      fits
    case 1n+less:
      match room:
        case 0n:
          BoolsProof.absurd({Nat.is_le(b, MergeProof.after(1n+less, 0n)) == True{} : Bool}, fits)
        case 1n+more:
          after_room(less, b, more, fits)

# Keys
# ====

# A lookup in two lists joined is a lookup in either: TC.Entries.has_key on
# `before` followed by `after` is the Bool.or of the lookups in each. By
# induction on `before`. machine_key uses it to split the kept entries into
# the first state's entries and those kept from the second.
law has_key_append:
  for before: List<&2, TC.StateEntry>
  for +after: List<&2, TC.StateEntry>
  for +key: String
  {TC.Entries.has_key(List.append(&2, TC.StateEntry, before, after), key) ==
    Bool.or(TC.Entries.has_key(before, key), TC.Entries.has_key(after, key)) : Bool}

def has_key_append(before, after, key):
  match before:
    case Nil{}:
      {==}
    case Con{+entry, +rest}:
      %Equal.sym(Bool, TC.Entries.has_key(List.append(&2, TC.StateEntry, rest, after), key),
        Bool.or(TC.Entries.has_key(rest, key), TC.Entries.has_key(after, key)), has_key_append(rest, after, key)) :
        {Bool.or(String.eq(TC.StateEntry.key_text(entry), key), _) ==
          Bool.or(Bool.or(String.eq(TC.StateEntry.key_text(entry), key), TC.Entries.has_key(rest, key)),
            TC.Entries.has_key(after, key)) : Bool}
      BoolsProof.or_assoc(String.eq(TC.StateEntry.key_text(entry), key), TC.Entries.has_key(rest, key),
        TC.Entries.has_key(after, key))

# One more entry of the second state
# ==================================

# Appending a tail commutes with Bool.pick, which gives its first list when
# `c` is True and its second otherwise: picking between `kept` and
# Con{entry, kept}, then appending `tail`, is picking between the two lists
# with `tail` already appended. By cases on `c`. missing_snoc uses it.
law pick_append:
  for c: Bool
  for -kept: List<&2, TC.StateEntry>
  for -entry: TC.StateEntry
  for -tail: List<&2, TC.StateEntry>
  {Bool.pick(List<&2, TC.StateEntry>, c, List.append(&2, TC.StateEntry, kept, tail),
    Con{entry, List.append(&2, TC.StateEntry, kept, tail)}) ==
    List.append(&2, TC.StateEntry, Bool.pick(List<&2, TC.StateEntry>, c, kept, Con{entry, kept}), tail) :
    List<&2, TC.StateEntry>}

def pick_append(c, kept, entry, tail):
  match c:
    case True{}:
      {==}
    case False{}:
      {==}

# `missing` of a list with one more entry at its end: what it keeps of the
# list, followed by the entry unless an entry of `earlier` has its key (the
# Bool.pick gives Nil{} when key_among is True). By induction on `seen`.
# split_step uses it when the scan reads one more entry.
law missing_snoc:
  for +earlier: List<&2, TC.StateEntry>
  for seen: List<&2, TC.StateEntry>
  for +entry: TC.StateEntry
  {Laws.missing(earlier, List.append(&2, TC.StateEntry, seen, Con{entry, Nil{}})) ==
    List.append(&2, TC.StateEntry, Laws.missing(earlier, seen),
      Bool.pick(List<&2, TC.StateEntry>, Laws.key_among(TC.StateEntry.key_text(entry), earlier), Nil{},
        Con{entry, Nil{}})) : List<&2, TC.StateEntry>}

# The induction hypothesis rewrites both branches of the pick (two `_`).
def missing_snoc(earlier, seen, entry):
  match seen:
    case Nil{}:
      {==}
    case Con{+first, rest}:
      +tail = {Bool.pick(List<&2, TC.StateEntry>, Laws.key_among(TC.StateEntry.key_text(entry), earlier), Nil{},
        Con{entry, Nil{}}) : List<&2, TC.StateEntry>}
      %Equal.sym(List<&2, TC.StateEntry>,
        Laws.missing(earlier, List.append(&2, TC.StateEntry, rest, Con{entry, Nil{}})),
        List.append(&2, TC.StateEntry, Laws.missing(earlier, rest), tail), missing_snoc(earlier, rest, entry)) :
        {Bool.pick(List<&2, TC.StateEntry>, Laws.key_among(TC.StateEntry.key_text(first), earlier), _,
          Con{first, _}) == List.append(&2, TC.StateEntry, Laws.missing(earlier, Con{first, rest}), tail) :
          List<&2, TC.StateEntry>}
      pick_append(Laws.key_among(TC.StateEntry.key_text(first), earlier), Laws.missing(earlier, rest), first, tail)

# The step of missing_subset, for either answer `c` of key_among on `first`:
# when no entry of missing(earlier, rest) has `key` and `first` has another
# key, whichever list the Bool.pick gives, missing(earlier, rest) with or
# without `first` in front, has no entry with `key`. `c` is a parameter so
# that the proof can match on it (`match` never inspects a computed value);
# missing_subset passes the key_among call.
law missing_subset_step:
  for -earlier: List<&2, TC.StateEntry>
  for -first: TC.StateEntry
  for -rest: List<&2, TC.StateEntry>
  for +key: String
  for c: Bool
  for rest_absent: {TC.Entries.has_key(Laws.missing(earlier, rest), key) == False{} : Bool}
  for first_differs: {String.eq(TC.StateEntry.key_text(first), key) == False{} : Bool}
  {TC.Entries.has_key(Bool.pick(List<&2, TC.StateEntry>, c, Laws.missing(earlier, rest),
    Con{first, Laws.missing(earlier, rest)}), key) == False{} : Bool}

def missing_subset_step(earlier, first, rest, key, c, rest_absent, first_differs):
  match c:
    case True{}:
      rest_absent
    case False{}:
      %Equal.sym(Bool, String.eq(TC.StateEntry.key_text(first), key), False{}, first_differs) :
        {Bool.or(_, TC.Entries.has_key(Laws.missing(earlier, rest), key)) == False{} : Bool}
      rest_absent

# `missing` keeps only entries of its second list: when no entry of `seen`
# has `key`, no entry of missing(earlier, seen) has it either. By induction
# on `seen`, splitting `absent` with BoolsProof.or_left_false and
# or_right_false. machine_key uses it.
law missing_subset:
  for +earlier: List<&2, TC.StateEntry>
  for seen: List<&2, TC.StateEntry>
  for +key: String
  for +absent: {TC.Entries.has_key(seen, key) == False{} : Bool}
  {TC.Entries.has_key(Laws.missing(earlier, seen), key) == False{} : Bool}

def missing_subset(earlier, seen, key, absent):
  match seen:
    case Nil{}:
      {==}
    case Con{+first, +rest}:
      missing_subset_step(earlier, first, rest, key, Laws.key_among(TC.StateEntry.key_text(first), earlier),
        missing_subset(earlier, rest, key,
          BoolsProof.or_right_false(String.eq(TC.StateEntry.key_text(first), key), TC.Entries.has_key(rest, key),
            absent)),
        BoolsProof.or_left_false(String.eq(TC.StateEntry.key_text(first), key), TC.Entries.has_key(rest, key), absent))

# The scan's duplicate check on the kept entries is the law's check on the
# first state's keys: when the kept entries are `earlier` followed by
# missing(earlier, seen) (`split`) and no entry of `seen` has `key`
# (`fresh`, since the second state's keys are distinct), TC.Entries.has_key
# on the kept entries is key_among(key, earlier), as no entry kept from
# `seen` has `key`. merge_rest uses it at each entry of the second state.
law machine_key:
  for +earlier: List<&2, TC.StateEntry>
  for +seen: List<&2, TC.StateEntry>
  for +entries: List<&2, TC.StateEntry>
  for split: {entries == List.append(&2, TC.StateEntry, earlier, Laws.missing(earlier, seen)) : List<&2, TC.StateEntry>}
  for +key: String
  for +fresh: {TC.Entries.has_key(seen, key) == False{} : Bool}
  {TC.Entries.has_key(entries, key) == Laws.key_among(key, earlier) : Bool}

# Rewrites with split, has_key_append, missing_subset and BoolsProof.or_false
# in turn.
def machine_key(earlier, seen, entries, split, key, fresh):
  %Equal.sym(List<&2, TC.StateEntry>, entries, List.append(&2, TC.StateEntry, earlier, Laws.missing(earlier, seen)),
    split) : {TC.Entries.has_key(_, key) == Laws.key_among(key, earlier) : Bool}
  %Equal.sym(Bool, TC.Entries.has_key(List.append(&2, TC.StateEntry, earlier, Laws.missing(earlier, seen)), key),
    Bool.or(TC.Entries.has_key(earlier, key), TC.Entries.has_key(Laws.missing(earlier, seen), key)),
    has_key_append(earlier, Laws.missing(earlier, seen), key)) :
    {_ == Laws.key_among(key, earlier) : Bool}
  %Equal.sym(Bool, TC.Entries.has_key(Laws.missing(earlier, seen), key), False{},
    missing_subset(earlier, seen, key, fresh)) :
    {Bool.or(TC.Entries.has_key(earlier, key), _) == Laws.key_among(key, earlier) : Bool}
  %Equal.sym(Bool, Bool.or(TC.Entries.has_key(earlier, key), False{}), TC.Entries.has_key(earlier, key),
    BoolsProof.or_false(TC.Entries.has_key(earlier, key))) :
    {_ == Laws.key_among(key, earlier) : Bool}
  DistinctProof.has_key_among(earlier, key)

# One more entry of the second state, dropped or kept as the first state's
# keys decide, keeps the invariant `split`: when the scan's check
# (`machine`) and the law's check (`among`) give the same answer `present`,
# TC.Entries.add of `entry` gives `earlier` followed by `missing` of `seen`
# with `entry` appended. `present` is a parameter, not a call to either
# check, so that the proof can match on it. merge_rest uses it to pass
# `split` to the next entry.
law split_step:
  for +earlier: List<&2, TC.StateEntry>
  for +seen: List<&2, TC.StateEntry>
  for +entries: List<&2, TC.StateEntry>
  for +entry: TC.StateEntry
  for present: Bool
  for machine: {TC.Entries.has_key(entries, TC.StateEntry.key_text(entry)) == present : Bool}
  for among: {Laws.key_among(TC.StateEntry.key_text(entry), earlier) == present : Bool}
  for split: {entries == List.append(&2, TC.StateEntry, earlier, Laws.missing(earlier, seen)) : List<&2, TC.StateEntry>}
  {TC.Entries.add(entries, entry) == List.append(&2, TC.StateEntry, earlier,
    Laws.missing(earlier, List.append(&2, TC.StateEntry, seen, Con{entry, Nil{}}))) : List<&2, TC.StateEntry>}

def split_step(earlier, seen, entries, entry, present, machine, among, split):
  match present:
    case True{}:
      %Equal.sym(Bool, TC.Entries.has_key(entries, TC.StateEntry.key_text(entry)), True{}, machine) :
        {TC.Entries.add.if(entries, entry, _) == List.append(&2, TC.StateEntry, earlier,
          Laws.missing(earlier, List.append(&2, TC.StateEntry, seen, Con{entry, Nil{}}))) : List<&2, TC.StateEntry>}
      %Equal.sym(List<&2, TC.StateEntry>,
        Laws.missing(earlier, List.append(&2, TC.StateEntry, seen, Con{entry, Nil{}})),
        List.append(&2, TC.StateEntry, Laws.missing(earlier, seen),
          Bool.pick(List<&2, TC.StateEntry>, Laws.key_among(TC.StateEntry.key_text(entry), earlier), Nil{},
            Con{entry, Nil{}})), missing_snoc(earlier, seen, entry)) :
        {entries == List.append(&2, TC.StateEntry, earlier, _) : List<&2, TC.StateEntry>}
      %Equal.sym(Bool, Laws.key_among(TC.StateEntry.key_text(entry), earlier), True{}, among) :
        {entries == List.append(&2, TC.StateEntry, earlier, List.append(&2, TC.StateEntry, Laws.missing(earlier, seen),
          Bool.pick(List<&2, TC.StateEntry>, _, Nil{}, Con{entry, Nil{}}))) : List<&2, TC.StateEntry>}
      %Equal.sym(List<&2, TC.StateEntry>, List.append(&2, TC.StateEntry, Laws.missing(earlier, seen), Nil{}),
        Laws.missing(earlier, seen), ListsProof.append_nil(TC.StateEntry, Laws.missing(earlier, seen))) :
        {entries == List.append(&2, TC.StateEntry, earlier, _) : List<&2, TC.StateEntry>}
      split
    case False{}:
      %Equal.sym(Bool, TC.Entries.has_key(entries, TC.StateEntry.key_text(entry)), False{}, machine) :
        {TC.Entries.add.if(entries, entry, _) == List.append(&2, TC.StateEntry, earlier,
          Laws.missing(earlier, List.append(&2, TC.StateEntry, seen, Con{entry, Nil{}}))) : List<&2, TC.StateEntry>}
      %Equal.sym(List<&2, TC.StateEntry>,
        Laws.missing(earlier, List.append(&2, TC.StateEntry, seen, Con{entry, Nil{}})),
        List.append(&2, TC.StateEntry, Laws.missing(earlier, seen),
          Bool.pick(List<&2, TC.StateEntry>, Laws.key_among(TC.StateEntry.key_text(entry), earlier), Nil{},
            Con{entry, Nil{}})), missing_snoc(earlier, seen, entry)) :
        {List.append(&2, TC.StateEntry, entries, Con{entry, Nil{}}) == List.append(&2, TC.StateEntry, earlier, _) :
          List<&2, TC.StateEntry>}
      %Equal.sym(Bool, Laws.key_among(TC.StateEntry.key_text(entry), earlier), False{}, among) :
        {List.append(&2, TC.StateEntry, entries, Con{entry, Nil{}}) ==
          List.append(&2, TC.StateEntry, earlier, List.append(&2, TC.StateEntry, Laws.missing(earlier, seen),
            Bool.pick(List<&2, TC.StateEntry>, _, Nil{}, Con{entry, Nil{}}))) : List<&2, TC.StateEntry>}
      %ListsProof.append_assoc(TC.StateEntry, earlier, Laws.missing(earlier, seen), Con{entry, Nil{}}) :
        {List.append(&2, TC.StateEntry, entries, Con{entry, Nil{}}) == _ : List<&2, TC.StateEntry>}
      %split : {List.append(&2, TC.StateEntry, entries, Con{entry, Nil{}}) ==
        List.append(&2, TC.StateEntry, _, Con{entry, Nil{}}) : List<&2, TC.StateEntry>}
      {==}

# One more entry keeps the expected result: when the two checks agree as in
# split_step (`machine`, `among`), the kept entries after TC.Entries.add,
# followed by missing(earlier, rest), are the kept entries before it,
# followed by missing(earlier, Con{entry, rest}). merge_rest uses it to
# relate the result of reading the entries after `entry` to its own claim.
law result_step:
  for +earlier: List<&2, TC.StateEntry>
  for +entries: List<&2, TC.StateEntry>
  for +entry: TC.StateEntry
  for +rest: List<&2, TC.StateEntry>
  for present: Bool
  for machine: {TC.Entries.has_key(entries, TC.StateEntry.key_text(entry)) == present : Bool}
  for among: {Laws.key_among(TC.StateEntry.key_text(entry), earlier) == present : Bool}
  {List.append(&2, TC.StateEntry, TC.Entries.add(entries, entry), Laws.missing(earlier, rest)) ==
    List.append(&2, TC.StateEntry, entries, Laws.missing(earlier, Con{entry, rest})) : List<&2, TC.StateEntry>}

def result_step(earlier, entries, entry, rest, present, machine, among):
  match present:
    case True{}:
      %Equal.sym(Bool, TC.Entries.has_key(entries, TC.StateEntry.key_text(entry)), True{}, machine) :
        {List.append(&2, TC.StateEntry, TC.Entries.add.if(entries, entry, _), Laws.missing(earlier, rest)) ==
          List.append(&2, TC.StateEntry, entries, Laws.missing(earlier, Con{entry, rest})) : List<&2, TC.StateEntry>}
      %Equal.sym(Bool, Laws.key_among(TC.StateEntry.key_text(entry), earlier), True{}, among) :
        {List.append(&2, TC.StateEntry, entries, Laws.missing(earlier, rest)) ==
          List.append(&2, TC.StateEntry, entries, Bool.pick(List<&2, TC.StateEntry>, _, Laws.missing(earlier, rest),
            Con{entry, Laws.missing(earlier, rest)})) : List<&2, TC.StateEntry>}
      {==}
    case False{}:
      %Equal.sym(Bool, TC.Entries.has_key(entries, TC.StateEntry.key_text(entry)), False{}, machine) :
        {List.append(&2, TC.StateEntry, TC.Entries.add.if(entries, entry, _), Laws.missing(earlier, rest)) ==
          List.append(&2, TC.StateEntry, entries, Laws.missing(earlier, Con{entry, rest})) : List<&2, TC.StateEntry>}
      %Equal.sym(Bool, Laws.key_among(TC.StateEntry.key_text(entry), earlier), False{}, among) :
        {List.append(&2, TC.StateEntry, List.append(&2, TC.StateEntry, entries, Con{entry, Nil{}}),
          Laws.missing(earlier, rest)) ==
          List.append(&2, TC.StateEntry, entries, Bool.pick(List<&2, TC.StateEntry>, _, Laws.missing(earlier, rest),
            Con{entry, Laws.missing(earlier, rest)})) : List<&2, TC.StateEntry>}
      ListsProof.append_assoc(TC.StateEntry, entries, Con{entry, Nil{}}, Laws.missing(earlier, rest))

# One more entry keeps the invariant `valid`: when the kept entries have
# distinct keys, so do they after TC.Entries.add of `entry`. The scan's
# check arrives as the Bool `present` with its equation `machine`, so that
# the proof can match on it. A duplicate leaves the kept entries unchanged,
# and an entry with a new key is appended (MergeProof.unique_snoc).
# merge_rest uses it to pass `valid` on and for the final state's evidence.
law valid_step:
  for +entries: List<&2, TC.StateEntry>
  for +entry: TC.StateEntry
  for present: Bool
  for +machine: {TC.Entries.has_key(entries, TC.StateEntry.key_text(entry)) == present : Bool}
  for +valid: {TC.Entries.unique(entries, Nil{}) == True{} : Bool}
  {TC.Entries.unique(TC.Entries.add(entries, entry), Nil{}) == True{} : Bool}

def valid_step(entries, entry, present, machine, valid):
  match present:
    case True{}:
      %Equal.sym(Bool, TC.Entries.has_key(entries, TC.StateEntry.key_text(entry)), True{}, machine) :
        {TC.Entries.unique(TC.Entries.add.if(entries, entry, _), Nil{}) == True{} : Bool}
      valid
    case False{}:
      %Equal.sym(Bool, TC.Entries.has_key(entries, TC.StateEntry.key_text(entry)), False{}, machine) :
        {TC.Entries.unique(TC.Entries.add.if(entries, entry, _), Nil{}) == True{} : Bool}
      MergeProof.unique_snoc(entries, entry, Nil{}, valid, machine)

# One more entry keeps the invariant `count`: when the kept entries and the
# 1 + rest entries still to count are at most 32, so are the kept entries
# after TC.Entries.add and the `rest` after `entry`. A duplicate keeps the
# list (NatsProof.le_drop); a new key adds one entry (ListsProof.length_snoc,
# NatsProof.add_succ). merge_rest uses it at every entry.
law count_step:
  for +entries: List<&2, TC.StateEntry>
  for +entry: TC.StateEntry
  for +rest: Nat
  for present: Bool
  for machine: {TC.Entries.has_key(entries, TC.StateEntry.key_text(entry)) == present : Bool}
  for count: {Nat.is_le(Nat.add(List.length(&2, TC.StateEntry, entries), 1n+rest), 32n) == True{} : Bool}
  {Nat.is_le(Nat.add(List.length(&2, TC.StateEntry, TC.Entries.add(entries, entry)), rest), 32n) == True{} : Bool}

def count_step(entries, entry, rest, present, machine, count):
  match present:
    case True{}:
      %Equal.sym(Bool, TC.Entries.has_key(entries, TC.StateEntry.key_text(entry)), True{}, machine) :
        {Nat.is_le(Nat.add(List.length(&2, TC.StateEntry, TC.Entries.add.if(entries, entry, _)), rest), 32n) == True{} :
          Bool}
      NatsProof.le_drop(Nat.add(List.length(&2, TC.StateEntry, entries), rest), 32n,
        %NatsProof.add_succ(List.length(&2, TC.StateEntry, entries), rest) : {Nat.is_le(_, 32n) == True{} : Bool}
        count)
    case False{}:
      %Equal.sym(Bool, TC.Entries.has_key(entries, TC.StateEntry.key_text(entry)), False{}, machine) :
        {Nat.is_le(Nat.add(List.length(&2, TC.StateEntry, TC.Entries.add.if(entries, entry, _)), rest), 32n) == True{} :
          Bool}
      %Equal.sym(Nat, List.length(&2, TC.StateEntry, List.append(&2, TC.StateEntry, entries, Con{entry, Nil{}})),
        1n+List.length(&2, TC.StateEntry, entries), ListsProof.length_snoc(TC.StateEntry, entries, entry)) :
        {Nat.is_le(Nat.add(_, rest), 32n) == True{} : Bool}
      %NatsProof.add_succ(List.length(&2, TC.StateEntry, entries), rest) : {Nat.is_le(_, 32n) == True{} : Bool}
      count

# Reading the rest of the second state
# ====================================

# The induction over the second state's entries, started by merge_second.
# The scan has kept `entries` and has just read the text of `current`, now
# its pending member (an InValue holding the key and the value's characters
# most recent first, hence String.reverse); the text left is
# TC.Entries.format.rest(rest). Under the invariants split, unique, valid,
# count and fits (module header), finishing the scan gives `entries`
# followed by missing(earlier, Con{current, rest}).
law merge_rest:
  for rest: List<&2, TC.StateEntry>
  for +current: TC.StateEntry
  for +member: Nat
  for +allowed: Nat
  for +entries: List<&2, TC.StateEntry>
  for +seen: List<&2, TC.StateEntry>
  for +earlier: List<&2, TC.StateEntry>
  for +split: {entries == List.append(&2, TC.StateEntry, earlier, Laws.missing(earlier, seen)) :
    List<&2, TC.StateEntry>}
  for +unique: {TC.Entries.unique(Con{current, rest}, seen) == True{} : Bool}
  for +valid: {TC.Entries.unique(entries, Nil{}) == True{} : Bool}
  for +count: {Nat.is_le(Nat.add(List.length(&2, TC.StateEntry, entries),
    List.length(&2, TC.StateEntry, Con{current, rest})), 32n) == True{} : Bool}
  for fits: {Nat.is_le(List.length(&2, TC.StateEntry, Con{current, rest}), allowed) == True{} : Bool}
  {Result.map(&2, &2, TC.StateError, TC.TraceState, List<&2, TC.StateEntry>, parsed => TC.TraceState.entries(parsed),
    TC.Scan.finish(TC.Scan.text(TC.Entries.format.rest(rest), TC.Scanning{member, allowed,
      TC.InValue{TC.StateEntry.key_text(current), String.reverse(TC.StateValue.to_string(TC.StateEntry.value(current)))},
      entries}))) ==
    Done{List.append(&2, TC.StateEntry, entries, Laws.missing(earlier, Con{current, rest}))} :
    Result<&2, &2, TC.StateError, List<&2, TC.StateEntry>>}

# Induction on `rest`. The comma before `next` closes `current` by computation.
def merge_rest(rest, current, member, allowed, entries, seen, earlier, split, unique, valid, count, fits):
  match rest:
    case Nil{}:
      match allowed:
        case 0n:
          BoolsProof.absurd({Result.map(&2, &2, TC.StateError, TC.TraceState, List<&2, TC.StateEntry>,
            parsed => TC.TraceState.entries(parsed),
            TC.Scan.finish(TC.Scan.text(TC.Entries.format.rest(Nil{}), TC.Scanning{member, 0n,
              TC.InValue{TC.StateEntry.key_text(current),
                String.reverse(TC.StateValue.to_string(TC.StateEntry.value(current)))}, entries}))) ==
            Done{List.append(&2, TC.StateEntry, entries, Laws.missing(earlier, Con{current, Nil{}}))} :
            Result<&2, &2, TC.StateError, List<&2, TC.StateEntry>>}, fits)
        case 1n+left:
          +key = {TC.StateEntry.key_text(current) : String}
          +fresh = BoolsProof.not_true(TC.Entries.has_key(seen, key),
            BoolsProof.and_left(Bool.not(TC.Entries.has_key(seen, key)),
              TC.Entries.unique(Nil{}, List.append(&2, TC.StateEntry, seen, Con{current, Nil{}})), unique))
          +machine = machine_key(earlier, seen, entries, split, key, fresh)
          +kept = {TC.Entries.add(entries, current) : List<&2, TC.StateEntry>}
          +kept_valid = Equal.trans(Bool, TC.TraceState.is_valid(kept),
            Nat.is_le(List.length(&2, TC.StateEntry, kept), 32n), True{},
            %Equal.sym(Bool, TC.Entries.unique(kept, Nil{}), True{},
              valid_step(entries, current, Laws.key_among(key, earlier), machine, valid)) :
              {Bool.and(_, Nat.is_le(List.length(&2, TC.StateEntry, kept), 32n)) ==
                Nat.is_le(List.length(&2, TC.StateEntry, kept), 32n) : Bool}
            {==},
            %NatsProof.add_zero(List.length(&2, TC.StateEntry, kept)) : {Nat.is_le(_, 32n) == True{} : Bool}
            count_step(entries, current, 0n, Laws.key_among(key, earlier), machine, count))
          %Equal.sym(TC.Scan, TC.Scan.close(member, 1n+left, TC.InValue{key,
              String.reverse(TC.StateValue.to_string(TC.StateEntry.value(current)))}, entries),
            TC.Scan.keep(1n+left, member, current, entries), StateProof.close_keep(current, member, 1n+left, entries)) :
            {Result.map(&2, &2, TC.StateError, TC.TraceState, List<&2, TC.StateEntry>,
              parsed => TC.TraceState.entries(parsed), TC.Scan.result(_)) ==
              Done{List.append(&2, TC.StateEntry, entries, Laws.missing(earlier, Con{current, Nil{}}))} :
              Result<&2, &2, TC.StateError, List<&2, TC.StateEntry>>}
          %Equal.sym(Result<&2, &2, TC.StateError, TC.TraceState>,
            TC.Scan.state(kept, TC.TraceState.is_valid(kept), {==}), Done{TC.TraceState{kept, kept_valid}},
            StateProof.checked_valid(kept, kept_valid)) :
            {Result.map(&2, &2, TC.StateError, TC.TraceState, List<&2, TC.StateEntry>,
              parsed => TC.TraceState.entries(parsed), _) ==
              Done{List.append(&2, TC.StateEntry, entries, Laws.missing(earlier, Con{current, Nil{}}))} :
              Result<&2, &2, TC.StateError, List<&2, TC.StateEntry>>}
          Equal.cong(List<&2, TC.StateEntry>, Result<&2, &2, TC.StateError, List<&2, TC.StateEntry>>,
            list => Done{list}, kept, List.append(&2, TC.StateEntry, entries, Laws.missing(earlier, Con{current, Nil{}})),
            Equal.trans(List<&2, TC.StateEntry>, kept, List.append(&2, TC.StateEntry, kept, Nil{}),
              List.append(&2, TC.StateEntry, entries, Laws.missing(earlier, Con{current, Nil{}})),
              Equal.sym(List<&2, TC.StateEntry>, List.append(&2, TC.StateEntry, kept, Nil{}), kept,
                ListsProof.append_nil(TC.StateEntry, kept)),
              result_step(earlier, entries, current, Nil{}, Laws.key_among(key, earlier), machine, {==})))
    case Con{+next, +later}:
      match allowed:
        case 0n:
          BoolsProof.absurd({Result.map(&2, &2, TC.StateError, TC.TraceState, List<&2, TC.StateEntry>,
            parsed => TC.TraceState.entries(parsed),
            TC.Scan.finish(TC.Scan.text(TC.Entries.format.rest(Con{next, later}), TC.Scanning{member, 0n,
              TC.InValue{TC.StateEntry.key_text(current),
                String.reverse(TC.StateValue.to_string(TC.StateEntry.value(current)))}, entries}))) ==
            Done{List.append(&2, TC.StateEntry, entries, Laws.missing(earlier, Con{current, Con{next, later}}))} :
            Result<&2, &2, TC.StateError, List<&2, TC.StateEntry>>}, fits)
        case 1n+left:
          +key = {TC.StateEntry.key_text(current) : String}
          +fresh = BoolsProof.not_true(TC.Entries.has_key(seen, key),
            BoolsProof.and_left(Bool.not(TC.Entries.has_key(seen, key)),
              TC.Entries.unique(Con{next, later}, List.append(&2, TC.StateEntry, seen, Con{current, Nil{}})), unique))
          +machine = machine_key(earlier, seen, entries, split, key, fresh)
          +kept = {TC.Entries.add(entries, current) : List<&2, TC.StateEntry>}
          +target = {Done{List.append(&2, TC.StateEntry, entries, Laws.missing(earlier, Con{current, Con{next, later}}))} :
            Result<&2, &2, TC.StateError, List<&2, TC.StateEntry>>}
          %Equal.sym(TC.Scan, TC.Scan.close(member, 1n+left, TC.InValue{key,
              String.reverse(TC.StateValue.to_string(TC.StateEntry.value(current)))}, entries),
            TC.Scan.keep(1n+left, member, current, entries), StateProof.close_keep(current, member, 1n+left, entries)) :
            {Result.map(&2, &2, TC.StateError, TC.TraceState, List<&2, TC.StateEntry>,
              parsed => TC.TraceState.entries(parsed),
              TC.Scan.finish(TC.Scan.text(TC.StateEntry.format(next) ++ TC.Entries.format.rest(later), _))) == target :
              Result<&2, &2, TC.StateError, List<&2, TC.StateEntry>>}
          %Equal.sym(TC.Scan,
            TC.Scan.text(TC.StateEntry.format(next) ++ TC.Entries.format.rest(later),
              TC.Scanning{1n+member, left, TC.Blank{}, kept}),
            TC.Scan.text(TC.Entries.format.rest(later),
              TC.Scan.text(TC.StateEntry.format(next), TC.Scanning{1n+member, left, TC.Blank{}, kept})),
            StateProof.scan_append(TC.StateEntry.format(next), TC.Entries.format.rest(later),
              TC.Scanning{1n+member, left, TC.Blank{}, kept})) :
            {Result.map(&2, &2, TC.StateError, TC.TraceState, List<&2, TC.StateEntry>,
              parsed => TC.TraceState.entries(parsed), TC.Scan.finish(_)) == target :
              Result<&2, &2, TC.StateError, List<&2, TC.StateEntry>>}
          %Equal.sym(TC.Scan,
            TC.Scan.text(TC.StateEntry.format(next), TC.Scanning{1n+member, left, TC.Blank{}, kept}),
            TC.Scanning{1n+member, left, TC.InValue{TC.StateEntry.key_text(next),
              String.reverse(TC.StateValue.to_string(TC.StateEntry.value(next)))}, kept},
            StateProof.read_entry(next, 1n+member, left, kept)) :
            {Result.map(&2, &2, TC.StateError, TC.TraceState, List<&2, TC.StateEntry>,
              parsed => TC.TraceState.entries(parsed), TC.Scan.finish(TC.Scan.text(TC.Entries.format.rest(later), _))) ==
              target : Result<&2, &2, TC.StateError, List<&2, TC.StateEntry>>}
          Equal.trans(Result<&2, &2, TC.StateError, List<&2, TC.StateEntry>>,
            Result.map(&2, &2, TC.StateError, TC.TraceState, List<&2, TC.StateEntry>,
              parsed => TC.TraceState.entries(parsed),
              TC.Scan.finish(TC.Scan.text(TC.Entries.format.rest(later), TC.Scanning{1n+member, left,
                TC.InValue{TC.StateEntry.key_text(next),
                  String.reverse(TC.StateValue.to_string(TC.StateEntry.value(next)))}, kept}))),
            Done{List.append(&2, TC.StateEntry, kept, Laws.missing(earlier, Con{next, later}))}, target,
            merge_rest(later, next, 1n+member, left, kept, List.append(&2, TC.StateEntry, seen, Con{current, Nil{}}),
              earlier, split_step(earlier, seen, entries, current, Laws.key_among(key, earlier), machine, {==}, split),
              BoolsProof.and_right(Bool.not(TC.Entries.has_key(seen, key)),
                TC.Entries.unique(Con{next, later}, List.append(&2, TC.StateEntry, seen, Con{current, Nil{}})), unique),
              valid_step(entries, current, Laws.key_among(key, earlier), machine, valid),
              count_step(entries, current, List.length(&2, TC.StateEntry, Con{next, later}), Laws.key_among(key, earlier),
                machine, count),
              fits),
            Equal.cong(List<&2, TC.StateEntry>, Result<&2, &2, TC.StateError, List<&2, TC.StateEntry>>,
              list => Done{list}, List.append(&2, TC.StateEntry, kept, Laws.missing(earlier, Con{next, later})),
              List.append(&2, TC.StateEntry, entries, Laws.missing(earlier, Con{current, Con{next, later}})),
              result_step(earlier, entries, current, Con{next, later}, Laws.key_among(key, earlier), machine, {==})))

# Reading the second state's value, the last step of first_wins, from the
# scan that MergeProof.read_state_then leaves: the first state's entries kept
# and no member pending. When both lists are valid states with at most 32
# entries in all, finishing gives `earlier` followed by
# missing(earlier, later). An empty second state leaves only an empty member,
# which is ignored; otherwise merge_rest starts with nothing in `seen`.
law merge_second:
  for later: List<&2, TC.StateEntry>
  for +later_evidence: {TC.TraceState.is_valid(later) == True{} : Bool}
  for +earlier: List<&2, TC.StateEntry>
  for +earlier_evidence: {TC.TraceState.is_valid(earlier) == True{} : Bool}
  for +count: {Nat.is_le(Nat.add(List.length(&2, TC.StateEntry, earlier), List.length(&2, TC.StateEntry, later)), 32n) ==
    True{} : Bool}
  {Result.map(&2, &2, TC.StateError, TC.TraceState, List<&2, TC.StateEntry>, parsed => TC.TraceState.entries(parsed),
    TC.Scan.finish(TC.Scan.text(TC.Entries.format(later), TC.Scanning{MergeProof.opened(earlier),
      MergeProof.after(List.length(&2, TC.StateEntry, earlier), 32n), TC.Blank{}, earlier}))) ==
    Done{List.append(&2, TC.StateEntry, earlier, Laws.missing(earlier, later))} :
    Result<&2, &2, TC.StateError, List<&2, TC.StateEntry>>}

def merge_second(later, later_evidence, earlier, earlier_evidence, count):
  match later:
    case Nil{}:
      %Equal.sym(Result<&2, &2, TC.StateError, TC.TraceState>,
        TC.Scan.state(earlier, TC.TraceState.is_valid(earlier), {==}), Done{TC.TraceState{earlier, earlier_evidence}},
        StateProof.checked_valid(earlier, earlier_evidence)) :
        {Result.map(&2, &2, TC.StateError, TC.TraceState, List<&2, TC.StateEntry>,
          parsed => TC.TraceState.entries(parsed), _) ==
          Done{List.append(&2, TC.StateEntry, earlier, Laws.missing(earlier, Nil{}))} :
          Result<&2, &2, TC.StateError, List<&2, TC.StateEntry>>}
      Equal.cong(List<&2, TC.StateEntry>, Result<&2, &2, TC.StateError, List<&2, TC.StateEntry>>,
        list => Done{list}, earlier, List.append(&2, TC.StateEntry, earlier, Nil{}),
        Equal.sym(List<&2, TC.StateEntry>, List.append(&2, TC.StateEntry, earlier, Nil{}), earlier,
          ListsProof.append_nil(TC.StateEntry, earlier)))
    case Con{+first, +rest}:
      +room = {MergeProof.after(List.length(&2, TC.StateEntry, earlier), 32n) : Nat}
      +target = {Done{List.append(&2, TC.StateEntry, earlier, Laws.missing(earlier, Con{first, rest}))} :
        Result<&2, &2, TC.StateError, List<&2, TC.StateEntry>>}
      %Equal.sym(TC.Scan,
        TC.Scan.text(TC.StateEntry.format(first) ++ TC.Entries.format.rest(rest),
          TC.Scanning{MergeProof.opened(earlier), room, TC.Blank{}, earlier}),
        TC.Scan.text(TC.Entries.format.rest(rest),
          TC.Scan.text(TC.StateEntry.format(first), TC.Scanning{MergeProof.opened(earlier), room, TC.Blank{}, earlier})),
        StateProof.scan_append(TC.StateEntry.format(first), TC.Entries.format.rest(rest),
          TC.Scanning{MergeProof.opened(earlier), room, TC.Blank{}, earlier})) :
        {Result.map(&2, &2, TC.StateError, TC.TraceState, List<&2, TC.StateEntry>,
          parsed => TC.TraceState.entries(parsed), TC.Scan.finish(_)) == target :
          Result<&2, &2, TC.StateError, List<&2, TC.StateEntry>>}
      %Equal.sym(TC.Scan,
        TC.Scan.text(TC.StateEntry.format(first), TC.Scanning{MergeProof.opened(earlier), room, TC.Blank{}, earlier}),
        TC.Scanning{MergeProof.opened(earlier), room, TC.InValue{TC.StateEntry.key_text(first),
          String.reverse(TC.StateValue.to_string(TC.StateEntry.value(first)))}, earlier},
        StateProof.read_entry(first, MergeProof.opened(earlier), room, earlier)) :
        {Result.map(&2, &2, TC.StateError, TC.TraceState, List<&2, TC.StateEntry>,
          parsed => TC.TraceState.entries(parsed), TC.Scan.finish(TC.Scan.text(TC.Entries.format.rest(rest), _))) ==
          target : Result<&2, &2, TC.StateError, List<&2, TC.StateEntry>>}
      merge_rest(rest, first, MergeProof.opened(earlier), room, earlier, Nil{}, earlier,
        Equal.sym(List<&2, TC.StateEntry>, List.append(&2, TC.StateEntry, earlier, Nil{}), earlier,
          ListsProof.append_nil(TC.StateEntry, earlier)),
        BoolsProof.and_left(TC.Entries.unique(Con{first, rest}, Nil{}),
          Nat.is_le(List.length(&2, TC.StateEntry, Con{first, rest}), 32n), later_evidence),
        BoolsProof.and_left(TC.Entries.unique(earlier, Nil{}),
          Nat.is_le(List.length(&2, TC.StateEntry, earlier), 32n), earlier_evidence),
        count,
        after_room(List.length(&2, TC.StateEntry, earlier), List.length(&2, TC.StateEntry, Con{first, rest}), 32n,
          count))

# Two states' values joined by a comma: when the two states have at most 32
# entries in all (`count`) and the joined value fits the tracestate input
# budget (`fits`), parsing it gives the first state's entries, then, in
# order, the second's entries whose keys the first lacks. This is the law
# first_wins of LAWS.bend, which PROOF.bend's Laws.first_wins proves by
# calling it. Result.map keeps only the entries of the parsed state.
law first_wins:
  for +limits: TC.Limits
  for first: TC.TraceState
  for second: TC.TraceState
  for +count: {Nat.is_le(Nat.add(List.length(&2, TC.StateEntry, TC.TraceState.entries(first)),
    List.length(&2, TC.StateEntry, TC.TraceState.entries(second))), 32n) == True{} : Bool}
  for fits: {Nat.is_le(TC.Utf8.length(TC.TraceState.format(first) ++ "," ++ TC.TraceState.format(second)),
    TC.Limits.tracestate_input(limits)) == True{} : Bool}
  {Result.map(&2, &2, TC.StateError, TC.TraceState, List<&2, TC.StateEntry>, parsed => TC.TraceState.entries(parsed),
    TC.TraceState.parse(limits, TC.TraceState.format(first) ++ "," ++ TC.TraceState.format(second))) ==
    Done{List.append(&2, TC.StateEntry, TC.TraceState.entries(first),
      Laws.missing(TC.TraceState.entries(first), TC.TraceState.entries(second)))} :
    Result<&2, &2, TC.StateError, List<&2, TC.StateEntry>>}

def first_wins(limits, first, second, count, fits):
  match first:
    case TC.TraceState{+earlier, +earlier_evidence}:
      match second:
        case TC.TraceState{+later, +later_evidence}:
          +text = {TC.Entries.format(earlier) ++ "," ++ TC.Entries.format(later) : String}
          +target = {Done{List.append(&2, TC.StateEntry, earlier, Laws.missing(earlier, later))} :
            Result<&2, &2, TC.StateError, List<&2, TC.StateEntry>>}
          %Equal.sym(Result<&2, &2, TC.StateError, TC.TraceState>, TC.TraceState.parse(limits, text),
            TC.Scan.finish(TC.Scan.text(text, TC.Scan.start())), MergeProof.parse_scan(limits, text, fits)) :
            {Result.map(&2, &2, TC.StateError, TC.TraceState, List<&2, TC.StateEntry>,
              parsed => TC.TraceState.entries(parsed), _) == target :
              Result<&2, &2, TC.StateError, List<&2, TC.StateEntry>>}
          %Equal.sym(TC.Scan, TC.Scan.text(text, TC.Scan.start()),
            TC.Scan.text(TC.Entries.format(later), TC.Scanning{MergeProof.opened(earlier),
              MergeProof.after(List.length(&2, TC.StateEntry, earlier), 32n), TC.Blank{}, earlier}),
            MergeProof.read_state_then(earlier, earlier_evidence, TC.Entries.format(later))) :
            {Result.map(&2, &2, TC.StateError, TC.TraceState, List<&2, TC.StateEntry>,
              parsed => TC.TraceState.entries(parsed), TC.Scan.finish(_)) == target :
              Result<&2, &2, TC.StateError, List<&2, TC.StateEntry>>}
          merge_second(later, later_evidence, earlier, earlier_evidence, count)
