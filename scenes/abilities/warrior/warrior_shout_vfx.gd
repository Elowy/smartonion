class_name WarriorShoutVfx
extends WarriorFx
## Battle Shout looks: the shout (three red-gold sound waves rushing out from the hero to the
## shout's reach) and the buff mark (a slowly turning ring of chevrons under every hero that
## has the buff; held until the buff ends). Purely visual.

enum Mode { WAVE, MARK }

const WAVE_LIFE := 0.7
const WAVES := 3
const WAVE_COLOR := Color(1.0, 0.45, 0.2, 0.6)
const MARK_COLOR := Color(1.0, 0.35, 0.2, 0.55)
## Commanding Shout (damage taken down) marks are steel blue.
const GUARD_COLOR := Color(0.55, 0.75, 1.0, 0.55)
const MARK_RADIUS := 0.85
const CHEVRONS := 6
const MARK_TURNS := 0.25
const GROUND_Y := 0.06

var mode := Mode.WAVE
var radius := 8.0
var tint := WAVE_COLOR

var _waves: Array[MeshInstance3D] = []
var _spin: Node3D


## The shout itself, centred on [param center], reaching [param p_radius] metres.
static func spawn_wave(center: Vector3, p_radius: float, p_tint: Color = WAVE_COLOR) -> WarriorShoutVfx:
	var parent := Vfx.effect_parent()
	if parent == null:
		return null
	var fx := WarriorShoutVfx.new()
	fx.name = "BattleShout"
	fx.mode = Mode.WAVE
	fx.radius = maxf(1.0, p_radius)
	fx.tint = p_tint
	fx.life = WAVE_LIFE
	fx.fade_in = 0.02
	fx.fade_out = 0.3
	parent.add_child(fx)
	fx.global_position = Vector3(center.x, GROUND_Y, center.z)
	return fx


## A buff mark under [param hero] (its child; [method WarriorFx.dismiss] it when the buff ends).
static func spawn_mark(hero: Node3D, p_tint: Color = MARK_COLOR) -> WarriorShoutVfx:
	if hero == null or not hero.is_inside_tree():
		return null
	var fx := WarriorShoutVfx.new()
	fx.name = "BattleShoutMark"
	fx.mode = Mode.MARK
	fx.tint = p_tint
	fx.life = 0.0
	fx.fade_in = 0.2
	fx.fade_out = 0.3
	hero.add_child(fx)
	fx.position = Vector3(0.0, GROUND_Y, 0.0)
	return fx


## A chevron (arrow head pointing outwards, +Z = outwards after placement) of two thin bars.
static func chevron_mesh() -> Mesh:
	return MeshKit.cached("warrior:chevron", func() -> Mesh:
		var k := MeshKit.new()
		k.add_box(Vector3(0.06, 0.02, 0.26), MeshKit.xf(Vector3(-0.07, 0.0, 0.0), Vector3(0.0, 35.0, 0.0)), Color.WHITE)
		k.add_box(Vector3(0.06, 0.02, 0.26), MeshKit.xf(Vector3(0.07, 0.0, 0.0), Vector3(0.0, -35.0, 0.0)), Color.WHITE)
		return k.build())


func _ready() -> void:
	if mode == Mode.WAVE:
		for i in WAVES:
			var w := add_part(ring_mesh(0.9, 64), tint)
			w.position.y = 0.005 * float(i)
			_waves.append(w)
	else:
		_spin = Node3D.new()
		_spin.name = "Spin"
		add_child(_spin)
		var ring := add_part(ring_mesh(0.9), Color(tint.r, tint.g, tint.b, tint.a * 0.6))
		ring.scale = Vector3(MARK_RADIUS, 1.0, MARK_RADIUS)
		for i in CHEVRONS:
			var yaw := TAU * float(i) / float(CHEVRONS)
			var c := add_part(chevron_mesh(), tint, _spin)
			var out := Vector3(sin(yaw), 0.0, cos(yaw))
			c.position = out * (MARK_RADIUS + 0.14)
			c.rotation.y = yaw + PI
	_animate(0.0)


func _animate(delta: float) -> void:
	if mode == Mode.WAVE:
		var t := progress()
		for i in _waves.size():
			# Staggered waves: each starts 0.12 of the life after the previous one.
			var local := clampf((t - 0.12 * float(i)) / 0.7, 0.0, 1.0)
			var r := lerpf(0.4, 1.0, 1.0 - pow(1.0 - local, 2.0)) * radius
			_waves[i].scale = Vector3(r, 1.0, r)
			_waves[i].visible = local > 0.0 and local < 1.0
	elif _spin != null:
		_spin.rotation.y += delta * TAU * MARK_TURNS
