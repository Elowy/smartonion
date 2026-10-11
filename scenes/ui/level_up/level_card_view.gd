class_name LevelCardView
extends Control
## One level-up card (GDD 6.1) in a player's LevelUpPanel, drawn in code:
##  - ability cards: a ribbon ("New Active" / "New Auto-cast" in green, "Rank II -> III" in
##    gold), the AbilityIcon, the name in the ability's colour, school + cooldown (or cost),
##    the rank's change (AbilityRanks.rank_text, green) for rank-ups, and the description
##    filled with the ability's params (AbilityIcon.format_description) – for a rank-up the
##    params of the next rank. A new ability whose slots are all taken carries a red
##    "Slots full – replaces one" strip.
##  - stat cards: a ribbon and a gem in the Items rarity colour, "<Rarity> Training" and the
##    stat lines (LevelCard.lines).
## Selected (the player's cursor): lifted, border and glow in the player's colour.

const CARD_SIZE := Vector2(172, 344)
const ICON_SIZE := 56.0
const RIBBON_HEIGHT := 28.0
const LIFT := 8.0
const PAD := 9.0
const NAME_FONT := 20
const INFO_FONT := 16
const TEXT_FONT := 17
const STAT_FONT := 21
const NEW_COLOR := Color(0.2, 0.55, 0.15)
const RANK_COLOR := Color(0.62, 0.45, 0.1)
const WARN_COLOR := Color(0.62, 0.12, 0.08)
const RANK_TEXT_COLOR := Color(0.5, 0.95, 0.42)

var card: LevelCard
var selected := false
## Player colour of the selection border / glow.
var cursor_color := UiTheme.GOLD
## The new ability needs a slot of its kind and they are all taken.
var replaces := false
var ribbon_text := ""
var accent := UiTheme.GOLD_BORDER

var name_label: Label
var info_label: Label
var rank_label: Label
var text_label: Label
var warning_label: Label

var _body: Control
var _content: VBoxContainer
var _icon_holder: CenterContainer
var _icon: AbilityIcon
var _gem: Gem
var _ribbon_color := RANK_COLOR
var _dim := false


static func create() -> LevelCardView:
	var v := LevelCardView.new()
	v.custom_minimum_size = CARD_SIZE
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v._build()
	return v


# --- Text (static: tests and the panel's summaries use them) ---------------------------

## "New Active", "New Auto-cast", "Rank II -> III" or "Rare" (stat cards).
static func kind_text(c: LevelCard, runner: AbilityRunner) -> String:
	if c == null:
		return ""
	match c.kind:
		LevelCard.Kind.NEW_ABILITY:
			return "New Auto-cast" if c.ability.kind == AbilityData.Kind.AUTO else "New Active"
		LevelCard.Kind.RANK_UP:
			var rank := runner.rank_of(c.ability.id) if runner != null else 1
			return "Rank %s -> %s" % [LevelCard.roman(rank), LevelCard.roman(rank + 1)]
	return Items.RARITY_NAMES[clampi(c.rarity, 0, Items.RARITY_NAMES.size() - 1)]


## The params the card's text shows: the ability as it would be after the pick (a new one at
## Rank I via runner.params_for, a rank-up at the next rank with the item mods).
static func card_params(c: LevelCard, runner: AbilityRunner) -> Dictionary:
	if c == null or c.ability == null:
		return {}
	if runner == null:
		return c.ability.params
	if c.kind == LevelCard.Kind.RANK_UP and runner.knows(c.ability.id):
		return next_rank_params(runner, c.ability)
	return runner.params_for(c.ability)


## [param ability]'s params one rank up: what AbilityRunner.params_for composes (base
## cooldown / cost / charges / power + params, then the rank's mods, then the item mods) at
## rank + 1 with the current specialisation.
static func next_rank_params(runner: AbilityRunner, ability: AbilityData) -> Dictionary:
	var base := {"cooldown": ability.cooldown, "cost": ability.cost, "charges": 1, "power": 1.0}
	base.merge(ability.params, true)
	var rank := mini(runner.rank_of(ability.id) + 1, AbilityRanks.MAX_RANK)
	var ranked := AbilityRunner.apply_mods(base, AbilityRanks.mods_for(ability, rank, runner.spec_of(ability.id)))
	var mods: Dictionary = runner.player.ability_mods(ability.id) if runner.player != null else {}
	return AbilityRunner.apply_mods(ranked, mods)


## "Fire · 8 s cooldown", "Physical · 40 Rage", "Holy · 30 Mana · 12 s cooldown"; a rank-up
## that shortens the cooldown shows "8 -> 7.2 s cooldown".
static func info_text(c: LevelCard, runner: AbilityRunner) -> String:
	if c == null or c.ability == null:
		return "Permanent stats"
	var a := c.ability
	var params := card_params(c, runner)
	var parts: Array[String] = [String(a.school).capitalize()]
	var cost := float(params.get("cost", a.cost))
	if a.resource != &"" and cost > 0.0:
		parts.append("%s %s" % [AbilityIcon.format_number(cost), UiTheme.resource_name(a.resource)])
	var cd := float(params.get("cooldown", a.cooldown))
	if cd > 0.0:
		var now := cd
		if c.kind == LevelCard.Kind.RANK_UP and runner != null and runner.knows(a.id):
			now = float(runner.params_for(a).get("cooldown", a.cooldown))
		if not is_equal_approx(now, cd):
			parts.append("%s -> %s s cooldown" % [AbilityIcon.format_number(now), AbilityIcon.format_number(cd)])
		else:
			parts.append("%s s cooldown" % AbilityIcon.format_number(cd))
	return " · ".join(parts)


## The card body: the filled description (ability cards) or the stat lines (stat cards).
static func body_text(c: LevelCard, runner: AbilityRunner) -> String:
	if c == null:
		return ""
	if c.kind == LevelCard.Kind.STAT:
		return "\n".join(c.lines(runner))
	return AbilityIcon.format_description(c.ability, card_params(c, runner))


## Rank-up cards: what the next rank adds (AbilityRanks.rank_text); Rank V names the two
## specialisations. "" for other cards.
static func rank_change_text(c: LevelCard, runner: AbilityRunner) -> String:
	if c == null or c.kind != LevelCard.Kind.RANK_UP or c.ability == null:
		return ""
	var rank := (runner.rank_of(c.ability.id) if runner != null else 1) + 1
	var text := AbilityRanks.rank_text(c.ability, rank)
	if rank >= AbilityRanks.MAX_RANK and c.ability.specs.size() >= 2:
		text = "Specialization: %s or %s" % [str(c.ability.specs[0].get("name", "?")), str(c.ability.specs[1].get("name", "?"))]
	return text


## True when [param c] teaches a new ability and every slot of its kind is taken.
static func needs_replacement(c: LevelCard, runner: AbilityRunner) -> bool:
	return c != null and c.kind == LevelCard.Kind.NEW_ABILITY and runner != null \
		and not runner.knows(c.ability.id) and runner.free_slot(c.ability.kind) < 0


static func rarity_color(rarity: int) -> Color:
	return UiTheme.RARITY_COLORS[clampi(rarity, 0, UiTheme.RARITY_COLORS.size() - 1)]


# --- State ---------------------------------------------------------------------------

## Shows [param c] for the hero whose abilities are [param runner].
func set_card(c: LevelCard, runner: AbilityRunner) -> void:
	card = c
	visible = c != null
	if c == null:
		return
	replaces = needs_replacement(c, runner)
	ribbon_text = kind_text(c, runner)
	name_label.text = c.title()
	info_label.text = info_text(c, runner)
	var rank_text := rank_change_text(c, runner)
	rank_label.text = rank_text
	rank_label.visible = rank_text != ""
	text_label.text = body_text(c, runner)
	warning_label.visible = replaces
	var stat := c.kind == LevelCard.Kind.STAT
	_icon.visible = not stat
	_gem.visible = stat
	if stat:
		accent = rarity_color(c.rarity)
		_ribbon_color = accent.darkened(0.45) if c.rarity > 0 else Color(0.42, 0.4, 0.37)
		_gem.color = accent
		_gem.queue_redraw()
		name_label.add_theme_color_override(&"font_color", accent if c.rarity > 0 else UiTheme.TEXT)
		text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text_label.add_theme_font_size_override(&"font_size", STAT_FONT)
		text_label.add_theme_color_override(&"font_color", UiTheme.TEXT)
		text_label.add_theme_constant_override(&"line_spacing", 4)
	else:
		_icon.set_ability(c.ability)
		accent = AbilityIcon.color_for(c.ability)
		_ribbon_color = NEW_COLOR if c.kind == LevelCard.Kind.NEW_ABILITY else RANK_COLOR
		name_label.add_theme_color_override(&"font_color", accent.lerp(Color.WHITE, 0.35))
		text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		text_label.add_theme_font_size_override(&"font_size", TEXT_FONT)
		text_label.add_theme_color_override(&"font_color", Color(0.9, 0.87, 0.8))
		text_label.add_theme_constant_override(&"line_spacing", -1)
	_body.queue_redraw()


func set_selected(on: bool, color: Color) -> void:
	if on == selected and color == cursor_color:
		return
	selected = on
	cursor_color = color
	_body.offset_top = -LIFT if on else 0.0
	_body.offset_bottom = -LIFT if on else 0.0
	_body.queue_redraw()


## Greyed out behind a sub-prompt / once the player is done.
func set_dim(on: bool) -> void:
	_dim = on
	modulate = Color(1, 1, 1, 0.3) if on else Color.WHITE


# --- Build / draw ------------------------------------------------------------------------

func _build() -> void:
	_body = Control.new()
	_body.name = "Body"
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_body.draw.connect(_draw_body)
	add_child(_body)
	_content = UiTheme.vbox(3)
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.offset_left = PAD
	_content.offset_right = -PAD
	_content.offset_top = RIBBON_HEIGHT + 8.0
	_content.offset_bottom = -PAD
	_body.add_child(_content)
	_icon_holder = CenterContainer.new()
	_icon_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_holder.custom_minimum_size = Vector2(0, ICON_SIZE + 4.0)
	_content.add_child(_icon_holder)
	_icon = AbilityIcon.create(ICON_SIZE)
	_icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	_icon_holder.add_child(_icon)
	_gem = Gem.new()
	_gem.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	_gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_holder.add_child(_gem)
	name_label = UiTheme.centered_label("", &"", NAME_FONT)
	name_label.add_theme_font_override(&"font", UiTheme.bold_font())
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(CARD_SIZE.x - PAD * 2.0, 0)
	name_label.add_theme_constant_override(&"line_spacing", -4)
	name_label.max_lines_visible = 2
	_content.add_child(name_label)
	info_label = UiTheme.centered_label("", &"", INFO_FONT, UiTheme.TEXT_DIM)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.custom_minimum_size = Vector2(CARD_SIZE.x - PAD * 2.0, 0)
	info_label.add_theme_constant_override(&"line_spacing", -3)
	_content.add_child(info_label)
	rank_label = UiTheme.centered_label("", &"", INFO_FONT + 1, RANK_TEXT_COLOR)
	rank_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rank_label.custom_minimum_size = Vector2(CARD_SIZE.x - PAD * 2.0, 0)
	rank_label.add_theme_constant_override(&"line_spacing", -3)
	_content.add_child(rank_label)
	var rule := UiTheme.divider(0)
	rule.custom_minimum_size.y = 10
	_content.add_child(rule)
	text_label = UiTheme.wrapped_label("", &"", TEXT_FONT)
	text_label.custom_minimum_size = Vector2(CARD_SIZE.x - PAD * 2.0, 0)
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text_label.clip_text = true
	_content.add_child(text_label)
	warning_label = UiTheme.centered_label("Slots full – replaces one", &"", 16, Color(1.0, 0.86, 0.8))
	warning_label.add_theme_font_override(&"font", UiTheme.bold_font())
	warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning_label.custom_minimum_size = Vector2(CARD_SIZE.x - PAD * 2.0, 0)
	warning_label.add_theme_constant_override(&"line_spacing", -4)
	warning_label.visible = false
	_content.add_child(warning_label)


func _draw_body() -> void:
	var ci := _body
	var r := Rect2(Vector2.ZERO, _body.size)
	if r.size.x <= 0.0:
		return
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.075, 0.06, 0.05, 0.98)
	box.set_corner_radius_all(7)
	box.anti_aliasing = true
	if selected:
		box.border_color = cursor_color.lightened(0.35)
		box.set_border_width_all(4)
		box.shadow_color = Color(cursor_color, 0.75)
		box.shadow_size = 18
	else:
		box.border_color = Color(accent.darkened(0.4), 0.95)
		box.set_border_width_all(2)
		box.shadow_color = Color(0, 0, 0, 0.55)
		box.shadow_size = 8
		box.shadow_offset = Vector2(0, 4)
	ci.draw_style_box(box, r)
	# Colour wash from the top (ability colour / rarity), like the shop cards.
	var inner := r.grow(-4.0)
	var glow := Color(accent, 0.2 if selected else 0.13)
	var clear := Color(accent, 0.0)
	var mid := inner.position.y + inner.size.y * 0.5
	ci.draw_polygon(PackedVector2Array([inner.position, Vector2(inner.end.x, inner.position.y),
		Vector2(inner.end.x, mid), Vector2(inner.position.x, mid)]), PackedColorArray([glow, glow, clear, clear]))
	# Ribbon across the top.
	var rib := Rect2(inner.position, Vector2(inner.size.x, RIBBON_HEIGHT))
	ci.draw_rect(rib, _ribbon_color)
	ci.draw_rect(Rect2(rib.position.x, rib.end.y - 2.0, rib.size.x, 2.0), Color(0, 0, 0, 0.45))
	ci.draw_rect(Rect2(rib.position, Vector2(rib.size.x, 1.0)), Color(1, 1, 1, 0.18))
	var font := UiTheme.bold_font()
	var fs := 16
	var tw := font.get_string_size(ribbon_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tp := Vector2(rib.position.x + (rib.size.x - tw) * 0.5, rib.position.y + RIBBON_HEIGHT * 0.5 + fs * 0.36)
	ci.draw_string_outline(font, tp, ribbon_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, UiTheme.OUTLINE)
	ci.draw_string(font, tp, ribbon_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.97, 0.9))
	# Red strip behind the "Slots full" warning.
	if replaces and warning_label.visible and warning_label.size.y > 0.0:
		var w := Rect2(Vector2(inner.position.x, _content.position.y + warning_label.position.y - 4.0),
			Vector2(inner.size.x, warning_label.size.y + 8.0))
		w.size.y = minf(w.size.y, inner.end.y - w.position.y)
		ci.draw_rect(w, Color(WARN_COLOR, 0.92))
		ci.draw_rect(Rect2(w.position, Vector2(w.size.x, 1.5)), Color(1.0, 0.45, 0.35, 0.8))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _body != null:
		_body.queue_redraw()


## A faceted gem in the rarity colour (stat cards).
class Gem extends Control:
	var color := Color.WHITE

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var c := size * 0.5
		var h := s * 0.46
		var w := s * 0.4
		var top := c + Vector2(0, -h)
		var bottom := c + Vector2(0, h)
		var left := c + Vector2(-w, -h * 0.25)
		var right := c + Vector2(w, -h * 0.25)
		var table_l := c + Vector2(-w * 0.45, -h * 0.25)
		var table_r := c + Vector2(w * 0.45, -h * 0.25)
		var outline := PackedVector2Array([top, right, bottom, left, top])
		draw_colored_polygon(PackedVector2Array([top + Vector2(0, -3), right + Vector2(3, 0), bottom + Vector2(0, 3), left + Vector2(-3, 0)]), Color(0.05, 0.03, 0.02, 0.9))
		var base := color
		draw_colored_polygon(PackedVector2Array([top, right, table_r, table_l, left]), base.lightened(0.25))
		draw_colored_polygon(PackedVector2Array([left, table_l, bottom]), base.darkened(0.15))
		draw_colored_polygon(PackedVector2Array([table_l, table_r, bottom]), base)
		draw_colored_polygon(PackedVector2Array([table_r, right, bottom]), base.darkened(0.4))
		draw_colored_polygon(PackedVector2Array([top, table_r, table_l]), base.lightened(0.55))
		draw_polyline(outline, UiTheme.GOLD_BORDER, 2.0, true)
		draw_line(left, right, Color(UiTheme.GOLD_BORDER, 0.7), 1.2, true)
		draw_circle(c + Vector2(-w * 0.18, -h * 0.5), s * 0.05, Color(1, 1, 1, 0.8))
