import Base: show
using Printf

function print_summary(io::IO, summary::CheckSummary)
    println(io, "\n" * "="^80)
    printstyled(io, "Check Summary: $(summary.checkset_name)\n", color=:blue, bold=true)
    println(io, "="^80 * "\n")

    # Sort by check results directly
    sorted_results = sort(collect(summary.check_results); by=x->x.second)
    
    for (name, result) in sorted_results
        print_check_result(io, name, result)
    end

    print_summary_footer(io, summary)
end

# print_summary(summary::CheckSummary) = print_summary(stdout, summary)

function print_check_result(io::IO, name::String, result::CheckResult)
    status = result.passed ? "✓" : "✗"
    color = result.passed ? :green : :red
    
    printstyled(io, "$status ", color=color, bold=true)
    print(io, "$name: ")
    printstyled(io, result.message * "\n", color=color)
    
    if !result.passed
        print_failures(io, result)
    end
end

function print_failures(io::IO, result::CheckResult)
    n_failures = length(result.failing_rows)
    if n_failures > 10
        # Show first 5 and last 5 failures
        for i in 1:5
            print_failure_row(io, result.failing_rows[i], result.failing_values[i])
        end
        println(io, "   ... $(n_failures-10) more failures ...")
        for i in (n_failures-4):n_failures
            print_failure_row(io, result.failing_rows[i], result.failing_values[i])
        end
    else
        for (row, vals) in zip(result.failing_rows, result.failing_values)
            print_failure_row(io, row, vals)
        end
    end
end

function print_failure_row(io::IO, row::Int, values::NamedTuple)
    println(io, "   Row $row: " * join(["$k=$v" for (k,v) in pairs(values)], ", "))
end

function print_summary_footer(io::IO, summary::CheckSummary)
    n_total = length(summary.check_results)
    n_passed = count(x -> x.second.passed, summary.check_results)
    
    println(io, "\nSummary:")
    @printf(io, " %d/%d checks passed (%.1f%%)\n", 
        n_passed, n_total, 100.0 * n_passed / n_total)
    println(io, "Checks completed in $(summary.time_elapsed) seconds")
end

function show(io::IO, summary::CheckSummary)
    print_summary(io, summary)
end

function show(io::IO, ::MIME"text/plain", summary::CheckSummary)
    print_summary(io, summary)
end

function show(io::IO, checkset::CheckSet)
    println(io, "CheckSet: \"$(checkset.name)\"")
    println(io, "Number of checks: $(length(checkset.checks))")
    for check in checkset.checks
        print(io, "  ▪ ")
        printstyled(io, check.name, color=:blue)
        print(io, " (columns: ")
        printstyled(io, join(check.columns, ", "), color=:cyan)
        println(io, ")")
    end
end

function show(io::IO, ::MIME"text/plain", checkset::CheckSet)
    show(io, checkset)
end