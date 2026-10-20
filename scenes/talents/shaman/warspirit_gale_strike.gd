class_name ShamanWarspiritGaleStrike
extends TalentEffect
## Gale Strike – the Shaman Warspirit capstone (design_shaman.md 4.4, M8): every [code]every[/code]th weapon
## ATTACK calls down [code]strikes[/code] lightning strikes. Strike one hits the attack's target at once, every
## further strike follows [code]strike_delay[/code] seconds after the one before and picks the nearest other
## enemy within [code]range[/code] m of the first target (an enemy of this volley is not struck twice; with none
## left it is the first target again, and a lost strike when that one is gone too).
##
## Attacks are counted with on_hit's [code]first[/code] (the attack's ProcGate hit, like Mortal Strike): a swing
## that hits five enemies counts once, both hands count. If the counted attack's target is already dead the
## strike is held for the next attack. Each strike is a Nature SPELL hit: damage + Intellect x intellect_scale +
## Spell Power x spell_power_scale through ShamanKit.strike (deal_raw as an ability: Livewire and the other
## outgoing multipliers apply, one Storm Echo roll) and builds [code]surge_per_strike[/code] Surge. It is no
## weapon hit (no on-hit procs, no Surge from the weapon gain) and never takes an Elemental Surge charge.
## Wave start / end, going down and teardown clear the count and the strikes still to come. No RNG of its own,
## passive for bots.
##
## Params (not rank-scaled; capstone, rank 1): every, strikes, damage, intellect_scale, spell_power_scale,
## strike_delay, range, surge_per_strike.


## One called-down volley: the strikes after the first wait here.
class Volley extends RefCounted:
	## Seconds until the next strike.
	var left := 0.0
	## Index of the next strike (the first one is index 0, struck at once).
	var index := 1
	## Where the first target stood and its instance id.
	var origin := Vector3.ZERO
	var first_id := 0
	## Instance ids of the enemies this volley struck.
	var struck: Array[int] = []


## Attacks counted towards the next volley (0 .. every; every = a volley is held).
var attacks := 0
## Volleys called and strikes dealt (tests, UI).
var volleys := 0
var strikes_dealt := 0

var _every := 5
var _strikes := 2
var _damage := 5.0
var _intellect_scale := 0.8
var _sp_scale := 1.2
var _delay := 0.2
var _range := 6.0
var _surge := 3.0
var _pending: Array[Volley] = []


func setup(p_player: Player, p_rank: int, p_params: Dictionary) -> void:
	super(p_player, p_rank, p_params)
	_every = maxi(1, roundi(num("every", 5.0)))
	_strikes = maxi(1, roundi(num("strikes", 2.0)))
	_damage = num("damage", 5.0)
	_intellect_scale = num("intellect_scale", 0.8)
	_sp_scale = num("spell_power_scale", 1.2)
	_delay = maxf(0.01, num("strike_delay", 0.2))
	_range = maxf(0.0, num("range", 6.0))
	_surge = maxf(0.0, num("surge_per_strike", 3.0))


func on_hit(target: Node3D, _damage_dealt: float, _is_crit: bool, first: bool) -> void:
	if not first or player == null or not is_instance_valid(player) or not player.is_alive():
		return
	attacks = mini(attacks + 1, _every)
	if attacks < _every:
		return
	var e: Enemy = target as Enemy if target != null and is_instance_valid(target) else null
	if not ShamanKit.is_live(e):
		return  # held: the next attack calls the strikes
	attacks = 0
	volleys += 1
	var v := Volley.new()
	v.origin = e.global_position
	v.first_id = e.get_instance_id()
	v.struck.append(v.first_id)
	_strike(e)
	if _strikes > 1:
		v.left = _delay
		_pending.append(v)


func tick(delta: float) -> void:
	if _pending.is_empty():
		return
	if player == null or not is_instance_valid(player) or not player.is_alive():
		_pending.clear()
		return
	var keep: Array[Volley] = []
	for v in _pending:
		v.left -= delta
		while v.left <= 0.0 and v.index < _strikes:
			var e := _next_target(v)
			v.index += 1
			v.left += _delay
			if e != null:
				v.struck.append(e.get_instance_id())
				_strike(e)
		if v.index < _strikes:
			keep.append(v)
	_pending = keep


func begin_wave() -> void:
	_reset()


func end_wave() -> void:
	_reset()


func teardown() -> void:
	_reset()


func describe() -> String:
	return "Gale Strike: %d / %d attacks" % [attacks, _every]


## The enemy the next strike of [param v] hits: the nearest enemy to the volley's origin within range that this
## volley has not struck, else the first target (while it lives), else null.
func _next_target(v: Volley) -> Enemy:
	if player == null or not player.is_inside_tree():
		return null
	var exclude: Array[Enemy] = []
	for id in v.struck:
		if is_instance_id_valid(id):
			var struck := instance_from_id(id) as Enemy
			if struck != null:
				exclude.append(struck)
	var found := ShamanKit.nearest_enemies(player.get_tree(), v.origin, _range, 1, exclude)
	if not found.is_empty():
		return found[0]
	if is_instance_id_valid(v.first_id):
		var first := instance_from_id(v.first_id) as Enemy
		if ShamanKit.is_live(first):
			return first
	return null


## One lightning strike on [param e]: Nature damage (with Storm Echo) and the Surge it builds.
func _strike(e: Enemy) -> void:
	if player == null or player.procs == null or not ShamanKit.is_live(e):
		return
	var params := {"damage": _damage, "intellect_scale": _intellect_scale, "spell_power_scale": _sp_scale}
	var amount := ShamanKit.spell_damage(player.stats, params, ShamanKit.NATURE)
	var at := ShamanKit.chest(e)
	ProcVfx.beam(Vector3(at.x + 0.4, ShamanThunderbolt.SKY_HEIGHT, at.z + 0.3), at, ShamanKit.LIGHTNING_COLOR)
	Vfx.explosion(WeaponRunner.flat(e.global_position) + Vector3.UP * 0.1, 0.7, ShamanKit.LIGHTNING_COLOR)
	strikes_dealt += 1
	ShamanKit.strike(player, e, amount, ShamanKit.NATURE, true)
	ShamanKit.add_surge(player, _surge)


func _reset() -> void:
	attacks = 0
	_pending.clear()
