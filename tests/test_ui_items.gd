extends TestCase
## ItemTooltip (WoW layout, colours, comparison block), its static helpers (stat_delta,
## upgrade_direction, equipped_for_compare) and ItemIcon / ItemArt state. Test items are built
## in memory (ItemInstance.from_weapon + hand-set stats / enchants).

var tip: ItemTooltip


func before_each() -> void:
	RunState.start_run(1, 3)
	tip = ItemTooltip.create()
	tree.root.add_child(tip)


func after_each() -> void:
	if is_instance_valid(tip):
		tip.get_parent().remove_child(tip)
		tip.free()


# --- Builders ---------------------------------------------------------------------------------

static func armor(name: String, slot_type: Items.SlotType, armor_type: int, rarity: int, stats: Dictionary,
		wave: int = 5, looted: bool = false) -> ItemInstance:
	var it := ItemInstance.new()
	it.display_name = name
	it.slot_type = slot_type
	it.armor_type = armor_type
	it.rarity = rarity
	it.wave = wave
	it.looted = looted
	it.item_level = Items.item_level(wave, rarity, looted)
	for k in stats:
		it.stats[StringName(k)] = float(stats[k])
	it.buy_price = 40
	return it


static func equip_enchant(stat: StringName, value: float, text: String = "") -> EnchantData:
	var e := EnchantData.new()
	e.id = &"test_equip"
	e.kind = EnchantData.Kind.EQUIP
	e.equip_stats[stat] = value
	e.description = text
	return e


static func proc_enchant(text: String, damage: float) -> EnchantData:
	var e := EnchantData.new()
	e.id = &"test_proc"
	e.kind = EnchantData.Kind.ON_HIT
	e.params = {"damage": damage}
	e.description = text
	return e


func _color(l: Label) -> Color:
	return l.get_theme_color(&"font_color")


# --- Tooltip content --------------------------------------------------------------------------

func test_weapon_tooltip_lines() -> void:
	var sword := ItemInstance.from_weapon(Db.get_weapon(&"sword"), Items.Rarity.RARE, 5)
	tip.show_item(sword, Db.get_class_data(&"warrior"))
	check(tip.visible, "shown")
	var title := tip.find_line(sword.display_name)
	check(title != null, "name line")
	check(title != null and _color(title).is_equal_approx(UiTheme.RARITY_COLORS[2]), "name in rare blue")
	var ilvl := tip.find_line("Item Level %d" % sword.item_level)
	check(ilvl != null and _color(ilvl).is_equal_approx(ItemTooltip.YELLOW), "item level line in yellow")
	check(tip.find_line("Looted") == null, "not looted")
	check(tip.find_line("One-Hand", true) != null, "hand")
	var type := tip.find_line("Sword", true)
	check(type != null and _color(type).is_equal_approx(ItemTooltip.WHITE), "weapon type white for a warrior")
	check(tip.find_line("10.2 Damage") != null, "damage x1.7 rarity: %s" % tip.line_texts())
	check(tip.find_line("Speed 0.90") != null, "speed")
	check(tip.find_line("(11.3 damage per second)") != null, "dps")
	check(tip.find_line("Scales with Strength 100%") != null, "scaling")
	check(tip.find_line("Sell Price:") != null, "sell price caption")
	check(str(sword.sell_value()) in tip.line_texts(), "sell value shown")


func test_armor_stats_enchants_and_looted() -> void:
	var helm := armor("Runed Plate Helm of the Bear", Items.SlotType.HEAD, ClassData.ArmorType.PLATE,
		Items.Rarity.EPIC, {"strength": 8, "stamina": 9}, 14, true)
	helm.enchants.append(EnchantRoll.new(proc_enchant("Chance on hit: Hurls a fiery ball that causes {damage} Fire damage.", 20.0), 1))
	helm.enchants.append(EnchantRoll.new(equip_enchant(Stats.ATTACK_POWER, 6.0), 0))
	tip.show_item(helm, Db.get_class_data(&"warrior"))
	var title := tip.find_line("Runed Plate Helm of the Bear")
	check(title != null and _color(title).is_equal_approx(UiTheme.RARITY_COLORS[3]), "epic purple name")
	var looted := tip.find_line("Looted")
	check(looted != null and _color(looted).is_equal_approx(ItemTooltip.ENCHANT_GREEN), "Looted line")
	check(tip.find_line("Head", true) != null, "slot")
	check(tip.find_line("Plate", true) != null, "armor type")
	var strength := tip.find_line("+8 Strength")
	check(strength != null and _color(strength).is_equal_approx(ItemTooltip.WHITE), "white stat line")
	check(tip.find_line("+9 Stamina") != null, "stamina line")
	var lines := tip.line_texts()
	check(lines.find("+8 Strength") < lines.find("+9 Stamina"), "primary stats before Stamina (WoW order)")
	var proc := tip.find_line("causes 30 Fire damage")
	check(proc != null and _color(proc).is_equal_approx(ItemTooltip.ENCHANT_GREEN), "green enchant line, rank II x1.5")
	var ap := tip.find_line("Equip: +6 Attack Power")
	check(ap != null and _color(ap).is_equal_approx(ItemTooltip.ENCHANT_GREEN), "enchant without text falls back to its stats")


func test_unusable_type_is_red() -> void:
	var legs := armor("Steel Plate Legguards", Items.SlotType.LEGS, ClassData.ArmorType.PLATE, 1, {"strength": 3})
	tip.show_item(legs, Db.get_class_data(&"mage"))
	var type := tip.find_line("Plate", true)
	check(type != null and _color(type).is_equal_approx(ItemTooltip.UNUSABLE_RED), "plate red for a mage")
	tip.show_item(legs, Db.get_class_data(&"paladin"))
	type = tip.find_line("Plate", true)
	check(type != null and _color(type).is_equal_approx(ItemTooltip.WHITE), "plate white for a paladin")
	var wand := ItemInstance.from_weapon(Db.get_weapon(&"wand"))
	wand.display_name = "Wand of Sparks"
	tip.show_item(wand, Db.get_class_data(&"warrior"))
	type = tip.find_line("Wand", true)
	check(type != null and _color(type).is_equal_approx(ItemTooltip.UNUSABLE_RED), "wand red for a warrior")


func test_classes_unique_flavor_and_prices() -> void:
	var trinket := armor("Heart of the Onion King", Items.SlotType.TRINKET, Items.NO_ARMOR, Items.Rarity.LEGENDARY, {"strength": 6})
	trinket.class_restriction = &"warrior"
	trinket.unique_text = "Equip: Your critical strikes summon a ring of fire."
	trinket.flavor = "It still beats."
	tip.show_item(trinket, Db.get_class_data(&"mage"), null, 120)
	var classes := tip.find_line("Classes: Warrior")
	check(classes != null and _color(classes).is_equal_approx(ItemTooltip.UNUSABLE_RED), "Classes red for a mage")
	var unique := tip.find_line("ring of fire")
	check(unique != null and _color(unique).is_equal_approx(ItemTooltip.ENCHANT_GREEN), "unique effect line green")
	var flavor := tip.find_line("\"It still beats.\"")
	check(flavor != null and _color(flavor).is_equal_approx(ItemTooltip.YELLOW), "flavor in gold quotes")
	check(tip.find_line("Trinket", true) != null, "slot name")
	check(tip.find_line("Price:", true) != null, "buy price row")
	var price := tip.find_line("120")
	check(price != null and _color(price).is_equal_approx(ItemTooltip.UNUSABLE_RED), "unaffordable price in red (wallet 0)")
	RunState.add_gold(500)
	tip.show_item(trinket, Db.get_class_data(&"warrior"), null, 120)
	classes = tip.find_line("Classes: Warrior")
	check(classes != null and _color(classes).is_equal_approx(ItemTooltip.WHITE), "Classes white for the warrior")
	price = tip.find_line("120")
	check(price != null and _color(price).is_equal_approx(ItemTooltip.YELLOW), "affordable price in gold")
	tip.show_item(trinket, null)
	check(tip.find_line("Price:", true) == null, "no buy price without one")
	check(tip.find_line("Sell Price:") != null, "sell price always")


func test_comparison_block() -> void:
	var new_helm := armor("New Helm", Items.SlotType.HEAD, ClassData.ArmorType.PLATE, 2, {"strength": 6, "armor": 3})
	var old_helm := armor("Old Helm", Items.SlotType.HEAD, ClassData.ArmorType.PLATE, 0, {"strength": 3, "stamina": 2, "armor": 3})
	tip.show_item(new_helm, Db.get_class_data(&"warrior"), old_helm)
	check(tip.find_line("If you replace this item:") != null, "comparison header")
	check(tip.find_line("Equipped: Old Helm") != null, "names the equipped item")
	var plus := tip.find_line("+3 Strength")
	check(plus != null and _color(plus).is_equal_approx(ItemTooltip.DELTA_GREEN), "+3 Strength green")
	var minus := tip.find_line("-2 Stamina")
	check(minus != null and _color(minus).is_equal_approx(ItemTooltip.DELTA_RED), "-2 Stamina red")
	check(tip.find_line("Armor") != null, "armor line present (item stat)")
	check(not ("+0 Armor" in tip.line_texts()), "unchanged stats are not listed")
	tip.set_comparison_visible(false)
	check(tip.find_line("If you replace this item:") == null, "comparison can be hidden")
	tip.set_comparison_visible(true)
	check(tip.find_line("If you replace this item:") != null, "and shown again")
	tip.show_item(new_helm, null, new_helm)
	check(tip.find_line("If you replace this item:") == null, "no comparison with itself")


func test_weapon_comparison_shows_dps() -> void:
	var rare := ItemInstance.from_weapon(Db.get_weapon(&"sword"), Items.Rarity.RARE)
	var common := ItemInstance.from_weapon(Db.get_weapon(&"sword"))
	tip.show_item(rare, Db.get_class_data(&"warrior"), common)
	var dps := tip.find_line("Damage per second")
	check(dps != null and dps.text.begins_with("+4.7"), "dps delta (10.2 - 6) / 0.9: %s" % (dps.text if dps else ""))
	check(dps != null and _color(dps).is_equal_approx(ItemTooltip.DELTA_GREEN), "dps gain green")


# --- Static helpers -----------------------------------------------------------------------------

func test_stat_delta() -> void:
	var a := armor("A", Items.SlotType.RING, Items.NO_ARMOR, 1, {"crit": 4, "haste": 2})
	a.enchants.append(EnchantRoll.new(equip_enchant(Stats.ATTACK_POWER, 6.0), 1))
	var b := armor("B", Items.SlotType.RING, Items.NO_ARMOR, 1, {"crit": 1, "versatility": 3})
	var d := ItemTooltip.stat_delta(a, b)
	check_eq(d.get(Stats.CRIT, 0.0), 3.0, "crit")
	check_eq(d.get(Stats.HASTE, 0.0), 2.0, "haste")
	check_eq(d.get(Stats.VERSATILITY, 0.0), -3.0, "lost versatility")
	check_eq(d.get(Stats.ATTACK_POWER, 0.0), 9.0, "equip enchant at rank II counts")
	check_eq(ItemTooltip.stat_delta(a, a).size(), 0, "no delta with itself")
	check_eq(ItemTooltip.stat_delta(b, null).size(), 2, "vs empty slot = its own stats")
	var tome := ItemInstance.from_weapon(Db.get_weapon(&"tome"))
	var td := ItemTooltip.stat_delta(tome, null)
	check_eq(td.get(Stats.INTELLECT, 0.0), 2.0, "weapon bonus stats count")


func test_upgrade_direction() -> void:
	var warrior := Db.get_class_data(&"warrior")
	var mage := Db.get_class_data(&"mage")
	var str_helm := armor("Str", Items.SlotType.HEAD, ClassData.ArmorType.CLOTH, 1, {"strength": 5})
	var int_helm := armor("Int", Items.SlotType.HEAD, ClassData.ArmorType.CLOTH, 1, {"intellect": 5})
	check_eq(ItemTooltip.upgrade_direction(str_helm, int_helm, warrior), 1, "primary stat wins for a warrior")
	check_eq(ItemTooltip.upgrade_direction(str_helm, int_helm, mage), -1, "and loses for a mage")
	check_eq(ItemTooltip.upgrade_direction(str_helm, str_helm, warrior), 0, "same item: unclear")
	check_eq(ItemTooltip.upgrade_direction(str_helm, null, warrior), 1, "filling an empty slot")
	var plate := armor("Plate", Items.SlotType.HEAD, ClassData.ArmorType.PLATE, 3, {"intellect": 20})
	check_eq(ItemTooltip.upgrade_direction(plate, null, mage), -1, "unusable is never an upgrade")
	var mixed := armor("Mixed", Items.SlotType.HEAD, ClassData.ArmorType.CLOTH, 1, {"strength": 2, "stamina": 1})
	var stam := armor("Stam", Items.SlotType.HEAD, ClassData.ArmorType.CLOTH, 1, {"stamina": 6})
	check_eq(ItemTooltip.upgrade_direction(mixed, stam, warrior), 0, "2 Str + 1 Sta vs 6 Sta is about even")
	var rare_sword := ItemInstance.from_weapon(Db.get_weapon(&"sword"), Items.Rarity.RARE)
	var sword := ItemInstance.from_weapon(Db.get_weapon(&"sword"))
	check_eq(ItemTooltip.upgrade_direction(rare_sword, sword, warrior), 1, "weapons compare damage")
	check_eq(ItemTooltip.upgrade_direction(sword, rare_sword, warrior), -1, "and the other way round")
	var staff := ItemInstance.from_weapon(Db.get_weapon(&"staff"))
	var axe := ItemInstance.from_weapon(Db.get_weapon(&"two_hand_axe"))
	check_eq(ItemTooltip.upgrade_direction(staff, axe, mage), 1, "intellect scaling counts for a mage")
	check_eq(ItemTooltip.upgrade_direction(axe, staff, warrior), 1, "strength scaling counts for a warrior")


func test_equipped_for_compare() -> void:
	var eq := Equipment.new(Db.get_class_data(&"rogue"))
	var ring := armor("New", Items.SlotType.RING, Items.NO_ARMOR, 2, {"agility": 5})
	check(ItemTooltip.equipped_for_compare(ring, eq) == null, "empty ring slot -> nothing to compare")
	var good := armor("Good", Items.SlotType.RING, Items.NO_ARMOR, 2, {"agility": 6})
	var weak := armor("Weak", Items.SlotType.RING, Items.NO_ARMOR, 1, {"agility": 1})
	eq.slots[Items.EquipSlot.RING_1] = good
	check(ItemTooltip.equipped_for_compare(ring, eq) == null, "Ring 2 still empty")
	eq.slots[Items.EquipSlot.RING_2] = weak
	check(ItemTooltip.equipped_for_compare(ring, eq) == weak, "compares with the weaker ring")
	var helm := armor("Helm", Items.SlotType.HEAD, ClassData.ArmorType.LEATHER, 1, {"agility": 2})
	var worn := armor("Worn", Items.SlotType.HEAD, ClassData.ArmorType.LEATHER, 0, {"agility": 1})
	eq.slots[Items.EquipSlot.HEAD] = worn
	check(ItemTooltip.equipped_for_compare(helm, eq) == worn, "single slot")
	check(ItemTooltip.equipped_for_compare(null, eq) == null, "null item")


func test_text_helpers() -> void:
	check_eq(ItemTooltip.slot_text(ItemInstance.from_weapon(Db.get_weapon(&"two_hand_axe"))), "Two-Hand", "two-hander")
	check_eq(ItemTooltip.slot_text(ItemInstance.from_weapon(Db.get_weapon(&"shield"))), "Off Hand", "shield")
	check_eq(ItemTooltip.type_text(ItemInstance.from_weapon(Db.get_weapon(&"two_hand_axe"))), "Axe", "axe")
	var ring := armor("R", Items.SlotType.RING, Items.NO_ARMOR, 0, {})
	check_eq(ItemTooltip.slot_text(ring), "Finger", "ring slot WoW name")
	check_eq(ItemTooltip.type_text(ring), "", "jewellery has no type")
	check_eq(ItemTooltip.fmt_number(10.2), "10.2", "one decimal")
	check_eq(ItemTooltip.fmt_number(6.0), "6", "whole numbers")


# --- Tier sets (M5) ---------------------------------------------------------------------------

## A tier-set piece "set_<class>_<slot>" as the generator makes it (wave 8, bought).
static func set_piece(class_id: StringName, slot: String) -> ItemInstance:
	return ItemGenerator.from_unique(Db.get_unique(StringName("set_%s_%s" % [class_id, slot])), 8, false,
			RandomNumberGenerator.new())


## Every shown label whose text is exactly [param text] (a piece name can also be the title).
func _exact(text: String) -> Array[Label]:
	var out: Array[Label] = []
	for l in ItemTooltip._labels(tip):
		if l.text == text:
			out.append(l)
	return out


func _index_of(text: String) -> int:
	return Array(tip.line_texts()).find(text)


func test_set_block_for_the_viewers_equipment() -> void:
	var warrior := Db.get_class_data(&"warrior")
	var eq := Equipment.new(warrior)
	eq.slots[Items.EquipSlot.HEAD] = set_piece(&"warrior", "head")
	eq.slots[Items.EquipSlot.LEGS] = set_piece(&"warrior", "legs")
	var chest := set_piece(&"warrior", "chest")
	tip.viewer_equipment = eq
	tip.show_item(chest, warrior)
	check(tip.find_line("Part of the") == null, "the old one-liner is gone")
	var header := tip.find_line("Battlegear of Fury (2/5)", true)
	check(header != null and _color(header).is_equal_approx(ItemTooltip.SET_NAME_COLOR), "set name + worn count in gold: %s" % tip.line_texts())
	for piece_name in ["Helm of Fury", "Legplates of Fury"]:
		var l := _exact(piece_name)
		check(l.size() == 1 and _color(l[0]).is_equal_approx(ItemTooltip.SET_PIECE_WORN), "%s worn: bright" % piece_name)
	for piece_name in ["Pauldrons of Fury", "Gauntlets of Fury"]:
		var l := _exact(piece_name)
		check(l.size() == 1 and _color(l[0]).is_equal_approx(ItemTooltip.SET_PIECE_MISSING), "%s missing: grey" % piece_name)
	var own := _exact("Breastplate of Fury")
	check(own.size() == 2 and _color(own[1]).is_equal_approx(ItemTooltip.SET_PIECE_MISSING),
		"the shown piece is listed too (grey until worn)")
	var two := tip.find_line("(2) Set: Increases your Rage generation by 10%.", true)
	check(two != null and _color(two).is_equal_approx(ItemTooltip.ENCHANT_GREEN), "active 2-piece bonus green")
	var four := tip.find_line("(4) Set: Whirlwind has a 30% chance to cost no Rage.", true)
	check(four != null and _color(four).is_equal_approx(ItemTooltip.DIM), "inactive 4-piece bonus grey")
	check(_index_of("Classes: Warrior") < _index_of("Battlegear of Fury (2/5)"), "after the Classes line")
	check(_index_of("(4) Set: Whirlwind has a 30% chance to cost no Rage.") < _index_of("\"%s\"" % chest.flavor), "before the flavor text")
	eq.slots[Items.EquipSlot.CHEST] = chest
	eq.slots[Items.EquipSlot.HANDS] = set_piece(&"warrior", "hands")
	tip.show_item(chest, warrior)
	check(tip.find_line("Battlegear of Fury (4/5)", true) != null, "4 worn")
	own = _exact("Breastplate of Fury")
	check(own.size() == 2 and _color(own[1]).is_equal_approx(ItemTooltip.SET_PIECE_WORN), "now worn")
	four = tip.find_line("(4) Set: Whirlwind has a 30% chance to cost no Rage.", true)
	check(four != null and _color(four).is_equal_approx(ItemTooltip.ENCHANT_GREEN), "4-piece bonus active")


func test_set_block_without_equipment() -> void:
	tip.viewer_equipment = null
	tip.show_item(set_piece(&"mage", "head"), Db.get_class_data(&"mage"))
	var header := tip.find_line("Regalia of the Arcane (5 pieces)", true)
	check(header != null and _color(header).is_equal_approx(ItemTooltip.SET_NAME_COLOR), "(5 pieces) without equipment")
	for piece_name in ["Mantle of the Arcane", "Robes of the Arcane", "Gloves of the Arcane", "Leggings of the Arcane"]:
		var l := _exact(piece_name)
		check(l.size() == 1 and _color(l[0]).is_equal_approx(ItemTooltip.SET_PIECE_MISSING), "%s grey" % piece_name)
	for prefix in ["(2) Set: ", "(4) Set: "]:
		var l := tip.find_line(prefix)
		check(l != null and _color(l).is_equal_approx(ItemTooltip.DIM), "%s grey" % prefix)
	check(tip.find_line("(4) Set: Casting Blink increases your damage by 30% for 3 sec. Can only occur once every 6 sec.", true) != null,
		"4-piece text")


func test_set_block_of_an_unknown_set() -> void:
	var odd := armor("Odd Helm", Items.SlotType.HEAD, ClassData.ArmorType.CLOTH, 3, {"stamina": 2})
	odd.set_id = &"zz_unknown_set"
	tip.show_item(odd)
	var l := tip.find_line("Part of the Zz Unknown Set set", true)
	check(l != null and _color(l).is_equal_approx(ItemTooltip.DIM), "no SetData: the plain line: %s" % tip.line_texts())


func test_upgrade_direction_values_set_thresholds() -> void:
	var warrior := Db.get_class_data(&"warrior")
	var eq := Equipment.new(warrior)
	eq.slots[Items.EquipSlot.HEAD] = set_piece(&"warrior", "head")
	var set_shoulders := set_piece(&"warrior", "shoulders")
	var set_score := ItemTooltip.item_score(set_shoulders, warrior)
	# Plain shoulders a bit better (within 30%) and much better (more than 30%).
	var better := armor("Better", Items.SlotType.SHOULDERS, ClassData.ArmorType.PLATE, 3, {"strength": 7, "stamina": 6, "armor": 2})
	var much := armor("Much", Items.SlotType.SHOULDERS, ClassData.ArmorType.PLATE, 3, {"strength": 10, "stamina": 7, "armor": 2})
	var b_score := ItemTooltip.item_score(better, warrior)
	var m_score := ItemTooltip.item_score(much, warrior)
	check(set_score < b_score and set_score >= b_score * 0.7, "fixture: %.1f is within 30%% below %.1f" % [set_score, b_score])
	check(set_score < m_score * 0.7, "fixture: %.1f is more than 30%% below %.1f" % [set_score, m_score])
	eq.slots[Items.EquipSlot.SHOULDERS] = better
	check_eq(ItemTooltip.upgrade_direction(set_shoulders, better, warrior), -1, "without equipment: stats only")
	check_eq(ItemTooltip.upgrade_direction(set_shoulders, better, warrior, eq), 1, "completes the 2-piece: upgrade")
	eq.slots[Items.EquipSlot.SHOULDERS] = much
	check_eq(ItemTooltip.upgrade_direction(set_shoulders, much, warrior, eq), -1, "more than 30% worse: no")
	# The other way round: keep an active bonus unless the new item is far better.
	eq.slots[Items.EquipSlot.SHOULDERS] = set_shoulders
	check_eq(ItemTooltip.upgrade_direction(better, set_shoulders, warrior), 1, "stats alone: better")
	check_eq(ItemTooltip.upgrade_direction(better, set_shoulders, warrior, eq), -1, "but it breaks the 2-piece bonus")
	check_eq(ItemTooltip.upgrade_direction(much, set_shoulders, warrior, eq), 1, "far better: worth it")
	# A third piece crosses no threshold: plain stats.
	var plain_chest := armor("Chest", Items.SlotType.CHEST, ClassData.ArmorType.PLATE, 3, {"strength": 10, "stamina": 8, "armor": 3})
	eq.slots[Items.EquipSlot.CHEST] = plain_chest
	var set_chest := set_piece(&"warrior", "chest")
	check(ItemTooltip.item_score(set_chest, warrior) < ItemTooltip.item_score(plain_chest, warrior) - ItemTooltip.UPGRADE_THRESHOLD,
		"fixture: the set chest is weaker")
	check_eq(ItemTooltip.upgrade_direction(set_chest, plain_chest, warrior, eq), -1, "3rd piece: no threshold, stats decide")
	# Bots: the same rule (Intermission.is_bot_upgrade / bot_equip_upgrades).
	eq.slots[Items.EquipSlot.SHOULDERS] = better
	eq.backpack.append(set_shoulders)
	check(ItemTooltip.upgrade_direction(set_shoulders, ItemTooltip.equipped_for_compare(set_shoulders, eq), warrior, eq) > 0,
		"a bot would put the set shoulders on")


## Which backpack pieces upgrade_direction counts as worn (SetBonuses.bonus_change lookahead).
func test_set_lookahead_picks_the_reachable_backpack_pieces() -> void:
	var warrior := Db.get_class_data(&"warrior")
	var eq := Equipment.new(warrior)
	eq.slots[Items.EquipSlot.HEAD] = set_piece(&"warrior", "head")
	eq.slots[Items.EquipSlot.CHEST] = set_piece(&"warrior", "chest")
	var legs := set_piece(&"warrior", "legs")
	var hands := set_piece(&"warrior", "hands")
	var shoulders := set_piece(&"warrior", "shoulders")
	var none: Array[ItemInstance] = []
	check(ItemTooltip.set_lookahead(legs, none, eq, warrior).is_empty(), "empty backpack: nothing")
	eq.backpack.append_array([legs, hands, set_piece(&"warrior", "legs"), set_piece(&"mage", "shoulders")])
	check_eq(ItemTooltip.set_lookahead(legs, none, eq, warrior), [hands] as Array[ItemInstance],
		"the hands (an empty slot); not the item, not a piece for its own slot, not another set")
	var plain := armor("Plain", Items.SlotType.SHOULDERS, ClassData.ArmorType.PLATE, 3, {"strength": 1})
	check(ItemTooltip.set_lookahead(plain, none, eq, warrior).is_empty(), "a plain item replacing a plain one: no set involved")
	eq.slots[Items.EquipSlot.HANDS] = armor("Gauntlets", Items.SlotType.HANDS, ClassData.ArmorType.PLATE, 3, {"strength": 60, "stamina": 30})
	check(ItemTooltip.item_score(hands, warrior) < ItemTooltip.item_score(eq.get_item(Items.EquipSlot.HANDS), warrior) * 0.7,
		"fixture: the worn gauntlets are far better")
	check(ItemTooltip.set_lookahead(legs, none, eq, warrior).is_empty(), "more than 30% worse than what it replaces: not counted")
	eq.slots[Items.EquipSlot.HANDS] = set_piece(&"rogue", "hands")
	check(ItemTooltip.set_lookahead(legs, none, eq, warrior).is_empty(), "never pushes out a worn set piece")
	eq.slots.erase(Items.EquipSlot.HANDS)
	eq.slots[Items.EquipSlot.SHOULDERS] = shoulders
	var chest := eq.get_item(Items.EquipSlot.CHEST)
	var plain_chest := armor("Plain chest", Items.SlotType.CHEST, ClassData.ArmorType.PLATE, 3, {"strength": 1})
	check_eq(ItemTooltip.set_lookahead(plain_chest, [chest] as Array[ItemInstance], eq, warrior), [legs, hands] as Array[ItemInstance],
		"a plain item pushing out a piece: that piece's set is looked at (one piece per slot)")


# --- ItemIcon / ItemArt ---------------------------------------------------------------------------

func test_item_icon_state() -> void:
	var icon := ItemIcon.create(null, 48)
	check_eq(icon.custom_minimum_size, Vector2(48, 48), "size")
	icon.set_empty_slot(Items.EquipSlot.HEAD)
	check(icon.item == null and icon.empty_slot == Items.EquipSlot.HEAD, "empty slot look")
	var helm := armor("H", Items.SlotType.HEAD, ClassData.ArmorType.MAIL, Items.Rarity.EPIC, {})
	icon.set_item(helm)
	check(icon.item == helm, "item set")
	check(icon.rarity_color().is_equal_approx(UiTheme.RARITY_COLORS[3]), "epic border colour")
	icon.set_upgrade_badge(5)
	check_eq(icon.badge, 1, "badge clamped to +1")
	icon.set_upgrade_badge(-2)
	check_eq(icon.badge, -1, "down badge")
	icon.set_unusable(true)
	check(icon.unusable, "unusable tint")
	icon.set_selected(true, Color.RED)
	check(icon.selected and icon.cursor_color == Color.RED, "cursor")
	icon.set_empty_slot(Items.EquipSlot.RING_1)
	check(icon.item == null and icon.badge == 0 and not icon.unusable, "empty slot clears the extras")
	check(ItemIcon.rarity_color_of(0) == ItemIcon.COMMON_BORDER, "common border greyer than white")
	icon.free()


func test_item_art_shapes() -> void:
	var cloth := armor("C", Items.SlotType.HEAD, ClassData.ArmorType.CLOTH, 0, {})
	check_eq(ItemArt.shape_for(cloth), &"hood", "cloth head = hood")
	var plate := armor("P", Items.SlotType.HEAD, ClassData.ArmorType.PLATE, 0, {})
	check_eq(ItemArt.shape_for(plate), &"head", "helm")
	for id: StringName in Db.weapons:
		var w := ItemInstance.from_weapon(Db.weapons[id])
		check(ItemArt.shape_for(w) in ItemArt.WEAPON_SHAPES, "weapon %s has a silhouette" % id)
	for t in Items.SlotType.values():
		check(ItemArt.SLOT_SHAPES.has(t), "slot type %d has a silhouette" % t)
	for s in Items.EquipSlot.values():
		check(ItemArt.EMPTY_SHAPES.has(s), "equip slot %d has an empty silhouette" % s)
	var pal := ItemArt.palette_for(plate)
	check(pal.main.is_equal_approx(ItemArt.ARMOR_COLORS[ClassData.ArmorType.PLATE]), "plate material colour")
	var epic := armor("E", Items.SlotType.RING, Items.NO_ARMOR, Items.Rarity.EPIC, {})
	check(ItemArt.palette_for(epic).gem.is_equal_approx(UiTheme.RARITY_COLORS[3]), "gem in rarity colour")
