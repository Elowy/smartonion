class_name MageFrozen
extends Node3D
## Ice on an enemy frozen by a Mage (Frost Nova, Frost Blink, Shattering Barrier): a clear
## shell and a ring of crystals for as long as the freeze lasts (the freeze itself is the
## enemy's stun). With [member shatter_damage] > 0 (Frost Nova "Shatter") the ice bursts
## when it melts: Frost damage to the enemy and every enemy within [member shatter_radius]
## (the caster's ProcSystem.deal_raw(..., &"ability")). The ice of one nova shares a
## [MageFrozen.ShatterGroup]: each enemy takes that nova's shatter at most once, however many
## frozen neighbours burst around it. Child of the enemy – freed with it; an enemy that dies
## frozen does not shatter. One per caster per enemy: a new freeze extends it.
##
## "Frozen" (M5 talents – Ice Lance, Flash Freeze): [method is_frozen] answers in O(1) without
## allocating from a static count of live ice per enemy (instance id -> ice nodes of any Mage).
## A new ice node counts in [method apply]; it stops counting exactly once – when it melts
## ([method _end], after its shatter, so the enemy is still frozen during its own shatter) or
## when it leaves the tree first (the enemy was freed / despawned). The count remembers
## RunState.run_serial and clears itself when a new run started, so nothing leaks between runs
## or tests.

const EPSILON := 0.0001
const SHELL_COLOR := Color(0.7, 0.9, 1.0, 0.32)
const CRYSTAL_COLOR := Color(0.72, 0.92, 1.0)
const CRYSTALS := 5


## Enemies the shatters of one Frost Nova already hit (instance ids), shared by its ice.
class ShatterGroup extends RefCounted:
	var hit: Dictionary[int, bool] = {}


## Enemy instance id -> live ice nodes on it ([method is_frozen]); keys are erased at 0.
static var _frozen: Dictionary[int, int] = {}
## RunState.run_serial the counts belong to.
static var _frozen_serial := -1

var caster: Player
var enemy: Enemy
## Seconds of ice left.
var left := 1.5
var shatter_damage := 0.0
var shatter_radius := 1.5
## Shared with the rest of the nova's ice (null: this ice shatters on its own).
var shatter_group: ShatterGroup
var shattered := false
## Enemies the shatter damaged (tests).
var shatter_hits := 0

var _age := 0.0
var _body: Node3D
## This ice is in the [method is_frozen] count (for [member _counted_id], run
## [member _counted_serial]); cleared when it stops counting.
var _counted := false
var _counted_id := 0
var _counted_serial := 0


## True while [param e] carries live ice of any Mage (O(1), no allocation; null / freed → false).
static func is_frozen(e: Node3D) -> bool:
	if e == null or not is_instance_valid(e):
		return false
	if _frozen_serial != RunState.run_serial:
		_reset_count()
	return _frozen.has(e.get_instance_id())


## Enemies counted as frozen right now (tests).
static func frozen_count() -> int:
	if _frozen_serial != RunState.run_serial:
		_reset_count()
	return _frozen.size()


static func apply(e: Enemy, p_caster: Player, duration: float, p_shatter_damage: float = 0.0,
		p_shatter_radius: float = 1.5, p_group: ShatterGroup = null) -> MageFrozen:
	if not MageSpell.is_live(e) or duration <= 0.0:
		return null
	var key := "MageFrozen%d" % (p_caster.get_instance_id() if p_caster != null else 0)
	var ice := e.get_node_or_null(NodePath(key)) as MageFrozen
	if ice == null or ice.is_queued_for_deletion():
		ice = MageFrozen.new()
		ice.name = key
		ice.caster = p_caster
		ice.enemy = e
		ice.left = 0.0
		e.add_child(ice)
		ice._build(e.radius)
		ice._count_in(e.get_instance_id())
	ice.left = maxf(ice.left, duration)
	if p_shatter_damage > 0.0:
		ice.shatter_radius = maxf(ice.shatter_radius, p_shatter_radius) if ice.shatter_damage > 0.0 \
				else p_shatter_radius
		ice.shatter_damage = maxf(ice.shatter_damage, p_shatter_damage)
		if p_group != null:
			ice.shatter_group = p_group
	return ice


func _physics_process(delta: float) -> void:
	if is_queued_for_deletion():
		return
	if not MageSpell.is_live(enemy):
		_end()
		return
	left -= delta
	if left > EPSILON:
		return
	if shatter_damage > 0.0:
		shatter()
	_end()


## Bursts the ice now: shatter damage around the enemy (once), skipping enemies another ice
## of the same nova already shattered on.
func shatter() -> void:
	if shattered or not MageSpell.is_live(enemy):
		return
	shattered = true
	var center := enemy.global_position
	if shatter_group == null:
		shatter_group = ShatterGroup.new()
	if is_instance_valid(caster) and caster.procs != null:
		for e in MageSpell.enemies_in(enemy.get_tree(), center, shatter_radius):
			var id := e.get_instance_id()
			if shatter_group.hit.has(id):
				continue
			shatter_group.hit[id] = true
			if caster.procs.deal_raw(e, shatter_damage, MageSpell.FROST, true, &"ability") > 0.0:
				shatter_hits += 1
	MageFx.shatter(center + Vector3.UP * Enemy.BODY_CENTER_HEIGHT, shatter_radius)


func _process(delta: float) -> void:
	_age += delta
	if _body != null:
		# Crystals grow in quickly and shrink away in the last moments.
		var s := clampf(_age / 0.12, 0.0, 1.0) * clampf(left / 0.25, 0.0, 1.0)
		_body.scale = Vector3.ONE * maxf(0.01, s)


func _end() -> void:
	_count_out()
	set_physics_process(false)
	set_process(false)
	name = "SpentIce"
	queue_free()


## The enemy was freed / despawned while frozen (or the ice was removed): stop counting.
func _exit_tree() -> void:
	_count_out()


func _count_in(enemy_id: int) -> void:
	if _frozen_serial != RunState.run_serial:
		_reset_count()
	_counted = true
	_counted_id = enemy_id
	_counted_serial = _frozen_serial
	_frozen[enemy_id] = int(_frozen.get(enemy_id, 0)) + 1


## Takes this ice out of the count (once; ice of an earlier run is ignored).
func _count_out() -> void:
	if not _counted:
		return
	_counted = false
	if _counted_serial != _frozen_serial or not _frozen.has(_counted_id):
		return
	var n := _frozen[_counted_id] - 1
	if n > 0:
		_frozen[_counted_id] = n
	else:
		_frozen.erase(_counted_id)


static func _reset_count() -> void:
	_frozen.clear()
	_frozen_serial = RunState.run_serial


func _build(body_radius: float) -> void:
	_body = Node3D.new()
	_body.name = "Ice"
	_body.scale = Vector3.ONE * 0.01
	add_child(_body)
	var r := maxf(0.3, body_radius)
	var shell := MeshInstance3D.new()
	shell.name = "Shell"
	shell.mesh = MeshKit.cached("mage:ice_shell", func() -> Mesh:
		var c := CylinderMesh.new()
		c.top_radius = 0.82
		c.bottom_radius = 1.0
		c.height = 1.0
		c.radial_segments = 7
		c.rings = 1
		return c)
	shell.material_override = Mats.unshaded(SHELL_COLOR)
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.scale = Vector3(r + 0.12, 1.15, r + 0.12)
	shell.position.y = 0.58
	_body.add_child(shell)
	var crystal := MeshKit.cached("mage:ice_crystal", func() -> Mesh:
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = 0.11
		c.height = 0.7
		c.radial_segments = 4
		c.rings = 1
		return c)
	var mat := Mats.glow(CRYSTAL_COLOR, 1.1)
	for i in CRYSTALS:
		var a := TAU * float(i) / float(CRYSTALS) + 0.4
		var mi := MeshInstance3D.new()
		mi.mesh = crystal
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var out := Vector3(cos(a), 0.0, sin(a))
		mi.position = out * (r + 0.05) + Vector3.UP * (0.28 + 0.12 * float(i % 2))
		# Lean outwards.
		mi.basis = Basis(out.cross(Vector3.UP).normalized(), -0.45) * Basis.from_scale(Vector3.ONE * (0.8 + 0.25 * float(i % 3)))
		_body.add_child(mi)
