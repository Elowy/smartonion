class_name TrainerRow
extends PanelContainer
## One line of the Trainer list (GDD 6.3, TrainerTab): an AbilityRunner slot with its slot tag
## (the player's RT / LT / RB / LB button – keyboard LMB / RMB / Q / E – or a gear for the
## auto-cast slots), the AbilityIcon (without a rank mark: the rank column right next to it
## shows it), the name, the rank as a roman numeral (I–V, orange once specialised) and the
## Trainer price in the shared wallet's gold (red while the wallet cannot pay it,
## "MAX" at Rank V, "Choose" while the Rank V specialisation is still open). An empty learned
## slot reads "Learn abilities on level-up". While A is held on an expensive rank the row fills
## up in the player's colour ([member hold_progress]). A rank the player pinged (GDD 10, R3 /
## Tab: "the team should save gold for this") shows a "Wants" tag in their colour before the
## rank ([method set_ping]).

const HEIGHT := 37.0
const ICON_SIZE := 32.0
const TAG_WIDTH := 40.0
const RANK_WIDTH := 32.0
const PRICE_WIDTH := 62.0
const NAME_FONT := 18
const TAG_FONT := 15
const EMPTY_TEXT := "Learn abilities on level-up"
const SPEC_TEXT := "Choose"
const MAX_TEXT := "MAX"
const WANT_TEXT := "Wants"
const WANT_FONT := 14

var slot_index := -1
var ability: AbilityData
var icon: AbilityIcon
var name_label: Label
var rank_label: Label
var price_label: Label
var coin: UiIcon
## 0..1 while A is held on this row's rank (drawn as a fill behind the content).
var hold_progress := 0.0
## The player pinged this rank (the [member want_tag] shows).
var pinged := false
var want_tag: WantTag
var selected := false
var accent := UiTheme.GOLD

var _tag_holder: CenterContainer
var _tag_key := ""
var _style: StyleBoxFlat


## Draws the auto-cast gear tag.
class GearTag extends Control:
	func _draw() -> void:
		AbilityIcon.draw_gear(self, size * 0.5, minf(size.x, size.y) * 0.42, Color(0.86, 0.8, 0.66))


## A button prompt drawn like the HUD's AbilityIcon pill: a dark pill with the pad button's
## name, or a light key cap for the keyboard ("LMB", "Q" ...). Bigger text than UiGlyph's pills,
## so it stays readable in the scaled-down market panels.
class PromptTag extends Control:
	var text := ""
	var keyboard := false
	var font_size := 15

	static func create(p_text: String, p_keyboard: bool, height: float = 22.0, p_font_size: int = 15) -> PromptTag:
		var t := PromptTag.new()
		t.text = p_text
		t.keyboard = p_keyboard
		t.font_size = p_font_size
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var w := UiTheme.bold_font().get_string_size(p_text, HORIZONTAL_ALIGNMENT_LEFT, -1, p_font_size).x
		t.custom_minimum_size = Vector2(maxf(height + 4.0, w + 12.0), height)
		return t

	func _draw() -> void:
		var fs := font_size
		var r := Rect2(Vector2.ZERO, size)
		var box := StyleBoxFlat.new()
		box.anti_aliasing = true
		box.set_border_width_all(2)
		if keyboard:
			box.bg_color = Color(0.82, 0.78, 0.7)
			box.border_color = UiGlyph.DARK
			box.border_width_bottom = 3
			box.set_corner_radius_all(4)
		else:
			box.bg_color = Color(0.24, 0.23, 0.22)
			box.border_color = Color(UiTheme.GOLD_DARK, 0.95)
			box.set_corner_radius_all(int(size.y * 0.5))
		draw_style_box(box, r)
		var font := UiTheme.bold_font()
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := Vector2((size.x - w) * 0.5, size.y * 0.5 + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5 - (1.0 if keyboard else 0.0))
		if keyboard:
			draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiGlyph.DARK)
		else:
			draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.7))
			draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT)


## The ping marker: a small "Wants" tag in the player's colour (like the shop's "P2 wants").
class WantTag extends Control:
	var color := UiTheme.GOLD

	static func create() -> WantTag:
		var t := WantTag.new()
		t.name = "WantTag"
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var w := UiTheme.bold_font().get_string_size(WANT_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, WANT_FONT).x
		t.custom_minimum_size = Vector2(ceilf(w + 12.0), 20.0)
		t.visible = false
		return t

	func set_color(c: Color) -> void:
		color = c
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(color.darkened(0.55), 0.92))
		draw_rect(r, color, false, 2.0)
		var font := UiTheme.bold_font()
		var pos := Vector2(6.0, size.y * 0.5 + (font.get_ascent(WANT_FONT) - font.get_descent(WANT_FONT)) * 0.5)
		draw_string_outline(font, pos, WANT_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, WANT_FONT, 4, UiTheme.OUTLINE)
		draw_string(font, pos, WANT_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, WANT_FONT, Color.WHITE)


static func create(p_slot_index: int) -> TrainerRow:
	var r := TrainerRow.new()
	r.slot_index = p_slot_index
	r.name = "TrainerRow%d" % p_slot_index
	r._build()
	return r


## Kind of slot [param index]: "Core", "Active" or "Auto-cast".
static func kind_name(index: int) -> String:
	if index < AbilityRunner.CORE_SLOTS:
		return "Core"
	if index < AbilityRunner.INPUT_SLOTS:
		return "Active"
	return "Auto-cast"


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, HEIGHT)
	_style = StyleBoxFlat.new()
	_style.set_corner_radius_all(5)
	_style.content_margin_left = 4
	_style.content_margin_right = 8
	_style.content_margin_top = 2
	_style.content_margin_bottom = 2
	_style.anti_aliasing = true
	add_theme_stylebox_override(&"panel", _style)
	var row := UiTheme.hbox(5)
	add_child(row)
	_tag_holder = CenterContainer.new()
	_tag_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag_holder.custom_minimum_size = Vector2(TAG_WIDTH, 0)
	row.add_child(_tag_holder)
	icon = AbilityIcon.create(ICON_SIZE, false)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.show_prompt = false
	row.add_child(icon)
	name_label = UiTheme.label("", &"", NAME_FONT, UiTheme.TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.custom_minimum_size.x = 40
	row.add_child(name_label)
	want_tag = WantTag.create()
	row.add_child(want_tag)
	rank_label = UiTheme.centered_label("", &"", 20, UiTheme.GOLD)
	rank_label.add_theme_font_override(&"font", UiTheme.bold_font())
	rank_label.custom_minimum_size = Vector2(RANK_WIDTH, 0)
	rank_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(rank_label)
	var price := UiTheme.hbox(4)
	price.custom_minimum_size = Vector2(PRICE_WIDTH, 0)
	price.alignment = BoxContainer.ALIGNMENT_END
	price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin = UiIcon.create(UiIcon.Kind.COIN, Vector2(18, 18))
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	price.add_child(coin)
	price_label = UiTheme.label("", &"", UiTheme.FONT_SMALL, UiTheme.GOLD)
	price_label.add_theme_font_override(&"font", UiTheme.bold_font())
	price.add_child(price_label)
	row.add_child(price)
	_update_style()


## Fills the row. [param p_rank] 1..5, [param price] 0 at max rank, [param affordable] colours
## the price, [param needs_spec] shows "Choose" instead of a price, [param spec_chosen] turns
## the rank orange. The icon carries no rank of its own (rank 0): a corner numeral on the
## 32 px icon would only hide its glyph next to [member rank_label].
func show_ability(a: AbilityData, p_rank: int, price: int, affordable: bool, needs_spec: bool, spec_chosen: bool) -> void:
	ability = a
	icon.set_ability(a)
	_update_style()
	if a == null:
		name_label.text = EMPTY_TEXT
		name_label.add_theme_font_size_override(&"font_size", 16)
		name_label.add_theme_color_override(&"font_color", Color(0.55, 0.52, 0.48))
		rank_label.text = ""
		price_label.text = ""
		coin.visible = false
		return
	icon.set_state(0.0, 0.0, true)
	name_label.text = a.display_name
	name_label.add_theme_font_size_override(&"font_size", NAME_FONT)
	name_label.add_theme_color_override(&"font_color", UiTheme.TEXT)
	rank_label.text = AbilityIcon.roman(p_rank)
	rank_label.add_theme_color_override(&"font_color", AbilityIcon.RANK_SPEC_COLOR if spec_chosen else UiTheme.GOLD)
	if needs_spec:
		price_label.text = SPEC_TEXT
		price_label.add_theme_color_override(&"font_color", AbilityIcon.RANK_SPEC_COLOR)
		coin.visible = false
	elif price <= 0:
		price_label.text = MAX_TEXT
		price_label.add_theme_color_override(&"font_color", UiTheme.GOLD_DARK.lightened(0.25))
		coin.visible = false
	else:
		price_label.text = UiTheme.format_int(price)
		price_label.add_theme_color_override(&"font_color", UiTheme.GOLD if affordable else UiTheme.RED)
		coin.visible = true


## The slot tag: the button prompt of [param input]'s device for slots 0..3, a gear for 4..7.
func set_tag(input: PlayerInput) -> void:
	var key := "gear"
	if slot_index < AbilityRunner.INPUT_SLOTS:
		key = "%s:%s" % [AbilityBar.prompt_text(input, slot_index), input is KeyboardInput]
	if key == _tag_key:
		return
	_tag_key = key
	for c in _tag_holder.get_children():
		_tag_holder.remove_child(c)
		c.queue_free()
	if slot_index >= AbilityRunner.INPUT_SLOTS:
		var gear := GearTag.new()
		gear.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gear.custom_minimum_size = Vector2(20, 20)
		_tag_holder.add_child(gear)
	else:
		_tag_holder.add_child(PromptTag.create(AbilityBar.prompt_text(input, slot_index), input is KeyboardInput, 22.0, TAG_FONT))


## Shows / hides the "Wants" tag in [param color] (the pinging player's colour).
func set_ping(on: bool, color: Color = UiTheme.GOLD) -> void:
	pinged = on
	want_tag.visible = on
	if on:
		want_tag.set_color(color)


func set_selected(on: bool, color: Color = UiTheme.GOLD) -> void:
	selected = on
	accent = color
	_update_style()


func set_hold_progress(p: float) -> void:
	var v := clampf(p, 0.0, 1.0)
	if not is_equal_approx(v, hold_progress):
		hold_progress = v
		queue_redraw()


func is_empty() -> bool:
	return ability == null


func _update_style() -> void:
	if selected:
		_style.bg_color = Color(0.3, 0.21, 0.1, 0.95)
		_style.border_color = accent
		_style.set_border_width_all(2)
	else:
		_style.bg_color = Color(0.05, 0.045, 0.04, 0.55) if ability != null else Color(0.05, 0.045, 0.04, 0.3)
		_style.border_color = Color(0.3, 0.26, 0.2, 0.6)
		_style.set_border_width_all(1)
	queue_redraw()


func _draw() -> void:
	if hold_progress <= 0.0:
		return
	var r := Rect2(Vector2(2, 2), Vector2((size.x - 4.0) * hold_progress, size.y - 4.0))
	draw_rect(r, Color(accent, 0.38))
	draw_rect(Rect2(Vector2(r.end.x - 2.0, 2.0), Vector2(2.0, size.y - 4.0)), Color(accent.lightened(0.5), 0.9))
