extends TestCase
## ProcSystem (GDD 5.7): enchant content, every building block, triggers (on hit with PPM,
## on kill, when struck, low HP, periodic, equip), internal cooldowns, no proc chains.

const Fakes := preload("res://tests/player_fakes.gd")
const EFakes := preload("res://tests/enemies_fakes.gd")
const DT := 1.0 / 60.0

const ENCHANT_IDS: Array[StringName] = [
	&"zealous", &"galeforce", &"mighty", &"arcane_touched", &"brutal", &"splitting", &"piercing",
	&"executioners", &"slayers", &"blazing", &"stormbound", &"frostbite", &"venomous", &"vampiric",
	&"bloodlust", &"crusading", &"thundering", &"hallowed", &"shadowflame", &"soulreaping",
	&"detonating", &"greedy", &"frozen_ward", &"retribution",
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

## A trinket with a unique effect (the shared vocabulary of unique items).
static func unique(effect: StringName, params: Dictionary, slot_type: Items.SlotType = Items.SlotType.TRINKET) -> ItemInstance:
	var item := ItemInstance.new()
	item.source_id = StringName("test_%s" % effect)
	item.display_name = "Test %s" % String(effect).capitalize()
	item.slot_type = slot_type
	item.rarity = Items.Rarity.LEGENDARY
	item.unique = true
	item.unique_effect = effect
	item.unique_params = params
	return item


## A ring carrying the enchant [param id] at [param rank].
static func enchanted(id: StringName, rank: int = 0, slot_type: Items.SlotType = Items.SlotType.RING) -> ItemInstance:
	var item := ItemInstance.new()
	item.source_id = &"test_ring"
	item.display_name = "Test Ring"
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


func _real(pos: Vector3, wave: int = 1) -> Enemy:
	var e := Enemy.create(Db.get_enemy(&"skeleton_grunt"), wave)
	world.add_child(e)
	e.global_position = pos
	EnemyGrid.mark_dirty()
	return e


static func _sum(values: Array[float]) -> float:
	var total := 0.0
	for v in values:
		total += v
	return total


# --- Content --------------------------------------------------------------------------------

func test_the_24_enchants_of_the_gdd() -> void:
	check_eq(ENCHANT_IDS.size(), 24, "GDD 5.7 lists 24")
	var proc_slots: Array[int] = [Items.SlotType.WEAPON, Items.SlotType.RING, Items.SlotType.TRINKET]
	var struck_slots: Array[int] = [Items.SlotType.HEAD, Items.SlotType.SHOULDERS, Items.SlotType.CHEST,
			Items.SlotType.WEAPON]
	for id in ENCHANT_IDS:
		var e := Db.get_enchant(id)
		check(e != null, "%s exists" % id)
		if e == null:
			continue
		check_eq(e.id, id, "id")
		check(e.prefix != "" and e.description != "", "%s has a prefix and a description" % id)
		check(not e.slot_types.is_empty(), "%s has slots" % id)
		check(e.min_rarity >= 1 and e.weight > 0.0, "%s rarity / weight" % id)
		for s in e.slot_types:
			check(s >= 0 and s <= Items.SlotType.WEAPON, "%s valid slot %d" % [id, s])
		for rank in 3:
			var text := EnchantRoll.new(e, rank).description()
			check(not text.contains("{") and not text.contains("}"), "%s rank %d filled: %s" % [id, rank, text])
		match e.kind:
			EnchantData.Kind.EQUIP:
				check(not e.equip_stats.is_empty(), "%s equip stats" % id)
				for stat in e.equip_stats:
					check(stat in Stats.ALL, "%s: %s is a stat" % [id, stat])
			EnchantData.Kind.ON_HIT:
				check(e.effect in ProcSystem.BLOCKS, "%s effect %s" % [id, e.effect])
				check(e.ppm > 0.0, "%s has a PPM" % id)
				for s in e.slot_types:
					check(s in proc_slots, "%s: chance on hit only on weapons, rings, trinkets" % id)
			EnchantData.Kind.WHEN_STRUCK:
				check(e.effect in ProcSystem.BLOCKS, "%s effect" % id)
				for s in e.slot_types:
					check(s in struck_slots, "%s: when struck on chest, shoulders, head, shield" % id)
			EnchantData.Kind.ON_KILL:
				check(e.effect in ProcSystem.BLOCKS, "%s effect" % id)
				check(e.chance > 0.0, "%s has a chance" % id)
		if e.is_proc():
			check(e.icd >= 0.5 and e.icd <= 20.0, "%s internal cooldown 0.5-20 s" % id)
	check(Db.get_enchant(&"splitting").requires_projectile, "Splitting only on projectile weapons")
	check_eq(EnchantRoll.new(Db.get_enchant(&"blazing"), 2).description(),
			"Chance on hit: Hurls a fireball for 40 Fire damage.", "rank III doubles the damage")
	check(EnchantRoll.new(Db.get_enchant(&"stormbound"), 2).description().contains("between 3 enemies"),
			"fixed values do not scale")


func test_rank_scaling_and_fixed_params() -> void:
	var storm := ProcSystem.proc_from_enchant(EnchantRoll.new(Db.get_enchant(&"stormbound"), 1))
	check_eq(storm.trigger, ProcSystem.TRIGGER_ON_HIT, "on hit")
	check_eq(storm.num("damage"), 22.5, "15 x 1.5")
	check_eq(storm.num("targets"), 3.0, "targets_fixed stays 3")
	check_eq(storm.school, &"nature", "school from the enchant")
	check_eq(storm.ppm, 3.0, "ppm")
	var lust := ProcSystem.proc_from_enchant(EnchantRoll.new(Db.get_enchant(&"bloodlust"), 2))
	check_eq(lust.num("haste"), 40.0, "buff stat scales")
	check_eq(lust.num("duration"), 6.0, "duration fixed")
	check(ProcSystem.proc_from_enchant(EnchantRoll.new(Db.get_enchant(&"mighty"))) == null, "equip: no proc")


func test_refresh_collects_enchants_and_uniques() -> void:
	var p := _hero()
	check(p.procs != null and p.procs.name == "Procs" and p.procs.get_parent() == p, "Procs child")
	check(p.procs.procs.is_empty(), "starting weapons have no procs")
	var ring := enchanted(&"blazing")
	var trinket := unique(&"nova", {"trigger": "periodic", "interval": 3.0, "damage": 5.0})
	p.equipment.add_to_backpack(ring)
	p.equipment.equip(ring)
	p.equipment.equip(trinket)
	check_eq(p.procs.procs.size(), 2, "both found on equipment.changed")
	p.equipment.unequip(Items.EquipSlot.RING_1)
	check_eq(p.procs.procs.size(), 1, "an unequipped item stops")
	check_eq(p.procs.procs[0].trigger, ProcSystem.TRIGGER_PERIODIC, "unique trigger from its params")


# --- Chances and cooldowns ---------------------------------------------------------------

func test_ppm_chance_statistics() -> void:
	var p := _hero()
	p.equipment.equip(enchanted(&"blazing"))  # 4 PPM, 0.5 s ICD
	var e := _fake(Vector3(30, 0, 0))
	var slow := Db.get_weapon(&"two_hand_axe")  # 1.5 s -> 10% per hit
	var fast := Db.get_weapon(&"dagger")  # 0.5 s -> 3.33% per hit
	var hits := 3000
	for i in hits:
		p.procs._physics_process(1.0)  # the ICD never blocks
		p.procs.on_hit(e, 5.0, slow, false)
	var slow_procs := p.procs.fire_count(&"blazing")
	check(slow_procs > 240 and slow_procs < 360, "~10%% of %d axe hits (%d)" % [hits, slow_procs])
	for i in hits:
		p.procs._physics_process(1.0)
		p.procs.on_hit(e, 5.0, fast, false)
	var fast_procs := p.procs.fire_count(&"blazing") - slow_procs
	check(fast_procs > 70 and fast_procs < 130, "~3.3%% of %d dagger hits (%d)" % [hits, fast_procs])
	# Procs per minute match: the dagger hits 3x as often.
	check_near(float(fast_procs) * 3.0 / float(slow_procs), 1.0, 0.25, "same procs per minute")


## On-hit procs roll once per attack, not once per enemy a melee arc / projectile fan /
## pierce hits; the attacked target gets them. Per-target effects (damage, Executioner /
## Slayer, hit_dealt) stay per hit.
func test_on_hit_procs_roll_once_per_attack() -> void:
	var p := _hero()
	p.equipment.equip(unique(&"bolt", {"trigger": "on_hit", "chance": 100.0, "damage": 1.0}))
	var side_a := _fake(Vector3(1.2, 0, -0.6))
	var target := _fake(Vector3(1.5, 0, 0))
	var side_b := _fake(Vector3(1.2, 0, 0.6))
	var hits: Array[Node3D] = []
	p.hit_dealt.connect(func(_d: float, t: Node3D) -> void: hits.append(t))
	p.weapons[0].attack(target)
	check_eq(hits.size(), 3, "the swing hits all three")
	check_eq(hits[0], target, "the attacked enemy first")
	check_eq(p.procs.fire_count(&"test_bolt"), 1, "one proc roll for the whole swing")
	check_eq([target.fake_hits(), side_a.fake_hits(), side_b.fake_hits()], [2, 1, 1],
			"the bolt hit the attacked enemy")
	# Projectiles: a fan of three wand bolts (Extra Projectile) and pierce share one roll.
	var m := _hero(&"mage", 1, Vector3(0, 0, 20))
	m.equipment.equip(unique(&"bolt", {"trigger": "on_hit", "chance": 100.0, "damage": 1.0}))
	m.stats.set_source(&"test", {Stats.EXTRA_PROJECTILE: 2.0, Stats.PIERCE: 3.0})
	var row: Array[Fakes.FakeEnemy] = []
	for i in 3:
		row.append(_fake(Vector3(0, 0, 16.5 - i * 1.2)))
	var landed: Array[Node3D] = []
	m.hit_dealt.connect(func(_d: float, t: Node3D) -> void: landed.append(t))
	m.weapons[0].attack(row[0])
	for i in 120:
		for node in tree.get_nodes_in_group(&"projectiles"):
			(node as Projectile).advance(DT)
	check(landed.size() >= 3, "several projectile hits (%d)" % landed.size())
	check_eq(m.procs.fire_count(&"test_bolt"), 1, "still one proc roll for the attack")
	# The next attack rolls again.
	p.procs._physics_process(0.1)
	p.weapons[0].attack(target)
	check_eq(p.procs.fire_count(&"test_bolt"), 2, "one roll per attack")


func test_internal_cooldown() -> void:
	var p := _hero()
	p.equipment.equip(unique(&"bolt", {"trigger": "on_hit", "chance": 100.0, "icd": 2.0, "damage": 1.0}))
	var e := _fake(Vector3(2, 0, 0))
	var t := 0.0
	while t < 10.0 - 0.001:
		p.procs.on_hit(e, 1.0, p.main_hand, false)
		p.procs._physics_process(0.1)
		t += 0.1
	check_eq(p.procs.fire_count(&"test_bolt"), 5, "every 2 s over 10 s")
	check_eq(e.fake_hits(), 5, "five bolts landed")


func test_on_kill_and_when_struck_chances() -> void:
	var p := _hero()
	p.equipment.equip(unique(&"gold", {"trigger": "on_kill", "chance": 25.0, "amount": 1.0}))
	var corpse := _fake(Vector3(3, 0, 0))
	for i in 2000:
		p.procs.on_kill(corpse)
	var n := p.procs.fire_count(&"test_gold")
	check(n > 420 and n < 580, "~25%% of 2000 kills (%d)" % n)
	check_eq(RunState.gold, n, "+1 gold each")


# --- Blocks -----------------------------------------------------------------------------

func test_bolt_scales_with_spell_power_and_school_and_never_chains() -> void:
	var p := _hero()
	p.equipment.equip(unique(&"bolt", {"trigger": "on_hit", "chance": 100.0, "damage": 20.0, "school": "fire"}))
	p.equipment.equip(unique(&"chain", {"trigger": "on_hit", "chance": 100.0, "damage": 4.0, "targets": 2}), Items.EquipSlot.TRINKET_2)
	p.stats.set_source(&"test", {Stats.SPELL_POWER: 10.0, Stats.FIRE_DAMAGE: 50.0})
	var e := _fake(Vector3(1.5, 0, 0))
	var dealt: Array[float] = []
	p.hit_dealt.connect(func(d: float, _t: Node3D) -> void: dealt.append(d))
	p.weapons[0].attack(e)
	check_eq(dealt.size(), 1, "only the weapon hit is a hit (proc damage never triggers procs)")
	check_eq(p.procs.fire_count(&"test_bolt"), 1, "bolt once")
	check_eq(p.procs.fire_count(&"test_chain"), 1, "chain once")
	check_eq(e.fake_hits(), 3, "weapon + bolt + chain")
	if e.fake_hits() == 3:
		check_near(e.fake_damage_log[1], (20.0 + 10.0) * 1.5, 0.0001, "(20 + SP) x fire %")
		check_near(e.fake_damage_log[2], 4.0, 0.0001, "physical chain: + Attack Power (0), no Spell Power")
		check(not e.fake_crit_log[1], "procs never crit")
		check(e.fake_attacker_log[1] == p, "proc damage credited to the player")
	check(RunState.damage_by_player.get(0, 0.0) > dealt[0] if not dealt.is_empty() else false,
			"proc damage recorded")


func test_chain_jumps_to_distinct_targets() -> void:
	var p := _hero()
	p.equipment.equip(unique(&"chain", {"trigger": "on_hit", "chance": 100.0, "damage": 5.0,
			"targets": 3, "school": "nature"}))
	var a := _fake(Vector3(2, 0, 0))
	var b := _fake(Vector3(5, 0, 0))
	var c := _fake(Vector3(8, 0, 0))
	var d := _fake(Vector3(11, 0, 0))
	var far := _fake(Vector3(30, 0, 0))
	p.procs.on_hit(a, 1.0, p.main_hand, false)
	check_eq([a.fake_hits(), b.fake_hits(), c.fake_hits(), d.fake_hits(), far.fake_hits()],
			[1, 1, 1, 0, 0], "3 targets, each once, nearest jumps")
	check_near(b.fake_damage_log[0], 5.0, 0.0001, "nature: + Spell Power (0)")


func test_dot_stacks_ticks_and_spreads() -> void:
	var p := _hero()
	p.equipment.equip(unique(&"dot", {"trigger": "on_hit", "chance": 100.0, "damage": 12.0,
			"duration": 3.0, "stacks": 3, "school": "nature", "spread": 3.0}))
	var e := _fake(Vector3(2, 0, 0))
	var near := _fake(Vector3(4, 0, 0))
	var far := _fake(Vector3(12, 0, 0))
	p.procs.on_hit(e, 1.0, p.main_hand, false)
	p.procs.on_hit(e, 1.0, p.main_hand, false)
	check_eq(p.procs.dot_stacks(e, &"test_dot"), 2, "two stacks")
	for i in 180:
		p.procs._physics_process(DT)
	check_eq(e.fake_hits(), 6, "a tick every 0.5 s for 3 s")
	check_near(_sum(e.fake_damage_log), 24.0, 0.01, "12 per stack over 3 s")
	check_eq(p.procs.dot_count(), 0, "expired")
	p.procs.on_hit(e, 1.0, p.main_hand, false)
	e.fake_dead = true
	p.procs._physics_process(DT)
	check_eq(p.procs.dot_stacks(near, &"test_dot"), 1, "spread to the neighbour when the target died")
	check_eq(p.procs.dot_stacks(far, &"test_dot"), 0, "not beyond the spread radius")


func test_nova_with_stun_slow_and_area_size() -> void:
	var p := _hero()
	p.equipment.equip(unique(&"nova", {"trigger": "on_hit", "chance": 100.0, "damage": 5.0,
			"radius": 2.0, "at": "self", "stun": 1.0, "slow": 40.0, "school": "frost"}))
	var inside := _real(Vector3(1.5, 0, 0), 20)
	var outside := _real(Vector3(0, 0, 3.6), 20)
	p.procs.on_hit(inside, 1.0, p.main_hand, false)
	check(inside.hp < inside.max_hp and inside.is_stunned() and inside.is_slowed(), "hit, stunned, slowed")
	check(outside.hp == outside.max_hp and not outside.is_stunned(), "outside untouched")
	p.stats.set_source(&"test", {Stats.AREA_SIZE: 100.0})
	p.procs._physics_process(1.0)
	p.procs.on_hit(inside, 1.0, p.main_hand, false)
	check(outside.hp < outside.max_hp, "doubled radius reaches it")


func test_explode_at_the_corpse_on_kill() -> void:
	var p := _hero()
	p.equipment.equip(unique(&"explode", {"trigger": "on_kill", "chance": 100.0, "damage": 3.0,
			"radius": 2.0, "school": "fire"}))
	var victim := _real(Vector3(1.4, 0, 0), 1)
	var neighbour := _real(Vector3(2.4, 0, 1.6), 25)
	var killed: Array[Node3D] = []
	p.enemy_killed.connect(func(en: Node3D) -> void: killed.append(en))
	victim.take_damage(10000.0, false, p)
	check(victim.is_dead(), "killed")
	check_eq(killed.size(), 1, "kill notified")
	check_eq(p.procs.fire_count(&"test_explode"), 1, "corpse exploded")
	check(neighbour.hp < neighbour.max_hp, "the blast hit the neighbour")


func test_extra_attack_proc_cannot_chain() -> void:
	var p := _hero()
	p.equipment.equip(unique(&"extra_attack", {"trigger": "on_hit", "chance": 100.0, "count": 2}))
	p.stats.set_source(&"test", {Stats.EXTRA_ATTACK: 100.0})
	var e := _fake(Vector3(1.5, 0, 0))
	p.weapons[0].attack(e)
	check_eq(e.fake_hits(), 4, "1 hit + 2 proc extras + 1 Extra Attack, nothing more")
	check_eq(p.procs.fire_count(&"test_extra_attack"), 1, "extra hits never trigger it again")
	# A ranged weapon: the proc fires on impact and shoots twice more.
	var m := _hero(&"mage", 1, Vector3(0, 0, 10))
	m.equip_weapons(Db.get_weapon(&"wand"), null)
	m.equipment.equip(unique(&"extra_attack", {"trigger": "on_hit", "chance": 100.0, "count": 2}))
	var target := _fake(Vector3(0, 0, 6))
	m.weapons[0].attack(target)
	for i in 120:
		for node in tree.get_nodes_in_group(&"projectiles"):
			(node as Projectile).advance(DT)
	check_eq(target.fake_hits(), 3, "bolt + two extra bolts")
	check_eq(m.procs.fire_count(&"test_extra_attack"), 1, "once")


func test_buffs_stack_expire_and_equip_buffs_last() -> void:
	var p := _hero()
	p.equipment.equip(unique(&"buff", {"trigger": "on_hit", "chance": 100.0, "stats": {"haste": 10.0},
			"duration": 4.0, "max_stacks": 2}))
	var e := _fake(Vector3(2, 0, 0))
	p.procs.on_hit(e, 1.0, p.main_hand, false)
	check_eq(p.stats.get_stat(Stats.HASTE), 10.0, "+10% Haste")
	p.procs.on_hit(e, 1.0, p.main_hand, false)
	p.procs.on_hit(e, 1.0, p.main_hand, false)
	check_eq(p.stats.get_stat(Stats.HASTE), 20.0, "two stacks at most")
	p.procs._physics_process(4.1)
	check_eq(p.stats.get_stat(Stats.HASTE), 0.0, "expired")
	# Crusading: primary stat + heal, rank I.
	p.equipment.equip(enchanted(&"crusading"))
	var proc: ProcSystem.Proc = null
	for pr in p.procs.procs:
		if pr.id == &"crusading":
			proc = pr
	check(proc != null, "crusading active")
	if proc != null:
		p.hp = 10.0
		p.procs._run(proc, e, Vector3.ZERO, p.main_hand)
		check_eq(p.stats.get_raw(Stats.STRENGTH), 5.0, "+5 Strength (the warrior's primary stat)")
		check_eq(p.hp, 12.0, "healed 2")
	var amulet := unique(&"buff", {"trigger": "equip", "stats": {"crit": 7.0}}, Items.SlotType.NECK)
	p.equipment.equip(amulet)
	check_eq(p.stats.get_stat(Stats.CRIT), 7.0, "equip buff while worn")
	p.procs._physics_process(100.0)
	check_eq(p.stats.get_stat(Stats.CRIT), 7.0, "never expires")
	p.equipment.unequip(Items.EquipSlot.NECK)
	check_eq(p.stats.get_stat(Stats.CRIT), 0.0, "gone when removed")


func test_heal_drain_and_smite_heal_target_the_right_hero() -> void:
	var p := _hero()
	var ally := _hero(&"paladin", 1, Vector3(3, 0, 0))
	Enemy.invalidate_player_cache()
	p.hp = p.max_hp() - 50.0
	ally.hp = 10.0
	p.equipment.equip(unique(&"heal", {"trigger": "on_hit", "chance": 100.0, "amount": 6.0, "target": "lowest_ally"}))
	var e := _real(Vector3(1.5, 0, 0), 25)
	p.procs.on_hit(e, 1.0, p.main_hand, false)
	check_eq(ally.hp, 16.0, "the most injured ally was healed")
	p.equipment.unequip(Items.EquipSlot.TRINKET_1)
	p.equipment.equip(unique(&"drain", {"trigger": "on_hit", "chance": 100.0, "damage": 8.0, "school": "shadow"}))
	var before := p.hp
	var hp_e := e.hp
	p.procs.on_hit(e, 1.0, p.main_hand, false)
	check_near(hp_e - e.hp, 8.0, 0.0001, "drained 8")
	check_near(p.hp - before, 8.0, 0.0001, "healed the wearer by the same")
	p.equipment.unequip(Items.EquipSlot.TRINKET_1)
	p.equipment.equip(unique(&"smite_heal", {"trigger": "on_hit", "chance": 100.0, "damage": 5.0,
			"heal": 3.0, "school": "holy"}))
	hp_e = e.hp
	p.procs.on_hit(e, 1.0, p.main_hand, false)
	check_near(hp_e - e.hp, 5.0, 0.0001, "smite")
	check_eq(ally.hp, 19.0, "ally healed 3")


func test_slow_stun_gold_and_resource_blocks() -> void:
	var p := _hero()
	var e := _real(Vector3(2, 0, 0), 25)
	p.equipment.equip(unique(&"slow", {"trigger": "on_hit", "chance": 100.0, "pct": 50.0, "duration": 3.0}))
	p.equipment.equip(unique(&"stun", {"trigger": "on_hit", "chance": 100.0, "duration": 1.0}), Items.EquipSlot.TRINKET_2)
	p.procs.on_hit(e, 1.0, p.main_hand, false)
	check(e.is_slowed() and e.slow_pct == 50.0, "slowed 50%")
	check(e.is_stunned(), "stunned")
	p.equipment.equip(unique(&"gold", {"trigger": "on_hit", "chance": 100.0, "amount": 1.5}), Items.EquipSlot.TRINKET_1)
	p.equipment.equip(unique(&"resource", {"trigger": "on_hit", "chance": 100.0, "amount": 1}), Items.EquipSlot.TRINKET_2)
	p.procs.on_hit(e, 1.0, p.main_hand, false)
	p.procs.on_hit(e, 1.0, p.main_hand, false)
	check_eq(RunState.gold, 3, "1.5 gold per proc: fractions carried")
	check_eq(p.procs.fire_count(&"test_resource"), 2, "resource fires")
	check_near(p.abilities.get_resource(&"rage").value, 2 * 0.1 * 100.0, 0.001,
			"Rage (a bar): +10% of the bar per point")


func test_resource_proc_gives_whole_pips() -> void:
	var p := _hero(&"paladin")
	var e := _fake(Vector3(1, 0, 0))
	p.equipment.equip(unique(&"resource", {"trigger": "on_hit", "chance": 100.0, "amount": 1}), Items.EquipSlot.TRINKET_2)
	p.procs.on_hit(e, 1.0, p.main_hand, false)
	check_eq(p.abilities.get_resource(&"holy_power").value, 1.0, "+1 Holy Power")


func test_when_struck_reflect_and_frozen_ward() -> void:
	var p := _hero()
	var e := _real(Vector3(1, 0, 0), 25)
	p.equipment.equip(enchanted(&"retribution", 0, Items.SlotType.CHEST))
	var hp_e := e.hp
	p.take_damage(2.0, CombatMath.KIND_MELEE, e)
	check_near(hp_e - e.hp, 6.0, 0.0001, "6 Holy damage to the attacker")
	p.invulnerable_left = 0.0
	p.take_damage(2.0, CombatMath.KIND_PROJECTILE, e)
	check_near(hp_e - e.hp, 6.0, 0.0001, "0.5 s internal cooldown")
	p.procs._physics_process(0.6)
	p.invulnerable_left = 0.0
	p.take_damage(2.0, CombatMath.KIND_PROJECTILE, e)
	check_near(hp_e - e.hp, 12.0, 0.0001, "projectile hits count as struck too")


func test_shields_keep_their_own_timers() -> void:
	var p := _hero()
	var ps := p.procs
	ps.add_shield(10.0, 3600.0, &"barrier")
	ps.add_shield(5.0, 4.0)
	check_eq(ps.shield_hp, 15.0, "shield_hp is the total")
	check_eq(ps.shield_of(&"barrier"), 10.0, "per source")
	check_eq(ps.shield_of(&""), 5.0, "anonymous shields share one entry")
	ps._physics_process(5.0)
	check_eq(ps.shield_hp, 10.0, "the 4 s shield expired: a long shield does not stretch it")
	ps.add_shield(6.0, 4.0)
	ps.add_shield(1.0, 2.0)
	check_eq(ps.shield_of(&""), 7.0, "same source: one entry (the longer timer wins)")
	check_eq(ps.absorb(8.0), 0.0, "absorbed")
	check_eq(ps.shield_of(&"barrier"), 9.0, "the shield that runs out first soaks first")
	check_eq(ps.shield_of(&""), 0.0, "used up")
	check_eq(ps.absorb(12.0), 3.0, "the rest goes through")
	check_eq(ps.shield_hp, 0.0, "all used up")
	ps.add_shield(4.0, 1.0, &"barrier")
	ps.add_shield(2.0, 1.0)
	ps.shield_hp = 0.0
	check_eq(ps.shield_hp, 0.0, "setting 0 clears every shield")
	check_eq(ps.shield_of(&"barrier"), 0.0, "including the named ones")
	ps.add_shield(4.0, 1.0, &"barrier")
	ps.begin_wave()
	check_eq(ps.shield_hp, 0.0, "wave start clears them")


func test_low_hp_shield_absorbs_and_rearms() -> void:
	var p := _hero()
	p.equipment.equip(unique(&"shield", {"trigger": "low_hp", "threshold": 50.0, "amount": 30.0,
			"duration": 3.0}))
	var max_hp := p.max_hp()
	p.take_damage(max_hp * 0.4)
	check_eq(p.procs.shield_hp, 0.0, "60% HP: nothing yet")
	p.invulnerable_left = 0.0
	p.take_damage(max_hp * 0.2)
	check_eq(p.procs.shield_hp, 30.0, "dropped below 50%: shield")
	var hp := p.hp
	p.invulnerable_left = 0.0
	p.take_damage(20.0)
	check_eq(p.hp, hp, "absorbed")
	check_near(p.procs.shield_hp, 30.0 - CombatMath.incoming_damage(20.0, p.stats), 0.0001, "shield used up")
	p.invulnerable_left = 0.0
	p.take_damage(2.0)
	check_eq(p.procs.fire_count(&"test_shield"), 1, "fires once while below the threshold")
	p.procs._physics_process(3.1)
	check_eq(p.procs.shield_hp, 0.0, "the shield fades")
	p.heal(max_hp)
	p.procs._physics_process(DT)
	p.invulnerable_left = 0.0
	p.take_damage(max_hp * 0.6)
	check_eq(p.procs.fire_count(&"test_shield"), 2, "re-armed after healing above it")


func test_periodic_waits_for_enemies() -> void:
	var p := _hero()
	p.equipment.equip(unique(&"nova", {"trigger": "periodic", "interval": 2.0, "damage": 1.0, "radius": 3.0}))
	p.procs.begin_wave()
	for i in 300:
		p.procs._physics_process(DT)
	check_eq(p.procs.fire_count(&"test_nova"), 0, "nobody around: no nova")
	var e := _fake(Vector3(2, 0, 0))
	for i in 361:  # 6 s
		p.procs._physics_process(DT)
	check_eq(p.procs.fire_count(&"test_nova"), 3, "every 2 s once enemies are near")
	check_eq(e.fake_hits(), 3, "each one hit")


func test_cheat_death_once_per_wave() -> void:
	var p := _hero()
	p.equipment.equip(unique(&"cheat_death", {"trigger": "equip", "invulnerable": 2.0}))
	p.take_damage(100000.0)
	check(not p.downed, "saved")
	check_eq(p.hp, 1.0, "at 1 HP")
	check_near(p.invulnerable_left, 2.0, 0.0001, "2 s invulnerable")
	p.invulnerable_left = 0.0
	p.take_damage(100000.0)
	check(p.downed, "only once per wave")
	p.begin_wave()
	p.invulnerable_left = 0.0
	p.take_damage(100000.0)
	check(not p.downed, "again next wave")


func test_galeforce_enchant_on_projectile_weapon() -> void:
	var m := _hero(&"mage")
	m.equip_weapons(Db.get_weapon(&"wand"), null)
	var ring := enchanted(&"galeforce")
	m.equipment.equip(ring)
	var e := _fake(Vector3(0, 0, -4))
	var proc: ProcSystem.Proc = m.procs.procs[0]
	check_eq(proc.effect, &"extra_attack", "Galeforce is an extra-attack proc")
	m.procs._run(proc, e, e.global_position, m.main_hand)
	var shots := 0
	for node in tree.get_nodes_in_group(&"projectiles"):
		var pr := node as Projectile
		if pr != null and pr.is_extra:
			shots += 1
	check_eq(shots, 2, "two extra bolts")


func test_downed_hero_does_not_proc() -> void:
	var p := _hero()
	p.equipment.equip(unique(&"bolt", {"trigger": "on_hit", "chance": 100.0, "damage": 5.0}))
	var e := _fake(Vector3(2, 0, 0))
	p.downed = true
	p.procs.on_hit(e, 1.0, p.main_hand, false)
	p.notify_kill(e)
	check_eq(e.fake_hits(), 0, "nothing while downed")
