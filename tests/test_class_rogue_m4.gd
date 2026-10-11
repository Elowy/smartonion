extends TestCase
## Rogue M4 abilities (GDD 6.4): Shuriken Toss, Blade Flurry, Poison Bomb, Cheat Death,
## Shadowstep, Killing Spree – data (kind, Rank III, Rank V specialisations, power), behaviour,
## auto-cast / bot rules and clean-up – plus the ranks of the core Fan of Knives and Vanish.

const Fakes := preload("res://tests/player_fakes.gd")
const EFakes := preload("res://tests/enemies_fakes.gd")
const DT := 1.0 / 60.0
const LEARNED: Array[StringName] = [&"shuriken_toss", &"blade_flurry", &"poison_bomb", &"cheat_death",
		&"shadowstep", &"killing_spree"]
const ACTIVES: Array[StringName] = [&"shadowstep", &"killing_spree"]
## Params every ability has through AbilityRunner.params_for.
const RUNNER_PARAMS: Array[String] = ["cooldown", "cost", "charges", "power"]

var world: Node3D
var rogue: Player


func before_each() -> void:
	PlayerManager.clear()
	RunState.start_run(1, 21)
	world = Fakes.make_world(tree)
	rogue = Fakes.spawn_player(world, 0, &"rogue")
	# Deterministic damage: no random crits / dodges unless a test asks for them.
	rogue.stats.set_source(&"test", {Stats.CRIT: -500.0, Stats.DODGE: -500.0})


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	rogue = null
	PlayerManager.clear()
	EnemyGrid.mark_dirty()


# --- Helpers ---------------------------------------------------------------------------------

func _learn(id: StringName) -> int:
	var i := rogue.abilities.learn(Db.get_ability(id))
	check(i >= 0, "%s learned" % id)
	return i


## Learns [param id] and raises it to [param rank] (with Rank V specialisation [param spec]).
func _learn_at(id: StringName, rank: int, spec: int = -1) -> int:
	var i := _learn(id)
	for r in range(1, rank):
		rogue.abilities.rank_up(id)
	if spec >= 0:
		check(rogue.abilities.set_spec(id, spec), "%s spec %d" % [id, spec])
	return i


func _params(id: StringName) -> Dictionary:
	return rogue.abilities.params_for(Db.get_ability(id))


func _effect(id: StringName) -> AbilityEffect:
	return rogue.abilities.effect_for(Db.get_ability(id))


func _enemy(pos: Vector3) -> Fakes.FakeEnemy:
	var e := Fakes.spawn_enemy(world, pos)
	EnemyGrid.mark_dirty()
	return e


func _blades() -> Array[RogueBlade]:
	var out: Array[RogueBlade] = []
	for node in tree.get_nodes_in_group(&"projectiles"):
		var b := node as RogueBlade
		if b != null and b.attacker == rogue and not b.is_queued_for_deletion():
			out.append(b)
	return out


func _advance_blades(seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		for b in _blades():
			b.advance(DT)
		t += DT


func _flasks() -> Array[RoguePoisonFlask]:
	var out: Array[RoguePoisonFlask] = []
	for node in tree.get_nodes_in_group(&"ability_areas"):
		var f := node as RoguePoisonFlask
		if f != null and not f.is_queued_for_deletion():
			out.append(f)
	return out


func _run(seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		rogue.abilities._physics_process(DT)
		rogue._physics_process(DT)
		t += DT


func _hit() -> float:
	return CombatMath.weapon_hit_damage(rogue.main_hand, rogue.stats)


func _total(e: Fakes.FakeEnemy) -> float:
	var sum := 0.0
	for d in e.fake_damage_log:
		sum += d
	return sum


func _check_rank_data(a: AbilityData) -> void:
	check(not a.rank3.is_empty() and a.rank3_text != "", "%s has a Rank III effect and text" % a.id)
	check_eq(a.specs.size(), 2, "%s has two Rank V specialisations" % a.id)
	var mods: Array[Dictionary] = [a.rank3]
	for s in a.specs:
		check(String(s.get("name", "")) != "" and String(s.get("text", "")) != "", "%s spec texts" % a.id)
		var m: Dictionary = s.get("mods", {})
		check(not m.is_empty(), "%s spec %s changes something" % [a.id, s.get("name")])
		mods.append(m)
	# Every key a rank changes is a param the effect reads, and the change really changes it
	# ("<param>_pct" scales, so a percentage param is set through "<param>_add").
	var params := {"cooldown": a.cooldown, "cost": a.cost, "charges": 1, "power": 1.0}
	params.merge(a.params, true)
	for m in mods:
		var after := AbilityRunner.apply_mods(params, m)
		for key: String in m:
			var p := key
			if key.ends_with("_add"):
				p = key.trim_suffix("_add")
			elif key.ends_with("_pct"):
				p = key.trim_suffix("_pct")
			check(a.params.has(p) or p in RUNNER_PARAMS, "%s: rank key %s names a known param" % [a.id, key])
			check(after.get(p) != params.get(p), "%s: rank key %s changes %s" % [a.id, key, p])
	var text := AbilityIcon.format_description(a, params)
	check(text != "" and not "{" in text, "%s description fills every placeholder: %s" % [a.id, text])


# --- Data ------------------------------------------------------------------------------------

func test_learned_abilities_data() -> void:
	var pool := Db.ability_pool(&"rogue")
	var mage_pool := Db.ability_pool(&"mage")
	for id in LEARNED:
		var a := Db.get_ability(id)
		check(a != null, "%s exists" % id)
		if a == null:
			continue
		check_eq(a.class_id, &"rogue", "%s class" % id)
		check_eq(a.kind, AbilityData.Kind.ACTIVE if id in ACTIVES else AbilityData.Kind.AUTO, "%s kind" % id)
		check(a.card_weight > 0.0, "%s offered on cards" % id)
		check(a.resource == &"" and a.cost == 0.0, "%s is free" % id)
		check(a.cooldown >= 4.0 and a.cooldown <= 60.0, "%s cooldown %s" % [id, a.cooldown])
		check_eq(a.icon, id, "%s icon id" % id)
		check(a.display_name != "" and a.description != "", "%s texts" % id)
		check(a.effect != null and a.effect.can_instantiate() and a.effect.new() is AbilityEffect, "%s effect" % id)
		check(a in pool, "%s in the Rogue pool" % id)
		check(not a in mage_pool, "%s not offered to a Mage" % id)
		_check_rank_data(a)


func test_core_abilities_have_ranks_too() -> void:
	for id: StringName in [&"fan_of_knives", &"vanish"]:
		var a := Db.get_ability(id)
		check_eq(a.kind, AbilityData.Kind.CORE, "%s stays a core ability" % id)
		_check_rank_data(a)


func test_learning_puts_them_in_the_right_slots() -> void:
	check_eq(_learn(&"shadowstep"), 2, "Shadowstep -> RB")
	check_eq(_learn(&"killing_spree"), 3, "Killing Spree -> LB")
	check_eq(_learn(&"shuriken_toss"), 4, "auto slots from 4")
	check_eq(_learn(&"blade_flurry"), 5, "")
	check_eq(_learn(&"poison_bomb"), 6, "")
	check_eq(_learn(&"cheat_death"), 7, "")
	for id in LEARNED:
		check(_effect(id) != null, "%s effect instance" % id)


# --- Shuriken Toss ---------------------------------------------------------------------------

func test_shuriken_toss_fans_three_stars_at_the_nearest_enemy() -> void:
	var e := _enemy(Vector3(4, 0, -4))
	var slot := _learn(&"shuriken_toss")
	check(rogue.abilities.try_cast(slot), "cast")
	var stars := _blades()
	check_eq(stars.size(), 3, "three shuriken")
	var aim := WeaponRunner.flat(e.global_position).normalized()
	var angles: Array[float] = []
	for s in stars:
		check_eq(s.look, RogueBlade.Look.SHURIKEN, "shuriken look")
		check(s.weapon == rogue.main_hand and s.is_extra, "weapon hit, no extra-attack chains")
		check(s.proc_gate == stars[0].proc_gate and s.proc_gate != null, "one proc roll per throw")
		check_near(s.damage, _hit(), 0.001, "100% weapon damage")
		check(not s.is_crit, "no crit at 0% crit")
		check_near(s.max_range, 11.0, 0.001, "range")
		angles.append(rad_to_deg(aim.signed_angle_to(s.direction, Vector3.UP)))
	angles.sort()
	check_near(angles[0], -15.0, 0.01, "fan edge")
	check_near(angles[1], 0.0, 0.01, "centre at the target")
	check_near(angles[2], 15.0, 0.01, "fan edge")
	check_near(rogue.abilities.remaining(slot), 4.0, 0.001, "4 s cooldown")
	check(stars[0].get_node("Visual").get_node_or_null("Spinner") != null, "a spinning star model")


func test_shuriken_hits_are_weapon_hits() -> void:
	rogue.stats.set_source(&"test", {Stats.CRIT: 500.0})
	var e := _enemy(Vector3(0, 0, -3))
	var slot := _learn(&"shuriken_toss")
	check(rogue.abilities.try_cast(slot), "cast")
	for s in _blades():
		check(s.is_crit, "crits at 100% crit")
	_advance_blades(0.5)
	check_eq(e.fake_hits(), 1, "the middle star hits (the others fly past)")
	check(e.fake_crit_log[0], "as a crit")
	check_eq(e.fake_attacker_log[0], rogue, "credited to the rogue")
	check_eq(RogueUtil.combo_points(rogue), 1, "a Combo Point")
	check_eq((rogue.abilities.mastery as RogueMastery).stacks_on(e), 1, "and Deadly Poison")


func test_shuriken_auto_casts_only_with_an_enemy_in_range() -> void:
	var slot := _learn(&"shuriken_toss")
	_run(0.3)
	check_eq(_blades().size(), 0, "nothing to throw at")
	_enemy(Vector3(0, 0, -12))
	_run(0.3)
	check_eq(_blades().size(), 0, "12 m is out of range")
	_enemy(Vector3(0, 0, -8))
	_run(0.3)
	check_eq(_blades().size(), 3, "thrown by itself (auto-cast slot, human player)")
	check(rogue.abilities.remaining(slot) > 3.0, "on cooldown")


func test_shuriken_ranks_and_specs() -> void:
	_enemy(Vector3(0, 0, -5))
	var slot := _learn_at(&"shuriken_toss", 2)
	check_near(_params(&"shuriken_toss")["power"], 1.25, 0.001, "Rank II power")
	rogue.abilities.try_cast(slot)
	for s in _blades():
		check_near(s.damage, _hit() * 1.25, 0.001, "+25% damage")
	check_near(rogue.abilities.remaining(slot), 3.6, 0.001, "-10% cooldown")
	rogue.abilities.rank_up(&"shuriken_toss")
	rogue.abilities.set_cooldown(Db.get_ability(&"shuriken_toss"), 0.0)
	for s in _blades():
		s.free()
	rogue.abilities.try_cast(slot)
	check_eq(_blades().size(), 5, "Rank III: +2 shuriken")
	for s in _blades():
		s.free()
	rogue.abilities.rank_up(&"shuriken_toss")
	rogue.abilities.rank_up(&"shuriken_toss")
	check(rogue.abilities.needs_spec(&"shuriken_toss"), "Rank V asks for a spec")
	rogue.abilities.set_spec(&"shuriken_toss", 0)
	rogue.abilities.set_cooldown(Db.get_ability(&"shuriken_toss"), 0.0)
	rogue.abilities.try_cast(slot)
	for s in _blades():
		check_eq(s.pierce, 2, "Razor Stars pierce")
		check_near(s.max_range, 15.0, 0.001, "and fly further")
		s.free()
	rogue.abilities.set_spec(&"shuriken_toss", 1)
	rogue.abilities.set_cooldown(Db.get_ability(&"shuriken_toss"), 0.0)
	rogue.abilities.try_cast(slot)
	check_eq(_blades().size(), 5, "first volley")
	_run(0.1)
	check_eq(_blades().size(), 5, "the second waits a moment")
	_run(0.2)
	check_eq(_blades().size(), 10, "Twin Volley: a second fan")
	_run(0.5)
	check_eq(_blades().size(), 10, "only two")


func test_shuriken_twin_volley_stops_with_the_wave() -> void:
	_enemy(Vector3(0, 0, -5))
	var slot := _learn_at(&"shuriken_toss", 5, 1)
	rogue.abilities.try_cast(slot)
	var n := _blades().size()
	rogue.end_wave()
	_effect(&"shuriken_toss").tick(null, 0.5)
	check_eq(_blades().size(), n, "no second volley after the wave ended")


# --- Blade Flurry ----------------------------------------------------------------------------

func test_blade_flurry_echoes_weapon_hits_on_a_second_enemy() -> void:
	var a := _enemy(Vector3(0, 0, -1.2))
	var b := _enemy(Vector3(1.5, 0, -1.2))
	var far := _enemy(Vector3(0, 0, -9))
	var slot := _learn(&"blade_flurry")
	var flurry := _effect(&"blade_flurry") as RogueBladeFlurry
	check(rogue.abilities.try_cast(slot), "cast")
	check(flurry.is_active(), "active")
	check_near(flurry.time_left(), 5.0, 0.001, "5 s")
	WeaponRunner.apply_hit(rogue, a, 10.0, false, Vector3.ZERO, 0.0, 0.5, rogue.main_hand)
	check_eq(a.fake_hits(), 1, "the target is hit once")
	check_eq(b.fake_hits(), 1, "the neighbour takes an echo")
	check_near(b.fake_damage_log[0], 5.0, 0.001, "50% of the hit")
	check_eq(b.fake_attacker_log[0], rogue, "credited to the rogue")
	check_eq(far.fake_hits(), 0, "nobody out of reach")
	WeaponRunner.apply_hit(rogue, a, 20.0, true, Vector3.ZERO, 0.0, 0.5, rogue.main_hand)
	check_near(b.fake_damage_log[1], 10.0, 0.001, "a crit echoes as a crit's worth")
	check_eq(RogueUtil.combo_points(rogue), 1, "only the real crit gives a Combo Point")
	rogue.damage_mults[&"test"] = 2.0
	WeaponRunner.apply_hit(rogue, a, 10.0, false, Vector3.ZERO, 0.0, 0.5, rogue.main_hand)
	check_near(a.fake_damage_log[-1], 20.0, 0.001, "(the hit itself is doubled)")
	check_near(b.fake_damage_log[-1], 10.0, 0.001, "the outgoing multiplier counts once on the echo")
	rogue.damage_mults.erase(&"test")
	_run(5.05)
	check(not flurry.is_active(), "over after 5 s")
	var n := b.fake_hits()
	WeaponRunner.apply_hit(rogue, a, 10.0, false, Vector3.ZERO, 0.0, 0.5, rogue.main_hand)
	check_eq(b.fake_hits(), n, "no more echoes")


func test_blade_flurry_echoes_thrown_blades_too() -> void:
	var a := _enemy(Vector3(0, 0, -3))
	var b := _enemy(Vector3(1.0, 0, -3))  # between two knives' paths: only echoes reach it
	check(rogue.abilities.try_cast(_learn(&"blade_flurry")), "flurry")
	rogue.facing = Vector3.FORWARD
	check(rogue.abilities.try_cast(0), "Fan of Knives")
	_advance_blades(0.6)
	check_eq(a.fake_hits(), 1, "a knife hit the first enemy")
	check_eq(b.fake_hits(), 1, "the knife hit echoed on the second")
	if b.fake_hits() == 1 and a.fake_hits() == 1:
		check_near(b.fake_damage_log[0], a.fake_damage_log[0] * 0.5, 0.001, "half of the knife's damage")


func test_blade_flurry_auto_cast_needs_two_enemies_close() -> void:
	var slot := _learn(&"blade_flurry")
	_enemy(Vector3(0, 0, -1.5))
	_run(0.3)
	check(not (_effect(&"blade_flurry") as RogueBladeFlurry).is_active(), "one enemy: no flurry")
	_enemy(Vector3(1.0, 0, -1.5))
	_run(0.3)
	check((_effect(&"blade_flurry") as RogueBladeFlurry).is_active(), "two: flurry")
	check(rogue.abilities.remaining(slot) > 10.0, "12 s cooldown running")


func test_blade_flurry_rank_three_hits_one_more_and_power_scales() -> void:
	var a := _enemy(Vector3(0, 0, -1.2))
	var b := _enemy(Vector3(1.5, 0, -1.2))
	var c := _enemy(Vector3(-2.0, 0, -1.2))
	var slot := _learn_at(&"blade_flurry", 3)
	check(rogue.abilities.try_cast(slot), "cast")
	WeaponRunner.apply_hit(rogue, a, 10.0, false, Vector3.ZERO, 0.0, 0.5, rogue.main_hand)
	check_eq(b.fake_hits(), 1, "first extra target")
	check_eq(c.fake_hits(), 1, "Rank III: a second one")
	check_near(c.fake_damage_log[0], 10.0 * 0.5 * 1.25, 0.001, "Rank II power")


func test_blade_flurry_specs() -> void:
	var a := _enemy(Vector3(0, 0, -1.2))
	_enemy(Vector3(1.5, 0, -1.2))
	var slot := _learn_at(&"blade_flurry", 5, 0)
	var flurry := _effect(&"blade_flurry") as RogueBladeFlurry
	check(rogue.abilities.try_cast(slot), "cast")
	rogue.notify_kill(a)
	check_near(flurry.time_left(), 6.0, 0.001, "Relentless Flurry: a kill adds 1 s")
	for i in 8:
		rogue.notify_kill(a)
	check_near(flurry.time_left(), 10.0, 0.001, "up to 5 s in total")
	flurry.end()
	rogue.abilities.set_spec(&"blade_flurry", 1)
	rogue.abilities.set_cooldown(Db.get_ability(&"blade_flurry"), 0.0)
	var haste := rogue.stats.get_stat(Stats.HASTE)
	check(rogue.abilities.try_cast(slot), "cast again")
	check_near(rogue.stats.get_stat(Stats.HASTE) - haste, 30.0 * 1.5, 0.01, "Adrenaline Surge: 30% x power Haste")
	rogue.notify_kill(a)
	check_near(flurry.time_left(), 5.0, 0.001, "no kill extension in this spec")
	_run(5.05)
	check_near(rogue.stats.get_stat(Stats.HASTE), haste, 0.01, "the Haste goes with it")


func test_blade_flurry_cleans_up() -> void:
	var a := _enemy(Vector3(0, 0, -1.2))
	var b := _enemy(Vector3(1.5, 0, -1.2))
	var slot := _learn_at(&"blade_flurry", 5, 1)
	var flurry := _effect(&"blade_flurry") as RogueBladeFlurry
	rogue.abilities.try_cast(slot)
	check(rogue.get_node_or_null("BladeFlurryVfx") != null, "blades circle the rogue")
	rogue.end_wave()
	check(not flurry.is_active(), "ends with the wave")
	check(not rogue.stats.has_source(RogueBladeFlurry.HASTE_SOURCE), "Haste gone")
	check(not rogue.hit_dealt.is_connected(flurry._on_hit_dealt), "listener gone")
	rogue.begin_wave()
	rogue.abilities.try_cast(slot)
	rogue.invulnerable_left = 0.0
	rogue.take_damage(9999.0)
	check(not flurry.is_active(), "ends when the rogue goes down")
	rogue.revive()
	rogue.begin_wave()
	rogue.abilities.try_cast(slot)
	check(flurry.is_active(), "active again")
	rogue.abilities.forget(slot)
	check(not flurry.is_active(), "ends when forgotten")
	check(not rogue.stats.has_source(RogueBladeFlurry.HASTE_SOURCE), "no Haste left behind")
	WeaponRunner.apply_hit(rogue, a, 10.0, false, Vector3.ZERO, 0.0, 0.5, rogue.main_hand)
	check_eq(b.fake_hits(), 0, "no echoes after it was forgotten")


# --- Poison Bomb -----------------------------------------------------------------------------

func _land_bomb() -> AbilityArea:
	var flasks := _flasks()
	check_eq(flasks.size(), 1, "one vial in the air")
	if flasks.is_empty():
		return null
	var flask := flasks[0]
	for i in 40:
		if flask.cloud != null or flask.is_queued_for_deletion():
			break
		flask._physics_process(DT)
	check(flask.cloud != null, "the vial landed")
	return flask.cloud


func test_poison_bomb_lobs_a_vial_that_leaves_a_poison_cloud() -> void:
	var a := _enemy(Vector3(0, 0, -6))
	var b := _enemy(Vector3(0.8, 0, -6.3))
	var c := _enemy(Vector3(-0.6, 0, -5.6))
	var lone := _enemy(Vector3(6, 0, 2))
	var slot := _learn(&"poison_bomb")
	check(rogue.abilities.try_cast(slot), "cast at the group")
	check_near(rogue.abilities.remaining(slot), 9.0, 0.001, "9 s cooldown")
	var flask := _flasks()[0]
	check(flask.is_in_group(&"ability_areas"), "the wave end removes a vial in flight")
	var cloud := _land_bomb()
	if cloud == null:
		return
	check_near(WeaponRunner.flat(cloud.global_position - a.global_position).length(), 0.0, 1.0, "lands on the group")
	check_eq(cloud.school, &"nature", "Nature damage")
	check_near(cloud.radius, 2.5, 0.001, "2.5 m")
	check_near(cloud.duration, 4.0, 0.001, "4 s")
	var tick := RogueUtil.weapon_damage(rogue, &"nature") * 0.25
	check_near(cloud.damage_per_tick, tick, 0.001, "25% weapon damage per tick")
	check(cloud.get_node_or_null("PoisonCloudVfx") != null, "a gas cloud look")
	for i in 241:
		cloud._physics_process(DT)
	for e in [a, b, c]:
		check_eq(e.fake_hits(), 8, "8 ticks in 4 s")
		check_near(_total(e), tick * 8.0, 0.01, "200% weapon damage in total")
	check_eq(lone.fake_hits(), 0, "the enemy far away is untouched")


func test_poison_bomb_auto_cast_wants_a_group_or_a_lone_enemy() -> void:
	var slot := _learn(&"poison_bomb")
	_enemy(Vector3(0, 0, -6))
	_run(0.3)
	check_eq(_flasks().size(), 1, "a lone enemy gets the bomb")
	rogue.abilities.set_cooldown(Db.get_ability(&"poison_bomb"), 0.0)
	for f in _flasks():
		f.free()
	_enemy(Vector3(6, 0, 0))
	_run(0.3)
	check_eq(_flasks().size(), 0, "two enemies far apart: not worth it")
	_enemy(Vector3(5.5, 0, 0.6))
	_run(0.3)
	check_eq(_flasks().size(), 1, "two together: bomb")
	check(rogue.abilities.remaining(slot) > 8.0, "on cooldown")


func test_poison_bomb_ranks_and_specs() -> void:
	var a := _enemy(Vector3(0, 0, -5))
	_enemy(Vector3(0.5, 0, -5))
	var slot := _learn_at(&"poison_bomb", 3)
	rogue.abilities.try_cast(slot)
	var cloud := _land_bomb()
	if cloud == null:
		return
	check_near(cloud.radius, 3.5, 0.001, "Rank III: +1 m")
	check_near(cloud.damage_per_tick, RogueUtil.weapon_damage(rogue, &"nature") * 0.25 * 1.25, 0.001, "Rank II power")
	rogue.abilities.rank_up(&"poison_bomb")
	rogue.abilities.rank_up(&"poison_bomb")
	rogue.abilities.set_spec(&"poison_bomb", 0)
	rogue.abilities.set_cooldown(Db.get_ability(&"poison_bomb"), 0.0)
	rogue.abilities.try_cast(slot)
	cloud = _land_bomb()
	if cloud == null:
		return
	check_near(cloud.slow_pct, 40.0, 0.001, "Crippling Fumes slow")
	cloud._physics_process(DT)
	check(a.is_slowed(), "enemies inside are slowed")
	rogue.abilities.set_spec(&"poison_bomb", 1)
	rogue.abilities.set_cooldown(Db.get_ability(&"poison_bomb"), 0.0)
	var hits := a.fake_hits()
	rogue.abilities.try_cast(slot)
	cloud = _land_bomb()
	if cloud == null:
		return
	check_eq(a.fake_hits(), hits + 1, "Volatile Mixture: an impact burst")
	check_near(a.fake_damage_log[-1], RogueUtil.weapon_damage(rogue, &"nature") * 2.0 * 1.5, 0.01, "200% x power")
	check_near(cloud.duration, 6.0, 0.001, "and a longer cloud")
	check_eq(cloud.slow_pct, 0.0, "no slow in this spec")


func test_poison_bomb_without_an_owner_leaves_nothing() -> void:
	_enemy(Vector3(0, 0, -5))
	var slot := _learn(&"poison_bomb")
	rogue.abilities.try_cast(slot)
	var flask := _flasks()[0]
	rogue.free()
	rogue = null
	for i in 40:
		if flask.is_queued_for_deletion():
			break
		flask._physics_process(DT)
	check(flask.cloud == null, "no cloud for a freed rogue")
	check(flask.is_queued_for_deletion(), "the vial is gone")


# --- Cheat Death -----------------------------------------------------------------------------

func _cheat_death() -> RogueCheatDeath:
	return _effect(&"cheat_death") as RogueCheatDeath


func test_cheat_death_saves_from_a_killing_blow_once_per_minute() -> void:
	var slot := _learn(&"cheat_death")
	var guard := _cheat_death()
	check(not guard.is_registered(), "not before its first tick")
	_run(DT)
	check(guard.is_registered(), "registered while slotted")
	check(guard.is_ready(), "ready")
	rogue.invulnerable_left = 0.0
	rogue.take_damage(9999.0)
	check(not rogue.downed, "survived")
	check_near(rogue.hp, 1.0, 0.001, "at 1 HP")
	check(rogue.invulnerable_left >= 0.99, "1 s invulnerable")
	check_eq(guard.saves, 1, "one save")
	check_near(rogue.abilities.remaining(slot), 60.0, 0.001, "60 s cooldown on the slot")
	var state := rogue.abilities.slot_state(slot)
	check_near(state["left"], 60.0, 0.001, "the HUD sees the cooldown")
	check_near(state["ratio"], 1.0, 0.001, "full sweep")
	check(not guard.is_ready(), "spent")
	_run(DT)
	check_near(rogue.hp, 1.0 + rogue.max_hp() * 0.15, 0.001, "heals 15% of max HP on the next tick")
	rogue.invulnerable_left = 0.0
	rogue.take_damage(9999.0)
	check(rogue.downed, "the next killing blow within a minute counts")
	rogue.revive()
	_run(60.0)
	check(guard.is_ready(), "ready again after 60 s")
	rogue.invulnerable_left = 0.0
	rogue.take_damage(9999.0)
	check(not rogue.downed, "saves again")


func test_cheat_death_is_never_cast() -> void:
	var slot := _learn(&"cheat_death")
	_enemy(Vector3(0, 0, -1.0))
	_run(1.0)
	check_eq(rogue.abilities.remaining(slot), 0.0, "the runner never fires it")
	check(not rogue.abilities.try_cast(slot), "and it cannot be cast by hand")
	rogue.take_damage(1.0)
	check_eq(_cheat_death().saves, 0, "a hit that does not kill does nothing")


func test_cheat_death_guard_follows_the_slot_and_the_waves() -> void:
	var slot := _learn(&"cheat_death")
	var guard := _cheat_death()
	_run(DT)
	check_eq(rogue.death_guards.size(), 1, "one guard")
	_run(1.0)
	check_eq(rogue.death_guards.size(), 1, "never added twice")
	rogue.end_wave()
	check_eq(rogue.death_guards.size(), 0, "dropped at the wave end")
	rogue.begin_wave()
	check_eq(rogue.death_guards.size(), 1, "back at the wave start")
	rogue.abilities.forget(slot)
	check_eq(rogue.death_guards.size(), 0, "removed when forgotten")
	check(not guard.is_registered(), "")
	rogue.invulnerable_left = 0.0
	rogue.take_damage(9999.0)
	check(rogue.downed, "a forgotten Cheat Death saves nobody")


func test_cheat_death_ranks_and_specs() -> void:
	var slot := _learn_at(&"cheat_death", 3)
	_run(DT)
	rogue.invulnerable_left = 0.0
	rogue.take_damage(9999.0)
	check(rogue.invulnerable_left >= 1.99, "Rank III: 2 s invulnerability")
	_run(DT)
	check_near(rogue.hp, 1.0 + rogue.max_hp() * 0.15 * 1.25, 0.01, "Rank II power on the heal")
	check_near(rogue.abilities.remaining(slot), 54.0 - DT, 0.01, "-10% cooldown")
	rogue.abilities.rank_up(&"cheat_death")
	rogue.abilities.rank_up(&"cheat_death")
	rogue.abilities.set_spec(&"cheat_death", 0)
	rogue.begin_wave()
	rogue.invulnerable_left = 0.0
	rogue.take_damage(9999.0)
	check(not rogue.downed, "saved")
	check(rogue.is_stealthed() and rogue.stealth_left >= 2.99, "Shadow Escape: 3 s stealth")
	check(RogueVanish.of(rogue).is_active(), "shown as the Vanish silhouette")
	check_eq(rogue.forced_crits, 1, "and a guaranteed crit")
	rogue.abilities.set_spec(&"cheat_death", 1)
	rogue.begin_wave()
	var near := _enemy(Vector3(0, 0, -2.5))
	var far := _enemy(Vector3(0, 0, -7))
	rogue.invulnerable_left = 0.0
	rogue.take_damage(9999.0)
	check_eq(near.fake_hits(), 0, "the burst waits for the next tick")
	_run(DT)
	check_eq(near.fake_hits(), 1, "Death's Reprisal hits the enemies around")
	check_near(near.fake_damage_log[0], RogueUtil.weapon_damage(rogue) * 3.0 * 1.5, 0.01, "300% x power")
	check_eq(near.fake_stun_count, 1, "and stuns them")
	check_eq(far.fake_hits(), 0, "4 m reach")
	check(not rogue.is_stealthed(), "no stealth in this spec")


# --- Shadowstep ------------------------------------------------------------------------------

func test_shadowstep_lands_behind_the_target_and_the_next_hit_crits() -> void:
	var e := _enemy(Vector3(0, 0, -5))
	rogue.facing = Vector3.FORWARD
	var slot := _learn(&"shadowstep")
	check_eq(slot, 2, "RB")
	check(rogue.abilities.try_cast(slot), "cast")
	var behind := -5.0 - (e.radius + Player.RADIUS + RogueUtil.TELEPORT_GAP)
	check_near(rogue.global_position.x, 0.0, 0.001, "on the line")
	check_near(rogue.global_position.z, behind, 0.001, "just behind the enemy")
	check(rogue.facing.dot(Vector3.BACK) > 0.99, "facing the enemy")
	check_eq(rogue.forced_crits, 1, "a guaranteed crit")
	check_near(rogue.damage_mults.get(RogueShadowstep.BUFF_KEY, 1.0), 1.15, 0.001, "+15% damage")
	check(rogue.invulnerable_left >= 0.29, "short invulnerability on arrival")
	check_near(rogue.abilities.remaining(slot), 10.0, 0.001, "10 s cooldown")
	rogue.runner_for(rogue.main_hand).attack(e)
	check(e.fake_crit_log[-1], "the next hit crits")
	_run(3.05)
	check(not rogue.damage_mults.has(RogueShadowstep.BUFF_KEY), "the damage buff lasts 3 s")


func test_shadowstep_prefers_the_enemy_ahead() -> void:
	var ahead := _enemy(Vector3(0, 0, -7))
	var side := _enemy(Vector3(3, 0, 0))
	var slot := _learn(&"shadowstep")
	rogue.facing = Vector3.FORWARD
	check(rogue.abilities.try_cast(slot), "cast")
	check(rogue.global_position.z < ahead.global_position.z, "went past the enemy ahead, not the closer one")
	rogue.global_position = Vector3.ZERO
	rogue.facing = Vector3.RIGHT
	rogue.abilities.set_cooldown(Db.get_ability(&"shadowstep"), 0.0)
	check(rogue.abilities.try_cast(slot), "cast again")
	check(rogue.global_position.x > side.global_position.x, "now the one to the right")
	rogue.global_position = Vector3.ZERO
	rogue.facing = Vector3.BACK
	rogue.abilities.set_cooldown(Db.get_ability(&"shadowstep"), 0.0)
	check(rogue.abilities.try_cast(slot), "nobody behind: the nearest one")
	check(rogue.global_position.x > side.global_position.x, "the nearest")


func test_shadowstep_needs_a_target_in_range() -> void:
	_enemy(Vector3(0, 0, -12))
	var slot := _learn(&"shadowstep")
	check(not rogue.abilities.try_cast(slot), "12 m is too far")
	check_eq(rogue.abilities.remaining(slot), 0.0, "nothing spent")
	check_eq(rogue.global_position, Vector3.ZERO, "no move")
	check_eq(rogue.forced_crits, 0, "no crit")


func test_shadowstep_stays_in_the_arena() -> void:
	var arena := EFakes.TestArena.new()
	world.add_child(arena)
	var edge := arena.get_bounds().end.x
	rogue.global_position = Vector3(edge - 5.0, 0, 0)
	_enemy(Vector3(edge - 0.6, 0, 0))
	rogue.facing = Vector3.RIGHT
	check(rogue.abilities.try_cast(_learn(&"shadowstep")), "cast")
	check(rogue.global_position.x <= edge - Player.RADIUS - Player.WALL_GAP + 0.001, "clamped to the wall")
	check(arena.is_inside(rogue.global_position), "inside")
	arena.free()


func test_shadowstep_ranks_and_specs() -> void:
	var e := _enemy(Vector3(0, 0, -5))
	rogue.facing = Vector3.FORWARD
	var slot := _learn_at(&"shadowstep", 3)
	check(rogue.abilities.try_cast(slot), "cast")
	check_eq(rogue.forced_crits, 2, "Rank III: two guaranteed crits")
	check_near(rogue.damage_mults[RogueShadowstep.BUFF_KEY], 1.0 + 0.15 * 1.25, 0.001, "Rank II power")
	rogue.begin_wave()
	rogue.abilities.rank_up(&"shadowstep")
	rogue.abilities.rank_up(&"shadowstep")
	rogue.abilities.set_spec(&"shadowstep", 0)
	rogue.global_position = Vector3.ZERO
	rogue.facing = Vector3.FORWARD
	check(rogue.abilities.try_cast(slot), "Ambush")
	check_eq(e.fake_hits(), 1, "a strike on arrival")
	check(e.fake_crit_log[0], "using the guaranteed crit")
	var crit := CombatMath.crit_multiplier(rogue.main_hand, rogue.stats)
	check_near(e.fake_damage_log[0], _hit() * 2.5 * 1.5 * crit * rogue.damage_mults[RogueShadowstep.BUFF_KEY], 0.01,
			"250% x power, critical, with the step's own damage buff")
	check_eq(e.fake_stun_count, 1, "stunned")
	check_eq(rogue.forced_crits, 1, "one guaranteed crit left for the weapons")
	rogue.begin_wave()
	rogue.abilities.set_spec(&"shadowstep", 1)
	check_eq(rogue.abilities.charges_max(Db.get_ability(&"shadowstep")), 2, "Twin Shadows: two charges")
	rogue.global_position = Vector3.ZERO
	check(rogue.abilities.try_cast(slot), "first step")
	check(rogue.abilities.try_cast(slot), "second step at once")
	check(not rogue.abilities.try_cast(slot), "then the cooldown")


func test_shadowstep_bot_rule() -> void:
	var e := _enemy(Vector3(0, 0, -1.5))
	var slot := _learn(&"shadowstep")
	var effect := _effect(&"shadowstep")
	var ctx := rogue.abilities.build_context(rogue.abilities.slots[slot])
	check(not effect.wants_auto_cast(ctx), "an enemy right next to it: no need")
	e.global_position = Vector3(0, 0, -6)
	EnemyGrid.mark_dirty()
	ctx = rogue.abilities.build_context(rogue.abilities.slots[slot])
	check(effect.wants_auto_cast(ctx), "a gap to close")
	rogue.hp = rogue.max_hp() * 0.3
	check(not effect.wants_auto_cast(ctx), "not when badly hurt")
	rogue.hp = rogue.max_hp()
	for i in 5:
		_enemy(Vector3(0.4 * float(i) - 0.8, 0, -7))
	ctx = rogue.abilities.build_context(rogue.abilities.slots[slot])
	check(not effect.wants_auto_cast(ctx), "not into a crowd")


func test_shadowstep_buff_ends_with_the_wave_and_a_down() -> void:
	_enemy(Vector3(0, 0, -5))
	var slot := _learn(&"shadowstep")
	rogue.abilities.try_cast(slot)
	rogue.end_wave()
	check(not rogue.damage_mults.has(RogueShadowstep.BUFF_KEY), "gone at the wave end")
	rogue.begin_wave()
	rogue.global_position = Vector3.ZERO
	rogue.abilities.try_cast(slot)
	rogue.invulnerable_left = 0.0
	rogue.take_damage(9999.0)
	check(not rogue.damage_mults.has(RogueShadowstep.BUFF_KEY), "gone when downed")


# --- Killing Spree ---------------------------------------------------------------------------

func _spree() -> RogueKillingSpree:
	return _effect(&"killing_spree") as RogueKillingSpree


func test_killing_spree_jumps_between_enemies() -> void:
	var enemies: Array[Fakes.FakeEnemy] = [_enemy(Vector3(0, 0, -3)), _enemy(Vector3(4, 0, -1)),
			_enemy(Vector3(-3, 0, 2)), _enemy(Vector3(2, 0, 4))]
	var slot := _learn(&"killing_spree")
	var spree := _spree()
	check(rogue.abilities.try_cast(slot), "cast")
	check_eq(spree.strikes, 1, "the first strike lands at once")
	check(spree.is_active(), "active")
	check_near(rogue.damage_taken_mults.get(RogueKillingSpree.DR_KEY, 1.0), 0.5, 0.001, "50% less damage taken")
	var hp := rogue.hp
	rogue.invulnerable_left = 0.0
	rogue.take_damage(4.0)
	check(hp - rogue.hp < 4.0 * 0.6, "the damage reduction works")
	_run(2.0)
	check(not spree.is_active(), "over after 2 s")
	check_eq(spree.strikes, 8, "a strike every 0.25 s")
	var expected := _hit() * 1.5
	for e in enemies:
		check_eq(e.fake_hits(), 2, "every enemy struck twice (four enemies, eight strikes)")
		check_near(e.fake_damage_log[0], expected, 0.001, "150% weapon damage")
	check(not rogue.damage_taken_mults.has(RogueKillingSpree.DR_KEY), "the reduction ends with it")
	check_near(rogue.abilities.remaining(slot), 18.0 - 2.0, 0.05, "18 s cooldown")


func test_killing_spree_strikes_are_weapon_hits_and_move_the_rogue() -> void:
	rogue.stats.set_source(&"test", {Stats.CRIT: 500.0})
	var e := _enemy(Vector3(5, 0, 0))
	check(rogue.abilities.try_cast(_learn(&"killing_spree")), "cast")
	check_near(rogue.global_position.x, 5.0 + e.radius + Player.RADIUS + RogueUtil.TELEPORT_GAP, 0.001, "behind it")
	check(e.fake_crit_log[0], "crits roll like weapon hits")
	check_eq(RogueUtil.combo_points(rogue), 1, "a Combo Point")
	_run(2.0)
	check_eq(_spree().strikes, 8, "eight strikes")
	var strikes := 0
	for crit in e.fake_crit_log:
		if crit:
			strikes += 1
	check_eq(strikes, 8, "a lone enemy takes every strike (the rest are Deadly Poison ticks)")


func test_killing_spree_needs_an_enemy_and_ends_when_they_are_gone() -> void:
	var slot := _learn(&"killing_spree")
	check(not rogue.abilities.try_cast(slot), "nobody in reach: refused")
	check_eq(rogue.abilities.remaining(slot), 0.0, "nothing spent")
	var e := _enemy(Vector3(0, 0, -4))
	check(rogue.abilities.try_cast(slot), "cast")
	e.fake_dead = true
	EnemyGrid.mark_dirty()
	_run(0.3)
	check(not _spree().is_active(), "ends when nobody is left")
	check(not rogue.damage_taken_mults.has(RogueKillingSpree.DR_KEY), "and cleans up")


func test_killing_spree_ranks_and_specs() -> void:
	var a := _enemy(Vector3(0, 0, -4))
	var b := _enemy(Vector3(1.2, 0, -4))
	var slot := _learn_at(&"killing_spree", 3)
	check(rogue.abilities.try_cast(slot), "cast")
	_run(3.0)
	check_eq(_spree().strikes, 12, "Rank III: +1 s = 12 strikes")
	check_near(a.fake_damage_log[0], _hit() * 1.5 * 1.25, 0.001, "Rank II power")
	rogue.begin_wave()
	rogue.abilities.rank_up(&"killing_spree")
	rogue.abilities.rank_up(&"killing_spree")
	rogue.abilities.set_spec(&"killing_spree", 0)
	var na := a.fake_hits()
	var nb := b.fake_hits()
	check(rogue.abilities.try_cast(slot), "Blade Whirl")
	check_eq(a.fake_hits() + b.fake_hits(), na + nb + 2, "the first strike also hits the neighbour")
	rogue.begin_wave()
	rogue.abilities.set_spec(&"killing_spree", 1)
	check(rogue.abilities.try_cast(slot), "Untouchable")
	var hp := rogue.hp
	for i in 10:
		rogue.abilities._physics_process(DT)
		rogue.take_damage(5.0)
	check_eq(rogue.hp, hp, "cannot be hurt during the spree")
	_run(3.0)
	check(not _spree().is_active(), "over")
	check(rogue.is_stealthed(), "ends in stealth")
	check(RogueVanish.of(rogue).is_active(), "with the Vanish silhouette")


func test_killing_spree_bot_rule_and_clean_up() -> void:
	var slot := _learn(&"killing_spree")
	var effect := _spree()
	_enemy(Vector3(0, 0, -3))
	_enemy(Vector3(2, 0, -3))
	var ctx := rogue.abilities.build_context(rogue.abilities.slots[slot])
	check(not effect.wants_auto_cast(ctx), "two enemies: keep it")
	_enemy(Vector3(-2, 0, -3))
	ctx = rogue.abilities.build_context(rogue.abilities.slots[slot])
	check(effect.wants_auto_cast(ctx), "three: go")
	rogue.abilities.try_cast(slot)
	rogue.end_wave()
	check(not effect.is_active(), "ends with the wave")
	check(not rogue.damage_taken_mults.has(RogueKillingSpree.DR_KEY), "no reduction in the market")
	rogue.begin_wave()
	rogue.abilities.try_cast(slot)
	rogue.invulnerable_left = 0.0
	rogue.damage_taken_mults.clear()
	rogue.take_damage(9999.0)
	check(not effect.is_active(), "ends when downed")


# --- Core abilities: ranks ---------------------------------------------------------------------

func test_fan_of_knives_ranks() -> void:
	rogue.abilities.rank_up(&"fan_of_knives")
	check(rogue.abilities.try_cast(0), "cast")
	var knives := _blades()
	check_eq(knives.size(), 10, "ten knives at Rank II")
	check_near(knives[0].damage, _hit() * 1.1 * 1.25, 0.001, "+25% damage")
	for k in knives:
		k.free()
	rogue.abilities.rank_up(&"fan_of_knives")
	rogue.abilities.get_resource(&"energy").set_value(100.0)
	rogue.abilities.try_cast(0)
	check_eq(_blades().size(), 12, "Rank III: +2 knives")


func test_fan_of_knives_deadly_fan_poisons_every_hit() -> void:
	var e := _enemy(Vector3(0, 0, -3))
	rogue.facing = Vector3.FORWARD
	for i in 4:
		rogue.abilities.rank_up(&"fan_of_knives")
	rogue.abilities.set_spec(&"fan_of_knives", 0)
	check(rogue.abilities.try_cast(0), "cast")
	_advance_blades(0.5)
	check_eq(e.fake_hits(), 1, "one knife hit")
	check(not e.fake_crit_log[0], "not a crit")
	check_eq((rogue.abilities.mastery as RogueMastery).stacks_on(e), 1, "poisoned anyway")


func test_fan_of_knives_returning_blades_hit_twice() -> void:
	var e := _enemy(Vector3(0, 0, -3))
	rogue.facing = Vector3.FORWARD
	for i in 4:
		rogue.abilities.rank_up(&"fan_of_knives")
	rogue.abilities.set_spec(&"fan_of_knives", 1)
	check(rogue.abilities.try_cast(0), "cast")
	_advance_blades(0.5)
	check_eq(e.fake_hits(), 1, "hit on the way out")
	var turned := 0
	for k in _blades():
		turned += k.turned
	check_eq(turned, 12, "every knife turned at the end of its range")
	_advance_blades(0.5)
	check_eq(e.fake_hits(), 2, "and again on the way back")
	_advance_blades(0.2)
	check_eq(_blades().size(), 0, "then they are gone")


func test_vanish_ranks_and_specs() -> void:
	var effect := rogue.abilities.effect_for(rogue.abilities.slots[1]) as RogueVanish
	for i in 2:
		rogue.abilities.rank_up(&"vanish")
	rogue.hp = rogue.max_hp() * 0.1
	check(rogue.abilities.try_cast(1), "cast")
	check_near(rogue.hp, rogue.max_hp() * (0.1 + 0.3 * 1.25), 0.001, "Rank II power on the heal")
	check_near(effect.time_left(), 3.0, 0.001, "Rank III: 3 s")
	rogue.begin_wave()
	rogue.abilities.rank_up(&"vanish")
	rogue.abilities.rank_up(&"vanish")
	rogue.abilities.set_spec(&"vanish", 0)
	var near := _enemy(Vector3(0, 0, -3))
	var far := _enemy(Vector3(0, 0, -6))
	check(rogue.abilities.try_cast(1), "Smoke Bomb")
	check_eq(near.fake_stun_count, 1, "stuns the enemies around")
	check_eq(far.fake_stun_count, 0, "within 4 m")
	check_eq(rogue.invulnerable_left, 0.0, "no invulnerability in this spec")
	rogue.begin_wave()
	rogue.abilities.set_spec(&"vanish", 1)
	var speed := rogue.stats.move_speed()
	check(rogue.abilities.try_cast(1), "Shadow Veil")
	check_near(rogue.invulnerable_left, 3.0, 0.001, "cannot be hurt while hidden")
	check_near(rogue.stats.move_speed(), speed * (1.0 + 0.3 * 1.5), 0.01, "30% x power faster")
	_run(3.05)
	check(not effect.is_active(), "over")
	check_near(rogue.stats.move_speed(), speed, 0.001, "normal speed again")
	rogue.abilities.set_cooldown(rogue.abilities.slots[1], 0.0)
	check(rogue.abilities.try_cast(1), "again")
	check(rogue.stats.move_speed() > speed, "fast")
	rogue.end_wave()
	check_near(rogue.stats.move_speed(), speed, 0.001, "no speed carried into the market")
