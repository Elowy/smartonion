class_name MageFrozen
extends Node3D
## Ice on an enemy frozen by a Mage (Frost Nova, Frost Blink, Shattering Barrier): a clear
## shell and a ring of crystals for as long as the freeze lasts (the freeze itself is the
## enemy's stun). With [member shatter_damage] > 0 (Frost Nova "Shatter") the ice bursts
## when it melts: Frost damage to the enemy and every enemy within [member shatter_radius]
## (the caster's ProcSystem.deal_raw(..., &"ability")). Child of the enemy – freed with it;
## an enemy that dies frozen does not shatter. One per caster per enemy: a new freeze
## extends it.

const EPSILON := 0.0001
const SHELL_COLOR := Color(0.7, 0.9, 1.0, 0.32)
const CRYSTAL_COLOR := Color(0.72, 0.92, 1.0)
const CRYSTALS := 5

var caster: Player
var enemy: Enemy
## Seconds of ice left.
var left := 1.5
var shatter_damage := 0.0
var shatter_radius := 1.5
var shattered := false
## Enemies the shatter damaged (tests).
var shatter_hits := 0

var _age := 0.0
var _body: Node3D


static func apply(e: Enemy, p_caster: Player, duration: float, p_shatter_damage: float = 0.0,
		p_shatter_radius: float = 1.5) -> MageFrozen:
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
	ice.left = maxf(ice.left, duration)
	if p_shatter_damage > 0.0:
		ice.shatter_radius = maxf(ice.shatter_radius, p_shatter_radius) if ice.shatter_damage > 0.0 \
				else p_shatter_radius
		ice.shatter_damage = maxf(ice.shatter_damage, p_shatter_damage)
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


## Bursts the ice now: shatter damage around the enemy (once).
func shatter() -> void:
	if shattered or not MageSpell.is_live(enemy):
		return
	shattered = true
	var center := enemy.global_position
	if is_instance_valid(caster) and caster.procs != null:
		for e in MageSpell.enemies_in(enemy.get_tree(), center, shatter_radius):
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
	set_physics_process(false)
	set_process(false)
	name = "SpentIce"
	queue_free()


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
