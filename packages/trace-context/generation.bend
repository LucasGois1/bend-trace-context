# Generation on the host's cryptographic source
# =============================================
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
# behavior over replayed tapes. This file only connects it to the host source
# of entropy.bend.

import Base
import ./trace_context.bend as TC
import ./entropy.bend as Entropy

# The host source as the machine reads it: each read returns one word result
# from Entropy.read_u32, and the state is Unit because the host keeps none.
def Source.host(state: Unit) -> IO(Unit & Result<&1, &1, U32 & String, U32>):
  IO.bind(Result<&1, &1, U32 & String, U32>, Unit & Result<&1, &1, U32 & String, U32>,
    Entropy.read_u32(), word => IO.pure(Unit & Result<&1, &1, U32 & String, U32>, (state, word)))

# The host source has no state to hand back.
def on_host(action: IO(Unit & Result<&2, &2, TC.GenerationError, TC.LocalContext>)) ->
  IO(Result<&2, &2, TC.GenerationError, TC.LocalContext>):
  IO.bind(Unit & Result<&2, &2, TC.GenerationError, TC.LocalContext>,
    Result<&2, &2, TC.GenerationError, TC.LocalContext>, action,
    done => IO.pure(Result<&2, &2, TC.GenerationError, TC.LocalContext>,
      Pair.snd(Unit, Result<&2, &2, TC.GenerationError, TC.LocalContext>, done)))

# Start a trace. The trace ID asserts random-trace-id and the root is not
# sampled, so it is emitted with flags 02.
def Context.root() -> IO(Result<&2, &2, TC.GenerationError, TC.LocalContext>):
  on_host(TC.Context.root_with(~Unit, ~Source.host, Unit{}))

# Continue a remote or local parent with a new operation.
def Context.child(parent: TC.Parent, sampling: TC.Sampling) -> IO(Result<&2, &2, TC.GenerationError, TC.LocalContext>):
  on_host(TC.Context.child_with(~Unit, ~Source.host, Unit{}, parent, sampling))

# Start a new trace instead of continuing a received context.
def Context.restart(previous: TC.RemoteContext) -> IO(Result<&2, &2, TC.GenerationError, TC.LocalContext>):
  on_host(TC.Context.restart_with(~Unit, ~Source.host, Unit{}, previous))
