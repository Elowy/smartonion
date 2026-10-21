extends TestCase
## BUILD: the release export setup (docs: tools/build/export.sh, export_presets.cfg). Reads the committed export presets
## and checks them against what the build scripts and the SteamPipe upload rely on (the content layout
## build/steam/content/<platform>/), the version setting and the main menu's version label, that no shipped script
## reaches into a folder the export leaves out, and that the build scripts parse (bash -n, shellcheck when installed).

const UiFakes := preload("res://tests/ui_fakes.gd")

const PRESETS_PATH := "res://export_presets.cfg"
const GITIGNORE_PATH := "res://.gitignore"
const EXPORT_SCRIPT := "res://tools/build/export.sh"
const TEMPLATES_SCRIPT := "res://tools/build/install_templates.sh"
const ICON_TOOL := "res://tools/build/make_icon.py"
const GAME_ICON := "res://assets/icon/smartonion_icon_256.png"
const VERSION_SETTING := "application/config/version"
## The owner / group / other execute bits of a Unix file mode (0o111).
const EXEC_BITS := 0x49
## Folders the release build leaves out (export_presets.cfg exclude_filter, written "tests/*").
const EXCLUDED_DIRS: Array[String] = ["tests", "tools", "docs"]
## Folders that are not project content at all (skipped by the source scans).
const SKIPPED_DIRS: Array[String] = [".godot", ".git", "addons", "build", "screenshots"]
const SCANNED_EXTENSIONS: Array[String] = ["gd", "tscn", "tres"]

var _nodes: Array[Node] = []
var _saved_version: Variant


func before_each() -> void:
	_saved_version = ProjectSettings.get_setting(VERSION_SETTING, null)


func after_each() -> void:
	for n in _nodes:
		UiFakes.free_node(n)
	_nodes.clear()
	ProjectSettings.set_setting(VERSION_SETTING, _saved_version)


# --- Helpers -------------------------------------------------------------------------------------

## The parsed export_presets.cfg.
func _presets() -> ConfigFile:
	var cfg := ConfigFile.new()
	var err := cfg.load(PRESETS_PATH)
	check_eq(err, OK, "export_presets.cfg loads")
	return cfg


## The section name ("preset.N") of the preset called [param preset_name], "" when there is none.
func _preset_section(cfg: ConfigFile, preset_name: String) -> String:
	for section in cfg.get_sections():
		if not section.ends_with(".options") and str(cfg.get_value(section, "name", "")) == preset_name:
			return section
	return ""


## The comma-separated filter [param key] of a preset as trimmed entries.
func _filter(cfg: ConfigFile, section: String, key: String) -> Array[String]:
	var out: Array[String] = []
	for entry in str(cfg.get_value(section, key, "")).split(","):
		var e := entry.strip_edges()
		if e != "":
			out.append(e)
	return out


func _version() -> String:
	return str(ProjectSettings.get_setting(VERSION_SETTING, ""))


## Every file below [param dir] with one of [param extensions], skipping SKIPPED_DIRS and (when
## [param skip_excluded]) the folders the export leaves out.
func _files(dir: String, extensions: Array[String], skip_excluded: bool) -> Array[String]:
	var out: Array[String] = []
	for entry in ResourceLoader.list_directory(dir):
		if entry.begins_with("."):
			continue
		if entry.ends_with("/"):
			var name := entry.trim_suffix("/")
			if name in SKIPPED_DIRS or (skip_excluded and dir == "res://" and name in EXCLUDED_DIRS):
				continue
			out.append_array(_files(dir.path_join(name) + "/", extensions, skip_excluded))
		elif entry.trim_suffix(".remap").get_extension() in extensions:
			out.append(dir + entry.trim_suffix(".remap"))
	return out


## The code lines of a script: no blank lines and no comment lines (a class named in a comment is no use).
func _code(text: String) -> String:
	var lines: Array[String] = []
	for line in text.split("\n"):
		var code := line.strip_edges()
		if code == "" or code.begins_with("#"):
			continue
		lines.append(code)
	return "\n".join(lines)


## Runs [param command] with [param args]; the exit code, -1 when the program cannot be started.
func _run(command: String, args: PackedStringArray, output: Array) -> int:
	return OS.execute(command, args, output, true)


func _skip_without_bash() -> bool:
	var out: Array = []
	return OS.get_name() == "Windows" or _run("bash", ["--version"], out) != 0


# --- The presets -----------------------------------------------------------------------------

func test_both_release_presets_exist() -> void:
	var cfg := _presets()
	var win := _preset_section(cfg, "Windows Desktop")
	var lin := _preset_section(cfg, "Linux")
	check(win != "", "a 'Windows Desktop' preset")
	check(lin != "", "a 'Linux' preset")
	if win == "" or lin == "":
		return
	check_eq(str(cfg.get_value(win, "platform")), "Windows Desktop", "Windows platform")
	check_eq(str(cfg.get_value(lin, "platform")), "Linux", "Linux platform")
	for section in [win, lin]:
		var options := str(section) + ".options"
		check_eq(str(cfg.get_value(options, "binary_format/architecture")), "x86_64", "%s is x86_64" % section)
		check_eq(cfg.get_value(options, "binary_format/embed_pck"), true, "%s embeds the PCK (one executable)" % section)
		check_eq(str(cfg.get_value(section, "export_filter")), "all_resources", "%s exports every resource" % section)
		check_eq(cfg.get_value(section, "runnable"), true, "%s is runnable" % section)
		check_eq(cfg.get_value(section, "encrypt_pck"), false, "%s: the PCK is not encrypted" % section)
		check_eq(str(cfg.get_value(options, "custom_template/release")), "", "%s uses the installed release template" % section)
	check_eq(cfg.get_value(win + ".options", "debug/export_console_wrapper"), 0, "no console wrapper next to the Windows exe")
	check_eq(cfg.get_sections().size(), 4, "exactly the two presets (and their options)")


func test_the_presets_filter_the_shipped_files() -> void:
	var cfg := _presets()
	for preset_name in ["Windows Desktop", "Linux"]:
		var section := _preset_section(cfg, preset_name)
		var include := _filter(cfg, section, "include_filter")
		var exclude := _filter(cfg, section, "exclude_filter")
		check("*.md" in include, "%s ships *.md (CREDITS.md and licence notices)" % preset_name)
		check("*.txt" in include, "%s ships *.txt (the font / icon licence texts)" % preset_name)
		for dir in EXCLUDED_DIRS:
			check("%s/*" % dir in exclude, "%s leaves out %s/*" % [preset_name, dir])
		check("CLAUDE.md" in exclude and "README.md" in exclude, "%s leaves out the repository's own .md files" % preset_name)
		check("CREDITS.md" not in exclude, "%s keeps CREDITS.md" % preset_name)


func test_the_export_paths_are_the_steam_content_layout() -> void:
	var cfg := _presets()
	check_eq(str(cfg.get_value(_preset_section(cfg, "Windows Desktop"), "export_path")), "build/steam/content/windows/SmartOnion.exe", "Windows content path")
	check_eq(str(cfg.get_value(_preset_section(cfg, "Linux"), "export_path")), "build/steam/content/linux/SmartOnion.x86_64", "Linux content path")


func test_the_windows_executable_metadata() -> void:
	var cfg := _presets()
	var options := _preset_section(cfg, "Windows Desktop") + ".options"
	check_eq(cfg.get_value(options, "application/modify_resources"), true, "the PE resources are edited (Godot's own editor, no rcedit)")
	check_eq(str(cfg.get_value(options, "application/product_name")), "SmartOnion", "product name")
	check_eq(str(cfg.get_value(options, "application/file_description")), "SmartOnion", "file description")
	check_eq(str(cfg.get_value(options, "application/file_version")), _version() + ".0", "file version = project version.0")
	check_eq(str(cfg.get_value(options, "application/product_version")), _version() + ".0", "product version = project version.0")
	check(str(cfg.get_value(options, "application/company_name", "")) != "", "a company name (a placeholder until the owner sets it)")
	check(str(cfg.get_value(options, "application/copyright", "")) != "", "a copyright line")
	check_eq(cfg.get_value(options, "codesign/enable"), false, "no code signing without a certificate")
	var icon := str(cfg.get_value(options, "application/icon", ""))
	check(icon.ends_with(".ico") and FileAccess.file_exists(icon), "the icon is an existing .ico: %s" % icon)


func test_the_windows_icon_has_every_size() -> void:
	var bytes := FileAccess.get_file_as_bytes("res://tools/build/SmartOnion.ico")
	check(bytes.size() > 6, "the icon file is there")
	if bytes.size() <= 6:
		return
	check_eq(bytes.decode_u16(0), 0, "ICO: reserved")
	check_eq(bytes.decode_u16(2), 1, "ICO: type 1 = icon")
	var sizes: Array[int] = []
	for i in bytes.decode_u16(4):
		var width := bytes.decode_u8(6 + i * 16)
		sizes.append(256 if width == 0 else width)
	for size in [16, 24, 32, 48, 64, 128, 256]:
		check(size in sizes, "the icon has a %d px image (has %s)" % [size, str(sizes)])


func test_the_game_icon_is_the_cut_out_art() -> void:
	check_eq(str(ProjectSettings.get_setting("application/config/icon")), GAME_ICON, "application/config/icon is the 256 px art")
	var texture := load(GAME_ICON) as Texture2D
	var image := texture.get_image() if texture != null else null
	check(image != null and not image.is_empty(), "the game icon loads")
	if image == null or image.is_empty():
		return
	check_eq(image.get_size(), Vector2i(256, 256), "256 x 256")
	check(image.detect_alpha() != Image.ALPHA_NONE, "the icon has an alpha channel")
	for corner in [Vector2i(0, 0), Vector2i(255, 0), Vector2i(0, 255), Vector2i(255, 255)]:
		check(image.get_pixelv(corner).a < 0.01, "the corner %s outside the ring is transparent" % str(corner))
	check(image.get_pixel(128, 128).a > 0.99, "the centre of the art is opaque")
	check(image.get_pixel(4, 128).a > 0.5, "the gold ring reaches the left edge")
	check(FileAccess.file_exists("res://tools/build/icon/smartonion_icon_source.png"), "the owner's source art is kept")
	check(FileAccess.file_exists("res://tools/build/icon/smartonion_icon_512.png"), "the 512 px cut-out master is kept")
	check(not FileAccess.file_exists("res://icon.svg"), "the placeholder icon.svg is gone (nothing references it)")


func test_release_exports_only() -> void:
	var script := FileAccess.get_file_as_string(EXPORT_SCRIPT)
	check("--export-release" in script, "export.sh exports the release template")
	check("--export-debug" not in script, "export.sh never builds a debug export")
	check("build/steam/content" in script, "export.sh writes the SteamPipe content layout")


func test_presets_are_committed_and_credentials_are_not() -> void:
	var ignored: Array[String] = []
	for line in FileAccess.get_file_as_string(GITIGNORE_PATH).split("\n"):
		ignored.append(line.strip_edges())
	check("export_presets.cfg" not in ignored, "export_presets.cfg is no longer ignored")
	check("export_credentials.cfg" in ignored, "export_credentials.cfg (signing secrets) stays ignored")
	check("/build/" in ignored, "build/ stays ignored")
	check("/addons/godotsteam/" in ignored, "the Valve libraries stay ignored")


# --- Version ---------------------------------------------------------------------------------

func test_the_project_has_a_version() -> void:
	var regex := RegEx.create_from_string("^[0-9]+\\.[0-9]+\\.[0-9]+$")
	check(regex.search(_version()) != null, "application/config/version looks like 1.2.3: '%s'" % _version())


func test_the_main_menu_shows_the_version() -> void:
	var menu := MainMenu.create()
	tree.root.add_child(menu)
	_nodes.append(menu)
	check_eq(MainMenu.version_text(), "v" + _version(), "the text is v<version>")
	check_eq(menu.version_label.text, "v" + _version(), "the label shows it")
	check(menu.version_label.is_visible_in_tree(), "the label is visible")
	check(menu.version_label.anchor_left == 1.0 and menu.version_label.anchor_top == 1.0, "bottom right corner")


func test_the_version_label_follows_the_setting() -> void:
	ProjectSettings.set_setting(VERSION_SETTING, "1.2.3")
	check_eq(MainMenu.version_text(), "v1.2.3", "another version")
	ProjectSettings.set_setting(VERSION_SETTING, "")
	check_eq(MainMenu.version_text(), "", "no version, no label text")


func test_the_scripts_pin_the_engine_version() -> void:
	var info := Engine.get_version_info()
	var triple := "%d.%d.%d" % [info["major"], info["minor"], info["patch"]]
	check('GODOT_VERSION="%s"' % triple in FileAccess.get_file_as_string(TEMPLATES_SCRIPT), "install_templates.sh pins Godot %s (update it, its sha512 and export.sh together)" % triple)
	check('EXPECTED_GODOT="%s.%s"' % [triple, info["status"]] in FileAccess.get_file_as_string(EXPORT_SCRIPT), "export.sh expects Godot %s.%s" % [triple, info["status"]])


# --- Nothing shipped reaches into the folders the export leaves out ------------------------------

func test_no_shipped_file_names_an_excluded_folder() -> void:
	var needle := RegEx.create_from_string("res://(%s)\\b" % "|".join(EXCLUDED_DIRS))
	var scanned := 0
	for path in _files("res://", SCANNED_EXTENSIONS, true):
		scanned += 1
		var m := needle.search(FileAccess.get_file_as_string(path))
		check(m == null, "%s loads from a folder the release build leaves out: %s" % [path, m.get_string() if m != null else ""])
	check(scanned > 500, "the scan saw the shipped sources (%d files)" % scanned)
	var project := FileAccess.get_file_as_string("res://project.godot")
	check(needle.search(project) == null, "project.godot names no excluded folder")


func test_no_shipped_script_uses_a_class_of_an_excluded_folder() -> void:
	var declared: Array[String] = []
	var class_re := RegEx.create_from_string("(?m)^class_name\\s+(\\w+)")
	for dir in EXCLUDED_DIRS:
		for path in _files("res://%s/" % dir, ["gd"], false):
			var m := class_re.search(FileAccess.get_file_as_string(path))
			if m != null:
				declared.append(m.get_string(1))
	check(declared.has("TestCase") and declared.has("FakeSteamSingleton"), "the scan found the test classes (%s)" % str(declared))
	var uses := RegEx.create_from_string("\\b(%s)\\b" % "|".join(declared))
	for path in _files("res://", ["gd"], true):
		var m := uses.search(_code(FileAccess.get_file_as_string(path)))
		check(m == null, "%s uses %s, a class the release build does not contain" % [path, m.get_string() if m != null else ""])


func test_credits_are_in_the_project_for_the_include_filter() -> void:
	var text := CreditsPage.read_markdown()
	check(text.begins_with("#") and text.length() > 200, "res://CREDITS.md is the credits page's text")
	check(FileAccess.file_exists("res://assets/fonts/OFL.txt") and FileAccess.file_exists("res://assets/icons/LICENSE.txt"), "the licence texts the *.txt filter ships")


# --- The scripts ---------------------------------------------------------------------------------

func test_the_build_scripts_parse() -> void:
	if _skip_without_bash():
		return
	for path in [EXPORT_SCRIPT, TEMPLATES_SCRIPT]:
		var real := ProjectSettings.globalize_path(path)
		var out: Array = []
		check_eq(_run("bash", ["-n", real], out), 0, "bash -n %s: %s" % [path, str(out)])
		check(FileAccess.get_unix_permissions(path) & EXEC_BITS != 0, "%s is executable" % path)
		check(FileAccess.get_file_as_string(path).contains("set -euo pipefail"), "%s uses set -euo pipefail" % path)


func test_the_build_scripts_pass_shellcheck_when_installed() -> void:
	if _skip_without_bash():
		return
	var out: Array = []
	if _run("shellcheck", ["--version"], out) != 0:
		return  # not installed (CI without it): bash -n above is the fallback
	for path in [EXPORT_SCRIPT, TEMPLATES_SCRIPT]:
		out = []
		check_eq(_run("shellcheck", ["-x", ProjectSettings.globalize_path(path)], out), 0, "shellcheck %s: %s" % [path, str(out)])


func test_the_scripts_print_their_help() -> void:
	if _skip_without_bash():
		return
	for path in [EXPORT_SCRIPT, TEMPLATES_SCRIPT]:
		var out: Array = []
		var code := _run("bash", [ProjectSettings.globalize_path(path), "--help"], out)
		check_eq(code, 0, "%s --help exits 0" % path)
		check("Usage" in str(out), "%s --help prints its usage" % path)


func test_the_icon_tool_prints_its_help() -> void:
	var out: Array = []
	if OS.execute("python3", ["-I", "-c", "import PIL"], out, true) != 0:
		return  # no python3 / Pillow here: the committed icons are what counts
	out = []
	check_eq(OS.execute("python3", ["-I", ProjectSettings.globalize_path(ICON_TOOL), "--help"], out, true), 0, "make_icon.py --help exits 0")
	check("usage" in str(out).to_lower(), "make_icon.py --help prints its usage: %s" % str(out))


func test_export_refuses_bad_arguments_before_doing_anything() -> void:
	if _skip_without_bash():
		return
	var script := ProjectSettings.globalize_path(EXPORT_SCRIPT)
	var out: Array = []
	check(_run("bash", [script, "--platform", "macos"], out) != 0, "an unknown platform is an error")
	check("--platform must be" in str(out), "...with a clear message: %s" % str(out))
	out = []
	check(_run("bash", [script, "--bogus"], out) != 0, "an unknown option is an error")
	check("unknown option" in str(out), "...with a clear message: %s" % str(out))
