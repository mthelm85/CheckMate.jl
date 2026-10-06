import Base: show
using Printf

"""
    print_summary([io::IO], summary::CheckSummary)

Write the validation report for `summary` to `io` (default `stdout`). This is
the same report shown when a [`CheckSummary`](@ref) is displayed.

# Examples
```julia
open("validation.log", "w") do io
    print_summary(io, summary)
end
```
"""
function print_summary(io::IO, summary::CheckSummary)
    println(io, "\n" * "="^80)
    printstyled(io, "Check Summary: $(summary.checkset_name)\n", color=:blue, bold=true)
    println(io, "="^80 * "\n")

    # Failed checks first, then warnings, then passed; most failures first within
    # each group. sort is stable, so ties keep definition order.
    sorted_results = sort(ordered_results(summary); by=report_sort_key)

    for (name, result) in sorted_results
        print_check_result(io, name, result)
    end

    print_summary_footer(io, summary)
end

print_summary(summary::CheckSummary) = print_summary(stdout, summary)

function report_sort_key((name, result))
    group = result.passed ? 2 : result.severity === :warning ? 1 : 0
    (group, -length(result.failing_rows))
end

function print_check_result(io::IO, name::String, result::CheckResult)
    status, color = if result.passed
        "✓", :green
    elseif result.severity === :warning
        "⚠", :yellow
    else
        "✗", :red
    end

    printstyled(io, "$status ", color=color, bold=true)
    print(io, "$name: ")
    printstyled(io, result.message * "\n", color=color)

    if !result.passed
        print_first_exception(io, result)
        print_failures(io, result)
    end
end

function print_first_exception(io::IO, result::CheckResult)
    result.first_exception === nothing && return
    row, e = result.first_exception
    # First line only, so a long stack-free message can't flood the report
    msg = first(split(sprint(showerror, e), '\n'))
    length(msg) > 120 && (msg = first(msg, 117) * "...")
    printstyled(io, "   First exception (row $row): $msg\n", color=:light_black)
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
    n_warnings = length(warning_checks(summary))

    println(io, "\nSummary:")
    if n_total == 0
        println(io, " 0/0 checks (empty checkset)")
    else
        @printf(io, " %d/%d checks passed (%.1f%%)", n_passed, n_total, 100.0 * n_passed / n_total)
        n_warnings > 0 && print(io, ", $n_warnings with warnings")
        println(io)
    end
    println(io, "Checks completed in $(format_duration(summary.time_elapsed))")
end

format_duration(seconds::Real) =
    seconds < 1 ? @sprintf("%.1f ms", 1000 * seconds) : @sprintf("%.2f seconds", seconds)

# Two-argument show is the compact form, used inside collections and string
# interpolation; the full report is the text/plain display.
function show(io::IO, summary::CheckSummary)
    n_passed = count(x -> x.second.passed, summary.check_results)
    print(io, "CheckSummary(\"", summary.checkset_name, "\": ",
          n_passed, "/", length(summary.check_results), " checks passed)")
end

function show(io::IO, ::MIME"text/plain", summary::CheckSummary)
    print_summary(io, summary)
end

function show(io::IO, checkset::CheckSet)
    n = length(checkset.checks)
    print(io, "CheckSet(\"", checkset.name, "\", ", n, n == 1 ? " check)" : " checks)")
end

function show(io::IO, ::MIME"text/plain", checkset::CheckSet)
    println(io, "CheckSet: \"$(checkset.name)\"")
    println(io, "Number of checks: $(length(checkset.checks))")
    for check in checkset.checks
        print(io, "  ▪ ")
        printstyled(io, check.name, color=:blue)
        print(io, " (columns: ")
        printstyled(io, join(check.columns, ", "), color=:cyan)
        print(io, ")")
        check.severity === :warning && printstyled(io, " [warning]", color=:yellow)
        println(io)
    end
end
