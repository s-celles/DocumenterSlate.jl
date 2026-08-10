# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Isolated notebook rendering in a dedicated Julia process with the notebook's adjacent project
  activated, hard process termination at timeout, and a deny-by-default worker environment.
- `SlateBuildOptions.worker_environment`, an explicit `Dict{String,String}` of variables passed
  to notebook workers; it participates in the composite cache fingerprint.
- `verify_slate_bundle` and `SlateBundleVerification`: verify exhaustive artifact checksums and
  provenance coherence for a distribution directory or safely extracted `.tar.gz`, without
  executing notebook code.
- Per-notebook distribution directories with unchanged `.jl` source, resolved environment files,
  deterministic `.tar.gz` archives, `SHA256SUMS`, and `PROVENANCE.toml` build metadata.
- A download panel on every generated notebook page with artifact SHA-256 digests, explicit
  arbitrary-code warnings, and KaimonSlate's `inactive = true` inspection command.
- Distinct `Download notebook` and collapsed `Inspect locally` actions in each notebook panel;
  neither action launches code or contacts a local service.
- Responsive, keyboard-focus-visible styling for the download and inspection actions, including
  dark-color-scheme and reduced-motion adaptations.
- Per-notebook local instructions presenting isolated-container, pinned-host, and native-app
  workflows in increasing order of host exposure.
- A distribution guide documenting verification, safe inspection, execution risks, and the
  current limits of provenance metadata.
- A minimal repository README linking to the published documentation.
- `SlateBuildOptions.allow_remote` with a secure `false` default: notebooks declaring a
  `region=<name>` cell tag are rejected before cache lookup or execution unless the caller
  explicitly opts in (REQ-EXE-09).
- `SlateBuildOptions` and `SlateOutputOptions`: configuration structs for `build_slates`
  (spec.md §7).
- `discover_notebooks`: glob-based notebook discovery under a source directory
  (`include`/`exclude` patterns), with a structural guard against directory traversal via
  symlinks.
- `resolve_notebook_project`/`NotebookProjectResolution`: resolves a notebook's pinned
  dependency environment — an external `Project.toml` beside the notebook if present,
  otherwise a fallback to the notebook's embedded `Slate.env` footer.
- `resolve_notebook_meta`/`NotebookMeta`: resolves per-notebook front-matter (title via a
  role-tag → first Markdown H1 → filename fallback chain matching KaimonSlate's own PDF
  export; `order`/`skip`/`show_code`/`binds` from `docs/slate.toml`'s `[[notebook]]` table).
- `AbstractSlateExporter`/`TextualReplayExporter`: the M1 headless execution backend, built
  on KaimonSlate's exported `standalone!` primitive rather than the interactive hub.
- `execute_notebook`/`ExecutedNotebook`/`CellResult`/`SlateExecutionError`/
  `SlateExecutionTimeoutError`: runs a notebook's cells top-to-bottom in a fresh module,
  capturing stdout/value/errors per cell, with `fail_on_error` stop-and-report semantics
  and a per-notebook execution timeout.
- `cell_to_markdown`: converts an executed cell into Documenter-native Markdown — markdown
  cells pass through with per-notebook anchor-prefixed headings to avoid cross-page
  collisions; code cells respect `hidecode`/`show_code`, render output as a plain fence
  (never doctested), and show an errored cell as a visible admonition.
- `extract_assets!`: writes a code cell's `image/png`/`image/svg+xml`-showable value to a
  destination directory as a deterministically-numbered figure file.
- `build_pages`/`SlateBuildResult`: orders resolved notebooks into a Documenter
  `pages`-ready vector — explicit front-matter `order` first, then alphabetically by title,
  `skip = true` notebooks excluded.
- `build_slates`: the single public orchestration entry point tying discovery, front-matter
  resolution, execution, asset extraction, Markdown rendering, and page ordering together.
- Composite build cache (ADR-004, `src/cache.jl`, internal): a SHA-256 fingerprint over
  notebook bytes, resolved environment, Julia/KaimonSlate/DocumenterSlate versions, and
  render options, backing real `execution = :auto`/`:always`/`:never` semantics in
  `build_slates` — `:never` (REQ-EXE-10, the privileged deploy job's hermetic build mode)
  is functional for the first time; a cache miss raises a clear error instead of executing
  anything.
- `options.nworkers > 1`: notebooks build across genuinely separate OS processes
  (`Distributed`, REQ-EXE-07), not threads — required because `redirect_stdout` is
  process-wide mutable state in Julia, so threaded fan-out would either corrupt output
  across notebooks or fully serialize the part meant to parallelize. Worker processes are
  always torn down (`try`/`finally`), and a notebook failure still raises the original
  `SlateExecutionError`/`SlateExecutionTimeoutError`, not a `Distributed.RemoteException`.
- Per-notebook `@info` build-status logging (`:cached`/`:executed`/`:failed` + elapsed
  time), pulled forward from M3's REQ-CI-02.
- `collect_build_statuses`/`write_github_step_summary`: taps the per-notebook build-status
  log into a `$GITHUB_STEP_SUMMARY`-ready Markdown table (REQ-CI-04). Sequential builds
  only (`options.nworkers <= 1`) — `Distributed` forwards a worker's `@info` as
  pre-formatted text rather than routing it through the master's `Logging` dispatch, so a
  parallel build's statuses aren't collectible here, only visible in the raw CI log.
- `Aqua.jl`/`JET.jl` in the test suite (REQ-TST-03).
- `docs/` site (dogfooded for this package itself rather than a separate example
  repository — REQ-DOC-01's literal "separate repo" would mean standing up a second
  public repo with its own secrets, an external action outside autonomous scope), built
  by the real two-job reference workflow (`.github/workflows/docs.yml`, REQ-SEC-01/02/03,
  REQ-CI-01) over two real KaimonSlate notebooks under `docs/notebooks/`.
- `docs/src/security.md`: states plainly what the CI workflow guarantees today and what
  it does not yet.
- `llms.txt`/`llms-full.txt` generated under `docs/src/` before `makedocs` runs (no
  native Documenter.jl support exists for this, confirmed by checking the latest release
  and a full-repository search).

### Fixed

- Notebook heading anchors now use Documenter's `@id` syntax instead of raw `<a>` elements
  that could appear as visible text in generated pages.
- Development cache keys now include a hash of DocumenterSlate's loaded sources, preventing
  renderer changes under the same `-DEV` version from reusing stale Markdown.
- Local documentation builds no longer emit expected environment warnings: the example
  notebooks now have an explicit Julia project, and `deploydocs` only runs in CI.
- Serialized per-cell stdout capture to prevent a notebook execution that outlives its
  configured `timeout` from corrupting output capture for unrelated, concurrently-running
  executions in the same process.
- Several tests didn't set an explicit `cache_dir`, so once the cache became load-bearing
  they started writing a live `slate_cache/` directory into the real repository (relative
  to the test process's working directory) instead of staying inside their own temp
  directory.
- `cell_to_markdown`'s error branch fenced the backtrace but spliced the exception's own
  message directly into the page as interpretable Markdown (REQ-SEC-05/T3) — an
  adversarial test now locks in the fenced behavior for both the error and ordinary
  success paths.
- `build_pages`' relative paths are relative to `options.output`, not `docs/src/` —
  `docs/make.jl` now prefixes `"notebooks/"` itself, since only the caller knows its own
  directory layout (caught by actually running the docs build end to end, not a unit test).
- Several JET-flagged type-inference gaps in the package's own code (not noise from
  dependencies): `something(...)` narrowing at a handful of provably-non-`nothing`
  `RegexMatch`/correlated-return-value sites, an explicitly-typed `[[notebook]]` TOML
  entry list instead of an `Any`-widened default, and `_build_one_notebook`'s page text
  built via `IOBuffer` instead of `join` (whose inferred return type widened once that
  function's `try` body exceeded Julia's inference complexity budget — confirmed via
  `@code_warntype`, not guessed).

### Changed

- `execute.jl`'s stdout-capture-is-task-local claim was empirically disproven (a leaked
  timed-out task racing a later notebook's capture in the same process) — see the Fixed
  entry above this project's M2 line for the serialization fix; this M3 pass found and
  fixed the remaining downstream type-inference consequences of the same code area.

### Security

- Recorded (not yet fixed — tracked for M3/M3b): `execution = :never`'s cache trust has no
  cryptographic binding to who produced a cache entry. The fingerprint validates only
  publicly-reproducible *inputs*, never the paired rendered `.md` body, so a forged cache
  entry placed into `options.cache_dir` could have arbitrary content published without
  `cell_to_markdown`'s REQ-SEC-05 escaping ever running on it (T6). REQ-SEC-03's "no code
  execution in the privileged job" guarantee is unaffected — a forged entry is a cache hit,
  never an execution. See `build_slates`'s docstring for the full write-up. Refined during
  M3 planning: the realistic attack for the reference workflow is a sibling notebook in
  the same `render-notebooks` job writing directly into `cache_dir`, not (only) an
  external supply chain; partially narrowed by the reference workflow populating the
  cache only from that run's own render job.
- `render-notebooks`/`build-and-deploy` (`.github/workflows/docs.yml`) run behind
  `step-security/harden-runner` in `egress-policy: audit` mode, not yet `block` — an
  initial `block` attempt with a guessed `allowed-endpoints` list was caught by review
  before merging (it would have broken every render run: a dead hostname, and missing the
  actual redirect chain Julia's package client follows). `audit` still provides real
  monitoring value today; upgrading to `block` needs a real run's confirmed endpoint set
  first.
- Recorded, current-backend-specific: `TextualReplayExporter` never reaches KaimonSlate's
  hub/agent (REQ-SEC-01), confirmed by reading `KaimonSlate.jl` source directly and by a
  runtime regression test — but this does not extend to a future `HubExporter`, which
  would reopen the question.

[Unreleased]: https://github.com/s-celles/DocumenterSlate.jl/compare/HEAD
