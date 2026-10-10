extends Node
## Autoload "Db": loads all data resources from res://data/ at startup.
## Content is data-driven – adding a .tres file to the right folder adds it to the game.

const CLASS_DIR := "res://data/classes/"
const WEAPON_DIR := "res://data/weapons/"
const ENEMY_DIR := "res://data/enemies/"
## Lobby order of the launch classes; any extra class is appended alphabetically.
const CLASS_ORDER: Array[StringName] = [&"warrior", &"mage", &"paladin", &"rogue", &"warlock"]

var classes: Dictionary[StringName, ClassData] = {}
var weapons: Dictionary[StringName, WeaponData] = {}
var enemies: Dictionary[StringName, EnemyData] = {}
var class_ids: Array[StringName] = []


func _ready() -> void:
	reload()


func reload() -> void:
	classes.clear()
	weapons.clear()
	enemies.clear()
	for res in _load_dir(CLASS_DIR):
		if res is ClassData:
			classes[res.id] = res
	for res in _load_dir(WEAPON_DIR):
		if res is WeaponData:
			weapons[res.id] = res
	for res in _load_dir(ENEMY_DIR):
		if res is EnemyData:
			enemies[res.id] = res
	class_ids.clear()
	for id in CLASS_ORDER:
		if classes.has(id):
			class_ids.append(id)
	var extra: Array[StringName] = []
	for id in classes:
		if id not in class_ids:
			extra.append(id)
	extra.sort()
	class_ids.append_array(extra)


func get_class_data(id: StringName) -> ClassData:
	return classes.get(id)


func get_default_class() -> ClassData:
	return classes.get(class_ids[0]) if not class_ids.is_empty() else null


func get_weapon(id: StringName) -> WeaponData:
	return weapons.get(id)


func get_enemy(id: StringName) -> EnemyData:
	return enemies.get(id)


## Next / previous class id in lobby order (wraps around).
func cycle_class(current: StringName, step: int) -> StringName:
	if class_ids.is_empty():
		return current
	var i := class_ids.find(current)
	return class_ids[wrapi(i + step, 0, class_ids.size())]


func _load_dir(path: String) -> Array[Resource]:
	var out: Array[Resource] = []
	var files := ResourceLoader.list_directory(path)
	files.sort()
	for file in files:
		# Exported builds list "x.tres.remap"; ResourceLoader resolves the original name.
		var name := file.trim_suffix(".remap")
		if name.ends_with(".tres") or name.ends_with(".res"):
			var res := load(path + name)
			if res != null:
				out.append(res)
			else:
				push_error("Db: failed to load %s" % (path + name))
	return out
