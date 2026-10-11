class_name MagePyroblast
extends AbilityEffect
## Pyroblast (GDD 6.4, Mage, Active – RB / LB): gathers a huge fireball for windup seconds
## (the hero keeps moving and attacking; [MagePyroCharge] shows it), then hurls it at the
## toughest enemy within reach (most HP; ties: the nearer one) – heavy Fire spell damage
## ([MageSpell], x power) and a burn ([MageBurn]) for burn_pct % of the hit. The cooldown
## starts with the wind-up; going down, the wave ending / starting or forgetting the spell
## cancels it. With nobody left in reach at the release the fireball flies along the facing.
##
## Params (data/abilities/mage_pyroblast.tres): damage, int_scaling, burn_pct, burn_duration,
## windup, speed, splash_radius + splash_pct (Rank III: it explodes; x Area Size), pierce
## (Rank V "Pyroclasm": burns through every enemy in its path), windup 0 + cooldown_pct
## (Rank V "Hot Streak": instant).
## Bots cast it whenever an enemy is in reach and no wind-up is running.

const SCALE := 3.0
const RANGE_SLACK := 4.0
const TURN_RATE := 2.5

## Seconds of wind-up left (0 = not winding up).
var windup_left := 0.0
## Fireballs released (tests) and the last one.
var released := 0
var last_bolt: MageBolt
var bolts: Array[Node3D] = []

var _charge: MagePyroCharge


func is_winding_up() -> bool:
	return windup_left > 0.0


func can_cast(ctx: AbilityContext) -> bool:
	return ctx.target != null and not is_winding_up()


func wants_auto_cast(ctx: AbilityContext) -> bool:
	return ctx.target != null and not is_winding_up()


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree() or ctx.target == null:
		return false
	if not p.downed_changed.is_connected(_on_downed_changed):
		p.downed_changed.connect(_on_downed_changed)
	var windup := ctx.num("windup", 1.0)
	if windup <= 0.0:
		release(ctx)
		return true
	windup_left = windup
	_clear_charge()
	_charge = MagePyroCharge.attach(p, windup)
	return true


func tick(ctx: AbilityContext, delta: float) -> void:
	if not is_winding_up():
		return
	windup_left -= delta
	if windup_left <= 0.0001:
		windup_left = 0.0
		release(ctx)


## Hurls the fireball now (end of the wind-up).
func release(ctx: AbilityContext) -> void:
	_clear_charge()
	var p := ctx.player
	if p == null or not is_instance_valid(p) or not p.is_inside_tree() or p.downed:
		return
	var here := p.global_position
	var reach := ctx.ability.cast_range
	var target := MageSpell.toughest_enemy(p.get_tree(), here, reach)
	var dir := WeaponRunner.flat(target.global_position - here) if target != null else p.facing
	if dir.length_squared() < 0.0001:
		dir = p.facing
	dir = dir.normalized()
	var from := here + Vector3.UP * Player.CHEST_HEIGHT + dir * (Player.RADIUS + 0.2)
	var bolt := MageBolt.fire(p, from, dir, MageSpell.damage_from(ctx, MageSpell.FIRE), MageSpell.FIRE,
			ctx.num("speed", 13.0), reach + RANGE_SLACK, &"fireball", MageSpell.FIRE_COLOR, SCALE)
	if target != null:
		bolt.home_on(target, TURN_RATE)
	bolt.burn_pct = ctx.num("burn_pct", 0.0)
	bolt.burn_duration = ctx.num("burn_duration", 4.0)
	bolt.splash_radius = ctx.num("splash_radius", 0.0) * MageSpell.area_mult(p)
	bolt.splash_pct = ctx.num("splash_pct", 50.0)
	bolt.set_pierce(roundi(ctx.num("pierce", 0.0)))
	MageSpell.prune(bolts)
	bolts.append(bolt)
	last_bolt = bolt
	released += 1
	p.face_attack(dir)
	Vfx.hit_spark(from, MageSpell.FIRE_COLOR)


## Cancels a wind-up (nothing is thrown; the cooldown stays spent).
func cancel() -> void:
	windup_left = 0.0
	_clear_charge()


func begin_wave(_ctx: AbilityContext) -> void:
	cancel()
	MageSpell.free_all(bolts)


func end_wave(_ctx: AbilityContext) -> void:
	cancel()
	MageSpell.free_all(bolts)


func _clear_charge() -> void:
	if _charge != null and is_instance_valid(_charge) and not _charge.is_queued_for_deletion():
		_charge.finish()
	_charge = null


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		cancel()
