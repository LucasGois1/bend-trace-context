import Base
import ../trace_context.bend as TC
import ../generation.bend as Generate

# A service handles the requests it receives with the convenience
# operations. Context.continue_or_start gives it an operation of its own for
# each request, and Context.send gives every request it sends on a child of
# that operation, injected into the request's fields. It continues a traced
# request and sends two requests on, each with a child of its own and the
# received state; it starts a trace for a request without context; and it
# restarts the trace of a partner's request at its trust boundary, where the
# partner's state is discarded. These run on the host's cryptographic
# source, so each run prints new IDs.
#
# The same operations take a caller's source (TC.Context.continue_or_start_with
# and TC.Context.send_with). With a source that fails, the lenient policy
# lets the request proceed without a new operation: the request sent on
# forwards the received context unchanged. The strict policy returns the
# error, so that the service can refuse the request instead.

def field(header: TC.Header) -> String:
  match header:
    case TC.Header{name, value}:
      name ++ ": " ++ value

def fields.rest(carrier: List<&2, TC.Header>) -> String:
  match carrier:
    case Nil{}:
      ""
    case Con{header, rest}:
      " | " ++ field(header) ++ fields.rest(rest)

# The fields of a carrier, in their order.
def fields(carrier: List<&2, TC.Header>) -> String:
  match carrier:
    case Nil{}:
      "no fields"
    case Con{header, rest}:
      field(header) ++ fields.rest(rest)

def operation(outgoing: Maybe<&2, TC.OutgoingContext>) -> String:
  match outgoing:
    case None{}:
      ""
    case Some{context}:
      " " ++ TC.TraceParentV00.format(TC.LocalContext.to_traceparent(TC.OutgoingContext.context(context)))

# How the service's operation came about, with its traceparent. Service.show
# includes no received value; the traceparent is the service's own
# operation, which keeps the received trace ID when it continues one.
def described(+service: TC.Service) -> String:
  TC.Service.show(service) ++ operation(TC.Service.outgoing(service))

# Send one request on: its own child of the service's operation, or the
# fallback when none can be generated. The example prints every field sent,
# a forwarded pair's received values included, to show what travels; a log
# line needs only Sent.show, which includes no received value.
def send(service: TC.Service, carrier: List<&2, TC.Header>) -> IO(Unit):
  do IO<Unit>:
    +sent : TC.Sent <- Generate.Context.send(TC.Limits.default(), service, TC.InheritSampled{}, TC.Lenient{},
      carrier)
    IO.print("sent: " ++ TC.Sent.show(sent) ++ " | " ++ fields(TC.Sent.carrier(sent)))

# A request this service handles, with the W3C example context.
def handled() -> List<&2, TC.Header>:
  [TC.Header{"traceparent", "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"},
    TC.Header{"tracestate", "congo=t61rcWkgMzE"}]

# Continue the handled request's trace, and send two requests on.
def traced(+limits: TC.Limits) -> IO(Unit):
  do IO<Unit>:
    +service : TC.Service <- Generate.Context.continue_or_start(TC.Context.extract(limits, handled(), None{}),
      TC.Continue{}, TC.InheritSampled{}, TC.Lenient{})
    Unit <- IO.print("traced request: " ++ described(service))
    Unit <- send(service, [TC.Header{"Host", "inventory.internal"}])
    send(service, [TC.Header{"Host", "billing.internal"}])

# Start a trace for a request without context.
def untraced(+limits: TC.Limits) -> IO(Unit):
  do IO<Unit>:
    +service : TC.Service <- Generate.Context.continue_or_start(TC.Context.extract(limits,
      [TC.Header{"Accept", "*/*"}], None{}), TC.Continue{}, TC.InheritSampled{}, TC.Lenient{})
    Unit <- IO.print("request without context: " ++ described(service))
    send(service, [TC.Header{"Host", "inventory.internal"}])

# Restart the trace of a partner's request at the trust boundary.
def partner(+limits: TC.Limits) -> IO(Unit):
  do IO<Unit>:
    +service : TC.Service <- Generate.Context.continue_or_start(TC.Context.extract(limits,
      [TC.Header{"traceparent", "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"},
        TC.Header{"tracestate", "partner=internal"}], None{}), TC.Restart{}, TC.InheritSampled{}, TC.Lenient{})
    Unit <- IO.print("partner request: " ++ described(service))
    send(service, [TC.Header{"Host", "inventory.internal"}])

# A source that cannot give entropy, as on a platform without a generator.
def unavailable(state: Unit) -> IO(Unit & Result<&1, &1, U32 & String, U32>):
  IO.pure(Unit & Result<&1, &1, U32 & String, U32>, (state, Fail{(5, "entropy unavailable")}))

# Without entropy, the lenient policy lets the handled request proceed: the
# service has no operation, and the request sent on forwards the received
# context unchanged.
def lenient(+limits: TC.Limits) -> IO(Unit):
  do IO<Unit>:
    done : Unit & TC.Service <- TC.Context.continue_or_start_with(~Unit, ~unavailable, Unit{},
      TC.Context.extract(limits, handled(), None{}), TC.Continue{}, TC.InheritSampled{}, TC.Lenient{})
    +service : TC.Service = Pair.snd(Unit, TC.Service, done)
    Unit <- IO.print("without entropy: " ++ described(service))
    send(service, [TC.Header{"Host", "inventory.internal"}])

def refusal(result: Result<&2, &2, TC.GenerationError, TC.Service>) -> String:
  match result:
    case Fail{error}:
      "refused after " ++ TC.GenerationError.show(error)
    case Done{service}:
      "handled: " ++ TC.Service.show(service)

# Without entropy, the strict policy returns the error.
def strict(+limits: TC.Limits) -> IO(Unit):
  do IO<Unit>:
    done : Unit & Result<&2, &2, TC.GenerationError, TC.Service> <- TC.Context.continue_or_start_with(~Unit,
      ~unavailable, Unit{}, TC.Context.extract(limits, handled(), None{}), TC.Continue{}, TC.InheritSampled{},
      TC.Strict{})
    IO.print("strict, without entropy: " ++ refusal(Pair.snd(Unit, Result<&2, &2, TC.GenerationError, TC.Service>,
      done)))

def main() -> IO(Unit):
  +limits = TC.Limits.default()
  do IO<Unit>:
    Unit <- traced(limits)
    Unit <- untraced(limits)
    Unit <- partner(limits)
    Unit <- lenient(limits)
    strict(limits)
