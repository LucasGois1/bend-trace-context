import Base
import ./LAWS.bend as Laws
import ./trace_context.bend as Trace
import ./src/digits.bend as Digits
import ./proofs/hex.bend as HexProof
import ./proofs/digits.bend as DigitsProof
import ./proofs/strings.bend as StringsProof
import ./proofs/parser.bend as ParserProof
import ./proofs/context.bend as ContextProof
import ./proofs/inverse.bend as InverseProof
import ./proofs/ids.bend as IdsProof
import ./proofs/lifecycle.bend as LifecycleProof
import ./proofs/words.bend as WordsProof
import ./proofs/conversion.bend as ConversionProof
import ./proofs/generation.bend as GenerationProof

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

def Laws.roundtrip(context):
  ContextProof.roundtrip(context)

def Laws.inverse(text, context, accepted):
  %accepted : InverseProof.ParseView(text, _)
  InverseProof.parse_view(text)

def Laws.trace_id_parse(text, id, accepted):
  %accepted : IdsProof.TraceIdView(text, _)
  IdsProof.trace_id_view(text)

def Laws.span_id_parse(text, id, accepted):
  %accepted : IdsProof.SpanIdView(text, _)
  IdsProof.span_id_view(text)

def Laws.trace_id_accepts(id):
  IdsProof.trace_id_accepts(id)

def Laws.span_id_roundtrip(id):
  IdsProof.span_id_roundtrip(id)

def Laws.assert_random(trace_id):
  match trace_id:
    case Trace.TraceId{value, random}:
      ({==}, {==})

def Laws.from_ids(trace_id, span_id, sampled):
  ({==}, ({==}, {==}))

def Laws.root(trace_id, span_id):
  {==}

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

def Laws.received_flags(traceparent):
  match traceparent:
    case Trace.TraceParentV00{trace_id, parent_id,
      Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}}:
      ({==}, {==})

def Laws.sampling(inherited, sampled):
  ({==}, {==})

def Laws.child(parent, span_id, sampling, created, accepted):
  %accepted : LifecycleProof.ChildView(parent, span_id,
    Trace.Sampling.resolve(sampling, Trace.Parent.is_sampled(parent)), _)
  LifecycleProof.child_view(parent, span_id, sampling)

def Laws.child_reuse(parent, span_id, sampling, reused):
  LifecycleProof.child_reuse(parent, span_id, sampling, reused)

def Laws.child_accepts(parent, span_id, sampling, distinct):
  LifecycleProof.child_accepts(parent, span_id, sampling, distinct)

def Laws.restart(previous, trace_id, span_id, restarted, accepted):
  %accepted : LifecycleProof.RestartView(previous, trace_id, span_id, _)
  LifecycleProof.restart_view(previous, trace_id, span_id)

def Laws.restart_reuse(previous, trace_id, span_id, reused):
  LifecycleProof.restart_reuse(previous, trace_id, span_id, reused)

def Laws.restart_accepts(previous, trace_id, span_id, distinct):
  LifecycleProof.restart_accepts(previous, trace_id, span_id, distinct)

def Laws.trace_words(first, second, third, fourth, id, made):
  %made : ConversionProof.TraceWordsView(first, second, third, fourth, _)
  ConversionProof.trace_words_view(first, second, third, fourth)

def Laws.span_words(first, second, id, made):
  %made : ConversionProof.SpanWordsView(first, second, _)
  ConversionProof.span_words_view(first, second)

def Laws.hex_injective(left, right, same):
  ConversionProof.hex_injective(left, right, same)

def Laws.word_hex(word):
  WordsProof.word_value(word)

def Laws.words_unasserted(first, second, third, fourth, id, made):
  %made : ConversionProof.UnassertedCandidate(_)
  ConversionProof.words_unasserted(first, second, third, fourth)

def Laws.feed_failure(code, message, draw):
  {==}

def Laws.root_tape(tape):
  GenerationProof.root_tape(tape)

def Laws.child_tape(tape, parent, sampling):
  GenerationProof.child_tape(tape, parent, sampling)

def Laws.restart_tape(tape, previous):
  GenerationProof.restart_tape(tape, previous)

def Laws.root_ends(tape):
  GenerationProof.run_ends(48n, Trace.Draw.root(), tape, GenerationProof.root_within())

def Laws.child_ends(tape, parent, sampling):
  GenerationProof.run_ends(16n, Trace.Draw.child(parent, sampling), tape,
    GenerationProof.child_within(parent, sampling))

def Laws.restart_ends(tape, previous):
  GenerationProof.run_ends(48n, Trace.Draw.restart(previous), tape, GenerationProof.restart_within(previous))

def Laws.root_exhaustion(rest):
  {==}

def Laws.child_exhaustion(parent, sampling, rest):
  {==}

def Laws.generated_root(tape, rest, created, generated):
  %generated : GenerationProof.RootRun(_)
  GenerationProof.root_run(48n, Trace.Draw.root(), tape, {==})

def Laws.generated_child(tape, parent, sampling, rest, created, generated):
  %generated : GenerationProof.ChildRun(parent, sampling, _)
  GenerationProof.child_run(parent, sampling, 16n, Trace.Draw.child(parent, sampling), tape,
    ({==}, ({==}, {==})))

def Laws.generated_restart(tape, previous, rest, created, generated):
  %generated : GenerationProof.RestartRun(previous, _)
  GenerationProof.restart_run(previous, 48n, Trace.Draw.restart(previous), tape, {==})
