class_name PortalScreen
extends Control
## The PORTAL phase of the between-wave screen (GDD 16.1, dungeon portal, M6b): "A dungeon portal
## has opened!" and the team's vote. Every player with a hero votes Accept (A) or Decline (B) on their
## own device; it is the reroll vote's rule: ALL must accept for the party to enter, one decline or the
## [constant VOTE_TIME] (20 s) timeout skips the dungeon. The deciding frame emits [signal decided].
##
## - Humans: A / B through their PlayerSlot.input (the opening frame's input is skipped, held buttons
##   are swallowed and A / B wait INPUT_LOCKOUT, so a Need press of the loot roll cannot vote). A vote can
##   still be changed until the decision falls.
## - Bots ([method bot_accepts]): accept after waves 6 and 9 – and whenever the portal was forced with
##   --dungeon –, after 12 and 15 only if nobody was downed in the last wave. They vote at once, or after
##   [member bot_think_time] in the demo (deterministic, no rng).
## - A player whose controller is unplugged abstains (like in the market, nobody is blocked by them); a
##   player who leaves ([method remove_slot]) takes their vote along, and the remaining votes may decide.
## - Nobody left to vote counts as a skip.
## Driven by Intermission (update(delta) every frame of the phase). Look: the portal (violet swirl rings),
## the title, what is inside and what it pays, the countdown bar and one chip per voter.

signal decided(enter: bool)

enum Vote { PENDING, ACCEPT, DECLINE }

## Seconds until a vote nobody finished skips the dungeon (GDD 16.1).
const VOTE_TIME := 20.0
## Seconds A / B are ignored after the phase starts.
const INPUT_LOCKOUT := 0.5
const TIMER_WARN := 6.0
const CHIP_SIZE := Vector2(250, 62)
const PORTAL_SIZE := 250.0
const ACCENT := Color(0.66, 0.42, 1.0)
const INSIDE_TEXT := "4 rooms: Clear · Survive · Defend · Warden"
const REWARD_TEXT := "Reward: an Epic for every hero, maybe a set piece, gold   ·   Failure: the purse loses 50%"
const BOT_THINK_BASE := 1.0

## Setting (demo): seconds a bot "thinks" before it votes (0 = at once).
var bot_think_time := 0.0
var wave := 6
var forced := false
var downs_last_wave := 0
## Seconds until the vote is lost; -1 while the screen is closed.
var time_left := -1.0
## Slot index -> Vote of every voter (slot order in [member order]).
var votes: Dictionary[int, int] = {}
var order: Array[int] = []

var title_label: Label
var subtitle_label: Label
var timer_bar: UiBar

## The portal's picture: nested violet rings and spiral arms that turn with [member clock].
class PortalDisc extends Control:
	var clock := 0.0

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 6.0
		draw_circle(c, r + 5.0, Color(0.04, 0.02, 0.08))
		draw_circle(c, r, PortalScreen.ACCENT.darkened(0.55))
		draw_arc(c, r, 0.0, TAU, 64, UiTheme.GOLD_BORDER, 6.0, true)
		for k in 5:
			var rr := r * (0.9 - 0.17 * float(k))
			var shade := PortalScreen.ACCENT.lerp(Color(0.9, 0.8, 1.0), float(k) / 5.0)
			var a0 := clock * (0.9 + 0.35 * float(k)) * (1.0 if k % 2 == 0 else -1.0)
			for arm in 3:
				var start := a0 + TAU * float(arm) / 3.0
				draw_arc(c, rr, start, start + 1.5, 20, Color(shade, 0.9), 5.0 - 0.5 * float(k), true)
		draw_circle(c, r * 0.09, Color(0.95, 0.9, 1.0, 0.9))


var _open := false
var _skip_frames := 0
var _lockout := 0.0
var _clock := 0.0
var _bot_wait: Dictionary[int, float] = {}
var _chips_row: HBoxContainer
var _chips: Dictionary[int, PanelContainer] = {}
var _chip_keys: Dictionary[int, String] = {}
var _swirl: PortalDisc
var _info_label: Label
var _slots: Dictionary[int, PlayerSlot] = {}


static func create() -> PortalScreen:
	var s := PortalScreen.new()
	s.name = "PortalScreen"
	s._build()
	return s


## Whether a bot votes to enter after [param p_wave]: always after waves 6 and 9 (and any wave while the
## portal was forced), after later waves only when nobody was downed in that wave.
static func bot_accepts(p_wave: int, p_downs_last_wave: int, p_forced: bool) -> bool:
	if p_forced or p_wave <= 9:
		return true
	return p_downs_last_wave <= 0


## Slots that can vote: a hero in play, and a connected device or a bot.
static func voters(slots: Array[PlayerSlot]) -> Array[PlayerSlot]:
	var out: Array[PlayerSlot] = []
	for s in slots:
		if s != null and is_instance_valid(s.player) and s.player is Player and not is_abstaining(s):
			out.append(s)
	out.sort_custom(func(a: PlayerSlot, b: PlayerSlot) -> bool: return a.index < b.index)
	return out


## A human whose controller is unplugged does not vote (nor block).
static func is_abstaining(s: PlayerSlot) -> bool:
	return not s.is_bot() and (s.input == null or not s.input.is_connected_device())


## The pure decision of a set of votes: ACCEPT-all = true, any DECLINE = false, otherwise still open
## (returns null while somebody has not voted and nobody declined).
static func tally(vote_list: Array[int]) -> Variant:
	if vote_list.is_empty():
		return false
	var pending := false
	for v in vote_list:
		if v == Vote.DECLINE:
			return false
		if v == Vote.PENDING:
			pending = true
	return null if pending else true


## Opens the vote for the heroes of [param slots] after wave [param p_wave].
func open(slots: Array[PlayerSlot], p_wave: int, p_forced: bool, p_downs_last_wave: int) -> void:
	wave = p_wave
	forced = p_forced
	downs_last_wave = p_downs_last_wave
	votes.clear()
	order.clear()
	_slots.clear()
	_bot_wait.clear()
	_chip_keys.clear()
	_skip_frames = 1
	_lockout = INPUT_LOCKOUT
	time_left = VOTE_TIME
	_clock = 0.0
	for s in voters(slots):
		if not s.is_bot() and s.input != null:
			s.input.swallow()
		votes[s.index] = Vote.PENDING
		order.append(s.index)
		_slots[s.index] = s
	subtitle_label.text = "Wave %d cleared" % wave
	_rebuild_chips()
	_update_timer()
	_open = true
	show()
	_check_decided()


func is_active() -> bool:
	return _open


## Closes the screen without a decision (the intermission was reopened / the dungeon starts).
func close() -> void:
	_open = false
	time_left = -1.0
	hide()


func set_backdrop_opacity(alpha: float) -> void:
	var backdrop := get_node_or_null(^"Backdrop") as CanvasItem
	if backdrop != null:
		backdrop.modulate.a = alpha


## The vote of slot [param slot_index] (Vote.PENDING for a stranger).
func vote_of(slot_index: int) -> int:
	return votes.get(slot_index, Vote.PENDING)


## Sets a vote (humans press A / B; tests and bots call it too). Ignored after the decision.
func cast(slot_index: int, vote: int) -> void:
	if not _open or not votes.has(slot_index):
		return
	votes[slot_index] = vote
	_chip_keys.erase(slot_index)
	# Shown before the decision: a Decline ends the vote in this call, and update() would not run
	# the refresh again.
	_refresh_chips()
	_check_decided()


## A player left (or their hero is gone): their vote goes away and the others may decide.
func remove_slot(slot_index: int) -> void:
	if not votes.has(slot_index):
		return
	votes.erase(slot_index)
	order.erase(slot_index)
	_slots.erase(slot_index)
	_bot_wait.erase(slot_index)
	_rebuild_chips()
	_check_decided()


# --- Frame -------------------------------------------------------------------------------

## One frame of the phase (Intermission._process while the PORTAL phase runs).
func update(delta: float) -> void:
	if not _open:
		return
	_clock += delta
	time_left = maxf(0.0, time_left - delta)
	_lockout = maxf(0.0, _lockout - delta)
	var skip := _skip_frames > 0
	if skip:
		_skip_frames -= 1
	for i in order.duplicate():
		var s: PlayerSlot = _slots.get(i)
		if s == null or not is_instance_valid(s.player):
			remove_slot(i)
			if not _open:
				return
			continue
		if is_abstaining(s):
			remove_slot(i)
			if not _open:
				return
			continue
		if s.is_bot():
			_bot_update(i, delta)
		elif not skip and _lockout <= 0.0 and s.input != null:
			if s.input.just_pressed(PlayerInput.Pad.A):
				cast(i, Vote.ACCEPT)
			elif s.input.just_pressed(PlayerInput.Pad.B):
				cast(i, Vote.DECLINE)
		if not _open:
			return
	_update_timer()
	_refresh_chips()
	_swirl.clock = _clock
	_swirl.queue_redraw()
	if _open and time_left <= 0.0:
		_decide(false)


func _bot_update(slot_index: int, delta: float) -> void:
	if votes.get(slot_index, Vote.PENDING) != Vote.PENDING:
		return
	if bot_think_time > 0.0:
		if not _bot_wait.has(slot_index):
			_bot_wait[slot_index] = bot_think_time * (BOT_THINK_BASE + 0.4 * float(slot_index % 3))
		_bot_wait[slot_index] -= delta
		if _bot_wait[slot_index] > 0.0:
			return
	cast(slot_index, Vote.ACCEPT if bot_accepts(wave, downs_last_wave, forced) else Vote.DECLINE)


func _check_decided() -> void:
	if not _open:
		return
	var list: Array[int] = []
	for i in order:
		list.append(votes[i])
	var result: Variant = tally(list)
	if result != null:
		_decide(bool(result))


func _decide(enter: bool) -> void:
	if not _open:
		return
	_open = false
	decided.emit(enter)


# --- Build -------------------------------------------------------------------------------

func _build() -> void:
	UiTheme.setup_root(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(UiTheme.backdrop(0.9, Color(0.24, 0.12, 0.42)))
	var col := UiTheme.vbox(10)
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.custom_minimum_size = Vector2(1100, 0)
	add_child(col)
	title_label = UiTheme.centered_label("A dungeon portal has opened!", UiTheme.TITLE, 60)
	title_label.add_theme_constant_override(&"outline_size", 12)
	col.add_child(title_label)
	subtitle_label = UiTheme.centered_label("", UiTheme.DIM, 24)
	col.add_child(subtitle_label)
	_swirl = PortalDisc.new()
	_swirl.name = "Swirl"
	_swirl.custom_minimum_size = Vector2(PORTAL_SIZE, PORTAL_SIZE)
	_swirl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_swirl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_swirl)
	_info_label = UiTheme.centered_label(INSIDE_TEXT, UiTheme.GOLD_LABEL, 26)
	col.add_child(_info_label)
	col.add_child(UiTheme.centered_label(REWARD_TEXT, UiTheme.DIM, 21))
	timer_bar = UiBar.create(ACCENT, 24.0, 18)
	timer_bar.animated = false
	timer_bar.custom_minimum_size = Vector2(520, 24)
	timer_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(timer_bar)
	_chips_row = UiTheme.hbox(14)
	_chips_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_chips_row.custom_minimum_size = Vector2(0, CHIP_SIZE.y)
	col.add_child(_chips_row)
	col.add_child(UiTheme.prompt_row([
		[UiGlyph.pad(PlayerInput.Pad.A, 30.0), "Accept"],
		[UiGlyph.pad(PlayerInput.Pad.B, 30.0), "Decline"],
	], 22, UiTheme.TEXT_DIM))
	col.add_child(UiTheme.centered_label("Everyone has to accept – one decline or the timeout skips the dungeon",
			UiTheme.DIM, 19))
	visible = false


func _update_timer() -> void:
	timer_bar.set_values(time_left, VOTE_TIME, "Skips in %d s" % ceili(time_left))
	timer_bar.set_fill_color(UiTheme.RED if time_left <= TIMER_WARN else ACCENT)


func _rebuild_chips() -> void:
	for c in _chips_row.get_children():
		_chips_row.remove_child(c)
		c.queue_free()
	_chips.clear()
	_chip_keys.clear()
	for i in order:
		var chip := PanelContainer.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.custom_minimum_size = CHIP_SIZE
		_chips_row.add_child(chip)
		_chips[i] = chip
	_refresh_chips()


func _refresh_chips() -> void:
	for i in order:
		var chip: PanelContainer = _chips.get(i)
		var s: PlayerSlot = _slots.get(i)
		if chip == null or s == null:
			continue
		var key := "%d:%s" % [votes[i], s.class_data.id if s.class_data != null else &""]
		if _chip_keys.get(i, "") != key:
			_chip_keys[i] = key
			_fill_chip(chip, s, votes[i])


func _fill_chip(chip: PanelContainer, s: PlayerSlot, vote: int) -> void:
	for c in chip.get_children():
		chip.remove_child(c)
		c.queue_free()
	# A pending chip keeps the neutral frame border: green and red only mean Accept and Decline (the
	# slot colour is on the name instead), so a green or red slot does not read as a vote.
	var border := UiTheme.GOLD_BORDER
	var fill := UiTheme.STONE_DARK
	match vote:
		Vote.ACCEPT:
			border = UiTheme.GREEN
			fill = Color(0.07, 0.13, 0.06, 0.97)
		Vote.DECLINE:
			border = UiTheme.RED
			fill = Color(0.17, 0.06, 0.05, 0.97)
	var style := UiTheme.inset_style()
	style.border = border
	style.border_width = 2
	style.fill = fill
	style.content_margin_left = 7
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	chip.add_theme_stylebox_override(&"panel", style.rebuild())
	var row := UiTheme.hbox(8)
	chip.add_child(row)
	var portrait := UiPortrait.create(46.0)
	portrait.setup(s.color, s.class_data)
	row.add_child(portrait)
	var box := UiTheme.vbox(-2)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(box)
	var name_row := UiTheme.hbox(5)
	name_row.add_child(UiTheme.label(s.label(), UiTheme.GOLD_LABEL, 19, s.color.lightened(0.3)))
	name_row.add_child(UiTheme.label(s.class_data.display_name if s.class_data != null else "", UiTheme.GOLD_LABEL, 19))
	box.add_child(name_row)
	var status := UiTheme.hbox(6)
	match vote:
		Vote.ACCEPT:
			status.add_child(UiIcon.create(UiIcon.Kind.CHECK, Vector2(17, 17)))
			status.add_child(UiTheme.label("Accepted" + (" (bot)" if s.is_bot() else ""), &"", 16, UiTheme.GREEN))
		Vote.DECLINE:
			status.add_child(UiIcon.create(UiIcon.Kind.WARNING, Vector2(17, 17)))
			status.add_child(UiTheme.label("Declined" + (" (bot)" if s.is_bot() else ""), &"", 16, UiTheme.RED))
		_:
			status.add_child(UiGlyph.for_input(s.input, PlayerInput.Pad.A, 22.0))
			status.add_child(UiTheme.label("or", &"", 15, UiTheme.TEXT_DIM))
			status.add_child(UiGlyph.for_input(s.input, PlayerInput.Pad.B, 22.0))
	box.add_child(status)
