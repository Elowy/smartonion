extends TestCase
## M6b content integration: the three content packages (CONTENT-W / CONTENT-DATA, CONTENT-FX,
## CONTENT-ITEMS) together and with the M6b features. Names and ids are unique across ALL content,
## the merged totals are pinned in one place, and the Black Market, the Shrine of Fortune, the dungeon
## rewards and the Enchanter can all hand out the new content (and never an Artifact).

const Support := preload("res://tests/test_loot_support.gd")
const Procs := preload("res://tests/test_procs.gd")
const Rules := preload("res://tests/content_rules.gd")

## The content of the three packages, by id (data/ file names).
const NEW_WEAPONS: Array[StringName] = [&"two_hand_sword", &"two_hand_mace", &"orb"]
const NEW_JEWELLERY: Array[StringName] = [
	&"neck_torque", &"neck_locket", &"neck_collar", &"neck_medallion", &"neck_talisman", &"neck_lavalier",
	&"ring_seal", &"ring_hoop", &"ring_crest", &"ring_bezel", &"ring_keeper", &"ring_thumb_ring",
]
const NEW_SUFFIXES: Array[StringName] = [&"ox", &"lynx", &"raven", &"thorns", &"mending", &"hunter", &"magpie"]
const NEW_ENCHANTS: Array[StringName] = [
	&"arcing", &"barbed", &"bulwarking", &"clinging", &"concussive", &"emberhide", &"feasting", &"fortifying",
	&"frenzied", &"gilded", &"glacial", &"gravewarded", &"quickened", &"rallying", &"rimebound", &"riposting",
	&"rousing", &"rupturing", &"scorching", &"smoldering", &"soothing", &"spiked", &"studious", &"sweeping",
	&"wailing", &"warding",
]
## The Epic hand-made items of CONTENT-ITEMS: the class items by class, and the class-free named ones.
const NEW_CLASS_EPICS := {
	&"warrior": [&"warhelm_of_the_standing_shout", &"breastplate_of_thunderous_echo", &"reaping_greataxe"],
	&"mage": [&"leggings_of_the_falling_star", &"long_coal_staff", &"robe_of_the_tidewoven_veil"],
	&"paladin": [&"cuirass_of_the_vigilant_dawn", &"girdle_of_lasting_grace", &"helm_of_the_holy_hour"],
	&"rogue": [&"hood_of_quick_blades", &"jerkin_of_the_last_breath", &"leathers_of_the_unseen_throw"],
	&"warlock": [&"hood_of_burning_summons", &"robe_of_the_hollow_star"],
}
const NEW_NAMED_EPICS: Array[StringName] = [
	&"amulet_of_the_thousand_skins", &"gauntlets_of_the_cloven_crust", &"girdle_of_the_unyielding_layer",
	&"halo_of_the_pearled_onion", &"leathers_of_the_rooted_dance", &"ringmail_of_the_second_skin",
	&"robe_of_the_lantern_heart", &"scallion_edge", &"shallot_shiv", &"signet_of_the_festering_wound",
	&"silken_leggings_of_the_veil", &"spaulders_of_the_hollow_shell", &"treads_of_the_nimble_clove",
	&"visor_of_the_sunward_watch", &"wrap_of_the_blighted_peel",
]
const ARTIFACT_IDS: Array[StringName] = [
	&"dawnbreaker", &"earthsplitter", &"fangs_of_the_shadow", &"skull_of_the_damned", &"staff_of_the_frostwyrm",
]
const WAVE := 20


# --- Helpers -------------------------------------------------------------------------------------

## The .tres files of [param dir] (a res://data/ folder), by file name without the extension.
static func _file_ids(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		var name := f.trim_suffix(".remap")
		if name.ends_with(".tres"):
			out.append(name.trim_suffix(".tres"))
	return out


func _seeded(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## What new content [param item] carries, keyed "tier base" / "jewellery" / "weapon" / "suffix" /
## "enchant" / "hand-made", into [param seen] (key -> count).
func _note(item: ItemInstance, seen: Dictionary) -> void:
	if item == null:
		return
	var base: ItemBase = Db.item_bases.get(item.source_id)
	if base != null and base.min_wave > 1:
		_bump(seen, "tier base")
	if item.source_id in NEW_JEWELLERY:
		_bump(seen, "jewellery")
	if item.source_id in NEW_WEAPONS:
		_bump(seen, "weapon")
	for id in NEW_SUFFIXES:
		if item.display_name.ends_with(" " + Db.affixes[id].suffix):
			_bump(seen, "suffix")
	for roll in item.enchants:
		if roll.enchant.id in NEW_ENCHANTS:
			_bump(seen, "enchant")
	if item.unique and not item.source_id.is_empty():
		_bump(seen, "hand-made")


func _bump(seen: Dictionary, key: String) -> void:
	seen[key] = int(seen.get(key, 0)) + 1


func _check_all_seen(seen: Dictionary, what: String, keys: Array[String]) -> void:
	for key in keys:
		check(int(seen.get(key, 0)) > 0, "%s can roll new content: %s (seen %s)" % [what, key, str(seen)])


# --- Names and ids -------------------------------------------------------------------------------

func test_ids_match_the_files_so_no_two_files_share_an_id() -> void:
	# Db keys its dictionaries by id: two files with one id would silently overwrite each other.
	check_eq(Db.uniques.size(), _file_ids("res://data/uniques").size(), "uniques: one id per file")
	check_eq(Db.enchants.size(), _file_ids("res://data/enchants").size(), "enchants: one id per file")
	check_eq(Db.item_bases.size(), _file_ids("res://data/item_bases").size(), "item bases: one id per file")
	check_eq(Db.affixes.size(), _file_ids("res://data/affixes").size(), "suffixes: one id per file")
	check_eq(Db.weapons.size(), _file_ids("res://data/weapons").size(), "weapons: one id per file")
	check_eq(Db.artifacts.size(), _file_ids("res://data/artifacts").size(), "artifacts: one id per file")
	check_eq(Forge.legendaries().size(), _file_ids("res://data/forge").size(), "Forge Legendaries: one per file")
	for id in Db.uniques:
		check(String(id) in _file_ids("res://data/uniques"), "unique %s is named like its file" % id)


func test_proc_ids_do_not_clash_between_uniques_artifacts_and_enchants() -> void:
	# ProcSystem keys fire counts and DoT stacks by the proc id: an enchant id and a unique's source id
	# on one hero must never be the same word.
	var owner: Dictionary[StringName, String] = {}
	for id in Db.enchants:
		owner[id] = "enchant"
	for pool: Dictionary in [Db.uniques, Db.artifacts]:
		for id in pool:
			check(not owner.has(id), "%s is both %s and a unique / artifact" % [id, owner.get(id, "")])
			owner[id] = "unique"


func test_display_names_are_unique_across_all_content() -> void:
	var seen: Dictionary[String, String] = {}
	var clashes: Array[String] = []
	var add := func(name: String, owner: String) -> void:
		var key := name.strip_edges().to_lower()
		check(key != "", "%s has a name" % owner)
		if seen.has(key):
			clashes.append("%s (%s and %s)" % [name, seen[key], owner])
		seen[key] = owner
	for id in Db.uniques:
		add.call(Db.uniques[id].display_name, "unique %s" % id)
	for id in Db.artifacts:
		add.call(Db.artifacts[id].display_name, "artifact %s" % id)
		if Db.artifacts[id].pair_name != "":
			add.call(Db.artifacts[id].pair_name, "artifact %s pair" % id)
	var legendaries := Forge.legendaries()
	for id in legendaries:
		add.call(legendaries[id].display_name, "Forge Legendary %s" % id)
	for id in Db.weapons:
		add.call(Db.weapons[id].display_name, "weapon %s" % id)
	# Item bases: the original tier I pieces of different armour types share a noun ("Gloves" of cloth and
	# of leather; the material word of the generated name tells them apart). Every other base - the
	# tier II / III pieces and the jewellery - has a name of its own.
	var tier_one_types: Dictionary[String, Array] = {}  # noun -> armour types that use it as tier I
	for id in Db.item_bases:
		var base := Db.item_bases[id]
		if base.min_wave == 1 and base.armor_type != Items.NO_ARMOR:
			var noun := base.display_name.to_lower()
			var types: Array = tier_one_types.get(noun, [])
			check(base.armor_type not in types, "tier I %s: only one armour type shares the noun" % base.display_name)
			if types.is_empty():
				add.call(base.display_name, "base %s" % id)
			types.append(base.armor_type)
			tier_one_types[noun] = types
		else:
			add.call(base.display_name, "base %s" % id)
	for id in Db.sets:
		add.call(Db.sets[id].display_name, "set %s" % id)
	check(clashes.is_empty(), "no display name is used twice (%d: %s)" % [clashes.size(), ", ".join(PackedStringArray(clashes.slice(0, 8)))])
	# Enchant prefixes and suffix phrases are words inside generated names: unique among themselves and
	# not the name of a hand-made item or base.
	var prefixes: Dictionary[String, StringName] = {}
	for id in Db.enchants:
		var key := Db.enchants[id].prefix.to_lower()
		check(key != "" and not prefixes.has(key), "enchant prefix %s is used once (%s)" % [Db.enchants[id].prefix, id])
		prefixes[key] = id
		check(not seen.has(key), "enchant prefix %s is no item name (%s)" % [Db.enchants[id].prefix, str(seen.get(key, ""))])
	var suffixes: Dictionary[String, StringName] = {}
	for id in Db.affixes:
		var key := Db.affixes[id].suffix.to_lower()
		check(key != "" and not suffixes.has(key), "suffix %s is used once (%s)" % [Db.affixes[id].suffix, id])
		suffixes[key] = id


func test_the_merged_totals() -> void:
	# Weapon bases, Legendaries, class items and Artifacts follow the classes and weapon types of the
	# data (the rules of content_rules.gd); the M6b launch content must all still be there.
	for id in Rules.LAUNCH_WEAPONS:
		check(Db.weapons.has(id), "launch weapon base %s" % id)
	check_eq(Forge.legendaries().size(), Db.weapons.size(), "Forge Legendaries: one per weapon base")
	check_eq(Db.item_bases.size(), 116, "item bases: 96 armour + 20 jewellery")
	check_eq(Db.affixes.size(), 25, "stat suffixes")
	check_eq(Db.enchants.size(), 50, "enchants: 24 + 26")
	check_eq(Rules.launch_uniques(), Rules.LAUNCH_UNIQUES,
			"launch hand-made items: 63 + 20 trinkets + 17 Legendaries + 30 named + 30 class items")
	for class_id in Rules.classes_with("items"):
		check_eq(Rules.class_items(class_id).size(), Rules.CLASS_ITEMS_PER_CLASS, "%s: its class items" % class_id)
	for class_id in Rules.classes_with("set"):
		check_eq(Rules.class_sets(class_id).size(), 1, "%s: one class tier set" % class_id)
	check_eq(Db.artifacts.size(), Rules.classes_with("artifact").size(), "Artifacts: one per class")
	check_eq(Db.enchants.size(), Procs.ENCHANT_IDS.size() + NEW_ENCHANTS.size(), "24 old + 26 new enchants")
	for id in NEW_ENCHANTS:
		check(Db.enchants.has(id), "new enchant %s exists" % id)
		check(id not in Procs.ENCHANT_IDS, "%s is not one of the 24 old ones" % id)
	for id in NEW_WEAPONS:
		check(Db.weapons.has(id), "new weapon %s exists" % id)
	for id in NEW_JEWELLERY:
		check(Db.item_bases.has(id), "new jewellery base %s exists" % id)
	for id in NEW_SUFFIXES:
		check(Db.affixes.has(id), "new suffix %s exists" % id)


# --- Every new unique can roll somewhere ---------------------------------------------------------

func test_every_hand_made_item_can_be_rolled_from_one_of_its_sources() -> void:
	var dead: Array[String] = []
	for id in Db.uniques:
		var data := Db.uniques[id]
		if data.set_id != &"":
			continue
		var reachable := false
		for source in ItemGenerator.SOURCE_IDS.size():
			if ItemGenerator.unique_available(data, source as ItemGenerator.Source, 25):
				reachable = true
		if not reachable or data.weight <= 0.0:
			dead.append(String(id))
	check(dead.is_empty(), "every hand-made item has a source and a weight at wave 25 (dead: %s)" % ", ".join(PackedStringArray(dead)))
	for id in Db.artifacts:
		for source in ItemGenerator.SOURCE_IDS.size():
			check(not ItemGenerator.unique_available(Db.artifacts[id], source as ItemGenerator.Source, 25),
					"%s never drops as a hand-made roll" % id)


# --- The features hand out the new content -------------------------------------------------------

func test_black_market_max_rolls_carry_the_new_content() -> void:
	var classes: Array[StringName] = [&"warrior", &"mage", &"paladin", &"warlock"]
	var slots := Support.make_slots(classes)
	var rng := _seeded(2026)
	var seen := {}
	for i in 500:
		var item := BlackMarket.roll(WAVE, slots, rng)
		check(item != null and item.rarity == Items.Rarity.EPIC and not item.is_artifact(), "an Epic, never an Artifact")
		_note(item, seen)
	Support.free_slots(slots)
	_check_all_seen(seen, "the Black Market", ["tier base", "jewellery", "suffix", "enchant", "weapon"])


func test_shrine_of_fortune_epics_carry_the_new_content() -> void:
	var classes: Array[StringName] = [&"warrior", &"mage", &"paladin", &"rogue"]
	var slots := Support.make_slots(classes)
	RunState.start_run(4, 99)
	RunState.set_wave(WAVE)
	var seen := {}
	var fortune := Db.get_shrine(&"fortune")
	for seed_value in 150:
		RunState.shrine_rng.seed = seed_value
		for s in slots:
			Support.equipment_of(s).backpack.clear()
		Shrines.accept(fortune, slots)
		for s in slots:
			for item in Support.equipment_of(s).backpack:
				check(item.rarity == Items.Rarity.EPIC and item.can_be_used_by(s.class_data), "an Epic its hero can use")
				_note(item, seen)
	Support.free_slots(slots)
	_check_all_seen(seen, "the Shrine of Fortune", ["tier base", "jewellery", "suffix", "enchant", "weapon"])


func test_dungeon_rewards_carry_the_new_content() -> void:
	var classes: Array[StringName] = [&"warrior", &"mage", &"rogue", &"warlock"]
	var slots := Support.make_slots(classes)
	var team: Array[ClassData] = []
	for s in slots:
		team.append(s.class_data)
	var rng := _seeded(515)
	var seen := {}
	for i in 150:
		for s in slots:
			var item := DungeonRewards.epic_for(s, WAVE, team, rng)
			check(item != null and item.rarity == Items.Rarity.EPIC and item.can_be_used_by(s.class_data), "an Epic the hero can use")
			_note(item, seen)
	Support.free_slots(slots)
	_check_all_seen(seen, "the dungeon rewards", ["tier base", "jewellery", "suffix", "enchant", "weapon"])


func test_the_epic_features_roll_the_new_hand_made_epics() -> void:
	# The Shrine of Fortune and the dungeon rewards ask the generator for an Epic usable by the hero's
	# class: the 14 new class items (each class its own) and the new named Epics come out of the same
	# hand-made roll (UNIQUE_CHANCE) as the old ones. The Black Market never sells them (set piece or
	# generated max-roll only, by design).
	var rng := _seeded(88)
	var named_seen: Dictionary[StringName, int] = {}
	for class_id in NEW_CLASS_EPICS:
		var class_data := Db.get_class_data(class_id)
		var own := 0
		for i in 1500:
			var item := ItemGenerator.generate(ItemGenerator.Source.LOOT, WAVE, rng,
					{&"rarity": Items.Rarity.EPIC, &"usable_by": class_data, &"class_data": class_data})
			if item == null or not item.unique:
				continue
			check(item.can_be_used_by(class_data), "%s: %s is usable" % [class_id, item.display_name])
			if item.source_id in NEW_CLASS_EPICS[class_id]:
				own += 1
			if item.source_id in NEW_NAMED_EPICS:
				named_seen[item.source_id] = named_seen.get(item.source_id, 0) + 1
		check(own > 0, "a new %s class item comes up in Epic rolls (%d)" % [class_id, own])
	check_eq(named_seen.size(), NEW_NAMED_EPICS.size(), "every new named Epic comes up in some class's Epic rolls (%s)" % str(named_seen))


# --- The Enchanter reaches the new enchants ------------------------------------------------------

func test_the_enchanter_can_reroll_into_every_new_enchant() -> void:
	# For each new enchant: the reroll pool of an Epic item of some slot holds it, and the weighted pick
	# can return it. Slots by kind: weapons, rings and trinkets take on-hit / on-kill, chest and head the
	# when-struck ones, anything the equip ones.
	var slot_types: Array[Items.SlotType] = [
		Items.SlotType.WEAPON, Items.SlotType.RING, Items.SlotType.TRINKET, Items.SlotType.CHEST,
		Items.SlotType.HEAD, Items.SlotType.SHOULDERS, Items.SlotType.NECK, Items.SlotType.LEGS,
		Items.SlotType.HANDS, Items.SlotType.WAIST, Items.SlotType.WRIST, Items.SlotType.FEET,
	]
	var unreachable: Array[String] = []
	for id in NEW_ENCHANTS:
		var enchant := Db.get_enchant(id)
		var found := false
		for slot_type in slot_types:
			var item := Support.make_armor(40, ClassData.ArmorType.PLATE, 20, Items.Rarity.EPIC, slot_type)
			item.enchants.append(EnchantRoll.new(Db.get_enchant(&"mighty"), 0))
			if slot_type == Items.SlotType.WEAPON:
				item = Support.make_weapon(&"bow", Items.Rarity.EPIC)
				item.enchants.append(EnchantRoll.new(Db.get_enchant(&"mighty"), 0))
			var pool := Enchanter.reroll_pool(item, 0)
			if enchant in pool and Enchanter.pick(pool, _seeded(1), Db.get_class_data(&"warrior")) != null:
				found = true
				break
		if not found:
			unreachable.append(String(id))
	check(unreachable.is_empty(), "every new enchant is in some item's reroll pool (not: %s)" % ", ".join(PackedStringArray(unreachable)))


func test_enchanter_rerolls_land_on_new_enchants_and_keep_artifacts_out() -> void:
	RunState.start_run(2, 31)
	RunState.wave = 15
	var slots := Support.make_slots([&"warrior"] as Array[StringName])
	var eq := Support.equipment_of(slots[0])
	var rng := _seeded(404)
	var landed: Dictionary[StringName, int] = {}
	for i in 120:
		RunState.add_gold(5000)
		RunState.add_dust(500, -1, "fixture")
		var ring := Support.make_armor(40, ClassData.ArmorType.PLATE, 20, Items.Rarity.EPIC, Items.SlotType.RING)
		ring.wave = 15
		ring.buy_price = ItemGenerator.price_for(Items.Rarity.EPIC, 15)
		ring.enchants.append(EnchantRoll.new(Db.get_enchant(&"blazing"), 1))
		eq.add_to_backpack(ring)
		var out := Enchanter.perform(eq, slots[0].index, ring, Enchanter.Action.REROLL, 0, rng)
		check(out.ok, "rerolled: %s" % out.reason)
		if out.ok:
			landed[ring.enchants[0].enchant.id] = landed.get(ring.enchants[0].enchant.id, 0) + 1
		eq.backpack.clear()
	var new_hits := 0
	for id in landed:
		if id in NEW_ENCHANTS:
			new_hits += landed[id]
	check(new_hits > 20, "a reroll into a new enchant is common (%d of 120)" % new_hits)
	# An Artifact is refused, whatever the new content.
	for id in Db.artifacts:
		var artifact := ItemGenerator.from_artifact(Db.artifacts[id], 12)
		check_eq(Enchanter.blocked_reason(artifact, Enchanter.Action.REROLL, 0), Enchanter.REASON_ARTIFACT, "%s cannot be rerolled" % id)
	Support.free_slots(slots)
	RunState.start_run(1, 7)


# --- Artifacts are unaffected --------------------------------------------------------------------

func test_artifacts_are_unchanged_by_the_content_packages() -> void:
	var ids: Array[StringName] = []
	for id in Db.artifacts:
		ids.append(id)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for id in ARTIFACT_IDS:
		check(ids.has(id), "the launch Artifact %s is still there" % id)
	check_eq(ids.size(), Rules.classes_with("artifact").size(), "and there is one per class")
	for id in ids:
		var item := ItemGenerator.from_artifact(Db.artifacts[id], 12)
		check(item.is_artifact() and item.rarity == Items.Rarity.ARTIFACT, "%s is an Artifact" % id)
		check(item.can_disenchant() == false, "%s cannot be disenchanted" % id)
		for roll in item.enchants:
			check(roll.enchant != null and Db.enchants.has(roll.enchant.id), "%s: its fixed enchants still exist" % id)
	# No generated or hand-made roll is an Artifact unless one is asked for.
	var rng := _seeded(7)
	for i in 1500:
		var item := ItemGenerator.generate(ItemGenerator.Source.LOOT, 1 + (i % 25), rng)
		check(item != null and not item.is_artifact(), "a normal roll is no Artifact")
