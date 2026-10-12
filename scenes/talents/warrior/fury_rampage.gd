class_name WarriorFuryRampage
extends TalentEffect
## Rampage – the Warrior Fury capstone (GDD 7.5, talents_warrior.md §2.3): every enemy the
## hero kills adds a stack for 5 sec (each kill refreshes the timer; at 0 every stack drops at
## once): +2% damage per stack, at most 10 stacks (+20%), on every source (weapon, ability,
## proc, dot, pet – [method damage_mult], multiplied with Mastery and buffs). Living allies
## within 8 m (XZ) get half of it as a Player.damage_mults entry under [member key] (one key
## per Warrior, so two Fury Warriors stack like two Battle Shouts), re-checked every
## ally_interval sec: an ally out of range or downed loses it.
##
## Everything drops (stacks, ally keys, the look) when the hero goes down (checked in tick),
## at wave start / end and on teardown. No RNG; passive for bots.
## Look: a red ember ring under the hero from 5 stacks (opacity = stacks / max), "Rampage!"
## over the hero when the stacks reach the maximum.
##
## Params (not rank-scaled; capstone, rank 1): pct_per_stack, max_stacks, duration,
## ally_share_pct, ally_radius, ally_interval.

const TEXT := "Rampage!"
const TEXT_COLOR := Color(1.0, 0.25, 0.15)
const RING_COLOR := Color(1.0, 0.28, 0.08, 0.6)
## Stacks from which the ember ring shows.
const RING_STACKS := 5

## Current stacks (tests, UI).
var stacks := 0
## The Player.damage_mults key the allies' share is stored under ("warrior_fury_rampage:<slot>").
var key: StringName = &""

var _pct := 2.0
var _max_stacks := 10
var _duration := 5.0
var _share := 0.5
var _radius := 8.0
var _interval := 0.25
var _left := 0.0
## Cached multipliers (the hot path only returns _mult).
var _mult := 1.0
var _ally_mult := 1.0
var _ally_clock := 0.0
## Instance id -> ally holding the share (values may be freed: untyped on purpose).
var _allies: Dictionary = {}
var _ring: WarriorAuraVfx


func setup(p_player: Player, p_rank: int, p_params: Dictionary) -> void:
	super(p_player, p_rank, p_params)
	_pct = num("pct_per_stack", 2.0)
	_max_stacks = maxi(1, int(num("max_stacks", 10.0)))
	_duration = maxf(0.01, num("duration", 5.0))
	_share = maxf(0.0, num("ally_share_pct", 50.0)) / 100.0
	_radius = maxf(0.0, num("ally_radius", 8.0))
	_interval = maxf(0.02, num("ally_interval", 0.25))
	key = key_for(p_player)


## The ally damage key of [param p] ("warrior_fury_rampage:<slot index>").
static func key_for(p: Player) -> StringName:
	if p != null and p.slot != null:
		return StringName("warrior_fury_rampage:%d" % p.slot.index)
	return StringName("warrior_fury_rampage:%d" % (p.get_instance_id() if p != null else 0))


## Seconds until the stacks drop (0 = none).
func time_left() -> float:
	return maxf(0.0, _left)


## The hero's own multiplier right now (1 + stacks x pct / 100).
func multiplier() -> float:
	return _mult


## Allies holding the share right now (tests, UI).
func allies() -> Array[Player]:
	var out: Array[Player] = []
	for id: int in _allies:
		var v: Variant = _allies[id]
		if is_instance_valid(v):
			out.append(v as Player)
	return out


func damage_mult(_target: Node3D, _school: StringName, _source: StringName) -> float:
	return _mult


func on_kill(_enemy: Node3D) -> void:
	if player == null or not player.is_alive():
		return
	var before := stacks
	stacks = mini(_max_stacks, stacks + 1)
	_left = _duration
	_mult = 1.0 + _pct * float(stacks) / 100.0
	_ally_mult = 1.0 + _pct * float(stacks) * _share / 100.0
	if before < _max_stacks and stacks >= _max_stacks:
		WarriorKit.shout_text(player, TEXT, TEXT_COLOR)
	if stacks != before:
		_update_ring()
		# Allies already holding the share see the new number at once.
		for id: int in _allies:
			var v: Variant = _allies[id]
			if is_instance_valid(v):
				(v as Player).damage_mults[key] = _ally_mult
	if before == 0:
		_ally_clock = 0.0  # share it on the next tick


func tick(delta: float) -> void:
	if stacks <= 0:
		return
	if player == null or not is_instance_valid(player) or not player.is_alive():
		_reset()
		return
	_left -= delta
	if _left <= 0.0:
		_reset()
		return
	_ally_clock -= delta
	if _ally_clock <= 0.0:
		_ally_clock += _interval
		if _ally_clock <= 0.0:
			_ally_clock = _interval
		_share_with_allies()


func begin_wave() -> void:
	_reset()


func end_wave() -> void:
	_reset()


func teardown() -> void:
	_reset()


func describe() -> String:
	return "Rampage: %d stacks (+%d%% damage)" % [stacks, roundi((_mult - 1.0) * 100.0)]


## Gives the share to every living ally in range and takes it from the others.
func _share_with_allies() -> void:
	if not player.is_inside_tree() or _share <= 0.0:
		return
	var here := player.global_position
	var r2 := _radius * _radius
	for node in player.get_tree().get_nodes_in_group(&"players"):
		var ally := node as Player
		if ally == null or ally == player:
			continue
		var id := ally.get_instance_id()
		var d := ally.global_position - here
		var inside := ally.is_alive() and ally.is_inside_tree() and d.x * d.x + d.z * d.z <= r2
		if inside:
			ally.damage_mults[key] = _ally_mult
			_allies[id] = ally
		elif _allies.has(id):
			ally.damage_mults.erase(key)
			_allies.erase(id)
	# Allies freed meanwhile.
	for id: int in _allies.keys():
		if not is_instance_valid(_allies[id]):
			_allies.erase(id)


func _update_ring() -> void:
	if stacks < RING_STACKS:
		_free_ring()
		return
	var strength := float(stacks) / float(_max_stacks)
	if is_instance_valid(_ring) and not _ring.is_queued_for_deletion():
		_ring.strength = strength
	elif player != null and player.is_inside_tree():
		_ring = WarriorAuraVfx.spawn(player, RING_COLOR, strength, "RampageRing")


func _free_ring() -> void:
	if is_instance_valid(_ring) and not _ring.is_queued_for_deletion():
		_ring.dismiss()
	_ring = null


## Drops every stack, the allies' share and the look.
func _reset() -> void:
	stacks = 0
	_left = 0.0
	_mult = 1.0
	_ally_mult = 1.0
	_ally_clock = 0.0
	for id: int in _allies:
		var v: Variant = _allies[id]
		if is_instance_valid(v):
			(v as Player).damage_mults.erase(key)
	_allies.clear()
	_free_ring()
