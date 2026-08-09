@testitem "cell_to_markdown: markdown cell passes through verbatim, anchor-annotated" begin
    using DocumenterSlate
    using Test

    notebook = joinpath(@__DIR__, "fixtures", "notebooks", "with_roles.jl")
    executed = execute_notebook(TextualReplayExporter(), notebook)
    title_cell = executed.cells[findfirst(c -> c.cell_id == "title", executed.cells)]

    md = cell_to_markdown(title_cell; anchor_prefix = "with-roles")

    @test occursin("# [A Notebook With Roles](@id with-roles-a-notebook-with-roles)", md)
    @test !occursin("<a id=", md)
end

@testitem "cell_to_markdown: hidecode-tagged code cell omits source, keeps output" begin
    using DocumenterSlate
    using Test

    notebook = joinpath(@__DIR__, "fixtures", "notebooks", "hidden_cell.jl")
    executed = execute_notebook(TextualReplayExporter(), notebook)
    hidden = executed.cells[findfirst(c -> c.cell_id == "hidden", executed.cells)]
    @test :hidecode in hidden.flags   # sanity: fixture actually carries the tag

    md = cell_to_markdown(hidden)   # show_code=true (default) — hidecode still wins

    @test !occursin("sum(1:10)", md)
    @test occursin("55", md)
end

@testitem "cell_to_markdown: show_code=false hides source for a non-hidecode cell" begin
    using DocumenterSlate
    using Test

    notebook = joinpath(@__DIR__, "fixtures", "notebooks", "simple.jl")
    executed = execute_notebook(TextualReplayExporter(), notebook)
    calc = executed.cells[findfirst(c -> c.cell_id == "calc", executed.cells)]

    shown = cell_to_markdown(calc; show_code = true)
    hidden = cell_to_markdown(calc; show_code = false)

    @test occursin("1 + 1", shown)
    @test occursin("2", shown)
    @test !occursin("1 + 1", hidden)
    @test occursin("2", hidden)
end

@testitem "cell_to_markdown: code output is a plain fence, never jldoctest (REQ-REN-10)" begin
    using DocumenterSlate
    using Test

    notebook = joinpath(@__DIR__, "fixtures", "notebooks", "simple.jl")
    executed = execute_notebook(TextualReplayExporter(), notebook)
    calc = executed.cells[findfirst(c -> c.cell_id == "calc", executed.cells)]

    md = cell_to_markdown(calc)

    @test !occursin("```jldoctest", md)
end

@testitem "cell_to_markdown: an errored cell renders a visible admonition" begin
    using DocumenterSlate
    using Test

    notebook = joinpath(@__DIR__, "fixtures", "notebooks", "broken_cell.jl")
    executed = execute_notebook(TextualReplayExporter(), notebook; fail_on_error = false)
    boom = executed.cells[findfirst(c -> c.cell_id == "boom", executed.cells)]
    @test boom.error !== nothing   # sanity

    md = cell_to_markdown(boom)

    @test occursin("!!! error", md)
    @test occursin("boom", md)
end

@testitem "cell_to_markdown: error message is fenced, not spliced as raw interpretable text (REQ-SEC-05/T3)" begin
    using DocumenterSlate
    using Test

    mktempdir() do dir
        notebook = joinpath(dir, "nb.jl")
        write(notebook, """
        try; import KaimonSlate; catch; error("no runtime"); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

        #%% code id=boom
        error("<script>alert(1)</script>")
        """)
        executed = execute_notebook(TextualReplayExporter(), notebook; fail_on_error = false)
        boom = only(executed.cells)

        md = cell_to_markdown(boom)

        # The literal payload must be present, but only inside a fenced (literal-text)
        # block — never left as bare, Markdown/raw-HTML-interpretable text. A prior version
        # of this function fenced the backtrace but not the exception's own message,
        # leaving arbitrary runtime-controlled text (whatever a cell happens to throw)
        # unescaped in the page.
        @test occursin("<script>alert(1)</script>", md)
        fence_positions = findall("```", md)
        @test length(fence_positions) >= 2
        payload_pos = first(findfirst("<script>alert(1)</script>", md))
        @test first(fence_positions[1]) < payload_pos < first(fence_positions[end])
    end
end

@testitem "cell_to_markdown: anchors are prefixed per-notebook to avoid cross-page collisions" begin
    using DocumenterSlate
    using Test

    notebook = joinpath(@__DIR__, "fixtures", "notebooks", "simple.jl")
    executed = execute_notebook(TextualReplayExporter(), notebook)
    intro = executed.cells[findfirst(c -> c.cell_id == "intro", executed.cells)]

    md_a = cell_to_markdown(intro; anchor_prefix = "nb1")
    md_b = cell_to_markdown(intro; anchor_prefix = "nb2")

    @test occursin("# [A simple notebook](@id nb1-a-simple-notebook)", md_a)
    @test occursin("# [A simple notebook](@id nb2-a-simple-notebook)", md_b)
    @test !occursin("<a id=", md_a)
    @test !occursin("<a id=", md_b)
    @test md_a != md_b
end

@testitem "cell_to_markdown: a code cell with no output and hidden source renders to near-empty" begin
    using DocumenterSlate
    using Test

    mktempdir() do dir
        notebook = joinpath(dir, "silent.jl")
        write(notebook, """
        try; import KaimonSlate; catch; error("no runtime"); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

        #%% code id=noop
        x = 1
        nothing
        """)
        executed = execute_notebook(TextualReplayExporter(), notebook)
        noop = only(executed.cells)

        md = cell_to_markdown(noop; show_code = false)
        @test strip(md) == "" || !occursin("```", md)
    end
end

@testitem "cell_to_markdown: successful stdout/value output is fenced regardless of HTML-special characters (REQ-SEC-05/T3)" begin
    using DocumenterSlate
    using Test

    mktempdir() do dir
        notebook = joinpath(dir, "nb.jl")
        write(notebook, """
        try; import KaimonSlate; catch; error("no runtime"); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

        #%% code id=printer
        println("<img src=x onerror=alert(1)>")
        "<script>alert(2)</script>"
        """)
        executed = execute_notebook(TextualReplayExporter(), notebook)
        cell = only(executed.cells)
        @test cell.error === nothing   # sanity: this is the success path, not the error path

        md = cell_to_markdown(cell)

        # Both payloads must be present, but only inside fenced (literal-text) blocks --
        # this is the same fencing mechanism M1.17 applied to the error-message path;
        # this test closes the analogous gap for ordinary successful output, which uses
        # the same code but had no adversarial-input test of its own until now.
        @test occursin("<img src=x onerror=alert(1)>", md)
        @test occursin("<script>alert(2)</script>", md)

        fence_positions = findall("```", md)
        @test length(fence_positions) >= 2
        img_pos = first(findfirst("<img src=x onerror=alert(1)>", md))
        script_pos = first(findfirst("<script>alert(2)</script>", md))
        @test first(fence_positions[1]) < img_pos < first(fence_positions[end])
        @test first(fence_positions[1]) < script_pos < first(fence_positions[end])
    end
end
