extends SceneTree
## Minimal dependency-free test runner.
##
##   godot --headless --path . -s res://tests/run_tests.gd [-- --filter=<substring>]
##
## Every res://tests/test_*.gd script must extend TestCase. Each method whose name starts
## with "test_" is run on a fresh instance. Exits with code 1 if anything fails.

const TEST_DIR := "res://tests/"


func _initialize() -> void:
	# Defer so autoloads are in the tree and _ready() has run.
	_run.call_deferred()


func _run() -> void:
	# Tests never touch the player's leaderboard file (a test that exercises Leaderboard.record_run
	# sets Leaderboard.path_override to a temp path and switches writing on itself). Set through the
	# script object: naming the class here would compile it (and the autoloads it needs) before the
	# autoloads exist.
	var leaderboard: GDScript = load("res://core/leaderboard.gd")
	leaderboard.set(&"writes_enabled", false)
	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.trim_prefix("--filter=")
	var files := ResourceLoader.list_directory(TEST_DIR)
	files.sort()
	var passed := 0
	var failed := 0
	var failures: Array[String] = []
	for file in files:
		if not (file.begins_with("test_") and file.ends_with(".gd")):
			continue
		var script: GDScript = load(TEST_DIR + file)
		if script == null or not script.can_instantiate():
			failures.append("%s: failed to load / compile" % file)
			failed += 1
			continue
		for method in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			if filter != "" and filter not in file + ":" + name:
				continue
			var case: TestCase = script.new()
			case.tree = self
			case.before_each()
			case.call(name)
			if case.is_async():
				await case.finished
			case.after_each()
			if case.failures.is_empty():
				passed += 1
			else:
				failed += 1
				for f in case.failures:
					failures.append("%s:%s – %s" % [file, name, f])
	for f in failures:
		printerr("FAIL ", f)
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
