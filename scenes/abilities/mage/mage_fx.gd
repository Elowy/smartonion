class_name MageFx
extends Node3D
## Procedural looks of the Mage's learned spells (placeholder art from primitives): spell
## trails, the Frost Nova burst, ice shattering, the meteor impact, the burning / frozen
## ground of an [AbilityArea] and the Ice Block. Purely visual – gameplay never waits for
## them, no RunState.rng. One-shot effects free themselves after [member life] seconds;
## they do nothing without a parent for effects (unit tests without a scene).

enum Kind { NOVA, SHATTER, IMPACT, ICE_BLOCK, GROUND_FIRE, GROUND_FROST }

const FIRE_CORE := Color(1.0, 0.9, 0.5)
const ICE := Color(0.75, 0.93, 1.0)
const MIST := Color(0.85, 0.95, 1.0)
const ROCK := Color(0.32, 0.2, 0.16)

const _ICE_CODE := """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, blend_mix, shadows_disabled;
uniform vec4 color : source_color = vec4(0.65, 0.88, 1.0, 0.2);
void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	ALBEDO = mix(color.rgb, vec3(1.0), f * 0.8);
	ALPHA = clamp(color.a + f * 0.65, 0.0, 1.0);
}
"""

static var _ice_shader: Shader
static var _ice_materials: Dictionary[String, Material] = {}

var kind: Kind = Kind.NOVA
var life := 0.7
var age := 0.0
var radius := 1.0
var color := Color.WHITE
## Hero an ICE_BLOCK belongs to (it melts early when the hero goes down).
var player: Player
var _ring: MeshInstance3D
var _parts: Array[Node3D] = []


## A continuous world-space trail for a bolt (child of the bolt, freed with it).
static func trail(p_color: Color, p_scale: float = 1.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Trail"
	p.amount = clampi(roundi(12.0 * p_scale), 8, 40)
	p.lifetime = 0.3
	p.local_coords = false
	p.mesh = _ball()
	p.material_override = Mats.particle(false)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.08
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.5
	p.gravity = Vector3(0.0, 0.6, 0.0)
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.2
	p.color_ramp = _gradient(Color(p_color.lerp(Color(1.0, 0.95, 0.7), 0.45), 0.9), Color(p_color, 0.0))
	p.emitting = true
	return p


## Look of a Mage bolt (faces -Z): a bright core, a coloured shell and a tapering tail.
static func bolt_look(p_color: Color) -> Node3D:
	var root := Node3D.new()
	var core := _mesh(root, _sphere("mage:bolt_core", 0.11), Mats.glow(p_color.lerp(Color(1.0, 0.97, 0.85), 0.6), 3.0))
	core.position = Vector3.ZERO
	_mesh(root, _sphere("mage:bolt_shell", 0.2), Mats.unshaded(Color(p_color, 0.72)))
	var tail := _mesh(root, MeshKit.cached("mage:bolt_tail", func() -> Mesh:
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = 0.18
		c.height = 0.8
		c.radial_segments = 10
		c.rings = 1
		return c), Mats.unshaded(Color(p_color.lerp(Color(1.0, 0.9, 0.5), 0.25), 0.5)))
	# Narrow end behind (+Z), wide end at the bolt.
	tail.rotation_degrees = Vector3(90, 0, 0)
	tail.position = Vector3(0, 0, 0.38)
	return root


## Frost Nova: a ring of frost races out to [param p_radius], ice spikes burst from the
## ground around the hero and a cold mist rolls outwards.
static func frost_nova(center: Vector3, p_radius: float) -> MageFx:
	var fx := _make(Kind.NOVA, center, 0.75, p_radius, MageSpell.FROST_COLOR)
	if fx == null:
		return null
	fx._add_ring(fx.color)
	var spike := _spike()
	var mat := Mats.glow(ICE, 1.2)
	var n := clampi(roundi(p_radius * 4.0), 8, 26)
	for i in n:
		var a := TAU * float(i) / float(n)
		var dist := p_radius * (0.6 if i % 2 == 0 else 0.9)
		var mi := _mesh(fx, spike, mat)
		var out := Vector3(cos(a), 0.0, sin(a))
		mi.position = out * dist
		mi.basis = Basis(out.cross(Vector3.UP).normalized(), -0.35)
		mi.set_meta(&"delay", dist / maxf(0.1, p_radius) * 0.18)
		mi.scale = Vector3.ONE * 0.01
		fx._parts.append(mi)
	var mist := fx._burst(18, 0.6, _ball(), Color(MIST, 0.8), Color(MIST, 0.0))
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	mist.emission_ring_axis = Vector3.UP
	mist.emission_ring_radius = 0.5
	mist.emission_ring_inner_radius = 0.2
	mist.emission_ring_height = 0.1
	mist.direction = Vector3(1, 0, 0)
	mist.spread = 180.0
	mist.flatness = 1.0
	mist.initial_velocity_min = p_radius * 2.2
	mist.initial_velocity_max = p_radius * 3.0
	mist.damping_min = p_radius * 3.0
	mist.damping_max = p_radius * 4.0
	mist.scale_amount_min = 1.2
	mist.scale_amount_max = 2.2
	mist.position.y = 0.25
	_start(fx)
	return fx


## Ice bursting into glittering chips (shatter, a broken barrier).
static func shatter(pos: Vector3, p_radius: float = 1.0) -> MageFx:
	var fx := _make(Kind.SHATTER, pos, 0.6, p_radius, ICE)
	if fx == null:
		return null
	var chips := fx._burst(14, 0.55, _chip(), Color(ICE, 1.0), Color(ICE, 0.0))
	chips.direction = Vector3.UP
	chips.spread = 80.0
	chips.initial_velocity_min = 2.5 + p_radius
	chips.initial_velocity_max = 4.5 + p_radius * 1.5
	chips.gravity = Vector3(0, -12, 0)
	chips.angular_velocity_min = -500.0
	chips.angular_velocity_max = 500.0
	chips.scale_amount_min = 0.8
	chips.scale_amount_max = 1.5
	Vfx.hit_spark(pos, ICE)
	_start(fx)
	return fx


## Meteor impact: a fire blast over [param p_radius], rock debris and a scorched ring.
static func impact(center: Vector3, p_radius: float) -> MageFx:
	var fx := _make(Kind.IMPACT, center, 0.9, p_radius, MageSpell.FIRE_COLOR)
	if fx == null:
		return null
	fx._add_ring(Color(1.0, 0.55, 0.15))
	var debris := fx._burst(16, 0.8, _chip(), Color(0.5, 0.3, 0.2, 1.0), Color(0.25, 0.15, 0.1, 0.0))
	debris.direction = Vector3.UP
	debris.spread = 60.0
	debris.initial_velocity_min = 4.0
	debris.initial_velocity_max = 8.0
	debris.gravity = Vector3(0, -18, 0)
	debris.angular_velocity_min = -400.0
	debris.angular_velocity_max = 400.0
	debris.scale_amount_min = 1.5
	debris.scale_amount_max = 2.8
	var flames := fx._burst(22, 0.6, _ball(), Color(FIRE_CORE, 1.0), Color(MageSpell.FIRE_COLOR, 0.0))
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flames.emission_sphere_radius = p_radius * 0.35
	flames.direction = Vector3.UP
	flames.spread = 70.0
	flames.initial_velocity_min = 2.0
	flames.initial_velocity_max = 5.0
	flames.damping_min = 3.0
	flames.damping_max = 5.0
	flames.scale_amount_min = 2.0
	flames.scale_amount_max = 3.5
	Vfx.explosion(center + Vector3.UP * 0.3, p_radius, MageSpell.FIRE_COLOR)
	_start(fx)
	return fx


## Ice Block: [param p_player] encased in ice for [param duration] seconds (melts early when
## the hero goes down). Child of the hero.
static func ice_block(p_player: Player, duration: float) -> MageFx:
	if p_player == null or not p_player.is_inside_tree():
		return null
	var fx := MageFx.new()
	fx.name = "IceBlock"
	fx.kind = Kind.ICE_BLOCK
	fx.life = maxf(0.1, duration)
	fx.color = ICE
	fx.player = p_player
	var block := _mesh(fx, MeshKit.cached("mage:ice_block", func() -> Mesh:
		var b := BoxMesh.new()
		b.size = Vector3(1.25, 1.6, 1.25)
		return b), Mats.unshaded(Color(0.72, 0.9, 1.0, 0.42)))
	block.position.y = 0.78
	block.rotation.y = 0.35
	var crystal := _spike()
	var mat := Mats.glow(ICE, 1.3)
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.35
		var c := _mesh(fx, crystal, mat)
		var out := Vector3(cos(a), 0.0, sin(a))
		c.position = out * 0.72 + Vector3.UP * 0.25
		c.basis = Basis(out.cross(Vector3.UP).normalized(), -0.3) * Basis.from_scale(Vector3.ONE * 1.4)
	p_player.add_child(fx)
	return fx


## Embers and licking flames over a burning [AbilityArea] (child of the area, freed with it).
static func ground_fire(area: AbilityArea) -> MageFx:
	var fx := MageFx.new()
	fx.name = "BurningGround"
	fx.kind = Kind.GROUND_FIRE
	fx.life = area.duration
	fx.radius = area.radius
	fx.color = MageSpell.FIRE_COLOR
	fx._add_ring(Color(1.0, 0.4, 0.08))
	var p := CPUParticles3D.new()
	p.name = "Embers"
	p.amount = clampi(roundi(area.radius * area.radius * 3.0), 12, 70)
	p.lifetime = 0.7
	p.local_coords = false
	p.mesh = _ball()
	p.material_override = Mats.particle(true)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = area.radius * 0.95
	p.emission_ring_inner_radius = 0.0
	p.emission_ring_height = 0.05
	p.direction = Vector3.UP
	p.spread = 15.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.0
	p.gravity = Vector3(0, 0.8, 0)
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.8
	p.color_ramp = _gradient(Color(FIRE_CORE, 0.95), Color(1.0, 0.25, 0.05, 0.0))
	p.position.y = 0.1
	p.emitting = true
	fx.add_child(p)
	area.add_child(fx)
	return fx


## Frost crystals frozen into the ground of an [AbilityArea] (Frozen Ground).
static func ground_frost(area: AbilityArea) -> MageFx:
	var fx := MageFx.new()
	fx.name = "FrozenGround"
	fx.kind = Kind.GROUND_FROST
	fx.life = area.duration
	fx.radius = area.radius
	fx.color = MageSpell.FROST_COLOR
	fx._add_ring(Color(0.7, 0.92, 1.0))
	var spike := _spike()
	var mat := Mats.glow(ICE, 1.0)
	var n := clampi(roundi(area.radius * area.radius * 1.6), 6, 40)
	for i in n:
		# Golden-angle spiral: evenly spread, no randomness.
		var a := float(i) * 2.39996
		var r := sqrt((float(i) + 0.5) / float(n)) * area.radius * 0.92
		var mi := _mesh(fx, spike, mat)
		mi.position = Vector3(cos(a) * r, 0.0, sin(a) * r)
		var out := Vector3(cos(a), 0.0, sin(a))
		mi.basis = Basis(out.cross(Vector3.UP).normalized(), -0.25)
		mi.set_meta(&"size", 0.55 + 0.1 * float(i % 4))
		mi.scale = Vector3.ONE * 0.01
		fx._parts.append(mi)
	area.add_child(fx)
	return fx


func _process(delta: float) -> void:
	age += delta
	var t := clampf(age / maxf(life, 0.001), 0.0, 1.0)
	match kind:
		Kind.NOVA:
			_ring_out(0.25, radius, 0.22, 0.35)
			for mi in _parts:
				var d: float = mi.get_meta(&"delay", 0.0)
				var up := smoothstep(d, d + 0.1, age)
				var down := 1.0 - smoothstep(life * 0.6, life, age)
				mi.scale = Vector3.ONE * maxf(0.01, up * down * 1.3)
		Kind.IMPACT:
			_ring_out(radius * 0.3, radius * 1.1, 0.5, 0.5)
		Kind.ICE_BLOCK:
			if player == null or not is_instance_valid(player) or player.downed:
				age = life
		Kind.GROUND_FIRE, Kind.GROUND_FROST:
			var fade := clampf(minf(age / 0.25, (life - age) / 0.4), 0.0, 1.0)
			if _ring != null:
				var pulse := 0.85 + 0.15 * sin(age * 7.0)
				Mats.set_ring(_ring, Color(color, 0.85 * fade * pulse), 0.9, 0.99, 0.08 * fade)
			for mi in _parts:
				var s: float = mi.get_meta(&"size", 1.0)
				mi.scale = Vector3(s, s * maxf(0.01, fade), s)
	if t >= 1.0:
		if kind == Kind.ICE_BLOCK:
			MageFx.shatter(global_position + Vector3.UP * 0.8, 1.0)
		queue_free()


## Expanding ground ring: [param from_r] -> [param to_r] (m) over [param grow] s, then
## fading for [param fade] s.
func _ring_out(from_r: float, to_r: float, grow: float, fade: float) -> void:
	if _ring == null:
		return
	var g := smoothstep(0.0, grow, age)
	var r := lerpf(from_r, to_r, g)
	_ring.scale = Vector3(r * 2.0, 1.0, r * 2.0)
	var a := 1.0 - smoothstep(grow, grow + fade, age)
	Mats.set_ring(_ring, Color(color, 0.95 * a), 0.72, 0.98, 0.18 * a)


func _add_ring(c: Color) -> void:
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	_ring.mesh = MeshKit.cached("mage:quad", func() -> Mesh:
		var q := PlaneMesh.new()
		q.size = Vector2(1, 1)
		return q)
	_ring.material_override = Mats.ring()
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position.y = 0.07
	_ring.scale = Vector3(radius * 2.0, 1.0, radius * 2.0)
	Mats.set_ring(_ring, Color(c, 0.0), 0.8, 0.98, 0.0)
	color = c
	add_child(_ring)


## A one-shot burst of particles (world space).
func _burst(amount: int, p_life: float, mesh: Mesh, from: Color, to: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = p_life
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.mesh = mesh
	p.material_override = Mats.particle(true)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.color_ramp = _gradient(from, to)
	p.emitting = true
	add_child(p)
	return p


static func _make(p_kind: Kind, pos: Vector3, p_life: float, p_radius: float, c: Color) -> MageFx:
	var parent := Vfx.effect_parent()
	if parent == null:
		return null
	var fx := MageFx.new()
	fx.name = "MageFx_%s" % Kind.keys()[p_kind]
	fx.kind = p_kind
	fx.life = p_life
	fx.radius = maxf(0.3, p_radius)
	fx.color = c
	fx.set_meta(&"parent", parent)
	fx.position = pos
	return fx


static func _start(fx: MageFx) -> void:
	var parent: Node = fx.get_meta(&"parent")
	fx.remove_meta(&"parent")
	var pos := fx.position
	parent.add_child(fx)
	fx.global_position = pos
	for child in fx.get_children():
		if child is CPUParticles3D:
			(child as CPUParticles3D).restart()


static func _mesh(parent: Node3D, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _gradient(from: Color, to: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, from)
	g.set_color(1, to)
	return g


static func _sphere(key: String, r: float) -> Mesh:
	return MeshKit.cached(key, func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = 12
		s.rings = 6
		return s)


## Clear ice with a bright rim (fresnel), for bubbles and shells. Cached per colour.
static func ice_material(c: Color) -> Material:
	var key := c.to_html()
	if _ice_materials.has(key):
		return _ice_materials[key]
	if _ice_shader == null:
		_ice_shader = Shader.new()
		_ice_shader.code = _ICE_CODE
	var m := ShaderMaterial.new()
	m.shader = _ice_shader
	m.set_shader_parameter("color", c)
	m.render_priority = 1
	_ice_materials[key] = m
	return m


static func _ball() -> Mesh:
	return MeshKit.cached("mage:ball", func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = 0.09
		s.height = 0.18
		s.radial_segments = 6
		s.rings = 3
		return s)


static func _chip() -> Mesh:
	return MeshKit.cached("mage:chip", func() -> Mesh:
		var b := BoxMesh.new()
		b.size = Vector3(0.09, 0.07, 0.06)
		return b)


## Upward ice spike (apex up, origin at its base).
static func _spike() -> Mesh:
	return MeshKit.cached("mage:spike", func() -> Mesh:
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = 0.13
		c.height = 0.75
		c.radial_segments = 4
		c.rings = 1
		# Shift up so the base sits on the ground.
		var arr := c.get_mesh_arrays()
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in verts.size():
			verts[i].y += 0.375
		arr[Mesh.ARRAY_VERTEX] = verts
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m)
