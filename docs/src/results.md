```@meta
CurrentModule = CheckMate
```

# Working with Results

[`run_checkset`](@ref) returns a [`CheckSummary`](@ref). Displaying it prints a
report, and a set of accessor functions turns it into plain Julia values for
further analysis.

The examples on this page use the following data and checks:

```@example results
using CheckMate, DataFrames

customers = DataFrame(
    id      = 1:8,
    age     = [34, 17, 52, 41, 130, 29, 63, 22],
    email   = ["a@x.com", "b@x.com", "bad-email", "d@x.com",
               "e@x.com", "f@x", "g@x.com", "h@x.com"],
    country = ["US", "US", "CA", "MX", "US", "ZZ", "CA", "US"],
)

checks = @checkset "Customer Validation" begin
    @check "Adult"         (a -> a >= 18)(:age)
    @check "Plausible age" (a -> a <= 120)(:age)
    @check "Valid email"   (e -> occursin(r"^[^@\s]+@[^@\s]+\.\w+$", e))(:email)
    @check "Known country" (c -> c in ("US", "CA", "MX"))(:country)
end

summary = run_checkset(customers, checks)
```

## Did validation pass?

[`all_passed`](@ref) answers the yes-or-no question:

```@example results
all_passed(summary)
```

To stop a script or pipeline when data is invalid, use [`assert_valid`](@ref).
It returns the summary when every check passes, and otherwise throws a
[`ValidationError`](@ref) whose message includes the full report:

```julia
summary = assert_valid(customers, checks)   # run and assert in one step
assert_valid(summary)                       # or assert on an existing summary
```

```@example results
try
    assert_valid(summary)
catch err
    showerror(stdout, err)
end
```

The thrown error keeps the summary in its `summary` field, so a `catch` block
can still inspect the failures.

## Which checks failed?

```@example results
failed_checks(summary)
```

```@example results
passed_checks(summary)
```

Both return check names in the order the checks were defined.

## Which rows failed?

[`failing_rows`](@ref) has three methods:

```@example results
failing_rows(summary)                  # unique rows that failed any check
```

```@example results
failing_rows(summary, "Valid email")   # rows that failed one check
```

The third method takes a single [`CheckResult`](@ref), the per-check result
stored in a summary.

Use the row indices to pull the offending records out of the original table:

```@example results
customers[failing_rows(summary), :]
```

To see *why* each row failed, [`row_failures`](@ref) lists the checks that
each failing row broke. It returns a table, so it converts directly to a
`DataFrame`:

```@example results
DataFrame(row_failures(summary))
```

## Pass rates

[`pass_rate`](@ref) with only a summary returns the percentage of rows that
passed *every* check. With a check name, it returns the pass rate for that one
check:

```@example results
pass_rate(summary)
```

```@example results
pass_rate(summary, "Valid email")
```

If a check could not run because its columns are missing from the data, its
pass rate is `0.0`, and so is the overall pass rate, since no row can be said
to have passed it.

## Counting failures

[`total_failures`](@ref) counts failures across all checks. A row that fails
two checks counts twice, so this number can be larger than
`length(failing_rows(summary))`:

```@example results
total_failures(summary), length(failing_rows(summary))
```

## The summary as a table

A [`CheckSummary`](@ref) is itself a [Tables.jl](https://github.com/JuliaData/Tables.jl)
table with one row per check, so a per-check report is one call away. Save it,
plot it, or compare it across runs:

```@example results
DataFrame(summary)
```

The same works with any Tables.jl sink, for example `CSV.write("report.csv", summary)`.

## Warnings

Checks defined with `severity=:warning` (see [Warning-level checks](@ref))
appear in the report and in the summary table, but do not count as failures:

- [`failed_checks`](@ref) and [`all_passed`](@ref) ignore them, and
  [`assert_valid`](@ref) never throws because of them.
- [`failing_rows(summary)`](@ref failing_rows), [`total_failures`](@ref) and the
  overall [`pass_rate`](@ref) only consider error-level checks.
- [`warning_checks`](@ref) lists the warning checks that did not pass.

Per-check functions such as `failing_rows(summary, name)` and
`pass_rate(summary, name)` work the same for both severities, and
[`row_failures`](@ref) includes both.

## Timing

```@example results
execution_time(summary)   # seconds
```

## Printing the report elsewhere

[`print_summary`](@ref) writes the report to any `IO`, such as a log file, or
captures it as a string:

```julia
open("validation.log", "w") do io
    print_summary(io, summary)
end

text = sprint(print_summary, summary)
```

Inside collections and string interpolation a summary prints in a compact
one-line form:

```@example results
"Result: $summary"
```

## Running checks in parallel

On large tables, pass `threaded = true` to run the checks in a checkset
concurrently, one task per check:

```julia
summary = run_checkset(data, checks; threaded = true)
```

!!! note "Start Julia with threads"
    Threading only helps when Julia is started with more than one thread, for
    example `julia --threads=auto`. Parallelism is across checks, not across
    rows, so a checkset with a single check gains nothing.
