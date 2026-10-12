class_name GoblinPortal
extends Node3D
## The Loot Goblin's escape portal (GDD 8, M5, architecture §2.6): a child of the
## [LootGoblin], standing just behind it (up-screen). The goblin drives the opening through
## [method set_progress] (0 = a spark, 1 = open, LootGoblin.PORTAL_TIME s); it is freed with
## the goblin (escape, death or wave end).
##
## Look (procedural, owned by GOBLIN): a gold rim and a violet swirl tilted towards the
## camera ("Gate"), and a violet ground ring under it. The swirl spins in [method _process]
## (cosmetic only, no gameplay state). Nodes: GoblinPortal → Ring, Gate → Rim, Swirl.

## Radius (m) of the open gate (rim centre line) and height of its centre.
const RADIUS := 0.62
const CENTER_HEIGHT := 0.85
## Offset (m) towards -Z (up-screen, behind the goblin as the camera sees it).
const BACK_OFFSET := 0.45
## Tilt of the gate from the ground plane towards the camera (degrees; 90 = upright).
const TILT_DEG := 62.0
## Scale of the gate / ring at progress 0.
const START_SCALE := 0.12
## Swirl speed (rad / s).
const SPIN_SPEED := 5.0
const RIM_COLOR := Color(1.0, 0.8, 0.3)
const CORE_COLOR := Color(0.55, 0.28, 1.0)
const ARM_COLOR := Color(0.85, 0.7, 1.0)
const RING_COLOR := Color(0.62, 0.38, 1.0, 0.85)

## 0..1: how far it has opened.
var progress := 0.0

var _gate: Node3D
var _rim: MeshInstance3D
var _swirl: MeshInstance3D
var _ring: MeshInstance3D
var _time := 0.0


static func create() -> GoblinPortal:
	var p := GoblinPortal.new()
	p.name = "GoblinPortal"
	p.position = Vector3(0.0, 0.0, -BACK_OFFSET)
	p._build()
	p.set_progress(0.0)
	return p


## Opening progress 0..1 (eased: grows fast, settles at full size).
func set_progress(value: float) -> void:
	progress = clampf(value, 0.0, 1.0)
	var s := lerpf(START_SCALE, 1.0, ease(progress, 0.4))
	if _gate != null:
		_gate.scale = Vector3.ONE * s
	if _ring != null:
		_ring.scale = Vector3(s * RADIUS * 3.0, 1.0, s * RADIUS * 3.0)


func _process(delta: float) -> void:
	_time += delta
	if _swirl != null:
		_swirl.rotation.y = -_time * SPIN_SPEED


func _build() -> void:
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	_ring.mesh = MeshKit.cached("goblin_portal:quad", func() -> Mesh:
		var q := PlaneMesh.new()
		q.size = Vector2(1, 1)
		return q)
	_ring.material_override = Mats.ring()
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position = Vector3(0.0, 0.04, BACK_OFFSET * 0.5)
	Mats.set_ring(_ring, RING_COLOR, 0.72, 0.96, 0.22)
	add_child(_ring)
	_gate = Node3D.new()
	_gate.name = "Gate"
	_gate.position = Vector3(0.0, CENTER_HEIGHT, 0.0)
	# Built in the XZ plane (normal +Y); tipped up so the normal leans to the camera (+Z, up).
	_gate.rotation.x = deg_to_rad(TILT_DEG)
	add_child(_gate)
	_rim = MeshInstance3D.new()
	_rim.name = "Rim"
	_rim.mesh = MeshKit.cached("goblin_portal:rim", func() -> Mesh: return _rim_mesh())
	_rim.material_override = Mats.glow(RIM_COLOR, 2.2)
	_rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gate.add_child(_rim)
	_swirl = MeshInstance3D.new()
	_swirl.name = "Swirl"
	_swirl.mesh = MeshKit.cached("goblin_portal:swirl", func() -> Mesh: return _swirl_mesh())
	_swirl.material_override = Mats.particle(true)
	_swirl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gate.add_child(_swirl)


static func _rim_mesh() -> Mesh:
	var k := MeshKit.new()
	k.add_torus(RADIUS - 0.06, RADIUS + 0.06, Transform3D(), Color.WHITE, 28, 8)
	# Four little gold studs (a goblin-made gate).
	for i in 4:
		var a := TAU * (float(i) + 0.5) / 4.0
		k.add_sphere(0.075, MeshKit.xf(Vector3(cos(a), 0.0, sin(a)) * RADIUS), Color.WHITE, 8, 4)
	return k.build()


## A violet disc with three lighter spiral arms (vertex colours, additive).
static func _swirl_mesh() -> Mesh:
	var k := MeshKit.new()
	k.add_cylinder(RADIUS - 0.04, RADIUS - 0.04, 0.01, Transform3D(), CORE_COLOR.darkened(0.35), 28)
	for arm in 3:
		var base := 120.0 * float(arm)
		# Each arm: arcs that widen and turn outwards (a spiral).
		for s in 5:
			var r0 := 0.08 + 0.1 * float(s)
			var r1 := r0 + 0.07
			var turn := base + 38.0 * float(s)
			var c := ARM_COLOR.lerp(CORE_COLOR, float(s) / 5.0)
			k.add_arc(r0, r1, 70.0, MeshKit.xf(Vector3(0.0, 0.012 + 0.002 * float(s), 0.0), Vector3(0.0, turn, 0.0)), c, 10)
	k.add_sphere(0.1, MeshKit.xf(Vector3(0.0, 0.02, 0.0), Vector3.ZERO, Vector3(1.0, 0.3, 1.0)), ARM_COLOR, 10, 4)
	return k.build()
