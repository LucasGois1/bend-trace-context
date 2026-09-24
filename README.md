# bend-trace-context

A pure, strict `traceparent` v00 codec for **Bend 2.0.27**, using dependent ID
types and checked proofs. Licensed under [MIT](LICENSE).

**Status: 0.1.0-dev.** The complete Trace Context propagator is being developed
under [specification #1](https://github.com/LucasGois1/bend-trace-context/issues/1).
The current codec parses, formats and inspects the sampled bit. ID generation,
`tracestate`, context lifecycles and HTTP/browser adapters are not implemented
yet. No BendHub package has been published.

## Try the codec

Prerequisites: Git, POSIX shell, curl, tar, a SHA-256 utility (`sha256sum` or
`shasum`), and Clang 14+ for native builds. Node 22 or 24 is needed to run
generated JavaScript. The pinned compiler installer supports macOS ARM64 and
Linux x86_64. Access to this repository is currently required because it is
private.

From a checkout of this development branch:

```sh
./scripts/setup-bend.sh
./bend version
./bend packages/trace-context/examples/demo.bend
```

Expected output from the example:

```text
00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01
sampled: True
```

Setup downloads the exact official release, verifies its SHA-256 before
extraction and installs it under `.tools/bend-2.0.27/`. It does not depend on
a pre-existing compiler installation or install global shell configuration.
See [compiler provenance](scripts/setup-bend.sh) for the release commit and hashes.

## Use it from another project

Choose a reviewed **full commit SHA** from this repository and substitute it for
`FULL_COMMIT_SHA` below. This source pin is separate from the compiler pin.
Keep that SHA in your application's dependency record so another checkout uses
the same code; a moving branch or `0.1.0-dev` is not a reproducible version.

```sh
mkdir -p deps
git clone git@github.com:LucasGois1/bend-trace-context.git deps/bend-trace-context
git -C deps/bend-trace-context checkout --detach FULL_COMMIT_SHA
./deps/bend-trace-context/scripts/setup-bend.sh
```

Create `main.bend` in your project:

```bend
import Base
import ./deps/bend-trace-context/packages/trace-context/trace_context.bend as TC

def display(result: Result<&2, &2, TC.Error, TC.TraceParentV00>) -> IO(Unit):
  match result:
    case Fail{error}:
      IO.die(Unit, 1, TC.Error.show(error))
    case Done{context}:
      IO.print(TC.TraceParentV00.format(context))

def main() -> IO(Unit):
  display(TC.TraceParentV00.parse(
    "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"))
```

Then run `./deps/bend-trace-context/bend main.bend`. No implementation files need
to be copied into the application. The documented public entry is the file
imported above; internal helpers are not a compatibility contract.

Read the [API and error reference](packages/trace-context/README.md) for strict
parsing semantics, typed values and proof scope. See [versioning and migration
policy](CHANGELOG.md) before updating a dependency pin.

## Validation

```sh
./scripts/validate.sh native
./scripts/validate.sh node
./scripts/test-consumer.sh native
./scripts/test-consumer.sh node
```

The consumer commands test the current **committed HEAD** in a separate fresh
clone; they do not test uncommitted edits. See [the validation guide](packages/trace-context/VALIDATION.md)
for explicit source/revision arguments and evidence limits.

Baseline gates cover proofs, independent protocol vectors, all 256 flag bytes,
expected static rejections and a consumer outside the repository. CI exercises
native macOS ARM64/Linux x86_64 and Node 22/24, recording exact runtime versions.
Configuring a job is distinct from observing a successful run.

The universal `parse(format(context)) == Done{context}` and fixed-length laws
are proved. The inverse law for every accepted text is still pending. Neither
these laws nor the finite corpus establish full W3C propagator conformance.

## Development

The [approved ticket plan](https://github.com/LucasGois1/bend-trace-context/issues/1) records
dependencies and acceptance criteria. Each slice includes its applicable laws,
tests and consumer documentation.

The package targets [Bend 2](https://bend-lang.com/), maintained at
[bendlang/bend](https://github.com/bendlang/bend).