```@raw html
---
layout: home

hero:
  name: DocumenterSlate.jl
  text: Reactive notebooks, native documentation
  tagline: Build KaimonSlate notebooks in isolated CI workers, then publish verified, reproducible output as first-class Documenter pages.
  actions:
    - theme: brand
      text: Get started
      link: "#Quick-start"
    - theme: alt
      text: See a real notebook
      link: /notebooks/hello/
  image:
    src: /logo.svg
    alt: A notebook rendered as a Documenter page

features:
  - icon: 📖
    title: Native Documenter pages
    details: Searchable, linkable notebook output lives beside the rest of your package documentation—not in an iframe or a separate app.
    link: /notebooks/hello/
  - icon: 🛡️
    title: Split, safer CI
    details: Execute notebooks without deployment secrets, then build and deploy from the resulting cache in a separate job.
    link: /security/
  - icon: 📦
    title: Reproducible environments
    details: Every cache miss runs in its own Julia process with the notebook's adjacent project activated and an explicit environment allowlist.
  - icon: ✓
    title: Verifiable downloads
    details: Publish source, environment, checksums, and provenance so readers can verify a bundle before inspecting or running it.
    link: /distribution/
  - icon: 🧩
    title: Pages or embeds
    details: Add every notebook to navigation automatically, or place one inside an authored guide with the @slate directive.
    link: "#Embed-a-notebook"
  - icon: ⚡
    title: Cache-aware builds
    details: Rebuild only when notebook inputs change; the deploy job is forbidden from silently executing a cache miss.
---
```

## Quick start

DocumenterSlate is not yet registered. Add it directly from GitHub to the environment that
builds your documentation:

```julia
import Pkg
Pkg.add(url = "https://github.com/s-celles/DocumenterSlate.jl")
```

Render the notebooks before calling `makedocs`:

```julia
using Documenter, DocumenterSlate

result = build_slates(
    SlateBuildOptions(;
        source = joinpath(@__DIR__, "notebooks"),
        output = joinpath(@__DIR__, "src", "notebooks"),
        worker_environment = Dict("LANG" => "C.UTF-8"),
    ),
)

makedocs(;
    sitename = "MyPkg.jl",
    plugins = [SlatePlugin(result)],
    pages = [
        "Home" => "index.md",
        "Notebooks" => result.pages,
    ],
)
```

Each cache miss runs in a separate Julia process with the notebook's adjacent project activated.
The parent environment is denied by default; `worker_environment` is the explicit allowlist.

## How the build stays predictable

1. `build_slates` discovers notebooks and hashes every relevant input.
2. A render job executes cache misses without documentation deployment credentials.
3. A separate deploy job consumes that exact cache with `execution = :never` and publishes the
   generated Markdown, assets, and downloadable bundles through Documenter.

This documentation site uses that two-job workflow itself. The [Notebooks](notebooks/hello.md)
section is generated from the real KaimonSlate sources in this repository, not from fixtures or
hand-written output.

!!! warning "Treat notebooks as code"
    Notebook cells are arbitrary Julia code. Read the [security model](security.md) before using
    the reference workflow for your own package, and verify downloaded bundles before opening
    them in a live runtime.

## Embed a notebook

Install `SlatePlugin(result)` as above, then place a pre-rendered notebook inside an authored
page:

````markdown
```@slate
notebook = "analysis.jl"
```
````

Use `@slate-download` with the same `notebook = "analysis.jl"` configuration when the page should
contain only the download and inactive-inspection panel.

## Explore further

- [See a generated notebook](notebooks/hello.md) to inspect the rendered result.
- [Understand downloads and verification](distribution.md) before sharing bundles.
- [Read the security model](security.md) before adopting the CI workflow.
- Use the [API reference](api.md) when you need the exact configuration surface.
