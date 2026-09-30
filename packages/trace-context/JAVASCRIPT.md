# JavaScript

The JavaScript facade gives Node applications and browser pages the
package's operations: extraction, continuing or starting a service's
operation and sending, tracestate edits, injection, forwarding and cleanup,
and generation on WebCrypto with explicit failure policies. Every Trace
Context rule runs in the Bend package itself, the same
[`trace_context.bend`](trace_context.bend) that native programs use,
compiled to an ES module, so a JavaScript service follows exactly the rules
of a Bend one and needs no Bend at run time. The facade converts JavaScript
values at the boundary, feeds WebCrypto words to the package's generation,
and wraps the package's values in [handles](#handles).

Use it for JavaScript code that must follow the same rules as your Bend
services, or that propagates context without a tracer. A Node application
that uses OpenTelemetry already has a W3C propagator; the
[OpenTelemetry recipe](#opentelemetry) shows how the facade works alongside
it. Like the Bend package, the facade records no spans and logs nothing.

The package has three entries, all ES modules with
[TypeScript declarations](#typescript):

- `bend-trace-context`: the facade;
- `bend-trace-context/node`: [`node:http` requests](#node-http-integration);
- `bend-trace-context/fetch`: [a browser page's requests](#browser-integration).

The [guide](GUIDE.md) explains the ideas behind these operations, and
[Errors and diagnostics](ERRORS.md) lists every error and log name.

- [Install and run](#install-and-run)
- [Recipes](#recipes): `node:http` and `fetch`, Express, Fastify,
  `AsyncLocalStorage`, log correlation and OpenTelemetry
- [Facade reference](#facade-reference), with
  [inspecting a traceparent](#inspecting-a-traceparent)
- [Node HTTP integration](#node-http-integration)
- [Browser integration](#browser-integration)
- [TypeScript](#typescript)
- [Troubleshooting](#troubleshooting)
- [How the facade works](#how-the-facade-works)

## Install and run

An application installs the facade from a checkout of the release tag, as
the [root README](../../README.md#install) shows:

```sh
mkdir -p deps
git clone --branch v0.1.2 https://github.com/LucasGois1/bend-trace-context.git deps/bend-trace-context
npm install ./deps/bend-trace-context/packages/trace-context
```

`npm install` links the package directory into `node_modules` as
`bend-trace-context`; the package has no dependencies. An application needs
neither the Bend binary, nor Bun, nor a module loader: it runs with Node
alone, as `node main.mjs`. The
[root README](../../README.md#quick-start-javascript) has the smallest
program, and the [recipes](#recipes) are complete services to start from.

The facade runs on:

- Node 22.18.0 or a later Node 22 release, or Node 24, the range that the
  package declares. CI qualifies 22.18.0 and 24.0.0, the lowest releases of
  that range, and the current release of each line, and records their exact
  versions.
- Browser pages bundled with the official Bend bundler, in the
  [tested engines](#tested-engines).

## Recipes

Each recipe is a complete program for a project that installed the package
as [Install and run](#install-and-run) shows, plus its framework. The
servers read their port from `PORT` and the downstream service from
`DOWNSTREAM`. For each request they call downstream with a new child of the
service's operation: a traced request continues its trace, and an untraced
one starts a trace. They answer 502 when downstream cannot be reached. The
tests run each server against an independent observer, with a traced
request, an untraced one and an unreachable downstream.

### node:http and fetch

<!-- test:javascript-http:start -->
```js
import http from 'node:http';
import * as TC from 'bend-trace-context';
import { continueOrStartRequest } from 'bend-trace-context/node';

const port = Number(process.env.PORT ?? 8080);
const downstream = process.env.DOWNSTREAM ?? 'http://127.0.0.1:8081/items';

http.createServer(async (request, response) => {
  // The service's own operation for this request: a child of the caller's
  // operation, or the root of a new trace when the request carries none.
  const service = continueOrStartRequest(request);
  // A child of that operation for the call downstream, in the call's fields.
  const sent = TC.send(service, [['content-type', 'application/json']]);
  console.log(`${request.method} ${request.url}: ${service.show}, downstream ${sent.show}`);
  try {
    const answer = await fetch(downstream, { method: 'POST', headers: sent.fields, body: '{"order":1}' });
    const body = await answer.text();
    response.writeHead(answer.status, { 'content-type': 'application/json' }).end(body);
  } catch {
    // Downstream could not be reached.
    response.writeHead(502).end();
  }
}).listen(port);
```
<!-- test:javascript-http:end -->

`sent.fields` is the call's fields with the context fields added; `fetch`
takes them as they are. With `http.request`, pass
`requestHeaders(sent.fields)` from `bend-trace-context/node` instead, as the
[gateway example](examples/gateway.mjs) does.

### Express

A middleware gives every request the service's operation, and the handlers
send with it:

<!-- test:javascript-express:start -->
```js
import express from 'express';
import * as TC from 'bend-trace-context';
import { continueOrStartRequest } from 'bend-trace-context/node';

const port = Number(process.env.PORT ?? 8080);
const downstream = process.env.DOWNSTREAM ?? 'http://127.0.0.1:8081/items';
const app = express();

// Every request gets the service's operation for it.
app.use((request, response, next) => {
  response.locals.service = continueOrStartRequest(request);
  next();
});

app.post('/orders', async (request, response) => {
  const sent = TC.send(response.locals.service, [['content-type', 'application/json']]);
  try {
    const answer = await fetch(downstream, { method: 'POST', headers: sent.fields, body: '{"order":1}' });
    const body = await answer.text();
    response.status(answer.status).type('application/json').send(body);
  } catch {
    response.status(502).end();
  }
});

app.listen(port);
```
<!-- test:javascript-express:end -->

An Express request is a `node:http` `IncomingMessage`, so
`continueOrStartRequest` reads its raw header lines directly.

### Fastify

A hook gives every request the service's operation, from the raw request:

<!-- test:javascript-fastify:start -->
```js
import Fastify from 'fastify';
import * as TC from 'bend-trace-context';
import { continueOrStartRequest } from 'bend-trace-context/node';

const port = Number(process.env.PORT ?? 8080);
const downstream = process.env.DOWNSTREAM ?? 'http://127.0.0.1:8081/items';
const app = Fastify();
app.decorateRequest('service', null);

// Every request gets the service's operation for it, from its raw headers.
app.addHook('onRequest', async (request) => {
  request.service = continueOrStartRequest(request.raw);
});

app.post('/orders', async (request, reply) => {
  const sent = TC.send(request.service, [['content-type', 'application/json']]);
  try {
    const answer = await fetch(downstream, { method: 'POST', headers: sent.fields, body: '{"order":1}' });
    const body = await answer.text();
    return reply.code(answer.status).type('application/json').send(body);
  } catch {
    return reply.code(502).send();
  }
});

await app.listen({ port, host: '127.0.0.1' });
```
<!-- test:javascript-fastify:end -->

### A service for the whole request

`AsyncLocalStorage` keeps the service's operation for the code that a
request runs, so that a function far from the handler sends with it without
receiving it as an argument:

<!-- test:javascript-context:start -->
```js
import http from 'node:http';
import { AsyncLocalStorage } from 'node:async_hooks';
import * as TC from 'bend-trace-context';
import { continueOrStartRequest } from 'bend-trace-context/node';

const port = Number(process.env.PORT ?? 8080);
const downstream = process.env.DOWNSTREAM ?? 'http://127.0.0.1:8081/items';
// The service's operation for the request that the current code serves.
const requests = new AsyncLocalStorage();

// fetch, with a new child of the current request's operation among the
// call's headers. Outside a request, the call goes without context fields.
function tracedCall(url, init = {}) {
  const service = requests.getStore();
  const fields = [...new Headers(init.headers)];
  const headers = service === undefined ? TC.clear(fields) : TC.send(service, fields).fields;
  return fetch(url, { ...init, headers });
}

// Code far from the request handler calls downstream through tracedCall.
async function placeOrder() {
  const answer = await tracedCall(downstream, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: '{"order":1}',
  });
  return { status: answer.status, body: await answer.text() };
}

http.createServer((request, response) => {
  requests.run(continueOrStartRequest(request), async () => {
    try {
      const { status, body } = await placeOrder();
      response.writeHead(status, { 'content-type': 'application/json' }).end(body);
    } catch {
      response.writeHead(502).end();
    }
  });
}).listen(port);
```
<!-- test:javascript-context:end -->

### Log correlation

Log the trace and span IDs of the service's operation with your log lines,
so that a log backend can relate them to the traces of other services. A
service without an operation has no IDs; log its `show`, which says why:

<!-- test:javascript-log:start -->
```js
import * as TC from 'bend-trace-context';

// The trace and span IDs of the service's operation, as fields of a log
// line, or why the service has none.
function traceFields(service) {
  const operation = service.outgoing?.context;
  if (operation === undefined) return `tracing="${service.show}"`;
  return `trace_id=${operation.traceId} span_id=${operation.spanId}`;
}

const traced = TC.continueOrStart(TC.extract([
  ['traceparent', '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01'],
]));
console.log(`order placed ${traceFields(traced)}`);
// Without a source of words, no ID can be generated: the service is untraced.
const untraced = TC.continueOrStart(TC.extract([]), { crypto: null });
console.log(`order placed ${traceFields(untraced)}`);
```
<!-- test:javascript-log:end -->

The span ID is new on every run:

<!-- test:javascript-log-output:start -->
```text
order placed trace_id=4bf92f3577b34da6a3ce929d0e0e4736 span_id=b9c7c989f97918e1
order placed tracing="Untraced SourceFailure 1 unavailable"
```
<!-- test:javascript-log-output:end -->

### OpenTelemetry

The facade records no spans. With OpenTelemetry, the service's operation
becomes the parent of the spans that a tracer records, and a span that
OpenTelemetry created can be sent with the package:

<!-- test:javascript-opentelemetry:start -->
```js
import { ROOT_CONTEXT, trace, TraceFlags } from '@opentelemetry/api';
import * as TC from 'bend-trace-context';

// The service's operation as an OpenTelemetry context, the parent of the
// spans that a tracer records for the request.
function openTelemetryContext(service) {
  const operation = service.outgoing?.context;
  if (operation === undefined) return ROOT_CONTEXT;
  return trace.setSpanContext(ROOT_CONTEXT, {
    traceId: operation.traceId,
    spanId: operation.spanId,
    traceFlags: operation.sampled ? TraceFlags.SAMPLED : TraceFlags.NONE,
  });
}

// An OpenTelemetry span as an operation of this service, to send with the
// package: the span's identifiers and sampled flag.
function fromOpenTelemetry(span) {
  const { traceId, spanId, traceFlags } = span.spanContext();
  return TC.fromIds(traceId, spanId, { sampled: (traceFlags & TraceFlags.SAMPLED) !== 0 });
}

const service = TC.continueOrStart(TC.extract([
  ['traceparent', '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01'],
  ['tracestate', 'congo=t61rcWkgMzE'],
]));
const span = trace.getTracer('orders').startSpan('place order', {}, openTelemetryContext(service));
// The span's context, with the state that the service received, for a
// request that the span makes.
const operation = TC.outgoing(fromOpenTelemetry(span), { state: service });
console.log(span.spanContext().traceId);
console.log(TC.inject(operation, []).fields.map(([name]) => name).join(' '));
span.end();
```
<!-- test:javascript-opentelemetry:end -->

<!-- test:javascript-opentelemetry-output:start -->
```text
4bf92f3577b34da6a3ce929d0e0e4736
traceparent tracestate
```
<!-- test:javascript-opentelemetry-output:end -->

With only `@opentelemetry/api` installed, as here, the tracer records
nothing and its span keeps the parent's identifiers. With an OpenTelemetry
SDK registered, the span is a child in the same trace, which the SDK
records when its sampler decides so: its default sampler follows the
parent's sampled flag. `fromOpenTelemetry` then sends that child. The
`state` option keeps the tracestate that the service received; without it,
`TC.outgoing` sends none.

## Facade reference

Values cross the boundary as ordinary JavaScript data:

- the fields of a message are an array of `[name, value]` string pairs in the
  message's order, the package's carrier;
- wire text, such as traceparent and tracestate values, is a string;
- diagnostics are the package's names, such as
  `TraceParentAccepted, StateAccepted` or
  `Untraced SourceFailure 2 source-failure`.

The diagnostics of extraction, of services and of sent messages contain no
received value, so they can be logged. Every function takes its options as
an optional last argument.

### Receiving and sending

```js
extract(fields, { limits, base }) -> Extraction
continueOrStart(extraction, { reception, sampling, policy, crypto }) -> Service
send(service, fields, { limits, sampling, policy, crypto }) -> Sent
```

- `extract` reads the context of a received message, as
  [`Context.extract`](README.md#extracting-context) does. `base`, an
  `IncomingContext` or `OutgoingContext`, is kept when the message has no
  usable traceparent.
- `continueOrStart` gives the service its own operation for the message, as
  [`Context.continue_or_start`](README.md#continuing-or-starting-a-trace)
  does:
  - a child of the context that extraction kept, with its state;
  - a root when extraction kept none;
  - with `reception: 'restart'`, a new trace in place of the kept context, as
    at a trust boundary.
- `send` gives one message that the service sends an operation of its own: a
  new child of the service's operation, injected into the message's own
  fields. The old context fields go and the new ones come last. When no child
  can be generated, the message forwards the received pair unchanged if it
  can, and carries no context fields otherwise. Call it once for each
  message: each request of a fan-out gets a child of its own.

| Option | Values | Default |
| --- | --- | --- |
| `reception` | `'continue'`, or `'restart'` at a trust boundary | `'continue'` |
| `sampling` | `'inherit'`: a child inherits its parent's sampled flag, and a root or a restart takes the root default, not sampled; `'sampled'` or `'unsampled'` sets it | `'inherit'` |
| `policy` | `'lenient'`, or `'strict'` (see [Failure handling](#failure-handling)) | `'lenient'` |
| `crypto` | An object with WebCrypto's `getRandomValues`, such as `node:crypto`'s `webcrypto`; `null` models an unavailable source. Any other value is a `TypeError` | `globalThis.crypto`, when called |
| `limits` | A `Limits` handle from `limits()` | the package's defaults |

### Handles

A handle is a frozen object that only the facade creates, with the package
value it stands for kept in a module-private `WeakMap`. Its kind is named
after the package's type, and its properties are plain data. A function
that takes a handle refuses any other object with a `TypeError`, including
a copy of a handle, an object that inherits from one, and a tagged object
shaped like the package's own values. JavaScript code therefore cannot
build a context, a service or a limit that the package's constructors did
not check.

| Handle | Properties |
| --- | --- |
| `Extraction` | `show`, the log line of both outcomes; `parent`, the traceparent outcome; `state`, the tracestate outcome; `incoming`, the message's `IncomingContext` or `null`; `context`, the `IncomingContext` or `OutgoingContext` that extraction kept, the message's or the base, or `null` |
| `IncomingContext` | `traceId`, `spanId`, the sender's span ID, `sampled` and `random`; `tracestate`, the normalized state received with it; `received`, the accepted pair `{ traceparent, tracestate }`, the tracestate as an array of the field values as they came, or `null` when the tracestate was discarded |
| `LocalContext` | an operation of this participant: `traceparent`, its participating value; `traceId`, `spanId`, `sampled` and `random` |
| `OutgoingContext` | `context`, a `LocalContext`; `tracestate`, the normalized state that it sends, before truncation |
| `Service` | `show`; `origin`, `'Continued'`, `'Started'`, `'Restarted'` or `null`; `error`, why it has no operation, or `null`; `outgoing`, its `OutgoingContext` or `null` |
| `Sent` | `fields`, the fields to send the message with, in every case; `show`; `operation`, its new `LocalContext` or `null`; `error`, why none was generated, or `null`; `dropped`, the tracestate keys that truncation to the output budget removed |
| `Limits` | `traceparentInput`, `tracestateInput` and `tracestateOutput`, in UTF-8 octets |

`Service.show` and `Sent.show` name what happened, for a log line:
`Continued`, `Untraced SourceFailure 2 source-failure`, `Fresh, truncated` or
`NoContext after ExhaustedSpanId, NothingKept`.
[Errors and diagnostics](ERRORS.md#continuing-or-starting-and-sending)
defines each name.

### Generation

```js
root({ crypto }) -> LocalContext
child(parent, { sampling, crypto }) -> LocalContext
restart(previous, { crypto }) -> LocalContext
```

`parent` is an `IncomingContext` or a `LocalContext`, and `previous` an
`IncomingContext`. The package's rules apply, as in
[Generated contexts](README.md#generated-contexts):

- four words per trace ID candidate and two per span ID candidate;
- at most eight candidates per identifier;
- no all-zero identifier, no reuse of the parent's span ID or of a received
  trace ID;
- an immediate stop at the first source error, without retry or fallback.

A root or a restart is not sampled and asserts random-trace-id, so it is sent
with flags `02`: the package's root and restart take the sampled indication
explicitly, and the facade passes the unsampled one, with no option for it.
A child keeps its parent's trace ID and randomness assertion. When
generation fails, these functions throw a `GenerationError`.

The facade reads one word at a time from `crypto`, and only while the
package says that the generation needs one, so it never reads more than the
package's rules use. A source is trusted to be random: nothing checks the
quality of its words.

### Supplied identifiers

```js
rootFromIds(traceId, spanId, { random }) -> LocalContext
fromIds(traceId, spanId, { sampled, random }) -> LocalContext
childFromId(parent, spanId, { sampling }) -> LocalContext
restartFromIds(previous, traceId, spanId, { random }) -> LocalContext
```

An application that already has identifiers, such as those of another
tracer, passes them as text, as the package's
[supplied-ID operations](README.md#supplied-ids-and-contexts) take them:

- `rootFromIds` starts a trace: not sampled, as `root` is, and asserting
  random-trace-id only with `random: true`.
- `fromIds` represents an operation that the application owns, with its
  sampled indication, `false` by default. Its identifiers must belong to that
  operation: validating their format does not establish where they came
  from.
- `childFromId` continues `parent`, an `IncomingContext` or a `LocalContext`,
  with its own span ID; the parent's span ID is refused.
- `restartFromIds` starts a new trace in place of `previous`, an
  `IncomingContext`; its trace ID is refused, even when only the randomness
  assertion differs.

`random: true` records the application's assertion that the trace ID's
digits were generated randomly; the application is responsible for it, and
validation cannot establish it. An identifier that the codec refuses throws a
`RangeError` with the codec's error, such as `ZeroTraceId` or
`InvalidHex at 1`, and a reused one `ReusedSpanId` or `ReusedTraceId`.

### Failure handling

- `GenerationError` has `name` `'GenerationError'` and `reason`, the
  package's [`GenerationError`](ERRORS.md#generation):
  `SourceFailure 1 unavailable` or `SourceFailure 2 source-failure` from
  WebCrypto, `ExhaustedTraceId` or `ExhaustedSpanId`.
- Under the lenient policy, `continueOrStart` and `send` never throw for a
  generation failure. The business operation proceeds: the service is
  `Untraced`, and each message it sends forwards the received pair unchanged
  or carries no context fields. `show` and `error` say why.
- Under the strict policy they throw a `GenerationError` whenever no new
  operation was generated, so that the application can refuse the request,
  for example with a 503.
- A `TypeError` reports an argument of the wrong type: fields that are not
  string pairs, a boxed string, an object that is not a handle of the
  expected kind, a `crypto` option without `getRandomValues`, or options that
  are not an object.
- A `RangeError` reports a value that the package refuses. Its `message` is
  the package's error name:
  - `InvalidKey` or `InvalidValue` for a tracestate entry;
  - `TraceParentInputTooSmall`, `TraceStateOutputTooSmall` or
    `TraceStateInputTooSmall` for limits;
  - the codec's error, `ReusedSpanId` or `ReusedTraceId` for
    [supplied identifiers](#supplied-identifiers);
  - a description for an unknown option value or a budget that is not a
    non-negative safe integer.

The facade reads each argument once and converts it before any package code
runs, so an array with getters or a proxy cannot pass one value to the check
and another to the package.

### Tracestate

```js
getState(target, key) -> string | null
setState(target, key, value) -> target's kind
removeState(target, key) -> target's kind
```

- `getState` reads the entry of `key` in the state of an `IncomingContext`
  or `OutgoingContext`, or of a `Service`'s operation.
- `setState` adds or updates the entry of `key` in the state that an
  `OutgoingContext` or a `Service` sends. The entry goes first, as a
  participant puts its own entry, and the others keep their order.
- `removeState` deletes the entry of `key` from that state.

The edits return new handles; handles never change. A service without an
operation sends no state, so both edits return it unchanged. The state
received with an `IncomingContext` is not edited: a service that changes the
state it passes on continues the trace with an operation of its own. Keys and
values follow the package's
[grammar](README.md#grammar-and-reading-rules), and nothing is trimmed.

### Injection, forwarding and cleanup

```js
outgoing(context, { state }) -> OutgoingContext
inject(outgoing, fields, { limits }) -> { fields, dropped }
forward(incoming, fields, { limits }) -> { ok: true, fields } | { ok: false, error }
clear(fields) -> fields
```

- `outgoing` pairs a `LocalContext` with the state of `state`, an
  `IncomingContext`, an `OutgoingContext` or a `Service`, or with none.
- `inject` writes the outgoing context into the fields of a message to send,
  as [`Context.inject`](README.md#injecting-and-forwarding-context) does.
  `dropped` lists the keys that truncation removed.
- `forward` writes the pair an `IncomingContext` was received with,
  unchanged, or refuses with a [`ForwardError`](ERRORS.md#forwarding) name:
  `NothingToForward` when the tracestate was discarded, and
  `ForwardTooLarge` over the output budget. Under a traceparent input
  budget smaller than the one it was extracted with, the traceparent may
  also be refused, as `InvalidForwardParent TraceParentTooLarge`.
- `clear` removes the context fields alone, for a message sent without
  context.

`send` does a child and its injection in one step. These functions serve an
application that manages its operations itself, such as an intermediary that
relays requests unchanged.

### Limits

```js
limits({ traceparentInput, tracestateInput, tracestateOutput }) -> Limits
```

`limits()` gives the package's defaults: 32768, 32768 and 512 octets. Each
option replaces one budget, and the package's
[rules](README.md#limits) decide whether the combination is valid.

### Inspecting a traceparent

`inspectTraceparent(value)` reads a traceparent value with the package's
strict version 00 codec, for a value that the application holds. Received
messages go through `extract`, which also reads later versions by their
known prefix. It accepts only a primitive string, and returns
`{ ok: true, traceparent, sampled }`, with every flag bit preserved, or
`{ ok: false, error }`, with the codec's
[error name](ERRORS.md#traceparent-and-identifiers) or `InvalidInputType`
for any other value. Numbers, arrays, boxed strings and tagged objects are
refused without coercion.

<!-- test:javascript-inspect:start -->
```js
import { inspectTraceparent } from 'bend-trace-context';

for (const value of ['00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01',
  '00-00000000000000000000000000000000-b7ad6b7169203331-01', 42]) {
  console.log(JSON.stringify(inspectTraceparent(value)));
}
```
<!-- test:javascript-inspect:end -->

<!-- test:javascript-inspect-output:start -->
```text
{"ok":true,"traceparent":"00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01","sampled":true}
{"ok":false,"error":"ZeroTraceId"}
{"ok":false,"error":"InvalidInputType"}
```
<!-- test:javascript-inspect-output:end -->

The codec names the version it refuses, as in `UnsupportedVersion 01`: that
is the only name of the package that holds part of a value it read. The
[inspector page](../../examples/javascript/index.html) does the same in a
browser.

## Node HTTP integration

```js
requestFields(request) -> fields
extractRequest(request, { limits, base }) -> Extraction
continueOrStartRequest(request, { limits, base, reception, sampling, policy, crypto }) -> Service
requestHeaders(fields) -> headers
```

- `requestFields` reads the fields of a received `node:http` request, an
  `IncomingMessage`, from its `rawHeaders`: every header line in arrival
  order, with its name as it came. Extraction therefore refuses a repeated
  traceparent and reads repeated tracestate lines in order.
  `IncomingMessage.headers` joins repeated values, so it is not used for
  incoming requests.
- `extractRequest` is `extract(requestFields(request), options)`.
- `continueOrStartRequest` is
  `continueOrStart(extractRequest(request, options), options)`. A service
  that logs why it continued or started a trace extracts first and passes
  the extraction on, as the gateway example does.
- `requestHeaders` gives the headers of a request to send, for the `headers`
  option of `http.request` or `ClientRequest`. It holds each name once, with
  the spelling of its first field, and the values of that name in order, as
  an array when the name repeats. `node:http` writes one header line per
  value, and a name's lines follow one another at the place of its first
  field. The lines of each name keep their order; RFC 9110 gives the order
  of different names no meaning, and no Trace Context rule depends on it.
  The object has no prototype, so a field named `__proto__` is kept.

An application that needs every line in the fields' own order passes them
as an array in the format of `rawHeaders`:
`http.request(url, { method: 'POST', headers: sent.fields.flat() })`. Node
then writes the lines as given and adds only `Connection`, so the fields
must include `Host` and the body's `Content-Length` or `Transfer-Encoding`.

Outgoing requests can also use `fetch`:
`fetch(url, { method: 'POST', headers: sent.fields, body })`. `Headers`
lowercases names and joins the repeated values of a name with `, `. The
package writes one traceparent and one tracestate field, so the context
fields arrive whole. Other repeated fields arrive joined, which RFC 9110
permits only for fields defined as lists.

What Node does before and after the package:

- Its parser trims the whitespace around header values, and refuses a
  request head over `maxHeaderSize`, 16 KiB by default, with 431 before any
  Trace Context code runs, whatever the package's input budgets allow.
- It decodes header bytes as Latin-1. A byte above `0x7F`, which only the
  unknown fields of a later traceparent version may hold, therefore counts
  as two UTF-8 octets toward the input budgets. Node writes such a character
  back as the same byte, so forwarding sends the value as it came.
- `ClientRequest` writes names as given and adds `Host`, `Connection` and
  the body's framing itself.

### Gateway walkthrough

The [gateway](examples/gateway.mjs) listens on `127.0.0.1:18777` and calls
`http://127.0.0.1:18776/downstream`. From the repository root, start an
observer that prints what reaches downstream:

```sh
OBSERVER_PORT=18776 node tests/native/fixtures/observer.mjs
```

Then, in two more terminals, start the gateway and send it a traced request
and an untraced one:

```sh
node packages/trace-context/examples/gateway.mjs
```

```sh
curl -X POST http://127.0.0.1:18777/orders -H 'traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01' -H 'tracestate: congo=t61rcWkgMzE' -d '{"order":1}'
curl -X POST http://127.0.0.1:18777/orders -d '{"order":2}'
```

The gateway logs its diagnostics, and the observer receives children of the
client's operation and of a new root. Each run prints new span IDs:

```text
POST /orders: TraceParentAccepted, StateAccepted; Continued, downstream Fresh
POST /orders: TraceParentAbsent, StateAbsent; Started, downstream Fresh
```

```text
POST /downstream {"order":1}
  traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-<new span ID>-01
  tracestate: congo=t61rcWkgMzE
POST /downstream {"order":2}
  traceparent: 00-<new trace ID>-<new span ID>-02
```

## Browser integration

A browser page uses the same facade, bundled into the page by the official
Bend bundler, and `bend-trace-context/fetch` for its requests. The
[root README](../../README.md#quick-start-browser-page) has a complete page,
and [Serving a page](#serving-a-page) a server for it.

### Build a page

In the pinned checkout that the [root README](../../README.md#install)
describes, install the facade into the project, then bundle each page with
the checkout's own `bend`:

```sh
./deps/bend-trace-context/scripts/setup-bend.sh
npm install ./deps/bend-trace-context/packages/trace-context
./deps/bend-trace-context/bend page.html -o dist
```

The bundler follows the page's `<script type="module">`, resolves
`bend-trace-context` through `node_modules` and writes the page and its
script to `dist`. The browser needs no Bend binary and no Bun. Bundling the
same checkout again gives byte-identical files. A copy of the sources at
another path gives the same scripts under other names, because the bundler
names its chunks by a hash that depends on where the sources are; the
qualification checks both. The facade itself is plain JavaScript: an ES
module of the package, which the pinned compiler builds, and the package's
WebCrypto source. Other bundlers, such as Vite, webpack or esbuild, are not
qualified.

### Serving a page

The page continues the operation of the server that rendered it: the
server's own operation for the page request, as it would inject it into a
request. Render each context field as a `<meta>` element, and escape the
value as an HTML attribute: a tracestate value may hold `"`, `&` and `<`,
and the HTML parser decodes character references before `documentFields`
reads them. Everything in the page is visible to its scripts, so render
only what the page's own requests would carry.

This server, saved next to `dist` as `server.mjs`, serves the page of the
[root README](../../README.md#quick-start-browser-page) that way, with its
script and the API that the page calls:

<!-- test:javascript-server:start -->
```js
import http from 'node:http';
import { readFile } from 'node:fs/promises';
import * as TC from 'bend-trace-context';
import { continueOrStartRequest } from 'bend-trace-context/node';

const port = Number(process.env.PORT ?? 8080);
// The page and the scripts that `bend page.html -o dist` wrote.
const dist = new URL('./dist/', import.meta.url);

// A value as an HTML attribute: a tracestate value may hold ", & and <.
const attribute = (text) => text.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;');

// The page, with the context of the server's own operation for the page
// request as <meta> elements. A server without an operation renders no
// context, and the page starts a trace of its own.
async function page(request) {
  const service = continueOrStartRequest(request);
  const fields = service.outgoing === null ? [] : TC.inject(service.outgoing, []).fields;
  const metas = fields.map(([name, value]) => `<meta name="${name}" content="${attribute(value)}">`).join('');
  const html = await readFile(new URL('page.html', dist), 'utf8');
  return html.replace('<meta charset="utf-8">', `<meta charset="utf-8">${metas}`);
}

http.createServer(async (request, response) => {
  const { pathname } = new URL(request.url, 'http://localhost');
  try {
    if (request.method === 'GET' && pathname === '/') {
      const html = await page(request);
      response.writeHead(200, { 'content-type': 'text/html' }).end(html);
    } else if (request.method === 'GET' && /^\/[\w-]+\.js$/.test(pathname)) {
      const script = await readFile(new URL(`.${pathname}`, dist));
      response.writeHead(200, { 'content-type': 'text/javascript' }).end(script);
    } else if (request.method === 'POST' && pathname === '/api/orders') {
      // The API's operation continues the page's trace.
      console.log(`POST /api/orders: ${continueOrStartRequest(request).show}`);
      request.resume();
      response.writeHead(200, { 'content-type': 'application/json' }).end('{"accepted":true}');
    } else {
      response.writeHead(404).end();
    }
  } catch {
    response.writeHead(404).end();
  }
}).listen(port);
```
<!-- test:javascript-server:end -->

Run it with `node server.mjs` and open `http://127.0.0.1:8080/`: the page
continues the server's trace, and its request to `/api/orders` carries a
child of the page's operation. The tests check both in the three engines.

### Fetch reference

```js
documentFields(document) -> fields
tracedFetch(service, input, init, { propagateTo, fetch, limits, sampling, policy, crypto }) -> Promise<{ response, sent }>
```

- `documentFields` reads the context that the page's server rendered as
  `<meta name="traceparent" content="...">` and
  `<meta name="tracestate" content="...">` elements, in document order, for
  `extract`. Names are compared without regard to ASCII case. The convention
  is OpenTelemetry's, not the W3C's. Two traceparent elements are refused,
  as two fields are.
- `tracedFetch` sends one request with `fetch`, taking `input` and `init` as
  `fetch` takes them: a URL, a string or a `Request`, and `init.headers` as a
  `Headers` object, pairs or a record, whose names and values it converts to
  strings as `fetch` does. `init` is read once, and a `Request` keeps its
  referrer and referrer policy.
  - When the destination may receive the context fields, it calls `send` for
    a new child of the service's operation, and the request carries
    `sent.fields`: its own fields, with any stale context fields replaced.
  - Otherwise, the request goes without context fields, and `sent` is
    `null`.
- The destinations that may receive the context fields are the page's own
  origin, as its document has it (`globalThis.origin`), and those that
  `propagateTo` allows. An entry is an origin, such as
  `'https://api.example.com'`, or a `RegExp` searched in the whole URL, with
  the same result on every call whatever its flags. A page with an opaque
  origin, such as a sandboxed frame, has no own origin. A `no-cors` request
  never carries the fields: the browser would drop them.
- `options.fetch` is the function that sends, `globalThis.fetch` by default,
  such as an application's own wrapper. The other options are `send`'s. All
  options, the headers and the handle are checked before anything is sent or
  generated. Under the strict policy, a request that may carry the fields is
  not sent when no new child can be generated, and the promise rejects with
  a `GenerationError`. A rejection of `fetch` itself, such as a refused
  preflight or a network failure, passes through unchanged.
- The result is frozen.
- Outside a page, as in Node, there is no own origin: only the origins that
  `propagateTo` allows receive the fields, and a relative URL is refused.
  Browsers and Node are qualified; other hosts are not.

### Cross-origin requests and CORS

`traceparent` and `tracestate` are not CORS-safelisted request headers, so a
cross-origin request that carries them sends a preflight first. The
destination's server must answer it with, for example:

```http
Access-Control-Allow-Origin: https://app.example.com
Access-Control-Allow-Methods: POST
Access-Control-Allow-Headers: content-type, traceparent, tracestate
```

It may add `Access-Control-Max-Age` so that the browser caches the answer.
When the answer does not allow the fields, the browser refuses the request
before sending it, and `tracedFetch` rejects with `fetch`'s `TypeError`: the
business request fails. That is why only the page's own origin receives the
fields by default. Allow an origin in `propagateTo` once its server accepts
them. A request to an origin outside the list goes without context fields,
and so needs no preflight for them.

`fetch` follows redirects by default, and the browser sends the redirected
request with the same header fields, the same child included, to the new
URL. The allowlist is not checked again there, so a redirect to another
origin needs a preflight that allows the fields, or the business request
fails. For a request whose redirects may leave the allowed destinations,
pass `redirect: 'error'` or `'manual'` in `init`, or allow the origins it
redirects to. The tests show all three outcomes.

### What browsers do to the fields

- `Headers` lowercases names, gives them sorted, and joins the repeated
  values of a name with `, `. A page that gives `tracedFetch` a `Headers`
  object therefore hands over one field per name. The package still writes
  one traceparent and one tracestate field. A joined pair of traceparent
  values is refused as repeated, and joined tracestate values read as the
  separate fields would.
- `Headers` removes the whitespace around values, and refuses a value with a
  line break with a `TypeError`.
- A `no-cors` request drops every header that is not CORS-safelisted,
  `traceparent` and `tracestate` included. A test shows it with a plain
  `fetch`.
- Engines choose the order of the header lines they send. The tests record
  the order that each engine sent in their reports (`header-order.json`). In
  the runs for this release, Chromium 153 and WebKit 26.6 sent lines of
  different names in an order of their own, and Firefox 155 in the given
  order. The lines of one name keep their order, and no Trace Context rule
  depends on the order of different names.
- A page reads a cross-origin response's headers only when its server
  exposes them with `Access-Control-Expose-Headers`; nothing here reads
  response headers.
- `navigator.sendBeacon`, form submissions and navigations cannot carry
  header fields that the page sets.

### Tested engines

The qualification runs Chromium (Chrome for Testing 153.0.8010.12), Firefox
155.0 and WebKit 26.6, as Playwright 1.63.0 builds and installs them: on
Linux in CI and on macOS locally. Each test records the exact version it
ran. Playwright's builds are close to the browsers' releases but are not
them. No claim is made for Chrome, Edge, Safari or Firefox as released, for
mobile browsers, or for other versions.

### Page walkthrough

The [Fetch page](../../examples/javascript/fetch.html) continues the context
that its server rendered, or starts a trace, and calls a same-origin API and
a partner API on another origin. From the repository root, after
`./scripts/setup-bend.sh` and `npm ci --ignore-scripts`, which links the
package into `node_modules`, bundle it and start its server:

```sh
npm run build:browser
node tests/browser/server.mjs
```

In another terminal, start the partner, the independent observer of the
tests:

```sh
node tests/browser/observer.mjs
```

Open
`http://127.0.0.1:4173/fetch.html?traceparent=00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01&tracestate=congo%3Dt61rcWkgMzE`.
The server renders both fields as `<meta>` elements, and the page shows
`TraceParentAccepted, StateAccepted; Continued`. "Call the same-origin API"
shows `200, Fresh`. "Call the partner API" shows `200, Fresh` too, after the
partner's preflight accepted the fields. The partner lists what it received
at `http://127.0.0.1:4174/observations/example`. "Show what Fetch hands
over" shows the fields that a `Headers` object gives the page, with a
repeated name joined, and what extraction makes of them.

## TypeScript

The package declares its three entries for TypeScript, in
[`javascript/index.d.mts`](javascript/index.d.mts),
[`node.d.mts`](javascript/node.d.mts) and [`fetch.d.mts`](javascript/fetch.d.mts),
which `package.json` names for each entry. The declarations of
`bend-trace-context` and `bend-trace-context/node` need no DOM or Node
types:

<!-- test:javascript-typescript:start -->
```ts
import * as TC from 'bend-trace-context';

function operationOf(service: TC.Service): TC.LocalContext | null {
  return service.outgoing === null ? null : service.outgoing.context;
}

const service: TC.Service = TC.continueOrStart(TC.extract([['traceparent',
  '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01']]), { sampling: 'inherit' });
const operation: TC.LocalContext | null = operationOf(service);
export const traceId: string | null = operation === null ? null : operation.traceId;
```
<!-- test:javascript-typescript:end -->

Those of `bend-trace-context/fetch` use the Fetch API's own types,
`Request`, `RequestInit`, `Response` and `URL`, which TypeScript's `dom`
library declares. Handles are declared read-only, and options take only
their documented values, such as `policy: 'lenient' | 'strict'`. The types
describe the checks that the facade makes anyway at run time.

The consumer qualification checks the declarations with TypeScript 5.9.3
and 7.0.2 with `strict` on: the first two entries, and the example above,
without the DOM library, and the Fetch entry with it. A test also requires
each declaration file to declare exactly the functions and classes that its
entry exports, and the handles to have exactly the properties that their
declarations list.

## Troubleshooting

**`ERR_MODULE_NOT_FOUND` for `bend-trace-context`.** The project has not
installed the package: run
`npm install ./deps/bend-trace-context/packages/trace-context`.

**`ERR_PACKAGE_PATH_NOT_EXPORTED`.** Only the three entries are exported;
files such as `javascript/codec.mjs` or `entropy/webcrypto.js` are internal.
Import `bend-trace-context`, `bend-trace-context/node` or
`bend-trace-context/fetch`.

**A Node request carries no context with `tracedFetch`.** Outside a page
there is no own origin: pass the destinations in `propagateTo`, or use
`send` and `fetch` as in [node:http and fetch](#nodehttp-and-fetch).

**A cross-origin request from a page fails.** Its server's CORS preflight
does not allow `traceparent` and `tracestate`; see
[Cross-origin requests and CORS](#cross-origin-requests-and-cors).

**A cross-origin request from a page carries no context.** Its origin is not
in `propagateTo`, or the request is `no-cors`.

**`TypeError: ... must be ... returned by bend-trace-context`.** A function
received a copy of a handle, or an object shaped like one; pass the handle
that the facade returned.

**`RangeError: InvalidKey`, `ZeroTraceId`, ...** The package refused a
value; [Errors and diagnostics](ERRORS.md#javascript) lists every name.

**My tracing backend shows no traces.** The facade records no spans: a
tracer records them, such as OpenTelemetry, as the
[OpenTelemetry recipe](#opentelemetry) shows. Its samplers usually follow
the sampled flag, and new traces start unsampled. To sample the traces that
a service starts and keep the caller's decision for the others, as the
[guide](GUIDE.md#sampling) explains, pass
`sampling: extraction.context === null ? 'sampled' : 'inherit'` to
`continueOrStart`.

## How the facade works

The compiler's ES module of a `.bend` file (`bend file.bend -o file.mjs`)
exports the file's definitions as JavaScript functions, but it runs no IO
operation. An IO operation without parameters, such as `read_u32` of
entropy.bend, is not exported. One with parameters, such as `Context.root`
or `Context.continue_or_start` of generation.bend, returns an unrun IO
action: calling it reads no word. A definition that takes a template, such as
`Context.continue_or_start_with`, is not exported at all. The package
therefore gives a host that feeds words itself a pure form of each
generating operation, described in
[Host-driven generation](README.md#host-driven-generation):

1. `Generation.needs`, `Generation.feed` and `Generation.result` drive one
   generation, a word at a time.
2. `ServicePlan` and `SendPlan` record what continuing or starting and
   sending decide before they read a word.

The package's own IO operations run on those same plans. Law
`generation_drive` proves that a host's loop reads the same words and gets
the same result as the pure driver that the other generation laws describe.
Laws `hosted_service` and `hosted_send` prove that a host that drives the
plans itself gets what the IO operations give, for every sequence of words.
The facade is such a host: it only chooses what to wrap and what to throw.
The laws hold of that host path in Bend; that the facade's JavaScript follows
it is tested, not proved. The facade's conversions, its handle checks and the
host effects are tested boundaries of foreign code, not formal proofs.

The facade imports [`javascript/trace_context.mjs`](javascript/trace_context.mjs),
which `./scripts/build-js.sh` builds from the Bend sources with the pinned
compiler; the qualification requires the committed file to be that build,
byte for byte. That module exports the compiler's own representations, such
as tagged objects and erased proof fields: a JavaScript object shaped like
a `TraceParentV00` is not evidence of validity. The facade therefore
accepts only wire or scalar inputs and its own handles, and code that calls
the raw module directly bypasses that boundary. The facade reaches no system
binding: the Bend runtime keeps its `bun:ffi` bindings behind
`globalThis.BEND_SYS`, which the package's ES module never names, and a test
traps that global while the facade works. bend-kit's JavaScript transport,
which runs on Bun, plays no part here.

Words come from the package's WebCrypto source, which the facade and Bend
programs compiled to JavaScript share. It asks `getRandomValues` for one
32-bit word at a time, from the `crypto` option or `globalThis.crypto` when
called. It fails with code 1, `unavailable`, when there is no
`getRandomValues`, and with code 2, `source-failure`, when the call throws
or answers anything but a 32-bit word. There is no time, counter or
`Math.random` fallback, and no retry. A provider is trusted to supply
entropy: validating a returned integer cannot prove its cryptographic origin.

A Bend program that imports generation.bend also runs on Node: build it with
`-o main.js` and run `node main.js`, as the consumer tests do with the
[Bend quick start](../../README.md#quick-start-bend). It reads its words
through the same source, which the package registers as the JavaScript side
of its `entropy.bend` effect; natively, the effect reads the host's
generator. `-o main.mjs` builds an ES module of the program's functions
instead, which runs nothing when Node starts it. The
[validation record](VALIDATION.md#javascript) describes how the facade, the
source and the compiled programs are qualified.
