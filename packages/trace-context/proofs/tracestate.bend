# Proofs: tracestate entries, budgets and repeated fields
# =======================================================
#
# Properties of the Level 2 tracestate code of trace_context.bend. The
# character classes (StateChar.*) rule out a comma or "=" in a key, a comma in
# a value, and optional whitespace at a key's start or a value's end.
# StateKey.parse and StateValue.parse accept exactly the texts of keys and
# values. The reading machine (Scan.*, Member.*) reads an entry's text into a
# pending member and closes that member into the entry, Value.restore giving
# the value back without trailing whitespace. The measure Utf8.left agrees
# with Utf8.length, and repeated fields are measured and read as their
# comma-joined text.
#
# PROOF.bend proves the laws key_parse and value_parse with key_view and
# value_view, and key_roundtrip, value_roundtrip (section 8 of LAWS.bend),
# over_budget, within_budgets and fields_join (section 10) with the lemmas of
# the same names. The other tracestate laws build on this module:
# key_separators, value_separators, state_roundtrip and ows_around in
# proofs/normal.bend, later_duplicate, later_new_key and full_state in
# proofs/merge.bend, and first_wins in proofs/first.bend.
#
# A parse is proved through a view (KeyView, ValueView), first for a Bool
# parameter in place of the grammar check, so that the proof can match on it;
# a round trip rewrites the evidence stored in the value with `%q@`. Reading
# follows the machine one character at a time: scan_append splits a text into
# parts, and each part is read by induction on the text along the recursion
# of its grammar check (read_key_rest, read_value), while CharsProof.differs
# rules out, character by character, the separators and whitespace that the
# machine tests for. The state proofs apply read_entry, then close_keep or
# close_entry, to each entry and end with checked_valid. Budgets follow by
# induction on the text (left_take, within), and repeated fields by induction
# on the fields after the first (left_join, scan_join, fields_join).

import Base
import ../trace_context.bend as TC
import ./chars.bend as CharsProof
import ./strings.bend as StringsProof
import ./bools.bend as BoolsProof

# Character classes
# =================
#
# CharsProof.differs (proofs/chars.bend) shows that two characters differ
# when a class of StateChar.* accepts one and refuses the other. Every
# separator and whitespace lemma of this module is built on it.

# A key's first character is not optional whitespace: when
# StateChar.is_key_start accepts `char`, StateChar.is_ows refuses it. So
# Member.start, which skips whitespace, starts the key with that character
# (read_entry_text).
law key_start_not_ows:
  for +char: Char
  for +holds: {TC.StateChar.is_key_start(char) == True{} : Bool}
  {TC.StateChar.is_ows(char) == False{} : Bool}

def key_start_not_ows(char, holds):
  %Equal.sym(Bool, Char.is_eq(char, ' '), False{}, CharsProof.differs(x => TC.StateChar.is_key_start(x), char, ' ', holds, {==})) :
    {Bool.or(_, Char.is_eq(char, '\t')) == False{} : Bool}
  %Equal.sym(Bool, Char.is_eq(char, '\t'), False{}, CharsProof.differs(x => TC.StateChar.is_key_start(x), char, '\t', holds, {==})) :
    {Bool.or(False{}, _) == False{} : Bool}
  {==}

# A value's last character is not optional whitespace: when
# StateChar.is_value_end accepts `char`, StateChar.is_ows refuses it. So
# Value.restore, which drops trailing whitespace, keeps a valid value whole
# (restore_value).
law value_end_not_ows:
  for +char: Char
  for +holds: {TC.StateChar.is_value_end(char) == True{} : Bool}
  {TC.StateChar.is_ows(char) == False{} : Bool}

def value_end_not_ows(char, holds):
  %Equal.sym(Bool, Char.is_eq(char, ' '), False{}, CharsProof.differs(x => TC.StateChar.is_value_end(x), char, ' ', holds, {==})) :
    {Bool.or(_, Char.is_eq(char, '\t')) == False{} : Bool}
  %Equal.sym(Bool, Char.is_eq(char, '\t'), False{}, CharsProof.differs(x => TC.StateChar.is_value_end(x), char, '\t', holds, {==})) :
    {Bool.or(False{}, _) == False{} : Bool}
  {==}

# Keys and values
# ===============
#
# StateKey.parse and StateValue.parse accept exactly the texts of keys and
# values and give back the key or value a text came from; Scan.validate does
# the same for the two texts of an entry.

# The view of a key parse of `text`: Unit for a failure, and for a success,
# that the key's text is `text`. key_view proves it for every text, and
# Laws.key_parse rewrites its hypothesis into it to prove law key_parse.
def KeyView(text: String, result: Result<&2, &2, TC.EntryError, TC.StateKey>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{key}:
      {TC.StateKey.to_string(key) == text : String}

# When `evidence` says that StateKey.is_valid(text) is `valid`, KeyView holds
# for StateKey.parse.checked(text, valid, evidence): for True the key built is
# StateKey{text, evidence}, whose text is `text`, and for False the result is
# a failure. The Bool is a parameter, with an equation about it, so that the
# proof can match on it; key_view supplies the check itself.
law key_step:
  for -text: String
  for valid: Bool
  for evidence: {TC.StateKey.is_valid(text) == valid : Bool}
  KeyView(text, TC.StateKey.parse.checked(text, valid, evidence))

def key_step(text, valid, evidence):
  match valid:
    case True{}:
      {==}
    case False{}:
      Unit{}

# KeyView holds for StateKey.parse and every text: an accepted key is exactly
# its input. It is key_step with the check StateKey.is_valid(text) and {==},
# which is how StateKey.parse calls StateKey.parse.checked. Laws.key_parse
# uses it.
law key_view:
  for +text: String
  KeyView(text, TC.StateKey.parse(text))

def key_view(text):
  key_step(text, TC.StateKey.is_valid(text), {==})

# StateKey.parse accepts the text of every key and gives back that same key,
# evidence included. Laws.key_roundtrip proves law key_roundtrip with it, and
# entry_roundtrip uses it for an entry's key.
law key_roundtrip:
  for key: TC.StateKey
  {TC.StateKey.parse(TC.StateKey.to_string(key)) == Done{key} : Result<&2, &2, TC.EntryError, TC.StateKey>}

# Rewrites with `%q@evidence`, which also puts the {==} of StateKey.parse in
# place of the stored proof: the goal becomes StateKey.parse's definition.
def key_roundtrip(key):
  match key:
    case TC.StateKey{+text, evidence}:
      %q@evidence : {TC.StateKey.parse(text) == TC.StateKey.parse.checked(text, _, q) :
        Result<&2, &2, TC.EntryError, TC.StateKey>}
      {==}

# The view of a value parse of `text`: Unit for a failure, and for a success,
# that the value's text is `text`. As KeyView, for law value_parse.
def ValueView(text: String, result: Result<&2, &2, TC.EntryError, TC.StateValue>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{value}:
      {TC.StateValue.to_string(value) == text : String}

# As key_step, for values: when `evidence` says that StateValue.is_valid(text)
# is `valid`, ValueView holds for StateValue.parse.checked(text, valid,
# evidence). value_view supplies the check itself.
law value_step:
  for -text: String
  for valid: Bool
  for evidence: {TC.StateValue.is_valid(text) == valid : Bool}
  ValueView(text, TC.StateValue.parse.checked(text, valid, evidence))

def value_step(text, valid, evidence):
  match valid:
    case True{}:
      {==}
    case False{}:
      Unit{}

# ValueView holds for StateValue.parse and every text: an accepted value is
# exactly its input, leading spaces included. Laws.value_parse uses it.
law value_view:
  for +text: String
  ValueView(text, TC.StateValue.parse(text))

def value_view(text):
  value_step(text, TC.StateValue.is_valid(text), {==})

# StateValue.parse accepts the text of every value and gives back that same
# value, evidence included. Laws.value_roundtrip proves law value_roundtrip
# with it, and entry_roundtrip uses it for an entry's value.
law value_roundtrip:
  for value: TC.StateValue
  {TC.StateValue.parse(TC.StateValue.to_string(value)) == Done{value} : Result<&2, &2, TC.EntryError, TC.StateValue>}

# As key_roundtrip: rewrites with `%q@evidence`.
def value_roundtrip(value):
  match value:
    case TC.StateValue{+text, evidence}:
      %q@evidence : {TC.StateValue.parse(text) == TC.StateValue.parse.checked(text, _, q) :
        Result<&2, &2, TC.EntryError, TC.StateValue>}
      {==}

# The Result continuations of Scan.validate, named for the rewrite motives of
# entry_roundtrip. entry_after_key is Scan.validate after the key text has
# been parsed to the result `key`: entry_after_key(TC.StateKey.parse(k), v)
# unfolds to the same term as TC.Scan.validate(k, v), so a motive can mark
# the key's parse result with `_`.
def entry_after_key(key: Result<&2, &2, TC.EntryError, TC.StateKey>, value: String) ->
  Result<&2, &2, TC.EntryError, TC.StateEntry>:
  do Result<&2, &2, TC.EntryError, TC.StateEntry>:
    parsed_key : TC.StateKey <- key
    parsed_value : TC.StateValue <- TC.StateValue.parse(value)
    return TC.StateEntry{parsed_key, parsed_value}

# Scan.validate after the key was accepted as `key` and the value text parsed
# to the result `value`: the entry when `value` is Done. The motive of the
# second rewrite of entry_roundtrip.
def entry_after_value(key: TC.StateKey, value: Result<&2, &2, TC.EntryError, TC.StateValue>) ->
  Result<&2, &2, TC.EntryError, TC.StateEntry>:
  do Result<&2, &2, TC.EntryError, TC.StateEntry>:
    parsed_value : TC.StateValue <- value
    return TC.StateEntry{key, parsed_value}

# Validating the texts of an entry's key and value gives back that entry:
# Scan.validate accepts both, and the key and value it rebuilds carry the
# entry's own evidence. close_restored uses it to validate a member whose
# texts are those of an entry.
law entry_roundtrip:
  for entry: TC.StateEntry
  {TC.Scan.validate(TC.StateEntry.key_text(entry), TC.StateValue.to_string(TC.StateEntry.value(entry))) ==
    Done{entry} : Result<&2, &2, TC.EntryError, TC.StateEntry>}

# Rewrites the key's parse, then the value's, into Done through the motives
# entry_after_key and entry_after_value.
def entry_roundtrip(entry):
  match entry:
    case TC.StateEntry{+key, +value}:
      %Equal.sym(Result<&2, &2, TC.EntryError, TC.StateKey>, TC.StateKey.parse(TC.StateKey.to_string(key)), Done{key},
        key_roundtrip(key)) :
        {entry_after_key(_, TC.StateValue.to_string(value)) == Done{TC.StateEntry{key, value}} :
          Result<&2, &2, TC.EntryError, TC.StateEntry>}
      %Equal.sym(Result<&2, &2, TC.EntryError, TC.StateValue>, TC.StateValue.parse(TC.StateValue.to_string(value)),
        Done{value}, value_roundtrip(value)) :
        {entry_after_value(key, _) == Done{TC.StateEntry{key, value}} : Result<&2, &2, TC.EntryError, TC.StateEntry>}
      {==}

# Reading an entry
# ================
#
# The machine keeps the text of the member being read most recent first, and
# puts the key back in reading order at "=". From a Blank member, reading
# `key=value` leaves the entry pending in InValue (read_entry_text,
# read_entry). scan_append and text_cons split a reading into parts.

# A stopped scan stays stopped: reading any text after the first problem
# changes nothing. scan_append and text_cons use it in their Stopped cases.
law scan_stopped:
  for text: String
  for -error: TC.StateError
  {TC.Scan.text(text, TC.Stopped{error}) == TC.Stopped{error} : TC.Scan}

# Scan.text computes only once its text is a constructor, even for a stopped
# scan, so the proof splits on the text; each case holds by computation.
def scan_stopped(text, error):
  match text:
    case SNil{}:
      {==}
    case SCon{char, tail}:
      {==}

# Reading a concatenation reads its parts in order: from any scan, reading
# a ++ b is reading `b` after `a`. It lets a proof read a formatted value
# piece by piece: read_entry_text and scan_join here, and the state proofs of
# proofs/normal.bend, merge.bend and first.bend.
law scan_append:
  for a: String
  for b: String
  for scan: TC.Scan
  {TC.Scan.text(a ++ b, scan) == TC.Scan.text(b, TC.Scan.text(a, scan)) : TC.Scan}

def scan_append(a, b, scan):
  match a:
    case SNil{}:
      match scan:
        case TC.Stopped{error}:
          {==}
        case TC.Scanning{member, room, current, entries}:
          {==}
    case SCon{char, tail}:
      match scan:
        case TC.Stopped{error}:
          Equal.sym(TC.Scan, TC.Scan.text(b, TC.Stopped{error}), TC.Stopped{error}, scan_stopped(b, error))
        case TC.Scanning{member, room, current, entries}:
          scan_append(tail, b, TC.Scan.char(char, TC.Scanning{member, room, current, entries}))

# Reading a text that starts with `char` reads `char` with Scan.char, then
# the rest, from any scan. This is the definition of Scan.text for a scan
# still reading; a stopped one needs scan_stopped. scan_join uses it for the
# comma between two fields.
law text_cons:
  for -char: Char
  for text: String
  for scan: TC.Scan
  {TC.Scan.text(SCon{char, text}, scan) == TC.Scan.text(text, TC.Scan.char(char, scan)) : TC.Scan}

def text_cons(char, text, scan):
  match scan:
    case TC.Stopped{error}:
      Equal.sym(TC.Scan, TC.Scan.text(text, TC.Stopped{error}), TC.Stopped{error}, scan_stopped(text, error))
    case TC.Scanning{member, room, current, entries}:
      {==}

# A key character is not a comma: when StateChar.is_key accepts `char`,
# Char.is_eq(char, ',') is False. So Scan.read does not end the member inside
# a key (read_key_rest).
law key_not_comma:
  for +char: Char
  for holds: {TC.StateChar.is_key(char) == True{} : Bool}
  {Char.is_eq(char, ',') == False{} : Bool}

def key_not_comma(char, holds):
  CharsProof.differs(x => TC.StateChar.is_key(x), char, ',', holds, {==})

# A key character is not "=": when StateChar.is_key accepts `char`,
# Char.is_eq(char, '=') is False. So Member.key does not end the key early
# (read_key_rest).
law key_not_equals:
  for +char: Char
  for holds: {TC.StateChar.is_key(char) == True{} : Bool}
  {Char.is_eq(char, '=') == False{} : Bool}

def key_not_equals(char, holds):
  CharsProof.differs(x => TC.StateChar.is_key(x), char, '=', holds, {==})

# The characters after a key's first are key characters: each one extends it.
# When `text` passes StateKey.valid.rest with `room`, reading it inside a key
# pushes each character onto the key text `acc`, most recent first; none is a
# comma or "=", so neither the member nor the key ends. `room` only bounds the
# check: with characters left but no room, `valid` proves False == True, and
# BoolsProof.absurd dismisses the case. read_entry_text uses it.
law read_key_rest:
  for text: String
  for room: Nat
  for +valid: {TC.StateKey.valid.rest(text, room) == True{} : Bool}
  for member: Nat
  for allowed: Nat
  for acc: String
  for entries: List<&2, TC.StateEntry>
  {TC.Scan.text(text, TC.Scanning{member, allowed, TC.InKey{acc}, entries}) ==
    TC.Scanning{member, allowed, TC.InKey{String.reverse.go(text, acc)}, entries} : TC.Scan}

def read_key_rest(text, room, valid, member, allowed, acc, entries):
  match text:
    case SNil{}:
      {==}
    case SCon{+char, tail}:
      match room:
        case 0n:
          BoolsProof.absurd({TC.Scan.text(SCon{char, tail}, TC.Scanning{member, allowed, TC.InKey{acc}, entries}) ==
            TC.Scanning{member, allowed, TC.InKey{String.reverse.go(SCon{char, tail}, acc)}, entries} : TC.Scan}, valid)
        case 1n+more:
          +key_char = BoolsProof.and_left(TC.StateChar.is_key(char), TC.StateKey.valid.rest(tail, more), valid)
          %Equal.sym(Bool, Char.is_eq(char, ','), False{}, key_not_comma(char, key_char)) :
            {TC.Scan.text(tail, TC.Scan.read(_, char, member, allowed, TC.InKey{acc}, entries)) ==
              TC.Scanning{member, allowed, TC.InKey{String.reverse.go(tail, SCon{char, acc})}, entries} : TC.Scan}
          %Equal.sym(Bool, Char.is_eq(char, '='), False{}, key_not_equals(char, key_char)) :
            {TC.Scan.text(tail, TC.Scanning{member, allowed, TC.Member.key(_, char, acc), entries}) ==
              TC.Scanning{member, allowed, TC.InKey{String.reverse.go(tail, SCon{char, acc})}, entries} : TC.Scan}
          read_key_rest(tail, more,
            BoolsProof.and_right(TC.StateChar.is_key(char), TC.StateKey.valid.rest(tail, more), valid),
            member, allowed, SCon{char, acc}, entries)

# A value character is not a comma: when StateChar.is_value accepts `char`,
# Char.is_eq(char, ',') is False. read_value uses it for every character of a
# value but the last.
law value_not_comma:
  for +char: Char
  for holds: {TC.StateChar.is_value(char) == True{} : Bool}
  {Char.is_eq(char, ',') == False{} : Bool}

def value_not_comma(char, holds):
  CharsProof.differs(x => TC.StateChar.is_value(x), char, ',', holds, {==})

# A value's last character is not a comma: when StateChar.is_value_end
# accepts `char`, Char.is_eq(char, ',') is False. read_value uses it for the
# last character.
law value_end_not_comma:
  for +char: Char
  for holds: {TC.StateChar.is_value_end(char) == True{} : Bool}
  {Char.is_eq(char, ',') == False{} : Bool}

def value_end_not_comma(char, holds):
  CharsProof.differs(x => TC.StateChar.is_value_end(x), char, ',', holds, {==})

# A value's characters are never commas: each one extends the value. When
# `char` followed by `tail` passes StateValue.valid.go with `room`, reading
# them inside a value pushes each one onto the value text `acc`, most recent
# first. The statement has the check's shape, a character and the rest, as
# the last character has its own class (StateChar.is_value_end); running out
# of room contradicts `valid`, as in read_key_rest. read_entry_text uses it.
law read_value:
  for tail: String
  for +char: Char
  for room: Nat
  for +valid: {TC.StateValue.valid.go(tail, char, room) == True{} : Bool}
  for member: Nat
  for allowed: Nat
  for key: String
  for acc: String
  for entries: List<&2, TC.StateEntry>
  {TC.Scan.text(SCon{char, tail}, TC.Scanning{member, allowed, TC.InValue{key, acc}, entries}) ==
    TC.Scanning{member, allowed, TC.InValue{key, String.reverse.go(SCon{char, tail}, acc)}, entries} : TC.Scan}

def read_value(tail, char, room, valid, member, allowed, key, acc, entries):
  match tail:
    case SNil{}:
      %Equal.sym(Bool, Char.is_eq(char, ','), False{}, value_end_not_comma(char, valid)) :
        {TC.Scan.text(SNil{}, TC.Scan.read(_, char, member, allowed, TC.InValue{key, acc}, entries)) ==
          TC.Scanning{member, allowed, TC.InValue{key, SCon{char, acc}}, entries} : TC.Scan}
      {==}
    case SCon{+next, +rest}:
      match room:
        case 0n:
          BoolsProof.absurd({TC.Scan.text(SCon{char, SCon{next, rest}}, TC.Scanning{member, allowed, TC.InValue{key, acc}, entries}) ==
            TC.Scanning{member, allowed, TC.InValue{key, String.reverse.go(SCon{char, SCon{next, rest}}, acc)}, entries} :
            TC.Scan}, valid)
        case 1n+more:
          %Equal.sym(Bool, Char.is_eq(char, ','), False{}, value_not_comma(char,
            BoolsProof.and_left(TC.StateChar.is_value(char), TC.StateValue.valid.go(rest, next, more), valid))) :
            {TC.Scan.text(SCon{next, rest}, TC.Scan.read(_, char, member, allowed, TC.InValue{key, acc}, entries)) ==
              TC.Scanning{member, allowed, TC.InValue{key, String.reverse.go(SCon{next, rest}, SCon{char, acc})}, entries} :
              TC.Scan}
          read_value(rest, next, more,
            BoolsProof.and_right(TC.StateChar.is_value(char), TC.StateValue.valid.go(rest, next, more), valid),
            member, allowed, key, SCon{char, acc}, entries)

# An entry's text, read after a comma or at the start, leaves the entry
# pending in the current member. When `key` and `value` pass the key and value
# checks, reading `key=value` from a Blank member gives InValue with `key` in
# reading order and `value` most recent first; no member ends, so the member
# number, the room and the kept entries do not change. read_entry restates it
# for a StateEntry.
law read_entry_text:
  for key: String
  for +key_valid: {TC.StateKey.is_valid(key) == True{} : Bool}
  for value: String
  for +value_valid: {TC.StateValue.is_valid(value) == True{} : Bool}
  for +member: Nat
  for +allowed: Nat
  for +entries: List<&2, TC.StateEntry>
  {TC.Scan.text(key ++ "=" ++ value, TC.Scanning{member, allowed, TC.Blank{}, entries}) ==
    TC.Scanning{member, allowed, TC.InValue{key, String.reverse(value)}, entries} : TC.Scan}

# Follows the machine through the key, "=" and the value, split with
# scan_append; StringsProof.reverse_twice undoes the key's double reversal.
def read_entry_text(key, key_valid, value, value_valid, member, allowed, entries):
  match key:
    case SNil{}:
      BoolsProof.absurd({TC.Scan.text(SNil{} ++ "=" ++ value, TC.Scanning{member, allowed, TC.Blank{}, entries}) ==
        TC.Scanning{member, allowed, TC.InValue{SNil{}, String.reverse(value)}, entries} : TC.Scan}, key_valid)
    case SCon{+first, +rest}:
      match value:
        case SNil{}:
          BoolsProof.absurd({TC.Scan.text(SCon{first, rest} ++ "=" ++ SNil{}, TC.Scanning{member, allowed, TC.Blank{}, entries}) ==
            TC.Scanning{member, allowed, TC.InValue{SCon{first, rest}, String.reverse(SNil{})}, entries} : TC.Scan},
            value_valid)
        case SCon{+value_first, +value_rest}:
          +start = BoolsProof.and_left(TC.StateChar.is_key_start(first), TC.StateKey.valid.rest(rest, 255n), key_valid)
          %Equal.sym(Bool, Char.is_eq(first, ','), False{},
            CharsProof.differs(x => TC.StateChar.is_key_start(x), first, ',', start, {==})) :
            {TC.Scan.text(rest ++ "=" ++ SCon{value_first, value_rest},
              TC.Scan.read(_, first, member, allowed, TC.Blank{}, entries)) ==
              TC.Scanning{member, allowed, TC.InValue{SCon{first, rest},
                String.reverse(SCon{value_first, value_rest})}, entries} : TC.Scan}
          %Equal.sym(Bool, TC.StateChar.is_ows(first), False{}, key_start_not_ows(first, start)) :
            {TC.Scan.text(rest ++ "=" ++ SCon{value_first, value_rest},
              TC.Scanning{member, allowed, TC.Member.start(_, Char.is_eq(first, '='), first), entries}) ==
              TC.Scanning{member, allowed, TC.InValue{SCon{first, rest},
                String.reverse(SCon{value_first, value_rest})}, entries} : TC.Scan}
          %Equal.sym(Bool, Char.is_eq(first, '='), False{},
            CharsProof.differs(x => TC.StateChar.is_key_start(x), first, '=', start, {==})) :
            {TC.Scan.text(rest ++ "=" ++ SCon{value_first, value_rest},
              TC.Scanning{member, allowed, TC.Member.start(False{}, _, first), entries}) ==
              TC.Scanning{member, allowed, TC.InValue{SCon{first, rest},
                String.reverse(SCon{value_first, value_rest})}, entries} : TC.Scan}
          %Equal.sym(TC.Scan,
            TC.Scan.text(rest ++ "=" ++ SCon{value_first, value_rest},
              TC.Scanning{member, allowed, TC.InKey{SCon{first, SNil{}}}, entries}),
            TC.Scan.text("=" ++ SCon{value_first, value_rest},
              TC.Scan.text(rest, TC.Scanning{member, allowed, TC.InKey{SCon{first, SNil{}}}, entries})),
            scan_append(rest, "=" ++ SCon{value_first, value_rest},
              TC.Scanning{member, allowed, TC.InKey{SCon{first, SNil{}}}, entries})) :
            {_ == TC.Scanning{member, allowed, TC.InValue{SCon{first, rest},
              String.reverse(SCon{value_first, value_rest})}, entries} : TC.Scan}
          %Equal.sym(TC.Scan,
            TC.Scan.text(rest, TC.Scanning{member, allowed, TC.InKey{SCon{first, SNil{}}}, entries}),
            TC.Scanning{member, allowed, TC.InKey{String.reverse.go(rest, SCon{first, SNil{}})}, entries},
            read_key_rest(rest, 255n, BoolsProof.and_right(TC.StateChar.is_key_start(first),
              TC.StateKey.valid.rest(rest, 255n), key_valid), member, allowed, SCon{first, SNil{}}, entries)) :
            {TC.Scan.text("=" ++ SCon{value_first, value_rest}, _) ==
              TC.Scanning{member, allowed, TC.InValue{SCon{first, rest},
                String.reverse(SCon{value_first, value_rest})}, entries} : TC.Scan}
          %Equal.sym(TC.Scan,
            TC.Scan.text(SCon{value_first, value_rest}, TC.Scanning{member, allowed,
              TC.InValue{String.reverse(String.reverse.go(rest, SCon{first, SNil{}})), ""}, entries}),
            TC.Scanning{member, allowed, TC.InValue{String.reverse(String.reverse.go(rest, SCon{first, SNil{}})),
              String.reverse.go(SCon{value_first, value_rest}, "")}, entries},
            read_value(value_rest, value_first, 255n, value_valid, member, allowed,
              String.reverse(String.reverse.go(rest, SCon{first, SNil{}})), "", entries)) :
            {_ == TC.Scanning{member, allowed, TC.InValue{SCon{first, rest},
              String.reverse(SCon{value_first, value_rest})}, entries} : TC.Scan}
          %Equal.sym(String, String.reverse.go(String.reverse.go(rest, SCon{first, SNil{}}), ""),
            SCon{first, rest}, StringsProof.reverse_twice(rest, SCon{first, SNil{}})) :
            {TC.Scanning{member, allowed, TC.InValue{_, String.reverse(SCon{value_first, value_rest})}, entries} ==
              TC.Scanning{member, allowed, TC.InValue{SCon{first, rest},
                String.reverse(SCon{value_first, value_rest})}, entries} : TC.Scan}
          {==}

# read_entry_text for an entry: reading StateEntry.format(entry) from a Blank
# member leaves the entry's key text and reversed value text pending, the
# entry's evidence supplying both checks. The state proofs of
# proofs/normal.bend, merge.bend and first.bend use it for each entry.
law read_entry:
  for entry: TC.StateEntry
  for member: Nat
  for allowed: Nat
  for entries: List<&2, TC.StateEntry>
  {TC.Scan.text(TC.StateEntry.format(entry), TC.Scanning{member, allowed, TC.Blank{}, entries}) ==
    TC.Scanning{member, allowed, TC.InValue{TC.StateEntry.key_text(entry),
      String.reverse(TC.StateValue.to_string(TC.StateEntry.value(entry)))}, entries} : TC.Scan}

def read_entry(entry, member, allowed, entries):
  match entry:
    case TC.StateEntry{TC.StateKey{key, key_valid}, TC.StateValue{value, value_valid}}:
      read_entry_text(key, key_valid, value, value_valid, member, allowed, entries)

# Ending a member
# ===============
#
# At a comma or at the end of the value, Scan.close restores the pending
# value text with Value.restore, validates the member, counts it and keeps
# its entry when its key is new. For an entry read from its own text, this
# gives back that entry.

# Once a character other than whitespace is kept, restoring reverses the rest:
# with its flag True, Value.restore.go pushes every remaining character onto
# `acc`, as String.reverse.go does. restore_value uses it once the value's
# last character is kept.
law restore_kept:
  for text: String
  for acc: String
  {TC.Value.restore.go(text, (True{}, acc)) == String.reverse.go(text, acc) : String}

def restore_kept(text, acc):
  match text:
    case SNil{}:
      {==}
    case SCon{char, tail}:
      restore_kept(tail, SCon{char, acc})

# A value ends with a character other than whitespace, so restoring the
# reversed value drops nothing. When `char` followed by `tail` passes
# StateValue.valid.go, String.reverse.go(tail, SCon{char, acc}) starts with
# the last character of SCon{char, tail}, and restoring it gives its whole
# reversal. `acc` holds the characters before `char`, most recent first, so
# the induction on `tail` can move `char` into it. restore_reversed uses it.
law restore_value:
  for tail: String
  for +char: Char
  for acc: String
  for room: Nat
  for +valid: {TC.StateValue.valid.go(tail, char, room) == True{} : Bool}
  {TC.Value.restore.go(String.reverse.go(tail, SCon{char, acc}), (False{}, "")) ==
    String.reverse.go(String.reverse.go(tail, SCon{char, acc}), "") : String}

def restore_value(tail, char, acc, room, valid):
  match tail:
    case SNil{}:
      %Equal.sym(Bool, TC.StateChar.is_ows(char), False{}, value_end_not_ows(char, valid)) :
        {TC.Value.restore.go(acc, TC.Value.restore.step(False{}, _, char, "")) ==
          String.reverse.go(acc, SCon{char, ""}) : String}
      restore_kept(acc, SCon{char, ""})
    case SCon{+next, +rest}:
      match room:
        case 0n:
          BoolsProof.absurd({TC.Value.restore.go(String.reverse.go(SCon{next, rest}, SCon{char, acc}), (False{}, "")) ==
            String.reverse.go(String.reverse.go(SCon{next, rest}, SCon{char, acc}), "") : String}, valid)
        case 1n+more:
          restore_value(rest, next, SCon{char, acc}, more,
            BoolsProof.and_right(TC.StateChar.is_value(char), TC.StateValue.valid.go(rest, next, more), valid))

# Restoring the reversal of a valid value gives the value back: the machine
# keeps a value most recent first, and Value.restore (Value.restore.go from
# (False{}, "")) returns it in order without dropping anything. close_keep and
# proofs/normal.bend (close_entry_ows) use it.
law restore_reversed:
  for value: String
  for +valid: {TC.StateValue.is_valid(value) == True{} : Bool}
  {TC.Value.restore.go(String.reverse(value), (False{}, "")) == value : String}

def restore_reversed(value, valid):
  match value:
    case SNil{}:
      {==}
    case SCon{+first, +rest}:
      Equal.trans(String, TC.Value.restore.go(String.reverse.go(rest, SCon{first, SNil{}}), (False{}, "")),
        String.reverse.go(String.reverse.go(rest, SCon{first, SNil{}}), ""), SCon{first, rest},
        restore_value(rest, first, "", 255n, valid), StringsProof.reverse_twice(rest, SCon{first, SNil{}}))

# A member whose value text restores to a valid value ends with the member
# count and duplicate checks. When the pending `text` restores to `value`,
# closing InValue{StateKey.to_string(key), text} validates it into the entry
# of `key` and `value`, and only Scan.keep remains. `text` may be any pending
# text, not only the reversed value: proofs/normal.bend (close_entry_ows)
# closes a value followed by optional whitespace. close_keep is the case
# without whitespace.
law close_restored:
  for +key: TC.StateKey
  for +value: String
  for +value_valid: {TC.StateValue.is_valid(value) == True{} : Bool}
  for +text: String
  for restored: {TC.Value.restore(text) == value : String}
  for +member: Nat
  for +room: Nat
  for +entries: List<&2, TC.StateEntry>
  {TC.Scan.close(member, room, TC.InValue{TC.StateKey.to_string(key), text}, entries) ==
    TC.Scan.keep(room, member, TC.StateEntry{key, TC.StateValue{value, value_valid}}, entries) : TC.Scan}

def close_restored(key, value, value_valid, text, restored, member, room, entries):
  +entry = {TC.StateEntry{key, TC.StateValue{value, value_valid}} : TC.StateEntry}
  %Equal.sym(String, TC.Value.restore(text), value, restored) :
    {TC.Scan.entry(TC.Scan.validate(TC.StateKey.to_string(key), _), member, room, entries) ==
      TC.Scan.keep(room, member, entry, entries) : TC.Scan}
  %Equal.sym(Result<&2, &2, TC.EntryError, TC.StateEntry>, TC.Scan.validate(TC.StateKey.to_string(key), value),
    Done{entry}, entry_roundtrip(entry)) :
    {TC.Scan.entry(_, member, room, entries) == TC.Scan.keep(room, member, entry, entries) : TC.Scan}
  {==}

# An entry read from its own text ends its member with Scan.keep of that
# entry: closing the member that read_entry leaves validates it back into
# `entry`, so only the member count and duplicate check remain. close_entry,
# proofs/merge.bend and proofs/first.bend use it.
law close_keep:
  for entry: TC.StateEntry
  for +member: Nat
  for +room: Nat
  for +entries: List<&2, TC.StateEntry>
  {TC.Scan.close(member, room, TC.InValue{TC.StateEntry.key_text(entry),
      String.reverse(TC.StateValue.to_string(TC.StateEntry.value(entry)))}, entries) ==
    TC.Scan.keep(room, member, entry, entries) : TC.Scan}

def close_keep(entry, member, room, entries):
  match entry:
    case TC.StateEntry{key, TC.StateValue{+value, +value_valid}}:
      close_restored(key, value, value_valid, String.reverse(value), restore_reversed(value, value_valid),
        member, room, entries)

# A new key is added after the entries kept so far: with room for another
# member and no kept entry with the entry's key (`absent`), Scan.keep counts
# the member, uses up one unit of room and appends the entry. close_entry and
# proofs/normal.bend (close_entry_ows) use it.
law keep_added:
  for member: Nat
  for left: Nat
  for +entry: TC.StateEntry
  for +entries: List<&2, TC.StateEntry>
  for absent: {TC.Entries.has_key(entries, TC.StateEntry.key_text(entry)) == False{} : Bool}
  {TC.Scan.keep(1n+left, member, entry, entries) ==
    TC.Scanning{1n+member, left, TC.Blank{}, List.append(&2, TC.StateEntry, entries, Con{entry, Nil{}})} : TC.Scan}

def keep_added(member, left, entry, entries, absent):
  %Equal.sym(Bool, TC.Entries.has_key(entries, TC.StateEntry.key_text(entry)), False{}, absent) :
    {TC.Scanning{1n+member, left, TC.Blank{}, TC.Entries.add.if(entries, entry, _)} ==
      TC.Scanning{1n+member, left, TC.Blank{}, List.append(&2, TC.StateEntry, entries, Con{entry, Nil{}})} : TC.Scan}
  {==}

# A comma, or the end of the value, adds the pending entry when its key is new:
# with room left and `absent`, closing the member that read_entry leaves
# appends the entry, counts the member and starts a Blank one; close_keep,
# then keep_added. proofs/normal.bend (read_rest_ows) and proofs/merge.bend
# (read_closed) use it.
law close_entry:
  for +entry: TC.StateEntry
  for +member: Nat
  for +left: Nat
  for +entries: List<&2, TC.StateEntry>
  for absent: {TC.Entries.has_key(entries, TC.StateEntry.key_text(entry)) == False{} : Bool}
  {TC.Scan.close(member, 1n+left, TC.InValue{TC.StateEntry.key_text(entry),
      String.reverse(TC.StateValue.to_string(TC.StateEntry.value(entry)))}, entries) ==
    TC.Scanning{1n+member, left, TC.Blank{}, List.append(&2, TC.StateEntry, entries, Con{entry, Nil{}})} : TC.Scan}

def close_entry(entry, member, left, entries, absent):
  Equal.trans(TC.Scan, TC.Scan.close(member, 1n+left, TC.InValue{TC.StateEntry.key_text(entry),
      String.reverse(TC.StateValue.to_string(TC.StateEntry.value(entry)))}, entries),
    TC.Scan.keep(1n+left, member, entry, entries),
    TC.Scanning{1n+member, left, TC.Blank{}, List.append(&2, TC.StateEntry, entries, Con{entry, Nil{}})},
    close_keep(entry, member, 1n+left, entries), keep_added(member, left, entry, entries, absent))

# When `evidence` proves that `entries` form a valid state, the final check
# of Scan.result accepts them and returns the state holding `evidence`. The
# left side is what Scan.result computes for a scan that ended with
# `entries`. The state proofs of proofs/normal.bend, merge.bend and
# first.bend end with it.
law checked_valid:
  for +entries: List<&2, TC.StateEntry>
  for evidence: {TC.TraceState.is_valid(entries) == True{} : Bool}
  {TC.Scan.state(entries, TC.TraceState.is_valid(entries), {==}) == Done{TC.TraceState{entries, evidence}} :
    Result<&2, &2, TC.StateError, TC.TraceState>}

# As key_roundtrip: rewrites with `%q@evidence`.
def checked_valid(entries, evidence):
  %q@evidence : {TC.Scan.state(entries, TC.TraceState.is_valid(entries), {==}) ==
    TC.Scan.state(entries, _, q) : Result<&2, &2, TC.StateError, TC.TraceState>}
  {==}

# Budgets
# =======
#
# Parsing measures with Utf8.left, which stops once the budget is exceeded;
# the laws state budgets with Utf8.length. `within` relates the two, and
# Scan.within either refuses the fields or reads them as if without a budget.

# Measuring against a budget, possibly after `need` more octets, succeeds
# exactly when the text's octets and `need` fit the budget: measuring `text`
# from what Budget.take leaves after `need` octets gives Some exactly when
# need + Utf8.length(text) <= budget. `need` stands for the octets of a
# character still to be taken, which makes the induction go through; `within`
# is the case need = 0.
law left_take:
  for +text: String
  for need: Nat
  for budget: Nat
  {Maybe.is_some(&2, Nat, TC.Utf8.left(text, TC.Budget.take(need, budget))) ==
    Nat.is_le(Nat.add(need, TC.Utf8.length(text)), budget) : Bool}

# Induction on the text, then on `need` while one character's octets are
# taken from the budget one at a time.
def left_take(text, need, budget):
  match text:
    case SNil{}:
      match need:
        case 0n:
          match budget:
            case 0n:
              {==}
            case 1n+more:
              {==}
        case 1n+more:
          match budget:
            case 0n:
              {==}
            case 1n+left:
              left_take(text, more, left)
    case SCon{char, tail}:
      match need:
        case 0n:
          left_take(tail, TC.Utf8.width(char), budget)
        case 1n+more:
          match budget:
            case 0n:
              {==}
            case 1n+left:
              left_take(text, more, left)

# The measure agrees with the length: Utf8.left of `text` against `budget`
# gives Some exactly when Utf8.length(text) <= budget. Parsing measures with
# Utf8.left and the laws use Utf8.length, so over_budget, within_budgets and
# proofs/merge.bend (parse_scan) go through it.
law within:
  for +text: String
  for budget: Nat
  {Maybe.is_some(&2, Nat, TC.Utf8.left(text, Some{budget})) == Nat.is_le(TC.Utf8.length(text), budget) : Bool}

def within(text, budget):
  left_take(text, 0n, budget)

# When the measurement `m` is Some, the fields fit their budget and
# Scan.within reads them from Scan.start, as if without a budget. The None
# case contradicts `fits`. within_budgets and proofs/merge.bend (parse_scan)
# use it.
law read_fits:
  for m: Maybe<&2, Nat>
  for fields: List<&2, String>
  for fits: {Maybe.is_some(&2, Nat, m) == True{} : Bool}
  {TC.Scan.within(m, fields) == TC.Scan.finish(TC.Scan.fields(fields, TC.Scan.start())) :
    Result<&2, &2, TC.StateError, TC.TraceState>}

def read_fits(m, fields, fits):
  match m:
    case None{}:
      BoolsProof.absurd({TC.Scan.within(None{}, fields) == TC.Scan.finish(TC.Scan.fields(fields, TC.Scan.start())) :
        Result<&2, &2, TC.StateError, TC.TraceState>}, fits)
    case Some{left}:
      {==}

# When the measurement `m` is None, the fields exceed their budget and
# Scan.within refuses them with StateTooLarge, without reading them. The Some
# case contradicts `larger`. over_budget uses it.
law read_over:
  for m: Maybe<&2, Nat>
  for fields: List<&2, String>
  for larger: {Maybe.is_some(&2, Nat, m) == False{} : Bool}
  {TC.Scan.within(m, fields) == Fail{TC.StateTooLarge{}} : Result<&2, &2, TC.StateError, TC.TraceState>}

def read_over(m, fields, larger):
  match m:
    case None{}:
      {==}
    case Some{left}:
      Empty.absurd({TC.Scan.within(Some{left}, fields) == Fail{TC.StateTooLarge{}} :
        Result<&2, &2, TC.StateError, TC.TraceState>}, BoolsProof.true_ne_false(larger))

# Parsing
# =======
#
# The budget laws of section 10 of LAWS.bend, from the lemmas above.

# When Utf8.length(text) exceeds the tracestate input budget of `limits`,
# TraceState.parse refuses `text` with StateTooLarge: `within` turns the
# hypothesis into one on the measurement, and read_over concludes.
# Laws.over_budget proves law over_budget with it.
law over_budget:
  for +limits: TC.Limits
  for +text: String
  for larger: {Nat.is_le(TC.Utf8.length(text), TC.Limits.tracestate_input(limits)) == False{} : Bool}
  {TC.TraceState.parse(limits, text) == Fail{TC.StateTooLarge{}} : Result<&2, &2, TC.StateError, TC.TraceState>}

def over_budget(limits, text, larger):
  read_over(TC.Utf8.left(text, Some{TC.Limits.tracestate_input(limits)}), Con{text, Nil{}},
    Equal.trans(Bool, Maybe.is_some(&2, Nat, TC.Utf8.left(text, Some{TC.Limits.tracestate_input(limits)})),
      Nat.is_le(TC.Utf8.length(text), TC.Limits.tracestate_input(limits)), False{},
      within(text, TC.Limits.tracestate_input(limits)), larger))

# When `text` fits the tracestate input budgets of both `first` and `second`,
# TraceState.parse gives the same result with either: by `within` and
# read_fits, both equal the reading without a budget. Laws.within_budgets
# proves law within_budgets with it.
law within_budgets:
  for +first: TC.Limits
  for +second: TC.Limits
  for +text: String
  for first_fits: {Nat.is_le(TC.Utf8.length(text), TC.Limits.tracestate_input(first)) == True{} : Bool}
  for second_fits: {Nat.is_le(TC.Utf8.length(text), TC.Limits.tracestate_input(second)) == True{} : Bool}
  {TC.TraceState.parse(first, text) == TC.TraceState.parse(second, text) :
    Result<&2, &2, TC.StateError, TC.TraceState>}

def within_budgets(first, second, text, first_fits, second_fits):
  Equal.trans(Result<&2, &2, TC.StateError, TC.TraceState>,
    TC.TraceState.parse(first, text), TC.Scan.finish(TC.Scan.fields(Con{text, Nil{}}, TC.Scan.start())),
    TC.TraceState.parse(second, text),
    read_fits(TC.Utf8.left(text, Some{TC.Limits.tracestate_input(first)}), Con{text, Nil{}},
      Equal.trans(Bool, Maybe.is_some(&2, Nat, TC.Utf8.left(text, Some{TC.Limits.tracestate_input(first)})),
        Nat.is_le(TC.Utf8.length(text), TC.Limits.tracestate_input(first)), True{},
        within(text, TC.Limits.tracestate_input(first)), first_fits)),
    Equal.sym(Result<&2, &2, TC.StateError, TC.TraceState>, TC.TraceState.parse(second, text),
      TC.Scan.finish(TC.Scan.fields(Con{text, Nil{}}, TC.Scan.start())),
      read_fits(TC.Utf8.left(text, Some{TC.Limits.tracestate_input(second)}), Con{text, Nil{}},
        Equal.trans(Bool, Maybe.is_some(&2, Nat, TC.Utf8.left(text, Some{TC.Limits.tracestate_input(second)})),
          Nat.is_le(TC.Utf8.length(text), TC.Limits.tracestate_input(second)), True{},
          within(text, TC.Limits.tracestate_input(second)), second_fits))))

# Repeated fields
# ===============
#
# TraceState.parse_fields measures each field after the first together with
# the comma before it (Utf8.left_fields) and reads it after that comma
# (Scan.fields). Induction on the fields after the first shows that this is
# measuring and reading their comma-joined text (law fields_join).

# A None budget stays None: once exceeded, a budget stays exceeded through any
# text. left_append and left_more_con use it.
law left_none:
  for text: String
  {TC.Utf8.left(text, None{}) == None{} : Maybe<&2, Nat>}

# As scan_stopped: Utf8.left computes only once its text is a constructor.
def left_none(text):
  match text:
    case SNil{}:
      {==}
    case SCon{char, tail}:
      {==}

# Measuring a concatenation measures its parts in order: from any budget,
# measuring a ++ b is measuring `b` from what `a` leaves. The counterpart of
# scan_append for budgets; left_join uses it at each comma.
law left_append:
  for a: String
  for b: String
  for budget: Maybe<&2, Nat>
  {TC.Utf8.left(a ++ b, budget) == TC.Utf8.left(b, TC.Utf8.left(a, budget)) : Maybe<&2, Nat>}

def left_append(a, b, budget):
  match a:
    case SNil{}:
      match budget:
        case None{}:
          {==}
        case Some{left}:
          {==}
    case SCon{char, tail}:
      match budget:
        case None{}:
          Equal.sym(Maybe<&2, Nat>, TC.Utf8.left(b, None{}), None{}, left_none(b))
        case Some{left}:
          left_append(tail, b, TC.Budget.take(TC.Utf8.width(char), left))

# Once the budget is None, Utf8.left_more stays None, whatever the fields.
# left_more_con uses it.
law left_more_none:
  for fields: List<&2, String>
  {TC.Utf8.left_more(fields, None{}) == None{} : Maybe<&2, Nat>}

# As left_none: Utf8.left_more computes only once the list is a constructor.
def left_more_none(fields):
  match fields:
    case Nil{}:
      {==}
    case Con{field, rest}:
      {==}

# Utf8.left_more measures each field after the comma before it, whatever the
# budget. For a Some budget, this is how Utf8.left_more is defined. For None,
# Utf8.left_more stops at once, and measuring on gives None too: once
# exceeded, a budget stays exceeded through every later field (left_none,
# left_more_none). left_join uses it.
law left_more_con:
  for +field: String
  for +rest: List<&2, String>
  for budget: Maybe<&2, Nat>
  {TC.Utf8.left_more(Con{field, rest}, budget) ==
    TC.Utf8.left_more(rest, TC.Utf8.left(field, TC.Utf8.left(",", budget))) : Maybe<&2, Nat>}

def left_more_con(field, rest, budget):
  match budget:
    case None{}:
      Equal.sym(Maybe<&2, Nat>, TC.Utf8.left_more(rest, TC.Utf8.left(field, None{})), None{},
        %Equal.sym(Maybe<&2, Nat>, TC.Utf8.left(field, None{}), None{}, left_none(field)) :
          {TC.Utf8.left_more(rest, _) == None{} : Maybe<&2, Nat>}
        left_more_none(rest))
    case Some{left}:
      {==}

# Measuring a first field and then the others, each after a comma, is
# measuring their comma-joined text: String.join.go(rest, first, ",") is
# `first` followed by each field of `rest` after a comma. Induction on `rest`,
# with left_more_con and left_append. fields_left uses it.
law left_join:
  for rest: List<&2, String>
  for +first: String
  for +budget: Maybe<&2, Nat>
  {TC.Utf8.left_more(rest, TC.Utf8.left(first, budget)) == TC.Utf8.left(String.join.go(rest, first, ","), budget) :
    Maybe<&2, Nat>}

def left_join(rest, first, budget):
  match rest:
    case Nil{}:
      {==}
    case Con{+next, +later}:
      Equal.trans(Maybe<&2, Nat>, TC.Utf8.left_more(Con{next, later}, TC.Utf8.left(first, budget)),
        TC.Utf8.left_more(later, TC.Utf8.left(next, TC.Utf8.left(",", TC.Utf8.left(first, budget)))),
        TC.Utf8.left(first ++ "," ++ String.join.go(later, next, ","), budget),
        left_more_con(next, later, TC.Utf8.left(first, budget)),
      Equal.trans(Maybe<&2, Nat>,
        TC.Utf8.left_more(later, TC.Utf8.left(next, TC.Utf8.left(",", TC.Utf8.left(first, budget)))),
        TC.Utf8.left(String.join.go(later, next, ","), TC.Utf8.left(",", TC.Utf8.left(first, budget))),
        TC.Utf8.left(first ++ "," ++ String.join.go(later, next, ","), budget),
        left_join(later, next, TC.Utf8.left(",", TC.Utf8.left(first, budget))),
        Equal.sym(Maybe<&2, Nat>, TC.Utf8.left(first ++ "," ++ String.join.go(later, next, ","), budget),
          TC.Utf8.left(String.join.go(later, next, ","), TC.Utf8.left(",", TC.Utf8.left(first, budget))),
          Equal.trans(Maybe<&2, Nat>, TC.Utf8.left(first ++ "," ++ String.join.go(later, next, ","), budget),
            TC.Utf8.left("," ++ String.join.go(later, next, ","), TC.Utf8.left(first, budget)),
            TC.Utf8.left(String.join.go(later, next, ","), TC.Utf8.left(",", TC.Utf8.left(first, budget))),
            left_append(first, "," ++ String.join.go(later, next, ","), budget),
            left_append(",", String.join.go(later, next, ","), TC.Utf8.left(first, budget))))))

# The reading counterpart of left_join: from any scan, reading a first field
# and then the others, each after a comma (Scan.more), is reading their
# comma-joined text. Induction on `rest`, with scan_append and text_cons.
# fields_scan uses it.
law scan_join:
  for rest: List<&2, String>
  for +first: String
  for +scan: TC.Scan
  {TC.Scan.more(rest, TC.Scan.text(first, scan)) == TC.Scan.text(String.join.go(rest, first, ","), scan) : TC.Scan}

def scan_join(rest, first, scan):
  match rest:
    case Nil{}:
      {==}
    case Con{+next, +later}:
      Equal.trans(TC.Scan,
        TC.Scan.more(later, TC.Scan.text(next, TC.Scan.char(',', TC.Scan.text(first, scan)))),
        TC.Scan.text(String.join.go(later, next, ","), TC.Scan.char(',', TC.Scan.text(first, scan))),
        TC.Scan.text(first ++ "," ++ String.join.go(later, next, ","), scan),
        scan_join(later, next, TC.Scan.char(',', TC.Scan.text(first, scan))),
        Equal.sym(TC.Scan, TC.Scan.text(first ++ "," ++ String.join.go(later, next, ","), scan),
          TC.Scan.text(String.join.go(later, next, ","), TC.Scan.char(',', TC.Scan.text(first, scan))),
          Equal.trans(TC.Scan, TC.Scan.text(first ++ "," ++ String.join.go(later, next, ","), scan),
            TC.Scan.text("," ++ String.join.go(later, next, ","), TC.Scan.text(first, scan)),
            TC.Scan.text(String.join.go(later, next, ","), TC.Scan.char(',', TC.Scan.text(first, scan))),
            scan_append(first, "," ++ String.join.go(later, next, ","), scan),
            text_cons(',', String.join.go(later, next, ","), TC.Scan.text(first, scan)))))

# Reading repeated fields from the start is reading their comma-joined text
# from the start: an empty list joins to "", which reads nothing, and any
# other list is scan_join. read_join uses it.
law fields_scan:
  for fields: List<&2, String>
  {TC.Scan.fields(fields, TC.Scan.start()) == TC.Scan.text(String.join(fields, ","), TC.Scan.start()) : TC.Scan}

def fields_scan(fields):
  match fields:
    case Nil{}:
      {==}
    case Con{first, rest}:
      scan_join(rest, first, TC.Scan.start())

# Measuring repeated fields is measuring their comma-joined text, so the
# commas that join them count toward the budget: Utf8.left_fields equals
# Utf8.left of String.join(fields, ","). fields_join uses it.
law fields_left:
  for fields: List<&2, String>
  for budget: Nat
  {TC.Utf8.left_fields(fields, Some{budget}) == TC.Utf8.left(String.join(fields, ","), Some{budget}) :
    Maybe<&2, Nat>}

def fields_left(fields, budget):
  match fields:
    case Nil{}:
      {==}
    case Con{first, rest}:
      left_join(rest, first, Some{budget})

# For the same measurement `m`, Scan.within gives the same result for
# repeated fields and for the single field of their comma-joined text: None
# refuses both, and Some reads the same text (fields_scan). fields_join uses
# it.
law read_join:
  for m: Maybe<&2, Nat>
  for +fields: List<&2, String>
  {TC.Scan.within(m, fields) == TC.Scan.within(m, Con{String.join(fields, ","), Nil{}}) :
    Result<&2, &2, TC.StateError, TC.TraceState>}

def read_join(m, fields):
  match m:
    case None{}:
      {==}
    case Some{left}:
      Equal.cong(TC.Scan, Result<&2, &2, TC.StateError, TC.TraceState>, scan => TC.Scan.finish(scan),
        TC.Scan.fields(fields, TC.Scan.start()), TC.Scan.text(String.join(fields, ","), TC.Scan.start()),
        fields_scan(fields))

# Parsing repeated fields gives exactly the result of parsing their values
# joined with commas: fields_left rewrites the measurement, and read_join
# compares the reading. Laws.fields_join proves law fields_join with it.
law fields_join:
  for +limits: TC.Limits
  for +fields: List<&2, String>
  {TC.TraceState.parse_fields(limits, fields) == TC.TraceState.parse(limits, String.join(fields, ",")) :
    Result<&2, &2, TC.StateError, TC.TraceState>}

def fields_join(limits, fields):
  %Equal.sym(Maybe<&2, Nat>, TC.Utf8.left_fields(fields, Some{TC.Limits.tracestate_input(limits)}),
    TC.Utf8.left(String.join(fields, ","), Some{TC.Limits.tracestate_input(limits)}),
    fields_left(fields, TC.Limits.tracestate_input(limits))) :
    {TC.Scan.within(_, fields) ==
      TC.Scan.within(TC.Utf8.left(String.join(fields, ","), Some{TC.Limits.tracestate_input(limits)}),
        Con{String.join(fields, ","), Nil{}}) : Result<&2, &2, TC.StateError, TC.TraceState>}
  read_join(TC.Utf8.left(String.join(fields, ","), Some{TC.Limits.tracestate_input(limits)}), fields)
