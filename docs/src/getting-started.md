```@meta
CurrentModule = CheckMate
```

# Getting Started

This page walks through a complete validation workflow: defining checks,
running them, and acting on the results.

## The workflow

Using CheckMate always takes three steps:

1. **Define** a [`CheckSet`](@ref) with the [`@checkset`](@ref) macro.
2. **Run** it against your data with [`run_checkset`](@ref), which returns a
   [`CheckSummary`](@ref).
3. **Inspect** the summary, either by reading the printed report or by querying
   it with functions such as [`failed_checks`](@ref) and [`failing_rows`](@ref).

## 1. Write validation functions

A validation function takes one value per column and returns a `Bool`: `true`
when the row is valid and `false` when it is not.

```@example start
is_positive(x) = x > 0
valid_currency(x) = x in ("USD", "EUR", "GBP")
nothing # hide
```

## 2. Define a checkset

Group related checks into a named checkset. Each [`@check`](@ref "Defining Checks")
line has a name and a call that applies a function to one or more columns,
written as symbols:

```@example start
using CheckMate

checks = @checkset "Payment Validation" begin
    @check "Positive Amount" is_positive(:amount)
    @check "Valid Currency"  valid_currency(:currency)
end
```

Displaying a checkset lists each check and the columns it reads.

## 3. Run the checks

Pass any Tables.jl-compatible table to [`run_checkset`](@ref):

```@example start
using DataFrames

payments = DataFrame(
    id       = 1:6,
    amount   = [100, -50, 200, 300, 0, 75],
    currency = ["USD", "EUR", "XXX", "GBP", "USD", "JPY"],
)

summary = run_checkset(payments, checks)
```

The report lists failed checks first, followed by passing checks. Each failure
shows the row index and the values the check saw. Long failure lists are
shortened to the first and last five rows.

## 4. Act on the results

The summary can also be queried in code, which is useful in pipelines and
tests:

```@example start
failed_checks(summary)
```

```@example start
failing_rows(summary)            # unique rows that failed any check
```

```@example start
pass_rate(summary)               # % of rows that passed every check
```

A common next step is to split the data into clean and rejected rows:

```@example start
bad = failing_rows(summary)
rejected = payments[bad, :]
```

```@example start
clean = payments[setdiff(1:nrow(payments), bad), :]
```

!!! tip "Using CheckMate in a pipeline"
    To stop a pipeline when validation fails, use [`assert_valid`](@ref). It
    runs the checks and throws a [`ValidationError`](@ref), including the full
    report, if any check fails:

    ```julia
    summary = assert_valid(data, checks)
    ```

## Next steps

- [Defining Checks](@ref) covers lambdas, multi-column checks and common
  pitfalls.
- [Working with Results](@ref) covers every way to query a summary.
