try; import KaimonSlate; catch; error("This is a Kaimon Slate notebook — running it as plain Julia needs the KaimonSlate runtime in this environment. Add it with `import Pkg; Pkg.add(\"KaimonSlate\")`, or open it in Kaimon Slate."); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

#%% md id=title title
# A Notebook With Roles

#%% md id=abstract abstract
This notebook exercises the `title`, `abstract`, and `bibliography` role tags that
KaimonSlate's front-matter cells actually support.

#%% md id=intro
## Introduction

Some ordinary prose that is not tagged with any role.

#%% code id=calc
2 + 2

#%% md id=refs bibliography
references.bib

# ╔═╡ Slate.env · notebook packages (auto-maintained — manage via the package panel)
#   Example 0.5.3 8ac3fa42-a05e-49e1-b0e7-4b9b5c1d1f3f
# ╚═╡
