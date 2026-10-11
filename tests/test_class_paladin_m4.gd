extends TestCase
## Paladin M4 kit (GDD 6.4): the six learned abilities – Hammer of Justice, Avenger's Shield,
## Divine Storm, Blessing of Kings (Auto), Divine Shield, Lay on Hands (Active) – with their
## Rank II / IV power, Rank III extra and Rank V specialisations, auto-cast / bot rules and
## cleanup; and the ranks of the core abilities (Consecration, Word of Glory).

const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0
const LEARNED: Array[StringName] = [
	&"hammer_of_justice", &"avengers_shield", &"divine_storm", &"blessing_of_kings",
	&"divine_shield", &"lay_on_hands",
]
## Main-hand mace hit at 0 stats: 7 base damage x 0.9 (Paladin -10% damage).
const MACE_HIT := 7.0 * 0.9


## An enemy that really dies at 0 HP (Fakes.FakeEnemy only dies when told to).
class MortalEnemy extends Fakes.FakeEnemy:
	func take_damage(amount: float, is_crit: bool = false, attacker: Node3D = null,
			knockback: Vector3 = Vector3.ZERO) -> void:
		super.take_damage(amount, is_crit, attacker, knockback)
		if hp <= 0.0:
			fake_dead = true


var world: Node3D


func before_each() -> void:
	RunState.start_run(1, 4321)
	world = Fakes.make_world(tree)
	EnemyGrid.mark_dirty()


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	EnemyGrid.mark_dirty()


func _paladin(pos: Vector3 = Vector3.ZERO, index: int = 0) -> Player:
	return Fakes.spawn_player(world, index, &"paladin", pos)


func _ally(index: int, pos: Vector3, class_id: StringName = &"warrior") -> Player:
	return Fakes.spawn_player(world, index, class_id, pos)


func _enemy(pos: Vector3) -> Fakes.FakeEnemy:
	var e := Fakes.spawn_enemy(world, pos)
	EnemyGrid.mark_dirty()
	return e


func _mortal(pos: Vector3, hp: float) -> MortalEnemy:
	var e := MortalEnemy.new()
	e.hp = hp
	e.max_hp = 100.0
	e.add_to_group(&"enemies")
	world.add_child(e)
	e.global_position = pos
	EnemyGrid.mark_dirty()
	return e


## Learns [param id] and brings it to [param rank] (Rank V: specialisation [param spec]).
func _learn(p: Player, id: StringName, rank: int = 1, spec: int = -1) -> int:
	var slot := p.abilities.learn(Db.get_ability(id))
	check(slot >= 0, "learned %s" % id)
	_rank(p, id, rank, spec)
	return slot


func _rank(p: Player, id: StringName, rank: int, spec: int = -1) -> void:
	while p.abilities.rank_of(id) < rank:
		check(p.abilities.rank_up(id), "rank up %s" % id)
	if spec >= 0:
		check(p.abilities.set_spec(id, spec), "spec %d of %s" % [spec, id])


func _effect(p: Player, id: StringName) -> AbilityEffect:
	return p.abilities.effect_for(Db.get_ability(id))


func _ctx(p: Player, id: StringName) -> AbilityContext:
	return p.abilities.build_context(Db.get_ability(id))


func _missiles() -> Array[PaladinHolyMissile]:
	var out: Array[PaladinHolyMissile] = []
	for node in tree.get_nodes_in_group(&"projectiles"):
		var m := node as PaladinHolyMissile
		if m != null and not m.is_queued_for_deletion() and not m.is_done():
			out.append(m)
	return out


func _fly(seconds: float = 1.5) -> void:
	var t := 0.0
	while t < seconds:
		for m in _missiles():
			m._physics_process(DT)
		t += DT


## Runs the hero's abilities (and its own frame: invulnerability, regen) for [param seconds].
func _run(p: Player, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		p._physics_process(DT)
		p.abilities._physics_process(DT)
		t += DT


func _vfx(parent: Node, prefix: String) -> Array[PaladinVfx]:
	var out: Array[PaladinVfx] = []
	for child in parent.get_children():
		var fx := child as PaladinVfx
		if fx != null and fx.name.begins_with(prefix) and not fx.is_queued_for_deletion():
			out.append(fx)
	return out


## A Vfx node is "ending" when it will be gone within a short fade.
func _ending(fx: PaladinVfx) -> bool:
	return fx.life - fx.age <= PaladinVfx.FADE_OUT + 0.0001


func _down(p: Player) -> void:
	p.invulnerable_left = 0.0
	p.hp = 1.0
	p.take_damage(1000.0)


# --- Data -------------------------------------------------------------------------------------

func test_learned_ability_data() -> void:
	var pool := Db.ability_pool(&"paladin")
	var expected_kinds := {
		&"hammer_of_justice": AbilityData.Kind.AUTO, &"avengers_shield": AbilityData.Kind.AUTO,
		&"divine_storm": AbilityData.Kind.AUTO, &"blessing_of_kings": AbilityData.Kind.AUTO,
		&"divine_shield": AbilityData.Kind.ACTIVE, &"lay_on_hands": AbilityData.Kind.ACTIVE,
	}
	var scripts := {
		&"hammer_of_justice": PaladinHammerOfJustice, &"avengers_shield": PaladinAvengersShield,
		&"divine_storm": PaladinDivineStorm, &"blessing_of_kings": PaladinBlessingOfKings,
		&"divine_shield": PaladinDivineShield, &"lay_on_hands": PaladinLayOnHands,
	}
	for id in LEARNED:
		var a := Db.get_ability(id)
		check(a != null, "%s loaded" % id)
		if a == null:
			continue
		check(a in pool, "%s in the Paladin pool" % id)
		check_eq(a.class_id, &"paladin", "%s class" % id)
		check_eq(a.kind, expected_kinds[id], "%s kind" % id)
		check_eq(a.school, &"holy", "%s holy" % id)
		check_eq(a.icon, id, "%s icon id" % id)
		check_eq(a.resource, &"", "%s is free" % id)
		check(a.cooldown >= 4.0 and a.cooldown <= 60.0, "%s cooldown %s" % [id, a.cooldown])
		check(a.card_weight > 0.0, "%s offered on cards" % id)
		check(a.effect != null and a.effect.new() is AbilityEffect, "%s effect" % id)
		check(a.effect == scripts[id], "%s effect script" % id)
		_check_rank_data(a)
	check(Db.get_ability(&"divine_shield").cooldown >= 30.0, "Divine Shield: long cooldown")
	check(Db.get_ability(&"lay_on_hands").cooldown >= 45.0, "Lay on Hands: long cooldown")


func test_core_abilities_have_ranks() -> void:
	for id: StringName in [&"consecration", &"word_of_glory"]:
		var a := Db.get_ability(id)
		check_eq(a.kind, AbilityData.Kind.CORE, "%s is core" % id)
		_check_rank_data(a)


## rank3 + text, two specs with name / text / mods; every mod key is a param the effect reads
## (an "_add" key needs its base param); the description's placeholders all resolve.
func _check_rank_data(a: AbilityData) -> void:
	check(not a.rank3.is_empty(), "%s rank3" % a.id)
	check(a.rank3_text != "", "%s rank3_text" % a.id)
	check_eq(a.specs.size(), 2, "%s: two specs" % a.id)
	var all_mods: Array[Dictionary] = [a.rank3]
	for s in a.specs:
		check(String(s.get("name", "")) != "" and String(s.get("text", "")) != "", "%s spec name / text" % a.id)
		check(s.get("mods") is Dictionary and not (s.get("mods") as Dictionary).is_empty(), "%s spec mods" % a.id)
		all_mods.append(s.get("mods", {}))
	for mods in all_mods:
		for key: String in mods:
			var param := key.trim_suffix("_add").trim_suffix("_pct")
			check(a.params.has(param), "%s: mod key %s has a param" % [a.id, key])
	var text := AbilityIcon.format_description(a, a.params)
	check(not text.contains("{"), "%s description resolves: %s" % [a.id, text])
	# Rank V with either spec builds params without errors.
	for i in a.specs.size():
		var mods := AbilityRanks.mods_for(a, AbilityRanks.MAX_RANK, i)
		check_eq(float(mods.get("power_pct", 0.0)), 50.0, "%s Rank V power" % a.id)


## Every Rank III / Rank V mod really changes the param it is meant for
## (AbilityRunner.params_at_rank: "_add" adds, "_pct" scales an existing param, others set).
func test_rank_mods_change_their_params() -> void:
	var p := _paladin()
	var r := p.abilities
	var ids: Array[StringName] = LEARNED.duplicate()
	ids.append_array([&"consecration", &"word_of_glory"] as Array[StringName])
	for id in ids:
		var a := Db.get_ability(id)
		var r1 := r.params_at_rank(a, 1)
		var r2 := r.params_at_rank(a, 2)
		var r4 := r.params_at_rank(a, 4)
		check_near(float(r1["power"]), 1.0, 0.0001, "%s Rank I power" % id)
		check_near(float(r2["power"]), 1.25, 0.0001, "%s Rank II power" % id)
		check_near(float(r4["power"]), 1.5, 0.0001, "%s Rank IV power" % id)
		check_near(float(r2["cooldown"]), a.cooldown * 0.9, 0.0001, "%s Rank II cooldown" % id)
		var r3 := r.params_at_rank(a, 3)
		for key: String in a.rank3:
			_check_mod_applied(id, "Rank III", key, a.rank3[key], r2, r3)
		for i in a.specs.size():
			var r5 := r.params_at_rank(a, 5, i)
			var mods: Dictionary = a.specs[i]["mods"]
			for key: String in mods:
				_check_mod_applied(id, "spec %d" % i, key, mods[key], r4, r5)


func _check_mod_applied(id: StringName, what: String, key: String, v: Variant, before: Dictionary,
		after: Dictionary) -> void:
	var label := "%s %s %s" % [id, what, key]
	if key.ends_with("_add"):
		var param := key.trim_suffix("_add")
		check(before.has(param), "%s: base param" % label)
		check_near(float(after.get(param, 0.0)) - float(before.get(param, 0.0)), float(v), 0.0001, label)
	elif key.ends_with("_pct") and before.has(key.trim_suffix("_pct")):
		var param := key.trim_suffix("_pct")
		check_near(float(after[param]), float(before[param]) * (1.0 + float(v) / 100.0), 0.0001, label)
	else:
		check(before.has(key), "%s: base param" % label)
		if typeof(v) in [TYPE_INT, TYPE_FLOAT]:
			check_near(float(after.get(key, 0.0)), float(v), 0.0001, label)
		else:
			check_eq(after.get(key), v, label)
		check(str(after.get(key)) != str(before.get(key)), "%s: changes the param" % label)


func test_learn_slots() -> void:
	var p := _paladin()
	check_eq(p.abilities.learn(Db.get_ability(&"hammer_of_justice")), 4, "Auto -> slot 4")
	check_eq(p.abilities.learn(Db.get_ability(&"divine_shield")), 2, "Active -> RB")
	check_eq(p.abilities.learn(Db.get_ability(&"lay_on_hands")), 3, "Active -> LB")
	check_eq(p.abilities.learn(Db.get_ability(&"blessing_of_kings")), 5, "Auto -> slot 5")


# --- Hammer of Justice ------------------------------------------------------------------------

func test_hammer_damages_and_stuns() -> void:
	var p := _paladin()
	var slot := _learn(p, &"hammer_of_justice")
	var e := _enemy(Vector3(0, 0, -5.0))
	check(p.abilities.try_cast(slot), "cast")
	check_near(p.abilities.remaining(slot), 8.0, 0.001, "8 s cooldown")
	var ms := _missiles()
	check_eq(ms.size(), 1, "one hammer")
	if ms.is_empty():
		return
	check(ms[0].get_node_or_null("Visual") != null, "hammer look")
	_fly()
	check_eq(e.fake_hits(), 1, "hit once")
	check_eq(e.fake_stun_count, 1, "stunned")
	check_near(ms[0].stun, 1.5, 0.001, "1.5 s stun")
	if e.fake_hits() > 0:
		check_near(e.fake_damage_log[0], MACE_HIT * 1.5, 0.001, "150% weapon damage as Holy")
	check(ms[0].is_done(), "hammer gone after its target")


func test_hammer_scales_with_spell_power_and_holy() -> void:
	var p := _paladin()
	_learn(p, &"hammer_of_justice")
	var ctx := _ctx(p, &"hammer_of_justice")
	check_near(PaladinHammerOfJustice.hammer_damage(ctx), MACE_HIT * 1.5, 0.001, "base")
	p.stats.set_source(&"test", {Stats.SPELL_POWER: 4.0, Stats.HOLY_DAMAGE: 20.0, Stats.STRENGTH: 5.0})
	# (7 + 5 Str x 0.8) x 1.5 + 4 SP, x (0.9 + 0.2)
	check_near(PaladinHammerOfJustice.hammer_damage(_ctx(p, &"hammer_of_justice")),
			((7.0 + 4.0) * 1.5 + 4.0) * 1.1, 0.001, "Strength, Spell Power and Holy %")


func test_hammer_prefers_targets_that_are_not_stunned() -> void:
	var p := _paladin()
	_learn(p, &"hammer_of_justice")
	var near := _enemy(Vector3(0, 0, -2.0))
	var far := _enemy(Vector3(4.0, 0, 0))
	near.stun_left = 1.0
	var targets := PaladinHammerOfJustice.targets_for(_ctx(p, &"hammer_of_justice"), 2)
	check_eq(targets.size(), 2, "two candidates")
	if targets.size() == 2:
		check(targets[0] == far, "the free enemy first")
		check(targets[1] == near, "then the stunned one")
	var none := PaladinHammerOfJustice.targets_for(_ctx(p, &"hammer_of_justice"), 0)
	check(none.is_empty(), "no hammers, no targets")


func test_hammer_auto_cast_needs_an_enemy_in_range() -> void:
	var p := _paladin()
	var slot := _learn(p, &"hammer_of_justice")
	var effect := _effect(p, &"hammer_of_justice")
	check(not effect.wants_auto_cast(_ctx(p, &"hammer_of_justice")), "no enemy")
	var e := _enemy(Vector3(0, 0, -10.0))
	check(not effect.wants_auto_cast(_ctx(p, &"hammer_of_justice")), "beyond 9 m")
	e.global_position = Vector3(0, 0, -8.0)
	EnemyGrid.mark_dirty()
	check(effect.wants_auto_cast(_ctx(p, &"hammer_of_justice")), "in range")
	# Auto slots fire by themselves for a human player too.
	for i in 20:
		p.abilities._physics_process(DT)
	check(p.abilities.remaining(slot) > 0.0, "auto-cast fired")
	check_eq(_missiles().size(), 1, "one hammer thrown")


func test_hammer_rank_two_and_three() -> void:
	var p := _paladin()
	_learn(p, &"hammer_of_justice", 2)
	var a := Db.get_ability(&"hammer_of_justice")
	check_near(p.abilities.cooldown_of(a), 8.0 * 0.9, 0.001, "Rank II: -10% cooldown")
	check_near(PaladinHammerOfJustice.hammer_damage(_ctx(p, a.id)), MACE_HIT * 1.5 * 1.25, 0.001, "Rank II: +25%")
	_rank(p, a.id, 3)
	check_eq(int(p.abilities.params_for(a)["hammers"]), 2, "Rank III: two hammers")
	var e1 := _enemy(Vector3(0, 0, -3.0))
	var e2 := _enemy(Vector3(3.0, 0, 3.0))
	check(p.abilities.try_cast(p.abilities.slot_of(a.id)), "cast")
	check_eq(_missiles().size(), 2, "two hammers")
	_fly()
	check_eq(e1.fake_stun_count, 1, "first target stunned")
	check_eq(e2.fake_stun_count, 1, "second target stunned")


func test_hammer_shattering_spec_bursts() -> void:
	var p := _paladin()
	var slot := _learn(p, &"hammer_of_justice", 5, 0)
	check_near(float(p.abilities.params_for(Db.get_ability(&"hammer_of_justice"))["impact_radius"]), 2.5, 0.001, "burst radius")
	# Rank V keeps Rank III's second hammer: it goes to `other` (the nearest), the first to
	# `target`; `beside` is no hammer target but stands in the burst.
	var other := _enemy(Vector3(-4.0, 0, 0))
	var target := _enemy(Vector3(0, 0, -5.0))
	var beside := _enemy(Vector3(1.5, 0, -5.5))
	var far := _enemy(Vector3(6.0, 0, -5.0))
	check(p.abilities.try_cast(slot), "cast")
	_fly()
	check_eq(other.fake_stun_count, 1, "second hammer's target stunned")
	check_eq(target.fake_stun_count, 1, "target stunned")
	check_eq(beside.fake_stun_count, 1, "neighbour stunned by the burst")
	check(beside.fake_hits() == 1, "neighbour damaged")
	check_eq(far.fake_hits(), 0, "out of the burst")
	if target.fake_hits() > 0:
		check_near(target.fake_damage_log[0], MACE_HIT * 1.5 * 1.5, 0.001, "Rank V power")


func test_hammer_wrathful_spec_executes_and_cuts_the_cooldown() -> void:
	var p := _paladin()
	var slot := _learn(p, &"hammer_of_justice", 5, 1)
	var a := Db.get_ability(&"hammer_of_justice")
	check_near(p.abilities.cooldown_of(a), 8.0 * 0.8, 0.001, "Rank V cooldown")
	# Rank V keeps Rank III's second hammer: one for each enemy.
	var weak := _mortal(Vector3(0, 0, -4.0), 20.0)  # 20% HP
	var sturdy := _mortal(Vector3(4.0, 0, 0), 100.0)
	check(p.abilities.try_cast(slot), "cast")
	check_near(p.abilities.remaining(slot), 6.4, 0.001, "on cooldown")
	_fly()
	check_eq(weak.fake_hits(), 1, "weak hit")
	if weak.fake_hits() > 0:
		check_near(weak.fake_damage_log[0], MACE_HIT * 1.5 * 1.5 * 2.0, 0.001, "+100% below 35% HP")
	check(weak.is_dead(), "killed")
	check_eq(sturdy.fake_hits(), 1, "sturdy hit")
	if sturdy.fake_hits() > 0:
		check_near(sturdy.fake_damage_log[0], MACE_HIT * 1.5 * 1.5, 0.001, "no bonus at full HP")
	check(not sturdy.is_dead(), "sturdy lives")
	# One kill: 2 s off (the flight took a few ticks of the 6.4 s, which _fly does not count).
	check_near(p.abilities.remaining(slot), 6.4 - 2.0, 0.001, "a killing blow takes 2 s off")


# --- Avenger's Shield -------------------------------------------------------------------------

func test_shield_bounces_between_three_enemies() -> void:
	var p := _paladin()
	var slot := _learn(p, &"avengers_shield")
	var es: Array[Fakes.FakeEnemy] = []
	for i in 4:
		es.append(_enemy(Vector3(2.0 * i, 0, -4.0)))
	check(p.abilities.try_cast(slot), "cast")
	check_near(p.abilities.remaining(slot), 10.0, 0.001, "10 s cooldown")
	var ms := _missiles()
	check_eq(ms.size(), 1, "one shield")
	if ms.is_empty():
		return
	check(ms[0].look == PaladinHolyMissile.Look.SHIELD, "shield look")
	_fly(2.0)
	for i in 3:
		check_eq(es[i].fake_hits(), 1, "enemy %d hit once" % i)
		if es[i].fake_hits() > 0:
			check_near(es[i].fake_damage_log[0], MACE_HIT, 0.001, "100% weapon damage")
	check_eq(es[3].fake_hits(), 0, "only 3 targets")
	check_eq(ms[0].victim_ids.size(), 3, "three victims")
	check(ms[0].is_done(), "done")


func test_shield_ends_without_a_next_target() -> void:
	var p := _paladin()
	var slot := _learn(p, &"avengers_shield")
	var lone := _enemy(Vector3(0, 0, -3.0))
	var far := _enemy(Vector3(0, 0, -15.0))
	check(p.abilities.try_cast(slot), "cast")
	_fly(2.0)
	check_eq(lone.fake_hits(), 1, "hit")
	check_eq(far.fake_hits(), 0, "no ricochet beyond 6 m")
	check(_missiles().is_empty(), "ended")


func test_shield_rank3_and_bulwark() -> void:
	var p := _paladin()
	var slot := _learn(p, &"avengers_shield", 3)
	check_eq(int(p.abilities.params_for(Db.get_ability(&"avengers_shield"))["targets"]), 4, "Rank III: 4 targets")
	_rank(p, &"avengers_shield", 5, 0)
	for i in 5:
		_enemy(Vector3(2.0 * i, 0, -4.0))
	check(p.abilities.try_cast(slot), "cast")
	_fly(3.0)
	# 4 enemies struck x 4% of max HP x 1.5 (Rank V power).
	check_near(p.procs.shield_hp, 4.0 * p.max_hp() * 0.04 * 1.5, 0.001, "absorb shield per enemy")


func test_shield_dazing_spec() -> void:
	var p := _paladin()
	var slot := _learn(p, &"avengers_shield", 5, 1)
	check_eq(int(p.abilities.params_for(Db.get_ability(&"avengers_shield"))["targets"]), 6, "3 + 1 + 2 targets")
	var es: Array[Fakes.FakeEnemy] = []
	for i in 7:
		es.append(_enemy(Vector3(2.0 * i, 0, -4.0)))
	check(p.abilities.try_cast(slot), "cast")
	_fly(4.0)
	var hit := 0
	for e in es:
		if e.fake_hits() > 0:
			hit += 1
			check_near(e.slow_pct, 50.0, 0.001, "dazed")
	check_eq(hit, 6, "6 enemies")


func test_shield_auto_cast_rule() -> void:
	var p := _paladin()
	_learn(p, &"avengers_shield")
	var effect := _effect(p, &"avengers_shield")
	check(not effect.wants_auto_cast(_ctx(p, &"avengers_shield")), "no enemy")
	var e := _enemy(Vector3(0, 0, -7.0))
	check(not effect.wants_auto_cast(_ctx(p, &"avengers_shield")), "a lone far enemy: wait")
	e.global_position = Vector3(0, 0, -3.0)
	EnemyGrid.mark_dirty()
	check(effect.wants_auto_cast(_ctx(p, &"avengers_shield")), "a close enemy")
	e.global_position = Vector3(0, 0, -7.0)
	_enemy(Vector3(2.0, 0, -7.0))
	check(effect.wants_auto_cast(_ctx(p, &"avengers_shield")), "two enemies in range")


# --- Divine Storm -----------------------------------------------------------------------------

func test_divine_storm_damages_and_heals() -> void:
	var p := _paladin()
	var slot := _learn(p, &"divine_storm")
	var inside := _enemy(Vector3(2.0, 0, 0))
	var outside := _enemy(Vector3(5.0, 0, 0))
	var near := _ally(1, Vector3(0, 0, 4.0))
	var far := _ally(2, Vector3(0, 0, 8.0), &"rogue")
	var healthy := _ally(3, Vector3(-3.0, 0, 0), &"mage")
	p.hp = 5.0
	near.hp = 4.0
	far.hp = 4.0
	check(p.abilities.try_cast(slot), "cast")
	check_near(p.abilities.remaining(slot), 10.0, 0.001, "10 s cooldown")
	check_eq(inside.fake_hits(), 1, "enemy inside struck")
	check_eq(outside.fake_hits(), 0, "outside")
	if inside.fake_hits() > 0:
		check_near(inside.fake_damage_log[0], MACE_HIT, 0.001, "100% weapon damage")
	check_near(p.hp, 5.0 + 1.0 + p.max_hp() * 0.05, 0.001, "Paladin healed")
	check_near(near.hp, 4.0 + 1.0 + near.max_hp() * 0.05, 0.001, "near ally healed")
	check_eq(far.hp, 4.0, "beyond 6 m")
	check_eq(healthy.hp, healthy.max_hp(), "full ally untouched")
	check_eq(_vfx(world, "PaladinStorm").size(), 1, "storm look")


func test_divine_storm_auto_cast_rule() -> void:
	var p := _paladin()
	_learn(p, &"divine_storm")
	var effect := _effect(p, &"divine_storm")
	check(not effect.wants_auto_cast(_ctx(p, &"divine_storm")), "no enemy")
	var e := _enemy(Vector3(4.5, 0, 0))
	check(not effect.wants_auto_cast(_ctx(p, &"divine_storm")), "too far")
	e.global_position = Vector3(3.0, 0, 0)
	EnemyGrid.mark_dirty()
	check(effect.wants_auto_cast(_ctx(p, &"divine_storm")), "touching the storm")


func test_divine_storm_rank3_power_and_merciful_spec() -> void:
	var p := _paladin()
	var slot := _learn(p, &"divine_storm", 3)
	var a := Db.get_ability(&"divine_storm")
	check_near(PaladinDivineStorm.reach_of(_ctx(p, a.id)), 4.0, 0.001, "Rank III: 4 m")
	var e := _enemy(Vector3(3.8, 0, 0))
	check(p.abilities.try_cast(slot), "cast")
	check_eq(e.fake_hits(), 1, "reached at 3.8 m")
	if e.fake_hits() > 0:
		check_near(e.fake_damage_log[0], MACE_HIT * 1.25, 0.001, "Rank II power")
	_rank(p, a.id, 5, 1)
	p.abilities.set_cooldown(a, 0.0)
	for i in 2:
		_enemy(Vector3(-1.0, 0, 1.0 + i))
	var ally := _ally(1, Vector3(0, 0, 9.0))
	ally.hp = 2.0
	check(p.abilities.try_cast(slot), "cast again")
	# 3 enemies x 2% bonus; within 10 m; x 1.5 power.
	check_near(ally.hp, minf(ally.max_hp(), 2.0 + (1.0 + ally.max_hp() * (5.0 + 6.0) / 100.0) * 1.5), 0.001,
			"Merciful: bigger heal, longer reach")


func test_divine_tempest_strikes_three_times() -> void:
	var p := _paladin()
	var slot := _learn(p, &"divine_storm", 5, 0)
	var e := _enemy(Vector3(1.0, 0, 0))
	var effect := _effect(p, &"divine_storm") as PaladinDivineStorm
	check(p.abilities.try_cast(slot), "cast")
	check_eq(e.fake_hits(), 1, "first strike at once")
	check(effect.is_storming(), "still whirling")
	check(not effect.can_cast(_ctx(p, &"divine_storm")), "no recast while whirling")
	_run(p, 0.4)
	check_eq(e.fake_hits(), 2, "second strike")
	_run(p, 0.4)
	check_eq(e.fake_hits(), 3, "third strike")
	_run(p, 1.0)
	check_eq(e.fake_hits(), 3, "only three")
	check(not effect.is_storming(), "over")
	# Going down ends the storm.
	p.abilities.set_cooldown(Db.get_ability(&"divine_storm"), 0.0)
	check(p.abilities.try_cast(slot), "recast")
	_down(p)
	check(not effect.is_storming(), "downed: storm over")
	p.revive(1.0)
	_run(p, 1.0)
	check_eq(e.fake_hits(), 4, "no strikes after going down")


# --- Blessing of Kings ------------------------------------------------------------------------

func test_kings_blesses_every_living_hero() -> void:
	var p := _paladin()
	var slot := _learn(p, &"blessing_of_kings")
	var effect := _effect(p, &"blessing_of_kings") as PaladinBlessingOfKings
	var key := PaladinBlessingOfKings.source_key(p)
	check_eq(key, &"kings:paladin0", "per-Paladin source")
	var ally := _ally(1, Vector3(20.0, 0, 0))
	ally.stats.set_source(&"test", {Stats.STRENGTH: 10.0, Stats.CRIT: 20.0, Stats.SPELL_POWER: 4.0})
	var downed := _ally(2, Vector3(2.0, 0, 0), &"rogue")
	_down(downed)
	var str_before := ally.stats.get_raw(Stats.STRENGTH)
	var armor_before := ally.stats.get_raw(Stats.ARMOR)
	var max_before := ally.max_hp()
	var pal_max := p.max_hp()
	check(p.abilities.try_cast(slot), "cast")
	check_near(p.abilities.remaining(slot), 15.0, 0.001, "15 s cooldown")
	check(ally.stats.has_source(key), "far ally blessed (every hero)")
	check(p.stats.has_source(key), "the Paladin too")
	check(not downed.stats.has_source(key), "not a downed hero")
	check_near(ally.stats.get_raw(Stats.STRENGTH), str_before * 1.05, 0.0001, "+5% Strength")
	check_near(ally.stats.get_raw(Stats.ARMOR), armor_before * 1.05, 0.0001, "+5% Armor")
	check_near(ally.stats.get_raw(Stats.CRIT), 21.0, 0.0001, "+5% Crit")
	check_near(ally.stats.get_raw(Stats.SPELL_POWER), 4.2, 0.0001, "+5% Spell Power")
	check_near(ally.max_hp(), max_before * 1.05, 0.0001, "+5% Max HP")
	check_near(ally.hp, ally.max_hp(), 0.0001, "a full hero stays full")
	check_near(p.max_hp(), pal_max * 1.05, 0.0001, "Paladin +5% Max HP")
	check(not ally.stats.get_source(key).has(Stats.DAMAGE_PCT), "no negative / other stats")
	check_eq(effect.blessed().size(), 2, "two blessed")
	check_eq(_vfx(ally, "PaladinKingsMark").size(), 1, "mark under the ally")
	check_eq(_vfx(ally, "PaladinCrown").size(), 1, "crown over the ally")
	_run(p, 9.9)
	check(ally.stats.has_source(key), "still blessed at 9.9 s")
	_run(p, 0.2)
	check(not ally.stats.has_source(key), "gone after 10 s")
	check(not p.stats.has_source(key), "from the Paladin too")
	check_near(ally.max_hp(), max_before, 0.0001, "Max HP back")
	check(ally.hp <= ally.max_hp(), "HP clamped")
	var marks := _vfx(ally, "PaladinKingsMark")
	check(marks.is_empty() or _ending(marks[0]), "mark fades")


func test_kings_does_not_compound_and_two_paladins_stack() -> void:
	var a := _paladin()
	var b := _paladin(Vector3(2.0, 0, 0), 1)
	var ally := _ally(2, Vector3(1.0, 0, 0))
	ally.stats.set_source(&"test", {Stats.STRENGTH: 20.0})
	var own := ally.stats.get_raw(Stats.STRENGTH)
	var slot_a := _learn(a, &"blessing_of_kings")
	var slot_b := _learn(b, &"blessing_of_kings")
	check(a.abilities.try_cast(slot_a), "first Paladin")
	check(b.abilities.try_cast(slot_b), "second Paladin")
	check_near(ally.stats.get_raw(Stats.STRENGTH), own * 1.1, 0.0001, "two sources of 5% of the own stats")
	a.abilities.set_cooldown(Db.get_ability(&"blessing_of_kings"), 0.0)
	check(a.abilities.try_cast(slot_a), "recast")
	check_near(ally.stats.get_raw(Stats.STRENGTH), own * 1.1, 0.0001, "a recast does not compound")
	ally.hp = 10.0
	a.abilities.set_cooldown(Db.get_ability(&"blessing_of_kings"), 0.0)
	check(a.abilities.try_cast(slot_a), "recast on a hurt ally")
	check_eq(ally.hp, 10.0, "a recast gives no HP")


func test_kings_power_and_specs() -> void:
	var p := _paladin()
	var slot := _learn(p, &"blessing_of_kings", 2)
	var ally := _ally(1, Vector3(3.0, 0, 0))
	ally.stats.set_source(&"test", {Stats.AGILITY: 10.0})
	var agi := ally.stats.get_raw(Stats.AGILITY)
	check(p.abilities.try_cast(slot), "cast")
	check_near(ally.stats.get_raw(Stats.AGILITY), agi * 1.0625, 0.0001, "Rank II: +6.25%")
	var key := PaladinBlessingOfKings.source_key(p)
	_rank(p, &"blessing_of_kings", 3)
	check_near(float(p.abilities.params_for(Db.get_ability(&"blessing_of_kings"))["duration"]), 15.0, 0.001, "Rank III: 15 s")
	_rank(p, &"blessing_of_kings", 5, 0)
	p.abilities.set_cooldown(Db.get_ability(&"blessing_of_kings"), 0.0)
	check(p.abilities.try_cast(slot), "Might")
	check_near(ally.damage_mults.get(key, 1.0), 1.15, 0.0001, "+10% x 1.5 damage")
	check_near(ally.stats.get_raw(Stats.AGILITY), agi * 1.075, 0.0001, "Rank V: +7.5%")
	_run(p, 15.1)
	check(not ally.damage_mults.has(key), "Might ends with the blessing")
	check(not ally.stats.has_source(key), "blessing over after 15 s")
	check(p.abilities.set_spec(&"blessing_of_kings", 1), "switch to Sanctuary")
	p.abilities.set_cooldown(Db.get_ability(&"blessing_of_kings"), 0.0)
	check(p.abilities.try_cast(slot), "Sanctuary")
	check_near(ally.damage_taken_mults.get(key, 1.0), 0.85, 0.0001, "-10% x 1.5 damage taken")
	var hp := ally.hp
	ally.invulnerable_left = 0.0
	var expected := CombatMath.incoming_damage(4.0, ally.stats) * 0.85
	ally.take_damage(4.0)
	check_near(hp - ally.hp, expected, 0.001, "takes 15% less")
	p.end_wave()
	check(not ally.damage_taken_mults.has(key), "Sanctuary gone at wave end")


func test_kings_cleanup() -> void:
	var p := _paladin()
	var slot := _learn(p, &"blessing_of_kings")
	var a := Db.get_ability(&"blessing_of_kings")
	var key := PaladinBlessingOfKings.source_key(p)
	var ally := _ally(1, Vector3(3.0, 0, 0))
	var other := _ally(2, Vector3(-3.0, 0, 0), &"mage")
	# Wave end.
	check(p.abilities.try_cast(slot), "cast")
	p.end_wave()
	check(not ally.stats.has_source(key) and not p.stats.has_source(key), "wave end clears")
	# Wave start.
	p.abilities.set_cooldown(a, 0.0)
	check(p.abilities.try_cast(slot), "cast")
	p.begin_wave()
	check(not ally.stats.has_source(key), "wave start clears")
	# An ally going down loses it at the next tick; the others keep it.
	p.abilities.set_cooldown(a, 0.0)
	check(p.abilities.try_cast(slot), "cast")
	_down(ally)
	_run(p, DT)
	check(not ally.stats.has_source(key), "downed ally loses it")
	check(other.stats.has_source(key), "others keep it")
	# The Paladin going down clears it for everybody.
	_down(p)
	check(not other.stats.has_source(key) and not p.stats.has_source(key), "Paladin down clears")
	p.revive(1.0)
	ally.revive(1.0)
	# Forgetting the ability.
	p.abilities.set_cooldown(a, 0.0)
	check(p.abilities.try_cast(slot), "cast")
	p.abilities.forget(slot)
	check(not other.stats.has_source(key), "forget clears")
	# The Paladin leaving the game.
	_learn(p, &"blessing_of_kings")
	check(p.abilities.try_cast(p.abilities.slot_of(a.id)), "cast")
	check(other.stats.has_source(key), "blessed")
	world.remove_child(p)
	check(not other.stats.has_source(key), "the Paladin left: cleared")
	p.free()


func test_kings_auto_cast_rule() -> void:
	var p := _paladin()
	var slot := _learn(p, &"blessing_of_kings")
	var effect := _effect(p, &"blessing_of_kings") as PaladinBlessingOfKings
	check(not effect.wants_auto_cast(_ctx(p, &"blessing_of_kings")), "no fight: wait")
	_enemy(Vector3(10.0, 0, 0))
	check(effect.wants_auto_cast(_ctx(p, &"blessing_of_kings")), "an enemy near: bless")
	check(p.abilities.try_cast(slot), "cast")
	check(not effect.wants_auto_cast(_ctx(p, &"blessing_of_kings")), "running: no recast")
	var ctx := _ctx(p, &"blessing_of_kings")
	for i in roundi(9.2 / DT):
		effect.tick(ctx, DT)
	check_near(effect.time_left(), 0.8, 0.01, "0.8 s left")
	check(effect.wants_auto_cast(_ctx(p, &"blessing_of_kings")), "about to end: refresh")


# --- Divine Shield ----------------------------------------------------------------------------

func test_divine_shield_makes_invulnerable() -> void:
	var p := _paladin()
	var slot := _learn(p, &"divine_shield")
	check_eq(slot, 2, "RB")
	check(p.abilities.try_cast(slot), "cast")
	check_near(p.abilities.remaining(slot), 40.0, 0.001, "40 s cooldown")
	check_near(p.invulnerable_left, 3.0, 0.001, "3 s")
	check_eq(_vfx(p, "PaladinBubble").size(), 1, "bubble")
	var hp := p.hp
	p.take_damage(50.0)
	check_eq(p.hp, hp, "immune")
	_run(p, 2.9)
	p.take_damage(50.0)
	check_eq(p.hp, hp, "still immune at 2.9 s")
	_run(p, 0.2)
	var bubbles := _vfx(p, "PaladinBubble")
	check(bubbles.is_empty() or _ending(bubbles[0]), "bubble ends")
	p.take_damage(3.0)
	check(p.hp < hp, "vulnerable again")


func test_divine_shield_rank_power_and_rank3_heal() -> void:
	var p := _paladin()
	var slot := _learn(p, &"divine_shield", 3)
	p.hp = 2.0
	check(p.abilities.try_cast(slot), "cast")
	check_near(p.invulnerable_left, 3.0 * 1.25, 0.001, "Rank II: longer")
	check_near(p.hp, 2.0 + p.max_hp() * 0.25 * 1.25, 0.001, "Rank III: heal")


func test_divine_shield_radiant_spec_burns() -> void:
	var p := _paladin()
	var slot := _learn(p, &"divine_shield", 5, 0)
	var near := _enemy(Vector3(2.0, 0, 0))
	var far := _enemy(Vector3(5.0, 0, 0))
	check(p.abilities.try_cast(slot), "cast")
	_run(p, 4.5 + 0.2)
	# 4.5 s at Rank V: ticks at 0, 0.5, ... 4.0 = 9.
	check_eq(near.fake_hits(), 9, "burned every 0.5 s while shielded")
	check_eq(far.fake_hits(), 0, "out of reach")
	if near.fake_hits() > 0:
		check_near(near.fake_damage_log[0], MACE_HIT * 0.4 * 1.5, 0.001, "40% weapon damage x power")


func test_divine_shield_sheltering_spec_shares() -> void:
	var p := _paladin()
	var slot := _learn(p, &"divine_shield", 5, 1)
	var hurt := _ally(1, Vector3(5.0, 0, 0))
	var healthy := _ally(2, Vector3(-3.0, 0, 0), &"mage")
	var far := _ally(3, Vector3(12.0, 0, 0), &"rogue")
	hurt.hp = 3.0
	far.hp = 1.0
	check(p.abilities.try_cast(slot), "cast")
	check_near(hurt.invulnerable_left, 4.5, 0.001, "the most wounded ally in range shielded")
	check_eq(healthy.invulnerable_left, 0.0, "only one ally")
	check_eq(far.invulnerable_left, 0.0, "out of range")
	check_eq(_vfx(hurt, "PaladinBubble").size(), 1, "ally bubble")


func test_divine_shield_bot_rule_and_cleanup() -> void:
	var p := _paladin()
	var slot := _learn(p, &"divine_shield")
	var effect := _effect(p, &"divine_shield") as PaladinDivineShield
	check(not effect.wants_auto_cast(_ctx(p, &"divine_shield")), "full HP")
	p.hp = p.max_hp() * 0.3
	check(not effect.wants_auto_cast(_ctx(p, &"divine_shield")), "low HP but no enemy")
	_enemy(Vector3(2.0, 0, 0))
	check(effect.wants_auto_cast(_ctx(p, &"divine_shield")), "low HP, enemy close")
	check(p.abilities.try_cast(slot), "cast")
	check(not effect.wants_auto_cast(_ctx(p, &"divine_shield")), "already shielded")
	p.end_wave()
	check(not effect.is_shielded(), "wave end ends it")
	var bubbles := _vfx(p, "PaladinBubble")
	check(bubbles.is_empty() or _ending(bubbles[0]), "bubble fades")


# --- Lay on Hands -----------------------------------------------------------------------------

func test_lay_on_hands_fully_heals_the_lowest_ratio() -> void:
	var p := _paladin()
	var slot := _learn(p, &"lay_on_hands")
	check_eq(slot, 2, "RB (first active)")
	var tank := _ally(1, Vector3(4.0, 0, 0))
	var squishy := _ally(2, Vector3(-4.0, 0, 0), &"mage")
	var downed := _ally(3, Vector3(0, 0, 4.0), &"rogue")
	_down(downed)
	check(not p.abilities.try_cast(slot), "nobody hurt: no cast")
	check_eq(p.abilities.remaining(slot), 0.0, "cooldown kept")
	tank.hp = tank.max_hp() * 0.3
	squishy.hp = squishy.max_hp() * 0.4
	p.hp = p.max_hp() * 0.5
	check(PaladinLayOnHands.heal_target(_ctx(p, &"lay_on_hands")) == tank, "lowest share of HP")
	check(p.abilities.try_cast(slot), "cast")
	check_near(p.abilities.remaining(slot), 60.0, 0.001, "60 s cooldown")
	check_eq(tank.hp, tank.max_hp(), "fully healed")
	check_near(squishy.hp, squishy.max_hp() * 0.4, 0.001, "others untouched")
	check_near(p.hp, p.max_hp() * 0.5, 0.001, "Paladin untouched")
	check(downed.downed, "no revive")


func test_lay_on_hands_heals_self_and_respects_range() -> void:
	var p := _paladin()
	var slot := _learn(p, &"lay_on_hands")
	var far := _ally(1, Vector3(16.0, 0, 0))
	far.hp = 1.0
	p.hp = p.max_hp() * 0.8
	check(PaladinLayOnHands.heal_target(_ctx(p, &"lay_on_hands")) == p, "the ally beyond 15 m is skipped")
	check(p.abilities.try_cast(slot), "cast")
	check_eq(p.hp, p.max_hp(), "self healed")
	check_eq(far.hp, 1.0, "out of range")


func test_lay_on_hands_rank3_shield_and_guardian_spec() -> void:
	var p := _paladin()
	var slot := _learn(p, &"lay_on_hands", 5, 1)
	var ally := _ally(1, Vector3(3.0, 0, 0))
	ally.hp = 1.0
	check(p.abilities.try_cast(slot), "cast")
	check_eq(ally.hp, ally.max_hp(), "full")
	check_near(ally.procs.shield_hp, ally.max_hp() * 0.2 * 1.5, 0.001, "Rank III shield x power")
	var key := PaladinLayOnHands.guard_key(p)
	check_near(ally.damage_taken_mults.get(key, 1.0), 1.0 - PaladinLayOnHands.MAX_GUARD / 100.0, 0.0001, "-50% x 1.5, capped")
	_run(p, 5.9)
	check(ally.damage_taken_mults.has(key), "guarded at 5.9 s")
	_run(p, 0.2)
	check(not ally.damage_taken_mults.has(key), "guard over after 6 s")
	# Cleanup: the Paladin going down ends the guard.
	ally.hp = 1.0
	p.abilities.set_cooldown(Db.get_ability(&"lay_on_hands"), 0.0)
	check(p.abilities.try_cast(slot), "recast")
	_down(p)
	check(not ally.damage_taken_mults.has(key), "Paladin down ends the guard")


func test_lay_on_hands_hands_of_mercy_spec() -> void:
	var p := _paladin()
	var slot := _learn(p, &"lay_on_hands", 5, 0)
	var a := _ally(1, Vector3(3.0, 0, 0))
	var b := _ally(2, Vector3(-3.0, 0, 0), &"mage")
	a.hp = 1.0
	b.hp = 2.0
	p.hp = 3.0
	check(p.abilities.try_cast(slot), "cast")
	# 60% x 1.5 (Rank V power) of max HP each.
	check_near(a.hp, minf(a.max_hp(), 1.0 + a.max_hp() * 0.9), 0.001, "ally a")
	check_near(b.hp, minf(b.max_hp(), 2.0 + b.max_hp() * 0.9), 0.001, "ally b")
	check_near(p.hp, minf(p.max_hp(), 3.0 + p.max_hp() * 0.9), 0.001, "Paladin")


func test_lay_on_hands_bot_rule() -> void:
	var p := _paladin()
	_learn(p, &"lay_on_hands")
	var effect := _effect(p, &"lay_on_hands")
	var ally := _ally(1, Vector3(4.0, 0, 0))
	ally.hp = ally.max_hp() * 0.5
	check(not effect.wants_auto_cast(_ctx(p, &"lay_on_hands")), "50%: save it")
	ally.hp = ally.max_hp() * 0.2
	check(effect.wants_auto_cast(_ctx(p, &"lay_on_hands")), "20%: heal")


# --- Core abilities: ranks --------------------------------------------------------------------

func test_consecration_ranks_and_specs() -> void:
	var p := _paladin()
	var cons := p.abilities.slots[0]
	var base := PaladinConsecration.tick_damage(p.stats, p.abilities.params_for(cons))
	_rank(p, cons.id, 2)
	check_near(PaladinConsecration.tick_damage(p.stats, p.abilities.params_for(cons)), base * 1.25, 0.0001, "Rank II power")
	_rank(p, cons.id, 3)
	check(p.abilities.try_cast(0), "cast")
	var areas: Array[AbilityArea] = []
	for node in tree.get_nodes_in_group(&"ability_areas"):
		if not node.is_queued_for_deletion():
			areas.append(node as AbilityArea)
	check_eq(areas.size(), 1, "one area")
	if not areas.is_empty():
		check_near(areas[0].radius, 4.0, 0.001, "Rank III: +1 m")
		check_eq(areas[0].heal_per_tick, 0.0, "no heal without the spec")
		areas[0].free()
	_rank(p, cons.id, 5, 0)
	p.abilities.set_cooldown(cons, 0.0)
	var ally := _ally(1, Vector3(1.0, 0, 0))
	ally.hp = 2.0
	check(p.abilities.try_cast(0), "Hallowed Ground")
	areas.clear()
	for node in tree.get_nodes_in_group(&"ability_areas"):
		if not node.is_queued_for_deletion():
			areas.append(node as AbilityArea)
	if not areas.is_empty():
		check_near(areas[0].heal_per_tick, 0.5 * 1.5, 0.001, "heal per tick x power")
		Fakes.step(areas[0], 1.0)
		check(ally.hp > 2.0, "ally standing in it healed")
		areas[0].free()
	p.abilities.set_spec(cons.id, 1)
	p.abilities.set_cooldown(cons, 0.0)
	var e := _enemy(Vector3(1.0, 0, 0))
	check(p.abilities.try_cast(0), "Binding Ground")
	for node in tree.get_nodes_in_group(&"ability_areas"):
		if not node.is_queued_for_deletion():
			Fakes.step(node, 0.1)
	check_near(e.slow_pct, 50.0, 0.001, "enemies inside slowed")


func test_word_of_glory_ranks_and_specs() -> void:
	var p := _paladin()
	var wog := p.abilities.slots[1]
	var hp := p.abilities.get_resource(&"holy_power")
	var a := _ally(1, Vector3(3.0, 0, 0))
	var b := _ally(2, Vector3(-3.0, 0, 0), &"mage")
	var c := _ally(3, Vector3(0, 0, 3.0), &"rogue")
	_rank(p, wog.id, 3)
	a.hp = 2.0
	b.hp = 3.0
	c.hp = 4.0
	p.hp = 5.0
	hp.set_value(3.0)
	check(p.abilities.try_cast(1), "cast")
	check_near(a.hp, minf(a.max_hp(), 2.0 + (3.0 + a.max_hp() * 0.25) * 1.25), 0.001, "most hurt, Rank II power")
	check(b.hp > 3.0, "Rank III: the second most hurt ally too")
	check_eq(c.hp, 4.0, "not a third ally")
	check(p.hp > 5.0, "Paladin healed")
	# Revive at Rank III: 40% x 1.25.
	_down(c)
	hp.set_value(3.0)
	check(p.abilities.try_cast(1), "revive")
	check_eq(c.hp, roundf(c.max_hp() * 0.5), "revived at 50%")
	# Light of Dawn: every hero in range.
	_rank(p, wog.id, 5, 0)
	for h: Player in [a, b, c, p]:
		h.hp = 2.0
	hp.set_value(3.0)
	check(p.abilities.try_cast(1), "Light of Dawn")
	for h: Player in [a, b, c, p]:
		check(h.hp > 2.0, "%s healed" % h.name)
	# Holy Bulwark: an absorb shield worth half of the heal.
	p.abilities.set_spec(wog.id, 1)
	a.hp = 2.0
	hp.set_value(3.0)
	check(p.abilities.try_cast(1), "Holy Bulwark")
	var heal := (3.0 + a.max_hp() * 0.25) * 1.5
	check_near(a.procs.shield_hp, heal * 0.5, 0.001, "shield = 50% of the heal")


# --- Bots ------------------------------------------------------------------------------------

func test_bot_paladin_uses_learned_abilities() -> void:
	var slot := PlayerSlot.new(0, BotInput.new("bot:paladin", 7), PlayerManager.PLAYER_COLORS[0])
	slot.class_data = Db.get_class_data(&"paladin")
	var p := Player.create(slot)
	world.add_child(p)
	check(p.abilities.auto_cast, "bot")
	for id in LEARNED:
		check(p.abilities.learn(Db.get_ability(id)) >= 0, "learned %s" % id)
	var ally := _ally(1, Vector3(3.0, 0, 0))
	ally.hp = ally.max_hp() * 0.2
	for i in 3:
		_enemy(Vector3(1.5 + i, 0, -1.0))
	for i in 30:
		p.abilities._physics_process(DT)
	for id in [&"hammer_of_justice", &"avengers_shield", &"divine_storm", &"blessing_of_kings", &"lay_on_hands"]:
		check(p.abilities.remaining(p.abilities.slot_of(id)) > 0.0, "bot cast %s" % id)
	check_eq(p.abilities.remaining(p.abilities.slot_of(&"divine_shield")), 0.0, "healthy bot keeps Divine Shield")
	check_eq(ally.hp, ally.max_hp(), "Lay on Hands saved the ally")
