import Base
import ../trace_context.bend as TC
import ./strings.bend as StringsProof

# What a successful child creation guarantees. A failed one guarantees nothing
# here; the reuse laws state when creation must fail.
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

law child_view:
  for +parent: TC.Parent
  for +span_id: TC.SpanId
  for +sampling: TC.Sampling
  ChildView(parent, span_id, TC.Sampling.resolve(sampling, TC.Parent.is_sampled(parent)),
    TC.Context.child_from_id(parent, span_id, sampling))

def child_view(parent, span_id, sampling):
  child_step(parent, span_id, TC.Sampling.resolve(sampling, TC.Parent.is_sampled(parent)),
    TC.SpanId.is_eq(span_id, TC.Parent.span_id(parent)), {==})

law child_reuse:
  for +parent: TC.Parent
  for +span_id: TC.SpanId
  for +sampling: TC.Sampling
  for reused: {TC.SpanId.to_string(span_id) == TC.SpanId.to_string(TC.Parent.span_id(parent)) : String}
  {TC.Context.child_from_id(parent, span_id, sampling) == Fail{TC.ReusedSpanId{}} :
    Result<&2, &2, TC.ContextError, TC.LocalContext>}

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

# What a successful restart guarantees.
def RestartView(previous: TC.RemoteContext, trace_id: TC.TraceId, span_id: TC.SpanId,
  result: Result<&2, &2, TC.ContextError, TC.LocalContext>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{restarted}:
      {restarted == TC.Context.root_from_ids(trace_id, span_id) : TC.LocalContext} &
      {TC.TraceId.to_string(trace_id) != TC.TraceId.to_string(TC.RemoteContext.trace_id(previous)) : String}

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

law restart_view:
  for +previous: TC.RemoteContext
  for +trace_id: TC.TraceId
  for span_id: TC.SpanId
  RestartView(previous, trace_id, span_id, TC.Context.restart_from_ids(previous, trace_id, span_id))

def restart_view(previous, trace_id, span_id):
  restart_step(previous, trace_id, span_id,
    TC.TraceId.is_eq(trace_id, TC.RemoteContext.trace_id(previous)), {==})

law restart_reuse:
  for +previous: TC.RemoteContext
  for +trace_id: TC.TraceId
  for span_id: TC.SpanId
  for reused: {TC.TraceId.to_string(trace_id) == TC.TraceId.to_string(TC.RemoteContext.trace_id(previous)) : String}
  {TC.Context.restart_from_ids(previous, trace_id, span_id) == Fail{TC.ReusedTraceId{}} :
    Result<&2, &2, TC.ContextError, TC.LocalContext>}

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
