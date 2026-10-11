class_name BlizzardShards
extends Node3D
## Visual of a Blizzard: ice shards falling onto the area's disc and frost puffs where they
## land. Child of the [AbilityArea] (freed with it); purely cosmetic, gameplay never waits
## for it. Two CPUParticles3D emitters sharing cached meshes and materials.

## Spawn height of the shards (m) and their gravity: they land after about FALL_TIME seconds.
const HEIGHT := 7.0
const GRAVITY := 24.0
const START_SPEED := 2.0
const FALL_TIME := 0.68
const PUFF_TIME := 0.4
## Emission stops this long before the area ends so the last shards still land.
const STOP_BEFORE_END := 0.35
const SHARD_COLOR := Color(0.78, 0.93, 1.0, 1.0)
const FROST_COLOR := Color(0.62, 0.84, 1.0, 1.0)

static var _shard_mesh: Mesh
static var _puff_mesh: Mesh

var duration := 3.0
var radius := 3.0
var _age := 0.0
var _shards: CPUParticles3D
var _puffs: CPUParticles3D


## Adds the effect to [param area] (its radius and duration are read now).
static func attach(area: AbilityArea) -> BlizzardShards:
	var fx := BlizzardShards.new()
	fx.name = "Shards"
	fx.radius = area.radius
	fx.duration = area.duration
	area.add_child(fx)
	return fx


func _ready() -> void:
	_ensure_meshes()
	var area := radius * radius
	_shards = _emitter(_shard_mesh, clampi(roundi(2.5 * area), 12, 90), FALL_TIME,
			Mats.particle(false))
	_shards.position.y = HEIGHT
	_shards.direction = Vector3.DOWN
	_shards.spread = 4.0
	_shards.initial_velocity_min = START_SPEED
	_shards.initial_velocity_max = START_SPEED
	_shards.gravity = Vector3(0.0, -GRAVITY, 0.0)
	_shards.particle_flag_align_y = true
	_shards.angular_velocity_min = -20.0
	_shards.angular_velocity_max = 20.0
	_shards.scale_amount_min = 0.7
	_shards.scale_amount_max = 1.3
	_shards.color_ramp = _gradient(SHARD_COLOR, Color(FROST_COLOR.r, FROST_COLOR.g, FROST_COLOR.b, 0.9))
	_puffs = _emitter(_puff_mesh, clampi(roundi(1.6 * area), 8, 60), PUFF_TIME,
			Mats.particle(false))
	_puffs.position.y = 0.1
	_puffs.direction = Vector3.UP
	_puffs.spread = 25.0
	_puffs.initial_velocity_min = 0.5
	_puffs.initial_velocity_max = 1.4
	_puffs.gravity = Vector3.ZERO
	_puffs.scale_amount_min = 0.6
	_puffs.scale_amount_max = 1.2
	_puffs.color_ramp = _gradient(Color(0.9, 0.97, 1.0, 0.8), Color(FROST_COLOR.r, FROST_COLOR.g, FROST_COLOR.b, 0.0))


func _process(delta: float) -> void:
	_age += delta
	if _age >= duration - STOP_BEFORE_END:
		if _shards != null:
			_shards.emitting = false
		if _puffs != null:
			_puffs.emitting = false


func is_emitting() -> bool:
	return _shards != null and _shards.emitting


func _emitter(mesh: Mesh, amount: int, lifetime: float, material: Material) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.mesh = mesh
	p.material_override = material
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_height = 0.1
	p.emission_ring_radius = maxf(0.3, radius)
	p.emission_ring_inner_radius = 0.0
	p.emitting = true
	add_child(p)
	return p


static func _gradient(from: Color, to: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, from)
	g.set_color(1, to)
	return g


static func _ensure_meshes() -> void:
	if _shard_mesh != null:
		return
	# Four-sided spike, apex up: with align_y the apex leads the fall.
	var spike := CylinderMesh.new()
	spike.top_radius = 0.0
	spike.bottom_radius = 0.07
	spike.height = 0.6
	spike.radial_segments = 4
	spike.rings = 1
	_shard_mesh = spike
	var puff := SphereMesh.new()
	puff.radius = 0.14
	puff.height = 0.28
	puff.radial_segments = 6
	puff.rings = 3
	_puff_mesh = puff
