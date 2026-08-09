# Download and inspect notebooks

Every generated notebook page begins with a distribution panel. It links to the original `.jl`
source, a reproducible `.tar.gz` archive, the resolved Julia environment, checksums, provenance,
and local instructions. The source bytes are copied unchanged.

## Verify before opening

Download the notebook directory or archive, then verify the files before using them:

```sh
sha256sum -c SHA256SUMS
```

`PROVENANCE.toml` records the repository, source commit, CI run identifier, build timestamp,
Julia and package versions, source digest, and manifest digest. A missing CI run identifier is
recorded honestly as a local build; this metadata is not a cryptographic attestation.

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
`SHA256SUMS` covers every artifact except itself. HTML/PDF exports, self-contained KaimonSlate
bundles, forge attestations, and a public verification API remain later roadmap work.
