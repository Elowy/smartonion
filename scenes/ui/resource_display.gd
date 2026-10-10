class_name ResourceDisplay
extends VBoxContainer
## The class resources of one player on a unit frame (GDD 12), read from the player's
## AbilityRunner: one row per ClassResource in the class's order (primary first).
##  - ResourceData.Display.BAR  -> a UiBar in ResourceData.color with "value / max" text
##    (Rage red, Mana blue, Energy yellow); a big spend flashes the bar.
##  - ResourceData.Display.PIPS -> a row of pips (Holy Power gold, Soul Shards purple, Combo
##    Points): as the primary resource in a recessed trough like a bar, as a secondary one a
##    small centred row under the bar (Rogue: Energy bar + 5 combo pips).
## Rows follow ClassResource.changed, nothing is polled. A class without M3 resources shows a
## full placeholder bar from ClassData.resource_type / resource_color (the M1 look).

const BAR_HEIGHT := 21.0
const SECONDARY_BAR_HEIGHT := 18.0
const PIPS_HEIGHT := 17.0
## More pips than this are shown as a bar instead.
const MAX_PIPS := 10
## A drop of at least this share of the maximum flashes the bar (an ability was paid for).
const SPEND_FLASH_SHARE := 0.1

var font_size := UiTheme.FONT_SMALL
## True while the display shows the M1 placeholder bar (no resources on the player).
var is_placeholder := false

var _rows: Array[Row] = []


## One displayed resource.
class Row extends RefCounted:
	var id: StringName
	var data: ResourceData
	var resource: ClassResource
	var bar: UiBar
	var pips: Pips
	var last_value := 0.0
	var callable: Callable


static func create(p_font_size: int = UiTheme.FONT_SMALL) -> ResourceDisplay:
	var d := ResourceDisplay.new()
	d.font_size = p_font_size
	d.name = "ResourceDisplay"
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.add_theme_constant_override(&"separation", 3)
	return d


## "37" for 37.9 (a cost of 38 is not affordable yet, so never round up).
static func format_value(value: float) -> String:
	return str(int(floorf(value + 0.0001)))


static func bar_text(value: float, max_value: float) -> String:
	return "%s / %s" % [format_value(value), str(int(roundf(max_value)))]


## Whether [param data] is drawn as pips.
static func uses_pips(data: ResourceData) -> bool:
	return data != null and data.display == ResourceData.Display.PIPS and data.max_value <= MAX_PIPS


## Builds the rows for [param runner]'s resources and follows them. With no resources the
## placeholder bar of [param class_data] is shown.
func bind(runner: AbilityRunner, class_data: ClassData = null) -> void:
	unbind()
	if is_instance_valid(runner):
		for id in runner.resource_order:
			var res := runner.get_resource(id)
			if res != null and res.data != null:
				_add_row(res)
	if _rows.is_empty():
		_add_placeholder(class_data)


func unbind() -> void:
	for row in _rows:
		if row.resource != null and row.callable.is_valid() and row.resource.changed.is_connected(row.callable):
			row.resource.changed.disconnect(row.callable)
		var node: Control = row.bar if row.bar != null else row.pips
		if node != null:
			if node.get_parent() == self:
				remove_child(node)
			node.queue_free()
	_rows.clear()
	is_placeholder = false


func row_count() -> int:
	return _rows.size()


## The bar of resource [param id] (null when it is shown as pips / not present).
func bar_for(id: StringName) -> UiBar:
	for row in _rows:
		if row.id == id:
			return row.bar
	return null


func pips_for(id: StringName) -> Pips:
	for row in _rows:
		if row.id == id:
			return row.pips
	return null


## The first resource shown as a bar (null when the class only has pips).
func first_bar() -> UiBar:
	for row in _rows:
		if row.bar != null:
			return row.bar
	return null


func _add_row(res: ClassResource) -> void:
	var d := res.data
	var row := Row.new()
	row.id = d.id
	row.data = d
	row.resource = res
	var primary := _rows.is_empty()
	if uses_pips(d):
		row.pips = Pips.create(d, primary)
		add_child(row.pips)
	else:
		row.bar = UiBar.create(d.color, BAR_HEIGHT if primary else SECONDARY_BAR_HEIGHT, font_size)
		row.bar.animated = false
		add_child(row.bar)
	row.last_value = res.value
	_apply(row, res.value, res.max_value(), false)
	row.callable = _on_changed.bind(row)
	res.changed.connect(row.callable)
	_rows.append(row)


func _add_placeholder(class_data: ClassData) -> void:
	if class_data == null:
		return
	var bar := UiBar.create(class_data.resource_color, BAR_HEIGHT, font_size)
	bar.animated = false
	bar.set_values(1.0, 1.0, UiTheme.resource_name(class_data.resource_type))
	add_child(bar)
	var row := Row.new()
	row.id = class_data.resource_type
	row.bar = bar
	_rows.append(row)
	is_placeholder = true


func _on_changed(value: float, max_value: float, row: Row) -> void:
	_apply(row, value, max_value, true)


func _apply(row: Row, value: float, max_value: float, animate: bool) -> void:
	if row.bar != null:
		row.bar.set_values(value, max_value, bar_text(value, max_value))
		if animate and max_value > 0.0 and row.last_value - value >= max_value * SPEND_FLASH_SHARE:
			row.bar.flash = 0.55
	elif row.pips != null:
		row.pips.set_value(value, max_value, animate)
	row.last_value = value


## A row of pips (diamonds; crystals for Soul Shards): filled ones in the resource colour,
## empty ones as dark sockets; a new pip pops, a full row glows.
class Pips extends Control:
	var color := Color.WHITE
	var count := 5
	var filled := 0
	## Crystal shape instead of a diamond.
	var shard := false
	## Recessed trough behind the pips (primary resource).
	var trough := false
	var pip_height := 15.0

	var _pop: Array[float] = []
	var _t := 0.0

	static func create(data: ResourceData, primary: bool) -> Pips:
		var p := Pips.new()
		p.color = data.color
		p.count = clampi(int(roundf(data.max_value)), 1, ResourceDisplay.MAX_PIPS)
		p.shard = String(data.id).contains("shard")
		p.trough = primary
		p.pip_height = ResourceDisplay.BAR_HEIGHT - 5.0 if primary else ResourceDisplay.PIPS_HEIGHT - 2.0
		p.custom_minimum_size = Vector2(60, ResourceDisplay.BAR_HEIGHT if primary else ResourceDisplay.PIPS_HEIGHT)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p._pop.resize(p.count)
		p._pop.fill(0.0)
		p.set_process(false)
		return p

	## Filled pips for [param value]: whole pips only.
	static func filled_for(value: float, p_count: int) -> int:
		return clampi(int(floorf(value + 0.0001)), 0, p_count)

	func set_value(value: float, _max_value: float, animate: bool = true) -> void:
		var n := filled_for(value, count)
		if n == filled:
			return
		if animate and n > filled:
			for i in range(filled, n):
				_pop[i] = 1.0
			set_process(true)
		filled = n
		queue_redraw()

	func is_full() -> bool:
		return filled >= count

	func _process(delta: float) -> void:
		_t += delta
		var busy := is_full()
		for i in count:
			if _pop[i] > 0.0:
				_pop[i] = maxf(0.0, _pop[i] - delta * 3.5)
				busy = true
		queue_redraw()
		if not busy:
			set_process(false)

	func _draw() -> void:
		var h := pip_height
		if trough:
			var tr := StyleBoxFlat.new()
			tr.bg_color = Color(0.03, 0.025, 0.02, 0.92)
			tr.border_color = Color(UiTheme.GOLD_DARK, 0.9)
			tr.set_border_width_all(1)
			tr.set_corner_radius_all(3)
			draw_style_box(tr, Rect2(Vector2.ZERO, size))
		var gap := minf(h * 1.15, (size.x - 12.0) / float(count) - h * 0.5) if trough else h * 0.55
		gap = maxf(gap, h * 0.35)
		var step := h * (0.62 if shard else 1.0) + gap
		var total := step * (count - 1)
		var cx := size.x * 0.5 - total * 0.5
		var cy := size.y * 0.5
		var glow := 0.5 + 0.5 * sin(_t * 5.0) if is_full() else 0.0
		for i in count:
			_draw_pip(Vector2(cx + step * i, cy), h, i < filled, _pop[i], glow)

	func _draw_pip(c: Vector2, h: float, on: bool, pop: float, glow: float) -> void:
		var k := 1.0 + 0.45 * pop * pop
		var rx := h * (0.34 if shard else 0.5) * k
		var ry := h * 0.5 * k
		var pts := _shape(c, rx, ry)
		var inner := _shape(c, rx - 3.0, ry - 3.0)
		var dark := Color(0.02, 0.015, 0.01, 0.95)
		if on:
			if glow > 0.0 or pop > 0.0:
				draw_circle(c, h * (0.75 + 0.2 * glow + 0.4 * pop), Color(color, 0.14 + 0.1 * glow + 0.3 * pop))
			draw_colored_polygon(_shape(c, rx + 1.5, ry + 1.5), dark)
			draw_colored_polygon(_shape(c, rx, ry), color.darkened(0.35))
			draw_colored_polygon(inner, color.lightened(0.15 + 0.2 * pop))
			var top := _shape(c + Vector2(0, -ry * 0.28), rx * 0.45, ry * 0.4)
			draw_colored_polygon(top, Color(1, 1, 1, 0.38))
			var rim := pts.duplicate()
			rim.append(pts[0])
			draw_polyline(rim, Color(color.lightened(0.5), 0.9), 1.2, true)
		else:
			draw_colored_polygon(_shape(c, rx + 1.5, ry + 1.5), dark)
			draw_colored_polygon(pts, Color(color.darkened(0.8), 0.9))
			var rim := pts.duplicate()
			rim.append(pts[0])
			draw_polyline(rim, Color(color.darkened(0.35), 0.7), 1.2, true)

	func _shape(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
		if shard:
			return PackedVector2Array([c + Vector2(0, -ry), c + Vector2(rx, -ry * 0.35), c + Vector2(rx * 0.8, ry * 0.55),
				c + Vector2(0, ry), c + Vector2(-rx * 0.8, ry * 0.55), c + Vector2(-rx, -ry * 0.35)])
		return PackedVector2Array([c + Vector2(0, -ry), c + Vector2(rx, 0), c + Vector2(0, ry), c + Vector2(-rx, 0)])
