extends TestCase
## Loot Goblin (GDD 8, M5, architecture §2.6): its data, GoblinSpawner (chance, timing,
## one per wave, spawn, announcements, wave end), LootGoblin (flight, no contact damage,
## taunt / fear immunity, crowd control, coins per hit, portal escape, kill rewards, elite
## status without elite rewards) and the overhead tag.

const EFakes := preload("res://tests/enemies_fakes.gd")
const DT := 1.0 / 60.0

var world: Node3D
var director: WaveDirector
var spawner: GoblinSpawner
var announcements: Array[Array] = []
var specials: Array[Array] = []


func before_each() -> void:
	PlayerManager.clear()
	RunState.start_run(1, 4242)
	world = EFakes.make_world(tree)
	announcements.clear()
	specials.clear()


func after_each() -> void:
	GoblinSpawner.chance_override = -1.0
	if RunState.special_killed.is_connected(_on_special_killed):
		RunState.special_killed.disconnect(_on_special_killed)
	EFakes.free_world(tree, world)
	world = null
	director = null
	spawner = null
	PlayerManager.clear()


func _on_announced(text: String, color: Color) -> void:
	announcements.append([text, color])


func _on_special_killed(kind: StringName, killer_index: int) -> void:
	specials.append([kind, killer_index])


func _arena() -> Arena:
	return EFakes.arena_of(world)


## A WaveDirector on the test arena with a GoblinSpawner child (announcements recorded).
func _make_director() -> void:
	director = WaveDirector.create(_arena())
	world.add_child(director)
	spawner = GoblinSpawner.create(director)
	director.add_child(spawner)
	spawner.announced.connect(_on_announced)


func _goblin(pos: Vector3, wave: int = 3) -> LootGoblin:
	var g := LootGoblin.create(LootGoblin.goblin_data(), wave)
	_arena().entities.add_child(g)
	g.global_position = pos
	return g


func _pickups() -> Array[Node]:
	return EFakes.live_children_of_type(world, Pickup)


func _gold_on_ground() -> int:
	var sum := 0
	for p in _pickups():
		sum += (p as Pickup).gold
	return sum


func _xp_on_ground() -> int:
	var sum := 0
	for p in _pickups():
		sum += (p as Pickup).xp
	return sum


func _goblins_alive() -> int:
	var n := 0
	for node in tree.get_nodes_in_group(&"loot_goblins"):
		if node is LootGoblin and not (node as LootGoblin).is_dead():
			n += 1
	return n


## A joined slot whose hero is a FakePlayer at [param pos] with [param fortune] extra Fortune.
func _hero(pos: Vector3, fortune: float) -> EFakes.FakePlayer:
	var slot := PlayerManager.add_bot(&"warrior", 1)
	var p := EFakes.spawn_player(world, pos)
	p.slot = slot
	slot.player = p
	p.stats.set_source(&"test", {Stats.FORTUNE: fortune})
	return p


# --- Data ------------------------------------------------------------------------------

func test_goblin_data_and_the_director_never_picks_it() -> void:
	var d := LootGoblin.goblin_data()
	check(d != null, "res://data/enemies/loot_goblin.tres is loaded")
	if d == null:
		return
	check_eq(d.display_name, "Loot Goblin", "name")
	check_eq(d.max_hp, 30.0, "30 base HP (~7.5 Skeleton Grunts)")
	check_eq(d.max_hp / Db.get_enemy(&"skeleton_grunt").max_hp, 7.5, "7.5 grunts")
	check_eq(d.move_speed, 4.4, "4.4 m/s")
	check_eq(d.contact_damage, 0.0, "no contact damage")
	check_eq(d.spawn_weight, 0.0, "spawn weight 0")
	check(d.gold == 0 and d.xp == 0, "custom rewards only")
	check_eq(d.first_wave, 3, "from wave 3")
	check_eq(d.knockback_resist, 0.3, "a little knockback resistance")
	check_eq(d.model_style, &"goblin", "goblin model")
	for w in range(1, 26):
		check(d not in WaveDirector.eligible_enemies(w), "never a director pick (wave %d)" % w)


# --- GoblinSpawner: chance and timing --------------------------------------------------

func test_chance_gates_fortune_cap_and_override() -> void:
	check_eq(GoblinSpawner.chance_for(1, 0.0), 0.0, "wave 1: none")
	check_eq(GoblinSpawner.chance_for(2, 100.0), 0.0, "wave 2: none, whatever the Fortune")
	check_eq(GoblinSpawner.chance_for(3, 0.0), 0.15, "wave 3: 15%")
	check_eq(GoblinSpawner.chance_for(4, 20.0), 0.25, "+0.5 pp per Fortune point")
	check_eq(GoblinSpawner.chance_for(9, 1000.0), 0.5, "capped at 50%")
	check_eq(GoblinSpawner.chance_for(6, -30.0), 0.15, "negative Fortune does not lower it")
	for w in [10, 20, 25]:
		check_eq(GoblinSpawner.chance_for(w, 50.0), 0.0, "boss / elite wave %d: none" % w)
	check_eq(GoblinSpawner.chance_for(11, 0.0), 0.15, "wave 11 again")
	check_eq(GoblinSpawner.chance_for(24, 0.0), 0.15, "wave 24")
	GoblinSpawner.chance_override = 0.8
	check_eq(GoblinSpawner.chance_for(3, 0.0), 0.8, "--goblin-chance replaces it")
	check_eq(GoblinSpawner.chance_for(4, 1000.0), 0.8, "also above the cap's Fortune")
	check_eq(GoblinSpawner.chance_for(2, 0.0), 0.0, "but only on eligible waves")
	check_eq(GoblinSpawner.chance_for(10, 0.0), 0.0, "never on a boss wave")
	GoblinSpawner.chance_override = 0.0
	check_eq(GoblinSpawner.chance_for(5, 100.0), 0.0, "--goblin-chance=0 switches it off")


func test_team_fortune_is_the_luckiest_living_hero() -> void:
	check_eq(GoblinSpawner.team_fortune(), 0.0, "no heroes")
	var a := _hero(Vector3(-3, 0, 0), 12.0)
	var b := _hero(Vector3(3, 0, 0), 30.0)
	check_eq(GoblinSpawner.team_fortune(), 30.0, "the highest Fortune")
	check_eq(GoblinSpawner.chance_for(5, GoblinSpawner.team_fortune()), 0.3, "15% + 30 x 0.5 pp")
	b.downed = true
	check_eq(GoblinSpawner.team_fortune(), 12.0, "downed heroes do not count")
	a.downed = true
	check_eq(GoblinSpawner.team_fortune(), 0.0, "nobody standing")


func test_spawn_time_window_and_skip_rule() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var lo := INF
	var hi := -INF
	for i in 300:
		var t := GoblinSpawner.roll_spawn_time(30.0, rng)
		lo = minf(lo, t)
		hi = maxf(hi, t)
	check(lo >= 3.0 and lo < 3.5, "from 3 s (earliest %.2f)" % lo)
	check(hi <= 10.5 and hi > 10.0, "to 35%% of a 30 s wave (latest %.2f)" % hi)
	for i in 50:
		check_eq(GoblinSpawner.roll_spawn_time(20.0, rng), -1.0, "a 20 s wave leaves < 18 s: no goblin")
	var skipped := 0
	for i in 200:
		var t := GoblinSpawner.roll_spawn_time(22.0, rng)
		if t < 0.0:
			skipped += 1
		else:
			check(t <= 4.0 + 0.0001, "22 s wave: only early spawns leave 18 s (%.2f)" % t)
	check(skipped > 50 and skipped < 200, "22 s wave: late rolls skipped (%d / 200)" % skipped)
	# One draw per roll.
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 5
	b.seed = 5
	GoblinSpawner.roll_spawn_time(40.0, a)
	b.randf()
	check_eq(a.randf(), b.randf(), "exactly one draw")
	# Every real eligible wave fits (the 35% window ends ≥ 18 s before the wave does).
	for w in range(GoblinSpawner.FIRST_WAVE, 26):
		var d := RunState.wave_duration(w)
		check(d - maxf(GoblinSpawner.SPAWN_MIN_TIME, GoblinSpawner.SPAWN_MAX_SHARE * d) >= 18.0,
				"wave %d always has room" % w)


func test_roll_wave_draws_chance_then_time() -> void:
	spawner = GoblinSpawner.create(null)
	var ref := RandomNumberGenerator.new()
	GoblinSpawner.chance_override = 1.0
	ref.state = RunState.rng.state
	spawner.roll_wave(3)
	check(spawner.pending_time() >= 3.0 and spawner.pending_time() <= 10.5, "wave 3: 3 .. 10.5 s (%.2f)" % spawner.pending_time())
	ref.randf()
	check_near(spawner.pending_time(), ref.randf_range(3.0, 10.5), 0.0001, "chance draw, then the time draw")
	check_eq(RunState.rng.state, ref.state, "two draws")
	var before := RunState.rng.state
	spawner.roll_wave(2)
	check_eq(spawner.pending_time(), -1.0, "wave 2: none")
	check_eq(RunState.rng.state, before, "no draw on an ineligible wave")
	spawner.roll_wave(10)
	check(spawner.pending_time() == -1.0 and RunState.rng.state == before, "boss wave: none, no draw")
	GoblinSpawner.chance_override = 0.5
	var came := 0
	for i in 40:
		ref.state = RunState.rng.state
		spawner.roll_wave(4)
		var hit := ref.randf() < 0.5
		if hit:
			came += 1
			ref.randf()
		check_eq(spawner.pending_time() >= 0.0, hit, "the chance draw decides")
		check_eq(RunState.rng.state, ref.state, "a time draw only when it comes")
	check(came > 5 and came < 35, "about half the waves (%d / 40)" % came)
	spawner.free()


# --- GoblinSpawner: spawning ------------------------------------------------------------

func test_spawner_brings_one_goblin_at_its_time_and_announces_it() -> void:
	_make_director()
	GoblinSpawner.chance_override = 1.0
	director.start_wave(3)
	var t := spawner.pending_time()
	check(t >= 3.0 and t <= 10.5, "a goblin is coming (%.2f s)" % t)
	EFakes.step_all([director, spawner], t - 0.1)
	check(spawner.goblin == null and RunState.goblins_spawned == 0 and _goblins_alive() == 0, "not yet")
	check(announcements.is_empty(), "no banner yet")
	EFakes.step_all([director, spawner], 0.2)
	var g := spawner.goblin
	check(g != null and is_instance_valid(g) and g.is_inside_tree(), "spawned")
	if g == null:
		return
	check(g.get_parent() == _arena().entities, "under the arena's entities")
	check(g.is_in_group(&"enemies"), "an enemy (the director's stop() removes it)")
	check_eq(g.wave, 3, "at the wave's strength")
	check_eq(RunState.goblins_spawned, 1, "counted")
	check_eq(spawner.pending_time(), -1.0, "nothing pending")
	check_eq(announcements, [["A Loot Goblin appeared!", UiTheme.GOLD]] as Array[Array], "gold banner")
	EFakes.step_all([director, spawner], 4.0)
	check_eq(_goblins_alive(), 1, "at most one per wave")
	check_eq(RunState.goblins_spawned, 1, "still one")


func test_no_goblin_without_the_chance() -> void:
	_make_director()
	GoblinSpawner.chance_override = 0.0
	director.start_wave(5)
	check_eq(spawner.pending_time(), -1.0, "none rolled")
	EFakes.step_all([director, spawner], 12.0)
	check(_goblins_alive() == 0 and RunState.goblins_spawned == 0 and announcements.is_empty(), "none came")


func test_wave_end_cancels_the_spawn_and_despawns_the_goblin() -> void:
	_make_director()
	GoblinSpawner.chance_override = 1.0
	director.start_wave(3)
	check(spawner.pending_time() > 0.0, "pending")
	director.time_left = 0.01
	EFakes.step_all([director, spawner], 0.05)
	check(not director.is_running(), "the wave ended before the goblin came")
	check_eq(spawner.pending_time(), -1.0, "cancelled")
	check_eq(RunState.goblins_spawned, 0, "never spawned")
	# Next wave: a fresh roll; this time it comes, and the wave end removes it without loot.
	director.start_wave(4)
	EFakes.step_all([director, spawner], spawner.pending_time() + 0.1)
	var g := spawner.goblin
	check(g != null, "came in wave 4")
	if g == null:
		return
	director.time_left = 0.01
	EFakes.step_all([director, spawner], 0.05)
	check(g.is_dead() and not g.is_in_group(&"enemies"), "despawned with the wave")
	check(spawner.goblin == null, "forgotten")
	check(RunState.goblins_killed == 0 and RunState.goblins_escaped == 0, "neither killed nor escaped")
	check(EFakes.live_children_of_type(world, LootBag).is_empty(), "no item")
	check_eq(_gold_on_ground(), 0, "no gold")


func test_spawner_forgets_a_goblin_that_left() -> void:
	_make_director()
	director.start_wave(3)
	var g := spawner.spawn_goblin()
	check(g != null and spawner.goblin == g, "tracked")
	if g == null:
		return
	g.take_damage(g.hp + 1.0)
	check(g.is_dead(), "killed")
	_arena().entities.remove_child(g)  # what its queued deletion does at the frame end
	check(spawner.goblin == null, "a killed goblin is forgotten")
	g.free()
	var h := spawner.spawn_goblin()
	check(spawner.goblin == h, "the next one is tracked")
	director.stop()  # a wipe stops the director without wave_cleared
	check(h.is_dead(), "despawned")
	_arena().entities.remove_child(h)
	check(spawner.goblin == null, "so is one the director removed")
	h.free()


# --- LootGoblin: behaviour -------------------------------------------------------------

func test_goblin_flees_a_player_standing_still() -> void:
	var p := EFakes.spawn_player(world, Vector3.ZERO)
	var g := _goblin(Vector3(3, 0, 0))
	EFakes.step(g, 2.0)
	var d := EFakes.flat_distance(g.global_position, p.global_position)
	check(d > 6.0, "ran away: %.2f m after 2 s" % d)
	check(p.fake_hits.is_empty(), "never hurt the player")
	var m := g.model
	check(m != null and m.style == &"goblin", "goblin model")


func test_goblin_runs_along_walls_and_out_of_corners() -> void:
	var b := _arena().get_bounds()
	var p := EFakes.spawn_player(world, Vector3(b.end.x - 5.0, 0, 0))
	var g := _goblin(Vector3(b.end.x - 1.5, 0, 0))
	EFakes.step(g, 1.5)
	var pos := g.global_position
	check(pos.x <= b.end.x - g.radius + 0.01, "stays inside the arena")
	check(absf(pos.z) > 2.5, "slides along the east wall instead of pressing into it (z %.2f)" % pos.z)
	check(EFakes.flat_distance(pos, p.global_position) > 3.0, "still away from the player")
	# Cornered (player on the diagonal): breaks out along a wall.
	var corner := Vector3(b.end.x - 1.0, 0, b.end.y - 1.0)
	g.global_position = corner
	p.global_position = corner + Vector3(-3, 0, -3)
	Enemy.invalidate_player_cache()
	EFakes.step(g, 2.0)
	check(EFakes.flat_distance(g.global_position, corner) > 3.0, "not stuck in the corner")
	check(b.grow(0.01).has_point(Vector2(g.global_position.x, g.global_position.z)), "inside the arena")


## Steps [param g] tick by tick for [param seconds]; returns [distance moved, total facing
## turn in degrees, largest single-tick turn in degrees].
func _calm_run(g: LootGoblin, seconds: float) -> Array[float]:
	var start := g.global_position
	var turned := 0.0
	var max_tick := 0.0
	var facing := g._facing
	for i in roundi(seconds / DT):
		g._physics_process(DT)
		var step_deg := rad_to_deg(facing.angle_to(g._facing))
		turned += step_deg
		max_tick = maxf(max_tick, step_deg)
		facing = g._facing
	return [EFakes.flat_distance(g.global_position, start), turned, max_tick]


func test_goblin_jogs_without_a_visible_player() -> void:
	# Nobody around, a stealthed hero next to it (Vanish / Killing Spree), a downed one: calm
	# jog – each jink turns it once, it does not spin on the spot.
	for variant in ["none", "stealthed", "downed"]:
		var p: EFakes.FakePlayer = null
		if variant != "none":
			p = EFakes.spawn_player(world, Vector3(1.5, 0, 0))
			if variant == "stealthed":
				p.stealth_left = 10.0
			else:
				p.downed = true
			Enemy.invalidate_player_cache()
		var g := _goblin(Vector3.ZERO)
		var out := _calm_run(g, 2.0)
		check_eq(g.flee_vector(g.global_position), Vector3.ZERO, "%s: no visible player" % variant)
		check(out[0] > 1.5, "%s: jogs (%.2f m in 2 s)" % [variant, out[0]])
		check(out[1] < 360.0, "%s: does not spin (turned %.0f° in 2 s)" % [variant, out[1]])
		check(out[2] <= rad_to_deg(LootGoblin.JINK_ANGLE) + 0.5,
				"%s: at most one jink per tick (%.1f°)" % [variant, out[2]])
		check(g.velocity.length() <= g.move_speed * LootGoblin.CALM_SPEED_RATIO + 0.01,
				"%s: at the calm speed (%.2f)" % [variant, g.velocity.length()])
		g.free()
		if p != null:
			p.free()
		Enemy.invalidate_player_cache()


func test_no_contact_damage() -> void:
	var p := EFakes.spawn_player(world, Vector3.ZERO)
	var g := _goblin(Vector3(0.3, 0, 0))
	check(not g.deals_contact_damage(), "harmless")
	EFakes.step(g, 1.5)
	check(p.fake_hits.is_empty(), "touching it never hurts")


func test_taunt_and_fear_do_not_work() -> void:
	var g := _goblin(Vector3(2, 0, 2))
	var decoy := Node3D.new()
	_arena().entities.add_child(decoy)
	g.apply_taunt(decoy, 5.0)
	check(not g.is_taunted() and g.taunt_left == 0.0, "taunt ignored")
	g.apply_fear(5.0, Vector3.ZERO)
	check(not g.is_feared() and g.fear_left == 0.0, "fear ignored")


func test_crowd_control_works() -> void:
	EFakes.spawn_player(world, Vector3.ZERO)
	var g := _goblin(Vector3(2, 0, 0))
	g.apply_stun(1.0)
	check(g.is_stunned(), "stunned")
	var at := g.global_position
	EFakes.step(g, 0.5)
	check(g.global_position.is_equal_approx(at), "a stun stops it")
	EFakes.step(g, 0.6)
	check(not g.is_stunned() and not g.global_position.is_equal_approx(at), "and it runs again")
	g.apply_slow(50.0, 3.0)
	check(g.is_slowed(), "slowed")
	EFakes.step(g, 0.5)
	check(g.velocity.length() <= g.move_speed * 0.5 + 0.01, "at half speed (%.2f)" % g.velocity.length())
	g.knockback_velocity = Vector3.ZERO
	g.take_damage(0.01, false, null, Vector3(5, 0, 0))
	check_near(g.knockback_velocity.x, 5.0 * Enemy.KNOCKBACK_VELOCITY_PER_UNIT * 0.7, 0.001, "knockback (30% resisted)")


func test_coins_per_hit_interval_and_cap() -> void:
	var g := _goblin(Vector3(0, 0, 0))
	g.take_damage(0.01)
	g.take_damage(0.01)
	check_eq(g.coins_dropped, 1, "one coin per COIN_INTERVAL")
	check_eq(_gold_on_ground(), 1, "1 gold")
	check_eq(_xp_on_ground(), 0, "no XP in coins")
	g._age += 0.15
	g.take_damage(0.01)
	check_eq(g.coins_dropped, 2, "0.15 s later: another")
	g._age += 0.1
	g.take_damage(0.01)
	check_eq(g.coins_dropped, 2, "0.1 s later: not yet")
	g.take_damage(0.0)
	g._age += 0.2
	g.take_damage(0.0)
	check_eq(g.coins_dropped, 2, "no damage, no coin")
	for i in 40:
		g._age += 0.2
		g.take_damage(0.01)
	check_eq(g.coins_dropped, LootGoblin.MAX_COINS, "at most 30 per goblin")
	check_eq(_gold_on_ground(), 30, "30 gold")
	for c in _pickups():
		check(EFakes.flat_distance((c as Node3D).global_position, g.global_position) < 1.0, "next to it")


func test_portal_opens_at_15_s_and_the_goblin_escapes() -> void:
	_make_director()
	var g := spawner.spawn_goblin()
	check(g != null, "spawned through the spawner")
	if g == null:
		return
	check_eq(announcements.size(), 1, "appeared")
	check_eq(g.escape_time, GoblinSpawner.ESCAPE_TIME, "15 s")
	g._age = GoblinSpawner.ESCAPE_TIME - 0.1
	EFakes.step(g, 0.05)
	check(not g.is_opening_portal() and g.portal == null, "not yet")
	EFakes.step(g, 0.1)
	check(g.is_opening_portal(), "opening")
	check(g.portal != null and g.portal.get_parent() == g, "a GoblinPortal at its back")
	EFakes.step(g, DT)
	var at := g.global_position
	EFakes.step(g, 0.5)
	check(g.global_position.is_equal_approx(at), "stands still while it opens")
	check(g.portal.progress > 0.3 and g.portal.progress < 0.7, "half open (%.2f)" % g.portal.progress)
	var hp := g.hp
	g.take_damage(1.0)
	check(g.hp < hp and g.coins_dropped == 1, "still hittable")
	EFakes.step(g, 0.7)
	check(g.has_escaped(), "escaped after 1.2 s")
	check(g.is_dead() and not g.is_in_group(&"enemies") and g.is_queued_for_deletion(), "gone")
	check_eq(RunState.goblins_escaped, 1, "escape counted")
	check_eq(RunState.goblins_killed, 0, "not a kill")
	check(spawner.goblin == null, "the spawner forgot it")
	check_eq(announcements.back(), ["The Loot Goblin escaped!", GoblinSpawner.ESCAPED_COLOR], "grey banner")
	check(EFakes.live_children_of_type(world, LootBag).is_empty(), "no item")
	check_eq(_gold_on_ground(), 1, "only the coin of the hit")


func test_killed_while_the_portal_opens() -> void:
	var g := _goblin(Vector3.ZERO)
	g._age = GoblinSpawner.ESCAPE_TIME
	EFakes.step(g, 0.2)
	check(g.is_opening_portal(), "opening")
	g.take_damage(g.hp + 1.0)
	check(g.is_dead(), "killed")
	EFakes.step(g, 2.0)
	check(not g.has_escaped() and RunState.goblins_escaped == 0, "a dead goblin does not escape")
	check_eq(RunState.goblins_killed, 1, "a kill")


# --- LootGoblin: rewards ---------------------------------------------------------------

func test_kill_reward_formulas() -> void:
	# Wave 3 (shipped data): grunt 1.0 / candlekin 0.8 / gurgler 0.7 weight, 1 gold each,
	# XP 1 / 1 / 2 -> 1.0 gold and 1.28 XP on average.
	check_near(LootGoblin.average_gold(3), 1.0, 0.0001, "average gold, wave 3")
	check_near(LootGoblin.average_xp(3), 1.28, 0.0001, "average XP, wave 3")
	check_eq(LootGoblin.kill_gold(3), 30, "30 x average gold")
	check_eq(LootGoblin.kill_xp(3), 32, "25 x average XP")
	for w in [3, 5, 12, 24]:
		var total := 0.0
		var gold := 0.0
		var xp := 0.0
		for d in WaveDirector.eligible_enemies(w):
			total += d.spawn_weight
			gold += d.spawn_weight * d.gold
			xp += d.spawn_weight * d.xp
		check_eq(LootGoblin.kill_gold(w), roundi(30.0 * gold / total), "wave %d gold" % w)
		check_eq(LootGoblin.kill_xp(w), roundi(25.0 * xp / total), "wave %d XP" % w)


func test_kill_rewards_without_elite_rewards() -> void:
	RunState.set_wave(5)
	RunState.special_killed.connect(_on_special_killed)
	var killer := EFakes.spawn_player(world, Vector3(-6, 0, 0), 2)
	# 100% normal drop chance: a normal drop roll would certainly drop something.
	killer.stats.set_source(&"test", {Stats.FORTUNE: 2000.0})
	check_eq(LootDrops.drop_chance(killer), 1.0, "a sure normal drop")
	var g := _goblin(Vector3(2, 0, 3), 5)
	var affix: Variant = g.get(&"elite_affix")
	check(affix == null or StringName(affix) == &"", "no elite affix")
	check(g.is_elite() and not g.is_boss(), "elite for Slayer / targeting, not a boss")
	g.take_damage(g.hp + 1.0, false, killer)
	check(g.is_dead(), "killed")
	check_eq(g.coins_dropped, 1, "the killing hit spills a coin too")
	check_eq(_gold_on_ground(), LootGoblin.kill_gold(5) + 1, "30 x average gold (+ the coin)")
	check_eq(_xp_on_ground(), LootGoblin.kill_xp(5), "25 x average XP")
	check(LootGoblin.kill_gold(5) != EliteAffixes.GOLD, "not the elite 10 gold")
	check_eq(_pickups().size(), LootGoblin.KILL_PILES + 1, "8 piles + the coin")
	var bags := EFakes.live_children_of_type(world, LootBag)
	check_eq(bags.size(), 1, "exactly one item: no normal roll, no elite drop")
	if bags.size() == 1:
		var item := (bags[0] as LootBag).item
		check(item.looted and item.rarity >= Items.Rarity.RARE, "Rare+ goblin drop")
	check_eq(RunState.loot_drops_this_wave, 0, "not counted against the drop cap")
	check_eq(RunState.goblins_killed, 1, "goblin kill counted")
	check_eq(RunState.elites_killed, 0, "not an elite kill")
	check_eq(specials, [[&"goblin", 2]] as Array[Array], "special kill with the killer's slot")


func test_epic_share_of_goblin_drops() -> void:
	RunState.set_wave(12)
	var epic := 0
	for i in 60:
		var g := _goblin(Vector3(0, 0, 0), 12)
		g.take_damage(g.hp + 1.0)
		for node in EFakes.live_children_of_type(world, LootBag):
			var bag := node as LootBag
			check(bag.item.rarity >= Items.Rarity.RARE, "Rare+")
			if bag.item.rarity >= Items.Rarity.EPIC:
				epic += 1
			bag.free()
		for node in _pickups():
			node.free()
	check(epic >= 5 and epic <= 30, "about 25%% Epic+ (%d / 60)" % epic)


func test_execute_treats_it_like_a_normal_enemy() -> void:
	var g := _goblin(Vector3.ZERO)
	g.hp = g.max_hp * 0.1
	check(WarriorExecute.is_executable(g, 20.0), "below the threshold it can be executed (not a boss)")


# --- Look ------------------------------------------------------------------------------

func test_name_tag_and_portal_look() -> void:
	var g := _goblin(Vector3.ZERO)
	var tag := g.get_node_or_null(^"NameTag") as Label3D
	check(tag != null and tag == g.label, "a name tag")
	if tag != null:
		check_eq(tag.text, "Loot Goblin", "text")
		check(tag.no_depth_test and tag.billboard == BaseMaterial3D.BILLBOARD_ENABLED, "always readable")
		check(tag.modulate.r > 0.9 and tag.modulate.b < 0.5, "gold")
		check(tag.position.y > g.model.head_height, "above the head (and sack)")
	check(g.is_in_group(&"loot_goblins"), "findable")
	var portal := GoblinPortal.create()
	check(portal.get_node_or_null(^"Gate/Rim") != null and portal.get_node_or_null(^"Gate/Swirl") != null
			and portal.get_node_or_null(^"Ring") != null, "rim, swirl, ground ring")
	var small := (portal.get_node(^"Gate") as Node3D).scale.x
	portal.set_progress(1.0)
	check(small < 0.2 and is_equal_approx((portal.get_node(^"Gate") as Node3D).scale.x, 1.0), "grows open")
	var other := GoblinPortal.create()
	check((other.get_node(^"Gate/Swirl") as MeshInstance3D).mesh == (portal.get_node(^"Gate/Swirl") as MeshInstance3D).mesh,
			"shared meshes")
	portal.free()
	other.free()
