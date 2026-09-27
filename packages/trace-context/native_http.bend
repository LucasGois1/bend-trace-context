# bend-trace-context: native HTTP headers
# =======================================
#
# The reference adapter for the native HTTP transport bend-net
# (paymog/bend-net, pinned as the vendor/bend-net submodule). bend-net keeps
# the header fields of a request or a response in a Base Map from each field
# name to its values in arrival order; its parser lowercases the names and
# trims the values. This module turns such a map into the carrier of
# trace_context.bend and back, and gives a service its receive-to-send
# shortcuts around bend-net's server and client.
#
# The module decides nothing about Trace Context. Which fields are context
# fields, how they are read and what is written all come from
# trace_context.bend: the shortcuts are the package's operations on the
# carrier of a map (laws http_continue and http_send), the carrier keeps
# every value of every name (law http_carrier), and the map of a carrier
# holds every value of every name (law http_headers). It imports only Base's Map
# and the package, not bend-net itself, so it builds wherever the package
# builds; a service imports bend-net for the transport.
#
# Names in the Headers namespace are internal: Bend lets any module import
# them, but they are not a compatibility contract.

import Base
import ./trace_context.bend as TC
import ./generation.bend as Generate

# The header fields of a bend-net request or response: each name, as bend-net
# stores it, with its values in arrival order.
def HeaderMap() -> Data:
  Map<&2, List<&2, String>>

# A request to send: the context fields the package gave it (`sent`), and
# the header map to send it with, which holds those fields.
type Outbound is Data:
  Outbound{sent: TC.Sent, headers: Map<&2, List<&2, String>>}

# One field for each value of `name`, pushed onto `fields` in order, so that
# the last value ends up first. A loop: a received head of 64 KiB can hold
# thousands of values.
def Headers.push(+name: String, values: List<&2, String>, fields: List<&2, TC.Header>) -> List<&2, TC.Header>:
  match values:
    case Nil{}:
      fields
    case Con{value, rest}:
      Headers.push(name, rest, Con{TC.Header{name, value}, fields})

# The fields of every entry pushed onto `fields`, entry by entry.
def Headers.gather(entries: List<&2, Sigma<&2, &2, String, _ => List<&2, String>>>, fields: List<&2, TC.Header>) ->
  List<&2, TC.Header>:
  match entries:
    case Nil{}:
      fields
    case Con{Tuple{name, values}, rest}:
      Headers.gather(rest, Headers.push(name, values, fields))

# The header fields of a map as a carrier for TC.Context.extract or
# TC.Context.send: every value of every name, in arrival order within each
# name (law http_carrier). The order between different names is the map's
# own, which no Trace Context rule depends on.
def carrier(headers: HeaderMap()) -> List<&2, TC.Header>:
  List.reverse(&2, TC.Header, Headers.gather(Map.to_list(&2, List<&2, String>, headers), Nil{}))

# The values a map holds under `name`, none when it has no entry for it.
def Headers.values(+headers: HeaderMap(), name: String) -> List<&2, String>:
  Pair.snd(HeaderMap(), List<&2, String>, Map.get(List<&2, String>, Nil{}, headers, name))

# Put one field's value first among its name's values.
def Headers.add(+headers: HeaderMap(), header: TC.Header) -> HeaderMap():
  match header:
    case TC.Header{+name, value}:
      Map.set(&2, List<&2, String>, headers, name, Con{value, Headers.values(headers, name)})

# Put every field of `fields` first among its name's values, in order. A
# loop, as Headers.push is.
def Headers.write(fields: List<&2, TC.Header>, +headers: HeaderMap()) -> HeaderMap():
  match fields:
    case Nil{}:
      headers
    case Con{header, rest}:
      Headers.write(rest, Headers.add(headers, header))

# The header map of a carrier, such as the one TC.Sent.carrier gives for a
# message to send: under each name, the carrier's values of that name in
# order (law http_headers), as bend-net's Http.add would add them one by one,
# with the names as the carrier spells them. The fields are put in from the
# last, each value first among its name's, which leaves every name's values
# in order. bend-net writes one header line for each value.
def headers(carrier: List<&2, TC.Header>) -> HeaderMap():
  Headers.write(List.reverse(&2, TC.Header, carrier), Map.new(&2, List<&2, String>))

# The service's own operation for a received message, from the header map of
# its request, on a caller's source: TC.Context.continue_or_start_with over
# the extraction of the map's carrier (law http_continue). `base` is the
# context to keep when the request carries no usable traceparent.
def continue_or_start_with(~S: Type, ~read: S -> IO(S & Result<&1, &1, U32 & String, U32>), source: S,
  +limits: TC.Limits, headers: HeaderMap(), base: Maybe<&2, TC.BaseContext>, reception: TC.Reception,
  sampling: TC.Sampling, +policy: TC.FailurePolicy) -> IO(S & TC.FailurePolicy.result(policy, TC.Service)):
  TC.Context.continue_or_start_with(~S, ~read, source, TC.Context.extract(limits, carrier(headers), base), reception,
    sampling, policy)

# The same on the host's cryptographic source
# (Generate.Context.continue_or_start).
def continue_or_start(+limits: TC.Limits, headers: HeaderMap(), base: Maybe<&2, TC.BaseContext>,
  reception: TC.Reception, sampling: TC.Sampling, +policy: TC.FailurePolicy) ->
  IO(TC.FailurePolicy.result(policy, TC.Service)):
  Generate.Context.continue_or_start(TC.Context.extract(limits, carrier(headers), base), reception, sampling, policy)

# The request to send for a message: the message with the map of the fields
# that TC.Sent.carrier gives.
def Headers.outbound(+sent: TC.Sent) -> Outbound:
  Outbound{sent, headers(TC.Sent.carrier(sent))}

# The same for a strict result: a failure stays a failure.
def Headers.strict(result: Result<&2, &2, TC.GenerationError, TC.Sent>) ->
  Result<&2, &2, TC.GenerationError, Outbound>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{sent}:
      Done{Headers.outbound(sent)}

# A message sent under `policy`, with its header map.
def Headers.written(policy: TC.FailurePolicy, result: TC.FailurePolicy.result(policy, TC.Sent)) ->
  TC.FailurePolicy.result(policy, Outbound):
  match policy:
    case TC.Lenient{}:
      Headers.outbound(result)
    case TC.Strict{}:
      Headers.strict(result)

# The source's final state with a message sent under `policy` and its map.
def Headers.written.done(-S: Type, +policy: TC.FailurePolicy, done: S & TC.FailurePolicy.result(policy, TC.Sent)) ->
  S & TC.FailurePolicy.result(policy, Outbound):
  (source, result) = done
  (source, Headers.written(policy, result))

# Give one request that the service sends the context of a new operation, on
# a caller's source: TC.Context.send_with on the carrier of `headers`, the
# request's own header map, and the map of the fields it gives back (law
# http_send). The request's old context fields go, whatever the case of
# their names, and the new ones replace them; without a new operation, the
# map forwards the received pair or carries no context fields.
def send_with(~S: Type, ~read: S -> IO(S & Result<&1, &1, U32 & String, U32>), source: S, +limits: TC.Limits,
  service: TC.Service, sampling: TC.Sampling, +policy: TC.FailurePolicy, headers: HeaderMap()) ->
  IO(S & TC.FailurePolicy.result(policy, Outbound)):
  IO.bind(S & TC.FailurePolicy.result(policy, TC.Sent), S & TC.FailurePolicy.result(policy, Outbound),
    TC.Context.send_with(~S, ~read, source, limits, service, sampling, policy, carrier(headers)),
    done => IO.pure(S & TC.FailurePolicy.result(policy, Outbound), Headers.written.done(S, policy, done)))

# The same on the host's cryptographic source (Generate.Context.send).
def send(+limits: TC.Limits, service: TC.Service, sampling: TC.Sampling, +policy: TC.FailurePolicy,
  headers: HeaderMap()) -> IO(TC.FailurePolicy.result(policy, Outbound)):
  IO.bind(TC.FailurePolicy.result(policy, TC.Sent), TC.FailurePolicy.result(policy, Outbound),
    Generate.Context.send(limits, service, sampling, policy, carrier(headers)),
    result => IO.pure(TC.FailurePolicy.result(policy, Outbound), Headers.written(policy, result)))

# The context fields that the package gave the request.
def Outbound.sent(outbound: Outbound) -> TC.Sent:
  match outbound:
    case Outbound{sent, headers}:
      sent

# The header map to send the request with.
def Outbound.headers(outbound: Outbound) -> HeaderMap():
  match outbound:
    case Outbound{sent, headers}:
      headers
