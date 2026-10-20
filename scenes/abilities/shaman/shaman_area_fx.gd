class_name ShamanAreaFx
extends Node3D
## Visual of a Shaman ground area (M8): rubble that jumps out of a quake or raindrops that fall into a
## healing rain. Child of the [AbilityArea] (freed with it); purely cosmetic, gameplay never waits for it.
## One or two CPUParticles3D emitters sharing cached meshes and materials.

enum Kind { RUBBLE, RAIN }

## Rain starts this high (m) and falls with this gravity.
const RAIN_HEIGHT := 5.0
const RAIN_GRAVITY := 22.0
## Emission stops this long before the area ends so the last pieces still land.
const STOP_BEFORE_END := 0.3
const RUBBLE_COLOR := Color(0.62, 0.48, 0.3, 1.0)
const DUST_COLOR := Color(0.75, 0.66, 0.5, 0.0)
const RAIN_COLOR := Color(0.5, 0.82, 1.0, 0.95)
const SPLASH_COLOR := Color(0.7, 0.92, 1.0, 0.0)

static var _rubble_mesh: Mesh
static var _drop_mesh: Mesh

var kind := Kind.RUBBLE
var duration := 4.0
var radius := 3.0
var _age := 0.0
var _emitters: Array[CPUParticles3D] = []


## Adds the effect to [param area] (its radius and duration are read now).
static func attach(area: AbilityArea, p_kind: Kind) -> ShamanAreaFx:
	var fx := ShamanAreaFx.new()
	fx.name = "AreaFx"
	fx.kind = p_kind
	fx.radius = area.radius
	fx.duration = area.duration
	area.add_child(fx)
	return fx


func _ready() -> void:
	_ensure_meshes()
	var size := radius * radius
	if kind == Kind.RAIN:
		var rain := _emitter(_drop_mesh, clampi(roundi(3.0 * size), 14, 80), 0.55)
		rain.position.y = RAIN_HEIGHT
		rain.direction = Vector3.DOWN
		rain.spread = 3.0
		rain.initial_velocity_min = 3.0
		rain.initial_velocity_max = 3.0
		rain.gravity = Vector3(0.0, -RAIN_GRAVITY, 0.0)
		rain.particle_flag_align_y = true
		rain.color_ramp = _gradient(RAIN_COLOR, Color(RAIN_COLOR.r, RAIN_COLOR.g, RAIN_COLOR.b, 0.7))
	else:
		var rubble := _emitter(_rubble_mesh, clampi(roundi(1.6 * size), 8, 48), 0.7)
		rubble.position.y = 0.05
		rubble.direction = Vector3.UP
		rubble.spread = 25.0
		rubble.initial_velocity_min = 2.0
		rubble.initial_velocity_max = 4.0
		rubble.gravity = Vector3(0.0, -14.0, 0.0)
		rubble.angular_velocity_min = -240.0
		rubble.angular_velocity_max = 240.0
		rubble.scale_amount_min = 0.6
		rubble.scale_amount_max = 1.3
		rubble.color_ramp = _gradient(RUBBLE_COLOR, Color(RUBBLE_COLOR.r, RUBBLE_COLOR.g, RUBBLE_COLOR.b, 0.85))


func _process(delta: float) -> void:
	_age += delta
	if _age >= duration - STOP_BEFORE_END:
		for e in _emitters:
			e.emitting = false


func is_emitting() -> bool:
	return not _emitters.is_empty() and _emitters[0].emitting


func _emitter(mesh: Mesh, amount: int, lifetime: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.mesh = mesh
	p.material_override = Mats.particle(false)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_height = 0.1
	p.emission_ring_radius = maxf(0.3, radius)
	p.emission_ring_inner_radius = 0.0
	p.emitting = true
	add_child(p)
	_emitters.append(p)
	return p


static func _gradient(from: Color, to: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, from)
	g.set_color(1, to)
	return g


static func _ensure_meshes() -> void:
	if _rubble_mesh != null:
		return
	var rock := BoxMesh.new()
	rock.size = Vector3(0.16, 0.12, 0.14)
	_rubble_mesh = rock
	var drop := CylinderMesh.new()
	drop.top_radius = 0.0
	drop.bottom_radius = 0.035
	drop.height = 0.4
	drop.radial_segments = 4
	drop.rings = 1
	_drop_mesh = drop
