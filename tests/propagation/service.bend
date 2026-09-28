import Base
import ./deps/bend-trace-context/packages/trace-context/trace_context.bend as TC
import ./deps/bend-trace-context/packages/trace-context/native_http.bend as NativeHttp
import ./deps/bend-trace-context/packages/trace-context/generation.bend as Generate
import ./deps/bend-trace-context/tests/harness/actions.bend as Harness
# bend-kit-http 0.23.0.1 and bend-kit-json 0.5.0.1, the JSON package that it
# uses, from BendHub by content hash.
import 0x1cef8a5fb1d9142ca5c6b2cb43629b21/http.bend as Http
import 0x584fc27920487ceab242392391418d7f/json.bend as Json

# The service under test for the W3C Trace Context harness and for the
# repository's own propagation checks, built from a pinned checkout of the
# package as an application would build it. Every Trace Context decision
# comes from the package and its native HTTP adapter; this file only routes
# requests and speaks the harness's protocol.
#
# POST /test follows the harness: the body is a JSON array of actions, each
# {url, arguments}, and for each the service posts `arguments` to `url` as a
# request of its own, carrying a new child of its operation for the received
# request. The other routes change one choice for the repository's checks:
#   /test/restart             the service restarts the trace, as at a trust
#                             boundary
#   /test/stale               each request starts from the received
#                             request's context fields and x-request-id, and
#                             each later one reuses the previous one's fields
#   /test/unavailable         the entropy source always fails, so the service
#                             has no operation and the requests carry the
#                             lenient fallback; they start from the copied
#                             fields too
#   /test/unavailable/strict  the same source under the strict policy, which
#                             refuses the request
#   /test/unavailable/send    the service's operation comes from the host,
#                             and each child from the failing source, so each
#                             request carries the fallback of an operating
#                             service; under /test/unavailable/send/strict,
#                             the request is refused before any is sent
#   /test/exhausted           a source that gives only zero words, so every
#                             candidate is rejected and generation is
#                             exhausted
# The response is a JSON object with the diagnostics, which hold no received
# value.

def limits() -> TC.Limits:
  TC.Limits.default()

# The harness actions of a request.
def Actions() -> Data:
  List<&2, Harness.Action>

def json.response(status: U32, body: Json.Val) -> Http.Res:
  Http.Res{status, Http.set(Http.empty(), "content-type", "application/json"), Json.encode.bytes(body)}

def text.response(status: U32, body: String) -> Http.Res:
  Http.Res{status, Http.set(Http.empty(), "content-type", "text/plain"), Http.from_string(body)}

# A JSON string, and one field of a JSON object, whose key is bytes: bend-kit
# keeps JSON text in its byte string, the type of Http.Body().
def json.text(text: String) -> Json.Val:
  Json.Str{Json.utf8(text)}

def json.field(name: String, value: Json.Val) -> Http.Body() & Json.Val:
  (Json.utf8(name), value)

def json.texts(texts: List<&2, String>) -> List<&1, Json.Val>:
  match texts:
    case Nil{}:
      Nil{}
    case Con{text, rest}:
      Con{json.text(text), json.texts(rest)}

# An entropy source that always fails, as a platform without a generator.
def unavailable(state: Unit) -> IO(Unit & Result<&1, &1, U32 & String, U32>):
  IO.pure(Unit & Result<&1, &1, U32 & String, U32>, (state, Fail{(5, "entropy unavailable")}))

# A source that gives only zero words: every candidate identifier is all
# zero, so generation ends exhausted.
def zeros(state: Unit) -> IO(Unit & Result<&1, &1, U32 & String, U32>):
  IO.pure(Unit & Result<&1, &1, U32 & String, U32>, (state, Done{0}))

# The fields a request to send starts from: only its content type.
def container.empty() -> NativeHttp.HeaderMap():
  Http.set(Http.empty(), "content-type", "application/json")

# The fields a request to send starts from in the stale routes: the received
# request's context fields and x-request-id, copied as a careless
# application would copy them, with the content type.
def container.copied(+headers: NativeHttp.HeaderMap()) -> NativeHttp.HeaderMap():
  Map.set(&2, List<&2, String>, Map.set(&2, List<&2, String>, Map.set(&2, List<&2, String>, container.empty(),
    "traceparent", Http.fields(headers, "traceparent")), "tracestate", Http.fields(headers, "tracestate")),
    "x-request-id", Http.fields(headers, "x-request-id"))

def callback.ok(result: Result<&1, &1, Http.Err, Http.Res>) -> Bool:
  match result:
    case Fail{err}:
      False{}
    case Done{res}:
      Http.Res{status, headers, body} = res
      U32.is_eq(status, 200)

# Post one action's arguments with the fields that the adapter wrote.
def callback(url: Maybe<&2, String>, body: String, +outbound: NativeHttp.Outbound) -> IO(Bool):
  match url:
    case None{}:
      IO.pure(Bool, False{})
    case Some{target}:
      do IO<Bool>:
        result : Result<&1, &1, Http.Err, Http.Res> <- Http.fetch.how("POST", target,
          NativeHttp.Outbound.headers(outbound), Http.from_string(body), 3000, Http.ModeManual{})
        return callback.ok(result)

# The diagnostics of the requests sent, and whether every callback succeeded.
type Callbacks is Data:
  Callbacks{sent: List<&2, String>, ok: Bool}

def callbacks.done(+outbound: NativeHttp.Outbound, ok: Bool, later: Callbacks) -> Callbacks:
  match later:
    case Callbacks{sent, fine}:
      Callbacks{Con{TC.Sent.show(NativeHttp.Outbound.sent(outbound)), sent}, Bool.and(ok, fine)}

# The fields the next request starts from: the same container, or, when
# reusing, the fields the previous request was sent with.
def callbacks.next(reuse: Bool, +container: NativeHttp.HeaderMap(), +outbound: NativeHttp.Outbound) ->
  NativeHttp.HeaderMap():
  match reuse:
    case True{}:
      NativeHttp.Outbound.headers(outbound)
    case False{}:
      container

# Send every action's request, each with a new child of the service's
# operation (Generate.NativeHttp.send), or its fallback when the service has
# none.
def callbacks(+service: TC.Service, actions: Actions(), +container: NativeHttp.HeaderMap(), +reuse: Bool) ->
  IO(Callbacks):
  match actions:
    case Nil{}:
      IO.pure(Callbacks, Callbacks{Nil{}, True{}})
    case Con{+action, rest}:
      do IO<Callbacks>:
        +outbound : NativeHttp.Outbound <- Generate.NativeHttp.send(limits(), service, TC.InheritSampled{},
          TC.Lenient{}, container)
        ok : Bool <- callback(Harness.Action.url(action), Harness.Action.body(action), outbound)
        later : Callbacks <- callbacks(service, rest, callbacks.next(reuse, container, outbound), reuse)
        return callbacks.done(outbound, ok, later)

# Send every action's request with a child from the failing source: an
# operating service's lenient fallback.
def callbacks.unavailable(+service: TC.Service, actions: Actions(), +container: NativeHttp.HeaderMap()) ->
  IO(Callbacks):
  match actions:
    case Nil{}:
      IO.pure(Callbacks, Callbacks{Nil{}, True{}})
    case Con{+action, rest}:
      do IO<Callbacks>:
        done : Unit & NativeHttp.Outbound <- NativeHttp.send_with(~Unit, ~unavailable, Unit{}, limits(), service,
          TC.InheritSampled{}, TC.Lenient{}, container)
        +outbound : NativeHttp.Outbound = Pair.snd(Unit, NativeHttp.Outbound, done)
        ok : Bool <- callback(Harness.Action.url(action), Harness.Action.body(action), outbound)
        later : Callbacks <- callbacks.unavailable(service, rest, container)
        return callbacks.done(outbound, ok, later)

def report(+extraction: String, +service: String, done: Callbacks) -> Http.Res:
  match done:
    case Callbacks{sent, +ok}:
      json.response(Bool.pick(U32, ok, 200, 502), Json.Obj{[json.field("extraction", json.text(extraction)),
        json.field("service", json.text(service)), json.field("sent", Json.Arr{json.texts(sent)}),
        json.field("ok", Json.Flag{ok})]})

# What extraction found in the received request, for the diagnostics.
def extraction(+headers: NativeHttp.HeaderMap()) -> String:
  TC.Extraction.show(TC.Context.extract(limits(), NativeHttp.carrier(headers), None{}))

# Send the actions' requests for a service's operation and report.
def respond(+headers: NativeHttp.HeaderMap(), +service: TC.Service, actions: Actions(),
  +container: NativeHttp.HeaderMap(), reuse: Bool) -> IO(Http.Res):
  do IO<Http.Res>:
    done : Callbacks <- callbacks(service, actions, container, reuse)
    return report(extraction(headers), TC.Service.show(service), done)

# The service's own operation on the host's source.
def host(+headers: NativeHttp.HeaderMap(), reception: TC.Reception) -> IO(TC.Service):
  Generate.NativeHttp.continue_or_start(limits(), headers, None{}, reception, TC.InheritSampled{}, TC.Lenient{})

# The service's own operation on the failing source, lenient.
def unavailable.lenient(+headers: NativeHttp.HeaderMap()) -> IO(TC.Service):
  do IO<TC.Service>:
    done : Unit & TC.Service <- NativeHttp.continue_or_start_with(~Unit, ~unavailable, Unit{}, limits(), headers,
      None{}, TC.Continue{}, TC.InheritSampled{}, TC.Lenient{})
    return Pair.snd(Unit, TC.Service, done)

def served(+headers: NativeHttp.HeaderMap(), actions: Actions(), reception: TC.Reception,
  +container: NativeHttp.HeaderMap(), reuse: Bool) -> IO(Http.Res):
  do IO<Http.Res>:
    +service : TC.Service <- host(headers, reception)
    respond(headers, service, actions, container, reuse)

# The service's own operation on the zero source, lenient.
def exhausted(+headers: NativeHttp.HeaderMap()) -> IO(TC.Service):
  do IO<TC.Service>:
    done : Unit & TC.Service <- NativeHttp.continue_or_start_with(~Unit, ~zeros, Unit{}, limits(), headers, None{},
      TC.Continue{}, TC.InheritSampled{}, TC.Lenient{})
    return Pair.snd(Unit, TC.Service, done)

def served.exhausted(+headers: NativeHttp.HeaderMap(), actions: Actions()) -> IO(Http.Res):
  do IO<Http.Res>:
    +service : TC.Service <- exhausted(headers)
    respond(headers, service, actions, container.copied(headers), True{})

# An operating service whose children cannot be generated.
def served.unavailable.send(+headers: NativeHttp.HeaderMap(), actions: Actions()) -> IO(Http.Res):
  do IO<Http.Res>:
    +service : TC.Service <- host(headers, TC.Continue{})
    done : Callbacks <- callbacks.unavailable(service, actions, container.copied(headers))
    return report(extraction(headers), TC.Service.show(service), done)

def refused.send(result: Result<&2, &2, TC.GenerationError, NativeHttp.Outbound>) -> Http.Res:
  match result:
    case Fail{error}:
      json.response(503, Json.Obj{[json.field("refused", json.text(TC.GenerationError.show(error)))]})
    case Done{outbound}:
      json.response(500, Json.Obj{[json.field("unexpected",
        json.text(TC.Sent.show(NativeHttp.Outbound.sent(outbound))))]})

# The strict policy refuses the request when a child cannot be generated:
# nothing is sent.
def served.unavailable.send.strict(+headers: NativeHttp.HeaderMap()) -> IO(Http.Res):
  do IO<Http.Res>:
    +service : TC.Service <- host(headers, TC.Continue{})
    done : Unit & Result<&2, &2, TC.GenerationError, NativeHttp.Outbound> <- NativeHttp.send_with(~Unit,
      ~unavailable, Unit{}, limits(), service, TC.InheritSampled{}, TC.Strict{}, container.empty())
    return refused.send(Pair.snd(Unit, Result<&2, &2, TC.GenerationError, NativeHttp.Outbound>, done))

def served.unavailable(+headers: NativeHttp.HeaderMap(), actions: Actions()) -> IO(Http.Res):
  do IO<Http.Res>:
    +service : TC.Service <- unavailable.lenient(headers)
    respond(headers, service, actions, container.copied(headers), True{})

def refused(result: Result<&2, &2, TC.GenerationError, TC.Service>) -> Http.Res:
  match result:
    case Fail{error}:
      json.response(503, Json.Obj{[json.field("refused", json.text(TC.GenerationError.show(error)))]})
    case Done{service}:
      json.response(500, Json.Obj{[json.field("unexpected", json.text(TC.Service.show(service)))]})

# The strict policy refuses the request when the service gets no operation.
def served.refused(+headers: NativeHttp.HeaderMap()) -> IO(Http.Res):
  do IO<Http.Res>:
    done : Unit & Result<&2, &2, TC.GenerationError, TC.Service> <- NativeHttp.continue_or_start_with(~Unit,
      ~unavailable, Unit{}, limits(), headers, None{}, TC.Continue{}, TC.InheritSampled{}, TC.Strict{})
    return refused(Pair.snd(Unit, Result<&2, &2, TC.GenerationError, TC.Service>, done))

def route.exhausted(matched: Bool, +headers: NativeHttp.HeaderMap(), actions: Actions()) -> IO(Http.Res):
  match matched:
    case True{}:
      served.exhausted(headers, actions)
    case False{}:
      IO.pure(Http.Res, text.response(404, "not found"))

def route.send.strict(matched: Bool, +path: String, +headers: NativeHttp.HeaderMap(), actions: Actions()) ->
  IO(Http.Res):
  match matched:
    case True{}:
      served.unavailable.send.strict(headers)
    case False{}:
      route.exhausted(String.eq(path, "/test/exhausted"), headers, actions)

def route.send(matched: Bool, +path: String, +headers: NativeHttp.HeaderMap(), actions: Actions()) ->
  IO(Http.Res):
  match matched:
    case True{}:
      served.unavailable.send(headers, actions)
    case False{}:
      route.send.strict(String.eq(path, "/test/unavailable/send/strict"), path, headers, actions)

def route.strict(matched: Bool, +path: String, +headers: NativeHttp.HeaderMap(), actions: Actions()) ->
  IO(Http.Res):
  match matched:
    case True{}:
      served.refused(headers)
    case False{}:
      route.send(String.eq(path, "/test/unavailable/send"), path, headers, actions)

def route.unavailable(matched: Bool, +path: String, +headers: NativeHttp.HeaderMap(), actions: Actions()) ->
  IO(Http.Res):
  match matched:
    case True{}:
      served.unavailable(headers, actions)
    case False{}:
      route.strict(String.eq(path, "/test/unavailable/strict"), path, headers, actions)

def route.stale(matched: Bool, +path: String, +headers: NativeHttp.HeaderMap(), actions: Actions()) ->
  IO(Http.Res):
  match matched:
    case True{}:
      served(headers, actions, TC.Continue{}, container.copied(headers), True{})
    case False{}:
      route.unavailable(String.eq(path, "/test/unavailable"), path, headers, actions)

def route.restart(matched: Bool, +path: String, +headers: NativeHttp.HeaderMap(), actions: Actions()) ->
  IO(Http.Res):
  match matched:
    case True{}:
      served(headers, actions, TC.Restart{}, container.empty(), False{})
    case False{}:
      route.stale(String.eq(path, "/test/stale"), path, headers, actions)

def route.test(matched: Bool, +path: String, +headers: NativeHttp.HeaderMap(), actions: Actions()) ->
  IO(Http.Res):
  match matched:
    case True{}:
      served(headers, actions, TC.Continue{}, container.empty(), False{})
    case False{}:
      route.restart(String.eq(path, "/test/restart"), path, headers, actions)

# The route for a path and its actions.
def route.actions(+path: String, +headers: NativeHttp.HeaderMap(), actions: Actions()) -> IO(Http.Res):
  route.test(String.eq(path, "/test"), path, headers, actions)

def route(+path: String, +headers: NativeHttp.HeaderMap(), actions: Maybe<&2, Actions()>) -> IO(Http.Res):
  match actions:
    case None{}:
      IO.pure(Http.Res, text.response(400, "expected a JSON array of actions"))
    case Some{list}:
      route.actions(path, headers, list)

def handle(req: Http.Req) -> IO(Http.Res):
  Http.Req{method, +path, +headers, body} = req
  route(path, headers, Harness.parse(body))

def main() -> IO(Unit):
  Http.serve.with(~handle, 18775, 1048576n)
