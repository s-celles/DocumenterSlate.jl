"""
    DocumenterSlate

Publishes [KaimonSlate.jl](https://github.com/kahliburke/KaimonSlate.jl) reactive
notebooks as native [Documenter.jl](https://github.com/JuliaDocs/Documenter.jl)
pages in CI.

# Quick start

```julia
using Documenter, DocumenterSlate

result = build_slates(
    SlateBuildOptions(; source = joinpath(@__DIR__, "..", "notebooks"),
                       output = joinpath(@__DIR__, "src", "notebooks")),
)

makedocs(; sitename = "MyPkg.jl",
         pages = ["Home" => "index.md", "Notebooks" => result.pages])
```

[`build_slates`](@ref) is the single public entry point (spec.md §7/§14): it discovers
notebooks ([`discover_notebooks`](@ref)), executes each headlessly via
[`TextualReplayExporter`](@ref) (built on KaimonSlate's own exported `standalone!`
primitive, not the interactive hub — see that type's docstring for why), caches results by
a composite fingerprint of every input that affects them (ADR-004), optionally in parallel
across separate OS processes (`options.nworkers`, REQ-EXE-07), converts cells to Documenter
Markdown ([`cell_to_markdown`](@ref)), extracts figures ([`extract_assets!`](@ref)), and
orders everything into `.pages` ([`build_pages`](@ref)) for `makedocs`.

# Where generated files land

`build_slates` writes one `.md` page and an `assets/<notebook-name>/` subdirectory per
notebook into `options.output`. **Always git-ignore that directory** (REQ-DOC-02): it is
regenerated on every `docs/make.jl` run, never source. Spec.md §6 documents the
`docs/src/notebooks/`-style convention this package's own future example follows.

# Notebook format

Built against the real KaimonSlate `.jl` notebook format (`#%% md id=...` /
`#%% code id=...` cells, `@bind`, role tags like `title`/`hidecode`, an embedded
`Slate.env` dependency footer) as confirmed by reading a local KaimonSlate.jl v1.0.0
checkout during development — not from spec.md's original, partially-guessed examples.
See `upstream-bugs.md` (repository root, not shipped in the package) for what was
confirmed against upstream source versus what is still open with the KaimonSlate
maintainer.

# Public API (M1–M3)

[`SlateBuildOptions`](@ref), [`SlateOutputOptions`](@ref), [`build_slates`](@ref),
[`discover_notebooks`](@ref), [`resolve_notebook_project`](@ref),
[`NotebookProjectResolution`](@ref), [`resolve_notebook_meta`](@ref),
[`NotebookMeta`](@ref), [`AbstractSlateExporter`](@ref),
[`TextualReplayExporter`](@ref), [`execute_notebook`](@ref),
[`ExecutedNotebook`](@ref), [`CellResult`](@ref), [`SlateExecutionError`](@ref),
[`SlateExecutionTimeoutError`](@ref), [`cell_to_markdown`](@ref),
[`extract_assets!`](@ref), [`build_pages`](@ref), [`SlateBuildResult`](@ref),
[`collect_build_statuses`](@ref), [`write_github_step_summary`](@ref).

The composite cache (`options.cache_dir`, `options.execution`) and parallel execution
(`options.nworkers`) internals (`src/cache.jl`) are not exported — they're consumed
through `SlateBuildOptions`/`build_slates`, not called directly.

**Known limitation** (see [`build_slates`](@ref)'s docstring for the full write-up): a
cache entry's fingerprint validates only its *inputs* (notebook bytes, environment, tool
versions, render options), never the paired `.md` body itself — `execution = :never`'s
trust in `options.cache_dir` has no cryptographic binding to who actually produced an
entry. This doesn't weaken REQ-SEC-03 (no code execution in a privileged job), but it does
mean T6 (third-party content published under the repo's identity) isn't mitigated yet.
Tracked for M3/M3b (REQ-TRUST-02/03), not fixed here.

Not yet implemented: the `SlatePlugin <: Documenter.Plugin` / `@slate` expander (N1)
and the `:embed`/`:iframe` output formats (M4) — see spec.md
§14 for the full milestone plan. CI security hardening and the two-job workflow (M3) are
implemented (`.github/workflows/docs.yml`, `docs/src/security.md`); the cache-trust known
limitation above is what's still open from that milestone, not the workflow itself.
Per-notebook environment isolation (REQ-EXE-02 — each notebook running in its own pinned
project rather than the calling process's) is also not implemented despite
[`resolve_notebook_project`](@ref) existing; it's currently consumed only as a cache-key
input.
"""
module DocumenterSlate

import Distributed
import KaimonSlate
import Logging
import TOML

include("options.jl")
include("discovery.jl")
include("notebook_env.jl")
include("frontmatter.jl")
include("exporters.jl")
include("execute.jl")
include("render_markdown.jl")
include("assets.jl")
include("pages.jl")
include("cache.jl")
include("distribution.jl")
include("build.jl")
include("ci_summary.jl")

export SlateBuildOptions, SlateOutputOptions, discover_notebooks,
       resolve_notebook_project, NotebookProjectResolution,
       resolve_notebook_meta, NotebookMeta,
       AbstractSlateExporter, TextualReplayExporter,
       execute_notebook, ExecutedNotebook, CellResult,
       SlateExecutionError, SlateExecutionTimeoutError,
       cell_to_markdown, extract_assets!,
       build_pages, SlateBuildResult,
       build_slates,
       collect_build_statuses, write_github_step_summary

end
