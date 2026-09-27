import Base
import ../trace_context.bend as TC
import ../generation.bend as Generate
import ../native_http.bend as NativeHttp
import ../../../vendor/bend-net/http.bend as Http

# A gateway that takes part in the traces of the requests it handles, on the
# native HTTP transport bend-net. For each request it extracts the context
# from the request's header map and gives itself an operation of its own: a
# child of the request's context, or a root when the request has none. It
# then calls the downstream service with a new child of that operation among
# the call's headers (NativeHttp.send), and returns the downstream response.
# It extracts first, rather than calling NativeHttp.continue_or_start, so
# that its log can say why it continued or started a trace: an absent or a
# rejected traceparent, or a discarded state.
#
# Tracing never fails a request here (TC.Lenient{}). When no identifier can
# be generated, the call downstream forwards the received context unchanged
# or carries none, and the log line says why. A downstream that cannot be
# reached gives 502. The log holds the request's method and path and the
# package's diagnostics, which include no received context value: the
# gateway never logs header values.
#
# Build it natively from the repository root, after
# `git submodule update --init --recursive`:
#   ./bend packages/trace-context/examples/gateway.bend -o build/gateway
# It listens on 127.0.0.1:18777 and calls http://127.0.0.1:18776/downstream.

def downstream() -> String:
  "http://127.0.0.1:18776/downstream"

def text(status: U32, body: String) -> Http.Res:
  Http.Res{status, Http.set(Http.empty(), "content-type", "text/plain"), body}

# The downstream response, or 502 when the call failed.
def answer(result: Result<&2, &2, Http.Err, Http.Res>) -> Http.Res:
  match result:
    case Done{Http.Res{status, headers, body}}:
      Http.Res{status, Http.set(Http.empty(), "content-type", "application/json"), body}
    case Fail{error}:
      text(502, "downstream unavailable")

# Call the downstream service with the fields that the adapter wrote.
def call(+outbound: NativeHttp.Outbound, body: String) -> IO(Http.Res):
  do IO<Http.Res>:
    result : Result<&2, &2, Http.Err, Http.Res> <- Http.fetch.how("POST", downstream(),
      NativeHttp.Outbound.headers(outbound), body, 3000, Http.ModeManual{})
    return answer(result)

def handle(req: Http.Req) -> IO(Http.Res):
  Http.Req{method, path, +headers, body} = req
  +extraction = TC.Context.extract(TC.Limits.default(), NativeHttp.carrier(headers), None{})
  do IO<Http.Res>:
    +service : TC.Service <- Generate.Context.continue_or_start(extraction, TC.Continue{}, TC.InheritSampled{},
      TC.Lenient{})
    +outbound : NativeHttp.Outbound <- NativeHttp.send(TC.Limits.default(), service, TC.InheritSampled{},
      TC.Lenient{}, Http.set(Http.empty(), "content-type", "application/json"))
    Unit <- IO.print(method ++ " " ++ path ++ ": " ++ TC.Extraction.show(extraction) ++ "; " ++
      TC.Service.show(service) ++ ", downstream " ++ TC.Sent.show(NativeHttp.Outbound.sent(outbound)))
    call(outbound, body)

def main() -> IO(Unit):
  Http.serve.with(~handle, 18777, 1048576n)
