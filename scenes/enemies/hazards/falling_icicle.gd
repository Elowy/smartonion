class_name FallingIcicle
extends ArenaHazard
## The Ice Cave's Falling Icicles (GDD 16.1): a deep blue circle (radius 1.2) appears near a hero and
## fills up for the telegraph time (1 s); in its last moments an icicle drops out of the ceiling and
## shatters – every hero inside takes [member damage] (1x the Skeleton Grunt's contact damage at the
## wave) and is chilled (movement -[member slow_pct] percent for [member slow_time] seconds, a
## GeneralBuff on the hero under [constant CHILL_KEY]).
##
## The marker is DARK on purpose: the ice floor is pale blue snow, and a pale blue ring on it measured
## 1.1:1 (nobody saw it). A deep blue band with a dark outline pass ([method Mats.set_ring_stroke]) and a
## darker, fairly opaque fill keeps [constant ArenaHazard.MIN_MARKER_CONTRAST] on every floor tone.

const CHILL_KEY := &"ice_chill"
## The shatter's burst and the pale flash after the impact (harmless by then).
const FROST := Color(0.6, 0.88, 1.0)
## The telegraph's ring (deep blue) and its fill (a lighter blue, but darker than the snow).
const MARKER := Color(0.03, 0.13, 0.52)
const FILL := Color(0.08, 0.28, 0.8)
## The ring band as a share of the circle's radius, and how much bigger its quad is than the circle, so
## that the dark outline pass just outside the band fits inside the quad (a quad is clipped at 1.0).
const BAND_INNER := 0.86
const BAND_OUTER := 0.985
const OUTLINE_PAD := 1.12
## The icicle starts to fall this long (s) before the impact, from FALL_HEIGHT metres.
const FALL_TIME := 0.5
const FALL_HEIGHT := 12.0

var slow_pct := 30.0
var slow_time := 1.5
## Heroes the icicle hit (tests).
var hits := 0

var _outline: MeshInstance3D
var _fill: MeshInstance3D
var _spike: MeshInstance3D


static func spawn(parent: Node, pos: Vector3, p_radius: float, p_telegraph: float, p_damage: float,
		p_slow_pct: float, p_slow_time: float, p_tally: EnvironmentHazards = null) -> FallingIcicle:
	var h := FallingIcicle.new()
	h.name = "FallingIcicle"
	h.radius = p_radius
	h.telegraph_time = p_telegraph
	h.damage = p_damage
	h.slow_pct = p_slow_pct
	h.slow_time = p_slow_time
	h.color = MARKER
	h.tally = p_tally
	place(parent, h, pos)
	return h


func _build() -> void:
	_outline = _ring("Outline", radius * 2.0 * OUTLINE_PAD)
	_fill = _ring("Fill", radius * 2.0)
	_set_outline(1.0, 0.12, 1.0)
	Mats.set_ring(_fill, FILL, 0.96, 1.0, 0.5)
	_spike = MeshInstance3D.new()
	_spike.name = "Icicle"
	_spike.mesh = MeshKit.cached("hazard:icicle", func() -> Mesh:
		var k := MeshKit.new()
		# Point down: a cone (top radius 0 points up), so it is turned over.
		k.add_cylinder(0.34, 0.0, 1.7, MeshKit.xf(Vector3(0.0, 0.0, 0.0), Vector3(180, 0, 0)), Color(0.8, 0.94, 1.0), 6)
		k.add_cylinder(0.2, 0.0, 1.1, MeshKit.xf(Vector3(0.28, 0.35, 0.1), Vector3(180, 0, 12)), Color(0.62, 0.84, 0.98), 5)
		k.add_cylinder(0.16, 0.0, 0.9, MeshKit.xf(Vector3(-0.24, 0.45, -0.12), Vector3(180, 0, -10)), Color(0.7, 0.9, 1.0), 5)
		return k.build())
	_spike.material_override = Mats.toon_vc_glow(Color(0.5, 0.8, 1.0), 0.6)
	_spike.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spike.visible = false
	add_child(_spike)


func _update_telegraph(progress: float) -> void:
	if _outline == null:
		return
	# (The band pulses between 76% and 100% opaque only: at the half of the other hazards' pulse it washed
	# out on the snow.)
	var pulse := 0.88 + 0.12 * sin(age * (6.0 + 14.0 * progress))
	_set_outline(pulse, 0.12 + 0.1 * progress, 1.0)
	var d := maxf(0.05, radius * 2.0 * progress)
	_fill.scale = Vector3(d, 1.0, d)
	var left := telegraph_time - age
	if left <= FALL_TIME:
		var t := 1.0 - left / FALL_TIME
		_spike.visible = true
		_spike.position = Vector3(0.0, lerpf(FALL_HEIGHT, 0.85, t * t), 0.0)


func _strike() -> void:
	for hero in heroes_in_circle():
		hits += 1
		hit_hero(hero, damage)
		if slow_pct > 0.0 and slow_time > 0.0 and Enemy.is_living_player(hero):
			GeneralBuff.apply(hero, CHILL_KEY, slow_time, {Stats.SPEED: -slow_pct})
	Vfx.explosion(global_position + Vector3.UP * 0.1, radius, FROST)
	_fill.scale = Vector3(radius * 2.0, 1.0, radius * 2.0)
	_spike.visible = true
	_spike.position = Vector3(0.0, 0.85, 0.0)
	finish()


func fade_time() -> float:
	return 0.7


func _update_fade(amount: float) -> void:
	if _outline == null:
		return
	_set_outline(amount, 0.1 * amount, amount)
	Mats.set_ring(_fill, Color(0.85, 0.96, 1.0, amount), 0.96, 1.0, 0.4 * amount)
	# The spike stays stuck a while, then sinks.
	_spike.position.y = lerpf(-0.9, 0.85, clampf(amount * 1.6, 0.0, 1.0))


## The outline ring: the deep blue band of [param alpha] with a faint blue tint inside it
## ([param tint]) and the dark outline / white inner stroke at [param stroke] (0..1).
func _set_outline(alpha: float, tint: float, stroke: float) -> void:
	Mats.set_ring(_outline, Color(MARKER.r, MARKER.g, MARKER.b, alpha), BAND_INNER / OUTLINE_PAD,
			BAND_OUTER / OUTLINE_PAD, tint)
	Mats.set_ring_stroke(_outline, stroke)
