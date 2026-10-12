extends TestCase
## Tier sets (GDD 5.5 / 5.2, M5 SETS, architecture §2.4): the content (5 sets x 5 Epic pieces,
## bonuses in the vocabulary), Equipment.set_counts / SetBonuses (counts, effects_for at 0 / 2 /
## 4 / 5 pieces, active_count, describe, bonus_change), the entries reaching the bonus engine
## through Player.apply_equipment, and the generator's set roll (rates, classes, slots, waves,
## rng draws).

const Fakes := preload("res://tests/player_fakes.gd")

const SET_IDS: Dictionary[StringName, StringName] = {
	&"warrior": &"battlegear_of_fury", &"mage": &"regalia_of_the_arcane",
	&"paladin": &"dawnforged_plate", &"rogue": &"shadowstitch_garb", &"warlock": &"felfire_raiment",
}
const SET_NAMES: Dictionary[StringName, String] = {
	&"battlegear_of_fury": "Battlegear of Fury", &"regalia_of_the_arcane": "Regalia of the Arcane",
	&"dawnforged_plate": "Dawnforged Plate", &"shadowstitch_garb": "Shadowstitch Garb",
	&"felfire_raiment": "Felfire Raiment",
}
## Piece slot suffix (set_<class>_<slot>) -> slot type, in SetData.piece_ids order.
const PIECE_SLOTS: Dictionary[String, int] = {
	"head": Items.SlotType.HEAD, "shoulders": Items.SlotType.SHOULDERS, "chest": Items.SlotType.CHEST,
	"hands": Items.SlotType.HANDS, "legs": Items.SlotType.LEGS,
}
const LOOT := ItemGenerator.Source.LOOT
const SHOP := ItemGenerator.Source.SHOP

var world: Node3D
var nodes: Array[Node] = []
## Db.sets before a test injected a fixture (restored in after_each).
var _saved_sets: Dictionary = {}


func before_each() -> void:
	RunState.start_run(1, 31)


func after_each() -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.free()
	nodes.clear()
	Fakes.free_world(world)
	world = null
	if not _saved_sets.is_empty():
		Db.sets.assign(_saved_sets)
		_saved_sets = {}


# --- Helpers -----------------------------------------------------------------------------------

## A set piece item of [param class_id] for [param slot] ("head" ...), wave 8.
static func piece(class_id: StringName, slot: String, wave: int = 8) -> ItemInstance:
	var rng := RandomNumberGenerator.new()
	return ItemGenerator.from_unique(Db.get_unique(StringName("set_%s_%s" % [class_id, slot])), wave, false, rng)


## Equipment of [param class_id] wearing the pieces [param slots] (direct slot writes).
static func wearing(class_id: StringName, slots: Array[String]) -> Equipment:
	var eq := Equipment.new(Db.get_class_data(class_id))
	for s in slots:
		var it := piece(class_id, s)
		eq.slots[Items.equip_slots_for(it.slot_type)[0]] = it
	return eq


func _player(class_id: StringName) -> Player:
	if world == null:
		world = Fakes.make_world(tree)
	return Fakes.spawn_player(world, 0, class_id)


func _wear(p: Player, it: ItemInstance) -> void:
	p.equipment.add_to_backpack(it)
	check(p.equipment.equip(it), "equip %s" % it.display_name)


## Every effect entry of the bonus of [param set_id] for [param pieces].
static func bonus_effects(set_id: StringName, pieces: int) -> Array:
	for b in Db.get_set(set_id).bonuses:
		if int(b["pieces"]) == pieces:
			return b["effects"]
	return []


# --- Content -----------------------------------------------------------------------------------

func test_five_sets_one_per_class() -> void:
	check_eq(Db.sets.size(), 5, "five tier sets")
	for class_id in SET_IDS:
		var data := Db.set_for_class(class_id)
		check(data != null, "%s has a set" % class_id)
		if data == null:
			continue
		check_eq(data.id, SET_IDS[class_id], "%s set id" % class_id)
		check_eq(data.display_name, SET_NAMES[data.id], "final set name (Q22)")
		check_eq(data.class_id, class_id, "set class")
		check(Db.get_set(data.id) == data, "Db.get_set")


func test_five_epic_class_pieces_per_set() -> void:
	for class_id in SET_IDS:
		var data := Db.get_set(SET_IDS[class_id])
		var cls := Db.get_class_data(class_id)
		var expected: Array[StringName] = []
		for s in PIECE_SLOTS:
			expected.append(StringName("set_%s_%s" % [class_id, s]))
		check_eq(data.piece_ids, expected, "%s: piece ids Head .. Legs" % class_id)
		for s in PIECE_SLOTS:
			var id := StringName("set_%s_%s" % [class_id, s])
			var u := Db.get_unique(id)
			check(u != null, "%s exists" % id)
			if u == null:
				continue
			check_eq(u.id, id, "%s: id" % id)
			check(u.display_name != "" and u.flavor != "", "%s: name and flavor" % id)
			check_eq(u.slot_type, PIECE_SLOTS[s], "%s: slot" % id)
			check_eq(u.armor_type, int(cls.armor_type), "%s: the class's armour type" % id)
			check_eq(u.rarity, Items.Rarity.EPIC, "%s: Epic" % id)
			check_eq(u.class_restriction, class_id, "%s: class-restricted" % id)
			check_eq(u.set_id, data.id, "%s: set id" % id)
			check(u.weapon == null and u.unique_effect == &"", "%s: no weapon / unique effect" % id)
			check_eq(u.sources, [&"shop", &"loot", &"elite", &"goblin", &"boss"] as Array[StringName], "%s: sources" % id)
			check_eq(u.min_wave, 6, "%s: from wave 6" % id)
			check_eq(u.weight, 0.0, "%s: weight 0 (only the set roll picks it)" % id)
			check(ItemGenerator.unique_usable_by(u, cls), "%s: usable by its class" % id)
			for other in Db.class_ids:
				if other != class_id:
					check(not ItemGenerator.unique_usable_by(u, Db.get_class_data(other)), "%s: not for %s" % [id, other])


func test_piece_stats_are_primary_stamina_and_one_secondary_on_the_epic_budget() -> void:
	for class_id in SET_IDS:
		var primary := Db.get_class_data(class_id).primary_stat
		for s in PIECE_SLOTS:
			var u := Db.get_unique(StringName("set_%s_%s" % [class_id, s]))
			check_eq(u.stats.size(), 3, "%s: three stats" % u.id)
			check(u.stats.get(primary, 0.0) > 0.0, "%s: primary stat" % u.id)
			check(u.stats.get(Stats.STAMINA, 0.0) > 0.0, "%s: Stamina" % u.id)
			var secondaries := 0
			for stat in u.stats:
				if stat in ItemGenerator.SECONDARY_STATS:
					secondaries += 1
			check_eq(secondaries, 1, "%s: one secondary stat" % u.id)
			var budget := ItemGenerator.RARITY_BUDGET[Items.Rarity.EPIC] * ItemGenerator.slot_multiplier(u.slot_type)
			check_near(ItemGenerator.stat_cost(u.stats), budget, 0.5, "%s: Epic budget" % u.id)


func test_every_set_piece_belongs_to_its_set() -> void:
	var pieces := 0
	for id in Db.uniques:
		var u := Db.uniques[id]
		if u.set_id == &"":
			check(not String(id).begins_with("set_"), "%s: set_ ids are set pieces" % id)
			continue
		pieces += 1
		var data := Db.get_set(u.set_id)
		check(data != null and id in data.piece_ids, "%s is listed by %s" % [id, u.set_id])
		check(data != null and data.class_id == u.class_restriction, "%s: the set's class" % id)
	check_eq(pieces, 25, "25 set pieces")


func test_bonuses_are_2_and_4_pieces_in_the_vocabulary() -> void:
	for class_id in SET_IDS:
		var data := Db.get_set(SET_IDS[class_id])
		var thresholds: Array[int] = []
		for b in data.bonuses:
			thresholds.append(int(b["pieces"]))
			check(str(b.get("text", "")) != "", "%s: bonus text" % data.id)
			check(not (b["effects"] as Array).is_empty(), "%s: bonus effects" % data.id)
			for e: Dictionary in b["effects"]:
				check_eq(BonusVocabulary.validate(e, class_id), "", "%s %d-piece: %s" % [data.id, b["pieces"], e])
		check_eq(thresholds, [2, 4] as Array[int], "%s: 2- and 4-piece bonuses, no 5-piece" % data.id)
	# As handed to the engine (rank / id / label added) they still validate.
	var eq := wearing(&"mage", ["head", "shoulders", "chest", "hands"])
	for e in SetBonuses.effects_for(eq):
		check_eq(BonusVocabulary.validate(e, &"mage"), "", "handed-over entry %s" % e)


func test_bonus_numbers_follow_the_design_table() -> void:
	check_eq(bonus_effects(&"battlegear_of_fury", 2), [{"kind": "stats", "stats": {"resource_regen": 10.0}}], "Fury 2: +10% Rage generation")
	check_eq(bonus_effects(&"battlegear_of_fury", 4),
		[{"kind": "ability", "match": {"id": "whirlwind"}, "mods": {"free_chance_add": 30.0}}], "Fury 4: free Whirlwind 30%")
	check_eq(bonus_effects(&"regalia_of_the_arcane", 2), [{"kind": "stats", "stats": {"haste": 10.0}}], "Regalia 2: +10% Haste")
	check_eq(bonus_effects(&"dawnforged_plate", 2), [{"kind": "stats", "stats": {"armor": 3.0}}], "Dawnforged 2: +3 Armor")
	check_eq(bonus_effects(&"dawnforged_plate", 4),
		[{"kind": "ability", "match": {"id": "word_of_glory"}, "mods": {"heal_all": true, "heal_max_hp_pct_add": 10.0}}],
		"Dawnforged 4: Word of Glory heals all, +10% of Max HP")
	check_eq(bonus_effects(&"shadowstitch_garb", 2), [{"kind": "stats", "stats": {"crit": 5.0}}], "Shadowstitch 2: +5% crit")
	check_eq(bonus_effects(&"shadowstitch_garb", 4), [{"kind": "proc", "proc": {"trigger": "on_cast", "ability": "vanish",
		"effect": "buff", "stats": {"crit_damage": 50.0}, "duration": 4.0}}], "Shadowstitch 4: Vanish +50% crit damage 4 s")
	check_eq(bonus_effects(&"felfire_raiment", 2), [{"kind": "damage", "pct": 10.0, "source": "pet"}], "Felfire 2: +10% pet damage")
	check_eq(bonus_effects(&"felfire_raiment", 4),
		[{"kind": "ability", "match": {"id": "rain_of_fire"}, "mods": {"free_chance_add": 20.0}}], "Felfire 4: free Rain of Fire 20%")


func test_regalia_4_piece_proc_has_a_6_second_icd() -> void:
	var effects := bonus_effects(&"regalia_of_the_arcane", 4)
	check_eq(effects.size(), 1, "one entry")
	var p: Dictionary = effects[0]["proc"]
	check_eq(p, {"trigger": "on_cast", "ability": "blink", "effect": "buff", "stats": {"damage_pct": 30.0},
		"duration": 3.0, "icd": 6.0}, "Blink: +30% damage for 3 s, at most every 6 s (judge B3)")


# --- Counting and bonuses ----------------------------------------------------------------------

func test_counts_distinct_pieces_per_set() -> void:
	var eq := Equipment.new(Db.get_class_data(&"warrior"))
	check(SetBonuses.counts(eq).is_empty() and SetBonuses.counts(null).is_empty(), "nothing worn")
	eq.equip_starting_weapons()
	check(eq.set_counts().is_empty(), "weapons are no set pieces")
	eq = wearing(&"warrior", ["head", "legs"])
	check_eq(eq.set_counts(), {&"battlegear_of_fury": 2} as Dictionary[StringName, int], "two pieces")
	check_eq(SetBonuses.counts(eq), eq.set_counts(), "SetBonuses.counts = Equipment.set_counts")
	var head := piece(&"warrior", "head")
	var copy := piece(&"warrior", "head")
	var mage_hands := piece(&"mage", "hands")
	var plain := ItemInstance.new()
	check_eq(Equipment.count_sets([head, copy, mage_hands, plain, null] as Array[ItemInstance]),
		{&"battlegear_of_fury": 1, &"regalia_of_the_arcane": 1} as Dictionary[StringName, int], "a duplicate counts once")


func test_effects_for_at_0_2_4_and_5_pieces() -> void:
	check(SetBonuses.effects_for(null).is_empty(), "no equipment")
	check(SetBonuses.effects_for(wearing(&"warrior", [])).is_empty(), "0 pieces")
	check(SetBonuses.effects_for(wearing(&"warrior", ["head"])).is_empty(), "1 piece: nothing yet")
	check_eq(SetBonuses.active_count(wearing(&"warrior", ["head"])), 0, "1 piece: no bonus")
	var two := SetBonuses.effects_for(wearing(&"warrior", ["head", "hands"]))
	check_eq(two, [{"kind": "stats", "stats": {"resource_regen": 10.0}, "rank": 1, "id": "battlegear_of_fury:2",
		"label": "Battlegear of Fury"}], "2 pieces: the 2-piece bonus, rank 1, id <set>:2, set name label")
	check_eq(SetBonuses.active_count(wearing(&"warrior", ["head", "hands"])), 1, "2 pieces: 1 bonus")
	check_eq(SetBonuses.effects_for(wearing(&"warrior", ["head", "hands", "legs"])), two, "3 pieces: still the 2-piece")
	var four := SetBonuses.effects_for(wearing(&"warrior", ["head", "shoulders", "hands", "legs"]))
	check_eq(four.size(), 2, "4 pieces: 2-piece + 4-piece")
	check_eq(four[0], two[0], "the 2-piece bonus stays")
	check_eq(four[1], {"kind": "ability", "match": {"id": "whirlwind"}, "mods": {"free_chance_add": 30.0}, "rank": 1,
		"id": "battlegear_of_fury:4", "label": "Battlegear of Fury"}, "the 4-piece bonus")
	var all := wearing(&"warrior", ["head", "shoulders", "chest", "hands", "legs"])
	check_eq(SetBonuses.effects_for(all), four, "5 pieces: no 5-piece bonus")
	check_eq(SetBonuses.active_count(all), 2, "5 pieces: 2 bonuses")
	# Copies: changing a handed-over entry leaves the data alone.
	var handed := SetBonuses.effects_for(all)
	(handed[0]["stats"] as Dictionary)["resource_regen"] = 99.0
	check_eq(bonus_effects(&"battlegear_of_fury", 2)[0]["stats"]["resource_regen"], 10.0, "deep copies")


func test_unknown_sets_give_no_bonus() -> void:
	var eq := Equipment.new(Db.get_class_data(&"warrior"))
	for slot in [Items.EquipSlot.HEAD, Items.EquipSlot.CHEST]:
		var it := ItemInstance.new()
		it.source_id = StringName("zz_%d" % slot)
		it.set_id = &"zz_no_such_set"
		eq.slots[slot] = it
	check_eq(eq.set_counts(), {&"zz_no_such_set": 2} as Dictionary[StringName, int], "counted")
	check(SetBonuses.effects_for(eq).is_empty(), "but no SetData -> no entries")
	check_eq(SetBonuses.active_count(eq), 0, "and no active bonus")
	check(SetBonuses.describe(eq.get_item(Items.EquipSlot.HEAD), eq).is_empty(), "no tooltip rows")


func test_bonuses_of_two_sets_come_in_set_id_order() -> void:
	# A fixture second set for the warrior (Db.sets restored in after_each).
	_saved_sets = Db.sets.duplicate()
	var extra := SetData.new()
	extra.id = &"aa_test_set"
	extra.display_name = "Test Set"
	extra.class_id = &"warrior"
	extra.bonuses = [{"pieces": 2, "text": "+1 Armor.", "effects": [{"kind": "stats", "stats": {"armor": 1.0}}]}]
	Db.sets[extra.id] = extra
	var eq := wearing(&"warrior", ["head", "chest"])
	for slot in [Items.EquipSlot.WRIST, Items.EquipSlot.WAIST]:
		var it := ItemInstance.new()
		it.source_id = StringName("aa_piece_%d" % slot)
		it.set_id = extra.id
		eq.slots[slot] = it
	var ids: Array[String] = []
	for e in SetBonuses.effects_for(eq):
		ids.append(str(e["id"]))
	check_eq(ids, ["aa_test_set:2", "battlegear_of_fury:2"] as Array[String], "sets by id")
	check_eq(SetBonuses.active_count(eq), 2, "one bonus each")


func test_describe_rows_with_and_without_equipment() -> void:
	var head := piece(&"rogue", "head")
	check(SetBonuses.describe(null, null).is_empty(), "no item")
	check(SetBonuses.describe(ItemInstance.from_weapon(Db.get_weapon(&"dagger")), null).is_empty(), "not a set piece")
	var loose := SetBonuses.describe(head, null)
	check_eq(loose.size(), 1 + 5 + 2, "header, five pieces, two bonuses")
	check_eq(loose[0], {"kind": SetBonuses.ROW_HEADER, "text": "Shadowstitch Garb (5 pieces)", "active": true}, "no equipment: (5 pieces)")
	var names: Array[String] = []
	for i in range(1, 6):
		names.append(str(loose[i]["text"]))
		check(loose[i]["kind"] == SetBonuses.ROW_PIECE and not loose[i]["active"], "piece row %d, not worn" % i)
	check_eq(names, ["Shadowstitch Hood", "Shadowstitch Spaulders", "Shadowstitch Tunic", "Shadowstitch Gloves",
		"Shadowstitch Leggings"] as Array[String], "the five piece names in slot order")
	var slot_names: Array[String] = []
	for i in range(1, 6):
		slot_names.append(str(loose[i].get("slot", "")))
	check_eq(slot_names, ["Head", "Shoulders", "Chest", "Hands", "Legs"] as Array[String],
		"and their slot names (the tooltip's compact block)")
	check_eq(loose[6], {"kind": SetBonuses.ROW_BONUS, "text": "(2) Set: Increases your critical strike chance by 5%.", "active": false}, "2-piece row")
	check_eq(str(loose[7]["text"]), "(4) Set: Vanish increases your critical strike damage by 50% for 4 sec.", "4-piece row")
	var eq := wearing(&"rogue", ["head", "chest"])
	var worn := SetBonuses.describe(head, eq)
	check_eq(worn[0]["text"], "Shadowstitch Garb (2/5)", "worn count")
	var active: Array[bool] = []
	for row in worn:
		active.append(bool(row["active"]))
	check_eq(active, [true, true, false, true, false, false, true, false] as Array[bool], "worn pieces and the 2-piece bonus active")
	# Another class looks at it: nothing worn.
	check_eq(SetBonuses.describe(head, wearing(&"mage", ["head"]))[0]["text"], "Shadowstitch Garb (0/5)", "0/5 for a mage")


func test_bonus_change_counts_thresholds() -> void:
	var eq := wearing(&"paladin", ["head"])
	var chest := piece(&"paladin", "chest")
	check_eq(SetBonuses.bonus_change(chest, [] as Array[ItemInstance], eq), 1, "2nd piece into an empty slot: +1")
	var plain_chest := ItemInstance.new()
	plain_chest.slot_type = Items.SlotType.CHEST
	plain_chest.armor_type = ClassData.ArmorType.PLATE
	eq.slots[Items.EquipSlot.CHEST] = plain_chest
	check_eq(SetBonuses.bonus_change(chest, [plain_chest] as Array[ItemInstance], eq), 1, "replacing a plain chest: +1")
	eq.slots[Items.EquipSlot.CHEST] = chest
	check_eq(SetBonuses.bonus_change(plain_chest, [chest] as Array[ItemInstance], eq), -1, "a plain chest breaks the 2-piece: -1")
	check_eq(SetBonuses.bonus_change(piece(&"paladin", "chest"), [chest] as Array[ItemInstance], eq), 0, "a duplicate: 0")
	eq.slots[Items.EquipSlot.LEGS] = piece(&"paladin", "legs")
	check_eq(SetBonuses.bonus_change(plain_chest, [chest] as Array[ItemInstance], eq), 0, "3 -> 2 pieces: still active")
	check_eq(SetBonuses.bonus_change(piece(&"paladin", "hands"), [] as Array[ItemInstance], eq), 1, "4th piece: +1")
	check_eq(SetBonuses.bonus_change(piece(&"paladin", "hands"), [] as Array[ItemInstance], null), 0, "no equipment")


## The lookahead (ItemTooltip.set_lookahead): reachable backpack pieces count as worn on both
## sides (as many as the next threshold needs), so the item gets its own share of the bonus
## within reach.
func test_bonus_change_looks_ahead_to_reachable_pieces() -> void:
	var eq := wearing(&"paladin", ["head", "chest"])
	var legs := piece(&"paladin", "legs")
	var hands := piece(&"paladin", "hands")
	var none: Array[ItemInstance] = []
	check_eq(SetBonuses.bonus_change(legs, none, eq), 0, "3rd piece alone: no threshold")
	check_eq(SetBonuses.bonus_change(legs, none, eq, [hands] as Array[ItemInstance]), 1, "with the 4th piece reachable: +1")
	check_eq(SetBonuses.bonus_change(hands, none, eq, [legs] as Array[ItemInstance]), 1, "and the other way round")
	check_eq(SetBonuses.bonus_change(legs, none, eq, [legs, hands] as Array[ItemInstance]), 1, "the item itself in the lookahead is skipped")
	var head := eq.get_item(Items.EquipSlot.HEAD)
	check_eq(SetBonuses.bonus_change(piece(&"paladin", "head"), [head] as Array[ItemInstance], eq, [hands] as Array[ItemInstance]), 0,
		"a duplicate gains nothing from the backpack")
	var plain_legs := ItemInstance.new()
	plain_legs.slot_type = Items.SlotType.LEGS
	plain_legs.armor_type = ClassData.ArmorType.PLATE
	eq.slots[Items.EquipSlot.LEGS] = legs
	check_eq(SetBonuses.bonus_change(plain_legs, [legs] as Array[ItemInstance], eq), 0, "3 -> 2 pieces: still active")
	check_eq(SetBonuses.bonus_change(plain_legs, [legs] as Array[ItemInstance], eq, [hands] as Array[ItemInstance]), -1,
		"but it pushes the reachable 4-piece away: -1")


func test_pieces_to_next_bonus() -> void:
	var data := Db.get_set(&"dawnforged_plate")
	var got: Array[int] = []
	for n in 6:
		got.append(SetBonuses.pieces_to_next_bonus(data, n))
	check_eq(got, [2, 1, 0, 1, 0, 0] as Array[int], "2- and 4-piece thresholds; nothing above 4")
	check_eq(SetBonuses.pieces_to_next_bonus(null, 1), 0, "no set data")


## Review cases: only the pieces the next threshold still needs count, so spare pieces in the
## backpack never cancel the item out, and a waiting piece never stands in for a worn one.
func test_bonus_change_counts_only_the_pieces_the_next_threshold_needs() -> void:
	var none: Array[ItemInstance] = []
	# (A) 3 worn, legs + hands waiting: the legs are the 4th piece whatever else waits.
	var eq := wearing(&"paladin", ["head", "chest", "shoulders"])
	var legs := piece(&"paladin", "legs")
	var hands := piece(&"paladin", "hands")
	check_eq(SetBonuses.bonus_change(legs, none, eq, [hands] as Array[ItemInstance]), 1, "(A) the 4th piece: +1")
	check_eq(SetBonuses.bonus_change(hands, none, eq, [legs] as Array[ItemInstance]), 1, "(A) either of them")
	# (B) 2 worn, three pieces waiting: the 3rd piece needs one of the other two.
	eq = wearing(&"paladin", ["head", "chest"])
	var shoulders := piece(&"paladin", "shoulders")
	check_eq(SetBonuses.bonus_change(legs, none, eq, [hands, shoulders] as Array[ItemInstance]), 1, "(B) a 3rd piece: +1")
	check_eq(SetBonuses.bonus_change(shoulders, none, eq, [legs, hands] as Array[ItemInstance]), 1, "(B) any of them")
	# The 2nd piece completes the 2-piece by itself: +1 with one or two pieces waiting.
	eq = wearing(&"paladin", ["head"])
	check_eq(SetBonuses.bonus_change(legs, none, eq, [hands] as Array[ItemInstance]), 1, "2nd piece, one waiting: +1")
	check_eq(SetBonuses.bonus_change(legs, none, eq, [hands, shoulders] as Array[ItemInstance]), 1, "2nd piece, two waiting: +1")
	# (C) 4 worn after giving the legs away for a plain pair: the waiting legs do not count
	# as worn when a plain item would push out the hands (4 -> 3 breaks the 4-piece).
	eq = wearing(&"paladin", ["head", "chest", "shoulders", "hands"])
	var plain_legs := ItemInstance.new()
	plain_legs.slot_type = Items.SlotType.LEGS
	plain_legs.armor_type = ClassData.ArmorType.PLATE
	eq.slots[Items.EquipSlot.LEGS] = plain_legs
	var worn_hands := eq.get_item(Items.EquipSlot.HANDS)
	var plain_hands := ItemInstance.new()
	plain_hands.slot_type = Items.SlotType.HANDS
	plain_hands.armor_type = ClassData.ArmorType.PLATE
	check_eq(SetBonuses.bonus_change(plain_hands, [worn_hands] as Array[ItemInstance], eq, [legs] as Array[ItemInstance]), -1,
		"(C) breaks the worn 4-piece: -1")
	# A full set gives one piece away for free: 5 -> 4.
	eq.slots[Items.EquipSlot.LEGS] = legs
	check_eq(SetBonuses.bonus_change(plain_legs, [legs] as Array[ItemInstance], eq), 0, "5 -> 4 pieces: 0")
	# Pieces already worn (or a duplicate of one) never count twice.
	eq = wearing(&"paladin", ["head", "chest"])
	check_eq(SetBonuses.bonus_change(legs, none, eq, [piece(&"paladin", "head")] as Array[ItemInstance]), 0,
		"a duplicate of a worn piece in the backpack: no 4th piece")


# --- Player: entries reach the bonus engine ----------------------------------------------------

func test_apply_equipment_hands_the_entries_to_player_bonuses() -> void:
	var p := _player(&"warrior")
	check(p.bonuses.effects_of(PlayerBonuses.SOURCE_SETS).is_empty(), "no set bonus at the start")
	_wear(p, piece(&"warrior", "head"))
	check(p.bonuses.effects_of(PlayerBonuses.SOURCE_SETS).is_empty(), "one piece: none")
	_wear(p, piece(&"warrior", "legs"))
	check_eq(p.bonuses.effects_of(PlayerBonuses.SOURCE_SETS), SetBonuses.effects_for(p.equipment), "2 pieces: the 2-piece entries")
	check_eq(p.stats.get_source(&"set_bonus").get(Stats.RESOURCE_REGEN, 0.0), 10.0, "+10% Rage generation in the set_bonus source")
	var whirlwind := Db.get_ability(&"whirlwind")
	check(not p.abilities.params_for(whirlwind).has("free_chance"), "no free Whirlwind yet")
	_wear(p, piece(&"warrior", "chest"))
	_wear(p, piece(&"warrior", "hands"))
	check_eq(p.bonuses.effects_of(PlayerBonuses.SOURCE_SETS).size(), 2, "4 pieces: both bonuses")
	check_eq(float(p.abilities.params_for(whirlwind).get("free_chance", 0.0)), 30.0, "Whirlwind free_chance 30")
	check(p.equipment.unequip(Items.EquipSlot.HEAD), "take a piece off")
	check_eq(p.bonuses.effects_of(PlayerBonuses.SOURCE_SETS).size(), 1, "3 pieces: the 4-piece bonus is gone")
	check(not p.abilities.params_for(whirlwind).has("free_chance"), "params invalidated")
	check(p.equipment.unequip(Items.EquipSlot.LEGS) and p.equipment.unequip(Items.EquipSlot.CHEST), "two more off")
	check(p.bonuses.effects_of(PlayerBonuses.SOURCE_SETS).is_empty(), "1 piece: nothing")
	check_eq(p.stats.get_source(&"set_bonus").get(Stats.RESOURCE_REGEN, 0.0), 0.0, "the stat is gone")


func test_each_class_set_reaches_the_engine() -> void:
	var mage := _player(&"mage")
	for s in ["head", "shoulders", "chest", "hands"]:
		_wear(mage, piece(&"mage", s))
	check_eq(mage.stats.get_source(&"set_bonus").get(Stats.HASTE, 0.0), 10.0, "Regalia 2: Haste")
	var defs := mage.procs.extra_defs(PlayerBonuses.SOURCE_SETS)
	check_eq(defs.size(), 1, "Regalia 4: one proc handed to ProcSystem")
	check(defs.size() == 1 and float(defs[0]["icd"]) == 6.0 and str(defs[0]["ability"]) == "blink",
		"the Blink proc with its 6 s icd: %s" % [defs])
	check(defs.size() == 1 and str(defs[0]["label"]) == "Regalia of the Arcane" and str(defs[0]["id"]) == "regalia_of_the_arcane:4",
		"labelled with the set name, id <set>:4")
	var paladin := Fakes.spawn_player(world, 1, &"paladin", Vector3(6, 0, 0))
	for s in ["head", "shoulders", "chest", "legs"]:
		_wear(paladin, piece(&"paladin", s))
	check_eq(paladin.stats.get_source(&"set_bonus").get(Stats.ARMOR, 0.0), 3.0, "Dawnforged 2: Armor")
	check_eq(paladin.abilities.params_for(Db.get_ability(&"word_of_glory")).get("heal_all"), true, "Dawnforged 4: heal_all")
	check_eq(paladin.abilities.params_for(Db.get_ability(&"word_of_glory")).get("heal_max_hp_pct"), 35.0,
		"Dawnforged 4: 25 + 10% of Max HP")
	var rogue := Fakes.spawn_player(world, 2, &"rogue", Vector3(12, 0, 0))
	for s in ["head", "shoulders", "hands", "legs"]:
		_wear(rogue, piece(&"rogue", s))
	check_eq(rogue.stats.get_source(&"set_bonus").get(Stats.CRIT, 0.0), 5.0, "Shadowstitch 2: crit")
	var rdefs := rogue.procs.extra_defs(PlayerBonuses.SOURCE_SETS)
	check(rdefs.size() == 1 and str(rdefs[0]["ability"]) == "vanish", "Shadowstitch 4: the Vanish proc")
	var warlock := Fakes.spawn_player(world, 3, &"warlock", Vector3(18, 0, 0))
	for s in ["chest", "shoulders", "hands", "legs"]:
		_wear(warlock, piece(&"warlock", s))
	check_near(warlock.bonuses.damage_mult(null, &"fire", &"pet"), 1.1, 0.0001, "Felfire 2: +10% pet damage")
	check_near(warlock.bonuses.damage_mult(null, &"fire", &"ability"), 1.0, 0.0001, "only pets")
	check_eq(float(warlock.abilities.params_for(Db.get_ability(&"rain_of_fire")).get("free_chance", 0.0)), 20.0, "Felfire 4: free Rain of Fire")


## Word of Glory Rank V "Light of Dawn" already heals every hero within 8 m; the Dawnforged
## 4-piece still pays off for that Paladin: every heal restores 10% more of Max HP.
func test_dawnforged_4_piece_still_helps_with_light_of_dawn() -> void:
	var paladin := _player(&"paladin")
	var wog := Db.get_ability(&"word_of_glory")
	var slot := paladin.abilities.slot_of(wog.id)
	check(slot >= 0, "Word of Glory is known")
	while paladin.abilities.rank_of(wog.id) < 5:
		check(paladin.abilities.rank_up(wog.id), "rank up")
	check(paladin.abilities.set_spec(wog.id, 0), "Light of Dawn chosen")
	var spec_only := paladin.abilities.params_for(wog)
	check(spec_only.get("heal_all") == true and float(spec_only.get("heal_max_hp_pct")) == 25.0, "the spec heals every hero, 25%")
	var ally := Fakes.spawn_player(world, 1, &"warrior", Vector3(3, 0, 0))
	var holy := paladin.abilities.get_resource(&"holy_power")
	ally.hp = 2.0
	holy.set_value(3.0)
	check(paladin.abilities.try_cast(slot), "cast without the set")
	var power := float(spec_only.get("power", 1.0))
	var heal_spec := ally.hp - 2.0
	check_near(heal_spec, (3.0 + ally.max_hp() * 0.25) * power, 0.001, "spec heal: flat + 25% of Max HP, x power")
	for s in ["head", "shoulders", "chest", "legs"]:
		_wear(paladin, piece(&"paladin", s))
	var with_set := paladin.abilities.params_for(wog)
	check(with_set.get("heal_all") == true, "still every hero")
	check_eq(float(with_set.get("heal_max_hp_pct")), 35.0, "the 4-piece adds 10% of Max HP")
	ally.hp = 2.0
	holy.set_value(3.0)
	check(paladin.abilities.try_cast(slot), "cast with the 4-piece")
	check_near(ally.hp - 2.0, (3.0 + ally.max_hp() * 0.35) * power, 0.001, "the heal grew by 10% of Max HP x power")
	check(ally.hp - 2.0 > heal_spec, "the set is worth something next to Light of Dawn")


# --- Generator: the set roll -------------------------------------------------------------------

## Set pieces among [param n] forced-Epic rolls of [param source] at [param wave].
func _set_rolls(source: ItemGenerator.Source, wave: int, n: int, options: Dictionary = {}, seed: int = 7) -> Array[ItemInstance]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var opts := options.duplicate()
	opts[&"rarity"] = Items.Rarity.EPIC
	var out: Array[ItemInstance] = []
	for i in n:
		var it := ItemGenerator.generate(source, wave, rng, opts)
		if it.set_id != &"":
			out.append(it)
	return out


func test_set_chance_per_source() -> void:
	check_near(ItemGenerator.set_chance(SHOP), 0.05, 0.0001, "shop 5%")
	for source in [LOOT, ItemGenerator.Source.ELITE, ItemGenerator.Source.GOBLIN, ItemGenerator.Source.BOSS]:
		check_near(ItemGenerator.set_chance(source), 0.15, 0.0001, "loot sources 3x: 15%")


func test_epic_rolls_become_set_pieces_at_the_documented_rates() -> void:
	var n := 4000
	var shop := _set_rolls(SHOP, 12, n).size()
	check_near(float(shop) / n, 0.05, 0.012, "shop: ~5%% of the Epics (%d / %d)" % [shop, n])
	var loot := _set_rolls(LOOT, 12, n).size()
	check_near(float(loot) / n, 0.15, 0.02, "loot: ~15%% of the Epics (%d / %d)" % [loot, n])
	var elite := _set_rolls(ItemGenerator.Source.ELITE, 12, 2000, {}, 9).size()
	check_near(float(elite) / 2000, 0.15, 0.025, "elite: ~15%% (%d / 2000)" % elite)
	# Rolled rarity too: only the Epics among them may be set pieces.
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var epics := 0
	var pieces := 0
	for i in 3000:
		var it := ItemGenerator.generate(LOOT, 20, rng)
		if it.set_id != &"":
			pieces += 1
			check_eq(it.rarity, Items.Rarity.EPIC, "set pieces are Epic")
		if it.rarity == Items.Rarity.EPIC:
			epics += 1
	check(epics > 500, "enough Epics (%d)" % epics)
	check_near(float(pieces) / epics, 0.15, 0.04, "~15%% of the rolled Epics (%d / %d)" % [pieces, epics])


func test_only_epic_rolls_and_only_from_wave_6() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for rarity in [Items.Rarity.COMMON, Items.Rarity.RARE, Items.Rarity.LEGENDARY]:
		for i in 300:
			check(ItemGenerator.generate(LOOT, 15, rng, {&"rarity": rarity}).set_id == &"", "no set piece at rarity %d" % rarity)
	check(_set_rolls(ItemGenerator.Source.GOBLIN, 5, 600).is_empty(), "goblin Epics before wave 6: no set piece")
	check(not _set_rolls(ItemGenerator.Source.GOBLIN, 6, 600).is_empty(), "from wave 6 they come")


func test_set_piece_items_are_hand_made_epics() -> void:
	var items := _set_rolls(LOOT, 17, 400, {&"team_classes": [Db.get_class_data(&"paladin")] as Array[ClassData]})
	check(not items.is_empty(), "some pieces")
	for it in items:
		var data := Db.get_unique(it.source_id)
		check(data != null and data.set_id == it.set_id, "%s: from the set's data" % it.display_name)
		check(it.unique and it.rarity == Items.Rarity.EPIC and it.looted, "%s: hand-made looted Epic" % it.display_name)
		check_eq(it.class_restriction, &"paladin", "%s: class" % it.display_name)
		check(it.enchants.is_empty(), "%s: no random enchants" % it.display_name)
		check(it.stats.get(Stats.STRENGTH, 0.0) > data.stats[Stats.STRENGTH], "%s: tier III + loot scaling" % it.display_name)
		check(it.stats.get(Stats.ARMOR, 0.0) > 0.0, "%s: implicit plate Armor" % it.display_name)
		check_eq(it.buy_price, ItemGenerator.price_for(Items.Rarity.EPIC, 17), "%s: Epic price" % it.display_name)


func test_the_piece_is_for_a_party_class() -> void:
	var team: Array[ClassData] = [Db.get_class_data(&"warrior"), Db.get_class_data(&"rogue")]
	var seen := {}
	for it in _set_rolls(LOOT, 12, 2500, {&"team_classes": team}):
		seen[it.class_restriction] = true
	check_eq(seen.keys().size(), 2, "both party classes get pieces: %s" % [seen.keys()])
	check(seen.has(&"warrior") and seen.has(&"rogue"), "only the party's classes")
	for it in _set_rolls(LOOT, 12, 800, {&"team_classes": [Db.get_class_data(&"mage")] as Array[ClassData]}):
		check_eq(it.class_restriction, &"mage", "solo mage")
	for it in _set_rolls(SHOP, 12, 2000, {&"usable_by": Db.get_class_data(&"warlock"), &"team_classes": team}):
		check_eq(it.class_restriction, &"warlock", "usable_by wins over the team")
	var biased := _set_rolls(SHOP, 12, 2000, {&"class_data": Db.get_class_data(&"paladin")})
	check(not biased.is_empty(), "biased shop rolls get pieces")
	for it in biased:
		check_eq(it.class_restriction, &"paladin", "the class bias")
	var anyone := {}
	for it in _set_rolls(LOOT, 12, 4000):
		anyone[it.class_restriction] = true
	check_eq(anyone.keys().size(), 5, "no team given: any class with a set")


func test_a_team_without_a_set_gets_no_piece() -> void:
	var nobody := ClassData.new()
	nobody.id = &"zz_test_class"
	nobody.armor_type = ClassData.ArmorType.PLATE
	check(_set_rolls(LOOT, 12, 600, {&"team_classes": [nobody] as Array[ClassData]}).is_empty(), "no set for that class")
	check(_set_rolls(LOOT, 12, 600, {&"usable_by": nobody}).is_empty(), "usable_by without a set")


func test_pieces_are_uniform_and_respect_a_forced_slot() -> void:
	var per_piece := {}
	var items := _set_rolls(LOOT, 12, 6000, {&"team_classes": [Db.get_class_data(&"rogue")] as Array[ClassData]})
	for it in items:
		per_piece[it.source_id] = per_piece.get(it.source_id, 0) + 1
	check_eq(per_piece.keys().size(), 5, "all five pieces drop")
	for id in per_piece:
		check_near(float(per_piece[id]) / items.size(), 0.2, 0.06, "%s ~1/5 (%d / %d)" % [id, per_piece[id], items.size()])
	for it in _set_rolls(LOOT, 12, 800, {&"slot_type": Items.SlotType.HANDS}):
		check_eq(it.slot_type, Items.SlotType.HANDS, "forced Hands -> a Hands piece")
	check(not _set_rolls(LOOT, 12, 800, {&"slot_type": Items.SlotType.HANDS}).is_empty(), "forced set slot still rolls")
	check(_set_rolls(LOOT, 12, 800, {&"slot_type": Items.SlotType.RING}).is_empty(), "rings: never")


func test_set_roll_draws_are_documented() -> void:
	# No draw at all for a forced non-set slot.
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var state := rng.state
	check(ItemGenerator._roll_set_piece(LOOT, 12, Items.SlotType.RING, null, [], rng) == null, "ring")
	check_eq(rng.state, state, "no draw for a non-set slot")
	# A miss: exactly one randf.
	var miss_seed := _seed_where(func(r: RandomNumberGenerator) -> bool: return r.randf() >= 0.15)
	rng.seed = miss_seed
	check(ItemGenerator._roll_set_piece(LOOT, 12, -1, null, [], rng) == null, "miss")
	var probe := RandomNumberGenerator.new()
	probe.seed = miss_seed
	probe.randf()
	check_eq(rng.state, probe.state, "a miss draws once")
	# A hit for one fitting class: chance + piece (no class draw).
	var hit_seed := _seed_where(func(r: RandomNumberGenerator) -> bool: return r.randf() < 0.15)
	rng.seed = hit_seed
	var team: Array[ClassData] = [Db.get_class_data(&"mage")]
	var got := ItemGenerator._roll_set_piece(LOOT, 12, -1, null, team, rng)
	probe.seed = hit_seed
	probe.randf()
	var index := probe.randi_range(0, 4)
	check(got != null and got.id == Db.get_set(&"regalia_of_the_arcane").piece_ids[index], "the piece of the second draw")
	check_eq(rng.state, probe.state, "hit, one class: chance + piece")
	# Two classes: chance + class + piece.
	rng.seed = hit_seed
	team = [Db.get_class_data(&"mage"), Db.get_class_data(&"warrior")]
	got = ItemGenerator._roll_set_piece(LOOT, 12, -1, null, team, rng)
	probe.seed = hit_seed
	probe.randf()
	var cls := team[probe.randi_range(0, 1)]
	index = probe.randi_range(0, 4)
	check(got != null and got.id == Db.set_for_class(cls.id).piece_ids[index], "class then piece")
	check_eq(rng.state, probe.state, "hit, two classes: three draws")
	# A forced slot leaves one piece: chance only.
	rng.seed = hit_seed
	got = ItemGenerator._roll_set_piece(LOOT, 12, Items.SlotType.LEGS, Db.get_class_data(&"warlock"), [], rng)
	probe.seed = hit_seed
	probe.randf()
	check(got != null and got.id == &"set_warlock_legs", "the Legs piece")
	check_eq(rng.state, probe.state, "one candidate piece: no piece draw")


## The first seed whose fresh RandomNumberGenerator satisfies [param ok].
func _seed_where(ok: Callable) -> int:
	for s in range(1, 10000):
		var r := RandomNumberGenerator.new()
		r.seed = s
		if ok.call(r):
			return s
	return -1


func test_loot_drops_roll_pieces_for_the_party() -> void:
	PlayerManager.clear()
	PlayerManager.add_bot(&"mage", 0)
	PlayerManager.add_bot(&"rogue", 1)
	RunState.start_run(2, 404)
	RunState.set_wave(20)
	var seen := {}
	for i in 1500:
		var it := LootDrops.generate_item(null)
		if it.set_id != &"":
			seen[it.class_restriction] = true
	PlayerManager.clear()
	check(not seen.is_empty(), "loot drops roll set pieces")
	for c in seen:
		check(c in [&"mage", &"rogue"], "only for the party: %s" % c)
