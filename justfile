# DocumenterSlate.jl — main entry points.
# Run `just` (no args) to list available recipes.

default:
    @just --list

# Run the test suite (TestItemRunner-based; see test/runtests.jl).
test:
    julia --project=. -e 'using Pkg; Pkg.test()'

# Build the documentation. Not set up yet — docs/make.jl does not exist.
docs:
    @echo "docs/ is not set up yet — no docs/make.jl in this repo."
