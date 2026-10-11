class_name RogueBlade
extends Projectile
## A thrown Rogue blade – a Fan of Knives knife or a Shuriken Toss star. An ordinary player
## [Projectile] (swept hits, EnemyGrid, pierce) whose hits are weapon hits of [member weapon]
## (Combo Points and Deadly Poison on a crit, leech, Executioner / Slayer, the Mastery and
## outgoing multipliers; on-hit procs roll once per throw through the shared proc gate), with
## the Rogue's own look and two extras used by the Rank V specialisations:
##   [member poison_hits] – a non-critical hit also adds a Deadly Poison stack (crits already
##                          do through the Mastery),
##   [member returns]     – at the end of its range the blade turns around and flies back
##                          along its path, able to hit every enemy again.

enum Look { KNIFE, SHURIKEN }

var look := Look.KNIFE
var poison_hits := false
## Turns left (0 = the blade ends at its range like any projectile).
var returns := 0
## Turns made so far (tests, visuals).
var turned := 0


## A blade of [param player] thrown along [param dir] with [param p_weapon]'s hit rules.
## Not yet in the tree: the caller adds it (WeaponRunner.effects_parent) and places it.
static func throw(player: Player, p_weapon: WeaponData, p_damage: float, p_crit: bool, dir: Vector3,
		p_speed: float, p_range: float, p_pierce: int, p_color: Color, p_look: Look = Look.KNIFE) -> RogueBlade:
	var b := RogueBlade.new()
	b.name = "RogueBlade"
	b.team = TEAM_PLAYERS
	b.damage = p_damage
	b.is_crit = p_crit
	var d := Vector3(dir.x, 0.0, dir.z)
	b.direction = d.normalized() if d.length_squared() > 0.000001 else Vector3.FORWARD
	b.speed = maxf(0.0, p_speed)
	b.max_range = maxf(0.0, p_range)
	b.pierce = maxi(0, p_pierce)
	b._pierce_left = b.pierce
	b.attacker = player
	b.style = &"arrow"
	b.color = p_color
	b.look = p_look
	b.weapon = p_weapon
	b.is_extra = true
	b.add_to_group(&"projectiles")
	b._build_visual()
	return b


## The Rogue's own models instead of the style's default visual.
func _build_visual() -> void:
	var v: Node3D
	_spinner = null
	if look == Look.SHURIKEN:
		v = RogueShurikenVisual.build(color, is_crit)
		_spinner = v.get_node_or_null("Spinner") as Node3D
	else:
		v = RogueKnifeVisual.build(color, is_crit)
	v.name = "Visual"
	v.basis = Basis.looking_at(direction, Vector3.UP) * Basis.from_scale(v.scale)
	add_child(v)
	_visual = v
	set_process(_spinner != null)


func _apply_hit(body: Node3D, kb_dir: Vector3, from_explosion: bool) -> void:
	super._apply_hit(body, kb_dir, from_explosion)
	if poison_hits and not is_crit:
		_poison(body)


## A Deadly Poison stack for the hit on [param body] (the Mastery's share of this blade's
## damage; a blade that killed its target poisons the nearest neighbour, like a crit).
func _poison(body: Node3D) -> void:
	var rogue := attacker as Player if attacker != null and is_instance_valid(attacker) else null
	if rogue == null or rogue.abilities == null or not rogue.is_alive():
		return
	var mastery := rogue.abilities.mastery as RogueMastery
	var enemy := CritDot.target_for(body)
	if mastery != null and enemy != null:
		mastery.poison(enemy, mastery.stack_damage(damage))


## At the end of its range a returning blade turns around (fresh hit list and pierce) instead
## of ending; hitting its last target or leaving the arena still ends it.
func _finish() -> void:
	if returns > 0 and not is_done() and is_inside_tree() and travelled >= max_range - 0.001:
		returns -= 1
		turned += 1
		direction = -direction
		travelled = 0.0
		_hit_ids.clear()
		_pierce_left = pierce
		if _visual != null:
			_visual.rotate_y(PI)
		return
	super._finish()
