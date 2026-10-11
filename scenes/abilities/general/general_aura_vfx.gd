class_name GeneralAuraVfx
extends Node3D
## The look of a [GeneralBuff] on a hero (purely visual, procedural):
##   BANDAGE – two cream bandage bands wound round the onion (slowly turning) and little green
##             crosses rising from it;
##   SPRINT  – kicked-up dust trailing behind the feet and a pale wind ring on the ground;
##   BERSERK – a pulsing blood-red ring at the feet and rising embers.
## A child of the buff (so of the hero); [method release] lets it fade out on its own when the
## buff ends. Materials are its own (alpha fades); meshes are cached.

enum Style { BANDAGE, SPRINT, BERSERK }

const FADE_IN := 0.15
const FADE_OUT := 0.3
const BANDAGE_COLOR := Color(0.97, 0.94, 0.84)
const BANDAGE_STRIPE := Color(0.82, 0.22, 0.2)
const HEAL_COLOR := Color(0.45, 1.0, 0.45)
const DUST_COLOR := Color(0.86, 0.76, 0.56)
const WIND_COLOR := Color(1.0, 0.95, 0.75)
const RAGE_COLOR := Color(1.0, 0.18, 0.1)
const EMBER_COLOR := Color(1.0, 0.5, 0.15)

var style := Style.BANDAGE
var color := Color.WHITE

var _age := 0.0
var _fade_left := -1.0
var _materials: Array[BaseMaterial3D] = []
var _alphas: Array[float] = []
var _rings: Array[MeshInstance3D] = []
var _ring_colors: Array[Color] = []
var _spinners: Array[Node3D] = []
var _particles: Array[CPUParticles3D] = []


static func create(p_style: Style, p_color: Color = Color.WHITE) -> GeneralAuraVfx:
	var fx := GeneralAuraVfx.new()
	fx.name = "Look"
	fx.style = p_style
	fx.color = p_color
	return fx


func _ready() -> void:
	match style:
		Style.BANDAGE:
			_build_bandage()
		Style.SPRINT:
			_build_sprint()
		Style.BERSERK:
			_build_berserk()
	_apply_alpha(0.0)


## The buff was refreshed: back to full strength.
func refresh() -> void:
	_fade_left = -1.0
	for p in _particles:
		p.emitting = true


## The buff ended: keep following the hero, fade out and free.
func release() -> void:
	if _fade_left >= 0.0:
		return
	_fade_left = FADE_OUT
	for p in _particles:
		p.emitting = false
	var hero := get_parent().get_parent() if get_parent() != null else null
	if hero is Node3D and hero.is_inside_tree() and not hero.is_queued_for_deletion():
		var keep := global_transform
		get_parent().remove_child(self)
		hero.add_child(self)
		global_transform = keep
	else:
		queue_free()


func _process(delta: float) -> void:
	_age += delta
	var strength := clampf(_age / FADE_IN, 0.0, 1.0)
	if _fade_left >= 0.0:
		_fade_left -= delta
		if _fade_left <= 0.0:
			queue_free()
			return
		strength *= _fade_left / FADE_OUT
	for i in _spinners.size():
		var dir := 1.0 if i % 2 == 0 else -1.0
		_spinners[i].rotation.y += delta * dir * (1.4 + 0.5 * i)
	var pulse := 1.0
	if style == Style.BERSERK:
		pulse = 0.75 + 0.25 * sin(_age * 9.0)
	elif style == Style.BANDAGE:
		for i in _spinners.size():
			_spinners[i].position.y = _spinners[i].get_meta(&"base_y", 0.5) + 0.03 * sin(_age * 3.0 + i)
	_apply_alpha(strength * pulse)


func _apply_alpha(strength: float) -> void:
	for i in _materials.size():
		_materials[i].albedo_color.a = _alphas[i] * strength
	for i in _rings.size():
		var c := _ring_colors[i]
		Mats.set_ring(_rings[i], Color(c.r, c.g, c.b, c.a * strength), 0.72, 0.95, 0.22 * strength)


# --- Builders ----------------------------------------------------------------------------------

func _build_bandage() -> void:
	# Two bands round the bulb (its widest part is ~0.4 m at 0.35-0.6 m height), tilted a bit.
	for i in 2:
		var spin := Node3D.new()
		spin.name = "Band%d" % i
		var y := 0.36 + 0.24 * i
		spin.position.y = y
		spin.set_meta(&"base_y", y)
		add_child(spin)
		var band := _mesh_part(_band_mesh(), BANDAGE_COLOR, 0.95)
		band.rotation_degrees = Vector3(9.0 if i == 0 else -7.0, 0.0, 6.0 if i == 0 else -5.0)
		band.scale = Vector3.ONE * (1.0 if i == 0 else 0.93)
		spin.add_child(band)
		_spinners.append(spin)
	var crosses := _emitter(8, 0.9, _cross_mesh(), Mats.particle(false, true))
	crosses.position.y = 0.6
	crosses.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	crosses.emission_ring_axis = Vector3.UP
	crosses.emission_ring_radius = 0.5
	crosses.emission_ring_inner_radius = 0.35
	crosses.emission_ring_height = 0.4
	crosses.direction = Vector3.UP
	crosses.spread = 10.0
	crosses.gravity = Vector3.ZERO
	crosses.initial_velocity_min = 0.6
	crosses.initial_velocity_max = 1.0
	crosses.scale_amount_min = 0.8
	crosses.scale_amount_max = 1.2
	crosses.color_ramp = _ramp(Color(HEAL_COLOR.r, HEAL_COLOR.g, HEAL_COLOR.b, 0.95),
			Color(HEAL_COLOR.r, HEAL_COLOR.g, HEAL_COLOR.b, 0.0))


func _build_sprint() -> void:
	_ground_ring(0.75, Color(WIND_COLOR.r, WIND_COLOR.g, WIND_COLOR.b, 0.45))
	var dust := _emitter(14, 0.55, _ball_mesh(), Mats.particle(false))
	dust.local_coords = false
	dust.position.y = 0.08
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = 0.25
	dust.direction = Vector3.UP
	dust.spread = 60.0
	dust.gravity = Vector3(0, 0.6, 0)
	dust.initial_velocity_min = 0.3
	dust.initial_velocity_max = 0.9
	dust.damping_min = 1.0
	dust.damping_max = 2.0
	dust.scale_amount_min = 1.2
	dust.scale_amount_max = 2.2
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 1.4))
	dust.scale_amount_curve = grow
	dust.color_ramp = _ramp(Color(DUST_COLOR.r, DUST_COLOR.g, DUST_COLOR.b, 0.7),
			Color(DUST_COLOR.r, DUST_COLOR.g, DUST_COLOR.b, 0.0))


func _build_berserk() -> void:
	_ground_ring(0.85, Color(RAGE_COLOR.r, RAGE_COLOR.g, RAGE_COLOR.b, 0.8))
	var embers := _emitter(16, 0.8, _ball_mesh(), Mats.particle(true))
	embers.position.y = 0.15
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	embers.emission_ring_axis = Vector3.UP
	embers.emission_ring_radius = 0.55
	embers.emission_ring_inner_radius = 0.3
	embers.emission_ring_height = 0.1
	embers.direction = Vector3.UP
	embers.spread = 15.0
	embers.gravity = Vector3(0, 1.5, 0)
	embers.initial_velocity_min = 1.2
	embers.initial_velocity_max = 2.2
	embers.scale_amount_min = 0.5
	embers.scale_amount_max = 0.9
	embers.color_ramp = _ramp(Color(EMBER_COLOR.r, EMBER_COLOR.g, EMBER_COLOR.b, 1.0),
			Color(RAGE_COLOR.r, RAGE_COLOR.g, RAGE_COLOR.b, 0.0))


# --- Parts -------------------------------------------------------------------------------------

func _mesh_part(mesh: Mesh, tint: Color, alpha: float) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(tint.r, tint.g, tint.b, alpha)
	_materials.append(m)
	_alphas.append(alpha)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _ground_ring(radius: float, ring_color: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Ring"
	mi.mesh = MeshKit.cached("general:aura_quad", func() -> Mesh:
		var q := PlaneMesh.new()
		q.size = Vector2(2.0, 2.0)
		return q)
	mi.material_override = Mats.ring()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(radius, 1.0, radius)
	mi.position.y = 0.05
	add_child(mi)
	_rings.append(mi)
	_ring_colors.append(ring_color)


func _emitter(amount: int, lifetime: float, mesh: Mesh, material: Material) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.mesh = mesh
	p.material_override = material
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = true
	add_child(p)
	_particles.append(p)
	return p


static func _ramp(from: Color, to: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, from)
	g.set_color(1, to)
	return g


## A flat ring of bandage cloth (radius ~0.43 m) with two red stripes.
static func _band_mesh() -> Mesh:
	return MeshKit.cached("general:bandage_band", func() -> Mesh:
		var k := MeshKit.new()
		k.add_cylinder(0.43, 0.44, 0.075, Transform3D.IDENTITY, Color.WHITE, 28)
		k.add_cylinder(0.445, 0.445, 0.012, MeshKit.xf(Vector3(0, 0.022, 0)), BANDAGE_STRIPE, 28)
		k.add_cylinder(0.445, 0.445, 0.012, MeshKit.xf(Vector3(0, -0.022, 0)), BANDAGE_STRIPE, 28)
		# A loose end hanging from the knot.
		k.add_box(Vector3(0.06, 0.16, 0.012), MeshKit.xf(Vector3(0.0, -0.08, -0.44), Vector3(0, 0, 12)), Color.WHITE)
		return k.build())


## A little "+" for the heal sparkles.
static func _cross_mesh() -> Mesh:
	return MeshKit.cached("general:heal_cross", func() -> Mesh:
		var k := MeshKit.new()
		k.add_box(Vector3(0.11, 0.035, 0.03), Transform3D.IDENTITY, Color.WHITE)
		k.add_box(Vector3(0.035, 0.11, 0.03), Transform3D.IDENTITY, Color.WHITE)
		return k.build())


static func _ball_mesh() -> Mesh:
	return MeshKit.cached("general:ball", func() -> Mesh:
		var m := SphereMesh.new()
		m.radius = 0.06
		m.height = 0.12
		m.radial_segments = 8
		m.rings = 4
		return m)
