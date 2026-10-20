extends TestCase
## The test runner (tests/run_tests.gd) and its error attribution: TestErrorLogger collects what the
## engine logs, TestCase.review_errors / expect_error decide which test fails because of it. The end
## to end part runs the real runner in a child process on generated fixture tests (a test file
## that does not compile among them).

const SPY_STACK_MARKER := "test_the_logger_collects_errors_with_a_stack"

## A fixture with a script error inside a helper: it aborts the helper, the test method goes on.
const HELPER := """
func _null_access() -> void:
	var o: Variant = null
	o.no_such_method()
"""

const FIXTURE_CLEAN := """extends TestCase
func test_clean_passes() -> void:
	check(true)
func test_failing_check_fails() -> void:
	check(false, "FIXTURE_PLAIN_CHECK")
"""

const FIXTURE_ERRORS := """extends TestCase
func test_script_error_fails() -> void:
	_null_access()
	check(true)
func test_script_error_that_ends_the_method_fails() -> void:
	var o: Variant = null
	o.no_such_method()
	check(true)
func test_push_error_fails() -> void:
	push_error("FIXTURE_PUSH")
func test_expected_error_passes() -> void:
	expect_error("FIXTURE_EXPECTED")
	push_error("FIXTURE_EXPECTED")
func test_expected_error_that_does_not_happen_fails() -> void:
	expect_error("FIXTURE_MISSING")
func test_error_beyond_the_expected_count_fails() -> void:
	expect_error("FIXTURE_TWICE")
	push_error("FIXTURE_TWICE")
	push_error("FIXTURE_TWICE")
func test_error_not_covered_by_the_expectation_fails() -> void:
	expect_error("FIXTURE_COVERED")
	push_error("FIXTURE_COVERED")
	push_error("FIXTURE_UNCOVERED")
func test_warning_passes() -> void:
	push_warning("FIXTURE_WARNING")
""" + HELPER

const FIXTURE_ASYNC := """extends TestCase
var _async := false
func is_async() -> bool:
	return _async
func test_async_passes() -> void:
	_async = true
	await tree.process_frame
	finished.emit()
func test_async_error_before_finishing_fails() -> void:
	_async = true
	await tree.process_frame
	push_error("FIXTURE_ASYNC_PUSH")
	finished.emit()
func test_async_script_error_after_an_await_fails() -> void:
	_async = true
	await tree.process_frame
	_null_access()
	finished.emit()
func test_async_coroutine_ended_by_an_error_times_out() -> void:
	_async = true
	await tree.process_frame
	var o: Variant = null
	o.no_such_method()
	finished.emit()
""" + HELPER

const FIXTURE_BROKEN := """extends TestCase
func test_never_runs() -> void:
	this is not gdscript
"""

var _dir := ""


func after_each() -> void:
	if _dir != "":
		for file in DirAccess.get_files_at(_dir):
			DirAccess.remove_absolute(_dir.path_join(file))
		DirAccess.remove_absolute(_dir)


# --- review_errors / expect_error -----------------------------------------------------------

func _entry(message: String, where: String = "res://x.gd:1 f", stack: String = "") -> TestErrorLogger.Entry:
	var e := TestErrorLogger.Entry.new()
	e.message = message
	e.where = where
	e.stack = stack
	return e


func _review(case: TestCase, logged: Array[TestErrorLogger.Entry]) -> Array[String]:
	case.review_errors(logged)
	return case.failures


func test_an_error_nobody_expected_fails_the_test_with_its_text() -> void:
	var case := TestCase.new()
	var errors: Array[TestErrorLogger.Entry] = [_entry("Invalid call. Nonexistent function 'x' in base 'Nil'.", "res://core/a.gd:7 f", "f (a.gd:7) < test_y (test_z.gd:3)")]
	var failures := _review(case, errors)
	check_eq(failures.size(), 1, "one failure")
	if failures.size() == 1:
		check("unexpected error" in failures[0], "it says what happened: %s" % failures[0])
		check("Nonexistent function 'x'" in failures[0], "it carries the error text: %s" % failures[0])
		check("res://core/a.gd:7" in failures[0] and "test_z.gd:3" in failures[0], "and where it came from: %s" % failures[0])


func test_no_errors_no_failures() -> void:
	var case := TestCase.new()
	check(_review(case, []).is_empty(), "nothing logged, nothing failed")


func test_an_expected_error_passes() -> void:
	var case := TestCase.new()
	case.expect_error("parse error")
	var errors: Array[TestErrorLogger.Entry] = [_entry("ConfigFile parse error at x.cfg:0: Unexpected EOF")]
	check(_review(case, errors).is_empty(), "the declared substring covers it")


func test_an_expected_error_that_did_not_happen_fails() -> void:
	var case := TestCase.new()
	case.expect_error("parse error")
	var failures := _review(case, [])
	check_eq(failures.size(), 1, "a stale expectation is a failure")
	if failures.size() == 1:
		check("parse error" in failures[0] and "seen 0" in failures[0], "it names the missing error: %s" % failures[0])


func test_an_expectation_covers_exactly_the_declared_count() -> void:
	var case := TestCase.new()
	case.expect_error("boom")
	var errors: Array[TestErrorLogger.Entry] = [_entry("boom"), _entry("boom again")]
	var failures := _review(case, errors)
	check_eq(failures.size(), 1, "the second boom is not covered: %s" % [failures])
	var twice := TestCase.new()
	twice.expect_error("boom", 2)
	check(_review(twice, errors).is_empty(), "times = 2 covers both")


func test_an_expectation_does_not_cover_other_errors() -> void:
	var case := TestCase.new()
	case.expect_error("parse error")
	var errors: Array[TestErrorLogger.Entry] = [_entry("parse error in a"), _entry("Invalid call. Nonexistent function")]
	var failures := _review(case, errors)
	check_eq(failures.size(), 1, "only the declared one is allowed: %s" % [failures])
	if failures.size() == 1:
		check("Nonexistent function" in failures[0], "the other one fails: %s" % failures[0])


func test_an_expectation_matches_the_message_not_the_location_or_the_stack() -> void:
	var case := TestCase.new()
	case.expect_error("test_runner")
	var errors: Array[TestErrorLogger.Entry] = [_entry("boom", "res://tests/test_runner.gd:1 f", "f (test_runner.gd:1)")]
	var failures := _review(case, errors)
	check_eq(failures.size(), 2, "the error is unexpected and the expectation unmet: %s" % [failures])


func test_a_bad_expectation_is_a_failure() -> void:
	var case := TestCase.new()
	case.expect_error("")
	case.expect_error("x", 0)
	check_eq(case.failures.size(), 2, "an empty substring and a count below 1 are refused")


func test_an_error_logged_between_tests_fails_the_next_test() -> void:
	var case := TestCase.new()
	case.expect_error("late")
	var stray: Array[TestErrorLogger.Entry] = [_entry("late error of something else")]
	case.review_errors([], stray)
	check_eq(case.failures.size(), 2, "a stray error cannot be expected (and the expectation is unmet): %s" % [case.failures])
	check("between tests" in case.failures[0], "it says so: %s" % case.failures[0])


# --- TestErrorLogger ----------------------------------------------------------------------

func test_the_logger_collects_errors_with_a_stack() -> void:
	expect_error("RUNNER_SPY_PUSH")
	expect_error("Nonexistent function 'no_such_method'")
	var logger := TestErrorLogger.new()
	OS.add_logger(logger)
	push_error("RUNNER_SPY_PUSH")
	_null_access()
	OS.remove_logger(logger)
	var errors := logger.drain()
	check_eq(errors.size(), 2, "both errors were caught")
	if errors.size() == 2:
		check_eq(errors[0].message, "RUNNER_SPY_PUSH", "push_error text")
		check(SPY_STACK_MARKER in errors[0].stack, "the stack names this test: %s" % errors[0].stack)
		check("Nonexistent function 'no_such_method'" in errors[1].message, "script error text: %s" % errors[1].message)
		check("test_runner.gd" in errors[1].where, "script error location: %s" % errors[1].where)
		check(SPY_STACK_MARKER in errors[1].stack, "the helper's stack reaches the test: %s" % errors[1].stack)
	check(logger.drain().is_empty(), "drain forgets what it returned")


func test_the_logger_ignores_warnings() -> void:
	var logger := TestErrorLogger.new()
	OS.add_logger(logger)
	push_warning("RUNNER_SPY_WARNING")
	OS.remove_logger(logger)
	check(logger.drain().is_empty(), "a warning is not an error")


func _null_access() -> void:
	var o: Variant = null
	o.no_such_method()


# --- The runner, end to end -----------------------------------------------------------------

func _write(file: String, source: String) -> void:
	var f := FileAccess.open(_dir.path_join(file), FileAccess.WRITE)
	f.store_string(source)
	f.close()


func test_the_runner_fails_the_tests_that_log_errors_and_the_files_that_do_not_compile() -> void:
	_dir = "user://runner_fixture_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(_dir)
	_write("test_clean.gd", FIXTURE_CLEAN)
	_write("test_errors.gd", FIXTURE_ERRORS)
	_write("test_async.gd", FIXTURE_ASYNC)
	_write("test_broken.gd", FIXTURE_BROKEN)
	var output: Array = []
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"-s", "res://tests/run_tests.gd", "--", "--test-dir=" + _dir, "--async-timeout=2"])
	var code := OS.execute(OS.get_executable_path(), args, output, true)
	var text := "\n".join(output)
	var fails: Array[String] = []
	for line in text.split("\n"):
		if line.begins_with("FAIL "):
			fails.append(line)
	check_eq(code, 1, "the run fails")
	# The four tests that must pass: no FAIL line names them.
	for passing in ["test_clean_passes", "test_expected_error_passes", "test_warning_passes", "test_async_passes"]:
		check(not _has(fails, ":" + passing + " "), "%s passes" % passing)
	# The ones that must fail, each with the reason in its message.
	check(_has(fails, "test_clean.gd:test_failing_check_fails – FIXTURE_PLAIN_CHECK"), "a plain failed check still fails")
	check(_has(fails, "test_errors.gd:test_script_error_fails – unexpected error: Invalid call. Nonexistent function 'no_such_method'"), "a script error inside a helper fails the test")
	check(_has(fails, "test_errors.gd:test_script_error_that_ends_the_method_fails – unexpected error: Invalid call"), "so does one that ends the method")
	check(_has(fails, "test_errors.gd:test_push_error_fails – unexpected error: FIXTURE_PUSH"), "so does push_error")
	check(_has(fails, "test_errors.gd:test_expected_error_that_does_not_happen_fails – expected error \"FIXTURE_MISSING\""), "an expected error that did not happen")
	check(_has(fails, "test_errors.gd:test_error_beyond_the_expected_count_fails – unexpected error: FIXTURE_TWICE"), "a second error where one was declared")
	check(_has(fails, "test_errors.gd:test_error_not_covered_by_the_expectation_fails – unexpected error: FIXTURE_UNCOVERED"), "an error the expectation does not cover")
	check(_has(fails, "test_async.gd:test_async_error_before_finishing_fails – unexpected error: FIXTURE_ASYNC_PUSH"), "an async test is attributed its errors")
	check(_has(fails, "test_async.gd:test_async_script_error_after_an_await_fails – unexpected error: Invalid call"), "also a script error after an await")
	check(_has(fails, "test_async.gd:test_async_coroutine_ended_by_an_error_times_out – async test did not finish"), "a coroutine an error ended times out")
	check(_has(fails, "test_async.gd:test_async_coroutine_ended_by_an_error_times_out – unexpected error: Invalid call"), "with the error that ended it")
	check(_has(fails, "test_broken.gd: failed to load / compile"), "a file that does not compile fails the run")
	check("4 passed, 11 failed" in text, "4 passed, 11 failed; got: %s" % text.right(200))
	check_eq(fails.size(), 12, "one FAIL line per failure (the timeout test has two)")


static func _has(lines: Array[String], needle: String) -> bool:
	for l in lines:
		if needle in l:
			return true
	return false
