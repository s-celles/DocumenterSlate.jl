@testitem "distribution: source, environment, provenance, and checksums are published" begin
    using DocumenterSlate
    using SHA
    using TOML

    mktempdir() do root
        notebook_dir = joinpath(root, "notebook")
        mkpath(notebook_dir)
        source = joinpath(notebook_dir, "example.jl")
        source_bytes = Vector{UInt8}(codeunits("#%% code id=x\n1 + 1\n"))
        write(source, source_bytes)
        write(joinpath(notebook_dir, "Project.toml"), "[deps]\n")
        write(joinpath(notebook_dir, "Manifest.toml"), "julia_version = \"1.12.0\"\n")

        project = resolve_notebook_project(source)
        dist = DocumenterSlate._write_distribution!(
            source, project, joinpath(root, "output"), "example";
            repository = "s-celles/DocumenterSlate.jl",
            git_sha = "abc123",
            run_id = "42",
            build_timestamp = "2026-08-09T00:00:00Z",
        )

        @test read(joinpath(dist.directory, "example.jl")) == source_bytes
        @test isfile(joinpath(dist.directory, "Project.toml"))
        @test isfile(joinpath(dist.directory, "Manifest.toml"))
        @test isfile(joinpath(dist.directory, "example.tar.gz"))

        provenance = TOML.parsefile(joinpath(dist.directory, "PROVENANCE.toml"))
        @test provenance["repository"] == "s-celles/DocumenterSlate.jl"
        @test provenance["git_sha"] == "abc123"
        @test provenance["run_id"] == "42"
        @test provenance["build_timestamp"] == "2026-08-09T00:00:00Z"

        sums = readlines(joinpath(dist.directory, "SHA256SUMS"))
        @test !isempty(sums)
        for line in sums
            digest, filename = split(line; limit = 2)
            @test digest == bytes2hex(SHA.sha256(read(joinpath(dist.directory, strip(filename)))))
        end
        @test Set(keys(dist.sha256)) == Set(strip(last(split(line; limit = 2))) for line in sums)
        @test haskey(dist.sha256, "example.tar.gz")
        @test occursin("Isolated container", read(joinpath(dist.directory, "README.md"), String))
        @test occursin("Pinned host environment", read(joinpath(dist.directory, "README.md"), String))
        @test occursin("Native application", read(joinpath(dist.directory, "README.md"), String))

        second = DocumenterSlate._write_distribution!(
            source, project, joinpath(root, "second"), "example";
            repository = "s-celles/DocumenterSlate.jl",
            git_sha = "abc123",
            run_id = "42",
            build_timestamp = "2026-08-09T00:00:00Z",
        )
        @test read(joinpath(dist.directory, "example.tar.gz")) ==
              read(joinpath(second.directory, "example.tar.gz"))
    end
end

@testitem "distribution panel: offers verification and inactive inspection, never one-click execution" begin
    using DocumenterSlate

    dist = (
        relative_directory = joinpath("downloads", "example"),
        sha256 = Dict(
            "example.jl" => repeat("a", 64),
            "example.tar.gz" => repeat("d", 64),
            "PROVENANCE.toml" => repeat("b", 64),
            "SHA256SUMS" => repeat("c", 64),
        ),
    )
    panel = DocumenterSlate._distribution_panel(dist, "example")

    @test occursin("[Download source]", panel)
    @test occursin(".tar.gz", panel)
    @test occursin("sha256sum -c SHA256SUMS", panel)
    @test occursin("inactive = true", panel)
    @test occursin("arbitrary code", panel)
    @test !occursin("slate://", panel)
    @test !occursin("127.0.0.1", panel)
    @test !occursin("curl", panel)
end
