class_name AbilityArea
extends Node3D
## Shared ground effect for abilities (Blizzard, Consecration, Rain of Fire ...): a circle that
## damages / slows enemies and optionally heals allies every [member tick_interval] seconds,
## for [member duration] seconds, optionally following a node. Parent: Arena entities.

var owner_player: Player
var radius := 3.0
var duration := 4.0
var tick_interval := 0.5
## Damage per tick per enemy (already scaled by the ability; target bonuses, Mastery and the
## owner's outgoing multipliers still apply via ProcSystem.deal_raw).
var damage_per_tick := 0.0
var school: StringName = &"physical"
## Slow applied to enemies inside (0..100 %), refreshed every tick.
var slow_pct := 0.0
## Heal per tick for living players inside (incl. the owner).
var heal_per_tick := 0.0
## Stun duration applied once to each enemy on the first tick that hits it (0 = none).
var stun := 0.0
var follow: Node3D
var color := Color(1, 1, 1, 0.5)

var _elapsed := 0.0
var _tick_left := 0.0
var _stunned: Dictionary[int, bool] = {}
var _disc: MeshInstance3D
var _material: StandardMaterial3D


## Creates the area at [param center] under the arena's entity root (or next to the owner).
static func spawn(owner: Player, center: Vector3, p_radius: float, p_duration: float, p_color: Color) -> AbilityArea:
	var area := AbilityArea.new()
	area.owner_player = owner
	area.radius = maxf(0.3, p_radius * (1.0 + (owner.stats.get_raw(Stats.AREA_SIZE) / 100.0 if owner != null else 0.0)))
	area.duration = p_duration
	area.color = p_color
	var parent := WeaponRunner.effects_parent(owner)
	if parent == null:
		return area
	parent.add_child(area)
	area.global_position = Vector3(center.x, 0.0, center.z)
	return area


func _ready() -> void:
	add_to_group(&"ability_areas")
	_disc = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.04
	mesh.radial_segments = 40
	_disc.mesh = mesh
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = Color(color.r, color.g, color.b, 0.0)
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_disc.material_override = _material
	_disc.position.y = 0.06
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_disc)


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if follow != null and is_instance_valid(follow) and follow.is_inside_tree():
		global_position = Vector3(follow.global_position.x, 0.0, follow.global_position.z)
	if _material != null:
		var fade := clampf(minf(_elapsed / 0.2, (duration - _elapsed) / 0.3), 0.0, 1.0)
		var pulse := 0.85 + 0.15 * sin(_elapsed * 6.0)
		_material.albedo_color.a = color.a * fade * pulse
	_tick_left -= delta
	if _tick_left <= 0.0 and _elapsed <= duration:
		_tick_left = tick_interval
		_tick()
	if _elapsed >= duration:
		queue_free()


func _tick() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	var center := global_position
	if damage_per_tick > 0.0 or slow_pct > 0.0 or stun > 0.0:
		for node in EnemyGrid.gather_around(tree, center, radius):
			var e := node as Enemy
			if e == null or e.is_dead():
				continue
			if slow_pct > 0.0:
				e.apply_slow(slow_pct, tick_interval + 0.2)
			if stun > 0.0 and not _stunned.has(e.get_instance_id()):
				_stunned[e.get_instance_id()] = true
				e.apply_stun(stun)
			if damage_per_tick > 0.0 and owner_player != null and is_instance_valid(owner_player) \
					and owner_player.procs != null:
				owner_player.procs.deal_raw(e, damage_per_tick, school, true, &"ability")
	if heal_per_tick > 0.0:
		for node in tree.get_nodes_in_group(&"players"):
			var p := node as Player
			if p != null and p.is_alive() and p.global_position.distance_to(center) <= radius:
				p.heal(heal_per_tick)
