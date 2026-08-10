# DocumenterSlate.jl

Publishes [KaimonSlate.jl](https://github.com/kahliburke/KaimonSlate.jl) reactive notebooks
as native [Documenter.jl](https://github.com/JuliaDocs/Documenter.jl) pages in CI.

This site is [`DocumenterSlate.jl`](https://github.com/s-celles/DocumenterSlate.jl)'s own
documentation, built by the same two-job workflow the package ships as its reference — the
"Notebooks" section below is real output from real KaimonSlate `.jl` files under
[`docs/notebooks/`](https://github.com/s-celles/DocumenterSlate.jl/tree/main/docs/notebooks),
not a mockup.

See [Security](security.md) for exactly what the CI workflow guarantees and what it does
not — read that before trusting this build model for your own package.

## Quick start

```julia
using Documenter, DocumenterSlate

result = build_slates(
    SlateBuildOptions(; source = joinpath(@__DIR__, "..", "notebooks"),
                       output = joinpath(@__DIR__, "src", "notebooks"),
                       worker_environment = Dict("LANG" => "C.UTF-8")),
)

makedocs(; sitename = "MyPkg.jl", plugins = [SlatePlugin(result)],
         pages = ["Home" => "index.md", "Notebooks" => result.pages])
```

Each cache miss runs in a separate Julia process with the notebook's adjacent project activated.
The parent environment is denied by default; `worker_environment` is the explicit allowlist.

To embed a pre-rendered notebook inside an authored page instead of adding it as a standalone page,
install `SlatePlugin(result)` as above and use:

````markdown
```@slate
notebook = "analysis.jl"
```
````

Use `@slate-download` with the same `notebook = "analysis.jl"` configuration when the authored
page should contain only the download and inactive-inspection panel.

## Public API

```@docs
DocumenterSlate
build_slates
SlateBuildOptions
SlateOutputOptions
discover_notebooks
resolve_notebook_project
NotebookProjectResolution
resolve_notebook_meta
NotebookMeta
AbstractSlateExporter
TextualReplayExporter
execute_notebook
ExecutedNotebook
CellResult
SlateExecutionError
SlateExecutionTimeoutError
cell_to_markdown
extract_assets!
build_pages
SlateBuildResult
SlatePlugin
verify_slate_bundle
SlateBundleVerification
collect_build_statuses
write_github_step_summary
```
