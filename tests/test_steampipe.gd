extends TestCase
## STEAMPIPE: tools/steam/upload.sh and the VDF templates, run for real in a scratch project root (--root) with a
## FAKE content folder and a FAKE steamcmd. No Steam account, no login, no network: a dry run never touches steamcmd,
## and the fake steamcmd only records the command line it was given.
## Skipped (and said so) where there is no bash, e.g. a plain Windows shell.

const SCRIPT := "res://tools/steam/upload.sh"
const TEMPLATE_DIR := "res://tools/steam/steampipe/"
const APP_ID := "2345670"
const DEPOT_WIN := "2345671"
const DEPOT_LINUX := "2345672"

var _root := ""
var _have_bash := false
var _counter := 0
var _script_path := ""


func before_each() -> void:
	_script_path = ProjectSettings.globalize_path(SCRIPT)
	var out: Array = []
	_have_bash = OS.get_name() != "Windows" and OS.execute("bash", ["--version"], out, true) == OK
	_root = ""


func after_each() -> void:
	if _root != "":
		_remove_tree(_root)


# --- Fixture ----------------------------------------------------------------------------------

func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		check(false, "cannot write %s" % path)
		return
	file.store_string(text)
	file.close()


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	for f in dir.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)


func _exists(rel: String) -> bool:
	return FileAccess.file_exists(_root.path_join(rel)) or DirAccess.dir_exists_absolute(_root.path_join(rel))


func _read(rel: String) -> String:
	return FileAccess.get_file_as_string(_root.path_join(rel))


## A scratch project root with a project.godot (app id [param app_id], version 0.9.0) and, if [param content], a
## complete fake Steam export: exe + Steamworks + GodotSteam libraries + a pdb that must be excluded.
func _make_root(app_id: String = APP_ID, content: bool = true) -> void:
	_counter += 1
	_root = ProjectSettings.globalize_path("user://steampipe_test_%d_%d" % [Time.get_ticks_msec(), _counter])
	_write(_root.path_join("project.godot"), "config_version=5\n\n[application]\n\nconfig/name=\"SmartOnion\"\nconfig/version=\"0.9.0\"\n\n[smartonion]\n\nsteam/app_id=%s\n" % app_id)
	if content:
		var win := "build/steam/content/windows/"
		_write(_root.path_join(win + "SmartOnion.exe"), "exe")
		_write(_root.path_join(win + "steam_api64.dll"), "dll")
		_write(_root.path_join(win + "libgodotsteam.windows.template_release.x86_64.dll"), "dll")
		_write(_root.path_join(win + "SmartOnion.pdb"), "pdb")
		_write(_root.path_join(win + "build_info.txt"), "version 0.9.0 steam yes")
		var lin := "build/steam/content/linux/"
		_write(_root.path_join(lin + "SmartOnion.x86_64"), "elf")
		FileAccess.set_unix_permissions(_root.path_join(lin + "SmartOnion.x86_64"), 493)  # 0755
		_write(_root.path_join(lin + "libsteam_api.so"), "so")
		_write(_root.path_join(lin + "libgodotsteam.linux.template_release.x86_64.so"), "so")


## Runs upload.sh with [param args] (and [param env] "NAME=value" entries); returns {code, out}.
func _run(args: Array[String], env: Array[String] = []) -> Dictionary:
	var out: Array = []
	var full: Array[String] = []
	full.append_array(env)
	full.append_array(["bash", _script_path, "--root", _root])
	full.append_array(args)
	var code := OS.execute("env", full, out, true)
	return {"code": code, "out": "".join(out)}


func _dry(extra: Array[String] = []) -> Dictionary:
	var args: Array[String] = ["--dry-run", "--depot-win", DEPOT_WIN, "--depot-linux", DEPOT_LINUX]
	args.append_array(extra)
	return _run(args)


## A fake steamcmd in the scratch root that writes its arguments, one per line, to build/fake_args.txt.
func _fake_steamcmd(exit_code: int = 0) -> String:
	var path := _root.path_join("fake_steamcmd.sh")
	_write(path, "#!/usr/bin/env bash\nprintf '%%s\\n' \"$@\" > \"$(dirname \"$0\")/fake_args.txt\"\nexit %d\n" % exit_code)
	FileAccess.set_unix_permissions(path, 493)
	return path


func _fake_args() -> PackedStringArray:
	if not _exists("fake_args.txt"):
		return PackedStringArray()
	return _read("fake_args.txt").strip_edges().split("\n")


func _upload_args(extra: Array[String] = []) -> Array[String]:
	var args: Array[String] = ["--user", "build_acct", "--depot-win", DEPOT_WIN, "--depot-linux", DEPOT_LINUX, "--steamcmd", _fake_steamcmd()]
	args.append_array(extra)
	return args


# --- The scripts ----------------------------------------------------------------------------------

func test_the_script_parses_and_has_a_help() -> void:
	if not _have_bash:
		return
	var out: Array = []
	check_eq(OS.execute("bash", ["-n", _script_path], out, true), 0, "bash -n: %s" % ["".join(out)])
	var help := OS.execute("bash", [_script_path, "--help"], out, true)
	check_eq(help, 0, "--help exits 0")
	var text := "".join(out)
	for needle in ["--dry-run", "--print-vdf", "--preview", "--app-id", "--depot-win", "--depot-linux", "--user", "--branch",
			"--desc", "--allow-test-app", "APP_ID", "DEPOT_WIN", "DEPOT_LINUX", "STEAM_USER", "Steam Guard"]:
		check(needle in text, "--help mentions %s" % needle)


func test_shellcheck_finds_no_error_if_it_is_installed() -> void:
	if not _have_bash:
		return
	var out: Array = []
	if OS.execute("shellcheck", ["--version"], out, true) != OK:
		return  # not installed: bash -n above is the check
	var code := OS.execute("shellcheck", ["--severity=error", _script_path], out, true)
	check_eq(code, 0, "shellcheck: %s" % ["".join(out)])


func test_the_script_is_executable_and_set_to_stop_on_errors() -> void:
	var source := FileAccess.get_file_as_string(SCRIPT)
	check(source.begins_with("#!/usr/bin/env bash"), "bash shebang")
	check("\nset -euo pipefail\n" in source, "set -euo pipefail")
	if OS.get_name() != "Windows":
		var perms := FileAccess.get_unix_permissions(SCRIPT)
		check(perms & FileAccess.UNIX_EXECUTE_OWNER != 0, "the script is executable")


func test_there_is_no_password_anywhere() -> void:
	var source := FileAccess.get_file_as_string(SCRIPT)
	var password := RegEx.create_from_string("(?i)(--password|STEAM_PASSWORD|\\$\\{?password)")
	check(password.search(source) == null, "no password option, variable or argument in the script")
	if not _have_bash:
		return
	_make_root()
	var r := _run(["--dry-run", "--password", "hunter2"])
	check_eq(r["code"], 2, "--password is an unknown option (usage error)")
	check("unknown option" in r["out"], "and says so")


func test_the_templates_exist_and_only_use_known_placeholders() -> void:
	var known := ["APP_ID", "DESC", "PREVIEW", "SET_LIVE", "CONTENT_ROOT", "BUILD_OUTPUT", "DEPOT_WIN", "DEPOT_LINUX", "DEPOT_ID", "DEPOT_CONTENT_ROOT"]
	var regex := RegEx.create_from_string("@([A-Z][A-Z_]*)@")
	for name in ["app_build.vdf.in", "depot_build_windows.vdf.in", "depot_build_linux.vdf.in"]:
		var text := FileAccess.get_file_as_string(TEMPLATE_DIR + name)
		check(text != "", "%s exists" % name)
		for m in regex.search_all(text):
			check(m.get_string(1) in known, "%s: placeholder %s is known" % [name, m.get_string(1)])
	var app := FileAccess.get_file_as_string(TEMPLATE_DIR + "app_build.vdf.in")
	check('"AppBuild"' in app and '"Depots"' in app and '"ContentRoot"' in app and '"BuildOutput"' in app, "the app build structure")
	for name in ["depot_build_windows.vdf.in", "depot_build_linux.vdf.in"]:
		var depot := FileAccess.get_file_as_string(TEMPLATE_DIR + name)
		check('"DepotBuild"' in depot and '"FileMapping"' in depot and '"FileExclusion" "*.pdb"' in depot, "%s: the depot structure" % name)
		check('"FileExclusion" "steam_appid.txt"' in depot, "%s: steam_appid.txt is excluded" % name)


# --- Dry run: the filled VDFs ------------------------------------------------------------------------

func test_a_dry_run_writes_the_filled_vdfs_and_logs_in_nowhere() -> void:
	if not _have_bash:
		return
	_make_root()
	var r := _dry()
	check_eq(r["code"], 0, "a dry run on a complete export succeeds: %s" % r["out"])
	for rel in ["build/steam/scripts/app_build_%s.vdf" % APP_ID, "build/steam/scripts/depot_build_%s.vdf" % DEPOT_WIN,
			"build/steam/scripts/depot_build_%s.vdf" % DEPOT_LINUX]:
		check(_exists(rel), "%s is written" % rel)
	var app := _read("build/steam/scripts/app_build_%s.vdf" % APP_ID)
	check('"AppID" "%s"' % APP_ID in app, "app id")
	check('"Desc" "v0.9.0 ' in app, "the description defaults to the version and the git state: %s" % app)
	check('"Preview" "0"' in app, "a normal build is not a preview")
	check('"SetLive" ""' in app, "nothing is set live by default")
	check('"ContentRoot" "%s"' % _root.path_join("build/steam/content") in app, "content root (absolute)")
	check('"BuildOutput" "%s"' % _root.path_join("build/steam/output") in app, "build output (absolute)")
	check('"%s" "depot_build_%s.vdf"' % [DEPOT_WIN, DEPOT_WIN] in app and '"%s" "depot_build_%s.vdf"' % [DEPOT_LINUX, DEPOT_LINUX] in app,
			"both depots are listed")
	check(RegEx.create_from_string("@[A-Z][A-Z_]*@").search(app) == null, "no placeholder is left")
	var win := _read("build/steam/scripts/depot_build_%s.vdf" % DEPOT_WIN)
	check('"DepotID" "%s"' % DEPOT_WIN in win, "Windows depot id")
	check('"ContentRoot" "%s"' % _root.path_join("build/steam/content/windows") in win, "Windows content root")
	check('"LocalPath" "*"' in win and '"DepotPath" "."' in win and '"Recursive" "1"' in win, "everything is mapped")
	check('"FileExclusion" "*.pdb"' in win, "pdb files are excluded")
	var lin := _read("build/steam/scripts/depot_build_%s.vdf" % DEPOT_LINUX)
	check('"DepotID" "%s"' % DEPOT_LINUX in lin, "Linux depot id")
	check('"ContentRoot" "%s"' % _root.path_join("build/steam/content/linux") in lin, "Linux content root")
	check(not _exists("build/steamcmd"), "steamcmd was not installed or touched")
	check("YOUR_STEAM_BUILD_ACCOUNT +run_app_build" in r["out"], "it shows the command it would run, with a placeholder account")


func test_print_vdf_shows_the_files() -> void:
	if not _have_bash:
		return
	_make_root()
	var r := _run(["--print-vdf", "--depot-win", DEPOT_WIN, "--depot-linux", DEPOT_LINUX])
	check_eq(r["code"], 0, "ok")
	check('"AppBuild"' in r["out"] and '"DepotBuild"' in r["out"] and '"DepotID" "%s"' % DEPOT_LINUX in r["out"], "the VDFs are printed")
	check(_exists("build/steam/scripts/app_build_%s.vdf" % APP_ID), "and written")


func test_environment_variables_fill_the_settings() -> void:
	if not _have_bash:
		return
	_make_root()
	var r := _run(["--dry-run"], ["DEPOT_WIN=" + DEPOT_WIN, "DEPOT_LINUX=" + DEPOT_LINUX, "STEAM_BRANCH=beta", "BUILD_DESC=from the environment"])
	check_eq(r["code"], 0, "ok: %s" % r["out"])
	var app := _read("build/steam/scripts/app_build_%s.vdf" % APP_ID)
	check('"SetLive" "beta"' in app, "STEAM_BRANCH")
	check('"Desc" "from the environment"' in app, "BUILD_DESC")
	check(_exists("build/steam/scripts/depot_build_%s.vdf" % DEPOT_WIN), "DEPOT_WIN")
	var flag := _run(["--dry-run", "--depot-win", DEPOT_WIN, "--depot-linux", DEPOT_LINUX, "--branch", "other"], ["STEAM_BRANCH=beta"])
	check_eq(flag["code"], 0, "ok")
	check('"SetLive" "other"' in _read("build/steam/scripts/app_build_%s.vdf" % APP_ID), "a flag beats the environment")


func test_the_description_is_made_safe_for_a_vdf() -> void:
	if not _have_bash:
		return
	_make_root()
	# Through a wrapper script: the quotes must reach upload.sh exactly as typed in a shell.
	var wrapper := _root.path_join("describe.sh")
	_write(wrapper, "#!/usr/bin/env bash\nbash \"$1\" --root \"$2\" --dry-run --depot-win %s --depot-linux %s --desc 'Tom & \"Jerry\" \\ 100%%'\n" % [DEPOT_WIN, DEPOT_LINUX])
	var out: Array = []
	check_eq(OS.execute("bash", [wrapper, _script_path, _root], out, true), 0, "ok: %s" % ["".join(out)])
	var app := _read("build/steam/scripts/app_build_%s.vdf" % APP_ID)
	check('"Desc" "Tom & \'Jerry\' \\\\ 100%"' in app, "quotes and backslashes cannot break the VDF: %s" % app)


# --- Refusals -----------------------------------------------------------------------------------------

func test_the_test_app_480_is_refused_unless_allowed() -> void:
	if not _have_bash:
		return
	_make_root("480")
	var r := _dry()
	check_eq(r["code"], 1, "app id 480 -> refused")
	check("480" in r["out"] and "test app" in r["out"], "and the reason is named: %s" % r["out"])
	check(not _exists("build/steam/scripts"), "no VDF was written")
	var allowed := _dry(["--allow-test-app"])
	check_eq(allowed["code"], 0, "--allow-test-app lets a dry run through: %s" % allowed["out"])
	check(_exists("build/steam/scripts/app_build_480.vdf"), "and writes the scripts")
	# A project.godot with no app id at all is the game's default 480 as well.
	_remove_tree(_root)
	_make_root("480")
	_write(_root.path_join("project.godot"), "config_version=5\n\n[application]\n\nconfig/name=\"SmartOnion\"\n")
	check_eq(_dry()["code"], 1, "no steam/app_id setting = 480 -> refused")


func test_an_app_id_that_differs_from_project_godot_is_refused() -> void:
	if not _have_bash:
		return
	_make_root()
	var r := _dry(["--app-id", "999"])
	check_eq(r["code"], 1, "mismatch -> refused")
	check("project.godot" in r["out"], "and project.godot is named: %s" % r["out"])
	check_eq(_dry(["--app-id", APP_ID])["code"], 0, "the same id given by flag is fine")
	check_eq(_run(["--dry-run", "--depot-win", DEPOT_WIN, "--depot-linux", DEPOT_LINUX], ["APP_ID=999"])["code"], 1, "also through APP_ID")


func test_missing_or_bad_settings_are_refused() -> void:
	if not _have_bash:
		return
	_make_root()
	check_eq(_run(["--dry-run", "--depot-linux", DEPOT_LINUX])["code"], 1, "no Windows depot id")
	check_eq(_run(["--dry-run", "--depot-win", DEPOT_WIN])["code"], 1, "no Linux depot id")
	check_eq(_run(["--dry-run", "--depot-win", "12a", "--depot-linux", DEPOT_LINUX])["code"], 1, "a depot id must be a number")
	check_eq(_run(["--dry-run", "--depot-win", "7", "--depot-linux", "7"])["code"], 1, "the two depots must differ")
	check_eq(_run(["--dry-run", "--depot-win", APP_ID, "--depot-linux", DEPOT_LINUX])["code"], 1, "a depot id is not the app id")
	check_eq(_dry(["--branch", "my beta"])["code"], 1, "a branch name has no spaces")
	check(not _exists("build/steam/scripts"), "none of that wrote a script")


func test_a_build_account_is_needed_for_a_real_run_only() -> void:
	if not _have_bash:
		return
	_make_root()
	var r := _run(["--depot-win", DEPOT_WIN, "--depot-linux", DEPOT_LINUX, "--steamcmd", _fake_steamcmd()])
	check_eq(r["code"], 1, "no --user / STEAM_USER -> refused")
	check("STEAM_USER" in r["out"], "and it says which: %s" % r["out"])
	check(_fake_args().is_empty(), "steamcmd was not started")
	check_eq(_dry()["code"], 0, "a dry run needs no account")


func test_missing_content_is_refused() -> void:
	if not _have_bash:
		return
	_make_root(APP_ID, false)
	var r := _dry()
	check_eq(r["code"], 1, "no content folders -> refused")
	check("windows content folder is missing" in r["out"] and "linux content folder is missing" in r["out"], "both are named: %s" % r["out"])
	check(not _exists("build/steam/scripts"), "no script was written")
	DirAccess.make_dir_recursive_absolute(_root.path_join("build/steam/content/windows"))
	DirAccess.make_dir_recursive_absolute(_root.path_join("build/steam/content/linux"))
	check("empty" in _dry()["out"], "empty folders are reported as empty")


func test_a_missing_executable_or_steam_library_is_refused() -> void:
	if not _have_bash:
		return
	var cases := [
		["build/steam/content/windows/SmartOnion.exe", "SmartOnion.exe"],
		["build/steam/content/windows/steam_api64.dll", "steam_api64.dll"],
		["build/steam/content/windows/libgodotsteam.windows.template_release.x86_64.dll", "libgodotsteam*.dll"],
		["build/steam/content/linux/SmartOnion.x86_64", "SmartOnion.x86_64"],
		["build/steam/content/linux/libsteam_api.so", "libsteam_api.so"],
		["build/steam/content/linux/libgodotsteam.linux.template_release.x86_64.so", "libgodotsteam*.so"],
	]
	for c: Array in cases:
		_make_root()
		DirAccess.remove_absolute(_root.path_join(c[0]))
		var r := _dry()
		check_eq(r["code"], 1, "without %s -> refused" % c[1])
		check(c[1] in r["out"], "and %s is named: %s" % [c[1], r["out"]])
		check(not _exists("build/steam/scripts"), "no script was written")
		_remove_tree(_root)
	_root = ""


func test_the_libraries_may_sit_in_a_sub_folder() -> void:
	if not _have_bash:
		return
	_make_root()
	DirAccess.remove_absolute(_root.path_join("build/steam/content/linux/libsteam_api.so"))
	_write(_root.path_join("build/steam/content/linux/addons/godotsteam/linux64/libsteam_api.so"), "so")
	check_eq(_dry()["code"], 0, "found below the executable's folder")


func test_a_steam_appid_txt_in_the_content_is_refused() -> void:
	if not _have_bash:
		return
	_make_root()
	_write(_root.path_join("build/steam/content/windows/steam_appid.txt"), APP_ID)
	var r := _dry()
	check_eq(r["code"], 1, "steam_appid.txt -> refused")
	check("steam_appid.txt" in r["out"], "named: %s" % r["out"])


# --- steamcmd (a fake) ----------------------------------------------------------------------------------

func test_a_real_run_starts_steamcmd_with_a_login_and_no_password() -> void:
	if not _have_bash:
		return
	_make_root()
	var r := _run(_upload_args())
	check_eq(r["code"], 0, "ok: %s" % r["out"])
	var args := _fake_args()
	var app_vdf := _root.path_join("build/steam/scripts/app_build_%s.vdf" % APP_ID)
	check_eq(args, PackedStringArray(["+@ShutdownOnFailedCommand", "1", "+login", "build_acct", "+run_app_build", app_vdf, "+quit"]),
			"the exact steamcmd command line: no password, nothing else")
	check('"Preview" "0"' in _read("build/steam/scripts/app_build_%s.vdf" % APP_ID), "a real build")
	check('"SetLive" ""' in _read("build/steam/scripts/app_build_%s.vdf" % APP_ID), "set live nowhere")


func test_preview_makes_a_preview_build() -> void:
	if not _have_bash:
		return
	_make_root()
	var r := _run(_upload_args(["--preview"]))
	check_eq(r["code"], 0, "ok: %s" % r["out"])
	check('"Preview" "1"' in _read("build/steam/scripts/app_build_%s.vdf" % APP_ID), "Preview 1")
	check(_fake_args().has("+run_app_build"), "steamcmd ran")
	var both := _run(["--preview", "--branch", "beta", "--dry-run", "--depot-win", DEPOT_WIN, "--depot-linux", DEPOT_LINUX])
	check_eq(both["code"], 0, "--preview with --dry-run: ok")
	var app := _read("build/steam/scripts/app_build_%s.vdf" % APP_ID)
	check('"Preview" "1"' in app and '"SetLive" ""' in app, "a preview never sets anything live")


func test_set_live_only_for_a_named_non_default_branch() -> void:
	if not _have_bash:
		return
	_make_root()
	var r := _run(_upload_args(["--branch", "beta"]))
	check_eq(r["code"], 0, "ok: %s" % r["out"])
	check('"SetLive" "beta"' in _read("build/steam/scripts/app_build_%s.vdf" % APP_ID), "SetLive beta")
	for forbidden in ["default", "Default", "DEFAULT", "public"]:
		DirAccess.remove_absolute(_root.path_join("fake_args.txt"))
		var bad := _run(_upload_args(["--branch", forbidden]))
		check_eq(bad["code"], 1, "branch '%s' -> refused" % forbidden)
		check(_fake_args().is_empty(), "'%s': steamcmd was not started" % forbidden)


func test_a_failing_steamcmd_fails_the_upload() -> void:
	if not _have_bash:
		return
	_make_root()
	var args := _upload_args()
	args[args.size() - 1] = _fake_steamcmd(5)
	var r := _run(args)
	check_eq(r["code"], 1, "steamcmd exit 5 -> upload.sh fails")
	check("steamcmd failed" in r["out"], "and says so: %s" % r["out"])


func test_a_missing_steamcmd_path_is_refused_without_downloading() -> void:
	if not _have_bash:
		return
	_make_root()
	var r := _run(["--user", "x", "--depot-win", DEPOT_WIN, "--depot-linux", DEPOT_LINUX, "--steamcmd", _root.path_join("nope/steamcmd.sh")])
	check_eq(r["code"], 1, "--steamcmd that does not exist -> refused")
	check(not _exists("build/steamcmd"), "nothing was installed")


# --- .gitignore ------------------------------------------------------------------------------------------

func test_gitignore_keeps_steam_secrets_and_build_output_out_of_git() -> void:
	var lines := FileAccess.get_file_as_string("res://.gitignore").split("\n")
	var stripped: Array[String] = []
	for line in lines:
		stripped.append(line.strip_edges())
	check("/build/" in stripped, "build/ (content, scripts, output, the steamcmd login token) is ignored")
	check("steam_appid.txt" in stripped, "a steam_appid.txt is ignored")
	check("ssfn*" in stripped, "Steam Guard sentry files are ignored")
	check("/addons/godotsteam/" in stripped, "the plug-in is ignored")
