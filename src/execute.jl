"""
    SlateExecutionError <: Exception

Raised by [`execute_notebook`](@ref) when a code cell throws and `fail_on_error = true`
(REQ-EXE-04). Identifies the notebook file, the failing cell's id and 1-based index (over
*all* cells, markdown included), the cell's source code, and the first 20 lines of the
formatted backtrace.

Custom exception type (rather than a rethrow of the raw exception) so callers can
`catch e; e isa SlateExecutionError` instead of pattern-matching on arbitrary user code
exceptions.

# Fields
- `notebook_path::String`
- `cell_id::String`
- `cell_index::Int`
- `cell_source::String`
- `backtrace_lines::Vector{String}`: at most the first 20 lines of the formatted
  backtrace of the underlying exception.
"""
struct SlateExecutionError <: Exception
    notebook_path::String
    cell_id::String
    cell_index::Int
    cell_source::String
    backtrace_lines::Vector{String}
end

function Base.showerror(io::IO, e::SlateExecutionError)
    print(io, "SlateExecutionError: notebook \"", e.notebook_path, "\" failed at cell ",
          e.cell_index, " (id=\"", e.cell_id, "\")\n\nCell source:\n", e.cell_source,
          "\n\nBacktrace (first ", length(e.backtrace_lines), " line(s)):\n")
    for line in e.backtrace_lines
        println(io, line)
    end
end

"""
    SlateExecutionTimeoutError <: Exception

Raised by [`execute_notebook`](@ref) when a notebook's total execution time exceeds
`exporter.timeout` seconds (REQ-EXE-06). Distinct from [`SlateExecutionError`](@ref) so
callers can tell a per-cell failure apart from a timeout.

Note: `TextualReplayExporter` executes in-process, so a timeout cannot forcibly kill a
non-yielding (CPU-bound, no I/O/`sleep`/task-switch) computation — see
[`execute_notebook`](@ref)'s docstring for the exact boundary.
"""
struct SlateExecutionTimeoutError <: Exception
    notebook_path::String
    timeout::Int
end

function Base.showerror(io::IO, e::SlateExecutionTimeoutError)
    print(io, "SlateExecutionTimeoutError: execution of notebook \"", e.notebook_path,
          "\" exceeded the configured timeout of ", e.timeout, " second(s)")
end

"""
    CellResult

Captured outcome of executing (or, for a markdown cell, simply carrying) a single
notebook cell (REQ-EXE-03/04/05).

# Fields
- `cell_id::String`: the cell's persistent id (`KaimonSlate.ReportEngine.Cell.id`).
- `kind::Symbol`: `:md` or `:code`. `KaimonSlate`'s `WEB` cell kind is treated as `:code`
  (it evaluates identically — see `widgets.jl`'s own comment on `WEB` cells).
- `source::String`: the cell's source text, exactly as `KaimonSlate.parse_report` returns
  it (for `:md` cells, already unwrapped from the `@md\"\"\"…\"\"\"` runnable skin — see
  `KaimonSlate.jl/src/engine.jl`'s `_unwrap_md`). Carried through for downstream rendering
  (M1.10) so it doesn't need to re-parse the notebook file.
- `flags::Set{Symbol}`: the cell's role/UI tags (`KaimonSlate.ReportEngine.Cell.flags`,
  e.g. `:title`, `:hidecode`) — also carried through for M1.10 rendering.
- `stdout_text::String`: captured standard output produced while evaluating the cell;
  always `""` for a `:md` cell.
- `value::Any`: the cell's last top-level expression value (mirrors `include`); `nothing`
  for `:md` cells and for `:code` cells whose last statement has no value (e.g. a bare
  `using X`), and for a cell recorded with an `error`.
- `error::Union{Nothing,Exception}`: the exception raised while evaluating this cell, or
  `nothing`. Only ever set when `fail_on_error = false` (with `fail_on_error = true`,
  [`execute_notebook`](@ref) raises [`SlateExecutionError`](@ref) instead of returning).
- `backtrace::Union{Nothing,String}`: the formatted backtrace of `error` (full length, not
  truncated — the 20-line cap of REQ-EXE-04 applies only to the raised
  [`SlateExecutionError`](@ref), not to a recorded per-cell result), or `nothing`.
"""
struct CellResult
    cell_id::String
    kind::Symbol
    source::String
    flags::Set{Symbol}
    stdout_text::String
    value::Any
    error::Union{Nothing,Exception}
    backtrace::Union{Nothing,String}
end

"""
    ExecutedNotebook

Result of executing a whole notebook via [`execute_notebook`](@ref) (REQ-EXE-03).

# Fields
- `notebook_path::String`: resolved (`realpath`) path of the executed notebook.
- `cells::Vector{CellResult}`: per-cell results, in source order. When
  `fail_on_error = true` this only reaches the caller for a notebook that executed to
  completion (an error instead raises [`SlateExecutionError`](@ref)); when
  `fail_on_error = false`, all cells are present, including any recorded with an error.
- `mod::Module`: the fresh, anonymous module the notebook was evaluated in. Kept for
  downstream rendering (M1.10) that may need to inspect leftover module state (e.g. a
  display object a cell only assigned to a variable without it being the last
  expression). Not needed for REQ-EXE-03/04/05/06 themselves.
"""
struct ExecutedNotebook
    notebook_path::String
    cells::Vector{CellResult}
    mod::Module
end

# Formats a backtrace via `Base.show_backtrace` and splits it into lines. Used both for
# the (untruncated) `CellResult.backtrace` and for `SlateExecutionError`'s 20-line cap.
function _format_backtrace_lines(bt)
    text = sprint(Base.show_backtrace, bt)
    return String.(split(text, '\n'))
end

# `redirect_stdout`/`stdout` is *process-wide* mutable state, not task-local (despite an
# earlier version of this comment claiming otherwise — empirically disproven: overlapping
# redirect/restore across two concurrently-live `_eval_cell` calls corrupts stdout for
# BOTH, up to and including the caller's own unrelated output). The only source of overlap
# in M1 (no parallel notebook execution yet, REQ-EXE-07/nworkers is M2) is a *leaked* task
# from a fired `SlateExecutionTimeoutError` (execute_notebook's caller stops waiting, but a
# non-yielding-detection-only timeout — see exporters.jl's `timeout` docstring — leaves the
# cell's own `Threads.@spawn`'d task running until it naturally finishes) racing against a
# later, unrelated `_eval_cell` call in the same process. This lock serializes the
# redirect/eval/restore critical section process-wide: a live notebook execution blocks
# briefly on a leaked one rather than racing it. Cheap and correct for M1's sequential
# execution model; a future parallel (`nworkers > 1`) implementation will need a per-task
# capture mechanism that doesn't share this global, not just a bigger lock.
const _STDOUT_CAPTURE_LOCK = ReentrantLock()

# Evaluate a single code cell's source in `mod`, mirroring `include`'s semantics (last
# top-level value returned; multiple statements run in order) via `Base.include_string`.
# Captures everything printed to `stdout` while it runs. Returns
# `(value, stdout_text, error, backtrace)`, where `error`/`backtrace` are `nothing` on
# success. `include_string` wraps a thrown exception in a `LoadError`; unwrapped here so
# `CellResult.error`/`SlateExecutionError` report the exception the cell itself raised,
# not an internal loading artifact.
function _eval_cell(mod::Module, cell, notebook_path::AbstractString)
    lock(_STDOUT_CAPTURE_LOCK) do
        _eval_cell_locked(mod, cell, notebook_path)
    end
end

function _eval_cell_locked(mod::Module, cell, notebook_path::AbstractString)
    pipe = Pipe()
    Base.link_pipe!(pipe; reader_supports_async = true, writer_supports_async = true)
    old_stdout = stdout
    redirect_stdout(pipe.in)
    reader = @async read(pipe.out, String)

    value = nothing
    err = nothing
    bt = nothing
    try
        value = Base.include_string(mod, cell.source, notebook_path)
    catch e
        err = e isa LoadError ? e.error : e
        bt = catch_backtrace()
    finally
        # A cell that outlives execute_notebook's timeout (SlateExecutionTimeoutError
        # already raised, exporters.jl's docstring is explicit this is detection-only, not
        # a kill) reaches this cleanup on its own schedule, arbitrarily later, in whatever
        # task-local stdout context it happens to wake up in — by then old_stdout / the
        # pipe may already be torn down by the caller (empirically: the test runner
        # recycles per-item IO streams between test items). Nothing downstream is still
        # listening for this cell's result at that point, so best-effort cleanup here
        # (never crash the process a leaked task happens to wake up in) is the correct
        # behavior, not error-hiding for a case anyone still cares about the outcome of.
        try
            redirect_stdout(old_stdout)
        catch
        end
        try
            close(pipe.in)
        catch
        end
    end
    out = try
        fetch(reader)
    catch
        ""
    end
    try
        close(pipe.out)
    catch
    end

    return (value, out, err, bt)
end

# Matches the bound variable name of a `@bind name Widget(...)` cell (KaimonSlate's real
# macro syntax, `widgets.jl`). AST-based detection (`KaimonSlate.ReportEngine`'s own
# `_bind_macrocall`) isn't reused here: it isn't exported and, more importantly,
# `Cell.binds`/`Cell.reads`/`Cell.writes` are only populated by `parse_report`'s
# dependency-analysis pass, which `execute_notebook` does not run (M1 is source-order
# execution, not the reactive DAG — see ADR-003's revision). A source regex is therefore
# both sufficient and honest about what information is actually available.
const _BIND_NAME_RE = r"@bind\s+([A-Za-z_!][A-Za-z0-9_!]*)"

# If `cell.source` declares `@bind <name> ...` and `binds` has a matching key (matched by
# name, as a `String`), override the module-level binding via the notebook namespace's own
# `__slate_set_bind` (injected by `KaimonSlate.standalone!`/`_populate_notebook_ns!` — the
# same function the browser calls on every live control change), so the module-level
# variable is reassigned to the coerced override value (REQ-EXE-08). No-op when `binds` is
# empty, the cell isn't a bind cell, or the notebook's module doesn't expose
# `__slate_set_bind` (defensive; `standalone!` always injects it, but a future upstream
# change removing it should degrade to "binds are ignored", not a hard error).
function _apply_bind_override!(mod::Module, cell, binds::Dict{String,Any})
    isempty(binds) && return nothing
    m = match(_BIND_NAME_RE, cell.source)
    m === nothing && return nothing
    name = m.captures[1]
    haskey(binds, name) || return nothing
    isdefined(mod, :__slate_set_bind) || return nothing
    Core.eval(mod, :(__slate_set_bind($(QuoteNode(Symbol(name))), $(binds[name]))))
    return nothing
end

# Runs the whole cell loop (fresh module + `standalone!` + per-cell eval + `fail_on_error`
# handling) synchronously; `execute_notebook` wraps a call to this in a timed task.
function _execute_cells(report, notebook_path::AbstractString, fail_on_error::Bool,
                         binds::Dict{String,Any})
    mod = Module(:SlateNotebook)
    KaimonSlate.standalone!(mod; dir = dirname(notebook_path))

    results = CellResult[]
    for (idx, cell) in enumerate(report.cells)
        if cell.kind == KaimonSlate.MARKDOWN
            push!(results, CellResult(cell.id, :md, cell.source, cell.flags, "", nothing,
                                       nothing, nothing))
            continue
        end

        value, out, err, bt = _eval_cell(mod, cell, notebook_path)

        if err !== nothing
            # `err`/`bt` are only ever set together, in the same `catch` block inside
            # `_eval_cell` — `err !== nothing` implies `bt !== nothing` at runtime, but that
            # correlation between two independently-`Union{Nothing,...}`-typed return values
            # isn't provable by the type system on its own; `something(bt)` narrows it.
            backtrace = something(bt)
            if fail_on_error
                throw(SlateExecutionError(
                    notebook_path, cell.id, idx, cell.source,
                    first(_format_backtrace_lines(backtrace), 20),
                ))
            end
            push!(results, CellResult(cell.id, :code, cell.source, cell.flags, out, nothing,
                                       err, join(_format_backtrace_lines(backtrace), '\n')))
            continue
        end

        push!(results, CellResult(cell.id, :code, cell.source, cell.flags, out, value,
                                   nothing, nothing))
        _apply_bind_override!(mod, cell, binds)
    end

    return ExecutedNotebook(notebook_path, results, mod)
end

"""
    execute_notebook(exporter::TextualReplayExporter, notebook_path::AbstractString;
                      fail_on_error::Bool = true, binds::Dict = Dict()) -> ExecutedNotebook

Execute a KaimonSlate notebook headlessly, cell by cell, in source order (REQ-EXE-02/03,
spec §17 addendum / `upstream-bugs.md` §7, ADR-003 revision). This is the
`TextualReplayExporter` half of `AbstractSlateExporter` (spec §5 ADR-003): built on the
confirmed, exported upstream primitive `KaimonSlate.standalone!`, with zero dependency on
the `slate` hub (REQ-EXE-09, verified by construction — this file never references
`HTTP`/`Sockets`/hub or remote machinery).

# Execution model
1. `notebook_path` is parsed via `KaimonSlate.parse_report`.
2. A **fresh, anonymous `Module`** is created for this call — never reused, never shared
   with the calling process's globals.
3. `KaimonSlate.standalone!(mod; dir = dirname(notebook_path))` injects the
   notebook-namespace contract (`@bind`, widgets, …) into it, per the confirmed upstream
   contract (`upstream-bugs.md` §7): `@bind x W(…)` resolves to `W`'s default with no
   browser/hub involved.
4. Cells are evaluated **in source order** — no reactive-DAG scheduling (ADR-003's
   revision: `execute_notebook` never calls into `KaimonSlate`'s dependency/`deps`
   machinery).
   - `:md` cells are recorded as-is; no evaluation. (`{{ expr }}` markdown interpolation
     is out of scope here — see [`CellResult`](@ref)'s "Fields" note above and the M1.10
     rendering task, which is a more natural home for it.)
   - `:code` (and `WEB`, which evaluates identically upstream) cells are evaluated via
     `include`-equivalent semantics (`Base.include_string`): `stdout` is captured, the last
     top-level expression's value is captured, and a thrown exception is caught with its
     backtrace.

# `fail_on_error` (REQ-EXE-04/05)
- `true` (default): the first cell that throws stops execution — later cells are **not**
  run — and [`SlateExecutionError`](@ref) is raised, identifying the notebook path, the
  cell's id/index, its source, and the first 20 lines of the formatted backtrace.
- `false`: the error is recorded on that cell's [`CellResult`](@ref) (`.error`/
  `.backtrace`) and execution continues with the next cell.

# `binds` (REQ-EXE-08, Should)
A `Dict` from bound variable name (as a `String`) to override value. For each `:code` cell
whose source contains `@bind <name> Widget(...)`, if `<name>` is a key of `binds`, the
override is applied via the notebook namespace's own `__slate_set_bind` function
(the same one the browser calls on a live control change) immediately after that cell
runs — i.e. *before* any later cell that reads the bound variable. This is a source-text
match, not an AST/dependency-graph one (see `_apply_bind_override!`'s comment for why);
sufficient for the *Should*-priority scope of REQ-EXE-08.

# `timeout` (REQ-EXE-06)
Enforced **per notebook** (matching the spec's "l'exécution d'un notebook" wording), not
per cell, using `exporter.timeout` seconds. The cell loop runs inside a
`Threads.@spawn`'d task; `timedwait` polls for completion. On timeout,
[`SlateExecutionTimeoutError`](@ref) is raised.

Because `TextualReplayExporter` executes in-process (no subprocess/worker to kill, unlike
the spec's "tuer le worker" wording, which describes the future `HubExporter`), a timeout
can only be *detected* reliably for cell code that yields control at some point (I/O,
`sleep`, task switches, GC safepoints under normal execution) — the background task is not
forcibly terminated, so a genuinely non-yielding, CPU-bound infinite loop keeps running
after `SlateExecutionTimeoutError` is raised to the caller (a real resource leak, not just
a cosmetic one). This is a known, explicit limitation of the in-process textual-replay
approach, not a bug; a true kill requires an out-of-process backend.

# `ENV`/REQ-SEC-02 nuance
The fresh module does not additionally import or widen access to the calling process's
`ENV` beyond what any Julia code can already see: `Base.ENV` is a *process-global*
binding, reachable from **any** Julia code in **any** module regardless of what
`execute_notebook` does — there is no module-scoped sandboxing of it in stock Julia, and
this function does not attempt one. What `execute_notebook` *does* guarantee is narrower
and real: it never explicitly copies, injects, or otherwise makes `ENV` "more reachable"
than it already is (e.g. it does not pass `ENV` as an argument into the module, define a
convenience alias, or widen any whitelist). A notebook cell that calls `ENV["SECRET"]`
directly succeeds regardless — full process-wide `ENV` containment (REQ-SEC-02's
CI-integration half — a whitelist propagated into a genuinely separate worker process) is
out of scope for an in-process executor and is deferred to a future out-of-process
backend (`HubExporter`+CI-level environment scrubbing, spec §9's two-job workflow).
"""
function execute_notebook(exporter::TextualReplayExporter, notebook_path::AbstractString;
                           fail_on_error::Bool = true, binds::Dict = Dict())
    resolved = realpath(notebook_path)
    text = read(resolved, String)
    report = KaimonSlate.parse_report(text)
    binds_str = Dict{String,Any}(string(k) => v for (k, v) in binds)

    task = Threads.@spawn _execute_cells(report, resolved, fail_on_error, binds_str)

    status = timedwait(() -> istaskdone(task), exporter.timeout)
    if status !== :ok
        throw(SlateExecutionTimeoutError(resolved, exporter.timeout))
    end

    try
        return fetch(task)
    catch e
        e isa TaskFailedException ? rethrow(e.task.exception) : rethrow(e)
    end
end
