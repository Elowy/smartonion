extends SceneTree
## Build tool (not shipped): checks what a release export packed. tools/build/export.sh runs it on every
## executable it builds - the editor binary opens the embedded PCK as the project (the release template cannot
## run an outside script), so the check sees exactly the files the player's executable holds:
##
##   godot --headless --main-pack build/steam/content/linux/SmartOnion.x86_64 \
##       -s tools/build/verify_pack.gd -- [--steam]
##
## Passes (prints "PACK_OK files=N", exit 0) when
##   - CREDITS.md and the font / icon licence texts are in (the Credits page reads res://CREDITS.md),
##   - the main scene and a data folder are in,
##   - nothing dev-only is in: tests/, tools/, docs/, build/, CLAUDE.md, README.md, no stray .md files,
##   - the GodotSteam plug-in is in with --steam and absent without it.
## Fails with "PACK_FAIL: ..." lines and exit 1 otherwise.

const MUST_EXIST: Array[String] = [
	"res://CREDITS.md",
	"res://assets/fonts/OFL.txt",
	"res://assets/icons/LICENSE.txt",
	"res://data",
]
const MUST_LOAD: Array[String] = [
	"res://scenes/main/main.tscn",
	"res://scenes/ui/main_menu.gd",
]
## Folders / files of the project that a release build must not hold.
const FORBIDDEN_PREFIXES: Array[String] = [
	"res://tests",
	"res://tools",
	"res://docs",
	"res://build",
	"res://screenshots",
	"res://CLAUDE.md",
	"res://README.md",
	"res://export_presets.cfg",
]
## The only .md files a release may hold (licence notices).
const ALLOWED_MD: Array[String] = ["res://CREDITS.md", "res://addons/godotsteam/license.md"]
const STEAM_FILES: Array[String] = [
	"res://addons/godotsteam/godotsteam.gdextension",
	"res://addons/godotsteam/license.md",
]

## Problems printed before "... and N more".
const MAX_REPORTED := 25

var _problems: Array[String] = []


func _init() -> void:
	var with_steam := OS.get_cmdline_user_args().has("--steam")
	var files: Array[String] = []
	_collect("res://", files)
	if files.size() < 100:
		_problems.append("the pack holds only %d files - is this a game executable's PCK?" % files.size())

	for path in MUST_EXIST:
		if not (FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)):
			_problems.append("missing in the pack: %s" % path)
	for path in MUST_LOAD:
		if not ResourceLoader.exists(path):
			_problems.append("missing resource in the pack: %s" % path)
	var credits := FileAccess.get_file_as_string("res://CREDITS.md")
	if not credits.begins_with("#") or credits.length() < 200:
		_problems.append("CREDITS.md is empty or unreadable in the pack (%d characters)" % credits.length())

	for path in files:
		for prefix in FORBIDDEN_PREFIXES:
			if path == prefix or path.begins_with(prefix + "/"):
				_problems.append("dev-only file in the pack: %s" % path)
		if path.ends_with(".md") and not ALLOWED_MD.has(path):
			_problems.append("unexpected .md file in the pack: %s" % path)

	var has_addons := DirAccess.dir_exists_absolute("res://addons")
	for path in STEAM_FILES:
		if with_steam and not FileAccess.file_exists(path):
			_problems.append("--steam build without %s" % path)
	if not with_steam and has_addons:
		_problems.append("a build without --steam holds res://addons (the Steam plug-in)")

	if _problems.is_empty():
		print("PACK_OK files=%d credits=%d chars steam=%s" % [files.size(), credits.length(), str(with_steam)])
		quit(0)
		return
	for i in mini(_problems.size(), MAX_REPORTED):
		print("PACK_FAIL: ", _problems[i])
	if _problems.size() > MAX_REPORTED:
		print("PACK_FAIL: ... and %d more" % (_problems.size() - MAX_REPORTED))
	quit(1)


## Every file of the pack below [param dir], as "res://..." paths.
func _collect(dir: String, out: Array[String]) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(sub), out)
	for file in DirAccess.get_files_at(dir):
		out.append(dir.path_join(file))
