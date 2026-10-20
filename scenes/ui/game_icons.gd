class_name GameIcons
extends RefCounted
## The picture side of the UI's icons (M7b, VIS-UI): resolves ability / talent / talent tree /
## consumable / shrine ids to the game-icons.net silhouettes of data/icons/icon_map.tres
## ([IconMap]) and draws them tinted. A white silhouette on transparent is drawn with a vertical
## gradient of the school / class / item colour over a dark outline, on the frame the owning
## control already draws (AbilityIcon, TalentGlyph, ConsumableIcon, ShrineIcon); a null result
## means "no picture for this id" and the control keeps its procedural glyph.
## Textures are loaded once (the resource cache hands out the same instance), no instance
## uniforms, no shaders.

const MAP_PATH := "res://data/icons/icon_map.tres"
## Texture filter of the controls that draw these (the imports have mipmaps: a 128 px picture
## shown at 40-60 px stays smooth).
const FILTER := CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
const OUTLINE := Color(0.05, 0.03, 0.02, 0.95)

static var _map: IconMap
static var _textures: Dictionary[String, Texture2D] = {}


## The shipped map (loaded once).
static func icon_map() -> IconMap:
	if _map == null:
		_map = load(MAP_PATH) as IconMap
		if _map == null:
			_map = IconMap.new()
	return _map


## The texture at [param path], shared by every caller (null when it cannot be loaded).
static func texture_at(path: String) -> Texture2D:
	if path == "":
		return null
	var tex: Texture2D = _textures.get(path)
	if tex == null and ResourceLoader.exists(path):
		tex = load(path) as Texture2D
		if tex != null:
			_textures[path] = tex
	return tex


# --- Lookups (null = no picture: keep the procedural glyph) ---------------------------------------

## The picture of [param a]: its icon id, then its id, then its id without the class prefix
## ("mage_blink" -> "blink"). Not the school: see [method for_school].
static func for_ability(a: AbilityData) -> Texture2D:
	if a == null:
		return null
	return for_ability_ids(a.icon, a.id, a.class_id)


static func for_ability_ids(icon: StringName, id: StringName = &"", class_id: StringName = &"") -> Texture2D:
	var abilities := icon_map().abilities
	for key: StringName in [icon, id]:
		if key != &"" and abilities.has(key):
			return texture_at(abilities[key])
	var prefix := String(class_id) + "_"
	if class_id != &"" and String(id).begins_with(prefix):
		var short := StringName(String(id).trim_prefix(prefix))
		if abilities.has(short):
			return texture_at(abilities[short])
	return null


## The picture of a school (the fallback of an ability without picture and glyph rule).
static func for_school(school: StringName) -> Texture2D:
	return texture_at(icon_map().schools.get(school, ""))


## The picture of a stat id (&"crit", &"armor" ...).
static func for_stat(stat: StringName) -> Texture2D:
	return texture_at(icon_map().stats.get(stat, ""))


## The picture of [param t]: its own entry (every shipped talent has one), else its icon id as an
## ability or a stat, else the ability a modifier changes.
static func for_talent(t: TalentData) -> Texture2D:
	if t == null:
		return null
	var map := icon_map()
	if map.talents.has(t.id):
		return texture_at(map.talents[t.id])
	for key: StringName in [t.icon, t.ability]:
		if key == &"":
			continue
		var tex := for_ability_ids(key)
		if tex == null:
			tex = for_stat(key)
		if tex != null:
			return tex
	return null


## The picture of a talent tree: its own entry, else its icon id as an ability.
static func for_tree(tree: TalentTreeData) -> Texture2D:
	if tree == null:
		return null
	var map := icon_map()
	if map.trees.has(tree.id):
		return texture_at(map.trees[tree.id])
	return for_ability_ids(tree.icon)


static func for_consumable(c: ConsumableData) -> Texture2D:
	if c == null:
		return null
	return texture_at(icon_map().consumables.get(c.icon_id, icon_map().consumables.get(c.id, "")))


static func for_shrine(s: ShrineData) -> Texture2D:
	if s == null:
		return null
	return texture_at(icon_map().shrines.get(s.icon_id, icon_map().shrines.get(s.id, "")))


# --- Drawing --------------------------------------------------------------------------------------

## Draws [param tex] into [param rect] of [param ci]: a dark outline ([param outline_px] wide, 8
## shifted copies) under the silhouette, tinted with a vertical gradient from [param top] to
## [param bottom]. The canvas item should use [constant FILTER].
static func draw_silhouette(ci: CanvasItem, tex: Texture2D, rect: Rect2, top: Color, bottom: Color,
		outline_px: float = 1.5, outline: Color = OUTLINE) -> void:
	if tex == null:
		return
	if outline_px > 0.0 and outline.a > 0.0:
		for i in 8:
			var a := TAU * i / 8.0
			ci.draw_texture_rect(tex, Rect2(rect.position + Vector2(cos(a), sin(a)) * outline_px, rect.size), false, outline)
	var pts := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	ci.draw_polygon(pts, PackedColorArray([top, top, bottom, bottom]), uvs, tex)


## The gradient ends of a silhouette of [param base] (light at the top, the base tone below).
static func gradient_top(base: Color) -> Color:
	return base.lightened(0.62)


static func gradient_bottom(base: Color) -> Color:
	return base.lightened(0.12)
