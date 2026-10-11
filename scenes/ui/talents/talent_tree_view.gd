class_name TalentTreeView
extends Control
## One talent tree column of the Talents tab (GDD 7.2, architecture §2.2): the tree's name on
## top in its colour, five tier rows of TalentNodes (two per row, the capstone centred in
## tier 5), the prerequisite arrows (gold once the prerequisite is at max rank, grey before),
## a dark band over the tiers whose gate this tree has not reached yet, and the points spent in
## the tree right of the capstone. Everything sits at fixed design positions ([method
## node_rect]), so the tab can navigate spatially without a layout pass. The gate numbers of the
## tiers (0 / 3 / 6 / 9 / 12, the same in every tree) are on the tab's [TierRail] left of the
## trees.
## Arrows run straight down between adjacent tiers of one column; any other link leaves the
## prerequisite's inner side, runs down the gap between the two columns and enters the
## talent's inner side, so it never crosses another node.

const WIDTH := 128.0
const HEIGHT := 332.0
const PAD_X := 6.0
const TITLE_HEIGHT := 24.0
const GRID_TOP := 28.0
const ROW_GAP := 13.0
const TIERS := 5
const NAME_FONT := 16
## The tree name shrinks down to this size to fit the column.
const MIN_NAME_FONT := 12
const POINTS_FONT := 20
const CAPTION_FONT := 13
const ARROW_WIDTH := 3.0
const ARROW_MET := Color(1.0, 0.82, 0.3)
const ARROW_UNMET := Color(0.42, 0.39, 0.34)

var tree: TalentTreeData
## Talent id -> its node.
var nodes: Dictionary[StringName, TalentNode] = {}
var name_label: Label
## Points spent in this tree (right of the capstone).
var points_label: Label
## The selection is in this tree (brighter frame).
var focused := false

## Tier 1..5 -> the tree has not reached that tier's gate (index tier - 1).
var _locked: Array[bool] = [false, false, false, false, false]
## Prerequisite arrows: {"from": id, "to": id, "met": bool}.
var _links: Array[Dictionary] = []
var _frame: StyleBoxFlat


## The tier gates (TalentState.TIER_POINTS) left of the trees: one number per tier row, gold
## while the selected talent's tree has reached that gate, grey with a padlock before.
class TierRail extends Control:
	const WIDTH := 20.0
	const FONT := 14
	## Tier 1..5 reached in the selected tree (index tier - 1).
	var open: Array[bool] = [true, true, true, true, true]

	static func create() -> TierRail:
		var r := TierRail.new()
		r.name = "TierRail"
		r.custom_minimum_size = Vector2(WIDTH, TalentTreeView.HEIGHT)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return r

	func set_open(p_open: Array[bool]) -> void:
		if p_open == open:
			return
		open = p_open.duplicate()
		queue_redraw()

	## The gate number of [param tier] ("" for tier 1, which has none).
	static func gate_text(tier: int) -> String:
		var points := TalentState.gate_points(tier)
		return str(points) if points > 0 else ""

	func _draw() -> void:
		var font := UiTheme.bold_font()
		for tier in range(1, TalentTreeView.TIERS + 1):
			var text := gate_text(tier)
			if text == "":
				continue
			var cy := TalentTreeView.tier_top(tier) + TalentNode.SIZE * 0.5
			var is_open: bool = open[tier - 1]
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT).x
			var base := cy + (font.get_ascent(FONT) - font.get_descent(FONT)) * 0.5 + (5.0 if not is_open else 0.0)
			var pos := Vector2((size.x - w) * 0.5, base)
			var color := UiTheme.GOLD if is_open else Color(0.6, 0.56, 0.5)
			draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, 4, Color(0, 0, 0, 0.7))
			draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, color)
			if not is_open:
				_lock(Vector2(size.x * 0.5, cy - 9.0), color)

	func _lock(c: Vector2, color: Color) -> void:
		draw_arc(c + Vector2(0, -1.5), 3.2, PI, TAU, 10, color, 1.6, true)
		draw_rect(Rect2(c + Vector2(-4.5, -1.0), Vector2(9, 6.5)), color)
		draw_rect(Rect2(c + Vector2(-0.8, 1.0), Vector2(1.6, 2.5)), Color(0.08, 0.06, 0.05))


static func create(p_tree: TalentTreeData) -> TalentTreeView:
	var v := TalentTreeView.new()
	v.tree = p_tree
	v.name = "Tree_%s" % String(p_tree.id) if p_tree != null else "Tree"
	v.custom_minimum_size = Vector2(WIDTH, HEIGHT)
	v.size = v.custom_minimum_size
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v._build()
	return v


# --- Layout (design pixels, relative to the view) ------------------------------------------------

## Top of tier row [param tier] (1..5).
static func tier_top(tier: int) -> float:
	return GRID_TOP + (clampi(tier, 1, TIERS) - 1) * (TalentNode.SIZE + ROW_GAP)


## Where [param t]'s node sits: column 0 left, column 1 right, the capstone centred in its row.
static func node_rect(t: TalentData) -> Rect2:
	var y := tier_top(t.tier)
	if t.is_capstone():
		var s := TalentNode.CAPSTONE_SIZE
		return Rect2((WIDTH - s) * 0.5, y + (TalentNode.SIZE - s) * 0.5, s, s)
	var x := PAD_X if t.column <= 0 else WIDTH - PAD_X - TalentNode.SIZE
	return Rect2(x, y, TalentNode.SIZE, TalentNode.SIZE)


## The node of [param talent_id] (null when this tree has none).
func node_for(talent_id: StringName) -> TalentNode:
	return nodes.get(talent_id)


func is_tier_locked(tier: int) -> bool:
	return tier >= 1 and tier <= TIERS and _locked[tier - 1]


## Tiers 1..5 reached (index tier - 1) – the TierRail of the selected tree.
func open_tiers() -> Array[bool]:
	var out: Array[bool] = []
	for locked in _locked:
		out.append(not locked)
	return out


## The prerequisite arrows of the last refresh: {"from": id, "to": id, "met": bool}.
func links() -> Array[Dictionary]:
	return _links


# --- Refresh ---------------------------------------------------------------------------------------

## Pulls every node's rank / state / pending points, the locked tiers, the arrows and the
## points spent from [param s] (null: everything locked at rank 0).
func refresh(s: TalentState) -> void:
	for id in nodes:
		var n := nodes[id]
		var t := n.talent
		var rank := s.rank_of(id) if s != null else 0
		var pending := int(s.pending.get(id, 0)) if s != null else 0
		n.set_state(rank, TalentNode.state_for(s, t), pending)
	for tier in range(1, TIERS + 1):
		var below := s.points_below_tier(tree, tier) if s != null else 0
		_locked[tier - 1] = s == null or below < TalentState.gate_points(tier)
	_links.clear()
	for t in tree.talents:
		if t == null or t.prerequisite == &"" or not nodes.has(t.prerequisite) or not nodes.has(t.id):
			continue
		var pre := nodes[t.prerequisite].talent
		var met := s != null and s.rank_of(pre.id) >= pre.max_rank
		_links.append({"from": pre.id, "to": t.id, "met": met})
	points_label.text = str(s.tree_points(tree.id) if s != null else 0)
	queue_redraw()


## Marks [param talent_id]'s node selected (when [param on]; every other node not).
func set_selection(talent_id: StringName, on: bool, accent: Color) -> void:
	var inside := false
	for id in nodes:
		var sel := on and id == talent_id
		nodes[id].set_selected(sel, accent)
		inside = inside or id == talent_id
	if inside != focused:
		focused = inside
		queue_redraw()


# --- Build / draw ----------------------------------------------------------------------------------

func _build() -> void:
	name_label = UiTheme.label(tree.display_name if tree != null else "", &"", NAME_FONT, _tint().lightened(0.35))
	name_label.name = "Name"
	name_label.add_theme_font_override(&"font", UiTheme.bold_font())
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_constant_override(&"outline_size", 4)
	name_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.75))
	name_label.position = Vector2(PAD_X - 2.0, 1.0)
	name_label.size = Vector2(WIDTH - 2.0 * PAD_X + 4.0, TITLE_HEIGHT)
	name_label.add_theme_font_size_override(&"font_size", fitted_name_size(name_label.text, name_label.size.x))
	add_child(name_label)
	if tree == null:
		return
	for t in tree.talents:
		if t == null or nodes.has(t.id):
			continue
		var n := TalentNode.create(t)
		n.position = node_rect(t).position
		nodes[t.id] = n
		add_child(n)
	# Points spent in the tree: in tier 5, right of the centred capstone.
	var cap_right := (WIDTH + TalentNode.CAPSTONE_SIZE) * 0.5
	var box := Rect2(cap_right, tier_top(TIERS) - 2.0, WIDTH - cap_right - 2.0, 26.0)
	points_label = UiTheme.label("0", &"", POINTS_FONT, UiTheme.GOLD)
	points_label.name = "Points"
	points_label.add_theme_font_override(&"font", UiTheme.bold_font())
	points_label.add_theme_constant_override(&"outline_size", 5)
	points_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	points_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	points_label.position = box.position
	points_label.size = box.size
	add_child(points_label)
	var caption := UiTheme.label("pts", &"", CAPTION_FONT, UiTheme.TEXT_DIM)
	caption.name = "PointsCaption"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.position = Vector2(box.position.x, box.end.y - 4.0)
	caption.size = Vector2(box.size.x, 18.0)
	add_child(caption)


## The largest font size from NAME_FONT down to MIN_NAME_FONT at which [param text] fits
## [param width].
static func fitted_name_size(text: String, width: float) -> int:
	var font := UiTheme.bold_font()
	for fs in range(NAME_FONT, MIN_NAME_FONT - 1, -1):
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= width:
			return fs
	return MIN_NAME_FONT


func _tint() -> Color:
	return tree.color if tree != null else UiTheme.GOLD


func _draw() -> void:
	var tint := _tint()
	var rect := Rect2(Vector2.ZERO, Vector2(WIDTH, HEIGHT))
	if _frame == null:
		_frame = StyleBoxFlat.new()
		_frame.set_corner_radius_all(6)
		_frame.anti_aliasing = true
	_frame.bg_color = Color(tint.darkened(0.84), 0.92)
	_frame.border_color = tint.lightened(0.15) if focused else Color(tint.darkened(0.4), 0.9)
	_frame.set_border_width_all(2 if focused else 1)
	draw_style_box(_frame, rect)
	draw_rect(Rect2(4.0, 2.0, WIDTH - 8.0, TITLE_HEIGHT - 2.0), Color(tint.darkened(0.6), 0.55))
	draw_line(Vector2(6.0, TITLE_HEIGHT + 1.0), Vector2(WIDTH - 6.0, TITLE_HEIGHT + 1.0), Color(tint, 0.65), 1.5)
	for tier in range(2, TIERS + 1):
		if _locked[tier - 1]:
			draw_rect(Rect2(3.0, tier_top(tier) - 4.0, WIDTH - 6.0, TalentNode.SIZE + 8.0), Color(0, 0, 0, 0.3))
	for link in _links:
		_draw_link(link)


## One prerequisite arrow (drawn behind the nodes: the view draws before its children).
func _draw_link(link: Dictionary) -> void:
	var from := nodes[link["from"]].talent
	var to := nodes[link["to"]].talent
	var a := node_rect(from)
	var b := node_rect(to)
	var color: Color = ARROW_MET if link["met"] else ARROW_UNMET
	var pts := PackedVector2Array()
	var head_dir := Vector2.DOWN
	var mid_x := WIDTH * 0.5 + (-3.0 if from.column <= 0 else 3.0)
	if not to.is_capstone() and not from.is_capstone() and from.column == to.column and to.tier == from.tier + 1:
		pts.append(Vector2(a.get_center().x, a.end.y + 1.0))
		pts.append(Vector2(b.get_center().x, b.position.y - 1.0))
	elif to.is_capstone():
		pts.append(Vector2(a.end.x + 1.0 if from.column <= 0 else a.position.x - 1.0, a.get_center().y))
		pts.append(Vector2(mid_x, a.get_center().y))
		pts.append(Vector2(mid_x, b.position.y - 3.0))
	else:
		var a_inner := a.end.x + 1.0 if from.column <= 0 else a.position.x - 1.0
		var b_inner := b.end.x + 1.0 if to.column <= 0 else b.position.x - 1.0
		pts.append(Vector2(a_inner, a.get_center().y))
		pts.append(Vector2(mid_x, a.get_center().y))
		pts.append(Vector2(mid_x, b.get_center().y))
		pts.append(Vector2(b_inner, b.get_center().y))
		head_dir = Vector2.LEFT if to.column <= 0 else Vector2.RIGHT
	# Leave room for the head at the end.
	var tip := pts[pts.size() - 1]
	pts[pts.size() - 1] = tip - head_dir * 5.0
	draw_polyline(pts, Color(0, 0, 0, 0.8), ARROW_WIDTH + 2.5, true)
	draw_polyline(pts, color, ARROW_WIDTH, true)
	var side := head_dir.orthogonal()
	var head := PackedVector2Array([tip, tip - head_dir * 7.0 + side * 5.0, tip - head_dir * 7.0 - side * 5.0])
	var ring := head.duplicate()
	ring.append(head[0])
	draw_polyline(ring, Color(0, 0, 0, 0.8), 2.0, true)
	draw_colored_polygon(head, color)
