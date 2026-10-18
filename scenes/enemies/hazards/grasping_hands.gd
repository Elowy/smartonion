class_name GraspingHands
extends ArenaHazard
## The Cemetery's Grasping Hands (GDD 16.1): a pale circle (radius 1.5) appears under a hero, fills up
## for the telegraph time (1 s) and then bony hands claw out of the ground – every hero inside takes
## [member damage] (0.5x the Skeleton Grunt's contact damage at the wave) and is ROOTED for
## [member root_time] seconds (Player.apply_root: no walking, attacks and spells still work). The hands
## stay up while the root lasts, then sink back. "Do not stand in it."

const BONE := Color(0.78, 0.7, 0.95)
const BONE_MESH := Color(0.9, 0.86, 0.74)
## Seconds the hands take to rise out of the ground.
const RISE_TIME := 0.18

## Seconds a hit hero cannot walk.
var root_time := 1.2
## Heroes the hands grabbed (tests).
var hits := 0

var _hold := 0.0
var _outline: MeshInstance3D
var _fill: MeshInstance3D
var _hands: MeshInstance3D


## A circle of [param p_radius] at [param pos] under [param parent], grabbing after [param p_telegraph]
## seconds for [param p_damage] and [param p_root] seconds of root.
static func spawn(parent: Node, pos: Vector3, p_radius: float, p_telegraph: float, p_damage: float,
		p_root: float, p_tally: EnvironmentHazards = null) -> GraspingHands:
	var h := GraspingHands.new()
	h.name = "GraspingHands"
	h.radius = p_radius
	h.telegraph_time = p_telegraph
	h.damage = p_damage
	h.root_time = p_root
	h.color = BONE
	h.tally = p_tally
	place(parent, h, pos)
	return h


## Dangerous only until the hands closed: once they struck, a hero walking in is not hurt again.
func is_dangerous() -> bool:
	return stage == Stage.TELEGRAPH


func _build() -> void:
	_outline = _ring("Outline", radius * 2.0)
	_fill = _ring("Fill", radius * 2.0)
	Mats.set_ring(_outline, BONE, 0.9, 0.985, 0.12)
	Mats.set_ring(_fill, BONE.lerp(Color.WHITE, 0.3), 0.96, 1.0, 0.4)
	_hands = MeshInstance3D.new()
	_hands.name = "Hands"
	_hands.mesh = MeshKit.cached("hazard:hands", _build_hands_mesh)
	_hands.material_override = Mats.toon_vc(true)
	_hands.scale = Vector3(radius / 1.5, 0.01, radius / 1.5)
	_hands.visible = false
	add_child(_hands)


## Seven skeletal hands reaching up inside a circle of radius 1.5 (centre one first).
static func _build_hands_mesh() -> Mesh:
	var k := MeshKit.new()
	var spots: Array[Vector3] = [Vector3(0.0, 0.0, 0.0)]
	for i in 6:
		var a := TAU * float(i) / 6.0 + 0.3
		spots.append(Vector3(sin(a), 0.0, cos(a)) * 1.0)
	for i in spots.size():
		var base := spots[i]
		var lean := Vector3(sin(float(i) * 2.1), 0.0, cos(float(i) * 1.7)) * 0.16
		var wrist := base + Vector3(0.0, 0.62, 0.0) + lean
		k.add_segment(base - Vector3(0.0, 0.05, 0.0), wrist, 0.09, 0.07, BONE_MESH.darkened(0.12), 6)
		k.add_sphere(0.1, MeshKit.xf(wrist + Vector3(0.0, 0.06, 0.0), Vector3.ZERO, Vector3(1.3, 0.7, 1.0)), BONE_MESH, 7, 4)
		for f in 4:
			var fa := (float(f) - 1.5) * 0.28 + float(i)
			var knuckle := wrist + Vector3(sin(fa) * 0.11, 0.1, cos(fa) * 0.11)
			var mid := knuckle + Vector3(sin(fa) * 0.07, 0.15, cos(fa) * 0.07)
			var tip := mid + Vector3(sin(fa) * 0.12, 0.07, cos(fa) * 0.12)
			k.add_segment(knuckle, mid, 0.034, 0.028, BONE_MESH, 5)
			k.add_segment(mid, tip, 0.028, 0.012, BONE_MESH.darkened(0.06), 5)
	return k.build()


func _update_telegraph(progress: float) -> void:
	if _outline == null:
		return
	var pulse := 0.75 + 0.25 * sin(age * (6.0 + 14.0 * progress))
	Mats.set_ring(_outline, Color(BONE.r, BONE.g, BONE.b, pulse), 0.9, 0.985, 0.1 + 0.1 * progress)
	var d := maxf(0.05, radius * 2.0 * progress)
	_fill.scale = Vector3(d, 1.0, d)


func _strike() -> void:
	for hero in heroes_in_circle():
		hits += 1
		hit_hero(hero, damage)
		if Enemy.is_living_player(hero):
			hero.apply_root(root_time)
	_hold = 0.0
	_fill.scale = Vector3(radius * 2.0, 1.0, radius * 2.0)
	_hands.visible = true
	Vfx.hit_spark(global_position + Vector3.UP * 0.2, BONE)


func _update_active(delta: float) -> void:
	_hold += delta
	var rise := clampf(_hold / RISE_TIME, 0.0, 1.0)
	var sink := clampf((root_time - _hold) / 0.25, 0.0, 1.0)
	var s := radius / 1.5
	_hands.scale = Vector3(s, maxf(0.01, rise * sink), s)
	Mats.set_ring(_fill, Color(0.9, 0.85, 1.0, 0.5 * sink), 0.96, 1.0, 0.35 * sink)
	if _hold >= root_time:
		finish()


func _update_fade(amount: float) -> void:
	if _outline == null:
		return
	_hands.visible = false
	Mats.set_ring(_outline, Color(BONE.r, BONE.g, BONE.b, amount * 0.6), 0.9, 0.985, 0.05 * amount)
	Mats.set_ring(_fill, Color(0.9, 0.85, 1.0, 0.0), 0.96, 1.0, 0.0)


func fade_time() -> float:
	return 0.25
