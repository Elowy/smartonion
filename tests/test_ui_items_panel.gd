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
var _async := false
## The headless root's size while a test runs on a 1920 x 1080 root (restored in after_each).
var _root_size := Vector2i.ZERO


func is_async() -> bool:
	return _async


func before_each() -> void:
	_async = false
	UiFakes.reset_players()
	RunState.start_run(2, 9)
	players.clear()
	panels.clear()
	traded.clear()
	sold.clear()


func after_each() -> void:
	if _root_size != Vector2i.ZERO:
		tree.root.size = _root_size
		_root_size = Vector2i.ZERO
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


## Between waves the tooltip stays over the panel on the half away from the selection – where
## the action menu opens too: the menu (Forge, Unequip …) must not sit under the tooltip.
func test_action_menu_hides_the_tooltip() -> void:
	var slot := _join(&"warrior")
	var helm := _helm("Iron Helm", ClassData.ArmorType.PLATE, 3)
	_eq(slot).add_to_backpack(helm)
	var panel := _panel(slot)
	panel.tooltip_inside = true
	panel.select_backpack(0)
	check(panel.tooltip.visible, "browsing: the tooltip shows")
	_tap(panel, slot, PlayerInput.Pad.A)
	check(panel.is_menu_open(), "A opens the action menu")
	check(not panel.tooltip.visible, "the tooltip hides while the menu is open")
	_nav(panel, slot, Vector2i.DOWN)
	check(not panel.tooltip.visible, "and stays hidden while the menu cursor moves")
	_tap(panel, slot, PlayerInput.Pad.B)
	check(not panel.is_menu_open(), "B closes the menu")
	check(panel.tooltip.visible and panel.tooltip.item == helm, "the tooltip is back")
	# An equipped weapon's menu (Unequip / Forge) likewise; X (Sell) on a backpack item too.
	panel.select_equip_slot(Items.EquipSlot.MAIN_HAND)
	check(panel.tooltip.visible, "the main hand's tooltip")
	_tap(panel, slot, PlayerInput.Pad.A)
	check(panel.is_menu_open() and "Forge" in panel.menu_labels(), "Unequip / Forge menu: %s" % panel.menu_labels())
	check(not panel.tooltip.visible, "hidden")
	_tap(panel, slot, PlayerInput.Pad.B)
	panel.select_backpack(0)
	_tap(panel, slot, PlayerInput.Pad.X)
	check(panel.is_menu_open() and not panel.tooltip.visible, "X opens the menu on Sell, without the tooltip")
	panel.set_tab(PlayerPanel.TRAINER_TAB)
	panel.set_tab(PlayerPanel.CHARACTER_TAB)
	check(not panel.is_menu_open() and panel.tooltip.visible, "a tab switch closes the menu; the tooltip returns")


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
	check_eq(panel.menu_labels(), PackedStringArray(["Equip", "Sell", "Disenchant", "Cancel"]), "solo: no Trade (Disenchant sits next to Sell)")
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
	check_eq(panel.menu_labels(), PackedStringArray(["Equip", "Sell", "Disenchant", "Cancel"]), "B goes back one level")
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
	check_eq(panel.menu_labels(), PackedStringArray(["Equip", "Sell", "Disenchant", "Trade", "Cancel"]), "Trade offered with a teammate")
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

func test_y_toggles_comparison_and_tabs_switch() -> void:
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
	check_eq(panel.active_tab, PlayerPanel.TRAINER_TAB, "RT opens the Trainer")
	check(panel.trainer.visible and not panel.tooltip.visible, "the Trainer replaces the paper doll and its tooltip")
	_tap(panel, slot, PlayerInput.Pad.RT)
	check_eq(panel.active_tab, PlayerPanel.TALENTS_TAB, "RT opens the Talents tab (M5)")
	check(panel.talents.visible and not panel.trainer.visible and not panel.tooltip.visible,
		"the Talents tab replaces the Trainer")
	_tap(panel, slot, PlayerInput.Pad.RT)
	check_eq(panel.active_tab, PlayerPanel.ENCHANTER_TAB, "RT opens the Enchanter tab (M6a)")
	check(panel.enchanter.visible and not panel.talents.visible and not panel.tooltip.visible,
		"the Enchanter tab replaces the Talents tab")
	_tap(panel, slot, PlayerInput.Pad.LT)
	check_eq(panel.active_tab, PlayerPanel.TALENTS_TAB, "LT goes back to the Talents tab")
	_tap(panel, slot, PlayerInput.Pad.LT)
	check_eq(panel.active_tab, PlayerPanel.TRAINER_TAB, "LT goes back to the Trainer")
	_tap(panel, slot, PlayerInput.Pad.LT)
	check_eq(panel.active_tab, PlayerPanel.CHARACTER_TAB, "LT goes back to Character")
	check(panel.tooltip.visible, "the item tooltip is back")
	_tap(panel, slot, PlayerInput.Pad.LT)
	check_eq(panel.active_tab, PlayerPanel.ENCHANTER_TAB, "wraps to the Enchanter tab")
	_tap(panel, slot, PlayerInput.Pad.RT)
	check_eq(panel.active_tab, PlayerPanel.CHARACTER_TAB, "RT wraps back to Character")


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


## The long rows M5 talents and set bonuses put into the compact stat list (Resource Regen,
## Cooldown Reduction, Crit Damage – a warrior also lists its base Speed) with wide values: the
## names give way, so the grid fits the inset and the frame stays inside the 700 x 480 design box
## (the 4-player corner layout scales that box, never past it). Every stat's compact name shows
## whole next to a "30%" and a "12.5%" value (PlayerPanel.SHORT_STAT_NAMES).
func test_stat_list_fits_its_inset_with_long_rows() -> void:
	_async = true
	var slot := _join(&"warrior")
	var player := slot.player as Player
	player.stats.set_source(&"test", {Stats.STAMINA: 990.0, Stats.ARMOR: 120.0, Stats.CRIT: 12.5,
		Stats.HASTE: 14.0, Stats.VERSATILITY: 10.0, Stats.DODGE: 16.0, Stats.MASTERY: 40.0,
		Stats.CRIT_DAMAGE: 120.0, Stats.COOLDOWN_REDUCTION: 12.0,
		Stats.RESOURCE_REGEN: 19.0})
	var panel := _panel(slot)
	panel.refresh()
	var ids: Array = PlayerPanel.stat_rows(player.stats, slot.class_data).map(func(r: Array) -> StringName: return r[0])
	for stat in [Stats.CRIT_DAMAGE, Stats.COOLDOWN_REDUCTION, Stats.RESOURCE_REGEN]:
		check(stat in ids, "%s listed: %s" % [stat, ids])
	var frame_min := panel.get_child(0).get_combined_minimum_size() as Vector2
	check(frame_min.x <= PlayerPanel.DESIGN_SIZE.x + 0.5 and frame_min.y <= PlayerPanel.DESIGN_SIZE.y + 0.5,
		"the frame fits the design size: %s" % frame_min)
	await tree.process_frame
	await tree.process_frame
	var inset := panel._stats_grid.get_parent() as Control
	var room := inset.size.x - 2.0 * PlayerPanel.STAT_INSET_PAD
	var grid_min := panel._stats_grid.get_combined_minimum_size().x
	check(grid_min <= room + 0.5, "the stat grid needs %.1f of the inset's %.1f" % [grid_min, room])
	check(inset.clip_contents, "the inset clips")
	var frame := (panel.get_child(0) as Control).get_global_rect()
	check(frame.end.x <= panel.get_global_rect().end.x + 0.5, "the frame ends inside the panel (%s / %s)" % [frame, panel.get_global_rect()])
	check(inset.get_global_rect().end.x <= frame.end.x + 0.5, "the inset ends inside the frame")
	# The compact names of these rows show whole next to a two-digit value.
	for cell in panel._stats_grid.get_children():
		var name_label := cell.get_child(0) as Label
		var value_label := cell.get_child(1) as Label
		var needed := name_label.get_theme_font(&"font").get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			name_label.get_theme_font_size(&"font_size")).x
		if value_label.text.length() <= 3:
			check(needed <= name_label.size.x + 0.5, "'%s' (%s) shows whole: %.1f / %.1f" % [name_label.text, value_label.text, needed, name_label.size.x])
		check(value_label.get_global_rect().end.x <= inset.get_global_rect().end.x + 0.5, "'%s' value inside the inset" % name_label.text)
	# Every stat's compact name shows whole next to "30%" and "12.5%" (a few stats at a time,
	# each batch fits the twelve cells next to the always-listed rows).
	var shown := {}
	var all_stats: Array[StringName] = Stats.ALL.duplicate()
	all_stats.erase(Stats.STAMINA)  # listed as Max HP
	for value in [30.0, 12.5]:
		for start in range(0, all_stats.size(), 3):
			var batch := all_stats.slice(start, start + 3)
			var values := {}
			for stat in batch:
				values[stat] = value
			player.stats.set_source(&"test", values)
			panel.refresh()
			await tree.process_frame
			await tree.process_frame
			for cell in panel._stats_grid.get_children():
				var name_label := cell.get_child(0) as Label
				var value_label := cell.get_child(1) as Label
				for stat in batch:
					if name_label.text != PlayerPanel._stat_name(stat):
						continue
					shown["%s %s" % [stat, value]] = true
					var needed := name_label.get_theme_font(&"font").get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
						name_label.get_theme_font_size(&"font_size")).x
					check(needed <= name_label.size.x + 0.5, "'%s' next to '%s' shows whole: %.1f / %.1f" % [name_label.text,
						value_label.text, needed, name_label.size.x])
	check_eq(shown.size(), all_stats.size() * 2, "every stat was listed with both values")
	finished.emit()


## Every tier-set piece's tooltip in each corner of the 4-player market layout at 1920 x 1080
## (Intermission scale, tooltip_inside, the root resized like the real screen): the compact set
## block (slot names, no flavor) keeps a looted piece's tooltip inside its panel at a readable
## scale (about 0.9 or more); with the comparison block on top it keeps that scale
## (PlayerPanel.MIN_INSIDE_TOOLTIP_FIT) and reaches out of the panel towards the middle, on
## screen. Neither it nor a wave-25 Legendary unique with the comparison block ever reaches the
## other corner panel of its screen column (those shrink below the floor only when it would).
## Piece [param i] of [param data] as a wave-8 item.
func _set_piece(data: SetData, i: int) -> ItemInstance:
	return ItemGenerator.from_unique(Db.get_unique(data.piece_ids[i]), 8, false, RandomNumberGenerator.new())


func test_set_piece_tooltips_fit_the_4_player_panels() -> void:
	_async = true
	_root_size = tree.root.size
	tree.root.size = Vector2i(1920, 1080)
	await tree.process_frame
	# The body text of a 4-player panel's tooltip at 1280 x 720: 20 px x 0.83 x 0.67 x this ≈ 10 px.
	const READABLE_FIT := 0.899
	var s := Intermission.panel_scale(PlayerPanel.DESIGN_SIZE)
	var shown := PlayerPanel.DESIGN_SIZE * s
	var m := Intermission.MARGIN
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var pieces := 0
	var legendaries := 0
	for data: SetData in Db.sets.values():
		# A class set is shown to its class; a class-independent one to the first class that can wear it.
		var viewer_class := data.class_id
		if viewer_class == &"":
			for id in Db.class_ids:
				if Db.set_usable_by(data, Db.get_class_data(id)):
					viewer_class = id
					break
		var slot := _join(viewer_class)
		var eq := _eq(slot)
		var panel := _panel(slot)
		panel.tooltip_inside = true
		panel.scale = Vector2(s, s)
		var view := panel.get_viewport_rect()
		check_eq(view.size, Vector2(1920, 1080), "the 1920 x 1080 view")
		var corners: Array[Vector2] = [Vector2(m, m), Vector2(view.end.x - m - shown.x, m),
			Vector2(m, view.end.y - m - shown.y), Vector2(view.end.x - m - shown.x, view.end.y - m - shown.y)]
		# The panel at the other end of each corner's column.
		var mates: Array[Rect2] = [Rect2(corners[2], shown), Rect2(corners[3], shown), Rect2(corners[0], shown),
			Rect2(corners[1], shown)]
		for i in data.piece_ids.size():
			var piece := _set_piece(data, i)
			piece.looted = true
			# Two other pieces worn ("(2/5)", the 2-piece bonus on), a plain item where this
			# one goes (the comparison block), the piece in the backpack.
			eq.slots.clear()
			for j in [(i + 1) % 5, (i + 2) % 5]:
				var other := _set_piece(data, j)
				eq.slots[eq.target_slots(other)[0]] = other
			eq.slots[eq.target_slots(piece)[0]] = Items_.armor("Plain Piece", piece.slot_type, piece.armor_type, 1, {"stamina": 2})
			eq.backpack.clear()
			eq.add_to_backpack(piece)
			panel.select_backpack(0)
			for comparison in [false, true]:
				if panel.comparison != comparison:
					panel.toggle_comparison()
				check(panel.tooltip.visible and panel.tooltip.item == piece, "%s shown" % piece.display_name)
				check(panel.tooltip.compact_set(), "%s: the compact set block" % piece.display_name)
				await tree.process_frame
				await tree.process_frame
				for c in corners.size():
					panel.position = corners[c]
					panel._place_tooltip()
					var what := "%s (comparison %s, corner %d)" % [piece.display_name, comparison, c + 1]
					var tip := panel.tooltip.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, panel.tooltip.size)
					var panel_rect := panel.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, panel.size)
					check(panel.tooltip.scale.y >= READABLE_FIT,
						"%s: readable scale %.2f" % [what, panel.tooltip.scale.y])
					check(view.grow(-3.0).encloses(tip), "%s: on screen %s" % [what, tip])
					check(not tip.intersects(mates[c]), "%s: clear of the column's other panel %s / %s" % [what, tip, mates[c]])
					if not comparison:
						check(panel_rect.grow(0.5).encloses(tip), "%s: inside its panel %s / %s" % [what, tip, panel_rect])
			pieces += 1
		# The Legendary uniques this class can use, in the backpack, compared with an item of
		# many other stats in every slot they could go to (a long comparison block).
		if not panel.comparison:
			panel.toggle_comparison()
		for unique: UniqueItemData in Db.uniques.values():
			if unique.rarity != Items.Rarity.LEGENDARY or not ItemGenerator.unique_usable_by(unique, slot.class_data):
				continue
			var item := ItemGenerator.from_unique(unique, 25, true, rng, slot.class_data)
			eq.slots.clear()
			for target in eq.target_slots(item):
				var worn := Items_.armor("Worn Piece", item.slot_type, item.armor_type, 3, {})
				if item.is_weapon():
					worn = ItemInstance.from_weapon(item.weapon, Items.Rarity.EPIC, 20)
				worn.stats = {Stats.STAMINA: 30.0, Stats.AGILITY: 20.0, Stats.INTELLECT: 20.0, Stats.MASTERY: 9.0,
					Stats.VERSATILITY: 9.0, Stats.DODGE: 6.0, Stats.LEECH: 4.0, Stats.SPEED: 5.0}
				eq.slots[target] = worn
			eq.backpack.clear()
			eq.add_to_backpack(item)
			panel.select_backpack(0)
			check(panel.tooltip.visible and panel.tooltip.compare != null, "%s: shown with the comparison block" % item.display_name)
			await tree.process_frame
			await tree.process_frame
			for c in corners.size():
				panel.position = corners[c]
				panel._place_tooltip()
				var what := "%s %s (corner %d)" % [data.class_id, item.display_name, c + 1]
				var tip := panel.tooltip.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, panel.tooltip.size)
				check(view.grow(-3.0).encloses(tip), "%s: on screen %s" % [what, tip])
				check(not tip.intersects(mates[c]), "%s: clear of the column's other panel %s / %s" % [what, tip, mates[c]])
				var room := view.size.y - 2.0 * m - shown.y - PlayerPanel.TOOLTIP_NEIGHBOUR_GAP
				check(panel.tooltip.scale.y >= READABLE_FIT or tip.size.y >= room - 0.5,
					"%s: below the floor (%.2f) only when it fills the column" % [what, panel.tooltip.scale.y])
			legendaries += 1
		panels.erase(panel)
		UiFakes.free_node(panel)
		players.erase(slot.player)
		(slot.player as Player).free()
		UiFakes.reset_players()
	check_eq(pieces, Db.sets.size() * 5, "five pieces of every set")
	check(legendaries >= 8, "Legendary uniques checked: %d" % legendaries)
	finished.emit()


## Every Artifact's tooltip (M6, five classes, asleep and fully awake) in each corner of the
## 4-player market layout at 1920 x 1080, with and without the comparison block against a worn
## Epic weapon of the same type: the compact property text of a viewer's tooltip keeps it at a readable
## scale (ARTIFACT_READABLE_FIT, below the set pieces' 0.9: an Artifact has two property blocks),
## on screen and clear of the column's other panel.
func test_artifact_tooltips_fit_the_4_player_panels() -> void:
	_async = true
	_root_size = tree.root.size
	tree.root.size = Vector2i(1920, 1080)
	await tree.process_frame
	const ARTIFACT_READABLE_FIT := 0.85
	var s := Intermission.panel_scale(PlayerPanel.DESIGN_SIZE)
	var shown := PlayerPanel.DESIGN_SIZE * s
	var m := Intermission.MARGIN
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var checked := 0
	for data: ArtifactData in Db.artifacts.values():
		var slot := _join(data.class_id)
		var eq := _eq(slot)
		var panel := _panel(slot)
		panel.tooltip_inside = true
		panel.scale = Vector2(s, s)
		var view := panel.get_viewport_rect()
		var corners: Array[Vector2] = [Vector2(m, m), Vector2(view.end.x - m - shown.x, m),
			Vector2(m, view.end.y - m - shown.y), Vector2(view.end.x - m - shown.x, view.end.y - m - shown.y)]
		var mates: Array[Rect2] = [Rect2(corners[2], shown), Rect2(corners[3], shown), Rect2(corners[0], shown),
			Rect2(corners[1], shown)]
		for waves in [0, 6]:
			var item := ItemGenerator.generate_artifact(data.class_id, 10)
			item.artifact_waves = waves
			if item.companion != null:
				item.companion.artifact_waves = waves
			# A worn Epic weapon of the same type (a pair: both hands) where the Artifact goes.
			eq.slots.clear()
			for target in eq.target_slots(item):
				var base := data.pair_weapon if target == Items.EquipSlot.OFF_HAND and data.is_pair() else data.weapon
				eq.slots[target] = ItemGenerator.generate_weapon(base, Items.Rarity.EPIC, 10, true, rng)
			eq.backpack.clear()
			eq.add_to_backpack(item)
			panel.select_backpack(0)
			for comparison in [false, true]:
				if panel.comparison != comparison:
					panel.toggle_comparison()
				check(panel.tooltip.visible and panel.tooltip.item == item, "%s shown" % item.display_name)
				check_eq(panel.tooltip.comparison_visible, comparison, "%s: the comparison block follows the toggle" % item.display_name)
				await tree.process_frame
				await tree.process_frame
				for c in corners.size():
					panel.position = corners[c]
					panel._place_tooltip()
					var what := "%s (%d waves, comparison %s, corner %d)" % [item.display_name, waves, comparison, c + 1]
					var tip := panel.tooltip.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, panel.tooltip.size)
					check(panel.tooltip.scale.y >= ARTIFACT_READABLE_FIT,
						"%s: readable scale %.3f (tooltip %.0f px tall)" % [what, panel.tooltip.scale.y, panel.tooltip.size.y])
					check(view.grow(-3.0).encloses(tip), "%s: on screen %s" % [what, tip])
					check(not tip.intersects(mates[c]), "%s: clear of the column's other panel %s / %s" % [what, tip, mates[c]])
					checked += 1
		panels.erase(panel)
		UiFakes.free_node(panel)
		players.erase(slot.player)
		(slot.player as Player).free()
		UiFakes.reset_players()
	check_eq(checked, Db.artifacts.size() * 2 * 2 * 4, "every Artifact x asleep / awake x comparison on / off x four corners")
	finished.emit()


func test_inside_tooltip_is_scaled_to_fit_the_panel() -> void:
	var slot := _join(&"warrior")
	_eq(slot).add_to_backpack(_helm("Iron Helm", ClassData.ArmorType.PLATE, 3))
	var panel := _panel(slot)
	panel.tooltip_inside = true
	panel.scale = Vector2(0.5, 0.5)
	panel.position = Vector2(20, 20)
	panel._place_tooltip()
	check(panel.tooltip.visible, "tooltip shown")
	var tip_h := panel.tooltip.get_combined_minimum_size().y * 0.5
	var room := panel.size.y * 0.5
	var expected := clampf(room / tip_h, PlayerPanel.MIN_INSIDE_TOOLTIP_FIT, 1.0)
	check_near(panel.tooltip.scale.y, expected, 0.001, "scaled to the panel's height (%s / %s)" % [room, tip_h])
	panel.tooltip_inside = false
	panel._place_tooltip()
	check(panel.tooltip.scale.y >= expected - 0.001, "outside the panel it may use the screen height")
