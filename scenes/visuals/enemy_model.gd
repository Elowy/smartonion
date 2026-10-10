class_name EnemyModel
extends Node3D
## Procedural enemy look per EnemyData.model_style (skeleton, candlekin, gurgler, troll),
## owned by the "visuals" module. Origin at the feet, faces -Z, scaled by data.model_scale.
##
## Built for crowds (up to ~150 on screen): per enemy only 4-5 nodes –
##   EnemyModel → Pivot (yaw + lean + bob + scale) → Body, Arm (weapon arm, pivots at the
##   shoulder), optional Glow (candle flame) – and every Mesh is shared per style + colour.
## Stun stars are created lazily on the first stun.

const STYLES: Array[StringName] = [&"skeleton", &"candlekin", &"gurgler", &"troll"]
const TURN_SPEED := 12.0
const FLASH_TIME := 0.12
const ATTACK_TIME := 0.32
const MAX_WINDUP := 1.2
const WINDUP_COLOR := Color(1.0, 0.18, 0.1)
## Angular speed of the pulsing wind-up tint (shader side).
const WINDUP_PULSE := 30.0

const BONE := Color(0.9, 0.88, 0.78)
const RUST := Color(0.62, 0.36, 0.2)
const IRON := Color(0.36, 0.36, 0.4)
const WOOD := Color(0.48, 0.3, 0.16)
const DARK := Color(0.08, 0.05, 0.06)
const WHITE := Color(0.97, 0.96, 0.92)

var data: EnemyData
var style: StringName = &""
## Height of the head top in metres (after model_scale) – for stars, health bars, text.
var head_height := 1.2

var _pivot: Node3D
var _body: MeshInstance3D
var _arm: MeshInstance3D
var _glow: MeshInstance3D
var _stars: MeshInstance3D
var _arm_rest := Vector3.ZERO
var _scale := 1.0
var _target_yaw := 0.0
var _yaw := 0.0
var _speed_target := 0.0
var _speed := 0.0
var _phase := 0.0
var _time := 0.0
var _flash := 0.0
var _windup := -1.0
var _attack := 1.0
var _stunned := false
var _overlay_dirty := false
## (kind, quantised amount) of the applied overlay: 0 none, 1 hit flash, 2 wind-up.
var _overlay_state := Vector2i.ZERO


func _init() -> void:
	name = "EnemyModel"


func setup(p_data: EnemyData) -> void:
	data = p_data
	style = data.model_style if data != null and data.model_style in STYLES else &"skeleton"
	_scale = data.model_scale if data != null else 1.0
	var color := data.color if data != null else BONE
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_stars = null
	_overlay_state = Vector2i.ZERO
	var parts := parts_for(style, color)
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	_pivot.scale = Vector3.ONE * _scale
	add_child(_pivot)
	_body = MeshInstance3D.new()
	_body.name = "Body"
	_body.mesh = parts["body"]
	_body.material_override = Mats.toon_vc()
	_pivot.add_child(_body)
	_arm = MeshInstance3D.new()
	_arm.name = "Arm"
	_arm.mesh = parts["arm"]
	_arm.material_override = Mats.toon_vc()
	_arm_rest = parts["arm_pivot"]
	_arm.position = _arm_rest
	_pivot.add_child(_arm)
	_glow = null
	if parts.has("glow"):
		_glow = MeshInstance3D.new()
		_glow.name = "Glow"
		_glow.mesh = parts["glow"]
		_glow.material_override = Mats.glow(parts["glow_color"], 2.4)
		_glow.position = parts["glow_pos"]
		_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_pivot.add_child(_glow)
	head_height = float(parts["head_y"]) * _scale
	_pivot.rotation.y = _target_yaw
	_yaw = _target_yaw
	_apply_overlay()


func set_facing(direction: Vector3) -> void:
	if Vector2(direction.x, direction.z).length_squared() < 0.0001:
		return
	_target_yaw = atan2(-direction.x, -direction.z)


func set_moving(speed_ratio: float) -> void:
	_speed_target = clampf(speed_ratio, 0.0, 1.0)


func flash_hit() -> void:
	_flash = 1.0
	_apply_overlay()


## Wind-up tell before a lunge / throw.
func play_windup() -> void:
	_windup = 0.0


func play_attack() -> void:
	_windup = -1.0
	_attack = 0.0


## Visual stun indicator (stars / daze).
func set_stunned(stunned: bool) -> void:
	_stunned = stunned
	if stunned and _stars == null and _pivot != null:
		_stars = MeshInstance3D.new()
		_stars.name = "Stars"
		_stars.mesh = MeshKit.cached("enemy:stars", func() -> Mesh: return _stars_mesh())
		_stars.material_override = Mats.glow(Color(1.0, 0.88, 0.25), 1.8)
		_stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_stars)
	if _stars != null:
		_stars.visible = stunned
		_stars.position = Vector3(0, head_height + 0.18, 0)


func is_stunned() -> bool:
	return _stunned


func is_winding_up() -> bool:
	return _windup >= 0.0


func _process(delta: float) -> void:
	if _pivot == null:
		return
	_time += delta
	_speed = lerpf(_speed, 0.0 if _stunned else _speed_target, 1.0 - exp(-10.0 * delta))
	_yaw = lerp_angle(_yaw, _target_yaw, 1.0 - exp(-TURN_SPEED * delta))
	_phase += delta * (4.0 + 9.0 * _speed) * (1.0 if _speed > 0.02 else 0.0)
	var bob := absf(sin(_phase)) * 0.07 * _speed
	var lean := 0.12 * _speed
	var roll := sin(_phase) * 0.1 * _speed
	var arm_x := sin(_phase) * 0.45 * _speed
	var sx := 1.0
	var sy := 1.0
	if _windup >= 0.0:
		_windup += delta
		var w := minf(_windup / 0.25, 1.0)
		lean -= 0.3 * w
		arm_x = lerpf(arm_x, -2.1, w)
		sy = 1.0 - 0.12 * w
		sx = 1.0 + 0.08 * w
		_overlay_dirty = true
		if _windup > MAX_WINDUP:
			_windup = -1.0
	if _attack < 1.0:
		_attack = minf(1.0, _attack + delta / ATTACK_TIME)
		var a := sin(_attack * PI)
		lean += 0.35 * a
		arm_x = lerpf(-2.1, 1.3, smoothstep(0.0, 0.35, _attack)) * (1.0 - smoothstep(0.5, 1.0, _attack)) + arm_x * smoothstep(0.5, 1.0, _attack)
		_overlay_dirty = true
	if _stunned:
		roll = sin(_time * 6.0) * 0.12
		lean = -0.1
		if _stars != null:
			_stars.rotation.y = _time * 5.0
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta / FLASH_TIME)
		_overlay_dirty = true
	_pivot.position = Vector3(0, bob, 0)
	_pivot.rotation = Vector3(-lean, _yaw, roll)
	_pivot.scale = Vector3(sx, sy, sx) * _scale
	_arm.rotation = Vector3(arm_x, 0, 0)
	if _glow != null:
		var f := 1.0 + sin(_time * 19.0 + get_instance_id() % 7) * 0.12
		_glow.scale = Vector3(1.0 / f, f, 1.0 / f)
	if _overlay_dirty:
		_apply_overlay()


func _apply_overlay() -> void:
	_overlay_dirty = false
	if _body == null:
		return
	# Hit flash (white, fading) wins over the wind-up tell (red, pulsing in the shader).
	var state := Vector2i(1, roundi(_flash * 0.9 * Mats.OVERLAY_STEPS))
	if state.y == 0:
		state = Vector2i(2, 5) if _windup >= 0.0 else Vector2i.ZERO
	if state == _overlay_state:
		return
	_overlay_state = state
	var color := WINDUP_COLOR if state.x == 2 else Color.WHITE
	var amount := float(state.y) / Mats.OVERLAY_STEPS
	var pulse := WINDUP_PULSE if state.x == 2 else 0.0
	Mats.set_overlay(_body, color, amount, pulse)
	Mats.set_overlay(_arm, color, amount, pulse)


# --- Mesh building (shared, cached) ------------------------------------------

## Returns { body: Mesh, arm: Mesh, arm_pivot: Vector3, head_y: float, [glow, glow_pos,
## glow_color] } for a style; cached per style + colour.
static func parts_for(p_style: StringName, color: Color) -> Dictionary:
	var key := "enemy:%s:%s" % [p_style, color.to_html()]
	var body := MeshKit.cached(key + ":body", func() -> Mesh: return _build(p_style, color, false))
	var arm := MeshKit.cached(key + ":arm", func() -> Mesh: return _build(p_style, color, true))
	var out := {"body": body, "arm": arm}
	match p_style:
		&"candlekin":
			out["arm_pivot"] = Vector3(0.25, 0.5, -0.02)
			out["head_y"] = 1.0
			out["glow"] = MeshKit.cached("enemy:flame", func() -> Mesh: return _flame_mesh())
			out["glow_pos"] = Vector3(0, 1.07, -0.02)
			out["glow_color"] = Color(1.0, 0.62, 0.18)
		&"gurgler":
			out["arm_pivot"] = Vector3(0.36, 0.52, 0.0)
			out["head_y"] = 0.95
		&"troll":
			out["arm_pivot"] = Vector3(0.27, 1.12, 0.02)
			out["head_y"] = 1.55
		_:
			out["arm_pivot"] = Vector3(0.21, 0.8, 0.0)
			out["head_y"] = 1.24
	return out


static func _build(p_style: StringName, color: Color, arm: bool) -> Mesh:
	var k := MeshKit.new()
	match p_style:
		&"candlekin":
			if arm:
				_candlekin_arm(k, color)
			else:
				_candlekin(k, color)
		&"gurgler":
			if arm:
				_gurgler_arm(k, color)
			else:
				_gurgler(k, color)
		&"troll":
			if arm:
				_troll_arm(k, color)
			else:
				_troll(k, color)
		_:
			if arm:
				_skeleton_arm(k, color)
			else:
				_skeleton(k, color)
	return k.build()


static func _xf(pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Transform3D:
	return MeshKit.xf(pos, rot, scl)


# Skeleton grunt: big skull, rib cage, rusty sword.
static func _skeleton(k: MeshKit, bone: Color) -> void:
	var shade := bone.darkened(0.18)
	k.add_sphere(0.2, _xf(Vector3(0, 1.03, 0), Vector3.ZERO, Vector3(1.0, 0.95, 1.05)), bone, 14, 7)
	k.add_box(Vector3(0.2, 0.08, 0.17), _xf(Vector3(0, 0.87, -0.05), Vector3(-10, 0, 0)), bone)
	for side: float in [-1.0, 1.0]:
		k.add_sphere(0.06, _xf(Vector3(0.08 * side, 1.04, -0.165), Vector3.ZERO, Vector3(1, 1.1, 0.6)), DARK, 8, 4)
		k.add_sphere(0.022, _xf(Vector3(0.08 * side, 1.04, -0.2)), Color(1.0, 0.3, 0.15), 6, 3)
	k.add_sphere(0.025, _xf(Vector3(0, 0.97, -0.195)), DARK, 6, 3)
	for i in 4:
		k.add_box(Vector3(0.035, 0.035, 0.02), _xf(Vector3(-0.06 + i * 0.04, 0.9, -0.14)), WHITE)
	# Cracks on the skull top.
	k.add_box(Vector3(0.018, 0.02, 0.12), _xf(Vector3(0.05, 1.21, 0.02), Vector3(0, 25, 0)), bone.darkened(0.45))
	k.add_box(Vector3(0.016, 0.02, 0.07), _xf(Vector3(0.09, 1.2, -0.05), Vector3(0, -30, 0)), bone.darkened(0.45))
	k.add_segment(Vector3(0, 0.48, 0.02), Vector3(0, 0.86, 0.02), 0.04, 0.035, shade, 6)
	for i in 3:
		var y := 0.62 + i * 0.075
		var r := 0.17 - i * 0.012
		k.add_torus(r - 0.025, r, _xf(Vector3(0, y, -0.01), Vector3(-6, 0, 0), Vector3(1.0, 1.0, 0.8)), bone, 12, 4)
	k.add_box(Vector3(0.05, 0.2, 0.04), _xf(Vector3(0, 0.7, -0.12)), bone)
	k.add_box(Vector3(0.26, 0.09, 0.14), _xf(Vector3(0, 0.48, 0.0)), shade)
	k.add_box(Vector3(0.3, 0.16, 0.05), _xf(Vector3(0, 0.4, -0.08), Vector3(8, 0, 0)), Color(0.42, 0.18, 0.14))
	for side: float in [-1.0, 1.0]:
		var hip := Vector3(0.09 * side, 0.46, 0.0)
		var knee := Vector3(0.11 * side, 0.25, -0.02)
		var foot := Vector3(0.11 * side, 0.04, 0.0)
		k.add_segment(hip, knee, 0.035, 0.03, bone, 6)
		k.add_segment(knee, foot, 0.03, 0.028, bone, 6)
		k.add_sphere(0.045, _xf(knee), shade, 6, 3)
		k.add_box(Vector3(0.09, 0.05, 0.16), _xf(foot + Vector3(0, -0.01, -0.04)), bone)
	# Left arm with a round rusty buckler.
	var sh := Vector3(-0.2, 0.8, 0.0)
	var el := Vector3(-0.26, 0.6, -0.05)
	var ha := Vector3(-0.22, 0.48, -0.14)
	k.add_sphere(0.06, _xf(sh), bone, 8, 4)
	k.add_segment(sh, el, 0.032, 0.028, bone, 6)
	k.add_segment(el, ha, 0.028, 0.025, bone, 6)
	k.add_cylinder(0.15, 0.15, 0.04, _xf(ha + Vector3(-0.04, 0.02, -0.02), Vector3(0, 0, 80)), RUST, 12)
	k.add_sphere(0.04, _xf(ha + Vector3(-0.07, 0.03, -0.02)), IRON, 6, 3)
	# Rusty shoulder pad.
	k.add_sphere(0.1, _xf(Vector3(0.2, 0.82, 0.0), Vector3(0, 0, -30)), RUST, 8, 4, true)


static func _skeleton_arm(k: MeshKit, bone: Color) -> void:
	var el := Vector3(0.03, -0.2, -0.02)
	var ha := Vector3(0.02, -0.33, -0.14)
	k.add_segment(Vector3.ZERO, el, 0.032, 0.028, bone, 6)
	k.add_segment(el, ha, 0.028, 0.025, bone, 6)
	k.add_sphere(0.04, _xf(ha), bone, 6, 3)
	# Rusty notched sword pointing forward.
	var b := Basis.from_euler(Vector3(deg_to_rad(-75), 0, 0))
	var t := Transform3D(b, ha)
	k.add_box(Vector3(0.16, 0.03, 0.05), t * _xf(Vector3(0, 0.05, 0)), IRON)
	k.add_cylinder(0.02, 0.02, 0.1, t * _xf(Vector3(0, -0.02, 0)), WOOD, 6)
	var blade := PackedVector2Array([Vector2(-0.04, 0.06), Vector2(0.04, 0.06), Vector2(0.045, 0.3),
		Vector2(0.02, 0.33), Vector2(0.04, 0.38), Vector2(0.0, 0.52), Vector2(-0.035, 0.42), Vector2(-0.04, 0.2)])
	k.add_extrusion(blade, 0.022, t, RUST.lightened(0.1), 0.8)


# Candlekin: small mole-like miner with a candle on its head.
static func _candlekin(k: MeshKit, fur: Color) -> void:
	var belly := fur.lerp(Color(0.95, 0.85, 0.65), 0.5)
	k.add_sphere(0.3, _xf(Vector3(0, 0.4, 0), Vector3.ZERO, Vector3(1.0, 1.08, 0.95)), fur, 14, 7)
	k.add_sphere(0.22, _xf(Vector3(0, 0.36, -0.12), Vector3.ZERO, Vector3(1.0, 1.1, 0.7)), belly, 12, 6)
	k.add_sphere(0.23, _xf(Vector3(0, 0.74, -0.04)), fur, 14, 7)
	k.add_sphere(0.12, _xf(Vector3(0, 0.68, -0.25), Vector3(-10, 0, 0), Vector3(0.9, 0.8, 1.3)), fur.lightened(0.1), 10, 5)
	k.add_sphere(0.05, _xf(Vector3(0, 0.7, -0.4)), Color(0.95, 0.5, 0.55), 8, 4)
	for side: float in [-1.0, 1.0]:
		k.add_sphere(0.035, _xf(Vector3(0.09 * side, 0.8, -0.2)), DARK, 6, 3)
		k.add_sphere(0.012, _xf(Vector3(0.095 * side, 0.81, -0.232)), WHITE, 4, 2)
		k.add_sphere(0.07, _xf(Vector3(0.2 * side, 0.86, -0.0), Vector3.ZERO, Vector3(1.0, 1.0, 0.45)), fur.darkened(0.15), 8, 4)
		k.add_sphere(0.09, _xf(Vector3(0.13 * side, 0.06, -0.06), Vector3.ZERO, Vector3(1.0, 0.6, 1.3)), fur.darkened(0.25), 8, 4)
		k.add_box(Vector3(0.025, 0.04, 0.012), _xf(Vector3(0.018 * side, 0.6, -0.33)), WHITE)
	# Miner helmet + candle.
	k.add_sphere(0.21, _xf(Vector3(0, 0.82, -0.02), Vector3(-6, 0, 0)), Color(0.95, 0.75, 0.2), 12, 5, true)
	k.add_torus(0.2, 0.25, _xf(Vector3(0, 0.83, -0.02), Vector3(-6, 0, 0), Vector3(1, 0.5, 1)), Color(0.75, 0.55, 0.15), 14, 4)
	k.add_cylinder(0.055, 0.06, 0.16, _xf(Vector3(0, 1.0, -0.02)), Color(0.98, 0.95, 0.85), 10)
	k.add_sphere(0.03, _xf(Vector3(0.05, 1.04, -0.05)), Color(0.98, 0.95, 0.85), 6, 3)
	k.add_cylinder(0.006, 0.006, 0.04, _xf(Vector3(0, 1.09, -0.02)), DARK, 4)
	# Tail and the other paw.
	k.add_tube(PackedVector3Array([Vector3(0, 0.25, 0.25), Vector3(0, 0.18, 0.42), Vector3(0.05, 0.22, 0.55)]), 0.035, 0.012, fur.darkened(0.2), 6)
	k.add_sphere(0.075, _xf(Vector3(-0.27, 0.42, -0.08)), fur.lightened(0.05), 8, 4)


static func _candlekin_arm(k: MeshKit, fur: Color) -> void:
	var hand := Vector3(0.02, -0.12, -0.1)
	k.add_segment(Vector3.ZERO, hand, 0.06, 0.055, fur, 8)
	k.add_sphere(0.075, _xf(hand), fur.lightened(0.05), 8, 4)
	# Tiny pickaxe.
	var b := Basis.from_euler(Vector3(deg_to_rad(-60), 0, 0))
	var t := Transform3D(b, hand)
	k.add_cylinder(0.02, 0.02, 0.4, t * _xf(Vector3(0, 0.12, 0)), WOOD, 6)
	var head := PackedVector3Array([t * Vector3(0, 0.27, 0.15), t * Vector3(0, 0.32, 0.0), t * Vector3(0, 0.27, -0.15)])
	k.add_tube(head, 0.03, 0.008, IRON, 6)


# Marsh gurgler: round fishman with a huge mouth, bulging eyes and fins.
static func _gurgler(k: MeshKit, skin: Color) -> void:
	var belly := skin.lerp(Color(0.92, 0.9, 0.7), 0.55)
	var fin := Color(0.95, 0.5, 0.3)
	k.add_sphere(0.38, _xf(Vector3(0, 0.5, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.92)), skin, 16, 8)
	k.add_sphere(0.28, _xf(Vector3(0, 0.42, -0.16), Vector3.ZERO, Vector3(1.0, 1.05, 0.65)), belly, 14, 7)
	for i in 5:
		var a := deg_to_rad(120.0 + i * 30.0)
		k.add_sphere(0.05, _xf(Vector3(sin(a) * 0.3, 0.62 + (i % 2) * 0.1, -cos(a) * 0.3), Vector3.ZERO, Vector3(1, 1, 0.4)), skin.darkened(0.25), 6, 3)
	# Big mouth with teeth.
	k.add_sphere(0.24, _xf(Vector3(0, 0.5, -0.29), Vector3.ZERO, Vector3(1.0, 0.36, 0.3)), Color(0.4, 0.06, 0.1), 14, 6)
	k.add_sphere(0.17, _xf(Vector3(0, 0.47, -0.33), Vector3.ZERO, Vector3(1.0, 0.25, 0.2)), Color(0.85, 0.3, 0.35), 10, 4)
	for i in 6:
		var x := -0.17 + i * 0.068
		k.add_cylinder(0.0, 0.018, 0.05, _xf(Vector3(x, 0.55, -0.335 + absf(x) * 0.25), Vector3(180, 0, 0)), WHITE, 5)
	# Bulging eyes on top.
	for side: float in [-1.0, 1.0]:
		k.add_sphere(0.1, _xf(Vector3(0.15 * side, 0.82, -0.17)), Color(1.0, 0.86, 0.3), 12, 6)
		k.add_sphere(0.05, _xf(Vector3(0.155 * side, 0.83, -0.255), Vector3.ZERO, Vector3(0.7, 1.3, 0.5)), DARK, 8, 4)
		var side_fin := PackedVector2Array([Vector2(0, 0), Vector2(0.18, 0.12), Vector2(0.2, -0.02), Vector2(0.14, -0.1)])
		k.add_extrusion(side_fin, 0.025, _xf(Vector3(0.33 * side, 0.68, 0.05), Vector3(0, 90.0 - 90.0 * side, 20.0 * side)), fin, 0.9)
		k.add_sphere(0.1, _xf(Vector3(0.15 * side, 0.08, -0.04), Vector3.ZERO, Vector3(1.0, 0.45, 1.4)), skin.darkened(0.1), 8, 4)
		k.add_segment(Vector3(0.15 * side, 0.25, 0.0), Vector3(0.15 * side, 0.08, -0.02), 0.06, 0.05, skin, 6)
	var crest := PackedVector2Array([Vector2(-0.25, 0.0), Vector2(-0.18, 0.2), Vector2(-0.05, 0.12),
		Vector2(0.05, 0.24), Vector2(0.15, 0.12), Vector2(0.28, 0.16), Vector2(0.3, 0.0)])
	k.add_extrusion(crest, 0.03, _xf(Vector3(0, 0.82, 0.08), Vector3(0, 90, 0)), fin, 0.9)
	k.add_sphere(0.08, _xf(Vector3(-0.37, 0.48, -0.06)), skin, 8, 4)


static func _gurgler_arm(k: MeshKit, skin: Color) -> void:
	var hand := Vector3(0.04, -0.16, -0.12)
	k.add_segment(Vector3.ZERO, hand, 0.06, 0.05, skin, 8)
	k.add_sphere(0.075, _xf(hand), skin.lightened(0.05), 8, 4)
	for i in 3:
		var a := deg_to_rad(-30.0 + i * 30.0)
		var claw := hand + Vector3(sin(a) * 0.05, -0.02, -0.06)
		k.add_segment(claw, claw + Vector3(sin(a) * 0.04, -0.03, -0.07), 0.018, 0.0, WHITE, 5)


# Troll: tall, lanky, tusks, mohawk, throwing axe.
static func _troll(k: MeshKit, skin: Color) -> void:
	var hair := Color(0.9, 0.22, 0.15)
	var cloth := Color(0.55, 0.3, 0.16)
	k.add_capsule(0.21, 0.6, Transform3D(MeshKit.basis_from_y(Vector3(0, 1.0, -0.25)), Vector3(0, 0.95, -0.04)), skin, 12, 4)
	k.add_sphere(0.25, _xf(Vector3(0, 1.12, -0.08), Vector3.ZERO, Vector3(1.15, 0.85, 0.9)), skin, 12, 6)
	k.add_sphere(0.16, _xf(Vector3(0, 0.9, -0.14)), skin.lightened(0.12), 10, 5)
	# Head: low and forward.
	var head := Vector3(0, 1.32, -0.24)
	k.add_sphere(0.17, _xf(head, Vector3.ZERO, Vector3(1.0, 0.95, 1.05)), skin, 14, 7)
	k.add_sphere(0.13, _xf(head + Vector3(0, -0.08, -0.08), Vector3.ZERO, Vector3(1.1, 0.7, 1.1)), skin.darkened(0.08), 10, 5)
	k.add_segment(head + Vector3(0, 0.0, -0.14), head + Vector3(0, -0.07, -0.3), 0.055, 0.02, skin.lightened(0.05), 8)
	for side: float in [-1.0, 1.0]:
		k.add_segment(head + Vector3(0.12 * side, 0.03, 0.0), head + Vector3(0.36 * side, 0.12, 0.08), 0.06, 0.0, skin, 6)
		k.add_sphere(0.03, _xf(head + Vector3(0.07 * side, 0.04, -0.15)), Color(1.0, 0.85, 0.2), 6, 3)
		k.add_segment(head + Vector3(0.08 * side, -0.12, -0.15), head + Vector3(0.11 * side, 0.02, -0.24), 0.028, 0.0, WHITE, 6)
	for i in 5:
		var z := -0.12 + i * 0.07
		var h := 0.16 - absf(i - 1.5) * 0.025
		k.add_cylinder(0.0, 0.05, h, _xf(head + Vector3(0, 0.16 + h * 0.4, z), Vector3(-10.0 + i * 12.0, 0, 0), Vector3(0.45, 1.0, 1.0)), hair, 6)
	# Loincloth and belt.
	k.add_torus(0.15, 0.2, _xf(Vector3(0, 0.72, 0.0), Vector3.ZERO, Vector3(1.0, 0.7, 0.9)), cloth.darkened(0.3), 12, 4)
	k.add_box(Vector3(0.24, 0.26, 0.04), _xf(Vector3(0, 0.58, -0.14), Vector3(6, 0, 0)), cloth)
	k.add_box(Vector3(0.24, 0.22, 0.04), _xf(Vector3(0, 0.6, 0.15), Vector3(-6, 0, 0)), cloth.darkened(0.1))
	for i in 5:
		k.add_cylinder(0.0, 0.016, 0.05, _xf(Vector3(-0.12 + i * 0.06, 1.0, -0.24), Vector3(180, 0, 0)), WHITE, 4)
	# Long legs with big feet.
	for side: float in [-1.0, 1.0]:
		var hip := Vector3(0.12 * side, 0.72, 0.0)
		var knee := Vector3(0.16 * side, 0.4, -0.08)
		var foot := Vector3(0.15 * side, 0.05, 0.0)
		k.add_segment(hip, knee, 0.07, 0.055, skin, 8)
		k.add_segment(knee, foot, 0.055, 0.045, skin, 8)
		k.add_sphere(0.1, _xf(foot + Vector3(0, -0.01, -0.06), Vector3.ZERO, Vector3(0.9, 0.5, 1.5)), skin.darkened(0.12), 8, 4)
	# Dangling left arm.
	var sh := Vector3(-0.27, 1.12, 0.02)
	var el := Vector3(-0.36, 0.84, -0.05)
	var ha := Vector3(-0.33, 0.56, -0.1)
	k.add_sphere(0.09, _xf(sh), skin, 8, 4)
	k.add_segment(sh, el, 0.06, 0.05, skin, 8)
	k.add_segment(el, ha, 0.05, 0.045, skin, 8)
	k.add_sphere(0.08, _xf(ha), skin.darkened(0.05), 8, 4)
	k.add_sphere(0.11, _xf(Vector3(0.27, 1.16, 0.02), Vector3(0, 0, -25)), Color(0.9, 0.86, 0.75), 8, 4, true)


static func _troll_arm(k: MeshKit, skin: Color) -> void:
	var el := Vector3(0.06, -0.28, -0.06)
	var ha := Vector3(0.05, -0.52, -0.16)
	k.add_sphere(0.085, _xf(Vector3.ZERO), skin, 8, 4)
	k.add_segment(Vector3.ZERO, el, 0.06, 0.05, skin, 8)
	k.add_segment(el, ha, 0.05, 0.045, skin, 8)
	k.add_sphere(0.075, _xf(ha), skin.darkened(0.05), 8, 4)
	var b := Basis.from_euler(Vector3(deg_to_rad(-70), 0, 0))
	var t := Transform3D(b, ha)
	k.add_cylinder(0.03, 0.03, 0.66, t * _xf(Vector3(0, 0.18, 0)), WOOD, 6)
	# Big bearded throwing-axe head with a bright edge and a back spike.
	var blade := PackedVector2Array([Vector2(0.02, 0.32), Vector2(0.12, 0.27), Vector2(0.2, 0.22),
		Vector2(0.3, 0.26), Vector2(0.34, 0.38), Vector2(0.32, 0.5), Vector2(0.24, 0.58),
		Vector2(0.14, 0.55), Vector2(0.02, 0.5)])
	k.add_extrusion(blade, 0.035, t, Color(0.66, 0.68, 0.72), 0.82)
	var edge := PackedVector2Array([Vector2(0.27, 0.25), Vector2(0.31, 0.26), Vector2(0.355, 0.38),
		Vector2(0.335, 0.51), Vector2(0.25, 0.59), Vector2(0.23, 0.56), Vector2(0.3, 0.49), Vector2(0.32, 0.38)])
	k.add_extrusion(edge, 0.04, t, Color(0.9, 0.92, 0.95), 0.8)
	var spike := PackedVector2Array([Vector2(-0.02, 0.36), Vector2(-0.16, 0.42), Vector2(-0.02, 0.47)])
	k.add_extrusion(spike, 0.03, t, Color(0.55, 0.56, 0.6), 0.8)
	k.add_box(Vector3(0.07, 0.24, 0.06), t * _xf(Vector3(0.0, 0.42, 0)), Color(0.35, 0.33, 0.35))
	for i in 2:
		k.add_torus(0.028, 0.045, t * _xf(Vector3(0, -0.02 + i * 0.09, 0)), Color(0.85, 0.25, 0.2), 8, 4)


static func _flame_mesh() -> Mesh:
	var k := MeshKit.new()
	k.add_sphere(0.075, _xf(Vector3(0, 0.05, 0), Vector3.ZERO, Vector3(1.0, 1.1, 1.0)), Color.WHITE, 10, 5)
	k.add_cylinder(0.0, 0.07, 0.19, _xf(Vector3(0, 0.16, 0)), Color.WHITE, 10)
	return k.build()


static func _stars_mesh() -> Mesh:
	var k := MeshKit.new()
	var star := PackedVector2Array()
	for i in 10:
		var a := TAU * i / 10.0
		var r := 0.09 if i % 2 == 0 else 0.04
		star.append(Vector2(sin(a), cos(a)) * r)
	for i in 3:
		var a := TAU * i / 3.0
		k.add_extrusion(star, 0.025, _xf(Vector3(sin(a) * 0.25, 0.04 * (i % 2), cos(a) * 0.25), Vector3(0, rad_to_deg(a), 0)), Color.WHITE)
	return k.build()
