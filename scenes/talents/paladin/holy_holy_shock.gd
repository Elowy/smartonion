class_name PaladinHolyHolyShock
extends TalentEffect
## Holy Shock – the Paladin Holy capstone (GDD 7.5, talents_paladin.md §1.3): every
## [code]interval[/code] seconds (shortened like an ability cooldown: Haste at half effect and
## Cooldown Reduction, [method interval_now]) Holy Shock goes off by itself:
##   1. the most wounded living hero within [code]range[/code] m (the Paladin included) below
##      [code]heal_below[/code] % of max HP heals heal_flat + heal_max_hp_pct % of their max HP +
##      heal_sp_scale x Spell Power (PaladinKit.heal_amount – Healing Done included);
##   2. else the nearest enemy within [code]range[/code] m takes weapon_pct % weapon damage +
##      sp_scale x Spell Power as Holy damage (PaladinKit.strike_damage, built from the hero's
##      stats: deal_raw(..., target_bonus = true, &"ability"));
##   3. else (nothing to do) the shock is held and tried again after [code]retry[/code] seconds.
## Downed heroes are never targeted (Word of Glory stays the only instant revive). The timer
## holds while the Paladin is downed; the first shock of a wave comes after half an interval
## ([method begin_wave]). No RNG, no stat sources, keys or nodes – teardown has nothing to undo.
## Passive for bots.
##
## Params (not rank-scaled; capstone, rank 1): interval, range, heal_below (%), heal_flat,
## heal_max_hp_pct, heal_sp_scale, weapon_pct, sp_scale, retry.

const SMITE_COLOR := Color(1.0, 0.95, 0.6)
const SMITE_BURST := 0.6

## Heals and smites done (tests, UI).
var heals := 0
var smites := 0

var _left := 0.0
var _interval := 4.0
var _range := 8.0
var _heal_below := 0.9
var _heal_flat := 1.0
var _heal_max_hp_pct := 6.0
var _heal_sp_scale := 0.5
var _weapon_pct := 100.0
var _sp_scale := 0.8
var _retry := 0.25


func setup(p_player: Player, p_rank: int, p_params: Dictionary) -> void:
	super(p_player, p_rank, p_params)
	_interval = maxf(0.1, num("interval", 4.0))
	_range = num("range", 8.0)
	_heal_below = num("heal_below", 90.0) / 100.0
	_heal_flat = num("heal_flat", 1.0)
	_heal_max_hp_pct = num("heal_max_hp_pct", 6.0)
	_heal_sp_scale = num("heal_sp_scale", 0.5)
	_weapon_pct = num("weapon_pct", 100.0)
	_sp_scale = num("sp_scale", 0.8)
	_retry = maxf(0.05, num("retry", 0.25))
	_left = interval_now() * 0.5


## The current interval: interval x Haste (half effect) x (1 - Cooldown Reduction), the rule of
## ability cooldowns (AbilityRunner.cooldown_of).
func interval_now() -> float:
	if player == null:
		return _interval
	var cdr := clampf(player.stats.get_raw(Stats.COOLDOWN_REDUCTION), 0.0, 60.0)
	return _interval * player.stats.cooldown_mult() * (1.0 - cdr / 100.0)


## Seconds to the next shock (tests, UI).
func time_left() -> float:
	return _left


func tick(delta: float) -> void:
	if player == null or not is_instance_valid(player) or not player.is_alive() or not player.is_inside_tree():
		return
	_left -= delta
	if _left > 0.0:
		return
	_shock()


func begin_wave() -> void:
	_left = interval_now() * 0.5


func describe() -> String:
	return "Radiant Pulse: every %.1f sec" % interval_now()


## One shock: heal, else smite, else hold (retry).
func _shock() -> void:
	var tree := player.get_tree()
	var here := player.global_position
	var who := PaladinKit.lowest_hero(tree, here, _range, true)
	if who != null and PaladinKit.hp_ratio(who) < _heal_below:
		who.heal(PaladinKit.heal_amount(player, who, _heal_flat, _heal_max_hp_pct, _heal_sp_scale), player.slot_index())
		heals += 1
		_left = interval_now()
		if who != player:
			ProcVfx.beam(player.get_chest_position(), who.get_chest_position(), PaladinKit.HOLY_COLOR)
		Vfx.hit_spark(who.get_chest_position(), PaladinKit.HOLY_COLOR)
		return
	var e := EnemyGrid.nearest(tree, here, _range)
	if e != null and not e.is_dead() and player.procs != null:
		var spot := e.global_position
		var chest := spot + Vector3.UP * WeaponRunner.DAMAGE_TEXT_HEIGHT * 0.5
		ProcVfx.beam(player.get_chest_position(), chest, SMITE_COLOR)
		Vfx.hit_spark(chest, SMITE_COLOR)
		Vfx.explosion(spot + Vector3.UP * 0.1, SMITE_BURST, PaladinKit.HOLY_COLOR)
		player.procs.deal_raw(e, PaladinKit.strike_damage(player, _weapon_pct, _sp_scale), PaladinKit.SCHOOL, true, &"ability")
		smites += 1
		_left = interval_now()
		return
	_left = _retry
