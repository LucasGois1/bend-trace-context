# Contributing

Thank you for helping. This file explains how the repository works and how
to run its gates; the [README](README.md) and the
[guide](packages/trace-context/GUIDE.md) explain the package itself.

## How work is organized

- The approved specification is
  [issue #1](https://github.com/LucasGois1/bend-trace-context/issues/1).
  Each change starts from an issue with its acceptance criteria, and the
  decisions taken while doing it are recorded on that issue.
- A pull request is complete when it is opened: it fixes every problem that
  its work found within its scope, with the laws, tests and documentation
  that the change needs. A problem outside that scope gets an issue of its
  own.
- English is the repository's language, for code, comments, documentation,
  file names and GitHub.
- [CONTEXT.md](CONTEXT.md) is the glossary: use its terms, and its
  preferred words over the ones it asks to avoid.

## Setting up

You need Git, a POSIX shell, curl, tar, a SHA-256 utility, Clang 14 or later
for native builds, as Bend requires (CI builds with Apple clang 15 and
Ubuntu clang 18), Node 22.18.0 or a later Node 22, or Node 24, and Python
3.13 for the W3C harness. The compiler installer supports macOS ARM64 and
Linux x86_64.

```sh
./scripts/setup-bend.sh
npm ci --ignore-scripts
npx --no-install playwright install chromium firefox webkit
```

`setup-bend.sh` installs the pinned Bend release under `.tools/`, after
checking its SHA-256; `./bend` runs it. `npm ci` installs the qualification
tooling locked in `package-lock.json`: Playwright, TypeScript 5.9 and 7.0,
and the frameworks of the JavaScript recipes; `npx tsc` runs 5.9, and
`node node_modules/typescript/bin/tsc` runs 7.0. It also links the package into
`node_modules` as `bend-trace-context`, so that the JavaScript examples
import it by name, as an application does. The package itself has no
dependencies.

## Layout

| Path | Holds |
| --- | --- |
| `packages/trace-context/*.bend` | The package: `trace_context.bend`, `generation.bend`, `native_http.bend` and `entropy.bend` with its effects in `entropy/` |
| `packages/trace-context/LAWS.bend`, `PROOF.bend`, `proofs/` | The laws and their proofs |
| `packages/trace-context/tests/`, `tests/` | Corpora and fixtures in Bend, and the JavaScript, browser, consumer, propagation and native HTTP tests |
| `packages/trace-context/javascript/` | The JavaScript facade, its type declarations, and `trace_context.mjs`, which `scripts/build-js.sh` generates |
| `packages/trace-context/examples/`, `examples/` | Runnable examples |
| `scripts/` | The gates, the installer and the build of the ES module |

## Gates

Every gate prints its evidence and exits non-zero on a failure; CI runs all
of them.

```sh
./scripts/validate.sh native
./scripts/validate.sh node
./scripts/test-installer.sh
./scripts/qualify-js.sh node
npm run build:browser
./scripts/qualify-js.sh browser
./scripts/test-consumer.sh native
./scripts/test-consumer.sh node
./scripts/test-consumer.sh browser
./scripts/qualify-native-http.sh
./scripts/qualify-propagation.sh native
./scripts/qualify-propagation.sh node
./scripts/qualify-release.sh candidate
./scripts/check-requirements.sh
```

- `validate.sh` requires `ALL PROOFS CHECK` from `PROOF.bend`, pins the host
  operations that rely on foreign code, checks the compile-time rejections,
  and runs the corpora and the examples, natively or compiled to JavaScript
  for Node.
- `test-installer.sh` checks the compiler installer against the real
  release, with corrupt and failed downloads and existing destinations.
- `qualify-js.sh` requires the committed ES module to be the exact build of
  the sources, and runs the JavaScript tests on Node or the page tests in
  the three browser engines, with a reproducible bundle.
- `test-consumer.sh` clones the committed `HEAD` afresh, installs the
  package into an independent project, and runs the consumer and every
  program of the README and the guides against the output that they show,
  the JavaScript recipes against an observer, the type declarations with
  TypeScript 5.9 and 7.0, and the README's browser quick start and an
  independent page in the three engines. It tests commits, not uncommitted
  edits.
- `qualify-native-http.sh` runs bend-kit's own HTTP laws and checks at the
  commit that published the package, and the transport tests.
- `qualify-propagation.sh` builds a service and the gateway example from a
  fresh clone, runs the propagation checks against an independent observer,
  and runs the W3C Trace Context harness at Level 2, natively on bend-kit or
  in Node on the facade.
- `qualify-release.sh candidate` publishes a fresh clone's BendHub package
  to a local hub with the pinned compiler's `--publish`, requires exactly
  the package's modules, effects and MIT license in it, and runs a clean
  consumer that imports it by its name. Its report,
  `build/release-candidate/artifact.txt`, lists what a publication would
  send.

Evidence goes under `build/`. CI keeps it for 14 days, including after a
failure, and records every runtime version. CI also runs ShellCheck,
actionlint, zizmor, JavaScript syntax checks, a local link check and
`./scripts/check-requirements.sh`, which requires the
[requirements matrix](packages/trace-context/REQUIREMENTS.md) to cite every
law; a weekly workflow checks external links. A change that adds a law,
or changes what a requirement rests on, updates the matrix.

The package pins one exact Bend release, and Bend releases often. Every
week, and on demand, the `Newest Bend` workflow runs the gates on the
newest Bend release in place of the pinned one: `./scripts/try-bend.sh`
pins that release in the runner's checkout only and commits the result
there. It is not a required check. A failed run means that moving to that
release needs work, and GitHub notifies the maintainer.

## Laws and proofs

[LAWS.bend](packages/trace-context/LAWS.bend) states the claims, each with a
comment that gives its meaning, its requirement and how to read it; the
project owner reviews and owns them. [PROOF.bend](packages/trace-context/PROOF.bend)
proves each law with a definition of the same name, with helper lemmas in
`proofs/`. A change that alters a public behavior states it as a law when it
holds for every input.

`PROOF.bend` must print `ALL PROOFS CHECK`, so nothing it imports may rely
on `@unsafe` or on foreign code: the laws state the host operations of
generation.bend over a caller's source instead.

## Documentation

The code blocks between `<!-- test:NAME:start -->` and
`<!-- test:NAME:end -->` markers in the README and the guides are run by
`test-consumer.sh`, and a block marked `NAME-output` holds the output that
the code must print. Keep them runnable, and print only what does not change
from run to run, apart from `span_id=` log fields, whose 16 digits the
comparison masks unless they are the documents' received parent IDs. Mark every program that a reader may copy. The guide's
native HTTP service is compared with the gateway example instead, which the
propagation gates run, and the TypeScript example is type-checked. Command
lines, signatures and the outputs of long-running services are not run.

## The JavaScript module

The facade imports `packages/trace-context/javascript/trace_context.mjs`,
which the pinned compiler builds from `trace_context.bend`. After changing
the Bend sources, rebuild it and commit the result:

```sh
./scripts/build-js.sh
```

`./scripts/build-js.sh --check` fails when the committed file is not the
build. The declarations in `javascript/*.d.mts` must declare exactly what
each entry exports, which a test checks.

## Releasing

A release is a pull request that sets `VERSION`, the JavaScript package's
version and a dated changelog section, which names the package's hash from
`qualify-release.sh candidate`. Once its CI passes and the maintainer has
reviewed the concrete artifact, `build/release-candidate/artifact.txt` of its
commit, the maintainer releases it from a fresh clone of that commit:

1. `./scripts/setup-bend.sh`, then `./bend login`, which authorizes this
   machine in the browser for the BendHub account that owns the name.
2. Publish the package without a name, and check that the hash it prints is
   the reviewed one:

   ```sh
   ./bend packages/trace-context/generation.bend --publish
   ```

   A publication is public and permanent, under
   [BendHub's terms](https://bend-lang.com/bender/terms#s18).
3. Name that package, `./bend link bend-trace-context@X.Y.Z.0 0x<hash>`,
   which also registers the name the first time.
4. `./scripts/qualify-release.sh published <commit>`: BendHub must name
   exactly the commit's package, owned by the repository's owner, and a
   clean consumer runs against BendHub.
5. Merge the pull request, whose README says that the release is published,
   now true. Tag the merge commit `vX.Y.Z`, and run
   `qualify-release.sh published` on it: its package files are the reviewed
   commit's, so it names the same package.
6. Publish a GitHub release for the tag, with the changelog section, the
   artifact and a link to the CI run of the tag's commit, and report on the
   release issue the state of the implementation, the proofs, the
   integrations, CI and the publication, each apart.
7. Set `VERSION` to the next version with `-dev`.

## Moving to a new Bend release

1. Update `version`, `release_commit` and the platform digests in
   [scripts/setup-bend.sh](scripts/setup-bend.sh); the wrapper and the
   installer tests read the version from there.
2. Run `./scripts/setup-bend.sh` and `./scripts/build-js.sh`.
   `./scripts/try-bend.sh X.Y.Z` does both steps from GitHub's release
   metadata, and commits them locally as a start.
3. Read the release notes for changes to effects, the proof verdict,
   `Base`, the JavaScript output and the HTTP dependencies, and run every
   gate.
4. Update the documentation, the changelog and its migration notes.

[Issue #29](https://github.com/LucasGois1/bend-trace-context/issues/29)
records the move from Bend 2.0.27 to 2.0.32, and
[issue #36](https://github.com/LucasGois1/bend-trace-context/issues/36) the
move to 2.0.34.
