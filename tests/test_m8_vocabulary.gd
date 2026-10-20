extends TestCase
## M8 P0 – the bonus vocabulary's M8 additions: the pseudo ids of the future classes (hunter_companion,
## shaman_totems: registered and valid before their classes have data) and the "proficiency" entry
## that grants dual wield at runtime (PlayerBonuses.has_proficiency -> Equipment.can_dual_wield), with
## a fake effect and a talent fixture.

const Fakes := preload("res://tests/player_fakes.gd")
const ClassFixtures := preload("res://tests/class_fixtures.gd")

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


