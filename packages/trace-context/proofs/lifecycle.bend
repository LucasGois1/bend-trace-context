# Proofs: children and restarts from supplied IDs
# ===============================================
#
# Proves the laws of section 4 of LAWS.bend about the operations on supplied
# IDs. For Context.child_from_id: a successful child keeps the parent's
# trace ID, uses the supplied span ID and the resolved sampled indication
# (law child), and creation fails exactly when the span ID reuses the
# parent's (child_reuse, child_accepts). For Context.restart_from_ids: a
# successful restart is the root of the supplied IDs (restart), and it fails
# exactly when the trace ID reuses the received one (restart_reuse,
# restart_accepts). Laws.child and Laws.restart in PROOF.bend rewrite their
# hypothesis into ChildView and RestartView; the other four Laws.* proofs
# call the lemma of the same name here.
#
# Strategy: each operation computes a reuse check, SpanId.is_eq or
# TraceId.is_eq, which compare the ID texts with String.eq, and passes it to
# a `.checked` function that matches on it. Since Bend matches only on
# parameters, each *_step lemma receives the check as a Bool, with an
# equation or a view that says what it is, and matches on it in turn. When
# the check is False, StringsProof.distinct turns it into different texts.
# The reuse laws rewrite the check into String.eq(t, t), which
# StringsProof.eq_refl makes True; the accept laws refute the True case with
# the view of StringsProof.eq_view. Reading order: ChildView, child_step,
# child_view, child_reuse, the same four for restarts, then the accept laws.

import Base
import ../trace_context.bend as TC
import ./strings.bend as StringsProof

# The view of a child creation: Unit for a failure, and for a success
# Done{child} the four facts of law child: the child keeps the parent's
# trace ID (the whole TraceId, randomness assertion included), uses
# span_id, has the sampled indication `sampled`, and its span ID text
# differs from the parent's. A failure guarantees nothing here; child_reuse
# states when creation must fail.
def ChildView(parent: TC.Parent, span_id: TC.SpanId, sampled: Bool,
  result: Result<&2, &2, TC.ContextError, TC.LocalContext>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{child}:
      {TC.LocalContext.trace_id(child) == TC.Parent.trace_id(parent) : TC.TraceId} &
      {TC.LocalContext.span_id(child) == span_id : TC.SpanId} &
      {TC.LocalContext.is_sampled(child) == sampled : Bool} &
      {TC.SpanId.to_string(span_id) != TC.SpanId.to_string(TC.Parent.span_id(parent)) : String}

# The child view holds for Context.child_from_id.checked whatever the reuse
# check reported: `reused` is any Bool, and `evidence` says it is the result
# of SpanId.is_eq(span_id, parent's span ID). When True, creation fails and
# the view is Unit. When False, the first three facts hold by computation,
# and StringsProof.distinct turns `evidence` into different texts, since
# SpanId.is_eq is String.eq of the two texts.
law child_step:
  for +parent: TC.Parent
  for +span_id: TC.SpanId
  for -sampled: Bool
  for reused: Bool
  for evidence: {TC.SpanId.is_eq(span_id, TC.Parent.span_id(parent)) == reused : Bool}
  ChildView(parent, span_id, sampled,
    TC.Context.child_from_id.checked(TC.Parent.trace_id(parent), span_id, sampled, reused))

def child_step(parent, span_id, sampled, reused, evidence):
  match reused:
    case True{}:
      Unit{}
    case False{}:
      ({==}, ({==}, ({==}, StringsProof.distinct(TC.SpanId.to_string(span_id),
        TC.SpanId.to_string(TC.Parent.span_id(parent)), evidence))))

# Every child creation satisfies the child view, with the sampled indication
# that Sampling.resolve gives. Context.child_from_id is
# child_from_id.checked applied to the reuse check, so child_step with that
# check and {==} as evidence proves it. Laws.child (PROOF.bend) rewrites its
# hypothesis into this view.
law child_view:
  for +parent: TC.Parent
  for +span_id: TC.SpanId
  for +sampling: TC.Sampling
  ChildView(parent, span_id, TC.Sampling.resolve(sampling, TC.Parent.is_sampled(parent)),
    TC.Context.child_from_id(parent, span_id, sampling))

def child_view(parent, span_id, sampling):
  child_step(parent, span_id, TC.Sampling.resolve(sampling, TC.Parent.is_sampled(parent)),
    TC.SpanId.is_eq(span_id, TC.Parent.span_id(parent)), {==})

# When the span ID's text equals the parent's, child creation fails with
# ReusedSpanId. Laws.child_reuse (PROOF.bend) calls it.
law child_reuse:
  for +parent: TC.Parent
  for +span_id: TC.SpanId
  for +sampling: TC.Sampling
  for reused: {TC.SpanId.to_string(span_id) == TC.SpanId.to_string(TC.Parent.span_id(parent)) : String}
  {TC.Context.child_from_id(parent, span_id, sampling) == Fail{TC.ReusedSpanId{}} :
    Result<&2, &2, TC.ContextError, TC.LocalContext>}

# `reused` turns the check into String.eq(t, t); eq_refl then makes it True.
def child_reuse(parent, span_id, sampling, reused):
  %Equal.sym(String, TC.SpanId.to_string(span_id), TC.SpanId.to_string(TC.Parent.span_id(parent)), reused) :
    {TC.Context.child_from_id.checked(TC.Parent.trace_id(parent), span_id,
      TC.Sampling.resolve(sampling, TC.Parent.is_sampled(parent)),
      String.eq(_, TC.SpanId.to_string(TC.Parent.span_id(parent)))) == Fail{TC.ReusedSpanId{}} :
      Result<&2, &2, TC.ContextError, TC.LocalContext>}
  %Equal.sym(Bool, String.eq(TC.SpanId.to_string(TC.Parent.span_id(parent)),
    TC.SpanId.to_string(TC.Parent.span_id(parent))), True{},
    StringsProof.eq_refl(TC.SpanId.to_string(TC.Parent.span_id(parent)))) :
    {TC.Context.child_from_id.checked(TC.Parent.trace_id(parent), span_id,
      TC.Sampling.resolve(sampling, TC.Parent.is_sampled(parent)), _) == Fail{TC.ReusedSpanId{}} :
      Result<&2, &2, TC.ContextError, TC.LocalContext>}
  {==}

# The view of a restart: Unit for a failure, and for a success
# Done{restarted} the two facts of law restart: restarted is the root of the
# supplied IDs, and the new trace ID's text differs from the received one's.
def RestartView(previous: TC.RemoteContext, trace_id: TC.TraceId, span_id: TC.SpanId,
  result: Result<&2, &2, TC.ContextError, TC.LocalContext>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{restarted}:
      {restarted == TC.Context.root_from_ids(trace_id, span_id) : TC.LocalContext} &
      {TC.TraceId.to_string(trace_id) != TC.TraceId.to_string(TC.RemoteContext.trace_id(previous)) : String}

# The restart view holds for Context.restart_from_ids.checked whatever the
# reuse check reported: `evidence` says that `reused` is the result of
# TraceId.is_eq against the received trace ID. When True, the restart fails
# and the view is Unit; when False, the restart is the root by computation,
# and StringsProof.distinct turns `evidence` into different texts.
law restart_step:
  for +previous: TC.RemoteContext
  for +trace_id: TC.TraceId
  for span_id: TC.SpanId
  for reused: Bool
  for evidence: {TC.TraceId.is_eq(trace_id, TC.RemoteContext.trace_id(previous)) == reused : Bool}
  RestartView(previous, trace_id, span_id, TC.Context.restart_from_ids.checked(trace_id, span_id, reused))

def restart_step(previous, trace_id, span_id, reused, evidence):
  match reused:
    case True{}:
      Unit{}
    case False{}:
      ({==}, StringsProof.distinct(TC.TraceId.to_string(trace_id),
        TC.TraceId.to_string(TC.RemoteContext.trace_id(previous)), evidence))

# Every restart satisfies the restart view: restart_step with the reuse
# check that Context.restart_from_ids computes and {==} as evidence.
# Laws.restart (PROOF.bend) rewrites its hypothesis into this view.
law restart_view:
  for +previous: TC.RemoteContext
  for +trace_id: TC.TraceId
  for span_id: TC.SpanId
  RestartView(previous, trace_id, span_id, TC.Context.restart_from_ids(previous, trace_id, span_id))

def restart_view(previous, trace_id, span_id):
  restart_step(previous, trace_id, span_id,
    TC.TraceId.is_eq(trace_id, TC.RemoteContext.trace_id(previous)), {==})

# When the new trace ID's text equals the received one's, the restart fails
# with ReusedTraceId, whatever the new ID's randomness assertion: TraceId.is_eq
# compares texts only. Laws.restart_reuse (PROOF.bend) calls it.
law restart_reuse:
  for +previous: TC.RemoteContext
  for +trace_id: TC.TraceId
  for span_id: TC.SpanId
  for reused: {TC.TraceId.to_string(trace_id) == TC.TraceId.to_string(TC.RemoteContext.trace_id(previous)) : String}
  {TC.Context.restart_from_ids(previous, trace_id, span_id) == Fail{TC.ReusedTraceId{}} :
    Result<&2, &2, TC.ContextError, TC.LocalContext>}

# `reused` turns the check into String.eq(t, t); eq_refl then makes it True.
def restart_reuse(previous, trace_id, span_id, reused):
  %Equal.sym(String, TC.TraceId.to_string(trace_id),
    TC.TraceId.to_string(TC.RemoteContext.trace_id(previous)), reused) :
    {TC.Context.restart_from_ids.checked(trace_id, span_id,
      String.eq(_, TC.TraceId.to_string(TC.RemoteContext.trace_id(previous)))) == Fail{TC.ReusedTraceId{}} :
      Result<&2, &2, TC.ContextError, TC.LocalContext>}
  %Equal.sym(Bool, String.eq(TC.TraceId.to_string(TC.RemoteContext.trace_id(previous)),
    TC.TraceId.to_string(TC.RemoteContext.trace_id(previous))), True{},
    StringsProof.eq_refl(TC.TraceId.to_string(TC.RemoteContext.trace_id(previous)))) :
    {TC.Context.restart_from_ids.checked(trace_id, span_id, _) == Fail{TC.ReusedTraceId{}} :
      Result<&2, &2, TC.ContextError, TC.LocalContext>}
  {==}

# When the span ID's text differs from the parent's (`distinct`), the
# checked creation succeeds with Context.from_ids, whatever `same` is, as
# long as `view` is the string view of `same` for the two texts. When
# `same` is False this is computation; when True, the view gives equal
# texts, which contradicts `distinct`, and Empty.absurd closes the case.
law child_accepts_step:
  for +parent: TC.Parent
  for +span_id: TC.SpanId
  for -sampled: Bool
  for same: Bool
  for view: StringsProof.EqView(TC.SpanId.to_string(span_id), TC.SpanId.to_string(TC.Parent.span_id(parent)), same)
  for distinct: {TC.SpanId.to_string(span_id) != TC.SpanId.to_string(TC.Parent.span_id(parent)) : String}
  {TC.Context.child_from_id.checked(TC.Parent.trace_id(parent), span_id, sampled, same) ==
    Done{TC.Context.from_ids(TC.Parent.trace_id(parent), span_id, sampled)} :
    Result<&2, &2, TC.ContextError, TC.LocalContext>}

def child_accepts_step(parent, span_id, sampled, same, view, distinct):
  match same:
    case False{}:
      {==}
    case True{}:
      Empty.absurd({TC.Context.child_from_id.checked(TC.Parent.trace_id(parent), span_id, sampled, True{}) ==
        Done{TC.Context.from_ids(TC.Parent.trace_id(parent), span_id, sampled)} :
        Result<&2, &2, TC.ContextError, TC.LocalContext>}, distinct(view))

# When the span ID's text differs from the parent's, child creation
# succeeds, and the child is exactly Context.from_ids of the parent's trace
# ID, span_id and the resolved sampled indication. Laws.child_accepts
# (PROOF.bend) calls it. The proof passes the reuse check and its view,
# from StringsProof.eq_view, to child_accepts_step.
law child_accepts:
  for +parent: TC.Parent
  for +span_id: TC.SpanId
  for +sampling: TC.Sampling
  for distinct: {TC.SpanId.to_string(span_id) != TC.SpanId.to_string(TC.Parent.span_id(parent)) : String}
  {TC.Context.child_from_id(parent, span_id, sampling) ==
    Done{TC.Context.from_ids(TC.Parent.trace_id(parent), span_id,
      TC.Sampling.resolve(sampling, TC.Parent.is_sampled(parent)))} :
    Result<&2, &2, TC.ContextError, TC.LocalContext>}

def child_accepts(parent, span_id, sampling, distinct):
  child_accepts_step(parent, span_id, TC.Sampling.resolve(sampling, TC.Parent.is_sampled(parent)),
    TC.SpanId.is_eq(span_id, TC.Parent.span_id(parent)),
    StringsProof.eq_view(TC.SpanId.to_string(span_id), TC.SpanId.to_string(TC.Parent.span_id(parent))),
    distinct)

# When the new trace ID's text differs from the received one's
# (`distinct`), the checked restart succeeds with the root of the supplied
# IDs, whatever `same` is, as long as `view` is the string view of `same`
# for the two texts. As in child_accepts_step, the True case contradicts
# `distinct`.
law restart_accepts_step:
  for +previous: TC.RemoteContext
  for +trace_id: TC.TraceId
  for -span_id: TC.SpanId
  for same: Bool
  for view: StringsProof.EqView(TC.TraceId.to_string(trace_id),
    TC.TraceId.to_string(TC.RemoteContext.trace_id(previous)), same)
  for distinct: {TC.TraceId.to_string(trace_id) != TC.TraceId.to_string(TC.RemoteContext.trace_id(previous)) : String}
  {TC.Context.restart_from_ids.checked(trace_id, span_id, same) ==
    Done{TC.Context.root_from_ids(trace_id, span_id)} : Result<&2, &2, TC.ContextError, TC.LocalContext>}

def restart_accepts_step(previous, trace_id, span_id, same, view, distinct):
  match same:
    case False{}:
      {==}
    case True{}:
      Empty.absurd({TC.Context.restart_from_ids.checked(trace_id, span_id, True{}) ==
        Done{TC.Context.root_from_ids(trace_id, span_id)} : Result<&2, &2, TC.ContextError, TC.LocalContext>},
        distinct(view))

# When the new trace ID's text differs from the received one's, the restart
# succeeds with exactly Context.root_from_ids(trace_id, span_id).
# Laws.restart_accepts (PROOF.bend) calls it. The proof passes the reuse
# check and its view, from StringsProof.eq_view, to restart_accepts_step.
law restart_accepts:
  for +previous: TC.RemoteContext
  for +trace_id: TC.TraceId
  for span_id: TC.SpanId
  for distinct: {TC.TraceId.to_string(trace_id) != TC.TraceId.to_string(TC.RemoteContext.trace_id(previous)) : String}
  {TC.Context.restart_from_ids(previous, trace_id, span_id) == Done{TC.Context.root_from_ids(trace_id, span_id)} :
    Result<&2, &2, TC.ContextError, TC.LocalContext>}

def restart_accepts(previous, trace_id, span_id, distinct):
  restart_accepts_step(previous, trace_id, span_id,
    TC.TraceId.is_eq(trace_id, TC.RemoteContext.trace_id(previous)),
    StringsProof.eq_view(TC.TraceId.to_string(trace_id), TC.TraceId.to_string(TC.RemoteContext.trace_id(previous))),
    distinct)
