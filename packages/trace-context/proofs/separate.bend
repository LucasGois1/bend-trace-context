# Proofs: separate generation
# ===========================
#
# What the two pieces of the generation machine do alone, over tapes: a trace
# ID draw (TraceDraw.feed and the TraceDraw.check, reuse and retry functions
# that decide a candidate) and a span ID draw (the same for SpanDraw),
# driven purely by TraceDraw.run and SpanDraw.run, and as IO actions by
# TraceDraw.read and SpanDraw.read over Source.tape, as TraceId.generate_with
# and SpanId.generate_with do. PROOF.bend proves the laws of the "Separate
# generation" part of section 6 of LAWS.bend with this module: trace_id_tape
# (read_trace_tape), trace_id_ends (trace_run_ends with trace_start_within)
# and generated_trace_id (trace_run_inv, through the view TraceRunView), the
# same for span IDs, and root_composed, child_composed and restart_composed
# (read_trace_same and read_span_same, with after_trace_same and
# span_context_same). trace_id_failure, trace_id_exhaustion and their span ID
# twins need no lemma: PROOF.bend proves them by computation, and
# trace_id_candidate and span_id_candidate by computation once their
# hypothesis is rewritten. proofs/generation.bend builds the laws of root,
# child and restart generation on the lemmas of this module.
#
# The strategy is that of proofs/generation.bend, piece by piece:
#
# - Termination. TraceWithin(step, n) says that a trace ID draw ends within
#   n more words, whatever they are, and the *_within lemmas follow the draw
#   word by word and candidate by candidate; TraceRetry carries the bound of
#   the next candidate. trace_run_ends turns a bound equal to the fuel into
#   TraceDraw.ended for every tape.
# - Drawn identifiers. TraceInv is an invariant of a trace ID draw whose
#   DrawnTraceId case is the conclusion of generated_trace_id. It holds of
#   the first step, every word keeps it (trace_feed_inv), and so does a
#   whole drive (trace_run_inv, by induction on the fuel).
# - IO. read_trace_tape shows, by induction on the fuel, that TraceDraw.read
#   over Source.tape computes TraceDraw.run, as read_tape_outcome of
#   proofs/generation.bend does for Draw.read.
# - Compositions. The checker compares two continuations only once the
#   outcome that they receive is known, so read_trace_same and read_span_same
#   carry an agreement on every outcome through the drivers.
#
# The statements use Tape, TapeTraceStep, TapeTraceId, TapeSpanStep,
# TapeSpanId, TapeOutcome, Observe, TraceAvoids, SpanAvoids, root_of and
# context_of of LAWS.bend.

import Base
import ../trace_context.bend as TC
import ./strings.bend as StringsProof
import ./bools.bend as BoolsProof
import ../LAWS.bend as Laws

# Trace ID draws: word bounds
# ===========================

# The claim "this trace ID draw ends within n more words, whatever they are",
# as a type, as Within of proofs/generation.bend states it of a generation:
# Unit for a draw that has ended, Empty for one that needs a word when n is
# 0, and otherwise, for every word, the bound n - 1 of the draw that feeding
# the word gives. A failed word ends the draw at once (law trace_id_failure),
# so only successful words count.
def TraceWithin(step: TC.TraceStep, n: Nat) -> Type:
  match step:
    case TC.DrawnTraceId{id}:
      Unit
    case TC.TraceFailed{error}:
      Unit
    case TC.NeedTraceWord{remaining, words, excluded}:
      match n:
        case 0n:
          Empty
        case 1n+p:
          @word: U32 -> TraceWithin(TC.TraceDraw.feed(Done{word}, remaining, words, excluded), p)

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
      TraceWithin(TC.NeedTraceWord{p, TC.NoTraceWord{}, excluded}, trace_budget(p))

# Retrying a candidate leaves the draw within trace_after(remaining) words,
# given `retry`: an exhausted draw has failed, and otherwise the retry is the
# fresh candidate that `retry` bounds.
law trace_retry_within:
  for +remaining: Nat
  for +excluded: Maybe<&2, TC.TraceId>
  for retry: TraceRetry(remaining, excluded)
  TraceWithin(TC.TraceDraw.retry(remaining, excluded), trace_after(remaining))

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
  TraceWithin(TC.TraceDraw.reuse(reused, id, old, remaining), trace_after(remaining))

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
  TraceWithin(TC.TraceDraw.check(candidate, excluded, remaining), trace_after(remaining))

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
  TraceWithin(TC.NeedTraceWord{remaining, TC.ThreeTraceWords{first, second, third}, excluded},
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
  TraceWithin(TC.NeedTraceWord{remaining, TC.TwoTraceWords{first, second}, excluded}, 2n+trace_after(remaining))

def trace_third_within(remaining, excluded, retry, first, second):
  +third => trace_fourth_within(remaining, excluded, retry, first, second, third)

# A draw holding one word of a candidate ends within three words more than
# trace_after(remaining), given `retry`, whatever the second word.
law trace_second_within:
  for +remaining: Nat
  for +excluded: Maybe<&2, TC.TraceId>
  for retry: TraceRetry(remaining, excluded)
  for +first: U32
  TraceWithin(TC.NeedTraceWord{remaining, TC.OneTraceWord{first}, excluded}, 3n+trace_after(remaining))

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
  TraceWithin(TC.NeedTraceWord{remaining, TC.NoTraceWord{}, excluded}, trace_budget(remaining))

def trace_start_within(remaining, excluded):
  match remaining:
    case 0n:
      +first => trace_second_within(0n, excluded, Unit{}, first)
    case 1n+p:
      +first => trace_second_within(1n+p, excluded, trace_start_within(p, excluded), first)

# When a trace ID draw has ended, driving it further keeps it ended, whatever
# the fuel and the tape. trace_run_ends uses it after a source error.
law trace_ended_stays:
  for +fuel: Nat
  for tape: Laws.Tape()
  for +step: TC.TraceStep
  for ended: {TC.TraceDraw.is_finished(step) == True{} : Bool}
  {TC.TraceDraw.ended(TC.TraceDraw.run(fuel, (tape, step))) == True{} : Bool}

# Refutes the waiting draws, for which `ended` says False == True.
def trace_ended_stays(fuel, tape, step, ended):
  match fuel step:
    case 0n TC.DrawnTraceId{id}:
      {==}
    case 0n TC.TraceFailed{error}:
      {==}
    case 0n TC.NeedTraceWord{remaining, words, excluded}:
      Empty.absurd({TC.TraceDraw.ended(TC.TraceDraw.run(0n, (tape, TC.NeedTraceWord{remaining, words, excluded}))) ==
        True{} : Bool}, BoolsProof.true_ne_false(Equal.sym(Bool, False{}, True{}, ended)))
    case 1n+p TC.DrawnTraceId{id}:
      {==}
    case 1n+p TC.TraceFailed{error}:
      {==}
    case 1n+p TC.NeedTraceWord{remaining, words, excluded}:
      Empty.absurd({TC.TraceDraw.ended(TC.TraceDraw.run(1n+p, (tape, TC.NeedTraceWord{remaining, words, excluded}))) ==
        True{} : Bool}, BoolsProof.true_ne_false(Equal.sym(Bool, False{}, True{}, ended)))

# Driving a trace ID draw with enough fuel ends it, whatever the tape holds:
# when the draw ends within `fuel` words (TraceWithin), TraceDraw.run with
# that fuel returns an ended draw. As run_ends of proofs/generation.bend:
# induction on the fuel along the tape, and an error, the end of the tape
# included, fails at once and stays ended.
law trace_run_ends:
  for +fuel: Nat
  for +step: TC.TraceStep
  for tape: Laws.Tape()
  for bound: TraceWithin(step, fuel)
  {TC.TraceDraw.ended(TC.TraceDraw.run(fuel, (tape, step))) == True{} : Bool}

def trace_run_ends(fuel, step, tape, bound):
  match fuel:
    case 0n:
      match step:
        case TC.DrawnTraceId{id}:
          {==}
        case TC.TraceFailed{error}:
          {==}
        case TC.NeedTraceWord{remaining, words, excluded}:
          Empty.absurd({TC.TraceDraw.ended(TC.TraceDraw.run(0n,
            (tape, TC.NeedTraceWord{remaining, words, excluded}))) == True{} : Bool}, bound)
    case 1n+p:
      match step:
        case TC.DrawnTraceId{id}:
          {==}
        case TC.TraceFailed{error}:
          {==}
        case TC.NeedTraceWord{+remaining, +words, +excluded}:
          match tape:
            case Nil{}:
              trace_ended_stays(p, Nil{}, TC.TraceFailed{TC.SourceFailure{1, "tape-exhausted"}}, {==})
            case Con{Fail{(code, message)}, rest}:
              trace_ended_stays(p, rest, TC.TraceFailed{TC.SourceFailure{code, message}}, {==})
            case Con{Done{+word}, rest}:
              trace_run_ends(p, TC.TraceDraw.feed(Done{word}, remaining, words, excluded), rest, bound(word))

# Driving a failed trace ID draw changes nothing, whatever the fuel.
# trace_run_inv uses it for the rest of a drive after a source error.
law trace_run_failed:
  for fuel: Nat
  for tape: Laws.Tape()
  for error: TC.GenerationError
  {TC.TraceDraw.run(fuel, (tape, TC.TraceFailed{error})) == (tape, TC.TraceFailed{error}) : Laws.TapeTraceStep()}

# Splits on the fuel only because TraceDraw.run does not compute on an unknown
# one.
def trace_run_failed(fuel, tape, error):
  match fuel:
    case 0n:
      {==}
    case 1n+p:
      {==}

# Trace ID draws: drawn trace IDs
# ===============================

# The view "this trace ID candidate asserts random-trace-id": Unit for None{}
# (a zero candidate, which is retried) and, for Some{id}, the equation that
# id is random. trace_check_inv takes it as a hypothesis about the candidate
# it checks.
def RandomCandidate(candidate: Maybe<&2, TC.TraceId>) -> Type:
  match candidate:
    case None{}:
      Unit
    case Some{id}:
      {TC.TraceId.is_random(id) == True{} : Bool}

# Every trace ID candidate that generation checks asserts random-trace-id:
# Draw.asserted, which TraceDraw.take applies to each complete candidate,
# sets the assertion on every present one. trace_feed_inv uses it when the
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

# The invariant of a trace ID draw that must avoid `excluded`, a view of each
# step: a draw that needs a word keeps `excluded` as the trace ID to avoid, a
# drawn trace ID has the two conclusions of law generated_trace_id (it asserts
# random-trace-id and avoids `excluded`), and a failure needs nothing (Unit).
def TraceInv(+excluded: Maybe<&2, TC.TraceId>, step: TC.TraceStep) -> Type:
  match step:
    case TC.NeedTraceWord{remaining, words, kept}:
      {kept == excluded : Maybe<&2, TC.TraceId>}
    case TC.DrawnTraceId{id}:
      {TC.TraceId.is_random(id) == True{} : Bool} & Laws.TraceAvoids(excluded, id)
    case TC.TraceFailed{error}:
      Unit

# When a draw keeps `excluded` (`valid`), retrying its candidate keeps the
# invariant: the fresh candidate keeps it too, and an exhausted draw has
# failed.
law trace_retry_inv:
  for -excluded: Maybe<&2, TC.TraceId>
  for remaining: Nat
  for -kept: Maybe<&2, TC.TraceId>
  for valid: {kept == excluded : Maybe<&2, TC.TraceId>}
  TraceInv(excluded, TC.TraceDraw.retry(remaining, kept))

def trace_retry_inv(excluded, remaining, kept, valid):
  match remaining:
    case 0n:
      Unit{}
    case 1n+p:
      valid

# When a draw keeps the excluded trace ID `old` (`valid`) and the candidate
# `id` asserts random-trace-id (`random`), deciding the candidate keeps the
# invariant. `reused` is the result of TraceId.is_eq(id, old), passed with the
# equation `evidence` because `match` inspects only variables: a reused
# candidate is retried, and a drawn one differs from `old` by
# StringsProof.distinct.
law trace_reuse_inv:
  for -excluded: Maybe<&2, TC.TraceId>
  for reused: Bool
  for +id: TC.TraceId
  for +old: TC.TraceId
  for remaining: Nat
  for evidence: {TC.TraceId.is_eq(id, old) == reused : Bool}
  for valid: {Some{old} == excluded : Maybe<&2, TC.TraceId>}
  for random: {TC.TraceId.is_random(id) == True{} : Bool}
  TraceInv(excluded, TC.TraceDraw.reuse(reused, id, old, remaining))

def trace_reuse_inv(excluded, reused, id, old, remaining, evidence, valid, random):
  match reused:
    case True{}:
      trace_retry_inv(excluded, remaining, Some{old}, valid)
    case False{}:
      %valid : {TC.TraceId.is_random(id) == True{} : Bool} & Laws.TraceAvoids(_, id)
      (random, StringsProof.distinct(TC.TraceId.to_string(id), TC.TraceId.to_string(old), evidence))

# When a draw keeps `excluded` (`valid`) and its complete candidate asserts
# random-trace-id (`random`), checking the candidate keeps the invariant. A
# draw with nothing to exclude draws any nonzero candidate, which avoids
# nothing; otherwise trace_reuse_inv decides the candidate.
law trace_check_inv:
  for -excluded: Maybe<&2, TC.TraceId>
  for candidate: Maybe<&2, TC.TraceId>
  for +kept: Maybe<&2, TC.TraceId>
  for remaining: Nat
  for valid: {kept == excluded : Maybe<&2, TC.TraceId>}
  for random: RandomCandidate(candidate)
  TraceInv(excluded, TC.TraceDraw.check(candidate, kept, remaining))

def trace_check_inv(excluded, candidate, kept, remaining, valid, random):
  match candidate:
    case None{}:
      trace_retry_inv(excluded, remaining, kept, valid)
    case Some{+id}:
      match kept:
        case None{}:
          %valid : {TC.TraceId.is_random(id) == True{} : Bool} & Laws.TraceAvoids(_, id)
          (random, Unit{})
        case Some{+old}:
          trace_reuse_inv(excluded, TC.TraceId.is_eq(id, old), id, old, remaining, {==}, valid, random)

# When a draw that needs a word keeps `excluded` (`valid`), the invariant
# holds after feeding it any word: a word that only extends a candidate
# changes nothing the invariant speaks of, and the fourth goes through
# trace_check_inv, its candidate random by asserted_random.
law trace_feed_inv:
  for -excluded: Maybe<&2, TC.TraceId>
  for +word: U32
  for remaining: Nat
  for words: TC.TraceWords
  for +kept: Maybe<&2, TC.TraceId>
  for valid: {kept == excluded : Maybe<&2, TC.TraceId>}
  TraceInv(excluded, TC.TraceDraw.feed(Done{word}, remaining, words, kept))

def trace_feed_inv(excluded, word, remaining, words, kept, valid):
  match words:
    case TC.NoTraceWord{}:
      valid
    case TC.OneTraceWord{first}:
      valid
    case TC.TwoTraceWords{first, second}:
      valid
    case TC.ThreeTraceWords{+first, +second, +third}:
      trace_check_inv(excluded, TC.Draw.asserted(TC.TraceId.from_words(first, second, third, word)), kept, remaining,
        valid, asserted_random(TC.TraceId.from_words(first, second, third, word)))

# The view of TraceDraw.run's result: TraceInv of its final step, the unread
# tape ignored. Laws.generated_trace_id rewrites its hypothesis
# {TraceDraw.run(...) == (rest, DrawnTraceId{id})} through TraceRunView, which
# turns the law's conclusion into TraceRunView of the drive, proved by
# trace_run_inv.
def TraceRunView(+excluded: Maybe<&2, TC.TraceId>, result: Laws.TapeTraceStep()) -> Type:
  match result:
    case Tuple{tape, step}:
      TraceInv(excluded, step)

# When TraceInv holds of a step, it holds of the step that TraceDraw.run
# returns from it, for every fuel and every tape. Laws.generated_trace_id
# applies it to TraceDraw.start(excluded), whose invariant holds by
# computation ({==}). Induction on the fuel; after an error,
# trace_run_failed rewrites the rest of the drive.
law trace_run_inv:
  for -excluded: Maybe<&2, TC.TraceId>
  for +fuel: Nat
  for +step: TC.TraceStep
  for tape: Laws.Tape()
  for valid: TraceInv(excluded, step)
  TraceRunView(excluded, TC.TraceDraw.run(fuel, (tape, step)))

def trace_run_inv(excluded, fuel, step, tape, valid):
  match fuel:
    case 0n:
      match step:
        case TC.NeedTraceWord{remaining, words, kept}:
          valid
        case TC.DrawnTraceId{id}:
          valid
        case TC.TraceFailed{error}:
          valid
    case 1n+p:
      match step:
        case TC.DrawnTraceId{id}:
          valid
        case TC.TraceFailed{error}:
          valid
        case TC.NeedTraceWord{remaining, words, +kept}:
          match tape:
            case Nil{}:
              %Equal.sym(Laws.TapeTraceStep(), TC.TraceDraw.run(p, (Nil{}, TC.TraceFailed{TC.SourceFailure{1,
                "tape-exhausted"}})), (Nil{}, TC.TraceFailed{TC.SourceFailure{1, "tape-exhausted"}}),
                trace_run_failed(p, Nil{}, TC.SourceFailure{1, "tape-exhausted"})) : TraceRunView(excluded, _)
              Unit{}
            case Con{Fail{(code, message)}, rest}:
              %Equal.sym(Laws.TapeTraceStep(), TC.TraceDraw.run(p, (rest, TC.TraceFailed{TC.SourceFailure{code,
                message}})), (rest, TC.TraceFailed{TC.SourceFailure{code, message}}),
                trace_run_failed(p, rest, TC.SourceFailure{code, message})) : TraceRunView(excluded, _)
              Unit{}
            case Con{Done{+word}, rest}:
              trace_run_inv(excluded, p, TC.TraceDraw.feed(Done{word}, remaining, words, kept), rest,
                trace_feed_inv(excluded, word, remaining, words, kept, valid))

# Trace ID draws: the IO operation over a tape
# ============================================

# Over a tape, the IO driver of a trace ID draw computes what its pure driver
# computes: running TraceDraw.read over Source.tape, followed by a
# continuation that emits a function `f` of the outcome, gives what any `g`
# that agrees with `f` on every outcome (`same`) emits for the outcome of
# TraceDraw.run, the same words read in the same order. The proof is that of
# read_tape_outcome in proofs/generation.bend, for the trace ID draw's steps.
law read_trace_tape:
  for -A: Type
  for -f: Laws.TapeTraceId() -> A
  for -g: Laws.TapeTraceId() -> A
  for same: @outcome: Laws.TapeTraceId() -> {f(outcome) == g(outcome) : A}
  for +fuel: Nat
  for current: Laws.TapeTraceStep()
  {TC.TraceDraw.read(~Laws.Tape(), ~TC.Source.tape, fuel, current)(A,
    step => Emit{f(TC.TraceDraw.outcome(Laws.Tape(), step))}) ==
    Emit{g(TC.TraceDraw.outcome(Laws.Tape(), TC.TraceDraw.run(fuel, current)))} : IO.OP<A>}

# Splits on the fuel for every step: the drivers compute only once it is
# known. An ended draw or an empty fuel emits at once, and a word is fed
# otherwise.
def read_trace_tape(A, f, g, same, fuel, current):
  match fuel current:
    case 0n Tuple{tape, TC.DrawnTraceId{id}}:
      Equal.cong(A, IO.OP<A>, value => Emit{value}, f((tape, Done{id})), g((tape, Done{id})), same((tape, Done{id})))
    case 0n Tuple{tape, TC.TraceFailed{error}}:
      Equal.cong(A, IO.OP<A>, value => Emit{value}, f((tape, Fail{error})), g((tape, Fail{error})),
        same((tape, Fail{error})))
    case 0n Tuple{tape, TC.NeedTraceWord{remaining, words, excluded}}:
      Equal.cong(A, IO.OP<A>, value => Emit{value}, f((tape, Fail{TC.ExhaustedTraceId{}})),
        g((tape, Fail{TC.ExhaustedTraceId{}})), same((tape, Fail{TC.ExhaustedTraceId{}})))
    case 1n+p Tuple{tape, TC.DrawnTraceId{id}}:
      Equal.cong(A, IO.OP<A>, value => Emit{value}, f((tape, Done{id})), g((tape, Done{id})), same((tape, Done{id})))
    case 1n+p Tuple{tape, TC.TraceFailed{error}}:
      Equal.cong(A, IO.OP<A>, value => Emit{value}, f((tape, Fail{error})), g((tape, Fail{error})),
        same((tape, Fail{error})))
    case 1n+p Tuple{tape, TC.NeedTraceWord{remaining, words, excluded}}:
      read_trace_tape(A, f, g, same, p, TC.TraceDraw.fed_by(Laws.Tape(), TC.Tape.next(tape), remaining, words,
        excluded))

# Span ID draws: word bounds
# ==========================
#
# The lemmas of the trace ID draws, for span ID draws: two words per
# candidate.

# The claim "this span ID draw ends within n more words, whatever they are",
# as TraceWithin states it of a trace ID draw.
def SpanWithin(step: TC.SpanStep, n: Nat) -> Type:
  match step:
    case TC.DrawnSpanId{id}:
      Unit
    case TC.SpanFailed{error}:
      Unit
    case TC.NeedSpanWord{remaining, words, excluded}:
      match n:
        case 0n:
          Empty
        case 1n+p:
          @word: U32 -> SpanWithin(TC.SpanDraw.feed(Done{word}, remaining, words, excluded), p)

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
      SpanWithin(TC.NeedSpanWord{p, TC.NoSpanWord{}, excluded}, span_budget(p))

# As trace_retry_within.
law span_retry_within:
  for +remaining: Nat
  for +excluded: Maybe<&2, TC.SpanId>
  for retry: SpanRetry(remaining, excluded)
  SpanWithin(TC.SpanDraw.retry(remaining, excluded), span_after(remaining))

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
  SpanWithin(TC.SpanDraw.reuse(reused, id, old, remaining), span_after(remaining))

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
  SpanWithin(TC.SpanDraw.check(candidate, excluded, remaining), span_after(remaining))

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
  SpanWithin(TC.NeedSpanWord{remaining, TC.OneSpanWord{first}, excluded}, 1n+span_after(remaining))

def span_second_within(remaining, excluded, retry, first):
  +second => span_check_within(TC.SpanId.from_words(first, second), excluded, remaining, retry)

# A span ID draw at the start of a candidate, with `remaining` further
# candidates allowed, ends within span_budget(remaining) words, for every
# span ID to exclude and every sequence of words, as trace_start_within.
# Laws.span_id_ends uses it with remaining 7n, which gives 16 words.
law span_start_within:
  for +remaining: Nat
  for +excluded: Maybe<&2, TC.SpanId>
  SpanWithin(TC.NeedSpanWord{remaining, TC.NoSpanWord{}, excluded}, span_budget(remaining))

def span_start_within(remaining, excluded):
  match remaining:
    case 0n:
      +first => span_second_within(0n, excluded, Unit{}, first)
    case 1n+p:
      +first => span_second_within(1n+p, excluded, span_start_within(p, excluded), first)

# As trace_ended_stays, for span ID draws.
law span_ended_stays:
  for +fuel: Nat
  for tape: Laws.Tape()
  for +step: TC.SpanStep
  for ended: {TC.SpanDraw.is_finished(step) == True{} : Bool}
  {TC.SpanDraw.ended(TC.SpanDraw.run(fuel, (tape, step))) == True{} : Bool}

def span_ended_stays(fuel, tape, step, ended):
  match fuel step:
    case 0n TC.DrawnSpanId{id}:
      {==}
    case 0n TC.SpanFailed{error}:
      {==}
    case 0n TC.NeedSpanWord{remaining, words, excluded}:
      Empty.absurd({TC.SpanDraw.ended(TC.SpanDraw.run(0n, (tape, TC.NeedSpanWord{remaining, words, excluded}))) ==
        True{} : Bool}, BoolsProof.true_ne_false(Equal.sym(Bool, False{}, True{}, ended)))
    case 1n+p TC.DrawnSpanId{id}:
      {==}
    case 1n+p TC.SpanFailed{error}:
      {==}
    case 1n+p TC.NeedSpanWord{remaining, words, excluded}:
      Empty.absurd({TC.SpanDraw.ended(TC.SpanDraw.run(1n+p, (tape, TC.NeedSpanWord{remaining, words, excluded}))) ==
        True{} : Bool}, BoolsProof.true_ne_false(Equal.sym(Bool, False{}, True{}, ended)))

# As trace_run_ends, for span ID draws.
law span_run_ends:
  for +fuel: Nat
  for +step: TC.SpanStep
  for tape: Laws.Tape()
  for bound: SpanWithin(step, fuel)
  {TC.SpanDraw.ended(TC.SpanDraw.run(fuel, (tape, step))) == True{} : Bool}

def span_run_ends(fuel, step, tape, bound):
  match fuel:
    case 0n:
      match step:
        case TC.DrawnSpanId{id}:
          {==}
        case TC.SpanFailed{error}:
          {==}
        case TC.NeedSpanWord{remaining, words, excluded}:
          Empty.absurd({TC.SpanDraw.ended(TC.SpanDraw.run(0n, (tape, TC.NeedSpanWord{remaining, words, excluded}))) ==
            True{} : Bool}, bound)
    case 1n+p:
      match step:
        case TC.DrawnSpanId{id}:
          {==}
        case TC.SpanFailed{error}:
          {==}
        case TC.NeedSpanWord{+remaining, +words, +excluded}:
          match tape:
            case Nil{}:
              span_ended_stays(p, Nil{}, TC.SpanFailed{TC.SourceFailure{1, "tape-exhausted"}}, {==})
            case Con{Fail{(code, message)}, rest}:
              span_ended_stays(p, rest, TC.SpanFailed{TC.SourceFailure{code, message}}, {==})
            case Con{Done{+word}, rest}:
              span_run_ends(p, TC.SpanDraw.feed(Done{word}, remaining, words, excluded), rest, bound(word))

# As trace_run_failed, for span ID draws.
law span_run_failed:
  for fuel: Nat
  for tape: Laws.Tape()
  for error: TC.GenerationError
  {TC.SpanDraw.run(fuel, (tape, TC.SpanFailed{error})) == (tape, TC.SpanFailed{error}) : Laws.TapeSpanStep()}

def span_run_failed(fuel, tape, error):
  match fuel:
    case 0n:
      {==}
    case 1n+p:
      {==}

# Span ID draws: drawn span IDs
# =============================

# The invariant of a span ID draw that must avoid `excluded`, as TraceInv
# without the randomness assertion: a drawn span ID avoids `excluded`.
def SpanInv(+excluded: Maybe<&2, TC.SpanId>, step: TC.SpanStep) -> Type:
  match step:
    case TC.NeedSpanWord{remaining, words, kept}:
      {kept == excluded : Maybe<&2, TC.SpanId>}
    case TC.DrawnSpanId{id}:
      Laws.SpanAvoids(excluded, id)
    case TC.SpanFailed{error}:
      Unit

# As trace_retry_inv.
law span_retry_inv:
  for -excluded: Maybe<&2, TC.SpanId>
  for remaining: Nat
  for -kept: Maybe<&2, TC.SpanId>
  for valid: {kept == excluded : Maybe<&2, TC.SpanId>}
  SpanInv(excluded, TC.SpanDraw.retry(remaining, kept))

def span_retry_inv(excluded, remaining, kept, valid):
  match remaining:
    case 0n:
      Unit{}
    case 1n+p:
      valid

# As trace_reuse_inv: a drawn span ID differs from the excluded `old`.
law span_reuse_inv:
  for -excluded: Maybe<&2, TC.SpanId>
  for reused: Bool
  for +id: TC.SpanId
  for +old: TC.SpanId
  for remaining: Nat
  for evidence: {TC.SpanId.is_eq(id, old) == reused : Bool}
  for valid: {Some{old} == excluded : Maybe<&2, TC.SpanId>}
  SpanInv(excluded, TC.SpanDraw.reuse(reused, id, old, remaining))

def span_reuse_inv(excluded, reused, id, old, remaining, evidence, valid):
  match reused:
    case True{}:
      span_retry_inv(excluded, remaining, Some{old}, valid)
    case False{}:
      %valid : Laws.SpanAvoids(_, id)
      StringsProof.distinct(TC.SpanId.to_string(id), TC.SpanId.to_string(old), evidence)

# As trace_check_inv.
law span_check_inv:
  for -excluded: Maybe<&2, TC.SpanId>
  for candidate: Maybe<&2, TC.SpanId>
  for +kept: Maybe<&2, TC.SpanId>
  for remaining: Nat
  for valid: {kept == excluded : Maybe<&2, TC.SpanId>}
  SpanInv(excluded, TC.SpanDraw.check(candidate, kept, remaining))

def span_check_inv(excluded, candidate, kept, remaining, valid):
  match candidate:
    case None{}:
      span_retry_inv(excluded, remaining, kept, valid)
    case Some{+id}:
      match kept:
        case None{}:
          %valid : Laws.SpanAvoids(_, id)
          Unit{}
        case Some{+old}:
          span_reuse_inv(excluded, TC.SpanId.is_eq(id, old), id, old, remaining, {==}, valid)

# As trace_feed_inv: the second word of a candidate goes through
# span_check_inv.
law span_feed_inv:
  for -excluded: Maybe<&2, TC.SpanId>
  for +word: U32
  for remaining: Nat
  for words: TC.SpanWords
  for +kept: Maybe<&2, TC.SpanId>
  for valid: {kept == excluded : Maybe<&2, TC.SpanId>}
  SpanInv(excluded, TC.SpanDraw.feed(Done{word}, remaining, words, kept))

def span_feed_inv(excluded, word, remaining, words, kept, valid):
  match words:
    case TC.NoSpanWord{}:
      valid
    case TC.OneSpanWord{first}:
      span_check_inv(excluded, TC.SpanId.from_words(first, word), kept, remaining, valid)

# The view of SpanDraw.run's result, as TraceRunView.
def SpanRunView(+excluded: Maybe<&2, TC.SpanId>, result: Laws.TapeSpanStep()) -> Type:
  match result:
    case Tuple{tape, step}:
      SpanInv(excluded, step)

# As trace_run_inv, for span ID draws.
law span_run_inv:
  for -excluded: Maybe<&2, TC.SpanId>
  for +fuel: Nat
  for +step: TC.SpanStep
  for tape: Laws.Tape()
  for valid: SpanInv(excluded, step)
  SpanRunView(excluded, TC.SpanDraw.run(fuel, (tape, step)))

def span_run_inv(excluded, fuel, step, tape, valid):
  match fuel:
    case 0n:
      match step:
        case TC.NeedSpanWord{remaining, words, kept}:
          valid
        case TC.DrawnSpanId{id}:
          valid
        case TC.SpanFailed{error}:
          valid
    case 1n+p:
      match step:
        case TC.DrawnSpanId{id}:
          valid
        case TC.SpanFailed{error}:
          valid
        case TC.NeedSpanWord{remaining, words, +kept}:
          match tape:
            case Nil{}:
              %Equal.sym(Laws.TapeSpanStep(), TC.SpanDraw.run(p, (Nil{}, TC.SpanFailed{TC.SourceFailure{1,
                "tape-exhausted"}})), (Nil{}, TC.SpanFailed{TC.SourceFailure{1, "tape-exhausted"}}),
                span_run_failed(p, Nil{}, TC.SourceFailure{1, "tape-exhausted"})) : SpanRunView(excluded, _)
              Unit{}
            case Con{Fail{(code, message)}, rest}:
              %Equal.sym(Laws.TapeSpanStep(), TC.SpanDraw.run(p, (rest, TC.SpanFailed{TC.SourceFailure{code,
                message}})), (rest, TC.SpanFailed{TC.SourceFailure{code, message}}),
                span_run_failed(p, rest, TC.SourceFailure{code, message})) : SpanRunView(excluded, _)
              Unit{}
            case Con{Done{+word}, rest}:
              span_run_inv(excluded, p, TC.SpanDraw.feed(Done{word}, remaining, words, kept), rest,
                span_feed_inv(excluded, word, remaining, words, kept, valid))

# Span ID draws: the IO operation over a tape
# ===========================================

# As read_trace_tape, for span ID draws.
law read_span_tape:
  for -A: Type
  for -f: Laws.TapeSpanId() -> A
  for -g: Laws.TapeSpanId() -> A
  for same: @outcome: Laws.TapeSpanId() -> {f(outcome) == g(outcome) : A}
  for +fuel: Nat
  for current: Laws.TapeSpanStep()
  {TC.SpanDraw.read(~Laws.Tape(), ~TC.Source.tape, fuel, current)(A,
    step => Emit{f(TC.SpanDraw.outcome(Laws.Tape(), step))}) ==
    Emit{g(TC.SpanDraw.outcome(Laws.Tape(), TC.SpanDraw.run(fuel, current)))} : IO.OP<A>}

def read_span_tape(A, f, g, same, fuel, current):
  match fuel current:
    case 0n Tuple{tape, TC.DrawnSpanId{id}}:
      Equal.cong(A, IO.OP<A>, value => Emit{value}, f((tape, Done{id})), g((tape, Done{id})), same((tape, Done{id})))
    case 0n Tuple{tape, TC.SpanFailed{error}}:
      Equal.cong(A, IO.OP<A>, value => Emit{value}, f((tape, Fail{error})), g((tape, Fail{error})),
        same((tape, Fail{error})))
    case 0n Tuple{tape, TC.NeedSpanWord{remaining, words, excluded}}:
      Equal.cong(A, IO.OP<A>, value => Emit{value}, f((tape, Fail{TC.ExhaustedSpanId{}})),
        g((tape, Fail{TC.ExhaustedSpanId{}})), same((tape, Fail{TC.ExhaustedSpanId{}})))
    case 1n+p Tuple{tape, TC.DrawnSpanId{id}}:
      Equal.cong(A, IO.OP<A>, value => Emit{value}, f((tape, Done{id})), g((tape, Done{id})), same((tape, Done{id})))
    case 1n+p Tuple{tape, TC.SpanFailed{error}}:
      Equal.cong(A, IO.OP<A>, value => Emit{value}, f((tape, Fail{error})), g((tape, Fail{error})),
        same((tape, Fail{error})))
    case 1n+p Tuple{tape, TC.NeedSpanWord{remaining, words, excluded}}:
      read_span_tape(A, f, g, same, p, TC.SpanDraw.fed_by(Laws.Tape(), TC.Tape.next(tape), remaining, words,
        excluded))

# Compositions over a tape
# ========================
#
# Laws root_composed, child_composed and restart_composed: over a tape, the
# compositions that Context.root_with, child_with and restart_with run agree
# with those that LAWS.bend states. The continuations of the package
# (Draw.after_trace, Draw.span_context) and those of LAWS.bend (root_of,
# context_of) are different definitions, which the checker compares only
# once the outcome they receive is known. read_trace_same and read_span_same
# carry an agreement on every outcome through the drivers, as read_tape_same
# of proofs/generation.bend does for Draw.read, and after_trace_same and
# span_context_same are those agreements.

# Two continuations `f` and `g` of a trace ID draw's outcome make
# TraceDraw.read over Source.tape give the same whenever they agree on every
# outcome (`same`). Induction on the fuel, as read_trace_tape.
law read_trace_same:
  for -A: Type
  for -f: Laws.TapeTraceId() -> IO.OP<A>
  for -g: Laws.TapeTraceId() -> IO.OP<A>
  for same: @outcome: Laws.TapeTraceId() -> {f(outcome) == g(outcome) : IO.OP<A>}
  for +fuel: Nat
  for current: Laws.TapeTraceStep()
  {TC.TraceDraw.read(~Laws.Tape(), ~TC.Source.tape, fuel, current)(A,
    step => f(TC.TraceDraw.outcome(Laws.Tape(), step))) ==
    TC.TraceDraw.read(~Laws.Tape(), ~TC.Source.tape, fuel, current)(A,
      step => g(TC.TraceDraw.outcome(Laws.Tape(), step))) : IO.OP<A>}

def read_trace_same(A, f, g, same, fuel, current):
  match fuel current:
    case 0n Tuple{tape, TC.DrawnTraceId{id}}:
      same((tape, Done{id}))
    case 0n Tuple{tape, TC.TraceFailed{error}}:
      same((tape, Fail{error}))
    case 0n Tuple{tape, TC.NeedTraceWord{remaining, words, excluded}}:
      same((tape, Fail{TC.ExhaustedTraceId{}}))
    case 1n+p Tuple{tape, TC.DrawnTraceId{id}}:
      same((tape, Done{id}))
    case 1n+p Tuple{tape, TC.TraceFailed{error}}:
      same((tape, Fail{error}))
    case 1n+p Tuple{tape, TC.NeedTraceWord{remaining, words, excluded}}:
      read_trace_same(A, f, g, same, p, TC.TraceDraw.fed_by(Laws.Tape(), TC.Tape.next(tape), remaining, words,
        excluded))

# As read_trace_same, for a span ID draw's continuations.
law read_span_same:
  for -A: Type
  for -f: Laws.TapeSpanId() -> IO.OP<A>
  for -g: Laws.TapeSpanId() -> IO.OP<A>
  for same: @outcome: Laws.TapeSpanId() -> {f(outcome) == g(outcome) : IO.OP<A>}
  for +fuel: Nat
  for current: Laws.TapeSpanStep()
  {TC.SpanDraw.read(~Laws.Tape(), ~TC.Source.tape, fuel, current)(A,
    step => f(TC.SpanDraw.outcome(Laws.Tape(), step))) ==
    TC.SpanDraw.read(~Laws.Tape(), ~TC.Source.tape, fuel, current)(A,
      step => g(TC.SpanDraw.outcome(Laws.Tape(), step))) : IO.OP<A>}

def read_span_same(A, f, g, same, fuel, current):
  match fuel current:
    case 0n Tuple{tape, TC.DrawnSpanId{id}}:
      same((tape, Done{id}))
    case 0n Tuple{tape, TC.SpanFailed{error}}:
      same((tape, Fail{error}))
    case 0n Tuple{tape, TC.NeedSpanWord{remaining, words, excluded}}:
      same((tape, Fail{TC.ExhaustedSpanId{}}))
    case 1n+p Tuple{tape, TC.DrawnSpanId{id}}:
      same((tape, Done{id}))
    case 1n+p Tuple{tape, TC.SpanFailed{error}}:
      same((tape, Fail{error}))
    case 1n+p Tuple{tape, TC.NeedSpanWord{remaining, words, excluded}}:
      read_span_same(A, f, g, same, p, TC.SpanDraw.fed_by(Laws.Tape(), TC.Tape.next(tape), remaining, words,
        excluded))

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
# Draw.after_trace, emits what LAWS.bend's root_of emits, for every outcome of
# the trace ID: a failure at once, and otherwise the same span ID draw, whose
# continuations agree by span_context_same.
law after_trace_same:
  for outcome: Laws.TapeTraceId()
  {TC.Draw.after_trace(~Laws.Tape(), ~TC.Source.tape, outcome)(Laws.TapeOutcome(), value => Emit{value}) ==
    Laws.root_of(outcome)(Laws.TapeOutcome(), value => Emit{value}) : IO.OP<Laws.TapeOutcome()>}

def after_trace_same(outcome):
  match outcome:
    case Tuple{rest, Fail{error}}:
      {==}
    case Tuple{rest, Done{trace_id}}:
      read_span_same(Laws.TapeOutcome(), done => Emit{TC.Draw.span_context(Laws.Tape(), trace_id, False{}, done)},
        done => Emit{Laws.context_of(trace_id, False{}, done)}, done => span_context_same(trace_id, False{}, done),
        16n, (rest, TC.SpanDraw.start(None{})))
