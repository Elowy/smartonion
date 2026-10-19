class_name LevelUpScreen
extends Control
## The LEVEL UP phase of the between-wave screen (GDD 6.1, 12), shared by 1–4 players: every
## hero picks 1 of 5 cards per level the team gained this wave, each in their own screen
## region (LevelUpPanel) and only with their own PlayerInput. Layout on the 1920x1080 canvas:
## a header band (title; levels, shared gold and the auto-pick countdown bar) and the panels in
## the players' quarters like the HUD / market (P1 top-left, P2 top-right, P3 bottom-left,
## P4 bottom-right; two players side by side, a solo player centred and larger).
##
## Driven by Intermission (update(delta) every frame while the phase runs):
## - open(): one LevelUpPanel per slot with a hero, in slot order; each player gets their own
##   RandomNumberGenerator seeded from RunState.rng in slot order (one draw per player), so the
##   hands are reproducible and one player's rerolls or pick timing never change another's.
## - Humans: their panel's handle_input (◀ ▶, A pick, Y reroll, B back in sub-prompts). The
##   input of the opening frame is skipped, held buttons are swallowed, and A / Y / B wait
##   INPUT_LOCKOUT after the phase starts (a Need / Greed press of the loot roll must not pick).
## - Bots (PlayerSlot.is_bot) pick with LevelUpDeck.bot_pick (spec 0) – at once, or after
##   [member bot_think_time] with a cursor walk (demo); unplugged pads pick at once.
## - The countdown (PICK_TIME + EXTRA_PICK_TIME per further level, [member pick_time] <= 0
##   switches it off) auto-picks every remaining pick of the idle humans (an open
##   specialisation takes the highlighted one).
## finished is emitted once when every panel is done (or nobody can pick).

signal finished
## A player applied a card (statistics).
signal card_picked(slot_index: int, card: LevelCard)

## Seconds for the first pick, plus EXTRA_PICK_TIME per further level gained this wave.
const PICK_TIME := 40.0
const EXTRA_PICK_TIME := 20.0
## Seconds A / Y / B are ignored after the phase starts.
const INPUT_LOCKOUT := 0.4
const TIMER_WARN := 10.0
const MARGIN := 12.0
## Header band (title, info row with the countdown) on the 1920x1080 canvas.
const HEADER_HEIGHT := 94.0
const SOLO_SCALE := 1.45
const TIMER_SIZE := Vector2(330, 28)
## Demo bots move their cursor one card every BOT_STEP_TIME while they "think".
const BOT_STEP_TIME := 0.28

## Setting: seconds for the first pick (<= 0 = no countdown, wait for everybody).
static var pick_time := PICK_TIME

## Seconds a bot "thinks" per pick (0 = picks at once; demo mode slows bots down).
var bot_think_time := 0.0
var level_ups := 0
var wave := 1
## Slot index -> that player's panel (slot order in [member order]).
var panels: Dictionary[int, LevelUpPanel] = {}
var order: Array[int] = []
## Seconds until the remaining picks are made automatically; -1 = no countdown.
var time_left := -1.0
var time_limit := -1.0

var title_label: Label
var subtitle_label: Label
var gold_value: Label
var timer_bar: UiBar

var _backdrop: TextureRect
var _panel_layer: Control
var _timer_box: Control
var _open := false
var _skip_frames := 0
var _lockout := 0.0
var _bot_wait: Dictionary[int, float] = {}
var _bot_step: Dictionary[int, float] = {}
var _bot_target: Dictionary[int, int] = {}
var _bot_picks: Dictionary[int, int] = {}


static func create() -> LevelUpScreen:
	var s := LevelUpScreen.new()
	s.name = "LevelUpScreen"
	s._build()
	return s


## Slots whose hero can pick cards (a valid Player).
static func pickers(slots: Array[PlayerSlot]) -> Array[PlayerSlot]:
	var out: Array[PlayerSlot] = []
	for s in slots:
		if s != null and s.player != null and is_instance_valid(s.player) and s.player is Player:
			out.append(s)
	out.sort_custom(func(a: PlayerSlot, b: PlayerSlot) -> bool: return a.index < b.index)
	return out


## Countdown for [param p_level_ups] picks per player (-1 when switched off).
static func time_for(p_level_ups: int) -> float:
	if pick_time <= 0.0:
		return -1.0
	return pick_time + EXTRA_PICK_TIME * maxi(0, p_level_ups - 1)


## Starts the phase: [param p_level_ups] picks for every slot with a hero, rerolls priced for
## [param p_wave] (the wave just cleared).
func open(slots: Array[PlayerSlot], p_level_ups: int, p_wave: int) -> void:
	level_ups = maxi(0, p_level_ups)
	wave = maxi(1, p_wave)
	_clear_panels()
	_bot_wait.clear()
	_bot_step.clear()
	_bot_target.clear()
	_bot_picks.clear()
	_skip_frames = 1
	_lockout = INPUT_LOCKOUT
	time_limit = time_for(level_ups)
	time_left = time_limit
	var first_level := maxi(RunState.START_LEVEL + 1, RunState.level - level_ups + 1)
	for s in pickers(slots):
		if not s.is_bot() and s.input != null:
			s.input.swallow()
		var panel := LevelUpPanel.create(s)
		panel.automatic = is_automatic(s)
		_panel_layer.add_child(panel)
		panels[s.index] = panel
		order.append(s.index)
		var rng := RandomNumberGenerator.new()
		rng.seed = RunState.rng.randi()
		panel.card_picked.connect(_on_card_picked.bind(s.index))
		panel.begin(level_ups, first_level, wave, rng)
	_layout()
	_fill_header(first_level)
	_update_timer()
	_open = not order.is_empty()
	show()
	if _open:
		Audio.play_ui(&"ui_card_flip")
	if not _open:
		finished.emit.call_deferred()


## Bots and players whose device is unplugged pick automatically.
static func is_automatic(s: PlayerSlot) -> bool:
	return s.is_bot() or s.input == null or not s.input.is_connected_device()


func is_active() -> bool:
	return _open


func panel_of(slot_index: int) -> LevelUpPanel:
	return panels.get(slot_index)


func all_done() -> bool:
	for i in order:
		if not panels[i].is_done():
			return false
	return true


func set_backdrop_opacity(alpha: float) -> void:
	_backdrop.modulate.a = alpha


## A player left (or their hero is gone): their panel goes away.
func remove_slot(slot_index: int) -> void:
	var panel: LevelUpPanel = panels.get(slot_index)
	if panel == null:
		return
	panels.erase(slot_index)
	order.erase(slot_index)
	_panel_layer.remove_child(panel)
	panel.queue_free()
	_layout()
	_check_finished()


## Closes the phase without finishing it (the intermission was reopened / hidden).
func close() -> void:
	_open = false
	_clear_panels()
	hide()


# --- Frame -----------------------------------------------------------------------------------

## One frame of the phase (called by Intermission._process).
func update(delta: float) -> void:
	if not _open:
		return
	if time_left > 0.0:
		time_left = maxf(0.0, time_left - delta)
	_lockout = maxf(0.0, _lockout - delta)
	var skip := _skip_frames > 0
	if skip:
		_skip_frames -= 1
	for i in order.duplicate():
		var panel: LevelUpPanel = panels.get(i)
		if panel == null:
			continue
		if panel.player == null or not is_instance_valid(panel.player):
			remove_slot(i)
			continue
		panel.tick(delta)
		if panel.is_done():
			continue
		var s := panel.slot
		var auto := is_automatic(s)
		if auto != panel.automatic:
			panel.automatic = auto
			panel.refresh()
		if s.is_bot():
			_bot_update(panel, delta)
		elif auto:
			panel.auto_finish()
		elif not skip:
			panel.handle_input(s.input, _lockout <= 0.0)
		panel.refresh_prompts()
	if time_limit > 0.0 and time_left <= 0.0:
		# GDD 12 spirit: nobody blocks the team – idle humans get the automatic picks.
		for i in order.duplicate():
			var panel: LevelUpPanel = panels.get(i)
			if panel != null and not panel.is_done():
				panel.auto_finish()
	_update_timer()
	_check_finished()


func _bot_update(panel: LevelUpPanel, delta: float) -> void:
	var i := panel.slot.index
	if bot_think_time <= 0.0:
		panel.auto_finish(0)
		return
	if not _bot_wait.has(i):
		_bot_wait[i] = _bot_delay(i)
		_bot_step[i] = BOT_STEP_TIME
		_bot_target[i] = panel.bot_choice()
	_bot_wait[i] -= delta
	_bot_step[i] -= delta
	var target: int = _bot_target[i]
	if _bot_step[i] <= 0.0 and target >= 0 and panel.cursor != target:
		_bot_step[i] = BOT_STEP_TIME
		panel.move_cursor(signi(target - panel.cursor))
	if _bot_wait[i] <= 0.0:
		_bot_wait.erase(i)
		_bot_picks[i] = int(_bot_picks.get(i, 0)) + 1
		panel.auto_pick(0)


## Deterministic pause per bot and pick (no rng: smoke runs stay reproducible).
func _bot_delay(slot_index: int) -> float:
	var n := int(_bot_picks.get(slot_index, 0))
	return bot_think_time * (1.2 + 0.3 * float((slot_index * 3 + n * 5) % 5))


func _check_finished() -> void:
	if _open and all_done():
		_open = false
		finished.emit()


func _on_card_picked(card: LevelCard, _result: Dictionary, slot_index: int) -> void:
	card_picked.emit(slot_index, card)


func _enter_tree() -> void:
	if not RunState.gold_changed.is_connected(_on_gold_changed):
		RunState.gold_changed.connect(_on_gold_changed)


func _exit_tree() -> void:
	if RunState.gold_changed.is_connected(_on_gold_changed):
		RunState.gold_changed.disconnect(_on_gold_changed)


func _on_gold_changed(_gold: int, _delta: int) -> void:
	if gold_value != null:
		gold_value.text = UiTheme.format_int(RunState.gold)
	for i in order:
		panels[i].refresh_prompts()


# --- Layout ----------------------------------------------------------------------------------

## Places the panels: solo centred (SOLO_SCALE), two side by side in the middle band, three or
## four in the players' quarters (by slot index, like the HUD and the market).
func _layout() -> void:
	var n := order.size()
	var design := LevelUpPanel.DESIGN_SIZE
	for k in n:
		var panel := panels[order[k]]
		var s := SOLO_SCALE if n == 1 else 1.0
		panel.scale = Vector2(s, s)
		var shown := design * s
		var right: bool
		var where_y := 0  # -1 top, 0 middle, 1 bottom
		if n == 1:
			right = false
		elif n == 2:
			right = k == 1
		else:
			right = order[k] % 2 == 1
			where_y = 1 if order[k] >= 2 else -1
		if n == 1:
			panel.anchor_left = 0.5
			panel.offset_left = -shown.x * 0.5
		else:
			panel.anchor_left = 1.0 if right else 0.0
			panel.offset_left = -MARGIN - shown.x if right else MARGIN
		panel.anchor_right = panel.anchor_left
		panel.offset_right = panel.offset_left + design.x
		match where_y:
			-1:
				panel.anchor_top = 0.0
				panel.offset_top = HEADER_HEIGHT
			1:
				panel.anchor_top = 1.0
				panel.offset_top = -MARGIN - shown.y
			_:
				panel.anchor_top = 0.5
				panel.offset_top = -shown.y * 0.5 + (HEADER_HEIGHT - MARGIN) * 0.5
		panel.anchor_bottom = panel.anchor_top
		panel.offset_bottom = panel.offset_top + design.y


# --- Build -----------------------------------------------------------------------------------

func _build() -> void:
	UiTheme.setup_root(self)
	_backdrop = UiTheme.backdrop(0.88, Color(0.3, 0.16, 0.42))
	add_child(_backdrop)
	_panel_layer = Control.new()
	_panel_layer.name = "Panels"
	_panel_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_panel_layer)

	var top := UiTheme.vbox(-8)
	top.anchor_left = 0.5
	top.anchor_right = 0.5
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.offset_top = 0
	add_child(top)
	title_label = UiTheme.centered_label("Level Up!", UiTheme.TITLE, 46)
	title_label.add_theme_constant_override(&"outline_size", 11)
	top.add_child(title_label)
	var row := UiTheme.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(row)
	subtitle_label = UiTheme.label("", UiTheme.DIM, 20)
	subtitle_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(subtitle_label)
	var dot := UiTheme.label("·", UiTheme.DIM, 22)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var coin := UiIcon.create(UiIcon.Kind.COIN, Vector2(22, 22))
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(coin)
	gold_value = UiTheme.label("0", UiTheme.GOLD_LABEL, 22, UiTheme.GOLD)
	gold_value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(gold_value)
	var shared := UiTheme.label("shared gold", UiTheme.DIM, 19)
	shared.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(shared)
	_timer_box = UiTheme.hbox(10)
	_timer_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_timer_box)
	var dot2 := UiTheme.label("·", UiTheme.DIM, 22)
	dot2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_timer_box.add_child(dot2)
	timer_bar = UiBar.create(UiTheme.XP_PURPLE.lightened(0.15), TIMER_SIZE.y, 18)
	timer_bar.animated = false
	timer_bar.custom_minimum_size = TIMER_SIZE
	timer_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_timer_box.add_child(timer_bar)
	visible = false


func _fill_header(first_level: int) -> void:
	var last := first_level + maxi(0, level_ups - 1)
	if level_ups > 1:
		subtitle_label.text = "Levels %d–%d: pick 1 card per level on your own controller" % [first_level, last]
	else:
		subtitle_label.text = "Level %d: pick 1 card on your own controller" % first_level
	gold_value.text = UiTheme.format_int(RunState.gold)


func _update_timer() -> void:
	_timer_box.visible = time_limit > 0.0
	if time_limit <= 0.0:
		return
	timer_bar.set_values(time_left, time_limit, "Auto-pick in %d s" % ceili(time_left))
	timer_bar.set_fill_color(UiTheme.RED if time_left <= TIMER_WARN else UiTheme.XP_PURPLE.lightened(0.15))


func _clear_panels() -> void:
	for i: int in panels.keys():
		var panel := panels[i]
		if is_instance_valid(panel):
			if panel.get_parent() != null:
				panel.get_parent().remove_child(panel)
			panel.queue_free()
	panels.clear()
	order.clear()
