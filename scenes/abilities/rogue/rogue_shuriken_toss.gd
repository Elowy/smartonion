class_name RogueShurikenToss
extends AbilityEffect
## Shuriken Toss (GDD 6.4, Rogue Auto): throws [code]shuriken[/code] (3) spinning stars in a
## fan of [code]spread[/code] (30) degrees at the nearest enemy within the cast range. Each is
## a weapon-based hit of the main hand ([code]damage_pct[/code] % x "power", rolls its own
## crit) flying [code]range[/code] m at [code]speed[/code] m/s through [code]pierce[/code]
## enemies – [RogueBlade]s, so crits give Combo Points and Deadly Poison and the throw rolls
## the on-hit procs once. A talent script that forces crits (Shadow Dance) is asked before each
## star's roll (RogueUtil.bonus_crit).
## Rank III: +2 shuriken. Rank V: "Razor Stars" ([code]pierce[/code] +2, [code]range[/code]
## +4) or "Twin Volley" ([code]volleys[/code] 2: a second fan [code]volley_delay[/code] s later,
## re-aimed at the nearest enemy; dropped when the Rogue goes down and with the wave).

const COLOR := Color(0.78, 0.86, 1.0)
const KNOCKBACK := 0.4
const DEFAULT_RANGE := 10.0

var _player: Player
var _weapon: WeaponData
## Volleys still to throw and the seconds until the next one (Twin Volley).
var _volleys_left := 0
var _volley_left := 0.0
var _volley_delay := 0.25
var _params: Dictionary = {}
var _fallback_dir := Vector3.FORWARD


## Auto-cast: an enemy is within the cast range (the runner resolved the nearest one).
func wants_auto_cast(ctx: AbilityContext) -> bool:
	return ctx.target != null and ctx.player != null and ctx.player.is_inside_tree()


func cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_inside_tree() or ctx.target == null:
		return false
	_player = player
	_weapon = RogueUtil.weapon(player)
	_params = ctx.params
	var dir := WeaponRunner.flat(ctx.target.global_position - player.global_position)
	dir = dir.normalized() if dir.length_squared() > 0.0001 else WeaponRunner.flat(ctx.direction).normalized()
	_fallback_dir = dir
	if not throw_volley(player, dir, _params, ctx.target):
		return false
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
	var reach := float(_params.get("range", DEFAULT_RANGE))
	var target := EnemyGrid.nearest(_player.get_tree(), _player.global_position, reach)
	if target != null:
		var to := WeaponRunner.flat(target.global_position - _player.global_position)
		if to.length_squared() > 0.0001:
			dir = to.normalized()
	throw_volley(_player, dir, _params, target)


func begin_wave(_ctx: AbilityContext) -> void:
	_volleys_left = 0


func end_wave(_ctx: AbilityContext) -> void:
	_volleys_left = 0


## A Rogue that goes down throws no late volley (the runner does not tick it while downed, so
## it would fly right after a revive).
func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		_volleys_left = 0


## One fan of shuriken from [param player] centred on [param dir]. False when nothing could be
## thrown (no weapon, not in a tree). [param target] (the aimed enemy, may be null) is what a
## talent script that forces crits is asked about (RogueUtil.bonus_crit – Shadow Dance) before
## each star's own roll.
static func throw_volley(player: Player, dir: Vector3, params: Dictionary, target: Node3D = null) -> bool:
	var weapon := RogueUtil.weapon(player)
	var parent := WeaponRunner.effects_parent(player)
	if weapon == null or parent == null:
		return false
	var count := maxi(1, roundi(float(params.get("shuriken", 3.0))))
	var spread := deg_to_rad(float(params.get("spread", 30.0)))
	var damage := star_damage(player, weapon, params)
	var crit_mult := CombatMath.crit_multiplier(weapon, player.stats)
	var speed := float(params.get("speed", 20.0))
	var reach := float(params.get("range", DEFAULT_RANGE))
	var pierce := maxi(0, roundi(float(params.get("pierce", 0.0))))
	var origin := player.global_position
	var gate := WeaponRunner.ProcGate.new()
	for i in count:
		var angle := 0.0
		if count > 1:
			angle = spread * (float(i) / float(count - 1) - 0.5)
		var shot := dir.rotated(Vector3.UP, angle)
		var crit := RogueUtil.bonus_crit(player, target) or CombatMath.roll_crit(player.stats, RunState.rng)
		var star := RogueBlade.throw(player, weapon, damage * (crit_mult if crit else 1.0), crit, shot,
				speed, reach, pierce, COLOR, RogueBlade.Look.SHURIKEN)
		star.knockback = KNOCKBACK
		star.proc_gate = gate
		parent.add_child(star)
		star.global_position = origin + Vector3.UP * Player.CHEST_HEIGHT + shot * (Player.RADIUS + 0.15)
	player.face_attack(dir)
	return true


## Damage of one (non-crit) shuriken: damage_pct % of a weapon hit x power.
static func star_damage(player: Player, weapon: WeaponData, params: Dictionary) -> float:
	return CombatMath.weapon_hit_damage(weapon, player.stats) * float(params.get("damage_pct", 90.0)) / 100.0 \
			* float(params.get("power", 1.0))
