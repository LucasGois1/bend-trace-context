# Proofs of the laws of bend-trace-context
# ========================================
#
# Each `def Laws.name(...)` below proves `law name` of LAWS.bend. Its
# parameters are the law's `for` lines, in order, and its body is a term whose
# type is the law's conclusion. In Bend a proposition is a type and a proof is
# an ordinary definition of that type: there are no tactics, and the checker
# verifies every step. The checker accepts this file only when every law of
# LAWS.bend has a proof, so
#
#   ./bend packages/trace-context/PROOF.bend --check-only
#
# is the proof gate of the package: it prints "All terms check.".
# scripts/validate.sh runs it on every backend and refuses any reliance on
# `@unsafe`, which would skip the termination check and void the proofs.
#
# Most proofs here call a lemma from proofs/, where the work is done. The
# notation used there:
#
#   {==}              reflexivity: both sides compute to the same term.
#   %e : P            rewrite with an equation e : {a == b : T}. P is the
#                     current goal with `_` where b appears, and the goal
#                     becomes P with a in that place. Equal.sym(T, a, b, e)
#                     turns an equation around; Equal.trans chains two.
#   %q@e : P          the same rewrite, also naming the equation's proof q. It
#                     replaces a proof stored inside a value, for example the
#                     evidence field of a StateKey, by the one given.
#   match x: case     case analysis: each case refines the goal for that
#                     constructor.
#   recursive call    the induction hypothesis. Bend checks that it is called
#                     on a structurally smaller argument.
#   views             many lemmas state a "view": a type computed from a
#                     result, Unit for a failure and the property for a
#                     success. Proving the view for every input, then
#                     rewriting a hypothesis {f(x) == Done{v}} into it, proves
#                     the property of every success.
#
# Proof modules:
#
#   proofs/hex.bend, digits.bend,   hexadecimal digits, digit sequences,
#     chars.bend, strings.bend      character and string equality, lengths
#   proofs/parser.bend,             the strict codec and supplied IDs
#     inverse.bend, context.bend,
#     ids.bend
#   proofs/lifecycle.bend           children and restarts from supplied IDs
#   proofs/words.bend,              source words to hexadecimal digits
#     conversion.bend
#   proofs/generation.bend          the generation machine over tapes
#   proofs/bools.bend, lists.bend,  general lemmas on Bool, List and Nat
#     nats.bend
#   proofs/limits.bend              Limits
#   proofs/tracestate.bend          tracestate characters, keys, values,
#                                   reading an entry, budgets, repeated fields
#   proofs/distinct.bend            distinct keys and lookups
#   proofs/merge.bend               a state's value followed by one entry
#   proofs/normal.bend              separators and optional whitespace
#   proofs/first.bend               two states' values joined by a comma

import Base
import ./LAWS.bend as Laws
import ./trace_context.bend as Trace
import ./src/digits.bend as Digits
import ./proofs/digits.bend as DigitsProof
import ./proofs/strings.bend as StringsProof
import ./proofs/context.bend as ContextProof
import ./proofs/inverse.bend as InverseProof
import ./proofs/ids.bend as IdsProof
import ./proofs/lifecycle.bend as LifecycleProof
import ./proofs/words.bend as WordsProof
import ./proofs/conversion.bend as ConversionProof
import ./proofs/generation.bend as GenerationProof
import ./proofs/limits.bend as LimitsProof
import ./proofs/tracestate.bend as StateProof
import ./proofs/distinct.bend as DistinctProof
import ./proofs/merge.bend as MergeProof
import ./proofs/normal.bend as NormalProof
import ./proofs/first.bend as FirstProof

# 1. Strict v00 codec
# ===================

# The text is "00-" ++ trace ++ "-" ++ parent ++ "-" ++ flags: add the lengths
# of the pieces, 3 + 32 + 1 + 16 + 1 + 2, from the innermost outwards.
def Laws.formatted_length(context):
  match context:
    case Trace.TraceParentV00{+trace_id, +parent_id, +flags}:
      +trace = Digits.NonZero.to_string(32n, trace_id)
      +parent = Digits.NonZero.to_string(16n, parent_id)
      +flag_text = Digits.Digits.to_string(2n, flags)
      f = StringsProof.joined_length("-", flag_text, 1n, 2n,
        {==}, DigitsProof.encoded_length(2n, flags))
      p = StringsProof.joined_length(parent, "-" ++ flag_text, 16n, 3n,
        DigitsProof.nonzero_encoded_length(16n, parent_id), f)
      ps = StringsProof.joined_length("-", parent ++ "-" ++ flag_text,
        1n, 19n, {==}, p)
      t = StringsProof.joined_length(trace, "-" ++ parent ++ "-" ++ flag_text,
        32n, 20n, DigitsProof.nonzero_encoded_length(32n, trace_id), ps)
      StringsProof.joined_length("00-", trace ++ "-" ++ parent ++ "-" ++ flag_text,
        3n, 52n, {==}, t)

# The parser reads back each field that the formatter wrote
# (proofs/context.bend).
def Laws.roundtrip(context):
  ContextProof.roundtrip(context)

# Rewrite the hypothesis into the parser's view of `text`, which holds for
# every string: a success reproduces its input.
def Laws.inverse(text, context, accepted):
  %accepted : InverseProof.ParseView(text, _)
  InverseProof.parse_view(text)

# 2. Supplied identifiers
# =======================

# Views of the ID parser: an accepted ID is its text, with no randomness
# assertion.
def Laws.trace_id_parse(text, id, accepted):
  %accepted : IdsProof.TraceIdView(text, _)
  IdsProof.trace_id_view(text)

# As trace_id_parse, for span IDs.
def Laws.span_id_parse(text, id, accepted):
  %accepted : IdsProof.SpanIdView(text, _)
  IdsProof.span_id_view(text)

# The ID parser reads the canonical text of the digits back.
def Laws.trace_id_accepts(id):
  IdsProof.trace_id_accepts(id)

# The ID parser reads the canonical text back, evidence included.
def Laws.span_id_roundtrip(id):
  IdsProof.span_id_roundtrip(id)

# Both sides compute once the trace ID is split into its fields.
def Laws.assert_random(trace_id):
  match trace_id:
    case Trace.TraceId{value, random}:
      ({==}, {==})

# 3. Local contexts and flags
# ===========================

# By computation.
def Laws.from_ids(trace_id, span_id, sampled):
  ({==}, ({==}, {==}))

# By computation.
def Laws.root(trace_id, span_id):
  {==}

# By computation in each of the four combinations of sampled and random.
def Laws.emitted_traceparent(context):
  match context:
    case Trace.LocalContext{Trace.TraceId{trace_id, False{}}, Trace.SpanId{span_id}, False{}}:
      {==}
    case Trace.LocalContext{Trace.TraceId{trace_id, False{}}, Trace.SpanId{span_id}, True{}}:
      {==}
    case Trace.LocalContext{Trace.TraceId{trace_id, True{}}, Trace.SpanId{span_id}, False{}}:
      {==}
    case Trace.LocalContext{Trace.TraceId{trace_id, True{}}, Trace.SpanId{span_id}, True{}}:
      {==}

# By computation in each of the four combinations of sampled and random.
def Laws.emitted_projection(context):
  match context:
    case Trace.LocalContext{Trace.TraceId{trace_id, False{}}, Trace.SpanId{span_id}, False{}}:
      ({==}, ({==}, {==}))
    case Trace.LocalContext{Trace.TraceId{trace_id, False{}}, Trace.SpanId{span_id}, True{}}:
      ({==}, ({==}, {==}))
    case Trace.LocalContext{Trace.TraceId{trace_id, True{}}, Trace.SpanId{span_id}, False{}}:
      ({==}, ({==}, {==}))
    case Trace.LocalContext{Trace.TraceId{trace_id, True{}}, Trace.SpanId{span_id}, True{}}:
      ({==}, ({==}, {==}))

# By computation once the flag byte is split into its two digits.
def Laws.received_flags(traceparent):
  match traceparent:
    case Trace.TraceParentV00{trace_id, parent_id,
      Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}}:
      ({==}, {==})

# 4. Children and restarts
# ========================

# By computation.
def Laws.sampling(inherited, sampled):
  ({==}, {==})

# Rewrite the hypothesis into the view of a child creation.
def Laws.child(parent, span_id, sampling, created, accepted):
  %accepted : LifecycleProof.ChildView(parent, span_id,
    Trace.Sampling.resolve(sampling, Trace.Parent.is_sampled(parent)), _)
  LifecycleProof.child_view(parent, span_id, sampling)

# The reuse check compares equal texts, which String.eq reports as equal.
def Laws.child_reuse(parent, span_id, sampling, reused):
  LifecycleProof.child_reuse(parent, span_id, sampling, reused)

# The reuse check compares different texts, which String.eq cannot report as
# equal.
def Laws.child_accepts(parent, span_id, sampling, distinct):
  LifecycleProof.child_accepts(parent, span_id, sampling, distinct)

# Rewrite the hypothesis into the view of a restart.
def Laws.restart(previous, trace_id, span_id, restarted, accepted):
  %accepted : LifecycleProof.RestartView(previous, trace_id, span_id, _)
  LifecycleProof.restart_view(previous, trace_id, span_id)

# As child_reuse, for the received trace ID.
def Laws.restart_reuse(previous, trace_id, span_id, reused):
  LifecycleProof.restart_reuse(previous, trace_id, span_id, reused)

# As child_accepts, for the received trace ID.
def Laws.restart_accepts(previous, trace_id, span_id, distinct):
  LifecycleProof.restart_accepts(previous, trace_id, span_id, distinct)

# 5. Identifiers from source words
# ================================

# Rewrite the hypothesis into the view of the word conversion.
def Laws.trace_words(first, second, third, fourth, id, made):
  %made : ConversionProof.TraceWordsView(first, second, third, fourth, _)
  ConversionProof.trace_words_view(first, second, third, fourth)

# Rewrite the hypothesis into the view of the word conversion.
def Laws.span_words(first, second, id, made):
  %made : ConversionProof.SpanWordsView(first, second, _)
  ConversionProof.span_words_view(first, second)

# Parsing the two equal texts back gives equal digits, and the digits give
# back the word, because Digits.to_u32 inverts Digits.of_u32
# (proofs/conversion.bend and proofs/words.bend).
def Laws.hex_injective(left, right, same):
  ConversionProof.hex_injective(left, right, same)

# The value of the digits, bit by bit, is Base's value of the word
# (proofs/words.bend).
def Laws.word_hex(word):
  WordsProof.word_value(word)

# Every candidate the conversion builds has its assertion unset.
def Laws.words_unasserted(first, second, third, fourth, id, made):
  %made : ConversionProof.UnassertedCandidate(_)
  ConversionProof.words_unasserted(first, second, third, fourth)

# 6. Generation from an identifier source
# =======================================

# By computation: an error result ends the machine whatever its state.
def Laws.feed_failure(code, message, draw):
  {==}

# The IO driver over a tape source computes the pure driver step by step.
def Laws.root_tape(tape):
  GenerationProof.root_tape(tape)

# As root_tape.
def Laws.child_tape(tape, parent, sampling):
  GenerationProof.child_tape(tape, parent, sampling)

# As root_tape.
def Laws.restart_tape(tape, previous):
  GenerationProof.restart_tape(tape, previous)

# Every step reads a word, and each candidate takes a bounded number of steps.
def Laws.root_ends(tape):
  GenerationProof.run_ends(48n, Trace.Draw.root(), tape, GenerationProof.root_within())

# As root_ends.
def Laws.child_ends(tape, parent, sampling):
  GenerationProof.run_ends(16n, Trace.Draw.child(parent, sampling), tape,
    GenerationProof.child_within(parent, sampling))

# As root_ends.
def Laws.restart_ends(tape, previous):
  GenerationProof.run_ends(48n, Trace.Draw.restart(previous), tape, GenerationProof.restart_within(previous))

# By computation on the concrete tape of 32 zero words.
def Laws.root_exhaustion(rest):
  {==}

# By computation on the concrete tape of 16 zero words.
def Laws.child_exhaustion(parent, sampling, rest):
  {==}

# Rewrite the hypothesis into the view of the driver's final step.
def Laws.generated_root(tape, rest, created, generated):
  %generated : GenerationProof.RootRun(_)
  GenerationProof.root_run(48n, Trace.Draw.root(), tape, {==})

# Rewrite the hypothesis into the view of the driver's final step.
def Laws.generated_child(tape, parent, sampling, rest, created, generated):
  %generated : GenerationProof.ChildRun(parent, sampling, _)
  GenerationProof.child_run(parent, sampling, 16n, Trace.Draw.child(parent, sampling), tape,
    ({==}, ({==}, {==})))

# Rewrite the hypothesis into the view of the driver's final step.
def Laws.generated_restart(tape, previous, rest, created, generated):
  %generated : GenerationProof.RestartRun(previous, _)
  GenerationProof.restart_run(previous, 48n, Trace.Draw.restart(previous), tape, {==})

# 7. Limits
# =========

# Split the evidence stored in the Limits value into its three rules.
def Laws.limits_bounds(limits):
  LimitsProof.bounds(limits)

# Limits.new returns Done exactly in the True case of its check.
def Laws.limits_new(traceparent_input, tracestate_input, tracestate_output):
  LimitsProof.new_accepts(traceparent_input, tracestate_input, tracestate_output)

# Rewrite the hypothesis into the view of Limits.new.
def Laws.limits_fields(traceparent_input, tracestate_input, tracestate_output, limits, accepted):
  %accepted : LimitsProof.NewView(traceparent_input, tracestate_input, tracestate_output, _)
  LimitsProof.new_view(traceparent_input, tracestate_input, tracestate_output)

# By computation.
def Laws.default_limits():
  ({==}, ({==}, {==}))

# 8. Tracestate keys and values
# =============================

# Rewrite the hypothesis into the view of StateKey.parse.
def Laws.key_parse(text, key, accepted):
  %accepted : StateProof.KeyView(text, _)
  StateProof.key_view(text)

# The check accepts the key's text, and the proof it builds is replaced by
# the key's own evidence.
def Laws.key_roundtrip(key):
  StateProof.key_roundtrip(key)

# Rewrite the hypothesis into the view of StateValue.parse.
def Laws.value_parse(text, value, accepted):
  %accepted : StateProof.ValueView(text, _)
  StateProof.value_view(text)

# As key_roundtrip, for values.
def Laws.value_roundtrip(value):
  StateProof.value_roundtrip(value)

# By induction over the key's text, following the grammar check.
def Laws.key_separators(key):
  NormalProof.key_separators(key)

# By induction over the value's text, following the grammar check.
def Laws.value_separators(value):
  NormalProof.value_separators(value)

# 9. Tracestate states and lookups
# ================================

# The package's check (no key repeats one seen before) implies keys_distinct
# (no key appears after it).
def Laws.state_valid(state):
  DistinctProof.state_valid(state)

# Distinct keys mean that every entry before `entry` has another key, so the
# lookup passes them by.
def Laws.get_entry(state, before, entry, after, split):
  DistinctProof.get_entry(state, before, entry, after, split)

# The lookup passes every entry by.
def Laws.get_absent(state, key, absent):
  DistinctProof.get_absent(state, key, absent)

# 10. Tracestate parsing
# ======================

# The case of ows_around with no whitespace.
def Laws.state_roundtrip(limits, state, fits):
  NormalProof.roundtrip(limits, state, fits)

# Whitespace before the value is skipped and whitespace after it is left out
# of the last value; the value is then read entry by entry.
def Laws.ows_around(limits, state, before, after, before_ows, after_ows, fits):
  NormalProof.ows_around(limits, state, before, after, before_ows, after_ows, fits)

# The budget check agrees with comparing Utf8.length to the budget.
def Laws.over_budget(limits, text, larger):
  StateProof.over_budget(limits, text, larger)

# Within either budget, parsing is the same budget-free reading.
def Laws.within_budgets(first, second, text, first_fits, second_fits):
  StateProof.within_budgets(first, second, text, first_fits, second_fits)

# Measuring and reading repeated fields is measuring and reading their
# comma-joined text.
def Laws.fields_join(limits, fields):
  StateProof.fields_join(limits, fields)

# The law states membership with key_among, and the proof uses the package's
# Entries.has_key; has_key_among converts one into the other.
def Laws.later_duplicate(limits, state, entry, present, room, fits):
  MergeProof.later_duplicate(limits, state, entry,
    %Equal.sym(Bool, Trace.Entries.has_key(Trace.TraceState.entries(state), Trace.StateEntry.key_text(entry)),
      Laws.key_among(Trace.StateEntry.key_text(entry), Trace.TraceState.entries(state)),
      DistinctProof.has_key_among(Trace.TraceState.entries(state), Trace.StateEntry.key_text(entry))) :
      {_ == True{} : Bool}
    present, room, fits)

# As later_duplicate.
def Laws.later_new_key(limits, state, entry, absent, room, fits):
  MergeProof.later_new_key(limits, state, entry,
    %Equal.sym(Bool, Trace.Entries.has_key(Trace.TraceState.entries(state), Trace.StateEntry.key_text(entry)),
      Laws.key_among(Trace.StateEntry.key_text(entry), Trace.TraceState.entries(state)),
      DistinctProof.has_key_among(Trace.TraceState.entries(state), Trace.StateEntry.key_text(entry))) :
      {_ == False{} : Bool}
    absent, room, fits)

# After 32 entries the member count is exhausted at the next entry.
def Laws.full_state(limits, state, entry, full, fits):
  MergeProof.full_state(limits, state, entry, full, fits)

# By induction over the second state's entries, keeping the invariants of
# proofs/first.bend.
def Laws.first_wins(limits, first, second, count, fits):
  FirstProof.first_wins(limits, first, second, count, fits)
