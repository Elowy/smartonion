class_name RogueKillingSpree
extends AbilityEffect
## Killing Spree (GDD 6.4, Rogue Active): for [code]duration[/code] (2) s the Rogue blinks from
## enemy to enemy – every [code]interval[/code] (0.25) s it appears behind the enemy within
## [code]range[/code] (8) m it struck least often in this spree (nearest first, not the last
## target again unless it is alone) and strikes it with the main hand for [code]damage_pct[/code] (150) % of a weapon
## hit x "power" – a real weapon hit (crit roll / guaranteed crit, Combo Points, Deadly Poison,
## on-hit procs; never an extra-attack chain). While it lasts the Rogue takes
## [code]damage_taken_pct[/code] (50) % less damage (Player.damage_taken_mults
## [constant DR_KEY]). It ends early when no enemy is in reach. Each jump is kept inside the
## arena and the shared screen like Shadowstep.
## Rank III: +1 s (four more strikes). Rank V: "Blade Whirl" ([code]cleave_radius[/code]: each
## strike also hits every enemy within that many metres of the target) or "Untouchable"
## ([code]invulnerable[/code]: immune to damage during the spree, then [code]stealth[/code] s
## of Vanish stealth).
## Bot rule: at least AUTO_MIN_ENEMIES enemies within AUTO_RANGE m, not while reviving.

const DR_KEY := &"killing_spree"
const AUTO_MIN_ENEMIES := 3
const AUTO_RANGE := 6.0
const STRIKE_COLOR := Color(0.75, 0.6, 1.0)
const KNOCKBACK := 0.4
const TIME_EPSILON := 0.0001

var _player: Player
var _strikes_left := 0
var _strike_timer := 0.0
var _interval := 0.25
var _range := 8.0
var _mult := 1.5
var _cleave := 0.0
var _invulnerable := false
var _stealth := 0.0
## Enemy instance id -> strikes it took in this spree.
var _struck: Dictionary[int, int] = {}
var _last_id := 0
## Strikes made in the current / last spree (tests).
var strikes := 0


func can_cast(ctx: AbilityContext) -> bool:
	return not is_active() and ctx.target != null


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_inside_tree() or player.is_reviving() or is_active():
		return false
	return RogueUtil.enemies_within(player, AUTO_RANGE) >= AUTO_MIN_ENEMIES


func cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_inside_tree() or ctx.target == null or is_active():
		return false
	_player = player
	if not player.downed_changed.is_connected(_on_downed_changed):
		player.downed_changed.connect(_on_downed_changed)
	_interval = maxf(0.05, ctx.num("interval", 0.25))
	_strikes_left = maxi(1, roundi(ctx.num("duration", 2.0) / _interval))
	_strike_timer = 0.0
	_range = maxf(1.0, ctx.num("range", 8.0))
	_mult = maxf(0.0, ctx.num("damage_pct", 150.0)) / 100.0 * ctx.num("power", 1.0)
	_cleave = maxf(0.0, ctx.num("cleave_radius", 0.0))
	_invulnerable = ctx.num("invulnerable", 0.0) > 0.0
	_stealth = maxf(0.0, ctx.num("stealth", 0.0))
	_struck.clear()
	_last_id = 0
	strikes = 0
	var dr := clampf(ctx.num("damage_taken_pct", 50.0), 0.0, 100.0)
	if dr > 0.0:
		player.damage_taken_mults[DR_KEY] = 1.0 - dr / 100.0
	if _invulnerable:
		player.invulnerable_left = maxf(player.invulnerable_left, _interval + 0.05)
	_step(player)  # the first strike lands at once
	return true


func tick(_ctx: AbilityContext, delta: float) -> void:
	if _strikes_left <= 0 and not is_active():
		return
	var player := _player
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		end(false)
		return
	if _invulnerable:
		player.invulnerable_left = maxf(player.invulnerable_left, _interval + 0.05)
	_strike_timer -= delta
	while _strike_timer <= TIME_EPSILON and is_active():
		_step(player)


func begin_wave(_ctx: AbilityContext) -> void:
	end(false)


func end_wave(_ctx: AbilityContext) -> void:
	end(false)


func is_active() -> bool:
	return _strikes_left > 0


## Strikes still to come.
func strikes_left() -> int:
	return _strikes_left


## Ends the spree: the damage reduction goes; with [param finish] an Untouchable spree ends in
## stealth.
func end(finish: bool = true) -> void:
	var was_active := _strikes_left > 0
	_strikes_left = 0
	_close(finish and was_active)


func _close(finish: bool) -> void:
	_struck.clear()
	if _player == null or not is_instance_valid(_player):
		return
	_player.damage_taken_mults.erase(DR_KEY)
	if finish and _stealth > 0.0 and _player.is_alive():
		RogueVanish.shroud(_player, _stealth)


## One jump + strike; ends the spree when it was the last one or nobody is in reach.
func _step(player: Player) -> void:
	_strike_timer += _interval
	var target := _next_target(player)
	if target == null:
		end()
		return
	var from := player.global_position
	var to := RogueUtil.spot_behind(player, target, from)
	RogueUtil.teleport(player, to)
	RogueVfx.streak(from, to)
	_strike(player, target)
	strikes += 1
	_strikes_left -= 1
	if _strikes_left <= 0:
		_strikes_left = 0
		_close(true)


## The next victim: among the living enemies within reach, the one struck least often in this
## spree, nearest first (ties: group order) – never the last target twice in a row unless it is
## the only one left.
func _next_target(player: Player) -> Enemy:
	var here := player.global_position
	var best: Enemy = null
	var best_count := 0
	var best_d := INF
	var last: Enemy = null
	var r_sq := _range * _range
	for node in EnemyGrid.gather_around(player.get_tree(), here, _range):
		var e := node as Enemy
		if e == null or not e.is_inside_tree() or e.is_dead():
			continue
		var dx := e.global_position.x - here.x
		var dz := e.global_position.z - here.z
		var d := dx * dx + dz * dz
		if d > r_sq:
			continue
		var id := e.get_instance_id()
		if id == _last_id:
			last = e
			continue
		var count: int = _struck.get(id, 0)
		if best == null or count < best_count or (count == best_count and d < best_d):
			best = e
			best_count = count
			best_d = d
	return best if best != null else last


func _strike(player: Player, target: Enemy) -> void:
	var id := target.get_instance_id()
	_struck[id] = int(_struck.get(id, 0)) + 1
	_last_id = id
	var weapon := RogueUtil.weapon(player)
	var dir := WeaponRunner.flat(target.global_position - player.global_position)
	dir = dir.normalized() if dir.length_squared() > 0.0001 else player.facing
	player.facing = dir
	player.face_attack(dir)
	var base := (CombatMath.weapon_hit_damage(weapon, player.stats) if weapon != null \
			else RogueUtil.weapon_damage(player)) * _mult
	var crit_mult := RogueUtil.crit_mult(player)
	var victims: Array[Enemy] = [target]
	if _cleave > 0.0:
		for e in RogueUtil.enemies_around(player.get_tree(), target.global_position, _cleave):
			if e != target:
				victims.append(e)
	Vfx.slash_arc(player.global_position + Vector3.UP * 0.3, dir, 1.5 + _cleave * 0.5,
			360.0 if _cleave > 0.0 else 100.0, STRIKE_COLOR)
	var gate := WeaponRunner.ProcGate.new()
	for e in victims:
		if not is_instance_valid(e) or e.is_dead():
			continue
		var crit := player.consume_forced_crit() or CombatMath.roll_crit(player.stats, RunState.rng)
		var push := WeaponRunner.flat(e.global_position - player.global_position)
		push = push.normalized() * KNOCKBACK if push.length_squared() > 0.0001 else Vector3.ZERO
		Vfx.hit_spark(e.global_position + Vector3.UP * 0.6, STRIKE_COLOR)
		WeaponRunner.apply_hit(player, e, base * (crit_mult if crit else 1.0), crit, push, 0.0, 0.5,
				weapon, true, gate.take())


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		end(false)
