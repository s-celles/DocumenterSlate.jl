# Security posture

This page states plainly what the reference two-job CI workflow (`.github/workflows/docs.yml`)
guarantees, and — just as important — what it does not, yet. Read this before adopting the
same build model for your own package. See `spec.md` (repository root, not shipped in this
site) §12 for the full threat model (T1–T6) this page is a summary of.

## What the two-job split guarantees (REQ-SEC-03)

- **`render-notebooks`** executes untrusted notebook code and holds **no secrets** — no
  `DOCUMENTER_KEY`, no write-scoped `GITHUB_TOKEN`. A malicious or compromised notebook
  dependency running in this job has nothing valuable to exfiltrate through CI's own
  credentials.
- **`build-and-deploy`** holds `DOCUMENTER_KEY` and runs `build_slates(...; execution = :never)`
  — this **never executes a single cell**. A cache miss raises an error rather than falling
  back to execution (REQ-EXE-10). This is enforced in code
  ([`build_slates`](@ref)'s docstring, `_build_one_notebook`'s `execution == :never` branch),
  not only by workflow convention.

## What is *not* guaranteed yet: cache-entry provenance (T6)

`execution = :never`'s cache lookup validates a fingerprint computed purely from *inputs*
(notebook bytes, resolved environment, tool versions, render options) and SHA-256 hashes of the
rendered Markdown, assets, and resolved environment. These hashes detect accidental or external
corruption, but they do not cryptographically bind a cache entry to *who produced it*. Concretely:
a notebook running in
`render-notebooks` has ordinary filesystem access to `docs/slate_cache` in that same job. A
malicious notebook merged into `notebooks/`/`docs/notebooks/` could in principle write a
forged `<slug>.md` + matching `<slug>.cache.toml` pair directly, bypassing
[`cell_to_markdown`](@ref)'s escaping entirely for that page.

This does **not** let a malicious notebook steal secrets or execute code in the privileged
job — `execution = :never` still never executes anything. Per-notebook `PROVENANCE.toml` files
now record the source commit and CI run as distribution metadata, but they are generated after
the cache lookup and are not a cryptographic producer binding. Closing this cache-specific gap
requires a forge build attestation (REQ-TRUST-03) or an equivalent authenticated handoff.
Mitigate the same way you'd mitigate any other risk from a PR touching
`notebooks/`: review those changes at the same rigor as source code (spec.md §12's own T6
mitigation note makes the same recommendation).

## Agent isolation (REQ-SEC-01)

[`TextualReplayExporter`](@ref) — the only execution backend implemented so far — never
starts KaimonSlate's interactive hub or reaches its AI agent. This was confirmed by reading
`KaimonSlate.jl`'s source directly (not assumed): the exporter's only calls into KaimonSlate
(`standalone!`, `parse_report`) never touch `_hub()` or the `KAIMON_EXTENSION`-gated agent
registration. A regression test (`test/test_execute.jl`) checks this at runtime, not only in
documentation.

**This is specific to the current backend.** A future `HubExporter` (driving KaimonSlate's
interactive hub directly, not yet implemented) would reopen this question — the hub *does*
expose the agent's tool-calling surface, and no upstream disable mechanism has been confirmed
to exist. Do not assume this guarantee carries over once a hub-based exporter ships.

## Process, project, and environment isolation (REQ-EXE-02, REQ-SEC-02)

`build_slates` renders every cache miss in a dedicated Julia child process. For a notebook with
an adjacent `Project.toml`, that project is activated before cells run. A timeout terminates and
waits for the operating-system process, including a worker stuck in non-yielding code. The
adjacent project must already be instantiated; documentation builds do not modify it or fetch
dependencies implicitly.

The child does not inherit the parent's environment. Only Julia's internal depot/load-path/thread
settings and `SlateBuildOptions.worker_environment` are passed. The latter is an explicit
`Dict{String,String}`; use it only for reviewed, non-secret values that the notebook genuinely
needs. Its contents affect the cache fingerprint.

For a notebook carrying only a `Slate.env` footer, DocumenterSlate creates a temporary project
from the declared name/UUID/version entries in another isolated process, resolves and instantiates
it, and publishes the resulting `Project.toml` and `Manifest.toml`. The cache artifact carries that
resolved environment into the non-executing deployment job, which never resolves packages.

The lower-level [`execute_notebook`](@ref) API remains an in-process primitive and can see the
caller's process-global `ENV`. Use `build_slates` for isolated documentation builds.

## Network egress (REQ-SEC-04) — monitored, not yet blocked

Both jobs run behind [`step-security/harden-runner`](https://github.com/step-security/harden-runner)
(pinned to a commit SHA, not a floating tag) in **`egress-policy: audit`** mode — every
outbound connection is logged and checked against StepSecurity's always-on malicious-domain
list, but nothing legitimate is blocked yet. This is deliberately the tool's own recommended
starting point, not a shortcut: an earlier attempt at `egress-policy: block` with a guessed
`allowed-endpoints` list was caught by review before merging — the guess missed the actual
redirect chain Julia's package client follows through `pkg.julialang.org` (a region-specific
mirror, then a separate storage backend), which would have made every `render-notebooks` run
fail outright once merged. Shipping a broken block-list is worse than the gap it closes.

Upgrading to `block` is the natural next step, once a real workflow run's harden-runner
insights confirm the exact endpoint set actually used — not before. This is a CI-infra
control, not a `SlateBuildOptions` option — there is no `network = :deny` field on
[`SlateBuildOptions`](@ref). The separate `allow_remote = false` default rejects notebooks
containing `region=<name>` cell tags unless the caller explicitly opts in (REQ-EXE-09); it
controls declared KaimonSlate remote placement, not arbitrary network access by notebook code.

## Remote-region opt-in (REQ-EXE-09)

Before consulting the cache or executing cells, [`build_slates`](@ref) parses every notebook
with KaimonSlate's parser and rejects any cell tagged `region=<name>` while
`SlateBuildOptions.allow_remote == false` (the default). Set `allow_remote = true` only after
reviewing the notebook's declared placement. The current `TextualReplayExporter` still replays
cells locally and never starts remote workers; the opt-in preserves the authorization boundary
for future exporters that can honor region placement.

## Content escaping and path traversal (REQ-SEC-05/06)

- [`discover_notebooks`](@ref) structurally rejects any notebook path that resolves outside
  its declared source directory, including via a symlink (REQ-SEC-06).
- [`cell_to_markdown`](@ref) fences all *derived/executed* content (stdout, values, error
  messages) so it renders as literal text regardless of what it contains — adversarially
  tested against HTML-special payloads, not merely assumed safe (REQ-SEC-05). A notebook's
  own markdown prose is intentionally passed through unmodified, the same as any Documenter
  `.md` source file — that is authored content, not derived output, and carries the same
  trust level as the rest of your documentation source.

## What none of this proves

An attestation or a clean cache lookup proves an artifact's *origin* — that it came from this
workflow, at this commit. It proves nothing about whether the notebook itself is
well-behaved. A malicious notebook authored and merged by a maintainer remains malicious
however cleanly it was built (spec.md §11.5's own point, restated here for the CI/build-cache
context rather than the download/distribution context it was originally written for).
