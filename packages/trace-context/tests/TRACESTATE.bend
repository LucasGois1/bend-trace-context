import Base
import ../trace_context.bend as TC

# Tracestate and limits through the public API. Expected values are literal
# fixtures written from the Level 2 grammar and the approved policy, not
# recomputed by package helpers.
def Test.assert(name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "FAIL: " ++ name)

def Test.limits_error_equal(actual: TC.LimitsError, expected: TC.LimitsError) -> Bool:
  match actual expected:
    case TC.TraceParentInputTooSmall{} TC.TraceParentInputTooSmall{}:
      True{}
    case TC.TraceStateOutputTooSmall{} TC.TraceStateOutputTooSmall{}:
      True{}
    case TC.TraceStateInputTooSmall{} TC.TraceStateInputTooSmall{}:
      True{}
    case _ _:
      False{}

def Test.limits_accepted(+name: String, tp: Nat, si: Nat, so: Nat,
  result: Result<&2, &2, TC.LimitsError, TC.Limits>) -> IO(Unit):
  match result:
    case Fail{error}:
      IO.die(Unit, 1, "FAIL: " ++ name ++ ": " ++ TC.LimitsError.show(error))
    case Done{+limits}:
      Test.assert(name, Bool.and(Nat.is_eq(TC.Limits.traceparent_input(limits), tp),
        Bool.and(Nat.is_eq(TC.Limits.tracestate_input(limits), si),
          Nat.is_eq(TC.Limits.tracestate_output(limits), so))))

def Test.limits_accept(name: String, +tp: Nat, +si: Nat, +so: Nat) -> IO(Unit):
  Test.limits_accepted(name, tp, si, so, TC.Limits.new(tp, si, so))

def Test.limits_rejected(name: String, result: Result<&2, &2, TC.LimitsError, TC.Limits>,
  expected: TC.LimitsError) -> IO(Unit):
  match result:
    case Done{_}:
      IO.die(Unit, 1, "FAIL: accepted " ++ name)
    case Fail{actual}:
      Test.assert(name, Test.limits_error_equal(actual, expected))

def Test.limits_reject(name: String, tp: Nat, si: Nat, so: Nat, expected: TC.LimitsError) -> IO(Unit):
  Test.limits_rejected(name, TC.Limits.new(tp, si, so), expected)

def Test.limits() -> IO(Unit):
  +defaults = TC.Limits.default()
  do IO<Unit>:
    Unit <- Test.assert("default traceparent input budget is 32 KiB",
      Nat.is_eq(TC.Limits.traceparent_input(defaults), 32768n))
    Unit <- Test.assert("default tracestate input budget is 32 KiB",
      Nat.is_eq(TC.Limits.tracestate_input(defaults), 32768n))
    Unit <- Test.assert("default tracestate output budget is 512 bytes",
      Nat.is_eq(TC.Limits.tracestate_output(defaults), 512n))
    Unit <- Test.limits_accept("the smallest accepted limits", 55n, 512n, 512n)
    Unit <- Test.limits_accept("a larger output budget with an equal input budget", 100n, 4096n, 4096n)
    Unit <- Test.limits_reject("a traceparent input budget of 54 bytes", 54n, 32768n, 512n,
      TC.TraceParentInputTooSmall{})
    Unit <- Test.limits_reject("a tracestate output budget of 511 bytes", 55n, 32768n, 511n,
      TC.TraceStateOutputTooSmall{})
    Unit <- Test.limits_reject("a tracestate input budget below the output budget", 55n, 1023n, 1024n,
      TC.TraceStateInputTooSmall{})
    Unit <- Test.limits_reject("the first failing limit is reported", 0n, 0n, 0n,
      TC.TraceParentInputTooSmall{})
    IO.print("OK: validated limits and their defaults")

def Test.entry_error_equal(actual: TC.EntryError, expected: TC.EntryError) -> Bool:
  match actual expected:
    case TC.MissingEquals{} TC.MissingEquals{}:
      True{}
    case TC.InvalidKey{} TC.InvalidKey{}:
      True{}
    case TC.InvalidValue{} TC.InvalidValue{}:
      True{}
    case _ _:
      False{}

def Test.key_accepted(+name: String, text: String, result: Result<&2, &2, TC.EntryError, TC.StateKey>) -> IO(Unit):
  match result:
    case Fail{error}:
      IO.die(Unit, 1, "FAIL: " ++ name ++ ": " ++ TC.EntryError.show(error))
    case Done{key}:
      Test.assert(name ++ " keeps its text", String.eq(TC.StateKey.to_string(key), text))

def Test.key_accept(name: String, +text: String) -> IO(Unit):
  Test.key_accepted(name, text, TC.StateKey.parse(text))

# Checks a rejection by StateKey.parse or StateValue.parse.
def Test.entry_rejected(-A: Data, name: String, result: Result<&2, &2, TC.EntryError, A>, expected: TC.EntryError) ->
  IO(Unit):
  match result:
    case Done{_}:
      IO.die(Unit, 1, "FAIL: accepted " ++ name)
    case Fail{error}:
      Test.assert(name, Test.entry_error_equal(error, expected))

def Test.key_reject(name: String, text: String) -> IO(Unit):
  Test.entry_rejected(TC.StateKey, name, TC.StateKey.parse(text), TC.InvalidKey{})

def Test.value_accepted(+name: String, text: String, result: Result<&2, &2, TC.EntryError, TC.StateValue>) ->
  IO(Unit):
  match result:
    case Fail{error}:
      IO.die(Unit, 1, "FAIL: " ++ name ++ ": " ++ TC.EntryError.show(error))
    case Done{value}:
      Test.assert(name ++ " keeps its text", String.eq(TC.StateValue.to_string(value), text))

def Test.value_accept(name: String, +text: String) -> IO(Unit):
  Test.value_accepted(name, text, TC.StateValue.parse(text))

def Test.value_reject(name: String, text: String) -> IO(Unit):
  Test.entry_rejected(TC.StateValue, name, TC.StateValue.parse(text), TC.InvalidValue{})

def Test.keys() -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.key_accept("a one-letter key", "a")
    Unit <- Test.key_accept("a key starting with a digit", "0")
    Unit <- Test.key_accept("every key character", "abcdefghijklmnopqrstuvwxyz0123456789_-*/@")
    Unit <- Test.key_accept("a multi-tenant style key", "fw529a3039@dt")
    Unit <- Test.key_accept("a 256-character key", String.repeat("k", 256n))
    Unit <- Test.key_reject("an empty key", "")
    Unit <- Test.key_reject("a 257-character key", String.repeat("k", 257n))
    Unit <- Test.key_reject("an uppercase letter", "Vendor")
    Unit <- Test.key_reject("an uppercase letter after the first", "vendorA")
    Unit <- Test.key_reject("a key starting with an underscore", "_vendor")
    Unit <- Test.key_reject("a key starting with a dash", "-vendor")
    Unit <- Test.key_reject("a key starting with an at sign", "@vendor")
    Unit <- Test.key_reject("a space inside a key", "ven dor")
    Unit <- Test.key_reject("a trailing space", "vendor ")
    Unit <- Test.key_reject("an equals sign", "ven=dor")
    Unit <- Test.key_reject("a comma", "ven,dor")
    Unit <- Test.key_reject("a dot", "ven.dor")
    Unit <- Test.key_reject("a non-ASCII letter", "vendé")
    Unit <- Test.key_reject("the character after z", "vendor{")
    Unit <- Test.key_reject("the character before a", "vendor`")
    IO.print("OK: Level 2 keys")

def Test.values() -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.value_accept("a one-character value", "x")
    Unit <- Test.value_accept("leading spaces are part of a value", "  x")
    Unit <- Test.value_accept("inner spaces are part of a value", "a b  c")
    Unit <- Test.value_accept("every value character",
      " !\"#$%&'()*+-./0123456789:;<>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~")
    Unit <- Test.value_accept("a 256-character value", String.repeat("v", 256n))
    Unit <- Test.value_accept("255 spaces and a final character", String.repeat(" ", 255n) ++ "v")
    Unit <- Test.value_reject("an empty value", "")
    Unit <- Test.value_reject("a single space", " ")
    Unit <- Test.value_reject("a trailing space", "x ")
    Unit <- Test.value_reject("a 257-character value", String.repeat("v", 257n))
    Unit <- Test.value_reject("256 spaces and a final character", String.repeat(" ", 256n) ++ "v")
    Unit <- Test.value_reject("a comma", "a,b")
    Unit <- Test.value_reject("an equals sign", "a=b")
    Unit <- Test.value_reject("a tab", "a\tb")
    Unit <- Test.value_reject("a trailing tab", "a\t")
    Unit <- Test.value_reject("a newline", "a\nb")
    Unit <- Test.value_reject("delete", "a" ++ Char.show(Char.from_u32(127)))
    Unit <- Test.value_reject("a non-ASCII character", "café")
    IO.print("OK: Level 2 values")

def Test.valid(-A: Data, name: String, result: Result<&2, &2, TC.EntryError, A>) -> IO(A):
  match result:
    case Fail{error}:
      IO.die(A, 1, "FAIL: " ++ name ++ " fixture: " ++ TC.EntryError.show(error))
    case Done{value}:
      IO.pure(A, value)

def Test.key(text: String) -> IO(TC.StateKey):
  Test.valid(TC.StateKey, "key", TC.StateKey.parse(text))

def Test.state(name: String, result: Result<&2, &2, TC.StateError, TC.TraceState>) -> IO(TC.TraceState):
  match result:
    case Fail{error}:
      IO.die(TC.TraceState, 1, "FAIL: " ++ name ++ ": " ++ TC.StateError.show(error))
    case Done{state}:
      IO.pure(TC.TraceState, state)

# Parse with the default limits and compare the normalized value.
def Test.parsed(+name: String, expected: String, result: Result<&2, &2, TC.StateError, TC.TraceState>) ->
  IO(Unit):
  do IO<Unit>:
    state : TC.TraceState <- Test.state(name, result)
    Test.assert(name, String.eq(TC.TraceState.format(state), expected))

def Test.parse(name: String, text: String, expected: String) -> IO(Unit):
  Test.parsed(name, expected, TC.TraceState.parse(TC.Limits.default(), text))

def Test.value_text(value: Maybe<&2, TC.StateValue>) -> String:
  match value:
    case None{}:
      "none"
    case Some{found}:
      "some " ++ TC.StateValue.to_string(found)

def Test.lookup(name: String, state: TC.TraceState, key: String, expected: String) -> IO(Unit):
  do IO<Unit>:
    found : TC.StateKey <- Test.key(key)
    Test.assert(name, String.eq(Test.value_text(TC.TraceState.get(state, found)), expected))

def Test.count(name: String, state: TC.TraceState, expected: Nat) -> IO(Unit):
  Test.assert(name, Nat.is_eq(List.length(&2, TC.StateEntry, TC.TraceState.entries(state)), expected))

def Test.queries() -> IO(Unit):
  do IO<Unit>:
    +example : TC.TraceState <- Test.state("the W3C example",
      TC.TraceState.parse(TC.Limits.default(), "congo=t61rcWkgMzE,rojo=00f067aa0ba902b7"))
    Unit <- Test.assert("the W3C example formats as received",
      String.eq(TC.TraceState.format(example), "congo=t61rcWkgMzE,rojo=00f067aa0ba902b7"))
    Unit <- Test.count("the W3C example has two entries", example, 2n)
    Unit <- Test.lookup("the first entry by key", example, "congo", "some t61rcWkgMzE")
    Unit <- Test.lookup("the second entry by key", example, "rojo", "some 00f067aa0ba902b7")
    Unit <- Test.lookup("an absent key", example, "absent", "none")
    Unit <- Test.lookup("a key that only prefixes an entry's key", example, "cong", "none")
    +empty : TC.TraceState <- Test.state("an empty value", TC.TraceState.parse(TC.Limits.default(), ""))
    Unit <- Test.assert("an empty value is the empty state", TC.TraceState.is_empty(empty))
    Unit <- Test.assert("the empty state formats as an empty string", String.eq(TC.TraceState.format(empty), ""))
    Unit <- Test.assert("the empty constructor is empty", TC.TraceState.is_empty(TC.TraceState.empty()))
    Test.assert("a parsed entry is not empty", Bool.not(TC.TraceState.is_empty(example)))

def Test.state_error_equal(actual: TC.StateError, expected: TC.StateError) -> Bool:
  match actual expected:
    case TC.StateTooLarge{} TC.StateTooLarge{}:
      True{}
    case TC.TooManyMembers{} TC.TooManyMembers{}:
      True{}
    case TC.InvalidEntry{a, x} TC.InvalidEntry{b, y}:
      Bool.and(Nat.is_eq(a, b), Test.entry_error_equal(x, y))
    case _ _:
      False{}

def Test.discarded(name: String, result: Result<&2, &2, TC.StateError, TC.TraceState>,
  expected: TC.StateError) -> IO(Unit):
  match result:
    case Done{state}:
      IO.die(Unit, 1, "FAIL: accepted " ++ name ++ " as " ++ TC.TraceState.format(state))
    case Fail{+actual}:
      Test.assert(name ++ " (" ++ TC.StateError.show(actual) ++ ")", Test.state_error_equal(actual, expected))

def Test.discard(name: String, text: String, expected: TC.StateError) -> IO(Unit):
  Test.discarded(name, TC.TraceState.parse(TC.Limits.default(), text), expected)

def Test.whitespace() -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.parse("a space after a comma", "a=1, b=2", "a=1,b=2")
    Unit <- Test.parse("a space before a comma", "a=1 ,b=2", "a=1,b=2")
    Unit <- Test.parse("spaces and tabs around members", " \t a=1 \t , \t b=2 \t ", "a=1,b=2")
    Unit <- Test.parse("a leading tab", "\ta=1", "a=1")
    Unit <- Test.parse("a trailing tab", "a=1\t", "a=1")
    Unit <- Test.parse("a leading value space is kept", "a= 1", "a= 1")
    Unit <- Test.parse("leading and inner value spaces are kept", "a=  x y", "a=  x y")
    Unit <- Test.parse("trailing value spaces are optional whitespace", "a=x y   ,b=2", "a=x y,b=2")
    Unit <- Test.parse("empty members are ignored", ",a=1,,b=2,", "a=1,b=2")
    Unit <- Test.parse("whitespace-only members are ignored", " , \t ,, ", "")
    Unit <- Test.parse("only commas", ",,,", "")
    Unit <- Test.discard("a key without a value", "a", TC.InvalidEntry{0n, TC.MissingEquals{}})
    Unit <- Test.discard("a later member without a value", "a=1,b", TC.InvalidEntry{1n, TC.MissingEquals{}})
    Unit <- Test.discard("an empty key", "=1", TC.InvalidEntry{0n, TC.InvalidKey{}})
    Unit <- Test.discard("an uppercase key", "A=1", TC.InvalidEntry{0n, TC.InvalidKey{}})
    Unit <- Test.discard("a space before the equals sign", "a =1", TC.InvalidEntry{0n, TC.InvalidKey{}})
    Unit <- Test.discard("a tab before the equals sign", "a\t=1", TC.InvalidEntry{0n, TC.InvalidKey{}})
    Unit <- Test.discard("a leading newline", "\na=1", TC.InvalidEntry{0n, TC.InvalidKey{}})
    Unit <- Test.discard("an empty value", "a=", TC.InvalidEntry{0n, TC.InvalidValue{}})
    Unit <- Test.discard("a value of optional whitespace", "a= \t ", TC.InvalidEntry{0n, TC.InvalidValue{}})
    Unit <- Test.discard("a tab inside a value", "a=1\tx", TC.InvalidEntry{0n, TC.InvalidValue{}})
    Unit <- Test.discard("an equals sign inside a value", "a=b=c", TC.InvalidEntry{0n, TC.InvalidValue{}})
    Unit <- Test.discard("a trailing newline", "a=1\n", TC.InvalidEntry{0n, TC.InvalidValue{}})
    Unit <- Test.discard("member numbers count empty members", "a=1,,b=é", TC.InvalidEntry{2n, TC.InvalidValue{}})
    Test.discard("an invalid third member", "a=1, b=2,C=3", TC.InvalidEntry{2n, TC.InvalidKey{}})

def Test.members.rest(count: Nat, +index: Nat, +value: String) -> String:
  match count:
    case 0n:
      ""
    case 1n+more:
      ",k" ++ Nat.show(index) ++ "=" ++ value ++ Test.members.rest(more, 1n+index, value)

# `count` members `k<i>=<value>`, numbered from `first`, joined by commas.
def Test.members(count: Nat, +first: Nat, +value: String) -> String:
  match count:
    case 0n:
      ""
    case 1n+more:
      "k" ++ Nat.show(first) ++ "=" ++ value ++ Test.members.rest(more, 1n+first, value)

def Test.repeated.rest(count: Nat, +index: Nat) -> String:
  match count:
    case 0n:
      ""
    case 1n+more:
      ",a=" ++ Nat.show(index) ++ Test.repeated.rest(more, 1n+index)

# `count` members of one key `a`, with values numbered from 0.
def Test.repeated(count: Nat) -> String:
  match count:
    case 0n:
      ""
    case 1n+more:
      "a=0" ++ Test.repeated.rest(more, 1n)

def Test.duplicates() -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.parse("the first entry of a key is kept", "a=1,b=2,a=3", "a=1,b=2")
    Unit <- Test.parse("an identical duplicate is dropped", "a=1,a=1", "a=1")
    +first : TC.TraceState <- Test.state("duplicates", TC.TraceState.parse(TC.Limits.default(), "a=1,b=2,a=3"))
    Unit <- Test.lookup("a duplicated key reads its first value", first, "a", "some 1")
    Unit <- Test.discard("an invalid duplicate is not dropped", "a=1,b=2,a=X=", TC.InvalidEntry{2n, TC.InvalidValue{}})
    Unit <- Test.discard("a duplicate without a value is not dropped", "a=1,a", TC.InvalidEntry{1n, TC.MissingEquals{}})
    Unit <- Test.parse("32 members are accepted", Test.members(32n, 0n, "v"), Test.members(32n, 0n, "v"))
    Unit <- Test.discard("a 33rd member is refused", Test.members(33n, 0n, "v"), TC.TooManyMembers{})
    Unit <- Test.parse("32 members of one key keep the first", Test.repeated(32n), "a=0")
    Unit <- Test.discard("members are counted before duplicates are dropped", Test.repeated(33n),
      TC.TooManyMembers{})
    Unit <- Test.parse("empty members are not counted", ",," ++ Test.members(32n, 0n, "v") ++ ",, ,",
      Test.members(32n, 0n, "v"))
    Test.discard("a 33rd member is validated before it is counted", Test.members(32n, 0n, "v") ++ ",K=v",
      TC.InvalidEntry{32n, TC.InvalidKey{}})

# Parse with the given limits.
def Test.parse_with(+name: String, limits: TC.Limits, text: String, expected: String) -> IO(Unit):
  Test.parsed(name, expected, TC.TraceState.parse(limits, text))

def Test.discard_with(name: String, limits: TC.Limits, text: String, expected: TC.StateError) -> IO(Unit):
  Test.discarded(name, TC.TraceState.parse(limits, text), expected)

def Test.limits_value(result: Result<&2, &2, TC.LimitsError, TC.Limits>) -> IO(TC.Limits):
  match result:
    case Fail{error}:
      IO.die(TC.Limits, 1, "FAIL: limits fixture: " ++ TC.LimitsError.show(error))
    case Done{limits}:
      IO.pure(TC.Limits, limits)

# 256 and 255 octets: "a=" and "b=" with 254 and 253 characters.
def Test.half() -> String:
  "a=" ++ String.repeat("v", 254n)

def Test.other_half() -> String:
  "b=" ++ String.repeat("w", 253n)

def Test.budget() -> IO(Unit):
  do IO<Unit>:
    +small : TC.Limits <- Test.limits_value(TC.Limits.new(55n, 512n, 512n))
    Unit <- Test.parse_with("a value of exactly 512 octets", small, Test.half() ++ "," ++ Test.other_half(),
      Test.half() ++ "," ++ Test.other_half())
    Unit <- Test.discard_with("a value of 513 octets", small, Test.half() ++ "," ++ Test.other_half() ++ "w",
      TC.StateTooLarge{})
    Unit <- Test.parse_with("whitespace counts toward the budget", small, "a=1" ++ String.repeat(" ", 509n), "a=1")
    Unit <- Test.discard_with("whitespace past the budget", small, "a=1" ++ String.repeat(" ", 510n),
      TC.StateTooLarge{})
    Unit <- Test.parse_with("empty members count toward the budget", small, "a=1" ++ String.repeat(",", 509n), "a=1")
    Unit <- Test.discard_with("the budget is checked before any member", small,
      "A=1," ++ String.repeat(" ", 509n), TC.StateTooLarge{})
    Unit <- Test.discard_with("two-octet characters within the budget are read", small,
      "a=" ++ String.repeat("é", 255n), TC.InvalidEntry{0n, TC.InvalidValue{}})
    Unit <- Test.discard_with("one more two-octet character", small,
      "a=" ++ String.repeat("é", 255n) ++ "x", TC.StateTooLarge{})
    Unit <- Test.discard_with("three-octet characters within the budget are read", small,
      "a=" ++ String.repeat("€", 170n), TC.InvalidEntry{0n, TC.InvalidValue{}})
    Unit <- Test.discard_with("one more three-octet character", small,
      "a=" ++ String.repeat("€", 171n), TC.StateTooLarge{})
    Unit <- Test.discard_with("four-octet characters within the budget are read", small,
      "a=" ++ String.repeat("😀", 127n) ++ "xx", TC.InvalidEntry{0n, TC.InvalidValue{}})
    Unit <- Test.discard_with("one more four-octet character", small,
      "a=" ++ String.repeat("😀", 128n), TC.StateTooLarge{})
    Test.discard_with("the last one-octet character", small,
      String.repeat(Char.show(Char.from_u32(127)), 513n), TC.StateTooLarge{})

# The octet widths at every UTF-8 boundary, through a budget that one more
# octet would exceed.
def Test.widths() -> IO(Unit):
  do IO<Unit>:
    +small : TC.Limits <- Test.limits_value(TC.Limits.new(55n, 512n, 512n))
    Unit <- Test.discard_with("U+007F is one octet", small,
      String.repeat(Char.show(Char.from_u32(127)), 512n), TC.InvalidEntry{0n, TC.MissingEquals{}})
    Unit <- Test.discard_with("U+0080 is two octets", small,
      String.repeat(Char.show(Char.from_u32(128)), 256n), TC.InvalidEntry{0n, TC.MissingEquals{}})
    Unit <- Test.discard_with("U+0080 past the budget", small,
      "x" ++ String.repeat(Char.show(Char.from_u32(128)), 256n), TC.StateTooLarge{})
    Unit <- Test.discard_with("U+07FF is two octets", small,
      String.repeat(Char.show(Char.from_u32(2047)), 256n), TC.InvalidEntry{0n, TC.MissingEquals{}})
    Unit <- Test.discard_with("U+0800 is three octets", small,
      "xx" ++ String.repeat(Char.show(Char.from_u32(2048)), 170n), TC.InvalidEntry{0n, TC.MissingEquals{}})
    Unit <- Test.discard_with("U+0800 past the budget", small,
      "xxx" ++ String.repeat(Char.show(Char.from_u32(2048)), 170n), TC.StateTooLarge{})
    Unit <- Test.discard_with("U+FFFF is three octets", small,
      "xx" ++ String.repeat(Char.show(Char.from_u32(65535)), 170n), TC.InvalidEntry{0n, TC.MissingEquals{}})
    Unit <- Test.discard_with("U+10000 is four octets", small,
      String.repeat(Char.show(Char.from_u32(65536)), 128n), TC.InvalidEntry{0n, TC.MissingEquals{}})
    Test.discard_with("U+10000 past the budget", small,
      "x" ++ String.repeat(Char.show(Char.from_u32(65536)), 128n), TC.StateTooLarge{})

def Test.fields_parse(name: String, fields: List<&2, String>, expected: String) -> IO(Unit):
  Test.parsed(name, expected, TC.TraceState.parse_fields(TC.Limits.default(), fields))

def Test.fields_discard(name: String, limits: TC.Limits, fields: List<&2, String>, expected: TC.StateError) ->
  IO(Unit):
  Test.discarded(name, TC.TraceState.parse_fields(limits, fields), expected)

def Test.fields() -> IO(Unit):
  do IO<Unit>:
    +small : TC.Limits <- Test.limits_value(TC.Limits.new(55n, 512n, 512n))
    Unit <- Test.fields_parse("repeated fields are combined in order", ["congo=1", "rojo=2"], "congo=1,rojo=2")
    Unit <- Test.fields_parse("an empty field is an empty member", ["a=1", "", "b=2"], "a=1,b=2")
    Unit <- Test.fields_parse("fields with their own empty members", ["a=1,", " ,b=2"], "a=1,b=2")
    Unit <- Test.fields_parse("no field is the empty state", [], "")
    Unit <- Test.fields_parse("the first field's entry of a key is kept", ["a=1,b=2", "a=3,c=4"], "a=1,b=2,c=4")
    Unit <- Test.fields_discard("members are numbered across fields", TC.Limits.default(), ["a=1", "b"],
      TC.InvalidEntry{1n, TC.MissingEquals{}})
    Unit <- Test.fields_discard("a joining comma separates members", TC.Limits.default(), ["a=1,", "b"],
      TC.InvalidEntry{2n, TC.MissingEquals{}})
    Unit <- Test.fields_discard("members are counted across fields", TC.Limits.default(),
      [Test.members(16n, 0n, "v"), Test.members(17n, 16n, "v")], TC.TooManyMembers{})
    Unit <- Test.parse_with("the joining comma fits the budget", small,
      Test.half() ++ "," ++ Test.other_half(), Test.half() ++ "," ++ Test.other_half())
    Unit <- Test.parsed("fields and their joining comma within the budget", Test.half() ++ "," ++ Test.other_half(),
      TC.TraceState.parse_fields(small, [Test.half(), Test.other_half()]))
    Test.fields_discard("the joining comma counts toward the budget", small, [Test.half(), Test.other_half() ++ "w"],
      TC.StateTooLarge{})

# A 256-character key starting with its number, and a 256-character value.
def Test.largest_entry(index: Nat) -> String:
  String.take("k" ++ Nat.show(index) ++ String.repeat("x", 256n), 256n) ++ "=" ++ String.repeat("v", 256n)

def Test.largest_rest(count: Nat, +index: Nat) -> String:
  match count:
    case 0n:
      ""
    case 1n+more:
      "," ++ Test.largest_entry(index) ++ Test.largest_rest(more, 1n+index)

# Base's String.eq recurses once per character, which a 16447-character text
# takes beyond the JavaScript stack; this comparison is a loop.
def Test.same(a: String, b: String, same: Bool) -> Bool:
  match a b:
    case SNil{} SNil{}:
      same
    case SNil{} SCon{y, ys}:
      False{}
    case SCon{x, xs} SNil{}:
      False{}
    case SCon{x, xs} SCon{y, ys}:
      Test.same(xs, ys, Bool.and(same, Char.is_eq(x, y)))

# The largest valid state: 32 entries with 256-character keys and values,
# 16447 octets, within the default budget.
def Test.largest() -> IO(Unit):
  +text = Test.largest_entry(0n) ++ Test.largest_rest(31n, 1n)
  do IO<Unit>:
    Unit <- Test.assert("the largest state fixture has 16447 octets", Nat.is_eq(String.length(text), 16447n))
    +largest : TC.TraceState <- Test.state("the largest state", TC.TraceState.parse(TC.Limits.default(), text))
    Unit <- Test.count("the largest state has 32 entries", largest, 32n)
    Test.assert("the largest state formats as received", Test.same(TC.TraceState.format(largest), text, True{}))

# `count` copies of a character before `tail`, built by a loop.
def Test.fill(count: Nat, +char: Char, tail: String) -> String:
  match count:
    case 0n:
      tail
    case 1n+more:
      Test.fill(more, char, SCon{char, tail})

# Inputs at and past the default budget. Reading loops over characters, so
# none of these needs a deep stack on either backend.
def Test.bounded() -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.discard("a 32768-octet member without an equals sign", Test.fill(32768n, 'k', ""),
      TC.InvalidEntry{0n, TC.MissingEquals{}})
    Unit <- Test.discard("a 32767-character key", Test.fill(32767n, 'k', "="),
      TC.InvalidEntry{0n, TC.InvalidKey{}})
    Unit <- Test.discard("a 32766-character value", "k=" ++ Test.fill(32766n, 'v', ""),
      TC.InvalidEntry{0n, TC.InvalidValue{}})
    Unit <- Test.parse("a value followed by 32765 spaces", "k=v" ++ Test.fill(32765n, ' ', ""), "k=v")
    Unit <- Test.parse("a value followed by 32765 tabs", "k=v" ++ Test.fill(32765n, '\t', ""), "k=v")
    Unit <- Test.discard("a value followed by 32766 spaces", "k=v" ++ Test.fill(32766n, ' ', ""), TC.StateTooLarge{})
    Unit <- Test.parse("32768 octets of separators and whitespace", Test.fill(16384n, ',', Test.fill(16384n, ' ', "")), "")
    Unit <- Test.discard("one octet past the default budget", Test.fill(32769n, ' ', ""), TC.StateTooLarge{})
    Unit <- Test.discard("a mebibyte is refused without reading past the budget", Test.fill(1048576n, 'x', ""),
      TC.StateTooLarge{})
    Test.fields_discard("fields past the default budget", TC.Limits.default(), [Test.fill(32768n, 'a', ""), "b=1"],
      TC.StateTooLarge{})

def Test.diagnostics() -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.assert("a budget diagnostic", String.eq(TC.StateError.show(TC.StateTooLarge{}), "StateTooLarge"))
    Unit <- Test.assert("a member-count diagnostic", String.eq(TC.StateError.show(TC.TooManyMembers{}),
      "TooManyMembers"))
    Unit <- Test.assert("a syntax diagnostic",
      String.eq(TC.StateError.show(TC.InvalidEntry{3n, TC.InvalidKey{}}), "InvalidEntry 3 InvalidKey"))
    Test.assert("a limits diagnostic",
      String.eq(TC.LimitsError.show(TC.TraceStateInputTooSmall{}), "TraceStateInputTooSmall"))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.limits()
    Unit <- Test.keys()
    Unit <- Test.values()
    Unit <- Test.queries()
    Unit <- IO.print("OK: parse, query and format")
    Unit <- Test.whitespace()
    Unit <- IO.print("OK: optional whitespace, empty members and member errors")
    Unit <- Test.duplicates()
    Unit <- IO.print("OK: first entry of a key, validated and counted before duplicates are dropped")
    Unit <- Test.budget()
    Unit <- Test.widths()
    Unit <- IO.print("OK: UTF-8 input budget")
    Unit <- Test.fields()
    Unit <- IO.print("OK: repeated fields and joining commas")
    Unit <- Test.largest()
    Unit <- IO.print("OK: the largest valid state")
    Unit <- Test.bounded()
    Unit <- IO.print("OK: bounded reading at and past the default budget")
    Unit <- Test.diagnostics()
    IO.print("OK: diagnostics")
