extends TestCase
## Elites (M5, GDD 8, architecture §2.5): EliteAffixes (count, schedule, affix), the
## WaveDirector turning the first enemies of the next group elite, Enemy.make_elite (HP, size,
## the four affixes), elite rewards (keyed on elite_affix, not is_elite), Slayer and the
## ElitePlate nameplate.

const EFakes := preload("res://tests/enemies_fakes.gd")
const PFakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0

var world: Node3D
var _special: Array = []


## A hero for the Vampiric tests: records hits like EFakes.FakePlayer and, like a real Player,
## reports landed damage through damage_taken.
class EmittingHero extends EFakes.FakePlayer:
	func take_damage(raw: float, kind: StringName = CombatMath.KIND_MELEE, source: Node3D = null) -> void:
		super.take_damage(raw, kind, source)
		damage_taken.emit(raw, source)


## An enemy that claims to be elite (like the Loot Goblin) without an affix.
class ClaimsElite extends Enemy:
	func is_elite() -> bool:
		return true


func before_each() -> void:
	RunState.start_run(1, 4242)
	RunState.set_wave(6)
	world = EFakes.make_world(tree)
	_special.clear()
	RunState.special_killed.connect(_on_special_killed)


func after_each() -> void:
	if RunState.special_killed.is_connected(_on_special_killed):
		RunState.special_killed.disconnect(_on_special_killed)
	EFakes.free_world(tree, world)
	world = null
	EliteAffixes.rate_mult = 1.0
	PlayerManager.clear()
	Enemy.invalidate_player_cache()


func _on_special_killed(kind: StringName, killer_index: int) -> void:
	_special.append([kind, killer_index])


func _entities() -> Node3D:
	return EFakes.arena_of(world).entities


## An elite of [param affix] built like the WaveDirector does (make_elite before add_child).
func _elite(affix: StringName, pos: Vector3 = Vector3.ZERO, data: EnemyData = null, p_wave: int = 3) -> Enemy:
	var e := Enemy.create(data if data != null else EFakes.enemy_data(), p_wave)
	e.make_elite(affix)
	_entities().add_child(e)
	e.global_position = pos
	return e


func _of_type(script_class: GDScript) -> Array[Node]:
	return EFakes.live_children_of_type(world, script_class)


func _enemies() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for node in tree.get_nodes_in_group(&"enemies"):
		var e := node as Enemy
		if e != null:
			out.append(e)
	return out


# --- EliteAffixes: count, schedule, affix ----------------------------------------------------

func test_expected_count_formula() -> void:
	for n in range(1, 5):
		check_eq(EliteAffixes.expected_count(4, n), 0.0, "wave 4, %d player(s): none" % n)
		check_eq(EliteAffixes.expected_count(1, n), 0.0, "wave 1: none")
	check_near(EliteAffixes.expected_count(5, 1), 0.4, 0.00001, "solo wave 5")
	check_near(EliteAffixes.expected_count(15, 1), 1.0, 0.00001, "solo wave 15")
	check_near(EliteAffixes.expected_count(25, 1), 1.6, 0.00001, "solo wave 25")
	var party: Array[float] = [1.0, 1.35, 1.7, 2.05]
	for n in range(1, 5):
		for w in [5, 15, 25]:
			var solo: float = 0.4 + 0.06 * (w - 5)
			check_near(EliteAffixes.expected_count(w, n), solo * party[n - 1], 0.00001,
					"wave %d, %d player(s)" % [w, n])
	check_near(EliteAffixes.expected_count(25, 4), 3.28, 0.00001, "4 players x2.05")
	EliteAffixes.rate_mult = 2.5
	check_near(EliteAffixes.expected_count(15, 1), 2.5, 0.00001, "--elite-mult multiplies")
	check_eq(EliteAffixes.expected_count(4, 4), 0.0, "still none below FIRST_WAVE")
	EliteAffixes.rate_mult = 0.0
	check_eq(EliteAffixes.expected_count(25, 4), 0.0, "--elite-mult=0: none")


func test_roll_count_draws_once_and_follows_the_fraction() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var state := rng.state
	check_eq(EliteAffixes.roll_count(4, 4, rng), 0, "below FIRST_WAVE")
	check_eq(rng.state, state, "no draw below FIRST_WAVE (waves 1-4 roll what they rolled before M5)")
	EliteAffixes.rate_mult = 0.0
	check_eq(EliteAffixes.roll_count(20, 4, rng), 0, "rate 0")
	check_eq(rng.state, state, "no draw with rate 0")
	EliteAffixes.rate_mult = 1.0
	# A whole expected count: always exactly that many, one draw each time.
	var probe := RandomNumberGenerator.new()
	probe.seed = 11
	for _i in 50:
		check_eq(EliteAffixes.roll_count(15, 1, rng), 1, "wave 15 solo: exactly one")
		probe.randf()
	check_eq(rng.state, probe.state, "one draw per roll")
	# Fractions: the chance of one more.
	var ones := 0
	for _i in 4000:
		var c := EliteAffixes.roll_count(5, 1, rng)
		check(c == 0 or c == 1, "wave 5 solo: 0 or 1")
		ones += c
	check_near(float(ones) / 4000.0, 0.4, 0.03, "wave 5 solo: 40% one elite")
	var fours := 0
	for _i in 4000:
		var c := EliteAffixes.roll_count(25, 4, rng)
		check(c == 3 or c == 4, "wave 25, 4 players: 3 or 4")
		if c == 4:
			fours += 1
	check_near(float(fours) / 4000.0, 0.28, 0.03, "3.28 -> 28% a fourth")


func test_schedule_window_sorted_and_deterministic() -> void:
	EliteAffixes.rate_mult = 4.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var start := rng.state
	var times := EliteAffixes.schedule(12, 50.0, 3, rng)
	var after := rng.state
	rng.state = start
	var count := EliteAffixes.roll_count(12, 3, rng)
	check_eq(times.size(), count, "one time per elite of roll_count")
	check(times.size() >= 5, "rate 4 at wave 12 with 3 players: many elites (%d)" % times.size())
	for _i in count:
		rng.randf()
	check_eq(rng.state, after, "draws: the count, then one per elite")
	for i in times.size():
		check(times[i] >= 0.15 * 50.0 - 0.0001 and times[i] <= 0.7 * 50.0 + 0.0001,
				"time %.2f inside 15-70%% of the wave" % times[i])
		if i > 0:
			check(times[i] >= times[i - 1], "sorted")
	rng.state = start
	check_eq(EliteAffixes.schedule(12, 50.0, 3, rng), times, "same seed, same schedule")
	check(EliteAffixes.schedule(3, 50.0, 4, rng).is_empty(), "nothing before wave 5")
	# Many schedules: every time inside the window, and the window is used end to end.
	var lo := INF
	var hi := -INF
	var outside := 0
	for _i in 300:
		for t in EliteAffixes.schedule(12, 50.0, 3, rng):
			lo = minf(lo, t)
			hi = maxf(hi, t)
			if t < 7.5 - 0.0001 or t > 35.0 + 0.0001:
				outside += 1
	check_eq(outside, 0, "no time outside 15-70% of a 50 s wave")
	check(lo < 8.0 and hi > 34.5, "the whole window is used (%.2f .. %.2f)" % [lo, hi])


func test_roll_affix_covers_every_affix() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var counts := {}
	var probe := RandomNumberGenerator.new()
	probe.seed = 5
	for _i in 4000:
		var a := EliteAffixes.roll_affix(rng)
		check(a in EliteAffixes.ALL, "a known affix")
		counts[a] = counts.get(a, 0) + 1
		probe.randi()
	check_eq(rng.state, probe.state, "one draw per affix")
	for a in EliteAffixes.ALL:
		check_near(float(counts.get(a, 0)) / 4000.0, 0.25, 0.03, "%s ~25%%" % a)
	check_eq(EliteAffixes.display_name(EliteAffixes.VAMPIRIC, "Troll Axethrower"), "Vampiric Troll Axethrower",
			"<Affix> <name>")


# --- WaveDirector ------------------------------------------------------------------------------

func _director() -> WaveDirector:
	var d := WaveDirector.create(EFakes.arena_of(world))
	world.add_child(d)
	return d


func test_director_schedules_elites_at_wave_start() -> void:
	EliteAffixes.rate_mult = 3.0
	var d := _director()
	var state := RunState.rng.state
	var expected := EliteAffixes.schedule(10, RunState.wave_duration(10), RunState.player_count, RunState.rng)
	RunState.rng.state = state
	d.start_wave(10)
	check(not expected.is_empty(), "elites expected at wave 10 with rate 3")
	check_eq(d.elite_times(), expected, "the schedule is drawn right at wave start, before the first group pick")
	check_eq(d.duration, RunState.wave_duration(10), "wave duration")
	check_eq(d.elapsed(), 0.0, "nothing elapsed yet")
	d.stop()
	check(d.elite_times().is_empty(), "stop() drops the remaining times")


func test_due_times_make_the_first_enemies_of_the_next_group_elite() -> void:
	var d := _director()
	d.start_wave(6)
	d.stop()  # drive _spawn_group by hand
	d._running = true
	d.time_left = d.duration - 10.0  # 10 s into the wave
	d._elite_times = [3.0, 9.5, 30.0] as Array[float]
	var spawned_before := RunState.elites_spawned
	var g := WaveDirector.PendingGroup.new()
	g.data = EFakes.enemy_data()
	g.count = 3
	g.position = Vector3(5.0, 0.0, 5.0)
	g.ring = 1.0
	var order: Array[Enemy] = []
	d.enemy_spawned.connect(func(e: Enemy) -> void: order.append(e))
	d._spawn_group(g)
	check_eq(order.size(), 3, "three spawned")
	if order.size() == 3:
		check(order[0].is_elite() and order[1].is_elite(), "two due times: the first two enemies")
		check(not order[2].is_elite(), "the third stays normal")
		check(order[0].elite_affix in EliteAffixes.ALL and order[1].elite_affix in EliteAffixes.ALL, "with an affix")
		check_near(order[0].max_hp, EFakes.enemy_data().hp_at_wave(6) * RunState.coop_hp_mult() * 3.0, 0.0001,
				"HP x3 of its wave")
	check_eq(RunState.elites_spawned, spawned_before + 2, "counted")
	check_eq(d.elites_this_wave, 2, "this wave")
	check_eq(d.elite_times(), [30.0] as Array[float], "the future time waits")
	# The next group before the last time: nobody is made elite (never twice either).
	order.clear()
	d._spawn_group(g)
	check_eq(order.size(), 3, "three more")
	for e in order:
		check(not e.is_elite(), "no due time, no elite")
	# Once it has passed, the next group's first enemy.
	d.time_left = d.duration - 31.0
	order.clear()
	d._spawn_group(g)
	check(order.size() == 3 and order[0].is_elite() and not order[1].is_elite(), "first of the next group")
	check(d.elite_times().is_empty(), "all used")
	check_eq(RunState.elites_spawned, spawned_before + 3, "three elites")


func test_elites_spawn_during_a_wave() -> void:
	EliteAffixes.rate_mult = 6.0
	EFakes.spawn_player(world, Vector3(30.0, 0.0, 30.0))  # far away: nothing dies
	var d := _director()
	d.start_wave(8)
	var times := d.elite_times()
	check(times.size() >= 2, "several elites scheduled (%d)" % times.size())
	var elites: Array[Enemy] = []
	d.enemy_spawned.connect(func(e: Enemy) -> void:
		if e.is_elite():
			elites.append(e))
	EFakes.step(d, times[0] - 0.5)
	check(elites.is_empty(), "no elite before the first scheduled time")
	EFakes.step(d, d.duration * 0.7 + 3.0 - d.elapsed())
	check(elites.size() >= 1, "elites spawned (%d of %d)" % [elites.size(), times.size()])
	check_eq(RunState.elites_spawned, elites.size(), "RunState counts every elite")
	check_eq(d.elites_this_wave, elites.size(), "the director too")
	for e in elites:
		check(e.is_in_group(&"enemies"), "an elite is a normal member of the enemies group (MAX_ENEMIES)")
		check(e.elite_plate != null and e.elite_plate.get_parent() == e, "with its nameplate")
		check_near(e.max_hp, e.data.hp_at_wave(8) * RunState.coop_hp_mult() * EliteAffixes.HP_MULT, 0.0001, "HP x3")
	d.time_left = 0.01
	EFakes.step(d, 0.05)
	check_eq(RunState.elites_killed, 0, "despawned at the wave end: not killed")


# --- make_elite and the affixes -------------------------------------------------------------------

func test_make_elite_hp_size_and_plate() -> void:
	var data := EFakes.enemy_data()
	var normal := Enemy.create(data, 3)
	var e := Enemy.create(data, 3)
	var shape := e.get_node(^"Shape") as CollisionShape3D
	var shared_shape := (normal.get_node(^"Shape") as CollisionShape3D).shape
	e.make_elite(EliteAffixes.FRENZIED)
	check(e.is_elite(), "is_elite")
	check_eq(e.elite_affix, EliteAffixes.FRENZIED, "affix")
	check_near(e.max_hp, normal.max_hp * 3.0, 0.0001, "max HP x3")
	check_near(e.hp, e.max_hp, 0.0001, "full HP")
	check_near(e.radius, data.radius * 1.3, 0.0001, "body x1.3")
	check_near((shape.shape as SphereShape3D).radius, data.radius * 1.3, 0.0001, "collision x1.3")
	check_near((shared_shape as SphereShape3D).radius, data.radius, 0.0001, "other enemies keep their shape")
	check(e.model.scale.is_equal_approx(Vector3.ONE * 1.3), "model x1.3")
	check(e.elite_plate != null and e.elite_plate.get_parent() == e, "nameplate child")
	check(not normal.is_elite() and normal.elite_plate == null, "a normal enemy is not elite")
	var hp := e.max_hp
	e.make_elite(EliteAffixes.SHIELDING)
	check_eq(e.max_hp, hp, "made elite once only")
	check_eq(e.elite_affix, EliteAffixes.FRENZIED, "keeps its first affix")
	check_eq(e.shield_hp, 0.0, "no second affix")
	normal.free()
	e.free()


func test_shielding_absorbs_and_regrows() -> void:
	var e := _elite(EliteAffixes.SHIELDING, Vector3(3.0, 0.0, 0.0))
	e.apply_stun(100.0)  # keep it in place
	var shield := e.max_hp * 0.3
	check_near(e.shield_hp, shield, 0.0001, "30% max HP shield at spawn")
	var hp := e.hp
	e.take_damage(shield * 0.5)
	check_eq(e.hp, hp, "the shield takes the hit")
	check_near(e.shield_hp, shield * 0.5, 0.0001, "drained")
	e.take_damage(shield * 0.5 + 4.0)
	check_eq(e.shield_hp, 0.0, "broken")
	check_near(e.hp, hp - 4.0, 0.0001, "the overflow reaches HP")
	e.take_damage(2.0)
	check_near(e.hp, hp - 6.0, 0.0001, "no shield: HP takes it all")
	EFakes.step(e, 7.9)
	check_eq(e.shield_hp, 0.0, "still down after 7.9 s")
	EFakes.step(e, 0.2)
	check_near(e.shield_hp, shield, 0.0001, "regrows 8 s after it broke")
	e.take_damage(1.0)
	EFakes.step(e, 9.0)
	check_near(e.shield_hp, shield - 1.0, 0.0001, "no regrow while it holds")
	# The plate shows the shield segment and the bubble.
	e.elite_plate.refresh()
	check(e.elite_plate.bubble.visible, "bubble while shielded")
	check_near(e.elite_plate.shield_ratio(), (shield - 1.0) / e.max_hp, 0.0001, "shield segment")
	e.take_damage(shield)
	e.elite_plate.refresh()
	check(not e.elite_plate.bubble.visible, "bubble gone with the shield")
	check_eq(e.elite_plate.shield_ratio(), 0.0, "segment gone")


func test_kill_goes_through_the_shield() -> void:
	var e := _elite(EliteAffixes.SHIELDING)
	var deaths: Array[int] = []
	e.died.connect(func(_e: Enemy, k: int) -> void: deaths.append(k))
	e.take_damage(e.hp)
	check(not e.is_dead(), "the shield saves it from a hit of its HP")
	e.kill()
	check(e.is_dead() and deaths.size() == 1, "kill() ignores the shield (Execute)")
	check_eq(RunState.elites_killed, 1, "a normal elite death")


func test_enraged_threshold_speed_damage_and_slow_immunity() -> void:
	var hero := EFakes.spawn_player(world, Vector3(20.0, 0.0, 0.0))
	var e := _elite(EliteAffixes.ENRAGED, Vector3(0.0, 0.0, 0.0))
	var base_speed := e.walk_speed()
	e.apply_slow(40.0, 5.0)
	check(e.is_slowed(), "slowed before the rage")
	e.take_damage(e.max_hp * 0.49)
	check(not e.is_enraged(), "51% HP: calm")
	check_eq(e.damage_mult, 1.0, "normal damage")
	e.take_damage(e.max_hp * 0.01 + 0.001)
	check(e.is_enraged(), "at 50% HP: enraged")
	check(not e.is_slowed(), "the rage ends slows")
	check_near(e.damage_mult, 1.5, 0.0001, "+50% damage")
	check_near(e.walk_speed(), base_speed * 1.3, 0.0001, "+30% speed")
	e.apply_slow(60.0, 3.0)
	check(not e.is_slowed(), "immune to slows")
	e.heal(e.max_hp)
	e.take_damage(e.max_hp * 0.6)
	check_near(e.damage_mult, 1.5, 0.0001, "rages once")
	e.apply_stun(0.5)
	check(e.is_stunned(), "stuns still work")
	e.stun_left = 0.0
	e.apply_fear(0.5, Vector3.ZERO)
	check(e.is_feared(), "fear still works")
	e.fear_left = 0.0
	# Enraged contact hits: +50%.
	e.global_position = hero.global_position + Vector3(0.5, 0.0, 0.0)
	e._physics_process(DT)
	check_eq(hero.fake_hits.size(), 1, "contact hit")
	if hero.fake_hits.size() == 1:
		check_near(hero.fake_hits[0], e.contact_damage * 1.5, 0.0001, "contact damage x1.5")
	e.elite_plate.refresh()
	check(e.elite_plate.is_tinted(), "red tint once enraged")
	var body := e.model.get_node(^"Pivot/Body") as MeshInstance3D
	var mat := Mats.base_material(body) as ShaderMaterial
	check(mat != null and (mat.get_shader_parameter(&"albedo") as Color).is_equal_approx(ElitePlate.ENRAGE_TINT),
			"the body's material carries the tint")


func test_enraged_projectiles_hit_harder() -> void:
	var data := EFakes.enemy_data(EnemyData.Behavior.RANGED)
	data.projectile_damage = 4.0
	data.attack_cooldown = 0.5
	data.preferred_distance = 6.0
	EFakes.spawn_player(world, Vector3.ZERO)
	var e := _elite(EliteAffixes.ENRAGED, Vector3(6.0, 0.0, 0.0), data)
	e.take_damage(e.max_hp * 0.6)
	check(e.is_enraged(), "enraged")
	EFakes.step(e, 1.5)
	var axes: Array[Node] = _of_type(Projectile)
	check(axes.size() >= 1, "threw")
	if not axes.is_empty():
		check_near((axes[0] as Projectile).damage, e.projectile_damage * 1.5, 0.0001, "axe damage x1.5")


func test_frenzied_speed_and_cooldowns() -> void:
	var hero := EFakes.spawn_player(world, Vector3.ZERO)
	var data := EFakes.enemy_data()
	data.move_speed = 0.0
	var e := _elite(EliteAffixes.FRENZIED, Vector3(0.5, 0.0, 0.0), data)
	check_near(e.speed_mult, 1.25, 0.0001, "+25% speed")
	check_near(e.attack_cooldown_mult, 0.6, 0.0001, "cooldowns x0.6")
	e._physics_process(DT)
	check_eq(hero.fake_hits.size(), 1, "first contact hit")
	EFakes.step(e, 0.55)
	check_eq(hero.fake_hits.size(), 1, "not within 0.6 s")
	EFakes.step(e, 0.1)
	check_eq(hero.fake_hits.size(), 2, "contact cooldown 0.6 s instead of 1 s")
	# Walks 25% faster than a normal enemy of the same data.
	var walker_data := EFakes.enemy_data()
	var frenzied := _elite(EliteAffixes.FRENZIED, Vector3(-10.0, 0.0, 8.0), walker_data)
	var normal := EFakes.spawn_enemy(world, walker_data, Vector3(-10.0, 0.0, -8.0))
	normal.move_speed = frenzied.move_speed  # same jitter
	EFakes.step_all([frenzied, normal] as Array[Node], 1.0)
	var fast := EFakes.flat_distance(frenzied.global_position, Vector3(-10.0, 0.0, 8.0))
	var slow := EFakes.flat_distance(normal.global_position, Vector3(-10.0, 0.0, -8.0))
	check_near(fast / slow, 1.25, 0.08, "walks ~25%% faster (%.2f vs %.2f m)" % [fast, slow])


func test_frenzied_lunges_and_throws_sooner() -> void:
	var lunger := EFakes.enemy_data(EnemyData.Behavior.LUNGE)
	lunger.lunge_windup = 0.3
	lunger.lunge_speed = 8.0
	lunger.attack_cooldown = 2.0
	lunger.contact_damage = 0.0
	EFakes.spawn_player(world, Vector3(0.0, 0.0, -3.0))
	var e := _elite(EliteAffixes.FRENZIED, Vector3.ZERO, lunger)
	for _i in 120:
		var before := e.ai_state
		e._physics_process(DT)
		if before == Enemy.AiState.LEAP and e.ai_state == Enemy.AiState.MOVE:
			break
	check_near(e.attack_cooldown_left, 2.0 * 0.6, 0.001, "lunge cooldown x0.6")
	check_near(e.attack_cooldown(), 1.2, 0.0001, "attack_cooldown()")
	var thrower := EFakes.enemy_data(EnemyData.Behavior.RANGED)
	thrower.attack_cooldown = 2.0
	var t := Enemy.create(thrower, 3)
	var start := t.attack_cooldown_left
	t.make_elite(EliteAffixes.FRENZIED)
	check_near(t.attack_cooldown_left, start * 0.6, 0.0001, "the spawn stagger shrinks too")
	t.free()


func test_vampiric_heals_on_landed_hits() -> void:
	var slot := PlayerManager.join(ScriptedInput.new("test:vamp"))
	var hero := EmittingHero.new()
	hero.slot = slot
	slot.player = hero
	_entities().add_child(hero)
	hero.global_position = Vector3(20.0, 0.0, 0.0)
	Enemy.invalidate_player_cache()
	# Built like the director does: make_elite before add_child connects through the slots.
	var data := EFakes.enemy_data()
	data.move_speed = 0.0
	var e := Enemy.create(data, 3)
	e.make_elite(EliteAffixes.VAMPIRIC)
	check(not e.is_inside_tree(), "not in the tree yet")
	check(hero.damage_taken.is_connected(e._on_hero_damage_taken), "connected before add_child")
	_entities().add_child(e)
	e.global_position = Vector3(0.0, 0.0, 0.0)
	e.take_damage(e.max_hp * 0.5)
	var hp := e.hp
	hero.global_position = Vector3(0.5, 0.0, 0.0)
	Enemy.invalidate_player_cache()
	e._physics_process(DT)
	check_eq(hero.fake_hits.size(), 1, "contact hit")
	check_near(e.hp, hp + e.max_hp * 0.1, 0.0001, "heals 10% of max HP per landed hit")
	# A projectile reports the elite as the source the same way.
	hp = e.hp
	hero.take_damage(3.0, CombatMath.KIND_PROJECTILE, e)
	check_near(e.hp, hp + e.max_hp * 0.1, 0.0001, "axe hits heal too")
	# Somebody else's hit does not.
	var other := EFakes.spawn_enemy(world, data, Vector3(15.0, 0.0, 0.0))
	hp = e.hp
	hero.take_damage(3.0, CombatMath.KIND_MELEE, other)
	hero.take_damage(3.0, CombatMath.KIND_MELEE, null)
	check_eq(e.hp, hp, "other sources do not heal it")
	# Mortal Wound: healing reduction applies.
	e.apply_healing_reduction(50.0, 5.0)
	hero.take_damage(3.0, CombatMath.KIND_MELEE, e)
	check_near(e.hp, hp + e.max_hp * 0.05, 0.0001, "-50% healing: 5%")
	# Dead: disconnected.
	e.take_damage(e.max_hp * 10.0)
	check(e.is_dead(), "dead")
	check(not hero.damage_taken.is_connected(e._on_hero_damage_taken), "disconnected on death")


func test_vampiric_skips_heroes_without_a_node_and_other_affixes_never_listen() -> void:
	var empty := PlayerManager.join(ScriptedInput.new("test:empty"))
	check(empty.player == null, "a slot without a hero")
	var slot := PlayerManager.join(ScriptedInput.new("test:hero"))
	var hero := EmittingHero.new()
	slot.player = hero
	_entities().add_child(hero)
	var vamp := _elite(EliteAffixes.VAMPIRIC, Vector3(5.0, 0.0, 5.0))
	check(hero.damage_taken.is_connected(vamp._on_hero_damage_taken), "the hero is connected")
	var frenzied := _elite(EliteAffixes.FRENZIED, Vector3(-5.0, 0.0, 5.0))
	check(not hero.damage_taken.is_connected(frenzied._on_hero_damage_taken), "only Vampiric listens")
	vamp.despawn()
	check(not hero.damage_taken.is_connected(vamp._on_hero_damage_taken), "despawn disconnects")


# --- Rewards -----------------------------------------------------------------------------------

func test_elite_rewards_keyed_on_the_affix() -> void:
	var killer := EFakes.spawn_player(world, Vector3(25.0, 0.0, 25.0), 1)
	var data := EFakes.enemy_data()
	var e := _elite(EliteAffixes.FRENZIED, Vector3(2.0, 0.0, 2.0), data)
	RunState.loot_drops_this_wave = LootDrops.max_drops_per_wave()  # the normal cap is full
	var gold_before := RunState.gold
	e.take_damage(e.max_hp * 2.0, false, killer)
	check(e.is_dead(), "dead")
	var pickups := _of_type(Pickup)
	check_eq(pickups.size(), 1, "one pickup")
	if pickups.size() == 1:
		check_eq((pickups[0] as Pickup).gold, EliteAffixes.GOLD, "10 gold instead of the enemy's gold")
		check_eq((pickups[0] as Pickup).xp, data.xp * EliteAffixes.XP_MULT, "XP x5")
	var bags := _of_type(LootBag)
	check_eq(bags.size(), 1, "the guaranteed drop ignores the full cap")
	if bags.size() == 1:
		var item := (bags[0] as LootBag).item
		check(item != null and item.rarity >= Items.Rarity.RARE and item.looted, "Rare+ looted item")
	check_eq(RunState.loot_drops_this_wave, LootDrops.max_drops_per_wave(), "not counted against the cap")
	check_eq(RunState.elites_killed, 1, "elite kill counted")
	check_eq(_special, [[&"elite", 1]], "special kill recorded for P2")
	check_eq(RunState.gold, gold_before, "gold arrives through the pickup")


func test_elite_keeps_the_normal_drop_roll() -> void:
	var killer := EFakes.spawn_player(world, Vector3(25.0, 0.0, 25.0), 0)
	killer.stats.set_source(&"test", {Stats.FORTUNE: 5000.0})  # every normal roll drops
	var e := _elite(EliteAffixes.SHIELDING, Vector3(-3.0, 0.0, 1.0))
	e.kill(killer)
	check_eq(_of_type(LootBag).size(), 2, "the guaranteed drop + the normal drop")
	check_eq(RunState.loot_drops_this_wave, 1, "only the normal one counts")


func test_is_elite_override_without_affix_gets_no_elite_rewards() -> void:
	var data := EFakes.enemy_data()
	var e := Enemy.setup(ClaimsElite.new(), data, 3)
	_entities().add_child(e)
	e.global_position = Vector3(1.0, 0.0, 1.0)
	check(e.is_elite() and e.elite_affix == &"", "claims elite, no affix")
	RunState.loot_drops_this_wave = LootDrops.max_drops_per_wave()
	e.take_damage(1000.0)
	var pickups := _of_type(Pickup)
	check(pickups.size() == 1 and (pickups[0] as Pickup).gold == data.gold and (pickups[0] as Pickup).xp == data.xp,
			"its normal gold / XP")
	check_eq(_of_type(LootBag).size(), 0, "no guaranteed drop")
	check_eq(RunState.elites_killed, 0, "not an elite kill")
	check(_special.is_empty(), "no special kill")


func test_despawned_elite_gives_nothing() -> void:
	var e := _elite(EliteAffixes.VAMPIRIC)
	var deaths: Array[int] = []
	e.died.connect(func(_e: Enemy, k: int) -> void: deaths.append(k))
	e.despawn()
	check(e.is_queued_for_deletion(), "removed")
	check_eq(deaths.size(), 0, "no death")
	check_eq(_of_type(Pickup).size(), 0, "no gold / XP")
	check_eq(_of_type(LootBag).size(), 0, "no item")
	check_eq(RunState.elites_killed, 0, "not killed")
	check(_special.is_empty(), "no special kill")


func test_slayer_applies_to_elites() -> void:
	var stats := StatBlock.new()
	stats.set_source(&"test", {Stats.SLAYER: 40.0})
	var normal := Enemy.create(EFakes.enemy_data(), 3)
	var elite := Enemy.create(EFakes.enemy_data(), 3)
	elite.make_elite(EliteAffixes.ENRAGED)
	check_eq(CombatMath.target_damage_mult(stats, 1.0, normal.is_elite()), 1.0, "no Slayer on normal enemies")
	check_near(CombatMath.target_damage_mult(stats, 1.0, elite.is_elite()), 1.4, 0.0001, "+40% on elites")
	normal.free()
	elite.free()
	# End to end through the proc door (the same target bonus as weapon hits).
	var p := PFakes.spawn_player(world, 0, &"warrior", Vector3(20.0, 0.0, 20.0))
	p.stats.set_source(&"test", {Stats.SLAYER: 40.0})
	var a := Enemy.create(EFakes.enemy_data(), 3)
	var b := Enemy.create(EFakes.enemy_data(), 3)
	b.make_elite(EliteAffixes.FRENZIED)
	a.max_hp = 1000.0
	a.hp = 1000.0
	b.max_hp = 1000.0
	b.hp = 1000.0
	_entities().add_child(a)
	_entities().add_child(b)
	p.procs.deal_raw(a, 10.0, &"physical")
	p.procs.deal_raw(b, 10.0, &"physical")
	check(a.hp < 1000.0, "the normal enemy took damage")
	check_near((1000.0 - b.hp) / maxf(0.001, 1000.0 - a.hp), 1.4, 0.0001, "Slayer x1.4 on the elite")


# --- ElitePlate --------------------------------------------------------------------------------

func test_nameplate_shows_name_hp_and_frees_with_the_enemy() -> void:
	var data := EFakes.enemy_data()
	var e := _elite(EliteAffixes.SHIELDING, Vector3(1.0, 0.0, 0.0), data)
	var plate := e.elite_plate
	check(plate != null and plate.get_parent() == e, "child of the elite")
	check_eq(plate.name_label.text, "Shielding Test Enemy", "<Affix> <name>")
	check(plate.name_label.fixed_size and plate.name_label.no_depth_test
			and plate.name_label.billboard == BaseMaterial3D.BILLBOARD_ENABLED, "fixed-size billboard, no depth test")
	check(plate.plate.position.y > e.model.head_height * 1.3, "above the scaled head")
	var sprites := 0
	for child in plate.plate.get_children():
		if child is Sprite3D:
			sprites += 1
			var s := child as Sprite3D
			check(s.fixed_size and s.no_depth_test and s.texture != null, "%s: fixed size, on top" % s.name)
	check(sprites >= 5, "two wings, bar back / fill / shield, gem (%d)" % sprites)
	check(plate.get_node_or_null(^"Plate/WingLeft") != null and plate.get_node_or_null(^"Plate/WingRight") != null,
			"silver dragon wings")
	var wl := plate.get_node(^"Plate/WingLeft") as Sprite3D
	var wr := plate.get_node(^"Plate/WingRight") as Sprite3D
	check(wr.flip_h and not wl.flip_h, "mirrored")
	check(wl.offset.x < 0.0 and wr.offset.x > 0.0, "one on each side")
	# The bar is as wide as the name (at least BAR_SIZE.x) and the wings sit on its ends.
	var text_w := ElitePlate.text_width_px(plate.name_label.text)
	check(text_w > 50.0, "the name has a width (%.0f px)" % text_w)
	check(plate.bar_width >= text_w and plate.bar_width >= ElitePlate.BAR_SIZE.x, "bar spans the name")
	var back := plate.get_node(^"Plate/BarBack") as Sprite3D
	check_eq(back.texture.get_width(), plate.bar_width, "bar texture width")
	var ss := float(ElitePlate.WING_SUPERSAMPLE)
	var right_root := wr.offset.x / ss + ElitePlate.WING_ROOT_INSET.x
	check_near(right_root, plate.bar_width * 0.5 + ElitePlate.WING_GAP, 0.01, "right wing root on the bar's end")
	var left_root := wl.offset.x / ss + ElitePlate.WING_SIZE.x - ElitePlate.WING_ROOT_INSET.x
	check_near(left_root, -plate.bar_width * 0.5 - ElitePlate.WING_GAP, 0.01, "left wing root on the bar's end")
	var short_plate := ElitePlate.bar_width_for("Ab")
	check_eq(short_plate, ElitePlate.BAR_SIZE.x, "short names keep the minimum bar")
	check_near(plate.hp_ratio(), 1.0, 0.0001, "full HP")
	e.take_damage(e.shield_hp + e.max_hp * 0.25)
	plate.refresh()
	check_near(plate.hp_ratio(), 0.75, 0.0001, "the bar follows the HP")
	check(not plate.is_tinted(), "only Enraged elites are tinted")
	e.take_damage(e.max_hp * 2.0)
	check(e.is_queued_for_deletion(), "dead")
	plate.refresh()
	check(not plate.plate.visible, "hidden once dead")
	e.free()
	check(not is_instance_valid(plate), "freed with the enemy")


func test_plate_textures_are_shared() -> void:
	var a := _elite(EliteAffixes.FRENZIED, Vector3(3.0, 0.0, 0.0))
	var b := _elite(EliteAffixes.VAMPIRIC, Vector3(-3.0, 0.0, 0.0))
	var wa := a.elite_plate.get_node(^"Plate/WingLeft") as Sprite3D
	var wb := b.elite_plate.get_node(^"Plate/WingLeft") as Sprite3D
	check(wa.texture == wb.texture, "one wing texture for every elite")
	check(a.elite_plate.bubble.material_override == b.elite_plate.bubble.material_override, "one bubble material")
	var ga := a.elite_plate.get_node(^"Plate/Gem") as Sprite3D
	var gb := b.elite_plate.get_node(^"Plate/Gem") as Sprite3D
	check(ga.texture != gb.texture, "gems in the affix colour")
	var img := ElitePlate.wing_texture().get_image()
	check_eq(img.get_size(), ElitePlate.WING_SIZE * ElitePlate.WING_SUPERSAMPLE, "wing texture size")
	var opaque := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				opaque += 1
	check(float(opaque) > img.get_width() * img.get_height() * 0.25, "the wing has a body (%d texels)" % opaque)
