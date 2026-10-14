class_name FrostBreath
extends EnemyHazard
## Morvain's Frost Breath (GDD 8): a cone of [member angle] degrees and [member range_m] metres
## from the boss towards the nearest hero (the direction is locked when it is laid down). It
## fills up for the telegraph time (1 s), then every hero inside takes [member damage].
## "Spread out." The ground marker is a flat sector (MeshKit.add_arc) with a bright rim.

const FROST := Color(0.5, 0.85, 1.0)

## Cone opening angle (degrees) and length (m) from the apex (this node's position).
var angle := 60.0
var range_m := 7.0
## Unit direction (XZ) the cone points to.
var direction := Vector3.FORWARD
## Heroes the breath hit (tests).
var hits := 0

var _rim: MeshInstance3D
var _fill: MeshInstance3D
var _fill_material: StandardMaterial3D
var _rim_material: StandardMaterial3D


## A cone with its apex at [param apex], pointing along [param dir] (XZ; normalised here).
static func spawn(parent: Node, apex: Vector3, dir: Vector3, p_angle: float, p_range: float,
		p_telegraph: float, p_damage: float, p_source: Node3D = null) -> FrostBreath:
	var h := FrostBreath.new()
	h.name = "FrostBreath"
	h.angle = p_angle
	h.range_m = p_range
	h.radius = p_range
	h.telegraph_time = p_telegraph
	h.damage = p_damage
	h.source = p_source
	h.color = FROST
	var flat := Vector3(dir.x, 0.0, dir.z)
	h.direction = flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD
	place(parent, h, apex)
	return h


## Whether the point [param p] lies in the cone (apex, direction, angle, range), with
## [param margin] m of slack (also at the sides: the margin is turned into an angle).
func contains(p: Vector3, margin: float = 0.0) -> bool:
	var rel := Vector2(p.x - global_position.x, p.z - global_position.z)
	var dist := rel.length()
	if dist > range_m + margin:
		return false
	if dist < 0.001:
		return true
	var axis := Vector2(direction.x, direction.z)
	var off := absf(rel.angle_to(axis))
	var slack := atan2(margin, maxf(dist, margin))
	return off <= deg_to_rad(angle * 0.5) + slack


## Sidestep: perpendicular to the cone's axis, to the side the hero already stands on.
func hazard_push(from: Vector3, margin: float = BOT_MARGIN) -> Vector2:
	if not is_dangerous() or not contains(from, margin):
		return Vector2.ZERO
	var axis := Vector2(direction.x, direction.z)
	var rel := Vector2(from.x - global_position.x, from.z - global_position.z)
	var side := Vector2(-axis.y, axis.x)
	var s := side.dot(rel)
	if absf(s) < 0.05:
		s = 1.0 if side.dot(Vector2(-from.x, -from.z)) >= 0.0 else -1.0  # on the axis: towards the middle
	return side * signf(s) * 2.0


func _build() -> void:
	rotation.y = atan2(-direction.x, -direction.z)
	_fill_material = _sector_material(0.0)
	_rim_material = _sector_material(0.0)
	_rim = MeshInstance3D.new()
	_rim.name = "Rim"
	_rim.mesh = _sector_mesh(angle, range_m, true)
	_rim.material_override = _rim_material
	_rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rim.position.y = GROUND_Y + 0.004
	add_child(_rim)
	_fill = MeshInstance3D.new()
	_fill.name = "Fill"
	_fill.mesh = _sector_mesh(angle, range_m, false)
	_fill.material_override = _fill_material
	_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fill.position.y = GROUND_Y + 0.002
	_fill.scale = Vector3(0.01, 1.0, 0.01)
	add_child(_fill)


func _update_telegraph(progress: float) -> void:
	if _fill == null:
		return
	var pulse := 0.7 + 0.3 * sin(age * (6.0 + 14.0 * progress))
	_rim_material.albedo_color = Color(FROST.r, FROST.g, FROST.b, 0.85 * pulse)
	_fill_material.albedo_color = Color(FROST.r, FROST.g, FROST.b, 0.18 + 0.22 * progress)
	var s := maxf(0.02, progress)
	_fill.scale = Vector3(s, 1.0, s)


func _strike() -> void:
	for hero in living_heroes():
		if contains(hero.global_position, HERO_REACH):
			hits += 1
			hit_hero(hero, damage)
	# A burst of frost along the axis.
	for i in 4:
		var d := range_m * (0.2 + 0.2 * float(i))
		Vfx.explosion(global_position + direction * d + Vector3.UP * 0.1, 0.7 + 0.25 * float(i), FROST)
	_fill.scale = Vector3.ONE
	_fill_material.albedo_color = Color(0.9, 0.97, 1.0, 0.5)
	finish()


func _update_fade(amount: float) -> void:
	if _fill_material == null:
		return
	_fill_material.albedo_color = Color(0.9, 0.97, 1.0, 0.5 * amount)
	_rim_material.albedo_color = Color(FROST.r, FROST.g, FROST.b, 0.85 * amount)


func fade_time() -> float:
	return 0.3


static func _sector_material(alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(FROST.r, FROST.g, FROST.b, alpha)
	m.render_priority = -1
	return m


## The flat sector (apex at the origin, pointing -Z): the filled pie, or just its rim (a thin
## band along the arc and the two edges).
static func _sector_mesh(p_angle: float, p_range: float, rim_only: bool) -> Mesh:
	return MeshKit.cached("hazard:cone:%.1f:%.1f:%s" % [p_angle, p_range, rim_only], func() -> Mesh:
		var k := MeshKit.new()
		var segments := maxi(8, ceili(p_angle / 5.0))
		if not rim_only:
			k.add_arc(0.0, p_range, p_angle, Transform3D(), Color.WHITE, segments)
		else:
			var band := 0.14
			k.add_arc(maxf(0.0, p_range - band), p_range, p_angle, Transform3D(), Color.WHITE, segments)
			for side: float in [-1.0, 1.0]:
				var a := deg_to_rad(p_angle * 0.5) * side
				var dir := Vector3(sin(a), 0.0, -cos(a))
				var xf := Transform3D(Basis.from_euler(Vector3(0.0, -a, 0.0)), dir * p_range * 0.5)
				k.add_box(Vector3(band * 0.7, 0.002, p_range), xf, Color.WHITE)
		return k.build())
