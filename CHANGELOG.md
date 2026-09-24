# Changelog

## 0.1.0-dev — unreleased

Development toward the complete 0.1.0 Trace Context propagator. This version
currently provides the strict v00 codec only; it is not a published release.

- Preserve the pure Bend codec, dependent ID representation, universal
  round-trip and fixed-length proofs, independent protocol corpus and
  negative-construction examples.
- Establish reproducible Bend 2.0.27 setup, Git-pinned consumption, MIT licensing
  and baseline validation on native and Node targets.

The inverse law for every accepted text remains pending in issue #5. ID
generation, tracestate, propagation and HTTP/browser integration are planned
under [specification #1](https://github.com/LucasGois1/bend-trace-context/issues/1).

## Versioning and compatibility

`VERSION` identifies the source's development/release status. Before 0.1.0 is
released, use a full Git commit SHA as the installation identity; a branch name
or `0.1.0-dev` does not identify an immutable artifact. No registry release or
version tag has been published by this baseline.

The documented public entry is `packages/trace-context/trace_context.bend`.
Its documented types, constructors, functions and error behavior form the
current API contract. Internal parsing/proof helpers are not compatibility
promises, even where Bend makes their names importable.

Future releases will record API, wire-policy and toolchain changes here, including
migration steps for incompatible changes. Development toward 0.1.0 does not
silently turn the strict codec into a normalizing propagator. Existing consumers
need no source migration for this baseline; install the pinned compiler and
import the same public entry from their pinned dependency checkout.
