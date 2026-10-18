class_name EnvironmentRollScreen
extends Control
## "Rolling the arena..." (GDD 12 / 16.1, M6b ENV): shown after the lobby's countdown, before the run.
## A horizontal reel of environment cards (the five of [member Db.environment_ids], repeated) runs past
## a gold marker and decelerates over [constant SPIN_TIME] seconds (ease-out, like opening a skin
## crate), stops with the rolled card under the marker, holds there for [constant HOLD_TIME] second and
## then emits [signal finished] – Main starts the run. Any joined player's A / START skips the spin
## (the reel jumps to the result and the hold starts); the screen never decides anything itself: the
## winner is given to [method create] (RunState.environment_for_seed of the run seed, or --env).
##
## Skipped in smoke / demo / forced-view runs and in tests ([member enabled] is switched off by
## tests/run_tests.gd, a test that exercises the screen switches it on). The look is placeholder art:
## each card paints a small scene for its decor set; the final art is M7's.

signal finished(environment_id: StringName)

enum Phase { SPIN, HOLD, DONE }

## Seconds the reel takes to come to rest, and how long the result stays up before the run starts.
const SPIN_TIME := 3.5
const HOLD_TIME := 1.0
## Skip presses are ignored for this long (the press that readied the lobby must not skip it).
const SKIP_GRACE := 0.6
const CARD_SIZE := Vector2(340.0, 500.0)
const CARD_GAP := 26.0
## The reel holds this many copies of the environment list; the result stops in the second but last.
const CYCLES := 7
## Ease-out exponent of the spin (the speed falls to 0 at the end; higher = a longer crawl).
const EASE_POWER := 3.4

## Whether Main shows the screen after the lobby (false in tests unless a test needs it).
static var enabled := true

var winner: StringName
var ids: Array[StringName] = []
var phase := Phase.SPIN
## Seconds since the screen opened (the spin runs from 0 to SPIN_TIME, the hold after it).
var age := 0.0
var cards: Array[Control] = []
var title_label: Label
var result_label: Label
var hint: Control
var reel: Control

var _winner_index := 0
var _target_index := 0
var _hold_left := HOLD_TIME
var _emitted := false
var _backdrop: TextureRect
var _clip: Control


## The screen for [param p_ids] (the environments on the reel, in order; Db.environment_ids when empty)
## landing on [param p_winner] (an id of the list).
static func create(p_winner: StringName, p_ids: Array[StringName] = []) -> EnvironmentRollScreen:
	var s := EnvironmentRollScreen.new()
	s.name = "EnvironmentRollScreen"
	s.ids = p_ids.duplicate() if not p_ids.is_empty() else Db.environment_ids.duplicate()
	s.winner = p_winner
	s._build()
	return s


## Index of the environment on the reel that stops under the marker.
func target_index() -> int:
	return _target_index


## Distance (px) between two neighbouring cards' left edges.
static func card_step() -> float:
	return CARD_SIZE.x + CARD_GAP


## The reel's progress 0..1 along its path at [param seconds] into the spin (ease-out: 1 at SPIN_TIME).
static func progress_at(seconds: float) -> float:
	var u := clampf(seconds / SPIN_TIME, 0.0, 1.0)
	return 1.0 - pow(1.0 - u, EASE_POWER)


## The id of the card under the marker right now (the middle of the screen).
func card_under_marker() -> StringName:
	var best := 0
	var best_d := INF
	for i in cards.size():
		var d := absf(_card_center_x(i) - size.x * 0.5)
		if d < best_d:
			best_d = d
			best = i
	return ids[best % ids.size()] if not ids.is_empty() else &""


func is_spinning() -> bool:
	return phase == Phase.SPIN


## Jumps from the spin to the result (the hold starts).
func skip() -> void:
	if phase != Phase.SPIN:
		return
	age = SPIN_TIME
	_enter_hold()


# --- Build ---------------------------------------------------------------------------------------------

func _build() -> void:
	UiTheme.setup_root(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var solid := ColorRect.new()  # (the lobby must not show through the backdrop's vignette)
	solid.name = "Solid"
	solid.color = UiTheme.BACKDROP
	solid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	solid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(solid)
	_backdrop = UiTheme.backdrop(1.0, Color(0.3, 0.2, 0.12))
	add_child(_backdrop)
	var n := maxi(1, ids.size())
	_winner_index = maxi(0, ids.find(winner))
	_target_index = (CYCLES - 2) * n + _winner_index

	title_label = UiTheme.centered_label("Rolling the arena…", UiTheme.TITLE, 64)
	title_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title_label.offset_top = 40
	title_label.offset_bottom = 130
	add_child(title_label)

	_clip = Control.new()
	_clip.name = "ReelWindow"
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_clip.offset_top = 150
	_clip.offset_bottom = -150
	add_child(_clip)
	reel = Control.new()
	reel.name = "Reel"
	reel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(reel)
	for i in CYCLES * n:
		var card := _EnvCard.create(Db.get_environment(ids[i % n]))
		card.position = Vector2(float(i) * card_step(), 20.0)
		reel.add_child(card)
		cards.append(card)
	_update_reel()

	# The marker: a gold frame round the middle card and two arrows.
	var marker := _Marker.new()
	marker.name = "Marker"
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	marker.offset_top = 150
	marker.offset_bottom = -150
	add_child(marker)

	result_label = UiTheme.centered_label("", UiTheme.GOLD_LABEL, 34)
	result_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	result_label.offset_top = -140
	result_label.offset_bottom = -80
	add_child(result_label)
	hint = UiTheme.prompt_row([[UiGlyph.pad(PlayerInput.Pad.A), "/", UiGlyph.key("Enter"), "Skip"]],
			UiTheme.FONT_BODY, UiTheme.TEXT_DIM)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.offset_top = -70
	hint.offset_bottom = -30
	hint.offset_left = -300
	hint.offset_right = 300
	add_child(hint)


# --- Frame ---------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	step(delta)
	if phase == Phase.SPIN and age >= SKIP_GRACE and _skip_pressed():
		skip()


## Advances the animation by [param delta] seconds (tests drive it directly).
func step(delta: float) -> void:
	match phase:
		Phase.SPIN:
			age += delta
			if age >= SPIN_TIME:
				age = SPIN_TIME
				_enter_hold()
		Phase.HOLD:
			_hold_left -= delta
			if _hold_left <= 0.0:
				phase = Phase.DONE
				if not _emitted:
					_emitted = true
					finished.emit(winner)
	_update_reel()


func _enter_hold() -> void:
	phase = Phase.HOLD
	_hold_left = HOLD_TIME
	var env := Db.get_environment(winner)
	title_label.text = "The arena: %s" % (env.display_name if env != null else String(winner))
	if env != null:
		result_label.text = "%s – %s" % [env.hazard_name, env.hazard_text] if env.has_hazard() else "No tricks today."
		result_label.add_theme_color_override(&"font_color", env.card_color.lerp(Color.WHITE, 0.35))
	hint.visible = false
	_update_reel()


func _skip_pressed() -> bool:
	for slot in PlayerManager.get_slots():
		var inp := slot.input
		if inp != null and (inp.just_pressed(PlayerInput.Pad.A) or inp.just_pressed(PlayerInput.Pad.START)):
			return true
	return false


func _card_center_x(i: int) -> float:
	return reel.position.x + float(i) * card_step() + CARD_SIZE.x * 0.5


func _update_reel() -> void:
	if reel == null:
		return
	var path := float(_target_index) * card_step() * progress_at(age)
	reel.position.x = (size.x - CARD_SIZE.x) * 0.5 - path
	var settled := phase != Phase.SPIN
	for i in cards.size():
		var d := absf(_card_center_x(i) - size.x * 0.5) / card_step()
		var near := clampf(1.0 - d, 0.0, 1.0)
		var card := cards[i]
		card.pivot_offset = CARD_SIZE * 0.5
		card.scale = Vector2.ONE * (1.0 + 0.07 * near)
		card.modulate = Color(1, 1, 1, 0.72 + 0.28 * near)
		if settled and i != _target_index:
			card.modulate.a = 0.5
	if _backdrop != null:
		var env := Db.get_environment(card_under_marker())
		if env != null:
			_backdrop.self_modulate = Color.WHITE.lerp(env.card_color.lerp(Color.WHITE, 0.5), 0.35)


# =================================================================================================
# One card of the reel
# =================================================================================================

class _EnvCard extends Control:
	var env: EnvironmentData
	var art: Control

	static func create(p_env: EnvironmentData) -> _EnvCard:
		var c := _EnvCard.new()
		c.env = p_env
		c.custom_minimum_size = EnvironmentRollScreen.CARD_SIZE
		c.size = EnvironmentRollScreen.CARD_SIZE
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c._build()
		return c

	func _build() -> void:
		var accent := env.card_color if env != null else UiTheme.GOLD_BORDER
		var frame := Panel.new()
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_theme_stylebox_override(&"panel", UiTheme.stone_style(accent.lerp(UiTheme.GOLD_BORDER, 0.35), UiTheme.STONE))
		add_child(frame)
		art = _ArtView.new()
		art.clip_contents = true
		(art as _ArtView).env = env
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.position = Vector2(14, 14)
		art.size = Vector2(EnvironmentRollScreen.CARD_SIZE.x - 28.0, 250.0)
		add_child(art)
		var name_label := UiTheme.centered_label(env.display_name if env != null else "?", UiTheme.HEADING, 38, accent.lerp(Color.WHITE, 0.4))
		name_label.position = Vector2(14, 274)
		name_label.size = Vector2(EnvironmentRollScreen.CARD_SIZE.x - 28.0, 46)
		add_child(name_label)
		var hazard_text := "No hazard" if env == null or not env.has_hazard() else env.hazard_name
		var hazard_label := UiTheme.centered_label(hazard_text, UiTheme.GOLD_LABEL, 24)
		hazard_label.position = Vector2(14, 322)
		hazard_label.size = Vector2(EnvironmentRollScreen.CARD_SIZE.x - 28.0, 32)
		add_child(hazard_label)
		var desc := UiTheme.wrapped_label(env.description if env != null else "", UiTheme.DIM, 18)
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.position = Vector2(24, 362)
		desc.size = Vector2(EnvironmentRollScreen.CARD_SIZE.x - 48.0, 120)
		add_child(desc)


## The little painted scene on a card: sky, ground and the silhouettes of the decor set.
class _ArtView extends Control:
	var env: EnvironmentData

	func _draw() -> void:
		if env == null:
			return
		var w := size.x
		var h := size.y
		var horizon := h * 0.58
		# Sky (a vertical gradient) and ground.
		var top := env.sky_color.lightened(0.05)
		var low := env.fog_color.lerp(env.sky_color, 0.3).lightened(0.12)
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, horizon), Vector2(0, horizon)]),
				PackedColorArray([top, top, low, low]))
		var ground := env.grass_mid
		var ground_far := env.grass_light.lerp(env.fog_color, 0.25)
		draw_polygon(PackedVector2Array([Vector2(0, horizon), Vector2(w, horizon), Vector2(w, h), Vector2(0, h)]),
				PackedColorArray([ground_far, ground_far, ground, ground]))
		match env.decor_id:
			&"cemetery":
				_cemetery(w, h, horizon)
			&"swamp":
				_swamp(w, h, horizon)
			&"volcano":
				_volcano(w, h, horizon)
			&"ice_cave":
				_ice(w, h, horizon)
			_:
				_forest(w, h, horizon)
		# A thin inner frame.
		draw_rect(Rect2(Vector2.ZERO, size), env.card_color.darkened(0.2), false, 2.0)

	func _forest(w: float, _h: float, horizon: float) -> void:
		var trunk := Color(0.34, 0.22, 0.12)
		for i in 5:
			var x := w * (0.1 + 0.2 * float(i)) + (10.0 if i % 2 == 0 else -6.0)
			var s := 1.0 + 0.25 * float(i % 3)
			draw_rect(Rect2(x - 5.0 * s, horizon - 34.0 * s, 10.0 * s, 40.0 * s), trunk)
			draw_circle(Vector2(x, horizon - 50.0 * s), 30.0 * s, Color(0.2, 0.45, 0.16).lerp(Color(0.33, 0.6, 0.2), float(i % 3) / 3.0))
		# The ruin: a broken arch of stones.
		for i in 3:
			draw_rect(Rect2(w * 0.38 + float(i) * 34.0, horizon + 18.0 - float(i % 2) * 14.0, 26.0, 40.0 + float(i % 2) * 14.0), Color(0.55, 0.52, 0.48))

	func _cemetery(w: float, h: float, horizon: float) -> void:
		draw_circle(Vector2(w * 0.78, h * 0.2), 24.0, Color(0.92, 0.95, 1.0, 0.9))
		draw_circle(Vector2(w * 0.78 + 8.0, h * 0.2 - 4.0), 22.0, env.sky_color.lightened(0.05))
		var bark := Color(0.16, 0.13, 0.15)
		# A dead tree.
		draw_line(Vector2(w * 0.2, horizon + 8.0), Vector2(w * 0.2, horizon - 90.0), bark, 7.0)
		draw_line(Vector2(w * 0.2, horizon - 56.0), Vector2(w * 0.2 + 34.0, horizon - 92.0), bark, 4.0)
		draw_line(Vector2(w * 0.2, horizon - 40.0), Vector2(w * 0.2 - 30.0, horizon - 74.0), bark, 4.0)
		draw_line(Vector2(w * 0.2, horizon - 76.0), Vector2(w * 0.2 - 16.0, horizon - 104.0), bark, 3.0)
		# Headstones.
		var stone := Color(0.5, 0.52, 0.6)
		for i in 5:
			var x := w * (0.3 + 0.13 * float(i))
			var y := horizon + 20.0 + 26.0 * float(i % 2)
			var sw := 30.0
			var sh := 44.0 + 6.0 * float(i % 3)
			draw_rect(Rect2(x - sw * 0.5, y - sh + sw * 0.5, sw, sh - sw * 0.5), stone)
			draw_circle(Vector2(x, y - sh + sw * 0.5), sw * 0.5, stone)
			draw_line(Vector2(x - 6.0, y - sh + 16.0), Vector2(x + 6.0, y - sh + 16.0), stone.darkened(0.3), 3.0)
		# A wisp.
		draw_circle(Vector2(w * 0.55, horizon - 30.0), 7.0, Color(0.55, 1.0, 0.85, 0.85))

	func _swamp(w: float, h: float, horizon: float) -> void:
		var water := Color(0.16, 0.22, 0.12)
		draw_colored_polygon(PackedVector2Array([Vector2(w * 0.1, h * 0.82), Vector2(w * 0.5, h * 0.74), Vector2(w * 0.92, h * 0.84), Vector2(w * 0.5, h * 0.95)]), water)
		var bark := Color(0.25, 0.2, 0.14)
		# A mangrove on its stilts.
		var cx := w * 0.3
		for i in 5:
			var dx := (float(i) - 2.0) * 16.0
			draw_line(Vector2(cx, horizon - 40.0), Vector2(cx + dx, horizon + 20.0), bark, 4.0)
		draw_line(Vector2(cx, horizon - 40.0), Vector2(cx, horizon - 80.0), bark, 7.0)
		draw_circle(Vector2(cx, horizon - 92.0), 36.0, Color(0.18, 0.32, 0.14))
		draw_circle(Vector2(cx + 22.0, horizon - 84.0), 24.0, Color(0.24, 0.38, 0.16))
		# Reeds.
		for i in 9:
			var x := w * (0.55 + 0.045 * float(i))
			var rh := 50.0 + 24.0 * float((i * 7) % 4)
			draw_line(Vector2(x, h * 0.88), Vector2(x + 6.0, h * 0.88 - rh), Color(0.5, 0.56, 0.26), 3.0)
			if i % 3 == 0:
				draw_line(Vector2(x + 5.0, h * 0.88 - rh + 12.0), Vector2(x + 6.0, h * 0.88 - rh), Color(0.34, 0.2, 0.1), 7.0)
		# Fireflies.
		for i in 5:
			draw_circle(Vector2(w * (0.15 + 0.17 * float(i)), horizon - 20.0 - 18.0 * float(i % 3)), 4.0, Color(0.85, 1.0, 0.4, 0.9))

	func _volcano(w: float, h: float, horizon: float) -> void:
		var rock := Color(0.2, 0.15, 0.15)
		draw_colored_polygon(PackedVector2Array([Vector2(w * 0.05, horizon + 6.0), Vector2(w * 0.4, horizon - 118.0), Vector2(w * 0.62, horizon - 118.0), Vector2(w * 0.98, horizon + 6.0)]), rock)
		draw_colored_polygon(PackedVector2Array([Vector2(w * 0.4, horizon - 118.0), Vector2(w * 0.5, horizon - 106.0), Vector2(w * 0.62, horizon - 118.0)]), Color(1.0, 0.5, 0.12))
		# Lava runs down the flank.
		var lava := Color(1.0, 0.45, 0.1)
		draw_line(Vector2(w * 0.5, horizon - 106.0), Vector2(w * 0.46, horizon - 60.0), lava, 5.0)
		draw_line(Vector2(w * 0.46, horizon - 60.0), Vector2(w * 0.52, horizon - 16.0), lava, 4.0)
		draw_line(Vector2(w * 0.52, horizon - 16.0), Vector2(w * 0.44, h * 0.88), lava, 6.0)
		# Vents and embers on the ground.
		for i in 3:
			var x := w * (0.2 + 0.3 * float(i))
			draw_circle(Vector2(x, h * 0.82 + 8.0 * float(i % 2)), 13.0, Color(0.08, 0.05, 0.05))
			draw_circle(Vector2(x, h * 0.82 + 8.0 * float(i % 2)), 8.0, lava)
		for i in 7:
			draw_circle(Vector2(w * (0.1 + 0.13 * float(i)), h * 0.2 + 26.0 * float((i * 5) % 4)), 3.0, Color(1.0, 0.75, 0.3, 0.85))

	func _ice(w: float, h: float, horizon: float) -> void:
		var shades: Array[Color] = [Color(0.6, 0.82, 0.96), Color(0.78, 0.92, 1.0), Color(0.36, 0.58, 0.85), Color(0.7, 0.88, 1.0)]
		var base_x: Array[float] = [0.12, 0.26, 0.4, 0.55, 0.68, 0.82]
		var heights: Array[float] = [70.0, 120.0, 90.0, 150.0, 100.0, 62.0]
		for i in base_x.size():
			var x := w * base_x[i]
			var ch := heights[i]
			var cw := 18.0 + 6.0 * float(i % 3)
			var col := shades[i % shades.size()]
			draw_colored_polygon(PackedVector2Array([Vector2(x - cw, horizon + 16.0), Vector2(x - cw, horizon + 16.0 - ch * 0.7), Vector2(x, horizon + 16.0 - ch), Vector2(x + cw, horizon + 16.0 - ch * 0.7), Vector2(x + cw, horizon + 16.0)]), col)
			draw_line(Vector2(x, horizon + 16.0 - ch), Vector2(x, horizon + 16.0), col.lightened(0.25), 2.0)
		# Snow drifts and sparkles.
		draw_circle(Vector2(w * 0.2, h * 0.9), 36.0, Color(0.9, 0.95, 1.0, 0.8))
		draw_circle(Vector2(w * 0.7, h * 0.94), 44.0, Color(0.9, 0.95, 1.0, 0.8))
		for i in 6:
			draw_circle(Vector2(w * (0.12 + 0.15 * float(i)), h * 0.16 + 24.0 * float((i * 3) % 4)), 2.5, Color(1, 1, 1, 0.9))


## The gold frame round the card under the marker and the two arrows over / under the reel.
class _Marker extends Control:
	func _draw() -> void:
		var cw := EnvironmentRollScreen.CARD_SIZE.x
		var ch := EnvironmentRollScreen.CARD_SIZE.y
		var cx := size.x * 0.5
		# The card under the marker is drawn 7% bigger (EnvironmentRollScreen._update_reel).
		var top := 20.0 + ch * 0.5 - ch * 0.535 - 6.0
		var rect := Rect2(cx - cw * 0.535 - 6.0, top, cw * 1.07 + 12.0, ch * 1.07 + 12.0)
		draw_rect(rect, UiTheme.GOLD_BRIGHT, false, 4.0)
		draw_rect(rect.grow(5.0), Color(UiTheme.GOLD.r, UiTheme.GOLD.g, UiTheme.GOLD.b, 0.35), false, 3.0)
		var arrow := PackedVector2Array([Vector2(cx - 16.0, top - 18.0), Vector2(cx + 16.0, top - 18.0), Vector2(cx, top - 2.0)])
		draw_colored_polygon(arrow, UiTheme.GOLD)
		var low := rect.end.y
		var arrow2 := PackedVector2Array([Vector2(cx - 16.0, low + 18.0), Vector2(cx + 16.0, low + 18.0), Vector2(cx, low + 2.0)])
		draw_colored_polygon(arrow2, UiTheme.GOLD)
