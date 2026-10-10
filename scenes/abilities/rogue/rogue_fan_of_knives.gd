class_name RogueFanOfKnives
extends AbilityEffect
## Fan of Knives (GDD 3.4, Rogue RT): throws [code]knives[/code] (10) knives in all directions,
## each a weapon-based hit ([code]damage_pct[/code] (110) % of the main-hand hit, able to crit)
## that passes through [code]pierce[/code] (1) enemies. Every Combo Point held is spent and
## adds [code]combo_bonus_pct[/code] % (20) damage.
## Item mod (Blade of the Thousand Cuts): [code]knives_add[/code] = +4 knives.
##
## The knives are ordinary player Projectiles: their hits count as weapon hits
## (Combo Points and Deadly Poison on a crit, leech, Executioner / Slayer, Mastery
## multipliers) and roll on-hit procs once per cast. Knife crits roll normally – Vanish's
## guaranteed crit is kept for the weapons.

const KNIFE_COLOR := Color(0.82, 0.88, 1.0)
const KNIFE_KNOCKBACK := 0.6
## Bots fan when at least this many enemies are within AUTO_RANGE metres ...
const AUTO_MIN_ENEMIES := 3
const AUTO_RANGE := 5.0
## ... or when the Combo Points are full and an enemy is within the knives' reach.
const AUTO_FULL_COMBO := 5
const BURST_RADIUS := 1.7


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_inside_tree():
		return false
	if RogueUtil.enemies_within(player, AUTO_RANGE) >= AUTO_MIN_ENEMIES:
		return true
	return RogueUtil.combo_points(player) >= AUTO_FULL_COMBO \
			and RogueUtil.enemies_within(player, ctx.num("range", 7.0)) >= 1


func cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	var weapon := _weapon(player)
	if weapon == null or not player.is_inside_tree():
		return false
	var parent := WeaponRunner.effects_parent(player)
	if parent == null:
		return false
	var points := RogueUtil.combo_points(player)
	var combo := player.abilities.get_resource(RogueUtil.COMBO_ID)
	if combo != null:
		combo.set_value(0.0)
	var knives := maxi(1, roundi(ctx.num("knives", 10.0)))
	var damage := knife_damage(player, weapon, ctx.num("damage_pct", 110.0), points,
			ctx.num("combo_bonus_pct", 20.0))
	var crit_mult := CombatMath.crit_multiplier(weapon, player.stats)
	var speed := ctx.num("speed", 16.0)
	var reach := ctx.num("range", 7.0)
	var pierce := maxi(0, roundi(ctx.num("pierce", 0.0)))
	var facing := Vector3(ctx.direction.x, 0.0, ctx.direction.z)
	facing = facing.normalized() if facing.length_squared() > 0.0001 else Vector3.FORWARD
	var origin := player.global_position
	var gate := WeaponRunner.ProcGate.new()
	for i in knives:
		var dir := facing.rotated(Vector3.UP, TAU * float(i) / float(knives))
		var crit := CombatMath.roll_crit(player.stats, RunState.rng)
		var proj := Projectile.create(Projectile.TEAM_PLAYERS, damage * (crit_mult if crit else 1.0), crit,
				dir, speed, reach, pierce, 0.0, player, &"arrow", KNIFE_COLOR)
		RogueKnifeVisual.attach(proj, KNIFE_COLOR, crit)
		proj.knockback = KNIFE_KNOCKBACK
		proj.weapon = weapon
		proj.is_extra = true
		proj.proc_gate = gate
		parent.add_child(proj)
		proj.global_position = origin + Vector3.UP * Player.CHEST_HEIGHT + dir * (Player.RADIUS + 0.15)
	Vfx.slash_arc(origin + Vector3.UP * 0.3, facing, BURST_RADIUS, 360.0, KNIFE_COLOR)
	return true


## Damage of one (non-crit) knife: [param pct] % of the weapon hit, +[param bonus_pct] % per
## Combo Point spent.
static func knife_damage(player: Player, weapon: WeaponData, pct: float, points: int, bonus_pct: float) -> float:
	var hit := CombatMath.weapon_hit_damage(weapon, player.stats)
	return hit * pct / 100.0 * (1.0 + float(points) * bonus_pct / 100.0)


## The weapon the knives are based on: the main hand, else the off hand.
static func _weapon(player: Player) -> WeaponData:
	if player == null:
		return null
	return player.main_hand if player.main_hand != null else player.off_hand
