class_name UnitFrame
extends PanelContainer
## WoW-style unit frame of one player (GDD 12): round portrait in the player's colour with the
## class initial, "P1 · Warrior", green HP bar with "hp / max", the class resource bar (a full
## placeholder bar until abilities arrive in M3) and a DOWNED overlay with the revive progress.
## Right-hand frames (P2, P4) are mirrored: portrait on the outside edge.

const WIDTH := 430.0
const PORTRAIT_SIZE := 96.0

var index := 0
var mirrored := false
var player: Player

var portrait: UiPortrait
var hp_bar: UiBar
var resource_bar: UiBar
var name_label: Label
var downed_overlay: PanelContainer
var revive_bar: UiBar

var _player_label: Label
var _class_label: Label


static func create(p_index: int, p_mirrored: bool = false) -> UnitFrame:
	var f := UnitFrame.new()
	f.index = p_index
	f.mirrored = p_mirrored
	f.name = "UnitFrame%d" % (p_index + 1)
	f._build()
	return f


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, 0)
	var style := UiTheme.card_style()
	style.content_margin_left = 12
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.fill = Color(0.1, 0.085, 0.075, 0.9)
	if mirrored:
		style.content_margin_left = 14
		style.content_margin_right = 12
	add_theme_stylebox_override(&"panel", style.rebuild())

	var row := UiTheme.hbox(12)
	add_child(row)
	portrait = UiPortrait.create(PORTRAIT_SIZE)

	var col := UiTheme.vbox(5)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var name_row := UiTheme.hbox(6)
	name_row.alignment = BoxContainer.ALIGNMENT_END if mirrored else BoxContainer.ALIGNMENT_BEGIN
	_player_label = UiTheme.label("P%d" % (index + 1), UiTheme.GOLD_LABEL, 24)
	name_row.add_child(_player_label)
	name_row.add_child(UiTheme.label("·", UiTheme.DIM, 24))
	_class_label = UiTheme.label("Warrior", UiTheme.GOLD_LABEL, 24)
	name_row.add_child(_class_label)
	name_label = _class_label
	col.add_child(name_row)

	# Bars and the DOWNED overlay share one cell (MarginContainer stacks its children).
	var stack := MarginContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(stack)
	var bars := UiTheme.vbox(5)
	stack.add_child(bars)
	hp_bar = UiBar.create(UiTheme.HP_GREEN, 30.0, 19)
	bars.add_child(hp_bar)
	resource_bar = UiBar.create(Color(0.85, 0.15, 0.1), 17.0, 14)
	resource_bar.animated = false
	bars.add_child(resource_bar)

	downed_overlay = PanelContainer.new()
	downed_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(0.2, 0.03, 0.03, 1.0)
	ds.border_color = UiTheme.RED.darkened(0.25)
	ds.set_border_width_all(2)
	ds.set_corner_radius_all(4)
	ds.content_margin_left = 10
	ds.content_margin_right = 10
	ds.content_margin_top = 1
	ds.content_margin_bottom = 4
	downed_overlay.add_theme_stylebox_override(&"panel", ds)
	var dbox := UiTheme.vbox(1)
	dbox.alignment = BoxContainer.ALIGNMENT_CENTER
	downed_overlay.add_child(dbox)
	var top := UiTheme.hbox(10)
	top.add_child(UiTheme.label("DOWNED", UiTheme.HEADING, 24, UiTheme.RED))
	revive_bar = UiBar.create(Color(0.55, 1.0, 0.45), 12.0, 12)
	revive_bar.animated = false
	revive_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(revive_bar)
	dbox.add_child(top)
	dbox.add_child(UiTheme.label("Stand next to them to revive", &"", 15, UiTheme.TEXT))
	downed_overlay.visible = false
	stack.add_child(downed_overlay)

	if mirrored:
		row.add_child(col)
		row.add_child(portrait)
	else:
		row.add_child(portrait)
		row.add_child(col)
	visible = false


## Connects to [param p] (null unbinds). Frames follow hp_changed / downed_changed /
## damage_taken and hide themselves when the player is freed.
func bind(p: Player) -> void:
	unbind()
	player = p
	if p == null or not is_instance_valid(p):
		player = null
		visible = false
		return
	var slot := p.slot
	var color := slot.color if slot != null else PlayerManager.PLAYER_COLORS[index % PlayerManager.PLAYER_COLORS.size()]
	var data := p.class_data
	portrait.setup(color, data)
	_player_label.text = slot.label() if slot != null else "P%d" % (index + 1)
	_player_label.add_theme_color_override(&"font_color", color.lightened(0.3))
	_class_label.text = data.display_name if data != null else "Hero"
	if data != null:
		resource_bar.set_fill_color(data.resource_color)
		resource_bar.set_values(1.0, 1.0, UiTheme.resource_name(data.resource_type))
	p.hp_changed.connect(_on_hp_changed)
	p.downed_changed.connect(_on_downed_changed)
	p.damage_taken.connect(_on_damage_taken)
	hp_bar.animated = false
	_on_hp_changed(p.hp, p.max_hp())
	hp_bar.animated = true
	_on_downed_changed(p.downed)
	visible = true


func unbind() -> void:
	if player != null and is_instance_valid(player):
		if player.hp_changed.is_connected(_on_hp_changed):
			player.hp_changed.disconnect(_on_hp_changed)
		if player.downed_changed.is_connected(_on_downed_changed):
			player.downed_changed.disconnect(_on_downed_changed)
		if player.damage_taken.is_connected(_on_damage_taken):
			player.damage_taken.disconnect(_on_damage_taken)
	player = null
	visible = false


func is_downed_shown() -> bool:
	return downed_overlay.visible


func _on_hp_changed(hp: float, max_hp: float) -> void:
	hp_bar.set_values(hp, max_hp, "%s / %s" % [UiTheme.format_amount(hp), UiTheme.format_amount(max_hp)])


func _on_downed_changed(is_downed: bool) -> void:
	downed_overlay.visible = is_downed
	portrait.set_downed(is_downed)
	revive_bar.set_values(0.0, 1.0)


func _on_damage_taken(_amount: float, _source: Node3D) -> void:
	portrait.flash_hit()


func _process(_delta: float) -> void:
	if player == null:
		return
	if not is_instance_valid(player) or player.is_queued_for_deletion():
		player = null
		visible = false
		return
	if player.downed:
		revive_bar.set_values(player.revive_progress, Player.REVIVE_TIME)
