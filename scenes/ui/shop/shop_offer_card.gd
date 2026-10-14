class_name ShopOfferCard
extends Control
## One offer on the goblin's stall (ShopPanel): the item icon, its name in the rarity colour,
## slot / armor type, the price with a coin (red while the shared wallet cannot pay it), a
## padlock in the colour of the player who locked it, "P2 wants" tags for pings, one small
## usable-by pip per player (crossed out when that class cannot use it, a green arrow when it
## is an upgrade for that player – ItemTooltip.upgrade_direction with the player's equipment,
## so completing a tier-set bonus counts), a small anvil in the player's colour sitting on the pip of
## every player who has a forge partner for the offered weapon (Forge.offer_forge_slots – full
## backpack or not, GDD 4.1) and a "SOLD" stamp once bought.
## M6: the same card, in its WIDE layout and with a gold frame ([member gold_frame]), is the Black
## Market offer beside the consumables row ([method create_wide]): icon on the left, name and price
## on the right, the pips below, [constant WIDE_SIZE] big (no type line – the tooltip has it).
## The wide card keeps its overlays off the content: the name stops short of the lock badge
## ([constant NAME_LOCK_RESERVE]) and the "P2 wants" tags sit in the band under the name, right of
## the icon ([method ping_tags]), never on the icon.

## Four of these (two rows) + the consumables row must fit the 4-player stall (ShopPanel).
const CARD_SIZE := Vector2(124, 176)
## The Black Market card.
const WIDE_SIZE := Vector2(200, 96)
const ICON_SIZE := 46.0
## Two lines of the 16 px bold name.
const NAME_HEIGHT := 44.0
const PIP_SIZE := Vector2(24, 18)
## The anvil drawn on a usable-by pip (forge partner) – width x height.
const ANVIL_SIZE := Vector2(22, 13)
## The padlock badge: radius of its dark disc and its top-left corner measured from the card's
## top-right corner (the disc is centred on the 20 px padlock).
const LOCK_BADGE_RADIUS := 14.0
const LOCK_OFFSET := Vector2(28, 8)
## Wide card: width taken off the name label so a locked card's padlock never covers the name
## (the badge disc is 2 * LOCK_BADGE_RADIUS wide).
const NAME_LOCK_RESERVE := 28.0
## Ping tags: height of a tag, gap between tags and the padding left / right of the text.
const PING_TAG_HEIGHT := 20.0
const PING_TAG_GAP := 3.0
const PING_TAG_PAD := 12.0
## Wide card: the tag row (its height, and the x it starts at so it clears the price).
const WIDE_PING_HEIGHT := 18.0
const WIDE_PING_X := 66.0

var index := -1
var offer: Shop.Offer
## The wide Black Market layout (see [method create_wide]).
var wide := false
## A gold frame instead of the rarity-coloured one (the Black Market card).
var gold_frame := false
var icon: ItemIcon
var name_label: Label
var type_label: Label
var price_label: Label

## Per joined slot index: 0 = cannot use, 1 = can use, 2 = can use and an upgrade.
var _usable: Dictionary[int, int] = {}
## Slot indices with a forge partner for the offered weapon (anvil pips).
var _forge: Array[int] = []
var _colors: Dictionary[int, Color] = {}
var _content: BoxContainer
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


## The Black Market card: [constant WIDE_SIZE], icon beside the text, gold frame.
static func create_wide(p_index: int) -> ShopOfferCard:
	var card := ShopOfferCard.new()
	card.name = "BlackMarket"
	card.index = p_index
	card.wide = true
	card.gold_frame = true
	card.custom_minimum_size = WIDE_SIZE
	card.size = WIDE_SIZE
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
	var text_width := custom_minimum_size.x - 12.0
	_content = UiTheme.vbox(2)
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.offset_left = 6
	_content.offset_right = -6
	_content.offset_top = 6
	# The usable-by pips sit in the bottom strip: the stacked card keeps it free, the wide card
	# puts its price into the strip's left half instead.
	_content.offset_bottom = -4 if wide else -26
	add_child(_content)
	icon = ItemIcon.create(null, ICON_SIZE)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wide:
		text_width -= ICON_SIZE + 6.0 + NAME_LOCK_RESERVE
	name_label = UiTheme.centered_label("", &"", 16)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.max_lines_visible = 2
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.custom_minimum_size = Vector2(text_width, NAME_HEIGHT)
	name_label.add_theme_font_override(&"font", UiTheme.bold_font())
	name_label.add_theme_constant_override(&"line_spacing", -3)
	type_label = UiTheme.centered_label("", UiTheme.SMALL, 14)
	type_label.clip_text = true
	type_label.custom_minimum_size = Vector2(text_width, 0)
	var price_row := UiTheme.hbox(5)
	price_row.alignment = BoxContainer.ALIGNMENT_BEGIN if wide else BoxContainer.ALIGNMENT_CENTER
	_coin = UiIcon.create(UiIcon.Kind.COIN, Vector2(18, 18))
	_coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	price_row.add_child(_coin)
	price_label = UiTheme.label("0", UiTheme.GOLD_LABEL, 20)
	price_row.add_child(price_label)
	if wide:
		# [icon | name] on top, the price at the bottom left, the pips at the bottom right.
		var top := UiTheme.hbox(6)
		_content.add_child(top)
		top.add_child(icon)
		# Not expanding: the label keeps its width and leaves the lock's column free.
		name_label.size_flags_horizontal = Control.SIZE_FILL
		name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(name_label)
		type_label.visible = false
		_content.add_child(type_label)
		_content.add_child(UiTheme.spacer(true))
		_content.add_child(price_row)
	else:
		_content.add_child(icon)
		_content.add_child(name_label)
		_content.add_child(type_label)
		_content.add_child(price_row)

	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_lock = UiIcon.create(UiIcon.Kind.LOCK, Vector2(20, 20))
	_lock.position = Vector2(custom_minimum_size.x - LOCK_OFFSET.x, LOCK_OFFSET.y)
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
	_forge = Forge.offer_forge_slots(item, slots) if item != null else ([] as Array[int])
	for s in slots:
		_colors[s.index] = s.color
		if item == null:
			continue
		var level := 0
		if item.can_be_used_by(s.class_data):
			level = 1
			var eq := ShopPanel.equipment_of(s)
			if eq != null:
				var current := ItemTooltip.equipped_for_compare(item, eq)
				if ItemTooltip.upgrade_direction(item, current, s.class_data, eq) > 0:
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


## Whether the player of [param slot_index] has a forge partner for this offer (anvil pip).
func has_anvil(slot_index: int) -> bool:
	return slot_index in _forge


## Slot indices with an anvil pip, in slot order (tests, screenshots).
func anvil_slots() -> Array[int]:
	var out: Array[int] = _forge.duplicate()
	out.sort()
	return out


## The padlock badge's disc in the card's coordinates (what the lock covers when it is shown).
func lock_badge_rect() -> Rect2:
	var center := _lock.position + _lock.size * 0.5
	return Rect2(center - Vector2.ONE * LOCK_BADGE_RADIUS, Vector2.ONE * (2.0 * LOCK_BADGE_RADIUS))


## The "P2 wants" tags of the offer's pings, in the card's coordinates:
## [{"slot": int, "text": String, "rect": Rect2}] in ping order.
##   - stacked card: a column from the top left corner (below the cursor corner tags);
##   - wide card: one row in the band under the name, right of the icon ([constant WIDE_PING_X]),
##     with the short "P2" text when the full "P2 wants" tags would not fit the row.
func ping_tags() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if offer == null:
		return out
	var font := UiTheme.bold_font()
	if not wide:
		var y := 14.0
		for slot_index in offer.pinged_by:
			var text := "P%d wants" % (slot_index + 1)
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + PING_TAG_PAD
			out.append({"slot": slot_index, "text": text, "rect": Rect2(4, y, w, PING_TAG_HEIGHT)})
			y += PING_TAG_HEIGHT + PING_TAG_GAP
		return out
	var x0 := WIDE_PING_X
	var y0 := 6.0 + ICON_SIZE
	var limit := custom_minimum_size.x - 6.0
	var short := false
	for _attempt in 2:
		out.clear()
		var x := x0
		for slot_index in offer.pinged_by:
			var text := ("P%d" if short else "P%d wants") % (slot_index + 1)
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + PING_TAG_PAD
			out.append({"slot": slot_index, "text": text, "rect": Rect2(x, y0, w, WIDE_PING_HEIGHT)})
			x += w + PING_TAG_GAP
		if out.is_empty() or x - PING_TAG_GAP <= limit:
			break
		short = true
	return out


## A small anvil (pointed horn to the left, flat face, waist, flared foot) centred on
## [param center], [param box] wide and high: a dark rim, then [param color], then a highlight
## along the face (readable on a pip of the same colour).
static func draw_anvil(ci: CanvasItem, center: Vector2, box: Vector2, color: Color) -> void:
	var w := box.x
	var h := box.y
	var top := center.y - h * 0.5
	var left := center.x - w * 0.5
	var pts := PackedVector2Array([
		Vector2(left, top + h * 0.08),               # horn tip
		Vector2(left + w * 0.25, top),               # face
		Vector2(left + w, top),
		Vector2(left + w, top + h * 0.4),
		Vector2(left + w * 0.74, top + h * 0.48),    # waist
		Vector2(left + w * 0.74, top + h * 0.7),
		Vector2(left + w * 0.92, top + h),           # foot
		Vector2(left + w * 0.18, top + h),
		Vector2(left + w * 0.36, top + h * 0.7),
		Vector2(left + w * 0.36, top + h * 0.48),
		Vector2(left + w * 0.24, top + h * 0.42),    # under the horn
	])
	var outline := pts.duplicate()
	outline.append(pts[0])
	ci.draw_polyline(outline, Color(0, 0, 0, 0.9), 3.0, true)
	ci.draw_colored_polygon(pts, color)
	ci.draw_line(Vector2(left + w * 0.28, top + 1.2), Vector2(left + w - 1.2, top + 1.2), color.lightened(0.5), 1.2)


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
	if gold_frame:
		# The Black Market: a gold frame with a warm glow just inside it.
		var gold := UiTheme.GOLD_BORDER
		draw_rect(r.grow(-3.0), Color(gold, 0.2), false, 4.0)
		draw_rect(r, gold, false, 3.0)
		draw_rect(r.grow(-4.5), Color(0, 0, 0, 0.55), false, 1.0)
	else:
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
		ci.draw_circle(_lock.position + _lock.size * 0.5, LOCK_BADGE_RADIUS, Color(0.05, 0.04, 0.03, 0.9))
		ci.draw_arc(_lock.position + _lock.size * 0.5, LOCK_BADGE_RADIUS, 0.0, TAU, 24, _lock.color, 2.0, true)
	# "P2 wants" tags (the stacked card: below the cursor corner tags; the wide one: see ping_tags).
	for entry in ping_tags():
		var col: Color = _colors.get(entry["slot"], Color.WHITE)
		var tag: Rect2 = entry["rect"]
		var text: String = entry["text"]
		var base := Vector2(tag.position.x + 6, tag.position.y + tag.size.y - 5.0)
		ci.draw_rect(tag, Color(col.darkened(0.55), 0.92))
		ci.draw_rect(tag, col, false, 2.0)
		ci.draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, UiTheme.OUTLINE)
		ci.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	# Usable-by pips, one per player in slot order.
	var keys := _colors.keys()
	keys.sort()
	var total := keys.size() * PIP_SIZE.x + maxi(0, keys.size() - 1) * 4.0
	var x := (size.x - 7.0 - total) if wide else (size.x - total) * 0.5
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
		if slot_index in _forge and not offer.sold:
			# The anvil sits on top of the pip: "P1 can forge this".
			draw_anvil(ci, Vector2(pip.get_center().x, pip.position.y - ANVIL_SIZE.y * 0.5 - 2.0), ANVIL_SIZE, col.lightened(0.35))
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
