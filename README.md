# CheckMate

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://mthelm85.github.io/CheckMate.jl/)
[![Build Status](https://github.com/mthelm85/CheckMate.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/mthelm85/CheckMate.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![codecov](https://codecov.io/gh/mthelm85/CheckMate.jl/graph/badge.svg?token=TF8UDDKSAW)](https://codecov.io/gh/mthelm85/CheckMate.jl)

A Julia package for data validation that allows you to define and run sets of checks against tabular data. CheckMate provides a simple macro-based interface for creating validation rules and generates detailed reports about validation failures.

## Features

- Easy-to-use macro syntax for defining validation rules
- Support for single and multi-column validation checks
- Detailed failure reporting with row-level information
- Optional multi-threaded validation for large datasets
- Compatible with any data source that implements the Tables.jl interface

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
notmissing(x) = !ismissing(x)

# Define validation rules
checks = @checkset "Payment Validation" begin
    @check "Positive Amount" is_positive(:amount)
    @check "Valid Currency" valid_currency(:currency)
    @check "No Missing Amounts" notmissing(:amount)
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
Checks completed in 0.02 seconds
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

Notes:

- You should used named functions in your `@check` declarations (e.g., `x -> x > 0` will not work).
- Also, negation in validation functions 
is not currently supported (e.g., `!ismissing(:col)` won't work, but `ismissing(col)` will work.)

### Running Checks

Run checks sequentially or in parallel:

```julia
# Sequential execution
results = run_checkset(data, checks)

# Parallel execution
results = run_checkset(data, checks, threaded=true)
```

### Analyzing Results

```julia
# Get failed checks
failed = failed_checks(results)

# Get passing checks
passed = passed_checks(results)

# Get overall pass rate
rate = pass_rate(results)

# Get failing row indices
rows = failing_rows(results)

# Create detailed report
using DataFrames

summary = DataFrame(
    check_name=check_names(checks),
    pass_rate=[pass_rate(results, check) for check in check_names(checks)],
    num_failures=[length(failing_rows(results,check)) for check in check_names(checks)]
)

# Output:

3×3 DataFrame
 Row │ check_name          pass_rate  num_failures 
     │ String              Float64    Int64        
─────┼─────────────────────────────────────────────
   1 │ Positive Amount          75.0             1
   2 │ Valid Currency           75.0             1
   3 │ No Missing Amounts      100.0             0
```

### Contributing

Contributions are welcome! Please feel free to submit a Pull Request.