try; import KaimonSlate; catch; error("This is a Kaimon Slate notebook — running it as plain Julia needs the KaimonSlate runtime in this environment. Add it with `import Pkg; Pkg.add(\"KaimonSlate\")`, or open it in Kaimon Slate."); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

#%% md id=title title
# Hello, DocumenterSlate

This page is not a mockup — it is a real [KaimonSlate.jl](https://github.com/kahliburke/KaimonSlate.jl)
notebook (`docs/notebooks/hello.jl` in this repository), executed headlessly by
[`build_slates`](@ref) and rendered into this Documenter page, exactly the way a package
maintainer would use `DocumenterSlate.jl` for their own tutorials.

#%% md id=intro
## A small computation

The cell below runs in a fresh Julia module, with its source shown above its output —
`show_code` defaults to `true` (REQ-REN-05).

#%% code id=calc
n = 12
factorial(n)

#%% md id=text
Standard output is captured too, fenced as plain text rather than a Documenter doctest
(REQ-REN-10) so a future change to this notebook's printed output never breaks the
package's own test suite the way a `jldoctest` block would.

#%% code id=greet
println("Hello from a real notebook, executed in CI.")
"nice to meet you"
