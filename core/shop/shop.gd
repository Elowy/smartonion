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
## - Buy: the shared wallet pays, the item goes into the buyer's backpack. A full backpack,
##   a sold offer or an empty wallet refuses without spending anything ([method try_buy]
##   tells which).

signal changed
## An offer was sold (offer index, buyer slot index, price) - for the spending log.
signal bought(index: int, slot_index: int, price: int)
## The stall was rerolled (new rerolls_this_round).
signal rerolled(count: int)

enum BuyResult { OK, INVALID_OFFER, SOLD, NO_PLAYER, BACKPACK_FULL, NOT_ENOUGH_GOLD }

## Offers per player that are guaranteed usable by the player's class.
const USABLE_PER_PLAYER := 2
## Biased draws per offer before the strict "usable_by" generation kicks in.
const BIAS_TRIES := 3


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


var offers: Array[Offer] = []
## Slot index -> voted for a reroll this round (absent = no vote).
var reroll_votes: Dictionary[int, bool] = {}
var rerolls_this_round := 0
var wave := 1

## The slots of the current round (class bias for the offers; set by open_round).
var _slots: Array[PlayerSlot] = []


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
	changed.emit()


## Cost of the next reroll: wave x 2 + 2, +2 for every reroll already done this round.
func reroll_cost() -> int:
	return wave * 2 + 2 + 2 * rerolls_this_round


## Buys offer [param index] for [param slot] (shared wallet, item into that player's backpack).
func buy(index: int, slot: PlayerSlot) -> bool:
	return try_buy(index, slot) == BuyResult.OK


## [method buy] with the reason for a refusal (nothing is spent unless the result is OK).
func try_buy(index: int, slot: PlayerSlot) -> BuyResult:
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
		return BuyResult.BACKPACK_FULL
	if not RunState.try_spend(o.price):
		return BuyResult.NOT_ENOUGH_GOLD
	if not player.equipment.add_to_backpack(o.item):
		RunState.add_gold(o.price)  # cannot happen (space was checked) - never keep the gold
		return BuyResult.BACKPACK_FULL
	o.sold = true
	o.locked_by = -1
	o.pinged_by.clear()
	bought.emit(index, slot.index, o.price)
	changed.emit()
	return BuyResult.OK


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
	if not reroll_ready(joined) or not RunState.try_spend(reroll_cost()):
		return false
	var positions := rerollable_positions()
	for i in positions:
		offers[i] = null
	for o in offers:
		if o != null:
			o.pinged_by.clear()
	reroll_votes.clear()
	rerolls_this_round += 1
	_fill(positions, rng)
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
	return RunState.can_afford(reroll_cost()) and not rerollable_positions().is_empty()


## Offer positions a reroll would redraw: unsold, not locked, not pinged.
func rerollable_positions() -> Array[int]:
	var out: Array[int] = []
	for i in offers.size():
		var o := offers[i]
		if o != null and not o.sold and o.locked_by < 0 and o.pinged_by.is_empty():
			out.append(i)
	return out


## The offer at [param index] (null if out of range).
func offer_at(index: int) -> Offer:
	if index < 0 or index >= offers.size():
		return null
	return offers[index]


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
	o.price = ItemGenerator.price_for(o.item.rarity, wave)
	o.item.buy_price = o.price
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
