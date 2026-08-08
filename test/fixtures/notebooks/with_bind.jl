try; import KaimonSlate; catch; error("This is a Kaimon Slate notebook — running it as plain Julia needs the KaimonSlate runtime in this environment. Add it with `import Pkg; Pkg.add(\"KaimonSlate\")`, or open it in Kaimon Slate."); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

#%% md id=intro
# A notebook with `@bind`

Exercises a real Slate widget constructor via `@bind`, resolving to its default
value under `KaimonSlate.standalone!`.

#%% code id=controls
@bind n Slider(1:10)

#%% code id=usebind
n * 2

# ╔═╡ Slate.env · notebook packages (auto-maintained — manage via the package panel)
#   Example 0.5.3 8ac3fa42-a05e-49e1-b0e7-4b9b5c1d1f3f
# ╚═╡
