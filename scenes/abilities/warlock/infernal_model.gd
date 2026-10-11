class_name WarlockInfernalModel
extends Node3D
## Procedural look of the Infernal: a hulking golem of dark, jagged rock – stubby legs, a
## boulder chest split by glowing fel cracks, a small head sunk between huge shoulder rocks,
## long arms ending in rock fists – wreathed in fel-green flames on its head, shoulders and
## back. Faces -Z, about 2.1 m tall.
##
## Rock body = one cached MeshKit mesh (Mats.toon_vc), the cracks + eyes and the flames are
## cached glow meshes. Animation (walk sway, slam, crumble) only moves / scales nodes.

const MODEL_SCALE := 1.0
const TURN_SPEED := 8.0
const SLAM_TIME := 0.45
const CRUMBLE_TIME := 0.45

const ROCK := Color(0.34, 0.31, 0.29)
const ROCK_DARK := Color(0.21, 0.19, 0.18)
const ROCK_LIGHT := Color(0.48, 0.44, 0.4)
const FEL := Color(0.3, 0.95, 0.12)
const FEL_CORE := Color(0.7, 1.0, 0.35)

var _pivot: Node3D
var _flames: MeshInstance3D
var _time := 0.0
var _yaw := 0.0
var _target_yaw := 0.0
var _moving := 0.0
var _slam := 1.0
var _crumble := -1.0


func _init() -> void:
	name = "InfernalModel"


func _ready() -> void:
	if _pivot == null:
		_build()


func set_facing(direction: Vector3) -> void:
	if Vector2(direction.x, direction.z).length_squared() < 0.0001:
		return
	_target_yaw = atan2(-direction.x, -direction.z)


func set_moving(ratio: float) -> void:
	_moving = clampf(ratio, 0.0, 1.0)


## Both fists come down on the ground in front.
func play_slam() -> void:
	_slam = 0.0


## Sinks and shrinks (the summon ends).
func play_crumble() -> void:
	_crumble = 0.0


func _build() -> void:
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	_pivot.scale = Vector3.ONE * MODEL_SCALE
	add_child(_pivot)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = MeshKit.cached("warlock:infernal:body", func() -> Mesh: return _body_mesh())
	body.material_override = Mats.toon_vc()
	_pivot.add_child(body)
	var cracks := MeshInstance3D.new()
	cracks.name = "Cracks"
	cracks.mesh = MeshKit.cached("warlock:infernal:cracks", func() -> Mesh: return _cracks_mesh())
	cracks.material_override = Mats.glow(FEL_CORE, 1.6)
	cracks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pivot.add_child(cracks)
	_flames = MeshInstance3D.new()
	_flames.name = "Flames"
	_flames.mesh = MeshKit.cached("warlock:infernal:flames", func() -> Mesh: return _flames_mesh())
	_flames.material_override = Mats.glow(FEL, 0.9)
	_flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pivot.add_child(_flames)
	_pivot.rotation.y = _target_yaw
	_yaw = _target_yaw


func _process(delta: float) -> void:
	if _pivot == null:
		return
	_time += delta
	_yaw = lerp_angle(_yaw, _target_yaw, 1.0 - exp(-TURN_SPEED * delta))
	_slam = minf(1.0, _slam + delta / SLAM_TIME)
	# Wind up (lean back) for the first third, then crash forward.
	var lean := 0.0
	if _slam < 1.0:
		lean = -0.25 * sin(_slam * 3.0 * PI) if _slam < 0.33 else 0.45 * sin((_slam - 0.33) / 0.67 * PI)
	var sway := sin(_time * 6.0) * 0.08 * _moving
	_pivot.rotation = Vector3(-lean - 0.1 * _moving, _yaw, sway)
	_pivot.position.y = absf(sin(_time * 6.0)) * 0.06 * _moving
	var s := MODEL_SCALE
	if _crumble >= 0.0:
		_crumble = minf(1.0, _crumble + delta / CRUMBLE_TIME)
		s *= 1.0 - 0.7 * _crumble
		_pivot.position.y -= 0.8 * _crumble
	_pivot.scale = Vector3.ONE * s
	var flicker := 1.0 + 0.1 * sin(_time * 19.0) + 0.06 * sin(_time * 31.0)
	_flames.scale = Vector3(1.0, flicker, 1.0)


# --- Meshes (shared, cached) ------------------------------------------------------------------

static func _xf(pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Transform3D:
	return MeshKit.xf(pos, rot, scl)


static func _body_mesh() -> Mesh:
	var k := MeshKit.new()
	# Stubby legs and blocky feet.
	for side: float in [-1.0, 1.0]:
		k.add_box(Vector3(0.32, 0.55, 0.34), _xf(Vector3(0.28 * side, 0.36, 0.02), Vector3(4, 0, 6 * side)), ROCK_DARK)
		k.add_box(Vector3(0.38, 0.16, 0.46), _xf(Vector3(0.3 * side, 0.08, -0.04), Vector3(0, 8 * side, 0)), ROCK)
	# Hips and the boulder chest, with extra slabs for a jagged outline.
	k.add_box(Vector3(0.75, 0.3, 0.5), _xf(Vector3(0, 0.7, 0.0), Vector3(0, 0, 3)), ROCK_DARK)
	k.add_sphere(0.56, _xf(Vector3(0, 1.18, 0.02), Vector3(0, 12, 0), Vector3(1.25, 1.0, 0.92)), ROCK, 9, 5)
	k.add_box(Vector3(0.5, 0.36, 0.2), _xf(Vector3(-0.16, 1.28, -0.42), Vector3(12, -10, 8)), ROCK_LIGHT)
	k.add_box(Vector3(0.42, 0.3, 0.2), _xf(Vector3(0.2, 1.0, -0.4), Vector3(-6, 14, -10)), ROCK)
	k.add_box(Vector3(0.6, 0.45, 0.3), _xf(Vector3(0.0, 1.3, 0.42), Vector3(-15, 0, 4)), ROCK_DARK)
	# Huge shoulder rocks.
	for side: float in [-1.0, 1.0]:
		k.add_box(Vector3(0.48, 0.42, 0.5), _xf(Vector3(0.66 * side, 1.5, 0.02), Vector3(10, 25 * side, 18 * side)), ROCK_LIGHT)
		k.add_box(Vector3(0.3, 0.26, 0.3), _xf(Vector3(0.78 * side, 1.72, 0.08), Vector3(-12, 40 * side, 30 * side)), ROCK)
	# Small head sunk between them, with a heavy jaw.
	var head := Vector3(0, 1.68, -0.16)
	k.add_box(Vector3(0.36, 0.3, 0.34), _xf(head, Vector3(-6, 0, 0)), ROCK_DARK)
	k.add_box(Vector3(0.3, 0.12, 0.16), _xf(head + Vector3(0, -0.16, -0.14), Vector3(10, 0, 0)), ROCK)
	# Long arms and big fists.
	for side: float in [-1.0, 1.0]:
		var shoulder := Vector3(0.72 * side, 1.42, 0.0)
		var elbow := Vector3(0.88 * side, 1.0, -0.08)
		var wrist := Vector3(0.86 * side, 0.6, -0.22)
		k.add_segment(shoulder, elbow, 0.2, 0.17, ROCK, 7)
		k.add_segment(elbow, wrist, 0.18, 0.2, ROCK_DARK, 7)
		k.add_box(Vector3(0.38, 0.36, 0.4), _xf(wrist + Vector3(0.0, -0.18, -0.04), Vector3(8, 10 * side, 6 * side)), ROCK_LIGHT)
	return k.build()


## Fel cracks across the chest and the glowing eyes.
static func _cracks_mesh() -> Mesh:
	var k := MeshKit.new()
	var head := Vector3(0, 1.68, -0.16)
	for side: float in [-1.0, 1.0]:
		k.add_box(Vector3(0.08, 0.04, 0.03), _xf(head + Vector3(0.08 * side, 0.03, -0.17), Vector3(0, 0, -14 * side)), Color.WHITE)
	k.add_segment(Vector3(-0.05, 1.5, -0.52), Vector3(0.02, 1.25, -0.56), 0.025, 0.02, Color.WHITE, 5)
	k.add_segment(Vector3(0.02, 1.25, -0.56), Vector3(-0.08, 1.02, -0.52), 0.02, 0.015, Color.WHITE, 5)
	k.add_segment(Vector3(0.02, 1.25, -0.56), Vector3(0.2, 1.15, -0.5), 0.018, 0.012, Color.WHITE, 5)
	k.add_segment(Vector3(-0.3, 1.32, -0.45), Vector3(-0.12, 1.2, -0.53), 0.015, 0.012, Color.WHITE, 5)
	return k.build()


## Fel flames: a crown of tongues on the head, on the shoulders and up the back.
static func _flames_mesh() -> Mesh:
	var k := MeshKit.new()
	var tongues: Array[Vector4] = [
		# (x, y, z, height)
		Vector4(0.0, 1.86, -0.12, 0.42), Vector4(-0.12, 1.84, -0.06, 0.3), Vector4(0.12, 1.84, -0.06, 0.32),
		Vector4(0.0, 1.8, 0.08, 0.36),
		Vector4(-0.68, 1.74, 0.04, 0.34), Vector4(-0.78, 1.86, 0.12, 0.24), Vector4(0.68, 1.74, 0.04, 0.34),
		Vector4(0.78, 1.86, 0.12, 0.24),
		Vector4(-0.18, 1.56, 0.5, 0.38), Vector4(0.18, 1.6, 0.48, 0.42), Vector4(0.0, 1.4, 0.56, 0.3),
	]
	for t in tongues:
		var base := Vector3(t.x, t.y, t.z)
		k.add_cylinder(0.0, 0.1 + t.w * 0.22, t.w, _xf(base + Vector3(0, t.w * 0.5, 0), Vector3(-10, 0, 0)), Color.WHITE, 7)
	return k.build()
