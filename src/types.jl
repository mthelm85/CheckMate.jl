import Base: isless

struct Check
    name::String
    condition::Function
    columns::Vector{Symbol}
end

struct CheckSet
    name::String
    checks::Vector{Check}
end

struct CheckResult
    passed::Bool
    failing_rows::Vector{Int}
    failing_values::Vector{NamedTuple}
    message::String
end

struct CheckSummary
    checkset_name::String
    check_results::Dict{String, CheckResult}
    time_elapsed::Float64
end

function isless(a::CheckResult, b::CheckResult)
    # Sort failed checks before passed checks
    if a.passed != b.passed
        return b.passed
    end
    # If both passed or both failed, sort by number of failures
    return length(a.failing_rows) > length(b.failing_rows)
end