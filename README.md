# CheckMate

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://mthelm85.github.io/CheckMate.jl/)
[![Build Status](https://github.com/mthelm85/CheckMate.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/mthelm85/CheckMate.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![codecov](https://codecov.io/gh/mthelm85/CheckMate.jl/graph/badge.svg?token=TF8UDDKSAW)](https://codecov.io/gh/mthelm85/CheckMate.jl)

A Julia package for data validation that allows you to define and run sets of checks against tabular data. CheckMate provides a simple macro-based interface for creating validation rules and generates detailed reports about validation failures.

## Features

- Easy-to-use macro syntax for defining validation rules
- Support for named functions and anonymous functions (lambdas) in checks
- Support for single and multi-column validation checks
- Detailed failure reporting with row-level information, including the first exception when a condition function throws
- Warning-level checks that are reported without failing validation
- `assert_valid` for pipelines and tests: throws a `ValidationError` containing the full report
- Results as plain Julia values, per-row diagnostics, and the summary itself is a Tables.jl table
- Fast: conditions are compiled for your column types, with optional multi-threading across checks
- Compatible with any data source that implements the Tables.jl interface, row- or column-oriented

## Installation

```julia
using Pkg
Pkg.add("CheckMate")
```

## Quick Start

```julia
using CheckMate
using DataFrames

# Example dataset
df = DataFrame(
    amount = [100, -50, 200, 300],
    currency = ["USD", "EUR", "XXX", "GBP"]
)

# Define your validation functions (must return Bool where true=pass/false=fail)
is_positive(x) = x > 0
valid_currency(x) = x in ("USD", "EUR", "GBP")

# Define validation rules using named functions or lambdas
checks = @checkset "Payment Validation" begin
    @check "Positive Amount" is_positive(:amount)
    @check "Valid Currency" valid_currency(:currency)
    @check "No Missing Amounts" (!ismissing)(:amount)
end

# Run the checks
results = run_checkset(df, checks)

# Output:

================================================================================
Check Summary: Payment Validation
================================================================================

✗ Positive Amount: 1 rows failed
   Row 2: amount=-50
✗ Valid Currency: 1 rows failed
   Row 3: currency=XXX
✓ No Missing Amounts: All rows passed

Summary:
 1/3 checks passed (33.3%)
Checks completed in 20.3 ms
```

## Details

### Defining Checks

Checks are defined using the `@checkset` macro, which allows you to group related validations:

```julia
checks = @checkset "Data Quality" begin
    @check "Check Name" validation_function(:column)
    @check "Multiple Columns" compare_values(:col1, :col2)
end
```

The pattern for individual `@check` statements is:

```julia
@check <YOUR_CHECK_NAME> f(args...)::Bool # f must return a Bool (where true=pass, false=fail)
```

Both named functions and anonymous functions (lambdas) are supported as the condition:

```julia
checks = @checkset "Inline Validation" begin
    @check "Positive Amount"  (x -> x > 0)(:amount)
    @check "Valid Currency"   (x -> x in ("USD", "EUR", "GBP"))(:currency)
    @check "A greater than B" ((a, b) -> a > b)(:col1, :col2)
end
```

Any expression that evaluates to a function works as the condition, e.g. `(!ismissing)(:col)`, `(==("USD"))(:currency)`, or `Base.isempty(:name)`.

Note: Negation and other operators work fine **inside** your validation functions, but cannot be applied directly to the macro call itself (e.g., `!ismissing(:col)` raises an error when the checkset is defined, but `(!ismissing)(:col)` or a lambda `(x -> !ismissing(x))(:col)` works).

### Warning-Level Checks

Append `severity=:warning` to report a check's failures without failing validation:

```julia
checks = @checkset "Payments" begin
    @check "Positive Amount"  (x -> x > 0)(:amount)
    @check "Unusually Large"  (x -> x < 100_000)(:amount) severity=:warning
end
```

Warnings are shown with ⚠ in the report and listed by `warning_checks(results)`. They are ignored by `failed_checks`, `all_passed`, `assert_valid`, `failing_rows(results)`, `total_failures` and the overall `pass_rate`.

### Running Checks

Run checks sequentially or in parallel:

```julia
# Sequential execution
results = run_checkset(data, checks)

# Parallel execution
results = run_checkset(data, checks, threaded=true)

# Run and throw a ValidationError (with the full report) if any check fails
results = assert_valid(data, checks)
```

### Analyzing Results

```julia
# Did every check pass?
all_passed(results)

# Get failed checks (in definition order)
failed = failed_checks(results)

# Get passing checks
passed = passed_checks(results)

# Get overall pass rate
rate = pass_rate(results)

# Get failing row indices
rows = failing_rows(results)

# Which checks did each failing row break?
using DataFrames
DataFrame(row_failures(results))

# A CheckSummary is a Tables.jl table with one row per check
DataFrame(results)

# Output:

3×7 DataFrame
 Row │ check               severity  passed  failures  exceptions  pass_rate  message
     │ String              Symbol    Bool    Int64     Int64       Float64    String
─────┼────────────────────────────────────────────────────────────────────────────────────────
   1 │ Positive Amount     error      false         1           0       75.0  1 rows failed
   2 │ Valid Currency      error      false         1           0       75.0  1 rows failed
   3 │ No Missing Amounts  error       true         0           0      100.0  All rows passed
```

### Contributing

Contributions are welcome! Please feel free to submit a Pull Request.