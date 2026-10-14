class_name GameOverScreen
extends Control
## End-of-run screen (GDD 1, M6): "Victory!" (gold) or "Defeat" (red) over two pages. Summary:
## waves cleared, total kills, gold earned, team level, the run time and one row per player (class,
## kills, damage; the top damage dealer gets a crown). Damage Meter ([MeterPage]): bars per stat
## and hero in the class colours and, in co-op, the Awards ([RunSummary]). After INPUT_DELAY, on
## any joined player's own device: LB / RB (or left / right) switch the page, X saves the run card
## ([method save_card], a 1200 x 630 PNG in user://cards), A / START ->
## back_to_menu_requested (once per open). Godot's global ui_accept / any controller's A only
## count when no joined player has a working device (nobody joined, a bot-only demo, or every
## human's controller unplugged), so a second device never acts for somebody else's slot.
## See docs/ARCHITECTURE.md.

signal back_to_menu_requested
## The run card was written to [param path] ("" = it could not be saved).
signal card_saved(path: String)

## Seconds before input is accepted (players are usually still mashing buttons).
const INPUT_DELAY := 1.0
enum Page { SUMMARY, METER }
const PAGE_NAMES: Array[String] = ["Summary", "Damage Meter"]
## --end-page values (LaunchOptions).
const PAGE_IDS: Array[String] = ["summary", "meter"]
## The longest "Saved to ..." line (characters): a longer path keeps its end (folder + file name).
const MAX_STATUS_CHARS := 72

var victory := false
var title_label: Label
var subtitle_label: Label
var waves_value: Label
var kills_value: Label
var gold_value: Label
var level_value: Label
var time_value: Label
var rows_box: VBoxContainer
## The page shown (Page.SUMMARY / Page.METER).
var page := Page.SUMMARY
## The framed panel in the middle (tests measure it).
var panel: PanelContainer
var summary_page: Control
var meter_page: MeterPage
## Holds both pages; as tall as the taller one (see [method _fit_pages]).
var page_box: MarginContainer
## The line under the prompts ("Saved to ..." after X).
var status_label: Label
## The tab labels, one per page.
var tab_labels: Array[Label] = []
## Controller edges (A on any pad). Public for tests.
var pads := UiPads.new()

var _t := 0.0
var _done := true
var _saving := false
var _prompt: Control
var _backdrop: TextureRect


static func create() -> GameOverScreen:
	var g := GameOverScreen.new()
	g.name = "GameOverScreen"
	g._build()
	return g


## Fills in the end-of-run summary from RunState (victory / defeat, waves, kills, gold).
func open(p_victory: bool) -> void:
	victory = p_victory
	_t = 0.0
	_done = false
	_set_status("")
	_fill()
	set_page(Page.SUMMARY)
	for s in PlayerManager.get_slots():
		if s.input != null and not s.is_bot():
			s.input.swallow()  # a stick push / button still held from the fight is not for this screen
	show()


## Number of waves the team survived.
static func waves_cleared(p_victory: bool) -> int:
	return RunState.TOTAL_WAVES if p_victory else clampi(RunState.wave - 1, 0, RunState.TOTAL_WAVES)


func set_backdrop_opacity(alpha: float) -> void:
	_backdrop.modulate.a = alpha


## Shows page [param p_page] (Page.SUMMARY / Page.METER).
func set_page(p_page: Page) -> void:
	page = p_page
	summary_page.visible = page == Page.SUMMARY
	meter_page.visible = page == Page.METER
	for i in tab_labels.size():
		var active := i == int(page)
		tab_labels[i].add_theme_color_override(&"font_color", UiTheme.GOLD if active else UiTheme.TEXT_DIM)
		tab_labels[i].add_theme_font_size_override(&"font_size", UiTheme.FONT_LARGE + (2 if active else -2))


## The next ([param step] +1) / previous (-1) page; the ends do not wrap.
func switch_page(step: int) -> void:
	set_page(clampi(int(page) + signi(step), 0, PAGE_NAMES.size() - 1) as Page)


## Page index for an --end-page name ("summary" / "meter"; anything else: the Summary).
static func page_from_name(page_name: String) -> Page:
	var at := PAGE_IDS.find(page_name)
	return (at if at >= 0 else Page.SUMMARY) as Page


## Renders the run card (RunCard: a 1200 x 630 picture of this run) through a SubViewport and saves it
## as user://cards/run_<date>_<time>.png; the status line then says "Saved to <path>" and
## [signal card_saved] fires (path "" if the picture could not be made or written, e.g. without a
## renderer). One card at a time.
func save_card() -> void:
	if _saving or not visible:
		return
	_saving = true
	_set_status("Saving the card...")
	var card_model := RunCard.model(RunSummary.collect(victory))
	var image := await RunCard.render(self, card_model)
	_saving = false
	if not is_instance_valid(self):
		return
	var path := RunCard.save_png(image)
	if path == "":
		_set_status("The card could not be saved.", UiTheme.RED)
	else:
		var full := ProjectSettings.globalize_path(path)
		print("Run card saved to ", full)
		_set_status(saved_text(full), UiTheme.GREEN)
	card_saved.emit(path)


## "Saved to <path>" for the status line. A path longer than [constant MAX_STATUS_CHARS] loses its
## beginning, at a folder boundary ("Saved to .../SmartOnion/cards/run_2026-10-14_15-20-11.png"): the
## line never gets wider than the panel, whatever the platform's user folder is (the full path goes
## to the log).
static func saved_text(full_path: String) -> String:
	var room := MAX_STATUS_CHARS - "Saved to ".length()
	if full_path.length() <= room:
		return "Saved to %s" % full_path
	var tail := full_path.right(room - 3)  # 3 = the dots
	var cut := tail.find("/")
	if cut >= 0 and cut < tail.length() - 1:
		tail = tail.substr(cut)
	return "Saved to ...%s" % tail


func _set_status(text: String, color: Color = UiTheme.TEXT_DIM) -> void:
	if status_label == null:
		return
	status_label.text = text if text != "" else " "
	status_label.add_theme_color_override(&"font_color", color)


# --- Build ---------------------------------------------------------------------------

func _build() -> void:
	UiTheme.setup_root(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_backdrop = UiTheme.backdrop(0.9, Color(0.3, 0.18, 0.1))
	add_child(_backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	panel = UiTheme.panel()
	var style := UiTheme.stone_style()
	style.content_margin_left = 48
	style.content_margin_right = 48
	style.content_margin_top = 26
	style.content_margin_bottom = 30
	panel.add_theme_stylebox_override(&"panel", style.rebuild())
	panel.custom_minimum_size = Vector2(1140, 0)
	center.add_child(panel)
	var col := UiTheme.vbox(12)
	panel.add_child(col)

	title_label = UiTheme.centered_label("Victory!", UiTheme.TITLE, 110)
	title_label.add_theme_constant_override(&"outline_size", 18)
	col.add_child(title_label)
	subtitle_label = UiTheme.centered_label("", UiTheme.DIM, UiTheme.FONT_LARGE)
	col.add_child(subtitle_label)
	col.add_child(UiTheme.divider(700))
	col.add_child(_build_tabs())

	# Both pages share one box, as tall as the taller one ([method _fit_pages]): the panel keeps its
	# size and the title its place when switching pages.
	page_box = MarginContainer.new()
	page_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(page_box)

	summary_page = UiTheme.vbox(12)
	summary_page.size_flags_vertical = Control.SIZE_SHRINK_CENTER  # the shorter page floats in the middle
	page_box.add_child(summary_page)
	var stats := UiTheme.hbox(12)
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	summary_page.add_child(stats)
	waves_value = _stat_tile(stats, "Waves cleared", null)
	kills_value = _stat_tile(stats, "Enemies slain", UiIcon.create(UiIcon.Kind.SWORDS, Vector2(30, 30), Color(0.85, 0.87, 0.92)))
	gold_value = _stat_tile(stats, "Gold earned", UiIcon.create(UiIcon.Kind.COIN, Vector2(30, 30)))
	level_value = _stat_tile(stats, "Team level", null)
	time_value = _stat_tile(stats, "Run time", null)

	var table := UiTheme.panel(UiTheme.INSET_PANEL)
	summary_page.add_child(table)
	var tcol := UiTheme.vbox(6)
	table.add_child(tcol)
	tcol.add_child(_row_layout([UiTheme.label("Hero", UiTheme.SMALL), UiTheme.label("Class", UiTheme.SMALL),
		UiTheme.label("Kills", UiTheme.SMALL), UiTheme.label("Damage", UiTheme.SMALL), Control.new()]))
	rows_box = UiTheme.vbox(6)
	tcol.add_child(rows_box)

	meter_page = MeterPage.create()
	page_box.add_child(meter_page)

	_prompt = UiTheme.prompt_row([
		[UiGlyph.pad(PlayerInput.Pad.LB), UiGlyph.pad(PlayerInput.Pad.RB), "/", UiGlyph.key("Q"), UiGlyph.key("E"),
			"/", UiGlyph.nav(), "Page"],
		[UiGlyph.pad(PlayerInput.Pad.X), "/", UiGlyph.key("R"), "Save card"],
		[UiGlyph.pad(PlayerInput.Pad.A), "/", UiGlyph.key("Enter"), "Back to Lobby"]],
		UiTheme.FONT_LARGE - 4, UiTheme.TEXT)
	col.add_child(_prompt)
	status_label = UiTheme.centered_label(" ", UiTheme.DIM, UiTheme.FONT_BODY)
	# One line, whatever the text: too long ends in "..." instead of widening / growing the panel.
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(status_label)
	visible = false


## "LB  Summary | Damage Meter  RB": the active page's name is gold.
func _build_tabs() -> Control:
	var row := UiTheme.hbox(28)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(UiGlyph.pad(PlayerInput.Pad.LB, 26.0))
	for i in PAGE_NAMES.size():
		var tab := UiTheme.centered_label(PAGE_NAMES[i], UiTheme.GOLD_LABEL, UiTheme.FONT_LARGE)
		tab_labels.append(tab)
		row.add_child(tab)
	row.add_child(UiGlyph.pad(PlayerInput.Pad.RB, 26.0))
	return row


func _stat_tile(parent: Control, caption: String, icon: Control) -> Label:
	var tile := UiTheme.panel(UiTheme.INSET_PANEL)
	tile.custom_minimum_size = Vector2(196, 100)
	parent.add_child(tile)
	var box := UiTheme.vbox(0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	tile.add_child(box)
	var row := UiTheme.hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if icon != null:
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon)
	var value := UiTheme.label("0", UiTheme.BIG_NUMBER, 40)
	row.add_child(value)
	box.add_child(row)
	box.add_child(UiTheme.centered_label(caption, UiTheme.SMALL, UiTheme.FONT_SMALL + 1))
	return value


## [hero, class, kills, damage, badge] with fixed column widths.
func _row_layout(cells: Array) -> HBoxContainer:
	var widths: Array[float] = [230.0, 300.0, 170.0, 200.0, 60.0]
	var row := UiTheme.hbox(12)
	for i in cells.size():
		var c := cells[i] as Control
		c.custom_minimum_size.x = widths[i]
		if i == 1:
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if c is Label and (i == 2 or i == 3):
			(c as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(c)
	return row


func _fill() -> void:
	if victory:
		title_label.text = "Victory!"
		title_label.add_theme_color_override(&"font_color", UiTheme.GOLD)
		subtitle_label.text = "All %d waves survived – the onions prevail!" % RunState.TOTAL_WAVES
	else:
		title_label.text = "Defeat"
		title_label.add_theme_color_override(&"font_color", UiTheme.RED)
		subtitle_label.text = "The party was peeled on wave %d. Dry your tears and try again." % maxi(RunState.wave, 1)
	waves_value.text = "%d / %d" % [waves_cleared(victory), RunState.TOTAL_WAVES]
	kills_value.text = UiTheme.format_int(RunState.kills)
	gold_value.text = UiTheme.format_int(RunState.gold_earned)
	gold_value.add_theme_color_override(&"font_color", UiTheme.GOLD)
	level_value.text = str(RunState.level)
	time_value.text = RunSummary.format_time(RunState.run_time)
	meter_page.fill(RunSummary.collect(victory))

	for c in rows_box.get_children():
		rows_box.remove_child(c)
		c.queue_free()
	var slots := PlayerManager.get_slots()
	var best := -1
	var best_damage := 0.0
	for s in slots:
		var dmg: float = RunState.damage_by_player.get(s.index, 0.0)
		if dmg > best_damage:
			best_damage = dmg
			best = s.index
	for s in slots:
		rows_box.add_child(_player_row(s, s.index == best and slots.size() > 1))
	if slots.is_empty():
		rows_box.add_child(UiTheme.centered_label("No heroes", UiTheme.DIM))
	_fit_pages()


## Sizes [member page_box] to the taller page (the Damage Meter grows by a second row of Awards, the
## Summary by more hero rows ...). Hidden pages still know their minimum size.
func _fit_pages() -> void:
	page_box.custom_minimum_size = Vector2(0.0, maxf(summary_page.get_combined_minimum_size().y,
			meter_page.get_combined_minimum_size().y))


func _player_row(s: PlayerSlot, mvp: bool) -> Control:
	var hero := UiTheme.hbox(10)
	var swatch := ColorRect.new()
	swatch.color = s.color
	swatch.custom_minimum_size = Vector2(8, 34)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.add_child(swatch)
	var data := s.class_data
	var portrait := UiPortrait.create(44.0)
	portrait.setup(s.color, data)
	hero.add_child(portrait)
	hero.add_child(UiTheme.label(s.label(), UiTheme.GOLD_LABEL, 28, s.color.lightened(0.3)))
	var cls := UiTheme.label(data.display_name if data != null else "?", UiTheme.GOLD_LABEL, 28)
	var kills: int = RunState.kills_by_player.get(s.index, 0)
	var dmg: float = RunState.damage_by_player.get(s.index, 0.0)
	var kill_label := UiTheme.label(UiTheme.format_int(kills), &"", UiTheme.FONT_LARGE)
	var dmg_label := UiTheme.label(UiTheme.format_int(roundi(dmg)), &"", UiTheme.FONT_LARGE)
	var badge: Control = UiIcon.create(UiIcon.Kind.CROWN, Vector2(34, 30)) if mvp else Control.new()
	return _row_layout([hero, cls, kill_label, dmg_label, badge])


# --- Frame ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	pads.poll()
	if not visible or _done:
		return
	_t += delta
	var accepting := _t >= INPUT_DELAY
	_prompt.modulate.a = clampf((_t - INPUT_DELAY + 0.4) / 0.4, 0.0, 1.0)
	if not accepting:
		return
	var go := false
	for s in PlayerManager.get_slots():
		if s.input == null:
			continue
		if s.input.just_pressed(PlayerInput.Pad.A) or s.input.just_pressed(PlayerInput.Pad.START):
			go = true
		if s.is_bot():
			continue  # a bot's last stick push must not turn the page
		var step := int(s.input.just_pressed(PlayerInput.Pad.RB)) - int(s.input.just_pressed(PlayerInput.Pad.LB)) \
				+ s.input.nav_just_pressed().x
		if step != 0:
			switch_page(signi(step))
		if s.input.just_pressed(PlayerInput.Pad.X):
			save_card()
	if not PlayerManager.has_connected_human():
		# Nobody who could press a button: the global actions keep the screen from soft-locking.
		go = go or Input.is_action_just_pressed(&"ui_accept") or pads.any_just_pressed(JOY_BUTTON_A) \
			or pads.any_just_pressed(JOY_BUTTON_START)
	if go:
		_done = true
		back_to_menu_requested.emit()
