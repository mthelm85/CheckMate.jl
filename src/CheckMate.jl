module CheckMate

using Tables
using MacroTools
using Base.Threads: @spawn, nthreads

include("types.jl")
include("macros.jl")
include("reporting.jl")
include("tables.jl")

export Check, CheckSet, CheckResult, CheckSummary, ValidationError                                            # Types
export @checkset                                                                                              # Macros
export run_checkset, failed_checks, passed_checks, warning_checks, all_passed, assert_valid,                  # Functions
       total_failures, pass_rate, execution_time, failing_rows, row_failures, check_columns, check_names
export print_summary                                                                                          # Reporting

"""
    run_checkset(data, checkset::CheckSet; threaded::Bool=false)::CheckSummary

Execute a complete set of validation checks on the provided data.

Runs all checks in a given CheckSet, with options for sequential or parallel execution.

# Arguments
- `data`: The dataset to be validated (must support Tables.jl interface)
- `checkset::CheckSet`: A collection of checks to be performed
- `threaded::Bool`: Whether to run checks in parallel (default: false)

# Returns
A `CheckSummary` containing:
- Name of the checkset
- Results of individual checks
- Total execution time

# Examples
```julia
summary = run_checkset(dataset, payment_checks, threaded=true)
```
"""
function run_checkset(
    data,
    checkset::CheckSet;
    threaded::Bool=false
)::CheckSummary
    start_ns = time_ns()
    # Materialize a column view once so row-oriented sources (e.g. a Vector of
    # NamedTuples) work, and so threaded checks share a single conversion.
    results = run_checks(Tables.columns(data), checkset, threaded)

    CheckSummary(
        checkset.name,
        results,
        (time_ns() - start_ns) / 1e9,
        check_names(checkset)
    )
end

# (name, result) pairs in check definition order
ordered_results(summary::CheckSummary) =
    [(name, summary.check_results[name]) for name in summary.check_order]

# Results that count toward overall pass/fail (warning-level checks do not)
error_results(summary::CheckSummary) =
    [result for (_, result) in ordered_results(summary) if result.severity === :error]

"""
    ValidationError(summary::CheckSummary)

Thrown by [`assert_valid`](@ref) when one or more error-level checks fail.
The `summary` field holds the full [`CheckSummary`](@ref), and the error
message includes the validation report.
"""
struct ValidationError <: Exception
    summary::CheckSummary
end

function Base.showerror(io::IO, e::ValidationError)
    failed = failed_checks(e.summary)
    print(io, "ValidationError: ", length(failed), " of ", length(e.summary.check_order),
          " checks failed in checkset \"", e.summary.checkset_name, "\": ", join(failed, ", "))
    print_summary(io, e.summary)
end

"""
    all_passed(summary::CheckSummary)::Bool

Return `true` if every error-level check passed. Warning-level checks are
ignored.

# Examples
```julia
all_passed(summary) || @warn "Validation failed" failed_checks(summary)
```
"""
all_passed(summary::CheckSummary)::Bool = isempty(failed_checks(summary))

"""
    assert_valid(summary::CheckSummary)::CheckSummary
    assert_valid(data, checkset::CheckSet; threaded::Bool=false)::CheckSummary

Throw a [`ValidationError`](@ref) if any error-level check failed, otherwise
return the summary. The second form runs the checkset first.

Warning-level checks never cause an error.

# Examples
```julia
summary = assert_valid(df, checks)      # throws if df is invalid
assert_valid(run_checkset(df, checks))  # same, from an existing summary
```
"""
function assert_valid(summary::CheckSummary)::CheckSummary
    all_passed(summary) || throw(ValidationError(summary))
    summary
end

assert_valid(data, checkset::CheckSet; threaded::Bool=false)::CheckSummary =
    assert_valid(run_checkset(data, checkset; threaded=threaded))


"""
    failed_checks(summary::CheckSummary)::Vector{String}

Retrieve the names of all error-level checks that did not pass, in definition
order. Warning-level checks are listed by [`warning_checks`](@ref) instead.

# Arguments
- `summary::CheckSummary`: A summary object containing the results of multiple checks.

# Returns
A vector of check names that failed (did not pass).

# Examples
```julia
checks = failed_checks(summary)  # Returns ['check1', 'check2', ...]
```
"""
function failed_checks(summary::CheckSummary)::Vector{String}
    [name for (name, r) in ordered_results(summary) if !r.passed && r.severity === :error]
end

"""
    warning_checks(summary::CheckSummary)::Vector{String}

Retrieve the names of all warning-level checks that did not pass, in definition
order.

# Examples
```julia
warnings = warning_checks(summary)  # Returns ["Round amounts", ...]
```
"""
function warning_checks(summary::CheckSummary)::Vector{String}
    [name for (name, r) in ordered_results(summary) if !r.passed && r.severity === :warning]
end

"""
    passed_checks(summary::CheckSummary)::Vector{String}

Retrieve the names of all checks that passed successfully, in definition order.

# Arguments
- `summary::CheckSummary`: A summary object containing the results of multiple checks.

# Returns
A vector of check names that passed.

# Examples
```julia
checks = passed_checks(summary)  # Returns ['check3', 'check4', ...]
```
"""
function passed_checks(summary::CheckSummary)::Vector{String}
    [name for (name, r) in ordered_results(summary) if r.passed]
end

"""
    total_failures(summary::CheckSummary)::Int

Calculate the total number of check failures across all error-level checks.

Note: a single row that fails multiple checks is counted once per check.
To get the unique set of failing rows, use `failing_rows(summary)`.
Failures of warning-level checks are not counted.

# Arguments
- `summary::CheckSummary`: A summary object containing the results of multiple checks.

# Returns
Total count of check failures across all checks.

# Examples
```julia
total_failed = total_failures(summary)  # Returns the total number of check failures
```
"""
function total_failures(summary::CheckSummary)::Int
    sum(result -> length(result.failing_rows), error_results(summary); init=0)
end

"""
    pass_rate(summary::CheckSummary)::Float64

Calculate the percentage of rows that passed all error-level checks.

Warning-level checks are ignored. If an error-level check could not run because
its columns are missing from the data, no row can be said to pass, and the
result is `0.0`.

# Arguments
- `summary::CheckSummary`: A summary object containing the results of multiple checks.

# Returns
Percentage of rows that passed all checks, rounded to two decimal places (0-100).

# Examples
```julia
rate = pass_rate(summary)  # Returns 95.0 if 95% of rows passed all checks
```
"""
function pass_rate(summary::CheckSummary)::Float64
    results = error_results(summary)
    any(result -> !isempty(result.missing_columns), results) && return 0.0

    total_rows = maximum(result.total_rows for result in results; init=0)
    total_rows == 0 && return 100.0

    # A row passes if it's not in the failing_rows of any check
    all_failing_rows = Set{Int}()
    for result in results
        union!(all_failing_rows, result.failing_rows)
    end

    n_failed = length(all_failing_rows)
    round(100.0 * (total_rows - n_failed) / total_rows, digits=2)
end

"""
    pass_rate(summary::CheckSummary, check_name::String)::Float64

Calculate the pass rate for a specific check based on number of rows that passed.

# Arguments
- `summary::CheckSummary`: A summary object containing the results of multiple checks.
- `check_name::String`: The name of the specific check to calculate pass rate for.

# Returns
Percentage of rows that passed the specified check, rounded to two decimal places (0-100).
Returns `0.0` if the check's columns are missing from the data, and `100.0` for
an empty table.

# Examples
```julia
rate = pass_rate(summary, "column_type_check")  # Returns 95.0 if 95% of rows passed this check
```
"""
function pass_rate(summary::CheckSummary, check_name::String)::Float64
    haskey(summary.check_results, check_name) || error("Check '$check_name' not found")
    result = summary.check_results[check_name]

    isempty(result.missing_columns) || return 0.0
    result.total_rows == 0 && return 100.0

    n_failed = length(result.failing_rows)
    round(100.0 * (result.total_rows - n_failed) / result.total_rows, digits=2)
end

"""
    execution_time(summary::CheckSummary)::Float64

Retrieve the total execution time of all checks.

# Arguments
- `summary::CheckSummary`: A summary object containing the results of multiple checks.

# Returns
Total execution time in seconds (unrounded).

# Examples
```julia
time = execution_time(summary)  # Returns execution time in seconds
```
"""
execution_time(summary::CheckSummary)::Float64 = summary.time_elapsed

"""
    failing_rows(result::CheckResult)::Vector{Int}

Retrieve the row indices that failed for a specific check result.

# Arguments
- `result::CheckResult`: A result object for a single check.

# Returns
A vector of row indices that failed the check.

# Examples
```julia
failed_indices = failing_rows(result)  # Returns [2, 5, 8, ...]
```
"""
function failing_rows(result::CheckResult)::Vector{Int}
    result.failing_rows
end

"""
    failing_rows(summary::CheckSummary, check_name::String)::Vector{Int}

Retrieve the row indices that failed for a specific named check.

# Arguments
- `summary::CheckSummary`: A summary object containing the results of multiple checks.
- `check_name::String`: The name of the specific check to retrieve failing rows for.

# Returns
A vector of row indices that failed the specified check.

# Throws
- `ErrorException` if the specified check name is not found in the summary.

# Examples
```julia
failed_indices = failing_rows(summary, "column_type_check")  # Returns [3, 7, 10, ...]
```
"""
function failing_rows(summary::CheckSummary, check_name::String)::Vector{Int}
    haskey(summary.check_results, check_name) || error("Check '$check_name' not found")
    failing_rows(summary.check_results[check_name])
end

"""
    failing_rows(summary::CheckSummary)::Vector{Int}

Retrieve all unique failing row indices across all error-level checks.
Rows that only failed warning-level checks are not included.

# Arguments
- `summary::CheckSummary`: A summary object containing the results of multiple checks.

# Returns
A sorted vector of unique row indices that failed any check.

# Examples
```julia
all_failed_indices = failing_rows(summary)  # Returns [1, 2, 5, 8, ...]
```
"""
function failing_rows(summary::CheckSummary)::Vector{Int}
    all_failing = Set{Int}()
    for result in error_results(summary)
        union!(all_failing, result.failing_rows)
    end
    sort!(collect(all_failing))
end

"""
    row_failures(summary::CheckSummary)

List, for each row that failed at least one check, the names of the checks it
failed. Both error- and warning-level checks are included.

Returns a Tables.jl column table, a `NamedTuple` with columns `row` (sorted
ascending) and `checks` (check names in definition order), so it can be passed
straight to `DataFrame`.

# Examples
```julia
rf = row_failures(summary)
rf.row      # [2, 3, 5]
rf.checks   # [["Positive Amount"], ["Valid Currency"], ["Positive Amount", "Valid Currency"]]
```
"""
function row_failures(summary::CheckSummary)
    by_row = Dict{Int,Vector{String}}()
    for (name, result) in ordered_results(summary)
        for row in result.failing_rows
            push!(get!(Vector{String}, by_row, row), name)
        end
    end
    rows = sort!(collect(keys(by_row)))
    (row = rows, checks = [by_row[row] for row in rows])
end

"""
    check_columns(checkset::CheckSet, check_name::String)::Vector{Symbol}

Retrieve the column names for a specific named check.

# Arguments
- `checkset::CheckSet`: A checkset object.
- `check_name::String`: The name of the specific check to retrieve column names for.

# Returns
A vector of column names used in the specified check.

# Examples
```julia
columns = check_columns(checkset, "column_type_check")  # Returns [:a, :b]
```
"""
function check_columns(checkset::CheckSet, check_name::String)::Vector{Symbol}
    idx = findfirst(x -> x.name == check_name, checkset.checks)
    isnothing(idx) && error("Check '$check_name' in checkset '$(checkset.name)' not found")
    checkset.checks[idx].columns
end

"""
    check_names(checkset::CheckSet)::Vector{String}

Retrieve the names of all checks in a given checkset.

# Arguments
- `checkset::CheckSet`: A checkset object.

# Returns
A vector of check names in the specified checkset.

# Examples
```julia
names = check_names(checkset)  # Returns ["check1", "check2", ...]
```
"""
function check_names(checkset::CheckSet)::Vector{String}
    map(check -> check.name, checkset.checks)
end

function run_check(data, check::Check)::CheckResult
    missing_cols = missing_columns(data, check.columns)
    isempty(missing_cols) || return CheckResult(
        false,
        Int[],
        NamedTuple[],
        "Required columns not found: $missing_cols",
        0,
        check.severity,
        missing_cols,
        0,
        nothing
    )

    columns = get_columns(data, check.columns)
    failing_rows, failing_values, exception_count, first_exception = check_rows(columns, check)
    total_rows = length(first(columns))
    n_failed = length(failing_rows)

    message = if n_failed == 0
        "All rows passed"
    elseif exception_count == 0
        "$n_failed rows failed"
    else
        "$n_failed rows failed ($exception_count due to exceptions in condition function)"
    end

    CheckResult(
        isempty(failing_rows),
        failing_rows,
        failing_values,
        message,
        total_rows,
        check.severity,
        Symbol[],
        exception_count,
        first_exception
    )
end

function run_checks(data, checkset::CheckSet, threaded::Bool)::Dict{String,CheckResult}
    if threaded && length(checkset.checks) > 1
        tasks = [@spawn run_check(data, check) for check in checkset.checks]
        results = fetch.(tasks)
        return Dict(check.name => result for (check, result) in zip(checkset.checks, results))
    else
        return Dict(check.name => run_check(data, check) for check in checkset.checks)
    end
end

function missing_columns(data, cols)::Vector{Symbol}
    colnames = Tables.columnnames(data)
    return [col for col in cols if !(col in colnames)]
end

function get_columns(data, cols)::Vector
    [Tables.getcolumn(data, col) for col in cols]
end

function check_rows(columns, check::Check)
    # Function barrier: the condition and column types are only known at runtime,
    # so dispatch once here and let _check_rows specialize on them.
    _check_rows(check.condition, Tuple(columns), Val(Tuple(check.columns)))
end

function _check_rows(condition::F, columns::NTuple{N,Any}, ::Val{names}) where {F,N,names}
    n = length(first(columns))
    failing_rows = Int[]
    failing_values = NamedTuple{names}[]
    exception_count = 0
    first_exception::Union{Nothing,Pair{Int,Any}} = nothing

    @inbounds for i in 1:n
        vals = ntuple(j -> columns[j][i], Val(N))
        passed = try
            # A non-Bool result (e.g. `missing` from `missing > 0`) counts as an exception
            condition(vals...)::Bool
        catch e
            e isa InterruptException && rethrow()
            exception_count += 1
            first_exception === nothing && (first_exception = i => e)
            false
        end
        if !passed
            push!(failing_rows, i)
            push!(failing_values, NamedTuple{names}(vals))
        end
    end

    failing_rows, failing_values, exception_count, first_exception
end

end # module
