class_name WarlockShadowBoltMissile
extends Projectile
## The Shadow Bolt: a regular player [Projectile] (flight, swept hits, EnemyGrid, optional
## pierce / explosion) whose hits are ability damage instead of weapon hits –
## ProcSystem.deal_raw(..., &"ability") on the Warlock (kill credit, damage meter; no on-hit
## procs, leech, crits or knockback). Its look: a bright violet core in a translucent dark
## shell with a soft halo, two motes circling it and a trailing wisp (shared meshes, cached
## materials).

const CORE := Color(0.82, 0.55, 1.0)
const SHELL := Color(0.3, 0.06, 0.5, 0.55)
const HALO := Color(0.6, 0.25, 1.0, 0.35)
const TRAIL := Color(0.38, 0.1, 0.6, 0.45)
const MODEL_SCALE := 1.35

static var _meshes: Dictionary[String, Mesh] = {}

## Instance ids of the enemies damaged by this bolt, in order (tests).
var victim_ids: Array[int] = []
var school: StringName = &"shadow"


## Fires a bolt from [param from] (world, its height is kept) along [param dir] for
## [param warlock]. [param p_pierce] extra enemies passed through; [param p_blast] > 0 makes
## it explode on impact (m). Added under the arena's entities (or next to the Warlock).
static func fire(warlock: Player, from: Vector3, dir: Vector3, p_damage: float, p_range: float,
		p_speed: float, p_pierce: int = 0, p_blast: float = 0.0) -> WarlockShadowBoltMissile:
	var b := WarlockShadowBoltMissile.new()
	b.name = "ShadowBolt"
	b.team = TEAM_PLAYERS
	b.damage = p_damage
	var d := Vector3(dir.x, 0.0, dir.z)
	b.direction = d.normalized() if d.length_squared() > 0.000001 else Vector3.FORWARD
	b.speed = maxf(0.0, p_speed)
	b.max_range = maxf(0.0, p_range)
	b.pierce = maxi(0, p_pierce)
	b._pierce_left = b.pierce
	b.aoe_radius = maxf(0.0, p_blast)
	b.attacker = warlock
	b.style = &"shadow_bolt"
	b.color = WarlockSpell.SHADOW_COLOR
	b.knockback = 0.0
	b.add_to_group(&"projectiles")
	b._build_shadow_visual()
	var parent := WeaponRunner.effects_parent(warlock)
	if parent != null:
		parent.add_child(b)
		b.global_position = from
	return b


## Replaces the weapon hit of Projectile: ability damage through the Warlock's ProcSystem.
func _apply_hit(body: Node3D, _kb_dir: Vector3, _from_explosion: bool) -> void:
	hit_count += 1
	var e := body as Enemy
	if e == null or attacker == null or not is_instance_valid(attacker):
		return
	var warlock := attacker as Player
	if warlock == null or warlock.procs == null:
		return
	victim_ids.append(e.get_instance_id())
	warlock.procs.deal_raw(e, damage, school, true, &"ability")


func _build_shadow_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	_visual.basis = Basis.looking_at(direction, Vector3.UP)
	_visual.scale = Vector3.ONE * MODEL_SCALE
	add_child(_visual)
	_add(_visual, _sphere(0.13), Mats.glow(CORE, 3.0), Vector3.ZERO, Vector3.ONE)
	_add(_visual, _sphere(0.2), Mats.unshaded(SHELL), Vector3.ZERO, Vector3.ONE)
	_add(_visual, _sphere(0.3), Mats.glow(HALO, 1.2), Vector3.ZERO, Vector3.ONE)
	_add(_visual, _sphere(0.16), Mats.unshaded(TRAIL), Vector3(0, 0, 0.38), Vector3(0.9, 0.9, 2.8))
	# Projectile spins a child named "Spinner" around its Y axis every frame.
	_spinner = Node3D.new()
	_spinner.name = "Spinner"
	_visual.add_child(_spinner)
	for side: float in [-1.0, 1.0]:
		_add(_spinner, _sphere(0.05), Mats.glow(CORE, 2.6), Vector3(0.27 * side, 0.0, 0.0), Vector3.ONE)
	set_process(true)


static func _add(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3, scl: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func _sphere(r: float) -> Mesh:
	var key := "%.3f" % r
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = 12
		m.rings = 6
		_meshes[key] = m
	return _meshes[key]
