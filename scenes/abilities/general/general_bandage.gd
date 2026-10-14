class_name GeneralBandage
extends AbilityEffect
## Bandage (GDD 6.4, general Active): heal_pct % of the hero's max HP over duration seconds, in
## equal ticks every tick seconds (a [GeneralBuff] with heal ticks and the bandage look).
## Design decision: taking damage does NOT interrupt it (an arena survivor is always being
## hit – a WoW-style interrupt would make it useless); going down ends it.
## The cast is refused (no cooldown) while nobody it would bandage is hurt.
##
## Params (rank / spec / item mods change them):
##   heal_pct        % of the bandaged hero's max HP (x power)
##   duration, tick  seconds of the heal and between two ticks
##   targets         heroes bandaged: the caster + the (targets - 1) most wounded living
##                   teammates within ally_range m without a bandage of their own running
##                   (it is never overwritten) (Rank III: +1 = one ally)
##   instant         Quick Wrap (spec): the whole heal lands at once
##   damage_reduction  Padded Wraps (spec): % less damage taken while bandaged (x power, max 75)
##   auto_hp         bots bandage below this % of max HP (themselves or a bandageable ally)

const KEY := &"general_bandage"
const TEXT_COLOR := Color(0.95, 0.92, 0.8)
const MAX_REDUCTION := 75.0
## Instant heals keep the bandage look this long.
const INSTANT_LOOK_TIME := 0.8


func can_cast(ctx: AbilityContext) -> bool:
	for p in bandage_targets(ctx):
		if p.hp < p.max_hp() - 0.001:
			return true
	return false


## Bots (the button slots) bandage when they – or a teammate this cast would reach – are low.
func wants_auto_cast(ctx: AbilityContext) -> bool:
	if ctx.player == null or not ctx.player.is_alive():
		return false
	var limit := ctx.num("auto_hp", 50.0) / 100.0
	for p in bandage_targets(ctx):
		if GeneralKit.hp_ratio(p) < limit and GeneralBuff.find(p, KEY) == null:
			return true
	return false


func cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_alive():
		return false
	var targets := bandage_targets(ctx)
	if targets.is_empty():
		return false
	for p in targets:
		bandage(ctx, p)
	if player.is_inside_tree():
		Vfx.floating_text(player.self_text_position(-1.0), "Bandage", TEXT_COLOR,
				Player.SELF_TEXT_SIZE, -1.0)
	return true


func begin_wave(ctx: AbilityContext) -> void:
	_clear(ctx)


func end_wave(ctx: AbilityContext) -> void:
	_clear(ctx)


## Heroes a cast bandages: the caster, then the most wounded living teammates within range
## that are not bandaged already (a running bandage keeps its own heal and Padded Wraps).
static func bandage_targets(ctx: AbilityContext) -> Array[Player]:
	var out: Array[Player] = []
	var player := ctx.player
	if player == null or not player.is_alive():
		return out
	out.append(player)
	var extra := roundi(ctx.num("targets", 1.0)) - 1
	if extra <= 0:
		return out
	var hurt: Array[Player] = []
	for p in GeneralKit.allies_near(player, ctx.num("ally_range", 6.0)):
		if p.hp < p.max_hp() - 0.001 and GeneralBuff.find(p, KEY) == null:
			hurt.append(p)
	# Most wounded first; ties keep the group order (stable insertion).
	var sorted: Array[Player] = []
	for p in hurt:
		var at := sorted.size()
		for i in sorted.size():
			if GeneralKit.hp_ratio(p) < GeneralKit.hp_ratio(sorted[i]):
				at = i
				break
		sorted.insert(at, p)
	for i in mini(extra, sorted.size()):
		out.append(sorted[i])
	return out


## HP a bandage restores to [param who] in total.
static func heal_total(ctx: AbilityContext, who: Player) -> float:
	if who == null:
		return 0.0
	return maxf(0.0, who.max_hp() * ctx.num("heal_pct", 30.0) / 100.0 * ctx.num("power", 1.0))


## Damage-taken multiplier while bandaged (Padded Wraps; 1 = none).
static func taken_mult(ctx: AbilityContext) -> float:
	var pct := clampf(ctx.num("damage_reduction") * ctx.num("power", 1.0), 0.0, MAX_REDUCTION)
	return 1.0 - pct / 100.0


## Puts a bandage on [param who] (refreshes a running one).
static func bandage(ctx: AbilityContext, who: Player) -> GeneralBuff:
	var total := heal_total(ctx, who)
	var mult := taken_mult(ctx)
	if ctx.flag("instant"):
		var look := GeneralBuff.apply(who, KEY, INSTANT_LOOK_TIME, {}, mult,
				GeneralAuraVfx.Style.BANDAGE)
		who.heal(total, Player.slot_index_of(ctx.player))
		return look
	var duration := maxf(0.05, ctx.num("duration", 3.0))
	var tick := clampf(ctx.num("tick", 0.5), 0.05, duration)
	var buff := GeneralBuff.apply(who, KEY, duration, {}, mult, GeneralAuraVfx.Style.BANDAGE)
	if buff != null:
		buff.set_heal(total, maxi(1, roundi(duration / tick)), tick, Player.slot_index_of(ctx.player))
	return buff


func _clear(ctx: AbilityContext) -> void:
	if ctx.player != null and is_instance_valid(ctx.player) and ctx.player.is_inside_tree():
		GeneralBuff.clear(ctx.player.get_tree(), KEY)
	elif ctx.player != null and is_instance_valid(ctx.player):
		GeneralBuff.clear_on(ctx.player, KEY, false)
