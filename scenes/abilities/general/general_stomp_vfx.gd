class_name GeneralStompVfx
extends Node3D
## War Stomp's shockwave: an earth-coloured ring racing out to the stomp radius, a cracked
## ground disc that fades, flying rock chips and a dust puff. Frees itself. Purely visual.

const LIFE := 0.55
const RING_TIME := 0.25
const EARTH := Color(0.62, 0.48, 0.3)
const DUST := Color(0.78, 0.68, 0.5)
const CRACK := Color(0.3, 0.2, 0.12)

var radius := 2.5
var _age := 0.0
var _ring: MeshInstance3D
var _cracks: MeshInstance3D
var _crack_material: StandardMaterial3D


## A shockwave of [param p_radius] m at [param pos] (ground). Null without a scene tree.
static func spawn(pos: Vector3, p_radius: float, tint: Color = EARTH) -> GeneralStompVfx:
	var parent := Vfx.effect_parent()
	if parent == null:
		return null
	var fx := GeneralStompVfx.new()
	fx.name = "WarStomp"
	fx.radius = maxf(0.5, p_radius)
	parent.add_child(fx)
	fx.global_position = Vector3(pos.x, 0.0, pos.z)
	fx._build(tint)
	Vfx.death_puff(Vector3(pos.x, 0.25, pos.z), DUST, clampf(p_radius * 0.5, 0.8, 2.0))
	return fx


func _build(tint: Color) -> void:
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	_ring.mesh = MeshKit.cached("general:aura_quad", func() -> Mesh:
		var q := PlaneMesh.new()
		q.size = Vector2(2.0, 2.0)
		return q)
	_ring.material_override = Mats.ring()
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position.y = 0.06
	add_child(_ring)
	_crack_material = StandardMaterial3D.new()
	_crack_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_crack_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_crack_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_crack_material.vertex_color_use_as_albedo = true
	_crack_material.albedo_color = Color(1, 1, 1, 0.85)
	_cracks = MeshInstance3D.new()
	_cracks.name = "Cracks"
	_cracks.mesh = MeshKit.cached("general:stomp_cracks", func() -> Mesh: return _crack_mesh())
	_cracks.material_override = _crack_material
	_cracks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cracks.position.y = 0.045
	_cracks.scale = Vector3(radius, 1.0, radius)
	add_child(_cracks)
	var chips := CPUParticles3D.new()
	chips.name = "Chips"
	chips.amount = clampi(roundi(radius * 6.0), 8, 24)
	chips.lifetime = 0.5
	chips.one_shot = true
	chips.explosiveness = 0.95
	chips.mesh = MeshKit.cached("general:chip", func() -> Mesh:
		var m := BoxMesh.new()
		m.size = Vector3(0.12, 0.08, 0.1)
		return m)
	chips.material_override = Mats.particle(false)
	chips.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chips.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	chips.emission_ring_axis = Vector3.UP
	chips.emission_ring_radius = radius * 0.6
	chips.emission_ring_inner_radius = 0.2
	chips.emission_ring_height = 0.05
	chips.direction = Vector3.UP
	chips.spread = 35.0
	chips.initial_velocity_min = 3.0
	chips.initial_velocity_max = 5.5
	chips.gravity = Vector3(0, -16, 0)
	chips.angular_velocity_min = -500.0
	chips.angular_velocity_max = 500.0
	var g := Gradient.new()
	g.set_color(0, Color(tint.r, tint.g, tint.b, 1.0))
	g.set_color(1, Color(tint.r * 0.7, tint.g * 0.7, tint.b * 0.7, 0.0))
	chips.color_ramp = g
	chips.position.y = 0.1
	add_child(chips)
	chips.emitting = true
	_update()


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFE:
		queue_free()
		return
	_update()


func _update() -> void:
	var k := clampf(_age / RING_TIME, 0.0, 1.0)
	var grow := 1.0 - (1.0 - k) * (1.0 - k)
	var r := maxf(0.2, radius * (0.25 + 0.8 * grow))
	_ring.scale = Vector3(r, 1.0, r)
	var fade := clampf(1.0 - (_age - RING_TIME) / (LIFE - RING_TIME), 0.0, 1.0) if _age > RING_TIME else 1.0
	Mats.set_ring(_ring, Color(DUST.r, DUST.g, DUST.b, 0.9 * fade), 0.78, 0.98, 0.18 * fade)
	_crack_material.albedo_color.a = 0.85 * clampf(1.0 - _age / LIFE, 0.0, 1.0)


## Jagged cracks radiating from the centre (unit radius, dark earth).
static func _crack_mesh() -> Mesh:
	var k := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 7:
		var a := TAU * float(i) / 7.0 + rng.randf_range(-0.2, 0.2)
		var p := Vector3.ZERO
		var walked := 0.0
		while walked < 0.9:
			var step := rng.randf_range(0.18, 0.3)
			a += rng.randf_range(-0.5, 0.5)
			var q := p + Vector3(sin(a), 0.0, -cos(a)) * step
			var dir := (q - p).normalized()
			var side := Vector3(-dir.z, 0.0, dir.x) * (0.035 * (1.0 - walked))
			k.add_mesh(_quad_strip(p, q, side), Transform3D.IDENTITY, CRACK)
			p = q
			walked += step
	return k.build()


static func _quad_strip(a: Vector3, b: Vector3, side: Vector3) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	st.add_vertex(a - side)
	st.add_vertex(b - side * 0.6)
	st.add_vertex(b + side * 0.6)
	st.add_vertex(a - side)
	st.add_vertex(b + side * 0.6)
	st.add_vertex(a + side)
	return st.commit()
