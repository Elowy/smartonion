class_name Consumables
extends RefCounted
## Shop consumables (GDD 10 / 16.1, M6 SHOPSINKS): the pure rules around [ConsumableData] –
## prices, the stall's row draw, the "one potion + one food pending per hero" rule, the effect
## texts, and applying / clearing the effects of a hero. Nothing here is a node; the hero keeps
## the two lists ([member Player.consumables_pending], [member Player.consumables_active]).
##
## Life cycle of a consumable (one hero, one wave):
##   bought in the market  -> [method give]: it becomes the hero's pending POTION / FOOD (a newer one
##                            of the same kind replaces the pending one, no refund);
##   next wave starts      -> [method apply] (Player.wave_began, i.e. after begin_wave reset
##                            everything): pending -> active, the effects of the active ones go
##                            into PlayerBonuses under [constant SOURCE]; a Max HP bonus is
##                            filled up at once (the HP the bigger Max HP adds);
##   that wave ends        -> [method clear] (Player.wave_ended): active -> nothing, the source is
##                            emptied, so the market never shows an expired buff.
## Effects are BonusVocabulary entries (damage / damage_taken / stats ...). One extension: a
## "stats_pct" dictionary on a "stats" entry gives stats as a share of the hero's current value
## ({"armor": 30.0} = +30% of the Armor the hero has, {"max_hp": 15.0} = Stamina worth 15% of the
## Max HP); [method resolve_effects] turns it into plain "stats" before the engine sees it.
## Prices: base price x the shop price multiplier of the cleared wave (ItemGenerator.price_for).
## No RNG in here except the row draw, which takes the rng it is given.

## PlayerBonuses source name of the active consumables.
const SOURCE := &"consumable"
## Cards in the stall's consumables row.
const ROW_SIZE := 4
## Rounding of a resolved percentage stat (HP / Armor come in tenths).
const PCT_STEP := 0.1


## Gold for [param data] at the shop price multiplier of [param wave] (1 + 0.08 x (wave - 1)).
static func price(data: ConsumableData, wave: int) -> int:
	if data == null:
		return 0
	return maxi(1, roundi(data.base_price * (1.0 + ItemGenerator.PRICE_GROWTH * (maxi(1, wave) - 1))))


## Every consumable the stall may sell (Db.consumables, unlocked), in id order.
static func pool() -> Array[ConsumableData]:
	var out: Array[ConsumableData] = []
	for id: StringName in Db.consumables:
		if Db.is_unlocked(id):
			out.append(Db.consumables[id])
	# By the id's text (a StringName sorts by address, which is not stable between runs).
	out.sort_custom(func(a: ConsumableData, b: ConsumableData) -> bool: return String(a.id) < String(b.id))
	return out


## [param count] DIFFERENT random consumables from [method pool] ([param rng] draws one
## randi_range per pick; fewer when the pool is smaller).
static func roll_row(rng: RandomNumberGenerator, count: int = ROW_SIZE) -> Array[ConsumableData]:
	var bag := pool()
	var out: Array[ConsumableData] = []
	while out.size() < count and not bag.is_empty():
		out.append(bag.pop_at(rng.randi_range(0, bag.size() - 1)))
	return out


# --- The pending rule ----------------------------------------------------------------------

## Puts [param data] into [param pending] under the "one POTION + one FOOD" rule: the pending
## one of the same kind makes room (it is returned, null when nothing was replaced – no refund).
## The list stays in kind order (potion first).
static func queue(pending: Array[ConsumableData], data: ConsumableData) -> ConsumableData:
	var replaced: ConsumableData = null
	if data == null:
		return null
	for i in pending.size():
		if pending[i].kind == data.kind:
			replaced = pending[i]
			pending.remove_at(i)
			break
	pending.append(data)
	pending.sort_custom(func(a: ConsumableData, b: ConsumableData) -> bool: return a.kind < b.kind)
	return replaced


## The pending (or active) consumable of [param kind] in [param list] (null = none).
static func of_kind(list: Array[ConsumableData], kind: ConsumableData.Kind) -> ConsumableData:
	for c in list:
		if c.kind == kind:
			return c
	return null


## [param data] becomes [param player]'s pending POTION / FOOD ([method queue]); returns the
## replaced one (null = none). The hero's [signal Player.consumables_changed] fires.
static func give(player: Player, data: ConsumableData) -> ConsumableData:
	if player == null or data == null:
		return null
	var replaced := queue(player.consumables_pending, data)
	player.consumables_changed.emit()
	return replaced


# --- Applying / clearing ---------------------------------------------------------------------

## Wave start (after Player.begin_wave): the pending consumables become active and their
## effects go into [param player]'s bonuses; the HP a bigger Max HP adds is filled up.
static func apply(player: Player) -> void:
	if player == null or not is_instance_valid(player) or player.bonuses == null:
		return
	var had_effects := not player.consumables_active.is_empty()
	if had_effects:
		player.consumables_active.clear()
		player.bonuses.set_effects(SOURCE, [] as Array[Dictionary])
	if player.consumables_pending.is_empty():
		if had_effects:
			player.consumables_changed.emit()
		return
	player.consumables_active = player.consumables_pending.duplicate()
	player.consumables_pending.clear()
	var before := player.max_hp()
	var entries: Array[Dictionary] = []
	for data in player.consumables_active:
		entries.append_array(resolve_effects(data, player))
	player.bonuses.set_effects(SOURCE, entries)
	var gain := player.max_hp() - before
	if gain > 0.0:
		player.fill_hp(gain)
	player.consumables_changed.emit()


## Wave end: the active consumables are gone, their source is emptied.
static func clear(player: Player) -> void:
	if player == null or not is_instance_valid(player) or player.bonuses == null:
		return
	if player.consumables_active.is_empty():
		return
	player.consumables_active.clear()
	player.bonuses.set_effects(SOURCE, [] as Array[Dictionary])
	player.consumables_changed.emit()


## The bonus entries of [param data] for [param player]: "stats_pct" resolved against the hero's
## current stats (the hero's stats without any consumable on them), "id" / "label" added.
static func resolve_effects(data: ConsumableData, player: Player) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if data == null:
		return out
	for raw in data.effects:
		var e: Dictionary = raw.duplicate(true)
		if e.has("stats_pct"):
			var pct: Dictionary = e["stats_pct"]
			e.erase("stats_pct")
			var stats: Dictionary = (e.get("stats", {}) as Dictionary).duplicate()
			for key: Variant in pct:
				var stat := _stat_of(String(key))
				var base := player.max_hp() if String(key) == "max_hp" else player.stats.get_stat(stat)
				var add := snappedf(base * float(pct[key]) / 100.0, PCT_STEP)
				stats[stat] = float(stats.get(stat, 0.0)) + add
			e["stats"] = stats
		e["id"] = String(data.id)
		e["label"] = data.display_name
		out.append(e)
	return out


## The stat a "stats_pct" key stands for ("max_hp" is Stamina).
static func _stat_of(key: String) -> StringName:
	return Stats.STAMINA if key == "max_hp" else StringName(key)


# --- Texts -------------------------------------------------------------------------------------

## "Potion" / "Food".
static func kind_name(data: ConsumableData) -> String:
	if data == null:
		return ""
	return "Potion" if data.is_potion() else "Food"


## The effect lines of [param data] ("+15% Damage", "+30% Armor", "+10% Haste", "-8% Damage taken").
static func effect_lines(data: ConsumableData) -> Array[String]:
	var out: Array[String] = []
	if data == null:
		return out
	for e in data.effects:
		match String(e.get("kind", "")):
			"damage":
				out.append("%s Damage" % _signed(float(e.get("pct", 0.0)), true))
			"damage_taken":
				out.append("%s Damage taken" % _signed(float(e.get("pct", 0.0)), true))
			"stats":
				var pct: Dictionary = e.get("stats_pct", {})
				for key: Variant in pct:
					var name := "Max HP" if String(key) == "max_hp" else Stats.display_name(StringName(key))
					out.append("%s %s" % [_signed(float(pct[key]), true), name])
				var stats: Dictionary = e.get("stats", {})
				for key: Variant in stats:
					var stat := StringName(key)
					out.append("%s %s" % [Stats.format_value(stat, float(stats[key])), Stats.display_name(stat)])
	return out


## The effect lines on one line ("+10% Haste, +10% Speed").
static func summary(data: ConsumableData) -> String:
	return ", ".join(effect_lines(data))


static func _signed(value: float, percent: bool) -> String:
	var text := str(int(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value
	return ("+" if value >= 0.0 else "") + text + ("%" if percent else "")
