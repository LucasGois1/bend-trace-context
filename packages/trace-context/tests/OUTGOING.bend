import Base
import ../trace_context.bend as TC

# Tracestate updates and emission through the public API. Expected values are
# literal fixtures written from W3C Trace Context Level 2 (sections 3.3.3.1
# and 3.5) and the approved policy of spec #1, not recomputed by package
# helpers.
def Test.assert(name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "FAIL: " ++ name)

def Test.valid(-A: Data, name: String, result: Result<&2, &2, TC.EntryError, A>) -> IO(A):
  match result:
    case Fail{error}:
      IO.die(A, 1, "FAIL: " ++ name ++ " fixture: " ++ TC.EntryError.show(error))
    case Done{value}:
      IO.pure(A, value)

def Test.key(text: String) -> IO(TC.StateKey):
  Test.valid(TC.StateKey, "key", TC.StateKey.parse(text))

def Test.value(text: String) -> IO(TC.StateValue):
  Test.valid(TC.StateValue, "value", TC.StateValue.parse(text))

def Test.state(name: String, result: Result<&2, &2, TC.StateError, TC.TraceState>) -> IO(TC.TraceState):
  match result:
    case Fail{error}:
      IO.die(TC.TraceState, 1, "FAIL: " ++ name ++ ": " ++ TC.StateError.show(error))
    case Done{state}:
      IO.pure(TC.TraceState, state)

# A state parsed from a fixture with the default limits.
def Test.parsed(text: String) -> IO(TC.TraceState):
  Test.state("fixture", TC.TraceState.parse(TC.Limits.default(), text))

# Set `key` to `value` in the state of `text`, and compare the normalized
# result with `expected`.
def Test.set(name: String, text: String, key: String, value: String, expected: String) -> IO(Unit):
  do IO<Unit>:
    state : TC.TraceState <- Test.parsed(text)
    found : TC.StateKey <- Test.key(key)
    given : TC.StateValue <- Test.value(value)
    Test.assert(name, String.eq(TC.TraceState.format(TC.TraceState.set(state, found, given)), expected))

# Remove `key` from the state of `text`, and compare the normalized result
# with `expected`.
def Test.remove(name: String, text: String, key: String, expected: String) -> IO(Unit):
  do IO<Unit>:
    state : TC.TraceState <- Test.parsed(text)
    found : TC.StateKey <- Test.key(key)
    Test.assert(name, String.eq(TC.TraceState.format(TC.TraceState.remove(state, found)), expected))

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

def Test.updates() -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.set("a new key goes to the front",
      "congo=t61rcWkgMzE,rojo=00f067aa0ba902b7", "fw529a3039", "00f067aa0ba902b7",
      "fw529a3039=00f067aa0ba902b7,congo=t61rcWkgMzE,rojo=00f067aa0ba902b7")
    Unit <- Test.set("an updated key moves to the front and the others keep their order",
      "congo=t61rcWkgMzE,rojo=00f067aa0ba902b7,fw529a3039=1", "rojo", "2",
      "rojo=2,congo=t61rcWkgMzE,fw529a3039=1")
    Unit <- Test.set("updating the first key keeps it first", "congo=1,rojo=2", "congo", "3", "congo=3,rojo=2")
    Unit <- Test.set("a key set on the empty state is its only entry", "", "congo", "1", "congo=1")
    Unit <- Test.set("updating a key of a full state evicts nothing",
      Test.members(32n, 0n, "v"), "k20", "new",
      "k20=new," ++ Test.members(20n, 0n, "v") ++ "," ++ Test.members(11n, 21n, "v"))
    Unit <- Test.set("updating the last key of a full state evicts nothing",
      Test.members(32n, 0n, "v"), "k31", "new", "k31=new," ++ Test.members(31n, 0n, "v"))
    Unit <- Test.set("a 33rd key removes the last entry",
      Test.members(32n, 0n, "v"), "a", "new", "a=new," ++ Test.members(31n, 0n, "v"))
    Unit <- Test.set("a key added to 31 entries evicts nothing",
      Test.members(31n, 0n, "v"), "a", "new", "a=new," ++ Test.members(31n, 0n, "v"))
    Unit <- Test.remove("a removed entry leaves the others in order",
      "congo=1,rojo=2,fw529a3039=3", "rojo", "congo=1,fw529a3039=3")
    Unit <- Test.remove("removing the first entry", "congo=1,rojo=2", "congo", "rojo=2")
    Unit <- Test.remove("removing the last entry", "congo=1,rojo=2", "rojo", "congo=1")
    Unit <- Test.remove("removing an absent key changes nothing", "congo=1,rojo=2", "absent", "congo=1,rojo=2")
    Unit <- Test.remove("removing the only entry leaves the empty state", "congo=1", "congo", "")
    IO.print("OK: updates")

# The emitted octets of the state of `text`.
def Test.size(name: String, text: String, expected: Nat) -> IO(Unit):
  do IO<Unit>:
    state : TC.TraceState <- Test.parsed(text)
    Test.assert(name, Nat.is_eq(TC.TraceState.size(state), expected))

def Test.sizes() -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.size("the empty state takes no octets", "", 0n)
    Unit <- Test.size("one entry takes its key, the equals sign and its value", "a=1", 3n)
    Unit <- Test.size("two entries take one comma more", "congo=t61rcWkgMzE,rojo=00f067aa0ba902b7", 39n)
    Unit <- Test.size("received optional whitespace is not emitted", " congo=1 , rojo=2 ", 14n)
    Unit <- Test.size("32 entries take 31 commas", Test.members(32n, 0n, "v"), 181n)
    IO.print("OK: emitted size")

# `key=` followed by `length` copies of "v": an entry of
# String.length(key) + 1 + length octets.
def Test.entry(key: String, length: Nat) -> String:
  key ++ "=" ++ String.repeat("v", length)

def Test.keys.rest(keys: List<&2, TC.StateKey>) -> String:
  match keys:
    case Nil{}:
      ""
    case Con{key, rest}:
      "," ++ TC.StateKey.to_string(key) ++ Test.keys.rest(rest)

# The keys joined by commas; "" for none.
def Test.keys(keys: List<&2, TC.StateKey>) -> String:
  match keys:
    case Nil{}:
      ""
    case Con{key, rest}:
      TC.StateKey.to_string(key) ++ Test.keys.rest(rest)

def Test.truncation(+name: String, kept: String, dropped: String, +result: TC.Truncation) -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.assert(name ++ ": the entries kept",
      String.eq(TC.TraceState.format(TC.Truncation.kept(result)), kept))
    Test.assert(name ++ ": the keys dropped", String.eq(Test.keys(TC.Truncation.dropped(result)), dropped))

# Truncate the state of `text` to the output budget of `limits`.
def Test.truncate_with(name: String, limits: TC.Limits, text: String, kept: String, dropped: String) -> IO(Unit):
  do IO<Unit>:
    state : TC.TraceState <- Test.parsed(text)
    Test.truncation(name, kept, dropped, TC.TraceState.truncate(limits, state))

def Test.truncate(name: String, text: String, kept: String, dropped: String) -> IO(Unit):
  Test.truncate_with(name, TC.Limits.default(), text, kept, dropped)

def Test.limits_value(result: Result<&2, &2, TC.LimitsError, TC.Limits>) -> IO(TC.Limits):
  match result:
    case Fail{error}:
      IO.die(TC.Limits, 1, "FAIL: limits fixture: " ++ TC.LimitsError.show(error))
    case Done{limits}:
      IO.pure(TC.Limits, limits)

# Sizes below are octets: a one-letter key, "=" and the value.
def Test.truncations() -> IO(Unit):
  # 127 + 127 + 127 + 128 octets and three commas: exactly 512.
  +exact = Test.entry("a", 125n) ++ "," ++ Test.entry("b", 125n) ++ "," ++ Test.entry("c", 125n) ++ "," ++
    Test.entry("d", 126n)
  # 127 + 127 + 128 + 128 and three commas: 513, and no entry larger than 128.
  +over = Test.entry("a", 125n) ++ "," ++ Test.entry("b", 125n) ++ "," ++ Test.entry("c", 126n) ++ "," ++
    Test.entry("d", 126n)
  do IO<Unit>:
    Unit <- Test.truncate("the empty state", "", "", "")
    Unit <- Test.truncate("a state of exactly 512 octets is emitted whole", exact, exact, "")
    Unit <- Test.truncate("at 513 octets without a large entry, the rightmost entry goes", over,
      Test.entry("a", 125n) ++ "," ++ Test.entry("b", 125n) ++ "," ++ Test.entry("c", 126n), "d")
    # 129 + 100 + 258 + 100 + 100 and four commas: 691. Removing the rightmost
    # entry larger than 128, c, leaves 432, so the large entry a stays.
    Unit <- Test.truncate("the rightmost large entry goes first, and removal stops once the value fits",
      Test.entry("a", 127n) ++ "," ++ Test.entry("b", 98n) ++ "," ++ Test.entry("c", 256n) ++ "," ++
        Test.entry("d", 98n) ++ "," ++ Test.entry("e", 98n),
      Test.entry("a", 127n) ++ "," ++ Test.entry("b", 98n) ++ "," ++ Test.entry("d", 98n) ++ "," ++
        Test.entry("e", 98n), "c")
    # 258 + 258 + 258 and two commas: 776, then 517 without c, then 258.
    Unit <- Test.truncate("large entries go from the right until the value fits",
      Test.entry("a", 256n) ++ "," ++ Test.entry("b", 256n) ++ "," ++ Test.entry("c", 256n),
      Test.entry("a", 256n), "b,c")
    # 129 + 5 * 128 and five commas: 774; 644 without a; 515 without f, whose
    # 512 octets of entries still need three commas; 386 without e.
    Unit <- Test.truncate("once no large entry is left, entries go from the right, commas counted",
      Test.entry("a", 127n) ++ "," ++ Test.entry("b", 126n) ++ "," ++ Test.entry("c", 126n) ++ "," ++
        Test.entry("d", 126n) ++ "," ++ Test.entry("e", 126n) ++ "," ++ Test.entry("f", 126n),
      Test.entry("b", 126n) ++ "," ++ Test.entry("c", 126n) ++ "," ++ Test.entry("d", 126n), "a,e,f")
    # 129 + 128 + 128 + 128 and three commas: 516. Only a is larger than 128.
    Unit <- Test.truncate("an entry of exactly 128 octets is not large",
      Test.entry("a", 127n) ++ "," ++ Test.entry("b", 126n) ++ "," ++ Test.entry("c", 126n) ++ "," ++
        Test.entry("d", 126n),
      Test.entry("b", 126n) ++ "," ++ Test.entry("c", 126n) ++ "," ++ Test.entry("d", 126n), "a")
    # A 256-character key, "=" and a 256-character value: 513 octets.
    Unit <- Test.truncate("a single entry larger than the budget is dropped",
      Test.entry("k" ++ String.repeat("x", 255n), 256n), "", "k" ++ String.repeat("x", 255n))
    +wide : TC.Limits <- Test.limits_value(TC.Limits.new(55n, 1024n, 1024n))
    Test.truncate_with("a larger output budget keeps a 691-octet state whole", wide,
      Test.entry("a", 127n) ++ "," ++ Test.entry("b", 98n) ++ "," ++ Test.entry("c", 256n) ++ "," ++
        Test.entry("d", 98n) ++ "," ++ Test.entry("e", 98n),
      Test.entry("a", 127n) ++ "," ++ Test.entry("b", 98n) ++ "," ++ Test.entry("c", 256n) ++ "," ++
        Test.entry("d", 98n) ++ "," ++ Test.entry("e", 98n), "")

def Test.id(-A: Data, result: Result<&2, &2, TC.Error, A>) -> IO(A):
  match result:
    case Fail{error}:
      IO.die(A, 1, "FAIL: ID fixture: " ++ TC.Error.show(error))
    case Done{value}:
      IO.pure(A, value)

def Test.context(result: Result<&2, &2, TC.ContextError, TC.LocalContext>) -> IO(TC.LocalContext):
  match result:
    case Fail{error}:
      IO.die(TC.LocalContext, 1, "FAIL: context fixture: " ++ TC.ContextError.show(error))
    case Done{context}:
      IO.pure(TC.LocalContext, context)

def Test.emitted(+name: String, traceparent: String, tracestate: String, dropped: String,
  +emission: TC.Emission) -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.assert(name ++ ": traceparent", String.eq(TC.Emission.traceparent(emission), traceparent))
    Unit <- Test.assert(name ++ ": tracestate", String.eq(TC.Emission.tracestate(emission), tracestate))
    Test.assert(name ++ ": the keys dropped", String.eq(Test.keys(TC.Emission.dropped(emission)), dropped))

# A new root has no state, so it emits its traceparent alone.
def Test.outgoing_root(limits: TC.Limits, trace: TC.TraceId, span: TC.SpanId) -> IO(Unit):
  +root = TC.OutgoingContext.new(TC.Context.root_from_ids(trace, span))
  do IO<Unit>:
    Unit <- Test.assert("a new outgoing context has the empty state",
      TC.TraceState.is_empty(TC.OutgoingContext.state(root)))
    Test.emitted("a root emits its traceparent and no state",
      "00-4bf92f3577b34da6a3ce929d0e0e4736-53995c3f42cd8ad8-00", "", "", TC.OutgoingContext.emit(limits, root))

def Test.or_empty(value: Maybe<&2, TC.StateValue>) -> TC.StateValue:
  match value:
    case None{}:
      TC.StateValue{"none", {==}}
    case Some{found}:
      found

# A child of a received context carries the received state, which its
# participant may update, because the child's traceparent identifies a new
# operation.
def Test.outgoing_child(+limits: TC.Limits, +child: TC.LocalContext, state: TC.TraceState, +own: TC.StateKey,
  mine: TC.StateValue, rojo: TC.StateKey, large: TC.TraceState) -> IO(Unit):
  +updated = TC.OutgoingContext.set(TC.OutgoingContext.with_state(child, state), own, mine)
  +emission = TC.OutgoingContext.emit(limits, TC.OutgoingContext.with_state(child, large))
  do IO<Unit>:
    Unit <- Test.emitted("a child sends the received state with its participant's entry first",
      "00-4bf92f3577b34da6a3ce929d0e0e4736-53995c3f42cd8ad8-01",
      "fw529a3039=cHJpbWFyeQ,congo=t61rcWkgMzE,rojo=00f067aa0ba902b7", "", TC.OutgoingContext.emit(limits, updated))
    Unit <- Test.assert("an outgoing context finds the entry set in it",
      String.eq(TC.StateValue.to_string(Test.or_empty(TC.OutgoingContext.get(updated, own))), "cHJpbWFyeQ"))
    Unit <- Test.emitted("removing an entry keeps the context and the other entries",
      "00-4bf92f3577b34da6a3ce929d0e0e4736-53995c3f42cd8ad8-01", "fw529a3039=cHJpbWFyeQ,congo=t61rcWkgMzE", "",
      TC.OutgoingContext.emit(limits, TC.OutgoingContext.remove(updated, rojo)))
    Unit <- Test.emitted("an emission is truncated to the output budget",
      "00-4bf92f3577b34da6a3ce929d0e0e4736-53995c3f42cd8ad8-01", Test.entry("a", 256n), "b,c", emission)
    again : TC.TraceState <- Test.state("the emitted value",
      TC.TraceState.parse(limits, TC.Emission.tracestate(emission)))
    Test.assert("the same limits accept the emitted value",
      String.eq(TC.TraceState.format(again), Test.entry("a", 256n)))

def Test.outgoing() -> IO(Unit):
  +limits = TC.Limits.default()
  do IO<Unit>:
    trace : TC.TraceId <- Test.id(TC.TraceId, TC.TraceId.parse("4bf92f3577b34da6a3ce929d0e0e4736"))
    +span : TC.SpanId <- Test.id(TC.SpanId, TC.SpanId.parse("53995c3f42cd8ad8"))
    Unit <- Test.outgoing_root(limits, trace, span)
    received : TC.TraceParentV00 <- Test.id(TC.TraceParentV00,
      TC.TraceParentV00.parse("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"))
    child : TC.LocalContext <- Test.context(TC.Context.child_from_id(
      TC.RemoteParent{TC.RemoteContext.from_traceparent(received)}, span, TC.InheritSampled{}))
    state : TC.TraceState <- Test.parsed("congo=t61rcWkgMzE,rojo=00f067aa0ba902b7")
    own : TC.StateKey <- Test.key("fw529a3039")
    mine : TC.StateValue <- Test.value("cHJpbWFyeQ")
    rojo : TC.StateKey <- Test.key("rojo")
    # 258 + 258 + 258 octets and two commas: the emission keeps only a.
    large : TC.TraceState <- Test.parsed(
      Test.entry("a", 256n) ++ "," ++ Test.entry("b", 256n) ++ "," ++ Test.entry("c", 256n))
    Test.outgoing_child(limits, child, state, own, mine, rojo, large)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.updates()
    Unit <- Test.sizes()
    Unit <- Test.truncations()
    Unit <- IO.print("OK: whole-entry truncation to the output budget")
    Unit <- Test.outgoing()
    IO.print("OK: outgoing contexts and their emission")
