class_name ConsumableTooltip
extends ItemTooltip
## The tooltip of a consumables-row card (ShopPanel): the name in the kind's colour, "Potion" /
## "Food" with how long it lasts, the effect lines in tooltip green, the flavour text in gold
## quotes, a red "Replaces: ..." line when the viewing hero already has a pending consumable of
## that kind (the new one pushes it out, no refund) and the price. It is an [ItemTooltip] so the
## stall places it with the same code (scale, position, layout_now, owner tag and colour); it
## just never holds an item.

const MIN_WIDTH := 300.0

var consumable: ConsumableData


static func create_consumable() -> ConsumableTooltip:
	var t := ConsumableTooltip.new()
	t.name = "ConsumableTooltip"
	t.theme = UiTheme.get_theme()
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.custom_minimum_size = Vector2(MIN_WIDTH, 0)
	t._box = UiTheme.vbox(3)
	t.add_child(t._box)
	t.add_theme_stylebox_override(&"panel", frame_style(0))
	t.minimum_size_changed.connect(t._shrink_to_fit, CONNECT_DEFERRED)
	t.visible = false
	return t


## Shows [param data] at [param p_price]; [param replaced] = the viewer hero's pending consumable of
## the same kind (null = none).
func show_consumable(data: ConsumableData, p_price: int, replaced: ConsumableData = null) -> void:
	consumable = data
	price = p_price
	item = null
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	if data == null:
		visible = false
		return
	var kind_color := ConsumableIcon.border_color(data)
	var style := frame_style(0)
	style.border = kind_color.darkened(0.1)
	if owner_tag != "":
		style.border = owner_color
		style.border_width = 3
		_line(owner_tag, owner_color, SMALL_SIZE, UiTheme.bold_font())
	add_theme_stylebox_override(&"panel", style)
	var title := _line(data.display_name, kind_color.lightened(0.25), NAME_SIZE, UiTheme.bold_font())
	title.add_theme_constant_override(&"outline_size", 6)
	_line("%s – lasts one wave" % Consumables.kind_name(data), YELLOW, SMALL_SIZE)
	for text in Consumables.effect_lines(data):
		_line(text, ENCHANT_GREEN, BODY_SIZE)
	_line("Takes effect when the next wave starts.", DIM, SMALL_SIZE)
	if data.description != "":
		var flavor := _line("\"%s\"" % data.description, YELLOW, SMALL_SIZE, _italic_font())
		flavor.add_theme_constant_override(&"outline_size", 3)
	if replaced != null:
		_line("Replaces: %s" % replaced.display_name, UNUSABLE_RED, SMALL_SIZE)
	_price_row("Price:", p_price, YELLOW if RunState.gold >= p_price else UNUSABLE_RED, BODY_SIZE)
	visible = true
