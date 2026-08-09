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

pages = ["Home" => "index.md", "Notebooks" => notebook_pages, "Security" => "security.md"]

# llms.txt / llms-full.txt (CLAUDE.md convention: generated under docs/, not the repo
# root). No native Documenter.jl support for this was found (checked the locally cached
# 0.27.25/1.14.1/1.16.1/1.17.0 releases, the latest GitHub release, and a full-repository
# code/issue search on JuliaDocs/Documenter.jl — zero references to "llms" anywhere) — this
# follows the same hand-written-generator pattern as github.com/s-celles/Giac.jl's own
# docs/make.jl: flatten `pages` into (title, path) pairs and write both files into
# `docs/src/` *before* `makedocs` runs, so Documenter picks them up as ordinary static
# files and copies them into `docs/build/` alongside the generated HTML.
function flatten_pages(entries, prefix = "")
    flat = Pair{String,String}[]
    for (name, value) in entries
        if value isa AbstractString
            push!(flat, (isempty(prefix) ? name : prefix * " > " * name) => value)
        else
            append!(flat, flatten_pages(value, isempty(prefix) ? name : prefix * " > " * name))
        end
    end
    return flat
end

flat_pages = flatten_pages(pages)

open(joinpath(@__DIR__, "src", "llms.txt"), "w") do io
    println(io, "# DocumenterSlate.jl")
    println(io, "> Publishes KaimonSlate.jl reactive notebooks as native Documenter.jl pages in CI.")
    println(io, "")
    println(io, "## Documentation Sections")
    for (name, path) in flat_pages
        println(io, "- [", name, "](", replace(path, ".md" => ".html"), ")")
    end
end

open(joinpath(@__DIR__, "src", "llms-full.txt"), "w") do io
    println(io, "# DocumenterSlate.jl Full Documentation")
    println(io, "> This file contains the complete documentation source for DocumenterSlate.jl.")
    println(io, "")
    for (name, path) in flat_pages
        src_path = joinpath(@__DIR__, "src", path)
        if isfile(src_path)
            println(io, "## Section: ", name)
            println(io, "<!-- Source: ", path, " -->")
            println(io, "")
            println(io, read(src_path, String))
            println(io, "\n---\n")
        end
    end
end

makedocs(;
    sitename = "DocumenterSlate.jl",
    modules = [DocumenterSlate],
    # `:exports`, not the default `:all` -- this package's many internal (`_`-prefixed)
    # helper functions carry docstrings for maintainers reading the source, but were never
    # meant to be part of the public doc site's `@docs`/cross-reference graph.
    checkdocs = :exports,
    pages = pages,
)

# Documenter warns when `deploydocs` is called outside a recognized CI environment. Keep
# local `just docs` builds warning-free while retaining deployment in GitHub Actions.
if get(ENV, "CI", "") == "true"
    deploydocs(; repo = "github.com/s-celles/DocumenterSlate.jl.git")
end
