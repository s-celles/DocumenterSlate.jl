@testitem "resolve_notebook_meta: title resolves via the :title-tagged cell" begin
    using DocumenterSlate

    notebook = joinpath(@__DIR__, "fixtures", "notebooks", "with_roles.jl")
    meta = resolve_notebook_meta(notebook)

    @test meta isa DocumenterSlate.NotebookMeta
    @test meta.title == "A Notebook With Roles"
end

@testitem "resolve_notebook_meta: title falls back to the first Markdown H1 when no :title tag exists" begin
    using DocumenterSlate

    notebook = joinpath(@__DIR__, "fixtures", "notebooks", "simple.jl")
    meta = resolve_notebook_meta(notebook)

    @test meta.title == "A simple notebook"
end

@testitem "resolve_notebook_meta: title falls back to the filename when neither a :title tag nor an H1 exist" begin
    using DocumenterSlate

    mktempdir() do dir
        notebook = joinpath(dir, "no_title_here.jl")
        write(notebook, """
        try; import KaimonSlate; catch; error("stub"); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

        #%% md id=intro
        Just some prose, no heading at all.

        #%% code id=calc
        1 + 1
        """)

        meta = resolve_notebook_meta(notebook)

        @test meta.title == "no_title_here"
    end
end

@testitem "resolve_notebook_meta: defaults apply when no slate.toml is given" begin
    using DocumenterSlate

    notebook = joinpath(@__DIR__, "fixtures", "notebooks", "with_roles.jl")
    meta = resolve_notebook_meta(notebook)

    @test meta.order === nothing
    @test meta.skip == false
    @test meta.show_code == true
    @test meta.binds == Dict()
end

@testitem "resolve_notebook_meta: defaults apply when slate.toml has no matching entry" begin
    using DocumenterSlate

    notebook = joinpath(@__DIR__, "fixtures", "notebooks", "simple.jl")
    slate_toml = joinpath(@__DIR__, "fixtures", "docs", "slate.toml")
    meta = resolve_notebook_meta(notebook, slate_toml)

    @test meta.title == "A simple notebook"
    @test meta.order === nothing
    @test meta.skip == false
    @test meta.show_code == true
    @test meta.binds == Dict()
end

@testitem "resolve_notebook_meta: slate.toml [[notebook]] entry overrides order, title and skip" begin
    using DocumenterSlate

    notebook = joinpath(@__DIR__, "fixtures", "notebooks", "with_roles.jl")
    slate_toml = joinpath(@__DIR__, "fixtures", "docs", "slate.toml")
    meta = resolve_notebook_meta(notebook, slate_toml)

    @test meta.title == "A Notebook With Roles"
    @test meta.order == 1
    @test meta.skip == false
    @test meta.show_code == true
end

@testitem "resolve_notebook_meta: slate.toml [[notebook]] entry sets skip = true" begin
    using DocumenterSlate

    notebook = joinpath(@__DIR__, "fixtures", "notebooks", "_skip_me.jl")
    slate_toml = joinpath(@__DIR__, "fixtures", "docs", "slate.toml")
    meta = resolve_notebook_meta(notebook, slate_toml)

    @test meta.skip == true
end

@testitem "resolve_notebook_meta: slate.toml [[notebook]] entry can override binds and show_code" begin
    using DocumenterSlate

    mktempdir() do dir
        notebook = joinpath(dir, "analysis.jl")
        cp(joinpath(@__DIR__, "fixtures", "notebooks", "simple.jl"), notebook)

        slate_toml = joinpath(dir, "slate.toml")
        write(slate_toml, """
        [[notebook]]
        path = "analysis.jl"
        order = 3
        show_code = false
        binds = { n = 42 }
        """)

        meta = resolve_notebook_meta(notebook, slate_toml)

        @test meta.order == 3
        @test meta.show_code == false
        @test meta.binds == Dict("n" => 42)
    end
end
