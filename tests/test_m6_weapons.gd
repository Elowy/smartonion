extends TestCase
## M6b CONTENT-W: the three new weapon types (Two-Hand Sword, Two-Hand Mace, Orb, GDD 4 / 5.8) –
## data, class proficiencies, the Orb as a passive off-hand (like the Tome), the generator, the
## procedural visuals and the three Forge Legendary effects actually firing.

const Fakes := preload("res://tests/player_fakes.gd")
const Content := preload("res://tests/test_items_gen_content.gd")
const ForgeTests := preload("res://tests/test_forge.gd")
const DT := 1.0 / 60.0

const NEW_IDS: Array[StringName] = [&"two_hand_sword", &"two_hand_mace", &"orb"]
## Who may use what (weapon id -> class ids), the rest may not.
const USERS := {
	&"two_hand_sword": [&"warrior", &"paladin"],
	&"two_hand_mace": [&"paladin", &"warrior"],
	&"orb": [&"mage", &"warlock"],
}

var world: Node3D
var rng: RandomNumberGenerator


func before_each() -> void:
	RunState.start_run(1, 77)
	Enemy.invalidate_player_cache()
	world = Fakes.make_world(tree)
	rng = RandomNumberGenerator.new()
	rng.seed = 6060


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	Enemy.invalidate_player_cache()
	EnemyGrid.mark_dirty()


func _hero(class_id: StringName, pos: Vector3 = Vector3.ZERO) -> Player:
	var p := Fakes.spawn_player(world, 0, class_id, pos)
	p.stats.set_source(&"tough", {Stats.STAMINA: 500.0})
	p.hp = p.max_hp()
	return p


func _fake(pos: Vector3) -> Fakes.FakeEnemy:
	var e := Fakes.spawn_enemy(world, pos)
	EnemyGrid.mark_dirty()
	return e


static func _has_proc(p: Player, id: StringName) -> bool:
	for proc in p.procs.procs:
		if proc.id == id:
			return true
	return false


## The Forge Legendary of [param weapon_id] as an equipped-ready item (two Epic bases forged).
func _legendary(weapon_id: StringName) -> ItemInstance:
	var a := ItemGenerator.generate_weapon(Db.get_weapon(weapon_id), Items.Rarity.EPIC, 14, false, rng)
	var b := ItemGenerator.generate_weapon(Db.get_weapon(weapon_id), Items.Rarity.EPIC, 15, false, rng)
	return Forge.make_result(a, b, rng)


# --- Data ----------------------------------------------------------------------------------

func test_three_new_weapons_are_loaded_with_valid_fields() -> void:
	check_eq(Db.weapons.size(), 13, "10 + 3 weapon base types")
	var proficiencies: Array[StringName] = []
	for id in Db.class_ids:
		proficiencies.append_array(Db.get_class_data(id).proficiencies)
	for id in NEW_IDS:
		var w := Db.get_weapon(id)
		check(w != null, "%s loaded" % id)
		if w == null:
			continue
		var label := String(id)
		check_eq(w.id, id, "%s: id" % label)
		check(w.display_name != "" and w.description != "", "%s: name and description" % label)
		check(w.weapon_type in proficiencies, "%s: some class can use the type" % label)
		check(w.base_price > 0 and w.color.a > 0.0, "%s: price and colour" % label)
		check(w.cooldown > 0.0, "%s: cooldown" % label)
		for stat in w.scaling:
			check(stat in Stats.ALL, "%s: scaling stat %s" % [label, stat])
		for stat in w.bonus_stats:
			check(stat in Stats.ALL, "%s: bonus stat %s" % [label, stat])
		check(w.weapon_type in WeaponModel.TYPES, "%s: a procedural 3D model" % label)
		check(w.weapon_type in ItemArt.WEAPON_SHAPES, "%s: an icon silhouette" % label)
		check(ItemTooltip.WEAPON_TYPE_NAMES.has(w.weapon_type), "%s: a tooltip type name" % label)
		for bad in Content.BANNED:
			check(not (w.display_name + " " + w.description).containsn(bad), "%s: no trademark (%s)" % [label, bad])
	var sword := Db.get_weapon(&"two_hand_sword")
	check(sword.is_two_handed() and sword.attacks() and sword.attack_kind == WeaponData.AttackKind.MELEE_ARC,
			"the Two-Hand Sword is a two-handed melee weapon")
	check(sword.scaling.has(Stats.STRENGTH) and not sword.is_magic(), "strength, physical")
	var mace := Db.get_weapon(&"two_hand_mace")
	check(mace.is_two_handed() and mace.attacks() and mace.stun_chance > 0.0, "the Two-Hand Mace stuns")
	check(mace.base_damage > Db.get_weapon(&"mace").base_damage, "heavier than the one-hander")
	var orb := Db.get_weapon(&"orb")
	check(orb.is_off_hand_only() and not orb.attacks() and orb.base_damage == 0.0, "the Orb is a passive off-hand")
	check(orb.bonus_stats.get(Stats.SPELL_POWER, 0.0) > 0.0, "spell-power-type stats")
	check(not orb.is_magic(), "the Orb has no school (it never attacks)")
	check(orb.block_chance == 0.0 and orb.scaling.is_empty(), "no block, no scaling")


func test_class_proficiencies_follow_the_gdd() -> void:
	for id in NEW_IDS:
		var w := Db.get_weapon(id)
		for class_id in Db.class_ids:
			var expected: bool = class_id in USERS[id]
			check_eq(Db.get_class_data(class_id).can_use(w), expected, "%s uses %s: %s" % [class_id, id, expected])
	# The old types stay as they were.
	check(Db.get_class_data(&"mage").can_use(Db.get_weapon(&"tome")), "the mage keeps the Tome")
	check(Db.get_class_data(&"paladin").can_use(Db.get_weapon(&"shield")), "the paladin keeps the Shield")
	check(not Db.get_class_data(&"rogue").can_use(Db.get_weapon(&"two_hand_axe")), "the rogue still has no axe")


# --- Equipment rules ------------------------------------------------------------------------

func test_orb_goes_into_the_off_hand_like_a_tome() -> void:
	var mage := Equipment.new(Db.get_class_data(&"mage"))
	mage.equip_starting_weapons()
	var orb := ItemInstance.from_weapon(Db.get_weapon(&"orb"))
	check(mage.can_equip(orb), "a mage can equip the Orb")
	check_eq(mage.target_slots(orb), [Items.EquipSlot.OFF_HAND] as Array[Items.EquipSlot], "off hand only")
	mage.add_to_backpack(orb)
	check(mage.equip(orb), "equipped")
	check_eq(mage.get_item(Items.EquipSlot.OFF_HAND), orb, "in the off hand")
	check(mage.get_item(Items.EquipSlot.MAIN_HAND) != null and mage.is_armed(), "the wand stays")
	# Next to a two-handed staff it would push the only weapon out: refused, like a Tome.
	var staff := ItemInstance.from_weapon(Db.get_weapon(&"staff"))
	mage.add_to_backpack(staff)
	check(mage.equip(staff), "a staff replaces wand and orb")
	check(mage.get_item(Items.EquipSlot.OFF_HAND) == null, "the off hand is free again")
	check(mage.equip_disarms(orb), "an Orb next to the staff would disarm the mage")
	check(not mage.equip(orb), "refused")
	var paladin := Equipment.new(Db.get_class_data(&"paladin"))
	check(not paladin.can_equip(orb), "a paladin cannot use the Orb")
	check_eq(orb.unusable_reason(Db.get_class_data(&"paladin")), "Cannot use Orb", "the reason")


func test_two_handers_replace_the_shield() -> void:
	var paladin := Equipment.new(Db.get_class_data(&"paladin"))
	paladin.equip_starting_weapons()
	check(paladin.get_item(Items.EquipSlot.OFF_HAND) != null, "the shield is worn")
	for id: StringName in [&"two_hand_sword", &"two_hand_mace"]:
		var item := ItemInstance.from_weapon(Db.get_weapon(id))
		check(paladin.can_equip(item), "the paladin can equip %s" % id)
		check_eq(paladin.target_slots(item), [Items.EquipSlot.MAIN_HAND] as Array[Items.EquipSlot], "%s: main hand" % id)
		paladin.add_to_backpack(item)
		check(paladin.equip(item), "%s equipped" % id)
		check_eq(paladin.get_item(Items.EquipSlot.MAIN_HAND), item, "%s in the main hand" % id)
		check(paladin.get_item(Items.EquipSlot.OFF_HAND) == null, "%s: the shield went to the backpack" % id)
		check(item.is_two_handed(), "%s is two-handed" % id)
	var rogue := Equipment.new(Db.get_class_data(&"rogue"))
	check(not rogue.can_equip(ItemInstance.from_weapon(Db.get_weapon(&"two_hand_sword"))), "a rogue cannot")


func test_equipped_orb_adds_spell_power_and_never_attacks() -> void:
	var p := _hero(&"mage")
	check_eq(p.weapons.size(), 1, "the wand attacks")
	var before := p.stats.get_raw(Stats.SPELL_POWER)
	var intellect := p.stats.get_raw(Stats.INTELLECT)
	var orb := ItemInstance.from_weapon(Db.get_weapon(&"orb"))
	p.equipment.add_to_backpack(orb)
	check(p.equipment.equip(orb), "equipped")
	check_eq(p.weapons.size(), 1, "the Orb has no auto-attack (still one weapon runner)")
	check_near(p.stats.get_raw(Stats.SPELL_POWER) - before, 4.0, 0.001, "+4 Spell Power")
	check_near(p.stats.get_raw(Stats.INTELLECT) - intellect, 1.0, 0.001, "+1 Intellect")
	p.equipment.unequip(Items.EquipSlot.OFF_HAND)
	check_near(p.stats.get_raw(Stats.SPELL_POWER), before, 0.001, "gone when taken off")


func test_two_hand_sword_attacks_in_a_wide_arc() -> void:
	var p := _hero(&"warrior")
	var item := ItemInstance.from_weapon(Db.get_weapon(&"two_hand_sword"))
	p.equipment.add_to_backpack(item)
	check(p.equipment.equip(item), "equipped")
	check_eq(p.weapons.size(), 1, "one runner")
	check_eq(p.main_hand.weapon_type, &"two_hand_sword", "the sword is in the main hand")
	var near := _fake(Vector3(2.4, 0, 0))
	var behind := _fake(Vector3(-2.0, 0, 0))
	p.facing = Vector3.RIGHT
	p.weapons[0].attack(near)
	check_eq(near.fake_hits(), 1, "hit in front")
	check_eq(behind.fake_hits(), 0, "not behind")


# --- Generator ------------------------------------------------------------------------------

func test_generator_rolls_the_new_weapons_only_for_their_classes() -> void:
	for class_id in [&"warrior", &"paladin", &"mage", &"warlock", &"rogue"]:
		var c := Db.get_class_data(class_id)
		var seen: Dictionary[StringName, int] = {}
		for i in 400:
			var item := ItemGenerator.generate(ItemGenerator.Source.LOOT, 1 + i % 25, rng,
					{&"usable_by": c, &"slot_type": Items.SlotType.WEAPON})
			check(item.is_weapon() and c.can_use(item.weapon), "%s can use %s" % [class_id, item.display_name])
			seen[item.weapon.id] = seen.get(item.weapon.id, 0) + 1
		for id in NEW_IDS:
			if class_id in USERS[id]:
				check(seen.get(id, 0) > 0, "%s is offered %s (%s)" % [class_id, id, seen])
			else:
				check(seen.get(id, 0) == 0, "%s is never offered %s" % [class_id, id])


func test_orb_names_and_stats_follow_the_generator_rules() -> void:
	var orb := Db.get_weapon(&"orb")
	var checked := 0
	for i in 60:
		var item := ItemGenerator.generate_weapon(orb, 1 + i % 4, 1 + i % 20, i % 2 == 0, rng)
		check(item.display_name.contains("Orb"), "named after the base: %s" % item.display_name)
		check_eq(item.weapon.base_damage, 0.0, "still no damage")
		check(not item.weapon.attacks(), "never attacks")
		check_eq(item.slot_type, Items.SlotType.WEAPON, "a weapon item")
		check(item.all_stats().get(Stats.SPELL_POWER, 0.0) >= 4.0, "keeps its Spell Power")
		checked += 1
	check_eq(checked, 60, "all sixty")


# --- Visuals --------------------------------------------------------------------------------

func test_procedural_models_build_for_the_new_weapons() -> void:
	for id in NEW_IDS:
		var w := Db.get_weapon(id)
		var model := WeaponModel.build(w)
		check(model != null and model.get_node_or_null(^"Mesh") != null, "%s: a mesh" % id)
		var mesh := (model.get_node(^"Mesh") as MeshInstance3D).mesh
		check(mesh != null and mesh.get_faces().size() > 0, "%s: some geometry" % id)
		check(WeaponModel.reach(w.weapon_type) != 0.5, "%s: its own reach" % id)
		check(OnionModel.grip_pose(w.weapon_type, false) != OnionModel.grip_pose(&"unknown_type", false),
				"%s: its own grip pose" % id)
		model.free()
	var orb_model := WeaponModel.build(Db.get_weapon(&"orb"))
	check(orb_model.get_node_or_null(^"Glow") != null, "the orb glows")
	orb_model.free()
	check_eq(ItemArt.shape_for(ItemInstance.from_weapon(Db.get_weapon(&"orb"))), &"orb", "orb icon")
	check_eq(ItemArt.shape_for(ItemInstance.from_weapon(Db.get_weapon(&"two_hand_mace"))), &"two_hand_mace", "maul icon")
	check_eq(ItemArt.shape_for(ItemInstance.from_weapon(Db.get_weapon(&"two_hand_sword"))), &"two_hand_sword", "greatsword icon")


# --- Forge Legendaries ----------------------------------------------------------------------

func test_every_new_weapon_has_its_own_legendary() -> void:
	check_eq(Forge.legendaries().size(), 13, "13 Legendary effects, one per weapon base")
	var names: Array[String] = []
	for id in Db.weapons:
		names.append(Forge.legendary_for(id).display_name)
	for id in NEW_IDS:
		var data := Forge.legendary_for(id)
		check(data != null, "%s has a Legendary" % id)
		if data == null:
			continue
		check_eq(data.weapon_id, id, "%s: keyed by the weapon" % id)
		check(names.count(data.display_name) == 1, "%s: a distinct name (%s)" % [id, data.display_name])
		check(data.unique_text != "" and data.flavor != "", "%s: text and flavor" % id)
		for bad in ForgeTests.FORBIDDEN_NAMES:
			check(not data.display_name.containsn(bad), "%s: no trademark (%s)" % [id, bad])
		for bad in Content.BANNED:
			check(not (data.display_name + " " + data.unique_text + " " + data.flavor).containsn(bad),
					"%s: no banned word (%s)" % [id, bad])
	var sword := Forge.legendary_for(&"two_hand_sword")
	check_eq(sword.unique_effect, &"bolt", "Thistlebrand: a barbed crescent")
	check_eq(int(sword.unique_params["every"]), 4, "every 4th hit")
	var mace := Forge.legendary_for(&"two_hand_mace")
	check_eq(mace.unique_effect, &"nova", "Boulderbloom: a ground slam")
	check_eq(String(mace.unique_params["at"]), "self", "around the wearer")
	var orb := Forge.legendary_for(&"orb")
	check_eq(String(orb.unique_params["trigger"]), "on_cast", "Tearglass: on spell casts (a passive off-hand)")
	check(not orb.unique_params.has("hit_pct"), "no hit to derive from")
	# Nothing is a hand-made item's name.
	for id in Db.uniques:
		check(names.count((Db.uniques[id] as UniqueItemData).display_name) == 0, "no clash with %s" % id)


func test_forged_epic_pairs_become_the_new_legendaries() -> void:
	for id in NEW_IDS:
		var item := _legendary(id)
		var data := Forge.legendary_for(id)
		check_eq(item.rarity, Items.Rarity.LEGENDARY, "%s: Legendary" % id)
		check_eq(item.display_name, data.display_name, "%s: its name" % id)
		check_eq(item.weapon.base_damage, Db.get_weapon(id).base_damage * 3.0, "%s: x3 base damage" % id)
		check_eq(item.enchants.size(), ItemGenerator.LEGENDARY_ENCHANTS, "%s: 2 enchants" % id)
		check(not Forge.is_forgeable(item), "%s: never forged again" % id)
		check(item.can_be_used_by(Db.get_class_data(USERS[id][0])), "%s: usable by its class" % id)


func test_thistlebrand_throws_a_crescent_on_every_fourth_hit() -> void:
	var p := _hero(&"warrior")
	var sword := _legendary(&"two_hand_sword")
	p.equipment.add_to_backpack(sword)
	check(p.equipment.equip(sword), "equipped")
	check(_has_proc(p, &"two_hand_sword"), "the Legendary effect joined the procs")
	var target := _fake(Vector3(2.0, 0, 0))
	for i in 3:
		p.procs._physics_process(1.0)
		p.procs.on_hit(target, 20.0, p.main_hand, false)
	check_eq(p.procs.fire_count(&"two_hand_sword"), 0, "three hits: nothing yet")
	var before := target.fake_hits()
	p.procs._physics_process(1.0)
	p.procs.on_hit(target, 20.0, p.main_hand, false)
	check_eq(p.procs.fire_count(&"two_hand_sword"), 1, "the 4th hit fires it")
	check(target.fake_hits() > before, "and the crescent hit the target")
	var dealt := target.fake_damage_log[before] if target.fake_damage_log.size() > before else 0.0
	check(dealt > 20.0 and dealt < 45.0, "about 150%% of the 20-damage hit (%s)" % dealt)
	for i in 4:
		p.procs._physics_process(1.0)
		p.procs.on_hit(target, 20.0, p.main_hand, false)
	check_eq(p.procs.fire_count(&"two_hand_sword"), 2, "again after four more hits")


func test_boulderbloom_slams_everything_around_the_wearer() -> void:
	var p := _hero(&"paladin")
	var mace := _legendary(&"two_hand_mace")
	p.equipment.add_to_backpack(mace)
	check(p.equipment.equip(mace), "equipped")
	var main := _fake(Vector3(2.0, 0, 0))
	var close := _fake(Vector3(-3.4, 0, 0))
	var far := _fake(Vector3(0, 0, 6.5))
	for i in 3:
		p.procs._physics_process(1.0)
		p.procs.on_hit(main, 30.0, p.main_hand, false)
	check_eq(p.procs.fire_count(&"two_hand_mace"), 0, "three hits: nothing yet")
	p.procs._physics_process(1.0)
	p.procs.on_hit(main, 30.0, p.main_hand, false)
	check_eq(p.procs.fire_count(&"two_hand_mace"), 1, "the 4th hit slams")
	check(main.fake_hits() >= 1 and close.fake_hits() == 1, "everything within 4 m of the wearer is hit")
	check_eq(far.fake_hits(), 0, "not the enemy 6.5 m away")


func test_tearglass_bursts_on_every_third_spell() -> void:
	var p := _hero(&"mage")
	var orb := _legendary(&"orb")
	check(orb.can_be_used_by(p.class_data), "a mage can use it")
	p.equipment.add_to_backpack(orb)
	check(p.equipment.equip(orb), "equipped in the off hand")
	check_eq(p.equipment.get_item(Items.EquipSlot.OFF_HAND), orb, "off hand")
	check_eq(p.weapons.size(), 1, "still only the wand attacks")
	var e := _fake(Vector3(2.0, 0, 0))
	var out_of_range := _fake(Vector3(0, 0, 7.0))
	var fireball := Db.get_ability(&"fireball")
	var blink := Db.get_ability(&"blink")
	p.procs.on_ability_cast(fireball)
	p.procs.on_ability_cast(blink)  # not a spell: does not count
	p.procs.on_ability_cast(fireball)
	check_eq(p.procs.fire_count(&"orb"), 0, "two spells: nothing yet")
	p.procs.on_ability_cast(Db.get_ability(&"blizzard"))
	check_eq(p.procs.fire_count(&"orb"), 1, "the 3rd spell bursts the orb")
	check_eq(e.fake_hits(), 1, "an enemy within 3.5 m is hit")
	check_eq(out_of_range.fake_hits(), 0, "one 7 m away is not")
	check(e.fake_damage_log[0] >= 45.0, "at least the base 45 damage (Spell Power adds) (%s)" % e.fake_damage_log[0])
	# The warlock can wield it as well.
	var lock := Equipment.new(Db.get_class_data(&"warlock"))
	check(lock.can_equip(orb), "a warlock can use it too")


# --- Epic weapons: +10% attack speed (GDD 4.1) ----------------------------------------------

func test_only_epic_weapons_get_the_attack_speed_bonus() -> void:
	check_eq(Items.WEAPON_RARITY_ATTACK_SPEED.size(), Items.RARITY_NAMES.size(), "one entry per rarity")
	for r in Items.RARITY_NAMES.size():
		var expected := 10.0 if r == Items.Rarity.EPIC else 0.0
		check_eq(Items.WEAPON_RARITY_ATTACK_SPEED[r], expected, "%s: %s%%" % [Items.RARITY_NAMES[r], expected])
	for id in Db.weapons:
		var base: WeaponData = Db.weapons[id]
		check_eq(base.attack_speed_pct, 0.0, "%s: the data files carry no bonus" % id)
		for r in Items.RARITY_NAMES.size():
			var w := ItemInstance.scaled_weapon(base, r)
			var expected := 10.0 if r == Items.Rarity.EPIC and base.attacks() else 0.0
			check_eq(w.attack_speed_pct, expected, "%s (%s): attack speed" % [id, Items.RARITY_NAMES[r]])
			check_eq(base.attack_speed_pct, 0.0, "%s: the base is never touched" % id)
	var epic_sword := ItemInstance.scaled_weapon(Db.get_weapon(&"sword"), Items.Rarity.EPIC)
	check_near(epic_sword.attack_speed_mult(), 1.1, 0.0001, "x1.1")
	check_near(epic_sword.effective_cooldown(), 0.9 / 1.1, 0.0001, "0.9 s -> 0.82 s")
	check_eq(epic_sword.cooldown, 0.9, "the base cooldown stays")
	var tome := ItemInstance.scaled_weapon(Db.get_weapon(&"tome"), Items.Rarity.EPIC)
	check_eq(tome.attack_speed_pct, 0.0, "a passive off-hand has no attacks to speed up")


func test_epic_speed_multiplies_with_haste_in_the_weapon_cooldown() -> void:
	var stats := StatBlock.new()
	var common := ItemInstance.scaled_weapon(Db.get_weapon(&"sword"), Items.Rarity.COMMON)
	var epic := ItemInstance.scaled_weapon(Db.get_weapon(&"sword"), Items.Rarity.EPIC)
	check_near(CombatMath.weapon_cooldown(common, stats), 0.9, 0.0001, "Common: 0.9 s")
	check_near(CombatMath.weapon_cooldown(epic, stats), 0.9 / 1.1, 0.0001, "Epic: 10% faster")
	stats.set_source(&"test", {Stats.HASTE: 20.0})
	check_near(CombatMath.weapon_cooldown(common, stats), 0.9 / 1.2, 0.0001, "Common with 20% Haste")
	check_near(CombatMath.weapon_cooldown(epic, stats), 0.9 / (1.2 * 1.1), 0.0001, "Epic with 20% Haste: both count")
	# Attack / Spell Power per hit is normalised to the base cooldown, so the bonus is real speed.
	stats.set_source(&"power", {Stats.ATTACK_POWER: 10.0})
	check_near(CombatMath.weapon_power_bonus(epic, stats), CombatMath.weapon_power_bonus(common, stats), 0.0001,
			"Attack Power per hit is the same")


func test_epic_weapon_attacks_ten_percent_more_often() -> void:
	var counts: Array[int] = []
	for rarity in [Items.Rarity.RARE, Items.Rarity.EPIC]:
		var p := _hero(&"warrior")
		var sword := ItemGenerator.generate_weapon(Db.get_weapon(&"sword"), rarity, 5, false, rng)
		p.equipment.add_to_backpack(sword)
		check(p.equipment.equip(sword, Items.EquipSlot.MAIN_HAND), "equipped in the main hand")
		check_eq(p.weapons.size(), 1, "one runner")
		var target := _fake(Vector3(1.5, 0, 0))
		var runner := p.weapons[0]
		var attacks := 0
		for i in 60 * 120:
			if runner.tick(DT):
				attacks += 1
		counts.append(attacks)
		check(target.fake_hits() >= attacks, "the target was hit")
		target.free()
		p.free()
		EnemyGrid.mark_dirty()
	check(counts[0] > 120, "a Rare sword attacks every 0.9 s (%d)" % counts[0])
	check_near(float(counts[1]) / float(counts[0]), 1.1, 0.03, "Epic: 10%% more attacks (%d vs %d)" % [counts[1], counts[0]])


func test_forged_and_hand_made_epics_keep_the_bonus_and_legendaries_do_not() -> void:
	var a := ItemGenerator.generate_weapon(Db.get_weapon(&"mace"), Items.Rarity.RARE, 9, false, rng)
	var b := ItemGenerator.generate_weapon(Db.get_weapon(&"mace"), Items.Rarity.RARE, 9, false, rng)
	var epic := Forge.make_result(a, b, rng)
	check_eq(epic.rarity, Items.Rarity.EPIC, "forged Epic")
	check_eq(epic.weapon.attack_speed_pct, 10.0, "Rare + Rare -> Epic: +10% attack speed")
	var legendary := Forge.make_result(epic, ItemGenerator.generate_weapon(Db.get_weapon(&"mace"), Items.Rarity.EPIC, 9, false, rng), rng)
	check_eq(legendary.rarity, Items.Rarity.LEGENDARY, "forged Legendary")
	check_eq(legendary.weapon.attack_speed_pct, 0.0, "the Legendary row has no attack speed bonus")
	var frostfang := ItemGenerator.from_unique(Db.get_unique(&"frostfang"), 5, false, rng)
	check_eq(frostfang.rarity, Items.Rarity.EPIC, "a hand-made Epic weapon")
	check_eq(frostfang.weapon.attack_speed_pct, 10.0, "gets it too (same rarity scaling)")
	var storm := ItemGenerator.from_unique(Db.get_unique(&"stormcaller"), 12, true, rng)
	check_eq(storm.weapon.attack_speed_pct, 0.0, "a hand-made Legendary does not")


## A refused weapon is named like its tooltip type line (the one that turns red for a caster): a
## mage refused the Two-Hand Sword reads "Cannot use 2H Sword", not "Cannot use Sword" or "Two Hand".
func test_refused_weapons_are_named_like_the_tooltip_type_line() -> void:
	var mage := Db.get_class_data(&"mage")
	var sword := ItemInstance.from_weapon(Db.get_weapon(&"two_hand_sword"))
	check_eq(sword.unusable_reason(mage), "Cannot use 2H Sword", "a mage is refused the 2H Sword")
	check_eq(ItemInstance.from_weapon(Db.get_weapon(&"two_hand_mace")).unusable_reason(mage), "Cannot use 2H Mace", "and the 2H Mace")
	check_eq(ItemTooltip.type_text(sword), "2H Sword", "the tooltip type line")
	for id in Db.weapons:
		var item := ItemInstance.from_weapon(Db.weapons[id])
		for class_id: StringName in [&"warrior", &"paladin", &"mage", &"warlock", &"rogue"]:
			var cls := Db.get_class_data(class_id)
			if not cls.can_use(item.weapon):
				check_eq(item.unusable_reason(cls), "Cannot use %s" % ItemTooltip.type_text(item), "%s for %s" % [id, class_id])


## The shop card's type line: "2H Sword" already says two-handed, so no second "(2H)"; a two-hand
## axe (type "Axe") keeps its "(2H)".
func test_shop_type_line_does_not_say_2h_twice() -> void:
	check_eq(ShopOfferCard.type_text(ItemInstance.from_weapon(Db.get_weapon(&"two_hand_sword"))), "2H Sword", "2H Sword")
	check_eq(ShopOfferCard.type_text(ItemInstance.from_weapon(Db.get_weapon(&"two_hand_mace"))), "2H Mace", "2H Mace")
	check_eq(ShopOfferCard.type_text(ItemInstance.from_weapon(Db.get_weapon(&"two_hand_axe"))), "Axe (2H)", "the axe keeps (2H)")
