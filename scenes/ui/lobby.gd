class_name Lobby
extends Control
## Join + class select screen (GDD 6, 12). Four slot cards in a row.
##
## - While visible, PlayerManager.joining_enabled is true: A on a free controller or one of
##   KeyboardInput.JOIN_KEYS (Enter / Space / Keypad Enter / F) joins a new player (armed only
##   once the button that opened the lobby has been released, so pressing "Play" does not also
##   join). The join press is swallowed by PlayerManager (PlayerInput.swallow()): it neither
##   readies the new player nor moves its class cursor until the stick has been neutral once.
## - Slots whose controller is unplugged are removed when the lobby is shown and every frame
##   while it is open (a ghost slot could never ready up and would block the start).
## - Joined players use their own PlayerSlot.input: ◀ ▶ changes class (Db.cycle_class),
##   RB / E cycles the companion of a class that has choices (ClassData.companion_choices, the
##   M8 Hunter; [method cycle_companion]), A toggles ready, START readies, B unreadies or – when
##   not ready – leaves.
## - Everyone joined and ready -> a COUNTDOWN_TIME countdown (cancelled by an unready or a new
##   join) -> start_requested. B / Esc while nobody has joined -> back_requested.
## - M6b mode select: any joined player's Y cycles the run mode (Normal / Endless, [method cycle_mode])
##   and X toggles Hardcore ([method toggle_hardcore]); the header shows the choice ("Mode: Endless ·
##   Hardcore", plus the HARDCORE badge) and [signal mode_changed] tells Main ([method Main.configure_run]).
##   A change while the start countdown runs un-readies the player who made it, which cancels the countdown
##   (everybody sees the new mode before the run starts).
## - M9 difficulty select: any joined player's BACK (Tab on the keyboard) cycles the difficulty tier
##   ([method cycle_difficulty]: Normal -> Pungent -> Tear-Jerker -> Normal ...) among the tiers every joined hero's
##   class has unlocked (Difficulty.selectable; a tier above the cap shows why it is locked instead, "Win a run on Normal
##   with the Mage"). The header shows "Difficulty: Pungent" in the tier's colour and [signal difficulty_changed]
##   tells Main ([method Main.configure_difficulty]). A class change that lowers the party's cap lowers the choice.
##   Y / X / RB / the d-pad are taken (mode, hardcore, companion, class); the Seasoning picker of the same milestone
##   uses another button.
## - M9: a class the main profile has not unlocked is still shown (with its unlock hint, on its card) but its player
##   cannot ready up ([method ready_block_reason]); a player's class change puts the Seasonings / Heirloom / looks
##   remembered for that class on their slot (Meta.apply_loadout).
## - M9 LEVELS: once a class reaches Class Level 12 its player can switch to the class's alternative starting weapon with
##   LB / Q ([method toggle_alt_weapon]; the weapons line of the card shows the choice, the run starts with it).
## See docs/ARCHITECTURE.md.

signal start_requested
signal back_requested
## A player changed the run mode or the hardcore flag ([method cycle_mode] / [method toggle_hardcore], i.e. Y / X);
## Main stores it with configure_run. [method set_run_mode] does not emit it.
signal mode_changed(mode: StringName, hardcore: bool)
## A player changed the difficulty tier ([method cycle_difficulty]), or the party's cap lowered it; Main stores it with
## configure_difficulty. [method set_difficulty] does not emit it.
signal difficulty_changed(difficulty: StringName)

const COUNTDOWN_TIME := 3.0
## The mode key prompts' opacity while nobody has joined (nobody can use them yet).
const MODE_PROMPTS_IDLE_ALPHA := 0.4
## Seconds the footer shows why a difficulty tier is locked.
const LOCK_NOTICE_TIME := 3.5

## The run mode (RunState.MODES) and the hardcore flag the next run will use.
var run_mode: StringName = RunState.MODE_NORMAL
var hardcore := false
## "Mode: Endless · Hardcore" in the header, and the HARDCORE badge next to it (visible with the flag).
var mode_label: Label
var hardcore_badge: HardcoreBadge
## M9: the difficulty tier (a Difficulty id) the next run will use, and the header line "Difficulty: Pungent".
var difficulty: StringName = Difficulty.NORMAL
var difficulty_label: Label
## Seconds left of the start countdown; < 0 when not counting down.
var countdown_left := -1.0
var cards: Array[LobbyCard] = []
## Controller edges for the "nobody joined yet" case (B = back). Public for tests.
var pads := UiPads.new()

var _started := false
var _owns_joining := false
var _t := 0.0
var _status: Label
var _sub_status: Label
var _countdown_label: Label
var _footer_prompts: CenterContainer
var _footer_key := ""
var _backdrop: TextureRect
var _mode_prompts: Control
var _difficulty_prompt: Control
## The footer line that explains a locked tier, and the seconds it still shows.
var _lock_notice := ""
var _lock_notice_left := 0.0


static func create() -> Lobby:
	var l := Lobby.new()
	l.name = "Lobby"
	l._build()
	return l


## Shows [param p_mode] (RunState.MODES; anything else is Normal) and [param p_hardcore] in the header without
## telling anybody (Main sets the stored choice when it opens the lobby).
func set_run_mode(p_mode: StringName, p_hardcore: bool) -> void:
	run_mode = p_mode if p_mode in RunState.MODES else RunState.MODE_NORMAL
	hardcore = p_hardcore
	_refresh_mode()


## The next mode of the cycle (Normal -> Endless -> Normal ...), by [param by_slot] (a joined slot; null = nobody:
## a test or a script). Emits [signal mode_changed].
func cycle_mode(by_slot: PlayerSlot = null) -> void:
	var at := RunState.MODES.find(run_mode)
	run_mode = RunState.MODES[(at + 1) % RunState.MODES.size()]
	_after_mode_change(by_slot)


## Hardcore on / off, by [param by_slot]. Emits [signal mode_changed].
func toggle_hardcore(by_slot: PlayerSlot = null) -> void:
	hardcore = not hardcore
	_after_mode_change(by_slot)


## Shows tier [param id] (anything else is Normal) in the header without telling anybody (Main sets the stored choice
## when it opens the lobby). The party's cap still applies on the next frame.
func set_difficulty(id: StringName) -> void:
	difficulty = Difficulty.sanitize(id)
	_refresh_difficulty()


## The next tier the joined heroes may play (Normal -> Pungent -> Tear-Jerker -> Normal ...), by [param by_slot] (a
## joined slot; null = nobody: a test or a script). When the next tier is locked for the party the footer says why and
## the choice wraps to Normal. Emits [signal difficulty_changed] and returns true when the tier changed.
func cycle_difficulty(by_slot: PlayerSlot = null) -> bool:
	var classes := party_classes()
	var all := Difficulty.ids()
	if all.is_empty():
		return false
	var allowed := Difficulty.selectable(classes)
	var next := all[(maxi(all.find(difficulty), 0) + 1) % all.size()]
	if next not in allowed:
		_show_lock_notice("%s is locked: %s" % [Difficulty.name_of(next), Difficulty.lock_reason(next, classes)])
		next = all[0]
	if next == difficulty:
		return false
	difficulty = next
	if by_slot != null and is_counting_down():
		by_slot.ready = false  # the countdown stops until everybody has seen the new tier and readied again
		countdown_left = -1.0
	_refresh_difficulty()
	difficulty_changed.emit(difficulty)
	return true


## The class ids of the joined heroes (the difficulty cap is the lowest tier they have all unlocked).
func party_classes() -> Array[StringName]:
	var out: Array[StringName] = []
	for slot in PlayerManager.get_slots():
		if slot.class_data != null:
			out.append(slot.class_data.id)
	return out


## "Difficulty: Pungent" (the header text of the current choice).
func difficulty_text() -> String:
	return "Difficulty: %s" % Difficulty.name_of(difficulty)


func _refresh_difficulty() -> void:
	if difficulty_label != null:
		difficulty_label.text = difficulty_text()
		difficulty_label.add_theme_color_override(&"font_color",
				UiTheme.GOLD if difficulty == Difficulty.NORMAL else Difficulty.color_of(difficulty).lightened(0.15))


func _show_lock_notice(text: String) -> void:
	_lock_notice = text
	_lock_notice_left = LOCK_NOTICE_TIME


## A class change (or a joined hero) can lower the party's cap: the choice follows it down.
func _enforce_difficulty_cap() -> void:
	var allowed := Difficulty.selectable(party_classes())
	if allowed.is_empty() or difficulty in allowed:
		return
	var tier := allowed[allowed.size() - 1]
	_show_lock_notice("%s is locked for this party: %s" % [Difficulty.name_of(difficulty), Difficulty.lock_reason(difficulty, party_classes())])
	difficulty = tier
	_refresh_difficulty()
	difficulty_changed.emit(difficulty)


## "Mode: Endless · Hardcore" (the header text of the current choice).
func mode_text() -> String:
	return "Mode: %s" % RunState.mode_text(run_mode, hardcore)


func _after_mode_change(by_slot: PlayerSlot) -> void:
	if by_slot != null and is_counting_down():
		by_slot.ready = false  # the countdown stops until everybody has seen the new mode and readied again
		countdown_left = -1.0
	_refresh_mode()
	mode_changed.emit(run_mode, hardcore)


func _refresh_mode() -> void:
	if mode_label != null:
		mode_label.text = mode_text()
	if hardcore_badge != null:
		hardcore_badge.visible = hardcore


## Opacity of the dark backdrop (lower it to let a 3D scene show through).
func set_backdrop_opacity(alpha: float) -> void:
	_backdrop.modulate.a = alpha


func is_counting_down() -> bool:
	return countdown_left >= 0.0 and not _started


## Clears every slot's ready flag and the countdown (done whenever the lobby is shown).
func reset() -> void:
	_started = false
	countdown_left = -1.0
	PlayerManager.prune_disconnected()
	PlayerManager.set_all_ready(false)
	_set_joining(not UiPads.join_button_held())


# --- Build ---------------------------------------------------------------------------

func _build() -> void:
	UiTheme.setup_root(self)
	_backdrop = UiTheme.backdrop(1.0, Color(0.3, 0.2, 0.12))
	add_child(_backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override(&"margin_left", 56)
	margin.add_theme_constant_override(&"margin_right", 56)
	margin.add_theme_constant_override(&"margin_top", 24)
	margin.add_theme_constant_override(&"margin_bottom", 18)
	add_child(margin)
	var col := UiTheme.vbox(10)
	margin.add_child(col)

	# The title stays in the middle; the mode select sits at the right end of the same row (it costs no height).
	var head := UiTheme.hbox(20)
	head.name = "Head"
	col.add_child(head)
	var head_left := Control.new()
	head_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(head_left)
	var title := UiTheme.centered_label("Assemble Your Party", UiTheme.TITLE, 60)
	head.add_child(title)
	head.add_child(_build_mode_block())
	var subtitle := UiTheme.centered_label("Up to four onion heroes  ·  pick a class and ready up", UiTheme.DIM, UiTheme.FONT_BODY + 2)
	col.add_child(subtitle)
	col.add_child(UiTheme.divider(620))

	var row := UiTheme.hbox(26)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)
	for i in PlayerManager.MAX_PLAYERS:
		var card := LobbyCard.create(i)
		row.add_child(card)
		cards.append(card)

	var footer := UiTheme.vbox(2)
	footer.custom_minimum_size = Vector2(0, 76)
	col.add_child(footer)
	_status = UiTheme.centered_label("", UiTheme.GOLD_LABEL, 34)
	footer.add_child(_status)
	_sub_status = UiTheme.centered_label("", UiTheme.DIM)
	footer.add_child(_sub_status)
	_footer_prompts = CenterContainer.new()
	_footer_prompts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_footer_prompts.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_footer_prompts.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_footer_prompts.offset_left = 60
	_footer_prompts.offset_bottom = -30
	_footer_prompts.offset_top = -72
	add_child(_footer_prompts)

	# Big countdown number over the cards.
	_countdown_label = UiTheme.centered_label("3", UiTheme.TITLE, 220)
	_countdown_label.add_theme_constant_override(&"outline_size", 26)
	_countdown_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_countdown_label.visible = false
	add_child(_countdown_label)


## The mode header at the right end of the title row: "Mode: Endless · Hardcore" with the HARDCORE badge,
## and under it the prompts of the two keys (dim until somebody has joined: they always take their line,
## so the row never changes height). It takes the row's free right half (the left one is an empty twin,
## so the title stays centred).
func _build_mode_block() -> Control:
	var box := UiTheme.vbox(0)
	box.name = "ModeBlock"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var row := UiTheme.hbox(14)
	row.name = "ModeRow"
	row.size_flags_horizontal = Control.SIZE_SHRINK_END
	box.add_child(row)
	mode_label = UiTheme.centered_label(mode_text(), UiTheme.GOLD_LABEL, UiTheme.FONT_LARGE)
	mode_label.name = "ModeLabel"
	row.add_child(mode_label)
	hardcore_badge = HardcoreBadge.create(UiTheme.FONT_SMALL)
	hardcore_badge.visible = hardcore
	row.add_child(hardcore_badge)
	# M9: the difficulty line carries its own prompt (the Mode / Hardcore prompts below keep their room, clear of the title).
	var difficulty_row := UiTheme.hbox(12)
	difficulty_row.name = "DifficultyRow"
	difficulty_row.size_flags_horizontal = Control.SIZE_SHRINK_END
	box.add_child(difficulty_row)
	difficulty_label = UiTheme.centered_label(difficulty_text(), UiTheme.GOLD_LABEL, UiTheme.FONT_BODY)
	difficulty_label.name = "DifficultyLabel"
	difficulty_row.add_child(difficulty_label)
	_difficulty_prompt = UiTheme.prompt_row([[UiGlyph.pad(PlayerInput.Pad.SELECT, 26.0), "/", UiGlyph.key("Tab", 26.0)]],
			UiTheme.FONT_SMALL + 2, UiTheme.TEXT_DIM)
	_difficulty_prompt.name = "DifficultyPrompt"
	_difficulty_prompt.modulate.a = MODE_PROMPTS_IDLE_ALPHA
	difficulty_row.add_child(_difficulty_prompt)
	_refresh_difficulty()
	_mode_prompts = UiTheme.prompt_row([
		[UiGlyph.pad(PlayerInput.Pad.Y, 26.0), "/", UiGlyph.key("C", 26.0), "Mode"],
		[UiGlyph.pad(PlayerInput.Pad.X, 26.0), "/", UiGlyph.key("R", 26.0), "Hardcore"],
	], UiTheme.FONT_SMALL + 2, UiTheme.TEXT_DIM)
	_mode_prompts.name = "ModePrompts"
	_mode_prompts.size_flags_horizontal = Control.SIZE_SHRINK_END
	_mode_prompts.modulate.a = MODE_PROMPTS_IDLE_ALPHA
	box.add_child(_mode_prompts)
	return box


# --- Lifecycle -------------------------------------------------------------------------

func _ready() -> void:
	PlayerManager.device_disconnected.connect(_on_device_disconnected)
	PlayerManager.player_joined.connect(_on_player_joined)
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()
	_refresh()


func _exit_tree() -> void:
	_set_joining(false)


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		reset()
	else:
		_set_joining(false)
		countdown_left = -1.0


func _set_joining(on: bool) -> void:
	if on:
		PlayerManager.joining_enabled = true
		_owns_joining = true
	elif _owns_joining:
		PlayerManager.joining_enabled = false
		_owns_joining = false


func _on_player_joined(slot: PlayerSlot) -> void:
	Meta.apply_loadout(slot)  # (the selections remembered for the class the player starts on)


func _on_device_disconnected(slot: PlayerSlot) -> void:
	# A controller unplugged in the lobby frees its slot (it could never ready up).
	if is_visible_in_tree() and not _started and PlayerManager.get_slot(slot.index) == slot:
		PlayerManager.leave(slot.index)


# --- Frame ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	pads.poll()
	if not is_visible_in_tree() or _started:
		return
	if not _owns_joining and not UiPads.join_button_held():
		_set_joining(true)
	PlayerManager.prune_disconnected()
	var nobody_before := PlayerManager.count() == 0
	for slot in PlayerManager.get_slots():
		_handle_slot_input(slot)
	if nobody_before and PlayerManager.count() == 0 \
			and (Input.is_action_just_pressed(&"ui_cancel") or pads.any_just_pressed(JOY_BUTTON_B)):
		_set_joining(false)
		back_requested.emit()
		return
	_enforce_difficulty_cap()
	_lock_notice_left = maxf(0.0, _lock_notice_left - delta)
	_update_countdown(delta)
	_refresh()


func _handle_slot_input(slot: PlayerSlot) -> void:
	var inp := slot.input
	if inp == null:
		return
	# B before START: the keyboard maps Esc to both.
	if inp.just_pressed(PlayerInput.Pad.A):
		if not slot.ready and ready_block_reason(slot) != "":
			Audio.play_ui(&"ui_error")
		else:
			slot.ready = not slot.ready
			Audio.play_ui(&"ui_confirm" if slot.ready else &"ui_back")
	elif inp.just_pressed(PlayerInput.Pad.B):
		Audio.play_ui(&"ui_back")
		if slot.ready:
			slot.ready = false
		else:
			PlayerManager.leave(slot.index)
			return
	elif inp.just_pressed(PlayerInput.Pad.START):
		if ready_block_reason(slot) != "":
			Audio.play_ui(&"ui_error")
		else:
			slot.ready = true
			Audio.play_ui(&"ui_confirm")
	# Any joined player picks the run's mode: Y cycles Normal / Endless, X toggles Hardcore.
	if inp.just_pressed(PlayerInput.Pad.Y):
		cycle_mode(slot)
		Audio.play_ui(&"ui_toggle")
	elif inp.just_pressed(PlayerInput.Pad.X):
		toggle_hardcore(slot)
		Audio.play_ui(&"ui_toggle")
	elif inp.just_pressed(PlayerInput.Pad.SELECT):
		Audio.play_ui(&"ui_toggle" if cycle_difficulty(slot) else &"ui_error")
	if not slot.ready:
		var nav := inp.nav_just_pressed()
		if nav.x != 0:
			_cycle_class(slot, nav.x)
			Audio.play_ui(&"ui_move")
		if inp.just_pressed(PlayerInput.Pad.RB) and cycle_companion(slot):
			Audio.play_ui(&"ui_move")
		if inp.just_pressed(PlayerInput.Pad.LB) and toggle_alt_weapon(slot):
			Audio.play_ui(&"ui_toggle")


## Why [param slot] cannot ready up ("" = it can): its class is locked in the main profile (M9) – the text is the
## class's unlock hint. Never the case with the dev profile of the automated runs.
func ready_block_reason(slot: PlayerSlot) -> String:
	if slot == null or slot.class_data == null or Meta.is_class_unlocked(slot.class_data.id):
		return ""
	return Meta.unlock_hint(Profile.KIND_CLASS, slot.class_data.id)


## Switches [param slot] between the standard and the alternative starting weapon of its class (LB / Q). False (nothing
## changes) unless the profile records runs and the class has unlocked the weapon (Class Level 12).
func toggle_alt_weapon(slot: PlayerSlot) -> bool:
	if slot == null or slot.class_data == null or not Meta.shows_class_levels() or not Meta.alt_weapon_unlocked(slot.class_data.id):
		return false
	slot.alt_weapon = not slot.alt_weapon
	return true


## The next companion of [param slot]'s class (RB / E; wraps). False (nothing changes) for a class
## without companion choices.
func cycle_companion(slot: PlayerSlot) -> bool:
	if slot == null or slot.class_data == null or not slot.class_data.has_companions():
		return false
	slot.cycle_companion(1)
	return true


func _cycle_class(slot: PlayerSlot, step: int) -> void:
	var current: StringName = slot.class_data.id if slot.class_data != null else &""
	var next := Db.get_class_data(Db.cycle_class(current, step))
	if next != null:
		slot.class_data = next
		Meta.apply_loadout(slot)
	if slot.index >= 0 and slot.index < cards.size():
		cards[slot.index].kick_arrow(step)


func _update_countdown(delta: float) -> void:
	if PlayerManager.all_ready():
		if countdown_left < 0.0:
			countdown_left = COUNTDOWN_TIME
		else:
			countdown_left -= delta
		if countdown_left <= 0.0:
			countdown_left = 0.0
			_started = true
			_set_joining(false)
			_refresh()
			start_requested.emit()
	else:
		countdown_left = -1.0


func _refresh() -> void:
	var keyboard_free := not PlayerManager.is_device_used("keyboard")
	for i in cards.size():
		cards[i].update_from(PlayerManager.get_slot(i), keyboard_free)
	var slots := PlayerManager.get_slots()
	# Only a joined player can change the mode: the key prompts light up with the first one.
	_mode_prompts.modulate.a = 1.0 if not slots.is_empty() else MODE_PROMPTS_IDLE_ALPHA
	_difficulty_prompt.modulate.a = _mode_prompts.modulate.a
	var ready_count := 0
	for s in slots:
		if s.ready:
			ready_count += 1
	var footer_key := ""
	if slots.is_empty():
		_status.text = "Press A to join"
		_status.add_theme_color_override(&"font_color", UiTheme.GOLD)
		_sub_status.text = "Every player joins with their own controller – or Enter on the keyboard"
		footer_key = "back"
	elif countdown_left >= 0.0:
		_status.text = "The battle begins in %d…" % ceili(maxf(countdown_left, 0.01)) if not _started else "To battle!"
		_status.add_theme_color_override(&"font_color", UiTheme.GREEN)
		_sub_status.text = "Unready to wait for more heroes"
	else:
		_status.text = "%d / %d ready" % [ready_count, slots.size()]
		_status.add_theme_color_override(&"font_color", UiTheme.GOLD)
		_sub_status.text = "The run starts when every joined player is ready" if slots.size() < PlayerManager.MAX_PLAYERS \
			else "The party is full – ready up!"
		if _lock_notice_left > 0.0:
			_sub_status.text = _lock_notice
	if footer_key != _footer_key:
		_footer_key = footer_key
		for c in _footer_prompts.get_children():
			_footer_prompts.remove_child(c)
			c.queue_free()
		if footer_key == "back":
			_footer_prompts.add_child(UiTheme.prompt_row([[UiGlyph.pad(PlayerInput.Pad.B), "/", UiGlyph.key("Esc"), "Back"]], UiTheme.FONT_BODY, UiTheme.TEXT_DIM))
	var counting := countdown_left >= 0.0 and not _started
	_countdown_label.visible = counting
	if counting:
		var n := ceili(maxf(countdown_left, 0.01))
		_countdown_label.text = str(n)
		var frac := countdown_left - floorf(countdown_left)
		_countdown_label.pivot_offset = _countdown_label.size * 0.5
		_countdown_label.scale = Vector2.ONE * (1.0 + 0.25 * frac * frac)
		_countdown_label.modulate.a = 0.35 + 0.65 * frac
