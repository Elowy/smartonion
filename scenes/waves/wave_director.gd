class_name WaveDirector
extends Node
## Runs one wave at a time (GDD 1, 9): timer, telegraphed spawns, co-op scaling.
##
## - Duration RunState.wave_duration(w). The timer is reported through
##   [signal wave_timer_changed] every TIMER_SIGNAL_STEP seconds.
## - A spawn budget accumulates at [method spawn_rate] per second (1 budget = 1 enemy).
##   The next group (weighted pick among Db.enemies with first_wave <= w, size in
##   [group_min, group_max]) is telegraphed once the budget covers it.
## - Each group gets a point >= MIN_PLAYER_DISTANCE from every living player – preferably
##   on screen outside the HUD (CameraRig.get_safe_ground_rect), else anywhere – a red rune
##   (Vfx.spawn_telegraph) and appears TELEGRAPH_TIME later, scattered around the point.
## - At most MAX_ENEMIES alive + telegraphed. A small opening group is telegraphed at once.
## - When the timer runs out: [method stop] (enemies despawn without loot, telegraphs are
##   cancelled, pickups and loot bags are banked), then [signal wave_cleared].
## - Elites (M5, GDD 8): at wave start [method EliteAffixes.schedule] picks this wave's elite
##   spawn times (15–70% of the duration). When a group hatches, its enemies are walked in
##   group order and each pops at most one time that has passed: that enemy becomes an elite
##   ([method Enemy.make_elite] with [method EliteAffixes.roll_affix], before add_child) – two
##   due times make the first two enemies elite, never one enemy twice. RunState.elites_spawned
##   counts them; elites count towards MAX_ENEMIES. Times left at the wave end are dropped.
## - Boss waves (M6, GDD 8 "Bossok"; RunState.BOSS_WAVES with a [BossData] in Db.bosses): there
##   is no timer. A telegraphed [Boss] arrives BOSS_TELEGRAPH_TIME s after the wave starts, far
##   from the heroes ([member boss], [signal boss_spawned]); the usual spawning goes on at
##   BOSS_ADD_RATE_MULT of its rate (the adds; no elites, no Loot Goblin); the wave ends when
##   the boss dies ([signal boss_defeated], then [method _finish_wave] on the next tick: the rest
##   despawns, pickups and loot bags are banked like at a normal end). [member time_left] is a
##   huge number (BOSS_WAVE_TIME) that nobody reaches, so code that forces the end by setting it
##   to 0 keeps working. A boss wave without a BossData in Db runs as a normal timed wave.
##   [method summon] is how a boss brings adds. In smoke runs ([member smoke_boss_timeout]) a boss
##   that lives SMOKE_BOSS_GRACE s past its enrage is killed ("SMOKE boss timeout"), so a run
##   always ends.
## - Elite wave (RunState.ELITE_WAVES, wave 20): every enemy gets an elite affix, a "lite" one
##   (HP x EliteAffixes.LITE_HP_MULT, normal rewards, a compact look; Enemy.make_elite); the real
##   elites (HP x3, elite rewards) come twice as often (EliteAffixes.expected_count).
## Does not process while the tree is paused. Copes with enemies being freed at any time.
##
## RunState.rng order inside [method start_wave]: eligible list (no draw) → elite schedule
## (count, then one time per elite; none on boss waves) → next group pick → [signal wave_started]
## (the GoblinSpawner draws there) → the opening group's telegraph (its type and size) → on a
## boss wave the boss's spawn point.

signal wave_started(wave: int)
signal wave_timer_changed(seconds_left: float)
signal wave_cleared(wave: int)
## Emitted for every enemy the director adds to the arena.
signal enemy_spawned(enemy: Enemy)
## A boss wave's boss arrived (the HUD shows its frame) / died (the wave ends right after).
signal boss_spawned(boss: Boss)
signal boss_defeated(boss: Boss)

const MAX_ENEMIES := 150

const BASE_SPAWN_RATE := 0.9
## Kept low: every kill pays gold and XP, so the enemy count drives the economy (and the
## waves get longer anyway); the late-game threat comes from EnemyData's HP / damage growth.
const SPAWN_RATE_PER_WAVE := 0.08
const TELEGRAPH_TIME := 1.0
const TELEGRAPH_RADIUS := 1.0
## Spawn points keep this far (m) from the arena walls.
const SPAWN_MARGIN := 2.0
const MIN_PLAYER_DISTANCE := 6.0
const SPAWN_POINT_TRIES := 8
## Enemies of a group appear on a ring of about this radius (m) around the marker.
const GROUP_SCATTER := 0.8
## Size of the opening group for one player (scaled by RunState.coop_count_mult()).
const OPENING_GROUP_SIZE := 2
## No new telegraphs when less than this many seconds are left (they would never hatch).
const LAST_TELEGRAPH_TIME := TELEGRAPH_TIME + 0.1
## Max new groups telegraphed per physics frame.
const MAX_GROUPS_PER_FRAME := 4
const TIMER_SIGNAL_STEP := 0.1

## Boss waves: [member time_left] at the start (the boss, not the clock, ends the wave).
const BOSS_WAVE_TIME := 1.0e6
## Boss waves: the share of the normal spawn rate that goes on (the boss's adds).
const BOSS_ADD_RATE_MULT := 0.5
## Boss waves: seconds between the boss's rune appearing and the boss, its radius (m), and the
## least distance (m) from every living hero it is placed at.
const BOSS_TELEGRAPH_TIME := 2.0
const BOSS_TELEGRAPH_RADIUS := 2.6
const BOSS_MIN_PLAYER_DISTANCE := 10.0
## Smoke runs: a boss still alive this many seconds after its enrage starts is killed.
const SMOKE_BOSS_GRACE := 120.0


## A telegraphed group waiting to appear.
class PendingGroup extends RefCounted:
	var data: EnemyData
	var count := 1
	var position := Vector3.ZERO
	var time_left := 0.0
	var ring := 0.0


var arena: Arena
var time_left := 0.0
## The wave currently (or last) running.
var wave := 0
## Unspent spawn budget (enemies).
var budget := 0.0
## Enemies spawned during the current wave.
var spawned_this_wave := 0
## Elites spawned during the current wave.
var elites_this_wave := 0
## Length (s) of the current wave.
var duration := 0.0

var _running := false
var _pending: Array[PendingGroup] = []
var _pending_count := 0
var _eligible: Array[EnemyData] = []
var _next_data: EnemyData
var _next_count := 0
var _last_timer_step := -1
## Elite spawn times of this wave not used yet (seconds into the wave, ascending).
var _elite_times: Array[float] = []

## The boss of the running (or last) boss wave (null before it arrives and on normal waves;
## dead or freed once it died) and the definition of this wave's boss (null on a normal wave).
var boss: Boss
var boss_data: BossData
## Smoke runs only (Main sets it): kill a boss that outlives its enrage by SMOKE_BOSS_GRACE.
var smoke_boss_timeout := false
## This wave is an elite wave (wave 20): every spawn gets a lite affix.
var elite_wave := false

var _boss_arrival_left := -1.0
var _boss_arrival_pos := Vector3.ZERO
## The boss has arrived (kept apart from [member boss]: a freed boss compares equal to null) and
## has died.
var _boss_arrived := false
var _boss_dead := false


static func create(p_arena: Arena) -> WaveDirector:
	var d := WaveDirector.new()
	d.name = "WaveDirector"
	d.arena = p_arena
	return d


func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func is_running() -> bool:
	return _running


func start_wave(p_wave: int) -> void:
	_pending.clear()
	_pending_count = 0
	wave = maxi(1, p_wave)
	RunState.set_wave(wave)
	boss = null
	_boss_arrived = false
	_boss_dead = false
	_boss_arrival_left = -1.0
	boss_data = BossData.for_wave(wave) if RunState.is_boss_wave(wave) else null
	elite_wave = RunState.is_elite_wave(wave)
	time_left = BOSS_WAVE_TIME if boss_data != null else RunState.wave_duration(wave)
	duration = time_left
	budget = 0.0
	spawned_this_wave = 0
	elites_this_wave = 0
	_running = true
	_last_timer_step = -1
	_eligible = eligible_enemies(wave)
	if boss_data != null:
		_elite_times.clear()  # the boss is the elite of its wave
	else:
		_elite_times = EliteAffixes.schedule(wave, duration, RunState.player_count, RunState.rng)
	if not _elite_times.is_empty() or elite_wave:
		ElitePlate.prepare()
	_choose_next_group()
	wave_started.emit(wave)
	_emit_timer(true)
	_telegraph_opening_group()
	if boss_data != null:
		_announce_boss()


## Stops spawning, removes remaining enemies (no loot) and banks dropped pickups and loot bags.
func stop() -> void:
	_running = false
	_pending.clear()
	_pending_count = 0
	_elite_times.clear()
	budget = 0.0
	if not is_inside_tree():
		return
	var tree := get_tree()
	for node in tree.get_nodes_in_group(&"enemies"):
		var e := node as Enemy
		if e != null and is_instance_valid(e):
			e.despawn()
	for node in tree.get_nodes_in_group(&"pickups"):
		var p := node as Pickup
		if p != null and is_instance_valid(p):
			p.collect_to_bank()
	# Item bags on the ground go to the team loot (the loot roll after the wave).
	for node in tree.get_nodes_in_group(&"loot_bags"):
		var bag := node as LootBag
		if bag != null and is_instance_valid(bag):
			bag.collect_to_bank()
	# Axes still in flight would hit players during the break.
	for node in tree.get_nodes_in_group(&"projectiles"):
		var proj := node as Projectile
		if proj != null and proj.team == Projectile.TEAM_ENEMIES and not proj.is_queued_for_deletion():
			proj.queue_free()
	# Ability ground effects (Blizzard, Consecration, Rain of Fire) end with the wave instead
	# of resuming at the old spot in the next one.
	for node in tree.get_nodes_in_group(&"ability_areas"):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			node.queue_free()
	# Enemy ground hazards (the bosses' circles, cones, fields, meteors; poison puddles) and the
	# chill they put on heroes end with the wave too.
	for node in tree.get_nodes_in_group(EnemyHazard.GROUP):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			node.queue_free()
	GeneralBuff.clear(tree, FrostCircle.CHILL_KEY)


# --- Queries / formulas -------------------------------------------------------------

## Spawn budget (enemies) per second at [param p_wave] with [param coop_mult]
## (RunState.coop_count_mult()).
static func spawn_rate(p_wave: int, coop_mult: float = 1.0) -> float:
	return (BASE_SPAWN_RATE + SPAWN_RATE_PER_WAVE * (maxi(1, p_wave) - 1)) * coop_mult


## Spawn budget per second of the current wave for the current team size (BOSS_ADD_RATE_MULT of
## it on a boss wave).
func spawn_budget_per_second() -> float:
	var rate := spawn_rate(wave, RunState.coop_count_mult())
	return rate * BOSS_ADD_RATE_MULT if boss_data != null else rate


## Enemy types that may appear at [param p_wave] (first_wave <= p_wave, positive weight),
## in a deterministic order (by id).
static func eligible_enemies(p_wave: int) -> Array[EnemyData]:
	var out: Array[EnemyData] = []
	for data in Db.enemies.values():
		var d := data as EnemyData
		if d != null and d.first_wave <= p_wave and d.spawn_weight > 0.0:
			out.append(d)
	out.sort_custom(func(a: EnemyData, b: EnemyData) -> bool: return String(a.id) < String(b.id))
	return out


## Weighted random pick by spawn_weight (null for an empty list).
static func pick_weighted(list: Array[EnemyData], rng: RandomNumberGenerator) -> EnemyData:
	if list.is_empty():
		return null
	var total := 0.0
	for d in list:
		total += maxf(0.0, d.spawn_weight)
	if total <= 0.0:
		return list[0]
	var r := rng.randf() * total
	for d in list:
		var w := maxf(0.0, d.spawn_weight)
		if w <= 0.0:
			continue
		r -= w
		if r < 0.0:
			return d
	for i in range(list.size() - 1, -1, -1):
		if list[i].spawn_weight > 0.0:
			return list[i]
	return list[0]


## Random group size in [group_min, group_max] (at least 1).
static func roll_group_size(data: EnemyData, rng: RandomNumberGenerator) -> int:
	var lo := maxi(1, mini(data.group_min, data.group_max))
	var hi := maxi(lo, data.group_max)
	return rng.randi_range(lo, hi)


## A random arena point (SPAWN_MARGIN from the walls) at least [param min_distance] from
## every position in [param avoid]. With a [param preferred] rect (XZ; the camera's
## HUD-safe visible ground, see CameraRig.safe_ground_rect) the first 2 x [param tries]
## candidates are drawn inside it, so the telegraph is seen; if none is far enough from
## the players, [param tries] more come from the whole arena; after those the farthest
## candidate.
static func pick_spawn_point(p_arena: Arena, rng: RandomNumberGenerator, avoid: Array[Vector3],
		min_distance: float = MIN_PLAYER_DISTANCE, tries: int = SPAWN_POINT_TRIES,
		preferred: Rect2 = Rect2()) -> Vector3:
	var best := Vector3.ZERO
	var best_d := -1.0
	var min_sq := min_distance * min_distance
	var on_screen := _spawn_area(p_arena).intersection(preferred) if preferred.has_area() else Rect2()
	var rounds := 2 if on_screen.has_area() else 1
	for r in rounds:
		# The on-screen round gets twice the tries: four spread-out heroes' 6 m circles
		# cover much of the view.
		for i in maxi(1, tries) * (2 if r == 0 and rounds == 2 else 1):
			var p := _random_point_in(on_screen, rng) if r == 0 and rounds == 2 else _random_arena_point(p_arena, rng)
			var d := INF
			for a in avoid:
				var dx := p.x - a.x
				var dz := p.z - a.z
				d = minf(d, dx * dx + dz * dz)
			if d >= min_sq:
				return p
			if d > best_d:
				best_d = d
				best = p
	return best


## Spawn point for the next group, away from the living players and the Spirit Healer (a
## revived hero must not pop up inside a fresh group), preferably where the camera shows it
## outside the HUD.
func find_spawn_point() -> Vector3:
	var tree := get_tree() if is_inside_tree() else null
	var a := _arena()
	var view := Rect2()
	if a != null and is_instance_valid(a.camera) and a.camera.is_inside_tree():
		view = a.camera.get_safe_ground_rect()
	var avoid := Enemy.living_player_positions(tree)
	if a != null and is_instance_valid(a.spirit_healer):
		avoid.append(a.spirit_healer.global_position)
	return pick_spawn_point(a, RunState.rng, avoid, MIN_PLAYER_DISTANCE, SPAWN_POINT_TRIES, view)


## Enemies currently alive in the tree.
func alive_count() -> int:
	return get_tree().get_node_count_in_group(&"enemies") if is_inside_tree() else 0


## Enemies telegraphed but not spawned yet.
func pending_count() -> int:
	return _pending_count


func pending_groups() -> int:
	return _pending.size()


## Seconds since the current wave started.
func elapsed() -> float:
	return maxf(0.0, duration - time_left)


## Elite spawn times of this wave still waiting for a group (seconds into the wave, ascending).
func elite_times() -> Array[float]:
	return _elite_times.duplicate()


# --- Frame update ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _running:
		return
	time_left = maxf(0.0, time_left - delta)
	if boss_data != null:
		_update_boss(delta)
		if not _running:
			return
	if time_left <= 0.0:
		_finish_wave()
		return
	_update_pending(delta)
	if not _running:
		return
	var room := MAX_ENEMIES - alive_count() - _pending_count
	if room > 0:
		budget += spawn_budget_per_second() * delta
		if time_left > LAST_TELEGRAPH_TIME:
			_spend_budget()
	_emit_timer(false)


func _finish_wave() -> void:
	var finished := wave
	stop()
	wave_timer_changed.emit(0.0)
	wave_cleared.emit(finished)


func _spend_budget() -> void:
	for _i in MAX_GROUPS_PER_FRAME:
		if _next_data == null or budget < float(_next_count):
			return
		var room := MAX_ENEMIES - alive_count() - _pending_count
		if room <= 0:
			return
		var count := mini(_next_count, room)
		budget -= float(count)
		_telegraph(_next_data, count)
		_choose_next_group()


func _telegraph_opening_group() -> void:
	var data := pick_weighted(_eligible, RunState.rng)
	if data == null:
		return
	var size := maxi(roll_group_size(data, RunState.rng), roundi(OPENING_GROUP_SIZE * RunState.coop_count_mult()))
	var count := mini(size, MAX_ENEMIES - alive_count() - _pending_count)
	if count > 0:
		_telegraph(data, count)


func _choose_next_group() -> void:
	_next_data = pick_weighted(_eligible, RunState.rng)
	_next_count = roll_group_size(_next_data, RunState.rng) if _next_data != null else 0


func _telegraph(data: EnemyData, count: int) -> void:
	var g := PendingGroup.new()
	g.data = data
	g.count = count
	g.position = find_spawn_point()
	g.time_left = TELEGRAPH_TIME
	g.ring = _ring_radius(data, count)
	_pending.append(g)
	_pending_count += count
	Vfx.spawn_telegraph(g.position, maxf(TELEGRAPH_RADIUS, g.ring + 0.3), TELEGRAPH_TIME)


func _update_pending(delta: float) -> void:
	var i := 0
	while i < _pending.size():
		var g := _pending[i]
		g.time_left -= delta
		if g.time_left > 0.0:
			i += 1
			continue
		_pending.remove_at(i)
		_pending_count -= g.count
		_spawn_group(g)
		if not _running:
			return


func _spawn_group(g: PendingGroup) -> void:
	var parent := _spawn_parent()
	if parent == null or g.data == null:
		return
	var rng := RunState.rng
	var count := mini(g.count, MAX_ENEMIES - alive_count())
	var base_angle := rng.randf() * TAU
	var a := _arena()
	var parent_3d := parent as Node3D
	for i in count:
		var pos := g.position
		if g.count > 1:
			var angle := base_angle + TAU * float(i) / float(g.count) + rng.randf_range(-0.25, 0.25)
			var r := g.ring * rng.randf_range(0.7, 1.0)
			pos += Vector3(cos(angle) * r, 0.0, sin(angle) * r)
		if a != null:
			pos = a.clamp_point(pos, g.data.radius + 0.1)
		pos.y = 0.0
		var e := Enemy.create(g.data, wave)
		if _pop_due_elite_time():
			e.make_elite(EliteAffixes.roll_affix(rng))
			if e.is_elite():
				RunState.elites_spawned += 1
				elites_this_wave += 1
		elif elite_wave:
			# Elite wave: everybody else gets a lite affix (HP x1.5, normal rewards).
			e.make_elite(EliteAffixes.roll_affix(rng), true)
		if parent_3d != null and parent_3d.is_inside_tree():
			e.position = parent_3d.global_transform.affine_inverse() * pos
		else:
			e.position = pos
		parent.add_child(e)
		spawned_this_wave += 1
		enemy_spawned.emit(e)
		if not _running:
			return


## Pops the earliest elite time if it has passed (true = the enemy being spawned becomes an
## elite).
func _pop_due_elite_time() -> bool:
	if _elite_times.is_empty() or _elite_times[0] > elapsed() + 0.000001:
		return false
	_elite_times.remove_at(0)
	return true


func _emit_timer(force: bool) -> void:
	if boss_data != null:
		return  # the HUD shows the boss frame instead of the clock
	var step := ceili(time_left / TIMER_SIGNAL_STEP - 0.0001)
	if force or step != _last_timer_step:
		_last_timer_step = step
		wave_timer_changed.emit(time_left)


# --- Boss waves ------------------------------------------------------------------------------

## A point for the boss: preferably on screen, at least BOSS_MIN_PLAYER_DISTANCE from every
## living hero (and the Spirit Healer).
func find_boss_point() -> Vector3:
	var tree := get_tree() if is_inside_tree() else null
	var a := _arena()
	var view := Rect2()
	if a != null and is_instance_valid(a.camera) and a.camera.is_inside_tree():
		view = a.camera.get_safe_ground_rect()
	var avoid := Enemy.living_player_positions(tree)
	if a != null and is_instance_valid(a.spirit_healer):
		avoid.append(a.spirit_healer.global_position)
	return pick_spawn_point(a, RunState.rng, avoid, BOSS_MIN_PLAYER_DISTANCE, SPAWN_POINT_TRIES, view)


## Boss wave start: picks the boss's place (one rng draw round) and shows its rune.
func _announce_boss() -> void:
	_boss_arrival_pos = find_boss_point()
	_boss_arrival_left = BOSS_TELEGRAPH_TIME
	Vfx.spawn_telegraph(_boss_arrival_pos, BOSS_TELEGRAPH_RADIUS, BOSS_TELEGRAPH_TIME)


## One tick of a boss wave: the boss arrives, the smoke safety, and the wave ends the tick after
## the boss died.
func _update_boss(delta: float) -> void:
	if not _boss_arrived:
		if _boss_arrival_left >= 0.0:
			_boss_arrival_left -= delta
			if _boss_arrival_left <= 0.0:
				_boss_arrival_left = -1.0
				_spawn_boss()
		return
	if _boss_dead or not is_instance_valid(boss) or boss.is_dead():
		_finish_wave()
		return
	if smoke_boss_timeout and boss.age() >= boss_data.enrage_time + SMOKE_BOSS_GRACE:
		print("SMOKE boss timeout: %s still alive %.0f s after its enrage (phase %d, %.0f%% HP) - killed" % [
			boss_data.display_name, SMOKE_BOSS_GRACE, boss.phase, boss.hp_ratio() * 100.0])
		boss.kill()


func _spawn_boss() -> void:
	var parent := _spawn_parent()
	if parent == null or boss_data == null:
		return
	var b := Boss.create(boss_data, wave)
	b.director = self
	var pos := _boss_arrival_pos
	var a := _arena()
	if a != null:
		pos = a.clamp_point(pos, boss_data.radius * boss_data.model_scale * 0.5 + 0.2)
	pos.y = 0.0
	var parent_3d := parent as Node3D
	if parent_3d != null and parent_3d.is_inside_tree():
		b.position = parent_3d.global_transform.affine_inverse() * pos
	else:
		b.position = pos
	boss = b
	_boss_arrived = true
	_boss_dead = false
	b.died.connect(_on_boss_died)
	parent.add_child(b)
	spawned_this_wave += 1
	boss_spawned.emit(b)
	enemy_spawned.emit(b)


func _on_boss_died(dead: Enemy, _killer_index: int) -> void:
	if dead != boss:
		return
	_boss_dead = true
	boss_defeated.emit(dead as Boss)


## Adds [param count] enemies of [param add_data] on a ring of [param scatter] m around
## [param center] (a boss's Raise Dead / Imp Swarm), as many as MAX_ENEMIES allows. They count
## as spawned this wave, like any group member; nothing here draws from the rng except
## Enemy.setup. Returns the new enemies.
func summon(add_data: EnemyData, count: int, center: Vector3, scatter: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	var parent := _spawn_parent()
	if not _running or parent == null or add_data == null:
		return out
	var n := mini(count, MAX_ENEMIES - alive_count() - _pending_count)
	var a := _arena()
	var parent_3d := parent as Node3D
	for i in maxi(0, n):
		var angle := TAU * float(i) / float(maxi(1, n)) + 0.4
		var pos := center + Vector3(cos(angle), 0.0, sin(angle)) * scatter
		if a != null:
			pos = a.clamp_point(pos, add_data.radius + 0.1)
		pos.y = 0.0
		var e := Enemy.create(add_data, wave)
		if parent_3d != null and parent_3d.is_inside_tree():
			e.position = parent_3d.global_transform.affine_inverse() * pos
		else:
			e.position = pos
		parent.add_child(e)
		spawned_this_wave += 1
		Vfx.death_puff(pos + Vector3.UP * 0.4, add_data.color, maxf(0.6, add_data.model_scale))
		enemy_spawned.emit(e)
		out.append(e)
	return out


func _arena() -> Arena:
	if arena != null and is_instance_valid(arena):
		return arena
	return Arena.current


func _spawn_parent() -> Node:
	var a := _arena()
	if a != null and is_instance_valid(a.entities) and a.entities.is_inside_tree():
		return a.entities
	if a != null and a.is_inside_tree():
		return a
	return get_parent() if is_inside_tree() else null


static func _ring_radius(data: EnemyData, count: int) -> float:
	if count <= 1:
		return 0.0
	return maxf(GROUP_SCATTER, float(count) * (data.radius * 2.0 + 0.15) / TAU)


static func _random_arena_point(p_arena: Arena, rng: RandomNumberGenerator) -> Vector3:
	if p_arena != null and is_instance_valid(p_arena):
		return p_arena.random_point(rng, SPAWN_MARGIN)
	var b := Rect2(-Arena.SIZE / 2.0, Arena.SIZE).grow(-SPAWN_MARGIN)
	return Vector3(rng.randf_range(b.position.x, b.end.x), 0.0, rng.randf_range(b.position.y, b.end.y))


## Where spawn points may lie: the arena bounds shrunk by SPAWN_MARGIN.
static func _spawn_area(p_arena: Arena) -> Rect2:
	var b := p_arena.get_bounds() if p_arena != null and is_instance_valid(p_arena) else Rect2(-Arena.SIZE / 2.0, Arena.SIZE)
	return b.grow(-SPAWN_MARGIN)


static func _random_point_in(rect: Rect2, rng: RandomNumberGenerator) -> Vector3:
	return Vector3(rng.randf_range(rect.position.x, rect.end.x), 0.0, rng.randf_range(rect.position.y, rect.end.y))
