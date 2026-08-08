# MIME types treated as extractable figures, in priority order (checked top to bottom per
# cell — the first one a value is `showable` as wins). PNG first: it's what CairoMakie's
# default `Makie.set_theme!`/`save` produces and is universally embeddable; SVG second, a
# common alternative for vector output. REQ-REN-04's `:base64` embedding is Could-priority
# and explicitly out of scope for M1 (see spec.md MoSCoW table) — this only ever writes
# files (`assets = :files`).
const _ASSET_MIME_EXTENSIONS = [
    (MIME("image/png"), "png"),
    (MIME("image/svg+xml"), "svg"),
]

function _asset_bytes(value, mime::MIME)
    Base.showable(mime, value) || return nothing
    io = IOBuffer()
    show(io, mime, value)
    return take!(io)
end

"""
    extract_assets!(executed::ExecutedNotebook, dest_dir::AbstractString) -> Dict{String,String}

Write every code cell's displayable figure output to `dest_dir` (REQ-REN-03), creating it
if needed. A cell's `.value` is checked against [`_ASSET_MIME_EXTENSIONS`](@ref) in order;
the first MIME type it is `showable` as is written to a deterministically-numbered file
(`fig-01.png`, `fig-02.svg`, …, numbered across the whole notebook in cell order — not
per-MIME-type). Cells with an `.error`, a `nothing` `.value`, or a `.value` that isn't
showable as any tracked image MIME type produce no asset and no entry.

Returns a `Dict` mapping each such cell's `cell_id` to the **bare filename** written inside
`dest_dir` (e.g. `"fig-01.png"`, not a path). Composing that into the
`assets/<notebook-name>/fig-01.png`-style relative link a rendered page actually embeds
(REQ-REN-03) is the caller's job (M1.12 page assembly), since only the caller knows the
notebook's name/slug — this function only knows the one `dest_dir` it was given, kept
decoupled and easy to test in isolation.

Pass the resulting filename to [`cell_to_markdown`](@ref)'s `asset_path` keyword (joined
with whatever the caller's relative-link convention is) to embed the figure instead of a
text rendering of the cell's raw value.
"""
function extract_assets!(executed::ExecutedNotebook, dest_dir::AbstractString)
    assets = Dict{String,String}()
    idx = 0
    for cell in executed.cells
        cell.kind == :code || continue
        cell.error === nothing || continue
        cell.value === nothing && continue

        for (mime, ext) in _ASSET_MIME_EXTENSIONS
            bytes = _asset_bytes(cell.value, mime)
            bytes === nothing && continue
            isdir(dest_dir) || mkpath(dest_dir)
            idx += 1
            filename = "fig-" * lpad(idx, 2, '0') * "." * ext
            write(joinpath(dest_dir, filename), bytes)
            assets[cell.cell_id] = filename
            break
        end
    end
    return assets
end
