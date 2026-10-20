class_name ArtifactHunterGaleVolley
extends TalentEffect
## Gale Volley – property 1 of the Galestrike Longbow (M8): every [code]every[/code]th (4) shot of the
## Hunter's own weapon splits into a fan of [code]arrows[/code] (5) free arrows – spread over a cone of
## [code]spread[/code] (40) degrees centred on the target, each for [code]damage_pct[/code] (60) % of that
## shot's damage ([ArtifactHunterGaleArrow]: proc damage, no crit, no on-hit procs, so a volley never counts
## itself and cannot chain).
## One count per shot: only the first hit of a main-hand weapon attack counts (the ProcGate hit). Arrows of
## an ability (Arrow Fan, Long Shot, Backstep's Parting Volley: [member Player.last_hit_extra]) and the
## hits of an extra attack do not count; the further hits of a piercing shot do not either. At most one
## volley every [code]cooldown[/code] (1) s – a Quick Draw Hunter shoots four times a second: a fourth shot
## that lands inside the cooldown keeps the count at "ready", the next shot after it looses the volley.
## The count carries across waves and resets when the property goes away. No RNG.
##
## Params (not rank-scaled): every (shots per volley), arrows, spread (degrees), damage_pct (%),
## cooldown (s between two volleys, 0 = none).

const SOUND := &"shot_bow"
const COLOR := Color(0.6, 0.92, 0.8)
const TEXT_COLOR := Color(0.6, 0.95, 0.82)
## Flight speed / range when the Hunter holds no weapon with its own.
const FALLBACK_SPEED := 24.0
const FALLBACK_RANGE := 11.0

## Shots counted towards the next volley (stays at `every` while the cooldown runs).
var shots := 0
## Volleys and arrows loosed so far (tests).
var volleys := 0
var arrows_loosed := 0
## Seconds until the next volley may be loosed.
var cooldown_left := 0.0


func on_hit(target: Node3D, damage: float, _is_crit: bool, first: bool) -> void:
	if not first or player == null or not is_instance_valid(player) or player.last_hit_extra:
		return
	var every := maxi(1, roundi(num("every", 4.0)))
	shots = mini(shots + 1, every)
	if shots < every or cooldown_left > 0.0:
		return
	if loose(target, damage) > 0:
		shots = 0
		volleys += 1
		cooldown_left = maxf(0.0, num("cooldown", 0.0))


func tick(delta: float) -> void:
	if cooldown_left > 0.0:
		cooldown_left = maxf(0.0, cooldown_left - delta)


## Looses the fan at [param target] (the hero's facing when it is gone): each arrow deals damage_pct % of
## [param shot_damage]. Returns the arrows.
func loose(target: Node3D, shot_damage: float) -> int:
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return 0
	var parent := WeaponRunner.effects_parent(player)
	if parent == null:
		return 0
	var weapon := player.main_hand
	var count := maxi(1, roundi(num("arrows", 5.0)))
	var spread := num("spread", 40.0)
	var speed := weapon.projectile_speed if weapon != null and weapon.projectile_speed > 0.0 else FALLBACK_SPEED
	var reach := weapon.attack_range if weapon != null and weapon.attack_range > 0.0 else FALLBACK_RANGE
	var school: StringName = weapon.school if weapon != null else &"physical"
	var damage := maxf(0.0, shot_damage) * num("damage_pct", 60.0) / 100.0
	var aim: Vector3 = target.global_position if target != null and is_instance_valid(target) and target.is_inside_tree() \
			else player.global_position + player.facing
	var facing := HunterKit.dir_to(player.global_position, aim, player.facing)
	var origin := player.global_position + Vector3.UP * Player.CHEST_HEIGHT
	for i in count:
		var angle := 0.0
		if count > 1:
			angle = deg_to_rad(spread) * (float(i) / float(count - 1) - 0.5)
		var shot := facing.rotated(Vector3.UP, angle)
		var arrow := ArtifactHunterGaleArrow.make(player, damage, shot, speed, reach, school, COLOR)
		parent.add_child(arrow)
		arrow.global_position = origin + shot * (Player.RADIUS + HunterKit.MUZZLE_GAP)
	arrows_loosed += count
	Audio.play(SOUND)
	Vfx.floating_text(player.self_text_position(1.0), "Gale Volley", TEXT_COLOR, Player.SELF_TEXT_SIZE, 1.0)
	return count


func describe() -> String:
	return "Every %d shots split into a fan of %d arrows." % [maxi(1, roundi(num("every", 4.0))),
			maxi(1, roundi(num("arrows", 5.0)))]
