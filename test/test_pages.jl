@testitem "build_pages: orders by explicit order first, then alphabetically, skip excluded" begin
    using DocumenterSlate
    using Test

    dir = joinpath(@__DIR__, "fixtures", "notebooks")
    slate_toml = joinpath(@__DIR__, "fixtures", "docs", "slate.toml")

    notebooks = ["simple.jl", "with_roles.jl", "with_bind.jl", "_skip_me.jl"]
    entries = [(joinpath(dir, n), resolve_notebook_meta(joinpath(dir, n), slate_toml))
               for n in notebooks]

    result = build_pages(entries)

    @test result isa SlateBuildResult
    @test result.output_dir === nothing
    titles = first.(result.pages)
    relpaths = last.(result.pages)

    # _skip_me.jl is skip=true in fixtures/docs/slate.toml -> excluded entirely.
    @test !("_skip_me" in [splitext(p)[1] for p in relpaths])
    @test length(result.pages) == 3

    # with_roles.jl has an explicit order=1 in slate.toml -> comes first.
    @test titles[1] == "A Notebook With Roles"
    # the remaining two (simple.jl, with_bind.jl) have no explicit order -> alphabetical
    # by their own resolved title.
    @test titles[2:end] == sort(titles[2:end])
end

@testitem "build_pages: relative output path is the notebook's basename with a .md extension" begin
    using DocumenterSlate
    using Test

    dir = joinpath(@__DIR__, "fixtures", "notebooks")
    meta = resolve_notebook_meta(joinpath(dir, "simple.jl"))

    result = build_pages([(joinpath(dir, "simple.jl"), meta)])

    @test result.pages == ["A simple notebook" => "simple.md"]
end

@testitem "build_pages: two entries sharing an explicit order break ties alphabetically by title" begin
    using DocumenterSlate
    using Test

    mktempdir() do dir
        for (name, title) in [("b.jl", "B title"), ("a.jl", "A title")]
            write(joinpath(dir, name), """
            try; import KaimonSlate; catch; error("no runtime"); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

            #%% md id=title title
            # $title
            """)
        end
        toml = joinpath(dir, "slate.toml")
        write(toml, """
        [[notebook]]
        path = "b.jl"
        order = 1

        [[notebook]]
        path = "a.jl"
        order = 1
        """)

        entries = [(joinpath(dir, n), resolve_notebook_meta(joinpath(dir, n), toml))
                   for n in ("b.jl", "a.jl")]
        result = build_pages(entries)

        @test first.(result.pages) == ["A title", "B title"]
    end
end

@testitem "build_pages: empty input yields an empty result" begin
    using DocumenterSlate
    using Test

    result = build_pages(Tuple{String,NotebookMeta}[])
    @test result.pages == Pair{String,String}[]
end
