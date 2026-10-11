class_name WarlockVoidwalkerModel
extends Node3D
## Procedural look of the Voidwalker: a hulking, legless void spirit – broad indigo chest and
## shoulders, a small sunken head with glowing pale eyes, huge fists with golden shackles and
## a golden belt, its body thinning into a smoky tail. It hovers over a dark violet shadow
## pool. Faces -Z.
##
## Body = one cached MeshKit mesh (Mats.toon_vc, shared by every Voidwalker), eyes = a cached
## glow mesh, the pool = a ring material owned by the node. Animation (hover bob, sway,
## punch, Torment roar) only moves / scales nodes.

const HOVER_HEIGHT := 0.2
const MODEL_SCALE := 1.05
const TURN_SPEED := 7.0
const PUNCH_TIME := 0.35
const ROAR_TIME := 0.6

const VOID := Color(0.27, 0.3, 0.74)
const VOID_DARK := Color(0.14, 0.13, 0.42)
const VOID_LIGHT := Color(0.42, 0.48, 0.92)
const SMOKE := Color(0.2, 0.16, 0.5)
const GOLD := Color(0.92, 0.74, 0.3)
const GOLD_DARK := Color(0.62, 0.45, 0.16)
const EYE := Color(0.75, 0.95, 1.0)
const POOL := Color(0.3, 0.15, 0.55, 0.55)

var _pivot: Node3D
var _body: MeshInstance3D
var _eyes: MeshInstance3D
var _pool: MeshInstance3D
var _time := 0.0
var _yaw := 0.0
var _target_yaw := 0.0
var _moving := 0.0
var _punch := 1.0
var _roar := 1.0


func _init() -> void:
	name = "VoidwalkerModel"


func _ready() -> void:
	if _pivot == null:
		_build()


func set_facing(direction: Vector3) -> void:
	if Vector2(direction.x, direction.z).length_squared() < 0.0001:
		return
	_target_yaw = atan2(-direction.x, -direction.z)


func set_moving(ratio: float) -> void:
	_moving = clampf(ratio, 0.0, 1.0)


## Fist slam on the enemy in front.
func play_attack() -> void:
	_punch = 0.0


## Torment: rears up and flares its eyes.
func play_roar() -> void:
	_roar = 0.0


func _build() -> void:
	_pool = MeshInstance3D.new()
	_pool.name = "Pool"
	_pool.mesh = MeshKit.cached("warlock:ground_quad", func() -> Mesh:
		var q := PlaneMesh.new()
		q.size = Vector2(1, 1)
		return q)
	_pool.scale = Vector3(1.7, 1.0, 1.7)
	_pool.position.y = 0.05
	_pool.material_override = Mats.ring()
	_pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Mats.set_ring(_pool, POOL, 0.55, 1.0, 0.6)
	add_child(_pool)
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	_pivot.position.y = HOVER_HEIGHT
	_pivot.scale = Vector3.ONE * MODEL_SCALE
	add_child(_pivot)
	_body = MeshInstance3D.new()
	_body.name = "Body"
	_body.mesh = MeshKit.cached("warlock:voidwalker:body", func() -> Mesh: return _body_mesh())
	_body.material_override = Mats.toon_vc()
	_pivot.add_child(_body)
	_eyes = MeshInstance3D.new()
	_eyes.name = "Eyes"
	_eyes.mesh = MeshKit.cached("warlock:voidwalker:eyes", func() -> Mesh: return _eyes_mesh())
	_eyes.material_override = Mats.glow(EYE, 3.0)
	_eyes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pivot.add_child(_eyes)
	_pivot.rotation.y = _target_yaw
	_yaw = _target_yaw


func _process(delta: float) -> void:
	if _pivot == null:
		return
	_time += delta
	_yaw = lerp_angle(_yaw, _target_yaw, 1.0 - exp(-TURN_SPEED * delta))
	_punch = minf(1.0, _punch + delta / PUNCH_TIME)
	_roar = minf(1.0, _roar + delta / ROAR_TIME)
	var punch := sin(_punch * PI) if _punch < 1.0 else 0.0
	var roar := sin(_roar * PI) if _roar < 1.0 else 0.0
	_pivot.rotation = Vector3(-0.18 * _moving - 0.45 * punch + 0.3 * roar, _yaw, 0.06 * sin(_time * 1.7))
	_pivot.position.y = HOVER_HEIGHT + 0.07 * sin(_time * 2.2) + 0.15 * roar
	_pivot.scale = Vector3.ONE * MODEL_SCALE * (1.0 + 0.1 * roar)
	_eyes.scale = Vector3.ONE * (1.0 + 0.6 * roar)
	var pulse := 0.5 + 0.1 * sin(_time * 3.0) + 0.3 * roar
	Mats.set_ring(_pool, Color(POOL, POOL.a * (0.8 + 0.4 * roar)), 0.55 - 0.2 * roar, 1.0, pulse)


# --- Meshes (shared, cached) ------------------------------------------------------------------

static func _xf(pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Transform3D:
	return MeshKit.xf(pos, rot, scl)


static func _body_mesh() -> Mesh:
	var k := MeshKit.new()
	# Smoky tail: stacked cones, darker towards the tip, curling back.
	k.add_tube(PackedVector3Array([Vector3(0, 0.62, 0.02), Vector3(0, 0.4, 0.08), Vector3(0, 0.2, 0.18),
			Vector3(0.0, 0.06, 0.32)]), 0.3, 0.05, SMOKE, 12)
	k.add_sphere(0.2, _xf(Vector3(0, 0.36, 0.1), Vector3.ZERO, Vector3(1.1, 0.9, 1.0)), VOID_DARK, 10, 5)
	# Barrel chest and belly.
	k.add_sphere(0.42, _xf(Vector3(0, 0.95, 0.0), Vector3.ZERO, Vector3(1.18, 0.95, 0.9)), VOID, 18, 9)
	k.add_sphere(0.3, _xf(Vector3(0, 0.7, -0.05), Vector3.ZERO, Vector3(1.05, 0.9, 0.9)), VOID_LIGHT, 14, 7)
	# Golden belt with a buckle.
	k.add_cylinder(0.33, 0.31, 0.08, _xf(Vector3(0, 0.62, 0.0), Vector3.ZERO, Vector3(1.05, 1.0, 0.95)), GOLD, 16)
	k.add_box(Vector3(0.14, 0.12, 0.04), _xf(Vector3(0, 0.62, -0.31)), GOLD_DARK)
	# Hunched shoulders and the small sunken head with a heavy brow and pointed chin.
	for side: float in [-1.0, 1.0]:
		k.add_sphere(0.22, _xf(Vector3(0.43 * side, 1.12, 0.02)), VOID, 12, 6)
	var head := Vector3(0, 1.3, -0.12)
	k.add_sphere(0.19, _xf(head, Vector3.ZERO, Vector3(1.0, 0.95, 1.0)), VOID_DARK, 14, 7)
	k.add_box(Vector3(0.3, 0.06, 0.1), _xf(head + Vector3(0, 0.07, -0.13), Vector3(-10, 0, 0)), VOID_DARK.darkened(0.3))
	k.add_cylinder(0.0, 0.1, 0.16, _xf(head + Vector3(0, -0.19, -0.06), Vector3(180, 0, 0)), VOID_DARK, 8)
	# Huge arms with fists and golden shackles.
	for side: float in [-1.0, 1.0]:
		var shoulder := Vector3(0.48 * side, 1.08, 0.0)
		var elbow := Vector3(0.62 * side, 0.78, -0.06)
		var wrist := Vector3(0.6 * side, 0.5, -0.2)
		k.add_segment(shoulder, elbow, 0.13, 0.11, VOID, 10)
		k.add_sphere(0.11, _xf(elbow), VOID, 8, 4)
		k.add_segment(elbow, wrist, 0.11, 0.12, VOID, 10)
		k.add_segment(elbow.lerp(wrist, 0.45), elbow.lerp(wrist, 0.85), 0.15, 0.15, GOLD, 12)
		k.add_segment(elbow.lerp(wrist, 0.5), elbow.lerp(wrist, 0.58), 0.165, 0.165, GOLD_DARK, 12)
		k.add_sphere(0.16, _xf(wrist + Vector3(0.0, -0.08, -0.04), Vector3.ZERO, Vector3(1.0, 0.9, 1.1)), VOID_LIGHT, 10, 5)
		# Broken chain link dangling from the shackle.
		k.add_torus(0.02, 0.05, _xf(wrist + Vector3(0.0, -0.02, 0.12), Vector3(90, 0, 0)), GOLD_DARK, 8, 4)
	return k.build()


static func _eyes_mesh() -> Mesh:
	var k := MeshKit.new()
	var head := Vector3(0, 1.3, -0.12)
	for side: float in [-1.0, 1.0]:
		k.add_sphere(0.04, _xf(head + Vector3(0.075 * side, 0.02, -0.16), Vector3(0, 0, 15.0 * side), Vector3(1.4, 0.7, 0.6)),
				Color.WHITE, 8, 4)
	return k.build()
