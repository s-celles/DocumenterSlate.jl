@testitem "resolve_notebook_project: footer fallback for a notebook with only a Slate.env footer" begin
    using DocumenterSlate
    using Test

    notebook = joinpath(@__DIR__, "fixtures", "notebooks", "simple.jl")

    result = @test_logs (:warn,) match_mode = :any resolve_notebook_project(notebook)

    @test result isa DocumenterSlate.NotebookProjectResolution
    @test result.kind == :footer
    @test result.notebook_path == realpath(notebook)
    @test result.project_dir === nothing
    @test result.manifest_path === nothing
    @test result.env_footer !== nothing
    @test !isempty(result.env_footer)
    @test any(p -> p["name"] == "Example", result.env_footer)
    @test any(p -> p["version"] == "0.5.3", result.env_footer)
end

@testitem "resolve_notebook_project: warns when falling back to the Slate.env footer" begin
    using DocumenterSlate
    using Test

    notebook = joinpath(@__DIR__, "fixtures", "notebooks", "simple.jl")

    @test_logs (:warn,) match_mode = :any resolve_notebook_project(notebook)
end

@testitem "resolve_notebook_project: external Project.toml beside the notebook wins" begin
    using DocumenterSlate
    using Test

    mktempdir() do dir
        notebook = joinpath(dir, "simple.jl")
        cp(joinpath(@__DIR__, "fixtures", "notebooks", "simple.jl"), notebook)

        project_toml = joinpath(dir, "Project.toml")
        write(project_toml, """
        name = "FakeNotebookProject"
        uuid = "11111111-1111-1111-1111-111111111111"

        [deps]
        Example = "7876af07-990d-54b4-ab0e-23690620f79a"
        """)

        result = resolve_notebook_project(notebook)

        @test result isa DocumenterSlate.NotebookProjectResolution
        @test result.kind == :external
        @test result.project_dir == realpath(dir)
        @test result.manifest_path === nothing
        @test result.env_footer === nothing
    end
end

@testitem "resolve_notebook_project: external Project.toml also reports a sibling Manifest.toml" begin
    using DocumenterSlate
    using Test

    mktempdir() do dir
        notebook = joinpath(dir, "simple.jl")
        cp(joinpath(@__DIR__, "fixtures", "notebooks", "simple.jl"), notebook)

        write(joinpath(dir, "Project.toml"), """
        name = "FakeNotebookProject"
        uuid = "22222222-2222-2222-2222-222222222222"
        """)
        write(joinpath(dir, "Manifest.toml"), """
        julia_version = "1.12.0"
        manifest_format = "2.0"
        """)

        result = resolve_notebook_project(notebook)

        @test result.kind == :external
        @test result.project_dir == realpath(dir)
        @test result.manifest_path == realpath(joinpath(dir, "Manifest.toml"))
    end
end

@testitem "resolve_notebook_project: no external Project.toml does not emit a warning about the wrong thing" begin
    using DocumenterSlate
    using Test

    notebook = joinpath(@__DIR__, "fixtures", "notebooks", "simple.jl")
    logs, result = Test.collect_test_logs() do
        resolve_notebook_project(notebook)
    end

    @test result.kind == :footer
    @test any(l -> l.level == Base.CoreLogging.Warn, logs)
end
