class_name EventSpawner
extends Node
## The mid-wave event slot (GDD 16.1, M6b; the EVENTS package fills it): a child of the WaveDirector
## (PAUSABLE) wired exactly like the [GoblinSpawner] – created by Main.start_run, it listens to
## [signal WaveDirector.wave_started] / [signal WaveDirector.wave_cleared], announces through
## [signal announced] (Main shows a HUD banner) and keeps its randomness on its own RNG.
##
## What this base class does (the P0-B foundation):
## - [method roll_wave] (every wave start): [method is_eligible_wave] (wave >= FIRST_WAVE, not a boss
##   wave, not an elite-rule wave), then CHANCE (1 when [member RunState.event_override] names an
##   event), which event ([member RunState.event_override] or one of EVENT_IDS) and when
##   (START_MIN_SHARE .. START_MAX_SHARE of the wave's duration). At most one event per wave.
## - [method _physics_process]: at that time (the director's clock) [method start_event] runs
##   [method _spawn_event]. The base [method _spawn_event] spawns nothing and returns false: EVENTS
##   overrides it (Guarded Chest, Defend the Totem, Goblin Caravan), adds the event objects to the
##   group [constant GROUP] (the director's stop() frees them at the wave end) and bumps
##   [member RunState.events_completed] when the player side wins.
## - [method end_wave] (wave_cleared) forgets the pending event; EVENTS overrides it to clean up.
##
## Determinism: every draw comes from [member RunState.event_rng] (seeded once from the run seed, see
## RunState.start_run) and never from [member RunState.rng], so a seeded run plays the same whether
## or not events roll. Draw order in [method roll_wave]: chance (only on an eligible wave and only when
## the chance is below 1), then the event kind (only when no override and more than one kind), then
## the start share.

## Banner text for the HUD ([param color] is the banner colour).
signal announced(text: String, color: Color)

const GUARDED_CHEST := &"guarded_chest"
const DEFEND_TOTEM := &"defend_totem"
const GOBLIN_CARAVAN := &"goblin_caravan"
## Every event kind (--event=<id> takes one of these).
const EVENT_IDS: Array[StringName] = [GUARDED_CHEST, DEFEND_TOTEM, GOBLIN_CARAVAN]
## Node group of event objects (chests, totems, caravans, their guards' markers ...): freed by
## WaveDirector.stop().
const GROUP := &"event_objects"

## First wave an event may come in.
const FIRST_WAVE := 4
## Chance per eligible wave (without --event).
const CHANCE := 0.3
## The event starts between these shares of the wave's duration.
const START_MIN_SHARE := 0.2
const START_MAX_SHARE := 0.4

var director: WaveDirector
## The event rolled for the current wave (&"" = none); stays set after it started.
var event_id: StringName = &""

var _wave := 0
var _duration := 0.0
## Seconds into the wave the event starts; < 0 = none pending.
var _start_at := -1.0


static func create(p_director: WaveDirector) -> EventSpawner:
	var s := EventSpawner.new()
	s.name = "EventSpawner"
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


## Wave [param wave] may carry an event: from FIRST_WAVE, never a boss wave or an elite-rule wave
## (wave 20 in the normal mode; endless adds its own, see RunState.is_elite_wave).
static func is_eligible_wave(wave: int) -> bool:
	return wave >= FIRST_WAVE and not RunState.is_boss_wave(wave) and not RunState.is_elite_wave(wave)


## Chance that wave [param wave] carries an event: 0 when not eligible, 1 when --event forces one,
## else CHANCE.
static func chance_for(wave: int) -> float:
	if not is_eligible_wave(wave):
		return 0.0
	if RunState.event_override != &"":
		return 1.0
	return CHANCE


## One draw: the share of a wave at which the event starts.
static func roll_start_share(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(START_MIN_SHARE, START_MAX_SHARE)


## Seconds into the current wave the pending event starts (-1 = none pending).
func pending_time() -> float:
	return _start_at


## Rolls wave [param wave] (normally from [signal WaveDirector.wave_started]); forgets the previous
## wave's pending event first. Returns the event id rolled (&"" = none).
func roll_wave(wave: int) -> StringName:
	_wave = wave
	_duration = RunState.wave_duration(wave)
	_start_at = -1.0
	event_id = &""
	var chance := chance_for(wave)
	if chance <= 0.0:
		return event_id
	var rng := RunState.event_rng
	if chance < 1.0 and rng.randf() >= chance:
		return event_id
	if RunState.event_override != &"" and RunState.event_override in EVENT_IDS:
		event_id = RunState.event_override
	else:
		event_id = EVENT_IDS[rng.randi() % EVENT_IDS.size()]
	_start_at = roll_start_share(rng) * _duration
	return event_id


## Seconds since the current wave started (the director's clock).
func wave_elapsed() -> float:
	if director == null or not is_instance_valid(director):
		return 0.0
	return _duration - director.time_left


func _physics_process(_delta: float) -> void:
	if _start_at < 0.0 or director == null or not is_instance_valid(director) or not director.is_running():
		return
	if wave_elapsed() + 0.0001 >= _start_at:
		_start_at = -1.0
		start_event(event_id)


## Starts event [param id] now (normally at [method pending_time]); counts it in
## [member RunState.events_spawned] when [method _spawn_event] built it. Returns whether it did.
func start_event(id: StringName) -> bool:
	if not _spawn_event(id):
		return false
	RunState.events_spawned += 1
	return true


## EVENTS hook: builds event [param id] for the current wave (objects under the arena's entities in
## the group GROUP, guards through the director, a banner through [signal announced]) and returns
## true. The base class has no events and returns false.
func _spawn_event(_id: StringName) -> bool:
	return false


## EVENTS hook: the wave ended (cleared, or a new one started): clean up what the event left.
func end_wave() -> void:
	_start_at = -1.0


func _on_wave_started(wave: int) -> void:
	roll_wave(wave)


func _on_wave_cleared(_wave_number: int) -> void:
	end_wave()


## The arena's entity root (the director's arena, else Arena.current), else null – where an event
## puts its objects.
func spawn_parent() -> Node:
	var a: Arena = null
	if director != null and is_instance_valid(director) and director.arena != null and is_instance_valid(director.arena):
		a = director.arena
	elif Arena.current != null and is_instance_valid(Arena.current):
		a = Arena.current
	if a != null and is_instance_valid(a.entities) and a.entities.is_inside_tree():
		return a.entities
	return null
