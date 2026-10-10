class_name LootRollScreen
extends Control
## Shared-screen WoW-style Need / Greed / Pass roll window (GDD 10.1, 12): items one after
## another; big tooltip in the middle, a 15 s timer bar, one chip per player (colour, upgrade
## arrow, decided tick, then dice / coin / pass icon and the 1-100 roll), message log on the
## right ("P2 rolls 87 (Need) for [Stormcaller]"), "Items: 2 / 5" and the queue of the next
## items on the left. Per player: A = Need (greyed with the reason when not allowed), X = Greed,
## B = Pass, Y = Greed all remaining. Choices stay hidden until everyone decided (or the time
## ran out: undecided = Pass). Bots decide with LootRoll.bot_choice; unplugged controllers
## pass. Solo: Take (A) / Sell (X) / Leave (B), Y = sell all remaining.
## Each roll is resolved with RunState.rng and applied (LootRoll.apply); the winner line shows
## for RESULT_TIME before the next item. finished is emitted once after the last item.

signal finished
## One item's roll was resolved and applied (statistics, logs).
signal roll_resolved(roll: LootRoll)

enum Phase { IDLE, CHOOSING, RESULT, DONE }

## GDD 10.1: seconds to decide per item; undecided players pass.
const ROLL_TIME := 15.0
## Seconds the winner line shows before the next item.
const RESULT_TIME := 1.2
## A press right when the next item appears is not taken as its choice.
const ITEM_INPUT_DELAY := 0.25
const LOG_LINES := 16
const QUEUE_SHOWN := 7
const CHIP_SIZE := Vector2(290, 96)

## Seconds a bot "thinks" before deciding (0 = at once; demo mode slows bots down a little
## so the ticks can be watched).
var bot_think_time := 0.0
## Builds the roll of one item (tests inject fakes): Callable(item: ItemInstance) -> LootRoll.
var make_roll: Callable = LootRoll.create

var items: Array[ItemInstance] = []
var slots: Array[PlayerSlot] = []
## Index of the item being rolled (-1 before the first).
var current := -1
var roll: LootRoll
var phase := Phase.IDLE
var time_left := 0.0
## Slot index -> chose "Greed all remaining" (Y).
var greed_all: Dictionary[int, bool] = {}
## Slot index -> LootRoll.Choice for the current item (mirrored here for the UI).
var choices: Dictionary[int, int] = {}
## Slot index -> the player passed because the time ran out (current item).
var timed_out: Dictionary[int, bool] = {}
## The result line of the last resolved item ("P2 wins [Stormcaller]").
var result_text := ""

var title_label: Label
var subtitle_label: Label
var counter_label: Label
var name_label: Label
var info_label: Label
var icon: ItemIcon
var tooltip: ItemTooltip
var timer_bar: UiBar
var result_label: RichTextLabel
var chips_row: HBoxContainer
var log_label: RichTextLabel

var _log_bb: Array[String] = []
var _log_plain: Array[String] = []
var _skip_frames := 0
var _input_delay := 0.0
var _result_left := 0.0
var _bot_wait: Dictionary[int, float] = {}
## Slot index -> seconds left of a "Cannot use" flash on the chip after a refused Need.
var _flash: Dictionary[int, float] = {}
var _chips: Dictionary[int, PanelContainer] = {}
var _chip_keys: Dictionary[int, String] = {}
var _legend: HBoxContainer
var _legend_solo: bool = false
var _legend_built := false
var _queue_box: VBoxContainer
var _backdrop: TextureRect
var _t := 0.0


static func create() -> LootRollScreen:
	var s := LootRollScreen.new()
	s.name = "LootRollScreen"
	s._build()
	return s


## Starts rolling [param p_items] for [param p_slots]; emits finished when all are resolved.
func open(p_items: Array[ItemInstance], p_slots: Array[PlayerSlot]) -> void:
	items = []
	for it in p_items:
		if it != null:
			items.append(it)
	slots = []
	for s in p_slots:
		if s != null:
			slots.append(s)
	slots.sort_custom(func(a: PlayerSlot, b: PlayerSlot) -> bool: return a.index < b.index)
	greed_all.clear()
	_log_bb.clear()
	_log_plain.clear()
	log_label.text = ""
	result_text = ""
	current = -1
	roll = null
	_skip_frames = 1
	_chip_keys.clear()
	_rebuild_chips()
	_build_legend(is_solo())
	title_label.text = "Loot" if is_solo() else "Loot Roll"
	subtitle_label.text = "Take it, sell it or leave it" if is_solo() \
		else "Need, Greed or Pass – everyone decides on their own controller"
	show()
	if items.is_empty():
		phase = Phase.DONE
		finished.emit.call_deferred()
		return
	_next_item()


## One player: no roll, just Take / Sell / Leave (GDD 10.1).
func is_solo() -> bool:
	return slots.size() == 1


func is_rolling() -> bool:
	return visible and (phase == Phase.CHOOSING or phase == Phase.RESULT)


## The current item's choice of [param slot_index] (LootRoll.Choice).
func choice_of(slot_index: int) -> int:
	return choices.get(slot_index, LootRoll.Choice.UNDECIDED)


## Everyone decided on the current item.
func all_decided() -> bool:
	for s in slots:
		if choice_of(s.index) == LootRoll.Choice.UNDECIDED:
			return false
	return true


## The message log as plain text, oldest first.
func log_lines() -> Array[String]:
	return _log_plain.duplicate()


## Opacity of the dark backdrop.
func set_backdrop_opacity(alpha: float) -> void:
	_backdrop.modulate.a = alpha


## Why Need is greyed out for [param slot] on the current item ("" = allowed).
func need_reason(slot: PlayerSlot) -> String:
	if roll == null or roll.item == null:
		return ""
	if roll.can_need(slot):
		return ""
	var why := roll.item.unusable_reason(slot.class_data)
	if why != "":
		return why
	var eq := ShopPanel.equipment_of(slot)
	if eq != null and not eq.has_space():
		return "Backpack full"
	return "Cannot need"


# --- Flow --------------------------------------------------------------------------

func _next_item() -> void:
	current += 1
	if current >= items.size():
		phase = Phase.DONE
		roll = null
		finished.emit()
		return
	var item := items[current]
	roll = make_roll.call(item) as LootRoll
	if roll == null:
		roll = LootRoll.create(item)
	choices.clear()
	timed_out.clear()
	_bot_wait.clear()
	_flash.clear()
	result_text = ""
	time_left = ROLL_TIME
	_input_delay = ITEM_INPUT_DELAY
	phase = Phase.CHOOSING
	for s in slots:
		if s.is_bot():
			_bot_wait[s.index] = _bot_delay(s.index)
		elif greed_all.get(s.index, false):
			_choose(s, LootRoll.Choice.GREED)
		elif s.input == null or not s.input.is_connected_device():
			_choose(s, LootRoll.Choice.PASS)
	_fill_item()
	_refresh_chips(true)


## Deterministic little pause per bot and item (no rng: smoke runs stay reproducible).
func _bot_delay(slot_index: int) -> float:
	if bot_think_time <= 0.0:
		return 0.0
	return bot_think_time * (0.35 + 0.22 * float((slot_index * 3 + current * 5) % 5))


func _choose(slot: PlayerSlot, choice: LootRoll.Choice) -> void:
	choices[slot.index] = choice
	if roll != null:
		roll.choose(slot.index, choice)


func _resolve() -> void:
	for s in slots:
		if choice_of(s.index) == LootRoll.Choice.UNDECIDED:
			timed_out[s.index] = true
			_choose(s, LootRoll.Choice.PASS)
	var item := roll.item
	var wins_before := RunState.need_wins_by_player.duplicate()
	var greed_before := RunState.greed_gold
	roll.resolve(RunState.rng)
	roll.apply(slots)
	# Statistics (GDD 10.1): count them here unless LootRoll.apply already did.
	if roll.outcome == &"need" and roll.winner >= 0 \
			and RunState.need_wins_by_player.get(roll.winner, 0) == wins_before.get(roll.winner, 0):
		RunState.need_wins_by_player[roll.winner] = int(wins_before.get(roll.winner, 0)) + 1
	if roll.outcome == &"greed" and RunState.greed_gold == greed_before and item != null:
		RunState.greed_gold += item.greed_value()
	_log_results(item)
	phase = Phase.RESULT
	_result_left = RESULT_TIME
	result_label.text = "[center]%s[/center]" % _result_bb(item)
	result_label.visible = true
	timer_bar.visible = false
	_refresh_chips(true)
	roll_resolved.emit(roll)


func _log_results(item: ItemInstance) -> void:
	var link := ShopPanel.item_link(item)
	var name := "[%s]" % (item.display_name if item != null else "?")
	if not is_solo():
		for s in slots:
			var c := choice_of(s.index)
			if c == LootRoll.Choice.NEED or c == LootRoll.Choice.GREED:
				var kind := "Need" if c == LootRoll.Choice.NEED else "Greed"
				if roll.rolls.has(s.index):
					var n: int = roll.rolls[s.index]
					_log("%s rolls %d (%s) for %s" % [ShopPanel.player_tag(s), n, kind, link],
						"%s rolls %d (%s) for %s" % [s.label(), n, kind, name])
				else:
					_log("%s chose %s for %s" % [ShopPanel.player_tag(s), kind, link],
						"%s chose %s for %s" % [s.label(), kind, name])
			else:
				var why := " (time)" if timed_out.get(s.index, false) else ""
				_log("[color=#a09a90]%s passed on %s%s[/color]" % [s.label(), ShopPanel.bb_escape(name), why],
					"%s passed on %s%s" % [s.label(), name, why])
	_log(_result_bb(item), _result_plain(item))
	result_text = _result_plain(item)


func _winner_slot() -> PlayerSlot:
	if roll == null:
		return null
	for s in slots:
		if s.index == roll.winner:
			return s
	return null


func _result_plain(item: ItemInstance) -> String:
	var name := "[%s]" % (item.display_name if item != null else "?")
	var w := _winner_slot()
	var gold := item.greed_value() if item != null else 0
	match roll.outcome:
		&"need":
			if is_solo():
				return "%s takes %s" % [w.label() if w != null else "?", name]
			return "%s wins %s" % [w.label() if w != null else "?", name]
		&"greed":
			if is_solo() or w == null:
				return "Sold %s for %d g" % [name, gold]
			return "%s sold for %d g (%s won the Greed roll)" % [name, gold, w.label()]
	if is_solo():
		return "Left %s behind" % name
	return "Everyone passed on %s" % name


func _result_bb(item: ItemInstance) -> String:
	var link := ShopPanel.item_link(item)
	var w := _winner_slot()
	var gold := item.greed_value() if item != null else 0
	var gold_bb := "[color=#%s]%d g[/color]" % [UiTheme.GOLD.to_html(false), gold]
	match roll.outcome:
		&"need":
			return "%s %s %s" % [ShopPanel.player_tag(w), "takes" if is_solo() else "wins", link]
		&"greed":
			if is_solo() or w == null:
				return "Sold %s for %s" % [link, gold_bb]
			return "%s sold for %s (%s won the Greed roll)" % [link, gold_bb, ShopPanel.player_tag(w)]
	if is_solo():
		return "[color=#a09a90]Left %s behind[/color]" % ShopPanel.bb_escape("[%s]" % (item.display_name if item != null else "?"))
	return "[color=#a09a90]Everyone passed on %s[/color]" % ShopPanel.bb_escape("[%s]" % (item.display_name if item != null else "?"))


func _log(bb: String, plain: String) -> void:
	_log_bb.append(bb)
	_log_plain.append(plain)
	while _log_bb.size() > LOG_LINES:
		_log_bb.pop_front()
	log_label.text = "\n".join(_log_bb)


# --- Frame ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if not visible:
		return
	match phase:
		Phase.CHOOSING:
			_process_choosing(delta)
		Phase.RESULT:
			_result_left -= delta
			if _result_left <= 0.0:
				_next_item()


func _process_choosing(delta: float) -> void:
	time_left = maxf(0.0, time_left - delta)
	_input_delay -= delta
	for i: int in _flash.keys():
		_flash[i] = float(_flash[i]) - delta
		if float(_flash[i]) <= 0.0:
			_flash.erase(i)
	for s in slots:
		if choice_of(s.index) != LootRoll.Choice.UNDECIDED:
			continue
		if s.is_bot():
			_bot_wait[s.index] = float(_bot_wait.get(s.index, 0.0)) - delta
			if float(_bot_wait[s.index]) <= 0.0:
				var c := LootRoll.bot_choice(s, roll.item)
				if c == LootRoll.Choice.UNDECIDED or (c == LootRoll.Choice.NEED and not roll.can_need(s)):
					c = LootRoll.Choice.GREED
				_choose(s, c)
		elif s.input == null or not s.input.is_connected_device():
			_choose(s, LootRoll.Choice.PASS)
	if _skip_frames > 0:
		_skip_frames -= 1
	elif _input_delay <= 0.0:
		for s in slots:
			if not s.is_bot() and s.input != null and s.input.is_connected_device():
				_handle_input(s)
	timer_bar.set_values(time_left, ROLL_TIME, "%d s" % ceili(time_left))
	timer_bar.set_fill_color(UiTheme.RED if time_left <= 5.0 else Color(0.95, 0.62, 0.15))
	_refresh_chips()
	if all_decided() or time_left <= 0.0:
		_resolve()


func _handle_input(s: PlayerSlot) -> void:
	var inp := s.input
	var undecided := choice_of(s.index) == LootRoll.Choice.UNDECIDED
	if inp.just_pressed(PlayerInput.Pad.Y):
		if not greed_all.get(s.index, false):
			greed_all[s.index] = true
			var what := "sell" if is_solo() else "greed"
			_log("[color=#a09a90]%s will %s all remaining items[/color]" % [s.label(), what],
				"%s will %s all remaining items" % [s.label(), what])
		if undecided:
			_choose(s, LootRoll.Choice.GREED)
		return
	if not undecided:
		return
	if inp.just_pressed(PlayerInput.Pad.A):
		if roll.can_need(s):
			_choose(s, LootRoll.Choice.NEED)
		else:
			_flash[s.index] = 1.2
	elif inp.just_pressed(PlayerInput.Pad.X):
		_choose(s, LootRoll.Choice.GREED)
	elif inp.just_pressed(PlayerInput.Pad.B):
		_choose(s, LootRoll.Choice.PASS)


# --- Build ---------------------------------------------------------------------------

func _build() -> void:
	UiTheme.setup_root(self)
	_backdrop = UiTheme.backdrop(0.9, Color(0.3, 0.2, 0.08))
	add_child(_backdrop)

	var top := UiTheme.vbox(0)
	top.anchor_left = 0.5
	top.anchor_right = 0.5
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.offset_top = 22
	add_child(top)
	title_label = UiTheme.centered_label("Loot Roll", UiTheme.TITLE, 60)
	top.add_child(title_label)
	subtitle_label = UiTheme.centered_label("", UiTheme.DIM, UiTheme.FONT_BODY)
	top.add_child(subtitle_label)

	var middle := UiTheme.hbox(26)
	middle.alignment = BoxContainer.ALIGNMENT_CENTER
	middle.anchor_right = 1.0
	middle.anchor_top = 0.5
	middle.anchor_bottom = 0.5
	middle.grow_vertical = Control.GROW_DIRECTION_BOTH
	middle.offset_top = -70
	middle.offset_bottom = -70
	add_child(middle)
	middle.add_child(_build_queue())
	middle.add_child(_build_frame())
	middle.add_child(_build_log())

	var bottom := UiTheme.vbox(10)
	bottom.anchor_left = 0.5
	bottom.anchor_right = 0.5
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_top = -24
	bottom.offset_bottom = -24
	add_child(bottom)
	chips_row = UiTheme.hbox(14)
	chips_row.alignment = BoxContainer.ALIGNMENT_CENTER
	chips_row.custom_minimum_size = Vector2(0, CHIP_SIZE.y)
	bottom.add_child(chips_row)
	_legend = UiTheme.hbox(22)
	_legend.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(_legend)
	visible = false


func _build_frame() -> Control:
	var frame := UiTheme.panel()
	var style := UiTheme.stone_style()
	style.content_margin_left = 26
	style.content_margin_right = 26
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	frame.add_theme_stylebox_override(&"panel", style.rebuild())
	frame.custom_minimum_size = Vector2(700, 0)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var col := UiTheme.vbox(12)
	frame.add_child(col)
	var head := UiTheme.hbox(18)
	col.add_child(head)
	icon = ItemIcon.create(null, 96.0)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(icon)
	var names := UiTheme.vbox(2)
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	name_label = UiTheme.label("", UiTheme.GOLD_LABEL, 34)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(500, 0)
	names.add_child(name_label)
	info_label = UiTheme.label("", UiTheme.DIM, 20)
	names.add_child(info_label)
	col.add_child(UiTheme.divider(0))
	var tip_holder := CenterContainer.new()
	tip_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_holder.custom_minimum_size = Vector2(0, 120)
	col.add_child(tip_holder)
	tooltip = ItemTooltip.create()
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_holder.add_child(tooltip)
	timer_bar = UiBar.create(Color(0.95, 0.62, 0.15), 28.0, UiTheme.FONT_BODY - 2)
	timer_bar.animated = false
	col.add_child(timer_bar)
	result_label = RichTextLabel.new()
	result_label.bbcode_enabled = true
	result_label.fit_content = true
	result_label.scroll_active = false
	result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_label.add_theme_font_size_override(&"normal_font_size", 28)
	result_label.add_theme_font_override(&"normal_font", UiTheme.bold_font())
	result_label.custom_minimum_size = Vector2(0, 28)
	result_label.visible = false
	col.add_child(result_label)
	return frame


func _build_log() -> Control:
	var panel := UiTheme.panel()
	var style := UiTheme.stone_style()
	style.content_margin_left = 18
	style.content_margin_right = 18
	panel.add_theme_stylebox_override(&"panel", style.rebuild())
	panel.custom_minimum_size = Vector2(440, 520)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var col := UiTheme.vbox(8)
	panel.add_child(col)
	var head := UiTheme.hbox(10)
	col.add_child(head)
	head.add_child(UiTheme.label("Roll log", UiTheme.HEADING, 28))
	head.add_child(UiTheme.spacer())
	counter_label = UiTheme.label("Items: 0 / 0", UiTheme.GOLD_LABEL, 24)
	counter_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(counter_label)
	col.add_child(UiTheme.divider(0))
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.add_theme_font_size_override(&"normal_font_size", 18)
	log_label.add_theme_constant_override(&"line_separation", 4)
	col.add_child(log_label)
	return panel


func _build_queue() -> Control:
	var panel := UiTheme.panel(UiTheme.INSET_PANEL)
	panel.custom_minimum_size = Vector2(120, 0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var col := UiTheme.vbox(8)
	panel.add_child(col)
	col.add_child(UiTheme.centered_label("Up next", UiTheme.SMALL, 17))
	_queue_box = UiTheme.vbox(8)
	col.add_child(_queue_box)
	return panel


func _build_legend(solo: bool) -> void:
	if _legend_built and solo == _legend_solo:
		return
	_legend_built = true
	_legend_solo = solo
	for c in _legend.get_children():
		_legend.remove_child(c)
		c.queue_free()
	var parts: Array = [
		[UiGlyph.pad(PlayerInput.Pad.A), RollIcon.make(RollIcon.Kind.DICE, 26.0), "Take" if solo else "Need"],
		[UiGlyph.pad(PlayerInput.Pad.X), RollIcon.make(RollIcon.Kind.COIN, 26.0), "Sell" if solo else "Greed"],
		[UiGlyph.pad(PlayerInput.Pad.B), RollIcon.make(RollIcon.Kind.PASS, 26.0), "Leave" if solo else "Pass"],
		[UiGlyph.pad(PlayerInput.Pad.Y), "Sell all remaining" if solo else "Greed all remaining"],
	]
	var row := UiTheme.prompt_row(parts, UiTheme.FONT_BODY, UiTheme.TEXT)
	_legend.add_child(row)
	var keys := UiTheme.label("Keyboard: Enter / R / Esc / C", UiTheme.SMALL, 17)
	keys.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_legend.add_child(keys)


# --- Content -----------------------------------------------------------------------

func _fill_item() -> void:
	var item := items[current]
	icon.set_item(item)
	name_label.text = item.display_name
	name_label.add_theme_color_override(&"font_color", ShopOfferCard.rarity_color(item))
	var bits: Array[String] = []
	if item.item_level > 0:
		bits.append("Item Level %d" % item.item_level)
	bits.append("%s %s" % [item.rarity_name(), ShopOfferCard.type_text(item)])
	if item.looted:
		bits.append("Looted")
	info_label.text = "  ·  ".join(bits)
	tooltip.show_item(item, null, null, 0)
	tooltip.reset_size()
	counter_label.text = "Items: %d / %d" % [current + 1, items.size()]
	timer_bar.visible = true
	timer_bar.set_values(ROLL_TIME, ROLL_TIME, "%d s" % int(ROLL_TIME))
	result_label.visible = false
	_fill_queue()


func _fill_queue() -> void:
	for c in _queue_box.get_children():
		_queue_box.remove_child(c)
		c.queue_free()
	var shown := 0
	for i in range(current + 1, items.size()):
		if shown >= QUEUE_SHOWN:
			break
		var holder := CenterContainer.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := ItemIcon.create(items[i], 54.0)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(ic)
		_queue_box.add_child(holder)
		shown += 1
	var rest := items.size() - current - 1 - shown
	if rest > 0:
		_queue_box.add_child(UiTheme.centered_label("+%d more" % rest, UiTheme.SMALL, 16))
	if items.size() - current - 1 <= 0:
		_queue_box.add_child(UiTheme.centered_label("Last item", UiTheme.SMALL, 16))


func _rebuild_chips() -> void:
	for c in chips_row.get_children():
		chips_row.remove_child(c)
		c.queue_free()
	_chips.clear()
	_chip_keys.clear()
	for s in slots:
		var chip := PanelContainer.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.custom_minimum_size = CHIP_SIZE
		chips_row.add_child(chip)
		_chips[s.index] = chip


func _refresh_chips(force: bool = false) -> void:
	for s in slots:
		var chip: PanelContainer = _chips.get(s.index)
		if chip == null:
			continue
		var key := "%d:%d:%d:%s:%s:%s" % [current, phase, choice_of(s.index), _flash.has(s.index),
			greed_all.get(s.index, false), roll.rolls.get(s.index, -1) if roll != null else -1]
		if force or _chip_keys.get(s.index, "") != key:
			_chip_keys[s.index] = key
			_fill_chip(chip, s)


func _upgrade_direction(s: PlayerSlot) -> int:
	if roll == null or roll.item == null or not roll.item.can_be_used_by(s.class_data):
		return 0
	var eq := ShopPanel.equipment_of(s)
	var current_item: ItemInstance = null
	if eq != null:
		var target := eq.default_slot(roll.item)
		if target >= 0:
			current_item = eq.get_item(target as Items.EquipSlot)
	return ItemTooltip.upgrade_direction(roll.item, current_item, s.class_data)


func _fill_chip(chip: PanelContainer, s: PlayerSlot) -> void:
	for c in chip.get_children():
		chip.remove_child(c)
		c.queue_free()
	var choice := choice_of(s.index)
	var revealed := phase == Phase.RESULT or phase == Phase.DONE
	var won := revealed and roll != null and roll.winner == s.index and roll.outcome in [&"need", &"greed"]
	var style := UiTheme.inset_style()
	style.border = UiTheme.GOLD_BRIGHT if won else s.color.darkened(0.1)
	style.border_width = 3 if won else 2
	style.fill = Color(0.16, 0.12, 0.05, 0.97) if won else UiTheme.STONE_DARK
	style.content_margin_left = 10
	style.content_margin_right = 12
	if won:
		style.glow = Color(1.0, 0.8, 0.3, 0.45)
		style.glow_size = 12
	chip.add_theme_stylebox_override(&"panel", style.rebuild())
	var row := UiTheme.hbox(10)
	chip.add_child(row)
	var portrait := UiPortrait.create(56.0)
	portrait.setup(s.color, s.class_data)
	row.add_child(portrait)
	var box := UiTheme.vbox(2)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	var name_row := UiTheme.hbox(6)
	name_row.add_child(UiTheme.label(s.label(), UiTheme.GOLD_LABEL, 21, s.color.lightened(0.3)))
	name_row.add_child(UiTheme.label(s.class_data.display_name if s.class_data != null else "", UiTheme.GOLD_LABEL, 21))
	var dir := _upgrade_direction(s)
	if roll != null and roll.item != null and not roll.item.can_be_used_by(s.class_data):
		name_row.add_child(UiTheme.label("can't use", UiTheme.SMALL, 15, UiTheme.RED.lightened(0.2)))
	elif dir != 0:
		name_row.add_child(RollIcon.make(RollIcon.Kind.UP if dir > 0 else RollIcon.Kind.DOWN, 20.0))
	if won:
		name_row.add_child(UiIcon.create(UiIcon.Kind.CROWN, Vector2(24, 20)))
	box.add_child(name_row)
	var status := UiTheme.hbox(6)
	box.add_child(status)
	if revealed:
		match choice:
			LootRoll.Choice.NEED, LootRoll.Choice.GREED:
				var need := choice == LootRoll.Choice.NEED
				status.add_child(RollIcon.make(RollIcon.Kind.DICE if need else RollIcon.Kind.COIN, 26.0))
				var label := ("Take" if need else "Sell") if is_solo() else ("Need" if need else "Greed")
				if roll.rolls.has(s.index) and not is_solo():
					label += "  %d" % int(roll.rolls[s.index])
				status.add_child(UiTheme.label(label, UiTheme.GOLD_LABEL, 24, UiTheme.GOLD_BRIGHT if won else UiTheme.TEXT))
			_:
				status.add_child(RollIcon.make(RollIcon.Kind.PASS, 26.0))
				var label := ("Leave" if is_solo() else "Pass") + (" (time)" if timed_out.get(s.index, false) else "")
				status.add_child(UiTheme.label(label, &"", 20, UiTheme.TEXT_DIM))
	elif choice != LootRoll.Choice.UNDECIDED:
		status.add_child(UiIcon.create(UiIcon.Kind.CHECK, Vector2(22, 22)))
		var text := "Decided"
		if greed_all.get(s.index, false):
			text = "Selling all" if is_solo() else "Greed all"
		status.add_child(UiTheme.label(text, &"", 20, UiTheme.GREEN))
	elif s.is_bot():
		status.add_child(UiTheme.label("Thinking…", &"", 19, UiTheme.TEXT_DIM))
	else:
		var reason := need_reason(s)
		if _flash.has(s.index):
			status.add_child(UiTheme.label("Need: %s" % reason, &"", 18, UiTheme.RED.lightened(0.2)))
		elif reason != "":
			var a := UiGlyph.for_input(s.input, PlayerInput.Pad.A, 22.0)
			a.modulate = Color(1, 1, 1, 0.35)
			status.add_child(a)
			status.add_child(UiTheme.label(reason, &"", 17, Color(0.6, 0.55, 0.5)))
		else:
			status.add_child(UiTheme.label("Choosing…", &"", 19, UiTheme.TEXT_DIM))


## Small vector icons of the roll window: dice (Need), coin (Greed), pass, upgrade arrows.
class RollIcon extends Control:
	enum Kind { DICE, COIN, PASS, UP, DOWN }

	var kind := Kind.DICE

	static func make(p_kind: Kind, p_size: float) -> RollIcon:
		var r := RollIcon.new()
		r.kind = p_kind
		r.custom_minimum_size = Vector2(p_size, p_size)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return r

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var c := size * 0.5
		var line := Color(0.07, 0.04, 0.02)
		match kind:
			Kind.DICE:
				var r := Rect2(c - Vector2(s, s) * 0.42, Vector2(s, s) * 0.84)
				var box := StyleBoxFlat.new()
				box.bg_color = Color(0.95, 0.92, 0.85)
				box.border_color = line
				box.set_border_width_all(2)
				box.set_corner_radius_all(int(s * 0.16))
				box.anti_aliasing = true
				draw_style_box(box, r)
				var pip := s * 0.075
				for p in [Vector2(0.3, 0.3), Vector2(0.7, 0.7), Vector2(0.5, 0.5), Vector2(0.7, 0.3), Vector2(0.3, 0.7)]:
					draw_circle(r.position + r.size * p, pip, Color(0.6, 0.08, 0.06))
			Kind.COIN:
				draw_circle(c + Vector2(0, 1), s * 0.42, Color(0, 0, 0, 0.4))
				draw_circle(c, s * 0.42, line)
				draw_circle(c, s * 0.37, UiTheme.GOLD)
				draw_circle(c - Vector2(s, s) * 0.06, s * 0.22, UiTheme.GOLD_BRIGHT)
				draw_arc(c, s * 0.27, 0.0, TAU, 20, UiTheme.GOLD_DARK, 1.5, true)
			Kind.PASS:
				draw_circle(c, s * 0.42, line)
				draw_circle(c, s * 0.36, Color(0.32, 0.29, 0.26))
				draw_line(c + Vector2(-s, -s) * 0.22, c + Vector2(s, s) * 0.22, Color(0.85, 0.82, 0.78), 3.0, true)
				draw_line(c + Vector2(s, -s) * 0.22, c + Vector2(-s, s) * 0.22, Color(0.85, 0.82, 0.78), 3.0, true)
			Kind.UP, Kind.DOWN:
				var up := kind == Kind.UP
				var col := UiTheme.GREEN if up else UiTheme.RED
				var d := -1.0 if up else 1.0
				var tri := PackedVector2Array([c + Vector2(0, d * s * 0.42), c + Vector2(s * 0.36, d * s * 0.02), c + Vector2(-s * 0.36, d * s * 0.02)])
				draw_colored_polygon(tri, col)
				draw_rect(Rect2(c + Vector2(-s * 0.13, -s * 0.02 if up else -s * 0.4), Vector2(s * 0.26, s * 0.42)), col)
				var outline := tri.duplicate()
				outline.append(tri[0])
				draw_polyline(outline, line, 1.5, true)
