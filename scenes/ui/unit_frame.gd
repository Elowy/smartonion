class_name UnitFrame
extends PanelContainer
## WoW-style unit frame of one player (GDD 12): round portrait in the player's colour with the
## class initial, "P1 · Warrior", green HP bar with "hp / max", the class resources
## (ResourceDisplay: a coloured bar with "value / max", pips for Holy Power / Soul Shards /
## Combo Points - live from player.abilities), the ability bar underneath (AbilityBar: the core
## ability icons with this player's button prompts, cooldown sweep and dimming) and a DOWNED
## overlay with the revive progress over the bars.
## Right-hand frames (P2, P4) are mirrored: portrait on the outside edge.

## Compact (it sits in a screen corner over the playfield): ~340 x 100 reference px.
const WIDTH := 340.0
const PORTRAIT_SIZE := 76.0
## Panel fill opacity – the battlefield shows through a little.
const PANEL_ALPHA := 0.8
## Smallest text on the frame (resource name, revive hint): readable at 720p.
const SMALL_FONT := 18

var index := 0
var mirrored := false
var player: Player

var portrait: UiPortrait
var hp_bar: UiBar
var resource_display: ResourceDisplay
var ability_bar: AbilityBar
## The first resource shown as a bar (the primary one; null for a class whose resources are all
## pips, and while no player is bound).
var resource_bar: UiBar:
	get:
		return resource_display.first_bar() if resource_display != null else null
var name_label: Label
var downed_overlay: PanelContainer
var revive_bar: UiBar

var _player_label: Label
var _class_label: Label
var _bound := false


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
	style.content_margin_left = 10
	style.content_margin_right = 12
	style.content_margin_top = 7
	style.content_margin_bottom = 6
	style.fill = Color(0.1, 0.085, 0.075, PANEL_ALPHA)
	style.shadow_color = Color(0, 0, 0, 0.4)
	if mirrored:
		style.content_margin_left = 12
		style.content_margin_right = 10
	add_theme_stylebox_override(&"panel", style.rebuild())

	# Portrait + bars on top, the ability bar under them.
	var outer := UiTheme.vbox(4)
	add_child(outer)
	var row := UiTheme.hbox(10)
	outer.add_child(row)
	portrait = UiPortrait.create(PORTRAIT_SIZE)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var col := UiTheme.vbox(3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var name_row := UiTheme.hbox(5)
	name_row.alignment = BoxContainer.ALIGNMENT_END if mirrored else BoxContainer.ALIGNMENT_BEGIN
	_player_label = UiTheme.label("P%d" % (index + 1), UiTheme.GOLD_LABEL, 21)
	name_row.add_child(_player_label)
	name_row.add_child(UiTheme.label("·", UiTheme.DIM, 21))
	_class_label = UiTheme.label("Warrior", UiTheme.GOLD_LABEL, 21)
	name_row.add_child(_class_label)
	name_label = _class_label
	col.add_child(name_row)

	# Bars and the DOWNED overlay share one cell (MarginContainer stacks its children).
	var stack := MarginContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(stack)
	var bars := UiTheme.vbox(3)
	stack.add_child(bars)
	hp_bar = UiBar.create(UiTheme.HP_GREEN, 25.0, SMALL_FONT)
	bars.add_child(hp_bar)
	resource_display = ResourceDisplay.create(SMALL_FONT)
	bars.add_child(resource_display)

	downed_overlay = PanelContainer.new()
	downed_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(0.2, 0.03, 0.03, 1.0)
	ds.border_color = UiTheme.RED.darkened(0.25)
	ds.set_border_width_all(2)
	ds.set_corner_radius_all(4)
	ds.content_margin_left = 8
	ds.content_margin_right = 8
	ds.content_margin_top = 0
	ds.content_margin_bottom = 2
	downed_overlay.add_theme_stylebox_override(&"panel", ds)
	var dbox := UiTheme.vbox(0)
	dbox.alignment = BoxContainer.ALIGNMENT_CENTER
	downed_overlay.add_child(dbox)
	var top := UiTheme.hbox(8)
	top.add_child(UiTheme.label("DOWNED", UiTheme.HEADING, 21, UiTheme.RED))
	revive_bar = UiBar.create(Color(0.55, 1.0, 0.45), 12.0, 12)
	revive_bar.animated = false
	revive_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(revive_bar)
	dbox.add_child(top)
	dbox.add_child(UiTheme.label("Stand close to revive", &"", SMALL_FONT, UiTheme.TEXT))
	downed_overlay.visible = false
	stack.add_child(downed_overlay)

	if mirrored:
		row.add_child(col)
		row.add_child(portrait)
	else:
		row.add_child(portrait)
		row.add_child(col)
	ability_bar = AbilityBar.create(mirrored)
	outer.add_child(ability_bar)
	visible = false


## Connects to [param p] (null unbinds). Frames follow hp_changed / downed_changed /
## damage_taken and hide themselves when the player is freed.
func bind(p: Player) -> void:
	unbind()
	if not is_instance_valid(p):
		return
	player = p
	_bound = true
	var slot := p.slot
	var color := slot.color if slot != null else PlayerManager.PLAYER_COLORS[index % PlayerManager.PLAYER_COLORS.size()]
	var data := p.class_data
	portrait.setup(color, data)
	_player_label.text = slot.label() if slot != null else "P%d" % (index + 1)
	_player_label.add_theme_color_override(&"font_color", color.lightened(0.3))
	_class_label.text = data.display_name if data != null else "Hero"
	resource_display.bind(p.abilities, data)
	ability_bar.bind(p.abilities, slot.input if slot != null else null)
	p.hp_changed.connect(_on_hp_changed)
	p.downed_changed.connect(_on_downed_changed)
	p.damage_taken.connect(_on_damage_taken)
	hp_bar.animated = false
	_on_hp_changed(p.hp, p.max_hp())
	hp_bar.animated = true
	_on_downed_changed(p.downed)
	visible = true


func unbind() -> void:
	if is_instance_valid(player):
		if player.hp_changed.is_connected(_on_hp_changed):
			player.hp_changed.disconnect(_on_hp_changed)
		if player.downed_changed.is_connected(_on_downed_changed):
			player.downed_changed.disconnect(_on_downed_changed)
		if player.damage_taken.is_connected(_on_damage_taken):
			player.damage_taken.disconnect(_on_damage_taken)
	player = null
	_bound = false
	resource_display.unbind()
	ability_bar.unbind()
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
	if not _bound:
		return
	if not is_instance_valid(player) or player.is_queued_for_deletion():
		player = null
		_bound = false
		resource_display.unbind()
		ability_bar.unbind()
		visible = false
		return
	if player.downed:
		revive_bar.set_values(player.revive_progress, Player.REVIVE_TIME)
