class_name MageArcaneMissiles
extends AbilityEffect
## Arcane Missiles (GDD 6.4, Mage, Auto-cast): a volley of small homing missiles, one every
## interval seconds, each at a RANDOM living enemy within the cast range (picked as it
## leaves, with the run RNG – RunState.rng). Each hit is Arcane spell damage ([MageSpell],
## x power). The volley stops when the hero goes down, at wave end / start, on forget, or
## when no enemy is left in reach.
##
## Params (data/abilities/mage_arcane_missiles.tres): missiles (Rank III: +2), damage,
## int_scaling, speed, interval, splash_radius + splash_pct (Rank V "Arcane Barrage": each
## missile bursts; x Area Size), focus + focus_bonus_pct (Rank V "Focused Missiles": every
## missile seeks the toughest enemy in reach and hits harder).

const TURN_RATE := 9.0
## Missiles leave alternately this far (radians) to either side of their target and curve in.
const LAUNCH_ANGLE := 0.45
const RANGE_SLACK := 6.0
const SCALE := 0.75

## Missiles still to launch in the running volley and the time to the next one.
var pending := 0
var launched := 0
var bolts: Array[Node3D] = []

var _player: Player
var _launch_left := 0.0
var _interval := 0.12
var _damage := 0.0
var _speed := 14.0
var _reach := 10.0
var _splash_radius := 0.0
var _splash_pct := 50.0
var _focus := false
var _rng: RandomNumberGenerator


func is_firing() -> bool:
	return pending > 0


func can_cast(ctx: AbilityContext) -> bool:
	return ctx.target != null and not is_firing()


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree() or ctx.target == null:
		return false
	_player = p
	_rng = ctx.rng if ctx.rng != null else RunState.rng
	_focus = ctx.flag("focus")
	_damage = MageSpell.damage_from(ctx, MageSpell.ARCANE)
	if _focus:
		_damage *= 1.0 + ctx.num("focus_bonus_pct", 40.0) / 100.0
	_interval = maxf(0.02, ctx.num("interval", 0.12))
	_speed = ctx.num("speed", 14.0)
	_reach = ctx.ability.cast_range
	_splash_radius = ctx.num("splash_radius", 0.0) * MageSpell.area_mult(p)
	_splash_pct = ctx.num("splash_pct", 50.0)
	pending = maxi(1, roundi(ctx.num("missiles", 5.0)))
	launched = 0
	_launch_left = 0.0
	if not p.downed_changed.is_connected(_on_downed_changed):
		p.downed_changed.connect(_on_downed_changed)
	MageSpell.prune(bolts)
	_launch_due()
	return true


func tick(_ctx: AbilityContext, delta: float) -> void:
	if not is_firing():
		return
	_launch_left -= delta
	_launch_due()


## Launches every missile whose time has come.
func _launch_due() -> void:
	while is_firing() and _launch_left <= 0.0001:
		_launch_left += _interval
		if not _launch_one():
			stop()
			return


func _launch_one() -> bool:
	# (Check the member itself: a freed hero must not be copied into a typed variable.)
	if not is_instance_valid(_player):
		return false
	var p := _player
	if not p.is_inside_tree() or p.downed:
		return false
	var here := p.global_position
	var tree := p.get_tree()
	var target := MageSpell.toughest_enemy(tree, here, _reach) if _focus \
			else MageSpell.random_enemy(tree, here, _reach, _rng)
	if target == null:
		return false
	var from := here + Vector3.UP * Player.CHEST_HEIGHT
	var to := WeaponRunner.flat(target.global_position - here)
	if to.length_squared() < 0.0001:
		to = p.facing
	var side := 1.0 if launched % 2 == 0 else -1.0
	var dir := to.normalized().rotated(Vector3.UP, LAUNCH_ANGLE * side)
	var bolt := MageBolt.fire(p, from + dir * (Player.RADIUS + 0.1), dir, _damage, MageSpell.ARCANE,
			_speed, _reach + RANGE_SLACK, &"bolt", MageSpell.ARCANE_COLOR, SCALE)
	bolt.home_on(target, TURN_RATE)
	bolt.splash_radius = _splash_radius
	bolt.splash_pct = _splash_pct
	bolts.append(bolt)
	launched += 1
	pending -= 1
	p.face_attack(to)
	return true


## Ends the volley (missiles already flying go on).
func stop() -> void:
	pending = 0
	_launch_left = 0.0


func begin_wave(_ctx: AbilityContext) -> void:
	stop()
	MageSpell.free_all(bolts)


func end_wave(_ctx: AbilityContext) -> void:
	stop()
	MageSpell.free_all(bolts)


## Bots / auto-cast: an enemy is in reach and no volley is running.
func wants_auto_cast(ctx: AbilityContext) -> bool:
	return ctx.target != null and not is_firing()


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		stop()
