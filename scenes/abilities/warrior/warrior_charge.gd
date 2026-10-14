class_name WarriorCharge
extends AbilityEffect
## Charge (GDD 3.1): the hero dashes in its movement direction (up to ~7 m), stuns the
## enemies it runs into, stuns everything around the landing spot and is invulnerable while it
## runs. The dash stops at walls, the arena bounds and the screen edge.
##
## Params (AbilityData.params; items and ranks change them):
##   distance       maximum dash length in metres
##   speed          dash speed in m/s
##   stun           seconds of stun for enemies hit on the way and around the landing spot
##                  (times "power": Rank II / IV make it longer)
##   stun_radius    landing stun radius in metres (Area Size scales it)
##   buff_damage    % outgoing damage for buff_duration seconds after the dash (0 = none;
##                  Warbringer's Greaves; times "power")
##   buff_duration  seconds the buff lasts
##   impact_pct     % weapon damage dealt to every enemy stunned by the charge (Rank V
##                  "Warbringer"; times "power")
##   rage_gain      Rage gained on landing (Rank V "Furious Charge"; times "power")
##   taunt          seconds the stunned enemies stay taunted to the hero after their stun
##                  (0 = no taunt; Protection talent "Challenging Charge" adds 4). Not
##                  "power"-scaled; ignores stun resistance (bosses can be taunted).
##   shield_per_enemy  absorb shield, % of the hero's Max HP per enemy stunned (0 = none;
##                  Challenging Charge adds 3; not "power"-scaled) ...
##   shield_max     ... at most this % of Max HP in the shield (a second Charge tops it up to
##                  the cap, not past it) ...
##   shield_duration  ... for this many seconds (ProcSystem shield source &"challenging_charge")
##   shockwave_radius / shockwave_stun  Artifact (Earthsplitter, "Shockwave"; 0 = off): on landing
##                  a shockwave stuns every enemy within shockwave_radius metres (Area Size
##                  scales it) for shockwave_stun seconds (not "power"-scaled; a ring effect)
## Rank III: +1 charge (charges_add) – two Charges in a row.
##
## Challenging Charge taunts are released (Enemy.release_taunt – only taunts still aimed at
## this hero) when the hero goes down, at wave start / end and when Charge is forgotten.

## Key of the temporary damage multiplier in Player.damage_mults.
const BUFF_KEY := &"charge"
const DEFAULT_DISTANCE := 7.0
const DEFAULT_SPEED := 36.0
const DEFAULT_STUN := 1.0
const DEFAULT_STUN_RADIUS := 2.0
## Dashes shorter than this (a wall right in front) are refused (and refunded).
const MIN_DISTANCE := 0.8
## Enemies closer than this to the hero's centre line (m, plus their radius) get run over.
const PATH_RADIUS := 0.9
## Invulnerability that outlasts the dash (s).
const INVULNERABLE_PAD := 0.12
## Bots only charge when this much free road lies ahead (m) ...
const AUTO_MIN_FREE := 3.0
## ... to reach an enemy that is at least this far away (m) ...
const AUTO_MIN_GAP := 3.5
## ... or when this many enemies crowd the hero within AUTO_SURROUND_RADIUS ...
const AUTO_SURROUNDED := 3
const AUTO_SURROUND_RADIUS := 3.0
## ... or to flee below this HP ratio when at least AUTO_FLEE_ENEMIES enemies are close.
const AUTO_FLEE_HP := 0.4
const AUTO_FLEE_ENEMIES := 2
## How well the move direction must point at / away from the enemy (cosine).
const AUTO_ALIGNMENT := 0.7
const SPARK_COLOR := Color(1.0, 0.8, 0.45)
## ProcSystem shield source of Challenging Charge.
const SHIELD_SOURCE := &"challenging_charge"
const CHALLENGE_TEXT := "Challenge!"
const CHALLENGE_COLOR := Color(1.0, 0.55, 0.15)
## Taunt sparks shown per Charge at most.
const MAX_TAUNT_SPARKS := 6

var _player: Player
var _dashing := false
var _dir := Vector3.FORWARD
var _left := 0.0
var _speed := DEFAULT_SPEED
var _stun := DEFAULT_STUN
var _stun_radius := DEFAULT_STUN_RADIUS
var _buff_damage := 0.0
var _buff_duration := 0.0
var _buff_left := 0.0
var _impact_pct := 0.0
var _rage_gain := 0.0
var _taunt := 0.0
var _shield_pct := 0.0
var _shield_max := 0.0
var _shield_duration := 0.0
var _shock_radius := 0.0
var _shock_stun := 0.0
var _school: StringName = &"physical"
var _start := Vector3.ZERO
var _hit: Dictionary[int, Enemy] = {}
## Challenging Charge: instance id -> enemy taunted by this hero (values may be freed: untyped).
var _taunted: Dictionary = {}


## Enemies Challenging Charge taunted that are still taunted to this hero (tests, UI).
func taunted() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for id: int in _taunted:
		var v: Variant = _taunted[id]
		if is_instance_valid(v) and (v as Enemy).taunt_target == _player and (v as Enemy).is_taunted():
			out.append(v as Enemy)
	return out


func is_dashing() -> bool:
	return _dashing


## Not while dashing or leaping (WarriorKit.is_displaced): a press then is refunded.
func can_cast(ctx: AbilityContext) -> bool:
	return not _dashing and not WarriorKit.is_displaced(ctx.player)


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	# A bot reviving a teammate stays put (the charge would break the revive).
	if player == null or not player.is_inside_tree() or player.is_reviving():
		return false
	var dir := Vector3(ctx.direction.x, 0.0, ctx.direction.z)
	if dir.length_squared() < 0.0001:
		return false
	dir = dir.normalized()
	var wanted := ctx.num("distance", DEFAULT_DISTANCE)
	if WarriorKit.free_distance(player, dir, wanted) < AUTO_MIN_FREE:
		return false
	var here := player.global_position
	var close := WarriorKit.enemies_around(player.get_tree(), here, AUTO_SURROUND_RADIUS)
	var hp_ratio := player.hp / player.max_hp() if player.max_hp() > 0.0 else 1.0
	# Escape: low HP, enemies close and the move direction leads away from them.
	if hp_ratio < AUTO_FLEE_HP and close.size() >= AUTO_FLEE_ENEMIES:
		var centre := Vector3.ZERO
		for e in close:
			centre += e.global_position
		var away := here - centre / float(close.size())
		away.y = 0.0
		return away.length_squared() > 0.0001 and dir.dot(away.normalized()) > 0.3
	# Close in: a gap to the nearest enemy, not surrounded, running at it.
	if hp_ratio < AUTO_FLEE_HP or close.size() >= AUTO_SURROUNDED or ctx.target == null:
		return false
	var to := ctx.target.global_position - here
	to.y = 0.0
	return to.length() >= AUTO_MIN_GAP and dir.dot(to.normalized()) >= AUTO_ALIGNMENT


func cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or _dashing:
		return false
	var dir := Vector3(ctx.direction.x, 0.0, ctx.direction.z)
	if dir.length_squared() < 0.0001:
		dir = Vector3(player.facing.x, 0.0, player.facing.z)
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var distance := WarriorKit.free_distance(player, dir, ctx.num("distance", DEFAULT_DISTANCE))
	if distance < MIN_DISTANCE:
		return false
	_player = player
	_dir = dir
	_left = distance
	_start = player.global_position
	var power := ctx.num("power", 1.0)
	_speed = maxf(1.0, ctx.num("speed", DEFAULT_SPEED))
	_stun = ctx.num("stun", DEFAULT_STUN) * power
	_stun_radius = ctx.num("stun_radius", DEFAULT_STUN_RADIUS) * CombatMath.area_mult(player.stats)
	_buff_damage = ctx.num("buff_damage") * power
	_buff_duration = ctx.num("buff_duration")
	_impact_pct = ctx.num("impact_pct") * power
	_rage_gain = ctx.num("rage_gain") * power
	_taunt = maxf(0.0, ctx.num("taunt"))
	_shield_pct = maxf(0.0, ctx.num("shield_per_enemy"))
	_shield_max = maxf(0.0, ctx.num("shield_max", 15.0))
	_shield_duration = maxf(0.0, ctx.num("shield_duration", 5.0))
	_shock_radius = maxf(0.0, ctx.num("shockwave_radius")) * CombatMath.area_mult(player.stats)
	_shock_stun = maxf(0.0, ctx.num("shockwave_stun"))
	_school = ctx.ability.school
	_hit.clear()
	_prune_taunted()
	_dashing = true
	if not player.downed_changed.is_connected(_on_downed_changed):
		player.downed_changed.connect(_on_downed_changed)
	player.facing = dir
	player.velocity = Vector3.ZERO
	player.invulnerable_left = maxf(player.invulnerable_left, distance / _speed + INVULNERABLE_PAD)
	Vfx.hit_spark(_start + Vector3.UP * 0.4, SPARK_COLOR)
	return true


func tick(_ctx: AbilityContext, delta: float) -> void:
	if _buff_left > 0.0:
		_buff_left -= delta
		if _buff_left <= 0.0:
			_clear_buff()
	if not _dashing:
		return
	var player := _player
	if player == null or not is_instance_valid(player):
		_dashing = false
		return
	var step := minf(_speed * delta, _left)
	var from := player.global_position
	var motion := _dir * step
	if player.is_inside_tree():
		player.move_and_collide(motion)
	else:
		player.position += motion
	var to := WarriorKit.keep_in_play_area(player, from, player.global_position)
	if to != player.global_position:
		player.global_position = to
	player.velocity = Vector3.ZERO
	player.invulnerable_left = maxf(player.invulnerable_left, INVULNERABLE_PAD)
	_left -= step
	_run_over(player)
	var moved := Vector2(to.x - from.x, to.z - from.z).length()
	if _left <= 0.001 or moved < step - 0.01:
		_arrive(player)


## Stuns the enemies the hero touches on its way (once each).
func _run_over(player: Player) -> void:
	for e in WarriorKit.enemies_within(player, Player.RADIUS + PATH_RADIUS):
		var id := e.get_instance_id()
		if _hit.has(id):
			continue
		_hit[id] = e
		e.apply_stun(_stun)


## The dash ends (full length, wall or bounds): landing stun, effects, the Greaves buff.
func _arrive(player: Player) -> void:
	_dashing = false
	player.velocity = Vector3.ZERO
	player.invulnerable_left = maxf(player.invulnerable_left, INVULNERABLE_PAD)
	var victims: Dictionary[int, Enemy] = _hit.duplicate()
	for e in WarriorKit.enemies_within(player, _stun_radius):
		victims[e.get_instance_id()] = e
	var impact := WarriorKit.weapon_damage(player) * _impact_pct / 100.0
	var stunned := 0
	for id in victims:
		# (An enemy run over earlier may have died and been freed meanwhile.)
		var v: Variant = victims[id]
		if not is_instance_valid(v):
			continue
		var e := v as Enemy
		if not e.is_dead():
			e.apply_stun(_stun)
			stunned += 1
			if impact > 0.0 and player.procs != null:
				player.procs.deal_raw(e, impact, _school, true, &"ability")
	_challenge(player, victims, stunned)
	_hit.clear()
	WarriorChargeVfx.spawn(_start, player.global_position, _stun_radius)
	_shockwave(player)
	if _buff_damage > 0.0 and _buff_duration > 0.0:
		player.damage_mults[BUFF_KEY] = 1.0 + _buff_damage / 100.0
		_buff_left = _buff_duration
	if _rage_gain > 0.0:
		WarriorKit.add_rage(player, _rage_gain)


## Earthsplitter's "Shockwave": the landing stuns everything within shockwave_radius.
func _shockwave(player: Player) -> void:
	if _shock_radius <= 0.0 or _shock_stun <= 0.0:
		return
	for e in WarriorKit.enemies_within(player, _shock_radius):
		if not e.is_dead():
			e.apply_stun(_shock_stun)
	WarriorClapVfx.spawn(player.global_position, _shock_radius)


## A new wave starts without a dash or buff.
func begin_wave(_ctx: AbilityContext) -> void:
	_stop()


## The market shows no dash or buff (also when the ability is forgotten).
func end_wave(_ctx: AbilityContext) -> void:
	_stop()


func _stop() -> void:
	_dashing = false
	_hit.clear()
	_clear_buff()
	_release_taunts()


## Challenging Charge on landing: the living victims ([param count] were stunned) are taunted
## to the hero for the stun + taunt seconds, and the hero gains the absorb shield.
func _challenge(player: Player, victims: Dictionary[int, Enemy], count: int) -> void:
	if count <= 0 or (_taunt <= 0.0 and _shield_pct <= 0.0):
		return
	var shown := player.is_inside_tree()
	if _taunt > 0.0:
		var sparks := 0
		for id in victims:
			var v: Variant = victims[id]
			if not is_instance_valid(v) or (v as Enemy).is_dead():
				continue
			var e := v as Enemy
			e.apply_taunt(player, _stun + _taunt)
			_taunted[id] = e
			if shown and sparks < MAX_TAUNT_SPARKS and e.is_inside_tree():
				sparks += 1
				Vfx.hit_spark(e.global_position + Vector3.UP * (WarriorSpin.SPARK_HEIGHT + 0.6), CHALLENGE_COLOR)
	if _shield_pct > 0.0 and player.procs != null:
		var max_hp := player.max_hp()
		var room := max_hp * _shield_max / 100.0 - player.procs.shield_of(SHIELD_SOURCE)
		var amount := minf(max_hp * float(count) * _shield_pct / 100.0, room)
		if amount > 0.0:
			player.procs.add_shield(amount, _shield_duration, SHIELD_SOURCE)
			if shown:
				Vfx.explosion(player.global_position + Vector3.UP * 0.1, 1.2, ProcSystem.SHIELD_COLOR)
	WarriorKit.shout_text(player, CHALLENGE_TEXT, CHALLENGE_COLOR)


## Ends every Challenging Charge taunt still aimed at this hero (another hero's taunt stays).
func _release_taunts() -> void:
	if _taunted.is_empty():
		return
	for id: int in _taunted:
		var v: Variant = _taunted[id]
		if is_instance_valid(v) and is_instance_valid(_player):
			(v as Enemy).release_taunt(_player)
	_taunted.clear()


## Forgets taunted enemies that are gone or no longer taunted to this hero.
func _prune_taunted() -> void:
	if _taunted.is_empty():
		return
	for id: int in _taunted.keys():
		var v: Variant = _taunted[id]
		if not is_instance_valid(v) or (v as Enemy).is_dead() or (v as Enemy).taunt_target != _player \
				or (v as Enemy).taunt_left <= 0.0:
			_taunted.erase(id)


func _clear_buff() -> void:
	_buff_left = 0.0
	if _player != null and is_instance_valid(_player):
		_player.damage_mults.erase(BUFF_KEY)


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		_stop()
