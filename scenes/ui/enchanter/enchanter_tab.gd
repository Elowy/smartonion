class_name EnchanterTab
extends Control
## The Enchanter tab of a player's between-wave panel (GDD 5.7, 12; PlayerPanel tab 4, M6a): the
## hero's items – the equipped ones first, then the backpack – as a grid of icons (a pip row
## under each icon: one per enchant, hollow for a free enchant slot) next to the detail of the
## selected item: name, kind, its enchants as EnchanterRows (rank I-V, name, the green text at
## that rank) plus an "Imbue" row while it has a free slot, and the price of its next action in
## gold and Arcane Dust (Enchanter.gold_price / dust_price: the same for every action on this
## item and doubling with each one; red when the shared wallet or the Dust pile cannot pay).
## Same body size as the Trainer / Talents tabs (PlayerPanel.DESIGN_SIZE scaled into the
## player's corner). The label shows the team's Dust ("Enchanter (12)", [method tab_label]).
## Input (handle_input, the panel's per-player PlayerInput – never the global Input):
##  - items: up / down / left / right move over the grid (equipped block, then the backpack block),
##    A or right at the grid's edge steps into the enchants of the item;
##  - enchants: up / down pick a row, left or B goes back to the items; A empowers the picked
##    enchant (+1 rank, up to V) or, on the Imbue row, adds a new one; X rerolls the picked enchant
##    (a new random one that fits the slot, same rank). Refusals show their reason in red.
##  A price above HOLD_SHARE of the shared gold needs the button held for HOLD_TIME (the shop /
##  Trainer rule; the row fills up; letting go, moving or B cancels). While a hold runs the tab is
##  modal (PlayerPanel keeps LT / RT) and B cancels it – otherwise B only steps back from the
##  enchants (the only times it counts as used, so the Intermission can still unready with B).
## The work is Enchanter.perform (rules, gold + Dust through RunState, Equipment.changed);
## feedback goes out through [signal message]. While hidden (another tab, or the whole wave) wallet
## changes only mark the tab stale; it refreshes at the end of the frame it is shown in, unless
## an explicit refresh() came first (the TrainerTab rule).

## Text for the panel's toast: [param bbcode] shown, [param plain] kept as PlayerPanel.last_message.
signal message(bbcode: String, plain: String, color: Color, coin: bool)
## Something the prompt row shows changed (selection, focus, hold).
signal prompts_changed
## The team's Dust changed: the panel relabels its tab.
signal label_changed

enum Focus { ITEMS, ROWS }

const NAV_PROMPT := TrainerTab.NAV_PROMPT
const HOLD_TIME := ShopPanel.HOLD_TIME
const HOLD_SHARE := ShopPanel.HOLD_SHARE
## Icons per grid row and their size / gap (design pixels).
const COLUMNS := 5
const CELL := 46.0
const CELL_GAP := 5
const LIST_MARGIN := 6
const LIST_WIDTH := COLUMNS * CELL + (COLUMNS - 1) * CELL_GAP + 2 * LIST_MARGIN
const COLUMN_GAP := 8
const CAPTION_FONT := 15
const DETAIL_FONT := 16
const ROW_GAP := 4
const EQUIPPED_CAPTION := "Equipped"
const BACKPACK_CAPTION := "Backpack"
const EMPTY_TEXT := "No items to enchant"
const HINT_TEXT := "Empower, Reroll or Imbue. Every action on an item doubles its price."

var slot: PlayerSlot
## The hero's items in grid order: [member equipped_count] equipped ones, then the backpack.
var items: Array[ItemInstance] = []
var equipped_count := 0
## Index into [member items].
var selected := 0
var focus := Focus.ITEMS
## Index into [member rows] (valid in the ROWS focus).
var row_selected := 0
var cells: Array[Cell] = []
var rows: Array[EnchanterRow] = []
## Detail labels (tests read them).
var detail_name: Label
var detail_kind: Label
var detail_uses: Label
var detail_gold: Label
var detail_dust: Label
var detail_empower: Label
var detail_reroll: Label
var detail_hint: Label

var _focused := false
var _stale := false
## {"item", "action", "index", "gold", "button", "time"} while a button is held on an expensive action.
var _hold: Dictionary[String, Variant] = {}
var _equipped_caption: Label
var _backpack_caption: Label
var _equipped_grid: GridContainer
var _backpack_grid: GridContainer
var _rows_box: VBoxContainer
var _detail_box: VBoxContainer
var _price_row: HBoxContainer
var _coin: UiIcon
var _dust_icon: DustIcon


## An item icon of the grid: the ItemIcon plus the enchant pips under it (filled = an enchant,
## hollow = a free slot) and a dimmed look when the Enchanter has nothing to do with the item.
class Cell extends ItemIcon:
	var enchants := 0
	var free_slots := 0

	func set_pips(p_enchants: int, p_free: int) -> void:
		if p_enchants != enchants or p_free != free_slots:
			enchants = p_enchants
			free_slots = p_free
			queue_redraw()

	func _draw() -> void:
		super._draw()
		var total := mini(enchants + free_slots, 3)
		if total <= 0:
			return
		var step := 7.0
		var x0 := size.x * 0.5 - (total - 1) * step * 0.5
		var y := size.y - 6.0
		for i in total:
			var c := Vector2(x0 + i * step, y)
			if i < enchants:
				draw_circle(c, 3.0, Color(0, 0, 0, 0.8))
				draw_circle(c, 2.2, ItemTooltip.ENCHANT_GREEN)
			else:
				draw_circle(c, 3.0, Color(0, 0, 0, 0.8))
				draw_arc(c, 2.1, 0.0, TAU, 10, Color(0.72, 0.68, 0.6), 1.2, true)


static func create(p_slot: PlayerSlot) -> EnchanterTab:
	var t := EnchanterTab.new()
	t.slot = p_slot
	t.name = "EnchanterTab"
	t._build()
	return t


# --- Queries ---------------------------------------------------------------------------------

func player() -> Player:
	if slot == null or not is_instance_valid(slot.player):
		return null
	return slot.player as Player


func equipment() -> Equipment:
	var p := player()
	return p.equipment if p != null else null


## "Enchanter (12)": the tab's name with the team's Arcane Dust (the panel draws the sparkle).
func tab_label() -> String:
	return "%s (%d)" % [PlayerPanel.TAB_NAMES[PlayerPanel.ENCHANTER_TAB], RunState.arcane_dust]


func selected_item() -> ItemInstance:
	return items[selected] if selected >= 0 and selected < items.size() else null


func is_equipped(item: ItemInstance) -> bool:
	return items.find(item) >= 0 and items.find(item) < equipped_count


## The selected row (null without rows).
func selected_row() -> EnchanterRow:
	return rows[row_selected] if row_selected >= 0 and row_selected < rows.size() else null


## Enchant index of the selected row (-1 on the Imbue row or without rows).
func selected_enchant_index() -> int:
	var r := selected_row()
	return r.enchant_index if r != null else -1


func is_modal() -> bool:
	return not _hold.is_empty()


func is_holding() -> bool:
	return not _hold.is_empty()


## 0..1 progress of the running hold (0 when none).
func hold_progress() -> float:
	return clampf(float(_hold.get("time", 0.0)) / HOLD_TIME, 0.0, 1.0) if not _hold.is_empty() else 0.0


## GDD 10 / shop rule: a price above HOLD_SHARE of the shared gold needs the button held.
static func needs_hold(gold_price: int) -> bool:
	return gold_price > RunState.gold * HOLD_SHARE


## Why [param action] on the selected item (enchant [param index]) cannot be done now ("" = it
## can): the Enchanter's rule first, then the wallet.
func block_reason(action: Enchanter.Action, index: int = -1) -> String:
	var item := selected_item()
	if item == null:
		return Enchanter.REASON_NO_ITEM
	var rule := Enchanter.blocked_reason(item, action, index)
	return rule if rule != "" else Enchanter.afford_reason(item)


## Why the Enchanter can do nothing with the selected item ("" = it can do something).
func item_reason() -> String:
	var item := selected_item()
	if item == null:
		return EMPTY_TEXT
	if item.rarity >= Items.Rarity.ARTIFACT:
		return Enchanter.REASON_ARTIFACT
	if Enchanter.is_enchantable(item):
		return ""
	if item.rarity < Items.Rarity.UNCOMMON:
		return Enchanter.REASON_COMMON
	return "Nothing left to change on this item"


## Grid position (column, row) of item [param index]: the equipped block first, the backpack
## block starting on a new row under it.
func grid_pos(index: int) -> Vector2i:
	if index < equipped_count:
		return Vector2i(index % COLUMNS, index / COLUMNS)
	var j := index - equipped_count
	return Vector2i(j % COLUMNS, ceili(equipped_count / float(COLUMNS)) + j / COLUMNS)


## The item at grid cell (column, row), -1 when there is none.
func index_at(col: int, row: int) -> int:
	for i in items.size():
		if grid_pos(i) == Vector2i(col, row):
			return i
	return -1


# --- Actions -----------------------------------------------------------------------------------

## Rebuilds the item grid and the detail from the hero's equipment; the selection follows the
## selected item when it is still there.
func refresh() -> void:
	_stale = false
	var keep := selected_item()
	_collect()
	if keep != null and items.has(keep):
		selected = items.find(keep)
	else:
		selected = clampi(selected, 0, maxi(items.size() - 1, 0))
	_sync_cells()
	_rebuild_rows()
	if not _hold.is_empty() and not _hold_still_valid():
		_hold.clear()
	_update_selection()


## Whether this tab receives its player's input (selection outline, no hold without it).
func set_focused(on: bool) -> void:
	_focused = on
	if not on:
		_hold.clear()
	_update_selection()


func select_item(index: int) -> void:
	if index < 0 or index >= items.size() or index == selected:
		return
	selected = index
	row_selected = 0
	_hold.clear()
	_rebuild_rows()
	_update_selection()


## Moves the item selection one cell in [param dir]. Right at the grid's edge steps into the
## item's enchants. True when something moved.
func move_item(dir: Vector2i) -> bool:
	if items.is_empty():
		return false
	var p := grid_pos(selected)
	if dir.y != 0:
		var target := _nearest_in_row(p.y + signi(dir.y), p.x)
		if target >= 0:
			select_item(target)
			return true
		return false
	if dir.x != 0:
		var target := index_at(p.x + signi(dir.x), p.y)
		if target >= 0:
			select_item(target)
			return true
		if dir.x > 0 and not rows.is_empty():
			enter_rows()
			return true
	return false


## A (or right at the edge): from the items into the selected item's enchants. An item the
## Enchanter can do nothing with says why.
func enter_rows() -> void:
	if rows.is_empty():
		var reason := item_reason()
		if reason != "":
			_say(reason, "", UiTheme.RED)
		return
	focus = Focus.ROWS
	row_selected = clampi(row_selected, 0, rows.size() - 1)
	_update_selection()


## Back from the enchants to the item grid.
func leave_rows() -> void:
	if focus == Focus.ITEMS:
		return
	focus = Focus.ITEMS
	_hold.clear()
	_update_selection()


func move_row(step: int) -> void:
	if rows.is_empty() or step == 0:
		return
	var i := clampi(row_selected + signi(step), 0, rows.size() - 1)
	if i == row_selected:
		return
	row_selected = i
	_hold.clear()
	_update_selection()


## A on the picked row: Empower the enchant, or Imbue on the Imbue row. Starts a hold when the
## gold part costs more than HOLD_SHARE of the wallet.
func press_primary() -> void:
	var row := selected_row()
	if row == null:
		return
	if row.is_imbue():
		_start(Enchanter.Action.IMBUE, -1, PlayerInput.Pad.A)
	else:
		_start(Enchanter.Action.EMPOWER, row.enchant_index, PlayerInput.Pad.A)


## X on the picked row: Reroll the enchant (the Imbue row has none).
func press_secondary() -> void:
	var row := selected_row()
	if row == null:
		return
	if row.is_imbue():
		_say("Imbue adds a new enchant – press A", "", UiTheme.TEXT_DIM)
		return
	_start(Enchanter.Action.REROLL, row.enchant_index, PlayerInput.Pad.X)


## Does [param action] on the selected item now (no hold check) with feedback; true on success.
func try_act(action: Enchanter.Action, index: int = -1) -> bool:
	var item := selected_item()
	var eq := equipment()
	if item == null or eq == null:
		_say(Enchanter.REASON_NO_ITEM, "", UiTheme.RED)
		return false
	var out := Enchanter.perform(eq, slot.index if slot != null else -1, item, action, index)
	if not out.ok:
		_say(out.reason, "", UiTheme.RED)
		return false
	_announce(out)
	refresh()
	if action == Enchanter.Action.IMBUE and out.index >= 0 and out.index < rows.size():
		row_selected = out.index
		_update_selection()
	return true


## Called every frame while the tab has its player's input; [param delta] runs the hold timer.
## Returns whether a press was used (B only while it cancels a hold or steps back).
func handle_input(input: PlayerInput, delta: float) -> bool:
	if input == null:
		return false
	var nav := input.nav_just_pressed()
	var used := false
	var b_used := false
	if not _hold.is_empty():
		if input.just_pressed(PlayerInput.Pad.B):
			used = true
			b_used = true
			_cancel_hold()
		elif nav != Vector2i.ZERO or not input.is_pressed(int(_hold["button"]) as PlayerInput.Pad) or not _hold_still_valid():
			_cancel_hold()
		else:
			_hold["time"] = float(_hold["time"]) + delta
			if float(_hold["time"]) >= HOLD_TIME:
				var action := _hold["action"] as Enchanter.Action
				var index := int(_hold["index"])
				_hold.clear()
				try_act(action, index)
			_update_hold_visual()
	if focus == Focus.ITEMS:
		if nav != Vector2i.ZERO:
			move_item(nav)
			used = true
		if input.just_pressed(PlayerInput.Pad.A):
			enter_rows()
			used = true
	else:
		if nav.y != 0:
			move_row(nav.y)
			used = true
		elif nav.x < 0:
			leave_rows()
			used = true
		if input.just_pressed(PlayerInput.Pad.B) and not b_used:
			leave_rows()
			used = true
		if focus == Focus.ROWS and _hold.is_empty():
			if input.just_pressed(PlayerInput.Pad.A):
				press_primary()
				used = true
			elif input.just_pressed(PlayerInput.Pad.X):
				press_secondary()
				used = true
	return used


## Button prompts for the panel's prompt row: [button, text] pairs, button a PlayerInput.Pad or
## NAV_PROMPT. Plain data, so the panel only builds glyphs when the row changes.
func prompt_spec() -> Array:
	var items_out: Array = []
	if focus == Focus.ROWS and selected_row() != null:
		var row := selected_row()
		var holds := needs_hold(Enchanter.gold_price(selected_item()))
		if row.is_imbue():
			items_out.append([PlayerInput.Pad.A, "Hold to imbue" if holds else "Imbue"])
		else:
			items_out.append([PlayerInput.Pad.A, "Hold to empower" if holds else "Empower"])
			items_out.append([PlayerInput.Pad.X, "Hold to reroll" if holds else "Reroll"])
		items_out.append([NAV_PROMPT, "Select"])
		items_out.append([PlayerInput.Pad.B, "Back"])
		return items_out
	if selected_item() != null and item_reason() == "":
		items_out.append([PlayerInput.Pad.A, "Enchants"])
	items_out.append([NAV_PROMPT, "Select"])
	return items_out


## Short context text for the panel's prompt row ("Epic Finger · Equipped").
func context_text() -> String:
	var item := selected_item()
	if item == null:
		return ""
	return "%s %s · %s" % [item.rarity_name(), Items.SLOT_NAMES.get(item.slot_type, ""),
		EQUIPPED_CAPTION if is_equipped(item) else BACKPACK_CAPTION]


# --- Build ---------------------------------------------------------------------------------------

func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var body := UiTheme.hbox(COLUMN_GAP)
	body.name = "Body"
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(body)
	body.add_child(_build_list())
	body.add_child(_build_detail())


func _build_list() -> Control:
	var panel := UiTheme.panel(UiTheme.INSET_PANEL)
	panel.name = "ItemList"
	panel.custom_minimum_size.x = LIST_WIDTH
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.clip_contents = true
	var style := UiTheme.inset_style()
	style.content_margin_left = LIST_MARGIN
	style.content_margin_right = LIST_MARGIN
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	panel.add_theme_stylebox_override(&"panel", style)
	var col := UiTheme.vbox(0)
	panel.add_child(col)
	_equipped_caption = UiTheme.label(EQUIPPED_CAPTION, &"", CAPTION_FONT, UiTheme.TEXT_DIM)
	col.add_child(_equipped_caption)
	_equipped_grid = _grid()
	col.add_child(_equipped_grid)
	_backpack_caption = UiTheme.label(BACKPACK_CAPTION, &"", CAPTION_FONT, UiTheme.TEXT_DIM)
	col.add_child(_backpack_caption)
	_backpack_grid = _grid()
	col.add_child(_backpack_grid)
	return panel


func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = COLUMNS
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_theme_constant_override(&"h_separation", CELL_GAP)
	g.add_theme_constant_override(&"v_separation", CELL_GAP)
	return g


func _build_detail() -> Control:
	var panel := UiTheme.panel(UiTheme.INSET_PANEL)
	panel.name = "Detail"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.clip_contents = true
	_detail_box = UiTheme.vbox(3)
	panel.add_child(_detail_box)
	detail_name = UiTheme.label("", &"", 21, UiTheme.GOLD_BRIGHT)
	detail_name.add_theme_font_override(&"font", UiTheme.bold_font())
	detail_name.clip_text = true
	detail_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail_name.custom_minimum_size.x = 40
	_detail_box.add_child(detail_name)
	detail_kind = UiTheme.label("", &"", DETAIL_FONT, UiTheme.TEXT_DIM)
	detail_kind.clip_text = true
	detail_kind.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail_kind.custom_minimum_size.x = 40
	_detail_box.add_child(detail_kind)
	# The enchant rows live in a clipping holder without a minimum height: a (hypothetical) third
	# row is cut off instead of pushing the price out of the panel.
	var holder := Control.new()
	holder.name = "RowsHolder"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.clip_contents = true
	_detail_box.add_child(holder)
	_rows_box = UiTheme.vbox(ROW_GAP)
	_rows_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	holder.add_child(_rows_box)
	detail_hint = UiTheme.wrapped_label("", &"", DETAIL_FONT, UiTheme.TEXT_DIM)
	detail_hint.max_lines_visible = 3
	detail_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail_hint.add_theme_constant_override(&"line_spacing", 0)
	_rows_box.add_child(detail_hint)
	_price_row = UiTheme.hbox(5)
	_price_row.name = "PriceRow"
	var cap := UiTheme.label("Next:", &"", DETAIL_FONT, UiTheme.TEXT_DIM)
	_price_row.add_child(cap)
	_coin = UiIcon.create(UiIcon.Kind.COIN, Vector2(20, 20))
	_coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_price_row.add_child(_coin)
	detail_gold = UiTheme.label("", &"", 20, UiTheme.GOLD)
	detail_gold.add_theme_font_override(&"font", UiTheme.bold_font())
	_price_row.add_child(detail_gold)
	var plus := UiTheme.label("+", &"", DETAIL_FONT, UiTheme.TEXT_DIM)
	_price_row.add_child(plus)
	_dust_icon = DustIcon.create(20.0)
	_dust_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_price_row.add_child(_dust_icon)
	detail_dust = UiTheme.label("", &"", 20, DustIcon.COLOR_BRIGHT)
	detail_dust.add_theme_font_override(&"font", UiTheme.bold_font())
	_price_row.add_child(detail_dust)
	_price_row.add_child(UiTheme.spacer())
	detail_uses = UiTheme.label("", &"", DETAIL_FONT - 1, UiTheme.TEXT_DIM)
	detail_uses.clip_text = true
	detail_uses.custom_minimum_size.x = 40
	_price_row.add_child(detail_uses)
	_detail_box.add_child(_price_row)
	detail_empower = _preview_label(2)
	detail_reroll = _preview_label(1)
	return panel


func _preview_label(max_lines: int) -> Label:
	var l := UiTheme.wrapped_label("", &"", DETAIL_FONT, UiTheme.GREEN)
	l.max_lines_visible = max_lines
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.add_theme_constant_override(&"line_spacing", 0)
	_detail_box.add_child(l)
	return l


# --- Refresh helpers -------------------------------------------------------------------------------

func _collect() -> void:
	items.clear()
	equipped_count = 0
	var eq := equipment()
	if eq == null:
		return
	for it in eq.equipped_items():
		items.append(it)
	equipped_count = items.size()
	for it in eq.backpack:
		items.append(it)


## One icon per item (equipped ones in the first grid, the backpack in the second).
func _sync_cells() -> void:
	for c in cells:
		if is_instance_valid(c):
			c.get_parent().remove_child(c)
			c.queue_free()
	cells.clear()
	for i in items.size():
		var cell := _make_cell(items[i])
		(_equipped_grid if i < equipped_count else _backpack_grid).add_child(cell)
		cells.append(cell)
	_equipped_caption.visible = equipped_count > 0
	_equipped_grid.visible = equipped_count > 0
	_backpack_caption.visible = items.size() > equipped_count
	_backpack_grid.visible = items.size() > equipped_count


func _make_cell(item: ItemInstance) -> Cell:
	var cell := Cell.new()
	cell.custom_minimum_size = Vector2(CELL, CELL)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.item = item
	var can := Enchanter.is_enchantable(item)
	cell.modulate = Color(1, 1, 1, 1.0 if can else 0.42)
	var free := 0
	if item.rarity >= Items.Rarity.UNCOMMON and item.rarity < Items.Rarity.ARTIFACT:
		free = maxi(0, Enchanter.max_enchants(item.rarity) - item.enchants.size())
	cell.set_pips(item.enchants.size(), free)
	return cell


## The rows of the selected item: one per enchant, plus the Imbue row while a slot is free.
func _rebuild_rows() -> void:
	for r in rows:
		if is_instance_valid(r):
			_rows_box.remove_child(r)
			r.queue_free()
	rows.clear()
	var item := selected_item()
	if item != null and item.rarity < Items.Rarity.ARTIFACT:
		for i in item.enchants.size():
			rows.append(EnchanterRow.create(i, item.enchants[i]))
		if item.rarity >= Items.Rarity.UNCOMMON and item.enchants.size() < Enchanter.max_enchants(item.rarity):
			rows.append(EnchanterRow.create(-1, null))
	for i in rows.size():
		_rows_box.add_child(rows[i])
		_rows_box.move_child(rows[i], i)
	if rows.is_empty() and focus == Focus.ROWS:
		focus = Focus.ITEMS
	row_selected = clampi(row_selected, 0, maxi(rows.size() - 1, 0))


func _accent() -> Color:
	return (slot.color if slot != null else UiTheme.GOLD).lightened(0.25)


func _update_selection() -> void:
	for i in cells.size():
		var on := _focused and i == selected
		cells[i].set_selected(on, _accent() if focus == Focus.ITEMS else _accent().darkened(0.45))
	for i in rows.size():
		rows[i].set_selected(_focused and focus == Focus.ROWS and i == row_selected, _accent())
	_update_hold_visual()
	_update_detail()
	prompts_changed.emit()


func _update_hold_visual() -> void:
	for i in rows.size():
		rows[i].set_hold_progress(hold_progress() if not _hold.is_empty() and i == row_selected else 0.0)


func _cancel_hold() -> void:
	_hold.clear()
	_update_hold_visual()
	prompts_changed.emit()


## The held action is still the picked one at the same price, doable and affordable.
func _hold_still_valid() -> bool:
	if _hold.is_empty():
		return false
	var item := selected_item()
	if item == null or item != _hold["item"] or focus != Focus.ROWS or selected_enchant_index() != int(_hold["index"]):
		return false
	var action := _hold["action"] as Enchanter.Action
	return Enchanter.gold_price(item) == int(_hold["gold"]) and block_reason(action, int(_hold["index"])) == ""


## Starts [param action] with the button [param button]: refused with a reason, a hold when the
## gold costs more than HOLD_SHARE of the wallet, else done at once.
func _start(action: Enchanter.Action, index: int, button: PlayerInput.Pad) -> void:
	var item := selected_item()
	var reason := block_reason(action, index)
	if reason != "":
		_say(reason, "", UiTheme.RED)
		return
	var gold := Enchanter.gold_price(item)
	if needs_hold(gold):
		_hold = {"item": item, "action": action, "index": index, "gold": gold, "button": int(button), "time": 0.0}
		_update_selection()
		return
	try_act(action, index)


func _nearest_in_row(row: int, col: int) -> int:
	var best := -1
	var best_gap := 1 << 30
	for i in items.size():
		var p := grid_pos(i)
		if p.y == row and absi(p.x - col) < best_gap:
			best = i
			best_gap = absi(p.x - col)
	return best


## The detail of the selected item and the price of its next action.
func _update_detail() -> void:
	var item := selected_item()
	if item == null:
		detail_name.text = EMPTY_TEXT
		detail_name.add_theme_color_override(&"font_color", UiTheme.TEXT_DIM)
		for c: Control in [detail_kind, detail_hint, _price_row, detail_empower, detail_reroll]:
			c.visible = false
		return
	detail_kind.visible = true
	detail_name.text = item.display_name
	detail_name.add_theme_color_override(&"font_color", ItemIcon.rarity_color_of(item.rarity).lightened(0.15))
	detail_kind.text = "%s %s · Item Level %d · %s" % [item.rarity_name(), Items.SLOT_NAMES.get(item.slot_type, ""),
		item.item_level, EQUIPPED_CAPTION if is_equipped(item) else BACKPACK_CAPTION]
	var reason := item_reason()
	_price_row.visible = reason == ""
	var gold := Enchanter.gold_price(item)
	var dust := Enchanter.dust_price(item)
	detail_gold.text = UiTheme.format_int(gold)
	detail_gold.add_theme_color_override(&"font_color", UiTheme.GOLD if RunState.can_afford(gold) else UiTheme.RED)
	detail_dust.text = str(dust)
	detail_dust.add_theme_color_override(&"font_color",
		DustIcon.COLOR_BRIGHT if RunState.can_afford_dust(dust) else UiTheme.RED)
	_dust_icon.set_dim(not RunState.can_afford_dust(dust))
	detail_uses.text = "Used %d x" % item.enchant_uses if item.enchant_uses > 0 else "Unused"
	# The hint under the rows: why nothing can be done, or what the tab does; while the enchants
	# have the focus the two lines under the price take over.
	detail_hint.visible = focus == Focus.ITEMS or rows.is_empty()
	detail_hint.text = reason if reason != "" else HINT_TEXT
	detail_hint.add_theme_color_override(&"font_color", UiTheme.RED if reason != "" else UiTheme.TEXT_DIM)
	_update_previews(item)


## The green / red lines under the rows: what A and X do on the picked row.
func _update_previews(item: ItemInstance) -> void:
	detail_empower.visible = false
	detail_reroll.visible = false
	var row := selected_row()
	if focus != Focus.ROWS or row == null:
		return
	detail_empower.visible = true
	if row.is_imbue():
		var why := Enchanter.blocked_reason(item, Enchanter.Action.IMBUE)
		if why != "":
			_set_preview(detail_empower, why, false)
		else:
			_set_preview(detail_empower, "Imbue: a new random enchant at Rank %s" %
				EnchantData.rank_label(ItemGenerator.enchant_rank(item.wave, item.looted)), true)
		return
	var index := row.enchant_index
	var roll := item.enchants[index]
	var why_empower := Enchanter.blocked_reason(item, Enchanter.Action.EMPOWER, index)
	if why_empower != "":
		_set_preview(detail_empower, why_empower, false)
	else:
		var next := EnchantRoll.new(roll.enchant, roll.rank + 1)
		_set_preview(detail_empower, "Empower to Rank %s: %s" % [next.rank_label(), ItemTooltip.enchant_text(next)], true)
	detail_reroll.visible = true
	var why_reroll := Enchanter.blocked_reason(item, Enchanter.Action.REROLL, index)
	if why_reroll != "":
		_set_preview(detail_reroll, why_reroll, false)
	else:
		_set_preview(detail_reroll, "Reroll: another enchant at Rank %s" % roll.rank_label(), true, UiTheme.TEXT_DIM)


func _set_preview(l: Label, text: String, ok: bool, ok_color: Color = UiTheme.GREEN) -> void:
	l.text = text
	l.add_theme_color_override(&"font_color", ok_color if ok else UiTheme.RED)


## The toast after an action.
func _announce(out: Enchanter.Outcome) -> void:
	var gold := UiTheme.format_int(out.gold)
	var cost := "  -%s  -%s" % [gold, DustIcon.bbcode(out.dust)]
	var cost_plain := "  -%s g, -%d Dust" % [gold, out.dust]
	var after_name := _name_of(out.after)
	var text := ""
	var plain := ""
	match out.action:
		Enchanter.Action.EMPOWER:
			text = "[color=#%s]%s[/color] is now Rank %s" % [UiTheme.GOLD_BRIGHT.to_html(false), after_name, out.after.rank_label()]
			plain = "%s is now Rank %s" % [after_name, out.after.rank_label()]
		Enchanter.Action.REROLL:
			text = "%s became [color=#%s]%s[/color]" % [_name_of(out.before), UiTheme.GOLD_BRIGHT.to_html(false), after_name]
			plain = "%s became %s" % [_name_of(out.before), after_name]
		_:
			text = "[color=#%s]%s[/color] added (Rank %s)" % [UiTheme.GOLD_BRIGHT.to_html(false), after_name, out.after.rank_label()]
			plain = "%s added" % after_name
	_say(text + cost, plain + cost_plain, UiTheme.TEXT, true)


static func _name_of(roll: EnchantRoll) -> String:
	if roll == null or roll.enchant == null:
		return ""
	return roll.enchant.prefix if roll.enchant.prefix != "" else String(roll.enchant.id).capitalize()


func _say(bbcode: String, plain: String, color: Color, coin: bool = false) -> void:
	message.emit(bbcode, plain if plain != "" else bbcode, color, coin)


# --- Wallet / visibility -------------------------------------------------------------------------

func _on_wallet_changed(_amount: int, _delta: int) -> void:
	if _refresh_if_shown():
		prompts_changed.emit()


func _on_dust_changed(_dust: int, _delta: int) -> void:
	label_changed.emit()
	if _refresh_if_shown():
		prompts_changed.emit()


## Refreshes now when the tab is on screen, else marks it stale (the Intermission keeps the panels
## in the tree, hidden, through the whole wave). True when it refreshed.
func _refresh_if_shown() -> bool:
	if not is_visible_in_tree():
		_stale = true
		return false
	refresh()
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and _stale and is_visible_in_tree():
		_catch_up.call_deferred()


func _catch_up() -> void:
	if _stale and is_visible_in_tree():
		refresh()


func _enter_tree() -> void:
	if not RunState.gold_changed.is_connected(_on_wallet_changed):
		RunState.gold_changed.connect(_on_wallet_changed)
	if not RunState.dust_changed.is_connected(_on_dust_changed):
		RunState.dust_changed.connect(_on_dust_changed)


func _exit_tree() -> void:
	if RunState.gold_changed.is_connected(_on_wallet_changed):
		RunState.gold_changed.disconnect(_on_wallet_changed)
	if RunState.dust_changed.is_connected(_on_dust_changed):
		RunState.dust_changed.disconnect(_on_dust_changed)
