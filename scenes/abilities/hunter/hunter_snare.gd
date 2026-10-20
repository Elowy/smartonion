class_name HunterSnare
extends Node3D
## A snare laid by Blast Snare: a toothed iron trap on the ground. It arms after
## [code]arm_time[/code] seconds (the light in its heart turns red) and bursts the moment an enemy
## body touches its trigger circle: Fire damage to everything in the blast circle
## (ProcSystem.deal_raw, source &"ability": no crits) and a slow. It fizzles after
## [code]lifetime[/code] seconds, when the Hunter lays a newer snare beyond its limit, at the wave
## start / end and with the Hunter. Item / talent riders of the burst (all from the numbers the
## ability snapshots into [member numbers]):
##   ember_*   – burning ground left after the burst (AbilityArea: ember_damage per ember_tick for
##               ember_duration seconds),
##   scatter   – that many smaller bombs thrown scatter_range m around the burst, each
##               scatter_damage in a scatter_radius circle (no RNG: spread evenly round the circle).
## The snare is not targetable and does not hurt the heroes.

const FIRE_COLOR := Color(1.0, 0.5, 0.15)
const SCAN_INTERVAL := 0.1
const IRON := Color(0.42, 0.42, 0.48)
const IRON_DARK := Color(0.24, 0.24, 0.3)

var owner_player: Player
## Burst numbers (see Blast Snare): damage, radius, base_radius, trigger_radius, arm_time, lifetime,
## slow, slow_duration, ember_duration, ember_damage, ember_tick, scatter, scatter_damage,
## scatter_radius, scatter_range.
var numbers: Dictionary = {}
var age := 0.0
var armed := false
var burst_done := false
## Enemies the burst hit (tests).
var victims := 0

var _scan_left := 0.0
var _light: MeshInstance3D
var _gone := false


## Lays a snare for [param p_owner] at [param pos] (ground) with [param p_numbers]. Not in the
## tree without an effects parent.
static func lay(p_owner: Player, pos: Vector3, p_numbers: Dictionary) -> HunterSnare:
	var s := HunterSnare.new()
	s.name = "HunterSnare"
	s.owner_player = p_owner
	s.numbers = p_numbers.duplicate()
	var parent := WeaponRunner.effects_parent(p_owner)
	if parent != null:
		parent.add_child(s)
		s.global_position = Vector3(pos.x, 0.0, pos.z)
	return s


func is_armed() -> bool:
	return armed and not burst_done


func is_active() -> bool:
	return not burst_done and not _gone and not is_queued_for_deletion()


func _ready() -> void:
	add_to_group(&"hunter_snares")
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = body_mesh()
	body.material_override = Mats.toon_vc()
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body)
	_light = MeshInstance3D.new()
	_light.name = "Light"
	_light.mesh = MeshKit.cached("hunter:snare_light", func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = 0.1
		s.height = 0.2
		s.radial_segments = 8
		s.rings = 4
		return s)
	_light.material_override = Mats.glow(Color(1.0, 0.2, 0.1), 3.0)
	_light.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_light.position.y = 0.14
	_light.visible = false
	add_child(_light)


func _physics_process(delta: float) -> void:
	step(delta)


## One physics step (tests drive it directly).
func step(delta: float) -> void:
	if burst_done or _gone:
		return
	if owner_player == null or not is_instance_valid(owner_player):
		fizzle(true)
		return
	age += delta
	if age >= float(numbers.get("lifetime", 15.0)):
		fizzle()
		return
	if not armed:
		if age >= float(numbers.get("arm_time", 0.5)):
			armed = true
			if _light != null:
				_light.visible = true
		return
	_scan_left -= delta
	if _scan_left > 0.0:
		return
	_scan_left = SCAN_INTERVAL
	if not is_inside_tree():
		return
	var trigger := float(numbers.get("trigger_radius", 1.2))
	if not GeneralKit.enemies_around(get_tree(), global_position, trigger).is_empty():
		burst()


## The snare goes off now (also called by tests).
func burst() -> void:
	if burst_done or _gone or not is_inside_tree():
		return
	burst_done = true
	var at := global_position
	var radius := float(numbers.get("radius", 2.5))
	var damage := float(numbers.get("damage", 0.0))
	var slow := float(numbers.get("slow", 0.0))
	var slow_duration := float(numbers.get("slow_duration", 3.0))
	Vfx.explosion(at + Vector3.UP * 0.2, radius, FIRE_COLOR)
	victims = _blast(at, radius, damage, slow, slow_duration)
	var ember := float(numbers.get("ember_duration", 0.0))
	if ember > 0.0 and float(numbers.get("ember_damage", 0.0)) > 0.0:
		_ember(at, ember)
	var bombs := maxi(0, roundi(float(numbers.get("scatter", 0.0))))
	if bombs > 0:
		_scatter(at, bombs)
	queue_free()


## Fire damage to every enemy whose body touches the circle; returns how many were hit.
func _blast(at: Vector3, radius: float, damage: float, slow: float, slow_duration: float) -> int:
	var hit := 0
	for e in GeneralKit.enemies_around(get_tree(), at, radius):
		if owner_player != null and is_instance_valid(owner_player) and owner_player.procs != null:
			owner_player.procs.deal_raw(e, damage, HunterKit.FIRE, true, &"ability")
		hit += 1
		if slow > 0.0 and HunterKit.is_live(e):
			e.apply_slow(minf(slow, 90.0), slow_duration)
	return hit


## Burning ground where the snare was.
func _ember(at: Vector3, duration: float) -> void:
	var area := AbilityArea.spawn(owner_player, at, float(numbers.get("base_radius", 2.5)), duration, Color(1.0, 0.4, 0.1, 0.3))
	if not area.is_inside_tree():
		area.free()
		return
	area.school = HunterKit.FIRE
	area.tick_interval = maxf(0.1, float(numbers.get("ember_tick", 0.5)))
	area.damage_per_tick = float(numbers.get("ember_damage", 0.0))


## Smaller bombs thrown round the burst (Firebug Bombs).
func _scatter(at: Vector3, bombs: int) -> void:
	var range_m := float(numbers.get("scatter_range", 3.0))
	var radius := float(numbers.get("scatter_radius", 1.5))
	var damage := float(numbers.get("scatter_damage", 0.0))
	for i in bombs:
		var angle := TAU * float(i) / float(bombs) + 0.5
		var spot := at + Vector3(cos(angle), 0.0, sin(angle)) * range_m
		Vfx.explosion(spot + Vector3.UP * 0.2, radius, FIRE_COLOR)
		_blast(spot, radius, damage, 0.0, 0.0)


## The snare vanishes without a burst (lifetime over, pushed out by a newer one, wave hooks).
func fizzle(quiet: bool = false) -> void:
	if burst_done or _gone:
		return
	_gone = true
	if not quiet and is_inside_tree():
		Vfx.death_puff(global_position + Vector3.UP * 0.1, IRON, 0.5)
	queue_free()


## The trap: a flat iron ring with eight teeth and a pressure plate (one cached vertex-coloured mesh).
static func body_mesh() -> Mesh:
	return MeshKit.cached("hunter:snare_body", func() -> Mesh:
		var k := MeshKit.new()
		k.add_torus(0.34, 0.48, MeshKit.xf(Vector3(0, 0.05, 0), Vector3.ZERO, Vector3(1, 0.5, 1)), IRON, 18, 6)
		k.add_cylinder(0.3, 0.3, 0.05, MeshKit.xf(Vector3(0, 0.04, 0)), IRON_DARK, 14)
		for i in 8:
			var a := TAU * float(i) / 8.0
			var p := Vector3(cos(a), 0.0, sin(a))
			k.add_segment(p * 0.43 + Vector3(0, 0.05, 0), p * 0.3 + Vector3(0, 0.3, 0), 0.05, 0.0, IRON.lightened(0.2), 5)
		k.add_cylinder(0.1, 0.12, 0.07, MeshKit.xf(Vector3(0, 0.09, 0)), IRON_DARK.lightened(0.1), 8)
		return k.build())
