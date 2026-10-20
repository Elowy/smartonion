class_name OnionPatchPage
extends MenuPage
## The Onion Patch (M9 PATCH, GDD 17): the main menu's meta page. A header with the Seeds wallet, the achievement points
## and the chosen title, five tabs – Classes, Seasonings, Heirlooms, Achievements, Wardrobe – and a status line that
## says what the last purchase did. Every player may drive it with their own PlayerSlot.input (or "anyone" from the
## title screen): ▲ ▼ ◀ ▶ move inside the tab, A buys / picks, LB / RB (Q / E) switch tabs, B goes back. Every
## purchase saves at once ([Meta]). With the dev profile of the automated runs (everything unlocked, no Seeds) the page
## opens and shows everything; buying simply is not affordable there. Input rules (driver, swallowed opening press):
## [MenuPage]; the tabs are [PatchTab]s.

enum Tab { CLASSES, SEASONINGS, HEIRLOOMS, ACHIEVEMENTS, WARDROBE }

const TAB_NAMES: Array[String] = ["Classes", "Seasonings", "Heirlooms", "Achievements", "Wardrobe"]
const PANEL_WIDTH := 1760.0
const CONTENT_HEIGHT := 620.0
const TITLE_SIZE := 46
const TAB_FONT := 26
const MESSAGE_GOOD := Color(0.62, 0.95, 0.5)
const MESSAGE_BAD := Color(1.0, 0.5, 0.4)

var tab: Tab = Tab.CLASSES
var tabs: Array[PatchTab] = []
var classes_tab: PatchClassesTab
var seasonings_tab: PatchSeasoningsTab
var heirlooms_tab: PatchHeirloomsTab
var achievements_tab: PatchAchievementsTab
var wardrobe_tab: PatchWardrobeTab
## The header: Seeds, achievement points, the chosen title.
var seeds_label: Label
var points_label: Label
var title_text_label: Label
## The status line under the tabs (the last purchase / refusal).
var message_label: Label

var _tab_labels: Array[Label] = []
var _tab_left: HBoxContainer
var _tab_right: HBoxContainer
var _tab_bar: HBoxContainer
var _content: MarginContainer
var _tab_skip := 0
var _q_down := false
var _e_down := false


static func create(dim_alpha: float = 0.55) -> OnionPatchPage:
	var p := OnionPatchPage.new()
	p.name = "OnionPatchPage"
	p._build(dim_alpha)
	return p


func _build(dim_alpha: float) -> void:
	_build_frame("The Onion Patch", PANEL_WIDTH, dim_alpha)
	column.add_theme_constant_override(&"separation", 6)
	title_label.add_theme_font_size_override(&"font_size", TITLE_SIZE)
	column.add_child(_make_header())
	_tab_bar = UiTheme.hbox(26)
	_tab_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_tab_bar)
	_tab_left = UiTheme.hbox(4)
	_tab_bar.add_child(_tab_left)
	for i in TAB_NAMES.size():
		var label := UiTheme.label(TAB_NAMES[i].to_upper(), UiTheme.HEADING, TAB_FONT, UiTheme.TEXT_DIM)
		label.name = "Tab_%s" % TAB_NAMES[i]
		_tab_bar.add_child(label)
		_tab_labels.append(label)
	_tab_right = UiTheme.hbox(4)
	_tab_bar.add_child(_tab_right)
	column.add_child(UiTheme.divider())
	_content = MarginContainer.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.custom_minimum_size = Vector2(0, CONTENT_HEIGHT)
	column.add_child(_content)
	classes_tab = PatchClassesTab.create()
	seasonings_tab = PatchSeasoningsTab.create()
	heirlooms_tab = PatchHeirloomsTab.create()
	achievements_tab = PatchAchievementsTab.create()
	wardrobe_tab = PatchWardrobeTab.create()
	tabs = [classes_tab, seasonings_tab, heirlooms_tab, achievements_tab, wardrobe_tab]
	for t in tabs:
		t.visible = false
		t.message_posted.connect(set_message)
		_content.add_child(t)
	message_label = UiTheme.centered_label(" ", &"", UiTheme.FONT_BODY, MESSAGE_GOOD)
	column.add_child(message_label)
	_finish_frame()
	Meta.seeds_changed.connect(_on_meta_changed)
	Meta.profile_replaced.connect(refresh)
	Meta.achievement_unlocked.connect(_on_achievement_unlocked)
	_apply_tab()


## Seeds, points and the title as one row.
func _make_header() -> HBoxContainer:
	var head := UiTheme.hbox(36)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	var seeds_box := UiTheme.hbox(8)
	seeds_box.add_child(_SeedIcon.new())
	seeds_label = UiTheme.label("", UiTheme.HEADING, 26, PatchTab.SEEDS_COLOR)
	seeds_box.add_child(seeds_label)
	head.add_child(seeds_box)
	var points_box := UiTheme.hbox(8)
	var crown := UiIcon.create(UiIcon.Kind.CROWN, Vector2(30, 26), UiTheme.GOLD)
	crown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	points_box.add_child(crown)
	points_label = UiTheme.label("", UiTheme.HEADING, 26, UiTheme.GOLD)
	points_box.add_child(points_label)
	head.add_child(points_box)
	title_text_label = UiTheme.label("", &"", UiTheme.FONT_BODY, UiTheme.TEXT)
	head.add_child(title_text_label)
	return head


# --- State -----------------------------------------------------------------------------------------

func _on_open() -> void:
	_tab_skip = 1
	_q_down = Input.is_physical_key_pressed(KEY_Q)
	_e_down = Input.is_physical_key_pressed(KEY_E)
	set_message("")
	refresh()
	tabs[tab].on_open()


## Redraws the header and the current tab (after a purchase, a profile change, opening).
func refresh() -> void:
	seeds_label.text = "Seeds  %s" % PatchTab.seeds_text(Meta.seeds())
	points_label.text = "%d points" % Meta.achievement_points()
	var id: StringName = Meta.profile.selected_title if Meta.profile != null else &""
	title_text_label.text = "Title: %s" % (PlayerTitles.name_of(id) if id != &"" else "none")
	if tabs.size() > tab:
		tabs[tab].refresh()
	_fill_prompts()


func set_message(text: String, good: bool = true) -> void:
	message_label.text = text if text != "" else " "
	message_label.add_theme_color_override(&"font_color", MESSAGE_GOOD if good else MESSAGE_BAD)
	_refresh_header()
	_fill_prompts()


func _refresh_header() -> void:
	if seeds_label == null:
		return
	seeds_label.text = "Seeds  %s" % PatchTab.seeds_text(Meta.seeds())
	points_label.text = "%d points" % Meta.achievement_points()
	var id: StringName = Meta.profile.selected_title if Meta.profile != null else &""
	title_text_label.text = "Title: %s" % (PlayerTitles.name_of(id) if id != &"" else "none")


func _on_meta_changed(_total: int, _delta: int) -> void:
	if is_inside_tree():
		_refresh_header()


func _on_achievement_unlocked(_id: StringName) -> void:
	if is_inside_tree():
		refresh()


func current() -> PatchTab:
	return tabs[tab]


## Shows [param value]. Out of range is ignored.
func set_tab(value: Tab) -> void:
	if value < 0 or value >= tabs.size():
		return
	tab = value
	_apply_tab()
	tabs[tab].on_open()
	_fill_prompts()


## Moves to the next / previous tab (wraps).
func switch_tab(step: int) -> void:
	if step == 0:
		return
	Audio.play_ui(&"ui_move")
	set_tab(wrapi(tab + step, 0, tabs.size()) as Tab)


func _apply_tab() -> void:
	for i in tabs.size():
		tabs[i].visible = i == tab
		var on := i == tab
		_tab_labels[i].add_theme_color_override(&"font_color", UiTheme.GOLD_BRIGHT if on else UiTheme.TEXT_DIM)
		_tab_labels[i].add_theme_constant_override(&"outline_size", 6 if on else 0)
	_fill_tab_glyphs()


func _fill_tab_glyphs() -> void:
	for box in [_tab_left, _tab_right]:
		for c in (box as Control).get_children():
			(box as Control).remove_child(c)
			c.queue_free()
	for part: Variant in _glyphs(PlayerInput.Pad.LB):
		_add_part(_tab_left, part)
	for part: Variant in _glyphs(PlayerInput.Pad.RB):
		_add_part(_tab_right, part)


func _add_part(box: HBoxContainer, part: Variant) -> void:
	if part is Control:
		(part as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(part as Control)
	else:
		box.add_child(UiTheme.label(str(part), &"", UiTheme.FONT_SMALL, UiTheme.TEXT_DIM))


# --- Input (MenuPage hooks) ----------------------------------------------------------------------

func _on_nav(dir: Vector2i) -> void:
	tabs[tab].on_nav(dir)
	_fill_prompts()


func _on_accept() -> void:
	tabs[tab].on_accept()
	_refresh_header()
	_fill_prompts()


func _process(delta: float) -> void:
	super._process(delta)
	if not is_visible_in_tree():
		return
	if _tab_skip > 0:
		_tab_skip -= 1
		return
	var step := _tab_step()
	if step != 0:
		switch_tab(step)


## LB / RB of the driver, or – when anyone drives the page – any controller's shoulders or the Q / E keys: -1, 0, +1.
func _tab_step() -> int:
	var driver := driver_slot()
	if driver != null:
		if driver.input.just_pressed(PlayerInput.Pad.LB):
			return -1
		if driver.input.just_pressed(PlayerInput.Pad.RB):
			return 1
		return 0
	var q := Input.is_physical_key_pressed(KEY_Q)
	var e := Input.is_physical_key_pressed(KEY_E)
	var step := 0
	if (q and not _q_down) or pads.any_just_pressed(JOY_BUTTON_LEFT_SHOULDER):
		step = -1
	elif (e and not _e_down) or pads.any_just_pressed(JOY_BUTTON_RIGHT_SHOULDER):
		step = 1
	_q_down = q
	_e_down = e
	return step


func _prompt_items() -> Array:
	var items: Array = []
	if tab < tabs.size():
		var action := tabs[tab].action_text()
		if action != "":
			items.append(_glyphs(PlayerInput.Pad.A) + [action])
	items.append([UiGlyph.nav(28.0), UiGlyph.nav(28.0, true), "Move"])
	items.append(_glyphs(PlayerInput.Pad.LB) + _glyphs(PlayerInput.Pad.RB) + ["Tab"])
	items.append(_glyphs(PlayerInput.Pad.B) + ["Back"])
	return items


## A small seed: a teardrop with a highlight, drawn in code.
class _SeedIcon extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(22, 30)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var c := size * 0.5
		var pts := PackedVector2Array()
		for i in 24:
			var a := TAU * float(i) / 24.0
			var r := Vector2(cos(a) * size.x * 0.4, sin(a) * size.y * 0.46)
			# Pointed tip at the top.
			if sin(a) < 0.0:
				r.x *= 1.0 + sin(a) * 0.55
			pts.append(c + r)
		draw_colored_polygon(pts, Color(0.55, 0.78, 0.25))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.24, 0.4, 0.1), 2.0)
		draw_line(c + Vector2(-size.x * 0.1, -size.y * 0.25), c + Vector2(-size.x * 0.1, size.y * 0.2), Color(0.85, 0.97, 0.6, 0.8), 2.0)
