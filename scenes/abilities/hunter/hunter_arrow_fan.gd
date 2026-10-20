class_name HunterArrowFan
extends AbilityEffect
## Arrow Fan (GDD 3.7, Hunter RT, 40 Focus): looses [code]arrows[/code] (5) arrows in a
## [code]spread[/code] (50) degree fan centred on the nearest enemy. Each arrow is a weapon-based
## hit ([HunterArrow]): [code]damage_pct[/code] (120) % of the weapon hit "W" ([method
## GeneralKit.weapon_damage]) x "power", able to crit, flying [code]range[/code] m at
## [code]speed[/code] m/s through [code]pierce[/code] enemies. Extra Projectile adds arrows and
## Pierce adds pierce (Quick Draw's Hail of Shafts, items), as they do to a plain shot. A melee
## main hand shoots too (the arrows leave the quiver by hand, same maths).
## Item / set mod: [code]arrows_add[/code] (Longbow of Many Feathers +2, Wildtracker's Garb 4 pc +2).
## Ranks (M4): Rank III +2 arrows; Rank V "Skewering Fan" ([code]pierce[/code] +1, [code]range[/code]
## +3) or "Echo Draw" ([code]volleys[/code] 2: a second fan [code]volley_delay[/code] s later,
## re-aimed at the nearest enemy; dropped when the Hunter goes down and with the wave).
##
## The arrows count as weapon hits (leech, Executioner / Slayer, the Mastery and outgoing
## multipliers; the on-hit procs roll once per fan). Their crits roll at the shot: a talent script
## that forces crits is asked first (HunterKit.bonus_crit), banked forced crits stay for the weapon.
## Bots fan when two or more enemies stand in the cone ahead, or Focus is nearly full.

const SOUND := &"shot_bow"
const AUTO_RANGE := 8.0
const AUTO_CONE := 35.0
const AUTO_MIN_ENEMIES := 2
const AUTO_FULL_FOCUS := 90.0

## Fans loosed this wave (tests).
var fans := 0
var last_arrows: Array[HunterArrow] = []

var _player: Player
var _params: Dictionary = {}
var _volleys_left := 0
var _volley_left := 0.0
var _volley_delay := 0.25
var _fallback_dir := Vector3.FORWARD


func can_cast(ctx: AbilityContext) -> bool:
	return ctx.target != null


## Focus is checked by the runner: two or more enemies in the cone ahead, or Focus nearly full and
## one enemy in reach.
func wants_auto_cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_inside_tree() or ctx.target == null:
		return false
	var here := player.global_position
	var dir := HunterKit.dir_to(here, ctx.target.global_position, ctx.direction)
	if HunterKit.enemies_in_cone(player.get_tree(), here, dir, AUTO_RANGE, AUTO_CONE) >= AUTO_MIN_ENEMIES:
		return true
	var focus := HunterKit.focus(player)
	return focus != null and focus.value >= AUTO_FULL_FOCUS \
			and GeneralKit.flat_distance(ctx.target.global_position, here) <= AUTO_RANGE


func cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_inside_tree() or ctx.target == null:
		return false
	_player = player
	_params = ctx.params
	var dir := HunterKit.dir_to(player.global_position, ctx.target.global_position, ctx.direction)
	_fallback_dir = dir
	if loose(player, dir, _params, ctx.target).is_empty():
		return false
	fans += 1
	_volleys_left = maxi(1, roundi(ctx.num("volleys", 1.0))) - 1
	_volley_delay = maxf(0.05, ctx.num("volley_delay", 0.25))
	_volley_left = _volley_delay
	if _volleys_left > 0 and not player.downed_changed.is_connected(_on_downed_changed):
		player.downed_changed.connect(_on_downed_changed)
	return true


func tick(_ctx: AbilityContext, delta: float) -> void:
	if _volleys_left <= 0:
		return
	_volley_left -= delta
	if _volley_left > 0.0:
		return
	_volleys_left -= 1
	_volley_left = _volley_delay
	if _player == null or not is_instance_valid(_player) or not _player.is_inside_tree():
		_volleys_left = 0
		return
	var dir := _fallback_dir
	var reach := float(_params.get("range", 11.0))
	var target := EnemyGrid.nearest(_player.get_tree(), _player.global_position, reach)
	if target != null:
		dir = HunterKit.dir_to(_player.global_position, target.global_position, dir)
	loose(_player, dir, _params, target)


func begin_wave(_ctx: AbilityContext) -> void:
	_volleys_left = 0
	fans = 0


func end_wave(_ctx: AbilityContext) -> void:
	_volleys_left = 0


## A Hunter that goes down looses no late volley (the runner does not tick it while downed, so it
## would fly right after a revive).
func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		_volleys_left = 0


## One fan of [param player] centred on [param dir] with the ability's [param params]. Returns the
## arrows (empty when nothing could be loosed).
static func loose(player: Player, dir: Vector3, params: Dictionary, target: Node3D = null) -> Array[HunterArrow]:
	var count := maxi(1, roundi(float(params.get("arrows", 5.0)))) + CombatMath.extra_projectiles(player.stats)
	var pierce := maxi(0, roundi(float(params.get("pierce", 0.0)))) + CombatMath.extra_pierce(player.stats)
	var arrows := HunterArrow.fan(player, dir, count, float(params.get("spread", 50.0)), arrow_damage(player, params),
			float(params.get("speed", 24.0)), float(params.get("range", 11.0)), pierce, target)
	if not arrows.is_empty():
		Audio.play(SOUND)
	var effect := HunterKit.effect_of(player, &"arrow_fan") as HunterArrowFan
	if effect != null:
		effect.last_arrows = arrows
	return arrows


## Damage of one (non-crit) arrow: damage_pct % of "W" x power.
static func arrow_damage(player: Player, params: Dictionary) -> float:
	return HunterKit.hit_damage(player, HunterKit.PHYSICAL) * float(params.get("damage_pct", 120.0)) / 100.0 \
			* float(params.get("power", 1.0))
