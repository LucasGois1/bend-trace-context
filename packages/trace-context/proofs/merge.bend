import Base
import ../trace_context.bend as TC
import ./strings.bend as StringsProof
import ./bools.bend as BoolsProof
import ./lists.bend as ListsProof
import ./nats.bend as NatsProof
import ./tracestate.bend as StateProof

# A state's value followed by more members: the state's entries all end before
# the text after the comma is read.
# How many nonempty members remain allowed after `count` more.
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

# The member number after `count` more members.
def members_after(count: Nat, member: Nat) -> Nat:
  match count:
    case 0n:
      member
    case 1n+more:
      members_after(more, 1n+member)

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

# The member number after a state's members and the comma that follows them:
# an empty state's value is itself an empty member.
def opened(entries: List<&2, TC.StateEntry>) -> Nat:
  match entries:
    case Nil{}:
      1n
    case Con{first, rest}:
      members_after(List.length(&2, TC.StateEntry, Con{first, rest}), 0n)

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

# Adding an entry whose key no entry has keeps the keys distinct.
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
# every entry of the state.
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

# A later entry whose key the state has is dropped.
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

# A later entry with a new key is added after every entry of the state.
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

# Members are counted before duplicates are dropped: after 32 entries, any
# entry is refused, even one repeating a key.
law full_state:
  for +limits: TC.Limits
  for state: TC.TraceState
  for entry: TC.StateEntry
  for full: {List.length(&2, TC.StateEntry, TC.TraceState.entries(state)) == 32n : Nat}
  for fits: {Nat.is_le(TC.Utf8.length(TC.TraceState.format(state) ++ "," ++ TC.StateEntry.format(entry)),
    TC.Limits.tracestate_input(limits)) == True{} : Bool}
  {TC.TraceState.parse(limits, TC.TraceState.format(state) ++ "," ++ TC.StateEntry.format(entry)) ==
    Fail{TC.TooManyMembers{}} : Result<&2, &2, TC.StateError, TC.TraceState>}

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
