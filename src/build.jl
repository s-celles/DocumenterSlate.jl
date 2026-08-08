# Copies a cache hit's page text + assets (if any) into the real output directory. Shared
# by every `execution` mode that can be satisfied by a cache hit (`:auto`, `:never`).
function _write_output_from_cache(output_dir::AbstractString, slug::AbstractString, cached)
    isdir(output_dir) || mkpath(output_dir)
    write(joinpath(output_dir, slug * ".md"), cached.page_text)
    if cached.assets_dir !== nothing
        dest = joinpath(output_dir, "assets", slug)
        isdir(dest) && rm(dest; recursive = true)
        mkpath(dirname(dest))
        cp(cached.assets_dir, dest)
    end
    return nothing
end

# One notebook's full pipeline: cache lookup (unless `:always`) -> execute on a miss ->
# render -> write to `options.output` -> refresh the cache. Factored out of `build_slates`'s
# loop body so M2.5's parallel path can call it identically per-worker.
function _build_one_notebook(path::AbstractString, meta::NotebookMeta, exporter,
                              options::SlateBuildOptions, output_options::SlateOutputOptions)
    slug = splitext(basename(path))[1]
    project = resolve_notebook_project(path)
    components = _gather_cache_components(path, project, output_options, meta,
                                           options.fail_on_error)
    fingerprint = _cache_fingerprint(components)

    cached = options.execution == :always ? nothing :
             _read_cache_entry(options.cache_dir, slug, fingerprint)

    if cached !== nothing
        _write_output_from_cache(options.output, slug, cached)
        return nothing
    end

    if options.execution == :never
        throw(ArgumentError(
            "execution = :never requires a cache hit for notebook \"$path\" (slug " *
            "\"$slug\"), but none was found under cache_dir=\"$(options.cache_dir)\" " *
            "matching the current fingerprint ($fingerprint); populate the cache with a " *
            "prior :auto or :always build before using :never (REQ-EXE-10)",
        ))
    end

    executed = execute_notebook(exporter, path;
                                 fail_on_error = options.fail_on_error, binds = meta.binds)

    assets_out_dir = joinpath(options.output, "assets", slug)
    assets_by_cell = if output_options.assets == :files
        extract_assets!(executed, assets_out_dir)
    else
        Dict{String,String}()
    end

    show_code = output_options.show_code && meta.show_code
    rendered = map(executed.cells) do cell
        asset_file = get(assets_by_cell, cell.cell_id, nothing)
        asset_path = asset_file === nothing ? nothing :
                     joinpath("assets", slug, asset_file)
        cell_to_markdown(cell; show_code = show_code, anchor_prefix = slug,
                          asset_path = asset_path)
    end
    page_text = join(rendered, "\n\n")
    write(joinpath(options.output, slug * ".md"), page_text)

    # Refresh the cache on every non-cache-hit build (`:auto` miss, or `:always`) so a
    # *following* `:auto`/`:never` build benefits (REQ-CACHE-01's "réutiliser" invariant
    # holds for the next build, not just this one).
    _write_cache_entry!(options.cache_dir, slug, fingerprint, components, page_text,
                         isdir(assets_out_dir) ? assets_out_dir : nothing)

    return nothing
end

"""
    build_slates(options::SlateBuildOptions,
                 output_options::SlateOutputOptions = SlateOutputOptions()) -> SlateBuildResult

Discover, execute, and render every notebook under `options.source` into Documenter-native
Markdown pages under `options.output` (spec §7 — the N0 tier's orchestration entry point,
tying together REQ-EXE-01/02/03/04/06/09/10, REQ-REN-01/02/03/05/06/09/10, REQ-CACHE-01/02,
REQ-INT-02).

# Pipeline
1. [`discover_notebooks`](@ref)`(options)`.
2. For each discovered path, [`resolve_notebook_meta`](@ref)`(path, options.slate_toml)`
   (front-matter, `docs/slate.toml` overrides).
3. For every non-`skip` notebook, [`_build_one_notebook`](@ref): resolve the notebook's
   pinned environment ([`resolve_notebook_project`](@ref)) and composite cache fingerprint
   (ADR-004), then:
   - **`execution = :auto`** (default): a cache hit copies straight from `options.cache_dir`
     (REQ-CACHE-01); a miss executes and refreshes the cache.
   - **`execution = :always`**: always executes (via `options.exporter`, defaulting to a
     fresh [`TextualReplayExporter`](@ref)), still refreshing the cache for a later build.
   - **`execution = :never`** (REQ-EXE-10, hermetic build): a cache hit copies from
     `options.cache_dir`; a miss raises `ArgumentError` rather than executing anything —
     this is the mode the privileged deploy job in spec §9's reference workflow runs under.
   A hit/miss/execute always passes `options.fail_on_error` and the notebook's resolved
   `binds` into [`execute_notebook`](@ref), extracts assets via [`extract_assets!`](@ref)
   when `output_options.assets == :files` (`:base64`, REQ-REN-04, is Could and not
   implemented), and renders cells via [`cell_to_markdown`](@ref) (anchor-prefixed by the
   notebook's slug, REQ-REN-09).
4. [`build_pages`](@ref) over every discovered `(path, meta)` pair (including `skip`
   entries, which it filters) to produce the ordered `.pages`.

# Effective `show_code`
A cell's source is shown only when **both** `output_options.show_code` (the site-wide
default) and the notebook's own resolved `meta.show_code` (REQ-REN-05, from
`docs/slate.toml`, defaulting to `true`) are `true` — either one being `false` hides it.
`meta.show_code`'s per-notebook resolution (M1.7) doesn't currently distinguish "explicitly
set to `true` in `docs/slate.toml`" from "left at its own default", so this AND-combination
is the simplest sound reading and is called out here as a judgment call rather than a
directly cited requirement. This also feeds the cache key (ADR-004's "hash des options de
rendu", widened — see `cache.jl`'s `_render_option_hash`), so a `show_code` change
correctly invalidates a stale cache entry rather than silently reusing mismatched output.

# Scope not yet implemented (raises `ArgumentError` rather than silently mis-behaving)
- `output_options.format != :documenter` (`:embed`/`:iframe`, REQ-REN-11) — N2 tier, M4.
- `options.nworkers > 1` (REQ-EXE-07, parallel execution) — M2.5; this does not error, only
  `@warn`s and runs sequentially, since running slower-than-requested is not incorrect the
  way a silently-ignored `:iframe` request would be.

Provenance footers (REQ-REN-07) and download links (REQ-REN-08) are Should-priority and
not produced by this milestone either, despite `output_options.provenance`/`.downloads`
existing as fields already (M1.4) — they are inert. REQ-CACHE-05's `check_slates()`
non-determinism detector is explicitly deferred past M2 (it needs a second execution to
diff against the cache, which is exactly the cost `:auto`/`:never` exist to avoid).

**Not fixed by this milestone**: REQ-EXE-02 ("exécuter chaque notebook dans son propre
projet Julia épinglé... sans polluer l'environnement `docs/`") is still not implemented —
[`resolve_notebook_project`](@ref)'s result is consumed here only as a cache-key input, not
to actually `Pkg.activate` a notebook's own environment before executing it. Every notebook
still runs inside the calling process's active project. Tracked as a follow-up, not silently
assumed fixed just because `resolve_notebook_project` is finally wired in.
"""
function build_slates(options::SlateBuildOptions,
                       output_options::SlateOutputOptions = SlateOutputOptions())
    output_options.format == :documenter || throw(ArgumentError(
        "SlateOutputOptions.format = :$(output_options.format) is not implemented until " *
        "a later milestone (REQ-REN-11, N2 tier); only :documenter is supported",
    ))
    if options.nworkers > 1
        @warn "nworkers > 1 requested but parallel execution (REQ-EXE-07) is not " *
              "implemented until M2.5; building sequentially" options.nworkers
    end

    exporter = options.exporter === nothing ? TextualReplayExporter() : options.exporter

    notebook_paths = discover_notebooks(options)
    entries = [(path, resolve_notebook_meta(path, options.slate_toml)) for path in notebook_paths]

    isdir(options.output) || mkpath(options.output)

    for (path, meta) in entries
        meta.skip && continue
        _build_one_notebook(path, meta, exporter, options, output_options)
    end

    return build_pages(entries)
end
