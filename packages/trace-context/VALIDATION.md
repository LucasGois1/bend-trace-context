# Validation performed

**2026-09-24 — Bend 2.0.27, macOS ARM64.** The results below correspond to the
final ID representation: an `evidence` field is available for composing proofs.
Run the commands from the repository root.

## Proofs

```sh
./bend packages/trace-context/PROOF.bend --check-only
```

Result: `All terms check.`, exit status 0, with no `@unsafe` dependency warning.
The gate imports proofs for hexadecimal, indexed sequences, strings, sequence
reading and the complete context. Public laws: length 55 and
`parse(format(context)) == Done{context}` for any typed context.

## Tests and consumer

```sh
./bend packages/trace-context/tests/TEST.bend
./bend packages/trace-context/examples/demo.bend
./bend packages/trace-context/tests/TEST.bend -o build/trace-context-test.js
node build/trace-context-test.js
./bend packages/trace-context/tests/TEST.bend -o build/trace-context-test
./build/trace-context-test
./bend packages/trace-context/examples/demo.bend -o build/trace-context-demo.js
node build/trace-context-demo.js
./bend packages/trace-context/examples/demo.bend -o build/trace-context-demo
./build/trace-context-demo
```

All passed with exit status 0. In a fresh checkout, create `build/` before
compiling; generated artifacts stay out of Git.

The suite contains 8 explicit valid inputs, 26 invalid inputs with expected
errors/positions and all 256 flag values, and also checks the literal
hexadecimal alphabet. The `sampled` oracle uses a numeric counter independent
of the package function. All three execution modes produced:

```text
OK: W3C example and reserved flag bits
OK: lengths, suffixes and version policy
OK: lowercase ASCII alphabet and character offsets
OK: separators and nonzero IDs
OK: all 256 flag bytes preserve format and sampled bit
```

The separate consumer produced this output in all three modes:

```text
00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01
sampled: True
```

## Expected static rejections

These commands **must exit with status 1**:

```sh
./bend packages/trace-context/tests/reject/zero_id.bend --check-only
./bend packages/trace-context/tests/reject/wrong_length.bend --check-only
```

The first was rejected with `expected: True{}` / `observed: False{}` when trying
to supply `{==}` for a zero ID. The second was rejected for supplying
`Digits.Nil` where `Digits.Con<0n>` was required. We use two positions to keep
the examples readable; these are the same type families used for 32- and
16-position IDs.

## Scope

We did not run the complete W3C HTTP suite, GPU execution, other operating
systems, benchmarks or performance assessments. The current consumer is local,
without HTTP package integration yet. The universal inverse property, covering
every accepted text, remains a future obligation explicitly stated in the README.
