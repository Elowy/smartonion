class_name WarlockImpBolt
extends Projectile
## The Imp's firebolt: a regular player [Projectile] (flight, swept hits, EnemyGrid) whose hits
## are PET damage instead of weapon hits – ProcSystem.deal_raw(..., &"pet") on the Warlock
## (kill credit, damage meter, Demonic Pact; no on-hit procs, leech or resource gains, no
## crits, no knockback). With [member pierce] > 0 (Grimoire of the Imp Lord: 2 targets) a hit
## ricochets towards the nearest enemy it has not hit yet (within [constant RICOCHET_RANGE]),
## else flies on.

const COLOR := Color(1.0, 0.45, 0.1)
## Metres a ricochet looks for its next target around the enemy just hit.
const RICOCHET_RANGE := 5.0

## Instance ids of the enemies damaged by this bolt, in order (tests).
var victim_ids: Array[int] = []


## Fires a bolt from [param from] (world, its height is kept) along [param dir] for
## [param warlock]. [param targets] = enemies it may hit (1 = no pierce). Added under the
## arena's entities (or next to the Warlock).
static func fire(warlock: Player, from: Vector3, dir: Vector3, p_damage: float, targets: int,
		p_range: float, p_speed: float = 13.0) -> WarlockImpBolt:
	var b := WarlockImpBolt.new()
	b.name = "ImpBolt"
	b.team = TEAM_PLAYERS
	b.damage = p_damage
	var d := Vector3(dir.x, 0.0, dir.z)
	b.direction = d.normalized() if d.length_squared() > 0.000001 else Vector3.FORWARD
	b.speed = maxf(0.0, p_speed)
	b.max_range = maxf(0.0, p_range)
	b.pierce = maxi(0, targets - 1)
	b._pierce_left = b.pierce
	b.attacker = warlock
	b.style = &"fireball"
	b.color = COLOR
	b.knockback = 0.0
	b.add_to_group(&"projectiles")
	b._build_visual()
	b.scale = Vector3.ONE * 0.8
	var parent := WeaponRunner.effects_parent(warlock)
	if parent != null:
		parent.add_child(b)
		b.global_position = from
	return b


## Replaces the weapon hit of Projectile: pet damage through the Warlock's ProcSystem.
func _apply_hit(body: Node3D, _kb_dir: Vector3, _from_explosion: bool) -> void:
	hit_count += 1
	var e := body as Enemy
	if e == null or attacker == null or not is_instance_valid(attacker):
		return
	var warlock := attacker as Player
	if warlock == null or warlock.procs == null:
		return
	victim_ids.append(e.get_instance_id())
	warlock.procs.deal_raw(e, damage, WarlockImp.SCHOOL, true, &"pet")
	if _pierce_left > 0:
		_ricochet(e)


## Turns towards the nearest enemy this bolt has not hit yet (flies on when there is none).
func _ricochet(from_enemy: Enemy) -> void:
	if not is_inside_tree() or not is_instance_valid(from_enemy) or not from_enemy.is_inside_tree():
		return
	var center := from_enemy.global_position
	var best: Enemy = null
	var best_d := RICOCHET_RANGE * RICOCHET_RANGE
	for node in EnemyGrid.gather_around(get_tree(), center, RICOCHET_RANGE):
		var e := node as Enemy
		if e == null or e == from_enemy or not e.is_inside_tree() or e.is_dead():
			continue
		if _hit_ids.has(e.get_instance_id()):
			continue
		var d := WeaponRunner.flat(e.global_position - center).length_squared()
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		return
	var to := WeaponRunner.flat(best.global_position - center)
	if to.length_squared() < 0.0001:
		return
	direction = to.normalized()
	global_position = Vector3(center.x, global_position.y, center.z)
	max_range = travelled + RICOCHET_RANGE + 1.0
	if _visual != null:
		_visual.basis = Basis.looking_at(direction, Vector3.UP)
