class_name TalentNode
extends Control
## One talent in a TalentTreeView (Talents tab, GDD 7.2, architecture §2.2): a square icon with
## the talent's glyph ([method make_glyph]: an ability id in TalentData.icon – or a modifier's
## TalentData.ability – gets that ability's AbilityIcon glyph, a school damage stat the school's
## AbilityIcon glyph, any other stat id a TalentGlyph stat glyph, everything else the
## TalentGlyph of its kind) and, drawn over it by a child layer ([class Overlay]):
##  - the state rim ([enum State], pushed in by the tab – nothing is read from gameplay):
##    LOCKED (a tier gate, a prerequisite or the level-10 rule: darkened glyph, grey rim),
##    UNAVAILABLE (open, but no free point: a little dark), AVAILABLE (a point can go in: green
##    rim), PARTIAL (some ranks: green), MAXED (gold),
##  - the rank pill "2/3" hanging over the bottom-right corner (ringed in the player's colour
##    while some of those ranks are pending – taken since the last wave start, X takes them back),
##  - a gear badge on modifiers, a gold double frame and a gem on the capstone,
##  - the selection outline in the player's colour.
## Capstones are CAPSTONE_SIZE, every other talent SIZE (design pixels of the 700x480 panel).

enum State { LOCKED, UNAVAILABLE, AVAILABLE, PARTIAL, MAXED }

const SIZE := 48.0
const CAPSTONE_SIZE := 52.0
## Rank pill text and height ("2/3"): 17 px stays legible (about 9 px) on a 4-player corner
## panel at 1280 x 720.
const RANK_FONT := 17
const PILL_HEIGHT := 19.0
## How far the rank pill reaches past the icon's right edge.
const PILL_OVERHANG := 5.0
const RIM_COLORS: Dictionary[State, Color] = {
	State.LOCKED: Color(0.3, 0.27, 0.23), State.UNAVAILABLE: Color(0.52, 0.46, 0.36),
	State.AVAILABLE: UiTheme.GREEN, State.PARTIAL: UiTheme.GREEN, State.MAXED: UiTheme.GOLD,
}
const PILL_TEXT_COLORS: Dictionary[State, Color] = {
	State.LOCKED: Color(0.55, 0.52, 0.48), State.UNAVAILABLE: Color(0.74, 0.7, 0.62),
	State.AVAILABLE: UiTheme.GREEN, State.PARTIAL: UiTheme.GREEN, State.MAXED: UiTheme.GOLD_BRIGHT,
}
## Glyph brightness per state (modulate of the glyph child).
const GLYPH_TONES: Dictionary[State, Color] = {
	State.LOCKED: Color(0.48, 0.47, 0.47), State.UNAVAILABLE: Color(0.74, 0.74, 0.74),
	State.AVAILABLE: Color.WHITE, State.PARTIAL: Color.WHITE, State.MAXED: Color.WHITE,
}
const MODIFIER_BADGE := Color(0.55, 0.8, 1.0)
const OUT_COLOR := AbilityIcon.OUT

var talent: TalentData
var rank := 0
var state := State.LOCKED
## Ranks added since the last wave start.
var pending := 0
var selected := false
var accent := UiTheme.GOLD
## Where the glyph comes from: "ability:<id>", "school:<school>", "stat:<id>" or "kind:<glyph>".
var glyph_source := ""

var _glyph: Control
var _overlay: Overlay
var _side := SIZE
var _pill_box: StyleBoxFlat
var _rim_box: StyleBoxFlat


## Draws the rim, rank pill, badges and selection over the glyph child.
class Overlay extends Control:
	var node: TalentNode

	func _draw() -> void:
		if node != null:
			node._draw_overlay(self)


static func create(t: TalentData) -> TalentNode:
	var n := TalentNode.new()
	n.talent = t
	n.name = "Talent_%s" % String(t.id) if t != null else "Talent"
	n._side = CAPSTONE_SIZE if t != null and t.is_capstone() else SIZE
	n.custom_minimum_size = Vector2(n._side, n._side)
	n.size = n.custom_minimum_size
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.glyph_source = source_for(t)
	n._glyph = make_glyph(t, n._side)
	n.add_child(n._glyph)
	n._overlay = Overlay.new()
	n._overlay.name = "Overlay"
	n._overlay.node = n
	n._overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n._overlay.size = n.custom_minimum_size
	n.add_child(n._overlay)
	n._apply_tone()
	return n


# --- Glyph choice ----------------------------------------------------------------------------

## Where [param t]'s glyph comes from: TalentData.icon first, then a modifier's
## TalentData.ability – an ability id ("ability:<id>"), a school damage stat ("school:<school>")
## or another stat id ("stat:<id>"); anything else falls back to the kind ("kind:talent" /
## "kind:modifier" / "kind:capstone").
static func source_for(t: TalentData) -> String:
	if t == null:
		return "kind:talent"
	for key: StringName in [t.icon, t.ability]:
		if key == &"":
			continue
		if Db.get_ability(key) != null:
			return "ability:%s" % key
		var school := school_of_stat(key)
		if school != &"":
			return "school:%s" % school
		if TalentGlyph.is_stat(key):
			return "stat:%s" % key
	return "kind:%s" % TalentGlyph.glyph_name(TalentGlyph.for_kind(t.kind))


## The glyph control of [param t] at [param side] px: an AbilityIcon (ability / school glyph)
## or a TalentGlyph (stat / kind glyph).
static func make_glyph(t: TalentData, side: float) -> Control:
	var source := source_for(t)
	var key := StringName(source.get_slice(":", 1))
	var ability: AbilityData = null
	if source.begins_with("ability:"):
		ability = Db.get_ability(key)
	elif source.begins_with("school:"):
		# Only the school picks AbilityIcon's glyph and tint (no id, no icon, default colour).
		ability = AbilityData.new()
		ability.school = key
	if ability != null:
		var icon := AbilityIcon.create(side, false)
		icon.show_prompt = false
		icon.set_ability(ability, 0.0)
		icon.name = "Glyph"
		icon.size = Vector2(side, side)
		return icon
	var g: TalentGlyph
	if source.begins_with("stat:"):
		g = TalentGlyph.create(TalentGlyph.for_stat(key), side)
	else:
		g = TalentGlyph.create(TalentGlyph.for_kind(t.kind if t != null else TalentData.Kind.TALENT), side)
	g.name = "Glyph"
	return g


## The school of a school damage stat (&"fire_damage" → &"fire"; &"" for other ids).
static func school_of_stat(stat: StringName) -> StringName:
	for school: StringName in Stats.SCHOOL_STATS:
		if Stats.SCHOOL_STATS[school] == stat:
			return school
	return &""


# --- State ---------------------------------------------------------------------------------------

## The node state of [param t] in [param s] (see [enum State]).
static func state_for(s: TalentState, t: TalentData) -> State:
	if s == null or t == null:
		return State.LOCKED
	var r := s.rank_of(t.id)
	if r >= t.max_rank:
		return State.MAXED
	if r > 0:
		return State.PARTIAL
	if s.can_add(t.id):
		return State.AVAILABLE
	return State.UNAVAILABLE if is_open(s, t) else State.LOCKED


## Whether [param t] passes the level rule, its tier gate and its prerequisite (a point could go
## in if one were free).
static func is_open(s: TalentState, t: TalentData) -> bool:
	if RunState.level < RunState.TALENT_START_LEVEL:
		return false
	if s.points_below_tier(s.tree_of(t.id), t.tier) < TalentState.gate_points(t.tier):
		return false
	if t.prerequisite != &"":
		var pre := s.talent(t.prerequisite)
		if pre != null and s.rank_of(pre.id) < pre.max_rank:
			return false
	return true


func set_state(p_rank: int, p_state: State, p_pending: int = 0) -> void:
	if p_rank == rank and p_state == state and p_pending == pending:
		return
	rank = p_rank
	state = p_state
	pending = p_pending
	_apply_tone()
	_overlay.queue_redraw()


func set_selected(on: bool, p_accent: Color = UiTheme.GOLD) -> void:
	if on == selected and p_accent == accent:
		return
	selected = on
	accent = p_accent
	_overlay.queue_redraw()


func side() -> float:
	return _side


func max_rank() -> int:
	return talent.max_rank if talent != null else 0


## "2/3".
func rank_text() -> String:
	return "%d/%d" % [rank, max_rank()]


func glyph_control() -> Control:
	return _glyph


func _apply_tone() -> void:
	if _glyph != null:
		_glyph.modulate = GLYPH_TONES.get(state, Color.WHITE)


# --- Drawing -------------------------------------------------------------------------------------

func _draw_overlay(ci: CanvasItem) -> void:
	var sq := _side
	var rect := Rect2(0, 0, sq, sq)
	if state == State.LOCKED:
		ci.draw_rect(rect.grow(-2.0), Color(0.04, 0.035, 0.05, 0.22))
	if _rim_box == null:
		_rim_box = StyleBoxFlat.new()
		_rim_box.draw_center = false
		_rim_box.anti_aliasing = true
		_rim_box.set_corner_radius_all(5)
	var rim_color: Color = RIM_COLORS.get(state, UiTheme.GOLD_DARK)
	ci.draw_rect(rect.grow(1.0), Color(0, 0, 0, 0.9), false, 1.0)
	_rim_box.border_color = rim_color
	_rim_box.set_border_width_all(3 if talent != null and talent.is_capstone() else 2)
	ci.draw_style_box(_rim_box, rect)
	if talent != null and talent.is_capstone():
		_draw_capstone_frame(ci, rect, rim_color)
	if talent != null and talent.is_modifier():
		var c := Vector2(sq - 3.0, 3.0)
		ci.draw_circle(c, 8.5, OUT_COLOR, true, -1.0, true)
		AbilityIcon.draw_gear(ci, c, 6.5, MODIFIER_BADGE if state != State.LOCKED else MODIFIER_BADGE.darkened(0.45))
	_draw_pill(ci, sq)
	if selected:
		ci.draw_rect(rect.grow(6.0), Color(accent, 0.28), false, 3.0)
		ci.draw_rect(rect.grow(3.5), accent, false, 3.0)



## The capstone's frame: a thin gold line outside the rim with a gem on top.
func _draw_capstone_frame(ci: CanvasItem, rect: Rect2, rim_color: Color) -> void:
	var gold := UiTheme.GOLD if state != State.LOCKED else Color(0.42, 0.36, 0.26)
	ci.draw_rect(rect.grow(2.5), Color(gold, 0.85), false, 1.5)
	var top := Vector2(rect.get_center().x, rect.position.y - 2.5)
	var gem := PackedVector2Array([top + Vector2(0, -6), top + Vector2(6, 0), top + Vector2(0, 6), top + Vector2(-6, 0)])
	var ring := gem.duplicate()
	ring.append(gem[0])
	ci.draw_colored_polygon(gem, rim_color if state != State.LOCKED else Color(0.36, 0.32, 0.27))
	ci.draw_polyline(ring, OUT_COLOR, 2.0, true)


## The "2/3" pill straddling the bottom edge, flush with the right edge (PILL_OVERHANG out).
func _draw_pill(ci: CanvasItem, sq: float) -> void:
	var text := rank_text()
	var font := UiTheme.bold_font()
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, RANK_FONT).x
	var pill := Rect2(sq + PILL_OVERHANG - (w + 8.0), sq - PILL_HEIGHT * 0.5, w + 8.0, PILL_HEIGHT)
	if _pill_box == null:
		_pill_box = StyleBoxFlat.new()
		_pill_box.anti_aliasing = true
		_pill_box.set_corner_radius_all(int(PILL_HEIGHT * 0.5))
		_pill_box.bg_color = Color(0.07, 0.06, 0.05, 0.96)
	var ring := accent.lightened(0.2) if pending > 0 else Color(UiTheme.GOLD_DARK, 0.95)
	_pill_box.border_color = ring
	_pill_box.set_border_width_all(2 if pending > 0 else 1)
	ci.draw_style_box(_pill_box, pill)
	var color: Color = PILL_TEXT_COLORS.get(state, UiTheme.TEXT)
	var pos := Vector2(pill.get_center().x - w * 0.5, pill.get_center().y + (font.get_ascent(RANK_FONT) - font.get_descent(RANK_FONT)) * 0.5)
	ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, RANK_FONT, 4, Color(0, 0, 0, 0.75))
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, RANK_FONT, color)
