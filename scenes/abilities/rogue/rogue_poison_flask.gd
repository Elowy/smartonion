class_name RoguePoisonFlask
extends Node3D
## The Poison Bomb vial in flight: a green glass flask on a lob from the Rogue to the target
## spot (physics ticks, so the landing time is deterministic). On landing it shatters into the
## poison cloud (an [AbilityArea] with a [RoguePoisonCloudVfx]) and, with
## [member impact_damage] > 0, bursts on everything inside first.
## In the group &"ability_areas": the wave end removes a vial still in the air.

const ARC_HEIGHT := 2.2
const GLASS := Color(0.45, 0.95, 0.35)
const CORK := Color(0.45, 0.3, 0.18)

var owner_player: Player
var from := Vector3.ZERO
var to := Vector3.ZERO
var flight := 0.45
var radius := 2.5
var duration := 4.0
var tick := 0.5
var damage_per_tick := 0.0
var slow_pct := 0.0
var impact_damage := 0.0
## The cloud it left (null while flying) – tests.
var cloud: AbilityArea

var _elapsed := 0.0
var _body: Node3D


## Lobs a vial of [param player] from [param p_from] to [param p_to] (ground points) landing
## after [param p_flight] s. Null when there is no place to put it.
static func throw(player: Player, p_from: Vector3, p_to: Vector3, p_flight: float) -> RoguePoisonFlask:
	var parent := WeaponRunner.effects_parent(player)
	if parent == null:
		return null
	var f := RoguePoisonFlask.new()
	f.name = "PoisonFlask"
	f.owner_player = player
	f.from = Vector3(p_from.x, Player.CHEST_HEIGHT, p_from.z)
	f.to = Vector3(p_to.x, 0.15, p_to.z)
	f.flight = maxf(0.05, p_flight)
	f.add_to_group(&"ability_areas")
	parent.add_child(f)
	f.global_position = f.from
	return f


func _ready() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	_add(_sphere(0.16), Mats.glow(Color(GLASS, 0.85), 1.4), Vector3.ZERO)
	_add(_cylinder(0.06, 0.12), Mats.toon(GLASS.darkened(0.3)), Vector3(0, 0.17, 0))
	_add(_cylinder(0.065, 0.06), Mats.toon(CORK), Vector3(0, 0.25, 0))


func _physics_process(delta: float) -> void:
	_elapsed += delta
	var t := clampf(_elapsed / flight, 0.0, 1.0)
	var pos := from.lerp(to, t)
	pos.y += ARC_HEIGHT * 4.0 * t * (1.0 - t)
	global_position = pos
	if _body != null:
		_body.rotation.z = -t * TAU * 1.5
	if t >= 1.0:
		_land()


func _land() -> void:
	set_physics_process(false)
	var player := owner_player if owner_player != null and is_instance_valid(owner_player) else null
	var center := Vector3(to.x, 0.0, to.z)
	if player != null and player.is_inside_tree():
		cloud = AbilityArea.spawn(player, center, radius, duration, RoguePoisonBomb.CLOUD_COLOR)
		if cloud.is_inside_tree():
			cloud.school = RoguePoisonBomb.SCHOOL
			cloud.tick_interval = tick
			cloud.damage_per_tick = damage_per_tick
			cloud.slow_pct = slow_pct
			cloud.add_child(RoguePoisonCloudVfx.create(cloud.radius, duration))
			if impact_damage > 0.0 and player.procs != null:
				for e in RogueUtil.enemies_around(get_tree(), center, cloud.radius):
					player.procs.deal_raw(e, impact_damage, RoguePoisonBomb.SCHOOL, true, &"ability")
		else:
			cloud.free()
			cloud = null
		Vfx.explosion(center + Vector3.UP * 0.2, maxf(0.8, radius * (0.9 if impact_damage > 0.0 else 0.55)),
				RogueVfx.POISON_COLOR)
	queue_free()


func _add(mesh: Mesh, mat: Material, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(mi)


static func _sphere(r: float) -> Mesh:
	return MeshKit.cached("rogue:flask_sphere:%.2f" % r, func() -> Mesh:
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = 12
		m.rings = 6
		return m)


static func _cylinder(r: float, h: float) -> Mesh:
	return MeshKit.cached("rogue:flask_cyl:%.3f:%.3f" % [r, h], func() -> Mesh:
		var m := CylinderMesh.new()
		m.top_radius = r
		m.bottom_radius = r
		m.height = h
		m.radial_segments = 8
		m.rings = 1
		return m)
