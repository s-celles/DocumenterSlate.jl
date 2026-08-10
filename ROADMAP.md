# Roadmap

This file is the current implementation roadmap. The original design requirements and milestone
definitions remain in `spec.md`; when their historical status text conflicts with this file, this
file describes the repository as it exists today.

DocumenterSlate remains in the `0.x.y` development series. No `1.0.0` release is planned until the
remaining trust boundary and embedded-rendering work is complete.

## Completed

- **M1 / N0:** notebook discovery, isolated execution, native Documenter Markdown, assets, page
  ordering, unique anchors, and error handling.
- **M2:** composite cache, process-based parallelism, cache-only builds, timeouts, and CI summaries.
- **M3:** two-job GitHub Actions documentation workflow, secret-free notebook execution,
  deny-by-default worker environments, and published security documentation.
- **M3b core:** intact sources, resolved Project/Manifest environments, reproducible archives,
  checksums, provenance metadata, safe download/inspection actions, bundle verification, and local
  execution guidance.

## Next priorities

1. **Harden the cache producer boundary.** Cache payload hashes and run-scoped GitHub artifacts
   detect corruption and bind transport to a workflow run, but a notebook process still shares the
   render job's filesystem identity. Add an OS sandbox boundary before claiming protection against
   a malicious notebook deliberately rewriting another cache entry.
2. **Complete M4 Documenter integration.** Implement `SlatePlugin`, `@slate`, and
   `@slate-download` without relying on unstable Documenter internals where a public extension
   point is available. `SlatePlugin` itself is complete; the two expanders remain.
3. **Embedded outputs.** Implement self-contained HTML export and `format = :iframe`; add PDF and
   KaimonSlate bundle downloads when the upstream export contract is stable.
4. **Finish configurable output controls.** Make `provenance`, `downloads`, `interactivity`, and
   `assets = :base64` effective rather than accepted-but-inert options.
5. **Expand the end-to-end example.** Cover a table, CairoMakie output, and ECharts output, and add
   a generated `Dockerfile` or `devcontainer.json` to every runnable bundle.
6. **Network enforcement.** Move harden-runner from audit to a tested allowlisted blocking policy.
7. **Optional follow-ups.** Add `check_slates()`, `@slate-index`, GitLab CI, PURL dependency
   inventories, third-party author indicators, and Codespaces links.

## Release policy

Continue making backward-compatible `0.x.y` releases. A release is intentionally out of scope for
the current work; completing a milestone does not automatically publish or tag a version.
