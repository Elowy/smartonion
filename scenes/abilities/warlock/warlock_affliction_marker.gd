class_name WarlockAfflictionMarker
extends Node3D
## Little look on an enemy afflicted by the Warlock, added as a child of the enemy (it moves
## and dies with it): Corruption = three purple wisps circling the body; Seed of Corruption =
## a glowing fel seed over the head that throbs faster as it ripens; Fear = a pale purple
## ghost wisp wobbling over the head. One MeshInstance3D each (a cached merged mesh with a
## cached glow material); the animation only moves / scales the node. [method finish] frees it.

const CORRUPTION := &"corruption"
const SEED := &"seed"
const FEAR := &"fear"

const CORRUPTION_COLOR := Color(0.62, 0.3, 0.98)
const SEED_COLOR := Color(0.55, 1.0, 0.3)
const FEAR_COLOR := Color(0.8, 0.62, 1.0)
const SPIN_SPEED := 3.2
const ORBIT_RADIUS := 0.5
## Heights over the enemy's feet, per model scale.
const HEAD_HEIGHT := 1.35

var kind: StringName = CORRUPTION
## 0..1: how far a seed is towards bursting (faster throb).
var ripeness := 0.0
var _mesh: MeshInstance3D
var _time := 0.0
var _base_y := 0.0


## Adds a marker of [param p_kind] to [param enemy] (null when the enemy is gone).
static func attach(enemy: Enemy, p_kind: StringName) -> WarlockAfflictionMarker:
	if enemy == null or not is_instance_valid(enemy) or not enemy.is_inside_tree():
		return null
	var m := WarlockAfflictionMarker.new()
	m.name = "Warlock%sMarker" % String(p_kind).capitalize().replace(" ", "")
	m.kind = p_kind
	var s := enemy.data.model_scale if enemy.data != null else 1.0
	m._base_y = WarlockSpell.body_height(enemy) if p_kind == CORRUPTION else HEAD_HEIGHT * s
	m.position = Vector3(0.0, m._base_y, 0.0)
	m.scale = Vector3.ONE * clampf(s, 0.7, 1.4)
	m._build()
	enemy.add_child(m)
	return m


## Frees the marker (safe on a freed one).
static func release(marker: Variant) -> void:
	if marker != null and is_instance_valid(marker) and not (marker as Node).is_queued_for_deletion():
		(marker as Node).queue_free()


func finish() -> void:
	queue_free()


func _build() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "Look"
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match kind:
		SEED:
			_mesh.mesh = MeshKit.cached("warlock:marker:seed", func() -> Mesh: return _seed_mesh())
			_mesh.material_override = Mats.glow(SEED_COLOR, 2.4)
		FEAR:
			_mesh.mesh = MeshKit.cached("warlock:marker:fear", func() -> Mesh: return _fear_mesh())
			_mesh.material_override = Mats.glow(FEAR_COLOR, 1.8)
		_:
			_mesh.mesh = MeshKit.cached("warlock:marker:corruption", func() -> Mesh: return _wisps_mesh())
			_mesh.material_override = Mats.glow(CORRUPTION_COLOR, 2.2)
	add_child(_mesh)


func _process(delta: float) -> void:
	_time += delta
	match kind:
		SEED:
			var speed := 5.0 + 14.0 * clampf(ripeness, 0.0, 1.0)
			var throb := 1.0 + (0.12 + 0.18 * ripeness) * sin(_time * speed)
			_mesh.scale = Vector3.ONE * throb
			_mesh.rotation.y = _time * 1.5
			position.y = _base_y + 0.05 * sin(_time * 2.3)
		FEAR:
			position.y = _base_y + 0.08 * sin(_time * 6.0)
			_mesh.rotation.z = 0.25 * sin(_time * 9.0)
		_:
			_mesh.rotation.y = -_time * SPIN_SPEED
			_mesh.position.y = 0.06 * sin(_time * 2.0)


# --- Meshes (cached, white – the glow material colours them) -----------------------------------

## Three tadpole wisps on a circle (heads leading, counter-clockwise from above).
static func _wisps_mesh() -> Mesh:
	var k := MeshKit.new()
	for i in 3:
		var a := TAU * float(i) / 3.0
		var head := Vector3(cos(a), 0.0, sin(a)) * ORBIT_RADIUS
		k.add_sphere(0.075, MeshKit.xf(head), Color.WHITE, 8, 4)
		for j in 3:
			var b := a - 0.22 * float(j + 1)
			var r := 0.055 - 0.014 * float(j)
			var y := 0.03 * float(j + 1)
			k.add_sphere(r, MeshKit.xf(Vector3(cos(b), 0.0, sin(b)) * ORBIT_RADIUS + Vector3(0, y, 0)), Color.WHITE, 6, 3)
	return k.build()


## A teardrop seed with two little sprouts.
static func _seed_mesh() -> Mesh:
	var k := MeshKit.new()
	k.add_sphere(0.13, MeshKit.xf(Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.25, 1.0)), Color.WHITE, 10, 6)
	k.add_cylinder(0.0, 0.08, 0.16, MeshKit.xf(Vector3(0, 0.2, 0)), Color.WHITE, 8)
	for side: float in [-1.0, 1.0]:
		k.add_segment(Vector3(0, 0.22, 0), Vector3(0.12 * side, 0.34, 0.02), 0.025, 0.0, Color.WHITE, 5)
	return k.build()


## A tiny ghost wisp: round head with a tapering tail.
static func _fear_mesh() -> Mesh:
	var k := MeshKit.new()
	k.add_sphere(0.14, MeshKit.xf(Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.1, 0.7)), Color.WHITE, 10, 6)
	k.add_cylinder(0.0, 0.1, 0.2, MeshKit.xf(Vector3(0, -0.18, 0), Vector3(180, 0, 0)), Color.WHITE, 8)
	return k.build()
