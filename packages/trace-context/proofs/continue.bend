# Proofs: continuing or starting, and sending
# ===========================================
#
# What Context.continue_or_start_with and Context.send_with of
# trace_context.bend do over a replayed tape. PROOF.bend proves the laws of
# section 14 of LAWS.bend with the lemmas of the same names.
#
# Each operation is a few IO binds around one generation (Context.child_with,
# root_with or restart_with), and IO is a continuation-passing type. Once the
# extraction's context or the service is known, by a rewrite with the law's
# hypothesis or a match, the operation reduces to Draw.read over Source.tape
# followed by a continuation that emits a pure function of the generation's
# outcome. A step lemma (continuing_step, starting_step, sending_step,
# started_keeps or reported_step) shows, for every outcome, that this
# function gives what LAWS.bend states, and GenerationProof.read_tape_outcome
# applies it to the outcome of the pure driver Draw.run. A service without an
# operation reads no word: for it, send_untraced needs only fallback_step,
# and send_reports_generated only unreported.

import Base
import ../LAWS.bend as Laws
import ../trace_context.bend as TC
import ./generation.bend as GenerationProof

# The package's handling of a continued context's outcome under `policy` is
# Laws.continuing. By cases on the policy and the outcome; each case
# computes.
law continuing_step:
  for +policy: TC.FailurePolicy
  for +state: TC.TraceState
  for +received: Maybe<&2, TC.IncomingContext>
  for outcome: Laws.TapeOutcome()
  {TC.Policy.apply.done(Laws.Tape(), policy, TC.Service, TC.Serve.strict,
    TC.Serve.from_child.done(Laws.Tape(), state, received, outcome)) ==
    Laws.continuing(policy, state, received, outcome) : Laws.TapeService(policy)}

def continuing_step(policy, state, received, outcome):
  match policy outcome:
    case TC.Lenient{} Tuple{rest, Fail{error}}:
      {==}
    case TC.Lenient{} Tuple{rest, Done{context}}:
      {==}
    case TC.Strict{} Tuple{rest, Fail{error}}:
      {==}
    case TC.Strict{} Tuple{rest, Done{context}}:
      {==}

# Law continue_usable: with `usable`, continuing reduces to the generation
# of a child of `base` followed by the package's continuation, which agrees
# with Laws.continuing on every outcome (continuing_step,
# GenerationProof.read_tape_outcome).
law continue_usable:
  for tape: Laws.Tape()
  for +extraction: TC.Extraction
  for +base: TC.BaseContext
  for +sampling: TC.Sampling
  for +policy: TC.FailurePolicy
  for usable: {TC.Extraction.context(extraction) == Some{base} : Maybe<&2, TC.BaseContext>}
  {Laws.Observe(Laws.TapeService(policy), TC.Context.continue_or_start_with(~Laws.Tape(), ~TC.Source.tape, tape,
    extraction, TC.Continue{}, sampling, policy)) ==
    Emit{Laws.continuing(policy, TC.BaseContext.state(base), TC.Extraction.incoming(extraction),
      TC.Draw.outcome(Laws.Tape(), TC.Draw.run(16n, (tape, TC.Draw.child(TC.BaseContext.parent(base), sampling)))))} :
    IO.OP<Laws.TapeService(policy)>}

def continue_usable(tape, extraction, base, sampling, policy, usable):
  +state = TC.BaseContext.state(base)
  +received = TC.Extraction.incoming(extraction)
  %Equal.sym(Maybe<&2, TC.BaseContext>, TC.Extraction.context(extraction), Some{base}, usable) :
    {TC.Serve.kept(~Laws.Tape(), ~TC.Source.tape, tape, _, received, TC.Continue{}, sampling)(Laws.TapeService(policy),
      done => Emit{TC.Policy.apply.done(Laws.Tape(), policy, TC.Service, TC.Serve.strict, done)}) ==
      Emit{Laws.continuing(policy, state, received, TC.Draw.outcome(Laws.Tape(),
        TC.Draw.run(16n, (tape, TC.Draw.child(TC.BaseContext.parent(base), sampling)))))} :
      IO.OP<Laws.TapeService(policy)>}
  GenerationProof.read_tape_outcome(Laws.TapeService(policy),
    outcome => TC.Policy.apply.done(Laws.Tape(), policy, TC.Service, TC.Serve.strict,
      TC.Serve.from_child.done(Laws.Tape(), state, received, outcome)),
    outcome => Laws.continuing(policy, state, received, outcome),
    outcome => continuing_step(policy, state, received, outcome),
    16n, (tape, TC.Draw.child(TC.BaseContext.parent(base), sampling)))

# The package's handling of a new trace's outcome under `policy` is
# Laws.starting. By cases on the policy and the outcome; each case
# computes.
law starting_step:
  for +policy: TC.FailurePolicy
  for +origin: TC.Origin
  for +sampling: TC.Sampling
  for outcome: Laws.TapeOutcome()
  {TC.Policy.apply.done(Laws.Tape(), policy, TC.Service, TC.Serve.strict,
    TC.Serve.from_start.done(Laws.Tape(), origin, sampling, outcome)) ==
    Laws.starting(policy, origin, sampling, outcome) : Laws.TapeService(policy)}

def starting_step(policy, origin, sampling, outcome):
  match policy outcome:
    case TC.Lenient{} Tuple{rest, Fail{error}}:
      {==}
    case TC.Lenient{} Tuple{rest, Done{context}}:
      {==}
    case TC.Strict{} Tuple{rest, Fail{error}}:
      {==}
    case TC.Strict{} Tuple{rest, Done{context}}:
      {==}

# A new trace's generation, a root or a restart, followed by the package's
# continuation gives Laws.starting of the pure driver's outcome
# (starting_step, GenerationProof.read_tape_outcome). Used by start_unusable
# and restart_usable.
law starting_read:
  for +policy: TC.FailurePolicy
  for +origin: TC.Origin
  for +sampling: TC.Sampling
  for current: Laws.TapeStep()
  {TC.Draw.read(~Laws.Tape(), ~TC.Source.tape, 48n, current)(Laws.TapeService(policy),
    step => Emit{TC.Policy.apply.done(Laws.Tape(), policy, TC.Service, TC.Serve.strict,
      TC.Serve.from_start.done(Laws.Tape(), origin, sampling, TC.Draw.outcome(Laws.Tape(), step)))}) ==
    Emit{Laws.starting(policy, origin, sampling, TC.Draw.outcome(Laws.Tape(), TC.Draw.run(48n, current)))} :
    IO.OP<Laws.TapeService(policy)>}

def starting_read(policy, origin, sampling, current):
  GenerationProof.read_tape_outcome(Laws.TapeService(policy),
    outcome => TC.Policy.apply.done(Laws.Tape(), policy, TC.Service, TC.Serve.strict,
      TC.Serve.from_start.done(Laws.Tape(), origin, sampling, outcome)),
    outcome => Laws.starting(policy, origin, sampling, outcome),
    outcome => starting_step(policy, origin, sampling, outcome),
    48n, current)

# Law restart_usable: with `usable`, a boundary reduces to the generation of
# a restart of the context that `base` replaces. By cases on the base, for
# which the package's and LAWS.bend's replaced context compute alike; then
# starting_read.
law restart_usable:
  for tape: Laws.Tape()
  for +extraction: TC.Extraction
  for +base: TC.BaseContext
  for +sampling: TC.Sampling
  for +policy: TC.FailurePolicy
  for usable: {TC.Extraction.context(extraction) == Some{base} : Maybe<&2, TC.BaseContext>}
  {Laws.Observe(Laws.TapeService(policy), TC.Context.continue_or_start_with(~Laws.Tape(), ~TC.Source.tape, tape,
    extraction, TC.Restart{}, sampling, policy)) ==
    Emit{Laws.starting(policy, TC.Restarted{}, sampling, TC.Draw.outcome(Laws.Tape(),
      TC.Draw.run(48n, (tape, TC.Draw.restart(Laws.replaced(base))))))} : IO.OP<Laws.TapeService(policy)>}

def restart_usable(tape, extraction, base, sampling, policy, usable):
  match base:
    case TC.IncomingBase{+incoming}:
      %Equal.sym(Maybe<&2, TC.BaseContext>, TC.Extraction.context(extraction), Some{TC.IncomingBase{incoming}}, usable) :
        {TC.Serve.kept(~Laws.Tape(), ~TC.Source.tape, tape, _, TC.Extraction.incoming(extraction), TC.Restart{},
          sampling)(Laws.TapeService(policy), done => Emit{TC.Policy.apply.done(Laws.Tape(), policy, TC.Service,
            TC.Serve.strict, done)}) ==
          Emit{Laws.starting(policy, TC.Restarted{}, sampling, TC.Draw.outcome(Laws.Tape(),
            TC.Draw.run(48n, (tape, TC.Draw.restart(TC.IncomingContext.context(incoming))))))} :
          IO.OP<Laws.TapeService(policy)>}
      starting_read(policy, TC.Restarted{}, sampling, (tape, TC.Draw.restart(TC.IncomingContext.context(incoming))))
    case TC.OutgoingBase{+outgoing}:
      +previous = TC.RemoteContext.from_traceparent(TC.LocalContext.to_traceparent(TC.OutgoingContext.context(outgoing)))
      %Equal.sym(Maybe<&2, TC.BaseContext>, TC.Extraction.context(extraction), Some{TC.OutgoingBase{outgoing}}, usable) :
        {TC.Serve.kept(~Laws.Tape(), ~TC.Source.tape, tape, _, TC.Extraction.incoming(extraction), TC.Restart{},
          sampling)(Laws.TapeService(policy), done => Emit{TC.Policy.apply.done(Laws.Tape(), policy, TC.Service,
            TC.Serve.strict, done)}) ==
          Emit{Laws.starting(policy, TC.Restarted{}, sampling, TC.Draw.outcome(Laws.Tape(),
            TC.Draw.run(48n, (tape, TC.Draw.restart(previous)))))} : IO.OP<Laws.TapeService(policy)>}
      starting_read(policy, TC.Restarted{}, sampling, (tape, TC.Draw.restart(previous)))

# Law start_unusable: with `none`, the service reduces to the generation of
# a root whatever the reception, since the package looks at the kept context
# first; then starting_read.
law start_unusable:
  for tape: Laws.Tape()
  for +extraction: TC.Extraction
  for reception: TC.Reception
  for +sampling: TC.Sampling
  for +policy: TC.FailurePolicy
  for none: {TC.Extraction.context(extraction) == None{} : Maybe<&2, TC.BaseContext>}
  {Laws.Observe(Laws.TapeService(policy), TC.Context.continue_or_start_with(~Laws.Tape(), ~TC.Source.tape, tape,
    extraction, reception, sampling, policy)) ==
    Emit{Laws.starting(policy, TC.Started{}, sampling, TC.Draw.outcome(Laws.Tape(),
      TC.Draw.run(48n, (tape, TC.Draw.root()))))} : IO.OP<Laws.TapeService(policy)>}

def start_unusable(tape, extraction, reception, sampling, policy, none):
  %Equal.sym(Maybe<&2, TC.BaseContext>, TC.Extraction.context(extraction), None{}, none) :
    {TC.Serve.kept(~Laws.Tape(), ~TC.Source.tape, tape, _, TC.Extraction.incoming(extraction), reception,
      sampling)(Laws.TapeService(policy), done => Emit{TC.Policy.apply.done(Laws.Tape(), policy, TC.Service,
        TC.Serve.strict, done)}) ==
      Emit{Laws.starting(policy, TC.Started{}, sampling, TC.Draw.outcome(Laws.Tape(),
        TC.Draw.run(48n, (tape, TC.Draw.root()))))} : IO.OP<Laws.TapeService(policy)>}
  starting_read(policy, TC.Started{}, sampling, (tape, TC.Draw.root()))

# A new trace keeps nothing of a received context, whatever its outcome and
# the policy. By cases on the policy and the outcome; each case computes.
law started_keeps:
  for +policy: TC.FailurePolicy
  for +origin: TC.Origin
  for +sampling: TC.Sampling
  for outcome: Laws.TapeOutcome()
  {Laws.kept_nothing(policy, TC.Policy.apply.done(Laws.Tape(), policy, TC.Service, TC.Serve.strict,
    TC.Serve.from_start.done(Laws.Tape(), origin, sampling, outcome))) == True{} : Bool}

def started_keeps(policy, origin, sampling, outcome):
  match policy outcome:
    case TC.Lenient{} Tuple{rest, Fail{error}}:
      {==}
    case TC.Lenient{} Tuple{rest, Done{context}}:
      {==}
    case TC.Strict{} Tuple{rest, Fail{error}}:
      {==}
    case TC.Strict{} Tuple{rest, Done{context}}:
      {==}

# A new trace's generation followed by the package's continuation and
# kept_nothing emits True{} (started_keeps,
# GenerationProof.read_tape_outcome).
law started_read:
  for +policy: TC.FailurePolicy
  for +origin: TC.Origin
  for +sampling: TC.Sampling
  for current: Laws.TapeStep()
  {TC.Draw.read(~Laws.Tape(), ~TC.Source.tape, 48n, current)(Bool,
    step => Emit{Laws.kept_nothing(policy, TC.Policy.apply.done(Laws.Tape(), policy, TC.Service, TC.Serve.strict,
      TC.Serve.from_start.done(Laws.Tape(), origin, sampling, TC.Draw.outcome(Laws.Tape(), step))))}) ==
    Emit{True{}} : IO.OP<Bool>}

def started_read(policy, origin, sampling, current):
  GenerationProof.read_tape_outcome(Bool,
    outcome => Laws.kept_nothing(policy, TC.Policy.apply.done(Laws.Tape(), policy, TC.Service, TC.Serve.strict,
      TC.Serve.from_start.done(Laws.Tape(), origin, sampling, outcome))),
    outcome => True{},
    outcome => started_keeps(policy, origin, sampling, outcome),
    48n, current)

# restart_keeps_nothing for a kept context `context` that extraction is
# known to give (`same`): by cases on it, a root or a restart, each through
# started_read.
law restart_keeps.kept:
  for tape: Laws.Tape()
  for +extraction: TC.Extraction
  for +sampling: TC.Sampling
  for +policy: TC.FailurePolicy
  for context: Maybe<&2, TC.BaseContext>
  for same: {TC.Extraction.context(extraction) == context : Maybe<&2, TC.BaseContext>}
  {Laws.Observe(Bool, IO.bind(Laws.TapeService(policy), Bool, TC.Context.continue_or_start_with(~Laws.Tape(),
    ~TC.Source.tape, tape, extraction, TC.Restart{}, sampling, policy),
    done => IO.pure(Bool, Laws.kept_nothing(policy, done)))) == Emit{True{}} : IO.OP<Bool>}

def restart_keeps.kept(tape, extraction, sampling, policy, context, same):
  match context:
    case None{}:
      %Equal.sym(Maybe<&2, TC.BaseContext>, TC.Extraction.context(extraction), None{}, same) :
        {TC.Serve.kept(~Laws.Tape(), ~TC.Source.tape, tape, _, TC.Extraction.incoming(extraction), TC.Restart{},
          sampling)(Bool, done => Emit{Laws.kept_nothing(policy, TC.Policy.apply.done(Laws.Tape(), policy,
            TC.Service, TC.Serve.strict, done))}) == Emit{True{}} : IO.OP<Bool>}
      started_read(policy, TC.Started{}, sampling, (tape, TC.Draw.root()))
    case Some{+base}:
      %Equal.sym(Maybe<&2, TC.BaseContext>, TC.Extraction.context(extraction), Some{base}, same) :
        {TC.Serve.kept(~Laws.Tape(), ~TC.Source.tape, tape, _, TC.Extraction.incoming(extraction), TC.Restart{},
          sampling)(Bool, done => Emit{Laws.kept_nothing(policy, TC.Policy.apply.done(Laws.Tape(), policy,
            TC.Service, TC.Serve.strict, done))}) == Emit{True{}} : IO.OP<Bool>}
      started_read(policy, TC.Restarted{}, sampling, (tape, TC.Draw.restart(TC.Serve.replaced(base))))

# Law restart_keeps_nothing: restart_keeps.kept with the context that
# extraction gives.
law restart_keeps_nothing:
  for tape: Laws.Tape()
  for +extraction: TC.Extraction
  for +sampling: TC.Sampling
  for +policy: TC.FailurePolicy
  {Laws.Observe(Bool, IO.bind(Laws.TapeService(policy), Bool, TC.Context.continue_or_start_with(~Laws.Tape(),
    ~TC.Source.tape, tape, extraction, TC.Restart{}, sampling, policy),
    done => IO.pure(Bool, Laws.kept_nothing(policy, done)))) == Emit{True{}} : IO.OP<Bool>}

def restart_keeps_nothing(tape, extraction, sampling, policy):
  restart_keeps.kept(tape, extraction, sampling, policy, TC.Extraction.context(extraction), {==})

# A tried forwarding gives, under `policy`, what Laws.fallback.forwarded
# states. By cases on the policy and the forwarding's result; each case
# computes.
law forwarded_step:
  for +policy: TC.FailurePolicy
  for result: Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>
  for +error: TC.GenerationError
  for +carrier: List<&2, TC.Header>
  {TC.Policy.apply(policy, TC.Sent, TC.Send.strict, TC.Send.forwarded(result, error, carrier)) ==
    Laws.sent_by(policy, Laws.fallback.forwarded(result, error, carrier)) : TC.FailurePolicy.result(policy, TC.Sent)}

def forwarded_step(policy, result, error, carrier):
  match policy result:
    case TC.Lenient{} Fail{reason}:
      {==}
    case TC.Lenient{} Done{forwarded}:
      {==}
    case TC.Strict{} Fail{reason}:
      {==}
    case TC.Strict{} Done{forwarded}:
      {==}

# The package's fallback gives, under `policy`, what Laws.fallback states.
# By cases on the policy and the received context: without one, each case
# computes; with one, forwarded_step covers the forwarding's result.
law fallback_step:
  for +policy: TC.FailurePolicy
  for +limits: TC.Limits
  for received: Maybe<&2, TC.IncomingContext>
  for +error: TC.GenerationError
  for +carrier: List<&2, TC.Header>
  {TC.Policy.apply(policy, TC.Sent, TC.Send.strict, TC.Send.fallback(limits, received, error, carrier)) ==
    Laws.sent_by(policy, Laws.fallback(limits, received, error, carrier)) : TC.FailurePolicy.result(policy, TC.Sent)}

def fallback_step(policy, limits, received, error, carrier):
  match policy received:
    case TC.Lenient{} None{}:
      {==}
    case TC.Lenient{} Some{incoming}:
      forwarded_step(TC.Lenient{}, TC.Context.forward(limits, incoming, carrier), error, carrier)
    case TC.Strict{} None{}:
      {==}
    case TC.Strict{} Some{incoming}:
      forwarded_step(TC.Strict{}, TC.Context.forward(limits, incoming, carrier), error, carrier)

# The package's handling of a sent child's outcome under `policy` is
# Laws.sending. By cases on the policy and the outcome: a failed child is the
# fallback (fallback_step), and a generated one computes.
law sending_step:
  for +policy: TC.FailurePolicy
  for +limits: TC.Limits
  for +outgoing: TC.OutgoingContext
  for +received: Maybe<&2, TC.IncomingContext>
  for +carrier: List<&2, TC.Header>
  for outcome: Laws.TapeOutcome()
  {TC.Policy.apply.done(Laws.Tape(), policy, TC.Sent, TC.Send.strict,
    TC.Send.done(Laws.Tape(), limits, outgoing, received, carrier, outcome)) ==
    Laws.sending(policy, limits, outgoing, received, carrier, outcome) : Laws.TapeSent(policy)}

def sending_step(policy, limits, outgoing, received, carrier, outcome):
  match policy outcome:
    case TC.Lenient{} Tuple{rest, Fail{error}}:
      Equal.cong(TC.Sent, Laws.TapeSent(TC.Lenient{}), sent => (rest, sent),
        TC.Policy.apply(TC.Lenient{}, TC.Sent, TC.Send.strict, TC.Send.fallback(limits, received, error, carrier)),
        Laws.sent_by(TC.Lenient{}, Laws.fallback(limits, received, error, carrier)),
        fallback_step(TC.Lenient{}, limits, received, error, carrier))
    case TC.Lenient{} Tuple{rest, Done{operation}}:
      {==}
    case TC.Strict{} Tuple{rest, Fail{error}}:
      Equal.cong(Result<&2, &2, TC.GenerationError, TC.Sent>, Laws.TapeSent(TC.Strict{}), sent => (rest, sent),
        TC.Policy.apply(TC.Strict{}, TC.Sent, TC.Send.strict, TC.Send.fallback(limits, received, error, carrier)),
        Laws.sent_by(TC.Strict{}, Laws.fallback(limits, received, error, carrier)),
        fallback_step(TC.Strict{}, limits, received, error, carrier))
    case TC.Strict{} Tuple{rest, Done{operation}}:
      {==}

# Law send_operating: a service with an operation reduces to the generation
# of a child of it followed by the package's continuation, which agrees with
# Laws.sending on every outcome (sending_step,
# GenerationProof.read_tape_outcome).
law send_operating:
  for tape: Laws.Tape()
  for +limits: TC.Limits
  for origin: TC.Origin
  for +outgoing: TC.OutgoingContext
  for +received: Maybe<&2, TC.IncomingContext>
  for +sampling: TC.Sampling
  for +policy: TC.FailurePolicy
  for +carrier: List<&2, TC.Header>
  {Laws.Observe(Laws.TapeSent(policy), TC.Context.send_with(~Laws.Tape(), ~TC.Source.tape, tape, limits,
    TC.Operating{origin, outgoing, received}, sampling, policy, carrier)) ==
    Emit{Laws.sending(policy, limits, outgoing, received, carrier, TC.Draw.outcome(Laws.Tape(), TC.Draw.run(16n,
      (tape, TC.Draw.child(TC.LocalParent{TC.OutgoingContext.context(outgoing)}, sampling)))))} :
    IO.OP<Laws.TapeSent(policy)>}

def send_operating(tape, limits, origin, outgoing, received, sampling, policy, carrier):
  GenerationProof.read_tape_outcome(Laws.TapeSent(policy),
    outcome => TC.Policy.apply.done(Laws.Tape(), policy, TC.Sent, TC.Send.strict,
      TC.Send.done(Laws.Tape(), limits, outgoing, received, carrier, outcome)),
    outcome => Laws.sending(policy, limits, outgoing, received, carrier, outcome),
    outcome => sending_step(policy, limits, outgoing, received, carrier, outcome),
    16n, (tape, TC.Draw.child(TC.LocalParent{TC.OutgoingContext.context(outgoing)}, sampling)))

# Law send_untraced: a service without an operation returns the tape whole
# with the fallback (fallback_step).
law send_untraced:
  for tape: Laws.Tape()
  for +limits: TC.Limits
  for +error: TC.GenerationError
  for +received: Maybe<&2, TC.IncomingContext>
  for sampling: TC.Sampling
  for +policy: TC.FailurePolicy
  for +carrier: List<&2, TC.Header>
  {Laws.Observe(Laws.TapeSent(policy), TC.Context.send_with(~Laws.Tape(), ~TC.Source.tape, tape, limits,
    TC.Untraced{error, received}, sampling, policy, carrier)) ==
    Emit{(tape, Laws.sent_by(policy, Laws.fallback(limits, received, error, carrier)))} :
    IO.OP<Laws.TapeSent(policy)>}

def send_untraced(tape, limits, error, received, sampling, policy, carrier):
  Equal.cong(TC.FailurePolicy.result(policy, TC.Sent), IO.OP<Laws.TapeSent(policy)>,
    sent => Emit{(tape, sent)},
    TC.Policy.apply(policy, TC.Sent, TC.Send.strict, TC.Send.fallback(limits, received, error, carrier)),
    Laws.sent_by(policy, Laws.fallback(limits, received, error, carrier)),
    fallback_step(policy, limits, received, error, carrier))

# A tried forwarding reports no new operation under either policy. By cases
# on the policy and the forwarding's result; each case computes.
law unreported.forwarded:
  for +policy: TC.FailurePolicy
  for result: Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>
  for +error: TC.GenerationError
  for +carrier: List<&2, TC.Header>
  {Laws.reported.result(policy, TC.Policy.apply(policy, TC.Sent, TC.Send.strict,
    TC.Send.forwarded(result, error, carrier))) == None{} : Maybe<&2, TC.LocalContext>}

def unreported.forwarded(policy, result, error, carrier):
  match policy result:
    case TC.Lenient{} Fail{reason}:
      {==}
    case TC.Lenient{} Done{forwarded}:
      {==}
    case TC.Strict{} Fail{reason}:
      {==}
    case TC.Strict{} Done{forwarded}:
      {==}

# The fallback reports no new operation under either policy. By cases on the
# policy and the received context, as fallback_step.
law unreported:
  for +policy: TC.FailurePolicy
  for +limits: TC.Limits
  for received: Maybe<&2, TC.IncomingContext>
  for +error: TC.GenerationError
  for +carrier: List<&2, TC.Header>
  {Laws.reported.result(policy, TC.Policy.apply(policy, TC.Sent, TC.Send.strict,
    TC.Send.fallback(limits, received, error, carrier))) == None{} : Maybe<&2, TC.LocalContext>}

def unreported(policy, limits, received, error, carrier):
  match policy received:
    case TC.Lenient{} None{}:
      {==}
    case TC.Lenient{} Some{incoming}:
      unreported.forwarded(TC.Lenient{}, TC.Context.forward(limits, incoming, carrier), error, carrier)
    case TC.Strict{} None{}:
      {==}
    case TC.Strict{} Some{incoming}:
      unreported.forwarded(TC.Strict{}, TC.Context.forward(limits, incoming, carrier), error, carrier)

# A sent child's outcome is reported as Laws.generated gives it: none after
# a failure (unreported), and the child itself otherwise. By cases on the
# policy and the outcome.
law reported_step:
  for +policy: TC.FailurePolicy
  for +limits: TC.Limits
  for +outgoing: TC.OutgoingContext
  for +received: Maybe<&2, TC.IncomingContext>
  for +carrier: List<&2, TC.Header>
  for outcome: Laws.TapeOutcome()
  {Laws.reported(policy, TC.Policy.apply.done(Laws.Tape(), policy, TC.Sent, TC.Send.strict,
    TC.Send.done(Laws.Tape(), limits, outgoing, received, carrier, outcome))) ==
    Laws.generated(outcome) : Maybe<&2, TC.LocalContext>}

def reported_step(policy, limits, outgoing, received, carrier, outcome):
  match policy outcome:
    case TC.Lenient{} Tuple{rest, Fail{error}}:
      unreported(TC.Lenient{}, limits, received, error, carrier)
    case TC.Lenient{} Tuple{rest, Done{operation}}:
      {==}
    case TC.Strict{} Tuple{rest, Fail{error}}:
      unreported(TC.Strict{}, limits, received, error, carrier)
    case TC.Strict{} Tuple{rest, Done{operation}}:
      {==}

# Law send_reports_generated: by cases on the service. With an operation,
# the send reduces to the generation of a child followed by the package's
# continuation and Laws.reported (reported_step,
# GenerationProof.read_tape_outcome); without one, it reads no word and
# reports none (unreported).
law send_reports_generated:
  for tape: Laws.Tape()
  for +limits: TC.Limits
  for +service: TC.Service
  for +sampling: TC.Sampling
  for +policy: TC.FailurePolicy
  for +carrier: List<&2, TC.Header>
  {Laws.Observe(Maybe<&2, TC.LocalContext>, IO.bind(Laws.TapeSent(policy), Maybe<&2, TC.LocalContext>,
    TC.Context.send_with(~Laws.Tape(), ~TC.Source.tape, tape, limits, service, sampling, policy, carrier),
    done => IO.pure(Maybe<&2, TC.LocalContext>, Laws.reported(policy, done)))) ==
    Emit{Laws.sent_child(tape, service, sampling)} : IO.OP<Maybe<&2, TC.LocalContext>>}

def send_reports_generated(tape, limits, service, sampling, policy, carrier):
  match service:
    case TC.Operating{origin, +outgoing, +received}:
      GenerationProof.read_tape_outcome(Maybe<&2, TC.LocalContext>,
        outcome => Laws.reported(policy, TC.Policy.apply.done(Laws.Tape(), policy, TC.Sent, TC.Send.strict,
          TC.Send.done(Laws.Tape(), limits, outgoing, received, carrier, outcome))),
        outcome => Laws.generated(outcome),
        outcome => reported_step(policy, limits, outgoing, received, carrier, outcome),
        16n, (tape, TC.Draw.child(TC.LocalParent{TC.OutgoingContext.context(outgoing)}, sampling)))
    case TC.Untraced{+error, received}:
      Equal.cong(Maybe<&2, TC.LocalContext>, IO.OP<Maybe<&2, TC.LocalContext>>, reported => Emit{reported},
        Laws.reported.result(policy, TC.Policy.apply(policy, TC.Sent, TC.Send.strict,
          TC.Send.fallback(limits, received, error, carrier))), None{},
        unreported(policy, limits, received, error, carrier))
