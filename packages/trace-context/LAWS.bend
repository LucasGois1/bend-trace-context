import Base
import ./trace_context.bend as Trace

# This is a statement about every value of the type, not just parsed examples.
law formatted_length:
  for context: Trace.TraceParentV00
  {String.length(Trace.TraceParentV00.format(context)) == 55n : Nat}

# The IDs, their evidence and all flag bits survive the complete codec.
law roundtrip:
  for context: Trace.TraceParentV00
  {Trace.TraceParentV00.parse(Trace.TraceParentV00.format(context)) ==
    Done{context} : Result<&2, &2, Trace.Error, Trace.TraceParentV00>}

# Quantified over every String: whenever the strict parser accepts a text,
# formatting the result reproduces exactly that text.
law inverse:
  for text: String
  for context: Trace.TraceParentV00
  for accepted: {Trace.TraceParentV00.parse(text) == Done{context} :
    Result<&2, &2, Trace.Error, Trace.TraceParentV00>}
  {Trace.TraceParentV00.format(context) == text : String}

# A supplied trace ID is exactly the text that was accepted, and parsing it
# makes no randomness assertion.
law trace_id_parse:
  for text: String
  for id: Trace.TraceId
  for accepted: {Trace.TraceId.parse(text) == Done{id} : Result<&2, &2, Trace.Error, Trace.TraceId>}
  {Trace.TraceId.to_string(id) == text : String} & {Trace.TraceId.is_random(id) == False{} : Bool}

law span_id_parse:
  for text: String
  for id: Trace.SpanId
  for accepted: {Trace.SpanId.parse(text) == Done{id} : Result<&2, &2, Trace.Error, Trace.SpanId>}
  {Trace.SpanId.to_string(id) == text : String}

# Conversely, the text of every trace ID is accepted, and every span ID's text
# parses back to that span ID.
law trace_id_accepts:
  for id: Trace.TraceId
  {Result.is_done(&2, &2, Trace.Error, Trace.TraceId, Trace.TraceId.parse(Trace.TraceId.to_string(id))) ==
    True{} : Bool}

law span_id_roundtrip:
  for id: Trace.SpanId
  {Trace.SpanId.parse(Trace.SpanId.to_string(id)) == Done{id} : Result<&2, &2, Trace.Error, Trace.SpanId>}

# Asserting randomness changes only the assertion, never the identifier.
law assert_random:
  for trace_id: Trace.TraceId
  {Trace.TraceId.is_random(Trace.TraceId.assert_random(trace_id)) == True{} : Bool} &
  {Trace.TraceId.to_string(Trace.TraceId.assert_random(trace_id)) == Trace.TraceId.to_string(trace_id) : String}

# Explicit construction keeps the supplied IDs and sampled indication.
law from_ids:
  for trace_id: Trace.TraceId
  for span_id: Trace.SpanId
  for sampled: Bool
  {Trace.LocalContext.trace_id(Trace.Context.from_ids(trace_id, span_id, sampled)) == trace_id : Trace.TraceId} &
  {Trace.LocalContext.span_id(Trace.Context.from_ids(trace_id, span_id, sampled)) == span_id : Trace.SpanId} &
  {Trace.LocalContext.is_sampled(Trace.Context.from_ids(trace_id, span_id, sampled)) == sampled : Bool}

# A root is the explicit construction of its supplied IDs with sampled 0.
law root:
  for trace_id: Trace.TraceId
  for span_id: Trace.SpanId
  {Trace.Context.root_from_ids(trace_id, span_id) == Trace.Context.from_ids(trace_id, span_id, False{}) : Trace.LocalContext}

# The only flag bytes a participant emits, from sampled (bit 0) and
# random-trace-id (bit 1).
def emitted_flags(sampled: Bool, random: Bool) -> String:
  match sampled random:
    case False{} False{}:
      "00"
    case True{} False{}:
      "01"
    case False{} True{}:
      "02"
    case True{} True{}:
      "03"

# Every local context is emitted as version 00 with its IDs and known flags;
# every reserved flag bit is zero.
law emitted_traceparent:
  for context: Trace.LocalContext
  {Trace.TraceParentV00.format(Trace.LocalContext.to_traceparent(context)) ==
    "00-" ++ Trace.TraceId.to_string(Trace.LocalContext.trace_id(context)) ++ "-" ++
    Trace.SpanId.to_string(Trace.LocalContext.span_id(context)) ++ "-" ++
    emitted_flags(Trace.LocalContext.is_sampled(context),
      Trace.TraceId.is_random(Trace.LocalContext.trace_id(context))) : String}

# Receiving an emitted local context recovers its trace ID, including the
# randomness assertion, its span ID and its sampled indication.
law emitted_projection:
  for context: Trace.LocalContext
  {Trace.RemoteContext.trace_id(Trace.RemoteContext.from_traceparent(Trace.LocalContext.to_traceparent(context))) ==
    Trace.LocalContext.trace_id(context) : Trace.TraceId} &
  {Trace.RemoteContext.span_id(Trace.RemoteContext.from_traceparent(Trace.LocalContext.to_traceparent(context))) ==
    Trace.LocalContext.span_id(context) : Trace.SpanId} &
  {Trace.RemoteContext.is_sampled(Trace.RemoteContext.from_traceparent(Trace.LocalContext.to_traceparent(context))) ==
    Trace.LocalContext.is_sampled(context) : Bool}

# A received context keeps the sender's sampled and random-trace-id flags.
law received_flags:
  for traceparent: Trace.TraceParentV00
  {Trace.RemoteContext.is_sampled(Trace.RemoteContext.from_traceparent(traceparent)) ==
    Trace.TraceParentV00.is_sampled(traceparent) : Bool} &
  {Trace.TraceId.is_random(Trace.RemoteContext.trace_id(Trace.RemoteContext.from_traceparent(traceparent))) ==
    Trace.TraceParentV00.is_random(traceparent) : Bool}

# A child either inherits its parent's sampled indication or takes the one set.
law sampling:
  for inherited: Bool
  for sampled: Bool
  {Trace.Sampling.resolve(Trace.InheritSampled{}, inherited) == inherited : Bool} &
  {Trace.Sampling.resolve(Trace.SetSampled{sampled}, inherited) == sampled : Bool}

# A successful child keeps the parent's trace ID and its randomness assertion,
# uses the supplied span ID, which differs from the parent's, and takes its
# sampled indication from the parent unless the caller sets it.
law child:
  for parent: Trace.Parent
  for span_id: Trace.SpanId
  for sampling: Trace.Sampling
  for created: Trace.LocalContext
  for accepted: {Trace.Context.child_from_id(parent, span_id, sampling) == Done{created} :
    Result<&2, &2, Trace.ContextError, Trace.LocalContext>}
  {Trace.LocalContext.trace_id(created) == Trace.Parent.trace_id(parent) : Trace.TraceId} &
  {Trace.LocalContext.span_id(created) == span_id : Trace.SpanId} &
  {Trace.LocalContext.is_sampled(created) ==
    Trace.Sampling.resolve(sampling, Trace.Parent.is_sampled(parent)) : Bool} &
  {Trace.SpanId.to_string(span_id) != Trace.SpanId.to_string(Trace.Parent.span_id(parent)) : String}

# A child reusing its parent's span ID is rejected.
law child_reuse:
  for parent: Trace.Parent
  for span_id: Trace.SpanId
  for sampling: Trace.Sampling
  for reused: {Trace.SpanId.to_string(span_id) == Trace.SpanId.to_string(Trace.Parent.span_id(parent)) : String}
  {Trace.Context.child_from_id(parent, span_id, sampling) == Fail{Trace.ReusedSpanId{}} :
    Result<&2, &2, Trace.ContextError, Trace.LocalContext>}

# Every other span ID is accepted: reuse is the only reason to refuse a child.
law child_accepts:
  for parent: Trace.Parent
  for span_id: Trace.SpanId
  for sampling: Trace.Sampling
  for distinct: {Trace.SpanId.to_string(span_id) != Trace.SpanId.to_string(Trace.Parent.span_id(parent)) : String}
  {Trace.Context.child_from_id(parent, span_id, sampling) ==
    Done{Trace.Context.from_ids(Trace.Parent.trace_id(parent), span_id,
      Trace.Sampling.resolve(sampling, Trace.Parent.is_sampled(parent)))} :
    Result<&2, &2, Trace.ContextError, Trace.LocalContext>}

# A successful restart is the root of its supplied IDs, and its trace ID
# differs from the received one.
law restart:
  for previous: Trace.RemoteContext
  for trace_id: Trace.TraceId
  for span_id: Trace.SpanId
  for restarted: Trace.LocalContext
  for accepted: {Trace.Context.restart_from_ids(previous, trace_id, span_id) == Done{restarted} :
    Result<&2, &2, Trace.ContextError, Trace.LocalContext>}
  {restarted == Trace.Context.root_from_ids(trace_id, span_id) : Trace.LocalContext} &
  {Trace.TraceId.to_string(trace_id) != Trace.TraceId.to_string(Trace.RemoteContext.trace_id(previous)) : String}

# A restart reusing the received trace ID is rejected.
law restart_reuse:
  for previous: Trace.RemoteContext
  for trace_id: Trace.TraceId
  for span_id: Trace.SpanId
  for reused: {Trace.TraceId.to_string(trace_id) ==
    Trace.TraceId.to_string(Trace.RemoteContext.trace_id(previous)) : String}
  {Trace.Context.restart_from_ids(previous, trace_id, span_id) == Fail{Trace.ReusedTraceId{}} :
    Result<&2, &2, Trace.ContextError, Trace.LocalContext>}

# Every other trace ID is accepted: reuse is the only reason to refuse a restart.
law restart_accepts:
  for previous: Trace.RemoteContext
  for trace_id: Trace.TraceId
  for span_id: Trace.SpanId
  for distinct: {Trace.TraceId.to_string(trace_id) !=
    Trace.TraceId.to_string(Trace.RemoteContext.trace_id(previous)) : String}
  {Trace.Context.restart_from_ids(previous, trace_id, span_id) ==
    Done{Trace.Context.root_from_ids(trace_id, span_id)} : Result<&2, &2, Trace.ContextError, Trace.LocalContext>}

# Identifiers from words. Words are converted most significant first: a
# candidate trace ID's text is its four words' texts in order, and a span ID's
# its two. No information is lost converting a word.
law trace_words:
  for first: U32
  for second: U32
  for third: U32
  for fourth: U32
  for id: Trace.TraceId
  for made: {Trace.TraceId.from_words(first, second, third, fourth) == Some{id} : Maybe<&2, Trace.TraceId>}
  {Trace.TraceId.to_string(id) ==
    Trace.U32.to_hex(first) ++ Trace.U32.to_hex(second) ++ Trace.U32.to_hex(third) ++ Trace.U32.to_hex(fourth) : String}

law span_words:
  for first: U32
  for second: U32
  for id: Trace.SpanId
  for made: {Trace.SpanId.from_words(first, second) == Some{id} : Maybe<&2, Trace.SpanId>}
  {Trace.SpanId.to_string(id) == Trace.U32.to_hex(first) ++ Trace.U32.to_hex(second) : String}

law hex_injective:
  for left: U32
  for right: U32
  for same: {Trace.U32.to_hex(left) == Trace.U32.to_hex(right) : String}
  {left == right : U32}

# The value of a lowercase hexadecimal digit: its position in `alphabet`,
# counted from `index`.
def hex_digit_value(alphabet: String, +char: Char, +index: Nat) -> Nat:
  match alphabet:
    case SNil{}:
      index
    case SCon{candidate, rest}:
      Bool.pick(Nat, Char.is_eq(char, candidate), index, hex_digit_value(rest, char, 1n+index))

def times16(value: Nat) -> Nat:
  Nat.double(Nat.double(Nat.double(Nat.double(value))))

# The value of a hexadecimal numeral, its first digit most significant.
def hex_numeral(text: String, value: Nat) -> Nat:
  match text:
    case SNil{}:
      value
    case SCon{char, rest}:
      hex_numeral(rest, Nat.add(hex_digit_value("0123456789abcdef", char, 0n), times16(value)))

# Digits are big-endian within a word too: a word's text is the base-16
# numeral of the number Base assigns to the word.
law word_hex:
  for word: U32
  {hex_numeral(Trace.U32.to_hex(word), 0n) == U32.to_nat(word) : Nat}

# Converting words makes no randomness assertion, as parsing makes none;
# generation makes it (generated_root, generated_restart).
law words_unasserted:
  for first: U32
  for second: U32
  for third: U32
  for fourth: U32
  for id: Trace.TraceId
  for made: {Trace.TraceId.from_words(first, second, third, fourth) == Some{id} : Maybe<&2, Trace.TraceId>}
  {Trace.TraceId.is_random(id) == False{} : Bool}

# A source error ends a generation at once.
law feed_failure:
  for code: U32
  for message: String
  for draw: Trace.Draw
  {Trace.Draw.feed(Fail{(code, message)}, draw) == Trace.Failed{Trace.SourceFailure{code, message}} : Trace.Step}

# A tape of source results, and what reading it leaves.
def Tape() -> Type:
  List<&1, Result<&1, &1, U32 & String, U32>>

def TapeStep() -> Type:
  Tape() & Trace.Step

def TapeOutcome() -> Type:
  Tape() & Result<&2, &2, Trace.GenerationError, Trace.LocalContext>

# The value an IO action produces when every effect in it is pure.
def Observe(-A: Type, action: IO(A)) -> IO.OP<A>:
  action(A, value => Emit{value})

def zeros(count: Nat) -> Tape():
  match count:
    case 0n:
      Nil{}
    case 1n+p:
      Con{Done{0}, zeros(p)}

# Generating from a tape performs exactly the pure tape driver: the same words
# are read, in order, and the unread words are handed back.
law root_tape:
  for tape: Tape()
  {Observe(TapeOutcome(), Trace.Context.root_with(~Tape(), ~Trace.Source.tape, tape)) ==
    Emit{Trace.Draw.outcome(Tape(), Trace.Draw.run(48n, (tape, Trace.Draw.root())))} : IO.OP<TapeOutcome()>}

law child_tape:
  for tape: Tape()
  for parent: Trace.Parent
  for sampling: Trace.Sampling
  {Observe(TapeOutcome(), Trace.Context.child_with(~Tape(), ~Trace.Source.tape, tape, parent, sampling)) ==
    Emit{Trace.Draw.outcome(Tape(), Trace.Draw.run(16n, (tape, Trace.Draw.child(parent, sampling))))} :
    IO.OP<TapeOutcome()>}

law restart_tape:
  for tape: Tape()
  for previous: Trace.RemoteContext
  {Observe(TapeOutcome(), Trace.Context.restart_with(~Tape(), ~Trace.Source.tape, tape, previous)) ==
    Emit{Trace.Draw.outcome(Tape(), Trace.Draw.run(48n, (tape, Trace.Draw.restart(previous))))} :
    IO.OP<TapeOutcome()>}

# Whatever a tape holds, a root or restart ends within 48 words and a child
# within 16: eight candidates of four words and eight of two.
law root_ends:
  for tape: Tape()
  {Trace.Draw.ended(Trace.Draw.run(48n, (tape, Trace.Draw.root()))) == True{} : Bool}

law child_ends:
  for tape: Tape()
  for +parent: Trace.Parent
  for +sampling: Trace.Sampling
  {Trace.Draw.ended(Trace.Draw.run(16n, (tape, Trace.Draw.child(parent, sampling)))) == True{} : Bool}

law restart_ends:
  for tape: Tape()
  for +previous: Trace.RemoteContext
  {Trace.Draw.ended(Trace.Draw.run(48n, (tape, Trace.Draw.restart(previous)))) == True{} : Bool}

# Eight all-zero candidates exhaust a root's trace ID or a child's span ID
# without reading a ninth: the words after them stay on the tape.
law root_exhaustion:
  for rest: Tape()
  {Trace.Draw.run(48n, (List.append(&1, Result<&1, &1, U32 & String, U32>, zeros(32n), rest), Trace.Draw.root())) ==
    (rest, Trace.Failed{Trace.ExhaustedTraceId{}}) : TapeStep()}

law child_exhaustion:
  for parent: Trace.Parent
  for sampling: Trace.Sampling
  for rest: Tape()
  {Trace.Draw.run(16n, (List.append(&1, Result<&1, &1, U32 & String, U32>, zeros(16n), rest),
    Trace.Draw.child(parent, sampling))) == (rest, Trace.Failed{Trace.ExhaustedSpanId{}}) : TapeStep()}

# A generated root asserts random-trace-id and is not sampled: flags 02.
law generated_root:
  for tape: Tape()
  for rest: Tape()
  for created: Trace.LocalContext
  for generated: {Trace.Draw.run(48n, (tape, Trace.Draw.root())) == (rest, Trace.Created{created}) : TapeStep()}
  {Trace.TraceId.is_random(Trace.LocalContext.trace_id(created)) == True{} : Bool} &
  {Trace.LocalContext.is_sampled(created) == False{} : Bool}

# A generated child keeps the parent's trace ID and randomness assertion, takes
# sampled from the parent unless set, and never reuses the parent's span ID.
law generated_child:
  for tape: Tape()
  for +parent: Trace.Parent
  for +sampling: Trace.Sampling
  for rest: Tape()
  for created: Trace.LocalContext
  for generated: {Trace.Draw.run(16n, (tape, Trace.Draw.child(parent, sampling))) ==
    (rest, Trace.Created{created}) : TapeStep()}
  {Trace.LocalContext.trace_id(created) == Trace.Parent.trace_id(parent) : Trace.TraceId} &
  {Trace.LocalContext.is_sampled(created) == Trace.Sampling.resolve(sampling, Trace.Parent.is_sampled(parent)) : Bool} &
  {Trace.SpanId.to_string(Trace.LocalContext.span_id(created)) !=
    Trace.SpanId.to_string(Trace.Parent.span_id(parent)) : String}

# A generated restart starts a new trace: its trace ID differs from the
# received one and asserts randomness, and it is not sampled.
law generated_restart:
  for tape: Tape()
  for +previous: Trace.RemoteContext
  for rest: Tape()
  for created: Trace.LocalContext
  for generated: {Trace.Draw.run(48n, (tape, Trace.Draw.restart(previous))) ==
    (rest, Trace.Created{created}) : TapeStep()}
  {Trace.TraceId.to_string(Trace.LocalContext.trace_id(created)) !=
    Trace.TraceId.to_string(Trace.RemoteContext.trace_id(previous)) : String} &
  {Trace.TraceId.is_random(Trace.LocalContext.trace_id(created)) == True{} : Bool} &
  {Trace.LocalContext.is_sampled(created) == False{} : Bool}

# Tracestate
# ----------

# A validated configuration accepts its own emitted representation: at least
# 55 octets of traceparent input, at least 512 octets of tracestate output,
# and no less tracestate input than output.
law limits_bounds:
  for limits: Trace.Limits
  {Nat.is_ge(Trace.Limits.traceparent_input(limits), 55n) == True{} : Bool} &
  {Nat.is_ge(Trace.Limits.tracestate_output(limits), 512n) == True{} : Bool} &
  {Nat.is_ge(Trace.Limits.tracestate_input(limits), Trace.Limits.tracestate_output(limits)) == True{} : Bool}

# Limits.new accepts exactly the configurations that meet those rules...
law limits_new:
  for +traceparent_input: Nat
  for +tracestate_input: Nat
  for +tracestate_output: Nat
  {Result.is_done(&2, &2, Trace.LimitsError, Trace.Limits,
    Trace.Limits.new(traceparent_input, tracestate_input, tracestate_output)) ==
    Bool.and(Nat.is_ge(traceparent_input, 55n),
      Bool.and(Nat.is_ge(tracestate_output, 512n), Nat.is_ge(tracestate_input, tracestate_output))) : Bool}

# ...and keeps the budgets it accepts.
law limits_fields:
  for +traceparent_input: Nat
  for +tracestate_input: Nat
  for +tracestate_output: Nat
  for limits: Trace.Limits
  for accepted: {Trace.Limits.new(traceparent_input, tracestate_input, tracestate_output) == Done{limits} :
    Result<&2, &2, Trace.LimitsError, Trace.Limits>}
  {Trace.Limits.traceparent_input(limits) == traceparent_input : Nat} &
  {Trace.Limits.tracestate_input(limits) == tracestate_input : Nat} &
  {Trace.Limits.tracestate_output(limits) == tracestate_output : Nat}

# 32 KiB for each received value and 512 octets for an emitted tracestate.
law default_limits:
  {Trace.Limits.traceparent_input(Trace.Limits.default()) == 32768n : Nat} &
  {Trace.Limits.tracestate_input(Trace.Limits.default()) == 32768n : Nat} &
  {Trace.Limits.tracestate_output(Trace.Limits.default()) == 512n : Nat}

# An accepted key or value is exactly the text accepted, and the text of every
# key or value is accepted as that key or value.
law key_parse:
  for +text: String
  for key: Trace.StateKey
  for accepted: {Trace.StateKey.parse(text) == Done{key} : Result<&2, &2, Trace.EntryError, Trace.StateKey>}
  {Trace.StateKey.to_string(key) == text : String}

law key_roundtrip:
  for key: Trace.StateKey
  {Trace.StateKey.parse(Trace.StateKey.to_string(key)) == Done{key} : Result<&2, &2, Trace.EntryError, Trace.StateKey>}

law value_parse:
  for +text: String
  for value: Trace.StateValue
  for accepted: {Trace.StateValue.parse(text) == Done{value} : Result<&2, &2, Trace.EntryError, Trace.StateValue>}
  {Trace.StateValue.to_string(value) == text : String}

law value_roundtrip:
  for value: Trace.StateValue
  {Trace.StateValue.parse(Trace.StateValue.to_string(value)) == Done{value} :
    Result<&2, &2, Trace.EntryError, Trace.StateValue>}

# Whether an entry of `entries` has the key `key`.
def key_among(+key: String, entries: List<&2, Trace.StateEntry>) -> Bool:
  match entries:
    case Nil{}:
      False{}
    case Con{entry, rest}:
      Bool.or(String.eq(key, Trace.StateEntry.key_text(entry)), key_among(key, rest))

# No two entries have the same key.
def keys_distinct(entries: List<&2, Trace.StateEntry>) -> Bool:
  match entries:
    case Nil{}:
      True{}
    case Con{entry, +rest}:
      Bool.and(Bool.not(key_among(Trace.StateEntry.key_text(entry), rest)), keys_distinct(rest))

# Every state, parsed or not, has distinct keys and at most 32 entries.
law state_valid:
  for state: Trace.TraceState
  {keys_distinct(Trace.TraceState.entries(state)) == True{} : Bool} &
  {Nat.is_le(List.length(&2, Trace.StateEntry, Trace.TraceState.entries(state)), 32n) == True{} : Bool}

# Every entry of a state is found by its key...
law get_entry:
  for state: Trace.TraceState
  for +before: List<&2, Trace.StateEntry>
  for +entry: Trace.StateEntry
  for +after: List<&2, Trace.StateEntry>
  for +split: {Trace.TraceState.entries(state) == List.append(&2, Trace.StateEntry, before, Con{entry, after}) :
    List<&2, Trace.StateEntry>}
  {Trace.TraceState.get(state, Trace.StateEntry.key(entry)) == Some{Trace.StateEntry.value(entry)} :
    Maybe<&2, Trace.StateValue>}

# ...and a key no entry has is absent.
law get_absent:
  for state: Trace.TraceState
  for +key: Trace.StateKey
  for absent: {key_among(Trace.StateKey.to_string(key), Trace.TraceState.entries(state)) == False{} : Bool}
  {Trace.TraceState.get(state, key) == None{} : Maybe<&2, Trace.StateValue>}

# Parsing a state's normalized value gives back that state whenever the value
# fits the tracestate input budget. Normalization drops optional whitespace,
# empty members and later duplicates, so received text need not be restored.
law state_roundtrip:
  for +limits: Trace.Limits
  for state: Trace.TraceState
  for fits: {Nat.is_le(Trace.Utf8.length(Trace.TraceState.format(state)), Trace.Limits.tracestate_input(limits)) ==
    True{} : Bool}
  {Trace.TraceState.parse(limits, Trace.TraceState.format(state)) == Done{state} :
    Result<&2, &2, Trace.StateError, Trace.TraceState>}

# A value whose UTF-8 octets exceed the budget is refused, whatever it holds...
law over_budget:
  for +limits: Trace.Limits
  for +text: String
  for larger: {Nat.is_le(Trace.Utf8.length(text), Trace.Limits.tracestate_input(limits)) == False{} : Bool}
  {Trace.TraceState.parse(limits, text) == Fail{Trace.StateTooLarge{}} :
    Result<&2, &2, Trace.StateError, Trace.TraceState>}

# ...and within the budget its size changes nothing: any budget the value fits
# gives the same result.
law within_budgets:
  for +first: Trace.Limits
  for +second: Trace.Limits
  for +text: String
  for first_fits: {Nat.is_le(Trace.Utf8.length(text), Trace.Limits.tracestate_input(first)) == True{} : Bool}
  for second_fits: {Nat.is_le(Trace.Utf8.length(text), Trace.Limits.tracestate_input(second)) == True{} : Bool}
  {Trace.TraceState.parse(first, text) == Trace.TraceState.parse(second, text) :
    Result<&2, &2, Trace.StateError, Trace.TraceState>}

# Repeated fields are parsed as their comma-joined combination, so the
# joining commas count toward the budget and member numbers run across fields.
law fields_join:
  for +limits: Trace.Limits
  for +fields: List<&2, String>
  {Trace.TraceState.parse_fields(limits, fields) == Trace.TraceState.parse(limits, String.join(fields, ",")) :
    Result<&2, &2, Trace.StateError, Trace.TraceState>}

# The first entry of a key is kept: a later entry repeating a key of the state
# is dropped, although it counts toward the 32 members...
law later_duplicate:
  for +limits: Trace.Limits
  for +state: Trace.TraceState
  for +entry: Trace.StateEntry
  for present: {key_among(Trace.StateEntry.key_text(entry), Trace.TraceState.entries(state)) == True{} : Bool}
  for room: {Nat.is_lt(List.length(&2, Trace.StateEntry, Trace.TraceState.entries(state)), 32n) == True{} : Bool}
  for fits: {Nat.is_le(Trace.Utf8.length(Trace.TraceState.format(state) ++ "," ++ Trace.StateEntry.format(entry)),
    Trace.Limits.tracestate_input(limits)) == True{} : Bool}
  {Trace.TraceState.parse(limits, Trace.TraceState.format(state) ++ "," ++ Trace.StateEntry.format(entry)) ==
    Done{state} : Result<&2, &2, Trace.StateError, Trace.TraceState>}

# ...a later entry with a new key follows every earlier entry, in order...
law later_new_key:
  for +limits: Trace.Limits
  for +state: Trace.TraceState
  for +entry: Trace.StateEntry
  for +absent: {key_among(Trace.StateEntry.key_text(entry), Trace.TraceState.entries(state)) == False{} : Bool}
  for +room: {Nat.is_lt(List.length(&2, Trace.StateEntry, Trace.TraceState.entries(state)), 32n) == True{} : Bool}
  for fits: {Nat.is_le(Trace.Utf8.length(Trace.TraceState.format(state) ++ "," ++ Trace.StateEntry.format(entry)),
    Trace.Limits.tracestate_input(limits)) == True{} : Bool}
  {Result.map(&2, &2, Trace.StateError, Trace.TraceState, List<&2, Trace.StateEntry>,
    parsed => Trace.TraceState.entries(parsed),
    Trace.TraceState.parse(limits, Trace.TraceState.format(state) ++ "," ++ Trace.StateEntry.format(entry))) ==
    Done{List.append(&2, Trace.StateEntry, Trace.TraceState.entries(state), Con{entry, Nil{}})} :
    Result<&2, &2, Trace.StateError, List<&2, Trace.StateEntry>>}

# ...and members are counted before duplicates are dropped: after 32 entries,
# any further entry is refused, even one repeating a key.
law full_state:
  for +limits: Trace.Limits
  for state: Trace.TraceState
  for entry: Trace.StateEntry
  for full: {List.length(&2, Trace.StateEntry, Trace.TraceState.entries(state)) == 32n : Nat}
  for fits: {Nat.is_le(Trace.Utf8.length(Trace.TraceState.format(state) ++ "," ++ Trace.StateEntry.format(entry)),
    Trace.Limits.tracestate_input(limits)) == True{} : Bool}
  {Trace.TraceState.parse(limits, Trace.TraceState.format(state) ++ "," ++ Trace.StateEntry.format(entry)) ==
    Fail{Trace.TooManyMembers{}} : Result<&2, &2, Trace.StateError, Trace.TraceState>}

# Whether no character of `text` is `char`.
def lacks(+char: Char, text: String) -> Bool:
  match text:
    case SNil{}:
      True{}
    case SCon{first, rest}:
      Bool.and(Bool.not(Char.is_eq(first, char)), lacks(char, rest))

# No key or value contains the comma that separates members or the equals sign
# that ends a key, so a formatted state has one reading.
law key_separators:
  for key: Trace.StateKey
  {lacks(',', Trace.StateKey.to_string(key)) == True{} : Bool} &
  {lacks('=', Trace.StateKey.to_string(key)) == True{} : Bool}

law value_separators:
  for value: Trace.StateValue
  {lacks(',', Trace.StateValue.to_string(value)) == True{} : Bool} &
  {lacks('=', Trace.StateValue.to_string(value)) == True{} : Bool}

# Whether every character of `text` is optional whitespace: a space or a
# horizontal tab.
def all_ows(text: String) -> Bool:
  match text:
    case SNil{}:
      True{}
    case SCon{+first, rest}:
      Bool.and(Bool.or(Char.is_eq(first, ' '), Char.is_eq(first, '\t')), all_ows(rest))

# Optional whitespace before and after a normalized value changes nothing:
# before the first key it is skipped, and after the last value it is not part
# of that value.
law ows_around:
  for +limits: Trace.Limits
  for state: Trace.TraceState
  for +before: String
  for +after: String
  for before_ows: {all_ows(before) == True{} : Bool}
  for after_ows: {all_ows(after) == True{} : Bool}
  for fits: {Nat.is_le(Trace.Utf8.length(before ++ Trace.TraceState.format(state) ++ after),
    Trace.Limits.tracestate_input(limits)) == True{} : Bool}
  {Trace.TraceState.parse(limits, before ++ Trace.TraceState.format(state) ++ after) == Done{state} :
    Result<&2, &2, Trace.StateError, Trace.TraceState>}

# The entries of `later` whose keys no entry of `earlier` has, in order.
def missing(+earlier: List<&2, Trace.StateEntry>, later: List<&2, Trace.StateEntry>) -> List<&2, Trace.StateEntry>:
  match later:
    case Nil{}:
      Nil{}
    case Con{+entry, +rest}:
      Bool.pick(List<&2, Trace.StateEntry>, key_among(Trace.StateEntry.key_text(entry), earlier),
        missing(earlier, rest), Con{entry, missing(earlier, rest)})

# Two states' values joined by a comma parse as the first state's entries
# followed, in order, by the second's entries whose keys the first lacks,
# whenever the value fits and their entries number at most 32 together.
law first_wins:
  for +limits: Trace.Limits
  for first: Trace.TraceState
  for second: Trace.TraceState
  for +count: {Nat.is_le(Nat.add(List.length(&2, Trace.StateEntry, Trace.TraceState.entries(first)),
    List.length(&2, Trace.StateEntry, Trace.TraceState.entries(second))), 32n) == True{} : Bool}
  for fits: {Nat.is_le(Trace.Utf8.length(Trace.TraceState.format(first) ++ "," ++ Trace.TraceState.format(second)),
    Trace.Limits.tracestate_input(limits)) == True{} : Bool}
  {Result.map(&2, &2, Trace.StateError, Trace.TraceState, List<&2, Trace.StateEntry>,
    parsed => Trace.TraceState.entries(parsed),
    Trace.TraceState.parse(limits, Trace.TraceState.format(first) ++ "," ++ Trace.TraceState.format(second))) ==
    Done{List.append(&2, Trace.StateEntry, Trace.TraceState.entries(first),
      missing(Trace.TraceState.entries(first), Trace.TraceState.entries(second)))} :
    Result<&2, &2, Trace.StateError, List<&2, Trace.StateEntry>>}
