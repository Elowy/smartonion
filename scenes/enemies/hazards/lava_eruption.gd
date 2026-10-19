class_name LavaEruption
extends ArenaHazard
## One eruption of a Volcano lava vent (GDD 16.1): an orange circle (radius 2) fills up over the
## telegraph time (1 s) around the vent, then a pillar of fire bursts out – EVERY hero AND every enemy
## inside takes [member damage] (1.5x the Skeleton Grunt's contact damage at the wave). The vents
## themselves are fixed dressing of the arena (the volcano decor set, at
## EnvironmentHazards.LAVA_VENT_POINTS); the director lays one of these on a vent every few seconds.

const FIRE := Color(1.0, 0.4, 0.08)
const EMBER := Color(1.0, 0.75, 0.25)

## Heroes / enemies the blast hurt (tests).
var hero_hits := 0
var enemy_hits := 0
var enemy_kills := 0

var _outline: MeshInstance3D
var _fill: MeshInstance3D
var _pillar: MeshInstance3D


static func spawn(parent: Node, pos: Vector3, p_radius: float, p_telegraph: float, p_damage: float,
		p_tally: EnvironmentHazards = null) -> LavaEruption:
	var h := LavaEruption.new()
	h.name = "LavaEruption"
	h.radius = p_radius
	h.telegraph_time = p_telegraph
	h.damage = p_damage
	h.color = FIRE
	h.tally = p_tally
	place(parent, h, pos)
	return h


func _build() -> void:
	_outline = _ring("Outline", radius * 2.0)
	_fill = _ring("Fill", radius * 2.0)
	Mats.set_ring(_outline, FIRE, 0.9, 0.985, 0.1)
	Mats.set_ring(_fill, EMBER, 0.96, 1.0, 0.4)
	_pillar = MeshInstance3D.new()
	_pillar.name = "Pillar"
	_pillar.mesh = MeshKit.cached("hazard:lava_pillar", func() -> Mesh:
		var k := MeshKit.new()
		k.add_cylinder(0.6, 1.0, 3.6, MeshKit.xf(Vector3(0.0, 1.8, 0.0)), Color.WHITE, 12, false)
		k.add_cylinder(0.0, 0.7, 4.6, MeshKit.xf(Vector3(0.0, 2.3, 0.0)), Color.WHITE, 10, false)
		return k.build())
	_pillar.material_override = Mats.glow(Color(1.0, 0.5, 0.12, 0.8), 2.2)
	_pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pillar.visible = false
	add_child(_pillar)


func _update_telegraph(progress: float) -> void:
	if _outline == null:
		return
	var pulse := 0.75 + 0.25 * sin(age * (6.0 + 14.0 * progress))
	Mats.set_ring(_outline, Color(FIRE.r, FIRE.g, FIRE.b, pulse), 0.9, 0.985, 0.08 + 0.1 * progress)
	var d := maxf(0.05, radius * 2.0 * progress)
	_fill.scale = Vector3(d, 1.0, d)


func _strike() -> void:
	for hero in heroes_in_circle():
		hero_hits += 1
		hit_hero(hero, damage)
	for e in enemies_in_circle():
		enemy_hits += 1
		if hit_enemy(e, damage):
			enemy_kills += 1
	var center := global_position + Vector3.UP * 0.2
	Vfx.explosion(center, radius * 1.1, FIRE)
	Vfx.explosion(center, radius * 0.6, EMBER)
	_fill.scale = Vector3(radius * 2.0, 1.0, radius * 2.0)
	_pillar.visible = true
	_pillar.scale = Vector3(radius / 2.0, 1.0, radius / 2.0)
	finish()


func fade_time() -> float:
	return 0.6


func _update_fade(amount: float) -> void:
	if _outline == null:
		return
	Mats.set_ring(_outline, Color(FIRE.r, FIRE.g, FIRE.b, amount), 0.9, 0.985, 0.1 * amount)
	Mats.set_ring(_fill, Color(1.0, 0.6, 0.25, amount), 0.96, 1.0, 0.45 * amount)
	var grow := radius / 2.0
	_pillar.scale = Vector3(grow * (0.4 + 0.6 * amount), maxf(0.05, amount), grow * (0.4 + 0.6 * amount))
	_pillar.visible = amount > 0.05
