try; import KaimonSlate; catch; error("This is a Kaimon Slate notebook — running it as plain Julia needs the KaimonSlate runtime in this environment. Add it with `import Pkg; Pkg.add(\"KaimonSlate\")`, or open it in Kaimon Slate."); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

#%% md id=intro
# A notebook with a hidden-source cell

The code cell below is tagged `hidecode` — its source should be hidden while its
output still renders.

#%% code id=hidden hidecode
sum(1:10)

# ╔═╡ Slate.env · notebook packages (auto-maintained — manage via the package panel)
#   Example 0.5.3 8ac3fa42-a05e-49e1-b0e7-4b9b5c1d1f3f
# ╚═╡
