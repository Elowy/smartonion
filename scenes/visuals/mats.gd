class_name Mats
extends RefCounted
## STUB – owned by the "visuals" module. Shared material factory with caching.
## Stylised WoW-like look: soft toon shading, rim light, optional inverted-hull outline.


## Lit, toon-shaded material for [param color]. Cached per colour.
static func toon(color: Color) -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m


## Unlit material (VFX, UI-in-world). Supports alpha when color.a < 1.
static func unshaded(color: Color) -> Material:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	return m


## Glowing (emissive) material for epic/legendary items, magic projectiles.
static func glow(color: Color, energy: float = 2.0) -> Material:
	return unshaded(color)
