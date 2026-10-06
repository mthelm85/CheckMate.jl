using CheckMate
using Aqua
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
    @testset "Code Quality (Aqua)" begin
        Aqua.test_all(CheckMate)
    end

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

        # Message should surface that failures were caused by exceptions
        @test occursin("exception", lowercase(results.check_results["always errors"].message))
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

    @testset "Thread Safety Stress Test" begin
        # Create a larger dataset to increase contention
        n = 1000
        data = TestTable(rand(-10:10, n), rand(-10:10, n))
        
        # Create many checks to maximize thread contention
        checks = @checkset "stress test" begin
            @check "positive a" is_positive(:a)
            @check "positive b" is_positive(:b)
            @check "less than ten a" is_less_than_ten(:a)
            @check "less than ten b" is_less_than_ten(:b)
            @check "a greater than b" first_greater_than_second(:a, :b)
            @check "always passes a" always_passes(:a)
            @check "always passes b" always_passes(:b)
            @check "positive a 2" is_positive(:a)
            @check "positive b 2" is_positive(:b)
            @check "less than ten a 2" is_less_than_ten(:a)
        end
        
        # Run many iterations - race conditions are probabilistic
        for iteration in 1:100
            results = run_checkset(data, checks, threaded=true)
            
            # Basic sanity checks
            @test length(results.check_results) == 10
            @test all(haskey(results.check_results, name) for name in check_names(checks))
            
            # Verify results are consistent
            for (name, result) in results.check_results
                @test result.total_rows == n
                @test length(result.failing_rows) == length(result.failing_values)
            end
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

        # Full report via text/plain and print_summary
        output = sprint(show, MIME("text/plain"), results)
        @test occursin("Check Summary: report test", output)
        @test occursin(":", output)  # Should contain column names
        @test occursin("checks completed in", lowercase(output))
        @test sprint(print_summary, results) == output

        # Compact two-argument show
        @test sprint(show, results) == "CheckSummary(\"report test\": 0/2 checks passed)"
        @test sprint(show, checks) == "CheckSet(\"report test\", 2 checks)"
        @test occursin("CheckSet(\"report test\"", sprint(show, [checks]))

        # Full CheckSet display
        set_mime_output = sprint(show, MIME("text/plain"), checks)
        @test occursin("CheckSet:", set_mime_output)
        @test occursin("Number of checks: 2", set_mime_output)
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

    @testset "Check Columns" begin
        data = TestTable([1, 2, 3], [4, 5, 6])
        
        checks = @checkset "column check" begin
            @check "positive values" is_positive(:a)
            @check "a greater than b" first_greater_than_second(:a, :b)
        end
        
        @test check_columns(checks, "positive values") == [:a]
        @test check_columns(checks, "a greater than b") == [:a, :b]
    end

    @testset "Check Names" begin
        checks = @checkset "name check" begin
            @check "positive values" is_positive(:a)
            @check "a greater than b" first_greater_than_second(:a, :b)
        end

        @test check_names(checks) == ["positive values", "a greater than b"]
    end

    @testset "Empty CheckSet Edge Cases" begin
        data = TestTable([1, 2, 3], [4, 5, 6])
        empty_checks = @checkset "empty" begin end
        results = run_checkset(data, empty_checks)

        @test pass_rate(results) == 100.0
        @test failing_rows(results) == Int[]
        @test total_failures(results) == 0
        @test_nowarn sprint(show, results)
    end

    @testset "Lambda Function Support" begin
        data = TestTable([1, -2, 3, -4, 5], [1, 2, 3, 4, 5])

        lambda_checks = @checkset "lambda validation" begin
            @check "positive lambda" (x -> x > 0)(:a)
        end

        results = run_checkset(data, lambda_checks)

        @test !results.check_results["positive lambda"].passed
        @test results.check_results["positive lambda"].failing_rows == [2, 4]
        @test results.check_results["positive lambda"].total_rows == 5
        @test check_columns(lambda_checks, "positive lambda") == [:a]

        # Multi-column lambda
        multi_lambda_checks = @checkset "multi lambda" begin
            @check "a gt b lambda" ((x, y) -> x > y)(:a, :b)
        end
        @test check_columns(multi_lambda_checks, "a gt b lambda") == [:a, :b]

        multi_results = run_checkset(data, multi_lambda_checks)
        @test !multi_results.check_results["a gt b lambda"].passed
    end

    @testset "Callable Expression Conditions" begin
        data = (x = [1, missing, 3], s = ["a", "", "c"])

        checks = @checkset "callable expressions" begin
            @check "negated function" (!ismissing)(:x)
            @check "qualified name" Base.isempty(:s)
            @check "curried function" (==(1))(:x)
        end
        results = run_checkset(data, checks)

        @test failing_rows(results, "negated function") == [2]
        @test failing_rows(results, "qualified name") == [1, 3]
        @test failing_rows(results, "curried function") == [2, 3]
        @test check_columns(checks, "negated function") == [:x]
    end

    @testset "Invalid Check Definitions" begin
        expansion_error(ex) =
            try
                macroexpand(@__MODULE__, ex)
                nothing
            catch e
                sprint(showerror, e isa LoadError ? e.error : e)
            end

        # `!ismissing(:x)` parses as `!` applied to `ismissing(:x)`, leaving no column arguments
        msg = expansion_error(:(@checkset "bad" begin
            @check "negated call" !ismissing(:x)
        end))
        @test msg !== nothing && occursin("no column arguments", msg)

        msg = expansion_error(:(@checkset "bad" begin
            @check "not a call" true
        end))
        @test msg !== nothing && occursin("must be a function applied to columns", msg)

        msg = expansion_error(:(@checkset "bad" begin
            @check "same" (x -> x > 0)(:a)
            @check "same" (x -> x > 1)(:a)
        end))
        @test msg !== nothing && occursin("Duplicate check name", msg)
    end

    @testset "Row-Oriented Tables" begin
        rows = [(a = 1, b = 2), (a = -1, b = 3), (a = 4, b = 1)]
        checks = @checkset "rows" begin
            @check "positive a" (x -> x > 0)(:a)
            @check "a gt b" ((x, y) -> x > y)(:a, :b)
        end
        results = run_checkset(rows, checks)

        @test failing_rows(results, "positive a") == [2]
        @test failing_rows(results, "a gt b") == [1, 2]
        @test results.check_results["a gt b"].failing_values == [(a = 1, b = 2), (a = -1, b = 3)]
        @test failing_rows(run_checkset(rows, checks; threaded = true)) == [1, 2]
    end

    @testset "Non-Bool Condition Results" begin
        checks = @checkset "non-bool" begin
            @check "missing result" (x -> x > 0)(:a)
        end
        result = run_checkset((a = [1, missing, 3],), checks).check_results["missing result"]

        @test result.failing_rows == [2]
        @test occursin("1 due to exceptions", result.message)
    end

    @testset "Error Messages" begin
        checks = @checkset "named set" begin
            @check "only" (x -> true)(:a)
        end
        err = try check_columns(checks, "nope"); "" catch e; sprint(showerror, e) end
        @test err == "Check 'nope' in checkset 'named set' not found"
    end

    @testset "Missing Columns and Pass Rate" begin
        data = TestTable([1, 2, 3], [1, 2, 3])
        checks = @checkset "missing col" begin
            @check "ok" is_positive(:a)
            @check "gone" is_positive(:zzz)
        end
        results = run_checkset(data, checks)

        @test results.check_results["gone"].missing_columns == [:zzz]
        @test results.check_results["ok"].missing_columns == Symbol[]
        @test failed_checks(results) == ["gone"]
        @test pass_rate(results) == 0.0           # no row can pass a check that couldn't run
        @test pass_rate(results, "gone") == 0.0

        # Empty tables pass rather than fail
        empty = run_checkset((a = Int[],), @checkset "empty" begin
            @check "positive" is_positive(:a)
        end)
        @test pass_rate(empty) == 100.0
        @test pass_rate(empty, "positive") == 100.0
    end

    @testset "Exception Details" begin
        checks = @checkset "exceptions" begin
            @check "errors" always_errors(:a)
            @check "fine" is_positive(:a)
        end
        results = run_checkset(TestTable([1, 2], [1, 2]), checks)
        result = results.check_results["errors"]

        @test result.exception_count == 2
        @test result.first_exception isa Pair
        @test first(result.first_exception) == 1
        @test last(result.first_exception) isa ErrorException
        @test results.check_results["fine"].first_exception === nothing
        @test occursin("First exception (row 1): test error", sprint(print_summary, results))
    end

    @testset "Definition Order" begin
        names = ["check $i" for i in 1:20]
        checks = CheckSet("ordered", [Check(n, iseven, [:a]) for n in names])
        results = run_checkset((a = [1, 2],), checks)

        @test results.check_order == names
        @test failed_checks(results) == names
        @test passed_checks(run_checkset((a = [2, 4],), checks)) == names

        # Ties in the report keep definition order
        report = sprint(print_summary, results)
        positions = [findfirst("✗ $n:", report) for n in names]
        @test issorted(first.(positions))

        # Summaries built with the old 3-argument constructor still work
        legacy = CheckSummary("legacy", results.check_results, 0.0)
        @test sort(failed_checks(legacy)) == sort(names)
    end

    @testset "Execution Time" begin
        results = run_checkset((a = [1],), @checkset "t" begin
            @check "p" is_positive(:a)
        end)
        @test execution_time(results) > 0.0     # not rounded away
        @test CheckMate.format_duration(0.0123) == "12.3 ms"
        @test CheckMate.format_duration(2.5) == "2.50 seconds"
    end

    @testset "Pass/Fail Helpers" begin
        checks = @checkset "helpers" begin
            @check "positive" is_positive(:a)
        end
        good = run_checkset((a = [1, 2],), checks)
        bad = run_checkset((a = [1, -2],), checks)

        @test all_passed(good)
        @test !all_passed(bad)
        @test assert_valid(good) === good
        @test assert_valid((a = [1, 2],), checks) isa CheckSummary
        @test_throws ValidationError assert_valid(bad)
        @test_throws ValidationError assert_valid((a = [-1],), checks; threaded = true)

        err = try assert_valid(bad); nothing catch e; e end
        @test err.summary === bad
        msg = sprint(showerror, err)
        @test startswith(msg, "ValidationError: 1 of 1 checks failed in checkset \"helpers\": positive")
        @test occursin("Row 2: a=-2", msg)
    end

    @testset "Summary as a Table" begin
        checks = @checkset "table" begin
            @check "positive" is_positive(:a)
            @check "small" is_less_than_ten(:a) severity=:warning
        end
        results = run_checkset((a = [1, -2, 30, 4],), checks)

        @test Tables.istable(results)
        cols = Tables.columntable(results)
        @test cols.check == ["positive", "small"]
        @test cols.severity == [:error, :warning]
        @test cols.passed == [false, false]
        @test cols.failures == [1, 1]
        @test cols.exceptions == [0, 0]
        @test cols.pass_rate == [75.0, 75.0]
        @test length(Tables.rowtable(results)) == 2
    end

    @testset "Row Failures" begin
        checks = @checkset "rows" begin
            @check "positive" is_positive(:a)
            @check "small" is_less_than_ten(:a)
            @check "b positive" is_positive(:b) severity=:warning
        end
        results = run_checkset(TestTable([1, -2, 30, -40], [1, 1, 1, -1]), checks)
        rf = row_failures(results)

        @test Tables.istable(rf)
        @test rf.row == [2, 3, 4]
        @test rf.checks == [["positive"], ["small"], ["positive", "b positive"]]
        @test row_failures(run_checkset(TestTable([1], [1]), checks)) == (row = Int[], checks = Vector{String}[])
    end

    @testset "Warning Severity" begin
        checks = @checkset "severity" begin
            @check "positive" is_positive(:a)
            @check "small" is_less_than_ten(:a) severity=:warning
            @check "explicit error" is_positive(:b) severity=:error
        end
        @test [c.severity for c in checks.checks] == [:error, :warning, :error]
        @test occursin("[warning]", sprint(show, MIME("text/plain"), checks))

        # Only the warning check fails
        results = run_checkset(TestTable([1, 20, 3], [1, 1, 1]), checks)
        @test !results.check_results["small"].passed
        @test failed_checks(results) == String[]
        @test warning_checks(results) == ["small"]
        @test passed_checks(results) == ["positive", "explicit error"]
        @test all_passed(results)
        @test assert_valid(results) === results
        @test failing_rows(results) == Int[]
        @test failing_rows(results, "small") == [2]
        @test total_failures(results) == 0
        @test pass_rate(results) == 100.0
        @test pass_rate(results, "small") ≈ 66.67

        report = sprint(print_summary, results)
        @test occursin("⚠ small: 1 rows failed", report)
        @test occursin("2/3 checks passed (66.7%), 1 with warnings", report)

        # A warning check with a missing column doesn't zero the overall pass rate
        missing_warning = run_checkset(TestTable([1], [1]), @checkset "mw" begin
            @check "ok" is_positive(:a)
            @check "gone" is_positive(:zzz) severity=:warning
        end)
        @test pass_rate(missing_warning) == 100.0
        @test warning_checks(missing_warning) == ["gone"]

        # Severity can come from a variable, and is validated
        level = :warning
        dynamic = @checkset "dynamic" begin
            @check "w" is_positive(:a) severity=level
        end
        @test dynamic.checks[1].severity === :warning
        @test_throws ErrorException Check("bad", is_positive, [:a], :fatal)

        # Old 3-argument Check and 5-argument CheckResult constructors default to :error
        @test Check("legacy", is_positive, [:a]).severity === :error
        @test CheckResult(true, Int[], NamedTuple[], "ok", 1).severity === :error

        bad_option(ex) =
            try
                macroexpand(@__MODULE__, ex)
                nothing
            catch e
                sprint(showerror, e isa LoadError ? e.error : e)
            end
        msg = bad_option(:(@checkset "bad" begin
            @check "x" is_positive(:a) level=:warning
        end))
        @test msg !== nothing && occursin("unsupported option", msg)
    end
end