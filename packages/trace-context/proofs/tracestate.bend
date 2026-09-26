import Base
import ../trace_context.bend as TC
import ./chars.bend as CharsProof
import ./strings.bend as StringsProof
import ./bools.bend as BoolsProof
import ./lists.bend as ListsProof
# A character a class accepts differs from every character the class refuses.
law differs_step:
  for -f: Char -> Bool
  for -char: Char
  for -other: Char
  for same: Bool
  for view: CharsProof.CharView(char, other, same)
  for holds: {f(char) == True{} : Bool}
  for fails: {f(other) == False{} : Bool}
  {same == False{} : Bool}

def differs_step(f, char, other, same, view, holds, fails):
  match same:
    case False{}:
      {==}
    case True{}:
      Equal.trans(Bool, True{}, f(char), False{}, Equal.sym(Bool, f(char), True{}, holds),
        Equal.trans(Bool, f(char), f(other), False{}, Equal.cong(Char, Bool, f, char, other, view), fails))

law differs:
  for -f: Char -> Bool
  for +char: Char
  for +other: Char
  for holds: {f(char) == True{} : Bool}
  for fails: {f(other) == False{} : Bool}
  {Char.is_eq(char, other) == False{} : Bool}

def differs(f, char, other, holds, fails):
  differs_step(f, char, other, Char.is_eq(char, other), CharsProof.char_view(char, other), holds, fails)

# Optional whitespace is neither a key's first character nor a value's last.
law key_start_not_ows:
  for +char: Char
  for +holds: {TC.StateChar.is_key_start(char) == True{} : Bool}
  {TC.StateChar.is_ows(char) == False{} : Bool}

def key_start_not_ows(char, holds):
  %Equal.sym(Bool, Char.is_eq(char, ' '), False{}, differs(x => TC.StateChar.is_key_start(x), char, ' ', holds, {==})) :
    {Bool.or(_, Char.is_eq(char, '\t')) == False{} : Bool}
  %Equal.sym(Bool, Char.is_eq(char, '\t'), False{}, differs(x => TC.StateChar.is_key_start(x), char, '\t', holds, {==})) :
    {Bool.or(False{}, _) == False{} : Bool}
  {==}

law value_end_not_ows:
  for +char: Char
  for +holds: {TC.StateChar.is_value_end(char) == True{} : Bool}
  {TC.StateChar.is_ows(char) == False{} : Bool}

def value_end_not_ows(char, holds):
  %Equal.sym(Bool, Char.is_eq(char, ' '), False{}, differs(x => TC.StateChar.is_value_end(x), char, ' ', holds, {==})) :
    {Bool.or(_, Char.is_eq(char, '\t')) == False{} : Bool}
  %Equal.sym(Bool, Char.is_eq(char, '\t'), False{}, differs(x => TC.StateChar.is_value_end(x), char, '\t', holds, {==})) :
    {Bool.or(False{}, _) == False{} : Bool}
  {==}

# Keys and values
# ---------------

def KeyView(text: String, result: Result<&2, &2, TC.EntryError, TC.StateKey>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{key}:
      {TC.StateKey.to_string(key) == text : String}

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

law key_view:
  for +text: String
  KeyView(text, TC.StateKey.parse(text))

def key_view(text):
  key_step(text, TC.StateKey.is_valid(text), {==})

law key_roundtrip:
  for key: TC.StateKey
  {TC.StateKey.parse(TC.StateKey.to_string(key)) == Done{key} : Result<&2, &2, TC.EntryError, TC.StateKey>}

def key_roundtrip(key):
  match key:
    case TC.StateKey{+text, evidence}:
      %q@evidence : {TC.StateKey.parse(text) == TC.StateKey.parse.checked(text, _, q) :
        Result<&2, &2, TC.EntryError, TC.StateKey>}
      {==}

def ValueView(text: String, result: Result<&2, &2, TC.EntryError, TC.StateValue>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{value}:
      {TC.StateValue.to_string(value) == text : String}

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

law value_view:
  for +text: String
  ValueView(text, TC.StateValue.parse(text))

def value_view(text):
  value_step(text, TC.StateValue.is_valid(text), {==})

law value_roundtrip:
  for value: TC.StateValue
  {TC.StateValue.parse(TC.StateValue.to_string(value)) == Done{value} : Result<&2, &2, TC.EntryError, TC.StateValue>}

def value_roundtrip(value):
  match value:
    case TC.StateValue{+text, evidence}:
      %q@evidence : {TC.StateValue.parse(text) == TC.StateValue.parse.checked(text, _, q) :
        Result<&2, &2, TC.EntryError, TC.StateValue>}
      {==}

# The Result continuations of Scan.validate, named for the motives.
def entry_after_key(key: Result<&2, &2, TC.EntryError, TC.StateKey>, value: String) ->
  Result<&2, &2, TC.EntryError, TC.StateEntry>:
  do Result<&2, &2, TC.EntryError, TC.StateEntry>:
    parsed_key : TC.StateKey <- key
    parsed_value : TC.StateValue <- TC.StateValue.parse(value)
    return TC.StateEntry{parsed_key, parsed_value}

def entry_after_value(key: TC.StateKey, value: Result<&2, &2, TC.EntryError, TC.StateValue>) ->
  Result<&2, &2, TC.EntryError, TC.StateEntry>:
  do Result<&2, &2, TC.EntryError, TC.StateEntry>:
    parsed_value : TC.StateValue <- value
    return TC.StateEntry{key, parsed_value}

law entry_roundtrip:
  for entry: TC.StateEntry
  {TC.Scan.validate(TC.StateEntry.key_text(entry), TC.StateValue.to_string(TC.StateEntry.value(entry))) ==
    Done{entry} : Result<&2, &2, TC.EntryError, TC.StateEntry>}

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

law scan_stopped:
  for text: String
  for -error: TC.StateError
  {TC.Scan.text(text, TC.Stopped{error}) == TC.Stopped{error} : TC.Scan}

def scan_stopped(text, error):
  match text:
    case SNil{}:
      {==}
    case SCon{char, tail}:
      {==}

# Reading a concatenation reads its parts in order.
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

law key_not_comma:
  for +char: Char
  for holds: {TC.StateChar.is_key(char) == True{} : Bool}
  {Char.is_eq(char, ',') == False{} : Bool}

def key_not_comma(char, holds):
  differs(x => TC.StateChar.is_key(x), char, ',', holds, {==})

law key_not_equals:
  for +char: Char
  for holds: {TC.StateChar.is_key(char) == True{} : Bool}
  {Char.is_eq(char, '=') == False{} : Bool}

def key_not_equals(char, holds):
  differs(x => TC.StateChar.is_key(x), char, '=', holds, {==})

# The characters after a key's first are key characters: each one extends it.
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

law value_not_comma:
  for +char: Char
  for holds: {TC.StateChar.is_value(char) == True{} : Bool}
  {Char.is_eq(char, ',') == False{} : Bool}

def value_not_comma(char, holds):
  differs(x => TC.StateChar.is_value(x), char, ',', holds, {==})

law value_end_not_comma:
  for +char: Char
  for holds: {TC.StateChar.is_value_end(char) == True{} : Bool}
  {Char.is_eq(char, ',') == False{} : Bool}

def value_end_not_comma(char, holds):
  differs(x => TC.StateChar.is_value_end(x), char, ',', holds, {==})

# A value's characters are never commas: each one extends the value.
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

# An entry's text, read after a comma or at the start, leaves its key and its
# value, most recent character first, pending in the current member.
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
            differs(x => TC.StateChar.is_key_start(x), first, ',', start, {==})) :
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
            differs(x => TC.StateChar.is_key_start(x), first, '=', start, {==})) :
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

# Once a character other than whitespace is kept, restoring reverses the rest.
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
# reversed value drops nothing.
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
# count and duplicate checks.
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

# An entry read from its own text ends its member the same way.
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

# A new key is added after the entries kept so far.
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

# A comma, or the end of the value, adds the pending entry when its key is new.
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

law checked_valid:
  for +entries: List<&2, TC.StateEntry>
  for evidence: {TC.TraceState.is_valid(entries) == True{} : Bool}
  {TC.Scan.state(entries, TC.TraceState.is_valid(entries), {==}) == Done{TC.TraceState{entries, evidence}} :
    Result<&2, &2, TC.StateError, TC.TraceState>}

def checked_valid(entries, evidence):
  %q@evidence : {TC.Scan.state(entries, TC.TraceState.is_valid(entries), {==}) ==
    TC.Scan.state(entries, _, q) : Result<&2, &2, TC.StateError, TC.TraceState>}
  {==}

# Measuring against a budget, possibly after `need` more octets, succeeds
# exactly when the text's octets and `need` fit the budget.
law left_take:
  for +text: String
  for need: Nat
  for budget: Nat
  {Maybe.is_some(&2, Nat, TC.Utf8.left(text, TC.Budget.take(need, budget))) ==
    Nat.is_le(Nat.add(need, TC.Utf8.length(text)), budget) : Bool}

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

law within:
  for +text: String
  for budget: Nat
  {Maybe.is_some(&2, Nat, TC.Utf8.left(text, Some{budget})) == Nat.is_le(TC.Utf8.length(text), budget) : Bool}

def within(text, budget):
  left_take(text, 0n, budget)

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
        Result<&2, &2, TC.StateError, TC.TraceState>}, StringsProof.true_ne_false(larger))

# Parsing
# -------

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
# ---------------

law left_none:
  for text: String
  {TC.Utf8.left(text, None{}) == None{} : Maybe<&2, Nat>}

def left_none(text):
  match text:
    case SNil{}:
      {==}
    case SCon{char, tail}:
      {==}

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

law left_more_none:
  for fields: List<&2, String>
  {TC.Utf8.left_more(fields, None{}) == None{} : Maybe<&2, Nat>}

def left_more_none(fields):
  match fields:
    case Nil{}:
      {==}
    case Con{field, rest}:
      {==}

# Once exceeded, a budget stays exceeded through every later field.
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

law fields_scan:
  for fields: List<&2, String>
  {TC.Scan.fields(fields, TC.Scan.start()) == TC.Scan.text(String.join(fields, ","), TC.Scan.start()) : TC.Scan}

def fields_scan(fields):
  match fields:
    case Nil{}:
      {==}
    case Con{first, rest}:
      scan_join(rest, first, TC.Scan.start())

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
