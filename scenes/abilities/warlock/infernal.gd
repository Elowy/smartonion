class_name WarlockInfernal
extends Node3D
## The Infernal of Summon Infernal (GDD 6.4): a fel-fire meteor that crashes onto the target
## point, bursts (fire damage + a stun around the crater, &"pet") and gets up as a rock golem
## that fights for [code]duration[/code] seconds: it walks to the nearest enemy and every
## [code]slam_interval[/code] s (Haste shortens it) smashes the ground in front, hitting every
## enemy within [code]slam_radius[/code] m (&"pet": Demonic Pact).
## Rank V options: Immolation ([code]immolation_share[/code] % of a slam every 0.5 s to enemies
## within [code]immolation_radius[/code] m) and Guardian ([code]taunt_radius[/code] m: keeps
## the enemies around it taunted onto itself).
## Enemies never attack it (only players take contact damage): it cannot die. It crumbles
## when its time is up and leaves at once when the Warlock goes down, at wave start / end,
## when the ability is forgotten and when the Warlock is freed.

const SCHOOL := &"fire"
const FALL_TIME := 0.5
const FALL_HEIGHT := 9.0
## The meteor comes in from the screen's upper right.
const FALL_SLANT := Vector3(2.0, 0.0, -1.5)
const MOVE_SPEED := 4.2
## Looks for enemies this far around itself (else it walks back to the Warlock).
const SEEK_RANGE := 12.0
## Stops this close (edge to edge) to its target; slams land this far in front.
const STOP_GAP := 0.5
const SLAM_REACH := 0.9
const BODY_RADIUS := 0.7
const AURA_TICK := 0.5
const TAUNT_INTERVAL := 1.0
const TAUNT_DURATION := 1.5
const CRUMBLE_TIME := 0.45
## Back to the Warlock when it is further than this (and nothing to fight).
const HOME_DISTANCE := 3.0

var owner_player: Player
var model: WarlockInfernalModel
var params: Dictionary = {}
var landed := false
## Seconds of fighting left (after the landing).
var time_left := 0.0
## Stats (tests): slams done, enemies hit by the landing.
var slams := 0
var impact_hits := 0

var _fall_left := FALL_TIME
var _slam_left := 0.0
var _aura_left := AURA_TICK
var _taunt_left := 0.0
var _crumble_left := -1.0
var _look_dir := Vector3.FORWARD
var _meteor: Node3D
var _leaving := false


## Creates the Infernal for [param p_owner] falling onto [param point]. Not in the tree when
## there is no arena / parent.
static func spawn(p_owner: Player, point: Vector3, p_params: Dictionary) -> WarlockInfernal:
	var inf := WarlockInfernal.new()
	inf.name = "Infernal"
	inf.owner_player = p_owner
	inf.params = p_params
	inf.time_left = maxf(0.5, float(p_params.get("duration", 8.0)))
	inf.model = WarlockInfernalModel.new()
	inf.model.visible = false
	inf.add_child(inf.model)
	inf._meteor = WarlockInfernal._meteor_node()
	inf.add_child(inf._meteor)
	var parent := WeaponRunner.effects_parent(p_owner)
	if parent != null:
		parent.add_child(inf)
		var at := Vector3(point.x, 0.0, point.z)
		if Arena.current != null:
			at = Arena.current.clamp_point(at, 0.6)
		inf.global_position = at
		var face := WeaponRunner.flat(at - p_owner.global_position)
		if face.length_squared() > 0.01:
			inf._look_dir = face.normalized()
		inf._update_meteor()
	return inf


func num(key: String, default: float) -> float:
	var v: Variant = params.get(key, default)
	return float(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else default


## Damage of one slam for the Warlock's [param stats].
static func slam_damage(stats: StatBlock, p_params: Dictionary) -> float:
	return WarlockSpell.damage(stats, p_params, SCHOOL, "", float(p_params.get("slam_interval", 1.0)))


## Damage of the landing burst.
static func impact_damage(stats: StatBlock, p_params: Dictionary) -> float:
	return WarlockSpell.damage(stats, p_params, SCHOOL, "impact_")


static func slam_interval(stats: StatBlock, p_params: Dictionary) -> float:
	return maxf(0.3, float(p_params.get("slam_interval", 1.0)) / maxf(0.2, stats.attack_speed_mult()))


func is_leaving() -> bool:
	return _leaving


## Gone at once – in a puff of fel smoke unless [param quiet] (wave end / start).
func dismiss(quiet: bool = false) -> void:
	if _leaving:
		return
	_leaving = true
	if is_inside_tree() and not quiet:
		Vfx.death_puff(global_position + Vector3.UP * 1.0, WarlockSpell.FEL_COLOR, 1.6)
	queue_free()


func _physics_process(delta: float) -> void:
	if owner_player == null or not is_instance_valid(owner_player) or owner_player.is_queued_for_deletion():
		_leaving = true
		queue_free()
		return
	if _leaving or not is_inside_tree():
		return
	if owner_player.downed:
		dismiss()
		return
	if _crumble_left >= 0.0:
		_crumble_left -= delta
		if _crumble_left <= 0.0:
			_leaving = true
			queue_free()
		return
	if not landed:
		_fall_left -= delta
		_update_meteor()
		if _fall_left <= 0.0:
			land()
		return
	time_left -= delta
	if time_left <= 0.0:
		_crumble()
		return
	var target := _move(delta)
	_slam_left -= delta
	if _slam_left <= 0.0:
		try_slam(target)
	if num("immolation_share", 0.0) > 0.0:
		_aura_left -= delta
		if _aura_left <= 0.0:
			_aura_left += AURA_TICK
			_immolate()
	if num("taunt_radius", 0.0) > 0.0:
		_taunt_left -= delta
		if _taunt_left <= 0.0:
			_taunt_left = TAUNT_INTERVAL
			_taunt()
	if model != null:
		model.set_facing(_look_dir)


## The meteor hits the ground: fire burst + stun around the crater, the golem stands up.
func land() -> void:
	if landed or not is_inside_tree():
		return
	landed = true
	_fall_left = 0.0
	if _meteor != null:
		_meteor.queue_free()
		_meteor = null
	if model != null:
		model.visible = true
		model.set_facing(_look_dir)
	var stats := owner_player.stats
	var radius := WarlockSpell.area(stats, num("impact_radius", 3.0))
	var dmg := impact_damage(stats, params)
	var stun := num("impact_stun", 1.0)
	for e in WarlockSpell.enemies_in_circle(get_tree(), global_position, radius):
		if stun > 0.0:
			e.apply_stun(stun)
		if owner_player.procs != null:
			owner_player.procs.deal_raw(e, dmg, SCHOOL, true, &"pet")
		impact_hits += 1
	WarlockVfx.infernal_slam(global_position, radius, true)
	_slam_left = 0.35


## Smashes the ground in front (resets the timer). False: no enemy within reach.
func try_slam(target: Enemy = null) -> bool:
	if not landed or _leaving or not is_inside_tree():
		return false
	var stats := owner_player.stats
	var radius := WarlockSpell.area(stats, num("slam_radius", 2.0))
	if WarlockSpell.is_live(target):
		var to := WeaponRunner.flat(target.global_position - global_position)
		if to.length_squared() > 0.0001:
			_look_dir = to.normalized()
	var center := global_position + _look_dir * SLAM_REACH
	var victims := WarlockSpell.enemies_in_circle(get_tree(), center, radius)
	if victims.is_empty():
		_slam_left = 0.1
		return false
	_slam_left = slam_interval(stats, params)
	var dmg := slam_damage(stats, params)
	for e in victims:
		if owner_player.procs != null:
			owner_player.procs.deal_raw(e, dmg, SCHOOL, true, &"pet")
	slams += 1
	WarlockVfx.infernal_slam(center, radius)
	if model != null:
		model.set_facing(_look_dir)
		model.play_slam()
	return true


## Walks towards the nearest enemy (or back to the Warlock). Returns that enemy.
func _move(delta: float) -> Enemy:
	var here := global_position
	var target := EnemyGrid.nearest(get_tree(), here, SEEK_RANGE)
	var goal := here
	var stop := 0.0
	if target != null:
		goal = target.global_position
		stop = BODY_RADIUS + target.radius + STOP_GAP
	elif WeaponRunner.flat(owner_player.global_position - here).length() > HOME_DISTANCE:
		goal = owner_player.global_position
		stop = HOME_DISTANCE
	var to := WeaponRunner.flat(goal - here)
	var dist := to.length()
	var moving := 0.0
	if dist > stop + 0.05:
		var step := minf(MOVE_SPEED * delta, dist - stop)
		var next := here + to / dist * step
		if Arena.current != null:
			next = Arena.current.clamp_point(next, 0.6)
		global_position = Vector3(next.x, 0.0, next.z)
		moving = 1.0
	if dist > 0.01:
		_look_dir = to / dist
	if model != null:
		model.set_moving(moving)
	return target


func _immolate() -> void:
	var stats := owner_player.stats
	var radius := WarlockSpell.area(stats, num("immolation_radius", 2.5))
	var dmg := slam_damage(stats, params) * num("immolation_share", 0.0) / 100.0
	if dmg <= 0.0 or owner_player.procs == null:
		return
	for e in WarlockSpell.enemies_in_circle(get_tree(), global_position, radius):
		owner_player.procs.deal_raw(e, dmg, SCHOOL, true, &"pet")


func _taunt() -> void:
	var radius := WarlockSpell.area(owner_player.stats, num("taunt_radius", 0.0))
	for e in WarlockSpell.enemies_in_circle(get_tree(), global_position, radius):
		e.apply_taunt(self, TAUNT_DURATION)


func _crumble() -> void:
	_crumble_left = CRUMBLE_TIME
	if model != null:
		model.play_crumble()
		model.set_moving(0.0)
	Vfx.death_puff(global_position + Vector3.UP * 0.6, Color(0.4, 0.38, 0.35), 1.4)


func _update_meteor() -> void:
	if _meteor == null:
		return
	var t := clampf(1.0 - _fall_left / FALL_TIME, 0.0, 1.0)
	var start := FALL_SLANT + Vector3.UP * FALL_HEIGHT
	_meteor.position = start.lerp(Vector3.UP * 0.5, t * t)
	var dir := (Vector3.UP * 0.5 - start).normalized()
	_meteor.basis = Basis.looking_at(dir, Vector3.FORWARD)


## The falling fel meteor: a hot core, a green flame shell and a long tail (cached materials).
static func _meteor_node() -> Node3D:
	var m := Node3D.new()
	m.name = "Meteor"
	_add_ball(m, 0.32, Mats.glow(Color(0.85, 1.0, 0.6), 3.0), Vector3.ZERO, Vector3.ONE)
	_add_ball(m, 0.55, Mats.unshaded(Color(0.4, 0.95, 0.2, 0.6)), Vector3.ZERO, Vector3.ONE)
	_add_ball(m, 0.4, Mats.unshaded(Color(0.3, 0.8, 0.15, 0.3)), Vector3(0, 0, 0.9), Vector3(1, 1, 3.2))
	_add_ball(m, 0.36, Mats.toon(Color(0.25, 0.22, 0.2)), Vector3(0, 0, -0.05), Vector3.ONE)
	return m


static func _add_ball(parent: Node3D, r: float, material: Material, pos: Vector3, scl: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.cached("warlock:infernal:ball:%.2f" % r, func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = 14
		s.rings = 7
		return s)
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)
