# W3C Trace Context Level 2 propagation, with its rules proved as laws. Source: https://github.com/LucasGois1/bend-trace-context
#
# Generation on the host's cryptographic source
# =============================================
#
# The first line is the package's description on BendHub, which shows the
# first line of the file that a release publishes: this file.
#
# Generated contexts on the host's cryptographic source: WebCrypto in
# JavaScript and the operating system's generator natively. They apply the
# rules of trace_context.bend: four words per trace ID candidate and two per
# span ID candidate, most significant first, eight candidates per identifier,
# no all-zero identifier, no reuse of the parent's span ID or of a received
# trace ID, and an immediate stop at the first source error. There is no time,
# counter or other fallback. TC.Context.root_with and its siblings take a
# caller's source instead.
#
# The generation machine itself is pure: section 6 of LAWS.bend states its
# behavior over replayed tapes. This file only connects it, and the native
# HTTP shortcuts of native_http.bend, to the host source of entropy.bend.
#
# Every operation here relies on entropy.bend's foreign effect, so a check of
# a file that imports this module reports them and answers SOME PROOFS FAIL.
# No law imports it: the laws state the same operations on a caller's
# source, which is how PROOF.bend proves them without host code.

import Base
import ./trace_context.bend as TC
import ./native_http.bend as Adapter
import ./entropy.bend as Entropy

# The host source as the machine reads it: each read returns one word result
# from Entropy.read_u32, and the state is Unit because the host keeps none.
def Source.host(state: Unit) -> IO(Unit & Result<&1, &1, U32 & String, U32>):
  IO.bind(Result<&1, &1, U32 & String, U32>, Unit & Result<&1, &1, U32 & String, U32>,
    Entropy.read_u32(), word => IO.pure(Unit & Result<&1, &1, U32 & String, U32>, (state, word)))

# The host source has no state to hand back.
def on_host(-A: Type, action: IO(Unit & A)) -> IO(A):
  IO.bind(Unit & A, A, action, done => IO.pure(A, Pair.snd(Unit, A, done)))

# Start a trace. The trace ID asserts random-trace-id and the root is not
# sampled, so it is emitted with flags 02.
def Context.root() -> IO(Result<&2, &2, TC.GenerationError, TC.LocalContext>):
  on_host(Result<&2, &2, TC.GenerationError, TC.LocalContext>, TC.Context.root_with(~Unit, ~Source.host, Unit{}))

# Continue a remote or local parent with a new operation.
def Context.child(parent: TC.Parent, sampling: TC.Sampling) -> IO(Result<&2, &2, TC.GenerationError, TC.LocalContext>):
  on_host(Result<&2, &2, TC.GenerationError, TC.LocalContext>,
    TC.Context.child_with(~Unit, ~Source.host, Unit{}, parent, sampling))

# Start a new trace instead of continuing a received context.
def Context.restart(previous: TC.RemoteContext) -> IO(Result<&2, &2, TC.GenerationError, TC.LocalContext>):
  on_host(Result<&2, &2, TC.GenerationError, TC.LocalContext>,
    TC.Context.restart_with(~Unit, ~Source.host, Unit{}, previous))

# Give a service its own operation for a received message: a child of the
# context that extraction keeps, the message's or the base, a root without
# one, or a new trace in its place at a trust boundary
# (TC.Context.continue_or_start_with).
def Context.continue_or_start(+extraction: TC.Extraction, reception: TC.Reception, sampling: TC.Sampling,
  +policy: TC.FailurePolicy) -> IO(TC.FailurePolicy.result(policy, TC.Service)):
  on_host(TC.FailurePolicy.result(policy, TC.Service),
    TC.Context.continue_or_start_with(~Unit, ~Source.host, Unit{}, extraction, reception, sampling, policy))

# Give one message that the service sends a new child of the service's
# operation, or the fallback when none can be generated
# (TC.Context.send_with).
def Context.send(+limits: TC.Limits, service: TC.Service, sampling: TC.Sampling, +policy: TC.FailurePolicy,
  +carrier: List<&2, TC.Header>) -> IO(TC.FailurePolicy.result(policy, TC.Sent)):
  on_host(TC.FailurePolicy.result(policy, TC.Sent),
    TC.Context.send_with(~Unit, ~Source.host, Unit{}, limits, service, sampling, policy, carrier))

# The service's own operation for a received request, from the header map of
# the request, on the host's cryptographic source: native_http.bend's
# continue_or_start_with on Source.host. `base` is the context to keep when
# the request carries no usable traceparent.
def NativeHttp.continue_or_start(+limits: TC.Limits, headers: Adapter.HeaderMap(), base: Maybe<&2, TC.BaseContext>,
  reception: TC.Reception, sampling: TC.Sampling, +policy: TC.FailurePolicy) ->
  IO(TC.FailurePolicy.result(policy, TC.Service)):
  on_host(TC.FailurePolicy.result(policy, TC.Service),
    Adapter.continue_or_start_with(~Unit, ~Source.host, Unit{}, limits, headers, base, reception, sampling, policy))

# Give one request that the service sends the context of a new operation, on
# the host's cryptographic source: native_http.bend's send_with on
# Source.host, which replaces the context fields of `headers`, the request's
# own header map.
def NativeHttp.send(+limits: TC.Limits, service: TC.Service, sampling: TC.Sampling, +policy: TC.FailurePolicy,
  headers: Adapter.HeaderMap()) -> IO(TC.FailurePolicy.result(policy, Adapter.Outbound)):
  on_host(TC.FailurePolicy.result(policy, Adapter.Outbound),
    Adapter.send_with(~Unit, ~Source.host, Unit{}, limits, service, sampling, policy, headers))
