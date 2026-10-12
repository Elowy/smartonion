class_name TalentTab
extends Control
## The Talents tab of a player's between-wave panel (GDD 7, 12; PlayerPanel tab 3, M5): the
## hero's talents (player.talents, a TalentState) – every hero has the team's full point count –
## spent in the market. Same body size as the Trainer tab (PlayerPanel.DESIGN_SIZE, scaled into
## the player's corner). Layout (architecture §2.2):
##  - left: the TierRail (gate numbers 3 / 6 / 9 / 12, padlocked while the selected tree has not
##    reached them) and the class's three trees side by side (TalentTreeView: name, 5 tier rows
##    of TalentNodes with rank pills "2/3", prerequisite arrows, locked tiers dimmed, the points
##    in the tree) – they take the whole body height;
##  - right: the header ("Talent points: 2 free · 11 spent", or "Talent points from level 10
##    (level 7)" before level 10 – the trees stay browsable), the detail of the selection
##    (glyph, name, kind, rank, the text at the current rank – rank 0: the rank-1 numbers –, the
##    next rank's text in green, "You haven't learned X" for a modifier whose ability is not
##    slotted, the block reason in red and, room permitting, the tree's one-line identity) and
##    at the bottom the Reset row ("Reset Talents – 40 g").
## Input (handle_input, the panel's per-player PlayerInput – never the global Input): d-pad /
## stick move spatially over the 6 x 5 grid (capstones centred); down from the bottom row goes
## to the Reset row, up (or left) from it back to the talent it came from; A adds a point (TalentState.add; refused presses
## show TalentState.add_block_reason in red); X takes back a pending point
## (TalentState.remove / remove_block_reason); Y previews the next rank (the description and
## the rank in green). Reset: A turns the Reset row into "Press A again to reset (40 g)" for
## CONFIRM_TIME (a shrinking bar; the detail repeats it); the second
## A resets (TalentState.try_reset, logged in the shared wallet as "Reset Talents") – or, when
## the price is above HOLD_SHARE of the wallet, has to be held for HOLD_TIME (the shop / Trainer
## rule; the row fills up; letting go, moving or B cancels). While a confirm / hold is open the
## tab is modal (PlayerPanel keeps LT / RT) and B cancels it – the only time B counts as used,
## so the Intermission can still unready with B. Feedback goes out through [signal message].
## [signal points_changed] tells the panel to relabel its tab ("Talents (2)", [method tab_label]).
## While hidden (another tab, or the whole wave) talent, gold and level changes only mark the
## tab stale; it refreshes at the end of the frame it is shown in, unless an explicit refresh()
## came first (the TrainerTab rule).

## Text for the panel's toast: [param bbcode] shown, [param plain] kept as PlayerPanel.last_message.
signal message(bbcode: String, plain: String, color: Color, coin: bool)
## Something the prompt row shows changed.
signal prompts_changed
## The free points (or the level gate) may have changed: the panel relabels its tab.
signal points_changed

enum ResetMode { IDLE, CONFIRM, HOLD }

const HOLD_TIME := ShopPanel.HOLD_TIME
const HOLD_SHARE := ShopPanel.HOLD_SHARE
## Seconds the "Press A again to reset" confirm stays open (GDD 7.3).
const CONFIRM_TIME := 2.0
const TREE_GAP := 5
## Between the detail panel and the Reset row.
const RESET_GAP := 6
const COLUMN_GAP := 8
const RESET_HEIGHT := 34.0
const RESET_FONT := 17
const RESET_MIN_FONT := 12
## Width of the rail + the three trees.
const TREES_WIDTH := TalentTreeView.TierRail.WIDTH + TREE_GAP + 3 * (TalentTreeView.WIDTH + TREE_GAP) - TREE_GAP
## Width of the right column in the 700 x 480 panel (PlayerPanel.DESIGN_SIZE minus the frame).
const DETAIL_WIDTH := 672.0 - TREES_WIDTH - COLUMN_GAP
const DETAIL_FONT := 16
## A long description shrinks down to this size before it is cut ([method _fit_description]).
const MIN_DETAIL_FONT := 14
const DETAIL_GLYPH := 34.0
## The description never gets fewer lines than this (even when the other texts are long).
const MIN_DESCRIPTION_LINES := 2
## The tree's identity line shows only when it fits whole in at most this many lines.
const MAX_TREE_LINES := 3
const CONFIRM_COLOR := Color(1.0, 0.7, 0.28)
const NOT_LEARNED_COLOR := Color(1.0, 0.62, 0.25)
const EMPTY_TEXT := "No talents for this class yet"
## Navigation key of the Reset row.
const RESET_KEY := &"__reset"

var slot: PlayerSlot
var tree_views: Array[TalentTreeView] = []
var rail: TalentTreeView.TierRail
## The selected talent (kept while the Reset row is selected: up returns to it).
var selected_id: StringName = &""
## The Reset row is selected (instead of [member selected_id]).
var reset_selected := false
## Y: the detail shows the next rank's text (in green).
var preview_next := false
var reset_mode := ResetMode.IDLE
## Header and detail labels (tests read them).
var header_label: Label
var detail_name: Label
var detail_kind: Label
var detail_rank: Label
## "+2 this round" (pending points) right of the rank.
var detail_state: Label
var detail_text: Label
## "Next rank: …" (green).
var detail_next: Label
## "You haven't learned X" / the reset confirm (orange).
var detail_hint: Label
## Why A is refused (red).
var detail_reason: Label
## "<Tree>: <its one-line identity>" (only in the room the other texts leave).
var detail_tree: Label
var reset_row: ResetRow
var empty_label: Label

var _state: TalentState
var _runner: AbilityRunner
## The TalentState the tree views were built for.
var _built_for: TalentState
var _built_trees: Array[TalentTreeData] = []
var _focused := false
var _stale := false
## RunState.level when the tab label was last announced (points_changed).
var _label_level := -1
var _confirm_left := 0.0
var _hold_time := 0.0
var _hold_price := 0
## Talent id / RESET_KEY -> centre in tab coordinates (spatial navigation).
var _nav_points: Dictionary[StringName, Vector2] = {}
var _trees_row: HBoxContainer
var _detail_box: VBoxContainer
var _detail_glyph_holder: Control
var _detail_glyph_key := ""
var _rank_row: HBoxContainer
var _texts: VBoxContainer
var _texts_holder: Control


## The Reset row under the detail: a reset glyph and "Reset Talents – 40 g"; fills up in the
## player's colour while A is held, shows a shrinking bar while the confirm is open.
class ResetRow extends PanelContainer:
	var label: Label
	var glyph: TalentGlyph
	var selected := false
	var accent := UiTheme.GOLD
	## 0..1 of the running hold.
	var hold_progress := 0.0
	## 0..1 of the confirm window left (0 = no confirm).
	var confirm_left := 0.0
	var _style: StyleBoxFlat

	static func create() -> ResetRow:
		var r := ResetRow.new()
		r.name = "ResetRow"
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.custom_minimum_size = Vector2(0, RESET_HEIGHT)
		r._style = StyleBoxFlat.new()
		r._style.set_corner_radius_all(6)
		r._style.anti_aliasing = true
		r._style.content_margin_left = 8
		r._style.content_margin_right = 10
		r.add_theme_stylebox_override(&"panel", r._style)
		var row := UiTheme.hbox(8)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		r.add_child(row)
		r.glyph = TalentGlyph.create(TalentGlyph.Glyph.RESET, 24.0)
		r.glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(r.glyph)
		r.label = UiTheme.label("", &"", RESET_FONT, UiTheme.TEXT)
		r.label.add_theme_font_override(&"font", UiTheme.bold_font())
		r.label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.label.clip_text = true
		r.label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(r.label)
		r._update_style()
		return r

	## Shows [param text] at the largest size from RESET_FONT down that fits the row (the glyph
	## makes room while [param modal]: the confirm / hold texts are longer).
	func show_text(text: String, color: Color, modal: bool) -> void:
		glyph.visible = not modal
		var room := DETAIL_WIDTH - 18.0 - (0.0 if modal else 32.0)
		var font := UiTheme.bold_font()
		var fs := RESET_FONT
		while fs > RESET_MIN_FONT and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
			fs -= 1
		label.text = text
		label.add_theme_font_size_override(&"font_size", fs)
		label.add_theme_color_override(&"font_color", color)
		label.custom_minimum_size.x = minf(room, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 2.0)

	func set_selected(on: bool, color: Color) -> void:
		selected = on
		accent = color
		_update_style()

	func set_progress(p_hold: float, p_confirm: float) -> void:
		hold_progress = clampf(p_hold, 0.0, 1.0)
		confirm_left = clampf(p_confirm, 0.0, 1.0)
		_update_style()

	func _update_style() -> void:
		var modal := confirm_left > 0.0 or hold_progress > 0.0
		_style.bg_color = Color(0.3, 0.21, 0.1, 0.95) if selected else Color(0.06, 0.05, 0.045, 0.85)
		_style.border_color = CONFIRM_COLOR if modal else (accent if selected else Color(0.4, 0.33, 0.22, 0.8))
		_style.set_border_width_all(2 if selected or modal else 1)
		queue_redraw()

	func _draw() -> void:
		if hold_progress > 0.0:
			var r := Rect2(Vector2(2, 2), Vector2((size.x - 4.0) * hold_progress, size.y - 4.0))
			draw_rect(r, Color(accent, 0.38))
			draw_rect(Rect2(Vector2(r.end.x - 2.0, 2.0), Vector2(2.0, size.y - 4.0)), Color(accent.lightened(0.5), 0.9))
		elif confirm_left > 0.0:
			draw_rect(Rect2(Vector2(4, size.y - 5.0), Vector2((size.x - 8.0) * confirm_left, 3.0)), CONFIRM_COLOR)


static func create(p_slot: PlayerSlot) -> TalentTab:
	var t := TalentTab.new()
	t.slot = p_slot
	t.name = "TalentTab"
	t._build()
	return t


# --- Queries ---------------------------------------------------------------------------------

## The hero (null when the slot has none).
func player() -> Player:
	if slot == null or not is_instance_valid(slot.player):
		return null
	return slot.player as Player


## The hero's TalentState (null without a hero).
func state() -> TalentState:
	var p := player()
	return p.talents if p != null else null


## Free talent points of the hero (0 without one, and before level 10).
func free_points() -> int:
	var s := state()
	return s.points_free() if s != null else 0


## The panel's tab label: "Talents (2)" while points are free (and there is a tree to spend
## them in), else "Talents".
func tab_label() -> String:
	var s := state()
	var n := free_points() if s != null and not s.trees().is_empty() else 0
	return "Talents (%d)" % n if n > 0 else "Talents"


## "Talent points: 2 free · 11 spent", or "Talent points from level 10 (level 7)" before the
## first point.
func header_text() -> String:
	var s := state()
	if s == null:
		return ""
	if RunState.level < RunState.TALENT_START_LEVEL:
		return "Talent points from level %d (level %d)" % [RunState.TALENT_START_LEVEL, RunState.level]
	return "Talent points: %d free · %d spent" % [s.points_free(), s.points_spent()]


func selected_talent() -> TalentData:
	var s := state()
	if s == null or reset_selected or selected_id == &"":
		return null
	return s.talent(selected_id)


## The view of the tree that holds [param talent_id] (null when none).
func view_for(talent_id: StringName) -> TalentTreeView:
	for v in tree_views:
		if v.nodes.has(talent_id):
			return v
	return null


func node_for(talent_id: StringName) -> TalentNode:
	var v := view_for(talent_id)
	return v.node_for(talent_id) if v != null else null


## Design-space centre of [param key] (a talent id or RESET_KEY) in the tab (navigation).
func nav_point(key: StringName) -> Vector2:
	return _nav_points.get(key, Vector2(-1, -1))


## GDD 10 / shop rule: a price above HOLD_SHARE of the wallet needs A held.
static func needs_hold(price: int) -> bool:
	return price > RunState.gold * HOLD_SHARE


## A reset confirm / hold is open: LT / RT must not switch tabs.
func is_modal() -> bool:
	return reset_mode != ResetMode.IDLE


func is_confirming() -> bool:
	return reset_mode == ResetMode.CONFIRM


func is_holding() -> bool:
	return reset_mode == ResetMode.HOLD


## 0..1 progress of the running hold-to-reset (0 when none).
func hold_progress() -> float:
	return clampf(_hold_time / HOLD_TIME, 0.0, 1.0) if is_holding() else 0.0


## "Press A again to reset (40 g)".
func confirm_text() -> String:
	var s := state()
	return "Press A again to reset (%d g)" % (s.reset_price() if s != null else 0)


## The Reset row's text: "Reset Talents – 40 g", or the confirm / hold prompt while open.
func reset_text() -> String:
	var s := state()
	var price := s.reset_price() if s != null else TalentState.RESET_BASE_PRICE
	match reset_mode:
		ResetMode.CONFIRM:
			return confirm_text()
		ResetMode.HOLD:
			return "Hold A to reset (%d g)" % _hold_price
	return "Reset Talents – %d g" % price


# --- Actions -----------------------------------------------------------------------------------

## Rebuilds from the hero's TalentState (trees, ranks, header, detail, Reset row).
func refresh() -> void:
	_stale = false
	_bind(player())
	var trees: Array[TalentTreeData] = _state.trees() if _state != null else ([] as Array[TalentTreeData])
	if _state != _built_for or trees != _built_trees:
		_rebuild_trees(trees)
	for v in tree_views:
		v.refresh(_state)
	_ensure_selection()
	if reset_mode != ResetMode.IDLE and not _reset_still_valid():
		cancel_reset()
	_update_selection()
	_announce_points(true)


## Whether this tab receives its player's input (selection outline; a confirm / hold closes
## without it).
func set_focused(on: bool) -> void:
	_focused = on
	if not on and reset_mode != ResetMode.IDLE:
		cancel_reset()
	_update_selection()


## One frame of the player's input. Returns true when a press was used (B only when it
## cancelled a confirm / hold, so the Intermission can unready with B).
func handle_input(input: PlayerInput, delta: float) -> bool:
	if input == null:
		return false
	var nav := input.nav_just_pressed()
	var used := false
	var a_done := false
	match reset_mode:
		ResetMode.CONFIRM:
			if input.just_pressed(PlayerInput.Pad.B):
				cancel_reset()
				return true
			if nav != Vector2i.ZERO:
				cancel_reset()
			else:
				_confirm_left -= delta
				if input.just_pressed(PlayerInput.Pad.A):
					a_done = true
					used = true
					confirm_reset()
				elif _confirm_left <= 0.0:
					cancel_reset()
				else:
					_update_reset_row()
		ResetMode.HOLD:
			a_done = true
			if input.just_pressed(PlayerInput.Pad.B):
				cancel_reset()
				return true
			if nav != Vector2i.ZERO or not input.is_pressed(PlayerInput.Pad.A) or not _reset_still_valid():
				cancel_reset()
			else:
				_hold_time += delta
				used = true
				if _hold_time >= HOLD_TIME:
					_do_reset()
				else:
					_update_reset_row()
	if nav != Vector2i.ZERO:
		move_selection(nav)
		used = true
	if input.just_pressed(PlayerInput.Pad.Y):
		toggle_preview()
		used = true
	if input.just_pressed(PlayerInput.Pad.X):
		press_take_back()
		used = true
	if input.just_pressed(PlayerInput.Pad.A) and not a_done and reset_mode == ResetMode.IDLE:
		press_accept()
		used = true
	return used


## A: a point into the selected talent, or the reset (Reset row).
func press_accept() -> void:
	if reset_selected:
		press_reset()
	else:
		press_add()


## A on a talent: one point in, or the block reason in red. True when added.
func press_add() -> bool:
	var s := state()
	var t := selected_talent()
	if s == null or t == null:
		return false
	var reason := s.add_block_reason(t.id)
	if reason != "":
		_say(reason, "", UiTheme.RED)
		return false
	if not s.add(t.id):
		return false
	var rank := "%d/%d" % [s.rank_of(t.id), t.max_rank]
	_say("%s %s" % [_bb_name(t.display_name), rank], "%s %s" % [t.display_name, rank], UiTheme.TEXT)
	return true


## X on a talent: takes one pending point back, or shows why not. True when taken back.
func press_take_back() -> bool:
	var s := state()
	var t := selected_talent()
	if s == null or t == null:
		return false
	var reason := s.remove_block_reason(t.id)
	if reason != "":
		_say(reason, "", UiTheme.RED)
		return false
	if not s.remove(t.id):
		return false
	var rank := "%d/%d" % [s.rank_of(t.id), t.max_rank]
	_say("%s back to %s" % [_bb_name(t.display_name), rank], "%s back to %s" % [t.display_name, rank], UiTheme.TEXT)
	return true


## A on the Reset row: opens the confirm – the row (and the detail) read "Press A again to reset
## (40 g)" for CONFIRM_TIME – or says why not.
func press_reset() -> void:
	var s := state()
	if s == null:
		return
	var reason := s.reset_block_reason()
	if reason != "":
		_say(reason, "", UiTheme.RED)
		return
	reset_mode = ResetMode.CONFIRM
	_confirm_left = CONFIRM_TIME
	# The warning is the row itself (and the detail): a toast would cover the row.
	_update_reset_row()
	_update_detail()
	prompts_changed.emit()


## The second A: resets now, or starts the hold when the price is above HOLD_SHARE of the
## wallet.
func confirm_reset() -> void:
	var s := state()
	if s == null:
		cancel_reset()
		return
	var reason := s.reset_block_reason()
	if reason != "":
		cancel_reset()
		_say(reason, "", UiTheme.RED)
		return
	var price := s.reset_price()
	if needs_hold(price):
		reset_mode = ResetMode.HOLD
		_hold_time = 0.0
		_hold_price = price
		_update_reset_row()
		_update_detail()
		prompts_changed.emit()
		return
	_do_reset()


## Closes an open confirm / hold (B, moving, letting go, losing the focus).
func cancel_reset() -> void:
	if reset_mode == ResetMode.IDLE:
		return
	reset_mode = ResetMode.IDLE
	_confirm_left = 0.0
	_hold_time = 0.0
	_update_reset_row()
	_update_detail()
	prompts_changed.emit()


## Y: switches the detail between the current and the next rank's text.
func toggle_preview() -> void:
	preview_next = not preview_next
	_update_detail()
	prompts_changed.emit()


func select_talent(talent_id: StringName) -> void:
	var s := state()
	if s == null or s.talent(talent_id) == null:
		return
	if talent_id == selected_id and not reset_selected:
		return
	selected_id = talent_id
	reset_selected = false
	preview_next = false  # Y previews the talent it was pressed on, not the next one selected
	cancel_reset()
	_update_selection()


func select_reset() -> void:
	if reset_selected or tree_views.is_empty():
		return
	reset_selected = true
	_update_selection()


## Spatial move over the trees ([param dir] one of the four directions). Only down reaches the
## Reset row (from the bottom row: nothing else is below); up or left from it leads back to the
## talent selected before.
func move_selection(dir: Vector2i) -> void:
	if dir == Vector2i.ZERO or _nav_points.is_empty():
		return
	if reset_selected:
		if dir.y < 0 or dir.x < 0:
			if state() != null and state().talent(selected_id) != null:
				reset_selected = false
				_update_selection()
		return
	var from := nav_point(selected_id)
	var d := Vector2(dir)
	var best := &""
	var best_score := INF
	for pass_i in 2:
		for key in _nav_points:
			if key == selected_id or (key == RESET_KEY and dir != Vector2i.DOWN):
				continue
			var off := _nav_points[key] - from
			var along := off.dot(d)
			var across := absf(off.dot(d.orthogonal()))
			if along < 12.0:
				continue
			# First pass: only targets within ~50° of the direction; then anything that way.
			if pass_i == 0 and across > along * 1.2:
				continue
			var score := along + across * 2.5
			if score < best_score:
				best_score = score
				best = key
		if best != &"":
			break
	if best == RESET_KEY:
		select_reset()
	elif best != &"":
		select_talent(best)


## Button prompts for the panel's prompt row: [button, text] pairs (PlayerInput.Pad or
## TrainerTab.NAV_PROMPT_SIDEWAYS for the stick / d-pad).
func prompt_spec() -> Array:
	var s := state()
	match reset_mode:
		ResetMode.CONFIRM:
			var hold := s != null and needs_hold(s.reset_price())
			return [[PlayerInput.Pad.A, "Hold to reset" if hold else "Reset"], [PlayerInput.Pad.B, "Cancel"]]
		ResetMode.HOLD:
			return [[PlayerInput.Pad.A, "Hold to reset"], [PlayerInput.Pad.B, "Cancel"]]
	var items: Array = []
	if s == null or tree_views.is_empty():
		return items
	if reset_selected:
		if s.points_spent() > 0:
			items.append([PlayerInput.Pad.A, "Reset Talents"])
	else:
		var t := selected_talent()
		if t != null:
			var rank := s.rank_of(t.id)
			if s.can_add(t.id):
				items.append([PlayerInput.Pad.A, "Add point"])
			if s.can_remove(t.id):
				items.append([PlayerInput.Pad.X, "Take back"])
			if rank >= 1 and rank < t.max_rank:
				items.append([PlayerInput.Pad.Y, "Now" if preview_next else "Next rank"])
	items.append([TrainerTab.NAV_PROMPT_SIDEWAYS, "Select"])
	return items


## Short context text for the panel's prompt row ("Arms · Tier 2", "Reset Talents").
func context_text() -> String:
	if reset_selected:
		return "Reset Talents"
	var t := selected_talent()
	if t == null:
		return ""
	var tree := state().tree_of(t.id)
	return "%s · Tier %d" % [tree.display_name if tree != null else "", t.tier]


# --- Build -------------------------------------------------------------------------------------

func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var body := UiTheme.hbox(COLUMN_GAP)
	body.name = "Body"
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(body)
	var trees_holder := Control.new()
	trees_holder.name = "Trees"
	trees_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trees_holder.custom_minimum_size = Vector2(TREES_WIDTH, TalentTreeView.HEIGHT)
	trees_holder.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(trees_holder)
	_trees_row = UiTheme.hbox(TREE_GAP)
	_trees_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	trees_holder.add_child(_trees_row)
	rail = TalentTreeView.TierRail.create()
	_trees_row.add_child(rail)
	empty_label = UiTheme.centered_label(EMPTY_TEXT, &"", 18, UiTheme.TEXT_DIM)
	empty_label.name = "Empty"
	empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	empty_label.visible = false
	trees_holder.add_child(empty_label)
	var right := UiTheme.vbox(RESET_GAP)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	right.add_child(_build_detail())
	reset_row = ResetRow.create()
	right.add_child(reset_row)


func _build_detail() -> Control:
	var panel := UiTheme.panel(UiTheme.INSET_PANEL)
	panel.name = "Detail"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.clip_contents = true
	var style := UiTheme.inset_style()
	style.content_margin_left = 10
	style.content_margin_right = 10
	panel.add_theme_stylebox_override(&"panel", style)
	_detail_box = UiTheme.vbox(4)
	panel.add_child(_detail_box)
	header_label = UiTheme.wrapped_label("", &"", 15, UiTheme.GOLD)
	header_label.name = "Header"
	header_label.add_theme_font_override(&"font", UiTheme.bold_font())
	_detail_box.add_child(header_label)
	var rule := ColorRect.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.color = Color(UiTheme.GOLD_DARK, 0.7)
	rule.custom_minimum_size = Vector2(0, 1)
	_detail_box.add_child(rule)
	var head := UiTheme.hbox(8)
	_detail_glyph_holder = Control.new()
	_detail_glyph_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_glyph_holder.custom_minimum_size = Vector2(DETAIL_GLYPH, DETAIL_GLYPH)
	_detail_glyph_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_detail_glyph_holder)
	var titles := UiTheme.vbox(0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	detail_name = UiTheme.wrapped_label("", &"", 18, UiTheme.GOLD_BRIGHT)
	detail_name.add_theme_font_override(&"font", UiTheme.bold_font())
	detail_name.max_lines_visible = 2
	detail_name.add_theme_constant_override(&"line_spacing", -2)
	titles.add_child(detail_name)
	detail_kind = UiTheme.label("", &"", 14, UiTheme.TEXT_DIM)
	detail_kind.clip_text = true
	detail_kind.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail_kind.custom_minimum_size.x = 40
	titles.add_child(detail_kind)
	head.add_child(titles)
	_detail_box.add_child(head)
	_rank_row = UiTheme.hbox(8)
	detail_rank = UiTheme.label("", &"", DETAIL_FONT, UiTheme.GOLD)
	detail_rank.add_theme_font_override(&"font", UiTheme.bold_font())
	_rank_row.add_child(detail_rank)
	detail_state = UiTheme.label("", &"", 14, UiTheme.TEXT_DIM)
	detail_state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_state.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	detail_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	detail_state.clip_text = true
	detail_state.custom_minimum_size.x = 30
	_rank_row.add_child(detail_state)
	_detail_box.add_child(_rank_row)
	# The texts live in a clipping holder without a minimum size: a long description is cut off
	# (ellipsis) instead of pushing the tree line out of the panel ([method _fit_description]).
	_texts_holder = Control.new()
	_texts_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_texts_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_texts_holder.clip_contents = true
	_detail_box.add_child(_texts_holder)
	_texts = UiTheme.vbox(3)
	_texts.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_texts_holder.add_child(_texts)
	detail_text = _detail_text(UiTheme.TEXT, 6)
	detail_next = _detail_text(UiTheme.GREEN, 4)
	detail_hint = _detail_text(NOT_LEARNED_COLOR, 2)
	detail_reason = _detail_text(UiTheme.RED, 2)
	detail_tree = _detail_text(UiTheme.TEXT_DIM, MAX_TREE_LINES)
	detail_tree.add_theme_font_size_override(&"font_size", 14)
	_texts.sort_children.connect(_fit_description)
	_texts_holder.resized.connect(_fit_description)
	return panel


## A wrapped detail text, at most [param max_lines] lines (ellipsis after).
func _detail_text(color: Color, max_lines: int) -> Label:
	var l := UiTheme.wrapped_label("", &"", DETAIL_FONT, color)
	l.max_lines_visible = max_lines
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.add_theme_constant_override(&"line_spacing", 0)
	_texts.add_child(l)
	return l


func _rebuild_trees(trees: Array[TalentTreeData]) -> void:
	for v in tree_views:
		_trees_row.remove_child(v)
		v.queue_free()
	tree_views.clear()
	_nav_points.clear()
	_built_for = _state
	_built_trees = trees.duplicate()
	var x := TalentTreeView.TierRail.WIDTH + TREE_GAP
	for tree in trees:
		var v := TalentTreeView.create(tree)
		_trees_row.add_child(v)
		tree_views.append(v)
		for id in v.nodes:
			_nav_points[id] = Vector2(x, 0.0) + TalentTreeView.node_rect(v.nodes[id].talent).get_center()
		x += TalentTreeView.WIDTH + TREE_GAP
	if not tree_views.is_empty():
		# The Reset row is under the detail, right of the trees: below every node (only "down"
		# reaches it, see move_selection).
		_nav_points[RESET_KEY] = Vector2(TREES_WIDTH + COLUMN_GAP + DETAIL_WIDTH * 0.5, TalentTreeView.HEIGHT - RESET_HEIGHT * 0.5)
	var empty := tree_views.is_empty()
	rail.visible = not empty
	reset_row.visible = not empty
	empty_label.visible = empty and _state != null
	if empty:
		selected_id = &""
		reset_selected = false


# --- Refresh helpers --------------------------------------------------------------------------------

func _bind(p: Player) -> void:
	var s := p.talents if p != null else null
	if s != _state:
		if _state != null and _state.changed.is_connected(_on_talents_changed):
			_state.changed.disconnect(_on_talents_changed)
		_state = s
		if s != null:
			s.changed.connect(_on_talents_changed)
		if reset_mode != ResetMode.IDLE:
			reset_mode = ResetMode.IDLE
	var r := p.abilities if p != null else null
	if r != _runner:
		_unbind_runner()
		_runner = r
		if r != null:
			r.slots_changed.connect(_on_slots_changed)


func _unbind() -> void:
	if _state != null and _state.changed.is_connected(_on_talents_changed):
		_state.changed.disconnect(_on_talents_changed)
	_state = null
	_unbind_runner()


func _unbind_runner() -> void:
	if is_instance_valid(_runner) and _runner.slots_changed.is_connected(_on_slots_changed):
		_runner.slots_changed.disconnect(_on_slots_changed)
	_runner = null


## Picks the first talent (tier 1, column 0 of the first tree) when the selection is gone.
func _ensure_selection() -> void:
	var s := _state
	if s == null or tree_views.is_empty():
		selected_id = &""
		reset_selected = false
		return
	if s.talent(selected_id) != null and view_for(selected_id) != null:
		return
	selected_id = &""
	for v in tree_views:
		for tier in range(1, TalentTreeView.TIERS + 1):
			var in_tier := v.tree.talents_in_tier(tier)
			if not in_tier.is_empty():
				selected_id = in_tier[0].id
				return


func _accent() -> Color:
	return (slot.color if slot != null else UiTheme.GOLD).lightened(0.25)


func _update_selection() -> void:
	var accent := _accent()
	var sel_view: TalentTreeView = null
	for v in tree_views:
		v.set_selection(selected_id, _focused and not reset_selected, accent)
		if v.nodes.has(selected_id):
			sel_view = v
	if sel_view == null and not tree_views.is_empty():
		sel_view = tree_views[0]
	if sel_view != null:
		rail.set_open(sel_view.open_tiers())
	reset_row.set_selected(_focused and reset_selected, accent)
	_update_reset_row()
	_update_detail()
	prompts_changed.emit()


func _update_reset_row() -> void:
	var s := _state
	var color := UiTheme.TEXT
	if reset_mode != ResetMode.IDLE:
		color = CONFIRM_COLOR
	elif s == null or s.points_spent() <= 0:
		color = UiTheme.TEXT_DIM
	elif not RunState.can_afford(s.reset_price()):
		color = UiTheme.RED
	reset_row.show_text(reset_text(), color, reset_mode != ResetMode.IDLE)
	reset_row.set_progress(hold_progress(), _confirm_left / CONFIRM_TIME if is_confirming() else 0.0)


func _update_detail() -> void:
	var s := _state
	header_label.text = header_text()
	header_label.add_theme_color_override(&"font_color", UiTheme.GOLD if s != null and s.points_free() > 0 else UiTheme.TEXT_DIM.lightened(0.15))
	var t := selected_talent()
	var show := s != null and (reset_selected or t != null)
	for c: Control in [_rank_row, _texts_holder, _detail_glyph_holder.get_parent()]:
		c.visible = show
	if not show:
		_set_detail_glyph("", null)
		return
	if reset_selected:
		_detail_reset(s)
	else:
		_detail_talent(s, t)
	_fit_description()


func _detail_talent(s: TalentState, t: TalentData) -> void:
	var tree := s.tree_of(t.id)
	var rank := s.rank_of(t.id)
	_set_detail_glyph("talent:%s" % t.id, t)
	detail_name.text = t.display_name
	detail_kind.text = kind_text(t)
	var preview := preview_next and rank < t.max_rank
	var shown := rank + 1 if preview else rank
	detail_rank.text = "Rank %d/%d" % [shown, t.max_rank]
	detail_rank.add_theme_color_override(&"font_color", UiTheme.GREEN if preview else UiTheme.GOLD)
	var pending := int(s.pending.get(t.id, 0))
	detail_state.text = "+%d this round" % pending if pending > 0 else ""
	detail_state.add_theme_color_override(&"font_color", _accent())
	detail_text.text = t.text_for_rank(rank + 1 if preview else rank)
	detail_text.add_theme_color_override(&"font_color", UiTheme.GREEN.lightened(0.35) if preview else UiTheme.TEXT)
	detail_text.visible = detail_text.text != ""
	detail_next.text = "Next rank: %s" % t.text_for_rank(rank + 1) if not preview and rank >= 1 and rank < t.max_rank else ""
	detail_next.visible = detail_next.text != ""
	detail_hint.text = not_learned_text(t)
	detail_hint.add_theme_color_override(&"font_color", NOT_LEARNED_COLOR)
	detail_hint.visible = detail_hint.text != ""
	var reason := s.add_block_reason(t.id) if rank < t.max_rank else ""
	detail_reason.text = reason
	detail_reason.visible = reason != ""
	detail_tree.text = "%s: %s" % [tree.display_name, tree.description] if tree != null and tree.description != "" else ""
	detail_tree.visible = detail_tree.text != ""


func _detail_reset(s: TalentState) -> void:
	var price := s.reset_price()
	_set_detail_glyph("reset", null)
	detail_name.text = "Reset Talents"
	detail_kind.text = "Shared wallet" if s.resets == 0 else "Shared wallet · %d so far" % s.resets
	detail_rank.text = "Price %d g" % price
	detail_rank.add_theme_color_override(&"font_color", UiTheme.GOLD if RunState.can_afford(price) else UiTheme.RED)
	detail_state.text = ""
	detail_text.text = "Takes back all %d points, this round's too, to spend them again. Every reset doubles the price." % s.points_spent()
	detail_text.add_theme_color_override(&"font_color", UiTheme.TEXT)
	detail_text.visible = true
	detail_next.text = ""
	detail_next.visible = false
	var hint := ""
	if reset_mode == ResetMode.CONFIRM:
		hint = confirm_text()
	elif reset_mode == ResetMode.HOLD:
		hint = reset_text()
	detail_hint.text = hint
	detail_hint.add_theme_color_override(&"font_color", CONFIRM_COLOR)
	detail_hint.visible = hint != ""
	var reason := s.reset_block_reason() if reset_mode == ResetMode.IDLE else ""
	detail_reason.text = reason
	detail_reason.visible = reason != ""
	detail_tree.text = ""
	detail_tree.visible = false


## "Talent · Tier 2", "Modifier · Whirlwind", "Capstone" – without the tree's name, which the
## prompt row's context already shows ("Arms · Tier 2"), so the one-line kind fits the detail
## column (every shipped talent, also at 720p).
static func kind_text(t: TalentData) -> String:
	if t.is_capstone():
		return "Capstone"
	if t.is_modifier():
		return "Modifier · %s" % ability_name(t.ability)
	return "Talent · Tier %d" % t.tier


static func ability_name(id: StringName) -> String:
	var a := Db.get_ability(id)
	return a.display_name if a != null else String(id).capitalize()


## "You haven't learned Whirlwind" for a modifier whose ability is not slotted ("" otherwise).
func not_learned_text(t: TalentData) -> String:
	if t == null or not t.is_modifier() or t.ability == &"":
		return ""
	if _runner != null and _runner.knows(t.ability):
		return ""
	return "You haven't learned %s" % ability_name(t.ability)


func _set_detail_glyph(key: String, t: TalentData) -> void:
	if key == _detail_glyph_key:
		return
	_detail_glyph_key = key
	for c in _detail_glyph_holder.get_children():
		_detail_glyph_holder.remove_child(c)
		c.queue_free()
	if key == "":
		return
	var g: Control = TalentGlyph.create(TalentGlyph.Glyph.RESET, DETAIL_GLYPH) if t == null else TalentNode.make_glyph(t, DETAIL_GLYPH)
	_detail_glyph_holder.add_child(g)


## Shares the clip holder's height: the next-rank, hint and reason lines are never cut, the
## description gets the whole lines it needs from what is left (at least
## MIN_DESCRIPTION_LINES), and the tree's identity line only shows when it fits whole in the
## room after that.
## Runs once the layout is known and after every detail update.
func _fit_description() -> void:
	if _texts_holder.size.y <= 0.0 or _texts.size.x <= 0.0:
		return
	var gap := float(_texts.get_theme_constant(&"separation"))
	var room := _texts_holder.size.y
	for l: Label in [detail_next, detail_hint, detail_reason]:
		if l.visible:
			room -= l.get_combined_minimum_size().y + gap
	# A long description (capstones) steps its font down to MIN_DETAIL_FONT before it is cut.
	var width := _texts.size.x
	var font := detail_text.get_theme_font(&"font")
	var fs := DETAIL_FONT
	while fs > MIN_DETAIL_FONT and _wrapped_lines(detail_text, width, fs) * font.get_height(fs) > room:
		fs -= 1
	if detail_text.get_theme_font_size(&"font_size") != fs:
		detail_text.add_theme_font_size_override(&"font_size", fs)
	var line_h := font.get_height(fs)
	var fit := maxi(MIN_DESCRIPTION_LINES, floori(room / line_h))
	var lines := mini(fit, maxi(1, _wrapped_lines(detail_text, width, fs)))
	if detail_text.max_lines_visible != fit:
		detail_text.max_lines_visible = fit
		# Label keeps its old minimum height after a max_lines_visible change until asked again.
		detail_text.update_minimum_size()
	room -= lines * line_h + gap
	# The identity line shows whole or not at all.
	var tree_lines := _wrapped_lines(detail_tree, width, detail_tree.get_theme_font_size(&"font_size"))
	var tree_visible := detail_tree.text != "" and tree_lines <= MAX_TREE_LINES \
		and tree_lines * float(detail_tree.get_line_height()) <= room
	if detail_tree.visible != tree_visible:
		detail_tree.visible = tree_visible


## Lines [param l]'s text wraps into at [param width] and font size [param fs] (measured, so
## a hidden label counts too).
static func _wrapped_lines(l: Label, width: float, fs: int) -> int:
	if l.text == "" or width <= 0.0:
		return 0
	var font := l.get_theme_font(&"font")
	var h := font.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, width, fs, -1,
		TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE).y
	return maxi(1, ceili(h / font.get_height(fs) - 0.01))


## The confirm / hold is still for the current price, the wallet can still pay it and
## something is left to reset.
func _reset_still_valid() -> bool:
	var s := _state
	if s == null or not reset_selected or s.reset_block_reason() != "":
		return false
	return reset_mode != ResetMode.HOLD or s.reset_price() == _hold_price


func _do_reset() -> bool:
	var s := _state
	reset_mode = ResetMode.IDLE
	_confirm_left = 0.0
	_hold_time = 0.0
	if s == null:
		return false
	var price := s.reset_price()
	if not s.try_reset(slot.index if slot != null else -1):
		_say(s.reset_block_reason() if s.reset_block_reason() != "" else "Not enough gold", "", UiTheme.RED)
		refresh()
		return false
	_say("Talents reset  -%s" % UiTheme.format_int(price), "Talents reset", UiTheme.TEXT, true)
	# try_reset emitted changed (a refresh while shown); the row and prompts follow either way.
	_update_reset_row()
	prompts_changed.emit()
	return true


## Emits points_changed when the label may differ ([param force]: always).
func _announce_points(force: bool = false) -> void:
	if force or RunState.level != _label_level:
		_label_level = RunState.level
		points_changed.emit()


func _on_talents_changed() -> void:
	_refresh_if_shown()
	_announce_points(true)


func _on_slots_changed() -> void:
	_refresh_if_shown()


func _on_gold_changed(_gold: int, _delta: int) -> void:
	if _state == null:
		return
	if not is_visible_in_tree():
		_stale = true
		return
	if reset_mode != ResetMode.IDLE and not _reset_still_valid():
		cancel_reset()
	_update_reset_row()
	_update_detail()
	prompts_changed.emit()


func _on_xp_changed(_xp: int, _needed: int) -> void:
	if RunState.level == _label_level:
		return
	_refresh_if_shown()
	_announce_points()


## Refreshes now when the tab is on screen, else marks it stale (the Intermission keeps the
## panels in the tree, hidden, through the whole wave). True when it refreshed.
func _refresh_if_shown() -> bool:
	if not is_visible_in_tree():
		_stale = true
		return false
	refresh()
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and _stale and is_visible_in_tree():
		_catch_up.call_deferred()


## The stale tab was shown: refreshes at the end of the frame unless an explicit refresh()
## (PlayerPanel.set_tab, the market start) came first.
func _catch_up() -> void:
	if _stale and is_visible_in_tree():
		refresh()


static func _bb_name(text: String) -> String:
	return "[color=#%s]%s[/color]" % [UiTheme.GOLD_BRIGHT.to_html(false), text.replace("[", "(")]


func _say(bbcode: String, plain: String, color: Color, coin: bool = false) -> void:
	message.emit(bbcode, plain if plain != "" else bbcode, color, coin)


func _enter_tree() -> void:
	if not RunState.gold_changed.is_connected(_on_gold_changed):
		RunState.gold_changed.connect(_on_gold_changed)
	if not RunState.xp_changed.is_connected(_on_xp_changed):
		RunState.xp_changed.connect(_on_xp_changed)


func _exit_tree() -> void:
	if RunState.gold_changed.is_connected(_on_gold_changed):
		RunState.gold_changed.disconnect(_on_gold_changed)
	if RunState.xp_changed.is_connected(_on_xp_changed):
		RunState.xp_changed.disconnect(_on_xp_changed)
	_unbind()
