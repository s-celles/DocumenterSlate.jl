@testitem "documentation entry points avoid expected local-build warnings" begin
    using TOML

    root = dirname(dirname(@__FILE__))
    notebook_project = joinpath(root, "docs", "notebooks", "Project.toml")
    @test isfile(notebook_project)
    @test haskey(TOML.parsefile(notebook_project)["deps"], "KaimonSlate")

    make_source = read(joinpath(root, "docs", "make.jl"), String)
    @test occursin(r"if\s+get\(ENV,\s*\"CI\"", make_source)

    readme = read(joinpath(root, "README.md"), String)
    @test occursin("https://s-celles.github.io/DocumenterSlate.jl/", readme)
end
