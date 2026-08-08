"""
    NotebookProjectResolution

Result of resolving the pinned dependency environment for a single KaimonSlate
notebook (spec §17 addendum, ADR-004; `upstream-bugs.md` §8 Decision A).

Real KaimonSlate notebooks carry their own dependencies as an embedded `Slate.env`
footer (name/version/UUID triples), not a resolved `Manifest.toml`. M1's resolution
order is:

1. `:external` — an external `Project.toml` sits beside the notebook. `project_dir`
   holds its directory and `manifest_path` holds the path to a sibling
   `Manifest.toml`, if one exists (`nothing` otherwise). `env_footer` is `nothing`.
2. `:footer` — no external `Project.toml` was found, so the literal `Slate.env`
   footer text embedded in the notebook is used as a weaker, unresolved-dependency
   cache-key/provenance component instead. `env_footer` holds the parsed footer
   entries (each a `Dict` with `"name"`, `"version"`, `"uuid"`); `project_dir` and
   `manifest_path` are `nothing`.

No `Pkg.resolve` happens for the `:footer` case in M1 — that is deferred to M2/M3b
per the spec §17 addendum.

# Fields
- `kind::Symbol`: `:external` or `:footer`.
- `notebook_path::String`: resolved (`realpath`) path of the notebook this resolution
  is for.
- `project_dir::Union{Nothing,String}`: resolved directory containing the external
  `Project.toml`, or `nothing` for the `:footer` case.
- `manifest_path::Union{Nothing,String}`: resolved path of a sibling `Manifest.toml`
  next to the external `Project.toml`, or `nothing` when absent or not applicable.
- `env_footer::Union{Nothing,Vector{Dict{String,Any}}}`: parsed `Slate.env` footer
  entries (`KaimonSlate.parse_report(...).meta["env"]`), or `nothing` for the
  `:external` case.
"""
struct NotebookProjectResolution
    kind::Symbol
    notebook_path::String
    project_dir::Union{Nothing,String}
    manifest_path::Union{Nothing,String}
    env_footer::Union{Nothing,Vector{Dict{String,Any}}}
end

"""
    resolve_notebook_project(notebook_path::AbstractString) -> NotebookProjectResolution

Resolve the pinned dependency environment for the KaimonSlate notebook at
`notebook_path` (spec §17 addendum, ADR-004; `upstream-bugs.md` §8 Decision A).

Resolution order:
1. If a `Project.toml` exists in the notebook's own directory, that directory is
   treated as the real pinned project (`kind = :external`). Only the notebook's
   immediate directory is checked — ancestor directories are *not* walked, to avoid
   accidentally picking up an unrelated ancestor `Project.toml` (for example a
   surrounding package repository's own root `Project.toml`).
2. Otherwise, the notebook's embedded `Slate.env` footer is parsed via
   `KaimonSlate.parse_report` and used as a weaker fallback (`kind = :footer`). A
   `@warn` is logged documenting that this is an unresolved-dependency-only
   fallback with no `Pkg.resolve` performed.
"""
function resolve_notebook_project(notebook_path::AbstractString)
    resolved_notebook = realpath(notebook_path)
    notebook_dir = dirname(resolved_notebook)

    project_toml = joinpath(notebook_dir, "Project.toml")
    if isfile(project_toml)
        manifest_toml = joinpath(notebook_dir, "Manifest.toml")
        manifest_path = isfile(manifest_toml) ? realpath(manifest_toml) : nothing
        return NotebookProjectResolution(
            :external, resolved_notebook, realpath(notebook_dir), manifest_path, nothing,
        )
    end

    @warn "No external Project.toml found beside notebook; falling back to the notebook's " *
          "embedded Slate.env footer, which only records unresolved name/version/UUID pins " *
          "(no Pkg.resolve is performed in M1)" notebook = resolved_notebook

    text = read(resolved_notebook, String)
    report = KaimonSlate.parse_report(text)
    env_footer = get(report.meta, "env", Dict{String,Any}[])

    return NotebookProjectResolution(:footer, resolved_notebook, nothing, nothing, env_footer)
end
