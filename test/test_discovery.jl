@testitem "discover_notebooks: default include/exclude finds fixtures, excludes _skip_me.jl" begin
    using DocumenterSlate

    fixtures_dir = joinpath(@__DIR__, "fixtures", "notebooks")
    found = discover_notebooks(fixtures_dir)

    @test length(found) == 5
    @test all(isabspath, found)
    @test all(isfile, found)
    @test !any(p -> basename(p) == "_skip_me.jl", found)

    expected_names = [
        "broken_cell.jl", "hidden_cell.jl", "simple.jl", "with_bind.jl", "with_roles.jl",
    ]
    @test sort(basename.(found)) == sort(expected_names)
end

@testitem "discover_notebooks: works from a SlateBuildOptions instance" begin
    using DocumenterSlate

    fixtures_dir = joinpath(@__DIR__, "fixtures", "notebooks")
    opts = SlateBuildOptions(source = fixtures_dir, output = mktempdir())
    found = discover_notebooks(opts)

    @test length(found) == 5
    @test !any(p -> basename(p) == "_skip_me.jl", found)
end

@testitem "discover_notebooks: custom include/exclude patterns" begin
    using DocumenterSlate

    fixtures_dir = joinpath(@__DIR__, "fixtures", "notebooks")

    only_with = discover_notebooks(fixtures_dir; include = ["with_*.jl"])
    @test sort(basename.(only_with)) == ["with_bind.jl", "with_roles.jl"]

    excl_broken = discover_notebooks(
        fixtures_dir; include = ["*.jl"], exclude = ["_*.jl", "broken_*.jl"],
    )
    @test !any(p -> basename(p) == "broken_cell.jl", excl_broken)
    @test length(excl_broken) == 4

    none = discover_notebooks(fixtures_dir; include = ["*.nonexistent"])
    @test isempty(none)
end

@testitem "discover_notebooks: deterministic sorted ordering" begin
    using DocumenterSlate

    fixtures_dir = joinpath(@__DIR__, "fixtures", "notebooks")
    found1 = discover_notebooks(fixtures_dir)
    found2 = discover_notebooks(fixtures_dir)

    @test found1 == found2
    @test found1 == sort(found1)
end

@testitem "discover_notebooks: nonexistent source directory errors" begin
    using DocumenterSlate

    bogus = joinpath(mktempdir(), "does_not_exist")
    @test_throws Exception discover_notebooks(bogus)
end

@testitem "discover_notebooks: rejects a notebook path that escapes source (REQ-SEC-06)" begin
    using DocumenterSlate

    mktempdir() do root
        source = joinpath(root, "source")
        outside = joinpath(root, "outside")
        mkpath(source)
        mkpath(outside)

        escapee = joinpath(outside, "evil.jl")
        write(escapee, "# not a real notebook\n")

        # A symlink inside `source` pointing to a file outside `source`: without a
        # structural check, the naive glob would happily "discover" it.
        symlink(escapee, joinpath(source, "linked.jl"))

        legit = joinpath(source, "legit.jl")
        write(legit, "# a real notebook\n")

        @test_throws Exception discover_notebooks(source)
    end
end
