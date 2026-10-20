extends TestCase
## M9 WARDROBE: the look ids and the collection (round trip with EquipLook), recording in real runs only, the cosmetics (data, the
## shapes, the ids granted elsewhere), dressing the hero's model without touching a stat, the cosmetic keys of a loadout, the
## Dye purchase, and the two controls (LookPicker, WardrobePage) under the dev profile and a real one.

const Fakes := preload("res://tests/player_fakes.gd")
const UiFakes := preload("res://tests/ui_fakes.gd")
const Items_ := preload("res://tests/test_ui_items.gd")

const HEAD := EquipLook.Slot.HEAD
const SHOULDERS := EquipLook.Slot.SHOULDERS
const CHEST := EquipLook.Slot.CHEST

var _tmp_path := "user://m9_wardrobe_test_%d.json" % OS.get_process_id()
var _saved_profile: Profile
var _saved_path := ""
var _saved_persist := false
var _saved_listeners: Array[Dictionary] = []
var _saved_achievements: Dictionary[StringName, AchievementData] = {}
var _nodes: Array[Node] = []
var _world: Node3D


func before_each() -> void:
	_saved_profile = Meta.profile
	_saved_path = Meta.path
	_saved_persist = Meta.persist
	_saved_listeners = Meta._listeners.duplicate()
	_saved_achievements = Db.achievements
	Db.achievements = {}  # (these tests count the Seeds they spend: the achievement Seeds are test_m9_achievements')
	Meta.save_count = 0
	Meta._pending_unlocks.clear()
	Meta._batching = false
	Wardrobe._run_new.clear()
	UiFakes.reset_players()
	RunState.start_run(1, 91)


func after_each() -> void:
	for i in range(_nodes.size() - 1, -1, -1):
		UiFakes.free_node(_nodes[i])
	_nodes.clear()
	if _world != null:
		Fakes.free_world(_world)
		_world = null
	Meta.profile = _saved_profile
	Meta.path = _saved_path
	Meta.persist = _saved_persist
	Meta._listeners = _saved_listeners
	Meta._pending_unlocks.clear()
	Meta._batching = false
	Db.achievements = _saved_achievements
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(_tmp_path + suffix):
			DirAccess.remove_absolute(_tmp_path + suffix)
	UiFakes.reset_players()
	PlayerManager.clear()
	EnemyGrid.mark_dirty()


# --- Helpers ------------------------------------------------------------------------------------

func _use_fresh() -> Profile:
	Meta.profile = Profile.fresh()
	Meta.persist = false
	Meta.path = ""
	return Meta.profile


func _use_file() -> Profile:
	Meta.profile = Profile.fresh()
	Meta.persist = true
	Meta.path = _tmp_path
	return Meta.profile


func _world_up() -> Node3D:
	if _world == null:
		_world = Fakes.make_world(tree)
	return _world


func _item(slot_type: Items.SlotType, armor_type: int, rarity: int = 0, wave: int = 1) -> ItemInstance:
	return Items_.armor("Test piece", slot_type, armor_type, rarity, {"stamina": 1}, wave)


func _unique_item(id: StringName, wave: int = 5) -> ItemInstance:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	return ItemGenerator.from_unique(Db.get_unique(id), wave, false, rng)


## A joined hero of [param class_id] with a real Player (slot.player set) in the world.
func _hero(class_id: StringName, index: int = 0, looks: Dictionary = {}, cosmetics: Dictionary = {}) -> Player:
	var slot := PlayerManager.join(ScriptedInput.new("wardrobe:%d" % index), Db.get_class_data(class_id))
	for k: StringName in looks:
		slot.looks[k] = looks[k]
	for k: StringName in cosmetics:
		slot.cosmetics[k] = cosmetics[k]
	var p := Player.create(slot)
	_world_up().add_child(p)
	slot.player = p
	return p


func _keys(list: Array[StringName]) -> Array[String]:
	var out: Array[String] = []
	for id in list:
		out.append(String(id))
	return out


func _human(key: String = "human") -> UiFakes.HumanInput:
	return UiFakes.HumanInput.new(key)


## One frame of a picker: poll the input, let the control read it.
func _feed(inp: UiFakes.HumanInput, picker: LookPicker) -> void:
	inp.poll(1.0 / 60.0)
	picker.process_input(inp)


func _tap(inp: UiFakes.HumanInput, picker: LookPicker, button: PlayerInput.Pad) -> void:
	inp.press(button)
	_feed(inp, picker)
	inp.release(button)
	_feed(inp, picker)


func _nudge(inp: UiFakes.HumanInput, picker: LookPicker, dir: Vector2) -> void:
	inp.move = dir
	_feed(inp, picker)
	inp.move = Vector2.ZERO
	_feed(inp, picker)


# --- Look ids -----------------------------------------------------------------------------------

func test_the_look_id_space_has_the_designed_shape() -> void:
	var ids := Wardrobe.all_look_ids()
	var generated := 0
	var sets := 0
	var uniques := 0
	var seen := {}
	for id in ids:
		check(not seen.has(id), "%s is listed once" % id)
		seen[id] = true
		match String(id).get_slice(".", 0):
			"g": generated += 1
			"s": sets += 1
			"u": uniques += 1
	check_eq(generated, 180, "generated: 3 slots x 4 armours x 3 tiers x 5 rarities (Artifact armour does not exist)")
	check_eq(sets, 36, "12 tier sets x 3 slots")
	check_eq(uniques, 40, "15 head + 11 shoulder + 14 chest uniques")
	check_eq(ids.size(), Wardrobe.total_count(), "the counter's total")
	check_eq(Wardrobe.look_ids_for_slot(&"head").size(), 87, "head")
	check_eq(Wardrobe.look_ids_for_slot(&"shoulders").size(), 83, "shoulders")
	check_eq(Wardrobe.look_ids_for_slot(&"chest").size(), 86, "chest")
	check_eq(Wardrobe.all_look_ids(true).size(), 292, "with the Artifact rarity the id space is the design's 292")
	check(Wardrobe.is_artifact_look(&"g.head.0.0.5") and not Wardrobe.is_artifact_look(&"g.head.0.0.4"), "only rarity 5 is Artifact")


func test_every_look_id_round_trips_with_equip_look() -> void:
	var mage := Db.get_class_data(&"mage")
	for id in Wardrobe.all_look_ids(true):
		var look := Wardrobe.look_from_id(id)
		check(look != null, "%s resolves" % id)
		if look == null:
			continue
		check_eq(Wardrobe.look_id(look), id, "%s survives the round trip" % id)
		check_eq(Wardrobe.slot_name(look.slot), Wardrobe.slot_of(id), "%s: the slot of the id is the look's" % id)
		var part := OnionArmor.part(look.slot, look, mage)
		check(part != null and (part.solid != null or part.cloth != null), "%s can be drawn" % id)
		check(Wardrobe.look_name(id) != "" and Wardrobe.look_name(id) != String(id), "%s has a name" % id)
		check(Wardrobe.look_detail(id) != "", "%s has a detail line" % id)


func test_items_become_look_ids() -> void:
	var rare := _item(Items.SlotType.HEAD, ClassData.ArmorType.PLATE, Items.Rarity.RARE, 17)
	check_eq(Wardrobe.look_id_of_item(rare), &"g.head.3.2.2", "a generated plate helm of wave 17: tier III, Rare")
	check_eq(Wardrobe.look_id_of_item(_item(Items.SlotType.SHOULDERS, ClassData.ArmorType.CLOTH, 0, 1)), &"g.shoulders.0.0.0", "cloth shoulders of wave 1")
	check_eq(Wardrobe.look_id_of_item(_item(Items.SlotType.CHEST, Items.NO_ARMOR, 1, 8)), &"g.chest.0.0.1", "no armour type counts as cloth")
	var set_piece := _unique_item(&"set_warrior_head")
	check_eq(Wardrobe.look_id_of_item(set_piece), &"s.head.battlegear_of_fury", "a tier set piece: the set, whatever the wave")
	check_eq(Wardrobe.look_id_of_item(_unique_item(&"set_warrior_head", 25)), &"s.head.battlegear_of_fury", "the same at wave 25")
	check_eq(Wardrobe.look_id_of_item(_unique_item(&"crown_of_ashes")), &"u.head.crown_of_ashes", "a hand-made unique")
	check_eq(Wardrobe.look_id_of_item(_unique_item(&"sunforged_breastplate", 3)), &"u.chest.sunforged_breastplate", "whatever its wave")
	var heirloom := _item(Items.SlotType.HEAD, ClassData.ArmorType.MAIL, Items.Rarity.EPIC, 1)
	heirloom.unique = true
	heirloom.source_id = &"heir_something_unknown"
	check_eq(Wardrobe.look_id_of_item(heirloom), &"g.head.2.0.3", "a unique the data does not know falls back to its generated look")
	var ghost := _item(Items.SlotType.HEAD, ClassData.ArmorType.CLOTH, 2, 1)
	ghost.set_id = &"no_such_set"
	check_eq(Wardrobe.look_id_of_item(ghost), &"g.head.0.0.2", "so does an unknown set")
	check_eq(Wardrobe.look_id_of_item(_item(Items.SlotType.WRIST, ClassData.ArmorType.PLATE)), &"", "wrists have no model")
	check_eq(Wardrobe.look_id_of_item(null), &"", "no item, no id")
	check_eq(Wardrobe.look_id_of_item(ItemInstance.from_weapon(Db.get_weapon(&"sword"))), &"", "weapons have their own models")
	check_eq(Wardrobe.look_id(null), &"", "no look, no id")


func test_ids_decode_to_the_looks_they_name() -> void:
	var warrior_set := Wardrobe.look_from_id(&"s.chest.battlegear_of_fury")
	check_eq(warrior_set.armor, ClassData.ArmorType.PLATE, "a class set wears its class's armour")
	check_eq(warrior_set.detail(), EquipLook.MAX_TIER, "and the richest detail")
	check(warrior_set.is_set() and warrior_set.slot == CHEST, "a set piece of the chest")
	check_eq(Wardrobe.look_from_id(&"s.head.mendweave_attire").armor, ClassData.ArmorType.CLOTH, "a class-independent set: the set's armour")
	var crown := Wardrobe.look_from_id(&"u.head.crown_of_ashes")
	check_eq(crown.unique_id, &"crown_of_ashes", "a unique keeps its id")
	check_eq(crown.rarity, Items.Rarity.LEGENDARY, "and its rarity")
	check_eq(crown.tier, EquipLook.MAX_TIER, "shown in the richest material")
	var bad: Array[StringName] = [&"", &"x", &"g.head", &"g.head.4.0.0", &"g.head.0.3.0", &"g.head.0.0.6", &"g.neck.0.0.0", &"g.head.-1.0.0", &"g.head.a.0.0",
			&"g.head.1.2", &"g.head.1.1.1.1", &"s.head.no_such_set", &"s.head", &"u.head.nobody", &"u.chest.crown_of_ashes", &"u.head.set_warrior_head", &"z.head.0.0.0"]
	for id in bad:
		check(Wardrobe.look_from_id(id) == null, "'%s' is not a look" % id)
		check_eq(Wardrobe.look_name(id), String(id), "'%s' is shown as it is" % id)
	check_eq(Wardrobe.slot_of(&"g.shoulders.1.1.1"), &"shoulders", "slot of an id")
	check_eq(Wardrobe.slot_of(&"junk"), &"", "no slot")


# --- Recording ----------------------------------------------------------------------------------

func test_nothing_is_recorded_in_an_automated_run() -> void:
	Meta.configure(&"", "", true)
	check(Meta.is_dev(), "the dev profile")
	var hero := _hero(&"warrior")
	hero.equipment.equip(_item(Items.SlotType.HEAD, ClassData.ArmorType.PLATE, Items.Rarity.RARE, 1))
	check(Wardrobe.record_worn_now().is_empty(), "nothing found")
	RunState.set_wave(2)  # the wave-start hook
	check(Meta.profile.unlocks.get(Profile.KIND_LOOK, {}).is_empty(), "no look recorded")
	check_eq(Meta.save_count, 0, "nothing saved")
	check(Wardrobe.collect([&"g.head.0.0.0"] as Array[StringName]).is_empty(), "collect refuses too")
	var report := RunReport.make([&"warrior"] as Array[StringName], true, {}, {}, [_hero_entry(&"warrior", [_equipped(Items.SlotType.HEAD, 3, 1, 2)])])
	check(not Meta.record_run(report)["recorded"], "the dev profile records no run")
	check(Meta.profile.unlocks.get(Profile.KIND_LOOK, {}).is_empty(), "and still no look")


func test_a_real_run_records_the_worn_visible_slots_at_a_wave_start() -> void:
	var profile := _use_fresh()
	var hero := _hero(&"warrior")
	hero.equipment.equip(_item(Items.SlotType.HEAD, ClassData.ArmorType.PLATE, Items.Rarity.RARE, 17))
	hero.equipment.equip(_item(Items.SlotType.CHEST, ClassData.ArmorType.PLATE, Items.Rarity.EPIC, 1))
	hero.equipment.equip(_item(Items.SlotType.WRIST, ClassData.ArmorType.PLATE, Items.Rarity.EPIC, 1))
	hero.equipment.equip(_item(Items.SlotType.LEGS, ClassData.ArmorType.PLATE, Items.Rarity.EPIC, 1))
	var added := Wardrobe.record_worn_now()
	check_eq(_keys(added), ["g.head.3.2.2", "g.chest.3.0.3"], "the helm and the breastplate, not the wrists or legs")
	check_eq(profile.unlocked_ids(Profile.KIND_LOOK).size(), 2, "the profile holds exactly those")
	check(Wardrobe.record_worn_now().is_empty(), "the same pieces are not new the second time")
	check_eq(_keys(Wardrobe.run_new_looks()), ["g.head.3.2.2", "g.chest.3.0.3"], "the run's list")
	# The wave-start signal does the same for a later piece.
	hero.equipment.equip(_item(Items.SlotType.SHOULDERS, ClassData.ArmorType.MAIL, Items.Rarity.UNCOMMON, 1))
	RunState.set_wave(2)
	check(profile.has_unlock(Profile.KIND_LOOK, &"g.shoulders.2.0.1"), "RunState.wave_changed records at a wave start")
	check_eq(Wardrobe.run_new_looks().size(), 3, "three looks this run")
	RunState.start_run(1, 5)
	check(Wardrobe.run_new_looks().is_empty(), "a new run starts the list again")


func test_two_heroes_and_several_looks_cost_one_save() -> void:
	var profile := _use_file()
	var a := _hero(&"warrior", 0)
	var b := _hero(&"mage", 1)
	a.equipment.equip(_item(Items.SlotType.HEAD, ClassData.ArmorType.PLATE, Items.Rarity.RARE, 1))
	a.equipment.equip(_item(Items.SlotType.CHEST, ClassData.ArmorType.PLATE, Items.Rarity.RARE, 1))
	b.equipment.equip(_item(Items.SlotType.HEAD, ClassData.ArmorType.CLOTH, Items.Rarity.EPIC, 1))
	b.equipment.equip(_item(Items.SlotType.SHOULDERS, ClassData.ArmorType.CLOTH, Items.Rarity.EPIC, 1))
	var saves := Meta.save_count
	check_eq(Wardrobe.record_worn_now().size(), 4, "four new looks")
	check_eq(Meta.save_count, saves + 1, "one save for all of them")
	check(Wardrobe.record_worn_now().is_empty(), "nothing new")
	check_eq(Meta.save_count, saves + 1, "and no save for nothing")
	var back := Profile.load_file(_tmp_path)
	check_eq(back.unlocked_ids(Profile.KIND_LOOK).size(), 4, "the file has them")
	check_eq(profile.unlocked_ids(Profile.KIND_LOOK).size(), 4, "so has the profile")


func _equipped(slot_type: Items.SlotType, armor: int, tier: int, rarity: int, set_id: String = "", unique_id: String = "") -> Dictionary:
	return {"source_id": "", "slot_type": int(slot_type), "equip_slot": 0, "armor_type": armor, "rarity": rarity, "wave": 1, "item_level": 1,
			"unique": unique_id != "", "set_id": set_id,
			"look": {"slot": EquipLook.slot_for_type(slot_type), "armor": armor, "tier": tier, "rarity": rarity, "set_id": set_id, "unique_id": unique_id}}


func _hero_entry(class_id: StringName, equipped: Array) -> Dictionary:
	return {"slot": 0, "class_id": String(class_id), "alive": true, "damage": 0.0, "healing": 0.0, "absorbed": 0.0, "taken": 0.0, "kills": 0,
			"bosses": 0, "revives": 0, "downs": 0, "need_wins": 0, "capstones": 0, "rank5": 0, "sets_active": 0, "companion": "", "equipped": equipped}


func test_the_run_end_records_what_the_report_says_in_the_single_save() -> void:
	var profile := _use_file()
	var heroes: Array[Dictionary] = [_hero_entry(&"warrior", [
		_equipped(Items.SlotType.HEAD, 3, 1, 2),
		_equipped(Items.SlotType.SHOULDERS, 3, 2, 3, "battlegear_of_fury", "set_warrior_shoulders"),
		_equipped(Items.SlotType.CHEST, 3, 0, 4, "", "breastplate_of_unbroken_anger"),
		{"source_id": "x", "slot_type": int(Items.SlotType.WRIST), "look": {}},
	])]
	var report := RunReport.make([&"warrior"] as Array[StringName], true, {}, {}, heroes)
	var saves := Meta.save_count
	var result := Meta.record_run(report)
	check(result["recorded"], "recorded")
	check(&"wardrobe" in (result["listeners"] as Array[StringName]), "the wardrobe listener ran")
	check_eq(_keys(result["new_looks"]), ["g.head.3.1.2", "s.shoulders.battlegear_of_fury", "u.chest.breastplate_of_unbroken_anger"], "three looks, not the wrist")
	check_eq(Meta.save_count, saves + 1, "one save")
	check_eq(int(result["looks_collected"]), 3, "the collected count")
	check(profile.has_unlock(Profile.KIND_LOOK, &"s.shoulders.battlegear_of_fury"), "in the profile")
	check(Profile.load_file(_tmp_path).has_unlock(Profile.KIND_LOOK, &"u.chest.breastplate_of_unbroken_anger"), "and in the file")
	var ids := Meta.listener_ids()
	check(ids.find(&"wardrobe") > ids.find(Meta.LISTENER_COUNTERS) and ids.find(&"wardrobe") < ids.find(Meta.LISTENER_ACHIEVEMENTS), "between the counters and the achievements")


func test_the_collected_counter_and_the_unlock_kind() -> void:
	var profile := _use_fresh()
	check_eq(Wardrobe.collected_count(), 0, "a new player has nothing")
	check(not Wardrobe.is_collected(&"g.head.0.0.0"), "not collected")
	profile.unlock(Profile.KIND_LOOK, &"g.head.0.0.0")
	profile.unlock(Profile.KIND_LOOK, &"u.head.crown_of_ashes")
	check_eq(Wardrobe.collected_count(), 2, "two")
	check_eq(_keys(Wardrobe.collected_for_slot(&"head")), ["g.head.0.0.0", "u.head.crown_of_ashes"], "in collection order")
	check(Wardrobe.collected_for_slot(&"chest").is_empty(), "none of the chest")
	Meta.profile = Profile.dev()
	check_eq(Wardrobe.collected_count(), Wardrobe.total_count(), "the dev profile has them all")
	Meta.profile = Profile.max_profile(Db.class_ids)
	check_eq(Wardrobe.collected_count(), Wardrobe.total_count(), "so has the max profile")


# --- Cosmetics ----------------------------------------------------------------------------------

func test_the_cosmetics_are_the_designed_29() -> void:
	check_eq(Db.cosmetics.size(), 29, "7 + 1 tabards... 8 tabards, 7 hats, 8 glows, 6 dyes")
	check_eq(Db.cosmetics_of_kind(CosmeticData.KIND_TABARD).size(), 8, "tabards")
	check_eq(Db.cosmetics_of_kind(CosmeticData.KIND_HAT).size(), 7, "hats")
	check_eq(Db.cosmetics_of_kind(CosmeticData.KIND_GLOW).size(), 8, "glows")
	check_eq(Db.cosmetics_of_kind(CosmeticData.KIND_DYE).size(), 6, "dyes")
	var names := {}
	for id in Db.cosmetics:
		var c := Db.cosmetics[id]
		check_eq(c.id, id, "id matches the key")
		check(c.kind in CosmeticData.KINDS, "%s has a kind" % id)
		check(c.display_name != "" and not names.has(c.display_name), "%s: a unique name" % id)
		names[c.display_name] = true
		if c.is_dye():
			check_eq(c.price, Wardrobe.DYE_PRICE, "%s costs 100 Seeds" % id)
			check(String(id).begins_with("dye_") and c.style == &"", "%s: a dye id and no shape" % id)
		else:
			check_eq(c.price, 0, "%s is not sold" % id)
			check(c.style != &"", "%s has a style" % id)
			check(String(id).begins_with("cos_"), "%s: a cosmetic id" % id)
	var dye_names: Array[String] = []
	for c in Db.cosmetics_of_kind(CosmeticData.KIND_DYE):
		dye_names.append(c.display_name)
	check_eq(dye_names, ["Rose Blush", "Gilded Gold", "Winter Blue", "Ember Orange", "Moss Green", "Charcoal Grey"] as Array[String], "the six dyes of the design")
	check_eq(Db.get_cosmetic(&"cos_gala_tabard").display_name, "Gala Tabard", "the achievement tabard")
	check_eq(Db.get_cosmetic(&"cos_salt_crystal_glow").display_name, "Salt Crystal Glow", "the achievement glow")


func test_every_cosmetic_id_granted_anywhere_resolves() -> void:
	var granted: Dictionary[StringName, StringName] = {}  # id -> the kind it must have
	for class_id in Db.class_ids:
		var path := Db.class_path(class_id)
		check(path != null, "%s has a level path" % class_id)
		if path == null:
			continue
		for entry in path.cosmetics:
			var id := StringName(str(entry["id"]))
			granted[id] = StringName(str(entry["slot"]))
			var c := Db.get_cosmetic(id)
			check(c != null, "%s (a level reward) exists" % id)
			if c != null:
				check_eq(c.display_name, str(entry["name"]), "%s: the name of the reward line" % id)
				check_eq(c.class_id, class_id, "%s: the class" % id)
		for slot in [&"tabard", &"hat", &"glow"]:
			check_eq(Wardrobe.level_of_cosmetic(Db.get_cosmetic(StringName("cos_%s_%s" % [class_id, slot]))), {&"tabard": 15, &"hat": 25, &"glow": 30}[slot],
					"%s %s: the level" % [class_id, slot])
	Db.achievements = _saved_achievements  # (the real achievements for this test)
	var from_achievements := 0
	for a in Db.achievement_list():
		for reward in a.rewards:
			if str(reward.get("kind", "")) == "cosmetic":
				from_achievements += 1
				var id := StringName(str(reward["id"]))
				granted[id] = &""
				check(Db.get_cosmetic(id) != null, "%s (reward of %s) exists" % [id, a.id])
	check(from_achievements >= 6, "the achievements grant cosmetics (%d)" % from_achievements)
	for id in granted:
		var c := Db.get_cosmetic(id)
		if c != null and granted[id] != &"":
			check_eq(c.kind, granted[id], "%s has the kind of its slot" % id)
	for id in [&"cos_gala_tabard", &"cos_salt_crystal_glow", &"dye_ember", &"dye_gilded", &"dye_moss", &"dye_charcoal"]:
		check(granted.has(id), "%s is granted by an achievement" % id)
	# Every cosmetic says how to get it.
	for id in Db.cosmetics:
		check(Wardrobe.cosmetic_source(id) != "Earned in play", "%s says how to get it" % id)
	check_eq(Wardrobe.cosmetic_source(&"cos_warrior_tabard"), "Class Level 15 with the Warrior", "a level cosmetic")
	check("Buy for 100 Seeds" in Wardrobe.cosmetic_source(&"dye_moss"), "a dye can be bought")
	check("Achievement" in Wardrobe.cosmetic_source(&"dye_moss"), "and earned")


func test_every_cosmetic_shape_builds() -> void:
	var seen_styles := {}
	for c in Db.cosmetics_of_kind(CosmeticData.KIND_TABARD):
		var part := OnionCosmetics.tabard_part(c)
		check(part.cloth != null and part.solid != null, "%s: a cloth panel and an emblem" % c.id)
		check(OnionCosmetics.tabard_part(c) == part, "%s: built once" % c.id)
		check(OnionCosmetics.tabard_part(c, Color(0.2, 0.5, 0.9)) != part, "%s: a dye is another part" % c.id)
		check(not seen_styles.has("t.%s" % c.style), "%s: its own emblem" % c.id)
		seen_styles["t.%s" % c.style] = true
	for c in Db.cosmetics_of_kind(CosmeticData.KIND_HAT):
		var part := OnionCosmetics.hat_part(c)
		check(part.solid != null, "%s: a head piece" % c.id)
		check(not seen_styles.has("h.%s" % c.style), "%s: its own shape" % c.id)
		seen_styles["h.%s" % c.style] = true
	for c in Db.cosmetics_of_kind(CosmeticData.KIND_GLOW):
		var mesh := OnionCosmetics.glow_mesh(c)
		check(mesh != null and mesh.get_surface_count() > 0, "%s: a mesh" % c.id)
		check(not seen_styles.has("g.%s" % c.style), "%s: its own style" % c.id)
		seen_styles["g.%s" % c.style] = true


func test_a_dye_purchase_spends_100_seeds_and_saves() -> void:
	var profile := _use_file()
	Meta.earn_seeds(150)
	var saves := Meta.save_count
	check_eq(Wardrobe.buy_cosmetic(&"dye_moss"), Wardrobe.RESULT_BOUGHT, "bought")
	check_eq(Meta.seeds(), 50, "100 Seeds paid")
	check(profile.has_unlock(Profile.KIND_COSMETIC, &"dye_moss"), "owned")
	check(Meta.save_count > saves, "saved at once")
	var back := Profile.load_file(_tmp_path)
	check(back.has_unlock(Profile.KIND_COSMETIC, &"dye_moss") and back.seeds == 50, "the file agrees")
	check_eq(Wardrobe.buy_cosmetic(&"dye_moss"), Wardrobe.RESULT_OWNED, "a second purchase is refused")
	check_eq(Meta.seeds(), 50, "and costs nothing")
	check_eq(Wardrobe.buy_cosmetic(&"dye_ember"), Wardrobe.RESULT_POOR, "50 Seeds are not enough")
	check_eq(Meta.seeds(), 50, "nothing was paid")
	check(not profile.has_unlock(Profile.KIND_COSMETIC, &"dye_ember"), "and nothing owned")
	check_eq(Wardrobe.buy_cosmetic(&"cos_gala_tabard"), Wardrobe.RESULT_INVALID, "an achievement tabard is not for sale")
	check_eq(Wardrobe.buy_cosmetic(&"dye_nobody"), Wardrobe.RESULT_INVALID, "no such dye")
	check_eq(Meta.seeds(), 50, "still 50")
	var changes: Array[int] = []
	Meta.seeds_changed.connect(func(_total: int, delta: int) -> void: changes.append(delta))
	Meta.earn_seeds(60)
	check_eq(Wardrobe.buy_cosmetic(&"dye_ember"), Wardrobe.RESULT_BOUGHT, "now it is")
	check_eq(changes, [60, -100] as Array[int], "the wallet signal told the price")
	check_eq(Meta.seeds(), 10, "10 left")
	Meta.profile = Profile.dev()
	check_eq(Wardrobe.buy_cosmetic(&"dye_charcoal"), Wardrobe.RESULT_OWNED, "the dev profile owns everything: nothing to buy")


# --- Loadout keys ---------------------------------------------------------------------------------

func test_the_loadout_keeps_the_cosmetic_keys() -> void:
	var l := Profile.normalize_loadout({"tabard": "cos_mage_tabard", "hat": "cos_mage_hat", "glow": "cos_mage_glow", "dye": "dye_ember",
			"looks": {"head": "g.head.0.0.0"}})
	for key in Profile.COSMETIC_KEYS:
		check(l.has(key), "%s is a loadout key" % key)
	check_eq(l["tabard"], &"cos_mage_tabard", "the tabard")
	check_eq(l["looks"], {&"head": &"g.head.0.0.0"} as Dictionary[StringName, StringName], "the looks stay")
	check_eq(Profile.normalize_loadout({})["dye"], &"", "empty by default")
	check_eq(Profile.normalize_loadout({"tabard": 5})["tabard"], &"5", "junk becomes an id")
	# The file keeps what is picked, and nothing for the rest.
	var p := Profile.fresh()
	p.set_loadout(&"mage", {"tabard": "cos_mage_tabard", "glow": "cos_mage_glow"})
	var d: Dictionary = p.to_dict()["loadouts"]["mage"]
	check_eq(d["tabard"], "cos_mage_tabard", "written")
	check(not d.has("hat") and not d.has("dye"), "an empty pick is not written")
	var back := Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	check_eq(back.loadout(&"mage")["glow"], &"cos_mage_glow", "read back")
	check_eq(back.loadout(&"warrior")["glow"], &"", "another class is untouched")
	# An old file (no cosmetic keys) loads.
	var old := Profile.from_dict({"version": 1, "loadouts": {"mage": {"seasonings": [], "heirloom": "", "looks": {}, "alt_weapon": false}}})
	check_eq(old.loadout(&"mage")["tabard"], &"", "an old loadout has none")


func test_the_slot_carries_the_cosmetics() -> void:
	var slot := Fakes.make_slot(0, &"mage")
	check(not slot.has_meta_selection(), "nothing selected")
	slot.cosmetics[&"glow"] = &"cos_mage_glow"
	check(slot.has_meta_selection(), "a cosmetic alone is a selection")
	var l := slot.meta_loadout()
	check_eq(l["glow"], &"cos_mage_glow", "it is in the loadout")
	var other := Fakes.make_slot(1, &"mage")
	other.set_meta_loadout(l)
	check_eq(other.cosmetics, {&"glow": &"cos_mage_glow"} as Dictionary[StringName, StringName], "and comes back")
	other.set_meta_loadout({})
	check(other.cosmetics.is_empty() and not other.has_meta_selection(), "an empty loadout clears it")


func test_remembering_and_sanitising_the_picks() -> void:
	var profile := _use_fresh()
	profile.unlock(Profile.KIND_LOOK, &"g.head.1.1.1")
	profile.unlock(Profile.KIND_COSMETIC, &"cos_mage_tabard")
	profile.unlock(Profile.KIND_COSMETIC, &"dye_ember")
	var l := Meta.sanitize_loadout({
		"looks": {"head": "g.head.1.1.1", "chest": "g.chest.0.0.0", "shoulders": "g.head.1.1.1", "legs": "g.head.1.1.1"},
		"tabard": "cos_mage_tabard", "hat": "cos_mage_hat", "glow": "dye_ember", "dye": "dye_ember"}, &"mage")
	check_eq(l["looks"], {&"head": &"g.head.1.1.1"} as Dictionary[StringName, StringName], "only the owned look of the right slot stays")
	check_eq(l["tabard"], &"cos_mage_tabard", "an owned tabard stays")
	check_eq(l["hat"], &"", "a hat the profile does not own goes")
	check_eq(l["glow"], &"", "a dye is not a glow")
	check_eq(l["dye"], &"dye_ember", "an owned dye stays")
	# Through the slot: remember, then apply on another slot of the class.
	var slot := Fakes.make_slot(0, &"mage")
	slot.looks[&"head"] = &"g.head.1.1.1"
	slot.cosmetics[&"tabard"] = &"cos_mage_tabard"
	Meta.remember_loadout(slot)
	var again := Fakes.make_slot(1, &"mage")
	Meta.apply_loadout(again)
	check_eq(again.looks, slot.looks, "the look comes back")
	check_eq(again.cosmetics, slot.cosmetics, "the tabard comes back")
	var other_class := Fakes.make_slot(2, &"rogue")
	Meta.apply_loadout(other_class)
	check(other_class.looks.is_empty() and other_class.cosmetics.is_empty(), "a class remembers its own")
	# The dev profile selects nothing.
	Meta.profile = Profile.dev()
	var dev := Fakes.make_slot(3, &"mage")
	Meta.apply_loadout(dev)
	check(dev.looks.is_empty() and dev.cosmetics.is_empty(), "nothing selected in an automated run")


# --- The model ----------------------------------------------------------------------------------

func test_a_look_override_dresses_the_model_and_never_changes_a_stat() -> void:
	var plain := _hero(&"mage", 0)
	var dressed := _hero(&"mage", 1, {&"head": &"g.head.3.2.4", &"chest": &"s.chest.battlegear_of_fury"})
	check(plain.model.dress() == null, "no selection, no dress")
	check_eq(plain.model.equipment_key(), "-|-|-", "the base model is untouched")
	check_eq(dressed.look_overrides.size(), 2, "the hero received the picks")
	check_eq(dressed.model.worn_look(HEAD).key(), Wardrobe.look_from_id(&"g.head.3.2.4").key(), "the head shows the override (plate on a mage: cross-armour)")
	check_eq(dressed.model.worn_look(CHEST).set_id, &"battlegear_of_fury", "the chest the set look")
	check(dressed.model.worn_look(SHOULDERS) == null, "an empty slot with no pick shows the class starter piece")
	check(dressed.model.equipment_key() != plain.model.equipment_key(), "the model's key changed")
	check_eq(plain.stats.snapshot(), dressed.stats.snapshot(), "not a stat moved")
	# A worn item is replaced for show only.
	var helm := _item(Items.SlotType.HEAD, ClassData.ArmorType.CLOTH, Items.Rarity.COMMON, 1)
	dressed.equipment.equip(helm)
	dressed.apply_equipment()
	check_eq(dressed.model.worn_look(HEAD).armor, ClassData.ArmorType.PLATE, "the override stays over the worn helm")
	var shoulders := _item(Items.SlotType.SHOULDERS, ClassData.ArmorType.CLOTH, Items.Rarity.COMMON, 1)
	dressed.equipment.equip(shoulders)
	dressed.apply_equipment()
	check_eq(dressed.model.worn_look(SHOULDERS).armor, ClassData.ArmorType.CLOTH, "a slot without a pick shows the worn item")
	# "Worn gear" again: the model returns to the item.
	dressed.model.set_dress(null)
	check_eq(dressed.model.worn_look(HEAD).armor, ClassData.ArmorType.CLOTH, "no pick: the worn helm")
	check_eq(dressed.model.worn_look(CHEST), null, "and the starter chest")


func test_overrides_do_not_touch_the_stat_sources_or_the_equipment() -> void:
	var hero := _hero(&"warrior", 0, {&"head": &"g.head.0.0.0", &"shoulders": &"g.shoulders.0.0.0", &"chest": &"g.chest.0.0.0"},
			{&"tabard": &"cos_warrior_tabard", &"hat": &"cos_warrior_hat", &"glow": &"cos_warrior_glow", &"dye": &"dye_ember"})
	var bare := _hero(&"warrior", 1)
	check_eq(hero.stats.snapshot(), bare.stats.snapshot(), "the same numbers")
	check(hero.equipment.get_item(Items.EquipSlot.HEAD) == null, "the dress put nothing in the equipment")
	check_eq(hero.cosmetic_overrides.size(), 4, "the cosmetics reached the hero")
	check_eq(hero.stats.max_hp(), bare.stats.max_hp(), "hit points")


func test_cosmetics_rebuild_the_model_by_their_key() -> void:
	var cd := Db.get_class_data(&"warrior")
	var m := OnionModel.new()
	_nodes.append(m)
	tree.root.add_child(m)
	m.setup(cd, Color.WHITE)
	var builds := m.gear_builds
	m.set_dress(null)
	m.set_dress(OnionDress.new())
	check_eq(m.gear_builds, builds, "no dress, no rebuild")
	var tabard := OnionDress.from_ids({}, {&"tabard": &"cos_warrior_tabard"})
	m.set_dress(tabard)
	check_eq(m.gear_builds, builds + 1, "a tabard rebuilds the gear")
	m.set_dress(OnionDress.from_ids({}, {&"tabard": &"cos_warrior_tabard"}))
	check_eq(m.gear_builds, builds + 1, "the same tabard again: nothing")
	m.set_dress(OnionDress.from_ids({}, {&"tabard": &"cos_warrior_tabard", &"dye": &"dye_ember"}))
	check_eq(m.gear_builds, builds + 2, "a dye on a tabard is another look")
	m.set_dress(OnionDress.from_ids({}, {&"dye": &"dye_ember"}))
	check_eq(m.gear_builds, builds + 3, "the tabard went (the dye alone shows nothing)")
	m.set_dress(OnionDress.from_ids({}, {&"dye": &"dye_moss"}))
	check_eq(m.gear_builds, builds + 3, "a dye alone changes nothing on the model")
	check(m.dress() == null, "and is not even kept as a dress")
	m.set_dress(OnionDress.from_ids({}, {&"glow": &"cos_warrior_glow"}))
	check(m.find_child("CosmeticGlow", true, false) != null, "a glow adds its light")
	m.set_dress(OnionDress.from_ids({}, {&"tabard": &"cos_warrior_tabard"}))
	check(m.find_child("CosmeticGlow", true, false) == null, "and takes it away again")
	m.set_dress(null)
	check_eq(m.equipment_key(), "-|-|-", "the base key is back")
	# A hat replaces the head piece; the face follows the hat (the mage's hat covers the sprout).
	var mage := OnionModel.new()
	_nodes.append(mage)
	tree.root.add_child(mage)
	mage.setup(Db.get_class_data(&"rogue"), Color.WHITE)
	var sprout := mage.find_child("Sprout", true, false) as Node3D
	check(sprout.visible, "the rogue's sprout shows")
	mage.set_dress(OnionDress.from_ids({}, {&"hat": &"cos_mage_hat"}))
	check(not (mage.find_child("Sprout", true, false) as Node3D).visible, "the Moonpeak Hat covers it")
	mage.set_dress(OnionDress.from_ids({}, {&"hat": &"cos_warrior_hat"}))
	check((mage.find_child("Sprout", true, false) as Node3D).visible, "the Bullhorn Helm does not")
	# Unresolvable picks are skipped, a cosmetic of the wrong kind too.
	var odd := OnionDress.from_ids({&"head": &"nonsense", &"chest": &"g.head.0.0.0"}, {&"tabard": &"dye_ember", &"glow": &"nobody"})
	check(odd.is_empty(), "nothing resolves")


func test_the_model_glow_is_hidden_while_downed() -> void:
	var m := OnionModel.new()
	_nodes.append(m)
	tree.root.add_child(m)
	m.setup(Db.get_class_data(&"mage"), Color.WHITE)
	m.set_dress(OnionDress.from_ids({}, {&"glow": &"cos_mage_glow"}))
	var glow := m.find_child("CosmeticGlow", true, false) as Node3D
	check(glow != null and glow.visible, "shown")
	m.set_downed(true)
	check(not glow.visible, "a ghost has no halo")
	m.set_downed(false)
	check(glow.visible, "and gets it back")


# --- LookPicker ---------------------------------------------------------------------------------

func _picker_for(class_id: StringName = &"mage", input: UiFakes.HumanInput = null) -> LookPicker:
	var inp := input if input != null else _human()
	var slot := PlayerManager.join(inp, Db.get_class_data(class_id))
	var picker := LookPicker.create(slot)
	picker.self_driven = false
	tree.root.add_child(picker)
	_nodes.append(picker)
	picker.skip_frames = 0
	return picker


func test_the_look_picker_builds_under_the_dev_profile() -> void:
	Meta.configure(&"", "", true)
	var picker := _picker_for()
	check(picker.is_open(), "open at once")
	check_eq(picker.row_panels.size(), 7, "head, shoulders, chest, tabard, hat, glow, dye")
	check_eq(picker.options_of(0).size(), 1 + 87, "worn gear + the 87 head looks (the dev profile owns them all)")
	check_eq(picker.options_of(3).size(), 1 + 8, "none + 8 tabards")
	check_eq(picker.options_of(6).size(), 1 + 6, "none + 6 dyes")
	check(picker.options_of(0)[0].kind == WardrobeEntry.Kind.NONE and picker.options_of(0)[0].title == "Worn gear", "'Worn gear' first")
	check(picker.options_of(4)[0].title == "None", "'None' first on a cosmetic row")
	check(picker.preview != null and picker.preview.model != null, "a live preview")
	check_eq(picker.preview.model.class_data.id, &"mage", "of the hero's class")


func test_the_look_picker_embedded_mode_is_rows_and_a_banner_and_goes_back() -> void:
	Meta.configure(&"", "", true)
	var picker := _picker_for()
	check(not picker.is_embedded(), "standalone to begin with")
	check_eq(picker.custom_minimum_size, LookPicker.STANDALONE_SIZE, "760 x 560")
	check(picker._head.visible and picker._stage.get_parent() == picker._body, "the title, and the stage on the left")
	picker.set_embedded(true)
	check(picker.is_embedded(), "embedded")
	check_eq(picker.custom_minimum_size, Vector2.ZERO, "no minimum size of its own")
	check(not picker._head.visible and not picker._head_divider.visible, "no title")
	check(picker._stage.get_parent() == picker._column and picker._stage.get_index() < picker._body.get_index(), "the preview is a banner above the rows")
	check_eq(picker._stage.custom_minimum_size, Vector2(0, LookPicker.EMBEDDED_STAGE_HEIGHT), "of its own height")
	check(picker.get_combined_minimum_size().x <= 400.0, "and it needs no more than a lobby card has inside (%d px; the prompts are the widest)" % picker.get_combined_minimum_size().x)
	check(picker.preview.model != null and picker.preview.model.class_data.id == &"mage", "it still shows the hero")
	var swap := _tap_feed(picker)
	check(swap, "the rows still answer the owner's input")
	picker.set_embedded(false)
	check(not picker.is_embedded() and picker._head.visible, "standalone again")
	check_eq(picker.custom_minimum_size, LookPicker.STANDALONE_SIZE, "with its size back")
	check(picker._stage.get_parent() == picker._body and picker._stage.get_index() == 0, "and the stage on the left")


## One step to the right on the first row of an embedded picker (a pick of the Head row); true when the slot changed.
func _tap_feed(picker: LookPicker) -> bool:
	var before: StringName = picker.slot.looks.get(&"head", &"")
	picker.step_row(0, 1)
	return picker.slot.looks.get(&"head", &"") != before


func test_the_look_picker_reacts_to_its_owners_input() -> void:
	Meta.configure(&"", "", true)
	var inp := _human("owner")
	var picker := _picker_for(&"mage", inp)
	var slot := picker.slot
	var closed: Array[bool] = []
	picker.closed.connect(func() -> void: closed.append(true))
	var changes: Array[StringName] = []
	picker.changed.connect(func(key: StringName, _id: StringName) -> void: changes.append(key))
	check_eq(picker.row, 0, "starts on Head")
	_nudge(inp, picker, Vector2(0, 1))
	check_eq(picker.row, 1, "down: Shoulders")
	_nudge(inp, picker, Vector2(0, -1))
	_nudge(inp, picker, Vector2(0, -1))
	check_eq(picker.row, 6, "up from the top wraps to Dye")
	_nudge(inp, picker, Vector2(0, 1))
	check_eq(picker.row, 0, "and back")
	_nudge(inp, picker, Vector2(1, 0))
	var first_head: StringName = picker.options_of(0)[1].id
	check_eq(slot.looks.get(&"head", &""), first_head, "right: the first look is worn for show")
	check(picker.preview.model.worn_look(HEAD) != null, "and the preview shows it")
	_nudge(inp, picker, Vector2(1, 0))
	check(slot.looks[&"head"] == picker.options_of(0)[2].id, "right again: the next one")
	_nudge(inp, picker, Vector2(-1, 0))
	_nudge(inp, picker, Vector2(-1, 0))
	check(not slot.looks.has(&"head"), "left back to 'Worn gear' clears it")
	_nudge(inp, picker, Vector2(-1, 0))
	check_eq(slot.looks[&"head"], picker.options_of(0)[picker.options_of(0).size() - 1].id, "left of 'Worn gear' wraps to the last look")
	_tap(inp, picker, PlayerInput.Pad.X)
	check(not slot.looks.has(&"head"), "X clears the row")
	# A cosmetic row.
	picker.row = 3
	_nudge(inp, picker, Vector2(1, 0))
	check(slot.cosmetics.has(&"tabard"), "a tabard is picked on the Tabard row")
	picker.row = 6
	_nudge(inp, picker, Vector2(1, 0))
	check(slot.cosmetics.has(&"dye"), "a dye on the Dye row")
	check_eq(slot.cosmetics[&"dye"], &"dye_rose_blush", "the first dye")
	check_eq(picker.preview.model.dress().tabard.id, slot.cosmetics[&"tabard"], "the preview wears the tabard")
	_tap(inp, picker, PlayerInput.Pad.Y)
	check(slot.looks.is_empty() and slot.cosmetics.is_empty(), "Y clears everything")
	check(changes.size() > 4, "the host heard the changes")
	_tap(inp, picker, PlayerInput.Pad.B)
	check_eq(closed.size(), 1, "B closes")
	check(not picker.is_open(), "hidden")


func test_the_look_picker_list_chooses_and_cancels() -> void:
	Meta.configure(&"", "", true)
	var inp := _human("lister")
	var picker := _picker_for(&"warrior", inp)
	var slot := picker.slot
	picker.row = 1  # Shoulders
	_tap(inp, picker, PlayerInput.Pad.A)
	check_eq(picker.mode, LookPicker.Mode.LIST, "A opens the list")
	check_eq(picker.grid.entries.size(), 1 + 83, "worn gear + every shoulder look")
	_nudge(inp, picker, Vector2(1, 0))
	check_eq(slot.looks.get(&"shoulders", &""), picker.grid.selected().id, "moving the cursor tries the look on")
	_nudge(inp, picker, Vector2(0, 1))
	var row_two: StringName = picker.grid.selected().id
	check_eq(slot.looks[&"shoulders"], row_two, "also down a row")
	_tap(inp, picker, PlayerInput.Pad.B)
	check_eq(picker.mode, LookPicker.Mode.ROWS, "B leaves the list")
	check(not slot.looks.has(&"shoulders"), "and puts the old choice back")
	_tap(inp, picker, PlayerInput.Pad.A)
	_nudge(inp, picker, Vector2(1, 0))
	var wanted: StringName = picker.grid.selected().id
	_tap(inp, picker, PlayerInput.Pad.A)
	check_eq(picker.mode, LookPicker.Mode.ROWS, "A takes the look and leaves the list")
	check_eq(slot.looks[&"shoulders"], wanted, "it stays")
	check_eq(picker.chosen_id(1), wanted, "the row says so")
	# The list of a row with nothing to choose from does not open.
	var fresh := _use_fresh()
	fresh.unlock(Profile.KIND_COSMETIC, &"cos_warrior_tabard")
	picker.open(slot)
	check_eq(picker.options_of(3).size(), 2, "none + the one owned tabard")
	check_eq(picker.options_of(0).size(), 1, "no collected head looks")
	picker.row = 0
	_tap(inp, picker, PlayerInput.Pad.A)
	check_eq(picker.mode, LookPicker.Mode.ROWS, "an empty list stays closed")


func test_the_look_picker_offers_only_what_a_real_profile_owns() -> void:
	var profile := _use_file()
	profile.unlock(Profile.KIND_LOOK, &"g.head.3.2.3")
	profile.unlock(Profile.KIND_LOOK, &"g.chest.0.0.0")
	profile.unlock(Profile.KIND_COSMETIC, &"cos_mage_glow")
	var inp := _human("real")
	var picker := _picker_for(&"mage", inp)
	check_eq(picker.options_of(0).size(), 2, "worn gear + the one collected head look")
	check_eq(picker.options_of(1).size(), 1, "no shoulder look yet")
	check_eq(picker.options_of(2).size(), 2, "the chest look")
	check_eq(picker.options_of(5).size(), 2, "the one owned glow")
	check_eq(picker.options_of(6).size(), 1, "no dye")
	_nudge(inp, picker, Vector2(1, 0))
	check_eq(picker.slot.looks[&"head"], &"g.head.3.2.3", "the collected look")
	var remembered := profile.loadout(&"mage")
	check_eq(remembered["looks"], {&"head": &"g.head.3.2.3"} as Dictionary[StringName, StringName], "remembered for the class at once")
	var saves := Meta.save_count
	_tap(inp, picker, PlayerInput.Pad.B)
	check_eq(Meta.save_count, saves + 1, "saved once, when the picker closes")
	check(Profile.load_file(_tmp_path).loadout(&"mage")["looks"].has(&"head"), "the file has the pick")
	# Shoulders have nothing: right does nothing, A does not open.
	picker.open(picker.slot)
	picker.skip_frames = 0
	picker.row = 1
	_nudge(inp, picker, Vector2(1, 0))
	check(not picker.slot.looks.has(&"shoulders"), "nothing to step to")


func test_the_look_picker_reads_a_frame_once_whoever_feeds_it() -> void:
	Meta.configure(&"", "", true)
	var inp := _human("frames")
	var picker := _picker_for(&"mage", inp)
	picker.self_driven = true
	inp.move = Vector2(0, 1)
	inp.poll(1.0 / 60.0)
	picker.handle_input(inp)  # the host feeds the frame
	picker._process(0.016)  # the picker's own turn in the same rendered frame
	check_eq(picker.row, 1, "one step, not two")
	inp.move = Vector2.ZERO
	inp.poll(1.0 / 60.0)
	# A host-driven picker is not read by _process either.
	picker.self_driven = false
	inp.move = Vector2(0, 1)
	inp.poll(1.0 / 60.0)
	picker._process(0.016)
	check_eq(picker.row, 1, "self_driven = false: _process reads nothing")
	picker.handle_input(inp)
	check_eq(picker.row, 2, "the host's call does")


func test_the_look_picker_ignores_the_press_that_opened_it() -> void:
	Meta.configure(&"", "", true)
	var inp := _human("opener")
	inp.press(PlayerInput.Pad.A)
	inp.move = Vector2(0, 1)
	inp.poll(1.0 / 60.0)
	var slot := PlayerManager.join(inp, Db.get_class_data(&"mage"))
	var picker := LookPicker.create(slot)
	picker.self_driven = false
	tree.root.add_child(picker)
	_nodes.append(picker)
	picker.process_input(inp)  # the opening frame
	picker.process_input(inp)  # the stick is still held
	check_eq(picker.row, 0, "a held direction does not move the cursor")
	check_eq(picker.mode, LookPicker.Mode.ROWS, "nor does A open the list")
	inp.move = Vector2.ZERO
	inp.release(PlayerInput.Pad.A)
	_feed(inp, picker)
	_nudge(inp, picker, Vector2(0, 1))
	check_eq(picker.row, 1, "once neutral it listens")


# --- WardrobePage -------------------------------------------------------------------------------

func _page() -> WardrobePage:
	var page := WardrobePage.create()
	tree.root.add_child(page)
	_nodes.append(page)
	return page


func _page_feed(inp: UiFakes.HumanInput, page: WardrobePage) -> bool:
	inp.poll(1.0 / 60.0)
	return page.handle_input(inp)


func _page_tap(inp: UiFakes.HumanInput, page: WardrobePage, button: PlayerInput.Pad) -> bool:
	inp.press(button)
	var used := _page_feed(inp, page)
	inp.release(button)
	_page_feed(inp, page)
	return used


func _page_nudge(inp: UiFakes.HumanInput, page: WardrobePage, dir: Vector2) -> bool:
	inp.move = dir
	var used := _page_feed(inp, page)
	inp.move = Vector2.ZERO
	_page_feed(inp, page)
	return used


func test_the_wardrobe_page_builds_under_the_dev_profile() -> void:
	Meta.configure(&"", "", true)
	var page := _page()
	check_eq(page.grid.entries.size(), 87, "the Head filter: 87 looks")
	check_eq(page.counts_for(0), Vector2i(87, 87), "all collected in the dev profile")
	check_eq(page.counts_for(1), Vector2i(83, 83), "shoulders")
	check_eq(page.counts_for(2), Vector2i(86, 86), "chest")
	check_eq(page.counts_for(3), Vector2i(23, 23), "tabards, hats and glows")
	check_eq(page.counts_for(4), Vector2i(6, 6), "dyes")
	check_eq(page._counter.text, "256 / 256 looks", "the counter")
	check(page.preview != null and page.preview.model != null, "a preview onion")
	check(page.selected() != null and page.selected().kind == WardrobeEntry.Kind.LOOK, "the cursor is on the first look")


func test_the_wardrobe_page_counts_a_real_collection() -> void:
	var profile := _use_fresh()
	for id in ["g.head.0.0.0", "g.head.1.0.0", "u.head.crown_of_ashes", "s.chest.battlegear_of_fury"]:
		profile.unlock(Profile.KIND_LOOK, StringName(id))
	profile.unlock(Profile.KIND_COSMETIC, &"cos_mage_tabard")
	profile.earn_seeds(340)
	var page := _page()
	check_eq(page._counter.text, "4 / 256 looks", "4 of 256")
	check_eq(page.counts_for(0), Vector2i(3, 87), "head")
	check_eq(page.counts_for(2), Vector2i(1, 86), "chest")
	check_eq(page.counts_for(3), Vector2i(1, 23), "cosmetics")
	check_eq(page.counts_for(4), Vector2i(0, 6), "no dye yet")
	check("340" in page._seeds.text, "the wallet is shown")
	var owned := 0
	for e in page.grid.entries:
		if e.owned:
			owned += 1
	check_eq(owned, 3, "three owned cells")
	check(not page.grid.entries[5].owned, "a locked cell")
	check(page.grid.entries[5].hint != "", "with a hint")


func test_the_wardrobe_page_reacts_to_input() -> void:
	Meta.configure(&"", "", true)
	var page := _page()
	var inp := _human("patch")
	check(not _page_feed(inp, page), "an idle frame is not used")
	check_eq(page.focus, WardrobePage.Focus.FILTERS, "the filters have the focus first")
	check(_page_nudge(inp, page, Vector2(1, 0)), "right: used")
	check_eq(page.filter, 1, "the Shoulders filter")
	check_eq(page.grid.entries.size(), 83, "its looks")
	check_eq(page.selected().slot, &"shoulders", "the cursor is on a shoulder look")
	_page_nudge(inp, page, Vector2(-1, 0))
	_page_nudge(inp, page, Vector2(-1, 0))
	check_eq(page.filter, 4, "left from the first wraps to Dyes")
	check_eq(page.grid.entries.size(), 6, "six dyes")
	check(not _page_nudge(inp, page, Vector2(0, -1)), "up on the filter row is the host's (not used)")
	check(_page_nudge(inp, page, Vector2(0, 1)), "down enters the grid")
	check_eq(page.focus, WardrobePage.Focus.GRID, "grid focus")
	check(_page_nudge(inp, page, Vector2(1, 0)), "right: the next dye")
	check_eq(page.grid.cursor, 1, "cursor 1")
	check_eq(page.selected().id, &"dye_gilded", "Gilded Gold")
	check(_page_nudge(inp, page, Vector2(0, -1)), "up from the top row goes back to the filters")
	check_eq(page.focus, WardrobePage.Focus.FILTERS, "filters")
	page.set_filter(0)
	_page_nudge(inp, page, Vector2(0, 1))
	var start := page.grid.cursor
	_page_nudge(inp, page, Vector2(0, 1))
	check_eq(page.grid.cursor, start + page.grid.columns(), "down a grid row")
	check(not _page_tap(inp, page, PlayerInput.Pad.B), "B is the host's")
	check(not _page_tap(inp, page, PlayerInput.Pad.LB) and not _page_tap(inp, page, PlayerInput.Pad.RB), "so are LB / RB")
	check(_page_tap(inp, page, PlayerInput.Pad.X), "X turns the preview")
	check(page.preview._turn != 0.0, "it turned")
	check_eq(page.activate(), &"", "A on a look does nothing")


func test_the_wardrobe_page_sells_dyes_for_100_seeds() -> void:
	var profile := _use_file()
	Meta.earn_seeds(230)
	var page := _page()
	var inp := _human("buyer")
	var bought: Array[StringName] = []
	page.purchased.connect(func(id: StringName) -> void: bought.append(id))
	page.set_filter(4)
	_page_nudge(inp, page, Vector2(0, 1))
	check_eq(page.selected().id, &"dye_rose_blush", "the first dye")
	check_eq(page.selected().price, 100, "100 Seeds")
	check(not page.selected().owned, "not owned")
	check("buy for 100" in page._status.text, "the status offers it")
	check(_page_tap(inp, page, PlayerInput.Pad.A), "A buys")
	check_eq(page.last_result(), Wardrobe.RESULT_BOUGHT, "bought")
	check_eq(bought, [&"dye_rose_blush"] as Array[StringName], "the signal")
	check_eq(Meta.seeds(), 130, "100 Seeds paid")
	check(profile.has_unlock(Profile.KIND_COSMETIC, &"dye_rose_blush"), "owned")
	check(page.selected().owned, "the cell is owned now")
	check("130" in page._seeds.text, "the wallet line followed")
	check_eq(page.counts_for(4), Vector2i(1, 6), "1 of 6")
	_page_nudge(inp, page, Vector2(1, 0))
	_page_tap(inp, page, PlayerInput.Pad.A)
	check_eq(Meta.seeds(), 30, "the second dye")
	_page_nudge(inp, page, Vector2(1, 0))
	check("Needs 70 more" in page._status.text, "30 Seeds: it says what is missing")
	_page_tap(inp, page, PlayerInput.Pad.A)
	check_eq(page.last_result(), Wardrobe.RESULT_POOR, "refused")
	check_eq(Meta.seeds(), 30, "nothing paid")
	_page_tap(inp, page, PlayerInput.Pad.A)
	check_eq(Meta.seeds(), 30, "still nothing")
	var back := Profile.load_file(_tmp_path)
	check(back.has_unlock(Profile.KIND_COSMETIC, &"dye_rose_blush") and back.has_unlock(Profile.KIND_COSMETIC, &"dye_gilded"), "both dyes are in the file")
	check_eq(back.seeds, 30, "and the wallet")


func test_the_wardrobe_page_previews_what_is_selected() -> void:
	Meta.configure(&"", "", true)
	var page := _page()
	page.set_preview_class(Db.get_class_data(&"rogue"), Color.RED)
	check_eq(page.preview.model.class_data.id, &"rogue", "the chosen class")
	page.grid.select_index(3)
	var dress := page.preview.model.dress()
	check(dress != null and dress.looks[HEAD] != null, "a head look is worn on the head")
	check_eq(Wardrobe.look_id(dress.looks[HEAD]), page.selected().id, "the selected one")
	page.set_filter(3)
	page.grid.select_index(0)
	check(page.preview.model.dress().tabard != null, "a tabard shows a tabard")
	page.grid.select_index(8)
	check(page.preview.model.dress().hat != null, "a hat a hat")
	page.grid.select_index(16)
	check(page.preview.model.dress().glow != null, "a glow a glow")
	page.set_filter(4)
	page.grid.select_index(3)
	var dyed := page.preview.model.dress()
	check(dyed.dye != null and dyed.tabard != null and dyed.glow != null, "a dye is shown on a tabard and a glow")


func test_the_wardrobe_grid_moves_and_scrolls() -> void:
	var grid := WardrobeGrid.new()
	_nodes.append(grid)
	tree.root.add_child(grid)
	grid.fixed_columns = 4
	grid.size = Vector2(420, 190)
	var list: Array[WardrobeEntry] = []
	for i in 10:
		list.append(WardrobeEntry.for_look(Wardrobe.all_look_ids()[i]))
	grid.set_entries(list)
	check_eq(grid.columns(), 4, "four columns")
	check_eq(grid.rows(), 3, "ten entries: three rows")
	check(grid.move(Vector2i(1, 0)) and grid.cursor == 1, "right")
	check(not grid.move(Vector2i(0, -1)), "no row above")
	grid.select_index(3)
	check(not grid.move(Vector2i(1, 0)), "no wrap at the row's end")
	check(grid.move(Vector2i(0, 1)) and grid.cursor == 7, "down")
	check(grid.move(Vector2i(0, 1)) and grid.cursor == 9, "down into the short last row lands on its last cell")
	check(not grid.move(Vector2i(0, 1)), "nothing below")
	grid.select_index(0)
	grid.select_index(9)
	check(grid._scroll > 0.0, "scrolled to keep the cursor in view")
	var moved: Array[StringName] = []
	grid.cursor_changed.connect(func(e: WardrobeEntry) -> void: moved.append(e.id if e != null else &""))
	grid.select_index(2)
	check_eq(moved.size(), 1, "the cursor signal")
	grid.set_entries([] as Array[WardrobeEntry])
	check(grid.selected() == null and not grid.move(Vector2i(1, 0)), "empty is safe")


func test_wardrobe_entries_describe_looks_and_cosmetics() -> void:
	_use_fresh()
	var e := WardrobeEntry.for_look(&"u.head.crown_of_ashes")
	check_eq(e.title, "Crown of Ashes", "the unique's name")
	check(not e.owned and e.hint != "", "locked, with a hint")
	check_eq(WardrobeEntry.for_look(&"s.head.battlegear_of_fury").title, "Ragebound Plate Head", "a set piece: the set's name and the slot")
	check_eq(WardrobeEntry.for_look(&"g.chest.3.1.2").title, "Steel Breastplate", "a generated piece")
	check_eq(WardrobeEntry.for_look(&"g.chest.3.1.2").detail, "Plate · Rare", "its detail")
	var d := WardrobeEntry.for_cosmetic(Db.get_cosmetic(&"dye_ember"))
	check(d.price == 100 and not d.owned and d.slot == &"dye", "a dye for sale")
	var none := WardrobeEntry.none(&"head", "Worn gear")
	check(none.kind == WardrobeEntry.Kind.NONE and none.id == &"", "the 'nothing' entry")
