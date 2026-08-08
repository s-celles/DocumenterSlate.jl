"""
    DocumenterSlate

Publishes [KaimonSlate.jl](https://github.com/kahliburke/KaimonSlate.jl) reactive
notebooks as native [Documenter.jl](https://github.com/JuliaDocs/Documenter.jl)
pages in CI.

Currently exposes [`SlateBuildOptions`](@ref) and [`SlateOutputOptions`](@ref); the
`build_slates` orchestration entry point is not implemented yet.
"""
module DocumenterSlate

include("options.jl")

export SlateBuildOptions, SlateOutputOptions

end
