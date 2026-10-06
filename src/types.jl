import Base: isless

const SEVERITIES = (:error, :warning)

"""
    Check

A single validation rule, created by `@check` inside [`@checkset`](@ref).

# Fields
- `name::String`: The check's name, used in reports and lookups.
- `condition::Function`: Called once per row with the values of `columns`;
  returns `true` if the row passes.
- `columns::Vector{Symbol}`: The columns passed to `condition`, in order.
- `severity::Symbol`: `:error` (the default) or `:warning`. Warning checks are
  reported but do not count as failures.
"""
struct Check
    name::String
    condition::Function
    columns::Vector{Symbol}
    severity::Symbol

    function Check(name, condition, columns, severity::Symbol=:error)
        severity in SEVERITIES ||
            error("Check severity must be one of $SEVERITIES, got: $(repr(severity))")
        new(name, condition, columns, severity)
    end
end

"""
    CheckSet

A named collection of [`Check`](@ref)s, created with [`@checkset`](@ref) and
run with [`run_checkset`](@ref).

# Fields
- `name::String`: The checkset's name, shown in the report header.
- `checks::Vector{Check}`: The checks, in definition order.
"""
struct CheckSet
    name::String
    checks::Vector{Check}
end

"""
    CheckResult

The outcome of running a single [`Check`](@ref). Stored in the
`check_results` field of a [`CheckSummary`](@ref).

# Fields
- `passed::Bool`: `true` if every row passed.
- `failing_rows::Vector{Int}`: Indices of rows that failed, in ascending order.
- `failing_values::Vector{NamedTuple}`: The column values for each failing row.
- `message::String`: A human-readable description of the result.
- `total_rows::Int`: Number of rows evaluated (`0` if a required column was
  missing).
- `severity::Symbol`: The check's severity, `:error` or `:warning`.
- `missing_columns::Vector{Symbol}`: Required columns that were not in the
  data. When non-empty, no rows were evaluated.
- `exception_count::Int`: Number of rows where the condition threw an exception
  or returned a non-`Bool` value.
- `first_exception::Union{Nothing, Pair{Int, Any}}`: `row => exception` for the
  first such row, or `nothing`.
"""
struct CheckResult
    passed::Bool
    failing_rows::Vector{Int}
    failing_values::Vector{NamedTuple}
    message::String
    total_rows::Int
    severity::Symbol
    missing_columns::Vector{Symbol}
    exception_count::Int
    first_exception::Union{Nothing,Pair{Int,Any}}
end

CheckResult(passed, failing_rows, failing_values, message, total_rows) =
    CheckResult(passed, failing_rows, failing_values, message, total_rows, :error, Symbol[], 0, nothing)

"""
    CheckSummary

The result of [`run_checkset`](@ref). Displaying a `CheckSummary` prints a
validation report.

A `CheckSummary` is also a [Tables.jl](https://github.com/JuliaData/Tables.jl)
table with one row per check, so `DataFrame(summary)` gives a per-check
overview. Its columns are `check`, `severity`, `passed`, `failures`,
`exceptions`, `pass_rate` and `message`.

# Fields
- `checkset_name::String`: Name of the checkset that was run.
- `check_results::Dict{String, CheckResult}`: Results keyed by check name.
- `time_elapsed::Float64`: Wall-clock time in seconds.
- `check_order::Vector{String}`: Check names in definition order.
"""
struct CheckSummary
    checkset_name::String
    check_results::Dict{String, CheckResult}
    time_elapsed::Float64
    check_order::Vector{String}
end

CheckSummary(checkset_name, check_results, time_elapsed) =
    CheckSummary(checkset_name, check_results, time_elapsed, sort!(collect(keys(check_results))))

function isless(a::CheckResult, b::CheckResult)
    # Sort failed checks before passed checks
    if a.passed != b.passed
        return b.passed
    end
    # If both passed or both failed, sort by number of failures
    return length(a.failing_rows) > length(b.failing_rows)
end
