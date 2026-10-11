class_name MageIceBarrier
extends AbilityEffect
## Ice Barrier (GDD 6.4, Mage, Auto-cast): an absorb shield ([method ProcSystem.add_shield])
## of (shield + int_scaling x Intellect + sp_scaling x Spell Power) x power that holds until
## it is used up (or the wave ends). It is its own ProcSystem shield entry
## ([constant SHIELD_SOURCE]): other shields on the hero (item procs, a Paladin's) keep their
## own timers, soak first when they run out sooner and neither block nor break the barrier.
## It is recast whenever the barrier is gone, the cooldown is over and an enemy is around.
## A frosty bubble shows it ([MageBarrierBubble]).
##
## Params (data/abilities/mage_ice_barrier.tres): shield, int_scaling, sp_scaling,
## chill + chill_duration (Rank III: enemies touching the hero when a hit strikes the barrier
## are slowed – any absorbed hit counts ([member ProcSystem.absorbed_total]), also one that a
## shorter-lived shield on top soaked first), break_pct + break_radius + break_freeze (Rank V
## "Shattering Barrier": when it breaks it explodes for break_pct % of its strength as Frost
## damage and freezes the enemies around), ice_block (Rank V "Ice Block": when it breaks the
## hero is immune to damage for that many seconds).
## The break is noticed in the physics tick (gameplay), never in the visual.

## Shield duration: until used up (ProcSystem clears shields at wave start anyway).
const UNTIL_USED := 3600.0
## The barrier's ProcSystem shield entry.
const SHIELD_SOURCE := &"ice_barrier"
## Auto-cast only with an enemy within this range (no barrier for an empty arena).
const AUTO_RANGE := 14.0
## Enemies this close to the hero's body count as the ones that struck the barrier.
const CHILL_REACH := 0.5
const EPSILON := 0.0001

## A barrier of this effect is up (and has not broken yet).
var active := false
## Strength the barrier was cast with (after power).
var strength := 0.0
var breaks := 0

## ProcSystem.absorbed_total at the last tick (a rise = a hit struck the barrier).
var _last_absorbed := 0.0
var _chill := 0.0
var _chill_duration := 2.0
var _break_pct := 0.0
var _break_radius := 3.5
var _break_freeze := 1.0
var _ice_block := 0.0
var _block_fx: MageFx


## Shield HP of the barrier at [param ctx]'s rank and the hero's stats.
static func shield_amount(ctx: AbilityContext) -> float:
	var stats := ctx.player.stats
	var base := ctx.num("shield") + ctx.num("int_scaling") * maxf(0.0, stats.get_raw(Stats.INTELLECT)) \
			+ ctx.num("sp_scaling") * maxf(0.0, stats.get_raw(Stats.SPELL_POWER))
	return maxf(0.0, base) * ctx.num("power", 1.0)


## Only when the hero's barrier is gone (other shields do not count).
func can_cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	return p != null and p.procs != null and p.procs.shield_of(SHIELD_SOURCE) <= EPSILON


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree() or not can_cast(ctx):
		return false
	return EnemyGrid.nearest(p.get_tree(), p.global_position, AUTO_RANGE) != null


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or p.procs == null:
		return false
	var amount := shield_amount(ctx)
	if amount <= 0.0:
		return false
	p.procs.add_shield(amount, UNTIL_USED, SHIELD_SOURCE)
	strength = amount
	active = true
	_last_absorbed = p.procs.absorbed_total
	_chill = ctx.num("chill", 0.0)
	_chill_duration = ctx.num("chill_duration", 2.0)
	_break_pct = ctx.num("break_pct", 0.0)
	_break_radius = ctx.num("break_radius", 3.5) * MageSpell.area_mult(p)
	_break_freeze = ctx.num("break_freeze", 1.0)
	_ice_block = ctx.num("ice_block", 0.0)
	if not p.downed_changed.is_connected(_on_downed_changed):
		p.downed_changed.connect(_on_downed_changed)
	if p.is_inside_tree():
		MageBarrierBubble.attach(p, amount)
		Vfx.hit_spark(p.global_position + Vector3.UP * Player.CHEST_HEIGHT, MageSpell.FROST_COLOR)
	return true


func tick(ctx: AbilityContext, _delta: float) -> void:
	if not active:
		return
	var p := ctx.player
	if p == null or p.procs == null:
		active = false
		return
	var hp := p.procs.shield_of(SHIELD_SOURCE)
	# Strikes: any shield soaked a blow (the barrier's own entry only drains once the shorter
	# shields on top are gone, but the attacker still hit the bubble).
	var absorbed := p.procs.absorbed_total
	if absorbed > _last_absorbed + EPSILON and _chill > 0.0 and p.is_inside_tree():
		_chill_attackers(p)
	_last_absorbed = absorbed
	if hp <= EPSILON:
		active = false
		breaks += 1
		_on_break(p)


## The barrier was used up: Shattering Barrier explodes, Ice Block encases the hero.
func _on_break(p: Player) -> void:
	if not p.is_inside_tree():
		return
	var center := WeaponRunner.flat(p.global_position)
	if _break_pct > 0.0 and p.procs != null:
		var damage := strength * _break_pct / 100.0
		for e in MageSpell.enemies_in(p.get_tree(), center, _break_radius):
			p.procs.deal_raw(e, damage, MageSpell.FROST, true, &"ability")
			MageSpell.freeze(e, p, _break_freeze)
		MageFx.frost_nova(center, _break_radius)
	if _ice_block > 0.0:
		p.invulnerable_left = maxf(p.invulnerable_left, _ice_block)
		_clear_block()
		_block_fx = MageFx.ice_block(p, _ice_block)


## Rank III: slows the enemies touching the hero (they just hit the barrier).
func _chill_attackers(p: Player) -> void:
	for e in MageSpell.enemies_in(p.get_tree(), p.global_position, Player.RADIUS + CHILL_REACH):
		e.apply_slow(_chill, _chill_duration)


func begin_wave(_ctx: AbilityContext) -> void:
	_reset()


## Wave end / forget: the barrier and its look go (the shield HP itself is cleared by
## ProcSystem at the next wave start).
func end_wave(ctx: AbilityContext) -> void:
	_reset()
	var bubble := MageBarrierBubble.of(ctx.player)
	if bubble != null:
		bubble.finish()


func _reset() -> void:
	active = false
	_clear_block()


func _clear_block() -> void:
	if _block_fx != null and is_instance_valid(_block_fx) and not _block_fx.is_queued_for_deletion():
		_block_fx.queue_free()
	_block_fx = null


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		_reset()
