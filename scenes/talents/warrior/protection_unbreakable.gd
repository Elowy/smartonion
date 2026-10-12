class_name WarriorProtectionUnbreakable
extends TalentEffect
## Unbreakable – the Warrior Protection capstone (GDD 7.5 "Last Stand", renamed: Shield Wall's
## Rank V spec is "Last Stand"; talents_warrior.md §3.3): once per wave a hit that would bring
## the hero down leaves it standing at 1 HP instead (a Player.death_guards entry) with 1 sec
## of invulnerability; then for 10 sec its Max HP is raised by 30% (a Stamina stat source,
## Max HP measured before the bonus) and it is healed by as much, and every other living hero
## within 8 m (XZ) gets +15% Max HP and as much healing the same way.
##
## The guard only answers: it never heals or changes Max HP itself (take_damage computes the
## damage from hp right after it). The bonus is applied in on_damage_taken (HP already set),
## or – as a safety net – at the start of the next tick. The guard stands aside (false) when it
## was used this wave, when the hero is downed, and while Shield Wall's "Last Stand" would save
## the hit anyway (WarriorShieldWall.guards_lethal – free and unlimited while the wall stands).
## Guards run before the item cheat-death procs, so an item's cheat death stays a second life.
##
## The bonus ends after 10 sec, when the hero goes down, at wave start / end and on teardown
## (HP clamps to the lower Max HP – nobody dies of it); an ally that goes down or is freed
## loses its share at once. begin_wave re-arms it. No RNG; passive for bots.
##
## Params (not rank-scaled; capstone, rank 1): max_hp_pct, duration, invulnerable,
## ally_max_hp_pct, ally_radius.

const TEXT := "Unbreakable!"
const GOLD := Color(1.0, 0.82, 0.3)
const RING_COLOR := Color(1.0, 0.82, 0.3, 0.5)
const SHAKE := 0.4

## Saves used this wave / in total (tests, UI).
var used := false
var saves := 0
## The hero's own stat source; allies get "<SELF_KEY>:<slot of this hero>".
var self_key: StringName = &"warrior_protection_unbreakable"
var ally_key: StringName = &""

var _max_hp_pct := 30.0
var _duration := 10.0
var _invulnerable := 1.0
var _ally_pct := 15.0
var _radius := 8.0
var _pending := false
var _left := 0.0
var _guard := Callable()
## Instance id -> ally holding the bonus (values may be freed: untyped on purpose).
var _allies: Dictionary = {}
var _ring: WarriorAuraVfx


func setup(p_player: Player, p_rank: int, p_params: Dictionary) -> void:
	super(p_player, p_rank, p_params)
	_max_hp_pct = maxf(0.0, num("max_hp_pct", 30.0))
	_duration = maxf(0.01, num("duration", 10.0))
	_invulnerable = maxf(0.0, num("invulnerable", 1.0))
	_ally_pct = maxf(0.0, num("ally_max_hp_pct", 15.0))
	_radius = maxf(0.0, num("ally_radius", 8.0))
	var index := p_player.slot.index if p_player != null and p_player.slot != null else 0
	ally_key = StringName("%s:%d" % [self_key, index])
	_guard = _on_lethal_hit
	if p_player != null:
		p_player.death_guards.append(_guard)


## True while the Max HP bonus runs.
func is_active() -> bool:
	return _left > 0.0


func time_left() -> float:
	return maxf(0.0, _left)


## Allies holding the bonus right now (tests, UI).
func allies() -> Array[Player]:
	var out: Array[Player] = []
	for id: int in _allies:
		var v: Variant = _allies[id]
		if is_instance_valid(v):
			out.append(v as Player)
	return out


func on_damage_taken(_amount: float, _attacker: Node3D) -> void:
	if _pending:
		_apply()


func tick(delta: float) -> void:
	if _pending:
		_apply()
	if _left <= 0.0:
		return
	if player == null or not is_instance_valid(player) or not player.is_alive():
		_end()
		return
	_left -= delta
	if _left <= 0.0:
		_end()
		return
	for id: int in _allies.keys():
		var v: Variant = _allies[id]
		if not is_instance_valid(v):
			_allies.erase(id)
		elif not (v as Player).is_alive():
			(v as Player).stats.remove_source(ally_key)
			_allies.erase(id)


func begin_wave() -> void:
	used = false
	_pending = false
	_end()


func end_wave() -> void:
	_pending = false
	_end()


func teardown() -> void:
	_pending = false
	_end()
	if is_instance_valid(player) and _guard.is_valid():
		player.death_guards.erase(_guard)
	_guard = Callable()


func describe() -> String:
	if _left > 0.0:
		return "Unbreakable: %.0f s" % _left
	return "Unbreakable: used this wave" if used else "Unbreakable: ready"


## Player.death_guards: survive a lethal hit (once per wave). Only answers – the bonus comes in
## on_damage_taken, after take_damage has set the HP.
func _on_lethal_hit() -> bool:
	if used or player == null or not is_instance_valid(player) or not player.is_alive():
		return false
	if _shield_wall_saves():
		return false
	used = true
	_pending = true
	saves += 1
	player.invulnerable_left = maxf(player.invulnerable_left, _invulnerable)
	return true


## True while the hero's Shield Wall with "Last Stand" stands (its guard saves the hit).
func _shield_wall_saves() -> bool:
	if player.abilities == null:
		return false
	for a in player.abilities.slots:
		var fx := player.abilities.effect_for(a) if a != null else null
		if fx is WarriorShieldWall and (fx as WarriorShieldWall).guards_lethal():
			return true
	return false


## +Max HP and the same healing for the hero and the allies in range, for the duration.
func _apply() -> void:
	_pending = false
	if player == null or not is_instance_valid(player) or not player.is_alive():
		return
	_end()
	var gain := player.max_hp() * _max_hp_pct / 100.0
	if gain > 0.0:
		player.stats.set_source(self_key, {Stats.STAMINA: gain})
		player.heal(gain)
	_left = _duration
	var shown := player.is_inside_tree()
	if shown and _ally_pct > 0.0:
		var here := player.global_position
		var r2 := _radius * _radius
		for node in player.get_tree().get_nodes_in_group(&"players"):
			var ally := node as Player
			if ally == null or ally == player or not ally.is_alive() or not ally.is_inside_tree():
				continue
			var d := ally.global_position - here
			if d.x * d.x + d.z * d.z > r2:
				continue
			var g := ally.max_hp() * _ally_pct / 100.0
			if g <= 0.0:
				continue
			ally.stats.set_source(ally_key, {Stats.STAMINA: g})
			ally.heal(g)
			_allies[ally.get_instance_id()] = ally
	if shown:
		WarriorKit.shout_text(player, TEXT, GOLD)
		Vfx.explosion(player.global_position + Vector3.UP * 0.1, _radius, GOLD)
		WarriorKit.shake(SHAKE)
		_ring = WarriorAuraVfx.spawn(player, RING_COLOR, 1.0, "UnbreakableRing")


## Removes the bonus from the hero and every ally, and the look.
func _end() -> void:
	_left = 0.0
	if is_instance_valid(player):
		player.stats.remove_source(self_key)
	for id: int in _allies:
		var v: Variant = _allies[id]
		if is_instance_valid(v):
			(v as Player).stats.remove_source(ally_key)
	_allies.clear()
	if is_instance_valid(_ring) and not _ring.is_queued_for_deletion():
		_ring.dismiss()
	_ring = null
