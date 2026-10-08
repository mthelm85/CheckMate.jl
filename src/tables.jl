# A CheckSummary is a Tables.jl table with one row per check, in definition order,
# so `DataFrame(summary)` or `CSV.write(path, summary)` give a per-check report.

Tables.istable(::Type{CheckSummary}) = true
Tables.columnaccess(::Type{CheckSummary}) = true

function Tables.columns(summary::CheckSummary)
    results = ordered_results(summary)
    (
        check      = [name for (name, _) in results],
        severity   = [r.severity for (_, r) in results],
        passed     = [r.passed for (_, r) in results],
        failures   = [length(r.failing_rows) for (_, r) in results],
        exceptions = [r.exception_count for (_, r) in results],
        pass_rate  = [pass_rate(summary, name) for (name, _) in results],
        message    = [r.message for (_, r) in results],
    )
end
