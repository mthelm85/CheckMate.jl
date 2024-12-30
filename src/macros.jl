using MacroTools

function extract_columns(expr)::Vector{Symbol}
    cols = Symbol[]
    
    function traverse(ex)
        if @capture(ex, f_(args__))
            for arg in args
                if arg isa QuoteNode && arg.value isa Symbol
                    push!(cols, arg.value)
                end
            end
        elseif ex isa Expr
            foreach(traverse, ex.args)
        end
    end
    
    traverse(expr)
    unique!(cols)
    return cols
end

function validate_check_args(name, func)
    name isa String || throw(ArgumentError("Check name must be a string"))
    func isa Expr && func.head == :call || throw(ArgumentError("Check must be a function call"))
    nothing
end

function transform_check(ex, checks)::Union{Expr,Nothing}
    if !@capture(ex, @check_(name_, call_))
        return nothing
    end
    
    try
        validate_check_args(name, call)
        
        func_name = call.args[1]
        cols = extract_columns(call)
        
        return quote
            push!($checks, Check(
                $(esc(name)),
                let check_func = $(esc(func_name))
                    (args...) -> check_func(args...)
                end,
                $cols
            ))
        end
    catch e
        throw(ArgumentError("Invalid @check syntax: $(sprint(showerror, e))"))
    end
end

function transform_checkset_expr(expr, checks)::Vector{Expr}
    filter(x -> x !== nothing, map(x -> transform_check(x, checks), expr.args))
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
    return quote
        let $checks = Check[]
            $(map(filter(x -> x isa Expr, expr.args)) do arg
                transform_check(arg, checks)
            end...)
            CheckSet($(esc(name)), $checks)
        end
    end
end