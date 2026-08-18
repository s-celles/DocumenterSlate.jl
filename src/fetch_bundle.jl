"""
    SlateBundle

A downloaded, verified, extracted notebook bundle, returned by [`fetch_slate_bundle`](@ref).

`directory` is the extracted bundle, `archive` the local `.tar.gz` it came from, `source` the
notebook's `.jl` file, `provenance` the parsed `PROVENANCE.toml`, and `verification` the
[`SlateBundleVerification`](@ref) produced while checking the archive.

Holding a `SlateBundle` means the bytes were checked, not that the code is safe: nothing in it
has been read, instantiated, or executed. Displaying one prints the remaining steps of the
download workflow.
"""
struct SlateBundle
    directory::String
    archive::String
    source::String
    provenance::Dict{String,Any}
    verification::SlateBundleVerification
end

function _bundle_archive_name(url::AbstractString)
    path = first(split(first(split(url, '#'; limit = 2)), '?'; limit = 2))
    name = basename(rstrip(path, '/') == path ? path : "")
    (isempty(name) || name != basename(name) || name in (".", "..")) && throw(ArgumentError(
        "cannot derive an archive filename from $(repr(url)): the URL must end in a " *
        "`<notebook>.tar.gz` filename",
    ))
    endswith(lowercase(name), ".tar.gz") || throw(ArgumentError(
        "slate bundles are `.tar.gz` archives; got $(repr(name))",
    ))
    return String(name)
end

function _acquire_bundle_archive(url::AbstractString, into::AbstractString)
    if isfile(url)
        name = _bundle_archive_name(abspath(url))
        destination = joinpath(into, name)
        abspath(url) == abspath(destination) || cp(url, destination; force = true)
        return destination
    end
    scheme = match(r"^([A-Za-z][A-Za-z0-9+.\-]*)://", url)
    scheme === nothing && throw(ArgumentError(
        "slate bundle does not exist and is not an `https://` URL: $(repr(url))",
    ))
    lowercase(scheme.captures[1]) == "https" || throw(ArgumentError(
        "slate bundles are fetched over `https://` only; got $(repr(url)). An unauthenticated " *
        "transport is not offered even though the bundle is checksum-verified afterwards",
    ))
    name = _bundle_archive_name(url)
    destination = joinpath(into, name)
    try
        Downloads.download(url, destination)
    catch error
        throw(ArgumentError("cannot download slate bundle $(repr(url)): " *
                            sprint(showerror, error)))
    end
    return destination
end

"""
    fetch_slate_bundle(url; into = mktempdir()) -> SlateBundle

Download a notebook bundle over `https`, verify it, and extract it — without executing notebook
code, instantiating its environment, or running package build scripts.

`url` may also be a local `.tar.gz` path, for a bundle you already downloaded by other means.

This is step 1 of the download workflow shown on every notebook page. It fails loudly rather
than returning an unverified bundle: the archive's entries are checked for links and nested
paths before extraction, every artifact is checked against `SHA256SUMS`, and the notebook source
and optional manifest are cross-checked against `PROVENANCE.toml` (see
[`verify_slate_bundle`](@ref)). The extracted directory is then verified in place.

What this deliberately does not do is launch anything. Verification establishes that the bytes
are the ones the publisher hashed; it establishes nothing about origin or intent. Judge
`bundle.provenance` and read `bundle.source` before running the notebook — displaying the
returned `SlateBundle` prints those remaining steps.

An `ArgumentError` is thrown on an unusable URL, a failed download, or any integrity or
structural failure.
"""
function fetch_slate_bundle(url::AbstractString; into::AbstractString = mktempdir())
    mkpath(into)
    archive = _acquire_bundle_archive(url, into)

    # Verify before extracting: a tampered archive must never reach the filesystem as a
    # notebook someone could open by mistake.
    verification = verify_slate_bundle(archive)

    slug = replace(basename(archive), r"\.tar\.gz$"i => "")
    directory = joinpath(into, slug)
    isdir(directory) && !isempty(readdir(directory)) && throw(ArgumentError(
        "refusing to extract over the existing directory $(repr(directory))",
    ))
    mkpath(directory)
    _safe_archive_headers(archive)
    try
        open(archive) do compressed
            Tar.extract(CodecZlib.GzipDecompressorStream(compressed), directory)
        end
    catch error
        rm(directory; recursive = true, force = true)
        throw(ArgumentError("cannot extract slate archive: $(sprint(showerror, error))"))
    end
    extracted = _verify_slate_directory(directory; archive = false)

    source_digest = extracted.provenance["source_sha256"]::String
    source_name = only(filter(extracted.artifacts) do name
        endswith(name, ".jl") &&
            bytes2hex(SHA.sha256(read(joinpath(directory, name)))) == source_digest
    end)

    return SlateBundle(directory, archive, joinpath(directory, source_name),
                       extracted.provenance, verification)
end

function Base.show(io::IO, ::MIME"text/plain", bundle::SlateBundle)
    provenance = bundle.provenance
    println(io, "SlateBundle: checksums and provenance coherence verified, nothing executed")
    println(io, "  directory: ", bundle.directory)
    println(io, "  source:    ", bundle.source)
    println(io)
    println(io, "Remaining steps of the workflow:")
    println(io)
    println(io, "  2. Judge the origin, which checksums cannot establish:")
    println(io, "       repository  = ", repr(get(provenance, "repository", "")))
    println(io, "       git_sha     = ", repr(get(provenance, "git_sha", "")))
    println(io, "       ci_produced = ", get(provenance, "ci_produced", false))
    println(io, "     Compare these against the repository you trust. Provenance is build")
    println(io, "     metadata, not a signature.")
    println(io)
    println(io, "  3. Read ", basename(bundle.source), " before running it. To browse it without")
    println(io, "     starting a worker or evaluating a cell:")
    println(io, "       KaimonSlate.serve_notebook(bundle.source; inactive = true)")
    println(io)
    println(io, "  4. Run deliberately, container first — see README.md in the bundle. This")
    print(io, "     package will not launch it for you.")
    return nothing
end
