# Proofs: validated limits
# ========================
#
# Every Limits value obeys the rules of Limits.is_valid, and Limits.new
# succeeds exactly when they hold, keeping the budgets it was given.
# PROOF.bend proves the laws limits_bounds, limits_new and limits_fields of
# LAWS.bend with bounds, new_accepts and new_view; output_within_input reads
# the third rule for proofs/emit.bend.
#
# bounds splits the evidence stored in every Limits value with the Bool.and
# lemmas of proofs/bools.bend. Limits.new passes the result of its check to
# Limits.new.checked, and `match` cannot inspect a computed value, so
# new_step and new_view_step state their claims for any Bool `valid` given
# with an equation saying what it is, and match on `valid`. new_accepts and
# new_view then pass the check itself with `{==}`. NewView is the view of a
# result through which limits_fields is proved.

import Base
import ../trace_context.bend as TC
import ./bools.bend as BoolsProof
import ./nats.bend as NatsProof
# Every Limits value has a traceparent input budget of at least 55, an
# output budget of at least 512 and an input budget no smaller than its
# output budget: the three rules that its evidence field proves, one
# equation each. PROOF.bend proves the law limits_bounds with it.
law bounds:
  for limits: TC.Limits
  {Nat.is_ge(TC.Limits.traceparent_input(limits), 55n) == True{} : Bool} &
  {Nat.is_ge(TC.Limits.tracestate_output(limits), 512n) == True{} : Bool} &
  {Nat.is_ge(TC.Limits.tracestate_input(limits), TC.Limits.tracestate_output(limits)) == True{} : Bool}

# Limits.is_valid nests two Bool.and; and_left and and_right take it apart.
def bounds(limits):
  match limits:
    case TC.Limits{+traceparent_input, +tracestate_input, +tracestate_output, +evidence}:
      +rest = BoolsProof.and_right(Nat.is_ge(traceparent_input, 55n),
        Bool.and(Nat.is_ge(tracestate_output, 512n), Nat.is_ge(tracestate_input, tracestate_output)), evidence)
      (BoolsProof.and_left(Nat.is_ge(traceparent_input, 55n),
        Bool.and(Nat.is_ge(tracestate_output, 512n), Nat.is_ge(tracestate_input, tracestate_output)), evidence),
       (BoolsProof.and_left(Nat.is_ge(tracestate_output, 512n), Nat.is_ge(tracestate_input, tracestate_output), rest),
        BoolsProof.and_right(Nat.is_ge(tracestate_output, 512n), Nat.is_ge(tracestate_input, tracestate_output), rest)))

# When `evidence` says that `valid` is the result of Limits.is_valid for the
# three budgets, Limits.new.checked succeeds exactly when `valid` is True{}.
# Stated for any such Bool so that the proof can match on it, after which
# each case computes. new_accepts passes the check itself.
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

# Limits.new succeeds exactly when Limits.is_valid accepts the budgets.
# PROOF.bend proves the law limits_new with it; the law spells out
# Limits.is_valid, which computes to the same Bool.
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

# The view of a Limits.new result: Unit for a failure, and for a success the
# equations saying that the limits hold exactly the three budgets given.
def NewView(traceparent_input: Nat, tracestate_input: Nat, tracestate_output: Nat,
  result: Result<&2, &2, TC.LimitsError, TC.Limits>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{limits}:
      {TC.Limits.traceparent_input(limits) == traceparent_input : Nat} &
      {TC.Limits.tracestate_input(limits) == tracestate_input : Nat} &
      {TC.Limits.tracestate_output(limits) == tracestate_output : Nat}

# NewView holds of Limits.new.checked for any `valid` that `evidence`
# describes: in the True{} case the accessors read the budgets back by
# computation, and the False{} case is a failure, whose view is Unit.
# new_view passes the check itself.
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

# NewView holds of every Limits.new result. PROOF.bend proves the law
# limits_fields by rewriting its hypothesis `accepted` (Limits.new returned
# Done{limits}) into this view, which then states the budgets of `limits`.
law new_view:
  for +traceparent_input: Nat
  for +tracestate_input: Nat
  for +tracestate_output: Nat
  NewView(traceparent_input, tracestate_input, tracestate_output,
    TC.Limits.new(traceparent_input, tracestate_input, tracestate_output))

def new_view(traceparent_input, tracestate_input, tracestate_output):
  new_view_step(traceparent_input, tracestate_input, tracestate_output,
    TC.Limits.is_valid(traceparent_input, tracestate_input, tracestate_output), {==})

# The output budget is at most the input budget: the third rule of a
# validated configuration (bounds), read with NatsProof.ge_le as a <= check.
# proofs/emit.bend uses it to parse an emitted value with the same limits.
law output_within_input:
  for +limits: TC.Limits
  {Nat.is_le(TC.Limits.tracestate_output(limits), TC.Limits.tracestate_input(limits)) == True{} : Bool}

def output_within_input(limits):
  %NatsProof.ge_le(TC.Limits.tracestate_input(limits), TC.Limits.tracestate_output(limits)) : {_ == True{} : Bool}
  Pair.snd({Nat.is_ge(TC.Limits.tracestate_output(limits), 512n) == True{} : Bool},
    {Nat.is_ge(TC.Limits.tracestate_input(limits), TC.Limits.tracestate_output(limits)) == True{} : Bool},
    Pair.snd({Nat.is_ge(TC.Limits.traceparent_input(limits), 55n) == True{} : Bool},
      {Nat.is_ge(TC.Limits.tracestate_output(limits), 512n) == True{} : Bool} &
        {Nat.is_ge(TC.Limits.tracestate_input(limits), TC.Limits.tracestate_output(limits)) == True{} : Bool},
      bounds(limits)))
