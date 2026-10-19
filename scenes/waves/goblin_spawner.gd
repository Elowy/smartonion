class_name GoblinSpawner
extends Node
## The Loot Goblin's spawner (GDD 8, M5, architecture §2.6): a child of the WaveDirector
## (PAUSABLE) that decides once per wave whether a Loot Goblin comes and when, spawns it and
## announces it ([signal announced] → Main → Hud.show_banner).
##
## - [signal WaveDirector.wave_started] (w): [method chance_for] (waves ≥ FIRST_WAVE except the
##   boss / elite waves 10, 20, 25; BASE_CHANCE + CHANCE_PER_FORTUNE per point of the luckiest
##   living hero's Fortune, at most MAX_CHANCE; [member chance_override] replaces it on
##   eligible waves). If it comes, [method roll_spawn_time]: SPAWN_MIN_TIME s ..
##   SPAWN_MAX_SHARE of the wave, skipped when less than ESCAPE_TIME + ESCAPE_MARGIN s would
##   remain. At most one goblin per wave.
## - At that time (the director's clock): a [LootGoblin] at [method WaveDirector.find_spawn_point]
##   under the arena's entities, a gold sparkle, "A Loot Goblin appeared!" (gold),
##   RunState.goblins_spawned += 1; the appearance jingle plays (Audio "goblin_appear").
## - Its escape ([signal LootGoblin.escaped]) is announced: "The Loot Goblin escaped!" (grey).
## - [signal WaveDirector.wave_cleared] / a new wave cancel a pending spawn; a living goblin
##   is despawned by [method WaveDirector.stop] like any enemy (no loot).
##
## Determinism (RunState.rng): the draws happen in [signal WaveDirector.wave_started], inside
## WaveDirector.start_wave after the elite schedule and the first group choice and before the
## opening group's telegraph draws – one draw for the chance when it is above 0, then one for
## the time only when the goblin comes. The goblin's own draws (Enemy.setup, its jinks) come
## during the wave.

## Banner text for the HUD ("A Loot Goblin appeared!", gold / "The Loot Goblin escaped!", grey).
signal announced(text: String, color: Color)

const BASE_CHANCE := 0.15
## Chance added per point of the team's highest Fortune.
const CHANCE_PER_FORTUNE := 0.005
const MAX_CHANCE := 0.5
## Seconds before the goblin opens its portal.
const ESCAPE_TIME := 15.0
## First wave a goblin may come in.
const FIRST_WAVE := 3
## Spawn window: from SPAWN_MIN_TIME s to SPAWN_MAX_SHARE of the wave's duration ...
const SPAWN_MIN_TIME := 3.0
const SPAWN_MAX_SHARE := 0.35
## ... and only if ESCAPE_TIME + this many seconds of the wave remain after it.
const ESCAPE_MARGIN := 3.0
const APPEARED_TEXT := "A Coin Gremlin appeared!"
const ESCAPED_TEXT := "The Coin Gremlin escaped!"
const APPEARED_COLOR := UiTheme.GOLD
const ESCAPED_COLOR := Color(0.7, 0.7, 0.72)

## --goblin-chance (0..1; < 0 = the normal chance). RunState.start_run resets it to -1, then Main
## applies the launch option.
static var chance_override := -1.0

var director: WaveDirector
## The goblin of the current wave (null before it spawns, after it died / escaped / the wave
## ended).
var goblin: LootGoblin

## Wave being run and its duration (s).
var _wave := 0
var _duration := 0.0
## Seconds into the wave the goblin spawns; < 0 = none (pending).
var _spawn_at := -1.0


static func create(p_director: WaveDirector) -> GoblinSpawner:
	var s := GoblinSpawner.new()
	s.name = "GoblinSpawner"
	s.director = p_director
	return s


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


## Spawn chance in wave [param wave] with the team's highest Fortune [param fortune] (0 below
## FIRST_WAVE and on boss / elite waves; [member chance_override] on the others when set).
static func chance_for(wave: int, fortune: float) -> float:
	if wave < FIRST_WAVE or RunState.is_boss_wave(wave) or RunState.is_elite_wave(wave):
		return 0.0
	if chance_override >= 0.0:
		return clampf(chance_override, 0.0, 1.0)
	return minf(BASE_CHANCE + CHANCE_PER_FORTUNE * maxf(0.0, fortune), MAX_CHANCE)


## Highest Fortune of the living heroes (PlayerManager slots; 0 without any).
static func team_fortune() -> float:
	var best := 0.0
	for s in PlayerManager.get_slots():
		if not Enemy.is_living_player(s.player):
			continue  # (also a freed hero: checked before the cast)
		var p := s.player as Player
		if p.stats != null:
			best = maxf(best, p.stats.get_stat(Stats.FORTUNE))
	return best


## One draw: seconds into a wave of [param duration] s the goblin appears, uniform in
## [SPAWN_MIN_TIME, max(SPAWN_MIN_TIME, SPAWN_MAX_SHARE x duration)]; -1 when less than
## ESCAPE_TIME + ESCAPE_MARGIN s would remain after it (no goblin).
static func roll_spawn_time(duration: float, rng: RandomNumberGenerator) -> float:
	var t := rng.randf_range(SPAWN_MIN_TIME, maxf(SPAWN_MIN_TIME, SPAWN_MAX_SHARE * duration))
	if duration - t < ESCAPE_TIME + ESCAPE_MARGIN:
		return -1.0
	return t


## Seconds into the wave it will spawn (-1 = none this wave, or it already came).
func pending_time() -> float:
	return _spawn_at


## Rolls wave [param wave] (normally from [signal WaveDirector.wave_started]): chance, then
## time. Forgets the previous wave's pending spawn and goblin.
func roll_wave(wave: int) -> void:
	_wave = wave
	_duration = RunState.wave_duration(wave)
	_spawn_at = -1.0
	goblin = null
	var chance := chance_for(wave, team_fortune())
	if chance <= 0.0 or RunState.rng.randf() >= chance:
		return
	_spawn_at = roll_spawn_time(_duration, RunState.rng)


## Seconds since the current wave started (the director's clock).
func wave_elapsed() -> float:
	if director == null or not is_instance_valid(director):
		return 0.0
	return _duration - director.time_left


func _physics_process(_delta: float) -> void:
	if _spawn_at < 0.0 or director == null or not is_instance_valid(director) or not director.is_running():
		return
	if wave_elapsed() + 0.0001 >= _spawn_at:
		_spawn_at = -1.0
		spawn_goblin()


## Spawns this wave's goblin now (normally at [method pending_time]). Returns it (null when
## there is no data / arena).
func spawn_goblin() -> LootGoblin:
	var data := LootGoblin.goblin_data()
	var parent := _spawn_parent()
	if data == null or parent == null:
		return null
	var pos := director.find_spawn_point() if director != null and is_instance_valid(director) else Vector3.ZERO
	var g := LootGoblin.create(data, maxi(1, _wave if _wave > 0 else RunState.wave))
	var parent_3d := parent as Node3D
	if parent_3d != null and parent_3d.is_inside_tree():
		g.position = parent_3d.global_transform.affine_inverse() * pos
	else:
		g.position = pos
	parent.add_child(g)
	goblin = g
	g.escaped.connect(_on_goblin_escaped)
	g.tree_exiting.connect(_on_goblin_left.bind(g))
	RunState.goblins_spawned += 1
	Vfx.explosion(pos + Vector3.UP * 0.3, 1.0, LootGoblin.COIN_COLOR)
	Vfx.pickup_sparkle(pos + Vector3.UP * 0.9)
	Audio.play(&"goblin_appear")
	announced.emit(APPEARED_TEXT, APPEARED_COLOR)
	return g


func _on_wave_started(wave: int) -> void:
	roll_wave(wave)


func _on_wave_cleared(_wave_number: int) -> void:
	_spawn_at = -1.0
	goblin = null


func _on_goblin_escaped(g: LootGoblin) -> void:
	if g == goblin:
		goblin = null
	Audio.play(&"goblin_escape")
	announced.emit(ESCAPED_TEXT, ESCAPED_COLOR)


## The goblin left the tree (killed, escaped, despawned by the director's stop() – also a stop
## without wave_cleared, such as a wipe): forget it, so [member goblin] never holds a freed node.
func _on_goblin_left(g: LootGoblin) -> void:
	if g == goblin:
		goblin = null


## The arena's entity root (the director's arena, else Arena.current), else null.
func _spawn_parent() -> Node:
	var a: Arena = null
	if director != null and is_instance_valid(director) and director.arena != null and is_instance_valid(director.arena):
		a = director.arena
	elif Arena.current != null and is_instance_valid(Arena.current):
		a = Arena.current
	if a != null and is_instance_valid(a.entities) and a.entities.is_inside_tree():
		return a.entities
	return null
