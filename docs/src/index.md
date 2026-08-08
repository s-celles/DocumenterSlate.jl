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
                       output = joinpath(@__DIR__, "src", "notebooks")),
)

makedocs(; sitename = "MyPkg.jl",
         pages = ["Home" => "index.md", "Notebooks" => result.pages])
```

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
collect_build_statuses
write_github_step_summary
```
