extends TestCase
## LootRoll: Need / Greed / Pass rules, roll tie-breaks, application, bot choices.

const Support := preload("res://tests/test_loot_support.gd")

var slots: Array[PlayerSlot] = []
var rng: RandomNumberGenerator


func before_each() -> void:
	RunState.start_run(3, 11)
	rng = RandomNumberGenerator.new()
	rng.seed = 1234
	slots = Support.make_slots([&"warrior", &"mage", &"rogue"] as Array[StringName])


func after_each() -> void:
	Support.free_slots(slots)
	slots.clear()


func _sword() -> ItemInstance:
	return Support.make_weapon(&"sword", Items.Rarity.RARE, 60)


func _all() -> Array[int]:
	return [0, 1, 2]


## First seed whose rolls (one per entry of [param count], 1-100, in order) satisfy [param ok].
func _find_seed(count: int, ok: Callable) -> int:
	for s in range(1, 200000):
		var probe := RandomNumberGenerator.new()
		probe.seed = s
		var rolls: Array[int] = []
		for _i in count:
			rolls.append(probe.randi_range(1, 100))
		if ok.call(rolls):
			return s
	return -1


func test_can_need_requires_proficiency_and_space() -> void:
	var roll := LootRoll.create(_sword())
	check(roll.can_need(slots[0]), "warrior uses swords")
	check(roll.can_need(slots[1]), "mage uses swords too")
	var bow := LootRoll.create(Support.make_weapon(&"bow"))
	check(not bow.can_need(slots[0]), "warrior cannot use a bow")
	check(bow.can_need(slots[2]), "rogue can")
	check(bow.need_blocked_reason(slots[0]).begins_with("Cannot use"), "reason: cannot use")
	check_eq(bow.need_blocked_reason(slots[2]), "", "no reason when allowed")
	Support.fill_backpack(slots[0])
	check(not roll.can_need(slots[0]), "full backpack blocks Need")
	check_eq(roll.need_blocked_reason(slots[0]), "Backpack full", "reason: backpack full")
	var ghost := PlayerSlot.new(5, ScriptedInput.new("ghost"), Color.WHITE)
	ghost.class_data = Db.get_class_data(&"warrior")
	check(not roll.can_need(ghost), "a slot without a player cannot Need")
	check(not roll.can_need(null), "null slot")


func test_choose_and_all_decided() -> void:
	var roll := LootRoll.create(_sword())
	check(not roll.all_decided(_all()), "nobody decided")
	roll.choose(0, LootRoll.Choice.NEED)
	roll.choose(1, LootRoll.Choice.PASS)
	check(not roll.all_decided(_all()), "P3 still undecided")
	check(roll.all_decided([0, 1] as Array[int]), "P1 + P2 decided")
	roll.choose(2, LootRoll.Choice.GREED)
	check(roll.all_decided(_all()), "all decided")
	check_eq(roll.choice_of(2), LootRoll.Choice.GREED, "choice stored")
	roll.choose(2, LootRoll.Choice.PASS)
	check_eq(roll.choice_of(2), LootRoll.Choice.PASS, "a choice can be changed before resolve")
	check_eq(roll.choice_of(7), LootRoll.Choice.UNDECIDED, "unknown slot is undecided")
	check(roll.all_decided([] as Array[int]), "vacuously decided")


func test_all_pass_disenchants_the_item_into_team_dust() -> void:
	var item := _sword()
	item.rarity = Items.Rarity.EPIC
	var roll := LootRoll.create(item)
	for i in 3:
		roll.choose(i, LootRoll.Choice.PASS)
	roll.resolve(rng)
	check_eq(roll.outcome, &"pass", "outcome")
	check_eq(roll.winner, -1, "no winner")
	check(roll.rolls.is_empty(), "nobody rolled")
	var gold := RunState.gold
	var dust := RunState.arcane_dust
	roll.apply(slots)
	check_eq(RunState.gold, gold, "no gold")
	check_eq(RunState.arcane_dust, dust + 8, "an Epic is 8 Dust for the team")
	check_eq(roll.dust, 8, "the roll remembers it")
	check_eq(RunState.dust_earned, 8, "counted as earned")
	check_eq(int(RunState.dust_gain_log[0]["slot"]), -1, "the team's, not a player's")
	for s in slots:
		check(Support.equipment_of(s).backpack.is_empty(), "no backpack gained an item")
	check_eq(RunState.greed_gold, 0, "no greed gold")
	roll.apply(slots)
	check_eq(RunState.arcane_dust, dust + 8, "apply works once")


func test_dust_by_rarity_when_everybody_passes() -> void:
	var want: Array[int] = [1, 2, 4, 8, 16]
	for r in 5:
		RunState.start_run(3, 5)
		var item := _sword()
		item.rarity = r
		var roll := LootRoll.create(item)
		roll.resolve(rng)  # nobody decided: everybody passes
		roll.apply(slots)
		check_eq(RunState.arcane_dust, want[r], "%s = %d Dust" % [Items.RARITY_NAMES[r], want[r]])


func test_an_artifact_nobody_wants_is_lost_not_disenchanted() -> void:
	var item := _sword()
	item.rarity = Items.Rarity.ARTIFACT
	var roll := LootRoll.create(item)
	roll.resolve(rng)
	roll.apply(slots)
	check_eq(roll.outcome, &"pass", "passed")
	check_eq(RunState.arcane_dust, 0, "no Dust from an Artifact")
	check_eq(roll.dust, 0, "none recorded")


func test_need_and_greed_make_no_dust() -> void:
	var needed := LootRoll.create(_sword())
	needed.choose(0, LootRoll.Choice.NEED)
	needed.resolve(rng)
	needed.apply(slots)
	var sold := LootRoll.create(_sword())
	sold.choose(1, LootRoll.Choice.GREED)
	sold.resolve(rng)
	sold.apply(slots)
	check_eq(RunState.arcane_dust, 0, "only a pass by everybody disenchants")


func test_undecided_counts_as_pass() -> void:
	var roll := LootRoll.create(_sword())
	roll.resolve(rng)
	check_eq(roll.outcome, &"pass", "everybody undecided -> pass")
	var roll2 := LootRoll.create(_sword())
	roll2.choose(1, LootRoll.Choice.NEED)
	roll2.resolve(rng)
	check_eq(roll2.outcome, &"need", "the only decided player")
	check_eq(roll2.winner, 1, "wins")
	check_eq(roll2.rolls.keys(), [1], "only they rolled")


func test_need_beats_greed_and_only_needers_roll() -> void:
	var roll := LootRoll.create(_sword())
	roll.choose(0, LootRoll.Choice.GREED)
	roll.choose(1, LootRoll.Choice.NEED)
	roll.choose(2, LootRoll.Choice.PASS)
	roll.resolve(rng)
	check_eq(roll.outcome, &"need", "need outcome")
	check_eq(roll.winner, 1, "the needer wins whatever anybody rolls")
	check_eq(roll.rolls.keys(), [1], "greeders and passers do not roll")
	check(roll.rolls[1] >= 1 and roll.rolls[1] <= 100, "1-100")


func test_highest_roll_wins() -> void:
	var seed_value := _find_seed(3, func(r: Array[int]) -> bool:
		return r[0] != r[1] and r[1] != r[2] and r[0] != r[2])
	check(seed_value > 0, "found a tie-free seed")
	var probe := RandomNumberGenerator.new()
	probe.seed = seed_value
	var expected: Array[int] = [probe.randi_range(1, 100), probe.randi_range(1, 100), probe.randi_range(1, 100)]
	rng.seed = seed_value
	var roll := LootRoll.create(_sword())
	for i in 3:
		roll.choose(i, LootRoll.Choice.NEED)
	roll.resolve(rng)
	for i in 3:
		check_eq(roll.rolls[i], expected[i], "P%d roll" % (i + 1))
	check_eq(roll.winner, expected.find(expected.max()), "highest roll wins")
	check_eq(roll.roll_history.size(), 3, "one round")


func test_tie_rerolls_among_the_tied_only() -> void:
	# Seed whose first round is a tie between P1 and P2, with P3 lower.
	var seed_value := _find_seed(3, func(r: Array[int]) -> bool:
		return r[0] == r[1] and r[2] < r[0])
	check(seed_value > 0, "found a tie seed")
	rng.seed = seed_value
	var probe := RandomNumberGenerator.new()
	probe.seed = seed_value
	var first: Array[int] = [probe.randi_range(1, 100), probe.randi_range(1, 100), probe.randi_range(1, 100)]
	var roll := LootRoll.create(_sword())
	for i in 3:
		roll.choose(i, LootRoll.Choice.NEED)
	roll.resolve(rng)
	check(roll.roll_history.size() >= 5, "3 first rolls + at least 2 tie-break rolls")
	for i in 3:
		var entry := roll.roll_history[i]
		check_eq(entry["round"], 0, "first round")
		check_eq(entry["roll"], first[i], "first round roll %d" % i)
	for i in range(3, roll.roll_history.size()):
		var entry := roll.roll_history[i]
		check(entry["round"] >= 1, "tie-break round")
		check(entry["slot"] != 2, "the lower roller is not in the tie-break")
	check(roll.winner == 0 or roll.winner == 1, "winner comes from the tie")
	check_eq(roll.rolls[2], first[2], "the outsider keeps their first roll")
	var other := 1 - roll.winner
	check(roll.rolls[roll.winner] > roll.rolls[other], "winner out-rolled the other tied player in the last round")


func test_greed_sells_into_the_shared_wallet() -> void:
	var item := _sword()
	item.buy_price = 61
	var roll := LootRoll.create(item)
	roll.choose(0, LootRoll.Choice.GREED)
	roll.choose(1, LootRoll.Choice.GREED)
	roll.choose(2, LootRoll.Choice.PASS)
	roll.resolve(rng)
	check_eq(roll.outcome, &"greed", "greed outcome")
	check(roll.winner == 0 or roll.winner == 1, "a greeder 'wins' for the statistics")
	check_eq(roll.rolls.size(), 2, "greeders roll")
	var gold := RunState.gold
	roll.apply(slots)
	check_eq(item.greed_value(), 31, "50% of 61, rounded")
	check_eq(RunState.gold, gold + 31, "gold added")
	check_eq(RunState.greed_gold, 31, "greed statistic")
	for s in slots:
		check(Support.equipment_of(s).backpack.is_empty(), "item not given to anybody")
	roll.apply(slots)
	check_eq(RunState.gold, gold + 31, "apply twice pays once")


func test_need_winner_gets_the_item() -> void:
	var item := _sword()
	var roll := LootRoll.create(item)
	roll.choose(0, LootRoll.Choice.NEED)
	roll.choose(1, LootRoll.Choice.NEED)
	roll.choose(2, LootRoll.Choice.GREED)
	roll.resolve(rng)
	var winner := roll.winner
	var gold := RunState.gold
	roll.apply(slots)
	check(Support.equipment_of(slots[winner]).backpack.has(item), "winner's backpack holds the item")
	for s in slots:
		if s.index != winner:
			check(Support.equipment_of(s).backpack.is_empty(), "nobody else got it")
	check_eq(RunState.need_wins_by_player.get(winner, 0), 1, "need win recorded")
	check_eq(RunState.need_wins_by_player.size(), 1, "only the winner")
	check_eq(RunState.gold, gold, "no gold for a Need")
	roll.apply(slots)
	check_eq(Support.equipment_of(slots[winner]).backpack.size(), 1, "apply twice gives it once")


func test_need_winner_with_a_full_backpack_sells_instead() -> void:
	var item := _sword()
	item.buy_price = 40
	var roll := LootRoll.create(item)
	roll.choose(1, LootRoll.Choice.NEED)
	roll.resolve(rng)
	Support.fill_backpack(slots[1])  # filled up between the choice and the application
	var gold := RunState.gold
	roll.apply(slots)
	check_eq(roll.outcome, &"greed", "falls back to Greed")
	check_eq(RunState.gold, gold + 20, "sold for the Greed price")
	check(RunState.need_wins_by_player.is_empty(), "not counted as a Need win")
	check(not Support.equipment_of(slots[1]).backpack.has(item), "not in the backpack")


func test_resolve_is_final() -> void:
	var roll := LootRoll.create(_sword())
	roll.choose(0, LootRoll.Choice.NEED)
	roll.resolve(rng)
	var winner := roll.winner
	var history := roll.roll_history.size()
	roll.choose(1, LootRoll.Choice.NEED)
	roll.resolve(rng)
	check_eq(roll.winner, winner, "second resolve changes nothing")
	check_eq(roll.roll_history.size(), history, "no extra rolls")
	check_eq(roll.choice_of(1), LootRoll.Choice.UNDECIDED, "late choice ignored")
	var unresolved := LootRoll.create(_sword())
	unresolved.apply(slots)
	check(Support.equipment_of(slots[0]).backpack.is_empty(), "apply before resolve does nothing")


## A hand-made item of [param slot_type] with [param stats] (no generator).
static func _gear(item_level: int, armor_type: int, stats: Dictionary,
		slot_type: Items.SlotType = Items.SlotType.CHEST) -> ItemInstance:
	var item := Support.make_armor(item_level, armor_type, 20, Items.Rarity.COMMON, slot_type)
	for stat: StringName in stats:
		item.stats[stat] = float(stats[stat])
	return item


func test_bot_choice() -> void:
	var warrior := slots[0]
	var chest := Support.make_armor(20, ClassData.ArmorType.PLATE)
	check_eq(LootRoll.bot_choice(warrior, chest), LootRoll.Choice.NEED, "empty slot -> Need")
	check(Support.equipment_of(warrior).equip(_gear(20, ClassData.ArmorType.PLATE, {Stats.STRENGTH: 4, Stats.ARMOR: 3})), "plate chest on")
	check_eq(LootRoll.bot_choice(warrior, _gear(25, ClassData.ArmorType.PLATE, {Stats.STRENGTH: 8, Stats.ARMOR: 3})),
			LootRoll.Choice.NEED, "better stats -> Need")
	check_eq(LootRoll.bot_choice(warrior, _gear(30, ClassData.ArmorType.PLATE, {Stats.STRENGTH: 4, Stats.ARMOR: 3})),
			LootRoll.Choice.GREED, "same stats: a higher Item Level alone is no upgrade -> Greed")
	check_eq(LootRoll.bot_choice(warrior, _gear(12, ClassData.ArmorType.PLATE, {Stats.STRENGTH: 1})),
			LootRoll.Choice.GREED, "downgrade -> Greed")
	check_eq(LootRoll.bot_choice(warrior, _gear(40, ClassData.ArmorType.CLOTH, {Stats.INTELLECT: 12})),
			LootRoll.Choice.GREED, "a cloth Intellect robe is no upgrade for a Warrior in plate -> Greed")
	check_eq(LootRoll.bot_choice(slots[1], _gear(40, ClassData.ArmorType.CLOTH, {Stats.INTELLECT: 12})),
			LootRoll.Choice.NEED, "but the Mage needs it")
	check_eq(LootRoll.bot_choice(slots[1], chest), LootRoll.Choice.GREED, "mage cannot wear plate -> Greed")
	check_eq(LootRoll.bot_choice(warrior, Support.make_weapon(&"bow")), LootRoll.Choice.GREED, "cannot use -> Greed")
	check_eq(LootRoll.bot_choice(slots[2], Support.make_weapon(&"bow")), LootRoll.Choice.NEED, "rogue + bow, empty slot")
	Support.fill_backpack(warrior)
	check_eq(LootRoll.bot_choice(warrior, _gear(99, ClassData.ArmorType.PLATE, {Stats.STRENGTH: 30})),
			LootRoll.Choice.GREED, "no room -> Greed")
	check_eq(LootRoll.bot_choice(null, chest), LootRoll.Choice.GREED, "no slot")
	var ghost := PlayerSlot.new(5, ScriptedInput.new("ghost"), Color.WHITE)
	ghost.class_data = Db.get_class_data(&"warrior")
	check_eq(LootRoll.bot_choice(ghost, chest), LootRoll.Choice.GREED, "no player node")


## Bots roll with the same upgrade test they equip with (ItemTooltip.upgrade_direction vs
## ItemTooltip.equipped_for_compare): rings against the weaker ring, by stats.
func test_bot_compares_rings_against_the_weaker_ring() -> void:
	var rogue := slots[2]
	var eq := Support.equipment_of(rogue)
	var ring_a := _gear(30, Items.NO_ARMOR, {Stats.AGILITY: 6}, Items.SlotType.RING)
	var ring_b := _gear(10, Items.NO_ARMOR, {Stats.AGILITY: 2}, Items.SlotType.RING)
	check(eq.equip(ring_a), "equip ring 1")
	check_eq(LootRoll.bot_choice(rogue, _gear(5, Items.NO_ARMOR, {Stats.AGILITY: 1}, Items.SlotType.RING)),
			LootRoll.Choice.NEED, "second ring slot is empty -> Need")
	check(eq.equip(ring_b), "equip ring 2")
	check_eq(LootRoll.bot_choice(rogue, _gear(20, Items.NO_ARMOR, {Stats.AGILITY: 2}, Items.SlotType.RING)),
			LootRoll.Choice.GREED, "no better than the weaker ring -> Greed")
	check_eq(LootRoll.bot_choice(rogue, _gear(15, Items.NO_ARMOR, {Stats.AGILITY: 4}, Items.SlotType.RING)),
			LootRoll.Choice.NEED, "better than the weaker ring (ring 2) -> Need")
	check_eq(LootRoll.bot_choice(rogue, _gear(35, Items.NO_ARMOR, {Stats.INTELLECT: 3}, Items.SlotType.RING)),
			LootRoll.Choice.GREED, "Item Level alone is no upgrade")


## The rogue holds two daggers: a bow (two-hander) is weighed against both of them.
func test_bot_choice_weighs_a_two_hander_against_both_hands() -> void:
	var rogue := slots[2]
	var eq := Support.equipment_of(rogue)
	eq.equip_starting_weapons()
	check_eq(LootRoll.bot_choice(rogue, Support.make_weapon(&"bow", Items.Rarity.EPIC)), LootRoll.Choice.GREED,
			"an Epic bow is worse than two daggers")
	var dagger := ItemTooltip.weapon_dps(eq.get_item(Items.EquipSlot.MAIN_HAND), Stats.AGILITY, ItemTooltip.NOMINAL_PRIMARY)
	check(ItemTooltip.weapon_dps(Support.make_weapon(&"bow", Items.Rarity.EPIC), Stats.AGILITY, ItemTooltip.NOMINAL_PRIMARY) > dagger,
			"(although it beats one dagger)")


# --- Tier sets and special drops (M5) ----------------------------------------------------------

static func _set_piece(id: StringName) -> ItemInstance:
	return ItemGenerator.from_unique(Db.get_unique(id), 9, true, RandomNumberGenerator.new())


## Bots Need a set piece that completes a set bonus even when its stats are a little worse
## (GDD 5.5 "Botok": up to 30% below what it replaces), and Greed it when it is far worse.
func test_bot_needs_a_set_piece_that_completes_a_bonus() -> void:
	var warrior := slots[0]
	var eq := Support.equipment_of(warrior)
	check(eq.equip(_set_piece(&"set_warrior_head")), "one piece worn")
	var hands := _set_piece(&"set_warrior_hands")
	var score := ItemTooltip.item_score(hands, warrior.class_data)
	var gloves := _gear(30, ClassData.ArmorType.PLATE, {Stats.STRENGTH: 14, Stats.STAMINA: 2}, Items.SlotType.HANDS)
	check(ItemTooltip.item_score(gloves, warrior.class_data) > score and score >= ItemTooltip.item_score(gloves, warrior.class_data) * 0.7,
		"fixture: the gloves are a little better")
	check(eq.equip(gloves), "plain gloves on")
	check_eq(LootRoll.bot_choice(warrior, hands), LootRoll.Choice.NEED, "the 2-piece bonus is worth it -> Need")
	check(eq.equip(_gear(30, ClassData.ArmorType.PLATE, {Stats.STRENGTH: 20, Stats.STAMINA: 4}, Items.SlotType.HANDS)), "far better gloves on")
	check_eq(LootRoll.bot_choice(warrior, hands), LootRoll.Choice.GREED, "more than 30% worse -> Greed")
	check_eq(LootRoll.bot_choice(slots[1], hands), LootRoll.Choice.GREED, "another class's piece -> Greed")


## A plain piece for [param set_item]'s slot with its stats raised by [param factor].
static func _plain_like(set_item: ItemInstance, factor: float) -> ItemInstance:
	var stats: Dictionary = {}
	for stat: StringName in set_item.stats:
		stats[stat] = set_item.stats[stat] * factor
	return _gear(set_item.item_level, set_item.armor_type, stats, set_item.slot_type)


## The review case (GDD 5.5 "Botok"): a warrior wears the Battlegear head + chest (2-piece)
## and plain legs / hands ~10% better than the set legs / hands. A 3rd piece crosses no
## threshold on its own, so the bots look ahead to the backpack: with the 4th piece waiting
## there, the 3rd one counts (Need, equip) and the bot reaches the 4-piece.
func test_bots_look_ahead_to_the_backpack_for_the_4_piece() -> void:
	var warrior := slots[0]
	var cls := warrior.class_data
	var eq := Support.equipment_of(warrior)
	check(eq.equip(_set_piece(&"set_warrior_head")) and eq.equip(_set_piece(&"set_warrior_chest")), "2-piece worn")
	var legs := _set_piece(&"set_warrior_legs")
	var hands := _set_piece(&"set_warrior_hands")
	var plain_legs := _plain_like(legs, 1.1)
	var plain_hands := _plain_like(hands, 1.1)
	for pair: Array in [[legs, plain_legs], [hands, plain_hands]]:
		var s := ItemTooltip.item_score(pair[0], cls)
		var p := ItemTooltip.item_score(pair[1], cls)
		check(p - s > ItemTooltip.UPGRADE_THRESHOLD and s >= p * (1.0 - ItemTooltip.SET_UPGRADE_TOLERANCE),
			"fixture: the plain piece is ~10%% better (%.1f vs %.1f)" % [p, s])
	check(eq.equip(plain_legs) and eq.equip(plain_hands), "plain legs and hands on")
	check_eq(LootRoll.bot_choice(warrior, legs), LootRoll.Choice.GREED, "nothing in the backpack: a 3rd piece goes by its stats")
	check(eq.add_to_backpack(hands), "the set hands wait in the backpack")
	check_eq(LootRoll.bot_choice(warrior, legs), LootRoll.Choice.NEED, "with the 4th piece in the backpack: Need the 3rd")
	check(eq.add_to_backpack(legs), "won")
	check_eq(ItemTooltip.upgrade_direction(legs, plain_legs, cls, eq), 1, "legs: an upgrade")
	check_eq(ItemTooltip.upgrade_direction(hands, plain_hands, cls, eq), 1, "hands: an upgrade")
	check_eq(Intermission.bot_equip_upgrades(warrior), 2, "the bot puts both on")
	check_eq(SetBonuses.counts(eq).get(&"battlegear_of_fury", 0), 4, "4 pieces worn")
	check_eq(SetBonuses.active_count(eq), 2, "the 4-piece bonus is reached")
	check_eq(Intermission.bot_equip_upgrades(warrior), 0, "and kept: the plain pieces would break it")


## A warrior bot (a fresh slot, freed in after_each) wearing the Battlegear pieces [param worn]
## and, in each slot of [param plain], a plain piece better than the set piece by the factor
## given there; the set pieces of those slots are returned by part name.
func _fury_bot(worn: Array[String], plain: Dictionary) -> Dictionary:
	var bot := Support.make_slot(3, &"warrior")
	slots.append(bot)
	var cls := bot.class_data
	var eq := Support.equipment_of(bot)
	for part in worn:
		check(eq.equip(_set_piece(StringName("set_warrior_" + part))), "%s worn" % part)
	var out: Dictionary = {"slot": bot, "eq": eq}
	for part: String in plain:
		var set_item := _set_piece(StringName("set_warrior_" + part))
		var plain_item := _plain_like(set_item, float(plain[part]))
		var s_score := ItemTooltip.item_score(set_item, cls)
		var p_score := ItemTooltip.item_score(plain_item, cls)
		check(p_score - s_score > ItemTooltip.UPGRADE_THRESHOLD and s_score >= p_score * (1.0 - ItemTooltip.SET_UPGRADE_TOLERANCE),
			"fixture: the plain %s is a little better (%.1f vs %.1f)" % [part, p_score, s_score])
		check(eq.equip(plain_item), "plain %s on" % part)
		out[part] = set_item
		out["plain_" + part] = plain_item
	return out


## Review case A: 3 pieces worn, the set legs and hands both wait in the backpack. Either is
## the 4th piece, the spare one does not cancel it out: both count as upgrades, the bot puts
## one on and keeps the plain item in the other slot (a 5th piece goes by its stats).
func test_bots_put_the_4th_piece_on_when_a_spare_waits_too() -> void:
	var b := _fury_bot(["head", "chest", "shoulders"] as Array[String], {"legs": 1.1, "hands": 1.15})
	var bot: PlayerSlot = b["slot"]
	var eq: Equipment = b["eq"]
	var cls := bot.class_data
	check(eq.add_to_backpack(b["legs"]) and eq.add_to_backpack(b["hands"]), "both set pieces wait")
	check_eq(ItemTooltip.upgrade_direction(b["legs"], b["plain_legs"], cls, eq), 1, "legs: the 4th piece")
	check_eq(ItemTooltip.upgrade_direction(b["hands"], b["plain_hands"], cls, eq), 1, "hands: the 4th piece too")
	check_eq(Intermission.bot_equip_upgrades(bot), 1, "the bot puts one on")
	check_eq(SetBonuses.counts(eq).get(&"battlegear_of_fury", 0), 4, "4 pieces worn")
	check_eq(SetBonuses.active_count(eq), 2, "the 4-piece bonus is reached")
	check(eq.get_item(Items.EquipSlot.HANDS) == b["plain_hands"], "the plain hands stay on")


## Review case B: 2 pieces worn, three more wait in the backpack. Each is a 3rd piece with a
## 4th one in reach, so each counts; the bot goes from 2 to 4 pieces in one market.
func test_bots_go_from_2_to_4_pieces_with_three_waiting() -> void:
	var b := _fury_bot(["head", "chest"] as Array[String], {"legs": 1.1, "hands": 1.15, "shoulders": 1.1})
	var bot: PlayerSlot = b["slot"]
	var eq: Equipment = b["eq"]
	var cls := bot.class_data
	for part in ["legs", "hands", "shoulders"]:
		check(eq.add_to_backpack(b[part]), "set %s waits" % part)
	for part in ["legs", "hands", "shoulders"]:
		check_eq(ItemTooltip.upgrade_direction(b[part], b["plain_" + part], cls, eq), 1, "%s: an upgrade" % part)
	var more := _set_piece(&"set_warrior_legs")
	eq.remove_from_backpack(b["legs"])
	check_eq(LootRoll.bot_choice(bot, more), LootRoll.Choice.NEED, "a rolled 3rd piece with two more waiting: Need")
	check(eq.add_to_backpack(b["legs"]), "legs back")
	check_eq(Intermission.bot_equip_upgrades(bot), 2, "the bot puts two on")
	check_eq(SetBonuses.counts(eq).get(&"battlegear_of_fury", 0), 4, "4 pieces worn")
	check_eq(SetBonuses.active_count(eq), 2, "the 4-piece bonus is reached")
	check_eq(Intermission.bot_equip_upgrades(bot), 0, "and kept")


## Review case C: a full set gives one piece away for a better plain item (5 -> 4 keeps the
## 4-piece), but not a second one – the piece it gave away waits in the backpack and must not
## count as worn. Both orders of the plain items end the pass with the 4-piece active.
func test_bots_keep_the_4_piece_when_trading_from_5() -> void:
	for plain_order: Array in [["legs", "hands"], ["hands", "legs"]]:
		var b := _fury_bot(["head", "chest", "shoulders", "legs", "hands"] as Array[String], {})
		var bot: PlayerSlot = b["slot"]
		var eq: Equipment = b["eq"]
		var factors: Dictionary = {"legs": 1.1, "hands": 1.15}
		for part: String in plain_order:
			var worn := eq.get_item(Items.equip_slots_for(_set_piece(StringName("set_warrior_" + part)).slot_type)[0])
			check(eq.add_to_backpack(_plain_like(worn, factors[part])), "plain %s waits" % part)
		check_eq(Intermission.bot_equip_upgrades(bot), 1, "%s first: one plain item goes on" % plain_order[0])
		check(eq.get_item(Items.EquipSlot.LEGS if plain_order[0] == "legs" else Items.EquipSlot.HANDS).set_id == &"",
			"the first one (5 -> 4)")
		check_eq(SetBonuses.counts(eq).get(&"battlegear_of_fury", 0), 4, "4 pieces worn")
		check_eq(SetBonuses.active_count(eq), 2, "the 4-piece bonus is kept")
		check_eq(Intermission.bot_equip_upgrades(bot), 0, "and stays")


## Guaranteed drops of elites / the goblin / bosses (LootDrops.drop_special) roll their
## Epics into set pieces at the loot rate, always for a class of the party.
func test_special_drops_roll_set_pieces_for_the_party() -> void:
	PlayerManager.clear()
	PlayerManager.add_bot(&"warlock", 1)
	PlayerManager.add_bot(&"paladin", 2)
	RunState.start_run(2, 808)
	RunState.set_wave(14)
	var world := Node3D.new()
	tree.root.add_child(world)
	var enemy := Node3D.new()
	world.add_child(enemy)
	var classes := {}
	var pieces := 0
	for i in 600:
		var bag := LootDrops.drop_special(ItemGenerator.Source.BOSS, enemy, null)
		check(bag != null and bag.item.rarity >= Items.Rarity.EPIC, "boss drops are Epic+")
		if bag != null and bag.item.set_id != &"":
			pieces += 1
			if bag.item.class_restriction != &"":
				classes[bag.item.class_restriction] = true
			else:
				# A class-independent set piece: some party class can wear it.
				check(bag.item.can_be_used_by(Db.get_class_data(&"warlock")) or bag.item.can_be_used_by(Db.get_class_data(&"paladin")),
						"a class-free piece fits the party")
			check(bag.item.looted, "looted")
		if bag != null:
			bag.free()
	world.free()
	PlayerManager.clear()
	check(pieces > 30, "some boss Epics are set pieces (%d / 600)" % pieces)
	check_eq(classes.keys().size(), 2, "both party classes: %s" % [classes.keys()])
	for c in classes:
		check(c in [&"warlock", &"paladin"], "a party class: %s" % c)
	check_eq(RunState.loot_drops_this_wave, 0, "special drops never count against the cap")
