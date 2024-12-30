using CheckMate
using Tables
using Test

struct TestTable
    a::Vector{Int}
    b::Vector{Int}
end

Tables.istable(::TestTable) = true
Tables.columnaccess(::TestTable) = true
Tables.columns(x::TestTable) = x
Tables.getcolumn(x::TestTable, ::Type, col::Int) = getfield(x, col)
Tables.getcolumn(x::TestTable, col::Symbol) = getfield(x, col)
Tables.columnnames(x::TestTable) = (:a, :b)

# Define check functions
is_positive(x) = x > 0
is_less_than_ten(x) = x < 10
first_greater_than_second(x, y) = !ismissing(x) && !ismissing(y) && x > y
always_errors(x) = error("test error")
always_passes(x) = true

@testset "Argus.jl" begin
    @testset "Single Column Validation" begin
        data = TestTable([1, -2, 3, -4, 5], [1, 2, 3, 4, 5])
        
        checks = @checkset "numeric validation" begin
            @check "positive numbers" is_positive(:a)
        end
        
        results = run_checkset(data, checks)
        
        @test !results.check_results["positive numbers"].passed
        @test length(failing_rows(results)) == 2
        @test results.check_results["positive numbers"].failing_rows == [2, 4]
        
        failing_vals = results.check_results["positive numbers"].failing_values
        @test length(failing_vals) == 2
        @test failing_vals[1].a == -2
        @test failing_vals[2].a == -4
    end

    @testset "Multiple Column Validation" begin
        data = TestTable([2, 3, 1, 5, 6], [1, 4, 2, 3, 3])
        
        checks = @checkset "comparison validation" begin
            @check "a greater than b" first_greater_than_second(:a, :b)
        end
        
        results = run_checkset(data, checks)
        
        @test !results.check_results["a greater than b"].passed
        failed_rows = failing_rows(results)
        @test length(failed_rows) == 2
        @test 2 ∈ failed_rows  # 3 is not > 4
        
        failing_vals = results.check_results["a greater than b"].failing_values
        @test failing_vals[1].a == 3
        @test failing_vals[1].b == 4
    end

    @testset "Error Handling" begin
        data = TestTable([1, 2, 3], [4, 5, 6])
        
        checks = @checkset "error handling" begin
            @check "always errors" always_errors(:a)
            @check "always passes" always_passes(:b)
        end
        
        results = run_checkset(data, checks)
        
        # First check should fail but not prevent second check from running
        @test !results.check_results["always errors"].passed
        @test results.check_results["always passes"].passed
        
        # All rows should fail for the erroring check
        @test length(results.check_results["always errors"].failing_rows) == 3
    end

    @testset "Multiple Checks" begin
        data = TestTable([1, 15, -3, 8, 5], [1, 2, 3, 4, 5])
        
        checks = @checkset "multiple checks" begin
            @check "positive values" is_positive(:a)
            @check "less than ten" is_less_than_ten(:a)
        end
        
        results = run_checkset(data, checks)
        
        # Check individual results
        @test !results.check_results["positive values"].passed
        @test !results.check_results["less than ten"].passed
        
        # Test summary statistics
        @test length(failed_checks(results)) == 2
        @test length(passed_checks(results)) == 0
        @test pass_rate(results) == 0.0
        
        # Test specific failures
        positive_fails = results.check_results["positive values"].failing_rows
        less_than_ten_fails = results.check_results["less than ten"].failing_rows
        
        @test length(positive_fails) == 1  # Only -3 fails positive check
        @test length(less_than_ten_fails) == 1  # Only 15 fails < 10 check
        @test 3 ∈ positive_fails  # -3 at index 3
        @test 2 ∈ less_than_ten_fails  # 15 at index 2
    end

    @testset "Threading" begin
        n = 1000
        data = TestTable(rand(-10:10, n), rand(-10:10, n))
        
        checks = @checkset "multiple checks" begin
            @check "positive values" is_positive(:a)
            @check "less than ten" is_less_than_ten(:a)
        end
        
        # Results should be identical regardless of threading
        r1 = run_checkset(data, checks, threaded=false)
        r2 = run_checkset(data, checks, threaded=true)
        
        for check_name in keys(r1.check_results)
            @test r1.check_results[check_name].failing_rows == 
                  r2.check_results[check_name].failing_rows
        end
    end
end