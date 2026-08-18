@testitem "fetch bundle: downloads, verifies, and extracts without executing anything" begin
    using DocumenterSlate

    mktempdir() do root
        notebook_dir = joinpath(root, "notebook")
        mkpath(notebook_dir)
        source = joinpath(notebook_dir, "example.jl")
        write(source, "#%% code id=x\nerror(\"this notebook must never be executed\")\n")
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
        archive = joinpath(dist.directory, "example.tar.gz")

        into = joinpath(root, "fetched")
        bundle = fetch_slate_bundle(archive; into = into)

        @test bundle isa SlateBundle
        @test isdir(bundle.directory)
        @test isfile(bundle.source)
        @test basename(bundle.source) == "example.jl"
        @test read(bundle.source, String) == read(source, String)
        @test bundle.verification.archive
        @test bundle.provenance["repository"] == "s-celles/DocumenterSlate.jl"
        @test bundle.provenance["git_sha"] == "abc123"
        @test bundle.provenance["ci_produced"] === true

        # The extracted directory is verified in place: nothing was added, removed, or
        # instantiated on the way out of the archive.
        @test verify_slate_bundle(bundle.directory).artifacts == bundle.verification.artifacts
        @test Set(readdir(bundle.directory)) ==
              Set(vcat(bundle.verification.artifacts, "SHA256SUMS"))
    end
end

@testitem "fetch bundle: refuses tampered archives before extracting them" begin
    using DocumenterSlate

    mktempdir() do root
        notebook_dir = joinpath(root, "notebook")
        mkpath(notebook_dir)
        source = joinpath(notebook_dir, "example.jl")
        write(source, "#%% code id=x\n1 + 1\n")
        write(joinpath(notebook_dir, "Project.toml"), "[deps]\n")

        project = resolve_notebook_project(source)
        dist = DocumenterSlate._write_distribution!(
            source, project, joinpath(root, "output"), "example";
            repository = "s-celles/DocumenterSlate.jl", git_sha = "abc123",
            run_id = "", build_timestamp = "2026-08-09T00:00:00Z",
        )
        archive = joinpath(dist.directory, "example.tar.gz")

        tampered = joinpath(root, "tampered.tar.gz")
        bytes = read(archive)
        bytes[end - 8] ⊻= 0xff
        write(tampered, bytes)

        into = joinpath(root, "fetched")
        @test_throws ArgumentError fetch_slate_bundle(tampered; into = into)
        # A rejected bundle leaves no extracted notebook source behind.
        @test !isdir(into) || isempty(filter(endswith(".jl"), readdir(into)))
    end
end

@testitem "fetch bundle: rejects unauthenticated and unsafe sources" begin
    using DocumenterSlate

    mktempdir() do root
        @test_throws ArgumentError fetch_slate_bundle(
            "http://example.org/downloads/demo/demo.tar.gz"; into = root)
        @test_throws ArgumentError fetch_slate_bundle(
            "ftp://example.org/demo.tar.gz"; into = root)
        @test_throws ArgumentError fetch_slate_bundle(
            "https://example.org/downloads/demo/demo.zip"; into = root)
        @test_throws ArgumentError fetch_slate_bundle(
            "https://example.org/downloads/demo/"; into = root)
        @test_throws ArgumentError fetch_slate_bundle(joinpath(root, "absent.tar.gz");
                                                      into = root)
    end
end

@testitem "fetch bundle: shows the remaining workflow steps and never a launch command" begin
    using DocumenterSlate

    mktempdir() do root
        notebook_dir = joinpath(root, "notebook")
        mkpath(notebook_dir)
        source = joinpath(notebook_dir, "example.jl")
        write(source, "#%% code id=x\n1 + 1\n")
        write(joinpath(notebook_dir, "Project.toml"), "[deps]\n")

        project = resolve_notebook_project(source)
        dist = DocumenterSlate._write_distribution!(
            source, project, joinpath(root, "output"), "example";
            repository = "s-celles/DocumenterSlate.jl", git_sha = "abc123",
            run_id = "", build_timestamp = "2026-08-09T00:00:00Z",
        )

        bundle = fetch_slate_bundle(joinpath(dist.directory, "example.tar.gz");
                                    into = joinpath(root, "fetched"))
        shown = sprint(show, MIME("text/plain"), bundle)

        # The remaining steps of the workflow are named, in order, with the notebook's own paths.
        @test occursin("verified", lowercase(shown))
        @test occursin("2.", shown)
        @test occursin("3.", shown)
        @test occursin("4.", shown)
        @test occursin("example.jl", shown)
        @test occursin("ci_produced", shown)
        # A locally built bundle is reported as such rather than silently trusted.
        @test occursin("false", shown)
        # Fetching never runs the notebook, so the display must not read as a launch.
        @test !occursin("serve_notebook(\"$(bundle.source)\")", shown)
        @test occursin("inactive = true", shown)
    end
end

@testitem "workflow: every notebook page presents the whole chain in order" begin
    using DocumenterSlate

    mktempdir() do root
        notebook_dir = joinpath(root, "notebook")
        mkpath(notebook_dir)
        source = joinpath(notebook_dir, "example.jl")
        write(source, "#%% code id=x\n1 + 1\n")
        write(joinpath(notebook_dir, "Project.toml"), "[deps]\n")

        project = resolve_notebook_project(source)
        dist = DocumenterSlate._write_distribution!(
            source, project, joinpath(root, "output"), "example";
            repository = "s-celles/DocumenterSlate.jl", git_sha = "abc123",
            run_id = "42", build_timestamp = "2026-08-09T00:00:00Z",
        )

        panel = DocumenterSlate._distribution_panel(dist, "example")
        for step in ("1. Download", "2. Verify", "3. Read", "4. Run")
            @test occursin(step, panel)
        end
        # Verification sits between download and launch, and the launch step is never chained
        # onto the fetch.
        @test findfirst("1. Download", panel).start < findfirst("2. Verify", panel).start <
              findfirst("3. Read", panel).start < findfirst("4. Run", panel).start
        @test occursin("fetch_slate_bundle", panel)
        # The run step never chains a fetch onto a launch: downloading and running stay
        # separate acts the reader performs in order.
        @test !occursin("fetch_slate_bundle", panel[findfirst("4. Run", panel).start:end])

        # Without a canonical site URL the panel still shows the chain, using the archive's
        # relative path and telling the reader where the absolute URL comes from.
        @test occursin("example.tar.gz", panel)
        @test occursin("Download notebook", panel)

        canonical = DocumenterSlate._distribution_panel(
            dist, "example"; canonical = "https://example.org/docs/")
        @test occursin("https://example.org/docs/downloads/example/example.tar.gz", canonical)
        @test occursin("fetch_slate_bundle(\"https://example.org/docs/downloads/example/example.tar.gz\")",
                       canonical)
    end
end

@testitem "workflow: the downloaded README repeats the same chain" begin
    using DocumenterSlate

    mktempdir() do root
        notebook_dir = joinpath(root, "notebook")
        mkpath(notebook_dir)
        source = joinpath(notebook_dir, "example.jl")
        write(source, "#%% code id=x\n1 + 1\n")
        write(joinpath(notebook_dir, "Project.toml"), "[deps]\n")

        project = resolve_notebook_project(source)
        dist = DocumenterSlate._write_distribution!(
            source, project, joinpath(root, "output"), "example";
            repository = "s-celles/DocumenterSlate.jl", git_sha = "abc123",
            run_id = "42", build_timestamp = "2026-08-09T00:00:00Z",
        )

        readme = read(joinpath(dist.directory, "README.md"), String)
        for step in ("1. Download", "2. Verify", "3. Read", "4. Run")
            @test occursin(step, readme)
        end
        @test occursin("verify_slate_bundle", readme)
        @test occursin("ci_produced", readme)
        @test occursin("inactive = true", readme)
        # The three execution routes stay ordered by host exposure inside the final step.
        podman = findfirst("podman", readme).start
        pinned = findfirst("Pkg; Pkg.instantiate()", readme).start
        native = findfirst("Pkg.Apps.add", readme).start
        @test podman < pinned < native
    end
end

@testitem "options: canonical is an https site URL or nothing" begin
    using DocumenterSlate

    @test SlateOutputOptions().canonical === nothing
    @test SlateOutputOptions(canonical = "https://example.org/docs/").canonical ==
          "https://example.org/docs/"
    # A trailing slash is normalized so the archive URL never doubles it.
    @test SlateOutputOptions(canonical = "https://example.org/docs").canonical ==
          "https://example.org/docs/"
    @test_throws ArgumentError SlateOutputOptions(canonical = "http://example.org/docs/")
    @test_throws ArgumentError SlateOutputOptions(canonical = "example.org/docs/")
    @test_throws ArgumentError SlateOutputOptions(canonical = "")
end
