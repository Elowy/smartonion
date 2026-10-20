class_name Dungeon
extends Node
## The dungeon (GDD 16.1, dungeon portal, M6b): an optional run of four short scripted rooms the
## party enters through the portal vote after wave 6, 9, 12 and 15 ([method is_portal_wave],
## Main._roll_portal, Intermission PORTAL phase). Main creates it, calls [method start] with the
## heroes and listens to [signal finished].
##
## The room is the run's own [Arena] in a small layout ([method Arena.enter_dungeon_layout]: 24 x 14 m,
## the run's environment palette, no environment hazard, no Spirit Healer): the heroes, the camera,
## Arena.current and the fighting systems stay exactly as in a wave, only the scenery is swapped, and
## [method _leave] puts it back. Enemies are the run's eligible ones ([method
## WaveDirector.eligible_enemies]) scaled to [method strength_wave] of the cleared wave ([member wave]); they pay nothing
## ([member Enemy.drops_loot] is false) – the dungeon has its own rewards, [DungeonRewards].
##
##   1 CLEAR   – kill CLEAR_KILLS (25) enemies; they come in telegraphed groups, at most CLEAR_CAP alive.
##   2 SURVIVE – survive SURVIVE_TIME (25 s) of a dense spawn (SURVIVE_DENSITY x the wave's spawn rate).
##   3 DEFEND  – keep a [DungeonBrazier] alive for DEFEND_TIME (20 s): the enemies near it are drawn to
##               it and hit it (their contact damage once a second each); its HP are
##               BRAZIER_GRUNTS x a Skeleton Grunt's HP at the wave x the party HP factor. Lost brazier
##               = failed dungeon.
##   4 WARDEN  – the Dungeon Warden (data/bosses/dungeon_warden.tres, a [BossData] run by [Boss]: frost
##               circles + raise dead, enrage at 60 s) arrives after a rune; its death clears the dungeon.
## Between the rooms: ROOM_PAUSE (3 s) "Room cleared" that heals every living hero ROOM_HEAL (30%) of
## its Max HP. Downed heroes stay down (no Spirit Healer): teammates revive them as in a wave. When
## every hero is down the dungeon is failed. Smoke runs ([member smoke_boss_timeout]) kill a Warden that
## outlives its enrage by SMOKE_BOSS_GRACE so a run always ends.
##
## Randomness: the groups' picks, sizes and places come from RunState.dungeon_rng (the run's own
## dungeon generator, never RunState.rng); only Enemy.setup draws RunState.rng, as everywhere.
## The node is PAUSABLE: the pause menu stops it like a wave.

## An enemy of the dungeon appeared (a spawned group member or a Warden's add).
signal enemy_spawned(enemy: Enemy)
## Room [param index] (0-based) began / was cleared.
signal room_started(index: int)
signal room_cleared(index: int)
## The Warden arrived (the HUD binds its boss frame) / the room it was in ended.
signal boss_spawned(boss: Boss)
signal boss_cleared
## A banner for the HUD (Main shows it).
signal announced(text: String, color: Color)
## The status line ([method title_text], [method task_text], [method seconds_left]) changed.
signal status_changed
## The dungeon is over and the arena is back to the clearing: [param success] = the Warden fell.
signal finished(success: bool)

enum Phase { IDLE, INTRO, ROOM, PAUSE, OUTRO, DONE }
enum Room { CLEAR, SURVIVE, DEFEND, WARDEN }

## The waves after which the portal opens (normal, endless and hardcore runs).
const PORTAL_WAVES: Array[int] = [6, 9, 12, 15]
## Final balance 2: the wave whose HP / damage growth the dungeon's enemies, its brazier and the Warden use, per
## portal wave and party size (the entry is [1, 2, 3, 4] heroes; see [method strength_wave]). The portal waves are
## the party's most comfortable stretch, so the dungeon is stronger than the cleared wave - by how much depends on
## the party and on the portal. Measured with the bots (cleared / entered after the waves 6 / 9 / 12 / 15):
##   four heroes  x1.6 flat (10 / 14 / 19 / 24)  9/12, 12/12, 6/10, 1/7   (too hard late)
##                9 / 13 / 16 / 19               9/10, 10/10, 8/8, 9/9   (too easy)
##                10 / 15 / 18 / 21              8/10, 9/10, 8/9, 8/9    (still 87%: revives are free in a full party)
##                10 / 17 / 20 / 23 (16 waves)   6/8, 3/8, 5/8, 4/6      (60%, only the second portal was too hard)
##   a lone hero  7 / 10 / 13 / 16               9/10, 9/10, 9/9, 8/8
##                8 / 12 / 16 / 20               6/10, 5/10, 5/6, 3/6    (and the runs that lost the first two dungeons
##                                                died on waves 10-12: a lone hero lives off the rewards)
## so a bigger party needs the bigger bonus (a full party is 3-4 revives deep), the middle portals a bigger one than the
## first (the party has gear by then), and a lone hero keeps the small numbers. The target is about 50-80% cleared per
## portal for three and four heroes and a bit fewer for a lone hero.
const STRENGTH_WAVES: Dictionary[int, Array] = {
	6: [7, 10, 10, 10],
	9: [11, 14, 14, 16],
	12: [15, 17, 18, 20],
	15: [18, 21, 22, 23],
}
const ROOM_COUNT := 4
const ROOM_NAMES: Array[String] = ["Clear", "Survive", "Defend", "Warden"]
const WARDEN_ID := &"dungeon_warden"

## Seconds between entering and the first room, the "Room cleared" pause (heals ROOM_HEAL) and the
## outro ("Dungeon cleared!" / "Dungeon failed") before the arena changes back.
const INTRO_TIME := 2.0
const ROOM_PAUSE := 3.0
const OUTRO_TIME := 2.5
const ROOM_HEAL := 0.3

## Room 1: kills needed; the most enemies alive (and telegraphed) at once; spawn rate relative to a wave's.
const CLEAR_KILLS := 25
const CLEAR_CAP := 12
const CLEAR_DENSITY := 1.5
## Room 2: seconds to survive, the most enemies alive at once, spawn rate relative to a wave's.
const SURVIVE_TIME := 25.0
const SURVIVE_CAP := 30
const SURVIVE_DENSITY := 2.5
## Room 3: seconds to hold, the most enemies alive, spawn rate relative to a wave's.
const DEFEND_TIME := 20.0
const DEFEND_CAP := 24
const DEFEND_DENSITY := 2.0
## The brazier's HP in Skeleton Grunts (their HP at the wave x RunState.coop_hp_mult()), the radius
## (m) around it in which enemies are drawn to it, how long one pull lasts and how often it is renewed,
## and the seconds between the enemies' hits on it.
const BRAZIER_GRUNTS := 30.0
const BRAZIER_GRUNT_ID := &"skeleton_grunt"
const DEFEND_TAUNT_RANGE := 9.0
const TAUNT_TIME := 0.8
const TAUNT_INTERVAL := 0.3
const BRAZIER_TICK := 1.0

## The Warden: the rune shows this long before it arrives, its radius, the least distance (m) from every
## hero it is placed at, the smoke safety (seconds past its enrage) and the most enemies alive that its
## Raise Dead may add up to.
const WARDEN_TELEGRAPH := 2.0
const WARDEN_RUNE_RADIUS := 2.6
const WARDEN_MIN_DISTANCE := 8.0
const SMOKE_BOSS_GRACE := 60.0
const SUMMON_CAP := 40

## Spawning: seconds a group's rune shows, the radius of the smallest rune, groups per tick at most,
## the least distance (m) from the heroes and the brazier, and the tries of the point search.
const TELEGRAPH_TIME := 1.0
const TELEGRAPH_RADIUS := 1.0
const GROUP_SCATTER := 0.8
const MAX_GROUPS_PER_FRAME := 4
const MIN_SPAWN_DISTANCE := 5.0
const SPAWN_TRIES := 8

const BANNER_COLOR := Color(0.78, 0.6, 1.0)
const CLEARED_COLOR := Color(0.45, 0.95, 0.5)
const FAILED_COLOR := Color(1.0, 0.4, 0.3)


## A telegraphed group waiting to appear.
class PendingGroup extends RefCounted:
	var data: EnemyData
	var count := 1
	var position := Vector3.ZERO
	var time_left := 0.0
	var ring := 0.0


var arena: Arena
## The cleared wave the enemies, the brazier and the Warden are scaled to.
var wave := 1
var heroes: Array[Player] = []
var phase := Phase.IDLE
## The current room (a Room value; -1 before the first).
var room := -1
## Seconds in the current room / phase.
var room_time := 0.0
var phase_time := 0.0
var success := false
## Why it was lost ("" while it is not).
var fail_reason := ""
## Seconds each cleared room took, in order; rooms cleared; kills of the dungeon; total seconds.
var room_times: Array[float] = []
var rooms_cleared := 0
var kills_total := 0
var total_time := 0.0
## Smoke runs only (Main sets it): kill a Warden that outlives its enrage by SMOKE_BOSS_GRACE.
var smoke_boss_timeout := false
var brazier: DungeonBrazier
## The share of the brazier's HP that was left when the Defend room was won (-1 = not won yet; balance data).
var brazier_left := -1.0
var warden: Boss
var warden_data: BossData
## The generator the dungeon draws from (RunState.dungeon_rng).
var rng: RandomNumberGenerator

var _eligible: Array[EnemyData] = []
var _pending: Array[PendingGroup] = []
var _pending_count := 0
var _spawning := false
var _rate := 0.0
var _cap := 0
var _limit := -1
var _spawned_room := 0
var _budget := 0.0
var _next_data: EnemyData
var _next_count := 0
var _room_kills := 0
var _warden_left := -1.0
var _warden_point := Vector3.ZERO
var _warden_arrived := false
var _warden_dead := false
var _taunt_left := 0.0
var _tick_left := BRAZIER_TICK
var _last_status := ""


## A dungeon in [param p_arena] for the cleared wave [param p_wave].
static func create(p_arena: Arena, p_wave: int, p_rng: RandomNumberGenerator = null) -> Dungeon:
	var d := Dungeon.new()
	d.name = "Dungeon"
	d.arena = p_arena
	d.wave = maxi(1, p_wave)
	d.rng = p_rng if p_rng != null else RunState.dungeon_rng
	return d


func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


## The portal opens after [param p_wave] (6, 9, 12, 15).
static func is_portal_wave(p_wave: int) -> bool:
	return p_wave in PORTAL_WAVES


## The wave whose growth the dungeon's enemies, brazier and Warden use after the cleared wave [param p_wave]
## for [param players] heroes (-1 = the run's party; more than four count as four): the [constant STRENGTH_WAVES]
## entry of the portal wave. Between two portal waves (a forced portal, tests) the bonus over the cleared wave is
## interpolated, before the first and after the last it stays that of the nearest portal. Which enemy types
## appear still follows the cleared wave itself.
static func strength_wave(p_wave: int, players: int = -1) -> int:
	var n := clampi(RunState.player_count if players < 0 else players, 1, 4)
	var w := maxi(1, p_wave)
	var portals := PORTAL_WAVES
	var bonus := float(int(STRENGTH_WAVES[portals[0]][n - 1]) - portals[0])
	for i in portals.size():
		var at: int = portals[i]
		var at_bonus := float(int(STRENGTH_WAVES[at][n - 1]) - at)
		if w >= at:
			bonus = at_bonus
			continue
		if i > 0:
			var prev: int = portals[i - 1]
			var prev_bonus := float(int(STRENGTH_WAVES[prev][n - 1]) - prev)
			bonus = lerpf(prev_bonus, at_bonus, float(w - prev) / float(at - prev))
		break
	return maxi(1, w + roundi(bonus))


## The Skeleton Grunt-based HP of the brazier at [param p_wave] (see BRAZIER_GRUNTS).
static func brazier_hp(p_wave: int) -> float:
	var grunt := Db.get_enemy(BRAZIER_GRUNT_ID)
	var base := grunt.hp_at_wave(p_wave) if grunt != null else 10.0
	return BRAZIER_GRUNTS * base * RunState.coop_hp_mult()


# --- Flow ------------------------------------------------------------------------------

## Enters: the arena takes the dungeon layout, the heroes (the valid ones of [param p_heroes]) are put
## on its spawn points as at a wave start (Player.begin_wave: full HP, downed ones back at 50%) and the
## first room begins after INTRO_TIME.
## Each hero gets the whole Player.begin_wave() reset, so a dungeon entry also counts as a wave start for
## the wave_start procs: their cooldowns and per-wave limits re-arm, and their "every N" counters keep
## counting across it (ProcSystem.begin_wave). No current content authors a wave_start trigger (data/ has
## none), so nothing differs today; a wave_start proc added later must allow for the extra wave, or the
## dungeon entry needs a lighter reset.
func start(p_heroes: Array[Player]) -> void:
	if phase != Phase.IDLE:
		return
	heroes.clear()
	for h in p_heroes:
		if is_instance_valid(h):
			heroes.append(h)
	_eligible = WaveDirector.eligible_enemies(wave)
	warden_data = Db.get_boss(WARDEN_ID)
	arena.enter_dungeon_layout(Db.environment_or_default(RunState.environment))
	_place_heroes()
	for h in heroes:
		h.begin_wave()
	Enemy.invalidate_player_cache()
	if is_instance_valid(arena.camera):
		arena.camera.snap()
	phase = Phase.INTRO
	phase_time = 0.0
	room = -1
	announced.emit("Dungeon!", BANNER_COLOR)
	status_changed.emit()


func is_running() -> bool:
	return phase != Phase.IDLE and phase != Phase.DONE


## The heroes are in the fight (from the intro to the outro): a hero getting up now was revived by a
## teammate. The entry's begin_wave and the exit's wave-start revive are not that (Main.revives).
func counts_revives() -> bool:
	return phase == Phase.INTRO or phase == Phase.ROOM or phase == Phase.PAUSE or phase == Phase.OUTRO


## 1-based number of the room shown ("Room 2/4"): the current one, the one just cleared during the
## pause, the first before the rooms begin.
func room_number() -> int:
	return clampi(room + 1, 1, ROOM_COUNT)


func _physics_process(delta: float) -> void:
	if not is_running():
		return
	total_time += delta
	_prune_heroes()
	_update_spawner(delta)
	if phase != Phase.OUTRO and _all_heroes_down():
		_fail("The party has fallen")
	match phase:
		Phase.INTRO:
			phase_time += delta
			if phase_time >= INTRO_TIME:
				_start_room(Room.CLEAR)
		Phase.ROOM:
			_update_room(delta)
		Phase.PAUSE:
			phase_time += delta
			if phase_time >= ROOM_PAUSE:
				_start_room(room + 1)
		Phase.OUTRO:
			phase_time += delta
			if phase_time >= OUTRO_TIME:
				_finish()
	_emit_status()


func _start_room(index: int) -> void:
	room = index
	room_time = 0.0
	phase_time = 0.0
	phase = Phase.ROOM
	_room_kills = 0
	_spawned_room = 0
	match room:
		Room.CLEAR:
			_begin_spawning(CLEAR_DENSITY, CLEAR_CAP, CLEAR_KILLS)
		Room.SURVIVE:
			_begin_spawning(SURVIVE_DENSITY, SURVIVE_CAP, -1)
		Room.DEFEND:
			_spawn_brazier()
			_begin_spawning(DEFEND_DENSITY, DEFEND_CAP, -1)
		Room.WARDEN:
			_begin_warden()
	announced.emit("Room %d/%d – %s" % [room + 1, ROOM_COUNT, ROOM_NAMES[room]], BANNER_COLOR)
	room_started.emit(room)
	status_changed.emit()


func _update_room(delta: float) -> void:
	room_time += delta
	match room:
		Room.CLEAR:
			if _room_kills >= CLEAR_KILLS:
				_room_done()
		Room.SURVIVE:
			if room_time >= SURVIVE_TIME:
				_room_done()
		Room.DEFEND:
			_update_defend(delta)
		Room.WARDEN:
			_update_warden(delta)


## The current room is won: its world is swept, the pause (and the heal) follows – or, after the
## Warden, the outro.
func _room_done() -> void:
	room_times.append(room_time)
	rooms_cleared += 1
	if room == Room.DEFEND and is_instance_valid(brazier):
		brazier_left = brazier.hp_ratio()
	_clear_room_world()
	room_cleared.emit(room)
	phase_time = 0.0
	if room >= ROOM_COUNT - 1:
		success = true
		phase = Phase.OUTRO
		announced.emit("Dungeon cleared!", CLEARED_COLOR)
	else:
		phase = Phase.PAUSE
		_heal_heroes(ROOM_HEAL)
		announced.emit("Room %d cleared!" % (room + 1), CLEARED_COLOR)
	status_changed.emit()


## The dungeon is lost: the room's world is swept and the outro shows "Dungeon failed".
func _fail(reason: String) -> void:
	if phase == Phase.OUTRO or phase == Phase.DONE:
		return
	success = false
	fail_reason = reason
	_clear_room_world()
	phase = Phase.OUTRO
	phase_time = 0.0
	announced.emit("Dungeon failed – %s" % reason, FAILED_COLOR)
	status_changed.emit()


## The end: the arena is the clearing again, the heroes stand where a wave starts them, [signal finished].
func _finish() -> void:
	if phase == Phase.DONE:
		return
	phase = Phase.DONE
	_leave()
	finished.emit(success)


## Everything of the dungeon goes: the world is swept, the heroes' auras and buffs end (as at a wave
## end, without the wave-end signal – Artifacts must not grow twice), downed ones are revived at the
## wave-start ratio, the clearing's scenery comes back and the heroes go to its spawn points.
func _leave() -> void:
	_prune_heroes()
	_clear_room_world()
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group(&"ability_areas"):
			if is_instance_valid(node) and not node.is_queued_for_deletion():
				node.queue_free()
	for h in heroes:
		if not is_instance_valid(h):
			continue
		if h.abilities != null:
			h.abilities.end_wave()
		if h.bonuses != null:
			h.bonuses.end_wave()
		if h.procs != null:
			h.procs.end_wave()
		h.refresh_armor_spec()
		if h.downed:
			h.revive(Player.WAVE_START_REVIVE_HP_RATIO)
	if is_instance_valid(arena):
		arena.leave_dungeon_layout()
	_place_heroes()
	Enemy.invalidate_player_cache()
	if is_instance_valid(arena) and is_instance_valid(arena.camera):
		arena.camera.snap()


## Forgets the heroes that were freed (a player given up through the pause menu): reading a freed
## instance into a Player-typed variable is a script error, so the list is checked as Variants.
func _prune_heroes() -> void:
	var i := heroes.size() - 1
	while i >= 0:
		var raw: Variant = heroes[i]
		if not is_instance_valid(raw):
			heroes.remove_at(i)
		i -= 1


func _place_heroes() -> void:
	if not is_instance_valid(arena):
		return
	var spawns := arena.get_player_spawn_points(heroes.size())
	for i in heroes.size():
		var h := heroes[i]
		if not is_instance_valid(h) or i >= spawns.size():
			continue
		h.global_position = spawns[i]
		h.velocity = Vector3.ZERO


func _all_heroes_down() -> bool:
	for h in heroes:
		if is_instance_valid(h) and h.is_alive():
			return false
	return true


func _heal_heroes(share: float) -> void:
	for h in heroes:
		if is_instance_valid(h) and h.is_alive():
			h.heal(h.max_hp() * share)


func _on_enemy_died(_enemy: Enemy, _killer_index: int) -> void:
	_room_kills += 1
	kills_total += 1


# --- Spawning --------------------------------------------------------------------------

## Starts the group spawner: [param density] x the wave's spawn rate for the party size, at most
## [param cap] enemies alive or telegraphed, [param limit] enemies in all (-1 = no limit). The first
## group is telegraphed at once.
func _begin_spawning(density: float, cap: int, limit: int) -> void:
	_spawning = true
	_rate = WaveDirector.spawn_rate(wave, RunState.coop_count_mult()) * density
	_cap = cap
	_limit = limit
	_choose_next_group()
	_budget = float(_next_count)


func _choose_next_group() -> void:
	_next_data = WaveDirector.pick_weighted(_eligible, rng)
	_next_count = WaveDirector.roll_group_size(_next_data, rng) if _next_data != null else 0


func _update_spawner(delta: float) -> void:
	var i := 0
	while i < _pending.size():
		var g := _pending[i]
		g.time_left -= delta
		if g.time_left > 0.0:
			i += 1
			continue
		_pending.remove_at(i)
		_pending_count -= g.count
		_hatch(g)
	if not _spawning:
		return
	_budget += _rate * delta
	for _i in MAX_GROUPS_PER_FRAME:
		if _next_data == null:
			return
		var count := _next_count
		if _limit >= 0:
			count = mini(count, _limit - _spawned_room - _pending_count)
			if count <= 0:
				return
		if alive_count() + _pending_count + count > _cap or _budget < float(count):
			return
		_budget -= float(count)
		_telegraph(_next_data, count)
		_choose_next_group()


func _telegraph(data: EnemyData, count: int) -> void:
	var g := PendingGroup.new()
	g.data = data
	g.count = count
	g.position = _find_spawn_point(MIN_SPAWN_DISTANCE)
	g.time_left = TELEGRAPH_TIME
	g.ring = _ring_radius(data, count)
	_pending.append(g)
	_pending_count += count
	Vfx.spawn_telegraph(g.position, maxf(TELEGRAPH_RADIUS, g.ring + 0.3), TELEGRAPH_TIME)


## A group appears: its members on a ring around the rune.
func _hatch(g: PendingGroup) -> void:
	var parent := _spawn_parent()
	if parent == null or g.data == null:
		return
	var base_angle := rng.randf() * TAU
	for i in g.count:
		var pos := g.position
		if g.count > 1:
			var angle := base_angle + TAU * float(i) / float(g.count) + rng.randf_range(-0.25, 0.25)
			pos += Vector3(cos(angle), 0.0, sin(angle)) * g.ring * rng.randf_range(0.7, 1.0)
		pos = arena.clamp_point(pos, g.data.radius + 0.1)
		pos.y = 0.0
		var e := Enemy.create(g.data, strength_wave(wave))
		e.drops_loot = false
		e.position = pos
		e.died.connect(_on_enemy_died)
		parent.add_child(e)
		_spawned_room += 1
		enemy_spawned.emit(e)


## A point for a group or the Warden: [param min_distance] m from every living hero and the brazier,
## preferably on the part of the ground the HUD leaves visible.
func _find_spawn_point(min_distance: float) -> Vector3:
	var tree := get_tree() if is_inside_tree() else null
	var avoid := Enemy.living_player_positions(tree)
	if is_instance_valid(brazier):
		avoid.append(brazier.global_position)
	var view := Rect2()
	if is_instance_valid(arena.camera) and arena.camera.is_inside_tree():
		view = arena.camera.get_safe_ground_rect()
	return WaveDirector.pick_spawn_point(arena, rng, avoid, min_distance, SPAWN_TRIES, view)


## Adds [param count] enemies of [param add_data] on a ring of [param scatter] m around [param center]
## (the Warden's Raise Dead; same contract as WaveDirector.summon), as many as SUMMON_CAP allows.
func summon(add_data: EnemyData, count: int, center: Vector3, scatter: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	var parent := _spawn_parent()
	if not is_running() or parent == null or add_data == null:
		return out
	var n := mini(count, SUMMON_CAP - alive_count() - _pending_count)
	for i in maxi(0, n):
		var angle := TAU * float(i) / float(maxi(1, n)) + 0.4
		var pos := center + Vector3(cos(angle), 0.0, sin(angle)) * scatter
		pos = arena.clamp_point(pos, add_data.radius + 0.1)
		pos.y = 0.0
		var e := Enemy.create(add_data, strength_wave(wave))
		e.drops_loot = false
		e.position = pos
		parent.add_child(e)
		Vfx.death_puff(pos + Vector3.UP * 0.4, add_data.color, maxf(0.6, add_data.model_scale))
		enemy_spawned.emit(e)
		out.append(e)
	return out


func alive_count() -> int:
	return get_tree().get_node_count_in_group(&"enemies") if is_inside_tree() else 0


func pending_count() -> int:
	return _pending_count


func _spawn_parent() -> Node:
	if is_instance_valid(arena) and is_instance_valid(arena.entities) and arena.entities.is_inside_tree():
		return arena.entities
	return get_parent() if is_inside_tree() else null


static func _ring_radius(data: EnemyData, count: int) -> float:
	if count <= 1:
		return 0.0
	return maxf(GROUP_SCATTER, float(count) * (data.radius * 2.0 + 0.15) / TAU)


# --- Room 3: the brazier -----------------------------------------------------------------

func _spawn_brazier() -> void:
	brazier = DungeonBrazier.create(brazier_hp(strength_wave(wave)))
	var parent := _spawn_parent()
	if parent != null:
		parent.add_child(brazier)
	brazier.position = Vector3.ZERO
	_taunt_left = 0.0
	_tick_left = BRAZIER_TICK


func _update_defend(delta: float) -> void:
	if not is_instance_valid(brazier):
		return
	_taunt_left -= delta
	if _taunt_left <= 0.0:
		_taunt_left = TAUNT_INTERVAL
		_taunt_enemies()
	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left += BRAZIER_TICK
		var damage := _brazier_damage()
		if damage > 0.0:
			brazier.take_damage(damage)
			Vfx.floating_text(brazier.global_position + Vector3(0.0, 2.7, 0.0), "-%d" % ceili(damage),
					Color(1.0, 0.55, 0.25), 0.9)
	if not brazier.is_alive():
		_fail("The brazier was destroyed")
	elif room_time >= DEFEND_TIME:
		_room_done()


## Enemies near the brazier chase it instead of the heroes (a taunt another source set stays).
func _taunt_enemies() -> void:
	var range_sq := DEFEND_TAUNT_RANGE * DEFEND_TAUNT_RANGE
	var at := brazier.global_position
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var e := node as Enemy
		if e == null or e.is_dead() or e.is_boss():
			continue
		if e.is_taunted() and e.taunt_target != brazier:
			continue
		var d := e.global_position - at
		if d.x * d.x + d.z * d.z <= range_sq:
			e.apply_taunt(brazier, TAUNT_TIME)


## What the enemies at the brazier deal in one tick: each one's contact damage (stunned and feared
## ones do not hit).
func _brazier_damage() -> float:
	var total := 0.0
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var e := node as Enemy
		if e == null or e.is_dead() or not e.deals_contact_damage() or e.stun_left > 0.0 or e.is_feared():
			continue
		if brazier.reaches(e.global_position, e.radius):
			total += e.contact_damage * e.damage_mult
	return total


# --- Room 4: the Warden ------------------------------------------------------------------

func _begin_warden() -> void:
	_spawning = false
	_warden_arrived = false
	_warden_dead = false
	if warden_data == null:
		push_warning("Dungeon: %s is missing from Db.bosses – the Warden room is skipped" % WARDEN_ID)
		_warden_left = -1.0
		_warden_dead = true
		_warden_arrived = true
		return
	_warden_point = _find_spawn_point(WARDEN_MIN_DISTANCE)
	_warden_left = WARDEN_TELEGRAPH
	Vfx.spawn_telegraph(_warden_point, WARDEN_RUNE_RADIUS, WARDEN_TELEGRAPH)


func _update_warden(delta: float) -> void:
	if not _warden_arrived:
		_warden_left -= delta
		if _warden_left <= 0.0:
			_spawn_warden()
		return
	if _warden_dead or not is_instance_valid(warden) or warden.is_dead():
		_room_done()
		return
	if smoke_boss_timeout and warden.age() >= warden_data.enrage_time + SMOKE_BOSS_GRACE:
		print("SMOKE dungeon boss timeout: %s still alive %.0f s after its enrage (phase %d, %.0f%% HP) - killed" % [
			warden_data.display_name, SMOKE_BOSS_GRACE, warden.phase, warden.hp_ratio() * 100.0])
		warden.kill()


func _spawn_warden() -> void:
	var parent := _spawn_parent()
	if parent == null:
		return
	var b := Boss.create(warden_data, strength_wave(wave))
	b.director = self
	b.drops_loot = false
	b.position = arena.clamp_point(_warden_point, warden_data.radius * warden_data.model_scale * 0.5 + 0.2)
	b.position.y = 0.0
	warden = b
	_warden_arrived = true
	_warden_dead = false
	b.died.connect(_on_warden_died)
	parent.add_child(b)
	boss_spawned.emit(b)
	enemy_spawned.emit(b)
	announced.emit(warden_data.intro_text(), FAILED_COLOR)


func _on_warden_died(dead: Enemy, _killer_index: int) -> void:
	if dead == warden:
		_warden_dead = true


# --- World sweep --------------------------------------------------------------------------

## Everything the room left: enemies (despawned without loot), telegraphs, hazards, enemy projectiles,
## the chill, the brazier and the Warden's frame.
func _clear_room_world() -> void:
	_spawning = false
	_pending.clear()
	_pending_count = 0
	var had_boss := warden != null
	warden = null
	if is_inside_tree():
		var tree := get_tree()
		for node in tree.get_nodes_in_group(&"enemies"):
			var e := node as Enemy
			if e != null and is_instance_valid(e):
				e.despawn()
		for node in tree.get_nodes_in_group(EnemyHazard.GROUP):
			if is_instance_valid(node) and not node.is_queued_for_deletion():
				node.queue_free()
		for node in tree.get_nodes_in_group(&"projectiles"):
			var proj := node as Projectile
			if proj != null and proj.team == Projectile.TEAM_ENEMIES and not proj.is_queued_for_deletion():
				proj.queue_free()
		GeneralBuff.clear(tree, FrostCircle.CHILL_KEY)
	if is_instance_valid(brazier):
		if brazier.get_parent() != null:
			brazier.get_parent().remove_child(brazier)
		brazier.queue_free()
	brazier = null
	if had_boss:
		boss_cleared.emit()


# --- Status line ----------------------------------------------------------------------------

## "Dungeon – Room 2/4" (the HUD's top line).
func title_text() -> String:
	match phase:
		Phase.INTRO, Phase.IDLE:
			return "Dungeon"
		Phase.OUTRO:
			return "Dungeon cleared!" if success else "Dungeon failed"
	return "Dungeon – Room %d/%d" % [room_number(), ROOM_COUNT]


## The room's task and how far it is ("Kill enemies 12 / 25").
func task_text() -> String:
	match phase:
		Phase.INTRO, Phase.IDLE:
			return "Get ready"
		Phase.PAUSE:
			return "Room cleared!"
		Phase.OUTRO:
			return "" if success else fail_reason
	match room:
		Room.CLEAR:
			return "Kill enemies  %d / %d" % [mini(_room_kills, CLEAR_KILLS), CLEAR_KILLS]
		Room.SURVIVE:
			return "Survive"
		Room.DEFEND:
			if is_instance_valid(brazier):
				return "Defend the brazier  (%d%%)" % ceili(brazier.hp_ratio() * 100.0 - 0.001)
			return "Defend the brazier"
		Room.WARDEN:
			return "Defeat the Dungeon Warden"
	return ""


## Seconds left of a timed room (Survive, Defend); -1 for the others.
func seconds_left() -> float:
	if phase != Phase.ROOM:
		return -1.0
	match room:
		Room.SURVIVE:
			return maxf(0.0, SURVIVE_TIME - room_time)
		Room.DEFEND:
			return maxf(0.0, DEFEND_TIME - room_time)
	return -1.0


## Kills of the current room.
func room_kills() -> int:
	return _room_kills


func _emit_status() -> void:
	var key := "%s|%s|%d" % [title_text(), task_text(), ceili(seconds_left())]
	if key != _last_status:
		_last_status = key
		status_changed.emit()


## A one-line summary for the smoke log: rooms, their times, kills.
func summary_text() -> String:
	var times: Array[String] = []
	for t in room_times:
		times.append("%.1f s" % t)
	return "%s on wave %d: %d / %d rooms%s, %d kills, %.1f s%s" % [
		"cleared" if success else "failed", wave, rooms_cleared, ROOM_COUNT,
		" (%s)" % ", ".join(times) if not times.is_empty() else "",
		kills_total, total_time, "" if success or fail_reason == "" else " – " + fail_reason]
