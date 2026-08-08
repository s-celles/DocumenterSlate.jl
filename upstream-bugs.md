# Upstream findings / spec-vs-reality gaps — KaimonSlate.jl

Tracked per this repo's CLAUDE.md convention ("if you find upstream bug create entry in
upstream-bugs.md"). These are not all "bugs" — some are gaps between spec.md's assumptions
(written without access to KaimonSlate's source) and what real KaimonSlate notebooks/exports
actually contain, found during the M0 feasibility spike (2026-08-08).

Sources: Julia General registry entries for `KaimonSlate`/`SlateExtensionsBase`; the `s-celles`
GitHub account's own KaimonSlate-based projects (`PARI-GP-Slate.jl`, `TachikomaSlate.jl`,
`SlateExtensionsBase.jl`) and `kahliburke/GiacSlate.jl`, `kahliburke/slate-publish-test`. The
KaimonSlate core repo itself (`kahliburke/KaimonSlate.jl`) and its docs site are inaccessible
(404, no Wayback snapshot) — everything below is inferred from downstream consumers, not from
upstream source directly, and should be confirmed with @kahliburke when possible.

## 1. Notebook environment is not `Project.toml`/`Manifest.toml` (affects ADR-004, REQ-EXE-02, REQ-DIST-02)

Per-notebook dependencies are recorded in an embedded footer block inside the `.jl` file:

```
# ╔═╡ Slate.env · notebook packages (auto-maintained — manage via the package panel)
#   Giac 0.14.1 e4421f97-9838-4fd0-9fa5-94f11373bf78
# ╚═╡
```

name/version/UUID triples, not a resolved `Manifest.toml` with tree hashes or transitive pins.
`PARI-GP-Slate.jl` sidesteps this by giving its notebooks a shared external `notebooks/Project.toml`
instead. Cache-key and manifest-publishing requirements need a fallback: resolve a real Manifest via
`Pkg` from the `Slate.env` footer when no external Project.toml exists, or accept the footer text
itself as a weaker cache component.

## 2. Front-matter is per-cell "roles," not a `[documenter]` TOML block (affects REQ-INT-02, spec §7/§10)

Real exports show title/byline/abstract/bibliography built from role-tagged ordinary cells
(`title`, `abstract`, `bibliography`, `caption`, …), not a TOML block in cell 1. DocumenterSlate
needs to either read these roles directly or define its own separate `[documenter]` convention
layered on top — decide explicitly, don't assume the TOML block exists upstream.

## 3. ECharts may not always freeze to a PNG snapshot (affects REQ-REN-03/12, ADR-005)

A real `kahliburke/slate-publish-test` gh-pages export renders ECharts as live client-side JS
(`_slateCharts` + `echarts.init(...).setOption(...)`), not a frozen raster, contradicting a
Discourse claim that ECharts freezes to a PNG. Possibly a difference between export modes (manager-
published site vs. self-contained `.html`) — re-verify empirically once a real KaimonSlate install
is available rather than trusting either source.

## 4. Registry: `KaimonSlate` is already in General (resolves spec §15 open question 6, ADR-001)

`KaimonSlate` and `SlateExtensionsBase` are in the Julia General registry. `SlateRegistry` now
exists only for extension packages, not the core package. `DocumenterSlate.jl` (depends on
`Documenter` + `KaimonSlate`, both General) likely does not need `SlateRegistry` and can probably
target General directly — confirm with @kahliburke before publishing, don't assume silently.

## 5. Agent disable mechanism (REQ-SEC-01) — still unresolved

No `KAIMONSLATE_AGENT`-style env var or agent-disable flag found anywhere accessible. `Tachikoma.jl`
is confirmed NOT the AI agent (it's an unrelated terminal-UI framework). This remains a hard
blocker for REQ-SEC-01 and most likely requires asking @kahliburke directly — the core repo's
inaccessibility means it can't be reverse-engineered from source.

## 6. Hub CSRF/origin defenses (REQ-SEC-04, T4) — still unresolved

A real hub HTTP route was confirmed to exist (`POST /api/<nb>/bind/<cell>`, from
`TachikomaSlate.jl`'s README), but no evidence of Origin/token verification was found on it or any
other hub route. Treat as "undocumented," not as "confirmed absent" — relevant only once
`HubExporter` is scoped (not needed for M1's `TextualReplayExporter`).

## 7. Working precedent for headless execution exists (resolves M0's core question)

`PARI-GP-Slate.jl/test/run_notebooks.jl` is a real, CI-tested (`ubuntu-latest`, no display) headless
notebook runner: parses cells top-to-bottom, evaluates each in a fresh `Module`, stubs `@bind`/
widget constructors to return their default value. This is the basis for the recommended
`TextualReplayExporter` (see ADR-003 revision proposal, M1 task breakdown from the M0 spike).

**Update (M1 planning session, same day):** `PARI-GP-Slate.jl` was not found on this machine when
re-checked — its description above could not be independently re-verified this session. However a
much stronger source turned up instead: a real local checkout of `KaimonSlate.jl` v1.0.0 at
`/home/scelles-admin/git/github/s-celles/julia/KaimonSlate.jl` (sibling to this repo), matching the
`compat = "1"` already pinned in this package's `Project.toml`. Findings below are read directly
from that source, not inferred from downstream consumers — treat them as higher-confidence than
findings 1-6 above.

- Real cell syntax is `#%% code id=<id> [tags…]` / `#%% md id=<id> [tags…]` (`src/engine.jl:164-259`
  and every file under `examples/`), not a Pluto-`# ╔═╡` format.
- `KaimonSlate.standalone!(m::Module=Main; dir=nothing)` is an **exported, public, documented**
  function (`src/widgets.jl:1076-1105`) built for exactly DocumenterSlate's use case: inject the
  notebook-namespace contract into a module so a Slate `.jl` file runs as plain Julia
  (`julia notebook.jl` / `include`), Pluto-style, with `@bind x W(…)` resolving to `W`'s default
  (`widgets.jl:1084`) — no browser/hub required. Every real notebook's first line is
  `KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)` (`engine.jl:202`). This resolves spec §15 Q1/
  Q2/Q4 for the headless-execution case specifically (does NOT resolve them for hub-driven live
  `@bind` UI interaction, which stays open).
- `KaimonSlate.ReportEngine` (re-exported unqualified via `using .ReportEngine` in
  `KaimonSlate.jl`'s top module, `engine.jl:20-24`, even though not in `KaimonSlate`'s own `export`
  line) provides `parse_report(text) -> Report` with `Report.cells::Vector{Cell}`,
  `Cell.kind::CellKind`, `Cell.source::String`, `Cell.flags::Set{Symbol}` — reuse this for
  discovery/parsing rather than reimplementing a `#%%` parser from scratch.
- Role/front-matter tags (`title`, `abstract`, `bibliography`, `caption`, `hidecode`, `collapsed`,
  `slide`, `notes`, …) live in `Cell.flags` (`engine.jl:256-259`). `hidecode` is the real equivalent
  of REQ-REN-05's "`# hide`" (source hidden, output kept) — no "hide cell + output entirely" tag was
  found, so a literal "`# hideall`" equivalent is **unconfirmed**; implement only `hidecode` in M1
  and treat "hideall" as an upstream question, not a guessed convention.
- The `Slate.env` footer (`engine.jl:188-210`, round-trip-tested in `KaimonSlate.jl`'s own
  `test/test_repro.jl:7-38`) is confirmed to match finding #1 above exactly: name/version/UUID
  triples, parsed into `Report.meta["env"]`, never a resolved `Manifest.toml`.
- `KaimonSlate.ReportEngine.run_capture` (`capture.jl:566`) is a rich per-cell capture (stdout,
  richest-MIME display, exception+backtrace, value repr, truncation) but is **not exported** by
  `ReportEngine` — the single biggest available risk-reducer for REQ-REN output fidelity, but
  relying on it means depending on an unexported internal with no semver guarantee. M1 deliberately
  avoids it (see Decision A/B below and the M1 task breakdown) in favor of a cruder but
  semver-stable reimplementation; worth proposing to @kahliburke as an export candidate — this is
  exactly the kind of upstream ask spec §15 Q3 already anticipates.

## 8. Design decisions ratified for M1 (provisional — not yet confirmed with @kahliburke)

**Decision A — notebook environment resolution (REQ-EXE-02, ADR-004 cache-key input).** Real
notebooks carry only the `Slate.env` footer (name/version/UUID, no tree hashes, no transitive pins)
unless the author also maintains an external `Project.toml`/`Manifest.toml` beside the notebook (the
`PARI-GP-Slate.jl` convention per finding #1 — a DocumenterSlate-invented layering, not something
KaimonSlate itself references anywhere found in its source). **Adopted for M1:** resolution order is
(1) external `Project.toml` beside/above the notebook if present → real resolved `Manifest.toml`,
satisfying ADR-004 as originally written; (2) else fall back to executing inside `docs/`'s own
pinned project and use the literal `Slate.env` footer text as the (weaker) cache-key + provenance
component, with an explicit `@warn`/log entry documenting the limitation. Actually `Pkg.resolve`-ing
a real Manifest from the footer is deferred to M2/M3b — M1 needs a stable execution environment and
a deterministic cache-key input, not yet bit-exact reproducibility (that's REQ-DIST-02's concern,
forced by M3b, not M1).

**Decision B — front-matter convention (REQ-INT-02, spec §7/§10).** Real title/abstract/
bibliography come from role-tagged cells (`Cell.flags`), not a `[documenter]` TOML block in cell 1
(finding #2). **Adopted for M1:** read `title` via the same fallback chain KaimonSlate's own PDF/
Typst export already uses — `:title`-tagged cell → first Markdown H1 → filename (confirmed at
`export_typst.jl:664-668`) — zero new convention invented for that field. For fields upstream has no
opinion on (`order`, `skip`, `show_code`, `binds`), use the already-spec'd `docs/slate.toml`
`[[notebook]]` table (spec §10), not a per-notebook cell-1 TOML block.

Both decisions are judgment calls inferred from reading KaimonSlate's source, not confirmed
upstream — flag to @kahliburke (spec §15 Q7/Q8 territory) before treating either as final for a
public release; they are load-bearing enough for M1 implementation to proceed on now.

## 9. REQ-SEC-01 (AI agent off in CI) — resolved for the current backend, not for future ones

Spec §15 Q5 asked how KaimonSlate's agent is disabled and whether that's verifiable from the
calling process. No upstream disable flag/env var was found anywhere in the source (confirmed
again during M3 planning). However, for `TextualReplayExporter` (the only execution backend
implemented through M2), the question resolves differently: the agent is architecturally
unreachable, not merely "assumed off."

Confirmed by reading `KaimonSlate.jl/src/KaimonSlate.jl` directly (M3 planning session):

- The hub/agent machinery is gated behind `_hub()` (`KaimonSlate.jl:174-181`), which lazily
  starts `NotebookServer.start_hub(...)` on first call and is only reachable from the live/
  interactive server code paths (`KaimonSlate.jl:535,1518,1813,1899` — all inside
  `NotebookServer`-facing functions like remote publish, agent tool dispatch, and the hub's own
  boot sequence).
- `__init__` (`KaimonSlate.jl:130-139`) only self-registers as a Kaimon extension (which is what
  exposes the agent's tool-calling surface) when `haskey(ENV, "KAIMON_EXTENSION")` is true — never
  true for a plain `using KaimonSlate` / `import KaimonSlate` from a Julia script or CI job.
- `KaimonSlate.standalone!` (`widgets.jl:1095-1105`, the sole entry point `TextualReplayExporter`
  calls into) does nothing but call `_populate_notebook_ns!` with plain function objects
  (`echart`, `EChart`, `slate_table`, …) and set a `const __slate_standalone = true` marker. It
  never references `_hub`, `NotebookServer`, or anything agent-related. `DocumenterSlate.jl`'s
  only other calls into KaimonSlate (`parse_report`, the `MARKDOWN` enum value) are pure parsing,
  same story.

**Conclusion**: for `TextualReplayExporter`, REQ-SEC-01 holds *by construction* — there is no
code path from `execute_notebook` that could start the hub or reach the agent, regardless of any
CI configuration. This is stronger than a disable flag (nothing to misconfigure), but it is
**specific to this backend**. It does **not** resolve REQ-SEC-01 for a future `HubExporter`
(M4+, spec ADR-003's third tier) — that backend drives the hub directly, where the agent *is*
reachable, and no upstream disable mechanism has been found. Re-open this question before any
hub-based exporter ships.
