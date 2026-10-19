class_name TalentGlyph
extends Control
## Square talent glyph drawn in code (Talents tab, architecture §2.2): the look of an
## AbilityIcon's base (dark tinted square, soft glow, a top sheen, a two-pass outlined glyph)
## for the icons that are not abilities – a stat id (TalentData.icon = &"crit" → a starburst,
## &"armor" → a breastplate ...) or the talent's kind when it names nothing (TALENT rune star,
## MODIFIER gear, CAPSTONE crown) – plus the Reset row's circular arrow. Ability ids and the
## school damage stats are drawn by AbilityIcon itself (TalentNode.make_glyph decides).
## With a [member texture] (the talent's game-icons.net picture, [GameIcons]) the glyph is that
## picture as a tinted silhouette instead of the procedural shape; the square stays the same.
## The square has no rim: TalentNode draws the state rim over it.

enum Glyph {
	# Kinds (TalentData.Kind without an icon) and the Reset row.
	TALENT, MODIFIER, CAPSTONE, RESET,
	# Any other stat id.
	STAT,
	# Stats.
	STRENGTH, AGILITY, INTELLECT, STAMINA, SPIRIT,
	CRIT, CRIT_DAMAGE, HASTE, MASTERY, VERSATILITY,
	ARMOR, DODGE, PARRY, BLOCK, AVOIDANCE, LEECH, SPEED,
	RESOURCE, COOLDOWN, DAMAGE, EXECUTIONER, SLAYER, HEALING, EXTRA_ATTACK, AREA, THORNS, POWER,
}

## Stat id -> glyph. A stat of Stats.ALL that is missing here gets Glyph.STAT.
const STAT_GLYPHS: Dictionary[StringName, Glyph] = {
	&"strength": Glyph.STRENGTH, &"agility": Glyph.AGILITY, &"intellect": Glyph.INTELLECT,
	&"stamina": Glyph.STAMINA, &"spirit": Glyph.SPIRIT, &"max_hp": Glyph.STAMINA,
	&"crit": Glyph.CRIT, &"crit_damage": Glyph.CRIT_DAMAGE, &"haste": Glyph.HASTE,
	&"mastery": Glyph.MASTERY, &"versatility": Glyph.VERSATILITY,
	&"armor": Glyph.ARMOR, &"dodge": Glyph.DODGE, &"parry": Glyph.PARRY,
	&"block_chance": Glyph.BLOCK, &"block_value": Glyph.BLOCK, &"avoidance": Glyph.AVOIDANCE,
	&"leech": Glyph.LEECH, &"speed": Glyph.SPEED, &"resource_regen": Glyph.RESOURCE,
	&"cooldown_reduction": Glyph.COOLDOWN, &"damage_pct": Glyph.DAMAGE,
	&"executioner": Glyph.EXECUTIONER, &"slayer": Glyph.SLAYER, &"healing_done": Glyph.HEALING,
	&"extra_attack": Glyph.EXTRA_ATTACK, &"area_size": Glyph.AREA, &"thorns": Glyph.THORNS,
	&"attack_power": Glyph.POWER, &"spell_power": Glyph.POWER, &"life_on_kill": Glyph.LEECH,
	&"extra_projectile": Glyph.EXTRA_ATTACK, &"pierce": Glyph.EXTRA_ATTACK,
}

## Tint of each glyph (the square's background is a dark shade of it).
const COLORS: Dictionary[Glyph, Color] = {
	Glyph.TALENT: Color(1.0, 0.82, 0.38), Glyph.MODIFIER: Color(0.5, 0.78, 1.0),
	Glyph.CAPSTONE: Color(1.0, 0.78, 0.25), Glyph.RESET: Color(0.95, 0.72, 0.35),
	Glyph.STAT: Color(0.85, 0.8, 0.7),
	Glyph.STRENGTH: Color(0.95, 0.52, 0.36), Glyph.AGILITY: Color(0.6, 0.92, 0.45),
	Glyph.INTELLECT: Color(0.52, 0.72, 1.0), Glyph.STAMINA: Color(0.96, 0.32, 0.34),
	Glyph.SPIRIT: Color(0.6, 0.95, 0.95),
	Glyph.CRIT: Color(1.0, 0.82, 0.28), Glyph.CRIT_DAMAGE: Color(1.0, 0.46, 0.2),
	Glyph.HASTE: Color(0.98, 0.86, 0.5), Glyph.MASTERY: Color(0.8, 0.56, 1.0),
	Glyph.VERSATILITY: Color(0.45, 0.85, 0.75),
	Glyph.ARMOR: Color(0.74, 0.78, 0.86), Glyph.DODGE: Color(0.55, 0.95, 0.62),
	Glyph.PARRY: Color(0.86, 0.87, 0.92), Glyph.BLOCK: Color(0.56, 0.72, 0.98),
	Glyph.AVOIDANCE: Color(0.7, 0.86, 1.0), Glyph.LEECH: Color(0.9, 0.2, 0.26),
	Glyph.SPEED: Color(1.0, 0.9, 0.46),
	Glyph.RESOURCE: Color(0.4, 0.86, 0.8), Glyph.COOLDOWN: Color(0.6, 0.85, 1.0),
	Glyph.DAMAGE: Color(1.0, 0.56, 0.3), Glyph.EXECUTIONER: Color(0.9, 0.32, 0.26),
	Glyph.SLAYER: Color(0.92, 0.86, 0.7), Glyph.HEALING: Color(0.5, 0.95, 0.45),
	Glyph.EXTRA_ATTACK: Color(0.96, 0.76, 0.42), Glyph.AREA: Color(1.0, 0.7, 0.36),
	Glyph.THORNS: Color(0.62, 0.82, 0.36), Glyph.POWER: Color(1.0, 0.86, 0.56),
}

## Glyph half-extent as a share of the half square (AbilityIcon.GLYPH_SCALE).
const GLYPH_SCALE := AbilityIcon.GLYPH_SCALE
const OUT := AbilityIcon.OUT

var glyph := Glyph.TALENT
var tint := Color.WHITE
## The picture drawn instead of the procedural glyph (null = the glyph).
var texture: Texture2D:
	set(value):
		texture = value
		queue_redraw()

var _bg: StyleBoxFlat
# Drawing state: every shape is drawn twice, pass 0 = dark outlines, pass 1 = fills (the
# AbilityIcon way, so overlapping parts of a glyph leave no seams).
var _pass := 0
var _c := Vector2.ZERO
var _h := 1.0
var _ow := 2.0


static func create(p_glyph: Glyph, p_size: float) -> TalentGlyph:
	var g := TalentGlyph.new()
	g.glyph = p_glyph
	g.tint = COLORS.get(p_glyph, Color.WHITE)
	g.custom_minimum_size = Vector2(p_size, p_size)
	g.size = Vector2(p_size, p_size)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.texture_filter = GameIcons.FILTER
	return g


## Whether [param id] is a stat id (Stats.ALL, or a stat this file has a glyph for).
static func is_stat(id: StringName) -> bool:
	return STAT_GLYPHS.has(id) or Stats.ALL.has(id)


## The glyph of stat [param stat] (Glyph.STAT for a stat without its own).
static func for_stat(stat: StringName) -> Glyph:
	return STAT_GLYPHS.get(stat, Glyph.STAT)


## The default glyph of a talent kind (no icon, no ability).
static func for_kind(kind: TalentData.Kind) -> Glyph:
	match kind:
		TalentData.Kind.MODIFIER:
			return Glyph.MODIFIER
		TalentData.Kind.CAPSTONE:
			return Glyph.CAPSTONE
	return Glyph.TALENT


## Lower-case name of [param g] ("crit_damage") – tests and TalentNode.glyph_source.
static func glyph_name(g: Glyph) -> String:
	return String(Glyph.keys()[g]).to_lower()


func _draw() -> void:
	var sq := minf(size.x, size.y)
	var rect := Rect2(Vector2.ZERO, Vector2(sq, sq))
	if _bg == null:
		_bg = StyleBoxFlat.new()
		_bg.set_corner_radius_all(5)
		_bg.anti_aliasing = true
	_bg.bg_color = tint.darkened(0.72)
	draw_style_box(_bg, rect)
	draw_circle(rect.get_center(), sq * 0.4, Color(tint, 0.22))
	draw_rect(Rect2(3, 3, sq - 6, sq * 0.34), Color(1, 1, 1, 0.05))
	_c = rect.get_center()
	_h = sq * 0.5 * GLYPH_SCALE
	_ow = maxf(1.5, sq / 24.0)
	if texture != null:
		var side := sq * AbilityIcon.PICTURE_SCALE
		GameIcons.draw_silhouette(self, texture, Rect2(_c - Vector2(side, side) * 0.5, Vector2(side, side)),
				GameIcons.gradient_top(tint), GameIcons.gradient_bottom(tint), maxf(1.0, sq / 38.0))
		return
	for p in 2:
		_pass = p
		_draw_glyph()


func _draw_glyph() -> void:
	var t := tint
	var hi := t.lightened(0.45)
	var deep := t.darkened(0.25)
	match glyph:
		Glyph.TALENT:
			_ring(Vector2.ZERO, 0.82, 0.12, deep)
			_poly(_star(Vector2.ZERO, 0.8, 0.2, 4), t)
			_d_poly(_star(Vector2.ZERO, 0.42, 0.1, 4, -PI * 0.25), hi)
		Glyph.MODIFIER:
			if _pass == 1:
				AbilityIcon.draw_gear(self, _p(Vector2(0, 0.12)), 0.62 * _h, t)
			_poly(PackedVector2Array([Vector2(0, -0.98), Vector2(0.5, -0.46), Vector2(0.2, -0.46),
				Vector2(0.2, -0.1), Vector2(-0.2, -0.1), Vector2(-0.2, -0.46), Vector2(-0.5, -0.46)]), hi)
		Glyph.CAPSTONE:
			_poly(PackedVector2Array([Vector2(-0.86, -0.5), Vector2(-0.45, -0.08), Vector2(0, -0.72),
				Vector2(0.45, -0.08), Vector2(0.86, -0.5), Vector2(0.7, 0.42), Vector2(-0.7, 0.42)]), t)
			_poly(_rect_pts(-0.74, 0.42, 0.74, 0.72), deep)
			_circ(Vector2(-0.86, -0.56), 0.12, hi)
			_circ(Vector2(0, -0.8), 0.13, hi)
			_circ(Vector2(0.86, -0.56), 0.12, hi)
			_poly(PackedVector2Array([Vector2(0, -0.1), Vector2(0.18, 0.14), Vector2(0, 0.38), Vector2(-0.18, 0.14)]),
				Color(0.95, 0.3, 0.3))
		Glyph.RESET:
			_stroke(_arc_pts(Vector2.ZERO, 0.62, -PI * 0.15, PI * 1.45), 0.2, t)
			_poly(PackedVector2Array([Vector2(0.28, -0.98), Vector2(0.86, -0.42), Vector2(0.16, -0.24)]), t)
		Glyph.STAT:
			_poly(PackedVector2Array([Vector2(0, -0.9), Vector2(0.75, 0), Vector2(0, 0.9), Vector2(-0.75, 0)]), deep)
			_poly(_plus(0.5, 0.13), hi)
		Glyph.STRENGTH:
			_poly(PackedVector2Array([Vector2(-0.62, -0.3), Vector2(0.58, -0.3), Vector2(0.62, 0.42),
				Vector2(0.3, 0.82), Vector2(-0.42, 0.82), Vector2(-0.66, 0.4)]), t)
			for i in 4:
				_circ(Vector2(-0.45 + i * 0.3, -0.38), 0.19, t)
			_poly(PackedVector2Array([Vector2(-0.9, -0.05), Vector2(-0.5, -0.12), Vector2(-0.1, 0.22),
				Vector2(-0.22, 0.38), Vector2(-0.82, 0.3)]), deep)
			for i in 3:
				_d_stroke(PackedVector2Array([Vector2(-0.3 + i * 0.3, -0.42), Vector2(-0.3 + i * 0.3, -0.16)]), 0.05, deep)
		Glyph.AGILITY:
			var feather := PackedVector2Array([Vector2(0.72, -0.9), Vector2(0.55, -0.15), Vector2(0.1, 0.42),
				Vector2(-0.48, 0.62), Vector2(-0.3, 0.1), Vector2(0.1, -0.42)])
			_poly(feather, t)
			_stroke(PackedVector2Array([Vector2(0.62, -0.72), Vector2(-0.82, 0.86)]), 0.08, hi)
			for i in 3:
				_d_stroke(PackedVector2Array([Vector2(0.38 - i * 0.28, -0.32 + i * 0.3), Vector2(0.06 - i * 0.28, -0.42 + i * 0.3)]), 0.05, deep)
		Glyph.INTELLECT:
			var gem := PackedVector2Array([Vector2(0, -0.92), Vector2(0.58, -0.32), Vector2(0.4, 0.78),
				Vector2(-0.4, 0.78), Vector2(-0.58, -0.32)])
			_poly(gem, t)
			_d_poly(PackedVector2Array([Vector2(0, -0.92), Vector2(0.58, -0.32), Vector2(0, -0.12), Vector2(-0.58, -0.32)]), hi)
			_d_stroke(PackedVector2Array([Vector2(0, -0.12), Vector2(0, 0.78)]), 0.05, deep)
		Glyph.STAMINA:
			_heart(t)
			_d_circ(Vector2(-0.34, -0.3), 0.14, Color(1, 1, 1, 0.45))
		Glyph.SPIRIT:
			_poly(_drop(Vector2(0, 0.22), 0.55, -1.0), t)
			_d_poly(_drop(Vector2(0, 0.34), 0.28, -0.6), hi)
		Glyph.CRIT:
			_poly(_star(Vector2.ZERO, 0.55, 0.2, 4, -PI * 0.25), deep)
			_poly(_star(Vector2.ZERO, 0.95, 0.2, 4), t)
			_d_circ(Vector2.ZERO, 0.14, hi)
		Glyph.CRIT_DAMAGE:
			_poly(_star(Vector2.ZERO, 0.95, 0.48, 8), t)
			_circ(Vector2.ZERO, 0.32, Color(0.85, 0.12, 0.1))
			_d_circ(Vector2(-0.08, -0.08), 0.1, hi)
		Glyph.HASTE:
			_poly(_rect_pts(-0.62, -0.9, 0.62, -0.72), deep)
			_poly(_rect_pts(-0.62, 0.72, 0.62, 0.9), deep)
			_poly(PackedVector2Array([Vector2(-0.5, -0.72), Vector2(0.5, -0.72), Vector2(0.08, 0),
				Vector2(0.5, 0.72), Vector2(-0.5, 0.72), Vector2(-0.08, 0)]), Color(t, 0.9).lightened(0.3))
			_d_poly(PackedVector2Array([Vector2(-0.3, -0.5), Vector2(0.3, -0.5), Vector2(0, -0.12)]), Color(1.0, 0.72, 0.28))
			_d_poly(PackedVector2Array([Vector2(0, 0.3), Vector2(0.42, 0.66), Vector2(-0.42, 0.66)]), Color(1.0, 0.72, 0.28))
		Glyph.MASTERY:
			_ring(Vector2.ZERO, 0.8, 0.14, deep)
			_poly(_star(Vector2.ZERO, 0.62, 0.26, 5), t)
			_d_poly(_star(Vector2(0, -0.04), 0.28, 0.12, 5), hi)
		Glyph.VERSATILITY:
			_circ(Vector2.ZERO, 0.8, t)
			_d_poly(_half_disc(0.8), Color(1.0, 0.82, 0.38))
			_d_circ(Vector2(0, -0.4), 0.18, Color(1.0, 0.82, 0.38))
			_d_circ(Vector2(0, 0.4), 0.18, t)
		Glyph.ARMOR:
			_poly(PackedVector2Array([Vector2(-0.86, -0.56), Vector2(-0.36, -0.78), Vector2(0, -0.5),
				Vector2(0.36, -0.78), Vector2(0.86, -0.56), Vector2(0.66, 0.08), Vector2(0.46, 0.8),
				Vector2(-0.46, 0.8), Vector2(-0.66, 0.08)]), t)
			_d_stroke(PackedVector2Array([Vector2(0, -0.44), Vector2(0, 0.74)]), 0.07, deep)
			_d_stroke(PackedVector2Array([Vector2(-0.5, 0.18), Vector2(0.5, 0.18)]), 0.06, deep)
			_d_poly(PackedVector2Array([Vector2(-0.7, -0.5), Vector2(-0.38, -0.66), Vector2(-0.3, -0.4), Vector2(-0.56, -0.24)]), hi)
		Glyph.DODGE:
			_stroke(_arc_pts(Vector2(0.1, 0.1), 0.66, PI * 0.95, PI * 1.9), 0.17, t)
			_poly(PackedVector2Array([Vector2(0.56, -0.62), Vector2(0.98, -0.12), Vector2(0.4, -0.06)]), t)
			for i in 3:
				_d_stroke(PackedVector2Array([Vector2(-0.9, 0.32 + i * 0.2), Vector2(-0.42, 0.32 + i * 0.2)]), 0.06, Color(t, 0.7))
		Glyph.PARRY:
			_sword(PI * 0.25, t, deep)
			_sword(-PI * 0.25, t, deep)
		Glyph.BLOCK:
			var shield := PackedVector2Array()
			for v: Vector2 in [Vector2(-0.74, -0.82), Vector2(0.74, -0.82), Vector2(0.74, 0.0), Vector2(0.46, 0.54),
					Vector2(0, 0.98), Vector2(-0.46, 0.54), Vector2(-0.74, 0.0)]:
				shield.append(v)
			_poly(shield, t)
			_d_stroke(PackedVector2Array([Vector2(0, -0.76), Vector2(0, 0.88)]), 0.1, deep)
			_d_stroke(PackedVector2Array([Vector2(-0.68, -0.2), Vector2(0.68, -0.2)]), 0.1, deep)
			_circ(Vector2(0, -0.2), 0.2, hi)
		Glyph.AVOIDANCE:
			_ring(Vector2.ZERO, 0.78, 0.13, t)
			_stroke(_arc_pts(Vector2.ZERO, 0.46, PI * 1.1, PI * 1.9), 0.1, hi)
			_stroke(_arc_pts(Vector2.ZERO, 0.46, PI * 0.1, PI * 0.9), 0.1, hi)
			_circ(Vector2.ZERO, 0.14, hi)
		Glyph.LEECH:
			_poly(_drop(Vector2(0, 0.25), 0.6, -1.05), t)
			_d_circ(Vector2(-0.2, 0.3), 0.14, Color(1, 1, 1, 0.4))
		Glyph.SPEED:
			for i in 3:
				var x := -0.72 + i * 0.5
				_poly(PackedVector2Array([Vector2(x, -0.62), Vector2(x + 0.28, -0.62), Vector2(x + 0.62, 0),
					Vector2(x + 0.28, 0.62), Vector2(x, 0.62), Vector2(x + 0.34, 0)]), t if i == 2 else Color(t, 0.55 + i * 0.2))
		Glyph.RESOURCE:
			_stroke(_arc_pts(Vector2.ZERO, 0.7, -PI * 0.1, PI * 0.8), 0.15, t)
			_stroke(_arc_pts(Vector2.ZERO, 0.7, PI * 0.9, PI * 1.8), 0.15, t)
			_poly(PackedVector2Array([Vector2(0.86, 0.18), Vector2(0.44, 0.64), Vector2(0.2, 0.2)]), t)
			_poly(PackedVector2Array([Vector2(-0.86, -0.18), Vector2(-0.44, -0.64), Vector2(-0.2, -0.2)]), t)
			_circ(Vector2.ZERO, 0.22, hi)
		Glyph.COOLDOWN:
			_circ(Vector2(0, 0.06), 0.78, deep)
			_d_circ(Vector2(0, 0.06), 0.62, Color(0.08, 0.1, 0.16))
			_d_stroke(PackedVector2Array([Vector2(0, 0.06), Vector2(0, -0.42)]), 0.1, hi)
			_d_stroke(PackedVector2Array([Vector2(0, 0.06), Vector2(0.34, 0.24)]), 0.1, hi)
			_poly(PackedVector2Array([Vector2(-0.95, -0.55), Vector2(-0.45, -0.95), Vector2(-0.4, -0.45)]), t)
		Glyph.DAMAGE:
			_sword(0.0, t, deep)
			_poly(_plus(0.26, 0.08, Vector2(0.6, 0.56)), hi)
		Glyph.EXECUTIONER:
			_stroke(PackedVector2Array([Vector2(-0.7, 0.86), Vector2(0.45, -0.5)]), 0.13, Color(0.55, 0.36, 0.2))
			_poly(PackedVector2Array([Vector2(0.05, -0.62), Vector2(0.42, -0.95), Vector2(0.9, -0.48),
				Vector2(0.98, 0.02), Vector2(0.58, -0.12), Vector2(0.32, -0.3)]), Color(0.82, 0.84, 0.88))
			_d_poly(PackedVector2Array([Vector2(0.62, -0.62), Vector2(0.88, -0.36), Vector2(0.9, -0.06), Vector2(0.7, -0.2)]), t)
		Glyph.SLAYER:
			_poly(PackedVector2Array([Vector2(-0.5, -0.4), Vector2(-0.92, -0.98), Vector2(-0.3, -0.62)]), Color(0.86, 0.8, 0.66))
			_poly(PackedVector2Array([Vector2(0.5, -0.4), Vector2(0.92, -0.98), Vector2(0.3, -0.62)]), Color(0.86, 0.8, 0.66))
			_circ(Vector2(0, -0.12), 0.6, t)
			_poly(_rect_pts(-0.34, 0.3, 0.34, 0.76), t)
			_d_circ(Vector2(-0.24, -0.12), 0.16, OUT)
			_d_circ(Vector2(0.24, -0.12), 0.16, OUT)
			_d_poly(PackedVector2Array([Vector2(0, 0.08), Vector2(0.09, 0.26), Vector2(-0.09, 0.26)]), OUT)
		Glyph.HEALING:
			_poly(_plus(0.78, 0.28), t)
			_d_poly(_plus(0.5, 0.12), hi)
		Glyph.EXTRA_ATTACK:
			for i in 2:
				var off := Vector2(-0.3 + i * 0.5, 0.1 - i * 0.2)
				_poly(PackedVector2Array([off + Vector2(-0.42, 0.72), off + Vector2(0.38, -0.78), off + Vector2(0.18, -0.12),
					off + Vector2(-0.3, 0.62)]), t if i == 1 else deep)
		Glyph.AREA:
			_ring(Vector2.ZERO, 0.84, 0.1, Color(t, 0.6))
			_ring(Vector2.ZERO, 0.56, 0.11, t)
			_circ(Vector2.ZERO, 0.22, hi)
		Glyph.THORNS:
			_poly(_star(Vector2.ZERO, 0.95, 0.5, 10), t)
			_circ(Vector2.ZERO, 0.42, deep)
		Glyph.POWER:
			_poly(_star(Vector2(0.12, 0.1), 0.85, 0.2, 4), t)
			_poly(_star(Vector2(-0.6, -0.6), 0.32, 0.08, 4), hi)
			_d_circ(Vector2(0.12, 0.1), 0.12, hi)


# --- Shape helpers (unit space: centre 0,0, extent about ±1, y down; the AbilityIcon way) ---

func _p(v: Vector2) -> Vector2:
	return _c + v * _h


func _map(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in pts:
		out.append(_p(v))
	return out


## Filled polygon, outlined in pass 0.
func _poly(pts: PackedVector2Array, col: Color) -> void:
	var m := _map(pts)
	if _pass == 0:
		var closed := m.duplicate()
		closed.append(m[0])
		draw_polyline(closed, OUT, _ow * 2.0, true)
	else:
		draw_colored_polygon(m, col)


func _circ(center: Vector2, r: float, col: Color) -> void:
	if _pass == 0:
		draw_circle(_p(center), r * _h + _ow, OUT, true, -1.0, true)
	else:
		draw_circle(_p(center), r * _h, col, true, -1.0, true)


## A ring of radius [param r] and width [param w].
func _ring(center: Vector2, r: float, w: float, col: Color) -> void:
	if _pass == 0:
		draw_arc(_p(center), r * _h, 0.0, TAU, 40, OUT, w * _h + _ow * 2.0, true)
	else:
		draw_arc(_p(center), r * _h, 0.0, TAU, 40, col, w * _h, true)


## An open stroke with round caps.
func _stroke(pts: PackedVector2Array, w: float, col: Color) -> void:
	var m := _map(pts)
	var out_w := w * _h + _ow * 2.0
	var c := OUT if _pass == 0 else col
	var width := out_w if _pass == 0 else w * _h
	draw_polyline(m, c, width, true)
	draw_circle(m[0], width * 0.5, c, true, -1.0, true)
	draw_circle(m[m.size() - 1], width * 0.5, c, true, -1.0, true)


# Fill-pass-only details (no outline).
func _d_poly(pts: PackedVector2Array, col: Color) -> void:
	if _pass == 1:
		draw_colored_polygon(_map(pts), col)


func _d_circ(center: Vector2, r: float, col: Color) -> void:
	if _pass == 1:
		draw_circle(_p(center), r * _h, col, true, -1.0, true)


func _d_stroke(pts: PackedVector2Array, w: float, col: Color) -> void:
	if _pass == 1:
		draw_polyline(_map(pts), col, w * _h, true)


## A sword along the vertical axis (tip up), turned by [param angle].
func _sword(angle: float, col: Color, guard: Color) -> void:
	var blade := PackedVector2Array([Vector2(0, -0.95), Vector2(0.14, -0.72), Vector2(0.12, 0.34), Vector2(-0.12, 0.34), Vector2(-0.14, -0.72)])
	_poly(_xf(blade, angle), col)
	_poly(_xf(_rect_pts(-0.42, 0.34, 0.42, 0.48), angle), guard)
	_poly(_xf(_rect_pts(-0.08, 0.48, 0.08, 0.82), angle), Color(0.5, 0.33, 0.2))
	_circ(Vector2(0, 0.9).rotated(angle), 0.1, guard)


func _heart(col: Color) -> void:
	_circ(Vector2(-0.34, -0.26), 0.4, col)
	_circ(Vector2(0.34, -0.26), 0.4, col)
	_poly(PackedVector2Array([Vector2(-0.72, -0.1), Vector2(0.72, -0.1), Vector2(0, 0.8)]), col)


static func _rect_pts(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])


static func _xf(pts: PackedVector2Array, angle: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in pts:
		out.append(v.rotated(angle))
	return out


static func _star(center: Vector2, outer: float, inner: float, points: int, rot: float = -PI * 0.5) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in points * 2:
		var a := rot + PI * i / float(points)
		out.append(center + Vector2(cos(a), sin(a)) * (outer if i % 2 == 0 else inner))
	return out


## A plus sign of half-length [param arm] and half-width [param w].
static func _plus(arm: float, w: float, center: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v: Vector2 in [Vector2(-w, -arm), Vector2(w, -arm), Vector2(w, -w), Vector2(arm, -w), Vector2(arm, w),
			Vector2(w, w), Vector2(w, arm), Vector2(-w, arm), Vector2(-w, w), Vector2(-arm, w), Vector2(-arm, -w), Vector2(-w, -w)]:
		out.append(center + v)
	return out


## A drop: a circle of radius [param r] around [param center] with a tip at height [param tip_y].
static func _drop(center: Vector2, r: float, tip_y: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.append(Vector2(center.x, tip_y))
	for i in 15:
		var a := -PI * 0.15 + (PI * 1.3) * i / 14.0
		out.append(center + Vector2(cos(a), sin(a)) * r)
	return out


## The right half of a disc (versatility's two halves).
static func _half_disc(r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 17:
		var a := -PI * 0.5 + PI * i / 16.0
		out.append(Vector2(cos(a), sin(a)) * r)
	return out


static func _arc_pts(center: Vector2, r: float, a0: float, a1: float, n: int = 18) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(a0, a1, i / float(n))
		out.append(center + Vector2(cos(a), sin(a)) * r)
	return out
