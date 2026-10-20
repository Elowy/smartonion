extends TestCase
## Hunter companion (M8, GDD 3.7) – Wolf, Boar and Owl: the kinds and their numbers, damage through the
## pet source (Beastbond, mods, no crits, credit and meter), the boar's charge and taunt, the owl's
## hover and feather bolts, hiding while the Hunter is down, the wave snap and the teardown; Hunt Signal
## (target choice, riders, strikes, splash, bleed, kill reset).

const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0

## A fake enemy that dies when its health runs out (the plain fake only records hits).
class MortalEnemy extends Fakes.FakeEnemy:
	func take_damage(amount: float, is_crit: bool = false, attacker: Node3D = null,
			knockback: Vector3 = Vector3.ZERO) -> void:
		super.take_damage(amount, is_crit, attacker, knockback)
		if hp <= 0.0:
			fake_dead = true

var world: Node3D
var hunter: Player


func before_each() -> void:
	PlayerManager.clear()
	RunState.start_run(1, 43)
	world = Fakes.make_world(tree)
	hunter = Fakes.spawn_player(world, 0, &"hunter")
	hunter.stats.set_source(&"test", {Stats.CRIT: -500.0, Stats.DODGE: -500.0})
	hunter.facing = Vector3.FORWARD


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	hunter = null
	PlayerManager.clear()
	EnemyGrid.mark_dirty()


# --- Helpers ---------------------------------------------------------------------------------

func _w() -> float:
	return GeneralKit.weapon_damage(hunter, &"physical")


func _mastery() -> HunterMastery:
	return hunter.abilities.mastery as HunterMastery


## The companion of [param kind] for the current Hunter (a fresh one when the kind changes).
func _pet(kind: StringName = &"wolf") -> HunterCompanion:
	var m := _mastery()
	if m.has_companion() and m.companion.kind != kind:
		m.companion.free()
		m.companion = null
	hunter.companion_id = kind
	return m.ensure_companion()


func _enemy(pos: Vector3, radius: float = 0.45) -> Fakes.FakeEnemy:
	var e := Fakes.spawn_enemy(world, pos, radius)
	EnemyGrid.mark_dirty()
	return e


func _step(pet: HunterCompanion, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		pet.step(DT)
		t += DT


func _learn(id: StringName, rank: int = 1, spec: int = -1) -> int:
	var i := hunter.abilities.learn(Db.get_ability(id))
	check(i >= 0, "%s learned" % id)
	for r in range(1, rank):
		hunter.abilities.rank_up(id)
	if spec >= 0:
		check(hunter.abilities.set_spec(id, spec), "%s spec %d" % [id, spec])
	return i


func _mods(entries: Array) -> void:
	var typed: Array[Dictionary] = []
	typed.assign(entries)
	hunter.bonuses.set_effects(PlayerBonuses.SOURCE_TALENTS, typed)


# --- Kinds ------------------------------------------------------------------------------------

func test_the_three_kinds_have_their_models_and_numbers() -> void:
	var table := {
		&"wolf": {"damage_pct": 38.0, "interval": 1.2, "range": 8.0, "slow": 30.0, "slow_duration": 1.0},
		&"boar": {"damage_pct": 50.0, "interval": 2.0, "range": 7.0, "charge_pct": 55.0, "charge_cooldown": 7.0,
			"charge_range": 8.0, "taunt_radius": 4.0, "taunt_duration": 1.5},
		&"owl": {"damage_pct": 20.0, "interval": 0.6, "range": 9.0, "attack_range": 8.0},
	}
	for kind: StringName in table:
		var pet := _pet(kind)
		check(pet != null and pet.is_inside_tree(), "%s: spawned" % kind)
		check_eq(pet.kind, kind, "%s: kind" % kind)
		check_eq(pet.model.kind, kind, "%s: model kind" % kind)
		var params := pet.current_params()
		for key: String in HunterCompanion.BASE_PARAMS:
			check(params.has(key), "%s: has %s" % [kind, key])
		for key: String in table[kind]:
			check_eq(params[key], table[kind][key], "%s: %s" % [kind, key])
		check_eq(params["reach"], 0.55, "%s: reach" % kind)
		check_eq(params["speed"], 9.0, "%s: speed" % kind)
		check_eq(params["bolt_speed"], 20.0, "%s: bolt speed" % kind)
	var wolf := HunterCompanion.base_params(&"wolf")
	for key in ["haste", "damage_bonus", "heal_pct", "taunt_radius", "charge_pct", "attack_range"]:
		check_eq(float(wolf[key]), 0.0, "the Wolf has no %s" % key)


func test_the_lobby_pick_decides_the_kind_and_bots_take_the_wolf() -> void:
	var human := PlayerManager.join(ScriptedInput.new("test:h"), Db.get_class_data(&"hunter"))
	human.companion = &"owl"
	var p := Player.create(human)
	world.add_child(p)
	check_eq(p.companion_id, &"owl", "the pick reaches the hero")
	check_eq(HunterCompanion.spawn(p).kind, &"owl", "and the companion")
	var bot := PlayerManager.add_bot(&"hunter", 1)
	var q := Player.create(bot)
	world.add_child(q)
	check_eq(q.companion_id, &"wolf", "a bot takes the Wolf")
	check_eq(HunterCompanion.spawn(q).kind, &"wolf", "and plays with it")


func test_the_companion_is_not_a_target_and_has_no_health() -> void:
	var pet := _pet()
	check(not pet.is_in_group(&"enemies") and not pet.is_in_group(&"players"), "in no target group")
	check(not (&"hp" in pet) and not pet.has_method("take_damage"), "no health to lose")
	check(pet.get_class() == "Node3D", "a plain node: no body for enemies to bump into")


# --- Beastbond and pet damage ----------------------------------------------------------------

func test_beastbond_boosts_pet_damage_only() -> void:
	var m := _mastery()
	check_eq(m.damage_mult(null, &"physical", &"pet"), 1.0, "no Mastery, no bonus")
	hunter.stats.set_source(&"mastery_test", {Stats.MASTERY: 10.0})
	check_near(m.bond_mult(), 1.2, 0.0001, "+2% per Mastery point")
	check_near(m.damage_mult(null, &"physical", &"pet"), 1.2, 0.0001, "pet damage")
	for src: StringName in [&"weapon", &"ability", &"proc", &"dot"]:
		check_eq(m.damage_mult(null, &"physical", src), 1.0, "%s damage is untouched" % src)
	check_eq(m.describe(), "Beastbond: +20% companion damage", "tooltip")
	hunter.stats.set_source(&"base", {Stats.MASTERY: Stats.BASE_MASTERY})
	check_near(m.bond_mult(), 1.0 + (Stats.BASE_MASTERY + 10.0) * 0.02, 0.0001, "with the base Mastery of 5: +30%")


func test_wolf_bites_for_pet_damage_slows_and_is_credited() -> void:
	hunter.stats.set_source(&"mastery_test", {Stats.MASTERY: 10.0})
	var pet := _pet(&"wolf")
	var e := _enemy(Vector3(3, 0, 0))
	_step(pet, 1.0)
	check(e.fake_hits() >= 1, "it ran to the enemy and bit")
	check_near(e.fake_damage_log[0], _w() * 0.38 * 1.2, 0.001, "38% W x Beastbond")
	check_eq(e.fake_attacker_log[0], hunter, "kill credit goes to the Hunter")
	check(not e.fake_crit_log[0], "pets never crit")
	check_eq(e.slow_pct, 30.0, "30% slow")
	check_near(e.slow_left, 1.0, 0.3, "for a second")
	check(RunState.damage_by_player.get(0, 0.0) > 0.0, "and the meter counts it as the Hunter's damage")


func test_pets_never_crit_whatever_the_crit_chance() -> void:
	hunter.stats.set_source(&"test", {Stats.CRIT: 900.0})
	var pet := _pet(&"wolf")
	var e := _enemy(Vector3(2, 0, 0))
	_step(pet, 2.5)
	check(e.fake_hits() >= 2, "bites")
	for crit in e.fake_crit_log:
		check(not crit, "no crit")
	for d in e.fake_damage_log:
		check_near(d, _w() * 0.38, 0.001, "plain damage")


func test_wolf_bites_at_its_interval_and_haste_speeds_it_up() -> void:
	var pet := _pet(&"wolf")
	var e := _enemy(Vector3(1.2, 0, 0))
	_step(pet, 6.2)
	var plain := e.fake_hits()
	check(plain >= 4 and plain <= 6, "about five bites in six seconds (%d)" % plain)
	check_near(pet.attack_interval(), 1.2, 0.0001, "1.2 s")
	hunter.stats.set_source(&"haste", {Stats.HASTE: 100.0})
	check_near(pet.attack_interval(), 0.6, 0.0001, "the Hunter's Haste applies")
	hunter.stats.remove_source(&"haste")
	_mods([{"kind": "ability", "match": {"id": "hunter_companion"}, "mods": {"haste_add": 50.0, "damage_bonus_add": 30.0}}])
	_step(pet, 0.3)
	check_near(pet.attack_interval(), 1.2 / 1.5, 0.0001, "companion Haste +50%")
	check_near(pet.hit_damage(38.0), _w() * 0.38 * 1.3, 0.001, "damage +30%")
	_mods([])
	hunter.stats.set_source(&"haste", {Stats.HASTE: 1000.0})
	_step(pet, 0.3)
	check_near(pet.attack_interval(), HunterCompanion.MIN_INTERVAL, 0.0001, "never faster than 0.2 s")


func test_pack_frenzy_hooks_boost_damage_and_speed_and_glow() -> void:
	var pet := _pet(&"wolf")
	check(not pet.model.is_frenzied(), "calm")
	pet.frenzy_left = 2.0
	pet.frenzy_damage_pct = 50.0
	pet.frenzy_haste_pct = 30.0
	_step(pet, DT)
	check(pet.model.is_frenzied(), "the companion glows")
	check_near(pet.hit_damage(100.0), _w() * 1.5, 0.001, "+50% damage")
	check_near(pet.attack_interval(), 1.2 / 1.3, 0.0001, "+30% attack speed")
	_step(pet, 2.1)
	check_eq(pet.frenzy_left, 0.0, "it ends")
	check(not pet.model.is_frenzied(), "the glow ends")
	check_near(pet.hit_damage(100.0), _w(), 0.001, "back to normal")


func test_bonded_vigor_heals_the_hunter_from_the_damage() -> void:
	_mods([{"kind": "ability", "match": {"id": "hunter_companion"}, "mods": {"heal_pct_add": 50.0}}])
	hunter.hp = hunter.max_hp() * 0.5
	var before := hunter.hp
	var pet := _pet(&"wolf")
	var e := _enemy(Vector3(1.5, 0, 0))
	_step(pet, 0.6)
	check(e.fake_hits() >= 1, "a bite")
	check_near(hunter.hp - before, e.fake_damage_log[0] * 0.5, 0.01, "50% of the damage dealt")


# --- Boar and Owl ------------------------------------------------------------------------------

func test_boar_bites_slowly_and_hard() -> void:
	var pet := _pet(&"boar")
	var e := _enemy(Vector3(1.2, 0, 0))
	pet._charge_left = 99.0
	_step(pet, 4.3)
	check_eq(e.fake_hits(), 3, "bites at t = 0.15, 2.15 and 4.15 s")
	check_near(e.fake_damage_log[0], _w() * 0.5, 0.001, "50% W")
	check_eq(e.slow_pct, 0.0, "no slow")


func test_boar_charges_every_seven_seconds_and_taunts() -> void:
	var pet := _pet(&"boar")
	var target := _enemy(Vector3(0, 0, -5))
	var beside := _enemy(Vector3(2.0, 0, -5))
	var far := _enemy(Vector3(-7, 0, 3))
	pet.global_position = Vector3(0, 0, -1)
	var t := 0.0
	while pet.charges_made == 0 and t < 6.0:
		pet.step(DT)
		t += DT
	check_eq(pet.charges_made, 1, "it charged")
	check(t >= 3.0, "not before its first cooldown has half run (%.1f s)" % t)
	check_near(pet.get_position().z, target.global_position.z, 1.6, "the charge ended at the enemy")
	var charge_hit := 0.0
	for d in target.fake_damage_log:
		charge_hit = maxf(charge_hit, d)
	check_near(charge_hit, _w() * 0.55, 0.001, "the impact hit for 55% W")
	check(target.is_taunted() and target.taunt_target == pet, "the target is taunted to the boar")
	check(beside.is_taunted() and beside.taunt_target == pet, "an enemy within 4 m too")
	check(not far.is_taunted(), "one further away is not")
	check_near(target.taunt_left, 1.5, 0.05, "for 1.5 s")
	check_eq(pet.taunts_applied, 2, "two enemies taunted")
	# Seven seconds until the next one.
	var charges := pet.charges_made
	_step(pet, 6.5)
	check_eq(pet.charges_made, charges, "no second charge within 7 s")
	_step(pet, 1.5)
	check(pet.charges_made > charges or pet.is_charging(), "the next charge comes")


func test_owl_hovers_and_shoots_feather_bolts_without_chasing() -> void:
	var pet := _pet(&"owl")
	check_near(pet.model._pivot.position.y, HunterCompanionModel.HOVER_HEIGHT, 0.1, "hovers 1.6 m up")
	var e := _enemy(Vector3(0, 0, -6))
	var start := pet.global_position
	_step(pet, 0.5)
	check(pet.attacks >= 1, "it shot")
	var bolt := pet.last_bolt
	check(bolt != null and bolt is HunterFeatherBolt, "a feather bolt")
	check_near(bolt.damage, _w() * 0.2, 0.001, "20% W")
	check_near(bolt.speed, 20.0, 0.001, "20 m/s")
	check_eq(bolt.pierce, 0, "single target")
	for i in 60:
		if is_instance_valid(bolt) and not bolt.is_done():
			bolt.advance(DT)
	check_eq(e.fake_hits(), 1, "the bolt hit")
	check_near(e.fake_damage_log[0], _w() * 0.2, 0.001, "for pet damage")
	check_eq(e.fake_attacker_log[0], hunter, "credited to the Hunter")
	check(not e.fake_crit_log[0], "no crit")
	check(pet.global_position.distance_to(start) < 0.5, "it did not move towards the enemy")


func test_owl_shoots_every_six_tenths_of_a_second_at_enemies_within_eight_metres() -> void:
	var pet := _pet(&"owl")
	_enemy(Vector3(0, 0, -12))
	_step(pet, 2.0)
	check_eq(pet.attacks, 0, "12 m is out of reach")
	var e := _enemy(Vector3(0, 0, -6))
	_step(pet, 3.05)
	check(pet.attacks >= 4 and pet.attacks <= 6, "about 5 shots in 3 s (%d)" % pet.attacks)
	check(e.fake_hits() == 0, "(the bolts are still in the air: nobody advanced them)")


# --- Rules ------------------------------------------------------------------------------------

func test_companion_hides_while_the_hunter_is_down_and_comes_back() -> void:
	var pet := _pet(&"wolf")
	var e := _enemy(Vector3(1.5, 0, 0))
	_step(pet, 0.3)
	hunter.downed = true
	_step(pet, DT)
	check(pet.is_hidden() and not pet.visible, "hidden")
	var hits := e.fake_hits()
	_step(pet, 3.0)
	check_eq(e.fake_hits(), hits, "and it does not attack")
	_mastery().tick(DT)
	check(_mastery().companion == pet, "no second companion is summoned")
	hunter.downed = false
	_step(pet, DT)
	check(not pet.is_hidden() and pet.visible, "back with the revive")
	check_near(pet.global_position.distance_to(hunter.global_position), HunterCompanion.FOLLOW_DISTANCE, 0.2, "beside the Hunter")


func test_companion_snaps_to_the_hunter_at_wave_start_and_when_far_away() -> void:
	var pet := _pet(&"wolf")
	hunter.global_position = Vector3(40, 0, 0)
	hunter.begin_wave()
	check_near(pet.global_position.distance_to(hunter.global_position), HunterCompanion.FOLLOW_DISTANCE, 0.2, "snapped at the wave start")
	pet.global_position = hunter.global_position + Vector3(20, 0, 0)
	_step(pet, DT * 2.0)
	check(pet.global_position.distance_to(hunter.global_position) < 3.0, "teleported home beyond 14 m")


func test_companion_follows_the_hunter() -> void:
	var pet := _pet(&"wolf")
	hunter.global_position = Vector3(6, 0, 0)
	_step(pet, 1.5)
	check(pet.global_position.distance_to(hunter.global_position) < 2.0, "it stays beside the Hunter")


func test_companion_is_freed_on_teardown_and_survives_waves() -> void:
	var pet := _pet(&"wolf")
	hunter.begin_wave()
	hunter.end_wave()
	check(is_instance_valid(pet) and not pet.is_queued_for_deletion(), "it survives waves")
	check(_mastery().companion == pet, "the Mastery keeps it")
	hunter.abilities.teardown()
	check(pet.is_queued_for_deletion(), "freed in teardown")
	check(not _mastery().has_companion(), "and forgotten")


func test_mastery_summons_lazily_from_its_tick_and_only_for_a_living_hunter() -> void:
	var m := _mastery()
	check(not m.has_companion(), "none at the start")
	hunter.downed = true
	m.tick(DT)
	check(not m.has_companion(), "no summon while down")
	hunter.downed = false
	m.tick(DT)
	check(m.has_companion(), "summoned by the first tick of a living Hunter")
	check_eq(m.companion.kind, &"wolf", "the Wolf")
	check(m.companion.get_parent() == world, "under the effects parent")


func test_the_pet_source_is_the_only_one_the_companion_uses() -> void:
	# deal_raw's source decides which Mastery multiplier applies: probe it with a Mastery of 10.
	hunter.stats.set_source(&"mastery_test", {Stats.MASTERY: 10.0})
	var pet := _pet(&"wolf")
	var e := _enemy(Vector3(1.2, 0, 0))
	_step(pet, 0.5)
	var as_pet: float = e.fake_damage_log[0]
	var direct := hunter.procs.deal_raw(e, pet.hit_damage(38.0), &"physical", true, &"ability")
	check_near(as_pet / direct, 1.2, 0.0001, "the companion's bite carries Beastbond, an ability hit does not")


# --- Hunt Signal -----------------------------------------------------------------------------

func test_hunt_signal_needs_a_companion_that_is_out() -> void:
	var slot := _learn(&"hunt_signal")
	_enemy(Vector3(0, 0, -5))
	check(not hunter.abilities.try_cast(slot), "no companion yet: refused")
	var pet := _pet(&"wolf")
	hunter.downed = true
	_step(pet, DT)
	hunter.downed = false
	check(not hunter.abilities.try_cast(slot), "a hidden companion: refused")
	_step(pet, DT)
	check(hunter.abilities.try_cast(slot), "with the companion out: cast")
	check_near(hunter.abilities.remaining(slot), 10.0, 0.001, "10 s cooldown")


func test_hunt_signal_picks_the_strongest_enemy() -> void:
	var pet := _pet(&"wolf")
	var weak := _enemy(Vector3(2, 0, 0))
	var big := _enemy(Vector3(-4, 0, 0))
	big.max_hp = 3000.0
	big.hp = 3000.0
	var near_big := _enemy(Vector3(0, 0, -3))
	near_big.max_hp = 3000.0
	near_big.hp = 3000.0
	var far := _enemy(Vector3(12, 0, 0))
	far.max_hp = 99999.0
	var picked := HunterHuntSignal.strongest(hunter, pet.global_position, 10.0, 1)
	check_eq(picked.size(), 1, "one asked")
	check(picked[0] == big or picked[0] == near_big, "the most Max HP wins among the others")
	var d_big := GeneralKit.flat_distance(big.global_position, pet.global_position)
	var d_near := GeneralKit.flat_distance(near_big.global_position, pet.global_position)
	check(picked[0] == (big if d_big < d_near else near_big), "ties: the nearer to the companion")
	check(weak not in picked and far not in picked, "weaker and out-of-range enemies are not")
	var boss := _enemy(Vector3(5, 0, 5))
	boss.fake_boss = true
	boss.max_hp = 100.0
	boss.hp = 100.0
	picked = HunterHuntSignal.strongest(hunter, pet.global_position, 10.0, 2)
	check(picked[0] == boss, "a boss beats any amount of health")
	check_eq(picked.size(), 2, "two asked: the next-strongest follows")
	check(picked[1] == big or picked[1] == near_big, "the strongest of the rest")


func test_hunt_signal_prefers_elites_over_health() -> void:
	var pet := _pet(&"wolf")
	var plain := _enemy(Vector3(3, 0, 0))
	plain.max_hp = 9000.0
	plain.hp = 9000.0
	var elite := _enemy(Vector3(-3, 0, 0))
	elite.elite_affix = &"swift"
	elite.max_hp = 100.0
	elite.hp = 100.0
	var picked := HunterHuntSignal.strongest(hunter, pet.global_position, 10.0, 1)
	check(picked[0] == elite, "an elite beats more health")
	check(plain not in picked, "")


func test_hunt_signal_the_wolf_leaps_in_strikes_and_slows() -> void:
	hunter.stats.set_source(&"mastery_test", {Stats.MASTERY: 10.0})
	var slot := _learn(&"hunt_signal")
	var pet := _pet(&"wolf")
	var e := _enemy(Vector3(0, 0, -7))
	check(hunter.abilities.try_cast(slot), "cast")
	check(pet.is_signalling(), "the companion is on its way")
	_step(pet, 1.0)
	check(not pet.is_signalling(), "the blow landed")
	check_eq(pet.signal_strikes, 1, "one blow")
	check_near(e.fake_damage_log[0], _w() * 2.5 * 1.2, 0.001, "250% W x Beastbond (pet damage)")
	check_eq(e.fake_attacker_log[0], hunter, "credited to the Hunter")
	check(not e.fake_crit_log[0], "no crit")
	check_eq(e.slow_pct, 50.0, "Wolf: 50% slow")
	check_near(e.slow_left, 2.0, 0.1, "for 2 s")


func test_hunt_signal_the_boar_stuns_and_the_owl_adds_damage() -> void:
	var slot := _learn(&"hunt_signal")
	var pet := _pet(&"boar")
	var e := _enemy(Vector3(0, 0, -7))
	pet._charge_left = 99.0
	hunter.abilities.try_cast(slot)
	_step(pet, 1.0)
	check_eq(e.fake_stun_count, 1, "Boar: stunned")
	check_near(e.fake_damage_log[0], _w() * 2.5, 0.001, "250% W")
	hunter.abilities.set_cooldown(Db.get_ability(&"hunt_signal"), 0.0)
	e.fake_damage_log.clear()
	var owl := _pet(&"owl")
	hunter.abilities.try_cast(slot)
	_step(owl, 1.0)
	check_near(e.fake_damage_log[0], _w() * 2.5 * 1.25, 0.001, "Owl: 25% more damage")


func test_hunt_signal_rank_three_strikes_the_next_strongest_too() -> void:
	var slot := _learn(&"hunt_signal", 3)
	var pet := _pet(&"wolf")
	var a := _enemy(Vector3(0, 0, -6))
	a.max_hp = 2000.0
	a.hp = 2000.0
	var b := _enemy(Vector3(5, 0, -3))
	b.max_hp = 1500.0
	b.hp = 1500.0
	var c := _enemy(Vector3(-5, 0, 0))
	hunter.abilities.try_cast(slot)
	_step(pet, 2.0)
	check_eq(pet.signal_strikes, 2, "two blows")
	var blow := _w() * 2.5 * float(hunter.abilities.params_for(Db.get_ability(&"hunt_signal"))["power"])
	check_near(a.fake_damage_log[0], blow, 0.001, "the strongest takes the first blow")
	check_near(b.fake_damage_log[0], blow, 0.001, "and the next-strongest the second")
	check_eq(c.fake_hits(), 0, "not the weakest (the companion moved on to bite near b)")


func test_hunt_signal_mauling_rush_splashes() -> void:
	var slot := _learn(&"hunt_signal", 5, 0)
	var pet := _pet(&"wolf")
	var main := _enemy(Vector3(0, 0, -6))
	main.max_hp = 3000.0
	main.hp = 3000.0
	var near := _enemy(Vector3(1.8, 0, -6))
	var far := _enemy(Vector3(6, 0, -6))
	var power := float(hunter.abilities.params_for(Db.get_ability(&"hunt_signal"))["power"])
	hunter.abilities.try_cast(slot)
	_step(pet, 2.0)
	check_near(main.fake_damage_log[0], _w() * 2.5 * power, 0.001, "the blow")
	check_near(near.fake_damage_log[0], _w() * 2.5 * power * 0.6, 0.001, "60% to an enemy within 2.5 m")
	check_eq(far.fake_hits(), 0, "none further out")


func test_hunt_signal_open_wound_bleeds_as_pet_damage() -> void:
	_mods([{"kind": "ability", "match": {"id": "hunt_signal"}, "mods": {"bleed_pct_add": 80.0}}])
	hunter.stats.set_source(&"mastery_test", {Stats.MASTERY: 10.0})
	var slot := _learn(&"hunt_signal")
	var pet := _pet(&"wolf")
	var e := _enemy(Vector3(0, 0, -6))
	hunter.abilities.try_cast(slot)
	_step(pet, 1.0)
	var bleed := HunterBleed.find(e, hunter, &"hunt_signal")
	check(bleed != null, "a wound")
	if bleed == null:
		return
	check_eq(bleed.source, &"pet", "pet damage")
	var blow: float = _w() * 2.5
	check_near(bleed.remaining(), blow * 0.8, 0.001, "80% of the blow over 4 s")
	var before := e.fake_hits()
	for i in 4 * 60 + 10:
		bleed._physics_process(DT)
	var dealt := 0.0
	for i in range(before, e.fake_hits()):
		dealt += e.fake_damage_log[i]
	check_near(dealt, blow * 0.8 * 1.2, 0.01, "Beastbond applies to the ticks")


func test_hunt_signal_relentless_pursuit_brings_it_back_after_a_kill() -> void:
	var slot := _learn(&"hunt_signal", 5, 1)
	var pet := _pet(&"wolf")
	var weak := MortalEnemy.new()
	weak.add_to_group(&"enemies")
	world.add_child(weak)
	weak.global_position = Vector3(0, 0, -6)
	weak.hp = 5.0
	weak.max_hp = 5.0
	EnemyGrid.mark_dirty()
	hunter.abilities.try_cast(slot)
	var ability := Db.get_ability(&"hunt_signal")
	check(hunter.abilities.cooldown_left(ability) > 5.0, "on cooldown")
	_step(pet, 1.0)
	check(weak.is_dead(), "the blow killed it")
	check(hunter.abilities.cooldown_left(ability) <= 2.0 + 0.001, "a kill brings it back after 2 s")
	# A blow that does not kill leaves the cooldown alone.
	hunter.abilities.set_cooldown(ability, 9.0)
	var tough := _enemy(Vector3(0, 0, -6))
	hunter.abilities.set_cooldown(ability, 0.0)
	hunter.abilities.try_cast(slot)
	_step(pet, 1.0)
	check(hunter.abilities.cooldown_left(ability) > 5.0, "no kill, no reset")
	check(tough.fake_hits() >= 1, "(the blow landed)")


func test_hunt_signal_auto_cast_rule() -> void:
	var slot := _learn(&"hunt_signal")
	var effect := HunterKit.effect_of(hunter, &"hunt_signal") as HunterHuntSignal
	var ability := Db.get_ability(&"hunt_signal")
	_enemy(Vector3(0, 0, -5))
	check(not effect.wants_auto_cast(hunter.abilities.build_context(ability)), "no companion")
	var pet := _pet(&"wolf")
	check(not effect.wants_auto_cast(hunter.abilities.build_context(ability)), "one plain enemy")
	_enemy(Vector3(3, 0, 0))
	check(not effect.wants_auto_cast(hunter.abilities.build_context(ability)), "two enemies")
	_enemy(Vector3(-3, 0, 0))
	check(effect.wants_auto_cast(hunter.abilities.build_context(ability)), "three within 8 m")
	for e in tree.get_nodes_in_group(&"enemies"):
		e.free()
	EnemyGrid.mark_dirty()
	var boss := _enemy(Vector3(0, 0, -9))
	boss.fake_boss = true
	check(effect.wants_auto_cast(hunter.abilities.build_context(ability)), "a boss within 10 m")
	hunter.abilities.try_cast(slot)
	check(pet.is_signalling(), "dashing")
	hunter.abilities.set_cooldown(ability, 0.0)
	check(not effect.wants_auto_cast(hunter.abilities.build_context(ability)), "not while the companion is out")
