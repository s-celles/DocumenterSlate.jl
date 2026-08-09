# DocumenterSlate.jl

DocumenterSlate.jl publishes KaimonSlate.jl reactive notebooks as native Documenter.jl
pages in CI.

Read the [documentation](https://s-celles.github.io/DocumenterSlate.jl/) for installation,
usage, examples, and the project's security model.

Generated notebook pages provide verified source downloads, reproducible archives, provenance,
and a KaimonSlate inspection command that does not evaluate notebook cells.

Verify a downloaded directory or archive before inspection with
`verify_slate_bundle("notebook.tar.gz")`.
