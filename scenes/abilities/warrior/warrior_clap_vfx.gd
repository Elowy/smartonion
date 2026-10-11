class_name WarriorClapVfx
extends WarriorFx
## Thunder Clap: a pale blue shock wave races out to the clap's radius over a flash disc, with
## ground cracks radiating from the hero and a thin outer rim marking the reach. Echoes
## (Aftershock) are fainter. Parented to the arena's effect root; frees itself.

const LIFE := 0.5
const CRACKS := 8
const WAVE_COLOR := Color(0.62, 0.82, 1.0, 0.75)
const FLASH_COLOR := Color(0.85, 0.93, 1.0, 0.45)
const CRACK_COLOR := Color(0.3, 0.26, 0.22, 0.6)
const RIM_COLOR := Color(0.75, 0.88, 1.0, 0.35)
const GROUND_Y := 0.05

var radius := 3.5
## Echo claps (Aftershock) are drawn fainter and without new cracks.
var echo := false

var _wave: MeshInstance3D
var _flash: MeshInstance3D


static func spawn(center: Vector3, p_radius: float, p_echo: bool = false) -> WarriorClapVfx:
	var parent := Vfx.effect_parent()
	if parent == null:
		return null
	var fx := WarriorClapVfx.new()
	fx.name = "ThunderClap"
	fx.radius = maxf(0.5, p_radius)
	fx.echo = p_echo
	fx.life = LIFE
	fx.fade_in = 0.03
	fx.fade_out = 0.25
	parent.add_child(fx)
	fx.global_position = Vector3(center.x, GROUND_Y, center.z)
	return fx


func _ready() -> void:
	var strength := 0.6 if echo else 1.0
	_flash = add_part(disc_mesh(), Color(FLASH_COLOR.r, FLASH_COLOR.g, FLASH_COLOR.b, FLASH_COLOR.a * strength))
	_flash.scale = Vector3(radius * 0.5, 1.0, radius * 0.5)
	_wave = add_part(ring_mesh(0.82), Color(WAVE_COLOR.r, WAVE_COLOR.g, WAVE_COLOR.b, WAVE_COLOR.a * strength))
	_wave.position.y = 0.01
	var rim := add_part(ring_mesh(0.96, 64), Color(RIM_COLOR.r, RIM_COLOR.g, RIM_COLOR.b, RIM_COLOR.a * strength))
	rim.scale = Vector3(radius, 1.0, radius)
	if not echo:
		for i in CRACKS:
			var crack := add_part(crack_mesh(), CRACK_COLOR)
			# Fixed, even spread with a little zig-zag (no RNG: purely visual, deterministic).
			crack.rotation.y = TAU * float(i) / float(CRACKS) + (0.18 if i % 2 == 0 else -0.12)
			var length := radius * (0.55 if i % 2 == 0 else 0.4)
			crack.scale = Vector3(length, 1.0, length)
			crack.position.y = -0.005
	_animate(0.0)


func _animate(_delta: float) -> void:
	var t := progress()
	# The wave front eases out to the full radius in the first 70 % of the life.
	var reach := lerpf(0.25, 1.0, 1.0 - pow(1.0 - clampf(t / 0.7, 0.0, 1.0), 3.0)) * radius
	_wave.scale = Vector3(reach, 1.0, reach)
	var flash := 1.0 + t * 0.6
	_flash.scale = Vector3(radius * 0.5 * flash, 1.0, radius * 0.5 * flash)
	_flash.visible = t < 0.45
