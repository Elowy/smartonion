class_name PaladinWordOfGlory
extends AbilityEffect
## Word of Glory (GDD 3.3, LT, Holy Power): with a downed teammate within cast range it
## INSTANTLY revives them at [code]revive_hp[/code] of their max HP instead of healing – the only
## instant revive in the game. Otherwise it heals the Paladin and the most hurt living teammate
## in range (AbilityRunner ALLY targeting with prefer_downed picks the target).
##
## Params: cost (Holy Power; Libram of Devotion: cost_add -1), prefer_downed, revive_hp,
## heal (flat), heal_max_hp_pct (% of the healed hero's max HP), spell_power_scale.

const HOLY_COLOR := Color(1.0, 0.88, 0.45)
## Bots heal when a hero in range is below this share of max HP.
const AUTO_HEAL_RATIO := 0.5


## The downed teammate this cast would revive (ctx.target when downed and within range).
static func revive_target(ctx: AbilityContext) -> Player:
	var t := ctx.target as Player
	if t == null or t == ctx.player or not t.downed or not t.is_inside_tree():
		return null
	if ctx.player == null or not ctx.player.is_inside_tree():
		return null
	if _flat_distance(ctx.player.global_position, t.global_position) > ctx.ability.cast_range + 0.001:
		return null
	return t


## Living heroes this cast heals: the Paladin and the targeted (most hurt) teammate in range.
static func heal_targets(ctx: AbilityContext) -> Array[Player]:
	var out: Array[Player] = []
	if ctx.player != null and ctx.player.is_alive():
		out.append(ctx.player)
	var ally := ctx.target as Player
	if ally != null and ally != ctx.player and ally.is_alive() and ally.is_inside_tree() \
			and _flat_distance(ctx.player.global_position, ally.global_position) <= ctx.ability.cast_range + 0.001:
		out.append(ally)
	return out


## HP restored to [param who] by the Paladin [param caster]: flat + % of the healed hero's max
## HP + the caster's Spell Power.
static func heal_amount(ctx: AbilityContext, caster: Player, who: Player) -> float:
	var power := maxf(0.0, caster.stats.get_raw(Stats.SPELL_POWER)) if caster != null else 0.0
	var max_hp := who.max_hp() if who != null else 0.0
	return maxf(0.0, ctx.num("heal") + max_hp * ctx.num("heal_max_hp_pct") / 100.0
			+ power * ctx.num("spell_power_scale"))


static func _is_hurt(p: Player) -> bool:
	return p != null and p.is_alive() and p.hp < p.max_hp() - 0.001


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Something to do: a downed teammate to raise or a hurt hero to heal (never wastes Holy Power).
func can_cast(ctx: AbilityContext) -> bool:
	if revive_target(ctx) != null:
		return true
	for p in heal_targets(ctx):
		if _is_hurt(p):
			return true
	return false


func cast(ctx: AbilityContext) -> bool:
	var paladin := ctx.player
	var downed := revive_target(ctx)
	if downed != null:
		var feet := downed.global_position
		downed.revive(ctx.num("revive_hp", 0.4))
		if downed.downed:
			return false
		Vfx.resurrect_column(feet)
		Vfx.floating_text(downed.get_chest_position() + Vector3.UP * 0.6, "Resurrected!", Player.HEAL_TEXT_COLOR, 1.2)
		ProcVfx.beam(paladin.get_chest_position(), downed.get_chest_position(), HOLY_COLOR)
		return true
	var healed := false
	for p in heal_targets(ctx):
		if not _is_hurt(p):
			continue
		p.heal(heal_amount(ctx, paladin, p))
		Vfx.hit_spark(p.get_chest_position(), HOLY_COLOR)
		if p != paladin:
			ProcVfx.beam(paladin.get_chest_position(), p.get_chest_position(), HOLY_COLOR)
		healed = true
	return healed


## Bots: always raise a downed teammate in range; heal when a hero in range is below half HP.
func wants_auto_cast(ctx: AbilityContext) -> bool:
	if revive_target(ctx) != null:
		return true
	for p in heal_targets(ctx):
		if p.hp < p.max_hp() * AUTO_HEAL_RATIO:
			return true
	return false
