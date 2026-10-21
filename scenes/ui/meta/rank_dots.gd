class_name RankDots
extends Control
## A row of rank dots (M9 PATCH): [member max_rank] circles, the first [member rank] of them filled gold. Used by the
## Heirloom cards of The Onion Patch and the Loadout screen. Draws itself; no children.

var rank := 0
var max_rank := HeirloomData.MAX_RANK
var radius := 6.0
var gap := 5.0
var filled_color := UiTheme.GOLD
var empty_color := Color(0.45, 0.4, 0.35, 0.8)


static func create(p_rank: int, p_max: int = HeirloomData.MAX_RANK, p_radius: float = 6.0) -> RankDots:
	var d := RankDots.new()
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.max_rank = maxi(p_max, 1)
	d.radius = p_radius
	d.rank = clampi(p_rank, 0, d.max_rank)
	d.custom_minimum_size = d._wanted_size()
	return d


func set_rank(value: int) -> void:
	var v := clampi(value, 0, max_rank)
	if v != rank:
		rank = v
		queue_redraw()


func _wanted_size() -> Vector2:
	return Vector2(float(max_rank) * (radius * 2.0 + gap) - gap + 2.0, radius * 2.0 + 2.0)


func _draw() -> void:
	for i in max_rank:
		var c := Vector2(radius + 1.0 + float(i) * (radius * 2.0 + gap), size.y * 0.5)
		if i < rank:
			draw_circle(c, radius, UiTheme.GOLD_DARK)
			draw_circle(c, radius - 1.5, filled_color)
		else:
			draw_arc(c, radius - 0.75, 0.0, TAU, 20, empty_color, 1.5)
