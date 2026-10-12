class_name PaladinLayOnHands
extends AbilityEffect
## Lay on Hands (GDD 6.4, Paladin Active, long cooldown): fully heals the living hero within the
## cast range – the Paladin included – with the lowest share of HP. It never revives: Word of
## Glory stays the only instant revive (GDD 3.3), so downed heroes are skipped.
##
## Params: shield_max_hp / shield_duration (Rank III: the healed hero also gets an absorb
## shield worth that % of its max HP x power x Healing Done), group_heal (spec "Hands of
## Mercy": instead of one full heal, every living hero in range is healed for that % of max HP
## x power x Healing Done – PaladinKit.healing_mult, talent Healing Light),
## guard / guard_duration (spec "Guardian's Touch": the healed hero takes -% damage x power
## for a while, Player.damage_taken_mults under [method guard_key]).
##
## A full heal cannot grow with power; Ranks II / IV scale the extras (shield, group heal,
## guard) and shorten the cooldown. Bots: someone in range below [constant AUTO_HP_RATIO]
## (group spec: two heroes below [constant AUTO_GROUP_RATIO], or one below AUTO_HP_RATIO).

const AUTO_HP_RATIO := 0.3
const AUTO_GROUP_RATIO := 0.5
const MAX_GUARD := 75.0

var _player: Player
var _key: StringName = &""
var _guard_left := 0.0
## Instance id -> guarded Player (values may be freed).
var _guarded: Dictionary = {}


## The damage-taken key of [param paladin]'s Guardian's Touch.
static func guard_key(paladin: Player) -> StringName:
	return PaladinKit.buff_key(paladin, "lay_on_hands")


## The hero a single-target cast heals: the hurt living hero in range with the lowest HP share.
static func heal_target(ctx: AbilityContext) -> Player:
	var p := ctx.player
	if p == null or not p.is_inside_tree():
		return null
	return PaladinKit.lowest_hero(p.get_tree(), p.global_position, ctx.ability.cast_range)


## Heroes a cast heals: the one [method heal_target], or every hurt living hero in range with
## the Hands of Mercy spec.
static func heal_targets(ctx: AbilityContext) -> Array[Player]:
	var out: Array[Player] = []
	var p := ctx.player
	if p == null or not p.is_inside_tree():
		return out
	if ctx.num("group_heal") > 0.0:
		for hero in PaladinKit.living_heroes_around(p.get_tree(), p.global_position, ctx.ability.cast_range):
			if PaladinKit.is_hurt(hero):
				out.append(hero)
		return out
	var t := heal_target(ctx)
	if t != null:
		out.append(t)
	return out


## HP [param who] regains: everything missing, or group_heal % of max HP x power x the
## caster's Healing Done (PaladinKit.healing_mult – a full heal cannot grow).
static func heal_for(ctx: AbilityContext, who: Player) -> float:
	var group := ctx.num("group_heal")
	if group > 0.0:
		return who.max_hp() * group / 100.0 * ctx.num("power", 1.0) * PaladinKit.healing_mult(ctx.player)
	return maxf(0.0, who.max_hp() - who.hp)


func guarded() -> Array[Player]:
	var out: Array[Player] = []
	for id: int in _guarded:
		var v: Variant = _guarded[id]
		if is_instance_valid(v):
			out.append(v as Player)
	return out


## Never wasted: somebody in range is hurt.
func can_cast(ctx: AbilityContext) -> bool:
	return not heal_targets(ctx).is_empty()


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var targets := heal_targets(ctx)
	if targets.is_empty():
		return false
	var low := 0
	for hero in targets:
		var r := PaladinKit.hp_ratio(hero)
		if r < AUTO_HP_RATIO:
			return true
		if r < AUTO_GROUP_RATIO:
			low += 1
	return ctx.num("group_heal") > 0.0 and low >= 2


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	var targets := heal_targets(ctx)
	if p == null or targets.is_empty():
		return false
	_bind(p)
	var power := ctx.num("power", 1.0)
	var shield_pct := ctx.num("shield_max_hp") * PaladinKit.healing_mult(p)
	var guard := minf(MAX_GUARD, ctx.num("guard") * power)
	for hero in targets:
		hero.heal(heal_for(ctx, hero))
		if shield_pct > 0.0 and hero.procs != null:
			hero.procs.add_shield(hero.max_hp() * shield_pct / 100.0 * power, ctx.num("shield_duration", 8.0))
		if guard > 0.0:
			hero.damage_taken_mults[_key] = 1.0 - guard / 100.0
			_guarded[hero.get_instance_id()] = hero
			_guard_left = ctx.num("guard_duration", 6.0)
		Vfx.resurrect_column(hero.global_position)
		if hero != p:
			ProcVfx.beam(p.get_chest_position(), hero.get_chest_position(), PaladinKit.HOLY_COLOR)
	Vfx.floating_text(p.get_chest_position() + Vector3.UP * 0.8, "Lay on Hands", PaladinKit.HOLY_COLOR, 0.9)
	return true


func tick(_ctx: AbilityContext, delta: float) -> void:
	if _guard_left <= 0.0:
		return
	_guard_left -= delta
	if _guard_left <= 0.0:
		clear()


## Ends Guardian's Touch on everybody.
func clear() -> void:
	for id: int in _guarded:
		var v: Variant = _guarded[id]
		if is_instance_valid(v):
			(v as Player).damage_taken_mults.erase(_key)
	_guarded.clear()
	_guard_left = 0.0


func begin_wave(_ctx: AbilityContext) -> void:
	clear()


func end_wave(_ctx: AbilityContext) -> void:
	clear()


func _bind(p: Player) -> void:
	if _player == p:
		return
	_player = p
	_key = guard_key(p)
	PaladinKit.connect_once(p.downed_changed, _on_downed_changed)
	PaladinKit.connect_once(p.tree_exiting, clear)


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		clear()
