"""
    NotebookMeta

Result of resolving front-matter for a single KaimonSlate notebook (spec §7/§10, §17
addendum; `upstream-bugs.md` §8 Decision B).

Real KaimonSlate notebooks carry title/abstract/bibliography as role-tagged cells
(`Cell.flags`), not a `[documenter]` TOML block in cell 1. `title` is resolved via the
same fallback chain KaimonSlate's own PDF/Typst export uses (`export_typst.jl`'s
`report_frontmatter`/`_parse_title_cell`, not itself exported so reimplemented here per
the same "avoid unexported internals" convention as `resolve_notebook_project`):

1. a `:title`-tagged cell's first Markdown H1 line, else
2. the first Markdown H1 in any cell, in cell order, else
3. the notebook's filename without its extension.

Fields DocumenterSlate needs that upstream has no opinion on (`order`, `skip`,
`show_code`, `binds`) come from a matching `[[notebook]]` table in `docs/slate.toml`
(spec §10), matched by notebook filename. When no `slate.toml` is given, or no entry
matches this notebook, they fall back to `order = nothing`, `skip = false`,
`show_code = true` (mirroring [`SlateOutputOptions`](@ref)'s own `show_code` default)
and `binds = Dict()`.

# Fields
- `title::String`: resolved notebook title.
- `order::Union{Nothing,Real}`: page ordering hint, or `nothing` when unset.
- `skip::Bool`: whether this notebook should be excluded from the build.
- `show_code::Bool`: whether cell source is rendered alongside outputs.
- `binds::Dict{String,Any}`: `@bind` values to apply before execution (REQ-EXE-08).
"""
struct NotebookMeta
    title::String
    order::Union{Nothing,Real}
    skip::Bool
    show_code::Bool
    binds::Dict{String,Any}
end

# Matches export_typst.jl's `_parse_title_cell`: a line consisting of a single `#`
# followed by whitespace is an H1 (`##`/`###` are not, since `#` isn't followed by
# whitespace immediately).
const _TITLE_TAG_H1_LINE_RE = r"^#\s+(.+?)\s*#*$"

# Matches export_typst.jl's `report_frontmatter` else-branch: the first ATX H1 anywhere
# in a markdown cell's source (multiline).
const _ANY_CELL_H1_RE = r"(?m)^#[ \t]+(.+?)[ \t]*#*$"

"""
    _resolve_own_title(report, notebook_path) -> String

Resolve a notebook's own title, independent of any `slate.toml` override, following the
fallback chain documented on [`NotebookMeta`](@ref).
"""
function _resolve_own_title(report, notebook_path::AbstractString)::String
    cells = report.cells
    titlei = findfirst(c -> :title in c.flags, cells)
    if titlei !== nothing
        for ln in split(String(cells[titlei].source), '\n')
            isempty(strip(ln)) && continue
            m = match(_TITLE_TAG_H1_LINE_RE, ln)
            # `_TITLE_TAG_H1_LINE_RE`'s sole capture group is non-optional, so whenever the
            # whole match succeeds, captures[1] is always populated -- `something(...)`
            # narrows `RegexMatch.captures`'s declared `Union{Nothing,SubString}` element
            # type accordingly (and would throw, correctly, if that invariant were ever
            # violated, rather than silently misbehaving).
            m !== nothing && return strip(something(m.captures[1]))
        end
        # A tagged `:title` cell with no H1 line does NOT fall through to searching
        # other cells (upstream's `report_frontmatter` only re-derives the title in the
        # `titlei === nothing` branch) — fall straight to the filename.
    else
        for c in cells
            c.kind == KaimonSlate.MARKDOWN || continue
            m = match(_ANY_CELL_H1_RE, c.source)
            m === nothing && continue
            return strip(something(m.captures[1]))   # see the analogous narrowing above
        end
    end
    return splitext(basename(notebook_path))[1]
end

"""
    _find_notebook_toml_entry(slate_toml_path, notebook_path) -> Union{Nothing,Dict}

Look up the `[[notebook]]` table entry in `slate_toml_path` whose `path` field matches
`notebook_path` by filename, or `nothing` if `slate_toml_path` is `nothing` or no entry
matches.
"""
function _find_notebook_toml_entry(
    slate_toml_path::Union{Nothing,AbstractString}, notebook_path::AbstractString,
)
    slate_toml_path === nothing && return nothing
    toml = TOML.parsefile(slate_toml_path)
    # `toml::Dict{String,Any}` (TOML.jl's own return type) means `get(toml, "notebook", ...)`
    # is statically `Any` regardless of the default's type. An `isa` check (rather than a
    # broadcasted conversion, whose own return type is still inferred from an `Any` input
    # and doesn't actually narrow anything) is control-flow narrowing JET's analysis
    # recognizes: after this branch, `raw` is concretely `AbstractVector`, so the
    # `Dict{String,Any}[...]` comprehension below produces a genuinely concrete
    # `Vector{Dict{String,Any}}`, not an `Any`-typed one — REQ-INT-02/spec §10's
    # `[[notebook]]` really must be an array of tables; anything else is a malformed
    # `slate.toml`, worth a clear error rather than papering over.
    raw = get(toml, "notebook", [])
    raw isa AbstractVector || throw(ArgumentError(
        "`notebook` in `$slate_toml_path` must be an array of tables (`[[notebook]]`), " *
        "got a `$(typeof(raw))`",
    ))
    entries = Dict{String,Any}[Dict{String,Any}(e) for e in raw]
    name = basename(notebook_path)
    idx = findfirst(e -> basename(String(get(e, "path", ""))) == name, entries)
    return idx === nothing ? nothing : entries[idx]
end

"""
    resolve_notebook_meta(notebook_path::AbstractString, slate_toml_path=nothing) -> NotebookMeta

Resolve front-matter for the KaimonSlate notebook at `notebook_path` (spec §7/§10, §17
addendum; `upstream-bugs.md` §8 Decision B).

`title` is resolved from the notebook itself (role-tagged cell → first H1 → filename,
see [`NotebookMeta`](@ref)); `order`, `skip`, `show_code` and `binds` fall back to
`nothing`/`false`/`true`/`Dict()` unless overridden.

If `slate_toml_path` is given, it is parsed and searched for a `[[notebook]]` table
entry whose `path` field's filename matches `notebook_path`'s filename; any of `title`,
`order`, `skip`, `show_code`, `binds` present in that entry override the notebook's own
resolution.
"""
function resolve_notebook_meta(
    notebook_path::AbstractString, slate_toml_path::Union{Nothing,AbstractString} = nothing,
)
    resolved_notebook = realpath(notebook_path)
    text = read(resolved_notebook, String)
    report = KaimonSlate.parse_report(text)

    title = _resolve_own_title(report, resolved_notebook)
    order = nothing
    skip = false
    show_code = true
    binds = Dict{String,Any}()

    entry = _find_notebook_toml_entry(slate_toml_path, resolved_notebook)
    if entry !== nothing
        haskey(entry, "title") && (title = String(entry["title"]))
        haskey(entry, "order") && (order = entry["order"])
        haskey(entry, "skip") && (skip = Bool(entry["skip"]))
        haskey(entry, "show_code") && (show_code = Bool(entry["show_code"]))
        haskey(entry, "binds") && (binds = Dict{String,Any}(entry["binds"]))
    end

    return NotebookMeta(title, order, skip, show_code, binds)
end
