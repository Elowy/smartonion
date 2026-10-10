class_name OnionModel
extends Node3D
## Procedural onion hero in WoW-style armour (GDD 13), owned by the "visuals" module.
## Origin is at the feet; total height ~1.3 m (hats a little more); faces -Z by default.
##
## Hierarchy (built by [method setup]):
##   OnionModel
##   ├── Ring / ReviveArea / ReviveArc   ground decals (do not turn)
##   └── Yaw                             turns towards the facing direction
##       ├── Pointer                     small player-coloured arrow on the ring
##       ├── FootL / FootR
##       └── Body                        bob / waddle / squash / ghost float
##           ├── Bulb (lathe mesh, layer stripes, peel shader), Sprout, Roots, Face, Mouth
##           ├── Gear (headgear, pauldrons, belt ...), Cloth (cape / hood / tabard)
##           ├── Peel0..2, TearL / TearR
##           └── HandMain / HandOff  → Grip → weapon model

const HEIGHT := 1.3
const EYE_Y := 0.57
const EYE_X := 0.125
const HAND_POS: Array[Vector3] = [Vector3(0.5, 0.4, -0.1), Vector3(-0.5, 0.4, -0.1)]
const FOOT_POS: Array[Vector3] = [Vector3(-0.15, 0.05, -0.02), Vector3(0.15, 0.05, -0.02)]
## Radius (m) of the revive area ring – keep in sync with Player.REVIVE_RADIUS.
const REVIVE_RING_RADIUS := 1.8
const RING_SIZE := 1.3
const TURN_SPEED := 14.0
const FLASH_TIME := 0.14
const SQUASH_TIME := 0.22
const ATTACK_TIME := 0.24
const PEEL_THRESHOLDS: Array[float] = [0.6, 0.4, 0.2]

const GOLD := Color(0.96, 0.76, 0.3)
const LEATHER := Color(0.4, 0.25, 0.14)
const IVORY := Color(0.94, 0.9, 0.78)
const SPROUT_GREEN := Color(0.38, 0.7, 0.22)
const TABARD_BLUE := Color(0.17, 0.3, 0.68)

## Bulb silhouette: (radius, y) from the root up to the neck.
const BULB_POINTS := [
	Vector2(0.0, 0.1), Vector2(0.12, 0.112), Vector2(0.25, 0.16), Vector2(0.35, 0.25),
	Vector2(0.4, 0.37), Vector2(0.405, 0.46), Vector2(0.38, 0.57), Vector2(0.32, 0.68),
	Vector2(0.23, 0.79), Vector2(0.13, 0.89), Vector2(0.065, 0.96), Vector2(0.035, 1.0),
	Vector2(0.0, 1.03),
]

static var _profile_cache := PackedVector2Array()

var class_data: ClassData
var player_color := Color.WHITE
var hp_ratio := 1.0
var downed := false
var revive_progress := 0.0

var _yaw: Node3D
var _body: Node3D
var _bulb: MeshInstance3D
var _face: Node3D
var _ring: MeshInstance3D
var _pointer: MeshInstance3D
var _revive_area: MeshInstance3D
var _revive_arc: MeshInstance3D
var _hands: Array[Node3D] = []
var _grips: Array[Node3D] = []
var _feet: Array[Node3D] = []
var _peels: Array[Node3D] = []
var _tears: Array[Node3D] = []
var _fel_flame: Node3D
var _weapon_nodes: Array[Node3D] = [null, null]
var _weapon_data: Array[WeaponData] = [null, null]
## Toon-shaded meshes that take the hit flash and the ghost material.
var _skin_meshes: Array[GeometryInstance3D] = []
var _saved_materials: Dictionary[GeometryInstance3D, Material] = {}

var _target_yaw := 0.0
var _speed_target := 0.0
var _speed := 0.0
var _phase := 0.0
var _time := 0.0
var _flash := 0.0
var _squash := 0.0
var _attack_t: Array[float] = [1.0, 1.0]
var _blink := 0.0
var _next_blink := 2.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	name = "OnionModel"
	_rng.seed = get_instance_id()


## Builds the model for [param p_class_data] (onion skin colour, headgear, shoulders,
## accent colour) with a small ring / marker in [param p_player_color] under the feet.
func setup(p_class_data: ClassData, p_player_color: Color) -> void:
	class_data = p_class_data
	player_color = p_player_color
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_hands.clear()
	_grips.clear()
	_feet.clear()
	_peels.clear()
	_tears.clear()
	_skin_meshes.clear()
	_saved_materials.clear()
	_weapon_nodes = [null, null]
	_fel_flame = null
	_build_ground_decals()
	_yaw = _node("Yaw", self)
	_body = _node("Body", _yaw)
	_build_body()
	if class_data != null:
		_build_gear()
	_build_peels()
	_build_tears()
	_build_pointer()
	_yaw.rotation.y = _target_yaw
	set_weapons(_weapon_data[0], _weapon_data[1])
	set_hp_ratio(hp_ratio)
	_apply_downed_look()
	set_revive_progress(revive_progress)


## Shows the weapon models in the hands (null = empty hand).
func set_weapons(main_hand: WeaponData, off_hand: WeaponData) -> void:
	_weapon_data = [main_hand, off_hand]
	if _grips.size() < 2:
		return
	for i in 2:
		if _weapon_nodes[i] != null:
			for mi in _meshes_in(_weapon_nodes[i]):
				_skin_meshes.erase(mi)
			_weapon_nodes[i].queue_free()
			_weapon_nodes[i] = null
		var data := _weapon_data[i]
		if data == null:
			continue
		var w := WeaponModel.build(data)
		_grips[i].add_child(w)
		_grips[i].transform = grip_pose(data.weapon_type, i == 1)
		_weapon_nodes[i] = w
		for mi in _meshes_in(w):
			if mi.name == "Mesh":
				_skin_meshes.append(mi)
		w.visible = not downed
	if _fel_flame != null:
		_fel_flame.visible = _weapon_data[1] == null and not downed


## Smoothly turns the body towards [param direction] (XZ plane).
func set_facing(direction: Vector3) -> void:
	if Vector2(direction.x, direction.z).length_squared() < 0.0001:
		return
	_target_yaw = yaw_for(direction)


## 0 = idle, 1 = full speed. Drives waddle / bob animation.
func set_moving(speed_ratio: float) -> void:
	_speed_target = clampf(speed_ratio, 0.0, 1.0)


## Short swing / thrust animation of one hand.
func play_attack(off_hand: bool) -> void:
	_attack_t[1 if off_hand else 0] = 0.0


## White flash + squash when damaged.
func flash_hit() -> void:
	_flash = 1.0
	_squash = 1.0
	_apply_flash()


## Low HP -> peeled / cracked onion layers (visual HP feedback). [param ratio] = hp / max.
func set_hp_ratio(ratio: float) -> void:
	hp_ratio = clampf(ratio, 0.0, 1.0)
	if _bulb != null:
		_bulb.set_instance_shader_parameter(&"damage", 0.0 if downed else damage_amount(hp_ratio))
	for i in _peels.size():
		_peels[i].visible = not downed and hp_ratio < PEEL_THRESHOLDS[i]


## Downed: translucent crying onion ghost. false restores the normal look.
func set_downed(p_downed: bool) -> void:
	if downed == p_downed:
		return
	downed = p_downed
	_apply_downed_look()
	set_hp_ratio(hp_ratio)
	if not downed:
		set_revive_progress(0.0)


## 0..1 revive progress ring shown while a teammate stands next to a downed player.
func set_revive_progress(progress: float) -> void:
	revive_progress = clampf(progress, 0.0, 1.0)
	if _revive_arc == null:
		return
	_revive_arc.visible = downed and revive_progress > 0.0
	Mats.set_ring(_revive_arc, Color(0.55, 1.0, 0.45, 0.95), 0.86, 0.97, 0.0, revive_progress)


# --- Public helpers ----------------------------------------------------------

## Yaw (radians, around +Y) that makes a -Z facing model look along [param direction].
static func yaw_for(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


## Shader peel amount for an HP ratio: 0 above 75% HP, up to 0.85 at 0 HP.
static func damage_amount(ratio: float) -> float:
	return clampf((0.75 - ratio) / 0.75, 0.0, 1.0) * 0.85


## Smoothed bulb profile (radius, y) from root to neck.
static func bulb_profile() -> PackedVector2Array:
	if _profile_cache.is_empty():
		_profile_cache = MeshKit.smooth_profile(PackedVector2Array(BULB_POINTS), 3)
	return _profile_cache


## Bulb radius at height [param y] (0 outside the bulb).
static func bulb_radius(y: float) -> float:
	var prof := bulb_profile()
	if y <= prof[0].y or y >= prof[prof.size() - 1].y:
		return 0.0
	for i in range(1, prof.size()):
		if prof[i].y >= y:
			var a := prof[i - 1]
			var b := prof[i]
			return lerpf(a.x, b.x, (y - a.y) / maxf(b.y - a.y, 0.0001))
	return 0.0


## Point on the bulb surface at height [param y] and [param angle_deg] (0 = front / -Z,
## 90 = right / +X), pushed out by [param offset] metres.
static func bulb_point(y: float, angle_deg: float, offset: float = 0.0) -> Vector3:
	var r := bulb_radius(y) + offset
	var a := deg_to_rad(angle_deg)
	return Vector3(r * sin(a), y, -r * cos(a))


## Local transform of the weapon grip inside a hand for [param weapon_type].
static func grip_pose(weapon_type: StringName, off_hand: bool) -> Transform3D:
	var side := -1.0 if off_hand else 1.0
	var rot := Vector3(-30, 0, -14 * side)
	var pos := Vector3.ZERO
	match weapon_type:
		&"axe":
			rot = Vector3(-38, 0, -24 * side)
			pos = Vector3(0, -0.04, 0)
		&"staff":
			rot = Vector3(-8, 0, -6 * side)
			pos = Vector3(0, 0.16, 0)
		&"bow":
			rot = Vector3(0, 0, -8 * side)
		&"gun":
			rot = Vector3(-80, 0, 0)
			pos = Vector3(0, 0.02, 0.08)
		&"wand":
			rot = Vector3(-42, 0, -10 * side)
		&"dagger":
			rot = Vector3(-50, 0, -18 * side)
		&"shield":
			rot = Vector3(0, -62.0 * side, 0)
			pos = Vector3(0.05 * side, 0.02, 0)
		&"tome":
			rot = Vector3(-25, -48 * side, 0)
			pos = Vector3(0, 0.2, 0.02)
	return MeshKit.xf(pos, rot)


# --- Animation ---------------------------------------------------------------

func _process(delta: float) -> void:
	if _body == null:
		return
	_time += delta
	_speed = lerpf(_speed, _speed_target, 1.0 - exp(-10.0 * delta))
	_yaw.rotation.y = lerp_angle(_yaw.rotation.y, _target_yaw, 1.0 - exp(-TURN_SPEED * delta))
	if downed:
		_animate_ghost(delta)
	else:
		_animate_alive(delta)
	_animate_hands(delta)
	_animate_blink(delta)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta / FLASH_TIME)
		_apply_flash()
	if _fel_flame != null and _fel_flame.visible:
		var f := 1.0 + sin(_time * 17.0) * 0.08 + sin(_time * 7.3) * 0.06
		_fel_flame.scale = Vector3(1.0 / f, f, 1.0 / f)


func _animate_alive(delta: float) -> void:
	var s := _speed
	_phase += delta * lerpf(0.0, 12.0, s)
	var bob := absf(sin(_phase)) * 0.07 * s
	var breathe := sin(_time * 2.4) * 0.018 * (1.0 - s)
	_squash = maxf(0.0, _squash - delta / SQUASH_TIME)
	var sq := _squash * _squash
	_body.position = Vector3(0, bob, 0)
	_body.rotation = Vector3(-0.14 * s, 0.0, sin(_phase) * 0.13 * s)
	_body.scale = Vector3(1.0 + 0.14 * sq - breathe * 0.5, 1.0 - 0.18 * sq + breathe, 1.0 + 0.14 * sq - breathe * 0.5)
	for i in _feet.size():
		var p := _phase + PI * i
		var foot := _feet[i]
		foot.position = FOOT_POS[i] + Vector3(0, maxf(0.0, cos(p)) * 0.07 * s, sin(p) * 0.1 * s)


func _animate_ghost(_delta: float) -> void:
	_body.position = Vector3(0, 0.28 + sin(_time * 2.0) * 0.06, 0)
	_body.rotation = Vector3(0.0, 0.0, sin(_time * 1.3) * 0.08)
	_body.scale = Vector3.ONE
	for i in _tears.size():
		var t := fmod(_time * 0.9 + 0.45 * i, 1.0)
		var tear := _tears[i]
		var side := -1.0 if i == 0 else 1.0
		var start := bulb_point(EYE_Y - 0.1, 22.0 * side, 0.03)
		tear.position = start + Vector3(0.05 * side * t, -0.32 * t * t - 0.02, -0.04 * t)
		var sc := 1.0 - smoothstep(0.7, 1.0, t)
		tear.scale = Vector3.ONE * maxf(sc, 0.01)


func _animate_hands(delta: float) -> void:
	for i in _hands.size():
		_attack_t[i] = minf(1.0, _attack_t[i] + delta / ATTACK_TIME)
		var side := 1.0 if i == 0 else -1.0
		var p := _phase + PI * i
		var swing := -sin(p) * 0.07 * _speed
		var hover := sin(_time * 3.0 + i * 1.7) * 0.025
		var pos := HAND_POS[i] + Vector3(0, hover, swing)
		var t := _attack_t[i]
		var strike := 0.0
		if t < 1.0:
			strike = smoothstep(0.0, 0.3, t) if t < 0.3 else 1.0 - smoothstep(0.3, 1.0, t)
		var data := _weapon_data[i]
		var ranged := data != null and data.attack_kind == WeaponData.AttackKind.PROJECTILE
		var rot := Vector3.ZERO
		if downed:
			pos = HAND_POS[i] * Vector3(0.85, 1.0, 1.0) + Vector3(0, 0.05 + hover * 2.0, 0.05)
		elif ranged:
			pos += Vector3(0, 0.03, -0.14) * strike
			rot.x = -0.25 * strike
		else:
			pos += Vector3(-0.2 * side, 0.1, -0.3) * strike
			rot = Vector3(-1.5 * strike, 0.0, 0.5 * side * strike)
		_hands[i].position = pos
		_hands[i].rotation = rot


func _animate_blink(delta: float) -> void:
	if _face == null:
		return
	_next_blink -= delta
	if _next_blink <= 0.0:
		_blink = 1.0
		_next_blink = _rng.randf_range(1.8, 4.5)
	if _blink > 0.0:
		_blink = maxf(0.0, _blink - delta / 0.14)
	var closed := sin(_blink * PI)
	if downed:
		closed = maxf(closed, 0.35)
	_face.scale = Vector3(1.0, maxf(0.08, 1.0 - closed), 1.0)


func _apply_flash() -> void:
	for mi in _skin_meshes:
		if is_instance_valid(mi):
			Mats.set_overlay(mi, Color(1, 1, 1), _flash * 0.85)


func _apply_downed_look() -> void:
	if _body == null:
		return
	var ghost_color := Color(0.88, 0.94, 1.0, 0.42)
	if class_data != null:
		var c := class_data.onion_color.lerp(Color(0.92, 0.96, 1.0), 0.6)
		ghost_color = Color(c.r, c.g, c.b, 0.42)
	for mi in _skin_meshes:
		if not is_instance_valid(mi):
			continue
		if downed:
			if not _saved_materials.has(mi):
				_saved_materials[mi] = mi.material_override
			if mi != _face_mesh():
				mi.material_override = Mats.ghost(ghost_color)
		elif _saved_materials.has(mi):
			mi.material_override = _saved_materials[mi]
	if not downed:
		_saved_materials.clear()
	for w in _weapon_nodes:
		if w != null:
			w.visible = not downed
	for f in _feet:
		f.visible = not downed
	for t in _tears:
		t.visible = downed
	if _fel_flame != null:
		_fel_flame.visible = not downed and _weapon_data[1] == null
	_revive_area.visible = downed
	_revive_arc.visible = downed and revive_progress > 0.0
	_ring.visible = not downed
	Mats.set_ring(_ring, Color(player_color.r, player_color.g, player_color.b, 0.95), 0.72, 0.93, 0.16)
	if _pointer != null:
		_pointer.visible = not downed


func _face_mesh() -> GeometryInstance3D:
	return _face.get_node_or_null("Eyes") as GeometryInstance3D if _face != null else null


# --- Building ----------------------------------------------------------------

func _node(n: String, parent: Node) -> Node3D:
	var node := Node3D.new()
	node.name = n
	parent.add_child(node)
	return node


func _mesh(n: String, parent: Node, mesh: Mesh, material: Material, skin: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.material_override = material
	parent.add_child(mi)
	if skin:
		_skin_meshes.append(mi)
	return mi


func _meshes_in(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_meshes_in(c))
	return out


static func _quad_mesh() -> Mesh:
	return MeshKit.cached("onion:quad", func() -> Mesh:
		var q := PlaneMesh.new()
		q.size = Vector2(1, 1)
		return q)


func _build_ground_decals() -> void:
	_ring = _mesh("Ring", self, _quad_mesh(), Mats.ring(), false)
	_ring.scale = Vector3(RING_SIZE, 1, RING_SIZE)
	_ring.position.y = 0.025
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Mats.set_ring(_ring, player_color, 0.72, 0.93, 0.16)
	var d := REVIVE_RING_RADIUS * 2.0
	_revive_area = _mesh("ReviveArea", self, _quad_mesh(), Mats.ring(), false)
	_revive_area.scale = Vector3(d, 1, d)
	_revive_area.position.y = 0.02
	_revive_area.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Mats.set_ring(_revive_area, Color(1.0, 1.0, 1.0, 0.45), 0.88, 0.95, 0.06)
	_revive_area.visible = false
	_revive_arc = _mesh("ReviveArc", self, _quad_mesh(), Mats.ring(), false)
	_revive_arc.scale = Vector3(d, 1, d)
	_revive_arc.position.y = 0.03
	_revive_arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_revive_arc.visible = false


func _build_pointer() -> void:
	var mesh := MeshKit.cached("onion:pointer", func() -> Mesh:
		var k := MeshKit.new()
		k.add_extrusion(PackedVector2Array([Vector2(-0.12, 0), Vector2(0.12, 0), Vector2(0, 0.13)]), 0.02,
			MeshKit.xf(Vector3(0, 0, -RING_SIZE * 0.5 - 0.02), Vector3(-90, 0, 0)), Color.WHITE)
		return k.build())
	_pointer = _mesh("Pointer", _yaw, mesh, Mats.unshaded(player_color), false)
	_pointer.position.y = 0.03
	_pointer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_body() -> void:
	var skin := class_data.onion_color if class_data != null else Color(0.85, 0.55, 0.3)
	var headgear: StringName = class_data.headgear if class_data != null else &""
	var bulb_mesh := MeshKit.cached("onion:bulb", func() -> Mesh:
		var k := MeshKit.new()
		k.add_lathe(bulb_profile(), Transform3D(), Color.WHITE, 36)
		return k.build())
	_bulb = _mesh("Bulb", _body, bulb_mesh, Mats.onion_skin(skin))
	# Sprout (long green stalk for the spring-onion rogue, withered for the warlock).
	var sprout_kind := "long" if headgear == &"hood" else ("dark" if headgear == &"horned_hood" else "normal")
	if headgear != &"wizard_hat":
		var sprout := MeshKit.cached("onion:sprout:" + sprout_kind, func() -> Mesh: return _sprout_mesh(sprout_kind))
		_mesh("Sprout", _body, sprout, Mats.toon_vc())
	var roots := MeshKit.cached("onion:roots", func() -> Mesh: return _roots_mesh())
	_mesh("Roots", _body, roots, Mats.toon_vc(false))
	# Face: big eyes (+ brows for classes without a helm).
	var brows := headgear not in [&"helm_horned", &"paladin_helm"]
	var face_key := "onion:face:%s:%s" % [brows, headgear]
	_face = _node("Face", _body)
	_face.position.y = EYE_Y
	var eyes := MeshKit.cached(face_key, func() -> Mesh: return _face_mesh_build(brows, headgear))
	_mesh("Eyes", _face, eyes, Mats.toon_vc())
	if headgear == &"horned_hood":
		var fel := MeshKit.cached("onion:fel_eyes", func() -> Mesh: return _fel_eyes_mesh())
		var fm := _mesh("FelEyes", _face, fel, Mats.glow(Color(0.45, 1.0, 0.3), 2.5), false)
		fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if headgear != &"hood":
		var mouth := MeshKit.cached("onion:mouth", func() -> Mesh: return _mouth_mesh())
		_mesh("Mouth", _body, mouth, Mats.toon_vc(false))
	# Hands and feet.
	var glove := _glove_color()
	var boot := _boot_color()
	var hand_mesh := MeshKit.cached("onion:hand", func() -> Mesh:
		var k := MeshKit.new()
		k.add_sphere(0.088, Transform3D(), Color.WHITE, 14, 7)
		return k.build())
	for i in 2:
		var hand := _node("HandMain" if i == 0 else "HandOff", _body)
		hand.position = HAND_POS[i]
		_mesh("Glove", hand, hand_mesh, Mats.toon(glove))
		var grip := _node("Grip", hand)
		_hands.append(hand)
		_grips.append(grip)
	var foot_mesh := MeshKit.cached("onion:foot", func() -> Mesh:
		var k := MeshKit.new()
		k.add_sphere(0.1, MeshKit.xf(Vector3.ZERO, Vector3.ZERO, Vector3(0.85, 0.6, 1.25)), Color.WHITE, 12, 6)
		return k.build())
	for i in 2:
		var foot := _node("FootL" if i == 0 else "FootR", _yaw)
		foot.position = FOOT_POS[i]
		_mesh("Boot", foot, foot_mesh, Mats.toon(boot))
		_feet.append(foot)


func _glove_color() -> Color:
	if class_data == null:
		return Color(0.85, 0.55, 0.3)
	match class_data.headgear:
		&"helm_horned": return class_data.accent_color.darkened(0.08)
		&"paladin_helm": return GOLD
		&"wizard_hat": return class_data.onion_color.lightened(0.15)
		&"hood": return Color(0.28, 0.2, 0.15)
		&"horned_hood": return Color(0.2, 0.12, 0.24)
	return class_data.onion_color.lightened(0.1)


func _boot_color() -> Color:
	if class_data == null:
		return LEATHER
	match class_data.headgear:
		&"helm_horned": return class_data.accent_color.darkened(0.3)
		&"paladin_helm": return Color(0.85, 0.86, 0.9)
		&"wizard_hat": return class_data.accent_color.darkened(0.35)
		&"hood": return Color(0.22, 0.16, 0.12)
		&"horned_hood": return Color(0.16, 0.09, 0.2)
	return LEATHER


static func _sprout_mesh(kind: String) -> Mesh:
	var k := MeshKit.new()
	var c := SPROUT_GREEN
	var stretch := 1.0
	match kind:
		"long":
			c = Color(0.42, 0.8, 0.25)
			stretch = 1.9
		"dark":
			c = Color(0.36, 0.42, 0.2)
			stretch = 0.85
	var y0 := 0.97
	var leaves := [
		[Vector3(0, 0, 0), Vector3(0.02, 0.14, 0.02), Vector3(0.06, 0.26, 0.06), Vector3(0.13, 0.32, 0.12)],
		[Vector3(0, 0, 0), Vector3(-0.02, 0.12, -0.01), Vector3(-0.08, 0.21, -0.03), Vector3(-0.15, 0.24, -0.05)],
		[Vector3(0, 0, 0), Vector3(0.0, 0.1, 0.03), Vector3(0.01, 0.17, 0.1), Vector3(0.0, 0.18, 0.16)],
	]
	for leaf in leaves:
		var pts := PackedVector3Array()
		for p: Vector3 in leaf:
			pts.append(Vector3(p.x, y0 + p.y * stretch, p.z))
		k.add_tube(pts, 0.036, 0.008, c, 7)
	return k.build()


static func _roots_mesh() -> Mesh:
	var k := MeshKit.new()
	var c := Color(0.86, 0.8, 0.62)
	for i in 6:
		var a := TAU * i / 6.0 + 0.3
		var d := Vector3(sin(a), 0, cos(a))
		var pts := PackedVector3Array([Vector3(0, 0.115, 0) + d * 0.03, Vector3(0, 0.07, 0) + d * 0.08,
			Vector3(0, 0.02, 0) + d * 0.1])
		k.add_tube(pts, 0.013, 0.005, c, 5)
	return k.build()


static func _face_mesh_build(brows: bool, headgear: StringName) -> Mesh:
	var k := MeshKit.new()
	var white := Color(0.98, 0.98, 0.96)
	var pupil := Color(0.08, 0.06, 0.1)
	for side: float in [-1.0, 1.0]:
		var surface := bulb_point(EYE_Y, 19.0 * side)
		var center := Vector3(surface.x * 0.93, 0.0, surface.z * 0.93)
		var b := Basis.from_euler(Vector3(deg_to_rad(18), deg_to_rad(-19.0 * side), 0))
		k.add_sphere(0.1, Transform3D(b * Basis.from_scale(Vector3(1.0, 1.2, 0.6)), center), white, 16, 8)
		if headgear != &"horned_hood":
			var pc := center + b * Vector3(-0.012 * side, 0.01, -0.05)
			k.add_sphere(0.058, Transform3D(b * Basis.from_scale(Vector3(1.0, 1.15, 0.55)), pc), pupil, 12, 6)
			k.add_sphere(0.02, Transform3D(b, pc + b * Vector3(0.02 * side, 0.03, -0.03)), white, 6, 3)
		if brows:
			var tilt := 0.0
			match headgear:
				&"horned_hood": tilt = 24.0
				&"hood": tilt = 14.0 if side > 0 else -6.0
				&"wizard_hat": tilt = -8.0
			var bc := center + b * Vector3(0, 0.15, -0.035)
			var bb := b * Basis.from_euler(Vector3(0, 0, deg_to_rad(tilt * side)))
			k.add_capsule(0.022, 0.13, Transform3D(bb * Basis.from_euler(Vector3(0, 0, PI / 2)), bc), Color(0.16, 0.1, 0.1), 6, 2)
	return k.build()


static func _fel_eyes_mesh() -> Mesh:
	var k := MeshKit.new()
	for side: float in [-1.0, 1.0]:
		var surface := bulb_point(EYE_Y, 19.0 * side)
		var center := Vector3(surface.x * 0.93, 0.0, surface.z * 0.93)
		var b := Basis.from_euler(Vector3(deg_to_rad(18), deg_to_rad(-19.0 * side), 0))
		var pc := center + b * Vector3(-0.01 * side, 0.0, -0.052)
		k.add_sphere(0.06, Transform3D(b * Basis.from_scale(Vector3(1.1, 0.7, 0.5)), pc), Color.WHITE, 10, 5)
	return k.build()


static func _mouth_mesh() -> Mesh:
	var k := MeshKit.new()
	var c := Color(0.25, 0.06, 0.08)
	var pts := PackedVector3Array()
	for i in 7:
		var a := lerpf(-20.0, 20.0, i / 6.0)
		var y := 0.405 + 0.022 * pow(absf(a) / 20.0, 1.6)
		pts.append(bulb_point(y, a, 0.002))
	k.add_tube(pts, 0.016, 0.016, c, 6)
	k.add_sphere(0.016, MeshKit.xf(pts[0]), c, 6, 3)
	k.add_sphere(0.016, MeshKit.xf(pts[pts.size() - 1]), c, 6, 3)
	return k.build()


func _build_peels() -> void:
	var skin := class_data.onion_color if class_data != null else Color(0.85, 0.55, 0.3)
	var paper := skin.lerp(Color(0.93, 0.82, 0.64), 0.45)
	var flap := MeshKit.cached("onion:peel:" + paper.to_html(), func() -> Mesh:
		var k := MeshKit.new()
		var leaf := PackedVector2Array([Vector2(-0.06, 0), Vector2(0.06, 0), Vector2(0.075, 0.1),
			Vector2(0.045, 0.19), Vector2(0.0, 0.22), Vector2(-0.05, 0.17), Vector2(-0.07, 0.08)])
		k.add_extrusion(leaf, 0.014, Transform3D(), paper, 0.9)
		return k.build())
	var spots := [[150.0, 0.42], [-115.0, 0.58], [48.0, 0.3]]
	for i in spots.size():
		var a: float = spots[i][0]
		var y: float = spots[i][1]
		var pivot := _node("Peel%d" % i, _body)
		var p := bulb_point(y, a, 0.005)
		var outward := Vector3(p.x, 0, p.z).normalized()
		# Local +Y up the surface, local -Z outwards (extrusion front faces outwards).
		var z_axis := -outward
		var y_axis := Vector3.UP
		var x_axis := y_axis.cross(z_axis).normalized()
		pivot.transform = Transform3D(Basis(x_axis, y_axis, z_axis) * Basis.from_euler(Vector3(deg_to_rad(38), 0, 0)), p)
		_mesh("Flap", pivot, flap, Mats.toon_vc())
		pivot.visible = false
		_peels.append(pivot)


func _build_tears() -> void:
	var tear := MeshKit.cached("onion:tear", func() -> Mesh:
		var k := MeshKit.new()
		k.add_sphere(0.04, MeshKit.xf(Vector3.ZERO, Vector3.ZERO, Vector3(0.8, 1.25, 0.8)), Color.WHITE, 8, 5)
		k.add_cylinder(0.0, 0.03, 0.05, MeshKit.xf(Vector3(0, 0.05, 0)), Color.WHITE, 8)
		return k.build())
	for i in 2:
		var t := _mesh("Tear%d" % i, _body, tear, Mats.glow(Color(0.45, 0.75, 1.0), 1.6), false)
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.visible = false
		_tears.append(t)


# --- Class gear --------------------------------------------------------------

func _build_gear() -> void:
	var acc := class_data.accent_color
	var key := "onion:gear:%s:%s:%s:%s" % [class_data.headgear, acc.to_html(), class_data.big_shoulders,
		class_data.onion_color.to_html()]
	var gear := MeshKit.cached(key, func() -> Mesh: return _gear_mesh(class_data))
	if gear.get_surface_count() > 0:
		_mesh("Gear", _body, gear, Mats.toon_vc())
	var cloth := MeshKit.cached("onion:cloth:%s:%s" % [class_data.headgear, acc.to_html()],
		func() -> Mesh: return _cloth_mesh(class_data))
	if cloth.get_surface_count() > 0:
		_mesh("Cloth", _body, cloth, Mats.toon_cloth_vc())
	match class_data.headgear:
		&"horned_hood":
			var glow := MeshKit.cached("onion:fel_trim", func() -> Mesh:
				var k := MeshKit.new()
				k.add_torus(0.395, 0.425, MeshKit.xf(Vector3(0, 0.3, 0), Vector3.ZERO, Vector3(1, 0.6, 1)), Color.WHITE, 24, 4)
				return k.build())
			var gm := _mesh("FelTrim", _body, glow, Mats.glow(acc, 1.6), false)
			gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_fel_flame = _build_flame(_hands[1], acc)
		&"wizard_hat":
			var star := MeshKit.cached("onion:hat_star", func() -> Mesh:
				var k := MeshKit.new()
				var pts := PackedVector2Array()
				for i in 10:
					var a := TAU * i / 10.0
					var r := 0.065 if i % 2 == 0 else 0.028
					pts.append(Vector2(sin(a), cos(a)) * r)
				k.add_extrusion(pts, 0.015, MeshKit.xf(Vector3(0, 0.86, -0.29), Vector3(12, 0, 0)), Color.WHITE)
				return k.build())
			var sm := _mesh("HatStar", _body, star, Mats.glow(Color(1.0, 0.85, 0.35), 1.4), false)
			sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_flame(parent: Node3D, color: Color) -> Node3D:
	var pivot := _node("FelFlame", parent)
	pivot.position = Vector3(0, 0.1, 0)
	var mesh := MeshKit.cached("onion:flame", func() -> Mesh:
		var k := MeshKit.new()
		k.add_sphere(0.075, MeshKit.xf(Vector3(0, 0.06, 0)), Color.WHITE, 10, 5)
		k.add_cylinder(0.0, 0.07, 0.2, MeshKit.xf(Vector3(0, 0.16, 0)), Color.WHITE, 10)
		return k.build())
	var outer := _mesh("Outer", pivot, mesh, Mats.glow(color, 1.8), false)
	outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var inner := _mesh("Inner", pivot, mesh, Mats.glow(color.lerp(Color.WHITE, 0.6), 2.5), false)
	inner.scale = Vector3(0.55, 0.6, 0.55)
	inner.position.y = 0.01
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return pivot


static func _gear_mesh(cd: ClassData) -> Mesh:
	var k := MeshKit.new()
	var acc := cd.accent_color
	match cd.headgear:
		&"helm_horned":
			_helm_dome(k, acc, acc.darkened(0.35))
			for side: float in [-1.0, 1.0]:
				var horn := PackedVector3Array([Vector3(0.28 * side, 0.8, 0.02), Vector3(0.42 * side, 0.85, 0.0),
					Vector3(0.53 * side, 0.96, -0.03), Vector3(0.57 * side, 1.1, -0.06), Vector3(0.53 * side, 1.2, -0.08)])
				k.add_tube(horn, 0.08, 0.012, IVORY, 8)
				k.add_torus(0.06, 0.1, Transform3D(MeshKit.basis_from_y(Vector3(side, 0.35, 0)), Vector3(0.3 * side, 0.81, 0.02)), acc.darkened(0.35), 10, 4)
			_belt(k, LEATHER, acc)
		&"paladin_helm":
			var silver := acc.lerp(Color(0.8, 0.82, 0.88), 0.35)
			_helm_dome(k, GOLD, silver)
			for side: float in [-1.0, 1.0]:
				for f in 4:
					var feather := PackedVector2Array([Vector2(0, 0), Vector2(0.07, 0.1), Vector2(0.05, 0.34),
						Vector2(0.0, 0.42), Vector2(-0.04, 0.25)])
					var rot := Vector3(-10.0 - f * 20.0, 90.0 * side, -30.0 * side - f * 6.0 * side)
					k.add_extrusion(feather, 0.03, MeshKit.xf(Vector3(0.33 * side, 0.8, 0.02 + f * 0.035), rot), Color(0.98, 0.98, 0.96), 0.85)
				k.add_sphere(0.06, MeshKit.xf(Vector3(0.33 * side, 0.8, 0.03)), silver, 8, 4)
			_belt(k, GOLD, Color(0.9, 0.2, 0.15))
		&"wizard_hat":
			var hat := acc
			k.add_cylinder(0.5, 0.5, 0.035, MeshKit.xf(Vector3(0, 0.77, 0), Vector3(-6, 0, 0)), hat.darkened(0.15), 24)
			var cone := PackedVector3Array([Vector3(0, 0.77, 0.0), Vector3(0, 0.98, 0.04), Vector3(0, 1.16, 0.12),
				Vector3(0, 1.3, 0.25), Vector3(0, 1.36, 0.38)])
			k.add_tube(cone, 0.29, 0.02, hat, 16)
			k.add_torus(0.26, 0.32, MeshKit.xf(Vector3(0, 0.83, 0.006), Vector3(-6, 0, 0), Vector3(1, 1.4, 1)), GOLD, 24, 5)
			_belt(k, GOLD, hat)
		&"hood":
			_hood_cap(k, acc)
			_belt(k, LEATHER, Color(0.7, 0.7, 0.72))
			k.add_box(Vector3(0.12, 0.12, 0.08), MeshKit.xf(OnionModel.bulb_point(0.25, 125.0, 0.04), Vector3(0, 125, 0)), LEATHER.darkened(0.2))
			var strap := Transform3D(Basis.from_euler(Vector3(0, 0, deg_to_rad(32))) * Basis.from_scale(Vector3(1, 0.55, 1)), Vector3(0, 0.45, 0))
			k.add_torus(0.385, 0.425, strap, LEATHER.darkened(0.1), 28, 4)
		&"horned_hood":
			var dark := Color(0.17, 0.09, 0.2)
			_hood_cap(k, dark)
			for side: float in [-1.0, 1.0]:
				var horn := PackedVector3Array([Vector3(0.26 * side, 0.86, 0.04), Vector3(0.4 * side, 0.95, 0.1),
					Vector3(0.47 * side, 1.07, 0.2), Vector3(0.43 * side, 1.14, 0.33), Vector3(0.35 * side, 1.1, 0.4)])
				k.add_tube(horn, 0.07, 0.012, Color(0.62, 0.52, 0.48), 8)
			_belt(k, dark.lightened(0.1), acc)
		_:
			_belt(k, LEATHER, GOLD)
	if cd.big_shoulders:
		var main := acc if cd.headgear != &"paladin_helm" else Color(0.96, 0.96, 0.93)
		var trim := acc.darkened(0.4) if cd.headgear != &"paladin_helm" else GOLD
		for side: float in [-1.0, 1.0]:
			var b := Basis.from_euler(Vector3(0, 0, deg_to_rad(-48.0 * side)))
			var c := Vector3(0.33 * side, 0.6, 0.03)
			k.add_sphere(0.22, Transform3D(b * Basis.from_scale(Vector3(1.05, 1.0, 1.0)), c), main, 16, 8, true)
			k.add_torus(0.19, 0.25, Transform3D(b * Basis.from_scale(Vector3(1.05, 0.6, 1.0)), c), trim, 18, 5)
			k.add_sphere(0.16, Transform3D(b * Basis.from_scale(Vector3(1.0, 0.75, 0.95)), c + b * Vector3(0, 0.08, 0)), main.lightened(0.08), 14, 7, true)
			if cd.headgear == &"helm_horned":
				for s in 3:
					var dir := b * Vector3((s - 1) * 0.45, 1.0, 0).normalized()
					var base := c + b * Vector3((s - 1) * 0.09, 0.17, 0)
					k.add_segment(base, base + dir * 0.17, 0.045, 0.0, IVORY, 8)
			else:
				k.add_sphere(0.05, Transform3D(b, c + b * Vector3(0, 0.2, 0)), Color(0.3, 0.6, 1.0), 8, 4)
	return k.build()


static func _helm_dome(k: MeshKit, metal: Color, trim: Color) -> void:
	k.add_sphere(0.36, MeshKit.xf(Vector3(0, 0.665, 0), Vector3.ZERO, Vector3(1.0, 0.98, 1.0)), metal, 24, 10, true)
	k.add_torus(0.33, 0.4, MeshKit.xf(Vector3(0, 0.68, 0), Vector3.ZERO, Vector3(1, 0.75, 1)), trim, 28, 6)
	var crest := PackedVector2Array()
	for i in 13:
		var a := PI * i / 12.0
		crest.append(Vector2(cos(a), sin(a)) * 0.375)
	k.add_extrusion(crest, 0.05, MeshKit.xf(Vector3(0, 0.67, 0), Vector3(0, 90, 0)), trim)
	for i in 10:
		var a := TAU * i / 10.0
		k.add_sphere(0.022, MeshKit.xf(Vector3(sin(a) * 0.392, 0.69, cos(a) * 0.392)), trim.lightened(0.3), 6, 3)


static func _belt(k: MeshKit, belt: Color, buckle: Color) -> void:
	k.add_torus(0.365, 0.41, MeshKit.xf(Vector3(0, 0.3, 0), Vector3.ZERO, Vector3(1, 0.65, 1)), belt, 28, 5)
	k.add_box(Vector3(0.1, 0.08, 0.04), MeshKit.xf(OnionModel.bulb_point(0.3, 0.0, 0.035)), buckle)


static func _hood_cap(k: MeshKit, color: Color) -> void:
	var prof := PackedVector2Array()
	for p in bulb_profile():
		if p.y >= 0.66:
			prof.append(Vector2(p.x * 1.1 + 0.02, p.y + 0.03))
	k.add_lathe(prof, Transform3D(), color, 28)
	var tip := PackedVector3Array([Vector3(0, 0.98, 0.04), Vector3(0, 1.05, 0.14), Vector3(0, 1.02, 0.27),
		Vector3(0, 0.95, 0.33)])
	k.add_tube(tip, 0.075, 0.015, color, 8)


static func _cloth_mesh(cd: ClassData) -> Mesh:
	var k := MeshKit.new()
	var acc := cd.accent_color
	match cd.headgear:
		&"wizard_hat":
			_cape(k, acc.darkened(0.1))
		&"paladin_helm":
			var tabard := PackedVector2Array([Vector2(0.43, 0.07), Vector2(0.415, 0.18), Vector2(0.395, 0.28)])
			k.add_lathe(tabard, Transform3D(), TABARD_BLUE, 6, -30.0, 30.0)
			var trim := PackedVector2Array([Vector2(0.435, 0.055), Vector2(0.433, 0.075)])
			k.add_lathe(trim, Transform3D(), GOLD, 6, -30.0, 30.0)
		&"hood":
			_hood_sides(k, acc)
			var mask := PackedVector2Array()
			for p in bulb_profile():
				if p.y >= 0.37 and p.y <= 0.49:
					mask.append(Vector2(p.x + 0.018, p.y))
			k.add_lathe(mask, Transform3D(), acc.darkened(0.25), 14, -80.0, 80.0)
		&"horned_hood":
			_hood_sides(k, Color(0.17, 0.09, 0.2))
			_cape(k, Color(0.24, 0.1, 0.28))
	return k.build()


static func _cape(k: MeshKit, color: Color) -> void:
	var cape := PackedVector2Array([Vector2(0.5, 0.06), Vector2(0.46, 0.25), Vector2(0.44, 0.45),
		Vector2(0.38, 0.6), Vector2(0.27, 0.72)])
	k.add_lathe(MeshKit.smooth_profile(cape, 3), Transform3D(), color, 18, 70.0, 290.0)


static func _hood_sides(k: MeshKit, color: Color) -> void:
	var prof := PackedVector2Array()
	for p in bulb_profile():
		if p.y >= 0.4 and p.y <= 0.72:
			prof.append(Vector2(p.x * 1.1 + 0.02, p.y + 0.03))
	k.add_lathe(prof, Transform3D(), color, 18, 58.0, 302.0)
