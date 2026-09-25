import Base
import ../trace_context.bend as TC
import ./strings.bend as StringsProof
import ../src/digits.bend as Digits

def Tape() -> Type:
  List<&1, Result<&1, &1, U32 & String, U32>>

def TapeStep() -> Type:
  Tape() & TC.Step

# The value an IO action produces when every effect in it is pure.
def Observe(-A: Type, action: IO(A)) -> IO.OP<A>:
  action(A, value => Emit{value})

# The IO driver reading a tape performs exactly the pure tape driver: the same
# words are read, in the same order, and the same generation state results.
law read_tape:
  for +fuel: Nat
  for current: TapeStep()
  {Observe(TapeStep(), TC.Draw.read(~Tape(), ~TC.Source.tape, fuel, current)) ==
    Emit{TC.Draw.run(fuel, current)} : IO.OP<TapeStep()>}

def read_tape(fuel, current):
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
      read_tape(p, TC.Draw.fed_by(Tape(), TC.Tape.next(tape), draw))

# A generation ends after at most `n` more successful words, whatever they
# are. A failed word ends it at once (law feed_failure), so this bounds every
# source.
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

law within_four:
  for +n: Nat
  for +step: TC.Step
  for bound: Within(step, n)
  Within(step, 4n+n)

def within_four(n, step, bound):
  within_succ(3n+n, step, within_succ(2n+n, step, within_succ(1n+n, step, within_succ(n, step, bound))))

# Span ID draws: eight candidates of two words.
def span_budget(remaining: Nat) -> Nat:
  match remaining:
    case 0n:
      2n
    case 1n+p:
      2n+span_budget(p)

# The bound left once a span ID candidate has been read.
def span_after(remaining: Nat) -> Nat:
  match remaining:
    case 0n:
      0n
    case 1n+p:
      span_budget(p)

def SpanRetry(+remaining: Nat, plan: TC.SpanPlan) -> Type:
  match remaining:
    case 0n:
      Unit
    case 1n+p:
      Within(TC.NeedWord{TC.DrawSpan{p, TC.NoSpanWord{}, plan}}, span_budget(p))

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

law span_accept_within:
  for -id: TC.SpanId
  for +plan: TC.SpanPlan
  for -remaining: Nat
  Within(TC.Draw.accept_span(id, plan), span_after(remaining))

def span_accept_within(id, plan, remaining):
  match plan:
    case TC.SpanPlan{trace_id, sampled, parent}:
      Unit{}

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

law span_second_within:
  for +remaining: Nat
  for +plan: TC.SpanPlan
  for retry: SpanRetry(remaining, plan)
  for +first: U32
  Within(TC.NeedWord{TC.DrawSpan{remaining, TC.OneSpanWord{first}, plan}}, 1n+span_after(remaining))

def span_second_within(remaining, plan, retry, first):
  +second => span_check_within(TC.SpanId.from_words(first, second), plan, remaining, retry)

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

# Trace ID draws: eight candidates of four words, then the span ID draw.
def trace_budget(remaining: Nat) -> Nat:
  match remaining:
    case 0n:
      20n
    case 1n+p:
      4n+trace_budget(p)

# The bound left once a trace ID candidate has been read: the span ID draw's
# sixteen words after the eighth candidate, the next candidates' budget otherwise.
def trace_after(remaining: Nat) -> Nat:
  match remaining:
    case 0n:
      16n
    case 1n+p:
      trace_budget(p)

def TraceRetry(+remaining: Nat, previous: Maybe<&2, TC.TraceId>) -> Type:
  match remaining:
    case 0n:
      Unit
    case 1n+p:
      Within(TC.NeedWord{TC.DrawTrace{p, TC.NoTraceWord{}, previous}}, trace_budget(p))

# Every trace budget covers the sixteen words of a span ID draw.
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

law trace_second_within:
  for +remaining: Nat
  for +previous: Maybe<&2, TC.TraceId>
  for retry: TraceRetry(remaining, previous)
  for +first: U32
  Within(TC.NeedWord{TC.DrawTrace{remaining, TC.OneTraceWord{first}, previous}}, 3n+trace_after(remaining))

def trace_second_within(remaining, previous, retry, first):
  +second => trace_third_within(remaining, previous, retry, first, second)

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

law root_within:
  Within(TC.Draw.root(), 48n)

def root_within():
  trace_start_within(7n, None{})

law restart_within:
  for previous: TC.RemoteContext
  Within(TC.Draw.restart(previous), 48n)

def restart_within(previous):
  trace_start_within(7n, Some{TC.RemoteContext.trace_id(previous)})

law child_within:
  for +parent: TC.Parent
  for sampling: TC.Sampling
  Within(TC.Draw.child(parent, sampling), 16n)

def child_within(parent, sampling):
  span_start_within(7n, TC.SpanPlan{TC.Parent.trace_id(parent),
    TC.Sampling.resolve(sampling, TC.Parent.is_sampled(parent)), Some{TC.Parent.span_id(parent)}})

law ended_stays:
  for +fuel: Nat
  for tape: Tape()
  for +step: TC.Step
  for ended: {TC.Step.is_finished(step) == True{} : Bool}
  {TC.Draw.ended(TC.Draw.run(fuel, (tape, step))) == True{} : Bool}

def ended_stays(fuel, tape, step, ended):
  match fuel step:
    case 0n TC.Created{context}:
      {==}
    case 0n TC.Failed{error}:
      {==}
    case 0n TC.NeedWord{draw}:
      Empty.absurd({TC.Draw.ended(TC.Draw.run(0n, (tape, TC.NeedWord{draw}))) == True{} : Bool},
        StringsProof.true_ne_false(Equal.sym(Bool, False{}, True{}, ended)))
    case 1n+p TC.Created{context}:
      {==}
    case 1n+p TC.Failed{error}:
      {==}
    case 1n+p TC.NeedWord{draw}:
      Empty.absurd({TC.Draw.ended(TC.Draw.run(1n+p, (tape, TC.NeedWord{draw}))) == True{} : Bool},
        StringsProof.true_ne_false(Equal.sym(Bool, False{}, True{}, ended)))

# Driving a generation with enough fuel ends it, whatever the tape holds.
law run_ends:
  for +fuel: Nat
  for +step: TC.Step
  for tape: Tape()
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

law run_failed:
  for fuel: Nat
  for tape: Tape()
  for error: TC.GenerationError
  {TC.Draw.run(fuel, (tape, TC.Failed{error})) == (tape, TC.Failed{error}) : TapeStep()}

def run_failed(fuel, tape, error):
  match fuel:
    case 0n:
      {==}
    case 1n+p:
      {==}

# Maybe discrimination for refuting impossible plans.
def MaybeTraceClash(value: Maybe<&2, TC.TraceId>) -> Type:
  match value:
    case None{}:
      Empty
    case Some{id}:
      Unit

law trace_some_ne_none:
  for -id: TC.TraceId
  for clash: {Some{id} == None{} : Maybe<&2, TC.TraceId>}
  Empty

def trace_some_ne_none(id, clash):
  %clash : MaybeTraceClash(_)
  Unit{}

def MaybeSpanClash(value: Maybe<&2, TC.SpanId>) -> Type:
  match value:
    case None{}:
      Empty
    case Some{id}:
      Unit

law span_some_ne_none:
  for -id: TC.SpanId
  for clash: {Some{id} == None{} : Maybe<&2, TC.SpanId>}
  Empty

def span_some_ne_none(id, clash):
  %clash : MaybeSpanClash(_)
  Unit{}

# Every generated trace ID candidate asserts random-trace-id.
def RandomCandidate(candidate: Maybe<&2, TC.TraceId>) -> Type:
  match candidate:
    case None{}:
      Unit
    case Some{id}:
      {TC.TraceId.is_random(id) == True{} : Bool}

law asserted_random:
  for candidate: Maybe<&2, TC.TraceId>
  RandomCandidate(TC.Draw.asserted(candidate))

def asserted_random(candidate):
  match candidate:
    case None{}:
      Unit{}
    case Some{id}:
      match id:
        case TC.TraceId{value, random}:
          {==}

# Roots: every state keeps a random trace ID, sampled 0 and no parent.
def RootPlan(plan: TC.SpanPlan) -> Type:
  match plan:
    case TC.SpanPlan{trace_id, sampled, parent}:
      {TC.TraceId.is_random(trace_id) == True{} : Bool} & {sampled == False{} : Bool} &
      {parent == None{} : Maybe<&2, TC.SpanId>}

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

def RootRun(result: TapeStep()) -> Type:
  match result:
    case Tuple{tape, step}:
      RootInv(step)

law root_run:
  for +fuel: Nat
  for +step: TC.Step
  for tape: Tape()
  for valid: RootInv(step)
  RootRun(TC.Draw.run(fuel, (tape, step)))

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
              %Equal.sym(TapeStep(), TC.Draw.run(p, (Nil{}, TC.Failed{TC.SourceFailure{1, "tape-exhausted"}})),
                (Nil{}, TC.Failed{TC.SourceFailure{1, "tape-exhausted"}}),
                run_failed(p, Nil{}, TC.SourceFailure{1, "tape-exhausted"})) : RootRun(_)
              Unit{}
            case Con{Fail{(code, message)}, rest}:
              %Equal.sym(TapeStep(), TC.Draw.run(p, (rest, TC.Failed{TC.SourceFailure{code, message}})),
                (rest, TC.Failed{TC.SourceFailure{code, message}}),
                run_failed(p, rest, TC.SourceFailure{code, message})) : RootRun(_)
              Unit{}
            case Con{Done{+word}, rest}:
              root_run(p, TC.Draw.feed(Done{word}, draw), rest, root_feed(word, draw, valid))

law span_none_ne_some:
  for -id: TC.SpanId
  for clash: {None{} == Some{id} : Maybe<&2, TC.SpanId>}
  Empty

def span_none_ne_some(id, clash):
  span_some_ne_none(id, Equal.sym(Maybe<&2, TC.SpanId>, None{}, Some{id}, clash))

law span_some_injective:
  for +old: TC.SpanId
  for -other: TC.SpanId
  for same: {Some{old} == Some{other} : Maybe<&2, TC.SpanId>}
  {old == other : TC.SpanId}

def span_some_injective(old, other, same):
  Equal.cong(Maybe<&2, TC.SpanId>, TC.SpanId, value => Maybe.default(&2, TC.SpanId, value, old),
    Some{old}, Some{other}, same)

# Children: every state keeps the parent's trace ID, the resolved sampled
# indication and the parent's span ID as the one not to reuse.
def ChildPlan(+parent: TC.Parent, sampling: TC.Sampling, plan: TC.SpanPlan) -> Type:
  match plan:
    case TC.SpanPlan{trace_id, sampled, excluded}:
      {trace_id == TC.Parent.trace_id(parent) : TC.TraceId} &
      {sampled == TC.Sampling.resolve(sampling, TC.Parent.is_sampled(parent)) : Bool} &
      {excluded == Some{TC.Parent.span_id(parent)} : Maybe<&2, TC.SpanId>}

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

# A span ID that compares unequal to the excluded one differs from the parent's.
law span_distinct:
  for +id: TC.SpanId
  for +old: TC.SpanId
  for -other: TC.SpanId
  for different: {TC.SpanId.is_eq(id, old) == False{} : Bool}
  for same: {Some{old} == Some{other} : Maybe<&2, TC.SpanId>}
  {TC.SpanId.to_string(id) != TC.SpanId.to_string(other) : String}

def span_distinct(id, old, other, different, same):
  %span_some_injective(old, other, same) : {TC.SpanId.to_string(id) != TC.SpanId.to_string(_) : String}
  StringsProof.distinct(TC.SpanId.to_string(id), TC.SpanId.to_string(old), different)

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

def ChildRun(+parent: TC.Parent, sampling: TC.Sampling, result: TapeStep()) -> Type:
  match result:
    case Tuple{tape, step}:
      ChildInv(parent, sampling, step)

law child_run:
  for +parent: TC.Parent
  for -sampling: TC.Sampling
  for +fuel: Nat
  for +step: TC.Step
  for tape: Tape()
  for valid: ChildInv(parent, sampling, step)
  ChildRun(parent, sampling, TC.Draw.run(fuel, (tape, step)))

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
              %Equal.sym(TapeStep(), TC.Draw.run(p, (Nil{}, TC.Failed{TC.SourceFailure{1, "tape-exhausted"}})),
                (Nil{}, TC.Failed{TC.SourceFailure{1, "tape-exhausted"}}),
                run_failed(p, Nil{}, TC.SourceFailure{1, "tape-exhausted"})) : ChildRun(parent, sampling, _)
              Unit{}
            case Con{Fail{(code, message)}, rest}:
              %Equal.sym(TapeStep(), TC.Draw.run(p, (rest, TC.Failed{TC.SourceFailure{code, message}})),
                (rest, TC.Failed{TC.SourceFailure{code, message}}),
                run_failed(p, rest, TC.SourceFailure{code, message})) : ChildRun(parent, sampling, _)
              Unit{}
            case Con{Done{+word}, rest}:
              child_run(parent, sampling, p, TC.Draw.feed(Done{word}, draw), rest,
                child_feed(parent, sampling, word, draw, valid))

law trace_none_ne_some:
  for -id: TC.TraceId
  for clash: {None{} == Some{id} : Maybe<&2, TC.TraceId>}
  Empty

def trace_none_ne_some(id, clash):
  trace_some_ne_none(id, Equal.sym(Maybe<&2, TC.TraceId>, None{}, Some{id}, clash))

law trace_some_injective:
  for +old: TC.TraceId
  for -other: TC.TraceId
  for same: {Some{old} == Some{other} : Maybe<&2, TC.TraceId>}
  {old == other : TC.TraceId}

def trace_some_injective(old, other, same):
  Equal.cong(Maybe<&2, TC.TraceId>, TC.TraceId, value => Maybe.default(&2, TC.TraceId, value, old),
    Some{old}, Some{other}, same)

law trace_distinct:
  for +id: TC.TraceId
  for +old: TC.TraceId
  for -other: TC.TraceId
  for different: {TC.TraceId.is_eq(id, old) == False{} : Bool}
  for same: {Some{old} == Some{other} : Maybe<&2, TC.TraceId>}
  {TC.TraceId.to_string(id) != TC.TraceId.to_string(other) : String}

def trace_distinct(id, old, other, different, same):
  %trace_some_injective(old, other, same) : {TC.TraceId.to_string(id) != TC.TraceId.to_string(_) : String}
  StringsProof.distinct(TC.TraceId.to_string(id), TC.TraceId.to_string(old), different)

# Restarts: the trace ID differs from the received one, asserts randomness,
# and the root defaults apply.
def RestartPlan(+previous: TC.RemoteContext, plan: TC.SpanPlan) -> Type:
  match plan:
    case TC.SpanPlan{trace_id, sampled, excluded}:
      {TC.TraceId.to_string(trace_id) != TC.TraceId.to_string(TC.RemoteContext.trace_id(previous)) : String} &
      {TC.TraceId.is_random(trace_id) == True{} : Bool} & {sampled == False{} : Bool} &
      {excluded == None{} : Maybe<&2, TC.SpanId>}

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

def RestartRun(+previous: TC.RemoteContext, result: TapeStep()) -> Type:
  match result:
    case Tuple{tape, step}:
      RestartInv(previous, step)

law restart_run:
  for +previous: TC.RemoteContext
  for +fuel: Nat
  for +step: TC.Step
  for tape: Tape()
  for valid: RestartInv(previous, step)
  RestartRun(previous, TC.Draw.run(fuel, (tape, step)))

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
              %Equal.sym(TapeStep(), TC.Draw.run(p, (Nil{}, TC.Failed{TC.SourceFailure{1, "tape-exhausted"}})),
                (Nil{}, TC.Failed{TC.SourceFailure{1, "tape-exhausted"}}),
                run_failed(p, Nil{}, TC.SourceFailure{1, "tape-exhausted"})) : RestartRun(previous, _)
              Unit{}
            case Con{Fail{(code, message)}, rest}:
              %Equal.sym(TapeStep(), TC.Draw.run(p, (rest, TC.Failed{TC.SourceFailure{code, message}})),
                (rest, TC.Failed{TC.SourceFailure{code, message}}),
                run_failed(p, rest, TC.SourceFailure{code, message})) : RestartRun(previous, _)
              Unit{}
            case Con{Done{+word}, rest}:
              restart_run(previous, p, TC.Draw.feed(Done{word}, draw), rest,
                restart_feed(previous, word, draw, valid))

# The same refinement for any continuation of the driver.
law read_tape_then:
  for -R: Type
  for next: TapeStep() -> IO.OP<R>
  for +fuel: Nat
  for current: TapeStep()
  {TC.Draw.read(~Tape(), ~TC.Source.tape, fuel, current)(R, next) == next(TC.Draw.run(fuel, current)) : IO.OP<R>}

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
      read_tape_then(R, next, p, TC.Draw.fed_by(Tape(), TC.Tape.next(tape), draw))

def TapeOutcome() -> Type:
  Tape() & Result<&2, &2, TC.GenerationError, TC.LocalContext>

law root_tape:
  for tape: Tape()
  {Observe(TapeOutcome(), TC.Context.root_with(~Tape(), ~TC.Source.tape, tape)) ==
    Emit{TC.Draw.outcome(Tape(), TC.Draw.run(48n, (tape, TC.Draw.root())))} : IO.OP<TapeOutcome()>}

def root_tape(tape):
  read_tape_then(TapeOutcome(), done => Emit{TC.Draw.outcome(Tape(), done)}, 48n, (tape, TC.Draw.root()))

law child_tape:
  for tape: Tape()
  for parent: TC.Parent
  for sampling: TC.Sampling
  {Observe(TapeOutcome(), TC.Context.child_with(~Tape(), ~TC.Source.tape, tape, parent, sampling)) ==
    Emit{TC.Draw.outcome(Tape(), TC.Draw.run(16n, (tape, TC.Draw.child(parent, sampling))))} : IO.OP<TapeOutcome()>}

def child_tape(tape, parent, sampling):
  read_tape_then(TapeOutcome(), done => Emit{TC.Draw.outcome(Tape(), done)}, 16n,
    (tape, TC.Draw.child(parent, sampling)))

law restart_tape:
  for tape: Tape()
  for previous: TC.RemoteContext
  {Observe(TapeOutcome(), TC.Context.restart_with(~Tape(), ~TC.Source.tape, tape, previous)) ==
    Emit{TC.Draw.outcome(Tape(), TC.Draw.run(48n, (tape, TC.Draw.restart(previous))))} : IO.OP<TapeOutcome()>}

def restart_tape(tape, previous):
  read_tape_then(TapeOutcome(), done => Emit{TC.Draw.outcome(Tape(), done)}, 48n,
    (tape, TC.Draw.restart(previous)))

def zeros(count: Nat) -> Tape():
  match count:
    case 0n:
      Nil{}
    case 1n+p:
      Con{Done{0}, zeros(p)}

# Eight zero candidates exhaust the trace ID; the words after them are not read.
law root_exhaustion:
  for rest: Tape()
  {TC.Draw.run(48n, (List.append(&1, Result<&1, &1, U32 & String, U32>, zeros(32n), rest), TC.Draw.root())) ==
    (rest, TC.Failed{TC.ExhaustedTraceId{}}) : TapeStep()}

def root_exhaustion(rest):
  {==}

# Eight zero candidates exhaust a child's span ID; the words after them are not read.
law child_exhaustion:
  for parent: TC.Parent
  for sampling: TC.Sampling
  for rest: Tape()
  {TC.Draw.run(16n, (List.append(&1, Result<&1, &1, U32 & String, U32>, zeros(16n), rest),
    TC.Draw.child(parent, sampling))) == (rest, TC.Failed{TC.ExhaustedSpanId{}}) : TapeStep()}

def child_exhaustion(parent, sampling, rest):
  {==}
