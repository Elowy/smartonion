extends TestCase
## M6 SHOPSINKS, the model side (GDD 10 / 16.1): the seven consumables (data, prices, the pending
## rule, apply at the wave start / clear at its end through PlayerBonuses), the stall's consumables
## row and the Black Market (Shop, BlackMarket): content, prices, purchases, lock / ping / reroll,
## the side rng that keeps the item offers of a seeded run unchanged.

const Fakes := preload("res://tests/player_fakes.gd")

const IDS: Array[StringName] = [
	&"elixir_of_fortune", &"elixir_of_ironskin", &"elixir_of_swiftness", &"flask_of_fury",
	&"hearty_onion_stew", &"smoked_boar_ribs", &"spiced_onion_rings",
]

var world: Node3D
var nodes: Array[Node] = []


## A Shop whose consumables row and Black Market are off: what the stall was before M6.
class PlainShop extends Shop:
	func _refresh_consumables(_rng: RandomNumberGenerator) -> void:
		pass

	func _refresh_black_market(_rng: RandomNumberGenerator, _keep_locked: bool) -> void:
		pass


func before_each() -> void:
	PlayerManager.clear()
	PlayerManager.joining_enabled = false
	RunState.start_run(1, 4242)
	world = Fakes.make_world(tree)


func after_each() -> void:
	for n in nodes:
		if n != null and is_instance_valid(n):
			n.free()
	nodes.clear()
	Fakes.free_world(world)
	world = null
	PlayerManager.clear()
	RunState.start_run(1, 1)


func _hero(class_id: StringName = &"warrior", index := 0) -> Player:
	var p := Fakes.spawn_player(world, index, class_id)
	return p


func _c(id: StringName) -> ConsumableData:
	return Db.get_consumable(id)


# --- Data --------------------------------------------------------------------------------------

func test_the_seven_consumables_are_loaded() -> void:
	var ids: Array[StringName] = []
	for id in Db.consumables:
		ids.append(id)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	check_eq(ids, IDS, "the seven ids")
	var pooled: Array[StringName] = []
	for c in Consumables.pool():
		pooled.append(c.id)
	check_eq(pooled, IDS, "the pool is in id order")
	var potions := 0
	var foods := 0
	for id in IDS:
		var c := _c(id)
		check(c != null and c.display_name != "" and c.description != "" and c.icon_id == id, "%s is complete" % id)
		if c.is_potion():
			potions += 1
		else:
			foods += 1
	check_eq(potions, 4, "four flasks / elixirs")
	check_eq(foods, 3, "three foods")
	for pair: Array in [[&"flask_of_fury", 14], [&"elixir_of_ironskin", 12], [&"elixir_of_swiftness", 12],
			[&"elixir_of_fortune", 10], [&"hearty_onion_stew", 10], [&"spiced_onion_rings", 10], [&"smoked_boar_ribs", 12]]:
		check_eq(_c(pair[0]).base_price, pair[1], "%s base price" % pair[0])
	check(_c(&"hearty_onion_stew").is_food() and _c(&"smoked_boar_ribs").is_food() and _c(&"spiced_onion_rings").is_food(), "the foods")


func test_the_effects_are_valid_bonus_entries() -> void:
	var hero := _hero()
	for id in IDS:
		var entries := Consumables.resolve_effects(_c(id), hero)
		check(not entries.is_empty(), "%s has effects" % id)
		for e in entries:
			check_eq(BonusVocabulary.validate(e), "", "%s: %s" % [id, e])


func test_price_is_base_times_the_shop_multiplier() -> void:
	var flask := _c(&"flask_of_fury")
	check_eq(Consumables.price(flask, 1), 14, "wave 1: the base price")
	check_eq(Consumables.price(flask, 15), roundi(14.0 * (1.0 + 0.08 * 14.0)), "wave 15: x 2.12")
	check_eq(Consumables.price(_c(&"elixir_of_fortune"), 25), roundi(10.0 * (1.0 + 0.08 * 24.0)), "wave 25")
	check_eq(Consumables.price(flask, 0), 14, "wave 0 counts as 1")
	check_eq(Consumables.price(null, 5), 0, "nothing")


func test_effect_texts() -> void:
	check_eq(Consumables.effect_lines(_c(&"flask_of_fury")), ["+15% Damage"] as Array[String], "flask")
	check_eq(Consumables.effect_lines(_c(&"elixir_of_ironskin")), ["+30% Armor"] as Array[String], "ironskin")
	check_eq(Consumables.effect_lines(_c(&"elixir_of_swiftness")), ["+10% Haste", "+10% Speed"] as Array[String], "swiftness")
	check_eq(Consumables.effect_lines(_c(&"elixir_of_fortune")), ["+25 Fortune"] as Array[String], "fortune")
	check_eq(Consumables.effect_lines(_c(&"hearty_onion_stew")), ["+15% Max HP", "+5 Spirit"] as Array[String], "stew")
	check_eq(Consumables.effect_lines(_c(&"spiced_onion_rings")), ["+5% Critical Strike"] as Array[String], "rings")
	check_eq(Consumables.effect_lines(_c(&"smoked_boar_ribs")), ["-8% Damage taken"] as Array[String], "ribs")
	check_eq(Consumables.summary(_c(&"elixir_of_swiftness")), "+10% Haste, +10% Speed", "one line")
	check_eq(Consumables.kind_name(_c(&"flask_of_fury")), "Potion", "potion")
	check_eq(Consumables.kind_name(_c(&"smoked_boar_ribs")), "Food", "food")


# --- The row draw and the pending rule ---------------------------------------------------------

func test_row_has_four_different_cards_and_follows_the_rng() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seen_sets: Dictionary[String, bool] = {}
	for i in 30:
		var row := Consumables.roll_row(rng)
		check_eq(row.size(), Consumables.ROW_SIZE, "four cards")
		var ids: Array[StringName] = []
		for c in row:
			check(c.id not in ids, "distinct")
			ids.append(c.id)
		ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
		seen_sets[",".join(ids)] = true
	check(seen_sets.size() > 5, "the row varies (%d different rows)" % seen_sets.size())
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 99
	b.seed = 99
	var ra := Consumables.roll_row(a)
	var rb := Consumables.roll_row(b)
	check_eq(ra.map(func(c: ConsumableData) -> StringName: return c.id), rb.map(func(c: ConsumableData) -> StringName: return c.id), "same seed, same row")
	check_eq(Consumables.roll_row(a, 20).size(), 7, "never more than the pool")


func test_the_pending_rule_replaces_the_same_kind() -> void:
	var pending: Array[ConsumableData] = []
	check(Consumables.queue(pending, _c(&"flask_of_fury")) == null, "nothing replaced")
	check(Consumables.queue(pending, _c(&"hearty_onion_stew")) == null, "a food next to the potion")
	check_eq(pending.size(), 2, "one potion + one food")
	check(Consumables.queue(pending, _c(&"elixir_of_swiftness")) == _c(&"flask_of_fury"), "the new potion pushes the old one out")
	check_eq(pending.size(), 2, "still one potion + one food")
	check(pending[0] == _c(&"elixir_of_swiftness") and pending[1] == _c(&"hearty_onion_stew"), "potion first")
	check(Consumables.queue(pending, _c(&"smoked_boar_ribs")) == _c(&"hearty_onion_stew"), "the new food pushes the old one out")
	check(Consumables.of_kind(pending, ConsumableData.Kind.FOOD) == _c(&"smoked_boar_ribs"), "of_kind")
	check(Consumables.of_kind(pending, ConsumableData.Kind.POTION) == _c(&"elixir_of_swiftness"), "of_kind potion")
	check(Consumables.queue(pending, null) == null and pending.size() == 2, "null is ignored")


# --- Apply at the wave start, clear at its end -------------------------------------------------

func test_a_bought_flask_starts_with_the_next_wave_and_ends_with_it() -> void:
	var hero := _hero()
	var seen: Array[int] = []
	hero.consumables_changed.connect(func() -> void: seen.append(hero.consumables_pending.size() * 10 + hero.consumables_active.size()))
	check_eq(hero.outgoing_damage_mult(null, &"physical", &"weapon"), 1.0, "no bonus")
	Consumables.give(hero, _c(&"flask_of_fury"))
	check_eq(hero.consumables_pending.size(), 1, "pending")
	check_eq(hero.outgoing_damage_mult(null, &"physical", &"weapon"), 1.0, "nothing before the wave starts")
	hero.begin_wave()
	check(hero.consumables_pending.is_empty(), "no longer pending")
	check_eq(hero.consumables_active.size(), 1, "active")
	check_near(hero.outgoing_damage_mult(null, &"physical", &"weapon"), 1.15, 0.0001, "+15% damage during the wave")
	hero.end_wave()
	check(hero.consumables_active.is_empty(), "gone")
	check_eq(hero.outgoing_damage_mult(null, &"physical", &"weapon"), 1.0, "and its effect with it")
	hero.begin_wave()
	check_eq(hero.outgoing_damage_mult(null, &"physical", &"weapon"), 1.0, "only the one wave")
	check_eq(seen, [10, 1, 0] as Array[int], "consumables_changed: bought, applied, cleared")


func test_a_potion_and_a_food_both_apply_and_a_newer_one_replaces() -> void:
	var hero := _hero()
	Consumables.give(hero, _c(&"flask_of_fury"))
	Consumables.give(hero, _c(&"spiced_onion_rings"))
	var replaced := Consumables.give(hero, _c(&"elixir_of_fortune"))
	check(replaced == _c(&"flask_of_fury"), "the pending flask was pushed out")
	hero.begin_wave()
	check_eq(hero.outgoing_damage_mult(null, &"physical", &"weapon"), 1.0, "the replaced flask never applies")
	check_eq(hero.stats.get_stat(Stats.FORTUNE), 25.0, "the elixir does")
	check_eq(hero.stats.get_stat(Stats.CRIT), 5.0, "and the food next to it")
	check_eq(hero.consumables_active.size(), 2, "potion + food")


func test_each_effect_does_what_the_card_says() -> void:
	var hero := _hero(&"warrior")
	hero.stats.set_source(&"item:test", {Stats.ARMOR: 20.0, Stats.STAMINA: 30.0})
	var armor := hero.stats.get_stat(Stats.ARMOR)
	var max_hp := hero.max_hp()
	var haste := hero.stats.get_stat(Stats.HASTE)
	var speed := hero.stats.get_stat(Stats.SPEED)
	var spirit := hero.stats.get_stat(Stats.SPIRIT)

	Consumables.give(hero, _c(&"elixir_of_ironskin"))
	hero.begin_wave()
	check_near(hero.stats.get_stat(Stats.ARMOR), armor * 1.3, 0.06, "Ironskin: +30% of the Armor the hero had")
	hero.end_wave()
	check_near(hero.stats.get_stat(Stats.ARMOR), armor, 0.001, "Armor back")

	Consumables.give(hero, _c(&"elixir_of_swiftness"))
	hero.begin_wave()
	check_eq(hero.stats.get_stat(Stats.HASTE), haste + 10.0, "Swiftness: +10% Haste")
	check_eq(hero.stats.get_stat(Stats.SPEED), speed + 10.0, "+10% move speed")
	hero.end_wave()
	check_eq(hero.stats.get_stat(Stats.HASTE), haste, "Haste back")

	Consumables.give(hero, _c(&"hearty_onion_stew"))
	hero.begin_wave()
	check_near(hero.max_hp(), max_hp * 1.15, 0.06, "Stew: +15% Max HP")
	check_eq(hero.stats.get_stat(Stats.SPIRIT), spirit + 5.0, "+5 Spirit")
	check_near(hero.hp, hero.max_hp(), 0.001, "healed to the new Max HP")
	hero.end_wave()
	check_near(hero.max_hp(), max_hp, 0.001, "Max HP back")
	check(hero.hp <= hero.max_hp(), "HP clamped to it")

	Consumables.give(hero, _c(&"smoked_boar_ribs"))
	hero.begin_wave()
	check_near(hero.bonuses.damage_taken_mult(&"melee", null), 0.92, 0.0001, "Ribs: -8% damage taken")
	hero.end_wave()
	check_near(hero.bonuses.damage_taken_mult(&"melee", null), 1.0, 0.0001, "gone")


func test_a_downed_hero_gets_the_effect_but_only_the_extra_max_hp_as_hp() -> void:
	var hero := _hero()
	hero.stats.set_source(&"item:test", {Stats.STAMINA: 90.0})
	hero.begin_wave()
	hero.hp = 0.0
	hero.downed = true
	Consumables.give(hero, _c(&"hearty_onion_stew"))
	var old_max := hero.max_hp()
	hero.begin_wave()
	var gain := hero.max_hp() - old_max
	check(gain > 0.0, "the Stew raised the Max HP")
	check_near(hero.hp, roundf(old_max * Player.WAVE_START_REVIVE_HP_RATIO) + gain, 0.01, "revived at 50% of the old Max HP + the new part")
	check(hero.hp < hero.max_hp(), "not a free full heal")


func test_apply_without_pending_is_a_no_op_and_clear_is_safe_twice() -> void:
	var hero := _hero()
	var changes := 0
	hero.consumables_changed.connect(func() -> void: changes += 1)
	hero.begin_wave()
	hero.end_wave()
	hero.end_wave()
	check_eq(changes, 0, "no consumables, no signal")
	Consumables.apply(null)
	Consumables.clear(null)
	Consumables.give(null, _c(&"flask_of_fury"))
	check(true, "null-safe")


func test_the_effects_survive_an_equipment_change_during_the_wave() -> void:
	var hero := _hero()
	Consumables.give(hero, _c(&"flask_of_fury"))
	hero.begin_wave()
	hero.apply_equipment()
	hero.bonuses.set_effects(&"set_bonus", [] as Array[Dictionary])
	check_near(hero.outgoing_damage_mult(null, &"physical", &"weapon"), 1.15, 0.0001, "the flask is still on")


# --- The stall: consumables row ----------------------------------------------------------------

func _stall(classes: Array[StringName] = [&"warrior", &"mage"]) -> Dictionary:
	var slots: Array[PlayerSlot] = []
	for i in classes.size():
		var p := _hero(classes[i], i)
		slots.append(p.slot)
	var shop := Shop.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	return {"shop": shop, "slots": slots, "rng": rng}


func test_open_round_fills_a_row_of_four_different_cards_next_to_the_offers() -> void:
	var s := _stall()
	var shop: Shop = s["shop"]
	shop.open_round(7, s["slots"], s["rng"])
	check_eq(shop.consumables.size(), 4, "four cards")
	check_eq(shop.offers.size(), Shop.offer_count(2), "the item offers are unchanged")
	var ids: Array[StringName] = []
	for c in shop.consumables:
		check(c.data != null and c.price == Consumables.price(c.data, 7), "priced for wave 7")
		check(c.data.id not in ids, "different")
		ids.append(c.data.id)
	check(shop.black_market == null, "no Black Market before wave 15")


func test_every_round_and_every_reroll_redraws_the_row() -> void:
	var s := _stall()
	var shop: Shop = s["shop"]
	var rng: RandomNumberGenerator = s["rng"]
	RunState.add_gold(5000)
	var rows: Dictionary[String, bool] = {}
	for round in 8:
		shop.open_round(3 + round, s["slots"], rng)
		rows[_row_key(shop)] = true
	check(rows.size() >= 3, "the row changes from round to round (%d different)" % rows.size())
	shop.open_round(5, s["slots"], rng)
	var joined: Array[int] = [0, 1]
	var before := _row_key(shop)
	var changed_rows := 0
	for i in 6:
		shop.reroll_votes = {0: true, 1: true}
		check(shop.try_reroll(joined, rng), "rerolled")
		if _row_key(shop) != before:
			changed_rows += 1
		before = _row_key(shop)
		for c in shop.consumables:
			check_eq(c.price, Consumables.price(c.data, 5), "priced at the round's wave")
	check(changed_rows >= 3, "a reroll redraws the row (%d of 6)" % changed_rows)


func _row_key(shop: Shop) -> String:
	var ids: Array[String] = []
	for c in shop.consumables:
		ids.append(String(c.data.id))
	return ",".join(ids)


func test_the_row_follows_the_reroll_even_when_every_item_offer_is_locked_but_cannot_start_one() -> void:
	var s := _stall()
	var shop: Shop = s["shop"]
	var rng: RandomNumberGenerator = s["rng"]
	RunState.add_gold(5000)
	shop.open_round(5, s["slots"], rng)
	for i in shop.offers.size():
		shop.toggle_lock(i, 0)
	shop.reroll_votes = {0: true, 1: true}
	var gold := RunState.gold
	check(not shop.try_reroll([0, 1] as Array[int], rng), "nothing to reroll: no charge, no reroll")
	check_eq(RunState.gold, gold, "nothing charged")
	check(not shop.reroll_ready([0, 1] as Array[int]), "the row alone never makes a reroll")


func test_the_row_does_not_touch_the_item_offers_or_the_main_rng() -> void:
	# Two stalls opened from the same seed: one with the row / Black Market, one without. The
	# item offers and the rng state afterwards are identical – the row has a side rng.
	var with := _stall()
	var without := _stall()
	var plain := PlainShop.new()
	var rng_a: RandomNumberGenerator = with["rng"]
	var rng_b: RandomNumberGenerator = without["rng"]
	var shop_a: Shop = with["shop"]
	for w in [3, 9, 16]:
		shop_a.open_round(w, with["slots"], rng_a)
		plain.open_round(w, without["slots"], rng_b)
		check_eq(shop_a.offers.size(), plain.offers.size(), "wave %d: same offer count" % w)
		for i in plain.offers.size():
			check_eq(shop_a.offers[i].item.display_name, plain.offers[i].item.display_name, "wave %d offer %d" % [w, i])
			check_eq(shop_a.offers[i].price, plain.offers[i].price, "wave %d price %d" % [w, i])
		check_eq(rng_a.state, rng_b.state, "wave %d: the rng state is the same" % w)
		check(not shop_a.consumables.is_empty() and plain.consumables.is_empty(), "the row exists only in the real stall")
	RunState.add_gold(5000)
	shop_a.reroll_votes = {0: true, 1: true}
	plain.reroll_votes = {0: true, 1: true}
	check(shop_a.try_reroll([0, 1] as Array[int], rng_a), "reroll")
	check(plain.try_reroll([0, 1] as Array[int], rng_b), "reroll")
	check_eq(rng_a.state, rng_b.state, "a reroll draws the same from the main rng")
	for i in plain.offers.size():
		check_eq(shop_a.offers[i].item.display_name, plain.offers[i].item.display_name, "rerolled offer %d" % i)


func test_buying_a_consumable_pays_logs_and_gives_the_hero_its_pending_item() -> void:
	var s := _stall()
	var shop: Shop = s["shop"]
	shop.open_round(6, s["slots"], s["rng"])
	var slots: Array[PlayerSlot] = s["slots"]
	var card := shop.consumables[0]
	var hero := slots[1].player as Player
	RunState.begin_spend_round()
	RunState.add_gold(500)
	var gold := RunState.gold
	var signals: Array = []
	shop.consumable_bought.connect(func(i: int, slot_index: int, price: int) -> void: signals.append([i, slot_index, price]))
	check_eq(shop.try_buy_consumable(0, slots[1]), Shop.BuyResult.OK, "bought")
	check_eq(RunState.gold, gold - card.price, "the shared wallet paid")
	check_eq(RunState.spend_log.size(), 1, "one spend entry")
	check_eq(RunState.spend_log[0]["kind"], &"consumable", "kind consumable")
	check_eq(RunState.spend_log[0]["slot"], 1, "by P2")
	check_eq(RunState.spend_log[0]["label"], card.data.display_name, "labelled")
	check_eq(RunState.consumables_bought, 1, "counted")
	check(Consumables.of_kind(hero.consumables_pending, card.data.kind) == card.data, "P2's hero holds it")
	check((slots[0].player as Player).consumables_pending.is_empty(), "P1's hero does not")
	check_eq(signals, [[0, 1, card.price]] as Array, "signal")
	check(shop.consumables[0] == card and shop.consumables.size() == 4, "unlimited stock: the card stays")
	check_eq(shop.try_buy_consumable(0, slots[1]), Shop.BuyResult.OK, "buy it again")
	check(shop.last_replaced == card.data, "the pending copy was replaced (no refund)")
	check_eq(RunState.consumables_bought, 2, "counted twice")
	check_eq(RunState.gold, gold - 2 * card.price, "paid twice")
	check_eq(shop.try_buy_consumable(0, slots[0]), Shop.BuyResult.OK, "P1 buys the same card for itself")
	check((slots[0].player as Player).consumables_pending.size() == 1, "its own copy")


func test_buying_a_consumable_refuses_without_gold_a_hero_or_a_card() -> void:
	var s := _stall()
	var shop: Shop = s["shop"]
	shop.open_round(6, s["slots"], s["rng"])
	var slots: Array[PlayerSlot] = s["slots"]
	check_eq(RunState.gold, 0, "empty wallet")
	check_eq(shop.try_buy_consumable(0, slots[0]), Shop.BuyResult.NOT_ENOUGH_GOLD, "not enough gold")
	check((slots[0].player as Player).consumables_pending.is_empty(), "nothing given")
	check_eq(RunState.consumables_bought, 0, "nothing counted")
	RunState.add_gold(100)
	check_eq(shop.try_buy_consumable(9, slots[0]), Shop.BuyResult.INVALID_OFFER, "no such card")
	check_eq(shop.try_buy_consumable(-1, slots[0]), Shop.BuyResult.INVALID_OFFER, "no such card (negative)")
	check_eq(shop.try_buy_consumable(0, null), Shop.BuyResult.NO_PLAYER, "no slot")
	var heroless := Fakes.make_slot(3, &"rogue")
	check_eq(shop.try_buy_consumable(0, heroless), Shop.BuyResult.NO_PLAYER, "no hero")
	check_eq(RunState.gold, 100, "nothing was spent")
	check(not shop.buy_consumable(0, null), "buy_consumable is the bool form")


# --- The Black Market --------------------------------------------------------------------------

func test_the_black_market_opens_at_wave_15() -> void:
	var s := _stall()
	var shop: Shop = s["shop"]
	shop.open_round(14, s["slots"], s["rng"])
	check(shop.black_market == null, "wave 14: closed")
	shop.open_round(15, s["slots"], s["rng"])
	check(shop.black_market != null, "wave 15: open")
	check_eq(shop.offers.size(), Shop.offer_count(2), "it takes no item offer's place")
	var o := shop.black_market
	check_eq(o.price, 3 * ItemGenerator.price_for(Items.Rarity.EPIC, 15), "3 x the Epic price of the wave")
	check_eq(o.price, 573, "about 570 g at wave 15 (GDD)")
	check_eq(o.item.rarity, Items.Rarity.EPIC, "an Epic, never Legendary")
	check_eq(o.item.buy_price, ItemGenerator.price_for(Items.Rarity.EPIC, 15), "the item keeps the normal Epic value")
	check(not o.sold and not o.is_locked() and not o.is_pinged(), "fresh")
	shop.open_round(22, s["slots"], s["rng"])
	check_eq(shop.black_market.price, 3 * ItemGenerator.price_for(Items.Rarity.EPIC, 22), "scales with the wave")
	shop.open_round(8, s["slots"], s["rng"])
	check(shop.black_market == null, "and is gone again below wave 15")
	check(BlackMarket.is_open(15) and not BlackMarket.is_open(14), "BlackMarket.is_open")
	check_eq(BlackMarket.price(15), 573, "BlackMarket.price")


func test_black_market_content_is_a_team_set_piece_or_a_max_roll_epic() -> void:
	var slots: Array[PlayerSlot] = []
	for i in 3:
		slots.append(_hero([&"warrior", &"mage", &"rogue"][i], i).slot)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var sets := 0
	var maxed := 0
	var team: Array[StringName] = [&"warrior", &"mage", &"rogue"]
	for i in 300:
		var item := BlackMarket.roll(18, slots, rng)
		check(item != null and item.rarity == Items.Rarity.EPIC, "an Epic")
		if item.set_id != &"":
			sets += 1
			var set_data := Db.get_set(item.set_id)
			check(set_data != null and set_data.class_id in team, "the piece is for a team class: %s" % item.set_id)
		else:
			maxed += 1
			check(item.enchants.size() >= 2, "a max-roll Epic has two enchants: %s" % item.display_name)
			check(item.looted, "rolled with the loot budget")
			var usable := false
			for c in team:
				usable = usable or item.can_be_used_by(Db.get_class_data(c))
			check(usable, "usable by somebody on the team: %s" % item.display_name)
		check_eq(item.buy_price, ItemGenerator.price_for(Items.Rarity.EPIC, 18), "Epic value")
	check(sets > 120 and sets < 240, "about 60%% set pieces (%d of 300)" % sets)
	check(maxed > 60, "about 40%% max-roll Epics (%d of 300)" % maxed)


func test_a_max_roll_epic_beats_a_normal_shop_epic() -> void:
	# The loot budget: every rolled stat of a max-roll Epic is at least what the shop budget gives.
	var shop_budget := ItemGenerator.stat_budget(Items.Rarity.EPIC, Items.SlotType.CHEST, 18, false)
	var loot_budget := ItemGenerator.stat_budget(Items.Rarity.EPIC, Items.SlotType.CHEST, 18, true)
	check_near(loot_budget / shop_budget, ItemGenerator.LOOTED_BUDGET_MULT, 0.0001, "the loot bonus")
	var slots: Array[PlayerSlot] = [_hero(&"warrior").slot]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var n := 0
	for i in 80:
		var item := BlackMarket.roll(18, slots, rng)
		if item.set_id != &"":
			continue
		n += 1
		check_eq(item.item_level, Items.item_level(18, Items.Rarity.EPIC, true), "item level of loot")
		var rank := ItemGenerator.enchant_rank(18, true)
		for e in item.enchants:
			check_eq(e.rank, rank, "enchants at the loot rank")
	check(n > 10, "enough max-roll samples")


func test_the_set_piece_prefers_what_the_set_still_misses() -> void:
	var hero := _hero(&"warrior")
	var set_data := Db.set_for_class(&"warrior")
	var slots: Array[PlayerSlot] = [hero.slot]
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	# The warrior wears three pieces and carries a fourth: only the fifth is missing.
	var owned: Array[StringName] = []
	for i in 4:
		var piece := ItemGenerator.from_unique(Db.get_unique(set_data.piece_ids[i]), 18, true, rng, hero.class_data)
		owned.append(piece.source_id)
		if i < 3:
			hero.equipment.slots[hero.equipment.default_slot(piece)] = piece
		else:
			hero.equipment.backpack.append(piece)
	var candidates := BlackMarket.set_piece_candidates(18, slots)
	check_eq(candidates.size(), 5, "all five pieces exist at wave 18")
	var missing: Array[StringName] = []
	for c in candidates:
		if c["missing"]:
			missing.append(c["data"].id)
	check_eq(missing, [set_data.piece_ids[4]] as Array[StringName], "one piece is missing")
	var hits := 0
	for i in 120:
		var item := BlackMarket.roll(18, slots, rng)
		if item.set_id == &"":
			continue
		hits += 1
		check_eq(item.source_id, set_data.piece_ids[4], "the missing piece, every time")
	check(hits > 40, "enough set rolls (%d)" % hits)
	# With the whole set owned any piece may come.
	var fifth := ItemGenerator.from_unique(Db.get_unique(set_data.piece_ids[4]), 18, true, rng, hero.class_data)
	hero.equipment.backpack.append(fifth)
	var seen: Dictionary[StringName, bool] = {}
	for i in 200:
		var item := BlackMarket.roll(18, slots, rng)
		if item.set_id != &"":
			seen[item.source_id] = true
	check(seen.size() >= 4, "a complete set: any piece (%d different)" % seen.size())


func test_a_team_without_a_set_piece_gets_the_max_roll_epic() -> void:
	var slots: Array[PlayerSlot] = [_hero(&"warrior").slot]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	# Before wave 6 no set piece exists (min_wave 6): every roll is a max-roll Epic.
	for i in 40:
		var item := BlackMarket.roll(4, slots, rng)
		check(item != null and item.set_id == &"" and item.rarity == Items.Rarity.EPIC, "wave 4: a plain max-roll Epic")
	check(BlackMarket.set_piece_candidates(4, slots).is_empty(), "no candidates at wave 4")
	check(BlackMarket.roll(18, [] as Array[PlayerSlot], rng) != null, "even an empty team gets an item")


func test_buying_the_black_market_offer() -> void:
	var s := _stall([&"warrior"])
	var shop: Shop = s["shop"]
	var slots: Array[PlayerSlot] = s["slots"]
	shop.open_round(16, slots, s["rng"])
	var o := shop.black_market
	var hero := slots[0].player as Player
	var bought: Array = []
	shop.bought.connect(func(i: int, slot_index: int, price: int) -> void: bought.append([i, slot_index, price]))
	check(shop.offer_at(Shop.BLACK_MARKET) == o, "offer_at(BLACK_MARKET)")
	check_eq(shop.try_buy(Shop.BLACK_MARKET, slots[0]), Shop.BuyResult.NOT_ENOUGH_GOLD, "too expensive for an empty wallet")
	check(not o.sold and hero.equipment.backpack.is_empty(), "nothing happened")
	RunState.begin_spend_round()
	RunState.add_gold(o.price + 7)
	check_eq(shop.try_buy(Shop.BLACK_MARKET, slots[0]), Shop.BuyResult.OK, "bought")
	check_eq(RunState.gold, 7, "paid the Black Market price")
	check(o.sold and hero.equipment.backpack.has(o.item), "the item is in the backpack")
	check_eq(RunState.spend_log[0]["kind"], &"black_market", "spend kind black_market")
	check_eq(RunState.spend_log[0]["amount"], o.price, "amount")
	check_eq(RunState.black_market_bought, 1, "counted")
	check_eq(bought, [[Shop.BLACK_MARKET, 0, o.price]] as Array, "bought signal with the BLACK_MARKET index")
	check_eq(shop.try_buy(Shop.BLACK_MARKET, slots[0]), Shop.BuyResult.SOLD, "sold")
	check_eq(RunState.black_market_bought, 1, "a second try counts nothing")


func test_a_full_backpack_refuses_the_black_market_offer_without_a_forge_partner() -> void:
	var s := _stall([&"warrior"])
	var shop: Shop = s["shop"]
	var slots: Array[PlayerSlot] = s["slots"]
	shop.open_round(16, slots, s["rng"])
	var hero := slots[0].player as Player
	for i in Items.BACKPACK_SIZE:
		hero.equipment.backpack.append(ItemGenerator.generate(ItemGenerator.Source.SHOP, 3, s["rng"], {&"rarity": Items.Rarity.COMMON, &"slot_type": Items.SlotType.RING}))
	RunState.add_gold(5000)
	var o := shop.black_market
	if o.item.is_weapon():
		o.item = ItemGenerator.generate(ItemGenerator.Source.LOOT, 16, s["rng"], {&"rarity": Items.Rarity.EPIC, &"slot_type": Items.SlotType.HEAD})
	check_eq(shop.try_buy(Shop.BLACK_MARKET, slots[0]), Shop.BuyResult.BACKPACK_FULL, "no room")
	check_eq(RunState.gold, 5000, "nothing spent")
	check(not o.sold and RunState.black_market_bought == 0, "still for sale")


func test_black_market_lock_ping_and_reroll() -> void:
	var s := _stall()
	var shop: Shop = s["shop"]
	var rng: RandomNumberGenerator = s["rng"]
	shop.open_round(15, s["slots"], rng)
	RunState.add_gold(9000)
	var first := shop.black_market
	# A ping keeps it out of a reroll.
	shop.toggle_ping(Shop.BLACK_MARKET, 1)
	check(first.is_pinged() and not shop.black_market_rerollable(), "pinged: not rerollable")
	shop.reroll_votes = {0: true, 1: true}
	check(shop.try_reroll([0, 1] as Array[int], rng), "the items still reroll")
	check(shop.black_market == first and not first.is_pinged(), "same offer, ping cleared by the reroll")
	# A lock keeps it for the next round.
	shop.toggle_lock(Shop.BLACK_MARKET, 0)
	check(first.is_locked() and not shop.black_market_rerollable(), "locked: not rerollable")
	shop.open_round(16, s["slots"], rng)
	check(shop.black_market == first, "a locked, unsold offer survives the round")
	check_eq(shop.black_market.price, BlackMarket.price(15), "it keeps the price of its wave")
	# Unlocked it is redrawn by a reroll and by a new round.
	shop.toggle_lock(Shop.BLACK_MARKET, 3)
	check(not first.is_locked() and shop.black_market_rerollable(), "any player may unlock it")
	shop.reroll_votes = {0: true, 1: true}
	check(shop.try_reroll([0, 1] as Array[int], rng), "reroll")
	check(shop.black_market != first, "a reroll redraws the Black Market")
	check_eq(shop.black_market.price, BlackMarket.price(16), "at the round's price")
	var second := shop.black_market
	shop.open_round(17, s["slots"], rng)
	check(shop.black_market != second, "a new round redraws it")
	# Sold offers do not stay locked and are redrawn too.
	shop.toggle_lock(Shop.BLACK_MARKET, 0)
	shop.black_market.sold = true
	shop.open_round(18, s["slots"], rng)
	check(not shop.black_market.sold, "a sold offer is replaced")


func test_the_black_market_alone_can_make_a_reroll_possible() -> void:
	var s := _stall()
	var shop: Shop = s["shop"]
	var rng: RandomNumberGenerator = s["rng"]
	shop.open_round(15, s["slots"], rng)
	RunState.add_gold(9000)
	for i in shop.offers.size():
		shop.toggle_lock(i, 0)
	check(shop.rerollable_positions().is_empty() and shop.black_market_rerollable(), "only the Black Market can change")
	shop.reroll_votes = {0: true, 1: true}
	check(shop.reroll_ready([0, 1] as Array[int]), "so a reroll is possible")
	var before := shop.black_market
	check(shop.try_reroll([0, 1] as Array[int], rng), "and goes through")
	check(shop.black_market != before, "it redrew the Black Market")
	for o in shop.offers:
		check(o.is_locked(), "the locked offers stayed")
	# Locked too: nothing is left to change.
	shop.toggle_lock(Shop.BLACK_MARKET, 0)
	shop.reroll_votes = {0: true, 1: true}
	check(not shop.reroll_ready([0, 1] as Array[int]), "everything locked: no reroll")


func test_black_market_rolls_use_the_side_rng_only() -> void:
	var s1 := _stall()
	var s2 := _stall()
	var plain := PlainShop.new()
	var shop: Shop = s1["shop"]
	var rng_a: RandomNumberGenerator = s1["rng"]
	var rng_b: RandomNumberGenerator = s2["rng"]
	shop.open_round(20, s1["slots"], rng_a)
	plain.open_round(20, s2["slots"], rng_b)
	check(shop.black_market != null and plain.black_market == null, "only the real stall has one")
	check_eq(rng_a.state, rng_b.state, "the main rng is untouched by the Black Market")
	for i in plain.offers.size():
		check_eq(shop.offers[i].item.display_name, plain.offers[i].item.display_name, "offer %d" % i)
