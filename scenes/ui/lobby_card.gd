class_name LobbyCard
extends PanelContainer
## One of the four lobby slots (GDD 12). Empty: "Press A to join". Joined: the player's
## colour and device, a live onion preview, the class (◀ ▶ to change), role, description,
## class stat bonuses, starting weapons, resource and the device's own button prompts.
## Lobby calls update_from(slot) every frame; the card only rebuilds when something changed.

const PREVIEW_HEIGHT := 150.0
const ABILITY_ICON_SIZE := 40.0
## The Mastery text is cut after this many lines: every class's mastery_text must fit in it
## at the 1080p canvas (test_ui_m3_lobby checks all Db classes).
const MASTERY_MAX_LINES := 3

var index := 0
var slot: PlayerSlot
var preview: OnionPreview

var _state_key := ""
var _was_ready := false
var _t := 0.0
var _arrow_kick := Vector2.ZERO  # x: left arrow, y: right arrow

# Empty view.
var _empty_box: VBoxContainer
var _join_glyph: UiGlyph
var _keyboard_hint: Label
var _empty_onion: UiIcon
# Joined view.
var _joined_box: VBoxContainer
var _header: PanelContainer
var _player_label: Label
var _device_label: Label
var _preview_frame: PanelContainer
var _preview_glow: TextureRect
var _ready_ribbon: PanelContainer
var _left_arrow: UiIcon
var _right_arrow: UiIcon
var _class_label: Label
var _role_label: Label
var _desc_label: Label
var _stats_grid: GridContainer
var _weapons_box: VBoxContainer
var _resource_dot: UiIcon
var _resource_label: Label
var _armor_label: Label
var _prompt_holder: CenterContainer
# Abilities / Mastery block (hidden for a class without M3 data).
var _abilities_panel: PanelContainer
var _ability_row: HBoxContainer
## One icon + name label per core ability of the shown class (for tests).
var ability_icons: Array[AbilityIcon] = []
var ability_name_labels: Array[Label] = []
var mastery_title_label: Label
var mastery_label: Label


static func create(p_index: int) -> LobbyCard:
	var c := LobbyCard.new()
	c.index = p_index
	c.name = "Card%d" % (p_index + 1)
	c._build()
	return c


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(300, 0)
	_build_empty()
	_build_joined()
	_apply_empty()


func _build_empty() -> void:
	_empty_box = UiTheme.vbox(14)
	_empty_box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_empty_box)
	var header := UiTheme.hbox()
	var p_label := UiTheme.label("P%d" % (index + 1), UiTheme.HEADING, 34, UiTheme.TEXT_DIM)
	header.add_child(p_label)
	header.add_child(UiTheme.spacer())
	header.add_child(UiTheme.label("Open slot", UiTheme.SMALL))
	_empty_box.add_child(header)
	_empty_box.add_child(UiTheme.spacer(true))
	_empty_onion = UiIcon.create(UiIcon.Kind.ONION, Vector2(200, 190), Color(0.4, 0.36, 0.34))
	_empty_onion.face = false
	_empty_onion.modulate = Color(1, 1, 1, 0.22)
	_empty_onion.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_empty_box.add_child(_empty_onion)
	_join_glyph = UiGlyph.pad(PlayerInput.Pad.A, 72.0)
	_join_glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_empty_box.add_child(_join_glyph)
	var press := UiTheme.centered_label("Press A to join", UiTheme.GOLD_LABEL, 34)
	_empty_box.add_child(press)
	_keyboard_hint = UiTheme.centered_label("Keyboard: Enter / Space / F", UiTheme.DIM)
	_empty_box.add_child(_keyboard_hint)
	_empty_box.add_child(UiTheme.spacer(true))


func _build_joined() -> void:
	_joined_box = UiTheme.vbox(5)
	add_child(_joined_box)

	_header = PanelContainer.new()
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hrow := UiTheme.hbox(10)
	_header.add_child(hrow)
	_player_label = UiTheme.label("P1", UiTheme.HEADING, 34, UiTheme.TEXT)
	hrow.add_child(_player_label)
	_device_label = UiTheme.label("Controller", &"", UiTheme.FONT_SMALL, UiTheme.TEXT)
	_device_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_device_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_device_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_device_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hrow.add_child(_device_label)
	_joined_box.add_child(_header)

	# Preview with the class arrows on its sides and the READY ribbon over it.
	_preview_frame = UiTheme.panel(UiTheme.INSET_PANEL)
	_preview_frame.custom_minimum_size = Vector2(0, PREVIEW_HEIGHT)
	_preview_frame.add_theme_stylebox_override(&"panel", _preview_style())
	_joined_box.add_child(_preview_frame)
	var stage := Control.new()
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.clip_contents = true
	_preview_frame.add_child(stage)
	_preview_glow = TextureRect.new()
	_preview_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_preview_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(_preview_glow)
	preview = OnionPreview.create()
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(preview)
	_ready_ribbon = _make_ready_ribbon()
	stage.add_child(_ready_ribbon)

	var class_row := UiTheme.hbox(6)
	_left_arrow = UiIcon.create(UiIcon.Kind.ARROW_LEFT, Vector2(34, 40), UiTheme.GOLD)
	_right_arrow = UiIcon.create(UiIcon.Kind.ARROW_RIGHT, Vector2(34, 40), UiTheme.GOLD)
	_class_label = UiTheme.centered_label("Warrior", UiTheme.HEADING, 42)
	_class_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	class_row.add_child(_left_arrow)
	class_row.add_child(_class_label)
	class_row.add_child(_right_arrow)
	_joined_box.add_child(class_row)
	_role_label = UiTheme.centered_label("Melee bruiser", UiTheme.DIM, UiTheme.FONT_BODY, Color(0.85, 0.8, 0.7))
	_joined_box.add_child(_role_label)

	_desc_label = UiTheme.wrapped_label("", &"", UiTheme.FONT_BODY - 1, Color(0.9, 0.87, 0.8))
	_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_label.custom_minimum_size.y = 52
	_joined_box.add_child(_desc_label)

	var info := UiTheme.panel(UiTheme.INSET_PANEL)
	_joined_box.add_child(info)
	var info_box := UiTheme.vbox(6)
	info.add_child(info_box)
	_stats_grid = GridContainer.new()
	_stats_grid.columns = 2
	_stats_grid.add_theme_constant_override(&"h_separation", 18)
	_stats_grid.add_theme_constant_override(&"v_separation", 2)
	_stats_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_box.add_child(_stats_grid)
	_weapons_box = UiTheme.vbox(2)
	info_box.add_child(_weapons_box)
	var res_row := UiTheme.hbox(8)
	_resource_dot = UiIcon.create(UiIcon.Kind.COIN, Vector2(18, 18))
	res_row.add_child(_resource_dot)
	_resource_label = UiTheme.label("Rage", &"", UiTheme.FONT_SMALL + 1)
	res_row.add_child(_resource_label)
	res_row.add_child(UiTheme.spacer())
	_armor_label = UiTheme.label("Plate", UiTheme.SMALL)
	res_row.add_child(_armor_label)
	info_box.add_child(res_row)

	_abilities_panel = UiTheme.panel(UiTheme.INSET_PANEL)
	_joined_box.add_child(_abilities_panel)
	var ab_box := UiTheme.vbox(4)
	_abilities_panel.add_child(ab_box)
	_ability_row = UiTheme.hbox(10)
	ab_box.add_child(_ability_row)
	mastery_title_label = UiTheme.label("Mastery", UiTheme.GOLD_LABEL, UiTheme.FONT_SMALL + 2)
	ab_box.add_child(mastery_title_label)
	mastery_label = UiTheme.wrapped_label("", &"", UiTheme.FONT_SMALL, Color(0.88, 0.85, 0.78))
	mastery_label.max_lines_visible = MASTERY_MAX_LINES
	mastery_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	ab_box.add_child(mastery_label)

	_joined_box.add_child(UiTheme.spacer(true))
	_prompt_holder = CenterContainer.new()
	_prompt_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_holder.custom_minimum_size = Vector2(0, 40)
	_joined_box.add_child(_prompt_holder)


func _preview_style() -> UiFrameStyle:
	var s := UiTheme.inset_style()
	s.content_margin_left = 2
	s.content_margin_right = 2
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	s.inner_shadow = 18
	return s.rebuild()


func _make_ready_ribbon() -> PanelContainer:
	var ribbon := PanelContainer.new()
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := UiTheme.stone_style(UiTheme.GREEN, Color(0.06, 0.16, 0.05, 0.92))
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.content_margin_left = 18
	style.content_margin_right = 22
	style.glow = Color(0.4, 1.0, 0.3, 0.35)
	style.rebuild()
	ribbon.add_theme_stylebox_override(&"panel", style)
	var row := UiTheme.hbox(10)
	row.add_child(UiIcon.create(UiIcon.Kind.CHECK, Vector2(28, 28)))
	row.add_child(UiTheme.label("READY", UiTheme.HEADING, 30, UiTheme.GREEN))
	ribbon.add_child(row)
	ribbon.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	ribbon.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ribbon.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ribbon.offset_bottom = -6
	ribbon.offset_top = -6
	ribbon.offset_left = 0
	ribbon.offset_right = 0
	ribbon.visible = false
	return ribbon


# --- Updating ------------------------------------------------------------------------

## Mirrors [param p_slot] (null = empty slot). Cheap when nothing changed.
func update_from(p_slot: PlayerSlot, keyboard_free: bool = true) -> void:
	slot = p_slot
	var key := "empty:%s" % keyboard_free
	if p_slot != null:
		var cid: StringName = p_slot.class_data.id if p_slot.class_data != null else &""
		key = "%d:%s:%s:%s" % [p_slot.get_instance_id(), cid, p_slot.ready, p_slot.input.get_device_name()]
	if key == _state_key:
		return
	_state_key = key
	if p_slot == null:
		_keyboard_hint.visible = keyboard_free
		_apply_empty()
		_was_ready = false
	else:
		_apply_joined(p_slot)
		if p_slot.ready and not _was_ready:
			preview.cheer()
		_was_ready = p_slot.ready


## Flashes the ◀ / ▶ arrow after a class change.
func kick_arrow(step: int) -> void:
	if step < 0:
		_arrow_kick.x = 1.0
	else:
		_arrow_kick.y = 1.0


func _apply_empty() -> void:
	_empty_box.visible = true
	_joined_box.visible = false
	preview.visible = false
	add_theme_stylebox_override(&"panel", _card_style(UiTheme.GOLD_DARK, Color(0.075, 0.066, 0.06, 0.9), Color(0, 0, 0, 0)))


func _apply_joined(s: PlayerSlot) -> void:
	_empty_box.visible = false
	_joined_box.visible = true
	preview.visible = true
	var data := s.class_data
	var border := UiTheme.GREEN if s.ready else UiTheme.GOLD_BORDER
	var glow := Color(0.4, 1.0, 0.3, 0.3) if s.ready else Color(0, 0, 0, 0)
	add_theme_stylebox_override(&"panel", _card_style(border, UiTheme.STONE, glow))

	var hs := StyleBoxFlat.new()
	hs.bg_color = s.color.darkened(0.45)
	hs.border_color = s.color
	hs.border_width_bottom = 3
	hs.set_corner_radius_all(4)
	hs.content_margin_left = 12
	hs.content_margin_right = 12
	hs.content_margin_top = 2
	hs.content_margin_bottom = 4
	_header.add_theme_stylebox_override(&"panel", hs)
	_player_label.text = s.label()
	_player_label.add_theme_color_override(&"font_color", s.color.lightened(0.35))
	_device_label.text = s.input.get_device_name()

	_preview_glow.texture = _glow_texture(s.color)
	if data != null:
		preview.show_class(data, s.color)
	_ready_ribbon.visible = s.ready
	_left_arrow.visible = not s.ready
	_right_arrow.visible = not s.ready
	_class_label.text = data.display_name if data != null else "?"
	_role_label.text = data.role if data != null else ""
	_desc_label.text = data.description if data != null else ""
	_fill_stats(data)
	_fill_weapons(data)
	_fill_abilities(data, s)
	if data != null:
		_resource_dot.set_color(data.resource_color)
		_resource_label.text = "Resource: " + UiTheme.resource_name(data.resource_type)
		_resource_label.add_theme_color_override(&"font_color", data.resource_color.lightened(0.35))
		_armor_label.text = String(ClassData.ArmorType.keys()[data.armor_type]).capitalize() + " armor"
	_fill_prompts(s)


func _fill_stats(data: ClassData) -> void:
	for c in _stats_grid.get_children():
		_stats_grid.remove_child(c)
		c.queue_free()
	if data == null:
		return
	for stat: StringName in data.base_stats:
		var v: float = data.base_stats[stat]
		var color := UiTheme.GREEN if v >= 0.0 else UiTheme.RED
		var l := UiTheme.label("%s %s" % [Stats.format_value(stat, v), Stats.display_name(stat)], &"", UiTheme.FONT_SMALL + 1, color)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_stats_grid.add_child(l)


func _fill_weapons(data: ClassData) -> void:
	for c in _weapons_box.get_children():
		_weapons_box.remove_child(c)
		c.queue_free()
	if data == null:
		return
	# One line: "Weapons  Mace + Shield".
	var line := UiTheme.hbox(6)
	var slot_label := UiTheme.label("Weapons", UiTheme.SMALL)
	slot_label.custom_minimum_size.x = 96
	line.add_child(slot_label)
	var first := true
	for w: WeaponData in [data.main_hand, data.off_hand]:
		if w == null:
			continue
		if not first:
			line.add_child(UiTheme.label("+", UiTheme.SMALL))
		first = false
		var rarity := clampi(w.rarity, 0, UiTheme.RARITY_COLORS.size() - 1)
		line.add_child(UiTheme.label(w.display_name, &"", UiTheme.FONT_SMALL + 1, UiTheme.RARITY_COLORS[rarity]))
	_weapons_box.add_child(line)


## The two core abilities (icon with this device's button, name) and the Mastery line.
func _fill_abilities(data: ClassData, s: PlayerSlot) -> void:
	for c in _ability_row.get_children():
		_ability_row.remove_child(c)
		c.queue_free()
	ability_icons.clear()
	ability_name_labels.clear()
	var has_abilities := data != null and not data.abilities.is_empty()
	var has_mastery := data != null and data.mastery_text.strip_edges() != ""
	_abilities_panel.visible = has_abilities or has_mastery
	_ability_row.visible = has_abilities
	mastery_title_label.visible = has_mastery
	mastery_label.visible = has_mastery
	if has_abilities:
		var keyboard := s.input is KeyboardInput
		for i in mini(data.abilities.size(), AbilityRunner.CORE_SLOTS):
			var a := data.abilities[i]
			if a == null:
				continue
			var cell := UiTheme.hbox(8)
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var icon := AbilityIcon.create(ABILITY_ICON_SIZE)
			icon.slot_index = i
			var cost_color := Color(0, 0, 0, 0)
			for r in data.resources:
				if r != null and r.id == a.resource:
					cost_color = r.color
			icon.set_ability(a, a.cost, cost_color)
			icon.set_prompt(AbilityBar.prompt_text(s.input, i), keyboard)
			cell.add_child(icon)
			var name_label := UiTheme.wrapped_label(a.display_name, &"", UiTheme.FONT_SMALL + 2, UiTheme.TEXT)
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			name_label.custom_minimum_size = Vector2(60, ABILITY_ICON_SIZE)
			name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			cell.add_child(name_label)
			_ability_row.add_child(cell)
			ability_icons.append(icon)
			ability_name_labels.append(name_label)
	if has_mastery:
		var parts := mastery_parts(data.mastery_text)
		mastery_title_label.text = "Mastery: %s" % parts[0] if parts[0] != "" else "Mastery"
		mastery_label.text = parts[1]


## Splits a Mastery text "Battle Fury: the lower your health ..." into its name and the rest,
## which starts with a capital letter on its own line ("The lower your health ..."); the name is
## empty when the text has no "Name: " lead-in.
static func mastery_parts(text: String) -> Array[String]:
	var t := text.strip_edges()
	var colon := t.find(": ")
	if colon > 0 and colon <= 28:
		var body := t.substr(colon + 2).strip_edges()
		return [t.substr(0, colon), body.left(1).to_upper() + body.substr(1)]
	return ["", t]


func _fill_prompts(s: PlayerSlot) -> void:
	for c in _prompt_holder.get_children():
		_prompt_holder.remove_child(c)
		c.queue_free()
	var inp := s.input
	var items: Array = []
	if s.ready:
		items = [[UiGlyph.for_input(inp, PlayerInput.Pad.B, 28.0), "Not ready"]]
	else:
		items = [
			[UiGlyph.nav(28.0), "Class"],
			[UiGlyph.for_input(inp, PlayerInput.Pad.A, 28.0), "Ready"],
			[UiGlyph.for_input(inp, PlayerInput.Pad.B, 28.0), "Leave"],
		]
	var row := UiTheme.prompt_row(items, UiTheme.FONT_SMALL + 1)
	row.add_theme_constant_override(&"separation", 16)
	_prompt_holder.add_child(row)


func _card_style(border: Color, fill: Color, glow: Color = Color(0, 0, 0, 0)) -> UiFrameStyle:
	var s := UiTheme.card_style(border, fill)
	s.glow = glow
	s.glow_size = 16
	return s.rebuild()


func _glow_texture(c: Color) -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.78)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 128
	tex.height = 128
	var g := Gradient.new()
	g.set_color(0, Color(c.lightened(0.1), 0.55))
	g.set_color(1, Color(c.darkened(0.6), 0.0))
	tex.gradient = g
	return tex


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	if _empty_box.visible:
		var p := 0.5 + 0.5 * sin(_t * 4.0)
		_join_glyph.set_pulse(p)
		_join_glyph.scale = Vector2.ONE * (1.0 + 0.06 * p)
		_join_glyph.pivot_offset = _join_glyph.size * 0.5
	elif _left_arrow.visible:
		_arrow_kick = _arrow_kick.move_toward(Vector2.ZERO, delta * 4.0)
		var glow := 0.15 + 0.15 * sin(_t * 3.0)
		_left_arrow.pivot_offset = _left_arrow.size * 0.5
		_right_arrow.pivot_offset = _right_arrow.size * 0.5
		_left_arrow.scale = Vector2.ONE * (1.0 + 0.35 * _arrow_kick.x)
		_right_arrow.scale = Vector2.ONE * (1.0 + 0.35 * _arrow_kick.y)
		_left_arrow.modulate = Color(1, 1, 1).lerp(Color(1.5, 1.45, 1.2), maxf(glow, _arrow_kick.x))
		_right_arrow.modulate = Color(1, 1, 1).lerp(Color(1.5, 1.45, 1.2), maxf(glow, _arrow_kick.y))
