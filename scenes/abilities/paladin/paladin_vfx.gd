class_name PaladinVfx
extends Node3D
## Procedural placeholder looks of the Paladin's learned abilities (GDD 6.4). Purely visual –
## the gameplay never waits for them.
##   * [method hammer_look] / [method shield_look]: the thrown hammer / shield of
##     PaladinHolyMissile (a "Spinner" child that Projectile spins).
##   * [method storm]: Divine Storm – golden blade arcs whirling around the Paladin, an
##     expanding holy ring and rising motes (fire and forget).
##   * [method crown]: Blessing of Kings cast – a golden crown pops over a hero's head.
##   * [method kings_mark]: three small golden crown gems circling a blessed hero at waist
##     height while the blessing lasts ([method finish] fades it early).
##   * [method bubble]: Divine Shield – a glowing golden sphere around a hero.
## Persistent looks are children of the hero (they follow it and die with it); their owner
## ends them with [method finish].

enum Kind { STORM, CROWN, KINGS_MARK, BUBBLE }

const GOLD := Color(1.0, 0.85, 0.38)
const LIGHT := Color(1.0, 0.95, 0.72)
const FADE_IN := 0.15
const FADE_OUT := 0.3
const STORM_TIME := 0.5
const STORM_ARCS := 3
const STORM_TURNS := 1.4
const CROWN_TIME := 1.4
const CROWN_HEIGHT := 3.0
const MARK_DIAMETER := 1.5
const MARK_GEMS := 3
const MARK_HEIGHT := 0.75
const BUBBLE_RADIUS := 0.85
const BUBBLE_CENTER := 0.62
## The bubble flickers during its last seconds (it is about to drop).
const BUBBLE_WARN := 0.7

const _BUBBLE_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.85, 0.4, 1.0);
uniform float strength = 1.0;
void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - facing, 2.0);
	ALBEDO = mix(tint.rgb, vec3(1.0), rim * 0.35);
	ALPHA = clamp((0.1 + rim * 0.95) * strength, 0.0, 1.0);
}
"""

static var _bubble_shader: Shader

var kind := Kind.STORM
var life := STORM_TIME
var age := 0.0
var radius := 1.0
var color := GOLD

var _spin: Node3D
var _ring: MeshInstance3D
var _body: MeshInstance3D
var _motes: CPUParticles3D
var _materials: Array[StandardMaterial3D] = []
var _alphas: Array[float] = []


# --- Thrown missiles -------------------------------------------------------------------------

## The Hammer of Justice: a gilded war hammer that spins flat (faces -Z, "Spinner" child).
static func hammer_look() -> Node3D:
	var root := Node3D.new()
	var tilt := Node3D.new()
	tilt.name = "Tilt"
	tilt.rotation_degrees = Vector3(22, 0, 0)
	root.add_child(tilt)
	var spinner := Node3D.new()
	spinner.name = "Spinner"
	tilt.add_child(spinner)
	var body := MeshInstance3D.new()
	body.name = "Hammer"
	body.mesh = MeshKit.cached("paladin:hammer", func() -> Mesh:
		var k := MeshKit.new()
		k.add_cylinder(0.04, 0.04, 0.56, MeshKit.xf(Vector3(0, 0, 0.12), Vector3(90, 0, 0)), Color(0.5, 0.33, 0.18))
		k.add_sphere(0.06, MeshKit.xf(Vector3(0, 0, 0.42)), Color(0.95, 0.78, 0.32), 8, 4)
		k.add_box(Vector3(0.42, 0.22, 0.22), MeshKit.xf(Vector3(0, 0, -0.2)), Color(0.86, 0.84, 0.8))
		k.add_box(Vector3(0.07, 0.27, 0.27), MeshKit.xf(Vector3(0.22, 0, -0.2)), Color(1.0, 0.82, 0.35))
		k.add_box(Vector3(0.07, 0.27, 0.27), MeshKit.xf(Vector3(-0.22, 0, -0.2)), Color(1.0, 0.82, 0.35))
		k.add_box(Vector3(0.44, 0.06, 0.06), MeshKit.xf(Vector3(0, 0.12, -0.2)), Color(1.0, 0.82, 0.35))
		return k.build())
	body.material_override = Mats.toon_vc()
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spinner.add_child(body)
	var glow := MeshInstance3D.new()
	glow.name = "Glow"
	glow.mesh = _glow_sphere()
	glow.material_override = Mats.glow(Color(GOLD.r, GOLD.g, GOLD.b, 0.32), 1.6)
	glow.position = Vector3(0, 0, -0.12)
	glow.scale = Vector3(1.0, 0.8, 1.15)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spinner.add_child(glow)
	root.scale = Vector3.ONE * 1.25
	return root


## Avenger's Shield: a round steel shield with a gilded rim and a holy glow, spinning flat.
static func shield_look() -> Node3D:
	var root := Node3D.new()
	var tilt := Node3D.new()
	tilt.name = "Tilt"
	tilt.rotation_degrees = Vector3(12, 0, 0)
	root.add_child(tilt)
	var spinner := Node3D.new()
	spinner.name = "Spinner"
	tilt.add_child(spinner)
	var body := MeshInstance3D.new()
	body.name = "Shield"
	body.mesh = MeshKit.cached("paladin:shield", func() -> Mesh:
		var k := MeshKit.new()
		var gold := Color(1.0, 0.8, 0.32)
		k.add_cylinder(0.36, 0.36, 0.06, Transform3D.IDENTITY, Color(0.36, 0.46, 0.78), 20)
		k.add_torus(0.33, 0.42, Transform3D.IDENTITY, gold, 20, 6)
		k.add_box(Vector3(0.5, 0.03, 0.08), MeshKit.xf(Vector3(0, 0.035, 0)), gold)
		k.add_box(Vector3(0.08, 0.03, 0.5), MeshKit.xf(Vector3(0, 0.035, 0)), gold)
		k.add_sphere(0.1, MeshKit.xf(Vector3(0, 0.04, 0), Vector3.ZERO, Vector3(1, 0.6, 1)), Color(1.0, 0.92, 0.6), 10, 5)
		return k.build())
	body.material_override = Mats.toon_vc()
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spinner.add_child(body)
	var glow := MeshInstance3D.new()
	glow.name = "Glow"
	glow.mesh = _glow_sphere()
	glow.material_override = Mats.glow(Color(GOLD.r, GOLD.g, GOLD.b, 0.2), 1.4)
	glow.scale = Vector3(1.9, 0.5, 1.9)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spinner.add_child(glow)
	root.scale = Vector3.ONE * 1.35
	return root


# --- Fire and forget / persistent looks --------------------------------------------------------

## Divine Storm around [param pos] (ground) reaching [param p_radius] metres.
static func storm(pos: Vector3, p_radius: float) -> PaladinVfx:
	var parent := Vfx.effect_parent()
	if parent == null or not parent.is_inside_tree():
		return null
	var fx := _make(Kind.STORM, STORM_TIME, p_radius)
	parent.add_child(fx)
	fx.global_position = Vector3(pos.x, 0.0, pos.z)
	return fx


## The crown that pops over [param hero]'s head when Blessing of Kings lands on it.
static func crown(hero: Node3D) -> PaladinVfx:
	return _attach(hero, _make(Kind.CROWN, CROWN_TIME, 1.0))


## The golden rune ring under a blessed [param hero] for [param duration] seconds.
static func kings_mark(hero: Node3D, duration: float) -> PaladinVfx:
	return _attach(hero, _make(Kind.KINGS_MARK, duration, MARK_DIAMETER * 0.5))


## Divine Shield's bubble around [param hero] for [param duration] seconds.
static func bubble(hero: Node3D, duration: float) -> PaladinVfx:
	return _attach(hero, _make(Kind.BUBBLE, duration, BUBBLE_RADIUS))


static func _make(p_kind: Kind, p_life: float, p_radius: float) -> PaladinVfx:
	var fx := PaladinVfx.new()
	fx.kind = p_kind
	fx.life = maxf(0.05, p_life)
	fx.radius = maxf(0.1, p_radius)
	fx.name = "Paladin%s" % ["Storm", "Crown", "KingsMark", "Bubble"][p_kind]
	return fx


static func _attach(hero: Node3D, fx: PaladinVfx) -> PaladinVfx:
	if hero == null or not is_instance_valid(hero) or not hero.is_inside_tree():
		fx.free()
		return null
	hero.add_child(fx)
	return fx


## Ends a persistent look early (a short fade). Safe on a freed / finished node.
static func finish(fx: Variant) -> void:
	if fx == null or not is_instance_valid(fx):
		return
	var node := fx as PaladinVfx
	if node == null or node.is_queued_for_deletion():
		return
	node.life = minf(node.life, node.age + FADE_OUT)


func _ready() -> void:
	match kind:
		Kind.STORM:
			_build_storm()
		Kind.CROWN:
			_build_crown()
		Kind.KINGS_MARK:
			_build_mark()
		Kind.BUBBLE:
			_build_bubble()
	_animate(0.0)


func _process(delta: float) -> void:
	age += delta
	if age >= life:
		queue_free()
		return
	_animate(delta)


func _fade() -> float:
	return clampf(minf(age / FADE_IN, (life - age) / FADE_OUT), 0.0, 1.0)


func _animate(delta: float) -> void:
	var fade := _fade()
	var t := clampf(age / life, 0.0, 1.0)
	match kind:
		Kind.STORM:
			_spin.rotation.y = -TAU * STORM_TURNS * (1.0 - pow(1.0 - t, 2.0))
			var grow := lerpf(0.35, 1.08, sqrt(t))
			_ring.scale = Vector3(radius * 2.0 * grow, 1.0, radius * 2.0 * grow)
			Mats.set_ring(_ring, Color(GOLD.r, GOLD.g, GOLD.b, 0.8 * (1.0 - t)), 0.9, 0.98, 0.08 * (1.0 - t))
			_set_alpha(fade)
		Kind.CROWN:
			# Opaque toon crown: pops in, floats up, shrinks away at the end.
			var pop := minf(1.0, age / 0.18)
			var gone := clampf((life - age) / FADE_OUT, 0.0, 1.0)
			_body.position.y = CROWN_HEIGHT + 0.3 * t
			_body.scale = Vector3.ONE * maxf(0.01, lerpf(0.5, 1.4, pop) * gone)
			_body.rotation.y += delta * 2.0
			var grow := lerpf(0.4, 1.6, sqrt(minf(1.0, age / 0.5)))
			_ring.scale = Vector3(grow, 1.0, grow)
			Mats.set_ring(_ring, Color(GOLD.r, GOLD.g, GOLD.b, 0.7 * maxf(0.0, 1.0 - age / 0.5)), 0.78, 0.96)
			_set_alpha(fade)
		Kind.KINGS_MARK:
			_spin.rotation.y += delta * 1.6
			_spin.position.y = MARK_HEIGHT + 0.06 * sin(age * 2.5)
			_set_alpha(fade)
			if _motes != null and life - age < FADE_OUT and _motes.emitting:
				_motes.emitting = false
		Kind.BUBBLE:
			var left := life - age
			var flicker := 1.0
			if left < BUBBLE_WARN:
				flicker = 0.55 + 0.45 * absf(sin(age * 18.0))
			var pulse := 0.9 + 0.1 * sin(age * 6.0)
			var strength := fade * flicker * pulse
			var mat := _body.material_override as ShaderMaterial
			if mat != null:
				mat.set_shader_parameter(&"strength", strength)
			_body.rotation.y += delta * 0.7
			Mats.set_ring(_ring, Color(GOLD.r, GOLD.g, GOLD.b, 0.65 * strength), 0.86, 0.98, 0.1 * strength)


func _set_alpha(fade: float) -> void:
	for i in _materials.size():
		_materials[i].albedo_color.a = _alphas[i] * fade


func _part(mesh: Mesh, tint: Color, alpha: float, additive: bool = true) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(tint.r, tint.g, tint.b, alpha)
	m.vertex_color_use_as_albedo = true
	_materials.append(m)
	_alphas.append(alpha)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _ground_ring(diameter: float, height: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = "Ring"
	m.mesh = MeshKit.cached("paladin:ground_quad", func() -> Mesh:
		var q := PlaneMesh.new()
		q.size = Vector2(1, 1)
		return q)
	m.material_override = Mats.ring()
	Mats.set_ring(m, Color(GOLD.r, GOLD.g, GOLD.b, 0.0), 0.84, 0.94)
	m.scale = Vector3(diameter, 1.0, diameter)
	m.position.y = height
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m


func _build_storm() -> void:
	_spin = Node3D.new()
	_spin.name = "Spin"
	_spin.position.y = 0.55
	add_child(_spin)
	var arc_mesh := MeshKit.cached("paladin:storm_arc", func() -> Mesh:
		return MeshKit.new().add_arc(0.55, 1.0, 100.0, Transform3D.IDENTITY, Color.WHITE, 18).build())
	var edge_mesh := MeshKit.cached("paladin:storm_edge", func() -> Mesh:
		return MeshKit.new().add_arc(0.93, 1.0, 100.0, Transform3D.IDENTITY, Color.WHITE, 18).build())
	for i in STORM_ARCS:
		var yaw := TAU * float(i) / float(STORM_ARCS)
		var arc := _part(arc_mesh, Color(1.0, 0.88, 0.5), 0.5, false)
		arc.rotation.y = yaw
		arc.scale = Vector3(radius, 1.0, radius)
		_spin.add_child(arc)
		var edge := _part(edge_mesh, Color(1.0, 0.85, 0.4), 0.8)
		edge.rotation.y = yaw
		edge.position.y = 0.02
		edge.scale = Vector3(radius, 1.0, radius)
		_spin.add_child(edge)
	_ring = _ground_ring(radius * 2.0, 0.07)
	_motes = _mote_particles(clampi(roundi(radius * 7.0), 10, 30), 0.6)
	_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_motes.emission_ring_axis = Vector3.UP
	_motes.emission_ring_radius = radius * 0.85
	_motes.emission_ring_inner_radius = radius * 0.3
	_motes.emission_ring_height = 0.1
	_motes.explosiveness = 0.85
	_motes.one_shot = true
	_motes.initial_velocity_min = 1.5
	_motes.initial_velocity_max = 3.2
	_motes.position.y = 0.3


func _build_crown() -> void:
	_body = MeshInstance3D.new()
	_body.mesh = MeshKit.cached("paladin:crown", func() -> Mesh:
		var k := MeshKit.new()
		var gold := Color(1.0, 0.82, 0.3)
		k.add_cylinder(0.2, 0.2, 0.1, Transform3D.IDENTITY, gold, 16, false)
		for i in 5:
			var a := TAU * float(i) / 5.0
			var p := Vector3(sin(a) * 0.2, 0.1, cos(a) * 0.2)
			k.add_segment(p - Vector3(0, 0.05, 0), p + Vector3(0, 0.13, 0), 0.05, 0.0, gold, 6)
			k.add_sphere(0.03, MeshKit.xf(p + Vector3(0, 0.15, 0)), Color(1.0, 0.95, 0.75), 6, 3)
		k.add_sphere(0.045, MeshKit.xf(Vector3(0, 0.0, 0.2)), Color(0.85, 0.2, 0.25), 6, 3)
		return k.build())
	_body.material_override = Mats.toon_vc()
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.name = "Crown"
	add_child(_body)
	var glow := _part(_glow_sphere(), GOLD, 0.18)
	glow.scale = Vector3(1.0, 0.7, 1.0)
	glow.position.y = 0.08
	_body.add_child(glow)
	_ring = _ground_ring(1.0, 0.06)


func _build_mark() -> void:
	_spin = Node3D.new()
	_spin.name = "Gems"
	_spin.position.y = MARK_HEIGHT
	add_child(_spin)
	var gem_mesh := MeshKit.cached("paladin:kings_gem", func() -> Mesh:
		var k := MeshKit.new()
		var gold := Color(1.0, 0.84, 0.32)
		k.add_cylinder(0.0, 0.1, 0.13, MeshKit.xf(Vector3(0, 0.065, 0)), gold, 4)
		k.add_cylinder(0.1, 0.0, 0.13, MeshKit.xf(Vector3(0, -0.065, 0)), gold, 4)
		return k.build())
	for i in MARK_GEMS:
		var a := TAU * float(i) / float(MARK_GEMS)
		var gem := _part(gem_mesh, Color.WHITE, 0.95, false)
		gem.name = "Gem%d" % i
		gem.position = Vector3(sin(a) * radius, 0.0, cos(a) * radius)
		_spin.add_child(gem)
		var halo := _part(_glow_sphere(), GOLD, 0.3)
		halo.scale = Vector3.ONE * 0.6
		gem.add_child(halo)
	_motes = _mote_particles(5, 1.3)
	_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_motes.emission_ring_axis = Vector3.UP
	_motes.emission_ring_radius = radius
	_motes.emission_ring_inner_radius = radius * 0.8
	_motes.emission_ring_height = 0.05
	_motes.initial_velocity_min = 0.3
	_motes.initial_velocity_max = 0.7
	_motes.position.y = MARK_HEIGHT - 0.2


func _build_bubble() -> void:
	_body = MeshInstance3D.new()
	_body.name = "Bubble"
	_body.mesh = MeshKit.cached("paladin:bubble", func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = 28
		s.rings = 14
		return s)
	if _bubble_shader == null:
		_bubble_shader = Shader.new()
		_bubble_shader.code = _BUBBLE_CODE
	var mat := ShaderMaterial.new()
	mat.shader = _bubble_shader
	mat.render_priority = 3
	mat.set_shader_parameter(&"tint", GOLD)
	mat.set_shader_parameter(&"strength", 0.0)
	_body.material_override = mat
	_body.scale = Vector3(radius, radius * 1.05, radius)
	_body.position.y = BUBBLE_CENTER
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_body)
	_ring = _ground_ring(radius * 2.2, 0.06)


func _mote_particles(amount: int, lifetime: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Motes"
	p.amount = amount
	p.lifetime = lifetime
	p.mesh = MeshKit.cached("paladin:holy_mote", func() -> Mesh:
		var q := QuadMesh.new()
		q.size = Vector2(0.12, 0.12)
		return q)
	p.material_override = Mats.particle(true, true)
	p.direction = Vector3.UP
	p.spread = 15.0
	p.gravity = Vector3(0.0, 0.5, 0.0)
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.96, 0.75, 0.95))
	ramp.set_color(1, Color(1.0, 0.75, 0.25, 0.0))
	p.color_ramp = ramp
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.emitting = true
	return p


static func _glow_sphere() -> Mesh:
	return MeshKit.cached("paladin:glow_sphere", func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = 0.3
		s.height = 0.6
		s.radial_segments = 12
		s.rings = 6
		return s)
