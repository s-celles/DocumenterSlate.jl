"""
    SlatePlugin([slates])

Documenter plugin state for notebook pages produced by [`build_slates`](@ref). Pass an instance to
`makedocs(; plugins = [SlatePlugin(slates)])`. The zero-argument constructor supports Documenter's
`getplugin` fallback and represents a build for which no slate result was supplied.

With the populated plugin installed, an authored documentation page can embed a rendered notebook
as native Documenter content:

````markdown
```@slate
notebook = "analysis.jl"
```
````

Use the same configuration under an `@slate-download` block to insert only the verified download
and inactive-inspection panel in an authored page.
"""
struct SlatePlugin <: Documenter.Plugin
    slates::Union{Nothing,SlateBuildResult}
end

SlatePlugin() = SlatePlugin(nothing)

abstract type SlateBlocks <: Documenter.Expanders.ExpanderPipeline end
abstract type SlateDownloadBlocks <: Documenter.Expanders.ExpanderPipeline end

Documenter.Selectors.order(::Type{SlateBlocks}) = 4.5
Documenter.Selectors.order(::Type{SlateDownloadBlocks}) = 4.6
Documenter.Selectors.matcher(::Type{SlateBlocks}, node, page, doc) =
    node.element isa MarkdownAST.CodeBlock && node.element.info == "@slate"
Documenter.Selectors.matcher(::Type{SlateDownloadBlocks}, node, page, doc) =
    node.element isa MarkdownAST.CodeBlock && node.element.info == "@slate-download"

function _slate_expander_config(codeblock::MarkdownAST.CodeBlock)
    config = try
        TOML.parse(codeblock.code)
    catch error
        throw(ArgumentError("invalid @slate configuration: " * sprint(showerror, error)))
    end
    notebook = get(config, "notebook", nothing)
    notebook isa String || throw(ArgumentError("@slate requires notebook = \"path.jl\""))
    return notebook
end

function _slate_expander_result(doc)::SlateBuildResult
    plugin = Documenter.getplugin(doc, SlatePlugin)
    result = plugin.slates
    result === nothing && throw(ArgumentError(
        "@slate requires makedocs(; plugins = [SlatePlugin(build_result)])"))
    result.output_dir === nothing && throw(ArgumentError(
        "@slate requires a SlateBuildResult returned by build_slates"))
    return result
end

function _replace_with_slate_markdown!(node, codeblock, markdown::AbstractString, page, doc)
    ast = convert(MarkdownAST.Node, Markdown.parse(markdown))
    node.element = Documenter.MultiOutput(codeblock)
    empty!(node.children)
    for child in collect(ast.children)
        inserted = MarkdownAST.unlink!(child)
        push!(node.children, inserted)
        Documenter.Selectors.dispatch(Documenter.Expanders.ExpanderPipeline, inserted, page, doc)
        Documenter.expand_recursively(inserted, page, doc)
    end
    return nothing
end

function Documenter.Selectors.runner(::Type{SlateBlocks}, node, page, doc)
    codeblock = node.element::MarkdownAST.CodeBlock
    notebook = _slate_expander_config(codeblock)
    result = _slate_expander_result(doc)
    output_dir = result.output_dir::String

    slug = splitext(basename(notebook))[1]
    rendered_path = joinpath(output_dir, slug * ".md")
    isfile(rendered_path) || throw(ArgumentError(
        "@slate could not find rendered notebook $rendered_path"))
    return _replace_with_slate_markdown!(
        node, codeblock, read(rendered_path, String), page, doc,
    )
end

function Documenter.Selectors.runner(::Type{SlateDownloadBlocks}, node, page, doc)
    codeblock = node.element::MarkdownAST.CodeBlock
    notebook = _slate_expander_config(codeblock)
    result = _slate_expander_result(doc)
    output_dir = result.output_dir::String
    slug = splitext(basename(notebook))[1]
    download_dir = joinpath(output_dir, "downloads", slug)
    sums_path = joinpath(download_dir, "SHA256SUMS")
    isfile(sums_path) || throw(ArgumentError(
        "@slate-download could not find $sums_path"))
    sha256 = Dict{String,String}()
    for line in readlines(sums_path)
        digest, name = split(line; limit = 2)
        sha256[strip(name)] = digest
    end
    page_path = abspath(doc.user.root, string(page.source))
    relative = relpath(download_dir, dirname(page_path))
    panel = _distribution_panel((; relative_directory = relative, sha256), slug)
    return _replace_with_slate_markdown!(node, codeblock, panel, page, doc)
end
