class_name WarriorLeapVfx
extends WarriorFx
## Heroic Leap looks: the landing marker (an orange ring closing in on the landing spot while
## the hero is in the air) and the impact (a dust shock wave, a warm flash and ground cracks
## radiating from the crater). Parented to the arena's effect root; frees itself.

enum Mode { MARKER, IMPACT }

const IMPACT_LIFE := 0.6
const CRACKS := 10
const MARKER_COLOR := Color(1.0, 0.55, 0.2, 0.7)
const DUST_COLOR := Color(0.78, 0.66, 0.48, 0.8)
const FLASH_COLOR := Color(1.0, 0.8, 0.45, 0.5)
const CRACK_COLOR := Color(0.28, 0.2, 0.14, 0.85)
const GROUND_Y := 0.05

var mode := Mode.IMPACT
var radius := 3.0

var _ring: MeshInstance3D
var _flash: MeshInstance3D


## The landing marker: shows where the hero comes down in [param seconds].
static func spawn_marker(center: Vector3, p_radius: float, seconds: float) -> WarriorLeapVfx:
	return _spawn(Mode.MARKER, center, p_radius, maxf(0.1, seconds))


## The impact at [param center] for an area of [param p_radius].
static func spawn_impact(center: Vector3, p_radius: float) -> WarriorLeapVfx:
	return _spawn(Mode.IMPACT, center, p_radius, IMPACT_LIFE)


static func _spawn(p_mode: Mode, center: Vector3, p_radius: float, p_life: float) -> WarriorLeapVfx:
	var parent := Vfx.effect_parent()
	if parent == null:
		return null
	var fx := WarriorLeapVfx.new()
	fx.name = "LeapMarker" if p_mode == Mode.MARKER else "LeapImpact"
	fx.mode = p_mode
	fx.radius = maxf(0.5, p_radius)
	fx.life = p_life
	fx.fade_in = 0.08 if p_mode == Mode.MARKER else 0.02
	fx.fade_out = 0.05 if p_mode == Mode.MARKER else 0.3
	parent.add_child(fx)
	fx.global_position = Vector3(center.x, GROUND_Y, center.z)
	return fx


func _ready() -> void:
	if mode == Mode.MARKER:
		_ring = add_part(ring_mesh(0.88), MARKER_COLOR)
		var inner := add_part(disc_mesh(), Color(MARKER_COLOR.r, MARKER_COLOR.g, MARKER_COLOR.b, 0.15))
		inner.scale = Vector3(radius, 1.0, radius)
	else:
		_flash = add_part(disc_mesh(), FLASH_COLOR)
		_ring = add_part(ring_mesh(0.7), DUST_COLOR)
		_ring.position.y = 0.01
		for i in CRACKS:
			var crack := add_part(crack_mesh(), CRACK_COLOR)
			crack.rotation.y = TAU * float(i) / float(CRACKS) + (0.2 if i % 3 == 0 else -0.1)
			var length := radius * (0.75 if i % 2 == 0 else 0.5)
			crack.scale = Vector3(length * 1.6, 1.0, length)
			crack.position.y = -0.005
	_animate(0.0)


func _animate(_delta: float) -> void:
	var t := progress()
	if mode == Mode.MARKER:
		# Closes in from 1.6x the radius to the radius as the hero comes down.
		var s := lerpf(1.6, 1.0, t) * radius
		_ring.scale = Vector3(s, 1.0, s)
	else:
		var reach := lerpf(0.3, 1.1, 1.0 - pow(1.0 - clampf(t / 0.6, 0.0, 1.0), 3.0)) * radius
		_ring.scale = Vector3(reach, 1.0, reach)
		var f := radius * (0.6 + t * 0.5)
		_flash.scale = Vector3(f, 1.0, f)
		_flash.visible = t < 0.4
