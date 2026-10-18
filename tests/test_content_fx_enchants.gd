extends TestCase
## M6b CONTENT-FX: the 26 new enchantments (GDD 5.7 "50 enchant"). Every one loads with valid
## fields and a tooltip that matches its numbers at all five ranks, rolls only where its kind
## allows, and does what its tooltip says (equip stats reach the stat block / the combat math, procs
## fire through their trigger and act as described).

const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0

const NEW_EQUIP: Array[StringName] = [
	&"scorching", &"glacial", &"sweeping", &"quickened", &"gilded", &"thorned", &"riposting", &"studious",
]
const NEW_ON_HIT: Array[StringName] = [
	&"rupturing", &"warding", &"soothing", &"concussive", &"rimebound", &"smoldering", &"frenzied",
]
const NEW_ON_KILL: Array[StringName] = [&"feasting", &"rousing", &"arcing", &"gravewarded", &"wailing"]
const NEW_WHEN_STRUCK: Array[StringName] = [
	&"barbed", &"mending", &"fortifying", &"bulwarking", &"emberhide", &"clinging",
]
## The 24 enchants that existed before M6b (their ids stay as they are).
const OLD_IDS: Array[StringName] = [
	&"zealous", &"galeforce", &"mighty", &"arcane_touched", &"brutal", &"splitting", &"piercing",
	&"executioners", &"slayers", &"blazing", &"stormbound", &"frostbite", &"venomous", &"vampiric",
	&"bloodlust", &"crusading", &"thundering", &"hallowed", &"shadowflame", &"soulreaping",
	&"detonating", &"greedy", &"frozen_ward", &"retribution",
]
const BANNED: Array[String] = [
	"azeroth", "murloc", "horde", "alliance", "thunderfury", "frozen throne", "silver hand",
	"ashbringer", "frostmourne", "warcraft", "lich king", "sylvanas", "windrunner", "arthas",
	"illidan", "thrall", "stormwind", "orgrimmar", "time is money", "felheart", "shadowcraft",
	"lightforged", "gorehowl", "sulfuras", "doomhammer", "atiesh", "warglaive",
]

var world: Node3D


func before_each() -> void:
	RunState.start_run(1, 99)
	Enemy.invalidate_player_cache()
	world = Fakes.make_world(tree)


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	Enemy.invalidate_player_cache()
	EnemyGrid.mark_dirty()


# --- Helpers ------------------------------------------------------------------------------

static func _all_new() -> Array[StringName]:
	var out: Array[StringName] = []
	out.append_array(NEW_EQUIP)
	out.append_array(NEW_ON_HIT)
	out.append_array(NEW_ON_KILL)
	out.append_array(NEW_WHEN_STRUCK)
	return out


## A piece of jewellery / armour carrying the enchant [param id] at [param rank].
static func _enchanted(id: StringName, rank: int, slot_type: Items.SlotType) -> ItemInstance:
	var item := ItemInstance.new()
	item.source_id = &"test_piece"
	item.display_name = "Test Piece"
	item.slot_type = slot_type
	item.rarity = Items.Rarity.RARE
	item.enchants.append(EnchantRoll.new(Db.get_enchant(id), rank))
	return item


func _hero(class_id: StringName = &"warrior", index: int = 0, pos: Vector3 = Vector3.ZERO) -> Player:
	var p := Fakes.spawn_player(world, index, class_id, pos)
	p.stats.set_source(&"tough", {Stats.STAMINA: 500.0})
	p.hp = p.max_hp()
	return p


func _fake(pos: Vector3) -> Fakes.FakeEnemy:
	var e := Fakes.spawn_enemy(world, pos)
	EnemyGrid.mark_dirty()
	return e


func _real(pos: Vector3, wave: int = 25) -> Enemy:
	var e := Enemy.create(Db.get_enemy(&"skeleton_grunt"), wave)
	world.add_child(e)
	e.global_position = pos
	EnemyGrid.mark_dirty()
	return e


## Equips [param id] at [param rank] on the first slot the enchant lists (a ring for procs that
## allow it) and returns the live proc, forced to fire on every qualifying event.
func _wear(p: Player, id: StringName, rank: int = 0) -> ProcSystem.Proc:
	var e := Db.get_enchant(id)
	var slot_type: Items.SlotType = Items.SlotType.RING if Items.SlotType.RING in e.slot_types else e.slot_types[0]
	if e.kind == EnchantData.Kind.WHEN_STRUCK:
		slot_type = Items.SlotType.CHEST
	check(p.equipment.equip(_enchanted(id, rank, slot_type)), "%s equipped" % id)
	for proc in p.procs.procs:
		if proc.id == id:
			proc.icd = 0.0
			proc.ppm = 100000.0 if proc.ppm > 0.0 else 0.0
			proc.chance = 100.0
			return proc
	check(false, "%s is an active proc" % id)
	return null


static func _sum(values: Array[float]) -> float:
	var total := 0.0
	for v in values:
		total += v
	return total


# --- Content ------------------------------------------------------------------------------

func test_there_are_fifty_enchants_and_the_old_ones_are_untouched() -> void:
	check_eq(Db.enchants.size(), 50, "24 + 26 enchants")
	for id in OLD_IDS:
		check(Db.enchants.has(id), "%s still exists" % id)
	check_eq(_all_new().size(), 26, "26 new ids listed")
	for id in _all_new():
		check(Db.enchants.has(id), "%s loads" % id)
	# Spread over the kinds: 16 equip, 18 on hit, 8 on kill, 8 when struck.
	var per_kind := {}
	for id in Db.enchants:
		var kind: int = Db.enchants[id].kind
		per_kind[kind] = per_kind.get(kind, 0) + 1
	check_eq(per_kind.get(EnchantData.Kind.EQUIP, 0), 16, "equip enchants")
	check_eq(per_kind.get(EnchantData.Kind.ON_HIT, 0), 18, "on-hit enchants")
	check_eq(per_kind.get(EnchantData.Kind.ON_KILL, 0), 8, "on-kill enchants")
	check_eq(per_kind.get(EnchantData.Kind.WHEN_STRUCK, 0), 8, "when-struck enchants")


func test_new_enchants_have_valid_fields_and_tooltips_at_every_rank() -> void:
	var prefixes := {}
	var proc_slots: Array[int] = [Items.SlotType.WEAPON, Items.SlotType.RING, Items.SlotType.TRINKET]
	var struck_slots: Array[int] = [Items.SlotType.HEAD, Items.SlotType.SHOULDERS, Items.SlotType.CHEST,
			Items.SlotType.WEAPON]
	for id in _all_new():
		var e := Db.get_enchant(id)
		if e == null:
			continue
		check_eq(e.id, id, "id matches")
		check(e.prefix != "" and e.prefix.split(" ").size() == 1, "%s: a one-word prefix" % id)
		check(not prefixes.has(e.prefix), "%s: unique prefix %s" % [id, e.prefix])
		prefixes[e.prefix] = true
		for old in OLD_IDS:
			check(Db.get_enchant(old).prefix != e.prefix, "%s: prefix differs from %s" % [id, old])
		check(not e.slot_types.is_empty(), "%s lists its slots" % id)
		for s in e.slot_types:
			check(s >= 0 and s <= Items.SlotType.WEAPON, "%s: valid slot %d" % [id, s])
		check(e.min_rarity >= 1 and e.min_rarity <= 3 and e.weight > 0.0, "%s: rarity / weight" % id)
		check(e.description != "", "%s: has a tooltip" % id)
		match e.kind:
			EnchantData.Kind.EQUIP:
				check(e.min_rarity == 1, "%s: Uncommon items take equip enchants" % id)
				check(not e.equip_stats.is_empty() and e.effect == &"", "%s: stats, no proc" % id)
				for stat in e.equip_stats:
					check(stat in Stats.ALL, "%s: %s is a stat" % [id, stat])
				check(e.description.begins_with("Equip: "), "%s: Equip: line" % id)
			EnchantData.Kind.ON_HIT:
				check(e.effect in ProcSystem.BLOCKS and e.ppm > 0.0, "%s: block and PPM" % id)
				check(e.min_rarity >= 2, "%s: Rare+" % id)
				for s in e.slot_types:
					check(s in proc_slots, "%s: chance on hit only on weapons, rings, trinkets" % id)
				check(e.description.begins_with("Chance on hit: "), "%s: Chance on hit: line" % id)
			EnchantData.Kind.ON_KILL:
				check(e.effect in ProcSystem.BLOCKS and e.chance > 0.0, "%s: block and chance" % id)
				check(e.description.begins_with("On kill: "), "%s: On kill: line" % id)
				check(e.description.contains("%d%%" % int(e.chance)), "%s: the chance is in the text" % id)
			EnchantData.Kind.WHEN_STRUCK:
				check(e.effect in ProcSystem.BLOCKS and e.chance > 0.0, "%s: block and chance" % id)
				for s in e.slot_types:
					check(s in struck_slots, "%s: when struck on head, shoulders, chest, shield" % id)
				check(e.description.begins_with("When struck: "), "%s: When struck: line" % id)
				check(e.description.contains("%d%%" % int(e.chance)), "%s: the chance is in the text" % id)
		if e.is_proc():
			check(e.icd >= 0.5 and e.icd <= 10.0, "%s: internal cooldown 0.5-10 s" % id)
		check(e.school in [&"physical", &"fire", &"frost", &"arcane", &"holy", &"shadow", &"nature"], "%s: school" % id)
		for rank in 5:
			var text := EnchantRoll.new(e, rank).description()
			check(not text.contains("{") and not text.contains("}"), "%s rank %d filled: %s" % [id, rank, text])
		for word in BANNED:
			check(word not in (e.prefix + " " + e.description).to_lower(), "%s: no trademark '%s'" % [id, word])


func test_equip_enchant_numbers_scale_with_the_rank_and_show_in_the_text() -> void:
	var expect := {
		&"scorching": [&"fire_damage", 10.0], &"glacial": [&"frost_damage", 10.0],
		&"sweeping": [&"area_size", 8.0], &"quickened": [&"cooldown_reduction", 5.0],
		&"gilded": [&"gold_find", 10.0], &"thorned": [&"thorns", 3.0],
		&"riposting": [&"parry", 4.0], &"studious": [&"xp_gain", 10.0],
	}
	for id: StringName in expect:
		var stat: StringName = expect[id][0]
		var base: float = expect[id][1]
		var e := Db.get_enchant(id)
		check_eq(e.equip_stats.size(), 1, "%s: one stat" % id)
		check_eq(e.equip_stats.get(stat, -1.0), base, "%s: %s at rank I" % [id, stat])
		for rank in 5:
			var roll := EnchantRoll.new(e, rank)
			check_near(roll.equip_stats()[stat], base * EnchantData.RANK_MULT[rank], 0.0001, "%s rank %d" % [id, rank])
			var shown := str(int(roundf(base * EnchantData.RANK_MULT[rank]))) if absf(base * EnchantData.RANK_MULT[rank] - roundf(base * EnchantData.RANK_MULT[rank])) < 0.05 else "%.1f" % (base * EnchantData.RANK_MULT[rank])
			check(roll.description().contains(shown), "%s rank %d: text shows %s (%s)" % [id, rank, shown, roll.description()])


# --- Equip enchants do what they say ------------------------------------------------------------

func test_school_enchants_raise_the_school_damage() -> void:
	var p := _hero()
	var fire_before := CombatMath.damage_mult_for(p.stats, &"fire")
	var frost_before := CombatMath.damage_mult_for(p.stats, &"frost")
	check(p.equipment.equip(_enchanted(&"scorching", 0, Items.SlotType.NECK)), "Scorching worn")
	check_near(CombatMath.damage_mult_for(p.stats, &"fire") - fire_before, 0.10, 0.0001, "+10% Fire Damage")
	check_near(CombatMath.damage_mult_for(p.stats, &"frost") - frost_before, 0.0, 0.0001, "Frost untouched")
	check(p.equipment.equip(_enchanted(&"glacial", 2, Items.SlotType.RING)), "Glacial III worn")
	check_near(CombatMath.damage_mult_for(p.stats, &"frost") - frost_before, 0.20, 0.0001, "rank III: +20% Frost Damage")
	# A fire bolt proc really hits harder.
	var e := _fake(Vector3(2, 0, 0))
	var bolt := ItemInstance.new()
	bolt.slot_type = Items.SlotType.TRINKET
	bolt.rarity = Items.Rarity.RARE
	bolt.display_name = "Test bolt"
	bolt.unique = true
	bolt.unique_effect = &"bolt"
	bolt.unique_params = {"trigger": "on_hit", "chance": 100.0, "damage": 20.0, "school": "fire"}
	check(p.equipment.equip(bolt), "bolt worn")
	p.procs.on_hit(e, 1.0, p.main_hand, false)
	check_near(e.fake_damage_log[0], 20.0 * 1.10, 0.0001, "20 Fire x 1.10")


func test_area_size_enchant_widens_areas() -> void:
	var p := _hero()
	check_near(CombatMath.area_mult(p.stats), 1.0, 0.0001, "no Area Size yet")
	p.equipment.equip(_enchanted(&"sweeping", 1, Items.SlotType.CHEST))
	check_near(CombatMath.area_mult(p.stats), 1.12, 0.0001, "rank II: +12% Area Size")


func test_cooldown_reduction_enchant_shortens_ability_cooldowns() -> void:
	var p := _hero()
	var ability := p.abilities.slots[0]
	check(ability != null, "the warrior has an ability")
	var before := p.abilities.cooldown_of(ability)
	p.equipment.equip(_enchanted(&"quickened", 0, Items.SlotType.RING))
	check_near(p.abilities.cooldown_of(ability), before * 0.95, 0.0001, "5% shorter cooldown")
	p.equipment.equip(_enchanted(&"quickened", 4, Items.SlotType.RING), Items.EquipSlot.RING_2)
	check_near(p.abilities.cooldown_of(ability), before * (1.0 - 0.05 - 0.15), 0.0001, "plus rank V: 15%")


func test_gold_find_enchant_adds_gold() -> void:
	var p := _hero()
	p.equipment.equip(_enchanted(&"gilded", 0, Items.SlotType.NECK))
	check_near(CombatMath.gold_with_find(10, p.stats), 11.0, 0.0001, "+10% Gold Find on a 10 gold pickup")
	p.equipment.equip(_enchanted(&"gilded", 2, Items.SlotType.RING))
	check_near(CombatMath.gold_with_find(10, p.stats), 13.0, 0.0001, "rank III: +20% more")


func test_thorns_enchant_hurts_melee_attackers() -> void:
	var p := _hero()
	p.equipment.equip(_enchanted(&"thorned", 0, Items.SlotType.CHEST))
	var e := _real(Vector3(1, 0, 0))
	var hp := e.hp
	p.take_damage(2.0, CombatMath.KIND_MELEE, e)
	check_near(hp - e.hp, 3.0, 0.0001, "3 damage back")
	p.invulnerable_left = 0.0
	hp = e.hp
	p.take_damage(2.0, CombatMath.KIND_PROJECTILE, e)
	check_near(hp - e.hp, 0.0, 0.0001, "ranged attackers are not hurt")


func test_parry_enchant_parries_melee_hits() -> void:
	var p := _hero()
	p.equipment.equip(_enchanted(&"riposting", 4, Items.SlotType.RING))
	check_eq(p.stats.get_raw(Stats.PARRY), 12.0, "rank V: +12% Parry")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var parries := 0
	for i in 5000:
		if CombatMath.roll_parry(p.stats, rng):
			parries += 1
	check(parries > 520 and parries < 680, "~12%% of 5000 hits parried (%d)" % parries)


func test_xp_enchant_adds_xp() -> void:
	var p := _hero()
	p.equipment.equip(_enchanted(&"studious", 1, Items.SlotType.NECK))
	check_near(CombatMath.xp_with_gain(20.0, p.stats.get_raw(Stats.XP_GAIN)), 23.0, 0.0001, "rank II: +15% XP")


# --- On-hit procs -------------------------------------------------------------------------------

func test_rupturing_bursts_around_the_target() -> void:
	var p := _hero()
	var proc := _wear(p, &"rupturing")
	check_eq(proc.trigger, ProcSystem.TRIGGER_ON_HIT, "on hit")
	check_eq(proc.effect, &"explode", "an explosion")
	var target := _fake(Vector3(5, 0, 0))
	var near := _fake(Vector3(6.4, 0, 0))
	var far := _fake(Vector3(9.5, 0, 0))
	p.procs.on_hit(target, 10.0, p.main_hand, false)
	check_eq(p.procs.fire_count(&"rupturing"), 1, "fired")
	check_eq([target.fake_hits(), near.fake_hits(), far.fake_hits()], [1, 1, 0], "target and the enemy within 2 m")
	check_near(target.fake_damage_log[0], 12.0, 0.0001, "12 Arcane damage")
	# Rank III doubles the damage, not the radius.
	p.equipment.unequip(Items.EquipSlot.RING_1)
	_wear(p, &"rupturing", 2)
	p.procs.on_hit(target, 10.0, p.main_hand, false)
	check_near(target.fake_damage_log[1], 24.0, 0.0001, "rank III: 24")
	check_eq(far.fake_hits(), 0, "the radius is fixed")


func test_warding_raises_a_shield_of_max_hp() -> void:
	var p := _hero()
	_wear(p, &"warding")
	var e := _fake(Vector3(2, 0, 0))
	check_near(p.procs.shield_hp, 0.0, 0.0001, "no shield yet")
	p.procs.on_hit(e, 10.0, p.main_hand, false)
	check_near(p.procs.shield_hp, p.max_hp() * 0.04, 0.001, "4% of Max HP")
	check_near(p.procs.shield_left, 5.0, 0.001, "for 5 sec")
	p.procs._physics_process(5.1)
	check_near(p.procs.shield_hp, 0.0, 0.0001, "gone after 5 sec")


func test_soothing_heals_the_most_wounded_ally() -> void:
	var p := _hero()
	var ally := _hero(&"paladin", 1, Vector3(3, 0, 0))
	Enemy.invalidate_player_cache()
	ally.hp = 100.0
	p.hp = p.max_hp() - 5.0
	_wear(p, &"soothing")
	var e := _fake(Vector3(2, 0, 0))
	p.procs.on_hit(e, 10.0, p.main_hand, false)
	check_near(ally.hp, 100.0 + ally.max_hp() * 0.03, 0.001, "the ally got 3% of their Max HP")
	check_near(p.hp, p.max_hp() - 5.0, 0.0001, "the wearer was fine")


func test_concussive_stuns_the_target() -> void:
	var p := _hero()
	_wear(p, &"concussive")
	var e := _real(Vector3(2, 0, 0))
	check(not e.is_stunned(), "not stunned")
	p.procs.on_hit(e, 10.0, p.main_hand, false)
	check(e.is_stunned(), "stunned")


func test_rimebound_freezes_and_slows_the_crowd_around_the_target() -> void:
	var p := _hero()
	_wear(p, &"rimebound")
	var target := _real(Vector3(4, 0, 0))
	var near := _real(Vector3(5.5, 0, 0))
	var far := _real(Vector3(8.0, 0, 0))
	var hp_t := target.hp
	var hp_n := near.hp
	p.procs.on_hit(target, 10.0, p.main_hand, false)
	check_near(hp_t - target.hp, 8.0, 0.0001, "8 Frost damage")
	check_near(hp_n - near.hp, 8.0, 0.0001, "the neighbour too")
	check(target.is_slowed() and target.slow_pct == 40.0 and near.is_slowed(), "slowed by 40%")
	check(far.hp == far.max_hp and not far.is_slowed(), "the far one is untouched")


func test_smoldering_burns_and_stacks_twice() -> void:
	var p := _hero()
	var proc := _wear(p, &"smoldering")
	var e := _fake(Vector3(2, 0, 0))
	p.procs.on_hit(e, 10.0, p.main_hand, false)
	check_eq(p.procs.dot_stacks(e, &"smoldering"), 1, "one stack")
	p.procs.on_hit(e, 10.0, p.main_hand, false)
	p.procs.on_hit(e, 10.0, p.main_hand, false)
	check_eq(p.procs.dot_stacks(e, &"smoldering"), 2, "at most two stacks")
	check_eq(proc.school, &"fire", "fire")
	for i in 300:
		p.procs._physics_process(DT)
	check_near(_sum(e.fake_damage_log), 28.0, 0.05, "14 Fire per stack over 4 sec")
	check_eq(p.procs.dot_count(), 0, "burned out")


func test_frenzied_grants_damage_for_six_seconds() -> void:
	var p := _hero()
	_wear(p, &"frenzied")
	var e := _fake(Vector3(2, 0, 0))
	var before := p.stats.damage_mult()
	p.procs.on_hit(e, 10.0, p.main_hand, false)
	check_near(p.stats.damage_mult() - before, 0.12, 0.0001, "+12% Damage")
	p.procs._physics_process(5.9)
	check_near(p.stats.damage_mult() - before, 0.12, 0.0001, "still there at 5.9 s")
	p.procs._physics_process(0.3)
	check_near(p.stats.damage_mult() - before, 0.0, 0.0001, "gone after 6 sec")


# --- On-kill procs ------------------------------------------------------------------------------

func _corpse(pos: Vector3) -> Fakes.FakeEnemy:
	var c := _fake(pos)
	c.fake_dead = true
	return c


func test_feasting_restores_max_hp_on_a_kill() -> void:
	var p := _hero()
	var proc := _wear(p, &"feasting")
	check_eq(proc.trigger, ProcSystem.TRIGGER_ON_KILL, "on kill")
	p.hp = 100.0
	p.procs.on_kill(_corpse(Vector3(3, 0, 0)))
	check_near(p.hp, 100.0 + p.max_hp() * 0.03, 0.001, "3% of Max HP")
	p.hp = p.max_hp()
	p.procs.on_kill(_corpse(Vector3(3, 0, 0)))
	check_eq(p.hp, p.max_hp(), "never above Max HP")


func test_rousing_grants_haste_for_four_seconds() -> void:
	var p := _hero()
	_wear(p, &"rousing")
	p.procs.on_kill(_corpse(Vector3(3, 0, 0)))
	check_eq(p.stats.get_stat(Stats.HASTE), 12.0, "+12% Haste")
	p.procs._physics_process(4.1)
	check_eq(p.stats.get_stat(Stats.HASTE), 0.0, "gone after 4 sec")


func test_arcing_leaps_between_three_enemies() -> void:
	var p := _hero()
	_wear(p, &"arcing")
	var corpse := _corpse(Vector3(2, 0, 0))
	var a := _fake(Vector3(3, 0, 0))
	var b := _fake(Vector3(6, 0, 0))
	var c := _fake(Vector3(9, 0, 0))
	var d := _fake(Vector3(12, 0, 0))
	p.procs.on_kill(corpse)
	check_eq([a.fake_hits(), b.fake_hits(), c.fake_hits(), d.fake_hits()], [1, 1, 1, 0], "three targets, each once")
	check_near(a.fake_damage_log[0], 12.0, 0.0001, "12 Nature damage")
	check_eq(corpse.fake_hits(), 0, "the corpse is no target")


func test_gravewarded_raises_a_shield_on_a_kill() -> void:
	var p := _hero()
	_wear(p, &"gravewarded")
	p.procs.on_kill(_corpse(Vector3(3, 0, 0)))
	check_near(p.procs.shield_hp, p.max_hp() * 0.05, 0.001, "5% of Max HP")
	check_near(p.procs.shield_left, 5.0, 0.001, "for 5 sec")


func test_wailing_stuns_around_the_corpse() -> void:
	var p := _hero()
	_wear(p, &"wailing")
	var corpse := _corpse(Vector3(5, 0, 0))
	var near := _real(Vector3(7.5, 0, 0))
	var far := _real(Vector3(9.5, 0, 0))
	var hp := near.hp
	p.procs.on_kill(corpse)
	check_near(hp - near.hp, 10.0, 0.0001, "10 Shadow damage")
	check(near.is_stunned(), "stunned")
	check(far.hp == far.max_hp and not far.is_stunned(), "outside 3 m: untouched")


# --- When-struck procs --------------------------------------------------------------------------

func test_barbed_impales_the_attacker() -> void:
	var p := _hero()
	var proc := _wear(p, &"barbed")
	check_eq(proc.trigger, ProcSystem.TRIGGER_WHEN_STRUCK, "when struck")
	var e := _fake(Vector3(1, 0, 0))
	p.procs.on_struck(e, 2.0)
	check_near(e.fake_damage_log[0], 5.0, 0.0001, "5 Nature damage")
	check_eq(p.procs.dot_stacks(e, &"barbed"), 1, "and a bleed")
	for i in 200:
		p.procs._physics_process(DT)
	check_near(_sum(e.fake_damage_log), 5.0 + 8.0, 0.05, "8 more over 3 sec")


func test_mending_heals_when_struck() -> void:
	var p := _hero()
	_wear(p, &"mending")
	var e := _fake(Vector3(1, 0, 0))
	p.hp = 100.0
	p.procs.on_struck(e, 2.0)
	check_near(p.hp, 100.0 + p.max_hp() * 0.04, 0.001, "4% of Max HP")


func test_fortifying_grants_armor_for_five_seconds() -> void:
	var p := _hero()
	_wear(p, &"fortifying")
	var e := _fake(Vector3(1, 0, 0))
	var before := p.stats.get_stat(Stats.ARMOR)
	p.procs.on_struck(e, 2.0)
	check_eq(p.stats.get_stat(Stats.ARMOR) - before, 4.0, "+4 Armor")
	p.procs._physics_process(5.1)
	check_eq(p.stats.get_stat(Stats.ARMOR) - before, 0.0, "gone after 5 sec")


func test_bulwarking_raises_a_ward_when_struck() -> void:
	var p := _hero()
	_wear(p, &"bulwarking")
	var e := _fake(Vector3(1, 0, 0))
	p.procs.on_struck(e, 2.0)
	check_near(p.procs.shield_hp, p.max_hp() * 0.06, 0.001, "6% of Max HP")
	check_near(p.procs.shield_left, 4.0, 0.001, "for 4 sec")


func test_emberhide_burns_the_crowd_around_the_wearer() -> void:
	var p := _hero()
	_wear(p, &"emberhide")
	var near := _real(Vector3(1.5, 0, 0))
	var far := _real(Vector3(0, 0, 5.0))
	var hp := near.hp
	p.procs.on_struck(near, 2.0)
	check_near(hp - near.hp, 8.0, 0.0001, "8 Fire damage")
	check(far.hp == far.max_hp, "outside 2.5 m: untouched")


func test_clinging_slows_the_attacker() -> void:
	var p := _hero()
	_wear(p, &"clinging")
	var e := _real(Vector3(1, 0, 0))
	p.procs.on_struck(e, 2.0)
	check(e.is_slowed() and e.slow_pct == 40.0, "slowed by 40%")


func test_struck_enchants_fire_through_player_take_damage() -> void:
	var p := _hero()
	_wear(p, &"mending")
	var e := _real(Vector3(1, 0, 0))
	p.hp = 100.0
	p.take_damage(2.0, CombatMath.KIND_MELEE, e)
	check(p.procs.fire_count(&"mending") == 1 and p.hp > 100.0 - 2.0, "the hit triggered it (hp %s)" % p.hp)


# --- Real trigger paths ---------------------------------------------------------------------------

func test_new_proc_enchants_fire_at_their_documented_rates() -> void:
	# On hit: PPM x weapon cooldown / 60 per attack.
	var p := _hero()
	p.equipment.equip(_enchanted(&"concussive", 0, Items.SlotType.RING))  # 2 PPM, 5 s ICD
	var e := _fake(Vector3(30, 0, 0))
	var axe := Db.get_weapon(&"two_hand_axe")  # 1.5 s -> 5% per hit
	for i in 4000:
		p.procs._physics_process(10.0)
		p.procs.on_hit(e, 5.0, axe, false)
	var n := p.procs.fire_count(&"concussive")
	check(n > 140 and n < 260, "~5%% of 4000 axe hits (%d)" % n)
	# On kill: the listed percentage.
	var q := _hero(&"warrior", 1, Vector3(0, 0, 20))
	q.equipment.equip(_enchanted(&"rousing", 0, Items.SlotType.RING))  # 8%
	var corpse := _corpse(Vector3(3, 0, 20))
	for i in 3000:
		q.procs._physics_process(10.0)
		q.procs.on_kill(corpse)
	var k := q.procs.fire_count(&"rousing")
	check(k > 180 and k < 300, "~8%% of 3000 kills (%d)" % k)


# --- Generator ----------------------------------------------------------------------------------

func test_every_new_enchant_fits_some_item_and_rolls() -> void:
	for id in _all_new():
		var e := Db.get_enchant(id)
		var fitted := false
		for slot in e.slot_types:
			var item := ItemInstance.new()
			item.slot_type = slot as Items.SlotType
			item.rarity = Items.Rarity.EPIC
			if slot == Items.SlotType.WEAPON:
				item.weapon = Db.get_weapon(&"shield" if e.kind == EnchantData.Kind.WHEN_STRUCK else &"sword")
			if ItemGenerator.enchant_fits(e, item):
				fitted = true
		check(fitted, "%s fits an Epic item of one of its slots" % id)
		var unc := ItemInstance.new()
		unc.slot_type = Items.SlotType.RING
		unc.rarity = Items.Rarity.UNCOMMON
		check_eq(ItemGenerator.enchant_fits(e, unc), e.kind == EnchantData.Kind.EQUIP and Items.SlotType.RING in e.slot_types,
				"%s: Uncommon items take equip enchants only" % id)
	# 3000 generated items roll every one of the 26 at least once.
	var seen := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var sources: Array[ItemGenerator.Source] = [ItemGenerator.Source.LOOT, ItemGenerator.Source.SHOP, ItemGenerator.Source.BOSS]
	for i in 3000:
		var item := ItemGenerator.generate(sources[i % 3], 1 + (i % 25), rng,
				{&"rarity": [Items.Rarity.UNCOMMON, Items.Rarity.RARE, Items.Rarity.EPIC, Items.Rarity.LEGENDARY][i % 4]})
		if item == null:
			continue
		for roll in item.enchants:
			seen[roll.enchant.id] = true
	for id in _all_new():
		check(seen.has(id), "%s was rolled on a generated item" % id)
