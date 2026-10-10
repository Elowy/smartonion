class_name ItemIcon
extends Control
## Square item icon: procedural slot / weapon silhouette (ItemArt) on a dark slot background
## with a rarity-coloured border (UiTheme.RARITY_COLORS) – Rare and better get a soft inner
## glow, Epic and better an outer glow as well. Empty slots show a faint slot silhouette.
## Optional extras: a small corner badge (green ↑ upgrade / red ↓ downgrade), a red "cannot
## use" tint and a selection cursor frame in the player's colour (pulses while shown).

const BACKGROUND := Color(0.07, 0.06, 0.055)
const EMPTY_BORDER := Color(0.32, 0.26, 0.18)
const EMPTY_SILHOUETTE := Color(0.62, 0.56, 0.48, 0.2)
const COMMON_BORDER := Color(0.66, 0.64, 0.6)
const UNUSABLE_TINT := Color(0.9, 0.06, 0.04, 0.45)

var item: ItemInstance
## Items.EquipSlot shown as a faint silhouette while [member item] is null (-1 = plain slot).
var empty_slot := -1
## +1 upgrade, -1 downgrade, 0 none.
var badge := 0
var unusable := false
var selected := false
var cursor_color := UiTheme.GOLD_BRIGHT

var _t := 0.0


static func create(p_item: ItemInstance = null, p_size: float = 64.0) -> ItemIcon:
	var icon := ItemIcon.new()
	icon.custom_minimum_size = Vector2(p_size, p_size)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.item = p_item
	return icon


func set_item(p_item: ItemInstance) -> void:
	if p_item == item:
		return
	item = p_item
	queue_redraw()


## Empty slot look for an equipment position (Items.EquipSlot).
func set_empty_slot(equip_slot: int) -> void:
	item = null
	empty_slot = equip_slot
	badge = 0
	unusable = false
	queue_redraw()


## Green ↑ / red ↓ / none badge (loot roll, shop: is it an upgrade for this player).
func set_upgrade_badge(direction: int) -> void:
	direction = signi(direction)
	if direction != badge:
		badge = direction
		queue_redraw()


## Red "cannot use" tint (strict proficiency, GDD 5.3).
func set_unusable(value: bool) -> void:
	if value != unusable:
		unusable = value
		queue_redraw()


## Selection cursor frame (e.g. a player's colour); pulses while shown.
func set_selected(value: bool, color: Color = UiTheme.GOLD_BRIGHT) -> void:
	if value != selected or color != cursor_color:
		selected = value
		cursor_color = color
		_t = 0.0
		queue_redraw()


func rarity_color() -> Color:
	if item == null:
		return EMPTY_BORDER
	return rarity_color_of(item.rarity)


## Border / name colour for [param rarity] (Common is drawn a little greyer than its text).
static func rarity_color_of(rarity: int) -> Color:
	var r := clampi(rarity, 0, UiTheme.RARITY_COLORS.size() - 1)
	return COMMON_BORDER if r == 0 else UiTheme.RARITY_COLORS[r]


func _process(delta: float) -> void:
	if selected and is_visible_in_tree():
		_t += delta
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if r.size.x < 4.0 or r.size.y < 4.0:
		return
	var s := minf(r.size.x, r.size.y)
	var radius := maxi(2, roundi(s * 0.07))
	var rarity := item.rarity if item != null else -1
	var border := rarity_color()
	var border_w := 2.0 if rarity < Items.Rarity.EPIC else 3.0
	if s < 40.0:
		border_w = maxf(1.5, border_w - 0.5)

	# Outer glow: the cursor, or Epic and better items.
	if selected:
		var pulse := 0.5 + 0.5 * sin(_t * 5.0)
		_draw_glow(r, Color(cursor_color, 0.45 + 0.3 * pulse), s * 0.16, radius)
	elif rarity >= Items.Rarity.EPIC:
		_draw_glow(r, Color(border, 0.4), s * 0.12, radius)

	# Slot background with an inner shadow.
	var bg := StyleBoxFlat.new()
	bg.bg_color = BACKGROUND
	bg.set_corner_radius_all(radius)
	bg.anti_aliasing = true
	draw_style_box(bg, r)
	var inner := r.grow(-border_w)
	if item != null and rarity >= Items.Rarity.UNCOMMON:
		_radial(inner.get_center(), inner.size.x * 0.62, Color(border, 0.1 + 0.07 * mini(rarity, 4)))
	var shade := StyleBoxFlat.new()
	shade.draw_center = false
	shade.border_color = Color(0, 0, 0, 0.55)
	shade.set_border_width_all(maxi(2, roundi(s * 0.09)))
	shade.border_blend = true
	shade.set_corner_radius_all(radius)
	draw_style_box(shade, inner)

	# Silhouette.
	var art := r.grow(-s * 0.1)
	if item != null:
		ItemArt.draw_item(self, art, item)
	elif empty_slot >= 0:
		ItemArt.draw_empty_slot(self, art, empty_slot, EMPTY_SILHOUETTE)
	if unusable and item != null:
		var tint := StyleBoxFlat.new()
		tint.bg_color = UNUSABLE_TINT
		tint.set_corner_radius_all(radius)
		draw_style_box(tint, inner)

	# Top sheen + rarity border.
	draw_rect(Rect2(inner.position + Vector2(2, 2), Vector2(inner.size.x - 4, inner.size.y * 0.18)), Color(1, 1, 1, 0.05))
	var frame := StyleBoxFlat.new()
	frame.draw_center = false
	frame.border_color = border if item != null else EMPTY_BORDER
	frame.set_border_width_all(roundi(border_w))
	frame.set_corner_radius_all(radius)
	frame.anti_aliasing = true
	draw_style_box(frame, r)
	if item != null and rarity >= Items.Rarity.RARE:
		var hi := StyleBoxFlat.new()
		hi.draw_center = false
		hi.border_color = Color(border.lightened(0.5), 0.35)
		hi.set_border_width_all(1)
		hi.set_corner_radius_all(maxi(0, radius - 2))
		draw_style_box(hi, r.grow(-border_w))

	if badge != 0 and item != null:
		_draw_badge(r, s)
	if selected:
		_draw_cursor(r, s, radius)


func _draw_glow(r: Rect2, color: Color, glow_size: float, radius: int) -> void:
	var g := StyleBoxFlat.new()
	g.draw_center = false
	g.bg_color = Color(color.r, color.g, color.b, 0.0)
	g.shadow_color = color
	g.shadow_size = maxi(2, roundi(glow_size))
	g.set_corner_radius_all(radius)
	draw_style_box(g, r)


func _radial(center: Vector2, radius: float, color: Color) -> void:
	var steps := 24
	var edge := Color(color, 0.0)
	for i in steps:
		var a0 := TAU * i / steps
		var a1 := TAU * (i + 1) / steps
		draw_polygon(PackedVector2Array([center, center + Vector2(cos(a0), sin(a0)) * radius,
			center + Vector2(cos(a1), sin(a1)) * radius]), PackedColorArray([color, edge, edge]))


func _draw_badge(r: Rect2, s: float) -> void:
	var br := maxf(7.0, s * 0.17)
	var c := Vector2(r.end.x - br * 0.85, r.position.y + br * 0.85)
	var col := UiTheme.GREEN if badge > 0 else UiTheme.RED
	draw_circle(c + Vector2(0, 1), br + 1.5, Color(0, 0, 0, 0.6))
	draw_circle(c, br + 1.0, ItemArt.OUTLINE)
	draw_circle(c, br - 0.5, col.darkened(0.45))
	var d := -1.0 if badge > 0 else 1.0
	var h := br * 0.62
	var arrow := PackedVector2Array([
		c + Vector2(0, d * h), c + Vector2(h * 0.85, d * h * 0.05), c + Vector2(h * 0.32, d * h * 0.05),
		c + Vector2(h * 0.32, -d * h * 0.85), c + Vector2(-h * 0.32, -d * h * 0.85),
		c + Vector2(-h * 0.32, d * h * 0.05), c + Vector2(-h * 0.85, d * h * 0.05)])
	draw_colored_polygon(arrow, col.lightened(0.15))


func _draw_cursor(r: Rect2, s: float, radius: int) -> void:
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	var outer := r.grow(maxf(2.0, s * 0.05))
	var frame := StyleBoxFlat.new()
	frame.draw_center = false
	frame.border_color = cursor_color.lerp(Color.WHITE, 0.25 * pulse)
	frame.set_border_width_all(maxi(2, roundi(s * 0.06)))
	frame.set_corner_radius_all(radius + 2)
	frame.anti_aliasing = true
	draw_style_box(frame, outer)
	# Gold corner brackets (WoW selection look).
	var arm := s * 0.24
	var w := maxf(2.0, s * 0.05)
	var g := UiTheme.GOLD_BRIGHT
	for corner: Vector2 in [outer.position, Vector2(outer.end.x, outer.position.y), Vector2(outer.position.x, outer.end.y), outer.end]:
		var sx := 1.0 if corner.x < r.get_center().x else -1.0
		var sy := 1.0 if corner.y < r.get_center().y else -1.0
		var o := corner + Vector2(-sx, -sy) * w * 0.5
		draw_line(o, o + Vector2(sx * arm, 0), ItemArt.OUTLINE, w + 2.0)
		draw_line(o, o + Vector2(0, sy * arm), ItemArt.OUTLINE, w + 2.0)
		draw_line(o, o + Vector2(sx * arm, 0), g, w)
		draw_line(o, o + Vector2(0, sy * arm), g, w)
