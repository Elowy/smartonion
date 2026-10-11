class_name MageBarrierBubble
extends Node3D
## Look of a Mage's Ice Barrier: a faceted, frosty bubble around the hero with three ice
## shards circling it; it thins out as the absorb shield wears down. Child of the hero.
## Purely visual: it shatters away by itself once the hero has no shield left or goes down;
## [method finish] removes it quietly (wave end, forget).

const SHELL_COLOR := Color(0.62, 0.86, 1.0, 0.16)
const RIM_COLOR := Color(0.8, 0.95, 1.0)
const SHARDS := 3
const RADIUS := 0.85
const CENTER_Y := 0.62

var player: Player
## Shield HP at full strength (the bubble thins with procs.shield_hp / max_amount).
var max_amount := 1.0
var _age := 0.0
var _shell: MeshInstance3D
var _orbit: Node3D


## The bubble on [param p_player] (creates it, or refreshes the existing one).
static func attach(p_player: Player, amount: float) -> MageBarrierBubble:
	if p_player == null:
		return null
	var b := p_player.get_node_or_null(^"IceBarrier") as MageBarrierBubble
	if b == null or b.is_queued_for_deletion():
		b = MageBarrierBubble.new()
		b.name = "IceBarrier"
		b.player = p_player
		b._build()
		p_player.add_child(b)
	b.max_amount = maxf(0.001, amount)
	return b


## The bubble currently on [param p_player] (null = none).
static func of(p_player: Player) -> MageBarrierBubble:
	if p_player == null:
		return null
	var b := p_player.get_node_or_null(^"IceBarrier") as MageBarrierBubble
	return b if b != null and not b.is_queued_for_deletion() else null


## Removes the bubble without the shatter (wave end, forget).
func finish() -> void:
	name = "SpentBarrier"
	queue_free()


func _process(delta: float) -> void:
	_age += delta
	if player == null or not is_instance_valid(player) or player.downed or player.procs == null \
			or player.procs.shield_hp <= 0.0:
		MageFx.shatter(global_position + Vector3.UP * CENTER_Y, 1.0)
		finish()
		return
	var ratio := clampf(player.procs.shield_hp / max_amount, 0.0, 1.0)
	var grow := smoothstep(0.0, 0.18, _age)
	if _shell != null:
		var pulse := 1.0 + 0.03 * sin(_age * 5.0)
		_shell.scale = Vector3.ONE * RADIUS * grow * pulse * lerpf(0.82, 1.0, ratio)
	if _orbit != null:
		_orbit.rotation.y = _age * 2.2
		_orbit.scale = Vector3.ONE * grow * lerpf(0.6, 1.0, ratio)


func _build() -> void:
	_shell = MeshInstance3D.new()
	_shell.name = "Shell"
	_shell.mesh = MeshKit.cached("mage:barrier", func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = 16
		s.rings = 8
		return s)
	_shell.material_override = MageFx.ice_material(SHELL_COLOR)
	_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shell.position.y = CENTER_Y
	_shell.scale = Vector3.ONE * 0.01
	add_child(_shell)
	_orbit = Node3D.new()
	_orbit.name = "Shards"
	_orbit.position.y = CENTER_Y
	_orbit.scale = Vector3.ONE * 0.01
	add_child(_orbit)
	var shard := MeshKit.cached("mage:barrier_shard", func() -> Mesh:
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = 0.09
		c.height = 0.42
		c.radial_segments = 4
		c.rings = 1
		return c)
	var mat := Mats.glow(RIM_COLOR, 1.4)
	for i in SHARDS:
		var a := TAU * float(i) / float(SHARDS)
		var mi := MeshInstance3D.new()
		mi.mesh = shard
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(cos(a), 0.15 * float(i % 2) - 0.05, sin(a)) * RADIUS
		mi.rotation = Vector3(0.0, -a, 0.5)
		_orbit.add_child(mi)
