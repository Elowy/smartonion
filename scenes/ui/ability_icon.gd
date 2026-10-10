class_name AbilityIcon
extends Control
## One ability slot on the HUD / lobby card, drawn in code (no image assets yet): a gold-rimmed
## square with a procedural glyph picked by AbilityData.icon (falling back to the ability id and
## then to the school), tinted by AbilityData.color (or the school colour when the data leaves
## the default white).
##
## State drawn on top of the glyph (all pushed in by the owner, nothing is read from gameplay):
##  - cooldown sweep: a dark pie that shrinks clockwise (WoW style) + the seconds left,
##  - dimmed: off cooldown but not usable (resource missing / player down) - darker, the cost in red,
##  - flash: a short white pop when the ability was cast ([method flash_cast]),
##  - the button prompt ("RT", "LMB" ...) as a small pill straddling the bottom edge, the
##    resource cost in the top-right corner.
## Empty slots draw a faint socket. The control is SIZE wide and SIZE + PROMPT_OVERHANG tall
## (the prompt pill hangs below the square).

enum Glyph {
	GENERIC, PHYSICAL, WHIRLWIND, DASH, BLIZZARD, BLINK, CONSECRATION, HEAL, KNIVES, VANISH,
	RAIN_OF_FIRE, DRAIN, FIRE, FROST, ARCANE, HOLY, SKULL, NATURE, SHIELD, HAMMER, BOLT, BOMB,
}

const SIZE := 44.0
const PROMPT_HEIGHT := 22.0
const PROMPT_OVERHANG := 11.0
const PROMPT_FONT := 18
const COOLDOWN_FONT := 22
const COST_FONT := 18
const FLASH_TIME := 0.32
## Glyph half-extent as a share of the half icon size.
const GLYPH_SCALE := 0.74
const OUT := Color(0.05, 0.03, 0.02, 0.95)

const SCHOOL_COLORS: Dictionary[StringName, Color] = {
	&"physical": Color(0.86, 0.78, 0.62),
	&"fire": Color(1.0, 0.5, 0.16),
	&"frost": Color(0.45, 0.8, 1.0),
	&"arcane": Color(0.78, 0.5, 1.0),
	&"holy": Color(1.0, 0.88, 0.4),
	&"shadow": Color(0.62, 0.36, 0.88),
	&"nature": Color(0.4, 0.85, 0.35),
}

## Glyph used when neither the icon id nor the ability id matches a rule.
const SCHOOL_GLYPHS: Dictionary[StringName, Glyph] = {
	&"physical": Glyph.PHYSICAL, &"fire": Glyph.FIRE, &"frost": Glyph.FROST,
	&"arcane": Glyph.ARCANE, &"holy": Glyph.HOLY, &"shadow": Glyph.SKULL, &"nature": Glyph.NATURE,
}

## Whole ids first (they win over the token rules).
const EXACT_GLYPHS: Dictionary[StringName, Glyph] = {
	&"thunder_clap": Glyph.WHIRLWIND, &"war_stomp": Glyph.HAMMER, &"cheat_death": Glyph.SKULL,
	&"divine_storm": Glyph.HOLY, &"rain_of_fire": Glyph.RAIN_OF_FIRE, &"drain_life": Glyph.DRAIN,
	&"word_of_glory": Glyph.HEAL, &"fan_of_knives": Glyph.KNIVES, &"lay_on_hands": Glyph.HEAL,
}

## Ordered token rules: the first rule with a key that starts one of the id's `_`-separated
## words wins ("rain_of_fire" -> rain before fire, "ice_barrier" -> barrier before ice).
const TOKEN_RULES: Array[Array] = [
	[Glyph.WHIRLWIND, ["whirl", "spin", "swirl", "bladestorm", "tornado", "cyclone"]],
	[Glyph.DASH, ["charge", "dash", "leap", "rush", "sprint", "shadowstep", "stampede", "jump"]],
	[Glyph.BLIZZARD, ["blizzard", "hail"]],
	[Glyph.BLINK, ["blink", "teleport", "phase", "warp"]],
	[Glyph.CONSECRATION, ["consecrat", "sanctif"]],
	[Glyph.DRAIN, ["drain", "siphon", "leech"]],
	[Glyph.KNIVES, ["knife", "knives", "dagger", "shuriken", "stab", "eviscerate"]],
	[Glyph.VANISH, ["vanish", "stealth", "cloak", "shroud"]],
	[Glyph.RAIN_OF_FIRE, ["rain", "meteor", "starfall"]],
	[Glyph.FIRE, ["fire", "flame", "burn", "inferno", "infernal", "pyro", "ignite", "immolat", "blaze"]],
	[Glyph.SHIELD, ["shield", "barrier", "ward", "wall", "bulwark", "bubble"]],
	[Glyph.HAMMER, ["hammer", "mace", "justice", "smash", "stomp", "slam"]],
	[Glyph.FROST, ["frost", "ice", "freez", "nova", "chill", "snow", "glacial"]],
	[Glyph.ARCANE, ["arcane", "missile", "mana", "orb"]],
	[Glyph.BOLT, ["bolt", "lightning", "thunder", "shock", "chain", "zap"]],
	[Glyph.HEAL, ["glory", "heal", "bandage", "hands", "mend", "renew", "rejuv"]],
	[Glyph.HOLY, ["holy", "smite", "light", "divine", "bless", "aura", "sacred", "crusader"]],
	[Glyph.BOMB, ["bomb", "explo", "grenade", "engineer", "mine", "dynamite"]],
	[Glyph.SKULL, ["skull", "death", "execute", "fear", "curse", "doom", "corrupt", "shadow", "void", "seed", "kill", "reap", "soul"]],
	[Glyph.NATURE, ["nature", "leaf", "thorn", "wolf", "spirit", "poison", "venom", "wild"]],
	[Glyph.PHYSICAL, ["slash", "strike", "cleave", "sword", "blade", "cut", "rend", "shout", "berserk", "rage", "fury", "bleed"]],
]

var ability: AbilityData
var slot_index := -1
var glyph := Glyph.GENERIC
## Resolved tint (AbilityData.color, or the school colour).
var icon_color := Color.WHITE
## Button prompt text ("RT", "LMB" ...); "" hides the pill.
var prompt := ""
## Keyboard prompts are drawn as a light key cap, controller prompts as a dark pill.
var prompt_keyboard := false
var show_prompt := true
var cost := 0.0
var cost_color := Color.WHITE
## 0..1 share of the cooldown still running (the dark pie).
var sweep_ratio := 0.0
var cooldown_left := 0.0
## Usable right now (alive, off cooldown, affordable).
var usable := true
## Off cooldown but not usable: dim overlay, red cost.
var dimmed := false
## 0..1, 1 right after a cast.
var flash := 0.0

var _text_cache := ""
## Side of the icon square (the control is a little taller: the prompt pill hangs below it).
var _side := SIZE


static func create(p_size: float = SIZE) -> AbilityIcon:
	var i := AbilityIcon.new()
	i._side = p_size
	i.custom_minimum_size = Vector2(p_size, p_size + PROMPT_OVERHANG)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	i.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	i.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	i.pivot_offset = Vector2(p_size * 0.5, p_size * 0.5)
	i.set_process(false)
	return i


# --- Glyph choice ---------------------------------------------------------------------

static func school_color(school: StringName) -> Color:
	return SCHOOL_COLORS.get(school, Color(0.85, 0.8, 0.7))


## Tint of [param a]: its own colour unless it still is the default white.
static func color_for(a: AbilityData) -> Color:
	if a == null:
		return Color(0.5, 0.5, 0.5)
	return a.color if not a.color.is_equal_approx(Color.WHITE) else school_color(a.school)


## Which glyph an ability gets: the icon id, then the ability id, then the school.
static func glyph_for(icon: StringName, school: StringName = &"", id: StringName = &"") -> Glyph:
	for key: StringName in [icon, id]:
		if key == &"":
			continue
		var norm := _normalize(key)
		if EXACT_GLYPHS.has(norm):
			return EXACT_GLYPHS[norm]
		var found := _match_tokens(String(norm))
		if found >= 0:
			return found as Glyph
	return SCHOOL_GLYPHS.get(school, Glyph.GENERIC)


static func glyph_for_ability(a: AbilityData) -> Glyph:
	return glyph_for(a.icon, a.school, a.id) if a != null else Glyph.GENERIC


static func _normalize(key: StringName) -> StringName:
	return StringName(String(key).to_lower().replace("-", "_").replace(" ", "_").replace("'", ""))


static func _match_tokens(id: String) -> int:
	var tokens := id.split("_", false)
	for rule in TOKEN_RULES:
		for token in tokens:
			for k: String in rule[1]:
				if token.begins_with(k):
					return rule[0]
	return -1


## Tooltip text of [param a]: AbilityData.description with {param} placeholders filled from
## [param params] (the ability's params after item mods / ranks; defaults to AbilityData.params).
## Numbers are shown without trailing zeros ("2.0" -> "2", "0.50" -> "0.5"); a placeholder
## without a value is left as written.
static func format_description(a: AbilityData, params: Dictionary = {}) -> String:
	if a == null:
		return ""
	var values: Dictionary = params if not params.is_empty() else a.params
	var text := a.description
	for key: Variant in values:
		text = text.replace("{%s}" % str(key), format_number(values[key]))
	return text


## 2.0 -> "2", 0.5 -> "0.5", 0.3333 -> "0.33", 1234 -> "1234"; other types via str().
static func format_number(value: Variant) -> String:
	match typeof(value):
		TYPE_INT:
			return str(value)
		TYPE_FLOAT:
			var v := float(value)
			if is_equal_approx(v, roundf(v)):
				return str(int(roundf(v)))
			var s := ("%.2f" % v)
			while s.ends_with("0"):
				s = s.left(s.length() - 1)
			return s
	return str(value)


## Cooldown readout: "" when nothing runs, "0.8" under 3 s, whole seconds above, "1:05" from a minute.
static func format_cooldown(seconds: float) -> String:
	if seconds < 0.05:
		return ""
	if seconds >= 60.0:
		return UiTheme.format_time(seconds)
	if seconds < 3.0:
		return "%.1f" % seconds
	return str(int(ceilf(seconds - 0.001)))


# --- State ------------------------------------------------------------------------------

## Shows [param a] (null = empty socket). [param p_cost] < 0 uses AbilityData.cost.
func set_ability(a: AbilityData, p_cost: float = -1.0, p_cost_color: Color = Color(0, 0, 0, 0)) -> void:
	ability = a
	if a != null:
		glyph = glyph_for_ability(a)
		icon_color = color_for(a)
		cost = p_cost if p_cost >= 0.0 else a.cost
		cost_color = p_cost_color if p_cost_color.a > 0.0 else icon_color
	else:
		cost = 0.0
	queue_redraw()


func set_prompt(text: String, keyboard: bool = false) -> void:
	prompt = text
	prompt_keyboard = keyboard
	queue_redraw()


## Pushes the live state. Only redraws when something visible changed.
func set_state(p_ratio: float, p_left: float, p_ready: bool) -> void:
	var ratio := clampf(p_ratio, 0.0, 1.0)
	var text := format_cooldown(p_left)
	var dim := not p_ready and p_left <= 0.0
	var changed := text != _text_cache or absf(ratio - sweep_ratio) >= 0.004 \
		or dim != dimmed or p_ready != usable
	sweep_ratio = ratio
	cooldown_left = maxf(p_left, 0.0)
	usable = p_ready
	dimmed = dim
	_text_cache = text
	if changed:
		queue_redraw()


func cooldown_text() -> String:
	return _text_cache


func is_dimmed() -> bool:
	return dimmed


func is_empty() -> bool:
	return ability == null


## Short white pop (the ability was just cast).
func flash_cast() -> void:
	flash = 1.0
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	flash = maxf(0.0, flash - delta / FLASH_TIME)
	scale = Vector2.ONE * (1.0 + 0.16 * flash * flash)
	if flash <= 0.0:
		scale = Vector2.ONE
		set_process(false)
	queue_redraw()


# --- Drawing ----------------------------------------------------------------------------

# Glyph drawing state: every glyph function runs twice, pass 0 = dark outlines, pass 1 = fills,
# so overlapping parts of one glyph never leave outline seams between them.
var _pass := 0
var _c := Vector2.ZERO
var _h := 1.0
var _ow := 2.0
var _tone := Color.WHITE
var _hi := Color.WHITE
var _deep := Color.WHITE


func _draw() -> void:
	var sq := _side
	var rect := Rect2(0, 0, sq, sq)
	if ability == null:
		var socket := StyleBoxFlat.new()
		socket.bg_color = Color(0.03, 0.025, 0.02, 0.45)
		socket.border_color = Color(UiTheme.GOLD_DARK, 0.5)
		socket.set_border_width_all(2)
		socket.set_corner_radius_all(5)
		draw_style_box(socket, rect)
		return
	var base := icon_color
	_tone = base.lightened(0.35)
	_hi = base.lightened(0.7)
	_deep = base.darkened(0.1)

	var bg := StyleBoxFlat.new()
	bg.bg_color = base.darkened(0.72)
	bg.set_corner_radius_all(5)
	bg.anti_aliasing = true
	draw_style_box(bg, rect)
	draw_circle(rect.get_center(), sq * 0.4, Color(base, 0.22))
	draw_rect(Rect2(3, 3, sq - 6, sq * 0.34), Color(1, 1, 1, 0.05))

	_c = rect.get_center()
	_h = sq * 0.5 * GLYPH_SCALE
	_ow = maxf(1.5, sq / 24.0)
	for p in 2:
		_pass = p
		_draw_glyph(glyph)

	if dimmed:
		var dim := StyleBoxFlat.new()
		dim.bg_color = Color(0.03, 0.035, 0.07, 0.66)
		dim.set_corner_radius_all(5)
		draw_style_box(dim, rect)
	elif sweep_ratio > 0.004:
		var poly := sweep_polygon(rect.grow(-2.0), sweep_ratio)
		if poly.size() >= 3:
			draw_colored_polygon(poly, Color(0, 0, 0, 0.7))
			if sweep_ratio < 0.996:
				draw_line(poly[0], poly[1], Color(1, 1, 1, 0.5), 1.5)
	if flash > 0.0:
		var f := StyleBoxFlat.new()
		f.bg_color = Color(1, 0.97, 0.85, 0.7 * flash)
		f.set_corner_radius_all(5)
		draw_style_box(f, rect)

	var border := UiTheme.GOLD_BORDER if usable else (UiTheme.GOLD_DARK if sweep_ratio > 0.004 else Color(0.34, 0.3, 0.24))
	var outer := StyleBoxFlat.new()
	outer.draw_center = false
	outer.border_color = Color(0, 0, 0, 0.9)
	outer.set_border_width_all(1)
	outer.set_corner_radius_all(6)
	draw_style_box(outer, rect.grow(1.0))
	var rim := StyleBoxFlat.new()
	rim.draw_center = false
	rim.border_color = UiTheme.GOLD_BRIGHT if flash > 0.3 else border
	rim.set_border_width_all(2)
	rim.set_corner_radius_all(5)
	rim.anti_aliasing = true
	draw_style_box(rim, rect)

	if _text_cache != "":
		_text(_text_cache, rect.get_center(), COOLDOWN_FONT, UiTheme.TEXT)
	if cost > 0.0:
		var label := UiTheme.format_amount(cost)
		var color := UiTheme.RED.lightened(0.15) if dimmed else cost_color.lightened(0.5)
		var w := _text_width(label, COST_FONT)
		_text(label, Vector2(sq - w * 0.5 - 3.0, 11.0), COST_FONT, color, 5)
	if show_prompt and prompt != "":
		_draw_prompt(sq)


## Polygon of the dark cooldown pie: [param ratio] of the circle, clockwise from 12 o'clock,
## ending at 12 o'clock (so it shrinks clockwise as the cooldown runs out). Point 0 is the centre,
## point 1 the leading edge.
static func sweep_polygon(rect: Rect2, ratio: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if ratio <= 0.0:
		return pts
	var center := rect.get_center()
	var half := rect.size * 0.5
	var start := (1.0 - clampf(ratio, 0.0, 1.0)) * TAU
	pts.append(center)
	pts.append(center + _edge_point(half, start))
	for k in 4:
		var corner := PI * 0.25 + k * PI * 0.5
		if corner > start + 0.0001 and corner < TAU - 0.0001:
			pts.append(center + _edge_point(half, corner))
	pts.append(center + _edge_point(half, TAU))
	return pts


## Point on the rectangle boundary (half extents) in direction [param angle] (clockwise from up).
static func _edge_point(half: Vector2, angle: float) -> Vector2:
	var d := Vector2(sin(angle), -cos(angle))
	var tx := half.x / maxf(absf(d.x), 0.0001)
	var ty := half.y / maxf(absf(d.y), 0.0001)
	return d * minf(tx, ty)


func _draw_prompt(sq: float) -> void:
	var w := maxf(_text_width(prompt, PROMPT_FONT) + 12.0, 28.0)
	var pill := Rect2(sq * 0.5 - w * 0.5, sq - PROMPT_OVERHANG, w, PROMPT_HEIGHT)
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(int(PROMPT_HEIGHT * 0.5) if not prompt_keyboard else 5)
	style.anti_aliasing = true
	style.set_border_width_all(2)
	style.border_color = UiGlyph.DARK
	if prompt_keyboard:
		style.bg_color = Color(0.82, 0.78, 0.7)
		style.border_width_bottom = 3
	else:
		style.bg_color = Color(0.24, 0.23, 0.22)
		style.border_color = Color(UiTheme.GOLD_DARK, 0.95)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 2
	draw_style_box(style, pill)
	var font := UiTheme.bold_font()
	var pos := Vector2(pill.get_center().x - _text_width(prompt, PROMPT_FONT) * 0.5,
		pill.get_center().y + (font.get_ascent(PROMPT_FONT) - font.get_descent(PROMPT_FONT)) * 0.5 - (1.0 if prompt_keyboard else 0.0))
	if prompt_keyboard:
		draw_string(font, pos, prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, PROMPT_FONT, UiGlyph.DARK)
	else:
		draw_string_outline(font, pos, prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, PROMPT_FONT, 4, Color(0, 0, 0, 0.7))
		draw_string(font, pos, prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, PROMPT_FONT, UiTheme.TEXT)


static func _text_width(text: String, fs: int) -> float:
	return UiTheme.bold_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


func _text(text: String, center: Vector2, fs: int, col: Color, outline: int = 6) -> void:
	var font := UiTheme.bold_font()
	var w := _text_width(text, fs)
	var pos := Vector2(center.x - w * 0.5, center.y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, UiTheme.OUTLINE)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


# --- Shape helpers (unit space: centre 0,0, extent about +-1, y down) -------------------

func _p(v: Vector2) -> Vector2:
	return _c + v * _h


func _map(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in pts:
		out.append(_p(v))
	return out


## Filled polygon with an outline. [param layered]: drawn only in the fill pass, outline
## included, so it separates itself from the shapes below it.
func _poly(pts: PackedVector2Array, col: Color, layered: bool = false) -> void:
	var m := _map(pts)
	if _pass == 0 and not layered:
		var closed := m.duplicate()
		closed.append(m[0])
		draw_polyline(closed, OUT, _ow * 2.0, true)
	elif _pass == 1:
		if layered:
			var closed := m.duplicate()
			closed.append(m[0])
			draw_polyline(closed, OUT, _ow * 1.4, true)
		draw_colored_polygon(m, col)


func _circ(center: Vector2, r: float, col: Color, layered: bool = false) -> void:
	if _pass == 0 and not layered:
		draw_circle(_p(center), r * _h + _ow, OUT, true, -1.0, true)
	elif _pass == 1:
		if layered:
			draw_circle(_p(center), r * _h + _ow * 0.7, OUT, true, -1.0, true)
		draw_circle(_p(center), r * _h, col, true, -1.0, true)


func _stroke(pts: PackedVector2Array, w: float, col: Color) -> void:
	var m := _map(pts)
	if _pass == 0:
		draw_polyline(m, OUT, w * _h + _ow * 2.0, true)
		draw_circle(m[0], w * _h * 0.5 + _ow, OUT, true, -1.0, true)
		draw_circle(m[m.size() - 1], w * _h * 0.5 + _ow, OUT, true, -1.0, true)
	else:
		draw_polyline(m, col, w * _h, true)
		draw_circle(m[0], w * _h * 0.5, col, true, -1.0, true)
		draw_circle(m[m.size() - 1], w * _h * 0.5, col, true, -1.0, true)


## Fill-pass-only variants: highlights and engraved details without an outline.
func _d_poly(pts: PackedVector2Array, col: Color) -> void:
	if _pass == 1:
		draw_colored_polygon(_map(pts), col)


func _d_circ(center: Vector2, r: float, col: Color) -> void:
	if _pass == 1:
		draw_circle(_p(center), r * _h, col, true, -1.0, true)


func _d_stroke(pts: PackedVector2Array, w: float, col: Color) -> void:
	if _pass == 1:
		draw_polyline(_map(pts), col, w * _h, true)


static func _rect_pts(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])


static func _xf(pts: PackedVector2Array, angle: float, offset: Vector2 = Vector2.ZERO, scale_by: float = 1.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in pts:
		out.append(v.rotated(angle) * scale_by + offset)
	return out


static func _ellipse(center: Vector2, rx: float, ry: float, n: int = 20) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * i / float(n)
		out.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return out


static func _star(center: Vector2, outer: float, inner: float, points: int, rot: float = -PI * 0.5) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in points * 2:
		var a := rot + PI * i / float(points)
		var r := outer if i % 2 == 0 else inner
		out.append(center + Vector2(cos(a), sin(a)) * r)
	return out


static func _mirror(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in pts:
		out.append(Vector2(-v.x, v.y))
	return out


# --- Glyphs -----------------------------------------------------------------------------

func _draw_glyph(g: Glyph) -> void:
	match g:
		Glyph.PHYSICAL: _g_sword()
		Glyph.WHIRLWIND: _g_whirlwind()
		Glyph.DASH: _g_dash()
		Glyph.BLIZZARD: _g_blizzard()
		Glyph.BLINK: _g_blink()
		Glyph.CONSECRATION: _g_consecration()
		Glyph.HEAL: _g_heal()
		Glyph.KNIVES: _g_knives()
		Glyph.VANISH: _g_vanish()
		Glyph.RAIN_OF_FIRE: _g_rain_of_fire()
		Glyph.DRAIN: _g_drain()
		Glyph.FIRE: _g_fire()
		Glyph.FROST: _g_frost()
		Glyph.ARCANE: _g_arcane()
		Glyph.HOLY: _g_holy()
		Glyph.SKULL: _g_skull()
		Glyph.NATURE: _g_leaf()
		Glyph.SHIELD: _g_shield()
		Glyph.HAMMER: _g_hammer()
		Glyph.BOLT: _g_bolt()
		Glyph.BOMB: _g_bomb()
		_: _g_generic()


func _g_generic() -> void:
	_poly(PackedVector2Array([Vector2(0, -0.9), Vector2(0.7, 0), Vector2(0, 0.9), Vector2(-0.7, 0)]), _tone)
	_d_poly(PackedVector2Array([Vector2(0, -0.5), Vector2(0.38, 0), Vector2(0, 0.5), Vector2(-0.38, 0)]), _deep)
	_d_circ(Vector2.ZERO, 0.12, _hi)


func _g_sword() -> void:
	var a := PI * 0.25
	_poly(_xf(PackedVector2Array([Vector2(-0.12, 0.3), Vector2(-0.12, -0.62), Vector2(0, -0.95), Vector2(0.12, -0.62), Vector2(0.12, 0.3)]), a), _hi)
	_poly(_xf(_rect_pts(-0.4, 0.3, 0.4, 0.45), a), UiTheme.GOLD_BORDER)
	_poly(_xf(_rect_pts(-0.08, 0.45, 0.08, 0.78), a), Color(0.55, 0.36, 0.2))
	_circ(Vector2(0.0, 0.85).rotated(a), 0.12, UiTheme.GOLD_BORDER)
	_d_stroke(_xf(PackedVector2Array([Vector2(0, 0.2), Vector2(0, -0.7)]), a), 0.05, _tone)


func _g_whirlwind() -> void:
	for arm in 2:
		var pts := PackedVector2Array()
		for i in 16:
			var t := i / 15.0
			var ang := arm * PI + t * 4.6 - 0.6
			pts.append(Vector2(cos(ang), sin(ang)) * (0.12 + 0.82 * t))
		_stroke(pts, 0.2, _tone if arm == 0 else _hi)
	_circ(Vector2.ZERO, 0.15, _hi)


func _g_dash() -> void:
	_poly(PackedVector2Array([Vector2(0.1, -0.58), Vector2(0.98, 0), Vector2(0.1, 0.58)]), _hi)
	_poly(_rect_pts(-0.35, -0.2, 0.2, 0.2), _tone)
	for y: float in [-0.5, 0.0, 0.5]:
		_stroke(PackedVector2Array([Vector2(-0.95, y), Vector2(-0.55 if y == 0.0 else -0.45, y)]), 0.11, _tone)


func _g_blizzard() -> void:
	for p: Vector2 in [Vector2(-0.42, -0.4), Vector2(0.0, -0.55), Vector2(0.42, -0.35)]:
		_circ(p, 0.32 if p.x == 0.0 else 0.27, _tone)
	_poly(_rect_pts(-0.66, -0.4, 0.66, -0.02), _tone)
	for x: float in [-0.42, 0.0, 0.42]:
		_stroke(PackedVector2Array([Vector2(x + 0.12, 0.2), Vector2(x - 0.12, 0.72)]), 0.14, _hi)
	_d_circ(Vector2(-0.08, -0.62), 0.14, _hi)


func _g_blink() -> void:
	_poly(_star(Vector2(0.34, 0.0), 0.62, 0.17, 4), _hi)
	_d_circ(Vector2(-0.28, 0.0), 0.2, Color(_tone, 0.9))
	_d_circ(Vector2(-0.6, 0.0), 0.14, Color(_tone, 0.6))
	_d_circ(Vector2(-0.84, 0.0), 0.09, Color(_tone, 0.38))
	_d_circ(Vector2(0.34, 0.0), 0.12, Color.WHITE)


func _g_consecration() -> void:
	_poly(_ellipse(Vector2(0, 0.52), 0.9, 0.34), _deep)
	_d_poly(_ellipse(Vector2(0, 0.52), 0.62, 0.2), _tone)
	_poly(_rect_pts(-0.11, -0.8, 0.11, 0.5), _hi)
	_poly(_rect_pts(-0.42, -0.45, 0.42, -0.22), _hi)


func _g_heal() -> void:
	for side: float in [-1.0, 1.0]:
		for i in 3:
			var ang := -1.0 + 0.52 * i
			var len := 0.7 + 0.14 * i
			var dir := Vector2(side, 0.0).rotated(ang * side)
			var feather := _xf(_ellipse(Vector2.ZERO, len * 0.5, 0.17, 16), dir.angle(), Vector2(side * 0.14, -0.06) + dir * len * 0.5)
			_poly(feather, _tone if i != 1 else _hi, true)
	_poly(_rect_pts(-0.15, -0.76, 0.15, 0.84), _hi, true)
	_poly(_rect_pts(-0.44, -0.36, 0.44, -0.06), _hi, true)


func _g_knives() -> void:
	var pivot := Vector2(0.0, 1.0)
	var blade := PackedVector2Array([Vector2(-0.14, -0.3), Vector2(-0.14, -0.92), Vector2(0, -1.24), Vector2(0.14, -0.92), Vector2(0.14, -0.3)])
	var guard := _rect_pts(-0.26, -0.3, 0.26, -0.2)
	for a: float in [-0.7, 0.7, 0.0]:
		_poly(_xf(blade, a, pivot), _hi if a == 0.0 else _tone, true)
		_poly(_xf(guard, a, pivot), UiTheme.GOLD_BORDER, true)
		_d_stroke(_xf(PackedVector2Array([Vector2(0, -0.35), Vector2(0, -1.0)]), a, pivot), 0.04, Color(1, 1, 1, 0.55))


func _g_vanish() -> void:
	var cloak := _deep.darkened(0.2)
	_poly(PackedVector2Array([Vector2(-0.82, 0.86), Vector2(-0.64, 0.3), Vector2(-0.3, 0.1), Vector2(0.3, 0.1), Vector2(0.64, 0.3), Vector2(0.82, 0.86)]), cloak)
	_circ(Vector2(0, -0.26), 0.46, cloak)
	_poly(PackedVector2Array([Vector2(-0.42, -0.45), Vector2(0.04, -1.02), Vector2(0.42, -0.45)]), cloak)
	_d_poly(_ellipse(Vector2(0, -0.2), 0.27, 0.27), OUT)
	_d_circ(Vector2(-0.11, -0.22), 0.065, _hi)
	_d_circ(Vector2(0.11, -0.22), 0.065, _hi)
	_d_stroke(PackedVector2Array([Vector2(-0.3, 0.45), Vector2(0.3, 0.45)]), 0.05, Color(_tone, 0.55))
	for p: Vector2 in [Vector2(-0.7, 0.8), Vector2(0.72, 0.84), Vector2(0.0, 0.92)]:
		_circ(p, 0.2 if p.x != 0.0 else 0.24, Color(_tone, 0.8), true)


func _g_rain_of_fire() -> void:
	var tip := PackedVector2Array([Vector2(-0.2, -0.06), Vector2(0.2, -0.06), Vector2(0.0, -0.82)])
	var drops := [[Vector2(-0.5, 0.0), 0.95], [Vector2(0.52, -0.02), 0.85], [Vector2(0.02, 0.45), 1.05]]
	for d in drops:
		var at: Vector2 = d[0]
		var s: float = d[1]
		_poly(_xf(tip, 0.5, at, s), _tone)
		_circ(at, 0.22 * s, _tone)
		_d_poly(_xf(tip, 0.5, at, s * 0.55), _hi)
		_d_circ(at, 0.11 * s, _hi)


func _g_drain() -> void:
	_circ(Vector2(-0.24, -0.38), 0.37, _tone)
	_circ(Vector2(0.24, -0.38), 0.37, _tone)
	_poly(PackedVector2Array([Vector2(-0.6, -0.24), Vector2(0.6, -0.24), Vector2(0.0, 0.52)]), _tone)
	_d_circ(Vector2(-0.34, -0.5), 0.1, _hi)
	var tip := PackedVector2Array([Vector2(-0.13, -0.04), Vector2(0.13, -0.04), Vector2(0.0, -0.4)])
	for at: Vector2 in [Vector2(-0.46, 0.76), Vector2(0.4, 0.82)]:
		_poly(_xf(tip, 0.0, at), _hi, true)
		_circ(at, 0.14, _hi, true)


func _g_fire() -> void:
	_poly(PackedVector2Array([Vector2(0.05, -0.98), Vector2(0.34, -0.55), Vector2(0.58, -0.1), Vector2(0.58, 0.4), Vector2(0.3, 0.82),
		Vector2(0, 0.92), Vector2(-0.3, 0.82), Vector2(-0.58, 0.4), Vector2(-0.52, -0.05), Vector2(-0.3, -0.32), Vector2(-0.14, -0.1), Vector2(-0.12, -0.55)]), _tone)
	_d_poly(PackedVector2Array([Vector2(0.04, -0.3), Vector2(0.28, 0.05), Vector2(0.32, 0.45), Vector2(0.0, 0.75), Vector2(-0.3, 0.45), Vector2(-0.26, 0.1)]), _hi)


func _g_frost() -> void:
	for k in 3:
		var a := Vector2.from_angle(k * PI / 3.0 + PI * 0.5)
		_stroke(PackedVector2Array([-a * 0.92, a * 0.92]), 0.13, _hi)
		for s: float in [-1.0, 1.0]:
			var base := a * 0.52 * s
			for side: float in [-1.0, 1.0]:
				_stroke(PackedVector2Array([base, base + (a * s).rotated(side * 0.85) * 0.3]), 0.1, _hi)
	_circ(Vector2.ZERO, 0.17, _hi)


func _g_arcane() -> void:
	_circ(Vector2.ZERO, 0.62, _deep)
	_poly(_star(Vector2.ZERO, 0.98, 0.24, 4), _hi)
	_d_poly(_star(Vector2.ZERO, 0.5, 0.2, 4, -PI * 0.25), _tone)
	_d_circ(Vector2.ZERO, 0.13, Color.WHITE)


func _g_holy() -> void:
	for k in 8:
		var a := k * PI * 0.25
		_poly(PackedVector2Array([Vector2.from_angle(a - 0.22) * 0.5, Vector2.from_angle(a) * (0.98 if k % 2 == 0 else 0.8), Vector2.from_angle(a + 0.22) * 0.5]), _tone)
	_circ(Vector2.ZERO, 0.45, _hi)
	_d_circ(Vector2.ZERO, 0.27, _tone)


func _g_skull() -> void:
	_circ(Vector2(0, -0.14), 0.62, _hi)
	_poly(PackedVector2Array([Vector2(-0.36, 0.3), Vector2(0.36, 0.3), Vector2(0.3, 0.8), Vector2(-0.3, 0.8)]), _hi)
	_d_circ(Vector2(-0.25, -0.1), 0.19, OUT)
	_d_circ(Vector2(0.25, -0.1), 0.19, OUT)
	_d_poly(PackedVector2Array([Vector2(0, 0.08), Vector2(-0.09, 0.3), Vector2(0.09, 0.3)]), OUT)
	for x: float in [-0.14, 0.0, 0.14]:
		_d_stroke(PackedVector2Array([Vector2(x, 0.5), Vector2(x, 0.8)]), 0.05, OUT)


func _g_leaf() -> void:
	var a := Vector2(-0.72, 0.72)
	var b := Vector2(0.72, -0.72)
	var axis := (b - a)
	var perp := Vector2(axis.y, -axis.x).normalized()
	var pts := PackedVector2Array()
	for i in 9:
		var t := i / 8.0
		pts.append(a.lerp(b, t) + perp * sin(PI * t) * 0.6)
	for i in range(7, 0, -1):
		var t := i / 8.0
		pts.append(a.lerp(b, t) - perp * sin(PI * t) * 0.6)
	_poly(pts, _tone)
	_stroke(PackedVector2Array([a + Vector2(-0.15, 0.15), b * 0.85]), 0.07, _hi)


func _g_shield() -> void:
	_poly(PackedVector2Array([Vector2(-0.72, -0.78), Vector2(0.72, -0.78), Vector2(0.72, 0.0), Vector2(0.46, 0.52), Vector2(0, 0.96),
		Vector2(-0.46, 0.52), Vector2(-0.72, 0.0)]), _tone)
	_d_poly(PackedVector2Array([Vector2(-0.5, -0.6), Vector2(0.5, -0.6), Vector2(0.5, -0.02), Vector2(0.3, 0.38), Vector2(0, 0.7),
		Vector2(-0.3, 0.38), Vector2(-0.5, -0.02)]), _deep)
	_d_poly(_rect_pts(-0.07, -0.5, 0.07, 0.45), _hi)
	_d_poly(_rect_pts(-0.36, -0.28, 0.36, -0.14), _hi)


func _g_hammer() -> void:
	var a := 0.62
	_poly(_xf(_rect_pts(-0.12, -0.3, 0.12, 0.92), a), Color(0.6, 0.4, 0.22))
	_poly(_xf(_rect_pts(-0.62, -0.84, 0.62, -0.28), a), _hi)
	_d_poly(_xf(_rect_pts(-0.5, -0.76, 0.5, -0.6), a), _tone)


func _g_bolt() -> void:
	_circ(Vector2(0.0, 0.0), 0.62, _deep)
	_poly(PackedVector2Array([Vector2(0.22, -0.98), Vector2(-0.52, 0.1), Vector2(-0.06, 0.1), Vector2(-0.3, 0.98), Vector2(0.56, -0.2),
		Vector2(0.1, -0.2), Vector2(0.5, -0.98)]), _hi)


func _g_bomb() -> void:
	_circ(Vector2(-0.08, 0.24), 0.58, _deep.darkened(0.45))
	_d_circ(Vector2(-0.28, 0.02), 0.13, Color(1, 1, 1, 0.55))
	_stroke(PackedVector2Array([Vector2(0.28, -0.28), Vector2(0.45, -0.52), Vector2(0.62, -0.58)]), 0.09, UiTheme.GOLD_DARK)
	_poly(_star(Vector2(0.58, -0.64), 0.27, 0.09, 4), _hi)
