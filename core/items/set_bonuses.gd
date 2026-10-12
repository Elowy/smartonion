class_name SetBonuses
extends RefCounted
## Tier-set counting and bonuses (GDD 5.5, M5, architecture §2.4): the set pieces a hero wears
## and the active 2- / 4-piece bonuses as PlayerBonuses entries (source &"set_bonus" –
## Player.apply_equipment sets them), plus the tooltip rows and the bots' set value.
##
## Rules:
## - A piece is an item whose set_id names a SetData (Db.sets); the five pieces of a set are
##   SetData.piece_ids. Pieces are counted by Equipment.count_sets: DISTINCT pieces (source
##   ids) per set, so a duplicate of a piece never counts twice.
## - Bonuses add up: with 4 pieces the 2-piece and the 4-piece bonus are both active
##   (SetData.bonuses, each {"pieces", "text", "effects"}). There is no 5-piece bonus.
## - [method effects_for] hands every effect of every active bonus to the bonus engine with
##   "rank" 1, "id" "<set id>:<pieces>" and "label" = the set's name (the default floating text
##   of a set proc). Sets come in id order, bonuses in data order. No RNG; the engine rebuilds
##   only on equipment changes.
## - Bots value a piece that completes a 2- / 4-piece bonus (ItemTooltip.upgrade_direction via
##   [method bonus_change]); the same rule keeps them from trading an active bonus away for a
##   slightly better item. It looks ahead to the backpack (ItemTooltip.set_lookahead): pieces
##   of the same set waiting there for other slots count as worn, so a 3rd piece that makes the
##   4-piece reachable is worth as much as the 2nd one.

## Tooltip row kinds of [method describe].
const ROW_HEADER := &"header"
const ROW_PIECE := &"piece"
const ROW_BONUS := &"bonus"


## Set id -> distinct pieces of that set equipped in [param eq] (empty for null).
static func counts(eq: Equipment) -> Dictionary[StringName, int]:
	if eq == null:
		var none: Dictionary[StringName, int] = {}
		return none
	return eq.set_counts()


## The active bonus entries of [param eq] (each effect of every active bonus, deep-copied, with
## "rank": 1, "id": "<set>:<n>", "label": set name). Unknown sets (no SetData) give nothing.
static func effects_for(eq: Equipment) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var c := counts(eq)
	for set_id in _sorted_ids(c):
		var data := Db.get_set(set_id)
		if data == null:
			continue
		for bonus in active_bonuses(data, c[set_id]):
			var tag := "%s:%d" % [set_id, int(bonus.get("pieces", 0))]
			for e: Variant in bonus.get("effects", []):
				if typeof(e) != TYPE_DICTIONARY:
					continue
				var entry: Dictionary = (e as Dictionary).duplicate(true)
				entry["rank"] = 1
				entry["id"] = tag
				entry["label"] = data.display_name
				out.append(entry)
	return out


## Active set bonuses of [param eq] (SMOKE_RESULT "set_bonuses"): a 4-piece set counts 2.
static func active_count(eq: Equipment) -> int:
	return _active_total(counts(eq))


## The bonuses of [param data] that [param pieces] worn pieces activate (data order).
static func active_bonuses(data: SetData, pieces: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if data == null:
		return out
	for bonus in data.bonuses:
		var needed := int(bonus.get("pieces", 0))
		if needed > 0 and pieces >= needed:
			out.append(bonus)
	return out


## Tooltip rows for the set of [param item] as worn in [param eq] (null = nobody's equipment,
## the loot roll). Empty when the item is not a piece of a known set. In order:
##   {"kind": ROW_HEADER, "text": "Battlegear of Fury (2/5)" | "Battlegear of Fury (5 pieces)", "active": true}
##   {"kind": ROW_PIECE, "text": <piece name>, "active": worn}           – one per SetData.piece_ids
##   {"kind": ROW_BONUS, "text": "(2) Set: <text>", "active": reached}   – one per bonus
static func describe(item: ItemInstance, eq: Equipment) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if item == null or item.set_id == &"":
		return out
	var data := Db.get_set(item.set_id)
	if data == null:
		return out
	var worn := worn_pieces(eq)
	var count: int = counts(eq).get(data.id, 0)
	var total := data.piece_ids.size()
	var header := "%s (%d/%d)" % [data.display_name, count, total] if eq != null \
			else "%s (%d pieces)" % [data.display_name, total]
	out.append({"kind": ROW_HEADER, "text": header, "active": true})
	for piece_id in data.piece_ids:
		var piece := Db.get_unique(piece_id)
		var piece_name := piece.display_name if piece != null else String(piece_id).capitalize()
		out.append({"kind": ROW_PIECE, "text": piece_name, "active": piece_id in worn})
	for bonus in data.bonuses:
		var needed := int(bonus.get("pieces", 0))
		out.append({"kind": ROW_BONUS, "text": "(%d) Set: %s" % [needed, str(bonus.get("text", ""))],
			"active": eq != null and needed > 0 and count >= needed})
	return out


## Source ids of the set pieces equipped in [param eq] (empty for null).
static func worn_pieces(eq: Equipment) -> Array[StringName]:
	var out: Array[StringName] = []
	if eq == null:
		return out
	for it in eq.equipped_items():
		if it.set_id != &"" and it.source_id not in out:
			out.append(it.source_id)
	return out


## How many set bonuses of [param eq] equipping [param item] would add (> 0) or take away
## (< 0) when [param displaced] (what it pushes out – ItemTooltip.equipped_for_compare, an
## EquippedPair's parts) leaves. 0 when no threshold is crossed (e.g. neither item is a piece,
## or a duplicate replaces the same piece).
## [param lookahead]: backpack pieces the hero could put on as well (ItemTooltip.set_lookahead
## – pieces of the item's or a displaced piece's set, for other slots that hold no set piece).
## They count as worn on both sides, so the change is the item's own share of the bonuses the
## hero can reach: a 3rd piece whose 4th waits in the backpack is +1 (and so is that 4th one),
## a plain item that would push out such a 3rd piece -1. [param item] itself is skipped there.
static func bonus_change(item: ItemInstance, displaced: Array[ItemInstance], eq: Equipment,
		lookahead: Array[ItemInstance] = []) -> int:
	if item == null or eq == null:
		return 0
	var before: Array[ItemInstance] = []
	var after: Array[ItemInstance] = []
	for it in eq.equipped_items():
		before.append(it)
		if it != item and it not in displaced:
			after.append(it)
	after.append(item)
	# A lookahead piece only goes into a slot without a set piece: what it pushes out never
	# counted for a set, so leaving it in changes no count.
	for extra in lookahead:
		if extra != null and extra != item:
			before.append(extra)
			after.append(extra)
	return _active_total(Equipment.count_sets(after)) - _active_total(Equipment.count_sets(before))


## Σ active bonuses over [param c] (set id -> pieces; unknown sets count 0).
static func _active_total(c: Dictionary[StringName, int]) -> int:
	var n := 0
	for set_id in c:
		n += active_bonuses(Db.get_set(set_id), c[set_id]).size()
	return n


static func _sorted_ids(c: Dictionary[StringName, int]) -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(c.keys())
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return ids
