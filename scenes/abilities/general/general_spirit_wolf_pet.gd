class_name GeneralSpiritWolfPet
extends Node3D
## One spirit wolf of the Spirit Wolf ability. Spawned under the arena's entity root (or next to
## its master), it lives for [member life_left] seconds, hunts the enemy nearest to it within
## [code]leash[/code] m of its master and bites it every [code]bite_interval[/code] seconds
## (Haste shortens it) for bite_pct % of the master's weapon damage (GeneralKit.weapon_damage,
## the ability's school, x power) – PET damage through ProcSystem.deal_raw(..., &"pet") (kill
## credit, damage meter, Demonic Pact; no on-hit procs). Spec extras: slow on bite, heal the
## master for heal_pct % of the damage.
## With nothing to hunt it trots back to its spot beside the master. It cannot be hurt; it
## vanishes (puff) when its time is up, when the master goes down or is freed, and with the wave
## (the ability's begin_wave / end_wave dismiss it).

const SCHOOL_DEFAULT := &"nature"
const SPIRIT_COLOR := Color(0.6, 0.88, 1.0)
const RUN_SPEED := 9.0
const FOLLOW_SPEED := 8.0
## Distance kept beside the master (m) and how far apart the pack spreads.
const FOLLOW_DISTANCE := 1.3
const PACK_ANGLE := 0.9
## Further than this from the master it pops back at once (teleports, wave start).
const TELEPORT_DISTANCE := 14.0
## Bites reach this far beyond the enemy's radius (m).
const BITE_REACH := 0.55
## Looks for a (new) target this often (s).
const RETARGET_INTERVAL := 0.25
## The first bite comes this soon after the wolf reaches its prey (s).
const FIRST_BITE_DELAY := 0.15
const BITE_COLOR := Color(0.7, 0.95, 1.0)

var owner_player: Player
## Index in the pack (spot beside the master).
var pack_index := 0
## Seconds until it fades.
var life_left := 12.0
var school: StringName = SCHOOL_DEFAULT
## bite_pct, bite_interval, leash, power, slow, slow_duration, heal_pct.
var params: Dictionary = {}
var model: GeneralWolfModel
## The enemy it hunts (untyped: it may be freed meanwhile – see [method current_target]).
var target: Variant = null
## Bites landed so far (tests).
var bites := 0
var dismissed := false

var _bite_left := FIRST_BITE_DELAY
var _retarget_left := 0.0


## Summons a wolf for [param p_owner] beside it. Not in the tree without a parent.
static func spawn(p_owner: Player, p_index: int, p_params: Dictionary, p_life: float,
		p_school: StringName = SCHOOL_DEFAULT) -> GeneralSpiritWolfPet:
	var w := GeneralSpiritWolfPet.new()
	w.name = "SpiritWolf"
	w.owner_player = p_owner
	w.pack_index = p_index
	w.params = p_params.duplicate()
	w.life_left = p_life
	w.school = p_school
	w.model = GeneralWolfModel.new()
	w.add_child(w.model)
	var parent := WeaponRunner.effects_parent(p_owner)
	if parent != null:
		parent.add_child(w)
		w.snap_to_owner()
		w._puff()
	return w


## New numbers / time from a recast.
func refresh(p_params: Dictionary, p_life: float) -> void:
	params = p_params.duplicate()
	life_left = maxf(life_left, p_life)


func is_active() -> bool:
	return not dismissed and life_left > 0.0


## Fades away now (with a puff unless [param quiet]).
func dismiss(quiet: bool = false) -> void:
	if dismissed:
		return
	dismissed = true
	target = null
	if not quiet:
		_puff()
	queue_free()


## Damage of one bite for the master's current stats.
func bite_damage() -> float:
	if not _owner_valid():
		return 0.0
	return GeneralKit.weapon_damage(owner_player, school) * float(params.get("bite_pct", 35.0)) / 100.0 \
			* float(params.get("power", 1.0))


## Seconds between bites (Haste speeds them up like a weapon).
func bite_interval() -> float:
	var base := float(params.get("bite_interval", 1.2))
	var haste := owner_player.stats.attack_speed_mult() if _owner_valid() else 1.0
	return maxf(0.2, base / maxf(0.2, haste))


func snap_to_owner() -> void:
	if not _owner_valid() or not owner_player.is_inside_tree() or not is_inside_tree():
		return
	global_position = _home()


func _physics_process(delta: float) -> void:
	step(delta)


## One physics step (tests drive it directly).
func step(delta: float) -> void:
	if dismissed:
		return
	if not _owner_valid():
		dismiss(true)
		return
	if not owner_player.is_inside_tree() or not is_inside_tree():
		return
	if owner_player.downed:
		dismiss()
		return
	life_left -= delta
	if life_left <= 0.0:
		dismiss()
		return
	_retarget_left -= delta
	if _retarget_left <= 0.0 or not _target_ok(target):
		_retarget_left = RETARGET_INTERVAL
		target = _find_target()
	_bite_left = maxf(0.0, _bite_left - delta)
	var prey := current_target()
	if prey != null:
		_hunt(prey, delta)
	else:
		_follow(delta)


## The hunted enemy while it is still a valid target (else null).
func current_target() -> Enemy:
	return target as Enemy if _target_ok(target) else null


func _hunt(prey: Enemy, delta: float) -> void:
	var here := _flat(global_position)
	var to := _flat(prey.global_position) - here
	var dist := to.length()
	var reach := prey.radius + BITE_REACH
	var dir := to / dist if dist > 0.001 else _flat(owner_player.facing)
	if dist > reach:
		var step_len := minf(RUN_SPEED * delta, dist - reach * 0.8)
		global_position = _clamp(here + dir * step_len)
		_bite_left = maxf(_bite_left, FIRST_BITE_DELAY * 0.5)
		_animate(dir, 1.0)
		return
	_animate(dir, 0.0)
	if _bite_left <= 0.0:
		_bite(prey)


func _bite(e: Enemy) -> void:
	_bite_left = bite_interval()
	if owner_player.procs == null or not _target_ok(e):
		return
	var dealt := owner_player.procs.deal_raw(e, bite_damage(), school, true, &"pet")
	bites += 1
	var slow := float(params.get("slow", 0.0)) * float(params.get("power", 1.0))
	if slow > 0.0 and is_instance_valid(e) and not e.is_dead():
		e.apply_slow(minf(slow, 90.0), float(params.get("slow_duration", 1.5)))
	var heal_pct := float(params.get("heal_pct", 0.0))
	if heal_pct > 0.0 and dealt > 0.0:
		owner_player.heal(dealt * heal_pct / 100.0)
	if model != null:
		model.play_bite()
	if is_instance_valid(e) and e.is_inside_tree():
		Vfx.hit_spark(e.global_position + Vector3.UP * 0.5, BITE_COLOR)


func _follow(delta: float) -> void:
	var here := _flat(global_position)
	var home := _home()
	var to := home - here
	var dist := to.length()
	if dist > TELEPORT_DISTANCE:
		snap_to_owner()
		_animate(owner_player.facing, 0.0)
		return
	if dist < 0.05:
		_animate(owner_player.facing, 0.0)
		return
	var step_len := minf(FOLLOW_SPEED * delta, dist)
	global_position = _clamp(here + to / dist * step_len)
	_animate(to / dist if dist > 0.3 else owner_player.facing, clampf(dist / 1.0, 0.0, 1.0))


func _animate(dir: Vector3, moving: float) -> void:
	if model != null:
		model.set_facing(dir)
		model.set_moving(moving)


## Nearest living enemy to the wolf within leash m of the master (ties: group order).
func _find_target() -> Enemy:
	var leash := float(params.get("leash", 8.0))
	var master := _flat(owner_player.global_position)
	var best: Enemy = null
	var best_d := INF
	for node in EnemyGrid.gather_around(get_tree(), master, leash):
		if not _target_ok(node):
			continue
		var e := node as Enemy
		if GeneralKit.flat_distance(e.global_position, master) > leash:
			continue
		var d := GeneralKit.flat_distance(e.global_position, global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _target_ok(candidate: Variant) -> bool:
	if candidate == null or not is_instance_valid(candidate):
		return false
	var e := candidate as Enemy
	if e == null or e.is_queued_for_deletion() or e.is_dead() or not e.is_inside_tree():
		return false
	var leash := float(params.get("leash", 8.0)) + 1.0
	return GeneralKit.flat_distance(e.global_position, owner_player.global_position) <= leash


## The wolf's spot beside the master: behind its shoulders, the pack fanned out.
func _home() -> Vector3:
	var facing := _flat(owner_player.facing)
	if facing.length_squared() < 0.0001:
		facing = Vector3.FORWARD
	facing = facing.normalized()
	var side := 1.0 if pack_index % 2 == 0 else -1.0
	var angle := side * (PACK_ANGLE + 0.5 * floorf(pack_index * 0.5))
	var dir := (-facing).rotated(Vector3.UP, angle)
	return _flat(owner_player.global_position) + dir * FOLLOW_DISTANCE


func _clamp(pos: Vector3) -> Vector3:
	var arena := Arena.current
	if arena != null and is_instance_valid(arena):
		return arena.clamp_point(pos, 0.4)
	return pos


func _owner_valid() -> bool:
	return owner_player != null and is_instance_valid(owner_player) and not owner_player.is_queued_for_deletion()


func _puff() -> void:
	if is_inside_tree():
		Vfx.death_puff(global_position + Vector3.UP * 0.5, SPIRIT_COLOR, 0.6)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
