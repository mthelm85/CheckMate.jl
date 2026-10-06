```@meta
CurrentModule = CheckMate
```

# Examples

Complete validation scenarios that combine the features covered in the rest of
the manual.

## Employee records

A typical HR extract with single-column format rules and a cross-field rule
on dates.

```@example employees
using CheckMate, DataFrames, Dates

employees = DataFrame(
    emp_id     = ["E001", "E002", "E03", "E004", "E005", "E006"],
    name       = ["Ada", "Grace", "Alan", "", "Edsger", "Barbara"],
    hire_date  = Date.(["2019-03-01", "2021-07-15", "2020-01-10",
                        "2018-11-30", "2023-05-02", "2022-09-19"]),
    term_date  = [missing, missing, Date("2019-12-31"),
                  missing, Date("2024-01-15"), missing],
    salary     = [98_000, 105_000, 87_500, 72_000, -1, 91_000],
)

valid_id(id) = occursin(r"^E\d{3}$", id)
not_blank(s) = !isempty(strip(s))
plausible_salary(x) = 20_000 <= x <= 500_000
terminated_after_hire(h, t) = ismissing(t) || t > h

checks = @checkset "Employee Records" begin
    @check "ID format"                valid_id(:emp_id)
    @check "Name present"             not_blank(:name)
    @check "Plausible salary"         plausible_salary(:salary)
    @check "Termination after hire"   terminated_after_hire(:hire_date, :term_date)
end

summary = run_checkset(employees, checks)
```

Records that need manual review:

```@example employees
employees[failing_rows(summary), [:emp_id, :name]]
```

## Sensor readings

Validating time-series data, where each reading must be within physical limits
and the timestamps must increase. Ordering rules compare each row with the one
before it, so we add a lagged column first.

```@example sensors
using CheckMate, DataFrames

readings = DataFrame(
    t        = [0, 10, 20, 15, 40, 50, 60],
    temp_c   = [21.4, 21.6, 21.9, 22.1, 85.0, 22.3, 22.2],
    humidity = [40.1, 40.3, 40.0, 39.8, 39.9, 101.2, 40.4],
)
readings.prev_t = [missing; readings.t[1:end-1]]

checks = @checkset "Sensor QA" begin
    @check "Temperature in range" (x -> -40 <= x <= 60)(:temp_c)
    @check "Humidity in range"    (h -> 0 <= h <= 100)(:humidity)
    @check "Timestamps increase"  ((t, p) -> ismissing(p) || t > p)(:t, :prev_t)
end

summary = run_checkset(readings, checks)
```

```@example sensors
pass_rate(summary)
```

## Without DataFrames

CheckMate works with any Tables.jl source. A `NamedTuple` of vectors is the
simplest column table and needs no extra packages:

```@example nt
using CheckMate

data = (
    sku   = ["A-1", "A-2", "B-1", "B-2"],
    stock = [12, 0, -4, 7],
)

checks = @checkset "Inventory" begin
    @check "Non-negative stock" (s -> s >= 0)(:stock)
end

run_checkset(data, checks)
```

Row tables such as a vector of `NamedTuple`s work too:

```@example nt
rows = [(sku = "A-1", stock = 12), (sku = "B-1", stock = -4)]
run_checkset(rows, checks)
```

The same applies to `CSV.File`, `Arrow.Table`, database query results and other
Tables.jl-compatible types, without converting them first.

## In a test suite

Because results are plain values, a checkset can serve as a data contract in
your tests:

```julia
using Test, CheckMate

const ORDER_CONTRACT = @checkset "Order contract" begin
    @check "Positive quantity" (q -> q > 0)(:quantity)
    @check "Known status"      (s -> s in ("open", "shipped", "closed"))(:status)
end

@testset "Order data" begin
    summary = run_checkset(load_orders(), ORDER_CONTRACT)
    @test all_passed(summary)
end
```

For a failure message that shows exactly which rows broke the contract, call
[`assert_valid`](@ref) instead. A failing check then throws a
[`ValidationError`](@ref) containing the full report:

```julia
@testset "Order data" begin
    @test assert_valid(load_orders(), ORDER_CONTRACT) isa CheckSummary
end
```
