using MacroTools

function extract_columns(expr)::Vector{Symbol}
    cols = Symbol[]
    MacroTools.postwalk(expr) do ex
        if ex isa QuoteNode && ex.value isa Symbol
            push!(cols, ex.value)
        end
        ex
    end
    unique!(cols)
end

"""
    @checkset(name::String, block::Expr)::CheckSet

Create a named set of data validation checks.

# Arguments
- `name`: A descriptive name for the set of checks
- `block`: A block of check definitions using @check syntax

# Examples
```julia
# Define your check functions
function check_amount_positive(amount)
    amount > 0
end

function check_valid_currency(currency)
    currency in ("USD", "EUR", "GBP")
end

# Create a checkset
checks = @checkset "Payment Validation" begin
    @check "Amount is positive" check_amount_positive(:amount)
    @check "Valid currency" check_valid_currency(:currency)
end
```

Note: Check conditions must be defined as named functions. Lambda expressions
(e.g., `x -> x > 0`) are not supported.
"""
macro checkset(name, expr)
    checks = gensym(:checks)
    check_exprs = Expr[]

    for arg in expr.args
        if @capture(arg, @check(check_name_, call_))
            # Validate
            check_name isa String || error("Check name must be a string, got: $check_name")

            func_name = call.args[1]
            cols = extract_columns(call)

            push!(check_exprs, quote
                push!($checks, Check(
                    $(esc(check_name)),
                    $(esc(func_name)),
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