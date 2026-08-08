# Tiny MIME-showable stand-ins for a real plotting value (e.g. a CairoMakie Figure), so
# extract_assets! tests don't need a heavy plotting dependency to exercise the real
# `showable`/`show` dispatch mechanism. Plain include-able file, deliberately NOT a test
# file itself (no @testitem) — TestItemRunner isolates each @testitem in its own module, so
# these types must be (re-)included from inside each testitem that needs them, not defined
# once at file scope in a test_*.jl file.

struct _FakePNG
    bytes::Vector{UInt8}
end
Base.showable(::MIME"image/png", ::_FakePNG) = true
Base.show(io::IO, ::MIME"image/png", x::_FakePNG) = write(io, x.bytes)

struct _FakeSVG
    text::String
end
Base.showable(::MIME"image/svg+xml", ::_FakeSVG) = true
Base.show(io::IO, ::MIME"image/svg+xml", x::_FakeSVG) = write(io, x.text)
