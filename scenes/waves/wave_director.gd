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
## Does not process while the tree is paused. Copes with enemies being freed at any time.

signal wave_started(wave: int)
signal wave_timer_changed(seconds_left: float)
signal wave_cleared(wave: int)
## Emitted for every enemy the director adds to the arena.
signal enemy_spawned(enemy: Enemy)

const MAX_ENEMIES := 150

const BASE_SPAWN_RATE := 0.9
const SPAWN_RATE_PER_WAVE := 0.22
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

var _running := false
var _pending: Array[PendingGroup] = []
var _pending_count := 0
var _eligible: Array[EnemyData] = []
var _next_data: EnemyData
var _next_count := 0
var _last_timer_step := -1


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
	time_left = RunState.wave_duration(wave)
	budget = 0.0
	spawned_this_wave = 0
	_running = true
	_last_timer_step = -1
	_eligible = eligible_enemies(wave)
	_choose_next_group()
	wave_started.emit(wave)
	_emit_timer(true)
	_telegraph_opening_group()


## Stops spawning, removes remaining enemies (no loot) and banks dropped pickups and loot bags.
func stop() -> void:
	_running = false
	_pending.clear()
	_pending_count = 0
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


# --- Queries / formulas -------------------------------------------------------------

## Spawn budget (enemies) per second at [param p_wave] with [param coop_mult]
## (RunState.coop_count_mult()).
static func spawn_rate(p_wave: int, coop_mult: float = 1.0) -> float:
	return (BASE_SPAWN_RATE + SPAWN_RATE_PER_WAVE * (maxi(1, p_wave) - 1)) * coop_mult


## Spawn budget per second of the current wave for the current team size.
func spawn_budget_per_second() -> float:
	return spawn_rate(wave, RunState.coop_count_mult())


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


## Spawn point for the next group, away from the living players, preferably where the
## camera shows it outside the HUD.
func find_spawn_point() -> Vector3:
	var tree := get_tree() if is_inside_tree() else null
	var a := _arena()
	var view := Rect2()
	if a != null and is_instance_valid(a.camera) and a.camera.is_inside_tree():
		view = a.camera.get_safe_ground_rect()
	return pick_spawn_point(a, RunState.rng, Enemy.living_player_positions(tree), MIN_PLAYER_DISTANCE,
		SPAWN_POINT_TRIES, view)


## Enemies currently alive in the tree.
func alive_count() -> int:
	return get_tree().get_node_count_in_group(&"enemies") if is_inside_tree() else 0


## Enemies telegraphed but not spawned yet.
func pending_count() -> int:
	return _pending_count


func pending_groups() -> int:
	return _pending.size()


# --- Frame update ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _running:
		return
	time_left = maxf(0.0, time_left - delta)
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
		if parent_3d != null and parent_3d.is_inside_tree():
			e.position = parent_3d.global_transform.affine_inverse() * pos
		else:
			e.position = pos
		parent.add_child(e)
		spawned_this_wave += 1
		enemy_spawned.emit(e)
		if not _running:
			return


func _emit_timer(force: bool) -> void:
	var step := ceili(time_left / TIMER_SIGNAL_STEP - 0.0001)
	if force or step != _last_timer_step:
		_last_timer_step = step
		wave_timer_changed.emit(time_left)


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
