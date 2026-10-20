class_name ShamanSpiritPack
extends AbilityEffect
## Spirit Pack (M8, Shaman Active): calls [code]wolves[/code] ancestral wolves ([ShamanWolf], the Phantom Wolf's
## pet in a teal coat) for [code]duration[/code] s. They hunt the enemies around the Shaman and bite for
## bite_pct % of the main hand's weapon hit as Nature damage every bite_interval s (Haste speeds them up) – PET
## damage (deal_raw &"pet": kill credit, damage meter, never a crit) – and every bite feeds the Shaman
## surge_per_bite Surge. A recast tops the pack up and refreshes the running wolves. The wolves vanish when the
## Shaman goes down or is freed and with the wave (begin_wave / end_wave).
##
## Params: wolves, duration, bite_pct, bite_interval, leash (m around the Shaman they hunt in), surge_per_bite,
## arc_pct + arc_radius (Thunder Pack), taunt_radius + taunt_duration (Pack Guardians), slow + slow_duration.
## "power" (Ranks II / IV) scales the bites. Elemental Surge: one charge per cast, baked into every bite.
## Bot rule: no wolf alive, an enemy in range and either >= 3 enemies within 8 m, an elite / boss within 9 m or
## the Shaman below 50% HP.
## Rank III: +1 wolf. Rank V: Thunder Pack or Pack Guardians.

const BOT_CROWD := 3
const BOT_CROWD_RADIUS := 8.0
const BOT_BIG_RADIUS := 9.0
const BOT_HP := 0.5

var casts := 0
## The running pack (tests, HUD).
var wolves: Array[ShamanWolf] = []


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_alive() or not p.is_inside_tree() or ctx.target == null:
		return false
	_prune()
	if not wolves.is_empty():
		return false
	var tree := p.get_tree()
	if ShamanKit.count_around(tree, p.global_position, BOT_CROWD_RADIUS) >= BOT_CROWD:
		return true
	if ShamanKit.any_enemy(tree, p.global_position, BOT_BIG_RADIUS, func(e: Enemy) -> bool: return e.is_elite()):
		return true
	return ShamanKit.hp_ratio(p) < BOT_HP


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_alive() or not p.is_inside_tree():
		return false
	var empower := ShamanKit.empower(p)
	_prune()
	var pet_params := pet_params_for(ctx, empower)
	var life := maxf(0.5, ctx.num("duration", 10.0))
	for w in wolves:
		w.refresh(pet_params, life)
	var want := maxi(1, roundi(ctx.num("wolves", 2.0)))
	var changed := not wolves.is_empty()
	var index := 0
	while wolves.size() < want:
		while _spot_taken(index):
			index += 1
		var w := ShamanWolf.summon(p, index, pet_params, life, ctx.ability.school)
		if not w.is_inside_tree():
			w.free()
			break
		wolves.append(w)
		changed = true
	if not changed:
		return false
	casts += 1
	Vfx.floating_text(p.self_text_position(1.0), "Spirit Pack", ShamanKit.WOLF_COLOR, Player.SELF_TEXT_SIZE, 1.0)
	return true


func begin_wave(_ctx: AbilityContext) -> void:
	dismiss_all()


func end_wave(_ctx: AbilityContext) -> void:
	dismiss_all()


## What each wolf needs to know (final numbers; the damage itself follows the hero's stats).
static func pet_params_for(ctx: AbilityContext, empower: float = 1.0) -> Dictionary:
	return {
		"bite_pct": ctx.num("bite_pct", 50.0),
		"bite_interval": ctx.num("bite_interval", 1.0),
		"leash": ctx.num("leash", 8.0),
		"power": ctx.num("power", 1.0),
		"slow": ctx.num("slow"),
		"slow_duration": ctx.num("slow_duration", 1.5),
		"heal_pct": 0.0,
		"surge_per_bite": ctx.num("surge_per_bite"),
		"arc_pct": ctx.num("arc_pct"),
		"arc_radius": ctx.num("arc_radius", 3.0),
		"taunt_radius": ctx.num("taunt_radius"),
		"taunt_duration": ctx.num("taunt_duration", 1.5),
		"empower": empower,
	}


func alive_count() -> int:
	_prune()
	return wolves.size()


## Sends every wolf away at once (no puff: the wave hooks, forget, teardown).
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
