extends TestCase
## M8 P0 – the bonus vocabulary's M8 additions: the pseudo ids of the future classes (hunter_companion,
## shaman_totems: registered and valid before their classes have data) and the "proficiency" entry
## that grants dual wield at runtime (PlayerBonuses.has_proficiency -> Equipment.can_dual_wield), with
## a fake effect and a talent fixture.

const Fakes := preload("res://tests/player_fakes.gd")
const ClassFixtures := preload("res://tests/class_fixtures.gd")
const Support := preload("res://tests/test_loot_support.gd")
## A fake grant of dual wield and a stat that only counts while two attacking weapons are held.
const GRANT := {"kind": "proficiency", "grant": "dual_wield", "id": "zz_grant", "rank": 1}
const DUAL_MASTERY := {"kind": "stats", "stats": {"mastery": 5.0}, "requires": {"weapon": "dual_wield"}, "id": "zz_dual", "rank": 1}

var world: Node3D
var classes := ClassFixtures.new()


func before_each() -> void:
	RunState.start_run(1, 88)


func after_each() -> void:
	if world != null:
		Fakes.free_world(world)
		world = null
	classes.restore()
	Enemy.invalidate_player_cache()
	EnemyGrid.mark_dirty()


# --- Pseudo ids of the future classes ---------------------------------------------------------

func test_the_m8_pseudo_ids_validate_while_their_classes_have_no_data() -> void:
	var pairs := {&"hunter_companion": &"hunter", &"shaman_totems": &"shaman"}
	for id: StringName in pairs:
		var owner: StringName = pairs[id]
		check_eq(BonusVocabulary.PSEUDO_IDS.get(id), owner, "%s is registered for %s" % [id, owner])
		var entry := {"kind": "ability", "match": {"id": String(id)}, "mods": {"damage_bonus_add": 10, "anything_pct": 5}}
		check_eq(BonusVocabulary.validate(entry, owner), "", "%s validates for %s" % [id, owner])
		for other in Db.class_ids:
			if other != owner:
				check(BonusVocabulary.validate(entry, other) != "", "%s refused for %s" % [id, other])
		check(BonusVocabulary.validate(entry) != "", "%s refused without a class" % id)
		check(BonusVocabulary.matches_id({"id": String(id)}, id, owner), "%s: matches_id reaches it" % id)
		check(owner in Db.CLASS_ORDER, "%s: the class is in the class order" % owner)


# --- Dual wield from a bonus entry ------------------------------------------------------------

func test_the_proficiency_entry_is_validated() -> void:
	check_eq(BonusVocabulary.validate({"kind": "proficiency", "grant": "dual_wield"}, &"shaman"), "", "dual wield")
	check_eq(BonusVocabulary.validate({"kind": "proficiency", "grant": &"dual_wield", "rank": 2, "requires": {"weapon": "one_handed"}}), "",
			"rank, requires, StringName")
	check(BonusVocabulary.validate({"kind": "proficiency", "grant": "bow"}) != "", "only the grantable proficiencies")
	check(BonusVocabulary.validate({"kind": "proficiency"}) != "", "a grant is needed")
	check(BonusVocabulary.validate({"kind": "proficiency", "grant": "dual_wield", "pct": 5}) != "", "no other keys")
	for kind in BonusVocabulary.KINDS:
		check(BonusVocabulary.KIND_KEYS.has(kind), "%s has keys" % kind)
	check_eq(BonusVocabulary.resolve({"kind": "proficiency", "grant": "dual_wield"}, 3)["grant"], "dual_wield", "rank does not scale it")


func test_a_fake_effect_grants_dual_wield_and_taking_it_away_frees_the_off_hand() -> void:
	world = Fakes.make_world(tree)
	var mage := Fakes.spawn_player(world, 0, &"mage")
	var dagger := ItemInstance.from_weapon(Db.get_weapon(&"dagger"))
	check(not mage.class_data.can_dual_wield(), "the Mage has no dual wield of its own")
	check(not mage.equipment.can_dual_wield(), "so the equipment refuses")
	check_eq(mage.equipment.target_slots(dagger), [Items.EquipSlot.MAIN_HAND] as Array[Items.EquipSlot], "a one-hander: main hand only")
	check(not mage.bonuses.has_proficiency(&"dual_wield"), "nothing granted")
	# The fake effect (a talent or set bonus entry has the same shape).
	mage.bonuses.set_effects(&"zz_fake", [{"kind": "proficiency", "grant": "dual_wield", "id": "zz_fake", "rank": 1}])
	check(mage.bonuses.has_proficiency(&"dual_wield"), "the engine knows the grant")
	check_eq(mage.bonuses.granted_proficiencies(), [&"dual_wield"] as Array[StringName], "granted_proficiencies")
	check(mage.equipment.can_dual_wield(), "the equipment follows")
	check_eq(mage.equipment.target_slots(dagger), [Items.EquipSlot.MAIN_HAND, Items.EquipSlot.OFF_HAND] as Array[Items.EquipSlot],
			"a one-hander may go to either hand")
	check(mage.equipment.add_to_backpack(dagger), "in the bag")
	check(mage.equipment.equip(dagger, Items.EquipSlot.OFF_HAND), "equipped in the off hand")
	check(mage.off_hand == dagger.weapon and mage.weapons.size() == 2, "both hands attack")
	# The grant ends (a respec): the off-hand weapon goes back to the backpack, once.
	var changes := [0]
	mage.equipment.changed.connect(func() -> void: changes[0] += 1)
	mage.bonuses.set_effects(&"zz_fake", [])
	check(not mage.equipment.can_dual_wield(), "no longer")
	check(mage.equipment.get_item(Items.EquipSlot.OFF_HAND) == null, "the off hand is empty again")
	check(dagger in mage.equipment.backpack, "the dagger is in the backpack")
	check(mage.off_hand == null and mage.weapons.size() == 1, "one weapon attacks")
	check_eq(changes[0], 1, "one equipment change")
	# Without the grant a second one-hander is refused again.
	check(not mage.equipment.equip(dagger, Items.EquipSlot.OFF_HAND), "the off hand is closed")


func test_losing_dual_wield_with_nothing_in_the_main_hand_moves_the_weapon_there() -> void:
	var eq := Equipment.new(Db.get_class_data(&"mage"))
	var dagger := ItemInstance.from_weapon(Db.get_weapon(&"dagger"))
	eq.set_granted_proficiencies([&"dual_wield"] as Array[StringName])
	eq.slots[Items.EquipSlot.OFF_HAND] = dagger
	eq.set_granted_proficiencies([] as Array[StringName])
	check(eq.get_item(Items.EquipSlot.MAIN_HAND) == dagger, "the only weapon becomes the main hand")
	check(eq.get_item(Items.EquipSlot.OFF_HAND) == null and eq.backpack.is_empty(), "nothing left behind")
	# A full backpack: it stays where it is (nothing is lost, nothing is dropped).
	var eq2 := Equipment.new(Db.get_class_data(&"mage"))
	eq2.equip_starting_weapons()
	eq2.set_granted_proficiencies([&"dual_wield"] as Array[StringName])
	var off := ItemInstance.from_weapon(Db.get_weapon(&"dagger"))
	eq2.slots[Items.EquipSlot.OFF_HAND] = off
	for i in Items.BACKPACK_SIZE:
		eq2.backpack.append(ItemInstance.from_weapon(Db.get_weapon(&"sword")))
	eq2.set_granted_proficiencies([] as Array[StringName])
	check(eq2.get_item(Items.EquipSlot.OFF_HAND) == off, "no room: it stays")
	# A shield / tome in the off hand never needed dual wield.
	var eq3 := Equipment.new(Db.get_class_data(&"paladin"))
	eq3.equip_starting_weapons()
	eq3.set_granted_proficiencies([&"dual_wield"] as Array[StringName])
	eq3.set_granted_proficiencies([] as Array[StringName])
	check(eq3.get_item(Items.EquipSlot.OFF_HAND) != null, "the Paladin's shield stays")


func test_a_stranded_off_hand_weapon_neither_attacks_nor_counts_while_the_backpack_is_full() -> void:
	world = Fakes.make_world(tree)
	var mage := Fakes.spawn_player(world, 0, &"mage")
	var eq := mage.equipment
	var dagger := ItemInstance.from_weapon(Db.get_weapon(&"dagger"))
	dagger.stats[Stats.INTELLECT] = 7.0
	var plain_mastery := mage.stats.get_raw(Stats.MASTERY)
	var plain_intellect := mage.stats.get_raw(Stats.INTELLECT)
	mage.bonuses.set_effects(&"zz_fake", [GRANT, DUAL_MASTERY])
	check(eq.add_to_backpack(dagger), "in the bag")
	check(eq.equip(dagger, Items.EquipSlot.OFF_HAND), "equipped in the off hand")
	check(mage.off_hand == dagger.weapon and mage.weapons.size() == 2, "both hands attack")
	check_near(mage.stats.get_raw(Stats.MASTERY), plain_mastery + 5.0, 0.0001, "the dual wield condition holds")
	check_near(mage.stats.get_raw(Stats.INTELLECT), plain_intellect + 7.0, 0.0001, "the dagger's own stats count")
	while eq.has_space():
		eq.backpack.append(Support.make_armor(1))
	# The respec: nowhere to put the dagger.
	mage.bonuses.set_effects(&"zz_fake", [DUAL_MASTERY])
	check(not eq.can_dual_wield(), "no dual wield any more")
	check(eq.get_item(Items.EquipSlot.OFF_HAND) == dagger, "the dagger stays in the slot (nothing is lost)")
	check(eq.stranded_off_hand() == dagger, "but it is stranded")
	check(eq.off_weapon() == null, "the equipment does not count it as a weapon in use")
	check(mage.off_hand == null and mage.weapons.size() == 1, "it stops attacking: one runner, no off-hand weapon")
	check(not PlayerBonuses.weapon_requirement_met(mage, &"dual_wield"), "the dual_wield requirement is off")
	check_near(mage.stats.get_raw(Stats.MASTERY), plain_mastery, 0.0001, "so the talent entries that need it turn off")
	check_near(mage.stats.get_raw(Stats.INTELLECT), plain_intellect, 0.0001, "and the dagger's stats do not count")
	check(not eq.stat_sources().has(Items.source_for(Items.EquipSlot.OFF_HAND)), "no stat source for the stranded slot")
	# Taking the points again while it still sits there: it works again.
	mage.bonuses.set_effects(&"zz_fake", [GRANT, DUAL_MASTERY])
	check(eq.stranded_off_hand() == null, "no longer stranded")
	check(mage.off_hand == dagger.weapon and mage.weapons.size() == 2, "both hands attack again")
	check_near(mage.stats.get_raw(Stats.MASTERY), plain_mastery + 5.0, 0.0001, "the condition holds again")
	# Lost once more, then a sale frees a slot: the dagger goes into the backpack by itself.
	mage.bonuses.set_effects(&"zz_fake", [DUAL_MASTERY])
	check(eq.stranded_off_hand() == dagger and mage.weapons.size() == 1, "stranded again")
	var changes := [0]
	eq.changed.connect(func() -> void: changes[0] += 1)
	check(eq.remove_from_backpack(eq.backpack[0]), "sold a piece")
	check(eq.get_item(Items.EquipSlot.OFF_HAND) == null and dagger in eq.backpack, "room appeared: the dagger is in the backpack")
	check_eq(eq.backpack.size(), Items.BACKPACK_SIZE, "the sold slot is taken by the dagger")
	check_eq(changes[0], 1, "one equipment change")
	check(mage.off_hand == null and mage.weapons.size() == 1, "one weapon attacks")
	check_near(mage.stats.get_raw(Stats.MASTERY), plain_mastery, 0.0001, "no dual wield bonus")
	check(not eq.equip(dagger, Items.EquipSlot.OFF_HAND), "and the off hand is closed again")


func test_every_way_of_freeing_a_backpack_slot_puts_a_stranded_weapon_away() -> void:
	for how in ["sell", "take", "equip"]:
		var eq := Equipment.new(Db.get_class_data(&"mage"))
		eq.equip_starting_weapons()
		eq.set_granted_proficiencies([&"dual_wield"] as Array[StringName])
		var off := ItemInstance.from_weapon(Db.get_weapon(&"dagger"))
		eq.slots[Items.EquipSlot.OFF_HAND] = off
		var piece := Support.make_armor(1)
		eq.backpack.append(piece)
		while eq.has_space():
			eq.backpack.append(Support.make_armor(1))
		eq.set_granted_proficiencies([] as Array[StringName])
		check(eq.stranded_off_hand() == off and eq.off_weapon() == null, "%s: stranded" % how)
		check(not eq.settle_off_hand(), "%s: nothing changes while the backpack is full" % how)
		var changes := Support.count_signal(eq.changed)
		match how:
			"sell":
				check(eq.remove_from_backpack(piece), "sold")
			"take":
				check(eq.take(piece), "taken")
			"equip":
				check(eq.equip(piece), "the chest piece is worn")
		check(eq.get_item(Items.EquipSlot.OFF_HAND) == null, "%s: the off hand is empty" % how)
		check(off in eq.backpack, "%s: the weapon is in the backpack" % how)
		check_eq(eq.backpack.size(), Items.BACKPACK_SIZE, "%s: no item lost, none created" % how)
		check_eq(changes[0], 1, "%s: one change" % how)
		check(eq.stranded_off_hand() == null, "%s: nothing stranded" % how)


func test_a_stranded_off_hand_weapon_becomes_the_main_hand_when_the_main_hand_is_taken() -> void:
	var eq := Equipment.new(Db.get_class_data(&"mage"))
	eq.equip_starting_weapons()
	var main := eq.get_item(Items.EquipSlot.MAIN_HAND)
	eq.set_granted_proficiencies([&"dual_wield"] as Array[StringName])
	var off := ItemInstance.from_weapon(Db.get_weapon(&"dagger"))
	eq.slots[Items.EquipSlot.OFF_HAND] = off
	while eq.has_space():
		eq.backpack.append(Support.make_armor(1))
	eq.set_granted_proficiencies([] as Array[StringName])
	check(eq.stranded_off_hand() == off, "stranded")
	check(eq.take(main), "the main hand weapon is taken (forged away)")
	check(eq.get_item(Items.EquipSlot.MAIN_HAND) == off and eq.get_item(Items.EquipSlot.OFF_HAND) == null, "the hero is not left without a weapon")
	check(eq.main_weapon() == off.weapon, "and it attacks")


func test_a_shield_a_pair_and_a_classless_equipment_are_never_stranded() -> void:
	var paladin := Equipment.new(Db.get_class_data(&"paladin"))
	paladin.equip_starting_weapons()
	check(paladin.get_item(Items.EquipSlot.OFF_HAND) != null and paladin.stranded_off_hand() == null, "a shield needs no dual wield")
	check(paladin.off_weapon() != null, "and it counts")
	var rogue := Equipment.new(Db.get_class_data(&"rogue"))
	rogue.equip_starting_weapons()
	check(rogue.get_item(Items.EquipSlot.OFF_HAND) != null and rogue.stranded_off_hand() == null, "a Rogue has dual wield of its own")
	check(rogue.off_weapon() != null, "so the second dagger counts")
	var bare := Equipment.new()
	bare.slots[Items.EquipSlot.OFF_HAND] = ItemInstance.from_weapon(Db.get_weapon(&"dagger"))
	check(bare.stranded_off_hand() == null and bare.off_weapon() != null, "no class, no rule")


func test_a_talent_with_the_proficiency_entry_grants_dual_wield() -> void:
	# A fixture tree for the Mage (Db restored after): one talent whose effect is the grant.
	var talent := TalentData.new()
	talent.id = &"mage_zz_dual_grasp"
	talent.display_name = "Dual Grasp"
	talent.tier = 1
	talent.column = 0
	talent.max_rank = 1
	talent.effects = [{"kind": "proficiency", "grant": "dual_wield"}]
	var tree_data := TalentTreeData.new()
	tree_data.id = &"mage_zz_tree"
	tree_data.class_id = &"mage"
	tree_data.display_name = "Grasp"
	tree_data.index = 9
	tree_data.talents = [talent] as Array[TalentData]
	classes.add_tree(tree_data)
	check_eq(BonusVocabulary.validate(talent.effects[0], &"mage"), "", "the talent's entry is valid")
	RunState.start_run(1, 5)
	RunState.set_start_level(12)
	world = Fakes.make_world(tree)
	var mage := Fakes.spawn_player(world, 0, &"mage")
	check(not mage.equipment.can_dual_wield(), "before the point")
	check(mage.talents.add(talent.id), "the point is taken")
	check(mage.equipment.can_dual_wield(), "the talent grants dual wield")
	check(mage.talents.remove(talent.id), "and given back")
	check(not mage.equipment.can_dual_wield(), "so it ends")


