extends SceneTree
## Text cards of the trailer (dev tool, see tools/trailer/README.md): renders every card on its own as a short movie
## so ffmpeg can lay them over any shot at any time (make_trailer.sh).
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --write-movie cards_text.avi --fixed-fps 30 --resolution 1920x1080 \
##       --path . --rendering-driver opengl3 -s res://tools/trailer/cards.gd -- --pass=text --marks=cards_text.json
##
## Two passes with the same animation: --pass=text draws the lettering (gold on black: added to the picture),
## --pass=dim draws the darkening band behind it (black on white: multiplied into the picture). Cinzel, the game's
## title font, is set the way UiTheme.title_font() does it (bold weight of the variable font).

const FPS := 30
const TITLE_FONT_PATH := "res://assets/fonts/Cinzel-VariableFont_wght.ttf"
## The OpenType tag of the weight axis ("wght").
const WEIGHT_TAG := 0x77676874
const GOLD_TOP := Color(1.0, 0.95, 0.72)
const GOLD_BOTTOM := Color(0.93, 0.66, 0.2)
const SILVER_TOP := Color(1.0, 1.0, 0.98)
const SILVER_BOTTOM := Color(0.78, 0.8, 0.86)
const GAP_FRAMES := 4

## Card kinds: "title" (slams in), "big" (tracks in, centred), "label" (a lower third for the class cuts), "end".
## A line: t text, size px, weight (400..900), track (letter spacing px), gold (false = silver).
const CARDS: Array[Dictionary] = [
	{"id": "title", "kind": "title", "frames": 92, "lines": [
		{"t": "SMARTONION", "size": 196, "weight": 800, "track": 12, "gold": true},
		{"t": "A FANTASY MMO PARODY", "size": 36, "weight": 600, "track": 15, "gold": false}]},
	{"id": "coop", "kind": "big", "frames": 84, "lines": [{"t": "1–4 PLAYER CO-OP", "size": 124, "weight": 800, "track": 8, "gold": true}]},
	{"id": "classes", "kind": "big", "frames": 78, "lines": [{"t": "7 ONION CLASSES", "size": 124, "weight": 800, "track": 8, "gold": true}]},
	{"id": "loot", "kind": "big", "frames": 87, "lines": [{"t": "LOOT. SO MUCH LOOT.", "size": 124, "weight": 800, "track": 8, "gold": true}]},
	{"id": "build", "kind": "big", "frames": 90, "lines": [{"t": "TALENTS · FORGING · TIER SETS", "size": 82, "weight": 800, "track": 6, "gold": true}]},
	{"id": "bosses", "kind": "big", "frames": 78, "lines": [{"t": "EPIC BOSSES", "size": 138, "weight": 900, "track": 10, "gold": true}]},
	{"id": "variety", "kind": "big", "frames": 96, "lines": [{"t": "5 ARENAS · DUNGEONS · ENDLESS MODE", "size": 64, "weight": 800, "track": 6, "gold": true}]},
	{"id": "survive", "kind": "big", "frames": 72, "lines": [{"t": "SURVIVE 25 WAVES", "size": 138, "weight": 900, "track": 10, "gold": true}]},
	{"id": "end", "kind": "end", "frames": 165, "lines": [
		{"t": "SMARTONION", "size": 178, "weight": 800, "track": 12, "gold": true},
		{"t": "COMING SOON TO STEAM", "size": 50, "weight": 700, "track": 14, "gold": false}]},
	{"id": "l_warrior", "kind": "label", "frames": 42, "lines": [{"t": "WARRIOR", "size": 62, "weight": 800, "track": 8, "gold": true}]},
	{"id": "l_mage", "kind": "label", "frames": 42, "lines": [{"t": "MAGE", "size": 62, "weight": 800, "track": 8, "gold": true}]},
	{"id": "l_paladin", "kind": "label", "frames": 42, "lines": [{"t": "PALADIN", "size": 62, "weight": 800, "track": 8, "gold": true}]},
	{"id": "l_rogue", "kind": "label", "frames": 42, "lines": [{"t": "ROGUE", "size": 62, "weight": 800, "track": 8, "gold": true}]},
	{"id": "l_warlock", "kind": "label", "frames": 42, "lines": [{"t": "WARLOCK", "size": 62, "weight": 800, "track": 8, "gold": true}]},
	{"id": "l_hunter", "kind": "label", "frames": 54, "lines": [
		{"t": "HUNTER", "size": 62, "weight": 800, "track": 8, "gold": true},
		{"t": "WOLF · BOAR · OWL COMPANIONS", "size": 24, "weight": 600, "track": 7, "gold": false}]},
	{"id": "l_shaman", "kind": "label", "frames": 54, "lines": [
		{"t": "SHAMAN", "size": 62, "weight": 800, "track": 8, "gold": true},
		{"t": "TOTEMS", "size": 24, "weight": 600, "track": 7, "gold": false}]},
]

const _GRADIENT_SHADER := """
shader_type canvas_item;
uniform vec4 top_color : source_color = vec4(1.0, 0.95, 0.72, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.93, 0.66, 0.2, 1.0);
uniform float y_top = 0.0;
uniform float y_bottom = 100.0;
void fragment() {
	float g = clamp((FRAGCOORD.y - y_top) / max(y_bottom - y_top, 1.0), 0.0, 1.0);
	vec3 tint = mix(top_color.rgb, bottom_color.rgb, g);
	COLOR = vec4(COLOR.rgb * tint, COLOR.a);
}
"""

const _DIM_SHADER := """
shader_type canvas_item;
uniform float max_alpha = 0.78;
uniform float horizontal = 0.0;
uniform float fade = 1.0;
void fragment() {
	float v = smoothstep(0.0, 0.34, UV.y) * smoothstep(1.0, 0.66, UV.y);
	float h = mix(1.0, 1.0 - smoothstep(0.42, 1.0, UV.x), horizontal);
	COLOR = vec4(0.0, 0.0, 0.0, max_alpha * v * h * fade);
}
"""

var _pass := "text"
var _only := ""
var _marks_path := ""
var _marks: Array[Dictionary] = []
var _frame := 0
var _font: FontVariation
var _gradient: Shader
var _stage: Control
var _bg: ColorRect
var _dim_band: ColorRect
var _lines: Array[Label] = []
var _ornament: Control
var _card: Dictionary = {}
var _card_frame := 0
var _queue: Array[Dictionary] = []
var _cursor := -1
var _gap := 0
var _clip_start := 0


func _initialize() -> void:
	for raw in OS.get_cmdline_user_args():
		var arg := String(raw)
		if arg.begins_with("--pass="):
			_pass = arg.get_slice("=", 1)
		elif arg.begins_with("--marks="):
			_marks_path = arg.get_slice("=", 1)
		elif arg.begins_with("--only="):
			_only = arg.get_slice("=", 1)
	var cinzel := load(TITLE_FONT_PATH) as Font
	_font = FontVariation.new()
	_font.base_font = cinzel
	_font.variation_opentype = {WEIGHT_TAG: 800.0}
	_font.fallbacks = [ThemeDB.fallback_font]
	_gradient = Shader.new()
	_gradient.code = _GRADIENT_SHADER
	for c in CARDS:
		if _only == "" or String(c["id"]) in _only.split(","):
			_queue.append(c)
	RenderingServer.set_default_clear_color(Color.BLACK if _pass == "text" else Color.WHITE)
	_build_stage()
	_next_card()


func _build_stage() -> void:
	var layer := CanvasLayer.new()
	root.add_child(layer)
	_stage = Control.new()
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.size = Vector2(1920, 1080)
	layer.add_child(_stage)
	_bg = ColorRect.new()
	_bg.size = Vector2(1920, 1080)
	_bg.color = Color.BLACK if _pass == "text" else Color.WHITE
	_stage.add_child(_bg)
	if _pass == "dim":
		# The band: black, fading out at its edges (vertically; towards the right for the lower thirds).
		_dim_band = ColorRect.new()
		_dim_band.color = Color.WHITE
		var mat := ShaderMaterial.new()
		mat.shader = Shader.new()
		mat.shader.code = _DIM_SHADER
		_dim_band.material = mat
		_stage.add_child(_dim_band)
	_ornament = Control.new()
	_ornament.size = Vector2(1920, 1080)
	_ornament.draw.connect(_draw_ornament)
	_ornament.visible = _pass == "text"
	_stage.add_child(_ornament)


func _next_card() -> void:
	if _cursor >= 0 and _cursor < _queue.size():
		_marks.append({"name": String(_queue[_cursor]["id"]), "start": _clip_start, "frames": _frame - _clip_start})
	_cursor += 1
	if _cursor >= _queue.size():
		_finish()
		return
	_card = _queue[_cursor]
	_card_frame = 0
	_clip_start = _frame
	_layout_card()


func _finish() -> void:
	if _marks_path != "":
		var f := FileAccess.open(_marks_path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify({"pass": _pass, "fps": FPS, "total_frames": _frame, "clips": _marks}, "\t"))
			f.close()
	quit()


## Builds the labels of the current card; the animation only moves / fades them.
func _layout_card() -> void:
	for l in _lines:
		l.queue_free()
	_lines.clear()
	var kind := String(_card["kind"])
	var specs: Array = _card["lines"]
	var heights: Array[float] = []
	var total := 0.0
	for spec: Dictionary in specs:
		var h := float(spec["size"]) * 1.25
		heights.append(h)
		total += h + (14.0 if heights.size() > 1 else 0.0)
	var block_top := 0.0
	var anchor_x := 960.0
	match kind:
		"label":
			block_top = 1080.0 - 150.0 - total
			anchor_x = 210.0
		"end":
			block_top = 235.0
		_:
			block_top = 540.0 - total * 0.5
	var y := block_top
	for i in specs.size():
		var spec: Dictionary = specs[i]
		var label := Label.new()
		label.text = String(spec["t"])
		label.add_theme_font_override("font", _font_for(spec))
		label.add_theme_font_size_override("font_size", int(spec["size"]))
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.0))
		label.add_theme_constant_override("outline_size", maxi(6, int(float(spec["size"]) * 0.07)))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if kind != "label" else HORIZONTAL_ALIGNMENT_LEFT
		label.size = Vector2(1900.0, heights[i])
		label.position = Vector2(10.0 if kind != "label" else anchor_x - 150.0, y)
		if kind == "label":
			label.position.x = 120.0
		label.pivot_offset = Vector2(label.size.x * (0.5 if kind != "label" else 0.0), heights[i] * 0.5)
		label.visible = _pass == "text"
		var mat := ShaderMaterial.new()
		mat.shader = _gradient
		var gold := bool(spec["gold"])
		mat.set_shader_parameter("top_color", GOLD_TOP if gold else SILVER_TOP)
		mat.set_shader_parameter("bottom_color", GOLD_BOTTOM if gold else SILVER_BOTTOM)
		mat.set_shader_parameter("y_top", y + heights[i] * 0.22)
		mat.set_shader_parameter("y_bottom", y + heights[i] * 0.86)
		label.material = mat
		_stage.add_child(label)
		_lines.append(label)
		y += heights[i] + 14.0
	var kind_band := kind
	if _pass == "dim":
		match kind_band:
			"label":
				_dim_band.position = Vector2(0, block_top - 70.0)
				_dim_band.size = Vector2(1180, total + 140.0)
				(_dim_band.material as ShaderMaterial).set_shader_parameter("horizontal", 1.0)
				(_dim_band.material as ShaderMaterial).set_shader_parameter("max_alpha", 0.7)
			"end":
				_dim_band.position = Vector2(0, block_top - 170.0)
				_dim_band.size = Vector2(1920, total + 340.0)
				(_dim_band.material as ShaderMaterial).set_shader_parameter("horizontal", 0.0)
				(_dim_band.material as ShaderMaterial).set_shader_parameter("max_alpha", 0.62)
			_:
				_dim_band.position = Vector2(0, block_top - 150.0)
				_dim_band.size = Vector2(1920, total + 300.0)
				(_dim_band.material as ShaderMaterial).set_shader_parameter("horizontal", 0.0)
				(_dim_band.material as ShaderMaterial).set_shader_parameter("max_alpha", 0.74)
	_ornament.set_meta(&"y", y)
	_ornament.set_meta(&"kind", kind)
	_ornament.queue_redraw()


func _font_for(spec: Dictionary) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = _font.base_font
	f.variation_opentype = {WEIGHT_TAG: float(spec["weight"])}
	f.fallbacks = _font.fallbacks
	f.spacing_glyph = int(spec["track"])
	return f


func _process(_delta: float) -> bool:
	if _cursor >= _queue.size():
		return false
	var total_frames := int(_card["frames"])
	if _gap > 0:
		_gap -= 1
		for l in _lines:
			l.modulate.a = 0.0
		_ornament.modulate.a = 0.0
		_set_dim_alpha(0.0)
		_frame += 1
		if _gap == 0:
			_next_card()
		return false
	var t := float(_card_frame) / float(FPS)
	var dur := float(total_frames) / float(FPS)
	_animate(t, dur)
	_card_frame += 1
	_frame += 1
	if _card_frame >= total_frames:
		_gap = GAP_FRAMES
	return false


## Fade in (and, per kind, track in / slam), a slow drift while it holds, fade out.
func _animate(t: float, dur: float) -> void:
	var kind := String(_card["kind"])
	var fade_in := 0.3 if kind != "title" else 0.12
	var fade_out := 0.32 if kind != "end" else 0.0
	var a_in := clampf(t / fade_in, 0.0, 1.0)
	var a_out := clampf((dur - t) / fade_out, 0.0, 1.0) if fade_out > 0.0 else 1.0
	var alpha := _ease_out(a_in) * a_out
	var drift := 1.0 + 0.03 * (t / dur)
	for i in _lines.size():
		var label := _lines[i]
		var spec: Dictionary = _card["lines"][i]
		var delay := 0.0 if i == 0 else 0.22
		var lt := maxf(t - delay, 0.0)
		var la := clampf(lt / fade_in, 0.0, 1.0) * a_out
		var scale := drift
		var track := float(spec["track"])
		match kind:
			"title":
				var k := clampf(lt / 0.22, 0.0, 1.0)
				scale = lerpf(1.45, 1.0, _ease_out_back(k)) * (1.0 + 0.02 * (t / dur)) if i == 0 else drift
				la = clampf(lt / fade_in, 0.0, 1.0) * a_out
			"big", "end":
				var k2 := clampf(lt / 0.5, 0.0, 1.0)
				track = lerpf(track * 3.2, track, _ease_out(k2))
				scale = lerpf(1.08, 1.0, _ease_out(k2)) * (1.0 + 0.012 * (t / dur))
			"label":
				var k3 := clampf(lt / 0.3, 0.0, 1.0)
				label.position.x = lerpf(60.0, 120.0, _ease_out(k3))
				scale = 1.0
		var f := label.get_theme_font("font") as FontVariation
		if f != null:
			f.spacing_glyph = int(round(track))
		label.scale = Vector2(scale, scale)
		label.modulate.a = la
	_ornament.modulate.a = alpha
	_set_dim_alpha(alpha)


func _set_dim_alpha(a: float) -> void:
	if _dim_band != null:
		(_dim_band.material as ShaderMaterial).set_shader_parameter("fade", a)


static func _ease_out(k: float) -> float:
	return 1.0 - pow(1.0 - k, 3.0)


static func _ease_out_back(k: float) -> float:
	var c1 := 1.4
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(k - 1.0, 3.0) + c1 * pow(k - 1.0, 2.0)


## A thin gold rule with a diamond, under the lettering of the centred cards (like the game's panel dividers).
func _draw_ornament() -> void:
	var kind := String(_ornament.get_meta(&"kind", ""))
	if kind == "title" or kind == "end" or kind == "label":
		return
	var y := float(_ornament.get_meta(&"y", 600.0)) + 6.0
	var c := Color(0.93, 0.7, 0.28)
	var half := 380.0
	_ornament.draw_line(Vector2(960.0 - half, y), Vector2(960.0 - 22.0, y), c, 3.0, true)
	_ornament.draw_line(Vector2(960.0 + 22.0, y), Vector2(960.0 + half, y), c, 3.0, true)
	var d := PackedVector2Array([Vector2(960, y - 11), Vector2(971, y), Vector2(960, y + 11), Vector2(949, y)])
	_ornament.draw_colored_polygon(d, c)
