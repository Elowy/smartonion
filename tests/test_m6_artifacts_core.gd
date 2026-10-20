extends TestCase
## M6 ARTIFACTS core (GDD 5.5): the data of the class Artifacts (one per class), the item path (ilvl, Greed, never
## sold / forged), growth (+3 Item Level, +4% weapon damage, the two properties awakening), the
## Fangs of the Shadow pair rule of Equipment and the drop roll of LootDrops.roll_artifact
## (wave 10, the chances, Fortune, 80 / 20 class pick, one per class, one roll per kill, pity).

const Fakes := preload("res://tests/player_fakes.gd")
const EFakes := preload("res://tests/enemies_fakes.gd")
const Rules := preload("res://tests/content_rules.gd")
## An id that is no class: "a class without an Artifact" in the checks below.
const NO_SUCH_CLASS := &"zz_no_such_class"

var world: Node3D
var arena: EFakes.TestArena


func before_each() -> void:
	PlayerManager.clear()
	RunState.start_run(2, 4711)
	RunState.set_wave(10)
	LootDrops.artifact_roll_probe = Callable()
	LootDrops.artifact_chance_override = -1.0
	world = EFakes.make_world(tree)
	arena = EFakes.arena_of(world)


func after_each() -> void:
	LootDrops.artifact_roll_probe = Callable()
	LootDrops.artifact_chance_override = -1.0
	EFakes.free_world(tree, world)
	world = null
	arena = null
	PlayerManager.clear()
	RunState.start_run(1, 1)


# --- Helpers ----------------------------------------------------------------------------

func _artifact(class_id: StringName, wave: int = 10) -> ItemInstance:
	return ItemGenerator.generate_artifact(class_id, wave)


func _equipment(class_id: StringName) -> Equipment:
	var eq := Equipment.new(Db.get_class_data(class_id))
	eq.equip_starting_weapons()
	return eq


## A normal enemy under the arena; [param boss] makes it a boss (EnemyData.is_boss).
func _enemy(boss: bool = false) -> Enemy:
	var data := EFakes.enemy_data()
	data.is_boss = boss
	return EFakes.spawn_enemy(world, data, Vector3(3.0, 0.0, 2.0), 10)


func _join(class_id: StringName) -> PlayerSlot:
	return PlayerManager.join(ScriptedInput.new("art:%s" % class_id), Db.get_class_data(class_id))


func _killer(fortune: float = 0.0) -> Player:
	var p := EFakes.spawn_player(world, Vector3(25.0, 0.0, 25.0), 0)
	if fortune != 0.0:
		p.stats.set_source(&"test", {Stats.FORTUNE: fortune})
	return p


# --- Data -------------------------------------------------------------------------------

## Every class has exactly one Artifact and every Artifact belongs to a class (a missing or a
## second one fails; a class whose Artifact is still pending in Rules.PENDING is left out), all
## with valid data, listed in lobby order.
func test_one_artifact_per_class_all_valid() -> void:
	var expected := Rules.classes_with("artifact")
	check_eq(Db.artifacts.size(), expected.size(), "one Artifact per class")
	for class_id in expected:
		check_eq(Rules.count_of(class_id, "artifact"), 1, "%s: exactly one Artifact" % class_id)
		var data := Db.artifact_for_class(class_id)
		check(data != null, "%s has an Artifact" % class_id)
		if data != null:
			check_eq(Artifacts.validate(data), "", "%s: valid data" % data.id)
	for id in Db.artifacts:
		check(Db.artifacts[id].class_id in expected, "%s belongs to a class that has Artifacts" % id)
	check_eq(Db.artifact_classes(), expected, "in lobby order")
	check(Db.artifact_for_class(NO_SUCH_CLASS) == null, "no Artifact for a class without one")


func test_the_named_weapons_of_the_gdd() -> void:
	var want := {
		&"warrior": [&"earthsplitter", &"axe", true], &"mage": [&"staff_of_the_frostwyrm", &"staff", true],
		&"paladin": [&"dawnbreaker", &"mace", false], &"rogue": [&"fangs_of_the_shadow", &"dagger", false],
		&"warlock": [&"skull_of_the_damned", &"staff", true],
	}
	for class_id: StringName in want:
		var data := Db.artifact_for_class(class_id)
		check_eq(data.id, want[class_id][0], "%s: the Artifact" % class_id)
		check_eq(data.weapon.weapon_type, want[class_id][1], "%s: its weapon type" % class_id)
		check_eq(data.weapon.is_two_handed(), want[class_id][2], "%s: two-handed" % class_id)
	# What every class's Artifact shares (the M8 classes' included).
	for class_id in Db.artifact_classes():
		var data := Db.artifact_for_class(class_id)
		check_eq(data.is_pair(), class_id == &"rogue", "%s: only the Rogue's is a pair" % class_id)
		check_eq(data.unlock_waves, [3, 6] as Array[int], "%s: properties after 3 and 6 wave ends" % class_id)
		check_eq(data.properties.size(), 2, "%s: two properties" % class_id)


func test_artifacts_stay_out_of_the_normal_pools() -> void:
	for id in Db.uniques:
		check(Db.uniques[id].rarity != Items.Rarity.ARTIFACT, "%s is no Artifact" % id)
	check_eq(Rules.launch_uniques(), Rules.LAUNCH_UNIQUES, "the launch hand-made items: 63 (M6a) + 20 trinkets + 17 Legendaries (CONTENT-FX) + 30 named + 30 class items (CONTENT-ITEMS)")
	for id in Db.artifacts:
		check(not ItemGenerator.unique_available(Db.artifacts[id], ItemGenerator.Source.BOSS, 25),
				"%s is never a hand-made roll" % id)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 400:
		var item := ItemGenerator.generate(ItemGenerator.Source.BOSS, 25, rng, {&"fortune": 500.0})
		check(not item.is_artifact(), "no table roll is an Artifact")


func test_property_scripts_load_and_extend_talent_effect() -> void:
	for id in Db.artifacts:
		for p in Db.artifacts[id].properties:
			for e: Dictionary in p["effects"]:
				if e["kind"] == "script":
					var script := load(str(e["script"])) as Script
					check(script != null and script.can_instantiate(), "%s loads" % e["script"])
					check(script.new() is TalentEffect, "%s extends TalentEffect" % e["script"])


# --- The item ---------------------------------------------------------------------------

func test_item_level_is_10_plus_3_wave_plus_25() -> void:
	for wave in [10, 13, 25]:
		var item := _artifact(&"warrior", wave)
		check_eq(item.item_level, 10 + 3 * wave + 25, "wave %d" % wave)
		check_eq(item.rarity, Items.Rarity.ARTIFACT, "rarity Artifact")
		check(item.is_artifact(), "is_artifact")
		check_eq(item.wave, wave, "made for the wave")
		check_eq(item.class_restriction, &"warrior", "only the class")
		check(item.looted, "Looted")


func test_the_item_is_a_class_weapon_with_fixed_enchants() -> void:
	for class_id in Db.artifact_classes():
		var item := _artifact(class_id)
		var cls := Db.get_class_data(class_id)
		check(item.is_weapon() and cls.can_use(item.weapon), "%s: a weapon the class can use" % class_id)
		check_near(item.weapon.base_damage, Db.artifact_for_class(class_id).weapon.base_damage * 3.0, 0.001,
				"%s: the Artifact weapon damage x3 at pickup" % class_id)
		check_eq(item.artifact_base_damage, item.weapon.base_damage, "the growth baseline")
		check_eq(item.enchants.size(), 2, "%s: two fixed enchants" % class_id)
		for roll in item.enchants:
			check_eq(roll.rank, 2, "rank III")
		check(item.can_be_used_by(cls), "usable by its class")
		for other in Db.class_ids:
			if other != class_id:
				check(not item.can_be_used_by(Db.get_class_data(other)), "%s cannot use %s's" % [other, class_id])


func test_making_an_artifact_draws_nothing() -> void:
	var before := RunState.rng.state
	for class_id in Db.artifact_classes():
		_artifact(class_id)
	check_eq(RunState.rng.state, before, "no rng draw: seeds stay stable")


func test_artifact_is_never_sold_forged_or_disenchanted() -> void:
	var item := _artifact(&"warrior")
	check(not item.can_sell(), "can_sell is false")
	check(not item.can_disenchant(), "and so is can_disenchant (the Enchanter asks)")
	check(_artifact(&"warrior").is_artifact(), "still an Artifact")
	var eq := _equipment(&"warrior")
	eq.backpack.append(item)
	check_eq(Forge.blocked_reason(eq, item), Forge.REASON_ARTIFACT, "the Forge refuses it")
	check(not Forge.is_forgeable(item), "not forgeable")
	check(_equipment(&"warrior").backpack.is_empty(), "fresh equipment is empty")
	var plain := ItemInstance.from_weapon(Db.get_weapon(&"sword"), Items.Rarity.EPIC, 5)
	check(plain.can_sell() and plain.can_disenchant(), "an ordinary Epic sells and disenchants")


func test_greed_pays_five_times_the_epic_price_of_the_wave() -> void:
	for wave in [10, 15, 25]:
		var item := _artifact(&"mage", wave)
		check_eq(item.greed_value(), roundi(ItemGenerator.price_for(Items.Rarity.EPIC, wave) * 5.0), "wave %d" % wave)
	check_eq(_artifact(&"mage", 10).greed_value(), 775, "about 770 gold on wave 10 (GDD)")
	var odd := _artifact(&"mage", 10)
	odd.buy_price = 1
	check_eq(odd.greed_value(), 775, "independent of the stored buy price: it is the Epic price of the wave x5")
	var epic := ItemInstance.from_weapon(Db.get_weapon(&"sword"), Items.Rarity.EPIC, 10)
	epic.buy_price = ItemGenerator.price_for(Items.Rarity.EPIC, 10)
	check_eq(epic.greed_value(), roundi(epic.buy_price * Items.GREED_SHARE), "other items keep the old share")


func test_generate_with_the_artifact_rarity_makes_the_class_artifact() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var mage := Db.get_class_data(&"mage")
	var item := ItemGenerator.generate(ItemGenerator.Source.BOSS, 12, rng,
			{&"rarity": Items.Rarity.ARTIFACT, &"usable_by": mage})
	check_eq(item.source_id, &"staff_of_the_frostwyrm", "the Mage's")
	var via_team := ItemGenerator.generate(ItemGenerator.Source.BOSS, 12, rng,
			{&"rarity": Items.Rarity.ARTIFACT, &"team_classes": [Db.get_class_data(&"rogue")] as Array[ClassData]})
	check_eq(via_team.source_id, &"fangs_of_the_shadow", "else the first team class that has one")
	var none := ItemGenerator.generate(ItemGenerator.Source.BOSS, 12, rng, {&"rarity": Items.Rarity.ARTIFACT})
	check_eq(none.rarity, Items.Rarity.LEGENDARY, "no class: a Legendary instead")


# --- Growth -----------------------------------------------------------------------------

func test_growth_adds_3_item_level_and_4_percent_weapon_damage() -> void:
	var item := _artifact(&"warrior", 10)
	var base := item.weapon.base_damage
	var ilvl := item.item_level
	for n in range(1, 6):
		check(Artifacts.grow_item(item), "grows")
		check_eq(item.artifact_waves, n, "wave ends held")
		check_eq(item.item_level, ilvl + 3 * n, "+3 Item Level per wave end")
		check_near(item.weapon.base_damage, base * (1.0 + 0.04 * n), 0.0001, "+4%% of the pickup damage (linear), n=%d" % n)
	check(not Artifacts.grow_item(ItemInstance.from_weapon(Db.get_weapon(&"sword"))), "only Artifacts grow")


func test_growth_applies_to_the_equipped_and_the_backpack_artifact() -> void:
	var eq := _equipment(&"warrior")
	var bag := _artifact(&"warrior")
	eq.backpack.append(bag)
	check_eq(Artifacts.grow(eq), 1, "one Artifact held (in the backpack)")
	check_eq(bag.artifact_waves, 1, "the backpack one grew")
	check(eq.equip(bag), "equip it")
	check_eq(Artifacts.grow(eq), 1, "equipped now")
	check_eq(bag.artifact_waves, 2, "grew again")
	var plain := _equipment(&"mage")
	check_eq(Artifacts.grow(plain), 0, "nothing to grow without an Artifact")


func test_a_player_grows_its_artifact_at_every_wave_end() -> void:
	world.free()
	world = Fakes.make_world(tree)
	var p := Fakes.spawn_player(world, 0, &"warrior")
	var item := _artifact(&"warrior")
	p.equipment.backpack.append(item)
	var base := item.weapon.base_damage
	var changes := [0]
	p.equipment.changed.connect(func() -> void: changes[0] += 1)
	p.end_wave()
	check_eq(item.artifact_waves, 1, "wave_ended grew it (backpack counts)")
	check_eq(changes[0], 1, "the equipment was re-applied once")
	p.begin_wave()
	check_eq(item.artifact_waves, 1, "a wave start does not grow it")
	p.end_wave()
	check_eq(item.artifact_waves, 2, "again at the next wave end")
	check_near(item.weapon.base_damage, base * 1.08, 0.0001, "+8% after two")
	var plain := Fakes.spawn_player(world, 1, &"mage")
	var before: int = changes[0]
	plain.end_wave()
	check_eq(changes[0], before, "no growth, no re-apply for ordinary gear")


func test_properties_awaken_after_three_and_six_wave_ends() -> void:
	var item := _artifact(&"warrior")
	check_eq(Artifacts.awake_count(item), 0, "asleep at pickup")
	check_eq(Artifacts.waves_left(item, 0), 3, "property 1 in 3 waves")
	check_eq(Artifacts.waves_left(item, 1), 6, "property 2 in 6 waves")
	for i in 2:
		Artifacts.grow_item(item)
	check_eq(Artifacts.awake_count(item), 0, "still asleep after 2")
	Artifacts.grow_item(item)
	check_eq(Artifacts.awake_count(item), 1, "property 1 after 3")
	check(Artifacts.is_awake(item, 0) and not Artifacts.is_awake(item, 1), "the first only")
	check_eq(Artifacts.waves_left(item, 1), 3, "property 2 in 3 more")
	for i in 3:
		Artifacts.grow_item(item)
	check_eq(Artifacts.awake_count(item), 2, "both after 6")
	check_eq(Artifacts.waves_left(item, 1), 0, "nothing left to wait for")
	check_eq(Artifacts.awakens_text(1), "Awakens in 1 wave", "singular")
	check_eq(Artifacts.awakens_text(3), "Awakens in 3 waves", "plural")


func test_effects_come_only_from_equipped_awake_properties() -> void:
	var eq := _equipment(&"warrior")
	var item := _artifact(&"warrior")
	eq.backpack.append(item)
	for i in 6:
		Artifacts.grow_item(item)
	check(Artifacts.effects_for(eq).is_empty(), "a backpack Artifact gives nothing")
	check(eq.equip(item), "equipped")
	var all := Artifacts.effects_for(eq)
	check_eq(all.size(), 2, "both properties of the Earthsplitter")
	check_eq(all[0]["id"], "artifact:earthsplitter:0", "tagged with the property")
	check_eq(all[1]["id"], "artifact:earthsplitter:1", "tagged with the property")
	item.artifact_waves = 3
	check_eq(Artifacts.effects_for(eq).size(), 1, "only property 1 at 3 wave ends")
	item.artifact_waves = 2
	check(Artifacts.effects_for(eq).is_empty(), "none before")
	for id in Db.artifacts:
		var data: ArtifactData = Db.artifacts[id]
		var eq2 := _equipment(data.class_id)
		var it := ItemGenerator.from_artifact(data, 10)
		eq2.backpack.append(it)
		check(eq2.equip(it), "%s equips" % id)
		it.artifact_waves = 6
		for e in Artifacts.effects_for(eq2):
			check_eq(BonusVocabulary.validate(e, data.class_id), "", "%s: %s" % [id, e.get("id")])


## The compact tooltip of a player's panel shows each property's short text (Artifacts.SHORT_TEXT_MAX
## characters at most – two tooltip lines): every shipped property has one, shorter than its text.
func test_every_property_has_a_short_text_for_the_compact_tooltip() -> void:
	var seen := 0
	for data: ArtifactData in Db.artifacts.values():
		for i in data.properties.size():
			var p := data.properties[i]
			var short := str(p.get("short", ""))
			check(short != "", "%s property %d has a short text" % [data.id, i + 1])
			check(short.length() <= Artifacts.SHORT_TEXT_MAX, "%s property %d: short text %d characters" % [data.id, i + 1, short.length()])
			check(short.length() <= str(p["text"]).length(), "%s property %d: not longer than the full text" % [data.id, i + 1])
			seen += 1
	check_eq(seen, 2 * Db.artifacts.size(), "two properties per Artifact")


func test_validate_wants_a_short_text() -> void:
	var data := Db.artifact_for_class(&"warrior").duplicate(true) as ArtifactData
	check_eq(Artifacts.validate(data), "", "the shipped data is valid")
	var props := data.properties.duplicate(true)
	props[1].erase("short")
	data.properties = props
	check("short text" in Artifacts.validate(data), "a property without one: %s" % Artifacts.validate(data))
	props[1]["short"] = "x".repeat(Artifacts.SHORT_TEXT_MAX + 1)
	data.properties = props
	check("short text" in Artifacts.validate(data), "one that is too long")
	props[1]["short"] = "x".repeat(Artifacts.SHORT_TEXT_MAX)
	data.properties = props
	check_eq(Artifacts.validate(data), "", "exactly the limit is fine")


func test_property_rows_carry_the_short_text_and_fall_back_to_the_full_one() -> void:
	var item := _artifact(&"warrior")
	var rows := Artifacts.property_rows(item)
	var data := Artifacts.data_of(item)
	check_eq(rows[0]["short"], data.properties[0]["short"], "the short text")
	check_eq(rows[0]["text"], data.properties[0]["text"], "next to the full one")
	var bare := data.duplicate(true) as ArtifactData
	var props := bare.properties.duplicate(true)
	props[0].erase("short")
	bare.properties = props
	var saved := Db.artifacts[data.id]
	Db.artifacts[data.id] = bare
	var fallback := Artifacts.property_rows(item)
	Db.artifacts[data.id] = saved
	check_eq(fallback[0]["short"], data.properties[0]["text"], "no short text: the full one")


func test_property_rows_report_sleeping_awake_and_missing_abilities() -> void:
	var item := _artifact(&"warrior")
	var rows := Artifacts.property_rows(item)
	check_eq(rows.size(), 2, "two rows")
	check_eq(rows[0]["state"], Artifacts.STATE_ASLEEP, "asleep")
	check_eq(rows[0]["waves_left"], 3, "3")
	check_eq(rows[1]["waves_left"], 6, "6")
	check_eq(rows[0]["needs"], "Whirlwind", "the ability's display name")
	check_eq(rows[1]["needs"], "Charge", "Charge")
	item.artifact_waves = 6
	world.free()
	world = Fakes.make_world(tree)
	var warrior := Fakes.spawn_player(world, 0, &"warrior")
	var mage := Fakes.spawn_player(world, 1, &"mage")
	for row in Artifacts.property_rows(item, warrior):
		check_eq(row["state"], Artifacts.STATE_AWAKE, "a Warrior knows Whirlwind and Charge")
	for row in Artifacts.property_rows(item, mage):
		check_eq(row["state"], Artifacts.STATE_NEEDS_ABILITY, "a hero without the ability: greyed")


# --- The Fangs of the Shadow pair -------------------------------------------------------

func _fangs() -> ItemInstance:
	return _artifact(&"rogue")


func test_the_fangs_are_two_pieces_that_count_as_one_artifact() -> void:
	var fangs := _fangs()
	check(fangs.companion != null and fangs.companion.pair_off, "a main-hand piece with an off-hand piece")
	check(fangs.companion.is_artifact() and fangs.companion.is_weapon(), "both are Artifact daggers")
	check_eq(fangs.weapon.weapon_type, &"dagger", "dagger")
	check_eq(fangs.companion.weapon.weapon_type, &"dagger", "dagger")
	check(not fangs.pair_off, "the main piece is not the off piece")
	var eq := _equipment(&"rogue")
	eq.backpack.append(fangs)
	check_eq(Artifacts.held(eq).size(), 1, "held once")
	check_eq(eq.backpack.size(), 1, "one backpack slot")
	check_eq(Artifacts.grow(eq), 1, "grows as one Artifact")
	check_eq(fangs.artifact_waves, 1, "the main piece")
	check_eq(fangs.companion.artifact_waves, 1, "and the off piece")
	check_eq(fangs.companion.item_level, fangs.item_level, "same Item Level")


func test_the_pair_equips_into_both_hands_as_one_backpack_item() -> void:
	var eq := _equipment(&"rogue")
	var fangs := _fangs()
	eq.backpack.append(fangs)
	check_eq(eq.target_slots(fangs), [Items.EquipSlot.MAIN_HAND] as Array[Items.EquipSlot], "equips via the main hand")
	check(eq.target_slots(fangs.companion).is_empty(), "the off piece never equips on its own")
	check(not eq.can_equip(fangs.companion), "cannot equip the off piece alone")
	check(eq.equip(fangs), "equip the pair")
	check(eq.get_item(Items.EquipSlot.MAIN_HAND) == fangs, "main hand")
	check(eq.get_item(Items.EquipSlot.OFF_HAND) == fangs.companion, "off hand")
	check_eq(eq.backpack.size(), 2, "the two starting daggers it displaced")
	check(fangs not in eq.backpack and fangs.companion not in eq.backpack, "the pair itself is out of the backpack")
	check(eq.is_armed(), "armed")
	check(eq.is_equipped(fangs) and eq.is_equipped(fangs.companion), "both are equipped")
	check(eq.pair_main_of(fangs.companion) == fangs, "the main piece of the off piece")


func test_take_removes_the_whole_pair_and_unequip_goes_through_either_piece() -> void:
	var eq := _equipment(&"rogue")
	var fangs := _fangs()
	eq.backpack.append(fangs)
	check(eq.equip(fangs), "equip")
	# unequip() of a last weapon is refused (the hero is never unarmed) - from either hand.
	check(not eq.unequip(Items.EquipSlot.MAIN_HAND), "not the last weapon: main hand")
	check(not eq.unequip(Items.EquipSlot.OFF_HAND), "not the last weapon: off hand")
	check(eq.take(fangs), "an internal move takes it")
	check(eq.get_item(Items.EquipSlot.MAIN_HAND) == null and eq.get_item(Items.EquipSlot.OFF_HAND) == null,
			"both hands empty: the off piece left with it")
	check(fangs not in eq.backpack and fangs.companion not in eq.backpack, "and neither is in the backpack")


func test_the_pair_is_the_last_weapon_as_a_whole() -> void:
	var eq := _equipment(&"rogue")
	var fangs := _fangs()
	eq.backpack.append(fangs)
	check(eq.equip(fangs), "equip")
	eq.backpack.clear()
	check(eq.is_last_weapon(fangs), "the pair is the only weapon")
	check(eq.is_last_weapon(fangs.companion), "from the off hand too")
	check(not eq.unequip(Items.EquipSlot.OFF_HAND), "so it cannot be unequipped without another weapon")
	check(eq.get_item(Items.EquipSlot.MAIN_HAND) == fangs, "still equipped")


func test_replacing_either_piece_pushes_out_the_whole_pair() -> void:
	var eq := _equipment(&"rogue")
	var fangs := _fangs()
	eq.backpack.append(fangs)
	check(eq.equip(fangs), "equip")
	var sword := ItemInstance.from_weapon(Db.get_weapon(&"sword"), Items.Rarity.RARE, 5)
	eq.backpack.append(sword)
	var before := eq.backpack.size()
	check(eq.equip(sword, Items.EquipSlot.MAIN_HAND), "a sword in the main hand")
	check(fangs in eq.backpack, "the pair goes back as the main piece")
	check(fangs.companion not in eq.backpack, "never as a loose off-hand dagger")
	check(eq.get_item(Items.EquipSlot.OFF_HAND) == null, "the off hand is empty")
	check_eq(eq.backpack.size(), before, "sword out, pair in: one slot each")
	# And the other way: an off-hand dagger over the pair.
	check(eq.equip(fangs), "equip the pair again")
	var dagger := ItemInstance.from_weapon(Db.get_weapon(&"dagger"), Items.Rarity.RARE, 5)
	eq.backpack.append(dagger)
	check(eq.equip(dagger, Items.EquipSlot.OFF_HAND), "a dagger into the off hand")
	check(fangs in eq.backpack and fangs.companion not in eq.backpack, "the pair left as one item")
	check(eq.get_item(Items.EquipSlot.MAIN_HAND) == null, "the main hand emptied with it")
	check(eq.get_item(Items.EquipSlot.OFF_HAND) == dagger, "the new dagger in the off hand")


func test_a_class_without_dual_wield_cannot_equip_the_pair() -> void:
	var fangs := _fangs()
	var warrior := _equipment(&"warrior")
	check(not fangs.can_be_used_by(Db.get_class_data(&"warrior")), "class restricted")
	fangs.class_restriction = &""
	var mage := _equipment(&"mage")
	check(mage.target_slots(fangs).is_empty(), "no dual wield: no slot")
	check(not mage.can_equip(fangs), "so no equip")
	check(warrior.can_equip(fangs), "a Warrior (dual wield, daggers) could")


func test_the_off_hand_piece_stats_apply_when_the_pair_is_worn() -> void:
	world.free()
	world = Fakes.make_world(tree)
	var p := Fakes.spawn_player(world, 0, &"rogue")
	var agi_before := p.stats.get_raw(Stats.AGILITY)
	var fangs := _fangs()
	p.equipment.backpack.append(fangs)
	check(p.equipment.equip(fangs), "equip")
	var both: float = fangs.stats.get(Stats.AGILITY, 0.0) + fangs.companion.stats.get(Stats.AGILITY, 0.0)
	check_near(p.stats.get_raw(Stats.AGILITY) - agi_before, both, 0.001, "both pieces' Agility")
	check_eq(p.weapons.size(), 2, "two weapon runners (main + off hand)")
	check(p.main_hand == fangs.weapon and p.off_hand == fangs.companion.weapon, "both daggers in hand")


# --- Drops ------------------------------------------------------------------------------

func test_no_roll_and_no_draw_below_wave_10() -> void:
	LootDrops.artifact_chance_override = 1.0
	var e := _enemy(true)
	RunState.set_wave(9)
	var before := RunState.rng.state
	check(LootDrops.roll_artifact(ItemGenerator.Source.BOSS, e, null) == null, "wave 9: nothing")
	check_eq(RunState.rng.state, before, "and no rng draw: old seeds stay comparable")
	RunState.set_wave(10)
	check(LootDrops.roll_artifact(ItemGenerator.Source.BOSS, e, null) != null, "wave 10: drops (chance 100%)")


func test_chances_by_source_and_fortune() -> void:
	check_near(LootDrops.artifact_chance(ItemGenerator.Source.BOSS, null), 0.15, 0.000001, "boss 15%")
	check_near(LootDrops.artifact_chance(ItemGenerator.Source.GOBLIN, null), 0.05, 0.000001, "Coin Gremlin 5%")
	check_near(LootDrops.artifact_chance(ItemGenerator.Source.ELITE, null), 0.02, 0.000001, "elite 2%")
	check_near(LootDrops.artifact_chance(ItemGenerator.Source.LOOT, null), 0.00025, 0.000001, "normal enemy 0.05% / 2 players (this run)")
	check_eq(LootDrops.artifact_chance(ItemGenerator.Source.SHOP, null), 0.0, "never from the shop")
	var lucky := _killer(100.0)
	check_near(LootDrops.artifact_chance(ItemGenerator.Source.BOSS, lucky), 0.30, 0.000001, "Fortune 100 doubles it")
	check_near(LootDrops.artifact_chance(ItemGenerator.Source.LOOT, lucky), 0.0005, 0.000001, "also the jackpot (0.025% x 2)")
	RunState.artifact_pity = 0.10
	check_near(LootDrops.artifact_chance(ItemGenerator.Source.BOSS, null), 0.25, 0.000001, "boss pity adds to the boss chance")
	check_near(LootDrops.artifact_chance(ItemGenerator.Source.ELITE, null), 0.02, 0.000001, "but not to the others")
	LootDrops.artifact_chance_override = 0.4
	check_near(LootDrops.artifact_chance(ItemGenerator.Source.LOOT, null), 0.4, 0.000001, "--artifact-chance replaces every chance")
	check_near(LootDrops.artifact_chance(ItemGenerator.Source.BOSS, lucky), 0.4, 0.000001, "Fortune too")
	LootDrops.artifact_chance_override = 7.0
	check_eq(LootDrops.artifact_chance(ItemGenerator.Source.LOOT, null), 1.0, "capped at 100%")


## The normal-kill chance is divided by the party size (kills scale with the players); the boss,
## Loot Goblin and elite chances are not.
func test_normal_kill_chance_is_divided_by_the_party_size() -> void:
	var lucky := _killer(100.0)
	for n in [1, 2, 3, 4]:
		RunState.start_run(n, 4711)
		RunState.set_wave(10)
		var expected := 0.0005 / float(n)
		check_near(LootDrops.normal_chance(), expected, 0.0000001, "%d player(s): 0.05%% / %d" % [n, n])
		check_near(LootDrops.artifact_chance(ItemGenerator.Source.LOOT, null), expected, 0.0000001, "%d player(s): a normal kill" % n)
		check_near(LootDrops.artifact_chance(ItemGenerator.Source.LOOT, lucky), expected * 2.0, 0.0000001, "%d player(s): Fortune still multiplies" % n)
		check_near(LootDrops.artifact_chance(ItemGenerator.Source.BOSS, null), 0.15, 0.0000001, "%d player(s): boss unchanged" % n)
		check_near(LootDrops.artifact_chance(ItemGenerator.Source.GOBLIN, null), 0.05, 0.0000001, "%d player(s): goblin unchanged" % n)
		check_near(LootDrops.artifact_chance(ItemGenerator.Source.ELITE, null), 0.02, 0.0000001, "%d player(s): elite unchanged" % n)
	LootDrops.artifact_chance_override = 0.4
	check_near(LootDrops.artifact_chance(ItemGenerator.Source.LOOT, null), 0.4, 0.0000001, "--artifact-chance is not divided")


func test_override_zero_never_drops_and_draws_nothing() -> void:
	LootDrops.artifact_chance_override = 0.0
	var bosses: Array[Enemy] = []
	for i in 20:
		bosses.append(_enemy(true))
	var before := RunState.rng.state
	for boss in bosses:
		check(LootDrops.roll_artifact(ItemGenerator.Source.BOSS, boss, null) == null, "never")
	check_eq(RunState.rng.state, before, "no draws")


func test_a_drop_makes_a_bag_with_the_artifact_and_counts() -> void:
	_join(&"mage")
	LootDrops.artifact_chance_override = 1.0
	var e := _enemy(true)
	var bag := LootDrops.roll_artifact(ItemGenerator.Source.BOSS, e, null)
	check(bag != null and bag.item.is_artifact(), "an Artifact bag")
	check(bag.is_in_group(&"loot_bags"), "in the loot_bags group")
	check_near(bag.global_position.x, e.global_position.x, 0.01, "where it died")
	check_eq(bag.item.item_level, 10 + 3 * 10 + 25, "Item Level of the drop wave")
	check_eq(RunState.artifacts_dropped, 1, "counted")
	check_eq(RunState.artifact_classes.size(), 1, "the class is taken")
	check_eq(RunState.artifact_classes[0], bag.item.class_restriction, "the item's class")
	check_eq(RunState.loot_drops_this_wave, 0, "not counted against the normal-drop cap")
	check_near(RunState.artifact_pity, 0.0, 0.000001, "pity stays at 0")


func test_one_kill_is_one_roll() -> void:
	LootDrops.artifact_chance_override = 1.0
	var elite := _enemy()
	check(LootDrops.roll_artifact(ItemGenerator.Source.ELITE, elite, null) != null, "the ELITE call rolls")
	check(LootDrops.roll_artifact(ItemGenerator.Source.LOOT, elite, null) == null, "the LOOT call after it does not")
	check_eq(RunState.artifacts_dropped, 1, "one Artifact")
	var boss := _enemy(true)
	var drops := 0
	for hero in 4:
		if LootDrops.roll_artifact(ItemGenerator.Source.BOSS, boss, null) != null:
			drops += 1
	check_eq(drops, 1, "a boss calling drop_special once per hero rolls once")
	LootDrops.artifact_chance_override = 0.5
	var before := RunState.rng.state
	var rolled := _enemy()
	LootDrops.roll_artifact(ItemGenerator.Source.LOOT, rolled, null)
	var after_first := RunState.rng.state
	for i in 3:
		LootDrops.roll_artifact(ItemGenerator.Source.LOOT, rolled, null)
	check_eq(RunState.rng.state, after_first, "repeated calls draw nothing more")
	check(after_first != before or LootDrops.artifact_candidates(false).is_empty(), "the first one drew")


func test_the_real_drop_paths_roll_once_per_kill() -> void:
	LootDrops.artifact_chance_override = 1.0
	var elite := _enemy()
	LootDrops.drop_special(ItemGenerator.Source.ELITE, elite, null)
	LootDrops.on_enemy_killed(elite, null)
	check_eq(RunState.artifacts_dropped, 1, "an elite's two calls: one Artifact")
	var boss := _enemy(true)
	for i in 3:
		LootDrops.drop_special(ItemGenerator.Source.BOSS, boss, null)
	LootDrops.on_enemy_killed(boss, null)
	check_eq(RunState.artifacts_dropped, 2, "a boss's four calls: one more Artifact")


func test_the_right_source_counts_boss_over_goblin_over_elite_over_normal() -> void:
	var boss := _enemy(true)
	var normal := _enemy()
	var S := ItemGenerator.Source
	check_eq(LootDrops.kill_artifact_source(boss, S.LOOT), S.BOSS, "a boss killed through the LOOT call is a boss")
	check_eq(LootDrops.kill_artifact_source(boss, S.ELITE), S.BOSS, "even through the ELITE call")
	check_eq(LootDrops.kill_artifact_source(normal, S.LOOT), S.LOOT, "a normal enemy")
	check_eq(LootDrops.kill_artifact_source(normal, S.ELITE), S.ELITE, "the call's source when it is higher")
	check_eq(LootDrops.kill_artifact_source(normal, S.GOBLIN), S.GOBLIN, "goblin")
	var goblin := LootGoblin.create(Db.get_enemy(&"loot_goblin"), 10)
	arena.entities.add_child(goblin)
	check_eq(LootDrops.kill_artifact_source(goblin, S.LOOT), S.GOBLIN, "the Coin Gremlin counts as a goblin")
	check_eq(LootDrops.kill_artifact_source(goblin, S.BOSS), S.BOSS, "never lower than the call")
	# The boss chance applies to a boss killed through the LOOT call.
	RunState.artifact_pity = 0.0
	var before := RunState.artifact_pity
	var misses := 0
	for i in 40:
		var b := _enemy(true)
		var was := RunState.artifact_pity
		var bag := LootDrops.roll_artifact(S.LOOT, b, null)
		if bag == null:
			misses += 1
			check_near(RunState.artifact_pity, was + 0.05, 0.000001, "a missed boss roll adds 5 points of pity")
		else:
			check_near(RunState.artifact_pity, 0.0, 0.000001, "a drop resets the pity")
		if LootDrops.artifact_candidates(false).is_empty():
			break
	check(misses > 0 or before == 0.0, "the sample missed at least once")


func test_pity_grows_per_boss_without_a_drop_and_resets_on_a_drop() -> void:
	RunState.start_run(1, 31)
	RunState.set_wave(10)
	var pity_seen: Array[float] = []
	var dropped := false
	for i in 60:
		var b := _enemy(true)
		var before := RunState.artifact_pity
		var bag := LootDrops.roll_artifact(ItemGenerator.Source.BOSS, b, null)
		if bag == null:
			check_near(RunState.artifact_pity, before + LootDrops.ARTIFACT_PITY_STEP, 0.000001, "miss: +5 points")
			pity_seen.append(RunState.artifact_pity)
		else:
			dropped = true
			check_near(RunState.artifact_pity, 0.0, 0.000001, "drop: back to 0")
			break
	check(dropped, "a boss dropped one within 60 tries (the pity guarantees it, seed 31)")


func test_class_pick_80_percent_the_team_20_percent_anyone() -> void:
	_join(&"warrior")
	var rng := RandomNumberGenerator.new()
	rng.seed = 123
	var team := 0
	var other := 0
	for i in 3000:
		var picked := LootDrops.pick_artifact_class(rng)
		if picked == &"warrior":
			team += 1
		else:
			other += 1
	# 80% the team's class + 20% any class that still has an Artifact to give (one in N of them the
	# Warrior): 0.8 + 0.2 / N (84% with five classes).
	var expected := 0.8 + 0.2 / float(Db.artifact_classes().size())
	check_near(float(team) / 3000.0, expected, 0.03, "the Warrior (the only team class) is picked ~%d%%" % roundi(expected * 100.0))
	check(other > 300, "other classes do come up")


func test_a_class_that_got_its_artifact_is_skipped_and_all_taken_means_no_drop() -> void:
	_join(&"warrior")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	RunState.artifact_classes.append(&"warrior")
	check(&"warrior" not in LootDrops.artifact_candidates(false), "the Warrior is out of the pool")
	check(LootDrops.artifact_candidates(true).is_empty(), "no team class left")
	for i in 200:
		check(LootDrops.pick_artifact_class(rng) != &"warrior", "never the taken class (the 80%% branch falls back to anyone)")
	for c in Db.class_ids:
		if c not in RunState.artifact_classes:
			RunState.artifact_classes.append(c)
	check_eq(LootDrops.pick_artifact_class(rng), &"", "all taken: no class")
	LootDrops.artifact_chance_override = 1.0
	var boss := _enemy(true)
	var before := RunState.rng.state
	check(LootDrops.roll_artifact(ItemGenerator.Source.BOSS, boss, null) == null, "so no more Artifact drops")
	check_eq(RunState.rng.state, before, "and no roll is made (no draw)")


func test_every_class_can_drop_once_and_only_once() -> void:
	for c in [&"warrior", &"mage"]:
		_join(c)
	LootDrops.artifact_chance_override = 1.0
	var seen: Array[StringName] = []
	var total := Db.artifact_classes().size()
	for i in total + 7:
		var bag := LootDrops.roll_artifact(ItemGenerator.Source.BOSS, _enemy(true), null)
		if bag == null:
			break
		check(bag.item.class_restriction not in seen, "%s dropped twice" % bag.item.class_restriction)
		seen.append(bag.item.class_restriction)
	check_eq(seen.size(), total, "one Artifact per class in total, then it stops")
	check_eq(RunState.artifacts_dropped, total, "counted")
	check(LootDrops.roll_artifact(ItemGenerator.Source.BOSS, _enemy(true), null) == null, "the next roll finds none")


func test_without_an_arena_the_artifact_goes_straight_to_the_team_loot() -> void:
	LootDrops.artifact_chance_override = 1.0
	var lone := Node3D.new()
	var bag := LootDrops.roll_artifact(ItemGenerator.Source.BOSS, lone, null)
	check(bag != null or RunState.team_loot.size() == 1, "an Artifact came out")
	lone.free()


# --- The Need / Greed / Pass roll -------------------------------------------------------

func test_need_only_for_the_class_and_greed_pays_the_artifact_price() -> void:
	var warrior := _join(&"warrior")
	var mage := _join(&"mage")
	world.add_child(Player.create(warrior))
	world.add_child(Player.create(mage))
	RunState.set_wave(10)
	var item := _artifact(&"warrior", 10)
	var roll := LootRoll.create(item)
	check(roll.can_need(warrior), "the Warrior may Need")
	check(not roll.can_need(mage), "the Mage may not")
	check_eq(roll.need_blocked_reason(mage), "Classes: Warrior", "the reason is shown")
	roll.choose(warrior.index, LootRoll.Choice.GREED)
	roll.choose(mage.index, LootRoll.Choice.GREED)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	roll.resolve(rng)
	var gold := RunState.gold
	roll.apply(PlayerManager.get_slots())
	check_eq(RunState.gold - gold, 775, "Greed on an Artifact: 5x the Epic price of wave 10")
	check_eq(RunState.greed_gold, 775, "counted as Greed gold")


func test_a_need_winner_gets_the_artifact_in_the_backpack() -> void:
	var warrior := _join(&"warrior")
	world.add_child(Player.create(warrior))
	var item := _artifact(&"warrior")
	var roll := LootRoll.create(item)
	roll.choose(warrior.index, LootRoll.Choice.NEED)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	roll.resolve(rng)
	roll.apply(PlayerManager.get_slots())
	check(item in (warrior.player as Player).equipment.backpack, "in the backpack")


func test_a_bot_needs_the_artifact_of_its_class_and_greeds_the_others() -> void:
	var warrior := _join(&"warrior")
	var mage := _join(&"mage")
	world.add_child(Player.create(warrior))
	world.add_child(Player.create(mage))
	var item := _artifact(&"warrior")
	check_eq(LootRoll.bot_choice(warrior, item), LootRoll.Choice.NEED, "its own class: Need")
	check_eq(LootRoll.bot_choice(mage, item), LootRoll.Choice.GREED, "another class: Greed")
	# Even when the Warrior already carries a far better-scoring Legendary two-hander.
	var eq := (warrior.player as Player).equipment
	var legendary := ItemInstance.from_weapon(Db.get_weapon(&"two_hand_axe"), Items.Rarity.LEGENDARY, 25)
	legendary.stats = {Stats.STRENGTH: 90.0, Stats.CRIT: 40.0}
	eq.slots[Items.EquipSlot.MAIN_HAND] = legendary
	check_eq(LootRoll.bot_choice(warrior, item), LootRoll.Choice.NEED, "still Need: an Artifact always replaces")
