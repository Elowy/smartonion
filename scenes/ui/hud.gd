class_name Hud
extends Control
## In-run HUD (GDD 12): WoW-style unit frames in the screen corners (P1 top-left, P2 top-right,
## P3 bottom-left, P4 bottom-right), wave counter + timer and the shared gold at the top
## centre, the shared XP bar at the bottom, a level-up / wave banner and a notice line for
## controller disconnects. Listens to RunState (wave, gold, xp, level) by itself.

const MARGIN := 22.0
const LOW_TIME := 5.0
const BANNER_IN := 0.22
const BANNER_HOLD := 1.3
const BANNER_OUT := 0.55
const XP_SEGMENTS := 20

var frames: Array[UnitFrame] = []
var wave_label: Label
var wave_tag_label: Label
var timer_label: Label
var gold_label: Label
var level_label: Label
var xp_label: Label
var xp_bar: UiBar
var banner_label: Label
var notice_label: Label

var _banner: Control
var _banner_tween: Tween
var _notice: PanelContainer
var _coin: UiIcon
var _fx_layer: Control
var _gold_target := 0
var _gold_shown := 0.0
var _coin_pop := 0.0
var _timer_second := -1
var _timer_pop := 0.0
var _floater: Label
var _floater_amount := 0
var _floater_born := 0.0
var _clock := 0.0


static func create() -> Hud:
	var h := Hud.new()
	h.name = "Hud"
	h._build()
	return h


# --- Contract ------------------------------------------------------------------------

## Connects the unit frames to the spawned players.
func bind_players(players: Array[Player]) -> void:
	for f in frames:
		f.unbind()
	for i in players.size():
		var p := players[i]
		if not is_instance_valid(p):
			continue
		var idx := p.slot.index if p.slot != null else i
		if idx >= 0 and idx < frames.size():
			frames[idx].bind(p)


func set_wave_time(seconds_left: float) -> void:
	timer_label.text = UiTheme.format_time(seconds_left)
	var low := seconds_left <= LOW_TIME
	timer_label.add_theme_color_override(&"font_color", UiTheme.RED if low else UiTheme.TEXT)
	var whole := int(ceilf(maxf(seconds_left, 0.0) - 0.001))
	if low and whole != _timer_second and whole > 0:
		_timer_pop = 1.0
	_timer_second = whole


## Big centred banner ("Wave 3", "Wave cleared!", "LEVEL UP!").
func show_banner(text: String, color: Color = UiTheme.GOLD) -> void:
	banner_label.text = text
	banner_label.add_theme_color_override(&"font_color", color)
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner.visible = true
	_banner.modulate.a = 0.0
	banner_label.pivot_offset = banner_label.size * 0.5
	banner_label.scale = Vector2.ONE * 1.35
	if not is_inside_tree():
		_banner.modulate.a = 1.0
		banner_label.scale = Vector2.ONE
		return
	_banner_tween = create_tween()
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, BANNER_IN)
	_banner_tween.tween_property(banner_label, "scale", Vector2.ONE, BANNER_IN + 0.08) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.chain().tween_interval(BANNER_HOLD)
	_banner_tween.chain().tween_property(_banner, "modulate:a", 0.0, BANNER_OUT)
	_banner_tween.chain().tween_callback(_banner.hide)


func is_banner_visible() -> bool:
	return _banner.visible


## e.g. "Controller disconnected – P2: reconnect or press A on another controller".
func show_notice(text: String) -> void:
	notice_label.text = text
	_notice.visible = true


func hide_notice() -> void:
	_notice.visible = false


func is_notice_visible() -> bool:
	return _notice.visible


# --- Build ---------------------------------------------------------------------------

func _build() -> void:
	UiTheme.setup_root(self)
	for i in PlayerManager.MAX_PLAYERS:
		var right := i % 2 == 1
		var bottom := i >= 2
		var f := UnitFrame.create(i, right)
		f.anchor_left = 1.0 if right else 0.0
		f.anchor_right = f.anchor_left
		f.anchor_top = 1.0 if bottom else 0.0
		f.anchor_bottom = f.anchor_top
		f.grow_horizontal = Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END
		f.grow_vertical = Control.GROW_DIRECTION_BEGIN if bottom else Control.GROW_DIRECTION_END
		f.offset_left = -MARGIN if right else MARGIN
		f.offset_right = f.offset_left
		f.offset_top = -MARGIN if bottom else MARGIN
		f.offset_bottom = f.offset_top
		add_child(f)
		frames.append(f)
	_build_top()
	_build_xp()
	_build_banner()
	_build_notice()
	_fx_layer = Control.new()
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fx_layer)


func _build_top() -> void:
	var plaque := UiTheme.panel()
	var style := UiTheme.stone_style()
	style.content_margin_top = 8
	style.content_margin_bottom = 10
	style.content_margin_left = 30
	style.content_margin_right = 30
	style.fill = Color(0.1, 0.085, 0.075, 0.9)
	plaque.add_theme_stylebox_override(&"panel", style.rebuild())
	plaque.custom_minimum_size = Vector2(250, 0)
	plaque.anchor_left = 0.5
	plaque.anchor_right = 0.5
	plaque.grow_horizontal = Control.GROW_DIRECTION_BOTH
	plaque.offset_top = MARGIN - 6
	add_child(plaque)
	var col := UiTheme.vbox(0)
	plaque.add_child(col)
	wave_label = UiTheme.centered_label("Wave 1 / %d" % RunState.TOTAL_WAVES, UiTheme.GOLD_LABEL, 24)
	col.add_child(wave_label)
	wave_tag_label = UiTheme.centered_label("", UiTheme.HEADING, 18, UiTheme.RED)
	wave_tag_label.visible = false
	col.add_child(wave_tag_label)
	timer_label = UiTheme.centered_label("20", UiTheme.BIG_NUMBER, 62)
	col.add_child(timer_label)
	col.add_child(UiTheme.divider(180))
	var gold_row := UiTheme.hbox(8)
	gold_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_coin = UiIcon.create(UiIcon.Kind.COIN, Vector2(28, 28))
	gold_row.add_child(_coin)
	gold_label = UiTheme.label("0", UiTheme.GOLD_LABEL, 30)
	gold_row.add_child(gold_label)
	col.add_child(gold_row)


func _build_xp() -> void:
	var holder := UiTheme.panel()
	var style := UiTheme.stone_style()
	style.content_margin_top = 6
	style.content_margin_bottom = 9
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.fill = Color(0.1, 0.085, 0.075, 0.88)
	holder.add_theme_stylebox_override(&"panel", style.rebuild())
	holder.anchor_left = 0.5
	holder.anchor_right = 0.5
	holder.anchor_top = 1.0
	holder.anchor_bottom = 1.0
	holder.grow_horizontal = Control.GROW_DIRECTION_BOTH
	holder.grow_vertical = Control.GROW_DIRECTION_BEGIN
	holder.offset_left = -430
	holder.offset_right = 430
	holder.offset_top = -MARGIN
	holder.offset_bottom = -MARGIN
	add_child(holder)
	var col := UiTheme.vbox(3)
	holder.add_child(col)
	var row := UiTheme.hbox(8)
	level_label = UiTheme.label("Level 0", UiTheme.GOLD_LABEL, 22)
	row.add_child(level_label)
	row.add_child(UiTheme.spacer())
	xp_label = UiTheme.label("0 / 16 XP", UiTheme.SMALL, 18, Color(0.85, 0.75, 1.0))
	row.add_child(xp_label)
	col.add_child(row)
	xp_bar = UiBar.create(UiTheme.XP_PURPLE, 18.0, 13)
	xp_bar.segments = XP_SEGMENTS
	xp_bar.set_values(0.0, 1.0)
	col.add_child(xp_bar)


func _build_banner() -> void:
	_banner = Control.new()
	_banner.name = "Banner"
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.anchor_left = 0.0
	_banner.anchor_right = 1.0
	_banner.anchor_top = 0.3
	_banner.anchor_bottom = 0.3
	_banner.offset_top = -80
	_banner.offset_bottom = 80
	add_child(_banner)
	var ribbon := TextureRect.new()
	ribbon.texture = _ribbon_texture(Color(0, 0, 0, 0.62))
	ribbon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ribbon.stretch_mode = TextureRect.STRETCH_SCALE
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ribbon.anchor_left = 0.18
	ribbon.anchor_right = 0.82
	ribbon.anchor_bottom = 1.0
	_banner.add_child(ribbon)
	for y in [0.0, 1.0]:
		var line := TextureRect.new()
		line.texture = _ribbon_texture(Color(UiTheme.GOLD_BORDER, 0.95))
		line.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		line.stretch_mode = TextureRect.STRETCH_SCALE
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.anchor_left = 0.22
		line.anchor_right = 0.78
		line.anchor_top = y
		line.anchor_bottom = y
		line.offset_top = -1.5
		line.offset_bottom = 1.5
		_banner.add_child(line)
	banner_label = UiTheme.centered_label("", UiTheme.TITLE, 96)
	banner_label.add_theme_constant_override(&"outline_size", 18)
	banner_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_banner.add_child(banner_label)
	_banner.visible = false


func _ribbon_texture(c: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(c, 0.0))
	g.set_color(1, Color(c, 0.0))
	g.add_point(0.25, c)
	g.add_point(0.75, c)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 256
	tex.height = 4
	return tex


func _build_notice() -> void:
	_notice = UiTheme.panel()
	var style := UiTheme.stone_style(UiTheme.RED.darkened(0.15), Color(0.16, 0.06, 0.05, 0.94))
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_notice.add_theme_stylebox_override(&"panel", style.rebuild())
	_notice.anchor_left = 0.5
	_notice.anchor_right = 0.5
	_notice.anchor_top = 1.0
	_notice.anchor_bottom = 1.0
	_notice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_notice.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_notice.offset_top = -118
	_notice.offset_bottom = -118
	add_child(_notice)
	var row := UiTheme.hbox(12)
	_notice.add_child(row)
	row.add_child(UiIcon.create(UiIcon.Kind.WARNING, Vector2(34, 34)))
	notice_label = UiTheme.label("", &"", UiTheme.FONT_LARGE - 2)
	notice_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(notice_label)
	_notice.visible = false


# --- RunState ----------------------------------------------------------------------

func _ready() -> void:
	RunState.wave_changed.connect(_on_wave_changed)
	RunState.gold_changed.connect(_on_gold_changed)
	RunState.xp_changed.connect(_on_xp_changed)
	RunState.leveled_up.connect(_on_leveled_up)
	_on_wave_changed(RunState.wave)
	_gold_target = RunState.gold
	_gold_shown = float(RunState.gold)
	gold_label.text = UiTheme.format_int(RunState.gold)
	_on_xp_changed(RunState.xp, RunState.xp_to_next_level())


func _on_wave_changed(w: int) -> void:
	wave_label.text = "Wave %d / %d" % [maxi(w, 1), RunState.TOTAL_WAVES]
	if RunState.is_boss_wave(w):
		wave_tag_label.text = "BOSS WAVE"
		wave_tag_label.add_theme_color_override(&"font_color", UiTheme.RED)
		wave_tag_label.visible = true
	elif RunState.is_elite_wave(w):
		wave_tag_label.text = "ELITE WAVE"
		wave_tag_label.add_theme_color_override(&"font_color", UiTheme.RARITY_COLORS[3].lightened(0.25))
		wave_tag_label.visible = true
	else:
		wave_tag_label.visible = false


func _on_gold_changed(gold: int, delta: int) -> void:
	_gold_target = gold
	if delta == 0 or not is_inside_tree():
		_gold_shown = float(gold)
		gold_label.text = UiTheme.format_int(gold)
		return
	_coin_pop = 1.0
	_spawn_gold_floater(delta)


func _on_xp_changed(xp: int, needed: int) -> void:
	xp_bar.set_values(float(xp), float(maxi(needed, 1)))
	xp_label.text = "%s / %s XP" % [UiTheme.format_int(xp), UiTheme.format_int(needed)]
	level_label.text = "Level %d" % RunState.level


func _on_leveled_up(level: int) -> void:
	level_label.text = "Level %d" % level
	xp_bar.flash = 1.0
	show_banner("LEVEL UP!", UiTheme.GOLD)


## "+12" (or "-30") rising from the gold counter. Pickups arriving in quick succession
## add up on one floater instead of stacking.
func _spawn_gold_floater(delta: int) -> void:
	if is_instance_valid(_floater) and _clock - _floater_born < 0.35 and signi(_floater_amount) == signi(delta):
		_floater_amount += delta
		_floater.text = _floater_text(_floater_amount)
		return
	_floater_amount = delta
	_floater_born = _clock
	var l := UiTheme.label(_floater_text(delta), UiTheme.GOLD_LABEL, 26, UiTheme.GOLD_BRIGHT if delta > 0 else UiTheme.RED)
	_floater = l
	_fx_layer.add_child(l)
	var origin := gold_label.get_global_rect().position - _fx_layer.get_global_rect().position
	l.position = origin + Vector2(gold_label.size.x + 10.0, -4.0)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 34.0, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.35)
	tw.chain().tween_callback(l.queue_free)


static func _floater_text(amount: int) -> String:
	return ("+%s" if amount > 0 else "-%s") % UiTheme.format_int(absi(amount))


func _process(delta: float) -> void:
	_clock += delta
	if not is_equal_approx(_gold_shown, float(_gold_target)):
		var step := maxf(absf(float(_gold_target) - _gold_shown) * minf(1.0, delta * 10.0), delta * 30.0)
		_gold_shown = move_toward(_gold_shown, float(_gold_target), step)
		gold_label.text = UiTheme.format_int(roundi(_gold_shown))
	if _coin_pop > 0.0:
		_coin_pop = maxf(0.0, _coin_pop - delta * 4.0)
		_coin.pivot_offset = _coin.size * 0.5
		_coin.scale = Vector2.ONE * (1.0 + 0.3 * _coin_pop)
	if _timer_pop > 0.0:
		_timer_pop = maxf(0.0, _timer_pop - delta * 3.0)
	timer_label.pivot_offset = timer_label.size * 0.5
	timer_label.scale = Vector2.ONE * (1.0 + 0.22 * _timer_pop)
