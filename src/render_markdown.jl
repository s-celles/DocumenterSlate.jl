# Matches an ATX heading line (`#` through `######`), capturing the heading text with any
# trailing closing `#`s and whitespace stripped. Used to inject a per-notebook-prefixed
# anchor before each heading (REQ-REN-09) without altering the visible heading text.
const _ATX_HEADING_RE = r"^(#{1,6})[ \t]+(.+?)[ \t]*#*$"

# Lowercase, non-alphanumeric runs collapsed to a single `-`, leading/trailing `-` trimmed.
# Deliberately simple (no transliteration/unicode folding) — good enough for the ASCII
# headings in scope for M1; a fancier slugifier can replace this without changing the
# public `cell_to_markdown` signature.
function _slugify(text::AbstractString)
    s = lowercase(strip(text))
    s = replace(s, r"[^a-z0-9]+" => "-")
    return strip(s, '-')
end

# Rewrites each heading using Documenter's supported `[title](@id anchor)` syntax, so each
# notebook's headings get a stable, page-unique anchor without leaking a raw `<a>` element
# into the rendered page. `anchor_prefix == ""` yields a bare slug (single-notebook /
# no-collision-risk callers can opt out of prefixing).
function _anchor_annotate_headings(text::AbstractString, anchor_prefix::AbstractString)
    out = String[]
    for line in split(text, '\n')
        m = match(_ATX_HEADING_RE, line)
        if m !== nothing
            # Both capture groups are non-optional; `something(...)` narrows their declared
            # `Union{Nothing,SubString}` element type after a successful match.
            hashes = something(m.captures[1])
            title = something(m.captures[2])
            slug = _slugify(title)
            anchor_id = isempty(anchor_prefix) ? slug : anchor_prefix * "-" * slug
            push!(out, hashes * " [" * title * "](@id " * anchor_id * ")")
        else
            push!(out, line)
        end
    end
    return join(out, '\n')
end

# `showerror`-formatted single-line-ish summary of a caught exception, for the admonition
# body — full `.backtrace` (already captured on `CellResult`) is appended below it.
_error_headline(err::Exception) = sprint(showerror, err)

"""
    cell_to_markdown(cell::CellResult; show_code::Bool = true,
                      anchor_prefix::AbstractString = "",
                      asset_path::Union{Nothing,AbstractString} = nothing) -> String

Convert one executed cell (REQ-REN-01) into a Documenter-native Markdown fragment.

# Markdown cells (`cell.kind == :md`)
Returned as-is (`KaimonSlate.parse_report` already unwraps the `@md\"\"\"…\"\"\"` runnable
skin, so `cell.source` is already plain Markdown — REQ-REN-02), except each ATX heading
is rewritten with Documenter's `[title](@id anchor)` syntax, prefixed with
`anchor_prefix` (REQ-REN-09: guarantees uniqueness across notebook pages built into the
same site, since Documenter's own heading-derived anchors are only guaranteed unique
within a single generated page). `{{ … }}` markdown interpolation is out of scope here,
same as M1.9's execution step — see that task's notes; none of this package's fixtures
use it.

**REQ-SEC-05 scope note** (recorded during M3 planning): a markdown cell's source —
including any raw HTML it contains — is passed through to Documenter's CommonMark pipeline
*unmodified*, by design. This matches ordinary Documenter `.md`-source-file semantics and is
required for REQ-REN-02 (native headings feed navigation/search). It is **not** covered by
REQ-SEC-05's "escape content not explicitly marked as raw HTML" guarantee, which applies to
*derived/executed* content — `stdout_text`, `value`, error messages — not author-written
prose. A notebook's markdown cells carry the same trust level as any other Documenter source
page; review changes to `notebooks/`/`docs/notebooks/` at the same rigor as source code
(spec §12 T6's own mitigation note makes the same recommendation).

# Code cells (`cell.kind == :code`)
- Source is shown as a ` ```julia ` fence when `show_code && !(:hidecode in cell.flags)`
  (REQ-REN-05: the `hidecode` tag always wins over `show_code`, since it is the cell
  author's own explicit choice).
- If the cell recorded an error (`cell.error !== nothing` — only possible when the
  notebook was executed with `fail_on_error = false`), the output is a Documenter
  `!!! error` admonition containing the formatted exception and its backtrace, so the
  failure is visible on the page rather than silently dropped (REQ-EXE-05).
- Otherwise, if `asset_path` is given (the relative path [`extract_assets!`](@ref) wrote
  the cell's value to — REQ-REN-03), the output is a single `![](asset_path)` image link
  instead of a text rendering of the value. Otherwise, non-empty `stdout_text` and/or a
  non-`nothing` `value` are rendered as a plain, untagged fenced block — **never**
  ` ```jldoctest ` (REQ-REN-10: notebook output must not be picked up by Documenter's
  doctest runner). A cell with neither stdout nor a displayable value (e.g. ending in a
  bare `using X` or `nothing`) and no `asset_path` produces no output block at all.

Preserves literal `\$…\$`/`\$\$…\$\$` math untouched in both branches (REQ-REN-06) — no
rewriting is performed, so whatever KaTeX/MathJax3 syntax the notebook author used passes
straight through.
"""
function cell_to_markdown(cell::CellResult; show_code::Bool = true,
                           anchor_prefix::AbstractString = "",
                           asset_path::Union{Nothing,AbstractString} = nothing)
    if cell.kind == :md
        return _anchor_annotate_headings(cell.source, anchor_prefix)
    end

    parts = String[]

    show_source = show_code && !(:hidecode in cell.flags)
    if show_source && !isempty(strip(cell.source))
        push!(parts, "```julia\n" * cell.source * "\n```")
    end

    if cell.error !== nothing
        # REQ-SEC-05/T3: the exception's own message is runtime-controlled text (whatever
        # the notebook's code happened to throw, e.g. `error("<script>…</script>")`) — it
        # MUST be fenced like the backtrace already was, not spliced into the admonition
        # body as interpretable Markdown/raw-HTML-passthrough. A single fenced block for
        # both keeps that guarantee simple: everything inside ``` ``` renders as literal
        # text under Documenter's CommonMark pipeline regardless of content.
        body = _error_headline(cell.error)
        if cell.backtrace !== nothing && !isempty(cell.backtrace)
            body *= "\n\n" * cell.backtrace
        end
        fenced = "```\n" * body * "\n```"
        push!(parts, "!!! error \"Cell errored\"\n    " *
                      replace(fenced, "\n" => "\n    "))
    elseif asset_path !== nothing
        !isempty(cell.stdout_text) && push!(parts, "```\n" * cell.stdout_text * "\n```")
        push!(parts, "![](" * asset_path * ")")
    else
        output_lines = String[]
        !isempty(cell.stdout_text) && push!(output_lines, cell.stdout_text)
        cell.value !== nothing && push!(output_lines, string(cell.value))
        if !isempty(output_lines)
            push!(parts, "```\n" * join(output_lines, "\n") * "\n```")
        end
    end

    return join(parts, "\n\n")
end
