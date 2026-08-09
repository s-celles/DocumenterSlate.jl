try; import KaimonSlate; catch; error("This is a Kaimon Slate notebook — running it as plain Julia needs the KaimonSlate runtime in this environment. Add it with `import Pkg; Pkg.add(\"KaimonSlate\")`, or open it in Kaimon Slate."); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

#%% md id=title title
# Hiding a cell's source

A code cell tagged `hidecode` keeps its output on the page while hiding its source — useful
when the *result* matters to the reader but the mechanics of producing it would be noise
(REQ-REN-05). This always wins over the site-wide `show_code` default; it's the cell
author's own explicit choice, not a global toggle.

#%% md id=shown
The cell below is an ordinary cell — its source is visible, as usual.

#%% code id=visible
message = "you can see this cell's source"

#%% md id=hidden_intro
The next cell is tagged `hidecode`. Its source (a short computation building the same kind
of value) does not appear on the page — only its output does.

#%% code id=hidden hidecode
sum(abs2, 1:10)
