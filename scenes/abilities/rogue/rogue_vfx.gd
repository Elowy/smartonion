class_name RogueVfx
extends Node3D
## Rogue ability effects (placeholder art, purely visual – no gameplay state, no RunState.rng):
##   [method streak]     – a fading shadow ribbon on the ground between two points (Shadowstep,
##                         Killing Spree jumps),
##   [method step_puff]  – smoke where a teleport leaves / arrives,
##   [method cheat_death] – a dark ring with rising pale wisps when Cheat Death saves the Rogue.
## Frees itself.

const SHADOW_COLOR := Color(0.55, 0.38, 0.9)
const SMOKE_COLOR := Color(0.32, 0.28, 0.42)
const POISON_COLOR := Color(0.45, 0.95, 0.3)
const CHEAT_DEATH_COLOR := Color(0.85, 0.82, 1.0)
const STREAK_LIFE := 0.35
const STREAK_WIDTH := 0.55
const STREAK_ALPHA := 0.55
const GROUND_Y := 0.08

var life := STREAK_LIFE
var _age := 0.0
var _material: StandardMaterial3D
var _alpha := STREAK_ALPHA


## A shadow ribbon from [param from] to [param to] (world positions, drawn on the ground).
static func streak(from: Vector3, to: Vector3, color: Color = SHADOW_COLOR) -> void:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var length := flat.length()
	if length < 0.1:
		return
	var parent := Vfx.effect_parent()
	if parent == null or not parent.is_inside_tree():
		return
	var fx := RogueVfx.new()
	fx.name = "RogueStreak"
	parent.add_child(fx)
	fx.global_position = Vector3((from.x + to.x) * 0.5, GROUND_Y, (from.z + to.z) * 0.5)
	fx.rotation.y = atan2(-flat.x, -flat.z)
	fx._build_streak(length, color)


## Smoke where a teleporting Rogue leaves or lands ([param pos]: feet).
static func step_puff(pos: Vector3, size: float = 0.8) -> void:
	Vfx.death_puff(pos + Vector3.UP * 0.5, SMOKE_COLOR, size)


## Cheat Death saved the Rogue at [param pos] (feet).
static func cheat_death(pos: Vector3) -> void:
	Vfx.explosion(Vector3(pos.x, 0.1, pos.z), 1.6, SHADOW_COLOR)
	Vfx.death_puff(pos + Vector3.UP * 0.6, CHEAT_DEATH_COLOR, 1.2)
	var parent := Vfx.effect_parent()
	if parent == null or not parent.is_inside_tree():
		return
	var fx := RogueVfx.new()
	fx.name = "CheatDeathWisps"
	fx.life = 1.0
	parent.add_child(fx)
	fx.global_position = Vector3(pos.x, 0.0, pos.z)
	fx._build_wisps()


func _process(delta: float) -> void:
	_age += delta
	if _age >= life:
		queue_free()
		return
	if _material != null:
		_material.albedo_color.a = _alpha * (1.0 - _age / life)


func _build_streak(length: float, color: Color) -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.albedo_color = Color(color.r, color.g, color.b, STREAK_ALPHA)
	var quad := PlaneMesh.new()
	quad.size = Vector2(STREAK_WIDTH, length)
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# A darker core line makes it read as a shadow, not a light beam.
	var core := MeshInstance3D.new()
	var core_quad := PlaneMesh.new()
	core_quad.size = Vector2(STREAK_WIDTH * 0.25, length)
	core.mesh = core_quad
	core.material_override = Mats.unshaded(Color(0.16, 0.08, 0.3, 0.4))
	core.position.y = 0.01
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)


func _build_wisps() -> void:
	var p := CPUParticles3D.new()
	p.name = "Wisps"
	p.amount = 16
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 0.6
	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.16
	mesh.radial_segments = 6
	mesh.rings = 3
	p.mesh = mesh
	p.material_override = Mats.particle(true, true)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 0.9
	p.emission_ring_inner_radius = 0.4
	p.emission_ring_height = 0.1
	p.direction = Vector3.UP
	p.spread = 10.0
	p.gravity = Vector3(0, 1.5, 0)
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 2.8
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(CHEAT_DEATH_COLOR, 0.9))
	ramp.set_color(1, Color(SHADOW_COLOR, 0.0))
	p.color_ramp = ramp
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position.y = 0.2
	add_child(p)
	p.emitting = true
