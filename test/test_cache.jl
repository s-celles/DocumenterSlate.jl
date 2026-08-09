@testitem "_gather_cache_components + _cache_fingerprint: stable for identical inputs" begin
    using DocumenterSlate
    using Test

    notebook = joinpath(@__DIR__, "fixtures", "notebooks", "simple.jl")
    project = resolve_notebook_project(notebook)
    output_options = SlateOutputOptions()
    meta = resolve_notebook_meta(notebook)

    c1 = DocumenterSlate._gather_cache_components(notebook, project, output_options, meta, true)
    c2 = DocumenterSlate._gather_cache_components(notebook, project, output_options, meta, true)

    @test DocumenterSlate._cache_fingerprint(c1) == DocumenterSlate._cache_fingerprint(c2)
    @test length(DocumenterSlate._cache_fingerprint(c1)) == 64   # hex sha256
    @test startswith(c1.documenterslate_version, string(pkgversion(DocumenterSlate)) * "+")
    @test length(last(split(c1.documenterslate_version, "+"))) == 64
end

@testitem "_cache_fingerprint changes when notebook bytes change" begin
    using DocumenterSlate
    using Test

    mktempdir() do dir
        path = joinpath(dir, "nb.jl")
        write(path, """
        try; import KaimonSlate; catch; error("no runtime"); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

        #%% code id=a
        1
        """)
        project = resolve_notebook_project(path)
        output_options = SlateOutputOptions()
        meta = resolve_notebook_meta(path)
        c1 = DocumenterSlate._gather_cache_components(path, project, output_options, meta, true)

        write(path, """
        try; import KaimonSlate; catch; error("no runtime"); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

        #%% code id=a
        2
        """)
        project2 = resolve_notebook_project(path)
        meta2 = resolve_notebook_meta(path)
        c2 = DocumenterSlate._gather_cache_components(path, project2, output_options, meta2, true)

        @test DocumenterSlate._cache_fingerprint(c1) != DocumenterSlate._cache_fingerprint(c2)
    end
end

@testitem "_cache_fingerprint changes when the :footer env fingerprint changes" begin
    using DocumenterSlate
    using Test

    mktempdir() do dir
        path = joinpath(dir, "nb.jl")
        write(path, """
        try; import KaimonSlate; catch; error("no runtime"); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

        #%% code id=a
        1

        # ╔═╡ Slate.env · notebook packages (auto-maintained — manage via the package panel)
        #   Example 0.5.3 8ac3fa42-a05e-49e1-b0e7-4b9b5c1d1f3f
        # ╚═╡
        """)
        project = resolve_notebook_project(path)
        @test project.kind == :footer   # sanity
        output_options = SlateOutputOptions()
        meta = resolve_notebook_meta(path)
        c1 = DocumenterSlate._gather_cache_components(path, project, output_options, meta, true)

        write(path, """
        try; import KaimonSlate; catch; error("no runtime"); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

        #%% code id=a
        1

        # ╔═╡ Slate.env · notebook packages (auto-maintained — manage via the package panel)
        #   Example 0.6.0 8ac3fa42-a05e-49e1-b0e7-4b9b5c1d1f3f
        # ╚═╡
        """)
        project2 = resolve_notebook_project(path)
        meta2 = resolve_notebook_meta(path)
        c2 = DocumenterSlate._gather_cache_components(path, project2, output_options, meta2, true)

        @test DocumenterSlate._cache_fingerprint(c1) != DocumenterSlate._cache_fingerprint(c2)
    end
end

@testitem "_cache_fingerprint changes when the :external env (Project.toml) changes" begin
    using DocumenterSlate
    using Test

    mktempdir() do dir
        path = joinpath(dir, "nb.jl")
        write(path, """
        try; import KaimonSlate; catch; error("no runtime"); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

        #%% code id=a
        1
        """)
        write(joinpath(dir, "Project.toml"), "name = \"Notebook\"\n")
        project = resolve_notebook_project(path)
        @test project.kind == :external   # sanity
        output_options = SlateOutputOptions()
        meta = resolve_notebook_meta(path)
        c1 = DocumenterSlate._gather_cache_components(path, project, output_options, meta, true)

        write(joinpath(dir, "Project.toml"), "name = \"NotebookChanged\"\n")
        project2 = resolve_notebook_project(path)
        c2 = DocumenterSlate._gather_cache_components(path, project2, output_options, meta, true)

        @test DocumenterSlate._cache_fingerprint(c1) != DocumenterSlate._cache_fingerprint(c2)
    end
end

@testitem "_cache_fingerprint changes when julia_version differs" begin
    using DocumenterSlate
    using Test

    notebook = joinpath(@__DIR__, "fixtures", "notebooks", "simple.jl")
    project = resolve_notebook_project(notebook)
    output_options = SlateOutputOptions()
    meta = resolve_notebook_meta(notebook)
    c = DocumenterSlate._gather_cache_components(notebook, project, output_options, meta, true)
    c_other = DocumenterSlate.CacheComponents(c.notebook_sha, c.env_fingerprint, "9.9.9",
                                               c.kaimonslate_version, c.documenterslate_version,
                                               c.render_option_hash)

    @test DocumenterSlate._cache_fingerprint(c) != DocumenterSlate._cache_fingerprint(c_other)
end

@testitem "_cache_fingerprint changes when kaimonslate_version or documenterslate_version differ" begin
    using DocumenterSlate
    using Test

    notebook = joinpath(@__DIR__, "fixtures", "notebooks", "simple.jl")
    project = resolve_notebook_project(notebook)
    output_options = SlateOutputOptions()
    meta = resolve_notebook_meta(notebook)
    c = DocumenterSlate._gather_cache_components(notebook, project, output_options, meta, true)

    c_ks = DocumenterSlate.CacheComponents(c.notebook_sha, c.env_fingerprint, c.julia_version,
                                            "9.9.9", c.documenterslate_version, c.render_option_hash)
    c_ds = DocumenterSlate.CacheComponents(c.notebook_sha, c.env_fingerprint, c.julia_version,
                                            c.kaimonslate_version, "9.9.9", c.render_option_hash)

    @test DocumenterSlate._cache_fingerprint(c) != DocumenterSlate._cache_fingerprint(c_ks)
    @test DocumenterSlate._cache_fingerprint(c) != DocumenterSlate._cache_fingerprint(c_ds)
end

@testitem "_cache_fingerprint changes when format/show_code/binds/fail_on_error differ" begin
    using DocumenterSlate
    using Test

    notebook = joinpath(@__DIR__, "fixtures", "notebooks", "simple.jl")
    project = resolve_notebook_project(notebook)
    meta = resolve_notebook_meta(notebook)

    base = DocumenterSlate._gather_cache_components(notebook, project, SlateOutputOptions(), meta, true)

    show_code_off = DocumenterSlate._gather_cache_components(
        notebook, project, SlateOutputOptions(; show_code = false), meta, true)
    @test DocumenterSlate._cache_fingerprint(base) != DocumenterSlate._cache_fingerprint(show_code_off)

    fail_off = DocumenterSlate._gather_cache_components(notebook, project, SlateOutputOptions(), meta, false)
    @test DocumenterSlate._cache_fingerprint(base) != DocumenterSlate._cache_fingerprint(fail_off)

    meta_binds = DocumenterSlate.NotebookMeta(meta.title, meta.order, meta.skip, meta.show_code,
                                               Dict{String,Any}("n" => 42))
    binds_changed = DocumenterSlate._gather_cache_components(notebook, project, SlateOutputOptions(),
                                                               meta_binds, true)
    @test DocumenterSlate._cache_fingerprint(base) != DocumenterSlate._cache_fingerprint(binds_changed)
end

@testitem "_gather_cache_components falls back cleanly when pkgversion is unavailable" begin
    using DocumenterSlate
    using Test

    # pkgversion(Main) is nothing for a non-package module — exercises the fallback path
    # without needing to fake a real package's version resolution.
    @test DocumenterSlate._fallback_version(Main) == "unknown"
end

@testitem "_write_cache_entry!/_read_cache_entry: round-trips page text and assets" begin
    using DocumenterSlate
    using Test

    mktempdir() do dir
        cache_dir = joinpath(dir, "slate_cache")
        notebook = joinpath(@__DIR__, "fixtures", "notebooks", "simple.jl")
        project = resolve_notebook_project(notebook)
        meta = resolve_notebook_meta(notebook)
        components = DocumenterSlate._gather_cache_components(
            notebook, project, SlateOutputOptions(), meta, true)
        fp = DocumenterSlate._cache_fingerprint(components)

        assets_src = joinpath(dir, "src_assets")
        mkpath(assets_src)
        write(joinpath(assets_src, "fig-01.png"), UInt8[1, 2, 3])

        DocumenterSlate._write_cache_entry!(cache_dir, "simple", fp, components,
                                             "# hello cache", assets_src)

        @test isfile(joinpath(cache_dir, "simple.md"))
        @test isfile(joinpath(cache_dir, "simple.cache.toml"))
        @test isfile(joinpath(cache_dir, "assets", "simple", "fig-01.png"))

        entry = DocumenterSlate._read_cache_entry(cache_dir, "simple", fp)
        @test entry !== nothing
        @test entry.page_text == "# hello cache"
        @test entry.assets_dir !== nothing
        @test read(joinpath(entry.assets_dir, "fig-01.png")) == UInt8[1, 2, 3]
    end
end

@testitem "_read_cache_entry: missing .cache.toml returns nothing" begin
    using DocumenterSlate
    using Test

    mktempdir() do dir
        @test DocumenterSlate._read_cache_entry(dir, "nope", "anyfingerprint") === nothing
    end
end

@testitem "_read_cache_entry: fingerprint mismatch returns nothing" begin
    using DocumenterSlate
    using Test

    mktempdir() do dir
        cache_dir = joinpath(dir, "cache")
        notebook = joinpath(@__DIR__, "fixtures", "notebooks", "simple.jl")
        project = resolve_notebook_project(notebook)
        meta = resolve_notebook_meta(notebook)
        components = DocumenterSlate._gather_cache_components(
            notebook, project, SlateOutputOptions(), meta, true)
        fp = DocumenterSlate._cache_fingerprint(components)

        DocumenterSlate._write_cache_entry!(cache_dir, "simple", fp, components, "stale content", nothing)

        @test DocumenterSlate._read_cache_entry(cache_dir, "simple", "a-different-fingerprint") === nothing
    end
end

@testitem "_read_cache_entry: corrupt .cache.toml returns nothing rather than throwing" begin
    using DocumenterSlate
    using Test

    mktempdir() do dir
        write(joinpath(dir, "broken.md"), "content")
        write(joinpath(dir, "broken.cache.toml"), "not [ valid toml")

        @test DocumenterSlate._read_cache_entry(dir, "broken", "whatever") === nothing
    end
end

@testitem "_write_cache_entry!/_read_cache_entry: cache_dir can be an arbitrary external directory (REQ-CACHE-04)" begin
    using DocumenterSlate
    using Test

    mktempdir() do dir
        external_cache = joinpath(dir, "restored-from-ci-artifact")
        notebook = joinpath(@__DIR__, "fixtures", "notebooks", "simple.jl")
        project = resolve_notebook_project(notebook)
        meta = resolve_notebook_meta(notebook)
        components = DocumenterSlate._gather_cache_components(
            notebook, project, SlateOutputOptions(), meta, true)
        fp = DocumenterSlate._cache_fingerprint(components)

        DocumenterSlate._write_cache_entry!(external_cache, "simple", fp, components, "content", nothing)
        entry = DocumenterSlate._read_cache_entry(external_cache, "simple", fp)

        @test entry !== nothing
        @test entry.page_text == "content"
    end
end
