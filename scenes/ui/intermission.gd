class_name Intermission
extends Control
## Between-wave screen (GDD 1, 10, 10.1, 12). open(cleared_wave, level_ups) runs the phases:
##
##   LOOT   – only when RunState.team_loot holds items: the full-screen LootRollScreen rolls
##            RunState.take_team_loot() (Need / Greed / Pass, solo Take / Sell / Leave).
##   (level-up cards come here in M4)
##   MARKET – RunState.shop.open_round(cleared_wave, slots, RunState.rng) once per open; the
##            shared ShopPanel (goblin stall) in the middle, one PlayerPanel per player with a
##            hero in that player's corner (P1 top-left, P2 top-right, P3 bottom-left,
##            P4 bottom-right, like the HUD), a compact wave-cleared summary on top and the
##            ready chips + "Next wave in N s" countdown at the bottom.
##
## Input (MARKET, per slot, through PlayerSlot.input): each player's focus is either the shop
## cursor (ShopPanel.handle_input) or their own panel (PlayerPanel.handle_input); LB / RB
## switch it. START toggles ready (A buys in the shop), B in the shop unreadies (B is checked
## before START: the keyboard's Esc is both). Bots and players whose controller is unplugged
## are ready; with [member bot_shopping] (smoke / demo) every bot buys the cheapest affordable
## offer its class can use with [member bot_buy_chance] once per round and equips what
## ItemTooltip.upgrade_direction calls an upgrade. Everyone ready -> continue_requested
## (once per open). GDD 12: after [member auto_continue_time] seconds of MARKET the next wave
## starts anyway (the countdown does not run during the loot roll).
## See docs/ARCHITECTURE.md.

signal continue_requested
## A player bought an item in the shared shop (statistics).
signal item_bought(slot_index: int, item: ItemInstance)
## One loot roll was resolved and applied (statistics).
signal loot_rolled(roll: LootRoll)

enum Phase { CLOSED, LOOT, MARKET }

## GDD 12: seconds after which the next wave starts even if not everyone is ready.
const AUTO_CONTINUE_TIME := 60.0
## The countdown turns gold for its last seconds.
const COUNTDOWN_WARN_TIME := 10.0
## Smoke / demo bots buy something with this chance once per round.
const BOT_BUY_CHANCE := 0.5
## Screen margin of the corner panels and the corner area each one is scaled to fit into
## (1920x1080 canvas: the stall takes the middle, ShopPanel.STALL_SIZE).
const MARGIN := 14.0
const PANEL_AREA := Vector2(580, 518)
## Vertical shift of the stall (between the header and the ready chips).
const STALL_OFFSET_Y := -8.0
const CHIP_SIZE := Vector2(176, 56)

## Setting (GDD 12: "can be switched off in the settings"; the settings menu comes later):
## seconds until the next wave starts by itself; 0 or less = wait for everyone's Ready.
static var auto_continue_time := AUTO_CONTINUE_TIME

## Smoke / demo (set by Main): bots shop and equip upgrades in the MARKET phase.
var bot_shopping := false
## Chance that a bot buys something in a round (with [member bot_shopping]).
var bot_buy_chance := BOT_BUY_CHANCE
## With [member bot_shopping]: seconds the market stays open for the bots (they shop half-way;
## demo mode uses a few seconds so the stall can be watched, smoke runs 0).
var bot_market_time := 0.0

var cleared_wave := 0
var level_ups := 0
var phase := Phase.CLOSED

var title_label: Label
var next_label: Label
var gold_value: Label
var level_value: Label
var level_ups_value: Label
var chips_row: HBoxContainer
## "Next wave in 42 s" (hidden when the auto-continue is switched off).
var countdown_label: Label
## Seconds until the next wave starts by itself; -1 = no countdown (switched off).
var time_left := -1.0
var shop_panel: ShopPanel
var loot_screen: LootRollScreen
## Slot index -> that player's personal panel (only players with a hero get one).
var panels: Dictionary[int, PlayerPanel] = {}
## Slot index -> true while the player's input goes to their own panel (else the shop).
var panel_focus: Dictionary[int, bool] = {}

var _done := true
## Input is ignored on the first frame after open() / the loot roll (the press that ended it).
var _skip_frames := 0
var _chips: Dictionary[int, PanelContainer] = {}
var _chip_keys: Dictionary[int, String] = {}
var _chip_ids := ""
var _backdrop: TextureRect
var _market_root: Control
var _panel_layer: Control
var _level_ups_caption: Label
var _t := 0.0
var _countdown_second := -1
var _market_time := 0.0
var _bots_shopped := false


static func create() -> Intermission:
	var im := Intermission.new()
	im.name = "Intermission"
	im._build()
	return im


## Shows the screen for the wave that was just cleared: the loot roll first (if any loot),
## then the market. Players ready up with START.
func open(p_cleared_wave: int, p_level_ups: int) -> void:
	cleared_wave = p_cleared_wave
	level_ups = p_level_ups
	_done = false
	_skip_frames = 1
	time_left = auto_continue_time if auto_continue_time > 0.0 else -1.0
	_countdown_second = -1
	_market_time = 0.0
	_bots_shopped = false
	for slot in PlayerManager.get_slots():
		slot.ready = is_auto_ready(slot)
	_fill()
	_update_countdown()
	_refresh_chips(true)
	show()
	if not RunState.team_loot.is_empty():
		_start_loot()
	else:
		_start_market()


## Bots and players whose device is unplugged never block the next wave.
static func is_auto_ready(slot: PlayerSlot) -> bool:
	return slot.is_bot() or slot.input == null or not slot.input.is_connected_device()


func is_open() -> bool:
	return visible and not _done


## Opacity of the dark backdrop (the frozen arena shows through by default).
func set_backdrop_opacity(alpha: float) -> void:
	_backdrop.modulate.a = alpha
	loot_screen.set_backdrop_opacity(alpha)


## Moves [param slot_index]'s input focus to their own panel ([param on]) or to the shop.
func set_panel_focus(slot_index: int, on: bool) -> void:
	on = on and panels.has(slot_index)
	panel_focus[slot_index] = on
	if panels.has(slot_index):
		panels[slot_index].set_input_focus(on)
	shop_panel.set_cursor_active(slot_index, not on)
	_chip_keys.erase(slot_index)


func has_panel_focus(slot_index: int) -> bool:
	return panel_focus.get(slot_index, false)


# --- Phases --------------------------------------------------------------------------

func _start_loot() -> void:
	phase = Phase.LOOT
	_market_root.visible = false
	loot_screen.show()
	loot_screen.open(RunState.take_team_loot(), PlayerManager.get_slots())


func _on_loot_finished() -> void:
	if phase == Phase.LOOT and not _done:
		_start_market()


func _start_market() -> void:
	phase = Phase.MARKET
	loot_screen.hide()
	_market_root.visible = true
	time_left = auto_continue_time if auto_continue_time > 0.0 else -1.0
	_countdown_second = -1
	_skip_frames = maxi(_skip_frames, 1)
	_market_time = 0.0
	var slots := PlayerManager.get_slots()
	shop_panel.set_shop(RunState.shop)
	RunState.shop.open_round(cleared_wave, slots, RunState.rng)
	_sync_panels(slots)
	shop_panel.refresh(slots)
	panel_focus.clear()
	for s in slots:
		set_panel_focus(s.index, false)
	_fill()
	_update_countdown()
	_refresh_chips(true)


## One PlayerPanel per slot with a hero, kept between intermissions while the slot stays.
func _sync_panels(slots: Array[PlayerSlot]) -> void:
	var keep: Dictionary[int, bool] = {}
	for s in slots:
		var hero := s.player as Player
		if hero == null or not is_instance_valid(hero):
			continue
		keep[s.index] = true
		var panel: PlayerPanel = panels.get(s.index)
		if panel != null and panel.slot != s:
			_free_panel(s.index)
			panel = null
		if panel == null:
			panel = PlayerPanel.create(s)
			panel.name = "PlayerPanel%d" % (s.index + 1)
			_panel_layer.add_child(panel)
			panel.trade_done.connect(_on_trade_done)
			panels[s.index] = panel
		panel.refresh()
		_place_panel(panel, s.index)
	for i: int in panels.keys():
		if not keep.has(i):
			_free_panel(i)


func _free_panel(index: int) -> void:
	var panel: PlayerPanel = panels.get(index)
	panels.erase(index)
	panel_focus.erase(index)
	if panel != null and is_instance_valid(panel):
		if panel.get_parent() != null:
			panel.get_parent().remove_child(panel)
		panel.queue_free()


## Scale that fits a panel of [param design] size into PANEL_AREA (never above 1).
static func panel_scale(design: Vector2) -> float:
	if design.x <= 0.0 or design.y <= 0.0:
		return 1.0
	return minf(1.0, minf(PANEL_AREA.x / design.x, PANEL_AREA.y / design.y))


## Anchors [param panel] to its player's screen corner (like the HUD unit frames: P1 top-left,
## P2 top-right, P3 bottom-left, P4 bottom-right), scaled to fit PANEL_AREA. The pivot is the
## top-left corner, so the offsets hold the unscaled size and the scaled panel ends MARGIN
## from the screen edges.
func _place_panel(panel: Control, index: int) -> void:
	var right := index % 2 == 1
	var bottom := index >= 2
	var design := panel.get_combined_minimum_size()
	if design.x <= 0.0 or design.y <= 0.0:
		design = PANEL_AREA
	var s := panel_scale(design)
	var shown := design * s
	panel.scale = Vector2(s, s)
	panel.anchor_left = 1.0 if right else 0.0
	panel.anchor_right = panel.anchor_left
	panel.anchor_top = 1.0 if bottom else 0.0
	panel.anchor_bottom = panel.anchor_top
	panel.grow_horizontal = Control.GROW_DIRECTION_END
	panel.grow_vertical = Control.GROW_DIRECTION_END
	panel.offset_left = -MARGIN - shown.x if right else MARGIN
	panel.offset_right = panel.offset_left + design.x
	panel.offset_top = -MARGIN - shown.y if bottom else MARGIN
	panel.offset_bottom = panel.offset_top + design.y


# --- Build ---------------------------------------------------------------------------

func _build() -> void:
	UiTheme.setup_root(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_backdrop = UiTheme.backdrop(0.82, Color(0.25, 0.17, 0.1))
	add_child(_backdrop)

	_market_root = Control.new()
	_market_root.name = "Market"
	_market_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_market_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_market_root)
	_panel_layer = Control.new()
	_panel_layer.name = "Panels"
	_panel_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_market_root.add_child(_panel_layer)
	_build_header()
	shop_panel = ShopPanel.create(RunState.shop)
	shop_panel.anchor_left = 0.5
	shop_panel.anchor_right = 0.5
	shop_panel.anchor_top = 0.5
	shop_panel.anchor_bottom = 0.5
	shop_panel.offset_left = -ShopPanel.STALL_SIZE.x * 0.5
	shop_panel.offset_right = ShopPanel.STALL_SIZE.x * 0.5
	shop_panel.offset_top = -ShopPanel.STALL_SIZE.y * 0.5 + STALL_OFFSET_Y
	shop_panel.offset_bottom = ShopPanel.STALL_SIZE.y * 0.5 + STALL_OFFSET_Y
	shop_panel.item_bought.connect(_on_item_bought)
	_market_root.add_child(shop_panel)
	_build_footer()

	loot_screen = LootRollScreen.create()
	loot_screen.finished.connect(_on_loot_finished)
	loot_screen.roll_resolved.connect(func(r: LootRoll) -> void: loot_rolled.emit(r))
	loot_screen.visible = false
	add_child(loot_screen)
	visible = false


## Compact wave-cleared summary at the top centre (between the two top panels).
func _build_header() -> void:
	var col := UiTheme.vbox(-4)
	col.anchor_left = 0.5
	col.anchor_right = 0.5
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.offset_top = 8
	_market_root.add_child(col)
	title_label = UiTheme.centered_label("Wave 1 cleared!", UiTheme.TITLE, 48)
	title_label.add_theme_constant_override(&"outline_size", 11)
	col.add_child(title_label)
	var row := UiTheme.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	next_label = UiTheme.label("", UiTheme.DIM, 20)
	next_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(next_label)
	row.add_child(_dot())
	var coin := UiIcon.create(UiIcon.Kind.COIN, Vector2(22, 22))
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(coin)
	gold_value = UiTheme.label("0", UiTheme.GOLD_LABEL, 22)
	gold_value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(gold_value)
	row.add_child(_dot())
	var lvl := UiTheme.label("Level", UiTheme.DIM, 20)
	lvl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lvl)
	level_value = UiTheme.label("1", UiTheme.GOLD_LABEL, 22)
	level_value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(level_value)
	level_ups_value = UiTheme.label("–", UiTheme.GOLD_LABEL, 20)
	level_ups_value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(level_ups_value)
	_level_ups_caption = UiTheme.label("this wave", UiTheme.DIM, 18)
	_level_ups_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_level_ups_caption)


func _dot() -> Label:
	var l := UiTheme.label("·", UiTheme.DIM, 22)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


## Ready chips, the auto-continue countdown and the prompts at the bottom centre.
func _build_footer() -> void:
	var col := UiTheme.vbox(6)
	col.anchor_left = 0.5
	col.anchor_right = 0.5
	col.anchor_top = 1.0
	col.anchor_bottom = 1.0
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	col.offset_top = -12
	col.offset_bottom = -12
	_market_root.add_child(col)
	chips_row = UiTheme.hbox(8)
	chips_row.alignment = BoxContainer.ALIGNMENT_CENTER
	chips_row.custom_minimum_size = Vector2(0, CHIP_SIZE.y)
	col.add_child(chips_row)
	var line := UiTheme.hbox(18)
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(line)
	countdown_label = UiTheme.label("", UiTheme.DIM, UiTheme.FONT_BODY)
	countdown_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	countdown_label.visible = false
	line.add_child(countdown_label)
	line.add_child(UiTheme.prompt_row([
		[UiGlyph.pad(PlayerInput.Pad.START, 26.0), "Ready"],
		[UiGlyph.pad(PlayerInput.Pad.LB, 26.0), UiGlyph.pad(PlayerInput.Pad.RB, 26.0), "Shop / own panel"],
		[UiTheme.label("Keys:", UiTheme.SMALL, 17), UiGlyph.key("P", 24.0), UiGlyph.key("Q", 24.0), UiGlyph.key("E", 24.0)],
	], 19, UiTheme.TEXT_DIM))


# --- Content -------------------------------------------------------------------------

func _fill() -> void:
	title_label.text = "Wave %d cleared!" % cleared_wave
	var next := cleared_wave + 1
	var tag := ""
	if RunState.is_boss_wave(next):
		tag = "  –  Boss wave!"
	elif RunState.is_elite_wave(next):
		tag = "  –  Elite wave!"
	if next > RunState.TOTAL_WAVES:
		next_label.text = "The final battle is won"
	else:
		next_label.text = "Next up: Wave %d of %d  ·  %d seconds%s" % [next, RunState.TOTAL_WAVES, int(RunState.wave_duration(next)), tag]
	next_label.add_theme_color_override(&"font_color", UiTheme.RED.lightened(0.2) if tag != "" else UiTheme.TEXT_DIM)
	_fill_gold()
	level_value.text = str(RunState.level)
	level_ups_value.text = "+%d" % level_ups if level_ups > 0 else "–"
	level_ups_value.add_theme_color_override(&"font_color", UiTheme.GREEN if level_ups > 0 else UiTheme.TEXT_DIM)
	level_ups_value.visible = level_ups > 0
	_level_ups_caption.visible = level_ups > 0


func _fill_gold() -> void:
	gold_value.text = UiTheme.format_int(RunState.gold)
	gold_value.add_theme_color_override(&"font_color", UiTheme.GOLD)


func _refresh_chips(force: bool = false) -> void:
	var slots := PlayerManager.get_slots()
	var ids := ""
	for s in slots:
		ids += "%d," % s.index
	if force or ids != _chip_ids:
		_chip_ids = ids
		for c in chips_row.get_children():
			chips_row.remove_child(c)
			c.queue_free()
		_chips.clear()
		_chip_keys.clear()
		for s in slots:
			var chip := PanelContainer.new()
			chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chips_row.add_child(chip)
			_chips[s.index] = chip
	for s in slots:
		var key := "%s:%s:%s:%s" % [s.ready, is_auto_ready(s), s.class_data.id if s.class_data != null else &"",
			has_panel_focus(s.index)]
		if _chip_keys.get(s.index, "") != key:
			_chip_keys[s.index] = key
			_fill_chip(_chips[s.index], s)


func _fill_chip(chip: PanelContainer, s: PlayerSlot) -> void:
	for c in chip.get_children():
		chip.remove_child(c)
		c.queue_free()
	var style := UiTheme.inset_style()
	style.border = UiTheme.GREEN if s.ready else s.color.darkened(0.3)
	style.border_width = 2
	style.fill = Color(0.07, 0.13, 0.06, 0.97) if s.ready else UiTheme.STONE_DARK
	style.content_margin_left = 8
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	chip.add_theme_stylebox_override(&"panel", style.rebuild())
	chip.custom_minimum_size = CHIP_SIZE
	var row := UiTheme.hbox(8)
	chip.add_child(row)
	var portrait := UiPortrait.create(42.0)
	portrait.setup(s.color, s.class_data)
	row.add_child(portrait)
	var box := UiTheme.vbox(-2)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(box)
	var name_row := UiTheme.hbox(5)
	name_row.add_child(UiTheme.label(s.label(), UiTheme.GOLD_LABEL, 19, s.color.lightened(0.3)))
	name_row.add_child(UiTheme.label(s.class_data.display_name if s.class_data != null else "", UiTheme.GOLD_LABEL, 19))
	box.add_child(name_row)
	var status := UiTheme.hbox(5)
	if s.ready:
		status.add_child(UiIcon.create(UiIcon.Kind.CHECK, Vector2(18, 18)))
		var text := "Ready"
		if s.is_bot():
			text = "Ready (bot)"
		elif s.input == null or not s.input.is_connected_device():
			text = "Disconnected"
		status.add_child(UiTheme.label(text, &"", 17, UiTheme.GREEN))
	else:
		status.add_child(UiGlyph.for_input(s.input, PlayerInput.Pad.START, 20.0))
		var where := "in own panel" if has_panel_focus(s.index) else "to ready"
		status.add_child(UiTheme.label(where, &"", 16, UiTheme.TEXT_DIM))
	box.add_child(status)


func _update_countdown() -> void:
	countdown_label.visible = time_left >= 0.0
	if time_left < 0.0:
		return
	var whole := maxi(0, ceili(time_left))
	if whole == _countdown_second:
		return
	_countdown_second = whole
	countdown_label.text = "Next wave in %d s" % whole
	var warn := time_left <= COUNTDOWN_WARN_TIME
	countdown_label.add_theme_color_override(&"font_color", UiTheme.GOLD if warn else UiTheme.TEXT_DIM)


# --- Frame ---------------------------------------------------------------------------

func _enter_tree() -> void:
	if not RunState.gold_changed.is_connected(_on_gold_changed):
		RunState.gold_changed.connect(_on_gold_changed)


func _exit_tree() -> void:
	if RunState.gold_changed.is_connected(_on_gold_changed):
		RunState.gold_changed.disconnect(_on_gold_changed)


func _process(delta: float) -> void:
	_t += delta
	if not visible or _done or phase != Phase.MARKET:
		return
	_market_time += delta
	if time_left > 0.0:
		time_left = maxf(0.0, time_left - delta)
		_update_countdown()
		if time_left <= 0.0:
			# GDD 12: time is up – the next wave starts, the stragglers come along anyway.
			_continue()
			return
	shop_panel.begin_frame(delta)
	if _skip_frames > 0:
		_skip_frames -= 1
		return
	if bot_shopping and not _bots_shopped and _market_time >= bot_market_time * 0.5:
		_bots_shop()
	var slots := PlayerManager.get_slots()
	for s in slots:
		if is_auto_ready(s):
			s.ready = true
			continue
		_route_input(s)
	_refresh_chips()
	if slots.is_empty() or (PlayerManager.all_ready() and _bots_settled()):
		_continue()


## One human's input: LB / RB switch the focus, the focused side gets the rest, START toggles
## ready (B in the shop unreadies; B + START together – the keyboard's Esc – act as B).
func _route_input(s: PlayerSlot) -> void:
	var inp := s.input
	var has_panel := panels.has(s.index)
	if has_panel and (inp.just_pressed(PlayerInput.Pad.LB) or inp.just_pressed(PlayerInput.Pad.RB)):
		set_panel_focus(s.index, not has_panel_focus(s.index))
		return
	var b := inp.just_pressed(PlayerInput.Pad.B)
	if has_panel and has_panel_focus(s.index):
		panels[s.index].handle_input(inp)
	else:
		shop_panel.handle_input(s)
		if b:
			s.ready = false
	if inp.just_pressed(PlayerInput.Pad.START) and not b:
		s.ready = not s.ready


func _bots_settled() -> bool:
	return not bot_shopping or (_bots_shopped and _market_time >= bot_market_time)


## Smoke / demo: every bot maybe buys the cheapest offer it can use, then equips upgrades
## from its backpack (loot won by Need included). RunState.rng keeps smoke runs reproducible.
func _bots_shop() -> void:
	_bots_shopped = true
	for s in PlayerManager.get_slots():
		if not s.is_bot():
			continue
		var eq := ShopPanel.equipment_of(s)
		if eq == null:
			continue
		_bot_make_room(s, eq)
		if RunState.rng.randf() < bot_buy_chance:
			var index := shop_panel.cheapest_offer_for(s)
			if index >= 0:
				shop_panel.set_cursor(s.index, index)
				shop_panel.try_buy(s, index)
		bot_equip_upgrades(s)
		if panels.has(s.index):
			panels[s.index].refresh()


## Equips every backpack item ItemTooltip.upgrade_direction calls an upgrade over what sits in
## its default slot. Returns how many items were equipped.
static func bot_equip_upgrades(s: PlayerSlot) -> int:
	var eq := ShopPanel.equipment_of(s)
	if eq == null:
		return 0
	var n := 0
	for item in eq.backpack.duplicate():
		if not eq.can_equip(item):
			continue
		var target := eq.default_slot(item)
		var current: ItemInstance = eq.get_item(target as Items.EquipSlot) if target >= 0 else null
		if ItemTooltip.upgrade_direction(item, current, s.class_data) > 0 and eq.equip(item, target):
			n += 1
	return n


## A full backpack would stop a bot from buying / needing: it sells its first item that is
## not an upgrade.
func _bot_make_room(s: PlayerSlot, eq: Equipment) -> void:
	if eq.has_space():
		return
	for item in eq.backpack:
		var target := eq.default_slot(item)
		var current: ItemInstance = eq.get_item(target as Items.EquipSlot) if target >= 0 else null
		if not eq.can_equip(item) or ItemTooltip.upgrade_direction(item, current, s.class_data) <= 0:
			if eq.remove_from_backpack(item):
				RunState.add_gold(item.sell_value())
			return


func _on_item_bought(slot_index: int, item: ItemInstance) -> void:
	if panels.has(slot_index):
		panels[slot_index].refresh()
	item_bought.emit(slot_index, item)


func _on_trade_done(_item: ItemInstance, to_slot_index: int) -> void:
	if panels.has(to_slot_index):
		panels[to_slot_index].refresh()


func _on_gold_changed(_gold: int, _delta: int) -> void:
	if gold_value != null:
		_fill_gold()


func _continue() -> void:
	_done = true
	continue_requested.emit()
