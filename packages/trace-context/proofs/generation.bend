# Proofs: the generation machine over tapes
# =========================================
#
# What generation does when its words come from a tape: the list of word
# results that a replayed source returns. The generation machine of
# trace_context.bend (Draw.feed, which feeds each word to the trace ID draw
# or the span ID draw that the generation runs, through Step.of_trace and
# Step.of_span) is driven purely by Draw.run and as an IO action by
# Draw.read over Source.tape, both through Drive, as Generation.run_with and
# the operations of section 14 do. Context.root_with, child_with and
# restart_with compose the separate generation instead (laws root_composed,
# child_composed and restart_composed), and proofs/separate.bend proves what
# each draw does alone. PROOF.bend proves these laws of LAWS.bend with this
# module: root_tape, child_tape and restart_tape (the lemmas of the same
# names, through trace_phase and span_phase); root_ends, child_ends and
# restart_ends (run_ends with root_within, child_within and restart_within);
# generated_root and generated_restart (new_trace_run, through the view
# NewTraceRun) and generated_child (child_run, through ChildRun). feed_failure,
# root_exhaustion and child_exhaustion need no lemma: PROOF.bend proves them
# by computation.
#
# The inductions over the drive are those of proofs/drive.bend, proved once
# for every machine; this module gives what is particular to generation:
#
# - Termination. StepWithin(view, n) is DriveProof.Within for a generation.
#   A span ID draw that ends within n words gives a generation that ends
#   within n words (span_lift_within), and a trace ID draw that ends within
#   n words one that ends within 16 more, those of the span ID draw that
#   follows it (trace_lift_within). These give the bounds of a root, a
#   restart and a child, and run_ends turns a bound equal to the fuel into
#   Draw.ended for every tape (DriveProof.drive_ends), with step_fails.
# - Created contexts. A root and a restart draw a new trace: a trace ID that
#   avoids `avoided`, none for a root and the received trace ID for a
#   restart, then the span ID of the root's span plan. NewTraceFinal holds of
#   the contexts they create the conclusions of generated_root and
#   generated_restart, and NewTracePending of each waiting draw what it keeps.
#   A child draws the span ID of its span plan, and ChildFinal and
#   ChildPending say the same of it with generated_child. A word keeps the
#   invariant of the draw that the generation runs (SeparateProof.trace_kept
#   or span_kept), and a lifting lemma gives the generation's
#   (trace_lift_holds, span_lift_new, span_lift_child); so does a whole drive
#   (new_trace_run, child_run, by DriveProof.drive_keeps).
# - IO. read_tape_outcome shows that Draw.read over Source.tape computes
#   Draw.run, whatever function of the outcome the continuation emits, and
#   read_tape_same relates two continuations that agree on every outcome
#   (DriveProof.drive_read and drive_same); proofs/continue.bend and
#   proofs/http.bend use them. generation_drive and read_tape_host relate
#   Draw.run and Draw.read to the loop of a host that feeds a Generation
#   itself.
# - Compositions. span_phase shows, by induction on the fuel, that a span ID
#   draw that Drive.read runs over a tape, followed by the context of its
#   span ID, emits what Draw.run gives for the generation that Step.of_span
#   makes of the draw, even with fuel to spare; trace_phase shows the same
#   for a trace ID draw followed by Draw.root_span_with. root_tape,
#   child_tape and restart_tape apply them to the first steps.
#
# The statements use Tape, TapeStep, TapeOutcome, Observe and host of
# LAWS.bend, so each statement here is the statement of the law it proves.

import Base
import ../trace_context.bend as TC
import ./drive.bend as DriveProof
import ./separate.bend as SeparateProof
import ../LAWS.bend as Laws

# Word bounds
# ===========
#
# StepWithin(view, n) states that a generation ends within n more words. The
# bounds of the draws, proved in proofs/separate.bend, give it for the first
# step of every generation.

# The claim "a generation whose step has the view `view` ends within n more
# words, whatever they are": DriveProof.Within for the generation.
def StepWithin(view: Maybe<&2, TC.Draw>, n: Nat) -> Type:
  DriveProof.Within(~TC.Step, ~TC.Draw, ~TC.Step.waiting, ~TC.Draw.feed, view, n)

# The same claim of a step: StepWithin of its view.
def StepEnds(step: TC.Step, n: Nat) -> Type:
  StepWithin(TC.Step.waiting(step), n)

# A span ID draw's bound carries over to the generation that Step.of_span
# makes of its step, for every trace ID and sampled indication: feeding a
# word to the generation feeds it to the draw. Induction on n. child_within
# and trace_lift_within use it.
law span_lift_within:
  for +n: Nat
  for +step: TC.SpanStep
  for +trace_id: TC.TraceId
  for +sampled: Bool
  for bound: SeparateProof.SpanEnds(step, n)
  StepEnds(TC.Step.of_span(step, trace_id, sampled), n)

def span_lift_within(n, step, trace_id, sampled, bound):
  match n step:
    case _ TC.DrawnSpanId{id}:
      Unit{}
    case _ TC.SpanFailed{error}:
      Unit{}
    case 0n TC.NeedSpanWord{draw}:
      Empty.absurd(StepEnds(TC.Step.of_span(TC.NeedSpanWord{draw}, trace_id, sampled), 0n), bound)
    case 1n+p TC.NeedSpanWord{+draw}:
      +word => span_lift_within(p, TC.SpanDraw.next(Done{word}, draw), trace_id, sampled, bound(word))

# A trace ID draw's bound carries over to the generation that Step.of_trace
# makes of its step, with 16 more words for the span ID that follows: a
# drawn trace ID starts the span ID draw of the root's span plan, which
# SeparateProof.span_start_within bounds by 16 words, loosened by the words
# that the trace ID draw had left (DriveProof.within_plus). Induction on n.
# root_within and restart_within use it.
law trace_lift_within:
  for +n: Nat
  for +step: TC.TraceStep
  for bound: SeparateProof.TraceEnds(step, n)
  StepEnds(TC.Step.of_trace(step), Nat.add(16n, n))

def trace_lift_within(n, step, bound):
  match n step:
    case _ TC.DrawnTraceId{+id}:
      DriveProof.within_plus(~TC.Step, ~TC.Draw, ~TC.Step.waiting, ~TC.Draw.feed, 16n, n,
        TC.Step.waiting(TC.SpanPlan.draw(TC.SpanPlan.root(id))),
        span_lift_within(16n, TC.SpanDraw.start(None{}), id, False{}, SeparateProof.span_start_within(7n, None{})))
    case _ TC.TraceFailed{error}:
      Unit{}
    case 0n TC.NeedTraceWord{draw}:
      Empty.absurd(StepEnds(TC.Step.of_trace(TC.NeedTraceWord{draw}), 16n), bound)
    case 1n+p TC.NeedTraceWord{+draw}:
      +word => trace_lift_within(p, TC.TraceDraw.next(Done{word}, draw), bound(word))

# Every generation ends
# =====================
#
# The bounds of the first step of a root, a restart and a child, and
# run_ends, which turns such a bound into the end of Draw.run (laws
# root_ends, restart_ends and child_ends).

# A root generation ends within 48 words, whatever they are: its trace ID
# draw within 32 and its span ID draw within 16 more. The bound that
# Laws.root_ends passes to run_ends.
law root_within:
  StepEnds(TC.Draw.root(), 48n)

def root_within():
  trace_lift_within(32n, TC.TraceDraw.start(None{}), SeparateProof.trace_start_within(7n, None{}))

# A restart ends within 48 words, whatever they are, as a root: the bound
# that Laws.restart_ends passes to run_ends.
law restart_within:
  for +previous: TC.RemoteContext
  StepEnds(TC.Draw.restart(previous), 48n)

def restart_within(previous):
  trace_lift_within(32n, TC.TraceDraw.start(TC.Draw.restart_excluded(previous)),
    SeparateProof.trace_start_within(7n, TC.Draw.restart_excluded(previous)))

# A child generation ends within 16 words, whatever they are, those of the
# span ID draw of its span plan: the bound that Laws.child_ends passes to
# run_ends.
law child_within:
  for +parent: TC.Parent
  for sampling: TC.Sampling
  StepEnds(TC.Draw.child(parent, sampling), 16n)

def child_within(parent, sampling):
  span_lift_within(16n, TC.SpanDraw.start(Some{TC.Parent.span_id(parent)}), TC.Parent.trace_id(parent),
    TC.Sampling.resolve(sampling, TC.Parent.is_sampled(parent)),
    SeparateProof.span_start_within(7n, Some{TC.Parent.span_id(parent)}))

# A source error ends a generation at once, whatever it draws (law
# feed_failure): the `fails` that DriveProof.drive_ends takes.
law step_fails:
  for draw: TC.Draw
  for code: U32
  for message: String
  {TC.Step.waiting(TC.Draw.feed(Fail{(code, message)}, draw)) == None{} : Maybe<&2, TC.Draw>}

# Splits the draw that the generation runs, so that its feed computes.
def step_fails(draw, code, message):
  match draw:
    case TC.DrawTrace{trace}:
      match trace:
        case TC.TraceDraw{remaining, words, excluded}:
          {==}
    case TC.DrawSpan{span, trace_id, sampled}:
      match span:
        case TC.SpanDraw{remaining, words, excluded}:
          {==}

# Driving a generation with enough fuel ends it, whatever the tape holds:
# when the step ends within `fuel` words (StepEnds), Draw.run with that fuel
# returns an ended step. Laws.root_ends, child_ends and restart_ends apply
# it with root_within, child_within and restart_within.
# DriveProof.drive_ends, for the generation.
law run_ends:
  for +fuel: Nat
  for +step: TC.Step
  for tape: Laws.Tape()
  for bound: StepEnds(step, fuel)
  {TC.Draw.ended(TC.Draw.run(fuel, (tape, step))) == True{} : Bool}

def run_ends(fuel, step, tape, bound):
  DriveProof.drive_ends(~TC.Step, ~TC.Draw, ~TC.Step.waiting, ~TC.Draw.feed, ~step_fails, fuel, step,
    TC.Step.waiting(step), {==}, bound, tape)

# Roots and restarts
# ==================
#
# A root and a restart draw a new trace: a trace ID that avoids `avoided`,
# nothing for a root and the received trace ID for a restart, then the span
# ID of the root's span plan, which excludes nothing and is not sampled.

# What law generated_root, or generated_restart, concludes of a context of
# the trace ID `trace_id` with the sampled indication `sampled`, created by
# a new trace that avoids `avoided`: the trace ID asserts random-trace-id,
# the context is not sampled, and, for a restart, the trace ID differs from
# the received one.
def NewTrace(avoided: Maybe<&2, TC.TraceId>, +trace_id: TC.TraceId, sampled: Bool) -> Type:
  match avoided:
    case None{}:
      {TC.TraceId.is_random(trace_id) == True{} : Bool} & {sampled == False{} : Bool}
    case Some{old}:
      {TC.TraceId.to_string(trace_id) != TC.TraceId.to_string(old) : String} &
      {TC.TraceId.is_random(trace_id) == True{} : Bool} & {sampled == False{} : Bool}

# What the invariant of a new trace says of an ended step: NewTrace of a
# created context, and nothing (Unit) of a failure, as of a waiting step.
def NewTraceFinal(avoided: Maybe<&2, TC.TraceId>, step: TC.Step) -> Type:
  match step:
    case TC.NeedWord{draw}:
      Unit
    case TC.Created{+context}:
      NewTrace(avoided, TC.LocalContext.trace_id(context), TC.LocalContext.is_sampled(context))
    case TC.Failed{error}:
      Unit

# What a waiting draw of a new trace keeps: its trace ID draw excludes
# `avoided` (SeparateProof.TracePending), and its span ID draw has a trace
# ID and a sampled indication with NewTrace and excludes nothing.
def NewTracePending(avoided: Maybe<&2, TC.TraceId>, draw: TC.Draw) -> Type:
  match draw:
    case TC.DrawTrace{trace}:
      SeparateProof.TracePending(avoided, trace)
    case TC.DrawSpan{span, trace_id, sampled}:
      NewTrace(avoided, trace_id, sampled) & SeparateProof.SpanPending(None{}, span)

# The invariant of a new trace, a view of each step: DriveProof.Holds with
# NewTraceFinal and NewTracePending.
def NewTraceHolds(+avoided: Maybe<&2, TC.TraceId>, +step: TC.Step) -> Type:
  DriveProof.Holds(~TC.Step, ~TC.Draw, ~Maybe<&2, TC.TraceId>, ~NewTraceFinal, ~NewTracePending, avoided, step,
    TC.Step.waiting(step))

# A drawn trace ID that asserts random-trace-id (`random`) and avoids
# `avoided` (`avoids`, law generated_trace_id's conclusion) has NewTrace
# with the root's sampled indication, False.
law new_trace_drawn:
  for avoided: Maybe<&2, TC.TraceId>
  for -id: TC.TraceId
  for random: {TC.TraceId.is_random(id) == True{} : Bool}
  for avoids: Laws.TraceAvoids(avoided, id)
  NewTrace(avoided, id, False{})

def new_trace_drawn(avoided, id, random, avoids):
  match avoided:
    case None{}:
      (random, {==})
    case Some{old}:
      (avoids, (random, {==}))

# The generation that a new trace's trace ID draw gives, Step.of_trace, keeps
# the invariant when the draw keeps SeparateProof.TraceHolds: a waiting draw
# excludes `avoided`, and a drawn trace ID starts the span ID draw of the
# root's span plan, whose trace ID has NewTrace by new_trace_drawn.
law trace_lift_holds:
  for avoided: Maybe<&2, TC.TraceId>
  for step: TC.TraceStep
  for valid: SeparateProof.TraceHolds(avoided, step)
  NewTraceHolds(avoided, TC.Step.of_trace(step))

def trace_lift_holds(avoided, step, valid):
  match step:
    case TC.NeedTraceWord{draw}:
      valid
    case TC.DrawnTraceId{id}:
      (random, avoids) = valid
      (Unit{}, (new_trace_drawn(avoided, id, random, avoids), {==}))
    case TC.TraceFailed{error}:
      Unit{}

# The generation that a new trace's span ID draw gives, Step.of_span, keeps
# the invariant when its trace ID and sampled indication have NewTrace
# (`plan`) and the draw keeps SeparateProof.SpanHolds with nothing to
# exclude: a created context has that trace ID and sampled indication.
law span_lift_new:
  for -avoided: Maybe<&2, TC.TraceId>
  for step: TC.SpanStep
  for -trace_id: TC.TraceId
  for -sampled: Bool
  for plan: NewTrace(avoided, trace_id, sampled)
  for valid: SeparateProof.SpanHolds(None{}, step)
  NewTraceHolds(avoided, TC.Step.of_span(step, trace_id, sampled))

def span_lift_new(avoided, step, trace_id, sampled, plan, valid):
  match step:
    case TC.NeedSpanWord{draw}:
      (final, pending) = valid
      (Unit{}, (plan, pending))
    case TC.DrawnSpanId{id}:
      plan
    case TC.SpanFailed{error}:
      Unit{}

# When a waiting draw of a new trace keeps NewTracePending (`valid`), the
# invariant holds after feeding it any word result: the draw that the
# generation runs keeps its invariant (SeparateProof.trace_kept or
# span_kept), which trace_lift_holds or span_lift_new lifts. The word is
# split so that each side gets its own copy. The `kept` that
# DriveProof.drive_keeps takes.
law new_trace_kept:
  for +avoided: Maybe<&2, TC.TraceId>
  for draw: TC.Draw
  for valid: NewTracePending(avoided, draw)
  for word: Result<&1, &1, U32 & String, U32>
  NewTraceHolds(avoided, TC.Draw.feed(word, draw))

def new_trace_kept(avoided, draw, valid, word):
  match draw:
    case TC.DrawTrace{+trace}:
      match word:
        case Fail{(+code, +message)}:
          trace_lift_holds(avoided, TC.TraceDraw.next(Fail{(code, message)}, trace),
            SeparateProof.trace_kept(avoided, trace, valid, Fail{(code, message)}))
        case Done{+next}:
          trace_lift_holds(avoided, TC.TraceDraw.next(Done{next}, trace),
            SeparateProof.trace_kept(avoided, trace, valid, Done{next}))
    case TC.DrawSpan{+span, trace_id, sampled}:
      (plan, pending) = valid
      match word:
        case Fail{(+code, +message)}:
          span_lift_new(avoided, TC.SpanDraw.next(Fail{(code, message)}, span), trace_id, sampled, plan,
            SeparateProof.span_kept(None{}, span, pending, Fail{(code, message)}))
        case Done{+next}:
          span_lift_new(avoided, TC.SpanDraw.next(Done{next}, span), trace_id, sampled, plan,
            SeparateProof.span_kept(None{}, span, pending, Done{next}))

# The view of Draw.run's result for a new trace: NewTraceFinal of its final
# step, the unread tape ignored (DriveProof.Ends). Laws.generated_root and
# generated_restart rewrite their hypothesis
# {Draw.run(...) == (rest, Created{created})} through NewTraceRun, which
# turns the law's conclusion into NewTraceRun of the drive, proved by
# new_trace_run.
def NewTraceRun(avoided: Maybe<&2, TC.TraceId>, result: Laws.TapeStep()) -> Type:
  DriveProof.Ends(~TC.Step, ~Maybe<&2, TC.TraceId>, ~NewTraceFinal, avoided, result)

# When a step keeps the invariant of a new trace, the step that Draw.run
# returns from it has NewTraceFinal, for every fuel and every tape:
# DriveProof.drive_keeps with new_trace_kept. Laws.generated_root applies it
# to Draw.root(), and Laws.generated_restart to Draw.restart(previous), whose
# invariants hold by computation.
law new_trace_run:
  for +avoided: Maybe<&2, TC.TraceId>
  for +fuel: Nat
  for +step: TC.Step
  for tape: Laws.Tape()
  for valid: NewTraceHolds(avoided, step)
  NewTraceRun(avoided, TC.Draw.run(fuel, (tape, step)))

def new_trace_run(avoided, fuel, step, tape, valid):
  DriveProof.drive_keeps(~TC.Step, ~TC.Draw, ~TC.Step.waiting, ~TC.Draw.feed, ~Maybe<&2, TC.TraceId>,
    ~NewTraceFinal, ~NewTracePending, ~new_trace_kept, avoided, fuel, step, TC.Step.waiting(step), tape, valid)

# Children
# ========
#
# A child draws only the span ID of its span plan (SpanPlan.child). Every
# state keeps the plan's trace ID, its sampled indication and its span ID to
# exclude, the parent's.

# What law generated_child concludes of a context created for the span plan
# `plan`: the plan's trace ID and sampled indication, and a span ID that
# avoids the one that the plan excludes. A failure needs nothing (Unit), as
# a waiting step.
def ChildFinal(plan: TC.SpanPlan, step: TC.Step) -> Type:
  match plan:
    case TC.SpanPlan{excluded, trace_id, sampled}:
      match step:
        case TC.NeedWord{draw}:
          Unit
        case TC.Created{+context}:
          {TC.LocalContext.trace_id(context) == trace_id : TC.TraceId} &
          {TC.LocalContext.is_sampled(context) == sampled : Bool} &
          Laws.SpanAvoids(excluded, TC.LocalContext.span_id(context))
        case TC.Failed{error}:
          Unit

# What a waiting draw of a child keeps: a trace ID draw is impossible
# (Empty), since a child draws only its span ID, and its span ID draw keeps
# the plan's trace ID and sampled indication and excludes the plan's span ID
# (SeparateProof.SpanPending).
def ChildPending(plan: TC.SpanPlan, draw: TC.Draw) -> Type:
  match plan:
    case TC.SpanPlan{excluded, trace_id, sampled}:
      match draw:
        case TC.DrawTrace{trace}:
          Empty
        case TC.DrawSpan{span, span_trace_id, span_sampled}:
          {span_trace_id == trace_id : TC.TraceId} & {span_sampled == sampled : Bool} &
          SeparateProof.SpanPending(excluded, span)

# The invariant of a child of the span plan `plan`, a view of each step:
# DriveProof.Holds with ChildFinal and ChildPending.
def ChildHolds(+plan: TC.SpanPlan, +step: TC.Step) -> Type:
  DriveProof.Holds(~TC.Step, ~TC.Draw, ~TC.SpanPlan, ~ChildFinal, ~ChildPending, plan, step, TC.Step.waiting(step))

# The generation that a child's span ID draw gives, Step.of_span, keeps the
# invariant when it keeps the plan's trace ID (`same_trace`) and sampled
# indication (`same_sampled`) and the draw keeps SeparateProof.SpanHolds
# with the plan's span ID to exclude: the span ID of a created context
# avoids it.
law span_lift_child:
  for -excluded: Maybe<&2, TC.SpanId>
  for -trace_id: TC.TraceId
  for -sampled: Bool
  for step: TC.SpanStep
  for -span_trace_id: TC.TraceId
  for -span_sampled: Bool
  for same_trace: {span_trace_id == trace_id : TC.TraceId}
  for same_sampled: {span_sampled == sampled : Bool}
  for valid: SeparateProof.SpanHolds(excluded, step)
  ChildHolds(TC.SpanPlan{excluded, trace_id, sampled}, TC.Step.of_span(step, span_trace_id, span_sampled))

def span_lift_child(excluded, trace_id, sampled, step, span_trace_id, span_sampled, same_trace, same_sampled, valid):
  match step:
    case TC.NeedSpanWord{draw}:
      (final, pending) = valid
      (Unit{}, (same_trace, (same_sampled, pending)))
    case TC.DrawnSpanId{id}:
      (same_trace, (same_sampled, valid))
    case TC.SpanFailed{error}:
      Unit{}

# When a waiting draw of a child keeps ChildPending (`valid`), the invariant
# holds after feeding it any word result. A trace ID draw is ruled out,
# since its invariant is Empty; the span ID draw keeps its invariant
# (SeparateProof.span_kept), which span_lift_child lifts. The `kept` that
# DriveProof.drive_keeps takes.
law child_kept:
  for +plan: TC.SpanPlan
  for draw: TC.Draw
  for valid: ChildPending(plan, draw)
  for word: Result<&1, &1, U32 & String, U32>
  ChildHolds(plan, TC.Draw.feed(word, draw))

def child_kept(plan, draw, valid, word):
  match plan:
    case TC.SpanPlan{+excluded, trace_id, sampled}:
      match draw:
        case TC.DrawTrace{trace}:
          Empty.absurd(ChildHolds(TC.SpanPlan{excluded, trace_id, sampled}, TC.Draw.feed(word, TC.DrawTrace{trace})),
            valid)
        case TC.DrawSpan{+span, span_trace_id, span_sampled}:
          (same_trace, rest) = valid
          (same_sampled, pending) = rest
          match word:
            case Fail{(+code, +message)}:
              span_lift_child(excluded, trace_id, sampled, TC.SpanDraw.next(Fail{(code, message)}, span),
                span_trace_id, span_sampled, same_trace, same_sampled,
                SeparateProof.span_kept(excluded, span, pending, Fail{(code, message)}))
            case Done{+next}:
              span_lift_child(excluded, trace_id, sampled, TC.SpanDraw.next(Done{next}, span), span_trace_id,
                span_sampled, same_trace, same_sampled, SeparateProof.span_kept(excluded, span, pending, Done{next}))

# The view of Draw.run's result for a child: ChildFinal of its final step,
# the unread tape ignored. Laws.generated_child rewrites its hypothesis
# through ChildRun(SpanPlan.child(parent, sampling), _), as for NewTraceRun.
def ChildRun(plan: TC.SpanPlan, result: Laws.TapeStep()) -> Type:
  DriveProof.Ends(~TC.Step, ~TC.SpanPlan, ~ChildFinal, plan, result)

# When a step keeps the invariant of a child, the step that Draw.run returns
# from it has ChildFinal, for every fuel and every tape: DriveProof.drive_keeps
# with child_kept. Laws.generated_child applies it to
# Draw.child(parent, sampling), whose invariant is three equations that hold
# by computation.
law child_run:
  for +plan: TC.SpanPlan
  for +fuel: Nat
  for +step: TC.Step
  for tape: Laws.Tape()
  for valid: ChildHolds(plan, step)
  ChildRun(plan, TC.Draw.run(fuel, (tape, step)))

def child_run(plan, fuel, step, tape, valid):
  DriveProof.drive_keeps(~TC.Step, ~TC.Draw, ~TC.Step.waiting, ~TC.Draw.feed, ~TC.SpanPlan, ~ChildFinal,
    ~ChildPending, ~child_kept, plan, fuel, step, TC.Step.waiting(step), tape, valid)

# The IO operations over a tape
# =============================

# Over a tape, the IO driver computes what the pure driver computes: running
# Draw.read over Source.tape, followed by a continuation that emits a
# function `f` of the driver's outcome, gives what any `g` that agrees with
# `f` on every outcome (`same`) emits for the outcome of Draw.run, the same
# words read in the same order: DriveProof.drive_read, with `f` and `g` read
# through the generation's outcome. proofs/continue.bend rests on it.
law read_tape_outcome:
  for -A: Type
  for -f: Laws.TapeOutcome() -> A
  for -g: Laws.TapeOutcome() -> A
  for same: @outcome: Laws.TapeOutcome() -> {f(outcome) == g(outcome) : A}
  for +fuel: Nat
  for current: Laws.TapeStep()
  {TC.Draw.read(~Laws.Tape(), ~TC.Source.tape, fuel, current)(A, step => Emit{f(TC.Draw.outcome(Laws.Tape(), step))}) ==
    Emit{g(TC.Draw.outcome(Laws.Tape(), TC.Draw.run(fuel, current)))} : IO.OP<A>}

# Splits the tape and the step, which Draw.read and Draw.run hand to Drive
# with the step's view.
def read_tape_outcome(A, f, g, same, fuel, current):
  match current:
    case Tuple{tape, +step}:
      DriveProof.drive_read(~TC.Step, ~TC.Draw, ~TC.Step.waiting, ~TC.Draw.feed, A,
        done => f(TC.Draw.outcome(Laws.Tape(), done)), done => g(TC.Draw.outcome(Laws.Tape(), done)),
        done => same(TC.Draw.outcome(Laws.Tape(), done)), fuel, (tape, (step, TC.Step.waiting(step))))

# Two continuations that emit functions `f` and `g` of the driver's outcome
# make Draw.read over Source.tape emit the same whenever `f` and `g` agree on
# every outcome (`same`): DriveProof.drive_same. proofs/http.bend uses it for
# an adapter that follows the package's operation with its own translation.
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
  match current:
    case Tuple{tape, +step}:
      DriveProof.drive_same(~TC.Step, ~TC.Draw, ~TC.Step.waiting, ~TC.Draw.feed, A,
        done => Emit{f(TC.Draw.outcome(Laws.Tape(), done))}, done => Emit{g(TC.Draw.outcome(Laws.Tape(), done))},
        done => Equal.cong(A, IO.OP<A>, value => Emit{value}, f(TC.Draw.outcome(Laws.Tape(), done)),
          g(TC.Draw.outcome(Laws.Tape(), done)), same(TC.Draw.outcome(Laws.Tape(), done))), fuel,
        (tape, (step, TC.Step.waiting(step))))

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
# Induction on the budget, as DriveProof.drive_read; the tape is linear, so
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
# budget. Each composition reads its words through the draws' IO drivers,
# while Draw.run feeds the same words to the same draws through Draw.feed, so
# one induction on a draw's fuel follows both at once. The tape is linear,
# so the draw's IO driver and the generation's pure one cannot be related
# through two lemmas joined by Equal.trans.

# Over a tape, a span ID draw that Drive.read runs from `step`, followed by
# a continuation that emits a function `k` of the context of its span ID for
# an operation of `trace_id` with `sampled` (Draw.span_context), emits `k` of
# the outcome of Draw.run for the generation that Step.of_span makes of the
# draw, with `extra` words of fuel to spare, when the draw ends within
# `fuel` words (`bound`). Induction on the fuel, splitting the tape and the
# draw: both drivers read the same word and feed it to the same draw.
law span_phase:
  for -A: Type
  for -k: Laws.TapeOutcome() -> A
  for -trace_id: TC.TraceId
  for -sampled: Bool
  for +fuel: Nat
  for +step: TC.SpanStep
  for tape: Laws.Tape()
  for extra: Nat
  for bound: SeparateProof.SpanEnds(step, fuel)
  {TC.Drive.read(~TC.SpanStep, ~TC.SpanDraw, ~TC.SpanStep.waiting, ~TC.SpanDraw.next, ~Laws.Tape(), ~TC.Source.tape,
    fuel, (tape, (step, TC.SpanStep.waiting(step))))(A, done => Emit{k(TC.Draw.span_context(Laws.Tape(), trace_id,
      sampled, TC.SpanDraw.outcome(Laws.Tape(), done)))}) ==
    Emit{k(TC.Draw.outcome(Laws.Tape(), TC.Draw.run(Nat.add(fuel, extra),
      (tape, TC.Step.of_span(step, trace_id, sampled)))))} : IO.OP<A>}

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
        case TC.NeedSpanWord{draw}:
          Empty.absurd({TC.Drive.read(~TC.SpanStep, ~TC.SpanDraw, ~TC.SpanStep.waiting, ~TC.SpanDraw.next,
            ~Laws.Tape(), ~TC.Source.tape, 0n, (tape, (TC.NeedSpanWord{draw}, Some{draw})))(A,
              done => Emit{k(TC.Draw.span_context(Laws.Tape(), trace_id, sampled,
                TC.SpanDraw.outcome(Laws.Tape(), done)))}) ==
            Emit{k(TC.Draw.outcome(Laws.Tape(), TC.Draw.run(Nat.add(0n, extra),
              (tape, TC.Step.of_span(TC.NeedSpanWord{draw}, trace_id, sampled)))))} : IO.OP<A>}, bound)
    case 1n+p:
      match step:
        case TC.DrawnSpanId{id}:
          {==}
        case TC.SpanFailed{error}:
          {==}
        case TC.NeedSpanWord{TC.SpanDraw{remaining, words, excluded}}:
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

# Over a tape, a trace ID draw that Drive.read runs from `step`, followed by
# Draw.root_span_with and a continuation that emits a function `k` of the
# outcome, emits `k` of the outcome of Draw.run for the generation that
# Step.of_trace makes of the draw, with 16 more words of fuel for the span
# ID, when the draw ends within `fuel` words (`bound`). Induction on the
# fuel, as span_phase; a drawn trace ID hands over to span_phase for the
# span ID draw of the root's span plan, which both then run, with the words
# that the trace ID draw left to spare.
law trace_phase:
  for -A: Type
  for -k: Laws.TapeOutcome() -> A
  for +fuel: Nat
  for +step: TC.TraceStep
  for tape: Laws.Tape()
  for bound: SeparateProof.TraceEnds(step, fuel)
  {TC.Drive.read(~TC.TraceStep, ~TC.TraceDraw, ~TC.TraceStep.waiting, ~TC.TraceDraw.next, ~Laws.Tape(),
    ~TC.Source.tape, fuel, (tape, (step, TC.TraceStep.waiting(step))))(A,
      done => TC.Draw.root_span_with(~Laws.Tape(), ~TC.Source.tape, TC.TraceDraw.outcome(Laws.Tape(), done))(A,
        outcome => Emit{k(outcome)})) ==
    Emit{k(TC.Draw.outcome(Laws.Tape(), TC.Draw.run(Nat.add(16n, fuel), (tape, TC.Step.of_trace(step)))))} :
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
        case TC.NeedTraceWord{draw}:
          Empty.absurd({TC.Drive.read(~TC.TraceStep, ~TC.TraceDraw, ~TC.TraceStep.waiting, ~TC.TraceDraw.next,
            ~Laws.Tape(), ~TC.Source.tape, 0n, (tape, (TC.NeedTraceWord{draw}, Some{draw})))(A,
              done => TC.Draw.root_span_with(~Laws.Tape(), ~TC.Source.tape, TC.TraceDraw.outcome(Laws.Tape(), done))(A,
                outcome => Emit{k(outcome)})) ==
            Emit{k(TC.Draw.outcome(Laws.Tape(), TC.Draw.run(16n, (tape, TC.Step.of_trace(TC.NeedTraceWord{draw})))))} :
            IO.OP<A>}, bound)
    case 1n+p:
      match step:
        case TC.DrawnTraceId{id}:
          span_phase(A, k, id, False{}, 16n, TC.SpanDraw.start(None{}), tape, 1n+p,
            SeparateProof.span_start_within(7n, None{}))
        case TC.TraceFailed{error}:
          {==}
        case TC.NeedTraceWord{TC.TraceDraw{remaining, words, excluded}}:
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
# span_phase from the first span ID candidate of the child's span plan,
# which excludes the parent's span ID, with no word to spare.
# Laws.child_tape returns this proof.
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
  trace_phase(Laws.TapeOutcome(), outcome => outcome, 32n, TC.TraceDraw.start(TC.Draw.restart_excluded(previous)),
    tape, SeparateProof.trace_start_within(7n, TC.Draw.restart_excluded(previous)))
