# Proofs: a state's value followed by one entry
# =============================================
#
# What TraceState.parse makes of a state's normalized value followed by a
# comma and one more entry: a repeated key is dropped (later_duplicate), a
# new key is added last (later_new_key), and a 33rd member is refused
# (full_state). PROOF.bend proves those laws of LAWS.bend with the lemmas of
# the same names. The lemmas about the reading machine are shared:
# proofs/normal.bend uses parse_scan for ows_around, and proofs/first.bend
# uses parse_scan, read_state_then, after, opened and unique_snoc for
# first_wins.
#
# The proofs rewrite parsing into the steps of the reading machine of
# trace_context.bend. parse_scan removes the budget check. read_state_then
# shows that the state's entries all end before the text after the comma is
# read; its induction, read_closed, closes the pending entry at each comma
# and reads the next one, while after and members_after track the room and
# the member number. scan_state_entry leaves the extra entry pending, and
# the end of the text closes it: keep_present, keep_new or the exhausted
# room decides the result. When parsing succeeds, Scan.result checks
# TraceState.is_valid to build the parsed state, and
# StateProof.checked_valid shows that it is the expected state with its own
# evidence; valid_snoc proves the evidence of the longer state.

import Base
import ../trace_context.bend as TC
import ./strings.bend as StringsProof
import ./bools.bend as BoolsProof
import ./lists.bend as ListsProof
import ./nats.bend as NatsProof
import ./tracestate.bend as StateProof

# How many nonempty members remain allowed after `count` more, from `room`:
# `room` minus `count`, or 0 when `count` is larger. Scan.keep takes one from
# the room for each valid member, so after a state's n entries a scan that
# started with 32 has after(n, 32) left. proofs/first.bend uses it too.
def after(count: Nat, room: Nat) -> Nat:
  match count:
    case 0n:
      room
    case 1n+more:
      match room:
        case 0n:
          0n
        case 1n+left:
          after(more, left)

# The member number after `count` more members: `member` plus `count`, added
# one at a time, as the recursive call of read_closed passes 1n+member.
def members_after(count: Nat, member: Nat) -> Nat:
  match count:
    case 0n:
      member
    case 1n+more:
      members_after(more, 1n+member)

# When the scan is in the value of `current`, its key and reversed value
# pending, reading the rest of a formatted state (each entry of `rest` after
# its comma) and then a comma closes `current` and each entry of `rest`,
# adding them after `entries`: `unique` says each key is new, and `fits`
# that there is room for all. The scan is left blank before `next`, with the
# member number advanced and the room reduced by one per entry. Induction
# on `rest`; read_state_then starts it after a state's first entry.
law read_closed:
  for rest: List<&2, TC.StateEntry>
  for +current: TC.StateEntry
  for +member: Nat
  for +allowed: Nat
  for +entries: List<&2, TC.StateEntry>
  for +next: String
  for +unique: {TC.Entries.unique(Con{current, rest}, entries) == True{} : Bool}
  for fits: {Nat.is_le(List.length(&2, TC.StateEntry, Con{current, rest}), allowed) == True{} : Bool}
  {TC.Scan.text(TC.Entries.format.rest(rest) ++ "," ++ next, TC.Scanning{member, allowed,
      TC.InValue{TC.StateEntry.key_text(current), String.reverse(TC.StateValue.to_string(TC.StateEntry.value(current)))},
      entries}) ==
    TC.Scan.text(next, TC.Scanning{members_after(List.length(&2, TC.StateEntry, Con{current, rest}), member),
      after(List.length(&2, TC.StateEntry, Con{current, rest}), allowed), TC.Blank{},
      List.append(&2, TC.StateEntry, entries, Con{current, rest})}) : TC.Scan}

def read_closed(rest, current, member, allowed, entries, next, unique, fits):
  match rest:
    case Nil{}:
      match allowed:
        case 0n:
          BoolsProof.absurd({TC.Scan.text(TC.Entries.format.rest(Nil{}) ++ "," ++ next, TC.Scanning{member, 0n,
              TC.InValue{TC.StateEntry.key_text(current),
                String.reverse(TC.StateValue.to_string(TC.StateEntry.value(current)))}, entries}) ==
            TC.Scan.text(next, TC.Scanning{members_after(1n, member), after(1n, 0n), TC.Blank{},
              List.append(&2, TC.StateEntry, entries, Con{current, Nil{}})}) : TC.Scan}, fits)
        case 1n+left:
          +absent = BoolsProof.not_true(TC.Entries.has_key(entries, TC.StateEntry.key_text(current)),
            BoolsProof.and_left(Bool.not(TC.Entries.has_key(entries, TC.StateEntry.key_text(current))),
              TC.Entries.unique(Nil{}, List.append(&2, TC.StateEntry, entries, Con{current, Nil{}})), unique))
          %Equal.sym(TC.Scan, TC.Scan.close(member, 1n+left, TC.InValue{TC.StateEntry.key_text(current),
              String.reverse(TC.StateValue.to_string(TC.StateEntry.value(current)))}, entries),
            TC.Scanning{1n+member, left, TC.Blank{}, List.append(&2, TC.StateEntry, entries, Con{current, Nil{}})},
            StateProof.close_entry(current, member, left, entries, absent)) :
            {TC.Scan.text(next, _) == TC.Scan.text(next, TC.Scanning{1n+member, left, TC.Blank{},
              List.append(&2, TC.StateEntry, entries, Con{current, Nil{}})}) : TC.Scan}
          {==}
    case Con{+later_first, +later}:
      match allowed:
        case 0n:
          BoolsProof.absurd({TC.Scan.text(TC.Entries.format.rest(Con{later_first, later}) ++ "," ++ next,
              TC.Scanning{member, 0n, TC.InValue{TC.StateEntry.key_text(current),
                String.reverse(TC.StateValue.to_string(TC.StateEntry.value(current)))}, entries}) ==
            TC.Scan.text(next, TC.Scanning{members_after(List.length(&2, TC.StateEntry,
                Con{current, Con{later_first, later}}), member),
              after(List.length(&2, TC.StateEntry, Con{current, Con{later_first, later}}), 0n), TC.Blank{},
              List.append(&2, TC.StateEntry, entries, Con{current, Con{later_first, later}})}) : TC.Scan}, fits)
        case 1n+left:
          +absent = BoolsProof.not_true(TC.Entries.has_key(entries, TC.StateEntry.key_text(current)),
            BoolsProof.and_left(Bool.not(TC.Entries.has_key(entries, TC.StateEntry.key_text(current))),
              TC.Entries.unique(Con{later_first, later}, List.append(&2, TC.StateEntry, entries, Con{current, Nil{}})),
              unique))
          +added = {List.append(&2, TC.StateEntry, entries, Con{current, Nil{}}) : List<&2, TC.StateEntry>}
          +target = {TC.Scan.text(next, TC.Scanning{members_after(List.length(&2, TC.StateEntry,
              Con{current, Con{later_first, later}}), member),
            after(List.length(&2, TC.StateEntry, Con{current, Con{later_first, later}}), 1n+left), TC.Blank{},
            List.append(&2, TC.StateEntry, entries, Con{current, Con{later_first, later}})}) : TC.Scan}
          %Equal.sym(TC.Scan, TC.Scan.close(member, 1n+left, TC.InValue{TC.StateEntry.key_text(current),
              String.reverse(TC.StateValue.to_string(TC.StateEntry.value(current)))}, entries),
            TC.Scanning{1n+member, left, TC.Blank{}, added},
            StateProof.close_entry(current, member, left, entries, absent)) :
            {TC.Scan.text((TC.StateEntry.format(later_first) ++ TC.Entries.format.rest(later)) ++ "," ++ next, _) ==
              target : TC.Scan}
          %Equal.sym(String, (TC.StateEntry.format(later_first) ++ TC.Entries.format.rest(later)) ++ "," ++ next,
            TC.StateEntry.format(later_first) ++ TC.Entries.format.rest(later) ++ "," ++ next,
            StringsProof.string_assoc(TC.StateEntry.format(later_first), TC.Entries.format.rest(later), "," ++ next)) :
            {TC.Scan.text(_, TC.Scanning{1n+member, left, TC.Blank{}, added}) == target : TC.Scan}
          %Equal.sym(TC.Scan,
            TC.Scan.text(TC.StateEntry.format(later_first) ++ TC.Entries.format.rest(later) ++ "," ++ next,
              TC.Scanning{1n+member, left, TC.Blank{}, added}),
            TC.Scan.text(TC.Entries.format.rest(later) ++ "," ++ next,
              TC.Scan.text(TC.StateEntry.format(later_first), TC.Scanning{1n+member, left, TC.Blank{}, added})),
            StateProof.scan_append(TC.StateEntry.format(later_first), TC.Entries.format.rest(later) ++ "," ++ next,
              TC.Scanning{1n+member, left, TC.Blank{}, added})) :
            {_ == target : TC.Scan}
          %Equal.sym(TC.Scan,
            TC.Scan.text(TC.StateEntry.format(later_first), TC.Scanning{1n+member, left, TC.Blank{}, added}),
            TC.Scanning{1n+member, left, TC.InValue{TC.StateEntry.key_text(later_first),
              String.reverse(TC.StateValue.to_string(TC.StateEntry.value(later_first)))}, added},
            StateProof.read_entry(later_first, 1n+member, left, added)) :
            {TC.Scan.text(TC.Entries.format.rest(later) ++ "," ++ next, _) == target : TC.Scan}
          %ListsProof.append_assoc(TC.StateEntry, entries, Con{current, Nil{}}, Con{later_first, later}) :
            {TC.Scan.text(TC.Entries.format.rest(later) ++ "," ++ next, TC.Scanning{1n+member, left,
              TC.InValue{TC.StateEntry.key_text(later_first),
                String.reverse(TC.StateValue.to_string(TC.StateEntry.value(later_first)))}, added}) ==
              TC.Scan.text(next, TC.Scanning{members_after(List.length(&2, TC.StateEntry, Con{later_first, later}),
                1n+member), after(List.length(&2, TC.StateEntry, Con{later_first, later}), left), TC.Blank{}, _}) :
              TC.Scan}
          read_closed(later, later_first, 1n+member, left, added, next,
            BoolsProof.and_right(Bool.not(TC.Entries.has_key(entries, TC.StateEntry.key_text(current))),
              TC.Entries.unique(Con{later_first, later}, added), unique),
            fits)

# The member number after a state's members and the comma that follows
# them: one per entry, or 1 for the empty state, whose value "" is itself an
# empty member. proofs/first.bend uses it too.
def opened(entries: List<&2, TC.StateEntry>) -> Nat:
  match entries:
    case Nil{}:
      1n
    case Con{first, rest}:
      members_after(List.length(&2, TC.StateEntry, Con{first, rest}), 0n)

# Reading a valid state's value and a comma from the start of a scan ends
# all of the state's entries before the text after the comma is read: the
# scan is then blank, at member number opened(entries), with every entry
# kept in order and after(n, 32) members still allowed for n entries.
# `evidence` gives read_closed its distinct keys and room. scan_state_entry
# uses it, and so does proofs/first.bend for first_wins, where `next` is the
# second state's value.
law read_state_then:
  for +entries: List<&2, TC.StateEntry>
  for +evidence: {TC.TraceState.is_valid(entries) == True{} : Bool}
  for +next: String
  {TC.Scan.text(TC.Entries.format(entries) ++ "," ++ next, TC.Scan.start()) ==
    TC.Scan.text(next, TC.Scanning{opened(entries), after(List.length(&2, TC.StateEntry, entries), 32n), TC.Blank{},
      entries}) : TC.Scan}

def read_state_then(entries, evidence, next):
  match entries:
    case Nil{}:
      {==}
    case Con{+first, +rest}:
      +target = {TC.Scan.text(next, TC.Scanning{opened(Con{first, rest}),
        after(List.length(&2, TC.StateEntry, Con{first, rest}), 32n), TC.Blank{}, Con{first, rest}}) : TC.Scan}
      %Equal.sym(String, (TC.StateEntry.format(first) ++ TC.Entries.format.rest(rest)) ++ "," ++ next,
        TC.StateEntry.format(first) ++ TC.Entries.format.rest(rest) ++ "," ++ next,
        StringsProof.string_assoc(TC.StateEntry.format(first), TC.Entries.format.rest(rest), "," ++ next)) :
        {TC.Scan.text(_, TC.Scan.start()) == target : TC.Scan}
      %Equal.sym(TC.Scan,
        TC.Scan.text(TC.StateEntry.format(first) ++ TC.Entries.format.rest(rest) ++ "," ++ next, TC.Scan.start()),
        TC.Scan.text(TC.Entries.format.rest(rest) ++ "," ++ next,
          TC.Scan.text(TC.StateEntry.format(first), TC.Scan.start())),
        StateProof.scan_append(TC.StateEntry.format(first), TC.Entries.format.rest(rest) ++ "," ++ next,
          TC.Scan.start())) :
        {_ == target : TC.Scan}
      %Equal.sym(TC.Scan, TC.Scan.text(TC.StateEntry.format(first), TC.Scanning{0n, 32n, TC.Blank{}, Nil{}}),
        TC.Scanning{0n, 32n, TC.InValue{TC.StateEntry.key_text(first),
          String.reverse(TC.StateValue.to_string(TC.StateEntry.value(first)))}, Nil{}},
        StateProof.read_entry(first, 0n, 32n, Nil{})) :
        {TC.Scan.text(TC.Entries.format.rest(rest) ++ "," ++ next, _) == target : TC.Scan}
      read_closed(rest, first, 0n, 32n, Nil{}, next,
        BoolsProof.and_left(TC.Entries.unique(Con{first, rest}, Nil{}),
          Nat.is_le(List.length(&2, TC.StateEntry, Con{first, rest}), 32n), evidence),
        BoolsProof.and_right(TC.Entries.unique(Con{first, rest}, Nil{}),
          Nat.is_le(List.length(&2, TC.StateEntry, Con{first, rest}), 32n), evidence))

# When `count` is less than `room`, members remain allowed after `count`:
# after(count, room) is positive. later_duplicate and later_new_key use it to
# show that the state's entries leave room for one more.
law after_positive:
  for count: Nat
  for room: Nat
  for less: {Nat.is_lt(count, room) == True{} : Bool}
  {Nat.is_lt(0n, after(count, room)) == True{} : Bool}

def after_positive(count, room, less):
  match count:
    case 0n:
      less
    case 1n+more:
      match room:
        case 0n:
          BoolsProof.absurd({Nat.is_lt(0n, after(1n+more, 0n)) == True{} : Bool}, less)
        case 1n+left:
          after_positive(more, left, less)

# When there is room and the entries already have the key of `entry`,
# keeping `entry` changes nothing: Scan.result checks the same entries.
# later_duplicate uses it for the dropped entry.
law keep_present:
  for room: Nat
  for member: Nat
  for +entry: TC.StateEntry
  for +entries: List<&2, TC.StateEntry>
  for present: {TC.Entries.has_key(entries, TC.StateEntry.key_text(entry)) == True{} : Bool}
  for positive: {Nat.is_lt(0n, room) == True{} : Bool}
  {TC.Scan.result(TC.Scan.keep(room, member, entry, entries)) ==
    TC.Scan.state(entries, TC.TraceState.is_valid(entries), {==}) : Result<&2, &2, TC.StateError, TC.TraceState>}

def keep_present(room, member, entry, entries, present, positive):
  match room:
    case 0n:
      BoolsProof.absurd({TC.Scan.result(TC.Scan.keep(0n, member, entry, entries)) ==
        TC.Scan.state(entries, TC.TraceState.is_valid(entries), {==}) :
        Result<&2, &2, TC.StateError, TC.TraceState>}, positive)
    case 1n+left:
      %Equal.sym(Bool, TC.Entries.has_key(entries, TC.StateEntry.key_text(entry)), True{}, present) :
        {TC.Scan.result(TC.Scanning{1n+member, left, TC.Blank{}, TC.Entries.add.if(entries, entry, _)}) ==
          TC.Scan.state(entries, TC.TraceState.is_valid(entries), {==}) :
          Result<&2, &2, TC.StateError, TC.TraceState>}
      {==}

# When there is room and no entry has the key of `entry`, keeping `entry`
# adds it at the end, and Scan.result checks the longer list. later_new_key
# uses it.
law keep_new:
  for room: Nat
  for member: Nat
  for +entry: TC.StateEntry
  for +entries: List<&2, TC.StateEntry>
  for absent: {TC.Entries.has_key(entries, TC.StateEntry.key_text(entry)) == False{} : Bool}
  for positive: {Nat.is_lt(0n, room) == True{} : Bool}
  {TC.Scan.result(TC.Scan.keep(room, member, entry, entries)) ==
    TC.Scan.state(List.append(&2, TC.StateEntry, entries, Con{entry, Nil{}}),
      TC.TraceState.is_valid(List.append(&2, TC.StateEntry, entries, Con{entry, Nil{}})), {==}) :
    Result<&2, &2, TC.StateError, TC.TraceState>}

def keep_new(room, member, entry, entries, absent, positive):
  match room:
    case 0n:
      BoolsProof.absurd({TC.Scan.result(TC.Scan.keep(0n, member, entry, entries)) ==
        TC.Scan.state(List.append(&2, TC.StateEntry, entries, Con{entry, Nil{}}),
          TC.TraceState.is_valid(List.append(&2, TC.StateEntry, entries, Con{entry, Nil{}})), {==}) :
        Result<&2, &2, TC.StateError, TC.TraceState>}, positive)
    case 1n+left:
      %Equal.sym(Bool, TC.Entries.has_key(entries, TC.StateEntry.key_text(entry)), False{}, absent) :
        {TC.Scan.result(TC.Scanning{1n+member, left, TC.Blank{}, TC.Entries.add.if(entries, entry, _)}) ==
          TC.Scan.state(List.append(&2, TC.StateEntry, entries, Con{entry, Nil{}}),
            TC.TraceState.is_valid(List.append(&2, TC.StateEntry, entries, Con{entry, Nil{}})), {==}) :
          Result<&2, &2, TC.StateError, TC.TraceState>}
      {==}

# Adding an entry whose key no entry has keeps the keys distinct: when
# Entries.unique accepts `list` after `seen`, and neither `seen` nor `list`
# has the key of `entry`, it accepts `list` followed by `entry`. Induction on
# `list`, which moves into `seen` one entry at a time. valid_snoc uses it,
# and so does proofs/first.bend when Entries.add keeps a new key.
law unique_snoc:
  for list: List<&2, TC.StateEntry>
  for +entry: TC.StateEntry
  for +seen: List<&2, TC.StateEntry>
  for +unique: {TC.Entries.unique(list, seen) == True{} : Bool}
  for absent: {TC.Entries.has_key(List.append(&2, TC.StateEntry, seen, list), TC.StateEntry.key_text(entry)) == False{} :
    Bool}
  {TC.Entries.unique(List.append(&2, TC.StateEntry, list, Con{entry, Nil{}}), seen) == True{} : Bool}

def unique_snoc(list, entry, seen, unique, absent):
  match list:
    case Nil{}:
      %Equal.sym(Bool, TC.Entries.has_key(seen, TC.StateEntry.key_text(entry)), False{},
        %ListsProof.append_nil(TC.StateEntry, seen) : {TC.Entries.has_key(_, TC.StateEntry.key_text(entry)) == False{} : Bool}
        absent) :
        {Bool.and(Bool.not(_), True{}) == True{} : Bool}
      {==}
    case Con{+first, +rest}:
      +head_absent = BoolsProof.and_left(Bool.not(TC.Entries.has_key(seen, TC.StateEntry.key_text(first))),
        TC.Entries.unique(rest, List.append(&2, TC.StateEntry, seen, Con{first, Nil{}})), unique)
      %Equal.sym(Bool, Bool.not(TC.Entries.has_key(seen, TC.StateEntry.key_text(first))), True{}, head_absent) :
        {Bool.and(_, TC.Entries.unique(List.append(&2, TC.StateEntry, rest, Con{entry, Nil{}}),
          List.append(&2, TC.StateEntry, seen, Con{first, Nil{}}))) == True{} : Bool}
      unique_snoc(rest, entry, List.append(&2, TC.StateEntry, seen, Con{first, Nil{}}),
        BoolsProof.and_right(Bool.not(TC.Entries.has_key(seen, TC.StateEntry.key_text(first))),
          TC.Entries.unique(rest, List.append(&2, TC.StateEntry, seen, Con{first, Nil{}})), unique),
        %Equal.sym(List<&2, TC.StateEntry>,
          List.append(&2, TC.StateEntry, List.append(&2, TC.StateEntry, seen, Con{first, Nil{}}), rest),
          List.append(&2, TC.StateEntry, seen, Con{first, rest}),
          ListsProof.append_assoc(TC.StateEntry, seen, Con{first, Nil{}}, rest)) :
          {TC.Entries.has_key(_, TC.StateEntry.key_text(entry)) == False{} : Bool}
        absent)

# When TraceState.is_valid accepts `entries`, they are fewer than 32 and none
# has the key of `entry`, it also accepts them with `entry` added at the
# end: unique_snoc gives the distinct keys, and ListsProof.length_snoc with
# NatsProof.le_succ the count. later_new_key uses it as the evidence of the
# parsed state.
law valid_snoc:
  for +entries: List<&2, TC.StateEntry>
  for +entry: TC.StateEntry
  for +evidence: {TC.TraceState.is_valid(entries) == True{} : Bool}
  for absent: {TC.Entries.has_key(entries, TC.StateEntry.key_text(entry)) == False{} : Bool}
  for room: {Nat.is_lt(List.length(&2, TC.StateEntry, entries), 32n) == True{} : Bool}
  {TC.TraceState.is_valid(List.append(&2, TC.StateEntry, entries, Con{entry, Nil{}})) == True{} : Bool}

def valid_snoc(entries, entry, evidence, absent, room):
  %Equal.sym(Bool, TC.Entries.unique(List.append(&2, TC.StateEntry, entries, Con{entry, Nil{}}), Nil{}), True{},
    unique_snoc(entries, entry, Nil{},
      BoolsProof.and_left(TC.Entries.unique(entries, Nil{}), Nat.is_le(List.length(&2, TC.StateEntry, entries), 32n),
        evidence),
      absent)) :
    {Bool.and(_, Nat.is_le(List.length(&2, TC.StateEntry, List.append(&2, TC.StateEntry, entries, Con{entry, Nil{}})),
      32n)) == True{} : Bool}
  %Equal.sym(Nat, List.length(&2, TC.StateEntry, List.append(&2, TC.StateEntry, entries, Con{entry, Nil{}})),
    1n+List.length(&2, TC.StateEntry, entries), ListsProof.length_snoc(TC.StateEntry, entries, entry)) :
    {Bool.and(True{}, Nat.is_le(_, 32n)) == True{} : Bool}
  Equal.trans(Bool, Nat.is_le(1n+List.length(&2, TC.StateEntry, entries), 32n),
    Nat.is_lt(List.length(&2, TC.StateEntry, entries), 32n), True{},
    NatsProof.le_succ(List.length(&2, TC.StateEntry, entries), 32n), room)

# Within the tracestate input budget, TraceState.parse is the reading
# machine alone: read the text from Scan.start() and finish.
# StateProof.within turns `fits` into the success of the budget measure.
# later_duplicate, later_new_key and full_state start with it, and so do
# ows_around in proofs/normal.bend and first_wins in proofs/first.bend.
law parse_scan:
  for +limits: TC.Limits
  for +text: String
  for fits: {Nat.is_le(TC.Utf8.length(text), TC.Limits.tracestate_input(limits)) == True{} : Bool}
  {TC.TraceState.parse(limits, text) == TC.Scan.finish(TC.Scan.text(text, TC.Scan.start())) :
    Result<&2, &2, TC.StateError, TC.TraceState>}

def parse_scan(limits, text, fits):
  StateProof.read_fits(TC.Utf8.left(text, Some{TC.Limits.tracestate_input(limits)}), Con{text, Nil{}},
    Equal.trans(Bool, Maybe.is_some(&2, Nat, TC.Utf8.left(text, Some{TC.Limits.tracestate_input(limits)})),
      Nat.is_le(TC.Utf8.length(text), TC.Limits.tracestate_input(limits)), True{},
      StateProof.within(text, TC.Limits.tracestate_input(limits)), fits))

# A state's value, a comma and one more entry leave that entry pending after
# every entry of the state: its key and reversed value wait in the current
# member, not yet validated or counted. It is read_state_then followed by
# StateProof.read_entry. The three laws below end the text there.
law scan_state_entry:
  for +entries: List<&2, TC.StateEntry>
  for +evidence: {TC.TraceState.is_valid(entries) == True{} : Bool}
  for +entry: TC.StateEntry
  {TC.Scan.text(TC.Entries.format(entries) ++ "," ++ TC.StateEntry.format(entry), TC.Scan.start()) ==
    TC.Scanning{opened(entries), after(List.length(&2, TC.StateEntry, entries), 32n),
      TC.InValue{TC.StateEntry.key_text(entry), String.reverse(TC.StateValue.to_string(TC.StateEntry.value(entry)))},
      entries} : TC.Scan}

def scan_state_entry(entries, evidence, entry):
  Equal.trans(TC.Scan, TC.Scan.text(TC.Entries.format(entries) ++ "," ++ TC.StateEntry.format(entry), TC.Scan.start()),
    TC.Scan.text(TC.StateEntry.format(entry), TC.Scanning{opened(entries),
      after(List.length(&2, TC.StateEntry, entries), 32n), TC.Blank{}, entries}),
    TC.Scanning{opened(entries), after(List.length(&2, TC.StateEntry, entries), 32n),
      TC.InValue{TC.StateEntry.key_text(entry), String.reverse(TC.StateValue.to_string(TC.StateEntry.value(entry)))},
      entries},
    read_state_then(entries, evidence, TC.StateEntry.format(entry)),
    StateProof.read_entry(entry, opened(entries), after(List.length(&2, TC.StateEntry, entries), 32n), entries))

# When the value of a state with fewer than 32 entries is followed by a comma
# and an entry whose key the state has, and the text fits the budget,
# parsing gives back the state: the later entry is dropped, though it still
# counts as a member. This is the law later_duplicate with `present` stated
# with Entries.has_key; Laws.later_duplicate converts its key_among
# hypothesis with DistinctProof.has_key_among.
law later_duplicate:
  for +limits: TC.Limits
  for state: TC.TraceState
  for entry: TC.StateEntry
  for present: {TC.Entries.has_key(TC.TraceState.entries(state), TC.StateEntry.key_text(entry)) == True{} : Bool}
  for room: {Nat.is_lt(List.length(&2, TC.StateEntry, TC.TraceState.entries(state)), 32n) == True{} : Bool}
  for fits: {Nat.is_le(TC.Utf8.length(TC.TraceState.format(state) ++ "," ++ TC.StateEntry.format(entry)),
    TC.Limits.tracestate_input(limits)) == True{} : Bool}
  {TC.TraceState.parse(limits, TC.TraceState.format(state) ++ "," ++ TC.StateEntry.format(entry)) == Done{state} :
    Result<&2, &2, TC.StateError, TC.TraceState>}

# Rewrites the parse step by step; keep_present drops the repeated entry.
def later_duplicate(limits, state, entry, present, room, fits):
  match state:
    case TC.TraceState{+entries, +evidence}:
      match entry:
        case TC.StateEntry{+key, TC.StateValue{+value, +value_valid}}:
          +pending = {TC.StateEntry{key, TC.StateValue{value, value_valid}} : TC.StateEntry}
          %Equal.sym(Result<&2, &2, TC.StateError, TC.TraceState>,
            TC.TraceState.parse(limits, TC.Entries.format(entries) ++ "," ++ TC.StateEntry.format(pending)),
            TC.Scan.finish(TC.Scan.text(TC.Entries.format(entries) ++ "," ++ TC.StateEntry.format(pending),
              TC.Scan.start())),
            parse_scan(limits, TC.Entries.format(entries) ++ "," ++ TC.StateEntry.format(pending), fits)) :
            {_ == Done{TC.TraceState{entries, evidence}} : Result<&2, &2, TC.StateError, TC.TraceState>}
          %Equal.sym(TC.Scan,
            TC.Scan.text(TC.Entries.format(entries) ++ "," ++ TC.StateEntry.format(pending), TC.Scan.start()),
            TC.Scanning{opened(entries), after(List.length(&2, TC.StateEntry, entries), 32n),
              TC.InValue{TC.StateKey.to_string(key), String.reverse(value)}, entries},
            scan_state_entry(entries, evidence, pending)) :
            {TC.Scan.finish(_) == Done{TC.TraceState{entries, evidence}} : Result<&2, &2, TC.StateError, TC.TraceState>}
          %Equal.sym(TC.Scan,
            TC.Scan.close(opened(entries), after(List.length(&2, TC.StateEntry, entries), 32n),
              TC.InValue{TC.StateKey.to_string(key), String.reverse(value)}, entries),
            TC.Scan.keep(after(List.length(&2, TC.StateEntry, entries), 32n), opened(entries), pending, entries),
            StateProof.close_keep(pending, opened(entries), after(List.length(&2, TC.StateEntry, entries), 32n),
              entries)) :
            {TC.Scan.result(_) == Done{TC.TraceState{entries, evidence}} : Result<&2, &2, TC.StateError, TC.TraceState>}
          %Equal.sym(Result<&2, &2, TC.StateError, TC.TraceState>,
            TC.Scan.result(TC.Scan.keep(after(List.length(&2, TC.StateEntry, entries), 32n), opened(entries), pending,
              entries)),
            TC.Scan.state(entries, TC.TraceState.is_valid(entries), {==}),
            keep_present(after(List.length(&2, TC.StateEntry, entries), 32n), opened(entries), pending, entries, present,
              after_positive(List.length(&2, TC.StateEntry, entries), 32n, room))) :
            {_ == Done{TC.TraceState{entries, evidence}} : Result<&2, &2, TC.StateError, TC.TraceState>}
          StateProof.checked_valid(entries, evidence)

# When the key of `entry` is new, the state has fewer than 32 entries and
# the state's value, a comma and `entry` fit the budget, parsing that text
# gives the state's entries followed by `entry`, in order; Result.map keeps
# only the parsed entries. The law later_new_key, with `absent` stated with
# Entries.has_key as in later_duplicate.
law later_new_key:
  for +limits: TC.Limits
  for state: TC.TraceState
  for entry: TC.StateEntry
  for +absent: {TC.Entries.has_key(TC.TraceState.entries(state), TC.StateEntry.key_text(entry)) == False{} : Bool}
  for +room: {Nat.is_lt(List.length(&2, TC.StateEntry, TC.TraceState.entries(state)), 32n) == True{} : Bool}
  for fits: {Nat.is_le(TC.Utf8.length(TC.TraceState.format(state) ++ "," ++ TC.StateEntry.format(entry)),
    TC.Limits.tracestate_input(limits)) == True{} : Bool}
  {Result.map(&2, &2, TC.StateError, TC.TraceState, List<&2, TC.StateEntry>, parsed => TC.TraceState.entries(parsed),
    TC.TraceState.parse(limits, TC.TraceState.format(state) ++ "," ++ TC.StateEntry.format(entry))) ==
    Done{List.append(&2, TC.StateEntry, TC.TraceState.entries(state), Con{entry, Nil{}})} :
    Result<&2, &2, TC.StateError, List<&2, TC.StateEntry>>}

# As later_duplicate, with keep_new; valid_snoc is the new state's evidence.
def later_new_key(limits, state, entry, absent, room, fits):
  match state:
    case TC.TraceState{+entries, +evidence}:
      match entry:
        case TC.StateEntry{+key, TC.StateValue{+value, +value_valid}}:
          +pending = {TC.StateEntry{key, TC.StateValue{value, value_valid}} : TC.StateEntry}
          +added = {List.append(&2, TC.StateEntry, entries, Con{pending, Nil{}}) : List<&2, TC.StateEntry>}
          %Equal.sym(Result<&2, &2, TC.StateError, TC.TraceState>,
            TC.TraceState.parse(limits, TC.Entries.format(entries) ++ "," ++ TC.StateEntry.format(pending)),
            TC.Scan.finish(TC.Scan.text(TC.Entries.format(entries) ++ "," ++ TC.StateEntry.format(pending),
              TC.Scan.start())),
            parse_scan(limits, TC.Entries.format(entries) ++ "," ++ TC.StateEntry.format(pending), fits)) :
            {Result.map(&2, &2, TC.StateError, TC.TraceState, List<&2, TC.StateEntry>,
              parsed => TC.TraceState.entries(parsed), _) == Done{added} :
              Result<&2, &2, TC.StateError, List<&2, TC.StateEntry>>}
          %Equal.sym(TC.Scan,
            TC.Scan.text(TC.Entries.format(entries) ++ "," ++ TC.StateEntry.format(pending), TC.Scan.start()),
            TC.Scanning{opened(entries), after(List.length(&2, TC.StateEntry, entries), 32n),
              TC.InValue{TC.StateKey.to_string(key), String.reverse(value)}, entries},
            scan_state_entry(entries, evidence, pending)) :
            {Result.map(&2, &2, TC.StateError, TC.TraceState, List<&2, TC.StateEntry>,
              parsed => TC.TraceState.entries(parsed), TC.Scan.finish(_)) == Done{added} :
              Result<&2, &2, TC.StateError, List<&2, TC.StateEntry>>}
          %Equal.sym(TC.Scan,
            TC.Scan.close(opened(entries), after(List.length(&2, TC.StateEntry, entries), 32n),
              TC.InValue{TC.StateKey.to_string(key), String.reverse(value)}, entries),
            TC.Scan.keep(after(List.length(&2, TC.StateEntry, entries), 32n), opened(entries), pending, entries),
            StateProof.close_keep(pending, opened(entries), after(List.length(&2, TC.StateEntry, entries), 32n),
              entries)) :
            {Result.map(&2, &2, TC.StateError, TC.TraceState, List<&2, TC.StateEntry>,
              parsed => TC.TraceState.entries(parsed), TC.Scan.result(_)) == Done{added} :
              Result<&2, &2, TC.StateError, List<&2, TC.StateEntry>>}
          %Equal.sym(Result<&2, &2, TC.StateError, TC.TraceState>,
            TC.Scan.result(TC.Scan.keep(after(List.length(&2, TC.StateEntry, entries), 32n), opened(entries), pending,
              entries)),
            TC.Scan.state(added, TC.TraceState.is_valid(added), {==}),
            keep_new(after(List.length(&2, TC.StateEntry, entries), 32n), opened(entries), pending, entries, absent,
              after_positive(List.length(&2, TC.StateEntry, entries), 32n, room))) :
            {Result.map(&2, &2, TC.StateError, TC.TraceState, List<&2, TC.StateEntry>,
              parsed => TC.TraceState.entries(parsed), _) == Done{added} :
              Result<&2, &2, TC.StateError, List<&2, TC.StateEntry>>}
          %Equal.sym(Result<&2, &2, TC.StateError, TC.TraceState>,
            TC.Scan.state(added, TC.TraceState.is_valid(added), {==}),
            Done{TC.TraceState{added, valid_snoc(entries, pending, evidence, absent, room)}},
            StateProof.checked_valid(added, valid_snoc(entries, pending, evidence, absent, room))) :
            {Result.map(&2, &2, TC.StateError, TC.TraceState, List<&2, TC.StateEntry>,
              parsed => TC.TraceState.entries(parsed), _) == Done{added} :
              Result<&2, &2, TC.StateError, List<&2, TC.StateEntry>>}
          {==}

# Members are counted before duplicates are dropped: after a state of 32
# entries, any further entry makes parsing fail with TooManyMembers when the
# text fits the budget, even an entry repeating a key. The law full_state,
# stated as in LAWS.bend.
law full_state:
  for +limits: TC.Limits
  for state: TC.TraceState
  for entry: TC.StateEntry
  for full: {List.length(&2, TC.StateEntry, TC.TraceState.entries(state)) == 32n : Nat}
  for fits: {Nat.is_le(TC.Utf8.length(TC.TraceState.format(state) ++ "," ++ TC.StateEntry.format(entry)),
    TC.Limits.tracestate_input(limits)) == True{} : Bool}
  {TC.TraceState.parse(limits, TC.TraceState.format(state) ++ "," ++ TC.StateEntry.format(entry)) ==
    Fail{TC.TooManyMembers{}} : Result<&2, &2, TC.StateError, TC.TraceState>}

# As later_duplicate up to Scan.keep; with `full`, its room computes to 0n.
def full_state(limits, state, entry, full, fits):
  match state:
    case TC.TraceState{+entries, +evidence}:
      match entry:
        case TC.StateEntry{+key, TC.StateValue{+value, +value_valid}}:
          +pending = {TC.StateEntry{key, TC.StateValue{value, value_valid}} : TC.StateEntry}
          %Equal.sym(Result<&2, &2, TC.StateError, TC.TraceState>,
            TC.TraceState.parse(limits, TC.Entries.format(entries) ++ "," ++ TC.StateEntry.format(pending)),
            TC.Scan.finish(TC.Scan.text(TC.Entries.format(entries) ++ "," ++ TC.StateEntry.format(pending),
              TC.Scan.start())),
            parse_scan(limits, TC.Entries.format(entries) ++ "," ++ TC.StateEntry.format(pending), fits)) :
            {_ == Fail{TC.TooManyMembers{}} : Result<&2, &2, TC.StateError, TC.TraceState>}
          %Equal.sym(TC.Scan,
            TC.Scan.text(TC.Entries.format(entries) ++ "," ++ TC.StateEntry.format(pending), TC.Scan.start()),
            TC.Scanning{opened(entries), after(List.length(&2, TC.StateEntry, entries), 32n),
              TC.InValue{TC.StateKey.to_string(key), String.reverse(value)}, entries},
            scan_state_entry(entries, evidence, pending)) :
            {TC.Scan.finish(_) == Fail{TC.TooManyMembers{}} : Result<&2, &2, TC.StateError, TC.TraceState>}
          %Equal.sym(TC.Scan,
            TC.Scan.close(opened(entries), after(List.length(&2, TC.StateEntry, entries), 32n),
              TC.InValue{TC.StateKey.to_string(key), String.reverse(value)}, entries),
            TC.Scan.keep(after(List.length(&2, TC.StateEntry, entries), 32n), opened(entries), pending, entries),
            StateProof.close_keep(pending, opened(entries), after(List.length(&2, TC.StateEntry, entries), 32n),
              entries)) :
            {TC.Scan.result(_) == Fail{TC.TooManyMembers{}} : Result<&2, &2, TC.StateError, TC.TraceState>}
          %Equal.sym(Nat, List.length(&2, TC.StateEntry, entries), 32n, full) :
            {TC.Scan.result(TC.Scan.keep(after(_, 32n), opened(entries), pending, entries)) ==
              Fail{TC.TooManyMembers{}} : Result<&2, &2, TC.StateError, TC.TraceState>}
          {==}
