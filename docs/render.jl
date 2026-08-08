# Render job entry point (spec.md §9): executes notebooks and populates the on-disk cache.
# No secrets in scope here, matching the reference workflow's `render-notebooks` job —
# nothing in this script needs (or should ever be given) `DOCUMENTER_KEY`.
#
# `Pkg.develop` always resolves DocumenterSlate against this local checkout rather than a
# registry (the package isn't published anywhere yet) — this matters for CI, which runs
# this script from a fresh checkout with no prior `Pkg.instantiate()`.
import Pkg
Pkg.develop(Pkg.PackageSpec(path = dirname(@__DIR__)))
Pkg.instantiate()

using DocumenterSlate

opts = SlateBuildOptions(;
    source = joinpath(@__DIR__, "notebooks"),
    output = joinpath(@__DIR__, "src", "notebooks"),
    cache_dir = joinpath(@__DIR__, "slate_cache"),
    slate_toml = joinpath(@__DIR__, "slate.toml"),
    execution = :auto,
)

statuses = collect_build_statuses() do
    build_slates(opts)
end

summary_path = get(ENV, "GITHUB_STEP_SUMMARY", nothing)
if summary_path !== nothing
    open(summary_path, "a") do io
        write_github_step_summary(io, statuses)
    end
end
