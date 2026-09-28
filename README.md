# bend-trace-context

W3C Trace Context propagation for [Bend](https://bend-lang.com/): the
`traceparent` and `tracestate` fields that let a distributed tracing system
follow one request through every service that it reaches. A service that
uses the package continues the trace of each request that it receives, and
gives each request that it sends a child of its own operation, with the
standard's rules proved as laws. Licensed under [MIT](LICENSE).

[![CI](https://github.com/LucasGois1/bend-trace-context/actions/workflows/ci.yml/badge.svg)](https://github.com/LucasGois1/bend-trace-context/actions/workflows/ci.yml)

It is for Bend services that take part in distributed tracing, natively or
compiled to JavaScript, and for the Node applications and browser pages that
call them or must follow the same rules. It propagates context, records
nothing and makes no sampling decision of its own: pair it with a tracer to
record spans, such as OpenTelemetry in JavaScript, or log the trace and span
IDs of a Bend service's operations to correlate its logs.

**Status: 0.1.0-dev, not released yet.** The package does everything that
0.1.0 will ship, and its release is being prepared in
[#15](https://github.com/LucasGois1/bend-trace-context/issues/15). Until
then, depend on a commit, as [Install](#install) shows. It needs exactly
Bend 2.0.32.

## What it does

For each message that a service receives, the package:

- reads its context, as
  [W3C Trace Context Level 2](https://www.w3.org/TR/2024/CRD-trace-context-2-20240328/)
  asks: a malformed, oversized or repeated `traceparent` is refused, repeated
  `tracestate` fields are combined, and later versions are read by their
  known prefix;
- gives the service an **operation** of its own, which tracers call a span:
  a **child** of the caller's operation, which keeps the caller's trace, or
  the root of a new trace when the message carries no context;
- gives each message that the service sends a new child of that operation,
  written into the message's fields, with `tracestate` kept within budgets.

It also generates trace and span IDs on the host's cryptographic source, or
on a source that you supply for tests; forwards a context unchanged for
intermediaries; restarts traces at trust boundaries; lets requests proceed
when no ID can be generated, or fails them if you choose; and reports every
outcome in names that can be logged, without logging anything itself. The
[guide](packages/trace-context/GUIDE.md) explains the ideas in a few
minutes.

## Where it runs

| Target | Support |
| --- | --- |
| Bend compiler | Exactly 2.0.32, which [Install](#install) sets up; other versions are not supported |
| Native Bend | macOS ARM64 and Linux x86_64, with Clang 14 or later |
| Bend programs compiled to JavaScript | Node 22 and 24 |
| JavaScript applications | Node 22.18.0 or a later Node 22, and Node 24, through the facade, with TypeScript declarations |
| Browser pages | Chromium, Firefox and WebKit, as Playwright 1.63 builds them, bundled with the official Bend bundler |
| Native HTTP | bend-kit's HTTP package, `bend-kit-http` 0.23.0.1 |

Each row is qualified in CI on every commit; the
[validation record](packages/trace-context/VALIDATION.md) lists the exact
versions.

## Install

The package has no release yet, so a project depends on an exact commit of
`master` whose [CI run](https://github.com/LucasGois1/bend-trace-context/actions/workflows/ci.yml?query=branch%3Amaster+is%3Asuccess)
passed. With the GitHub CLI, the latest such commit is:

```sh
gh run list --repo LucasGois1/bend-trace-context --workflow ci.yml --branch master --status success --limit 1 --json headSha --jq '.[0].headSha'
```

Record it where your project records its dependencies, so that every
checkout uses the same code: a moving branch is not a version. After the
release, use its tag instead. Put the repository in your project at that
commit, in place of `FULL_COMMIT_SHA` below, and install the Bend compiler
that it pins:

```sh
mkdir -p deps
git clone https://github.com/LucasGois1/bend-trace-context.git deps/bend-trace-context
git -C deps/bend-trace-context checkout --detach FULL_COMMIT_SHA
./deps/bend-trace-context/scripts/setup-bend.sh
```

`setup-bend.sh` downloads the official Bend 2.0.32 release for macOS ARM64
or Linux x86_64, verifies its SHA-256, and installs it under
`deps/bend-trace-context/.tools/`; `./deps/bend-trace-context/bend` runs it.
It installs no global shell configuration.

A JavaScript project installs the facade from the same checkout; it needs no
Bend at run time, and a page needs it only to be bundled:

```sh
npm install ./deps/bend-trace-context/packages/trace-context
```

## Quick start: Bend

A service that receives a request continues its trace and gives the request
it sends a child of its own operation. Create `main.bend`:

<!-- test:readme-bend:start -->
```bend
import Base
import ./deps/bend-trace-context/packages/trace-context/trace_context.bend as TC
import ./deps/bend-trace-context/packages/trace-context/generation.bend as Generate

# The fields of a request that this service receives, in their order.
def received() -> List<&2, TC.Header>:
  [TC.Header{"traceparent", "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"},
    TC.Header{"tracestate", "congo=t61rcWkgMzE"}]

# The trace ID of the service's operation, for a log line.
def trace_id(outgoing: Maybe<&2, TC.OutgoingContext>) -> String:
  match outgoing:
    case Some{context}:
      TC.TraceId.to_string(TC.LocalContext.trace_id(TC.OutgoingContext.context(context)))
    case None{}:
      "none"

# The names of the fields to send, in their order.
def names(fields: List<&2, TC.Header>) -> String:
  match fields:
    case Nil{}:
      ""
    case Con{TC.Header{name, value}, rest}:
      " " ++ name ++ names(rest)

def main() -> IO(Unit):
  # The request's context. None{} passes no base context, so a request
  # without a usable traceparent would start a new trace.
  +extraction = TC.Context.extract(TC.Limits.default(), received(), None{})
  do IO<Unit>:
    # The service's own operation for the request: a child of the caller's.
    +service : TC.Service <- Generate.Context.continue_or_start(extraction, TC.Continue{}, TC.InheritSampled{},
      TC.Lenient{})
    # A child of that operation for a request that the service sends.
    +sent : TC.Sent <- Generate.Context.send(TC.Limits.default(), service, TC.InheritSampled{}, TC.Lenient{},
      [TC.Header{"content-type", "application/json"}])
    Unit <- IO.print(TC.Extraction.show(extraction))
    Unit <- IO.print(TC.Service.show(service) ++ " " ++ trace_id(TC.Service.outgoing(service)))
    IO.print(TC.Sent.show(sent) ++ names(TC.Sent.carrier(sent)))
```
<!-- test:readme-bend:end -->

Run it with `./deps/bend-trace-context/bend main.bend`, build a native
binary with `-o main`, or a program for Node with `-o main.js`. The span IDs
are new on every run, so it prints only what does not change: the request's
context was accepted, the service continued its trace, and the request sent
carries a new `traceparent` and the received `tracestate`.

<!-- test:readme-bend-output:start -->
```text
TraceParentAccepted, StateAccepted
Continued 4bf92f3577b34da6a3ce929d0e0e4736
Fresh content-type traceparent tracestate
```
<!-- test:readme-bend-output:end -->

A real service takes the fields from its transport: the
[guide](packages/trace-context/GUIDE.md#a-native-http-service) has a
complete HTTP service on bend-kit, and recipes for log correlation, jobs,
sampling, your own `tracestate` entry, trust boundaries, relays, queue
workers and tests.

## Quick start: JavaScript

The same service in Node. Create `main.mjs`:

<!-- test:readme-javascript:start -->
```js
import * as TC from 'bend-trace-context';

// The fields of a received request, in their order.
const extraction = TC.extract([
  ['traceparent', '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01'],
  ['tracestate', 'congo=t61rcWkgMzE'],
]);
// The service's own operation for the request, and a child of it for a
// request that the service sends, with that request's own fields.
const service = TC.continueOrStart(extraction);
const sent = TC.send(service, [['content-type', 'application/json']]);
console.log(extraction.show);
// A service has no operation only when no ID could be generated.
console.log(service.show, service.outgoing?.context.traceId ?? 'untraced');
console.log(sent.show, sent.fields.map(([name]) => name).join(' '));
```
<!-- test:readme-javascript:end -->

Run it with `node main.mjs`:

<!-- test:readme-javascript-output:start -->
```text
TraceParentAccepted, StateAccepted
Continued 4bf92f3577b34da6a3ce929d0e0e4736
Fresh content-type traceparent tracestate
```
<!-- test:readme-javascript-output:end -->

`bend-trace-context/node` reads `node:http` requests. The
[JavaScript guide](packages/trace-context/JAVASCRIPT.md#recipes) has recipes
for `node:http`, Express, Fastify, `AsyncLocalStorage`, log correlation and
OpenTelemetry.

## Quick start: browser page

A page continues the context that its server rendered into it, and gives
each request that it sends a child of the page's own operation. In a project
that installed the facade, create `page.html`:

<!-- test:readme-page-html:start -->
```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>Orders</title>
  </head>
  <body>
    <script type="module" src="./page.mjs"></script>
  </body>
</html>
```
<!-- test:readme-page-html:end -->

and `page.mjs`:

<!-- test:readme-page:start -->
```js
import * as TC from 'bend-trace-context';
import { documentFields, tracedFetch } from 'bend-trace-context/fetch';

// The page's own operation: a child of the one that its server rendered
// into it, or the root of a new trace when it rendered none.
const service = TC.continueOrStart(TC.extract(documentFields(document)));
// A request to the page's own origin, with a child of the page's operation.
const { response, sent } = await tracedFetch(service, '/api/orders', {
  method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ order: 1 }),
});
console.log(service.show);
console.log(response.status, sent.show);
```
<!-- test:readme-page:end -->

Bundle it with the checkout's bundler, which writes the page and its script
to `dist`:

```sh
./deps/bend-trace-context/bend page.html -o dist
```

Serve `dist` with a server that renders its own context into the page: save
the one of [Serving a page](packages/trace-context/JAVASCRIPT.md#serving-a-page)
as `server.mjs`, run `node server.mjs`, and open `http://127.0.0.1:8080/`.
The console shows that the page continued the server's trace, and that its
request carried a new child:

<!-- test:readme-page-output:start -->
```text
Continued
200 Fresh
```
<!-- test:readme-page-output:end -->

Requests to other origins carry the context only when you allow them, as
[Cross-origin requests and CORS](packages/trace-context/JAVASCRIPT.md#cross-origin-requests-and-cors)
explains.

## Documentation

- [Guide](packages/trace-context/GUIDE.md): the ideas, the decisions a
  service makes, recipes, security considerations and troubleshooting.
- [Bend API reference](packages/trace-context/README.md): every operation
  and type, and what the laws prove.
- [Errors and diagnostics](packages/trace-context/ERRORS.md): every error
  and log name, in Bend and in JavaScript.
- [JavaScript guide](packages/trace-context/JAVASCRIPT.md): the facade for
  Node and browser pages.
- [Native HTTP guide](packages/trace-context/NATIVE-HTTP.md): the bend-kit
  transport and its qualification.
- [Glossary](CONTEXT.md), [changelog](CHANGELOG.md) with versioning and
  migration notes, [contributing](CONTRIBUTING.md) and
  [security policy](SECURITY.md).

## How it is verified

- **Proofs.** The laws of [LAWS.bend](packages/trace-context/LAWS.bend)
  quantify over every input, and `./bend packages/trace-context/PROOF.bend`
  prints `ALL PROOFS CHECK`. They cover the codec's round trip, the
  contexts, generation, `tracestate`, extraction, injection, forwarding and
  the service operations; the [reference](packages/trace-context/README.md#proofs)
  states each law and its limits.
- **Tests.** Independent protocol vectors, all 256 flag bytes, compile-time
  rejections, deterministic generation, the examples, and a consumer that
  installs the package from a fresh clone, natively, in Node and in
  browsers. That consumer also runs every program of this README and of the
  guides, and compares what it prints with what the documents show; the
  guide's HTTP service is checked to be the gateway example, which the
  propagation tests run, and the TypeScript example is type-checked.
- **Interoperability.** A native service on bend-kit and a Node service on
  the facade pass the [W3C Trace Context test harness](https://github.com/w3c/trace-context/tree/acab820be9db7b3433668baa5cdd43f57f4c4be0/test)
  at Level 2, 41 tests, and browser pages run in Chromium, Firefox and
  WebKit.

Neither the laws nor the tests establish full conformance to the W3C
publication. [CONTRIBUTING.md](CONTRIBUTING.md) shows how to run every gate.
