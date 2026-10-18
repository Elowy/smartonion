class_name Hud
extends Control
## In-run HUD (GDD 12): compact WoW-style unit frames in the screen corners (P1 top-left,
## P2 top-right, P3 bottom-left, P4 bottom-right), wave counter + timer and the shared gold at
## the top centre, the shared XP bar as a thin full-width strip along the bottom edge (WoW
## style), a translucent level-up / wave banner just below the timer and a notice line for
## controller disconnects. Listens to RunState (wave, gold, xp, level, team loot) by itself.
## Under the gold a "Team Loot: N" bag counter shows the items picked up this wave (they wait
## for the Need / Greed / Pass roll, GDD 10.1); hidden while the team loot is empty.
## M6: on a boss wave a boss frame (name, HP bar, phase pips, "ENRAGED") takes the timer's place
## ([method bind_boss] / [method clear_boss]; it already shows from the wave's start, when the
## wave is a boss wave with a BossData, so the stale clock never shows).

const MARGIN := 22.0
const LOW_TIME := 5.0
const BANNER_IN := 0.22
const BANNER_HOLD := 1.3
const BANNER_OUT := 0.55
## Banner: a slim translucent ribbon anchored just below the wave / timer plaque.
const BANNER_ANCHOR := 0.22
const BANNER_HEIGHT := 100.0
const BANNER_ALPHA := 0.38
const XP_SEGMENTS := 20
## Height of the XP strip along the bottom screen edge (reference px).
const XP_STRIP_HEIGHT := 26.0
## Gold "+N" floater: pickups add up on one floater beside the coin, shown this long after
## the last pickup.
const FLOATER_TIME := 0.6
## Boss frame: width of the HP bar (reference px), its height, and the number of phase pips.
const BOSS_BAR_WIDTH := 440.0
const BOSS_BAR_HEIGHT := 22.0
const BOSS_PHASES := 2
const BOSS_BAR_COLOR := Color(0.84, 0.16, 0.14)
const PIP_SIZE := 14.0
## The ENRAGED line pulses between this alpha and 1 (never dim on the dark plaque); the row is
## always reserved (alpha 0 while calm), so nothing below it jumps when the boss enrages.
const ENRAGED_ALPHA_MIN := 0.8
const ENRAGED_PULSE_SPEED := 8.0

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
## "Team Loot: N" (RunState.team_loot); its row is hidden while N is 0.
var team_loot_label: Label
## M6b: the HARDCORE badge above the wave line (visible in a hardcore run only).
var hardcore_badge: HardcoreBadge

var _banner: Control
var _banner_tween: Tween
var _notice: PanelContainer
var _coin: UiIcon
var _loot_row: HBoxContainer
var _loot_bag: LootBagIcon
var _loot_count := 0
var _loot_pop := 0.0
var _fx_layer: Control
var _gold_target := 0
var _gold_shown := 0.0
var _coin_pop := 0.0
var _timer_second := -1
var _timer_pop := 0.0
var _floater: Label
var _floater_amount := 0
## Seconds since the last pickup added to the floater.
var _floater_age := 0.0
var _clock := 0.0

## The boss frame (replaces the timer on boss waves): its box, name, HP bar, phase pips and the
## "ENRAGED" line, and the boss it shows.
var boss_frame: VBoxContainer
var boss_name_label: Label
var boss_bar: UiBar
var boss_enraged_label: Label
var _boss_pips: Array[Panel] = []
var _boss: Boss


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


## Shows the frame of [param boss] (WaveDirector.boss_spawned): its name, HP, phase and enrage
## follow the boss every frame until [method clear_boss].
func bind_boss(boss: Boss) -> void:
	_boss = boss
	var title := boss.boss_data.display_name if boss != null and boss.boss_data != null else \
			(boss.data.display_name if boss != null and boss.data != null else "")
	_show_boss_frame(title)
	_update_boss_frame()


## Hides the boss frame and brings the timer back (the wave ended).
func clear_boss(_wave: int = 0) -> void:
	_boss = null
	if boss_frame != null:
		boss_frame.visible = false
	timer_label.visible = true


## True while the boss frame replaces the timer.
func is_boss_frame_visible() -> bool:
	return boss_frame != null and boss_frame.visible


## The boss frame's "ENRAGED" line is showing (its row is always reserved, see
## [constant ENRAGED_ALPHA_MIN]: shown means not transparent).
func is_boss_enraged_shown() -> bool:
	return boss_enraged_label != null and boss_enraged_label.visible and boss_enraged_label.modulate.a > 0.01


## The phase pip (0-based) lit up last: the boss's current phase (1-based) as shown.
func boss_phase_shown() -> int:
	var n := 0
	for pip in _boss_pips:
		if pip.has_meta(&"lit"):
			n += 1
	return n


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
		# Bottom frames sit just above the XP strip.
		f.offset_top = -(XP_STRIP_HEIGHT + 10.0) if bottom else MARGIN - 6.0
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
	_build_floater()


func _build_top() -> void:
	var plaque := UiTheme.panel()
	var style := UiTheme.stone_style()
	style.content_margin_top = 4
	style.content_margin_bottom = 6
	style.content_margin_left = 26
	style.content_margin_right = 26
	style.fill = Color(0.1, 0.085, 0.075, UnitFrame.PANEL_ALPHA)
	style.shadow_color = Color(0, 0, 0, 0.4)
	plaque.add_theme_stylebox_override(&"panel", style.rebuild())
	plaque.custom_minimum_size = Vector2(220, 0)
	plaque.anchor_left = 0.5
	plaque.anchor_right = 0.5
	plaque.grow_horizontal = Control.GROW_DIRECTION_BOTH
	plaque.offset_top = MARGIN - 8
	add_child(plaque)
	# Compact (it sits over the far / top part of the playfield): tight line spacing.
	var col := UiTheme.vbox(-6)
	plaque.add_child(col)
	_build_mode_badge(col)
	wave_label = UiTheme.centered_label(RunState.wave_progress_text(1), UiTheme.GOLD_LABEL, 22)
	col.add_child(wave_label)
	wave_tag_label = UiTheme.centered_label("", UiTheme.HEADING, 18, UiTheme.RED)
	wave_tag_label.visible = false
	col.add_child(wave_tag_label)
	timer_label = UiTheme.centered_label("20", UiTheme.BIG_NUMBER, 52)
	col.add_child(timer_label)
	_build_boss_frame(col)
	col.add_child(UiTheme.divider(160))
	var gold_row := UiTheme.hbox(8)
	gold_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_coin = UiIcon.create(UiIcon.Kind.COIN, Vector2(24, 24))
	_coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gold_row.add_child(_coin)
	gold_label = UiTheme.label("0", UiTheme.GOLD_LABEL, 26)
	gold_row.add_child(gold_label)
	col.add_child(gold_row)
	# Team loot bag counter (GDD 10.1: picked-up item bags fly into it).
	_loot_row = UiTheme.hbox(6)
	_loot_row.name = "TeamLoot"
	_loot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_loot_bag = LootBagIcon.new()
	_loot_bag.custom_minimum_size = Vector2(22, 22)
	_loot_bag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loot_bag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_loot_row.add_child(_loot_bag)
	team_loot_label = UiTheme.label("Team Loot: 0", UiTheme.GOLD_LABEL, 19, Color(0.86, 0.78, 1.0))
	_loot_row.add_child(team_loot_label)
	_loot_row.visible = false
	col.add_child(_loot_row)


## The HARDCORE badge (M6b MODES) on the first row of the plaque (call it first, right after the column is
## made): shown in a hardcore run only (the HUD is built for a run after RunState.start_run, so the flag is
## known), hidden otherwise – it takes no room then.
func _build_mode_badge(col: VBoxContainer) -> void:
	hardcore_badge = HardcoreBadge.create(UiTheme.FONT_SMALL - 2)
	hardcore_badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hardcore_badge.visible = RunState.hardcore
	col.add_child(hardcore_badge)


## The boss frame (hidden until a boss wave): name, HP bar, phase pips and the ENRAGED line.
func _build_boss_frame(col: VBoxContainer) -> void:
	boss_frame = UiTheme.vbox(2)
	boss_frame.name = "BossFrame"
	boss_frame.custom_minimum_size = Vector2(BOSS_BAR_WIDTH, 0.0)
	boss_frame.visible = false
	boss_name_label = UiTheme.centered_label("", UiTheme.HEADING, 26, UiTheme.RED.lightened(0.15))
	boss_frame.add_child(boss_name_label)
	boss_bar = UiBar.create(BOSS_BAR_COLOR, BOSS_BAR_HEIGHT, UiTheme.FONT_SMALL)
	boss_bar.set_values(1.0, 1.0, "100%")
	boss_frame.add_child(boss_bar)
	var row := UiTheme.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in BOSS_PHASES:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(PIP_SIZE, PIP_SIZE)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pip)
		_boss_pips.append(pip)
		_light_pip(pip, i == 0)
	boss_frame.add_child(row)
	boss_enraged_label = UiTheme.centered_label("ENRAGED", UiTheme.HEADING, 22, UiTheme.RED.lightened(0.3))
	# Takes its row up front (transparent while calm) so the plaque never grows mid-fight.
	boss_enraged_label.modulate.a = 0.0
	boss_frame.add_child(boss_enraged_label)
	# Sits where the timer sits (the timer hides while the frame shows).
	col.add_child(boss_frame)
	col.move_child(boss_frame, timer_label.get_index() + 1)


## A round pip: lit (bright gold ring) or dim.
func _light_pip(pip: Panel, lit: bool) -> void:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(int(PIP_SIZE * 0.5))
	style.bg_color = UiTheme.GOLD if lit else Color(0.16, 0.13, 0.11)
	style.border_color = UiTheme.GOLD_BORDER if lit else Color(0.35, 0.3, 0.25)
	style.set_border_width_all(2)
	pip.add_theme_stylebox_override(&"panel", style)
	if lit:
		pip.set_meta(&"lit", true)
	elif pip.has_meta(&"lit"):
		pip.remove_meta(&"lit")


## Frame on, timer off.
func _show_boss_frame(title: String) -> void:
	boss_name_label.text = title
	boss_frame.visible = true
	timer_label.visible = false
	boss_enraged_label.modulate.a = 0.0


## Follows the bound boss: HP bar (percent), phase pips, ENRAGED (pulsing).
func _update_boss_frame() -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	var ratio := _boss.hp_ratio()
	boss_bar.set_values(ratio * 1000.0, 1000.0, "%d%%" % int(ceilf(ratio * 100.0 - 0.001)))
	for i in _boss_pips.size():
		var lit := i < _boss.phase
		if lit != _boss_pips[i].has_meta(&"lit"):
			_light_pip(_boss_pips[i], lit)
	if _boss.is_boss_enraged():
		var pulse := 0.5 + 0.5 * sin(_clock * ENRAGED_PULSE_SPEED)
		boss_enraged_label.modulate.a = lerpf(ENRAGED_ALPHA_MIN, 1.0, pulse)
	else:
		boss_enraged_label.modulate.a = 0.0


## WoW-style XP bar: a thin segmented strip across the whole bottom edge, the team level at
## its left end and "xp / needed XP" at its right end.
func _build_xp() -> void:
	var strip := Control.new()
	strip.name = "XpStrip"
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.anchor_left = 0.0
	strip.anchor_right = 1.0
	strip.anchor_top = 1.0
	strip.anchor_bottom = 1.0
	strip.offset_top = -XP_STRIP_HEIGHT
	strip.offset_bottom = 0.0
	add_child(strip)
	# Gold hairline on top of the strip, like the WoW action bar edge.
	var edge := ColorRect.new()
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge.color = Color(UiTheme.GOLD_DARK, 0.95)
	edge.anchor_right = 1.0
	edge.offset_top = -2.0
	edge.offset_bottom = 0.0
	strip.add_child(edge)
	xp_bar = UiBar.create(UiTheme.XP_PURPLE, XP_STRIP_HEIGHT, UiTheme.FONT_SMALL)
	xp_bar.segments = XP_SEGMENTS
	xp_bar.set_values(0.0, 1.0)
	xp_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	strip.add_child(xp_bar)
	var row := UiTheme.hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 14.0
	row.offset_right = -14.0
	strip.add_child(row)
	level_label = UiTheme.label("Level %d" % RunState.START_LEVEL, UiTheme.GOLD_LABEL, UiTheme.FONT_SMALL)
	level_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(level_label)
	row.add_child(UiTheme.spacer())
	xp_label = UiTheme.label("0 / 16 XP", UiTheme.SMALL, UiTheme.FONT_SMALL, Color(0.88, 0.8, 1.0))
	xp_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	xp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(xp_label)


func _build_banner() -> void:
	_banner = Control.new()
	_banner.name = "Banner"
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.anchor_left = 0.0
	_banner.anchor_right = 1.0
	_banner.anchor_top = BANNER_ANCHOR
	_banner.anchor_bottom = BANNER_ANCHOR
	_banner.offset_top = 0.0
	_banner.offset_bottom = BANNER_HEIGHT
	add_child(_banner)
	var ribbon := TextureRect.new()
	ribbon.texture = _ribbon_texture(Color(0, 0, 0, BANNER_ALPHA))
	ribbon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ribbon.stretch_mode = TextureRect.STRETCH_SCALE
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ribbon.anchor_left = 0.18
	ribbon.anchor_right = 0.82
	ribbon.anchor_bottom = 1.0
	_banner.add_child(ribbon)
	for y in [0.0, 1.0]:
		var line := TextureRect.new()
		line.texture = _ribbon_texture(Color(UiTheme.GOLD_BORDER, 0.7))
		line.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		line.stretch_mode = TextureRect.STRETCH_SCALE
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.anchor_left = 0.22
		line.anchor_right = 0.78
		line.anchor_top = y
		line.anchor_bottom = y
		line.offset_top = -1.0
		line.offset_bottom = 1.0
		_banner.add_child(line)
	banner_label = UiTheme.centered_label("", UiTheme.TITLE, 64)
	banner_label.add_theme_constant_override(&"outline_size", 14)
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
	_notice.offset_top = -(XP_STRIP_HEIGHT + 40.0)
	_notice.offset_bottom = _notice.offset_top
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
	hardcore_badge.visible = RunState.hardcore
	RunState.wave_changed.connect(_on_wave_changed)
	RunState.gold_changed.connect(_on_gold_changed)
	RunState.xp_changed.connect(_on_xp_changed)
	RunState.leveled_up.connect(_on_leveled_up)
	RunState.team_loot_changed.connect(_on_team_loot_changed)
	_on_wave_changed(RunState.wave)
	_loot_count = RunState.team_loot.size()
	_show_team_loot()
	_gold_target = RunState.gold
	_gold_shown = float(RunState.gold)
	gold_label.text = UiTheme.format_int(RunState.gold)
	_on_xp_changed(RunState.xp, RunState.xp_to_next_level())


func _on_wave_changed(w: int) -> void:
	wave_label.text = RunState.wave_progress_text(maxi(w, 1))
	_boss = null
	var boss_data := BossData.for_wave(w) if RunState.is_boss_wave(w) else null
	if boss_data != null:
		# A boss wave has no clock: the frame shows from the start (full bar) until the boss comes.
		_show_boss_frame(boss_data.display_name)
		boss_bar.set_values(1.0, 1.0, "100%")
		for i in _boss_pips.size():
			_light_pip(_boss_pips[i], i == 0)
	else:
		boss_frame.visible = false
		timer_label.visible = true
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


func _on_team_loot_changed() -> void:
	var n := RunState.team_loot.size()
	if n > _loot_count:
		_loot_pop = 1.0
	_loot_count = n
	_show_team_loot()


func _show_team_loot() -> void:
	team_loot_label.text = "Team Loot: %d" % _loot_count
	_loot_row.visible = _loot_count > 0


func is_team_loot_visible() -> bool:
	return _loot_row.visible


func _build_floater() -> void:
	_floater = UiTheme.label("", UiTheme.GOLD_LABEL, 24, UiTheme.GOLD_BRIGHT)
	_floater.name = "GoldFloater"
	_floater.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_floater.visible = false
	_fx_layer.add_child(_floater)


## "+12" (or "-30") beside the gold counter. Every pickup while it shows adds up on the same
## floater (it pops and stays FLOATER_TIME after the last one) – never a stack of labels.
func _spawn_gold_floater(delta: int) -> void:
	if _floater.visible and _floater_age < FLOATER_TIME and signi(_floater_amount) == signi(delta):
		_floater_amount += delta
	else:
		_floater_amount = delta
	_floater_age = 0.0
	_floater.text = _floater_text(_floater_amount)
	_floater.add_theme_color_override(&"font_color", UiTheme.GOLD_BRIGHT if _floater_amount > 0 else UiTheme.RED)
	_floater.visible = true
	_floater.modulate.a = 1.0
	_place_floater()


## Keeps the floater right of the coin row (the amount label grows / the plaque moves).
func _place_floater() -> void:
	var origin := gold_label.get_global_rect().position - _fx_layer.get_global_rect().position
	var rise := 6.0 * clampf(_floater_age / FLOATER_TIME, 0.0, 1.0)
	_floater.position = origin + Vector2(gold_label.size.x + 10.0, (gold_label.size.y - _floater.size.y) * 0.5 - rise)
	var pop := 1.0 + 0.25 * maxf(0.0, 1.0 - _floater_age / 0.12)
	_floater.pivot_offset = Vector2(0.0, _floater.size.y * 0.5)
	_floater.scale = Vector2.ONE * pop


func is_gold_floater_visible() -> bool:
	return _floater.visible


static func _floater_text(amount: int) -> String:
	return ("+%s" if amount > 0 else "-%s") % UiTheme.format_int(absi(amount))


func _process(delta: float) -> void:
	_clock += delta
	if _boss != null:
		_update_boss_frame()
	if _floater.visible:
		_floater_age += delta
		if _floater_age >= FLOATER_TIME:
			_floater.visible = false
		else:
			_floater.modulate.a = 1.0 - smoothstep(FLOATER_TIME * 0.6, FLOATER_TIME, _floater_age)
			_place_floater()
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
	if _loot_pop > 0.0:
		_loot_pop = maxf(0.0, _loot_pop - delta * 3.0)
		_loot_bag.pivot_offset = _loot_bag.size * 0.5
		_loot_bag.scale = Vector2.ONE * (1.0 + 0.45 * _loot_pop)
		_loot_bag.glow = _loot_pop
		_loot_bag.queue_redraw()
	timer_label.pivot_offset = timer_label.size * 0.5
	timer_label.scale = Vector2.ONE * (1.0 + 0.22 * _timer_pop)


## Small loot sack drawn in code (the "Team Loot" counter); [member glow] flashes it when an
## item bag was picked up.
class LootBagIcon extends Control:
	var glow := 0.0

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var c := size * 0.5
		var line := Color(0.07, 0.04, 0.02)
		if glow > 0.0:
			draw_circle(c, s * 0.7, Color(0.75, 0.55, 1.0, 0.35 * glow))
		var body := PackedVector2Array()
		for i in 20:
			var a := TAU * i / 20.0
			body.append(c + Vector2(cos(a) * s * 0.42, s * 0.12 + sin(a) * s * 0.34))
		draw_colored_polygon(body, Color(0.58, 0.4, 0.22))
		var outline := body.duplicate()
		outline.append(body[0])
		draw_polyline(outline, line, 1.5, true)
		var neck := PackedVector2Array([c + Vector2(-s * 0.16, -s * 0.2), c + Vector2(s * 0.16, -s * 0.2),
			c + Vector2(s * 0.26, -s * 0.44), c + Vector2(-s * 0.26, -s * 0.44)])
		draw_colored_polygon(neck, Color(0.66, 0.47, 0.27))
		draw_line(c + Vector2(-s * 0.2, -s * 0.2), c + Vector2(s * 0.2, -s * 0.2), UiTheme.GOLD, 2.0)
		draw_circle(c + Vector2(0, s * 0.12), s * 0.1, Color(0.75, 0.55, 1.0))
