@testitem "Aqua: quality checks" begin
    using Aqua
    using DocumenterSlate

    # `ambiguities = false`: DocumenterSlate itself defines no ambiguous methods, but
    # Aqua's default ambiguity scan also walks KaimonSlate/Documenter/Distributed's own
    # method tables, which have pre-existing ambiguities unrelated to this package (not
    # ours to fix).
    #
    # `stale_deps = (; ignore = [:Documenter])`: Documenter is a genuine, intentional
    # dependency (REQ-INT-07 requires declaring and enforcing `Documenter = "1"` compat)
    # that src/ doesn't `import`/`using` yet — the actual `Documenter.Plugin` integration
    # (`SlatePlugin`, N1 tier) isn't implemented until a later milestone (M4). This is a
    # real, correctly-detected "unused for now" dependency, not a mistake to silently
    # work around by adding a token unused import.
    Aqua.test_all(DocumenterSlate; ambiguities = false, stale_deps = (; ignore = [:Documenter]))
end
