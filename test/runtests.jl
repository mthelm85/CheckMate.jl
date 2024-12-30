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

@testset "CheckMate.jl" begin
    @testset "Single Column Validation" begin
        data = TestTable([1, -2, 3, -4, 5], [1, 2, 3, 4, 5])
        
        checks = @checkset "numeric validation" begin
            @check "positive numbers" is_positive(:a)
        end
        
        results = run_checkset(data, checks)
        
        @test !results.check_results["positive numbers"].passed
        @test length(failing_rows(results)) == 2
        @test results.check_results["positive numbers"].failing_rows == [2, 4]
        @test results.check_results["positive numbers"].total_rows == 5
        
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
        @test results.check_results["a greater than b"].total_rows == 5
        
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
        @test results.check_results["always errors"].total_rows == 3
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
        @test pass_rate(results) == 60.0  # No checks passed
        
        # Test specific failures
        positive_fails = results.check_results["positive values"].failing_rows
        less_than_ten_fails = results.check_results["less than ten"].failing_rows
        
        @test length(positive_fails) == 1  # Only -3 fails positive check
        @test length(less_than_ten_fails) == 1  # Only 15 fails < 10 check
        @test 3 ∈ positive_fails  # -3 at index 3
        @test 2 ∈ less_than_ten_fails  # 15 at index 2
        @test results.check_results["positive values"].total_rows == 5
        @test results.check_results["less than ten"].total_rows == 5
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
            @test r1.check_results[check_name].total_rows == 
                  r2.check_results[check_name].total_rows
        end
    end

    @testset "Basic Macro Tests" begin
        # Test empty checkset
        empty_checks = @checkset "empty" begin end
        @test length(empty_checks.checks) == 0
        @test empty_checks.name == "empty"

        # Test working check macro
        working_checks = @checkset "working" begin
            @check "test" is_positive(:a)
        end
        @test length(working_checks.checks) == 1
        @test working_checks.checks[1].name == "test"
        @test working_checks.checks[1].columns == [:a]

        # Test multiple columns
        multi_col_checks = @checkset "multi" begin
            @check "test" first_greater_than_second(:a, :b)
        end
        @test length(multi_col_checks.checks[1].columns) == 2
    end

    @testset "Pass Rate Tests" begin
        data = TestTable([1, -2, 3], [4, 5, 6])
        
        checks = @checkset "pass rate tests" begin
            @check "positive" is_positive(:a)
            @check "less than 10" is_less_than_ten(:a)
        end
        
        results = run_checkset(data, checks)

        # Test pass rate for specific check
        @test pass_rate(results, "positive") ≈ 66.7 atol=0.1  # 2 out of 3 pass
        @test pass_rate(results, "less than 10") == 100.0  # All pass
        
        # Test error handling
        @test_throws ErrorException pass_rate(results, "nonexistent")
        
        # Test with all failing data
        fail_data = TestTable([-1, -2, -3], [4, 5, 6])
        fail_results = run_checkset(fail_data, checks)
        @test pass_rate(fail_results, "positive") == 0.0
        
        # Test with all passing data
        pass_data = TestTable([1, 2, 3], [4, 5, 6])
        pass_results = run_checkset(pass_data, checks)
        @test pass_rate(pass_results, "positive") == 100.0
        
        # Test pass rate with error-throwing check
        error_checks = @checkset "error tests" begin
            @check "always errors" always_errors(:a)
        end
        error_results = run_checkset(data, error_checks)
        @test pass_rate(error_results, "always errors") == 0.0
    end

    @testset "Reporting Functionality" begin
        data = TestTable([1, -2, 3], [4, 5, 6])
        checks = @checkset "report test" begin
            @check "always pass" is_positive(:a)
            @check "multi col" first_greater_than_second(:a, :b)
        end
        
        results = run_checkset(data, checks)

        # Test string output
        output = sprint(show, results)
        @test occursin("Check Summary: report test", output)
        @test occursin(":", output)  # Should contain column names
        @test occursin("checks completed in", lowercase(output))

        # Test MIME output
        mime_output = sprint(show, MIME("text/plain"), results)
        @test occursin("Check Summary", mime_output)

        # Test CheckSet display
        set_output = sprint(show, checks)
        @test occursin("CheckSet:", set_output)
        @test occursin("Number of checks: 2", set_output)
        
        # Test MIME output for CheckSet
        set_mime_output = sprint(show, MIME("text/plain"), checks)
        @test occursin("CheckSet:", set_mime_output)
    end

    @testset "Type Functionality" begin
        # Test CheckResult comparison
        passed = CheckResult(true, Int[], NamedTuple[], "passed", 3)
        failed1 = CheckResult(false, [1], [NamedTuple()], "failed", 3)
        failed2 = CheckResult(false, [1,2], [NamedTuple(), NamedTuple()], "failed more", 3)
        
        @test passed > failed1  # Passed sorts after failed
        @test failed2 < failed1  # More failures sorts before fewer failures
        
        # Test Check construction
        check = Check("test", x -> x > 0, [:column])
        @test check.name == "test"
        @test check.columns == [:column]
        @test check.condition(1) == true
        @test check.condition(-1) == false

        # Test CheckSet construction
        checks = CheckSet("test set", [check])
        @test checks.name == "test set"
        @test length(checks.checks) == 1
        @test checks.checks[1].name == "test"
    end
end