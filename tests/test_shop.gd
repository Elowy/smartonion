extends TestCase
## Shop: offer counts, class bias, price, locks, pings, buying edge cases, reroll vote.

const Support := preload("res://tests/test_loot_support.gd")

var shop: Shop
var slots: Array[PlayerSlot] = []
var rng: RandomNumberGenerator


func before_each() -> void:
	RunState.start_run(2, 7)
	shop = Shop.new()
	rng = RandomNumberGenerator.new()
	rng.seed = 99
	slots = Support.make_slots([&"warrior", &"mage"] as Array[StringName])


func after_each() -> void:
	Support.free_slots(slots)
	slots.clear()
	shop = null


func _open(wave: int = 1) -> void:
	shop.open_round(wave, slots, rng)


func _joined() -> Array[int]:
	var out: Array[int] = []
	for s in slots:
		out.append(s.index)
	return out


func _signature() -> Array[String]:
	var out: Array[String] = []
	for o in shop.offers:
		out.append("%s|%d|%d" % [o.item.display_name, o.item.rarity, o.price])
	return out


func test_offer_count_scales_with_players() -> void:
	check_eq(Shop.offer_count(1), 4, "1 player")
	check_eq(Shop.offer_count(2), 6, "2 players")
	check_eq(Shop.offer_count(3), 8, "3 players")
	check_eq(Shop.offer_count(4), 10, "4 players")
	check_eq(Shop.offer_count(0), 4, "clamped low")
	check_eq(Shop.offer_count(9), 10, "clamped high")


func test_open_round_fills_the_stall_with_priced_items() -> void:
	var changes := Support.count_signal(shop.changed)
	_open(3)
	check_eq(shop.offers.size(), 6, "two players -> 6 offers")
	check_eq(shop.wave, 3, "wave stored")
	check(changes[0] >= 1, "changed emitted")
	for o in shop.offers:
		check(o != null and o.item != null, "every offer holds an item")
		check(not o.sold and o.locked_by == -1 and o.pinged_by.is_empty(), "fresh offer state")
		check_eq(o.price, ItemGenerator.price_for(o.item.rarity, 3), "price = price_for(rarity, wave)")
		check_eq(o.item.buy_price, o.price, "item.buy_price mirrors the price")
		check(o.item.rarity <= Items.Rarity.EPIC, "shop sells at most Epic")


func test_stall_size_follows_the_slot_count() -> void:
	var four := Support.make_slots([&"warrior", &"mage", &"rogue", &"paladin"] as Array[StringName])
	shop.open_round(1, four, rng)
	check_eq(shop.offers.size(), 10, "4 players")
	var one: Array[PlayerSlot] = [four[0]]
	shop.open_round(2, one, rng)
	check_eq(shop.offers.size(), 4, "1 player")
	Support.free_slots(four)


func test_every_class_gets_usable_offers() -> void:
	var four := Support.make_slots([&"warrior", &"mage", &"rogue", &"paladin"] as Array[StringName])
	for seed_value in 12:
		rng.seed = seed_value
		shop.open_round(1 + seed_value, four, rng)
		for s in four:
			check(shop.usable_count(s.class_data) >= Shop.USABLE_PER_PLAYER,
					"%s has >= %d usable offers (seed %d): %d" % [s.class_data.id, Shop.USABLE_PER_PLAYER,
					seed_value, shop.usable_count(s.class_data)])
	Support.free_slots(four)


func test_same_seed_same_stall() -> void:
	rng.seed = 5
	_open(4)
	var first := _signature()
	var shop2 := Shop.new()
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 5
	shop2.open_round(4, slots, rng2)
	var second: Array[String] = []
	for o in shop2.offers:
		second.append("%s|%d|%d" % [o.item.display_name, o.item.rarity, o.price])
	check_eq(first, second, "deterministic")


func test_locked_offers_survive_the_next_round() -> void:
	_open(1)
	var kept_item := shop.offers[2].item
	var kept_price := shop.offers[2].price
	shop.toggle_lock(2, 1)
	shop.toggle_ping(2, 0)
	shop.toggle_ping(4, 1)
	shop.vote_reroll(0, _joined(), rng)
	var old_unlocked := shop.offers[3]
	_open(2)
	check_eq(shop.offers.size(), 6, "full stall again")
	check(shop.offers[2].item == kept_item, "locked item still at its place")
	check_eq(shop.offers[2].price, kept_price, "keeps its price")
	check_eq(shop.offers[2].locked_by, 1, "lock persists until toggled")
	check(shop.offers[2].pinged_by.is_empty(), "pings are cleared")
	check(shop.offers[4].pinged_by.is_empty(), "pings cleared everywhere")
	check(shop.offers[3] != old_unlocked, "unlocked offers are new")
	check(shop.reroll_votes.is_empty(), "votes cleared")
	check_eq(shop.rerolls_this_round, 0, "reroll count reset")
	check_eq(shop.wave, 2, "wave updated")


func test_sold_locked_offer_is_not_kept() -> void:
	_open(1)
	RunState.add_gold(500)
	shop.toggle_lock(1, 0)
	check(shop.buy(1, slots[0]), "buy it")
	check_eq(shop.offers[1].locked_by, -1, "selling releases the lock")
	var sold_offer := shop.offers[1]
	_open(2)
	check(shop.offers[1] != sold_offer and not shop.offers[1].sold, "sold offer replaced by a new one")


func test_lock_toggle_rules() -> void:
	_open(1)
	shop.toggle_lock(0, 0)
	check_eq(shop.offers[0].locked_by, 0, "P1 locks")
	shop.toggle_lock(0, 0)
	check_eq(shop.offers[0].locked_by, -1, "same player unlocks")
	shop.toggle_lock(0, 0)
	shop.toggle_lock(0, 1)
	check_eq(shop.offers[0].locked_by, -1, "another player may remove a lock")
	shop.toggle_lock(0, 1)
	check_eq(shop.offers[0].locked_by, 1, "and lock it again as themselves")
	var changes := Support.count_signal(shop.changed)
	shop.toggle_lock(-1, 0)
	shop.toggle_lock(99, 0)
	check_eq(changes[0], 0, "invalid index is ignored silently")
	RunState.add_gold(500)
	shop.buy(3, slots[0])
	shop.toggle_lock(3, 0)
	check_eq(shop.offers[3].locked_by, -1, "a sold offer cannot be locked")
	shop.toggle_lock(2, 1)
	check_eq(changes[0], 2, "changed emitted for the buy and the lock, not for the refused toggle")


func test_ping_toggle() -> void:
	_open(1)
	shop.toggle_ping(1, 0)
	shop.toggle_ping(1, 1)
	check_eq(shop.offers[1].pinged_by, [0, 1] as Array[int], "two pingers")
	shop.toggle_ping(1, 0)
	check_eq(shop.offers[1].pinged_by, [1] as Array[int], "first removed")
	shop.toggle_ping(1, 1)
	check(shop.offers[1].pinged_by.is_empty(), "all removed")
	RunState.add_gold(500)
	shop.buy(1, slots[1])
	shop.toggle_ping(1, 0)
	check(shop.offers[1].pinged_by.is_empty(), "no ping on a sold offer")
	shop.toggle_ping(50, 0)
	check(true, "out of range ping does not crash")


func test_buy_spends_shared_gold_and_fills_backpack() -> void:
	_open(2)
	var o := shop.offers[0]
	RunState.add_gold(o.price + 7)
	var bought: Array[int] = []
	shop.bought.connect(func(index: int, slot_index: int, price: int) -> void:
		bought.append_array([index, slot_index, price]))
	var changes := Support.count_signal(shop.changed)
	check(shop.buy(0, slots[1]), "bought")
	check_eq(RunState.gold, 7, "price taken from the shared wallet")
	check(o.sold, "offer sold")
	check(Support.equipment_of(slots[1]).backpack.has(o.item), "item in the buyer's backpack")
	check(Support.equipment_of(slots[0]).backpack.is_empty(), "not in the other backpack")
	check_eq(bought, [0, 1, o.price] as Array[int], "bought signal")
	check_eq(changes[0], 1, "changed emitted")
	check(not shop.buy(0, slots[0]), "cannot buy twice")
	check_eq(shop.try_buy(0, slots[0]), Shop.BuyResult.SOLD, "reason: sold")
	check_eq(RunState.gold, 7, "no second charge")


func test_buy_refused_without_enough_gold() -> void:
	_open(1)
	var o := shop.offers[0]
	RunState.add_gold(o.price - 1)
	var changes := Support.count_signal(shop.changed)
	check(not shop.buy(0, slots[0]), "refused")
	check_eq(shop.try_buy(0, slots[0]), Shop.BuyResult.NOT_ENOUGH_GOLD, "reason")
	check_eq(RunState.gold, o.price - 1, "wallet untouched")
	check(not o.sold, "still for sale")
	check(Support.equipment_of(slots[0]).backpack.is_empty(), "nothing in the backpack")
	check_eq(changes[0], 0, "no change signal for a refusal")
	RunState.add_gold(1)
	check(shop.buy(0, slots[0]), "affordable now")
	check_eq(RunState.gold, 0, "exact price spent")


func test_buy_refused_with_full_backpack() -> void:
	_open(1)
	Support.fill_backpack(slots[0])
	RunState.add_gold(500)
	check(not shop.buy(0, slots[0]), "full backpack refuses")
	check_eq(shop.try_buy(0, slots[0]), Shop.BuyResult.BACKPACK_FULL, "reason")
	check_eq(RunState.gold, 500, "no gold spent")
	check(not shop.offers[0].sold, "offer still for sale")
	check(shop.buy(0, slots[1]), "another player with room can still buy it")
	check_eq(RunState.gold, 500 - shop.offers[0].price, "charged once")


func test_buy_invalid_requests() -> void:
	_open(1)
	RunState.add_gold(500)
	check_eq(shop.try_buy(-1, slots[0]), Shop.BuyResult.INVALID_OFFER, "negative index")
	check_eq(shop.try_buy(6, slots[0]), Shop.BuyResult.INVALID_OFFER, "past the end")
	check_eq(shop.try_buy(0, null), Shop.BuyResult.NO_PLAYER, "no slot")
	var ghost := PlayerSlot.new(3, ScriptedInput.new("ghost"), Color.WHITE)
	check_eq(shop.try_buy(0, ghost), Shop.BuyResult.NO_PLAYER, "slot without a player node")
	check(not shop.buy(0, ghost), "buy refuses too")
	check_eq(RunState.gold, 500, "nothing spent")


func test_reroll_cost_formula() -> void:
	_open(5)
	check_eq(shop.reroll_cost(), 12, "wave x 2 + 2")
	shop.rerolls_this_round = 2
	check_eq(shop.reroll_cost(), 16, "+2 per reroll")


func test_reroll_needs_every_joined_player() -> void:
	_open(1)
	RunState.add_gold(500)
	var before := shop.offers.duplicate()
	check(not shop.vote_reroll(0, _joined(), rng), "one of two voted")
	check_eq(shop.reroll_votes.size(), 1, "vote recorded")
	check_eq(RunState.gold, 500, "no cost yet")
	check(shop.vote_reroll(1, _joined(), rng), "second vote rerolls")
	check_eq(RunState.gold, 500 - 4, "wave 1 reroll costs 4")
	check_eq(shop.rerolls_this_round, 1, "counted")
	check(shop.reroll_votes.is_empty(), "votes cleared")
	for i in shop.offers.size():
		check(shop.offers[i] != before[i], "offer %d redrawn" % i)
		check(not shop.offers[i].sold and shop.offers[i].item != null, "valid new offer")
	check_eq(shop.reroll_cost(), 6, "next reroll is 2 more")


func test_vote_can_be_withdrawn() -> void:
	_open(1)
	RunState.add_gold(500)
	check(not shop.vote_reroll(0, _joined(), rng), "P1 votes")
	check(not shop.vote_reroll(0, _joined(), rng), "P1 withdraws")
	check(shop.reroll_votes.is_empty(), "no votes left")
	check(not shop.vote_reroll(1, _joined(), rng), "P2 alone does not reroll")
	check_eq(RunState.gold, 500, "nothing spent")
	check(shop.vote_reroll(0, _joined(), rng), "P1 votes again -> all voted")
	check_eq(RunState.gold, 496, "paid once")


func test_reroll_joined_list_edge_cases() -> void:
	_open(1)
	RunState.add_gold(500)
	var only_first: Array[int] = [0]
	check(shop.vote_reroll(0, only_first, rng), "a single joined player decides alone")
	var nobody: Array[int] = []
	check(not shop.vote_reroll(0, nobody, rng), "nobody joined never rerolls")


func test_reroll_without_gold_keeps_the_votes() -> void:
	_open(2)
	RunState.add_gold(shop.reroll_cost() - 1)
	var before := shop.offers.duplicate()
	shop.vote_reroll(0, _joined(), rng)
	check(not shop.vote_reroll(1, _joined(), rng), "cannot pay")
	check_eq(RunState.gold, shop.reroll_cost() - 1, "wallet untouched")
	check_eq(shop.offers, before, "offers untouched")
	check_eq(shop.rerolls_this_round, 0, "not counted")
	check_eq(shop.reroll_votes.size(), 2, "both votes remain")
	check(not shop.reroll_ready(_joined()) , "not ready while poor")
	RunState.add_gold(1)
	check(shop.reroll_ready(_joined()), "ready once the wallet can pay")


func test_reroll_keeps_locked_pinged_and_sold_offers() -> void:
	_open(1)
	RunState.add_gold(500)
	shop.toggle_lock(0, 0)
	shop.toggle_ping(1, 1)
	check(shop.buy(2, slots[0]), "sold one")
	var locked := shop.offers[0]
	var pinged := shop.offers[1]
	var sold := shop.offers[2]
	var others := [shop.offers[3], shop.offers[4], shop.offers[5]]
	shop.vote_reroll(0, _joined(), rng)
	check(shop.vote_reroll(1, _joined(), rng), "rerolled")
	check(shop.offers[0] == locked and shop.offers[0].locked_by == 0, "locked survives with its lock")
	check(shop.offers[1] == pinged, "pinged survives")
	check(shop.offers[1].pinged_by.is_empty(), "pings cleared by the reroll")
	check(shop.offers[2] == sold and sold.sold, "sold stays sold")
	for i in 3:
		check(shop.offers[3 + i] != others[i], "plain offer %d redrawn" % i)


func test_reroll_with_nothing_to_redraw_costs_nothing() -> void:
	_open(1)
	RunState.add_gold(500)
	for i in shop.offers.size():
		shop.toggle_lock(i, 0)
	check(shop.rerollable_positions().is_empty(), "all locked")
	shop.vote_reroll(0, _joined(), rng)
	check(not shop.vote_reroll(1, _joined(), rng), "no reroll")
	check_eq(RunState.gold, 500, "nothing charged")
	check_eq(shop.rerolls_this_round, 0, "not counted")


func test_reroll_keeps_class_coverage() -> void:
	var four := Support.make_slots([&"warrior", &"mage", &"rogue", &"paladin"] as Array[StringName])
	shop.open_round(3, four, rng)
	RunState.add_gold(1000)
	var joined: Array[int] = [0, 1, 2, 3]
	for round_index in 3:
		for i in 4:
			shop.vote_reroll(i, joined, rng)
		check_eq(shop.rerolls_this_round, round_index + 1, "reroll %d done" % round_index)
		for s in four:
			check(shop.usable_count(s.class_data) >= Shop.USABLE_PER_PLAYER,
					"%s still has usable offers after reroll %d" % [s.class_data.id, round_index])
	Support.free_slots(four)


func test_changed_signal_fires_for_votes_and_pings() -> void:
	_open(1)
	var changes := Support.count_signal(shop.changed)
	shop.toggle_ping(0, 0)
	shop.toggle_lock(0, 0)
	shop.vote_reroll(0, _joined(), rng)
	check_eq(changes[0], 3, "ping + lock + vote")


## Generic offers (beyond each class's guaranteed ones) are still usable by someone in the
## team: a strict `usable_by` roll for a random joined class.
func test_generic_offers_are_usable_by_the_team() -> void:
	for team: Array in [[&"mage"], [&"warlock", &"mage"], [&"rogue"], [&"warrior", &"paladin"]]:
		Support.free_slots(slots)
		var ids: Array[StringName] = []
		for id: StringName in team:
			ids.append(id)
		slots = Support.make_slots(ids)
		var total := 0
		var unusable := 0
		for wave in range(1, 21, 2):
			for _rep in 4:
				shop = Shop.new()
				_open(wave)
				for o in shop.offers:
					total += 1
					var anyone := false
					for s in slots:
						anyone = anyone or o.item.can_be_used_by(s.class_data)
					if not anyone:
						unusable += 1
		check(total >= 40, "%s: enough offers looked at (%d)" % [str(ids), total])
		check_eq(unusable, 0, "%s: every offer is usable by someone in the team" % str(ids))


## The team's highest Fortune goes into the shop's rarity roll (round and reroll).
func test_team_fortune_raises_the_shop_rarity() -> void:
	_open(12)
	check_eq(shop.team_fortune(), 0.0, "no Fortune")
	(slots[0].player as Player).stats.set_source(&"test", {Stats.FORTUNE: 15.0})
	(slots[1].player as Player).stats.set_source(&"test", {Stats.FORTUNE: 300.0})
	check_eq(shop.team_fortune(), 300.0, "the highest Fortune in the team")
	var lucky := _mean_shop_rarity(12)
	(slots[0].player as Player).stats.remove_source(&"test")
	(slots[1].player as Player).stats.remove_source(&"test")
	var plain := _mean_shop_rarity(12)
	check(lucky > plain + 0.3, "Fortune shifts the stall towards higher rarities (%.2f vs %.2f)" % [lucky, plain])
	# A reroll draws with the same Fortune.
	(slots[1].player as Player).stats.set_source(&"test", {Stats.FORTUNE: 300.0})
	var rolled := 0.0
	var n := 0
	for i in 30:
		shop = Shop.new()
		_open(12)
		RunState.add_gold(shop.reroll_cost())
		for s in slots:
			shop.vote_reroll(s.index, _joined(), rng)
		for o in shop.offers:
			rolled += o.item.rarity
			n += 1
	check(rolled / n > plain + 0.3, "rerolled offers too (%.2f)" % (rolled / n))


func _mean_shop_rarity(wave: int) -> float:
	var total := 0.0
	var n := 0
	for i in 40:
		shop = Shop.new()
		_open(wave)
		for o in shop.offers:
			total += o.item.rarity
			n += 1
	return total / maxf(1.0, n)
