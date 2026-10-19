class_name RogueCombatAdrenalineRush
extends TalentEffect
## Adrenaline Rush – the Rogue Combat capstone (GDD 7.5, talents_rogue.md 2.4): while at least
## min_enemies (3) living enemies are within radius (5) m of the Rogue, its Energy is generated
## regen_pct (50) % faster – a Resource Regen stat source on the hero ([constant SELF_KEY]: the
## regeneration AND every Energy gain – Combat Potency, Venomous Wounds, Shadow Focus; Combo
## Points are pips and stay exact) – and the other living heroes within ally_radius (8) m gain
## ally_haste (10) % Haste (a stat source per Rogue, "rogue_combat_adrenaline_rush:<slot>", so
## two Combat Rogues stack like two Battle Shouts).
##
## The crowd is counted every interval (0.25) s (RogueUtil.enemies_within – no RNG); once the
## pack thins out the rush lingers linger (1) s before it ends, so it does not flicker. The
## allies are re-checked on the same clock while it runs (a hero who walks out of range or goes
## down loses the Haste). GDD deviation (deviations.md): +50% instead of doubled – Fan of Knives
## is Energy-bound, doubling ≈ +70% fan damage.
## Ends (every source removed, the ring freed) when the Rogue goes down, at wave start / end and
## on teardown. Passive for bots.
##
## Params (not rank-scaled; capstone): min_enemies, radius, regen_pct, ally_radius, ally_haste,
## interval, linger, text_interval (s between two "Adrenaline Rush" texts).

const SELF_KEY := &"rogue_combat_adrenaline_rush"
const COLOR := Color(1.0, 0.9, 0.2)
const RING_ALPHA := 0.35
const RING_RADIUS := 1.2
const TEXT := "Crowd Surge"

## True while the rush is on (tests, UI).
var active := false

var _min_enemies := 3
var _radius := 5.0
var _regen_pct := 50.0
var _ally_radius := 8.0
var _ally_haste := 10.0
var _interval := 0.25
var _linger := 1.0
var _text_interval := 8.0
var _ally_key := SELF_KEY
var _clock := 0.0
var _linger_left := 0.0
var _text_cd := 0.0
## Allies currently carrying this Rogue's Haste source (instance id -> hero).
var _allies: Dictionary[int, Player] = {}
var _ring: MeshInstance3D


func setup(p_player: Player, p_rank: int, p_params: Dictionary) -> void:
	super(p_player, p_rank, p_params)
	_min_enemies = maxi(1, roundi(num("min_enemies", 3.0)))
	_radius = maxf(0.0, num("radius", 5.0))
	_regen_pct = num("regen_pct", 50.0)
	_ally_radius = maxf(0.0, num("ally_radius", 8.0))
	_ally_haste = num("ally_haste", 10.0)
	_interval = maxf(0.05, num("interval", 0.25))
	_linger = maxf(0.0, num("linger", 1.0))
	_text_interval = maxf(0.0, num("text_interval", 8.0))
	var index := player.slot.index if player != null and player.slot != null else 0
	_ally_key = StringName("%s:%d" % [SELF_KEY, index])


func tick(delta: float) -> void:
	_text_cd -= delta
	if player == null or not is_instance_valid(player):
		return
	if not player.is_alive():
		if active:
			_deactivate()
		_clock = 0.0
		return
	_clock -= delta
	if _clock > 0.0:
		return
	_clock += _interval
	if _clock <= 0.0:
		_clock = _interval
	var crowded := RogueUtil.enemies_within(player, _radius) >= _min_enemies
	if crowded:
		_linger_left = _linger
		if not active:
			_activate()
	elif active:
		_linger_left -= _interval
		if _linger_left <= 0.0:
			_deactivate()
	if active:
		_refresh_allies()


func begin_wave() -> void:
	_reset()


func end_wave() -> void:
	_reset()


func teardown() -> void:
	_reset()


func describe() -> String:
	if active:
		return "Crowd Surge: active"
	return "Crowd Surge: needs %d enemies within %s m" % [_min_enemies, TalentData.format_number(_radius)]


## Heroes currently given this Rogue's Haste (tests).
func buffed_allies() -> Array[Player]:
	var out: Array[Player] = []
	for id in _allies:
		var a := _allies[id]
		if is_instance_valid(a):
			out.append(a)
	return out


func _activate() -> void:
	active = true
	player.stats.set_source(SELF_KEY, {Stats.RESOURCE_REGEN: _regen_pct})
	if player.is_inside_tree():
		_ring = RogueVfx.ring(player, COLOR, RING_RADIUS, RING_ALPHA)
		if _ring != null:
			_ring.name = "AdrenalineRushRing"
		if _text_cd <= 0.0:
			_text_cd = _text_interval
			Vfx.floating_text(player.self_text_position(1.0), TEXT, COLOR, Player.SELF_TEXT_SIZE, 1.0)


## Gives the Haste to the living heroes within ally_radius (XZ) and takes it from those who
## left, went down or were freed.
func _refresh_allies() -> void:
	if not player.is_inside_tree():
		return
	var here := player.global_position
	var r_sq := _ally_radius * _ally_radius
	for node in player.get_tree().get_nodes_in_group(&"players"):
		var ally := node as Player
		if ally == null or ally == player or not ally.is_inside_tree():
			continue
		var id := ally.get_instance_id()
		var d := ally.global_position - here
		var near := ally.is_alive() and d.x * d.x + d.z * d.z <= r_sq
		if near and not _allies.has(id):
			ally.stats.set_source(_ally_key, {Stats.HASTE: _ally_haste})
			_allies[id] = ally
		elif not near and _allies.has(id):
			ally.stats.remove_source(_ally_key)
			_allies.erase(id)
	# Freed heroes (left the game) drop out.
	for id in _allies.keys():
		if not is_instance_valid(_allies[id]):
			_allies.erase(id)


func _deactivate() -> void:
	active = false
	_linger_left = 0.0
	if player != null and is_instance_valid(player):
		player.stats.remove_source(SELF_KEY)
	for id in _allies:
		var ally := _allies[id]
		if is_instance_valid(ally):
			ally.stats.remove_source(_ally_key)
	_allies.clear()
	if _ring != null and is_instance_valid(_ring):
		_ring.queue_free()
	_ring = null


func _reset() -> void:
	_deactivate()
	_clock = 0.0
	_text_cd = 0.0
