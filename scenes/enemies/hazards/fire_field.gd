class_name FireField
extends EnemyHazard
## Vor'thalax's Fire Fields (GDD 8): a burning patch laid on a hero's position. It shows a
## marker for the telegraph time (1 s), then burns for [member duration] seconds (8): every
## [member tick_interval] seconds (1) each hero inside takes [member damage] (1x the boss's
## contact damage). The first tick lands the moment it ignites, so leave during the marker.

const FIRE := Color(1.0, 0.45, 0.1)
const EMBER := Color(1.0, 0.75, 0.25)

var duration := 8.0
var tick_interval := 1.0
## Damage ticks done so far / heroes hurt in total (tests).
var ticks := 0
var hits := 0

var _burn_age := 0.0
var _tick_left := 0.0
var _outline: MeshInstance3D
var _fill: MeshInstance3D
var _embers: CPUParticles3D


## A patch of [param p_radius] at [param pos]: telegraph, then [param p_duration] s of burning.
static func spawn(parent: Node, pos: Vector3, p_radius: float, p_telegraph: float, p_duration: float,
		p_tick_interval: float, p_damage: float, p_source: Node3D = null) -> FireField:
	var h := FireField.new()
	h.name = "FireField"
	h.radius = p_radius
	h.telegraph_time = p_telegraph
	h.duration = p_duration
	h.tick_interval = maxf(0.1, p_tick_interval)
	h.damage = p_damage
	h.source = p_source
	h.color = FIRE
	place(parent, h, pos)
	return h


## Seconds of burning left (0 while telegraphing or once it burnt out).
func burn_left() -> float:
	return maxf(0.0, duration - _burn_age) if stage == Stage.ACTIVE else 0.0


func _build() -> void:
	_outline = _ring("Outline", radius * 2.0)
	_fill = _ring("Fill", radius * 2.0)
	Mats.set_ring(_outline, FIRE, 0.9, 0.985, 0.1)
	Mats.set_ring(_fill, EMBER, 0.96, 1.0, 0.4)
	_embers = CPUParticles3D.new()
	_embers.name = "Embers"
	_embers.amount = 10
	_embers.lifetime = 1.1
	_embers.emitting = false
	_embers.mesh = MeshKit.cached("hazard:ember", func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = 0.07
		s.height = 0.14
		s.radial_segments = 6
		s.rings = 3
		return s)
	_embers.material_override = Mats.particle(true)
	_embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_embers.emission_sphere_radius = radius * 0.75
	_embers.direction = Vector3.UP
	_embers.spread = 25.0
	_embers.gravity = Vector3(0.0, 1.2, 0.0)
	_embers.initial_velocity_min = 0.6
	_embers.initial_velocity_max = 1.6
	_embers.scale_amount_min = 0.5
	_embers.scale_amount_max = 1.2
	var ramp := Gradient.new()
	ramp.set_color(0, EMBER)
	ramp.set_color(1, Color(FIRE.r, FIRE.g, FIRE.b, 0.0))
	_embers.color_ramp = ramp
	_embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_embers.position.y = 0.1
	add_child(_embers)


func _update_telegraph(progress: float) -> void:
	if _outline == null:
		return
	var pulse := 0.75 + 0.25 * sin(age * (6.0 + 14.0 * progress))
	Mats.set_ring(_outline, Color(FIRE.r, FIRE.g, FIRE.b, pulse), 0.9, 0.985, 0.08 + 0.1 * progress)
	var d := maxf(0.05, radius * 2.0 * progress)
	_fill.scale = Vector3(d, 1.0, d)


func _strike() -> void:
	_burn_age = 0.0
	_tick_left = 0.0
	_fill.scale = Vector3(radius * 2.0, 1.0, radius * 2.0)
	_embers.emitting = true
	_burn_tick()
	if stage == Stage.ACTIVE:
		_update_active(0.0)


func _update_active(delta: float) -> void:
	_burn_age += delta
	if _burn_age >= duration - 0.0001:
		_embers.emitting = false
		finish()
		return
	_tick_left -= delta
	if _tick_left <= 0.0:
		_burn_tick()
	# Flicker.
	var flick := 0.8 + 0.2 * sin(_burn_age * 9.0) + 0.06 * sin(_burn_age * 23.0)
	var fade_in := clampf(_burn_age / 0.3, 0.0, 1.0)
	var fade_out := clampf((duration - _burn_age) / 0.6, 0.0, 1.0)
	var a := fade_in * fade_out
	Mats.set_ring(_outline, Color(FIRE.r, FIRE.g, FIRE.b, a * flick), 0.9, 0.985, 0.2 * a)
	Mats.set_ring(_fill, Color(EMBER.r, EMBER.g, EMBER.b, a * 0.55 * flick), 0.96, 1.0, 0.32 * a)


func _burn_tick() -> void:
	_tick_left = tick_interval
	ticks += 1
	for hero in heroes_in_circle():
		hits += 1
		hit_hero(hero, damage)


func _update_fade(amount: float) -> void:
	if _outline == null:
		return
	Mats.set_ring(_outline, Color(FIRE.r, FIRE.g, FIRE.b, 0.5 * amount), 0.9, 0.985, 0.1 * amount)
	Mats.set_ring(_fill, Color(EMBER.r, EMBER.g, EMBER.b, 0.3 * amount), 0.96, 1.0, 0.1 * amount)
