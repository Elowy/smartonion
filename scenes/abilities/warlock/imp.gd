class_name WarlockImp
extends Node3D
## The Warlock's permanent Imp (GDD 3.5). Spawned by [WarlockMastery] under the arena's entity
## root (or next to the Warlock), it hovers about [constant FOLLOW_DISTANCE] m from its master
## and every [code]interval[/code] seconds (Haste shortens it) hurls a firebolt
## ([WarlockImpBolt], fire, tagged &"pet" so Demonic Pact boosts it) at the nearest enemy
## within [code]range[/code] m. While the Warlock is downed it hides and stops shooting; it
## comes back with the revive. It cannot be hurt and survives waves (Main frees it with the
## arena; the Mastery frees it in teardown).
##
## Numbers live in [constant BASE_PARAMS]; items change them through ability_mod on the pseudo
## ability [constant MOD_ID] (Grimoire of the Imp Lord: {"damage_bonus_add": 50,
## "targets_add": 1}); talents too (Improved Imp: "damage_bonus_add").
##
## Wild Imps (M5 Demonology modifier on Rain of Fire, [method spawn_wild]): smaller, fel-green
## imps with the same logic and params that live [member lifetime] seconds (counted down also
## while hidden – the Warlock down), deal [member power_mult] of a bolt's damage and hover at
## their own [member orbit_slot] spot (four presets around the Warlock; the permanent Imp keeps
## back-left). WarlockRainOfFire owns and dismisses them; they are never WarlockMastery.imp.

const MOD_ID := &"warlock_imp"
const BASE_PARAMS := {
	## Fire damage of one bolt before the Warlock's stats.
	"damage": 2.0,
	## Extra damage per point of the Warlock's Intellect.
	"intellect_scale": 0.4,
	## Extra damage per point of Spell Power per second of [code]interval[/code].
	"spell_power_scale": 1.0,
	## % more damage (multiplies the whole bolt).
	"damage_bonus": 0.0,
	## Seconds between bolts at Haste 0.
	"interval": 1.2,
	## Metres: only enemies this close to the Imp are shot at.
	"range": 9.0,
	## Enemies one bolt hits (more than 1: it ricochets to the nearest new enemy).
	"targets": 1,
	"bolt_speed": 13.0,
}
const SCHOOL := &"fire"
## Preferred distance to the Warlock (m).
const FOLLOW_DISTANCE := 1.5
## Further than this from the Warlock (teleport, wave start) it pops back at once.
const TELEPORT_DISTANCE := 9.0
## How fast it closes the gap (1/s, exponential) and its top speed (m/s).
const FOLLOW_GAIN := 5.0
const MAX_SPEED := 11.0
## How fast it drifts to its favourite spot behind the Warlock's shoulder (1/s).
const ORBIT_RATE := 1.2
## Favourite spot: behind the Warlock (share of the distance) and to its left (+ = left).
const ORBIT_BACK := 0.55
const ORBIT_SIDE := 0.85
## Bolts start at this height (the hand of the hovering model).
const BOLT_HEIGHT := 0.95
## With nothing in range it looks again after this many seconds.
const NO_TARGET_RETRY := 0.1
## The first bolt of a wave (and after a revive) comes this long after it appears.
const FIRST_SHOT_DELAY := 0.5
## Turns towards its last target for this long after a shot.
const LOOK_TIME := 0.6
const SUMMON_COLOR := Color(0.45, 1.0, 0.3)
## Wild Imps' spots around the Warlock as (back, left) shares of the follow distance, like
## ORBIT_BACK / ORBIT_SIDE: front-left, front-right, back-right, back.
const WILD_ORBITS: Array[Vector2] = [Vector2(-0.6, 0.8), Vector2(-0.6, -0.8), Vector2(0.55, -0.85), Vector2(1.0, 0.0)]

var owner_player: Player
var model: WarlockImpModel
## Bolts fired so far (tests, stats).
var shots_fired := 0
## The last bolt fired (tests); may be freed.
var last_bolt: WarlockImpBolt
## Seconds a Wild Imp has left (< 0 = permanent: the Mastery's Imp).
var lifetime := -1.0
## Share of a bolt's damage (Wild Imps: wild_imp_power / 100).
var power_mult := 1.0
## -1 = the Imp's back-left spot; 0..3 = a Wild Imp spot ([constant WILD_ORBITS]).
var orbit_slot := -1

var _shot_left := FIRST_SHOT_DELAY
var _hidden := false
var _look_dir := Vector3.FORWARD
var _look_left := 0.0
var _speed_ratio := 0.0


## Creates the Imp for [param p_owner] and adds it under the arena's entities (or the
## Warlock's parent) next to the Warlock. Not in the tree when there is no such parent.
static func spawn(p_owner: Player) -> WarlockImp:
	var imp := WarlockImp.new()
	imp.name = "Imp"
	imp.owner_player = p_owner
	imp.model = WarlockImpModel.new()
	imp.add_child(imp.model)
	var parent := WeaponRunner.effects_parent(p_owner)
	if parent != null:
		parent.add_child(imp)
		imp.snap_to_owner()
		imp._puff()
	return imp


## A Wild Imp (Rain of Fire's Wild Imps): lives [param p_lifetime] seconds, deals
## [param p_power] x the Imp's bolt damage, hovers at orbit spot [param p_slot] (0..3).
## Smaller and fel-green. Not in the tree when the Warlock has no effects parent.
static func spawn_wild(p_owner: Player, p_lifetime: float, p_power: float, p_slot: int) -> WarlockImp:
	var imp := WarlockImp.new()
	imp.name = "WildImp"
	imp.owner_player = p_owner
	imp.lifetime = maxf(0.0, p_lifetime)
	imp.power_mult = maxf(0.0, p_power)
	imp.orbit_slot = clampi(p_slot, 0, WILD_ORBITS.size() - 1)
	imp.model = WarlockImpModel.new()
	imp.model.wild = true
	imp.add_child(imp.model)
	var parent := WeaponRunner.effects_parent(p_owner)
	if parent != null:
		parent.add_child(imp)
		imp.snap_to_owner()
		imp._puff()
	return imp


func is_wild() -> bool:
	return lifetime >= 0.0


## Leaves now ([param puff]: the summon puff where it was).
func dismiss(puff: bool = false) -> void:
	if is_queued_for_deletion():
		return
	if puff and is_inside_tree() and visible:
		Vfx.death_puff(global_position + Vector3.UP * BOLT_HEIGHT, SUMMON_COLOR, 0.6)
	queue_free()


## The Imp's numbers with the Warlock's item mods applied.
func current_params() -> Dictionary:
	var mods: Dictionary = owner_player.ability_mods(MOD_ID) if _owner_valid() else {}
	return AbilityRunner.apply_mods(BASE_PARAMS, mods)


## Fire damage of one bolt for the Warlock's [param stats] (before the target bonuses,
## Demonic Pact and the Warlock's outgoing multipliers, which ProcSystem.deal_raw applies).
static func bolt_damage(stats: StatBlock, params: Dictionary) -> float:
	var interval := float(params.get("interval", 1.2))
	var flat := float(params.get("damage", 0.0)) \
			+ maxf(0.0, stats.get_raw(Stats.INTELLECT)) * float(params.get("intellect_scale", 0.0)) \
			+ maxf(0.0, stats.get_raw(Stats.SPELL_POWER)) * float(params.get("spell_power_scale", 0.0)) * interval
	var bonus := 1.0 + float(params.get("damage_bonus", 0.0)) / 100.0
	return maxf(CombatMath.MIN_DAMAGE, flat * CombatMath.damage_mult_for(stats, SCHOOL) * maxf(0.0, bonus))


## Seconds between bolts for [param stats] (Haste speeds the Imp up like a weapon).
static func shot_interval(stats: StatBlock, params: Dictionary) -> float:
	return maxf(0.2, float(params.get("interval", 1.2)) / maxf(0.2, stats.attack_speed_mult()))


func is_hidden() -> bool:
	return _hidden


## Wave start: back next to the (teleported) Warlock, first bolt after a short delay.
func begin_wave() -> void:
	snap_to_owner()
	_shot_left = FIRST_SHOT_DELAY
	_look_left = 0.0


## Puts the Imp at its favourite spot next to the Warlock.
func snap_to_owner() -> void:
	if not _owner_valid() or not owner_player.is_inside_tree() or not is_inside_tree():
		return
	var anchor := _flat(owner_player.global_position)
	global_position = anchor + _preferred_dir() * FOLLOW_DISTANCE


func _physics_process(delta: float) -> void:
	if not _owner_valid():
		queue_free()
		return
	if lifetime >= 0.0:
		lifetime -= delta
		if lifetime <= 0.0:
			dismiss(true)
			return
	if not owner_player.is_inside_tree() or not is_inside_tree():
		return
	var hide_now := owner_player.downed
	if hide_now != _hidden:
		_hidden = hide_now
		visible = not hide_now
		if not hide_now:
			snap_to_owner()
			_puff()
			_shot_left = FIRST_SHOT_DELAY
	_follow(delta)
	if _hidden:
		return
	_look_left = maxf(0.0, _look_left - delta)
	if model != null:
		model.set_facing(_look_dir if _look_left > 0.0 else owner_player.facing)
		model.set_moving(_speed_ratio)
	_shot_left -= delta
	if _shot_left <= 0.0:
		try_shoot()


## Shoots at the nearest enemy in range now (resets the shot timer). False: nothing in range.
func try_shoot() -> bool:
	if not _owner_valid() or not is_inside_tree() or _hidden:
		return false
	var params := current_params()
	var reach := float(params.get("range", 9.0))
	var here := global_position
	var target := EnemyGrid.nearest(get_tree(), here, reach)
	if target == null:
		_shot_left = NO_TARGET_RETRY
		return false
	_shot_left = shot_interval(owner_player.stats, params)
	var from := Vector3(here.x, BOLT_HEIGHT, here.z)
	var dir := _flat(target.global_position - here)
	if dir.length_squared() < 0.0001:
		dir = owner_player.facing
	dir = dir.normalized()
	_look_dir = dir
	_look_left = LOOK_TIME
	last_bolt = WarlockImpBolt.fire(owner_player, from, dir, bolt_damage(owner_player.stats, params) * power_mult,
			maxi(1, roundi(float(params.get("targets", 1)))), reach + 1.5,
			float(params.get("bolt_speed", 13.0)))
	shots_fired += 1
	if model != null:
		model.set_facing(dir)
		model.play_cast()
	return true


func _follow(delta: float) -> void:
	var anchor := _flat(owner_player.global_position)
	var here := _flat(global_position)
	var offset := here - anchor
	var dist := offset.length()
	if dist > TELEPORT_DISTANCE:
		snap_to_owner()
		_speed_ratio = 0.0
		return
	var dir := offset / dist if dist > 0.001 else _preferred_dir()
	# Drift slowly towards the favourite spot behind the shoulder (never swings around fast).
	dir = dir.lerp(_preferred_dir(), 1.0 - exp(-ORBIT_RATE * delta))
	if dir.length_squared() < 0.0001:
		dir = _preferred_dir()
	var want := anchor + dir.normalized() * FOLLOW_DISTANCE
	var step := (want - here) * (1.0 - exp(-FOLLOW_GAIN * delta))
	var max_step := MAX_SPEED * delta
	if step.length() > max_step:
		step = step.normalized() * max_step
	global_position = here + step
	_speed_ratio = clampf(step.length() / maxf(0.0001, delta) / 4.0, 0.0, 1.0)


## Unit vector (XZ) from the Warlock to the Imp's favourite spot: behind its left shoulder
## (a Wild Imp: its [constant WILD_ORBITS] spot).
func _preferred_dir() -> Vector3:
	var facing := _flat(owner_player.facing) if _owner_valid() else Vector3.FORWARD
	if facing.length_squared() < 0.0001:
		facing = Vector3.FORWARD
	facing = facing.normalized()
	var left := Vector3(facing.z, 0.0, -facing.x)
	var spot := Vector2(ORBIT_BACK, ORBIT_SIDE)
	if orbit_slot >= 0 and orbit_slot < WILD_ORBITS.size():
		spot = WILD_ORBITS[orbit_slot]
	return (-facing * spot.x + left * spot.y).normalized()


func _owner_valid() -> bool:
	return owner_player != null and is_instance_valid(owner_player) and not owner_player.is_queued_for_deletion()


func _puff() -> void:
	if is_inside_tree():
		Vfx.hit_spark(global_position + Vector3.UP * BOLT_HEIGHT, SUMMON_COLOR)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
