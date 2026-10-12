class_name ElitePlate
extends Node3D
## The look of an elite (M5, GDD 8, architecture §2.5), a child of its [Enemy] built by
## [method Enemy.make_elite] and freed with it:
##   - an overhead nameplate above the (scaled) head: "<Affix> <Enemy name>" in silver over a
##     thin HP bar as wide as the name (with the absorb-shield segment and a small gem in the
##     affix colour, EliteAffixes.COLORS) and a procedural silver dragon wing on each end of the
##     bar ([method wing_texture]) rising beside the name; billboard sprites at a fixed screen
##     size, drawn on top of everything (like the heroes' tags, but below them and below the
##     damage numbers);
##   - a blue bubble around a Shielding elite while its shield holds;
##   - the red tint of an Enraged elite's model once it raged (its body / weapon arm swap to a
##     red-tinted variant of their material; the model's hit flash keeps working on top).
## Visual only: polls the enemy every rendered frame ([method refresh]), changes no gameplay
## state and never touches RunState.rng. Textures, meshes and materials are built once and
## shared by every elite.

## Fixed-size sprites: world size per texel at 1 m depth – one texel is ~1 px at 1080p (the
## same scale as the heroes' health bars, OnionModel.HP_BAR_PIXEL).
const PIXEL := 0.00068
## The wing texture is drawn at this many texels per screen pixel (smooth edges).
const WING_SUPERSAMPLE := 2
## One wing in screen px (the texture is WING_SIZE × WING_SUPERSAMPLE texels).
const WING_SIZE := Vector2i(46, 42)
## Where the wing joins the plate, in wing px from the texture's bottom-right corner (y up).
const WING_ROOT_INSET := Vector2(3.0, 9.0)
## Screen px between a bar end and the wing root (negative: the wing overlaps the bar's rim).
const WING_GAP := -2.0
## HP bar (dark outline, silver rim, dark-red back) in px: at least BAR_SIZE.x wide, else as
## wide as the name plus 2 × BAR_PAD (the wings sit on its ends), at most BAR_MAX_WIDTH.
const BAR_SIZE := Vector2i(100, 10)
const BAR_PAD := 6
const BAR_MAX_WIDTH := 300
const BAR_BORDER := 2
## Height (px, y up) of the bar's centre above the plate origin.
const BAR_Y := 6.0
## Gem below the bar's centre (px).
const GEM_SIZE := Vector2i(12, 14)
## Name text: Label3D font size and world size per font pixel at 1 m (fixed size).
const NAME_FONT_SIZE := 30
const NAME_OUTLINE := 9
const NAME_PIXEL := 0.00037
## Screen px between the bar's top edge and the name's bottom.
const NAME_GAP := 3.0
## Metres between the scaled head top and the plate origin.
const LIFT := 0.4
## Draw order: above the world's transparent effects, below the damage numbers (19 / 20) and
## the heroes' tags (23–28).
const PRIORITY := 12

const SILVER := Color(0.86, 0.89, 0.95)
const SILVER_DARK := Color(0.52, 0.56, 0.64)
const OUTLINE := Color(0.06, 0.035, 0.045)
const BAR_BACK := Color(0.2, 0.04, 0.04, 0.9)
const BAR_FILL := Color(0.88, 0.17, 0.12)
const BAR_SHIELD := Color(0.72, 0.9, 1.0, 0.95)
## Shielding bubble colour and its size relative to the body.
const BUBBLE_COLOR := Color(0.38, 0.68, 1.0)
const BUBBLE_RADIUS_MULT := 1.75
## Enraged: albedo tint of the model's vertex-colour material.
const ENRAGE_TINT := Color(1.0, 0.42, 0.36)

const _BUBBLE_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.38, 0.68, 1.0, 1.0);
void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - facing, 2.2);
	float pulse = 0.85 + 0.15 * sin(TIME * 3.0);
	ALBEDO = mix(tint.rgb, vec3(1.0), rim * 0.3);
	ALPHA = clamp((0.08 + rim * 0.85) * pulse, 0.0, 1.0);
}
"""

static var _wing_texture: Texture2D
## [back, fill] per bar width.
static var _bar_textures: Dictionary[int, Array] = {}
static var _gem_textures: Dictionary[String, Texture2D] = {}
static var _bubble_material: ShaderMaterial

var enemy: Enemy
## The overhead part (billboard sprites), at the head; the bubble hangs off this node.
var plate: Node3D
var name_label: Label3D
var bubble: MeshInstance3D
var _bar_back: Sprite3D
var _bar_fill: Sprite3D
var _bar_shield: Sprite3D
var _wings: Array[Sprite3D] = []
var _gem: Sprite3D
## Bar width in px (see BAR_SIZE / BAR_PAD).
var bar_width := BAR_SIZE.x
var _shown_hp := -1.0
var _shown_shield := -1.0
var _tinted := false


## Builds the look of [param p_enemy] (an elite with its model already set up); add it as
## the enemy's child.
static func create(p_enemy: Enemy) -> ElitePlate:
	var p := ElitePlate.new()
	p.name = "ElitePlate"
	p.enemy = p_enemy
	p._build()
	p.refresh()
	return p


func _process(_delta: float) -> void:
	refresh()


## Brings the bar, the shield segment, the bubble and the enrage tint up to date.
func refresh() -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	plate.visible = not enemy.is_dead()
	var max_hp := maxf(0.001, enemy.max_hp)
	var hp := clampf(enemy.hp / max_hp, 0.0, 1.0)
	var shield := clampf(enemy.shield_hp / max_hp, 0.0, 1.0)
	if not is_equal_approx(hp, _shown_hp) or not is_equal_approx(shield, _shown_shield):
		_shown_hp = hp
		_shown_shield = shield
		_update_bar()
	bubble.visible = enemy.shield_hp > 0.0 and not enemy.is_dead()
	if enemy.is_enraged() and not _tinted:
		_tint_model()


## HP fraction the bar shows (0..1).
func hp_ratio() -> float:
	return maxf(0.0, _shown_hp)


## Shield fraction (of max HP) the bar's shield segment shows.
func shield_ratio() -> float:
	return maxf(0.0, _shown_shield)


## Whether the Enraged tint has been applied to the model.
func is_tinted() -> bool:
	return _tinted


# --- Building --------------------------------------------------------------------------

func _build() -> void:
	var head := 1.2
	if enemy.model != null:
		head = enemy.model.head_height * enemy.model.scale.y
	plate = Node3D.new()
	plate.name = "Plate"
	plate.position = Vector3(0.0, head + LIFT, 0.0)
	add_child(plate)

	var text := EliteAffixes.display_name(enemy.elite_affix,
			enemy.data.display_name if enemy.data != null else "")
	bar_width = bar_width_for(text)
	var bars := bar_textures(bar_width)
	_bar_back = _sprite("BarBack", bars[0], PIXEL, PRIORITY + 1)
	_bar_back.offset = Vector2(0.0, BAR_Y)
	var inner := _bar_inner()
	_bar_fill = _sprite("BarFill", bars[1], PIXEL, PRIORITY + 2)
	_bar_fill.centered = false
	_bar_fill.region_enabled = true
	_bar_fill.modulate = BAR_FILL
	_bar_fill.offset = Vector2(-inner.x * 0.5, BAR_Y - inner.y * 0.5)
	_bar_shield = _sprite("BarShield", bars[1], PIXEL, PRIORITY + 3)
	_bar_shield.centered = false
	_bar_shield.region_enabled = true
	_bar_shield.modulate = BAR_SHIELD

	_gem = _sprite("Gem", gem_texture(EliteAffixes.color_of(enemy.elite_affix)), PIXEL, PRIORITY + 4)
	_gem.offset = Vector2(0.0, BAR_Y - BAR_SIZE.y * 0.5 - GEM_SIZE.y * 0.5 + 4.0)

	name_label = Label3D.new()
	name_label.name = "Name"
	name_label.text = text
	name_label.font_size = NAME_FONT_SIZE
	name_label.outline_size = NAME_OUTLINE
	name_label.pixel_size = NAME_PIXEL
	name_label.modulate = SILVER
	name_label.outline_modulate = OUTLINE
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.fixed_size = true
	name_label.no_depth_test = true
	name_label.shaded = false
	name_label.double_sided = true
	name_label.render_priority = PRIORITY + 6
	name_label.outline_render_priority = PRIORITY + 5
	name_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var name_bottom := BAR_Y + BAR_SIZE.y * 0.5 + NAME_GAP
	name_label.offset = Vector2(0.0, name_bottom * PIXEL / NAME_PIXEL)
	plate.add_child(name_label)

	# The wings sit on the bar's ends and rise beside the name.
	var half := bar_width * 0.5 + WING_GAP
	var ss := float(WING_SUPERSAMPLE)
	var wing := wing_texture()
	for side in [-1.0, 1.0]:
		var w := _sprite("WingLeft" if side < 0.0 else "WingRight", wing, PIXEL / ss, PRIORITY)
		w.centered = false
		w.flip_h = side > 0.0
		var root_x := float(WING_SIZE.x) - WING_ROOT_INSET.x  # from the texture's left edge
		var left := -half - root_x if side < 0.0 else half - WING_ROOT_INSET.x
		w.offset = Vector2(left * ss, (BAR_Y - WING_ROOT_INSET.y) * ss)
		_wings.append(w)

	bubble = MeshInstance3D.new()
	bubble.name = "ShieldBubble"
	bubble.mesh = MeshKit.cached("elite:bubble", func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = 24
		s.rings = 12
		return s)
	bubble.material_override = bubble_material()
	bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var r := maxf(enemy.radius * BUBBLE_RADIUS_MULT, head * 0.55)
	bubble.scale = Vector3(r, maxf(r, head * 0.62), r)
	bubble.position = Vector3(0.0, head * 0.48, 0.0)
	bubble.visible = false
	add_child(bubble)


func _sprite(n: String, texture: Texture2D, pixel: float, priority: int) -> Sprite3D:
	var s := Sprite3D.new()
	s.name = n
	s.texture = texture
	s.pixel_size = pixel
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.fixed_size = true
	s.no_depth_test = true
	s.shaded = false
	s.double_sided = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	s.render_priority = priority
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plate.add_child(s)
	return s


func _update_bar() -> void:
	var inner := _bar_inner()
	var fill_w := roundf(inner.x * _shown_hp)
	if _shown_hp > 0.0:
		fill_w = maxf(fill_w, 1.0)  # a sliver of life stays visible
	_bar_fill.visible = fill_w > 0.0
	_bar_fill.region_rect = Rect2(0, 0, maxf(fill_w, 1.0), inner.y)
	var shield_w := roundf(inner.x * _shown_shield)
	_bar_shield.visible = shield_w > 0.0
	if not _bar_shield.visible:
		return
	# After the HP fill, over its end when the two overflow the bar.
	var start := minf(fill_w, inner.x - shield_w)
	_bar_shield.region_rect = Rect2(0, 0, shield_w, inner.y)
	_bar_shield.offset = Vector2(-inner.x * 0.5 + start, _bar_fill.offset.y)


## Enraged: the model's body and weapon arm switch to a red-tinted material (the model's
## overlay logic picks the new material up as its base, so hit flashes still show).
func _tint_model() -> void:
	_tinted = true
	if enemy.model == null:
		return
	var tinted := Mats.toon_vc(true, ENRAGE_TINT)
	for path: NodePath in [^"Pivot/Body", ^"Pivot/Arm"]:
		var mi := enemy.model.get_node_or_null(path) as MeshInstance3D
		if mi != null:
			mi.material_override = tinted


func _bar_inner() -> Vector2:
	return Vector2(bar_width - BAR_BORDER * 2, BAR_SIZE.y - BAR_BORDER * 2)


## Bar width (px, even) for a plate showing [param text].
static func bar_width_for(text: String) -> int:
	var w := clampi(ceili(text_width_px(text)) + BAR_PAD * 2, BAR_SIZE.x, BAR_MAX_WIDTH)
	return w + w % 2


## Width in screen px (1080p) of [param text] on the plate.
static func text_width_px(text: String) -> float:
	var font := ThemeDB.fallback_font
	if font == null or text == "":
		return 0.0
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FONT_SIZE).x + NAME_OUTLINE
	return w * NAME_PIXEL / PIXEL


# --- Shared textures / materials -------------------------------------------------------

## Builds the shared textures and material ahead of the first elite (the wing texture takes a
## few dozen ms): WaveDirector calls it when a wave starts with elites scheduled, so the first
## nameplate does not stall a frame in the middle of the fight.
static func prepare() -> void:
	wing_texture()
	bar_textures()
	bubble_material()


## [back, fill] for a bar [param width] px wide: the framed bar (dark outline, silver rim with
## a lighter top, dark-red back) and the white fill strip (tinted through modulate). Cached
## per width (a handful of name lengths exist).
static func bar_textures(width: int = BAR_SIZE.x) -> Array[Texture2D]:
	if _bar_textures.has(width):
		var cached: Array[Texture2D] = []
		cached.assign(_bar_textures[width])
		return cached
	var h := BAR_SIZE.y
	var back := Image.create(width, h, false, Image.FORMAT_RGBA8)
	back.fill(OUTLINE)
	back.fill_rect(Rect2i(1, 1, width - 2, h - 2), SILVER_DARK)
	back.fill_rect(Rect2i(1, 1, width - 2, 1), SILVER)
	var inner := Vector2i(width - BAR_BORDER * 2, h - BAR_BORDER * 2)
	back.fill_rect(Rect2i(Vector2i.ONE * BAR_BORDER, inner), BAR_BACK)
	var fill := Image.create(inner.x, inner.y, false, Image.FORMAT_RGBA8)
	for y in inner.y:
		var shade := 1.0 if y == 0 else (0.9 if y < inner.y * 0.45 else 0.72)
		fill.fill_rect(Rect2i(0, y, inner.x, 1), Color(shade, shade, shade))
	var out: Array[Texture2D] = [ImageTexture.create_from_image(back), ImageTexture.create_from_image(fill)]
	_bar_textures[width] = out
	return out


## A small faceted gem in [param color] with a silver rim and a dark outline (cached per
## colour).
static func gem_texture(color: Color) -> Texture2D:
	var key := color.to_html()
	if _gem_textures.has(key):
		return _gem_textures[key]
	var w := GEM_SIZE.x
	var h := GEM_SIZE.y
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var hw := w * 0.5 - 0.5
	var hh := h * 0.5 - 0.5
	for y in h:
		for x in w:
			var dx := (x + 0.5 - w * 0.5) / hw
			var dy := (y + 0.5 - h * 0.5) / hh
			var d := absf(dx) + absf(dy)  # 1 = the diamond's edge
			if d > 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var c: Color
			if d > 0.82:
				c = OUTLINE
			elif d > 0.62:
				c = SILVER if dx + dy < 0.0 else SILVER_DARK
			else:
				c = color.lightened(0.35) if dx + dy < -0.15 else (color if dx + dy < 0.25 else color.darkened(0.3))
			img.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
	var tex := ImageTexture.create_from_image(img)
	_gem_textures[key] = tex
	return tex


## The left dragon wing (the right one is the same texture flipped): a silver arm bone from
## the root up to a clawed wrist, three finger bones fanning out from it and a membrane with
## scalloped edges between them, all with a dark outline. WING_SIZE × WING_SUPERSAMPLE
## texels, 2 × 2 samples per texel. Built once.
static func wing_texture() -> Texture2D:
	if _wing_texture != null:
		return _wing_texture
	var ss := WING_SUPERSAMPLE
	var w := WING_SIZE.x * ss
	var h := WING_SIZE.y * ss
	var k := float(ss)
	# Key points in wing px (y down), scaled to texels.
	var root := Vector2(WING_SIZE.x - WING_ROOT_INSET.x, WING_SIZE.y - WING_ROOT_INSET.y) * k
	var wrist := Vector2(25.0, 7.0) * k
	var claw := Vector2(29.0, 0.8) * k
	var tips: Array[Vector2] = [Vector2(1.5, 5.0) * k, Vector2(1.0, 20.0) * k, Vector2(7.0, 32.0) * k]
	var tail := Vector2(23.0, 40.5) * k
	var membrane := PackedVector2Array([root, wrist, tips[0], tips[1], tips[2], tail])
	# Scallops: circles through two neighbouring edge points, bulging into the membrane.
	var scallops: Array[Vector3] = []
	var edge_points: Array[Vector2] = [tips[0], tips[1], tips[2], tail]
	var centroid := Vector2.ZERO
	for v in membrane:
		centroid += v
	centroid /= float(membrane.size())
	for i in edge_points.size() - 1:
		var a := edge_points[i]
		var b := edge_points[i + 1]
		var mid := (a + b) * 0.5
		var half_len := a.distance_to(b) * 0.5
		var sag := half_len * 0.42
		var outward := Vector2(-(b - a).y, (b - a).x).normalized()
		if outward.dot(mid - centroid) < 0.0:
			outward = -outward
		var dist := (half_len * half_len - sag * sag) / (2.0 * sag)
		var c := mid + outward * dist
		scallops.append(Vector3(c.x, c.y, dist + sag))
	# Bones: [from, to, half width] in texels.
	var bones: Array = [
		[root, wrist, 1.6 * k],
		[wrist, claw, 1.1 * k],
		[wrist, tips[0], 0.95 * k],
		[wrist, tips[1], 0.85 * k],
		[wrist, tips[2], 0.8 * k],
	]
	var cover := PackedFloat32Array()
	cover.resize(w * h)
	var colors: Array[Color] = []
	colors.resize(w * h)
	var span := root.distance_to(tips[1])
	for y in h:
		for x in w:
			var sum := 0.0
			var col := Color(0, 0, 0, 0)
			for sy in 2:
				for sx in 2:
					var p := Vector2(x + 0.25 + 0.5 * sx, y + 0.25 + 0.5 * sy)
					var bone_shade := -1.0
					for b in bones:
						var q := Geometry2D.get_closest_point_to_segment(p, b[0], b[1])
						var d := p.distance_to(q)
						if d <= b[2]:
							# Lit on the upper-left side of the bone.
							bone_shade = maxf(bone_shade, 1.0 - 0.35 * (d / b[2]))
					if bone_shade >= 0.0:
						sum += 1.0
						col += SILVER.lightened(0.1) * bone_shade
						continue
					if not Geometry2D.is_point_in_polygon(p, membrane):
						continue
					var cut := false
					for s in scallops:
						if p.distance_to(Vector2(s.x, s.y)) < s.z:
							cut = true
							break
					if cut:
						continue
					# Membrane: darker at the root, lighter towards the edge, faint ribs.
					var t := clampf(p.distance_to(root) / span, 0.0, 1.0)
					var shade := lerpf(0.62, 0.86, t)
					sum += 1.0
					col += Color(SILVER_DARK.r * shade * 1.3, SILVER_DARK.g * shade * 1.3, SILVER_DARK.b * shade * 1.35)
			var i := y * w + x
			cover[i] = sum / 4.0
			colors[i] = col / sum if sum > 0.0 else Color(0, 0, 0, 0)
	# Dark outline: every texel within OUTLINE_TEXELS of the shape.
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var reach := ss + 1
	for y in h:
		for x in w:
			var i := y * w + x
			var c := cover[i]
			var near := 0.0
			if c < 1.0:
				for oy in range(-reach, reach + 1):
					var yy := y + oy
					if yy < 0 or yy >= h:
						continue
					for ox in range(-reach, reach + 1):
						var xx := x + ox
						if xx < 0 or xx >= w or ox * ox + oy * oy > reach * reach:
							continue
						near = maxf(near, cover[yy * w + xx])
			var base := colors[i] if c > 0.0 else OUTLINE
			var out := OUTLINE.lerp(Color(base.r, base.g, base.b), c)
			var alpha := maxf(c, clampf(near * 1.6, 0.0, 1.0))
			img.set_pixel(x, y, Color(out.r, out.g, out.b, alpha))
	_wing_texture = ImageTexture.create_from_image(img)
	return _wing_texture


## The shared Shielding bubble material (additive rim glow with a slow pulse).
static func bubble_material() -> ShaderMaterial:
	if _bubble_material != null:
		return _bubble_material
	var sh := Shader.new()
	sh.code = _BUBBLE_CODE
	_bubble_material = ShaderMaterial.new()
	_bubble_material.shader = sh
	_bubble_material.render_priority = 3
	_bubble_material.set_shader_parameter(&"tint", BUBBLE_COLOR)
	return _bubble_material
