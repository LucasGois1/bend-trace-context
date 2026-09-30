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
# is the proof gate of the package: it prints "ALL PROOFS CHECK", which
# Bend prints only when no definition this file imports relies on `@unsafe`,
# which would skip the termination check and void the proofs, or on foreign
# code. scripts/validate.sh runs it on every backend.
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
#   proofs/order.bend               entries kept in order
#   proofs/update.bend              setting and removing entries
#   proofs/emit.bend                sizes, truncation and emission
#   proofs/extract.bend             field selection, traceparent reading and
#                                   extraction
#   proofs/inject.bend              cleanup, injection and forwarding
#   proofs/continue.bend            continuing or starting, and sending
#   proofs/http.bend                native HTTP headers

import Base
import ./LAWS.bend as Laws
import ./trace_context.bend as Trace
import ./src/digits.bend as Digits
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
import ./proofs/update.bend as UpdateProof
import ./proofs/emit.bend as EmitProof
import ./proofs/extract.bend as ExtractProof
import ./proofs/inject.bend as InjectProof
import ./proofs/continue.bend as ContinueProof
import ./proofs/http.bend as HttpProof

# 1. Strict v00 codec
# ===================

# The lengths of the pieces of the text add up to 55 (proofs/context.bend).
def Laws.formatted_length(context):
  ContextProof.formatted_length(context)

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

# By computation: the accessors read back the constructor's fields.
def Laws.remote_from_ids(trace_id, span_id, sampled):
  ({==}, ({==}, ({==}, {==})))

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

# The remote context read back is the local context's own fields
# (proofs/context.bend, by cases on both flags).
def Laws.emitted_projection(context):
  ContextProof.emitted_fields(context)

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

# The host's loop feeds the words the pure driver reads (proofs/generation.bend).
def Laws.generation_drive(fuel, tape, step, extra):
  GenerationProof.generation_drive(fuel, tape, step, extra)

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

# 11. Tracestate updates and emission
# ===================================

# The new entry first, then at most 31 of the others, in their order
# (proofs/update.bend).
def Laws.set_entries(state, key, value):
  UpdateProof.set_entries(state, key, value)

# With the key present, the other entries are at most 31, so none is
# evicted.
def Laws.update_keeps_all(state, key, value, present):
  UpdateProof.update_keeps_all(state, key, value, present)

# With the key absent, removing it changes nothing, so the first 31 entries
# follow the new one.
def Laws.insert_entries(state, key, value, absent):
  UpdateProof.insert_entries(state, key, value, absent)

# The lookup meets the new entry first.
def Laws.set_get(state, key, value):
  UpdateProof.set_get(state, key, value)

# The other entries, in their order.
def Laws.remove_entries(state, key):
  UpdateProof.remove_entries(state, key)

# The entries left lack the key.
def Laws.remove_get(state, key):
  UpdateProof.remove_get(state, key)

# The octets of key, "=" and value add up (proofs/emit.bend).
def Laws.entry_size(entry):
  EmitProof.entry_size(entry)

# The octets of the entries and their commas add up as Entries.format writes
# them.
def Laws.state_size(state):
  EmitProof.state_size(state)

# One removal step per entry reaches entries that fit.
def Laws.truncate_fits(limits, state):
  EmitProof.truncate_fits(limits, state)

# A state that fits comes out of the loop unchanged, with its own evidence.
def Laws.truncate_whole(limits, state, fits):
  EmitProof.truncate_whole(limits, state, fits)

# Each removal step keeps the other entries in order, and in_order is
# transitive.
def Laws.truncate_order(limits, state):
  EmitProof.truncate_order(limits, state)

# The keys reported are those of the entries the loop did not keep.
def Laws.truncate_dropped(limits, state):
  EmitProof.truncate_dropped(limits, state)

# The loop measures the same octets and takes the same step as the
# procedure, one step at a time.
def Laws.truncate_steps(limits, state):
  EmitProof.truncate_steps(limits, state)

# By computation once the outgoing context is split into its fields.
def Laws.outgoing_set(outgoing, key, value):
  match outgoing:
    case Trace.OutgoingContext{context, state}:
      {==}

# By computation once the outgoing context is split into its fields.
def Laws.outgoing_remove(outgoing, key):
  match outgoing:
    case Trace.OutgoingContext{context, state}:
      {==}

# By computation once the outgoing context is split into its fields.
def Laws.emit_traceparent(limits, outgoing):
  match outgoing:
    case Trace.OutgoingContext{context, state}:
      {==}

# By computation once the outgoing context is split into its fields.
def Laws.emit_tracestate(limits, outgoing):
  match outgoing:
    case Trace.OutgoingContext{context, state}:
      ({==}, {==})

# The emitted value is the truncated state's normalized value, which fits.
def Laws.emit_fits(limits, outgoing):
  EmitProof.emit_fits(limits, outgoing)

# The emitted value fits the input budget too, so it parses back.
def Laws.emit_accepted(limits, outgoing):
  EmitProof.emit_accepted(limits, outgoing)

# 12. Extraction
# ==============

# The selected traceparent values are none, so the base is kept
# (proofs/extract.bend).
def Laws.extract_absent(limits, carrier, base, absent):
  ExtractProof.extract_absent(limits, carrier, base, absent)

# Two values or more are refused as repeated.
def Laws.extract_repeated(limits, carrier, base, first, second, more, repeated):
  ExtractProof.extract_repeated(limits, carrier, base, first, second, more, repeated)

# The only value is refused, so the base is kept with the reason.
def Laws.extract_refused(limits, carrier, base, value, error, single, refused):
  ExtractProof.extract_refused(limits, carrier, base, value, error, single, refused)

# The only value is read; the tracestate fields are read with it, and the
# value is kept without its surrounding whitespace.
def Laws.extract_read(limits, carrier, base, value, known, single, read):
  ExtractProof.extract_read(limits, carrier, base, value, known, single, read)

# Both extractions read the same traceparent values; the tracestate fields
# change only the state.
def Laws.state_independent(limits, first, second, base, same):
  ExtractProof.state_independent(limits, first, second, base, same)

# A kept value fitted its budget before trimming, and kept fields parsed
# within theirs.
def Laws.received_bounds(limits, carrier, base, incoming, pair, extracted, kept):
  ExtractProof.received_bounds(limits, carrier, base, incoming, pair, extracted, kept)

# By computation: the accessors read back the constructor's fields, and the
# received pair is None{}.
def Laws.incoming_from_remote(context, state):
  ({==}, ({==}, {==}))

# The value is measured, trimmed, found free of commas and read by the strict
# codec, which reads its text back.
def Laws.read_v00(limits, known, before, after, before_ows, after_ows, fits):
  ExtractProof.read_v00(limits, known, before, after, before_ows, after_ows, fits)

# A value read back would format to 55 characters, fewer than the text has.
def Laws.read_v00_exact(limits, known, more, nonempty, plain_more, fits):
  ExtractProof.read_v00_exact(limits, known, more, nonempty, plain_more, fits)

# The first 55 characters, with the version replaced by 00, are the text of
# the value whose known fields they carry.
def Laws.read_future(limits, version, known, unknown, before, after, later, plain_unknown, before_ows, after_ows,
  fits):
  ExtractProof.read_future(limits, version, known, unknown, before, after, later, plain_unknown, before_ows,
    after_ows, fits)

# The version check refuses ff by computation.
def Laws.read_ff(limits, rest, plain_rest, fits):
  ExtractProof.read_ff(limits, rest, plain_rest, fits)

# Trimming keeps the comma, and the package refuses it.
def Laws.read_comma(limits, value, joined, fits):
  ExtractProof.read_comma(limits, value, joined, fits)

# The measurement agrees with Utf8.length, and a value over the budget is not
# read.
def Laws.read_over_budget(limits, value, larger):
  ExtractProof.read_over_budget(limits, value, larger)

# Within either budget, the value is read the same way.
def Laws.read_within_budgets(first, second, value, first_fits, second_fits):
  ExtractProof.read_within_budgets(first, second, value, first_fits, second_fits)

# 13. Injection and forwarding
# ============================

# The loop keeps exactly the fields Laws.unrelated keeps (proofs/inject.bend).
def Laws.clear_carrier(carrier):
  InjectProof.clear_carrier(carrier)

# The kept fields are followed by the emission's fields.
def Laws.inject_carrier(limits, outgoing, carrier):
  InjectProof.inject_carrier(limits, outgoing, carrier)

# By computation once the emission is split into its fields.
def Laws.inject_dropped(limits, outgoing, carrier):
  InjectProof.inject_dropped(limits, outgoing, carrier)

# The second injection keeps the same fields and adds the same ones.
def Laws.inject_idempotent(limits, outgoing, carrier):
  InjectProof.inject_idempotent(limits, outgoing, carrier)

# A receiver selects the written fields, reads the traceparent back and
# parses the emitted state.
def Laws.inject_extracted(limits, outgoing, carrier, base):
  InjectProof.inject_extracted(limits, outgoing, carrier, base)

# A success writes the received fields after the unrelated ones.
def Laws.forward_carrier(limits, incoming, carrier, pair, forwarded, kept, done):
  InjectProof.forward_carrier(limits, incoming, carrier, pair, forwarded, kept, done)

# Without a received pair, forwarding refuses at once.
def Laws.forward_nothing(limits, incoming, carrier, none):
  InjectProof.forward_nothing(limits, incoming, carrier, none)

# forward_nothing, whose hypothesis holds by computation for a context built
# from parts.
def Laws.forward_from_parts(limits, context, state, carrier):
  InjectProof.forward_nothing(limits, Trace.IncomingContext.from_remote(context, state), carrier, {==})

# The budget check comes first and refuses the pair.
def Laws.forward_too_large(limits, incoming, carrier, pair, kept, larger):
  InjectProof.forward_too_large(limits, incoming, carrier, pair, kept, larger)

# The pair of an extracted context reads back, so only its size can refuse it.
def Laws.forward_extracted(limits, received, base, incoming, pair, carrier, extracted, kept, fits):
  InjectProof.forward_extracted(limits, received, base, incoming, pair, carrier, extracted, kept, fits)

# The checks never depend on the carrier, and the second forwarding keeps the
# same fields.
def Laws.forward_idempotent(limits, incoming, carrier, forwarded, done):
  InjectProof.forward_idempotent(limits, incoming, carrier, forwarded, done)

# 14. Continuing or starting, and sending
# =======================================

# The child of the usable context, over the tape (proofs/continue.bend).
def Laws.continue_usable(tape, extraction, base, sampling, policy, usable):
  ContinueProof.continue_usable(tape, extraction, base, sampling, policy, usable)

# A restart of the usable context at a boundary, over the tape
# (proofs/continue.bend).
def Laws.restart_usable(tape, extraction, base, sampling, policy, usable):
  ContinueProof.restart_usable(tape, extraction, base, sampling, policy, usable)

# A root without a usable context, over the tape (proofs/continue.bend).
def Laws.start_unusable(tape, extraction, reception, sampling, policy, none):
  ContinueProof.start_unusable(tape, extraction, reception, sampling, policy, none)

# A new trace keeps nothing received, whatever extraction keeps
# (proofs/continue.bend).
def Laws.restart_keeps_nothing(tape, extraction, sampling, policy):
  ContinueProof.restart_keeps_nothing(tape, extraction, sampling, policy)

# A child of the service's operation for a message sent, over the tape
# (proofs/continue.bend).
def Laws.send_operating(tape, limits, origin, outgoing, received, sampling, policy, carrier):
  ContinueProof.send_operating(tape, limits, origin, outgoing, received, sampling, policy, carrier)

# The fallback of a service without an operation (proofs/continue.bend).
def Laws.send_untraced(tape, limits, error, received, sampling, policy, carrier):
  ContinueProof.send_untraced(tape, limits, error, received, sampling, policy, carrier)

# A message reports the generated child and nothing else
# (proofs/continue.bend).
def Laws.send_reports_generated(tape, limits, service, sampling, policy, carrier):
  ContinueProof.send_reports_generated(tape, limits, service, sampling, policy, carrier)

# A host that drives a service plan's generation itself gets the service that
# the operation gives (proofs/continue.bend).
def Laws.hosted_service(tape, extraction, reception, sampling, policy):
  ContinueProof.hosted_service(tape, extraction, reception, sampling, policy)

# The same for a send plan and the message that the operation gives.
def Laws.hosted_send(tape, limits, service, sampling, policy, carrier):
  ContinueProof.hosted_send(tape, limits, service, sampling, policy, carrier)

# 15. Native HTTP headers
# =======================

# The carrier keeps every value of every entry (proofs/http.bend).
def Laws.http_carrier(headers, name):
  HttpProof.http_carrier(headers, name)

# The map of a carrier holds every value of every name, given Base's Map
# contract (proofs/http.bend).
def Laws.http_headers(found, kept, carrier, name):
  HttpProof.http_headers(~found, ~kept, carrier, name)

# The adapter's continue-or-start is the package's (proofs/http.bend).
def Laws.http_continue(tape, limits, headers, base, reception, sampling, policy):
  HttpProof.http_continue(tape, limits, headers, base, reception, sampling, policy)

# The adapter's send is the package's, then the map (proofs/http.bend).
def Laws.http_send(tape, limits, service, sampling, policy, headers):
  HttpProof.http_send(tape, limits, service, sampling, policy, headers)
