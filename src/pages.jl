"""
    SlateBuildResult

Result of ordering a set of notebooks into Documenter `pages` entries
([`build_pages`](@ref), REQ-INT-02).

# Fields
- `pages::Vector{Pair{String,String}}`: `title => relative_output_path`, directly
  insertable into `makedocs(; pages = ...)` (spec §7). Directly `Vector{Pair{String,String}}`
  rather than nesting under a section name — spec §7's example wraps it itself
  (`"Notebooks" => slates.pages`), so this type doesn't presume a section title.
"""
struct SlateBuildResult
    pages::Vector{Pair{String,String}}
end

"""
    build_pages(entries) -> SlateBuildResult

`entries` is an iterable of `(notebook_path, meta::NotebookMeta)` tuples, typically built
by calling [`resolve_notebook_meta`](@ref) over the output of [`discover_notebooks`](@ref).

Filters out every entry with `meta.skip == true` (REQ-INT-02), then orders the rest
(REQ-INT-02: "ordonnée selon le champ `order` du front-matter puis alphabétiquement"):
entries with a non-`nothing` `meta.order` come first, sorted ascending by that value;
entries with no explicit `order` follow, sorted alphabetically by `meta.title`. Ties
(two entries sharing the same explicit `order`, or two unordered entries with the same
title) are broken alphabetically by title. This "explicit order pins the front, everything
else follows alphabetically" rule isn't pinned down further by spec.md — it is the most
common documentation-generator convention and is called out here as a judgment call rather
than a directly cited requirement.

Each page's relative output path is the notebook's basename with its extension replaced by
`.md` (e.g. `notebooks/analysis.jl` → `"analysis.md"`) — bare, not prefixed with a
directory, since only the caller (M1.13's `build_slates`) knows the actual output-directory
layout it is writing into.
"""
function build_pages(entries)
    kept = [(path = String(p), meta = m) for (p, m) in entries if !m.skip]

    ordered = filter(e -> e.meta.order !== nothing, kept)
    unordered = filter(e -> e.meta.order === nothing, kept)
    sort!(ordered; by = e -> (e.meta.order, e.meta.title))
    sort!(unordered; by = e -> e.meta.title)

    pages = Pair{String,String}[]
    for e in Iterators.flatten((ordered, unordered))
        relpath = splitext(basename(e.path))[1] * ".md"
        push!(pages, e.meta.title => relpath)
    end
    return SlateBuildResult(pages)
end
