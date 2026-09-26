import Base
import ../trace_context.bend as TC
import ./bools.bend as BoolsProof
# A validated configuration keeps the three rules it was checked against.
law bounds:
  for limits: TC.Limits
  {Nat.is_ge(TC.Limits.traceparent_input(limits), 55n) == True{} : Bool} &
  {Nat.is_ge(TC.Limits.tracestate_output(limits), 512n) == True{} : Bool} &
  {Nat.is_ge(TC.Limits.tracestate_input(limits), TC.Limits.tracestate_output(limits)) == True{} : Bool}

def bounds(limits):
  match limits:
    case TC.Limits{+traceparent_input, +tracestate_input, +tracestate_output, +evidence}:
      +rest = BoolsProof.and_right(Nat.is_ge(traceparent_input, 55n),
        Bool.and(Nat.is_ge(tracestate_output, 512n), Nat.is_ge(tracestate_input, tracestate_output)), evidence)
      (BoolsProof.and_left(Nat.is_ge(traceparent_input, 55n),
        Bool.and(Nat.is_ge(tracestate_output, 512n), Nat.is_ge(tracestate_input, tracestate_output)), evidence),
       (BoolsProof.and_left(Nat.is_ge(tracestate_output, 512n), Nat.is_ge(tracestate_input, tracestate_output), rest),
        BoolsProof.and_right(Nat.is_ge(tracestate_output, 512n), Nat.is_ge(tracestate_input, tracestate_output), rest)))

law new_step:
  for +traceparent_input: Nat
  for +tracestate_input: Nat
  for +tracestate_output: Nat
  for valid: Bool
  for evidence: {TC.Limits.is_valid(traceparent_input, tracestate_input, tracestate_output) == valid : Bool}
  {Result.is_done(&2, &2, TC.LimitsError, TC.Limits,
    TC.Limits.new.checked(traceparent_input, tracestate_input, tracestate_output, valid, evidence)) == valid : Bool}

def new_step(traceparent_input, tracestate_input, tracestate_output, valid, evidence):
  match valid:
    case True{}:
      {==}
    case False{}:
      {==}

law new_accepts:
  for +traceparent_input: Nat
  for +tracestate_input: Nat
  for +tracestate_output: Nat
  {Result.is_done(&2, &2, TC.LimitsError, TC.Limits,
    TC.Limits.new(traceparent_input, tracestate_input, tracestate_output)) ==
    TC.Limits.is_valid(traceparent_input, tracestate_input, tracestate_output) : Bool}

def new_accepts(traceparent_input, tracestate_input, tracestate_output):
  new_step(traceparent_input, tracestate_input, tracestate_output,
    TC.Limits.is_valid(traceparent_input, tracestate_input, tracestate_output), {==})

# What an accepted configuration keeps.
def NewView(traceparent_input: Nat, tracestate_input: Nat, tracestate_output: Nat,
  result: Result<&2, &2, TC.LimitsError, TC.Limits>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{limits}:
      {TC.Limits.traceparent_input(limits) == traceparent_input : Nat} &
      {TC.Limits.tracestate_input(limits) == tracestate_input : Nat} &
      {TC.Limits.tracestate_output(limits) == tracestate_output : Nat}

law new_view_step:
  for +traceparent_input: Nat
  for +tracestate_input: Nat
  for +tracestate_output: Nat
  for valid: Bool
  for evidence: {TC.Limits.is_valid(traceparent_input, tracestate_input, tracestate_output) == valid : Bool}
  NewView(traceparent_input, tracestate_input, tracestate_output,
    TC.Limits.new.checked(traceparent_input, tracestate_input, tracestate_output, valid, evidence))

def new_view_step(traceparent_input, tracestate_input, tracestate_output, valid, evidence):
  match valid:
    case True{}:
      ({==}, ({==}, {==}))
    case False{}:
      Unit{}

law new_view:
  for +traceparent_input: Nat
  for +tracestate_input: Nat
  for +tracestate_output: Nat
  NewView(traceparent_input, tracestate_input, tracestate_output,
    TC.Limits.new(traceparent_input, tracestate_input, tracestate_output))

def new_view(traceparent_input, tracestate_input, tracestate_output):
  new_view_step(traceparent_input, tracestate_input, tracestate_output,
    TC.Limits.is_valid(traceparent_input, tracestate_input, tracestate_output), {==})
