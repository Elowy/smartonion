class_name GameOverScreen
extends Control
## End-of-run screen (GDD 1, M6): "Victory!" (gold) or "Defeat" (red) over three pages (M6b adds the
## Leaderboard: [LeaderboardPage], the local top 10 of the run's category with this run highlighted; the
## Summary shows the "Best: ..." line under its table, and the mode row under the subtitle holds the arena
## name, plus the mode and the HARDCORE badge in an endless / hardcore run). Summary:
## waves cleared, total kills, gold earned, team level, the run time and one row per player (class,
## kills, damage; the top damage dealer gets a crown). Damage Meter ([MeterPage]): bars per stat
## and hero in the class colours and, in co-op, the Awards ([RunSummary]). After INPUT_DELAY, on
## any joined player's own device: LB / RB (or left / right) switch the page, X saves the run card
## ([method save_card], a 1200 x 630 PNG in user://cards), A / START ->
## back_to_menu_requested (once per open). M9 LEVELS: with a profile that records runs a fourth page, Progress, follows
## the Leaderboard – per class that played: Class Level before -> after, the XP bar, "+N XP", the rewards of the new levels
## (abilities, capstones, Seasoning slots ...) – and the run's Seeds ([method progress_rows]); its tab appears only then
## (a run that is not recorded – every automated run – has the three pages above). Godot's global ui_accept / any controller's A only
## count when no joined player has a working device (nobody joined, a bot-only demo, or every
## human's controller unplugged), so a second device never acts for somebody else's slot.
## See docs/ARCHITECTURE.md.

signal back_to_menu_requested
## The run card was written to [param path] ("" = it could not be saved).
signal card_saved(path: String)

## Seconds before input is accepted (players are usually still mashing buttons).
const INPUT_DELAY := 1.0
enum Page { SUMMARY, METER, LEADERBOARD, PROGRESS }
## The tabs every run has; the Progress tab ([constant PROGRESS_TAB_NAME]) joins them when the run was recorded in a profile.
const PAGE_NAMES: Array[String] = ["Summary", "Damage Meter", "Leaderboard"]
const PROGRESS_TAB_NAME := "Progress"
## --end-page values (LaunchOptions).
const PAGE_IDS: Array[String] = ["summary", "meter", "leaderboard", "progress"]
## The longest "Saved to ..." line (characters): a longer path keeps its end (folder + file name).
const MAX_STATUS_CHARS := 72

var victory := false
var title_label: Label
var subtitle_label: Label
## The arena of the run (M6b ENV): "Arena: Cemetery", in the environment's colour, in the mode row under the
## subtitle, where it has the panel's whole width (in the tab row it was cut to "Arena: Forest R...").
var environment_label: Label
var waves_value: Label
var kills_value: Label
var gold_value: Label
var level_value: Label
var time_value: Label
var rows_box: VBoxContainer
## The page shown (Page.SUMMARY / Page.METER / Page.LEADERBOARD).
var page := Page.SUMMARY
## The framed panel in the middle (tests measure it).
var panel: PanelContainer
var summary_page: Control
var meter_page: MeterPage
var leaderboard_page: LeaderboardPage
## Holds the pages; as tall as the tallest one (see [method _fit_pages]).
var page_box: MarginContainer
## M6b: the leaderboard model of this run ([method Leaderboard.screen_model]; {} = no board, see [method open]).
var board: Dictionary = {}
## M6b: the mode row under the subtitle: the arena name ([member environment_label]) and, beside it, "Endless
## mode" / "Normal mode" and the HARDCORE badge (an endless or a hardcore run only). The "Best: ..." line sits
## under the Summary's hero table.
var mode_row: HBoxContainer
var mode_label: Label
var hardcore_badge: HardcoreBadge
var best_label: Label
## M9 LEVELS: the Progress page (its tab exists only when the run was recorded: not in the dev profile of the automated
## runs), the panel on it, its rows (one per class that played) and the Seeds line at the panel's right.
var progress_page: Control
var progress_panel: PanelContainer
var progress_box: VBoxContainer
var progress_seeds_label: Label
## What the profile made of the run ([member Main.meta_result]); {} = nothing recorded.
var meta: Dictionary = {}
## The line under the prompts ("Saved to ..." after X).
var status_label: Label
## The tab labels, one per page (the Progress tab is the last one and only there while [method has_progress]).
var tab_labels: Array[Label] = []
## Controller edges (A on any pad). Public for tests.
var pads := UiPads.new()

var _tab_row: HBoxContainer
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


## Fills in the end-of-run summary from RunState (victory / defeat, waves, kills, gold). [param p_board] is
## the run's leaderboard model ([method Leaderboard.screen_model], what Main reads after recording the
## run); {} = no board (the leaderboard file is not in use).
## [param p_meta] is what the profile made of the run (Main.meta_result; {} = nothing recorded): it fills the Class Progress panel.
func open(p_victory: bool, p_board: Dictionary = {}, p_meta: Dictionary = {}) -> void:
	victory = p_victory
	board = p_board
	meta = p_meta
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
	var total := RunState.total_waves()
	if p_victory:
		return total if total > 0 else maxi(RunState.wave, 0)
	return clampi(RunState.wave - 1, 0, total) if total > 0 else maxi(RunState.wave - 1, 0)


func set_backdrop_opacity(alpha: float) -> void:
	_backdrop.modulate.a = alpha


## Shows page [param p_page] (Page.SUMMARY / Page.METER / Page.LEADERBOARD).
func set_page(p_page: Page) -> void:
	page = Page.SUMMARY if p_page == Page.PROGRESS and not has_progress() else p_page
	summary_page.visible = page == Page.SUMMARY
	meter_page.visible = page == Page.METER
	leaderboard_page.visible = page == Page.LEADERBOARD
	progress_page.visible = page == Page.PROGRESS
	for i in tab_labels.size():
		var active := i == int(page)
		var idle := UiTheme.GOLD_BRIGHT.lerp(UiTheme.TEXT_DIM, 0.3) if i == int(Page.PROGRESS) and _leveled_up() else UiTheme.TEXT_DIM
		tab_labels[i].add_theme_color_override(&"font_color", UiTheme.GOLD if active else idle)
		tab_labels[i].add_theme_font_size_override(&"font_size", UiTheme.FONT_LARGE + (2 if active else -2))


## The next ([param step] +1) / previous (-1) page; the ends do not wrap.
func switch_page(step: int) -> void:
	var before := page
	set_page(clampi(int(page) + signi(step), 0, tab_labels.size() - 1) as Page)
	if page != before:
		Audio.play_ui(&"ui_tab")


## Page index for an --end-page name ("summary" / "meter" / "leaderboard" / "progress"; anything else: the Summary).
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


## The arena label of the end screen: "Arena: Cemetery" ("" for an id nobody knows).
static func environment_text(id: StringName) -> String:
	var env := Db.get_environment(id)
	return "Arena: %s" % env.display_name if env != null else ""


func _fill_environment() -> void:
	environment_label.text = environment_text(RunState.environment)
	var env := Db.get_environment(RunState.environment)
	environment_label.add_theme_color_override(&"font_color",
			env.card_color.lerp(Color.WHITE, 0.25) if env != null else UiTheme.TEXT_DIM)


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
	# The subtitle and the mode row are one group with a tight gap. The mode row always shows (it holds the arena
	# name); the mode and the badge are hidden in a normal run, and in an endless / hardcore run the arena name
	# joins that row on the same line, so the worst-case panel still fits 1080 px.
	var head := UiTheme.vbox(2)
	col.add_child(head)
	subtitle_label = UiTheme.centered_label("", UiTheme.DIM, UiTheme.FONT_LARGE)
	head.add_child(subtitle_label)
	mode_row = UiTheme.hbox(14)
	mode_row.name = "ModeRow"
	mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mode_label = UiTheme.centered_label("", UiTheme.GOLD_LABEL, UiTheme.FONT_BODY)
	mode_row.add_child(mode_label)
	hardcore_badge = HardcoreBadge.create(UiTheme.FONT_BODY - 2)
	mode_row.add_child(hardcore_badge)
	environment_label = UiTheme.centered_label("", UiTheme.DIM, UiTheme.FONT_BODY)
	environment_label.name = "ArenaLabel"
	mode_row.add_child(environment_label)
	head.add_child(mode_row)
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
	best_label = UiTheme.centered_label(" ", UiTheme.GOLD_LABEL, UiTheme.FONT_BODY)
	best_label.name = "BestLabel"
	summary_page.add_child(best_label)

	meter_page = MeterPage.create()
	page_box.add_child(meter_page)
	leaderboard_page = LeaderboardPage.create()
	page_box.add_child(leaderboard_page)
	page_box.add_child(_build_progress_page())

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


## "LB  Summary | Damage Meter | Leaderboard  RB": the active page's name is gold.
func _build_tabs() -> Control:
	_tab_row = UiTheme.hbox(28)
	_tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_tab_row.add_child(UiGlyph.pad(PlayerInput.Pad.LB, 26.0))
	for i in PAGE_NAMES.size():
		var tab := UiTheme.centered_label(PAGE_NAMES[i], UiTheme.GOLD_LABEL, UiTheme.FONT_LARGE)
		tab_labels.append(tab)
		_tab_row.add_child(tab)
	_tab_row.add_child(UiGlyph.pad(PlayerInput.Pad.RB, 26.0))
	return _tab_row


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
		var survived := "All %d waves survived" % RunState.total_waves() if RunState.total_waves() > 0 \
				else "%d waves survived" % waves_cleared(true)
		subtitle_label.text = survived + " – the onions prevail!"
	else:
		title_label.text = "Defeat"
		title_label.add_theme_color_override(&"font_color", UiTheme.RED)
		subtitle_label.text = "The party was peeled on wave %d. Dry your tears and try again." % maxi(RunState.wave, 1)
	_fill_environment()
	waves_value.text = RunState.count_text(waves_cleared(victory))
	kills_value.text = UiTheme.format_int(RunState.kills)
	gold_value.text = UiTheme.format_int(RunState.gold_earned)
	gold_value.add_theme_color_override(&"font_color", UiTheme.GOLD)
	level_value.text = str(RunState.level)
	time_value.text = RunSummary.format_time(RunState.run_time)
	meter_page.fill(RunSummary.collect(victory))
	_fill_mode_and_board()
	_fill_progress()

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


## M6b: the mode and the HARDCORE badge of the mode row under the subtitle (an endless or a hardcore run only),
## the "Best: ..." line of the Summary and the Leaderboard page, from [member board] and RunState.
func _fill_mode_and_board() -> void:
	mode_label.visible = RunState.is_endless() or RunState.hardcore
	mode_label.text = "%s mode" % RunState.mode_text(RunState.mode)
	hardcore_badge.visible = RunState.hardcore
	leaderboard_page.fill(board)
	best_label.visible = not board.is_empty()
	best_label.text = String(board.get("line", " "))
	best_label.add_theme_color_override(&"font_color", UiTheme.GOLD_BRIGHT if int(board.get("rank", -1)) == 0 else UiTheme.GOLD)


# --- M9 LEVELS: Class Progress ---------------------------------------------------------------------

## The Progress page: one panel with a header ("Class progress" and the Seeds of the run) and one block per class.
func _build_progress_page() -> Control:
	progress_page = UiTheme.vbox(12)
	progress_page.name = "ProgressPage"
	progress_page.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	progress_page.visible = false
	progress_panel = UiTheme.panel(UiTheme.INSET_PANEL)
	progress_panel.name = "ProgressPanel"
	progress_page.add_child(progress_panel)
	var col := UiTheme.vbox(8)
	progress_panel.add_child(col)
	var head := UiTheme.hbox(10)
	head.add_child(UiTheme.label("Class progress", UiTheme.GOLD_LABEL, UiTheme.FONT_LARGE))
	head.add_child(UiTheme.spacer())
	progress_seeds_label = UiTheme.label("", UiTheme.GOLD_LABEL, UiTheme.FONT_LARGE)
	progress_seeds_label.name = "SeedsLabel"
	head.add_child(progress_seeds_label)
	col.add_child(head)
	progress_box = UiTheme.vbox(10)
	col.add_child(progress_box)
	return progress_page


## True when the run was recorded in the profile and a class earned XP: the Progress tab and page exist.
func has_progress() -> bool:
	return not progress_rows(meta).is_empty()


func _leveled_up() -> bool:
	for row in progress_rows(meta):
		if row["leveled_up"]:
			return true
	return false


## One dictionary per class that played, from [param p_meta] (Main.meta_result): {"class_id", "heroes" (shares), "xp_gained",
## "level_before", "level_after", "leveled_up", "max" (the top level), "from" / "to" (the bar's fraction before / after, 0..1),
## "into" / "needed" (XP into the level now / its cost), "rewards" (the lines of the new levels' rewards)}. [] when nothing
## was recorded.
static func progress_rows(p_meta: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var entries: Variant = p_meta.get("class_xp", [])
	if not entries is Array:
		return out
	for raw: Variant in entries:
		if not raw is Dictionary:
			continue
		var e: Dictionary = raw
		var before := ClassLevels.progress(int(e.get("xp_before", 0)), int(e.get("level_before", 1)))
		var after := ClassLevels.progress(int(e.get("xp_after", 0)), int(e.get("level_after", 1)))
		var texts: Array[String] = []
		for r: Variant in e.get("rewards", []):
			if r is Dictionary and str(r.get("text", "")) != "":
				texts.append(str(r["text"]))
		out.append({
			"class_id": StringName(str(e.get("class_id", ""))), "heroes": int(e.get("heroes", 1)),
			"xp_gained": int(e.get("xp_gained", 0)), "level_before": int(e.get("level_before", 1)),
			"level_after": int(e.get("level_after", 1)), "leveled_up": int(e.get("level_after", 1)) > int(e.get("level_before", 1)),
			"max": bool(after["max"]), "from": float(before["fraction"]) if int(e.get("level_after", 1)) == int(e.get("level_before", 1)) else 0.0,
			"to": float(after["fraction"]), "into": int(after["into"]), "needed": int(after["needed"]), "rewards": texts,
		})
	return out


## "+87 Seeds" for the run's Seeds including the level gifts ("" when none).
static func seeds_text(p_meta: Dictionary) -> String:
	var seeds: Variant = p_meta.get("seeds", {})
	var total := int(seeds.get("total", 0)) if seeds is Dictionary else 0
	return "+%d Seeds" % total if total > 0 else ""


## Fills the Progress page and adds / removes its tab (the last of [member tab_labels]).
func _fill_progress() -> void:
	for c in progress_box.get_children():
		progress_box.remove_child(c)
		c.queue_free()
	var rows := progress_rows(meta)
	progress_seeds_label.text = seeds_text(meta)
	for row in rows:
		progress_box.add_child(_progress_row(row))
	var has_tab := tab_labels.size() > PAGE_NAMES.size()
	if rows.is_empty() and has_tab:
		var tab: Label = tab_labels.pop_back()
		_tab_row.remove_child(tab)
		tab.queue_free()
	elif not rows.is_empty() and not has_tab:
		var tab := UiTheme.centered_label(PROGRESS_TAB_NAME, UiTheme.GOLD_LABEL, UiTheme.FONT_LARGE)
		tab_labels.append(tab)
		_tab_row.add_child(tab)
		_tab_row.move_child(tab, _tab_row.get_child_count() - 2)  # (before the RB glyph)


func _progress_row(row: Dictionary) -> Control:
	var class_id: StringName = row["class_id"]
	var data := Db.get_class_data(class_id)
	var color := Color.WHITE
	for s in PlayerManager.get_slots():
		if s.class_data != null and s.class_data.id == class_id:
			color = s.color
			break
	var box := UiTheme.vbox(0)
	box.name = "Progress_%s" % class_id
	var line := UiTheme.hbox(10)
	var portrait := UiPortrait.create(30.0)
	portrait.setup(color, data)
	line.add_child(portrait)
	var heroes := int(row["heroes"])
	var cls := UiTheme.label(("%s ×%d" % [data.display_name, heroes]) if data != null and heroes > 1 else (data.display_name if data != null else "?"),
			UiTheme.GOLD_LABEL, UiTheme.FONT_LARGE - 2)
	cls.custom_minimum_size.x = 190
	cls.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(cls)
	var level_text := "Lv %d" % int(row["level_before"])
	if row["leveled_up"]:
		level_text = "Lv %d → %d" % [int(row["level_before"]), int(row["level_after"])]
	var level := UiTheme.label(level_text, &"", UiTheme.FONT_LARGE - 2, UiTheme.GOLD_BRIGHT if row["leveled_up"] else UiTheme.TEXT)
	level.custom_minimum_size.x = 150
	level.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(level)
	var bar := UiBar.create(Color(0.62, 0.34, 0.85), 18.0, UiTheme.FONT_SMALL)
	bar.name = "XpBar"
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.segments = 0
	var after_text := "MAX" if row["max"] else "%s / %s" % [UiTheme.format_int(int(row["into"])), UiTheme.format_int(int(row["needed"]))]
	bar.set_values(float(row["from"]), 1.0, after_text)
	bar.set_values(float(row["to"]), 1.0, after_text)
	line.add_child(bar)
	var gain := UiTheme.label("+%s XP" % UiTheme.format_int(int(row["xp_gained"])), UiTheme.GOLD_LABEL, UiTheme.FONT_LARGE - 2, UiTheme.GREEN)
	gain.custom_minimum_size.x = 150
	gain.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gain.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(gain)
	box.add_child(line)
	var rewards: Array = row["rewards"]
	if not rewards.is_empty():
		var text := UiTheme.label("New:  " + "  ·  ".join(rewards), &"", UiTheme.FONT_SMALL, UiTheme.GOLD_BRIGHT.lerp(UiTheme.TEXT, 0.35))
		text.name = "Rewards"
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size.x = 400
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(text)
	return box


## Sizes [member page_box] to the tallest page (the Damage Meter grows by a second row of Awards, the
## Summary by more hero rows ...). Hidden pages still know their minimum size.
func _fit_pages() -> void:
	page_box.custom_minimum_size = Vector2(0.0, maxf(maxf(summary_page.get_combined_minimum_size().y,
			meter_page.get_combined_minimum_size().y), maxf(leaderboard_page.get_combined_minimum_size().y,
			progress_page.get_combined_minimum_size().y if has_progress() else 0.0)))


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
		Audio.play_ui(&"ui_confirm")
		back_to_menu_requested.emit()
