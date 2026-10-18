class_name PaladinWordOfGlory
extends AbilityEffect
## Word of Glory (GDD 3.3, LT, Holy Power): with a downed teammate within cast range it
## INSTANTLY revives them at [code]revive_hp[/code] of their max HP instead of healing – the only
## instant revive in the game (AbilityRunner ALLY targeting with prefer_downed picks the
## downed teammate). Otherwise it heals the Paladin and the most hurt living teammate in range
## ([method heal_targets]). A ghost the Spirit Healer's pulse revives within
## [constant HEALER_SOON] seconds (at full HP, [method healer_raises_soon]) is left to it – the
## cast revives another downed teammate in range instead (AbilityRunner's ALLY targeting skips
## that ghost), or heals when there is none; a ghost with a longer wait is a fair revive.
##
## Params: prefer_downed, revive_hp (x power, at most full HP), heal (flat), heal_max_hp_pct (% of
## the healed hero's max HP), spell_power_scale – the heal x power (ranks II / IV); allies
## (Rank III: +1 – the most hurt allies in range healed besides the Paladin), heal_all (spec
## "Light of Dawn": every hero within range), shield_share / shield_duration (spec "Holy
## Bulwark": every healed hero also gets an absorb shield worth that % of the heal); "cost" is
## seeded from AbilityData.cost (Libram of Devotion: cost_add -1). Heals x the caster's Healing
## Done (PaladinKit.heal_amount); the revive HP is not.
## Artifact (Dawnbreaker, "Dawn's Embrace"): shield_max_hp_pct (% of the target's max HP, 0 =
## off): every hero this cast heals or raises is also shielded for that much (shield_duration;
## a source of its own that tops up to the amount, never stacks past it).
##
## M5 – Divine Verdict (Retribution modifier, "verdict_pct_add"): verdict_pct (% weapon damage,
## 0 = off), verdict_sp_scale (x Spell Power), verdict_range (m). With verdict_pct > 0 the cast
## picks, in this order: (1) a revive (unchanged); (2) a heal when a hero within the cast range
## (the Paladin included) is below [constant VERDICT_HEAL_RATIO] of max HP; (3) the Verdict – a
## Holy strike on the nearest elite / boss within verdict_range, else the nearest enemy
## ([method verdict_target]): PaladinKit.strike_damage(verdict_pct, verdict_sp_scale, power) as
## &"ability" damage; (4) a heal of whoever else is hurt. Nothing to do: no cast (no Holy Power
## spent). Same cost, free_chance (Eternal Glory) and power as the heal. Bots cast the Verdict
## only while no teammate is downed anywhere (the Holy Power waits for a revive).

const HOLY_COLOR := Color(1.0, 0.88, 0.45)
## ProcSystem shield source of Dawn's Embrace (the Dawnbreaker Artifact).
const ARTIFACT_SHIELD := &"dawn_embrace"
## Bots heal when a hero in range is below this share of max HP.
const AUTO_HEAL_RATIO := 0.5
## Divine Verdict: a hero in range below this share of max HP is healed instead.
const VERDICT_HEAL_RATIO := 0.8
const VERDICT_TEXT := "Verdict!"
const VERDICT_SHAKE := 0.15
## A ghost the Spirit Healer revives within this many seconds (Player.healer_seconds_left) is
## not worth a revive.
const HEALER_SOON := 1.0


## True when the Spirit Healer's pulse revives [param p] (at full HP) within HEALER_SOON
## seconds (0 <= Player.healer_seconds_left <= that; -1 = not waiting in its circle). The one
## rule for both the targeting (AbilityRunner) and [method revive_target].
static func healer_raises_soon(p: Player) -> bool:
	return p != null and p.healer_seconds_left >= 0.0 and p.healer_seconds_left <= HEALER_SOON


## The downed teammate this cast would revive (ctx.target when downed and within range, unless
## the Spirit Healer revives it within HEALER_SOON seconds anyway).
static func revive_target(ctx: AbilityContext) -> Player:
	var t := ctx.target as Player
	if t == null or t == ctx.player or not t.downed or not t.is_inside_tree():
		return null
	if healer_raises_soon(t):
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


## Divine Verdict: the enemy a Verdict strikes – the nearest elite / boss within verdict_range
## of the Paladin, else the nearest enemy (null without the talent or without an enemy).
static func verdict_target(ctx: AbilityContext) -> Enemy:
	var p := ctx.player
	if ctx.num("verdict_pct") <= 0.0 or p == null or not p.is_inside_tree():
		return null
	var near := PaladinKit.enemies_by_distance(p.get_tree(), p.global_position, ctx.num("verdict_range", 4.0))
	for e in near:
		if e.is_elite() or e.is_boss():
			return e
	return near[0] if not near.is_empty() else null


## True when a living hero within the cast range (the Paladin included) is below
## [param ratio] of max HP.
static func someone_below(ctx: AbilityContext, ratio: float) -> bool:
	var p := ctx.player
	if p == null:
		return false
	if p.is_alive() and PaladinKit.hp_ratio(p) < ratio:
		return true
	if not p.is_inside_tree():
		return false
	for hero in PaladinKit.living_heroes_around(p.get_tree(), p.global_position, ctx.ability.cast_range):
		if PaladinKit.hp_ratio(hero) < ratio:
			return true
	return false


## The Verdict target when this cast strikes instead of healing (Divine Verdict: no revive, no
## hero in range below VERDICT_HEAL_RATIO, an enemy within verdict_range); null otherwise.
static func verdict_now(ctx: AbilityContext) -> Enemy:
	if ctx.num("verdict_pct") <= 0.0 or revive_target(ctx) != null:
		return null
	if someone_below(ctx, VERDICT_HEAL_RATIO):
		return null
	return verdict_target(ctx)


## Divine Verdict damage of one cast (before the target bonuses, Mastery and the outgoing
## multipliers, which deal_raw applies).
static func verdict_damage(ctx: AbilityContext) -> float:
	return PaladinKit.strike_damage(ctx.player, ctx.num("verdict_pct"), ctx.num("verdict_sp_scale", 1.5),
			ctx.num("power", 1.0))


## Something to do: a downed teammate to raise, a hurt hero to heal or (Divine Verdict) an enemy
## to judge – never wastes Holy Power.
func can_cast(ctx: AbilityContext) -> bool:
	if revive_target(ctx) != null:
		return true
	for p in heal_targets(ctx):
		if _is_hurt(p):
			return true
	return verdict_now(ctx) != null


func cast(ctx: AbilityContext) -> bool:
	var paladin := ctx.player
	var downed := revive_target(ctx)
	if downed != null:
		var feet := downed.global_position
		downed.revive(revive_ratio(ctx), [paladin.slot_index()] as Array[int])
		if downed.downed:
			return false
		grant_shield(ctx, downed)
		Vfx.resurrect_column(feet)
		Vfx.floating_text(downed.get_chest_position() + Vector3.UP * 0.6, "Resurrected!", Player.HEAL_TEXT_COLOR, 1.2)
		ProcVfx.beam(paladin.get_chest_position(), downed.get_chest_position(), HOLY_COLOR)
		return true
	var judged := verdict_now(ctx)
	if judged != null:
		return _verdict(ctx, judged)
	var healed := false
	var shield_share := ctx.num("shield_share")
	for p in heal_targets(ctx):
		if not _is_hurt(p):
			continue
		var amount := heal_amount(ctx, paladin, p)
		p.heal(amount, paladin.slot_index())
		grant_shield(ctx, p)
		if shield_share > 0.0 and p.procs != null:
			p.procs.add_shield(amount * shield_share / 100.0, ctx.num("shield_duration", 8.0), &"", paladin.slot_index())
		Vfx.hit_spark(p.get_chest_position(), HOLY_COLOR)
		if p != paladin:
			ProcVfx.beam(paladin.get_chest_position(), p.get_chest_position(), HOLY_COLOR)
		healed = true
	return healed


## Dawn's Embrace: [param who] gets an absorb shield of shield_max_hp_pct % of their max HP
## (topped up to that amount: a second cast adds nothing while it is still there).
static func grant_shield(ctx: AbilityContext, who: Player) -> void:
	var pct := ctx.num("shield_max_hp_pct")
	if pct <= 0.0 or who == null or who.procs == null:
		return
	var want := who.max_hp() * pct / 100.0
	var missing := want - who.procs.shield_of(ARTIFACT_SHIELD)
	if missing > 0.0:
		# The Paladin cast it: the damage meter credits what it absorbs to the Paladin (METER).
		var caster := ctx.player.slot_index() if ctx.player != null else -1
		who.procs.add_shield(missing, ctx.num("shield_duration", 8.0), ARTIFACT_SHIELD, caster)
		Vfx.explosion(who.global_position + Vector3.UP * 0.1, 1.0, ProcSystem.SHIELD_COLOR)


## Bots: always raise a downed teammate in range; heal when a hero in range is below half HP;
## with Divine Verdict, judge an enemy while nobody in range needs a heal and no teammate is
## downed anywhere (the Holy Power waits for a revive).
func wants_auto_cast(ctx: AbilityContext) -> bool:
	if revive_target(ctx) != null:
		return true
	for p in heal_targets(ctx):
		if p.hp < p.max_hp() * AUTO_HEAL_RATIO:
			return true
	if ctx.num("verdict_pct") <= 0.0 or ctx.player == null or not ctx.player.is_inside_tree():
		return false
	if PaladinKit.any_downed(ctx.player.get_tree(), ctx.player):
		return false
	return verdict_now(ctx) != null


## Divine Verdict on [param target]: a golden Holy strike (ability damage).
func _verdict(ctx: AbilityContext, target: Enemy) -> bool:
	var paladin := ctx.player
	if paladin == null or paladin.procs == null or not is_instance_valid(target) or target.is_dead():
		return false
	var spot := target.global_position
	var chest := spot + Vector3.UP * WeaponRunner.DAMAGE_TEXT_HEIGHT * 0.5
	paladin.procs.deal_raw(target, verdict_damage(ctx), PaladinKit.SCHOOL, true, &"ability")
	if paladin.is_inside_tree():
		ProcVfx.beam(paladin.get_chest_position(), chest, HOLY_COLOR)
	Vfx.explosion(spot + Vector3.UP * 0.1, 1.0, HOLY_COLOR)
	Vfx.hit_spark(chest, HOLY_COLOR)
	Vfx.floating_text(spot + Vector3.UP * (WeaponRunner.DAMAGE_TEXT_HEIGHT + 0.5), VERDICT_TEXT, HOLY_COLOR, 0.9)
	var arena := Arena.current
	if arena != null and is_instance_valid(arena) and is_instance_valid(arena.camera):
		arena.camera.shake(VERDICT_SHAKE)
	return true
