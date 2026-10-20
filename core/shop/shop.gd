class_name Shop
extends RefCounted
## The shared shop (GDD 10): one goblin stall for the whole team, offers = 2 + 2 x players
## (4 / 6 / 8 / 10), at least 1-2 offers each player's class can use, shared wallet, locks,
## pings ("P2 wants"), reroll only when EVERY joined player voted; locked and pinged offers
## survive a reroll; max Epic (the generator enforces it for Source.SHOP).
##
## Rules decided here (the UI just calls the methods and listens to [signal changed]):
## - Offers: every distinct joined class gets USABLE_PER_PLAYER offers biased to / guaranteed
##   usable by it (two players on the same class share them) (the guarantee: a few biased draws, then the generator's strict `usable_by`
##   option). The class bias rotates over the players from round to round, so with few free
##   slots (many locked offers) it is not always the same player who loses out. Slots left
##   over are generic (no class bias) but still usable by somebody: each is generated with
##   the strict `usable_by` option for a random joined class. Placement of the offers in the
##   stall is shuffled with the run rng.
## - Fortune: every new offer (round or reroll) is generated with the team's highest Fortune
##   ([method team_fortune]), which shifts the rarity upwards like it does for loot
##   (ItemGenerator.rarity_weights; the shop still stops at Epic).
## - Price: ItemGenerator.price_for(rarity, wave), stored on the Offer and item.buy_price. A
##   kept (locked) offer keeps the price of the wave it was generated for.
## - Lock: any player may lock an unsold offer for the next round (locked_by = their slot).
##   Toggling a lock removes it - ANY player may remove ANY lock (the stall is shared and a
##   lock must never hold the shop hostage, e.g. when its owner left). A lock stays until
##   somebody toggles it off or the offer is sold (Brotato style); it is not consumed by
##   the round change.
## - Ping: toggle per slot, cleared by a reroll and by a new round; selling clears it.
## - Reroll: each joined player toggles their vote; when all voted and the wallet can pay,
##   the cost is spent and every unsold, unlocked, unpinged offer is redrawn. Nothing is
##   charged (and nothing happens) when no offer would change. Voting ([method vote_reroll])
##   and the reroll step ([method try_reroll]) are separate: the UI re-runs the step every
##   frame while votes stand (a voter unplugged, gold arrived) and drops the votes of
##   players who are no longer voters ([method prune_votes]).
## - Buy: the shared wallet pays, the item goes into the buyer's backpack. A sold offer or an
##   empty wallet refuses without spending anything ([method try_buy] tells which). A full
##   backpack refuses too – unless the offer is a weapon the buyer has a forge partner for
##   (Forge.partner_for, GDD 4.1): then the purchase forges at once (BuyResult.FORGED,
##   Forge.forge_with_offer – the bought weapon never enters the backpack; spend kind
##   &"shop_forge", label "<name> (forged)"; the result is [member last_forged]). With room in
##   the backpack the item goes there as usual, partner or not (forging is the player's call).
## - M6 gold sinks next to the offers (kept OUT of [member offers]: that array drives
##   offer_count, the usable-per-player maths, the reroll positions and the card grid):
##   - [member consumables]: the consumables row, [constant Consumables.ROW_SIZE] DIFFERENT
##     random consumables, redrawn by every open_round and by every reroll (also when every item
##     offer is locked: the row is part of the reroll, but it never makes a reroll possible on its
##     own). Unlimited stock: a purchase ([method buy_consumable]) never empties a card, and every
##     hero buys for itself – the buyer's hero gets it as its pending potion / food
##     ([method Consumables.give]: a newer one of the same kind replaces the pending one, no
##     refund). Price: base x the shop price multiplier of the wave. Spend kind &"consumable".
##   - [member black_market]: the one extra Black Market offer from wave [constant
##     BlackMarket.FIRST_WAVE] (null before). An [class Offer] like the item offers: locked offers
##     survive a round, a ping keeps it out of a reroll, a reroll redraws it (and it alone can make
##     a reroll possible); it is addressed by the index [constant BLACK_MARKET] in [method
##     offer_at], [method try_buy], [method toggle_lock] and [method toggle_ping]. Price 3 x the
##     Epic price (BlackMarket); spend kind &"black_market"; the content is BlackMarket.roll.
##   Both draw from a side rng of their own, seeded once from the seed of the rng the first
##   open_round gets: the item offers of a seeded run stay exactly what they were without them.
##   (The Enchanter's &"enchant" spend kind belongs to the Enchanter, not the stall.)

signal changed
## An offer was sold (offer index, buyer slot index, price) - for the spending log.
signal bought(index: int, slot_index: int, price: int)
## The stall was rerolled (new rerolls_this_round).
signal rerolled(count: int)
## A consumable was bought (row index, buyer slot index, price) - for the spending log.
signal consumable_bought(index: int, slot_index: int, price: int)

## FORGED: bought and forged with a partner at once (full backpack, see the class doc).
enum BuyResult { OK, INVALID_OFFER, SOLD, NO_PLAYER, BACKPACK_FULL, NOT_ENOUGH_GOLD, FORGED }

## Offers per player that are guaranteed usable by the player's class.
const USABLE_PER_PLAYER := 2
## Biased draws per offer before the strict "usable_by" generation kicks in.
const BIAS_TRIES := 3
## The "index" of the Black Market offer for [method offer_at], [method try_buy],
## [method toggle_lock] and [method toggle_ping] (the item offers are 0 .. n - 1).
const BLACK_MARKET := -2
## XORed into the first rng's seed for the side rng of the consumables row and the Black Market.
const SIDE_RNG_SALT := 0x5C0DE17


class Offer:
	var item: ItemInstance
	var price := 0
	var sold := false
	## Slot index that locked it, -1 = not locked.
	var locked_by := -1
	## Slot indices that pinged it ("P2 wants").
	var pinged_by: Array[int] = []

	func is_locked() -> bool:
		return locked_by >= 0

	func is_pinged() -> bool:
		return not pinged_by.is_empty()


## One card of the consumables row: unlimited stock, so there is no sold / lock / ping state.
class ConsumableOffer:
	var data: ConsumableData
	var price := 0


var offers: Array[Offer] = []
## The consumables row (M6): the compact cards below the offers, redrawn by every round and every
## reroll (see the class doc).
var consumables: Array[ConsumableOffer] = []
## The Black Market offer (M6; wave 15+): null = none this round (see the class doc).
var black_market: Offer = null
## Slot index -> voted for a reroll this round (absent = no vote).
var reroll_votes: Dictionary[int, bool] = {}
var rerolls_this_round := 0
var wave := 1
## The weapon the last [method try_buy] forged (BuyResult.FORGED); null after any other result.
var last_forged: ItemInstance
## The pending consumable the last [method try_buy_consumable] replaced (null = none).
var last_replaced: ConsumableData

## The slots of the current round (class bias for the offers; set by open_round).
var _slots: Array[PlayerSlot] = []
## The rng of the consumables row and the Black Market, seeded on first use ([method _side]).
var _side_rng := RandomNumberGenerator.new()
var _side_seeded := false


static func offer_count(players: int) -> int:
	return 2 + 2 * clampi(players, 1, 4)


## New round after a wave: keeps locked offers, fills the rest, clears votes and pings.
func open_round(p_wave: int, slots: Array[PlayerSlot], rng: RandomNumberGenerator) -> void:
	wave = maxi(1, p_wave)
	_slots.clear()
	for s in slots:
		if s != null:
			_slots.append(s)
	rerolls_this_round = 0
	reroll_votes.clear()
	var count := offer_count(_slots.size() if not _slots.is_empty() else RunState.player_count)

	# Locked, unsold offers keep their place (if it still exists); the rest of the stall is new.
	var fresh: Array[Offer] = []
	fresh.resize(count)
	var overflow: Array[Offer] = []
	for i in offers.size():
		var o := offers[i]
		if o == null or o.sold or o.locked_by < 0 or o.item == null:
			continue
		o.pinged_by.clear()
		if i < count and fresh[i] == null:
			fresh[i] = o
		else:
			overflow.append(o)
	var empty_positions: Array[int] = []
	for i in count:
		if fresh[i] == null and not overflow.is_empty():
			fresh[i] = overflow.pop_front()
		if fresh[i] == null:
			empty_positions.append(i)
	offers = fresh
	_fill(empty_positions, rng)
	_refresh_consumables(rng)
	_refresh_black_market(rng, true)
	changed.emit()


## Cost of the next reroll: wave x 2 + 2, +2 for every reroll already done this round.
func reroll_cost() -> int:
	return wave * 2 + 2 + 2 * rerolls_this_round


## Buys offer [param index] for [param slot] (shared wallet, item into that player's backpack
## – or forged at once when the backpack is full, see the class doc). True on success.
func buy(index: int, slot: PlayerSlot) -> bool:
	var result := try_buy(index, slot)
	return result == BuyResult.OK or result == BuyResult.FORGED


## [method buy] with the reason for a refusal (nothing is spent unless the result is OK or
## FORGED).
func try_buy(index: int, slot: PlayerSlot) -> BuyResult:
	last_forged = null
	var o := offer_at(index)
	if o == null or o.item == null:
		return BuyResult.INVALID_OFFER
	if o.sold:
		return BuyResult.SOLD
	var player: Player = null
	if slot != null:
		player = slot.player as Player
	if player == null or player.equipment == null:
		return BuyResult.NO_PLAYER
	if not player.equipment.has_space():
		return _buy_and_forge(index, o, slot, player.equipment)
	var kind: StringName = &"black_market" if index == BLACK_MARKET else &"shop"
	if not RunState.try_spend_for(o.price, slot.index, kind, o.item.display_name):
		return BuyResult.NOT_ENOUGH_GOLD
	if not player.equipment.add_to_backpack(o.item):
		RunState.add_gold(o.price)  # cannot happen (space was checked) - never keep the gold
		return BuyResult.BACKPACK_FULL
	_sell(index, o, slot)
	return BuyResult.OK


## Whether buying offer [param index] would forge for [param slot]'s hero right now: a full
## backpack and a forge partner for the offered weapon (with a place for the result).
func forges_on_buy(index: int, slot: PlayerSlot) -> bool:
	var o := offer_at(index)
	if o == null or o.item == null or o.sold or slot == null:
		return false
	var player := slot.player as Player
	if player == null or player.equipment == null or player.equipment.has_space():
		return false
	var partner := Forge.partner_for(player.equipment, o.item)
	return partner != null and not Forge.result_locked(o.item) and Forge.can_place(player.equipment, o.item, partner)


## The full-backpack purchase: forges with the partner (Forge.forge_with_offer) or refuses.
func _buy_and_forge(index: int, o: Offer, slot: PlayerSlot, eq: Equipment) -> BuyResult:
	if not forges_on_buy(index, slot):
		return BuyResult.BACKPACK_FULL
	var kind: StringName = &"black_market" if index == BLACK_MARKET else &"shop_forge"
	if not RunState.try_spend_for(o.price, slot.index, kind, "%s (forged)" % o.item.display_name):
		return BuyResult.NOT_ENOUGH_GOLD
	var result := Forge.forge_with_offer(eq, o.item)
	if result == null:
		RunState.add_gold(o.price)  # cannot happen (forges_on_buy checked) - never keep the gold
		return BuyResult.BACKPACK_FULL
	last_forged = result
	_sell(index, o, slot)
	return BuyResult.FORGED


func _sell(index: int, o: Offer, slot: PlayerSlot) -> void:
	o.sold = true
	o.locked_by = -1
	o.pinged_by.clear()
	if index == BLACK_MARKET:
		RunState.black_market_bought += 1
	bought.emit(index, slot.index, o.price)
	changed.emit()


## Locks an unsold offer for the next round (shows who locked it); toggling a locked offer
## unlocks it, whoever locked it (see the class doc).
func toggle_lock(index: int, slot_index: int) -> void:
	var o := offer_at(index)
	if o == null or o.sold:
		return
	o.locked_by = -1 if o.locked_by >= 0 else slot_index
	changed.emit()


## Adds / removes [param slot_index]'s "P2 wants" label on an unsold offer.
func toggle_ping(index: int, slot_index: int) -> void:
	var o := offer_at(index)
	if o == null or o.sold:
		return
	var at := o.pinged_by.find(slot_index)
	if at >= 0:
		o.pinged_by.remove_at(at)
	else:
		o.pinged_by.append(slot_index)
	changed.emit()


## Toggles [param slot_index]'s reroll vote; rerolls (and returns true) once every index in
## [param joined] voted and the wallet can pay.
func vote_reroll(slot_index: int, joined: Array[int], rng: RandomNumberGenerator) -> bool:
	if reroll_votes.has(slot_index):
		reroll_votes.erase(slot_index)
	else:
		reroll_votes[slot_index] = true
	if try_reroll(joined, rng):
		return true
	changed.emit()
	return false


## The reroll step on its own: rerolls (and returns true) when every index in [param joined]
## voted, the wallet can pay and an offer would change; otherwise it does nothing (no signal).
## The between-wave screen calls it every frame while votes are standing, so a reroll also
## fires when the last missing voter unplugs or the gold arrives after the last vote.
func try_reroll(joined: Array[int], rng: RandomNumberGenerator) -> bool:
	if not reroll_ready(joined) or not RunState.try_spend_for(reroll_cost(), -1, &"shop_reroll", "Stall reroll"):
		return false
	var positions := rerollable_positions()
	var redraw_black_market := black_market_rerollable()
	for i in positions:
		offers[i] = null
	for o in offers:
		if o != null:
			o.pinged_by.clear()
	if black_market != null:
		black_market.pinged_by.clear()
	reroll_votes.clear()
	rerolls_this_round += 1
	_fill(positions, rng)
	_refresh_consumables(rng)
	if redraw_black_market:
		black_market = null
		_refresh_black_market(rng, false)
	rerolled.emit(rerolls_this_round)
	changed.emit()
	return true


## Drops the votes of slots that are not in [param joined] any more (the player left or the
## pad is unplugged). True when a vote was dropped.
func prune_votes(joined: Array[int]) -> bool:
	var dropped := false
	for i: int in reroll_votes.keys():
		if i not in joined:
			reroll_votes.erase(i)
			dropped = true
	if dropped:
		changed.emit()
	return dropped


## True when every index in [param joined] voted, the wallet can pay and an offer would change.
func reroll_ready(joined: Array[int]) -> bool:
	if joined.is_empty():
		return false
	for i in joined:
		if not reroll_votes.get(i, false):
			return false
	return RunState.can_afford(reroll_cost()) \
		and (not rerollable_positions().is_empty() or black_market_rerollable())


## Offer positions a reroll would redraw: unsold, not locked, not pinged.
func rerollable_positions() -> Array[int]:
	var out: Array[int] = []
	for i in offers.size():
		var o := offers[i]
		if o != null and not o.sold and o.locked_by < 0 and o.pinged_by.is_empty():
			out.append(i)
	return out


## True when a reroll would redraw the Black Market offer: there is one, unsold, not locked, not
## pinged.
func black_market_rerollable() -> bool:
	var o := black_market
	return o != null and not o.sold and o.locked_by < 0 and o.pinged_by.is_empty()


## The offer at [param index] (null if out of range); [constant BLACK_MARKET] is the Black Market
## offer.
func offer_at(index: int) -> Offer:
	if index == BLACK_MARKET:
		return black_market
	if index < 0 or index >= offers.size():
		return null
	return offers[index]


# --- The consumables row and the Black Market ---------------------------------------------------

## The consumables card at [param index] (null if out of range).
func consumable_at(index: int) -> ConsumableOffer:
	if index < 0 or index >= consumables.size():
		return null
	return consumables[index]


## Buys the consumables card [param index] for [param slot]'s hero (unlimited stock: the card
## stays): the shared wallet pays (&"consumable"), the hero gets it as its pending potion / food
## ([method Consumables.give]). [member last_replaced] is the pending one it pushed out. True on
## success.
func buy_consumable(index: int, slot: PlayerSlot) -> bool:
	return try_buy_consumable(index, slot) == BuyResult.OK


## [method buy_consumable] with the reason for a refusal (nothing is spent unless the result is
## OK; INVALID_OFFER / NO_PLAYER / NOT_ENOUGH_GOLD are the possible refusals).
func try_buy_consumable(index: int, slot: PlayerSlot) -> BuyResult:
	last_replaced = null
	var c := consumable_at(index)
	if c == null or c.data == null:
		return BuyResult.INVALID_OFFER
	var player: Player = null
	if slot != null:
		player = slot.player as Player
	if player == null or not is_instance_valid(player):
		return BuyResult.NO_PLAYER
	if not RunState.try_spend_for(c.price, slot.index, &"consumable", c.data.display_name):
		return BuyResult.NOT_ENOUGH_GOLD
	last_replaced = Consumables.give(player, c.data)
	RunState.consumables_bought += 1
	consumable_bought.emit(index, slot.index, c.price)
	changed.emit()
	return BuyResult.OK


## The rng of the consumables row and the Black Market. Seeded the first time from the seed of
## [param base] (the rng the stall is opened with): independent of every other draw, so the item
## offers (and everything else on RunState.rng) do not depend on these two features.
func _side(base: RandomNumberGenerator) -> RandomNumberGenerator:
	if not _side_seeded:
		_side_seeded = true
		_side_rng.seed = base.seed ^ SIDE_RNG_SALT
	return _side_rng


## Draws a new consumables row (all cards replaced).
func _refresh_consumables(rng: RandomNumberGenerator) -> void:
	consumables.clear()
	for data in Consumables.roll_row(_side(rng)):
		var c := ConsumableOffer.new()
		c.data = data
		c.price = Difficulty.price(Consumables.price(data, wave))  # (M9: the tier's shop prices)
		consumables.append(c)


## The Black Market offer for the new round ([param keep_locked]) or after a reroll: null before
## BlackMarket.FIRST_WAVE; a locked, unsold offer stays for the next round; otherwise a new roll.
func _refresh_black_market(rng: RandomNumberGenerator, keep_locked: bool) -> void:
	if not BlackMarket.is_open(wave):
		black_market = null
		return
	var kept := black_market
	if keep_locked and kept != null and kept.item != null and not kept.sold and kept.locked_by >= 0:
		kept.pinged_by.clear()
		return
	var item := BlackMarket.roll(wave, _slots, _side(rng))
	if item == null:
		black_market = null
		return
	var o := Offer.new()
	o.item = item
	o.price = Difficulty.price(BlackMarket.price(wave))
	black_market = o


## Number of unsold offers [param class_data] can use.
func usable_count(class_data: ClassData) -> int:
	var n := 0
	for o in offers:
		if o != null and not o.sold and o.item != null and o.item.can_be_used_by(class_data):
			n += 1
	return n


# --- Generation --------------------------------------------------------------

## Draws new offers into the (null) [param positions] of [member offers].
func _fill(positions: Array[int], rng: RandomNumberGenerator) -> void:
	if positions.is_empty():
		return
	var targets := _class_targets(positions.size())
	var order := positions.duplicate()
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: int = order[i]
		order[i] = order[j]
		order[j] = t
	for k in order.size():
		offers[order[k]] = _make_offer(targets[k], rng)


## The class each of the next [param n] offers must be usable by (null = generic): every
## player is topped up to USABLE_PER_PLAYER usable offers, round-robin, starting at a
## player that rotates with the wave / reroll count.
func _class_targets(n: int) -> Array[ClassData]:
	var out: Array[ClassData] = []
	var pool: Array[PlayerSlot] = []
	for s in _slots:
		if s.class_data != null:
			pool.append(s)
	if not pool.is_empty():
		var start := (wave + rerolls_this_round) % pool.size()
		for r in USABLE_PER_PLAYER:
			for j in pool.size():
				var s := pool[(start + j) % pool.size()]
				if usable_count(s.class_data) + _queued(out, s.class_data) <= r:
					out.append(s.class_data)
	out.resize(mini(out.size(), n))
	while out.size() < n:
		out.append(null)
	return out


static func _queued(list: Array[ClassData], class_data: ClassData) -> int:
	return list.count(class_data)


func _make_offer(class_data: ClassData, rng: RandomNumberGenerator) -> Offer:
	var o := Offer.new()
	o.item = _generate_for(class_data, rng)
	var base_price := ItemGenerator.price_for(o.item.rarity, wave)
	o.price = Difficulty.price(base_price)  # (M9: the tier's shop prices; the item's own value stays the base price)
	o.item.buy_price = base_price
	return o


## The highest Fortune among the round's heroes (0 without any) – the shop's rarity roll.
func team_fortune() -> float:
	var best := 0.0
	for s in _slots:
		best = maxf(best, LootDrops.killer_fortune(s.player))
	return best


## Distinct classes of the round's players (generic offers must be usable by one of them).
func _team_classes() -> Array[ClassData]:
	var out: Array[ClassData] = []
	for s in _slots:
		if s.class_data != null and s.class_data not in out:
			out.append(s.class_data)
	return out


func _generate_for(class_data: ClassData, rng: RandomNumberGenerator) -> ItemInstance:
	var fortune := team_fortune()
	if class_data == null:
		# Generic: no class bias, but never something nobody in the team can use.
		var team := _team_classes()
		if team.is_empty():
			return ItemGenerator.generate(ItemGenerator.Source.SHOP, wave, rng, {&"fortune": fortune})
		var anyone := team[rng.randi_range(0, team.size() - 1)]
		return ItemGenerator.generate(ItemGenerator.Source.SHOP, wave, rng,
			{&"usable_by": anyone, &"fortune": fortune})
	var item: ItemInstance = null
	for _i in BIAS_TRIES:
		item = ItemGenerator.generate(ItemGenerator.Source.SHOP, wave, rng,
			{&"class_data": class_data, &"fortune": fortune})
		if item.can_be_used_by(class_data):
			return item
	return ItemGenerator.generate(ItemGenerator.Source.SHOP, wave, rng,
		{&"usable_by": class_data, &"fortune": fortune})
