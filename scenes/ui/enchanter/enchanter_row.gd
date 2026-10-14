class_name EnchanterRow
extends PanelContainer
## One line of the Enchanter tab's detail (GDD 5.7, 12): an enchant of the selected item – its rank
## as a roman numeral I-V (gold; violet at the top rank, V), its name and the green tooltip text at
## that rank – or the "Imbue" row (a free enchant slot: "+ New enchant"). The selected row has the
## player's colour as its border; while A / X is held on an expensive action it fills up in that
## colour ([member hold_progress], like the Trainer's rows).

const RANK_WIDTH := 34.0
const NAME_FONT := 18
const TEXT_FONT := 15
const MAX_RANK_COLOR := Color(0.78, 0.66, 1.0)
const FREE_TEXT := "Free enchant slot"
const IMBUE_TEXT := "Imbue: add a new enchant"

## Index into ItemInstance.enchants, -1 for the Imbue row.
var enchant_index := -1
var roll: EnchantRoll
var rank_label: Label
var name_label: Label
var text_label: Label
var selected := false
var accent := UiTheme.GOLD
## 0..1 while A / X is held on this row.
var hold_progress := 0.0

var _style: StyleBoxFlat


## A row for enchant [param index] of an item ([param p_roll]) or, with index -1 and no roll, the
## Imbue row.
static func create(index: int, p_roll: EnchantRoll) -> EnchanterRow:
	var r := EnchanterRow.new()
	r.enchant_index = index
	r.roll = p_roll
	r.name = "ImbueRow" if index < 0 else "EnchantRow%d" % index
	r._build()
	return r


func is_imbue() -> bool:
	return enchant_index < 0


func set_selected(on: bool, color: Color = UiTheme.GOLD) -> void:
	selected = on
	accent = color
	_update_style()


func set_hold_progress(p: float) -> void:
	var v := clampf(p, 0.0, 1.0)
	if not is_equal_approx(v, hold_progress):
		hold_progress = v
		queue_redraw()


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style = StyleBoxFlat.new()
	_style.set_corner_radius_all(5)
	_style.content_margin_left = 6
	_style.content_margin_right = 8
	_style.content_margin_top = 2
	_style.content_margin_bottom = 3
	_style.anti_aliasing = true
	add_theme_stylebox_override(&"panel", _style)
	var row := UiTheme.hbox(6)
	add_child(row)
	rank_label = UiTheme.centered_label("", &"", 22, UiTheme.GOLD)
	rank_label.add_theme_font_override(&"font", UiTheme.bold_font())
	rank_label.custom_minimum_size = Vector2(RANK_WIDTH, 0)
	rank_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(rank_label)
	var texts := UiTheme.vbox(0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(texts)
	name_label = UiTheme.label("", &"", NAME_FONT, UiTheme.TEXT)
	name_label.add_theme_font_override(&"font", UiTheme.bold_font())
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.custom_minimum_size.x = 40
	texts.add_child(name_label)
	text_label = UiTheme.wrapped_label("", &"", TEXT_FONT, ItemTooltip.ENCHANT_GREEN)
	text_label.max_lines_visible = 2
	text_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text_label.add_theme_constant_override(&"line_spacing", -2)
	texts.add_child(text_label)
	if enchant_index < 0:
		rank_label.text = "+"
		rank_label.add_theme_color_override(&"font_color", UiTheme.GREEN)
		name_label.text = IMBUE_TEXT
		text_label.text = FREE_TEXT
		text_label.add_theme_color_override(&"font_color", UiTheme.TEXT_DIM)
	else:
		fill(roll)
	_update_style()


## Shows [param p_roll] (the enchant at this row changed).
func fill(p_roll: EnchantRoll) -> void:
	roll = p_roll
	if roll == null or roll.enchant == null:
		return
	rank_label.text = roll.rank_label()
	rank_label.add_theme_color_override(&"font_color",
		MAX_RANK_COLOR if roll.rank >= EnchantData.MAX_RANK else UiTheme.GOLD)
	var e := roll.enchant
	name_label.text = e.prefix if e.prefix != "" else String(e.id).capitalize()
	text_label.text = ItemTooltip.enchant_text(roll)


func _update_style() -> void:
	if _style == null:
		return
	if selected:
		_style.bg_color = Color(0.3, 0.21, 0.1, 0.95)
		_style.border_color = accent
		_style.set_border_width_all(2)
	else:
		_style.bg_color = Color(0.05, 0.045, 0.04, 0.55)
		_style.border_color = Color(0.3, 0.26, 0.2, 0.6)
		_style.set_border_width_all(1)
	queue_redraw()


func _draw() -> void:
	if hold_progress <= 0.0:
		return
	var r := Rect2(Vector2(2, 2), Vector2((size.x - 4.0) * hold_progress, size.y - 4.0))
	draw_rect(r, Color(accent, 0.38))
	draw_rect(Rect2(Vector2(r.end.x - 2.0, 2.0), Vector2(2.0, size.y - 4.0)), Color(accent.lightened(0.5), 0.9))
