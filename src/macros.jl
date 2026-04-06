"""
    @checkset(name::String, block::Expr)::CheckSet

Create a named set of data validation checks.

# Arguments
- `name`: A descriptive name for the set of checks
- `block`: A block of check definitions using @check syntax

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
```
"""
macro checkset(name, expr)
    checks = gensym(:checks)
    check_exprs = Expr[]

    for arg in expr.args
        if @capture(arg, @check(check_name_, call_))
            check_name isa String || error("Check name must be a string, got: $check_name")

            func_expr = call.args[1]
            func_expr isa Symbol || (func_expr isa Expr && func_expr.head == :->) ||
                error("Check condition must be a named function or lambda (x -> ...), got: $func_expr")

            # Extract columns only from the call arguments (args[2:end]), not the
            # function/lambda expression, to avoid false positives from lambda bodies.
            cols = Symbol[]
            for carg in call.args[2:end]
                if carg isa QuoteNode && carg.value isa Symbol
                    push!(cols, carg.value)
                end
            end
            unique!(cols)

            push!(check_exprs, quote
                push!($checks, Check(
                    $(esc(check_name)),
                    $(esc(func_expr)),
                    $cols
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