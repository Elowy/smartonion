extends TestCase
## PlayerPanel: navigation, the action menu flows (equip / unequip / sell / trade) driven
## through handle_input with ScriptedInput, strict proficiency, comparison toggle, refresh on
## equipment.changed and the compact stat list.

const UiFakes := preload("res://tests/ui_fakes.gd")
const Items_ := preload("res://tests/test_ui_items.gd")

var players: Array[Player] = []
var panels: Array[PlayerPanel] = []
var traded: Array = []
var sold: Array = []


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(2, 9)
	players.clear()
	panels.clear()
	traded.clear()
	sold.clear()


func after_each() -> void:
	for panel in panels:
		UiFakes.free_node(panel)
	for p in players:
		if is_instance_valid(p):
			p.free()
	panels.clear()
	players.clear()
	UiFakes.reset_players()


func _join(class_id: StringName) -> PlayerSlot:
	var input := ScriptedInput.new("panel:%d" % PlayerManager.count())
	var slot := PlayerManager.join(input, Db.get_class_data(class_id))
	players.append(Player.create(slot))
	return slot


func _panel(slot: PlayerSlot) -> PlayerPanel:
	var panel := PlayerPanel.create(slot)
	tree.root.add_child(panel)
	panel.set_input_focus(true)
	panel.trade_done.connect(func(item: ItemInstance, to: int) -> void: traded.append([item, to]))
	panel.item_sold.connect(func(item: ItemInstance, gold: int) -> void: sold.append([item, gold]))
	panels.append(panel)
	return panel


func _eq(slot: PlayerSlot) -> Equipment:
	return (slot.player as Player).equipment


## One frame with [param button] pressed, then one with it released (edges like a real pad).
func _tap(panel: PlayerPanel, slot: PlayerSlot, button: PlayerInput.Pad) -> void:
	var input := slot.input as ScriptedInput
	input.press(button)
	input.poll(1.0 / 60.0)
	panel.handle_input(input)
	input.release(button)
	input.poll(0.0)
	panel.handle_input(input)


func _nav(panel: PlayerPanel, slot: PlayerSlot, dir: Vector2i) -> void:
	var button := PlayerInput.Pad.DPAD_RIGHT
	if dir.x < 0:
		button = PlayerInput.Pad.DPAD_LEFT
	elif dir.y < 0:
		button = PlayerInput.Pad.DPAD_UP
	elif dir.y > 0:
		button = PlayerInput.Pad.DPAD_DOWN
	_tap(panel, slot, button)


func _helm(name: String, armor_type: int, strength: float) -> ItemInstance:
	return Items_.armor(name, Items.SlotType.HEAD, armor_type, 1, {"strength": strength, "stamina": 2})


# --- Navigation ------------------------------------------------------------------------------

func test_navigation_moves_through_doll_and_backpack() -> void:
	var slot := _join(&"warrior")
	var panel := _panel(slot)
	check_eq(panel.selected_equip_slot(), Items.EquipSlot.MAIN_HAND, "starts on the main hand with an empty backpack")
	panel.select_equip_slot(Items.EquipSlot.HEAD)
	_nav(panel, slot, Vector2i.DOWN)
	check_eq(panel.selected_equip_slot(), Items.EquipSlot.NECK, "down the left column")
	for i in 3:
		_nav(panel, slot, Vector2i.DOWN)
	check_eq(panel.selected_equip_slot(), Items.EquipSlot.WRIST, "bottom of the left column")
	_nav(panel, slot, Vector2i.DOWN)
	check_eq(panel.selected_equip_slot(), Items.EquipSlot.RING_1, "into the bottom row")
	_nav(panel, slot, Vector2i.RIGHT)
	_nav(panel, slot, Vector2i.RIGHT)
	check_eq(panel.selected_equip_slot(), Items.EquipSlot.MAIN_HAND, "rings then weapons")
	_nav(panel, slot, Vector2i.RIGHT)
	_nav(panel, slot, Vector2i.RIGHT)
	_nav(panel, slot, Vector2i.RIGHT)
	check_eq(panel.selected_equip_slot(), Items.EquipSlot.TRINKET_2, "trinkets at the end of the row")
	_nav(panel, slot, Vector2i.RIGHT)
	check_eq(panel.selected_bag_index(), 5, "on into the backpack's second row")
	_nav(panel, slot, Vector2i.UP)
	check_eq(panel.selected_bag_index(), 0, "backpack grid up")
	_nav(panel, slot, Vector2i.RIGHT)
	check_eq(panel.selected_bag_index(), 1, "backpack grid right")
	_nav(panel, slot, Vector2i.LEFT)
	_nav(panel, slot, Vector2i.LEFT)
	check_eq(panel.selected_equip_slot(), Items.EquipSlot.TRINKET_2, "left from the backpack back to the doll")
	panel.select_equip_slot(Items.EquipSlot.FEET)
	_nav(panel, slot, Vector2i.RIGHT)
	check_eq(panel.selected_bag_index(), 0, "right column -> first backpack cell")
	panel.select_equip_slot(Items.EquipSlot.HEAD)
	_nav(panel, slot, Vector2i.RIGHT)
	check_eq(panel.selected_equip_slot(), Items.EquipSlot.HANDS, "across to the right column")
	_nav(panel, slot, Vector2i.RIGHT)
	check(panel.selected_bag_index() >= 0, "right of the doll is the backpack")
	panel.select_equip_slot(Items.EquipSlot.HEAD)
	_nav(panel, slot, Vector2i.LEFT)
	_nav(panel, slot, Vector2i.UP)
	check_eq(panel.selected_equip_slot(), Items.EquipSlot.HEAD, "edges stop the cursor")


func test_backpack_starts_selected_and_focus_shows_tooltip() -> void:
	var slot := _join(&"warrior")
	var helm := _helm("Iron Helm", ClassData.ArmorType.PLATE, 3)
	_eq(slot).add_to_backpack(helm)
	var panel := PlayerPanel.create(slot)
	tree.root.add_child(panel)
	panels.append(panel)
	check_eq(panel.selected_bag_index(), 0, "first backpack item preselected")
	check(not panel.tooltip.visible, "no tooltip without input focus")
	check(not panel.icon_for_bag_index(0).selected, "no cursor without focus")
	panel.set_input_focus(true)
	check(panel.tooltip.visible and panel.tooltip.item == helm, "tooltip for the selected item")
	check(panel.icon_for_bag_index(0).selected, "cursor shown")
	check_eq(panel.icon_for_bag_index(0).badge, 1, "upgrade badge on an empty-slot item")
	panel.select_equip_slot(Items.EquipSlot.HEAD)
	check(not panel.tooltip.visible, "empty slot: no tooltip")
	panel.set_input_focus(false)
	check(not panel.icon_for_equip_slot(Items.EquipSlot.HEAD).selected, "focus lost hides the cursor")


# --- Equip / unequip --------------------------------------------------------------------------

func test_equip_from_backpack() -> void:
	var slot := _join(&"warrior")
	var panel := _panel(slot)
	var eq := _eq(slot)
	var old := _helm("Old Helm", ClassData.ArmorType.PLATE, 2)
	var new := _helm("New Helm", ClassData.ArmorType.PLATE, 6)
	eq.add_to_backpack(old)
	eq.add_to_backpack(new)
	check(panel.icon_for_bag_index(1).item == new, "refresh on equipment.changed")
	panel.select_backpack(0)
	_tap(panel, slot, PlayerInput.Pad.A)
	check(panel.is_menu_open(), "A opens the action menu")
	check_eq(panel.menu_labels(), PackedStringArray(["Equip", "Sell", "Cancel"]), "solo: no Trade")
	check_eq(panel.menu_index(), 0, "cursor on Equip")
	_tap(panel, slot, PlayerInput.Pad.A)
	check(eq.get_item(Items.EquipSlot.HEAD) == old, "equipped")
	check(not panel.is_menu_open(), "menu closed")
	check("Equipped Old Helm" in panel.last_message, "message: %s" % panel.last_message)
	check(panel.icon_for_equip_slot(Items.EquipSlot.HEAD).item == old, "paper doll updated")
	check_eq(eq.backpack.size(), 1, "one left in the backpack")
	# Equipping the better helm swaps the old one back into the backpack.
	panel.select_backpack(0)
	_tap(panel, slot, PlayerInput.Pad.A)
	_tap(panel, slot, PlayerInput.Pad.A)
	check(eq.get_item(Items.EquipSlot.HEAD) == new, "swapped")
	check(eq.backpack == [old], "displaced item back in the backpack")
	check_eq((slot.player as Player).stats.get_raw(Stats.STRENGTH), 6.0, "player stats follow")


func test_ring_equip_asks_for_the_slot() -> void:
	var slot := _join(&"rogue")
	var panel := _panel(slot)
	var eq := _eq(slot)
	var first := Items_.armor("Band A", Items.SlotType.RING, Items.NO_ARMOR, 1, {"agility": 2})
	var second := Items_.armor("Band B", Items.SlotType.RING, Items.NO_ARMOR, 2, {"agility": 4})
	eq.equip(first, Items.EquipSlot.RING_1)
	eq.add_to_backpack(second)
	panel.select_backpack(0)
	_tap(panel, slot, PlayerInput.Pad.A)
	_tap(panel, slot, PlayerInput.Pad.A)
	check_eq(panel.menu_labels(), PackedStringArray(["Ring 1", "Ring 2"]), "choose the ring slot")
	_tap(panel, slot, PlayerInput.Pad.B)
	check_eq(panel.menu_labels(), PackedStringArray(["Equip", "Sell", "Cancel"]), "B goes back one level")
	_tap(panel, slot, PlayerInput.Pad.A)
	_nav(panel, slot, Vector2i.DOWN)
	_tap(panel, slot, PlayerInput.Pad.A)
	check(eq.get_item(Items.EquipSlot.RING_2) == second, "equipped into Ring 2")
	check(eq.get_item(Items.EquipSlot.RING_1) == first, "Ring 1 untouched")
	check(not panel.is_menu_open(), "closed after equipping")


func test_unequip_needs_backpack_space() -> void:
	var slot := _join(&"warrior")
	var panel := _panel(slot)
	var eq := _eq(slot)
	var helm := _helm("Helm", ClassData.ArmorType.PLATE, 3)
	eq.equip(helm)
	panel.select_equip_slot(Items.EquipSlot.HEAD)
	_tap(panel, slot, PlayerInput.Pad.A)
	check_eq(panel.menu_labels(), PackedStringArray(["Unequip", "Cancel"]), "equipped item menu")
	_tap(panel, slot, PlayerInput.Pad.A)
	check(eq.get_item(Items.EquipSlot.HEAD) == null and eq.backpack == [helm], "unequipped to the backpack")
	eq.equip(helm)
	for i in Items.BACKPACK_SIZE:
		eq.add_to_backpack(_helm("Filler %d" % i, ClassData.ArmorType.CLOTH, 1))
	_tap(panel, slot, PlayerInput.Pad.A)
	check(not panel.menu_entry_enabled("Unequip"), "Unequip disabled with a full backpack")
	_tap(panel, slot, PlayerInput.Pad.A)
	check(eq.get_item(Items.EquipSlot.HEAD) == helm, "still equipped")
	check("full" in panel.last_message, "reason shown: %s" % panel.last_message)
	var input := slot.input as ScriptedInput
	input.press(PlayerInput.Pad.B)
	input.poll(1.0 / 60.0)
	panel.handle_input(input)
	check(not panel.is_menu_open(), "B closes the menu")
	check(panel.last_input_consumed, "and is used by the panel")
	input.release(PlayerInput.Pad.B)
	input.poll(0.0)
	input.press(PlayerInput.Pad.B)
	input.poll(1.0 / 60.0)
	panel.handle_input(input)
	check(not panel.last_input_consumed, "B without a menu is left to the owner (unready)")
	input.release(PlayerInput.Pad.B)
	input.poll(0.0)


func test_unusable_item_cannot_be_equipped() -> void:
	var slot := _join(&"mage")
	var panel := _panel(slot)
	var eq := _eq(slot)
	var plate := _helm("Plate Helm", ClassData.ArmorType.PLATE, 8)
	eq.add_to_backpack(plate)
	check(panel.icon_for_bag_index(0).unusable, "red tint")
	check_eq(panel.icon_for_bag_index(0).badge, 0, "no upgrade badge on unusable items")
	panel.select_backpack(0)
	_tap(panel, slot, PlayerInput.Pad.A)
	check(not panel.menu_entry_enabled("Equip"), "Equip greyed out")
	_tap(panel, slot, PlayerInput.Pad.A)
	check(eq.get_item(Items.EquipSlot.HEAD) == null, "not equipped")
	check(eq.backpack.has(plate), "still in the backpack")
	check("Cannot wear Plate" in panel.last_message, "reason: %s" % panel.last_message)
	var axe := ItemInstance.from_weapon(Db.get_weapon(&"two_hand_axe"))
	eq.add_to_backpack(axe)
	check(panel.icon_for_bag_index(1).unusable, "weapon proficiency too")


# --- Sell / trade -----------------------------------------------------------------------------

func test_sell_adds_gold() -> void:
	var slot := _join(&"warrior")
	var panel := _panel(slot)
	var eq := _eq(slot)
	var helm := _helm("Helm", ClassData.ArmorType.PLATE, 3)
	helm.buy_price = 40
	eq.add_to_backpack(helm)
	panel.select_backpack(0)
	_tap(panel, slot, PlayerInput.Pad.A)
	_nav(panel, slot, Vector2i.DOWN)
	check_eq(panel.menu_labels()[panel.menu_index()], "Sell", "cursor on Sell")
	_tap(panel, slot, PlayerInput.Pad.A)
	var value := roundi(40 * Items.SELL_SHARE)
	check_eq(RunState.gold, value, "35% of the price to the shared wallet")
	check(eq.backpack.is_empty(), "sold item gone")
	check_eq(panel.last_message, "+%d gold" % value, "+N gold message")
	check_eq(sold.size(), 1, "item_sold emitted")
	# X opens the menu right on Sell.
	var ring := Items_.armor("Ring", Items.SlotType.RING, Items.NO_ARMOR, 0, {"crit": 1})
	ring.buy_price = 20
	eq.add_to_backpack(ring)
	panel.select_backpack(0)
	_tap(panel, slot, PlayerInput.Pad.X)
	check(panel.is_menu_open() and panel.menu_labels()[panel.menu_index()] == "Sell", "X = sell shortcut")
	_tap(panel, slot, PlayerInput.Pad.A)
	check_eq(RunState.gold, value + 7, "second sale")


func test_trade_to_teammate() -> void:
	var giver := _join(&"warrior")
	var taker := _join(&"mage")
	var panel := _panel(giver)
	var other_panel := _panel(taker)
	other_panel.set_input_focus(false)
	var robe := Items_.armor("Silk Robe", Items.SlotType.CHEST, ClassData.ArmorType.CLOTH, 2, {"intellect": 6})
	_eq(giver).add_to_backpack(robe)
	panel.select_backpack(0)
	_tap(panel, giver, PlayerInput.Pad.A)
	check_eq(panel.menu_labels(), PackedStringArray(["Equip", "Sell", "Trade", "Cancel"]), "Trade offered with a teammate")
	check(panel.select_menu_entry("Trade"), "trade entry")
	_tap(panel, giver, PlayerInput.Pad.A)
	check_eq(panel.menu_labels(), PackedStringArray(["P2"]), "teammates listed")
	_tap(panel, giver, PlayerInput.Pad.A)
	check(not _eq(giver).backpack.has(robe), "left the giver's backpack")
	check(_eq(taker).backpack.has(robe), "in the teammate's backpack")
	check_eq(traded.size(), 1, "trade_done emitted")
	check(traded.size() == 1 and traded[0][0] == robe and traded[0][1] == 1, "with the item and slot index")
	check_eq(other_panel.last_message, "P1 gave you Silk Robe", "the receiver is told")
	check(other_panel.icon_for_bag_index(0).item == robe, "receiver's panel refreshed")
	check(not panel.is_menu_open(), "menu closed")


func test_trade_to_full_backpack_is_refused() -> void:
	var giver := _join(&"warrior")
	var taker := _join(&"rogue")
	var panel := _panel(giver)
	for i in Items.BACKPACK_SIZE:
		_eq(taker).add_to_backpack(_helm("Junk %d" % i, ClassData.ArmorType.CLOTH, 1))
	var helm := _helm("Helm", ClassData.ArmorType.PLATE, 4)
	_eq(giver).add_to_backpack(helm)
	panel.select_backpack(0)
	_tap(panel, giver, PlayerInput.Pad.A)
	panel.select_menu_entry("Trade")
	_tap(panel, giver, PlayerInput.Pad.A)
	check(not panel.menu_entry_enabled("P2"), "full teammate greyed out")
	_tap(panel, giver, PlayerInput.Pad.A)
	check(_eq(giver).backpack.has(helm), "item stays")
	check_eq(_eq(taker).backpack.size(), Items.BACKPACK_SIZE, "nothing added")
	check_eq(traded.size(), 0, "no trade")
	check("full" in panel.last_message, "reason: %s" % panel.last_message)


# --- Misc --------------------------------------------------------------------------------------

func test_y_toggles_comparison_and_tabs_are_locked() -> void:
	var slot := _join(&"warrior")
	var panel := _panel(slot)
	var eq := _eq(slot)
	eq.equip(_helm("Worn Helm", ClassData.ArmorType.PLATE, 1))
	eq.add_to_backpack(_helm("Better Helm", ClassData.ArmorType.PLATE, 5))
	panel.select_backpack(0)
	check(panel.tooltip.find_line("If you replace this item:") != null, "comparison shown by default")
	check(panel.tooltip.find_line("+4 Strength") != null, "delta vs the equipped helm")
	_tap(panel, slot, PlayerInput.Pad.Y)
	check(not panel.comparison, "Y toggles off")
	check(panel.tooltip.find_line("If you replace this item:") == null, "comparison hidden")
	_tap(panel, slot, PlayerInput.Pad.Y)
	check(panel.tooltip.find_line("If you replace this item:") != null, "and back on")
	_tap(panel, slot, PlayerInput.Pad.RT)
	check_eq(panel.last_message, "Trainer: coming soon", "locked tab")
	_tap(panel, slot, PlayerInput.Pad.LT)
	check_eq(panel.last_message, "Talents: coming soon", "wraps to Talents")
	check_eq(panel.active_tab, 0, "stays on Character")


func test_stat_rows_and_header() -> void:
	var slot := _join(&"rogue")
	var panel := _panel(slot)
	var player := slot.player as Player
	var rows := PlayerPanel.stat_rows(player.stats, slot.class_data)
	check_eq(rows[0][0], Stats.AGILITY, "class primary stat first")
	check_eq(rows[1][0], &"max_hp", "Max HP")
	check_eq(rows[1][1], player.max_hp(), "Max HP value")
	var ids: Array = rows.map(func(r: Array) -> StringName: return r[0])
	for stat in [Stats.ARMOR, Stats.CRIT, Stats.HASTE, Stats.VERSATILITY, Stats.DODGE]:
		check(stat in ids, "%s listed" % stat)
	check(Stats.STAMINA not in ids, "Stamina shown as Max HP")
	player.stats.set_source(&"test", {Stats.THORNS: 3.0, Stats.SPELL_POWER: 2.0, Stats.PIERCE: 1.0,
		Stats.FIRE_DAMAGE: 5.0, Stats.SLAYER: 4.0, Stats.XP_GAIN: 2.0, Stats.LEECH: 1.0})
	rows = PlayerPanel.stat_rows(player.stats, slot.class_data)
	ids = rows.map(func(r: Array) -> StringName: return r[0])
	check(Stats.THORNS in ids, "non-zero exotic stats listed")
	check(rows.size() <= PlayerPanel.MAX_STAT_ROWS * 2, "capped so the panel keeps its size")
	panel.refresh()
	var needed := panel.get_child(0).get_combined_minimum_size() as Vector2
	check(needed.x <= PlayerPanel.DESIGN_SIZE.x + 0.5 and needed.y <= PlayerPanel.DESIGN_SIZE.y + 0.5,
		"a full stat list still fits the design size: %s" % needed)
	check_eq(panel._class_label.text, "Rogue", "class in the header")
	check_eq(panel._ilvl_value.text, "13", "Avg. Item Level of two common wave-1 daggers")
