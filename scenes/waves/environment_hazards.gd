class_name EnvironmentHazards
extends Node
## The hazard director of an arena environment (GDD 16.1, M6b ENV): a child of the WaveDirector (like
## the GoblinSpawner and the EventSpawner) that lays the environment's hazards on the ground while a
## wave runs, as EnvironmentHazards (EnemyHazards: group enemy_hazards, the bots step out of them,
## WaveDirector.stop() frees them at the wave end). The hazard of the run is
## [member EnvironmentData.hazard_id]:
##
##   grasping_hands   (Cemetery)  every ~9 s: 2-3 circles (r 1.5) under the heroes, 1 s telegraph, a hit
##                                for 0.5x grunt damage and a 1.2 s root
##   bog_pools        (Swamp)     5 pools (r 2.3) for the whole wave, at the same places all run: heroes
##                                inside -30% move speed, enemies -15%
##   lava_vents       (Volcano)   6 fixed vents; each erupts every ~8 s (1 s telegraph, r 2): 1.5x grunt
##                                damage to heroes AND enemies
##   falling_icicles  (Ice Cave)  every ~7 s: 3 circles (r 1.2) near the heroes, 1 s telegraph, 1x grunt
##                                damage and a 30% chill for 1.5 s
##
## "Grunt damage" is the Skeleton Grunt's contact damage at the wave (its damage growth) times the
## party-size factor RunState.coop_damage_mult() – [method grunt_damage]. On a boss wave the hazards run
## at HALF rate ([constant BOSS_WAVE_RATE]: twice the interval; the Swamp lays 3 of its 5 pools).
## Forest Ruin has no hazard: the director then does nothing.
##
## Randomness: every draw comes from RunState.environment_rng (seeded from the run seed, see
## RunState.start_run), never from RunState.rng, so the hazards never shift the fight's own rolls. The
## Swamp's pool places are drawn once, on the first wave, and kept for the run.

const GRASPING_HANDS := &"grasping_hands"
const BOG_POOLS := &"bog_pools"
const LAVA_VENTS := &"lava_vents"
const FALLING_ICICLES := &"falling_icicles"
const HAZARD_IDS: Array[StringName] = [GRASPING_HANDS, BOG_POOLS, LAVA_VENTS, FALLING_ICICLES]

## The Skeleton Grunt (the hazards' damage yardstick) and the damage multiples of the hazards.
const GRUNT_ID := &"skeleton_grunt"
const HANDS_DAMAGE_MULT := 0.5
const LAVA_DAMAGE_MULT := 1.5
const ICICLE_DAMAGE_MULT := 1.0

## Grasping Hands.
const HANDS_INTERVAL := 9.0
const HANDS_MIN := 2
const HANDS_MAX := 3
const HANDS_RADIUS := 1.5
const HANDS_TELEGRAPH := 1.0
const HANDS_ROOT := 1.2
## Bog pools.
const BOG_COUNT := 5
const BOG_RADIUS := 2.3
const BOG_HERO_SLOW := 30.0
const BOG_ENEMY_SLOW := 15.0
## Pools keep this far (m) from the arena centre (spawn ring, Spirit Healer), from the walls and from
## each other.
const BOG_CENTER_CLEARANCE := 4.5
const BOG_WALL_MARGIN := 3.0
const BOG_SPACING := 6.0
## Lava vents: the six fixed places (XZ metres; the volcano decor set draws the vents there), the
## eruptions' radius, telegraph and interval.
const LAVA_VENT_POINTS: Array[Vector3] = [
	Vector3(-12.0, 0.0, -6.0), Vector3(-12.0, 0.0, 6.0), Vector3(0.0, 0.0, -8.0),
	Vector3(0.0, 0.0, 8.0), Vector3(12.0, 0.0, -6.0), Vector3(12.0, 0.0, 6.0),
]
const LAVA_RADIUS := 2.0
const LAVA_TELEGRAPH := 1.0
const LAVA_INTERVAL := 8.0
## Falling icicles.
const ICICLE_INTERVAL := 7.0
const ICICLE_COUNT := 3
const ICICLE_RADIUS := 1.2
const ICICLE_TELEGRAPH := 1.0
const ICICLE_SLOW := 30.0
const ICICLE_SLOW_TIME := 1.5
## How close to a hero (m) an icicle's circle is laid.
const ICICLE_NEAR_MIN := 0.8
const ICICLE_NEAR_MAX := 3.2
## A second circle on the same hero lies this far (m) from him.
const EXTRA_CIRCLE_MIN := 1.6
const EXTRA_CIRCLE_MAX := 2.8
## The first cast of a wave comes this share of one interval after the wave starts.
const FIRST_CAST_SHARE := 0.45
## Boss waves: the share of the normal rate the hazards run at.
const BOSS_WAVE_RATE := 0.5

var director: WaveDirector
var environment: EnvironmentData
## The hazard of this run (EnvironmentData.hazard_id; &"" = none).
var kind: StringName = &""

# Counters of the run (SMOKE_RESULT "hazards", see [method stats]).
var hazards_laid := 0
var hero_hits := 0
var hero_damage := 0.0
var enemy_hits := 0
var enemy_damage := 0.0
var enemy_kills := 0

## The Swamp's pool places (drawn on the first wave, then kept).
var pool_points: Array[Vector3] = []

var _wave := 0
## Seconds into the wave (this director's own clock, counted while the director runs).
var _t := 0.0
## Seconds into the wave of the next cast (hands, icicles) / of each vent's next eruption.
var _next_cast := 0.0
var _vent_next: Array[float] = []
var _running := false


## The director of [param p_director]'s run for [param p_environment] (null = the forest: no hazard).
static func create(p_director: WaveDirector, p_environment: EnvironmentData = null) -> EnvironmentHazards:
	var h := EnvironmentHazards.new()
	h.name = "EnvironmentHazards"
	h.director = p_director
	h.environment = p_environment
	h.kind = p_environment.hazard_id if p_environment != null else &""
	return h


func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _enter_tree() -> void:
	if director == null:
		return
	if not director.wave_started.is_connected(_on_wave_started):
		director.wave_started.connect(_on_wave_started)
	if not director.wave_cleared.is_connected(_on_wave_cleared):
		director.wave_cleared.connect(_on_wave_cleared)


func _exit_tree() -> void:
	if director == null or not is_instance_valid(director):
		return
	if director.wave_started.is_connected(_on_wave_started):
		director.wave_started.disconnect(_on_wave_started)
	if director.wave_cleared.is_connected(_on_wave_cleared):
		director.wave_cleared.disconnect(_on_wave_cleared)


# --- Formulas (pure) ------------------------------------------------------------------------------

## The Skeleton Grunt's contact damage at [param wave] with the party-size factor: the yardstick of
## every hazard's damage (the wave's enemy damage growth and RunState.coop_damage_mult()).
static func grunt_damage(wave: int) -> float:
	var grunt: EnemyData = Db.enemies.get(GRUNT_ID)
	var base := grunt.contact_damage_at_wave(wave) if grunt != null else 1.0
	return base * RunState.coop_damage_mult()


## The hazard rate of [param wave]: 1, or BOSS_WAVE_RATE on a boss wave.
static func rate_mult(wave: int) -> float:
	return BOSS_WAVE_RATE if RunState.is_boss_wave(wave) else 1.0


## Seconds between two casts of [param hazard] on [param wave] (the base interval over the rate; 0 for a
## hazard that is not cast periodically).
static func interval_for(hazard: StringName, wave: int) -> float:
	var base := 0.0
	match hazard:
		GRASPING_HANDS:
			base = HANDS_INTERVAL
		LAVA_VENTS:
			base = LAVA_INTERVAL
		FALLING_ICICLES:
			base = ICICLE_INTERVAL
		_:
			return 0.0
	return base / rate_mult(wave)


## How many pools the Swamp lays on [param wave]: all of BOG_COUNT, half of them (rounded up) on a boss wave.
static func pool_count_for(wave: int) -> int:
	return BOG_COUNT if rate_mult(wave) >= 1.0 else ceili(float(BOG_COUNT) * BOSS_WAVE_RATE)


## Damage of one hit of [param hazard] on [param wave].
static func damage_for(hazard: StringName, wave: int) -> float:
	match hazard:
		GRASPING_HANDS:
			return grunt_damage(wave) * HANDS_DAMAGE_MULT
		LAVA_VENTS:
			return grunt_damage(wave) * LAVA_DAMAGE_MULT
		FALLING_ICICLES:
			return grunt_damage(wave) * ICICLE_DAMAGE_MULT
	return 0.0


## Whether the director has anything to do in this environment.
func has_hazard() -> bool:
	return kind in HAZARD_IDS


# --- Wave hooks -------------------------------------------------------------------------------------

func _on_wave_started(wave: int) -> void:
	begin_wave(wave)


func _on_wave_cleared(_wave: int) -> void:
	end_wave()


## The wave starts: the clock restarts, the first cast is scheduled, the Swamp lays its pools.
func begin_wave(wave: int) -> void:
	_wave = wave
	_t = 0.0
	_running = has_hazard()
	if not _running:
		return
	var interval := interval_for(kind, wave)
	_next_cast = interval * FIRST_CAST_SHARE
	if kind == LAVA_VENTS:
		_vent_next.clear()
		for i in LAVA_VENT_POINTS.size():
			# The first eruption of each vent, spread over one interval so they go off one after another.
			_vent_next.append(_next_cast + interval * float(i) / float(LAVA_VENT_POINTS.size()))
	elif kind == BOG_POOLS:
		_lay_pools()


## The wave ended: the hazards themselves are freed by WaveDirector.stop(); the chill / slow they put
## on the heroes ends with them.
func end_wave() -> void:
	_running = false
	if is_inside_tree():
		var tree := get_tree()
		GeneralBuff.clear(tree, BogPool.SLOW_KEY)
		GeneralBuff.clear(tree, FallingIcicle.CHILL_KEY)
		for node in tree.get_nodes_in_group(&"players"):
			var p := node as Player
			if p != null:
				p.rooted_left = 0.0


func _physics_process(delta: float) -> void:
	if not _running or director == null or not is_instance_valid(director) or not director.is_running():
		return
	_t += delta
	match kind:
		GRASPING_HANDS:
			if _t + 0.0001 >= _next_cast:
				_cast_hands()
				_next_cast += interval_for(kind, _wave)
		FALLING_ICICLES:
			if _t + 0.0001 >= _next_cast:
				_cast_icicles()
				_next_cast += interval_for(kind, _wave)
		LAVA_VENTS:
			for i in _vent_next.size():
				if _t + 0.0001 >= _vent_next[i]:
					_erupt(i)
					_vent_next[i] += interval_for(kind, _wave)


# --- Casts ----------------------------------------------------------------------------------------------

## Cemetery: HANDS_MIN..HANDS_MAX circles, one under each of that many heroes (picked in a random order;
## with fewer heroes than circles the extra ones lie beside a hero).
func _cast_hands() -> int:
	var heroes := _living_heroes()
	var parent := _hazard_parent()
	if heroes.is_empty() or parent == null:
		return 0
	var rng := RunState.environment_rng
	var count := rng.randi_range(HANDS_MIN, HANDS_MAX)
	var order := _shuffled(heroes, rng)
	var damage := damage_for(GRASPING_HANDS, _wave)
	for i in count:
		var hero: Player = order[i % order.size()]
		var pos := hero.global_position
		if i >= order.size():
			pos += _random_offset(rng, EXTRA_CIRCLE_MIN, EXTRA_CIRCLE_MAX)
		GraspingHands.spawn(parent, _inside_arena(pos), HANDS_RADIUS, HANDS_TELEGRAPH, damage, HANDS_ROOT, self)
		hazards_laid += 1
	return count


## Ice Cave: ICICLE_COUNT circles near the heroes (one per hero in a random order, wrapping round).
func _cast_icicles() -> int:
	var heroes := _living_heroes()
	var parent := _hazard_parent()
	if heroes.is_empty() or parent == null:
		return 0
	var rng := RunState.environment_rng
	var order := _shuffled(heroes, rng)
	var damage := damage_for(FALLING_ICICLES, _wave)
	for i in ICICLE_COUNT:
		var hero: Player = order[i % order.size()]
		var pos := hero.global_position + _random_offset(rng, ICICLE_NEAR_MIN, ICICLE_NEAR_MAX)
		FallingIcicle.spawn(parent, _inside_arena(pos), ICICLE_RADIUS, ICICLE_TELEGRAPH, damage,
				ICICLE_SLOW, ICICLE_SLOW_TIME, self)
		hazards_laid += 1
	return ICICLE_COUNT


## Volcano: vent [param index] erupts.
func _erupt(index: int) -> void:
	var parent := _hazard_parent()
	if parent == null or index < 0 or index >= LAVA_VENT_POINTS.size():
		return
	LavaEruption.spawn(parent, LAVA_VENT_POINTS[index], LAVA_RADIUS, LAVA_TELEGRAPH,
			damage_for(LAVA_VENTS, _wave), self)
	hazards_laid += 1


## Swamp: the wave's pools (the same places every wave; the places are drawn once).
func _lay_pools() -> void:
	var parent := _hazard_parent()
	if parent == null:
		return
	if pool_points.is_empty():
		pool_points = draw_pool_points(RunState.environment_rng, _arena())
	var count := mini(pool_count_for(_wave), pool_points.size())
	for i in count:
		BogPool.spawn(parent, pool_points[i], BOG_RADIUS, BOG_HERO_SLOW, BOG_ENEMY_SLOW, i, self)
		hazards_laid += 1


## [param count] pool places inside [param arena] (the default arena size when null): at least
## BOG_CENTER_CLEARANCE from the middle, BOG_WALL_MARGIN from the walls and BOG_SPACING from each other
## (rejection sampling, 60 tries a pool; the farthest try when none fits). Draws from [param rng].
static func draw_pool_points(rng: RandomNumberGenerator, arena: Arena = null, count: int = BOG_COUNT) -> Array[Vector3]:
	var bounds := arena.get_bounds() if arena != null and is_instance_valid(arena) else Rect2(-Arena.SIZE / 2.0, Arena.SIZE)
	bounds = bounds.grow(-BOG_WALL_MARGIN)
	var out: Array[Vector3] = []
	for _n in count:
		var best := Vector3.ZERO
		var best_score := -INF
		var placed := false
		for _try in 60:
			var p := Vector3(rng.randf_range(bounds.position.x, bounds.end.x), 0.0,
					rng.randf_range(bounds.position.y, bounds.end.y))
			var score := Vector2(p.x, p.z).length() - BOG_CENTER_CLEARANCE
			for q in out:
				score = minf(score, Vector2(p.x - q.x, p.z - q.z).length() - BOG_SPACING)
			if score >= 0.0:
				out.append(p)
				placed = true
				break
			if score > best_score:
				best_score = score
				best = p
		if not placed:
			out.append(best)
	return out


# --- Counters --------------------------------------------------------------------------------------------

func record_hero_hit(amount: float) -> void:
	hero_hits += 1
	hero_damage += amount


func record_enemy_hit(amount: float, killed: bool) -> void:
	enemy_hits += 1
	enemy_damage += amount
	if killed:
		enemy_kills += 1


## The run's hazard numbers (SMOKE_RESULT "hazards"): {id, laid, hero_hits, hero_damage, enemy_hits,
## enemy_damage, enemy_kills}.
func stats() -> Dictionary:
	return {
		"id": String(kind),
		"laid": hazards_laid,
		"hero_hits": hero_hits,
		"hero_damage": snappedf(hero_damage, 0.1),
		"enemy_hits": enemy_hits,
		"enemy_damage": snappedf(enemy_damage, 0.1),
		"enemy_kills": enemy_kills,
	}


# --- Helpers ----------------------------------------------------------------------------------------------

func _arena() -> Arena:
	if director != null and is_instance_valid(director) and director.arena != null and is_instance_valid(director.arena):
		return director.arena
	return Arena.current


## The arena's entity root (where the hazards go), else null.
func _hazard_parent() -> Node:
	var a := _arena()
	if a != null and is_instance_valid(a.entities) and a.entities.is_inside_tree():
		return a.entities
	return null


func _living_heroes() -> Array[Player]:
	var out: Array[Player] = []
	if not is_inside_tree():
		return out
	for p in Enemy.cached_players(get_tree()):
		if Enemy.is_living_player(p):
			out.append(p)
	return out


func _inside_arena(pos: Vector3) -> Vector3:
	var a := _arena()
	var p := a.clamp_point(pos, 0.8) if a != null else pos
	return Vector3(p.x, 0.0, p.z)


## A random offset of [param lo]..[param hi] metres in a random direction (two draws).
static func _random_offset(rng: RandomNumberGenerator, lo: float, hi: float) -> Vector3:
	var a := rng.randf() * TAU
	var d := rng.randf_range(lo, hi)
	return Vector3(cos(a) * d, 0.0, sin(a) * d)


## [param list] in a random order (Fisher-Yates, one draw per swap).
static func _shuffled(list: Array[Player], rng: RandomNumberGenerator) -> Array[Player]:
	var out := list.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Player = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out
