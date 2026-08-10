import SHA

# `pkgversion` returns `nothing` for a module not loaded as a real package (e.g. `Main`, or
# certain dev-loaded contexts) — not something the cache key can hash directly. Falls back
# to a fixed sentinel with a loud @warn rather than erroring (a build should still be able
# to proceed, just with a less precise cache key) or silently hashing `"nothing"` (which
# would look like a legitimate, stable version string).
function _fallback_version(m::Module)
    v = pkgversion(m)
    if v === nothing
        @warn "pkgversion(...) returned nothing; using a fixed sentinel in the cache key" m
        return "unknown"
    end
    return string(v)
end

# Package versions alone do not invalidate caches while developing an unreleased
# `0.x.y-DEV` checkout. Mix a deterministic hash of the loaded DocumenterSlate sources into
# its build identity so renderer changes cannot silently reuse stale generated Markdown.
function _documenterslate_build_id()
    source_dir = dirname(something(pathof(@__MODULE__)))
    source_files = sort!(filter(path -> endswith(path, ".jl"), readdir(source_dir; join = true)))
    io = IOBuffer()
    for path in source_files
        write(io, basename(path), '\0', read(path), '\0')
    end
    return _fallback_version(@__MODULE__) * "+" * bytes2hex(SHA.sha256(take!(io)))
end

# Bytes that represent "the pinned environment" for a resolved notebook project (ADR-004,
# revised per upstream-bugs.md §8 Decision A): the real Project.toml (+ Manifest.toml, if
# present) for an `:external` resolution, or the literal embedded Slate.env footer text for
# a `:footer` one. Two different notebooks whose `:footer` entries only differ in package
# version (not just presence) must produce different bytes here — `repr` over the parsed
# `Vector{Dict}` (not just its keys) achieves that without depending on dict iteration order
# being stable (`repr` of a `Dict` isn't order-guaranteed across Julia versions either, but
# within a single process/version it round-trips consistently, which is all a cache key
# needs — it's compared to itself, never parsed back).
function _env_fingerprint_bytes(project::NotebookProjectResolution)
    if project.kind == :external
        # resolve_notebook_project's contract guarantees project_dir is set whenever
        # kind == :external (see its docstring); something(...) narrows the field's
        # declared Union{Nothing,String} type accordingly.
        bytes = read(joinpath(something(project.project_dir), "Project.toml"))
        if project.manifest_path !== nothing && isfile(project.manifest_path)
            bytes = vcat(bytes, read(project.manifest_path))
        end
        return bytes
    else
        return Vector{UInt8}(repr(project.env_footer))
    end
end

# Deterministic string over every render-affecting option (ADR-004's "hash des options de
# rendu", widened beyond the literal `SlateOutputOptions` fields — `meta.show_code`,
# `meta.binds`, and `fail_on_error` all change the actual rendered output exactly like a
# `SlateOutputOptions` field does, per M1.13's `build_slates` docstring precedent of
# combining `output_options.show_code`/`meta.show_code`). `format`/`interactivity`/`assets`
# are included even though only `:documenter`/`:files` are implemented in M1/M2 — the key
# must already be correct once those options become load-bearing, not retrofitted then.
function _render_option_hash(output_options::SlateOutputOptions, meta::NotebookMeta,
                              fail_on_error::Bool,
                              worker_environment::Dict{String,String} = Dict{String,String}())
    environment = join((key * "=" * worker_environment[key]
                        for key in sort!(collect(keys(worker_environment)))), '\0')
    parts = [
        string(output_options.format), string(output_options.interactivity),
        string(output_options.show_code), string(output_options.assets),
        string(meta.show_code), repr(meta.binds), string(fail_on_error), environment,
    ]
    return join(parts, "\x00")
end

"""
    CacheComponents

The raw, individually-inspectable inputs to a notebook's composite cache fingerprint
(ADR-004). Written verbatim into each `*.cache.toml` (REQ-CACHE-03: "empreinte et ses
composantes") so a stale/mismatched cache entry is diagnosable without recomputing
anything.

# Fields
- `notebook_sha::String`: hex SHA-256 of the notebook file's raw bytes.
- `env_fingerprint::String`: hex SHA-256 of `_env_fingerprint_bytes`'s output —
  the resolved project's `Project.toml`(+`Manifest.toml`) bytes, or the notebook's embedded
  `Slate.env` footer text.
- `julia_version::String`: `string(VERSION)`.
- `kaimonslate_version::String`: `string(pkgversion(...))`, or `"unknown"` if unavailable.
- `documenterslate_version::String`: package version plus a SHA-256 of the loaded package
  sources, preventing stale cache hits across code changes made under the same development
  version.
- `render_option_hash::String`: see `_render_option_hash`.
"""
struct CacheComponents
    notebook_sha::String
    env_fingerprint::String
    julia_version::String
    kaimonslate_version::String
    documenterslate_version::String
    render_option_hash::String
end

"""
    _gather_cache_components(path, project::NotebookProjectResolution,
                              output_options::SlateOutputOptions, meta::NotebookMeta,
                              fail_on_error::Bool) -> CacheComponents

Reads/computes every raw input to a notebook's cache key (ADR-004): the notebook's own
bytes, its resolved environment's fingerprint, the running Julia/KaimonSlate/
DocumenterSlate versions, and a hash of the render-affecting options. Impure (reads files,
`VERSION`, `pkgversion`) by design — kept separate from the pure `_cache_fingerprint`
so the latter is trivially testable without touching the filesystem.
"""
function _gather_cache_components(path::AbstractString, project::NotebookProjectResolution,
                                   output_options::SlateOutputOptions, meta::NotebookMeta,
                                   fail_on_error::Bool,
                                   worker_environment::Dict{String,String} = Dict{String,String}())
    notebook_sha = bytes2hex(SHA.sha256(read(path)))
    env_fingerprint = bytes2hex(SHA.sha256(_env_fingerprint_bytes(project)))
    return CacheComponents(
        notebook_sha, env_fingerprint, string(VERSION),
        _fallback_version(KaimonSlate), _documenterslate_build_id(),
        _render_option_hash(output_options, meta, fail_on_error, worker_environment),
    )
end

"""
    _cache_fingerprint(c::CacheComponents) -> String

Pure hex-SHA-256 composite of every field of `c`, joined in field-declaration order with a
NUL separator (so e.g. `("ab", "c")` and `("a", "bc")` never collide). This is the actual
cache-key comparison value (REQ-CACHE-01/02): two [`CacheComponents`](@ref) with the same
fingerprint are treated as producing identical output.
"""
function _cache_fingerprint(c::CacheComponents)
    combined = join(
        (c.notebook_sha, c.env_fingerprint, c.julia_version, c.kaimonslate_version,
         c.documenterslate_version, c.render_option_hash),
        "\x00",
    )
    return bytes2hex(SHA.sha256(combined))
end

function _cache_tree_hash(directory::AbstractString)
    isdir(directory) || return bytes2hex(SHA.sha256(UInt8[]))
    paths = String[]
    for (root, _, files) in walkdir(directory), name in files
        push!(paths, relpath(joinpath(root, name), directory))
    end
    io = IOBuffer()
    for relative in sort!(paths)
        write(io, replace(relative, '\\' => '/'), '\0')
        write(io, read(joinpath(directory, relative)), '\0')
    end
    return bytes2hex(SHA.sha256(take!(io)))
end

"""
    _write_cache_entry!(cache_dir, slug, fingerprint, components::CacheComponents,
                         page_text, assets_dir) -> Nothing

Writes one notebook's rendered result into the on-disk cache (REQ-CACHE-01, spec §6's
`slate_cache/` layout): `<cache_dir>/<slug>.md` (the rendered page text),
`<cache_dir>/assets/<slug>/` (copied from `assets_dir`, if given and non-empty — no-op
otherwise, matching `cell_to_markdown`'s existing "no asset, no entry" convention), and
`<cache_dir>/<slug>.cache.toml` (the fingerprint plus every raw [`CacheComponents`](@ref)
field, REQ-CACHE-03: "empreinte et ses composantes", human-diffable to see exactly *why* a
later build considers this entry stale).
"""
function _write_cache_entry!(cache_dir::AbstractString, slug::AbstractString,
                              fingerprint::AbstractString, components::CacheComponents,
                              page_text::AbstractString, assets_dir::Union{Nothing,AbstractString},
                              environment_dir::Union{Nothing,AbstractString} = nothing)
    isdir(cache_dir) || mkpath(cache_dir)
    write(joinpath(cache_dir, slug * ".md"), page_text)

    cache_assets_dir = joinpath(cache_dir, "assets", slug)
    isdir(cache_assets_dir) && rm(cache_assets_dir; recursive = true)
    if assets_dir !== nothing && isdir(assets_dir) && !isempty(readdir(assets_dir))
        mkpath(dirname(cache_assets_dir))
        cp(assets_dir, cache_assets_dir)
    end

    cache_environment_dir = joinpath(cache_dir, "environments", slug)
    isdir(cache_environment_dir) && rm(cache_environment_dir; recursive = true)
    if environment_dir !== nothing && isdir(environment_dir)
        mkpath(cache_environment_dir)
        for name in ("Project.toml", "Manifest.toml")
            source = joinpath(environment_dir, name)
            isfile(source) && cp(source, joinpath(cache_environment_dir, name))
        end
    end

    open(joinpath(cache_dir, slug * ".cache.toml"), "w") do io
        TOML.print(io, Dict(
            "fingerprint" => String(fingerprint),
            "notebook_sha" => components.notebook_sha,
            "env_fingerprint" => components.env_fingerprint,
            "julia_version" => components.julia_version,
            "kaimonslate_version" => components.kaimonslate_version,
            "documenterslate_version" => components.documenterslate_version,
            "render_option_hash" => components.render_option_hash,
            "rendered_sha256" => bytes2hex(SHA.sha256(String(page_text))),
            "assets_sha256" => _cache_tree_hash(cache_assets_dir),
            "environment_sha256" => _cache_tree_hash(cache_environment_dir),
        ))
    end
    return nothing
end

"""
    _read_cache_entry(cache_dir, slug, fingerprint) -> Union{Nothing,NamedTuple}

Returns `(page_text, assets_dir)` (`assets_dir` is `nothing` if the notebook produced no
assets) when a valid cache entry for `slug` exists under `cache_dir` **and** its recorded
`fingerprint` matches, else `nothing`. A cache miss must always be a safe, silent signal to
re-execute (REQ-CACHE-01/02) — this function never throws, whether the entry is simply
absent, its `.cache.toml` is corrupt/unparseable, or its fingerprint is stale; all three
collapse to the same `nothing` result. `cache_dir` may be any directory (REQ-CACHE-04: a
restored CI artifact, a previous `gh-pages` checkout, …), not necessarily one this process
itself wrote to.
"""
function _read_cache_entry(cache_dir::AbstractString, slug::AbstractString,
                            fingerprint::AbstractString)
    meta_path = joinpath(cache_dir, slug * ".cache.toml")
    md_path = joinpath(cache_dir, slug * ".md")
    (isfile(meta_path) && isfile(md_path)) || return nothing

    meta = try
        TOML.parsefile(meta_path)
    catch
        return nothing
    end
    get(meta, "fingerprint", nothing) == fingerprint || return nothing

    page_text = try
        read(md_path, String)
    catch
        return nothing
    end
    get(meta, "rendered_sha256", nothing) == bytes2hex(SHA.sha256(page_text)) || return nothing

    assets_dir = joinpath(cache_dir, "assets", slug)
    environment_dir = joinpath(cache_dir, "environments", slug)
    get(meta, "assets_sha256", nothing) == _cache_tree_hash(assets_dir) || return nothing
    get(meta, "environment_sha256", nothing) == _cache_tree_hash(environment_dir) || return nothing
    cached_environment = isfile(joinpath(environment_dir, "Project.toml")) &&
                         isfile(joinpath(environment_dir, "Manifest.toml")) ?
                         environment_dir : nothing
    return (page_text = page_text, assets_dir = isdir(assets_dir) ? assets_dir : nothing,
            environment_dir = cached_environment)
end
