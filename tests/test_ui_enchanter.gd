extends TestCase
## The Enchanter tab (GDD 5.7, 12; PlayerPanel tab 4 / EnchanterTab, M6a) and the Disenchant
## entry of the Character tab's item menu, driven through PlayerPanel.handle_input like a real
## pad: the item grid (equipped first, then the backpack; spatial navigation; the edge steps into
## the enchants), A empowers / imbues, X rerolls, refusals show their reason, the hold rule above
## half the purse, LT / RT while a hold runs, the "Enchanter (N)" label following the team's Dust
## (also while hidden), the tab's fit at the panel's design size and in the 4-player market
## layout, and the purse board's Dust.

const UiFakes := preload("res://tests/ui_fakes.gd")
const Support := preload("res://tests/test_loot_support.gd")
const MarketFakes := preload("res://tests/test_ui_market_fakes.gd")
const DT := 1.0 / 60.0

var players: Array[Player] = []
var panels: Array[PlayerPanel] = []
var messages: Array[String] = []
## Whether the press frame of the last _press() used the press (PlayerPanel.last_input_consumed).
var consumed := false
var _async := false
var _root_size := Vector2i.ZERO


func is_async() -> bool:
	return _async


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(1, 7)
	RunState.wave = 15
	players.clear()
	panels.clear()
	messages.clear()


func after_each() -> void:
	for panel in panels:
		UiFakes.free_node(panel)
	for p in players:
		if is_instance_valid(p):
			p.free()
	panels.clear()
	players.clear()
	if _root_size != Vector2i.ZERO:
		tree.root.size = _root_size
		_root_size = Vector2i.ZERO
	UiFakes.reset_players()
	RunState.start_run(1, 7)


# --- Fixtures ----------------------------------------------------------------------------------

func _hero(class_id: StringName = &"warrior") -> PlayerSlot:
	var slot := PlayerManager.join(ScriptedInput.new("ench:%d" % PlayerManager.count()), Db.get_class_data(class_id))
	var p := Player.create(slot)
	players.append(p)
	return slot


func _eq(slot: PlayerSlot) -> Equipment:
	return (slot.player as Player).equipment


func _panel(slot: PlayerSlot, open_tab: bool = true) -> PlayerPanel:
	var panel := PlayerPanel.create(slot)
	tree.root.add_child(panel)
	panel.set_input_focus(true)
	panels.append(panel)
	panel.enchanter.message.connect(func(_bb: String, plain: String, _c: Color, _coin: bool) -> void: messages.append(plain))
	if open_tab:
		panel.set_tab(PlayerPanel.ENCHANTER_TAB)
	return panel


## A hand-built item of [param rarity] in [param slot_type] with the Db enchants [param ids] at [param rank].
func _item(rarity: int, slot_type: Items.SlotType, ids: Array[StringName] = [], rank: int = 0, name: String = "") -> ItemInstance:
	var item := Support.make_armor(40, ClassData.ArmorType.PLATE, 20, rarity, slot_type)
	item.wave = 15
	item.buy_price = ItemGenerator.price_for(rarity, 15)
	item.display_name = name if name != "" else "%s %s" % [Items.RARITY_NAMES[rarity], Items.SLOT_NAMES[slot_type]]
	for id in ids:
		item.enchants.append(EnchantRoll.new(Db.get_enchant(id), rank))
	return item


## A hero that wears only [param worn] items (equipment slots by position) and carries [param bag].
func _dress(slot: PlayerSlot, worn: Dictionary, bag: Array[ItemInstance] = []) -> void:
	var eq := _eq(slot)
	eq.slots.clear()
	eq.backpack.clear()
	for pos in worn:
		eq.slots[pos] = worn[pos]
	for item in bag:
		eq.backpack.append(item)
	eq.changed.emit()


func _rich(gold: int = 1000, dust: int = 100) -> void:
	RunState.add_gold(gold)
	RunState.add_dust(dust, -1, "fixture")


func _press(panel: PlayerPanel, slot: PlayerSlot, button: PlayerInput.Pad) -> void:
	var input := slot.input as ScriptedInput
	input.press(button)
	input.poll(DT)
	panel.handle_input(input, DT)
	consumed = panel.last_input_consumed
	input.release(button)
	input.poll(0.0)
	panel.handle_input(input, 0.0)


func _hold(panel: PlayerPanel, slot: PlayerSlot, button: PlayerInput.Pad, seconds: float) -> void:
	var input := slot.input as ScriptedInput
	input.press(button)
	for i in int(roundf(seconds * 60.0)):
		input.poll(DT)
		panel.handle_input(input, DT)


func _release(panel: PlayerPanel, slot: PlayerSlot, button: PlayerInput.Pad) -> void:
	var input := slot.input as ScriptedInput
	input.release(button)
	input.poll(DT)
	panel.handle_input(input, DT)


func _dir(panel: PlayerPanel, slot: PlayerSlot, dir: Vector2i) -> void:
	var button := PlayerInput.Pad.DPAD_RIGHT
	if dir.x < 0:
		button = PlayerInput.Pad.DPAD_LEFT
	elif dir.y < 0:
		button = PlayerInput.Pad.DPAD_UP
	elif dir.y > 0:
		button = PlayerInput.Pad.DPAD_DOWN
	_press(panel, slot, button)


## One hero with an Epic helm (Mighty I) worn, in the Enchanter tab, rich enough for several actions.
func _simple() -> Array:
	var slot := _hero()
	var helm := _item(Items.Rarity.EPIC, Items.SlotType.HEAD, [&"mighty"], 0, "Test Helm")
	_dress(slot, {Items.EquipSlot.HEAD: helm, Items.EquipSlot.MAIN_HAND: ItemInstance.from_weapon(Db.get_weapon(&"sword"))})
	_rich()
	var panel := _panel(slot)
	return [slot, panel, helm]


# --- Disenchant in the item menu --------------------------------------------------------------

func test_disenchant_sits_next_to_sell_and_gives_dust() -> void:
	var slot := _hero()
	var panel := _panel(slot, false)
	var eq := _eq(slot)
	var epic := _item(Items.Rarity.EPIC, Items.SlotType.HEAD, [&"mighty"], 0, "Spare Helm")
	eq.add_to_backpack(epic)
	var seen: Array[Vector2i] = []
	panel.item_disenchanted.connect(func(it: ItemInstance, dust: int) -> void:
		seen.append(Vector2i(1 if it == epic else 0, dust)))
	panel.select_backpack(0)
	_press(panel, slot, PlayerInput.Pad.A)
	var labels := Array(panel.menu_labels())
	check_eq(labels, ["Equip", "Sell", "Disenchant", "Cancel"], "Disenchant right after Sell")
	check_eq(panel.menu_entry_detail("Disenchant"), "+8 Dust", "an Epic: +8 Dust")
	check(panel.menu_entry_enabled("Disenchant"), "enabled")
	check(panel.select_menu_entry("Disenchant"), "cursor on it")
	_press(panel, slot, PlayerInput.Pad.A)
	check(not panel.is_menu_open(), "the menu closed")
	check(eq.backpack.is_empty(), "the item is gone")
	check_eq(RunState.arcane_dust, 8, "8 Dust in the team pile")
	check_eq(RunState.gold, 0, "no gold")
	check("8 Dust" in panel.last_message, "the toast says how much: %s" % panel.last_message)
	check_eq(seen, [Vector2i(1, 8)] as Array[Vector2i], "item_disenchanted")


func test_the_dust_by_rarity_shows_in_the_menu() -> void:
	var slot := _hero()
	var panel := _panel(slot, false)
	var eq := _eq(slot)
	var want: Array[String] = ["+1 Dust", "+2 Dust", "+4 Dust", "+8 Dust", "+16 Dust"]
	for r in 5:
		eq.add_to_backpack(_item(r, Items.SlotType.RING))
	for r in 5:
		panel.select_backpack(r)
		panel.open_menu()
		check_eq(panel.menu_entry_detail("Disenchant"), want[r], "%s" % Items.RARITY_NAMES[r])
		panel.close_menu()


func test_an_artifact_has_no_disenchant_entry() -> void:
	var slot := _hero()
	var panel := _panel(slot, false)
	_eq(slot).add_to_backpack(_item(Items.Rarity.ARTIFACT, Items.SlotType.WEAPON))
	panel.select_backpack(0)
	panel.open_menu()
	check(not Array(panel.menu_labels()).has("Disenchant"), "no Disenchant for an Artifact: %s" % str(panel.menu_labels()))


func test_disenchant_keeps_the_last_weapon() -> void:
	var slot := _hero()
	var panel := _panel(slot, false)
	var eq := _eq(slot)
	eq.slots.clear()
	var blade := Support.make_weapon(&"sword", Items.Rarity.UNCOMMON)
	eq.add_to_backpack(blade)
	eq.changed.emit()
	panel.select_backpack(0)
	panel.open_menu()
	check(not panel.menu_entry_enabled("Disenchant"), "greyed out like Sell")
	check_eq(panel.menu_entry_detail("Disenchant"), "Last weapon", "says why")
	panel.select_menu_entry("Disenchant")
	_press(panel, slot, PlayerInput.Pad.A)
	check(eq.backpack.has(blade), "still there")
	check_eq(RunState.arcane_dust, 0, "no Dust")
	check_eq(panel.last_message, Equipment.NEED_WEAPON, "the reason")


func test_equipped_items_are_not_in_the_disenchant_menu() -> void:
	var slot := _hero()
	var panel := _panel(slot, false)
	panel.select_equip_slot(Items.EquipSlot.MAIN_HAND)
	panel.open_menu()
	check(not Array(panel.menu_labels()).has("Disenchant"), "unequip first: %s" % str(panel.menu_labels()))


# --- The tab: items, label ---------------------------------------------------------------------

func test_the_tab_lists_equipped_items_first_then_the_backpack() -> void:
	var slot := _hero()
	var helm := _item(Items.Rarity.EPIC, Items.SlotType.HEAD, [&"mighty"])
	var ring := _item(Items.Rarity.RARE, Items.SlotType.RING, [&"blazing"])
	var sword := ItemInstance.from_weapon(Db.get_weapon(&"sword"))
	var chest := _item(Items.Rarity.COMMON, Items.SlotType.CHEST)
	var band := _item(Items.Rarity.UNCOMMON, Items.SlotType.RING)
	_dress(slot, {Items.EquipSlot.MAIN_HAND: sword, Items.EquipSlot.HEAD: helm, Items.EquipSlot.RING_1: ring}, [chest, band])
	var panel := _panel(slot)
	var tab := panel.enchanter
	check_eq(tab.items, [helm, ring, sword, chest, band] as Array[ItemInstance], "equipped (slot order), then the backpack")
	check_eq(tab.equipped_count, 3, "three equipped")
	check_eq(tab.cells.size(), 5, "one icon per item")
	check(tab.cells[0].item == helm and tab.cells[4].item == band, "icons in that order")
	check_eq(tab.selected_item(), helm, "the first one is selected")
	check(tab.is_equipped(helm) and not tab.is_equipped(chest), "equipped / backpack")
	check_eq(tab.context_text(), "Epic Head · Equipped", "context text")
	# The pips: filled for an enchant, hollow for a free slot; Common has none.
	check_eq([tab.cells[0].enchants, tab.cells[0].free_slots], [1, 1], "Epic with 1 of 2")
	check_eq([tab.cells[1].enchants, tab.cells[1].free_slots], [1, 0], "Rare with its one")
	check_eq([tab.cells[3].enchants, tab.cells[3].free_slots], [0, 0], "Common holds none")
	check_eq([tab.cells[4].enchants, tab.cells[4].free_slots], [0, 1], "an empty Uncommon has a free slot")
	# What the Enchanter cannot use is dimmed.
	check(tab.cells[3].modulate.a < 0.6, "the Common chest is dimmed")
	check(tab.cells[0].modulate.a > 0.9, "the Epic helm is not")
	check(tab.cells[2].modulate.a < 0.6, "nor is the plain starting sword (nothing to change on a Common)")


func test_the_label_shows_the_team_dust_even_while_hidden() -> void:
	var slot := _hero()
	var panel := _panel(slot, false)
	check_eq(panel.tab_text(PlayerPanel.ENCHANTER_TAB), "Enchanter (0)", "no Dust yet")
	check_eq(panel.enchanter.tab_label(), "Enchanter (0)", "the tab's own label")
	RunState.add_dust(12, 0, "x")
	check_eq(panel._tab_labels[PlayerPanel.ENCHANTER_TAB].text, "Enchanter (12)", "relabelled while the Character tab shows")
	check_eq(panel.active_tab, PlayerPanel.CHARACTER_TAB, "still on Character")
	RunState.try_spend_dust_for(5, 0, &"enchant", "x")
	check_eq(panel._tab_labels[PlayerPanel.ENCHANTER_TAB].text, "Enchanter (7)", "and on a spend")


func test_the_tab_follows_the_equipment() -> void:
	var slot := _hero()
	var helm := _item(Items.Rarity.EPIC, Items.SlotType.HEAD, [&"mighty"])
	_dress(slot, {Items.EquipSlot.HEAD: helm})
	var panel := _panel(slot)
	var tab := panel.enchanter
	check_eq(tab.items.size(), 1, "one item")
	var chest := _item(Items.Rarity.RARE, Items.SlotType.CHEST, [&"brutal"])
	_eq(slot).add_to_backpack(chest)
	check_eq(tab.items.size(), 2, "a new backpack item shows at once")
	check_eq(tab.selected_item(), helm, "the selection stays on its item")
	_eq(slot).backpack.erase(chest)
	_eq(slot).changed.emit()
	check_eq(tab.items.size(), 1, "and a sold one goes")


func test_a_hidden_tab_only_rebuilds_when_shown() -> void:
	var slot := _hero()
	var helm := _item(Items.Rarity.EPIC, Items.SlotType.HEAD, [&"mighty"])
	_dress(slot, {Items.EquipSlot.HEAD: helm})
	var panel := _panel(slot, false)
	var tab := panel.enchanter
	check(tab.items.is_empty(), "never shown: nothing built yet")
	_eq(slot).add_to_backpack(_item(Items.Rarity.RARE, Items.SlotType.CHEST, [&"brutal"]))
	check(tab.items.is_empty(), "equipment changes do not rebuild a hidden tab")
	check(tab._stale, "they only mark it stale")
	panel.set_tab(PlayerPanel.ENCHANTER_TAB)
	check_eq(tab.items.size(), 2, "showing it builds it")
	check(not tab._stale, "and clears the mark")


func test_the_cursor_stays_visible_on_a_dimmed_icon() -> void:
	var slot := _hero()
	var chest := _item(Items.Rarity.COMMON, Items.SlotType.CHEST)
	var helm := _item(Items.Rarity.EPIC, Items.SlotType.HEAD, [&"mighty"])
	_dress(slot, {Items.EquipSlot.HEAD: helm}, [chest])
	var panel := _panel(slot)
	var tab := panel.enchanter
	check(tab.cells[1].modulate.a < 0.6, "the Common chest is dimmed while nobody looks at it")
	tab.select_item(1)
	check(tab.cells[1].selected and tab.cells[1].modulate.a > 0.9, "the selected icon is bright even when dimmed otherwise")
	tab.select_item(0)
	check(tab.cells[1].modulate.a < 0.6, "and dims again when the cursor leaves")


func test_an_empty_hero_has_an_empty_tab() -> void:
	var slot := _hero()
	_dress(slot, {})
	var panel := _panel(slot)
	var tab := panel.enchanter
	check(tab.items.is_empty() and tab.selected_item() == null, "nothing to pick")
	check_eq(tab.detail_name.text, EnchanterTab.EMPTY_TEXT, "says so")
	_press(panel, slot, PlayerInput.Pad.A)
	check_eq(tab.focus, EnchanterTab.Focus.ITEMS, "A does nothing")
	check(not tab.move_item(Vector2i.RIGHT) and not tab.move_item(Vector2i.DOWN), "no movement")


# --- Navigation --------------------------------------------------------------------------------

func test_navigation_over_the_grid_and_into_the_enchants() -> void:
	var slot := _hero()
	var helm := _item(Items.Rarity.EPIC, Items.SlotType.HEAD, [&"mighty"])
	var ring := _item(Items.Rarity.RARE, Items.SlotType.RING, [&"blazing"])
	var sword := ItemInstance.from_weapon(Db.get_weapon(&"sword"))
	var chest := _item(Items.Rarity.COMMON, Items.SlotType.CHEST)
	var band := _item(Items.Rarity.UNCOMMON, Items.SlotType.RING)
	_dress(slot, {Items.EquipSlot.HEAD: helm, Items.EquipSlot.RING_1: ring, Items.EquipSlot.MAIN_HAND: sword}, [chest, band])
	var panel := _panel(slot)
	var tab := panel.enchanter
	check_eq(tab.grid_pos(0), Vector2i(0, 0), "the first equipped item")
	check_eq(tab.grid_pos(2), Vector2i(2, 0), "the third")
	check_eq(tab.grid_pos(3), Vector2i(0, 1), "the backpack starts on a new row")
	check_eq(tab.index_at(1, 1), 4, "index_at")
	check_eq(tab.index_at(4, 4), -1, "none out there")
	_dir(panel, slot, Vector2i.RIGHT)
	check_eq(tab.selected, 1, "right")
	_dir(panel, slot, Vector2i.RIGHT)
	check_eq(tab.selected, 2, "right again")
	_dir(panel, slot, Vector2i.DOWN)
	check_eq(tab.selected, 4, "down into the backpack row: the nearest column (2 -> the band at column 1)")
	_dir(panel, slot, Vector2i.UP)
	check_eq(tab.selected, 1, "up again: the nearest column of the equipped row (the ring at column 1)")
	_dir(panel, slot, Vector2i.LEFT)
	_dir(panel, slot, Vector2i.LEFT)
	_dir(panel, slot, Vector2i.LEFT)
	check_eq(tab.selected, 0, "left stops at the edge")
	_dir(panel, slot, Vector2i.UP)
	check_eq(tab.selected, 0, "up at the top does nothing")
	check_eq(tab.focus, EnchanterTab.Focus.ITEMS, "still on the items")
	# Right from the last item of the row (no cell right of it): into the enchants of a helm.
	_dress(slot, {Items.EquipSlot.HEAD: helm})
	tab.refresh()
	_dir(panel, slot, Vector2i.RIGHT)
	check_eq(tab.focus, EnchanterTab.Focus.ROWS, "right at the edge steps into the enchants")
	_dir(panel, slot, Vector2i.LEFT)
	check_eq(tab.focus, EnchanterTab.Focus.ITEMS, "left comes back")
	_press(panel, slot, PlayerInput.Pad.A)
	check_eq(tab.focus, EnchanterTab.Focus.ROWS, "A steps in too")
	_press(panel, slot, PlayerInput.Pad.B)
	check_eq(tab.focus, EnchanterTab.Focus.ITEMS, "B steps back")
	check(consumed, "and counts as used")


func test_b_on_the_items_is_not_consumed_so_the_market_can_unready() -> void:
	var parts := _simple()
	var panel: PlayerPanel = parts[1]
	var slot: PlayerSlot = parts[0]
	_press(panel, slot, PlayerInput.Pad.B)
	check(not consumed, "B on the items is the market's")


func test_rows_follow_the_selected_item() -> void:
	var slot := _hero()
	var helm := _item(Items.Rarity.EPIC, Items.SlotType.HEAD, [&"mighty"])
	var ring := _item(Items.Rarity.EPIC, Items.SlotType.RING, [&"blazing", &"zealous"], 2)
	var chest := _item(Items.Rarity.COMMON, Items.SlotType.CHEST)
	_dress(slot, {Items.EquipSlot.HEAD: helm, Items.EquipSlot.RING_1: ring}, [chest])
	var panel := _panel(slot)
	var tab := panel.enchanter
	check_eq(tab.rows.size(), 2, "the helm: its enchant and the Imbue row")
	check(not tab.rows[0].is_imbue() and tab.rows[1].is_imbue(), "the Imbue row comes last")
	check_eq(tab.rows[0].rank_label.text, "I", "rank I")
	check_eq(tab.rows[0].name_label.text, "Mighty", "the enchant's name")
	check(tab.rows[0].text_label.text.contains("Attack Power"), "its green text: %s" % tab.rows[0].text_label.text)
	_dir(panel, slot, Vector2i.RIGHT)
	check_eq(tab.rows.size(), 2, "the ring: two enchants, no free slot")
	check(not tab.rows[0].is_imbue() and not tab.rows[1].is_imbue(), "no Imbue row")
	check_eq(tab.rows[0].rank_label.text, "III", "rank III")
	_dir(panel, slot, Vector2i.DOWN)
	check_eq(tab.selected_item(), chest, "the Common chest")
	check(tab.rows.is_empty(), "no rows for a Common")
	check_eq(tab.item_reason(), Enchanter.REASON_COMMON, "the reason")
	check(tab.detail_hint.visible and tab.detail_hint.text == Enchanter.REASON_COMMON, "shown in red under the name")
	check(not tab._price_row.visible, "no price for nothing")


func test_a_common_item_and_an_artifact_explain_themselves() -> void:
	var slot := _hero()
	var chest := _item(Items.Rarity.COMMON, Items.SlotType.CHEST)
	var relic := _item(Items.Rarity.ARTIFACT, Items.SlotType.WEAPON, [&"blazing"], 2)
	_dress(slot, {Items.EquipSlot.MAIN_HAND: ItemInstance.from_weapon(Db.get_weapon(&"sword"))}, [chest, relic])
	var panel := _panel(slot)
	var tab := panel.enchanter
	tab.select_item(1)
	_press(panel, slot, PlayerInput.Pad.A)
	check_eq(tab.focus, EnchanterTab.Focus.ITEMS, "A on a Common stays on the items")
	check_eq(messages.back(), Enchanter.REASON_COMMON, "and says why")
	tab.select_item(2)
	check(tab.rows.is_empty(), "an Artifact has no rows")
	_press(panel, slot, PlayerInput.Pad.A)
	check_eq(messages.back(), Enchanter.REASON_ARTIFACT, "Artifacts are left alone")
	check(not tab.is_holding(), "no hold")


# --- Actions -----------------------------------------------------------------------------------

func test_a_empowers_and_pays_gold_and_dust() -> void:
	var parts := _simple()
	var slot: PlayerSlot = parts[0]
	var panel: PlayerPanel = parts[1]
	var helm: ItemInstance = parts[2]
	var tab := panel.enchanter
	_press(panel, slot, PlayerInput.Pad.A)
	check_eq(tab.focus, EnchanterTab.Focus.ROWS, "in the enchants")
	check_eq(tab.selected_enchant_index(), 0, "on Mighty")
	var gold := RunState.gold
	var dust := RunState.arcane_dust
	_press(panel, slot, PlayerInput.Pad.A)
	check_eq(helm.enchants[0].rank, 1, "rank II")
	check_eq(RunState.gold, gold - 48, "48 gold at wave 15")
	check_eq(RunState.arcane_dust, dust - 8, "8 Dust")
	check_eq(RunState.enchants_done, 1, "counted")
	check_eq(helm.enchant_uses, 1, "a use")
	check_eq(tab.rows[0].rank_label.text, "II", "the row shows it")
	check(messages.back().contains("Mighty is now Rank II"), "message: %s" % messages.back())
	check(panel.last_message.contains("Rank II"), "the panel's toast: %s" % panel.last_message)
	check_eq(RunState.spend_log.back()["kind"], &"enchant", "logged for the purse board")
	check_eq(tab.focus, EnchanterTab.Focus.ROWS, "still in the enchants")
	check_eq(tab.detail_gold.text, "96", "the next price doubled")
	check_eq(tab.detail_dust.text, "16", "Dust too")
	check_eq(tab.detail_uses.text, "Used 1x", "uses shown")
	check_near((slot.player as Player).stats.get_raw(Stats.ATTACK_POWER), 9.0, 0.001, "the hero's Attack Power follows (6 x 1.5)")


func test_x_rerolls_the_enchant_at_the_same_rank() -> void:
	var parts := _simple()
	var slot: PlayerSlot = parts[0]
	var panel: PlayerPanel = parts[1]
	var helm: ItemInstance = parts[2]
	helm.enchants[0].rank = 3
	panel.enchanter.refresh()
	_press(panel, slot, PlayerInput.Pad.A)
	_press(panel, slot, PlayerInput.Pad.X)
	check(helm.enchants[0].enchant.id != &"mighty", "a new enchant")
	check_eq(helm.enchants[0].rank, 3, "the same rank (IV)")
	check_eq(panel.enchanter.rows[0].rank_label.text, "IV", "the row")
	check(messages.back().contains("Mighty became "), "message: %s" % messages.back())
	check_eq(RunState.gold, 1000 - 48, "the same price as an Empower")


func test_the_imbue_row_adds_an_enchant() -> void:
	var parts := _simple()
	var slot: PlayerSlot = parts[0]
	var panel: PlayerPanel = parts[1]
	var helm: ItemInstance = parts[2]
	var tab := panel.enchanter
	_press(panel, slot, PlayerInput.Pad.A)
	_dir(panel, slot, Vector2i.DOWN)
	check(tab.selected_row().is_imbue(), "on the Imbue row")
	_press(panel, slot, PlayerInput.Pad.X)
	check_eq(helm.enchants.size(), 1, "X does nothing on the Imbue row")
	check(messages.back().contains("press A"), "it says so: %s" % messages.back())
	_press(panel, slot, PlayerInput.Pad.A)
	check_eq(helm.enchants.size(), 2, "a second enchant")
	check_eq(tab.rows.size(), 2, "two rows, no Imbue row any more")
	check_eq(tab.row_selected, 1, "the new enchant is selected")
	check(messages.back().contains("added"), "message: %s" % messages.back())


func test_refusals_show_their_reason_and_cost_nothing() -> void:
	var parts := _simple()
	var slot: PlayerSlot = parts[0]
	var panel: PlayerPanel = parts[1]
	var helm: ItemInstance = parts[2]
	var tab := panel.enchanter
	_press(panel, slot, PlayerInput.Pad.A)
	# Rank V: Empower refuses, Reroll still works.
	helm.enchants[0].rank = 4
	tab.refresh()
	_press(panel, slot, PlayerInput.Pad.A)
	check_eq(messages.back(), Enchanter.REASON_MAX_RANK, "Rank V is the top")
	check_eq(helm.enchants[0].rank, 4, "unchanged")
	check_eq(RunState.gold, 1000, "no gold spent")
	check(tab.detail_empower.text == Enchanter.REASON_MAX_RANK, "the preview line says it too: %s" % tab.detail_empower.text)
	# No Dust.
	helm.enchants[0].rank = 1
	tab.refresh()
	RunState.try_spend_dust_for(RunState.arcane_dust, 0, &"enchant", "all")
	_press(panel, slot, PlayerInput.Pad.A)
	check_eq(messages.back(), Enchanter.REASON_POOR_DUST, "no Dust")
	check(tab.detail_dust.get_theme_color(&"font_color") == UiTheme.RED, "the price shows red")
	# No gold either.
	RunState.try_spend(RunState.gold)
	_press(panel, slot, PlayerInput.Pad.X)
	check_eq(messages.back(), Enchanter.REASON_POOR_BOTH, "neither")
	check_eq(helm.enchant_uses, 0, "no use counted")
	check_eq(RunState.enchants_done, 0, "nothing done")


func test_the_preview_lines_show_the_next_rank_and_the_reroll() -> void:
	var parts := _simple()
	var slot: PlayerSlot = parts[0]
	var panel: PlayerPanel = parts[1]
	var helm: ItemInstance = parts[2]
	var tab := panel.enchanter
	check(not tab.detail_empower.visible, "no preview while on the items")
	_press(panel, slot, PlayerInput.Pad.A)
	check(tab.detail_empower.visible and tab.detail_reroll.visible, "both lines in the enchants")
	check(tab.detail_empower.text.begins_with("Empower to Rank II: "), "Empower: %s" % tab.detail_empower.text)
	check(tab.detail_empower.text.contains("9 Attack Power"), "with the next rank's number: %s" % tab.detail_empower.text)
	check(tab.detail_reroll.text.begins_with("Reroll: another enchant at Rank I"), "Reroll: %s" % tab.detail_reroll.text)
	_dir(panel, slot, Vector2i.DOWN)
	check(tab.detail_empower.text.begins_with("Imbue: a new random enchant at Rank "), "Imbue: %s" % tab.detail_empower.text)
	check(not tab.detail_reroll.visible, "no reroll line on the Imbue row")
	helm.enchants.append(EnchantRoll.new(Db.get_enchant(&"brutal"), 0))
	tab.refresh()
	check_eq(tab.rows.size(), 2, "full")


# --- The hold rule -------------------------------------------------------------------------------

func test_an_action_above_half_the_purse_needs_a_hold() -> void:
	var slot := _hero()
	var helm := _item(Items.Rarity.EPIC, Items.SlotType.HEAD, [&"mighty"])
	_dress(slot, {Items.EquipSlot.HEAD: helm})
	RunState.add_gold(80)
	RunState.add_dust(50, -1, "x")
	var panel := _panel(slot)
	var tab := panel.enchanter
	check(EnchanterTab.needs_hold(48), "48 is more than half of 80")
	check(not EnchanterTab.needs_hold(40), "40 is exactly half: no hold")
	_press(panel, slot, PlayerInput.Pad.A)
	check(Array(tab.prompt_spec()).any(func(p: Array) -> bool: return str(p[1]) == "Hold to empower"), "the prompt says hold")
	# A pressed and kept down starts the hold; nothing is paid yet.
	_hold(panel, slot, PlayerInput.Pad.A, 2.0 * DT)
	check(tab.is_holding() and tab.is_modal(), "a hold started: %s" % str(tab._hold))
	check_eq(helm.enchants[0].rank, 0, "nothing yet")
	check_eq(RunState.gold, 80, "no gold spent")
	# Held for about half the time, then let go: cancelled.
	_hold(panel, slot, PlayerInput.Pad.A, EnchanterTab.HOLD_TIME * 0.5)
	check(tab.hold_progress() > 0.3 and tab.hold_progress() < 0.7, "the row fills up: %.2f" % tab.hold_progress())
	check(tab.rows[0].hold_progress > 0.3, "the row shows the fill")
	_release(panel, slot, PlayerInput.Pad.A)
	check(not tab.is_holding(), "letting go cancels")
	check_eq(helm.enchants[0].rank, 0, "nothing happened")
	check_eq(RunState.gold, 80, "still no gold spent")
	check_eq(tab.rows[0].hold_progress, 0.0, "the fill is gone")
	# A full hold does it.
	_hold(panel, slot, PlayerInput.Pad.A, EnchanterTab.HOLD_TIME + 0.2)
	_release(panel, slot, PlayerInput.Pad.A)
	check_eq(helm.enchants[0].rank, 1, "empowered after the hold")
	check_eq(RunState.gold, 80 - 48, "paid")
	check(not tab.is_holding(), "the hold is over")


func test_a_cheap_action_needs_no_hold() -> void:
	var parts := _simple()
	var slot: PlayerSlot = parts[0]
	var panel: PlayerPanel = parts[1]
	_press(panel, slot, PlayerInput.Pad.A)
	_press(panel, slot, PlayerInput.Pad.A)
	check_eq((parts[2] as ItemInstance).enchants[0].rank, 1, "48 of 1000 gold: at once")
	check(not panel.enchanter.is_holding(), "no hold")


func test_b_and_moving_cancel_a_hold_and_lt_rt_wait_for_it() -> void:
	var slot := _hero()
	var helm := _item(Items.Rarity.EPIC, Items.SlotType.HEAD, [&"mighty"])
	_dress(slot, {Items.EquipSlot.HEAD: helm})
	RunState.add_gold(80)
	RunState.add_dust(50, -1, "x")
	var panel := _panel(slot)
	var tab := panel.enchanter
	_press(panel, slot, PlayerInput.Pad.A)
	_hold(panel, slot, PlayerInput.Pad.X, 2.0 * DT)
	check(tab.is_holding(), "a Reroll hold (X)")
	# LT / RT are the panel's only while no hold runs.
	_press(panel, slot, PlayerInput.Pad.RT)
	check_eq(panel.active_tab, PlayerPanel.ENCHANTER_TAB, "RT does not switch away during a hold")
	check(tab.is_holding(), "and the hold goes on")
	_release(panel, slot, PlayerInput.Pad.X)
	check(not tab.is_holding(), "letting go ends it")
	# B cancels a running hold, counts as used and keeps the focus on the enchants.
	_hold(panel, slot, PlayerInput.Pad.A, 2.0 * DT)
	check(tab.is_holding(), "a new hold")
	_press(panel, slot, PlayerInput.Pad.B)
	check(consumed, "the B that cancelled the hold counts as used")
	check(not tab.is_holding(), "B cancelled it")
	check_eq(tab.focus, EnchanterTab.Focus.ROWS, "but did not leave the enchants")
	_release(panel, slot, PlayerInput.Pad.A)
	# Moving cancels it too.
	_hold(panel, slot, PlayerInput.Pad.A, 2.0 * DT)
	check(tab.is_holding(), "hold again")
	_press(panel, slot, PlayerInput.Pad.DPAD_DOWN)
	check(not tab.is_holding(), "a direction cancels")
	_release(panel, slot, PlayerInput.Pad.A)
	check_eq(helm.enchants[0].rank, 0, "nothing was bought")
	check_eq(RunState.gold, 80, "no gold spent")
	# Without a hold LT / RT switch tabs again.
	_press(panel, slot, PlayerInput.Pad.RT)
	check_eq(panel.active_tab, PlayerPanel.CHARACTER_TAB, "RT: the Character tab")


func test_a_hold_that_became_unaffordable_is_dropped() -> void:
	var slot := _hero()
	var helm := _item(Items.Rarity.EPIC, Items.SlotType.HEAD, [&"mighty"])
	_dress(slot, {Items.EquipSlot.HEAD: helm})
	RunState.add_gold(80)
	RunState.add_dust(50, -1, "x")
	var panel := _panel(slot)
	var tab := panel.enchanter
	_press(panel, slot, PlayerInput.Pad.A)
	_hold(panel, slot, PlayerInput.Pad.A, 2.0 * DT)
	check(tab.is_holding(), "holding")
	RunState.try_spend(60)  # a teammate spent the gold
	check(not tab.is_holding(), "the wallet change dropped the hold")
	_release(panel, slot, PlayerInput.Pad.A)
	check_eq(helm.enchants[0].rank, 0, "nothing happened")


# --- Prompts and wiring ---------------------------------------------------------------------------

func test_prompts_follow_the_focus() -> void:
	var parts := _simple()
	var slot: PlayerSlot = parts[0]
	var panel: PlayerPanel = parts[1]
	var tab := panel.enchanter
	var texts := func(spec: Array) -> Array[String]:
		var out: Array[String] = []
		for pair: Array in spec:
			out.append(str(pair[1]))
		return out
	check_eq(texts.call(tab.prompt_spec()), ["Enchants", "Select"] as Array[String], "on the items")
	_press(panel, slot, PlayerInput.Pad.A)
	check_eq(texts.call(tab.prompt_spec()), ["Empower", "Reroll", "Select", "Back"] as Array[String], "on an enchant")
	_dir(panel, slot, Vector2i.DOWN)
	check_eq(texts.call(tab.prompt_spec()), ["Imbue", "Select", "Back"] as Array[String], "on the Imbue row")
	check_eq(panel._context_label.text, "Epic Head · Equipped", "the panel shows the context")
	_press(panel, slot, PlayerInput.Pad.B)
	# A Common item offers no "Enchants".
	tab.select_item(1)
	check_eq(texts.call(tab.prompt_spec()), ["Select"] as Array[String], "nothing to enter on a Common")


func test_a_hidden_tab_catches_up_when_shown() -> void:
	var slot := _hero()
	var helm := _item(Items.Rarity.EPIC, Items.SlotType.HEAD, [&"mighty"])
	_dress(slot, {Items.EquipSlot.HEAD: helm})
	RunState.add_gold(500)
	RunState.add_dust(50, -1, "x")
	var panel := _panel(slot, false)
	var tab := panel.enchanter
	check(not tab.visible, "hidden on the Character tab")
	RunState.add_gold(5)
	check(tab._stale, "a wallet change only marks it stale")
	panel.set_tab(PlayerPanel.ENCHANTER_TAB)
	check(not tab._stale, "showing it refreshed it")
	check_eq(tab.detail_gold.text, "48", "price")
	check(tab.detail_gold.get_theme_color(&"font_color") == UiTheme.GOLD, "affordable: gold")


func test_the_hero_leaving_the_tab_resets_focus_and_holds() -> void:
	var slot := _hero()
	var helm := _item(Items.Rarity.EPIC, Items.SlotType.HEAD, [&"mighty"])
	_dress(slot, {Items.EquipSlot.HEAD: helm})
	RunState.add_gold(80)
	RunState.add_dust(50, -1, "x")
	var panel := _panel(slot)
	var tab := panel.enchanter
	_press(panel, slot, PlayerInput.Pad.A)
	_hold(panel, slot, PlayerInput.Pad.A, 2.0 * DT)
	check(tab.is_holding(), "holding")
	panel.set_input_focus(false)
	check(not tab.is_holding(), "losing the focus drops the hold")
	panel.set_input_focus(true)
	check(tab.cells[0].selected, "the cursor shows with the focus")


func test_the_tab_is_wired_like_the_trainer_and_talents() -> void:
	var slot := _hero()
	var panel := _panel(slot)
	check(panel.enchanter != null and panel.enchanter.slot == slot, "the panel owns an EnchanterTab")
	check(panel.enchanter.visible and not panel.trainer.visible and not panel.talents.visible, "shown alone")
	check_eq(panel._prompt_holder.get_child_count(), 1, "the prompt row is built")
	check(panel.enchanter.is_connected(&"message", panel._on_enchanter_message), "messages reach the toast")
	check(panel.enchanter.is_connected(&"prompts_changed", panel._on_enchanter_prompts_changed), "prompts reach the row")


# --- Layout -----------------------------------------------------------------------------------------

## The tab never grows the panel and its content fits the area the panel's column gives it, with the
## fullest hero (15 equipped items and a full backpack, a long enchant text) – like the Talents tab.
func test_the_tab_fits_the_panel() -> void:
	_async = true
	var slot := _hero()
	var worn := {}
	var positions: Array = Items.EquipSlot.values()
	for i in positions.size():
		var item := _item(Items.Rarity.EPIC, Items.SlotType.RING, [&"blazing", &"mighty"], 4,
			"An Extremely Long Item Name For Testing %d" % i)
		item.enchant_uses = 12
		worn[positions[i]] = item
	var bag: Array[ItemInstance] = []
	for i in Items.BACKPACK_SIZE:
		bag.append(_item(Items.Rarity.UNCOMMON, Items.SlotType.RING, [], 0, "Bag %d" % i))
	_dress(slot, worn, bag)
	_rich(5000000, 5000)
	var panel := _panel(slot)
	panel.size = PlayerPanel.DESIGN_SIZE
	panel.refresh()
	check_eq(panel.enchanter.items.size(), 25, "15 equipped + 10 backpack")
	var min_size := panel.get_combined_minimum_size()
	check(min_size.x <= PlayerPanel.DESIGN_SIZE.x + 0.5 and min_size.y <= PlayerPanel.DESIGN_SIZE.y + 0.5,
		"the panel keeps its design size: %s" % min_size)
	var frame_min := panel.get_child(0).get_combined_minimum_size() as Vector2
	check(frame_min.x <= PlayerPanel.DESIGN_SIZE.x + 0.5 and frame_min.y <= PlayerPanel.DESIGN_SIZE.y + 0.5,
		"the frame's content fits the design size: %s" % frame_min)
	await tree.process_frame
	await tree.process_frame
	var tab := panel.enchanter
	var body := tab.get_node("Body") as Control
	var body_min := body.get_combined_minimum_size()
	check(tab.size.x > 0.0 and tab.size.y > 0.0, "laid out: %s" % tab.size)
	check(body_min.x <= tab.size.x + 0.5 and body_min.y <= tab.size.y + 0.5,
		"the tab's content fits its area: needs %s, gets %s" % [body_min, tab.size])
	var prompt_row := panel._prompt_holder.get_parent() as Control
	check(body.get_global_rect().end.y <= prompt_row.get_global_rect().position.y + 0.5,
		"the Body ends above the prompt row (%s / %s)" % [body.get_global_rect(), prompt_row.get_global_rect()])
	check(body.get_global_rect().end.x <= tab.get_global_rect().end.x + 0.5, "and inside the tab's width")
	# Every icon of the grid is inside the list panel, the rows and the price row inside the detail.
	var list := tab.get_node("Body/ItemList") as Control
	for c in tab.cells:
		check(list.get_global_rect().encloses(c.get_global_rect().grow(-0.5)), "icon %s inside the list: %s / %s" % [c.item.display_name, c.get_global_rect(), list.get_global_rect()])
	var detail := tab.get_node("Body/Detail") as Control
	check(detail.get_global_rect().encloses(tab._price_row.get_global_rect().grow(-0.5)),
		"the price row inside the detail: %s / %s" % [tab._price_row.get_global_rect(), detail.get_global_rect()])
	check(tab._price_row.get_global_rect().end.y <= detail.get_global_rect().end.y + 0.5, "price row above the bottom")
	# "Used 12x" and a five-digit gold / four-digit Dust price show whole in the price row.
	check_eq(tab.detail_uses.text, "Used 12x", "the uses")
	var uses_font := tab.detail_uses.get_theme_font_size(&"font_size")
	check(tab.detail_uses.get_theme_default_font().get_string_size(tab.detail_uses.text, HORIZONTAL_ALIGNMENT_LEFT, -1, uses_font).x
		<= tab.detail_uses.size.x + 0.5, "the uses text is not clipped: %s" % tab.detail_uses.size)
	# The widest texts: a 4-digit gold and a 3-digit Dust price fit the price row.
	check(tab._price_row.get_combined_minimum_size().x <= detail.size.x, "the price row fits its width")
	# In the enchants: both preview lines and rows stay inside the detail.
	tab.enter_rows()
	await tree.process_frame
	await tree.process_frame
	check(detail.get_global_rect().encloses(tab.detail_empower.get_global_rect().grow(-0.5)),
		"the Empower line inside the detail: %s / %s" % [tab.detail_empower.get_global_rect(), detail.get_global_rect()])
	check(detail.get_global_rect().encloses(tab.detail_reroll.get_global_rect().grow(-0.5)), "the Reroll line inside the detail")
	var holder := tab.get_node("Body/Detail").find_child("RowsHolder", true, false) as Control
	check(holder.size.y >= 2.0 * 60.0, "room for two enchant rows: %.1f" % holder.size.y)
	for r in tab.rows:
		check(holder.get_global_rect().encloses(r.get_global_rect().grow(-0.5)), "row inside its holder: %s / %s" % [r.get_global_rect(), holder.get_global_rect()])
	finished.emit()


## Four panels in the market layout at 1920 x 1080 (1280 x 720 is the same canvas scaled), all on the
## Enchanter tab: their body text stays readable at 720p and no panel reaches the header.
func test_four_panels_on_the_enchanter_tab_fit_at_1080p_and_720p() -> void:
	_async = true
	_root_size = tree.root.size
	tree.root.size = Vector2i(1920, 1080)
	await tree.process_frame
	var holder := Control.new()
	holder.size = Vector2(1920, 1080)
	tree.root.add_child(holder)
	var screen := Intermission.create()
	holder.add_child(screen)
	var world := MarketFakes.make_world(tree)
	for i in 4:
		MarketFakes.human_with_hero(world, "pad:%d" % i, Db.class_ids[i % Db.class_ids.size()])
		var eq := _eq(PlayerManager.get_slot(i))
		eq.slots[Items.EquipSlot.HEAD] = _item(Items.Rarity.EPIC, Items.SlotType.HEAD, [&"mighty", &"zealous"], 4)
		eq.slots[Items.EquipSlot.RING_1] = _item(Items.Rarity.UNCOMMON, Items.SlotType.RING)
	RunState.set_start_level(20)
	RunState.add_gold(8000)
	RunState.add_dust(120, -1, "x")
	screen.open(15, 0)
	MarketFakes.poll_all(DT)
	screen._process(DT)
	MarketFakes.poll_all(Intermission.MARKET_INPUT_LOCKOUT)
	screen._process(Intermission.MARKET_INPUT_LOCKOUT)
	for i in 4:
		screen.panels[i].set_tab(PlayerPanel.ENCHANTER_TAB)
	await tree.process_frame
	await tree.process_frame
	var head := screen.header.get_global_rect()
	var scale_factor := Intermission.panel_scale(PlayerPanel.DESIGN_SIZE)
	for i in 4:
		var p := screen.panels[i]
		check_eq(p.active_tab, PlayerPanel.ENCHANTER_TAB, "P%d on the Enchanter tab" % (i + 1))
		var r := p.get_global_rect()
		var visual := Rect2(r.position, r.size * p.scale)
		check(not visual.intersects(head), "P%d's panel clears the header (%s / %s)" % [i + 1, visual, head])
		check(Rect2(Vector2.ZERO, Vector2(1920, 1080)).encloses(visual), "P%d's panel is on screen: %s" % [i + 1, visual])
		var tab := p.enchanter
		var body := tab.get_node("Body") as Control
		check(body.get_combined_minimum_size().x <= tab.size.x + 0.5 and body.get_combined_minimum_size().y <= tab.size.y + 0.5,
			"P%d: the content fits: %s / %s" % [i + 1, body.get_combined_minimum_size(), tab.size])
		# Readability at 1280 x 720: 4-player panel scale x the canvas scale 2/3 x the font size.
		for label: Label in _labels_of(tab):
			if not label.visible or label.text == "":
				continue
			var fs := label.get_theme_font_size(&"font_size")
			check(float(fs) * scale_factor * 0.667 >= 7.5, "'%s' (%d px) stays readable at 720p" % [label.text, fs])
	check(screen.purse_board.dust_value.text == "120", "the purse board shows the Dust: %s" % screen.purse_board.dust_value.text)
	UiFakes.free_node(holder)
	UiFakes.free_node(world)
	finished.emit()


func _labels_of(node: Node) -> Array[Label]:
	var out: Array[Label] = []
	for c in node.find_children("*", "Label", true, false):
		out.append(c as Label)
	return out


# --- Purse board -------------------------------------------------------------------------------------

func test_the_purse_board_shows_the_dust_next_to_the_gold() -> void:
	var board := PurseBoard.create()
	tree.root.add_child(board)
	board.refresh()
	check_eq(board.dust_value.text, "0", "no Dust yet")
	check(board.dust_icon.dim, "the sparkle is dimmed at 0")
	check(board.gold_value.get_parent() == board.dust_value.get_parent(), "in the gold's row")
	RunState.add_dust(37, -1, "x")
	check_eq(board.dust_value.text, "37", "follows dust_changed at once")
	check(not board.dust_icon.dim, "bright with Dust")
	RunState.try_spend_dust_for(7, 0, &"enchant", "x")
	check_eq(board.dust_value.text, "30", "and a spend")
	RunState.add_dust(1234, -1, "x")
	check_eq(board.dust_value.text, "1,264", "thousands separated like the gold")
	var handler := board._on_dust_changed
	UiFakes.free_node(board)
	check(not RunState.dust_changed.is_connected(handler), "disconnected when the board leaves the tree")


func test_the_ticker_lists_an_enchanter_action_with_its_dust() -> void:
	var slot := _hero()
	var ring := _item(Items.Rarity.EPIC, Items.SlotType.RING, [&"blazing"], 1)
	_dress(slot, {Items.EquipSlot.RING_1: ring})
	_rich()
	RunState.begin_spend_round()
	check(Enchanter.perform(_eq(slot), slot.index, ring, Enchanter.Action.EMPOWER, 0).ok, "empowered")
	check_eq(PurseBoard.entry_text(RunState.spend_log[0]), "P1 Empower Blazing (8 Dust) 48", "the ticker text names the Dust")


# --- Bots --------------------------------------------------------------------------------------------

## An Intermission, a bot hero with an Epic sword (one enchant, wave 12 prices) and [param spares] Epic
## cloth pieces in the backpack (no upgrades for a warrior in plate).
func _bot_smith(spares: int) -> Array:
	var world := MarketFakes.make_world(tree)
	var screen := Intermission.create()
	tree.root.add_child(screen)
	MarketFakes.bot_with_hero(world, "bot:smith", &"warrior")
	var slot := PlayerManager.get_slot(0)
	var eq := _eq(slot)
	var weapon := Support.make_weapon(&"sword", Items.Rarity.EPIC)
	weapon.wave = 12
	weapon.buy_price = ItemGenerator.price_for(Items.Rarity.EPIC, 12)
	weapon.enchants.append(EnchantRoll.new(Db.get_enchant(&"brutal"), 0))
	eq.slots.clear()
	eq.slots[Items.EquipSlot.MAIN_HAND] = weapon
	eq.slots[Items.EquipSlot.CHEST] = Support.make_armor(500, ClassData.ArmorType.PLATE, 20, Items.Rarity.EPIC, Items.SlotType.CHEST)
	for i in spares:
		eq.backpack.append(Support.make_armor(1, ClassData.ArmorType.CLOTH, 20, Items.Rarity.EPIC, Items.SlotType.CHEST))
	RunState.wave = 12
	return [screen, slot, weapon, world]


func _free_smith(parts: Array) -> void:
	UiFakes.free_node(parts[0])
	UiFakes.free_node(parts[3])


func test_bots_enchant_from_wave_12_with_the_gold_above_their_reserve() -> void:
	var parts := _bot_smith(3)
	var screen: Intermission = parts[0]
	var slot: PlayerSlot = parts[1]
	var weapon: ItemInstance = parts[2]
	var reserve := Intermission.bot_train_reserve(12, 1)
	RunState.add_gold(reserve + 500)
	screen.cleared_wave = 11
	check_eq(screen._bots_enchant(), 0, "not before wave 12")
	check_eq(RunState.enchants_done, 0, "nothing done")
	check_eq(_eq(slot).backpack.size(), 3, "no spare thrown away before it matters")
	screen.cleared_wave = 12
	var done := screen._bots_enchant()
	check_eq(done, Enchanter.BOT_MAX_ACTIONS, "two actions on the best weapon")
	check_eq(RunState.enchants_done, done, "counted")
	check_eq(weapon.enchant_uses, done, "all on the best weapon")
	check_eq(weapon.enchants.size(), 2, "Imbue filled the free slot first")
	check(weapon.enchants[0].rank == 1 or weapon.enchants[1].rank == 1, "then an Empower")
	check(RunState.gold >= reserve, "the reserve is kept: %d >= %d" % [RunState.gold, reserve])
	check(RunState.gold_spent > 0, "gold went through the purse")
	check(RunState.dust_spent > 0 and RunState.dust_earned >= RunState.dust_spent, "Dust came from the spares: %d / %d" % [RunState.dust_spent, RunState.dust_earned])
	check(_eq(slot).backpack.size() < 3, "spare items were disenchanted")
	for e: Dictionary in RunState.spend_log:
		check_eq(e["kind"], &"enchant", "logged as enchant")
	_free_smith(parts)


func test_bots_enchant_nothing_when_the_wallet_is_at_the_reserve() -> void:
	var parts := _bot_smith(3)
	var screen: Intermission = parts[0]
	screen.cleared_wave = 12
	RunState.add_gold(Intermission.bot_train_reserve(12, 1))
	RunState.add_dust(100, -1, "x")
	check_eq(screen._bots_enchant(), 0, "the reserve is not touched")
	check_eq(RunState.enchants_done, 0, "nothing done")
	check_eq(RunState.dust_spent, 0, "no Dust spent")
	_free_smith(parts)


func test_bots_do_not_touch_human_heroes() -> void:
	var parts := _bot_smith(2)
	var screen: Intermission = parts[0]
	var world: Node3D = parts[3]
	MarketFakes.human_with_hero(world, "pad:human", &"mage")
	var human := PlayerManager.get_slot(1)
	var staff := Support.make_weapon(&"wand", Items.Rarity.EPIC)
	_eq(human).slots[Items.EquipSlot.MAIN_HAND] = staff
	screen.cleared_wave = 12
	RunState.add_gold(2000)
	RunState.add_dust(100, -1, "x")
	check(screen._bots_enchant() > 0, "the bot enchanted")
	check_eq(staff.enchant_uses, 0, "a human's items are left to the human")
	_free_smith(parts)
