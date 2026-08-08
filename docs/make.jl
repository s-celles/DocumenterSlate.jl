# Deploy job entry point (spec.md §9): consumes the cache `docs/render.jl` populated,
# executing no notebook code (`execution = :never`, REQ-EXE-10) — this is the only script
# that ever runs in a job holding `DOCUMENTER_KEY`.
import Pkg
Pkg.develop(Pkg.PackageSpec(path = dirname(@__DIR__)))
Pkg.instantiate()

using Documenter, DocumenterSlate

opts = SlateBuildOptions(;
    source = joinpath(@__DIR__, "notebooks"),
    output = joinpath(@__DIR__, "src", "notebooks"),
    cache_dir = joinpath(@__DIR__, "slate_cache"),
    slate_toml = joinpath(@__DIR__, "slate.toml"),
    execution = :never,
)
result = build_slates(opts)

# `result.pages`' relative paths are relative to `opts.output` (docs/src/notebooks/) by
# design (SlateBuildResult's docstring: bare, not directory-prefixed, since only the
# caller knows its own layout) — Documenter's own `pages` argument wants paths relative to
# `docs/src/` instead, so the "notebooks/" prefix has to be added here, not assumed away.
notebook_pages = [title => joinpath("notebooks", relpath) for (title, relpath) in result.pages]

makedocs(;
    sitename = "DocumenterSlate.jl",
    modules = [DocumenterSlate],
    # `:exports`, not the default `:all` -- this package's many internal (`_`-prefixed)
    # helper functions carry docstrings for maintainers reading the source, but were never
    # meant to be part of the public doc site's `@docs`/cross-reference graph.
    checkdocs = :exports,
    pages = ["Home" => "index.md", "Notebooks" => notebook_pages,
              "Security" => "security.md"],
)

deploydocs(; repo = "github.com/s-celles/DocumenterSlate.jl.git")
