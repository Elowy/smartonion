class_name MeteorStrike
extends EnemyHazard
## Vor'thalax's Meteor (GDD 8): a marked circle (radius 3) on a hero that fills up for 3 s and
## then takes a meteor. The impact's damage is [member damage] IN TOTAL (8x the boss's contact
## damage) and is SHARED EQUALLY among the heroes standing inside – the more who stand in it,
## the less each takes (the co-op mechanic). When nobody stands inside, every living hero takes
## [member fallback_damage] instead (4x contact), so hiding from it altogether is not free.
## Bots with a team stack in the circle ([method hazard_push] pulls them in); a lone hero
## steps out (4x instead of 8x).

const FIRE := Color(1.0, 0.28, 0.1)
const ROCK := Color(0.25, 0.1, 0.06)
## The meteor itself starts to fall this long (s) before the impact.
const FALL_TIME := 1.1
const FALL_HEIGHT := 16.0

## What every living hero takes when nobody is inside.
var fallback_damage := 0.0
## Heroes inside at the impact and the damage each took (tests).
var inside_count := 0
var damage_each := 0.0
var struck := false

var _outline: MeshInstance3D
var _fill: MeshInstance3D
var _ball: MeshInstance3D


## A meteor marker of [param p_radius] at [param pos]; [param p_total_damage] is split among
## the heroes inside, [param p_fallback_damage] hits everybody when nobody is.
static func spawn(parent: Node, pos: Vector3, p_radius: float, p_telegraph: float,
		p_total_damage: float, p_fallback_damage: float, p_source: Node3D = null) -> MeteorStrike:
	var h := MeteorStrike.new()
	h.name = "MeteorStrike"
	h.radius = p_radius
	h.telegraph_time = p_telegraph
	h.damage = p_total_damage
	h.fallback_damage = p_fallback_damage
	h.source = p_source
	h.color = FIRE
	place(parent, h, pos)
	return h


## Bots in a team gather in the circle (the damage is shared); a lone hero (or the last one
## standing) steps out like from any circle.
func hazard_push(from: Vector3, margin: float = BOT_MARGIN) -> Vector2:
	if not is_dangerous():
		return Vector2.ZERO
	if living_heroes().size() < 2:
		return super(from, margin)
	var to := Vector2(global_position.x - from.x, global_position.z - from.z)
	if to.length() <= radius * 0.6:
		return Vector2.ZERO
	return to.normalized() * 3.0


func _build() -> void:
	_outline = _ring("Outline", radius * 2.0)
	_fill = _ring("Fill", radius * 2.0)
	Mats.set_ring(_outline, FIRE, 0.9, 0.985, 0.12)
	Mats.set_ring(_fill, FIRE.lerp(Color.WHITE, 0.25), 0.96, 1.0, 0.45)
	_ball = MeshInstance3D.new()
	_ball.name = "Meteor"
	_ball.mesh = MeshKit.cached("hazard:meteor", func() -> Mesh:
		var k := MeshKit.new()
		k.add_sphere(0.9, Transform3D(), Color.WHITE, 12, 6)
		k.add_sphere(0.55, MeshKit.xf(Vector3(0.5, 0.45, 0.2)), Color.WHITE, 8, 4)
		return k.build())
	_ball.material_override = Mats.glow(Color(1.0, 0.5, 0.12), 2.4)
	_ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ball.visible = false
	add_child(_ball)


func _update_telegraph(progress: float) -> void:
	if _outline == null:
		return
	var pulse := 0.75 + 0.25 * sin(age * (5.0 + 16.0 * progress))
	Mats.set_ring(_outline, Color(FIRE.r, FIRE.g, FIRE.b, pulse), 0.9, 0.985, 0.1 + 0.12 * progress)
	var d := maxf(0.05, radius * 2.0 * progress)
	_fill.scale = Vector3(d, 1.0, d)
	var left := telegraph_time - age
	if left <= FALL_TIME:
		var t := 1.0 - left / FALL_TIME
		_ball.visible = true
		_ball.position = Vector3(0.0, lerpf(FALL_HEIGHT, 0.7, t * t), 0.0)
		_ball.rotation.y = age * 4.0


func _strike() -> void:
	struck = true
	var inside := heroes_in_circle()
	inside_count = inside.size()
	if inside_count > 0:
		damage_each = damage / float(inside_count)
		for hero in inside:
			hit_hero(hero, damage_each)
	else:
		damage_each = fallback_damage
		for hero in living_heroes():
			hit_hero(hero, fallback_damage)
	var center := global_position + Vector3.UP * 0.2
	Vfx.explosion(center, radius * 1.1, FIRE)
	Vfx.explosion(center, radius * 0.6, Color(1.0, 0.8, 0.3))
	_ball.visible = false
	_fill.scale = Vector3(radius * 2.0, 1.0, radius * 2.0)
	finish()


func _update_fade(amount: float) -> void:
	if _outline == null:
		return
	Mats.set_ring(_outline, Color(FIRE.r, FIRE.g, FIRE.b, amount), 0.9, 0.985, 0.12 * amount)
	Mats.set_ring(_fill, Color(1.0, 0.6, 0.25, amount), 0.96, 1.0, 0.45 * amount)
