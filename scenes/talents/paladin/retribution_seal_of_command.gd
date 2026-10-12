class_name PaladinRetributionSealOfCommand
extends TalentEffect
## Seal of Command – the Paladin Retribution capstone (GDD 7.5, talents_paladin.md §3.3): each
## weapon ATTACK has a [code]chance[/code] % chance to unleash a holy strike. Rolled once per
## attack – on on_hit's [code]first[/code] hit (the attack's ProcGate hit), so an arc over a
## pack rolls once, while extra attacks (Reckoning, ripostes, Sweeping Blows in hybrids) are
## attacks of their own and roll too. One RunState.rng draw per attack whose first hit leaves
## a living target (the only draw point; nothing is rolled while the Paladin is downed or when
## the hit killed its target).
## The strike deals strike_pct % of the hit's base amount (after the crit, before Executioner /
## Slayer and the outgoing multipliers – the derived-damage rule, talent_vocabulary §3.6) as
## Holy damage to the target and to up to extra_targets more living enemies within radius m of
## it (nearest first): deal_raw(..., target_bonus = false, &"proc"), so the outgoing multipliers
## (Holy %, Purifying Power, Vengeance, auras) apply exactly once. Each seal then heals once
## (however many enemies it struck) the most wounded living hero within heal_range m of the
## Paladin (the Paladin included) for heal_max_hp_pct % of their max HP x the Paladin's
## Healing Done. Procs never trigger procs.
## Nothing persists between attacks: begin_wave / end_wave / teardown have nothing to undo.
## Passive for bots.
##
## Params (not rank-scaled; capstone, rank 1): chance (%), strike_pct, extra_targets, radius,
## heal_range, heal_max_hp_pct.

const SEAL_COLOR := Color(1.0, 0.8, 0.3)
const SPARK_HEIGHT := 0.6

## Seals unleashed (tests, UI).
var seals := 0

var _chance := 15.0
var _strike_mult := 0.7
var _extra := 2
var _radius := 3.0
var _heal_range := 8.0
var _heal_pct := 2.0


func setup(p_player: Player, p_rank: int, p_params: Dictionary) -> void:
	super(p_player, p_rank, p_params)
	_chance = num("chance", 15.0)
	_strike_mult = num("strike_pct", 70.0) / 100.0
	_extra = maxi(0, int(num("extra_targets", 2.0)))
	_radius = num("radius", 3.0)
	_heal_range = num("heal_range", 8.0)
	_heal_pct = num("heal_max_hp_pct", 2.0)


func on_hit(target: Node3D, damage: float, _is_crit: bool, first: bool) -> void:
	if not first or player == null or not player.is_alive() or player.procs == null:
		return
	var e: Enemy = target as Enemy if target != null and is_instance_valid(target) else null
	if e == null or e.is_dead() or not e.is_inside_tree():
		return
	if not RunState.rng.randf() * 100.0 < _chance:
		return
	_seal(e, damage * _strike_mult)


func describe() -> String:
	return "Seal of Command: %d%% chance per attack" % roundi(_chance)


## The strike on [param e] and its neighbours for [param amount] each, then the heal.
func _seal(e: Enemy, amount: float) -> void:
	seals += 1
	var tree := e.get_tree()
	var center := e.global_position
	var victims: Array[Enemy] = [e]
	if _extra > 0:
		for other in PaladinKit.enemies_by_distance(tree, center, _radius):
			if other == e:
				continue
			victims.append(other)
			if victims.size() > _extra:
				break
	var from := center + Vector3.UP * SPARK_HEIGHT
	for v in victims:
		if not is_instance_valid(v) or v.is_dead():
			continue
		var spot := v.global_position + Vector3.UP * SPARK_HEIGHT
		Vfx.hit_spark(spot, SEAL_COLOR)
		if v != e:
			ProcVfx.beam(from, spot, SEAL_COLOR)
		player.procs.deal_raw(v, amount, PaladinKit.SCHOOL, false, &"proc")
	if not player.is_inside_tree():
		return
	var who := PaladinKit.lowest_hero(player.get_tree(), player.global_position, _heal_range, true)
	if who != null:
		who.heal(who.max_hp() * _heal_pct / 100.0 * PaladinKit.healing_mult(player))
		Vfx.hit_spark(who.get_chest_position(), PaladinKit.HOLY_COLOR)
