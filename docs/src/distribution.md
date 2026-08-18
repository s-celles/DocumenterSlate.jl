# Download and inspect notebooks

Every generated notebook page begins with a distribution panel. It links to the original `.jl`
source, a reproducible `.tar.gz` archive, the resolved Julia environment, checksums, provenance,
and local instructions. The source bytes are copied unchanged.

The prominent **Download notebook** action downloads the archive only. **Inspect locally** is a
collapsed disclosure containing verification and inactive-preview commands; expanding it performs
no network request and executes nothing on the reader's machine.

!!! note "There is deliberately no one-click launch"
    DocumenterSlate never offers a "download and run this notebook from a URL" action, and this
    is a design decision rather than a missing feature. A KaimonSlate notebook is arbitrary
    Julia code: instantiating its environment can run package build scripts, and opening it in
    live mode can execute anything. The documentation therefore never emits a custom URL scheme,
    never contacts a local server, and never suggests piping a remote download into Julia.

    Fetching a notebook over the network is supported — see
    [Download from a URL](@ref) — but only as an explicit *verify-then-run* sequence you carry
    out yourself.

## Verify before opening

Download the notebook directory or archive, then verify the files before using them:

```sh
sha256sum -c SHA256SUMS
```

`PROVENANCE.toml` records the repository, source commit, CI run identifier, build timestamp,
Julia and package versions, source digest, and manifest digest. A missing CI run identifier is
recorded honestly as a local build; this metadata is not a cryptographic attestation.

DocumenterSlate can verify either the downloaded directory or its archive without evaluating
notebook cells or instantiating the environment:

```julia
using DocumenterSlate

result = verify_slate_bundle("notebook.tar.gz")
result.artifacts
result.provenance
```

Verification rejects missing, extra, modified, duplicated, or dangerously named files. For an
archive, links and nested paths are rejected before extraction. The source and optional manifest
digests are also checked against `PROVENANCE.toml`. An integrity failure raises `ArgumentError`.

## Download from a URL

Fetching a bundle over the network is fine; treating the fetch itself as a launch is not. Split
it into two steps that you control, and never chain them into a single command.

First, download the archive to a local path and check what you received:

```julia
using Downloads, DocumenterSlate

archive = Downloads.download("https://example.org/notebooks/downloads/demo/demo.tar.gz",
                             joinpath(mktempdir(), "demo.tar.gz"))
result = verify_slate_bundle(archive)
result.artifacts
result.provenance
```

[`verify_slate_bundle`](@ref) reads the archive's entries and rejects links, nested paths, and
non-regular files *before* extracting anything, then checks every artifact against `SHA256SUMS`
and cross-checks the notebook source and optional manifest against `PROVENANCE.toml`. It never
evaluates notebook cells and never instantiates the environment, so it is safe to run on a bundle
you have not yet reviewed. An integrity or structural failure raises `ArgumentError`.

Only after verification succeeds, and after reading the `.jl` source, extract the archive and use
one of the routes in [Run deliberately](@ref) — the container route first.

`result.provenance` tells you where the bundle claims to come from, not that the claim is true:
it is build metadata, not a signature. Compare `repository` and `git_sha` against the repository
you actually trust, and treat `ci_produced = false` as a locally built bundle. Until forge
attestations are authenticated, a URL is not evidence of origin — anyone can serve a well-formed
bundle.

## Inspect without evaluating cells

A KaimonSlate notebook is plain Julia source, so reading the `.jl` file is the safest first step.
KaimonSlate can also serve a static inspection view without starting a worker or evaluating cells:

```julia
using KaimonSlate
KaimonSlate.serve_notebook("notebook.jl"; inactive = true)
```

This deliberately is not a one-click launch mechanism. The documentation never emits a custom
URL scheme, contacts a local server, or suggests piping a remote download into Julia.

## Run deliberately

The downloaded `README.md` presents three routes in increasing order of host exposure:

1. a Podman container using the recorded Julia minor version;
2. the published `Project.toml` and `Manifest.toml` on the host;
3. the native `slate` application.

Instantiating a Julia environment can run package build scripts. Opening a notebook in live mode
can execute arbitrary code. A container reduces access to the host, but it does not make untrusted
code harmless; review the mount and network permissions as well.

## Reproducibility and current scope

Archives use sorted entries, a zero timestamp, normalized ownership and normalized file modes.
They are written in-process with `Tar.jl`, so every entry is a flat regular file and the build
does not depend on a system `tar`. `SHA256SUMS` covers every artifact except itself. HTML/PDF exports, self-contained KaimonSlate
bundles, and forge attestations remain later roadmap work. Until attestation authentication is
implemented, `verify_slate_bundle` rejects an archive containing an attestation rather than
presenting unverified metadata as trusted.
