# Native HTTP transport probe for the W3C action/callback request shape.
import Base
import ../../../vendor/bend-net/http.bend as Http
import ../../../vendor/bend-net/json/json.bend as Json

def send.headers(values: List<&2, String>, +key: String, +output: Map<&2, List<&2, String>>) -> Map<&2, List<&2, String>>:
  match values:
    case Nil{}:
      output
    case Con{value, rest}:
      send.headers(rest, key, Http.add(output, key, value))

def trace.headers(+headers: Map<&2, List<&2, String>>) -> Map<&2, List<&2, String>>:
  +output = send.headers(Http.fields(headers, "traceparent"), "traceparent", Http.empty())
  send.headers(Http.fields(headers, "tracestate"), "tracestate", output)

def from.observer(result: Result<&2, &2, Http.Err, Http.Res>) -> Http.Res:
  match result:
    case Done{res}:
      res
    case Fail{err}:
      Http.Res{502, Http.set(Http.empty(), "content-type", "text/plain"), "observer request failed"}

def relay(req: Http.Req) -> IO(Http.Res):
  Http.Req{method, path, headers, body} = req
  do IO<Http.Res>:
    result : Result<&2, &2, Http.Err, Http.Res> <- Http.fetch.how(
      "POST", "http://127.0.0.1:18774/relay", trace.headers(headers), body, 3000, Http.ModeManual{})
    return from.observer(result)

def url_value(value: Maybe<&2, Json.Val>) -> Maybe<&2, String>:
  match value:
    case Some{Json.Str{url}}:
      Some{url}
    case Some{value}:
      None{}
    case None{}:
      None{}

def body_value(value: Maybe<&2, Json.Val>) -> String:
  match value:
    case Some{arguments}:
      Json.encode(arguments)
    case None{}:
      "[]"

def action.url(action: Json.Val) -> Maybe<&2, String>:
  url_value(Json.get(action, "url"))

def action.body(action: Json.Val) -> String:
  body_value(Json.get(action, "arguments"))

def callback.result(result: Result<&2, &2, Http.Err, Http.Res>) -> Bool:
  match result:
    case Fail{err}:
      False{}
    case Done{res}:
      Http.Res{status, headers, body} = res
      U32.is_eq(status, 200)

def callbacks.action(action: Json.Val, url: Maybe<&2, String>) -> IO(Bool):
  match url:
    case None{}:
      IO.pure(Bool, False{})
    case Some{url}:
      do IO<Bool>:
        result : Result<&2, &2, Http.Err, Http.Res> <- Http.fetch.how(
          "POST", url,
          Http.set(Http.empty(), "content-type", "application/json"),
          action.body(action), 3000, Http.ModeManual{})
        return callback.result(result)

def callbacks(xs: List<&2, Json.Val>) -> IO(Bool):
  match xs:
    case Nil{}:
      IO.pure(Bool, True{})
    case Con{+action, rest}:
      do IO<Bool>:
        ok : Bool <- callbacks.action(action, action.url(action))
        later : Bool <- callbacks(rest)
        return Bool.and(ok, later)

def test.response.result(ok: Bool) -> IO(Http.Res):
  match ok:
    case True{}:
      IO.pure(Http.Res, Http.Res{200, Http.set(Http.empty(), "content-type", "application/json"), "{\"ok\":true}"})
    case False{}:
      IO.pure(Http.Res, Http.Res{502, Http.set(Http.empty(), "content-type", "application/json"), "{\"ok\":false}"})

def test.response.parsed(parsed: Maybe<&2, Json.Val>) -> IO(Http.Res):
  match parsed:
    case None{}:
      IO.pure(Http.Res, Http.Res{400, Http.empty(), "invalid JSON"})
    case Some{Json.Arr{actions}}:
      do IO<Http.Res>:
        ok : Bool <- callbacks(actions)
        response : Http.Res <- test.response.result(ok)
        return response
    case Some{value}:
      IO.pure(Http.Res, Http.Res{400, Http.empty(), "expected a JSON action array"})

def test.response(body: String) -> IO(Http.Res):
  test.response.parsed(Json.parse(body))

def route.test(req: Http.Req) -> IO(Http.Res):
  Http.Req{method, path, headers, body} = req
  test.response(body)

def route(req: Http.Req, is.test: Bool, is.relay: Bool) -> IO(Http.Res):
  match is.test:
    case True{}:
      route.test(req)
    case False{}:
      match is.relay:
        case True{}:
          relay(req)
        case False{}:
          IO.pure(Http.Res, Http.Res{404, Http.empty(), "not found"})

def handle(req: Http.Req) -> IO(Http.Res):
  Http.Req{method, +path, headers, body} = req
  route(req, String.eq(path, "/test"), String.eq(path, "/relay"))

def main() -> IO(Unit):
  Http.serve.with(~handle, 18773, 1048576n)
