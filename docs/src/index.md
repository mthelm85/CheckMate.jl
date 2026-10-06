```@meta
CurrentModule = CheckMate
```

# CheckMate.jl

**Declarative, row-level data validation for tabular data in Julia.**

CheckMate lets you describe what *valid* data looks like as a named set of
checks, run those checks against any [Tables.jl](https://github.com/JuliaData/Tables.jl)
source, and get back a readable report that points to the exact rows and values
that failed.

```@example home
using CheckMate, DataFrames

payments = DataFrame(
    amount   = [100, -50, 200, 300],
    currency = ["USD", "EUR", "XXX", "GBP"],
)

checks = @checkset "Payment Validation" begin
    @check "Positive Amount"    (x -> x > 0)(:amount)
    @check "Valid Currency"     (c -> c in ("USD", "EUR", "GBP"))(:currency)
    @check "No Missing Amounts" (!ismissing)(:amount)
end

run_checkset(payments, checks)
```

## Features

- **Readable rules.** Define checks with the [`@checkset`](@ref) macro, using
  named functions or inline lambdas.
- **Single- and multi-column checks.** A check can compare values across
  several columns in the same row.
- **Row-level failure reports.** Every failure records its row index and the
  values that caused it.
- **Robust to bad data.** If a condition throws, for example on a `missing`
  value, the row is recorded as a failure instead of stopping the run, and the
  report shows the first exception.
- **Warnings as well as errors.** Mark a check `severity=:warning` to report
  it without failing validation.
- **Programmatic results.** Pass rates, failing rows and per-row diagnostics
  are plain Julia values, and the summary is itself a Tables.jl table.
- **Pipeline- and test-friendly.** [`assert_valid`](@ref) throws a
  [`ValidationError`](@ref) with the full report when data is invalid.
- **Fast.** Conditions are compiled for your column types, so checking millions
  of rows takes milliseconds, and checks can also run in parallel.
- **Works with any table.** DataFrames, CSV files, Arrow tables, named tuples
  of vectors, or anything else that implements the Tables.jl interface.

## Installation

CheckMate is registered in the General registry:

```julia
using Pkg
Pkg.add("CheckMate")
```

## Where to go next

- [Getting Started](@ref) walks through a first validation from start to finish.
- [Defining Checks](@ref) covers the `@checkset` syntax in detail.
- [Working with Results](@ref) shows how to analyze a [`CheckSummary`](@ref).
- [Examples](@ref) has complete, realistic validation scenarios.
- [API Reference](@ref) documents every exported type and function.
