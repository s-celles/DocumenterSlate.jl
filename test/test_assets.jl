@testitem "extract_assets!: writes a PNG-showable cell value and returns its relative filename" begin
    using DocumenterSlate
    using Test

    include(joinpath(@__DIR__, "fixtures", "fake_mime_types.jl"))

    mktempdir() do dir
        notebook = joinpath(dir, "nb.jl")
        write(notebook, """
        try; import KaimonSlate; catch; error("no runtime"); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

        #%% code id=fig
        1 + 1
        """)
        executed = execute_notebook(TextualReplayExporter(), notebook)
        # Swap in a fake-image value without needing a real plotting dependency.
        fig_cell = only(executed.cells)
        patched = ExecutedNotebook(executed.notebook_path,
            [CellResult(fig_cell.cell_id, fig_cell.kind, fig_cell.source, fig_cell.flags,
                        fig_cell.stdout_text, _FakePNG(UInt8[1, 2, 3, 4]), nothing, nothing)],
            executed.mod)

        dest = joinpath(dir, "assets_out")
        assets = extract_assets!(patched, dest)

        @test haskey(assets, "fig")
        relpath_written = assets["fig"]
        @test endswith(relpath_written, ".png")
        @test read(joinpath(dest, relpath_written)) == UInt8[1, 2, 3, 4]
    end
end

@testitem "extract_assets!: writes an SVG-showable cell value" begin
    using DocumenterSlate
    using Test

    include(joinpath(@__DIR__, "fixtures", "fake_mime_types.jl"))

    mktempdir() do dir
        notebook = joinpath(dir, "nb.jl")
        write(notebook, """
        try; import KaimonSlate; catch; error("no runtime"); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

        #%% code id=fig
        1 + 1
        """)
        executed = execute_notebook(TextualReplayExporter(), notebook)
        fig_cell = only(executed.cells)
        patched = ExecutedNotebook(executed.notebook_path,
            [CellResult(fig_cell.cell_id, fig_cell.kind, fig_cell.source, fig_cell.flags,
                        fig_cell.stdout_text, _FakeSVG("<svg></svg>"), nothing, nothing)],
            executed.mod)

        dest = joinpath(dir, "assets_out")
        assets = extract_assets!(patched, dest)

        @test haskey(assets, "fig")
        @test endswith(assets["fig"], ".svg")
        @test read(joinpath(dest, assets["fig"]), String) == "<svg></svg>"
    end
end

@testitem "extract_assets!: a plain numeric value produces no asset" begin
    using DocumenterSlate
    using Test

    notebook = joinpath(@__DIR__, "fixtures", "notebooks", "simple.jl")
    executed = execute_notebook(TextualReplayExporter(), notebook)

    mktempdir() do dir
        assets = extract_assets!(executed, joinpath(dir, "assets_out"))
        @test isempty(assets)
    end
end

@testitem "extract_assets!: filenames are deterministic and sequential across multiple figures" begin
    using DocumenterSlate
    using Test

    include(joinpath(@__DIR__, "fixtures", "fake_mime_types.jl"))

    mktempdir() do dir
        notebook = joinpath(dir, "nb.jl")
        write(notebook, """
        try; import KaimonSlate; catch; error("no runtime"); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

        #%% code id=a
        1
        #%% code id=b
        2
        """)
        executed = execute_notebook(TextualReplayExporter(), notebook)
        patched = ExecutedNotebook(executed.notebook_path,
            [CellResult(c.cell_id, c.kind, c.source, c.flags, c.stdout_text,
                        _FakePNG(UInt8[UInt8(i)]), nothing, nothing)
             for (i, c) in enumerate(executed.cells)],
            executed.mod)

        dest = joinpath(dir, "assets_out")
        assets = extract_assets!(patched, dest)

        @test assets["a"] != assets["b"]
        @test length(readdir(dest)) == 2
    end
end

@testitem "cell_to_markdown: an asset_path renders an image link instead of the raw value" begin
    using DocumenterSlate
    using Test

    notebook = joinpath(@__DIR__, "fixtures", "notebooks", "simple.jl")
    executed = execute_notebook(TextualReplayExporter(), notebook)
    calc = executed.cells[findfirst(c -> c.cell_id == "calc", executed.cells)]

    md = cell_to_markdown(calc; asset_path = "assets/simple/fig-01.png")

    @test occursin("![](assets/simple/fig-01.png)", md)
    @test !occursin("2\n```", md)   # raw value text no longer rendered
end
