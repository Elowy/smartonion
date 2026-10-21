extends TestCase
## STEAMPIPE: the "launch through Steam" check, SteamRemotePlayBackend.restart_through_steam_if_needed() and
## RemotePlay.hand_over_to_steam_if_needed(), driven by the fake "Steam" singleton (no Steam client, no plug-in).
## restartAppIfNecessary(app_id) may only be called in a release export, with the real app id (not 480), outside
## automated runs, with the plug-in present; when it answers true the game quits.

## Catches push_warning() messages (the test runner's own logger only keeps errors).
class WarningCatcher extends Logger:
	var warnings: Array[String] = []

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			warnings.append(rationale if rationale != "" else code)

const REAL_APP_ID := 2345670
const REMOTE_PLAY_SCRIPT := "res://autoload/remote_play.gd"

var _fake: FakeSteamSingleton
var _catcher: WarningCatcher
var _saved_app_id: Variant
var _lookups := 0
var _quits := 0
var _remote_play: Node


func before_each() -> void:
	_fake = FakeSteamSingleton.new()
	_catcher = WarningCatcher.new()
	OS.add_logger(_catcher)
	_saved_app_id = ProjectSettings.get_setting(SteamRemotePlayBackend.APP_ID_SETTING, null)
	ProjectSettings.set_setting(SteamRemotePlayBackend.APP_ID_SETTING, REAL_APP_ID)
	_lookups = 0
	_quits = 0
	var script := load(REMOTE_PLAY_SCRIPT) as GDScript
	_remote_play = script.new()


func after_each() -> void:
	OS.remove_logger(_catcher)
	ProjectSettings.set_setting(SteamRemotePlayBackend.APP_ID_SETTING, _saved_app_id)
	_remote_play.free()


# --- Seams --------------------------------------------------------------------------------------

func _provide_fake() -> Object:
	_lookups += 1
	return _fake


func _provide_nothing() -> Object:
	_lookups += 1
	return null


func _not_automated() -> bool:
	return false


func _automated() -> bool:
	return true


func _release() -> bool:
	return true


func _debug() -> bool:
	return false


func _quit() -> void:
	_quits += 1


## The check as a real release session would run it.
func _restart_in_release() -> bool:
	return SteamRemotePlayBackend.restart_through_steam_if_needed(_provide_fake, _not_automated, _release)


# --- The call itself --------------------------------------------------------------------------

func test_a_release_export_with_a_real_id_asks_steam_and_passes_the_answer_on() -> void:
	_fake.restart_needed = true
	check(_restart_in_release(), "Steam says restart -> true (quit)")
	check_eq(_fake.restart_requests, [REAL_APP_ID] as Array[int], "asked once, with the configured app id")
	check_eq(_fake.calls, ["restartAppIfNecessary"] as Array[String], "and nothing else was called")
	_fake.restart_needed = false
	check(not _restart_in_release(), "launched by Steam -> false (play on)")
	check_eq(_fake.restart_requests.size(), 2, "the second call was a real ask too")
	check(_catcher.warnings.is_empty(), "no warnings: %s" % [_catcher.warnings])


func test_the_check_is_not_gated_on_steam_being_initialised() -> void:
	# Valve: it comes BEFORE SteamAPI_Init. The fake records a gated call made before init; this one must not be.
	check(not _fake.initialized, "a fresh fake is not initialised")
	_restart_in_release()
	check(_fake.calls_while_uninitialised.is_empty(), "restartAppIfNecessary is not an 'uninitialised' call")
	check_eq(_fake.count("steamInitEx"), 0, "and the check does not initialise Steam itself")


# --- The gates: never called -----------------------------------------------------------------

func test_the_test_app_480_never_restarts() -> void:
	_fake.restart_needed = true
	ProjectSettings.set_setting(SteamRemotePlayBackend.APP_ID_SETTING, 480)
	check(not _restart_in_release(), "app id 480 -> false")
	ProjectSettings.set_setting(SteamRemotePlayBackend.APP_ID_SETTING, null)
	check(not _restart_in_release(), "no app id at all (the default 480) -> false")
	for bad: Variant in [0, -3, "x", ""]:
		ProjectSettings.set_setting(SteamRemotePlayBackend.APP_ID_SETTING, bad)
		check(not _restart_in_release(), "%s is no app id (480) -> false" % [bad])
	check(_fake.restart_requests.is_empty(), "restartAppIfNecessary was never called: %s" % [_fake.restart_requests])
	check_eq(_lookups, 0, "the singleton was not even looked up")


func test_an_automated_run_never_restarts() -> void:
	_fake.restart_needed = true
	check(not SteamRemotePlayBackend.restart_through_steam_if_needed(_provide_fake, _automated, _release),
			"an automated release-like run -> false")
	check(_fake.calls.is_empty(), "nothing was called on Steam: %s" % [_fake.calls])
	check_eq(_lookups, 0, "the singleton was not looked up")
	check(_catcher.warnings.is_empty(), "and nothing was warned about")


func test_the_test_runner_itself_is_an_automated_run() -> void:
	check(Settings.is_automated_run(), "the test runner is an automated run")
	_fake.restart_needed = true
	# No automated seam: the real engine answer.
	check(not SteamRemotePlayBackend.restart_through_steam_if_needed(_provide_fake, Callable(), _release),
			"even a 'release' test run does not restart")
	check(_fake.calls.is_empty(), "nothing was called on Steam")


func test_the_editor_and_debug_exports_never_restart() -> void:
	_fake.restart_needed = true
	check(not SteamRemotePlayBackend.restart_through_steam_if_needed(_provide_fake, _not_automated, _debug),
			"a debug / editor run -> false")
	check(_fake.calls.is_empty(), "nothing was called on Steam")
	check_eq(_lookups, 0, "the singleton was not looked up")
	# The default release test: a real release EXPORT only (this test run is not one).
	check(not SteamRemotePlayBackend.is_release_build(), "the test runner is not a release export")
	check(not SteamRemotePlayBackend.restart_through_steam_if_needed(_provide_fake, _not_automated),
			"the default release check says no here")
	check(_fake.calls.is_empty(), "still nothing was called")


func test_with_no_defaults_at_all_nothing_happens_here() -> void:
	# The plain call, as RemotePlay makes it: editor / test run -> false, whatever plug-in is installed.
	check(not SteamRemotePlayBackend.restart_through_steam_if_needed(), "the plain call is false in the tests")


func test_without_the_plug_in_there_is_nothing_to_ask() -> void:
	check(not SteamRemotePlayBackend.restart_through_steam_if_needed(_provide_nothing, _not_automated, _release),
			"no singleton -> false")
	check_eq(_lookups, 1, "the singleton was looked up")
	check(_catcher.warnings.is_empty(), "a missing plug-in is not worth a warning")


func test_a_plug_in_without_the_method_gives_one_warning_and_no_restart() -> void:
	var odd := RefCounted.new()
	var provide_odd := func() -> Object: return odd
	check(not SteamRemotePlayBackend.restart_through_steam_if_needed(provide_odd, _not_automated, _release),
			"no restartAppIfNecessary -> false")
	check_eq(_catcher.warnings.size(), 1, "one warning")
	if not _catcher.warnings.is_empty():
		check("restartAppIfNecessary" in _catcher.warnings[0], "it names the method: %s" % _catcher.warnings[0])


# --- RemotePlay: the quit -------------------------------------------------------------------------

func test_remote_play_quits_when_steam_says_so() -> void:
	_fake.restart_needed = true
	check(_remote_play.hand_over_to_steam_if_needed(_provide_fake, _not_automated, _release, _quit), "handed over")
	check_eq(_quits, 1, "the game quit once")
	check(_remote_play.steam_restart_requested, "and says why")
	check_eq(_fake.restart_requests, [REAL_APP_ID] as Array[int], "after one ask")


func test_remote_play_plays_on_when_the_exe_was_started_by_steam() -> void:
	check(not _remote_play.hand_over_to_steam_if_needed(_provide_fake, _not_automated, _release, _quit), "not handed over")
	check_eq(_quits, 0, "no quit")
	check(not _remote_play.steam_restart_requested, "no flag")
	check_eq(_fake.restart_requests.size(), 1, "Steam was asked")


func test_remote_play_never_quits_in_the_gated_cases() -> void:
	_fake.restart_needed = true
	check(not _remote_play.hand_over_to_steam_if_needed(_provide_fake, _automated, _release, _quit), "automated")
	check(not _remote_play.hand_over_to_steam_if_needed(_provide_fake, _not_automated, _debug, _quit), "debug / editor")
	check(not _remote_play.hand_over_to_steam_if_needed(_provide_nothing, _not_automated, _release, _quit), "no plug-in")
	ProjectSettings.set_setting(SteamRemotePlayBackend.APP_ID_SETTING, 480)
	check(not _remote_play.hand_over_to_steam_if_needed(_provide_fake, _not_automated, _release, _quit), "app id 480")
	check_eq(_quits, 0, "no quit in any of them")
	check(not _remote_play.steam_restart_requested, "no flag")
	check(_fake.restart_requests.is_empty(), "Steam was never asked")


func test_the_check_comes_before_the_steam_init_of_the_backend() -> void:
	# What RemotePlay._ready does: the hand-over check first, then the backend that initialises Steam.
	_fake.restart_needed = false
	check(not _remote_play.hand_over_to_steam_if_needed(_provide_fake, _not_automated, _release, _quit), "play on")
	var backend := SteamRemotePlayBackend.try_create(_provide_fake, _not_automated)
	check(backend != null, "the backend starts after it")
	check_eq(_fake.calls.slice(0, 2), ["restartAppIfNecessary", "get_current_app_id"] as Array[String],
			"restartAppIfNecessary is the first Steam call")
	check(_fake.calls.find("restartAppIfNecessary") < _fake.calls.find("steamInitEx"), "and it precedes steamInitEx")


func test_a_handed_over_launch_never_initialises_steam() -> void:
	# RemotePlay._ready returns right after a hand-over: the backend (and so steamInitEx) is never reached.
	_fake.restart_needed = true
	if _remote_play.hand_over_to_steam_if_needed(_provide_fake, _not_automated, _release, _quit):
		pass
	else:
		SteamRemotePlayBackend.try_create(_provide_fake, _not_automated)
	check_eq(_fake.count("steamInitEx"), 0, "Steam was not initialised by the process that quits")
	check(_remote_play.backend is NullRemotePlayBackend, "and it keeps the Null backend")


func test_remote_play_source_wires_the_check_before_the_backend() -> void:
	# Reads the autoload's source: _ready must call the hand-over before it creates a backend, and a --fake-rpt run
	# must skip it.
	var source := FileAccess.get_file_as_string(REMOTE_PLAY_SCRIPT)
	var ready_at := source.find("func _ready()")
	var hand_over_at := source.find("hand_over_to_steam_if_needed()", ready_at)
	var backend_at := source.find("set_backend(create_default_backend", ready_at)
	check(ready_at >= 0 and hand_over_at > ready_at and backend_at > hand_over_at,
			"_ready: the hand-over check comes before the backend is created")
	check("options.fake_rpt <= 0 and hand_over_to_steam_if_needed()" in source, "a --fake-rpt run skips the hand-over")
