class_name LevelUpPanel
extends Control
## One player's region of the LEVEL UP phase (GDD 6.1, 12: "everyone their own, in their own
## quarter"): header in the player's colour (portrait, Pn, class, "Level 5 – pick 1 of 5
## (2 left)"), a row of 5 LevelCardViews, the player's own prompts (their device's glyphs) and
## a short message line. DESIGN_SIZE on the 1920x1080 canvas; LevelUpScreen places / scales it.
##
## State machine per player (only the PlayerInput passed to handle_input drives it):
##   CARDS   – ◀ ▶ move the cursor, A picks, Y rerolls all 5 cards for
##             LevelUpDeck.reroll_price(wave, rerolls) gold from the shared wallet (refused with
##             "Not enough gold" when broke; the price rises with every reroll of this round).
##   REPLACE – a new ability while every slot of its kind is taken: the slots of that kind
##             (icon, name, rank, refund = AbilityRanks.replace_refund) – A replaces
##             (LevelUpDeck.apply with the slot index; the refund goes to the wallet), B back.
##   SPEC    – a pick reached Rank V (AbilityRunner.needs_spec): the two specialisations
##             (name + text), A chooses (AbilityRunner.set_spec). There is no way back.
##   DONE    – every pick made: the summary of what was picked.
## Each pick draws the next hand from the player's own [member rng] (LevelUpScreen seeds it
## from RunState.rng). auto_pick() resolves one pick like a bot (LevelUpDeck.bot_pick; a
## pending specialisation takes the highlighted / first one) – bots, unplugged pads and the
## phase timer use it.

signal card_picked(card: LevelCard, result: Dictionary)
signal picks_finished

enum Mode { CARDS, REPLACE, SPEC, DONE }

const DESIGN_SIZE := Vector2(936, 476)
const CARD_GAP := 9
const ROW_HEIGHT := LevelCardView.CARD_SIZE.y + LevelCardView.LIFT + 4.0
## Seconds A / Y are ignored after a new hand appears or a sub-prompt opens (a mashed A must
## not pick the next card unseen).
const PICK_INPUT_DELAY := 0.3
const MESSAGE_TIME := 2.4
const ENTRY_SIZE := Vector2(196, 196)
const SPEC_SIZE := Vector2(400, 214)

var slot: PlayerSlot
var player: Player
var wave := 1
var picks_total := 0
var picks_done := 0
## Team level the first pick of this round belongs to.
var first_level := 2
var hand: Array[LevelCard] = []
var cursor := 0
var mode := Mode.CARDS
## Rerolls this round (the price rises with each).
var rerolls := 0
var rng: RandomNumberGenerator
## REPLACE: the new ability card and the highlighted entry (index into replace_slots()).
var replace_card: LevelCard
var replace_cursor := 0
## SPEC: the ability that reached Rank V and the highlighted specialisation.
var spec_ability: AbilityData
var spec_cursor := 0
## Seconds until A / Y count again (PICK_INPUT_DELAY).
var input_delay := 0.0
## One line per pick ("Learned Fireball", "Whirlwind: Rank III", "+3 Crit, +2 Agility").
var history: Array[String] = []
## Picks made by auto_pick (bot / timeout / unplugged).
var auto_picks := 0
## The automatic picker drives this panel (bots, unplugged pads): prompts say so.
var automatic := false
var message := ""
var message_bad := false

var cards: Array[LevelCardView] = []
var level_label: Label
var left_label: Label
var message_label: Label

var _frame: PanelContainer
var _row: HBoxContainer
var _stage: Control
var _prompts: HBoxContainer
var _overlay: PanelContainer
var _overlay_box: VBoxContainer
var _done_box: PanelContainer
var _message_left := 0.0
var _prompt_key := ""


static func create(p_slot: PlayerSlot) -> LevelUpPanel:
	var p := LevelUpPanel.new()
	p.name = "LevelUpPanel%d" % (p_slot.index + 1 if p_slot != null else 0)
	p.slot = p_slot
	p.player = p_slot.player as Player if p_slot != null else null
	p._build()
	return p


## Starts this round: [param p_picks] picks (one per level gained), the first for team level
## [param p_first_level], rerolls priced for [param p_wave], hands drawn from [param p_rng].
func begin(p_picks: int, p_first_level: int, p_wave: int, p_rng: RandomNumberGenerator) -> void:
	picks_total = maxi(0, p_picks)
	picks_done = 0
	first_level = p_first_level
	wave = maxi(1, p_wave)
	rng = p_rng if p_rng != null else RunState.rng
	rerolls = 0
	auto_picks = 0
	history.clear()
	cursor = 0
	replace_card = null
	spec_ability = null
	_message_left = 0.0
	message = ""
	if picks_total <= 0:
		mode = Mode.DONE
		hand.clear()
	else:
		mode = Mode.CARDS
		hand = LevelUpDeck.draw(player, rng)
		input_delay = PICK_INPUT_DELAY
	refresh()


func runner() -> AbilityRunner:
	return player.abilities if player != null and is_instance_valid(player) else null


func is_done() -> bool:
	return mode == Mode.DONE


func picks_left() -> int:
	return maxi(0, picks_total - picks_done)


## Team level of the current pick.
func current_level() -> int:
	return first_level + mini(picks_done, maxi(0, picks_total - 1))


## "Level 5 – pick 1 of 5 (2 left)"; "All picks done" at the end.
func level_text() -> String:
	if is_done():
		return "All picks done"
	return "Level %d – pick 1 of %d (%d left)" % [current_level(), hand.size(), picks_left()]


func reroll_price() -> int:
	return LevelUpDeck.reroll_price(wave, rerolls)


## Test / screenshot hook: shows [param p_hand] instead of the drawn one.
func set_hand(p_hand: Array[LevelCard]) -> void:
	hand = p_hand.duplicate()
	cursor = clampi(cursor, 0, maxi(0, hand.size() - 1))
	refresh()


## Runner slot indices a new ability of the REPLACE card's kind could go into.
func replace_slots() -> Array[int]:
	if replace_card == null or replace_card.ability == null:
		return []
	return AbilityRunner.slots_for_kind(replace_card.ability.kind)


# --- Input ---------------------------------------------------------------------------------

## One frame of this player's input. [param can_act]: A / Y / B may act (the screen's lockout
## after it opened is over); navigation always works.
func handle_input(input: PlayerInput, can_act: bool = true) -> void:
	if input == null or mode == Mode.DONE:
		return
	var nav := input.nav_just_pressed()
	var act := can_act and input_delay <= 0.0
	match mode:
		Mode.CARDS:
			if nav.x != 0:
				move_cursor(nav.x)
			if not act:
				return
			if input.just_pressed(PlayerInput.Pad.A):
				pick(cursor)
			elif input.just_pressed(PlayerInput.Pad.Y):
				try_reroll()
		Mode.REPLACE:
			if nav.x != 0:
				move_replace_cursor(nav.x)
			if input.just_pressed(PlayerInput.Pad.B):
				back()
			elif act and input.just_pressed(PlayerInput.Pad.A):
				choose_replacement(replace_cursor)
		Mode.SPEC:
			if nav.x != 0:
				move_spec_cursor(nav.x)
			if act and input.just_pressed(PlayerInput.Pad.A):
				choose_spec(spec_cursor)


func move_cursor(step: int) -> void:
	if hand.is_empty():
		return
	cursor = clampi(cursor + step, 0, hand.size() - 1)
	_refresh_cards()


func move_replace_cursor(step: int) -> void:
	var n := replace_slots().size()
	if n > 0:
		replace_cursor = clampi(replace_cursor + step, 0, n - 1)
		_refresh_overlay()


func move_spec_cursor(step: int) -> void:
	if spec_ability != null and not spec_ability.specs.is_empty():
		spec_cursor = clampi(spec_cursor + step, 0, spec_ability.specs.size() - 1)
		_refresh_overlay()


## Picks hand[[param index]]. A new ability with its slots full opens REPLACE instead; a
## rank-up to Rank V opens SPEC after it was applied. Returns true when the card was applied.
func pick(index: int) -> bool:
	if mode != Mode.CARDS or index < 0 or index >= hand.size():
		return false
	var card := hand[index]
	cursor = index
	if LevelCardView.needs_replacement(card, runner()):
		replace_card = card
		replace_cursor = 0
		mode = Mode.REPLACE
		input_delay = PICK_INPUT_DELAY
		refresh()
		return false
	return _apply(card, -1)


## Rerolls the hand from the shared wallet; false (and a message) when the team is broke.
func try_reroll() -> bool:
	if mode != Mode.CARDS:
		return false
	var price := reroll_price()
	if not RunState.try_spend_for(price, slot.index if slot != null else -1, &"level_reroll", "Level-up reroll"):
		show_message("Not enough gold (%d g)" % price, true)
		return false
	rerolls += 1
	hand = LevelUpDeck.draw(player, rng)
	input_delay = PICK_INPUT_DELAY
	show_message("Rerolled for %d g" % price)
	refresh()
	return true


## REPLACE: B goes back to the cards (nothing changes).
func back() -> void:
	if mode == Mode.REPLACE:
		mode = Mode.CARDS
		replace_card = null
		refresh()


## REPLACE: learns the new ability into the [param entry]-th slot of its kind.
func choose_replacement(entry: int) -> bool:
	var targets := replace_slots()
	if mode != Mode.REPLACE or entry < 0 or entry >= targets.size():
		return false
	var card := replace_card
	replace_card = null
	mode = Mode.CARDS
	return _apply(card, targets[entry])


## SPEC: chooses the [param index]-th specialisation of the ability that reached Rank V.
func choose_spec(index: int) -> bool:
	var r := runner()
	if mode != Mode.SPEC or spec_ability == null or r == null:
		return false
	if not r.set_spec(spec_ability.id, index):
		return false
	var spec_name := str(spec_ability.specs[index].get("name", "?"))
	if not history.is_empty():
		history[history.size() - 1] = "%s: Rank V – %s" % [spec_ability.display_name, spec_name]
	spec_ability = null
	_next_pick()
	return true


## One automatic pick (bots, unplugged pads, the phase timer): a pending specialisation takes
## [param spec] (-1 = the highlighted one), an open REPLACE prompt is cancelled, then
## LevelUpDeck.bot_pick chooses (never a card that needs a replacement).
func auto_pick(spec: int = -1) -> void:
	if mode == Mode.DONE:
		return
	if mode == Mode.SPEC:
		_auto_spec(spec)
		return
	if mode == Mode.REPLACE:
		back()
	var first := bot_choice()
	if first < 0:
		return
	# The bot's card first; should it not apply, the other cards that need no replacement.
	var tries: Array[int] = [first]
	for i in hand.size():
		if i != first and not LevelCardView.needs_replacement(hand[i], runner()):
			tries.append(i)
	for index in tries:
		cursor = index
		if _apply(hand[index], -1):
			auto_picks += 1
			if mode == Mode.SPEC:
				_auto_spec(spec)
			return


## Every remaining pick automatically (see auto_pick).
func auto_finish(spec: int = -1) -> void:
	var guard := picks_total * 3 + 3
	while mode != Mode.DONE and guard > 0:
		guard -= 1
		auto_pick(spec)
	if mode != Mode.DONE:
		# Nothing pickable (empty hand): count the rest as skipped.
		picks_done = picks_total
		_finish()


## The card auto_pick takes: LevelUpDeck.bot_pick, but never one that needs a replacement
## (the first other card then). -1 for an empty hand.
func bot_choice() -> int:
	if hand.is_empty():
		return -1
	var r := runner()
	var index := LevelUpDeck.bot_pick(player, hand)
	if index >= 0 and not LevelCardView.needs_replacement(hand[index], r):
		return index
	for i in hand.size():
		if not LevelCardView.needs_replacement(hand[i], r):
			return i
	return -1


func _auto_spec(spec: int) -> void:
	var count := spec_ability.specs.size() if spec_ability != null else 0
	var i := spec_cursor if spec < 0 else spec
	choose_spec(clampi(i, 0, maxi(0, count - 1)))


func _apply(card: LevelCard, replace_index: int) -> bool:
	var r := runner()
	var replaced: AbilityData = r.slots[replace_index] if r != null and replace_index >= 0 and replace_index < r.slots.size() else null
	var was_known := card.ability != null and r != null and r.knows(card.ability.id)
	var result := LevelUpDeck.apply(player, card, replace_index)
	if not result.get("ok", false):
		show_message("Cannot pick that card", true)
		refresh()
		return false
	history.append(_summary(card, was_known, replaced))
	var refund := int(result.get("refund", 0))
	if refund > 0 and replaced != null:
		show_message("%s replaced: +%d g refund" % [replaced.display_name, refund])
	card_picked.emit(card, result)
	if result.get("needs_spec", false) and card.ability != null:
		spec_ability = card.ability
		spec_cursor = 0
		mode = Mode.SPEC
		input_delay = PICK_INPUT_DELAY
		refresh()
		return true
	_next_pick()
	return true


func _summary(card: LevelCard, was_known: bool, replaced: AbilityData) -> String:
	match card.kind:
		LevelCard.Kind.STAT:
			return ", ".join(card.lines())
		LevelCard.Kind.NEW_ABILITY:
			if was_known:
				return "%s: Rank %s" % [card.ability.display_name, LevelCard.roman(runner().rank_of(card.ability.id))]
			if replaced != null:
				return "Learned %s (for %s)" % [card.ability.display_name, replaced.display_name]
			return "Learned %s" % card.ability.display_name
	var r := runner()
	return "%s: Rank %s" % [card.ability.display_name, LevelCard.roman(r.rank_of(card.ability.id) if r != null else 1)]


func _next_pick() -> void:
	picks_done += 1
	if picks_done >= picks_total:
		_finish()
		return
	mode = Mode.CARDS
	hand = LevelUpDeck.draw(player, rng)
	cursor = clampi(cursor, 0, maxi(0, hand.size() - 1))
	input_delay = PICK_INPUT_DELAY
	refresh()


func _finish() -> void:
	mode = Mode.DONE
	hand.clear()
	refresh()
	picks_finished.emit()


# --- Frame ---------------------------------------------------------------------------------

## Timers (input delay, message); called by LevelUpScreen every frame.
func tick(delta: float) -> void:
	input_delay = maxf(0.0, input_delay - delta)
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			message = ""
			message_label.text = ""


func show_message(text: String, bad: bool = false) -> void:
	message = text
	message_bad = bad
	_message_left = MESSAGE_TIME
	message_label.text = text
	message_label.add_theme_color_override(&"font_color", UiTheme.RED.lightened(0.15) if bad else UiTheme.GREEN)


## Reroll price colour follows the wallet (LevelUpScreen calls it on gold changes).
func refresh_prompts() -> void:
	var key := "%d:%d:%d:%s:%d" % [mode, reroll_price(), RunState.gold, automatic, picks_left()]
	if key == _prompt_key:
		return
	_prompt_key = key
	for c in _prompts.get_children():
		_prompts.remove_child(c)
		c.queue_free()
	var input := slot.input if slot != null else null
	var parts: Array = []
	if mode == Mode.DONE:
		parts.append(["Waiting for the others…"])
	elif automatic:
		parts.append(["Picks automatically"])
	else:
		match mode:
			Mode.CARDS:
				parts.append([UiGlyph.nav(24.0), "Choose"])
				parts.append([UiGlyph.for_input(input, PlayerInput.Pad.A, 28.0), "Pick"])
				var price := reroll_price()
				var coin := UiIcon.create(UiIcon.Kind.COIN, Vector2(20, 20))
				var price_label := UiTheme.label(str(price), UiTheme.GOLD_LABEL, 21,
					UiTheme.GOLD if RunState.can_afford(price) else UiTheme.RED)
				parts.append([UiGlyph.for_input(input, PlayerInput.Pad.Y, 28.0), "Reroll", coin, price_label])
			Mode.REPLACE:
				parts.append([UiGlyph.nav(24.0), "Choose"])
				parts.append([UiGlyph.for_input(input, PlayerInput.Pad.A, 28.0), "Replace"])
				parts.append([UiGlyph.for_input(input, PlayerInput.Pad.B, 28.0), "Back"])
			Mode.SPEC:
				parts.append([UiGlyph.nav(24.0), "Choose"])
				parts.append([UiGlyph.for_input(input, PlayerInput.Pad.A, 28.0), "Specialize"])
	var row := UiTheme.prompt_row(parts, 20, UiTheme.TEXT)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_prompts.add_child(row)


## Rebuilds everything shown from the state.
func refresh() -> void:
	if level_label == null:
		return
	level_label.text = "Level %d" % current_level() if not is_done() else "All picks done"
	left_label.text = ("–  pick 1 of %d  (%d left)" % [hand.size(), picks_left()]) if not is_done() else ""
	_refresh_cards()
	_refresh_overlay()
	_refresh_done()
	_prompt_key = ""
	refresh_prompts()


func _refresh_cards() -> void:
	var r := runner()
	var color := slot.color if slot != null else UiTheme.GOLD
	for i in cards.size():
		var view := cards[i]
		var c: LevelCard = hand[i] if i < hand.size() else null
		if view.card != c:
			view.set_card(c, r)
		view.visible = c != null
		view.set_selected(mode == Mode.CARDS and i == cursor, color)
		view.set_dim(mode != Mode.CARDS)


# --- Build ---------------------------------------------------------------------------------

func _build() -> void:
	theme = UiTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = DESIGN_SIZE
	size = DESIGN_SIZE
	var color := slot.color if slot != null else UiTheme.GOLD
	_frame = PanelContainer.new()
	_frame.name = "Frame"
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := UiTheme.stone_style(color.darkened(0.15))
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 8
	_frame.add_theme_stylebox_override(&"panel", style.rebuild())
	add_child(_frame)
	var col := UiTheme.vbox(6)
	_frame.add_child(col)
	col.add_child(_build_header(color))
	_stage = Control.new()
	_stage.name = "Stage"
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_stage)
	_row = UiTheme.hbox(CARD_GAP)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_row.offset_top = LevelCardView.LIFT + 2.0
	_stage.add_child(_row)
	for i in LevelUpDeck.HAND_SIZE:
		var view := LevelCardView.create()
		view.name = "Card%d" % i
		view.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_row.add_child(view)
		cards.append(view)
	_build_overlay()
	_build_done()
	var bottom := UiTheme.hbox(12)
	col.add_child(bottom)
	_prompts = UiTheme.hbox(0)
	_prompts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(_prompts)
	bottom.add_child(UiTheme.spacer())
	message_label = UiTheme.label("", UiTheme.GOLD_LABEL, 20, UiTheme.GREEN)
	message_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(message_label)


func _build_header(color: Color) -> PanelContainer:
	var header := PanelContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hs := StyleBoxFlat.new()
	hs.bg_color = color.darkened(0.55)
	hs.border_color = color
	hs.border_width_bottom = 3
	hs.set_corner_radius_all(4)
	hs.content_margin_left = 8
	hs.content_margin_right = 12
	hs.content_margin_top = 2
	hs.content_margin_bottom = 3
	header.add_theme_stylebox_override(&"panel", hs)
	var row := UiTheme.hbox(10)
	header.add_child(row)
	var portrait := UiPortrait.create(40.0)
	portrait.setup(color, slot.class_data if slot != null else null)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(portrait)
	var who := UiTheme.label(slot.label() if slot != null else "P?", UiTheme.HEADING, 30, color.lightened(0.35))
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(who)
	var cls := UiTheme.label(slot.class_data.display_name if slot != null and slot.class_data != null else "",
		UiTheme.GOLD_LABEL, 25)
	cls.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cls)
	row.add_child(UiTheme.spacer())
	level_label = UiTheme.label("Level 2", UiTheme.GOLD_LABEL, 27, UiTheme.GOLD_BRIGHT)
	level_label.add_theme_font_override(&"font", UiTheme.title_font())
	level_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(level_label)
	left_label = UiTheme.label("", &"", 21, UiTheme.TEXT)
	left_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(left_label)
	return header


## The REPLACE / SPEC sub-prompt: a dark plate over the card row.
func _build_overlay() -> void:
	_overlay = PanelContainer.new()
	_overlay.name = "Prompt"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := UiTheme.stone_style(UiTheme.GOLD_BORDER, Color(0.06, 0.05, 0.045, 0.97))
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	_overlay.add_theme_stylebox_override(&"panel", s.rebuild())
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.offset_top = 2.0
	_overlay.visible = false
	_stage.add_child(_overlay)
	_overlay_box = UiTheme.vbox(14)
	_overlay_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay.add_child(_overlay_box)


func _build_done() -> void:
	_done_box = PanelContainer.new()
	_done_box.name = "Done"
	_done_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := UiTheme.stone_style(UiTheme.GREEN.darkened(0.3), Color(0.06, 0.08, 0.05, 0.96))
	s.content_margin_left = 26
	s.content_margin_right = 26
	_done_box.add_theme_stylebox_override(&"panel", s.rebuild())
	_done_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_done_box.offset_left = 140.0
	_done_box.offset_right = -140.0
	_done_box.offset_top = 70.0
	_done_box.offset_bottom = -70.0
	_done_box.visible = false
	_stage.add_child(_done_box)


func _refresh_done() -> void:
	_done_box.visible = is_done()
	if not _done_box.visible:
		return
	for c in _done_box.get_children():
		_done_box.remove_child(c)
		c.queue_free()
	var col := UiTheme.vbox(6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_done_box.add_child(col)
	var head := UiTheme.hbox(10)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(UiIcon.create(UiIcon.Kind.CHECK, Vector2(30, 30)))
	head.add_child(UiTheme.label("Ready for the market", UiTheme.HEADING, 30, UiTheme.GREEN))
	col.add_child(head)
	col.add_child(UiTheme.divider(0))
	for line in history:
		col.add_child(UiTheme.centered_label(line, &"", 21, UiTheme.TEXT))
	if history.is_empty():
		col.add_child(UiTheme.centered_label("Nothing to pick", &"", 21, UiTheme.TEXT_DIM))


func _refresh_overlay() -> void:
	var show := mode == Mode.REPLACE or mode == Mode.SPEC
	_overlay.visible = show
	if not show:
		return
	for c in _overlay_box.get_children():
		_overlay_box.remove_child(c)
		c.queue_free()
	if mode == Mode.REPLACE:
		_fill_replace()
	else:
		_fill_spec()


func _fill_replace() -> void:
	var a := replace_card.ability
	var r := runner()
	var kind := "Auto-cast" if a.kind == AbilityData.Kind.AUTO else "Active"
	var head := UiTheme.hbox(12)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	var icon := AbilityIcon.create(44.0)
	icon.custom_minimum_size = Vector2(44, 44)
	icon.set_ability(a)
	head.add_child(icon)
	var titles := UiTheme.vbox(-2)
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	titles.add_child(UiTheme.label("Learn %s – your %s slots are full" % [a.display_name, kind], UiTheme.GOLD_LABEL, 24))
	titles.add_child(UiTheme.label("Choose the ability it replaces – you get back half of what its ranks cost", &"", 18, UiTheme.TEXT_DIM))
	head.add_child(titles)
	_overlay_box.add_child(head)
	var row := UiTheme.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay_box.add_child(row)
	var targets := replace_slots()
	var color := slot.color if slot != null else UiTheme.GOLD
	for i in targets.size():
		var old: AbilityData = r.slots[targets[i]] if r != null else null
		row.add_child(_replace_entry(old, r, i == replace_cursor, color))


func _replace_entry(old: AbilityData, r: AbilityRunner, on: bool, color: Color) -> Control:
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size = ENTRY_SIZE if replace_slots().size() <= 2 else Vector2(ENTRY_SIZE.x, 170)
	box.add_theme_stylebox_override(&"panel", _choice_style(on, color))
	var col := UiTheme.vbox(3)
	box.add_child(col)
	var holder := CenterContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := AbilityIcon.create(48.0)
	icon.custom_minimum_size = Vector2(48, 48)
	icon.set_ability(old)
	holder.add_child(icon)
	col.add_child(holder)
	if old == null:
		col.add_child(UiTheme.centered_label("Empty", &"", 19, UiTheme.TEXT_DIM))
		return box
	if icon.has_method(&"set_rank"):
		icon.call(&"set_rank", r.rank_of(old.id), r.spec_of(old.id) >= 0)
	var name := UiTheme.centered_label(old.display_name, &"", 20, AbilityIcon.color_for(old).lerp(Color.WHITE, 0.35))
	name.add_theme_font_override(&"font", UiTheme.bold_font())
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.custom_minimum_size.x = ENTRY_SIZE.x - 24
	col.add_child(name)
	col.add_child(UiTheme.centered_label("Rank %s" % LevelCard.roman(r.rank_of(old.id)), UiTheme.GOLD_LABEL, 19))
	# The wave LevelUpDeck.apply refunds at (RunState.wave = the wave just cleared).
	var refund := AbilityRanks.replace_refund(r.rank_of(old.id), RunState.wave)
	var refund_row := UiTheme.hbox(5)
	refund_row.alignment = BoxContainer.ALIGNMENT_CENTER
	refund_row.add_child(UiTheme.label("Refund", &"", 18, UiTheme.TEXT_DIM))
	var coin := UiIcon.create(UiIcon.Kind.COIN, Vector2(18, 18))
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	refund_row.add_child(coin)
	refund_row.add_child(UiTheme.label(str(refund), UiTheme.GOLD_LABEL, 19, UiTheme.GOLD))
	col.add_child(refund_row)
	return box


func _fill_spec() -> void:
	var a := spec_ability
	var head := UiTheme.hbox(12)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	var icon := AbilityIcon.create(44.0)
	icon.custom_minimum_size = Vector2(44, 44)
	icon.set_ability(a)
	head.add_child(icon)
	var titles := UiTheme.vbox(-2)
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	titles.add_child(UiTheme.label("%s reached Rank V!" % a.display_name, UiTheme.GOLD_LABEL, 25))
	titles.add_child(UiTheme.label("Choose a specialization – it changes how the ability works", &"", 18, UiTheme.TEXT_DIM))
	head.add_child(titles)
	_overlay_box.add_child(head)
	var row := UiTheme.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay_box.add_child(row)
	var color := slot.color if slot != null else UiTheme.GOLD
	for i in a.specs.size():
		var spec: Dictionary = a.specs[i]
		var box := PanelContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.custom_minimum_size = SPEC_SIZE
		box.add_theme_stylebox_override(&"panel", _choice_style(i == spec_cursor, color))
		var col := UiTheme.vbox(6)
		box.add_child(col)
		var title := UiTheme.centered_label(str(spec.get("name", "?")), UiTheme.GOLD_LABEL, 27, UiTheme.GOLD_BRIGHT)
		title.add_theme_font_override(&"font", UiTheme.title_font())
		col.add_child(title)
		col.add_child(UiTheme.divider(0))
		var text := UiTheme.wrapped_label(str(spec.get("text", "")), &"", 20, UiTheme.TEXT)
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text.custom_minimum_size.x = SPEC_SIZE.x - 36
		col.add_child(text)
		row.add_child(box)


func _choice_style(on: bool, color: Color) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.1, 0.085, 0.07, 0.98) if not on else Color(color.darkened(0.7), 0.98)
	st.border_color = color.lightened(0.35) if on else Color(0.35, 0.29, 0.2)
	st.set_border_width_all(4 if on else 2)
	st.set_corner_radius_all(6)
	st.content_margin_left = 12
	st.content_margin_right = 12
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	if on:
		st.shadow_color = Color(color, 0.6)
		st.shadow_size = 14
	st.anti_aliasing = true
	return st
