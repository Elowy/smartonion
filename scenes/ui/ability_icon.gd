class_name AbilityIcon
extends Control
## One ability slot on the HUD / lobby card / Trainer, drawn in code (no image assets yet): a
## gold-rimmed square with a procedural glyph picked by AbilityData.icon (falling back to the
## ability id and then to the school), tinted by AbilityData.color (or the school colour when the
## data leaves the default white). Every shipped ability id has its own glyph (EXACT_GLYPHS);
## the token rules and the school are the fallbacks for new content.
##
## State drawn on top of the glyph (all pushed in by the owner, nothing is read from gameplay):
##  - cooldown sweep: a dark pie that shrinks clockwise (WoW style) + the seconds left (the
##    seconds can be switched off: [member show_cooldown_text], the small auto-cast icons),
##  - dimmed: off cooldown but not usable (resource missing / player down) - darker, the cost in red,
##  - flash: a short white pop when the ability was cast ([method flash_cast]),
##  - the button prompt ("RT", "LMB" ...) as a small pill straddling the bottom edge, the
##    resource cost in the top-right corner,
##  - the rank (GDD 6.3, [method set_rank]): one small gold diamond per rank (I–V) up the left
##    edge, orange once the Rank V specialisation is chosen.
## Empty slots draw a faint socket. The control is SIZE wide and SIZE + PROMPT_OVERHANG tall
## (the prompt pill hangs below the square) unless it is created without the prompt row
## (create(size, false): a plain square for the auto-cast slots and the Trainer list).

enum Glyph {
	GENERIC, PHYSICAL, WHIRLWIND, DASH, BLIZZARD, BLINK, CONSECRATION, HEAL, KNIVES, VANISH,
	RAIN_OF_FIRE, DRAIN, FIRE, FROST, ARCANE, HOLY, SKULL, NATURE, SHIELD, HAMMER, BOLT, BOMB,
	# M4 learned abilities (GDD 6.4), one each.
	THUNDER_CLAP, HEROIC_LEAP, EXECUTE, BATTLE_SHOUT, SHIELD_WALL, BLADESTORM,
	FIREBALL, FROST_NOVA, ARCANE_MISSILES, ICE_BARRIER, PYROBLAST, METEOR,
	AVENGERS_SHIELD, DIVINE_STORM, KINGS, DIVINE_SHIELD, LAY_ON_HANDS,
	SHURIKEN, BLADE_FLURRY, POISON_BOMB, CHEAT_DEATH, SHADOWSTEP, KILLING_SPREE,
	CORRUPTION, SHADOW_BOLT, SEED, VOIDWALKER, FEAR, INFERNAL,
	BANDAGE, SPRINT, WAR_STOMP, SPIRIT_WOLF, BERSERKING,
}

const SIZE := 50.0
const PROMPT_HEIGHT := 22.0
const PROMPT_OVERHANG := 11.0
const PROMPT_FONT := 18
const COOLDOWN_FONT := 22
const COST_FONT := 18
const FLASH_TIME := 0.32
## The cooldown pie is redrawn once it moved this share of a full turn (~1.4 degrees).
const SWEEP_REDRAW_STEP := 0.004
## Glyph half-extent as a share of the half icon size.
const GLYPH_SCALE := 0.74
const OUT := Color(0.05, 0.03, 0.02, 0.95)
## Icons narrower than this use the small text sizes (SMALL_FONT).
const SMALL_ICON := 36.0
const SMALL_FONT := 14
const MAX_RANK := 5
## Rank pips: gold, orange once the Rank V specialisation is chosen.
const RANK_COLOR := Color(1.0, 0.86, 0.38)
const RANK_SPEC_COLOR := Color(1.0, 0.52, 0.12)
const ROMAN: Array[String] = ["", "I", "II", "III", "IV", "V"]

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

## Whole ids first (they win over the token rules): every shipped ability (M3 core kits and the
## M4 pool of GDD 6.4) has its own glyph.
const EXACT_GLYPHS: Dictionary[StringName, Glyph] = {
	# M3 core abilities.
	&"whirlwind": Glyph.WHIRLWIND, &"charge": Glyph.DASH, &"blizzard": Glyph.BLIZZARD,
	&"blink": Glyph.BLINK, &"consecration": Glyph.CONSECRATION, &"word_of_glory": Glyph.HEAL,
	&"fan_of_knives": Glyph.KNIVES, &"vanish": Glyph.VANISH, &"rain_of_fire": Glyph.RAIN_OF_FIRE,
	&"drain_life": Glyph.DRAIN,
	# Warrior.
	&"thunder_clap": Glyph.THUNDER_CLAP, &"heroic_leap": Glyph.HEROIC_LEAP, &"execute": Glyph.EXECUTE,
	&"battle_shout": Glyph.BATTLE_SHOUT, &"shield_wall": Glyph.SHIELD_WALL, &"bladestorm": Glyph.BLADESTORM,
	# Mage.
	&"fireball": Glyph.FIREBALL, &"frost_nova": Glyph.FROST_NOVA, &"arcane_missiles": Glyph.ARCANE_MISSILES,
	&"ice_barrier": Glyph.ICE_BARRIER, &"pyroblast": Glyph.PYROBLAST, &"meteor": Glyph.METEOR,
	# Paladin.
	&"hammer_of_justice": Glyph.HAMMER, &"avengers_shield": Glyph.AVENGERS_SHIELD,
	&"divine_storm": Glyph.DIVINE_STORM, &"blessing_of_kings": Glyph.KINGS,
	&"divine_shield": Glyph.DIVINE_SHIELD, &"lay_on_hands": Glyph.LAY_ON_HANDS,
	# Rogue.
	&"shuriken_toss": Glyph.SHURIKEN, &"blade_flurry": Glyph.BLADE_FLURRY, &"poison_bomb": Glyph.POISON_BOMB,
	&"cheat_death": Glyph.CHEAT_DEATH, &"shadowstep": Glyph.SHADOWSTEP, &"killing_spree": Glyph.KILLING_SPREE,
	# Warlock.
	&"corruption": Glyph.CORRUPTION, &"shadow_bolt": Glyph.SHADOW_BOLT, &"seed_of_corruption": Glyph.SEED,
	&"summon_voidwalker": Glyph.VOIDWALKER, &"fear": Glyph.FEAR, &"summon_infernal": Glyph.INFERNAL,
	# General pool.
	&"bandage": Glyph.BANDAGE, &"sprint": Glyph.SPRINT, &"engineers_bomb": Glyph.BOMB,
	&"war_stomp": Glyph.WAR_STOMP, &"spirit_wolf": Glyph.SPIRIT_WOLF, &"berserking": Glyph.BERSERKING,
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
## Charge counter (Blink with a second charge): shown top-left while charges_max > 1.
var charges := 0
var charges_max := 0
## Rank I–V (0 = not shown, e.g. the lobby preview) and whether the Rank V specialisation is
## chosen (orange pips).
var rank := 0
var rank_spec := false
## The seconds on the cooldown sweep (off on the small auto-cast icons: the sweep says enough).
var show_cooldown_text := true
## Created with the prompt row below the square (see [method create]).
var has_prompt_row := true

## StyleBoxes reused by every draw (a running cooldown redraws every few frames): the fixed
## looks are shared by all icons, the tinted ones belong to the icon and are recoloured.
static var _shared_boxes: Dictionary[StringName, StyleBoxFlat] = {}
var _boxes: Dictionary[StringName, StyleBoxFlat] = {}
var _text_cache := ""
## The sweep ratio of the last queued redraw: small per-tick steps add up until they are worth
## a redraw (comparing with the live ratio would only redraw on whole seconds for long cooldowns).
var _drawn_ratio := -1.0
## Side of the icon square (the control is a little taller: the prompt pill hangs below it).
var _side := SIZE


## [param with_prompt_row] false: a plain square (no room for the button prompt pill below it).
static func create(p_size: float = SIZE, with_prompt_row: bool = true) -> AbilityIcon:
	var i := AbilityIcon.new()
	i._side = p_size
	i.has_prompt_row = with_prompt_row
	i.custom_minimum_size = Vector2(p_size, p_size + (PROMPT_OVERHANG if with_prompt_row else 0.0))
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
			return s.trim_suffix(".")
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


## "I" .. "V" for ranks 1..5 ("" outside).
static func roman(p_rank: int) -> String:
	return ROMAN[p_rank] if p_rank >= 1 and p_rank < ROMAN.size() else ""


# --- State ------------------------------------------------------------------------------

## Rank pips: [param p_rank] 1..5 (0 hides them); [param spec_chosen] turns them orange.
func set_rank(p_rank: int, spec_chosen: bool = false) -> void:
	var r := clampi(p_rank, 0, MAX_RANK)
	if r != rank or spec_chosen != rank_spec:
		rank = r
		rank_spec = spec_chosen
		queue_redraw()


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


## Updates the cost shown in the corner (item mods can change it).
func set_cost(p_cost: float) -> void:
	if not is_equal_approx(p_cost, cost):
		cost = p_cost
		queue_redraw()


## Charge counter; [param p_max] <= 1 hides it.
func set_charges(p_charges: int, p_max: int) -> void:
	if p_charges != charges or p_max != charges_max:
		charges = p_charges
		charges_max = p_max
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
	var changed := text != _text_cache or absf(ratio - _drawn_ratio) >= SWEEP_REDRAW_STEP \
		or dim != dimmed or p_ready != usable
	sweep_ratio = ratio
	cooldown_left = maxf(p_left, 0.0)
	usable = p_ready
	dimmed = dim
	_text_cache = text
	if changed:
		_drawn_ratio = ratio
		queue_redraw()


func cooldown_text() -> String:
	return _text_cache


## Side of the icon square (the control is PROMPT_OVERHANG taller).
func icon_side() -> float:
	return _side


## Width of the button prompt pill (0 without a prompt); it may be wider than the icon.
func prompt_width() -> float:
	if not show_prompt or prompt == "":
		return 0.0
	return maxf(_text_width(prompt, PROMPT_FONT) + 12.0, 28.0)


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
		draw_style_box(_shared_box(&"socket"), rect)
		return
	var base := icon_color
	_tone = base.lightened(0.35)
	_hi = base.lightened(0.7)
	_deep = base.darkened(0.1)

	var bg := _own_box(&"bg")
	bg.bg_color = base.darkened(0.72)
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
		draw_style_box(_shared_box(&"dim"), rect)
	elif sweep_ratio > 0.004:
		# A light veil over the whole icon keeps the seconds readable on a busy glyph.
		draw_style_box(_shared_box(&"veil"), rect)
		var poly := sweep_polygon(rect.grow(-2.0), sweep_ratio)
		if poly.size() >= 3:
			draw_colored_polygon(poly, Color(0, 0, 0, 0.7))
			if sweep_ratio < 0.996:
				draw_line(poly[0], poly[1], Color(1, 1, 1, 0.5), 1.5)
	if flash > 0.0:
		var f := _own_box(&"flash")
		f.bg_color = Color(1, 0.97, 0.85, 0.7 * flash)
		draw_style_box(f, rect)

	var border := UiTheme.GOLD_BORDER if usable else (UiTheme.GOLD_DARK if sweep_ratio > 0.004 else Color(0.34, 0.3, 0.24))
	draw_style_box(_shared_box(&"outer"), rect.grow(1.0))
	var rim := _own_box(&"rim")
	rim.draw_center = false
	rim.border_color = UiTheme.GOLD_BRIGHT if flash > 0.3 else border
	rim.set_border_width_all(2)
	draw_style_box(rim, rect)

	var small := sq < SMALL_ICON
	var corner_font := SMALL_FONT if small else COST_FONT
	var corner_y := corner_font * 0.6 + 0.5
	if _text_cache != "" and show_cooldown_text:
		_text(_text_cache, rect.get_center(), SMALL_FONT + 2 if small else COOLDOWN_FONT, UiTheme.TEXT)
	if cost > 0.0:
		var label := UiTheme.format_amount(cost)
		var color := UiTheme.RED.lightened(0.15) if dimmed else cost_color.lightened(0.5)
		var w := _text_width(label, corner_font)
		_text(label, Vector2(sq - w * 0.5 - 3.0, corner_y), corner_font, color, 5)
	if charges_max > 1:
		var count := str(charges)
		var cw := _text_width(count, corner_font)
		# Right of the rank pips' column.
		var left := 4.0 + (rank_pip_size(sq) * 2.0 + 1.0 if rank > 0 else 0.0)
		_text(count, Vector2(cw * 0.5 + left, corner_y), corner_font, UiTheme.GOLD_BRIGHT if charges > 0 else UiTheme.RED.lightened(0.15), 5)
	if rank > 0:
		_draw_rank(sq)
	if show_prompt and prompt != "":
		_draw_prompt(sq)


## Half-size of one rank diamond on an icon of side [param sq].
static func rank_pip_size(sq: float) -> float:
	return maxf(1.7, sq * 0.05)


## Centres of the rank pips (bottom one first) on an icon of side [param sq]; [param above_prompt]
## keeps them clear of the prompt pill hanging over the bottom edge.
static func rank_pip_centers(sq: float, count: int, above_prompt: bool) -> PackedVector2Array:
	var r := rank_pip_size(sq)
	var step := r * 2.0 + maxf(0.8, sq * 0.026)
	var bottom := (sq - PROMPT_OVERHANG - 2.0 if above_prompt else sq - 2.5) - r
	var out := PackedVector2Array()
	for i in clampi(count, 0, MAX_RANK):
		out.append(Vector2(2.5 + r, bottom - i * step))
	return out


## One small diamond per rank up the left edge (GDD 12: rank shown on every icon).
func _draw_rank(sq: float) -> void:
	var r := rank_pip_size(sq)
	var fill := RANK_SPEC_COLOR if rank_spec else RANK_COLOR
	for c in rank_pip_centers(sq, rank, show_prompt and prompt != ""):
		var o := r + 1.2
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -o), c + Vector2(o, 0), c + Vector2(0, o), c + Vector2(-o, 0)]), OUT)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), fill)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.7), c + Vector2(r * 0.45, -r * 0.1), c + Vector2(-r * 0.45, -r * 0.1)]), Color(1, 1, 1, 0.55))


## A small gear (auto-cast mark) centred on [param center] with outer radius [param r].
static func draw_gear(ci: CanvasItem, center: Vector2, r: float, fill: Color, outline: Color = OUT) -> void:
	var teeth := 8
	var pts := PackedVector2Array()
	for i in teeth * 4:
		var a := TAU * (i / float(teeth * 4)) - PI * 0.5
		var tooth := (i % 4) < 2
		pts.append(center + Vector2(cos(a), sin(a)) * (r if tooth else r * 0.74))
	var ring := pts.duplicate()
	ring.append(pts[0])
	ci.draw_polyline(ring, outline, maxf(1.5, r * 0.22), true)
	ci.draw_colored_polygon(pts, fill)
	ci.draw_circle(center, r * 0.36, outline, true, -1.0, true)
	ci.draw_circle(center, r * 0.2, fill.darkened(0.5), true, -1.0, true)


## A StyleBoxFlat shared by every icon (socket, dim, veil, outer): built once, never changed.
static func _shared_box(key: StringName) -> StyleBoxFlat:
	var s: StyleBoxFlat = _shared_boxes.get(key)
	if s != null:
		return s
	s = StyleBoxFlat.new()
	s.set_corner_radius_all(5)
	match key:
		&"socket":
			s.bg_color = Color(0.03, 0.025, 0.02, 0.45)
			s.border_color = Color(UiTheme.GOLD_DARK, 0.5)
			s.set_border_width_all(2)
		&"dim":
			s.bg_color = Color(0.03, 0.035, 0.07, 0.66)
		&"veil":
			s.bg_color = Color(0, 0, 0, 0.3)
		&"outer":
			s.draw_center = false
			s.border_color = Color(0, 0, 0, 0.9)
			s.set_border_width_all(1)
			s.set_corner_radius_all(6)
	_shared_boxes[key] = s
	return s


## This icon's own StyleBoxFlat [param key] (bg, flash, rim, prompt), recoloured by _draw.
func _own_box(key: StringName) -> StyleBoxFlat:
	var s: StyleBoxFlat = _boxes.get(key)
	if s == null:
		s = StyleBoxFlat.new()
		s.set_corner_radius_all(5)
		s.anti_aliasing = true
		_boxes[key] = s
	return s


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
	var w := prompt_width()
	var pill := Rect2(sq * 0.5 - w * 0.5, sq - PROMPT_OVERHANG, w, PROMPT_HEIGHT)
	var style := _own_box(&"prompt")
	style.set_corner_radius_all(int(PROMPT_HEIGHT * 0.5) if not prompt_keyboard else 5)
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


## Point at [param t] on the quadratic Bezier p0 -> p1 -> p2.
static func _bez(p0: Vector2, p1: Vector2, p2: Vector2, t: float) -> Vector2:
	return p0.lerp(p1, t).lerp(p1.lerp(p2, t), t)


## Points on an ellipse arc from angle [param a0] to [param a1] (radians, 0 = right, clockwise).
static func _arc_pts(center: Vector2, radii: Vector2, a0: float, a1: float, n: int = 16) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(a0, a1, i / float(n))
		out.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return out


## A heater shield outline around [param center], [param s] = 1 about the size of _g_shield.
static func _heater(center: Vector2, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v: Vector2 in [Vector2(-0.72, -0.78), Vector2(0.72, -0.78), Vector2(0.72, 0.0), Vector2(0.46, 0.52),
			Vector2(0, 0.96), Vector2(-0.46, 0.52), Vector2(-0.72, 0.0)]:
		out.append(center + v * s)
	return out


## A star whose valleys are turned by [param skew] (radians): curved, spinning blades / flames.
static func _pinwheel(center: Vector2, outer: float, inner: float, points: int, skew: float, rot: float = -PI * 0.5) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in points:
		var a := rot + TAU * i / float(points)
		out.append(center + Vector2(cos(a), sin(a)) * outer)
		var v := a + PI / float(points) + skew
		out.append(center + Vector2(cos(v), sin(v)) * inner)
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
		Glyph.THUNDER_CLAP: _g_thunder_clap()
		Glyph.HEROIC_LEAP: _g_heroic_leap()
		Glyph.EXECUTE: _g_execute()
		Glyph.BATTLE_SHOUT: _g_battle_shout()
		Glyph.SHIELD_WALL: _g_shield_wall()
		Glyph.BLADESTORM: _g_bladestorm()
		Glyph.FIREBALL: _g_fireball()
		Glyph.FROST_NOVA: _g_frost_nova()
		Glyph.ARCANE_MISSILES: _g_arcane_missiles()
		Glyph.ICE_BARRIER: _g_ice_barrier()
		Glyph.PYROBLAST: _g_pyroblast()
		Glyph.METEOR: _g_meteor()
		Glyph.AVENGERS_SHIELD: _g_avengers_shield()
		Glyph.DIVINE_STORM: _g_divine_storm()
		Glyph.KINGS: _g_kings()
		Glyph.DIVINE_SHIELD: _g_divine_shield()
		Glyph.LAY_ON_HANDS: _g_lay_on_hands()
		Glyph.SHURIKEN: _g_shuriken()
		Glyph.BLADE_FLURRY: _g_blade_flurry()
		Glyph.POISON_BOMB: _g_poison_bomb()
		Glyph.CHEAT_DEATH: _g_cheat_death()
		Glyph.SHADOWSTEP: _g_shadowstep()
		Glyph.KILLING_SPREE: _g_killing_spree()
		Glyph.CORRUPTION: _g_corruption()
		Glyph.SHADOW_BOLT: _g_shadow_bolt()
		Glyph.SEED: _g_seed()
		Glyph.VOIDWALKER: _g_voidwalker()
		Glyph.FEAR: _g_fear()
		Glyph.INFERNAL: _g_infernal()
		Glyph.BANDAGE: _g_bandage()
		Glyph.SPRINT: _g_sprint()
		Glyph.WAR_STOMP: _g_war_stomp()
		Glyph.SPIRIT_WOLF: _g_spirit_wolf()
		Glyph.BERSERKING: _g_berserking()
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


# --- M4 glyphs (GDD 6.4) -----------------------------------------------------------------

func _g_thunder_clap() -> void:
	# Shock rings on the ground around a thunder strike.
	_stroke(_arc_pts(Vector2(0, 0.46), Vector2(0.92, 0.38), 0.0, TAU, 28), 0.1, _tone)
	_stroke(_arc_pts(Vector2(0, 0.46), Vector2(0.5, 0.19), 0.0, TAU, 20), 0.09, _hi)
	_poly(PackedVector2Array([Vector2(0.14, -0.98), Vector2(-0.36, -0.16), Vector2(-0.04, -0.16), Vector2(-0.22, 0.5),
		Vector2(0.4, -0.34), Vector2(0.08, -0.34), Vector2(0.46, -0.98)]), _hi, true)


func _g_heroic_leap() -> void:
	# A dashed leap arc landing in an impact burst.
	var p0 := Vector2(-0.88, 0.72)
	var p1 := Vector2(-0.3, -1.3)
	var p2 := Vector2(0.4, 0.28)
	_poly(_star(Vector2(0.56, 0.62), 0.4, 0.16, 7), _deep)
	for seg: Vector2 in [Vector2(0.0, 0.22), Vector2(0.32, 0.54), Vector2(0.64, 0.84)]:
		var pts := PackedVector2Array()
		for k in 6:
			pts.append(_bez(p0, p1, p2, lerpf(seg.x, seg.y, k / 5.0)))
		_stroke(pts, 0.14, _tone)
	var dir := (p2 - p1).normalized()
	var n := Vector2(-dir.y, dir.x)
	var base := _bez(p0, p1, p2, 0.88)
	_poly(PackedVector2Array([base + n * 0.26, p2 + dir * 0.16, base - n * 0.26]), _hi)


func _g_execute() -> void:
	# The executioner's axe: a long haft and a bearded crescent blade.
	var a := 0.5
	var at := Vector2(0.16, 0.08)
	_poly(_xf(_rect_pts(-0.08, -0.78, 0.08, 0.98), a, at), Color(0.55, 0.36, 0.2))
	var blade := PackedVector2Array([Vector2(0.04, -0.72), Vector2(-0.22, -0.64), Vector2(-0.5, -0.9), Vector2(-0.78, -0.62),
		Vector2(-0.9, -0.26), Vector2(-0.8, 0.1), Vector2(-0.56, 0.32), Vector2(-0.26, -0.02), Vector2(0.04, 0.0)])
	_poly(_xf(blade, a, at), _hi)
	_d_poly(_xf(PackedVector2Array([Vector2(-0.6, -0.78), Vector2(-0.82, -0.26), Vector2(-0.64, 0.2), Vector2(-0.56, 0.16),
		Vector2(-0.7, -0.26), Vector2(-0.5, -0.74)]), a, at), Color(1, 1, 1, 0.7))
	_d_poly(_xf(_rect_pts(-0.26, -0.5, 0.04, -0.2), a, at), _tone.darkened(0.2))
	_circ(_xf(PackedVector2Array([Vector2(0.0, -0.36)]), a, at)[0], 0.09, UiTheme.GOLD_BORDER)


func _g_battle_shout() -> void:
	# A war horn with sound waves.
	var p0 := Vector2(-0.92, 0.52)
	var p1 := Vector2(-0.3, 0.62)
	var p2 := Vector2(0.12, -0.12)
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in 11:
		var t := i / 10.0
		var c := _bez(p0, p1, p2, t)
		var d := (_bez(p0, p1, p2, minf(1.0, t + 0.05)) - _bez(p0, p1, p2, maxf(0.0, t - 0.05))).normalized()
		var w := 0.07 + 0.36 * pow(t, 1.7)
		left.append(c + Vector2(-d.y, d.x) * w)
		right.append(c - Vector2(-d.y, d.x) * w)
	right.reverse()
	left.append_array(right)
	_poly(left, _tone)
	for t: float in [0.35, 0.68]:
		var c := _bez(p0, p1, p2, t)
		var d := (_bez(p0, p1, p2, t + 0.05) - c).normalized()
		var w := 0.07 + 0.36 * pow(t, 1.7)
		_d_stroke(PackedVector2Array([c + Vector2(-d.y, d.x) * w, c - Vector2(-d.y, d.x) * w]), 0.09, UiTheme.GOLD_BORDER)
	var mouth := (p2 - p1).normalized()
	var ang := mouth.angle()
	_poly(_xf(_ellipse(Vector2.ZERO, 0.12, 0.42, 16), ang, p2), _hi)
	for r: float in [0.42, 0.68]:
		_stroke(_arc_pts(p2 + mouth * 0.08, Vector2(r, r), ang - 0.62, ang + 0.62, 8), 0.08, _hi)


func _g_shield_wall() -> void:
	# A wall of three shields, the middle one in front.
	for x: float in [-0.62, 0.62]:
		_poly(_heater(Vector2(x, -0.3), 0.56), _tone.darkened(0.3), true)
		_d_poly(_heater(Vector2(x, -0.3), 0.36), _deep.darkened(0.35))
	_poly(_heater(Vector2(0, 0.12), 0.74), _tone, true)
	_d_poly(_heater(Vector2(0, 0.12), 0.52), _deep)
	_d_poly(_rect_pts(-0.07, -0.34, 0.07, 0.5), _hi)
	_d_poly(_rect_pts(-0.3, -0.14, 0.3, -0.01), _hi)


func _g_bladestorm() -> void:
	# Four blades spinning around a hub, with motion arcs.
	for k in 4:
		var a := k * PI * 0.5 + 0.4
		var dir := a - PI * 0.5
		_d_stroke(_arc_pts(Vector2.ZERO, Vector2(0.66, 0.66), dir - 1.3, dir - 0.35, 8), 0.06, Color(_tone, 0.75))
	var blade := PackedVector2Array([Vector2(-0.1, -0.24), Vector2(-0.1, -0.7), Vector2(0, -0.98), Vector2(0.1, -0.7), Vector2(0.1, -0.24)])
	for k in 4:
		var a := k * PI * 0.5 + 0.4
		_poly(_xf(blade, a), _hi)
		_poly(_xf(_rect_pts(-0.22, -0.28, 0.22, -0.18), a), UiTheme.GOLD_BORDER)
	_circ(Vector2.ZERO, 0.2, _tone)
	_d_circ(Vector2.ZERO, 0.08, _deep)


func _g_fireball() -> void:
	# A ball of fire with a flame tail.
	var c := Vector2(-0.26, 0.28)
	_poly(PackedVector2Array([Vector2(-0.66, 0.06), Vector2(-0.26, -0.5), Vector2(0.02, -0.96), Vector2(0.16, -0.5),
		Vector2(0.52, -0.86), Vector2(0.5, -0.36), Vector2(0.96, -0.46), Vector2(0.54, 0.02), Vector2(0.2, 0.62),
		Vector2(-0.3, 0.8)]), _tone)
	_circ(c, 0.52, _tone)
	_d_poly(PackedVector2Array([Vector2(-0.4, -0.06), Vector2(0.04, -0.56), Vector2(0.14, -0.2), Vector2(0.5, -0.36),
		Vector2(0.2, 0.2)]), _hi)
	_d_circ(c, 0.38, _hi)
	_d_circ(c + Vector2(-0.04, 0.04), 0.2, Color(1, 1, 0.9))


func _g_frost_nova() -> void:
	# Ice spikes bursting out of a frozen ring.
	for k in 8:
		var d := Vector2.from_angle(k * PI * 0.25 - PI * 0.5)
		var n := Vector2(-d.y, d.x)
		var tip := d * (0.98 if k % 2 == 0 else 0.76)
		_poly(PackedVector2Array([d * 0.36 + n * 0.16, tip, d * 0.36 - n * 0.16]), _hi if k % 2 == 0 else _tone)
	_circ(Vector2.ZERO, 0.42, _tone)
	_d_circ(Vector2.ZERO, 0.28, _deep)
	_d_poly(_star(Vector2.ZERO, 0.24, 0.08, 6), _hi)


func _g_arcane_missiles() -> void:
	# Three arcane bolts streaking up and to the right.
	var d := Vector2(0.707, -0.707)
	var n := Vector2(0.707, 0.707)
	for o: Array in [[Vector2(0.5, -0.5), 0.26], [Vector2(0.04, 0.04), 0.22], [Vector2(-0.42, 0.52), 0.18]]:
		var at: Vector2 = o[0]
		var r: float = o[1]
		_poly(PackedVector2Array([at + n * r * 0.82, at - d * r * 3.0, at - n * r * 0.82]), Color(_tone, 0.85))
		_circ(at, r, _hi)
		_d_circ(at, r * 0.5, Color.WHITE)
	_d_poly(_star(Vector2(0.62, 0.36), 0.2, 0.06, 4), _hi)
	_d_poly(_star(Vector2(-0.52, -0.42), 0.16, 0.05, 4), _hi)


func _g_ice_barrier() -> void:
	# A faceted hexagonal ice crystal.
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for k in 6:
		var v := Vector2.from_angle(k * TAU / 6.0 - PI * 0.5)
		outer.append(v * 0.96)
		inner.append(v * 0.52)
	_poly(outer, _tone)
	_d_poly(inner, _deep)
	for k in 6:
		_d_stroke(PackedVector2Array([inner[k], outer[k]]), 0.06, _hi)
	var ring := inner.duplicate()
	ring.append(inner[0])
	_d_stroke(ring, 0.07, _hi)
	_d_poly(PackedVector2Array([outer[5], outer[0], inner[0], inner[5]]), Color(1, 1, 1, 0.35))
	_d_poly(_star(Vector2.ZERO, 0.3, 0.1, 6), _hi)


func _g_pyroblast() -> void:
	# A huge swirling fireball.
	_poly(_pinwheel(Vector2.ZERO, 0.98, 0.62, 9, 0.22), _tone)
	_d_circ(Vector2.ZERO, 0.6, _hi)
	_d_poly(_pinwheel(Vector2.ZERO, 0.5, 0.3, 6, 0.3, 0.3), Color(1, 0.95, 0.75))
	_d_circ(Vector2.ZERO, 0.2, Color.WHITE)


func _g_meteor() -> void:
	# A burning rock falling out of the sky on a long flame trail.
	var c := Vector2(-0.34, 0.36)
	var dir := Vector2(0.72, -0.7).normalized()
	var n := Vector2(-dir.y, dir.x)
	_poly(PackedVector2Array([c + n * 0.5, c + n * 0.34 + dir * 0.7, c + dir * 1.42 + n * 0.06, c + n * 0.02 + dir * 0.9,
		c - n * 0.2 + dir * 1.25, c - n * 0.34 + dir * 0.6, c - n * 0.5]), _tone)
	_d_poly(PackedVector2Array([c + n * 0.28, c + n * 0.1 + dir * 0.95, c - n * 0.28]), _hi)
	var rock := PackedVector2Array()
	var radii: Array[float] = [0.5, 0.42, 0.52, 0.44, 0.5, 0.4, 0.48, 0.44]
	for i in radii.size():
		rock.append(c + Vector2.from_angle(TAU * i / radii.size() + 0.3) * radii[i])
	_poly(rock, Color(0.36, 0.24, 0.18), true)
	_d_stroke(PackedVector2Array([c + Vector2(-0.26, -0.06), c + Vector2(0.0, 0.06), c + Vector2(0.14, -0.2)]), 0.07, _hi)
	_d_stroke(PackedVector2Array([c + Vector2(-0.1, 0.28), c + Vector2(0.1, 0.1)]), 0.06, _hi)
	_d_circ(c + Vector2(0.2, 0.22), 0.08, Color(0.22, 0.14, 0.1))


func _g_avengers_shield() -> void:
	# A round shield thrown with motion lines behind it.
	var c := Vector2(0.18, 0.04)
	for k in 3:
		var y := -0.38 + k * 0.38
		_stroke(PackedVector2Array([Vector2(-0.98, y + 0.12), Vector2(-0.58, y)]), 0.09, Color(_tone, 0.8))
	_circ(c, 0.76, _tone)
	_d_circ(c, 0.6, _deep)
	_d_circ(c, 0.48, _tone.darkened(0.1))
	_d_poly(_star(c, 0.4, 0.16, 5), _hi)


func _g_divine_storm() -> void:
	# A three-armed whirl of holy light.
	for k in 3:
		var pts := PackedVector2Array()
		for i in 12:
			var t := i / 11.0
			var a := k * TAU / 3.0 + t * 2.0
			pts.append(Vector2.from_angle(a) * (0.26 + 0.7 * t))
		_stroke(pts, 0.18, _hi if k == 0 else _tone)
	_circ(Vector2.ZERO, 0.3, _hi)
	_d_poly(_star(Vector2.ZERO, 0.24, 0.08, 4), Color.WHITE)


func _g_kings() -> void:
	# A crown.
	_poly(PackedVector2Array([Vector2(-0.82, 0.5), Vector2(-0.92, -0.42), Vector2(-0.44, 0.0), Vector2(0.0, -0.72),
		Vector2(0.44, 0.0), Vector2(0.92, -0.42), Vector2(0.82, 0.5)]), _hi)
	_poly(_rect_pts(-0.86, 0.4, 0.86, 0.78), _tone)
	for p: Vector2 in [Vector2(-0.92, -0.5), Vector2(0.0, -0.82), Vector2(0.92, -0.5)]:
		_circ(p, 0.14, _tone)
	for x: float in [-0.48, 0.0, 0.48]:
		_d_circ(Vector2(x, 0.59), 0.1 if x == 0.0 else 0.08, Color(0.85, 0.2, 0.25) if x == 0.0 else Color(0.3, 0.55, 1.0))


func _g_divine_shield() -> void:
	# A golden bubble with a cross inside.
	_circ(Vector2.ZERO, 0.94, Color(_tone, 0.32))
	_d_stroke(_arc_pts(Vector2.ZERO, Vector2(0.86, 0.86), 0.0, TAU, 32), 0.1, _hi)
	_d_stroke(_arc_pts(Vector2.ZERO, Vector2(0.64, 0.64), PI * 1.08, PI * 1.42, 8), 0.1, Color(1, 1, 1, 0.8))
	_poly(_rect_pts(-0.11, -0.5, 0.11, 0.52), _hi, true)
	_poly(_rect_pts(-0.34, -0.24, 0.34, -0.04), _hi, true)


func _g_lay_on_hands() -> void:
	# An open palm in a glow of light.
	_d_circ(Vector2(0, -0.1), 0.9, Color(_hi, 0.22))
	for k in 5:
		var a := -PI * 0.5 + (k - 2) * 0.5
		_d_stroke(PackedVector2Array([Vector2.from_angle(a) * 0.72 + Vector2(0, -0.08), Vector2.from_angle(a) * 0.95 + Vector2(0, -0.08)]), 0.06, _hi)
	_poly(PackedVector2Array([Vector2(-0.42, -0.1), Vector2(0.42, -0.1), Vector2(0.46, 0.42), Vector2(0.26, 0.86),
		Vector2(-0.26, 0.86), Vector2(-0.5, 0.42)]), _hi)
	for f: Vector2 in [Vector2(-0.31, -0.5), Vector2(-0.1, -0.64), Vector2(0.11, -0.62), Vector2(0.32, -0.46)]:
		_stroke(PackedVector2Array([Vector2(f.x, 0.0), f]), 0.19, _hi)
	_stroke(PackedVector2Array([Vector2(-0.42, 0.36), Vector2(-0.76, 0.0)]), 0.19, _hi)
	_d_stroke(PackedVector2Array([Vector2(-0.18, 0.32), Vector2(0.2, 0.36)]), 0.04, Color(_deep, 0.6))


func _g_shuriken() -> void:
	# A four-bladed throwing star.
	_poly(_pinwheel(Vector2.ZERO, 0.98, 0.3, 4, 0.36, -PI * 0.25), _hi)
	_d_poly(_pinwheel(Vector2.ZERO, 0.58, 0.2, 4, 0.36, -PI * 0.25), _tone)
	_d_circ(Vector2.ZERO, 0.15, OUT)


func _g_blade_flurry() -> void:
	# Two crossed daggers in a flurry of slashes.
	_d_stroke(_arc_pts(Vector2(0, 0.12), Vector2(0.92, 0.92), PI * 1.05, PI * 1.42, 8), 0.07, Color(_tone, 0.8))
	_d_stroke(_arc_pts(Vector2(0, 0.12), Vector2(0.92, 0.92), PI * 1.58, PI * 1.95, 8), 0.07, Color(_tone, 0.8))
	var blade := PackedVector2Array([Vector2(-0.1, 0.12), Vector2(-0.1, -0.62), Vector2(0, -0.96), Vector2(0.1, -0.62), Vector2(0.1, 0.12)])
	for a: float in [-0.6, 0.6]:
		var at := Vector2(0, 0.18)
		_poly(_xf(blade, a, at), _hi, true)
		_poly(_xf(_rect_pts(-0.26, 0.12, 0.26, 0.22), a, at), UiTheme.GOLD_BORDER, true)
		_poly(_xf(_rect_pts(-0.07, 0.22, 0.07, 0.6), a, at), Color(0.4, 0.26, 0.16), true)


func _g_poison_bomb() -> void:
	# A corked flask of bubbling poison.
	var glass := Color(0.16, 0.2, 0.18)
	_poly(_rect_pts(-0.18, -0.62, 0.18, -0.12), glass)
	_circ(Vector2(0, 0.32), 0.6, glass)
	_d_circ(Vector2(0, 0.38), 0.5, _tone)
	_d_poly(_rect_pts(-0.5, 0.08, 0.5, 0.2), _tone)
	_d_circ(Vector2(-0.22, 0.12), 0.1, _hi)
	_d_circ(Vector2(0.18, 0.42), 0.08, _hi)
	_d_circ(Vector2(-0.05, 0.62), 0.06, _hi)
	_d_stroke(PackedVector2Array([Vector2(-0.4, 0.2), Vector2(-0.3, 0.02)]), 0.06, Color(1, 1, 1, 0.5))
	_poly(_rect_pts(-0.24, -0.84, 0.24, -0.6), Color(0.55, 0.36, 0.2))
	_circ(Vector2(0.46, -0.7), 0.14, Color(_tone, 0.8), true)
	_circ(Vector2(0.66, -0.9), 0.1, Color(_tone, 0.6), true)


func _g_cheat_death() -> void:
	# Two fanned playing cards, an ace of spades in front.
	var card := _rect_pts(-0.42, -0.66, 0.42, 0.66)
	_poly(_xf(card, -0.32, Vector2(-0.22, 0.06)), Color(0.55, 0.14, 0.18), true)
	_d_poly(_xf(_rect_pts(-0.3, -0.54, 0.3, 0.54), -0.32, Vector2(-0.22, 0.06)), Color(0.42, 0.1, 0.13))
	var a := 0.2
	var at := Vector2(0.2, 0.0)
	_poly(_xf(card, a, at), Color(0.95, 0.92, 0.86), true)
	var ink := Color(0.12, 0.08, 0.12)
	_d_poly(_xf(PackedVector2Array([Vector2(0, -0.4), Vector2(0.3, -0.02), Vector2(-0.3, -0.02)]), a, at), ink)
	for x: float in [-0.15, 0.15]:
		_d_circ(Vector2(x, 0.02).rotated(a) + at, 0.16, ink)
	_d_poly(_xf(PackedVector2Array([Vector2(0, 0.02), Vector2(0.13, 0.34), Vector2(-0.13, 0.34)]), a, at), ink)


func _g_shadowstep() -> void:
	# Footprints: a faded one in a puff of shadow, then the next step far ahead.
	for p: Vector2 in [Vector2(-0.68, 0.62), Vector2(-0.3, 0.78), Vector2(-0.6, 0.2)]:
		_circ(p, 0.16, Color(_tone, 0.45), true)
	for f: Array in [[Vector2(-0.42, 0.42), -0.25, Color(_tone, 0.6)], [Vector2(0.36, -0.28), 0.3, _hi]]:
		var c: Vector2 = f[0]
		var a: float = f[1]
		var col: Color = f[2]
		_poly(_xf(_ellipse(Vector2(0, -0.14), 0.22, 0.33, 16), a, c), col, true)
		_poly(_xf(_ellipse(Vector2(0, 0.36), 0.16, 0.16, 12), a, c), col, true)


func _g_killing_spree() -> void:
	# A zig-zag of strikes from foe to foe.
	var path := PackedVector2Array([Vector2(-0.88, 0.64), Vector2(-0.38, -0.4), Vector2(0.08, 0.5), Vector2(0.54, -0.42)])
	_stroke(path, 0.13, _tone)
	var dir := (path[3] - path[2]).normalized()
	var n := Vector2(-dir.y, dir.x)
	_poly(PackedVector2Array([path[3] + n * 0.24, path[3] + dir * 0.4, path[3] - n * 0.24]), _hi)
	for v: Vector2 in [path[1], path[2]]:
		_poly(_star(v, 0.3, 0.09, 4, PI * 0.25), _hi, true)


func _g_corruption() -> void:
	# A dripping blob of corruption.
	var blob := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		var r := 0.62 + 0.07 * sin(a * 5.0)
		blob.append(Vector2(0, -0.22) + Vector2(cos(a) * r * 1.2, sin(a) * r * 0.86))
	for d: Vector2 in [Vector2(-0.46, 0.66), Vector2(0.06, 0.88), Vector2(0.52, 0.58)]:
		_poly(_ellipse(Vector2(d.x, (0.2 + d.y) * 0.5), 0.1, (d.y - 0.2) * 0.5 + 0.06, 12), _tone)
		_circ(d, 0.14, _tone)
	_poly(blob, _tone)
	_d_circ(Vector2(-0.26, -0.3), 0.15, _deep.darkened(0.45))
	_d_circ(Vector2(0.26, -0.06), 0.11, _deep.darkened(0.45))
	_d_circ(Vector2(0.34, -0.46), 0.07, _deep.darkened(0.45))
	_d_circ(Vector2(-0.5, -0.5), 0.1, _hi)


func _g_shadow_bolt() -> void:
	# A dark orb with a swirling core on a smooth comet tail.
	var c := Vector2(0.26, -0.26)
	var d := Vector2(-0.707, 0.707)
	var n := Vector2(0.707, 0.707)
	_poly(PackedVector2Array([c + n * 0.42, c + d * 1.28, c - n * 0.42]), Color(_tone, 0.8))
	_d_poly(PackedVector2Array([c + n * 0.2, c + d * 0.98, c - n * 0.2]), Color(_hi, 0.7))
	_circ(c, 0.52, _deep.darkened(0.45))
	_d_circ(c, 0.42, _tone)
	_d_circ(c, 0.3, _deep.darkened(0.6))
	var swirl := PackedVector2Array()
	for i in 12:
		var t := i / 11.0
		swirl.append(c + Vector2.from_angle(t * 4.4) * (0.04 + 0.22 * t))
	_d_stroke(swirl, 0.06, _hi)


func _g_seed() -> void:
	# A dark seed with a sprouting tendril.
	_d_circ(Vector2(-0.06, 0.18), 0.86, Color(_tone, 0.18))
	_stroke(PackedVector2Array([Vector2(0.16, -0.36), Vector2(0.32, -0.68), Vector2(0.62, -0.84)]), 0.08, _hi)
	_poly(_xf(_ellipse(Vector2.ZERO, 0.2, 0.1, 12), -0.5, Vector2(0.62, -0.84)), _hi, true)
	_poly(_xf(_ellipse(Vector2.ZERO, 0.42, 0.66, 20), 0.45, Vector2(-0.08, 0.2)), _tone)
	_d_stroke(_xf(PackedVector2Array([Vector2(0, -0.5), Vector2(0.08, 0.0), Vector2(0, 0.5)]), 0.45, Vector2(-0.08, 0.2)), 0.07, _deep.darkened(0.4))
	_d_circ(Vector2(-0.3, 0.0), 0.08, _hi)


func _g_voidwalker() -> void:
	# The hulking void servant: broad shoulders, glowing eyes, golden bracers.
	_poly(PackedVector2Array([Vector2(-0.96, 0.96), Vector2(-0.9, 0.24), Vector2(-0.52, -0.06), Vector2(0.52, -0.06),
		Vector2(0.9, 0.24), Vector2(0.96, 0.96)]), _deep)
	_circ(Vector2(0, -0.4), 0.44, _tone)
	_d_poly(PackedVector2Array([Vector2(-0.3, -0.48), Vector2(-0.06, -0.4), Vector2(-0.1, -0.3), Vector2(-0.3, -0.38)]), Color(1, 0.96, 0.7))
	_d_poly(_mirror(PackedVector2Array([Vector2(-0.3, -0.48), Vector2(-0.06, -0.4), Vector2(-0.1, -0.3), Vector2(-0.3, -0.38)])), Color(1, 0.96, 0.7))
	_poly(_rect_pts(-0.98, 0.46, -0.6, 0.74), UiTheme.GOLD_BORDER, true)
	_poly(_rect_pts(0.6, 0.46, 0.98, 0.74), UiTheme.GOLD_BORDER, true)
	_d_stroke(PackedVector2Array([Vector2(-0.3, 0.3), Vector2(0.3, 0.3)]), 0.05, Color(_hi, 0.5))


func _g_fear() -> void:
	# A wailing ghost face.
	var ghost := _arc_pts(Vector2(0, -0.16), Vector2(0.7, 0.7), PI, TAU, 14)
	for v: Vector2 in [Vector2(0.7, 0.72), Vector2(0.46, 0.94), Vector2(0.23, 0.72), Vector2(0.0, 0.94),
			Vector2(-0.23, 0.72), Vector2(-0.46, 0.94), Vector2(-0.7, 0.72)]:
		ghost.append(v)
	_poly(ghost, _hi)
	_d_poly(_ellipse(Vector2(-0.25, -0.22), 0.13, 0.19, 12), OUT)
	_d_poly(_ellipse(Vector2(0.25, -0.22), 0.13, 0.19, 12), OUT)
	_d_poly(_ellipse(Vector2(0, 0.28), 0.16, 0.25, 14), OUT)


func _g_infernal() -> void:
	# A horned demon head of rock in fel fire.
	_poly(PackedVector2Array([Vector2(-0.5, -0.3), Vector2(-0.34, -0.8), Vector2(-0.12, -0.5), Vector2(0.04, -0.98),
		Vector2(0.18, -0.52), Vector2(0.38, -0.82), Vector2(0.5, -0.3)]), _tone)
	var horn := PackedVector2Array([Vector2(-0.44, -0.3), Vector2(-0.96, -0.7), Vector2(-0.66, -0.02)])
	_poly(horn, Color(0.85, 0.8, 0.66))
	_poly(_mirror(horn), Color(0.85, 0.8, 0.66))
	_poly(PackedVector2Array([Vector2(-0.56, -0.38), Vector2(0.56, -0.38), Vector2(0.64, 0.3), Vector2(0.3, 0.88),
		Vector2(-0.3, 0.88), Vector2(-0.64, 0.3)]), Color(0.3, 0.25, 0.22))
	var eye := PackedVector2Array([Vector2(-0.4, -0.12), Vector2(-0.08, 0.02), Vector2(-0.12, 0.14), Vector2(-0.38, 0.04)])
	_d_poly(eye, _hi)
	_d_poly(_mirror(eye), _hi)
	_d_poly(PackedVector2Array([Vector2(-0.3, 0.44), Vector2(-0.18, 0.6), Vector2(-0.06, 0.46), Vector2(0.06, 0.62),
		Vector2(0.18, 0.46), Vector2(0.3, 0.6), Vector2(0.3, 0.68), Vector2(-0.3, 0.68)]), _tone)
	_d_stroke(PackedVector2Array([Vector2(0.42, -0.2), Vector2(0.3, 0.06), Vector2(0.46, 0.22)]), 0.05, _tone)


func _g_bandage() -> void:
	# A bandage strip with a red cross on its pad.
	var a := -PI * 0.25
	_poly(_xf(_rect_pts(-0.96, -0.3, 0.96, 0.3), a), Color(0.94, 0.9, 0.82))
	_d_poly(_xf(_rect_pts(-0.36, -0.3, 0.36, 0.3), a), Color(0.84, 0.77, 0.66))
	for x: float in [-0.72, -0.56, 0.56, 0.72]:
		for y: float in [-0.12, 0.12]:
			_d_circ(Vector2(x, y).rotated(a), 0.04, Color(0.7, 0.62, 0.52))
	var red := Color(0.86, 0.16, 0.16)
	_d_poly(_xf(_rect_pts(-0.07, -0.22, 0.07, 0.22), a), red)
	_d_poly(_xf(_rect_pts(-0.22, -0.07, 0.22, 0.07), a), red)


func _g_sprint() -> void:
	# A winged boot with speed lines.
	for y: float in [-0.3, 0.05, 0.4]:
		_stroke(PackedVector2Array([Vector2(-0.98, y), Vector2(-0.72, y)]), 0.08, Color(_tone, 0.7))
	_poly(PackedVector2Array([Vector2(-0.3, -0.76), Vector2(0.14, -0.76), Vector2(0.14, 0.18), Vector2(0.72, 0.34),
		Vector2(0.88, 0.58), Vector2(0.84, 0.78), Vector2(-0.36, 0.78)]), _tone)
	_d_poly(_rect_pts(-0.36, 0.62, 0.86, 0.78), _deep.darkened(0.35))
	_d_poly(_rect_pts(-0.3, -0.76, 0.14, -0.58), _hi)
	for i in 3:
		var at := Vector2(-0.38, -0.36 + i * 0.2)
		_poly(_xf(_ellipse(Vector2(-0.24, 0), 0.3 - i * 0.04, 0.09, 12), -0.5 + i * 0.25, at), _hi, true)


func _g_war_stomp() -> void:
	# A hoofed leg stamping cracks into the ground.
	_poly(_ellipse(Vector2(0, 0.66), 0.96, 0.26, 24), _deep.darkened(0.3))
	for e: Vector2 in [Vector2(-0.8, 0.6), Vector2(0.82, 0.64), Vector2(-0.4, 0.88), Vector2(0.42, 0.86)]:
		_d_stroke(PackedVector2Array([Vector2(0, 0.62), Vector2(e.x * 0.5, lerpf(0.62, e.y, 0.5) - 0.04), e]), 0.05, _tone)
	_poly(_rect_pts(-0.24, -0.98, 0.24, 0.1), _tone)
	_poly(PackedVector2Array([Vector2(-0.36, 0.08), Vector2(-0.22, -0.02), Vector2(-0.1, 0.1), Vector2(0.02, -0.02),
		Vector2(0.14, 0.1), Vector2(0.26, -0.02), Vector2(0.36, 0.08), Vector2(0.3, 0.2), Vector2(-0.3, 0.2)]), _hi)
	_poly(PackedVector2Array([Vector2(-0.34, 0.2), Vector2(0.34, 0.2), Vector2(0.42, 0.6), Vector2(-0.42, 0.6)]), Color(0.24, 0.19, 0.16))
	_d_stroke(PackedVector2Array([Vector2(0, 0.26), Vector2(0, 0.58)]), 0.06, OUT)
	for side: float in [-1.0, 1.0]:
		_stroke(_arc_pts(Vector2(0, 0.5), Vector2(0.72, 0.5), PI * 0.5 + side * PI * 0.5 - side * 0.5, PI * 0.5 + side * PI * 0.5 + side * 0.15, 6), 0.07, Color(_hi, 0.85))
	_circ(Vector2(-0.84, 0.3), 0.12, Color(_hi, 0.6), true)
	_circ(Vector2(0.84, 0.3), 0.1, Color(_hi, 0.6), true)


func _g_spirit_wolf() -> void:
	# A ghostly wolf's head in profile.
	_poly(PackedVector2Array([Vector2(-0.78, 0.74), Vector2(-0.82, 0.04), Vector2(-0.58, -0.42), Vector2(-0.52, -0.96),
		Vector2(-0.22, -0.52), Vector2(0.02, -0.52), Vector2(0.2, -0.92), Vector2(0.3, -0.36), Vector2(0.56, -0.16),
		Vector2(0.96, 0.04), Vector2(0.92, 0.26), Vector2(0.46, 0.38), Vector2(0.12, 0.56), Vector2(-0.2, 0.9)]), _tone)
	_d_poly(PackedVector2Array([Vector2(0.06, -0.16), Vector2(0.3, -0.1), Vector2(0.08, -0.02)]), Color.WHITE)
	_d_circ(Vector2(0.9, 0.12), 0.07, OUT)
	_d_stroke(PackedVector2Array([Vector2(-0.6, 0.3), Vector2(-0.38, 0.5)]), 0.05, _hi)
	_d_stroke(PackedVector2Array([Vector2(-0.5, 0.06), Vector2(-0.26, 0.28)]), 0.05, _hi)


func _g_berserking() -> void:
	# A raging face: furrowed brows, burning eyes, gritted teeth.
	_circ(Vector2(0, 0.06), 0.86, _deep.darkened(0.4))
	var eye := PackedVector2Array([Vector2(-0.56, -0.12), Vector2(-0.12, 0.0), Vector2(-0.18, 0.14), Vector2(-0.5, 0.06)])
	_d_poly(eye, Color(1, 0.86, 0.3))
	_d_poly(_mirror(eye), Color(1, 0.86, 0.3))
	_stroke(PackedVector2Array([Vector2(-0.64, -0.42), Vector2(-0.1, -0.16)]), 0.15, _hi)
	_stroke(PackedVector2Array([Vector2(0.64, -0.42), Vector2(0.1, -0.16)]), 0.15, _hi)
	_d_poly(_rect_pts(-0.4, 0.36, 0.4, 0.6), Color(0.95, 0.92, 0.85))
	for x: float in [-0.2, 0.0, 0.2]:
		_d_stroke(PackedVector2Array([Vector2(x, 0.36), Vector2(x, 0.6)]), 0.04, OUT)
	_d_stroke(PackedVector2Array([Vector2(-0.4, 0.48), Vector2(0.4, 0.48)]), 0.04, OUT)
