class_name RogueShadowstep
extends AbilityEffect
## Shadowstep (GDD 6.4, Rogue Active): the Rogue steps through the shadows to the far side of
## an enemy within the cast range – the nearest one in the direction it faces (within
## FACING_CONE degrees), else the nearest one – and its next [code]forced_crits[/code] (1)
## weapon hits are guaranteed crits (Player.forced_crits). For [code]buff_duration[/code] (3) s
## it deals [code]damage_pct[/code] (15) % x "power" more damage (Player.damage_mults
## [constant BUFF_KEY]) and it is invulnerable for [code]invulnerable[/code] (0.3) s on arrival.
## The landing spot is kept inside the arena, the shared screen's walk rectangle and short of
## props (RogueUtil.spot_behind); no enemy in range: nothing happens, nothing is spent.
## Rank III: +1 guaranteed crit. Rank V: "Ambush" ([code]strike_pct[/code]: the step ends in
## a weapon strike on the target for that % x power – it takes the guaranteed crit – and a
## [code]stun[/code] s stun) or "Twin Shadows" ([code]charges[/code] +1: two steps in a row).
## The Ambush strike asks a talent script that forces crits (RogueUtil.bonus_crit – Shadow
## Dance) after the banked guaranteed crit and before its own roll.
## Bot rule: an enemy at least AUTO_MIN_GAP m away, the Rogue healthy enough and not reviving,
## and not too many enemies waiting around the target.

const BUFF_KEY := &"shadowstep"
const FACING_CONE := 50.0
const AUTO_MIN_GAP := 3.0
const AUTO_MIN_HP := 0.45
const AUTO_MAX_CROWD := 4
const AUTO_CROWD_RADIUS := 2.5
const STRIKE_COLOR := Color(0.7, 0.55, 1.0)

var _player: Player
var _buff_left := 0.0


func can_cast(ctx: AbilityContext) -> bool:
	return pick_target(ctx) != null


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_inside_tree() or player.is_reviving():
		return false
	if player.max_hp() <= 0.0 or player.hp / player.max_hp() < AUTO_MIN_HP:
		return false
	var target := pick_target(ctx)
	if target == null:
		return false
	var gap := WeaponRunner.flat(target.global_position - player.global_position).length()
	if gap < AUTO_MIN_GAP:
		return false
	return RogueUtil.enemies_around(player.get_tree(), target.global_position, AUTO_CROWD_RADIUS).size() \
			<= AUTO_MAX_CROWD


func cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	var target := pick_target(ctx)
	if player == null or target == null:
		return false
	_player = player
	if not player.downed_changed.is_connected(_on_downed_changed):
		player.downed_changed.connect(_on_downed_changed)
	var from := player.global_position
	var to := RogueUtil.spot_behind(player, target, from)
	RogueUtil.teleport(player, to)
	var look := WeaponRunner.flat(target.global_position - to)
	if look.length_squared() > 0.0001:
		player.facing = look.normalized()
		player.face_attack(look)
	var power := ctx.num("power", 1.0)
	player.forced_crits = maxi(player.forced_crits, roundi(ctx.num("forced_crits", 1.0)))
	player.invulnerable_left = maxf(player.invulnerable_left, ctx.num("invulnerable", 0.3))
	var bonus := ctx.num("damage_pct", 15.0) * power
	_buff_left = ctx.num("buff_duration", 3.0)
	if bonus > 0.0 and _buff_left > 0.0:
		player.damage_mults[BUFF_KEY] = 1.0 + bonus / 100.0
	var strike := ctx.num("strike_pct", 0.0)
	var enemy := target as Enemy
	if strike > 0.0 and enemy != null:
		_ambush(player, enemy, strike * power / 100.0)
	var stun := ctx.num("stun", 0.0)
	if stun > 0.0 and enemy != null and is_instance_valid(enemy) and not enemy.is_dead():
		enemy.apply_stun(stun)
	RogueVfx.step_puff(from)
	RogueVfx.streak(from, to)
	RogueVfx.step_puff(to, 0.6)
	return true


func tick(_ctx: AbilityContext, delta: float) -> void:
	if _buff_left > 0.0:
		_buff_left -= delta
		if _buff_left <= 0.0:
			clear_buff()


func begin_wave(_ctx: AbilityContext) -> void:
	clear_buff()


func end_wave(_ctx: AbilityContext) -> void:
	clear_buff()


func buff_left() -> float:
	return maxf(0.0, _buff_left)


func clear_buff() -> void:
	_buff_left = 0.0
	if _player != null and is_instance_valid(_player):
		_player.damage_mults.erase(BUFF_KEY)


## The enemy the step goes to: the nearest living one within the cast range inside the
## FACING_CONE in front of the Rogue (its facing / last move direction), else the nearest one
## (the runner's target).
static func pick_target(ctx: AbilityContext) -> Node3D:
	var player := ctx.player
	if player == null or not player.is_inside_tree():
		return null
	var here := player.global_position
	var reach := ctx.ability.cast_range if ctx.ability != null else 10.0
	var facing := WeaponRunner.flat(player.facing)
	if facing.length_squared() > 0.0001:
		facing = facing.normalized()
		var cos_cone := cos(deg_to_rad(FACING_CONE))
		var best: Enemy = null
		var best_d := INF
		for node in EnemyGrid.gather_around(player.get_tree(), here, reach):
			var e := node as Enemy
			if e == null or not e.is_inside_tree() or e.is_dead():
				continue
			var to := WeaponRunner.flat(e.global_position - here)
			var d := to.length()
			if d > reach or d < 0.001 or d >= best_d:
				continue
			if facing.dot(to / d) < cos_cone:
				continue
			best = e
			best_d = d
		if best != null:
			return best
	var t := ctx.target
	if t != null and is_instance_valid(t) and t.is_inside_tree() and not (t is Enemy and (t as Enemy).is_dead()):
		return t
	return EnemyGrid.nearest(player.get_tree(), here, reach)


## Ambush: a weapon strike of the main hand on [param enemy] for [param mult] x a hit (takes a
## guaranteed crit first).
static func _ambush(player: Player, enemy: Enemy, mult: float) -> void:
	var weapon := RogueUtil.weapon(player)
	if weapon == null or not is_instance_valid(enemy) or enemy.is_dead():
		return
	var crit := player.consume_forced_crit() or RogueUtil.bonus_crit(player, enemy) \
			or CombatMath.roll_crit(player.stats, RunState.rng)
	var damage := CombatMath.weapon_hit_damage(weapon, player.stats) * mult \
			* (CombatMath.crit_multiplier(weapon, player.stats) if crit else 1.0)
	var dir := WeaponRunner.flat(enemy.global_position - player.global_position)
	dir = dir.normalized() if dir.length_squared() > 0.0001 else player.facing
	Vfx.slash_arc(player.global_position + Vector3.UP * 0.3, dir, 1.6, 90.0, STRIKE_COLOR)
	WeaponRunner.apply_hit(player, enemy, damage, crit, dir * weapon.knockback, 0.0, 0.5, weapon, true)


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		clear_buff()
