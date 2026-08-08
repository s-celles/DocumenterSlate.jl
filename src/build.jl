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

# `Distributed.pmap`'s worker function must never let an exception escape uncaught: pmap
# wraps an escaping exception in `RemoteException`/`CompositeException`, which would change
# `SlateExecutionError`/`SlateExecutionTimeoutError`'s type as seen by the caller (breaking
# the `err isa DocumenterSlate.SlateExecutionError` contract the sequential path already
# guarantees). Catching here and returning the exception as an ordinary value instead
# sidesteps that entirely: `pmap` sees a normal (non-throwing) result either way, and
# `_build_parallel!` re-throws the *original* typed exception itself once every worker has
# finished, after `finally`-guaranteed `rmprocs` cleanup has already run.
function _build_one_notebook_safe(path::AbstractString, meta::NotebookMeta, exporter,
                                   options::SlateBuildOptions, output_options::SlateOutputOptions)
    try
        _build_one_notebook(path, meta, exporter, options, output_options)
        return nothing
    catch e
        return e
    end
end

"""
    _build_parallel!(to_build, exporter, options::SlateBuildOptions,
                      output_options::SlateOutputOptions) -> Nothing

Runs [`_build_one_notebook`](@ref) for every `(path, meta)` in `to_build` across
`min(options.nworkers, length(to_build))` genuinely separate OS processes (REQ-EXE-07),
each spawned with the *same* active project as the caller so `using DocumenterSlate`
succeeds on every worker.

# Why separate processes, not threads
`Threads.@spawn`-based fan-out was considered and rejected: `src/execute.jl`'s stdout
capture (`_STDOUT_CAPTURE_LOCK`) exists precisely because `redirect_stdout`/`stdout` is
process-wide mutable state in Julia, not task-local — any threaded approach would either
corrupt output across concurrently-running notebooks (the M1.9→M1.17 bug this lock fixed)
or, if the lock is kept, simply serialize the one part of the work that most needs to
parallelize (every output-producing cell), defeating the purpose. Separate OS processes
each have their own `stdout`, eliminating the constraint rather than working around it.

# What does NOT get fixed by this
Workers inherit the calling process's active project (`Base.active_project()`) — this
implements REQ-EXE-07 (parallelism), it does **not** implement REQ-EXE-02 (each notebook
executing in its own pinned project). That gap is pre-existing (see [`build_slates`](@ref)'s
docstring) and unaffected by parallelizing the still-shared-project execution.

# Process lifecycle and error propagation
`Distributed.addprocs`/`Distributed.rmprocs` are paired in a `try`/`finally` — workers are
always torn down, even when a notebook build throws, to avoid leaking OS processes.
[`_build_one_notebook_safe`](@ref) catches every exception on the worker and returns it as
an ordinary value; after `pmap` completes (and workers are torn down), the first caught
exception, if any, is re-thrown here with its original type intact — `fail_on_error = true`
still raises a directly-catchable `SlateExecutionError`/`SlateExecutionTimeoutError`, not a
`Distributed.RemoteException` wrapper, exactly as the `nworkers = 1` sequential path does.
Because all workers run concurrently, a failure is *reported* once every dispatched notebook
has finished, not the instant it occurs — parallel execution cannot offer the sequential
path's "stop at the very next cell" immediacy (REQ-EXE-04's diagnostic clarity is preserved;
its stop-fast *timing* is necessarily relaxed under parallelism).

`pmap` preserves `to_build`'s input order in its result vector regardless of which worker
finished first or in what order, so nothing here disturbs [`build_pages`](@ref)'s ordering
guarantee — this function only executes/renders/caches; page ordering is computed
separately, after every worker's result (or exception) is back.
"""
function _build_parallel!(to_build, exporter, options::SlateBuildOptions,
                           output_options::SlateOutputOptions)
    n = min(options.nworkers, length(to_build))
    active_project = Base.active_project()
    worker_ids = Distributed.addprocs(n; exeflags = `--project=$(active_project)`)
    try
        # Distributed.@everywhere expands to a top-level `:toplevel` Expr, which is a
        # syntax error nested inside this function body — remotecall_eval is the same
        # underlying mechanism the macro itself calls, usable from ordinary code.
        Distributed.remotecall_eval(Main, worker_ids, :(using DocumenterSlate))
        pool = Distributed.WorkerPool(worker_ids)
        results = Distributed.pmap(pool, to_build) do entry
            path, meta = entry
            _build_one_notebook_safe(path, meta, exporter, options, output_options)
        end
        for r in results
            r isa Exception && throw(r)
        end
    finally
        Distributed.rmprocs(worker_ids)
    end
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

# `nworkers > 1` (REQ-EXE-07)
Notebooks are built across `min(options.nworkers, <number to build>)` separate OS
processes via [`_build_parallel!`](@ref) — not threads; see that function's docstring for
why (`src/execute.jl`'s stdout-capture lock makes threaded fan-out either corrupt output or
fully serialize, not actually parallelize). Falls back to the plain sequential loop when
`nworkers <= 1` or there is at most one notebook to build (not worth process-spawn
overhead). Each dispatched notebook still does its own cache lookup independently (on
whichever worker it lands on) — a hit is cheap disk I/O, not worth special-casing out of
the worker pool. `pmap`'s result order matches input order regardless of completion order,
so worker scheduling never disturbs [`build_pages`](@ref)'s ordering.

# Scope not yet implemented (raises `ArgumentError` rather than silently mis-behaving)
- `output_options.format != :documenter` (`:embed`/`:iframe`, REQ-REN-11) — N2 tier, M4.

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

    exporter = options.exporter === nothing ? TextualReplayExporter() : options.exporter

    notebook_paths = discover_notebooks(options)
    entries = [(path, resolve_notebook_meta(path, options.slate_toml)) for path in notebook_paths]

    isdir(options.output) || mkpath(options.output)

    to_build = [(path, meta) for (path, meta) in entries if !meta.skip]
    if options.nworkers > 1 && length(to_build) > 1
        _build_parallel!(to_build, exporter, options, output_options)
    else
        for (path, meta) in to_build
            _build_one_notebook(path, meta, exporter, options, output_options)
        end
    end

    return build_pages(entries)
end
