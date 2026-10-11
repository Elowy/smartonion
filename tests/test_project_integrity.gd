extends TestCase
## Catches parse errors anywhere in the project and broken scene / resource references.

const SKIP_DIRS: Array[String] = ["res://.godot", "res://.git", "res://addons"]


func test_all_scripts_compile() -> void:
	for path in _files("res://", ".gd"):
		var script := load(path) as GDScript
		check(script != null and script.can_instantiate(), "script does not compile: %s" % path)


func test_all_scenes_and_resources_load() -> void:
	for path in _files("res://", ".tscn") + _files("res://", ".tres"):
		check(load(path) != null, "failed to load: %s" % path)


func _files(dir: String, ext: String) -> Array[String]:
	var out: Array[String] = []
	if dir.trim_suffix("/") in SKIP_DIRS:
		return out
	for entry in ResourceLoader.list_directory(dir):
		if entry.begins_with("."):
			continue  # hidden (.godot, .git, .claude worktrees): Godot does not import them either
		if entry.ends_with("/"):
			out.append_array(_files(dir.path_join(entry.trim_suffix("/")) + "/", ext))
		elif entry.trim_suffix(".remap").ends_with(ext):
			out.append(dir + entry.trim_suffix(".remap"))
	return out
