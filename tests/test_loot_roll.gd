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


func test_all_pass_loses_the_item() -> void:
	var roll := LootRoll.create(_sword())
	for i in 3:
		roll.choose(i, LootRoll.Choice.PASS)
	roll.resolve(rng)
	check_eq(roll.outcome, &"pass", "outcome")
	check_eq(roll.winner, -1, "no winner")
	check(roll.rolls.is_empty(), "nobody rolled")
	var gold := RunState.gold
	roll.apply(slots)
	check_eq(RunState.gold, gold, "no gold")
	for s in slots:
		check(Support.equipment_of(s).backpack.is_empty(), "no backpack gained an item")
	check_eq(RunState.greed_gold, 0, "no greed gold")


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


func test_bot_choice() -> void:
	var warrior := slots[0]
	var chest := Support.make_armor(20, ClassData.ArmorType.PLATE)
	check_eq(LootRoll.bot_choice(warrior, chest), LootRoll.Choice.NEED, "empty slot -> Need")
	Support.equipment_of(warrior).equip(Support.make_armor(20, ClassData.ArmorType.PLATE))
	check_eq(LootRoll.bot_choice(warrior, Support.make_armor(25, ClassData.ArmorType.PLATE)),
			LootRoll.Choice.NEED, "higher Item Level -> Need")
	check_eq(LootRoll.bot_choice(warrior, Support.make_armor(20, ClassData.ArmorType.PLATE)),
			LootRoll.Choice.GREED, "same Item Level -> Greed")
	check_eq(LootRoll.bot_choice(warrior, Support.make_armor(12, ClassData.ArmorType.PLATE)),
			LootRoll.Choice.GREED, "downgrade -> Greed")
	check_eq(LootRoll.bot_choice(slots[1], chest), LootRoll.Choice.GREED, "mage cannot wear plate -> Greed")
	check_eq(LootRoll.bot_choice(warrior, Support.make_weapon(&"bow")), LootRoll.Choice.GREED, "cannot use -> Greed")
	check_eq(LootRoll.bot_choice(slots[2], Support.make_weapon(&"bow")), LootRoll.Choice.NEED, "rogue + bow, empty slot")
	Support.fill_backpack(warrior)
	check_eq(LootRoll.bot_choice(warrior, Support.make_armor(99, ClassData.ArmorType.PLATE)),
			LootRoll.Choice.GREED, "no room -> Greed")
	check_eq(LootRoll.bot_choice(null, chest), LootRoll.Choice.GREED, "no slot")
	var ghost := PlayerSlot.new(5, ScriptedInput.new("ghost"), Color.WHITE)
	ghost.class_data = Db.get_class_data(&"warrior")
	check_eq(LootRoll.bot_choice(ghost, chest), LootRoll.Choice.GREED, "no player node")


func test_bot_compares_rings_against_the_default_slot() -> void:
	var rogue := slots[2]
	var eq := Support.equipment_of(rogue)
	var ring_a := Support.make_armor(30, Items.NO_ARMOR, 20, 0, Items.SlotType.RING)
	var ring_b := Support.make_armor(10, Items.NO_ARMOR, 20, 0, Items.SlotType.RING)
	check(eq.equip(ring_a), "equip ring 1")
	check_eq(LootRoll.bot_choice(rogue, Support.make_armor(5, Items.NO_ARMOR, 20, 0, Items.SlotType.RING)),
			LootRoll.Choice.NEED, "second ring slot is empty -> Need")
	check(eq.equip(ring_b), "equip ring 2")
	check_eq(LootRoll.bot_choice(rogue, Support.make_armor(20, Items.NO_ARMOR, 20, 0, Items.SlotType.RING)),
			LootRoll.Choice.GREED, "both slots full: compared with the default position (ring 1, level 30)")
	check_eq(LootRoll.bot_choice(rogue, Support.make_armor(35, Items.NO_ARMOR, 20, 0, Items.SlotType.RING)),
			LootRoll.Choice.NEED, "better than ring 1")
