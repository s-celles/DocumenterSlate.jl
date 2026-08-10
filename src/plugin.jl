"""
    SlatePlugin([slates])

Documenter plugin state for notebook pages produced by [`build_slates`](@ref). Pass an instance to
`makedocs(; plugins = [SlatePlugin(slates)])`. The zero-argument constructor supports Documenter's
`getplugin` fallback and represents a build for which no slate result was supplied.
"""
struct SlatePlugin <: Documenter.Plugin
    slates::Union{Nothing,SlateBuildResult}
end

SlatePlugin() = SlatePlugin(nothing)
