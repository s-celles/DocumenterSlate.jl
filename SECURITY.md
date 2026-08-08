# Security Policy

## Supported Versions

DocumenterSlate.jl is pre-1.0 and has not yet made a tagged release. Until a
`1.0.0` release, only the latest tagged version (or `main`) receives security
fixes.

| Version   | Supported          |
| --------- | ------------------ |
| `main`    | :white_check_mark: |
| `< 1.0.0` | :white_check_mark: (latest tag only) |

Once DocumenterSlate.jl reaches `1.0.0`, this table will be updated to track
supported major/minor lines following [Semantic Versioning](https://semver.org/).

## Reporting a Vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.

Instead, report vulnerabilities privately using
[GitHub Security Advisories](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing/privately-reporting-a-security-vulnerability)
for this repository:

<https://github.com/s-celles/DocumenterSlate.jl/security/advisories/new>

This lets maintainers triage and fix the issue before public disclosure. You
should receive an initial response within a few days; if you don't, feel free
to follow up on the same advisory thread.

Once a fix is available, we will coordinate a disclosure timeline with you and
publish the advisory (with credit, if desired) alongside the release that
contains the fix.

## Scope Note: Notebook Execution

DocumenterSlate.jl builds documentation by executing
[KaimonSlate.jl](https://github.com/kahliburke/KaimonSlate.jl) reactive
notebooks as part of the documentation build. Executing a notebook means
executing arbitrary Julia code contained in that notebook. Only build
documentation from notebooks you trust (e.g. notebooks reviewed via the same
pull-request process as source code), the same way you would only run `julia`
on scripts you trust.

This repository's own threat model for notebook execution (untrusted
contributions, CI isolation, secrets handling, etc.) is documented separately
in `spec.md` — this file covers the standard vulnerability-disclosure process,
not the full threat model. For a concrete statement of what the reference CI
workflow (`.github/workflows/docs.yml`) actually guarantees today — and what
it does not yet — see the
["Security posture"](https://s-celles.github.io/DocumenterSlate.jl/dev/security/)
page in the published documentation (source: `docs/src/security.md`).
