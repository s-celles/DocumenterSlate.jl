"""
    DocumenterSlate

Publishes [KaimonSlate.jl](https://github.com/kahliburke/KaimonSlate.jl) reactive
notebooks as native [Documenter.jl](https://github.com/JuliaDocs/Documenter.jl)
pages in CI.

Currently exposes [`SlateBuildOptions`](@ref), [`SlateOutputOptions`](@ref),
[`discover_notebooks`](@ref), [`resolve_notebook_project`](@ref),
[`NotebookProjectResolution`](@ref), [`resolve_notebook_meta`](@ref),
[`NotebookMeta`](@ref), [`AbstractSlateExporter`](@ref),
[`TextualReplayExporter`](@ref), [`execute_notebook`](@ref),
[`ExecutedNotebook`](@ref), [`CellResult`](@ref), [`SlateExecutionError`](@ref) and
[`SlateExecutionTimeoutError`](@ref); the `build_slates` orchestration entry point is not
implemented yet.
"""
module DocumenterSlate

import KaimonSlate
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

export SlateBuildOptions, SlateOutputOptions, discover_notebooks,
       resolve_notebook_project, NotebookProjectResolution,
       resolve_notebook_meta, NotebookMeta,
       AbstractSlateExporter, TextualReplayExporter,
       execute_notebook, ExecutedNotebook, CellResult,
       SlateExecutionError, SlateExecutionTimeoutError,
       cell_to_markdown, extract_assets!,
       build_pages, SlateBuildResult

end
