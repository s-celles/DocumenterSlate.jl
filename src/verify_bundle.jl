"""
    SlateBundleVerification

Successful result returned by [`verify_slate_bundle`](@ref).

`artifacts` contains the checksum-covered filenames, `provenance` is the parsed
`PROVENANCE.toml`, and `archive` records whether verification required safe extraction of a
`.tar.gz` archive.
"""
struct SlateBundleVerification
    artifacts::Vector{String}
    provenance::Dict{String,Any}
    archive::Bool
end

function _safe_archive_headers(archive::AbstractString)
    headers = try
        open(archive) do compressed
            Tar.list(CodecZlib.GzipDecompressorStream(compressed))
        end
    catch error
        throw(ArgumentError("cannot read slate archive $(repr(archive)): $(sprint(showerror, error))"))
    end
    for header in headers
        path = replace(header.path, '\\' => '/')
        normalized = startswith(path, "./") ? path[3:end] : path
        if header.type == :directory && isempty(normalized)
            continue
        end
        header.type == :file || throw(ArgumentError(
            "unsafe slate archive entry $(repr(header.path)): only regular files are allowed",
        ))
        (isempty(normalized) || startswith(normalized, "/") || basename(normalized) != normalized ||
         normalized in (".", "..")) && throw(ArgumentError(
            "unsafe slate archive path $(repr(header.path)): entries must be top-level filenames",
        ))
    end
    return headers
end

function _parse_sha256sums(directory::AbstractString)
    checksum_path = joinpath(directory, "SHA256SUMS")
    isfile(checksum_path) || throw(ArgumentError("bundle has no SHA256SUMS"))
    checksums = Dict{String,String}()
    for (line_number, line) in enumerate(readlines(checksum_path))
        parts = split(line; limit = 2)
        length(parts) == 2 || throw(ArgumentError("invalid SHA256SUMS line $line_number"))
        digest, raw_name = parts
        name = strip(raw_name)
        occursin(r"^[0-9a-f]{64}$", digest) ||
            throw(ArgumentError("invalid SHA-256 digest on line $line_number"))
        (isempty(name) || basename(name) != name || name in (".", "..", "SHA256SUMS")) &&
            throw(ArgumentError("unsafe checksum filename on line $line_number"))
        haskey(checksums, name) && throw(ArgumentError("duplicate checksum for $(repr(name))"))
        checksums[name] = digest
    end
    isempty(checksums) && throw(ArgumentError("SHA256SUMS is empty"))
    return checksums
end

function _verify_slate_directory(directory::AbstractString; archive::Bool)
    entries = readdir(directory)
    for name in entries
        path = joinpath(directory, name)
        (islink(path) || !isfile(path)) && throw(ArgumentError(
            "unsafe bundle entry $(repr(name)): only regular top-level files are allowed",
        ))
    end

    checksums = _parse_sha256sums(directory)
    actual = Set(filter(!=("SHA256SUMS"), entries))
    expected = Set(keys(checksums))
    actual == expected || throw(ArgumentError(
        "SHA256SUMS inventory does not match bundle files (missing=$(collect(setdiff(actual, expected))), extra=$(collect(setdiff(expected, actual))))",
    ))
    for (name, expected_digest) in checksums
        actual_digest = bytes2hex(SHA.sha256(read(joinpath(directory, name))))
        actual_digest == expected_digest ||
            throw(ArgumentError("SHA-256 mismatch for $(repr(name))"))
    end

    provenance_path = joinpath(directory, "PROVENANCE.toml")
    isfile(provenance_path) || throw(ArgumentError("bundle has no PROVENANCE.toml"))
    provenance = TOML.parsefile(provenance_path)
    source_digest = get(provenance, "source_sha256", nothing)
    source_digest isa String || throw(ArgumentError("PROVENANCE.toml has no source_sha256"))
    source_candidates = filter(name -> endswith(name, ".jl"), keys(checksums))
    count(name -> checksums[name] == source_digest, source_candidates) == 1 ||
        throw(ArgumentError("source_sha256 does not identify exactly one notebook source"))

    manifest_digest = get(provenance, "manifest_sha256", nothing)
    manifest_digest isa String || throw(ArgumentError("PROVENANCE.toml has no manifest_sha256"))
    if "Manifest.toml" in actual
        checksums["Manifest.toml"] == manifest_digest ||
            throw(ArgumentError("manifest_sha256 does not match Manifest.toml"))
    else
        isempty(manifest_digest) ||
            throw(ArgumentError("provenance records a manifest but the bundle has none"))
    end

    any(name -> occursin("attestation", lowercase(name)), entries) && throw(ArgumentError(
        "bundle contains an attestation, but this release cannot authenticate attestations yet",
    ))
    return SlateBundleVerification(sort!(collect(keys(checksums))), provenance, archive)
end

"""
    verify_slate_bundle(path) -> SlateBundleVerification

Verify a downloaded DocumenterSlate distribution directory or `.tar.gz` archive without
executing notebook or package code. Verification requires an exhaustive `SHA256SUMS`, checks
every listed artifact, and cross-checks the notebook source and optional manifest against
`PROVENANCE.toml`. Archives containing links, nested paths, or non-regular entries are rejected
before extraction.

An `ArgumentError` is thrown on any integrity or structural failure. Forge attestations are not
accepted until DocumenterSlate can authenticate them; provenance metadata alone is not treated as
a signature.
"""
function verify_slate_bundle(path::AbstractString)
    resolved = abspath(path)
    if isdir(resolved)
        return _verify_slate_directory(resolved; archive = false)
    end
    isfile(resolved) || throw(ArgumentError("slate bundle does not exist: $(repr(path))"))
    endswith(lowercase(resolved), ".tar.gz") ||
        throw(ArgumentError("slate bundle must be a directory or .tar.gz archive"))
    _safe_archive_headers(resolved)
    return mktempdir() do directory
        try
            open(resolved) do compressed
                Tar.extract(CodecZlib.GzipDecompressorStream(compressed), directory)
            end
        catch error
            throw(ArgumentError("cannot extract slate archive: $(sprint(showerror, error))"))
        end
        _verify_slate_directory(directory; archive = true)
    end
end
