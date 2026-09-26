# Proofs: separators and optional whitespace
# ==========================================
#
# Two groups of lemmas. Separators: no key or value contains "," or "=",
# because every character of a valid key or value passes a class that
# refuses both (laws key_separators and value_separators). Optional
# whitespace: a state's normalized value with optional whitespace before and
# after it parses back to the state when it fits the budget (law
# ows_around), and so does the value alone (law state_roundtrip, proved by
# roundtrip). PROOF.bend calls key_separators, value_separators, ows_around
# and roundtrip.
#
# The separator proofs follow the grammar checks of trace_context.bend: an
# induction on the text, with the room of the check, in which
# CharsProof.differs shows that a character a class accepts differs from
# one it refuses. The whitespace proofs follow the reading machine:
# MergeProof.parse_scan removes the budget check, blank_ows skips the
# whitespace before the value, and ows_after reads the value. Its induction,
# read_rest_ows, reads one entry at a time like MergeProof.read_closed; at
# the end, value_ows reads the trailing whitespace into the last value, and
# close_entry_ows shows, through restore_ows, that closing the member drops
# it.

import Base
import ../LAWS.bend as Laws
import ../trace_context.bend as TC
import ./chars.bend as CharsProof
import ./strings.bend as StringsProof
import ./bools.bend as BoolsProof
import ./lists.bend as ListsProof
import ./tracestate.bend as StateProof
import ./merge.bend as MergeProof

# Separators
# ==========

# When StateKey.valid.rest accepts `text`, every character of it is a key
# character, so `text` lacks any `char` that StateChar.is_key refuses.
# Induction on `text` with the room of the check; CharsProof.differs shows
# that each character differs from `char`. key_lacks uses it for the
# characters after a key's first.
law key_rest_lacks:
  for text: String
  for room: Nat
  for +valid: {TC.StateKey.valid.rest(text, room) == True{} : Bool}
  for +char: Char
  for +fails: {TC.StateChar.is_key(char) == False{} : Bool}
  {Laws.lacks(char, text) == True{} : Bool}

def key_rest_lacks(text, room, valid, char, fails):
  match text:
    case SNil{}:
      {==}
    case SCon{+first, +rest}:
      match room:
        case 0n:
          BoolsProof.absurd({Laws.lacks(char, SCon{first, rest}) == True{} : Bool}, valid)
        case 1n+left:
          %Equal.sym(Bool, Char.is_eq(first, char), False{},
            CharsProof.differs(x => TC.StateChar.is_key(x), first, char,
              BoolsProof.and_left(TC.StateChar.is_key(first), TC.StateKey.valid.rest(rest, left), valid), fails)) :
            {Bool.and(Bool.not(_), Laws.lacks(char, rest)) == True{} : Bool}
          key_rest_lacks(rest, left,
            BoolsProof.and_right(TC.StateChar.is_key(first), TC.StateKey.valid.rest(rest, left), valid), char, fails)

# A valid key lacks every `char` refused both as a key's first character
# (StateChar.is_key_start) and as a later one (StateChar.is_key, through
# key_rest_lacks). key_separators applies it to "," and "=", for which both
# checks compute to False{}.
law key_lacks:
  for text: String
  for +valid: {TC.StateKey.is_valid(text) == True{} : Bool}
  for +char: Char
  for +start_fails: {TC.StateChar.is_key_start(char) == False{} : Bool}
  for +fails: {TC.StateChar.is_key(char) == False{} : Bool}
  {Laws.lacks(char, text) == True{} : Bool}

def key_lacks(text, valid, char, start_fails, fails):
  match text:
    case SNil{}:
      {==}
    case SCon{+first, +rest}:
      %Equal.sym(Bool, Char.is_eq(first, char), False{},
        CharsProof.differs(x => TC.StateChar.is_key_start(x), first, char,
          BoolsProof.and_left(TC.StateChar.is_key_start(first), TC.StateKey.valid.rest(rest, 255n), valid),
          start_fails)) :
        {Bool.and(Bool.not(_), Laws.lacks(char, rest)) == True{} : Bool}
      key_rest_lacks(rest, 255n,
        BoolsProof.and_right(TC.StateChar.is_key_start(first), TC.StateKey.valid.rest(rest, 255n), valid),
        char, fails)

# No key contains "," or "=": the law key_separators, which PROOF.bend
# proves with it.
law key_separators:
  for key: TC.StateKey
  {Laws.lacks(',', TC.StateKey.to_string(key)) == True{} : Bool} &
  {Laws.lacks('=', TC.StateKey.to_string(key)) == True{} : Bool}

def key_separators(key):
  match key:
    case TC.StateKey{+text, +valid}:
      (key_lacks(text, valid, ',', {==}, {==}), key_lacks(text, valid, '=', {==}, {==}))

# When StateValue.valid.go accepts `first` followed by `tail`, that text
# lacks any `char` refused both by StateChar.is_value, which the check
# applies to every character but the last, and by StateChar.is_value_end,
# which it applies to the last. Induction on `tail` with the room of the
# check. value_lacks uses it.
law value_go_lacks:
  for tail: String
  for +first: Char
  for room: Nat
  for +valid: {TC.StateValue.valid.go(tail, first, room) == True{} : Bool}
  for +char: Char
  for +value_fails: {TC.StateChar.is_value(char) == False{} : Bool}
  for +end_fails: {TC.StateChar.is_value_end(char) == False{} : Bool}
  {Laws.lacks(char, SCon{first, tail}) == True{} : Bool}

def value_go_lacks(tail, first, room, valid, char, value_fails, end_fails):
  match tail:
    case SNil{}:
      %Equal.sym(Bool, Char.is_eq(first, char), False{},
        CharsProof.differs(x => TC.StateChar.is_value_end(x), first, char, valid, end_fails)) :
        {Bool.and(Bool.not(_), Laws.lacks(char, SNil{})) == True{} : Bool}
      {==}
    case SCon{+next, +rest}:
      match room:
        case 0n:
          BoolsProof.absurd({Laws.lacks(char, SCon{first, SCon{next, rest}}) == True{} : Bool}, valid)
        case 1n+left:
          %Equal.sym(Bool, Char.is_eq(first, char), False{},
            CharsProof.differs(x => TC.StateChar.is_value(x), first, char,
              BoolsProof.and_left(TC.StateChar.is_value(first), TC.StateValue.valid.go(rest, next, left), valid),
              value_fails)) :
            {Bool.and(Bool.not(_), Laws.lacks(char, SCon{next, rest})) == True{} : Bool}
          value_go_lacks(rest, next, left,
            BoolsProof.and_right(TC.StateChar.is_value(first), TC.StateValue.valid.go(rest, next, left), valid),
            char, value_fails, end_fails)

# A valid value lacks every `char` that StateChar.is_value and
# StateChar.is_value_end both refuse. value_separators applies it to ","
# and "=", for which both checks compute to False{}.
law value_lacks:
  for text: String
  for +valid: {TC.StateValue.is_valid(text) == True{} : Bool}
  for +char: Char
  for +value_fails: {TC.StateChar.is_value(char) == False{} : Bool}
  for +end_fails: {TC.StateChar.is_value_end(char) == False{} : Bool}
  {Laws.lacks(char, text) == True{} : Bool}

def value_lacks(text, valid, char, value_fails, end_fails):
  match text:
    case SNil{}:
      {==}
    case SCon{+first, +tail}:
      value_go_lacks(tail, first, 255n, valid, char, value_fails, end_fails)

# No value contains "," or "=": the law value_separators, which PROOF.bend
# proves with it.
law value_separators:
  for value: TC.StateValue
  {Laws.lacks(',', TC.StateValue.to_string(value)) == True{} : Bool} &
  {Laws.lacks('=', TC.StateValue.to_string(value)) == True{} : Bool}

def value_separators(value):
  match value:
    case TC.StateValue{+text, +valid}:
      (value_lacks(text, valid, ',', {==}, {==}), value_lacks(text, valid, '=', {==}, {==}))

# Optional whitespace
# ===================

# The first character of a text that Laws.all_ows accepts passes
# StateChar.is_ows: all_ows spells out the same test, a space or a
# horizontal tab. The whitespace lemmas below use it at each character.
law ows_is_ows:
  for +char: Char
  for +rest: String
  for +ows: {Laws.all_ows(SCon{char, rest}) == True{} : Bool}
  {TC.StateChar.is_ows(char) == True{} : Bool}

def ows_is_ows(char, rest, ows):
  BoolsProof.and_left(Bool.or(Char.is_eq(char, ' '), Char.is_eq(char, '\t')), Laws.all_ows(rest), ows)

# Whitespace after a value's last character is read into the pending value:
# inside a value, reading a text that Laws.all_ows accepts ends nothing and
# adds each character to the value text, which is kept most recent first
# (String.reverse.go(text, acc)). read_rest_ows uses it at the end of the
# last value.
law value_ows:
  for text: String
  for +ows: {Laws.all_ows(text) == True{} : Bool}
  for +member: Nat
  for +allowed: Nat
  for +key: String
  for acc: String
  for +entries: List<&2, TC.StateEntry>
  {TC.Scan.text(text, TC.Scanning{member, allowed, TC.InValue{key, acc}, entries}) ==
    TC.Scanning{member, allowed, TC.InValue{key, String.reverse.go(text, acc)}, entries} : TC.Scan}

def value_ows(text, ows, member, allowed, key, acc, entries):
  match text:
    case SNil{}:
      {==}
    case SCon{+char, +rest}:
      %Equal.sym(Bool, Char.is_eq(char, ','), False{},
        CharsProof.differs(x => TC.StateChar.is_ows(x), char, ',', ows_is_ows(char, rest, ows), {==})) :
        {TC.Scan.text(rest, TC.Scan.read(_, char, member, allowed, TC.InValue{key, acc}, entries)) ==
          TC.Scanning{member, allowed, TC.InValue{key, String.reverse.go(rest, SCon{char, acc})}, entries} : TC.Scan}
      value_ows(rest,
        BoolsProof.and_right(Bool.or(Char.is_eq(char, ' '), Char.is_eq(char, '\t')), Laws.all_ows(rest), ows),
        member, allowed, key, SCon{char, acc}, entries)

# Restoring a pending value leaves out the whitespace read after it:
# Value.restore skips optional whitespace at the front of a pending value
# text, where the last characters read are, so whitespace pushed onto `acc`
# changes nothing. Induction on `text`, generalized over `acc`.
# close_entry_ows uses it.
law restore_ows:
  for text: String
  for +ows: {Laws.all_ows(text) == True{} : Bool}
  for acc: String
  {TC.Value.restore.go(String.reverse.go(text, acc), (False{}, "")) == TC.Value.restore.go(acc, (False{}, "")) : String}

def restore_ows(text, ows, acc):
  match text:
    case SNil{}:
      {==}
    case SCon{+char, +rest}:
      Equal.trans(String, TC.Value.restore.go(String.reverse.go(rest, SCon{char, acc}), (False{}, "")),
        TC.Value.restore.go(SCon{char, acc}, (False{}, "")), TC.Value.restore.go(acc, (False{}, "")),
        restore_ows(rest,
          BoolsProof.and_right(Bool.or(Char.is_eq(char, ' '), Char.is_eq(char, '\t')), Laws.all_ows(rest), ows),
          SCon{char, acc}),
        %Equal.sym(Bool, TC.StateChar.is_ows(char), True{}, ows_is_ows(char, rest, ows)) :
          {TC.Value.restore.go(acc, TC.Value.restore.step(False{}, _, char, "")) ==
            TC.Value.restore.go(acc, (False{}, "")) : String}
        {==})

# Whitespace before a key is skipped: in a member that has no key yet,
# reading a text that Laws.all_ows accepts changes nothing. ows_around uses
# it for the whitespace before the value, and ows_after for the whitespace
# after the empty state's value.
law blank_ows:
  for text: String
  for +ows: {Laws.all_ows(text) == True{} : Bool}
  for +member: Nat
  for +allowed: Nat
  for +entries: List<&2, TC.StateEntry>
  {TC.Scan.text(text, TC.Scanning{member, allowed, TC.Blank{}, entries}) ==
    TC.Scanning{member, allowed, TC.Blank{}, entries} : TC.Scan}

def blank_ows(text, ows, member, allowed, entries):
  match text:
    case SNil{}:
      {==}
    case SCon{+char, +rest}:
      +holds = ows_is_ows(char, rest, ows)
      %Equal.sym(Bool, Char.is_eq(char, ','), False{},
        CharsProof.differs(x => TC.StateChar.is_ows(x), char, ',', holds, {==})) :
        {TC.Scan.text(rest, TC.Scan.read(_, char, member, allowed, TC.Blank{}, entries)) ==
          TC.Scanning{member, allowed, TC.Blank{}, entries} : TC.Scan}
      %Equal.sym(Bool, TC.StateChar.is_ows(char), True{}, holds) :
        {TC.Scan.text(rest, TC.Scanning{member, allowed, TC.Member.start(_, Char.is_eq(char, '='), char), entries}) ==
          TC.Scanning{member, allowed, TC.Blank{}, entries} : TC.Scan}
      blank_ows(rest,
        BoolsProof.and_right(Bool.or(Char.is_eq(char, ' '), Char.is_eq(char, '\t')), Laws.all_ows(rest), ows),
        member, allowed, entries)

# When an entry's value is followed by whitespace, ending its member works
# as without it (StateProof.close_entry): with room left and a new key,
# closing the member adds exactly that entry, because restoring the pending
# text drops the whitespace (restore_ows) and gives back the value
# (StateProof.restore_reversed). read_rest_ows uses it for the last entry.
law close_entry_ows:
  for entry: TC.StateEntry
  for +member: Nat
  for +left: Nat
  for +entries: List<&2, TC.StateEntry>
  for absent: {TC.Entries.has_key(entries, TC.StateEntry.key_text(entry)) == False{} : Bool}
  for +after: String
  for +after_ows: {Laws.all_ows(after) == True{} : Bool}
  {TC.Scan.close(member, 1n+left, TC.InValue{TC.StateEntry.key_text(entry),
      String.reverse.go(after, String.reverse(TC.StateValue.to_string(TC.StateEntry.value(entry))))}, entries) ==
    TC.Scanning{1n+member, left, TC.Blank{}, List.append(&2, TC.StateEntry, entries, Con{entry, Nil{}})} : TC.Scan}

def close_entry_ows(entry, member, left, entries, absent, after, after_ows):
  match entry:
    case TC.StateEntry{+key, TC.StateValue{+value, +value_valid}}:
      +pending = {TC.StateEntry{key, TC.StateValue{value, value_valid}} : TC.StateEntry}
      Equal.trans(TC.Scan,
        TC.Scan.close(member, 1n+left, TC.InValue{TC.StateKey.to_string(key),
          String.reverse.go(after, String.reverse(value))}, entries),
        TC.Scan.keep(1n+left, member, pending, entries),
        TC.Scanning{1n+member, left, TC.Blank{}, List.append(&2, TC.StateEntry, entries, Con{pending, Nil{}})},
        StateProof.close_restored(key, value, value_valid, String.reverse.go(after, String.reverse(value)),
          Equal.trans(String, TC.Value.restore.go(String.reverse.go(after, String.reverse(value)), (False{}, "")),
            TC.Value.restore.go(String.reverse(value), (False{}, "")), value,
            restore_ows(after, after_ows, String.reverse(value)), StateProof.restore_reversed(value, value_valid)),
          member, 1n+left, entries),
        StateProof.keep_added(member, left, pending, entries, absent))

# The rest of a formatted state followed by whitespace adds every entry:
# with `current` pending after `entries`, reading each entry of `rest` after
# its comma, then `after`, and finishing gives the state `all` that `split`
# says they form, with its own evidence. `unique` says each key is new, and
# `fits` that there is room for each entry. Induction on `rest`, as in
# MergeProof.read_closed, but ending at the end of the text, not a comma.
law read_rest_ows:
  for rest: List<&2, TC.StateEntry>
  for +current: TC.StateEntry
  for +member: Nat
  for +allowed: Nat
  for +entries: List<&2, TC.StateEntry>
  for +all: List<&2, TC.StateEntry>
  for +evidence: {TC.TraceState.is_valid(all) == True{} : Bool}
  for split: {List.append(&2, TC.StateEntry, entries, Con{current, rest}) == all : List<&2, TC.StateEntry>}
  for +unique: {TC.Entries.unique(Con{current, rest}, entries) == True{} : Bool}
  for fits: {Nat.is_le(List.length(&2, TC.StateEntry, Con{current, rest}), allowed) == True{} : Bool}
  for +after: String
  for +after_ows: {Laws.all_ows(after) == True{} : Bool}
  {TC.Scan.finish(TC.Scan.text(TC.Entries.format.rest(rest) ++ after, TC.Scanning{member, allowed,
      TC.InValue{TC.StateEntry.key_text(current), String.reverse(TC.StateValue.to_string(TC.StateEntry.value(current)))},
      entries})) == Done{TC.TraceState{all, evidence}} : Result<&2, &2, TC.StateError, TC.TraceState>}

def read_rest_ows(rest, current, member, allowed, entries, all, evidence, split, unique, fits, after, after_ows):
  match rest:
    case Nil{}:
      match allowed:
        case 0n:
          BoolsProof.absurd({TC.Scan.finish(TC.Scan.text(TC.Entries.format.rest(Nil{}) ++ after, TC.Scanning{member, 0n,
            TC.InValue{TC.StateEntry.key_text(current),
              String.reverse(TC.StateValue.to_string(TC.StateEntry.value(current)))}, entries})) ==
            Done{TC.TraceState{all, evidence}} : Result<&2, &2, TC.StateError, TC.TraceState>}, fits)
        case 1n+left:
          +absent = BoolsProof.not_true(TC.Entries.has_key(entries, TC.StateEntry.key_text(current)),
            BoolsProof.and_left(Bool.not(TC.Entries.has_key(entries, TC.StateEntry.key_text(current))),
              TC.Entries.unique(Nil{}, List.append(&2, TC.StateEntry, entries, Con{current, Nil{}})), unique))
          +pending = {String.reverse(TC.StateValue.to_string(TC.StateEntry.value(current))) : String}
          %Equal.sym(TC.Scan,
            TC.Scan.text(after, TC.Scanning{member, 1n+left, TC.InValue{TC.StateEntry.key_text(current), pending},
              entries}),
            TC.Scanning{member, 1n+left, TC.InValue{TC.StateEntry.key_text(current), String.reverse.go(after, pending)},
              entries},
            value_ows(after, after_ows, member, 1n+left, TC.StateEntry.key_text(current), pending, entries)) :
            {TC.Scan.finish(_) == Done{TC.TraceState{all, evidence}} : Result<&2, &2, TC.StateError, TC.TraceState>}
          %Equal.sym(TC.Scan, TC.Scan.close(member, 1n+left, TC.InValue{TC.StateEntry.key_text(current),
              String.reverse.go(after, pending)}, entries),
            TC.Scanning{1n+member, left, TC.Blank{}, List.append(&2, TC.StateEntry, entries, Con{current, Nil{}})},
            close_entry_ows(current, member, left, entries, absent, after, after_ows)) :
            {TC.Scan.result(_) == Done{TC.TraceState{all, evidence}} : Result<&2, &2, TC.StateError, TC.TraceState>}
          %Equal.sym(List<&2, TC.StateEntry>, List.append(&2, TC.StateEntry, entries, Con{current, Nil{}}), all, split) :
            {TC.Scan.state(_, TC.TraceState.is_valid(_), {==}) == Done{TC.TraceState{all, evidence}} :
              Result<&2, &2, TC.StateError, TC.TraceState>}
          StateProof.checked_valid(all, evidence)
    case Con{+next, +later}:
      match allowed:
        case 0n:
          BoolsProof.absurd({TC.Scan.finish(TC.Scan.text(TC.Entries.format.rest(Con{next, later}) ++ after,
            TC.Scanning{member, 0n, TC.InValue{TC.StateEntry.key_text(current),
              String.reverse(TC.StateValue.to_string(TC.StateEntry.value(current)))}, entries})) ==
            Done{TC.TraceState{all, evidence}} : Result<&2, &2, TC.StateError, TC.TraceState>}, fits)
        case 1n+left:
          +absent = BoolsProof.not_true(TC.Entries.has_key(entries, TC.StateEntry.key_text(current)),
            BoolsProof.and_left(Bool.not(TC.Entries.has_key(entries, TC.StateEntry.key_text(current))),
              TC.Entries.unique(Con{next, later}, List.append(&2, TC.StateEntry, entries, Con{current, Nil{}})), unique))
          +added = {List.append(&2, TC.StateEntry, entries, Con{current, Nil{}}) : List<&2, TC.StateEntry>}
          %Equal.sym(TC.Scan, TC.Scan.close(member, 1n+left, TC.InValue{TC.StateEntry.key_text(current),
              String.reverse(TC.StateValue.to_string(TC.StateEntry.value(current)))}, entries),
            TC.Scanning{1n+member, left, TC.Blank{}, added},
            StateProof.close_entry(current, member, left, entries, absent)) :
            {TC.Scan.finish(TC.Scan.text((TC.StateEntry.format(next) ++ TC.Entries.format.rest(later)) ++ after, _)) ==
              Done{TC.TraceState{all, evidence}} : Result<&2, &2, TC.StateError, TC.TraceState>}
          %Equal.sym(String, (TC.StateEntry.format(next) ++ TC.Entries.format.rest(later)) ++ after,
            TC.StateEntry.format(next) ++ TC.Entries.format.rest(later) ++ after,
            StringsProof.string_assoc(TC.StateEntry.format(next), TC.Entries.format.rest(later), after)) :
            {TC.Scan.finish(TC.Scan.text(_, TC.Scanning{1n+member, left, TC.Blank{}, added})) ==
              Done{TC.TraceState{all, evidence}} : Result<&2, &2, TC.StateError, TC.TraceState>}
          %Equal.sym(TC.Scan,
            TC.Scan.text(TC.StateEntry.format(next) ++ TC.Entries.format.rest(later) ++ after,
              TC.Scanning{1n+member, left, TC.Blank{}, added}),
            TC.Scan.text(TC.Entries.format.rest(later) ++ after,
              TC.Scan.text(TC.StateEntry.format(next), TC.Scanning{1n+member, left, TC.Blank{}, added})),
            StateProof.scan_append(TC.StateEntry.format(next), TC.Entries.format.rest(later) ++ after,
              TC.Scanning{1n+member, left, TC.Blank{}, added})) :
            {TC.Scan.finish(_) == Done{TC.TraceState{all, evidence}} : Result<&2, &2, TC.StateError, TC.TraceState>}
          %Equal.sym(TC.Scan,
            TC.Scan.text(TC.StateEntry.format(next), TC.Scanning{1n+member, left, TC.Blank{}, added}),
            TC.Scanning{1n+member, left, TC.InValue{TC.StateEntry.key_text(next),
              String.reverse(TC.StateValue.to_string(TC.StateEntry.value(next)))}, added},
            StateProof.read_entry(next, 1n+member, left, added)) :
            {TC.Scan.finish(TC.Scan.text(TC.Entries.format.rest(later) ++ after, _)) ==
              Done{TC.TraceState{all, evidence}} : Result<&2, &2, TC.StateError, TC.TraceState>}
          read_rest_ows(later, next, 1n+member, left, added, all, evidence,
            Equal.trans(List<&2, TC.StateEntry>, List.append(&2, TC.StateEntry, added, Con{next, later}),
              List.append(&2, TC.StateEntry, entries, Con{current, Con{next, later}}), all,
              ListsProof.append_assoc(TC.StateEntry, entries, Con{current, Nil{}}, Con{next, later}), split),
            BoolsProof.and_right(Bool.not(TC.Entries.has_key(entries, TC.StateEntry.key_text(current))),
              TC.Entries.unique(Con{next, later}, added), unique),
            fits, after, after_ows)

# Reading a valid state's normalized value, then whitespace, from the start
# and finishing gives back the state. For the empty state only whitespace is
# read (blank_ows); otherwise the first entry is read and read_rest_ows
# reads the rest. ows_around uses it.
law ows_after:
  for entries: List<&2, TC.StateEntry>
  for +evidence: {TC.TraceState.is_valid(entries) == True{} : Bool}
  for +after: String
  for +after_ows: {Laws.all_ows(after) == True{} : Bool}
  {TC.Scan.finish(TC.Scan.text(TC.Entries.format(entries) ++ after, TC.Scan.start())) ==
    Done{TC.TraceState{entries, evidence}} : Result<&2, &2, TC.StateError, TC.TraceState>}

def ows_after(entries, evidence, after, after_ows):
  match entries:
    case Nil{}:
      %Equal.sym(TC.Scan, TC.Scan.text(after, TC.Scan.start()), TC.Scan.start(),
        blank_ows(after, after_ows, 0n, 32n, Nil{})) :
        {TC.Scan.finish(_) == Done{TC.TraceState{Nil{}, evidence}} : Result<&2, &2, TC.StateError, TC.TraceState>}
      StateProof.checked_valid(Nil{}, evidence)
    case Con{+first, +rest}:
      %Equal.sym(String, (TC.StateEntry.format(first) ++ TC.Entries.format.rest(rest)) ++ after,
        TC.StateEntry.format(first) ++ TC.Entries.format.rest(rest) ++ after,
        StringsProof.string_assoc(TC.StateEntry.format(first), TC.Entries.format.rest(rest), after)) :
        {TC.Scan.finish(TC.Scan.text(_, TC.Scan.start())) == Done{TC.TraceState{Con{first, rest}, evidence}} :
          Result<&2, &2, TC.StateError, TC.TraceState>}
      %Equal.sym(TC.Scan, TC.Scan.text(TC.StateEntry.format(first) ++ TC.Entries.format.rest(rest) ++ after,
          TC.Scan.start()),
        TC.Scan.text(TC.Entries.format.rest(rest) ++ after, TC.Scan.text(TC.StateEntry.format(first), TC.Scan.start())),
        StateProof.scan_append(TC.StateEntry.format(first), TC.Entries.format.rest(rest) ++ after, TC.Scan.start())) :
        {TC.Scan.finish(_) == Done{TC.TraceState{Con{first, rest}, evidence}} :
          Result<&2, &2, TC.StateError, TC.TraceState>}
      %Equal.sym(TC.Scan, TC.Scan.text(TC.StateEntry.format(first), TC.Scanning{0n, 32n, TC.Blank{}, Nil{}}),
        TC.Scanning{0n, 32n, TC.InValue{TC.StateEntry.key_text(first),
          String.reverse(TC.StateValue.to_string(TC.StateEntry.value(first)))}, Nil{}},
        StateProof.read_entry(first, 0n, 32n, Nil{})) :
        {TC.Scan.finish(TC.Scan.text(TC.Entries.format.rest(rest) ++ after, _)) ==
          Done{TC.TraceState{Con{first, rest}, evidence}} : Result<&2, &2, TC.StateError, TC.TraceState>}
      read_rest_ows(rest, first, 0n, 32n, Nil{}, Con{first, rest}, evidence, {==},
        BoolsProof.and_left(TC.Entries.unique(Con{first, rest}, Nil{}),
          Nat.is_le(List.length(&2, TC.StateEntry, Con{first, rest}), 32n), evidence),
        BoolsProof.and_right(TC.Entries.unique(Con{first, rest}, Nil{}),
          Nat.is_le(List.length(&2, TC.StateEntry, Con{first, rest}), 32n), evidence),
        after, after_ows)

# When `before` and `after` are optional whitespace and the text fits the
# budget, a state's normalized value between them parses to the state: the
# law ows_around, which PROOF.bend proves with it. MergeProof.parse_scan
# removes the budget check, blank_ows reads `before`, and ows_after the
# rest.
law ows_around:
  for +limits: TC.Limits
  for state: TC.TraceState
  for +before: String
  for +after: String
  for +before_ows: {Laws.all_ows(before) == True{} : Bool}
  for +after_ows: {Laws.all_ows(after) == True{} : Bool}
  for fits: {Nat.is_le(TC.Utf8.length(before ++ TC.TraceState.format(state) ++ after),
    TC.Limits.tracestate_input(limits)) == True{} : Bool}
  {TC.TraceState.parse(limits, before ++ TC.TraceState.format(state) ++ after) == Done{state} :
    Result<&2, &2, TC.StateError, TC.TraceState>}

def ows_around(limits, state, before, after, before_ows, after_ows, fits):
  match state:
    case TC.TraceState{+entries, +evidence}:
      %Equal.sym(Result<&2, &2, TC.StateError, TC.TraceState>,
        TC.TraceState.parse(limits, before ++ TC.Entries.format(entries) ++ after),
        TC.Scan.finish(TC.Scan.text(before ++ TC.Entries.format(entries) ++ after, TC.Scan.start())),
        MergeProof.parse_scan(limits, before ++ TC.Entries.format(entries) ++ after, fits)) :
        {_ == Done{TC.TraceState{entries, evidence}} : Result<&2, &2, TC.StateError, TC.TraceState>}
      %Equal.sym(TC.Scan, TC.Scan.text(before ++ TC.Entries.format(entries) ++ after, TC.Scan.start()),
        TC.Scan.text(TC.Entries.format(entries) ++ after, TC.Scan.text(before, TC.Scan.start())),
        StateProof.scan_append(before, TC.Entries.format(entries) ++ after, TC.Scan.start())) :
        {TC.Scan.finish(_) == Done{TC.TraceState{entries, evidence}} : Result<&2, &2, TC.StateError, TC.TraceState>}
      %Equal.sym(TC.Scan, TC.Scan.text(before, TC.Scan.start()), TC.Scan.start(),
        blank_ows(before, before_ows, 0n, 32n, Nil{})) :
        {TC.Scan.finish(TC.Scan.text(TC.Entries.format(entries) ++ after, _)) == Done{TC.TraceState{entries, evidence}} :
          Result<&2, &2, TC.StateError, TC.TraceState>}
      ows_after(entries, evidence, after, after_ows)

# Parsing a state's normalized value gives it back when it fits the budget:
# the law state_roundtrip, as the case of ows_around with no whitespace
# around the value. StringsProof.append_nil relates the value to the value
# followed by "", in the goal and in `fits`.
law roundtrip:
  for +limits: TC.Limits
  for +state: TC.TraceState
  for fits: {Nat.is_le(TC.Utf8.length(TC.TraceState.format(state)), TC.Limits.tracestate_input(limits)) == True{} :
    Bool}
  {TC.TraceState.parse(limits, TC.TraceState.format(state)) == Done{state} :
    Result<&2, &2, TC.StateError, TC.TraceState>}

def roundtrip(limits, state, fits):
  %StringsProof.append_nil(TC.TraceState.format(state)) :
    {TC.TraceState.parse(limits, _) == Done{state} : Result<&2, &2, TC.StateError, TC.TraceState>}
  ows_around(limits, state, "", "", {==}, {==},
    %Equal.sym(String, TC.TraceState.format(state) ++ "", TC.TraceState.format(state),
      StringsProof.append_nil(TC.TraceState.format(state))) :
      {Nat.is_le(TC.Utf8.length(_), TC.Limits.tracestate_input(limits)) == True{} : Bool}
    fits)
