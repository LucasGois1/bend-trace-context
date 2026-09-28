# Security policy

## Supported versions

bend-trace-context has not been released yet. Until 0.1.0 is released,
security fixes land on `master`; after it, on the latest release.

## Reporting a vulnerability

Report a vulnerability privately, through GitHub's
[private vulnerability reporting](https://github.com/LucasGois1/bend-trace-context/security/advisories/new),
and not in a public issue or pull request. Include what you observed, the
input or steps that reproduce it, and the version or commit. If that form is
not available to you, open an issue that asks for a private contact, with
no detail of the vulnerability.

The maintainer acknowledges the report on it. Once a fix is ready, it is
released, and the report is published as a GitHub security advisory, with
credit to you unless you prefer otherwise.

## Scope

Reports about the package itself are in scope: its handling of received
`traceparent` and `tracestate` values, the identifiers that it generates,
the JavaScript facade and its integrations, and the scripts that install
its toolchain. Vulnerabilities in Bend, in bend-kit or in a browser or Node
belong to those projects.

The [guide's security considerations](packages/trace-context/GUIDE.md#security-considerations)
describe what the package guarantees and what it leaves to your service.
