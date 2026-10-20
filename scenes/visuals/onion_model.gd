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
##           ├── Gear                    Head / Shoulders / Chest armour (OnionArmor): Solid (+ Glow<n> for
##           │                           Epic and better), Cloth, Accent<n>; class extras (HatStar, ...)
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
## Peel flaps (angle in degrees from the front, height): on the bulb, and lifted by PEEL_GEAR_LIFT when a
## chest piece is worn so they stay visible on top of the armour (the low-HP cue must not vanish).
const PEEL_SPOTS: Array[Vector2] = [Vector2(132.0, 0.46), Vector2(-132.0, 0.6), Vector2(48.0, 0.3)]
const PEEL_GEAR_LIFT := 0.11
## Play Dead: how fast the body tips over (1/s), how far (radians) and how much it is lifted so
## that it rests on the ground.
const TIP_RATE := 6.0
const TIP_ANGLE := 1.5
const TIP_LIFT := 0.36
## Revive cast bar ("Resurrecting") above a downed onion: height, size (metres).
const CAST_BAR_Y := 2.0
const CAST_BAR_SIZE := Vector2(1.6, 0.3)
const REVIVE_COLOR := Color(0.55, 1.0, 0.45)
const CHANNEL_GOLD := Color(1.0, 0.84, 0.36)
## Where the reviver's light beam ends on the ghost (above its origin).
const CHANNEL_TARGET_HEIGHT := 0.85
## Base alpha of the translucent downed ghost (the rim adds more).
const GHOST_ALPHA := 0.6
## Player marker ("P2" + nameplate diamond + health bar, see [method set_tag]): height of
## its origin above a living hero (the bar's bottom edge) / a floating ghost and above the
## "Resurrecting" cast bar text (the diamond's bottom tip, no bar). The marker is drawn at a
## fixed screen size and on top of everything (shows through crowds).
const MARKER_Y := 1.9
const MARKER_GHOST_Y := 2.05
const MARKER_GHOST_BOB := 0.09
## World lift that puts the marker above the cast bar label for the gameplay camera pitch
## (the label sits ~0.7 m above the bar in the billboard plane).
const MARKER_CAST_Y := CAST_BAR_Y + 1.3
## Fixed-size sprites: world size per texel at 1 m depth (FOV 40: 1080 px span 0.728 m).
const MARKER_DIAMOND_PIXEL := 0.00038
const MARKER_LABEL_PIXEL := 0.00037
const MARKER_TEX_SIZE := Vector2i(40, 52)
## Overhead health bar: its bottom edge sits on the marker origin (just above the head)
## and lifts the diamond + tag above it; hidden with the marker and while downed (the
## diamond drops back onto the origin). Same fixed screen size, drawn on top of everything.
## Texels are ~1 px at 1080p.
const HP_BAR_PIXEL := 0.00068
## Whole bar incl. the dark frame / fill area inside it (texels).
const HP_BAR_SIZE := Vector2i(84, 14)
const HP_BAR_BORDER := 2
## Screen gap (bar texels) between the bar's top edge and the diamond's bottom tip.
const HP_BAR_GAP := 3.0
const HP_BAR_BACK := Color(0.2, 0.04, 0.04, 0.85)
const HP_BAR_YELLOW := Color(1.0, 0.8, 0.18)
## Absorb shield segment (ProcSystem.shield_hp) after the HP fill, over it when it overflows.
const HP_BAR_SHIELD := Color(0.75, 0.92, 1.0, 0.9)
## Revive area ring alpha (tinted with the downed player's own colour).
const REVIVE_AREA_ALPHA := 0.7
## Revive area ring fill (inner disc alpha) – normally a faint wash.
const REVIVE_AREA_FILL := 0.06
## Ghost slow cue (GDD 16.1, [method set_ghost_slowing]): while enemies inside the circle are
## slowed, the ring leans towards a pale spectral blue and its inner disc breathes up by
## GHOST_SLOW_FILL at GHOST_SLOW_PULSE rad/s.
const GHOST_SLOW_TINT := Color(0.6, 0.82, 1.0)
const GHOST_SLOW_TINT_MIX := 0.55
const GHOST_SLOW_FILL := 0.14
const GHOST_SLOW_PULSE := 2.6
## Purple flames (GDD 13: "horned hood and purple flames") on the warlock's horns.
const WARLOCK_FLAME := Color(0.72, 0.38, 1.0)

const GOLD := Color(0.96, 0.76, 0.3)
const LEATHER := Color(0.4, 0.25, 0.14)
const IVORY := Color(0.94, 0.9, 0.78)
const SPROUT_GREEN := Color(0.38, 0.7, 0.22)
const TABARD_BLUE := Color(0.17, 0.3, 0.68)
const SCARF_RED := Color(0.66, 0.11, 0.13)
## Rogue cowl: open above this height (pale neck + green stalk show), pale trim, dark mask.
const ROGUE_COWL_TOP := 0.86
const ROGUE_TRIM := Color(0.93, 0.89, 0.74)
const ROGUE_MASK := Color(0.13, 0.11, 0.12)
## Warlock hood / cape (purple, light enough to read against dark ground) and bone horns.
const WARLOCK_HOOD := Color(0.36, 0.17, 0.44)
const WARLOCK_HORN := Color(0.86, 0.79, 0.7)

## Bulb silhouette: (radius, y) from the root up to the neck.
const BULB_POINTS := [
	Vector2(0.0, 0.1), Vector2(0.12, 0.112), Vector2(0.25, 0.16), Vector2(0.35, 0.25),
	Vector2(0.4, 0.37), Vector2(0.405, 0.46), Vector2(0.38, 0.57), Vector2(0.32, 0.68),
	Vector2(0.23, 0.79), Vector2(0.13, 0.89), Vector2(0.065, 0.96), Vector2(0.035, 1.0),
	Vector2(0.0, 1.03),
]

static var _profile_cache := PackedVector2Array()
static var _marker_texture: Texture2D
static var _hp_bar_textures: Array[Texture2D] = []

var class_data: ClassData
var player_color := Color.WHITE
var hp_ratio := 1.0
var downed := false
var revive_progress := 0.0
## The ghost's revive circle slows enemies right now ([method set_ghost_slowing]).
var ghost_slowing := false
## Absorb shield / max HP shown on the overhead health bar (see [method set_shield_ratio]).
var shield_ratio := 0.0
## Player tag shown on the marker above the head ("P1" ...); "" hides the marker.
var tag := ""

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
## Extra flickering flames (warlock horn flames).
var _flames: Array[Node3D] = []
var _marker: Node3D
var _marker_label: Label3D
var _marker_diamond: Sprite3D
var _hp_bar: Node3D
var _hp_fill: Sprite3D
var _hp_shield: Sprite3D
var _weapon_nodes: Array[Node3D] = [null, null]
var _weapon_data: Array[WeaponData] = [null, null]
## Worn Head / Shoulders / Chest looks (EquipLook.Slot order; null = empty slot = the class starter
## piece) and their change-detection key. The gear is rebuilt only when the key changes.
var _looks: Array[EquipLook] = [null, null, null]
var _looks_key := "-|-|-"
var _gear: Node3D
var _gear_meshes: Array[MeshInstance3D] = []
## Nodes of the class starter pieces (hat star, horn flames, fel trim): freed with the gear.
var _gear_extras: Array[Node] = []
## Unshaded glow accents of the gear (hidden on the ghost).
var _accents: Array[MeshInstance3D] = []
var _sprout: MeshInstance3D
var _mouth: MeshInstance3D
## How often the gear was (re)built – for tests: equipment changes rebuild it, repeats do not.
var gear_builds := 0
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
## Play Dead (the Hunter): the body tips over on its side while true; _tip is the smoothed 0..1 pose.
var play_dead := false
var _tip := 0.0
var _attack_t: Array[float] = [1.0, 1.0]
var _blink := 0.0
var _next_blink := 2.0
var _rng := RandomNumberGenerator.new()
var _reviver_color := REVIVE_COLOR
var _cast_bar: MeshInstance3D
var _cast_label: Label3D
## Reviving a teammate: raised glowing hands + light beam to [member _channel_target].
var _channel_target: Node3D
var _channel_glows: Array[MeshInstance3D] = []
var _beam: MeshInstance3D


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
	_flames.clear()
	_gear = null
	_gear_meshes.clear()
	_gear_extras.clear()
	_accents.clear()
	_sprout = null
	_mouth = null
	_cast_bar = null
	_cast_label = null
	_hp_bar = null
	_hp_fill = null
	_hp_shield = null
	_channel_glows.clear()
	_beam = null
	_build_ground_decals()
	_yaw = _node("Yaw", self)
	_body = _node("Body", _yaw)
	_build_body()
	_build_class_extras()
	_build_gear()
	_build_peels()
	_build_tears()
	_build_pointer()
	_build_marker()
	_yaw.rotation.y = _target_yaw
	set_weapons(_weapon_data[0], _weapon_data[1])
	set_hp_ratio(hp_ratio)
	_apply_downed_look()
	set_revive_progress(revive_progress, _reviver_color)
	set_channel_target(_channel_target)


## Player marker above the head: a small nameplate diamond in the player colour with
## [param text] ("P1" ...) on top, drawn through everything so a hero / ghost is easy to
## find in a crowd. "" hides it (lobby previews).
func set_tag(text: String) -> void:
	tag = text
	if _marker_label != null:
		_marker_label.text = text
	_update_marker(0.0)


func is_marker_visible() -> bool:
	return _marker != null and _marker.visible


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


## Shows the worn Head / Shoulders / Chest armour (GDD 13): per slot the look of the item (armour
## type, material tier, rarity, set), or the class starter piece when the slot is empty (null) –
## an equipped item replaces the starter piece of its slot entirely. Only a change of what is worn
## rebuilds the gear; calling it again with the same items is free.
func set_equipment(head: ItemInstance, shoulders: ItemInstance, chest: ItemInstance) -> void:
	set_looks(EquipLook.from_item(head), EquipLook.from_item(shoulders), EquipLook.from_item(chest))


## [method set_equipment] with ready-made looks (showcase, tests). A look of the wrong slot is
## ignored.
func set_looks(head: EquipLook, shoulders: EquipLook, chest: EquipLook) -> void:
	var next: Array[EquipLook] = [head, shoulders, chest]
	var keys := PackedStringArray()
	for i in EquipLook.SLOT_COUNT:
		if next[i] != null and next[i].slot != i:
			next[i] = null
		keys.append(next[i].key() if next[i] != null else "-")
	var key := "|".join(keys)
	if key == _looks_key:
		return
	_looks = next
	_looks_key = key
	if _body != null:
		_build_gear()


## The worn look of an EquipLook.Slot (null = the class starter piece shows).
func worn_look(slot: int) -> EquipLook:
	return _looks[slot] if slot >= 0 and slot < _looks.size() else null


## Change-detection key of the worn looks ("-|-|-" = nothing worn).
func equipment_key() -> String:
	return _looks_key


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


## Play Dead (the Hunter): the onion tips over on its side (true) and gets up again (false).
func set_play_dead(on: bool) -> void:
	play_dead = on


## 0..1 how far the body has tipped over (Play Dead; tests).
func tip_amount() -> float:
	return _tip


## White flash + squash when damaged.
func flash_hit() -> void:
	_flash = 1.0
	_squash = 1.0
	_apply_flash()


## Low HP -> peeled / cracked onion layers (visual HP feedback). [param ratio] = hp / max.
func set_hp_ratio(ratio: float) -> void:
	hp_ratio = clampf(ratio, 0.0, 1.0)
	if _bulb != null and not downed:
		_bulb.material_override = Mats.onion_skin(_skin_color(), damage_amount(hp_ratio), _is_garlic())
		if _flash > 0.0:
			Mats.set_overlay(_bulb, Color(1, 1, 1), _flash * 0.85)
	for i in _peels.size():
		_peels[i].visible = not downed and hp_ratio < PEEL_THRESHOLDS[i]
	_update_hp_bar()


## Absorb shield as a share of max HP: a pale segment after the HP fill on the overhead bar
## (laid over the fill's end when HP + shield exceeds the bar).
func set_shield_ratio(ratio: float) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	if is_equal_approx(ratio, shield_ratio):
		return
	shield_ratio = ratio
	_update_hp_bar()


func is_hp_bar_visible() -> bool:
	return is_marker_visible() and _hp_bar != null and _hp_bar.visible


## Width of the visible HP fill as a fraction of the bar (0..1).
func hp_bar_fill() -> float:
	return _hp_fill.region_rect.size.x / _hp_inner().x if _hp_fill != null else 0.0


## Visible shield segment as (start, end) fractions of the bar; zero when there is none.
func hp_bar_shield() -> Vector2:
	if _hp_shield == null or not _hp_shield.visible:
		return Vector2.ZERO
	var w := _hp_inner().x
	var start := _hp_shield.offset.x + w * 0.5
	return Vector2(start, start + _hp_shield.region_rect.size.x) / w


## Bar colour: green when healthy, yellow at half, red when nearly dead.
static func hp_bar_color(ratio: float) -> Color:
	if ratio >= 0.5:
		return HP_BAR_YELLOW.lerp(UiTheme.HP_GREEN, (ratio - 0.5) * 2.0)
	return UiTheme.RED.lerp(HP_BAR_YELLOW, ratio * 2.0)


## Downed: translucent crying onion ghost. false restores the normal look.
func set_downed(p_downed: bool) -> void:
	if downed == p_downed:
		return
	downed = p_downed
	_apply_downed_look()
	set_hp_ratio(hp_ratio)
	if not downed:
		set_revive_progress(0.0)
		set_ghost_slowing(false)


## Ghost slow cue (GDD 16.1): [param active] while the downed hero's revive circle slows at
## least one enemy (Player sets it every tick; only changes do anything). Active, the revive
## ring turns spectral blue and its inner disc breathes ([method _pulse_ghost_slow]); off, the
## plain player-colour ring comes back.
func set_ghost_slowing(active: bool) -> void:
	if ghost_slowing == active:
		return
	ghost_slowing = active
	if _revive_area == null:
		return
	if active:
		_pulse_ghost_slow()
	else:
		Mats.set_ring(_revive_area, Color(player_color.r, player_color.g, player_color.b, REVIVE_AREA_ALPHA), 0.88, 0.95, REVIVE_AREA_FILL)


## 0..1 revive progress shown while a teammate stands next to a downed player: an arc on
## the revive ring plus a WoW-like "Resurrecting" cast bar above the head, both in
## [param reviver_color] (the reviver's player colour). [param seconds_left] >= 0 adds the
## remaining cast time to the bar.
func set_revive_progress(progress: float, reviver_color: Color = REVIVE_COLOR, seconds_left: float = -1.0) -> void:
	revive_progress = clampf(progress, 0.0, 1.0)
	_reviver_color = reviver_color
	if _revive_arc == null:
		return
	var showing := downed and revive_progress > 0.0
	_revive_arc.visible = showing
	Mats.set_ring(_revive_arc, Color(reviver_color.r, reviver_color.g, reviver_color.b, 0.95), 0.86, 0.97, 0.0, revive_progress)
	if showing and _cast_bar == null:
		_build_cast_bar()
	if _cast_bar == null:
		return
	_cast_bar.visible = showing
	_cast_label.visible = showing
	if showing:
		Mats.set_cast_bar(_cast_bar, Color(reviver_color.r, reviver_color.g, reviver_color.b, 1.0), revive_progress)
		_cast_label.text = "Resurrecting" if seconds_left < 0.0 else "Resurrecting  %.1f" % seconds_left


func is_cast_bar_visible() -> bool:
	return _cast_bar != null and _cast_bar.visible


## Reviving a teammate (GDD 1): both hands rise and glow golden, and a beam of light
## connects them to [param target] (the downed player's node). null stops it.
func set_channel_target(target: Node3D) -> void:
	_channel_target = target if target != null and is_instance_valid(target) else null
	var active := _channel_target != null
	if active and _beam == null and _hands.size() == 2:
		_build_channel_fx()
	for g in _channel_glows:
		g.visible = active
	if _beam != null:
		_beam.visible = active
		if active:
			_update_beam()


func is_channeling() -> bool:
	return _channel_target != null


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
		&"two_hand_sword":
			rot = Vector3(-34, 0, -18 * side)
			pos = Vector3(0, 0.04, 0)
		&"two_hand_mace":
			rot = Vector3(-38, 0, -24 * side)
			pos = Vector3(0, -0.02, 0)
		&"orb":
			rot = Vector3(-12, 0, 0)
			pos = Vector3(0, 0.08, 0.06)
		&"crossbow":
			# Gun-like, held a little higher.
			rot = Vector3(-76, 0, 0)
			pos = Vector3(0, 0.03, 0.10)
		&"polearm":
			# The staff family: slanted forward, the hand low on the haft.
			rot = Vector3(-22, 0, -10 * side)
			pos = Vector3(0, 0.12, 0.02)
		&"fist_weapon":
			# Claws forward.
			rot = Vector3(-60, 0, -14 * side)
			pos = Vector3(0, 0, 0.04)
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
	for i in _flames.size():
		var fl := _flames[i]
		if fl.visible:
			var g := 1.0 + sin(_time * 15.0 + i * 2.1) * 0.12 + sin(_time * 6.1 + i) * 0.08
			fl.scale = Vector3(1.0 / g, g, 1.0 / g)
	if downed:
		_pulse_ghost_ring()
		if ghost_slowing:
			_pulse_ghost_slow()
	_update_marker(delta)
	if _channel_target != null:
		if not is_instance_valid(_channel_target) or not _channel_target.is_inside_tree() or downed:
			set_channel_target(null)
		else:
			_update_beam()


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
	_tip = move_toward(_tip, 1.0 if play_dead else 0.0, delta * TIP_RATE)
	if _tip > 0.0:
		var eased := smoothstep(0.0, 1.0, _tip)
		_body.rotation.z += eased * TIP_ANGLE
		_body.position += Vector3(-0.05, TIP_LIFT, 0.0) * eased
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
		elif _channel_target != null:
			pos = Vector3(HAND_POS[i].x * 0.82, 0.98 + hover * 1.5, -0.22)
			rot = Vector3(0.5, 0.0, -0.35 * side)
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
	if downed:
		return
	for mi in _skin_meshes:
		if is_instance_valid(mi):
			Mats.set_overlay(mi, Color(1, 1, 1), _flash * 0.85)


## Current peel amount of the bulb material (0 = intact) – for tests / debugging.
func bulb_damage() -> float:
	var m := Mats.base_material(_bulb) as ShaderMaterial if _bulb != null else null
	if m == null:
		return 0.0
	var v: Variant = m.get_shader_parameter(&"damage")
	return float(v) if v != null else 0.0


func _skin_color() -> Color:
	return class_data.onion_color if class_data != null else Color(0.85, 0.55, 0.3)


## The Shaman is a garlic bulb: white-lilac skin with purple streaks (Mats.onion_skin).
func _is_garlic() -> bool:
	return class_data != null and class_data.headgear == &"tribal_mask"


func _apply_downed_look() -> void:
	if _body == null:
		return
	var ghost_color := Color(0.88, 0.94, 1.0, GHOST_ALPHA)
	if class_data != null:
		var c := class_data.onion_color.lerp(Color(0.92, 0.96, 1.0), 0.6)
		ghost_color = Color(c.r, c.g, c.b, GHOST_ALPHA)
	for mi in _skin_meshes:
		if not is_instance_valid(mi):
			continue
		if downed:
			# Drop any hit-flash tint first so the saved / kept look is the plain one.
			mi.material_override = Mats.base_material(mi)
			if not _saved_materials.has(mi):
				_saved_materials[mi] = mi.material_override
			if mi != _face_mesh():
				mi.material_override = Mats.ghost(ghost_color)
		elif _saved_materials.has(mi):
			mi.material_override = _saved_materials[mi]
	if not downed:
		_saved_materials.clear()
	var eyes := _face_mesh()
	if eyes != null:
		# The ghost casts no shadow, so floating eye shadows would look odd.
		eyes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if downed \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for w in _weapon_nodes:
		if w != null:
			w.visible = not downed
	for f in _feet:
		f.visible = not downed
	for t in _tears:
		t.visible = downed
	if _fel_flame != null:
		_fel_flame.visible = not downed and _weapon_data[1] == null
	for fl in _flames:
		fl.visible = not downed
	for a in _accents:
		a.visible = not downed
	_revive_area.visible = downed
	_revive_arc.visible = downed and revive_progress > 0.0
	# The player-colour ring stays under the ghost (pulsing, see _pulse_ghost_ring) so it is
	# clear whose ghost it is; the facing pointer goes.
	_ring.visible = true
	_ring.scale = Vector3(RING_SIZE, 1, RING_SIZE)
	Mats.set_ring(_ring, Color(player_color.r, player_color.g, player_color.b, 0.95), 0.72, 0.93, 0.16)
	if _pointer != null:
		_pointer.visible = not downed
	_update_marker(0.0)


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
	Mats.set_ring_stroke(_ring, 1.0)
	var d := REVIVE_RING_RADIUS * 2.0
	_revive_area = _mesh("ReviveArea", self, _quad_mesh(), Mats.ring(), false)
	_revive_area.scale = Vector3(d, 1, d)
	_revive_area.position.y = 0.02
	_revive_area.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Tinted with the downed player's own colour: whose circle it is reads from afar.
	Mats.set_ring(_revive_area, Color(player_color.r, player_color.g, player_color.b, REVIVE_AREA_ALPHA), 0.88, 0.95, REVIVE_AREA_FILL)
	Mats.set_ring_stroke(_revive_area, 0.6)
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


## "P1" + nameplate diamond above the head (see [method set_tag]). Fixed screen size, no
## depth test (visible through enemies), does not turn with the body.
func _build_marker() -> void:
	_marker = _node("Marker", self)
	_marker_diamond = Sprite3D.new()
	_marker_diamond.name = "Diamond"
	_marker_diamond.texture = marker_texture()
	_marker_diamond.pixel_size = MARKER_DIAMOND_PIXEL
	# Bottom tip on the marker origin (above the health bar, see _lift_plate), grows upwards.
	_marker_diamond.modulate = Color(player_color.r, player_color.g, player_color.b, 1.0)
	_marker_diamond.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker_diamond.fixed_size = true
	_marker_diamond.no_depth_test = true
	_marker_diamond.shaded = false
	_marker_diamond.double_sided = true
	_marker_diamond.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_marker_diamond.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	_marker_diamond.render_priority = 26
	_marker_diamond.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.add_child(_marker_diamond)
	_marker_label = Label3D.new()
	_marker_label.name = "Tag"
	_marker_label.text = tag
	_marker_label.font_size = 44
	_marker_label.outline_size = 14
	_marker_label.pixel_size = MARKER_LABEL_PIXEL
	_marker_label.modulate = player_color.lightened(0.3)
	_marker_label.outline_modulate = Color(0.06, 0.035, 0.045)
	_marker_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	# Sits on the diamond's top tip (both scale with depth the same way, see _lift_plate).
	_marker_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker_label.fixed_size = true
	_marker_label.no_depth_test = true
	_marker_label.shaded = false
	_marker_label.double_sided = true
	_marker_label.render_priority = 28
	_marker_label.outline_render_priority = 27
	_marker_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.add_child(_marker_label)
	_build_hp_bar()
	_update_marker(0.0)


## Health bar between the head and the diamond: dark framed back, HP fill (region width =
## HP ratio, left-aligned) and the absorb shield segment.
func _build_hp_bar() -> void:
	var tex := hp_bar_textures()
	_hp_bar = _node("HpBar", _marker)
	var center_y := HP_BAR_SIZE.y * 0.5
	var back := _hp_sprite("Back", tex[0], 23)
	back.offset = Vector2(0, center_y)
	var inner := _hp_inner()
	_hp_fill = _hp_sprite("Fill", tex[1], 24)
	_hp_fill.centered = false
	_hp_fill.region_enabled = true
	_hp_fill.offset = Vector2(-inner.x * 0.5, center_y - inner.y * 0.5)
	_hp_shield = _hp_sprite("Shield", tex[1], 25)
	_hp_shield.centered = false
	_hp_shield.region_enabled = true
	_hp_shield.modulate = HP_BAR_SHIELD
	_update_hp_bar()


func _hp_sprite(n: String, texture: Texture2D, priority: int) -> Sprite3D:
	var s := Sprite3D.new()
	s.name = n
	s.texture = texture
	s.pixel_size = HP_BAR_PIXEL
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.fixed_size = true
	s.no_depth_test = true
	s.shaded = false
	s.double_sided = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	s.render_priority = priority
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hp_bar.add_child(s)
	return s


## Diamond (bottom tip) + tag on top of the health bar, or right on the marker origin
## when the bar is hidden. Offsets are in each sprite's own texels.
func _lift_plate(over_bar: bool) -> void:
	var lift := (HP_BAR_SIZE.y + HP_BAR_GAP) * HP_BAR_PIXEL if over_bar else 0.0
	_marker_diamond.offset = Vector2(0, MARKER_TEX_SIZE.y * 0.5 + lift / MARKER_DIAMOND_PIXEL)
	_marker_label.offset = Vector2(0, (MARKER_TEX_SIZE.y * MARKER_DIAMOND_PIXEL + lift) / MARKER_LABEL_PIXEL - 10.0)


static func _hp_inner() -> Vector2:
	return Vector2(HP_BAR_SIZE - Vector2i.ONE * HP_BAR_BORDER * 2)


func _update_hp_bar() -> void:
	if _hp_bar == null:
		return
	# A ghost has no health: the cast bar / Spirit Healer hints take over.
	_hp_bar.visible = not downed
	_lift_plate(_hp_bar.visible)
	var inner := _hp_inner()
	var fill_w := roundf(inner.x * hp_ratio)
	if hp_ratio > 0.0:
		fill_w = maxf(fill_w, 1.0)  # a sliver of life stays visible
	_hp_fill.visible = fill_w > 0.0
	_hp_fill.region_rect = Rect2(0, 0, fill_w, inner.y)
	var c := hp_bar_color(hp_ratio)
	_hp_fill.modulate = Color(c.r, c.g, c.b, 1.0)
	var shield_w := roundf(inner.x * shield_ratio)
	_hp_shield.visible = shield_w > 0.0
	if not _hp_shield.visible:
		return
	var start := minf(fill_w, inner.x - shield_w)
	_hp_shield.region_rect = Rect2(0, 0, shield_w, inner.y)
	_hp_shield.offset = Vector2(-inner.x * 0.5 + start, _hp_fill.offset.y)


## Marker height / visibility: above the head, bobbing over a ghost, lifted above the
## "Resurrecting" cast bar while a teammate revives.
func _update_marker(_delta: float) -> void:
	if _marker == null:
		return
	_marker.visible = tag != ""
	if not _marker.visible:
		return
	var y := MARKER_Y
	if downed:
		y = MARKER_CAST_Y if is_cast_bar_visible() else MARKER_GHOST_Y
		y += sin(_time * 3.2) * MARKER_GHOST_BOB
	_marker.position = Vector3(0, y, 0)


## Downed: the player-colour ring under the ghost breathes (alpha + size) so the ghost is
## easy to spot and clearly someone's.
func _pulse_ghost_ring() -> void:
	var pulse := 0.5 + 0.5 * sin(_time * 4.2)
	var s := RING_SIZE * (1.08 + 0.14 * pulse)
	_ring.scale = Vector3(s, 1, s)
	Mats.set_ring(_ring, Color(player_color.r, player_color.g, player_color.b, 0.6 + 0.38 * pulse), 0.7, 0.93, 0.1 + 0.18 * pulse)


## Ghost slow cue: the revive ring in the player colour leaning towards GHOST_SLOW_TINT, its
## inner disc breathing between REVIVE_AREA_FILL and + GHOST_SLOW_FILL.
func _pulse_ghost_slow() -> void:
	var pulse := 0.5 + 0.5 * sin(_time * GHOST_SLOW_PULSE)
	var c := player_color.lerp(GHOST_SLOW_TINT, GHOST_SLOW_TINT_MIX)
	Mats.set_ring(_revive_area, Color(c.r, c.g, c.b, REVIVE_AREA_ALPHA), 0.88, 0.95, REVIVE_AREA_FILL + GHOST_SLOW_FILL * pulse)


## Nameplate diamond (white fill with soft facets, dark outline) – tinted per player through
## the sprite's modulate. Built once.
static func marker_texture() -> Texture2D:
	if _marker_texture != null:
		return _marker_texture
	var w := MARKER_TEX_SIZE.x
	var h := MARKER_TEX_SIZE.y
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var hw := w * 0.5 - 1.0
	var hh := h * 0.5 - 1.0
	var edge_scale := hw * hh / sqrt(hw * hw + hh * hh)
	var outline := 3.2
	var dark := Color(0.06, 0.035, 0.045)
	for y in h:
		for x in w:
			var dx := (x + 0.5 - w * 0.5) / hw
			var dy := (y + 0.5 - h * 0.5) / hh
			var e := (1.0 - (absf(dx) + absf(dy))) * edge_scale
			var a := clampf(e + 0.5, 0.0, 1.0)
			if a <= 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			# Upper-left facets lit, lower-right a little darker, a bright inner edge.
			var shade := 1.0 if dx + dy < 0.0 else 0.8
			var inner := clampf(1.0 - absf(e - outline - 1.5) / 1.2, 0.0, 1.0) * 0.15
			var fill := Color(shade + inner, shade + inner, shade + inner)
			var t := clampf(e - outline + 0.5, 0.0, 1.0)
			var c := dark.lerp(fill, t)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	_marker_texture = ImageTexture.create_from_image(img)
	return _marker_texture


## [back, fill]: the framed dark bar and the white fill strip (a lighter top row and a
## darker bottom row give it some volume; tinted through modulate). Built once.
static func hp_bar_textures() -> Array[Texture2D]:
	if not _hp_bar_textures.is_empty():
		return _hp_bar_textures
	var dark := Color(0.06, 0.035, 0.045)
	var back := Image.create(HP_BAR_SIZE.x, HP_BAR_SIZE.y, false, Image.FORMAT_RGBA8)
	back.fill(dark)
	back.fill_rect(Rect2i(Vector2i.ONE * HP_BAR_BORDER, Vector2i(_hp_inner())), HP_BAR_BACK)
	var inner := Vector2i(_hp_inner())
	var fill := Image.create(inner.x, inner.y, false, Image.FORMAT_RGBA8)
	for y in inner.y:
		var shade := 1.0 if y == 0 else (0.9 if y < inner.y * 0.45 else 0.72)
		fill.fill_rect(Rect2i(0, y, inner.x, 1), Color(shade, shade, shade))
	_hp_bar_textures = [ImageTexture.create_from_image(back), ImageTexture.create_from_image(fill)]
	return _hp_bar_textures


func _build_body() -> void:
	var skin := class_data.onion_color if class_data != null else Color(0.85, 0.55, 0.3)
	var headgear: StringName = class_data.headgear if class_data != null else &""
	var bulb_mesh := MeshKit.cached("onion:bulb", func() -> Mesh:
		var k := MeshKit.new()
		k.add_lathe(bulb_profile(), Transform3D(), Color.WHITE, 36)
		return k.build())
	_bulb = _mesh("Bulb", _body, bulb_mesh, Mats.onion_skin(skin, damage_amount(hp_ratio), _is_garlic()))
	# Sprout: long green stalk for the spring-onion rogue, withered for the warlock, pale garlic scapes for the
	# shaman, "normal" for any other headgear (the hunter's hat covers it).
	var sprout_kind := "long" if headgear == &"hood" else ("dark" if headgear == &"horned_hood" else ("pale" if headgear == &"tribal_mask" else "normal"))
	var sprout := MeshKit.cached("onion:sprout:" + sprout_kind, func() -> Mesh: return _sprout_mesh(sprout_kind))
	_sprout = _mesh("Sprout", _body, sprout, Mats.toon_vc())
	var roots := MeshKit.cached("onion:roots", func() -> Mesh: return _roots_mesh())
	_mesh("Roots", _body, roots, Mats.toon_vc(false))
	# Face: big eyes (+ brows unless the head piece is a helm; _apply_head_effects keeps them in sync).
	var head := OnionArmor.part(EquipLook.Slot.HEAD, _looks[EquipLook.Slot.HEAD], class_data)
	_face = _node("Face", _body)
	_face.position.y = EYE_Y
	_mesh("Eyes", _face, _eyes_mesh(head.brows if head != null else true), Mats.toon_vc())
	if headgear == &"horned_hood":
		var fel := MeshKit.cached("onion:fel_eyes", func() -> Mesh: return _fel_eyes_mesh())
		var fm := _mesh("FelEyes", _face, fel, Mats.glow(Color(0.45, 1.0, 0.3), 2.5), false)
		fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mouth := MeshKit.cached("onion:mouth", func() -> Mesh: return _mouth_mesh())
	_mouth = _mesh("Mouth", _body, mouth, Mats.toon_vc(false))
	if head != null:
		_sprout.visible = not head.hides_sprout
		_mouth.visible = not head.hides_mouth
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


## Glove colour per headgear. [code]hunter_hat[/code] and [code]tribal_mask[/code] (M8) are hooks the
## class packages fill; any headgear id without an arm gets the plain look (the onion skin, lighter).
func _glove_color() -> Color:
	if class_data == null:
		return Color(0.85, 0.55, 0.3)
	match class_data.headgear:
		&"helm_horned": return class_data.accent_color.darkened(0.08)
		&"paladin_helm": return GOLD
		&"wizard_hat": return class_data.onion_color.lightened(0.15)
		&"hood": return Color(0.28, 0.2, 0.15)
		&"horned_hood": return Color(0.2, 0.12, 0.24)
		&"hunter_hat": return Color(0.45, 0.3, 0.18)
		&"tribal_mask": return Color(0.5, 0.34, 0.2)  # wrapped wooden-brown hands
		_: pass
	return class_data.onion_color.lightened(0.1)


## Boot colour per headgear (same hooks and default as [method _glove_color]: plain leather).
func _boot_color() -> Color:
	if class_data == null:
		return LEATHER
	match class_data.headgear:
		&"helm_horned": return class_data.accent_color.darkened(0.3)
		&"paladin_helm": return Color(0.85, 0.86, 0.9)
		&"wizard_hat": return class_data.accent_color.darkened(0.35)
		&"hood": return Color(0.22, 0.16, 0.12)
		&"horned_hood": return Color(0.16, 0.09, 0.2)
		&"hunter_hat": return Color(0.3, 0.2, 0.12)
		&"tribal_mask": return Color(0.33, 0.22, 0.14)
		_: pass
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
		"pale":
			# Garlic scapes: pale green-white stalks.
			c = Color(0.8, 0.9, 0.62)
			stretch = 0.95
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
				&"hunter_hat": tilt = 9.0  # a keen, steady look
				&"tribal_mask": pass  # level brows under the carved mask
				_: pass  # level brows
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
	for i in PEEL_SPOTS.size():
		var a := PEEL_SPOTS[i].x
		var y := PEEL_SPOTS[i].y
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
	_place_peels()


## Puts the peel flaps on the bulb, or on top of the armour when a chest piece is worn.
func _place_peels() -> void:
	var lift := PEEL_GEAR_LIFT if _looks[EquipLook.Slot.CHEST] != null else 0.0
	for i in _peels.size():
		_peels[i].position = bulb_point(PEEL_SPOTS[i].y, PEEL_SPOTS[i].x, 0.005 + lift)


func _build_cast_bar() -> void:
	_cast_bar = _mesh("CastBar", self, MeshKit.cached("onion:cast_bar", func() -> Mesh:
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		return q), Mats.cast_bar(), false)
	_cast_bar.position = Vector3(0, CAST_BAR_Y, 0)
	_cast_bar.scale = Vector3(CAST_BAR_SIZE.x, CAST_BAR_SIZE.y, 1.0)
	_cast_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cast_label = Label3D.new()
	_cast_label.name = "CastLabel"
	_cast_label.text = "Resurrecting"
	_cast_label.font_size = 48
	_cast_label.pixel_size = 0.0062
	_cast_label.outline_size = 12
	_cast_label.modulate = Color(1.0, 0.97, 0.88)
	_cast_label.outline_modulate = Color(0.08, 0.04, 0.05)
	_cast_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_cast_label.no_depth_test = true
	_cast_label.shaded = false
	_cast_label.render_priority = 32
	_cast_label.outline_render_priority = 31
	_cast_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Same anchor as the bar, lifted in screen space (billboard plane) so it never overlaps.
	_cast_label.position = Vector3(0, CAST_BAR_Y, 0)
	_cast_label.offset = Vector2(0, (CAST_BAR_SIZE.y * 0.5 + 0.2) / _cast_label.pixel_size)
	add_child(_cast_label)


func _build_channel_fx() -> void:
	var glow_mesh := MeshKit.cached("onion:channel_glow", func() -> Mesh:
		var k := MeshKit.new()
		k.add_sphere(0.15, Transform3D(), Color.WHITE, 12, 6)
		return k.build())
	for hand in _hands:
		var g := _mesh("ChannelGlow", hand, glow_mesh, Mats.glow(Color(CHANNEL_GOLD, 0.55), 2.2), false)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.visible = false
		_channel_glows.append(g)
	_beam = _mesh("ChannelBeam", self, MeshKit.cached("onion:beam", func() -> Mesh:
		var k := MeshKit.new()
		k.add_cylinder(1.0, 1.0, 1.0, MeshKit.xf(Vector3(0, 0.5, 0)), Color.WHITE, 10, false)
		return k.build()), Mats.glow(Color(1.0, 0.88, 0.5, 0.5), 2.0), false)
	_beam.top_level = true
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false


## Stretches the light beam from the raised hands to the revived ghost.
func _update_beam() -> void:
	if _beam == null or _channel_target == null or not is_inside_tree() or not _channel_target.is_inside_tree():
		return
	var from := (_hands[0].global_position + _hands[1].global_position) * 0.5 + Vector3(0, 0.08, 0)
	var to := _channel_target.global_position + Vector3.UP * CHANNEL_TARGET_HEIGHT
	var length := from.distance_to(to)
	if length < 0.05:
		_beam.visible = false
		return
	_beam.visible = true
	var r := 0.05 * (1.0 + 0.3 * sin(_time * 14.0))
	var b := MeshKit.basis_from_y((to - from) / length)
	_beam.global_transform = Transform3D(Basis(b.x * r, b.y * length, b.z * r), from)
	for g in _channel_glows:
		g.scale = Vector3.ONE * (1.0 + 0.18 * sin(_time * 9.0 + g.get_instance_id() % 5))


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

# --- Gear (class starter pieces and worn armour, see OnionArmor) ----------------

## Rebuilds the Gear node and the class extras (hat star, horn flames, fel trim) from the three slot
## looks: an empty slot shows the class starter piece, a worn item its own (OnionArmor.part). The
## parts are merged by material so the common case stays at one solid + one cloth mesh.
func _build_gear() -> void:
	_clear_gear()
	gear_builds += 1
	if class_data == null:
		return
	_gear = _node("Gear", _body)
	var parts: Array[OnionArmor.Part] = []
	for slot in EquipLook.SLOT_COUNT:
		parts.append(OnionArmor.part(slot, _looks[slot], class_data))
	# Solid toon meshes grouped by material (plain / one glow material per rarity colour).
	var groups: Dictionary[String, Array] = {}
	for p in parts:
		if p != null and p.solid != null:
			var group: Array = groups.get(p.material_key(), [])
			group.append(p)
			groups[p.material_key()] = group
	var gkeys: Array = groups.keys()
	gkeys.sort()
	for i in gkeys.size():
		var group: Array = groups[gkeys[i]]
		var first: OnionArmor.Part = group[0]
		var meshes: Array[Mesh] = []
		var key := "onion:gear:solid"
		for p: OnionArmor.Part in group:
			meshes.append(p.solid)
			key += "|" + p.key
		var mesh: Mesh = first.solid if meshes.size() == 1 else OnionArmor.merged(key, meshes)
		var material := Mats.toon_vc() if first.glow.a <= 0.0 else Mats.toon_vc_glow(first.glow, first.glow_energy)
		_gear_mesh_node("Solid" if first.glow.a <= 0.0 else "Glow%d" % i, mesh, material, true)
	# Cloth (double-sided, no outline) of every slot in one mesh.
	var cloths: Array[Mesh] = []
	var cloth_key := "onion:gear:cloth"
	for p in parts:
		if p != null and p.cloth != null:
			cloths.append(p.cloth)
			cloth_key += "|" + p.key
	if not cloths.is_empty():
		_gear_mesh_node("Cloth", cloths[0] if cloths.size() == 1 else OnionArmor.merged(cloth_key, cloths),
			Mats.toon_cloth_vc(), true)
	# Glowing accents (Legendary / set gems and rings): one unshaded mesh per glow colour.
	var accent_groups: Dictionary[String, Array] = {}
	for p in parts:
		if p != null and p.accent != null:
			var group: Array = accent_groups.get(p.accent_color.to_html(false), [])
			group.append(p)
			accent_groups[p.accent_color.to_html(false)] = group
	var akeys: Array = accent_groups.keys()
	akeys.sort()
	for i in akeys.size():
		var group: Array = accent_groups[akeys[i]]
		var meshes: Array[Mesh] = []
		var key := "onion:gear:accent"
		for p: OnionArmor.Part in group:
			meshes.append(p.accent)
			key += "|" + p.key
		var first: OnionArmor.Part = group[0]
		var node := _gear_mesh_node("Accent%d" % i, first.accent if meshes.size() == 1 else OnionArmor.merged(key, meshes),
			Mats.glow(first.accent_color, OnionArmor.ACCENT_ENERGY), false)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visible = not downed
		_accents.append(node)
	_build_starter_extras(parts)
	_apply_head_effects(parts[EquipLook.Slot.HEAD])
	_place_peels()
	if downed:
		_apply_downed_look()
	elif _flash > 0.0:
		_apply_flash()


func _gear_mesh_node(n: String, mesh: Mesh, material: Material, skin: bool) -> MeshInstance3D:
	var mi := _mesh(n, _gear, mesh, material, skin)
	_gear_meshes.append(mi)
	return mi


## Frees the previous Gear node and every extra, and forgets them in the skin lists.
func _clear_gear() -> void:
	for mi in _gear_meshes:
		_skin_meshes.erase(mi)
		_saved_materials.erase(mi)
	_gear_meshes.clear()
	_accents.clear()
	_flames.clear()
	for n in _gear_extras:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.queue_free()
	_gear_extras.clear()
	if _gear != null:
		_gear.get_parent().remove_child(_gear)
		_gear.queue_free()
		_gear = null


## The glowing / animated bits that belong to a class starter piece: the mage's hat star, the warlock's
## horn flames and fel trim. They go with the starter piece of their slot, not with the class.
func _build_starter_extras(parts: Array[OnionArmor.Part]) -> void:
	var acc := class_data.accent_color
	for p in parts:
		if p == null:
			continue
		for extra in p.extras:
			match extra:
				&"hat_star":
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
					_gear_extras.append(sm)
				&"fel_trim":
					var glow := MeshKit.cached("onion:fel_trim", func() -> Mesh:
						var k := MeshKit.new()
						k.add_torus(0.395, 0.425, MeshKit.xf(Vector3(0, 0.3, 0), Vector3.ZERO, Vector3(1, 0.6, 1)), Color.WHITE, 24, 4)
						return k.build())
					var gm := _mesh("FelTrim", _body, glow, Mats.glow(acc, 1.6), false)
					gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					_gear_extras.append(gm)
				&"horn_flames":
					# Purple flames licking up from the horn tips: the warlock's silhouette glows
					# from above instead of reading as a dark blob.
					for side: float in [-1.0, 1.0]:
						var horn := OnionArmor.warlock_horn(side)
						var flame := _build_flame(_body, WARLOCK_FLAME, "HornFlameL" if side < 0.0 else "HornFlameR")
						flame.position = horn[horn.size() - 1] + Vector3(0, 0.02, 0)
						flame.scale = Vector3.ONE
						_flames.append(flame)
						_gear_extras.append(flame)


## Class-specific nodes that do not depend on the worn armour: the warlock's fel flame in the empty
## off hand, the small totem on the shaman's back.
func _build_class_extras() -> void:
	if class_data != null and class_data.headgear == &"horned_hood" and _hands.size() == 2:
		_fel_flame = _build_flame(_hands[1], class_data.accent_color)
	if class_data != null and class_data.headgear == &"tribal_mask":
		var accent := class_data.accent_color
		var totem := MeshKit.cached("onion:back_totem:" + accent.to_html(), func() -> Mesh: return _back_totem_mesh(accent))
		_mesh("BackTotem", _body, totem, Mats.toon_vc(), true)


## The shaman's small totem strapped to the back: a carved post with two faces and a teal crown, tied on by a
## leather strap across the body. Back = +Z (the front is -Z).
static func _back_totem_mesh(accent: Color) -> Mesh:
	var k := MeshKit.new()
	var wood := Color(0.55, 0.37, 0.22)
	var dark := Color(0.27, 0.16, 0.1)
	var tilt := Vector3(-14.0, 0.0, 0.0)  # leans back a little, away from the bulb
	var base := Vector3(0.0, 0.24, 0.52)
	var at := func(local: Vector3) -> Transform3D:
		return Transform3D(Basis.from_euler(Vector3(deg_to_rad(tilt.x), 0, 0)), base) * Transform3D(Basis(), local)
	k.add_cylinder(0.052, 0.062, 0.7, at.call(Vector3(0, 0.35, 0)) as Transform3D, wood, 8)
	for i in 2:
		var y := 0.28 + 0.24 * float(i)
		k.add_box(Vector3(0.13, 0.13, 0.1), at.call(Vector3(0, y, 0)) as Transform3D, wood.lightened(0.08 * float(1 - i)))
		# Face on the side that looks away from the bulb (+Z).
		for side: float in [-1.0, 1.0]:
			k.add_box(Vector3(0.032, 0.03, 0.02), at.call(Vector3(0.03 * side, y + 0.02, 0.055)) as Transform3D, IVORY)
		k.add_box(Vector3(0.07, 0.025, 0.02), at.call(Vector3(0, y - 0.035, 0.055)) as Transform3D, dark)
	k.add_cylinder(0.0, 0.085, 0.2, at.call(Vector3(0, 0.78, 0)) as Transform3D, accent, 8)
	k.add_sphere(0.03, at.call(Vector3(0, 0.9, 0)) as Transform3D, accent.lightened(0.4), 8, 4)
	# Wings.
	for side: float in [-1.0, 1.0]:
		k.add_box(Vector3(0.14, 0.04, 0.05), at.call(Vector3(0.1 * side, 0.46, 0)) as Transform3D, dark)
	# A strap across the back and around the sides (never over the face) and a binding ring on the post.
	var strap := PackedVector3Array()
	for step in 11:
		var a := lerpf(70.0, 290.0, float(step) / 10.0)
		strap.append(bulb_point(lerpf(0.66, 0.26, float(step) / 10.0), a, 0.025))
	k.add_tube(strap, 0.022, 0.022, LEATHER.darkened(0.1), 5)
	k.add_torus(0.045, 0.075, at.call(Vector3(0, 0.12, 0)) as Transform3D, LEATHER, 10, 4)
	return k.build()


## What the head piece does to the onion body: a closed hat hides the sprout, a mask the mouth,
## helms and hoods the eyebrows (the face meshes are cached per variant).
func _apply_head_effects(head: OnionArmor.Part) -> void:
	if head == null:
		return
	if _sprout != null:
		_sprout.visible = not head.hides_sprout
	if _mouth != null:
		_mouth.visible = not head.hides_mouth
	var eyes := _face_mesh() as MeshInstance3D
	if eyes != null:
		eyes.mesh = _eyes_mesh(head.brows)


func _eyes_mesh(brows: bool) -> Mesh:
	var headgear: StringName = class_data.headgear if class_data != null else &""
	return MeshKit.cached("onion:face:%s:%s" % [brows, headgear], func() -> Mesh: return _face_mesh_build(brows, headgear))

func _build_flame(parent: Node3D, color: Color, node_name: String = "FelFlame") -> Node3D:
	var pivot := _node(node_name, parent)
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
