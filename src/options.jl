"""
    SlateBuildOptions(; source, output, kwargs...)

Options controlling notebook discovery, execution and caching for [`build_slates`](@ref)
(spec §7, REQ-EXE-*, REQ-CACHE-*).

`source` and `output` are required keyword arguments: there is no sensible default source
or destination directory for a given documentation build, so omitting either is an error.

# Keywords
- `source::AbstractString`: directory containing the KaimonSlate notebooks (required).
- `output::AbstractString`: directory the generated Markdown pages are written to (required).
- `include::Vector{String} = ["*.jl"]`: glob patterns selecting notebooks under `source`.
- `exclude::Vector{String} = ["_*.jl"]`: glob patterns excluding notebooks under `source`.
- `exporter = nothing`: execution backend (`TextualReplayExporter()` by default). During
  `build_slates`, textual replay runs in a dedicated child process.
- `execution::Symbol = :auto`: one of `:auto`, `:always`, `:never`.
- `cache_dir::AbstractString = "slate_cache"`: directory holding the build cache.
- `nworkers::Integer = 1`: number of notebooks executed in parallel.
- `fail_on_error::Bool = true`: whether a cell exception aborts the build (REQ-EXE-04/05).
- `allow_remote::Bool = false`: whether notebooks containing `region=<name>` cell tags may
  be built. The default refusal requires an explicit opt-in (REQ-EXE-09).
- `worker_environment::Dict{String,String} = Dict()`: explicit environment variables passed
  to the isolated notebook process. The parent process environment is not inherited.
- `slate_toml::Union{Nothing,AbstractString} = nothing`: path to a `docs/slate.toml`-shaped
  declarative config (spec §10) providing per-notebook `order`/`skip`/`show_code`/`binds`
  overrides to [`resolve_notebook_meta`](@ref). Added in M1.13 (not part of spec §7's
  original sketch, which didn't say how `build_slates` would locate it) — no
  auto-discovery, must be given explicitly if wanted.
"""
struct SlateBuildOptions
    source::String
    output::String
    include::Vector{String}
    exclude::Vector{String}
    exporter::Any
    execution::Symbol
    cache_dir::String
    nworkers::Int
    fail_on_error::Bool
    allow_remote::Bool
    worker_environment::Dict{String,String}
    slate_toml::Union{Nothing,String}

    function SlateBuildOptions(
        source::AbstractString,
        output::AbstractString,
        include::AbstractVector,
        exclude::AbstractVector,
        exporter,
        execution::Symbol,
        cache_dir::AbstractString,
        nworkers::Integer,
        fail_on_error::Bool,
        allow_remote::Bool,
        worker_environment::Dict{String,String},
        slate_toml::Union{Nothing,AbstractString},
    )
        execution in (:auto, :always, :never) || throw(ArgumentError(
            "`execution` must be one of `:auto`, `:always`, `:never`; got `:$execution`",
        ))
        return new(
            String(source), String(output), collect(String, include), collect(String, exclude),
            exporter, execution, String(cache_dir), Int(nworkers), fail_on_error,
            allow_remote, copy(worker_environment),
            slate_toml === nothing ? nothing : String(slate_toml),
        )
    end
end

function SlateBuildOptions(;
    source,
    output,
    include = ["*.jl"],
    exclude = ["_*.jl"],
    exporter = nothing,
    execution::Symbol = :auto,
    cache_dir = "slate_cache",
    nworkers::Integer = 1,
    fail_on_error::Bool = true,
    allow_remote::Bool = false,
    worker_environment::Dict{String,String} = Dict{String,String}(),
    slate_toml::Union{Nothing,AbstractString} = nothing,
)
    return SlateBuildOptions(
        source, output, include, exclude, exporter, execution, cache_dir, nworkers,
        fail_on_error, allow_remote, worker_environment, slate_toml,
    )
end

"""
    SlateOutputOptions(; kwargs...)

Options controlling how rendered notebooks are formatted (spec §7, REQ-REN-*, ADR-005).

# Keywords
- `format::Symbol = :documenter`: one of `:documenter`, `:embed`, `:iframe`.
- `interactivity::Symbol = :frozen`: one of `:frozen`, `:client` (ADR-005 default is `:frozen`).
- `show_code::Bool = true`: whether cell source is rendered alongside outputs.
- `assets::Symbol = :files`: one of `:files`, `:base64`.
- `provenance::Bool = true`: whether a provenance footer is added (REQ-REN-07).
- `downloads::Vector{Symbol} = [:html, :pdf, :source]`: download links shown on the page.
"""
struct SlateOutputOptions
    format::Symbol
    interactivity::Symbol
    show_code::Bool
    assets::Symbol
    provenance::Bool
    downloads::Vector{Symbol}

    function SlateOutputOptions(
        format::Symbol,
        interactivity::Symbol,
        show_code::Bool,
        assets::Symbol,
        provenance::Bool,
        downloads::AbstractVector,
    )
        format in (:documenter, :embed, :iframe) || throw(ArgumentError(
            "`format` must be one of `:documenter`, `:embed`, `:iframe`; got `:$format`",
        ))
        interactivity in (:frozen, :client) || throw(ArgumentError(
            "`interactivity` must be one of `:frozen`, `:client`; got `:$interactivity`",
        ))
        assets in (:files, :base64) || throw(ArgumentError(
            "`assets` must be one of `:files`, `:base64`; got `:$assets`",
        ))
        return new(format, interactivity, show_code, assets, provenance, collect(Symbol, downloads))
    end
end

function SlateOutputOptions(;
    format::Symbol = :documenter,
    interactivity::Symbol = :frozen,
    show_code::Bool = true,
    assets::Symbol = :files,
    provenance::Bool = true,
    downloads = [:html, :pdf, :source],
)
    return SlateOutputOptions(format, interactivity, show_code, assets, provenance, downloads)
end
