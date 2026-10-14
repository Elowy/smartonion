extends TestCase
## Arcane Dust and the Enchanter (GDD 5.7, M6a ENCHANTER, core/items/enchanter.gd): rank V
## (RANK_MULT, labels, the generator staying at III), Disenchant yields and guards, the prices
## (25% of the shop price x 2^uses, the rarity's Dust x 2^uses), Reroll / Empower / Imbue rules
## and effects, paying gold AND Dust (kind &"enchant", enchants_done, enchant_uses), name
## prefixes, Equipment.changed, and the bot rules.

const Support := preload("res://tests/test_loot_support.gd")
const Fakes := preload("res://tests/player_fakes.gd")

var rng: RandomNumberGenerator
var slots: Array[PlayerSlot] = []


func before_each() -> void:
	RunState.start_run(2, 31)
	RunState.wave = 15
	rng = RandomNumberGenerator.new()
	rng.seed = 777
	slots.clear()


func after_each() -> void:
	Support.free_slots(slots)
	slots.clear()
	RunState.start_run(1, 7)


# --- Fixtures ----------------------------------------------------------------------------------

func _slot(class_id: StringName = &"warrior") -> PlayerSlot:
	var s := Support.make_slot(slots.size(), class_id)
	Support.equipment_of(s).equip_starting_weapons()
	slots.append(s)
	return s


func _eq(slot: PlayerSlot) -> Equipment:
	return Support.equipment_of(slot)


## A hand-built item: [param rarity], slot [param slot_type] and the Db enchants [param ids] at
## [param rank].
func _item(rarity: int, slot_type: Items.SlotType, ids: Array[StringName], rank: int = 0, wave: int = 15) -> ItemInstance:
	var item := Support.make_armor(40, ClassData.ArmorType.PLATE, 20, rarity, slot_type)
	item.wave = wave
	item.buy_price = ItemGenerator.price_for(rarity, wave)
	for id in ids:
		item.enchants.append(EnchantRoll.new(Db.get_enchant(id), rank))
	return item


func _epic_ring(ids: Array[StringName] = [&"blazing"], rank: int = 1) -> ItemInstance:
	var item := _item(Items.Rarity.EPIC, Items.SlotType.RING, ids, rank)
	item.display_name = "Blazing Jade Band"
	return item


## Gives the pile and the purse enough for [param actions] actions on an Epic item.
func _rich() -> void:
	RunState.add_gold(5000)
	RunState.add_dust(500, -1, "fixture")


# --- Rank V ------------------------------------------------------------------------------------

func test_ranks_reach_v() -> void:
	check_eq(EnchantData.RANK_MULT, [1.0, 1.5, 2.0, 2.5, 3.0] as Array[float], "x1 .. x3")
	check_eq(EnchantData.MAX_RANK, 4, "V is index 4")
	check_eq(EnchantData.MAX_GENERATED_RANK, 2, "the generator stops at III")
	var labels: Array[String] = []
	for r in 5:
		labels.append(EnchantData.rank_label(r))
	check_eq(labels, ["I", "II", "III", "IV", "V"] as Array[String], "labels I-V")
	check_eq(EnchantData.rank_label(9), "V", "clamped")
	check_eq(EnchantData.rank_label(-1), "I", "clamped below")
	var roll := EnchantRoll.new(Db.get_enchant(&"mighty"), 9)
	check_eq(roll.rank, 4, "a roll holds ranks up to V")
	check_eq(roll.rank_label(), "V", "its label")
	check_eq(roll.equip_stats()[Stats.ATTACK_POWER], 18.0, "Mighty 6 x 3 at rank V")
	roll.rank = 3
	check_eq(roll.equip_stats()[Stats.ATTACK_POWER], 15.0, "Mighty 6 x 2.5 at rank IV")
	check(EnchantRoll.new(Db.get_enchant(&"blazing"), 4).description().contains("%d" % (20 * 3)),
		"a proc's numbers follow rank V: %s" % EnchantRoll.new(Db.get_enchant(&"blazing"), 4).description())


func test_the_generator_never_rolls_above_rank_iii() -> void:
	check_eq(ItemGenerator.enchant_rank(30, true), 2, "looted late items stay at III")
	check_eq(ItemGenerator.enchant_rank(17, false), 2, "III at wave 17")
	var top := 0
	for wave in [1, 9, 17, 25]:
		for looted in [false, true]:
			for i in 40:
				var item := ItemGenerator.generate(ItemGenerator.Source.LOOT if looted else ItemGenerator.Source.SHOP,
						wave, rng, {&"rarity": Items.Rarity.LEGENDARY if looted else Items.Rarity.EPIC})
				for roll in item.enchants:
					top = maxi(top, roll.rank)
	check_eq(top, 2, "no generated enchant above III")
	# Hand-made items with a looted +1 rank are capped at III too.
	for id in Db.uniques:
		var data: UniqueItemData = Db.uniques[id]
		var item := ItemGenerator.from_unique(data, 25, true, rng)
		for roll in item.enchants:
			check(roll.rank <= 2, "%s: unique enchants stay at III" % data.id)


# --- Disenchant --------------------------------------------------------------------------------

func test_dust_by_rarity() -> void:
	var want: Array[int] = [1, 2, 4, 8, 16]
	for r in 5:
		var item := _item(r, Items.SlotType.RING, [])
		check_eq(Enchanter.dust_for(item), want[r], "%s gives %d" % [Items.RARITY_NAMES[r], want[r]])
		check(Enchanter.can_disenchant(item), "%s can be disenchanted" % Items.RARITY_NAMES[r])
	var artifact := _item(Items.Rarity.ARTIFACT, Items.SlotType.WEAPON, [])
	check_eq(Enchanter.dust_for(artifact), 0, "an Artifact gives nothing")
	check(not Enchanter.can_disenchant(artifact), "and cannot be disenchanted")
	check(Enchanter.disenchant_blocked_reason(artifact).contains("Artifact"), "the reason names it")
	check_eq(Enchanter.dust_for(null), 0, "no item")
	check(not Enchanter.can_disenchant(null), "no item, nothing to do")


func test_disenchant_turns_a_backpack_item_into_team_dust() -> void:
	var s := _slot()
	var eq := _eq(s)
	var item := _item(Items.Rarity.EPIC, Items.SlotType.HEAD, [&"mighty"])
	eq.add_to_backpack(item)
	var changed := Support.count_signal(eq.changed)
	var seen: Array[Vector2i] = []
	RunState.dust_changed.connect(func(dust: int, delta: int) -> void: seen.append(Vector2i(dust, delta)))
	check_eq(Enchanter.disenchant(eq, item, s.index), 8, "Epic = 8 Dust")
	check(not eq.backpack.has(item), "the item is gone")
	check_eq(RunState.arcane_dust, 8, "in the team pile")
	check_eq(RunState.dust_earned, 8, "counted as earned")
	check_eq(seen, [Vector2i(8, 8)] as Array[Vector2i], "dust_changed")
	check_eq(changed[0], 1, "the backpack changed")
	check_eq(RunState.dust_gain_log.size(), 1, "logged")
	check_eq(int(RunState.dust_gain_log[0]["slot"]), s.index, "for the slot")
	check_eq(RunState.gold, 0, "no gold for it")


func test_disenchant_refusals() -> void:
	var s := _slot()
	var eq := _eq(s)
	var artifact := _item(Items.Rarity.ARTIFACT, Items.SlotType.HEAD, [])
	eq.add_to_backpack(artifact)
	check_eq(Enchanter.disenchant(eq, artifact), 0, "an Artifact stays")
	check(eq.backpack.has(artifact), "still in the backpack")
	var worn := _item(Items.Rarity.RARE, Items.SlotType.HEAD, [])
	eq.slots[Items.EquipSlot.HEAD] = worn
	check_eq(Enchanter.disenchant(eq, worn), 0, "worn items are not disenchanted from here")
	check_eq(Enchanter.disenchant(eq, _item(Items.Rarity.RARE, Items.SlotType.HEAD, [])), 0, "not in the backpack")
	# The hero's last weapon: Equipment.remove_from_backpack refuses it while none is worn.
	eq.slots.clear()
	var blade := Support.make_weapon(&"sword", Items.Rarity.UNCOMMON)
	eq.add_to_backpack(blade)
	check(eq.is_last_weapon(blade), "the last usable weapon")
	check_eq(Enchanter.disenchant(eq, blade), 0, "refused like Sell")
	check_eq(RunState.arcane_dust, 0, "no Dust from a refused one")


func test_a_lost_item_becomes_dust_unless_it_is_an_artifact() -> void:
	check_eq(Enchanter.disenchant_lost_item(_item(Items.Rarity.RARE, Items.SlotType.RING, [])), 4, "Rare = 4")
	check_eq(RunState.arcane_dust, 4, "in the pile")
	check_eq(Enchanter.disenchant_lost_item(_item(Items.Rarity.ARTIFACT, Items.SlotType.RING, [])), 0, "Artifact: nothing")
	check_eq(RunState.arcane_dust, 4, "unchanged")


# --- Prices ------------------------------------------------------------------------------------

func test_the_epic_example_of_the_gdd() -> void:
	RunState.wave = 15
	var item := _epic_ring()
	check_eq(ItemGenerator.price_for(Items.Rarity.EPIC, 15), 191, "the shop price at wave 15")
	var gold: Array[int] = []
	var dust: Array[int] = []
	for use in 3:
		item.enchant_uses = use
		gold.append(Enchanter.gold_price(item))
		dust.append(Enchanter.dust_price(item))
	check_eq(gold, [48, 96, 191] as Array[int], "gold 48 / 96 / 191")
	check_eq(dust, [8, 16, 32] as Array[int], "Dust 8 / 16 / 32")
	item.enchant_uses = 0
	check_eq(Enchanter.price_text(item), "48 g + 8 Dust", "the text")


func test_prices_follow_rarity_and_the_current_wave() -> void:
	var common := _item(Items.Rarity.COMMON, Items.SlotType.RING, [])
	RunState.wave = 1
	check_eq(Enchanter.gold_price(common), 4, "15 g shop price: 25% = 3.75 -> 4")
	check_eq(Enchanter.dust_price(common), 1, "Common 1")
	var legendary := _item(Items.Rarity.LEGENDARY, Items.SlotType.RING, [])
	check_eq(Enchanter.dust_price(legendary), 16, "Legendary 16")
	RunState.wave = 25
	var epic := _epic_ring()
	check_eq(Enchanter.gold_price(epic), roundi(ItemGenerator.price_for(Items.Rarity.EPIC, 25) * 0.25), "the CURRENT wave, not the item's")
	check(Enchanter.gold_price(epic) > Enchanter.gold_price(epic, 5), "later waves cost more")
	check_eq(Enchanter.gold_price(null), 0, "no item")


func test_the_price_doubles_per_use_without_overflowing() -> void:
	var item := _epic_ring()
	item.enchant_uses = 10
	check_eq(Enchanter.multiplier(item), 1024, "2^10")
	check_eq(Enchanter.dust_price(item), 8 * 1024, "Dust too")
	item.enchant_uses = 500
	check_eq(Enchanter.multiplier(item), 1 << Enchanter.MAX_DOUBLINGS, "capped")
	check(Enchanter.gold_price(item) > 0 and Enchanter.dust_price(item) > 0, "still positive")


func test_afford_reasons() -> void:
	var item := _epic_ring()
	check_eq(Enchanter.afford_reason(item), Enchanter.REASON_POOR_BOTH, "nothing")
	RunState.add_gold(100)
	check_eq(Enchanter.afford_reason(item), Enchanter.REASON_POOR_DUST, "gold only")
	RunState.try_spend(100)
	RunState.add_dust(20, -1, "x")
	check_eq(Enchanter.afford_reason(item), Enchanter.REASON_POOR_GOLD, "Dust only")
	RunState.add_gold(48)
	check_eq(Enchanter.afford_reason(item), "", "exactly enough")
	RunState.try_spend(1)
	check_eq(Enchanter.afford_reason(item), Enchanter.REASON_POOR_GOLD, "one gold short")


# --- Rules -------------------------------------------------------------------------------------

func test_max_enchants_by_rarity() -> void:
	var got: Array[int] = []
	for r in 6:
		got.append(Enchanter.max_enchants(r))
	check_eq(got, [0, 1, 1, 2, 2, 0] as Array[int], "Common 0, Uncommon 1, Rare 1, Epic 2, Legendary 2, Artifact 0")


func test_blocked_reasons() -> void:
	var epic := _epic_ring()
	check_eq(Enchanter.blocked_reason(epic, Enchanter.Action.REROLL, 0), "", "reroll")
	check_eq(Enchanter.blocked_reason(epic, Enchanter.Action.EMPOWER, 0), "", "empower")
	check_eq(Enchanter.blocked_reason(epic, Enchanter.Action.IMBUE), "", "imbue: Epic with 1 of 2")
	check_eq(Enchanter.blocked_reason(epic, Enchanter.Action.REROLL, -1), Enchanter.REASON_PICK_ENCHANT, "no enchant picked")
	check_eq(Enchanter.blocked_reason(epic, Enchanter.Action.EMPOWER, 5), Enchanter.REASON_PICK_ENCHANT, "out of range")
	epic.enchants[0].rank = 4
	check_eq(Enchanter.blocked_reason(epic, Enchanter.Action.EMPOWER, 0), Enchanter.REASON_MAX_RANK, "Rank V is the top")
	check_eq(Enchanter.blocked_reason(epic, Enchanter.Action.REROLL, 0), "", "but a V can be rerolled")
	epic.enchants.append(EnchantRoll.new(Db.get_enchant(&"mighty"), 0))
	check_eq(Enchanter.blocked_reason(epic, Enchanter.Action.IMBUE), Enchanter.REASON_FULL, "Epic with 2 of 2")
	var rare := _item(Items.Rarity.RARE, Items.SlotType.RING, [&"blazing"])
	check_eq(Enchanter.blocked_reason(rare, Enchanter.Action.IMBUE), Enchanter.REASON_FULL, "Rare holds one")
	var common := _item(Items.Rarity.COMMON, Items.SlotType.RING, [])
	check_eq(Enchanter.blocked_reason(common, Enchanter.Action.IMBUE), Enchanter.REASON_COMMON, "Common cannot be imbued")
	check_eq(Enchanter.blocked_reason(common, Enchanter.Action.REROLL, 0), Enchanter.REASON_COMMON, "nothing to reroll")
	var uncommon := _item(Items.Rarity.UNCOMMON, Items.SlotType.RING, [])
	check_eq(Enchanter.blocked_reason(uncommon, Enchanter.Action.EMPOWER, 0), Enchanter.REASON_NO_ENCHANTS, "an empty Uncommon")
	check_eq(Enchanter.blocked_reason(uncommon, Enchanter.Action.IMBUE), "", "but it can be imbued")
	var artifact := _item(Items.Rarity.ARTIFACT, Items.SlotType.WEAPON, [&"blazing"])
	for action in [Enchanter.Action.REROLL, Enchanter.Action.EMPOWER, Enchanter.Action.IMBUE]:
		check_eq(Enchanter.blocked_reason(artifact, action, 0), Enchanter.REASON_ARTIFACT, "an Artifact is left alone")
	check_eq(Enchanter.blocked_reason(null, Enchanter.Action.IMBUE), Enchanter.REASON_NO_ITEM, "no item")
	check(Enchanter.is_enchantable(_epic_ring()) and Enchanter.is_enchantable(uncommon), "enchantable")
	check(not Enchanter.is_enchantable(common) and not Enchanter.is_enchantable(artifact), "not enchantable")
	check(not Enchanter.is_enchantable(null), "no item")


func test_the_pool_follows_the_fit_rules() -> void:
	var uncommon := _item(Items.Rarity.UNCOMMON, Items.SlotType.CHEST, [&"mighty"])
	for e in Enchanter.reroll_pool(uncommon, 0):
		check_eq(e.kind, EnchantData.Kind.EQUIP, "%s: an Uncommon only takes EQUIP enchants" % e.id)
		check(ItemGenerator.enchant_fits(e, uncommon), "%s fits" % e.id)
		check(e.id != &"mighty", "never what it already has")
	var epic := _item(Items.Rarity.EPIC, Items.SlotType.HEAD, [&"mighty", &"retribution"])
	var ids: Array[StringName] = []
	for e in Enchanter.reroll_pool(epic, 0):
		ids.append(e.id)
	check(&"mighty" not in ids and &"retribution" not in ids, "neither carried enchant is offered")
	check(&"frozen_ward" in ids, "a WHEN_STRUCK enchant fits a helm")
	check(&"blazing" not in ids, "a weapon / jewellery proc does not")
	# Projectile-only enchants need a projectile weapon.
	var sword := Support.make_weapon(&"sword", Items.Rarity.RARE)
	var bow := Support.make_weapon(&"bow", Items.Rarity.RARE)
	var sword_ids: Array[StringName] = []
	for e in Enchanter.imbue_pool(sword):
		sword_ids.append(e.id)
	var bow_ids: Array[StringName] = []
	for e in Enchanter.imbue_pool(bow):
		bow_ids.append(e.id)
	check(&"piercing" not in sword_ids and &"piercing" in bow_ids, "Piercing is for projectile weapons only")


# --- Doing it ----------------------------------------------------------------------------------

func test_reroll_replaces_one_enchant_at_the_same_rank() -> void:
	_rich()
	var s := _slot()
	var eq := _eq(s)
	var item := _epic_ring([&"blazing", &"mighty"], 3)
	eq.add_to_backpack(item)
	var out := Enchanter.perform(eq, s.index, item, Enchanter.Action.REROLL, 0, rng)
	check(out.ok, "done: %s" % out.reason)
	check_eq(item.enchants.size(), 2, "still two")
	check(item.enchants[0].enchant.id != &"blazing", "a new enchant")
	check(item.enchants[0].enchant.id != &"mighty", "not one the item already has")
	check(ItemGenerator.enchant_fits(item.enchants[0].enchant, item), "that fits the slot")
	check_eq(item.enchants[0].rank, 3, "the same rank (IV)")
	check_eq(item.enchants[1].enchant.id, &"mighty", "the other enchant is untouched")
	check_eq(out.before.enchant.id, &"blazing", "the outcome remembers what it was")
	check_eq(out.after.enchant.id, item.enchants[0].enchant.id, "and what it became")
	check_eq(item.enchant_uses, 1, "one use counted")


func test_reroll_is_one_deterministic_draw() -> void:
	_rich()
	var s := _slot()
	var eq := _eq(s)
	var a := _epic_ring([&"blazing"], 1)
	var b := _epic_ring([&"blazing"], 1)
	eq.add_to_backpack(a)
	eq.add_to_backpack(b)
	var r1 := RandomNumberGenerator.new()
	r1.seed = 99
	var r2 := RandomNumberGenerator.new()
	r2.seed = 99
	Enchanter.perform(eq, s.index, a, Enchanter.Action.REROLL, 0, r1)
	Enchanter.perform(eq, s.index, b, Enchanter.Action.REROLL, 0, r2)
	check_eq(a.enchants[0].enchant.id, b.enchants[0].enchant.id, "same seed, same enchant")
	var fresh := RandomNumberGenerator.new()
	fresh.seed = 99
	fresh.randf()
	check_eq(r1.randi(), fresh.randi(), "exactly one random number was drawn")


func test_reroll_defaults_to_the_run_rng() -> void:
	_rich()
	var s := _slot()
	var eq := _eq(s)
	var item := _epic_ring()
	eq.add_to_backpack(item)
	RunState.rng.seed = 5
	var probe := RandomNumberGenerator.new()
	probe.seed = 5
	probe.randf()
	Enchanter.perform(eq, s.index, item, Enchanter.Action.REROLL, 0)
	check_eq(RunState.rng.randi(), probe.randi(), "RunState.rng advanced by one draw")


func test_reroll_favours_the_class_power_enchant() -> void:
	# A Mage (magic weapon) rolls Spell Power far more often than Attack Power.
	var s := _slot(&"mage")
	var eq := _eq(s)
	var attack := 0
	var spell := 0
	RunState.add_gold(10_000_000)
	RunState.add_dust(10_000_000, -1, "fixture")
	for i in 300:
		var item := _item(Items.Rarity.UNCOMMON, Items.SlotType.CHEST, [&"brutal"])
		eq.backpack.append(item)
		var out := Enchanter.perform(eq, s.index, item, Enchanter.Action.REROLL, 0, rng)
		eq.backpack.erase(item)
		if out.ok and out.after.enchant.id == &"mighty":
			attack += 1
		elif out.ok and out.after.enchant.id == &"arcane_touched":
			spell += 1
	check(spell > attack * 3, "Arcane-touched %d vs Mighty %d for a Mage" % [spell, attack])


func test_empower_adds_a_rank_up_to_v() -> void:
	_rich()
	var s := _slot()
	var eq := _eq(s)
	var item := _epic_ring([&"mighty"], 2)
	eq.add_to_backpack(item)
	var seen: Array[int] = []
	for i in 3:
		var out := Enchanter.perform(eq, s.index, item, Enchanter.Action.EMPOWER, 0)
		check(out.ok == (i < 2), "empower %d: %s" % [i, out.reason])
		seen.append(item.enchants[0].rank)
	check_eq(seen, [3, 4, 4] as Array[int], "III -> IV -> V, then it stops")
	check_eq(item.enchant_uses, 2, "the refused one is not a use")
	check_eq(item.enchants[0].enchant.id, &"mighty", "the enchant itself is the same")
	check_eq(item.equip_stats()[Stats.ATTACK_POWER], 18.0, "x3 at rank V")


func test_empower_draws_no_random_numbers() -> void:
	_rich()
	var s := _slot()
	var eq := _eq(s)
	var item := _epic_ring()
	eq.add_to_backpack(item)
	RunState.rng.seed = 11
	var probe := RandomNumberGenerator.new()
	probe.seed = 11
	Enchanter.perform(eq, s.index, item, Enchanter.Action.EMPOWER, 0)
	check_eq(RunState.rng.randi(), probe.randi(), "no draw")


func test_imbue_fills_a_free_slot_at_the_generator_rank() -> void:
	_rich()
	var s := _slot()
	var eq := _eq(s)
	var uncommon := _item(Items.Rarity.UNCOMMON, Items.SlotType.RING, [], 0, 17)
	eq.add_to_backpack(uncommon)
	var out := Enchanter.perform(eq, s.index, uncommon, Enchanter.Action.IMBUE, -1, rng)
	check(out.ok, "imbued: %s" % out.reason)
	check_eq(uncommon.enchants.size(), 1, "one enchant")
	check_eq(out.index, 0, "at index 0")
	check_eq(uncommon.enchants[0].enchant.kind, EnchantData.Kind.EQUIP, "an Uncommon takes an EQUIP enchant")
	check_eq(uncommon.enchants[0].rank, 2, "rank III: the rank of a wave-17 item")
	check_eq(Enchanter.blocked_reason(uncommon, Enchanter.Action.IMBUE), Enchanter.REASON_FULL, "now full")
	var again := Enchanter.perform(eq, s.index, uncommon, Enchanter.Action.IMBUE, -1, rng)
	check(not again.ok and again.reason == Enchanter.REASON_FULL, "a second imbue is refused")
	var epic := _item(Items.Rarity.EPIC, Items.SlotType.RING, [&"blazing"], 0, 3)
	eq.add_to_backpack(epic)
	check(Enchanter.perform(eq, s.index, epic, Enchanter.Action.IMBUE, -1, rng).ok, "an Epic with one gets a second")
	check_eq(epic.enchants.size(), 2, "two")
	check_eq(epic.enchants[1].rank, 0, "wave 3: rank I")
	check(epic.enchants[1].enchant.id != &"blazing", "a different one")


func test_perform_pays_gold_and_dust_and_logs_them() -> void:
	var s := _slot()
	var eq := _eq(s)
	RunState.add_gold(300)
	RunState.add_dust(20, -1, "x")
	RunState.begin_spend_round()
	var item := _epic_ring([&"blazing"], 1)
	eq.add_to_backpack(item)
	var spent_signals: Array[Dictionary] = []
	RunState.spent.connect(func(entry: Dictionary) -> void: spent_signals.append(entry))
	var changed := Support.count_signal(eq.changed)
	var out := Enchanter.perform(eq, s.index, item, Enchanter.Action.EMPOWER, 0)
	check(out.ok, "done")
	check_eq(out.gold, 48, "48 gold")
	check_eq(out.dust, 8, "8 Dust")
	check_eq(RunState.gold, 300 - 48, "gold paid")
	check_eq(RunState.arcane_dust, 20 - 8, "Dust paid")
	check_eq(RunState.gold_spent, 48, "counted as spent gold")
	check_eq(RunState.dust_spent, 8, "counted as spent Dust")
	check_eq(RunState.enchants_done, 1, "enchants_done")
	check_eq(RunState.spend_log.size(), 1, "one gold entry")
	check_eq(RunState.spend_log[0]["kind"], &"enchant", "kind enchant")
	check_eq(RunState.spend_log[0]["slot"], s.index, "for the slot")
	check_eq(RunState.spend_log[0]["amount"], 48, "the gold amount")
	check_eq(String(RunState.spend_log[0]["label"]), "Empower Blazing (8 Dust)", "the ticker label names the Dust too")
	check_eq(RunState.dust_spend_log.size(), 1, "one Dust entry")
	check_eq(RunState.dust_spend_log[0]["kind"], &"enchant", "kind enchant")
	check_eq(RunState.dust_spend_log[0]["amount"], 8, "the Dust amount")
	check_eq(spent_signals.size(), 1, "RunState.spent fired for the purse board")
	check_eq(changed[0], 1, "Equipment.changed fired once")
	check_eq(item.enchant_uses, 1, "the next action costs double")
	check_eq(Enchanter.gold_price(item), 96, "gold doubled")
	check_eq(Enchanter.dust_price(item), 16, "Dust doubled")


func test_a_refused_action_changes_and_spends_nothing() -> void:
	var s := _slot()
	var eq := _eq(s)
	var item := _epic_ring([&"blazing"], 1)
	eq.add_to_backpack(item)
	var changed := Support.count_signal(eq.changed)
	RunState.rng.seed = 3
	var probe := RandomNumberGenerator.new()
	probe.seed = 3
	# Poor in both.
	var out := Enchanter.perform(eq, s.index, item, Enchanter.Action.REROLL, 0)
	check(not out.ok and out.reason == Enchanter.REASON_POOR_BOTH, "poor: %s" % out.reason)
	# Gold but no Dust, and Dust but no gold: neither is spent.
	RunState.add_gold(500)
	out = Enchanter.perform(eq, s.index, item, Enchanter.Action.EMPOWER, 0)
	check(not out.ok and out.reason == Enchanter.REASON_POOR_DUST, "no Dust: %s" % out.reason)
	check_eq(RunState.gold, 500, "the gold stays when the Dust is short")
	RunState.try_spend(500)
	RunState.add_dust(50, -1, "x")
	out = Enchanter.perform(eq, s.index, item, Enchanter.Action.EMPOWER, 0)
	check(not out.ok and out.reason == Enchanter.REASON_POOR_GOLD, "no gold: %s" % out.reason)
	check_eq(RunState.arcane_dust, 50, "the Dust stays when the gold is short")
	_rich()
	# Not this hero's item, a blocked action.
	var foreign := _epic_ring()
	out = Enchanter.perform(eq, s.index, foreign, Enchanter.Action.EMPOWER, 0)
	check(not out.ok and out.reason == Enchanter.REASON_NOT_YOURS, "not yours: %s" % out.reason)
	item.enchants[0].rank = 4
	out = Enchanter.perform(eq, s.index, item, Enchanter.Action.EMPOWER, 0)
	check(not out.ok and out.reason == Enchanter.REASON_MAX_RANK, "rank V: %s" % out.reason)
	out = Enchanter.perform(eq, s.index, null, Enchanter.Action.EMPOWER, 0)
	check(not out.ok and out.reason == Enchanter.REASON_NO_ITEM, "no item")
	check_eq(item.enchant_uses, 0, "no use counted")
	check_eq(RunState.enchants_done, 0, "nothing done")
	check_eq(RunState.spend_log.size(), 0, "nothing logged")
	check_eq(RunState.dust_spend_log.size(), 0, "nothing logged")
	check_eq(changed[0], 0, "Equipment.changed stayed quiet")
	check_eq(RunState.rng.randi(), probe.randi(), "and no random number was drawn")


func test_the_hold_rule_input_is_the_gold_part() -> void:
	# The tab asks Trainer-style: price > purse x HOLD_SHARE. Enchanter exposes the gold price.
	var item := _epic_ring()
	RunState.add_gold(80)
	check(Enchanter.gold_price(item) > RunState.gold * ShopPanel.HOLD_SHARE, "48 of 80 is more than half")
	RunState.add_gold(100)
	check(not (Enchanter.gold_price(item) > RunState.gold * ShopPanel.HOLD_SHARE), "48 of 180 is not")


func test_an_enchanted_item_keeps_its_name_in_step_with_the_first_prefix() -> void:
	_rich()
	var s := _slot()
	var eq := _eq(s)
	var item := _epic_ring([&"blazing", &"mighty"], 1)
	eq.add_to_backpack(item)
	item.display_name = "Blazing Jade Band of the Bear"
	var out := Enchanter.perform(eq, s.index, item, Enchanter.Action.REROLL, 0, rng)
	check(out.ok, "rerolled")
	var prefix := item.enchants[0].enchant.prefix
	check(item.display_name.begins_with(prefix + " "), "the name starts with the new prefix: %s" % item.display_name)
	check(not item.display_name.contains("Blazing") or prefix == "Blazing", "the old prefix is gone")
	check(item.display_name.ends_with("Jade Band of the Bear"), "the rest stays: %s" % item.display_name)
	# A second-enchant reroll leaves the name alone.
	var before := item.display_name
	Enchanter.perform(eq, s.index, item, Enchanter.Action.REROLL, 1, rng)
	check_eq(item.display_name, before, "the first prefix did not change")
	# An item without a prefix gets one from Imbue.
	var plain := _item(Items.Rarity.UNCOMMON, Items.SlotType.RING, [])
	plain.display_name = "Jade Band"
	eq.add_to_backpack(plain)
	Enchanter.perform(eq, s.index, plain, Enchanter.Action.IMBUE, -1, rng)
	check_eq(plain.display_name, "%s Jade Band" % plain.enchants[0].enchant.prefix, "Imbue names the item")
	# Hand-made items and forged Legendaries keep their names.
	var unique := _epic_ring([&"blazing"], 0)
	unique.unique = true
	unique.display_name = "Jade Band of Legend"
	eq.add_to_backpack(unique)
	Enchanter.perform(eq, s.index, unique, Enchanter.Action.REROLL, 0, rng)
	check_eq(unique.display_name, "Jade Band of Legend", "a hand-made name stays")
	var forged := _epic_ring([&"blazing"], 0)
	forged.unique_effect = &"some_effect"
	forged.display_name = "Dagger of Fate"
	eq.add_to_backpack(forged)
	Enchanter.perform(eq, s.index, forged, Enchanter.Action.REROLL, 0, rng)
	check_eq(forged.display_name, "Dagger of Fate", "a Legendary effect keeps its name")


func test_equipped_items_rebuild_the_heroes_stats_and_procs() -> void:
	var world := Fakes.make_world(tree)
	var p := Fakes.spawn_player(world, 0, &"warrior")
	var ring := _item(Items.Rarity.EPIC, Items.SlotType.RING, [&"mighty"], 0)
	p.equipment.slots[Items.EquipSlot.RING_1] = ring
	p.equipment.changed.emit()
	var base := p.stats.get_raw(Stats.ATTACK_POWER)
	_rich()
	var out := Enchanter.perform(p.equipment, p.slot.index, ring, Enchanter.Action.EMPOWER, 0)
	check(out.ok, "empowered a worn ring")
	check_near(p.stats.get_raw(Stats.ATTACK_POWER) - base, 3.0, 0.001, "Attack Power +6 x 0.5 more at once")
	# A proc enchant: rerolling it swaps the hero's proc.
	var blade := Support.make_weapon(&"sword", Items.Rarity.EPIC)
	blade.enchants.append(EnchantRoll.new(Db.get_enchant(&"blazing"), 0))
	p.equipment.slots[Items.EquipSlot.MAIN_HAND] = blade
	p.equipment.changed.emit()
	check(_proc_enchant_ids(p).has(&"blazing"), "the Blazing proc is live: %s" % [_proc_enchant_ids(p)])
	var got := Enchanter.perform(p.equipment, p.slot.index, blade, Enchanter.Action.REROLL, 0, rng)
	check(got.ok, "rerolled the worn sword's enchant")
	check(not _proc_enchant_ids(p).has(&"blazing"), "the old proc is gone: %s" % [_proc_enchant_ids(p)])
	check(_proc_enchant_ids(p).has(blade.enchants[0].enchant.id) or not blade.enchants[0].enchant.is_proc(),
		"the new proc runs instead: %s" % [_proc_enchant_ids(p)])
	Fakes.free_world(world)


## Ids of the procs the hero's ProcSystem runs (rebuilt from the equipment on Equipment.changed).
func _proc_enchant_ids(p: Player) -> Array[StringName]:
	var out: Array[StringName] = []
	for proc in p.procs.procs:
		out.append(proc.id)
	return out


# --- Bots --------------------------------------------------------------------------------------

func test_best_weapon_is_the_best_equipped_attacker() -> void:
	var s := _slot(&"rogue")
	var eq := _eq(s)
	var main := eq.get_item(Items.EquipSlot.MAIN_HAND)
	check_eq(Enchanter.best_weapon(eq), main, "the starting main hand")
	var better := Support.make_weapon(&"dagger", Items.Rarity.RARE)
	better.item_level = 90
	eq.slots[Items.EquipSlot.OFF_HAND] = better
	check_eq(Enchanter.best_weapon(eq), better, "the rarer weapon")
	eq.slots.clear()
	check_eq(Enchanter.best_weapon(eq), null, "unarmed")
	check_eq(Enchanter.best_weapon(null), null, "no equipment")


func test_bot_plan_order() -> void:
	var mage := Db.get_class_data(&"mage")
	var warrior := Db.get_class_data(&"warrior")
	var wrong := _item(Items.Rarity.EPIC, Items.SlotType.RING, [&"mighty"], 1)
	var plan := Enchanter.bot_plan(wrong, mage)
	check_eq(plan["action"], Enchanter.Action.REROLL, "Attack Power on a Mage is rerolled first")
	check_eq(plan["index"], 0, "that enchant")
	plan = Enchanter.bot_plan(wrong, warrior)
	check_eq(plan["action"], Enchanter.Action.IMBUE, "right class, a free slot: Imbue")
	var full := _item(Items.Rarity.EPIC, Items.SlotType.RING, [&"mighty", &"brutal"], 1)
	full.enchants[1].rank = 0
	plan = Enchanter.bot_plan(full, warrior)
	check_eq(plan["action"], Enchanter.Action.EMPOWER, "full: Empower")
	check_eq(plan["index"], 1, "the lowest rank")
	for e in full.enchants:
		e.rank = 4
	check(Enchanter.bot_plan(full, warrior).is_empty(), "everything V and full: nothing to do")
	check(Enchanter.bot_plan(_item(Items.Rarity.COMMON, Items.SlotType.RING, []), warrior).is_empty(), "a Common has nothing")
	check(Enchanter.bot_plan(null, warrior).is_empty(), "no item")


func test_bot_enchant_spends_within_its_budget_and_disenchants_spares() -> void:
	var s := _slot(&"warrior")
	var eq := _eq(s)
	var weapon := Support.make_weapon(&"sword", Items.Rarity.EPIC)
	weapon.wave = 15
	weapon.buy_price = ItemGenerator.price_for(Items.Rarity.EPIC, 15)
	weapon.enchants.append(EnchantRoll.new(Db.get_enchant(&"brutal"), 1))
	eq.slots[Items.EquipSlot.MAIN_HAND] = weapon
	# Spare backpack items (not upgrades): Epic 8 + Rare 4 Dust.
	var spare_a := Support.make_armor(1, ClassData.ArmorType.CLOTH, 20, Items.Rarity.EPIC, Items.SlotType.HEAD)
	var spare_b := Support.make_armor(1, ClassData.ArmorType.CLOTH, 20, Items.Rarity.RARE, Items.SlotType.CHEST)
	eq.slots[Items.EquipSlot.HEAD] = Support.make_armor(500, ClassData.ArmorType.PLATE, 20, Items.Rarity.EPIC, Items.SlotType.HEAD)
	eq.slots[Items.EquipSlot.CHEST] = Support.make_armor(500, ClassData.ArmorType.PLATE, 20, Items.Rarity.EPIC, Items.SlotType.CHEST)
	eq.add_to_backpack(spare_a)
	eq.add_to_backpack(spare_b)
	RunState.add_gold(1000)
	check(Enchanter.is_spare(spare_a, s, eq) and Enchanter.is_spare(spare_b, s, eq), "both are spares")
	# A budget below the first price: nothing happens, nothing is thrown away.
	check_eq(Enchanter.bot_enchant(s, 10, rng), 0, "10 gold buys nothing at 48")
	check(eq.backpack.has(spare_a) and eq.backpack.has(spare_b), "the spares stay")
	check_eq(RunState.arcane_dust, 0, "no Dust made for nothing")
	var done := Enchanter.bot_enchant(s, 400, rng)
	check(done >= 1 and done <= Enchanter.BOT_MAX_ACTIONS, "acted: %d" % done)
	check_eq(RunState.enchants_done, done, "counted")
	check(not eq.backpack.has(spare_b) or not eq.backpack.has(spare_a), "spares were disenchanted for the Dust")
	check(RunState.dust_spent >= 8, "Dust was spent: %d" % RunState.dust_spent)
	check_eq(weapon.enchant_uses, done, "on the best weapon")
	check(RunState.gold_spent <= 400, "inside the budget: %d" % RunState.gold_spent)


func test_bots_keep_upgrades_and_the_last_weapon() -> void:
	var s := _slot(&"warrior")
	var eq := _eq(s)
	# An upgrade in the backpack is not spare.
	var upgrade := Support.make_armor(900, ClassData.ArmorType.PLATE, 20, Items.Rarity.EPIC, Items.SlotType.HEAD)
	upgrade.stats = {Stats.STRENGTH: 99.0, Stats.STAMINA: 99.0}
	eq.add_to_backpack(upgrade)
	check(not Enchanter.is_spare(upgrade, s, eq), "an upgrade is kept")
	check_eq(Enchanter.bot_disenchant_spare(s, eq, 100), 0, "nothing thrown away")
	check(eq.backpack.has(upgrade), "still there")
	# The last weapon is kept.
	eq.slots.clear()
	var blade := Support.make_weapon(&"sword", Items.Rarity.COMMON)
	eq.add_to_backpack(blade)
	check(not Enchanter.is_spare(blade, s, eq), "the last weapon is not spare")


func test_bot_enchant_without_a_weapon_or_hero_does_nothing() -> void:
	var s := _slot()
	_eq(s).slots.clear()
	check_eq(Enchanter.bot_enchant(s, 1000, rng), 0, "unarmed")
	check_eq(Enchanter.bot_enchant(null, 1000, rng), 0, "no slot")
