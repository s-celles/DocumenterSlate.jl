function _git_output(args...)
    try
        return strip(read(`git $(args)`, String))
    catch
        return ""
    end
end

function _distribution_context(; repository = get(ENV, "GITHUB_REPOSITORY", ""),
                                 git_sha = get(ENV, "GITHUB_SHA", ""),
                                 run_id = get(ENV, "GITHUB_RUN_ID", ""),
                                 build_timestamp = get(ENV, "SOURCE_DATE_EPOCH", ""))
    isempty(repository) && (repository = _git_output("config", "--get", "remote.origin.url"))
    isempty(git_sha) && (git_sha = _git_output("rev-parse", "HEAD"))
    if isempty(build_timestamp)
        build_timestamp = _git_output("show", "-s", "--format=%cI", isempty(git_sha) ? "HEAD" : git_sha)
    end
    isempty(build_timestamp) && (build_timestamp = "unknown")
    return (; repository = String(repository), git_sha = String(git_sha),
            run_id = String(run_id), build_timestamp = String(build_timestamp))
end

function _write_sha256sums!(directory::AbstractString)
    artifact_names = sort!(filter(!=("SHA256SUMS"), readdir(directory)))
    sha256 = Dict{String,String}(
        name => bytes2hex(SHA.sha256(read(joinpath(directory, name)))) for name in artifact_names
    )
    open(joinpath(directory, "SHA256SUMS"), "w") do io
        for name in artifact_names
            println(io, sha256[name], "  ", name)
        end
    end
    return sha256
end

# Tar.jl writes normalized headers — flat paths, no `./` prefix, mtime 0, owner and group 0,
# and modes clamped to 0o644/0o755 — so the archive is reproducible without shelling out to a
# GNU tar that BSD and macOS hosts do not provide.
function _write_reproducible_archive!(directory::AbstractString, slug::AbstractString)
    archive_name = string(slug, ".tar.gz")::String
    archive_path = joinpath(directory, archive_name)
    mktempdir() do temporary
        temporary_archive = joinpath(temporary, archive_name)
        open(temporary_archive, "w") do raw
            gzip = CodecZlib.GzipCompressorStream(raw)
            try
                # Tar.create sorts entries and normalizes uid/gid, mtime and modes.
                # Keeping both archive layers in-process makes this work with BSD tar
                # on macOS and without an external tar executable on Windows.
                Tar.create(directory, gzip; portable = true)
            finally
                close(gzip)
            end
        end
        cp(temporary_archive, archive_path)
    end
    return archive_name
end

# The whole download story, defined once and shown in both places a reader can meet a bundle:
# the notebook page's panel, and the bundle's own README. Verification is step 2 of four rather
# than an optional aside, and step 4 never chains a launch onto the fetch — each step is an act
# the reader performs, in order, having read the previous one.
function _workflow_steps(slug::AbstractString;
                         archive_url::Union{Nothing,AbstractString} = nothing,
                         relative_archive::Union{Nothing,AbstractString} = nothing,
                         downloaded::Bool = false)
    source_name = string(slug, ".jl")::String
    archive_name = string(slug, ".tar.gz")::String
    steps = Pair{String,Vector{String}}[]

    if downloaded
        push!(steps, "Download" => [
            "You already have this directory. If you also kept the archive it came from, verify",
            "that before trusting anything extracted from it:",
            "",
            "```julia",
            "using DocumenterSlate",
            "verify_slate_bundle($(repr(archive_name)))",
            "```",
        ])
    else
        url = archive_url === nothing ?
              "https://<this site>/$(something(relative_archive, archive_name))" : archive_url
        located = archive_url === nothing ?
                  ["Copy the **Download notebook** link above — it is `$(something(relative_archive, archive_name))`",
                   "on this site — and fetch it:"] :
                  ["Fetch the archive:"]
        push!(steps, "Download" => vcat([
            "One call downloads the archive, checks every artifact against `SHA256SUMS`,",
            "cross-checks `PROVENANCE.toml`, and extracts the result. It evaluates no cell and",
            "instantiates no environment.",
            "",
        ], located, [
            "",
            "```julia",
            "using DocumenterSlate",
            "bundle = fetch_slate_bundle($(repr(url)))",
            "```",
        ]))
    end

    verify_body = downloaded ?
        [
            "Check the files against the checksums the bundle carries:",
            "",
            "```sh",
            "sha256sum -c SHA256SUMS",
            "```",
            "",
            "or, equivalently, from Julia:",
            "",
            "```julia",
            "using DocumenterSlate",
            "verify_slate_bundle(\".\")",
            "```",
            "",
            "Then read `PROVENANCE.toml`. Checksums prove the bytes are intact; they say nothing",
            "about *origin*. Compare `repository` and `git_sha` against the repository you",
            "actually trust, and treat `ci_produced = false` as a locally built bundle.",
            "Provenance is build metadata, not a signature — anyone can serve a well-formed",
            "bundle.",
        ] :
        [
            "Step 1 raises rather than returning an unverified bundle, so reaching this step means",
            "the bytes are intact. If you took the download directory instead, check it with the",
            "checksums it carries:",
            "",
            "```sh",
            "sha256sum -c SHA256SUMS",
            "```",
            "",
            "What checksums cannot establish, either way, is *origin*:",
            "",
            "```julia",
            "bundle.provenance[\"repository\"]",
            "bundle.provenance[\"git_sha\"]",
            "bundle.provenance[\"ci_produced\"]",
            "```",
            "",
            "Compare `repository` and `git_sha` against the repository you actually trust, and",
            "treat `ci_produced = false` as a locally built bundle. Provenance is build metadata,",
            "not a signature — anyone can serve a well-formed bundle.",
        ]
    push!(steps, "Verify" => verify_body)

    read_target = downloaded ? repr(source_name) : "bundle.source"
    push!(steps, "Read" => [
        "A KaimonSlate notebook is plain Julia source, and reading `$(source_name)` is the only",
        "step that tells you what the code would actually do. KaimonSlate can also serve a static",
        "view that starts no worker and evaluates no cell:",
        "",
        "```julia",
        "using KaimonSlate",
        "KaimonSlate.serve_notebook($(read_target); inactive = true)",
        "```",
    ])

    push!(steps, "Run deliberately" => [
        "Only after steps 2 and 3. Instantiating the environment may run package build scripts,",
        "and opening the notebook in live mode may execute anything. The three routes below are",
        "ordered by how much of your host they expose.",
        "",
        "*Isolated container* (recommended) — keeps package installation and notebook inspection",
        "off the host. The image opens the notebook in inactive mode; it evaluates no cell:",
        "",
        "```sh",
        "podman build -t $(slug)-inspect . && podman run --rm -it -p 8765:8765 $(slug)-inspect",
        "```",
        "",
        "Alternatively, open `devcontainer.json` in a compatible editor.",
        "",
        "*Pinned host environment* — uses the published project and manifest, but runs package",
        "build scripts and notebook code with your host account's permissions:",
        "",
        "```sh",
        "julia --project=. -e 'using Pkg; Pkg.instantiate()'",
        "julia --project=. -e 'using KaimonSlate; KaimonSlate.serve_notebook($(repr(source_name)))'",
        "```",
        "",
        "*Native application* — installing and opening the application executes code with your",
        "host account's permissions:",
        "",
        "```sh",
        "julia -e 'using Pkg; Pkg.Registry.add(Pkg.Registry.RegistrySpec(url=\"https://github.com/kahliburke/SlateRegistry\")); Pkg.Apps.add(\"KaimonSlate\")'",
        "slate --own $(source_name)",
        "```",
        "",
        "A container reduces access to the host; it does not make untrusted code harmless. Review",
        "the mount and network permissions too.",
    ])

    return steps
end

function _workflow_markdown(steps; indent::AbstractString = "", heading::Bool = false)
    io = IOBuffer()
    for (index, (title, lines)) in enumerate(steps)
        label = string(index, ". ", title)
        println(io, indent, heading ? "## " * label : "**" * label * "**")
        println(io, rstrip(indent))
        for line in lines
            println(io, isempty(line) ? rstrip(indent) : indent * line)
        end
        index == length(steps) || println(io, rstrip(indent))
    end
    return String(take!(io))
end

function _write_distribution!(notebook_path::AbstractString,
                              project::NotebookProjectResolution,
                              output_dir::AbstractString, slug::AbstractString;
                              environment_dir::Union{Nothing,AbstractString} = nothing,
                              kwargs...)
    ctx = _distribution_context(; kwargs...)
    relative_directory = joinpath("downloads", String(slug))
    directory = joinpath(output_dir, relative_directory)
    isdir(directory) && rm(directory; recursive = true)
    mkpath(directory)

    source_name = string(slug, ".jl")::String
    cp(notebook_path, joinpath(directory, source_name))
    if environment_dir !== nothing
        cp(joinpath(environment_dir, "Project.toml"), joinpath(directory, "Project.toml"))
        cp(joinpath(environment_dir, "Manifest.toml"), joinpath(directory, "Manifest.toml"))
    elseif project.kind == :external
        project_dir = something(project.project_dir)
        cp(joinpath(project_dir, "Project.toml"), joinpath(directory, "Project.toml"))
        project.manifest_path === nothing ||
            cp(project.manifest_path, joinpath(directory, "Manifest.toml"))
    else
        open(joinpath(directory, "Slate.env.toml"), "w") do io
            TOML.print(io, Dict("dependency" => something(project.env_footer)))
        end
    end

    dockerfile = """FROM julia:$(VERSION.major).$(VERSION.minor)
WORKDIR /work
COPY . /work
RUN julia --project=. -e 'using Pkg; Pkg.instantiate()'
EXPOSE 8765
ENTRYPOINT ["julia", "--project=.", "-e", "using KaimonSlate; KaimonSlate.serve_notebook(ARGS[1]; host=\\\"0.0.0.0\\\", inactive = true)"]
CMD [$(repr(source_name))]
"""
    write(joinpath(directory, "Dockerfile"), dockerfile)

    devcontainer = """{
  "name": $(repr("$(slug) notebook inspection")),
  "build": { "dockerfile": "Dockerfile" },
  "forwardPorts": [8765],
  "remoteUser": "root"
}
"""
    write(joinpath(directory, "devcontainer.json"), devcontainer)

    readme = """# $(slug) — local inspection

This directory contains untrusted notebook code. Verify the files before opening them, then read
the source before running it. The four steps below are the whole story, in order; the site this
bundle came from shows the same chain.

$(_workflow_markdown(_workflow_steps(slug; downloaded = true); heading = true))
"""
    write(joinpath(directory, "README.md"), readme)

    source_sha = bytes2hex(SHA.sha256(read(joinpath(directory, source_name))))
    manifest_sha = isfile(joinpath(directory, "Manifest.toml")) ?
                   bytes2hex(SHA.sha256(read(joinpath(directory, "Manifest.toml")))) : ""
    provenance = Dict(
        "repository" => ctx.repository,
        "git_sha" => ctx.git_sha,
        "run_id" => ctx.run_id,
        "build_timestamp" => ctx.build_timestamp,
        "source_sha256" => source_sha,
        "manifest_sha256" => manifest_sha,
        "julia_version" => string(VERSION),
        "kaimonslate_version" => _fallback_version(KaimonSlate),
        "documenterslate_version" => _documenterslate_build_id(),
        "environment_kind" => string(project.kind),
        "ci_produced" => !isempty(ctx.run_id),
    )
    open(joinpath(directory, "PROVENANCE.toml"), "w") do io
        TOML.print(io, provenance)
    end

    _write_sha256sums!(directory)
    _write_reproducible_archive!(directory, slug)
    sha256 = _write_sha256sums!(directory)
    return (; directory, relative_directory, sha256)
end

function _html_text(value::AbstractString)
    return replace(value, '&' => "&amp;", '<' => "&lt;", '>' => "&gt;", '"' => "&quot;",
                   '\'' => "&#39;")
end

function _url_path(value::AbstractString)
    io = IOBuffer()
    for byte in codeunits(value)
        char = Char(byte)
        if isascii(char) && (isletter(char) || isdigit(char) || char in ('-', '_', '.', '~', '/'))
            write(io, byte)
        else
            print(io, '%', uppercase(string(byte; base = 16, pad = 2)))
        end
    end
    return String(take!(io))
end

function _distribution_panel(dist, slug::AbstractString;
                             canonical::Union{Nothing,AbstractString} = nothing)
    relative = replace(dist.relative_directory, '\\' => '/')
    source_name = string(slug, ".jl")::String
    archive_name = string(slug, ".tar.gz")::String
    relative_archive = replace(joinpath(relative, archive_name), '\\' => '/')
    archive_url = _url_path(relative_archive)
    absolute_url = canonical === nothing ? nothing :
                   (endswith(canonical, "/") ? canonical : canonical * "/") * archive_url
    safe_archive_name = _html_text(archive_name)
    safe_source_name = _html_text(source_name)
    io = IOBuffer()
    println(io, "```@raw html")
    println(io, "<div class=\"slate-actions\">")
    println(io, "  <a class=\"button is-link slate-download-button\" href=\"", archive_url,
            "\" download>Download notebook</a>")
    println(io, "  <details class=\"slate-inspect\">")
    println(io, "    <summary>Inspect locally</summary>")
    println(io, "    <p><strong>Do not run the notebook before reviewing it.</strong> If you already hold the files, these two calls verify the archive and open KaimonSlate's inactive view, which starts no worker and evaluates no cell. The full download-to-run workflow is below.</p>")
    println(io, "    <pre><code>using DocumenterSlate")
    println(io, "verify_slate_bundle(\"", safe_archive_name, "\")</code></pre>")
    println(io, "    <pre><code>using KaimonSlate")
    println(io, "KaimonSlate.serve_notebook(\"", safe_source_name,
            "\"; inactive = true)</code></pre>")
    println(io, "  </details>")
    println(io, "</div>")
    println(io, "```")
    println(io, "")
    println(io, "!!! warning \"Download, verify, read, then run — in that order\"")
    println(io, "    This notebook is arbitrary code. Instantiating its environment may run package build scripts, and live opening may execute cells. There is deliberately no one-click launch: each step below is an act you perform after reading the previous one.")
    println(io, "")
    print(io, _workflow_markdown(
        _workflow_steps(slug; archive_url = absolute_url, relative_archive = relative_archive);
        indent = "    "))
    println(io, "")
    println(io, "    [Download source](", relative, "/", source_name, ") · [Checksums](", relative,
            "/SHA256SUMS) · [Provenance](", relative, "/PROVENANCE.toml) · [Local instructions](",
            relative, "/README.md)")
    println(io, "")
    println(io, "    | Artifact | SHA-256 |")
    println(io, "    |:--|:--|")
    for name in sort!(collect(keys(dist.sha256)))
        println(io, "    | [`", name, "`](", relative, "/", name, ") | `", dist.sha256[name], "` |")
    end
    return String(take!(io))
end

function _decorate_page(page_text::AbstractString, dist, slug::AbstractString;
                        canonical::Union{Nothing,AbstractString} = nothing)
    return _distribution_panel(dist, slug; canonical) * "\n\n" * String(page_text)
end
