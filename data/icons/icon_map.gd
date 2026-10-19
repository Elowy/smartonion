class_name IconMap
extends Resource
## Which picture an id gets (M7b, VIS-UI): icon id -> texture path, one dictionary per kind of
## content, so the content stays data. The pictures are white silhouettes on transparent from
## game-icons.net (CC BY 3.0, authors Lorc and Delapouite; assets/icons/<author>/<name>.svg, imported
## at 128 px with mipmaps); the UI tints them with the school / class / item colour
## ([GameIcons] draws them). An id that has no entry keeps its procedural glyph.
## The shipped map is data/icons/icon_map.tres.

## AbilityData.icon (falling back to AbilityData.id): "whirlwind" -> res://assets/icons/lorc/whirlwind.svg.
@export var abilities: Dictionary[StringName, String] = {}
## TalentData.id (every talent has its own picture).
@export var talents: Dictionary[StringName, String] = {}
## TalentTreeData.id.
@export var trees: Dictionary[StringName, String] = {}
## ConsumableData.icon_id.
@export var consumables: Dictionary[StringName, String] = {}
## ShrineData.icon_id.
@export var shrines: Dictionary[StringName, String] = {}
## A stat id (TalentData.icon of a talent that has no entry of its own, new content): &"crit", &"armor" ...
@export var stats: Dictionary[StringName, String] = {}
## A school (AbilityData.school): the picture of an ability whose icon id has no entry and no glyph rule.
@export var schools: Dictionary[StringName, String] = {}


## Every texture path of the map (a path used by several ids once).
func all_paths() -> Array[String]:
	var out: Array[String] = []
	for dict: Dictionary in [abilities, talents, trees, consumables, shrines, stats, schools]:
		for path: String in dict.values():
			if path not in out:
				out.append(path)
	return out
