"""
    build_slates(options::SlateBuildOptions,
                 output_options::SlateOutputOptions = SlateOutputOptions()) -> SlateBuildResult

Discover, execute, and render every notebook under `options.source` into Documenter-native
Markdown pages under `options.output` (spec §7 — the N0 tier's orchestration entry point,
tying together REQ-EXE-01/02/03/04/06/09, REQ-REN-01/02/03/05/06/09/10, REQ-INT-02).

# Pipeline
1. [`discover_notebooks`](@ref)`(options)`.
2. For each discovered path, [`resolve_notebook_meta`](@ref)`(path, options.slate_toml)`
   (front-matter, `docs/slate.toml` overrides).
3. For every non-`skip` notebook: [`execute_notebook`](@ref) (via `options.exporter`,
   defaulting to a fresh [`TextualReplayExporter`](@ref) when `options.exporter === nothing`),
   passing `options.fail_on_error` and the notebook's resolved `binds`.
4. [`extract_assets!`](@ref) into `<output>/assets/<notebook-slug>/` when
   `output_options.assets == :files` (`:base64`, REQ-REN-04, is Could-priority and not
   implemented).
5. [`cell_to_markdown`](@ref) each cell (anchor-prefixed by the notebook's slug,
   REQ-REN-09), joined and written to `<output>/<notebook-slug>.md`.
6. [`build_pages`](@ref) over every discovered `(path, meta)` pair (including `skip`
   entries, which it filters) to produce the ordered `.pages`.

# Effective `show_code`
A cell's source is shown only when **both** `output_options.show_code` (the site-wide
default) and the notebook's own resolved `meta.show_code` (REQ-REN-05, from
`docs/slate.toml`, defaulting to `true`) are `true` — either one being `false` hides it.
`meta.show_code`'s per-notebook resolution (M1.7) doesn't currently distinguish "explicitly
set to `true` in `docs/slate.toml`" from "left at its own default", so this AND-combination
is the simplest sound reading and is called out here as a judgment call rather than a
directly cited requirement.

# Scope not yet implemented (raises `ArgumentError` rather than silently mis-behaving)
- `options.execution == :never` (REQ-EXE-10: hermetic, cache-only build) — no build cache
  exists until M2's ADR-004 work lands.
- `output_options.format != :documenter` (`:embed`/`:iframe`, REQ-REN-11) — N2 tier, M4.
- `options.nworkers > 1` (REQ-EXE-07, parallel execution) — M2; this does not error, only
  `@warn`s and runs sequentially, since running slower-than-requested is not incorrect the
  way a silently-ignored `:never`/`:iframe` request would be.

Provenance footers (REQ-REN-07) and download links (REQ-REN-08) are Should-priority and
not produced by this milestone either, despite `output_options.provenance`/`.downloads`
existing as fields already (M1.4) — they are inert in M1.
"""
function build_slates(options::SlateBuildOptions,
                       output_options::SlateOutputOptions = SlateOutputOptions())
    options.execution == :never && throw(ArgumentError(
        "execution = :never requires a build cache, which is not implemented until M2 " *
        "(ADR-004); use :auto or :always for now",
    ))
    output_options.format == :documenter || throw(ArgumentError(
        "SlateOutputOptions.format = :$(output_options.format) is not implemented until " *
        "a later milestone (REQ-REN-11, N2 tier); only :documenter is supported in M1",
    ))
    if options.nworkers > 1
        @warn "nworkers > 1 requested but parallel execution (REQ-EXE-07) is not " *
              "implemented until M2; building sequentially" options.nworkers
    end

    exporter = options.exporter === nothing ? TextualReplayExporter() : options.exporter

    notebook_paths = discover_notebooks(options)
    entries = [(path, resolve_notebook_meta(path, options.slate_toml)) for path in notebook_paths]

    isdir(options.output) || mkpath(options.output)

    for (path, meta) in entries
        meta.skip && continue

        executed = execute_notebook(exporter, path;
                                     fail_on_error = options.fail_on_error, binds = meta.binds)
        slug = splitext(basename(path))[1]

        assets_by_cell = if output_options.assets == :files
            extract_assets!(executed, joinpath(options.output, "assets", slug))
        else
            Dict{String,String}()
        end

        show_code = output_options.show_code && meta.show_code
        rendered = map(executed.cells) do cell
            asset_file = get(assets_by_cell, cell.cell_id, nothing)
            asset_path = asset_file === nothing ? nothing :
                         joinpath("assets", slug, asset_file)
            cell_to_markdown(cell; show_code = show_code, anchor_prefix = slug,
                              asset_path = asset_path)
        end

        write(joinpath(options.output, slug * ".md"), join(rendered, "\n\n"))
    end

    return build_pages(entries)
end
