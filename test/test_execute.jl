@testitem "execute_notebook: simple.jl executes top-to-bottom, captures value + kind" begin
    using DocumenterSlate
    using Test

    notebook = joinpath(@__DIR__, "fixtures", "notebooks", "simple.jl")
    exporter = TextualReplayExporter()

    executed = execute_notebook(exporter, notebook)

    @test executed isa ExecutedNotebook
    @test executed.notebook_path == realpath(notebook)
    @test length(executed.cells) == 2

    md_cell = executed.cells[1]
    @test md_cell isa CellResult
    @test md_cell.cell_id == "intro"
    @test md_cell.kind == :md
    @test md_cell.value === nothing
    @test md_cell.error === nothing

    code_cell = executed.cells[2]
    @test code_cell.cell_id == "calc"
    @test code_cell.kind == :code
    @test code_cell.value == 2
    @test code_cell.error === nothing
    @test code_cell.stdout_text == ""
end

@testitem "execute_notebook: captures stdout produced by a code cell" begin
    using DocumenterSlate
    using Test

    mktempdir() do dir
        notebook = joinpath(dir, "prints.jl")
        write(notebook, """
        try; import KaimonSlate; catch; error("no runtime"); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

        #%% code id=printer
        println("hello from cell")
        1 + 1
        """)

        executed = execute_notebook(TextualReplayExporter(), notebook)

        cell = only(executed.cells)
        @test cell.stdout_text == "hello from cell\n"
        @test cell.value == 2
    end
end

@testitem "execute_notebook: resolves markdown interpolations in notebook order" begin
    using DocumenterSlate
    using Test

    mktempdir() do dir
        notebook = joinpath(dir, "interpolation.jl")
        write(notebook, """
        try; import KaimonSlate; catch; error("no runtime"); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

        #%% code id=setup
        n = 7
        unsafe = "<script>alert(1)</script>"

        #%% md id=prose
        @md\"\"\"
        The value is {{ n }} and the payload is {{ unsafe }}.

        Inline code stays literal: `{{ unsafe }}`.

        \$\$n = {{ n }}\$\$
        \"\"\"
        """)

        executed = execute_notebook(TextualReplayExporter(), notebook)
        prose = executed.cells[findfirst(c -> c.cell_id == "prose", executed.cells)]

        @test !occursin("{{", prose.source)
        @test occursin("slate-interpolation\">7</span>", prose.source)
        @test occursin("&lt;script&gt;alert(1)&lt;/script&gt;", prose.source)
        @test count("<script>", prose.source) == 1  # only the safe inline-code example
        @test occursin("`<script>alert(1)</script>`", prose.source)
        @test occursin("\$\$n = 7\$\$", prose.source)
    end
end

@testitem "execute_notebook: a failing markdown interpolation identifies its cell" begin
    using DocumenterSlate
    using Test

    mktempdir() do dir
        notebook = joinpath(dir, "broken-interpolation.jl")
        write(notebook, """
        try; import KaimonSlate; catch; error("no runtime"); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

        #%% md id=broken
        @md\"\"\"
        {{ error("interpolation failed") }}
        \"\"\"
        """)

        error = try
            execute_notebook(TextualReplayExporter(), notebook)
            nothing
        catch caught
            caught
        end
        @test error isa SlateExecutionError
        @test error.cell_id == "broken"
        @test occursin("interpolation failed", sprint(showerror, error))
    end
end

@testitem "execute_notebook: broken_cell.jl with fail_on_error=true stops at the failing cell" begin
    using DocumenterSlate
    using Test

    notebook = joinpath(@__DIR__, "fixtures", "notebooks", "broken_cell.jl")

    err = try
        execute_notebook(TextualReplayExporter(), notebook; fail_on_error = true)
        nothing
    catch e
        e
    end

    @test err isa DocumenterSlate.SlateExecutionError
    @test err.cell_id == "boom"
    @test occursin("boom", sprint(showerror, err))
    @test occursin("error(\"boom\")", err.cell_source)
    @test !isempty(err.backtrace_lines)
    @test length(err.backtrace_lines) <= 20
end

@testitem "execute_notebook: broken_cell.jl with fail_on_error=false records the error and continues" begin
    using DocumenterSlate
    using Test

    notebook = joinpath(@__DIR__, "fixtures", "notebooks", "broken_cell.jl")

    executed = execute_notebook(TextualReplayExporter(), notebook; fail_on_error = false)

    @test executed isa ExecutedNotebook
    ids = [c.cell_id for c in executed.cells]
    @test "ok" in ids
    @test "boom" in ids
    @test "unreached" in ids   # execution continued past the broken cell

    ok_cell = executed.cells[findfirst(==("ok"), ids)]
    @test ok_cell.error === nothing
    @test ok_cell.value == 2

    boom_cell = executed.cells[findfirst(==("boom"), ids)]
    @test boom_cell.error !== nothing
    @test boom_cell.backtrace !== nothing

    unreached_cell = executed.cells[findfirst(==("unreached"), ids)]
    @test unreached_cell.error === nothing
    @test unreached_cell.value == "this cell should never run when fail_on_error stops execution at id=boom"
end

@testitem "execute_notebook: notebook exceeding the configured timeout raises a timeout error" begin
    using DocumenterSlate
    using Test

    mktempdir() do dir
        notebook = joinpath(dir, "slow.jl")
        write(notebook, """
        try; import KaimonSlate; catch; error("no runtime"); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

        #%% code id=slow
        sleep(5)
        1
        """)

        exporter = TextualReplayExporter(timeout = 1)

        elapsed = @elapsed begin
            @test_throws DocumenterSlate.SlateExecutionTimeoutError execute_notebook(exporter, notebook)
        end
        @test elapsed < 4.0
    end
end

@testitem "execute_notebook: with_bind.jl resolves the widget default with no binds override" begin
    using DocumenterSlate
    using Test

    notebook = joinpath(@__DIR__, "fixtures", "notebooks", "with_bind.jl")

    executed = execute_notebook(TextualReplayExporter(), notebook)

    ids = [c.cell_id for c in executed.cells]
    use_cell = executed.cells[findfirst(==("usebind"), ids)]
    @test use_cell.value == 2   # Slider(1:10) default is 1, so n * 2 == 2
end

@testitem "execute_notebook: with_bind.jl applies a binds override before dependent cells run" begin
    using DocumenterSlate
    using Test

    notebook = joinpath(@__DIR__, "fixtures", "notebooks", "with_bind.jl")

    executed = execute_notebook(TextualReplayExporter(), notebook; binds = Dict("n" => 7))

    ids = [c.cell_id for c in executed.cells]
    use_cell = executed.cells[findfirst(==("usebind"), ids)]
    @test use_cell.value == 14   # overridden n=7, so n * 2 == 14
end

@testitem "execute_notebook: never references remote/hub machinery (REQ-EXE-09, by construction)" begin
    using DocumenterSlate
    using TOML

    pkg_dir = dirname(dirname(pathof(DocumenterSlate)))

    # Strongest check: no network-capable dependency exists at all, so execute_notebook
    # has nothing to reach a hub/remote host *with*, regardless of what its code says.
    project = TOML.parsefile(joinpath(pkg_dir, "Project.toml"))
    deps = get(project, "deps", Dict())
    @test !haskey(deps, "HTTP")
    @test !haskey(deps, "Sockets")

    # Concrete code patterns that would indicate hub/remote usage if present. Deliberately
    # narrower than a bare substring search over the whole file: execute_notebook's own
    # docstring legitimately *discusses* HubExporter/"remote" while explaining that this
    # exporter doesn't use them (ADR-003's revision), so checking for those words verbatim
    # would flag the documentation, not the code.
    src = read(joinpath(pkg_dir, "src", "execute.jl"), String)
    forbidden_code_patterns = ["using HTTP", "import HTTP", "using Sockets",
                                "import Sockets", "127.0.0.1", "listen("]
    for pattern in forbidden_code_patterns
        @test !occursin(pattern, src)
    end
end

@testitem "execute_notebook never starts the KaimonSlate hub (REQ-SEC-01)" begin
    using DocumenterSlate
    using KaimonSlate
    using Test

    # KaimonSlate._HUB (KaimonSlate.jl:168, `const _HUB = Ref{Union{Hub,Nothing}}(nothing)`)
    # is only ever populated by `_hub()`, which TextualReplayExporter's sole calls into
    # KaimonSlate (standalone!, parse_report) never reach -- see upstream-bugs.md §9 for the
    # exact call sites checked. Checking the internal Ref directly (not a port-connect probe:
    # the literal port number is environment-dependent and unreliable to assert against, e.g.
    # something unrelated may already occupy it in a given sandbox) is a real runtime check
    # of that claim's actual mechanism, not just a documented assertion.
    @test KaimonSlate._HUB[] === nothing   # sanity: not started before this test runs

    notebook = joinpath(@__DIR__, "fixtures", "notebooks", "simple.jl")
    execute_notebook(TextualReplayExporter(), notebook)

    @test KaimonSlate._HUB[] === nothing   # still not started after a real execution
end
