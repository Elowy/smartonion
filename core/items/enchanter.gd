class_name Enchanter
extends RefCounted
## Arcane Dust and the Enchanter (GDD 5.7, M6a). Pure rules + the spending; the UI (the
## PlayerPanel "Disenchant" entry, the Enchanter tab, the loot roll's Pass outcome, the bots)
## only asks.
##
## Dust sources:
## - [method disenchant] – a backpack item becomes team Dust ([method dust_for]: Common 1,
##   Uncommon 2, Rare 4, Epic 8, Legendary 16). Artifacts never ([method disenchant_blocked_reason]).
## - [method disenchant_lost_item] – an item nobody wanted (LootRoll: everybody Passed) becomes Dust
##   without a backpack.
##
## Enchanter actions on one of a hero's items (equipped or in the backpack), all through
## [method perform]:
## - REROLL: one enchant is replaced by a new random one that fits the item (the existing
##   ItemGenerator.enchant_fits rules, not one the item already has), at the SAME rank. Weighted
##   like the generator (Attack / Spell Power follow the hero's class).
## - EMPOWER: one enchant gains a rank, up to V (EnchantData.RANK_MULT x1 .. x3).
## - IMBUE: an Uncommon+ item with fewer enchants than its rarity allows ([method max_enchants]) gets
##   a new random one, at the rank the generator would give it (ItemGenerator.enchant_rank).
## Price of ANY action on an item: gold = [constant GOLD_SHARE] of the shop price of its rarity at
## the current wave x 2^uses, Dust = [method dust_for] x 2^uses; [member ItemInstance.enchant_uses]
## counts the actions done on this item (so the n-th costs twice the (n-1)-th – the open-ended
## gold sink). Gold and Dust are both checked before either is spent; the gold goes through
## RunState.try_spend_for and the Dust through RunState.try_spend_dust_for, kind &"enchant".
## After a change the hero's Equipment emits `changed` (stats and procs rebuild, the panels
## refresh) and the item's name prefix follows its first enchant (Forge-made Legendaries and
## hand-made items keep their names).
##
## Determinism: every REROLL / IMBUE is one RunState.rng.randf() (the weighted pick); EMPOWER and the
## prices draw nothing. Bots ([method bot_enchant]) are rule-based.

enum Action { REROLL, EMPOWER, IMBUE }

## Gold per action: this share of the item's shop price at the current wave.
const GOLD_SHARE := 0.25
## Disenchant yield by rarity index (Common .. Legendary); Artifacts give nothing (never disenchanted).
const DUST_BY_RARITY: Array[int] = [1, 2, 4, 8, 16]
## The doubling stops here (keeps the price inside an int however long a run goes on).
const MAX_DOUBLINGS := 24
## Spend kind of the gold and Dust of an action.
const SPEND_KIND := &"enchant"
## Enchants an item of each rarity index may hold (GDD 5.2): Common none, Uncommon 1, Rare 1,
## Epic 2, Legendary 2, Artifact none (it is not enchanted).
const MAX_ENCHANTS: Array[int] = [0, 1, 1, 2, 2, 0]

## Bots: from this wave on they enchant (and disenchant their spare items to pay for it).
const BOT_FIRST_WAVE := 12
## Actions a bot does per market round at most.
const BOT_MAX_ACTIONS := 2
## A bot without an enchantable weapon (it wears an Artifact) works on equipped armour / off-hand
## of at least this rarity ([method bot_target]).
const BOT_FALLBACK_MIN_RARITY := Items.Rarity.EPIC

const REASON_NO_ITEM := "No item"
const REASON_ARTIFACT := "Artifacts cannot be changed"
const REASON_BOUND := "Heirlooms cannot be changed"
const REASON_NOT_YOURS := "Not one of your items"
const REASON_COMMON := "Common items hold no enchants"
const REASON_NO_ENCHANTS := "No enchants to change"
const REASON_PICK_ENCHANT := "Pick an enchant"
const REASON_MAX_RANK := "Already Rank V"
const REASON_NO_OTHER := "No other enchant fits this item"
const REASON_FULL := "No free enchant slot"
const REASON_NO_FIT := "No enchant fits this item"
const REASON_POOR_GOLD := "Not enough gold"
const REASON_POOR_DUST := "Not enough Dust"
const REASON_POOR_BOTH := "Not enough gold and Dust"


## What [method perform] did (or why not).
class Outcome:
	extends RefCounted
	var ok := false
	## Why it did not happen ("" when ok).
	var reason := ""
	var action := Action.REROLL
	var item: ItemInstance
	## Enchant index the action worked on (the new one for IMBUE).
	var index := -1
	## The enchant before (null for IMBUE) and after, as [EnchantRoll] copies.
	var before: EnchantRoll
	var after: EnchantRoll
	var gold := 0
	var dust := 0
	## "Reroll Blazing (8 Dust)" style text for the purse ticker; "Empower Blazing to Rank IV" etc.
	var label := ""


# --- Dust from items ---------------------------------------------------------------------------

## Dust a Disenchant of [param item] gives (0 for nothing / an Artifact).
static func dust_for(item: ItemInstance) -> int:
	if item == null or not item.can_disenchant():
		return 0
	return DUST_BY_RARITY[clampi(item.rarity, 0, DUST_BY_RARITY.size() - 1)]


static func can_disenchant(item: ItemInstance) -> bool:
	return disenchant_blocked_reason(item) == ""


## Why [param item] cannot be disenchanted ("" = it can): only Artifacts are kept.
static func disenchant_blocked_reason(item: ItemInstance) -> String:
	if item == null:
		return REASON_NO_ITEM
	if item.is_bound():  # (M9 PATCH)
		return "Heirlooms cannot be disenchanted"
	if not item.can_disenchant():  # the one rule of the item (ARTIFACTS: an Artifact never)
		return "Artifacts cannot be disenchanted"
	return ""


## Disenchants backpack item [param item] of [param eq] for slot [param slot_index]: it leaves the
## backpack (Equipment.remove_from_backpack, which keeps the hero's last weapon) and its Dust goes
## to the team pile. Returns the Dust (0 = refused, nothing changed).
static func disenchant(eq: Equipment, item: ItemInstance, slot_index: int = -1) -> int:
	if eq == null or not can_disenchant(item) or not eq.backpack.has(item):
		return 0
	if not eq.remove_from_backpack(item):
		return 0
	var dust := dust_for(item)
	RunState.add_dust(dust, slot_index, item.display_name)
	return dust


## An item nobody wanted (everybody Passed on it): its Dust goes to the team pile. Returns the Dust
## (0 for an Artifact: it is lost as before).
static func disenchant_lost_item(item: ItemInstance) -> int:
	var dust := dust_for(item)
	if dust > 0:
		RunState.add_dust(dust, -1, item.display_name)
	return dust


# --- Prices ------------------------------------------------------------------------------------

## 2^[member ItemInstance.enchant_uses] (capped at MAX_DOUBLINGS).
static func multiplier(item: ItemInstance) -> int:
	return 1 << mini(maxi(0, item.enchant_uses if item != null else 0), MAX_DOUBLINGS)


## Gold of the next action on [param item]: 25% of its shop price at [param wave] (-1 = the current
## wave) x 2^uses; at least 1.
static func gold_price(item: ItemInstance, wave: int = -1) -> int:
	if item == null:
		return 0
	var shop := ItemGenerator.price_for(item.rarity, RunState.wave if wave < 0 else wave)
	return Difficulty.price(maxi(1, roundi(shop * GOLD_SHARE * multiplier(item))))  # (M9: the tier's shop prices)


## Dust of the next action on [param item]: the rarity's Dust x 2^uses.
static func dust_price(item: ItemInstance) -> int:
	if item == null:
		return 0
	return maxi(1, DUST_BY_RARITY[clampi(item.rarity, 0, DUST_BY_RARITY.size() - 1)]) * multiplier(item)


## "48 g + 8 Dust".
static func price_text(item: ItemInstance) -> String:
	return "%s g + %d Dust" % [UiTheme.format_int(gold_price(item)), dust_price(item)]


## Why the wallet cannot pay the next action on [param item] ("" = it can).
static func afford_reason(item: ItemInstance) -> String:
	if item == null:
		return REASON_NO_ITEM
	var poor_gold := not RunState.can_afford(gold_price(item))
	var poor_dust := not RunState.can_afford_dust(dust_price(item))
	if poor_gold and poor_dust:
		return REASON_POOR_BOTH
	if poor_gold:
		return REASON_POOR_GOLD
	if poor_dust:
		return REASON_POOR_DUST
	return ""


# --- Rules -------------------------------------------------------------------------------------

## How many enchants an item of [param rarity] may hold.
static func max_enchants(rarity: int) -> int:
	return MAX_ENCHANTS[clampi(rarity, 0, MAX_ENCHANTS.size() - 1)]


## Whether Imbue could add an enchant now (a free slot and at least one that fits), ignoring cost.
static func can_imbue(item: ItemInstance) -> bool:
	return blocked_reason(item, Action.IMBUE) == ""


## Whether [param item] is one the Enchanter can do anything with now: Reroll / Empower on an
## enchant it has or Imbue into a free slot (cost ignored).
static func is_enchantable(item: ItemInstance) -> bool:
	if item == null or item.rarity >= Items.Rarity.ARTIFACT or item.is_bound():
		return false
	for i in item.enchants.size():
		if blocked_reason(item, Action.REROLL, i) == "" or blocked_reason(item, Action.EMPOWER, i) == "":
			return true
	return can_imbue(item)


## Why [param action] on [param item] (enchant [param index] for Reroll / Empower) cannot happen,
## whatever the wallet holds ("" = it can).
static func blocked_reason(item: ItemInstance, action: Action, index: int = -1) -> String:
	if item == null:
		return REASON_NO_ITEM
	if item.is_bound():  # (M9 PATCH: an Heirloom takes no enchants)
		return REASON_BOUND
	if item.rarity >= Items.Rarity.ARTIFACT:
		return REASON_ARTIFACT
	match action:
		Action.IMBUE:
			if item.rarity < Items.Rarity.UNCOMMON:
				return REASON_COMMON
			if item.enchants.size() >= max_enchants(item.rarity):
				return REASON_FULL
			if imbue_pool(item).is_empty():
				return REASON_NO_FIT
		Action.REROLL, Action.EMPOWER:
			if item.enchants.is_empty():
				return REASON_COMMON if item.rarity < Items.Rarity.UNCOMMON else REASON_NO_ENCHANTS
			if index < 0 or index >= item.enchants.size():
				return REASON_PICK_ENCHANT
			if action == Action.EMPOWER and item.enchants[index].rank >= EnchantData.MAX_RANK:
				return REASON_MAX_RANK
			if action == Action.REROLL and reroll_pool(item, index).is_empty():
				return REASON_NO_OTHER
	return ""


## The enchants that may replace enchant [param index] of [param item]: every Db enchant the item
## may roll (ItemGenerator.enchant_fits, weight > 0) that it does not already carry.
static func reroll_pool(item: ItemInstance, index: int) -> Array[EnchantData]:
	var have: Array[StringName] = []
	if item != null:
		for i in item.enchants.size():
			if item.enchants[i].enchant != null:
				have.append(item.enchants[i].enchant.id)
	return _pool(item, have)


## The enchants Imbue may add to [param item] (fit, weight > 0, not already carried).
static func imbue_pool(item: ItemInstance) -> Array[EnchantData]:
	return reroll_pool(item, -1)


## Weighted pick of one of [param pool] like the generator (Attack / Spell Power by [param for_class]).
## Draws one RunState-style random number from [param rng]; null for an empty pool.
static func pick(pool: Array[EnchantData], rng: RandomNumberGenerator, for_class: ClassData = null) -> EnchantData:
	var weights: Array[float] = []
	for e in pool:
		weights.append(e.weight * ItemGenerator.power_enchant_weight(e, for_class))
	var total := 0.0
	for w in weights:
		total += maxf(w, 0.0)
	if total <= 0.0:
		return null
	var x := rng.randf() * total
	var last := -1
	for i in weights.size():
		if weights[i] <= 0.0:
			continue
		last = i
		x -= weights[i]
		if x < 0.0:
			return pool[i]
	return pool[last]


# --- Doing it ----------------------------------------------------------------------------------

## Whether [param item] is one of [param eq]'s items (backpack or worn).
static func owns(eq: Equipment, item: ItemInstance) -> bool:
	if eq == null or item == null:
		return false
	return eq.backpack.has(item) or item in eq.equipped_items()


## Does [param action] on [param item] (enchant [param index] for Reroll / Empower) for slot
## [param slot_index]: checks the rules and the wallet (gold AND Dust), pays both, changes the
## item, counts the use (price x 2 next time) and RunState.enchants_done and emits
## Equipment.changed on [param eq]. [param rng] defaults to RunState.rng. A refused action changes
## and spends nothing ([member Outcome.reason] says why).
static func perform(eq: Equipment, slot_index: int, item: ItemInstance, action: Action, index: int = -1,
		rng: RandomNumberGenerator = null) -> Outcome:
	var out := Outcome.new()
	out.action = action
	out.item = item
	out.index = index
	if item == null:
		out.reason = REASON_NO_ITEM
		return out
	if not owns(eq, item):
		out.reason = REASON_NOT_YOURS
		return out
	out.reason = blocked_reason(item, action, index)
	if out.reason != "":
		return out
	out.reason = afford_reason(item)
	if out.reason != "":
		return out
	out.gold = gold_price(item)
	out.dust = dust_price(item)
	var generator := rng if rng != null else RunState.rng
	# Decide what changes first (the only random draw), then pay, then change the item.
	var chosen: EnchantData = null
	match action:
		Action.REROLL:
			chosen = pick(reroll_pool(item, index), generator, eq.class_data)
			out.before = _copy(item.enchants[index])
		Action.EMPOWER:
			out.before = _copy(item.enchants[index])
		Action.IMBUE:
			chosen = pick(imbue_pool(item), generator, eq.class_data)
	if action != Action.EMPOWER and chosen == null:
		out.reason = REASON_NO_FIT if action == Action.IMBUE else REASON_NO_OTHER
		return out
	var subject_enchant: EnchantData = out.before.enchant if out.before != null else chosen
	var subject := subject_enchant.prefix if subject_enchant.prefix != "" \
			else String(subject_enchant.id).capitalize()
	var verb: String = ["Reroll", "Empower", "Imbue"][action]
	var base_label := "%s %s" % [verb, subject]
	# Both were checked affordable above: neither spend can fail now.
	if not RunState.try_spend_for(out.gold, slot_index, SPEND_KIND, "%s (%d Dust)" % [base_label, out.dust]):
		out.reason = REASON_POOR_GOLD
		return out
	if not RunState.try_spend_dust_for(out.dust, slot_index, SPEND_KIND, base_label):
		RunState.add_gold(out.gold)  # unreachable; never keep the gold of a refused action
		out.reason = REASON_POOR_DUST
		return out
	var old_prefix := name_prefix(item)
	match action:
		Action.REROLL:
			item.enchants[index] = EnchantRoll.new(chosen, item.enchants[index].rank)
		Action.EMPOWER:
			item.enchants[index].rank += 1
		Action.IMBUE:
			item.enchants.append(EnchantRoll.new(chosen, ItemGenerator.enchant_rank(item.wave, item.looted)))
			out.index = item.enchants.size() - 1
	out.after = _copy(item.enchants[out.index])
	item.enchant_uses += 1
	RunState.enchants_done += 1
	refresh_name(item, old_prefix)
	out.ok = true
	out.reason = ""
	out.label = base_label
	eq.changed.emit()
	return out


## The first enchant prefix of [param item] ("Blazing"; "" when none has one) – the word its
## generated name starts with.
static func name_prefix(item: ItemInstance) -> String:
	if item != null:
		for roll in item.enchants:
			if roll.enchant != null and roll.enchant.prefix != "":
				return roll.enchant.prefix
	return ""


## Keeps a generated item's name in step with its enchants after a change: the old first prefix
## ([param old_prefix]) is swapped for the new one. Hand-made items and Forge-made Legendaries
## (unique / unique_effect) and names that do not start with the old prefix stay as they are.
static func refresh_name(item: ItemInstance, old_prefix: String) -> void:
	if item == null or item.unique or item.unique_effect != &"":
		return
	var new_prefix := name_prefix(item)
	if new_prefix == old_prefix:
		return
	var text := item.display_name
	if old_prefix != "":
		if not text.begins_with(old_prefix + " "):
			return
		text = text.substr(old_prefix.length() + 1)
	item.display_name = ("%s %s" % [new_prefix, text]) if new_prefix != "" else text


# --- Bots --------------------------------------------------------------------------------------

## The weapon a bot enchants: its best attacking weapon (higher rarity, then Item Level, then the
## main hand), equipped. An Artifact and a bound Heirloom (the Ancestral Peeler) are skipped (neither
## can be enchanted, see [method bot_target] for what the bot works on instead). Null without one.
static func best_weapon(eq: Equipment) -> ItemInstance:
	if eq == null:
		return null
	var best: ItemInstance = null
	for hand in [Items.EquipSlot.MAIN_HAND, Items.EquipSlot.OFF_HAND]:
		var item := eq.get_item(hand)
		if not Equipment.is_attacking_weapon(item) or item.rarity >= Items.Rarity.ARTIFACT or item.is_bound():
			continue
		if best == null or item.rarity > best.rarity or (item.rarity == best.rarity and item.item_level > best.item_level):
			best = item
	return best


## What a bot enchants: its [method best_weapon]; when it has none besides an Artifact (a hero
## wearing the class Artifact, the pair included) the best other equipped non-Artifact item that
## is Epic or better and still has something for [method bot_plan] to do – an armour or jewellery
## piece or a non-attacking off-hand (higher rarity, then Item Level, then the lower equip slot).
## Null when there is nothing to work on.
static func bot_target(eq: Equipment) -> ItemInstance:
	var weapon := best_weapon(eq)
	if weapon != null or eq == null:
		return weapon
	var best: ItemInstance = null
	for equip_slot in Items.EquipSlot.values():
		var item := eq.get_item(equip_slot)
		if item == null or item.rarity < BOT_FALLBACK_MIN_RARITY or item.rarity >= Items.Rarity.ARTIFACT:
			continue
		if Equipment.is_attacking_weapon(item) or bot_plan(item, eq.class_data).is_empty():
			continue
		if best == null or item.rarity > best.rarity or (item.rarity == best.rarity and item.item_level > best.item_level):
			best = item
	return best


## What a bot does next on [param item] for [param class_data]: a Reroll of an enchant the class
## cannot use (Attack Power on a Spell Power class and the other way round), else Imbue (a free
## slot), else Empower of its lowest-ranked enchant. {} when nothing is possible. No randomness.
static func bot_plan(item: ItemInstance, class_data: ClassData) -> Dictionary:
	if item == null or item.rarity >= Items.Rarity.ARTIFACT or item.is_bound():
		return {}
	for i in item.enchants.size():
		var e := item.enchants[i].enchant
		if e != null and ItemGenerator.power_enchant_weight(e, class_data) < 1.0 \
				and blocked_reason(item, Action.REROLL, i) == "":
			return {"action": Action.REROLL, "index": i}
	if blocked_reason(item, Action.IMBUE) == "":
		return {"action": Action.IMBUE, "index": -1}
	var lowest := -1
	for i in item.enchants.size():
		if blocked_reason(item, Action.EMPOWER, i) != "":
			continue
		if lowest < 0 or item.enchants[i].rank < item.enchants[lowest].rank:
			lowest = i
	if lowest >= 0:
		return {"action": Action.EMPOWER, "index": lowest}
	return {}


## A bot's enchanting round: up to BOT_MAX_ACTIONS actions on its [method bot_target] ([method bot_plan]),
## each only while its gold stays inside [param gold_budget]; when the Dust pile is short for the
## next action the bot disenchants spare backpack items (not upgrades for it, never the last
## weapon – [method bot_disenchant_spare]) to make up the difference. Returns the actions done.
static func bot_enchant(slot: PlayerSlot, gold_budget: int, rng: RandomNumberGenerator = null) -> int:
	var eq := _equipment_of(slot)
	var item := bot_target(eq)
	if item == null:
		return 0
	var done := 0
	var budget := gold_budget
	while done < BOT_MAX_ACTIONS:
		var plan := bot_plan(item, eq.class_data)
		if plan.is_empty():
			break
		var gold := gold_price(item)
		if gold > budget or not RunState.can_afford(gold):
			break
		var need := dust_price(item) - RunState.arcane_dust
		if need > 0:
			bot_disenchant_spare(slot, eq, need)
		if not RunState.can_afford_dust(dust_price(item)):
			break
		var out := perform(eq, slot.index, item, plan["action"], int(plan["index"]), rng)
		if not out.ok:
			break
		budget -= out.gold
		done += 1
	return done


## A bot disenchants spare backpack items – the ones that are no upgrade for it (the same test
## as bot buying, [method is_spare]) – until [param dust_needed] is covered, the lowest Dust first
## so the least is thrown away. Returns the Dust gained.
static func bot_disenchant_spare(slot: PlayerSlot, eq: Equipment, dust_needed: int) -> int:
	var gained := 0
	while gained < dust_needed:
		var pick_item: ItemInstance = null
		for item in eq.backpack:
			if not is_spare(item, slot, eq) or not can_disenchant(item):
				continue
			if pick_item == null or dust_for(item) < dust_for(pick_item):
				pick_item = item
		if pick_item == null:
			break
		var dust := disenchant(eq, pick_item, slot.index)
		if dust <= 0:
			break
		gained += dust
	return gained


## A backpack item the bot has no use for: not an upgrade for it (what bots buy, equip and Need).
static func is_spare(item: ItemInstance, slot: PlayerSlot, eq: Equipment) -> bool:
	if item == null or eq == null:
		return false
	if eq.is_last_weapon(item):
		return false
	if eq.can_equip(item):
		var current := ItemTooltip.equipped_for_compare(item, eq)
		if ItemTooltip.upgrade_direction(item, current, slot.class_data, eq) > 0:
			return false
	return true


# --- Helpers -----------------------------------------------------------------------------------

static func _pool(item: ItemInstance, have: Array[StringName]) -> Array[EnchantData]:
	var out: Array[EnchantData] = []
	if item == null:
		return out
	for id in Db.enchants:
		var enchant: EnchantData = Db.enchants[id]
		if enchant == null or enchant.weight <= 0.0 or enchant.id in have:
			continue
		if not Db.is_unlocked(enchant.id) or not ItemGenerator.enchant_fits(enchant, item):
			continue
		out.append(enchant)
	return out


static func _copy(roll: EnchantRoll) -> EnchantRoll:
	return EnchantRoll.new(roll.enchant, roll.rank)


static func _equipment_of(slot: PlayerSlot) -> Equipment:
	if slot == null:
		return null
	var p := slot.player as Player
	if p == null or not is_instance_valid(p):
		return null
	return p.equipment
