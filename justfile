# DocumenterSlate.jl — main entry points.
# Run `just` (no args) to list available recipes.

default:
    @just --list

# Run the test suite (TestItemRunner-based; see test/runtests.jl).
test:
    julia --project=. -e 'using Pkg; Pkg.test()'

# Render notebooks (execution=:auto, no secrets) then build the docs site
# (execution=:never, consumes only the cache render just populated) -- the same two steps
# spec.md §9's two-job CI workflow runs as separate jobs, run here sequentially for a
# local build. `deploydocs` inside docs/make.jl safely no-ops outside a real CI
# environment (Documenter's own auto-detection), so this never actually publishes.
docs:
    julia --project=docs docs/render.jl
    julia --project=docs docs/make.jl
