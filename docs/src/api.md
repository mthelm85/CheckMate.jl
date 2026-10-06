```@meta
CurrentModule = CheckMate
```

# API Reference

```@index
Pages = ["api.md"]
```

## Defining checks

```@docs
@checkset
```

## Running checks

```@docs
run_checkset
```

## Asserting validity

```@docs
all_passed
assert_valid
ValidationError
```

## Querying results

```@docs
failed_checks
passed_checks
warning_checks
failing_rows
row_failures
pass_rate
total_failures
execution_time
```

## Inspecting checksets

```@docs
check_names
check_columns
```

## Reporting

```@docs
print_summary
```

## Types

```@docs
Check
CheckSet
CheckResult
CheckSummary
```
