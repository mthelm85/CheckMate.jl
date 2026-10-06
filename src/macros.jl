"""
    @checkset(name::String, block::Expr)::CheckSet

Create a named set of data validation checks.

# Arguments
- `name`: A descriptive name for the set of checks
- `block`: A block of check definitions using @check syntax

Each check has the form `@check "name" f(:col1, :col2, ...)`, where `f` is any
expression that evaluates to a function returning `Bool`. Append
`severity=:warning` to make a check that is reported but does not count as a
failure.

# Examples
```julia
# Using named functions
function check_amount_positive(amount)
    amount > 0
end

checks = @checkset "Payment Validation" begin
    @check "Amount is positive" check_amount_positive(:amount)
    @check "Valid currency" check_valid_currency(:currency)
end

# Using anonymous functions (lambdas)
checks = @checkset "Lambda Validation" begin
    @check "positive" (x -> x > 0)(:amount)
    @check "valid currency" (c -> c in ("USD", "EUR", "GBP"))(:currency)
end

# Warning-level checks
checks = @checkset "With Warnings" begin
    @check "positive" (x -> x > 0)(:amount)
    @check "round amount" (x -> x % 100 == 0)(:amount) severity=:warning
end
```
"""
macro checkset(name, expr)
    checks = gensym(:checks)
    check_exprs = Expr[]
    seen_names = Set{String}()

    for arg in expr.args
        if @capture(arg, @check(check_name_, call_, opts__))
            check_name isa String || error("Check name must be a string, got: $check_name")
            # Results are keyed by name, so a duplicate would silently replace the earlier check
            check_name in seen_names && error("Duplicate check name \"$check_name\" in checkset \"$name\"")
            push!(seen_names, check_name)

            call isa Expr && call.head == :call ||
                error("Check \"$check_name\" must be a function applied to columns, e.g. f(:col), got: $call")

            # Any expression that evaluates to a callable is accepted: a name, a lambda,
            # a qualified name (Base.isempty), or an expression like (!ismissing) or ==(1).
            func_expr = call.args[1]

            # Extract columns only from the call arguments (args[2:end]), not the
            # function/lambda expression, to avoid false positives from lambda bodies.
            cols = Symbol[]
            for carg in call.args[2:end]
                if carg isa QuoteNode && carg.value isa Symbol
                    push!(cols, carg.value)
                end
            end
            unique!(cols)

            # Catches e.g. `!ismissing(:col)`, which parses as `!` applied to `ismissing(:col)`
            isempty(cols) && error("Check \"$check_name\" has no column arguments in `$call`. " *
                "Apply the condition directly to columns, e.g. (x -> !ismissing(x))(:col).")

            severity = QuoteNode(:error)
            for opt in opts
                @capture(opt, severity = sev_) ||
                    error("Check \"$check_name\": unsupported option `$opt`, expected severity=:error or severity=:warning")
                severity = sev
            end

            push!(check_exprs, quote
                push!($checks, Check(
                    $(esc(check_name)),
                    $(esc(func_expr)),
                    $cols,
                    $(esc(severity))
                ))
            end)
        elseif arg isa Expr && arg.head != :line
            error("Expected @check macro, got: $arg")
        end
    end

    return quote
        let $checks = Check[]
            $(check_exprs...)
            CheckSet($(esc(name)), $checks)
        end
    end
end