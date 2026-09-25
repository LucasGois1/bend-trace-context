# Native HTTP transport qualification

The repository qualifies the pinned [`paymog/bend-net`](https://github.com/paymog/bend-net/tree/274591f1d1fcca2e4aa39ba65e505b32e2dbff21)
HTTP/1.1 client and server on native Bend 2.0.27 for macOS ARM64 and Linux
x86_64. The tested revision is recorded by the Git submodule at
`vendor/bend-net`.

This is a transport qualification for the repository's development harness. It
does not add Trace Context parsing, context creation, ID generation, propagation
policy, or a tracer. The `/relay` probe forwards header values unchanged at the
application layer so tests can observe what the transport does to field names,
repeated values and optional whitespace. It does not interpret those values.
The `/test` route accepts the W3C test harness's basic JSON action shape
(`url` and `arguments`) and posts each `arguments` value to its callback URL;
this is not a claim that the codec or a propagator passes the W3C trace suite.
The envelope follows the harness pinned at
[`w3c/trace-context` commit `acab820`](https://github.com/w3c/trace-context/tree/acab820be9db7b3433668baa5cdd43f57f4c4be0/test).

The dependency is a Bend-native HTTP implementation with explicit `IO` effects
and a small foreign runtime seam. Its JavaScript runtime path targets Bun; this
qualification builds and executes its native C backend directly and makes no
Node.js transport claim. Node 24 is used only as an independent local HTTP
observer and raw-socket test driver.

Initialize the exact dependency and install the pinned compiler:

```sh
git submodule update --init --recursive
./scripts/setup-bend.sh
```

Run the full offline qualification on macOS ARM64 or Linux x86_64 (Clang 14+
and Node 24 required):

```sh
./scripts/qualify-native-http.sh
```

The script checks the submodule SHA and dependency proofs, builds
`tests/native/fixtures/transport-service.bend` as a native executable, then runs
real loopback HTTP tests. Evidence is written under `build/native-http/`.
Nothing in this route calls an external service.
The suite checks the dependency's 431 oversized-header response and 413
declared-body-limit response, plus repeated field ordering and trimming.

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
