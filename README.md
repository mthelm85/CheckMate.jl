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

# Define your validation functions
is_positive(x) = x > 0
valid_currency(x) = x in ("USD", "EUR", "GBP")

# Create a dataset
df = DataFrame(
    amount = [100, -50, 200, 300],
    currency = ["USD", "EUR", "XXX", "GBP"]
)

# Define validation rules
checks = @checkset "Payment Validation" begin
    @check "Positive Amount" is_positive(:amount)
    @check "Valid Currency" valid_currency(:currency)
end

# Run the checks
results = run_checkset(df, checks)
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
```

### Contributing

Contributions are welcome! Please feel free to submit a Pull Request.