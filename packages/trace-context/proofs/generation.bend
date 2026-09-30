# Proofs: the generation machine over tapes
# =========================================
#
# What generation does when its words come from a tape: the list of word
# results that a replayed source returns. The generation machine of
# trace_context.bend (Draw.feed, which feeds each word to the trace ID draw
# or the span ID draw that the generation runs, through Draw.traced and
# Draw.spanned) is driven purely by Draw.run, which reads the tape with
# Tape.next, and as an IO action by Draw.read over Source.tape, as
# Generation.run_with and the operations of section 14 do. Context.root_with,
# child_with and restart_with compose the separate generation instead (laws
# root_composed, child_composed and restart_composed), and
# proofs/separate.bend proves what each draw does alone. PROOF.bend proves
# these laws of LAWS.bend with this module: root_tape, child_tape and
# restart_tape (the lemmas of the same names, through trace_phase and
# span_phase); root_ends, child_ends and restart_ends (run_ends with
# root_within, child_within and restart_within); generated_root,
# generated_child and generated_restart (root_run, child_run and
# restart_run, through the views RootRun, ChildRun and RestartRun).
# feed_failure, root_exhaustion and child_exhaustion need no lemma:
# PROOF.bend proves them by computation.
#
# The strategy, in reading order:
#
# - Termination. Within(step, n) says that a step ends within n more words,
#   whatever they are. A span ID draw that ends within n words
#   (SeparateProof.SpanWithin) gives a generation that ends within n words
#   (span_lift_within), and a trace ID draw that ends within n words
#   (SeparateProof.TraceWithin) one that ends within 16 more, those of the
#   span ID draw that follows it (trace_lift_within). These give the bounds
#   of a root, a restart and a child, and run_ends turns a bound equal to the
#   fuel into Draw.ended for every tape.
# - Created contexts. RootInv, ChildInv and RestartInv are invariants of the
#   machine's state, and the Created case of each is the conclusion of
#   generated_root, generated_child or generated_restart. Each holds of the
#   first step, and every word keeps it (root_feed, child_feed,
#   restart_feed): the word keeps the invariant of the draw that the
#   generation runs (SeparateProof.TraceInv or SpanInv), and a lifting lemma
#   (root_traced, root_spanned, child_spanned, restart_traced,
#   restart_spanned) gives the generation's. So does a whole drive (root_run,
#   child_run, restart_run, by induction on the fuel).
# - IO. read_tape_outcome shows, by induction on the fuel, that Draw.read
#   over Source.tape computes Draw.run, whatever function of the outcome the
#   continuation emits; proofs/continue.bend applies it to the continuations
#   of the operations of section 14, and read_tape_same, which relates two
#   continuations that agree on every outcome, serves proofs/http.bend.
# - Compositions. span_phase shows, by induction on the fuel, that a span ID
#   draw that SpanDraw.read runs over a tape, followed by the context of its
#   span ID, emits what Draw.run gives for the generation that Draw.spanned
#   makes of the draw, even with fuel to spare; trace_phase shows the same for
#   a trace ID draw followed by Draw.after_trace. root_tape, child_tape and
#   restart_tape apply them to the first steps.
#
# The statements use Tape, TapeStep, TapeOutcome and Observe of LAWS.bend,
# so each statement here is the statement of the law it proves.

import Base
import ../trace_context.bend as TC
import ./bools.bend as BoolsProof
import ./separate.bend as SeparateProof
import ../LAWS.bend as Laws

# Word bounds
# ===========
#
# Within(step, n) states that a generation ends within n more words. The
# bounds of the draws, proved in proofs/separate.bend, give it for the first
# step of every generation.

# The claim "this step ends within n more words, whatever they are", as a
# type. Unit for a step that has ended (Created or Failed); Empty for a step
# that needs a word when n is 0; otherwise, for every word, the bound n - 1
# of the step that feeding the word gives (`@word: U32 -> ...` is a function
# type, so such a proof is a function of the word). Only successful words
# count: a failed word ends the generation at once (law feed_failure), so
# the bound holds for every source.
def Within(step: TC.Step, n: Nat) -> Type:
  match step:
    case TC.Created{context}:
      Unit
    case TC.Failed{error}:
      Unit
    case TC.NeedWord{draw}:
      match n:
        case 0n:
          Empty
        case 1n+p:
          @word: U32 -> Within(TC.Draw.feed(Done{word}, draw), p)

# A bound can be loosened by any number of words: a step that ends within m
# words ends within m + n. Induction on m. trace_lift_within uses it for a
# trace ID drawn before its draw's bound was reached.
law within_plus:
  for +m: Nat
  for n: Nat
  for +step: TC.Step
  for bound: Within(step, m)
  Within(step, Nat.add(m, n))

def within_plus(m, n, step, bound):
  match m:
    case 0n:
      match step:
        case TC.Created{context}:
          Unit{}
        case TC.Failed{error}:
          Unit{}
        case TC.NeedWord{draw}:
          Empty.absurd(Within(TC.NeedWord{draw}, n), bound)
    case 1n+p:
      match step:
        case TC.Created{context}:
          Unit{}
        case TC.Failed{error}:
          Unit{}
        case TC.NeedWord{+draw}:
          +word => within_plus(p, n, TC.Draw.feed(Done{word}, draw), bound(word))

# A span ID draw's bound carries over to the generation that Draw.spanned
# makes of it, for every trace ID and sampled indication: feeding a word to
# the generation feeds it to the draw. Induction on n. child_within and
# trace_lift_within use it.
law span_lift_within:
  for +n: Nat
  for +step: TC.SpanStep
  for +trace_id: TC.TraceId
  for +sampled: Bool
  for bound: SeparateProof.SpanWithin(step, n)
  Within(TC.Draw.spanned(step, trace_id, sampled), n)

def span_lift_within(n, step, trace_id, sampled, bound):
  match n:
    case 0n:
      match step:
        case TC.DrawnSpanId{id}:
          Unit{}
        case TC.SpanFailed{error}:
          Unit{}
        case TC.NeedSpanWord{remaining, words, excluded}:
          Empty.absurd(Within(TC.Draw.spanned(TC.NeedSpanWord{remaining, words, excluded}, trace_id, sampled), 0n),
            bound)
    case 1n+p:
      match step:
        case TC.DrawnSpanId{id}:
          Unit{}
        case TC.SpanFailed{error}:
          Unit{}
        case TC.NeedSpanWord{+remaining, +words, +excluded}:
          +word => span_lift_within(p, TC.SpanDraw.feed(Done{word}, remaining, words, excluded), trace_id, sampled,
            bound(word))

# A trace ID draw's bound carries over to the generation that Draw.traced
# makes of it, with 16 more words for the span ID that follows: a drawn trace
# ID starts the span ID draw that SeparateProof.span_start_within bounds by
# 16 words, loosened by the words that the trace ID draw had left
# (within_plus). Induction on n. root_within and restart_within use it.
law trace_lift_within:
  for +n: Nat
  for +step: TC.TraceStep
  for bound: SeparateProof.TraceWithin(step, n)
  Within(TC.Draw.traced(step), Nat.add(16n, n))

def trace_lift_within(n, step, bound):
  match n:
    case 0n:
      match step:
        case TC.DrawnTraceId{+id}:
          span_lift_within(16n, TC.SpanDraw.start(None{}), id, False{}, SeparateProof.span_start_within(7n, None{}))
        case TC.TraceFailed{error}:
          Unit{}
        case TC.NeedTraceWord{remaining, words, excluded}:
          Empty.absurd(Within(TC.Draw.traced(TC.NeedTraceWord{remaining, words, excluded}), 16n), bound)
    case 1n+p:
      match step:
        case TC.DrawnTraceId{+id}:
          within_plus(16n, 1n+p, TC.Draw.accept_trace(id),
            span_lift_within(16n, TC.SpanDraw.start(None{}), id, False{}, SeparateProof.span_start_within(7n, None{})))
        case TC.TraceFailed{error}:
          Unit{}
        case TC.NeedTraceWord{+remaining, +words, +excluded}:
          +word => trace_lift_within(p, TC.TraceDraw.feed(Done{word}, remaining, words, excluded), bound(word))

# Every generation ends
# =====================
#
# The bounds of the first step of a root, a restart and a child, and
# run_ends, which turns such a bound into the end of Draw.run (laws
# root_ends, restart_ends and child_ends). ended_stays and run_failed show
# that Draw.run keeps an ended step ended and a failed one unchanged.

# A root generation ends within 48 words, whatever they are: its trace ID
# draw within 32 and its span ID draw within 16 more. The bound that
# Laws.root_ends passes to run_ends.
law root_within:
  Within(TC.Draw.root(), 48n)

def root_within():
  trace_lift_within(32n, TC.TraceDraw.start(None{}), SeparateProof.trace_start_within(7n, None{}))

# A restart ends within 48 words, whatever they are, as a root: the bound
# that Laws.restart_ends passes to run_ends.
law restart_within:
  for +previous: TC.RemoteContext
  Within(TC.Draw.restart(previous), 48n)

def restart_within(previous):
  trace_lift_within(32n, TC.TraceDraw.start(Some{TC.RemoteContext.trace_id(previous)}),
    SeparateProof.trace_start_within(7n, Some{TC.RemoteContext.trace_id(previous)}))

# A child generation ends within 16 words, whatever they are, those of its
# span ID draw: the bound that Laws.child_ends passes to run_ends.
law child_within:
  for +parent: TC.Parent
  for sampling: TC.Sampling
  Within(TC.Draw.child(parent, sampling), 16n)

def child_within(parent, sampling):
  span_lift_within(16n, TC.SpanDraw.start(Some{TC.Parent.span_id(parent)}), TC.Parent.trace_id(parent),
    TC.Sampling.resolve(sampling, TC.Parent.is_sampled(parent)),
    SeparateProof.span_start_within(7n, Some{TC.Parent.span_id(parent)}))

# When a step has ended, driving it further keeps it ended: Draw.run returns
# a Created or Failed step as it is, whatever the fuel and the tape. run_ends
# uses it after a source error, the end of the tape included.
law ended_stays:
  for +fuel: Nat
  for tape: Laws.Tape()
  for +step: TC.Step
  for ended: {TC.Step.is_finished(step) == True{} : Bool}
  {TC.Draw.ended(TC.Draw.run(fuel, (tape, step))) == True{} : Bool}

# Refutes the waiting steps, for which `ended` says False == True.
def ended_stays(fuel, tape, step, ended):
  match fuel step:
    case 0n TC.Created{context}:
      {==}
    case 0n TC.Failed{error}:
      {==}
    case 0n TC.NeedWord{draw}:
      Empty.absurd({TC.Draw.ended(TC.Draw.run(0n, (tape, TC.NeedWord{draw}))) == True{} : Bool},
        BoolsProof.true_ne_false(Equal.sym(Bool, False{}, True{}, ended)))
    case 1n+p TC.Created{context}:
      {==}
    case 1n+p TC.Failed{error}:
      {==}
    case 1n+p TC.NeedWord{draw}:
      Empty.absurd({TC.Draw.ended(TC.Draw.run(1n+p, (tape, TC.NeedWord{draw}))) == True{} : Bool},
        BoolsProof.true_ne_false(Equal.sym(Bool, False{}, True{}, ended)))

# Driving a generation with enough fuel ends it, whatever the tape holds:
# when the step ends within `fuel` words (Within), Draw.run with that fuel
# returns an ended step. Laws.root_ends, child_ends and restart_ends apply it
# with root_within, child_within and restart_within. Induction on the fuel
# along the tape: a word uses the bound at that word, and an error, the end
# of the tape included, fails at once and stays ended (ended_stays).
law run_ends:
  for +fuel: Nat
  for +step: TC.Step
  for tape: Laws.Tape()
  for bound: Within(step, fuel)
  {TC.Draw.ended(TC.Draw.run(fuel, (tape, step))) == True{} : Bool}

def run_ends(fuel, step, tape, bound):
  match fuel:
    case 0n:
      match step:
        case TC.Created{context}:
          {==}
        case TC.Failed{error}:
          {==}
        case TC.NeedWord{draw}:
          Empty.absurd({TC.Draw.ended(TC.Draw.run(0n, (tape, TC.NeedWord{draw}))) == True{} : Bool}, bound)
    case 1n+p:
      match step:
        case TC.Created{context}:
          {==}
        case TC.Failed{error}:
          {==}
        case TC.NeedWord{+draw}:
          match tape:
            case Nil{}:
              ended_stays(p, Nil{}, TC.Failed{TC.SourceFailure{1, "tape-exhausted"}}, {==})
            case Con{Fail{(code, message)}, rest}:
              ended_stays(p, rest, TC.Failed{TC.SourceFailure{code, message}}, {==})
            case Con{Done{+word}, rest}:
              run_ends(p, TC.Draw.feed(Done{word}, draw), rest, bound(word))

# Driving a failed generation changes nothing: Draw.run returns the tape and
# the failure as they are, whatever the fuel. root_run, child_run and
# restart_run use it for the rest of a drive after a source error.
law run_failed:
  for fuel: Nat
  for tape: Laws.Tape()
  for error: TC.GenerationError
  {TC.Draw.run(fuel, (tape, TC.Failed{error})) == (tape, TC.Failed{error}) : Laws.TapeStep()}

# Splits on the fuel only because Draw.run does not compute on an unknown one.
def run_failed(fuel, tape, error):
  match fuel:
    case 0n:
      {==}
    case 1n+p:
      {==}

# Properties of created contexts
# ==============================
#
# generated_root, generated_child and generated_restart hold because each
# kind of generation keeps an invariant of its state (RootInv, ChildInv,
# RestartInv below) whose Created case is the law's conclusion. A word keeps
# the invariant of the draw that the generation runs (SeparateProof.TraceInv
# and SpanInv), and a lifting lemma gives the generation's invariant from the
# draw's.

# Roots
# =====
#
# A root's trace ID draw has no trace ID to exclude; its span ID draw keeps a
# random trace ID, sampled False and no span ID to exclude.

# What a root's span ID draw keeps in its plan: a trace ID that asserts
# random-trace-id, sampled False, and no span ID to exclude (parent None{}).
def RootPlan(plan: TC.SpanPlan) -> Type:
  match plan:
    case TC.SpanPlan{trace_id, sampled, parent}:
      {TC.TraceId.is_random(trace_id) == True{} : Bool} & {sampled == False{} : Bool} &
      {parent == None{} : Maybe<&2, TC.SpanId>}

# The invariant of a root's generation, a view of each step: a trace ID draw
# has no received trace ID (previous None{}), a span ID draw keeps RootPlan,
# a created context has the two conclusions of law generated_root (random
# trace ID, not sampled), and a failure needs nothing (Unit).
def RootInv(step: TC.Step) -> Type:
  match step:
    case TC.NeedWord{TC.DrawTrace{remaining, words, previous}}:
      {previous == None{} : Maybe<&2, TC.TraceId>}
    case TC.NeedWord{TC.DrawSpan{remaining, words, plan}}:
      RootPlan(plan)
    case TC.Created{context}:
      {TC.TraceId.is_random(TC.LocalContext.trace_id(context)) == True{} : Bool} &
      {TC.LocalContext.is_sampled(context) == False{} : Bool}
    case TC.Failed{error}:
      Unit

# The generation that a root's trace ID draw gives keeps the invariant when
# the draw keeps SeparateProof.TraceInv with nothing to exclude: a draw that
# needs a word excludes nothing, and a drawn trace ID, which is random,
# starts the span ID draw with a RootPlan.
law root_traced:
  for step: TC.TraceStep
  for valid: SeparateProof.TraceInv(None{}, step)
  RootInv(TC.Draw.traced(step))

def root_traced(step, valid):
  match step:
    case TC.NeedTraceWord{remaining, words, kept}:
      valid
    case TC.DrawnTraceId{id}:
      (random, avoids) = valid
      (random, ({==}, {==}))
    case TC.TraceFailed{error}:
      Unit{}

# The generation that a root's span ID draw gives keeps the invariant when
# its trace ID asserts random-trace-id (`random`), it is not sampled
# (`unsampled`), and the draw keeps SeparateProof.SpanInv with nothing to
# exclude: a created context has that trace ID and sampled indication.
law root_spanned:
  for step: TC.SpanStep
  for -trace_id: TC.TraceId
  for -sampled: Bool
  for random: {TC.TraceId.is_random(trace_id) == True{} : Bool}
  for unsampled: {sampled == False{} : Bool}
  for valid: SeparateProof.SpanInv(None{}, step)
  RootInv(TC.Draw.spanned(step, trace_id, sampled))

def root_spanned(step, trace_id, sampled, random, unsampled, valid):
  match step:
    case TC.NeedSpanWord{remaining, words, kept}:
      (random, (unsampled, valid))
    case TC.DrawnSpanId{id}:
      (random, unsampled)
    case TC.SpanFailed{error}:
      Unit{}

# When RootInv holds of a step that needs a word, it holds after feeding any
# word: the draw that the generation runs keeps its invariant
# (SeparateProof.trace_feed_inv or span_feed_inv), which root_traced or
# root_spanned lifts.
law root_feed:
  for +word: U32
  for draw: TC.Draw
  for valid: RootInv(TC.NeedWord{draw})
  RootInv(TC.Draw.feed(Done{word}, draw))

def root_feed(word, draw, valid):
  match draw:
    case TC.DrawTrace{+remaining, +words, +previous}:
      root_traced(TC.TraceDraw.feed(Done{word}, remaining, words, previous),
        SeparateProof.trace_feed_inv(None{}, word, remaining, words, previous, valid))
    case TC.DrawSpan{+remaining, +words, TC.SpanPlan{+trace_id, +sampled, +parent}}:
      (random, rest) = valid
      (unsampled, none) = rest
      root_spanned(TC.SpanDraw.feed(Done{word}, remaining, words, parent), trace_id, sampled, random, unsampled,
        SeparateProof.span_feed_inv(None{}, word, remaining, words, parent, none))

# The view of Draw.run's result for a root: RootInv of its final step, the
# unread tape ignored. Laws.generated_root rewrites its hypothesis
# {Draw.run(...) == (rest, Created{created})} through RootRun(_), which turns
# the law's conclusion into RootRun of the drive, proved by root_run.
def RootRun(result: Laws.TapeStep()) -> Type:
  match result:
    case Tuple{tape, step}:
      RootInv(step)

# When RootInv holds of a step, it holds of the step that Draw.run returns
# from it, for every fuel and every tape. Laws.generated_root applies it to
# Draw.root(), whose invariant holds by computation ({==}).
law root_run:
  for +fuel: Nat
  for +step: TC.Step
  for tape: Laws.Tape()
  for valid: RootInv(step)
  RootRun(TC.Draw.run(fuel, (tape, step)))

# Induction on the fuel; after an error, run_failed rewrites the drive's rest.
def root_run(fuel, step, tape, valid):
  match fuel:
    case 0n:
      match step:
        case TC.NeedWord{draw}:
          valid
        case TC.Created{context}:
          valid
        case TC.Failed{error}:
          valid
    case 1n+p:
      match step:
        case TC.Created{context}:
          valid
        case TC.Failed{error}:
          valid
        case TC.NeedWord{+draw}:
          match tape:
            case Nil{}:
              %Equal.sym(Laws.TapeStep(), TC.Draw.run(p, (Nil{}, TC.Failed{TC.SourceFailure{1, "tape-exhausted"}})),
                (Nil{}, TC.Failed{TC.SourceFailure{1, "tape-exhausted"}}),
                run_failed(p, Nil{}, TC.SourceFailure{1, "tape-exhausted"})) : RootRun(_)
              Unit{}
            case Con{Fail{(code, message)}, rest}:
              %Equal.sym(Laws.TapeStep(), TC.Draw.run(p, (rest, TC.Failed{TC.SourceFailure{code, message}})),
                (rest, TC.Failed{TC.SourceFailure{code, message}}),
                run_failed(p, rest, TC.SourceFailure{code, message})) : RootRun(_)
              Unit{}
            case Con{Done{+word}, rest}:
              root_run(p, TC.Draw.feed(Done{word}, draw), rest, root_feed(word, draw, valid))

# Children
# ========
#
# A child draws only its span ID. Every state keeps the parent's trace ID,
# the resolved sampled indication and the parent's span ID as the one to
# exclude.

# What a child's span ID draw keeps in its plan, as Draw.child builds it: the
# parent's trace ID, the sampled indication Sampling.resolve gives, and the
# parent's span ID as the one to exclude.
def ChildPlan(+parent: TC.Parent, sampling: TC.Sampling, plan: TC.SpanPlan) -> Type:
  match plan:
    case TC.SpanPlan{trace_id, sampled, excluded}:
      {trace_id == TC.Parent.trace_id(parent) : TC.TraceId} &
      {sampled == TC.Sampling.resolve(sampling, TC.Parent.is_sampled(parent)) : Bool} &
      {excluded == Some{TC.Parent.span_id(parent)} : Maybe<&2, TC.SpanId>}

# The invariant of a child's generation, a view of each step: a trace ID draw
# is impossible (Empty), since a child draws only its span ID; a span ID draw
# keeps ChildPlan; a created context has the three conclusions of law
# generated_child; a failure needs nothing (Unit).
def ChildInv(+parent: TC.Parent, sampling: TC.Sampling, step: TC.Step) -> Type:
  match step:
    case TC.NeedWord{TC.DrawTrace{remaining, words, previous}}:
      Empty
    case TC.NeedWord{TC.DrawSpan{remaining, words, plan}}:
      ChildPlan(parent, sampling, plan)
    case TC.Created{context}:
      {TC.LocalContext.trace_id(context) == TC.Parent.trace_id(parent) : TC.TraceId} &
      {TC.LocalContext.is_sampled(context) == TC.Sampling.resolve(sampling, TC.Parent.is_sampled(parent)) : Bool} &
      {TC.SpanId.to_string(TC.LocalContext.span_id(context)) != TC.SpanId.to_string(TC.Parent.span_id(parent)) : String}
    case TC.Failed{error}:
      Unit

# The generation that a child's span ID draw gives keeps the invariant when
# its trace ID is the parent's (`same_trace`), its sampled indication the one
# that Sampling.resolve gives (`same_sampled`), and the draw keeps
# SeparateProof.SpanInv with the parent's span ID to exclude: the span ID of
# a created context avoids the parent's.
law child_spanned:
  for +parent: TC.Parent
  for -sampling: TC.Sampling
  for step: TC.SpanStep
  for -trace_id: TC.TraceId
  for -sampled: Bool
  for same_trace: {trace_id == TC.Parent.trace_id(parent) : TC.TraceId}
  for same_sampled: {sampled == TC.Sampling.resolve(sampling, TC.Parent.is_sampled(parent)) : Bool}
  for valid: SeparateProof.SpanInv(Some{TC.Parent.span_id(parent)}, step)
  ChildInv(parent, sampling, TC.Draw.spanned(step, trace_id, sampled))

def child_spanned(parent, sampling, step, trace_id, sampled, same_trace, same_sampled, valid):
  match step:
    case TC.NeedSpanWord{remaining, words, kept}:
      (same_trace, (same_sampled, valid))
    case TC.DrawnSpanId{id}:
      (same_trace, (same_sampled, valid))
    case TC.SpanFailed{error}:
      Unit{}

# When ChildInv holds of a step that needs a word, it holds after feeding
# any word. A trace ID draw is ruled out, since its invariant is Empty; the
# span ID draw keeps its invariant (SeparateProof.span_feed_inv), which
# child_spanned lifts.
law child_feed:
  for +parent: TC.Parent
  for -sampling: TC.Sampling
  for +word: U32
  for draw: TC.Draw
  for valid: ChildInv(parent, sampling, TC.NeedWord{draw})
  ChildInv(parent, sampling, TC.Draw.feed(Done{word}, draw))

def child_feed(parent, sampling, word, draw, valid):
  match draw:
    case TC.DrawTrace{remaining, words, previous}:
      Empty.absurd(ChildInv(parent, sampling, TC.Draw.feed(Done{word}, TC.DrawTrace{remaining, words, previous})),
        valid)
    case TC.DrawSpan{+remaining, +words, TC.SpanPlan{+trace_id, +sampled, +excluded}}:
      (same_trace, rest) = valid
      (same_sampled, parent_span) = rest
      child_spanned(parent, sampling, TC.SpanDraw.feed(Done{word}, remaining, words, excluded), trace_id, sampled,
        same_trace, same_sampled,
        SeparateProof.span_feed_inv(Some{TC.Parent.span_id(parent)}, word, remaining, words, excluded, parent_span))

# The view of Draw.run's result for a child: ChildInv of its final step, the
# unread tape ignored. Laws.generated_child rewrites its hypothesis through
# ChildRun(parent, sampling, _), as for RootRun.
def ChildRun(+parent: TC.Parent, sampling: TC.Sampling, result: Laws.TapeStep()) -> Type:
  match result:
    case Tuple{tape, step}:
      ChildInv(parent, sampling, step)

# When ChildInv holds of a step, it holds of the step that Draw.run returns
# from it, for every fuel and every tape. Laws.generated_child applies it to
# Draw.child(parent, sampling), whose invariant is three equations that hold
# by computation.
law child_run:
  for +parent: TC.Parent
  for -sampling: TC.Sampling
  for +fuel: Nat
  for +step: TC.Step
  for tape: Laws.Tape()
  for valid: ChildInv(parent, sampling, step)
  ChildRun(parent, sampling, TC.Draw.run(fuel, (tape, step)))

# As root_run: induction on the fuel, and run_failed after an error.
def child_run(parent, sampling, fuel, step, tape, valid):
  match fuel:
    case 0n:
      match step:
        case TC.NeedWord{draw}:
          valid
        case TC.Created{context}:
          valid
        case TC.Failed{error}:
          valid
    case 1n+p:
      match step:
        case TC.Created{context}:
          valid
        case TC.Failed{error}:
          valid
        case TC.NeedWord{+draw}:
          match tape:
            case Nil{}:
              %Equal.sym(Laws.TapeStep(), TC.Draw.run(p, (Nil{}, TC.Failed{TC.SourceFailure{1, "tape-exhausted"}})),
                (Nil{}, TC.Failed{TC.SourceFailure{1, "tape-exhausted"}}),
                run_failed(p, Nil{}, TC.SourceFailure{1, "tape-exhausted"})) : ChildRun(parent, sampling, _)
              Unit{}
            case Con{Fail{(code, message)}, rest}:
              %Equal.sym(Laws.TapeStep(), TC.Draw.run(p, (rest, TC.Failed{TC.SourceFailure{code, message}})),
                (rest, TC.Failed{TC.SourceFailure{code, message}}),
                run_failed(p, rest, TC.SourceFailure{code, message})) : ChildRun(parent, sampling, _)
              Unit{}
            case Con{Done{+word}, rest}:
              child_run(parent, sampling, p, TC.Draw.feed(Done{word}, draw), rest,
                child_feed(parent, sampling, word, draw, valid))

# Restarts
# ========
#
# A restart's trace ID draw keeps the received trace ID to exclude. Its span
# ID draw keeps a trace ID that differs from the received one and asserts
# random-trace-id, with the root defaults: sampled False and no span ID to
# exclude.

# What a restart's span ID draw keeps in its plan: a trace ID whose digits
# differ from those of the received trace ID and that asserts
# random-trace-id, sampled False, and no span ID to exclude.
def RestartPlan(+previous: TC.RemoteContext, plan: TC.SpanPlan) -> Type:
  match plan:
    case TC.SpanPlan{trace_id, sampled, excluded}:
      {TC.TraceId.to_string(trace_id) != TC.TraceId.to_string(TC.RemoteContext.trace_id(previous)) : String} &
      {TC.TraceId.is_random(trace_id) == True{} : Bool} & {sampled == False{} : Bool} &
      {excluded == None{} : Maybe<&2, TC.SpanId>}

# The invariant of a restart, a view of each step: a trace ID draw keeps the
# trace ID of `previous` as the received one to exclude, a span ID draw keeps
# RestartPlan, a created context has the three conclusions of law
# generated_restart, and a failure needs nothing (Unit).
def RestartInv(+previous: TC.RemoteContext, step: TC.Step) -> Type:
  match step:
    case TC.NeedWord{TC.DrawTrace{remaining, words, received}}:
      {received == Some{TC.RemoteContext.trace_id(previous)} : Maybe<&2, TC.TraceId>}
    case TC.NeedWord{TC.DrawSpan{remaining, words, plan}}:
      RestartPlan(previous, plan)
    case TC.Created{context}:
      {TC.TraceId.to_string(TC.LocalContext.trace_id(context)) !=
        TC.TraceId.to_string(TC.RemoteContext.trace_id(previous)) : String} &
      {TC.TraceId.is_random(TC.LocalContext.trace_id(context)) == True{} : Bool} &
      {TC.LocalContext.is_sampled(context) == False{} : Bool}
    case TC.Failed{error}:
      Unit

# The generation that a restart's trace ID draw gives keeps the invariant
# when the draw keeps SeparateProof.TraceInv with the received trace ID to
# exclude: a drawn trace ID is random and differs from the received one, and
# starts the span ID draw with a RestartPlan.
law restart_traced:
  for +previous: TC.RemoteContext
  for step: TC.TraceStep
  for valid: SeparateProof.TraceInv(Some{TC.RemoteContext.trace_id(previous)}, step)
  RestartInv(previous, TC.Draw.traced(step))

def restart_traced(previous, step, valid):
  match step:
    case TC.NeedTraceWord{remaining, words, kept}:
      valid
    case TC.DrawnTraceId{id}:
      (random, distinct) = valid
      (distinct, (random, ({==}, {==})))
    case TC.TraceFailed{error}:
      Unit{}

# The generation that a restart's span ID draw gives keeps the invariant
# when its trace ID differs from the received one (`distinct`) and asserts
# random-trace-id (`random`), it is not sampled (`unsampled`), and the draw
# keeps SeparateProof.SpanInv with nothing to exclude.
law restart_spanned:
  for +previous: TC.RemoteContext
  for step: TC.SpanStep
  for -trace_id: TC.TraceId
  for -sampled: Bool
  for distinct: {TC.TraceId.to_string(trace_id) != TC.TraceId.to_string(TC.RemoteContext.trace_id(previous)) :
    String}
  for random: {TC.TraceId.is_random(trace_id) == True{} : Bool}
  for unsampled: {sampled == False{} : Bool}
  for valid: SeparateProof.SpanInv(None{}, step)
  RestartInv(previous, TC.Draw.spanned(step, trace_id, sampled))

def restart_spanned(previous, step, trace_id, sampled, distinct, random, unsampled, valid):
  match step:
    case TC.NeedSpanWord{remaining, words, kept}:
      (distinct, (random, (unsampled, valid)))
    case TC.DrawnSpanId{id}:
      (distinct, (random, unsampled))
    case TC.SpanFailed{error}:
      Unit{}

# When RestartInv holds of a step that needs a word, it holds after feeding
# any word, with the same cases as root_feed: restart_traced lifts the trace
# ID draw's invariant and restart_spanned the span ID draw's.
law restart_feed:
  for +previous: TC.RemoteContext
  for +word: U32
  for draw: TC.Draw
  for valid: RestartInv(previous, TC.NeedWord{draw})
  RestartInv(previous, TC.Draw.feed(Done{word}, draw))

def restart_feed(previous, word, draw, valid):
  match draw:
    case TC.DrawTrace{+remaining, +words, +received}:
      restart_traced(previous, TC.TraceDraw.feed(Done{word}, remaining, words, received),
        SeparateProof.trace_feed_inv(Some{TC.RemoteContext.trace_id(previous)}, word, remaining, words, received,
          valid))
    case TC.DrawSpan{+remaining, +words, TC.SpanPlan{+trace_id, +sampled, +excluded}}:
      (distinct, rest) = valid
      (random, more) = rest
      (unsampled, none) = more
      restart_spanned(previous, TC.SpanDraw.feed(Done{word}, remaining, words, excluded), trace_id, sampled,
        distinct, random, unsampled, SeparateProof.span_feed_inv(None{}, word, remaining, words, excluded, none))

# The view of Draw.run's result for a restart: RestartInv of its final step,
# the unread tape ignored. Laws.generated_restart rewrites its hypothesis
# through RestartRun(previous, _), as for RootRun.
def RestartRun(+previous: TC.RemoteContext, result: Laws.TapeStep()) -> Type:
  match result:
    case Tuple{tape, step}:
      RestartInv(previous, step)

# When RestartInv holds of a step, it holds of the step that Draw.run returns
# from it, for every fuel and every tape. Laws.generated_restart applies it
# to Draw.restart(previous), whose invariant holds by computation ({==}).
law restart_run:
  for +previous: TC.RemoteContext
  for +fuel: Nat
  for +step: TC.Step
  for tape: Laws.Tape()
  for valid: RestartInv(previous, step)
  RestartRun(previous, TC.Draw.run(fuel, (tape, step)))

# As root_run: induction on the fuel, and run_failed after an error.
def restart_run(previous, fuel, step, tape, valid):
  match fuel:
    case 0n:
      match step:
        case TC.NeedWord{draw}:
          valid
        case TC.Created{context}:
          valid
        case TC.Failed{error}:
          valid
    case 1n+p:
      match step:
        case TC.Created{context}:
          valid
        case TC.Failed{error}:
          valid
        case TC.NeedWord{+draw}:
          match tape:
            case Nil{}:
              %Equal.sym(Laws.TapeStep(), TC.Draw.run(p, (Nil{}, TC.Failed{TC.SourceFailure{1, "tape-exhausted"}})),
                (Nil{}, TC.Failed{TC.SourceFailure{1, "tape-exhausted"}}),
                run_failed(p, Nil{}, TC.SourceFailure{1, "tape-exhausted"})) : RestartRun(previous, _)
              Unit{}
            case Con{Fail{(code, message)}, rest}:
              %Equal.sym(Laws.TapeStep(), TC.Draw.run(p, (rest, TC.Failed{TC.SourceFailure{code, message}})),
                (rest, TC.Failed{TC.SourceFailure{code, message}}),
                run_failed(p, rest, TC.SourceFailure{code, message})) : RestartRun(previous, _)
              Unit{}
            case Con{Done{+word}, rest}:
              restart_run(previous, p, TC.Draw.feed(Done{word}, draw), rest,
                restart_feed(previous, word, draw, valid))

# The IO operations over a tape
# =============================

# Over a tape, the IO driver computes what the pure driver computes: running
# Draw.read over Source.tape, followed by a continuation that emits a
# function `f` of the driver's outcome, gives what any `g` that agrees with
# `f` on every outcome (`same`) emits for the outcome of Draw.run, the same
# words read in the same order. Since an IO action is a function of a result
# type and a continuation (IO in Base), this says how Draw.read behaves
# inside a larger action, such as the one Draw.finished builds. The
# induction applies `same` once, to the outcome the tape leads to, so the
# tape, which is linear, is read once. proofs/continue.bend rests on it.
law read_tape_outcome:
  for -A: Type
  for -f: Laws.TapeOutcome() -> A
  for -g: Laws.TapeOutcome() -> A
  for same: @outcome: Laws.TapeOutcome() -> {f(outcome) == g(outcome) : A}
  for +fuel: Nat
  for current: Laws.TapeStep()
  {TC.Draw.read(~Laws.Tape(), ~TC.Source.tape, fuel, current)(A, step => Emit{f(TC.Draw.outcome(Laws.Tape(), step))}) ==
    Emit{g(TC.Draw.outcome(Laws.Tape(), TC.Draw.run(fuel, current)))} : IO.OP<A>}

# Splits on the fuel for every step: the drivers compute only once it is
# known. An ended step or an empty fuel emits at once, and a word is fed
# otherwise.
def read_tape_outcome(A, f, g, same, fuel, current):
  match fuel current:
    case 0n Tuple{tape, TC.Created{context}}:
      Equal.cong(A, IO.OP<A>, value => Emit{value}, f((tape, Done{context})), g((tape, Done{context})),
        same((tape, Done{context})))
    case 0n Tuple{tape, TC.Failed{error}}:
      Equal.cong(A, IO.OP<A>, value => Emit{value}, f((tape, Fail{error})), g((tape, Fail{error})),
        same((tape, Fail{error})))
    case 0n Tuple{tape, TC.NeedWord{draw}}:
      Equal.cong(A, IO.OP<A>, value => Emit{value},
        f(TC.Draw.outcome(Laws.Tape(), (tape, TC.NeedWord{draw}))),
        g(TC.Draw.outcome(Laws.Tape(), (tape, TC.NeedWord{draw}))),
        same(TC.Draw.outcome(Laws.Tape(), (tape, TC.NeedWord{draw}))))
    case 1n+p Tuple{tape, TC.Created{context}}:
      Equal.cong(A, IO.OP<A>, value => Emit{value}, f((tape, Done{context})), g((tape, Done{context})),
        same((tape, Done{context})))
    case 1n+p Tuple{tape, TC.Failed{error}}:
      Equal.cong(A, IO.OP<A>, value => Emit{value}, f((tape, Fail{error})), g((tape, Fail{error})),
        same((tape, Fail{error})))
    case 1n+p Tuple{tape, TC.NeedWord{draw}}:
      read_tape_outcome(A, f, g, same, p, TC.Draw.fed_by(Laws.Tape(), TC.Tape.next(tape), draw))

# Two continuations that emit functions `f` and `g` of the driver's outcome
# make Draw.read over Source.tape emit the same whenever `f` and `g` agree on
# every outcome (`same`). Induction on the fuel, as read_tape_outcome, whose
# body it repeats: the tape is linear, so this cannot be two uses of
# read_tape_outcome on the same step joined by Equal.trans. proofs/http.bend
# uses it for an adapter that follows the package's operation with its own
# translation.
law read_tape_same:
  for -A: Type
  for -f: Laws.TapeOutcome() -> A
  for -g: Laws.TapeOutcome() -> A
  for same: @outcome: Laws.TapeOutcome() -> {f(outcome) == g(outcome) : A}
  for +fuel: Nat
  for current: Laws.TapeStep()
  {TC.Draw.read(~Laws.Tape(), ~TC.Source.tape, fuel, current)(A, step => Emit{f(TC.Draw.outcome(Laws.Tape(), step))}) ==
    TC.Draw.read(~Laws.Tape(), ~TC.Source.tape, fuel, current)(A, step => Emit{g(TC.Draw.outcome(Laws.Tape(), step))}) :
    IO.OP<A>}

def read_tape_same(A, f, g, same, fuel, current):
  match fuel current:
    case 0n Tuple{tape, TC.Created{context}}:
      Equal.cong(A, IO.OP<A>, value => Emit{value}, f((tape, Done{context})), g((tape, Done{context})),
        same((tape, Done{context})))
    case 0n Tuple{tape, TC.Failed{error}}:
      Equal.cong(A, IO.OP<A>, value => Emit{value}, f((tape, Fail{error})), g((tape, Fail{error})),
        same((tape, Fail{error})))
    case 0n Tuple{tape, TC.NeedWord{draw}}:
      Equal.cong(A, IO.OP<A>, value => Emit{value},
        f(TC.Draw.outcome(Laws.Tape(), (tape, TC.NeedWord{draw}))),
        g(TC.Draw.outcome(Laws.Tape(), (tape, TC.NeedWord{draw}))),
        same(TC.Draw.outcome(Laws.Tape(), (tape, TC.NeedWord{draw}))))
    case 1n+p Tuple{tape, TC.Created{context}}:
      Equal.cong(A, IO.OP<A>, value => Emit{value}, f((tape, Done{context})), g((tape, Done{context})),
        same((tape, Done{context})))
    case 1n+p Tuple{tape, TC.Failed{error}}:
      Equal.cong(A, IO.OP<A>, value => Emit{value}, f((tape, Fail{error})), g((tape, Fail{error})),
        same((tape, Fail{error})))
    case 1n+p Tuple{tape, TC.NeedWord{draw}}:
      read_tape_same(A, f, g, same, p, TC.Draw.fed_by(Laws.Tape(), TC.Tape.next(tape), draw))

# Law generation_drive: induction on the budget, for every tape and step.
# Neither loop reads a word once the step has ended or the budget is spent;
# the host's loop, whose bound is the budget plus `extra`, then stops on
# Generation.needs, and each word the budget allows is fed alike.
law generation_drive:
  for fuel: Nat
  for tape: Laws.Tape()
  for step: TC.Step
  for extra: Nat
  {Laws.host(Nat.add(fuel, extra), tape, TC.Generation{fuel, step}) ==
    TC.Draw.outcome(Laws.Tape(), TC.Draw.run(fuel, (tape, step))) : Laws.TapeOutcome()}

def generation_drive(fuel, tape, step, extra):
  match fuel tape step extra:
    case 0n _ TC.Created{context} 0n:
      {==}
    case 0n _ TC.Created{context} 1n+q:
      {==}
    case 0n _ TC.Failed{error} 0n:
      {==}
    case 0n _ TC.Failed{error} 1n+q:
      {==}
    case 0n _ TC.NeedWord{draw} 0n:
      {==}
    case 0n _ TC.NeedWord{draw} 1n+q:
      {==}
    case 1n+p _ TC.Created{context} _:
      {==}
    case 1n+p _ TC.Failed{error} _:
      {==}
    case 1n+p Nil{} TC.NeedWord{draw} _:
      generation_drive(p, Nil{}, TC.Draw.feed(Fail{(1, "tape-exhausted")}, draw), extra)
    case 1n+p Con{word, rest} TC.NeedWord{draw} _:
      generation_drive(p, rest, TC.Draw.feed(word, draw), extra)

# The IO driver over Source.tape emits, through any continuation that emits
# a function `f` of the outcome, what `g` gives of the host's loop bounded
# by the budget, whenever `f` and `g` agree on every outcome (`same`).
# Induction on the budget, as read_tape_outcome; the tape is linear, so
# this cannot join read_tape_outcome and generation_drive. Used by
# run_hosted.
law read_tape_host:
  for -A: Type
  for -f: Laws.TapeOutcome() -> A
  for -g: Laws.TapeOutcome() -> A
  for same: @outcome: Laws.TapeOutcome() -> {f(outcome) == g(outcome) : A}
  for fuel: Nat
  for tape: Laws.Tape()
  for step: TC.Step
  {TC.Draw.read(~Laws.Tape(), ~TC.Source.tape, fuel, (tape, step))(A,
    current => Emit{f(TC.Draw.outcome(Laws.Tape(), current))}) ==
    Emit{g(Laws.host(fuel, tape, TC.Generation{fuel, step}))} : IO.OP<A>}

def read_tape_host(A, f, g, same, fuel, tape, step):
  match fuel tape step:
    case 0n _ TC.Created{context}:
      Equal.cong(A, IO.OP<A>, value => Emit{value}, f((tape, Done{context})), g((tape, Done{context})),
        same((tape, Done{context})))
    case 0n _ TC.Failed{error}:
      Equal.cong(A, IO.OP<A>, value => Emit{value}, f((tape, Fail{error})), g((tape, Fail{error})),
        same((tape, Fail{error})))
    case 0n _ TC.NeedWord{draw}:
      Equal.cong(A, IO.OP<A>, value => Emit{value},
        f(TC.Draw.outcome(Laws.Tape(), (tape, TC.NeedWord{draw}))),
        g(TC.Draw.outcome(Laws.Tape(), (tape, TC.NeedWord{draw}))),
        same(TC.Draw.outcome(Laws.Tape(), (tape, TC.NeedWord{draw}))))
    case 1n+p _ TC.Created{context}:
      Equal.cong(A, IO.OP<A>, value => Emit{value}, f((tape, Done{context})), g((tape, Done{context})),
        same((tape, Done{context})))
    case 1n+p _ TC.Failed{error}:
      Equal.cong(A, IO.OP<A>, value => Emit{value}, f((tape, Fail{error})), g((tape, Fail{error})),
        same((tape, Fail{error})))
    case 1n+p Nil{} TC.NeedWord{draw}:
      read_tape_host(A, f, g, same, p, Nil{}, TC.Draw.feed(Fail{(1, "tape-exhausted")}, draw))
    case 1n+p Con{word, rest} TC.NeedWord{draw}:
      read_tape_host(A, f, g, same, p, rest, TC.Draw.feed(word, draw))

# Generation.run_with over Source.tape, followed by a continuation that
# emits a function `f` of its outcome, emits what `g` gives of the host's
# loop over the same generation (Laws.host.drive), whenever `f` and `g`
# agree on every outcome. By read_tape_host on the generation's budget and
# step. proofs/continue.bend uses it for the plans of section 14.
law run_hosted:
  for -A: Type
  for -f: Laws.TapeOutcome() -> A
  for -g: Laws.TapeOutcome() -> A
  for same: @outcome: Laws.TapeOutcome() -> {f(outcome) == g(outcome) : A}
  for tape: Laws.Tape()
  for generation: TC.Generation
  {TC.Generation.run_with(~Laws.Tape(), ~TC.Source.tape, tape, generation)(A, done => Emit{f(done)}) ==
    Emit{g(Laws.host.drive(tape, generation))} : IO.OP<A>}

def run_hosted(A, f, g, same, tape, generation):
  match generation:
    case TC.Generation{fuel, step}:
      read_tape_host(A, f, g, same, fuel, tape, step)

# Roots, children and restarts over a tape
# ========================================
#
# Laws root_tape, child_tape and restart_tape: Context.root_with, child_with
# and restart_with, which compose the separate generation, produce over
# Source.tape the outcome of the pure driver Draw.run with the generation's
# budget. Each composition reads its words with TraceDraw.read and
# SpanDraw.read, while Draw.run feeds the same words to the same draws
# through Draw.feed, so one induction on a draw's fuel follows both at once.
# The tape is linear, so the draw's IO driver and the generation's pure one
# cannot be related through two lemmas joined by Equal.trans.

# Over a tape, a span ID draw that SpanDraw.read runs, followed by a
# continuation that emits a function `k` of the context of its span ID for
# an operation of `trace_id` with `sampled` (Draw.span_context), emits `k` of
# the outcome of Draw.run for the generation that Draw.spanned makes of the
# draw, with `extra` words of fuel to spare, when the draw ends within
# `fuel` words (`bound`). Induction on the fuel, splitting the tape: both
# drivers read the same word and feed it to the same draw.
law span_phase:
  for -A: Type
  for -k: Laws.TapeOutcome() -> A
  for -trace_id: TC.TraceId
  for -sampled: Bool
  for +fuel: Nat
  for +step: TC.SpanStep
  for tape: Laws.Tape()
  for extra: Nat
  for bound: SeparateProof.SpanWithin(step, fuel)
  {TC.SpanDraw.read(~Laws.Tape(), ~TC.Source.tape, fuel, (tape, step))(A,
    done => Emit{k(TC.Draw.span_context(Laws.Tape(), trace_id, sampled, TC.SpanDraw.outcome(Laws.Tape(), done)))}) ==
    Emit{k(TC.Draw.outcome(Laws.Tape(), TC.Draw.run(Nat.add(fuel, extra),
      (tape, TC.Draw.spanned(step, trace_id, sampled)))))} : IO.OP<A>}

def span_phase(A, k, trace_id, sampled, fuel, step, tape, extra, bound):
  match fuel:
    case 0n:
      match step:
        case TC.DrawnSpanId{id}:
          match extra:
            case 0n:
              {==}
            case 1n+q:
              {==}
        case TC.SpanFailed{error}:
          match extra:
            case 0n:
              {==}
            case 1n+q:
              {==}
        case TC.NeedSpanWord{remaining, words, excluded}:
          Empty.absurd({TC.SpanDraw.read(~Laws.Tape(), ~TC.Source.tape, 0n,
            (tape, TC.NeedSpanWord{remaining, words, excluded}))(A, done => Emit{k(TC.Draw.span_context(Laws.Tape(),
              trace_id, sampled, TC.SpanDraw.outcome(Laws.Tape(), done)))}) ==
            Emit{k(TC.Draw.outcome(Laws.Tape(), TC.Draw.run(Nat.add(0n, extra),
              (tape, TC.Draw.spanned(TC.NeedSpanWord{remaining, words, excluded}, trace_id, sampled)))))} :
            IO.OP<A>}, bound)
    case 1n+p:
      match step:
        case TC.DrawnSpanId{id}:
          {==}
        case TC.SpanFailed{error}:
          {==}
        case TC.NeedSpanWord{+remaining, +words, +excluded}:
          match tape:
            case Nil{}:
              span_phase(A, k, trace_id, sampled, p, TC.SpanFailed{TC.SourceFailure{1, "tape-exhausted"}}, Nil{},
                extra, Unit{})
            case Con{Fail{(code, message)}, rest}:
              span_phase(A, k, trace_id, sampled, p, TC.SpanFailed{TC.SourceFailure{code, message}}, rest, extra,
                Unit{})
            case Con{Done{+word}, rest}:
              span_phase(A, k, trace_id, sampled, p, TC.SpanDraw.feed(Done{word}, remaining, words, excluded), rest,
                extra, bound(word))

# Over a tape, a trace ID draw that TraceDraw.read runs, followed by
# Draw.after_trace and a continuation that emits a function `k` of the
# outcome, emits `k` of the outcome of Draw.run for the generation that
# Draw.traced makes of the draw, with 16 more words of fuel for the span ID,
# when the draw ends within `fuel` words (`bound`). Induction on the fuel,
# as span_phase; a drawn trace ID hands over to span_phase for the span ID
# draw that both then run, with the words that the trace ID draw left to
# spare.
law trace_phase:
  for -A: Type
  for -k: Laws.TapeOutcome() -> A
  for +fuel: Nat
  for +step: TC.TraceStep
  for tape: Laws.Tape()
  for bound: SeparateProof.TraceWithin(step, fuel)
  {TC.TraceDraw.read(~Laws.Tape(), ~TC.Source.tape, fuel, (tape, step))(A,
    done => TC.Draw.after_trace(~Laws.Tape(), ~TC.Source.tape, TC.TraceDraw.outcome(Laws.Tape(), done))(A,
      outcome => Emit{k(outcome)})) ==
    Emit{k(TC.Draw.outcome(Laws.Tape(), TC.Draw.run(Nat.add(16n, fuel), (tape, TC.Draw.traced(step)))))} :
    IO.OP<A>}

def trace_phase(A, k, fuel, step, tape, bound):
  match fuel:
    case 0n:
      match step:
        case TC.DrawnTraceId{id}:
          span_phase(A, k, id, False{}, 16n, TC.SpanDraw.start(None{}), tape, 0n,
            SeparateProof.span_start_within(7n, None{}))
        case TC.TraceFailed{error}:
          {==}
        case TC.NeedTraceWord{remaining, words, excluded}:
          Empty.absurd({TC.TraceDraw.read(~Laws.Tape(), ~TC.Source.tape, 0n,
            (tape, TC.NeedTraceWord{remaining, words, excluded}))(A, done => TC.Draw.after_trace(~Laws.Tape(),
              ~TC.Source.tape, TC.TraceDraw.outcome(Laws.Tape(), done))(A, outcome => Emit{k(outcome)})) ==
            Emit{k(TC.Draw.outcome(Laws.Tape(), TC.Draw.run(16n,
              (tape, TC.Draw.traced(TC.NeedTraceWord{remaining, words, excluded})))))} : IO.OP<A>}, bound)
    case 1n+p:
      match step:
        case TC.DrawnTraceId{id}:
          span_phase(A, k, id, False{}, 16n, TC.SpanDraw.start(None{}), tape, 1n+p,
            SeparateProof.span_start_within(7n, None{}))
        case TC.TraceFailed{error}:
          {==}
        case TC.NeedTraceWord{+remaining, +words, +excluded}:
          match tape:
            case Nil{}:
              trace_phase(A, k, p, TC.TraceFailed{TC.SourceFailure{1, "tape-exhausted"}}, Nil{}, Unit{})
            case Con{Fail{(code, message)}, rest}:
              trace_phase(A, k, p, TC.TraceFailed{TC.SourceFailure{code, message}}, rest, Unit{})
            case Con{Done{+word}, rest}:
              trace_phase(A, k, p, TC.TraceDraw.feed(Done{word}, remaining, words, excluded), rest, bound(word))

# Law root_tape: generating a root as an IO action over a tape source
# (Context.root_with with Source.tape) produces Draw.outcome of the pure
# driver Draw.run with the same budget of 48 words: trace_phase from the
# first trace ID candidate, with nothing to exclude, whose 32 words
# SeparateProof.trace_start_within bounds. Laws.root_tape returns this proof.
law root_tape:
  for tape: Laws.Tape()
  {Laws.Observe(Laws.TapeOutcome(), TC.Context.root_with(~Laws.Tape(), ~TC.Source.tape, tape)) ==
    Emit{TC.Draw.outcome(Laws.Tape(), TC.Draw.run(48n, (tape, TC.Draw.root())))} : IO.OP<Laws.TapeOutcome()>}

def root_tape(tape):
  trace_phase(Laws.TapeOutcome(), outcome => outcome, 32n, TC.TraceDraw.start(None{}), tape,
    SeparateProof.trace_start_within(7n, None{}))

# Law child_tape: as root_tape, for a child with a budget of 16 words:
# span_phase from the first span ID candidate, which excludes the parent's
# span ID, with no word to spare. Laws.child_tape returns this proof.
law child_tape:
  for tape: Laws.Tape()
  for +parent: TC.Parent
  for sampling: TC.Sampling
  {Laws.Observe(Laws.TapeOutcome(), TC.Context.child_with(~Laws.Tape(), ~TC.Source.tape, tape, parent, sampling)) ==
    Emit{TC.Draw.outcome(Laws.Tape(), TC.Draw.run(16n, (tape, TC.Draw.child(parent, sampling))))} : IO.OP<Laws.TapeOutcome()>}

def child_tape(tape, parent, sampling):
  span_phase(Laws.TapeOutcome(), outcome => outcome, TC.Parent.trace_id(parent),
    TC.Sampling.resolve(sampling, TC.Parent.is_sampled(parent)), 16n,
    TC.SpanDraw.start(Some{TC.Parent.span_id(parent)}), tape, 0n,
    SeparateProof.span_start_within(7n, Some{TC.Parent.span_id(parent)}))

# Law restart_tape: as root_tape, for a restart with a budget of 48 words,
# whose first trace ID candidate excludes the received trace ID.
# Laws.restart_tape returns this proof.
law restart_tape:
  for tape: Laws.Tape()
  for +previous: TC.RemoteContext
  {Laws.Observe(Laws.TapeOutcome(), TC.Context.restart_with(~Laws.Tape(), ~TC.Source.tape, tape, previous)) ==
    Emit{TC.Draw.outcome(Laws.Tape(), TC.Draw.run(48n, (tape, TC.Draw.restart(previous))))} : IO.OP<Laws.TapeOutcome()>}

def restart_tape(tape, previous):
  trace_phase(Laws.TapeOutcome(), outcome => outcome, 32n,
    TC.TraceDraw.start(Some{TC.RemoteContext.trace_id(previous)}), tape,
    SeparateProof.trace_start_within(7n, Some{TC.RemoteContext.trace_id(previous)}))
