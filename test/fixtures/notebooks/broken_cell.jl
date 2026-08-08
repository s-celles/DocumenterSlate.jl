try; import KaimonSlate; catch; error("This is a Kaimon Slate notebook — running it as plain Julia needs the KaimonSlate runtime in this environment. Add it with `import Pkg; Pkg.add(\"KaimonSlate\")`, or open it in Kaimon Slate."); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

#%% md id=intro
# A notebook with a broken cell

The second code cell deliberately throws, so `fail_on_error` handling can be tested
against a known cell index.

#%% code id=ok
1 + 1

#%% code id=boom
error("boom")

#%% code id=unreached
"this cell should never run when fail_on_error stops execution at id=boom"

# ╔═╡ Slate.env · notebook packages (auto-maintained — manage via the package panel)
#   Example 0.5.3 8ac3fa42-a05e-49e1-b0e7-4b9b5c1d1f3f
# ╚═╡
