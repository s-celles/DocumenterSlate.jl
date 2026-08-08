# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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

### Fixed

- Serialized per-cell stdout capture to prevent a notebook execution that outlives its
  configured `timeout` from corrupting output capture for unrelated, concurrently-running
  executions in the same process.
- Several tests didn't set an explicit `cache_dir`, so once the cache became load-bearing
  they started writing a live `slate_cache/` directory into the real repository (relative
  to the test process's working directory) instead of staying inside their own temp
  directory.

### Security

- Recorded (not yet fixed — tracked for M3/M3b): `execution = :never`'s cache trust has no
  cryptographic binding to who produced a cache entry. The fingerprint validates only
  publicly-reproducible *inputs*, never the paired rendered `.md` body, so a forged cache
  entry placed into `options.cache_dir` could have arbitrary content published without
  `cell_to_markdown`'s REQ-SEC-05 escaping ever running on it (T6). REQ-SEC-03's "no code
  execution in the privileged job" guarantee is unaffected — a forged entry is a cache hit,
  never an execution. See `build_slates`'s docstring for the full write-up.

[Unreleased]: https://github.com/s-celles/DocumenterSlate.jl/compare/HEAD
