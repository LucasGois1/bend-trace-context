# Changelog

## 0.1.0-dev — unreleased

Development toward the complete 0.1.0 Trace Context propagator. This version
currently provides the strict v00 codec and qualified JavaScript/entropy
boundaries; it is not a published release.

- Preserve the pure Bend codec, dependent ID representation, universal
  round-trip and fixed-length proofs, independent protocol corpus and
  negative-construction examples.
- Establish reproducible Bend 2.0.27 setup, Git-pinned consumption, MIT licensing
  and baseline validation on native and Node targets.
- Standardize documentation and package paths in English, including the public
  entry `packages/trace-context/trace_context.bend` and `examples/` directory.
- Qualify pure module consumption in Node 22/24 and Chromium/Firefox/WebKit with
  the official Bend loader and HTML bundler. Add primitive-string inspection and
  a shared WebCrypto source whose explicit Bend JS effect returns structured
  failures. Native entropy, ID generation and HTTP/Fetch integration remain
  separate planned capabilities.
- Pin `paymog/bend-net` at `274591f1d1fcca2e4aa39ba65e505b32e2dbff21` and
  qualify its native HTTP client/server on macOS ARM64 and Linux x86_64 with a
  real loopback observer, repeated trace-header values, whitespace handling,
  no-redirect behavior and the listener's header-size limit. This is a
  development transport fixture, not Trace Context propagation or a tracer.

The inverse law for every accepted text remains pending in issue #5. ID
generation, tracestate, propagation and HTTP/Fetch integration are planned
under [specification #1](https://github.com/LucasGois1/bend-trace-context/issues/1).

## Versioning and compatibility

`VERSION` identifies the source's development/release status. Before 0.1.0 is
released, use a full Git commit SHA as the installation identity; a branch name
or `0.1.0-dev` does not identify an immutable artifact. No registry release or
version tag has been published by this baseline.

The documented pure Bend entry is `packages/trace-context/trace_context.bend`.
Its documented types, constructors, functions and error behavior form the
current API contract. Internal parsing/proof helpers are not compatibility
promises, even where Bend makes their names importable.

The additional JavaScript inspection and entropy entries and their error
contracts are documented in the [qualification guide](packages/trace-context/JAVASCRIPT.md).

Future releases will record API, wire-policy and toolchain changes here, including
migration steps for incompatible changes. Development toward 0.1.0 does not
silently turn the strict codec into a normalizing propagator. When upgrading an
earlier development snapshot, update the dependency pin and imports together
to use `packages/trace-context/trace_context.bend`. The protocol, public types
and functions are unchanged by this directory migration.
