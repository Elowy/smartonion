class_name Forge
extends RefCounted
## Weapon forging (GDD 4.1, M5): two generated weapons with the same base (source_id) and
## rarity become one new weapon of the next rarity, freshly rolled. Used by the PlayerPanel
## "Forge" entry, the shop's auto-forge (Shop.try_buy -> BuyResult.FORGED when the buyer's
## backpack is full) and the bots (Intermission._bots_shop -> bot_forge_all). Free of charge.
##
## Rules (decided here, the callers only ask):
## - Forgeable ([method is_forgeable]): a weapon that is not hand-made (ItemInstance.unique),
##   below Legendary (so never an Artifact) and whose base is a Db weapon. Starting weapons
##   qualify (Common, not hand-made).
## - Pair: two different forgeable items with the same source_id and the same rarity.
## - Partner ([method partner_for], deterministic): the first match in the backpack (lowest
##   index), then the main hand, then the off hand; never the item itself.
## - Result ([method make_result]): ItemGenerator.generate_weapon(base, rarity + 1,
##   max(a.wave, b.wave, RunState.wave), a.looted or b.looted) – new suffix stats and enchants.
##   A Legendary result also gets the weapon type's Legendary effect (ForgeLegendaryData in
##   res://data/forge/, loaded lazily here, not by Db): its name, unique_effect /
##   unique_params / unique_text and flavor. It stays unique = false; being Legendary it can
##   never be forged again.
## - Placement: both pieces leave the Equipment (Equipment.take, unguarded); if either was
##   equipped the result takes that position (the main hand when both were), else it is
##   appended to the backpack. Same base = same hand, so the hero is never left unarmed. Taking
##   two pieces frees a place, so the result always fits ([method can_place] guards the odd
##   case of an unequippable result).
## - Every forge counts RunState.weapons_forged.
## - Bots ([method bot_forge_all]): backpack + backpack and equipped + backpack pairs (the
##   result replaces the equipped one), never two equipped weapons (dual wield – whether one
##   stronger weapon beats two is not knowable before the roll). Bots never reach the shop's
##   auto-forge: Intermission._bot_make_room sells before buying, so their backpack is never
##   full at the till (by design, architecture §2.3).
##
## Determinism: every forge is one ItemGenerator.generate_weapon call on [param rng]
## (default RunState.rng): suffix pick, the Epic+ extra secondary stat, enchant count and picks.
## Nothing else draws (partner choice, placement, bots and anvil pips are rule-based).

## Where the Legendary effects live (one ForgeLegendaryData per base weapon).
const LEGENDARY_DIR := "res://data/forge/"

## Block reasons shown on the disabled panel entry (GDD 4.1).
const REASON_NOT_WEAPON := "Only weapons can be forged"
const REASON_HAND_MADE := "Hand-made weapons cannot be forged"
const REASON_LEGENDARY := "Legendary is the highest rarity"
const REASON_ARTIFACT := "Artifacts grow on their own"
const REASON_UNKNOWN := "This weapon cannot be forged"
const REASON_NO_HERO := "No hero to forge for"
## "No other Common Dagger" (rarity name, base weapon name).
const REASON_NO_PARTNER := "No other %s %s"
const REASON_NO_ROOM := "No room for the forged weapon"

## Partner search order of the equipped hands (after the backpack).
const HANDS: Array[Items.EquipSlot] = [Items.EquipSlot.MAIN_HAND, Items.EquipSlot.OFF_HAND]
## Safety stop of bot_forge_all (every forge removes one item, so the loop ends anyway).
const MAX_BOT_FORGES := 32

## weapon_id -> its Legendary effect (filled on first use, see [method legendaries]).
static var _legendaries: Dictionary[StringName, ForgeLegendaryData] = {}
static var _legendaries_loaded := false


## A generated weapon below Legendary whose base is a Db weapon (never hand-made / Artifact).
static func is_forgeable(item: ItemInstance) -> bool:
	return item != null and item.is_weapon() and not item.unique \
		and item.rarity >= Items.Rarity.COMMON and item.rarity < Items.Rarity.LEGENDARY \
		and Db.get_weapon(item.source_id) != null


## Whether [param a] and [param b] can be forged together: two different forgeable items of
## the same base and rarity.
static func pairs_with(a: ItemInstance, b: ItemInstance) -> bool:
	return a != null and b != null and a != b and is_forgeable(a) and is_forgeable(b) \
		and a.source_id == b.source_id and a.rarity == b.rarity


## The partner [param item] would be forged with: the first match in the backpack, then the
## main hand, then the off hand; null when there is none. [param item] may be outside
## [param eq] (a shop offer).
static func partner_for(eq: Equipment, item: ItemInstance) -> ItemInstance:
	if eq == null or not is_forgeable(item):
		return null
	for other in eq.backpack:
		if pairs_with(item, other):
			return other
	for s in HANDS:
		var other := eq.get_item(s)
		if pairs_with(item, other):
			return other
	return null


## Why [param item] cannot be forged right now ("" = it can): not a weapon, an Artifact,
## Legendary, hand-made, no partner ("No other Common Dagger"), no place for the result.
static func blocked_reason(eq: Equipment, item: ItemInstance) -> String:
	if item == null or not item.is_weapon():
		return REASON_NOT_WEAPON
	if item.rarity >= Items.Rarity.ARTIFACT:
		return REASON_ARTIFACT
	if item.rarity >= Items.Rarity.LEGENDARY:
		return REASON_LEGENDARY
	if item.unique:
		return REASON_HAND_MADE
	var base := Db.get_weapon(item.source_id)
	if base == null or not is_forgeable(item):
		return REASON_UNKNOWN
	if eq == null:
		return REASON_NO_HERO
	var partner := partner_for(eq, item)
	if partner == null:
		return REASON_NO_PARTNER % [item.rarity_name(), base.display_name]
	if not can_place(eq, item, partner):
		return REASON_NO_ROOM
	return ""


## The rarity a forge of [param item] produces (-1 when it is not forgeable).
static func forged_rarity(item: ItemInstance) -> int:
	return item.rarity + 1 if is_forgeable(item) else -1


## Menu detail of the Forge entry: "→ Rare" for a forgeable weapon (partner or not), "" else.
static func result_text(item: ItemInstance) -> String:
	var r := forged_rarity(item)
	if r < 0:
		return ""
	return "→ %s" % Items.RARITY_NAMES[clampi(r, 0, Items.RARITY_NAMES.size() - 1)]


## Whether the forged weapon of [param a] + [param b] has a place in [param eq] (see the
## class doc): the equipped position it takes, or the backpack (taking a backpack piece frees
## a place).
static func can_place(eq: Equipment, a: ItemInstance, b: ItemInstance) -> bool:
	if eq == null or a == null or b == null:
		return false
	var target := _target_slot(eq, a, b)
	if target >= 0 and _equippable(eq, a, target):
		return true
	return eq.backpack.has(a) or eq.backpack.has(b) or eq.has_space()


## Forges [param item] with its partner in [param eq]; returns the result (null = refused,
## nothing changed – see [method blocked_reason]).
static func forge(eq: Equipment, item: ItemInstance, rng: RandomNumberGenerator = null) -> ItemInstance:
	if blocked_reason(eq, item) != "":
		return null
	if not eq.backpack.has(item) and _equipped_slot(eq, item) < 0:
		return null  # not this hero's weapon (the shop path is forge_with_offer): no free rarity-up
	var partner := partner_for(eq, item)
	var result := make_result(item, partner, rng)
	if result == null:
		return null
	_place(eq, item, partner, result)
	return result


## Shop auto-forge: [param offer_item] (bought, never put into the backpack) is forged with its
## partner in [param eq]; returns the result (null = no partner / no place, nothing changed).
static func forge_with_offer(eq: Equipment, offer_item: ItemInstance, rng: RandomNumberGenerator = null) -> ItemInstance:
	if eq == null or offer_item == null or eq.backpack.has(offer_item) or _equipped_slot(eq, offer_item) >= 0:
		return null
	var partner := partner_for(eq, offer_item)
	if partner == null or not can_place(eq, offer_item, partner):
		return null
	var result := make_result(offer_item, partner, rng)
	if result == null:
		return null
	_place(eq, offer_item, partner, result)
	return result


## The forged weapon of [param a] + [param b] (pure apart from the [param rng] draws; null when
## they are not a pair): the base of [param a] at rarity + 1, generated for
## max(a.wave, b.wave, RunState.wave), Looted if either was; a Legendary gets its weapon
## type's Legendary effect ([method legendary_for]).
static func make_result(a: ItemInstance, b: ItemInstance, rng: RandomNumberGenerator) -> ItemInstance:
	if not pairs_with(a, b):
		return null
	var base := Db.get_weapon(a.source_id)
	var rarity := a.rarity + 1
	var wave := maxi(maxi(a.wave, b.wave), RunState.wave)
	var item := ItemGenerator.generate_weapon(base, rarity, wave, a.looted or b.looted,
			rng if rng != null else RunState.rng)
	if item != null and rarity >= Items.Rarity.LEGENDARY:
		apply_legendary(item, legendary_for(base.id))
	return item


## Turns a generated Legendary [param item] into its weapon type's forged Legendary: name,
## effect, effect text and flavor of [param data] (stats and enchants stay as rolled).
static func apply_legendary(item: ItemInstance, data: ForgeLegendaryData) -> void:
	if item == null:
		return
	if data == null:
		push_warning("Forge: no Legendary effect for %s" % item.source_id)
		return
	item.display_name = data.display_name
	item.unique_effect = data.unique_effect
	item.unique_params = data.unique_params.duplicate(true)
	item.unique_text = data.unique_text
	item.flavor = data.flavor


## Slot indices of the players in [param slots] for whom [param offer_item] has a forge
## partner (the shop's anvil pips) – with a full backpack or not.
static func offer_forge_slots(offer_item: ItemInstance, slots: Array[PlayerSlot]) -> Array[int]:
	var out: Array[int] = []
	if not is_forgeable(offer_item):
		return out
	for s in slots:
		var eq := _equipment_of(s)
		if eq != null and partner_for(eq, offer_item) != null:
			out.append(s.index)
	return out


## Bot forging between waves: forges every backpack weapon that has a partner (another
## backpack weapon or an equipped one, whose position the result takes) until no pair is left;
## two equipped weapons are never forged together. Returns the forges done.
static func bot_forge_all(slot: PlayerSlot) -> int:
	var eq := _equipment_of(slot)
	if eq == null:
		return 0
	var done := 0
	while done < MAX_BOT_FORGES:
		var next: ItemInstance = null
		for item in eq.backpack:
			if blocked_reason(eq, item) == "":
				next = item
				break
		if next == null or forge(eq, next) == null:
			break
		done += 1
	return done


## Every Legendary effect by base weapon id (res://data/forge/, loaded on first use).
static func legendaries() -> Dictionary[StringName, ForgeLegendaryData]:
	if not _legendaries_loaded:
		_legendaries_loaded = true
		_legendaries.clear()
		var files := ResourceLoader.list_directory(LEGENDARY_DIR)
		files.sort()
		for file in files:
			# Exported builds list "x.tres.remap"; ResourceLoader resolves the original name.
			var file_name := file.trim_suffix(".remap")
			if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
				continue
			var data := load(LEGENDARY_DIR + file_name) as ForgeLegendaryData
			if data == null:
				push_error("Forge: %s is not a ForgeLegendaryData" % (LEGENDARY_DIR + file_name))
			elif _legendaries.has(data.weapon_id):
				push_error("Forge: two Legendary effects for %s" % data.weapon_id)
			else:
				_legendaries[data.weapon_id] = data
	return _legendaries


## The Legendary effect of base weapon [param weapon_id] (null = none).
static func legendary_for(weapon_id: StringName) -> ForgeLegendaryData:
	return legendaries().get(weapon_id)


# --- Helpers -----------------------------------------------------------------------------------

## Takes both pieces and puts [param result] where the class doc says.
static func _place(eq: Equipment, a: ItemInstance, b: ItemInstance, result: ItemInstance) -> void:
	var target := _target_slot(eq, a, b)
	if target >= 0 and not _equippable(eq, a, target):
		target = -1
	eq.take(a)
	eq.take(b)
	RunState.weapons_forged += 1
	if target >= 0 and eq.equip(result, target):
		return
	if not eq.add_to_backpack(result):
		push_error("Forge: no place for %s" % result.display_name)


## The equipped position the result takes: the main hand if either piece holds it, else the
## position of the equipped piece, -1 when neither is equipped.
static func _target_slot(eq: Equipment, a: ItemInstance, b: ItemInstance) -> int:
	var sa := _equipped_slot(eq, a)
	var sb := _equipped_slot(eq, b)
	if sa == Items.EquipSlot.MAIN_HAND or sb == Items.EquipSlot.MAIN_HAND:
		return Items.EquipSlot.MAIN_HAND
	return sa if sa >= 0 else sb


static func _equipped_slot(eq: Equipment, item: ItemInstance) -> int:
	if item == null:
		return -1
	for s in HANDS:
		if eq.get_item(s) == item:
			return s
	return -1


## Whether a weapon of [param item]'s base may go to [param equip_slot] for this class (the
## result has the same base, so [param item] answers for it).
static func _equippable(eq: Equipment, item: ItemInstance, equip_slot: int) -> bool:
	return eq.can_equip(item) and equip_slot in eq.target_slots(item)


static func _equipment_of(slot: PlayerSlot) -> Equipment:
	if slot == null:
		return null
	var p := slot.player as Player
	if p == null or not is_instance_valid(p):
		return null
	return p.equipment
