class_name HunterBleed
extends Node3D
## A wound left by a Hunter ability (Long Shot's Rending Shaft, Hunt Signal's Open Wound):
## [member rate] x [member left] damage still to come, dealt every [constant TICK] seconds through
## the Hunter's ProcSystem.deal_raw (kill credit, damage meter, the Mastery multiplier of the
## [member source]; no crits, no on-hit procs). A child of the bleeding enemy – freed with it –
## with a few blood drops. One bleed per Hunter, enemy and [member key]: a new one adds its damage
## to what still bleeds and restarts the clock. Keeps bleeding while the Hunter is downed (like
## every DoT); ends when the Hunter is freed. No RNG.

const TICK := 0.5
const EPSILON := 0.0001
const BLOOD := Color(0.78, 0.06, 0.08, 0.95)
const BLOOD_FADE := Color(0.5, 0.02, 0.04, 0.0)

var caster: Player
var enemy: Enemy
var key: StringName = &"bleed"
## Damage source for the Mastery: &"dot" (Long Shot) or &"pet" (the companion's Hunt Signal).
var source: StringName = &"dot"
var school: StringName = &"physical"
var rate := 0.0
var left := 0.0
## Damage dealt so far and ticks done (tests).
var dealt := 0.0
var ticks := 0

var _tick_left := TICK
var _owed := 0.0


## Makes [param e] bleed for [param total] damage over [param duration] seconds (added to a running
## bleed of the same [param p_caster] and [param p_key]). Null when nothing bleeds.
static func apply(e: Enemy, p_caster: Player, total: float, duration: float, p_key: StringName = &"bleed",
		p_source: StringName = &"dot") -> HunterBleed:
	if not HunterKit.is_live(e) or p_caster == null or not is_instance_valid(p_caster) or total <= 0.0 or duration <= 0.0:
		return null
	var bleed := find(e, p_caster, p_key)
	if bleed != null:
		total += bleed.remaining()
		bleed._owed = 0.0
	else:
		bleed = HunterBleed.new()
		bleed.name = _node_name(p_caster, p_key)
		bleed.caster = p_caster
		bleed.enemy = e
		bleed.key = p_key
		e.add_child(bleed)
		bleed.position = Vector3.UP * Enemy.BODY_CENTER_HEIGHT
		bleed._build_drops(e.radius)
	bleed.source = p_source
	bleed.left = duration
	bleed.rate = total / duration
	return bleed


## The running bleed of [param p_caster] with [param p_key] on [param e] (null = none).
static func find(e: Enemy, p_caster: Player, p_key: StringName = &"bleed") -> HunterBleed:
	if e == null or not is_instance_valid(e) or p_caster == null or not is_instance_valid(p_caster):
		return null
	var bleed := e.get_node_or_null(NodePath(_node_name(p_caster, p_key))) as HunterBleed
	if bleed == null or bleed.is_queued_for_deletion() or bleed.left <= EPSILON:
		return null
	return bleed


## Damage still to come (incl. what bled since the last tick).
func remaining() -> float:
	return rate * maxf(0.0, left) + _owed


func _physics_process(delta: float) -> void:
	if is_queued_for_deletion():
		return
	if not HunterKit.is_live(enemy) or not is_instance_valid(caster):
		_end()
		return
	_owed += rate * clampf(left, 0.0, delta)
	left -= delta
	_tick_left -= delta
	if _tick_left > EPSILON and left > EPSILON:
		return
	_tick_left += TICK
	var amount := _owed
	_owed = 0.0
	if amount > 0.0 and caster.procs != null:
		ticks += 1
		dealt += caster.procs.deal_raw(enemy, amount, school, true, source)
	if left <= EPSILON or not HunterKit.is_live(enemy):
		_end()


func _end() -> void:
	set_physics_process(false)
	# Free the name at once so a new bleed can take it while this one waits for deletion.
	name = "SpentBleed"
	queue_free()


static func _node_name(p_caster: Player, p_key: StringName) -> String:
	return "HunterBleed_%d_%s" % [p_caster.get_instance_id(), p_key]


## A few blood drops falling off the body (world-space particles: they trail a walking enemy).
func _build_drops(body_radius: float) -> void:
	var p := CPUParticles3D.new()
	p.name = "Drops"
	p.amount = 5
	p.lifetime = 0.55
	p.local_coords = false
	p.mesh = MeshKit.cached("hunter:drop", func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = 0.045
		s.height = 0.09
		s.radial_segments = 6
		s.rings = 3
		return s)
	p.material_override = Mats.particle(false)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = maxf(0.12, body_radius * 0.5)
	p.direction = Vector3.DOWN
	p.spread = 25.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.7
	p.gravity = Vector3(0.0, -4.0, 0.0)
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.3
	var g := Gradient.new()
	g.set_color(0, BLOOD)
	g.set_color(1, BLOOD_FADE)
	p.color_ramp = g
	p.emitting = true
	add_child(p)
