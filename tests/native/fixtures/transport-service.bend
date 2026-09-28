# Native HTTP transport probe for the W3C action/callback request shape.
import Base
import ../../harness/actions.bend as Harness
# bend-kit-http 0.23.0.1, from BendHub by content hash.
import 0x1cef8a5fb1d9142ca5c6b2cb43629b21/http.bend as Http

def send.headers(values: List<&2, String>, +key: String, +output: Map<&2, List<&2, String>>) -> Map<&2, List<&2, String>>:
  match values:
    case Nil{}:
      output
    case Con{value, rest}:
      send.headers(rest, key, Http.add(output, key, value))

def trace.headers(+headers: Map<&2, List<&2, String>>) -> Map<&2, List<&2, String>>:
  +output = send.headers(Http.fields(headers, "traceparent"), "traceparent", Http.empty())
  send.headers(Http.fields(headers, "tracestate"), "tracestate", output)

# A response with a text body.
def response(status: U32, headers: Map<&2, List<&2, String>>, body: String) -> Http.Res:
  Http.Res{status, headers, Http.from_string(body)}

def from.observer(result: Result<&1, &1, Http.Err, Http.Res>) -> Http.Res:
  match result:
    case Done{res}:
      res
    case Fail{err}:
      response(502, Http.set(Http.empty(), "content-type", "text/plain"), "observer request failed")

def relay(req: Http.Req) -> IO(Http.Res):
  Http.Req{method, path, headers, body} = req
  do IO<Http.Res>:
    result : Result<&1, &1, Http.Err, Http.Res> <- Http.fetch.how(
      "POST", "http://127.0.0.1:18774/relay", trace.headers(headers), body, 3000, Http.ModeManual{})
    return from.observer(result)

def callback.result(result: Result<&1, &1, Http.Err, Http.Res>) -> Bool:
  match result:
    case Fail{err}:
      False{}
    case Done{res}:
      Http.Res{status, headers, body} = res
      U32.is_eq(status, 200)

def callbacks.action(url: Maybe<&2, String>, body: String) -> IO(Bool):
  match url:
    case None{}:
      IO.pure(Bool, False{})
    case Some{target}:
      do IO<Bool>:
        result : Result<&1, &1, Http.Err, Http.Res> <- Http.fetch.how(
          "POST", target,
          Http.set(Http.empty(), "content-type", "application/json"),
          Http.from_string(body), 3000, Http.ModeManual{})
        return callback.result(result)

def callbacks(actions: List<&2, Harness.Action>) -> IO(Bool):
  match actions:
    case Nil{}:
      IO.pure(Bool, True{})
    case Con{+action, rest}:
      do IO<Bool>:
        ok : Bool <- callbacks.action(Harness.Action.url(action), Harness.Action.body(action))
        later : Bool <- callbacks(rest)
        return Bool.and(ok, later)

def test.response.result(ok: Bool) -> IO(Http.Res):
  match ok:
    case True{}:
      IO.pure(Http.Res, response(200, Http.set(Http.empty(), "content-type", "application/json"), "{\"ok\":true}"))
    case False{}:
      IO.pure(Http.Res, response(502, Http.set(Http.empty(), "content-type", "application/json"), "{\"ok\":false}"))

def test.response(actions: Maybe<&2, List<&2, Harness.Action>>) -> IO(Http.Res):
  match actions:
    case None{}:
      IO.pure(Http.Res, response(400, Http.empty(), "expected a JSON array of actions"))
    case Some{list}:
      do IO<Http.Res>:
        ok : Bool <- callbacks(list)
        answer : Http.Res <- test.response.result(ok)
        return answer

def route.test(req: Http.Req) -> IO(Http.Res):
  Http.Req{method, path, headers, body} = req
  test.response(Harness.parse(body))

def route(req: Http.Req, is.test: Bool, is.relay: Bool) -> IO(Http.Res):
  match is.test:
    case True{}:
      route.test(req)
    case False{}:
      match is.relay:
        case True{}:
          relay(req)
        case False{}:
          IO.pure(Http.Res, response(404, Http.empty(), "not found"))

def handle(req: Http.Req) -> IO(Http.Res):
  Http.Req{method, +path, headers, body} = req
  route(Http.Req{method, path, headers, body}, String.eq(path, "/test"), String.eq(path, "/relay"))

def main() -> IO(Unit):
  Http.serve.with(~handle, 18773, 1048576n)
