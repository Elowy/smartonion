class_name Heirlooms
extends RefCounted
## The Heirloom rules (M9 PATCH, design_m9 §4): the scaling formula, how the item is made and re-scaled, its rank
## perks as a bonus source, and the lobby's pick logic. The data is [HeirloomData] (Db.heirlooms), what the player
## owns and the rank are the profile's ([method Meta.heirloom_rank]), the lobby UI is LoadoutScreen, the upgrade
## shop is The Onion Patch.
##
## A hero starts a run with its picked Heirloom EQUIPPED ([method equip_at_start], called by Player.create): an
## [ItemInstance] with [member ItemInstance.heirloom_rank] > 0, which makes it BOUND – [method ItemInstance.can_sell],
## can_trade, can_disenchant are false, the Forge, the Enchanter and the team loot refuse it (see ItemInstance). Armour
## pieces take the HERO's armour type (so they count for Armor Specialization), the Ancestral Peeler takes the weapon
## type of the hero's starting weapon. [method rescale_player] re-scales every Heirloom the hero holds at the start of
## each wave (Main.start_wave), so it grows with the run but stays below a looted Epic.
##
## Formula (all starting numbers, no balance pass):
##   budget(w, r) = (2.5 + 0.5 w) x slot_mult x (1 + 0.08 (r - 1))     slot_mult: Head / Chest / Legs 1.0,
##                  Shoulders / Hands / Feet 0.8, Neck / Ring / Trinket 0.7
##   stat_i       = budget x share_i / ItemGenerator.STAT_PRICE_i       (snapped to 0.1) + the implicit Armor of the
##                  hero's armour type (ItemGenerator.implicit_armor)
##   weapon       : damage x (1 + (0.030 + 0.003 (r - 1)) w), no stats
##   item level   = 5 + 2 w + 2 (r - 1)
## Rank 3 switches on [member HeirloomData.perk3], rank 5 [member HeirloomData.perk5]: BonusVocabulary entries that run
## as the PlayerBonuses source [constant SOURCE] while the item is worn ([method effects_for], Player.apply_equipment).
## A run with nothing picked (every automated run) touches none of this: no item, no source, no random draw.

## The PlayerBonuses source of the worn Heirloom's rank perks.
const SOURCE := &"heirloom"
const BUDGET_BASE := 2.5
const BUDGET_PER_WAVE := 0.5
const BUDGET_PER_RANK := 0.08
const WEAPON_PCT := 0.030
const WEAPON_PCT_PER_RANK := 0.003
const LEVEL_BASE := 5
const LEVEL_PER_WAVE := 2
const LEVEL_PER_RANK := 2
## Slot multiplier of the budget (design_m9 §4).
const SLOT_MULT := {
	Items.SlotType.HEAD: 1.0, Items.SlotType.CHEST: 1.0, Items.SlotType.LEGS: 1.0,
	Items.SlotType.SHOULDERS: 0.8, Items.SlotType.HANDS: 0.8, Items.SlotType.FEET: 0.8,
	Items.SlotType.NECK: 0.7, Items.SlotType.RING: 0.7, Items.SlotType.TRINKET: 0.7,
}
## Rarity of the item (its look: trim colour, the glow from Epic) by rank 1 .. 5.
const RARITY_BY_RANK: Array[int] = [1, 1, 1, 2, 3]
## Stats are kept to one decimal.
const STAT_STEP := 0.1
## The waves The Onion Patch shows a preview for.
const PREVIEW_WAVES: Array[int] = [1, 10, 25]

## [method toggle] results.
const RESULT_ADDED := &"added"
const RESULT_REMOVED := &"removed"
## Not owned, or a slot the class does not have yet (Class Level 5).
const RESULT_LOCKED := &"locked"
const RESULT_NO_SLOT := &"no_slot"
const RESULT_INVALID := &"invalid"

## The tooltip / panel texts of a bound item.
const BOUND_TEXT := "Heirloom – bound to its hero"
const NO_SELL_TEXT := "Heirlooms can't be sold"
const NO_TRADE_TEXT := "Heirlooms can't be traded"


# --- The formula --------------------------------------------------------------------------------

## The slot multiplier of [param slot_type] (1.0 for an unlisted one).
static func slot_mult(slot_type: int) -> float:
	return float(SLOT_MULT.get(slot_type, 1.0))


## Stat budget in points of an Heirloom of [param slot_type] at [param wave] and [param rank].
static func budget_for(slot_type: int, wave: int, rank: int) -> float:
	return (BUDGET_BASE + BUDGET_PER_WAVE * maxi(1, wave)) * slot_mult(slot_type) \
			* (1.0 + BUDGET_PER_RANK * (clampi(rank, 1, HeirloomData.MAX_RANK) - 1))


static func budget(data: HeirloomData, wave: int, rank: int) -> float:
	return budget_for(data.slot_type, wave, rank)


## Damage multiplier of the weapon Heirloom at [param wave] and [param rank] (1.03 at wave 1 rank 1, 1.75 at wave 25,
## 2.05 at wave 25 rank 5).
static func weapon_mult(wave: int, rank: int) -> float:
	var r := clampi(rank, 1, HeirloomData.MAX_RANK)
	return 1.0 + (WEAPON_PCT + WEAPON_PCT_PER_RANK * (r - 1)) * maxi(1, wave)


static func item_level_for(wave: int, rank: int) -> int:
	return LEVEL_BASE + LEVEL_PER_WAVE * maxi(1, wave) + LEVEL_PER_RANK * (clampi(rank, 1, HeirloomData.MAX_RANK) - 1)


static func rarity_for(rank: int) -> int:
	return RARITY_BY_RANK[clampi(rank, 1, HeirloomData.MAX_RANK) - 1]


## The stats of [param data] for a hero of [param class_data] at [param wave] / [param rank]: the budget split by the
## shares, the primary share on the hero's primary stat, plus the implicit Armor of its armour type. Empty for the
## weapon (and without a class the primary share is skipped).
static func stats_for(data: HeirloomData, class_data: ClassData, wave: int, rank: int) -> Dictionary[StringName, float]:
	var out: Dictionary[StringName, float] = {}
	if data == null or data.is_weapon():
		return out
	var points := budget(data, wave, rank)
	for key in data.weights:
		var stat: StringName = key
		if key == HeirloomData.PRIMARY:
			if class_data == null:
				continue
			stat = class_data.primary_stat
		out[stat] = out.get(stat, 0.0) + points * data.weights[key] / ItemGenerator.stat_price(stat)
	for stat in out:
		out[stat] = snappedf(out[stat], STAT_STEP)
	if data.armor_rule == HeirloomData.RULE_HERO and class_data != null:
		var armor := ItemGenerator.implicit_armor(class_data.armor_type, data.slot_type, wave)
		if armor > 0:
			out[Stats.ARMOR] = out.get(Stats.ARMOR, 0.0) + armor
	return out


# --- The item -----------------------------------------------------------------------------------

## The ItemInstance of [param data] for a hero of [param class_data] at [param wave] / [param rank]. [param alt]: the
## hero starts with the class's alternative weapon (the Ancestral Peeler copies the weapon type of the one it has).
## Null when it cannot be made (the weapon without a starting weapon). No random draw.
static func create_item(data: HeirloomData, class_data: ClassData, wave: int, rank: int, alt: bool = false) -> ItemInstance:
	if data == null:
		return null
	var item: ItemInstance
	if data.is_weapon():
		var base := ClassLevels.start_main_hand(class_data, alt) if class_data != null else null
		if base == null:
			return null
		item = ItemInstance.from_weapon(base, Items.Rarity.COMMON, wave)
		item.heirloom_base_damage = base.base_damage
		item.weapon.display_name = data.display_name
	else:
		item = ItemInstance.new()
		item.slot_type = data.slot_type
		if data.armor_rule == HeirloomData.RULE_HERO and class_data != null:
			item.armor_type = class_data.armor_type
	item.source_id = data.id
	item.display_name = data.display_name
	item.flavor = data.flavor
	item.buy_price = 0
	item.heirloom_rank = clampi(rank, 1, HeirloomData.MAX_RANK)
	rescale(item, class_data, wave)
	return item


## Re-scales [param item] (an Heirloom) to [param wave] at its own rank: wave, Item Level, rarity (the look) and stats
## – or the weapon's damage. Returns false for anything that is not an Heirloom of the data.
static func rescale(item: ItemInstance, class_data: ClassData, wave: int) -> bool:
	if item == null or not item.is_heirloom():
		return false
	var data := Db.get_heirloom(item.source_id)
	if data == null:
		return false
	wave = maxi(1, wave)
	var rank := item.heirloom_rank
	item.wave = wave
	item.item_level = item_level_for(wave, rank)
	item.rarity = rarity_for(rank)
	if item.is_weapon():
		item.weapon.rarity = item.rarity
		item.weapon.base_damage = item.heirloom_base_damage * weapon_mult(wave, rank)
	else:
		item.stats = stats_for(data, class_data, wave, rank)
	return true


## The smoke log line of an Heirloom a hero holds at a wave start ("heirloom: P1 mage Sprout Cap rank 1 on wave 3, item
## level 11, equipped: +2.8 Intellect, +1.7 Stamina, +1.1 Crit"; Main prints it behind "SMOKE ").
static func log_line(slot_label: String, class_id: StringName, item: ItemInstance, equipped: bool, wave: int) -> String:
	var detail := "weapon damage %.1f" % item.weapon.base_damage if item.is_weapon() else ", ".join(PackedStringArray(stat_lines(item.stats)))
	return "heirloom: %s %s %s rank %d on wave %d, item level %d, %s: %s" % [slot_label, class_id, item.display_name,
			item.heirloom_rank, wave, item.item_level, "equipped" if equipped else "in the backpack", detail]


## The Heirlooms [param equipment] holds, equipped first, then the backpack.
static func held(equipment: Equipment) -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	if equipment == null:
		return out
	for item in equipment.equipped_items():
		if item.is_heirloom() and item not in out:
			out.append(item)
	for item in equipment.backpack:
		if item != null and item.is_heirloom() and item not in out:
			out.append(item)
	return out


## Wave start: re-scales every Heirloom [param player] holds to [param wave] (Main.start_wave, before Player.begin_wave
## heals to the new Max HP). The equipment is re-applied when one changed. Returns how many were re-scaled.
static func rescale_player(player: Player, wave: int) -> int:
	if player == null or player.equipment == null:
		return 0
	var n := 0
	for item in held(player.equipment):
		if rescale(item, player.class_data, wave):
			n += 1
	if n > 0:
		player.equipment.changed.emit()
	return n


## True when a hero of [param class_id] may start a run with [param id]: it has the slot (Class Level 5) and the
## profile owns the Heirloom (the dev and max profiles own everything).
static func available(class_id: StringName, id: StringName) -> bool:
	return Db.get_heirloom(id) != null and Meta.heirloom_slots(class_id) >= 1 \
			and Meta.is_unlocked(Profile.KIND_HEIRLOOM, id, class_id)


## Run start (Player.create): equips the Heirloom [member Player.heirloom_id] names, made for wave 1 at the rank the
## profile has. An Heirloom the hero cannot carry (unknown, not owned, no slot yet, nothing to copy) is dropped from
## [member Player.heirloom_id]. Nothing happens without a pick.
static func equip_at_start(player: Player) -> void:
	if player == null or player.heirloom_id == &"" or player.class_data == null or player.equipment == null:
		return
	var data := Db.get_heirloom(player.heirloom_id)
	if data == null or not available(player.class_data.id, data.id):
		player.heirloom_id = &""
		return
	var alt := player.slot != null and player.slot.alt_weapon
	var item := create_item(data, player.class_data, 1, maxi(1, Meta.heirloom_rank(data.id)), alt)
	# The weapon replaces the MAIN hand (a dual-wield class would otherwise get it as a second weapon in the off hand).
	var target := Items.EquipSlot.MAIN_HAND if item != null and item.is_weapon() else -1
	if item == null or not player.equipment.equip(item, target):
		player.heirloom_id = &""


## The bonus entries of the rank perks of the Heirlooms [param equipment] has EQUIPPED (a backpack one gives nothing),
## each tagged with "id" ("heirloom:<id>:perk3") and "label" (the Heirloom's name).
static func effects_for(equipment: Equipment) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if equipment == null:
		return out
	for item in equipment.equipped_items():
		if not item.is_heirloom():
			continue
		var data := Db.get_heirloom(item.source_id)
		if data == null:
			continue
		for perk: Array in [[HeirloomData.PERK3_RANK, data.perk3, "perk3"], [HeirloomData.PERK5_RANK, data.perk5, "perk5"]]:
			if item.heirloom_rank < int(perk[0]):
				continue
			for entry: Variant in perk[1]:
				var e: Dictionary = (entry as Dictionary).duplicate(true)
				e["id"] = "heirloom:%s:%s" % [data.id, perk[2]]
				e["label"] = data.display_name
				out.append(e)
	return out


# --- The lobby's selection ----------------------------------------------------------------------

## Puts [param id] on [param slot] (replacing the one it had) or takes it off when it is the pick already. Returns a
## RESULT_ constant; a change is remembered for the slot's class and saved (Meta.remember_loadout).
static func toggle(slot: PlayerSlot, id: StringName) -> StringName:
	if slot == null or slot.class_data == null or Db.get_heirloom(id) == null:
		return RESULT_INVALID
	if slot.heirloom == id:
		slot.heirloom = &""
		_remember(slot)
		return RESULT_REMOVED
	var cid := slot.class_data.id
	if Meta.heirloom_slots(cid) < 1:
		return RESULT_NO_SLOT
	if not Meta.is_unlocked(Profile.KIND_HEIRLOOM, id, cid):
		return RESULT_LOCKED
	slot.heirloom = id
	_remember(slot)
	return RESULT_ADDED


## Drops [param slot]'s Heirloom when its class cannot carry it (after a class change).
static func prune(slot: PlayerSlot) -> void:
	if slot == null or slot.class_data == null or slot.heirloom == &"":
		return
	if not available(slot.class_data.id, slot.heirloom):
		slot.heirloom = &""


static func _remember(slot: PlayerSlot) -> void:
	Meta.remember_loadout(slot)
	Meta.save()


# --- Texts for the screens ----------------------------------------------------------------------

## Short stat names for the narrow lobby panel ("+1.5 Int").
const SHORT_NAMES := {
	Stats.STRENGTH: "Str", Stats.AGILITY: "Agi", Stats.INTELLECT: "Int", Stats.STAMINA: "Sta", Stats.CRIT: "Crit",
	Stats.HASTE: "Haste", Stats.MASTERY: "Mast", Stats.VERSATILITY: "Vers", Stats.ARMOR: "Armor", Stats.DODGE: "Dodge",
	Stats.LEECH: "Leech", Stats.SPEED: "Speed", Stats.SPIRIT: "Spirit", Stats.FORTUNE: "Fort", Stats.GOLD_FIND: "Gold",
	Stats.XP_GAIN: "XP",
}


## "+1.5 Strength" style lines of [param stats] in a stable order (primary stats first); [param short]: "+1.5 Str".
static func stat_lines(stats: Dictionary, short: bool = false) -> Array[String]:
	var out: Array[String] = []
	var order: Array[StringName] = []
	for stat in stats:
		order.append(stat)
	order.sort_custom(func(a: StringName, b: StringName) -> bool:
		var ia := Stats.ALL.find(a)
		var ib := Stats.ALL.find(b)
		return ia < ib if ia != ib else String(a) < String(b))
	for stat in order:
		var label: String = SHORT_NAMES.get(stat, Stats.display_name(stat)) if short else Stats.display_name(stat)
		out.append("%s %s" % [Stats.format_value(stat, float(stats[stat])), label])
	return out


## The class a card of [param data] previews its numbers for: the class that gifts it, else the first class.
static func preview_class(data: HeirloomData) -> ClassData:
	var c := Db.get_class_data(data.gift_class) if data != null and data.gift_class != &"" else null
	return c if c != null else Db.get_default_class()


## One preview line of [param data] at [param wave] / [param rank] for [param class_data]: the stats ("+1.5 Strength
## · +0.9 Stamina · +0.6 Crit"), or "Weapon damage x1.27" for the weapon. [param short]: the short stat names,
## separated by a space (the lobby's narrow panel).
static func preview_text(data: HeirloomData, class_data: ClassData, wave: int, rank: int, short: bool = false) -> String:
	if data == null:
		return ""
	if data.is_weapon():
		return "Damage x%.2f" % weapon_mult(wave, rank) if short else "Weapon damage x%.2f" % weapon_mult(wave, rank)
	return ("  " if short else "  ·  ").join(PackedStringArray(stat_lines(stats_for(data, class_data, wave, rank), short)))


## The perk text of [param data] that applies at [param rank]'s milestone ("perk3" / "perk5") with its rank prefix.
static func perk_text(data: HeirloomData, which: int) -> String:
	if data == null:
		return ""
	return data.perk3_text if which == HeirloomData.PERK3_RANK else data.perk5_text


## Whether [param rank] has reached the perk of rank [param which] (3 or 5).
static func perk_active(rank: int, which: int) -> bool:
	return rank >= which


## The obtain hint of [param data] ("Reach Mage level 5", "Achievement: Harvest Home").
static func obtain_text(data: HeirloomData) -> String:
	return data.source_text if data != null else ""


## Every Heirloom's data problems, one pass (ids and names unique across the list); an empty array = all valid.
static func all_problems() -> Array[String]:
	var out: Array[String] = []
	var ids := {}
	var names := {}
	for id in Db.heirlooms:
		out.append_array(Db.heirlooms[id].problems(ids, names))
	return out
