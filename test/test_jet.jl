@testitem "JET: no obvious type errors" begin
    using JET
    using DocumenterSlate

    # `target_defined_modules = true` isn't a valid keyword for the installed JET version
    # (0.12.1) -- confirmed by reading `@doc JET.test_package`. `target_modules` is the
    # real equivalent (`@doc JET.report_package`'s own "About target_modules" tip):
    # without it, results are overwhelmed by pre-existing issues in KaimonSlate's/Base's
    # own code (reachable from DocumenterSlate's calls into them, e.g. parse_report's
    # regex-capture handling) that aren't this package's to fix.
    JET.test_package(DocumenterSlate; toplevel_logger = nothing,
                      target_modules = (DocumenterSlate,))
end
