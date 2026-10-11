class_name RoguePoisonBomb
extends AbilityEffect
## Poison Bomb (GDD 6.4, Rogue Auto): lobs a vial at the densest group of enemies within the
## cast range; after [code]flight[/code] (0.45) s it shatters into a poison cloud
## ([AbilityArea], Nature) of [code]radius[/code] (2.5) m for [code]duration[/code] (4) s that
## deals [code]damage_pct[/code] (25) % of a weapon hit x "power" as Nature damage to every
## enemy inside each [code]tick[/code] (0.5) s.
## Rank III: +1 m radius. Rank V: "Crippling Fumes" ([code]slow_pct[/code]: the cloud slows)
## or "Volatile Mixture" ([code]impact_pct[/code]: the vial bursts for that % of a weapon hit
## on impact, [code]duration[/code] +2 s).
## Auto-cast when the cloud would cover at least AUTO_MIN_ENEMIES enemies – or a lone enemy
## when nothing else is around.

## The AbilityArea disc: a faint sickly yellow-green (the gas puffs carry the look).
const CLOUD_COLOR := Color(0.62, 0.8, 0.18, 0.14)
const SCHOOL := &"nature"
const AUTO_MIN_ENEMIES := 2


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_inside_tree() or ctx.target == null:
		return false
	var tree := player.get_tree()
	var radius := ctx.num("radius", 2.5) * CombatMath.area_mult(player.stats)
	if RogueUtil.enemies_around(tree, ctx.target.global_position, radius).size() >= AUTO_MIN_ENEMIES:
		return true
	return RogueUtil.enemies_around(tree, player.global_position, ctx.ability.cast_range).size() == 1


func cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_inside_tree() or ctx.target == null:
		return false
	var flask := RoguePoisonFlask.throw(player, player.global_position, ctx.target.global_position,
			maxf(0.05, ctx.num("flight", 0.45)))
	if flask == null:
		return false
	flask.radius = ctx.num("radius", 2.5)
	flask.duration = maxf(0.1, ctx.num("duration", 4.0))
	flask.tick = maxf(0.1, ctx.num("tick", 0.5))
	flask.damage_per_tick = tick_damage(player, ctx.params)
	flask.slow_pct = clampf(ctx.num("slow_pct", 0.0), 0.0, 90.0)
	flask.impact_damage = RogueUtil.weapon_damage(player, SCHOOL) * ctx.num("impact_pct", 0.0) / 100.0 \
			* ctx.num("power", 1.0)
	player.face_attack(WeaponRunner.flat(ctx.target.global_position - player.global_position))
	return true


## Nature damage of one cloud tick for [param player] with [param params] (before the owner's
## outgoing multipliers and target bonuses, which ProcSystem.deal_raw applies).
static func tick_damage(player: Player, params: Dictionary) -> float:
	return RogueUtil.weapon_damage(player, SCHOOL) * float(params.get("damage_pct", 25.0)) / 100.0 \
			* float(params.get("power", 1.0))
