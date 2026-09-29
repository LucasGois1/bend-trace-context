# Native HTTP transport and propagation

## Transport

The repository qualifies the HTTP/1.1 client and server of
[bend-kit](https://github.com/paymog/bend-kit/tree/31912fbd99e9090df43bf2ef70da4340241e9e51/http), version
0.23.0.1 of `bend-kit-http` on BendHub, on native Bend 2.0.32 for macOS
ARM64 and Linux x86_64. The programs that use it import it by content hash,
`0x1cef8a5fb1d9142ca5c6b2cb43629b21`, together with `bend-kit-json` 0.5.0.1,
`0x584fc27920487ceab242392391418d7f`, the JSON package that it uses, and
Bend checks the files of each against its hash. `bend-kit-http` imports its
other dependencies, such as `bend-kit-wire` 0.4.2.0 and `bend-kit-dns`
0.4.0.2, by name and version, which BendHub resolves to hashes when a build
fetches them. The qualification records each resolution, and the propagation
qualification records those of its own build.

This part qualifies the transport alone. It adds no Trace Context parsing,
context creation, ID generation, propagation policy or tracer; the
[propagation](#propagation) below does. The `/relay` probe forwards header values unchanged at the
application layer so tests can observe what the transport does to field names,
repeated values and optional whitespace. It does not interpret those values.
The `/test` route accepts the W3C test harness's basic JSON action shape
(`url` and `arguments`) and posts each `arguments` value to its callback URL;
this is not a claim that the codec or a propagator passes the W3C trace suite.
The envelope follows the harness pinned at
[`w3c/trace-context` commit `acab820`](https://github.com/w3c/trace-context/tree/acab820be9db7b3433668baa5cdd43f57f4c4be0/test).

The dependency is a Bend-native HTTP implementation with explicit `IO` effects
and foreign runtime code of its own, so a check of a program that imports it
answers `SOME PROOFS FAIL` and names those definitions. Its JavaScript
runtime path targets Bun; this qualification builds and executes its native
C backend directly and makes no Node.js transport claim. Node 24 is used only
as an independent local HTTP observer and raw-socket test driver.

Install the pinned compiler, then run the qualification on macOS ARM64 or
Linux x86_64 (Clang 14 or later, as Bend requires, and Node 24):

```sh
./scripts/setup-bend.sh
./scripts/qualify-native-http.sh
```

The script:

1. checks that every native HTTP program imports the same bend-kit
   packages;
2. builds `tests/native/fixtures/transport-service.bend` as a native
   executable, fetching bend-kit from BendHub into a fresh package cache;
3. clones bend-kit at commit `31912fbd99e9090df43bf2ef70da4340241e9e51`,
   which published `bend-kit-http` 0.23.0.1, requires its `http/http.bend`
   to be byte for byte the file that BendHub serves, and runs its laws and
   checks there. Its laws hold as bend-kit's own check requires: `PROOF.bend`
   answers `SOME PROOFS FAIL` only for definitions that rely on `@unsafe` or
   foreign code, and no law is among them;
4. runs real loopback HTTP tests against the fixture.

Evidence is written under `build/native-http/`. Apart from the BendHub and
GitHub fetches, nothing in this route calls an external service. The suite
checks the dependency's 431 response to a head over 64 KiB and its 413
response to a declared body over the fixture's limit, plus repeated field
ordering and trimming. bend-kit's `Http.serve` binds every interface
(`0.0.0.0`), so the fixture, the propagation service and the gateway example
listen on every interface while they run.

To try the two local processes manually after building:

```sh
./bend tests/native/fixtures/transport-service.bend -o build/native-http/transport-service
node tests/native/fixtures/observer.mjs
```

In another terminal, start `build/native-http/transport-service`, then send a
W3C-shaped action to its callback observer:

```sh
curl --fail-with-body http://127.0.0.1:18773/test \
  -H 'content-type: application/json' \
  --data '[{"url":"http://127.0.0.1:18774/callback/example","arguments":[{"id":1}]}]'
```

The independent observer prints the callback. The `/relay` route can be probed
with `curl -X POST http://127.0.0.1:18773/relay -H 'traceparent: opaque-value' -d '{"probe":true}'`;
it forwards raw transport values to the observer's `/relay` endpoint. The
server is a narrow qualification fixture, not an application framework or
production tracing API.

## Propagation

[native_http.bend](native_http.bend) adapts bend-kit's header maps to the
package, as the [package reference](README.md#native-http-integration)
documents. `./scripts/qualify-propagation.sh native` qualifies that path end
to end, from the exact commit given, or `HEAD` by default, in three steps.
`./scripts/qualify-propagation.sh node` qualifies the
[JavaScript facade](JAVASCRIPT.md) on `node:http` with the same checks and
the same harness run; only the first step differs.

1. It clones that commit. Natively, it builds
   [the propagation service](../../tests/propagation/service.bend) and the
   [gateway example](examples/gateway.bend) from the clone, with bend-kit
   from BendHub, as an application builds them. In Node, it installs
   the facade from the clone into
   [the Node propagation service](../../tests/propagation/service.mjs), and
   runs it and the [gateway example](examples/gateway.mjs) from the clone on
   Node alone.
2. It runs the repository's own checks,
   [propagation.mjs](../../tests/propagation/propagation.mjs) and
   [gateway.mjs](../../tests/propagation/gateway.mjs), against an independent
   Node observer that records the header lines as they arrive. They cover:
   - sampled `0` and every combination of the sampled and random-trace-id
     flags;
   - roots, restarts at a trust boundary and fan-out;
   - repeated injection into reused containers with stale context fields;
   - a discarded state, with diagnostics that hold no received value;
   - source failures for the service's operation and for each child, and
     exhausted candidates, which forward the received pair or clear the
     context;
   - strict refusals;
   - the gateway's call downstream and its log.
3. It fetches the
   [W3C Trace Context harness](https://github.com/w3c/trace-context/tree/acab820be9db7b3433668baa5cdd43f57f4c4be0/test)
   at commit `acab820be9db7b3433668baa5cdd43f57f4c4be0` and installs aiohttp in
   a virtual environment from
   [requirements.txt](../../tests/propagation/requirements.txt), whose
   versions and hashes are pinned. It then starts the service on
   `127.0.0.1:18775` and runs `TraceContextTest`, `AdvancedTest` and
   `TraceContext2Test` with `SPEC_LEVEL=2` and `STRICT_LEVEL=2`. It requires
   all 41 tests to run and pass: a failure, an error or a skipped test, such
   as the Level 2 class without `SPEC_LEVEL=2`, fails the qualification.

The service follows the harness's protocol on `POST /test`: the body is a
JSON array of actions, each `{url, arguments}`, and the service posts each
`arguments` to its `url` with a new child of its operation for the received
request. Its other routes serve the repository's checks:

| Route | What changes |
| --- | --- |
| `/test/restart` | The service restarts the trace, as at a trust boundary |
| `/test/stale` | Each request starts from the received request's context fields and `x-request-id`, and each later one reuses the previous one's fields |
| `/test/unavailable` | The entropy source always fails, so the service has no operation and the requests carry the lenient fallback; they start from the copied fields too. The native service's source fails with `5 entropy unavailable`, and the Node service's WebCrypto is unavailable, `1 unavailable` |
| `/test/unavailable/strict` | The same source under the strict policy, which refuses the request with 503 |
| `/test/unavailable/send` | The service's operation comes from the host source, and each child from the failing one, so each request carries an operating service's fallback |
| `/test/unavailable/send/strict` | The same under the strict policy: the request is refused with 503 before any request is sent |
| `/test/exhausted` | A source that gives only zero words, so every candidate is rejected and generation is exhausted |

The harness runs as published, with no test excluded. Its 41 tests found no
disagreement with
[spec #1](https://github.com/LucasGois1/bend-trace-context/issues/1); the
package's extraction and tracestate corpora already use the harness's
inputs.

Run it natively on macOS ARM64 or Linux x86_64 with the transport's
requirements, Python 3.13 or later with `venv`, and network access to
BendHub for bend-kit, to GitHub for the harness and to PyPI for aiohttp:

```sh
./scripts/setup-bend.sh
./scripts/qualify-propagation.sh native
```

The Node mode needs Node 22.18.0 or a later Node 22, or Node 24, instead of the
transport and the Bend binary: `./scripts/qualify-propagation.sh node`.
Evidence is written under `build/propagation-native/` or
`build/propagation-node/`: the environment, including the Python and
aiohttp versions and, natively, the packages that BendHub resolved, the
compile or install logs, both TAP reports, and the harness output.
