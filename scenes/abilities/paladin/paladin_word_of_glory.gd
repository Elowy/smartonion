class_name PaladinWordOfGlory
extends AbilityEffect
## Word of Glory (GDD 3.3, LT, Holy Power): with a downed teammate within cast range it
## INSTANTLY revives them at [code]revive_hp[/code] of their max HP instead of healing – the only
## instant revive in the game (AbilityRunner ALLY targeting with prefer_downed picks the
## downed teammate). Otherwise it heals the Paladin and the most hurt living teammate in range
## ([method heal_targets]).
##
## Params: prefer_downed, revive_hp (x power, at most full HP), heal (flat), heal_max_hp_pct (% of
## the healed hero's max HP), spell_power_scale – the heal x power (ranks II / IV); allies
## (Rank III: +1 – the most hurt allies in range healed besides the Paladin), heal_all (spec
## "Light of Dawn": every hero within range), shield_share / shield_duration (spec "Holy
## Bulwark": every healed hero also gets an absorb shield worth that % of the heal); "cost" is
## seeded from AbilityData.cost (Libram of Devotion: cost_add -1).

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


## Living heroes this cast heals: the Paladin and the [code]allies[/code] (1) most hurt living
## teammates in range (lowest HP share first, ties in group order) – or, with heal_all, every
## living hero in range.
static func heal_targets(ctx: AbilityContext) -> Array[Player]:
	var out: Array[Player] = []
	var paladin := ctx.player
	if paladin == null:
		return out
	if paladin.is_alive():
		out.append(paladin)
	if not paladin.is_inside_tree():
		return out
	var rows: Array[Array] = []
	var order := 0
	for p in PaladinKit.living_heroes_around(paladin.get_tree(), paladin.global_position, ctx.ability.cast_range):
		if p != paladin:
			rows.append([PaladinKit.hp_ratio(p), order, p])
			order += 1
	if not ctx.flag("heal_all"):
		rows.sort_custom(func(a: Array, b: Array) -> bool:
			return float(a[0]) < float(b[0]) or (float(a[0]) == float(b[0]) and int(a[1]) < int(b[1])))
		rows.resize(mini(rows.size(), maxi(0, roundi(ctx.num("allies", 1.0)))))
	for row in rows:
		out.append(row[2] as Player)
	return out


## HP restored to [param who] by the Paladin [param caster]: flat + % of the healed hero's max
## HP + the caster's Spell Power, x power.
static func heal_amount(ctx: AbilityContext, caster: Player, who: Player) -> float:
	return PaladinKit.heal_amount(caster, who, ctx.num("heal"), ctx.num("heal_max_hp_pct"),
			ctx.num("spell_power_scale"), ctx.num("power", 1.0))


## Share of max HP a revive brings back: revive_hp x power, at most everything.
static func revive_ratio(ctx: AbilityContext) -> float:
	return clampf(ctx.num("revive_hp", 0.4) * ctx.num("power", 1.0), 0.01, 1.0)


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
		downed.revive(revive_ratio(ctx))
		if downed.downed:
			return false
		Vfx.resurrect_column(feet)
		Vfx.floating_text(downed.get_chest_position() + Vector3.UP * 0.6, "Resurrected!", Player.HEAL_TEXT_COLOR, 1.2)
		ProcVfx.beam(paladin.get_chest_position(), downed.get_chest_position(), HOLY_COLOR)
		return true
	var healed := false
	var shield_share := ctx.num("shield_share")
	for p in heal_targets(ctx):
		if not _is_hurt(p):
			continue
		var amount := heal_amount(ctx, paladin, p)
		p.heal(amount)
		if shield_share > 0.0 and p.procs != null:
			p.procs.add_shield(amount * shield_share / 100.0, ctx.num("shield_duration", 8.0))
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
