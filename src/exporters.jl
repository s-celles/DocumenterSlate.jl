"""
    AbstractSlateExporter

Abstract supertype for headless notebook execution backends (spec §5 ADR-003, revised
per `upstream-bugs.md` §7: three tiers instead of two).

Concrete subtypes so far:
- [`TextualReplayExporter`](@ref): M1 default, built on `KaimonSlate.standalone!`, zero
  dependency on the hub.

Deferred / not yet implemented:
- `HubExporter` (M2+): self-contained PDF/HTML export via the local `slate` hub,
  supports interactivity.
- `InProcessExporter`: speculative, unconfirmed upstream — do not assume it exists.

This type only defines the exporter hierarchy (M1.8); execution behavior
(`KaimonSlate.standalone!` invocation, timeout enforcement per REQ-EXE-06) is added
separately (M1.9).
"""
abstract type AbstractSlateExporter end

"""
    TextualReplayExporter(; timeout::Int = 900)

Headless execution backend built on `KaimonSlate.standalone!` (spec §5 ADR-003, revised;
see `upstream-bugs.md` §7). This is the M1 default exporter: it has zero dependency on the
`slate` hub and evaluates a notebook's cells top-to-bottom in a fresh module, Pluto-style.

# Keywords
- `timeout::Int = 900`: maximum wall-clock time, in seconds, allowed for a single
  notebook's execution (REQ-EXE-06) before the worker is killed and the build fails with
  an explicit diagnostic. Default of 900s (15 minutes) matches spec §5's original
  `HubExporter` sketch, applied here to the current default exporter. Must be positive.

Execution behavior (actually invoking `KaimonSlate.standalone!` and enforcing `timeout`)
is implemented separately; this type only carries the configuration.
"""
struct TextualReplayExporter <: AbstractSlateExporter
    timeout::Int

    function TextualReplayExporter(timeout::Int)
        timeout > 0 || throw(ArgumentError("`timeout` must be positive; got $timeout"))
        return new(timeout)
    end
end

TextualReplayExporter(; timeout::Int = 900) = TextualReplayExporter(timeout)
