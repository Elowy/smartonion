class_name CartModel
extends EnemyModel
## The Goblin Caravan's cart (M6b EVENTS), an [EnemyModel] the [CaravanCart] swaps in for the stock model:
## a wooden two-wheeler loaded with sacks and gold, a long shaft in front and a green goblin driver on the
## bed. Origin at the ground in the middle of the axle line, faces -Z like every model (the cart's own
## yaw follows [method set_facing]). The wheels roll with the distance it travels ([method set_moving]
## gives the speed ratio, [member roll_speed] the m/s at ratio 1), the load glints, the whole cart sways a
## little and flashes white when hit. One cached body mesh, two wheel nodes sharing one cached mesh and the
## driver: five nodes, as cheap as an enemy.

const WOOD_DARK := Color(0.33, 0.2, 0.1)
const PLANK := Color(0.6, 0.4, 0.22)
const SACK_COLOR := Color(0.72, 0.56, 0.34)
const CANVAS := Color(0.86, 0.8, 0.62)
const GLINT := Color(1.0, 0.86, 0.35)
const WHEEL_RADIUS := 0.45
const WHEEL_X := 0.82
const WHEEL_Z := 0.25
const DRIVER_SKIN := Color(0.42, 0.64, 0.26)

## Metres per second the cart travels at speed ratio 1 (the wheels roll with it).
var roll_speed := 1.4

var _wheels: Array[MeshInstance3D] = []
var _driver: MeshInstance3D
var _roll := 0.0


func setup(p_data: EnemyData) -> void:
	data = p_data
	style = &"cart"
	_scale = 1.0
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_stars = null
	_overlay_state = Vector2i.ZERO
	_wheels.clear()
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	_body = MeshInstance3D.new()
	_body.name = "Body"
	_body.mesh = MeshKit.cached("event:cart_body", func() -> Mesh: return _body_mesh())
	_body.material_override = Mats.toon_vc()
	_pivot.add_child(_body)
	for side: float in [-1.0, 1.0]:
		var wheel := MeshInstance3D.new()
		wheel.name = "Wheel%s" % ("L" if side < 0.0 else "R")
		wheel.mesh = MeshKit.cached("event:cart_wheel", func() -> Mesh: return _wheel_mesh())
		wheel.material_override = Mats.toon_vc()
		wheel.position = Vector3(WHEEL_X * side, WHEEL_RADIUS, WHEEL_Z)
		_pivot.add_child(wheel)
		_wheels.append(wheel)
	var parts := EnemyModel.parts_for(&"goblin", DRIVER_SKIN)
	_driver = MeshInstance3D.new()
	_driver.name = "Driver"
	_driver.mesh = parts["body"]
	_driver.material_override = Mats.toon_vc()
	_driver.position = Vector3(0.0, 0.72, -0.55)
	_driver.scale = Vector3.ONE * 1.25
	_pivot.add_child(_driver)
	_glow = MeshInstance3D.new()
	_glow.name = "Glow"
	_glow.mesh = MeshKit.cached("event:cart_glint", func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = 0.13
		s.height = 0.26
		s.radial_segments = 8
		s.rings = 4
		return s)
	_glow.material_override = Mats.glow(GLINT, 2.4)
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow.position = Vector3(0.1, 1.28, 0.55)
	_pivot.add_child(_glow)
	head_height = 1.7
	_pivot.rotation.y = _target_yaw
	_yaw = _target_yaw
	_apply_overlay()


func _process(delta: float) -> void:
	if _pivot == null:
		return
	_time += delta
	_speed = lerpf(_speed, 0.0 if _stunned else _speed_target, 1.0 - exp(-10.0 * delta))
	_yaw = lerp_angle(_yaw, _target_yaw, 1.0 - exp(-TURN_SPEED * delta))
	_phase += delta * (3.0 + 6.0 * _speed) * (1.0 if _speed > 0.02 else 0.0)
	_roll += _speed * roll_speed * delta / WHEEL_RADIUS
	var sway := sin(_phase) * 0.035 * _speed
	var bob := absf(sin(_phase * 0.5)) * 0.04 * _speed
	_pivot.position = Vector3(0.0, bob, 0.0)
	_pivot.rotation = Vector3(0.0, _yaw, sway)
	for wheel in _wheels:
		wheel.rotation.x = _roll
	if _glow != null:
		var f := 1.0 + sin(_time * 11.0) * 0.18
		_glow.scale = Vector3(f, f, f)
	if _stunned and _stars != null:
		_stars.rotation.y = _time * 5.0
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta / FLASH_TIME)
		_overlay_dirty = true
	if _overlay_dirty:
		_apply_overlay()


## The hit flash (white, fading) on the cart and its driver; the stock wind-up tells do not exist here.
func _apply_overlay() -> void:
	_overlay_dirty = false
	if _body == null:
		return
	var state := Vector2i(1, roundi(_flash * 0.9 * Mats.OVERLAY_STEPS))
	if state == _overlay_state:
		return
	_overlay_state = state
	var amount := float(state.y) / Mats.OVERLAY_STEPS
	Mats.set_overlay(_body, Color.WHITE, amount, 0.0)
	if _driver != null:
		Mats.set_overlay(_driver, Color.WHITE, amount, 0.0)
	for wheel in _wheels:
		Mats.set_overlay(wheel, Color.WHITE, amount, 0.0)


## Bed, rails, canvas-less frame, shafts, sacks and the gold heap (the wheels and the driver are nodes).
static func _body_mesh() -> Mesh:
	var k := MeshKit.new()
	# The bed and its rails.
	k.add_box(Vector3(1.3, 0.14, 2.3), MeshKit.xf(Vector3(0.0, 0.68, 0.1)), PLANK)
	for side: float in [-1.0, 1.0]:
		k.add_box(Vector3(0.09, 0.4, 2.3), MeshKit.xf(Vector3(0.64 * side, 0.9, 0.1)), WOOD)
		k.add_box(Vector3(0.11, 0.06, 2.34), MeshKit.xf(Vector3(0.64 * side, 1.12, 0.1)), WOOD_DARK)
	k.add_box(Vector3(1.3, 0.4, 0.09), MeshKit.xf(Vector3(0.0, 0.9, 1.24)), WOOD)
	k.add_box(Vector3(1.3, 0.28, 0.09), MeshKit.xf(Vector3(0.0, 0.84, -1.04)), WOOD)
	# Axle and the shafts the (invisible) pony would pull on.
	k.add_cylinder(0.06, 0.06, 1.9, MeshKit.xf(Vector3(0.0, WHEEL_RADIUS, WHEEL_Z), Vector3(0.0, 0.0, 90.0)), IRON, 8)
	for side: float in [-1.0, 1.0]:
		k.add_segment(Vector3(0.45 * side, 0.66, -0.9), Vector3(0.42 * side, 0.56, -2.35), 0.05, 0.04, WOOD_DARK, 6)
	k.add_segment(Vector3(-0.42, 0.56, -2.35), Vector3(0.42, 0.56, -2.35), 0.04, 0.04, WOOD_DARK, 6)
	# The load: tied sacks, a canvas bundle and a heap of gold with bars on top.
	k.add_sphere(0.34, MeshKit.xf(Vector3(-0.3, 1.05, 0.55), Vector3.ZERO, Vector3(1.0, 1.1, 1.0)), SACK_COLOR, 12, 6)
	k.add_sphere(0.3, MeshKit.xf(Vector3(0.32, 1.0, 0.75), Vector3.ZERO, Vector3(1.0, 1.0, 1.1)), SACK_COLOR.darkened(0.1), 12, 6)
	k.add_cylinder(0.07, 0.1, 0.1, MeshKit.xf(Vector3(-0.3, 1.46, 0.55)), SACK_COLOR.lightened(0.1), 8)
	k.add_sphere(0.36, MeshKit.xf(Vector3(0.0, 0.92, 0.1), Vector3.ZERO, Vector3(1.3, 0.8, 1.2)), CANVAS, 12, 6)
	k.add_sphere(0.38, MeshKit.xf(Vector3(0.05, 0.95, 0.9), Vector3.ZERO, Vector3(1.4, 0.6, 1.1)), GLINT.darkened(0.15), 12, 6)
	for p: Vector3 in [Vector3(-0.15, 1.2, 0.95), Vector3(0.2, 1.22, 0.85), Vector3(0.0, 1.32, 0.9)]:
		k.add_box(Vector3(0.3, 0.1, 0.16), MeshKit.xf(p, Vector3(0.0, 20.0 * signf(p.x + 0.01), 0.0)), GLINT)
	for p: Vector3 in [Vector3(0.35, 1.18, 0.45), Vector3(-0.1, 1.15, 1.1), Vector3(0.3, 1.14, 1.15)]:
		k.add_cylinder(0.09, 0.09, 0.025, MeshKit.xf(p, Vector3(70.0, 0.0, 25.0)), GLINT.lightened(0.2), 10)
	# A hanging lantern on the back corner.
	k.add_box(Vector3(0.05, 0.4, 0.05), MeshKit.xf(Vector3(0.6, 1.3, 1.22)), IRON)
	k.add_sphere(0.09, MeshKit.xf(Vector3(0.6, 1.5, 1.22)), Color(1.0, 0.7, 0.25), 8, 4)
	return k.build()


## A spoked wheel in its own space: the axle runs along X, so the node spins about X.
static func _wheel_mesh() -> Mesh:
	var k := MeshKit.new()
	k.add_torus(WHEEL_RADIUS - 0.07, WHEEL_RADIUS, MeshKit.xf(Vector3.ZERO, Vector3(0.0, 0.0, 90.0)), WOOD_DARK, 16, 5)
	k.add_cylinder(0.09, 0.09, 0.16, MeshKit.xf(Vector3.ZERO, Vector3(0.0, 0.0, 90.0)), IRON, 8)
	for i in 4:
		var a := PI * float(i) / 4.0
		k.add_segment(Vector3(0.0, sin(a) * -(WHEEL_RADIUS - 0.05), cos(a) * -(WHEEL_RADIUS - 0.05)),
				Vector3(0.0, sin(a) * (WHEEL_RADIUS - 0.05), cos(a) * (WHEEL_RADIUS - 0.05)), 0.035, 0.035, WOOD, 6)
	return k.build()
