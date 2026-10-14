class_name BossModel
extends EnemyModel
## The look of the two bosses (M6, GDD 8 "Bossok"), procedural like every enemy: a big skeleton
## mage with an icy crown and a staff (style &"lich", Lich Commander Morvain) and a horned fire
## demon with wings and a flaming greatsword (&"demon", Vor'thalax, the Burning Tyrant).
##
## Same contract as [EnemyModel] (it is one): Origin at the feet, faces -Z, scaled by
## data.model_scale; Pivot -> Body, Arm (the weapon arm, swung by the attack / wind-up
## animation) and one Glow part (eyes and crown fire, pulsing). [method setup] builds the
## parts from [method boss_parts] instead of EnemyModel.parts_for; everything else (animation,
## hit flash, stun stars) is inherited. Meshes are cached per style + colour like the others.

const BOSS_STYLES: Array[StringName] = [&"lich", &"demon"]

## Lich palette.
const ROBE := Color(0.16, 0.14, 0.34)
const ROBE_DARK := Color(0.09, 0.08, 0.2)
const ICE := Color(0.55, 0.86, 1.0)
const ICE_PALE := Color(0.84, 0.96, 1.0)
const STAFF_WOOD := Color(0.24, 0.2, 0.26)
## Demon palette.
const SKIN := Color(0.52, 0.12, 0.1)
const SKIN_DARK := Color(0.3, 0.07, 0.07)
const IRON_DARK := Color(0.16, 0.14, 0.16)
const HORN := Color(0.86, 0.8, 0.66)
const LAVA := Color(1.0, 0.55, 0.12)
const LAVA_BRIGHT := Color(1.0, 0.85, 0.35)


func setup(p_data: EnemyData) -> void:
	data = p_data
	style = data.model_style if data != null and data.model_style in BOSS_STYLES else &"lich"
	_scale = data.model_scale if data != null else 1.0
	var color := data.color if data != null else BONE
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_stars = null
	_overlay_state = Vector2i.ZERO
	var parts := boss_parts(style, color)
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


## { body, arm, arm_pivot, head_y, glow, glow_pos, glow_color } of [param p_style] tinted with
## [param color] (the lich's bone / the demon's skin), cached per style + colour.
static func boss_parts(p_style: StringName, color: Color) -> Dictionary:
	var key := "boss:%s:%s" % [p_style, color.to_html()]
	var body := MeshKit.cached(key + ":body", func() -> Mesh: return _build(p_style, color, false))
	var arm := MeshKit.cached(key + ":arm", func() -> Mesh: return _build(p_style, color, true))
	var out := {"body": body, "arm": arm}
	if p_style == &"demon":
		out["arm_pivot"] = Vector3(0.52, 1.28, 0.0)
		out["head_y"] = 2.3
		out["glow"] = MeshKit.cached(key + ":glow", func() -> Mesh: return _demon_glow())
		out["glow_pos"] = Vector3(0.0, 1.78, -0.12)
		out["glow_color"] = Color(1.0, 0.55, 0.14)
	else:
		out["arm_pivot"] = Vector3(0.3, 1.18, 0.0)
		out["head_y"] = 1.78
		out["glow"] = MeshKit.cached(key + ":glow", func() -> Mesh: return _lich_glow())
		out["glow_pos"] = Vector3(0.0, 1.46, -0.06)
		out["glow_color"] = Color(0.5, 0.88, 1.0)
	return out


static func _build(p_style: StringName, color: Color, arm: bool) -> Mesh:
	var k := MeshKit.new()
	if p_style == &"demon":
		if arm:
			_demon_arm(k, color)
		else:
			_demon(k, color)
	else:
		if arm:
			_lich_arm(k, color)
		else:
			_lich(k, color)
	return k.build()


# --- Lich Commander Morvain --------------------------------------------------------------

static func _lich(k: MeshKit, bone: Color) -> void:
	var shade := bone.darkened(0.2)
	# Tattered robe: a wide cone and a hem of hanging rags.
	k.add_cylinder(0.2, 0.46, 0.95, _xf(Vector3(0, 0.5, 0.0)), ROBE, 14)
	k.add_cylinder(0.27, 0.2, 0.22, _xf(Vector3(0, 1.02, 0.0)), ROBE_DARK, 12)
	for i in 11:
		var a := TAU * float(i) / 11.0
		var len := 0.2 + 0.1 * float(i % 3)
		var at := Vector3(sin(a) * 0.43, 0.1, cos(a) * 0.43)
		k.add_cylinder(0.0, 0.07, len, _xf(at, Vector3(0, rad_to_deg(a), 0)), ROBE_DARK if i % 2 == 0 else ROBE, 5)
	# Ice belt and a frozen sash.
	k.add_torus(0.19, 0.25, _xf(Vector3(0, 0.98, 0.0)), ICE, 14, 5)
	k.add_box(Vector3(0.09, 0.4, 0.03), _xf(Vector3(0.0, 0.76, -0.22), Vector3(-6, 0, 0)), ICE.darkened(0.3))
	# Ribcage showing in the open robe, spine and collar.
	for i in 4:
		var y := 1.08 + 0.075 * float(i)
		var r := 0.2 - 0.014 * float(i)
		k.add_torus(r - 0.025, r, _xf(Vector3(0, y, -0.01), Vector3(-6, 0, 0), Vector3(1.0, 1.0, 0.8)), bone, 12, 4)
	k.add_box(Vector3(0.05, 0.3, 0.04), _xf(Vector3(0, 1.17, -0.15)), bone)
	k.add_segment(Vector3(0, 1.0, 0.04), Vector3(0, 1.36, 0.0), 0.04, 0.035, shade, 6)
	# Spiked ice pauldrons.
	for side: float in [-1.0, 1.0]:
		var sh := Vector3(0.3 * side, 1.3, 0.0)
		k.add_sphere(0.13, _xf(sh, Vector3.ZERO, Vector3(1.0, 0.7, 1.0)), ROBE, 10, 5)
		for j in 3:
			var tilt := (-35.0 + 35.0 * float(j)) * side
			k.add_cylinder(0.0, 0.04, 0.24 - 0.04 * float(j), _xf(sh + Vector3(0.05 * side * float(j), 0.1, 0.0), Vector3(0, 0, -tilt)), ICE, 5)
	# Cloak hanging behind.
	var cloak := PackedVector2Array([Vector2(-0.3, 1.3), Vector2(0.3, 1.3), Vector2(0.46, 0.05), Vector2(0.2, 0.18),
		Vector2(0.0, 0.0), Vector2(-0.2, 0.18), Vector2(-0.46, 0.05)])
	k.add_extrusion(cloak, 0.03, _xf(Vector3(0, 0.0, 0.22), Vector3(-4, 0, 0)), ROBE_DARK, 0.9)
	# Skull: big, with a jaw, eye sockets and teeth.
	var head := Vector3(0, 1.45, -0.04)
	k.add_sphere(0.19, _xf(head, Vector3.ZERO, Vector3(1.0, 1.0, 1.05)), bone, 14, 7)
	k.add_box(Vector3(0.2, 0.08, 0.17), _xf(head + Vector3(0, -0.15, -0.04), Vector3(-10, 0, 0)), bone)
	for side: float in [-1.0, 1.0]:
		k.add_sphere(0.06, _xf(head + Vector3(0.08 * side, 0.02, -0.16), Vector3.ZERO, Vector3(1, 1.15, 0.6)), DARK, 8, 4)
	k.add_sphere(0.028, _xf(head + Vector3(0, -0.05, -0.2)), DARK, 6, 3)
	for i in 5:
		k.add_box(Vector3(0.03, 0.035, 0.02), _xf(head + Vector3(-0.06 + 0.03 * float(i), -0.12, -0.2)), WHITE)
	# Icy crown: a band, a ring of spikes, taller ones at the front and the sides.
	k.add_torus(0.17, 0.21, _xf(head + Vector3(0, 0.15, 0.0)), ICE.darkened(0.15), 14, 4)
	for i in 9:
		var a := TAU * float(i) / 9.0
		var tall := 0.2 + 0.1 * float(i % 3 == 0)
		k.add_cylinder(0.0, 0.034, tall, _xf(head + Vector3(sin(a) * 0.19, 0.15 + tall * 0.5, cos(a) * 0.19),
				Vector3(-rad_to_deg(cos(a)) * 0.12, 0, rad_to_deg(sin(a)) * 0.12)), ICE_PALE if i % 3 == 0 else ICE, 5)
	k.add_sphere(0.04, _xf(head + Vector3(0, 0.17, -0.2)), ICE_PALE, 8, 4)
	# The off hand: bony fingers curled around a floating frost shard.
	var sh := Vector3(-0.3, 1.26, 0.0)
	var el := Vector3(-0.38, 1.04, -0.1)
	var ha := Vector3(-0.3, 0.9, -0.3)
	k.add_sphere(0.05, _xf(sh), bone, 8, 4)
	k.add_segment(sh, el, 0.03, 0.026, bone, 6)
	k.add_segment(el, ha, 0.026, 0.024, bone, 6)
	k.add_sphere(0.045, _xf(ha), bone, 8, 4)
	for i in 3:
		k.add_segment(ha, ha + Vector3(-0.03 + 0.03 * float(i), 0.02, -0.1), 0.014, 0.0, bone, 4)
	k.add_cylinder(0.0, 0.06, 0.26, _xf(ha + Vector3(0.0, 0.2, -0.05), Vector3(180, 0, 0)), ICE, 5)


static func _lich_arm(k: MeshKit, bone: Color) -> void:
	var el := Vector3(0.04, -0.2, -0.08)
	var ha := Vector3(0.02, -0.34, -0.22)
	k.add_sphere(0.05, _xf(Vector3.ZERO), bone, 8, 4)
	k.add_segment(Vector3.ZERO, el, 0.03, 0.026, bone, 6)
	k.add_segment(el, ha, 0.026, 0.024, bone, 6)
	k.add_sphere(0.045, _xf(ha), bone, 8, 4)
	# The staff: a long dark shaft through the fist, a claw of ice crystals around a frost orb.
	var from := ha + Vector3(0, -0.55, 0.05)
	var to := ha + Vector3(0, 1.0, -0.05)
	k.add_segment(from, to, 0.032, 0.028, STAFF_WOOD, 7)
	k.add_torus(0.03, 0.055, _xf(ha + Vector3(0, 0.3, -0.01)), ICE.darkened(0.3), 8, 4)
	var top := to + Vector3(0, 0.05, 0.0)
	k.add_sphere(0.11, _xf(top + Vector3(0, 0.12, 0)), ICE_PALE, 12, 6)
	for i in 5:
		var a := TAU * float(i) / 5.0
		k.add_cylinder(0.0, 0.035, 0.3, _xf(top + Vector3(sin(a) * 0.12, 0.1, cos(a) * 0.12),
				Vector3(rad_to_deg(cos(a)) * 18.0, 0, -rad_to_deg(sin(a)) * 18.0)), ICE, 5)
	k.add_cylinder(0.0, 0.04, 0.24, _xf(top + Vector3(0, 0.45, 0)), ICE_PALE, 5)


## The lich's eyes, the crown's front gem and a ring of frost motes around the crown.
static func _lich_glow() -> Mesh:
	var k := MeshKit.new()
	for side: float in [-1.0, 1.0]:
		k.add_sphere(0.034, _xf(Vector3(0.08 * side, 0.0, -0.17)), Color.WHITE, 8, 4)
	k.add_sphere(0.045, _xf(Vector3(0, 0.15, -0.2)), Color.WHITE, 8, 4)
	for i in 5:
		var a := TAU * float(i) / 5.0 + 0.3
		k.add_sphere(0.026, _xf(Vector3(sin(a) * 0.36, 0.34 + 0.06 * float(i % 2), cos(a) * 0.36)), Color.WHITE, 6, 3)
	return k.build()


# --- Vor'thalax, the Burning Tyrant -------------------------------------------------------

static func _demon(k: MeshKit, skin: Color) -> void:
	var dark := skin.darkened(0.35)
	# Hooved digitigrade legs.
	for side: float in [-1.0, 1.0]:
		var hip := Vector3(0.2 * side, 0.92, 0.0)
		var knee := Vector3(0.27 * side, 0.58, -0.14)
		var heel := Vector3(0.25 * side, 0.3, 0.12)
		var hoof := Vector3(0.25 * side, 0.05, -0.08)
		k.add_segment(hip, knee, 0.15, 0.1, skin, 8)
		k.add_segment(knee, heel, 0.1, 0.07, skin, 8)
		k.add_segment(heel, hoof, 0.07, 0.06, dark, 8)
		k.add_sphere(0.1, _xf(hoof + Vector3(0, -0.01, -0.06), Vector3.ZERO, Vector3(1.0, 0.55, 1.5)), IRON_DARK, 8, 4)
	# Loincloth of scorched plates and a lava belt.
	k.add_box(Vector3(0.34, 0.34, 0.05), _xf(Vector3(0, 0.78, -0.27), Vector3(6, 0, 0)), IRON_DARK)
	k.add_box(Vector3(0.34, 0.3, 0.05), _xf(Vector3(0, 0.8, 0.27), Vector3(-6, 0, 0)), IRON_DARK)
	k.add_torus(0.3, 0.38, _xf(Vector3(0, 0.98, 0.0), Vector3.ZERO, Vector3(1.0, 1.0, 0.8)), LAVA.darkened(0.2), 14, 5)
	# Broad chest with a glowing cracked core, belly, collar.
	k.add_sphere(0.34, _xf(Vector3(0, 1.1, 0.0), Vector3.ZERO, Vector3(1.0, 0.8, 0.78)), skin, 14, 7)
	k.add_sphere(0.5, _xf(Vector3(0, 1.38, 0.0), Vector3.ZERO, Vector3(1.0, 0.6, 0.62)), skin.lightened(0.05), 16, 8)
	k.add_sphere(0.2, _xf(Vector3(0, 1.32, -0.2), Vector3.ZERO, Vector3(1.0, 1.0, 0.5)), LAVA_BRIGHT, 10, 5)
	for i in 6:
		var a := deg_to_rad(float(i) * 60.0 + 15.0)
		k.add_segment(Vector3(cos(a) * 0.09, 1.32 + sin(a) * 0.09, -0.27),
				Vector3(cos(a) * 0.3, 1.32 + sin(a) * 0.28, -0.24), 0.018, 0.008, LAVA, 4)
	for i in 3:
		k.add_box(Vector3(0.28 - 0.04 * float(i), 0.04, 0.06), _xf(Vector3(0, 1.0 - 0.09 * float(i), -0.26)), skin.darkened(0.25))
	# Spiked iron pauldrons.
	for side: float in [-1.0, 1.0]:
		var sh := Vector3(0.56 * side, 1.5, 0.0)
		k.add_sphere(0.22, _xf(sh, Vector3.ZERO, Vector3(1.0, 0.85, 1.0)), IRON_DARK, 12, 6)
		for j in 3:
			k.add_cylinder(0.0, 0.05, 0.3 - 0.05 * float(j), _xf(sh + Vector3(0.04 * side * float(j), 0.2, -0.05 + 0.05 * float(j)),
					Vector3(0, 0, -side * (30.0 + 25.0 * float(j)))), LAVA.darkened(0.3), 5)
	# Head: heavy brow, snout, fangs, great curved horns.
	var head := Vector3(0, 1.78, -0.1)
	k.add_segment(Vector3(0, 1.58, -0.04), head, 0.12, 0.1, skin, 7)
	k.add_sphere(0.21, _xf(head, Vector3.ZERO, Vector3(1.0, 1.0, 1.05)), skin, 14, 7)
	k.add_sphere(0.14, _xf(head + Vector3(0, -0.1, -0.12), Vector3.ZERO, Vector3(1.1, 0.7, 1.1)), skin.darkened(0.08), 10, 5)
	k.add_box(Vector3(0.36, 0.06, 0.1), _xf(head + Vector3(0, 0.07, -0.16), Vector3(14, 0, 0)), dark)
	for side: float in [-1.0, 1.0]:
		k.add_segment(head + Vector3(0.07 * side, -0.16, -0.2), head + Vector3(0.09 * side, -0.07, -0.22), 0.03, 0.0, HORN.lightened(0.1), 5)
		var horn := PackedVector3Array([head + Vector3(0.14 * side, 0.1, -0.04), head + Vector3(0.36 * side, 0.12, -0.06),
				head + Vector3(0.5 * side, 0.34, -0.12), head + Vector3(0.46 * side, 0.6, -0.2)])
		k.add_tube(horn, 0.075, 0.012, HORN, 7)
		k.add_segment(head + Vector3(0.2 * side, 0.02, 0.05), head + Vector3(0.36 * side, -0.02, 0.2), 0.05, 0.0, HORN.darkened(0.15), 5)
	# Wings: bone struts and dark membranes.
	for side: float in [-1.0, 1.0]:
		var root := Vector3(0.3 * side, 1.46, 0.28)
		var elbow := Vector3(0.95 * side, 2.0, 0.42)
		var tip := Vector3(1.55 * side, 1.78, 0.55)
		k.add_segment(root, elbow, 0.05, 0.035, dark, 6)
		k.add_segment(elbow, tip, 0.035, 0.012, dark, 6)
		k.add_segment(elbow, Vector3(1.28 * side, 1.02, 0.5), 0.025, 0.01, dark, 5)
		k.add_segment(elbow, Vector3(0.7 * side, 0.92, 0.42), 0.025, 0.01, dark, 5)
		var membrane := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.65, 0.54), Vector2(1.25, 0.32), Vector2(1.0, -0.02),
				Vector2(1.04, -0.5), Vector2(0.62, -0.38), Vector2(0.4, -0.54), Vector2(0.2, -0.3)])
		var flip := Vector3(side, 1.0, 1.0)
		k.add_extrusion(membrane, 0.012, _xf(root + Vector3(0, 0, 0.0), Vector3(0, 0, 0), flip), SKIN_DARK.lightened(0.04), 0.9)
	# Tail with a burning tip.
	k.add_tube(PackedVector3Array([Vector3(0, 0.95, 0.2), Vector3(0, 0.55, 0.62), Vector3(0.1, 0.35, 1.0), Vector3(0.0, 0.6, 1.3)]),
			0.07, 0.015, skin, 6)
	k.add_sphere(0.07, _xf(Vector3(0.0, 0.66, 1.34)), LAVA_BRIGHT, 8, 4)
	# The off arm: massive, clawed, hanging.
	var sh := Vector3(-0.52, 1.28, 0.0)
	var el := Vector3(-0.66, 0.92, -0.08)
	var ha := Vector3(-0.6, 0.6, -0.16)
	k.add_sphere(0.14, _xf(sh), skin, 8, 4)
	k.add_segment(sh, el, 0.13, 0.1, skin, 8)
	k.add_segment(el, ha, 0.1, 0.085, skin, 8)
	k.add_sphere(0.11, _xf(ha), dark, 8, 4)
	for i in 3:
		k.add_segment(ha + Vector3(-0.05 + 0.05 * float(i), -0.04, -0.04), ha + Vector3(-0.07 + 0.07 * float(i), -0.16, -0.14), 0.03, 0.0, HORN, 5)


static func _demon_arm(k: MeshKit, skin: Color) -> void:
	var el := Vector3(0.12, -0.38, -0.1)
	var ha := Vector3(0.08, -0.62, -0.22)
	k.add_sphere(0.14, _xf(Vector3.ZERO), skin, 8, 4)
	k.add_segment(Vector3.ZERO, el, 0.13, 0.1, skin, 8)
	k.add_segment(el, ha, 0.1, 0.085, skin, 8)
	k.add_sphere(0.12, _xf(ha), skin.darkened(0.3), 8, 4)
	# A greatsword of black iron with a burning edge, held point forward and up.
	var t := Transform3D(Basis.from_euler(Vector3(deg_to_rad(-62), 0, 0)), ha)
	k.add_cylinder(0.035, 0.035, 0.34, t * _xf(Vector3(0, 0.02, 0)), IRON_DARK, 6)
	k.add_box(Vector3(0.34, 0.05, 0.07), t * _xf(Vector3(0, 0.22, 0)), LAVA.darkened(0.35))
	var blade := PackedVector2Array([Vector2(-0.09, 0.26), Vector2(0.09, 0.26), Vector2(0.11, 1.2), Vector2(0.0, 1.45), Vector2(-0.11, 1.2)])
	k.add_extrusion(blade, 0.04, t, IRON_DARK.lightened(0.08), 0.9)
	var edge := PackedVector2Array([Vector2(-0.03, 0.3), Vector2(0.03, 0.3), Vector2(0.045, 1.18), Vector2(0.0, 1.38), Vector2(-0.045, 1.18)])
	k.add_extrusion(edge, 0.05, t, LAVA, 0.5)
	for i in 4:
		k.add_cylinder(0.0, 0.03, 0.16, t * _xf(Vector3(0.09 + 0.01 * float(i % 2), 0.5 + 0.22 * float(i), 0.0), Vector3(0, 0, -80)), LAVA_BRIGHT, 4)


## Eyes, the flames between the horns and the furnace in the chest.
static func _demon_glow() -> Mesh:
	var k := MeshKit.new()
	for side: float in [-1.0, 1.0]:
		k.add_sphere(0.04, _xf(Vector3(0.09 * side, 0.02, -0.18), Vector3.ZERO, Vector3(1.0, 0.6, 0.7)), Color.WHITE, 8, 4)
		# A flame on every horn tip.
		k.add_cylinder(0.0, 0.07, 0.3, _xf(Vector3(0.46 * side, 0.7, -0.1)), Color.WHITE, 7)
		k.add_sphere(0.06, _xf(Vector3(0.46 * side, 0.64, -0.1)), Color.WHITE, 8, 4)
	# The mane of fire above the brow.
	for i in 5:
		var x := -0.16 + 0.08 * float(i)
		var h := 0.26 - 0.05 * absf(float(i) - 2.0)
		k.add_cylinder(0.0, 0.05, h, _xf(Vector3(x, 0.22 + h * 0.45, 0.02)), Color.WHITE, 6)
	# The furnace: a glowing core in the chest.
	k.add_sphere(0.12, _xf(Vector3(0, -0.46, -0.3), Vector3.ZERO, Vector3(1.0, 1.0, 0.5)), Color.WHITE, 8, 4)
	return k.build()
