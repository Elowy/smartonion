class_name TestCase
extends RefCounted
## Base class for tests run by tests/run_tests.gd.

@warning_ignore("unused_signal")
signal finished

var tree: SceneTree
var failures: Array[String] = []

## The errors this test declared with [method expect_error]: {"text": String, "times": int, "seen": int}.
var _expected_errors: Array[Dictionary] = []


func before_each() -> void:
	pass


func after_each() -> void:
	pass


## Async tests override this to return true and emit [signal finished] when done.
func is_async() -> bool:
	return false


## Declares that this test deliberately provokes an engine / script error (push_error, a ConfigFile
## parse error, ...) whose message contains [param substring], exactly [param times] times. The runner
## fails every other error logged while the test runs (a GDScript runtime error such as a null access
## aborts the method but would otherwise leave the test green), and fails the test too when an
## expected error does not show up. Keep the substring as narrow as the message allows; call it in the
## test (or in before_each) before or after the code that logs the error.
func expect_error(substring: String, times: int = 1) -> void:
	if substring == "" or times < 1:
		failures.append("expect_error needs a non-empty substring and times >= 1")
		return
	_expected_errors.append({"text": substring, "times": times, "seen": 0})


## Called by the runner after the test (and after_each) with the errors logged meanwhile: the ones
## not covered by [method expect_error] fail the test, and so does an expected one that did not occur.
## [param stray] are errors logged before the test started (late errors of the previous one): they
## cannot be expected.
func review_errors(logged: Array[TestErrorLogger.Entry], stray: Array[TestErrorLogger.Entry] = []) -> void:
	for entry in stray:
		failures.append("error logged between tests (late error of the previous test?): %s" % entry.describe())
	for entry in logged:
		var expected := false
		for e in _expected_errors:
			if int(e["seen"]) < int(e["times"]) and String(e["text"]) in entry.message:
				e["seen"] = int(e["seen"]) + 1
				expected = true
				break
		if not expected:
			failures.append("unexpected error: %s" % entry.describe())
	for e in _expected_errors:
		if int(e["seen"]) != int(e["times"]):
			failures.append("expected error \"%s\" %d time(s), seen %d" % [e["text"], e["times"], e["seen"]])


func check(condition: bool, message: String = "check failed") -> void:
	if not condition:
		failures.append(message)


func check_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if typeof(actual) in [TYPE_FLOAT, TYPE_INT] and typeof(expected) in [TYPE_FLOAT, TYPE_INT]:
		if not is_equal_approx(float(actual), float(expected)):
			failures.append("%s expected %s, got %s" % [message, expected, actual])
	elif actual != expected:
		failures.append("%s expected %s, got %s" % [message, expected, actual])


func check_near(actual: float, expected: float, tolerance: float, message: String = "") -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%s expected %s ± %s, got %s" % [message, expected, tolerance, actual])
