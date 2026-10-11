class_name WarriorShieldWallVfx
extends WarriorFx
## Shield Wall: a translucent steel-blue dome over the hero with a bright rim on the ground and
## four tower shields slowly circling it (spiked and red-tinged with Spiked Wall, golden with
## Last Stand). Child of the hero; held until [method WarriorFx.dismiss] when the wall ends.

const DOME_RADIUS := 1.05
const DOME_COLOR := Color(0.55, 0.72, 1.0, 0.22)
const RIM_COLOR := Color(0.7, 0.85, 1.0, 0.6)
const SHIELD_COLOR := Color(0.75, 0.82, 0.95, 0.85)
const SPIKED_COLOR := Color(1.0, 0.55, 0.45, 0.85)
const LAST_STAND_COLOR := Color(1.0, 0.85, 0.4, 0.85)
const SHIELDS := 4
const SHIELD_ORBIT := 1.05
const SHIELD_SCALE := 1.35
const TURNS_PER_SECOND := 0.3
const GROUND_Y := 0.05

enum Style { PLAIN, SPIKED, LAST_STAND }

var style := Style.PLAIN

var _orbit: Node3D
var _dome: MeshInstance3D


static func spawn(hero: Node3D, p_style: Style = Style.PLAIN) -> WarriorShieldWallVfx:
	if hero == null or not hero.is_inside_tree():
		return null
	var fx := WarriorShieldWallVfx.new()
	fx.name = "ShieldWall"
	fx.style = p_style
	fx.life = 0.0
	fx.fade_in = 0.12
	fx.fade_out = 0.3
	hero.add_child(fx)
	fx.position = Vector3(0.0, GROUND_Y, 0.0)
	return fx


## A heater-style tower shield standing on the ground, face towards +Z, vertex coloured.
static func shield_mesh(spiked: bool) -> Mesh:
	return MeshKit.cached("warrior:wall_shield:%s" % spiked, func() -> Mesh:
		var k := MeshKit.new()
		var face := Color(0.85, 0.88, 0.95)
		var trim := Color(0.95, 0.78, 0.35)
		k.add_box(Vector3(0.5, 0.62, 0.06), MeshKit.xf(Vector3(0.0, 0.55, 0.0)), face)
		k.add_cylinder(0.0, 0.25, 0.3, MeshKit.xf(Vector3(0.0, 0.1, 0.0), Vector3(180.0, 45.0, 0.0), Vector3(1.0, 1.0, 0.24)), face, 4)
		k.add_box(Vector3(0.56, 0.06, 0.08), MeshKit.xf(Vector3(0.0, 0.87, 0.0)), trim)
		k.add_box(Vector3(0.07, 0.58, 0.08), MeshKit.xf(Vector3(0.0, 0.55, 0.01)), trim)
		if spiked:
			for i in 3:
				var x := -0.17 + 0.17 * float(i)
				k.add_cylinder(0.0, 0.05, 0.22, MeshKit.xf(Vector3(x, 0.6, 0.12), Vector3(90.0, 0.0, 0.0)), Color(0.9, 0.9, 0.95), 6)
		return k.build())


func _ready() -> void:
	var tint := SHIELD_COLOR
	match style:
		Style.SPIKED:
			tint = SPIKED_COLOR
		Style.LAST_STAND:
			tint = LAST_STAND_COLOR
	var dome_mesh := MeshKit.cached("warrior:wall_dome", func() -> Mesh:
		return MeshKit.new().add_sphere(1.0, Transform3D.IDENTITY, Color.WHITE, 24, 8, true).build())
	_dome = add_part(dome_mesh, Color(tint.r, tint.g, tint.b, DOME_COLOR.a).lerp(DOME_COLOR, 0.5))
	_dome.scale = Vector3(DOME_RADIUS, DOME_RADIUS * 1.25, DOME_RADIUS)
	var rim := add_part(ring_mesh(0.9), RIM_COLOR)
	rim.scale = Vector3(DOME_RADIUS + 0.1, 1.0, DOME_RADIUS + 0.1)
	_orbit = Node3D.new()
	_orbit.name = "Orbit"
	add_child(_orbit)
	var mesh := shield_mesh(style == Style.SPIKED)
	for i in SHIELDS:
		var yaw := TAU * float(i) / float(SHIELDS) + PI / float(SHIELDS)
		var s := add_part(mesh, tint, _orbit, true)
		s.position = Vector3(sin(yaw), 0.0, cos(yaw)) * SHIELD_ORBIT
		s.rotation.y = yaw
		s.scale = Vector3.ONE * SHIELD_SCALE
	_animate(0.0)


func _animate(delta: float) -> void:
	_orbit.rotation.y += delta * TAU * TURNS_PER_SECOND
	var pulse := 1.0 + 0.04 * sin(age * 5.0)
	_dome.scale = Vector3(DOME_RADIUS * pulse, DOME_RADIUS * 1.25 * pulse, DOME_RADIUS * pulse)
