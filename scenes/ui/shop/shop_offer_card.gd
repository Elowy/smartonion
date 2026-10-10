class_name ShopOfferCard
extends Control
## One offer on the goblin's stall (ShopPanel): the item icon, its name in the rarity colour,
## slot / armor type, the price with a coin (red while the shared wallet cannot pay it), a
## padlock in the colour of the player who locked it, "P2 wants" tags for pings, one small
## usable-by pip per player (crossed out when that class cannot use it, a green arrow when it
## is an upgrade for that player) and a "SOLD" stamp once bought.

const CARD_SIZE := Vector2(124, 212)
const ICON_SIZE := 64.0
const PIP_SIZE := Vector2(24, 18)

var index := -1
var offer: Shop.Offer
var icon: ItemIcon
var name_label: Label
var type_label: Label
var price_label: Label

## Per joined slot index: 0 = cannot use, 1 = can use, 2 = can use and an upgrade.
var _usable: Dictionary[int, int] = {}
var _colors: Dictionary[int, Color] = {}
var _content: VBoxContainer
var _overlay: Control
var _coin: UiIcon
var _lock: UiIcon


static func create(p_index: int) -> ShopOfferCard:
	var card := ShopOfferCard.new()
	card.name = "Offer%d" % p_index
	card.index = p_index
	card.custom_minimum_size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card._build()
	return card


## "Plate Head", "Sword (2H)", "Finger", "Trinket" – the type line under the name.
static func type_text(item: ItemInstance) -> String:
	if item == null:
		return ""
	if item.is_weapon():
		var t := String(item.weapon.weapon_type).capitalize()
		if t == "":
			t = "Weapon"
		if item.is_two_handed():
			t += " (2H)"
		elif item.is_off_hand_only():
			t += " (Off Hand)"
		return t
	var slot_name: String = Items.SLOT_NAMES.get(item.slot_type, "")
	if item.armor_type != Items.NO_ARMOR:
		return "%s %s" % [Items.ARMOR_TYPE_NAMES.get(item.armor_type, ""), slot_name]
	return slot_name


static func rarity_color(item: ItemInstance) -> Color:
	if item == null:
		return UiTheme.TEXT
	return UiTheme.RARITY_COLORS[clampi(item.rarity, 0, UiTheme.RARITY_COLORS.size() - 1)]


func _build() -> void:
	_content = UiTheme.vbox(2)
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.offset_left = 6
	_content.offset_right = -6
	_content.offset_top = 10
	_content.offset_bottom = -26
	add_child(_content)
	icon = ItemIcon.create(null, ICON_SIZE)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(icon)
	name_label = UiTheme.centered_label("", &"", 16)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.max_lines_visible = 2
	name_label.custom_minimum_size = Vector2(CARD_SIZE.x - 12, 44)
	name_label.add_theme_font_override(&"font", UiTheme.bold_font())
	name_label.add_theme_constant_override(&"line_spacing", -3)
	_content.add_child(name_label)
	type_label = UiTheme.centered_label("", UiTheme.SMALL, 15)
	type_label.clip_text = true
	type_label.custom_minimum_size = Vector2(CARD_SIZE.x - 12, 0)
	_content.add_child(type_label)
	var price_row := UiTheme.hbox(5)
	price_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_coin = UiIcon.create(UiIcon.Kind.COIN, Vector2(20, 20))
	_coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	price_row.add_child(_coin)
	price_label = UiTheme.label("0", UiTheme.GOLD_LABEL, 22)
	price_row.add_child(price_label)
	_content.add_child(price_row)

	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_lock = UiIcon.create(UiIcon.Kind.LOCK, Vector2(20, 20))
	_lock.position = Vector2(CARD_SIZE.x - 28, 8)
	_lock.visible = false
	_overlay.add_child(_lock)


## Shows [param p_offer] (null = empty position) for the players in [param slots].
func set_offer(p_offer: Shop.Offer, slots: Array[PlayerSlot]) -> void:
	offer = p_offer
	var item := offer.item if offer != null else null
	icon.set_item(item)
	name_label.text = item.display_name if item != null else ""
	name_label.add_theme_color_override(&"font_color", rarity_color(item))
	type_label.text = type_text(item)
	_usable.clear()
	_colors.clear()
	for s in slots:
		_colors[s.index] = s.color
		if item == null:
			continue
		var level := 0
		if item.can_be_used_by(s.class_data):
			level = 1
			var eq := ShopPanel.equipment_of(s)
			if eq != null:
				var target := eq.default_slot(item)
				var current: ItemInstance = eq.get_item(target as Items.EquipSlot) if target >= 0 else null
				if ItemTooltip.upgrade_direction(item, current, s.class_data) > 0:
					level = 2
		_usable[s.index] = level
	update_state()


## Price colour, lock, pings and the sold stamp (cheap; called on shop / wallet changes).
func update_state() -> void:
	var has := offer != null and offer.item != null
	_content.visible = has
	if not has:
		_lock.visible = false
		queue_redraw()
		_overlay.queue_redraw()
		return
	price_label.text = UiTheme.format_int(offer.price)
	var poor := RunState.gold < offer.price and not offer.sold
	price_label.add_theme_color_override(&"font_color", UiTheme.RED if poor else UiTheme.GOLD)
	_content.modulate = Color(1, 1, 1, 0.35) if offer.sold else Color.WHITE
	_lock.visible = offer.locked_by >= 0 and not offer.sold
	if _lock.visible:
		var locker := PlayerManager.get_slot(offer.locked_by)
		_lock.set_color(locker.color.lightened(0.15) if locker != null else UiTheme.GOLD)
	queue_redraw()
	_overlay.queue_redraw()


func is_affordable() -> bool:
	return offer != null and RunState.gold >= offer.price


# --- Drawing ------------------------------------------------------------------------

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var item := offer.item if offer != null else null
	var rc := rarity_color(item) if item != null else Color(0.35, 0.3, 0.25)
	# Recessed slot on the counter.
	draw_rect(Rect2(r.position + Vector2(0, 4), r.size), Color(0, 0, 0, 0.35))
	draw_rect(r, Color(0.07, 0.055, 0.045, 0.96))
	# Rarity glow from the top.
	if item != null and not offer.sold:
		var glow := Color(rc, 0.16)
		var clear := Color(rc, 0.0)
		draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, 0), Vector2(r.end.x, r.size.y * 0.55), Vector2(0, r.size.y * 0.55)]),
			PackedColorArray([glow, glow, clear, clear]))
	draw_rect(r, Color(rc.darkened(0.35), 0.9 if item != null else 0.5), false, 2.0)
	draw_rect(r.grow(-3.0), Color(0, 0, 0, 0.5), false, 1.0)
	# Pip strip.
	draw_rect(Rect2(3, r.size.y - 25, r.size.x - 6, 22), Color(0, 0, 0, 0.35))


func _draw_overlay() -> void:
	if offer == null or offer.item == null:
		return
	var ci := _overlay
	var font := UiTheme.bold_font()
	# Lock badge background (the UiIcon padlock sits on it).
	if _lock.visible:
		ci.draw_circle(_lock.position + _lock.size * 0.5, 14.0, Color(0.05, 0.04, 0.03, 0.9))
		ci.draw_arc(_lock.position + _lock.size * 0.5, 14.0, 0.0, TAU, 24, _lock.color, 2.0, true)
	# "P2 wants" tags (below the cursor corner tags).
	var y := 14.0
	for slot_index in offer.pinged_by:
		var col: Color = _colors.get(slot_index, Color.WHITE)
		var text := "P%d wants" % (slot_index + 1)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 12.0
		var tag := Rect2(4, y, w, 20)
		ci.draw_rect(tag, Color(col.darkened(0.55), 0.92))
		ci.draw_rect(tag, col, false, 2.0)
		ci.draw_string_outline(font, Vector2(tag.position.x + 6, y + 15), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, UiTheme.OUTLINE)
		ci.draw_string(font, Vector2(tag.position.x + 6, y + 15), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		y += 23.0
	# Usable-by pips, one per player in slot order.
	var keys := _colors.keys()
	keys.sort()
	var total := keys.size() * PIP_SIZE.x + maxi(0, keys.size() - 1) * 4.0
	var x := (size.x - total) * 0.5
	for slot_index: int in keys:
		var col: Color = _colors[slot_index]
		var level: int = _usable.get(slot_index, 0)
		var pip := Rect2(x, size.y - 23, PIP_SIZE.x, PIP_SIZE.y)
		if level > 0:
			ci.draw_rect(pip, Color(col.darkened(0.35), 0.95))
			ci.draw_rect(pip, col.lightened(0.2), false, 1.5)
		else:
			ci.draw_rect(pip, Color(0.12, 0.1, 0.09, 0.9))
			ci.draw_rect(pip, Color(col, 0.35), false, 1.0)
		var label := str(slot_index + 1)
		var tc := Color.WHITE if level > 0 else Color(0.55, 0.5, 0.45)
		ci.draw_string(font, Vector2(pip.position.x + 4, pip.position.y + 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, tc)
		if level == 0:
			ci.draw_line(pip.position + Vector2(2, pip.size.y - 2), pip.position + Vector2(pip.size.x - 2, 2), Color(0.85, 0.25, 0.2, 0.9), 2.0)
		elif level == 2:
			var ac := pip.position + Vector2(pip.size.x - 7, pip.size.y * 0.5)
			ci.draw_colored_polygon(PackedVector2Array([ac + Vector2(0, -6), ac + Vector2(5, 2), ac + Vector2(-5, 2)]), UiTheme.GREEN)
			ci.draw_rect(Rect2(ac + Vector2(-1.5, 2), Vector2(3, 4)), UiTheme.GREEN)
		x += PIP_SIZE.x + 4.0
	if offer.sold:
		_draw_sold_stamp(ci)


func _draw_sold_stamp(ci: Control) -> void:
	var c := size * Vector2(0.5, 0.42)
	ci.draw_set_transform(c, -0.3, Vector2.ONE)
	var text := "SOLD"
	var fs := 34
	var w := UiTheme.title_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var box := Rect2(Vector2(-w * 0.5 - 10, -fs * 0.62), Vector2(w + 20, fs * 1.2))
	ci.draw_rect(box, Color(0.25, 0.04, 0.03, 0.55))
	ci.draw_rect(box, UiTheme.RED, false, 3.0)
	ci.draw_string_outline(UiTheme.title_font(), Vector2(-w * 0.5, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, UiTheme.OUTLINE)
	ci.draw_string(UiTheme.title_font(), Vector2(-w * 0.5, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.RED.lightened(0.15))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
