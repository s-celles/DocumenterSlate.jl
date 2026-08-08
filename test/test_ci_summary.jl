@testitem "collect_build_statuses + write_github_step_summary: end-to-end over a real build" begin
    using DocumenterSlate
    using Test

    mktempdir() do root
        source = joinpath(root, "notebooks")
        mkpath(source)
        cp(joinpath(@__DIR__, "fixtures", "notebooks", "simple.jl"), joinpath(source, "simple.jl"))

        opts = SlateBuildOptions(; source = source, output = joinpath(root, "out"),
                                  cache_dir = joinpath(root, "cache"))

        statuses = DocumenterSlate.collect_build_statuses() do
            build_slates(opts)
        end

        @test length(statuses) == 1
        @test statuses[1].slug == "simple"
        @test statuses[1].status == :executed
        @test statuses[1].elapsed_s isa Real

        io = IOBuffer()
        DocumenterSlate.write_github_step_summary(io, statuses)
        text = String(take!(io))
        @test occursin("simple", text)
        @test occursin("executed", text)
        @test occursin("|", text)   # a Markdown table
    end
end

@testitem "collect_build_statuses: a second, cached build reports :cached" begin
    using DocumenterSlate
    using Test

    mktempdir() do root
        source = joinpath(root, "notebooks")
        mkpath(source)
        cp(joinpath(@__DIR__, "fixtures", "notebooks", "simple.jl"), joinpath(source, "simple.jl"))

        cache_dir = joinpath(root, "cache")
        opts = SlateBuildOptions(; source = source, output = joinpath(root, "out"), cache_dir = cache_dir)

        DocumenterSlate.collect_build_statuses() do
            build_slates(opts)
        end
        statuses2 = DocumenterSlate.collect_build_statuses() do
            build_slates(opts)
        end

        @test statuses2[1].status == :cached
    end
end

@testitem "write_github_step_summary: formats multiple statuses in input order" begin
    using DocumenterSlate
    using Test

    statuses = [
        (slug = "a", status = :cached, elapsed_s = 0.1),
        (slug = "b", status = :executed, elapsed_s = 2.5),
        (slug = "c", status = :failed, elapsed_s = 0.3),
    ]
    io = IOBuffer()
    DocumenterSlate.write_github_step_summary(io, statuses)
    text = String(take!(io))
    lines = split(text, '\n')

    a_idx = findfirst(l -> occursin("a", l) && occursin("cached", l), lines)
    b_idx = findfirst(l -> occursin("b", l) && occursin("executed", l), lines)
    c_idx = findfirst(l -> occursin("c", l) && occursin("failed", l), lines)

    @test a_idx !== nothing && b_idx !== nothing && c_idx !== nothing
    @test a_idx < b_idx < c_idx
end

@testitem "write_github_step_summary: empty statuses still writes a valid (header-only) table" begin
    using DocumenterSlate
    using Test

    io = IOBuffer()
    DocumenterSlate.write_github_step_summary(io, NamedTuple[])
    text = String(take!(io))
    @test occursin("|", text)
end
