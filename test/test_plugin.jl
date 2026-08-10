@testitem "SlatePlugin is accepted by Documenter and retains build pages" begin
    using Documenter
    using DocumenterSlate

    result = SlateBuildResult(["Notebook" => "notebook.md"])
    plugin = SlatePlugin(result)

    @test plugin isa Documenter.Plugin
    @test plugin.slates === result
    @test SlatePlugin().slates === nothing

    mktempdir() do root
        source = joinpath(root, "src")
        mkpath(source)
        write(joinpath(source, "index.md"), "# Home\n")
        makedocs(; root, source = "src", build = "build", sitename = "Plugin test",
                 plugins = [plugin], pages = ["Home" => "index.md"], warnonly = true,
                 remotes = nothing,
                 format = Documenter.HTML(; repolink = "https://example.invalid",
                                          inventory_version = "test"))
        @test isfile(joinpath(root, "build", "index.html"))
    end
end


@testitem "@slate-download embeds the verified download panel in an authored page" begin
    using Documenter
    using DocumenterSlate

    mktempdir() do root
        source = joinpath(root, "src")
        rendered = joinpath(source, "notebooks")
        download = joinpath(rendered, "downloads", "hello")
        mkpath(download)
        write(joinpath(download, "hello.jl"), "# notebook\n")
        write(joinpath(download, "hello.tar.gz"), "archive")
        write(joinpath(download, "PROVENANCE.toml"), "git_sha = \"abc\"\n")
        write(joinpath(download, "README.md"), "# Instructions\n")
        write(joinpath(download, "SHA256SUMS"), repeat("a", 64) * "  hello.jl\n" *
                                                     repeat("b", 64) * "  hello.tar.gz\n")
        write(joinpath(source, "index.md"), """
        # Home

        ```@slate-download
        notebook = "hello.jl"
        ```
        """)
        result = SlateBuildResult(["Hello" => "hello.md"], rendered)
        makedocs(; root, source = "src", build = "build", sitename = "Download expander test",
                 plugins = [SlatePlugin(result)], pages = ["Home" => "index.md"],
                 remotes = nothing,
                 format = Documenter.HTML(; repolink = "https://example.invalid",
                                          inventory_version = "test"))

        html = read(joinpath(root, "build", "index.html"), String)
        @test occursin("Download notebook", html)
        @test occursin("notebooks/downloads/hello/hello.tar.gz", html)
        @test !occursin("@slate-download", html)
    end
end


@testitem "@slate embeds a pre-rendered notebook as native Documenter content" begin
    using Documenter
    using DocumenterSlate

    mktempdir() do root
        source = joinpath(root, "src")
        rendered = joinpath(root, "rendered")
        mkpath(source)
        mkpath(rendered)
        write(joinpath(rendered, "hello.md"), "# Embedded notebook\n\nSearchable slate text.\n")
        write(joinpath(source, "index.md"), """
        # Home

        ```@slate
        notebook = "hello.jl"
        ```
        """)
        result = SlateBuildResult(["Embedded notebook" => "hello.md"], rendered)
        makedocs(; root, source = "src", build = "build", sitename = "Expander test",
                 plugins = [SlatePlugin(result)], pages = ["Home" => "index.md"],
                 remotes = nothing,
                 format = Documenter.HTML(; repolink = "https://example.invalid",
                                          inventory_version = "test"))

        html = read(joinpath(root, "build", "index.html"), String)
        @test occursin("Embedded notebook", html)
        @test occursin("Searchable slate text", html)
        @test !occursin("@slate", html)
    end
end
