class_name ShamanTotemModel
extends Node3D
## Procedural look of a Shaman totem (M8): a carved wooden post (two stacked faces, a painted band, arms)
## on a stone plinth, crowned by its element – a flame (Fire), a water orb (Water), a ring of rocks
## (Earth), a wind ring with feathers (Air), a pale orb (Bond / Storm totems of the talents) – over a
## faint coloured disc on the ground, so each element reads from the top-down camera. Faces -Z.
##
## One cached body mesh per element (vertex colours, Mats.toon_vc), one cached crown mesh per element
## and the shared disc: 3 draws. Animation (the crown bobs and turns, the grow / shrink at the start
## and end of a totem's life) only moves / scales nodes – no per-node materials.

const HEIGHT := 1.55
const WOOD := Color(0.5, 0.33, 0.2)
const WOOD_DARK := Color(0.3, 0.19, 0.12)
const WOOD_LIGHT := Color(0.68, 0.5, 0.32)
const STONE := Color(0.5, 0.48, 0.45)
const BONE := Color(0.95, 0.9, 0.78)
const DISC_RADIUS := 0.62
const CROWN_Y := 1.3
const BOB_SPEED := 3.0
const SPIN_SPEED := 1.6

var element: StringName = &"fire"

var _crown: Node3D
var _grow := 1.0
var _time := 0.0


func _init() -> void:
	name = "TotemModel"


func _ready() -> void:
	if _crown == null:
		_build()


## Builds the look of [param p_element] (call before the model enters the tree).
func setup(p_element: StringName) -> void:
	element = p_element
	if _crown == null:
		_build()


## 0..1 grow factor of the whole model (the totem fades in and out by it).
func set_grow(k: float) -> void:
	_grow = clampf(k, 0.0, 1.0)
	scale = Vector3.ONE * maxf(_grow, 0.001)


func color() -> Color:
	return ShamanKit.ELEMENT_COLORS.get(element, ShamanKit.AIR_COLOR)


func _process(delta: float) -> void:
	_time += delta
	if _crown != null:
		_crown.position.y = sin(_time * BOB_SPEED) * 0.04
		_crown.rotation.y = _time * SPIN_SPEED


func _build() -> void:
	var tint := color()
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = MeshKit.cached("shaman:totem_body:" + String(element), func() -> Mesh: return body_mesh(element))
	body.material_override = Mats.toon_vc()
	add_child(body)
	_crown = Node3D.new()
	_crown.name = "Crown"
	_crown.position = Vector3(0.0, 0.0, 0.0)
	add_child(_crown)
	var crown := MeshInstance3D.new()
	crown.name = "CrownMesh"
	crown.mesh = MeshKit.cached("shaman:totem_crown:" + String(element), func() -> Mesh: return crown_mesh(element))
	crown.material_override = Mats.toon_vc() if element == &"earth" else Mats.glow(tint, 2.2)
	crown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_crown.add_child(crown)
	if element == &"fire":
		var core := MeshInstance3D.new()
		core.name = "FlameCore"
		core.mesh = MeshKit.cached("shaman:totem_flame_core", func() -> Mesh:
			var k := MeshKit.new()
			k.add_cylinder(0.0, 0.1, 0.34, MeshKit.xf(Vector3(0, CROWN_Y + 0.06, 0)), Color.WHITE, 8)
			return k.build())
		core.material_override = Mats.glow(Color(1.0, 0.92, 0.55), 2.6)
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_crown.add_child(core)
	var disc := MeshInstance3D.new()
	disc.name = "Disc"
	disc.mesh = MeshKit.cached("shaman:totem_disc", func() -> Mesh:
		var m := CylinderMesh.new()
		m.top_radius = DISC_RADIUS
		m.bottom_radius = DISC_RADIUS
		m.height = 0.03
		m.radial_segments = 28
		return m)
	# Alpha-blended (not additive): the element colour stays readable on the bright ice and snow arenas too.
	disc.material_override = Mats.unshaded(Color(tint.r, tint.g, tint.b, 0.5))
	disc.position.y = 0.04
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)


## The wooden post of [param p_element] with its painted band (vertex colours, no glow).
static func body_mesh(p_element: StringName) -> Mesh:
	var k := MeshKit.new()
	var tint: Color = ShamanKit.ELEMENT_COLORS.get(p_element, ShamanKit.AIR_COLOR)
	# Stone plinth.
	k.add_cylinder(0.3, 0.36, 0.16, MeshKit.xf(Vector3(0, 0.08, 0)), STONE, 10)
	k.add_cylinder(0.2, 0.26, 0.08, MeshKit.xf(Vector3(0, 0.2, 0)), STONE.darkened(0.1), 10)
	# The post and its two carved faces.
	k.add_cylinder(0.16, 0.2, 1.05, MeshKit.xf(Vector3(0, 0.75, 0)), WOOD, 9)
	for i in 2:
		var y := 0.52 + 0.42 * i
		k.add_box(Vector3(0.34, 0.3, 0.3), MeshKit.xf(Vector3(0, y, 0)), WOOD_LIGHT if i == 0 else WOOD)
		# Brow, eyes, mouth (dark carvings on the -Z face).
		k.add_box(Vector3(0.3, 0.05, 0.04), MeshKit.xf(Vector3(0, y + 0.08, -0.15)), WOOD_DARK)
		for side: float in [-1.0, 1.0]:
			k.add_box(Vector3(0.07, 0.07, 0.04), MeshKit.xf(Vector3(0.07 * side, y + 0.02, -0.155)), BONE)
			k.add_box(Vector3(0.03, 0.04, 0.045), MeshKit.xf(Vector3(0.07 * side, y + 0.02, -0.16)), WOOD_DARK)
		k.add_box(Vector3(0.14, 0.06, 0.04), MeshKit.xf(Vector3(0, y - 0.08, -0.155)), WOOD_DARK)
	# Painted element band and short arms.
	k.add_cylinder(0.215, 0.215, 0.09, MeshKit.xf(Vector3(0, 0.3, 0)), tint.darkened(0.15), 10)
	for side: float in [-1.0, 1.0]:
		k.add_box(Vector3(0.22, 0.07, 0.1), MeshKit.xf(Vector3(0.26 * side, 0.7, 0), Vector3(0, 0, -18.0 * side)), WOOD_DARK)
		k.add_sphere(0.05, MeshKit.xf(Vector3(0.36 * side, 0.64, 0)), BONE, 6, 3)
	# A bone bead hanging off each face.
	k.add_sphere(0.045, MeshKit.xf(Vector3(0, 0.37, -0.17)), BONE, 6, 3)
	return k.build()


## The crown of [param p_element]: a glow mesh (Earth: rocks in vertex colours).
static func crown_mesh(p_element: StringName) -> Mesh:
	var k := MeshKit.new()
	match p_element:
		&"fire":
			k.add_cylinder(0.0, 0.2, 0.52, MeshKit.xf(Vector3(0, CROWN_Y, 0)), Color.WHITE, 8)
			k.add_cylinder(0.0, 0.11, 0.38, MeshKit.xf(Vector3(0.1, CROWN_Y - 0.06, 0.04), Vector3(0, 0, -18)), Color.WHITE, 6)
			k.add_cylinder(0.0, 0.11, 0.34, MeshKit.xf(Vector3(-0.1, CROWN_Y - 0.08, -0.04), Vector3(0, 0, 18)), Color.WHITE, 6)
		&"water":
			k.add_sphere(0.21, MeshKit.xf(Vector3(0, CROWN_Y, 0), Vector3.ZERO, Vector3(1, 1.2, 1)), Color.WHITE, 12, 6)
			k.add_torus(0.19, 0.25, MeshKit.xf(Vector3(0, CROWN_Y - 0.12, 0)), Color.WHITE, 16, 5)
		&"earth":
			var rocks := [[Vector3(0.0, CROWN_Y, 0.0), 0.17], [Vector3(0.2, CROWN_Y - 0.1, 0.06), 0.11],
				[Vector3(-0.18, CROWN_Y - 0.08, -0.08), 0.12], [Vector3(0.04, CROWN_Y + 0.17, 0.02), 0.09]]
			var i := 0
			for r in rocks:
				var c := ShamanKit.EARTH_COLOR.lightened(0.12 * (i % 2)).darkened(0.08 * float(i == 2))
				k.add_sphere(float(r[1]), MeshKit.xf(r[0] as Vector3, Vector3(20.0 * i, 35.0 * i, 0), Vector3(1.0, 0.85, 1.1)), c, 6, 3)
				i += 1
		&"air":
			k.add_torus(0.2, 0.27, MeshKit.xf(Vector3(0, CROWN_Y, 0)), Color.WHITE, 18, 5)
			k.add_torus(0.1, 0.15, MeshKit.xf(Vector3(0, CROWN_Y + 0.2, 0)), Color.WHITE, 14, 5)
			for side: float in [-1.0, 1.0]:
				var feather := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.1 * side, 0.1), Vector2(0.3 * side, 0.2),
					Vector2(0.2 * side, 0.05), Vector2(0.12 * side, -0.04)])
				k.add_extrusion(feather, 0.02, MeshKit.xf(Vector3(0.1 * side, CROWN_Y + 0.02, 0)), Color.WHITE)
		_:
			k.add_sphere(0.19, MeshKit.xf(Vector3(0, CROWN_Y, 0)), Color.WHITE, 12, 6)
			k.add_torus(0.2, 0.26, MeshKit.xf(Vector3(0, CROWN_Y, 0), Vector3(55, 0, 0)), Color.WHITE, 16, 5)
	return k.build()
