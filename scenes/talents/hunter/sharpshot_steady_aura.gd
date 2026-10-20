class_name HunterSharpshotSteadyAura
extends TalentEffect
## Steady Aura – the Hunter Sharpshot capstone (design_hunter 4.2): every living hero within
## [code]radius[/code] (8) m (XZ) of the Hunter – the Hunter included – deals [code]damage_pct[/code]
## (+5) % more damage, on every damage source: a Player.damage_mults entry under [member key]
## ("hunter_steady_aura:<Hunter's slot index>": one key per Hunter, so two Hunters stack on the
## heroes both reach, like two Battle Shouts). The other half of the capstone (Long Shot recharges
## twice as fast) is a data entry next to this script.
##
## Re-checked every [code]interval[/code] (0.25) s while a wave runs: a hero that walks out of range
## or is downed loses the entry, one that walks in gets it. Everything is dropped (every hero's key,
## the ring) when the Hunter goes down, at wave start / end and on teardown. Allies who leave the
## game are forgotten. A faint ring under the Hunter shows the radius. No RNG; passive for bots.
##
## Params (not rank-scaled; capstone, rank 1): radius, damage_pct, interval.

const KEY_PREFIX := "hunter_steady_aura"
const RING_COLOR := Color(0.4, 0.7, 1.0, 0.42)
const RING_Y := 0.03
## Ring band as fractions of the quad's half size (a thin edge of 0.2 m at 8 m and a very faint
## fill) and the weight of the dark / white edge strokes that keep it readable on any ground.
const RING_INNER := 0.975
const RING_OUTER := 1.0
const RING_FILL := 0.1
const RING_STROKE := 0.4

## The Player.damage_mults key of this Hunter's aura.
var key: StringName = &""

var _radius := 8.0
var _pct := 5.0
var _interval := 0.25
var _mult := 1.05
var _clock := 0.0
## True from the wave start to the wave end.
var _in_wave := false
## Instance id -> hero holding the buff (values may be freed meanwhile: untyped on purpose).
var _held: Dictionary = {}
var _ring: MeshInstance3D


func setup(p_player: Player, p_rank: int, p_params: Dictionary) -> void:
	super(p_player, p_rank, p_params)
	_radius = maxf(0.0, num("radius", 8.0))
	_pct = num("damage_pct", 5.0)
	_interval = maxf(0.02, num("interval", 0.25))
	_mult = 1.0 + _pct / 100.0
	key = key_for(p_player)


## The damage key of [param p]'s aura ("hunter_steady_aura:<slot index>").
static func key_for(p: Player) -> StringName:
	if p != null and p.slot != null:
		return StringName("%s:%d" % [KEY_PREFIX, p.slot.index])
	return StringName("%s:%d" % [KEY_PREFIX, p.get_instance_id() if p != null else 0])


## Heroes holding the buff right now (tests, UI).
func buffed() -> Array[Player]:
	var out: Array[Player] = []
	for id: int in _held:
		var v: Variant = _held[id]
		if is_instance_valid(v):
			out.append(v as Player)
	return out


## True while the aura is on (a wave is running and the Hunter is up).
func is_active() -> bool:
	return _in_wave and player != null and is_instance_valid(player) and player.is_alive()


func tick(delta: float) -> void:
	if not _in_wave or player == null or not is_instance_valid(player):
		return
	if not player.is_alive():
		if not _held.is_empty() or _ring != null:
			_release()
		_clock = 0.0
		return
	_clock -= delta
	if _clock > 0.0:
		return
	_clock += _interval
	if _clock <= 0.0:
		_clock = _interval
	_refresh()


func begin_wave() -> void:
	_release()
	_in_wave = true
	_clock = 0.0


func end_wave() -> void:
	_in_wave = false
	_release()


func teardown() -> void:
	_in_wave = false
	_release()


func describe() -> String:
	if not is_active():
		return "Steady Aura: +%s%% damage within %s m" % [TalentData.format_number(_pct), TalentData.format_number(_radius)]
	return "Steady Aura: %d heroes inside" % buffed().size()


## Gives the buff to every living hero within the radius and takes it from the others.
func _refresh() -> void:
	if not player.is_inside_tree():
		return
	var here := player.global_position
	var r2 := _radius * _radius
	for node in player.get_tree().get_nodes_in_group(&"players"):
		var hero := node as Player
		if hero == null or not hero.is_inside_tree():
			continue
		var id := hero.get_instance_id()
		var d := hero.global_position - here
		var inside := hero.is_alive() and d.x * d.x + d.z * d.z <= r2
		if inside:
			hero.damage_mults[key] = _mult
			_held[id] = hero
		elif _held.has(id):
			hero.damage_mults.erase(key)
			_held.erase(id)
	# Heroes freed meanwhile.
	for id: int in _held.keys():
		if not is_instance_valid(_held[id]):
			_held.erase(id)
	_show_ring()


## Takes the buff from everyone and frees the ring.
func _release() -> void:
	for id: int in _held:
		var v: Variant = _held[id]
		if is_instance_valid(v):
			(v as Player).damage_mults.erase(key)
	_held.clear()
	if player != null and is_instance_valid(player):
		player.damage_mults.erase(key)
	if _ring != null and is_instance_valid(_ring):
		_ring.queue_free()
	_ring = null


## The faint circle of the radius under the Hunter (a child of the hero; one draw call).
func _show_ring() -> void:
	if _ring != null and is_instance_valid(_ring):
		return
	var quad := PlaneMesh.new()
	quad.size = Vector2(2.0 * _radius, 2.0 * _radius)
	_ring = MeshInstance3D.new()
	_ring.name = "SteadyAuraRing"
	_ring.mesh = quad
	_ring.material_override = Mats.ring()
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position = Vector3(0.0, RING_Y, 0.0)
	player.add_child(_ring)
	Mats.set_ring(_ring, RING_COLOR, RING_INNER, RING_OUTER, RING_FILL)
	Mats.set_ring_stroke(_ring, RING_STROKE)
