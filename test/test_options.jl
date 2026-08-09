@testitem "SlateBuildOptions: required source/output, spec-shaped defaults" begin
    using DocumenterSlate

    opts = SlateBuildOptions(source = "notebooks", output = "src/notebooks")

    @test opts.source == "notebooks"
    @test opts.output == "src/notebooks"
    @test opts.include == ["*.jl"]
    @test opts.exclude == ["_*.jl"]
    @test opts.execution == :auto
    @test opts.fail_on_error == true
    @test opts.allow_remote == false
    @test opts.nworkers isa Integer
    @test opts.nworkers >= 1
    @test opts.exporter === nothing
end

@testitem "SlateBuildOptions: source and output are required (no default)" begin
    using DocumenterSlate

    @test_throws Exception SlateBuildOptions(output = "src/notebooks")
    @test_throws Exception SlateBuildOptions(source = "notebooks")
    @test_throws Exception SlateBuildOptions()
end

@testitem "SlateBuildOptions: execution is validated" begin
    using DocumenterSlate

    for valid in (:auto, :always, :never)
        opts = SlateBuildOptions(source = "notebooks", output = "src/notebooks", execution = valid)
        @test opts.execution == valid
    end

    @test_throws ArgumentError SlateBuildOptions(
        source = "notebooks", output = "src/notebooks", execution = :sometimes,
    )
end

@testitem "SlateBuildOptions: custom keyword overrides" begin
    using DocumenterSlate

    opts = SlateBuildOptions(
        source = "notebooks",
        output = "src/notebooks",
        include = ["*.slate.jl"],
        exclude = ["_draft*.jl"],
        execution = :never,
        cache_dir = "custom_cache",
        nworkers = 4,
        fail_on_error = false,
        allow_remote = true,
    )

    @test opts.include == ["*.slate.jl"]
    @test opts.exclude == ["_draft*.jl"]
    @test opts.execution == :never
    @test opts.cache_dir == "custom_cache"
    @test opts.nworkers == 4
    @test opts.fail_on_error == false
    @test opts.allow_remote == true
end

@testitem "SlateOutputOptions: spec-shaped defaults" begin
    using DocumenterSlate

    opts = SlateOutputOptions()

    @test opts.format == :documenter
    @test opts.interactivity == :frozen
    @test opts.show_code == true
    @test opts.assets == :files
    @test opts.provenance == true
    @test opts.downloads == [:html, :pdf, :source]
end

@testitem "SlateOutputOptions: format/interactivity/assets are validated" begin
    using DocumenterSlate

    for valid in (:documenter, :embed, :iframe)
        @test SlateOutputOptions(format = valid).format == valid
    end
    @test_throws ArgumentError SlateOutputOptions(format = :nope)

    for valid in (:frozen, :client)
        @test SlateOutputOptions(interactivity = valid).interactivity == valid
    end
    @test_throws ArgumentError SlateOutputOptions(interactivity = :nope)

    for valid in (:files, :base64)
        @test SlateOutputOptions(assets = valid).assets == valid
    end
    @test_throws ArgumentError SlateOutputOptions(assets = :nope)
end

@testitem "SlateOutputOptions: custom keyword overrides" begin
    using DocumenterSlate

    opts = SlateOutputOptions(
        format = :embed,
        interactivity = :client,
        show_code = false,
        assets = :base64,
        provenance = false,
        downloads = [:html],
    )

    @test opts.format == :embed
    @test opts.interactivity == :client
    @test opts.show_code == false
    @test opts.assets == :base64
    @test opts.provenance == false
    @test opts.downloads == [:html]
end
