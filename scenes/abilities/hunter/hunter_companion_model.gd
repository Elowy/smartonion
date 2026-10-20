class_name HunterCompanionModel
extends Node3D
## Procedural look of the Hunter's companion (placeholder art from primitives + Mats): a grey
## Wolf with a leather collar, a stocky brown Boar with ivory tusks and a bristly mane, or a
## round tawny Owl with a pale facial disc that hovers at [constant HOVER_HEIGHT] over a soft
## ground shadow. Faces -Z; [member kind] must be set before the model enters the tree.
##
## Body (+ head) is one cached MeshKit mesh per kind, drawn with Mats.toon_vc(); the legs and the
## tail of the Wolf / Boar and the wings of the Owl are separate cached meshes whose nodes are
## swung in _process (trot cycle, wagging, flaps); attacks lunge the body forward. A pulsing
## amber ring marks Pack Frenzy ([method set_frenzy]). Only nodes move – materials are shared.

const WOLF_SCALE := 1.05
const BOAR_SCALE := 1.2
const OWL_SCALE := 1.0
const HOVER_HEIGHT := 1.6
const DIVE_HEIGHT := 0.75
const TURN_SPEED := 12.0
const TROT_SPEED := 13.0
const ATTACK_TIME := 0.25
const FLAP_SPEED := 16.0
const FRENZY_COLOR := Color(1.0, 0.55, 0.15, 0.85)

const WOLF_FUR := Color(0.52, 0.48, 0.44)
const WOLF_DARK := Color(0.29, 0.26, 0.26)
const WOLF_LIGHT := Color(0.84, 0.79, 0.7)
const COLLAR := Color(0.5, 0.32, 0.16)
const TAG := Color(0.96, 0.76, 0.3)
const NOSE := Color(0.12, 0.1, 0.12)
const EYE := Color(0.98, 0.78, 0.2)

const BOAR_FUR := Color(0.47, 0.31, 0.2)
const BOAR_DARK := Color(0.26, 0.17, 0.12)
const BOAR_LIGHT := Color(0.64, 0.47, 0.33)
const SNOUT := Color(0.78, 0.58, 0.52)
const IVORY := Color(0.96, 0.92, 0.8)

const OWL_BACK := Color(0.52, 0.36, 0.22)
const OWL_DARK := Color(0.32, 0.21, 0.13)
const OWL_BELLY := Color(0.94, 0.88, 0.74)
const OWL_DISC := Color(0.96, 0.92, 0.82)
const BEAK := Color(0.96, 0.62, 0.18)
const OWL_EYE := Color(1.0, 0.82, 0.15)
const BLACK := Color(0.07, 0.05, 0.06)

## Hips of the Wolf and the Boar (pivot space): front left, front right, hind left, hind right.
const WOLF_HIPS: Array[Vector3] = [Vector3(-0.1, 0.42, -0.24), Vector3(0.1, 0.42, -0.24),
		Vector3(-0.1, 0.42, 0.22), Vector3(0.1, 0.42, 0.22)]
const BOAR_HIPS: Array[Vector3] = [Vector3(-0.15, 0.3, -0.26), Vector3(0.15, 0.3, -0.26),
		Vector3(-0.14, 0.3, 0.26), Vector3(0.14, 0.3, 0.26)]

var kind: StringName = &"wolf"

var _pivot: Node3D
var _legs: Array[Node3D] = []
var _tail: Node3D
var _wings: Array[Node3D] = []
var _glow: MeshInstance3D
var _shadow: MeshInstance3D
var _time := 0.0
var _yaw := 0.0
var _target_yaw := 0.0
var _moving := 0.0
var _attack := 1.0
var _diving := false
var _dive := 0.0
var _frenzy := false


func _init() -> void:
	name = "CompanionModel"


func _ready() -> void:
	if _pivot == null:
		_build()


func set_facing(direction: Vector3) -> void:
	if Vector2(direction.x, direction.z).length_squared() < 0.0001:
		return
	_target_yaw = atan2(-direction.x, -direction.z)


## 0..1 trot / flap strength.
func set_moving(ratio: float) -> void:
	_moving = clampf(ratio, 0.0, 1.0)


## A bite, a peck or a blow: the body lunges forward.
func play_attack() -> void:
	_attack = 0.0


## The Owl swoops low for a Hunt Signal strike.
func set_diving(on: bool) -> void:
	_diving = on


## Pack Frenzy: the amber ring pulses under the companion.
func set_frenzy(on: bool) -> void:
	_frenzy = on
	if _glow != null:
		_glow.visible = on


func is_frenzied() -> bool:
	return _frenzy


func _build() -> void:
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	var scale_by := WOLF_SCALE
	match kind:
		&"boar":
			scale_by = BOAR_SCALE
		&"owl":
			scale_by = OWL_SCALE
	_pivot.scale = Vector3.ONE * scale_by
	add_child(_pivot)
	var mat := Mats.toon_vc()
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = MeshKit.cached("hunter:%s:body" % kind, func() -> Mesh: return _body_mesh(kind))
	body.material_override = mat
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pivot.add_child(body)
	match kind:
		&"owl":
			_build_owl(mat)
		_:
			_build_ground(mat)
	_glow = MeshInstance3D.new()
	_glow.name = "FrenzyGlow"
	_glow.mesh = MeshKit.cached("hunter:quad2", func() -> Mesh:
		var q := PlaneMesh.new()
		q.size = Vector2(2.0, 2.0)
		return q)
	_glow.material_override = Mats.ring()
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow.position.y = 0.05
	_glow.scale = Vector3(0.8, 1.0, 0.8) * scale_by
	Mats.set_ring(_glow, FRENZY_COLOR, 0.72, 0.95, 0.3)
	_glow.visible = _frenzy
	add_child(_glow)
	_pivot.rotation.y = _target_yaw
	_yaw = _target_yaw


func _build_ground(mat: Material) -> void:
	var hips := WOLF_HIPS if kind == &"wolf" else BOAR_HIPS
	var leg_mesh := MeshKit.cached("hunter:%s:leg" % kind, func() -> Mesh: return _leg_mesh(kind))
	for i in hips.size():
		var leg := Node3D.new()
		leg.name = "Leg%d" % i
		leg.position = hips[i]
		_pivot.add_child(leg)
		var mi := MeshInstance3D.new()
		mi.mesh = leg_mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		leg.add_child(mi)
		_legs.append(leg)
	_tail = Node3D.new()
	_tail.name = "Tail"
	_tail.position = Vector3(0.0, 0.55, 0.34) if kind == &"wolf" else Vector3(0.0, 0.5, 0.42)
	_pivot.add_child(_tail)
	var tail := MeshInstance3D.new()
	tail.mesh = MeshKit.cached("hunter:%s:tail" % kind, func() -> Mesh: return _tail_mesh(kind))
	tail.material_override = mat
	tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tail.add_child(tail)


func _build_owl(mat: Material) -> void:
	for side: float in [-1.0, 1.0]:
		var wing := Node3D.new()
		wing.name = "WingL" if side < 0.0 else "WingR"
		wing.position = Vector3(0.17 * side, 0.08, 0.0)
		_pivot.add_child(wing)
		var mi := MeshInstance3D.new()
		mi.mesh = MeshKit.cached("hunter:owl:wing:%d" % int(side), func() -> Mesh: return _wing_mesh(side))
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wing.add_child(mi)
		_wings.append(wing)
	_pivot.position.y = HOVER_HEIGHT
	# A soft shadow on the ground keeps the hovering owl readable.
	_shadow = MeshInstance3D.new()
	_shadow.name = "Shadow"
	_shadow.mesh = MeshKit.cached("hunter:quad2", func() -> Mesh:
		var q := PlaneMesh.new()
		q.size = Vector2(2.0, 2.0)
		return q)
	_shadow.material_override = Mats.ring()
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.position.y = 0.04
	_shadow.scale = Vector3(0.38, 1.0, 0.38)
	Mats.set_ring(_shadow, Color(0.0, 0.0, 0.0, 0.5), 0.95, 0.99, 0.55)
	add_child(_shadow)


func _process(delta: float) -> void:
	if _pivot == null:
		return
	_time += delta
	_yaw = lerp_angle(_yaw, _target_yaw, 1.0 - exp(-TURN_SPEED * delta))
	_attack = minf(1.0, _attack + delta / ATTACK_TIME)
	var lunge := sin(_attack * PI) if _attack < 1.0 else 0.0
	if kind == &"owl":
		_animate_owl(delta, lunge)
	else:
		_animate_ground(lunge)
	if _glow != null and _glow.visible:
		Mats.set_ring(_glow, Color(FRENZY_COLOR, 0.55 + 0.3 * sin(_time * 9.0)), 0.72, 0.95, 0.3)
	if _glow != null:
		_glow.rotation.y = _yaw


func _animate_ground(lunge: float) -> void:
	var trot := _time * TROT_SPEED
	var scale_by := _pivot.scale.x
	_pivot.rotation = Vector3(-0.25 * lunge, _yaw, 0.0)
	var forward := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	_pivot.position = forward * 0.22 * lunge * scale_by \
			+ Vector3.UP * (absf(sin(trot)) * 0.05 * _moving + 0.02 * sin(_time * 2.0)) * scale_by
	for i in _legs.size():
		# Diagonal pairs move together (trot): FL + HR, FR + HL.
		var phase := 0.0 if i == 0 or i == 3 else PI
		_legs[i].rotation.x = sin(trot + phase) * 0.6 * _moving
	if _tail != null:
		var wag := 6.0 + 6.0 * _moving
		if kind == &"boar":
			_tail.rotation = Vector3(0.2, 0.0, sin(_time * wag) * 0.25)
		else:
			_tail.rotation = Vector3(0.35 + 0.15 * sin(_time * 3.0), 0.0, sin(_time * wag) * 0.35)


func _animate_owl(delta: float, lunge: float) -> void:
	_dive = move_toward(_dive, 1.0 if _diving else 0.0, delta * 5.0)
	var flap := sin(_time * FLAP_SPEED * (1.0 + 0.5 * _moving + 0.5 * _dive))
	var height := lerpf(HOVER_HEIGHT, DIVE_HEIGHT, _dive)
	_pivot.rotation = Vector3(-0.2 * _moving - 0.55 * _dive - 0.25 * lunge, _yaw, 0.0)
	_pivot.position.y = height + sin(_time * 3.1) * 0.06
	var forward := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	_pivot.position.x = forward.x * 0.2 * lunge
	_pivot.position.z = forward.z * 0.2 * lunge
	for i in _wings.size():
		var side := -1.0 if i == 0 else 1.0
		_wings[i].rotation = Vector3(0.0, 0.0, side * (0.1 + 0.6 * flap))
	if _shadow != null:
		_shadow.scale = Vector3(0.38, 1.0, 0.38) * lerpf(1.0, 0.7, _dive)


# --- Meshes (shared, cached) ------------------------------------------------------------------

static func _xf(pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Transform3D:
	return MeshKit.xf(pos, rot, scl)


static func _body_mesh(p_kind: StringName) -> Mesh:
	match p_kind:
		&"boar":
			return _boar_body()
		&"owl":
			return _owl_body()
	return _wolf_body()


static func _wolf_body() -> Mesh:
	var k := MeshKit.new()
	# Deep chest, lean belly, haunches, a darker saddle over the back.
	k.add_sphere(0.17, _xf(Vector3(0, 0.52, -0.17), Vector3.ZERO, Vector3(1.0, 1.1, 1.2)), WOLF_FUR, 12, 6)
	k.add_capsule(0.12, 0.5, _xf(Vector3(0, 0.53, 0.02), Vector3(90, 0, 0)), WOLF_FUR, 10, 4)
	k.add_sphere(0.14, _xf(Vector3(0, 0.53, 0.2), Vector3.ZERO, Vector3(1.0, 1.0, 1.1)), WOLF_FUR, 12, 6)
	k.add_sphere(0.13, _xf(Vector3(0, 0.6, -0.02), Vector3.ZERO, Vector3(0.95, 0.55, 2.0)), WOLF_DARK, 10, 5)
	k.add_sphere(0.11, _xf(Vector3(0, 0.44, -0.2), Vector3.ZERO, Vector3(0.9, 0.7, 1.1)), WOLF_LIGHT, 10, 5)
	# Neck and head.
	k.add_segment(Vector3(0, 0.58, -0.25), Vector3(0, 0.72, -0.38), 0.11, 0.09, WOLF_FUR, 10)
	var head := Vector3(0, 0.74, -0.42)
	k.add_sphere(0.11, _xf(head, Vector3.ZERO, Vector3(1.0, 0.95, 1.1)), WOLF_FUR, 12, 6)
	# Long pale snout with a dark nose.
	k.add_segment(head + Vector3(0, -0.02, -0.06), head + Vector3(0, -0.05, -0.24), 0.065, 0.035, WOLF_LIGHT, 8)
	k.add_sphere(0.032, _xf(head + Vector3(0, -0.04, -0.25)), NOSE, 6, 3)
	# Pointed ears, dark on the outside.
	for side: float in [-1.0, 1.0]:
		k.add_segment(head + Vector3(0.055 * side, 0.07, 0.02), head + Vector3(0.08 * side, 0.2, 0.04), 0.04, 0.0, WOLF_DARK, 6)
		k.add_sphere(0.022, _xf(head + Vector3(0.062 * side, 0.03, -0.085)), EYE, 6, 3)
		k.add_sphere(0.011, _xf(head + Vector3(0.062 * side, 0.03, -0.103)), NOSE, 4, 2)
	# Ruff of fur round the neck and the leather collar with a tag.
	k.add_torus(0.1, 0.17, _xf(Vector3(0, 0.6, -0.27), Vector3(70, 0, 0)), WOLF_LIGHT, 12, 6)
	k.add_torus(0.085, 0.115, _xf(Vector3(0, 0.62, -0.3), Vector3(70, 0, 0)), COLLAR, 12, 5)
	k.add_sphere(0.03, _xf(Vector3(0, 0.55, -0.36)), TAG, 6, 3)
	return k.build()


static func _boar_body() -> Mesh:
	var k := MeshKit.new()
	# Barrel body: heavy shoulders, round haunches, a pale belly.
	k.add_sphere(0.24, _xf(Vector3(0, 0.44, -0.1), Vector3.ZERO, Vector3(1.0, 0.95, 1.35)), BOAR_FUR, 14, 7)
	k.add_sphere(0.22, _xf(Vector3(0, 0.43, 0.24), Vector3.ZERO, Vector3(1.0, 0.95, 1.1)), BOAR_FUR, 14, 7)
	k.add_sphere(0.2, _xf(Vector3(0, 0.55, -0.22), Vector3.ZERO, Vector3(1.05, 0.9, 1.05)), BOAR_DARK, 12, 6)
	k.add_sphere(0.2, _xf(Vector3(0, 0.32, -0.02), Vector3.ZERO, Vector3(0.9, 0.5, 1.8)), BOAR_LIGHT, 10, 5)
	# A bristly mane along the back.
	for i in 7:
		var z := -0.4 + 0.1 * float(i)
		var y := 0.66 - 0.02 * absf(float(i) - 2.0)
		k.add_segment(Vector3(0, y - 0.02, z), Vector3(0, y + 0.1, z + 0.02), 0.035, 0.0, BOAR_DARK, 5)
	# Head: low and wedge-shaped, with a flat snout disc.
	var head := Vector3(0, 0.4, -0.5)
	k.add_sphere(0.17, _xf(head, Vector3.ZERO, Vector3(1.0, 0.92, 1.2)), BOAR_FUR, 12, 6)
	k.add_segment(head + Vector3(0, -0.02, -0.08), head + Vector3(0, -0.06, -0.26), 0.1, 0.075, BOAR_LIGHT, 8)
	k.add_cylinder(0.075, 0.075, 0.04, _xf(head + Vector3(0, -0.06, -0.28), Vector3(90, 0, 0)), SNOUT, 10)
	for side: float in [-1.0, 1.0]:
		k.add_sphere(0.014, _xf(head + Vector3(0.03 * side, -0.05, -0.3)), BOAR_DARK, 4, 2)
		# Curved ivory tusks, ears and small eyes.
		k.add_tube(PackedVector3Array([head + Vector3(0.08 * side, -0.08, -0.2), head + Vector3(0.13 * side, -0.06, -0.27),
				head + Vector3(0.14 * side, 0.03, -0.3)]), 0.026, 0.004, IVORY, 6)
		k.add_segment(head + Vector3(0.1 * side, 0.12, 0.02), head + Vector3(0.15 * side, 0.26, 0.0), 0.05, 0.0, BOAR_DARK, 5)
		k.add_sphere(0.026, _xf(head + Vector3(0.085 * side, 0.06, -0.12)), OWL_EYE, 6, 3)
		k.add_sphere(0.013, _xf(head + Vector3(0.085 * side, 0.06, -0.14)), BLACK, 4, 2)
	return k.build()


static func _owl_body() -> Mesh:
	var k := MeshKit.new()
	# Round body: tawny back, pale speckled belly, short tail.
	k.add_sphere(0.2, _xf(Vector3(0, 0.0, 0.02), Vector3.ZERO, Vector3(1.0, 1.2, 0.95)), OWL_BACK, 14, 7)
	k.add_sphere(0.16, _xf(Vector3(0, -0.02, -0.08), Vector3.ZERO, Vector3(0.9, 1.1, 0.6)), OWL_BELLY, 12, 6)
	for i in 3:
		k.add_sphere(0.022, _xf(Vector3(0.05 * float(i - 1), -0.02 - 0.06 * float(i % 2), -0.18)), OWL_BACK, 5, 3)
	# Head with a pale facial disc, big eyes, a small hooked beak and ear tufts.
	var head := Vector3(0, 0.27, -0.03)
	k.add_sphere(0.17, _xf(head, Vector3.ZERO, Vector3(1.15, 0.95, 1.0)), OWL_BACK, 14, 7)
	for side: float in [-1.0, 1.0]:
		var eye := head + Vector3(0.075 * side, 0.02, -0.12)
		k.add_sphere(0.1, _xf(eye, Vector3.ZERO, Vector3(1.0, 1.0, 0.4)), OWL_DISC, 12, 6)
		k.add_sphere(0.058, _xf(eye + Vector3(0, 0, -0.025), Vector3.ZERO, Vector3(1.0, 1.0, 0.6)), OWL_EYE, 10, 5)
		k.add_sphere(0.028, _xf(eye + Vector3(0, 0, -0.045), Vector3.ZERO, Vector3(1.0, 1.0, 0.6)), BLACK, 8, 4)
		k.add_segment(head + Vector3(0.1 * side, 0.12, 0.0), head + Vector3(0.14 * side, 0.27, 0.02), 0.04, 0.0, OWL_DARK, 6)
		# Feet dangling under the belly.
		var foot := Vector3(0.07 * side, -0.27, -0.06)
		k.add_segment(Vector3(0.07 * side, -0.18, -0.02), foot, 0.025, 0.02, BEAK, 5)
		for toe in 3:
			k.add_segment(foot, foot + Vector3((float(toe) - 1.0) * 0.03, -0.03, -0.05), 0.014, 0.004, BEAK.darkened(0.2), 4)
	k.add_segment(head + Vector3(0, 0.0, -0.15), head + Vector3(0, -0.07, -0.23), 0.032, 0.0, BEAK, 6)
	# Tail feathers fanning out behind.
	var tail := PackedVector2Array([Vector2(-0.07, 0.0), Vector2(0.07, 0.0), Vector2(0.11, 0.2), Vector2(0.04, 0.26),
			Vector2(-0.04, 0.26), Vector2(-0.11, 0.2)])
	k.add_extrusion(tail, 0.02, _xf(Vector3(0, -0.18, 0.12), Vector3(-110, 0, 0)), OWL_DARK)
	return k.build()


## One leg hanging down from its hip (origin), paw at the bottom.
static func _leg_mesh(p_kind: StringName) -> Mesh:
	var k := MeshKit.new()
	if p_kind == &"boar":
		k.add_segment(Vector3(0, 0.02, 0), Vector3(0, -0.26, 0.0), 0.07, 0.05, BOAR_FUR, 8)
		k.add_sphere(0.055, _xf(Vector3(0, -0.28, -0.015), Vector3.ZERO, Vector3(1.0, 0.6, 1.3)), BOAR_DARK, 8, 4)
		return k.build()
	k.add_segment(Vector3(0, 0.02, 0), Vector3(0, -0.22, 0.02), 0.07, 0.05, WOLF_FUR, 8)
	k.add_segment(Vector3(0, -0.22, 0.02), Vector3(0, -0.4, -0.01), 0.05, 0.04, WOLF_LIGHT, 8)
	k.add_sphere(0.055, _xf(Vector3(0, -0.4, -0.03), Vector3.ZERO, Vector3(1.0, 0.6, 1.4)), WOLF_LIGHT, 8, 4)
	return k.build()


## A tail curving back from its root (origin): bushy with a dark tip for the Wolf, a thin curl for the Boar.
static func _tail_mesh(p_kind: StringName) -> Mesh:
	var k := MeshKit.new()
	if p_kind == &"boar":
		k.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, 0.06, 0.08), Vector3(0.03, 0.12, 0.06), Vector3(0.03, 0.1, 0.0)]),
				0.03, 0.012, BOAR_DARK, 6)
		return k.build()
	k.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.02, 0.15), Vector3(0, -0.08, 0.3), Vector3(0, -0.06, 0.42)]),
			0.05, 0.02, WOLF_FUR, 8)
	k.add_sphere(0.07, _xf(Vector3(0, -0.06, 0.28), Vector3.ZERO, Vector3(0.9, 0.9, 1.6)), WOLF_FUR, 8, 4)
	k.add_sphere(0.05, _xf(Vector3(0, -0.07, 0.44), Vector3.ZERO, Vector3(0.9, 0.9, 1.3)), WOLF_DARK, 8, 4)
	return k.build()


## A wing for [param side] (-1 left, +1 right), its root at the origin: a long rounded feather
## shape with a darker leading edge.
static func _wing_mesh(side: float) -> Mesh:
	var k := MeshKit.new()
	var outline := PackedVector2Array([
		Vector2(0.0, 0.1), Vector2(0.14, 0.14), Vector2(0.3, 0.1), Vector2(0.42, 0.0), Vector2(0.4, -0.1),
		Vector2(0.32, -0.16), Vector2(0.22, -0.13), Vector2(0.14, -0.2), Vector2(0.06, -0.12), Vector2(0.0, -0.1),
	])
	var mirrored := PackedVector2Array()
	for v in outline:
		mirrored.append(Vector2(v.x * side, v.y))
	# The outline lies in XY (x outwards, y along the body): lay it flat with the leading edge forward (-Z).
	k.add_extrusion(mirrored, 0.025, _xf(Vector3(0, 0, 0), Vector3(90, 0, 0)), OWL_BACK)
	k.add_extrusion(PackedVector2Array([Vector2(0.0 * side, 0.1), Vector2(0.3 * side, 0.1), Vector2(0.4 * side, 0.0),
			Vector2(0.3 * side, 0.03), Vector2(0.0, 0.04)]), 0.03, _xf(Vector3(0, 0.005, 0), Vector3(90, 0, 0)), OWL_DARK)
	return k.build()
