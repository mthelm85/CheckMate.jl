using CheckMate
using Documenter

DocMeta.setdocmeta!(CheckMate, :DocTestSetup, :(using CheckMate); recursive=true)

makedocs(;
    modules=[CheckMate],
    authors="Matt Helm mthelm85@gmail.com",
    sitename="CheckMate.jl",
    format=Documenter.HTML(;
        canonical="https://mthelm85.github.io/CheckMate.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="https://github.com/mthelm85/CheckMate.jl",
    devbranch="main",
)
