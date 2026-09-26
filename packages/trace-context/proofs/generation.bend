# Proofs: the generation machine over tapes
# =========================================
#
# What generation does when its words come from a tape: the list of word
# results that a replayed source returns. The generation machine of
# trace_context.bend (Draw.feed, with the Draw.check_*, reuse_*, retry_* and
# accept_* functions that decide a candidate) is driven purely by Draw.run,
# which reads the tape with Tape.next, and as an IO action by Draw.read over
# Source.tape, as Context.root_with, child_with and restart_with do.
# PROOF.bend proves these laws of LAWS.bend with this module: root_tape,
# child_tape and restart_tape (the lemmas of the same names); root_ends,
# child_ends and restart_ends (run_ends with root_within, child_within and
# restart_within); generated_root, generated_child and generated_restart
# (root_run, child_run and restart_run, through the views RootRun, ChildRun
# and RestartRun). feed_failure, root_exhaustion and child_exhaustion need no
# lemma: PROOF.bend proves them by computation.
#
# The strategy, in reading order:
#
# - Termination. Within(step, n) says that a step ends within n more words,
#   whatever they are. The *_within lemmas follow the machine word by word
#   and candidate by candidate; SpanRetry and TraceRetry carry the bound of
#   the next candidate, the induction hypothesis on the candidates left.
#   run_ends turns a bound equal to the fuel into Draw.ended for every tape.
# - Created contexts. RootInv, ChildInv and RestartInv are invariants of the
#   machine's state, and the Created case of each is the conclusion of
#   generated_root, generated_child or generated_restart. Each holds of the
#   first step, every word keeps it (root_feed, child_feed, restart_feed),
#   and so does a whole drive (root_run, child_run, restart_run, by induction
#   on the fuel). Branches an invariant excludes are refuted through the
#   clash motives MaybeTraceClash and MaybeSpanClash.
# - IO. read_tape_then shows, by induction on the fuel, that Draw.read over
#   Source.tape computes Draw.run, whatever continuation follows it;
#   root_tape, child_tape and restart_tape apply it to the continuation of
#   Draw.finished.
#
# The statements use Tape, TapeStep, TapeOutcome and Observe of LAWS.bend,
# so each statement here is the statement of the law it proves.

import Base
import ../trace_context.bend as TC
import ./strings.bend as StringsProof
import ./bools.bend as BoolsProof
import ../LAWS.bend as Laws

# Word bounds
# ===========
#
# Within(step, n) states that a generation ends within n more words. The next
# three sections prove it for the first step of every generation.

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

# A bound can be loosened by one word: a step that ends within n words ends
# within 1 + n. Induction on n; within_four applies it four times.
law within_succ:
  for +n: Nat
  for +step: TC.Step
  for bound: Within(step, n)
  Within(step, 1n+n)

def within_succ(n, step, bound):
  match n:
    case 0n:
      match step:
        case TC.Created{context}:
          Unit{}
        case TC.Failed{error}:
          Unit{}
        case TC.NeedWord{draw}:
          Empty.absurd(Within(TC.NeedWord{draw}, 1n), bound)
    case 1n+p:
      match step:
        case TC.Created{context}:
          Unit{}
        case TC.Failed{error}:
          Unit{}
        case TC.NeedWord{+draw}:
          +word => within_succ(p, TC.Draw.feed(Done{word}, draw), bound(word))

# A bound can be loosened by four words, the length of a trace ID candidate.
# lift_span_bound uses it once per candidate.
law within_four:
  for +n: Nat
  for +step: TC.Step
  for bound: Within(step, n)
  Within(step, 4n+n)

def within_four(n, step, bound):
  within_succ(3n+n, step, within_succ(2n+n, step, within_succ(1n+n, step, within_succ(n, step, bound))))

# Span ID draws
# =============
#
# A span ID draw reads two words per candidate, for at most eight
# candidates. The lemmas go backwards through a candidate: its decision
# (retry, accept, reuse, check), its second word, then its start.

# The words a span ID draw may still read when it starts a candidate with
# `remaining` further candidates allowed: two for each of the 1 + remaining
# candidates. span_budget(7n) is 16, the word budget of a child.
def span_budget(remaining: Nat) -> Nat:
  match remaining:
    case 0n:
      2n
    case 1n+p:
      2n+span_budget(p)

# The words a span ID draw may still read once a candidate is complete: two
# for each further candidate allowed. None are left after the last one, which
# is accepted or exhausts the draw.
def span_after(remaining: Nat) -> Nat:
  match remaining:
    case 0n:
      0n
    case 1n+p:
      span_budget(p)

# The bound the span ID lemmas assume for a retry, the induction hypothesis
# on the candidates left: nothing when no further candidate is allowed (a
# retry fails with ExhaustedSpanId), and otherwise the bound of the fresh
# draw that a retry starts. span_start_within supplies it by recursion.
def SpanRetry(+remaining: Nat, plan: TC.SpanPlan) -> Type:
  match remaining:
    case 0n:
      Unit
    case 1n+p:
      Within(TC.NeedWord{TC.DrawSpan{p, TC.NoSpanWord{}, plan}}, span_budget(p))

# Retrying a span ID candidate leaves the draw within span_after(remaining)
# words, given `retry`: an exhausted draw has failed, and otherwise the retry
# is the fresh draw that `retry` bounds.
law span_retry_within:
  for +remaining: Nat
  for +plan: TC.SpanPlan
  for retry: SpanRetry(remaining, plan)
  Within(TC.Draw.retry_span(remaining, plan), span_after(remaining))

def span_retry_within(remaining, plan, retry):
  match remaining:
    case 0n:
      Unit{}
    case 1n+p:
      retry

# Accepting a span ID candidate ends the generation with a context, so every
# bound holds.
law span_accept_within:
  for -id: TC.SpanId
  for +plan: TC.SpanPlan
  for -remaining: Nat
  Within(TC.Draw.accept_span(id, plan), span_after(remaining))

# Splits the plan so that Draw.accept_span computes to Created.
def span_accept_within(id, plan, remaining):
  match plan:
    case TC.SpanPlan{trace_id, sampled, parent}:
      Unit{}

# Deciding a span ID candidate by `reused`, its comparison with the excluded
# span ID, leaves the draw within span_after(remaining) words given `retry`,
# whichever way it went: a reused candidate is retried, any other accepted.
law span_reuse_within:
  for reused: Bool
  for -id: TC.SpanId
  for +plan: TC.SpanPlan
  for +remaining: Nat
  for retry: SpanRetry(remaining, plan)
  Within(TC.Draw.reuse_span(reused, id, plan, remaining), span_after(remaining))

def span_reuse_within(reused, id, plan, remaining, retry):
  match reused:
    case True{}:
      span_retry_within(remaining, plan, retry)
    case False{}:
      span_accept_within(id, plan, remaining)

# Checking a complete span ID candidate, whatever it is, leaves the draw
# within span_after(remaining) words, given `retry`. The cases follow
# Draw.check_span: zero is retried, and a nonzero candidate is accepted or,
# when the plan excludes a span ID (a child's does), compared with it.
law span_check_within:
  for candidate: Maybe<&2, TC.SpanId>
  for +plan: TC.SpanPlan
  for +remaining: Nat
  for retry: SpanRetry(remaining, plan)
  Within(TC.Draw.check_span(candidate, plan, remaining), span_after(remaining))

def span_check_within(candidate, plan, remaining, retry):
  match candidate:
    case None{}:
      span_retry_within(remaining, plan, retry)
    case Some{+id}:
      match plan:
        case TC.SpanPlan{+trace_id, +sampled, None{}}:
          span_accept_within(id, TC.SpanPlan{trace_id, sampled, None{}}, remaining)
        case TC.SpanPlan{+trace_id, +sampled, Some{+old}}:
          span_reuse_within(TC.SpanId.is_eq(id, old), id, TC.SpanPlan{trace_id, sampled, Some{old}},
            remaining, retry)

# A span ID draw holding the first word of a candidate ends within one word
# more than span_after(remaining), given `retry`: whatever the second word,
# it completes the candidate, which Draw.check_span decides. The proof is a
# function of that second word.
law span_second_within:
  for +remaining: Nat
  for +plan: TC.SpanPlan
  for retry: SpanRetry(remaining, plan)
  for +first: U32
  Within(TC.NeedWord{TC.DrawSpan{remaining, TC.OneSpanWord{first}, plan}}, 1n+span_after(remaining))

def span_second_within(remaining, plan, retry, first):
  +second => span_check_within(TC.SpanId.from_words(first, second), plan, remaining, retry)

# A span ID draw at the start of a candidate, with `remaining` further
# candidates allowed, ends within span_budget(remaining) words, for every
# plan and every sequence of words. Induction on remaining: the bound for
# one candidate fewer is the `retry` of the lemmas above. child_within and
# trace_accept_within use it with remaining 7n, which gives 16 words.
law span_start_within:
  for +remaining: Nat
  for +plan: TC.SpanPlan
  Within(TC.NeedWord{TC.DrawSpan{remaining, TC.NoSpanWord{}, plan}}, span_budget(remaining))

def span_start_within(remaining, plan):
  match remaining:
    case 0n:
      +first => span_second_within(0n, plan, Unit{}, first)
    case 1n+p:
      +first => span_second_within(1n+p, plan, span_start_within(p, plan), first)

# Trace ID draws
# ==============
#
# A trace ID draw reads four words per candidate, for at most eight
# candidates, and an accepted trace ID starts a span ID draw. The lemmas go
# backwards through a candidate, as for span IDs.

# The words a trace ID draw may still read when it starts a candidate with
# `remaining` further candidates allowed: four for each of the 1 + remaining
# candidates, then the 16 of the span ID draw that follows an accepted trace
# ID. trace_budget(7n) is 48, the word budget of a root and of a restart.
def trace_budget(remaining: Nat) -> Nat:
  match remaining:
    case 0n:
      20n
    case 1n+p:
      4n+trace_budget(p)

# The words a trace ID draw may still read once a candidate is complete: four
# for each further candidate allowed, then the 16 of the span ID draw. After
# the last candidate only the span ID draw is left.
def trace_after(remaining: Nat) -> Nat:
  match remaining:
    case 0n:
      16n
    case 1n+p:
      trace_budget(p)

# The bound the trace ID lemmas assume for a retry, as SpanRetry does for
# span IDs: nothing when no further candidate is allowed (a retry fails with
# ExhaustedTraceId), and otherwise the bound of the fresh draw that a retry
# starts. trace_start_within supplies it by recursion.
def TraceRetry(+remaining: Nat, previous: Maybe<&2, TC.TraceId>) -> Type:
  match remaining:
    case 0n:
      Unit
    case 1n+p:
      Within(TC.NeedWord{TC.DrawTrace{p, TC.NoTraceWord{}, previous}}, trace_budget(p))

# Every trace budget covers the sixteen words of a span ID draw: a step that
# ends within 16 words ends within trace_budget(remaining), for every
# remaining. trace_accept_within uses it for a candidate that was not the
# last allowed. Induction on remaining, four words at a time (within_four).
law lift_span_bound:
  for +remaining: Nat
  for +step: TC.Step
  for bound: Within(step, 16n)
  Within(step, trace_budget(remaining))

def lift_span_bound(remaining, step, bound):
  match remaining:
    case 0n:
      within_four(16n, step, bound)
    case 1n+p:
      within_four(trace_budget(p), step, lift_span_bound(p, step, bound))

# Accepting a trace ID candidate leaves the generation within
# trace_after(remaining) words: the span ID draw it starts ends within 16
# words (span_start_within), which fits every trace budget (lift_span_bound).
law trace_accept_within:
  for +remaining: Nat
  for +trace_id: TC.TraceId
  Within(TC.Draw.accept_trace(trace_id), trace_after(remaining))

def trace_accept_within(remaining, trace_id):
  match remaining:
    case 0n:
      span_start_within(7n, TC.SpanPlan{trace_id, False{}, None{}})
    case 1n+p:
      lift_span_bound(p, TC.Draw.accept_trace(trace_id), span_start_within(7n, TC.SpanPlan{trace_id, False{}, None{}}))

# Retrying a trace ID candidate leaves the draw within trace_after(remaining)
# words, given `retry`, as span_retry_within shows for span IDs.
law trace_retry_within:
  for +remaining: Nat
  for +previous: Maybe<&2, TC.TraceId>
  for retry: TraceRetry(remaining, previous)
  Within(TC.Draw.retry_trace(remaining, previous), trace_after(remaining))

def trace_retry_within(remaining, previous, retry):
  match remaining:
    case 0n:
      Unit{}
    case 1n+p:
      retry

# Deciding a trace ID candidate by `reused`, its comparison with the received
# trace ID, leaves the draw within trace_after(remaining) words given
# `retry`, whichever way it went: a reused candidate is retried, any other
# accepted.
law trace_reuse_within:
  for reused: Bool
  for +id: TC.TraceId
  for +previous: TC.TraceId
  for +remaining: Nat
  for retry: TraceRetry(remaining, Some{previous})
  Within(TC.Draw.reuse_trace(reused, id, previous, remaining), trace_after(remaining))

def trace_reuse_within(reused, id, previous, remaining, retry):
  match reused:
    case True{}:
      trace_retry_within(remaining, Some{previous}, retry)
    case False{}:
      trace_accept_within(remaining, id)

# Checking a complete trace ID candidate, whatever it is, leaves the draw
# within trace_after(remaining) words, given `retry`. The cases follow
# Draw.check_trace: zero is retried, and a nonzero candidate is accepted or,
# when the draw has a received trace ID (a restart's does), compared with it.
law trace_check_within:
  for candidate: Maybe<&2, TC.TraceId>
  for +previous: Maybe<&2, TC.TraceId>
  for +remaining: Nat
  for retry: TraceRetry(remaining, previous)
  Within(TC.Draw.check_trace(candidate, previous, remaining), trace_after(remaining))

def trace_check_within(candidate, previous, remaining, retry):
  match candidate:
    case None{}:
      trace_retry_within(remaining, previous, retry)
    case Some{+id}:
      match previous:
        case None{}:
          trace_accept_within(remaining, id)
        case Some{+old}:
          trace_reuse_within(TC.TraceId.is_eq(id, old), id, old, remaining, retry)

# A trace ID draw holding three words of a candidate ends within one word
# more than trace_after(remaining), given `retry`: whatever the fourth word,
# it completes the candidate, which Draw.check_trace decides. The proof is a
# function of that fourth word.
law trace_fourth_within:
  for +remaining: Nat
  for +previous: Maybe<&2, TC.TraceId>
  for retry: TraceRetry(remaining, previous)
  for +first: U32
  for +second: U32
  for +third: U32
  Within(TC.NeedWord{TC.DrawTrace{remaining, TC.ThreeTraceWords{first, second, third}, previous}},
    1n+trace_after(remaining))

def trace_fourth_within(remaining, previous, retry, first, second, third):
  +fourth => trace_check_within(TC.Draw.asserted(TC.TraceId.from_words(first, second, third, fourth)), previous,
    remaining, retry)

# A trace ID draw holding two words of a candidate ends within two words
# more than trace_after(remaining), given `retry`, whatever the third word.
law trace_third_within:
  for +remaining: Nat
  for +previous: Maybe<&2, TC.TraceId>
  for retry: TraceRetry(remaining, previous)
  for +first: U32
  for +second: U32
  Within(TC.NeedWord{TC.DrawTrace{remaining, TC.TwoTraceWords{first, second}, previous}},
    2n+trace_after(remaining))

def trace_third_within(remaining, previous, retry, first, second):
  +third => trace_fourth_within(remaining, previous, retry, first, second, third)

# A trace ID draw holding one word of a candidate ends within three words
# more than trace_after(remaining), given `retry`, whatever the second word.
law trace_second_within:
  for +remaining: Nat
  for +previous: Maybe<&2, TC.TraceId>
  for retry: TraceRetry(remaining, previous)
  for +first: U32
  Within(TC.NeedWord{TC.DrawTrace{remaining, TC.OneTraceWord{first}, previous}}, 3n+trace_after(remaining))

def trace_second_within(remaining, previous, retry, first):
  +second => trace_third_within(remaining, previous, retry, first, second)

# A trace ID draw at the start of a candidate, with `remaining` further
# candidates allowed, ends within trace_budget(remaining) words, for every
# `previous` and every sequence of words. Induction on remaining, as for
# span_start_within. root_within and restart_within use it with 7n.
law trace_start_within:
  for +remaining: Nat
  for +previous: Maybe<&2, TC.TraceId>
  Within(TC.NeedWord{TC.DrawTrace{remaining, TC.NoTraceWord{}, previous}}, trace_budget(remaining))

def trace_start_within(remaining, previous):
  match remaining:
    case 0n:
      +first => trace_second_within(0n, previous, Unit{}, first)
    case 1n+p:
      +first => trace_second_within(1n+p, previous, trace_start_within(p, previous), first)

# Every generation ends
# =====================
#
# The bounds of the first step of a root, a restart and a child, and
# run_ends, which turns such a bound into the end of Draw.run (laws
# root_ends, restart_ends and child_ends). ended_stays and run_failed show
# that Draw.run keeps an ended step ended and a failed one unchanged.

# A root generation ends within 48 words, whatever they are: the bound that
# Laws.root_ends passes to run_ends.
law root_within:
  Within(TC.Draw.root(), 48n)

def root_within():
  trace_start_within(7n, None{})

# A restart ends within 48 words, whatever they are: the bound that
# Laws.restart_ends passes to run_ends.
law restart_within:
  for previous: TC.RemoteContext
  Within(TC.Draw.restart(previous), 48n)

def restart_within(previous):
  trace_start_within(7n, Some{TC.RemoteContext.trace_id(previous)})

# A child generation ends within 16 words, whatever they are: the bound that
# Laws.child_ends passes to run_ends.
law child_within:
  for +parent: TC.Parent
  for sampling: TC.Sampling
  Within(TC.Draw.child(parent, sampling), 16n)

def child_within(parent, sampling):
  span_start_within(7n, TC.SpanPlan{TC.Parent.trace_id(parent),
    TC.Sampling.resolve(sampling, TC.Parent.is_sampled(parent)), Some{TC.Parent.span_id(parent)}})

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
# RestartInv below) whose Created case is the law's conclusion. A branch
# that an invariant excludes comes with a hypothesis that proves Empty, and
# Empty.absurd turns Empty into any goal. This section holds the shared
# tools: motives that refute a present ID equal to an absent one, and the
# randomness of trace ID candidates (for roots and restarts).

# The motive that tells a present trace ID from an absent one: Empty for
# None{} and Unit for Some{id}. Rewriting a clash {Some{id} == None{}}
# through it turns the goal Empty into Unit (trace_some_ne_none).
def MaybeTraceClash(value: Maybe<&2, TC.TraceId>) -> Type:
  match value:
    case None{}:
      Empty
    case Some{id}:
      Unit

# A present trace ID never equals an absent one: the equation proves Empty.
# root_check_trace uses it, because a root's trace ID draw has no received
# trace ID; trace_none_ne_some states it the other way round.
law trace_some_ne_none:
  for -id: TC.TraceId
  for clash: {Some{id} == None{} : Maybe<&2, TC.TraceId>}
  Empty

def trace_some_ne_none(id, clash):
  %clash : MaybeTraceClash(_)
  Unit{}

# The same motive for span IDs: Empty for None{} and Unit for Some{id}
# (span_some_ne_none).
def MaybeSpanClash(value: Maybe<&2, TC.SpanId>) -> Type:
  match value:
    case None{}:
      Empty
    case Some{id}:
      Unit

# A present span ID never equals an absent one. root_check_span and
# restart_check_span use it, because a root's or a restart's span plan
# excludes no span ID; span_none_ne_some states it the other way round.
law span_some_ne_none:
  for -id: TC.SpanId
  for clash: {Some{id} == None{} : Maybe<&2, TC.SpanId>}
  Empty

def span_some_ne_none(id, clash):
  %clash : MaybeSpanClash(_)
  Unit{}

# The view "this trace ID candidate asserts random-trace-id": Unit for None{}
# (a zero candidate, which is retried) and, for Some{id}, the equation that
# id is random. root_check_trace and restart_check_trace take it as a
# hypothesis about the candidate they check.
def RandomCandidate(candidate: Maybe<&2, TC.TraceId>) -> Type:
  match candidate:
    case None{}:
      Unit
    case Some{id}:
      {TC.TraceId.is_random(id) == True{} : Bool}

# Every trace ID candidate that generation checks asserts random-trace-id:
# Draw.asserted, which Draw.feed applies to each complete candidate, sets
# the assertion on every present one. root_feed and restart_feed use it when
# the fourth word completes a candidate.
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

# Roots
# =====
#
# A root's trace ID draw has no received trace ID to avoid; its span ID draw
# keeps a random trace ID, sampled False and no excluded span ID.

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

# When a root's trace ID draw has no received trace ID (`none`), retrying its
# candidate keeps the invariant: the fresh draw has none either, and an
# exhausted draw has failed.
law root_retry_trace:
  for remaining: Nat
  for -previous: Maybe<&2, TC.TraceId>
  for none: {previous == None{} : Maybe<&2, TC.TraceId>}
  RootInv(TC.Draw.retry_trace(remaining, previous))

def root_retry_trace(remaining, previous, none):
  match remaining:
    case 0n:
      Unit{}
    case 1n+p:
      none

# When a root's trace ID draw has no received trace ID (`none`) and its
# complete candidate asserts random-trace-id (`random`), checking the
# candidate keeps the invariant. An accepted candidate starts the span ID
# draw with a RootPlan; a received trace ID is ruled out with
# trace_some_ne_none.
law root_check_trace:
  for candidate: Maybe<&2, TC.TraceId>
  for +previous: Maybe<&2, TC.TraceId>
  for remaining: Nat
  for none: {previous == None{} : Maybe<&2, TC.TraceId>}
  for random: RandomCandidate(candidate)
  RootInv(TC.Draw.check_trace(candidate, previous, remaining))

def root_check_trace(candidate, previous, remaining, none, random):
  match candidate:
    case None{}:
      root_retry_trace(remaining, previous, none)
    case Some{+id}:
      match previous:
        case None{}:
          (random, ({==}, {==}))
        case Some{+old}:
          Empty.absurd(RootInv(TC.Draw.reuse_trace(TC.TraceId.is_eq(id, old), id, old, remaining)),
            trace_some_ne_none(old, none))

# When a root's span ID draw keeps a RootPlan (`valid`), retrying its
# candidate keeps the invariant: the fresh draw keeps the plan, and an
# exhausted draw has failed.
law root_retry_span:
  for remaining: Nat
  for -plan: TC.SpanPlan
  for valid: RootPlan(plan)
  RootInv(TC.Draw.retry_span(remaining, plan))

def root_retry_span(remaining, plan, valid):
  match remaining:
    case 0n:
      Unit{}
    case 1n+p:
      valid

# When a root's span ID draw keeps a RootPlan (`valid`), checking its
# complete candidate keeps the invariant: an accepted candidate creates a
# context with the plan's random trace ID and sampled False. A plan that
# excludes a span ID contradicts RootPlan and is ruled out with
# span_some_ne_none.
law root_check_span:
  for candidate: Maybe<&2, TC.SpanId>
  for +plan: TC.SpanPlan
  for remaining: Nat
  for valid: RootPlan(plan)
  RootInv(TC.Draw.check_span(candidate, plan, remaining))

def root_check_span(candidate, plan, remaining, valid):
  match candidate:
    case None{}:
      root_retry_span(remaining, plan, valid)
    case Some{+id}:
      match plan:
        case TC.SpanPlan{+trace_id, +sampled, None{}}:
          (random, rest) = valid
          (unsampled, none) = rest
          (random, unsampled)
        case TC.SpanPlan{+trace_id, +sampled, Some{+old}}:
          (random, rest) = valid
          (unsampled, none) = rest
          Empty.absurd(RootInv(TC.Draw.reuse_span(TC.SpanId.is_eq(id, old), id,
            TC.SpanPlan{trace_id, sampled, Some{old}}, remaining)), span_some_ne_none(old, none))

# When RootInv holds of a step that needs a word, it holds after feeding any
# word. The cases follow Draw.feed: a word that only extends a candidate
# changes nothing the invariant speaks of, the fourth trace word goes through
# root_check_trace (its candidate is random by asserted_random), and the
# second span word through root_check_span.
law root_feed:
  for +word: U32
  for draw: TC.Draw
  for valid: RootInv(TC.NeedWord{draw})
  RootInv(TC.Draw.feed(Done{word}, draw))

def root_feed(word, draw, valid):
  match draw:
    case TC.DrawTrace{remaining, TC.NoTraceWord{}, previous}:
      valid
    case TC.DrawTrace{remaining, TC.OneTraceWord{first}, previous}:
      valid
    case TC.DrawTrace{remaining, TC.TwoTraceWords{first, second}, previous}:
      valid
    case TC.DrawTrace{remaining, TC.ThreeTraceWords{+first, +second, +third}, +previous}:
      root_check_trace(TC.Draw.asserted(TC.TraceId.from_words(first, second, third, word)), previous, remaining,
        valid, asserted_random(TC.TraceId.from_words(first, second, third, word)))
    case TC.DrawSpan{remaining, TC.NoSpanWord{}, plan}:
      valid
    case TC.DrawSpan{remaining, TC.OneSpanWord{first}, +plan}:
      root_check_span(TC.SpanId.from_words(first, word), plan, remaining, valid)

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
# the resolved sampled indication and the parent's span ID as the one not
# to reuse.

# An absent span ID never equals a present one: span_some_ne_none with the
# equation turned around. child_check_span uses it: a child's plan always
# excludes the parent's span ID, so a plan that excludes none is impossible.
law span_none_ne_some:
  for -id: TC.SpanId
  for clash: {None{} == Some{id} : Maybe<&2, TC.SpanId>}
  Empty

def span_none_ne_some(id, clash):
  span_some_ne_none(id, Equal.sym(Maybe<&2, TC.SpanId>, None{}, Some{id}, clash))

# Some is injective: when Some{old} equals Some{other}, old equals other.
# span_distinct uses it to read the parent's span ID out of the plan's
# excluded field.
law span_some_injective:
  for +old: TC.SpanId
  for -other: TC.SpanId
  for same: {Some{old} == Some{other} : Maybe<&2, TC.SpanId>}
  {old == other : TC.SpanId}

# Equal.cong with Maybe.default, which takes the ID out of both sides.
def span_some_injective(old, other, same):
  Equal.cong(Maybe<&2, TC.SpanId>, TC.SpanId, value => Maybe.default(&2, TC.SpanId, value, old),
    Some{old}, Some{other}, same)

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

# When a child's span ID draw keeps a ChildPlan (`valid`), retrying its
# candidate keeps the invariant: the fresh draw keeps the plan, and an
# exhausted draw has failed.
law child_retry_span:
  for -parent: TC.Parent
  for -sampling: TC.Sampling
  for remaining: Nat
  for -plan: TC.SpanPlan
  for valid: ChildPlan(parent, sampling, plan)
  ChildInv(parent, sampling, TC.Draw.retry_span(remaining, plan))

def child_retry_span(parent, sampling, remaining, plan, valid):
  match remaining:
    case 0n:
      Unit{}
    case 1n+p:
      valid

# A span ID that compares unequal to the excluded one differs from the
# parent's: when SpanId.is_eq(id, old) is False and Some{old} equals
# Some{other}, the digits of id and other differ. child_reuse_span uses it
# with the plan's excluded span ID as old and the parent's as other.
law span_distinct:
  for +id: TC.SpanId
  for +old: TC.SpanId
  for -other: TC.SpanId
  for different: {TC.SpanId.is_eq(id, old) == False{} : Bool}
  for same: {Some{old} == Some{other} : Maybe<&2, TC.SpanId>}
  {TC.SpanId.to_string(id) != TC.SpanId.to_string(other) : String}

# Rewrites other into old; StringsProof.distinct then reads the comparison.
def span_distinct(id, old, other, different, same):
  %span_some_injective(old, other, same) : {TC.SpanId.to_string(id) != TC.SpanId.to_string(_) : String}
  StringsProof.distinct(TC.SpanId.to_string(id), TC.SpanId.to_string(old), different)

# When a child's span ID draw keeps a ChildPlan with the excluded span ID
# `old`, deciding its candidate `id` keeps the invariant. `reused` is the
# result of SpanId.is_eq(id, old), passed as a Bool with the equation
# `evidence` because `match` inspects only variables: matching on `reused`
# refines `evidence`. A reused candidate is retried; an accepted one differs
# from the parent's span ID by span_distinct.
law child_reuse_span:
  for +parent: TC.Parent
  for -sampling: TC.Sampling
  for reused: Bool
  for +id: TC.SpanId
  for -trace_id: TC.TraceId
  for -sampled: Bool
  for +old: TC.SpanId
  for remaining: Nat
  for evidence: {TC.SpanId.is_eq(id, old) == reused : Bool}
  for valid: ChildPlan(parent, sampling, TC.SpanPlan{trace_id, sampled, Some{old}})
  ChildInv(parent, sampling, TC.Draw.reuse_span(reused, id, TC.SpanPlan{trace_id, sampled, Some{old}}, remaining))

def child_reuse_span(parent, sampling, reused, id, trace_id, sampled, old, remaining, evidence, valid):
  match reused:
    case True{}:
      child_retry_span(parent, sampling, remaining, TC.SpanPlan{trace_id, sampled, Some{old}}, valid)
    case False{}:
      (same_trace, rest) = valid
      (same_sampled, excluded) = rest
      (same_trace, (same_sampled, span_distinct(id, old, TC.Parent.span_id(parent), evidence, excluded)))

# When a child's span ID draw keeps a ChildPlan (`valid`), checking its
# complete candidate keeps the invariant. A plan with no span ID to exclude
# contradicts ChildPlan and is ruled out with span_none_ne_some; otherwise
# child_reuse_span decides the candidate.
law child_check_span:
  for +parent: TC.Parent
  for -sampling: TC.Sampling
  for candidate: Maybe<&2, TC.SpanId>
  for +plan: TC.SpanPlan
  for remaining: Nat
  for valid: ChildPlan(parent, sampling, plan)
  ChildInv(parent, sampling, TC.Draw.check_span(candidate, plan, remaining))

def child_check_span(parent, sampling, candidate, plan, remaining, valid):
  match candidate:
    case None{}:
      child_retry_span(parent, sampling, remaining, plan, valid)
    case Some{+id}:
      match plan:
        case TC.SpanPlan{+trace_id, +sampled, None{}}:
          (same_trace, rest) = valid
          (same_sampled, excluded) = rest
          Empty.absurd(ChildInv(parent, sampling, TC.Draw.accept_span(id, TC.SpanPlan{trace_id, sampled, None{}})),
            span_none_ne_some(TC.Parent.span_id(parent), excluded))
        case TC.SpanPlan{+trace_id, +sampled, Some{+old}}:
          child_reuse_span(parent, sampling, TC.SpanId.is_eq(id, old), id, trace_id, sampled, old,
            remaining, {==}, valid)

# When ChildInv holds of a step that needs a word, it holds after feeding
# any word. A trace ID draw is ruled out, since its invariant is Empty; the
# second word of a span ID candidate goes through child_check_span.
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
    case TC.DrawSpan{remaining, TC.NoSpanWord{}, plan}:
      valid
    case TC.DrawSpan{remaining, TC.OneSpanWord{first}, +plan}:
      child_check_span(parent, sampling, TC.SpanId.from_words(first, word), plan, remaining, valid)

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
# A restart's trace ID draw keeps the received trace ID to avoid. Its span ID
# draw keeps a trace ID that differs from the received one and asserts
# random-trace-id, with the root defaults: sampled False and no span ID to
# exclude.

# An absent trace ID never equals a present one: trace_some_ne_none with the
# equation turned around. restart_check_trace uses it: a restart's trace ID
# draw always has the received trace ID, so a draw without one is impossible.
law trace_none_ne_some:
  for -id: TC.TraceId
  for clash: {None{} == Some{id} : Maybe<&2, TC.TraceId>}
  Empty

def trace_none_ne_some(id, clash):
  trace_some_ne_none(id, Equal.sym(Maybe<&2, TC.TraceId>, None{}, Some{id}, clash))

# Some is injective for trace IDs: when Some{old} equals Some{other}, old
# equals other. trace_distinct uses it.
law trace_some_injective:
  for +old: TC.TraceId
  for -other: TC.TraceId
  for same: {Some{old} == Some{other} : Maybe<&2, TC.TraceId>}
  {old == other : TC.TraceId}

# Equal.cong with Maybe.default, which takes the ID out of both sides.
def trace_some_injective(old, other, same):
  Equal.cong(Maybe<&2, TC.TraceId>, TC.TraceId, value => Maybe.default(&2, TC.TraceId, value, old),
    Some{old}, Some{other}, same)

# A trace ID that compares unequal to the received one differs from it: when
# TraceId.is_eq(id, old) is False and Some{old} equals Some{other}, the
# digits of id and other differ. restart_reuse_trace uses it with the draw's
# received trace ID as old and that of the previous context as other.
law trace_distinct:
  for +id: TC.TraceId
  for +old: TC.TraceId
  for -other: TC.TraceId
  for different: {TC.TraceId.is_eq(id, old) == False{} : Bool}
  for same: {Some{old} == Some{other} : Maybe<&2, TC.TraceId>}
  {TC.TraceId.to_string(id) != TC.TraceId.to_string(other) : String}

# As span_distinct: rewrites other into old, then StringsProof.distinct.
def trace_distinct(id, old, other, different, same):
  %trace_some_injective(old, other, same) : {TC.TraceId.to_string(id) != TC.TraceId.to_string(_) : String}
  StringsProof.distinct(TC.TraceId.to_string(id), TC.TraceId.to_string(old), different)

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
# trace ID of `previous` as the received one to avoid, a span ID draw keeps
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

# When a restart's trace ID draw keeps the received trace ID (`valid`),
# retrying its candidate keeps the invariant: the fresh draw keeps it too,
# and an exhausted draw has failed.
law restart_retry_trace:
  for -previous: TC.RemoteContext
  for remaining: Nat
  for -received: Maybe<&2, TC.TraceId>
  for valid: {received == Some{TC.RemoteContext.trace_id(previous)} : Maybe<&2, TC.TraceId>}
  RestartInv(previous, TC.Draw.retry_trace(remaining, received))

def restart_retry_trace(previous, remaining, received, valid):
  match remaining:
    case 0n:
      Unit{}
    case 1n+p:
      valid

# When a restart's trace ID draw keeps the received trace ID `old` (`valid`)
# and the candidate `id` asserts random-trace-id (`random`), deciding the
# candidate keeps the invariant. As in child_reuse_span, `reused` is the
# result of TraceId.is_eq(id, old), with the equation `evidence`. A reused
# candidate is retried; an accepted one differs from the received trace ID
# by trace_distinct.
law restart_reuse_trace:
  for +previous: TC.RemoteContext
  for reused: Bool
  for +id: TC.TraceId
  for +old: TC.TraceId
  for remaining: Nat
  for evidence: {TC.TraceId.is_eq(id, old) == reused : Bool}
  for valid: {Some{old} == Some{TC.RemoteContext.trace_id(previous)} : Maybe<&2, TC.TraceId>}
  for random: {TC.TraceId.is_random(id) == True{} : Bool}
  RestartInv(previous, TC.Draw.reuse_trace(reused, id, old, remaining))

def restart_reuse_trace(previous, reused, id, old, remaining, evidence, valid, random):
  match reused:
    case True{}:
      restart_retry_trace(previous, remaining, Some{old}, valid)
    case False{}:
      (trace_distinct(id, old, TC.RemoteContext.trace_id(previous), evidence, valid), (random, ({==}, {==})))

# When a restart's trace ID draw keeps the received trace ID (`valid`) and
# its complete candidate asserts random-trace-id (`random`), checking the
# candidate keeps the invariant. A draw without a received trace ID
# contradicts `valid` and is ruled out with trace_none_ne_some; otherwise
# restart_reuse_trace decides the candidate.
law restart_check_trace:
  for +previous: TC.RemoteContext
  for candidate: Maybe<&2, TC.TraceId>
  for +received: Maybe<&2, TC.TraceId>
  for remaining: Nat
  for valid: {received == Some{TC.RemoteContext.trace_id(previous)} : Maybe<&2, TC.TraceId>}
  for random: RandomCandidate(candidate)
  RestartInv(previous, TC.Draw.check_trace(candidate, received, remaining))

def restart_check_trace(previous, candidate, received, remaining, valid, random):
  match candidate:
    case None{}:
      restart_retry_trace(previous, remaining, received, valid)
    case Some{+id}:
      match received:
        case None{}:
          Empty.absurd(RestartInv(previous, TC.Draw.accept_trace(id)),
            trace_none_ne_some(TC.RemoteContext.trace_id(previous), valid))
        case Some{+old}:
          restart_reuse_trace(previous, TC.TraceId.is_eq(id, old), id, old, remaining, {==}, valid, random)

# When a restart's span ID draw keeps a RestartPlan (`valid`), retrying its
# candidate keeps the invariant: the fresh draw keeps the plan, and an
# exhausted draw has failed.
law restart_retry_span:
  for -previous: TC.RemoteContext
  for remaining: Nat
  for -plan: TC.SpanPlan
  for valid: RestartPlan(previous, plan)
  RestartInv(previous, TC.Draw.retry_span(remaining, plan))

def restart_retry_span(previous, remaining, plan, valid):
  match remaining:
    case 0n:
      Unit{}
    case 1n+p:
      valid

# When a restart's span ID draw keeps a RestartPlan (`valid`), checking its
# complete candidate keeps the invariant: an accepted candidate creates a
# context with the plan's trace ID and sampled False. A plan that excludes a
# span ID contradicts RestartPlan and is ruled out with span_some_ne_none.
law restart_check_span:
  for +previous: TC.RemoteContext
  for candidate: Maybe<&2, TC.SpanId>
  for +plan: TC.SpanPlan
  for remaining: Nat
  for valid: RestartPlan(previous, plan)
  RestartInv(previous, TC.Draw.check_span(candidate, plan, remaining))

def restart_check_span(previous, candidate, plan, remaining, valid):
  match candidate:
    case None{}:
      restart_retry_span(previous, remaining, plan, valid)
    case Some{+id}:
      match plan:
        case TC.SpanPlan{+trace_id, +sampled, None{}}:
          (distinct, rest) = valid
          (random, more) = rest
          (unsampled, none) = more
          (distinct, (random, unsampled))
        case TC.SpanPlan{+trace_id, +sampled, Some{+old}}:
          (distinct, rest) = valid
          (random, more) = rest
          (unsampled, none) = more
          Empty.absurd(RestartInv(previous, TC.Draw.reuse_span(TC.SpanId.is_eq(id, old), id,
            TC.SpanPlan{trace_id, sampled, Some{old}}, remaining)), span_some_ne_none(old, none))

# When RestartInv holds of a step that needs a word, it holds after feeding
# any word, with the same cases as root_feed: the fourth trace word goes
# through restart_check_trace and the second span word through
# restart_check_span.
law restart_feed:
  for +previous: TC.RemoteContext
  for +word: U32
  for draw: TC.Draw
  for valid: RestartInv(previous, TC.NeedWord{draw})
  RestartInv(previous, TC.Draw.feed(Done{word}, draw))

def restart_feed(previous, word, draw, valid):
  match draw:
    case TC.DrawTrace{remaining, TC.NoTraceWord{}, received}:
      valid
    case TC.DrawTrace{remaining, TC.OneTraceWord{first}, received}:
      valid
    case TC.DrawTrace{remaining, TC.TwoTraceWords{first, second}, received}:
      valid
    case TC.DrawTrace{remaining, TC.ThreeTraceWords{+first, +second, +third}, +received}:
      restart_check_trace(previous, TC.Draw.asserted(TC.TraceId.from_words(first, second, third, word)), received,
        remaining, valid, asserted_random(TC.TraceId.from_words(first, second, third, word)))
    case TC.DrawSpan{remaining, TC.NoSpanWord{}, plan}:
      valid
    case TC.DrawSpan{remaining, TC.OneSpanWord{first}, +plan}:
      restart_check_span(previous, TC.SpanId.from_words(first, word), plan, remaining, valid)

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
#
# Laws root_tape, child_tape and restart_tape: Context.root_with, child_with
# and restart_with over Source.tape produce the outcome of Draw.run.

# Over a tape, the IO driver computes what the pure driver computes: running
# Draw.read over Source.tape with a continuation `next`, to any result type
# R, gives `next` the result of Draw.run, the same words read in the same
# order. Since an IO action is a function of R and a continuation (IO in
# Base), this says how Draw.read behaves inside a larger action, such as the
# one Draw.finished builds. root_tape, child_tape and restart_tape rest on it.
law read_tape_then:
  for -R: Type
  for next: Laws.TapeStep() -> IO.OP<R>
  for +fuel: Nat
  for current: Laws.TapeStep()
  {TC.Draw.read(~Laws.Tape(), ~TC.Source.tape, fuel, current)(R, next) == next(TC.Draw.run(fuel, current)) : IO.OP<R>}

# Splits on the fuel for every step: the drivers compute only once it is known.
def read_tape_then(R, next, fuel, current):
  match fuel current:
    case 0n Tuple{tape, TC.Created{context}}:
      {==}
    case 0n Tuple{tape, TC.Failed{error}}:
      {==}
    case 0n Tuple{tape, TC.NeedWord{draw}}:
      {==}
    case 1n+p Tuple{tape, TC.Created{context}}:
      {==}
    case 1n+p Tuple{tape, TC.Failed{error}}:
      {==}
    case 1n+p Tuple{tape, TC.NeedWord{draw}}:
      read_tape_then(R, next, p, TC.Draw.fed_by(Laws.Tape(), TC.Tape.next(tape), draw))

# Law root_tape: generating a root as an IO action over a tape source
# (Context.root_with with Source.tape) produces Draw.outcome of the pure
# driver Draw.run with the same budget of 48 words. Laws.root_tape returns
# this proof.
law root_tape:
  for tape: Laws.Tape()
  {Laws.Observe(Laws.TapeOutcome(), TC.Context.root_with(~Laws.Tape(), ~TC.Source.tape, tape)) ==
    Emit{TC.Draw.outcome(Laws.Tape(), TC.Draw.run(48n, (tape, TC.Draw.root())))} : IO.OP<Laws.TapeOutcome()>}

# read_tape_then, with the continuation that Draw.finished and Observe supply.
def root_tape(tape):
  read_tape_then(Laws.TapeOutcome(), done => Emit{TC.Draw.outcome(Laws.Tape(), done)}, 48n, (tape, TC.Draw.root()))

# Law child_tape: as root_tape, for a child with a budget of 16 words.
# Laws.child_tape returns this proof.
law child_tape:
  for tape: Laws.Tape()
  for parent: TC.Parent
  for sampling: TC.Sampling
  {Laws.Observe(Laws.TapeOutcome(), TC.Context.child_with(~Laws.Tape(), ~TC.Source.tape, tape, parent, sampling)) ==
    Emit{TC.Draw.outcome(Laws.Tape(), TC.Draw.run(16n, (tape, TC.Draw.child(parent, sampling))))} : IO.OP<Laws.TapeOutcome()>}

def child_tape(tape, parent, sampling):
  read_tape_then(Laws.TapeOutcome(), done => Emit{TC.Draw.outcome(Laws.Tape(), done)}, 16n,
    (tape, TC.Draw.child(parent, sampling)))

# Law restart_tape: as root_tape, for a restart with a budget of 48 words.
# Laws.restart_tape returns this proof.
law restart_tape:
  for tape: Laws.Tape()
  for previous: TC.RemoteContext
  {Laws.Observe(Laws.TapeOutcome(), TC.Context.restart_with(~Laws.Tape(), ~TC.Source.tape, tape, previous)) ==
    Emit{TC.Draw.outcome(Laws.Tape(), TC.Draw.run(48n, (tape, TC.Draw.restart(previous))))} : IO.OP<Laws.TapeOutcome()>}

def restart_tape(tape, previous):
  read_tape_then(Laws.TapeOutcome(), done => Emit{TC.Draw.outcome(Laws.Tape(), done)}, 48n,
    (tape, TC.Draw.restart(previous)))
