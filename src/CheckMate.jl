module CheckMate

using Tables
using MacroTools
using Base.Threads: @threads, nthreads

include("types.jl")
include("macros.jl")
include("reporting.jl")

export Check, CheckSet, CheckResult, CheckSummary                                                             # Types
export @checkset                                                                                              # Macros
export run_checkset, failed_checks, passed_checks, total_failures, pass_rate, execution_time,                 # Functions
       failing_rows, check_columns, check_names
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

Calculate the percentage of rows that passed all checks.

# Arguments
- `summary::CheckSummary`: A summary object containing the results of multiple checks.

# Returns
Percentage of rows that passed all checks, rounded to one decimal place (0-100).

# Examples
```julia
rate = pass_rate(summary)  # Returns 95.0 if 95% of rows passed all checks
```
"""
function pass_rate(summary::CheckSummary)::Float64
    # Get the total number of rows from any check result
    # Since all checks run on the same data, total_rows should be the same
    first_result = first(values(summary.check_results))
    total_rows = first_result.total_rows
    
    if total_rows == 0
        return 0.0
    end
    
    # A row passes if it's not in the failing_rows of any check
    all_failing_rows = Set{Int}()
    for result in values(summary.check_results)
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
Percentage of rows that passed the specified check, rounded to one decimal place (0-100).

# Examples
```julia
rate = pass_rate(summary, "column_type_check")  # Returns 95.0 if 95% of rows passed this check
```
"""
function pass_rate(summary::CheckSummary, check_name::String)::Float64
    haskey(summary.check_results, check_name) || error("Check '$check_name' not found")
    result = summary.check_results[check_name]
    
    if result.total_rows == 0
        return 0.0
    end
    
    n_failed = length(result.failing_rows)
    round(100.0 * (result.total_rows - n_failed) / result.total_rows, digits=2)
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
    in(check_name, map(x -> x.name, checkset.checks)) || error("Check '$check_name' in checkset '$checkset' not found")
    checkset.checks[findfirst(x -> x.name == check_name, checkset.checks)].columns
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
    !has_required_columns(data, check.columns) && return CheckResult(
        false, 
        Int[], 
        NamedTuple[],
        "Required columns not found: $(check.columns)",
        0  # No valid rows if columns missing
    )
    
    columns = get_columns(data, check.columns)
    failing_rows, failing_values = check_rows(columns, check)
    total_rows = length(first(columns))
    
    CheckResult(
        isempty(failing_rows),
        failing_rows,
        failing_values,
        isempty(failing_rows) ? "All rows passed" : "$(length(failing_rows)) rows failed",
        total_rows
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
    n = length(first(columns))
    failing_rows = sizehint!(Int[], n)  # Use max possible size
    failing_values = sizehint!(NamedTuple{Tuple(check.columns)}[], n)
    
    col_names = Tuple(check.columns)
    
    @inbounds for i in 1:n
        vals = ntuple(j -> columns[j][i], length(columns))
        try
            if !check.condition(vals...)
                push!(failing_rows, i)
                push!(failing_values, NamedTuple{col_names}(vals))
            end
        catch e
            push!(failing_rows, i)
            push!(failing_values, NamedTuple{col_names}(vals))
        end
    end
    
    failing_rows, failing_values
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
