class_name ErrorCounter
extends Logger
## Counts engine / script errors and warnings while installed with OS.add_logger() (smoke
## runs report them in SMOKE_RESULT). May be called from any thread, hence the mutex.

const MAX_SAMPLES := 8

var errors := 0
var warnings := 0
## The first few error messages ("file:line: text").
var samples: Array[String] = []

var _mutex := Mutex.new()


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	var text := rationale if rationale != "" else code
	_mutex.lock()
	if error_type == ERROR_TYPE_WARNING:
		warnings += 1
	else:
		errors += 1
		if samples.size() < MAX_SAMPLES:
			samples.append("%s:%d %s: %s" % [file.get_file(), line, function, text])
	_mutex.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass


func error_count() -> int:
	_mutex.lock()
	var n := errors
	_mutex.unlock()
	return n


func warning_count() -> int:
	_mutex.lock()
	var n := warnings
	_mutex.unlock()
	return n


func error_samples() -> Array[String]:
	_mutex.lock()
	var out := samples.duplicate()
	_mutex.unlock()
	return out
