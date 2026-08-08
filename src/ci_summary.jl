# A pass-through logger that skims `_build_one_notebook`'s "notebook build" @info records
# (slug/status/elapsed_s, added in M2.6) into `statuses` while forwarding every message
# unchanged to `parent` — nothing about the build's own logging behavior changes, this only
# taps it. Kept private/internal (not exported): callers use `collect_build_statuses`, which
# owns setting this up and tearing it down via `Logging.with_logger`.
struct _BuildStatusLogger <: Logging.AbstractLogger
    statuses::Vector{NamedTuple{(:slug, :status, :elapsed_s),Tuple{String,Symbol,Float64}}}
    parent::Logging.AbstractLogger
end

Logging.min_enabled_level(l::_BuildStatusLogger) = Logging.min_enabled_level(l.parent)
Logging.shouldlog(l::_BuildStatusLogger, level, _module, group, id) =
    Logging.shouldlog(l.parent, level, _module, group, id)
Logging.catch_exceptions(l::_BuildStatusLogger) = Logging.catch_exceptions(l.parent)

function Logging.handle_message(l::_BuildStatusLogger, level, message, _module, group, id,
                                 file, line; kwargs...)
    if message == "notebook build"
        kw = Dict(pairs(kwargs))
        push!(l.statuses, (
            slug = string(kw[:slug]),
            status = kw[:status]::Symbol,
            elapsed_s = Float64(kw[:elapsed_s]),
        ))
    end
    return Logging.handle_message(l.parent, level, message, _module, group, id, file, line;
                                   kwargs...)
end

"""
    collect_build_statuses(f) -> Vector{<:NamedTuple}

Runs `f()` (typically `() -> build_slates(options, output_options)`) while capturing every
per-notebook `"notebook build"` `@info` record `build_slates` emits (REQ-CI-02, M2.6),
returning them as `(slug, status, elapsed_s)` NamedTuples in emission order.

`build_slates`'s own return type ([`SlateBuildResult`](@ref)) intentionally doesn't carry
this — it's build-*order* information (`.pages`), not build-*status* information, and widening
it would touch every existing caller/test of `build_slates`. This function taps the logging
output instead (a real, already-emitted signal, not a parallel bookkeeping path that could
drift from what actually happened).

# Limitation: sequential builds only (`options.nworkers <= 1`)
Verified empirically, not assumed: `@info` calls made inside a `_build_parallel!`
`pmap`-dispatched worker task are **not** routed through the calling process's `Logging`
dispatch — `Distributed` instead forwards each worker's log output as pre-formatted text
straight to the master's `stdout` (visible in a CI job's raw log either way), bypassing
`Logging.with_logger`/`handle_message` entirely. This function's capture mechanism therefore
only sees records from a *sequential* build. A `nworkers > 1` build's per-notebook statuses
are still logged normally and visible in CI output, just not collectible here — building a
cross-process structured-logging bridge is out of scope for this Could-priority utility
(REQ-CI-04).

Pair with [`write_github_step_summary`](@ref) to build a `\$GITHUB_STEP_SUMMARY`-ready
report from a real `docs/render.jl`/`docs/make.jl` build.
"""
function collect_build_statuses(f)
    logger = _BuildStatusLogger(
        NamedTuple{(:slug, :status, :elapsed_s),Tuple{String,Symbol,Float64}}[],
        Logging.current_logger(),
    )
    Logging.with_logger(f, logger)
    return logger.statuses
end

const _STATUS_EMOJI = Dict(:cached => "🗄️", :executed => "✅", :failed => "❌")

"""
    write_github_step_summary(io::IO, statuses) -> Nothing

Writes a Markdown table (notebook slug, status, elapsed seconds) to `io`, suitable for
`\$GITHUB_STEP_SUMMARY` (REQ-CI-04). `statuses` is any iterable of objects exposing `.slug`,
`.status`, and `.elapsed_s` — typically [`collect_build_statuses`](@ref)'s return value, but
deliberately duck-typed rather than requiring that exact type, so a caller assembling its own
report (e.g. merging two builds) doesn't need to.
"""
function write_github_step_summary(io::IO, statuses)
    println(io, "| Notebook | Status | Elapsed (s) |")
    println(io, "|---|---|---|")
    for s in statuses
        emoji = get(_STATUS_EMOJI, s.status, "❓")
        println(io, "| `", s.slug, "` | ", emoji, " ", s.status, " | ",
                round(s.elapsed_s; digits = 3), " |")
    end
    return nothing
end
