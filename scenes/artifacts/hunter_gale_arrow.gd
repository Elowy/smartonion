class_name ArtifactHunterGaleArrow
extends Projectile
## One arrow of the Galestrike Longbow's Gale Volley (M8): a plain player [Projectile] (swept hits, the shared
## EnemyGrid) whose hit is NOT a weapon hit – it deals its fixed [member damage] as a proc through
## ProcSystem.deal_raw (source &"proc", no target bonus, no crit, no leech, no on-hit procs, no talent hooks),
## so a volley can never feed itself or the Gale Volley counter. Looks like an arrow of the bow.

## School of the damage (the bow's: physical).
var school: StringName = &"physical"


## An arrow of [param player] flying along [param dir] that deals [param p_damage] to the first enemy it meets.
## Not in the tree yet: the caller adds it (WeaponRunner.effects_parent) and places it.
static func make(player: Player, p_damage: float, dir: Vector3, p_speed: float, p_range: float,
		p_school: StringName, p_color: Color) -> ArtifactHunterGaleArrow:
	var a := ArtifactHunterGaleArrow.new()
	a.name = "GaleArrow"
	a.team = TEAM_PLAYERS
	a.damage = p_damage
	var d := Vector3(dir.x, 0.0, dir.z)
	a.direction = d.normalized() if d.length_squared() > 0.000001 else Vector3.FORWARD
	a.speed = maxf(0.0, p_speed)
	a.max_range = maxf(0.0, p_range)
	a.attacker = player
	a.style = &"arrow"
	a.color = p_color
	a.school = p_school
	a.add_to_group(&"projectiles")
	a._build_visual()
	return a


func _apply_hit(body: Node3D, _kb_dir: Vector3, _from_explosion: bool) -> void:
	hit_count += 1
	if attacker == null or not is_instance_valid(attacker):
		return
	var hero := attacker as Player
	var enemy := body as Enemy
	if hero == null or hero.procs == null or enemy == null:
		return
	hero.procs.deal_raw(enemy, damage, school, false, &"proc")
