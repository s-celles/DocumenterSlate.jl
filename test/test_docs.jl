@testitem "documentation entry points avoid expected local-build warnings" begin
    using TOML

    root = dirname(dirname(@__FILE__))
    notebook_project = joinpath(root, "docs", "notebooks", "Project.toml")
    @test isfile(notebook_project)
    @test haskey(TOML.parsefile(notebook_project)["deps"], "KaimonSlate")

    make_source = read(joinpath(root, "docs", "make.jl"), String)
    @test occursin(r"if\s+get\(ENV,\s*\"CI\"", make_source)
    @test occursin("edit_link = \"main\"", make_source)
    @test occursin("assets/documenterslate.css", make_source)

    stylesheet = joinpath(root, "docs", "src", "assets", "documenterslate.css")
    @test isfile(stylesheet)
    css = read(stylesheet, String)
    @test occursin(".slate-download-button", css)
    @test occursin(".slate-inspect", css)
    @test occursin("prefers-color-scheme: dark", css)
    @test occursin("@media", css)

    readme = read(joinpath(root, "README.md"), String)
    @test occursin("https://s-celles.github.io/DocumenterSlate.jl/", readme)

    distribution = joinpath(root, "docs", "src", "distribution.md")
    @test isfile(distribution)
    @test occursin("inactive = true", read(distribution, String))
    @test occursin("\"Distribution\" => \"distribution.md\"", make_source)
    @test occursin("verify_slate_bundle", read(distribution, String))
end
