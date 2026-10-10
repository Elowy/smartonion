class_name TestCase
extends RefCounted
## Base class for tests run by tests/run_tests.gd.

@warning_ignore("unused_signal")
signal finished

var tree: SceneTree
var failures: Array[String] = []


func before_each() -> void:
	pass


func after_each() -> void:
	pass


## Async tests override this to return true and emit [signal finished] when done.
func is_async() -> bool:
	return false


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
