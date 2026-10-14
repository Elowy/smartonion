class_name ConsumableCard
extends Control
## One compact card of the stall's consumables row (ShopPanel, M6 SHOPSINKS): the picture
## (ConsumableIcon), the price with a coin (red while the shared wallet cannot pay it) and the name
## in the kind's colour (blue for flasks / elixirs, orange for food). Unlimited stock: there is no
## sold stamp, lock or ping, and no per-player marker – who bought what shows in the purse board's
## spend log and, from the next wave on, on the heroes' unit frames. The card is as wide as the row
## gives it ([method create]), [constant HEIGHT] high.

const HEIGHT := 96.0
const ICON_SIZE := 40.0
const NAME_SIZE := 15
## Two lines of the name.
const NAME_HEIGHT := 42.0

var index := -1
var offer: Shop.ConsumableOffer
var icon: ConsumableIcon
var name_label: Label
var price_label: Label

var _content: VBoxContainer
var _coin: UiIcon


static func create(p_index: int, p_width: float) -> ConsumableCard:
	var card := ConsumableCard.new()
	card.name = "Consumable%d" % p_index
	card.index = p_index
	card.custom_minimum_size = Vector2(p_width, HEIGHT)
	card.size = card.custom_minimum_size
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card._build()
	return card


func _build() -> void:
	_content = UiTheme.vbox(2)
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.offset_left = 6
	_content.offset_right = -6
	_content.offset_top = 6
	_content.offset_bottom = -4
	add_child(_content)
	var head := UiTheme.hbox(4)
	_content.add_child(head)
	icon = ConsumableIcon.create(null, ICON_SIZE)
	head.add_child(icon)
	head.add_child(UiTheme.spacer())
	var price_row := UiTheme.hbox(4)
	price_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_coin = UiIcon.create(UiIcon.Kind.COIN, Vector2(18, 18))
	_coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	price_row.add_child(_coin)
	price_label = UiTheme.label("0", UiTheme.GOLD_LABEL, 20)
	price_row.add_child(price_label)
	head.add_child(price_row)
	name_label = UiTheme.centered_label("", &"", NAME_SIZE)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.max_lines_visible = 2
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.custom_minimum_size = Vector2(0, NAME_HEIGHT)
	name_label.add_theme_font_override(&"font", UiTheme.bold_font())
	name_label.add_theme_constant_override(&"line_spacing", -3)
	_content.add_child(name_label)


## Shows [param p_offer] (null = empty position).
func set_offer(p_offer: Shop.ConsumableOffer) -> void:
	offer = p_offer
	var data := offer.data if offer != null else null
	icon.set_data(data)
	name_label.text = data.display_name if data != null else ""
	name_label.add_theme_color_override(&"font_color", ConsumableIcon.border_color(data).lightened(0.25) if data != null else UiTheme.TEXT)
	update_state()
	queue_redraw()


## Price and its colour (cheap; called on shop / wallet changes).
func update_state() -> void:
	var has := offer != null and offer.data != null
	_content.visible = has
	if has:
		price_label.text = UiTheme.format_int(offer.price)
		price_label.add_theme_color_override(&"font_color", UiTheme.RED if RunState.gold < offer.price else UiTheme.GOLD)
	queue_redraw()


func is_affordable() -> bool:
	return offer != null and RunState.gold >= offer.price


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var data := offer.data if offer != null else null
	var kc := ConsumableIcon.border_color(data)
	draw_rect(Rect2(r.position + Vector2(0, 4), r.size), Color(0, 0, 0, 0.35))
	draw_rect(r, Color(0.07, 0.055, 0.045, 0.96))
	if data != null:
		var glow := Color(kc, 0.14)
		var clear := Color(kc, 0.0)
		draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, 0), Vector2(r.end.x, r.size.y * 0.6), Vector2(0, r.size.y * 0.6)]),
			PackedColorArray([glow, glow, clear, clear]))
	draw_rect(r, Color(kc.darkened(0.35), 0.9 if data != null else 0.5), false, 2.0)
	draw_rect(r.grow(-3.0), Color(0, 0, 0, 0.5), false, 1.0)
