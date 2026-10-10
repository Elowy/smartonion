class_name WarlockImpModel
extends Node3D
## Procedural look of the Warlock's Imp: a cute little red imp (big head, cream horns, pointy
## ears, yellow eyes, toothy grin, bat wings, arrow-tipped tail) hovering at
## [constant HOVER_HEIGHT] with a fireball floating over its raised hand. Faces -Z.
##
## Body and the two wings are MeshKit meshes (cached, shared by every Imp) drawn with
## Mats.toon_vc(); the fireball uses a cached Mats.glow material. Animation (hover bob, wing
## flaps, fireball flicker, throw) only moves / scales nodes – no per-node materials.

const HOVER_HEIGHT := 0.6
const MODEL_SCALE := 0.85
const TURN_SPEED := 10.0
const FLAP_SPEED := 17.0
const CAST_TIME := 0.3

const SKIN := Color(0.86, 0.2, 0.14)
const SKIN_DARK := Color(0.6, 0.1, 0.1)
const BELLY := Color(0.98, 0.58, 0.36)
const HORN := Color(0.96, 0.88, 0.68)
const WING := Color(0.48, 0.08, 0.12)
const EYE := Color(1.0, 0.86, 0.2)
const DARK := Color(0.08, 0.04, 0.05)
const WHITE := Color(0.98, 0.97, 0.93)
const FLAME := Color(1.0, 0.55, 0.15)
const FLAME_CORE := Color(1.0, 0.9, 0.55)

## Where the wings attach (pivot space) and the fireball floats.
const WING_ROOT := Vector3(0.07, 0.1, 0.11)
const FLAME_POS := Vector3(0.25, 0.27, -0.12)

var _pivot: Node3D
var _body: MeshInstance3D
var _wings: Array[MeshInstance3D] = []
var _flame: Node3D
var _time := 0.0
var _yaw := 0.0
var _target_yaw := 0.0
var _moving := 0.0
var _cast := 1.0


func _init() -> void:
	name = "ImpModel"


func _ready() -> void:
	if _pivot == null:
		_build()


## Turns (smoothly) to look along [param direction] (XZ).
func set_facing(direction: Vector3) -> void:
	if Vector2(direction.x, direction.z).length_squared() < 0.0001:
		return
	_target_yaw = atan2(-direction.x, -direction.z)


## 0..1: leans forward and flaps faster while it flies after its master.
func set_moving(ratio: float) -> void:
	_moving = clampf(ratio, 0.0, 1.0)


## Throw animation (the fireball leaves the hand and regrows).
func play_cast() -> void:
	_cast = 0.0


func _build() -> void:
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	_pivot.position.y = HOVER_HEIGHT
	_pivot.scale = Vector3.ONE * MODEL_SCALE
	add_child(_pivot)
	_body = MeshInstance3D.new()
	_body.name = "Body"
	_body.mesh = MeshKit.cached("warlock:imp:body", func() -> Mesh: return _body_mesh())
	_body.material_override = Mats.toon_vc()
	_pivot.add_child(_body)
	for side: float in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		wing.name = "WingL" if side < 0.0 else "WingR"
		var key := "warlock:imp:wing:%d" % int(side)
		wing.mesh = MeshKit.cached(key, func() -> Mesh: return _wing_mesh(side))
		wing.material_override = Mats.toon_vc()
		wing.position = Vector3(WING_ROOT.x * side, WING_ROOT.y, WING_ROOT.z)
		_pivot.add_child(wing)
		_wings.append(wing)
	_flame = Node3D.new()
	_flame.name = "Flame"
	_flame.position = FLAME_POS
	_pivot.add_child(_flame)
	var outer := MeshInstance3D.new()
	outer.mesh = _sphere_mesh(0.085)
	outer.material_override = Mats.glow(FLAME, 2.6)
	outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame.add_child(outer)
	var core := MeshInstance3D.new()
	core.mesh = _sphere_mesh(0.05)
	core.material_override = Mats.glow(FLAME_CORE, 3.2)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.position = Vector3(0, 0.0, -0.03)
	_flame.add_child(core)
	var tip := MeshInstance3D.new()
	tip.mesh = MeshKit.cached("warlock:imp:flame_tip", func() -> Mesh: return _flame_tip_mesh())
	tip.material_override = Mats.glow(FLAME, 2.2)
	tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame.add_child(tip)
	_pivot.rotation.y = _target_yaw
	_yaw = _target_yaw


func _process(delta: float) -> void:
	if _pivot == null:
		return
	_time += delta
	_yaw = lerp_angle(_yaw, _target_yaw, 1.0 - exp(-TURN_SPEED * delta))
	_cast = minf(1.0, _cast + delta / CAST_TIME)
	var throw := sin(_cast * PI) if _cast < 1.0 else 0.0
	_pivot.rotation = Vector3(-0.25 * _moving - 0.2 * throw, _yaw, 0.0)
	_pivot.position.y = HOVER_HEIGHT + sin(_time * 3.1) * 0.06
	var flap := sin(_time * FLAP_SPEED * (1.0 + 0.4 * _moving))
	for i in _wings.size():
		var side := -1.0 if i == 0 else 1.0
		_wings[i].rotation = Vector3(0.0, side * 0.35, side * (0.15 + 0.55 * flap))
	if _flame != null:
		var regrow := _cast if _cast < 1.0 else 1.0
		var flicker := 1.0 + 0.12 * sin(_time * 23.0) + 0.06 * sin(_time * 37.0)
		_flame.scale = Vector3.ONE * maxf(0.05, regrow * flicker)
		_flame.position = FLAME_POS + Vector3(0.0, 0.03 * sin(_time * 5.0), 0.0)


# --- Meshes (shared, cached) ------------------------------------------------------------------

static func _xf(pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Transform3D:
	return MeshKit.xf(pos, rot, scl)


static func _body_mesh() -> Mesh:
	var k := MeshKit.new()
	# Pot-bellied torso.
	k.add_sphere(0.15, _xf(Vector3(0, 0.0, 0.0), Vector3.ZERO, Vector3(1.0, 1.1, 0.95)), SKIN, 14, 7)
	k.add_sphere(0.11, _xf(Vector3(0, -0.02, -0.07), Vector3.ZERO, Vector3(1.0, 1.05, 0.62)), BELLY, 12, 6)
	# Big round head.
	var head := Vector3(0, 0.27, -0.02)
	k.add_sphere(0.17, _xf(head, Vector3.ZERO, Vector3(1.05, 0.98, 1.0)), SKIN, 16, 8)
	k.add_sphere(0.1, _xf(head + Vector3(0, -0.05, -0.11), Vector3.ZERO, Vector3(1.35, 0.8, 0.85)), SKIN.lightened(0.06), 12, 6)
	# Wide toothy grin.
	k.add_sphere(0.1, _xf(head + Vector3(0, -0.07, -0.155), Vector3(-8, 0, 0), Vector3(1.0, 0.32, 0.4)), DARK, 12, 5)
	for side: float in [-1.0, 1.0]:
		k.add_cylinder(0.0, 0.014, 0.04, _xf(head + Vector3(0.045 * side, -0.06, -0.19), Vector3(180, 0, 0)), WHITE, 5)
	# Eyes: big yellow with slit pupils and a highlight; cheeky brows.
	for side: float in [-1.0, 1.0]:
		var eye := head + Vector3(0.068 * side, 0.035, -0.13)
		k.add_sphere(0.052, _xf(eye, Vector3.ZERO, Vector3(1.0, 1.15, 0.7)), EYE, 10, 5)
		k.add_sphere(0.024, _xf(eye + Vector3(0.004 * side, 0.0, -0.03), Vector3.ZERO, Vector3(0.55, 1.3, 0.5)), DARK, 8, 4)
		k.add_sphere(0.01, _xf(eye + Vector3(-0.012 * side, 0.02, -0.035)), WHITE, 4, 2)
		k.add_box(Vector3(0.07, 0.016, 0.02), _xf(eye + Vector3(0.0, 0.055, -0.01), Vector3(0, 0, -22.0 * side)), SKIN_DARK)
		# Pointy ears.
		k.add_segment(head + Vector3(0.14 * side, 0.02, 0.0), head + Vector3(0.29 * side, 0.08, 0.03), 0.045, 0.0, SKIN, 8)
		# Curved cream horns.
		k.add_tube(PackedVector3Array([head + Vector3(0.075 * side, 0.13, -0.01),
				head + Vector3(0.11 * side, 0.22, 0.01), head + Vector3(0.09 * side, 0.3, 0.07)]),
				0.035, 0.006, HORN, 8)
		# Short legs with round feet (dangling while it hovers).
		var hip := Vector3(0.07 * side, -0.11, 0.0)
		var foot := Vector3(0.085 * side, -0.27, -0.03)
		k.add_segment(hip, foot, 0.045, 0.035, SKIN, 8)
		k.add_sphere(0.045, _xf(foot + Vector3(0, -0.01, -0.03), Vector3.ZERO, Vector3(1.0, 0.7, 1.4)), SKIN_DARK, 8, 4)
	# Left arm hangs, right arm is raised under the fireball.
	k.add_segment(Vector3(-0.13, 0.06, 0.0), Vector3(-0.2, -0.06, -0.06), 0.035, 0.03, SKIN, 8)
	k.add_sphere(0.038, _xf(Vector3(-0.2, -0.07, -0.07)), SKIN_DARK, 8, 4)
	k.add_segment(Vector3(0.13, 0.07, 0.0), Vector3(0.23, 0.17, -0.1), 0.035, 0.03, SKIN, 8)
	k.add_sphere(0.04, _xf(Vector3(0.235, 0.18, -0.105)), SKIN_DARK, 8, 4)
	# Tail with an arrow tip.
	k.add_tube(PackedVector3Array([Vector3(0, -0.08, 0.12), Vector3(0.0, -0.2, 0.25),
			Vector3(0.06, -0.14, 0.38), Vector3(0.1, -0.02, 0.42)]), 0.026, 0.012, SKIN, 6)
	var arrow := PackedVector2Array([Vector2(0.0, 0.07), Vector2(-0.05, -0.02), Vector2(0.0, 0.0), Vector2(0.05, -0.02)])
	k.add_extrusion(arrow, 0.02, _xf(Vector3(0.105, 0.0, 0.425), Vector3(0, 90, 0)), SKIN_DARK)
	# Little loincloth.
	k.add_cylinder(0.12, 0.155, 0.07, _xf(Vector3(0, -0.1, 0.0)), Color(0.25, 0.12, 0.3), 12)
	return k.build()


## Bat wing for [param side] (-1 left, +1 right), its root at the origin.
static func _wing_mesh(side: float) -> Mesh:
	var k := MeshKit.new()
	var outline := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.1, 0.1), Vector2(0.24, 0.16), Vector2(0.33, 0.1),
		Vector2(0.27, 0.04), Vector2(0.23, -0.05), Vector2(0.16, 0.0), Vector2(0.1, -0.07),
		Vector2(0.05, -0.02),
	])
	var mirrored := PackedVector2Array()
	for v in outline:
		mirrored.append(Vector2(v.x * side, v.y))
	k.add_extrusion(mirrored, 0.014, _xf(Vector3(0, 0, 0.02)), WING)
	k.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0.1 * side, 0.1, 0.02),
			Vector3(0.24 * side, 0.16, 0.02), Vector3(0.33 * side, 0.1, 0.02)]), 0.016, 0.007, SKIN_DARK, 6)
	return k.build()


static func _flame_tip_mesh() -> Mesh:
	var k := MeshKit.new()
	k.add_cylinder(0.0, 0.07, 0.15, _xf(Vector3(0, 0.09, 0.0)), Color.WHITE, 10)
	return k.build()


static func _sphere_mesh(radius: float) -> Mesh:
	return MeshKit.cached("warlock:imp:sphere:%.3f" % radius, func() -> Mesh:
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius * 2.0
		m.radial_segments = 12
		m.rings = 6
		return m)
