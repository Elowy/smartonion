extends RefCounted
## Temporary tier sets for tests (M8 P0): a class-independent set (SetData.class_id empty) built in
## code and registered in Db for the length of a test – never shipped data. Pieces carry no class
## restriction and no primary stat (Stamina + two secondaries), like the real class-free sets.
##
##   var fixtures := SetFixtures.new()          # in a test; call fixtures.restore() in after_each
##   var set_data := fixtures.add_free_set(&"zz_free_mail", ClassData.ArmorType.MAIL)
##   fixtures.restore()                         # Db.sets / Db.uniques as they were

const SLOTS: Array[int] = [Items.SlotType.HEAD, Items.SlotType.SHOULDERS, Items.SlotType.CHEST,
	Items.SlotType.HANDS, Items.SlotType.LEGS]
const SLOT_NAMES: Array[String] = ["head", "shoulders", "chest", "hands", "legs"]

var _saved_sets: Dictionary = {}
var _saved_uniques: Dictionary = {}
var _saved := false


## Registers a class-independent test set [param id] of five [param armor] (ClassData.ArmorType)
## pieces "<id>_head" .. "<id>_legs" (Epic, from wave [param min_wave], set-roll only) and returns
## it. 2 pieces: +10 Stamina; 4 pieces: +5% weapon damage.
func add_free_set(id: StringName, armor: int, min_wave: int = 6) -> SetData:
	_save()
	var set_data := SetData.new()
	set_data.id = id
	set_data.display_name = "Test Set %s" % id
	set_data.class_id = &""
	for i in SLOTS.size():
		var piece := UniqueItemData.new()
		piece.id = StringName("%s_%s" % [id, SLOT_NAMES[i]])
		piece.display_name = "%s %s" % [set_data.display_name, SLOT_NAMES[i].capitalize()]
		piece.flavor = "A test piece."
		piece.slot_type = SLOTS[i] as Items.SlotType
		piece.armor_type = armor
		piece.rarity = Items.Rarity.EPIC
		piece.stats = {Stats.STAMINA: 6.0, Stats.CRIT: 3.0, Stats.HASTE: 3.0}
		piece.class_restriction = &""
		piece.set_id = id
		piece.sources = [&"shop", &"loot", &"elite", &"goblin", &"boss"]
		piece.min_wave = min_wave
		piece.weight = 0.0
		Db.uniques[piece.id] = piece
		set_data.piece_ids.append(piece.id)
	set_data.bonuses = [
		{"pieces": 2, "text": "+10 Stamina.", "effects": [{"kind": "stats", "stats": {"stamina": 10.0}}]},
		{"pieces": 4, "text": "Weapon hits deal 5% more damage.",
			"effects": [{"kind": "damage", "pct": 5.0, "source": "weapon"}]},
	]
	Db.sets[id] = set_data
	return set_data


## Puts Db.sets and Db.uniques back as they were before the first add_free_set.
func restore() -> void:
	if not _saved:
		return
	Db.sets.assign(_saved_sets)
	Db.uniques.assign(_saved_uniques)
	_saved = false


## Removes every class-independent set (and its pieces) from Db for this test: the world of
## "class sets only", whatever the shipped data holds.
func remove_free_sets() -> void:
	_save()
	for id in Db.sets.keys():
		var s: SetData = Db.sets[id]
		if s.class_id == &"":
			for piece_id in s.piece_ids:
				Db.uniques.erase(piece_id)
			Db.sets.erase(id)


func _save() -> void:
	if _saved:
		return
	_saved = true
	_saved_sets = Db.sets.duplicate()
	_saved_uniques = Db.uniques.duplicate()
