FROM julia:1.12
WORKDIR /work
COPY . /work
RUN julia --project=. -e 'using Pkg; Pkg.instantiate()'
EXPOSE 8765
ENTRYPOINT ["julia", "--project=.", "-e", "using KaimonSlate; KaimonSlate.serve_notebook(ARGS[1]; host=\"0.0.0.0\", inactive = true)"]
CMD ["hello.jl"]
