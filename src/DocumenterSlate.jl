"""
    DocumenterSlate

Publishes [KaimonSlate.jl](https://github.com/kahliburke/KaimonSlate.jl) reactive
notebooks as native [Documenter.jl](https://github.com/JuliaDocs/Documenter.jl)
pages in CI.

Currently exposes [`SlateBuildOptions`](@ref), [`SlateOutputOptions`](@ref),
[`discover_notebooks`](@ref), [`resolve_notebook_project`](@ref),
[`NotebookProjectResolution`](@ref), [`resolve_notebook_meta`](@ref) and
[`NotebookMeta`](@ref); the `build_slates` orchestration entry point is not
implemented yet.
"""
module DocumenterSlate

import KaimonSlate
import TOML

include("options.jl")
include("discovery.jl")
include("notebook_env.jl")
include("frontmatter.jl")

export SlateBuildOptions, SlateOutputOptions, discover_notebooks,
       resolve_notebook_project, NotebookProjectResolution,
       resolve_notebook_meta, NotebookMeta

end
