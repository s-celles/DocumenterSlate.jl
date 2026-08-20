# Copies a cache hit's page text + assets (if any) into the real output directory. Shared
# by every `execution` mode that can be satisfied by a cache hit (`:auto`, `:never`).
function _write_output_from_cache(output_dir::AbstractString, slug::AbstractString, cached;
                                  page_text::AbstractString = cached.page_text)
    isdir(output_dir) || mkpath(output_dir)
    write(joinpath(output_dir, slug * ".md"), page_text)
    if cached.assets_dir !== nothing
        dest = joinpath(output_dir, "assets", slug)
        isdir(dest) && rm(dest; recursive = true)
        mkpath(dirname(dest))
        cp(cached.assets_dir, dest)
    end
    return nothing
end

function _rewrite_notebook_links!(output_dir::AbstractString,
                                  notebook_paths::AbstractVector{<:AbstractString})
    for source_path in notebook_paths
        slug = splitext(basename(source_path))[1]
        page_path = joinpath(output_dir, slug * ".md")
        isfile(page_path) || continue
        page = read(page_path, String)

        for target_path in notebook_paths
            relative_source = replace(relpath(target_path, dirname(source_path)), '\\' => '/')
            relative_page = splitext(basename(target_path))[1] * ".md"
            candidates = startswith(relative_source, "./") ? (relative_source,) :
                         (relative_source, "./" * relative_source)
            for candidate in candidates, boundary in (')', '#', '?', ' ')
                page = replace(page,
                    "](" * candidate * string(boundary) =>
                    "](" * relative_page * string(boundary),
                )
            end
        end

        write(page_path, page)
    end
    return nothing
end

# Return the distinct `region=<name>` tags declared by a notebook. Use KaimonSlate's parser
# instead of matching source text so comments and strings containing `region=` cannot trigger
# the security gate accidentally. This is an authorization check only: the current
# TextualReplayExporter remains local and never starts KaimonSlate's remote machinery.
function _remote_region_tags(path::AbstractString)
    report = KaimonSlate.parse_report(read(path, String))
    tags = String[]
    for cell in report.cells, flag in cell.flags
        tag = String(flag)
        startswith(tag, "region=") && length(tag) > length("region=") && push!(tags, tag)
    end
    return sort!(unique!(tags))
end

function _check_remote_opt_in(path::AbstractString, options::SlateBuildOptions)
    options.allow_remote && return nothing
    tags = _remote_region_tags(path)
    isempty(tags) && return nothing
    throw(ArgumentError(
        "notebook \"$path\" declares remote execution ($(join(tags, ", "))); " *
        "refusing to build it unless SlateBuildOptions(allow_remote = true) is set " *
        "explicitly (REQ-EXE-09)",
    ))
end

# One notebook's full pipeline: cache lookup (unless `:always`) -> execute on a miss ->
# render -> write to `options.output` -> refresh the cache. Factored out of `build_slates`'s
# loop body so M2.5's parallel path can call it identically per-worker. Logs one @info line
# per notebook with its final status (:cached/:executed) and elapsed wall-clock time
# (REQ-CI-02, pulled forward from M3 since M2 introduces these statuses in the first place —
# there'd otherwise be nothing observable distinguishing a fast cache hit from a slow
# re-execution). A thrown exception (execution=:never miss, or a fail_on_error=true cell
# error) is logged as :failed and then re-raised unchanged — this is observability, not
# error handling, so it must never swallow or alter what the caller sees.
function _build_one_notebook(path::AbstractString, meta::NotebookMeta,
                              exporter::AbstractSlateExporter,
                              options::SlateBuildOptions, output_options::SlateOutputOptions)
    t0 = time()
    slug = splitext(basename(path))[1]
    try
        _check_remote_opt_in(path, options)
        project = resolve_notebook_project(path)
        components = _gather_cache_components(path, project, output_options, meta,
                                               options.fail_on_error,
                                               options.worker_environment)
        fingerprint = _cache_fingerprint(components)

        cached = options.execution == :always ? nothing :
                 _read_cache_entry(options.cache_dir, slug, fingerprint)

        if cached !== nothing && cached.environment_dir !== nothing
            cached_distribution = _write_distribution!(
                path, project, options.output, slug; environment_dir = cached.environment_dir,
            )
            decorated = _decorate_page(cached.page_text, cached_distribution, slug;
                                       canonical = output_options.canonical)
            _write_output_from_cache(options.output, slug, cached; page_text = decorated)
            @info "notebook build" slug status=:cached elapsed_s=round(time() - t0; digits = 3)
            return nothing
        end

        if options.execution == :never
            throw(ArgumentError(
                "execution = :never requires a cache hit for notebook \"$path\" (slug " *
                "\"$slug\"), but none was found under cache_dir=\"$(options.cache_dir)\" " *
                "matching the current fingerprint ($fingerprint); populate the cache with " *
                "a prior :auto or :always build before using :never (REQ-EXE-10)",
            ))
        end

        exporter isa TextualReplayExporter || throw(ArgumentError(
            "isolated rendering is not implemented for $(typeof(exporter))"))
        _with_prepared_project(project, options, exporter.timeout) do prepared_project
            fresh_distribution = _write_distribution!(
                path, project, options.output, slug; environment_dir = prepared_project,
            )
            assets_out_dir = joinpath(options.output, "assets", slug)
            page_text = _render_notebook_isolated(
                path, prepared_project, exporter, options, output_options, meta, slug,
            )
            write(joinpath(options.output, slug * ".md"),
                  _decorate_page(page_text, fresh_distribution, slug;
                                 canonical = output_options.canonical))

            # Refresh the cache on every non-cache-hit build (`:auto` miss, or `:always`) so a
            # *following* `:auto`/`:never` build benefits (REQ-CACHE-01's "réutiliser" invariant
            # holds for the next build, not just this one).
            _write_cache_entry!(options.cache_dir, slug, fingerprint, components, page_text,
                                isdir(assets_out_dir) ? assets_out_dir : nothing,
                                prepared_project)
        end

        @info "notebook build" slug status=:executed elapsed_s=round(time() - t0; digits = 3)
        return nothing
    catch e
        @info "notebook build" slug status=:failed elapsed_s=round(time() - t0; digits = 3)
        rethrow(e)
    end
end

# `Distributed.pmap`'s worker function must never let an exception escape uncaught: pmap
# wraps an escaping exception in `RemoteException`/`CompositeException`, which would change
# `SlateExecutionError`/`SlateExecutionTimeoutError`'s type as seen by the caller (breaking
# the `err isa DocumenterSlate.SlateExecutionError` contract the sequential path already
# guarantees). Catching here and returning the exception as an ordinary value instead
# sidesteps that entirely: `pmap` sees a normal (non-throwing) result either way, and
# `_build_parallel!` re-throws the *original* typed exception itself once every worker has
# finished, after `finally`-guaranteed `rmprocs` cleanup has already run.
function _build_one_notebook_safe(path::AbstractString, meta::NotebookMeta,
                                   exporter::AbstractSlateExporter,
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

Runs `_build_one_notebook` for every `(path, meta)` in `to_build` across
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
`_build_one_notebook_safe` catches every exception on the worker and returns it as
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
function _build_parallel!(to_build, exporter::AbstractSlateExporter, options::SlateBuildOptions,
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
3. For every non-`skip` notebook, refuse any `region=<name>` tag unless
   `options.allow_remote == true` (REQ-EXE-09), then `_build_one_notebook`: resolve the notebook's
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

# Known limitation: `execution = :never`'s cache trust has no producer binding
(M2 security review finding, recorded here since it's the first milestone where
`:never` is actually functional.) The composite fingerprint (ADR-004) is computed only
from *inputs* — notebook bytes, resolved environment, tool versions, render options — all
of which spec.md itself requires publishing (REQ-DIST-01/02) or are checked into the repo.
It never hashes the paired `.md` body. A party who can place a `<slug>.md` +
`<slug>.cache.toml` pair with a matching self-reported fingerprint into whatever directory
later becomes `options.cache_dir` for a privileged `execution = :never` build can have
arbitrary content published verbatim — `_write_output_from_cache` copies it through with
none of `cell_to_markdown`'s REQ-SEC-05 escaping, since that only runs on the
execute-then-render path. REQ-SEC-03's "no code execution in the privileged job" guarantee
still holds (a forged entry is a cache *hit*, never triggers `execute_notebook`), but T6
("third-party content published under repo identity") is not mitigated by anything in
`src/cache.jl`/`src/build.jl` today. Closing this needs binding a cache entry to *who
produced it* (REQ-TRUST-02's `PROVENANCE.toml`/CI run ID, or REQ-TRUST-03's build
attestation) — a stronger hash of the same public inputs cannot fix it. Tracked for M3
(before the two-job workflow is considered to hold end-to-end) / M3b, not fixed here.

# Historical note: spec.md §9's illustrative example workflow had this bug
spec.md §9's *illustrative* reference workflow (non-normative prose, not shipped code) only
restored `docs/src/notebooks` via `actions/download-artifact` — it never restored
`docs/slate_cache`. As written, that example's `execution = :never` call would have hit
this function's `ArgumentError` on every run, since `options.cache_dir` would always be
empty. **Fixed in the actual shipped workflow**: `.github/workflows/docs.yml` uploads
`docs/slate_cache` as an artifact in `render-notebooks` and downloads that same artifact in
`build-and-deploy` before `docs/make.jl` runs — `execution = :never` there has a genuinely
populated cache to read. This note stays only as the historical record of the bug spec.md's
own prose sketch had; it does not describe a gap in this repository's real workflow.

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
processes via `_build_parallel!` — not threads; see that function's docstring for
why (`src/execute.jl`'s stdout-capture lock makes threaded fan-out either corrupt output or
fully serialize, not actually parallelize). Falls back to the plain sequential loop when
`nworkers <= 1` or there is at most one notebook to build (not worth process-spawn
overhead). Each dispatched notebook still does its own cache lookup independently (on
whichever worker it lands on) — a hit is cheap disk I/O, not worth special-casing out of
the worker pool. `pmap`'s result order matches input order regardless of completion order,
so worker scheduling never disturbs [`build_pages`](@ref)'s ordering.

# Scope not yet implemented (raises `ArgumentError` rather than silently mis-behaving)
- `output_options.format != :documenter` (`:embed`/`:iframe`, REQ-REN-11) — N2 tier, M4.

Download links and per-artifact provenance (M3b) are generated for every notebook. The
`output_options.provenance`/`.downloads` selectors and a separate provenance footer
(REQ-REN-07) remain inert until the configurable expander work in M4. REQ-CACHE-05's `check_slates()`
non-determinism detector is explicitly deferred past M2 (it needs a second execution to
diff against the cache, which is exactly the cost `:auto`/`:never` exist to avoid).

Cache misses are rendered in a dedicated child process. A manifest-backed notebook project is
activated before execution, the parent environment is not inherited, and timeout hard-kills the
worker process. Footer-only environments are resolved and instantiated in another isolated
process; their Project and Manifest are cached for the non-executing deployment job.
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

    # Notebook authors naturally link to another runnable source as `other.jl`. The
    # generated Documenter site contains `other.md`, while the downloadable source must
    # remain unchanged. Rewrite only destinations that resolve to another discovered,
    # non-skipped notebook, after cache materialization and page decoration.
    _rewrite_notebook_links!(options.output, first.(to_build))

    pages = build_pages(entries)
    return SlateBuildResult(pages.pages, options.output)
end
