using CheckMate
using Documenter
using MaterialDocs

DocMeta.setdocmeta!(CheckMate, :DocTestSetup, :(using CheckMate); recursive=true)

makedocs(;
    modules=[CheckMate],
    authors="Matt Helm mthelm85@gmail.com",
    sitename="CheckMate.jl",
    format=Material3(;
        theme=:amber_workshop,
        dark_mode=:toggle,
        canonical="https://mthelm85.github.io/CheckMate.jl",
        edit_link="main",
        assets=["assets/custom.css"],
    ),
    pages=[
        "Home" => "index.md",
        "Getting Started" => "getting-started.md",
        "Manual" => [
            "Defining Checks" => "defining-checks.md",
            "Working with Results" => "results.md",
        ],
        "Examples" => "examples.md",
        "API Reference" => "api.md",
    ],
)

# Work around MaterialDocs <= 0.2.1 copying ANSI color codes from @example output
# into the search index, which makes it invalid JSON and breaks search.
# Remove once MaterialDocs 0.2.2 is released.
let index = joinpath(@__DIR__, "build", "assets", "search-index.json")
    isfile(index) && write(index, replace(read(index, String), r"\e\[[0-9;:?]*[ -/]*[@-~]" => ""))
end

deploydocs(;
    repo="github.com/mthelm85/CheckMate.jl",
    devbranch="main",
)
