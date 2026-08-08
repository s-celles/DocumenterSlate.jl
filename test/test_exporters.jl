@testitem "AbstractSlateExporter: type hierarchy" begin
    using DocumenterSlate

    @test TextualReplayExporter <: AbstractSlateExporter
end

@testitem "TextualReplayExporter: spec-shaped default timeout" begin
    using DocumenterSlate

    exporter = TextualReplayExporter()

    @test exporter isa AbstractSlateExporter
    @test exporter.timeout == 900
    @test exporter.timeout isa Int
end

@testitem "TextualReplayExporter: custom timeout override" begin
    using DocumenterSlate

    exporter = TextualReplayExporter(timeout = 60)

    @test exporter.timeout == 60
end

@testitem "TextualReplayExporter: non-positive timeout is rejected" begin
    using DocumenterSlate

    @test_throws ArgumentError TextualReplayExporter(timeout = 0)
    @test_throws ArgumentError TextualReplayExporter(timeout = -1)
end
