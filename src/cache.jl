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
        bytes = read(joinpath(project.project_dir, "Project.toml"))
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
                              fail_on_error::Bool)
    parts = [
        string(output_options.format), string(output_options.interactivity),
        string(output_options.show_code), string(output_options.assets),
        string(meta.show_code), repr(meta.binds), string(fail_on_error),
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
- `env_fingerprint::String`: hex SHA-256 of [`_env_fingerprint_bytes`](@ref)'s output —
  the resolved project's `Project.toml`(+`Manifest.toml`) bytes, or the notebook's embedded
  `Slate.env` footer text.
- `julia_version::String`: `string(VERSION)`.
- `kaimonslate_version::String`, `documenterslate_version::String`: `string(pkgversion(...))`,
  or `"unknown"` if unavailable (see [`_fallback_version`](@ref)).
- `render_option_hash::String`: see [`_render_option_hash`](@ref).
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
`VERSION`, `pkgversion`) by design — kept separate from the pure [`_cache_fingerprint`](@ref)
so the latter is trivially testable without touching the filesystem.
"""
function _gather_cache_components(path::AbstractString, project::NotebookProjectResolution,
                                   output_options::SlateOutputOptions, meta::NotebookMeta,
                                   fail_on_error::Bool)
    notebook_sha = bytes2hex(SHA.sha256(read(path)))
    env_fingerprint = bytes2hex(SHA.sha256(_env_fingerprint_bytes(project)))
    return CacheComponents(
        notebook_sha, env_fingerprint, string(VERSION),
        _fallback_version(KaimonSlate), _fallback_version(@__MODULE__),
        _render_option_hash(output_options, meta, fail_on_error),
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
