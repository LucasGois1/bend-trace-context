# Guide

This guide explains what bend-trace-context does, the few ideas that you
need to use it, and how to do common tasks in Bend. The
[Bend API reference](README.md) lists every operation, the
[JavaScript guide](JAVASCRIPT.md) covers Node and browser pages, and
[Errors and diagnostics](ERRORS.md) lists every error and log name. The
[glossary](../../CONTEXT.md) defines the terms used throughout.

- [What the package does](#what-the-package-does)
- [Trace Context in five minutes](#trace-context-in-five-minutes)
- [How a service takes part](#how-a-service-takes-part)
- [Choosing a module](#choosing-a-module)
- [Decisions a service makes](#decisions-a-service-makes)
- [Recipes](#recipes)
- [Writing Bend with the package](#writing-bend-with-the-package)
- [Security considerations](#security-considerations)
- [Questions](#questions)
- [Troubleshooting](#troubleshooting)
- [OpenTelemetry](#opentelemetry)

## What the package does

bend-trace-context propagates [W3C Trace Context Level 2](https://www.w3.org/TR/2024/CRD-trace-context-2-20240328/),
the `traceparent` and `tracestate` header fields that let the services of a
system follow one request through all of them. For a service it:

- reads the context of each message that it receives, and refuses malformed
  or oversized values as the standard asks;
- gives the service an operation of its own for each message: a child of
  the caller's operation, or the root of a new trace;
- gives each message that the service sends a child of that operation,
  written into the message's fields;
- generates the trace and span IDs on the host's cryptographic source, or on
  a source that the caller supplies, and keeps and edits `tracestate` within
  budgets;
- reports what happened to each message in log-safe names, such as
  `TraceParentAccepted, StateAccepted`, that never contain a received value.

It does not record, sample or export spans, and it logs nothing. It is the
propagation layer that a tracer builds on: pair it with a tracer, such as
[OpenTelemetry](#opentelemetry), to record spans, or log its IDs to
correlate your logs.

It runs natively on macOS ARM64 and Linux x86_64, in Bend programs compiled
to JavaScript for Node, and, through its JavaScript facade, in Node
applications and in browser pages, as the
[support table](../../README.md#where-it-runs) details. Its rules are
stated as laws over every input and proved with Bend's checker, and its
behavior is tested against independent vectors and the W3C test harness;
the [reference](README.md#proofs) describes exactly what is proved.

## Trace Context in five minutes

A **trace** is the tree of operations that one request causes across
services. Each **operation**, which tracers call a span, has an 8-byte span
ID; the whole trace shares a 16-byte trace ID. When a service calls another,
it sends the context of the operation that makes the call, and the receiver
creates its own operation as a **child** of it.

The `traceparent` field carries that context:

```text
00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
│  │                                │                └─ trace flags
│  │                                └─ parent ID: the sender's operation
│  └─ trace ID: the whole trace
└─ version
```

- The **trace ID** stays the same across the whole trace. A new trace, a
  **root**, gets a new one.
- The **parent ID** is the span ID of the sender's operation. Every
  operation has its own span ID, so a service never reuses the one it
  received.
- The **sampled** flag (`01`) tells the next services that the caller may
  record the trace. It is only an indication: the package records nothing,
  and many samplers follow it. New traces start unsampled; see
  [Sampling](#sampling).
- The **random-trace-id** flag (`02`) says that the trace ID was generated
  randomly. Every trace ID that the package generates sets it, so a new
  unsampled trace is sent with flags `02`.

`tracestate` carries vendor entries, such as `congo=t61rcWkgMzE,rojo=00f0`,
one per tracing system. A participant that changes its own entry puts it
first and keeps the others in their order. A service that receives no valid
`traceparent` ignores `tracestate`.

## How a service takes part

A service does three things for each request that it handles:

```text
received request ─ extract ─▶ Extraction ─ continue or start ─▶ Service
                                                                  │
      each request that the service sends ◀─ send (a new child) ──┘
```

1. **Extract** the context of the received request from its fields in
   their order, which the package calls the **carrier**: an `Extraction`,
   which says what it found. It keeps the request's context, or, when the
   request has no usable `traceparent`, a **base** context that you pass,
   such as the operation of a batch that a [queue worker](#a-queue-worker)
   handles; `None{}` passes none.
2. **Continue or start**: the service's own operation for the request, a
   `Service`. It is a child of the kept context, or a root when extraction
   kept none. Its `reception` argument says what to do with a kept
   context: `TC.Continue{}` continues it, and `TC.Restart{}` starts a new
   trace in its place, at a [trust boundary](#continue-or-restart).
3. **Send**, once for every request that the service sends: a `Sent`, a new
   child of the service's operation, written into that request's own fields.
   Each request of a fan-out gets its own child.

| Step | Bend | JavaScript |
| --- | --- | --- |
| Extract | `TC.Context.extract` | `extract`, or `extractRequest` for `node:http` |
| Continue or start | `Generate.Context.continue_or_start` | `continueOrStart`, or `continueOrStartRequest` |
| Send | `Generate.Context.send` | `send`, or `tracedFetch` in a page |
| Both on a header map | `Generate.NativeHttp.continue_or_start` and `Generate.NativeHttp.send` | — |

The [quick start](../../README.md#quick-start-bend) does all three in a
dozen lines. The same operations take a source of words that you supply
(`TC.Context.continue_or_start_with` and `TC.Context.send_with`), for tests
and for hosts with their own generator.

## Choosing a module

| Module | Import it for | Host effects |
| --- | --- | --- |
| [trace_context.bend](trace_context.bend) | Everything that decides a Trace Context rule: the codec, IDs and contexts, `tracestate`, limits, extraction, injection, forwarding, and generation on a source that you supply | None |
| [generation.bend](generation.bend) | The same operations on the host's cryptographic source: `Context.root`, `child`, `restart`, `continue_or_start` and `send`, and the native HTTP shortcuts `NativeHttp.continue_or_start` and `NativeHttp.send` | Reads the host's entropy |
| [native_http.bend](native_http.bend) | The header maps of bend-kit's HTTP package: `carrier`, `headers`, `Outbound`, and the shortcuts on a source that you supply | None |
| `bend-trace-context`, `/node`, `/fetch` | JavaScript applications and pages, as the [JavaScript guide](JAVASCRIPT.md) describes | WebCrypto |

Most services import `trace_context.bend` as `TC` and `generation.bend` as
`Generate`, and add `native_http.bend` as `NativeHttp` on bend-kit.
generation.bend reads the host's entropy through a foreign effect, so a
check of a file that imports it prints `SOME PROOFS FAIL` and names its host
operations; see [Troubleshooting](#troubleshooting).

## Decisions a service makes

### Continue or restart

`TC.Continue{}` continues the kept context: the service's operation is its
child, with its `tracestate`. `TC.Restart{}` is for a **trust boundary**,
such as a public ingress, where the caller's context should not be trusted
or disclosed: the service starts a new trace in its place, keeps none of its
state, and never reuses its trace ID. When extraction keeps no context, the
service starts a new trace either way. See
[A public ingress](#a-public-ingress).

### Sampling

`TC.InheritSampled{}` gives a child its parent's sampled flag, and a root or
a restart the root default: not sampled. Samplers that follow the parent,
such as OpenTelemetry's default, then drop traces that your service starts.
To have them recorded, set the flag where they start, with
`TC.SetSampled{True{}}`. The common policy keeps the caller's decision for
the traces that the service continues and samples the traces that it
starts: [New traces that are sampled](#new-traces-that-are-sampled) shows
it. The flag never decides anything in the package itself.

### Failure policy

Generating an ID can fail, when the host has no entropy or a source that you
supply fails. `TC.Lenient{}`, the common choice, lets the business request
proceed: the service has no operation (`Untraced ...`), and each request
that it sends forwards the received context unchanged when it can, or goes
without context fields; the diagnostics say which. `TC.Strict{}` returns the
error instead, so that the service can refuse the request, for example with
a 503. The package never retries and never falls back to a time or a
counter.

### Your own entry

A service that keeps state in `tracestate` sets its entry on the `Service`
with `TC.Service.set`: it goes first in the state that the service's
operation sends, and the other entries follow in their order; see
[Your own tracestate entry](#your-own-tracestate-entry). A service never
edits the state of a context that it forwards unchanged.

### Limits

`TC.Limits.default()` bounds a received `traceparent` to 32 KiB, all the
`tracestate` fields of a message together to 32 KiB, and the `tracestate`
that the package emits to 512 octets, removing whole entries to fit.
`TC.Limits.new` sets other budgets within the [rules](README.md#limits).

### Participate or forward

A service that does work of its own **participates**: it continues or starts
and sends, as above. An intermediary that only passes requests on, such as a
proxy, can **forward** the received pair unchanged with `TC.Context.forward`
instead, and creates no operation; see [A relay](#a-relay).

## Recipes

Each recipe is a complete program. Put the package in your project as the
[root README](../../README.md#install) shows, at `deps/bend-trace-context`,
and run a recipe with `./deps/bend-trace-context/bend recipe.bend`, or
build it with `-o recipe` for a native binary. To import the package from
BendHub instead, replace `./deps/bend-trace-context/packages/trace-context/`
in the imports with `bend-trace-context@0.1.1.0/`. The recipes with new IDs
print only what does not change from run to run, apart from the span IDs of
log fields; each shows its output.

### A native HTTP service

A gateway on bend-kit's HTTP package: for each request it gives itself an
operation, calls a downstream service with a child of it, and logs the
package's diagnostics. It is the program of
[examples/gateway.bend](examples/gateway.bend), with the imports that your
project uses; the [reference](README.md#native-http-integration) describes
the adapter and the first build fetches bend-kit from BendHub.

<!-- test:guide-gateway:start -->
```bend
import Base
import ./deps/bend-trace-context/packages/trace-context/trace_context.bend as TC
import ./deps/bend-trace-context/packages/trace-context/generation.bend as Generate
import ./deps/bend-trace-context/packages/trace-context/native_http.bend as NativeHttp
# bend-kit-http 0.23.0.1, from BendHub by content hash.
import 0x1cef8a5fb1d9142ca5c6b2cb43629b21/http.bend as Http

def downstream() -> String:
  "http://127.0.0.1:18776/downstream"

def text(status: U32, body: String) -> Http.Res:
  Http.Res{status, Http.set(Http.empty(), "content-type", "text/plain"), Http.from_string(body)}

# The downstream response, or 502 when the call failed.
def answer(result: Result<&1, &1, Http.Err, Http.Res>) -> Http.Res:
  match result:
    case Done{Http.Res{status, headers, body}}:
      Http.Res{status, Http.set(Http.empty(), "content-type", "application/json"), body}
    case Fail{error}:
      text(502, "downstream unavailable")

# Call the downstream service with the fields that the adapter wrote.
def call(+outbound: NativeHttp.Outbound, body: Http.Body()) -> IO(Http.Res):
  do IO<Http.Res>:
    result : Result<&1, &1, Http.Err, Http.Res> <- Http.fetch.how("POST", downstream(),
      NativeHttp.Outbound.headers(outbound), body, 3000, Http.ModeManual{})
    return answer(result)

def handle(req: Http.Req) -> IO(Http.Res):
  Http.Req{method, path, +headers, body} = req
  # Extracting first lets the log say why the service continued or started.
  +extraction = TC.Context.extract(TC.Limits.default(), NativeHttp.carrier(headers), None{})
  do IO<Http.Res>:
    +service : TC.Service <- Generate.Context.continue_or_start(extraction, TC.Continue{}, TC.InheritSampled{},
      TC.Lenient{})
    +outbound : NativeHttp.Outbound <- Generate.NativeHttp.send(TC.Limits.default(), service, TC.InheritSampled{},
      TC.Lenient{}, Http.set(Http.empty(), "content-type", "application/json"))
    Unit <- IO.print(method ++ " " ++ path ++ ": " ++ TC.Extraction.show(extraction) ++ "; " ++
      TC.Service.show(service) ++ ", downstream " ++ TC.Sent.show(NativeHttp.Outbound.sent(outbound)))
    call(outbound, body)

def main() -> IO(Unit):
  Http.serve.with(~handle, 18777, 1048576n)
```
<!-- test:guide-gateway:end -->

Build it with `./deps/bend-trace-context/bend gateway.bend -o gateway`; the
native build of bend-kit takes a few minutes. A request with a
`traceparent` and a `tracestate` logs
`POST /orders: TraceParentAccepted, StateAccepted; Continued, downstream Fresh`,
and one without context fields logs
`POST /orders: TraceParentAbsent, StateAbsent; Started, downstream Fresh`;
the propagation tests check both. When the service does not need that log
line, `Generate.NativeHttp.continue_or_start` takes the header map directly.

The program uses two operations of bend-kit, which its
[HTTP package's README](https://github.com/paymog/bend-kit/blob/31912fbd99e9090df43bf2ef70da4340241e9e51/http/README.md)
documents:

- `Http.serve.with(~handle, 18777, 1048576n)` runs `handle` for each request
  on port 18777 of every interface, and answers 413 to a body over 1 MiB.
  `Http.serve(~handle, port)` allows bodies of up to 16 MiB.
- `Http.fetch.how(method, url, headers, body, 3000, Http.ModeManual{})`
  sends a request and fails it when a step takes longer than 3000 ms.
  `Http.ModeManual{}` returns a redirect as the response instead of
  following it, so the call and its context fields never go to a URL that
  downstream names; `answer` passes its status and body on.
  `Http.ModeFollow{}` follows redirects, and `Http.ModeError{}` fails the
  call.

### Log correlation

Log the trace and span IDs of the service's operation with your log lines,
so that a log backend can relate them to the traces of other services. A
service without an operation, `Untraced`, has no IDs; log its `show`,
which says why.

<!-- test:guide-log:start -->
```bend
import Base
import ./deps/bend-trace-context/packages/trace-context/trace_context.bend as TC
import ./deps/bend-trace-context/packages/trace-context/generation.bend as Generate

def received() -> List<&2, TC.Header>:
  [TC.Header{"traceparent", "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"}]

# The trace and span IDs of an operation, as fields of a log line.
def ids(+operation: TC.LocalContext) -> String:
  "trace_id=" ++ TC.TraceId.to_string(TC.LocalContext.trace_id(operation)) ++ " span_id=" ++
    TC.SpanId.to_string(TC.LocalContext.span_id(operation))

# The log fields of a service: the IDs of its operation, or why it has none.
def trace_fields(outgoing: Maybe<&2, TC.OutgoingContext>, show: String) -> String:
  match outgoing:
    case Some{context}:
      ids(TC.OutgoingContext.context(context))
    case None{}:
      "tracing=\"" ++ show ++ "\""

def main() -> IO(Unit):
  do IO<Unit>:
    +service : TC.Service <- Generate.Context.continue_or_start(TC.Context.extract(TC.Limits.default(), received(),
      None{}), TC.Continue{}, TC.InheritSampled{}, TC.Lenient{})
    IO.print("order placed " ++ trace_fields(TC.Service.outgoing(service), TC.Service.show(service)))
```
<!-- test:guide-log:end -->

The span ID is new on every run:

<!-- test:guide-log-output:start -->
```text
order placed trace_id=4bf92f3577b34da6a3ce929d0e0e4736 span_id=b9c7c989f97918e1
```
<!-- test:guide-log-output:end -->

### Work without a request

A scheduled job starts its own trace: extraction of no fields keeps no
context, so the service's operation is a new root, and the requests that
the job sends carry its children. A worker that handles messages from a
queue continues their context instead, as [A queue worker](#a-queue-worker)
shows.

<!-- test:guide-job:start -->
```bend
import Base
import ./deps/bend-trace-context/packages/trace-context/trace_context.bend as TC
import ./deps/bend-trace-context/packages/trace-context/generation.bend as Generate

# The flags of an operation's traceparent: 02 for a new unsampled trace.
def flags(operation: Maybe<&2, TC.LocalContext>) -> String:
  match operation:
    case Some{context}:
      String.drop(TC.TraceParentV00.format(TC.LocalContext.to_traceparent(context)), 53n)
    case None{}:
      "none"

def main() -> IO(Unit):
  # Work that no request started: extraction of no fields keeps no context,
  # so the service's operation is a new trace.
  +extraction = TC.Context.extract(TC.Limits.default(), [], None{})
  do IO<Unit>:
    +service : TC.Service <- Generate.Context.continue_or_start(extraction, TC.Continue{}, TC.InheritSampled{},
      TC.Lenient{})
    +sent : TC.Sent <- Generate.Context.send(TC.Limits.default(), service, TC.InheritSampled{}, TC.Lenient{},
      [TC.Header{"content-type", "text/csv"}])
    Unit <- IO.print(TC.Extraction.show(extraction))
    Unit <- IO.print(TC.Service.show(service))
    IO.print(TC.Sent.show(sent) ++ ", flags " ++ flags(TC.Sent.operation(sent)))
```
<!-- test:guide-job:end -->

<!-- test:guide-job-output:start -->
```text
TraceParentAbsent, StateAbsent
Started
Fresh, flags 02
```
<!-- test:guide-job-output:end -->

`Generate.Context.root()` gives the same root without a `Service`, for code
that manages its operations itself.

### New traces that are sampled

This service keeps the caller's decision for the traces that it continues,
and samples the traces that it starts: it passes `TC.SetSampled{True{}}`
only when extraction keeps no context. The children that it sends inherit
the flag, so samplers that follow the parent record the traces that it
starts.

<!-- test:guide-sampled:start -->
```bend
import Base
import ./deps/bend-trace-context/packages/trace-context/trace_context.bend as TC
import ./deps/bend-trace-context/packages/trace-context/generation.bend as Generate

# Keep the caller's decision for a kept context, and sample a new trace.
def sampling(kept: Maybe<&2, TC.BaseContext>) -> TC.Sampling:
  match kept:
    case Some{context}:
      TC.InheritSampled{}
    case None{}:
      TC.SetSampled{True{}}

def flags(operation: Maybe<&2, TC.LocalContext>) -> String:
  match operation:
    case Some{context}:
      String.drop(TC.TraceParentV00.format(TC.LocalContext.to_traceparent(context)), 53n)
    case None{}:
      "none"

# The service's operation for a request with these fields, and the flags of
# the request that it sends.
def handle(fields: List<&2, TC.Header>) -> IO(Unit):
  +extraction = TC.Context.extract(TC.Limits.default(), fields, None{})
  do IO<Unit>:
    +service : TC.Service <- Generate.Context.continue_or_start(extraction, TC.Continue{},
      sampling(TC.Extraction.context(extraction)), TC.Lenient{})
    +sent : TC.Sent <- Generate.Context.send(TC.Limits.default(), service, TC.InheritSampled{}, TC.Lenient{}, [])
    IO.print(TC.Service.show(service) ++ ", downstream flags " ++ flags(TC.Sent.operation(sent)))

def main() -> IO(Unit):
  do IO<Unit>:
    # A caller that did not sample its trace.
    Unit <- handle([TC.Header{"traceparent", "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00"}])
    # A request without context: this service starts the trace, sampled.
    handle([])
```
<!-- test:guide-sampled:end -->

<!-- test:guide-sampled-output:start -->
```text
Continued, downstream flags 00
Started, downstream flags 03
```
<!-- test:guide-sampled-output:end -->

Passing `TC.SetSampled{True{}}` always would also override the caller's
decision for the traces that the service continues.

### Your own tracestate entry

The service's entry goes first in the state that its operation sends; the
received entries follow in their order. Keys and values are validated once,
like IDs.

<!-- test:guide-vendor:start -->
```bend
import Base
import ./deps/bend-trace-context/packages/trace-context/trace_context.bend as TC
import ./deps/bend-trace-context/packages/trace-context/generation.bend as Generate

def received() -> List<&2, TC.Header>:
  [TC.Header{"traceparent", "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"},
    TC.Header{"tracestate", "congo=t61rcWkgMzE,rojo=00f067aa0ba902b7"}]

# This service's entry, first in the state that its operation sends. A
# refused key or value leaves the state as it is.
def own(service: TC.Service, key: Result<&2, &2, TC.EntryError, TC.StateKey>,
  value: Result<&2, &2, TC.EntryError, TC.StateValue>) -> TC.Service:
  match key value:
    case Done{key} Done{value}:
      TC.Service.set(service, key, value)
    case _ _:
      service

# The tracestate field of a request's fields.
def tracestate(fields: List<&2, TC.Header>) -> String:
  match fields:
    case Nil{}:
      "no tracestate"
    case Con{TC.Header{name, value}, rest}:
      Bool.pick(String, String.eq(name, "tracestate"), value, tracestate(rest))

def main() -> IO(Unit):
  do IO<Unit>:
    service : TC.Service <- Generate.Context.continue_or_start(TC.Context.extract(TC.Limits.default(), received(),
      None{}), TC.Continue{}, TC.InheritSampled{}, TC.Lenient{})
    +sent : TC.Sent <- Generate.Context.send(TC.Limits.default(), own(service, TC.StateKey.parse("fw529a3039"),
      TC.StateValue.parse("cHJpbWFyeQ")), TC.InheritSampled{}, TC.Lenient{}, [])
    IO.print(tracestate(TC.Sent.carrier(sent)))
```
<!-- test:guide-vendor:end -->

<!-- test:guide-vendor-output:start -->
```text
fw529a3039=cHJpbWFyeQ,congo=t61rcWkgMzE,rojo=00f067aa0ba902b7
```
<!-- test:guide-vendor-output:end -->

### A public ingress

At a trust boundary the service restarts the trace: a new trace ID, no
received state, and the root defaults.

<!-- test:guide-boundary:start -->
```bend
import Base
import ./deps/bend-trace-context/packages/trace-context/trace_context.bend as TC
import ./deps/bend-trace-context/packages/trace-context/generation.bend as Generate

# A request from outside this system, carrying another party's context.
def received() -> List<&2, TC.Header>:
  [TC.Header{"traceparent", "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"},
    TC.Header{"tracestate", "partner=internal-routing"}]

# Whether the service's operation belongs to another trace than the request.
def new_trace(outgoing: Maybe<&2, TC.OutgoingContext>) -> String:
  match outgoing:
    case Some{context}:
      Bool.show(Bool.not(String.eq(TC.TraceId.to_string(TC.LocalContext.trace_id(TC.OutgoingContext.context(context))),
        "4bf92f3577b34da6a3ce929d0e0e4736")))
    case None{}:
      "none"

def main() -> IO(Unit):
  +extraction = TC.Context.extract(TC.Limits.default(), received(), None{})
  do IO<Unit>:
    +service : TC.Service <- Generate.Context.continue_or_start(extraction, TC.Restart{}, TC.InheritSampled{},
      TC.Lenient{})
    Unit <- IO.print(TC.Extraction.show(extraction))
    IO.print(TC.Service.show(service) ++ ", new trace: " ++ new_trace(TC.Service.outgoing(service)))
```
<!-- test:guide-boundary:end -->

<!-- test:guide-boundary-output:start -->
```text
TraceParentAccepted, StateAccepted
Restarted, new trace: True
```
<!-- test:guide-boundary-output:end -->

### A relay

A proxy that takes no part in the trace forwards the received pair
unchanged into the request that it sends on: the `traceparent` as
extraction accepted it, without the whitespace around it, and the
`tracestate` fields joined by commas in their order. Or it learns why it
cannot: a `tracestate` larger than the output budget, or one that was
discarded.

<!-- test:guide-relay:start -->
```bend
import Base
import ./deps/bend-trace-context/packages/trace-context/trace_context.bend as TC

def received() -> List<&2, TC.Header>:
  [TC.Header{"Host", "gateway.internal"},
    TC.Header{"traceparent", "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"},
    TC.Header{"tracestate", "congo=t61rcWkgMzE"}]

# The fields of a message, one per line.
def fields(carrier: List<&2, TC.Header>) -> String:
  match carrier:
    case Nil{}:
      ""
    case Con{TC.Header{name, value}, Nil{}}:
      name ++ ": " ++ value
    case Con{TC.Header{name, value}, rest}:
      name ++ ": " ++ value ++ "\n" ++ fields(rest)

def forwarded(result: Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>) -> String:
  match result:
    case Done{carrier}:
      fields(carrier)
    case Fail{error}:
      "not forwarded: " ++ TC.ForwardError.show(error)

def relayed(incoming: Maybe<&2, TC.IncomingContext>) -> String:
  match incoming:
    case Some{context}:
      forwarded(TC.Context.forward(TC.Limits.default(), context, [TC.Header{"Host", "orders.internal"}]))
    case None{}:
      "nothing to forward"

def main() -> IO(Unit):
  IO.print(relayed(TC.Extraction.incoming(TC.Context.extract(TC.Limits.default(), received(), None{}))))
```
<!-- test:guide-relay:end -->

<!-- test:guide-relay-output:start -->
```text
Host: orders.internal
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
tracestate: congo=t61rcWkgMzE
```
<!-- test:guide-relay-output:end -->

A relay that cannot forward a pair continues the trace with an operation of
its own instead, as the [reference](README.md#injecting-and-forwarding-context)
describes.

### A queue worker

A worker that processes a batch continues its own batch operation for the
messages that carry no context: the batch is the **base** that extraction
keeps when a message has no usable `traceparent`. A message with one
continues its own trace instead.

<!-- test:guide-worker:start -->
```bend
import Base
import ./deps/bend-trace-context/packages/trace-context/trace_context.bend as TC
import ./deps/bend-trace-context/packages/trace-context/generation.bend as Generate

# A message from a queue that carries no trace context.
def message() -> List<&2, TC.Header>:
  [TC.Header{"content-type", "application/json"}]

# Whether two operations belong to the same trace.
def same_trace(batch: TC.LocalContext, outgoing: Maybe<&2, TC.OutgoingContext>) -> String:
  match outgoing:
    case Some{context}:
      Bool.show(TC.TraceId.is_eq(TC.LocalContext.trace_id(batch), TC.LocalContext.trace_id(
        TC.OutgoingContext.context(context))))
    case None{}:
      "none"

# Handle one message: without a usable traceparent it continues the base,
# the batch's own operation.
def handle(+batch: TC.LocalContext) -> IO(Unit):
  +extraction = TC.Context.extract(TC.Limits.default(), message(),
    Some{TC.OutgoingBase{TC.OutgoingContext.new(batch)}})
  do IO<Unit>:
    +service : TC.Service <- Generate.Context.continue_or_start(extraction, TC.Continue{}, TC.InheritSampled{},
      TC.Lenient{})
    Unit <- IO.print(TC.Extraction.show(extraction))
    IO.print(TC.Service.show(service) ++ ", same trace as the batch: " ++ same_trace(batch,
      TC.Service.outgoing(service)))

def started(root: Result<&2, &2, TC.GenerationError, TC.LocalContext>) -> IO(Unit):
  match root:
    case Done{batch}:
      handle(batch)
    case Fail{error}:
      IO.print("no batch operation: " ++ TC.GenerationError.show(error))

def main() -> IO(Unit):
  do IO<Unit>:
    # The batch's own operation, the root of a new trace.
    root : Result<&2, &2, TC.GenerationError, TC.LocalContext> <- Generate.Context.root()
    started(root)
```
<!-- test:guide-worker:end -->

<!-- test:guide-worker-output:start -->
```text
TraceParentAbsent, StateAbsent
Continued, same trace as the batch: True
```
<!-- test:guide-worker-output:end -->

A base can also be an `IncomingBase{incoming}`, a context received earlier,
such as the one of the request that enqueued the batch.

### Identifiers from another tracer

When another tracer already created the operation, the service represents it
with its identifiers and sampled flag, `TC.Context.from_ids`, and sends it
with the package. Invalid identifiers are refused with their error.

<!-- test:guide-supplied:start -->
```bend
import Base
import ./deps/bend-trace-context/packages/trace-context/trace_context.bend as TC

# The traceparent of an operation that another tracer created, as the
# package sends it.
def sent(trace: Result<&2, &2, TC.Error, TC.TraceId>, span: Result<&2, &2, TC.Error, TC.SpanId>) -> String:
  match trace span:
    case Done{trace_id} Done{span_id}:
      TC.Emission.traceparent(TC.OutgoingContext.emit(TC.Limits.default(),
        TC.OutgoingContext.new(TC.Context.from_ids(trace_id, span_id, True{}))))
    case Fail{error} _:
      "invalid trace ID: " ++ TC.Error.show(error)
    case _ Fail{error}:
      "invalid span ID: " ++ TC.Error.show(error)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.print(sent(TC.TraceId.parse("4bf92f3577b34da6a3ce929d0e0e4736"), TC.SpanId.parse("53995c3f42cd8ad8")))
    IO.print(sent(TC.TraceId.parse("4bf92f3577b34da6a3ce929d0e0e4736"), TC.SpanId.parse("0000000000000000")))
```
<!-- test:guide-supplied:end -->

<!-- test:guide-supplied-output:start -->
```text
00-4bf92f3577b34da6a3ce929d0e0e4736-53995c3f42cd8ad8-01
invalid span ID: ZeroSpanId
```
<!-- test:guide-supplied-output:end -->

`TC.Context.root_from_ids`, `child_from_id` and `restart_from_ids` create
roots, children and restarts from supplied IDs, as the
[reference](README.md#supplied-ids-and-contexts) describes.

### Deterministic tests

The `_with` operations take a source of words instead of the host's, so a
test knows the IDs in advance. `TC.Source.tape` replays a list of word
results, most significant word first.

<!-- test:guide-tape:start -->
```bend
import Base
import ./deps/bend-trace-context/packages/trace-context/trace_context.bend as TC

# 1402559551 and 1120766680 are 53995c3f and 42cd8ad8 in hexadecimal: the
# span ID of the service's operation.
def words() -> List<&1, Result<&1, &1, U32 & String, U32>>:
  [Done{1402559551}, Done{1120766680}]

def received() -> List<&2, TC.Header>:
  [TC.Header{"traceparent", "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"}]

def traceparent(outgoing: Maybe<&2, TC.OutgoingContext>) -> String:
  match outgoing:
    case Some{context}:
      TC.TraceParentV00.format(TC.LocalContext.to_traceparent(TC.OutgoingContext.context(context)))
    case None{}:
      "none"

# The service, with the words that the tape has left.
def described(done: List<&1, Result<&1, &1, U32 & String, U32>> & TC.Service) -> String:
  (rest, +service) = done
  TC.Service.show(service) ++ " " ++ traceparent(TC.Service.outgoing(service))

def main() -> IO(Unit):
  do IO<Unit>:
    done : List<&1, Result<&1, &1, U32 & String, U32>> & TC.Service <- TC.Context.continue_or_start_with(
      ~List<&1, Result<&1, &1, U32 & String, U32>>, ~TC.Source.tape, words(),
      TC.Context.extract(TC.Limits.default(), received(), None{}), TC.Continue{}, TC.InheritSampled{}, TC.Lenient{})
    IO.print(described(done))
```
<!-- test:guide-tape:end -->

<!-- test:guide-tape-output:start -->
```text
Continued 00-4bf92f3577b34da6a3ce929d0e0e4736-53995c3f42cd8ad8-01
```
<!-- test:guide-tape-output:end -->

A tape entry `Fail{(code, message)}` makes the source fail at that word,
and an empty tape fails with `SourceFailure 1 tape-exhausted`, which
exercises the failure policies.

## Writing Bend with the package

`bend guide` explains the language; these points come up with this package:

- An IO program runs its steps in a `do IO<Unit>:` block, each step
  `name : Type <- action` or `Unit <- action`.
- Bend is affine: a variable is used at most once, unless it is bound with
  `+`, as in `+service : TC.Service <- ...`, which lets a value of a `Data`
  type be used again. Most of the package's values are `Data`.
- A `match` inspects a parameter or a variable bound by a pattern, never a
  computed value: give the computed value to a helper `def` that matches on
  its parameter, as `forwarded` does in [A relay](#a-relay).
- A `def` can only use the definitions above it, and cannot call itself
  through another one.
- Results are `Done{value}` or `Fail{error}`, and optional values
  `Some{value}` or `None{}`.
- Numbers have no hexadecimal literals: write `1402559551`, not
  `0x53995c3f`.
- `./bend file.bend` runs a program; `-o file` builds a native binary,
  `-o file.js` a program for Node, and `-o file.mjs` an ES module of its
  functions, which runs nothing when Node starts it.

## Security considerations

- **Logs.** The diagnostics of extraction, of services and of sent
  messages never contain a received value, so they can be logged; only the
  strict codec's `UnsupportedVersion` names the two version digits that it
  refused. Header values themselves can hold data: a `tracestate` may carry
  vendor data. The package logs nothing.
- **Untrusted input.** Budgets bound what a message makes the package read,
  by default 32 KiB for the `traceparent` and 32 KiB for all `tracestate`
  fields together, and an oversized value is refused before it is read. A
  repeated `traceparent` is refused, since a host may join two into one
  value. A control character in a later version's unknown fields is
  refused, so a forwarded value can never add a line to a message. An
  invalid `tracestate` is discarded as a whole.
- **Trust boundaries.** A received context is the caller's claim. Restart at
  a public ingress, and never base an authorization decision on the trace ID
  or the flags.
- **Forwarding.** `forward` sends the received pair unchanged, and only when
  it reads back as extraction would accept it under the limits that you
  pass. It refuses what it cannot send whole, so a `traceparent` never
  travels with an edited or truncated `tracestate`.
- **Entropy.** The host's cryptographic generator makes new IDs. A source
  that you supply is trusted to be random: the package cannot check it.
- **Browsers.** By default only requests to the page's own origin carry
  the context fields; allow other origins with `propagateTo` once their
  CORS preflight accepts the fields. A redirect that `fetch` follows sends
  the same fields to its new URL, which the allowlist does not check: pass
  `redirect: 'error'` or `'manual'` for requests whose redirects may leave
  the allowed origins. Escape the values that a server renders into a page,
  as the [JavaScript guide](JAVASCRIPT.md#serving-a-page) shows.
- **bend-kit.** Its `Http.serve` listens on every interface.

Report a vulnerability as [SECURITY.md](../../SECURITY.md) describes.

## Questions

**Does the package record spans or send them to a backend?** No. It
propagates context: the IDs and flags that a tracer needs. Pair it with a
tracer to record spans, or log its IDs; see [OpenTelemetry](#opentelemetry)
and [Log correlation](#log-correlation).

**Does it decide what to sample?** No. It carries the caller's sampled
flag to the children that a service sends, and sets it only where you ask;
see [Sampling](#sampling).

**Which Bend versions does it support?** Exactly one: 2.0.34 on `master`,
and 2.0.32 for 0.1.1, which `setup-bend.sh` installs. Moving to another
version needs the package's own gates to pass on it first.

**Can a Bend service and a JavaScript one share traces?** Yes. Both speak
the W3C fields, and the JavaScript facade runs this same package, so they
follow the same rules. Both also pass the W3C Trace Context test harness at
Level 2, which checks a service against the standard's rules in the
scenarios that it runs.

## Troubleshooting

**`bend app.bend --check-only` prints `SOME PROOFS FAIL`.** It lists, by
their paths, the definitions that rely on `@unsafe` or foreign code, and
those of your program that use them, such as `main`: a program that
imports generation.bend lists its host operations, such as
`deps/bend-trace-context/packages/trace-context/generation.Context.root`,
and one on bend-kit lists bend-kit's. The check exits with status 1. That is
expected, and the program builds and runs. Keep the laws of your own
project in files that import only trace_context.bend, with the `_with`
operations on a source that you pass, as this package's laws are.

**A `match` fails with "a match cannot scrutinize a computed value".** Move
it into a helper `def`; see
[Writing Bend with the package](#writing-bend-with-the-package).

**My tracing backend shows no traces.** The package records no spans: a
tracer records them, and a Bend service logs its IDs instead; see
[OpenTelemetry](#opentelemetry). A tracer's sampler usually follows the
sampled flag, and new traces start unsampled; see [Sampling](#sampling).

**A program built with `-o app.mjs` does nothing.** `-o app.mjs` builds an
ES module of the program's functions, which runs nothing when Node starts
it. Build a program for Node with `-o app.js`, or a native binary with
`-o app`.

**Extraction reports `TraceParentRejected RepeatedTraceParent`.** The
request carried two `traceparent` fields, or a proxy joined two into one
value with a comma. The service starts a new trace, or continues your base.

**Extraction reports `StateDiscarded ...`.** The `tracestate` was invalid or
too large and was dropped as a whole; the `traceparent` is still continued.

**A service is `Untraced SourceFailure ...`.** No ID could be generated:
the host has no entropy, or your source failed. Under the lenient policy the
requests still go out; [Errors and diagnostics](ERRORS.md) lists each code.

**A native build is slow.** A program on bend-kit takes minutes to build
natively; `./bend file.bend` runs it without a native build.

For the JavaScript facade, see the
[JavaScript guide](JAVASCRIPT.md#troubleshooting).

## OpenTelemetry

The package speaks the W3C fields, so its services interoperate on the wire
with services that use OpenTelemetry's W3C propagator, in either direction:
a test runs that propagator, `@opentelemetry/core`, against the JavaScript
facade, which follows the same rules as Bend services.
It records no spans. To record them:

- in JavaScript, hand the service's operation to an OpenTelemetry tracer as
  the parent of its spans, or send an OpenTelemetry span with the package;
  the [JavaScript guide](JAVASCRIPT.md#opentelemetry) shows both;
- in Bend, log the trace and span IDs of the service's operation with your
  log lines, so that a log backend can correlate them, as
  [Log correlation](#log-correlation) shows.
