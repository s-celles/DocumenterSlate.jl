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
