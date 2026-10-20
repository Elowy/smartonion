class_name EnemyCorpse
extends Node3D
## M7b: the visual-only corpse an enemy leaves when it dies (owned by the "visuals" module). A
## detached, lightweight node that reuses the dead model's SHARED meshes: it flashes, tips over away
## from the killer, then sinks into the ground (the ground hides it) under a darkening tint, and is
## done after [constant LIFE] seconds (elites and bosses: longer and with a stronger flash).
##
## Nothing about it is gameplay: a plain Node3D tree (Pivot -> Body, Arm [, Glow]) without collision
## shapes, groups, scripts of the enemy or timers other than its own animation, so the enemy itself
## still leaves the world and the grid exactly as before.
##
## Cheap by design (150+ enemies die in a late wave):
##   - at most [constant MAX_CORPSES] live at once – a new one recycles the oldest;
##   - finished corpses are hidden and reused (pooled under one "Corpses" node of the effect root);
##   - at most [constant MAX_SPAWNS_PER_FRAME] ordinary corpses per rendered frame (elites and
##     bosses always get one);
##   - the fade is the Mats overlay (cached, quantised variants of the shared toon material), the
##     sink is a Transform3D – no per-corpse materials, no Tween.
## Visual variation uses a private RandomNumberGenerator (never RunState.rng).

enum Tier { NORMAL, ELITE, BOSS }

const MAX_CORPSES := 40
const MAX_SPAWNS_PER_FRAME := 8
## Seconds a corpse lasts and how long its hit flash takes, per [enum Tier].
const LIFE: Array[float] = [0.6, 0.9, 1.7]
const FLASH_TIME: Array[float] = [0.14, 0.2, 0.4]
## The body tips over to this angle (rad) during the first FALL_RATIO of its life.
const FALL_ANGLE := 1.45
const FALL_RATIO := 0.32
## The sink (and the dark tint) starts at this share of the life.
const SINK_START := 0.4
## How deep (x model scale) it sinks, and how much it shrinks on the way.
const SINK_DEPTH := 0.95
const SINK_SHRINK := 0.25
const DARK_TINT := Color(0.1, 0.08, 0.12)
const HOLDER_NAME := "Corpses"

## Corpses in flight, oldest first, and finished ones waiting for reuse.
static var _active: Array[EnemyCorpse] = []
static var _idle: Array[EnemyCorpse] = []
static var _holder: Node3D
static var _budget_frame := -1
static var _budget_used := 0
static var _rng := RandomNumberGenerator.new()

var tier: Tier = Tier.NORMAL
var life := 0.6
var age := 0.0
var _pivot: Node3D
var _body: MeshInstance3D
var _arm: MeshInstance3D
var _glow: MeshInstance3D
var _material: Material
var _fall_axis := Vector3.RIGHT
var _yaw := 0.0
var _model_scale := 1.0
var _flash_color := Color.WHITE
## (kind, step) of the applied overlay – only re-applied when it changes.
var _overlay_state := Vector2i(-1, -1)


func _init() -> void:
	name = "Corpse"
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	_body = MeshInstance3D.new()
	_body.name = "Body"
	_pivot.add_child(_body)
	_arm = MeshInstance3D.new()
	_arm.name = "Arm"
	_pivot.add_child(_arm)


## A corpse standing in for [param model] (an [EnemyModel]) at world position [param pos] (the feet).
## It tips away from [param away] (a flat direction, e.g. from the killer to the victim; zero = a random
## side). [param accent] tints the flash of elites / bosses. Returns null when nothing was spawned (no
## model data, no effect root, or the per-frame budget of ordinary corpses is used up).
static func spawn(model: EnemyModel, pos: Vector3, p_tier: Tier = Tier.NORMAL, away: Vector3 = Vector3.ZERO,
		accent: Color = Color.WHITE) -> EnemyCorpse:
	if model == null or not is_instance_valid(model):
		return null
	var info := model.corpse_info()
	if info.is_empty():
		return null
	if p_tier == Tier.NORMAL and not _take_budget():
		return null
	var holder := _get_holder()
	if holder == null:
		return null
	var c := _acquire(holder)
	c._begin(info, holder.to_local(pos), p_tier, away, accent)
	return c


## Corpses currently animating / waiting for reuse.
static func active_count() -> int:
	_purge()
	return _active.size()


static func idle_count() -> int:
	_purge()
	return _idle.size()


## Forgets the pool (the nodes go with their parent; tests).
static func reset() -> void:
	_active.clear()
	_idle.clear()
	_holder = null
	_budget_frame = -1
	_budget_used = 0


static func _take_budget() -> bool:
	var f := Vfx.frame_id()
	if f != _budget_frame:
		_budget_frame = f
		_budget_used = 0
	if _budget_used >= MAX_SPAWNS_PER_FRAME:
		return false
	_budget_used += 1
	return true


static func _purge() -> void:
	for i in range(_active.size() - 1, -1, -1):
		if not is_instance_valid(_active[i]):
			_active.remove_at(i)
	for i in range(_idle.size() - 1, -1, -1):
		if not is_instance_valid(_idle[i]):
			_idle.remove_at(i)


static func _get_holder() -> Node3D:
	var parent := Vfx.effect_parent()
	if parent == null or not parent.is_inside_tree():
		return null
	if is_instance_valid(_holder) and _holder.is_inside_tree() and _holder.get_parent() == parent:
		return _holder
	var found := parent.get_node_or_null(HOLDER_NAME) as Node3D
	if found == null:
		found = Node3D.new()
		found.name = HOLDER_NAME
		parent.add_child(found)
	_holder = found
	return _holder


static func _acquire(holder: Node3D) -> EnemyCorpse:
	_purge()
	var c: EnemyCorpse = null
	# An idle one of this holder first, then a new one, else the oldest running corpse is recycled.
	while c == null and not _idle.is_empty():
		var candidate: EnemyCorpse = _idle.pop_back()
		if candidate.get_parent() == holder:
			c = candidate
	if c == null and _active.size() + _idle.size() < MAX_CORPSES:
		c = EnemyCorpse.new()
		holder.add_child(c)
	if c == null and not _active.is_empty():
		c = _active.pop_front()
	if c == null:
		c = EnemyCorpse.new()
		holder.add_child(c)
	_active.append(c)
	return c


func _exit_tree() -> void:
	_active.erase(self)
	_idle.erase(self)
	if _holder == self:
		_holder = null


func _begin(info: Dictionary, local_pos: Vector3, p_tier: Tier, away: Vector3, accent: Color) -> void:
	tier = p_tier
	life = LIFE[tier]
	age = 0.0
	_overlay_state = Vector2i(-1, -1)
	visible = true
	set_process(true)
	position = local_pos
	rotation = Vector3.ZERO
	scale = Vector3.ONE * float(info.get("node_scale", 1.0))
	_model_scale = float(info.get("scale", 1.0))
	_yaw = float(info.get("yaw", 0.0))
	_material = info.get("material", null)
	if _material == null:
		_material = Mats.toon_vc()
	_body.mesh = info["body"]
	_body.material_override = _material
	_arm.mesh = info["arm"]
	_arm.material_override = _material
	_arm.position = info.get("arm_pivot", Vector3.ZERO)
	_arm.rotation = Vector3(float(info.get("arm_x", 0.0)), 0.0, 0.0)
	_flash_color = Color.WHITE.lerp(accent, 0.6) if tier != Tier.NORMAL else Color.WHITE
	# Ordinary corpses are short-lived: no shadow pass for them (the enemy's shadow goes with it).
	var shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if tier == Tier.BOSS \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.cast_shadow = shadow
	_arm.cast_shadow = shadow
	# Glow parts (candle flame, eyes, crown) only stay on elites and bosses.
	if info.has("glow") and tier != Tier.NORMAL:
		if _glow == null:
			_glow = MeshInstance3D.new()
			_glow.name = "Glow"
			_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_pivot.add_child(_glow)
		_glow.mesh = info["glow"]
		_glow.material_override = info.get("glow_material", null)
		_glow.position = info["glow_pos"]
		_glow.scale = Vector3.ONE
		_glow.visible = true
	elif _glow != null:
		_glow.visible = false
	var dir := Vector3(away.x, 0.0, away.z)
	if dir.length_squared() < 0.0025:
		var a := _rng.randf() * TAU
		dir = Vector3(cos(a), 0.0, sin(a))
	else:
		# A little scatter so a pile of corpses killed from one spot does not look cloned.
		dir = dir.normalized().rotated(Vector3.UP, _rng.randf_range(-0.35, 0.35))
	_fall_axis = Vector3.UP.cross(dir.normalized()).normalized()
	_pose(0.0)


func _process(delta: float) -> void:
	age += delta
	_pose(clampf(age / maxf(life, 0.001), 0.0, 1.0))
	if age >= life:
		_release()


## Poses the corpse at [param t] (0..1 of its life).
func _pose(t: float) -> void:
	var fall_t := clampf(t / FALL_RATIO, 0.0, 1.0)
	var theta := FALL_ANGLE * (1.0 - pow(1.0 - fall_t, 2.2))
	var sink_t := smoothstep(SINK_START, 1.0, t)
	var shrink := 1.0 - SINK_SHRINK * sink_t
	_pivot.basis = (Basis(_fall_axis, theta) * Basis(Vector3.UP, _yaw)).scaled(Vector3.ONE * _model_scale * shrink)
	# Lying on its back / front the body would clip the floor: lift it a little while it tips, then sink.
	_pivot.position = Vector3(0.0, sin(theta) * 0.22 * _model_scale - sink_t * SINK_DEPTH * _model_scale, 0.0)
	if _glow != null and _glow.visible:
		_glow.scale = Vector3.ONE * (1.0 - sink_t)
	_apply_overlay(t, sink_t)


func _apply_overlay(t: float, sink_t: float) -> void:
	var flash_time := FLASH_TIME[tier]
	var state := Vector2i(0, 0)
	var color := _flash_color
	var amount := 0.0
	if age < flash_time:
		amount = (1.0 - age / flash_time) * 0.9
		state = Vector2i(1, roundi(amount * Mats.OVERLAY_STEPS))
	else:
		color = DARK_TINT
		amount = sink_t * 0.85
		state = Vector2i(2, roundi(amount * Mats.OVERLAY_STEPS))
	if state == _overlay_state:
		return
	_overlay_state = state
	var m := Mats.with_overlay(_material, color, float(state.y) / Mats.OVERLAY_STEPS)
	_body.material_override = m
	_arm.material_override = m


## Done: hidden and parked for reuse (or freed when the pool is full).
func _release() -> void:
	set_process(false)
	visible = false
	_active.erase(self)
	if _active.size() + _idle.size() < MAX_CORPSES:
		_idle.append(self)
	else:
		queue_free()
