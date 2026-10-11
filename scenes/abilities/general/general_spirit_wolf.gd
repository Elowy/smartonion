class_name GeneralSpiritWolf
extends AbilityEffect
## Spirit Wolf (GDD 6.4, general Auto-cast pet): summons [code]wolves[/code] spirit wolves
## ([GeneralSpiritWolfPet]) for duration seconds. They hunt the enemies around the hero and
## bite for bite_pct % of its weapon damage (GeneralKit.weapon_damage in the ability's school –
## Nature – x power) every bite_interval seconds (Haste speeds them up), as pet damage.
## Auto-cast: when an enemy is within cast range and the pack is missing a wolf or about to
## fade (REFRESH_WINDOW s); a recast tops the pack up and refreshes the running wolves.
## The wolves vanish when the hero goes down or is freed, and with the wave (begin_wave /
## end_wave – so also on forget).
##
## Params (rank / spec / item mods change them):
##   wolves, duration, bite_pct, bite_interval, leash (m around the hero they hunt in)
##   slow, slow_duration     Feral Pack (spec, with +1 wolf): bites slow (% x power)
##   heal_pct                Spirit Link (spec): bites heal the hero for this % of the damage

## A pack with less than this many seconds left may be refreshed early.
const REFRESH_WINDOW := 1.5
const TEXT_COLOR := Color(0.65, 0.9, 1.0)

## The running pack (tests, HUD).
var wolves: Array[GeneralSpiritWolfPet] = []


func wants_auto_cast(ctx: AbilityContext) -> bool:
	if ctx.player == null or not ctx.player.is_alive() or ctx.target == null:
		return false
	_prune()
	if wolves.size() < pack_size(ctx):
		return true
	for w in wolves:
		if w.life_left < REFRESH_WINDOW:
			return true
	return false


func cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_alive():
		return false
	_prune()
	var pet_params := pet_params_for(ctx)
	var life := maxf(0.5, ctx.num("duration", 12.0))
	for w in wolves:
		w.refresh(pet_params, life)
	var want := pack_size(ctx)
	var changed := not wolves.is_empty()
	# Free pack spots in order (a lost wolf's spot is taken again).
	var index := 0
	while wolves.size() < want:
		while _spot_taken(index):
			index += 1
		var w := GeneralSpiritWolfPet.spawn(player, index, pet_params, life, ctx.ability.school)
		if not w.is_inside_tree():
			w.free()
			break
		wolves.append(w)
		changed = true
	if changed and player.is_inside_tree():
		Vfx.floating_text(player.self_text_position(1.0), "Spirit Wolf", TEXT_COLOR, Player.SELF_TEXT_SIZE, 1.0)
	return changed


func begin_wave(_ctx: AbilityContext) -> void:
	dismiss_all()


func end_wave(_ctx: AbilityContext) -> void:
	dismiss_all()


## Wolves of one cast.
static func pack_size(ctx: AbilityContext) -> int:
	return maxi(1, roundi(ctx.num("wolves", 1.0)))


## What each wolf needs to know (final numbers; the damage itself follows the hero's stats).
static func pet_params_for(ctx: AbilityContext) -> Dictionary:
	return {
		"bite_pct": ctx.num("bite_pct", 35.0),
		"bite_interval": ctx.num("bite_interval", 1.2),
		"leash": ctx.num("leash", 8.0),
		"power": ctx.num("power", 1.0),
		"slow": ctx.num("slow"),
		"slow_duration": ctx.num("slow_duration", 1.5),
		"heal_pct": ctx.num("heal_pct"),
	}


func alive_count() -> int:
	_prune()
	return wolves.size()


## Sends every wolf away at once (no puff: wave hooks, forget).
func dismiss_all() -> void:
	for i in wolves.size():
		if is_instance_valid(wolves[i]):
			wolves[i].dismiss(true)
	wolves.clear()


func _spot_taken(index: int) -> bool:
	for w in wolves:
		if w.pack_index == index:
			return true
	return false


func _prune() -> void:
	for i in range(wolves.size() - 1, -1, -1):
		if not is_instance_valid(wolves[i]) or wolves[i].is_queued_for_deletion() or not wolves[i].is_active():
			wolves.remove_at(i)
