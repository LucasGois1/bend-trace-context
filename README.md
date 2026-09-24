# bend-trace-context

A pure, strict `traceparent` v00 codec for Bend 2.0.27, using dependent ID
types and checked proofs. The public entry is
[trace_context.bend](packages/trace-context/trace_context.bend).

The implemented codec parses and formats valid contexts, reports structured
errors and inspects the sampled bit. IDs have fixed lengths and checked
nonzero evidence. All 256 flag values are preserved.

## Run the codec

This baseline expects an existing official Bend 2.0.27 installation, including
its bundled assets, at `.tools/runtime/`. An automated, pinned installer is not
yet included. The local `./bend` launcher uses that installation.

```sh
./bend version
./bend packages/trace-context/examples/demo.bend
./bend packages/trace-context/PROOF.bend --check-only
./bend packages/trace-context/tests/TEST.bend
```

The [API reference](packages/trace-context/README.md) describes parsing,
representation, errors and proof scope. The
[validation record](packages/trace-context/VALIDATION.md) distinguishes execution
results from unverified support claims.

## Scope and development

Universal proofs establish fixed output length and
`parse(format(context)) == Done{context}`. The inverse property for every
accepted text still needs a universal proof. Independent protocol vectors and
negative construction fixtures complement these proofs.

The complete propagator is planned in
[specification #1](https://github.com/LucasGois1/bend-trace-context/issues/1)
and the [delivery tickets](https://github.com/LucasGois1/bend-trace-context/issues/1).
`tracestate`, ID generation, context lifecycles and HTTP/browser adapters are
not yet implemented. No package release or complete W3C propagator conformance
is claimed.

The package targets [Bend 2](https://bend-lang.com/), maintained at
[bendlang/bend](https://github.com/bendlang/bend).
