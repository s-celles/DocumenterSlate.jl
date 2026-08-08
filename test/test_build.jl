@testitem "build_slates: end-to-end over 3 notebooks produces .md files and ordered pages" begin
    using DocumenterSlate
    using Test

    mktempdir() do root
        source = joinpath(root, "notebooks")
        mkpath(source)
        for name in ("simple.jl", "with_roles.jl", "with_bind.jl")
            cp(joinpath(@__DIR__, "fixtures", "notebooks", name), joinpath(source, name))
        end
        slate_toml = joinpath(root, "slate.toml")
        write(slate_toml, """
        [[notebook]]
        path = "with_roles.jl"
        order = 1
        """)

        outdir = joinpath(root, "out")
        opts = SlateBuildOptions(; source = source, output = outdir, slate_toml = slate_toml)
        result = build_slates(opts)

        @test result isa SlateBuildResult
        @test length(result.pages) == 3
        relpaths = last.(result.pages)
        @test Set(relpaths) == Set(["simple.md", "with_roles.md", "with_bind.md"])
        for rp in relpaths
            @test isfile(joinpath(outdir, rp))
        end
        @test first(result.pages).first == "A Notebook With Roles"

        content = read(joinpath(outdir, "simple.md"), String)
        @test occursin("A simple notebook", content)
        @test occursin("1 + 1", content)   # show_code default true
        @test occursin("2", content)       # cell value
    end
end

@testitem "build_slates: fail_on_error=true (default) stops the build with SlateExecutionError" begin
    using DocumenterSlate
    using Test

    mktempdir() do root
        source = joinpath(root, "notebooks")
        mkpath(source)
        cp(joinpath(@__DIR__, "fixtures", "notebooks", "broken_cell.jl"),
           joinpath(source, "broken_cell.jl"))

        opts = SlateBuildOptions(; source = source, output = joinpath(root, "out"))
        err = try
            build_slates(opts)
            nothing
        catch e
            e
        end
        @test err isa DocumenterSlate.SlateExecutionError
        @test err.cell_id == "boom"
    end
end

@testitem "build_slates: fail_on_error=false records the error visibly and keeps building" begin
    using DocumenterSlate
    using Test

    mktempdir() do root
        source = joinpath(root, "notebooks")
        mkpath(source)
        cp(joinpath(@__DIR__, "fixtures", "notebooks", "broken_cell.jl"),
           joinpath(source, "broken_cell.jl"))

        outdir = joinpath(root, "out")
        opts = SlateBuildOptions(; source = source, output = outdir, fail_on_error = false)
        result = build_slates(opts)

        @test length(result.pages) == 1
        content = read(joinpath(outdir, "broken_cell.md"), String)
        @test occursin("!!! error", content)
        @test occursin("boom", content)
    end
end

@testitem "build_slates: skip=true notebooks are excluded from output files and pages" begin
    using DocumenterSlate
    using Test

    mktempdir() do root
        source = joinpath(root, "notebooks")
        mkpath(source)
        cp(joinpath(@__DIR__, "fixtures", "notebooks", "simple.jl"), joinpath(source, "simple.jl"))
        cp(joinpath(@__DIR__, "fixtures", "notebooks", "with_bind.jl"),
           joinpath(source, "with_bind.jl"))
        slate_toml = joinpath(root, "slate.toml")
        write(slate_toml, """
        [[notebook]]
        path = "with_bind.jl"
        skip = true
        """)

        outdir = joinpath(root, "out")
        opts = SlateBuildOptions(; source = source, output = outdir, slate_toml = slate_toml)
        result = build_slates(opts)

        @test length(result.pages) == 1
        @test !isfile(joinpath(outdir, "with_bind.md"))
    end
end

@testitem "build_slates: execution=:never errors clearly (no cache support until M2)" begin
    using DocumenterSlate
    using Test

    mktempdir() do root
        source = joinpath(root, "notebooks")
        mkpath(source)
        cp(joinpath(@__DIR__, "fixtures", "notebooks", "simple.jl"), joinpath(source, "simple.jl"))

        opts = SlateBuildOptions(; source = source, output = joinpath(root, "out"),
                                  execution = :never)
        @test_throws ArgumentError build_slates(opts)
    end
end

@testitem "build_slates: a non-:documenter format errors clearly (not implemented until later milestones)" begin
    using DocumenterSlate
    using Test

    mktempdir() do root
        source = joinpath(root, "notebooks")
        mkpath(source)
        cp(joinpath(@__DIR__, "fixtures", "notebooks", "simple.jl"), joinpath(source, "simple.jl"))

        opts = SlateBuildOptions(; source = source, output = joinpath(root, "out"))
        @test_throws ArgumentError build_slates(opts, SlateOutputOptions(; format = :iframe))
    end
end
