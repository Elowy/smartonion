extends TestCase
## M6 ARTIFACTS on screen and for the bots: the tooltip (golden properties, "Awakens in N waves",
## "(needs Whirlwind)", no sell price, the pair notes), the greyed Sell entry of the character
## panel, the compare / upgrade rules and what bots do with an Artifact (Need, equip, never sell).

const UiFakes := preload("res://tests/ui_fakes.gd")

var players: Array[Player] = []
var panels: Array[PlayerPanel] = []
var tips: Array[ItemTooltip] = []


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(2, 9)
	RunState.set_wave(10)
	players.clear()
	panels.clear()
	tips.clear()


func after_each() -> void:
	for t in tips:
		UiFakes.free_node(t)
	for panel in panels:
		UiFakes.free_node(panel)
	for p in players:
		if is_instance_valid(p):
			p.free()
	tips.clear()
	panels.clear()
	players.clear()
	UiFakes.reset_players()


func _join(class_id: StringName) -> PlayerSlot:
	var input := ScriptedInput.new("art_ui:%d" % PlayerManager.count())
	var slot := PlayerManager.join(input, Db.get_class_data(class_id))
	players.append(Player.create(slot))
	return slot


func _eq(slot: PlayerSlot) -> Equipment:
	return (slot.player as Player).equipment


func _artifact(class_id: StringName, waves: int = 0) -> ItemInstance:
	var item := ItemGenerator.generate_artifact(class_id, 10)
	item.artifact_waves = waves
	if item.companion != null:
		item.companion.artifact_waves = waves
	return item


func _tooltip(item: ItemInstance, viewer: ClassData = null, viewer_eq: Equipment = null) -> ItemTooltip:
	var t := ItemTooltip.create()
	tree.root.add_child(t)
	t.viewer_equipment = viewer_eq
	t.show_item(item, viewer)
	tips.append(t)
	return t


func _panel(slot: PlayerSlot) -> PlayerPanel:
	var panel := PlayerPanel.create(slot)
	tree.root.add_child(panel)
	panel.set_input_focus(true)
	panels.append(panel)
	return panel


func _tap(panel: PlayerPanel, slot: PlayerSlot, button: PlayerInput.Pad) -> void:
	var input := slot.input as ScriptedInput
	input.press(button)
	input.poll(1.0 / 60.0)
	panel.handle_input(input)
	input.release(button)
	input.poll(0.0)
	panel.handle_input(input)


func _lines(t: ItemTooltip) -> String:
	return "\n".join(t.line_texts())


# --- Tooltip ----------------------------------------------------------------------------

func test_a_fresh_artifact_tooltip_says_when_each_property_awakens() -> void:
	var t := _tooltip(_artifact(&"warrior"), Db.get_class_data(&"warrior"))
	var text := _lines(t)
	check("Earthsplitter" in text, "the name")
	check("Artifact" not in text.split("\n")[0], "(the rarity is the colour of the name)")
	check("Item Level %d" % (10 + 30 + 25) in text, "Item Level 10 + 3 x wave + 25")
	check("Earthquake" in text and "Awakens in 3 waves" in text, "property 1: awakens in 3 waves")
	check("Shockwave" in text and "Awakens in 6 waves" in text, "property 2: awakens in 6 waves")
	check("Whirlwind leaves an earthquake zone" in text, "the text is shown too")
	check("Sell Price" not in text, "an Artifact has no sell price")


func test_the_tooltip_counts_the_waves_down() -> void:
	var item := _artifact(&"warrior", 2)
	var text := _lines(_tooltip(item, Db.get_class_data(&"warrior")))
	check("Awakens in 1 wave" in text and "Awakens in 1 waves" not in text, "1 wave left: singular")
	check("Awakens in 4 waves" in text, "4 waves left for property 2")


func test_awake_properties_are_golden_and_asleep_ones_dim() -> void:
	var asleep := _tooltip(_artifact(&"warrior", 0), Db.get_class_data(&"warrior"))
	var name_asleep := asleep.find_line("Earthquake", true)
	check(name_asleep != null, "the title line")
	var awake := _tooltip(_artifact(&"warrior", 3), Db.get_class_data(&"warrior"))
	var name_awake := awake.find_line("Earthquake", true)
	check(name_awake.get_theme_color(&"font_color") == ItemTooltip.ARTIFACT_GOLD, "awake: gold")
	check(name_asleep.get_theme_color(&"font_color") == ItemTooltip.ARTIFACT_ASLEEP, "asleep: dim")
	check(awake.find_line("Awakens in 3 waves") != null, "property 2 still waits: it says so")
	check(awake.find_line("Awakens in 6 waves") == null, "(property 1 is awake: no waiting line for it)")
	var both := _tooltip(_artifact(&"warrior", 6), Db.get_class_data(&"warrior"))
	check(both.find_line("Awakens in") == null, "nothing left to wait for after six")
	check(both.find_line("Shockwave", true).get_theme_color(&"font_color") == ItemTooltip.ARTIFACT_GOLD, "both gold")


func test_a_missing_ability_greys_the_property_with_its_name() -> void:
	var warrior := _join(&"warrior")
	var mage := _join(&"mage")
	var item := _artifact(&"warrior", 6)
	var for_mage := _tooltip(item, Db.get_class_data(&"mage"), _eq(mage))
	check(for_mage.find_line("(needs Whirlwind)") != null, "(needs Whirlwind) for a hero without it")
	check(for_mage.find_line("(needs Charge)") != null, "(needs Charge)")
	var grey := for_mage.find_line("Earthquake", true)
	check(grey.get_theme_color(&"font_color") == ItemTooltip.DIM, "greyed")
	var for_warrior := _tooltip(item, Db.get_class_data(&"warrior"), _eq(warrior))
	check(for_warrior.find_line("(needs") == null, "the Warrior knows both abilities")
	check(for_warrior.find_line("Earthquake", true).get_theme_color(&"font_color") == ItemTooltip.ARTIFACT_GOLD, "gold")


func test_the_tooltip_without_a_viewer_never_greys() -> void:
	var t := _tooltip(_artifact(&"warrior", 6))
	check(t.find_line("(needs") == null, "no hero to ask: nothing is missing")


func test_ordinary_items_keep_their_sell_price_and_have_no_artifact_lines() -> void:
	var sword := ItemInstance.from_weapon(Db.get_weapon(&"sword"), Items.Rarity.EPIC, 5)
	sword.buy_price = 100
	var text := _lines(_tooltip(sword, Db.get_class_data(&"warrior")))
	check("Sell Price" in text, "sold for 35")
	check("Awakens" not in text, "no property lines")


func test_the_pair_tooltips_name_each_other() -> void:
	var fangs := _artifact(&"rogue")
	var main := _lines(_tooltip(fangs, Db.get_class_data(&"rogue")))
	check("A pair: it equips together with Fangs of the Shadow (Off Hand)" in main, "the main piece names its partner")
	check("Shadow's Bite" in main and "Hidden Fangs" in main, "the properties are on the main piece")
	check("(24 damage per second)" in main and "(48 damage" not in main, "the DPS line is this dagger's alone")
	var off := _lines(_tooltip(fangs.companion, Db.get_class_data(&"rogue")))
	check("Off-hand piece of a pair" in off, "the off piece says what it is")
	check("Shadow's Bite" not in off, "without repeating the properties")
	check("Sell Price" not in off, "no sell price either")


func test_the_weapon_lines_show_the_grown_damage() -> void:
	var item := _artifact(&"warrior")
	var before := _lines(_tooltip(item, Db.get_class_data(&"warrior")))
	Artifacts.grow_item(item)
	var after := _lines(_tooltip(item, Db.get_class_data(&"warrior")))
	check(before != after, "the tooltip changes with the growth")
	check("Item Level %d" % (65 + 3) in after, "Item Level +3")


# --- The panel --------------------------------------------------------------------------

func test_the_sell_entry_of_an_artifact_is_greyed_out() -> void:
	var slot := _join(&"warrior")
	var panel := _panel(slot)
	var item := _artifact(&"warrior")
	_eq(slot).add_to_backpack(item)
	panel.select_backpack(0)
	_tap(panel, slot, PlayerInput.Pad.A)
	check(panel.is_menu_open(), "the menu opens")
	check("Sell" in panel.menu_labels(), "the entry is listed")
	check(not panel.menu_entry_enabled("Sell"), "greyed out")
	check_eq(panel.menu_entry_detail("Sell"), "Artifact", "says why")
	check(panel.menu_entry_enabled("Equip"), "Equip works")
	check_eq(panel.menu_entry_detail("Forge"), "", "(the Forge entry is blocked by its own reason)")
	check(not panel.menu_entry_enabled("Forge"), "no Forge for an Artifact")


func test_selling_an_artifact_is_refused_even_when_forced() -> void:
	var slot := _join(&"warrior")
	var panel := _panel(slot)
	var item := _artifact(&"warrior")
	_eq(slot).add_to_backpack(item)
	var gold := RunState.gold
	panel._do_sell(item)
	check(item in _eq(slot).backpack, "still in the backpack")
	check_eq(RunState.gold, gold, "no gold")
	check_eq(panel.last_message, PlayerPanel.ARTIFACT_NO_SELL, "the reason as the toast")


func test_the_x_sell_shortcut_cannot_sell_an_artifact() -> void:
	var slot := _join(&"warrior")
	var panel := _panel(slot)
	var item := _artifact(&"warrior")
	_eq(slot).add_to_backpack(item)
	panel.select_backpack(0)
	_tap(panel, slot, PlayerInput.Pad.X)
	_tap(panel, slot, PlayerInput.Pad.A)
	check(item in _eq(slot).backpack, "X then A does not sell it")
	check_eq(RunState.gold, 0, "no gold")


func test_the_pair_equips_from_the_menu_and_its_off_piece_is_selected_with_the_slot() -> void:
	var slot := _join(&"rogue")
	var panel := _panel(slot)
	var fangs := _artifact(&"rogue")
	_eq(slot).add_to_backpack(fangs)
	panel.select_backpack(0)
	_tap(panel, slot, PlayerInput.Pad.A)
	_tap(panel, slot, PlayerInput.Pad.A)  # Equip (the only slot: no choice menu)
	check(_eq(slot).get_item(Items.EquipSlot.MAIN_HAND) == fangs, "main hand")
	check(_eq(slot).get_item(Items.EquipSlot.OFF_HAND) == fangs.companion, "off hand")
	check(fangs not in _eq(slot).backpack, "out of the backpack")


# --- Compare / upgrade rules -------------------------------------------------------------

func test_an_artifact_always_beats_what_it_replaces_and_is_never_replaced() -> void:
	var warrior := Db.get_class_data(&"warrior")
	var eq := Equipment.new(warrior)
	eq.equip_starting_weapons()
	var artifact := _artifact(&"warrior")
	var legendary := ItemInstance.from_weapon(Db.get_weapon(&"two_hand_axe"), Items.Rarity.LEGENDARY, 25)
	legendary.stats = {Stats.STRENGTH: 90.0, Stats.CRIT: 40.0}
	eq.slots[Items.EquipSlot.MAIN_HAND] = legendary
	var current := ItemTooltip.equipped_for_compare(artifact, eq)
	check_eq(ItemTooltip.upgrade_direction(artifact, current, warrior, eq), 1, "an Artifact replaces even a monster Legendary")
	eq.slots[Items.EquipSlot.MAIN_HAND] = artifact
	var other := ItemInstance.from_weapon(Db.get_weapon(&"two_hand_axe"), Items.Rarity.LEGENDARY, 25)
	other.stats = {Stats.STRENGTH: 900.0}
	var there := ItemTooltip.equipped_for_compare(other, eq)
	check_eq(ItemTooltip.upgrade_direction(other, there, warrior, eq), -1, "and is never swapped for ordinary gear")
	check_eq(ItemTooltip.upgrade_direction(artifact, null, Db.get_class_data(&"mage")), -1, "another class cannot use it")


func test_a_pair_is_compared_and_scored_as_both_pieces() -> void:
	var fangs := _artifact(&"rogue")
	var single_stats := ItemTooltip.total_stats(fangs.companion)
	var both := ItemTooltip.total_stats(fangs)
	for stat in single_stats:
		check(both.get(stat, 0.0) >= single_stats[stat] + fangs.stats.get(stat, 0.0) - 0.001, "%s counts both pieces" % stat)
	check_near(ItemTooltip.weapon_dps(fangs), ItemTooltip.weapon_dps(fangs.companion) * 2.0, ItemTooltip.weapon_dps(fangs) * 0.05,
			"the DPS of both daggers")
	var eq := Equipment.new(Db.get_class_data(&"rogue"))
	eq.equip_starting_weapons()
	var pair := ItemTooltip.equipped_for_compare(fangs, eq)
	check(pair is ItemTooltip.EquippedPair, "compared with both starting daggers, like a two-hander")


# --- Bots -------------------------------------------------------------------------------

func test_a_bot_equips_its_artifact_over_better_looking_gear() -> void:
	var slot := _join(&"warrior")
	var eq := _eq(slot)
	var artifact := _artifact(&"warrior")
	var legendary := ItemInstance.from_weapon(Db.get_weapon(&"two_hand_axe"), Items.Rarity.LEGENDARY, 25)
	legendary.stats = {Stats.STRENGTH: 90.0, Stats.CRIT: 40.0}
	eq.add_to_backpack(legendary)
	eq.add_to_backpack(artifact)
	check(Intermission.is_bot_upgrade(artifact, slot, eq), "an upgrade")
	Intermission.bot_equip_upgrades(slot)
	check(eq.get_item(Items.EquipSlot.MAIN_HAND) == artifact, "the Artifact is in the main hand")
	check(legendary in eq.backpack, "the Legendary waits in the backpack: it never swaps back")


func test_a_bot_never_sells_an_artifact_to_make_room() -> void:
	var slot := _join(&"mage")
	var eq := _eq(slot)
	var foreign := _artifact(&"warrior")  # not usable by a Mage: "not an upgrade"
	eq.add_to_backpack(foreign)
	for i in Items.BACKPACK_SIZE - 1:
		var junk := ItemInstance.from_weapon(Db.get_weapon(&"wand"), Items.Rarity.COMMON, 1)
		junk.buy_price = 5
		eq.add_to_backpack(junk)
	check(not eq.has_space(), "a full backpack")
	check(not Intermission.is_bot_upgrade(foreign, slot, eq), "not an upgrade for a Mage")
	var screen := Intermission.new()
	var gold := RunState.gold
	screen._bot_make_room(slot, eq)
	screen.free()
	check(foreign in eq.backpack, "the Artifact stays")
	check(eq.has_space(), "a junk item was sold instead")
	check(RunState.gold > gold, "for gold")
