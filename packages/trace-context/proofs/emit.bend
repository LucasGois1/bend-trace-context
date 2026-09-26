# Proofs: tracestate emission
# ===========================
#
# What the package emits for a state: its size, its truncation to the output
# budget, and the header values of an outgoing context. PROOF.bend proves the
# laws entry_size, state_size, truncate_fits, truncate_whole, truncate_order,
# truncate_dropped, truncate_steps, emit_fits and emit_accepted of LAWS.bend
# with the lemmas of the same names.
#
# Sizes follow the text: Utf8.length of a concatenation is the sum of the
# lengths (utf8_append), so an entry's size and a state's size, commas
# included, add up exactly as Entries.format writes them. Truncation repeats
# one removal step, Entries.shrink, while the state is over the budget. The
# proofs follow that loop by induction on its fuel: each step removes exactly
# one entry (shrink_length), so one step per entry reaches a state that fits
# (truncated_fits); each step keeps the other entries in their order
# (shrink_order), and in_order is transitive (OrderProof.order_trans), so
# the whole loop does too (truncated_order). Entries kept in order from a
# state keep its distinct keys and bound (OrderProof.order_distinct and
# order_length), so TraceState.from_entries accepts them, as
# UpdateProof.checked_entries requires. Finally, each piece of the loop is
# the matching piece of LAWS.bend's restatement of spec #1's procedure
# (format_joined, large_law, drop_last_large_law, drop_last_law,
# shrink_law), so the loop is that procedure (truncated_law).
#
# In reading order: sizes; the removal steps; the loop; the dropped keys;
# the truncated state; the procedure of spec #1; then emission.

import Base
import ../LAWS.bend as Laws
import ../trace_context.bend as TC
import ./strings.bend as StringsProof
import ./bools.bend as BoolsProof
import ./nats.bend as NatsProof
import ./lists.bend as ListsProof
import ./distinct.bend as DistinctProof
import ./first.bend as FirstProof
import ./limits.bend as LimitsProof
import ./normal.bend as NormalProof
import ./update.bend as UpdateProof
import ./order.bend as OrderProof

# Sizes
# =====

# The UTF-8 octets of a concatenation are those of its parts added up.
# Induction on the first text, with NatsProof.add_assoc to regroup the sum.
# entry_size and entries_size use it at every `++` of Entries.format.
law utf8_append:
  for a: String
  for +b: String
  {TC.Utf8.length(a ++ b) == Nat.add(TC.Utf8.length(a), TC.Utf8.length(b)) : Nat}

def utf8_append(a, b):
  match a:
    case SNil{}:
      {==}
    case SCon{+char, +rest}:
      %Equal.sym(Nat, TC.Utf8.length(rest ++ b), Nat.add(TC.Utf8.length(rest), TC.Utf8.length(b)),
        utf8_append(rest, b)) :
        {Nat.add(TC.Utf8.width(char), _) == Nat.add(Nat.add(TC.Utf8.width(char), TC.Utf8.length(rest)),
          TC.Utf8.length(b)) : Nat}
      NatsProof.add_assoc(TC.Utf8.width(char), TC.Utf8.length(rest), TC.Utf8.length(b))

# Law entry_size: key=value takes the key's octets, one for "=" and the
# value's octets (utf8_append).
law entry_size:
  for +entry: TC.StateEntry
  {TC.StateEntry.size(entry) == TC.Utf8.length(TC.StateEntry.format(entry)) : Nat}

def entry_size(entry):
  match entry:
    case TC.StateEntry{+key, +value}:
      +text = TC.StateKey.to_string(key)
      +rest = "=" ++ TC.StateValue.to_string(value)
      %Equal.sym(Nat, TC.Utf8.length(text ++ rest), Nat.add(TC.Utf8.length(text), TC.Utf8.length(rest)),
        utf8_append(text, rest)) :
        {Nat.add(TC.Utf8.length(text), 1n+TC.Utf8.length(TC.StateValue.to_string(value))) == _ : Nat}
      {==}

# Each entry after the first takes one octet for its comma and its own
# octets. Induction on the entries, with entry_size and utf8_append.
law rest_size:
  for entries: List<&2, TC.StateEntry>
  {TC.Entries.size.rest(entries) == TC.Utf8.length(TC.Entries.format.rest(entries)) : Nat}

def rest_size(entries):
  match entries:
    case Nil{}:
      {==}
    case Con{+entry, +rest}:
      %Equal.sym(Nat, TC.Utf8.length(TC.StateEntry.format(entry) ++ TC.Entries.format.rest(rest)),
        Nat.add(TC.Utf8.length(TC.StateEntry.format(entry)), TC.Utf8.length(TC.Entries.format.rest(rest))),
        utf8_append(TC.StateEntry.format(entry), TC.Entries.format.rest(rest))) :
        {1n+Nat.add(TC.StateEntry.size(entry), TC.Entries.size.rest(rest)) == 1n+_ : Nat}
      %entry_size(entry) :
        {1n+Nat.add(TC.StateEntry.size(entry), TC.Entries.size.rest(rest)) ==
          1n+Nat.add(_, TC.Utf8.length(TC.Entries.format.rest(rest))) : Nat}
      %rest_size(rest) :
        {1n+Nat.add(TC.StateEntry.size(entry), TC.Entries.size.rest(rest)) ==
          1n+Nat.add(TC.StateEntry.size(entry), _) : Nat}
      {==}

# The octets of entries joined by commas, as Entries.format writes them.
law entries_size:
  for entries: List<&2, TC.StateEntry>
  {TC.Entries.size(entries) == TC.Utf8.length(TC.Entries.format(entries)) : Nat}

def entries_size(entries):
  match entries:
    case Nil{}:
      {==}
    case Con{+entry, +rest}:
      %Equal.sym(Nat, TC.Utf8.length(TC.StateEntry.format(entry) ++ TC.Entries.format.rest(rest)),
        Nat.add(TC.Utf8.length(TC.StateEntry.format(entry)), TC.Utf8.length(TC.Entries.format.rest(rest))),
        utf8_append(TC.StateEntry.format(entry), TC.Entries.format.rest(rest))) :
        {Nat.add(TC.StateEntry.size(entry), TC.Entries.size.rest(rest)) == _ : Nat}
      %entry_size(entry) :
        {Nat.add(TC.StateEntry.size(entry), TC.Entries.size.rest(rest)) ==
          Nat.add(_, TC.Utf8.length(TC.Entries.format.rest(rest))) : Nat}
      %rest_size(rest) :
        {Nat.add(TC.StateEntry.size(entry), TC.Entries.size.rest(rest)) == Nat.add(TC.StateEntry.size(entry), _) : Nat}
      {==}

# Law state_size: the state's size is the octets of its normalized value.
law state_size:
  for +state: TC.TraceState
  {TC.TraceState.size(state) == TC.Utf8.length(TC.TraceState.format(state)) : Nat}

def state_size(state):
  entries_size(TC.TraceState.entries(state))

# Removal steps
# =============

# The step of drop_large_order for one entry: it stays when a large entry
# follows (order_cons), goes when it is the rightmost large one (order_skip),
# and stays with the rest untouched otherwise (order_refl).
law drop_large_order_step:
  for +entry: TC.StateEntry
  for +rest: List<&2, TC.StateEntry>
  for later_large: Bool
  for large: Bool
  for later: {Laws.in_order(rest, TC.Entries.drop_last_large(rest)) == True{} : Bool}
  {Laws.in_order(Con{entry, rest}, Bool.pick(List<&2, TC.StateEntry>, later_large,
    Con{entry, TC.Entries.drop_last_large(rest)}, Bool.pick(List<&2, TC.StateEntry>, large, rest, Con{entry, rest}))) ==
    True{} : Bool}

def drop_large_order_step(entry, rest, later_large, large, later):
  match later_large large:
    case True{} _:
      OrderProof.order_cons(entry, rest, TC.Entries.drop_last_large(rest), later)
    case False{} True{}:
      OrderProof.order_skip(rest, entry)
    case False{} False{}:
      OrderProof.order_refl(Con{entry, rest})

# Removing the rightmost large entry keeps the others in order. Induction on
# the entries, with drop_large_order_step.
law drop_large_order:
  for entries: List<&2, TC.StateEntry>
  {Laws.in_order(entries, TC.Entries.drop_last_large(entries)) == True{} : Bool}

def drop_large_order(entries):
  match entries:
    case Nil{}:
      {==}
    case Con{+entry, +rest}:
      drop_large_order_step(entry, rest, TC.Entries.has_large(rest), TC.StateEntry.is_large(entry),
        drop_large_order(rest))

# The step of drop_last_order for one entry: the last entry goes; any other
# stays (order_cons).
law drop_last_order_step:
  for +entry: TC.StateEntry
  for +rest: List<&2, TC.StateEntry>
  for empty: Bool
  for later: {Laws.in_order(rest, TC.Entries.drop_last(rest)) == True{} : Bool}
  {Laws.in_order(Con{entry, rest}, Bool.pick(List<&2, TC.StateEntry>, empty, Nil{},
    Con{entry, TC.Entries.drop_last(rest)})) == True{} : Bool}

def drop_last_order_step(entry, rest, empty, later):
  match empty:
    case True{}:
      {==}
    case False{}:
      OrderProof.order_cons(entry, rest, TC.Entries.drop_last(rest), later)

# Removing the last entry keeps the others in order. Induction on the
# entries, with drop_last_order_step.
law drop_last_order:
  for entries: List<&2, TC.StateEntry>
  {Laws.in_order(entries, TC.Entries.drop_last(entries)) == True{} : Bool}

def drop_last_order(entries):
  match entries:
    case Nil{}:
      {==}
    case Con{+entry, +rest}:
      drop_last_order_step(entry, rest, List.is_empty(&2, TC.StateEntry, rest), drop_last_order(rest))

# The step of shrink_order: whichever entry one removal step takes, the
# others stay in order.
law shrink_order_step:
  for +entries: List<&2, TC.StateEntry>
  for large: Bool
  {Laws.in_order(entries, Bool.pick(List<&2, TC.StateEntry>, large, TC.Entries.drop_last_large(entries),
    TC.Entries.drop_last(entries))) == True{} : Bool}

def shrink_order_step(entries, large):
  match large:
    case True{}:
      drop_large_order(entries)
    case False{}:
      drop_last_order(entries)

# One removal step keeps the other entries in order.
law shrink_order:
  for +entries: List<&2, TC.StateEntry>
  {Laws.in_order(entries, TC.Entries.shrink(entries)) == True{} : Bool}

def shrink_order(entries):
  shrink_order_step(entries, TC.Entries.has_large(entries))

# The step of drop_large_length for one entry, given the answers for the
# rest and for the entry and the lemma for the rest. When neither the entry
# nor the rest is large, `found` computes to {False{} == True{}}.
law drop_large_length_step:
  for -entry: TC.StateEntry
  for +rest: List<&2, TC.StateEntry>
  for later_large: Bool
  for later_large_is: {TC.Entries.has_large(rest) == later_large : Bool}
  for large: Bool
  for found: {Bool.or(large, later_large) == True{} : Bool}
  for later: {TC.Entries.has_large(rest) == True{} : Bool} ->
    {1n+List.length(&2, TC.StateEntry, TC.Entries.drop_last_large(rest)) == List.length(&2, TC.StateEntry, rest) : Nat}
  {1n+List.length(&2, TC.StateEntry, Bool.pick(List<&2, TC.StateEntry>, later_large,
    Con{entry, TC.Entries.drop_last_large(rest)}, Bool.pick(List<&2, TC.StateEntry>, large, rest, Con{entry, rest}))) ==
    1n+List.length(&2, TC.StateEntry, rest) : Nat}

def drop_large_length_step(entry, rest, later_large, later_large_is, large, found, later):
  match later_large large:
    case True{} _:
      %Equal.sym(Nat, 1n+List.length(&2, TC.StateEntry, TC.Entries.drop_last_large(rest)), List.length(&2, TC.StateEntry, rest),
        later(later_large_is)) :
        {1n+_ == 1n+List.length(&2, TC.StateEntry, rest) : Nat}
      {==}
    case False{} True{}:
      {==}
    case False{} False{}:
      BoolsProof.absurd({1n+List.length(&2, TC.StateEntry, Con{entry, rest}) == 1n+List.length(&2, TC.StateEntry, rest) :
        Nat}, found)

# When the entries have a large one, removing the rightmost removes exactly
# one entry. Induction on the entries, with drop_large_length_step.
law drop_large_length:
  for entries: List<&2, TC.StateEntry>
  for found: {TC.Entries.has_large(entries) == True{} : Bool}
  {1n+List.length(&2, TC.StateEntry, TC.Entries.drop_last_large(entries)) == List.length(&2, TC.StateEntry, entries) :
    Nat}

def drop_large_length(entries, found):
  match entries:
    case Nil{}:
      BoolsProof.absurd({1n == 0n : Nat}, found)
    case Con{+entry, +rest}:
      drop_large_length_step(entry, rest, TC.Entries.has_large(rest), {==}, TC.StateEntry.is_large(entry), found,
        large => drop_large_length(rest, large))

# Removing the last entry of a nonempty list leaves as many entries as its
# rest. Induction on the rest.
law drop_last_length:
  for rest: List<&2, TC.StateEntry>
  for -entry: TC.StateEntry
  {List.length(&2, TC.StateEntry, TC.Entries.drop_last(Con{entry, rest})) == List.length(&2, TC.StateEntry, rest) :
    Nat}

def drop_last_length(rest, entry):
  match rest:
    case Nil{}:
      {==}
    case Con{+next, +more}:
      %Equal.sym(Nat, List.length(&2, TC.StateEntry, TC.Entries.drop_last(Con{next, more})),
        List.length(&2, TC.StateEntry, more), drop_last_length(more, next)) :
        {1n+_ == 1n+List.length(&2, TC.StateEntry, more) : Nat}
      {==}

# The step of shrink_length, given the answer to whether the list has a
# large entry.
law shrink_length_step:
  for +entry: TC.StateEntry
  for +rest: List<&2, TC.StateEntry>
  for large: Bool
  for large_is: {TC.Entries.has_large(Con{entry, rest}) == large : Bool}
  {List.length(&2, TC.StateEntry, Bool.pick(List<&2, TC.StateEntry>, large, TC.Entries.drop_last_large(Con{entry, rest}),
    TC.Entries.drop_last(Con{entry, rest}))) == List.length(&2, TC.StateEntry, rest) : Nat}

def shrink_length_step(entry, rest, large, large_is):
  match large:
    case True{}:
      Equal.cong(Nat, Nat, n => NatsProof.pred(n), 1n+List.length(&2, TC.StateEntry, TC.Entries.drop_last_large(Con{entry, rest})),
        1n+List.length(&2, TC.StateEntry, rest), drop_large_length(Con{entry, rest}, large_is))
    case False{}:
      drop_last_length(rest, entry)

# One removal step on a nonempty list removes exactly one entry.
law shrink_length:
  for +entry: TC.StateEntry
  for +rest: List<&2, TC.StateEntry>
  {List.length(&2, TC.StateEntry, TC.Entries.shrink(Con{entry, rest})) == List.length(&2, TC.StateEntry, rest) : Nat}

def shrink_length(entry, rest):
  shrink_length_step(entry, rest, TC.Entries.has_large(Con{entry, rest}), {==})

# The truncation loop
# ===================

# The step of truncated_order: the loop stops with the entries unchanged, or
# takes one step and goes on (order_trans).
law truncated_order_step:
  for +more: Nat
  for +budget: Nat
  for +entries: List<&2, TC.StateEntry>
  for fits: Bool
  for later: {Laws.in_order(TC.Entries.shrink(entries), TC.Entries.truncate(more, budget, TC.Entries.shrink(entries))) ==
    True{} : Bool}
  {Laws.in_order(entries, Bool.pick(List<&2, TC.StateEntry>, fits, entries,
    TC.Entries.truncate(more, budget, TC.Entries.shrink(entries)))) == True{} : Bool}

def truncated_order_step(more, budget, entries, fits, later):
  match fits:
    case True{}:
      OrderProof.order_refl(entries)
    case False{}:
      OrderProof.order_trans(entries, TC.Entries.shrink(entries), TC.Entries.truncate(more, budget, TC.Entries.shrink(entries)),
        shrink_order(entries), later)

# The loop keeps the entries it does not remove in order. Induction on the
# fuel.
law truncated_order:
  for +fuel: Nat
  for +budget: Nat
  for +entries: List<&2, TC.StateEntry>
  {Laws.in_order(entries, TC.Entries.truncate(fuel, budget, entries)) == True{} : Bool}

def truncated_order(fuel, budget, entries):
  match fuel:
    case 0n:
      OrderProof.order_refl(entries)
    case 1n+more:
      truncated_order_step(more, budget, entries, Nat.is_le(TC.Entries.size(entries), budget),
        truncated_order(more, budget, TC.Entries.shrink(entries)))

# The step of truncated_fits for the empty list, which fits every budget
# (NatsProof.zero_le): the loop stops at once.
law empty_fits_step:
  for -more: Nat
  for +budget: Nat
  for fits: Bool
  for fits_is: {Nat.is_le(0n, budget) == fits : Bool}
  {Nat.is_le(TC.Entries.size(Bool.pick(List<&2, TC.StateEntry>, fits, Nil{},
    TC.Entries.truncate(more, budget, TC.Entries.shrink(Nil{})))), budget) == True{} : Bool}

def empty_fits_step(more, budget, fits, fits_is):
  match fits:
    case True{}:
      NatsProof.zero_le(budget)
    case False{}:
      Empty.absurd({Nat.is_le(TC.Entries.size(TC.Entries.truncate(more, budget, TC.Entries.shrink(Nil{}))), budget) ==
        True{} : Bool}, BoolsProof.true_ne_false(Equal.trans(Bool, True{}, Nat.is_le(0n, budget), False{},
          Equal.sym(Bool, Nat.is_le(0n, budget), True{}, NatsProof.zero_le(budget)), fits_is)))

# The step of truncated_fits for a nonempty list: the loop stops because the
# entries fit, or takes one step, after which there is one entry fewer
# (shrink_length) for one step fewer.
law truncated_fits_step:
  for +more: Nat
  for +budget: Nat
  for +entry: TC.StateEntry
  for +rest: List<&2, TC.StateEntry>
  for fits: Bool
  for fits_is: {Nat.is_le(TC.Entries.size(Con{entry, rest}), budget) == fits : Bool}
  for room: {Nat.is_le(List.length(&2, TC.StateEntry, rest), more) == True{} : Bool}
  for later: {Nat.is_le(List.length(&2, TC.StateEntry, TC.Entries.shrink(Con{entry, rest})), more) == True{} : Bool} ->
    {Nat.is_le(TC.Entries.size(TC.Entries.truncate(more, budget, TC.Entries.shrink(Con{entry, rest}))), budget) ==
      True{} : Bool}
  {Nat.is_le(TC.Entries.size(Bool.pick(List<&2, TC.StateEntry>, fits, Con{entry, rest},
    TC.Entries.truncate(more, budget, TC.Entries.shrink(Con{entry, rest})))), budget) == True{} : Bool}

def truncated_fits_step(more, budget, entry, rest, fits, fits_is, room, later):
  match fits:
    case True{}:
      fits_is
    case False{}:
      later((%Equal.sym(Nat, List.length(&2, TC.StateEntry, TC.Entries.shrink(Con{entry, rest})),
          List.length(&2, TC.StateEntry, rest), shrink_length(entry, rest)) :
        {Nat.is_le(_, more) == True{} : Bool}
        room))

# With at least one step per entry, the loop ends with entries that fit the
# budget. Induction on the fuel.
law truncated_fits:
  for +fuel: Nat
  for entries: List<&2, TC.StateEntry>
  for +budget: Nat
  for room: {Nat.is_le(List.length(&2, TC.StateEntry, entries), fuel) == True{} : Bool}
  {Nat.is_le(TC.Entries.size(TC.Entries.truncate(fuel, budget, entries)), budget) == True{} : Bool}

def truncated_fits(fuel, entries, budget, room):
  match fuel entries:
    case 0n Nil{}:
      NatsProof.zero_le(budget)
    case 0n Con{entry, rest}:
      BoolsProof.absurd({Nat.is_le(TC.Entries.size(Con{entry, rest}), budget) == True{} : Bool}, room)
    case 1n+more Nil{}:
      empty_fits_step(more, budget, Nat.is_le(0n, budget), {==})
    case 1n+more Con{+entry, +rest}:
      truncated_fits_step(more, budget, entry, rest, Nat.is_le(TC.Entries.size(Con{entry, rest}), budget), {==}, room,
        found => truncated_fits(more, TC.Entries.shrink(Con{entry, rest}), budget, found))

# Entries that fit the budget come out of the loop unchanged, with one step
# per entry.
law truncated_whole:
  for +entries: List<&2, TC.StateEntry>
  for +budget: Nat
  for fits: {Nat.is_le(TC.Entries.size(entries), budget) == True{} : Bool}
  {TC.Entries.truncate(List.length(&2, TC.StateEntry, entries), budget, entries) == entries : List<&2, TC.StateEntry>}

def truncated_whole(entries, budget, fits):
  match entries:
    case Nil{}:
      {==}
    case Con{+entry, +rest}:
      %Equal.sym(Bool, Nat.is_le(TC.Entries.size(Con{entry, rest}), budget), True{}, fits) :
        {Bool.pick(List<&2, TC.StateEntry>, _, Con{entry, rest}, TC.Entries.truncate(List.length(&2, TC.StateEntry, rest),
          budget, TC.Entries.shrink(Con{entry, rest}))) == Con{entry, rest} : List<&2, TC.StateEntry>}
      {==}

# The dropped keys
# ================

# The package's filter step on the dropped keys and LAWS.bend's `keys` of
# the choice that `missing` makes agree for the same answer, by cases on it.
law keys_pick:
  for c: Bool
  for +entry: TC.StateEntry
  for +rest: List<&2, TC.StateEntry>
  {TC.Entries.unless(TC.StateKey, c, TC.StateEntry.key(entry), Laws.keys(rest)) ==
    Laws.keys(Bool.pick(List<&2, TC.StateEntry>, c, rest, Con{entry, rest})) : List<&2, TC.StateKey>}

def keys_pick(c, entry, rest):
  match c:
    case True{}:
      {==}
    case False{}:
      {==}

# The package's Entries.dropped lists the keys of LAWS.bend's `missing`: both
# keep the entries that `kept` lacks, and they look the key up in the two
# ways that DistinctProof.has_key_among equates. Induction on the entries,
# with keys_pick.
law dropped_missing:
  for entries: List<&2, TC.StateEntry>
  for +kept: List<&2, TC.StateEntry>
  {TC.Entries.dropped(entries, kept) == Laws.keys(Laws.missing(kept, entries)) : List<&2, TC.StateKey>}

def dropped_missing(entries, kept):
  match entries:
    case Nil{}:
      {==}
    case Con{+entry, +rest}:
      %Equal.sym(Bool, TC.Entries.has_key(kept, TC.StateEntry.key_text(entry)),
        Laws.key_among(TC.StateEntry.key_text(entry), kept), DistinctProof.has_key_among(kept, TC.StateEntry.key_text(entry))) :
        {TC.Entries.unless(TC.StateKey, _, TC.StateEntry.key(entry), TC.Entries.dropped(rest, kept)) ==
          Laws.keys(Laws.missing(kept, Con{entry, rest})) : List<&2, TC.StateKey>}
      %Equal.sym(List<&2, TC.StateKey>, TC.Entries.dropped(rest, kept), Laws.keys(Laws.missing(kept, rest)),
        dropped_missing(rest, kept)) :
        {TC.Entries.unless(TC.StateKey, Laws.key_among(TC.StateEntry.key_text(entry), kept), TC.StateEntry.key(entry), _) ==
          Laws.keys(Laws.missing(kept, Con{entry, rest})) : List<&2, TC.StateKey>}
      keys_pick(Laws.key_among(TC.StateEntry.key_text(entry), kept), entry, Laws.missing(kept, rest))

# An entry's key is found in any list that holds the entry: the lookup
# splits at the entry (FirstProof.has_key_append), which compares equal to
# its own key (StringsProof.eq_refl).
law key_found:
  for +before: List<&2, TC.StateEntry>
  for +entry: TC.StateEntry
  for +after: List<&2, TC.StateEntry>
  {TC.Entries.has_key(List.append(&2, TC.StateEntry, before, Con{entry, after}), TC.StateEntry.key_text(entry)) ==
    True{} : Bool}

def key_found(before, entry, after):
  +key = TC.StateEntry.key_text(entry)
  %Equal.sym(Bool, TC.Entries.has_key(List.append(&2, TC.StateEntry, before, Con{entry, after}), key),
    Bool.or(TC.Entries.has_key(before, key), TC.Entries.has_key(Con{entry, after}, key)),
    FirstProof.has_key_append(before, Con{entry, after}, key)) :
    {_ == True{} : Bool}
  %Equal.sym(Bool, String.eq(key, key), True{}, StringsProof.eq_refl(key)) :
    {Bool.or(TC.Entries.has_key(before, key), Bool.or(_, TC.Entries.has_key(after, key))) == True{} : Bool}
  BoolsProof.or_true(TC.Entries.has_key(before, key))

# No entry is dropped against a list that holds all of them: every key is
# found (key_found), whatever precedes the entries in that list. Induction on
# the entries, `before` growing by one entry (ListsProof.append_assoc).
# truncate_whole uses it with nothing before.
law dropped_prefix:
  for entries: List<&2, TC.StateEntry>
  for +before: List<&2, TC.StateEntry>
  {TC.Entries.dropped(entries, List.append(&2, TC.StateEntry, before, entries)) == Nil{} : List<&2, TC.StateKey>}

def dropped_prefix(entries, before):
  match entries:
    case Nil{}:
      {==}
    case Con{+entry, +rest}:
      %Equal.sym(Bool, TC.Entries.has_key(List.append(&2, TC.StateEntry, before, Con{entry, rest}),
          TC.StateEntry.key_text(entry)), True{}, key_found(before, entry, rest)) :
        {TC.Entries.unless(TC.StateKey, _, TC.StateEntry.key(entry),
          TC.Entries.dropped(rest, List.append(&2, TC.StateEntry, before, Con{entry, rest}))) == Nil{} :
          List<&2, TC.StateKey>}
      %ListsProof.append_assoc(TC.StateEntry, before, Con{entry, Nil{}}, rest) :
        {TC.Entries.dropped(rest, _) == Nil{} : List<&2, TC.StateKey>}
      dropped_prefix(rest, List.append(&2, TC.StateEntry, before, Con{entry, Nil{}}))

# The truncated state
# ===================

# The entries the loop keeps pass the package's check: they are kept in
# order from the state (truncated_order), so their keys are distinct
# (order_distinct) and they are at most the state's 32 (order_length).
law kept_valid:
  for +budget: Nat
  for +state: TC.TraceState
  {TC.TraceState.is_valid(TC.Entries.truncate(List.length(&2, TC.StateEntry, TC.TraceState.entries(state)), budget,
    TC.TraceState.entries(state))) == True{} : Bool}

def kept_valid(budget, state):
  +entries = TC.TraceState.entries(state)
  +kept = TC.Entries.truncate(List.length(&2, TC.StateEntry, entries), budget, entries)
  +order = truncated_order(List.length(&2, TC.StateEntry, entries), budget, entries)
  UpdateProof.valid_of_distinct(kept, OrderProof.order_distinct(entries, kept, order, UpdateProof.state_distinct(state)),
    NatsProof.le_trans(List.length(&2, TC.StateEntry, kept), List.length(&2, TC.StateEntry, entries), 32n,
      OrderProof.order_length(entries, kept, order), UpdateProof.state_bound(state)))

# The entries of the state that truncation keeps are the entries the loop
# keeps.
law kept_entries:
  for +limits: TC.Limits
  for +state: TC.TraceState
  {TC.TraceState.entries(TC.Truncation.kept(TC.TraceState.truncate(limits, state))) ==
    TC.Entries.truncate(List.length(&2, TC.StateEntry, TC.TraceState.entries(state)), TC.Limits.tracestate_output(limits),
      TC.TraceState.entries(state)) : List<&2, TC.StateEntry>}

def kept_entries(limits, state):
  UpdateProof.checked_entries(TC.Entries.truncate(List.length(&2, TC.StateEntry, TC.TraceState.entries(state)),
    TC.Limits.tracestate_output(limits), TC.TraceState.entries(state)), TC.TraceState.empty(),
    kept_valid(TC.Limits.tracestate_output(limits), state))

# Law truncate_fits: the loop has one step per entry (NatsProof.le_refl), so
# what it keeps fits the output budget (truncated_fits).
law truncate_fits:
  for +limits: TC.Limits
  for +state: TC.TraceState
  {Nat.is_le(TC.TraceState.size(TC.Truncation.kept(TC.TraceState.truncate(limits, state))),
    TC.Limits.tracestate_output(limits)) == True{} : Bool}

def truncate_fits(limits, state):
  +entries = TC.TraceState.entries(state)
  +budget = TC.Limits.tracestate_output(limits)
  %Equal.sym(List<&2, TC.StateEntry>, TC.TraceState.entries(TC.Truncation.kept(TC.TraceState.truncate(limits, state))),
    TC.Entries.truncate(List.length(&2, TC.StateEntry, entries), budget, entries), kept_entries(limits, state)) :
    {Nat.is_le(TC.Entries.size(_), budget) == True{} : Bool}
  truncated_fits(List.length(&2, TC.StateEntry, entries), entries, budget,
    NatsProof.le_refl(List.length(&2, TC.StateEntry, entries)))

# Law truncate_whole: a state that fits comes out of the loop unchanged
# (truncated_whole); the check gives back the state with its own evidence
# (UpdateProof.checked_state), and no key is dropped (dropped_prefix).
law truncate_whole:
  for +limits: TC.Limits
  for +state: TC.TraceState
  for fits: {Nat.is_le(TC.TraceState.size(state), TC.Limits.tracestate_output(limits)) == True{} : Bool}
  {TC.TraceState.truncate(limits, state) == TC.Truncation{state, Nil{}} : TC.Truncation}

def truncate_whole(limits, state, fits):
  match state:
    case TC.TraceState{+entries, +evidence}:
      +budget = TC.Limits.tracestate_output(limits)
      %Equal.sym(List<&2, TC.StateEntry>, TC.Entries.truncate(List.length(&2, TC.StateEntry, entries), budget, entries),
        entries, truncated_whole(entries, budget, fits)) :
        {TC.Truncation{TC.TraceState.from_entries(_, TC.TraceState.empty()), TC.Entries.dropped(entries, _)} ==
          TC.Truncation{TC.TraceState{entries, evidence}, Nil{}} : TC.Truncation}
      %Equal.sym(TC.TraceState, TC.TraceState.from_entries(entries, TC.TraceState.empty()), TC.TraceState{entries, evidence},
        UpdateProof.checked_state(entries, TC.TraceState.empty(), evidence)) :
        {TC.Truncation{_, TC.Entries.dropped(entries, entries)} == TC.Truncation{TC.TraceState{entries, evidence}, Nil{}} :
          TC.Truncation}
      %Equal.sym(List<&2, TC.StateKey>, TC.Entries.dropped(entries, entries), Nil{}, dropped_prefix(entries, Nil{})) :
        {TC.Truncation{TC.TraceState{entries, evidence}, _} == TC.Truncation{TC.TraceState{entries, evidence}, Nil{}} :
          TC.Truncation}
      {==}

# Law truncate_order: what the loop keeps is in order (truncated_order).
law truncate_order:
  for +limits: TC.Limits
  for +state: TC.TraceState
  {Laws.in_order(TC.TraceState.entries(state),
    TC.TraceState.entries(TC.Truncation.kept(TC.TraceState.truncate(limits, state)))) == True{} : Bool}

def truncate_order(limits, state):
  +entries = TC.TraceState.entries(state)
  +budget = TC.Limits.tracestate_output(limits)
  %Equal.sym(List<&2, TC.StateEntry>, TC.TraceState.entries(TC.Truncation.kept(TC.TraceState.truncate(limits, state))),
    TC.Entries.truncate(List.length(&2, TC.StateEntry, entries), budget, entries), kept_entries(limits, state)) :
    {Laws.in_order(entries, _) == True{} : Bool}
  truncated_order(List.length(&2, TC.StateEntry, entries), budget, entries)

# Law truncate_dropped: the keys reported are Entries.dropped of what the
# loop keeps, which are the keys of `missing` (dropped_missing).
law truncate_dropped:
  for +limits: TC.Limits
  for +state: TC.TraceState
  {TC.Truncation.dropped(TC.TraceState.truncate(limits, state)) ==
    Laws.keys(Laws.missing(TC.TraceState.entries(TC.Truncation.kept(TC.TraceState.truncate(limits, state))),
      TC.TraceState.entries(state))) : List<&2, TC.StateKey>}

def truncate_dropped(limits, state):
  +entries = TC.TraceState.entries(state)
  +kept = TC.Entries.truncate(List.length(&2, TC.StateEntry, entries), TC.Limits.tracestate_output(limits), entries)
  %Equal.sym(List<&2, TC.StateEntry>, TC.TraceState.entries(TC.Truncation.kept(TC.TraceState.truncate(limits, state))),
    kept, kept_entries(limits, state)) :
    {TC.Entries.dropped(entries, kept) == Laws.keys(Laws.missing(_, entries)) : List<&2, TC.StateKey>}
  dropped_missing(entries, kept)

# The procedure of spec #1
# ========================

# The package's Entries.format.rest and LAWS.bend's joined.rest write the
# same text. Induction on the entries.
law format_rest_joined:
  for entries: List<&2, TC.StateEntry>
  {TC.Entries.format.rest(entries) == Laws.joined.rest(entries) : String}

def format_rest_joined(entries):
  match entries:
    case Nil{}:
      {==}
    case Con{+entry, +rest}:
      %Equal.sym(String, TC.Entries.format.rest(rest), Laws.joined.rest(rest), format_rest_joined(rest)) :
        {"," ++ TC.StateEntry.format(entry) ++ _ == "," ++ TC.StateEntry.format(entry) ++ Laws.joined.rest(rest) :
          String}
      {==}

# The package's Entries.format and LAWS.bend's joined write the same text.
law format_joined:
  for entries: List<&2, TC.StateEntry>
  {TC.Entries.format(entries) == Laws.joined(entries) : String}

def format_joined(entries):
  match entries:
    case Nil{}:
      {==}
    case Con{+entry, +rest}:
      %Equal.sym(String, TC.Entries.format.rest(rest), Laws.joined.rest(rest), format_rest_joined(rest)) :
        {TC.StateEntry.format(entry) ++ _ == TC.StateEntry.format(entry) ++ Laws.joined.rest(rest) : String}
      {==}

# An entry is large by the package's size exactly when it is by the octets of
# its text (entry_size).
law large_law:
  for +entry: TC.StateEntry
  {TC.StateEntry.is_large(entry) == Laws.large(entry) : Bool}

def large_law(entry):
  %entry_size(entry) :
    {Nat.is_gt(TC.StateEntry.size(entry), 128n) == Nat.is_gt(_, 128n) : Bool}
  {==}

# The package's Entries.has_large and LAWS.bend's any_large agree. Induction
# on the entries, with large_law.
law has_large_law:
  for entries: List<&2, TC.StateEntry>
  {TC.Entries.has_large(entries) == Laws.any_large(entries) : Bool}

def has_large_law(entries):
  match entries:
    case Nil{}:
      {==}
    case Con{+entry, +rest}:
      %large_law(entry) : {Bool.or(TC.StateEntry.is_large(entry), TC.Entries.has_large(rest)) ==
        Bool.or(_, Laws.any_large(rest)) : Bool}
      %has_large_law(rest) : {Bool.or(TC.StateEntry.is_large(entry), TC.Entries.has_large(rest)) ==
        Bool.or(TC.StateEntry.is_large(entry), _) : Bool}
      {==}

# The package's Entries.drop_last_large and LAWS.bend's without_last_large
# remove the same entry. Induction on the entries, with has_large_law and
# large_law.
law drop_last_large_law:
  for entries: List<&2, TC.StateEntry>
  {TC.Entries.drop_last_large(entries) == Laws.without_last_large(entries) : List<&2, TC.StateEntry>}

def drop_last_large_law(entries):
  match entries:
    case Nil{}:
      {==}
    case Con{+entry, +rest}:
      %has_large_law(rest) :
        {Bool.pick(List<&2, TC.StateEntry>, TC.Entries.has_large(rest), Con{entry, TC.Entries.drop_last_large(rest)},
          Bool.pick(List<&2, TC.StateEntry>, TC.StateEntry.is_large(entry), rest, Con{entry, rest})) ==
          Bool.pick(List<&2, TC.StateEntry>, _, Con{entry, Laws.without_last_large(rest)},
            Bool.pick(List<&2, TC.StateEntry>, Laws.large(entry), rest, Con{entry, rest})) : List<&2, TC.StateEntry>}
      %large_law(entry) :
        {Bool.pick(List<&2, TC.StateEntry>, TC.Entries.has_large(rest), Con{entry, TC.Entries.drop_last_large(rest)},
          Bool.pick(List<&2, TC.StateEntry>, TC.StateEntry.is_large(entry), rest, Con{entry, rest})) ==
          Bool.pick(List<&2, TC.StateEntry>, TC.Entries.has_large(rest), Con{entry, Laws.without_last_large(rest)},
            Bool.pick(List<&2, TC.StateEntry>, _, rest, Con{entry, rest})) : List<&2, TC.StateEntry>}
      %drop_last_large_law(rest) :
        {Bool.pick(List<&2, TC.StateEntry>, TC.Entries.has_large(rest), Con{entry, TC.Entries.drop_last_large(rest)},
          Bool.pick(List<&2, TC.StateEntry>, TC.StateEntry.is_large(entry), rest, Con{entry, rest})) ==
          Bool.pick(List<&2, TC.StateEntry>, TC.Entries.has_large(rest), Con{entry, _},
            Bool.pick(List<&2, TC.StateEntry>, TC.StateEntry.is_large(entry), rest, Con{entry, rest})) :
          List<&2, TC.StateEntry>}
      {==}

# The package's Entries.drop_last and LAWS.bend's without_last remove the
# same entry. Induction on the entries.
law drop_last_law:
  for entries: List<&2, TC.StateEntry>
  {TC.Entries.drop_last(entries) == Laws.without_last(entries) : List<&2, TC.StateEntry>}

def drop_last_law(entries):
  match entries:
    case Nil{}:
      {==}
    case Con{+entry, +rest}:
      %drop_last_law(rest) :
        {Bool.pick(List<&2, TC.StateEntry>, List.is_empty(&2, TC.StateEntry, rest), Nil{},
          Con{entry, TC.Entries.drop_last(rest)}) ==
          Bool.pick(List<&2, TC.StateEntry>, List.is_empty(&2, TC.StateEntry, rest), Nil{}, Con{entry, _}) :
          List<&2, TC.StateEntry>}
      {==}

# One removal step of the package is one step of LAWS.bend's procedure.
law shrink_law:
  for +entries: List<&2, TC.StateEntry>
  {TC.Entries.shrink(entries) == Bool.pick(List<&2, TC.StateEntry>, Laws.any_large(entries),
    Laws.without_last_large(entries), Laws.without_last(entries)) : List<&2, TC.StateEntry>}

def shrink_law(entries):
  %has_large_law(entries) :
    {TC.Entries.shrink(entries) == Bool.pick(List<&2, TC.StateEntry>, _, Laws.without_last_large(entries),
      Laws.without_last(entries)) : List<&2, TC.StateEntry>}
  %drop_last_large_law(entries) :
    {TC.Entries.shrink(entries) == Bool.pick(List<&2, TC.StateEntry>, TC.Entries.has_large(entries), _,
      Laws.without_last(entries)) : List<&2, TC.StateEntry>}
  %drop_last_law(entries) :
    {TC.Entries.shrink(entries) == Bool.pick(List<&2, TC.StateEntry>, TC.Entries.has_large(entries),
      TC.Entries.drop_last_large(entries), _) : List<&2, TC.StateEntry>}
  {==}

# The package's loop is LAWS.bend's procedure, step for step: both measure
# the same octets (entries_size, format_joined) and take the same step
# (shrink_law). Induction on the fuel.
law truncated_law:
  for +fuel: Nat
  for +budget: Nat
  for +entries: List<&2, TC.StateEntry>
  {TC.Entries.truncate(fuel, budget, entries) == Laws.truncated(fuel, budget, entries) : List<&2, TC.StateEntry>}

def truncated_law(fuel, budget, entries):
  match fuel:
    case 0n:
      {==}
    case 1n+more:
      %Equal.sym(Nat, TC.Entries.size(entries), TC.Utf8.length(TC.Entries.format(entries)), entries_size(entries)) :
        {Bool.pick(List<&2, TC.StateEntry>, Nat.is_le(_, budget), entries,
          TC.Entries.truncate(more, budget, TC.Entries.shrink(entries))) == Laws.truncated(1n+more, budget, entries) :
          List<&2, TC.StateEntry>}
      %Equal.sym(String, TC.Entries.format(entries), Laws.joined(entries), format_joined(entries)) :
        {Bool.pick(List<&2, TC.StateEntry>, Nat.is_le(TC.Utf8.length(_), budget), entries,
          TC.Entries.truncate(more, budget, TC.Entries.shrink(entries))) == Laws.truncated(1n+more, budget, entries) :
          List<&2, TC.StateEntry>}
      %Equal.sym(List<&2, TC.StateEntry>, TC.Entries.truncate(more, budget, TC.Entries.shrink(entries)),
        Laws.truncated(more, budget, TC.Entries.shrink(entries)), truncated_law(more, budget, TC.Entries.shrink(entries))) :
        {Bool.pick(List<&2, TC.StateEntry>, Nat.is_le(TC.Utf8.length(Laws.joined(entries)), budget), entries, _) ==
          Laws.truncated(1n+more, budget, entries) : List<&2, TC.StateEntry>}
      %Equal.sym(List<&2, TC.StateEntry>, TC.Entries.shrink(entries), Bool.pick(List<&2, TC.StateEntry>,
          Laws.any_large(entries), Laws.without_last_large(entries), Laws.without_last(entries)), shrink_law(entries)) :
        {Bool.pick(List<&2, TC.StateEntry>, Nat.is_le(TC.Utf8.length(Laws.joined(entries)), budget), entries,
          Laws.truncated(more, budget, _)) == Laws.truncated(1n+more, budget, entries) : List<&2, TC.StateEntry>}
      {==}

# Law truncate_steps: the entries truncation keeps are those of the loop
# (kept_entries), which is LAWS.bend's procedure (truncated_law).
law truncate_steps:
  for +limits: TC.Limits
  for +state: TC.TraceState
  {TC.TraceState.entries(TC.Truncation.kept(TC.TraceState.truncate(limits, state))) ==
    Laws.truncated(List.length(&2, TC.StateEntry, TC.TraceState.entries(state)), TC.Limits.tracestate_output(limits),
      TC.TraceState.entries(state)) : List<&2, TC.StateEntry>}

def truncate_steps(limits, state):
  +entries = TC.TraceState.entries(state)
  +budget = TC.Limits.tracestate_output(limits)
  +fuel = List.length(&2, TC.StateEntry, entries)
  Equal.trans(List<&2, TC.StateEntry>, TC.TraceState.entries(TC.Truncation.kept(TC.TraceState.truncate(limits, state))),
    TC.Entries.truncate(fuel, budget, entries), Laws.truncated(fuel, budget, entries), kept_entries(limits, state),
    truncated_law(fuel, budget, entries))

# Emission
# ========

# Law emit_fits: the emitted tracestate is the normalized value of the
# truncated state, whose octets are its size (state_size), which fits
# (truncate_fits).
law emit_fits:
  for +limits: TC.Limits
  for +outgoing: TC.OutgoingContext
  {Nat.is_le(TC.Utf8.length(TC.Emission.tracestate(TC.OutgoingContext.emit(limits, outgoing))),
    TC.Limits.tracestate_output(limits)) == True{} : Bool}

def emit_fits(limits, outgoing):
  match outgoing:
    case TC.OutgoingContext{context, +state}:
      +kept = TC.Truncation.kept(TC.TraceState.truncate(limits, state))
      %state_size(kept) : {Nat.is_le(_, TC.Limits.tracestate_output(limits)) == True{} : Bool}
      truncate_fits(limits, state)

# Law emit_accepted: the emitted value fits the output budget (emit_fits),
# which fits the input budget (output_within_input, NatsProof.le_trans), so
# parsing it gives back the state (NormalProof.roundtrip).
law emit_accepted:
  for +limits: TC.Limits
  for +outgoing: TC.OutgoingContext
  {TC.TraceState.parse(limits, TC.Emission.tracestate(TC.OutgoingContext.emit(limits, outgoing))) ==
    Done{TC.Truncation.kept(TC.TraceState.truncate(limits, TC.OutgoingContext.state(outgoing)))} :
    Result<&2, &2, TC.StateError, TC.TraceState>}

def emit_accepted(limits, outgoing):
  match outgoing:
    case TC.OutgoingContext{+context, +state}:
      +kept = TC.Truncation.kept(TC.TraceState.truncate(limits, state))
      NormalProof.roundtrip(limits, kept,
        NatsProof.le_trans(TC.Utf8.length(TC.TraceState.format(kept)), TC.Limits.tracestate_output(limits),
          TC.Limits.tracestate_input(limits), emit_fits(limits, TC.OutgoingContext{context, state}), LimitsProof.output_within_input(limits)))
