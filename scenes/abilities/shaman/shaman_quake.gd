class_name ShamanQuake
extends AbilityArea
## The ground area of Rumbling Earth (M8): an [AbilityArea] that ticks Nature damage and slows, and on the
## FIRST tick that touches an enemy rolls its [member stun_chance] once for it (one RunState.rng draw per
## enemy, in EnemyGrid order; a hit enemy that was not stunned is never rolled again). Quake ticks are not
## Storm Echo eligible.

## % chance (0..100) an enemy inside is stunned for [member stun_time] seconds on its first tick.
var stun_chance := 0.0
var stun_time := 1.2
## Instance ids of the enemies that were rolled (tests).
var rolled: Dictionary[int, bool] = {}


## Opens the quake at [param center] under the arena's entity root (or next to the owner): the same
## radius / duration rules as [method AbilityArea.spawn]. Not in the tree without a parent.
static func open(p_owner: Player, center: Vector3, p_radius: float, p_duration: float, p_color: Color) -> ShamanQuake:
	var area := ShamanQuake.new()
	area.owner_player = p_owner
	area.radius = maxf(0.3, p_radius * (1.0 + (p_owner.stats.get_raw(Stats.AREA_SIZE) / 100.0 if p_owner != null else 0.0)))
	area.duration = p_duration
	area.color = p_color
	var parent := WeaponRunner.effects_parent(p_owner)
	if parent == null:
		return area
	parent.add_child(area)
	area.global_position = Vector3(center.x, 0.0, center.z)
	return area


func _ready() -> void:
	super._ready()
	ShamanAreaFx.attach(self, ShamanAreaFx.Kind.RUBBLE)


func _tick() -> void:
	if not is_inside_tree():
		return
	if stun_chance > 0.0 and stun_time > 0.0:
		_roll_stuns()
	super._tick()


func _roll_stuns() -> void:
	var center := global_position
	for node in EnemyGrid.gather_around(get_tree(), center, radius):
		var e := node as Enemy
		if e == null or e.is_dead() or rolled.has(e.get_instance_id()):
			continue
		var reach := radius + e.radius
		var dx := e.global_position.x - center.x
		var dz := e.global_position.z - center.z
		if dx * dx + dz * dz > reach * reach:
			continue
		rolled[e.get_instance_id()] = true
		if RunState.rng.randf() * 100.0 < stun_chance:
			e.apply_stun(stun_time)
