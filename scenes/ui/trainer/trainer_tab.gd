class_name TrainerTab
extends Control
## The Trainer tab of a player's between-wave panel (GDD 6.3, 12; PlayerPanel tab 2): the hero's
## eight ability slots – core RT / LT, learned Active RB / LB, learned Auto-cast 1–4 – as
## TrainerRow lines (slot tag, icon with rank pips, name, Rank I–V, price of the next rank from
## the shared wallet, red when it cannot pay) next to a detail area for the selected ability:
## kind and school, current rank, the description filled from AbilityRunner.params_for (ranks
## and item mods included), what the next rank adds (AbilityRanks.rank_text), the two Rank V
## specialisations (or the chosen one) and the price.
##
## Input (handle_input, the panel's per-player PlayerInput): up / down picks a learned row,
## Y previews the description at the next rank (AbilityRunner.params_at_rank, in green),
## A trains the next rank through Trainer.try_buy_rank. A rank that costs more than
## HOLD_SHARE of the wallet needs A held for HOLD_TIME (the shop's rule; the row fills up; letting
## go, moving or B cancels). Reaching Rank V opens the SpecChooser (left / right, A learns
## AbilityRunner.set_spec, B decides later – the row then reads "Choose" and A reopens it).
## Bots never use it (Trainer.bot_train). Feedback goes out through [signal message].

## Text for the panel's toast: [param bbcode] shown, [param plain] kept as PlayerPanel.last_message.
signal message(bbcode: String, plain: String, color: Color, coin: bool)
## Something the prompt row shows changed (selection, hold, chooser).
signal prompts_changed

## prompt_spec() placeholders for the navigation glyphs (up / down, left / right).
const NAV_PROMPT := -1
const NAV_PROMPT_SIDEWAYS := -2
const HOLD_TIME := ShopPanel.HOLD_TIME
const HOLD_SHARE := ShopPanel.HOLD_SHARE
const LIST_WIDTH := 372.0
const COLUMN_GAP := 10
const ROW_GAP := 3
## Extra room between the core, Active and Auto-cast groups of rows.
const GROUP_GAP := 4
const DETAIL_ICON := 46.0
const SCHOOL_NAMES: Dictionary[StringName, String] = {
	&"physical": "Physical", &"fire": "Fire", &"frost": "Frost", &"arcane": "Arcane",
	&"holy": "Holy", &"shadow": "Shadow", &"nature": "Nature",
}

var slot: PlayerSlot
var rows: Array[TrainerRow] = []
## Selected AbilityRunner slot index (0..7).
var selected := 0
## Y: the detail shows the description with the next rank's numbers.
var preview_next := false
var chooser: SpecChooser
## Detail area labels (tests read them).
var detail_name: Label
var detail_kind: Label
var detail_rank: Label
var detail_description: Label
## "Next: Rank III – <what it adds>" (empty at Rank V).
var detail_next: Label
var detail_spec: Label
var detail_price: Label

var _runner: AbilityRunner
var _focused := false
## {"slot": int, "id": StringName, "price": int, "time": float} while A is held on an expensive rank.
var _hold: Dictionary[String, Variant] = {}
var _detail_icon: AbilityIcon
var _detail_box: VBoxContainer
var _texts: VBoxContainer
var _price_row: HBoxContainer
var _price_coin: UiIcon
var _empty_hint: Label


static func create(p_slot: PlayerSlot) -> TrainerTab:
	var t := TrainerTab.new()
	t.slot = p_slot
	t.name = "TrainerTab"
	t._build()
	return t


# --- Queries ---------------------------------------------------------------------------------

func player() -> Player:
	if slot == null or not is_instance_valid(slot.player):
		return null
	return slot.player as Player


func runner() -> AbilityRunner:
	var p := player()
	return p.abilities if p != null else null


## The ability in slot [param index] (null when empty / no hero).
func ability_at(index: int) -> AbilityData:
	var r := runner()
	if r == null or index < 0 or index >= r.slots.size():
		return null
	return r.slots[index]


func selected_ability() -> AbilityData:
	return ability_at(selected)


func row_for(index: int) -> TrainerRow:
	return rows[index] if index >= 0 and index < rows.size() else null


## Gold for the next rank of slot [param index] (0: empty or Rank V).
func price_of(index: int) -> int:
	var a := ability_at(index)
	return runner().trainer_price(a.id) if a != null else 0


## GDD 10 / shop rule: a rank that takes more than HOLD_SHARE of the wallet needs A held.
static func needs_hold(price: int) -> bool:
	return price > RunState.gold * HOLD_SHARE


## Why slot [param index] cannot be trained right now ("" = it can).
func train_block_reason(index: int) -> String:
	var a := ability_at(index)
	if a == null:
		return "Learn abilities on level-up"
	var r := runner()
	if not r.can_rank_up(a.id):
		return "%s is at Rank V" % a.display_name
	if RunState.gold < r.trainer_price(a.id):
		return "Not enough gold"
	return ""


## 0..1 progress of the running hold-to-train (0 when none).
func hold_progress() -> float:
	return clampf(float(_hold.get("time", 0.0)) / HOLD_TIME, 0.0, 1.0) if not _hold.is_empty() else 0.0


func is_holding() -> bool:
	return not _hold.is_empty()


func is_choosing_spec() -> bool:
	return chooser.is_open()


# --- Actions -----------------------------------------------------------------------------------

## Rebuilds every row and the detail area from the hero's AbilityRunner.
func refresh() -> void:
	_bind_runner(runner())
	var r := _runner
	var input := slot.input if slot != null else null
	for i in rows.size():
		var row := rows[i]
		row.set_tag(input)
		var a := ability_at(i)
		if a == null:
			row.show_ability(null, 0, 0, false, false, false)
			continue
		var price := r.trainer_price(a.id)
		row.show_ability(a, r.rank_of(a.id), price, RunState.gold >= price, r.needs_spec(a.id), r.spec_of(a.id) >= 0)
	if ability_at(selected) == null:
		var first := _first_learned()
		if first >= 0:
			selected = first
	if not _hold.is_empty() and not _hold_still_valid():
		_hold.clear()
	_update_selection()


## Moves the selection [param step] rows up / down over the filled slots.
func move_selection(step: int) -> void:
	if step == 0:
		return
	var i := selected
	for n in rows.size():
		i = posmod(i + signi(step), rows.size())
		if ability_at(i) != null:
			break
	select_slot(i)


func select_slot(index: int) -> void:
	if index < 0 or index >= rows.size() or index == selected:
		return
	selected = index
	_hold.clear()
	_update_selection()


## Whether this tab receives its player's input (selection outline, no hold without it).
func set_focused(on: bool) -> void:
	_focused = on
	if not on:
		_hold.clear()
		if chooser.is_open():
			chooser.close()
	_update_selection()


## A on the selected row: opens the specialisation choice, trains at once, or starts a hold
## when the rank costs more than HOLD_SHARE of the wallet.
func press_train() -> void:
	var a := selected_ability()
	if a == null:
		_say(TrainerRow.EMPTY_TEXT, "", UiTheme.TEXT_DIM)
		return
	if runner().needs_spec(a.id):
		open_spec_choice()
		return
	var reason := train_block_reason(selected)
	if reason != "":
		_say(reason, "", UiTheme.RED)
		return
	var price := price_of(selected)
	if needs_hold(price):
		_hold = {"slot": selected, "id": a.id, "price": price, "time": 0.0}
		_update_selection()
		return
	try_train(selected)


## Buys the next rank of slot [param index] (no hold check) with feedback; Rank V opens the
## specialisation choice. True on success.
func try_train(index: int) -> bool:
	var a := ability_at(index)
	var reason := train_block_reason(index)
	if reason != "":
		_say(reason, "", UiTheme.RED)
		return false
	var price := price_of(index)
	if not Trainer.try_buy_rank(player(), a.id):
		_say("Not enough gold", "", UiTheme.RED)
		return false
	var rank := runner().rank_of(a.id)
	var name_bb := "[color=#%s]%s[/color]" % [UiTheme.GOLD_BRIGHT.to_html(false), a.display_name]
	_say("%s is now Rank %s  -%s" % [name_bb, AbilityIcon.roman(rank), UiTheme.format_int(price)],
		"%s is now Rank %s" % [a.display_name, AbilityIcon.roman(rank)], UiTheme.TEXT, true)
	var row := row_for(index)
	if row != null:
		row.icon.flash_cast()
	if runner().needs_spec(a.id):
		select_slot(index)
		open_spec_choice()
	return true


## Opens the Rank V choice for the selected ability (it must need one).
func open_spec_choice() -> void:
	var a := selected_ability()
	if a == null or not runner().needs_spec(a.id):
		return
	_hold.clear()
	chooser.open(a, _accent())
	prompts_changed.emit()


## Learns specialisation [param index] (0 / 1) for the ability in the chooser.
func choose_spec(index: int) -> bool:
	if not chooser.is_open():
		return false
	var a := chooser.ability
	if not runner().set_spec(a.id, index):
		return false
	chooser.close()
	var spec_name := str(a.specs[index].get("name", ""))
	_say("%s: [color=#%s]%s[/color]" % [a.display_name, AbilityIcon.RANK_SPEC_COLOR.to_html(false), spec_name],
		"%s: %s" % [a.display_name, spec_name], UiTheme.TEXT)
	refresh()
	prompts_changed.emit()
	return true


## Y: switches the description between the current and the next rank's numbers.
func toggle_preview() -> void:
	preview_next = not preview_next
	_update_detail()
	prompts_changed.emit()


func close_spec_choice() -> void:
	chooser.close()
	refresh()
	prompts_changed.emit()


## Called every frame while the tab has its player's input; [param delta] runs the hold timer.
## Returns whether a press was used (B only while it cancels a hold or the chooser).
func handle_input(input: PlayerInput, delta: float) -> bool:
	if input == null:
		return false
	var nav := input.nav_just_pressed()
	if chooser.is_open():
		var used := nav != Vector2i.ZERO or input.just_pressed(PlayerInput.Pad.A) or input.just_pressed(PlayerInput.Pad.B)
		if nav.x != 0:
			chooser.set_choice(chooser.choice + nav.x)
		if input.just_pressed(PlayerInput.Pad.B):
			close_spec_choice()
		elif input.just_pressed(PlayerInput.Pad.A):
			choose_spec(chooser.choice)
		return used
	var used := false
	if not _hold.is_empty():
		if input.just_pressed(PlayerInput.Pad.B):
			used = true
			_cancel_hold()
		elif nav.y != 0 or not input.is_pressed(PlayerInput.Pad.A) or not _hold_still_valid():
			_cancel_hold()
		else:
			_hold["time"] = float(_hold["time"]) + delta
			if float(_hold["time"]) >= HOLD_TIME:
				var index := int(_hold["slot"])
				_hold.clear()
				try_train(index)
			_update_hold_visual()
	if nav.y != 0:
		move_selection(nav.y)
		used = true
	if input.just_pressed(PlayerInput.Pad.Y):
		toggle_preview()
		used = true
	if input.just_pressed(PlayerInput.Pad.A) and _hold.is_empty():
		press_train()
		used = true
	return used


## Button prompts for the panel's prompt row: [button, text] pairs, button a PlayerInput.Pad or
## NAV_PROMPT (up / down). Plain data, so the panel only builds glyphs when the row changes.
func prompt_spec() -> Array:
	if chooser.is_open():
		return [[NAV_PROMPT_SIDEWAYS, "Pick"], [PlayerInput.Pad.A, "Learn"], [PlayerInput.Pad.B, "Later"]]
	var a := selected_ability()
	var items: Array = []
	if a != null:
		if runner().needs_spec(a.id):
			items.append([PlayerInput.Pad.A, "Choose specialization"])
		elif runner().can_rank_up(a.id):
			items.append([PlayerInput.Pad.A, "Hold to train" if needs_hold(price_of(selected)) else "Train"])
			items.append([PlayerInput.Pad.Y, "Now" if preview_next else "Next rank"])
	items.append([NAV_PROMPT, "Select"])
	return items


## Short context text for the panel's prompt row ("Auto-cast 2", "RB" ...).
func context_text() -> String:
	if selected < AbilityRunner.CORE_SLOTS:
		return "Core · %s" % AbilityBar.prompt_text(slot.input if slot != null else null, selected)
	if selected < AbilityRunner.INPUT_SLOTS:
		return "Active · %s" % AbilityBar.prompt_text(slot.input if slot != null else null, selected)
	return "Auto-cast %d" % (selected - AbilityRunner.INPUT_SLOTS + 1)


# --- Build ---------------------------------------------------------------------------------------

func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var body := UiTheme.hbox(COLUMN_GAP)
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(body)
	var list := UiTheme.vbox(ROW_GAP)
	list.custom_minimum_size.x = LIST_WIDTH
	list.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(list)
	for i in AbilityRunner.MAX_SLOTS:
		if i == AbilityRunner.CORE_SLOTS or i == AbilityRunner.INPUT_SLOTS:
			var gap := Control.new()
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			gap.custom_minimum_size.y = GROUP_GAP - ROW_GAP
			list.add_child(gap)
		var row := TrainerRow.create(i)
		list.add_child(row)
		rows.append(row)
	body.add_child(_build_detail())
	chooser = SpecChooser.create()
	add_child(chooser)


func _build_detail() -> Control:
	var panel := UiTheme.panel(UiTheme.INSET_PANEL)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.clip_contents = true
	_detail_box = UiTheme.vbox(4)
	panel.add_child(_detail_box)
	var head := UiTheme.hbox(10)
	_detail_icon = AbilityIcon.create(DETAIL_ICON, false)
	_detail_icon.show_prompt = false
	_detail_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_detail_icon)
	var titles := UiTheme.vbox(0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	detail_name = UiTheme.label("", &"", 21, UiTheme.GOLD_BRIGHT)
	detail_name.add_theme_font_override(&"font", UiTheme.bold_font())
	detail_name.clip_text = true
	detail_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail_name.custom_minimum_size.x = 40
	titles.add_child(detail_name)
	detail_kind = UiTheme.label("", &"", 16, UiTheme.TEXT_DIM)
	titles.add_child(detail_kind)
	head.add_child(titles)
	_detail_box.add_child(head)
	detail_rank = UiTheme.label("", &"", UiTheme.FONT_SMALL, UiTheme.GOLD)
	detail_rank.add_theme_font_override(&"font", UiTheme.bold_font())
	_detail_box.add_child(detail_rank)
	# The texts live in a clipping holder without a minimum size: a long description is cut off
	# instead of pushing the price out of the panel.
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.clip_contents = true
	_detail_box.add_child(holder)
	_texts = UiTheme.vbox(3)
	_texts.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	holder.add_child(_texts)
	detail_description = UiTheme.wrapped_label("", &"", 16, UiTheme.TEXT)
	detail_description.max_lines_visible = 5
	_texts.add_child(detail_description)
	detail_next = UiTheme.wrapped_label("", &"", 16, UiTheme.GREEN)
	detail_next.max_lines_visible = 3
	_texts.add_child(detail_next)
	detail_spec = UiTheme.wrapped_label("", &"", 16, AbilityIcon.RANK_SPEC_COLOR)
	detail_spec.max_lines_visible = 3
	_texts.add_child(detail_spec)
	_price_row = UiTheme.hbox(6)
	_price_row.alignment = BoxContainer.ALIGNMENT_END
	var cap := UiTheme.label("Train", &"", UiTheme.FONT_SMALL, UiTheme.TEXT_DIM)
	_price_row.add_child(cap)
	_price_coin = UiIcon.create(UiIcon.Kind.COIN, Vector2(20, 20))
	_price_coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_price_row.add_child(_price_coin)
	detail_price = UiTheme.label("", &"", 20, UiTheme.GOLD)
	detail_price.add_theme_font_override(&"font", UiTheme.bold_font())
	_price_row.add_child(detail_price)
	_detail_box.add_child(_price_row)
	_empty_hint = UiTheme.wrapped_label("", &"", 16, UiTheme.TEXT_DIM)
	_empty_hint.visible = false
	_detail_box.add_child(_empty_hint)
	return panel


# --- Refresh helpers ------------------------------------------------------------------------------

func _bind_runner(r: AbilityRunner) -> void:
	if r == _runner:
		return
	_unbind_runner()
	_runner = r
	if r != null:
		r.ranks_changed.connect(_on_ranks_changed)
		r.slots_changed.connect(refresh)


func _unbind_runner() -> void:
	if is_instance_valid(_runner):
		if _runner.ranks_changed.is_connected(_on_ranks_changed):
			_runner.ranks_changed.disconnect(_on_ranks_changed)
		if _runner.slots_changed.is_connected(refresh):
			_runner.slots_changed.disconnect(refresh)
	_runner = null


func _on_ranks_changed(_id: StringName) -> void:
	refresh()


func _on_gold_changed(_gold: int, _delta: int) -> void:
	if _runner != null:
		refresh()
		prompts_changed.emit()


func _first_learned() -> int:
	for i in rows.size():
		if ability_at(i) != null:
			return i
	return -1


func _accent() -> Color:
	return (slot.color if slot != null else UiTheme.GOLD).lightened(0.25)


func _update_selection() -> void:
	for i in rows.size():
		rows[i].set_selected(_focused and i == selected, _accent())
	_update_hold_visual()
	_update_detail()
	prompts_changed.emit()


func _update_hold_visual() -> void:
	var holding_slot := int(_hold.get("slot", -1))
	for i in rows.size():
		rows[i].set_hold_progress(hold_progress() if i == holding_slot else 0.0)


func _cancel_hold() -> void:
	_hold.clear()
	_update_hold_visual()
	prompts_changed.emit()


## The held rank is still the selected one at the same price, and still for sale.
func _hold_still_valid() -> bool:
	var index := int(_hold.get("slot", -1))
	var a := ability_at(index)
	return a != null and index == selected and a.id == _hold.get("id") and price_of(index) == int(_hold.get("price", -1)) \
		and runner().can_rank_up(a.id)


func _update_detail() -> void:
	var a := selected_ability()
	var r := _runner
	var filled := a != null and r != null
	for c in _detail_box.get_children():
		c.visible = filled
	for c in _texts.get_children():
		c.visible = filled
	_empty_hint.visible = not filled
	if not filled:
		_detail_icon.set_ability(null)
		_empty_hint.text = "%s\n%s" % [context_text() if slot != null else "", TrainerRow.EMPTY_TEXT]
		return
	var rank := r.rank_of(a.id)
	var spec := r.spec_of(a.id)
	_detail_icon.set_ability(a)
	_detail_icon.set_rank(rank, spec >= 0)
	detail_name.text = a.display_name
	detail_kind.text = "%s · %s" % [TrainerRow.kind_name(selected), SCHOOL_NAMES.get(a.school, String(a.school).capitalize())]
	var preview := preview_next and rank < AbilityRanks.MAX_RANK
	detail_rank.text = "Rank %s of V" % AbilityIcon.roman(rank + 1 if preview else rank) + (" (preview)" if preview else "")
	detail_rank.add_theme_color_override(&"font_color", UiTheme.GREEN if preview else UiTheme.GOLD)
	var params := r.params_at_rank(a, rank + 1, spec) if preview else r.params_for(a)
	detail_description.text = AbilityIcon.format_description(a, params)
	detail_description.add_theme_color_override(&"font_color", UiTheme.GREEN.lightened(0.35) if preview else UiTheme.TEXT)
	detail_description.visible = detail_description.text != ""
	# From Rank IV on the specialisation lines need the room.
	detail_description.max_lines_visible = 4 if rank >= AbilityRanks.MAX_RANK - 1 and not a.specs.is_empty() else 5
	var next := rank + 1
	if rank >= AbilityRanks.MAX_RANK:
		detail_next.text = ""
		detail_next.visible = false
	else:
		detail_next.text = next_rank_text(a, next)
	detail_spec.text = _spec_text(a, rank, spec)
	detail_spec.visible = detail_spec.text != ""
	var price := r.trainer_price(a.id)
	if r.needs_spec(a.id):
		detail_price.text = "Choose a specialization"
		detail_price.add_theme_color_override(&"font_color", AbilityIcon.RANK_SPEC_COLOR)
		_price_row.get_child(0).visible = false
		_price_coin.visible = false
	elif price <= 0:
		detail_price.text = "Max rank"
		detail_price.add_theme_color_override(&"font_color", UiTheme.GOLD_DARK.lightened(0.3))
		_price_row.get_child(0).visible = false
		_price_coin.visible = false
	else:
		detail_price.text = UiTheme.format_int(price)
		detail_price.add_theme_color_override(&"font_color", UiTheme.GOLD if RunState.gold >= price else UiTheme.RED)
		_price_row.get_child(0).visible = true
		_price_coin.visible = true


## "Next: Rank III – +1 knife": what reaching [param rank] adds (AbilityRanks.rank_text).
static func next_rank_text(a: AbilityData, rank: int) -> String:
	return "Next: Rank %s – %s" % [AbilityIcon.roman(rank), AbilityRanks.rank_text(a, rank)]


## The Rank V line: the chosen specialisation, or the two to choose from.
static func _spec_text(a: AbilityData, rank: int, spec: int) -> String:
	if a.specs.is_empty():
		return ""
	if spec >= 0 and spec < a.specs.size():
		return "%s: %s" % [str(a.specs[spec].get("name", "")), str(a.specs[spec].get("text", ""))]
	if rank >= AbilityRanks.MAX_RANK - 1:
		var names := PackedStringArray()
		for s in a.specs:
			names.append(str(s.get("name", "")))
		return " or ".join(names)
	return ""


func _say(bbcode: String, plain: String, color: Color, coin: bool = false) -> void:
	message.emit(bbcode, plain if plain != "" else bbcode, color, coin)


func _enter_tree() -> void:
	if not RunState.gold_changed.is_connected(_on_gold_changed):
		RunState.gold_changed.connect(_on_gold_changed)


func _exit_tree() -> void:
	if RunState.gold_changed.is_connected(_on_gold_changed):
		RunState.gold_changed.disconnect(_on_gold_changed)
	_unbind_runner()
