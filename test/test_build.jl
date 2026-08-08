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
        opts = SlateBuildOptions(; source = source, output = outdir, slate_toml = slate_toml,
                                  cache_dir = joinpath(root, "cache"))
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

        opts = SlateBuildOptions(; source = source, output = joinpath(root, "out"),
                                  cache_dir = joinpath(root, "cache"))
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
        opts = SlateBuildOptions(; source = source, output = outdir, fail_on_error = false,
                                  cache_dir = joinpath(root, "cache"))
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
        opts = SlateBuildOptions(; source = source, output = outdir, slate_toml = slate_toml,
                                  cache_dir = joinpath(root, "cache"))
        result = build_slates(opts)

        @test length(result.pages) == 1
        @test !isfile(joinpath(outdir, "with_bind.md"))
    end
end

@testitem "build_slates: execution=:never with a cold cache errors clearly (REQ-EXE-10)" begin
    using DocumenterSlate
    using Test

    mktempdir() do root
        source = joinpath(root, "notebooks")
        mkpath(source)
        cp(joinpath(@__DIR__, "fixtures", "notebooks", "simple.jl"), joinpath(source, "simple.jl"))

        opts = SlateBuildOptions(; source = source, output = joinpath(root, "out"),
                                  cache_dir = joinpath(root, "cache-that-does-not-exist"),
                                  execution = :never)
        @test_throws ArgumentError build_slates(opts)
    end
end

@testitem "build_slates: :auto populates the cache; a later :never build is a pure cache hit" begin
    using DocumenterSlate
    using Test

    mktempdir() do root
        source = joinpath(root, "notebooks")
        mkpath(source)
        cp(joinpath(@__DIR__, "fixtures", "notebooks", "simple.jl"), joinpath(source, "simple.jl"))

        cache_dir = joinpath(root, "cache")
        opts_auto = SlateBuildOptions(; source = source, output = joinpath(root, "out1"),
                                       cache_dir = cache_dir)
        result1 = build_slates(opts_auto)
        @test isfile(joinpath(cache_dir, "simple.md"))
        @test isfile(joinpath(cache_dir, "simple.cache.toml"))

        # A completely fresh output directory, execution = :never: can only succeed by
        # reading the cache populated above -- :never cannot execute anything by
        # construction, so success here is structural proof of a cache hit, not an
        # instrumentation-dependent assertion.
        opts_never = SlateBuildOptions(; source = source, output = joinpath(root, "out2"),
                                        cache_dir = cache_dir, execution = :never)
        result2 = build_slates(opts_never)

        @test isfile(joinpath(root, "out2", "simple.md"))
        @test read(joinpath(root, "out2", "simple.md"), String) ==
              read(joinpath(root, "out1", "simple.md"), String)
        @test result1.pages == result2.pages
    end
end

@testitem "build_slates: a mutated notebook invalidates the cache and re-executes" begin
    using DocumenterSlate
    using Test

    mktempdir() do root
        source = joinpath(root, "notebooks")
        mkpath(source)
        notebook = joinpath(source, "nb.jl")
        write(notebook, """
        try; import KaimonSlate; catch; error("no runtime"); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

        #%% code id=calc
        1 + 1
        """)

        cache_dir = joinpath(root, "cache")
        opts = SlateBuildOptions(; source = source, output = joinpath(root, "out"), cache_dir = cache_dir)
        build_slates(opts)
        @test occursin("2", read(joinpath(root, "out", "nb.md"), String))

        write(notebook, """
        try; import KaimonSlate; catch; error("no runtime"); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

        #%% code id=calc
        1 + 100
        """)
        build_slates(opts)
        @test occursin("101", read(joinpath(root, "out", "nb.md"), String))
        @test occursin("101", read(joinpath(cache_dir, "nb.md"), String))   # cache refreshed too
    end
end

@testitem "build_slates: execution=:always always re-executes even with a warm cache" begin
    using DocumenterSlate
    using Test

    mktempdir() do root
        source = joinpath(root, "notebooks")
        mkpath(source)
        notebook = joinpath(source, "nb.jl")
        write(notebook, """
        try; import KaimonSlate; catch; error("no runtime"); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

        #%% code id=c
        println("ran")
        1
        """)

        cache_dir = joinpath(root, "cache")
        opts_auto = SlateBuildOptions(; source = source, output = joinpath(root, "out"), cache_dir = cache_dir)
        build_slates(opts_auto)   # populate cache

        # Rewrite the cached page to a sentinel value; if :always incorrectly served from
        # cache, the output would contain the sentinel instead of a freshly rendered page.
        write(joinpath(cache_dir, "nb.md"), "SENTINEL: should never be served by :always")

        opts_always = SlateBuildOptions(; source = source, output = joinpath(root, "out2"),
                                         cache_dir = cache_dir, execution = :always)
        build_slates(opts_always)

        content = read(joinpath(root, "out2", "nb.md"), String)
        @test !occursin("SENTINEL", content)
        @test occursin("ran", content)
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

@testitem "build_slates: nworkers=2 produces the same output as nworkers=1 (REQ-EXE-07)" begin
    using DocumenterSlate
    using Distributed
    using Test

    mktempdir() do root
        source = joinpath(root, "notebooks")
        mkpath(source)
        for name in ("simple.jl", "with_roles.jl", "with_bind.jl")
            cp(joinpath(@__DIR__, "fixtures", "notebooks", name), joinpath(source, name))
        end

        opts_seq = SlateBuildOptions(; source = source, output = joinpath(root, "out_seq"),
                                      cache_dir = joinpath(root, "cache_seq"))
        result_seq = build_slates(opts_seq)

        opts_par = SlateBuildOptions(; source = source, output = joinpath(root, "out_par"),
                                      cache_dir = joinpath(root, "cache_par"), nworkers = 2)
        nprocs_before = nprocs()
        result_par = build_slates(opts_par)

        @test nprocs() == nprocs_before   # no leaked workers
        @test Set(result_seq.pages) == Set(result_par.pages)
        for (_, relpath) in result_seq.pages
            @test read(joinpath(root, "out_seq", relpath), String) ==
                  read(joinpath(root, "out_par", relpath), String)
        end
    end
end

@testitem "build_slates: nworkers=2 with a failing notebook still raises SlateExecutionError, not RemoteException, and cleans up workers" begin
    using DocumenterSlate
    using Distributed
    using Test

    mktempdir() do root
        source = joinpath(root, "notebooks")
        mkpath(source)
        cp(joinpath(@__DIR__, "fixtures", "notebooks", "simple.jl"), joinpath(source, "simple.jl"))
        cp(joinpath(@__DIR__, "fixtures", "notebooks", "broken_cell.jl"),
           joinpath(source, "broken_cell.jl"))

        opts = SlateBuildOptions(; source = source, output = joinpath(root, "out"), nworkers = 2,
                                  cache_dir = joinpath(root, "cache"))
        nprocs_before = nprocs()
        err = try
            build_slates(opts)
            nothing
        catch e
            e
        end

        @test err isa DocumenterSlate.SlateExecutionError
        @test err.cell_id == "boom"
        @test nprocs() == nprocs_before   # workers torn down even on failure
    end
end
