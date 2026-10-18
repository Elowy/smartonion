class_name DungeonBrazier
extends Node3D
## The brazier of the Defend room (GDD 16.1, room 3: "keep a brazier alive for 20 s"): a stone bowl on
## a pedestal with a flame, standing in the middle of the dungeon. Enemies near it are drawn to it
## ([Dungeon] taunts them) and hurt it through [method take_damage]; when its HP is gone the room
## is lost. Procedural look (MeshKit + Mats): the flame shrinks and reddens with the damage, a small
## HP bar floats over it (a billboard), a flicker animates in [method _process] (cosmetic only).
## Group [constant GROUP]. No physics body: nothing here may switch Enemy's open-field path off.

signal damaged(amount: float)
signal destroyed

const GROUP := &"dungeon_braziers"
## Enemies within this reach (m, beyond their own radius) of the brazier's centre hit it.
const RADIUS := 0.9
const BAR_WIDTH := 1.8
const BAR_HEIGHT := 0.2
const BAR_Y := 2.35
const FLAME_COLOR := Color(1.0, 0.62, 0.18)
const FLAME_HURT_COLOR := Color(0.95, 0.2, 0.08)
const STONE := Color(0.42, 0.4, 0.42)
const STONE_DARK := Color(0.27, 0.25, 0.28)

var max_hp := 100.0
var hp := 100.0

var _flame: MeshInstance3D
var _glow: OmniLight3D
var _fill: MeshInstance3D
var _fill_material: StandardMaterial3D
var _time := 0.0
var _flash := 0.0


## A brazier with [param p_max_hp] HP (full), not in the tree yet.
static func create(p_max_hp: float) -> DungeonBrazier:
	var b := DungeonBrazier.new()
	b.name = "Brazier"
	b.max_hp = maxf(1.0, p_max_hp)
	b.hp = b.max_hp
	b._build()
	return b


func _enter_tree() -> void:
	add_to_group(GROUP)


func is_alive() -> bool:
	return hp > 0.0


## The share of the HP left (0..1).
func hp_ratio() -> float:
	return clampf(hp / maxf(1.0, max_hp), 0.0, 1.0)


## An enemy at [param pos] (XZ) with [param enemy_radius] reaches the brazier.
func reaches(pos: Vector3, enemy_radius: float = 0.0) -> bool:
	var d := Vector2(pos.x - global_position.x, pos.z - global_position.z)
	var reach := RADIUS + enemy_radius + 0.35
	return d.length_squared() <= reach * reach


## Takes [param amount] damage (the flame flinches). Emits [signal damaged]; [signal destroyed] once
## when the HP runs out.
func take_damage(amount: float) -> void:
	if hp <= 0.0 or amount <= 0.0:
		return
	hp = maxf(0.0, hp - amount)
	_flash = 1.0
	damaged.emit(amount)
	_refresh()
	if hp <= 0.0:
		destroyed.emit()


func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(0.0, _flash - delta * 3.0)
	if _flame != null and hp > 0.0:
		var ratio := hp_ratio()
		var flicker := 1.0 + 0.1 * sin(_time * 11.0) + 0.06 * sin(_time * 17.3 + 1.0)
		var s := lerpf(0.55, 1.0, ratio) * flicker * (1.0 + 0.25 * _flash)
		_flame.scale = Vector3(s, s * (1.0 + 0.08 * sin(_time * 7.0)), s)
	if _glow != null:
		_glow.light_energy = (0.5 + 1.6 * hp_ratio() if hp > 0.0 else 0.0) * (1.0 + 0.3 * _flash)


func _build() -> void:
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = MeshKit.cached("dungeon_brazier:body", func() -> Mesh: return _body_mesh())
	body.material_override = Mats.toon_vc()
	add_child(body)
	_flame = MeshInstance3D.new()
	_flame.name = "Flame"
	_flame.mesh = MeshKit.cached("dungeon_brazier:flame", func() -> Mesh: return _flame_mesh())
	_flame.material_override = Mats.glow(FLAME_COLOR, 2.6)
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame.position = Vector3(0.0, 1.12, 0.0)
	add_child(_flame)
	_glow = OmniLight3D.new()
	_glow.name = "Glow"
	_glow.light_color = FLAME_COLOR
	_glow.light_energy = 2.0
	_glow.omni_range = 7.0
	_glow.position = Vector3(0.0, 1.5, 0.0)
	_glow.shadow_enabled = false
	add_child(_glow)
	_build_bar()
	_refresh()


static func _body_mesh() -> Mesh:
	var k := MeshKit.new()
	k.add_cylinder(0.75, 0.85, 0.18, MeshKit.xf(Vector3(0.0, 0.09, 0.0)), STONE_DARK, 16)
	k.add_cylinder(0.34, 0.5, 0.62, MeshKit.xf(Vector3(0.0, 0.49, 0.0)), STONE, 12)
	# The bowl: a wide rim over a narrow base, with a dark inside.
	k.add_cylinder(0.78, 0.46, 0.34, MeshKit.xf(Vector3(0.0, 0.97, 0.0)), STONE, 16)
	k.add_cylinder(0.64, 0.64, 0.04, MeshKit.xf(Vector3(0.0, 1.14, 0.0)), STONE_DARK.darkened(0.4), 16)
	for i in 3:
		var a := TAU * float(i) / 3.0 + 0.4
		k.add_cylinder(0.07, 0.07, 0.5, MeshKit.xf(Vector3(cos(a) * 0.62, 0.3, sin(a) * 0.62)), STONE_DARK, 6)
	return k.build()


static func _flame_mesh() -> Mesh:
	var k := MeshKit.new()
	k.add_cylinder(0.0, 0.34, 0.9, MeshKit.xf(Vector3(0.0, 0.45, 0.0)), FLAME_COLOR, 10)
	k.add_cylinder(0.0, 0.2, 0.65, MeshKit.xf(Vector3(0.0, 0.4, 0.0)), Color(1.0, 0.92, 0.55), 8)
	k.add_cylinder(0.0, 0.14, 0.55, MeshKit.xf(Vector3(0.22, 0.3, 0.1)), FLAME_COLOR, 6)
	k.add_cylinder(0.0, 0.14, 0.5, MeshKit.xf(Vector3(-0.2, 0.27, -0.12)), FLAME_COLOR, 6)
	return k.build()


## The floating HP bar: a dark back quad and a fill quad that shrinks to the left; both billboards.
func _build_bar() -> void:
	var root := Node3D.new()
	root.name = "Bar"
	root.position = Vector3(0.0, BAR_Y, 0.0)
	add_child(root)
	var back := MeshInstance3D.new()
	back.name = "Back"
	var back_mesh := QuadMesh.new()
	back_mesh.size = Vector2(BAR_WIDTH + 0.1, BAR_HEIGHT + 0.08)
	back.mesh = back_mesh
	back.material_override = _bar_material(Color(0.05, 0.04, 0.04, 0.9), 0)
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(back)
	_fill = MeshInstance3D.new()
	_fill.name = "Fill"
	var fill_mesh := QuadMesh.new()
	fill_mesh.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	fill_mesh.center_offset = Vector3(BAR_WIDTH * 0.5, 0.0, 0.0)
	_fill.mesh = fill_mesh
	_fill_material = _bar_material(FLAME_COLOR, 1)
	_fill.material_override = _fill_material
	_fill.position = Vector3(-BAR_WIDTH * 0.5, 0.0, 0.01)
	_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(_fill)


static func _bar_material(color: Color, priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.no_depth_test = true
	m.render_priority = priority
	return m


func _refresh() -> void:
	var ratio := hp_ratio()
	if _fill != null:
		_fill.scale = Vector3(maxf(ratio, 0.0001), 1.0, 1.0)
		_fill_material.albedo_color = FLAME_HURT_COLOR.lerp(FLAME_COLOR, ratio)
	if _flame != null:
		_flame.visible = hp > 0.0
