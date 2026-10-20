class_name TestErrorLogger
extends Logger
## Collects the engine / script errors logged while it is installed with OS.add_logger(), for the
## test runner to attribute to the test that was running: GDScript runtime errors ("SCRIPT ERROR:
## null access, invalid call, out of bounds ...", which abort the method but leave a green test),
## push_error() and engine errors (ConfigFile parse errors, failed loads ...). Warnings are not
## collected. Same mechanism as ErrorCounter (smoke runs), but it keeps every entry and hands them
## out per test. May be called from any thread, hence the mutex.

## One logged error.
class Entry:
	## The error text (what a script error says, or the engine's message). [method TestCase.expect_error]
	## matches against this only.
	var message := ""
	## "file:line function" of the logging site (engine source for push_error and engine errors).
	var where := ""
	## The script call stack, innermost first ("func (file.gd:12) < caller (...)"); "" if there is none.
	var stack := ""

	func describe() -> String:
		var out := message
		if where != "":
			out += "  [at %s]" % where
		if stack != "":
			out += "  [stack %s]" % stack
		return out


const MAX_STACK_FRAMES := 6
const RUNNER_FILE := "res://tests/run_tests.gd"

var _mutex := Mutex.new()
var _entries: Array[Entry] = []


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	var entry := Entry.new()
	# A failed engine check has the expression in `code` and the message in `rationale`; script
	# errors and push_error() only have `code`.
	entry.message = rationale if rationale != "" else code
	entry.where = "%s:%d %s" % [file, line, function]
	entry.stack = _format_stack(script_backtraces)
	_mutex.lock()
	_entries.append(entry)
	_mutex.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass


## Returns the errors logged since the last call and forgets them.
func drain() -> Array[Entry]:
	_mutex.lock()
	var out := _entries
	_entries = []
	_mutex.unlock()
	return out


static func _format_stack(backtraces: Array[ScriptBacktrace]) -> String:
	for bt in backtraces:
		if bt.is_empty():
			continue
		var frames: Array[String] = []
		for i in bt.get_frame_count():
			var frame_file := bt.get_frame_file(i)
			if frame_file == RUNNER_FILE:
				break  # the runner itself (and whatever resumed it) is not interesting
			if frames.size() == MAX_STACK_FRAMES:
				frames.append("...")
				break
			frames.append("%s (%s:%d)" % [bt.get_frame_function(i), frame_file.get_file(), bt.get_frame_line(i)])
		return " < ".join(frames)
	return ""
