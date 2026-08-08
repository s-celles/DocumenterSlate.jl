"""
    discover_notebooks(source::AbstractString; include=["*.jl"], exclude=["_*.jl"]) -> Vector{String}
    discover_notebooks(options::SlateBuildOptions) -> Vector{String}

Discover KaimonSlate notebooks under `source` (or `options.source`) matching any
`include` glob pattern and none of the `exclude` glob patterns (spec §7, REQ-EXE-01).

Returns absolute, normalized paths sorted alphabetically so that build order is
reproducible across runs and machines.

`source` (or `options.source`) must exist, or an `ArgumentError` is thrown rather than
silently returning an empty result.

Every discovered path is resolved (`realpath`) and checked to still live inside the
resolved `source` directory before being returned; a notebook whose resolved path
escapes `source` — for example via a symlink planted inside `source` that points
outside it — causes an `ArgumentError` rather than being included (REQ-SEC-06,
directory traversal).
"""
function discover_notebooks(
    source::AbstractString;
    include::AbstractVector{<:AbstractString} = ["*.jl"],
    exclude::AbstractVector{<:AbstractString} = ["_*.jl"],
)
    isdir(source) || throw(ArgumentError(
        "notebook source directory does not exist or is not a directory: `$source`",
    ))

    abs_source = realpath(source)
    include_patterns = _glob_regex.(include)
    exclude_patterns = _glob_regex.(exclude)

    notebooks = String[]
    for name in readdir(source)
        any(re -> occursin(re, name), include_patterns) || continue
        any(re -> occursin(re, name), exclude_patterns) && continue

        candidate = joinpath(source, name)
        isfile(candidate) || continue

        resolved = realpath(candidate)
        _is_within(resolved, abs_source) || throw(ArgumentError(
            "refusing to discover notebook whose path escapes the source directory " *
            "(directory traversal): `$resolved` is not inside `$abs_source`",
        ))

        push!(notebooks, resolved)
    end

    return sort!(notebooks)
end

function discover_notebooks(options::SlateBuildOptions)
    return discover_notebooks(options.source; include = options.include, exclude = options.exclude)
end

"""
    _is_within(path, dir) -> Bool

Structural check that resolved `path` lives inside resolved `dir` (or equals it),
comparing path components rather than the pattern strings used to find `path`
(REQ-SEC-06).
"""
function _is_within(path::AbstractString, dir::AbstractString)
    path == dir && return true
    sep = Base.Filesystem.path_separator
    prefix = endswith(dir, sep) ? dir : dir * sep
    return startswith(path, prefix)
end

"""
    _glob_regex(pattern::AbstractString) -> Regex

Translate a simple shell glob pattern (`*` = any run of characters, `?` = any single
character, everything else literal) into an anchored `Regex` matched against a
filename.
"""
function _glob_regex(pattern::AbstractString)
    io = IOBuffer()
    print(io, "^")
    for c in pattern
        if c == '*'
            print(io, ".*")
        elseif c == '?'
            print(io, ".")
        elseif c in ('\\', '^', '$', '.', '|', '+', '(', ')', '[', ']', '{', '}')
            print(io, '\\', c)
        else
            print(io, c)
        end
    end
    print(io, "\$")
    return Regex(String(take!(io)))
end
