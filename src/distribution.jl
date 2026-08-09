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

function _write_reproducible_archive!(directory::AbstractString, slug::AbstractString)
    archive_name = string(slug, ".tar.gz")::String
    archive_path = joinpath(directory, archive_name)
    mktempdir() do temporary
        temporary_archive = joinpath(temporary, archive_name)
        run(`tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner --mode=u=rwX,go=rX --format=ustar -czf $temporary_archive -C $directory .`)
        cp(temporary_archive, archive_path)
    end
    return archive_name
end

function _write_distribution!(notebook_path::AbstractString,
                              project::NotebookProjectResolution,
                              output_dir::AbstractString, slug::AbstractString; kwargs...)
    ctx = _distribution_context(; kwargs...)
    relative_directory = joinpath("downloads", String(slug))
    directory = joinpath(output_dir, relative_directory)
    isdir(directory) && rm(directory; recursive = true)
    mkpath(directory)

    source_name = string(slug, ".jl")::String
    cp(notebook_path, joinpath(directory, source_name))
    if project.kind == :external
        project_dir = something(project.project_dir)
        cp(joinpath(project_dir, "Project.toml"), joinpath(directory, "Project.toml"))
        project.manifest_path === nothing ||
            cp(project.manifest_path, joinpath(directory, "Manifest.toml"))
    else
        open(joinpath(directory, "Slate.env.toml"), "w") do io
            TOML.print(io, Dict("dependency" => something(project.env_footer)))
        end
    end

    readme = """# $(slug) — local inspection

This directory contains untrusted notebook code. Verify the files before opening them.
Installing the environment may execute package build scripts; opening the notebook in live mode
may execute arbitrary code.

Verify the downloaded files:

```sh
sha256sum -c SHA256SUMS
```

Inspect without starting a worker or executing cells:

```julia
using KaimonSlate
KaimonSlate.serve_notebook(\"$(source_name)\"; inactive = true)
```

## 1. Isolated container (recommended)

This keeps notebook execution out of the host, but package installation still executes code in
the container:

```sh
podman run --rm -it -p 8765:8765 -v \"\$PWD:/work:Z\" -w /work julia:$(VERSION.major).$(VERSION.minor) \\
  julia --project=. -e 'using Pkg; Pkg.instantiate(); using KaimonSlate; KaimonSlate.serve_notebook(\"$(source_name)\"; host=\"0.0.0.0\")'
```

## 2. Pinned host environment

This uses the published project and manifest, but runs package build scripts and notebook code
with your host account's permissions:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. -e 'using KaimonSlate; KaimonSlate.serve_notebook(\"$(source_name)\")'
```

## 3. Native application

Installing and opening the application executes code with your host account's permissions:

```sh
julia -e 'using Pkg; Pkg.Registry.add(Pkg.Registry.RegistrySpec(url=\"https://github.com/kahliburke/SlateRegistry\")); Pkg.Apps.add(\"KaimonSlate\")'
slate --own $(source_name)
```
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

function _distribution_panel(dist, slug::AbstractString)
    relative = replace(dist.relative_directory, '\\' => '/')
    source_name = string(slug, ".jl")::String
    archive_name = string(slug, ".tar.gz")::String
    archive_url = _url_path(replace(joinpath(relative, archive_name), '\\' => '/'))
    safe_archive_name = _html_text(archive_name)
    safe_source_name = _html_text(source_name)
    io = IOBuffer()
    println(io, "```@raw html")
    println(io, "<div class=\"slate-actions\">")
    println(io, "  <a class=\"button is-link slate-download-button\" href=\"", archive_url,
            "\" download>Download notebook</a>")
    println(io, "  <details class=\"slate-inspect\">")
    println(io, "    <summary>Inspect locally</summary>")
    println(io, "    <p><strong>Do not run the notebook before reviewing it.</strong> Verify the archive, then use KaimonSlate's inactive view, which does not start a worker or evaluate cells.</p>")
    println(io, "    <pre><code>using DocumenterSlate")
    println(io, "verify_slate_bundle(\"", safe_archive_name, "\")</code></pre>")
    println(io, "    <pre><code>using KaimonSlate")
    println(io, "KaimonSlate.serve_notebook(\"", safe_source_name,
            "\"; inactive = true)</code></pre>")
    println(io, "  </details>")
    println(io, "</div>")
    println(io, "```")
    println(io, "")
    println(io, "!!! warning \"Download and inspect safely\"")
    println(io, "    This notebook is arbitrary code. Instantiating its environment may run package build scripts, and live opening may execute cells.")
    println(io, "")
    println(io, "    [Download source](", relative, "/", source_name, ") · [Checksums](", relative,
            "/SHA256SUMS) · [Provenance](", relative, "/PROVENANCE.toml) · [Local instructions](",
            relative, "/README.md)")
    println(io, "")
    println(io, "    Verify after downloading the directory: `sha256sum -c SHA256SUMS`.")
    println(io, "")
    println(io, "    Inspect without starting a worker or executing cells:")
    println(io, "")
    println(io, "    ```julia")
    println(io, "    using KaimonSlate")
    println(io, "    KaimonSlate.serve_notebook(\"", source_name, "\"; inactive = true)")
    println(io, "    ```")
    println(io, "")
    println(io, "    | Artifact | SHA-256 |")
    println(io, "    |:--|:--|")
    for name in sort!(collect(keys(dist.sha256)))
        println(io, "    | [`", name, "`](", relative, "/", name, ") | `", dist.sha256[name], "` |")
    end
    return String(take!(io))
end

function _decorate_page(page_text::AbstractString, dist, slug::AbstractString)
    return _distribution_panel(dist, slug) * "\n\n" * String(page_text)
end
