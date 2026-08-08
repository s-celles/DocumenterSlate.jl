@testitem "fixtures parse under upstream KaimonSlate.parse_report" begin
    using KaimonSlate

    fixtures_dir = joinpath(@__DIR__, "fixtures", "notebooks")
    fixture_files = [
        "simple.jl",
        "with_roles.jl",
        "with_bind.jl",
        "broken_cell.jl",
        "hidden_cell.jl",
        "_skip_me.jl",
    ]

    for name in fixture_files
        path = joinpath(fixtures_dir, name)
        @test isfile(path)
        text = read(path, String)
        report = KaimonSlate.parse_report(text)
        @test !isempty(report.cells)
    end
end
