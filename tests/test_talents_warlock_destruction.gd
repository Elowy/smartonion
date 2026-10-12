extends TestCase
## Warlock Destruction talents (M5 Wave 2, talents_warlock.md §3) through player.talents.add ->
## PlayerBonuses on a real Warlock: Devastation, Emberstorm, Fire and Brimstone, Aftermath
## (Rain of Fire's new neutral "slow" param), Soul Leech (on_crit drain), the Shadowburn
## modifier (Drain Life's new neutral shadowburn_* params: scorch on a completed channel, a
## Soul Shard for a kill inside the window, the shard cooldown, interrupted channels, going
## down), Ruin, Burning Embers (start_value_add) and the Conflagrate capstone (Rain of Fire's
## ember_* params and WarlockEmbers; the on_crit Soul Shard proc). Bot paths:
## test_talents_warlock.gd.

const Fakes := preload("res://tests/player_fakes.gd")
const EFakes := preload("res://tests/enemies_fakes.gd")
const WFakes := preload("res://tests/talents_warlock_fakes.gd")
const DT := 1.0 / 60.0
const RT := 0
const LT := 1

var world: Node3D


func before_each() -> void:
	RunState.start_run(1, 2024)
	RunState.set_start_level(31)
	world = EFakes.make_world(tree)
	EnemyGrid.mark_dirty()


func after_each() -> void:
	EFakes.free_world(tree, world)
	world = null
	EnemyGrid.mark_dirty()


func _warlock(pos: Vector3 = Vector3.ZERO, index: int = 0) -> Player:
	return Fakes.spawn_player(world, index, &"warlock", pos)


func _enemy(pos: Vector3, hp: float = 1000.0) -> WFakes.DyingEnemy:
	return WFakes.spawn_enemy(world, pos, hp)


func _add(p: Player, name: String, n: int = 1) -> void:
	var id := StringName("warlock_destruction_" + name)
	for i in n:
		check(p.talents.add(id), "add %s: %s" % [id, p.talents.add_block_reason(id)])


func _remove(p: Player, name: String, n: int = 1) -> void:
	var id := StringName("warlock_destruction_" + name)
	for i in n:
		check(p.talents.remove(id), "remove %s: %s" % [id, p.talents.remove_block_reason(id)])


func _rain(p: Player) -> WarlockRainOfFire:
	return p.abilities.effect_for(Db.get_ability(&"rain_of_fire")) as WarlockRainOfFire


func _drain(p: Player) -> WarlockDrainLife:
	return p.abilities.effect_for(Db.get_ability(&"drain_life")) as WarlockDrainLife


func _cluster() -> Array[WFakes.DyingEnemy]:
	var out: Array[WFakes.DyingEnemy] = []
	for i in 4:
		out.append(_enemy(Vector3(6.0 + 0.6 * i, 0, 0.5 * (i % 2))))
	return out


func _areas() -> Array[AbilityArea]:
	var out: Array[AbilityArea] = []
	for node in tree.get_nodes_in_group(&"ability_areas"):
		var a := node as AbilityArea
		if a != null and not a.is_queued_for_deletion():
			out.append(a)
	return out


## Steps an area and its WarlockEmbers child (if any) frame by frame, like the scene tree.
func _step_area(area: AbilityArea, seconds: float) -> void:
	var embers := area.get_node_or_null("Embers")
	var t := 0.0
	while t < seconds - 0.00001:
		area._physics_process(DT)
		if embers != null:
			embers._physics_process(DT)
		t += DT


## The 12 points that open Conflagrate without Aftermath (so the embers' own slow shows).
func _to_capstone(p: Player) -> void:
	_add(p, "devastation", 3)
	_add(p, "emberstorm", 3)
	_add(p, "fire_and_brimstone", 3)
	_add(p, "soul_leech", 2)
	_add(p, "shadowburn")
	_add(p, "conflagrate")


# --- Tier 1-4 ----------------------------------------------------------------------------------

func test_devastation_and_ruin_crit() -> void:
	var p := _warlock()
	var crit := p.stats.get_raw(Stats.CRIT)
	var crit_damage := p.stats.get_raw(Stats.CRIT_DAMAGE)
	_add(p, "devastation", 2)
	check_eq(p.stats.get_raw(Stats.CRIT), crit + 4.0, "+2% crit per rank")
	_add(p, "emberstorm", 3)
	_add(p, "fire_and_brimstone", 3)
	_add(p, "aftermath")
	check_eq(p.talents.add_block_reason(&"warlock_destruction_ruin"), "Requires Devastation", "prerequisite")
	_add(p, "devastation")
	_add(p, "ruin", 3)
	check_eq(p.stats.get_raw(Stats.CRIT), crit + 6.0, "rank 3")
	check_eq(p.stats.get_raw(Stats.CRIT_DAMAGE), crit_damage + 30.0, "+10% crit damage per rank")
	_remove(p, "ruin", 3)
	check_eq(p.stats.get_raw(Stats.CRIT_DAMAGE), crit_damage, "undone")


func test_emberstorm_fire_damage() -> void:
	var p := _warlock()
	_add(p, "emberstorm", 3)
	check_near(p.outgoing_damage_mult(null, &"fire", &"weapon"), 1.09, 0.0001, "the staff (Fire)")
	check_near(p.outgoing_damage_mult(null, &"fire", &"ability"), 1.09, 0.0001, "Rain of Fire")
	check_near(p.outgoing_damage_mult(null, &"fire", &"pet"), 1.09, 0.0001, "the Imp")
	check_near(p.outgoing_damage_mult(null, &"arcane", &"weapon"), 1.0, 0.0001, "not a wand's Arcane")
	_remove(p, "emberstorm", 3)
	check_near(p.outgoing_damage_mult(null, &"fire", &"weapon"), 1.0, 0.0001, "undone")


func test_fire_and_brimstone_scales_power_and_radius_after_the_rank() -> void:
	var p := _warlock()
	var rain := Db.get_ability(&"rain_of_fire")
	var base := p.abilities.params_for(rain)
	_add(p, "devastation", 3)
	_add(p, "fire_and_brimstone", 3)
	var params := p.abilities.params_for(rain)
	check_near(float(params["power"]), 1.12, 0.0001, "+4% damage per rank")
	check_near(float(params["radius"]), float(base["radius"]) * 1.06, 0.0001, "+2% radius per rank")
	p.abilities.rank_up(&"rain_of_fire")
	p.abilities.rank_up(&"rain_of_fire")
	check_near(float(p.abilities.params_for(rain)["radius"]), (float(base["radius"]) + 1.0) * 1.06, 0.0001,
		"after Rank III's +1 m")
	_remove(p, "fire_and_brimstone", 3)
	check_near(float(p.abilities.params_for(rain)["radius"]), float(base["radius"]) + 1.0, 0.0001, "undone")


func test_aftermath_slows_inside_rain_of_fire() -> void:
	var p := _warlock()
	var inside := _cluster()
	var rain := Db.get_ability(&"rain_of_fire")
	check_eq(p.abilities.params_for(rain)["slow"], 0.0, "neutral: no slow")
	_add(p, "devastation", 3)
	_add(p, "aftermath", 3)
	check_eq(p.abilities.params_for(rain)["slow"], 30.0, "+10% per rank")
	WFakes.shards(p).set_value(1.0)
	check(p.abilities.try_cast(RT), "cast")
	var area := _areas()[0]
	check_eq(area.slow_pct, 30.0, "the circle slows 30%")
	area._physics_process(DT)
	for e in inside:
		check(e.is_slowed() and e.slow_pct == 30.0, "an enemy inside is slowed")


func test_soul_leech_drains_a_share_of_every_crit() -> void:
	var p := _warlock()
	_add(p, "devastation", 3)
	_add(p, "emberstorm", 3)
	_add(p, "soul_leech", 2)
	var e := _enemy(Vector3(3, 0, 0))
	p.hp = 2.0
	var state := RunState.rng.state
	p.on_hit_dealt(12.0, e, p.main_hand, false, false, true, 10.0)
	check(e.hits.is_empty(), "no crit: nothing")
	p.on_hit_dealt(12.0, e, p.main_hand, true, false, true, 10.0)
	check_eq(e.hits.size(), 1, "a crit drains")
	var expected := 10.0 * 0.4 * p.outgoing_damage_mult(e, &"shadow", &"proc")
	check_near(e.hits[0], expected, 0.0001, "40% of the crit's base amount as Shadow")
	check_near(p.hp, 2.0 + expected, 0.0001, "healing the Warlock for it")
	check_eq(RunState.rng.state, state, "a 100% proc draws nothing")
	_remove(p, "soul_leech", 2)
	p.on_hit_dealt(12.0, e, p.main_hand, true, false, true, 10.0)
	check_eq(e.hits.size(), 1, "undone")


func test_burning_embers_start_shards() -> void:
	var p := _warlock()
	var res := WFakes.shards(p)
	_add(p, "devastation", 3)
	_add(p, "emberstorm", 3)
	_add(p, "fire_and_brimstone", 3)
	for rank in range(1, 4):
		_add(p, "burning_embers")
		p.begin_wave()
		check_eq(res.value, 1.0 + rank, "%d shards at wave start" % (1 + rank))
	check_eq(res.bonus, {"start_value_add": 3.0}, "ClassResource.set_bonus")
	RunState.add_gold(500)
	check(p.talents.try_reset(0), "Reset Talents")
	p.begin_wave()
	check_eq(res.value, 1.0, "undone")


# --- Shadowburn --------------------------------------------------------------------------------

func test_shadowburn_scorches_a_completed_channel_and_pays_a_shard() -> void:
	var p := _warlock()
	var drain := Db.get_ability(&"drain_life")
	check_eq(p.abilities.params_for(drain)["shadowburn_pct"], 0.0, "neutral")
	_add(p, "devastation", 3)
	_add(p, "emberstorm", 3)
	_add(p, "shadowburn")
	var params := p.abilities.params_for(drain)
	check_eq(params["shadowburn_pct"], 75.0, "shadowburn_pct 0 -> 75")
	var effect := _drain(p)
	var res := WFakes.shards(p)
	res.set_value(1.0)
	var a := _enemy(Vector3(2, 0, 0))
	var per_tick := WarlockDrainLife.tick_damage(p.stats, params)
	var state := RunState.rng.state
	check(p.abilities.try_cast(LT), "cast")
	WFakes.step_abilities(p, 2.1)
	check(not effect.is_channeling(), "completed")
	check_eq(a.hits.size(), 6, "5 ticks + the scorch")
	check_near(a.hits[5], per_tick * 5.0 * 0.75 * p.outgoing_damage_mult(a, &"shadow", &"ability"), 0.001,
		"75% of the channel's damage at once")
	check_eq(effect.scorches, 1, "one scorch")
	check(effect.is_watched(a), "watched for the shard")
	a.take_damage(5000.0, false, null)
	check_eq(res.value, 2.0, "it died within 3 sec: +1 Soul Shard")
	check_near(effect.shard_cooldown, 10.0, 0.0001, "at most once every 10 sec")
	check_eq(effect.shadowburn_shards, 1, "stats")
	p.abilities.set_cooldown(drain, 0.0)
	var b := _enemy(Vector3(2, 0, 1))
	check(p.abilities.try_cast(LT), "cast again")
	WFakes.step_abilities(p, 2.1)
	check_eq(b.hits.size(), 6, "scorched")
	b.take_damage(5000.0, false, null)
	check_eq(res.value, 2.0, "within the shard cooldown: no shard")
	check_eq(RunState.rng.state, state, "no RNG")


func test_shadowburn_window_interrupts_scorch_kills_and_going_down() -> void:
	var p := _warlock()
	_add(p, "devastation", 3)
	_add(p, "emberstorm", 3)
	_add(p, "shadowburn")
	var drain := Db.get_ability(&"drain_life")
	var effect := _drain(p)
	var res := WFakes.shards(p)
	var params := p.abilities.params_for(drain)
	var per_tick := WarlockDrainLife.tick_damage(p.stats, params)
	# The window runs out.
	var c := _enemy(Vector3(2, 0, 0))
	check(p.abilities.try_cast(LT), "cast")
	WFakes.step_abilities(p, 2.1)
	check(effect.is_watched(c), "watched after the channel")
	WFakes.step_abilities(p, 3.1)
	check(not effect.is_watched(c), "3 sec later: not any more")
	var before := res.value
	c.take_damage(5000.0, false, null)
	check_eq(res.value, before, "a late death pays nothing")
	# An interrupted channel scorches nothing.
	p.begin_wave()
	var d := _enemy(Vector3(2, 0, 0))
	check(p.abilities.try_cast(LT), "cast")
	WFakes.step_abilities(p, 0.5)
	d.global_position = Vector3(40, 0, 0)
	EnemyGrid.mark_dirty()
	WFakes.step_abilities(p, 2.0)
	check(not effect.is_channeling(), "ended early")
	check_eq(d.hits.size(), 1, "one tick, no scorch")
	check_eq(effect.scorches, 0, "nothing scorched")
	# The scorch itself kills: still a shard.
	p.begin_wave()
	d.global_position = Vector3(40, 0, 0)
	var f := _enemy(Vector3(2, 0, 0), per_tick * 5.5)
	res.set_value(1.0)
	check(p.abilities.try_cast(LT), "cast")
	WFakes.step_abilities(p, 2.1)
	check(f.is_dead(), "the scorch killed it")
	check_eq(res.value, 2.0, "+1 Soul Shard")
	# Going down clears the watch.
	p.begin_wave()
	var g := _enemy(Vector3(2, 0, 0))
	check(p.abilities.try_cast(LT), "cast")
	WFakes.step_abilities(p, 2.1)
	check(effect.is_watched(g), "watched before going down")
	p._go_down()
	check(not effect.is_watched(g), "going down clears the watch")
	g.die_now(null)
	p.begin_wave()
	var h := _enemy(Vector3(2, 0, 0))
	check(p.abilities.try_cast(LT), "cast")
	WFakes.step_abilities(p, 2.1)
	check(effect.is_watched(h), "watched before the wave end")
	p.end_wave()
	check(not effect.is_watched(h), "the wave end clears it too")


# --- Conflagrate -------------------------------------------------------------------------------

func test_conflagrate_leaves_burning_ground() -> void:
	var p := _warlock()
	var inside := _cluster()
	_to_capstone(p)
	var rain := Db.get_ability(&"rain_of_fire")
	var params := p.abilities.params_for(rain)
	check_eq(params["ember_duration"], 3.0, "ember_duration 0 -> 3")
	WFakes.shards(p).set_value(2.0)
	check(p.abilities.try_cast(RT), "cast")
	var areas := _areas()
	check_eq(areas.size(), 1, "one circle")
	var area := areas[0]
	check_near(area.duration, 7.0, 0.0001, "4 sec of rain + 3 sec of burning ground")
	var embers := area.get_node_or_null("Embers") as WarlockEmbers
	check(embers != null, "the embers ride along")
	var vfx := area.get_node_or_null("RainOfFireVfx") as WarlockRainOfFireVfx
	check_near(vfx.duration, 4.0, 0.0001, "meteors only for the rain")
	var tick := area.damage_per_tick
	check_eq(area.slow_pct, 0.0, "no slow while it rains (no Aftermath)")
	var effect := _rain(p)
	var ctx := p.abilities.build_context(rain)
	check(not effect.wants_auto_cast(ctx), "bots do not rain on a running rain")
	_step_area(area, 3.95)
	check(not embers.burning, "still raining at 3.95 sec")
	_step_area(area, 0.1)
	check(embers.burning, "the rain is over: the ground burns")
	check_near(area.damage_per_tick, tick * 0.4, 0.0001, "40% of the rain's ticks")
	check(area.slow_pct >= 30.0, "slows 30%")
	check(area.follow == null, "stays where it is")
	check(area.has_meta(WarlockEmbers.META), "marked")
	check(area.get_node_or_null("EmberVfx") != null, "the ember look")
	check(effect.wants_auto_cast(p.abilities.build_context(rain)), "bots rain again on the burning group")
	_step_area(area, 3.1)
	var e := inside[0]
	check_eq(e.hits.size(), 14, "8 rain ticks + 6 ember ticks")
	check_near(e.total(), (tick * 8.0 + tick * 0.4 * 6.0) * p.outgoing_damage_mult(e, &"fire", &"ability"), 0.01,
		"+30% damage per cast")
	check(e.is_slowed(), "slowed by the embers")
	check(area.is_queued_for_deletion(), "gone after 7 sec")


func test_conflagrate_walking_inferno_and_crit_shards() -> void:
	var p := _warlock()
	_cluster()
	_to_capstone(p)
	for i in 4:
		p.abilities.rank_up(&"rain_of_fire")
	p.abilities.set_spec(&"rain_of_fire", 0)
	WFakes.shards(p).set_value(2.0)
	check(p.abilities.try_cast(RT), "Walking Inferno cast")
	var area := _areas()[0]
	check(area.follow == p, "follows the Warlock while it rains")
	check_near(area.duration, 8.0, 0.0001, "5 + 3 sec")
	_step_area(area, 5.05)
	check(area.follow == null, "the burning ground stays behind")
	# The on_crit Soul Shard proc: 10% per weapon crit, RunState.rng only.
	var e := _enemy(Vector3(-3, 0, 0))
	var res := WFakes.shards(p)
	RunState.rng.seed = 99
	var replay := RandomNumberGenerator.new()
	replay.seed = 99
	replay.state = RunState.rng.state
	var expected := 0
	for i in 60:
		if replay.randf() < 0.1:
			expected += 1
	var got := 0
	for i in 60:
		res.set_value(0.0)
		p.on_hit_dealt(12.0, e, p.main_hand, true, false, true, 10.0)
		got += int(res.value)
	check(expected > 0, "the seed rolls some shards")
	check_eq(got, expected, "one draw per crit, a shard below 10%")
	check_eq(p.procs.fire_count(&"warlock_destruction_conflagrate"), expected, "the proc fired that often")
	var no_crit := RunState.rng.state
	res.set_value(0.0)
	p.on_hit_dealt(12.0, e, p.main_hand, false, false, true, 10.0)
	check_eq(RunState.rng.state, no_crit, "no roll without a crit")
	check_eq(res.value, 0.0, "no shard")
