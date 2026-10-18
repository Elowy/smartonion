class_name EventSpawner
extends Node
## The mid-wave event spawner (GDD 16.1, M6b EVENTS): a child of the WaveDirector (PAUSABLE) wired exactly
## like the [GoblinSpawner] – created by Main.start_run, it listens to [signal WaveDirector.wave_started] /
## [signal WaveDirector.wave_cleared], announces through [signal announced] (Main shows a HUD banner) and
## keeps its randomness on its own RNG.
##
## Rolling (every wave start, [method roll_wave]): [method is_eligible_wave] (wave >= FIRST_WAVE, not a
## boss wave, not an elite-rule wave), then CHANCE (1 when [member RunState.event_override] names an
## event), which event ([member RunState.event_override] or one of EVENT_IDS) and when (START_MIN_SHARE ..
## START_MAX_SHARE of the wave's duration). At most one event per wave. At that time (the director's clock)
## [method start_event] runs [method _spawn_event], which builds the event:
##
## - GUARDED_CHEST: a [GuardedChest] with [constant GuardedChest.GUARD_COUNT] guards ([EventGuards]: types
##   drawn from the wave's eligible enemies by spawn weight, x2 HP, no affix) at a point away from the
##   heroes. Guards dead + a hero at the chest for 1.5 s: [signal GuardedChest.opened] – one Rare+ item (a
##   loot bag; the Need / Greed / Pass roll at the wave end, outside the drop limit) and 10 x the wave's
##   average enemy gold. Unopened at the wave end = failed.
## - DEFEND_TOTEM: a [DefendTotem] (30 x grunt HP). Enemies within 8 m go for it; alive after 20 s
##   ([signal DefendTotem.held]) = every hero gets +15% damage until the wave ends ([constant BUFF_SOURCE]
##   in the heroes' PlayerBonuses) and the team 25 x the wave's average enemy XP; fallen = failed.
## - GOBLIN_CARAVAN: a [CaravanCart] (40 x grunt HP, [constant CaravanCart.GUARD_COUNT] guards) crossing the
##   arena edge to edge in about 25 s. Killed ([signal CaravanCart.plundered]) = 40 x the wave's average
##   enemy gold and a Rare item; it reaches the far edge ([signal CaravanCart.escaped]) = "The caravan got
##   away", failed.
## Every event object joins the group [constant GROUP] (WaveDirector.stop() frees them at the wave end); each
## event ends once, with [method _finish]: [signal event_finished], RunState.events_completed when it was won,
## one "EVENT ..." log line. [method end_wave] (wave_cleared) settles an event still open (= failed), takes
## the totem buff off and forgets the objects. The camera frames the target (CameraRig.event_points) and bots
## play along (BotInput).
##
## Determinism: every draw of the spawner itself (the roll, the spot, the guard types, the cart's side and
## lane) comes from [member RunState.event_rng] (seeded once from the run seed, see RunState.start_run) and
## never from [member RunState.rng]; what the built objects do afterwards (Enemy.setup, the item) uses the
## gameplay rng like any other enemy / drop. Draw order in [method roll_wave]: chance (only on an eligible
## wave and only when the chance is below 1), then the event kind (only when no override and more than one
## kind), then the start share.

## Banner text for the HUD ([param color] is the banner colour).
signal announced(text: String, color: Color)
## An event ended: [param kind] (one of EVENT_IDS) and whether the team won it.
signal event_finished(kind: StringName, success: bool)

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

## EnemyData id of the Skeleton Grunt: the HP yardstick of the totem and the cart.
const GRUNT_ID := &"skeleton_grunt"
## The heroes' PlayerBonuses source of the totem's damage buff.
const BUFF_SOURCE := &"event"
## Event spots keep this far (m) from the living heroes (the chest: they have to walk; the totem: close
## enough to defend at once).
const CHEST_HERO_DISTANCE := 10.0
const TOTEM_HERO_DISTANCE := 4.0
## The cart's lane keeps this far (m) from the long walls.
const LANE_MARGIN := 3.5
## The cart's crossing ends this many seconds before the wave does (never shorter than
## CaravanCart.MIN_CROSS_TIME).
const CROSS_END_MARGIN := 2.0

## Banners.
const CHEST_TEXT := "A guarded chest appeared!"
const CHEST_OPENED_TEXT := "The chest was opened!"
const TOTEM_TEXT := "Defend the totem!"
const TOTEM_HELD_TEXT := "The totem holds!  +15% damage"
const TOTEM_FELL_TEXT := "The totem fell"
const CARAVAN_TEXT := "A goblin caravan is crossing!"
const CARAVAN_PLUNDERED_TEXT := "The caravan was plundered!"
const CARAVAN_ESCAPED_TEXT := "The caravan got away"
const EVENT_COLOR := UiTheme.GOLD
const TOTEM_COLOR := Color(0.45, 0.88, 0.95)
const FAIL_COLOR := Color(0.7, 0.7, 0.72)

var director: WaveDirector
## The event rolled for the current wave (&"" = none); stays set after it started.
var event_id: StringName = &""

## The objects of the event running this wave (null when none / not that kind / gone).
var chest: GuardedChest
var totem: DefendTotem
var cart: CaravanCart
## The kind of the event that started this wave (&"" = none yet) and how it ended: &"" (still open),
## &"completed" or &"failed".
var active_kind: StringName = &""
var result: StringName = &""

var _wave := 0
var _duration := 0.0
## Seconds into the wave the event starts; < 0 = none pending.
var _start_at := -1.0
var _buff_on := false


static func create(p_director: WaveDirector) -> EventSpawner:
	var s := EventSpawner.new()
	s.name = "EventSpawner"
	s.director = p_director
	return s


func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


## The event id [param text] names – an id of EVENT_IDS or its short form ("chest", "totem", "caravan") –
## else &"" (--event takes either).
static func parse_id(text: String) -> StringName:
	var t := text.strip_edges().to_lower()
	for id in EVENT_IDS:
		if t == String(id):
			return id
	match t:
		"chest":
			return GUARDED_CHEST
		"totem":
			return DEFEND_TOTEM
		"caravan":
			return GOBLIN_CARAVAN
	return &""


## HP of one Skeleton Grunt at [param wave] with the party's HP factor (what Enemy.setup gives a grunt):
## the yardstick of the totem (x30) and the cart (x40).
static func grunt_hp(wave: int) -> float:
	var grunt := Db.get_enemy(GRUNT_ID)
	var base := grunt.hp_at_wave(maxi(1, wave)) if grunt != null else 4.0
	return maxf(1.0, base * RunState.coop_hp_mult())


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
	_settle()
	active_kind = &""
	result = &""
	_wave = wave
	# The length the director counts this wave down from (its duration is set before wave_started is
	# emitted); the run's wave length when there is no director.
	var running := director != null and is_instance_valid(director)
	_duration = director.duration if running else RunState.wave_duration(wave)
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
	print("EVENT %s (wave %d): started at %.1f s" % [id, _event_wave(), wave_elapsed()])
	return true


# --- Building the events -------------------------------------------------------------

## Builds event [param id] for the current wave (objects under the arena's entities in the group GROUP,
## guards through the director, a banner through [signal announced]); true when it exists. Unknown ids,
## and a world without an arena, build nothing.
func _spawn_event(id: StringName) -> bool:
	var parent := spawn_parent()
	if parent == null or id not in EVENT_IDS:
		return false
	_settle()
	active_kind = id
	result = &""
	match id:
		GUARDED_CHEST:
			_spawn_chest(parent)
		DEFEND_TOTEM:
			_spawn_totem(parent)
		GOBLIN_CARAVAN:
			_spawn_caravan(parent)
	return true


func _spawn_chest(parent: Node) -> void:
	var c := GuardedChest.create(_event_wave())
	chest = c
	parent.add_child(c)
	var a := _arena()
	var pos := _event_point(CHEST_HERO_DISTANCE)
	if a != null:
		pos = a.clamp_point(pos, GuardedChest.POST_RADIUS + 0.4)
	_place(c, parent, pos)
	var datas := _pick_guard_datas(GuardedChest.GUARD_COUNT)
	c.guards.spawn_guards(datas, _event_wave(), GuardedChest.post_offsets(datas.size()),
			GuardedChest.GUARD_HP_MULT, parent, director)
	c.opened.connect(_on_chest_opened)
	Vfx.explosion(pos + Vector3.UP * 0.4, 1.4, GuardedChest.GOLD)
	announced.emit(CHEST_TEXT, EVENT_COLOR)


func _spawn_totem(parent: Node) -> void:
	var t := DefendTotem.create(_event_wave())
	totem = t
	parent.add_child(t)
	var pos := _event_point(TOTEM_HERO_DISTANCE)
	_place(t, parent, pos)
	t.held.connect(_on_totem_held)
	t.fell.connect(_on_totem_fell)
	Vfx.explosion(pos + Vector3.UP * 0.4, 1.6, DefendTotem.COLOR)
	announced.emit(TOTEM_TEXT, TOTEM_COLOR)


func _spawn_caravan(parent: Node) -> void:
	var a := _arena()
	var b := a.get_bounds() if a != null else Rect2(-Arena.SIZE / 2.0, Arena.SIZE)
	var rng := RunState.event_rng
	var left_to_right := rng.randf() < 0.5
	var lane := rng.randf_range(b.position.y + LANE_MARGIN, b.end.y - LANE_MARGIN)
	var x0 := b.position.x + CaravanCart.EDGE_MARGIN
	var x1 := b.end.x - CaravanCart.EDGE_MARGIN
	var from := Vector3(x0 if left_to_right else x1, 0.0, lane)
	var to := Vector3(x1 if left_to_right else x0, 0.0, lane)
	var c := CaravanCart.create_route(_event_wave(), from, to, _cross_time())
	cart = c
	parent.add_child(c)
	_place(c, parent, from)
	var datas := _pick_guard_datas(CaravanCart.GUARD_COUNT)
	c.guards.spawn_guards(datas, _event_wave(), CaravanCart.escort_offsets(datas.size(), c.route_dir()),
			1.0, parent, director)
	c.plundered.connect(_on_cart_plundered)
	c.escaped.connect(_on_cart_escaped)
	Vfx.explosion(from + Vector3.UP * 0.5, 1.6, Color(1.0, 0.82, 0.3))
	announced.emit(CARAVAN_TEXT, EVENT_COLOR)


## The seconds the cart takes to cross: CaravanCart.CROSS_TIME, less when the wave would end first.
func _cross_time() -> float:
	if director == null or not is_instance_valid(director) or not director.is_running():
		return CaravanCart.CROSS_TIME
	return clampf(director.time_left - CROSS_END_MARGIN, CaravanCart.MIN_CROSS_TIME, CaravanCart.CROSS_TIME)


## [param count] enemy types of the wave's eligible ones, by spawn weight (the guards).
func _pick_guard_datas(count: int) -> Array[EnemyData]:
	var out: Array[EnemyData] = []
	var pool := WaveDirector.eligible_enemies(_event_wave())
	for i in count:
		var d := WaveDirector.pick_weighted(pool, RunState.event_rng)
		if d != null:
			out.append(d)
	return out


## A spot at least [param min_distance] m from the living heroes (and the Spirit Healer), preferably on
## screen outside the HUD – WaveDirector.find_spawn_point's rule, drawn from the event rng.
func _event_point(min_distance: float) -> Vector3:
	var a := _arena()
	var view := Rect2()
	if a != null and is_instance_valid(a.camera) and a.camera.is_inside_tree():
		view = a.camera.get_safe_ground_rect()
	var avoid: Array[Vector3] = []
	if is_inside_tree():
		avoid = Enemy.living_player_positions(get_tree())
	if a != null and is_instance_valid(a.spirit_healer) and a.spirit_healer.is_inside_tree():
		avoid.append(a.spirit_healer.global_position)
	return WaveDirector.pick_spawn_point(a, RunState.event_rng, avoid, min_distance,
			WaveDirector.SPAWN_POINT_TRIES, view)


## Puts [param node] (already a child of [param parent]) at the world point [param pos] on the ground.
func _place(node: Node3D, parent: Node, pos: Vector3) -> void:
	var at := Vector3(pos.x, 0.0, pos.z)
	var parent_3d := parent as Node3D
	if parent_3d != null and parent_3d.is_inside_tree():
		node.position = parent_3d.global_transform.affine_inverse() * at
	else:
		node.position = at


## The wave the event belongs to (the rolled wave; the run's current one before any roll).
func _event_wave() -> int:
	return maxi(1, _wave if _wave > 0 else RunState.wave)


# --- Results -------------------------------------------------------------------------

func _on_chest_opened(_chest: GuardedChest, _opener: Player) -> void:
	_finish(GUARDED_CHEST, true)
	announced.emit(CHEST_OPENED_TEXT, EVENT_COLOR)


func _on_totem_held(t: DefendTotem) -> void:
	apply_team_buff()
	var at := t.global_position if is_instance_valid(t) and t.is_inside_tree() else Vector3.ZERO
	EventFx.burst(spawn_parent(), at, 0, DefendTotem.reward_xp(_event_wave()), DefendTotem.XP_PILES,
			DefendTotem.XP_RING)
	_finish(DEFEND_TOTEM, true)
	announced.emit(TOTEM_HELD_TEXT, TOTEM_COLOR)


func _on_totem_fell(_t: DefendTotem) -> void:
	_finish(DEFEND_TOTEM, false)
	announced.emit(TOTEM_FELL_TEXT, FAIL_COLOR)


func _on_cart_plundered(_c: CaravanCart, _killer: Player) -> void:
	_finish(GOBLIN_CARAVAN, true)
	announced.emit(CARAVAN_PLUNDERED_TEXT, EVENT_COLOR)


func _on_cart_escaped(_c: CaravanCart) -> void:
	_finish(GOBLIN_CARAVAN, false)
	announced.emit(CARAVAN_ESCAPED_TEXT, FAIL_COLOR)


## The running event ended, once: [signal event_finished], RunState.events_completed when it was won, one
## log line ("EVENT guarded_chest (wave 6): completed").
func _finish(kind: StringName, success: bool) -> void:
	if result != &"" or kind != active_kind:
		return
	result = &"completed" if success else &"failed"
	if success:
		RunState.events_completed += 1
	print("EVENT %s (wave %d): %s at %.1f s" % [kind, _event_wave(), result, wave_elapsed()])
	event_finished.emit(kind, success)


## Every hero gets +DefendTotem.BUFF_PCT % damage until the wave ends (the totem's reward). Returns the
## number of heroes buffed.
func apply_team_buff() -> int:
	_buff_on = true
	var entries: Array[Dictionary] = [{
		"kind": "damage", "pct": DefendTotem.BUFF_PCT, "id": "event_totem", "label": "Totem blessing",
	}]
	var n := 0
	for slot in PlayerManager.get_slots():
		var p := slot.player as Player
		if p == null or not is_instance_valid(p) or p.bonuses == null:
			continue
		p.bonuses.set_effects(BUFF_SOURCE, entries)
		n += 1
	return n


func _clear_buff() -> void:
	if not _buff_on:
		return
	_buff_on = false
	for slot in PlayerManager.get_slots():
		var p := slot.player as Player
		if p != null and is_instance_valid(p) and p.bonuses != null:
			p.bonuses.set_effects(BUFF_SOURCE, [] as Array[Dictionary])


## Settles an event that is still open (= failed: the chest was not opened, the totem did not last, the cart
## is still rolling), takes the buff off and forgets the objects. [member active_kind] and [member result]
## stay (the last event's outcome) until the next wave rolls.
func _settle() -> void:
	if active_kind != &"" and result == &"":
		_finish(active_kind, false)
	_clear_buff()
	chest = null
	totem = null
	cart = null


## The wave ended (cleared, or a new one started): settle the event, forget the pending one.
func end_wave() -> void:
	_start_at = -1.0
	_settle()


func _on_wave_started(wave: int) -> void:
	roll_wave(wave)


func _on_wave_cleared(_wave_number: int) -> void:
	end_wave()


## The arena (the director's, else Arena.current), null when there is none.
func _arena() -> Arena:
	if director != null and is_instance_valid(director) and director.arena != null and is_instance_valid(director.arena):
		return director.arena
	if Arena.current != null and is_instance_valid(Arena.current):
		return Arena.current
	return null


## The arena's entity root, else null – where an event puts its objects.
func spawn_parent() -> Node:
	var a := _arena()
	if a != null and is_instance_valid(a.entities) and a.entities.is_inside_tree():
		return a.entities
	return null
