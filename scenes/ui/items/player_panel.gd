class_name PlayerPanel
extends Control
## One player's personal between-wave panel (GDD 12), shown in that player's screen corner /
## quadrant (DESIGN_SIZE 700x480 on the 1920x1080 canvas; scale it with [member scale]).
## Header in the player's colour (Pn, class, Avg. Item Level), tabs Character | Trainer |
## Talents. Trainer tab = TrainerTab (GDD 6.3: the hero's slotted
## abilities, their ranks and the gold for the next one; see scenes/ui/trainer/), same size as
## the Character tab; Talents tab = TalentTab (GDD 7, M5; scenes/ui/talents/: the three talent
## trees, points, reset), wired the same way – its label shows the hero's free talent points
## ("Talents (2)", TalentTab.tab_label, relabelled on TalentTab.points_changed; talent stats come
## through stats.set_source, so that signal and showing the Character tab rebuild the stat list).
## Character tab = WoW paper doll – Head, Neck,
## Shoulders, Chest, Wrist on the left, Hands, Waist, Legs, Feet on the right, rings, weapons
## and trinkets along the bottom, a live onion preview in the middle – next to a compact stat
## list and the 10-slot backpack.
## Controller (only the PlayerInput passed to handle_input): d-pad / stick moves the
## selection, A opens the action menu (backpack: Equip (→ slot for rings / trinkets /
## dual wield) / Forge (weapons) / Sell / Trade → Pn / Cancel; equipped: Unequip / Forge
## (weapons) / Cancel), X opens it on Sell, B closes menus, Y toggles the comparison in the
## tooltip, LT / RT switch tabs (the Trainer and Talents tabs take the rest of the input while
## they are shown; TrainerTab / TalentTab.handle_input – LT / RT stay with the panel unless the
## tab is modal). Forge (M5): Forge.blocked_reason greys the entry out, Forge.result_text is its
## detail, Forge.forge does it and the result gets selected.
## Sell gives Items.SELL_SHARE of the price to the shared wallet. Trade moves a backpack item
## into a teammate's backpack (needs free space); the teammate's panel says "P1 gave you X".
## Equip shows what else it pushes out ("Replaces Bow" for an off-hand item next to a
## two-hander, "Replaces Dagger + Dagger" for a two-hander). Nothing may leave the hero without
## an attacking weapon (Equipment.is_last_weapon / equip_disarms): those Equip / Unequip /
## Sell / Trade entries are greyed out with "You need a weapon".
## The selected item's ItemTooltip floats beside the panel, towards the screen centre (with
## [member tooltip_inside] over the panel's other half); it hides while the action menu is open.

signal trade_done(item: ItemInstance, to_slot_index: int)
## Emitted after an item was sold from the backpack ([param gold] went to RunState).
signal item_sold(item: ItemInstance, gold: int)

const DESIGN_SIZE := Vector2(700, 480)
const DOLL_ICON := 48.0
const DOLL_GAP := 6.0
const BOTTOM_GROUP_GAP := 14.0
const BAG_ICON := 52.0
const BAG_GAP := 7.0
const BAG_COLUMNS := 5
const BODY_GAP := 12.0
const MESSAGE_TIME := 2.8
## With [member tooltip_inside] a tooltip taller than the panel shrinks to fit it, but not below
## this scale: a still taller one (a set piece with the comparison block) reaches past the
## panel's edge towards the middle of the screen instead of becoming unreadable at 720p – as
## far as the other corner panel of the screen column allows ([member tooltip_column_mate]; it
## shrinks below this only when this scale would cross into that panel).
const MIN_INSIDE_TOOLTIP_FIT := 0.9
## A tooltip that reaches out of the panel ends this far (canvas px) before the column's other
## corner panel.
const TOOLTIP_NEIGHBOUR_GAP := 8.0
## Without [member tooltip_inside]: the tooltip shrinks to the screen height, down to this.
const MIN_TOOLTIP_FIT := 0.4

const LEFT_SLOTS: Array[Items.EquipSlot] = [
	Items.EquipSlot.HEAD, Items.EquipSlot.NECK, Items.EquipSlot.SHOULDERS,
	Items.EquipSlot.CHEST, Items.EquipSlot.WRIST,
]
const RIGHT_SLOTS: Array[Items.EquipSlot] = [
	Items.EquipSlot.HANDS, Items.EquipSlot.WAIST, Items.EquipSlot.LEGS, Items.EquipSlot.FEET,
]
## Bottom row, in three groups of two: rings | weapons | trinkets.
const BOTTOM_SLOTS: Array[Items.EquipSlot] = [
	Items.EquipSlot.RING_1, Items.EquipSlot.RING_2, Items.EquipSlot.MAIN_HAND,
	Items.EquipSlot.OFF_HAND, Items.EquipSlot.TRINKET_1, Items.EquipSlot.TRINKET_2,
]
const TAB_NAMES: Array[String] = ["Character", "Trainer", "Talents"]
const CHARACTER_TAB := 0
const TRAINER_TAB := 1
const TALENTS_TAB := 2
## Tabs that only say "coming soon" (none since M5 opened Talents).
const LOCKED_TABS: Array[int] = []
## --panel-tab values -> tab index (debug_start_tab).
const TAB_IDS: Dictionary[String, int] = {"character": CHARACTER_TAB, "trainer": TRAINER_TAB, "talents": TALENTS_TAB}
## Stat list (two columns, at most MAX_STAT_ROWS rows so the panel never grows): the class's
## primary stat, then these, then the other primary stats and every other non-zero stat.
## Stamina is shown as Max HP (10 + Stamina).
const LISTED_STATS: Array[StringName] = [
	&"max_hp", Stats.ARMOR, Stats.CRIT, Stats.HASTE, Stats.VERSATILITY, Stats.DODGE,
]
const PRIMARY_STATS: Array[StringName] = [Stats.STRENGTH, Stats.AGILITY, Stats.INTELLECT]
const UNLISTED_STATS: Array[StringName] = [Stats.STAMINA]
const MAX_STAT_ROWS := 6
## Compact names of the stat list: the two columns share the inset's width (STAT_COLUMN_GAP
## apart), so a name gets 90 design px next to a "12.5%" value (105 next to "30%"). Longer names
## are cut with an ellipsis ([method _refresh_stats]) – the list never widens the panel; every
## stat's name here or in Stats.DISPLAY_NAMES fits next to "12.5%". The spell schools drop the
## "Damage" ("Shadow 30%" – plain Damage is its own row).
const SHORT_STAT_NAMES := {
	&"max_hp": "Max HP", Stats.CRIT: "Crit", Stats.CRIT_DAMAGE: "Crit Dmg",
	Stats.COOLDOWN_REDUCTION: "CDR", Stats.EXTRA_PROJECTILE: "Projectiles",
	Stats.RESOURCE_REGEN: "Regen", Stats.PICKUP_RANGE: "Pickup", Stats.HEALING_DONE: "Healing",
	Stats.ATTACK_POWER: "Atk Power", Stats.EXTRA_ATTACK: "Extra Atk", Stats.BLOCK_VALUE: "Block Val.",
	Stats.EXECUTIONER: "Execute",
	Stats.FIRE_DAMAGE: "Fire", Stats.FROST_DAMAGE: "Frost", Stats.ARCANE_DAMAGE: "Arcane",
	Stats.HOLY_DAMAGE: "Holy", Stats.SHADOW_DAMAGE: "Shadow", Stats.NATURE_DAMAGE: "Nature",
	Stats.PHYSICAL_DAMAGE: "Physical",
}
## Stat list inset: side padding, the gap between the two columns and between a name and its value.
const STAT_INSET_PAD := 8
const STAT_COLUMN_GAP := 14
const STAT_VALUE_GAP := 6

enum Mode { BROWSE, MENU }


## One selectable icon: an equipment position or a backpack index.
class Cell:
	var equip_slot := -1
	var bag_index := -1
	## Centre in the design layout of the body (spatial navigation).
	var pos := Vector2.ZERO
	var icon: ItemIcon


class MenuEntry:
	var label := ""
	## Right-hand text (gold value, current item, "Backpack full" ...).
	var detail := ""
	var enabled := true
	## Shown as a message when the entry is activated while disabled.
	var reason := ""
	var action: Callable
	var color := UiTheme.TEXT


var slot: PlayerSlot
var tooltip: ItemTooltip
## true: the selected item's tooltip stays over this panel (on the half away from the
## selection) instead of floating towards the screen centre – used between waves, where the
## middle of the screen holds the shared shop.
var tooltip_inside := false
## With [member tooltip_inside]: the other corner of this panel's screen column holds a
## teammate's panel (the Intermission's corner layout – P1 / P3 left, P2 / P4 right – where it is
## the mirror image of this panel about the view's horizontal centre line). A tooltip that
## reaches out of this panel then ends TOOLTIP_NEIGHBOUR_GAP before it; false: before the screen
## edge. The Intermission keeps it up to date ([method Intermission._sync_panels]).
var tooltip_column_mate := true
## Index into the cells (see select_equip_slot / select_backpack).
var selected := 0
## Whether the tooltip shows the "If you replace this item:" block (Y toggles).
var comparison := true
var mode := Mode.BROWSE
var active_tab := 0
## Plain text of the last message ("+12 gold", "P1 gave you Iron Helm" ...).
var last_message := ""
## Whether the last handle_input() used a press (navigation, A / B / X / Y / LT / RT). B is
## only used while a menu is open, so the owner may treat an unconsumed B as its own (unready).
var last_input_consumed := false

## The Trainer tab's body (shown instead of the paper doll while active_tab is TRAINER_TAB).
var trainer: TrainerTab
## The Talents tab's body (shown while active_tab is TALENTS_TAB).
var talents: TalentTab

## Dev only (--panel-tab=talents / trainer / character, screenshots): when the market opens,
## P1's panel switches to that tab once ("" = off).
static var debug_start_tab := ""

var _cells: Array[Cell] = []
var _focused := false
var _body: HBoxContainer
var _equipment: Equipment
var _frame: PanelContainer
var _header: PanelContainer
var _player_label: Label
var _class_label: Label
var _ilvl_value: Label
var _tabs_row: HBoxContainer
## The tab strip's name labels (index = tab), relabelled in place (_refresh_tab_labels).
var _tab_labels: Array[Label] = []
var _stats_grid: GridContainer
var _bag_count: Label
var _spec_label: Label
var _preview: OnionPreview
var _preview_glow: TextureRect
var _prompt_holder: HBoxContainer
var _prompt_key := ""
var _context_label: Label
var _menu_panel: PanelContainer
var _menu_box: VBoxContainer
## Stack of menus: {title, color, entries: Array[MenuEntry], index, item}.
var _menu_stack: Array[Dictionary] = []
var _toast: PanelContainer
var _toast_label: RichTextLabel
var _toast_coin: UiIcon
var _toast_time := 0.0
var _initial_selection := true
## debug_start_tab was applied to this panel.
var _debug_tab_done := false

## Panels in the tree, so a trade can notify the receiver's panel.
static var _open_panels: Array[PlayerPanel] = []


static func create(p_slot: PlayerSlot) -> PlayerPanel:
	var panel := PlayerPanel.new()
	panel.slot = p_slot
	panel.name = "PlayerPanel%d" % (p_slot.index + 1) if p_slot != null else "PlayerPanel"
	panel._build()
	return panel


## Rebuilds from slot.player.equipment (call when opening and after external changes).
func refresh() -> void:
	var eq := equipment()
	_bind(eq)
	var cls := class_data()
	for cell in _cells:
		var it := _item_at(cell)
		if it == null:
			cell.icon.set_empty_slot(cell.equip_slot)
			continue
		cell.icon.set_item(it)
		cell.icon.set_unusable(cls != null and not it.can_be_used_by(cls))
		var badge := 0
		if cell.bag_index >= 0 and cls != null and it.can_be_used_by(cls):
			badge = ItemTooltip.upgrade_direction(it, ItemTooltip.equipped_for_compare(it, eq), cls, eq)
		cell.icon.set_upgrade_badge(badge)
	if _initial_selection:
		_initial_selection = false
		selected = _cell_index(-1, 0) if eq != null and not eq.backpack.is_empty() else _cell_index(Items.EquipSlot.MAIN_HAND, -1)
	_refresh_header(eq, cls)
	_refresh_stats(cls)
	_refresh_side(eq, cls)
	if mode == Mode.MENU and not _menu_item_still_there():
		close_menu()
	trainer.refresh()
	talents.refresh()
	_refresh_tab_labels()
	_update_selection()
	_apply_debug_start_tab()


## Whether this panel currently receives the player's input (the Intermission routes input
## between the shared shop cursor and this panel; LB / RB switch).
func set_input_focus(focused: bool) -> void:
	_focused = focused
	if not focused and mode == Mode.MENU:
		close_menu()
	trainer.set_focused(focused and active_tab == TRAINER_TAB)
	talents.set_focused(focused and active_tab == TALENTS_TAB)
	_frame.add_theme_stylebox_override(&"panel", _frame_style(focused))
	_update_selection()


func has_input_focus() -> bool:
	return _focused


## Called every _process frame by the Intermission while this panel has focus. [param delta]
## runs the Trainer's hold-to-train timer (default: this frame's process delta).
func handle_input(input: PlayerInput, delta: float = -1.0) -> void:
	last_input_consumed = false
	if input == null:
		return
	if active_tab == TRAINER_TAB:
		_trainer_input(input, delta if delta >= 0.0 else get_process_delta_time())
		return
	if active_tab == TALENTS_TAB:
		_talents_input(input, delta if delta >= 0.0 else get_process_delta_time())
		return
	if mode == Mode.MENU:
		last_input_consumed = input.nav_just_pressed() != Vector2i.ZERO or input.just_pressed(PlayerInput.Pad.A) \
			or input.just_pressed(PlayerInput.Pad.B)
		_menu_input(input)
		return
	var nav := input.nav_just_pressed()
	if nav != Vector2i.ZERO:
		move_selection(nav)
		last_input_consumed = true
	if input.just_pressed(PlayerInput.Pad.A):
		open_menu()
		last_input_consumed = true
	elif input.just_pressed(PlayerInput.Pad.X) and _cells[selected].bag_index >= 0:
		open_menu(true)
		last_input_consumed = true
	if input.just_pressed(PlayerInput.Pad.Y):
		toggle_comparison()
		last_input_consumed = true
	if input.just_pressed(PlayerInput.Pad.LT):
		switch_tab(-1)
		last_input_consumed = true
	elif input.just_pressed(PlayerInput.Pad.RT):
		switch_tab(1)
		last_input_consumed = true


# --- Queries ---------------------------------------------------------------------------------

func equipment() -> Equipment:
	return _equipment_of(slot)


func class_data() -> ClassData:
	var eq := equipment()
	if eq != null and eq.class_data != null:
		return eq.class_data
	return slot.class_data if slot != null else null


func selected_item() -> ItemInstance:
	return _item_at(_cells[selected]) if selected >= 0 and selected < _cells.size() else null


## Equipment position of the selection (-1 when a backpack cell is selected).
func selected_equip_slot() -> int:
	return _cells[selected].equip_slot


## Backpack index of the selection (-1 when an equipment cell is selected).
func selected_bag_index() -> int:
	return _cells[selected].bag_index


func icon_for_equip_slot(equip_slot: int) -> ItemIcon:
	var i := _cell_index(equip_slot, -1)
	return _cells[i].icon if i >= 0 else null


func icon_for_bag_index(index: int) -> ItemIcon:
	var i := _cell_index(-1, index)
	return _cells[i].icon if i >= 0 else null


func select_equip_slot(equip_slot: int) -> void:
	var i := _cell_index(equip_slot, -1)
	if i >= 0:
		_select(i)


func select_backpack(index: int) -> void:
	var i := _cell_index(-1, index)
	if i >= 0:
		_select(i)


func is_menu_open() -> bool:
	return mode == Mode.MENU


## Labels of the open menu level (empty when closed).
func menu_labels() -> PackedStringArray:
	var out := PackedStringArray()
	if _menu_stack.is_empty():
		return out
	for e: MenuEntry in _menu_stack.back()["entries"]:
		out.append(e.label)
	return out


## Whether the entry labelled [param label] in the open menu level is enabled.
func menu_entry_enabled(label: String) -> bool:
	if _menu_stack.is_empty():
		return false
	for e: MenuEntry in _menu_stack.back()["entries"]:
		if e.label == label:
			return e.enabled
	return false


## Right-hand text of the entry labelled [param label] in the open menu level ("" if none).
func menu_entry_detail(label: String) -> String:
	if _menu_stack.is_empty():
		return ""
	for e: MenuEntry in _menu_stack.back()["entries"]:
		if e.label == label:
			return e.detail
	return ""


func menu_index() -> int:
	return int(_menu_stack.back()["index"]) if not _menu_stack.is_empty() else -1


## Moves the menu cursor onto the entry labelled [param label] (tests / scripted flows).
func select_menu_entry(label: String) -> bool:
	if _menu_stack.is_empty():
		return false
	var entries: Array = _menu_stack.back()["entries"]
	for i in entries.size():
		if (entries[i] as MenuEntry).label == label:
			_menu_stack.back()["index"] = i
			_render_menu()
			return true
	return false


## Anchors the panel in its player's corner (P1 top-left, P2 top-right, P3 bottom-left,
## P4 bottom-right – the HUD unit frame corners).
func anchor_to_corner(margin: float = 16.0) -> void:
	var i := slot.index if slot != null else 0
	var presets := [Control.PRESET_TOP_LEFT, Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT]
	size = DESIGN_SIZE
	set_anchors_and_offsets_preset(presets[clampi(i, 0, 3)], Control.PRESET_MODE_KEEP_SIZE, int(margin))


## Shows "[from] gave you [item]" (called by the giver's panel after a trade).
func notify_received(item: ItemInstance, from_slot: PlayerSlot) -> void:
	var who := from_slot.label() if from_slot != null else "A teammate"
	_message("%s gave you %s" % [who, _bb_item(item)], "%s gave you %s" % [who, item.display_name])


# --- Actions -------------------------------------------------------------------------------

func move_selection(dir: Vector2i) -> void:
	var from := _cells[selected].pos
	var d := Vector2(dir)
	var best := -1
	var best_score := INF
	for pass_i in 2:
		for i in _cells.size():
			if i == selected:
				continue
			var off := _cells[i].pos - from
			var along := off.dot(d)
			var across := absf(off.dot(d.orthogonal()))
			if along < 12.0:
				continue
			# First pass: only cells within ~50° of the direction; then anything that way.
			if pass_i == 0 and across > along * 1.2:
				continue
			var score := along + across * 2.5
			if score < best_score:
				best_score = score
				best = i
		if best >= 0:
			break
	if best >= 0:
		_select(best)


## Opens the action menu for the selected item ([param sell_first]: cursor on Sell).
func open_menu(sell_first: bool = false) -> void:
	var it := selected_item()
	var eq := equipment()
	if eq == null:
		return
	if it == null:
		_message(_cell_name(_cells[selected]) + " is empty")
		return
	var cell := _cells[selected]
	var entries: Array[MenuEntry] = []
	if cell.bag_index >= 0:
		entries = _backpack_entries(it)
	else:
		entries = _equipped_entries(cell.equip_slot)
	var index := 0
	if sell_first:
		for i in entries.size():
			if entries[i].label == "Sell":
				index = i
	_menu_stack = [{"title": it.display_name, "color": _rarity_color(it), "entries": entries, "index": index, "item": it}]
	mode = Mode.MENU
	_render_menu()
	_update_tooltip()
	_update_prompts()


func close_menu() -> void:
	_menu_stack.clear()
	mode = Mode.BROWSE
	_menu_panel.visible = false
	_update_tooltip()
	_update_prompts()


func toggle_comparison() -> void:
	comparison = not comparison
	_update_tooltip()
	_update_prompts()


## LT / RT: the neighbouring tab; a locked one (none since M5) only says "coming soon".
func switch_tab(step: int) -> void:
	var target := posmod(active_tab + step, TAB_NAMES.size())
	if target in LOCKED_TABS:
		_message("%s: coming soon" % TAB_NAMES[target])
		return
	set_tab(target)


## Shows tab [param index] (CHARACTER_TAB, TRAINER_TAB or TALENTS_TAB; locked tabs are refused).
func set_tab(index: int) -> void:
	if index < 0 or index >= TAB_NAMES.size() or index in LOCKED_TABS or index == active_tab:
		return
	if mode == Mode.MENU:
		close_menu()
	active_tab = index
	_body.visible = index == CHARACTER_TAB
	trainer.visible = index == TRAINER_TAB
	talents.visible = index == TALENTS_TAB
	_refresh_tabs()
	if index == CHARACTER_TAB:
		# Talent points (and other set_source changes) do not fire Equipment.changed.
		_refresh_stats(class_data())
	elif index == TRAINER_TAB:
		trainer.refresh()
	elif index == TALENTS_TAB:
		talents.refresh()
	trainer.set_focused(_focused and index == TRAINER_TAB)
	talents.set_focused(_focused and index == TALENTS_TAB)
	_prompt_key = ""
	_update_selection()


## --panel-tab (dev): P1's panel opens on [member debug_start_tab] once, when the market first
## shows it.
func _apply_debug_start_tab() -> void:
	if _debug_tab_done or debug_start_tab == "" or slot == null or slot.index != 0:
		return
	_debug_tab_done = true
	set_tab(int(TAB_IDS.get(debug_start_tab, active_tab)))


## LT / RT switch tabs unless the Talents tab is modal (a confirm / hold is open); everything
## else goes to the Talents tab.
func _talents_input(input: PlayerInput, delta: float) -> void:
	if not talents.is_modal():
		if input.just_pressed(PlayerInput.Pad.LT):
			switch_tab(-1)
			last_input_consumed = true
			return
		if input.just_pressed(PlayerInput.Pad.RT):
			switch_tab(1)
			last_input_consumed = true
			return
	last_input_consumed = talents.handle_input(input, delta)


## LT / RT switch tabs (not while the Rank V choice is open); everything else goes to the
## Trainer. B counts as used only when it cancelled a hold or closed the choice.
func _trainer_input(input: PlayerInput, delta: float) -> void:
	if not trainer.is_choosing_spec():
		if input.just_pressed(PlayerInput.Pad.LT):
			switch_tab(-1)
			last_input_consumed = true
			return
		if input.just_pressed(PlayerInput.Pad.RT):
			switch_tab(1)
			last_input_consumed = true
			return
	last_input_consumed = trainer.handle_input(input, delta)


func _backpack_entries(it: ItemInstance) -> Array[MenuEntry]:
	var eq := equipment()
	var cls := class_data()
	var out: Array[MenuEntry] = []
	var equip := _entry("Equip")
	var targets := eq.target_slots(it)
	if cls != null and not it.can_be_used_by(cls):
		equip.enabled = false
		equip.detail = "Can't use"
		equip.reason = it.unusable_reason(cls)
	elif targets.is_empty():
		equip.enabled = false
		equip.reason = "Can't equip that"
	elif targets.size() > 1:
		equip.detail = "▸"
		equip.action = _open_equip_choice.bind(it)
	else:
		_fill_equip_entry(equip, it, targets[0], Items.EQUIP_SLOT_NAMES.get(targets[0], ""))
	out.append(equip)
	if it.is_weapon():
		out.append(_forge_entry(it))
	var last_weapon := eq.is_last_weapon(it)
	var sell := _entry("Sell")
	sell.detail = "+%d gold" % it.sell_value()
	if last_weapon:
		_need_weapon(sell)
	else:
		sell.action = _do_sell.bind(it)
	out.append(sell)
	if not _teammates().is_empty():
		var trade := _entry("Trade")
		trade.detail = "▸"
		if last_weapon:
			_need_weapon(trade)
		else:
			trade.action = _open_trade_choice.bind(it)
		out.append(trade)
	var cancel := _entry("Cancel")
	cancel.action = close_menu
	out.append(cancel)
	return out


func _equipped_entries(equip_slot: int) -> Array[MenuEntry]:
	var out: Array[MenuEntry] = []
	var unequip := _entry("Unequip")
	if equipment().is_last_weapon(equipment().get_item(equip_slot as Items.EquipSlot)):
		_need_weapon(unequip)
	elif not equipment().has_space():
		unequip.enabled = false
		unequip.detail = "Backpack full"
		unequip.reason = "Your backpack is full"
	else:
		unequip.action = _do_unequip.bind(equip_slot)
	out.append(unequip)
	var it := equipment().get_item(equip_slot as Items.EquipSlot)
	if it != null and it.is_weapon():
		out.append(_forge_entry(it))
	var cancel := _entry("Cancel")
	cancel.action = close_menu
	out.append(cancel)
	return out


## "Forge" for weapon [param it] (M5): greyed out with Forge.blocked_reason, the result's rarity
## (Forge.result_text) as the detail.
func _forge_entry(it: ItemInstance) -> MenuEntry:
	var e := _entry("Forge")
	e.detail = Forge.result_text(it)
	var reason := Forge.blocked_reason(equipment(), it)
	if reason != "":
		e.enabled = false
		e.reason = reason
	else:
		e.action = _do_forge.bind(it)
	return e


func _open_equip_choice(it: ItemInstance) -> void:
	var eq := equipment()
	var entries: Array[MenuEntry] = []
	for s in eq.target_slots(it):
		var e := _entry(Items.EQUIP_SLOT_NAMES.get(s, "?"))
		var current := eq.get_item(s)
		_fill_equip_entry(e, it, s, current.display_name if current != null else "empty")
		entries.append(e)
	_push_menu("Equip to", entries, it)


## An Equip entry for [param it] at [param equip_slot]: [param plain] as the detail, or
## "Replaces A (+ B)" when it pushes out an item of another position (an off-hand item next to
## a two-hander, a two-hander with something in the off hand); greyed out when it would leave
## the hero without an attacking weapon.
func _fill_equip_entry(e: MenuEntry, it: ItemInstance, equip_slot: int, plain: String) -> void:
	var eq := equipment()
	var gone := eq.displaced_by(it, equip_slot)
	e.detail = plain
	var current := eq.get_item(equip_slot as Items.EquipSlot)
	var names := PackedStringArray()
	var elsewhere := false
	for old in gone:
		names.append(old.display_name)
		elsewhere = elsewhere or old != current
	if elsewhere:
		e.detail = "Replaces " + " + ".join(names)
	if eq.equip_disarms(it, equip_slot):
		e.enabled = false
		e.reason = "%s – equip a one-handed weapon first" % Equipment.NEED_WEAPON
	else:
		e.action = _do_equip.bind(it, equip_slot)


## Greys out [param e]: it would leave the hero without an attacking weapon.
func _need_weapon(e: MenuEntry) -> void:
	e.enabled = false
	e.detail = "Last weapon"
	e.reason = Equipment.NEED_WEAPON


func _open_trade_choice(it: ItemInstance) -> void:
	var entries: Array[MenuEntry] = []
	for mate in _teammates():
		var data := mate.class_data
		var e := _entry(mate.label())
		e.color = mate.color.lightened(0.3)
		var other := _equipment_of(mate)
		if other.has_space():
			e.detail = data.display_name if data != null else ""
			e.action = _do_trade.bind(it, mate)
		else:
			e.enabled = false
			e.detail = "Backpack full"
			e.reason = "%s's backpack is full" % mate.label()
		entries.append(e)
	_push_menu("Trade to", entries, it)


func _do_equip(it: ItemInstance, equip_slot: int) -> void:
	var eq := equipment()
	if eq.equip(it, equip_slot):
		close_menu()
		_message("Equipped %s" % _bb_item(it), "Equipped %s" % it.display_name)
	elif eq.equip_disarms(it, equip_slot):
		_message(Equipment.NEED_WEAPON, "", UiTheme.RED)
	else:
		_message("Your backpack is full", "", UiTheme.RED)


func _do_unequip(equip_slot: int) -> void:
	var it := equipment().get_item(equip_slot as Items.EquipSlot)
	if equipment().unequip(equip_slot as Items.EquipSlot):
		close_menu()
		_message("Unequipped %s" % _bb_item(it), "Unequipped %s" % it.display_name)
	elif equipment().is_last_weapon(it):
		_message(Equipment.NEED_WEAPON, "", UiTheme.RED)
	else:
		_message("Your backpack is full", "", UiTheme.RED)


## Forges [param it] with its partner (Forge.forge): "Forged [Rare Dagger]!" and the result is
## selected (where it went: an equipped position or the backpack).
func _do_forge(it: ItemInstance) -> void:
	var eq := equipment()
	var reason := Forge.blocked_reason(eq, it)
	var result := Forge.forge(eq, it) if reason == "" else null
	if result == null:
		_message(reason if reason != "" else "Can't forge that", "", UiTheme.RED)
		return
	close_menu()
	_message("Forged %s!" % _bb_item(result), "Forged %s!" % result.display_name, _rarity_color(result))
	var at := eq.backpack.find(result)
	if at >= 0:
		select_backpack(at)
	else:
		for s in Items.EquipSlot.values():
			if eq.get_item(s) == result:
				select_equip_slot(s)
				break
	refresh()


func _do_sell(it: ItemInstance) -> void:
	var eq := equipment()
	if not eq.backpack.has(it):
		return
	var value := it.sell_value()
	if not eq.remove_from_backpack(it):
		_message(Equipment.NEED_WEAPON, "", UiTheme.RED)
		return
	RunState.add_gold(value)
	close_menu()
	_message("+%d gold" % value, "", UiTheme.GOLD, true)
	item_sold.emit(it, value)


func _do_trade(it: ItemInstance, mate: PlayerSlot) -> void:
	var eq := equipment()
	var other := _equipment_of(mate)
	if other == null or not other.has_space():
		_message("%s's backpack is full" % mate.label(), "", UiTheme.RED)
		return
	if not eq.remove_from_backpack(it):
		if eq.is_last_weapon(it):
			_message(Equipment.NEED_WEAPON, "", UiTheme.RED)
		return
	if not other.add_to_backpack(it):
		eq.add_to_backpack(it)
		return
	close_menu()
	_message("Gave %s to %s" % [_bb_item(it), mate.label()], "Gave %s to %s" % [it.display_name, mate.label()])
	trade_done.emit(it, mate.index)
	for panel in _open_panels:
		if is_instance_valid(panel) and panel != self and panel.slot == mate:
			panel.notify_received(it, slot)


func _menu_input(input: PlayerInput) -> void:
	var level: Dictionary = _menu_stack.back()
	var entries: Array = level["entries"]
	var nav := input.nav_just_pressed()
	if nav.y != 0 and not entries.is_empty():
		level["index"] = posmod(int(level["index"]) + nav.y, entries.size())
		_render_menu()
	if input.just_pressed(PlayerInput.Pad.B) or (nav.x < 0 and _menu_stack.size() > 1):
		_menu_stack.pop_back()
		if _menu_stack.is_empty():
			close_menu()
		else:
			_render_menu()
		return
	var e := _current_entry()
	if e == null:
		return
	if input.just_pressed(PlayerInput.Pad.A) or (nav.x > 0 and e.detail == "▸"):
		if not e.enabled:
			_message(e.reason if e.reason != "" else "Not possible", "", UiTheme.RED)
		elif e.action.is_valid():
			e.action.call()


func _current_entry() -> MenuEntry:
	if _menu_stack.is_empty():
		return null
	var level: Dictionary = _menu_stack.back()
	var entries: Array = level["entries"]
	var i := int(level["index"])
	return entries[i] if i >= 0 and i < entries.size() else null


func _push_menu(title: String, entries: Array[MenuEntry], it: ItemInstance) -> void:
	var first := 0
	for i in entries.size():
		if entries[i].enabled:
			first = i
			break
	_menu_stack.append({"title": title, "color": UiTheme.GOLD, "entries": entries, "index": first, "item": it})
	_render_menu()


func _entry(label: String) -> MenuEntry:
	var e := MenuEntry.new()
	e.label = label
	return e


func _menu_item_still_there() -> bool:
	if _menu_stack.is_empty():
		return false
	return _menu_stack[0]["item"] == selected_item()


# --- Build -----------------------------------------------------------------------------------

func _build() -> void:
	theme = UiTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = DESIGN_SIZE
	size = DESIGN_SIZE
	_frame = PanelContainer.new()
	_frame.name = "Frame"
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.add_theme_stylebox_override(&"panel", _frame_style(false))
	add_child(_frame)
	var col := UiTheme.vbox(6)
	_frame.add_child(col)
	col.add_child(_build_header())
	col.add_child(_build_tabs())
	_body = UiTheme.hbox(int(BODY_GAP))
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_body)
	_body.add_child(_build_doll())
	_body.add_child(_build_side())
	trainer = TrainerTab.create(slot)
	trainer.visible = false
	trainer.message.connect(_on_trainer_message)
	trainer.prompts_changed.connect(_on_trainer_prompts_changed)
	col.add_child(trainer)
	talents = TalentTab.create(slot)
	talents.visible = false
	talents.message.connect(_on_talents_message)
	talents.prompts_changed.connect(_on_talents_prompts_changed)
	talents.points_changed.connect(_on_talent_points_changed)
	col.add_child(talents)
	col.add_child(_build_prompt_row())
	_layout_cells()
	_build_menu()
	_build_toast()
	tooltip = ItemTooltip.create()
	tooltip.z_index = 20
	add_child(tooltip)


func _build_header() -> PanelContainer:
	_header = PanelContainer.new()
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var color := slot.color if slot != null else UiTheme.GOLD
	var hs := StyleBoxFlat.new()
	hs.bg_color = color.darkened(0.55)
	hs.border_color = color
	hs.border_width_bottom = 3
	hs.set_corner_radius_all(4)
	hs.content_margin_left = 12
	hs.content_margin_right = 12
	hs.content_margin_top = 0
	hs.content_margin_bottom = 2
	_header.add_theme_stylebox_override(&"panel", hs)
	var row := UiTheme.hbox(10)
	_header.add_child(row)
	_player_label = UiTheme.label(slot.label() if slot != null else "P?", UiTheme.HEADING, 30, color.lightened(0.35))
	row.add_child(_player_label)
	_class_label = UiTheme.label("", UiTheme.GOLD_LABEL, 26)
	_class_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_class_label)
	row.add_child(UiTheme.spacer())
	var cap := UiTheme.label("Avg. Item Level", &"", UiTheme.FONT_SMALL, UiTheme.TEXT)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cap)
	_ilvl_value = UiTheme.label("0", UiTheme.GOLD_LABEL, 28, ItemTooltip.YELLOW)
	_ilvl_value.add_theme_font_override(&"font", UiTheme.title_font())
	_ilvl_value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_ilvl_value)
	return _header


func _build_tabs() -> HBoxContainer:
	_tabs_row = UiTheme.hbox(6)
	_refresh_tabs()
	return _tabs_row


## Redraws the tab strip: the active tab raised in gold, locked tabs with a padlock and
## "Coming soon".
func _refresh_tabs() -> void:
	for c in _tabs_row.get_children():
		_tabs_row.remove_child(c)
		c.queue_free()
	_tab_labels.clear()
	for i in TAB_NAMES.size():
		var tab := PanelContainer.new()
		tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var active := i == active_tab
		var ts := StyleBoxFlat.new()
		ts.bg_color = Color(0.3, 0.21, 0.11, 0.98) if active else Color(0.09, 0.08, 0.07, 0.9)
		ts.border_color = UiTheme.GOLD if active else Color(0.3, 0.26, 0.2)
		ts.set_border_width_all(2 if active else 1)
		ts.border_width_bottom = 0 if active else 1
		ts.corner_radius_top_left = 6
		ts.corner_radius_top_right = 6
		ts.content_margin_left = 14
		ts.content_margin_right = 14
		ts.content_margin_top = 2
		ts.content_margin_bottom = 3
		ts.anti_aliasing = true
		tab.add_theme_stylebox_override(&"panel", ts)
		var row := UiTheme.hbox(6)
		tab.add_child(row)
		var locked := i in LOCKED_TABS
		if locked:
			var lock := UiIcon.create(UiIcon.Kind.LOCK, Vector2(16, 16), Color(0.55, 0.5, 0.44))
			lock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(lock)
		var l := UiTheme.label(tab_text(i), &"", 20 if active else UiTheme.FONT_SMALL,
			UiTheme.GOLD_BRIGHT if active else (Color(0.55, 0.52, 0.48) if locked else UiTheme.TEXT_DIM.lightened(0.1)))
		if active:
			l.add_theme_font_override(&"font", UiTheme.bold_font())
		row.add_child(l)
		_tab_labels.append(l)
		_tabs_row.add_child(tab)
	if not LOCKED_TABS.is_empty():
		var soon := UiTheme.label("Coming soon", &"", 16, Color(0.55, 0.52, 0.48))
		soon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_tabs_row.add_child(soon)
	_tabs_row.add_child(UiTheme.spacer())
	# LT / RT hint at the end of the strip.
	var input := slot.input if slot != null else null
	var hint := UiTheme.hbox(3)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var keyboard := input is KeyboardInput
	# Keyboard: the mouse buttons (KeyboardInput maps LT / RT to RMB / LMB).
	hint.add_child(TrainerRow.PromptTag.create("RMB" if keyboard else "LT", keyboard, 20.0, 14))
	hint.add_child(TrainerRow.PromptTag.create("LMB" if keyboard else "RT", keyboard, 20.0, 14))
	hint.modulate = Color(1, 1, 1, 0.8)
	_tabs_row.add_child(hint)


## The label of tab [param index]: its name; the Talents tab adds the free talent points
## ("Talents (2)", TalentTab.tab_label).
func tab_text(index: int) -> String:
	if index == TALENTS_TAB and talents != null:
		return talents.tab_label()
	return TAB_NAMES[index] if index >= 0 and index < TAB_NAMES.size() else ""


## Updates the tab names in place (the free talent points changed; no strip rebuild).
func _refresh_tab_labels() -> void:
	for i in _tab_labels.size():
		var text := tab_text(i)
		if _tab_labels[i].text != text:
			_tab_labels[i].text = text


## TalentTab.points_changed (every talent add / take back / reset, and level-ups): relabels the
## tab and, while the Character tab is shown, rebuilds its stat list – talent stats arrive
## through stats.set_source, which fires no Equipment.changed (GDD 7.2: the Character tab shows
## the new numbers). Another tab rebuilds the list when it switches back (set_tab).
func _on_talent_points_changed() -> void:
	_refresh_tab_labels()
	if active_tab == CHARACTER_TAB:
		_refresh_stats(class_data())


func _build_doll() -> Control:
	var doll := UiTheme.vbox(int(DOLL_GAP) + 2)
	doll.custom_minimum_size.x = _doll_width()
	var top := UiTheme.hbox(int(DOLL_GAP))
	doll.add_child(top)
	top.add_child(_icon_column(LEFT_SLOTS))
	top.add_child(_build_stage())
	var right := _icon_column(RIGHT_SLOTS)
	top.add_child(right)
	var bottom := UiTheme.hbox(int(DOLL_GAP))
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	doll.add_child(bottom)
	for i in BOTTOM_SLOTS.size():
		if i == 2 or i == 4:
			var gap := Control.new()
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			gap.custom_minimum_size.x = BOTTOM_GROUP_GAP - DOLL_GAP * 2.0
			bottom.add_child(gap)
		bottom.add_child(_add_cell(BOTTOM_SLOTS[i], -1, DOLL_ICON))
	return doll


func _icon_column(slots: Array[Items.EquipSlot]) -> VBoxContainer:
	var column := UiTheme.vbox(int(DOLL_GAP))
	for s in slots:
		column.add_child(_add_cell(s, -1, DOLL_ICON))
	return column


func _build_stage() -> Control:
	var stage_frame := UiTheme.panel(UiTheme.INSET_PANEL)
	var st := UiTheme.inset_style()
	st.content_margin_left = 2
	st.content_margin_right = 2
	st.content_margin_top = 2
	st.content_margin_bottom = 2
	st.inner_shadow = 16
	stage_frame.add_theme_stylebox_override(&"panel", st.rebuild())
	stage_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stage := Control.new()
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.clip_contents = true
	stage_frame.add_child(stage)
	_preview_glow = TextureRect.new()
	_preview_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_preview_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_glow.texture = _glow_texture(slot.color if slot != null else UiTheme.GOLD)
	stage.add_child(_preview_glow)
	_preview = OnionPreview.create()
	_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview.offset_bottom = -22
	stage.add_child(_preview)
	_spec_label = UiTheme.centered_label("", &"", 16, UiTheme.TEXT_DIM)
	_spec_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_spec_label.offset_top = -24
	_spec_label.offset_bottom = -3
	stage.add_child(_spec_label)
	return stage_frame


func _build_side() -> Control:
	var side := UiTheme.vbox(6)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stats_panel := UiTheme.panel(UiTheme.INSET_PANEL)
	stats_panel.name = "StatsInset"
	stats_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Nothing in the list may draw past the inset (the names clip, see _refresh_stats).
	stats_panel.clip_contents = true
	var inset := UiTheme.inset_style()
	inset.content_margin_left = STAT_INSET_PAD
	inset.content_margin_right = STAT_INSET_PAD
	stats_panel.add_theme_stylebox_override(&"panel", inset)
	side.add_child(stats_panel)
	_stats_grid = GridContainer.new()
	_stats_grid.columns = 2
	_stats_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats_grid.add_theme_constant_override(&"h_separation", STAT_COLUMN_GAP)
	_stats_grid.add_theme_constant_override(&"v_separation", 1)
	stats_panel.add_child(_stats_grid)

	var bag_head := UiTheme.hbox(8)
	bag_head.add_child(UiTheme.label("Backpack", &"", 20, UiTheme.GOLD))
	bag_head.get_child(0).add_theme_font_override(&"font", UiTheme.bold_font())
	bag_head.add_child(UiTheme.spacer())
	_bag_count = UiTheme.label("0 / %d" % Items.BACKPACK_SIZE, &"", UiTheme.FONT_SMALL, UiTheme.TEXT_DIM)
	bag_head.add_child(_bag_count)
	side.add_child(bag_head)
	var grid := GridContainer.new()
	grid.columns = BAG_COLUMNS
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override(&"h_separation", int(BAG_GAP))
	grid.add_theme_constant_override(&"v_separation", int(BAG_GAP))
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for i in Items.BACKPACK_SIZE:
		grid.add_child(_add_cell(-1, i, BAG_ICON))
	side.add_child(grid)
	return side


func _build_prompt_row() -> HBoxContainer:
	var row := UiTheme.hbox(10)
	row.custom_minimum_size.y = 28
	_prompt_holder = UiTheme.hbox(14)
	row.add_child(_prompt_holder)
	row.add_child(UiTheme.spacer())
	_context_label = UiTheme.label("", &"", UiTheme.FONT_SMALL, UiTheme.TEXT_DIM)
	_context_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_context_label)
	return row


func _build_menu() -> void:
	_menu_panel = PanelContainer.new()
	_menu_panel.name = "ActionMenu"
	_menu_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_panel.z_index = 10
	var ms := UiTheme.stone_style(UiTheme.GOLD, Color(0.07, 0.06, 0.05, 0.98))
	ms.content_margin_left = 10
	ms.content_margin_right = 10
	ms.content_margin_top = 8
	ms.content_margin_bottom = 8
	ms.shadow_size = 14
	ms.shadow_color = Color(0, 0, 0, 0.7)
	_menu_panel.add_theme_stylebox_override(&"panel", ms.rebuild())
	_menu_box = UiTheme.vbox(2)
	_menu_panel.add_child(_menu_box)
	_menu_panel.visible = false
	add_child(_menu_panel)


func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.name = "Toast"
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.z_index = 12
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(0.03, 0.025, 0.02, 0.9)
	ts.border_color = Color(UiTheme.GOLD_BORDER, 0.8)
	ts.set_border_width_all(1)
	ts.set_corner_radius_all(6)
	ts.content_margin_left = 14
	ts.content_margin_right = 14
	ts.content_margin_top = 4
	ts.content_margin_bottom = 5
	ts.shadow_color = Color(0, 0, 0, 0.5)
	ts.shadow_size = 6
	_toast.add_theme_stylebox_override(&"panel", ts)
	var row := UiTheme.hbox(8)
	_toast.add_child(row)
	_toast_coin = UiIcon.create(UiIcon.Kind.COIN, Vector2(24, 24))
	_toast_coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_toast_coin)
	_toast_label = RichTextLabel.new()
	_toast_label.bbcode_enabled = true
	_toast_label.fit_content = true
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_toast_label.scroll_active = false
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label.add_theme_font_size_override(&"normal_font_size", 20)
	_toast_label.add_theme_constant_override(&"outline_size", 5)
	_toast_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_toast_label)
	_toast.visible = false
	add_child(_toast)


func _add_cell(equip_slot: int, bag_index: int, icon_size: float) -> ItemIcon:
	var cell := Cell.new()
	cell.equip_slot = equip_slot
	cell.bag_index = bag_index
	cell.icon = ItemIcon.create(null, icon_size)
	cell.icon.name = ("Bag%d" % bag_index) if bag_index >= 0 else String(Items.EquipSlot.keys()[equip_slot]).capitalize().replace(" ", "")
	cell.icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cell.icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if equip_slot >= 0:
		cell.icon.set_empty_slot(equip_slot)
	_cells.append(cell)
	return cell.icon


## Design-layout centres of every cell (the containers place the icons the same way).
func _layout_cells() -> void:
	var doll_w := _doll_width()
	var step := DOLL_ICON + DOLL_GAP
	var half := DOLL_ICON * 0.5
	var bottom_y := LEFT_SLOTS.size() * step + 2.0 + half
	var bottom_w := BOTTOM_SLOTS.size() * DOLL_ICON + 3 * DOLL_GAP + 2 * BOTTOM_GROUP_GAP
	var side_x := doll_w + BODY_GAP
	var side_w := DESIGN_SIZE.x - 28.0 - side_x
	var bag_w := BAG_COLUMNS * BAG_ICON + (BAG_COLUMNS - 1) * BAG_GAP
	var body_h := 336.0
	var bag_top := body_h - 2 * BAG_ICON - BAG_GAP
	for cell in _cells:
		if cell.bag_index >= 0:
			var c := cell.bag_index % BAG_COLUMNS
			var r := floori(cell.bag_index / float(BAG_COLUMNS))
			cell.pos = Vector2(side_x + (side_w - bag_w) * 0.5 + c * (BAG_ICON + BAG_GAP) + BAG_ICON * 0.5,
				bag_top + r * (BAG_ICON + BAG_GAP) + BAG_ICON * 0.5)
		elif cell.equip_slot in LEFT_SLOTS:
			cell.pos = Vector2(half, LEFT_SLOTS.find(cell.equip_slot) * step + half)
		elif cell.equip_slot in RIGHT_SLOTS:
			cell.pos = Vector2(doll_w - half, RIGHT_SLOTS.find(cell.equip_slot) * step + half)
		else:
			var i := BOTTOM_SLOTS.find(cell.equip_slot)
			var x := (doll_w - bottom_w) * 0.5 + i * step + half
			x += (BOTTOM_GROUP_GAP - DOLL_GAP) * floorf(i / 2.0)
			cell.pos = Vector2(x, bottom_y)


func _doll_width() -> float:
	return BOTTOM_SLOTS.size() * DOLL_ICON + 3 * DOLL_GAP + 2 * BOTTOM_GROUP_GAP


# --- Refresh helpers ---------------------------------------------------------------------------

func _bind(eq: Equipment) -> void:
	if eq == _equipment:
		return
	if _equipment != null and _equipment.changed.is_connected(refresh):
		_equipment.changed.disconnect(refresh)
	_equipment = eq
	if eq != null:
		eq.changed.connect(refresh)


func _refresh_header(eq: Equipment, cls: ClassData) -> void:
	_class_label.text = cls.display_name if cls != null else ""
	_ilvl_value.text = str(floori(eq.average_item_level())) if eq != null else "0"


func _refresh_stats(cls: ClassData) -> void:
	for c in _stats_grid.get_children():
		_stats_grid.remove_child(c)
		c.queue_free()
	var stats := _stat_block()
	for row in stat_rows(stats, cls):
		var stat: StringName = row[0]
		var v: float = row[1]
		var cell := UiTheme.hbox(STAT_VALUE_GAP)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var primary := cls != null and stat == cls.primary_stat
		var name_label := UiTheme.label(_stat_name(stat), &"", UiTheme.FONT_SMALL, UiTheme.GOLD if primary else UiTheme.TEXT_DIM)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# The name takes what the value leaves and is cut with an ellipsis: its text never sets
		# the column's width (the two columns share the inset evenly).
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.custom_minimum_size.x = 0
		cell.add_child(name_label)
		var value_label := UiTheme.label(_stat_text(stat, v), &"", UiTheme.FONT_SMALL, UiTheme.RED if v < 0.0 else UiTheme.TEXT)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cell.add_child(value_label)
		_stats_grid.add_child(cell)


## [stat id, value] pairs of the compact stat list ("max_hp" = Max HP).
static func stat_rows(stats: StatBlock, cls: ClassData) -> Array[Array]:
	var order: Array[StringName] = []
	var primary: StringName = cls.primary_stat if cls != null else Stats.STRENGTH
	order.append(primary)
	order.append_array(LISTED_STATS)
	var rows: Array[Array] = []
	for stat in order:
		rows.append([stat, _stat_value(stats, stat)])
	var limit := MAX_STAT_ROWS * 2
	var extras: Array[StringName] = []
	extras.append_array(PRIMARY_STATS)
	extras.append_array(Stats.ALL)
	for stat in extras:
		if rows.size() >= limit:
			break
		if stat in order or stat in UNLISTED_STATS:
			continue
		var v := _stat_value(stats, stat)
		if absf(v) >= 0.05:
			rows.append([stat, v])
			order.append(stat)
	return rows


func _refresh_side(eq: Equipment, cls: ClassData) -> void:
	var used := eq.backpack.size() if eq != null else 0
	_bag_count.text = "%d / %d" % [used, Items.BACKPACK_SIZE]
	_bag_count.add_theme_color_override(&"font_color", UiTheme.RED if used >= Items.BACKPACK_SIZE else UiTheme.TEXT_DIM)
	if cls != null and eq != null:
		var worn := 0
		for s in [Items.EquipSlot.HEAD, Items.EquipSlot.SHOULDERS, Items.EquipSlot.CHEST, Items.EquipSlot.WRIST,
				Items.EquipSlot.HANDS, Items.EquipSlot.WAIST, Items.EquipSlot.LEGS, Items.EquipSlot.FEET]:
			var it := eq.get_item(s)
			if it != null and it.armor_type == cls.armor_type:
				worn += 1
		var armor_name: String = Items.ARMOR_TYPE_NAMES.get(cls.armor_type, "")
		if eq.armor_spec_active():
			_spec_label.text = "%s 8/8 · +10%% %s" % [armor_name, Stats.display_name(cls.primary_stat)]
			_spec_label.add_theme_color_override(&"font_color", UiTheme.GREEN)
		else:
			_spec_label.text = "%s armor %d / 8" % [armor_name, worn]
			_spec_label.add_theme_color_override(&"font_color", UiTheme.TEXT_DIM)
		_preview.show_class(cls, slot.color)
		if _preview.model != null:
			_preview.model.set_weapons(eq.main_weapon(), eq.off_weapon())
	else:
		_spec_label.text = ""


func _stat_block() -> StatBlock:
	if slot == null or slot.player == null:
		return null
	return slot.player.get(&"stats") as StatBlock


static func _stat_value(stats: StatBlock, stat: StringName) -> float:
	if stats == null:
		return 0.0
	if stat == &"max_hp":
		return stats.max_hp()
	return stats.get_stat(stat)


static func _stat_name(stat: StringName) -> String:
	return SHORT_STAT_NAMES.get(stat, Stats.display_name(stat))


static func _stat_text(stat: StringName, v: float) -> String:
	var text := ItemTooltip.fmt_number(v, 1)
	return text + ("%" if Stats.is_percent(stat) else "")


# --- Selection, tooltip, prompts ----------------------------------------------------------------

func _select(i: int) -> void:
	if i == selected:
		return
	selected = i
	_update_selection()


func _update_selection() -> void:
	var cursor := (slot.color if slot != null else UiTheme.GOLD).lightened(0.25)
	for i in _cells.size():
		_cells[i].icon.set_selected(_focused and i == selected, cursor)
	_update_tooltip()
	_update_prompts()


## The selected item's tooltip – hidden while the action menu is open: both use the panel's
## half away from the selection (_place_tooltip / _place_menu), and the menu's title names the
## item anyway.
func _update_tooltip() -> void:
	var it := selected_item()
	if not _focused or it == null or active_tab != CHARACTER_TAB or mode == Mode.MENU:
		tooltip.visible = false
		return
	var compare: ItemInstance = null
	if _cells[selected].bag_index >= 0:
		compare = ItemTooltip.equipped_for_compare(it, equipment())
	tooltip.comparison_visible = comparison
	tooltip.viewer_equipment = equipment()
	tooltip.show_item(it, class_data(), compare)
	if is_inside_tree():
		_place_tooltip.call_deferred()


func _update_prompts() -> void:
	if active_tab == TRAINER_TAB:
		_update_trainer_prompts()
		return
	if active_tab == TALENTS_TAB:
		_update_tab_prompts("talents", talents.prompt_spec(), talents.context_text())
		return
	var cell := _cells[selected]
	var it := selected_item()
	var key := "%d:%s:%s:%s:%s" % [mode, it != null, cell.bag_index >= 0, comparison, _focused]
	_context_label.text = _cell_name(cell) if mode == Mode.BROWSE else ""
	if key == _prompt_key:
		return
	_prompt_key = key
	for c in _prompt_holder.get_children():
		_prompt_holder.remove_child(c)
		c.queue_free()
	var input := slot.input if slot != null else null
	var items: Array = []
	if mode == Mode.MENU:
		items = [[_glyph(input, PlayerInput.Pad.A), "Select"], [_glyph(input, PlayerInput.Pad.B), "Back"]]
	elif it != null:
		items.append([_glyph(input, PlayerInput.Pad.A), "Actions"])
		if cell.bag_index >= 0:
			items.append([_glyph(input, PlayerInput.Pad.X), "Sell"])
			items.append([_glyph(input, PlayerInput.Pad.Y), "Compare: %s" % ("On" if comparison else "Off")])
	else:
		items.append([UiGlyph.nav(24.0), "Select an item"])
	var row := UiTheme.prompt_row(items, UiTheme.FONT_SMALL)
	row.add_theme_constant_override(&"separation", 14)
	_prompt_holder.add_child(row)


func _update_trainer_prompts() -> void:
	_update_tab_prompts("trainer", trainer.prompt_spec(), trainer.context_text())


## The prompt row of the Trainer / Talents tab ([param tab_key]): [param spec] = [button, text]
## pairs (PlayerInput.Pad or TrainerTab.NAV_PROMPT / NAV_PROMPT_SIDEWAYS), [param context] the
## text on the left. Rebuilt only when something changed.
func _update_tab_prompts(tab_key: String, spec: Array, context: String) -> void:
	_context_label.text = context
	var input := slot.input if slot != null else null
	var key := "%s:%s:%s" % [tab_key, str(spec), _focused]
	if key == _prompt_key:
		return
	_prompt_key = key
	for c in _prompt_holder.get_children():
		_prompt_holder.remove_child(c)
		c.queue_free()
	var items: Array = []
	for pair: Array in spec:
		var button := int(pair[0])
		var glyph: UiGlyph
		if button == TrainerTab.NAV_PROMPT:
			glyph = UiGlyph.nav(24.0, true)
		elif button == TrainerTab.NAV_PROMPT_SIDEWAYS:
			glyph = UiGlyph.nav(24.0)
		else:
			glyph = _glyph(input, button as PlayerInput.Pad)
		items.append([glyph, pair[1]])
	var row := UiTheme.prompt_row(items, UiTheme.FONT_SMALL)
	row.add_theme_constant_override(&"separation", 14)
	_prompt_holder.add_child(row)


func _on_trainer_message(bbcode: String, plain: String, color: Color, coin: bool) -> void:
	_message(bbcode, plain, color, coin)


func _on_trainer_prompts_changed() -> void:
	if active_tab == TRAINER_TAB and _prompt_holder != null:
		_update_prompts()


func _on_talents_message(bbcode: String, plain: String, color: Color, coin: bool) -> void:
	_message(bbcode, plain, color, coin)


func _on_talents_prompts_changed() -> void:
	if active_tab == TALENTS_TAB and _prompt_holder != null:
		_update_prompts()


func _glyph(input: PlayerInput, button: PlayerInput.Pad) -> UiGlyph:
	return UiGlyph.for_input(input, button, 24.0) if input != null else UiGlyph.pad(button, 24.0)


func _cell_name(cell: Cell) -> String:
	if cell.bag_index >= 0:
		return "Backpack %d" % (cell.bag_index + 1)
	return Items.EQUIP_SLOT_NAMES.get(cell.equip_slot, "")


func _render_menu() -> void:
	for c in _menu_box.get_children():
		_menu_box.remove_child(c)
		c.queue_free()
	if _menu_stack.is_empty():
		_menu_panel.visible = false
		return
	var level: Dictionary = _menu_stack.back()
	var title := UiTheme.label(str(level["title"]), &"", 20, level["color"])
	title.add_theme_font_override(&"font", UiTheme.bold_font())
	_menu_box.add_child(title)
	var rule := HSeparator.new()
	rule.add_theme_constant_override(&"separation", 4)
	_menu_box.add_child(rule)
	var entries: Array = level["entries"]
	for i in entries.size():
		var e: MenuEntry = entries[i]
		var row := PanelContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rs := StyleBoxFlat.new()
		rs.content_margin_left = 10
		rs.content_margin_right = 10
		rs.content_margin_top = 2
		rs.content_margin_bottom = 3
		rs.set_corner_radius_all(4)
		if i == int(level["index"]):
			rs.bg_color = Color(0.36, 0.25, 0.1, 0.95)
			rs.border_color = UiTheme.GOLD_BRIGHT
			rs.set_border_width_all(1)
		else:
			rs.bg_color = Color(0, 0, 0, 0)
		row.add_theme_stylebox_override(&"panel", rs)
		var line := UiTheme.hbox(14)
		row.add_child(line)
		var col := e.color if e.enabled else Color(0.48, 0.45, 0.42)
		var l := UiTheme.label(e.label, &"", 20, col)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(l)
		if e.detail != "":
			var dcol := UiTheme.GOLD if e.enabled and e.label == "Sell" else (UiTheme.TEXT_DIM if e.enabled else Color(0.75, 0.3, 0.25))
			line.add_child(UiTheme.label(e.detail, &"", UiTheme.FONT_SMALL, dcol))
		_menu_box.add_child(row)
	_menu_panel.visible = true
	_menu_panel.reset_size()
	if is_inside_tree():
		_place_menu.call_deferred()


func _place_menu() -> void:
	if not _menu_panel.visible:
		return
	_menu_panel.reset_size()
	var icon := _cells[selected].icon
	var inv := get_global_transform_with_canvas().affine_inverse()
	var r := inv * icon.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, icon.size)
	var ms := _menu_panel.size
	var x := r.end.x + 8.0 if r.get_center().x < size.x * 0.5 else r.position.x - 8.0 - ms.x
	var y := r.position.y - 4.0
	# Keep it inside the panel and above the prompt row.
	_menu_panel.position = Vector2(clampf(x, 6.0, size.x - ms.x - 6.0), clampf(y, 6.0, size.y - ms.y - 44.0))


## The tooltip floats beside the panel on the side facing the screen centre, level with the
## selected icon and kept inside the visible area. With [member tooltip_inside] it stays over the
## panel (scaled down to its height, at least MIN_INSIDE_TOOLTIP_FIT); one taller than that hangs
## from the panel's top edge downwards (top-corner panels) or rises from its bottom edge (bottom
## corners), over the middle of the screen – and shrinks further if it would otherwise reach the
## column's other corner panel ([method _inside_tooltip_reach]).
func _place_tooltip() -> void:
	if not tooltip.visible or not is_inside_tree():
		return
	var to_canvas := get_global_transform_with_canvas()
	var panel_rect := to_canvas * Rect2(Vector2.ZERO, size)
	var icon := _cells[selected].icon
	var icon_rect := icon.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, icon.size)
	var tip := tooltip.get_combined_minimum_size()
	tooltip.size = tip
	var view := get_viewport_rect()
	var tip_h := maxf(1.0, tip.y * to_canvas.get_scale().y)
	var fit := clampf((view.size.y - 8.0) / tip_h, MIN_TOOLTIP_FIT, 1.0)
	if tooltip_inside:
		# Inside the panel a tooltip taller than the panel is scaled down to fit it (it would
		# otherwise spill over the neighbouring player's panel) – but only so far, and never so
		# little that it reaches the panel at the column's other end.
		var room := minf(panel_rect.end.y, view.end.y - 4.0) - maxf(panel_rect.position.y, view.position.y + 4.0)
		var reach := maxf(room, _inside_tooltip_reach(panel_rect, view))
		fit = minf(clampf(room / tip_h, MIN_INSIDE_TOOLTIP_FIT, 1.0), reach / tip_h)
	tooltip.scale = Vector2.ONE * fit
	var tip_size := tip * to_canvas.get_scale() * fit
	var gap := 10.0 * to_canvas.get_scale().x
	var x := panel_rect.end.x + gap
	if tooltip_inside:
		# Over the panel, on the half that does not hold the selected icon.
		x = panel_rect.position.x + gap
		if icon_rect.get_center().x < panel_rect.get_center().x:
			x = panel_rect.end.x - gap - tip_size.x
	elif panel_rect.get_center().x > view.get_center().x:
		x = panel_rect.position.x - gap - tip_size.x
	x = clampf(x, view.position.x + 4.0, maxf(view.position.x + 4.0, view.end.x - tip_size.x - 4.0))
	var top := panel_rect.position.y if tooltip_inside else view.position.y
	var bottom := panel_rect.end.y if tooltip_inside else view.end.y
	top = maxf(top, view.position.y + 4.0)
	bottom = minf(bottom, view.end.y - 4.0)
	var y := clampf(icon_rect.position.y - 6.0, top, maxf(top, bottom - tip_size.y))
	if tip_size.y > bottom - top + 0.5:
		# Taller than the panel even at the minimum fit: out over the panel's inner edge.
		y = top if panel_rect.get_center().y <= view.get_center().y else bottom - tip_size.y
		y = clampf(y, view.position.y + 4.0, maxf(view.position.y + 4.0, view.end.y - 4.0 - tip_size.y))
	tooltip.position = to_canvas.affine_inverse() * Vector2(x, y)


## The item tooltip's global rect while it is shown and reaches out of the panel (a tall one
## with [member tooltip_inside], over the free band between two corner panels); an empty Rect2
## while it is hidden or stays over the panel. The shop keeps its tooltips clear of it
## (ShopPanel.tooltip_obstacles).
func outside_tooltip_rect() -> Rect2:
	if tooltip == null or not tooltip.visible or not is_visible_in_tree():
		return Rect2()
	var r := tooltip.get_global_transform() * Rect2(Vector2.ZERO, tooltip.size)
	return Rect2() if (get_global_transform() * Rect2(Vector2.ZERO, size)).grow(0.5).encloses(r) else r


## How tall (canvas px) a [member tooltip_inside] tooltip may get when it reaches out of the
## panel: from the panel's outer edge (top for the top corners, bottom for the bottom ones) to
## TOOLTIP_NEIGHBOUR_GAP before the column's other corner panel (the mirror image of this one,
## [member tooltip_column_mate]), or to the screen edge.
func _inside_tooltip_reach(panel_rect: Rect2, view: Rect2) -> float:
	var mirror_y := view.position.y + view.end.y
	if panel_rect.get_center().y <= view.get_center().y:
		var end := view.end.y - 4.0
		if tooltip_column_mate:
			end = minf(end, mirror_y - panel_rect.end.y - TOOLTIP_NEIGHBOUR_GAP)
		return end - maxf(panel_rect.position.y, view.position.y + 4.0)
	var start := view.position.y + 4.0
	if tooltip_column_mate:
		start = maxf(start, mirror_y - panel_rect.position.y + TOOLTIP_NEIGHBOUR_GAP)
	return minf(panel_rect.end.y, view.end.y - 4.0) - start


# --- Messages -----------------------------------------------------------------------------------

## Shows [param bbcode] in the toast for MESSAGE_TIME seconds; [param plain] is stored in
## [member last_message] (defaults to the bbcode text).
func _message(bbcode: String, plain: String = "", color: Color = UiTheme.TEXT, coin: bool = false) -> void:
	last_message = plain if plain != "" else bbcode
	_toast_label.text = "[color=#%s]%s[/color]" % [color.to_html(false), bbcode]
	_toast_coin.visible = coin
	_toast.visible = true
	_toast.modulate.a = 1.0
	_toast_time = MESSAGE_TIME
	_toast.reset_size()
	if is_inside_tree():
		_place_toast.call_deferred()


func _place_toast() -> void:
	_toast.reset_size()
	_toast.position = Vector2((size.x - _toast.size.x) * 0.5, size.y - 44.0 - _toast.size.y)


static func _bb_item(it: ItemInstance) -> String:
	if it == null:
		return ""
	return "[color=#%s]%s[/color]" % [_rarity_color(it).to_html(false), it.display_name.replace("[", "(")]


static func _rarity_color(it: ItemInstance) -> Color:
	return UiTheme.RARITY_COLORS[clampi(it.rarity, 0, UiTheme.RARITY_COLORS.size() - 1)]


# --- Misc -----------------------------------------------------------------------------------------

func _item_at(cell: Cell) -> ItemInstance:
	var eq := equipment()
	if eq == null:
		return null
	if cell.bag_index >= 0:
		return eq.backpack[cell.bag_index] if cell.bag_index < eq.backpack.size() else null
	return eq.get_item(cell.equip_slot as Items.EquipSlot)


func _cell_index(equip_slot: int, bag_index: int) -> int:
	for i in _cells.size():
		var c := _cells[i]
		if bag_index >= 0 and c.bag_index == bag_index:
			return i
		if bag_index < 0 and c.bag_index < 0 and c.equip_slot == equip_slot:
			return i
	return -1


func _teammates() -> Array[PlayerSlot]:
	var out: Array[PlayerSlot] = []
	for s in PlayerManager.get_slots():
		if s != null and s != slot and _equipment_of(s) != null:
			out.append(s)
	return out


static func _equipment_of(s: PlayerSlot) -> Equipment:
	if s == null or s.player == null or not is_instance_valid(s.player):
		return null
	return s.player.get(&"equipment") as Equipment


func _frame_style(focused: bool) -> UiFrameStyle:
	var col := slot.color if slot != null else UiTheme.GOLD
	var s := UiTheme.card_style(col.lightened(0.15) if focused else UiTheme.GOLD_BORDER)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 12
	s.content_margin_bottom = 10
	if focused:
		s.glow = Color(col, 0.4)
		s.glow_size = 14
	return s.rebuild()


func _glow_texture(c: Color) -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.72)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 128
	tex.height = 128
	var g := Gradient.new()
	g.set_color(0, Color(c.lightened(0.1), 0.5))
	g.set_color(1, Color(c.darkened(0.6), 0.0))
	tex.gradient = g
	return tex


func _enter_tree() -> void:
	if self not in _open_panels:
		_open_panels.append(self)


func _exit_tree() -> void:
	_open_panels.erase(self)


func _ready() -> void:
	refresh()


func _process(delta: float) -> void:
	if _toast.visible:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time / 0.5, 0.0, 1.0)
		if _toast_time <= 0.0:
			_toast.visible = false
	if tooltip.visible:
		_place_tooltip()
	if _menu_panel.visible:
		_place_menu()
