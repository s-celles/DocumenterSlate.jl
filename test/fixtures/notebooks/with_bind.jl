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
#   Example 0.5.5 7876af07-990d-54b4-ab0e-23690620f79a
# ╚═╡
