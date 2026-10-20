extends SceneTree
## Minimal dependency-free test runner.
##
##   godot --headless --path . -s res://tests/run_tests.gd [-- --filter=<substring>] [--test-dir=<dir>]
##
## Every res://tests/test_*.gd script must extend TestCase. Each method whose name starts
## with "test_" is run on a fresh instance. Exits with code 1 if anything fails.
##
## An engine / script error logged while a test runs (a GDScript runtime error, push_error(), a
## failed load ...) fails that test unless it declared it with TestCase.expect_error(): Godot only
## logs such an error and returns from the method, so the test would otherwise stay green. A test
## file that does not compile fails the run, with the compile errors in the message.
## --test-dir (default res://tests/) is for the runner's own test, which runs generated fixtures.

const TEST_DIR := "res://tests/"
## An async test that has not emitted `finished` after this many seconds fails: a script error in
## its coroutine ends it silently, so it would never finish and hang the run.
const ASYNC_TIMEOUT_SEC := 120.0

var _logger: TestErrorLogger


## Waits for [signal TestCase.finished] or the timeout, whichever comes first.
class FinishWaiter extends RefCounted:
	signal done
	var is_done := false
	var timed_out := false

	func on_finished() -> void:
		is_done = true
		done.emit()

	func on_timeout() -> void:
		timed_out = true
		on_finished()


func _initialize() -> void:
	_logger = TestErrorLogger.new()
	OS.add_logger(_logger)
	# Defer so autoloads are in the tree and _ready() has run.
	_run.call_deferred()


func _run() -> void:
	# Tests never touch the player's leaderboard file (a test that exercises Leaderboard.record_run
	# sets Leaderboard.path_override to a temp path and switches writing on itself). Set through the
	# script object: naming the class here would compile it (and the autoloads it needs) before the
	# autoloads exist.
	var leaderboard: GDScript = load("res://core/leaderboard.gd")
	leaderboard.set(&"writes_enabled", false)
	# The lobby's "Rolling the arena..." screen (4.5 s) is off in tests; a test of the screen switches it on.
	var roll_screen: GDScript = load("res://scenes/ui/environment_roll_screen.gd")
	roll_screen.set(&"enabled", false)
	# No shrine at a break unless a test asks for one (--shrine-chance / RunState.shrine_chance_override): a
	# random 5% shrine would turn every Main flow test that follows a wave into a flake.
	var shrines: GDScript = load("res://core/shrines.gd")
	shrines.set(&"base_chance", 0.0)
	var filter := ""
	var test_dir := TEST_DIR
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.trim_prefix("--filter=")
		elif arg.begins_with("--test-dir="):
			test_dir = arg.trim_prefix("--test-dir=").trim_suffix("/") + "/"
	var files := ResourceLoader.list_directory(test_dir)
	files.sort()
	var passed := 0
	var failed := 0
	var failures: Array[String] = []
	for file in files:
		if not (file.begins_with("test_") and file.ends_with(".gd")):
			continue
		if _report_outside_a_test("before " + file, failures):
			failed += 1
		var script: GDScript = load(test_dir + file)
		var load_errors := _logger.drain()
		var loads := script != null and script.can_instantiate()
		if not loads or not load_errors.is_empty():
			failures.append("%s: failed to load / compile%s" % [file, _describe(load_errors)])
			failed += 1
		if not loads:
			continue
		for method in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			if filter != "" and filter not in file + ":" + name:
				continue
			var stray := _logger.drain()
			var case: TestCase = script.new()
			case.tree = self
			var waiter := FinishWaiter.new()
			case.finished.connect(waiter.on_finished)
			case.before_each()
			case.call(name)
			if case.is_async() and not waiter.is_done:
				var timer := create_timer(ASYNC_TIMEOUT_SEC, true, false, true)
				timer.timeout.connect(waiter.on_timeout)
				await waiter.done
				if waiter.timed_out:
					case.failures.append("async test did not finish within %d s (a script error in its coroutine ends it silently)" % int(ASYNC_TIMEOUT_SEC))
				else:
					timer.timeout.disconnect(waiter.on_timeout)
			case.after_each()
			case.review_errors(_logger.drain(), stray)
			if case.failures.is_empty():
				passed += 1
			else:
				failed += 1
				for f in case.failures:
					failures.append("%s:%s – %s" % [file, name, f])
	if _report_outside_a_test("after the last test", failures):
		failed += 1
	OS.remove_logger(_logger)
	for f in failures:
		printerr("FAIL ", f)
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


## Errors logged between tests (nothing declared them, nothing was running): a failure of their own,
## because they would otherwise land on the next test's account. True if there were any.
func _report_outside_a_test(when: String, failures: Array[String]) -> bool:
	var stray := _logger.drain()
	if stray.is_empty():
		return false
	failures.append("<%s>: errors logged outside any test:%s" % [when, _describe(stray)])
	return true


## " – <error> – <error>" for a failure line; "" without errors.
static func _describe(errors: Array[TestErrorLogger.Entry]) -> String:
	var out := ""
	for e in errors:
		out += " – %s" % e.describe()
	return out
