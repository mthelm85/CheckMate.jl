module CheckMate

using Tables
using MacroTools
using Base.Threads: @threads, nthreads

include("types.jl")
include("macros.jl")
include("reporting.jl")

export Check, CheckSet, CheckResult, CheckSummary                                                             # Types
export @checkset                                                                                              # Macros
export run_checkset, failed_checks, passed_checks, total_failures, pass_rate, execution_time, failing_rows    # Functions
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
    start_time = time()
    results = run_checks(data, checkset, threaded)
    
    CheckSummary(
        checkset.name,
        results,
        round(time() - start_time, digits=2)
    )
end


"""
    failed_checks(summary::CheckSummary)::Vector{String}

Retrieve the names of all checks that did not pass.

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
    filter(name -> !summary.check_results[name].passed, collect(keys(summary.check_results)))
end

"""
    passed_checks(summary::CheckSummary)::Vector{String}

Retrieve the names of all checks that passed successfully.

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
    filter(name -> summary.check_results[name].passed, collect(keys(summary.check_results)))
end

"""
    total_failures(summary::CheckSummary)::Int

Calculate the total number of failing rows across all checks.

# Arguments
- `summary::CheckSummary`: A summary object containing the results of multiple checks.

# Returns
Total count of rows that failed validation across all checks.

# Examples
```julia
total_failed = total_failures(summary)  # Returns the total number of failing rows
```
"""
function total_failures(summary::CheckSummary)::Int
    sum(result -> length(result.failing_rows), values(summary.check_results))
end

"""
    pass_rate(summary::CheckSummary)::Float64

Calculate the percentage of checks that passed.

# Arguments
- `summary::CheckSummary`: A summary object containing the results of multiple checks.

# Returns
Percentage of checks passed, rounded to one decimal place (0-100).

# Examples
```julia
rate = pass_rate(summary)  # Returns 95.0 for 95% pass rate
```
"""
function pass_rate(summary::CheckSummary)::Float64
    n_total = length(summary.check_results)
    n_passed = length(passed_checks(summary))
    round(100.0 * n_passed / n_total, digits=1)
end

"""
    execution_time(summary::CheckSummary)::Float64

Retrieve the total execution time of all checks.

# Arguments
- `summary::CheckSummary`: A summary object containing the results of multiple checks.

# Returns
Total execution time in seconds.

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

Retrieve all unique failing row indices across all checks.

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
    sort(unique(vcat([failing_rows(result) for result in values(summary.check_results)]...)))
end

function run_check(data, check::Check)::CheckResult
    # Early return if required columns aren't present
    !has_required_columns(data, check.columns) && return CheckResult(
        false, 
        Int[], 
        NamedTuple[],
        "Required columns not found: $(check.columns)"
    )
    
    # Get relevant columns and check rows
    columns = get_columns(data, check.columns)
    failing_rows, failing_values = check_rows(columns, check)
    
    CheckResult(
        isempty(failing_rows),
        failing_rows,
        failing_values,
        isempty(failing_rows) ? "All rows passed" : "$(length(failing_rows)) rows failed"
    )
end

function run_checks(data, checkset::CheckSet, threaded::Bool)::Dict{String,CheckResult}
    results = Dict{String,CheckResult}()
    
    if threaded && length(checkset.checks) > 1
        # Thread-safe dictionary access
        locks = Dict(check.name => ReentrantLock() for check in checkset.checks)
        
        @threads for check in checkset.checks
            result = run_check(data, check)
            lock(locks[check.name]) do
                results[check.name] = result
            end
        end
    else
        # Sequential execution
        for check in checkset.checks
            results[check.name] = run_check(data, check)
        end
    end
    
    return results
end

function has_required_columns(data, cols)::Bool
    colnames = Tables.columnnames(data) |> collect
    return all(col -> col in colnames, cols)
end

function get_columns(data, cols)::Vector
    [Tables.getcolumn(data, col) for col in cols]
end

function check_rows(columns, check::Check)
    failing_rows = Int[]
    failing_values = NamedTuple[]
    
    for (i, vals) in enumerate(zip(columns...))
        try
            if !check.condition(vals...)
                push_failure!(failing_rows, failing_values, i, vals, check)
            end
        catch e
            # Record both condition failures and errors
            push_failure!(failing_rows, failing_values, i, vals, check)
        end
    end
    
    failing_rows, failing_values
end

function push_failure!(failing_rows, failing_values, idx, vals, check)
    push!(failing_rows, idx)
    push!(failing_values, NamedTuple{Tuple(check.columns)}(vals))
end

function make_summary(checkset::CheckSet, results::Dict, data, start_time::Float64)
    CheckSummary(
        checkset.name,
        results,
        data,
        round(time() - start_time, digits=2)
    )
end

end # module