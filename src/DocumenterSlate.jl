"""
    DocumenterSlate

Publishes [KaimonSlate.jl](https://github.com/kahliburke/KaimonSlate.jl) reactive
notebooks as native [Documenter.jl](https://github.com/JuliaDocs/Documenter.jl)
pages in CI.

Currently exposes [`SlateBuildOptions`](@ref), [`SlateOutputOptions`](@ref),
[`discover_notebooks`](@ref), [`resolve_notebook_project`](@ref) and
[`NotebookProjectResolution`](@ref); the `build_slates` orchestration entry point is
not implemented yet.
"""
module DocumenterSlate

import KaimonSlate

include("options.jl")
include("discovery.jl")
include("notebook_env.jl")

export SlateBuildOptions, SlateOutputOptions, discover_notebooks,
       resolve_notebook_project, NotebookProjectResolution

end
