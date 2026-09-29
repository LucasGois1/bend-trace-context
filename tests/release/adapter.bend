# The native HTTP adapter of the published package, without bend-kit: a
# received header map continues its trace, and the header map of the request
# that the service sends carries a child in the same trace.
# scripts/qualify-release.sh imports the package by its name on the hub in
# place of PACKAGE.
import Base
import PACKAGE/trace_context.bend as TC
import PACKAGE/generation.bend as Generate
import PACKAGE/native_http.bend as NativeHttp

def received() -> Map<&2, List<&2, String>>:
  Map.set(&2, List<&2, String>, Map.new(&2, List<&2, String>), "traceparent",
    ["00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"])

# The version and trace ID of the first of these traceparent values.
def trace.of(values: List<&2, String>) -> String:
  match values:
    case Nil{}:
      "no traceparent"
    case Con{value, rest}:
      String.take(value, 35n)

# The version and trace ID of the traceparent of a header map.
def trace(headers: Map<&2, List<&2, String>>) -> String:
  trace.of(Pair.snd(Map<&2, List<&2, String>>, List<&2, String>,
    Map.get(List<&2, String>, Nil{}, headers, "traceparent")))

def main() -> IO(Unit):
  do IO<Unit>:
    +service : TC.Service <- Generate.NativeHttp.continue_or_start(TC.Limits.default(), received(), None{},
      TC.Continue{}, TC.InheritSampled{}, TC.Lenient{})
    +outbound : NativeHttp.Outbound <- Generate.NativeHttp.send(TC.Limits.default(), service, TC.InheritSampled{},
      TC.Lenient{}, Map.new(&2, List<&2, String>))
    Unit <- IO.print(TC.Service.show(service) ++ ", downstream " ++ TC.Sent.show(NativeHttp.Outbound.sent(outbound)))
    IO.print(trace(NativeHttp.Outbound.headers(outbound)))
