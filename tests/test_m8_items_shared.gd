extends TestCase
## M8 ITEMS-SHARED – the three new weapon types (Crossbow, Polearm, Fist Weapon: data, who may use them,
## equipment rules, the quarrel projectile, visuals, sounds), their three Forge Legendaries (Bindweed,
## Barberry, Mossknuckle: the effects actually fire) and the five class-independent tier sets (Mendweave
## Attire, Slipskin Leathers, Hoardscale Mail, Redthorn Mail, Stonebark Plate: data, bonuses, roll
## eligibility with the 30% share, Black Market, bots, looks). The set-roll mechanism itself and its
## fixtures are test_m8_sets.gd; the Hunter / Shaman classes that wield the weapons come with their own
## packages, so the tests build a Warrior-based class with the proficiencies (ClassFixtures).

const Fakes := preload("res://tests/player_fakes.gd")
const Content := preload("res://tests/test_items_gen_content.gd")
const ForgeTests := preload("res://tests/test_forge.gd")
const Rules := preload("res://tests/content_rules.gd")
const ClassFixtures := preload("res://tests/class_fixtures.gd")
const SetFixtures := preload("res://tests/set_fixtures.gd")

const DT := 1.0 / 60.0
const NEW_IDS: Array[StringName] = [&"crossbow", &"polearm", &"fist_weapon"]
## The classes that wield each type once they exist (the HUNTER / SHAMAN packages); no other class does.
const USERS := {
	&"crossbow": [&"hunter"],
	&"polearm": [&"hunter"],
	&"fist_weapon": [&"shaman"],
}
## The five class-independent sets: id -> [display name, ClassData.ArmorType, one-word piece key].
const SETS := {
	&"mendweave_attire": ["Mendweave Attire", ClassData.ArmorType.CLOTH, "mendweave"],
	&"slipskin_leathers": ["Slipskin Leathers", ClassData.ArmorType.LEATHER, "slipskin"],
	&"hoardscale_mail": ["Hoardscale Mail", ClassData.ArmorType.MAIL, "hoardscale"],
	&"redthorn_mail": ["Redthorn Mail", ClassData.ArmorType.MAIL, "redthorn"],
	&"stonebark_plate": ["Stonebark Plate", ClassData.ArmorType.PLATE, "stonebark"],
}
const SLOT_KEYS: Array[String] = ["head", "shoulders", "chest", "hands", "legs"]

var world: Node3D
var rng: RandomNumberGenerator
var classes: ClassFixtures
var fixtures: SetFixtures


func before_each() -> void:
	RunState.start_run(1, 77)
	Enemy.invalidate_player_cache()
	world = Fakes.make_world(tree)
	rng = RandomNumberGenerator.new()
	rng.seed = 8080
	classes = ClassFixtures.new()
	fixtures = SetFixtures.new()
	ItemGenerator.independent_share_override = -1.0


func after_each() -> void:
	for p in tree.get_nodes_in_group(&"projectiles"):
		p.free()
	Fakes.free_world(world)
	world = null
	classes.restore()
	fixtures.restore()
	PlayerManager.clear()
	ItemGenerator.independent_share_override = -1.0
	Enemy.invalidate_player_cache()
	EnemyGrid.mark_dirty()


## A hero of a Warrior-based class that wields the new weapon types (and dual wields).
func _hero(pos: Vector3 = Vector3.ZERO, extra: Array[StringName] = []) -> Player:
	var cd := classes.add_class()
	cd.proficiencies = cd.proficiencies.duplicate()
	cd.proficiencies.append_array(NEW_IDS)
	cd.proficiencies.append_array(extra)
	var p := Fakes.spawn_player(world, 0, cd.id, pos)
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


func _equip(p: Player, item: ItemInstance, slot: int = -1) -> void:
	p.equipment.add_to_backpack(item)
	check(p.equipment.equip(item, slot) if slot >= 0 else p.equipment.equip(item), "%s equipped" % item.display_name)


# --- Weapons: data ----------------------------------------------------------------------------

func test_the_three_weapons_load_with_the_designed_fields() -> void:
	for id in NEW_IDS:
		var w := Db.get_weapon(id)
		check(w != null, "%s loaded" % id)
		if w == null:
			continue
		var label := String(id)
		check_eq(w.id, id, "%s: id" % label)
		check_eq(w.weapon_type, id, "%s: its own weapon type" % label)
		check(w.display_name != "" and w.description != "", "%s: name and description" % label)
		check(w.base_price > 0 and w.color.a > 0.0 and w.cooldown > 0.0 and w.base_damage > 0.0, "%s: price, colour, cooldown, damage" % label)
		check(w.attacks(), "%s attacks" % label)
		for stat in w.scaling:
			check(stat in Stats.ALL, "%s: scaling stat %s" % [label, stat])
		check(not w.is_magic(), "%s is physical" % label)
		for bad in Content.BANNED:
			check(not (w.display_name + " " + w.description).containsn(bad), "%s: no trademark (%s)" % [label, bad])
		# Every place a weapon type is named: model, reach, grip, silhouette, type name.
		check(w.weapon_type in WeaponModel.TYPES, "%s: a procedural 3D model" % label)
		check(WeaponModel.reach(w.weapon_type) != 0.5, "%s: its own reach" % label)
		check(OnionModel.grip_pose(w.weapon_type, false) != OnionModel.grip_pose(&"unknown_type", false), "%s: its own grip pose" % label)
		check(w.weapon_type in ItemArt.WEAPON_SHAPES, "%s: an icon silhouette" % label)
		check_eq(ItemArt.shape_for(ItemInstance.from_weapon(w)), id, "%s: shape_for" % label)
		check(ItemTooltip.WEAPON_TYPE_NAMES.has(w.weapon_type), "%s: a tooltip type name" % label)
	var crossbow := Db.get_weapon(&"crossbow")
	check(crossbow.is_two_handed() and crossbow.attack_kind == WeaponData.AttackKind.PROJECTILE, "the Crossbow is a two-handed projectile weapon")
	check_eq(crossbow.pierce, 2, "its bolt pierces two")
	check_near(crossbow.attack_range, 12.0, 0.001, "range 12 m")
	check(crossbow.cooldown >= 1.3, "slow (%s s)" % crossbow.cooldown)
	check(crossbow.base_damage > Db.get_weapon(&"bow").base_damage, "heavier than the bow")
	check(crossbow.scaling.has(Stats.AGILITY) and not crossbow.scaling.has(Stats.STRENGTH), "Agility")
	var polearm := Db.get_weapon(&"polearm")
	check(polearm.is_two_handed() and polearm.attack_kind == WeaponData.AttackKind.MELEE_ARC, "the Polearm is a two-handed melee weapon")
	check_near(polearm.attack_range, 3.2, 0.001, "reach 3.2 m")
	check_near(polearm.arc_degrees, 70.0, 0.001, "a narrow 70 degree sweep")
	check(polearm.scaling.has(Stats.AGILITY), "Agility")
	var fist := Db.get_weapon(&"fist_weapon")
	check(not fist.is_two_handed() and not fist.is_off_hand_only(), "the Fist Weapon is a one-hander")
	check(fist.attack_kind == WeaponData.AttackKind.MELEE_ARC and fist.attack_range < Db.get_weapon(&"dagger").attack_range, "melee, the shortest reach of the attacking weapons")
	check(fist.cooldown <= 0.6, "fast (%s s)" % fist.cooldown)
	check(fist.scaling.has(Stats.INTELLECT) and fist.scaling.has(Stats.AGILITY), "Intellect + Agility: it works for the Shaman")


func test_the_polearm_has_the_longest_melee_reach_and_the_fist_the_shortest() -> void:
	var polearm := Db.get_weapon(&"polearm")
	var fist := Db.get_weapon(&"fist_weapon")
	for id in Db.weapons:
		var w: WeaponData = Db.weapons[id]
		if w.attack_kind != WeaponData.AttackKind.MELEE_ARC or id == &"polearm":
			continue
		check(w.attack_range < polearm.attack_range, "%s (%s m) reaches less than the polearm" % [id, w.attack_range])
		if id != &"fist_weapon":
			check(w.attack_range > fist.attack_range, "%s reaches more than the fist weapon" % id)
	check(polearm.attack_range < BotInput.MELEE_REACH, "bots still treat the polearm as a melee weapon (under %s m)" % BotInput.MELEE_REACH)


func test_nobody_of_the_launch_wields_the_new_weapons_and_the_m8_classes_only_theirs() -> void:
	for id in NEW_IDS:
		var w := Db.get_weapon(id)
		for class_id in Rules.LAUNCH_CLASSES:
			check(not Db.get_class_data(class_id).can_use(w), "%s never uses %s" % [class_id, id])
		for class_id in Db.class_ids:
			var expected: bool = class_id in USERS[id]
			check_eq(Db.get_class_data(class_id).can_use(w), expected, "%s uses %s: %s" % [class_id, id, expected])


# --- Weapons: equipment rules -----------------------------------------------------------------

func test_the_fist_weapon_is_dual_wieldable_the_others_are_not() -> void:
	var cd := Db.get_class_data(&"rogue").duplicate() as ClassData
	cd.proficiencies = cd.proficiencies.duplicate()
	cd.proficiencies.append(&"fist_weapon")
	check(cd.can_dual_wield(), "the fixture class dual wields")
	var eq := Equipment.new(cd)
	var a := ItemInstance.from_weapon(Db.get_weapon(&"fist_weapon"))
	var b := ItemInstance.from_weapon(Db.get_weapon(&"fist_weapon"))
	check_eq(eq.target_slots(a), [Items.EquipSlot.MAIN_HAND, Items.EquipSlot.OFF_HAND] as Array[Items.EquipSlot], "main hand or off hand")
	eq.add_to_backpack(a)
	eq.add_to_backpack(b)
	check(eq.equip(a, Items.EquipSlot.MAIN_HAND), "one in the main hand")
	check(eq.equip(b, Items.EquipSlot.OFF_HAND), "one in the off hand")
	check(eq.get_item(Items.EquipSlot.MAIN_HAND) == a and eq.get_item(Items.EquipSlot.OFF_HAND) == b, "both held")
	# Without dual wield (the Shaman before its talent) only the main hand.
	cd.proficiencies.erase(&"dual_wield")
	var plain := Equipment.new(cd)
	check_eq(plain.target_slots(a), [Items.EquipSlot.MAIN_HAND] as Array[Items.EquipSlot], "no dual wield: the main hand only")
	plain.set_granted_proficiencies([&"dual_wield"] as Array[StringName])
	check_eq(plain.target_slots(a), [Items.EquipSlot.MAIN_HAND, Items.EquipSlot.OFF_HAND] as Array[Items.EquipSlot], "a granted dual wield opens the off hand")
	# The two-handers take both hands.
	for id in [&"crossbow", &"polearm"]:
		check_eq(eq.target_slots(ItemInstance.from_weapon(Db.get_weapon(id))), [Items.EquipSlot.MAIN_HAND] as Array[Items.EquipSlot], "%s: main hand only" % id)


func test_two_fist_weapons_both_attack() -> void:
	var p := _hero()
	_equip(p, ItemInstance.from_weapon(Db.get_weapon(&"fist_weapon")), Items.EquipSlot.MAIN_HAND)
	_equip(p, ItemInstance.from_weapon(Db.get_weapon(&"fist_weapon")), Items.EquipSlot.OFF_HAND)
	check_eq(p.weapons.size(), 2, "a runner per hand")
	var target := _fake(Vector3(1.3, 0, 0))
	p.facing = Vector3.RIGHT
	for r in p.weapons:
		r.attack(target)
	check_eq(target.fake_hits(), 2, "both hands hit the enemy 1.3 m away")


func test_the_generator_offers_each_type_only_to_a_class_that_can_use_it() -> void:
	var cd := classes.add_class()
	cd.proficiencies = cd.proficiencies.duplicate()
	cd.proficiencies.append_array(NEW_IDS)
	for class_id in [&"warrior", &"mage", &"rogue", cd.id]:
		var c := Db.get_class_data(class_id)
		var seen: Dictionary[StringName, int] = {}
		for i in 500:
			var item := ItemGenerator.generate(ItemGenerator.Source.LOOT, 1 + i % 25, rng,
					{&"usable_by": c, &"slot_type": Items.SlotType.WEAPON})
			check(item.is_weapon() and c.can_use(item.weapon), "%s can use %s" % [class_id, item.display_name])
			seen[item.weapon.id] = seen.get(item.weapon.id, 0) + 1
		for id in NEW_IDS:
			if c.can_use(Db.get_weapon(id)):
				check(seen.get(id, 0) > 0, "%s is offered %s (%s)" % [class_id, id, seen])
			else:
				check_eq(seen.get(id, 0), 0, "%s is never offered %s" % [class_id, id])


func test_item_names_follow_the_base() -> void:
	for id in NEW_IDS:
		for i in 12:
			var item := ItemGenerator.generate_weapon(Db.get_weapon(id), 1 + i % 4, 1 + i, i % 2 == 0, rng)
			check(item.display_name.contains(Db.get_weapon(id).display_name), "named after the base: %s" % item.display_name)
			check_eq(ShopOfferCard.type_text(item).replace(" (2H)", ""), Db.get_weapon(id).display_name, "%s: the type line" % item.display_name)
	check_eq(ShopOfferCard.type_text(ItemInstance.from_weapon(Db.get_weapon(&"crossbow"))), "Crossbow (2H)", "two-handed types say so")
	check_eq(ShopOfferCard.type_text(ItemInstance.from_weapon(Db.get_weapon(&"fist_weapon"))), "Fist Weapon", "a one-hander does not")


# --- Weapons: combat ---------------------------------------------------------------------------

func test_the_polearm_hits_inside_its_arc_and_reach_only() -> void:
	var p := _hero()
	_equip(p, ItemInstance.from_weapon(Db.get_weapon(&"polearm")))
	check_eq(p.weapons.size(), 1, "one runner")
	p.facing = Vector3.RIGHT
	var near := _fake(Vector3(3.4, 0, 0))
	var far := _fake(Vector3(3.9, 0, 0))
	var side := _fake(Vector3(1.5, 0, 1.6))  # 47 degrees off the facing, inside 2 m: outside the 70 degree sweep (+-35)
	var behind := _fake(Vector3(-2.0, 0, 0))
	p.weapons[0].attack(near)
	check_eq(near.fake_hits(), 1, "the enemy 3.4 m ahead is hit (3.2 m reach + its body)")
	check_eq(far.fake_hits(), 0, "the one 3.9 m away is not")
	check_eq(side.fake_hits(), 0, "not outside the narrow sweep")
	check_eq(behind.fake_hits(), 0, "not behind")
	# The warrior's two-hand sword (2.7 m) does not reach the enemy the polearm does.
	var q := Fakes.spawn_player(world, 1, &"warrior", Vector3(0, 0, 20))
	var sword := ItemInstance.from_weapon(Db.get_weapon(&"two_hand_sword"))
	q.equipment.add_to_backpack(sword)
	check(q.equipment.equip(sword), "sword equipped")
	q.facing = Vector3.RIGHT
	var e3 := Fakes.spawn_enemy(world, Vector3(3.4, 0, 20))
	EnemyGrid.mark_dirty()
	q.weapons[0].attack(e3)
	check_eq(e3.fake_hits(), 0, "a two-hand sword misses the enemy 3.4 m away")


func test_the_crossbow_fires_a_quarrel_that_passes_through_two_enemies() -> void:
	var p := _hero()
	_equip(p, ItemInstance.from_weapon(Db.get_weapon(&"crossbow")))
	check_eq(WeaponRunner.projectile_style(p.main_hand), &"quarrel", "the quarrel style")
	var a := _fake(Vector3(0, 0, -4))
	var b := _fake(Vector3(0, 0, -6))
	var c := _fake(Vector3(0, 0, -8))
	var d := _fake(Vector3(0, 0, -10))
	var off := _fake(Vector3(3, 0, -6))
	check(p.weapons[0].tick(DT), "the crossbow fires")
	var shots := tree.get_nodes_in_group(&"projectiles")
	check_eq(shots.size(), 1, "one bolt")
	var proj := shots[0] as Projectile
	check_eq(proj.style, &"quarrel", "its look")
	check_eq(proj.pierce, 2, "it pierces 2")
	check_eq(proj.color, Projectile.default_color(&"quarrel"), "its colour")
	check_near(proj.speed, 30.0, 0.001, "fast")
	for _i in 120:
		proj.advance(DT)
		if proj.is_done():
			break
	check_eq(a.fake_hits(), 1, "the first enemy is hit")
	check_eq(b.fake_hits(), 1, "the second")
	check_eq(c.fake_hits(), 1, "and the third: two enemies pierced")
	check_eq(d.fake_hits(), 0, "the fourth is not")
	check_eq(off.fake_hits(), 0, "an enemy off the line is not")
	check(proj.is_done(), "used up")
	var visual := ProjectileVisual.build(&"quarrel", Color.WHITE)
	check(visual.get_child_count() >= 4, "the quarrel has a shaft, a head, vanes, a streak (%d parts)" % visual.get_child_count())
	visual.free()
	check_eq(WeaponRunner.projectile_style(Db.get_weapon(&"bow")), &"arrow", "the bow keeps its arrow")


# --- Weapons: sounds ---------------------------------------------------------------------------

func test_the_new_weapons_pick_banked_sounds() -> void:
	check_eq(AudioIds.shot(Db.get_weapon(&"crossbow")), &"shot_crossbow", "crossbow shot")
	check_eq(AudioIds.swing(Db.get_weapon(&"polearm")), &"swing_heavy", "polearm: a two-hander swings heavy")
	check_eq(AudioIds.swing(Db.get_weapon(&"fist_weapon")), &"swing_light", "fist weapon: light")
	for id in [&"shot_crossbow", &"swing_heavy", &"swing_light"]:
		check(Audio.bank.sound(id) != null, "%s is in the bank" % id)
	var crossbow := Audio.bank.sound(&"shot_crossbow")
	var bow := Audio.bank.sound(&"shot_bow")
	check(crossbow != null and bow != null and crossbow.pitch < bow.pitch and crossbow.volume_db < bow.volume_db,
			"a lower, softer cousin of the bow shot")
	check_eq(AudioIds.shot(Db.get_weapon(&"bow")), &"shot_bow", "the bow keeps its own")
	check_eq(AudioIds.swing(Db.get_weapon(&"dagger")), &"swing_light", "the dagger keeps its own")


# --- Weapons: visuals --------------------------------------------------------------------------

func test_procedural_models_build_for_the_new_weapons() -> void:
	var reaches := {}
	for id in NEW_IDS:
		var w := Db.get_weapon(id)
		var model := WeaponModel.build(w)
		check(model != null and model.get_node_or_null(^"Mesh") != null, "%s: a mesh" % id)
		var mesh := (model.get_node(^"Mesh") as MeshInstance3D).mesh
		check(mesh != null and mesh.get_faces().size() > 0, "%s: some geometry" % id)
		# The model reaches about as far as WeaponModel.reach says (+-30%).
		var top := 0.0
		for v in mesh.get_faces():
			top = maxf(top, v.y)
		check_near(top, WeaponModel.reach(id), WeaponModel.reach(id) * 0.3, "%s: the model's top is its reach (%.2f)" % [id, top])
		reaches[id] = WeaponModel.reach(id)
		model.free()
	check(reaches[&"polearm"] > Db.get_weapon(&"two_hand_sword").attack_range * 0.5 and reaches[&"polearm"] > WeaponModel.reach(&"two_hand_sword"),
			"the polearm model is the longest weapon")
	check(reaches[&"fist_weapon"] < WeaponModel.reach(&"dagger"), "the fist weapon is the shortest")
	# On an onion: held in the grips, one in each hand for the fist weapon.
	var cd := Db.get_class_data(&"rogue")
	var m := OnionModel.new()
	world.add_child(m)
	m.setup(cd, Color.WHITE)
	m.set_weapons(Db.get_weapon(&"fist_weapon"), Db.get_weapon(&"fist_weapon"))
	check(m.find_children("Weapon_fist_weapon", "Node3D", true, false).size() == 2, "two fist weapons in hand")
	m.set_weapons(Db.get_weapon(&"crossbow"), null)
	check(m.find_children("Weapon_crossbow", "Node3D", true, false).size() == 1, "a crossbow in hand")
	m.set_weapons(Db.get_weapon(&"polearm"), null)
	check(m.find_children("Weapon_polearm", "Node3D", true, false).size() == 1, "a polearm in hand")


func test_item_art_draws_the_silhouettes() -> void:
	for id in NEW_IDS:
		var item := ItemInstance.from_weapon(Db.get_weapon(id))
		var icon := ItemIcon.new()
		icon.custom_minimum_size = Vector2(64, 64)
		world.add_child(icon)
		icon.set_item(item)
		check_eq(ItemArt.shape_for(item), id, "%s: its own silhouette" % id)
		icon.free()


# --- Forge Legendaries -------------------------------------------------------------------------

func test_every_weapon_has_exactly_one_legendary_and_the_new_ones_are_unique() -> void:
	check_eq(Forge.legendaries().size(), Db.weapons.size(), "one Legendary effect per weapon base")
	var names: Array[String] = []
	for id in Db.weapons:
		var legendary := Forge.legendary_for(id)
		check(legendary != null and legendary.weapon_id == id, "%s has its Legendary" % id)
		if legendary != null:
			names.append(legendary.display_name)
	var wanted := {&"crossbow": "Bindweed", &"polearm": "Barberry", &"fist_weapon": "Mossknuckle"}
	for id in NEW_IDS:
		var data := Forge.legendary_for(id)
		check_eq(data.display_name, wanted[id], "%s: its name" % id)
		check_eq(names.count(data.display_name), 1, "%s: a distinct name among the Legendaries" % id)
		check(data.unique_text != "" and data.flavor != "", "%s: text and flavor" % id)
		check_eq(String(data.unique_params.get("trigger", "")), "on_hit", "%s: on hit (an attacking weapon)" % id)
		check(data.unique_params.has("every") and data.unique_params.has("hit_pct"), "%s: every Nth hit, a share of the hit" % id)
		var proc: Dictionary = data.unique_params.duplicate(true)
		proc["effect"] = String(data.unique_effect)
		check_eq(BonusVocabulary.validate({"kind": "proc", "proc": proc}), "", "%s: a valid proc dict" % id)
		for bad in ForgeTests.FORBIDDEN_NAMES:
			check(not data.display_name.containsn(bad), "%s: no trademark (%s)" % [id, bad])
		for bad in Content.BANNED:
			check(not (data.display_name + " " + data.unique_text + " " + data.flavor).containsn(bad), "%s: no banned word (%s)" % [id, bad])
	for id in Db.uniques:
		check(names.count((Db.uniques[id] as UniqueItemData).display_name) == 0, "no hand-made item is called like a Legendary: %s" % id)
	check_eq(Forge.legendary_for(&"crossbow").unique_effect, &"bolt", "Bindweed: a harpoon")
	check_eq(Forge.legendary_for(&"polearm").unique_effect, &"dot", "Barberry: a wound")
	check_eq(Forge.legendary_for(&"fist_weapon").unique_effect, &"smite_heal", "Mossknuckle: a spirit strike")


func test_forged_epic_pairs_become_the_new_legendaries() -> void:
	for id in NEW_IDS:
		var item := _legendary(id)
		var data := Forge.legendary_for(id)
		check_eq(item.rarity, Items.Rarity.LEGENDARY, "%s: Legendary" % id)
		check_eq(item.display_name, data.display_name, "%s: its name" % id)
		check_eq(item.weapon.base_damage, Db.get_weapon(id).base_damage * 3.0, "%s: x3 base damage" % id)
		check(not Forge.is_forgeable(item), "%s: never forged again" % id)
		check_eq(item.unique_effect, data.unique_effect, "%s: carries the effect" % id)


func test_bindweed_pins_the_target_on_every_third_bolt() -> void:
	var p := _hero()
	_equip(p, _legendary(&"crossbow"))
	check(_has_proc(p, &"crossbow"), "the Legendary effect joined the procs")
	var target := _fake(Vector3(5.0, 0, 0))
	for i in 2:
		p.procs._physics_process(1.0)
		p.procs.on_hit(target, 20.0, p.main_hand, false)
	check_eq(p.procs.fire_count(&"crossbow"), 0, "two bolts: nothing yet")
	check_eq(target.fake_stun_count, 0, "not pinned")
	var before := target.fake_hits()
	p.procs._physics_process(1.0)
	p.procs.on_hit(target, 20.0, p.main_hand, false)
	check_eq(p.procs.fire_count(&"crossbow"), 1, "the 3rd bolt fires it")
	check(target.fake_hits() > before, "the harpoon hit")
	var dealt: float = target.fake_damage_log[before]
	check(dealt >= 32.0 and dealt < 50.0, "about 160%% of the 20-damage shot (%s)" % dealt)
	check(target.fake_stun_count >= 1, "and it pins the target")
	for i in 3:
		p.procs._physics_process(1.0)
		p.procs.on_hit(target, 20.0, p.main_hand, false)
	check_eq(p.procs.fire_count(&"crossbow"), 2, "again three bolts later")


func test_barberry_opens_a_stacking_wound_on_every_fourth_thrust() -> void:
	var p := _hero()
	_equip(p, _legendary(&"polearm"))
	check(_has_proc(p, &"polearm"), "the Legendary effect joined the procs")
	var target := _fake(Vector3(3.0, 0, 0))
	for i in 3:
		p.procs._physics_process(1.0)
		p.procs.on_hit(target, 20.0, p.main_hand, false)
	check_eq(p.procs.dot_stacks(target, &"polearm"), 0, "three thrusts: no wound")
	p.procs._physics_process(1.0)
	p.procs.on_hit(target, 20.0, p.main_hand, false)
	check_eq(p.procs.fire_count(&"polearm"), 1, "the 4th thrust fires it")
	check_eq(p.procs.dot_stacks(target, &"polearm"), 1, "a wound is bleeding")
	for i in 4:
		p.procs._physics_process(1.0)
		p.procs.on_hit(target, 20.0, p.main_hand, false)
	check_eq(p.procs.dot_stacks(target, &"polearm"), 2, "the second wound stacks (max 2)")
	for i in 4:
		p.procs._physics_process(1.0)
		p.procs.on_hit(target, 20.0, p.main_hand, false)
	check_eq(p.procs.dot_stacks(target, &"polearm"), 2, "never more than two")
	var before := target.fake_damage_log.size()
	for i in 20:
		p.procs._physics_process(0.5)
	check(target.fake_damage_log.size() > before, "the wound ticks")


func test_mossknuckle_strikes_and_heals_the_most_wounded_ally_on_every_fifth_hit() -> void:
	var p := _hero()
	var ally := Fakes.spawn_player(world, 1, &"warrior", Vector3(2, 0, 2))
	ally.stats.set_source(&"tough", {Stats.STAMINA: 500.0})
	ally.hp = ally.max_hp() * 0.4
	var hurt := ally.hp
	_equip(p, _legendary(&"fist_weapon"), Items.EquipSlot.MAIN_HAND)
	check(_has_proc(p, &"fist_weapon"), "the Legendary effect joined the procs")
	var target := _fake(Vector3(1.5, 0, 0))
	for i in 4:
		p.procs._physics_process(1.0)
		p.procs.on_hit(target, 20.0, p.main_hand, false)
	check_eq(p.procs.fire_count(&"fist_weapon"), 0, "four hits: nothing yet")
	check_near(ally.hp, hurt, 0.001, "nobody healed")
	var before := target.fake_hits()
	p.procs._physics_process(1.0)
	p.procs.on_hit(target, 20.0, p.main_hand, false)
	check_eq(p.procs.fire_count(&"fist_weapon"), 1, "the 5th hit fires it")
	check(target.fake_hits() > before, "the spirit strike hit")
	var dealt: float = target.fake_damage_log[before]
	check(dealt >= 24.0 and dealt < 40.0, "about 120%% of the 20-damage hit (%s)" % dealt)
	check(ally.hp > hurt + 3.5 and ally.hp < hurt + 6.0, "the most wounded ally recovered about 4 health (%s -> %s)" % [hurt, ally.hp])
	# Alone, the wielder is the most wounded ally.
	var solo_world := p
	solo_world.hp = solo_world.max_hp() * 0.2
	ally.hp = ally.max_hp()
	var low := solo_world.hp
	for i in 5:
		p.procs._physics_process(1.0)
		p.procs.on_hit(target, 20.0, p.main_hand, false)
	check(p.hp > low, "the wielder heals when he is the most wounded (%s -> %s)" % [low, p.hp])
