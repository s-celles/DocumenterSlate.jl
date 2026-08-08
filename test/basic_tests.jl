@testitem "DocumenterSlate loads and exports its public M1 API surface" begin
    using DocumenterSlate

    public_names = [
        :SlateBuildOptions, :SlateOutputOptions,
        :discover_notebooks,
        :resolve_notebook_project, :NotebookProjectResolution,
        :resolve_notebook_meta, :NotebookMeta,
        :AbstractSlateExporter, :TextualReplayExporter,
        :execute_notebook, :ExecutedNotebook, :CellResult,
        :SlateExecutionError, :SlateExecutionTimeoutError,
        :cell_to_markdown, :extract_assets!,
        :build_pages, :SlateBuildResult,
        :build_slates,
    ]
    for name in public_names
        @test isdefined(DocumenterSlate, name)
        @test name in names(DocumenterSlate)   # actually exported, not just defined
    end
end
