class_name ShrineScreen
extends Control
## The SHRINE phase of the between-wave screen (GDD 16.1, 12; M6b): a shrine's card – name, icon, flavour, the
## BOON and the BANE – and the party's vote on it, shared by 1-4 players. Every player with a hero says
## Accept (A) or Decline (B) on their own controller; ALL must accept, a single Decline (or the clock,
## [constant ShrineVote.VOTE_TIME] seconds) declines the shrine. Bots vote by the data ([method
## Shrines.bot_accepts]: Greed / Haste / Learning / Blood yes, Fortune / the Gambler no), at once – or after
## [member bot_think_time] in the demo; a player whose controller is unplugged votes like a bot. The
## decision shows for a moment (the result line: who declined / time ran out / what the shrine does), then
## [signal finished].
##
## Driven by Intermission (update(delta) every frame while the phase runs):
##   open(data, slots)  – builds the card, one chip per voter (portrait, class, vote), starts the vote;
##   update(delta)      – the clock, the bots, the humans' input (the opening frame is skipped, held buttons
##                        are swallowed and A / B wait INPUT_LOCKOUT: a Need / Greed press of the loot roll
##                        must not vote), the decision;
##   decided            – the vote is over (accepted?, why): the Intermission applies the effect
##                        (Shrines.accept) and hands the text back with [method show_result];
##   finished           – the result had its time; the break goes on.
## The vote itself is the pure model [ShrineVote].

signal decided(accepted: bool, reason: StringName)
signal finished

enum Phase { IDLE, VOTING, RESULT, DONE }

## Seconds A / B are ignored after the phase starts.
const INPUT_LOCKOUT := 0.4
## Seconds the decision shows before the break goes on (0 when only bots voted and the screen is not slowed
## for watching: smoke runs).
const RESULT_TIME := 2.4
const TIMER_WARN := 5.0
const CARD_WIDTH := 680.0
const ICON_SIZE := 104.0
## The shrine's name sits right of the icon (card width - margins - icon - gap): the heading font shrinks
## from NAME_FONT until the name fits ("Shrine of the Gambler" in the wide title font).
const NAME_FONT := 40
const NAME_WIDTH := CARD_WIDTH - 60.0 - ICON_SIZE - 20.0
const CHIP_SIZE := Vector2(290, 96)
const TIMER_SIZE := Vector2(520, 30)
const TITLE_TOP := 26.0
const BOTTOM_MARGIN := 24.0
## With a human at the screen the bots wait at least this long (seconds, then a little more per slot), so the
## card is seen before it can be declined.
const MIN_BOT_DELAY := 0.9

## Setting: seconds for the vote ([constant ShrineVote.VOTE_TIME]; <= 0 = no clock).
static var vote_time := ShrineVote.VOTE_TIME

## Seconds a bot "thinks" before it votes (0 = at once; the demo slows the bots down).
var bot_think_time := 0.0
var data: ShrineData
var vote: ShrineVote
var phase := Phase.IDLE
## The voters (slots with a hero), in slot order.
var voters: Array[PlayerSlot] = []
## The decision's headline and the lines under it ([method show_result]).
var result_headline := ""
var result_lines: Array[String] = []

var title_label: Label
var subtitle_label: Label
var card: PanelContainer
var icon: ShrineIcon
var name_label: Label
var duration_label: Label
var flavour_label: Label
var boon_head: Label
var boon_box: VBoxContainer
var bane_head: Label
var bane_box: VBoxContainer
var timer_bar: UiBar
var result_box: VBoxContainer
var result_label: Label
var result_detail: Label
var chips_row: HBoxContainer
var legend: HBoxContainer

var _backdrop: TextureRect
var _skip_frames := 0
var _lockout := 0.0
var _result_left := 0.0
var _bot_wait: Dictionary[int, float] = {}
var _chips: Dictionary[int, PanelContainer] = {}
var _chip_keys: Dictionary[int, String] = {}


static func create() -> ShrineScreen:
	var s := ShrineScreen.new()
	s.name = "ShrineScreen"
	s._build()
	return s


## Slots that can vote: a valid hero, in slot order.
static func voters_of(slots: Array[PlayerSlot]) -> Array[PlayerSlot]:
	return LevelUpScreen.pickers(slots)


## Bots and players whose controller has been missing for the grace (PlayerManager.auto_decide_grace) vote by the
## data, without waiting for input.
static func is_automatic(s: PlayerSlot) -> bool:
	return s.is_bot() or PlayerManager.is_absent(s)


## Opens the vote on [param p_data] for [param p_slots]; false (and nothing shown) without a shrine or a voter.
func open(p_data: ShrineData, p_slots: Array[PlayerSlot]) -> bool:
	data = p_data
	voters = voters_of(p_slots)
	_bot_wait.clear()
	result_headline = ""
	result_lines.clear()
	if data == null or voters.is_empty():
		phase = Phase.IDLE
		vote = null
		hide()
		return false
	var ids: Array[int] = []
	for s in voters:
		ids.append(s.index)
		if not s.is_bot() and s.input != null:
			s.input.swallow()
	vote = ShrineVote.create(ids, vote_time)
	phase = Phase.VOTING
	_skip_frames = 1
	_lockout = INPUT_LOCKOUT
	_fill_card()
	_rebuild_chips()
	_show_block(false)
	_update_timer()
	show()
	return true


func is_voting() -> bool:
	return phase == Phase.VOTING


func is_active() -> bool:
	return phase == Phase.VOTING or phase == Phase.RESULT


## A player left (or their hero is gone): their vote goes away and the others may now be unanimous.
func remove_slot(slot_index: int) -> void:
	if vote == null:
		return
	for i in range(voters.size() - 1, -1, -1):
		if voters[i].index == slot_index:
			voters.remove_at(i)
	_bot_wait.erase(slot_index)
	if phase == Phase.VOTING:
		vote.remove_voter(slot_index)
	_rebuild_chips()
	if phase == Phase.VOTING and vote.is_decided():
		_decide()


## Closes the phase without finishing it (the intermission was reopened, or the phase is over).
func close() -> void:
	phase = Phase.IDLE
	vote = null
	hide()


func set_backdrop_opacity(alpha: float) -> void:
	_backdrop.modulate.a = alpha


## The text under the decision's headline (what the shrine did): called from the [signal decided] handler.
func show_result(lines: Array[String]) -> void:
	result_lines = lines.duplicate()
	if phase == Phase.RESULT:
		_fill_result()


## Seconds the decision stays: nothing when only bots / unplugged pads voted and nobody watches, else RESULT_TIME.
func result_time() -> float:
	if bot_think_time <= 0.0:
		var human := false
		for s in voters:
			if not is_automatic(s):
				human = true
		if not human:
			return 0.0
	return RESULT_TIME


# --- Frame ---------------------------------------------------------------------------------

## One frame of the phase (called by Intermission._update_shrine).
func update(delta: float) -> void:
	match phase:
		Phase.VOTING:
			_update_voting(delta)
		Phase.RESULT:
			_result_left -= delta
			if _result_left <= 0.0:
				phase = Phase.DONE
				finished.emit()


func _update_voting(delta: float) -> void:
	vote.tick(delta)
	_lockout = maxf(0.0, _lockout - delta)
	var skip := _skip_frames > 0
	if skip:
		_skip_frames -= 1
	var humans_present := false
	for s in voters:
		if not is_automatic(s):
			humans_present = true
	for s in voters.duplicate():
		if vote.is_decided():
			break
		if is_automatic(s):
			_auto_vote(s, delta, humans_present)
		elif not skip and _lockout <= 0.0:
			_handle_input(s)
	_update_timer()
	_refresh_chips()
	if vote.is_decided():
		_decide()


## A bot (or an unplugged pad) votes by the data, after its think time.
func _auto_vote(s: PlayerSlot, delta: float, humans_present: bool) -> void:
	if vote.choice_of(s.index) != ShrineVote.Choice.UNDECIDED:
		return
	var wait := 0.0
	if s.is_bot():
		wait = bot_think_time * (1.0 + 0.4 * float(s.index % 3))
		if humans_present:
			wait = maxf(wait, MIN_BOT_DELAY * (1.0 + 0.3 * float(s.index % 3)))
	if wait > 0.0:
		_bot_wait[s.index] = float(_bot_wait.get(s.index, wait)) - delta
		if float(_bot_wait[s.index]) > 0.0:
			return
	vote.cast(s.index, Shrines.bot_accepts(data, vote.voters.size()))


## A = Accept, B = Decline (a first press counts, an Accept may still turn into a Decline).
func _handle_input(s: PlayerSlot) -> void:
	var inp := s.input
	if inp.just_pressed(PlayerInput.Pad.A):
		vote.cast(s.index, true)
		Audio.play_ui(&"ui_confirm")
	elif inp.just_pressed(PlayerInput.Pad.B):
		vote.cast(s.index, false)
		Audio.play_ui(&"ui_back")


func _decide() -> void:
	phase = Phase.RESULT
	_result_left = result_time()
	result_headline = headline()
	_show_block(true)
	_fill_result()
	_refresh_chips(true)
	decided.emit(vote.is_accepted(), vote.reason)
	if _result_left <= 0.0 and phase == Phase.RESULT:
		# Nobody is watching (bots only): the break goes on in the same frame.
		phase = Phase.DONE
		finished.emit()


## The decision's headline ("Everyone accepted", "P2 declined – the shrine fades").
func headline() -> String:
	if vote == null:
		return ""
	match vote.reason:
		&"accepted":
			return "Accepted by everyone" if voters.size() > 1 else "Accepted"
		&"declined":
			var who: Array[String] = []
			for s in voters:
				if vote.choice_of(s.index) == ShrineVote.Choice.DECLINE:
					who.append(s.label())
			return "%s declined – the shrine fades" % ", ".join(PackedStringArray(who))
		&"timeout":
			return "Time ran out – the shrine fades"
	return "The shrine fades"


# --- Build ---------------------------------------------------------------------------------

func _build() -> void:
	UiTheme.setup_root(self)
	_backdrop = UiTheme.backdrop(0.9, Color(0.34, 0.2, 0.46))
	add_child(_backdrop)

	var top := UiTheme.vbox(0)
	top.anchor_left = 0.5
	top.anchor_right = 0.5
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.offset_top = TITLE_TOP
	add_child(top)
	title_label = UiTheme.centered_label("A Shrine!", UiTheme.TITLE, 56)
	top.add_child(title_label)
	subtitle_label = UiTheme.centered_label("", UiTheme.DIM, UiTheme.FONT_BODY)
	top.add_child(subtitle_label)

	var middle := UiTheme.vbox(16)
	middle.name = "Middle"
	middle.anchor_left = 0.5
	middle.anchor_right = 0.5
	middle.anchor_top = 0.5
	middle.anchor_bottom = 0.5
	middle.grow_horizontal = Control.GROW_DIRECTION_BOTH
	# The card stays where it is; the result (a few lines for Fortune) grows downwards under it.
	middle.grow_vertical = Control.GROW_DIRECTION_END
	middle.offset_top = -300.0
	middle.offset_bottom = -300.0
	add_child(middle)
	card = _build_card()
	middle.add_child(card)
	var status := UiTheme.vbox(6)
	status.custom_minimum_size = Vector2(CARD_WIDTH, 92)
	middle.add_child(status)
	timer_bar = UiBar.create(Color(0.95, 0.62, 0.15), TIMER_SIZE.y, 18)
	timer_bar.animated = false
	timer_bar.custom_minimum_size = TIMER_SIZE
	timer_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	status.add_child(timer_bar)
	result_box = UiTheme.vbox(2)
	result_box.visible = false
	status.add_child(result_box)
	result_label = UiTheme.centered_label("", UiTheme.HEADING, 32)
	result_box.add_child(result_label)
	result_detail = UiTheme.wrapped_label("", &"", 21, UiTheme.TEXT)
	result_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_box.add_child(result_detail)

	var bottom := UiTheme.vbox(10)
	bottom.anchor_left = 0.5
	bottom.anchor_right = 0.5
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_top = -BOTTOM_MARGIN
	bottom.offset_bottom = -BOTTOM_MARGIN
	add_child(bottom)
	chips_row = UiTheme.hbox(14)
	chips_row.alignment = BoxContainer.ALIGNMENT_CENTER
	chips_row.custom_minimum_size = Vector2(0, CHIP_SIZE.y)
	bottom.add_child(chips_row)
	legend = UiTheme.hbox(22)
	legend.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(legend)
	_build_legend()
	visible = false


func _build_card() -> PanelContainer:
	var panel := UiTheme.panel()
	panel.name = "Card"
	panel.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	var style := UiTheme.card_style()
	style.content_margin_left = 30
	style.content_margin_right = 30
	style.content_margin_top = 22
	style.content_margin_bottom = 24
	panel.add_theme_stylebox_override(&"panel", style.rebuild())
	var col := UiTheme.vbox(12)
	panel.add_child(col)
	var head := UiTheme.hbox(20)
	col.add_child(head)
	icon = ShrineIcon.create(null, ICON_SIZE)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(icon)
	var names := UiTheme.vbox(4)
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	name_label = UiTheme.label("", UiTheme.HEADING, NAME_FONT)
	names.add_child(name_label)
	duration_label = UiTheme.label("", UiTheme.DIM, 22)
	names.add_child(duration_label)
	col.add_child(UiTheme.divider())
	flavour_label = UiTheme.wrapped_label("", UiTheme.DIM, 21)
	col.add_child(flavour_label)
	boon_head = UiTheme.label("BOON", UiTheme.HEADING, 24, UiTheme.GREEN)
	boon_box = UiTheme.vbox(2)
	col.add_child(_section(boon_head, boon_box))
	bane_head = UiTheme.label("BANE", UiTheme.HEADING, 24, UiTheme.RED)
	bane_box = UiTheme.vbox(2)
	col.add_child(_section(bane_head, bane_box))
	return panel


## A heading with its lines right under it (the sections of the card stay apart from each other).
func _section(head: Label, box: VBoxContainer) -> VBoxContainer:
	var section := UiTheme.vbox(0)
	section.add_child(head)
	section.add_child(box)
	return section


func _build_legend() -> void:
	for c in legend.get_children():
		legend.remove_child(c)
		c.queue_free()
	var parts: Array = [
		[UiGlyph.pad(PlayerInput.Pad.A), "Accept"],
		[UiGlyph.pad(PlayerInput.Pad.B), "Decline"],
	]
	legend.add_child(UiTheme.prompt_row(parts, UiTheme.FONT_BODY, UiTheme.TEXT))
	var keys := UiTheme.label("Keyboard: Enter / Esc", UiTheme.SMALL, 17)
	keys.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	legend.add_child(keys)


# --- Content -------------------------------------------------------------------------------

func _fill_card() -> void:
	icon.set_data(data)
	icon.set_badge(0)
	name_label.text = data.display_name
	name_label.add_theme_font_size_override(&"font_size", UiTheme.fitted_font_size(
			UiTheme.title_font(), data.display_name, NAME_WIDTH, NAME_FONT))
	name_label.add_theme_color_override(&"font_color", data.color.lightened(0.3))
	duration_label.text = Shrines.duration_text(data)
	flavour_label.text = data.description
	flavour_label.visible = data.description != ""
	var style := UiTheme.card_style(data.color.darkened(0.05))
	style.content_margin_left = 30
	style.content_margin_right = 30
	style.content_margin_top = 22
	style.content_margin_bottom = 24
	style.glow = Color(data.color, 0.35)
	style.glow_size = 18
	card.add_theme_stylebox_override(&"panel", style.rebuild())
	var boons := Shrines.boon_lines(data)
	var banes := Shrines.bane_lines(data)
	_fill_lines(boon_head, boon_box, boons, UiTheme.GREEN.lightened(0.45))
	_fill_lines(bane_head, bane_box, banes, UiTheme.RED.lightened(0.4))
	if voters.size() > 1:
		subtitle_label.text = "Everyone must accept – one Decline, or the clock, and the shrine fades"
	else:
		subtitle_label.text = "Accept the offer, or let the shrine fade"


func _fill_lines(head: Label, box: VBoxContainer, lines: Array[String], color: Color) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	head.get_parent().visible = not lines.is_empty()
	for line in lines:
		box.add_child(UiTheme.label(line, &"", 27, color))


## Timer bar (voting) or the decision (result).
func _show_block(result: bool) -> void:
	timer_bar.visible = not result and vote != null and vote.time_limit > 0.0
	result_box.visible = result


func _update_timer() -> void:
	if vote == null or vote.time_limit <= 0.0:
		timer_bar.visible = false
		return
	timer_bar.set_values(vote.time_left, vote.time_limit, "Decide in %d s" % ceili(vote.time_left))
	timer_bar.set_fill_color(UiTheme.RED if vote.time_left <= TIMER_WARN else Color(0.95, 0.62, 0.15))


func _fill_result() -> void:
	var color := UiTheme.GREEN.lightened(0.2) if vote != null and vote.is_accepted() else UiTheme.RED.lightened(0.25)
	result_label.text = result_headline
	result_label.add_theme_color_override(&"font_color", color)
	result_detail.text = "\n".join(PackedStringArray(result_lines))
	result_detail.visible = not result_lines.is_empty()


func _rebuild_chips() -> void:
	for c in chips_row.get_children():
		chips_row.remove_child(c)
		c.queue_free()
	_chips.clear()
	_chip_keys.clear()
	for s in voters:
		var chip := PanelContainer.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.custom_minimum_size = CHIP_SIZE
		chips_row.add_child(chip)
		_chips[s.index] = chip
	_refresh_chips(true)


func _refresh_chips(force: bool = false) -> void:
	if vote == null:
		return
	for s in voters:
		var chip: PanelContainer = _chips.get(s.index)
		if chip == null:
			continue
		# (missing / absent: "Reconnecting…" and "No controller" replace "Choosing…" while the pad is away)
		var key := "%d:%d:%s:%s" % [vote.choice_of(s.index), phase, PlayerManager.is_missing(s), PlayerManager.is_absent(s)]
		if force or _chip_keys.get(s.index, "") != key:
			_chip_keys[s.index] = key
			_fill_chip(chip, s)


func _fill_chip(chip: PanelContainer, s: PlayerSlot) -> void:
	for c in chip.get_children():
		chip.remove_child(c)
		c.queue_free()
	var choice := vote.choice_of(s.index)
	var style := UiTheme.inset_style()
	style.border = s.color.darkened(0.1)
	style.border_width = 2
	style.fill = UiTheme.STONE_DARK
	if choice == ShrineVote.Choice.ACCEPT:
		style.border = UiTheme.GREEN.darkened(0.1)
	elif choice == ShrineVote.Choice.DECLINE:
		style.border = UiTheme.RED
	style.content_margin_left = 10
	style.content_margin_right = 12
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
	box.add_child(name_row)
	var status := UiTheme.hbox(6)
	box.add_child(status)
	match choice:
		ShrineVote.Choice.ACCEPT:
			status.add_child(VoteMark.make(true, 24.0))
			status.add_child(UiTheme.label("Accept", &"", 22, UiTheme.GREEN))
		ShrineVote.Choice.DECLINE:
			status.add_child(VoteMark.make(false, 24.0))
			status.add_child(UiTheme.label("Decline", &"", 22, UiTheme.RED.lightened(0.15)))
		_:
			var waiting := "Thinking…" if s.is_bot() else ("No controller" if PlayerManager.is_absent(s) else ("Reconnecting…" if PlayerManager.is_missing(s) else "Choosing…"))
			if phase == Phase.RESULT:
				waiting = "–"
			status.add_child(UiTheme.label(waiting, &"", 19, UiTheme.TEXT_DIM))


## The vote's tick (green) or cross (red).
class VoteMark extends Control:
	var accept := true

	static func make(p_accept: bool, p_size: float) -> VoteMark:
		var m := VoteMark.new()
		m.accept = p_accept
		m.custom_minimum_size = Vector2(p_size, p_size)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return m

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var dark := Color(0.08, 0.05, 0.03)
		if accept:
			var pts := PackedVector2Array([Vector2(0.14, 0.52) * s, Vector2(0.4, 0.78) * s, Vector2(0.88, 0.22) * s])
			draw_polyline(pts, dark, s * 0.26, true)
			draw_polyline(pts, UiTheme.GREEN, s * 0.15, true)
		else:
			var a := [Vector2(0.2, 0.2) * s, Vector2(0.8, 0.8) * s]
			var b := [Vector2(0.8, 0.2) * s, Vector2(0.2, 0.8) * s]
			for line: Array in [a, b]:
				draw_line(line[0], line[1], dark, s * 0.26, true)
			for line: Array in [a, b]:
				draw_line(line[0], line[1], UiTheme.RED, s * 0.15, true)
