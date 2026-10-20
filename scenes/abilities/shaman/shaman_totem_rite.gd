class_name ShamanTotemRite
extends AbilityEffect
## Totem Rite (M8, Shaman core, LT): plants a totem at the Shaman's feet. Each cast calls the next element
## of the cycle Fire -> Water -> Earth -> Air -> Fire ([member cycle] lives in this effect: it persists across
## waves, a new run starts at Fire); a new cast frees the previous Rite totem(s) at once. The totem rules are
## ShamanTotem's. Totem Rite never consumes an Elemental Surge charge and builds Surge like every cast.
##
## Params (rank / spec / item mods change them; the pseudo ability shaman_totems adds the talent / set /
## item mods of "all totems" on top, ShamanKit.totem_params): duration, totems (1; Twin Totems 2: a second
## totem of the next element 1.6 m to the right, the cycle moves on by two), follows (Walking Totem: the
## totem walks with the Shaman), the element numbers (fire_*, water_*, earth_*, air_*, aura_*) and
## auto_cast_range (the bot rule).
## Bot rule: an enemy within auto_cast_range and no Rite totem with more than REFRESH_WINDOW s left.

const ELEMENTS: Array[StringName] = [&"fire", &"water", &"earth", &"air"]
const NAMES: Dictionary[StringName, String] = {
	&"fire": "Fire Totem", &"water": "Water Totem", &"earth": "Earth Totem", &"air": "Air Totem",
}
## Twin Totems: the second totem stands this far to the right of the first.
const TWIN_OFFSET := 1.6
## A Rite totem with at most this many seconds left may be replaced by a bot.
const REFRESH_WINDOW := 4.0

## Index (into ELEMENTS) of the element the NEXT cast calls.
var cycle := 0
## The standing Rite totems (may hold freed nodes: use [method standing]).
var totems: Array[ShamanTotem] = []


func can_cast(ctx: AbilityContext) -> bool:
	return ctx.player != null and ctx.player.is_inside_tree()


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree():
		return false
	if not ShamanKit.any_enemy(p.get_tree(), p.global_position, ctx.num("auto_cast_range", 10.0)):
		return false
	return longest_left() <= REFRESH_WINDOW


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree():
		return false
	var params := ShamanKit.totem_params(p, ctx.params)
	var duration := maxf(1.0, float(params.get("duration", 10.0)))
	var count := clampi(roundi(float(params.get("totems", 1.0))), 1, ELEMENTS.size())
	var follows := bool(params.get("follows", false))
	clear()
	var names: Array[String] = []
	var first_color := ShamanKit.TEXT_COLOR
	for i in count:
		var element := ELEMENTS[(cycle + i) % ELEMENTS.size()]
		var at := p.global_position + Vector3(TWIN_OFFSET * float(i), 0.0, 0.0)
		var t := ShamanTotem.plant(p, element, params, at, duration, follows)
		if not t.is_inside_tree():
			t.free()
			continue
		totems.append(t)
		names.append(String(NAMES.get(element, "Totem")))
		if i == 0:
			first_color = ShamanKit.ELEMENT_COLORS.get(element, ShamanKit.TEXT_COLOR)
	if totems.is_empty():
		return false
	cycle = (cycle + count) % ELEMENTS.size()
	Vfx.floating_text(p.self_text_position(1.0), " + ".join(names), first_color, Player.SELF_TEXT_SIZE, 1.0)
	return true


func begin_wave(_ctx: AbilityContext) -> void:
	clear()


func end_wave(_ctx: AbilityContext) -> void:
	clear()


## The standing, live Rite totems (freed ones pruned).
func standing() -> Array[ShamanTotem]:
	for i in range(totems.size() - 1, -1, -1):
		if not is_instance_valid(totems[i]) or totems[i].dismissed or totems[i].is_queued_for_deletion():
			totems.remove_at(i)
	var out: Array[ShamanTotem] = []
	out.assign(totems)
	return out


## Longest time (s) any standing Rite totem has left (0 = none).
func longest_left() -> float:
	var best := 0.0
	for t in standing():
		best = maxf(best, t.time_left())
	return best


## Frees every standing Rite totem at once (a new cast, the wave hooks, forget, teardown).
func clear() -> void:
	for i in totems.size():
		# Check validity on the element itself: a freed totem must not be copied to a typed var.
		if is_instance_valid(totems[i]):
			totems[i].dismiss(true)
	totems.clear()


## The element the next cast calls.
func next_element() -> StringName:
	return ELEMENTS[cycle % ELEMENTS.size()]
