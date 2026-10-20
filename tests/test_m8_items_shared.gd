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


# --- Class-independent sets: data -------------------------------------------------------------------

func _set_data(id: StringName) -> SetData:
	return Db.get_set(id)


func _piece(set_key: String, slot: String, wave: int = 8) -> ItemInstance:
	return ItemGenerator.from_unique(Db.get_unique(StringName("set_%s_%s" % [set_key, slot])), wave, false, rng)


func test_the_five_independent_sets_are_shipped_with_five_pieces_each() -> void:
	var free: Array[StringName] = []
	for s in Rules.free_sets():
		free.append(s.id)
	free.sort()
	var wanted: Array[StringName] = []
	wanted.assign(SETS.keys())
	wanted.sort()
	check_eq(free, wanted, "exactly the five class-independent sets")
	for id in SETS:
		var data := _set_data(id)
		check(data != null, "%s loaded" % id)
		if data == null:
			continue
		var info: Array = SETS[id]
		check_eq(data.display_name, info[0], "%s: its name" % id)
		check_eq(data.class_id, &"", "%s: class-independent" % id)
		check(data.is_independent(), "%s: is_independent" % id)
		check_eq(data.armor_type, info[1], "%s: its armour type" % id)
		var expected: Array[StringName] = []
		for s in SLOT_KEYS:
			expected.append(StringName("set_%s_%s" % [info[2], s]))
		check_eq(data.piece_ids, expected, "%s: Head, Shoulders, Chest, Hands, Legs" % id)
		var thresholds: Array[int] = []
		for b in data.bonuses:
			thresholds.append(int(b["pieces"]))
			check(str(b.get("text", "")) != "" and not (b["effects"] as Array).is_empty(), "%s: bonus text and effects" % id)
		check_eq(thresholds, [2, 4] as Array[int], "%s: 2- and 4-piece bonuses, no 5-piece" % id)
		check(Db.set_for_class(&"") == null, "an independent set is nobody's own")
		for bad in Content.BANNED:
			check(not data.display_name.containsn(bad), "%s: no trademark (%s)" % [id, bad])
	# Two mail sets (the Hunter and the Shaman are the mail natives), one set of every other armour type.
	var by_armor := {}
	for id in SETS:
		by_armor[SETS[id][1]] = by_armor.get(SETS[id][1], 0) + 1
	check_eq(by_armor, {ClassData.ArmorType.CLOTH: 1, ClassData.ArmorType.LEATHER: 1, ClassData.ArmorType.MAIL: 2, ClassData.ArmorType.PLATE: 1},
			"one set per armour type, plus a second mail set")


func test_set_pieces_have_stamina_two_secondaries_and_no_primary_stat() -> void:
	var slot_types: Array[int] = [Items.SlotType.HEAD, Items.SlotType.SHOULDERS, Items.SlotType.CHEST, Items.SlotType.HANDS, Items.SlotType.LEGS]
	var names: Array[String] = []
	for id in SETS:
		var info: Array = SETS[id]
		for i in SLOT_KEYS.size():
			var pid := StringName("set_%s_%s" % [info[2], SLOT_KEYS[i]])
			var u := Db.get_unique(pid)
			check(u != null, "%s exists" % pid)
			if u == null:
				continue
			check_eq(u.set_id, id, "%s: its set" % pid)
			check_eq(u.rarity, Items.Rarity.EPIC, "%s: Epic" % pid)
			check_eq(u.slot_type, slot_types[i], "%s: slot" % pid)
			check_eq(u.armor_type, info[1], "%s: the set's armour type" % pid)
			check_eq(u.class_restriction, &"", "%s: usable by any class that wears the armour" % pid)
			check_eq(u.weight, 0.0, "%s: set roll only" % pid)
			check_eq(u.min_wave, 6, "%s: from wave 6" % pid)
			check_eq(u.sources, [&"shop", &"loot", &"elite", &"goblin", &"boss"] as Array[StringName], "%s: every source" % pid)
			check(u.display_name != "" and u.flavor != "" and u.unique_effect == &"", "%s: named, flavoured, no unique effect of its own" % pid)
			check(u.display_name.begins_with(String(info[0]).get_slice(" ", 0)), "%s: named after the set (%s)" % [pid, u.display_name])
			for bad in Content.BANNED:
				check(not (u.display_name + " " + u.flavor).containsn(bad), "%s: no banned word (%s)" % [pid, bad])
			check(u.display_name not in names, "%s: a distinct name" % pid)
			names.append(u.display_name)
			check_eq(u.stats.size(), 3, "%s: three stats" % pid)
			check(u.stats.get(Stats.STAMINA, 0.0) > 0.0, "%s: Stamina" % pid)
			var secondaries := 0
			for stat in u.stats:
				check(stat not in [Stats.STRENGTH, Stats.AGILITY, Stats.INTELLECT], "%s: no primary stat (%s)" % [pid, stat])
				if stat in ItemGenerator.SECONDARY_STATS:
					secondaries += 1
			check_eq(secondaries, 2, "%s: two secondary stats" % pid)
			var budget := ItemGenerator.RARITY_BUDGET[Items.Rarity.EPIC] * ItemGenerator.slot_multiplier(u.slot_type)
			check_near(ItemGenerator.stat_cost(u.stats), budget, 0.5, "%s: Epic budget" % pid)
			# As an item: implicit armour of its type, a set piece, hand-made.
			var item := ItemGenerator.from_unique(u, 8, false, rng)
			check(item.unique and item.set_id == id and item.class_restriction == &"", "%s: a class-free hand-made set piece" % pid)
			if info[1] != ClassData.ArmorType.CLOTH:
				check(item.all_stats().get(Stats.ARMOR, 0.0) > 0.0, "%s: implicit armour" % pid)


func test_the_bonuses_follow_the_design_and_validate_for_every_class() -> void:
	var want := {
		&"mendweave_attire": [[{"kind": "stats", "stats": {"spirit": 8.0}}],
			[{"kind": "proc", "proc": {"trigger": "periodic", "interval": 8.0, "effect": "heal", "target": "lowest_ally", "max_hp_pct": 10.0}}]],
		&"slipskin_leathers": [[{"kind": "stats", "stats": {"dodge": 5.0}}],
			[{"kind": "proc", "proc": {"trigger": "on_dodge", "effect": "buff", "icd": 3.0, "duration": 4.0, "stats": {"damage_pct": 10.0, "speed": 15.0}}}]],
		&"hoardscale_mail": [[{"kind": "stats", "stats": {"gold_find": 20.0, "fortune": 15.0}}],
			[{"kind": "proc", "proc": {"trigger": "on_kill", "effect": "gold", "chance": 6.0, "amount": 3}}]],
		&"redthorn_mail": [[{"kind": "stats", "stats": {"slayer": 12.0}}],
			[{"kind": "proc", "proc": {"trigger": "on_kill", "effect": "buff", "duration": 6.0, "max_stacks": 6, "stats": {"damage_pct": 2.0}}}]],
		&"stonebark_plate": [[{"kind": "damage_taken", "pct": -5.0}],
			[{"kind": "proc", "proc": {"trigger": "low_hp", "threshold": 40.0, "per_wave": 1, "effect": "shield", "max_hp_pct": 30.0, "duration": 6.0}}]],
	}
	for id in want:
		var data := _set_data(id)
		check_eq(data.bonuses[0]["effects"], want[id][0], "%s 2 pieces" % id)
		check_eq(data.bonuses[1]["effects"], want[id][1], "%s 4 pieces" % id)
		for b in data.bonuses:
			for e: Dictionary in b["effects"]:
				check_eq(BonusVocabulary.validate(e, &""), "", "%s %d-piece valid without a class: %s" % [id, b["pieces"], e])
				for class_id in Db.class_ids:
					check_eq(BonusVocabulary.validate(e, class_id), "", "%s %d-piece valid for %s" % [id, b["pieces"], class_id])
				# Class-agnostic: no ability ids, no class resources.
				check(not e.has("match") and not e.has("ability") and e.get("kind") != "resource", "%s: no class content in %s" % [id, e])
				if e.get("kind") == "proc":
					check(not (e["proc"] as Dictionary).has("ability") and not (e["proc"] as Dictionary).has("label"), "%s: a plain proc (the engine labels it with the set name)" % id)


func test_every_independent_set_has_its_own_look() -> void:
	var seen: Array[Color] = []
	for id in OnionArmor.SET_STYLES:
		var main: Color = OnionArmor.SET_STYLES[id]["main"]
		check(main not in seen, "%s: its own main colour" % id)
		seen.append(main)
	for id in SETS:
		check(OnionArmor.SET_STYLES.has(id), "%s has a style" % id)
		var look := EquipLook.make(EquipLook.Slot.HEAD, SETS[id][1], 1, 3, id)
		var pal := OnionArmor.palette(look)
		check(pal.main != OnionArmor.GENERIC_SET["main"], "%s: not the generic gold" % id)
		for slot in [EquipLook.Slot.HEAD, EquipLook.Slot.SHOULDERS, EquipLook.Slot.CHEST]:
			var part := OnionArmor.part(slot, EquipLook.make(slot, SETS[id][1], 1, 3, id), Db.get_class_data(&"warrior"))
			check(part != null and part.solid != null, "%s: draws slot %d" % [id, slot])


# --- Class-independent sets: they work for every class that wears them ---------------------------------

## Players of every class that can wear [param armor] (class armour >= set armour).
func _wearers(armor: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in Db.class_ids:
		if int(Db.get_class_data(id).armor_type) >= armor:
			out.append(id)
	return out


func _wear(p: Player, item: ItemInstance) -> void:
	p.equipment.add_to_backpack(item)
	check(p.equipment.equip(item), "%s equips on %s" % [item.display_name, p.class_data.id])


func test_any_class_that_can_wear_a_set_gets_its_bonuses() -> void:
	var two_piece := {
		&"mendweave_attire": {Stats.SPIRIT: 8.0}, &"slipskin_leathers": {Stats.DODGE: 5.0},
		&"hoardscale_mail": {Stats.GOLD_FIND: 20.0, Stats.FORTUNE: 15.0}, &"redthorn_mail": {Stats.SLAYER: 12.0},
		&"stonebark_plate": {},
	}
	var checked := 0
	for id in SETS:
		var key: String = SETS[id][2]
		for class_id in _wearers(SETS[id][1]):
			var p := Fakes.spawn_player(world, 0, class_id)
			Enemy.invalidate_player_cache()
			_wear(p, _piece(key, "head"))
			check(p.bonuses.effects_of(PlayerBonuses.SOURCE_SETS).is_empty(), "%s on %s: one piece, nothing" % [id, class_id])
			_wear(p, _piece(key, "legs"))
			check_eq(p.equipment.set_counts(), {id: 2} as Dictionary[StringName, int], "%s on %s: two pieces counted" % [id, class_id])
			check_eq(SetBonuses.active_count(p.equipment), 1, "%s on %s: the 2-piece bonus" % [id, class_id])
			var source := p.stats.get_source(&"set_bonus")
			for stat in two_piece[id]:
				check_eq(source.get(stat, 0.0), two_piece[id][stat], "%s on %s: %s" % [id, class_id, stat])
			if id == &"stonebark_plate":
				check_near(p.bonuses.damage_taken_mult(CombatMath.KIND_MELEE, null), 0.95, 0.0001, "%s on %s: 5%% less damage taken" % [id, class_id])
			check(p.procs.extra_defs(PlayerBonuses.SOURCE_SETS).is_empty(), "%s on %s: no proc yet" % [id, class_id])
			_wear(p, _piece(key, "chest"))
			_wear(p, _piece(key, "hands"))
			check_eq(SetBonuses.active_count(p.equipment), 2, "%s on %s: four pieces, both bonuses" % [id, class_id])
			var defs := p.procs.extra_defs(PlayerBonuses.SOURCE_SETS)
			check_eq(defs.size(), 1, "%s on %s: the 4-piece proc is handed to the ProcSystem" % [id, class_id])
			if defs.size() == 1:
				check_eq(str(defs[0]["id"]), "%s:4" % id, "%s on %s: proc id" % [id, class_id])
				check_eq(str(defs[0]["label"]), SETS[id][0], "%s on %s: labelled with the set name" % [id, class_id])
			check(_has_proc(p, StringName("%s:4" % id)), "%s on %s: the proc is live" % [id, class_id])
			p.free()
			Enemy.invalidate_player_cache()
			checked += 1
	var pairs := 0
	for id in SETS:
		pairs += _wearers(SETS[id][1]).size()
	check_eq(checked, pairs, "every (set, wearing class) pair was checked")
	check(checked >= 14, "the five launch classes alone make 14 pairs (%d)" % checked)


func test_a_lighter_set_is_wearable_by_a_heavier_class_but_not_the_other_way() -> void:
	var warrior := Fakes.spawn_player(world, 0, &"warrior")
	var mage := Fakes.spawn_player(world, 1, &"mage", Vector3(5, 0, 0))
	Enemy.invalidate_player_cache()
	for id in SETS:
		var piece := _piece(SETS[id][2], "chest")
		check(piece.can_be_used_by(warrior.class_data), "%s: the plate warrior may Need / wear it" % id)
		check_eq(piece.can_be_used_by(mage.class_data), SETS[id][1] == ClassData.ArmorType.CLOTH, "%s: the cloth mage only wears the cloth set" % id)
		if SETS[id][1] != ClassData.ArmorType.CLOTH:
			check(piece.unusable_reason(mage.class_data) != "", "%s: the mage is told why" % id)
	for p in [warrior, mage]:
		p.free()


func test_mendweave_heals_the_most_wounded_ally_every_eight_seconds() -> void:
	var p := Fakes.spawn_player(world, 0, &"mage")
	var ally := Fakes.spawn_player(world, 1, &"warrior", Vector3(3, 0, 0))
	for h in [p, ally]:
		h.stats.set_source(&"tough", {Stats.STAMINA: 500.0})
	Enemy.invalidate_player_cache()
	for s in ["head", "shoulders", "chest", "hands"]:
		_wear(p, _piece("mendweave", s))
	p.hp = p.max_hp()
	ally.hp = ally.max_hp() * 0.4
	var before := ally.hp
	p.procs.begin_wave()
	for i in 470:  # 7.8 s
		p.procs._physics_process(DT)
	check_near(ally.hp, before, 0.001, "nothing before 8 s")
	for i in 30:
		p.procs._physics_process(DT)
	check_near(ally.hp, before + ally.max_hp() * 0.10, 0.6, "10%% of the ally's Max HP (%s -> %s of %s)" % [before, ally.hp, ally.max_hp()])
	# Alone: the wearer is the most wounded ally.
	ally.hp = ally.max_hp()
	p.hp = p.max_hp() * 0.5
	var mine := p.hp
	for i in 500:
		p.procs._physics_process(DT)
	check(p.hp > mine + p.max_hp() * 0.05, "the wearer heals when he is the most wounded (%s -> %s)" % [mine, p.hp])
	for h in [p, ally]:
		h.free()


func test_slipskin_rewards_a_dodge_with_damage_and_speed_once_every_three_seconds() -> void:
	var p := Fakes.spawn_player(world, 0, &"rogue")
	for s in ["head", "shoulders", "chest", "hands"]:
		_wear(p, _piece("slipskin", s))
	var damage := p.stats.get_stat(Stats.DAMAGE_PCT)
	var speed := p.stats.get_stat(Stats.SPEED)
	p.procs.on_avoided(&"dodge", null)
	check_eq(p.procs.fire_count(&"slipskin_leathers:4"), 1, "a dodge fires it")
	check_near(p.stats.get_stat(Stats.DAMAGE_PCT) - damage, 10.0, 0.001, "+10% damage")
	check_near(p.stats.get_stat(Stats.SPEED) - speed, 15.0, 0.001, "+15% Speed")
	p.procs.on_avoided(&"dodge", null)
	check_eq(p.procs.fire_count(&"slipskin_leathers:4"), 1, "the 3 s cooldown holds it back")
	p.procs._physics_process(3.2)
	check_near(p.stats.get_stat(Stats.DAMAGE_PCT) - damage, 10.0, 0.001, "the buff is still up after 3.2 s")
	p.procs.on_avoided(&"dodge", null)
	check_eq(p.procs.fire_count(&"slipskin_leathers:4"), 2, "and it fires again after the cooldown")
	check_near(p.stats.get_stat(Stats.DAMAGE_PCT) - damage, 10.0, 0.001, "refreshed, not stacked")
	p.procs.on_avoided(&"parry", null)
	check_eq(p.procs.fire_count(&"slipskin_leathers:4"), 2, "a parry is not a dodge")
	p.procs._physics_process(4.2)
	check_near(p.stats.get_stat(Stats.DAMAGE_PCT), damage, 0.001, "the 4 s buff ran out")
	check_near(p.stats.get_stat(Stats.SPEED), speed, 0.001, "and the speed with it")
	p.free()


func test_hoardscale_finds_extra_gold_on_six_percent_of_the_kills() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior")
	for s in ["head", "shoulders", "chest", "hands"]:
		_wear(p, _piece("hoardscale", s))
	var e := _fake(Vector3(3, 0, 0))
	RunState.rng.seed = 4242
	var gold := RunState.gold
	for i in 3000:
		p.procs.on_kill(e)
	var found := RunState.gold - gold
	check_eq(found % 3, 0, "gold comes in lots of 3 (%d)" % found)
	check_near(float(found) / 3.0 / 3000.0, 0.06, 0.012, "about 6%% of the kills (%d lots)" % (found / 3))
	p.free()


func test_redthorn_stacks_damage_with_every_kill_up_to_six_times() -> void:
	var p := Fakes.spawn_player(world, 0, &"paladin")
	for s in ["head", "shoulders", "chest", "hands"]:
		_wear(p, _piece("redthorn", s))
	var e := _fake(Vector3(3, 0, 0))
	var base := p.stats.get_stat(Stats.DAMAGE_PCT)
	for i in 3:
		p.procs.on_kill(e)
	check_near(p.stats.get_stat(Stats.DAMAGE_PCT) - base, 6.0, 0.001, "three kills: +6% damage")
	for i in 10:
		p.procs.on_kill(e)
	check_near(p.stats.get_stat(Stats.DAMAGE_PCT) - base, 12.0, 0.001, "six stacks at most: +12%")
	p.procs._physics_process(6.1)
	check_near(p.stats.get_stat(Stats.DAMAGE_PCT), base, 0.001, "gone after 6 s")
	p.free()


func test_stonebark_raises_a_barrier_below_forty_percent_once_per_wave() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior")
	p.stats.set_source(&"tough", {Stats.STAMINA: 500.0})
	for s in ["head", "shoulders", "chest", "hands"]:
		_wear(p, _piece("stonebark", s))
	var max_hp := p.max_hp()
	p.hp = max_hp
	p.procs.begin_wave()
	p.hp = max_hp * 0.5
	p.procs.on_struck(null, 1.0)
	check_eq(p.procs.shield_hp, 0.0, "50% health: nothing yet")
	p.hp = max_hp * 0.39
	p.procs.on_struck(null, 1.0)
	check_near(p.procs.shield_hp, max_hp * 0.30, 0.01, "below 40%%: a barrier of 30%% Max HP (%s of %s)" % [p.procs.shield_hp, max_hp])
	check_eq(p.procs.fire_count(&"stonebark_plate:4"), 1, "fired")
	p.procs._physics_process(6.2)
	check_eq(p.procs.shield_hp, 0.0, "it fades after 6 s")
	p.hp = max_hp
	p.procs._physics_process(DT)
	p.hp = max_hp * 0.3
	p.procs.on_struck(null, 1.0)
	check_eq(p.procs.fire_count(&"stonebark_plate:4"), 1, "once per wave: not again")
	p.procs.begin_wave()
	p.hp = max_hp
	p.procs._physics_process(DT)
	p.hp = max_hp * 0.3
	p.procs.on_struck(null, 1.0)
	check_eq(p.procs.fire_count(&"stonebark_plate:4"), 2, "the next wave it is back")
	p.free()


# --- Class-independent sets: who rolls them -----------------------------------------------------------

func _ids(sets: Array[SetData]) -> Array[StringName]:
	var out: Array[StringName] = []
	for s in sets:
		out.append(s.id)
	return out


func _team(ids: Array[StringName]) -> Array[ClassData]:
	var out: Array[ClassData] = []
	for id in ids:
		out.append(Db.get_class_data(id))
	return out


## [param n] Epic rolls from [param source] at [param wave]; the set pieces among them.
func _set_rolls(source: ItemGenerator.Source, wave: int, n: int, options: Dictionary = {}, seed_value: int = 7) -> Array[ItemInstance]:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var opts := options.duplicate()
	opts[&"rarity"] = Items.Rarity.EPIC
	var out: Array[ItemInstance] = []
	for i in n:
		var it := ItemGenerator.generate(source, wave, r, opts)
		if it.set_id != &"":
			out.append(it)
	return out


func test_the_roll_pool_is_the_native_armour_of_the_hero_or_team() -> void:
	# A mail class (the Hunter / Shaman come with their own packages): the two mail sets.
	var mail := classes.add_class()
	mail.armor_type = ClassData.ArmorType.MAIL
	check_eq(_ids(ItemGenerator.independent_sets_for(mail, [])), [&"hoardscale_mail", &"redthorn_mail"] as Array[StringName], "mail: Hoardscale + Redthorn, by id")
	check_eq(_ids(Db.sets_for_class(mail.id, mail)), [&"hoardscale_mail", &"redthorn_mail"] as Array[StringName],
			"Db.sets_for_class: no class set for the fixture, the two mail sets")
	var per_class := {&"warrior": [&"stonebark_plate"], &"paladin": [&"stonebark_plate"], &"mage": [&"mendweave_attire"],
		&"warlock": [&"mendweave_attire"], &"rogue": [&"slipskin_leathers"]}
	for class_id in per_class:
		var cd := Db.get_class_data(class_id)
		var want: Array[StringName] = []
		want.assign(per_class[class_id])
		check_eq(_ids(ItemGenerator.independent_sets_for(cd, [])), want, "%s: only its own armour's set" % class_id)
		var listed := _ids(Db.sets_for_class(class_id))
		check_eq(listed.slice(1), want, "%s: Db.sets_for_class = its class set, then that set" % class_id)
		check_eq(listed[0], Db.set_for_class(class_id).id, "%s: its own set first" % class_id)
		for set_id in SETS:
			var native: bool = SETS[set_id][1] == int(cd.armor_type)
			check_eq(Db.set_usable_by(Db.get_set(set_id), cd), native, "%s collects %s: %s" % [class_id, set_id, native])
	# The default party: plate + cloth + leather.
	var party := _team([&"warrior", &"mage", &"paladin", &"rogue"])
	check_eq(_ids(ItemGenerator.independent_sets_for(null, party)), [&"mendweave_attire", &"slipskin_leathers", &"stonebark_plate"] as Array[StringName],
			"the default party rolls the plate, cloth and leather sets, not the mail sets")
	# Nobody given: every armour of the classes in the game.
	var any_mail := false
	for id in Db.class_ids:
		any_mail = any_mail or int(Db.get_class_data(id).armor_type) == ClassData.ArmorType.MAIL
	check_eq(&"hoardscale_mail" in _ids(ItemGenerator.independent_sets_for(null, [])), any_mail, "the mail sets roll for 'nobody in particular' only when a mail class exists")


func test_rolled_independent_pieces_are_native_and_wearable() -> void:
	var party := _team([&"warrior", &"mage", &"paladin", &"rogue"])
	var seen := {}
	for it in _set_rolls(ItemGenerator.Source.LOOT, 14, 12000, {&"team_classes": party}):
		var data := Db.get_set(it.set_id)
		if not data.is_independent():
			continue
		seen[it.set_id] = seen.get(it.set_id, 0) + 1
		check_eq(it.armor_type, data.armor_type, "%s: its armour" % it.display_name)
		check_eq(it.class_restriction, &"", "%s: no class restriction" % it.display_name)
		check(it.can_be_used_by(party[0]) or it.can_be_used_by(party[1]) or it.can_be_used_by(party[3]), "%s: a party class wears it" % it.display_name)
		check(it.set_id != &"hoardscale_mail" and it.set_id != &"redthorn_mail", "%s: no mail set for a party without a mail class" % it.display_name)
	check_eq(seen.keys().size(), 3, "all three native sets drop: %s" % [seen])
	# A hero asked for by class (the shop): its own armour's set only.
	var warrior := Db.get_class_data(&"warrior")
	for it in _set_rolls(ItemGenerator.Source.SHOP, 14, 6000, {&"usable_by": warrior, &"team_classes": party}):
		check(it.set_id in [Db.set_for_class(&"warrior").id, &"stonebark_plate"], "usable_by warrior: its class set or the plate set (%s)" % it.set_id)
	# Before wave 6 there is no piece at all.
	check(_set_rolls(ItemGenerator.Source.LOOT, 5, 3000, {&"team_classes": party}).is_empty(), "waves 1-5: no set pieces")
	# A forced slot rolls that slot only.
	for it in _set_rolls(ItemGenerator.Source.LOOT, 14, 4000, {&"slot_type": Items.SlotType.HANDS, &"team_classes": party}):
		check_eq(it.slot_type, Items.SlotType.HANDS, "forced Hands: a Hands piece")


func test_thirty_percent_of_the_set_hits_are_independent_sets() -> void:
	var party := _team([&"warrior", &"mage", &"paladin", &"rogue"])
	var rolls: Array[ItemInstance] = []
	var n := 40000
	var r := RandomNumberGenerator.new()
	r.seed = 5150
	var hits := 0
	var independent := 0
	var by_set := {}
	for i in n:
		var piece := ItemGenerator._roll_set_piece(ItemGenerator.Source.LOOT, 14, -1, null, party, r)
		if piece == null:
			continue
		hits += 1
		var set_id := piece.set_id
		by_set[set_id] = by_set.get(set_id, 0) + 1
		if Db.get_set(set_id).is_independent():
			independent += 1
	check_near(float(hits) / n, 0.15, 0.01, "set rate unchanged: 15%% of the loot rolls (%d hits)" % hits)
	check_near(float(independent) / hits, 0.30, 0.03, "30%% of the hits are independent sets (%d / %d)" % [independent, hits])
	# The default party: 17.5% per class set (4 of them share 70%), 10% per independent set (3 share 30%).
	for set_id in by_set:
		var share := float(by_set[set_id]) / hits
		var expected := 0.10 if Db.get_set(set_id).is_independent() else 0.175
		check_near(share, expected, 0.03, "%s: %.1f%% of the hits (expected %.1f%%)" % [set_id, share * 100.0, expected * 100.0])
	# A solo mail hero: 70% class set (none here: a fixture has none) -> the two mail sets share everything.
	var mail := classes.add_class()
	mail.armor_type = ClassData.ArmorType.MAIL
	r.seed = 99
	by_set.clear()
	hits = 0
	for i in 8000:
		var piece := ItemGenerator._roll_set_piece(ItemGenerator.Source.LOOT, 14, -1, mail, [], r)
		if piece != null:
			hits += 1
			by_set[piece.set_id] = by_set.get(piece.set_id, 0) + 1
	check_eq(by_set.keys().size(), 2, "a mail hero without a class set: the two mail sets")
	for set_id in by_set:
		check_near(float(by_set[set_id]) / hits, 0.5, 0.06, "%s: half each" % set_id)
	# The hook switches the independent sets off.
	ItemGenerator.independent_share_override = 0.0
	r.seed = 5150
	for i in 6000:
		var piece := ItemGenerator._roll_set_piece(ItemGenerator.Source.LOOT, 14, -1, null, party, r)
		check(piece == null or not Db.get_set(piece.set_id).is_independent(), "override 0: class sets only")


func test_class_set_rolls_are_the_old_rolls_when_no_independent_set_is_eligible() -> void:
	# Hide the independent sets: the draws are exactly the M7 ones (chance, class, piece).
	fixtures.remove_free_sets()
	var party := _team([&"warrior", &"mage"])
	var a := RandomNumberGenerator.new()
	var probe := RandomNumberGenerator.new()
	var hits := 0
	for seed_value in range(1, 150):
		a.seed = seed_value
		probe.seed = seed_value
		if probe.randf() >= 0.15:
			check(ItemGenerator._roll_set_piece(ItemGenerator.Source.LOOT, 12, -1, null, party, a) == null, "seed %d: a miss" % seed_value)
			check_eq(a.state, probe.state, "seed %d: a miss draws once" % seed_value)
			continue
		hits += 1
		var got := ItemGenerator._roll_set_piece(ItemGenerator.Source.LOOT, 12, -1, null, party, a)
		var cls := party[probe.randi_range(0, 1)]
		var want := Db.set_for_class(cls.id).piece_ids[probe.randi_range(0, 4)]
		check(got != null and got.id == want, "seed %d: class %s, piece %s" % [seed_value, cls.id, want])
		check_eq(a.state, probe.state, "seed %d: three draws" % seed_value)
	check(hits > 10, "hits: %d" % hits)


# --- Class-independent sets: Black Market, dungeon, Need -----------------------------------------------

func test_the_black_market_offers_independent_pieces_once_the_class_set_is_complete() -> void:
	var mage := Fakes.spawn_player(world, 0, &"mage")
	var slots: Array[PlayerSlot] = [mage.slot]
	var class_set := Db.set_for_class(&"mage")
	check_eq(BlackMarket.set_piece_candidates(18, slots).size(), 5, "class pieces: the mage's five")
	var free := BlackMarket.independent_piece_candidates(18, slots)
	check_eq(free.size(), 5, "independent pieces: the five Mendweave pieces (cloth is the mage's armour)")
	for c in free:
		check_eq((c["data"] as UniqueItemData).set_id, &"mendweave_attire", "a Mendweave piece")
	for c in BlackMarket.set_piece_pool(18, slots):
		check_eq((c["data"] as UniqueItemData).set_id, class_set.id, "first the class set")
	for piece_id in class_set.piece_ids:
		mage.equipment.add_to_backpack(ItemGenerator.from_unique(Db.get_unique(piece_id), 18, false, rng))
	var pool := BlackMarket.set_piece_pool(18, slots)
	check_eq(pool.size(), 5, "the class set complete: the independent set is what is missing")
	for c in pool:
		check_eq((c["data"] as UniqueItemData).set_id, &"mendweave_attire", "Mendweave")
	var seen := {}
	for i in 60:
		var r2 := RandomNumberGenerator.new()
		r2.seed = i
		var item := BlackMarket.roll(18, slots, r2)
		check(item != null, "an offer")
		if item != null and item.set_id != &"":
			seen[item.set_id] = true
			check(item.can_be_used_by(mage.class_data), "the mage can wear %s" % item.display_name)
	check_eq(seen.keys(), [&"mendweave_attire"], "only Mendweave pieces are offered as the set piece")
	# A plate warrior in the party gets the Stonebark set, never the cloth one.
	var warrior := Fakes.spawn_player(world, 1, &"warrior", Vector3(4, 0, 0))
	var both: Array[PlayerSlot] = [mage.slot, warrior.slot]
	var ids: Array[StringName] = []
	for c in BlackMarket.independent_piece_candidates(18, both):
		var sid := (c["data"] as UniqueItemData).set_id
		if sid not in ids:
			ids.append(sid)
	check_eq(ids, [&"mendweave_attire", &"stonebark_plate"] as Array[StringName], "one independent set per native armour, in hero order")
	check(BlackMarket.independent_piece_candidates(3, both).is_empty(), "before wave 6: nothing")
	for p in [mage, warrior]:
		p.free()
	Enemy.invalidate_player_cache()


func test_a_plate_hero_may_need_a_cloth_set_piece_but_a_cloth_hero_not_a_plate_one() -> void:
	var cloth_piece := _piece("mendweave", "head")
	var plate_piece := _piece("stonebark", "head")
	var warrior := Db.get_class_data(&"warrior")
	var mage := Db.get_class_data(&"mage")
	check(cloth_piece.can_be_used_by(warrior), "the warrior may Need the Mendweave Cowl (wearable)")
	check(not plate_piece.can_be_used_by(mage), "the mage may not Need the Stonebark Greathelm")
	check_eq(plate_piece.unusable_reason(mage), "Cannot wear Plate", "and is told why")


# --- Class-independent sets: bots, tooltips ---------------------------------------------------------------

func test_bots_value_independent_pieces_with_a_flat_credit() -> void:
	for set_id in SETS:
		var key: String = SETS[set_id][2]
		for class_id in _wearers(SETS[set_id][1]):
			var cd := Db.get_class_data(class_id)
			var native: bool = int(cd.armor_type) == SETS[set_id][1]
			for slot in SLOT_KEYS:
				var item := _piece(key, slot)
				var stats := 0.0
				for stat in ItemTooltip.total_stats(item):
					stats += ItemTooltip.total_stats(item)[stat] * ItemTooltip.stat_weight(stat, cd)
				var credit := ItemTooltip.INDEPENDENT_SET_CREDIT if native else 0.0
				check_near(ItemTooltip.item_score(item, cd), stats + credit, 0.0001,
						"%s on %s: the stats%s" % [item.display_name, class_id, " plus the flat credit" if native else " (a lighter set than its armour: no credit)"])
		# No viewer at all: scored without a class, credit included.
		var anon := _piece(key, "head")
		var anon_stats := 0.0
		for stat in ItemTooltip.total_stats(anon):
			anon_stats += ItemTooltip.total_stats(anon)[stat] * ItemTooltip.stat_weight(stat, null)
		check_near(ItemTooltip.item_score(anon, null), anon_stats + ItemTooltip.INDEPENDENT_SET_CREDIT, 0.0001, "%s: no viewer" % set_id)
	# A class piece gets no credit.
	var warrior := Db.get_class_data(&"warrior")
	var class_piece := ItemGenerator.from_unique(Db.get_unique(&"set_warrior_head"), 8, false, rng)
	var stats := 0.0
	for stat in ItemTooltip.total_stats(class_piece):
		stats += ItemTooltip.total_stats(class_piece)[stat] * ItemTooltip.stat_weight(stat, warrior)
	check_near(ItemTooltip.item_score(class_piece, warrior), stats, 0.0001, "a class set piece: the stats only")
	# With the credit an independent piece is worth at least 70% of the class piece it competes with
	# (SET_UPGRADE_TOLERANCE 0.3), so a bot completing a bonus with it does wear it.
	for slot in SLOT_KEYS:
		var mine := ItemTooltip.item_score(_piece("stonebark", slot), warrior)
		var theirs := ItemTooltip.item_score(ItemGenerator.from_unique(Db.get_unique(StringName("set_warrior_%s" % slot)), 8, false, rng), warrior)
		check(mine >= theirs * (1.0 - ItemTooltip.SET_UPGRADE_TOLERANCE), "Stonebark %s (%.1f) is within 30%% of the Battlegear piece (%.1f)" % [slot, mine, theirs])


func test_a_bot_wears_the_second_piece_of_an_independent_set_over_a_plain_epic() -> void:
	var warrior := Db.get_class_data(&"warrior")
	var eq := Equipment.new(warrior)
	# A plain Epic chest as a bot would carry it: a Battlegear chest without its set (a primary stat, 37 points).
	var plain_chest := ItemGenerator.from_unique(Db.get_unique(&"set_warrior_chest"), 8, false, rng)
	plain_chest.set_id = &""
	plain_chest.class_restriction = &""
	eq.slots[Items.EquipSlot.CHEST] = plain_chest
	eq.slots[Items.EquipSlot.HEAD] = _piece("stonebark", "head")
	var chest := _piece("stonebark", "chest")
	check_eq(SetBonuses.bonus_change(chest, [plain_chest] as Array[ItemInstance], eq), 1, "the second piece completes the 2-piece bonus")
	check_eq(ItemTooltip.upgrade_direction(chest, plain_chest, warrior, eq), 1, "so the bot swaps the plain chest for it")
	# Without the credit the piece would be below 70% of the plain chest and be refused.
	var bare := ItemTooltip.item_score(chest, warrior) - ItemTooltip.INDEPENDENT_SET_CREDIT
	check(bare < ItemTooltip.item_score(plain_chest, warrior) * (1.0 - ItemTooltip.SET_UPGRADE_TOLERANCE),
			"the credit is what makes the difference (%.1f without it, the plain chest %.1f)" % [bare, ItemTooltip.item_score(plain_chest, warrior)])


func test_the_tooltip_shows_the_set_of_an_independent_piece() -> void:
	var tip := ItemTooltip.create()
	tree.root.add_child(tip)
	var mage := Db.get_class_data(&"mage")
	var head := _piece("mendweave", "head")
	tip.show_item(head, mage)
	check(tip.find_line("Mendweave Attire (5 pieces)", true) != null, "the loot-roll block names the set: %s" % [tip.line_texts()])
	check(tip.find_line("(2) Set: Increases your Spirit by 8.", true) != null, "the 2-piece row")
	check(tip.find_line("(4) Set: Every 8 sec, the most wounded ally (you, when alone) is healed for 10% of their Max HP.", true) != null, "the 4-piece row")
	check(tip.find_line("Classes:") == null, "no Classes line: any class that wears cloth")
	var eq := Equipment.new(mage)
	eq.slots[Items.EquipSlot.HEAD] = head
	eq.slots[Items.EquipSlot.CHEST] = _piece("mendweave", "chest")
	tip.viewer_equipment = eq
	tip.show_item(head, mage)
	check(tip.find_line("Mendweave Attire (2/5)", true) != null, "worn count")
	var two := tip.find_line("(2) Set: Increases your Spirit by 8.", true)
	check(two != null and two.get_theme_color(&"font_color").is_equal_approx(ItemTooltip.ENCHANT_GREEN), "the reached bonus is green")
	# A heavier armour than the viewer wears is called out.
	tip.viewer_equipment = null
	tip.show_item(_piece("stonebark", "head"), mage)
	var plate := tip.find_line("Plate")
	check(plate != null and plate.get_theme_color(&"font_color").is_equal_approx(ItemTooltip.UNUSABLE_RED), "a heavier armour than the viewer wears is red")
	tip.show_item(_piece("mendweave", "head"), Db.get_class_data(&"warrior"))
	var cloth := tip.find_line("Cloth")
	check(cloth != null and not cloth.get_theme_color(&"font_color").is_equal_approx(ItemTooltip.UNUSABLE_RED), "a lighter one is fine for the warrior")
	tip.get_parent().remove_child(tip)
	tip.free()
