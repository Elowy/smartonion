class_name BlackMarket
extends RefCounted
## The Black Market (GDD 16.1, M6 SHOPSINKS): one expensive extra offer in the stall from wave
## [constant FIRST_WAVE] on – a gold-framed card beside the consumables row that takes no item
## offer's place. This file is the pure part (what is on offer, what it costs); [Shop] keeps the
## offer, its lock / ping / reroll and the purchase.
##
## Content ([method roll]):
##   - with [constant MAX_ROLL_CHANCE] a "max-roll" Epic: the best the generator rolls for the
##     wave – the loot budget (+25% stats, one enchant rank more, GDD 5.2 "Loot bonus") and two
##     enchants – usable by one of the team's classes;
##   - otherwise a guaranteed tier-set piece (GDD 5.5) of a class in the team, preferably a piece
##     the hero's set is still missing (not worn and not in the backpack of a hero of that class),
##     else any piece of those sets that exists at the wave; a team without such a piece (no
##     class with a set, wave before the sets) gets the max-roll Epic instead. A set piece is
##     NOT looted (no loot budget, no "Looted" tag): it is exactly the shop's piece of that wave.
## Both are Epic: the stall never sells Legendary (GDD 10). The offer's price is
## [constant PRICE_MULT] x the Epic shop price of the wave ([method price], about 570 g at wave 15
## in the GDD's numbers); the item itself keeps the normal Epic buy price, so selling it back or
## Greed rolling it is worth what any Epic is.
## The rolls take the rng they are given (Shop passes its own side rng, so the item offers of a
## seeded run do not change).

## First wave (the cleared wave of the market) the Black Market opens.
const FIRST_WAVE := 15
## Share of the offers that are a max-roll Epic (the rest are set pieces).
const MAX_ROLL_CHANCE := 0.4
## Price: this many Epic shop prices.
const PRICE_MULT := 3
## Tries to roll a max-roll Epic with two enchants (each succeeds about 40%).
const MAX_ROLL_TRIES := 12


static func is_open(wave: int) -> bool:
	return wave >= FIRST_WAVE


## Offer price at [param wave]: PRICE_MULT x the Epic shop price.
static func price(wave: int) -> int:
	return PRICE_MULT * ItemGenerator.price_for(Items.Rarity.EPIC, wave)


## The item of a Black Market offer at [param wave] for the heroes in [param slots] (null only
## when nothing could be rolled at all). Draws from [param rng]: the 40% chance first, then the
## set piece (candidates are listed in slot / piece order) or the max-roll Epic.
static func roll(wave: int, slots: Array[PlayerSlot], rng: RandomNumberGenerator) -> ItemInstance:
	wave = maxi(1, wave)
	var item: ItemInstance = null
	if rng.randf() >= MAX_ROLL_CHANCE:
		item = _roll_set_piece(wave, slots, rng)
	if item == null:
		item = _roll_max_epic(wave, slots, rng)
	if item != null:
		item.buy_price = ItemGenerator.price_for(Items.Rarity.EPIC, wave)
	return item


## Set pieces the team can use at [param wave]: [{"data": UniqueItemData, "class": ClassData,
## "missing": bool}] – every piece of the set of every team class that exists at the wave, in
## slot order then piece order, one entry per piece id. "missing" = some hero of that class
## neither wears nor carries it.
static func set_piece_candidates(wave: int, slots: Array[PlayerSlot]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Dictionary[StringName, bool] = {}
	var ordered := slots.duplicate()
	ordered.sort_custom(func(a: PlayerSlot, b: PlayerSlot) -> bool: return a.index < b.index)
	for s: PlayerSlot in ordered:
		if s == null or s.class_data == null:
			continue
		var set_data := Db.set_for_class(s.class_data.id)
		if set_data == null:
			continue
		var owned := _owned_source_ids(s)
		for piece_id in set_data.piece_ids:
			var data := Db.get_unique(piece_id)
			if not ItemGenerator.set_piece_available(data, ItemGenerator.Source.SHOP, wave) \
					or not ItemGenerator.unique_usable_by(data, s.class_data):
				continue
			var missing := not owned.has(piece_id)
			if seen.has(piece_id):
				# The same piece for a second hero of the class: missing for either counts.
				if missing:
					for entry in out:
						if entry["data"] == data:
							entry["missing"] = true
				continue
			seen[piece_id] = true
			out.append({"data": data, "class": s.class_data, "missing": missing})
	return out


## Source ids of everything [param slot]'s hero wears or carries.
static func _owned_source_ids(slot: PlayerSlot) -> Dictionary[StringName, bool]:
	var out: Dictionary[StringName, bool] = {}
	var eq: Equipment = null
	var hero := slot.player as Player
	if hero != null and is_instance_valid(hero):
		eq = hero.equipment
	if eq == null:
		return out
	for item in eq.equipped_items():
		out[item.source_id] = true
	for item in eq.backpack:
		out[item.source_id] = true
	return out


static func _roll_set_piece(wave: int, slots: Array[PlayerSlot], rng: RandomNumberGenerator) -> ItemInstance:
	var all := set_piece_candidates(wave, slots)
	if all.is_empty():
		return null
	var pool: Array[Dictionary] = []
	for c in all:
		if c["missing"]:
			pool.append(c)
	if pool.is_empty():
		pool = all
	var pick := pool[0] if pool.size() == 1 else pool[rng.randi_range(0, pool.size() - 1)]
	# Not looted: the loot budget (+25% stats, +1 enchant rank, "Looted" tag) belongs to the max-roll
	# Epic only; a set piece is the same piece the shop sells, the offer is just guaranteed.
	return ItemGenerator.from_unique(pick["data"], wave, false, rng, pick["class"])


## A loot-quality Epic with two enchants, made for a random class of the team (usable by it,
## its primary stat favoured). Hand-made Epics and set pieces are skipped (their stats and
## enchants are fixed); after MAX_ROLL_TRIES the best Epic seen is taken.
static func _roll_max_epic(wave: int, slots: Array[PlayerSlot], rng: RandomNumberGenerator) -> ItemInstance:
	var classes: Array[ClassData] = []
	for s in slots:
		if s != null and s.class_data != null and s.class_data not in classes:
			classes.append(s.class_data)
	var options := {&"rarity": Items.Rarity.EPIC}
	if not classes.is_empty():
		var target := classes[0] if classes.size() == 1 else classes[rng.randi_range(0, classes.size() - 1)]
		options[&"usable_by"] = target
		options[&"class_data"] = target
		options[&"team_classes"] = classes
	var best: ItemInstance = null
	for _i in MAX_ROLL_TRIES:
		var item := ItemGenerator.generate(ItemGenerator.Source.LOOT, wave, rng, options)
		if item == null:
			continue
		if item.set_id != &"" or item.unique:
			continue
		if best == null or item.enchants.size() > best.enchants.size():
			best = item
		if item.enchants.size() >= 2:
			break
	return best
