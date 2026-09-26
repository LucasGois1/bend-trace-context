# Proofs: entries kept in order
# ==============================
#
# Facts about LAWS.bend's in_order(original, kept), which says that `kept` is
# `original` with some entries removed, in the same order. proofs/update.bend
# uses them for removal and prefixes (without_order, take_order), and
# proofs/emit.bend for truncation (truncated_order); both then read distinct
# keys, absent keys and lengths off the kept entries with order_distinct,
# order_among and order_length.
#
# in_order compares entries with LAWS.bend's same_entry, key and value texts
# alike, and matches greedily from the left, so every lemma is an induction
# on the original list with a case split on that comparison. Bend matches
# only on parameters, so each case split is a step lemma that receives the
# comparison's answer and its equation, and the induction hypotheses it
# needs as functions. same_self and same_left make comparisons agree;
# order_refl, order_skip, order_cons and order_extend build kept lists;
# order_tail and order_trans compose them; order_among, order_distinct and
# order_length read them.

import Base
import ../LAWS.bend as Laws
import ../trace_context.bend as TC
import ./strings.bend as StringsProof
import ./bools.bend as BoolsProof
import ./nats.bend as NatsProof

# Every entry is the same entry as itself: its key text and its value text
# are equal to themselves (StringsProof.eq_refl).
law same_self:
  for +entry: TC.StateEntry
  {Laws.same_entry(entry, entry) == True{} : Bool}

def same_self(entry):
  +key = TC.StateEntry.key_text(entry)
  +value = TC.StateValue.to_string(TC.StateEntry.value(entry))
  %Equal.sym(Bool, String.eq(key, key), True{}, StringsProof.eq_refl(key)) :
    {Bool.and(_, String.eq(value, value)) == True{} : Bool}
  %Equal.sym(Bool, String.eq(value, value), True{}, StringsProof.eq_refl(value)) :
    {Bool.and(True{}, _) == True{} : Bool}
  {==}

# When `a` is the same entry as `b`, comparing `a` or `b` with `c` gives the
# same answer: equal texts (StringsProof.eq_sound) compare alike. order_trans
# uses it to compare the middle list's entry for the outer ones.
law same_left:
  for +a: TC.StateEntry
  for +b: TC.StateEntry
  for +c: TC.StateEntry
  for +same: {Laws.same_entry(a, b) == True{} : Bool}
  {Laws.same_entry(a, c) == Laws.same_entry(b, c) : Bool}

def same_left(a, b, c, same):
  +ka = TC.StateEntry.key_text(a)
  +kb = TC.StateEntry.key_text(b)
  +kc = TC.StateEntry.key_text(c)
  +va = TC.StateValue.to_string(TC.StateEntry.value(a))
  +vb = TC.StateValue.to_string(TC.StateEntry.value(b))
  +vc = TC.StateValue.to_string(TC.StateEntry.value(c))
  +keys = StringsProof.eq_sound(ka, kb, BoolsProof.and_left(String.eq(ka, kb), String.eq(va, vb), same))
  +values = StringsProof.eq_sound(va, vb, BoolsProof.and_right(String.eq(ka, kb), String.eq(va, vb), same))
  %Equal.sym(String, ka, kb, keys) :
    {Bool.and(String.eq(_, kc), String.eq(va, vc)) == Bool.and(String.eq(kb, kc), String.eq(vb, vc)) : Bool}
  %Equal.sym(String, va, vb, values) :
    {Bool.and(String.eq(kb, kc), String.eq(_, vc)) == Bool.and(String.eq(kb, kc), String.eq(vb, vc)) : Bool}
  {==}

# A list keeps all of its own entries in order. Induction on the entries,
# with same_self at each one.
law order_refl:
  for entries: List<&2, TC.StateEntry>
  {Laws.in_order(entries, entries) == True{} : Bool}

def order_refl(entries):
  match entries:
    case Nil{}:
      {==}
    case Con{+entry, +rest}:
      %Equal.sym(Bool, Laws.same_entry(entry, entry), True{}, same_self(entry)) :
        {Bool.pick(Bool, _, Laws.in_order(rest, rest), Laws.in_order(rest, Con{entry, rest})) == True{} : Bool}
      order_refl(rest)

# Leaving out the first entry keeps the others in order. Induction on the
# rest, whichever branch in_order takes (pick_true).
law order_skip:
  for rest: List<&2, TC.StateEntry>
  for +entry: TC.StateEntry
  {Laws.in_order(Con{entry, rest}, rest) == True{} : Bool}

def order_skip(rest, entry):
  match rest:
    case Nil{}:
      {==}
    case Con{+next, +more}:
      BoolsProof.pick_true(Laws.same_entry(entry, next), Laws.in_order(Con{next, more}, more),
        Laws.in_order(Con{next, more}, Con{next, more}), order_skip(more, next), order_refl(Con{next, more}))

# Keeping the first entry and some of the rest in order keeps the rest's
# choice in order too.
law order_cons:
  for +entry: TC.StateEntry
  for +rest: List<&2, TC.StateEntry>
  for +kept: List<&2, TC.StateEntry>
  for order: {Laws.in_order(rest, kept) == True{} : Bool}
  {Laws.in_order(Con{entry, rest}, Con{entry, kept}) == True{} : Bool}

def order_cons(entry, rest, kept, order):
  %Equal.sym(Bool, Laws.same_entry(entry, entry), True{}, same_self(entry)) :
    {Bool.pick(Bool, _, Laws.in_order(rest, kept), Laws.in_order(rest, Con{entry, kept})) == True{} : Bool}
  order

# The step of order_tail: whichever branch in_order took for the first kept
# entry, the rest of the original keeps the later ones in order. `later`
# is order_tail for the rest of the original.
law tail_known:
  for +rest: List<&2, TC.StateEntry>
  for -first: TC.StateEntry
  for -next: TC.StateEntry
  for -more: List<&2, TC.StateEntry>
  for same: Bool
  for order: {Bool.pick(Bool, same, Laws.in_order(rest, Con{next, more}),
    Laws.in_order(rest, Con{first, Con{next, more}})) == True{} : Bool}
  for later: {Laws.in_order(rest, Con{first, Con{next, more}}) == True{} : Bool} ->
    {Laws.in_order(rest, Con{next, more}) == True{} : Bool}
  {Laws.in_order(rest, Con{next, more}) == True{} : Bool}

def tail_known(rest, first, next, more, same, order, later):
  match same:
    case True{}:
      order
    case False{}:
      later(order)

# Leaving out the first kept entry keeps the other kept entries in order.
# Induction on the original, with tail_known.
law order_tail:
  for original: List<&2, TC.StateEntry>
  for kept: List<&2, TC.StateEntry>
  for +first: TC.StateEntry
  for order: {Laws.in_order(original, Con{first, kept}) == True{} : Bool}
  {Laws.in_order(original, kept) == True{} : Bool}

def order_tail(original, kept, first, order):
  match original kept:
    case Nil{} _:
      BoolsProof.absurd({Laws.in_order(Nil{}, kept) == True{} : Bool}, order)
    case Con{candidate, rest} Nil{}:
      {==}
    case Con{+candidate, +rest} Con{+next, +more}:
      +known = tail_known(rest, first, next, more, Laws.same_entry(candidate, first), order,
        found => order_tail(rest, Con{next, more}, first, found))
      BoolsProof.pick_true(Laws.same_entry(candidate, next), Laws.in_order(rest, more), Laws.in_order(rest, Con{next, more}),
        order_tail(rest, more, next, known), known)

# The step of order_trans for three nonempty lists: `a`, `b` and `c` are
# their first entries and `ab`, `bc` and `ac` the answers of comparing them.
# When `a` matches `b`, comparing `a` or `b` with `c` agrees (same_left), so
# the cases where they disagree are refuted; the others follow from the
# three instances of the induction hypothesis `left`, `right` and `skip`,
# and from order_tail.
law trans_step:
  for +a: TC.StateEntry
  for +rest_a: List<&2, TC.StateEntry>
  for +b: TC.StateEntry
  for +rest_b: List<&2, TC.StateEntry>
  for +c: TC.StateEntry
  for +rest_c: List<&2, TC.StateEntry>
  for ab: Bool
  for ab_is: {Laws.same_entry(a, b) == ab : Bool}
  for bc: Bool
  for bc_is: {Laws.same_entry(b, c) == bc : Bool}
  for ac: Bool
  for ac_is: {Laws.same_entry(a, c) == ac : Bool}
  for first: {Bool.pick(Bool, ab, Laws.in_order(rest_a, rest_b), Laws.in_order(rest_a, Con{b, rest_b})) ==
    True{} : Bool}
  for second: {Bool.pick(Bool, bc, Laws.in_order(rest_b, rest_c), Laws.in_order(rest_b, Con{c, rest_c})) ==
    True{} : Bool}
  for whole: {Laws.in_order(Con{b, rest_b}, Con{c, rest_c}) == True{} : Bool}
  for left: {Laws.in_order(rest_a, rest_b) == True{} : Bool} -> {Laws.in_order(rest_b, rest_c) == True{} : Bool} ->
    {Laws.in_order(rest_a, rest_c) == True{} : Bool}
  for right: {Laws.in_order(rest_a, rest_b) == True{} : Bool} ->
    {Laws.in_order(rest_b, Con{c, rest_c}) == True{} : Bool} -> {Laws.in_order(rest_a, Con{c, rest_c}) == True{} : Bool}
  for skip: {Laws.in_order(rest_a, Con{b, rest_b}) == True{} : Bool} ->
    {Laws.in_order(Con{b, rest_b}, Con{c, rest_c}) == True{} : Bool} ->
    {Laws.in_order(rest_a, Con{c, rest_c}) == True{} : Bool}
  {Bool.pick(Bool, ac, Laws.in_order(rest_a, rest_c), Laws.in_order(rest_a, Con{c, rest_c})) == True{} : Bool}

def trans_step(a, rest_a, b, rest_b, c, rest_c, ab, ab_is, bc, bc_is, ac, ac_is, first, second, whole, left, right,
  skip):
  match ab bc ac:
    case True{} True{} True{}:
      left(first, second)
    case True{} True{} False{}:
      BoolsProof.absurd({Laws.in_order(rest_a, Con{c, rest_c}) == True{} : Bool},
        Equal.trans(Bool, False{}, Laws.same_entry(a, c), True{}, Equal.sym(Bool, Laws.same_entry(a, c), False{}, ac_is),
          Equal.trans(Bool, Laws.same_entry(a, c), Laws.same_entry(b, c), True{}, same_left(a, b, c, ab_is), bc_is)))
    case True{} False{} True{}:
      Empty.absurd({Laws.in_order(rest_a, rest_c) == True{} : Bool},
        BoolsProof.true_ne_false(Equal.trans(Bool, True{}, Laws.same_entry(a, c), False{},
          Equal.sym(Bool, Laws.same_entry(a, c), True{}, ac_is),
          Equal.trans(Bool, Laws.same_entry(a, c), Laws.same_entry(b, c), False{}, same_left(a, b, c, ab_is), bc_is))))
    case True{} False{} False{}:
      right(first, second)
    case False{} _ True{}:
      order_tail(rest_a, rest_c, c, skip(first, whole))
    case False{} _ False{}:
      skip(first, whole)

# in_order is transitive: when `middle` keeps some of `original` in order
# and `kept` keeps some of `middle`, then `kept` keeps some of `original`.
# Induction on the original; the three lists' first entries are compared by
# trans_step. truncated_order chains the removal steps with it.
law order_trans:
  for original: List<&2, TC.StateEntry>
  for middle: List<&2, TC.StateEntry>
  for kept: List<&2, TC.StateEntry>
  for first: {Laws.in_order(original, middle) == True{} : Bool}
  for +second: {Laws.in_order(middle, kept) == True{} : Bool}
  {Laws.in_order(original, kept) == True{} : Bool}

def order_trans(original, middle, kept, first, second):
  match original middle kept:
    case Nil{} Nil{} _:
      second
    case Nil{} Con{b, rest_b} _:
      BoolsProof.absurd({Laws.in_order(Nil{}, kept) == True{} : Bool}, first)
    case Con{a, rest_a} _ Nil{}:
      {==}
    case Con{a, rest_a} Nil{} Con{c, rest_c}:
      BoolsProof.absurd({Laws.in_order(Con{a, rest_a}, Con{c, rest_c}) == True{} : Bool}, second)
    case Con{+a, +rest_a} Con{+b, +rest_b} Con{+c, +rest_c}:
      trans_step(a, rest_a, b, rest_b, c, rest_c, Laws.same_entry(a, b), {==}, Laws.same_entry(b, c), {==},
        Laws.same_entry(a, c), {==}, first, second, second,
        p => q => order_trans(rest_a, rest_b, rest_c, p, q),
        p => q => order_trans(rest_a, rest_b, Con{c, rest_c}, p, q),
        p => q => order_trans(rest_a, Con{b, rest_b}, Con{c, rest_c}, p, q))

# The step of order_among for two nonempty lists: when the first entries are
# the same entry, they share the key, which is not `key`; otherwise the kept
# list is kept by the original's rest.
law among_step:
  for +key: String
  for +entry: TC.StateEntry
  for +rest: List<&2, TC.StateEntry>
  for +next: TC.StateEntry
  for +more: List<&2, TC.StateEntry>
  for same: Bool
  for same_is: {Laws.same_entry(entry, next) == same : Bool}
  for order: {Bool.pick(Bool, same, Laws.in_order(rest, more), Laws.in_order(rest, Con{next, more})) == True{} :
    Bool}
  for here: {String.eq(key, TC.StateEntry.key_text(entry)) == False{} : Bool}
  for kept: {Laws.in_order(rest, more) == True{} : Bool} -> {Laws.key_among(key, more) == False{} : Bool}
  for skipped: {Laws.in_order(rest, Con{next, more}) == True{} : Bool} ->
    {Laws.key_among(key, Con{next, more}) == False{} : Bool}
  {Laws.key_among(key, Con{next, more}) == False{} : Bool}

def among_step(key, entry, rest, next, more, same, same_is, order, here, kept, skipped):
  match same:
    case True{}:
      +keys = StringsProof.eq_sound(TC.StateEntry.key_text(entry), TC.StateEntry.key_text(next),
        BoolsProof.and_left(String.eq(TC.StateEntry.key_text(entry), TC.StateEntry.key_text(next)),
          String.eq(TC.StateValue.to_string(TC.StateEntry.value(entry)), TC.StateValue.to_string(TC.StateEntry.value(next))),
          same_is))
      %keys : {Bool.or(String.eq(key, _), Laws.key_among(key, more)) == False{} : Bool}
      %Equal.sym(Bool, String.eq(key, TC.StateEntry.key_text(entry)), False{}, here) :
        {Bool.or(_, Laws.key_among(key, more)) == False{} : Bool}
      kept(order)
    case False{}:
      skipped(order)

# Keeping entries in order adds no key: a key that no entry of the original
# has is not among the kept entries. Induction on the original, with
# among_step. order_distinct uses it.
law order_among:
  for original: List<&2, TC.StateEntry>
  for kept: List<&2, TC.StateEntry>
  for +key: String
  for order: {Laws.in_order(original, kept) == True{} : Bool}
  for +absent: {Laws.key_among(key, original) == False{} : Bool}
  {Laws.key_among(key, kept) == False{} : Bool}

def order_among(original, kept, key, order, absent):
  match original kept:
    case Nil{} Nil{}:
      {==}
    case Nil{} Con{next, more}:
      BoolsProof.absurd({Laws.key_among(key, Con{next, more}) == False{} : Bool}, order)
    case Con{entry, rest} Nil{}:
      {==}
    case Con{+entry, +rest} Con{+next, +more}:
      +here = BoolsProof.or_left_false(String.eq(key, TC.StateEntry.key_text(entry)), Laws.key_among(key, rest), absent)
      +later = BoolsProof.or_right_false(String.eq(key, TC.StateEntry.key_text(entry)), Laws.key_among(key, rest),
        absent)
      among_step(key, entry, rest, next, more, Laws.same_entry(entry, next), {==}, order, here,
        found => order_among(rest, more, key, found, later),
        found => order_among(rest, Con{next, more}, key, found, later))

# The step of order_distinct for two nonempty lists, as among_step: the
# first kept entry either is the original's first entry, whose key no later
# entry of the original has, or comes from the original's rest.
law distinct_step:
  for +entry: TC.StateEntry
  for +rest: List<&2, TC.StateEntry>
  for +next: TC.StateEntry
  for +more: List<&2, TC.StateEntry>
  for same: Bool
  for same_is: {Laws.same_entry(entry, next) == same : Bool}
  for +order: {Bool.pick(Bool, same, Laws.in_order(rest, more), Laws.in_order(rest, Con{next, more})) == True{} :
    Bool}
  for fresh: {Laws.key_among(TC.StateEntry.key_text(entry), rest) == False{} : Bool}
  for kept: {Laws.in_order(rest, more) == True{} : Bool} -> {Laws.keys_distinct(more) == True{} : Bool}
  for skipped: {Laws.in_order(rest, Con{next, more}) == True{} : Bool} ->
    {Laws.keys_distinct(Con{next, more}) == True{} : Bool}
  {Laws.keys_distinct(Con{next, more}) == True{} : Bool}

def distinct_step(entry, rest, next, more, same, same_is, order, fresh, kept, skipped):
  match same:
    case True{}:
      +keys = StringsProof.eq_sound(TC.StateEntry.key_text(entry), TC.StateEntry.key_text(next),
        BoolsProof.and_left(String.eq(TC.StateEntry.key_text(entry), TC.StateEntry.key_text(next)),
          String.eq(TC.StateValue.to_string(TC.StateEntry.value(entry)), TC.StateValue.to_string(TC.StateEntry.value(next))),
          same_is))
      %keys : {Bool.and(Bool.not(Laws.key_among(_, more)), Laws.keys_distinct(more)) == True{} : Bool}
      %Equal.sym(Bool, Laws.key_among(TC.StateEntry.key_text(entry), more), False{},
        order_among(rest, more, TC.StateEntry.key_text(entry), order, fresh)) :
        {Bool.and(Bool.not(_), Laws.keys_distinct(more)) == True{} : Bool}
      kept(order)
    case False{}:
      skipped(order)

# Entries kept in order from a list with distinct keys have distinct keys.
# Induction on the original, with distinct_step. The truncated state passes
# the package's check through it.
law order_distinct:
  for original: List<&2, TC.StateEntry>
  for kept: List<&2, TC.StateEntry>
  for order: {Laws.in_order(original, kept) == True{} : Bool}
  for +distinct: {Laws.keys_distinct(original) == True{} : Bool}
  {Laws.keys_distinct(kept) == True{} : Bool}

def order_distinct(original, kept, order, distinct):
  match original kept:
    case Nil{} Nil{}:
      {==}
    case Nil{} Con{next, more}:
      BoolsProof.absurd({Laws.keys_distinct(Con{next, more}) == True{} : Bool}, order)
    case Con{entry, rest} Nil{}:
      {==}
    case Con{+entry, +rest} Con{+next, +more}:
      +fresh = BoolsProof.not_true(Laws.key_among(TC.StateEntry.key_text(entry), rest),
        BoolsProof.and_left(Bool.not(Laws.key_among(TC.StateEntry.key_text(entry), rest)), Laws.keys_distinct(rest),
          distinct))
      +later = BoolsProof.and_right(Bool.not(Laws.key_among(TC.StateEntry.key_text(entry), rest)),
        Laws.keys_distinct(rest), distinct)
      distinct_step(entry, rest, next, more, Laws.same_entry(entry, next), {==}, order, fresh,
        found => order_distinct(rest, more, found, later),
        found => order_distinct(rest, Con{next, more}, found, later))

# The step of order_length for two nonempty lists: the kept rest is at most
# the original's rest either way; when the first kept entry comes from the
# original's rest, NatsProof.le_drop takes the extra one off.
law length_step:
  for -entry: TC.StateEntry
  for +rest: List<&2, TC.StateEntry>
  for -next: TC.StateEntry
  for +more: List<&2, TC.StateEntry>
  for same: Bool
  for order: {Bool.pick(Bool, same, Laws.in_order(rest, more), Laws.in_order(rest, Con{next, more})) == True{} :
    Bool}
  for kept: {Laws.in_order(rest, more) == True{} : Bool} ->
    {Nat.is_le(List.length(&2, TC.StateEntry, more), List.length(&2, TC.StateEntry, rest)) == True{} : Bool}
  for skipped: {Laws.in_order(rest, Con{next, more}) == True{} : Bool} ->
    {Nat.is_le(1n+List.length(&2, TC.StateEntry, more), List.length(&2, TC.StateEntry, rest)) == True{} : Bool}
  {Nat.is_le(List.length(&2, TC.StateEntry, more), List.length(&2, TC.StateEntry, rest)) == True{} : Bool}

def length_step(entry, rest, next, more, same, order, kept, skipped):
  match same:
    case True{}:
      kept(order)
    case False{}:
      NatsProof.le_drop(List.length(&2, TC.StateEntry, more), List.length(&2, TC.StateEntry, rest), skipped(order))

# Entries kept in order are at most as many as the original's. Induction on
# the original, with length_step.
law order_length:
  for original: List<&2, TC.StateEntry>
  for kept: List<&2, TC.StateEntry>
  for order: {Laws.in_order(original, kept) == True{} : Bool}
  {Nat.is_le(List.length(&2, TC.StateEntry, kept), List.length(&2, TC.StateEntry, original)) == True{} : Bool}

def order_length(original, kept, order):
  match original kept:
    case Nil{} Nil{}:
      {==}
    case Nil{} Con{next, more}:
      BoolsProof.absurd({Nat.is_le(1n+List.length(&2, TC.StateEntry, more), 0n) == True{} : Bool}, order)
    case Con{entry, rest} Nil{}:
      {==}
    case Con{+entry, +rest} Con{+next, +more}:
      length_step(entry, rest, next, more, Laws.same_entry(entry, next), order,
        found => order_length(rest, more, found),
        found => order_length(rest, Con{next, more}, found))

# Adding an entry in front of the original keeps what was kept in order
# (order_skip and order_trans). proofs/update.bend's without_order uses it
# for an entry that removal takes out.
law order_extend:
  for +entry: TC.StateEntry
  for +rest: List<&2, TC.StateEntry>
  for kept: List<&2, TC.StateEntry>
  for order: {Laws.in_order(rest, kept) == True{} : Bool}
  {Laws.in_order(Con{entry, rest}, kept) == True{} : Bool}

def order_extend(entry, rest, kept, order):
  order_trans(Con{entry, rest}, rest, kept, order_skip(rest, entry), order)
