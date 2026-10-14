class_name FrostCircle
extends EnemyHazard
## Morvain's Frost Circles (GDD 8): an ice circle that appears under a hero, fills up for the
## telegraph time (1.2 s) and then bursts – every hero inside takes [member damage] and is
## chilled (movement slowed by [member slow_pct] percent for [member slow_time] seconds, a
## GeneralBuff on the hero under [constant CHILL_KEY]). "Do not stand in it."

const CHILL_KEY := &"boss_chill"
const FROST := Color(0.5, 0.85, 1.0)

## The chill the burst puts on the heroes it hits (percent, seconds).
var slow_pct := 40.0
var slow_time := 2.0
## Heroes the burst hit (tests).
var hits := 0

var _outline: MeshInstance3D
var _fill: MeshInstance3D


## A circle of [param p_radius] at [param pos] under [param parent], striking after
## [param p_telegraph] seconds for [param p_damage] (+ the chill).
static func spawn(parent: Node, pos: Vector3, p_radius: float, p_telegraph: float, p_damage: float,
		p_slow_pct: float, p_slow_time: float, p_source: Node3D = null) -> FrostCircle:
	var h := FrostCircle.new()
	h.name = "FrostCircle"
	h.radius = p_radius
	h.telegraph_time = p_telegraph
	h.damage = p_damage
	h.slow_pct = p_slow_pct
	h.slow_time = p_slow_time
	h.source = p_source
	h.color = FROST
	place(parent, h, pos)
	return h


func _build() -> void:
	_outline = _ring("Outline", radius * 2.0)
	_fill = _ring("Fill", radius * 2.0)
	Mats.set_ring(_outline, FROST, 0.9, 0.985, 0.12)
	Mats.set_ring(_fill, FROST.lerp(Color.WHITE, 0.35), 0.96, 1.0, 0.4)


func _update_telegraph(progress: float) -> void:
	if _outline == null:
		return
	var pulse := 0.75 + 0.25 * sin(age * (6.0 + 14.0 * progress))
	Mats.set_ring(_outline, Color(FROST.r, FROST.g, FROST.b, pulse), 0.9, 0.985, 0.1 + 0.1 * progress)
	var d := maxf(0.05, radius * 2.0 * progress)
	_fill.scale = Vector3(d, 1.0, d)


func _strike() -> void:
	for hero in heroes_in_circle():
		hits += 1
		hit_hero(hero, damage)
		if slow_pct > 0.0 and slow_time > 0.0 and Enemy.is_living_player(hero):
			GeneralBuff.apply(hero, CHILL_KEY, slow_time, {Stats.SPEED: -slow_pct})
	Vfx.explosion(global_position + Vector3.UP * 0.1, radius, FROST)
	_fill.scale = Vector3(radius * 2.0, 1.0, radius * 2.0)
	finish()


func _update_fade(amount: float) -> void:
	if _outline == null:
		return
	Mats.set_ring(_outline, Color(FROST.r, FROST.g, FROST.b, amount), 0.9, 0.985, 0.1 * amount)
	Mats.set_ring(_fill, Color(0.9, 0.97, 1.0, amount), 0.96, 1.0, 0.4 * amount)
