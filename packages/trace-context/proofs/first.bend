import Base
import ../LAWS.bend as Laws
import ../trace_context.bend as TC
import ./bools.bend as BoolsProof
import ./lists.bend as ListsProof
import ./tracestate.bend as StateProof
import ./distinct.bend as DistinctProof
import ./merge.bend as MergeProof

# Naturals
# --------

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

# The members a state's entries leave for those after them.
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
# ----

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

law or_false:
  for a: Bool
  {Bool.or(a, False{}) == a : Bool}

def or_false(a):
  match a:
    case False{}:
      {==}
    case True{}:
      {==}

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
      or_assoc(String.eq(TC.StateEntry.key_text(entry), key), TC.Entries.has_key(rest, key),
        TC.Entries.has_key(after, key))

# What the second state's entries leave
# -------------------------------------

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

law missing_snoc:
  for +earlier: List<&2, TC.StateEntry>
  for seen: List<&2, TC.StateEntry>
  for +entry: TC.StateEntry
  {Laws.missing(earlier, List.append(&2, TC.StateEntry, seen, Con{entry, Nil{}})) ==
    List.append(&2, TC.StateEntry, Laws.missing(earlier, seen),
      Bool.pick(List<&2, TC.StateEntry>, Laws.key_among(TC.StateEntry.key_text(entry), earlier), Nil{},
        Con{entry, Nil{}})) : List<&2, TC.StateEntry>}

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

# A key no entry of the seen list has is not among the entries it leaves.
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
# first state's keys: none of the second state's entries kept so far has the
# key of a later one.
law machine_key:
  for +earlier: List<&2, TC.StateEntry>
  for +seen: List<&2, TC.StateEntry>
  for +entries: List<&2, TC.StateEntry>
  for split: {entries == List.append(&2, TC.StateEntry, earlier, Laws.missing(earlier, seen)) : List<&2, TC.StateEntry>}
  for +key: String
  for +fresh: {TC.Entries.has_key(seen, key) == False{} : Bool}
  {TC.Entries.has_key(entries, key) == Laws.key_among(key, earlier) : Bool}

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
    or_false(TC.Entries.has_key(earlier, key))) :
    {_ == Laws.key_among(key, earlier) : Bool}
  DistinctProof.has_key_among(earlier, key)

# One more entry of the second state, dropped or kept as the first state's
# keys decide, keeps each invariant of the scan.
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
      le_drop(Nat.add(List.length(&2, TC.StateEntry, entries), rest), 32n,
        %add_succ(List.length(&2, TC.StateEntry, entries), rest) : {Nat.is_le(_, 32n) == True{} : Bool}
        count)
    case False{}:
      %Equal.sym(Bool, TC.Entries.has_key(entries, TC.StateEntry.key_text(entry)), False{}, machine) :
        {Nat.is_le(Nat.add(List.length(&2, TC.StateEntry, TC.Entries.add.if(entries, entry, _)), rest), 32n) == True{} :
          Bool}
      %Equal.sym(Nat, List.length(&2, TC.StateEntry, List.append(&2, TC.StateEntry, entries, Con{entry, Nil{}})),
        1n+List.length(&2, TC.StateEntry, entries), ListsProof.length_snoc(TC.StateEntry, entries, entry)) :
        {Nat.is_le(Nat.add(_, rest), 32n) == True{} : Bool}
      %add_succ(List.length(&2, TC.StateEntry, entries), rest) : {Nat.is_le(_, 32n) == True{} : Bool}
      count

# Reading the rest of the second state
# ------------------------------------

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
            %add_zero(List.length(&2, TC.StateEntry, kept)) : {Nat.is_le(_, 32n) == True{} : Bool}
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

# Two states' values joined by a comma: the first state's entries, then the
# second's entries whose keys the first lacks, in order.
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
