class_name UnitFrame
extends PanelContainer
## WoW-style unit frame of one player (GDD 12): round portrait in the player's colour with the
## class initial, "P1 · Warrior", green HP bar with "hp / max", the class resources
## (ResourceDisplay: a coloured bar with "value / max", pips for Holy Power / Soul Shards; a
## secondary pip row - the Rogue's Combo Points - sits inline at the inner end of the name row),
## the ability icons beside the bars on the frame's inner side (AbilityBar: RT / LT core and
## RB / LB learned Active abilities with this player's button prompts, then the 2 x 2 cluster of
## learned Auto-cast abilities behind a gear mark; cooldown sweep, dimming and rank pips on
## every icon) and a DOWNED overlay over the bars: the revive progress (teammates' or the Spirit
## Healer's, whichever is further along) and the hint "Go to the Spirit Healer" (or, in a level
## without a Spirit Healer, the dungeon, "Only a teammate can revive you").
## Right-hand frames (P2, P4) are mirrored: portrait on the outside edge, icons on the inside.
## Learned abilities make the frame wider (towards the screen centre), never taller.
## M6: the hero's active consumables (flask / elixir, food – Player.consumables_active) show as
## small ConsumableIcons behind the class name in the name row ([member consumable_icons]).

## Compact (it sits in a screen corner over the playfield): ~430 x 104 reference px with the
## core abilities, up to MAX_WIDTH with every learned slot filled. The height matters most – CameraRig keeps the heroes out of full-width bands at the top / bottom of the
## screen, so frames must stay within MAX_HEIGHT (alive, downed, with pips).
const WIDTH := 430.0
const MAX_HEIGHT := 112.0
## Widest frame (all eight ability slots filled): the top frames must leave the wave / timer
## plaque in the middle free (1920 px canvas).
const MAX_WIDTH := 640.0
const PORTRAIT_SIZE := 76.0
## Ability icon side (the prompt pill hangs AbilityIcon.PROMPT_OVERHANG below it).
const ABILITY_ICON_SIZE := 42.0
## Side of the small consumable icons in the name row.
const CONSUMABLE_ICON_SIZE := 24.0
## The HP / resource bars never get narrower than this (learned slots widen the frame instead).
const BARS_MIN_WIDTH := 214.0
## Panel fill opacity – the battlefield shows through a little.
const PANEL_ALPHA := 0.8
## Smallest text on the frame (resource name, revive hint): readable at 720p.
const SMALL_FONT := 18
## Shown while downed: what a ghost should do (GDD 1 – 1 s in the healer's circle = full HP).
const GHOST_HINT := "Go to the Spirit Healer"
## Shown while downed where no Spirit Healer waits (M6b: a hardcore run's clearing, the dungeon): a teammate
## has to revive the hero.
const TEAMMATE_HINT := "Only a teammate can revive you"
const WAITING_HINT := "Spirit Healer: %d s"
const SICKNESS_HINT := "Resurrection Sickness: %d s"
## Hint text and revive bar fill (pale spirit blue while the Spirit Healer channels).
const GHOST_HINT_COLOR := Color(0.74, 0.9, 1.0)
const REVIVE_BAR_COLOR := Color(0.55, 1.0, 0.45)

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
## Inline holder at the inner end of the name row for secondary pip rows (Combo Points).
var name_pips: HBoxContainer
## The small icons of the hero's active consumables, behind the class name.
var consumable_icons: HBoxContainer
var downed_overlay: PanelContainer
var revive_bar: UiBar
var hint_label: Label

var _player_label: Label
var _class_label: Label
var _bound := false
## The cell the bars and the DOWNED overlay share.
var _bars_cell: MarginContainer


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

	# [portrait | name row over (bars | ability icons)], mirrored on the right-hand side.
	var row := UiTheme.hbox(10)
	add_child(row)
	portrait = UiPortrait.create(PORTRAIT_SIZE)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var col := UiTheme.vbox(3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var name_row := UiTheme.hbox(5)
	_player_label = UiTheme.label("P%d" % (index + 1), UiTheme.GOLD_LABEL, 21)
	var dot := UiTheme.label("·", UiTheme.DIM, 21)
	_class_label = UiTheme.label("Warrior", UiTheme.GOLD_LABEL, 21)
	name_label = _class_label
	name_pips = UiTheme.hbox(0)
	name_pips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_pips.alignment = BoxContainer.ALIGNMENT_BEGIN if mirrored else BoxContainer.ALIGNMENT_END
	consumable_icons = UiTheme.hbox(3)
	consumable_icons.name = "ConsumableIcons"
	consumable_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	consumable_icons.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var name_parts: Array[Control] = [_player_label, dot, _class_label, consumable_icons]
	if mirrored:
		name_parts.push_front(name_pips)
	else:
		name_parts.append(name_pips)
	for c in name_parts:
		name_row.add_child(c)
	col.add_child(name_row)

	var lower := UiTheme.hbox(8)
	col.add_child(lower)
	# Bars and the DOWNED overlay share one cell (MarginContainer stacks its children).
	var stack := MarginContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.custom_minimum_size = Vector2(BARS_MIN_WIDTH, 0)
	_bars_cell = stack
	var bars := UiTheme.vbox(3)
	bars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stack.add_child(bars)
	hp_bar = UiBar.create(UiTheme.HP_GREEN, 25.0, SMALL_FONT)
	bars.add_child(hp_bar)
	resource_display = ResourceDisplay.create(SMALL_FONT)
	resource_display.inline_holder = name_pips
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
	revive_bar = UiBar.create(REVIVE_BAR_COLOR, 12.0, 12)
	revive_bar.animated = false
	revive_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(revive_bar)
	dbox.add_child(top)
	hint_label = UiTheme.label(GHOST_HINT, &"", SMALL_FONT, GHOST_HINT_COLOR)
	dbox.add_child(hint_label)
	downed_overlay.visible = false
	stack.add_child(downed_overlay)

	ability_bar = AbilityBar.create(mirrored, ABILITY_ICON_SIZE)
	ability_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if mirrored:
		lower.add_child(ability_bar)
		lower.add_child(stack)
		row.add_child(col)
		row.add_child(portrait)
	else:
		lower.add_child(stack)
		lower.add_child(ability_bar)
		row.add_child(portrait)
		row.add_child(col)
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
	p.consumables_changed.connect(_refresh_consumables)
	_refresh_consumables()
	hp_bar.animated = false
	_on_hp_changed(p.hp, p.max_hp())
	hp_bar.animated = true
	_on_downed_changed(p.downed)
	visible = true
	_fit_bars_cell()


## Makes the bars cell as tall as the DOWNED overlay, so the frame keeps its height when the
## player goes down (the themed text sizes are only known once the frame is in the tree).
func _fit_bars_cell() -> void:
	var shown := downed_overlay.visible
	downed_overlay.visible = true
	_bars_cell.custom_minimum_size.y = downed_overlay.get_combined_minimum_size().y
	downed_overlay.visible = shown


func unbind() -> void:
	if is_instance_valid(player):
		if player.hp_changed.is_connected(_on_hp_changed):
			player.hp_changed.disconnect(_on_hp_changed)
		if player.downed_changed.is_connected(_on_downed_changed):
			player.downed_changed.disconnect(_on_downed_changed)
		if player.damage_taken.is_connected(_on_damage_taken):
			player.damage_taken.disconnect(_on_damage_taken)
		if player.consumables_changed.is_connected(_refresh_consumables):
			player.consumables_changed.disconnect(_refresh_consumables)
	player = null
	_bound = false
	resource_display.unbind()
	ability_bar.unbind()
	_clear_consumables()
	visible = false


func is_downed_shown() -> bool:
	return downed_overlay.visible


## Rebuilds the small consumable icons from the hero's active consumables (potion first).
func _refresh_consumables() -> void:
	_clear_consumables()
	if not is_instance_valid(player):
		return
	for data in player.consumables_active:
		var icon := ConsumableIcon.create(data, CONSUMABLE_ICON_SIZE)
		icon.name = "Icon_%s" % data.id
		consumable_icons.add_child(icon)


func _clear_consumables() -> void:
	for c in consumable_icons.get_children():
		consumable_icons.remove_child(c)
		c.queue_free()


## The consumables whose icons are shown (tests, screenshots).
func shown_consumables() -> Array[ConsumableData]:
	var out: Array[ConsumableData] = []
	for c in consumable_icons.get_children():
		if c is ConsumableIcon and not c.is_queued_for_deletion():
			out.append((c as ConsumableIcon).data)
	return out


func _on_hp_changed(hp: float, max_hp: float) -> void:
	hp_bar.set_values(hp, max_hp, "%s / %s" % [UiTheme.format_amount(hp), UiTheme.format_amount(max_hp)])


func _on_downed_changed(is_downed: bool) -> void:
	downed_overlay.visible = is_downed
	portrait.set_downed(is_downed)
	revive_bar.set_values(0.0, 1.0)


## The ghost hint: Resurrection Sickness time left, else the Spirit Healer's next pulse
## ("Spirit Healer: 7 s" while waiting in its circle, "Go to the Spirit Healer (7 s)" else). Where there is no
## Spirit Healer - a hardcore run, or an arena without one (the dungeon) - it is [constant TEAMMATE_HINT].
func _update_hint() -> void:
	var arena: Arena = Arena.current if is_instance_valid(Arena.current) else null
	var healer: SpiritHealer = arena.spirit_healer if arena != null else null
	var has_healer := healer != null and is_instance_valid(healer)
	var text := GHOST_HINT
	var color := GHOST_HINT_COLOR
	if player.res_sickness_left > 0.0:
		text = SICKNESS_HINT % ceili(player.res_sickness_left)
		color = Player.RES_SICKNESS_TEXT_COLOR
	elif RunState.hardcore or (arena != null and not has_healer):
		text = TEAMMATE_HINT
	elif has_healer:
		var secs := ceili(maxf(0.0, healer.pulse_left))
		text = (WAITING_HINT % secs) if player.healer_channel > 0.0 else (GHOST_HINT + " (%d s)" % secs)
	if hint_label.text != text:
		hint_label.text = text
		hint_label.add_theme_color_override(&"font_color", color)


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
		_clear_consumables()
		visible = false
		return
	if player.downed:
		# Whichever revive is further along: teammates standing close or the Spirit Healer.
		var mates := player.revive_progress / Player.REVIVE_TIME
		var healer := player.healer_channel > mates
		revive_bar.fill_color = SpiritHealer.CAST_COLOR if healer else REVIVE_BAR_COLOR
		revive_bar.set_values(player.healer_channel if healer else mates, 1.0)
		_update_hint()
