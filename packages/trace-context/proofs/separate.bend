# Proofs: separate generation
# ===========================
#
# What the two pieces of the generation machine do alone, over tapes: a trace
# ID draw (TraceDraw.feed and the TraceDraw.check, reuse and retry functions
# that decide a candidate) and a span ID draw (the same for SpanDraw), which
# Drive runs, purely with Drive.run as TraceDraw.run and SpanDraw.run do, and
# as IO actions with Drive.read over Source.tape, as TraceId.generate_with
# and SpanId.generate_with do. PROOF.bend proves the laws of the "Separate
# generation" part of section 6 of LAWS.bend with this module: trace_id_tape
# (read_trace_tape), trace_id_ends (trace_run_ends with trace_start_within)
# and generated_trace_id (trace_run_holds, through the view TraceRunView),
# the same for span IDs, root_composed and restart_composed
# (new_trace_composed: read_trace_same with root_span_same), and
# child_composed (read_span_same with span_context_same). trace_id_failure,
# trace_id_exhaustion and their
# span ID twins need no lemma: PROOF.bend proves them by computation, and
# trace_id_candidate and span_id_candidate by computation once their
# hypothesis is rewritten. proofs/generation.bend builds the laws of root,
# child and restart generation on the lemmas of this module.
#
# The inductions over the drive are those of proofs/drive.bend, proved once
# for every machine; this module gives what is particular to each piece:
#
# - Termination. TraceWithin(view, n) is DriveProof.Within for a trace ID
#   draw. The *_within lemmas follow the draw word by word and candidate by
#   candidate, TraceRetry carrying the bound of the next candidate, and
#   trace_run_ends turns a bound equal to the fuel into TraceDraw.ended for
#   every tape (DriveProof.drive_ends), with trace_fails.
# - Drawn identifiers. TraceFinal holds of a drawn trace ID the conclusions
#   of generated_trace_id, and TracePending of a waiting draw that it keeps
#   the trace ID to exclude. The first step keeps both (TraceHolds), every
#   word result keeps them (trace_kept), and so does a whole drive
#   (trace_run_holds, by DriveProof.drive_keeps).
# - IO. read_trace_tape and read_trace_same are DriveProof.drive_read and
#   drive_same for a trace ID draw from its first step. The checker compares
#   two continuations only once the outcome that they receive is known, so
#   root_span_same and span_context_same are agreements on every outcome.
#
# The statements use Tape, TapeTraceStep, TapeTraceId, TapeSpanStep,
# TapeSpanId, TapeOutcome, TraceAvoids, SpanAvoids, root_of and context_of of
# LAWS.bend.

import Base
import ../trace_context.bend as TC
import ./strings.bend as StringsProof
import ./drive.bend as DriveProof
import ../LAWS.bend as Laws

# Trace ID draws: word bounds
# ===========================

# The claim "a trace ID draw whose step has the view `view` ends within n
# more words, whatever they are": DriveProof.Within for the trace ID draw.
def TraceWithin(view: Maybe<&2, TC.TraceDraw>, n: Nat) -> Type:
  DriveProof.Within(~TC.TraceStep, ~TC.TraceDraw, ~TC.TraceStep.waiting, ~TC.TraceDraw.next, view, n)

# The same claim of a step: TraceWithin of its view.
def TraceEnds(step: TC.TraceStep, n: Nat) -> Type:
  TraceWithin(TC.TraceStep.waiting(step), n)

# The words a trace ID draw may still read when it starts a candidate with
# `remaining` further candidates allowed: four for each of the 1 + remaining
# candidates. trace_budget(7n) is 32, the word budget of TraceId.generate_with.
def trace_budget(remaining: Nat) -> Nat:
  match remaining:
    case 0n:
      4n
    case 1n+p:
      4n+trace_budget(p)

# The words a trace ID draw may still read once a candidate is complete: four
# for each further candidate allowed, none after the last one.
def trace_after(remaining: Nat) -> Nat:
  match remaining:
    case 0n:
      0n
    case 1n+p:
      trace_budget(p)

# The bound assumed for a retry, the induction hypothesis on the candidates
# left: nothing when no further candidate is allowed (a retry fails with
# ExhaustedTraceId), and otherwise the bound of the fresh candidate that a
# retry starts. trace_start_within supplies it by recursion.
def TraceRetry(+remaining: Nat, excluded: Maybe<&2, TC.TraceId>) -> Type:
  match remaining:
    case 0n:
      Unit
    case 1n+p:
      TraceWithin(Some{TC.TraceDraw{p, TC.NoTraceWord{}, excluded}}, trace_budget(p))

# Retrying a candidate leaves the draw within trace_after(remaining) words,
# given `retry`: an exhausted draw has failed, and otherwise the retry is the
# fresh candidate that `retry` bounds.
law trace_retry_within:
  for +remaining: Nat
  for +excluded: Maybe<&2, TC.TraceId>
  for retry: TraceRetry(remaining, excluded)
  TraceEnds(TC.TraceDraw.retry(remaining, excluded), trace_after(remaining))

def trace_retry_within(remaining, excluded, retry):
  match remaining:
    case 0n:
      Unit{}
    case 1n+p:
      retry

# Deciding a candidate by `reused`, its comparison with the excluded trace
# ID, leaves the draw within trace_after(remaining) words given `retry`: a
# reused candidate is retried, and any other one is drawn.
law trace_reuse_within:
  for reused: Bool
  for -id: TC.TraceId
  for +old: TC.TraceId
  for +remaining: Nat
  for retry: TraceRetry(remaining, Some{old})
  TraceEnds(TC.TraceDraw.reuse(reused, id, old, remaining), trace_after(remaining))

def trace_reuse_within(reused, id, old, remaining, retry):
  match reused:
    case True{}:
      trace_retry_within(remaining, Some{old}, retry)
    case False{}:
      Unit{}

# Checking a complete candidate, whatever it is, leaves the draw within
# trace_after(remaining) words, given `retry`. The cases follow
# TraceDraw.check: zero is retried, and a nonzero candidate is drawn or, when
# the draw excludes a trace ID, compared with it.
law trace_check_within:
  for candidate: Maybe<&2, TC.TraceId>
  for +excluded: Maybe<&2, TC.TraceId>
  for +remaining: Nat
  for retry: TraceRetry(remaining, excluded)
  TraceEnds(TC.TraceDraw.check(candidate, excluded, remaining), trace_after(remaining))

def trace_check_within(candidate, excluded, remaining, retry):
  match candidate:
    case None{}:
      trace_retry_within(remaining, excluded, retry)
    case Some{+id}:
      match excluded:
        case None{}:
          Unit{}
        case Some{+old}:
          trace_reuse_within(TC.TraceId.is_eq(id, old), id, old, remaining, retry)

# A draw holding three words of a candidate ends within one word more than
# trace_after(remaining), given `retry`: whatever the fourth word, it
# completes the candidate, which TraceDraw.check decides.
law trace_fourth_within:
  for +remaining: Nat
  for +excluded: Maybe<&2, TC.TraceId>
  for retry: TraceRetry(remaining, excluded)
  for +first: U32
  for +second: U32
  for +third: U32
  TraceWithin(Some{TC.TraceDraw{remaining, TC.ThreeTraceWords{first, second, third}, excluded}},
    1n+trace_after(remaining))

def trace_fourth_within(remaining, excluded, retry, first, second, third):
  +fourth => trace_check_within(TC.Draw.asserted(TC.TraceId.from_words(first, second, third, fourth)), excluded,
    remaining, retry)

# A draw holding two words of a candidate ends within two words more than
# trace_after(remaining), given `retry`, whatever the third word.
law trace_third_within:
  for +remaining: Nat
  for +excluded: Maybe<&2, TC.TraceId>
  for retry: TraceRetry(remaining, excluded)
  for +first: U32
  for +second: U32
  TraceWithin(Some{TC.TraceDraw{remaining, TC.TwoTraceWords{first, second}, excluded}}, 2n+trace_after(remaining))

def trace_third_within(remaining, excluded, retry, first, second):
  +third => trace_fourth_within(remaining, excluded, retry, first, second, third)

# A draw holding one word of a candidate ends within three words more than
# trace_after(remaining), given `retry`, whatever the second word.
law trace_second_within:
  for +remaining: Nat
  for +excluded: Maybe<&2, TC.TraceId>
  for retry: TraceRetry(remaining, excluded)
  for +first: U32
  TraceWithin(Some{TC.TraceDraw{remaining, TC.OneTraceWord{first}, excluded}}, 3n+trace_after(remaining))

def trace_second_within(remaining, excluded, retry, first):
  +second => trace_third_within(remaining, excluded, retry, first, second)

# A draw at the start of a candidate, with `remaining` further candidates
# allowed, ends within trace_budget(remaining) words, for every trace ID to
# exclude and every sequence of words. Induction on remaining: the bound for
# one candidate fewer is the `retry` of the lemmas above. Laws.trace_id_ends
# uses it with remaining 7n, which gives 32 words.
law trace_start_within:
  for +remaining: Nat
  for +excluded: Maybe<&2, TC.TraceId>
  TraceWithin(Some{TC.TraceDraw{remaining, TC.NoTraceWord{}, excluded}}, trace_budget(remaining))

def trace_start_within(remaining, excluded):
  match remaining:
    case 0n:
      +first => trace_second_within(0n, excluded, Unit{}, first)
    case 1n+p:
      +first => trace_second_within(1n+p, excluded, trace_start_within(p, excluded), first)

# A source error ends a trace ID draw at once, whatever the draw (law
# trace_id_failure): the `fails` that DriveProof.drive_ends takes.
law trace_fails:
  for draw: TC.TraceDraw
  for code: U32
  for message: String
  {TC.TraceStep.waiting(TC.TraceDraw.next(Fail{(code, message)}, draw)) == None{} : Maybe<&2, TC.TraceDraw>}

# Splits the draw so that TraceDraw.next computes.
def trace_fails(draw, code, message):
  match draw:
    case TC.TraceDraw{remaining, words, excluded}:
      {==}

# Driving a trace ID draw with enough fuel ends it, whatever the tape holds:
# when the step ends within `fuel` words (TraceEnds), TraceDraw.run with that
# fuel returns an ended draw. DriveProof.drive_ends, for the trace ID draw.
law trace_run_ends:
  for +fuel: Nat
  for +step: TC.TraceStep
  for tape: Laws.Tape()
  for bound: TraceEnds(step, fuel)
  {TC.TraceDraw.ended(TC.TraceDraw.run(fuel, (tape, step))) == True{} : Bool}

def trace_run_ends(fuel, step, tape, bound):
  DriveProof.drive_ends(~TC.TraceStep, ~TC.TraceDraw, ~TC.TraceStep.waiting, ~TC.TraceDraw.next, ~trace_fails, fuel,
    step, TC.TraceStep.waiting(step), {==}, bound, tape)

# Trace ID draws: drawn trace IDs
# ===============================

# The view "this trace ID candidate asserts random-trace-id": Unit for None{}
# (a zero candidate, which is retried) and, for Some{id}, the equation that
# id is random. trace_check_holds takes it as a hypothesis about the
# candidate it checks.
def RandomCandidate(candidate: Maybe<&2, TC.TraceId>) -> Type:
  match candidate:
    case None{}:
      Unit
    case Some{id}:
      {TC.TraceId.is_random(id) == True{} : Bool}

# Every trace ID candidate that generation checks asserts random-trace-id:
# Draw.asserted, which TraceDraw.take applies to each complete candidate,
# sets the assertion on every present one. trace_kept uses it when the
# fourth word completes a candidate.
law asserted_random:
  for candidate: Maybe<&2, TC.TraceId>
  RandomCandidate(TC.Draw.asserted(candidate))

# Splits the trace ID so that TraceId.assert_random computes.
def asserted_random(candidate):
  match candidate:
    case None{}:
      Unit{}
    case Some{id}:
      match id:
        case TC.TraceId{value, random}:
          {==}

# What law generated_trace_id concludes of a trace ID draw that must avoid
# `avoided`, once it has ended: a drawn trace ID asserts random-trace-id and
# avoids `avoided`, and a failure needs nothing (Unit), as a waiting draw.
def TraceFinal(avoided: Maybe<&2, TC.TraceId>, step: TC.TraceStep) -> Type:
  match step:
    case TC.NeedTraceWord{draw}:
      Unit
    case TC.DrawnTraceId{id}:
      {TC.TraceId.is_random(id) == True{} : Bool} & Laws.TraceAvoids(avoided, id)
    case TC.TraceFailed{error}:
      Unit

# What a waiting trace ID draw that must avoid `avoided` keeps: `avoided` as
# the trace ID that it excludes.
def TracePending(avoided: Maybe<&2, TC.TraceId>, draw: TC.TraceDraw) -> Type:
  match draw:
    case TC.TraceDraw{remaining, words, excluded}:
      {excluded == avoided : Maybe<&2, TC.TraceId>}

# The invariant of a trace ID draw that must avoid `avoided`, a view of each
# step: DriveProof.Holds with TraceFinal and TracePending.
def TraceHolds(+avoided: Maybe<&2, TC.TraceId>, +step: TC.TraceStep) -> Type:
  DriveProof.Holds(~TC.TraceStep, ~TC.TraceDraw, ~Maybe<&2, TC.TraceId>, ~TraceFinal, ~TracePending, avoided, step,
    TC.TraceStep.waiting(step))

# When a draw excludes `avoided` (`valid`), retrying its candidate keeps the
# invariant: the fresh candidate excludes it too, and an exhausted draw has
# failed.
law trace_retry_holds:
  for -avoided: Maybe<&2, TC.TraceId>
  for remaining: Nat
  for -excluded: Maybe<&2, TC.TraceId>
  for valid: {excluded == avoided : Maybe<&2, TC.TraceId>}
  TraceHolds(avoided, TC.TraceDraw.retry(remaining, excluded))

def trace_retry_holds(avoided, remaining, excluded, valid):
  match remaining:
    case 0n:
      Unit{}
    case 1n+p:
      (Unit{}, valid)

# When a draw excludes the trace ID `old`, which is `avoided` (`valid`), and
# the candidate `id` asserts random-trace-id (`random`), deciding the
# candidate keeps the invariant. `reused` is the result of
# TraceId.is_eq(id, old), passed with the equation `evidence` because `match`
# inspects only variables: a reused candidate is retried, and a drawn one
# differs from `old` by StringsProof.distinct.
law trace_reuse_holds:
  for -avoided: Maybe<&2, TC.TraceId>
  for reused: Bool
  for +id: TC.TraceId
  for +old: TC.TraceId
  for remaining: Nat
  for evidence: {TC.TraceId.is_eq(id, old) == reused : Bool}
  for valid: {Some{old} == avoided : Maybe<&2, TC.TraceId>}
  for random: {TC.TraceId.is_random(id) == True{} : Bool}
  TraceHolds(avoided, TC.TraceDraw.reuse(reused, id, old, remaining))

def trace_reuse_holds(avoided, reused, id, old, remaining, evidence, valid, random):
  match reused:
    case True{}:
      trace_retry_holds(avoided, remaining, Some{old}, valid)
    case False{}:
      %valid : {TC.TraceId.is_random(id) == True{} : Bool} & Laws.TraceAvoids(_, id)
      (random, StringsProof.distinct(TC.TraceId.to_string(id), TC.TraceId.to_string(old), evidence))

# When a draw excludes `avoided` (`valid`) and its complete candidate asserts
# random-trace-id (`random`), checking the candidate keeps the invariant. A
# draw with nothing to exclude draws any nonzero candidate, which avoids
# nothing; otherwise trace_reuse_holds decides the candidate.
law trace_check_holds:
  for -avoided: Maybe<&2, TC.TraceId>
  for candidate: Maybe<&2, TC.TraceId>
  for +excluded: Maybe<&2, TC.TraceId>
  for remaining: Nat
  for valid: {excluded == avoided : Maybe<&2, TC.TraceId>}
  for random: RandomCandidate(candidate)
  TraceHolds(avoided, TC.TraceDraw.check(candidate, excluded, remaining))

def trace_check_holds(avoided, candidate, excluded, remaining, valid, random):
  match candidate:
    case None{}:
      trace_retry_holds(avoided, remaining, excluded, valid)
    case Some{+id}:
      match excluded:
        case None{}:
          %valid : {TC.TraceId.is_random(id) == True{} : Bool} & Laws.TraceAvoids(_, id)
          (random, Unit{})
        case Some{+old}:
          trace_reuse_holds(avoided, TC.TraceId.is_eq(id, old), id, old, remaining, {==}, valid, random)

# When a waiting draw excludes `avoided` (`valid`), the invariant holds after
# it takes any word: a word that only extends a candidate changes nothing
# the invariant speaks of, and the fourth goes through trace_check_holds, its
# candidate random by asserted_random.
law trace_take_holds:
  for -avoided: Maybe<&2, TC.TraceId>
  for +word: U32
  for remaining: Nat
  for words: TC.TraceWords
  for +excluded: Maybe<&2, TC.TraceId>
  for valid: {excluded == avoided : Maybe<&2, TC.TraceId>}
  TraceHolds(avoided, TC.TraceDraw.take(word, remaining, words, excluded))

def trace_take_holds(avoided, word, remaining, words, excluded, valid):
  match words:
    case TC.NoTraceWord{}:
      (Unit{}, valid)
    case TC.OneTraceWord{first}:
      (Unit{}, valid)
    case TC.TwoTraceWords{first, second}:
      (Unit{}, valid)
    case TC.ThreeTraceWords{+first, +second, +third}:
      trace_check_holds(avoided, TC.Draw.asserted(TC.TraceId.from_words(first, second, third, word)), excluded,
        remaining, valid, asserted_random(TC.TraceId.from_words(first, second, third, word)))

# When a waiting draw excludes `avoided` (`valid`), the invariant holds after
# feeding it any word result: a source error fails the draw, which needs
# nothing, and a word is taken (trace_take_holds). The `kept` that
# DriveProof.drive_keeps takes.
law trace_kept:
  for +avoided: Maybe<&2, TC.TraceId>
  for draw: TC.TraceDraw
  for valid: TracePending(avoided, draw)
  for word: Result<&1, &1, U32 & String, U32>
  TraceHolds(avoided, TC.TraceDraw.next(word, draw))

def trace_kept(avoided, draw, valid, word):
  match draw:
    case TC.TraceDraw{remaining, words, excluded}:
      match word:
        case Fail{(code, message)}:
          Unit{}
        case Done{next}:
          trace_take_holds(avoided, next, remaining, words, excluded, valid)

# The view of TraceDraw.run's result: TraceFinal of its final step, the
# unread tape ignored (DriveProof.Ends). Laws.generated_trace_id rewrites its
# hypothesis {TraceDraw.run(...) == (rest, DrawnTraceId{id})} through
# TraceRunView, which turns the law's conclusion into TraceRunView of the
# drive, proved by trace_run_holds.
def TraceRunView(avoided: Maybe<&2, TC.TraceId>, result: Laws.TapeTraceStep()) -> Type:
  DriveProof.Ends(~TC.TraceStep, ~Maybe<&2, TC.TraceId>, ~TraceFinal, avoided, result)

# When a step keeps the invariant, the step that TraceDraw.run returns from
# it has TraceFinal, for every fuel and every tape: DriveProof.drive_keeps
# with trace_kept. Laws.generated_trace_id applies it to
# TraceDraw.start(excluded), whose invariant holds by computation.
law trace_run_holds:
  for +avoided: Maybe<&2, TC.TraceId>
  for +fuel: Nat
  for +step: TC.TraceStep
  for tape: Laws.Tape()
  for valid: TraceHolds(avoided, step)
  TraceRunView(avoided, TC.TraceDraw.run(fuel, (tape, step)))

def trace_run_holds(avoided, fuel, step, tape, valid):
  DriveProof.drive_keeps(~TC.TraceStep, ~TC.TraceDraw, ~TC.TraceStep.waiting, ~TC.TraceDraw.next,
    ~Maybe<&2, TC.TraceId>, ~TraceFinal, ~TracePending, ~trace_kept, avoided, fuel, step, TC.TraceStep.waiting(step),
    tape, valid)

# Trace ID draws: the IO operation over a tape
# ============================================

# Over a tape, the IO driver of a trace ID draw from `step`, as
# TraceId.generate_with runs it, computes what its pure driver TraceDraw.run
# computes: DriveProof.drive_read, with `f` and `g` read through the draw's
# outcome.
law read_trace_tape:
  for -A: Type
  for -f: Laws.TapeTraceId() -> A
  for -g: Laws.TapeTraceId() -> A
  for same: @outcome: Laws.TapeTraceId() -> {f(outcome) == g(outcome) : A}
  for +fuel: Nat
  for tape: Laws.Tape()
  for +step: TC.TraceStep
  {TC.Drive.read(~TC.TraceStep, ~TC.TraceDraw, ~TC.TraceStep.waiting, ~TC.TraceDraw.next, ~Laws.Tape(),
    ~TC.Source.tape, fuel, (tape, (step, TC.TraceStep.waiting(step))))(A,
      done => Emit{f(TC.TraceDraw.outcome(Laws.Tape(), done))}) ==
    Emit{g(TC.TraceDraw.outcome(Laws.Tape(), TC.TraceDraw.run(fuel, (tape, step))))} : IO.OP<A>}

def read_trace_tape(A, f, g, same, fuel, tape, step):
  DriveProof.drive_read(~TC.TraceStep, ~TC.TraceDraw, ~TC.TraceStep.waiting, ~TC.TraceDraw.next, A,
    done => f(TC.TraceDraw.outcome(Laws.Tape(), done)), done => g(TC.TraceDraw.outcome(Laws.Tape(), done)),
    done => same(TC.TraceDraw.outcome(Laws.Tape(), done)), fuel, (tape, (step, TC.TraceStep.waiting(step))))

# Two continuations `f` and `g` of a trace ID draw's outcome make its IO
# driver over Source.tape, from `step`, give the same whenever they agree on
# every outcome (`same`): DriveProof.drive_same, read through the outcome.
law read_trace_same:
  for -A: Type
  for -f: Laws.TapeTraceId() -> IO.OP<A>
  for -g: Laws.TapeTraceId() -> IO.OP<A>
  for same: @outcome: Laws.TapeTraceId() -> {f(outcome) == g(outcome) : IO.OP<A>}
  for +fuel: Nat
  for tape: Laws.Tape()
  for +step: TC.TraceStep
  {TC.Drive.read(~TC.TraceStep, ~TC.TraceDraw, ~TC.TraceStep.waiting, ~TC.TraceDraw.next, ~Laws.Tape(),
    ~TC.Source.tape, fuel, (tape, (step, TC.TraceStep.waiting(step))))(A,
      done => f(TC.TraceDraw.outcome(Laws.Tape(), done))) ==
    TC.Drive.read(~TC.TraceStep, ~TC.TraceDraw, ~TC.TraceStep.waiting, ~TC.TraceDraw.next, ~Laws.Tape(),
      ~TC.Source.tape, fuel, (tape, (step, TC.TraceStep.waiting(step))))(A,
        done => g(TC.TraceDraw.outcome(Laws.Tape(), done))) : IO.OP<A>}

def read_trace_same(A, f, g, same, fuel, tape, step):
  DriveProof.drive_same(~TC.TraceStep, ~TC.TraceDraw, ~TC.TraceStep.waiting, ~TC.TraceDraw.next, A,
    done => f(TC.TraceDraw.outcome(Laws.Tape(), done)), done => g(TC.TraceDraw.outcome(Laws.Tape(), done)),
    done => same(TC.TraceDraw.outcome(Laws.Tape(), done)), fuel, (tape, (step, TC.TraceStep.waiting(step))))

# Span ID draws: word bounds
# ==========================
#
# The lemmas of the trace ID draws, for span ID draws: two words per
# candidate.

# The claim "a span ID draw whose step has the view `view` ends within n
# more words, whatever they are", as TraceWithin states it of a trace ID
# draw.
def SpanWithin(view: Maybe<&2, TC.SpanDraw>, n: Nat) -> Type:
  DriveProof.Within(~TC.SpanStep, ~TC.SpanDraw, ~TC.SpanStep.waiting, ~TC.SpanDraw.next, view, n)

# The same claim of a step: SpanWithin of its view.
def SpanEnds(step: TC.SpanStep, n: Nat) -> Type:
  SpanWithin(TC.SpanStep.waiting(step), n)

# The words a span ID draw may still read when it starts a candidate with
# `remaining` further candidates allowed: two for each of the 1 + remaining
# candidates. span_budget(7n) is 16, the word budget of SpanId.generate_with.
def span_budget(remaining: Nat) -> Nat:
  match remaining:
    case 0n:
      2n
    case 1n+p:
      2n+span_budget(p)

# The words a span ID draw may still read once a candidate is complete: two
# for each further candidate allowed, none after the last one.
def span_after(remaining: Nat) -> Nat:
  match remaining:
    case 0n:
      0n
    case 1n+p:
      span_budget(p)

# The bound assumed for a retry, as TraceRetry.
def SpanRetry(+remaining: Nat, excluded: Maybe<&2, TC.SpanId>) -> Type:
  match remaining:
    case 0n:
      Unit
    case 1n+p:
      SpanWithin(Some{TC.SpanDraw{p, TC.NoSpanWord{}, excluded}}, span_budget(p))

# As trace_retry_within.
law span_retry_within:
  for +remaining: Nat
  for +excluded: Maybe<&2, TC.SpanId>
  for retry: SpanRetry(remaining, excluded)
  SpanEnds(TC.SpanDraw.retry(remaining, excluded), span_after(remaining))

def span_retry_within(remaining, excluded, retry):
  match remaining:
    case 0n:
      Unit{}
    case 1n+p:
      retry

# As trace_reuse_within.
law span_reuse_within:
  for reused: Bool
  for -id: TC.SpanId
  for +old: TC.SpanId
  for +remaining: Nat
  for retry: SpanRetry(remaining, Some{old})
  SpanEnds(TC.SpanDraw.reuse(reused, id, old, remaining), span_after(remaining))

def span_reuse_within(reused, id, old, remaining, retry):
  match reused:
    case True{}:
      span_retry_within(remaining, Some{old}, retry)
    case False{}:
      Unit{}

# As trace_check_within.
law span_check_within:
  for candidate: Maybe<&2, TC.SpanId>
  for +excluded: Maybe<&2, TC.SpanId>
  for +remaining: Nat
  for retry: SpanRetry(remaining, excluded)
  SpanEnds(TC.SpanDraw.check(candidate, excluded, remaining), span_after(remaining))

def span_check_within(candidate, excluded, remaining, retry):
  match candidate:
    case None{}:
      span_retry_within(remaining, excluded, retry)
    case Some{+id}:
      match excluded:
        case None{}:
          Unit{}
        case Some{+old}:
          span_reuse_within(TC.SpanId.is_eq(id, old), id, old, remaining, retry)

# A span ID draw holding the first word of a candidate ends within one word
# more than span_after(remaining), given `retry`: whatever the second word,
# it completes the candidate, which SpanDraw.check decides.
law span_second_within:
  for +remaining: Nat
  for +excluded: Maybe<&2, TC.SpanId>
  for retry: SpanRetry(remaining, excluded)
  for +first: U32
  SpanWithin(Some{TC.SpanDraw{remaining, TC.OneSpanWord{first}, excluded}}, 1n+span_after(remaining))

def span_second_within(remaining, excluded, retry, first):
  +second => span_check_within(TC.SpanId.from_words(first, second), excluded, remaining, retry)

# A span ID draw at the start of a candidate, with `remaining` further
# candidates allowed, ends within span_budget(remaining) words, for every
# span ID to exclude and every sequence of words, as trace_start_within.
# Laws.span_id_ends uses it with remaining 7n, which gives 16 words.
law span_start_within:
  for +remaining: Nat
  for +excluded: Maybe<&2, TC.SpanId>
  SpanWithin(Some{TC.SpanDraw{remaining, TC.NoSpanWord{}, excluded}}, span_budget(remaining))

def span_start_within(remaining, excluded):
  match remaining:
    case 0n:
      +first => span_second_within(0n, excluded, Unit{}, first)
    case 1n+p:
      +first => span_second_within(1n+p, excluded, span_start_within(p, excluded), first)

# As trace_fails, for span ID draws (law span_id_failure).
law span_fails:
  for draw: TC.SpanDraw
  for code: U32
  for message: String
  {TC.SpanStep.waiting(TC.SpanDraw.next(Fail{(code, message)}, draw)) == None{} : Maybe<&2, TC.SpanDraw>}

def span_fails(draw, code, message):
  match draw:
    case TC.SpanDraw{remaining, words, excluded}:
      {==}

# As trace_run_ends, for span ID draws.
law span_run_ends:
  for +fuel: Nat
  for +step: TC.SpanStep
  for tape: Laws.Tape()
  for bound: SpanEnds(step, fuel)
  {TC.SpanDraw.ended(TC.SpanDraw.run(fuel, (tape, step))) == True{} : Bool}

def span_run_ends(fuel, step, tape, bound):
  DriveProof.drive_ends(~TC.SpanStep, ~TC.SpanDraw, ~TC.SpanStep.waiting, ~TC.SpanDraw.next, ~span_fails, fuel, step,
    TC.SpanStep.waiting(step), {==}, bound, tape)

# Span ID draws: drawn span IDs
# =============================

# What law generated_span_id concludes of a span ID draw that must avoid
# `avoided`, once it has ended, as TraceFinal without the randomness
# assertion: a drawn span ID avoids `avoided`.
def SpanFinal(avoided: Maybe<&2, TC.SpanId>, step: TC.SpanStep) -> Type:
  match step:
    case TC.NeedSpanWord{draw}:
      Unit
    case TC.DrawnSpanId{id}:
      Laws.SpanAvoids(avoided, id)
    case TC.SpanFailed{error}:
      Unit

# What a waiting span ID draw that must avoid `avoided` keeps, as
# TracePending.
def SpanPending(avoided: Maybe<&2, TC.SpanId>, draw: TC.SpanDraw) -> Type:
  match draw:
    case TC.SpanDraw{remaining, words, excluded}:
      {excluded == avoided : Maybe<&2, TC.SpanId>}

# The invariant of a span ID draw that must avoid `avoided`, as TraceHolds.
def SpanHolds(+avoided: Maybe<&2, TC.SpanId>, +step: TC.SpanStep) -> Type:
  DriveProof.Holds(~TC.SpanStep, ~TC.SpanDraw, ~Maybe<&2, TC.SpanId>, ~SpanFinal, ~SpanPending, avoided, step,
    TC.SpanStep.waiting(step))

# As trace_retry_holds.
law span_retry_holds:
  for -avoided: Maybe<&2, TC.SpanId>
  for remaining: Nat
  for -excluded: Maybe<&2, TC.SpanId>
  for valid: {excluded == avoided : Maybe<&2, TC.SpanId>}
  SpanHolds(avoided, TC.SpanDraw.retry(remaining, excluded))

def span_retry_holds(avoided, remaining, excluded, valid):
  match remaining:
    case 0n:
      Unit{}
    case 1n+p:
      (Unit{}, valid)

# As trace_reuse_holds: a drawn span ID differs from the excluded `old`.
law span_reuse_holds:
  for -avoided: Maybe<&2, TC.SpanId>
  for reused: Bool
  for +id: TC.SpanId
  for +old: TC.SpanId
  for remaining: Nat
  for evidence: {TC.SpanId.is_eq(id, old) == reused : Bool}
  for valid: {Some{old} == avoided : Maybe<&2, TC.SpanId>}
  SpanHolds(avoided, TC.SpanDraw.reuse(reused, id, old, remaining))

def span_reuse_holds(avoided, reused, id, old, remaining, evidence, valid):
  match reused:
    case True{}:
      span_retry_holds(avoided, remaining, Some{old}, valid)
    case False{}:
      %valid : Laws.SpanAvoids(_, id)
      StringsProof.distinct(TC.SpanId.to_string(id), TC.SpanId.to_string(old), evidence)

# As trace_check_holds.
law span_check_holds:
  for -avoided: Maybe<&2, TC.SpanId>
  for candidate: Maybe<&2, TC.SpanId>
  for +excluded: Maybe<&2, TC.SpanId>
  for remaining: Nat
  for valid: {excluded == avoided : Maybe<&2, TC.SpanId>}
  SpanHolds(avoided, TC.SpanDraw.check(candidate, excluded, remaining))

def span_check_holds(avoided, candidate, excluded, remaining, valid):
  match candidate:
    case None{}:
      span_retry_holds(avoided, remaining, excluded, valid)
    case Some{+id}:
      match excluded:
        case None{}:
          %valid : Laws.SpanAvoids(_, id)
          Unit{}
        case Some{+old}:
          span_reuse_holds(avoided, TC.SpanId.is_eq(id, old), id, old, remaining, {==}, valid)

# As trace_take_holds: the second word of a candidate goes through
# span_check_holds.
law span_take_holds:
  for -avoided: Maybe<&2, TC.SpanId>
  for +word: U32
  for remaining: Nat
  for words: TC.SpanWords
  for +excluded: Maybe<&2, TC.SpanId>
  for valid: {excluded == avoided : Maybe<&2, TC.SpanId>}
  SpanHolds(avoided, TC.SpanDraw.take(word, remaining, words, excluded))

def span_take_holds(avoided, word, remaining, words, excluded, valid):
  match words:
    case TC.NoSpanWord{}:
      (Unit{}, valid)
    case TC.OneSpanWord{first}:
      span_check_holds(avoided, TC.SpanId.from_words(first, word), excluded, remaining, valid)

# As trace_kept, for span ID draws.
law span_kept:
  for +avoided: Maybe<&2, TC.SpanId>
  for draw: TC.SpanDraw
  for valid: SpanPending(avoided, draw)
  for word: Result<&1, &1, U32 & String, U32>
  SpanHolds(avoided, TC.SpanDraw.next(word, draw))

def span_kept(avoided, draw, valid, word):
  match draw:
    case TC.SpanDraw{remaining, words, excluded}:
      match word:
        case Fail{(code, message)}:
          Unit{}
        case Done{next}:
          span_take_holds(avoided, next, remaining, words, excluded, valid)

# The view of SpanDraw.run's result, as TraceRunView.
def SpanRunView(avoided: Maybe<&2, TC.SpanId>, result: Laws.TapeSpanStep()) -> Type:
  DriveProof.Ends(~TC.SpanStep, ~Maybe<&2, TC.SpanId>, ~SpanFinal, avoided, result)

# As trace_run_holds, for span ID draws.
law span_run_holds:
  for +avoided: Maybe<&2, TC.SpanId>
  for +fuel: Nat
  for +step: TC.SpanStep
  for tape: Laws.Tape()
  for valid: SpanHolds(avoided, step)
  SpanRunView(avoided, TC.SpanDraw.run(fuel, (tape, step)))

def span_run_holds(avoided, fuel, step, tape, valid):
  DriveProof.drive_keeps(~TC.SpanStep, ~TC.SpanDraw, ~TC.SpanStep.waiting, ~TC.SpanDraw.next, ~Maybe<&2, TC.SpanId>,
    ~SpanFinal, ~SpanPending, ~span_kept, avoided, fuel, step, TC.SpanStep.waiting(step), tape, valid)

# Span ID draws: the IO operation over a tape
# ===========================================

# As read_trace_tape, for span ID draws.
law read_span_tape:
  for -A: Type
  for -f: Laws.TapeSpanId() -> A
  for -g: Laws.TapeSpanId() -> A
  for same: @outcome: Laws.TapeSpanId() -> {f(outcome) == g(outcome) : A}
  for +fuel: Nat
  for tape: Laws.Tape()
  for +step: TC.SpanStep
  {TC.Drive.read(~TC.SpanStep, ~TC.SpanDraw, ~TC.SpanStep.waiting, ~TC.SpanDraw.next, ~Laws.Tape(), ~TC.Source.tape,
    fuel, (tape, (step, TC.SpanStep.waiting(step))))(A, done => Emit{f(TC.SpanDraw.outcome(Laws.Tape(), done))}) ==
    Emit{g(TC.SpanDraw.outcome(Laws.Tape(), TC.SpanDraw.run(fuel, (tape, step))))} : IO.OP<A>}

def read_span_tape(A, f, g, same, fuel, tape, step):
  DriveProof.drive_read(~TC.SpanStep, ~TC.SpanDraw, ~TC.SpanStep.waiting, ~TC.SpanDraw.next, A,
    done => f(TC.SpanDraw.outcome(Laws.Tape(), done)), done => g(TC.SpanDraw.outcome(Laws.Tape(), done)),
    done => same(TC.SpanDraw.outcome(Laws.Tape(), done)), fuel, (tape, (step, TC.SpanStep.waiting(step))))

# As read_trace_same, for a span ID draw's continuations.
law read_span_same:
  for -A: Type
  for -f: Laws.TapeSpanId() -> IO.OP<A>
  for -g: Laws.TapeSpanId() -> IO.OP<A>
  for same: @outcome: Laws.TapeSpanId() -> {f(outcome) == g(outcome) : IO.OP<A>}
  for +fuel: Nat
  for tape: Laws.Tape()
  for +step: TC.SpanStep
  {TC.Drive.read(~TC.SpanStep, ~TC.SpanDraw, ~TC.SpanStep.waiting, ~TC.SpanDraw.next, ~Laws.Tape(), ~TC.Source.tape,
    fuel, (tape, (step, TC.SpanStep.waiting(step))))(A, done => f(TC.SpanDraw.outcome(Laws.Tape(), done))) ==
    TC.Drive.read(~TC.SpanStep, ~TC.SpanDraw, ~TC.SpanStep.waiting, ~TC.SpanDraw.next, ~Laws.Tape(), ~TC.Source.tape,
      fuel, (tape, (step, TC.SpanStep.waiting(step))))(A, done => g(TC.SpanDraw.outcome(Laws.Tape(), done))) :
    IO.OP<A>}

def read_span_same(A, f, g, same, fuel, tape, step):
  DriveProof.drive_same(~TC.SpanStep, ~TC.SpanDraw, ~TC.SpanStep.waiting, ~TC.SpanDraw.next, A,
    done => f(TC.SpanDraw.outcome(Laws.Tape(), done)), done => g(TC.SpanDraw.outcome(Laws.Tape(), done)),
    done => same(TC.SpanDraw.outcome(Laws.Tape(), done)), fuel, (tape, (step, TC.SpanStep.waiting(step))))

# Compositions over a tape
# ========================
#
# Laws root_composed, child_composed and restart_composed: over a tape, the
# compositions that Context.root_with, child_with and restart_with run agree
# with those that LAWS.bend states. The continuations of the package
# (Draw.root_span_with, Draw.span_context) and those of LAWS.bend (root_of,
# context_of) are different definitions, which the checker compares only
# once the outcome they receive is known. read_trace_same and read_span_same
# carry an agreement on every outcome through the drivers, and
# root_span_same and span_context_same are those agreements. A root and a
# restart are the new trace of a plan (TracePlan), so one lemma,
# new_trace_composed, gives both of their laws.

# The package's context of a span ID outcome, Draw.span_context, is
# LAWS.bend's context_of, once the outcome is split.
law span_context_same:
  for -trace_id: TC.TraceId
  for -sampled: Bool
  for outcome: Laws.TapeSpanId()
  {Emit{TC.Draw.span_context(Laws.Tape(), trace_id, sampled, outcome)} ==
    Emit{Laws.context_of(trace_id, sampled, outcome)} : IO.OP<Laws.TapeOutcome()>}

def span_context_same(trace_id, sampled, outcome):
  match outcome:
    case Tuple{rest, Fail{error}}:
      {==}
    case Tuple{rest, Done{span_id}}:
      {==}

# What the package runs after a root's or a restart's trace ID,
# Draw.root_span_with, emits what LAWS.bend's root_of emits, for every
# sampled indication and every outcome of the trace ID: a failure at once,
# and otherwise the same span ID draw, that of the root's span plan, whose
# continuations agree by span_context_same.
law root_span_same:
  for +sampled: Bool
  for outcome: Laws.TapeTraceId()
  {TC.Draw.root_span_with(~Laws.Tape(), ~TC.Source.tape, sampled, outcome)(Laws.TapeOutcome(),
    value => Emit{value}) == Laws.root_of(sampled, outcome)(Laws.TapeOutcome(), value => Emit{value}) :
    IO.OP<Laws.TapeOutcome()>}

def root_span_same(sampled, outcome):
  match outcome:
    case Tuple{rest, Fail{error}}:
      {==}
    case Tuple{rest, Done{trace_id}}:
      read_span_same(Laws.TapeOutcome(), done => Emit{TC.Draw.span_context(Laws.Tape(), trace_id, sampled, done)},
        done => Emit{Laws.context_of(trace_id, sampled, done)}, done => span_context_same(trace_id, sampled, done),
        16n, rest, TC.SpanDraw.start(None{}))

# Laws root_composed and restart_composed: over a tape, the new trace of the
# plan of `excluded` and `sampled`, as TracePlan.generate_with runs it, is
# generating a trace ID that excludes `excluded`, then what LAWS.bend's
# root_of does with `sampled`: read_trace_same from the first trace ID
# candidate, with root_span_same on every outcome. Laws.root_composed applies
# it with nothing to exclude, the plan of a root, and Laws.restart_composed
# with the received trace ID, the plan of a restart.
law new_trace_composed:
  for tape: Laws.Tape()
  for +excluded: Maybe<&2, TC.TraceId>
  for +sampled: Bool
  {Laws.Observe(Laws.TapeOutcome(), TC.TracePlan.generate_with(~Laws.Tape(), ~TC.Source.tape, tape,
    TC.TracePlan{excluded, sampled})) ==
    Laws.Observe(Laws.TapeOutcome(), IO.bind(Laws.TapeTraceId(), Laws.TapeOutcome(),
      TC.TraceId.generate_with(~Laws.Tape(), ~TC.Source.tape, tape, excluded), traced => Laws.root_of(sampled, traced))) :
    IO.OP<Laws.TapeOutcome()>}

def new_trace_composed(tape, excluded, sampled):
  read_trace_same(Laws.TapeOutcome(),
    outcome => TC.Draw.root_span_with(~Laws.Tape(), ~TC.Source.tape, sampled, outcome)(Laws.TapeOutcome(),
      value => Emit{value}),
    outcome => Laws.root_of(sampled, outcome)(Laws.TapeOutcome(), value => Emit{value}),
    outcome => root_span_same(sampled, outcome), 32n, tape, TC.TraceDraw.start(excluded))
