class_name PatchHeirloomsTab
extends PatchTab
## The Heirlooms tab of The Onion Patch: the ten Heirlooms as rows on the left (slot, name, rank dots or a lock) and a
## detail pane on the right – the numbers at wave 1 / 10 / 25 for a class (◀ ▶ change the class the preview is for),
## the rank 3 / rank 5 perks (green once reached), how the Heirloom is obtained, and the rank-up: A buys the next rank
## with Seeds (R2 60, R3 120, R4 240, R5 480; [method Meta.rank_up_heirloom], saved at once). An Heirloom the profile
## does not own yet only shows its obtain hint.

const ROW_HEIGHT := 54.0
const SLOT_BADGE_COLOR := Color(0.55, 0.62, 0.78)

var cursor := 0
## The class the stat preview is for (an index into Db.class_ids; starts on the gift class of the selected Heirloom).
var preview_index := 0
var rows: Array[PanelContainer] = []
var entries: Array[HeirloomData] = []

var _list: VBoxContainer
var _name: Label
var _sub: Label
var _dots_slot: HBoxContainer
var _owned_label: Label
var _preview_head: Label
var _preview: Label
var _perk3: Label
var _perk5: Label
var _obtain: Label
var _flavor: Label
var _rank_up: Label
var _rank_reason: Label


static func create() -> PatchHeirloomsTab:
	var t := PatchHeirloomsTab.new()
	t.name = "HeirloomsTab"
	t._build()
	return t


func tab_name() -> String:
	return "Heirlooms"


func _build() -> void:
	var body := UiTheme.hbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(body)
	_list = UiTheme.vbox(4)
	_list.custom_minimum_size.x = 620
	body.add_child(_list)
	var detail := inset_panel()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(detail)
	var box := UiTheme.vbox(5)
	detail.add_child(box)
	_name = clipped_label("", 34, UiTheme.GOLD_BRIGHT, UiTheme.HEADING)
	box.add_child(_name)
	_sub = clipped_label("", UiTheme.FONT_SMALL, UiTheme.TEXT_DIM)
	box.add_child(_sub)
	var rank_row := UiTheme.hbox(12)
	_dots_slot = UiTheme.hbox(0)
	rank_row.add_child(_dots_slot)
	_owned_label = UiTheme.label("", &"", UiTheme.FONT_SMALL, UiTheme.TEXT)
	rank_row.add_child(_owned_label)
	box.add_child(rank_row)
	box.add_child(UiTheme.divider())
	_preview_head = UiTheme.label("", &"", UiTheme.FONT_SMALL, UiTheme.GOLD)
	box.add_child(_preview_head)
	_preview = UiTheme.wrapped_label("", &"", UiTheme.FONT_SMALL, UiTheme.TEXT)
	_preview.custom_minimum_size.y = 84
	_preview.max_lines_visible = 3
	box.add_child(_preview)
	_perk3 = UiTheme.wrapped_label("", &"", UiTheme.FONT_SMALL, UiTheme.TEXT_DIM)
	_perk3.custom_minimum_size.y = 28
	_perk3.max_lines_visible = 1
	box.add_child(_perk3)
	_perk5 = UiTheme.wrapped_label("", &"", UiTheme.FONT_SMALL, UiTheme.TEXT_DIM)
	_perk5.custom_minimum_size.y = 56
	_perk5.max_lines_visible = 2
	box.add_child(_perk5)
	_obtain = UiTheme.wrapped_label("", &"", UiTheme.FONT_SMALL, UiTheme.TEXT)
	_obtain.max_lines_visible = 1
	box.add_child(_obtain)
	_flavor = UiTheme.wrapped_label("", &"", UiTheme.FONT_SMALL - 2, UiTheme.TEXT_DIM)
	_flavor.max_lines_visible = 2
	_flavor.custom_minimum_size.y = 44
	box.add_child(_flavor)
	box.add_child(UiTheme.spacer(true))
	_rank_up = UiTheme.label("", UiTheme.HEADING, 26, SEEDS_COLOR)
	box.add_child(_rank_up)
	_rank_reason = UiTheme.label("", &"", UiTheme.FONT_SMALL, UiTheme.TEXT_DIM)
	box.add_child(_rank_reason)


# --- State -----------------------------------------------------------------------------------------

func on_open() -> void:
	entries.clear()
	for id in Db.heirloom_ids:
		entries.append(Db.heirlooms[id])
	cursor = clampi(cursor, 0, maxi(entries.size() - 1, 0))
	_sync_preview_class()
	refresh()


func selected() -> HeirloomData:
	return entries[cursor] if cursor >= 0 and cursor < entries.size() else null


func preview_class() -> ClassData:
	return Db.get_class_data(Db.class_ids[preview_index]) if preview_index >= 0 and preview_index < Db.class_ids.size() else null


## The preview starts on the class that gifts the Heirloom (the Mage for the Sprout Cap).
func _sync_preview_class() -> void:
	var h := selected()
	if h != null:
		var at := Db.class_ids.find(Heirlooms.preview_class(h).id)
		if at >= 0:
			preview_index = at


func on_nav(dir: Vector2i) -> void:
	if dir.y != 0:
		cursor = wrap_index(cursor, dir.y, entries.size())
		_sync_preview_class()
		Audio.play_ui(&"ui_move")
		refresh()
	elif dir.x != 0:
		preview_index = wrap_index(preview_index, dir.x, Db.class_ids.size())
		Audio.play_ui(&"ui_move")
		refresh()


func action_text() -> String:
	var h := selected()
	if h == null or Meta.heirloom_rank_price(h.id) <= 0:
		return ""
	return "Rank up"


func on_accept() -> void:
	var h := selected()
	if h == null:
		return
	var reason := Meta.heirloom_rank_up_reason(h.id)
	if reason != "":
		Audio.play_ui(&"ui_error")
		post("%s: %s" % [h.display_name, reason], false)
		return
	var price := Meta.heirloom_rank_price(h.id)
	if Meta.rank_up_heirloom(h.id):
		Audio.play_ui(&"ui_confirm")
		post("%s is rank %d now (%d Seeds)" % [h.display_name, Meta.heirloom_rank(h.id), price])
	refresh()


# --- Drawing ---------------------------------------------------------------------------------------

func refresh() -> void:
	if entries.is_empty():
		for id in Db.heirloom_ids:
			entries.append(Db.heirlooms[id])
	clear(_list)
	rows.clear()
	for i in entries.size():
		var row := _make_row(entries[i], i == cursor)
		_list.add_child(row)
		rows.append(row)
	_fill_detail()


func _make_row(h: HeirloomData, selected_row: bool) -> PanelContainer:
	var rank := Meta.heirloom_rank(h.id)
	var owned := rank > 0
	var panel := row_panel(selected_row, ROW_HEIGHT)
	panel.name = "Row_%s" % h.id
	var line := UiTheme.hbox(12)
	panel.add_child(line)
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.custom_minimum_size = Vector2(96, 30)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = Color(SLOT_BADGE_COLOR.r, SLOT_BADGE_COLOR.g, SLOT_BADGE_COLOR.b, 0.28) if owned else Color(0.15, 0.14, 0.13)
	style.border_color = SLOT_BADGE_COLOR if owned else Color(0.3, 0.28, 0.26)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	badge.add_theme_stylebox_override(&"panel", style)
	badge.add_child(UiTheme.centered_label(String(Items.SLOT_NAMES.get(h.slot_type, "")).to_upper(), &"", 12, SLOT_BADGE_COLOR if owned else LOCKED_COLOR))
	line.add_child(badge)
	var name_label := clipped_label(h.display_name, UiTheme.FONT_BODY, UiTheme.TEXT if owned else LOCKED_COLOR)
	name_label.name = "Name"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(name_label)
	if owned:
		var dots := RankDots.create(rank, HeirloomData.MAX_RANK, 7.0)
		dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(dots)
	else:
		line.add_child(UiIcon.create(UiIcon.Kind.LOCK, Vector2(24, 24), Color(0.6, 0.55, 0.5)))
	return panel


func _fill_detail() -> void:
	var h := selected()
	if h == null:
		return
	var cls := preview_class()
	var rank := Meta.heirloom_rank(h.id)
	var owned := rank > 0
	var shown_rank := maxi(rank, 1)
	_name.text = h.display_name
	_name.add_theme_color_override(&"font_color", UiTheme.GOLD_BRIGHT if owned else LOCKED_COLOR)
	var armor := ""
	if h.armor_rule == HeirloomData.RULE_HERO:
		armor = "  ·  armor of the hero"
	elif h.armor_rule == HeirloomData.RULE_WEAPON:
		armor = "  ·  same type as the hero's starting weapon"
	_sub.text = "%s%s  ·  bound to its hero" % [Items.SLOT_NAMES.get(h.slot_type, ""), armor]
	clear(_dots_slot)
	var dots := RankDots.create(rank, HeirloomData.MAX_RANK, 9.0)
	dots.name = "Dots"
	_dots_slot.add_child(dots)
	_owned_label.text = "Rank %d of %d" % [rank, HeirloomData.MAX_RANK] if owned else "Not owned"
	_owned_label.add_theme_color_override(&"font_color", UiTheme.TEXT if owned else ERROR_COLOR)
	if h.is_weapon():
		_preview_head.text = "Damage of the starting weapon at rank %d (waves 1 / 10 / 25)" % shown_rank
	else:
		_preview_head.text = "For a %s at rank %d" % [cls.display_name if cls != null else "hero", shown_rank]
	var lines: Array[String] = []
	for w in Heirlooms.PREVIEW_WAVES:
		lines.append("Wave %d:  %s" % [w, Heirlooms.preview_text(h, cls, w, shown_rank)])
	_preview.text = "\n".join(PackedStringArray(lines))
	_perk3.text = "Rank %d:  %s" % [HeirloomData.PERK3_RANK, h.perk3_text]
	_perk3.add_theme_color_override(&"font_color", UiTheme.GREEN if rank >= HeirloomData.PERK3_RANK else UiTheme.TEXT_DIM)
	_perk5.text = "Rank %d:  %s" % [HeirloomData.PERK5_RANK, h.perk5_text]
	_perk5.add_theme_color_override(&"font_color", UiTheme.GREEN if rank >= HeirloomData.PERK5_RANK else UiTheme.TEXT_DIM)
	_obtain.text = "Obtained: %s" % Heirlooms.obtain_text(h)
	_obtain.add_theme_color_override(&"font_color", UiTheme.TEXT if not owned else UiTheme.TEXT_DIM)
	_flavor.text = "\"%s\"" % h.flavor if h.flavor != "" else ""
	var price := Meta.heirloom_rank_price(h.id)
	if not owned:
		_rank_up.text = "Not owned yet"
		_rank_up.add_theme_color_override(&"font_color", ERROR_COLOR)
		_rank_reason.text = "Earn it first: %s" % Heirlooms.obtain_text(h)
	elif price <= 0:
		_rank_up.text = "Top rank reached"
		_rank_up.add_theme_color_override(&"font_color", UiTheme.GOLD)
		_rank_reason.text = "Nothing more to buy for this Heirloom."
	else:
		_rank_up.text = "Rank %d  ·  %d Seeds" % [rank + 1, price]
		var reason := Meta.heirloom_rank_up_reason(h.id)
		_rank_up.add_theme_color_override(&"font_color", SEEDS_COLOR if reason == "" else ERROR_COLOR)
		_rank_reason.text = "Press A to buy it." if reason == "" else "%s (you have %d Seeds)." % [reason, Meta.seeds()]
