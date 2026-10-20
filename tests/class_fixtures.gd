extends RefCounted
## A temporary class for tests (M8 P0): built from the Warrior's data and registered in Db for the
## length of a test – never shipped data ("zz_" id).
##
##   var classes := ClassFixtures.new()          # in a test; call classes.restore() in after_each
##   var cd := classes.add_class(&"hunter_hat", [&"wolf", &"boar"])

const FAKE_CLASS := &"zz_beastmaster"

var _saved_classes: Dictionary = {}
var _saved_class_ids: Array[StringName] = []
var _saved_trees: Dictionary = {}
var _saved_talents: Dictionary = {}
var _saved := false


## Registers the fixture class (Warrior data, [param headgear], [param companions]) in Db.classes /
## Db.class_ids and returns it.
func add_class(headgear: StringName = &"zz_unknown_headgear", companions: Array[StringName] = []) -> ClassData:
	save()
	var cd := Db.get_class_data(&"warrior").duplicate() as ClassData
	cd.id = FAKE_CLASS
	cd.display_name = "Beastmaster"
	cd.headgear = headgear
	cd.companion_choices = companions.duplicate()
	Db.classes[cd.id] = cd
	if cd.id not in Db.class_ids:
		Db.class_ids.append(cd.id)
	return cd


## Registers [param tree_data] and its talents in Db (restored by [method restore]).
func add_tree(tree_data: TalentTreeData) -> void:
	save()
	Db.talent_trees[tree_data.id] = tree_data
	for t in tree_data.talents:
		Db.talents[t.id] = t


## Remembers Db's classes and talents (the first call of a test; add_class / add_tree do it).
func save() -> void:
	if _saved:
		return
	_saved = true
	_saved_classes = Db.classes.duplicate()
	_saved_class_ids = Db.class_ids.duplicate()
	_saved_trees = Db.talent_trees.duplicate()
	_saved_talents = Db.talents.duplicate()


## Db's classes, class ids, talent trees and talents as they were.
func restore() -> void:
	if not _saved:
		return
	_saved = false
	Db.classes.assign(_saved_classes)
	Db.class_ids.assign(_saved_class_ids)
	Db.talent_trees.assign(_saved_trees)
	Db.talents.assign(_saved_talents)
