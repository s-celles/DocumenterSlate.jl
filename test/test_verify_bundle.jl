@testitem "verify bundle: accepts published directory and reproducible archive" begin
    using DocumenterSlate

    mktempdir() do root
        notebook_dir = joinpath(root, "notebook")
        mkpath(notebook_dir)
        source = joinpath(notebook_dir, "example.jl")
        write(source, "#%% code id=x\n1 + 1\n")
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

        directory_result = verify_slate_bundle(dist.directory)
        @test directory_result.archive == false
        @test "example.jl" in directory_result.artifacts
        @test directory_result.provenance["git_sha"] == "abc123"

        archive_result = verify_slate_bundle(joinpath(dist.directory, "example.tar.gz"))
        @test archive_result.archive == true
        @test "example.jl" in archive_result.artifacts
        @test archive_result.provenance["manifest_sha256"] != ""
    end
end

@testitem "verify bundle: rejects tampering and incomplete checksum inventories" begin
    using DocumenterSlate

    mktempdir() do root
        source = joinpath(root, "example.jl")
        write(source, "#%% code id=x\n1 + 1\n")
        write(joinpath(root, "Project.toml"), "[deps]\n")
        project = resolve_notebook_project(source)
        dist = DocumenterSlate._write_distribution!(source, project, joinpath(root, "output"), "example")

        write(joinpath(dist.directory, "example.jl"), "tampered")
        @test_throws ArgumentError verify_slate_bundle(dist.directory)

        rm(joinpath(dist.directory, "example.tar.gz"))
        lines = filter(line -> !occursin("README.md", line),
                       readlines(joinpath(dist.directory, "SHA256SUMS")))
        write(joinpath(dist.directory, "SHA256SUMS"), join(lines, '\n') * "\n")
        @test_throws ArgumentError verify_slate_bundle(dist.directory)
    end
end

@testitem "verify bundle: rejects unsafe archive entries before extraction" begin
    using DocumenterSlate

    mktempdir() do root
        payload = joinpath(root, "payload")
        mkpath(payload)
        write(joinpath(payload, "target"), "outside")
        symlink("target", joinpath(payload, "link"))
        archive = joinpath(root, "unsafe.tar.gz")
        run(`tar -czf $archive -C $payload .`)

        @test_throws ArgumentError verify_slate_bundle(archive)
    end
end
