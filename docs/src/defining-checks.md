```@meta
CurrentModule = CheckMate
```

# Defining Checks

Checks are defined inside a [`@checkset`](@ref) block. A checkset has a name and
contains one or more `@check` lines:

```julia
checks = @checkset "Checkset Name" begin
    @check "Check name" condition(:column)
    @check "Another check" condition(:column_a, :column_b)
end
```

The general form of a check is:

```julia
@check "<check name>" f(:col1, :col2, ...)
```

- The **name** must be a string literal, and must be unique within the
  checkset. It identifies the check in reports and in functions such as
  [`pass_rate`](@ref) and [`failing_rows`](@ref).
- The **condition** `f` is a named function or an anonymous function (lambda).
  It is called once per row with the values of the listed columns, in the order
  they are listed.
- The **columns** are written as symbols (`:amount`). Each symbol argument
  names a column whose values are passed to `f`.

`f` must return a `Bool`: `true` means the row passes, `false` means it fails.

## Named functions

Named functions keep checksets short and let you reuse and unit-test your
rules:

```@example define
using CheckMate

is_positive(x) = x > 0
is_valid_email(s) = occursin(r"^[^@\s]+@[^@\s]+\.[a-z]{2,}$"i, s)

checks = @checkset "Customer Validation" begin
    @check "Positive balance" is_positive(:balance)
    @check "Valid email"      is_valid_email(:email)
end
```

## Anonymous functions

For one-off rules, write the condition inline as a lambda. Wrap the lambda in
parentheses and apply it to the columns:

```@example define
checks = @checkset "Inline Validation" begin
    @check "Positive amount" (x -> x > 0)(:amount)
    @check "Known currency"  (c -> c in ("USD", "EUR", "GBP"))(:currency)
end
```

## Multi-column checks

A check can read several columns from the same row. The values are passed to
the condition in the order the columns are listed, which makes it easy to
express relationships between fields:

```@example define
using DataFrames

orders = DataFrame(
    order_date = [10, 12, 15, 20],
    ship_date  = [11, 11, 15, 25],
    quantity   = [2, 1, 3, 4],
    unit_price = [5.0, 9.5, 2.0, 3.0],
    total      = [10.0, 9.5, 6.0, 11.0],
)

checks = @checkset "Order Consistency" begin
    @check "Ships on or after order" ((o, s) -> s >= o)(:order_date, :ship_date)
    @check "Total matches line items" ((q, p, t) -> q * p ≈ t)(
        :quantity, :unit_price, :total)
end

run_checkset(orders, checks)
```

## Other callable conditions

The condition can be any expression that evaluates to a function, not only a
name or a lambda. Wrap it in parentheses when it is more than a plain name:

```julia
@check "Not missing"  (!ismissing)(:amount)   # negated function
@check "Non-empty"    (!Base.isempty)(:name)  # qualified name
@check "Is USD"       (==("USD"))(:currency)  # curried comparison
```

## Operators and negation

The condition must be a function that is *applied* to the columns. Operators
written in front of the call are not supported:

```julia
@check "Not missing" !ismissing(:amount)            # ✗ error: no column arguments
@check "Not missing" (!ismissing)(:amount)          # ✓ negated function
@check "Not missing" (x -> !ismissing(x))(:amount)  # ✓ lambda
```

`!ismissing(:amount)` parses as `!` applied to `ismissing(:amount)`, so the
check has no column arguments of its own. `@checkset` reports this when the
checkset is defined.

Operators work normally *inside* a named function or a lambda.

## Missing values and exceptions

If a condition throws an error for a row, that row is recorded as a failure
and the run continues. The report says how many failures came from
exceptions.

This matters most for `missing` values. `missing > 0` returns `missing`, not a
`Bool`, so a condition like `x -> x > 0` throws on a missing value:

```@example define
data = (amount = [10, missing, -3],)

checks = @checkset "Missing Handling" begin
    @check "Positive (strict)"  (x -> x > 0)(:amount)
    @check "Positive or absent" (x -> ismissing(x) || x > 0)(:amount)
end

run_checkset(data, checks)
```

!!! tip "Make missing-value policy explicit"
    Decide whether `missing` is allowed for each column and say so in the
    condition, for example `ismissing(x) || x > 0`. Use a separate
    `(!ismissing)(:col)` check when missing values should be reported on their
    own.

When a condition throws, the report shows the first exception and the row it
happened on, so a bug in a condition, such as a typo in a variable name, is easy
to spot. The same information is stored in the `exception_count` and
`first_exception` fields of the [`CheckResult`](@ref).

## Warning-level checks

Not every rule should fail validation. Append `severity=:warning` to a check to
report its failures without counting them as failures:

```@example define
data = (amount = [100, 250, -5, 1_000_000],)

checks = @checkset "Payments" begin
    @check "Positive"         (x -> x > 0)(:amount)
    @check "Unusually large"  (x -> x < 100_000)(:amount) severity=:warning
end

summary = run_checkset(data, checks)
```

```@example define
all_passed(summary), failed_checks(summary), warning_checks(summary)
```

Warnings are marked with ⚠ in the report. They are ignored by
[`failed_checks`](@ref), [`all_passed`](@ref), [`assert_valid`](@ref) and the
summary-wide row and pass-rate functions; see [Warnings](@ref) for details.
The severity can also come from a variable, for example `severity=level`, and
must be `:error` (the default) or `:warning`.

## Missing columns

If a column named in a check does not exist in the data, the check fails with
the message `Required columns not found`. No rows are evaluated for that check.
The other checks in the checkset still run.

```@example define
run_checkset((amount = [1, 2, 3],), @checkset "Schema" begin
    @check "Has a currency" (c -> true)(:currency)
end)
```

## Inspecting a checkset

[`check_names`](@ref) and [`check_columns`](@ref) let you inspect a checkset
programmatically:

```@example define
checks = @checkset "Order Consistency" begin
    @check "Ships on or after order" ((o, s) -> s >= o)(:order_date, :ship_date)
    @check "Positive quantity" (q -> q > 0)(:quantity)
end

check_names(checks)
```

```@example define
check_columns(checks, "Ships on or after order")
```
