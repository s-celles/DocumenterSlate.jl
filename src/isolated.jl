function _portable_error(error)
    if error isa SlateExecutionError
        return Dict{String,Any}(
            "type" => "execution",
            "notebook_path" => error.notebook_path,
            "cell_id" => error.cell_id,
            "cell_index" => error.cell_index,
            "cell_source" => error.cell_source,
            "backtrace_lines" => error.backtrace_lines,
        )
    end
    return Dict{String,Any}("type" => "generic", "message" => sprint(showerror, error))
end

function _isolated_worker(request_path::AbstractString, response_path::AbstractString)
    request = open(Serialization.deserialize, request_path)
    response = try
        Pkg.activate(request.project_dir; io = devnull)
        resolved = realpath(request.notebook_path)
        report = KaimonSlate.parse_report(read(resolved, String))
        executed = _execute_cells(report, resolved, request.fail_on_error, request.binds)
        mktempdir() do assets_dir
            assets = request.assets == :files ? extract_assets!(executed, assets_dir) : Dict{String,String}()
            rendered = String[
                let asset_file = get(assets, cell.cell_id, nothing),
                    asset_path = asset_file === nothing ? nothing :
                                 joinpath("assets", request.slug, asset_file)
                    cell_to_markdown(cell; show_code = request.show_code,
                                     anchor_prefix = request.slug, asset_path = asset_path)
                end for cell in executed.cells
            ]
            files = Dict{String,Vector{UInt8}}()
            isdir(assets_dir) && foreach(readdir(assets_dir)) do name
                files[name] = read(joinpath(assets_dir, name))
            end
            (; ok = true, page_text = join(rendered, "\n\n"), assets = files,
               active_project = Base.active_project())
        end
    catch error
        (; ok = false, error = _portable_error(error))
    end
    open(response_path, "w") do io
        Serialization.serialize(io, response)
    end
    return nothing
end

function _footer_project!(directory::AbstractString, project::NotebookProjectResolution)
    dependencies = Dict{String,String}("KaimonSlate" => "f7b954f5-0334-4562-ac21-b005218ce1da")
    for dependency in something(project.env_footer)
        name = get(dependency, "name", nothing)
        uuid = get(dependency, "uuid", nothing)
        name isa String && uuid isa String && (dependencies[name] = uuid)
    end
    open(joinpath(directory, "Project.toml"), "w") do io
        TOML.print(io, Dict("deps" => dependencies))
    end
    return directory
end

function _with_worker_project(f::Function, project::NotebookProjectResolution)
    if project.kind == :external
        return f(something(project.project_dir))
    end
    return mktempdir() do directory
        _footer_project!(directory, project)
        f(directory)
    end
end

function _isolated_environment(explicit::Dict{String,String})
    separator = Sys.iswindows() ? ';' : ':'
    environment = Dict{String,String}(
        "JULIA_DEPOT_PATH" => join(Base.DEPOT_PATH, separator),
        "JULIA_LOAD_PATH" => "@:@stdlib",
        "JULIA_NUM_THREADS" => "1",
    )
    merge!(environment, explicit)
    return environment
end

_worker_bootstrap_project() = dirname(something(Base.active_project()))

function _render_notebook_isolated(path::AbstractString, project::NotebookProjectResolution,
                                   exporter::TextualReplayExporter, options::SlateBuildOptions,
                                   output_options::SlateOutputOptions, meta::NotebookMeta,
                                   slug::AbstractString)
    return _with_worker_project(project) do project_dir
        mktempdir() do temporary
            request_path = joinpath(temporary, "request.bin")
            response_path = joinpath(temporary, "response.bin")
            stderr_path = joinpath(temporary, "stderr.txt")
            request = (;
                notebook_path = String(path), project_dir = String(project_dir),
                fail_on_error = options.fail_on_error,
                binds = Dict{String,Any}(meta.binds),
                assets = output_options.assets,
                show_code = output_options.show_code && meta.show_code,
                slug = String(slug),
            )
            open(request_path, "w") do io
                Serialization.serialize(io, request)
            end
            bootstrap_project = _worker_bootstrap_project()
            expression = "using DocumenterSlate; DocumenterSlate._isolated_worker(ARGS[1], ARGS[2])"
            command = `$(Base.julia_cmd()) --startup-file=no --history-file=no --project=$bootstrap_project -e $expression $request_path $response_path`
            stderr_io = open(stderr_path, "w")
            process = run(pipeline(
                setenv(command, _isolated_environment(options.worker_environment));
                stdout = devnull, stderr = stderr_io,
            ); wait = false)
            status = timedwait(() -> process_exited(process), exporter.timeout)
            if status !== :ok
                kill(process)
                wait(process)
                close(stderr_io)
                throw(SlateExecutionTimeoutError(realpath(path), exporter.timeout))
            end
            wait(process)
            close(stderr_io)
            if !isfile(response_path)
                stderr = isfile(stderr_path) ? read(stderr_path, String) : ""
                throw(ErrorException("isolated notebook worker failed: " * stderr))
            end
            response = open(Serialization.deserialize, response_path)
            if !response.ok
                error = response.error
                if error["type"] == "execution"
                    throw(SlateExecutionError(
                        error["notebook_path"], error["cell_id"], error["cell_index"],
                        error["cell_source"], String.(error["backtrace_lines"]),
                    ))
                end
                throw(ErrorException("isolated notebook worker failed: " * error["message"]))
            end
            assets_dir = joinpath(options.output, "assets", slug)
            if !isempty(response.assets)
                mkpath(assets_dir)
                for (name, bytes) in response.assets
                    write(joinpath(assets_dir, name), bytes)
                end
            end
            return String(response.page_text)
        end
    end
end
