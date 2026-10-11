class_name RogueBladeFlurry
extends AbilityEffect
## Blade Flurry (GDD 6.4, Rogue Auto): for [code]duration[/code] (5) seconds every weapon hit
## of the Rogue (daggers, thrown knives and shuriken, Killing Spree strikes) also strikes
## [code]targets[/code] (1) other enemies – the nearest living ones within [code]range[/code]
## (5) m of the enemy that was hit – for [code]damage_pct[/code] (60) % of that hit x "power".
##
## Listens to Player.hit_dealt while active. The echo is ability damage
## (ProcSystem.deal_raw(..., &"ability")), not a weapon hit, so it never echoes again, rolls
## no procs and gives no Combo Points; the hit's own outgoing multipliers and the struck
## enemy's Executioner / Slayer bonus are taken out first (deal_raw applies them again for
## the new target, with that target's own bonus), its crit is kept.
## Rank III: +1 extra target. Rank V: "Relentless Flurry" ([code]extend_on_kill[/code]: every
## kill while it lasts adds that many seconds, up to [code]max_extend[/code]) or "Adrenaline
## Rush" ([code]haste_pct[/code] % Haste x power while it lasts, StatBlock source
## [constant HASTE_SOURCE]).
## Ends with the duration, when the Rogue goes down, with the wave, and when forgotten.

const HASTE_SOURCE := &"blade_flurry"
const ECHO_COLOR := Color(0.9, 0.92, 1.0)
## Auto-cast: at least this many enemies within AUTO_RANGE m (an echo needs a second target).
const AUTO_MIN_ENEMIES := 2
const AUTO_RANGE := 3.5
const TIME_EPSILON := 0.0001

var _player: Player
var _left := 0.0
var _targets := 1
var _range := 5.0
var _pct := 60.0
var _power := 1.0
var _extend := 0.0
var _extend_left := 0.0
var _vfx: RogueFlurryVfx
## Re-entrancy guard: an echo that kills may trigger kill effects that hit again.
var _echoing := false


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_inside_tree() or is_active():
		return false
	return RogueUtil.enemies_within(player, AUTO_RANGE) >= AUTO_MIN_ENEMIES


func can_cast(_ctx: AbilityContext) -> bool:
	return not is_active()


func cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null:
		return false
	end()
	_player = player
	_left = maxf(0.0, ctx.num("duration", 5.0))
	_targets = maxi(1, roundi(ctx.num("targets", 1.0)))
	_range = maxf(0.5, ctx.num("range", 5.0))
	_pct = maxf(0.0, ctx.num("damage_pct", 60.0))
	_power = ctx.num("power", 1.0)
	_extend = maxf(0.0, ctx.num("extend_on_kill", 0.0))
	_extend_left = maxf(0.0, ctx.num("max_extend", 5.0))
	var haste := ctx.num("haste_pct", 0.0) * _power
	if haste > 0.0:
		player.stats.set_source(HASTE_SOURCE, {Stats.HASTE: haste})
	if not player.hit_dealt.is_connected(_on_hit_dealt):
		player.hit_dealt.connect(_on_hit_dealt)
	if not player.enemy_killed.is_connected(_on_enemy_killed):
		player.enemy_killed.connect(_on_enemy_killed)
	if not player.downed_changed.is_connected(_on_downed_changed):
		player.downed_changed.connect(_on_downed_changed)
	_vfx = RogueFlurryVfx.attach(player)
	if player.is_inside_tree():
		Vfx.slash_arc(player.global_position + Vector3.UP * 0.3, player.facing, 1.6, 360.0, ECHO_COLOR)
	return true


func tick(_ctx: AbilityContext, delta: float) -> void:
	if _left <= 0.0:
		return
	_left -= delta
	if _left <= TIME_EPSILON:
		end()


func begin_wave(_ctx: AbilityContext) -> void:
	end()


## Wave end and forget (the runner calls end_wave when the ability is replaced).
func end_wave(_ctx: AbilityContext) -> void:
	end()


func is_active() -> bool:
	return _left > TIME_EPSILON


func time_left() -> float:
	return maxf(0.0, _left)


## Stops the flurry: no more echoes, the Haste buff and the blades around the Rogue go.
func end() -> void:
	_left = 0.0
	if _player != null and is_instance_valid(_player):
		_player.stats.remove_source(HASTE_SOURCE)
		if _player.hit_dealt.is_connected(_on_hit_dealt):
			_player.hit_dealt.disconnect(_on_hit_dealt)
		if _player.enemy_killed.is_connected(_on_enemy_killed):
			_player.enemy_killed.disconnect(_on_enemy_killed)
	if _vfx != null and is_instance_valid(_vfx):
		_vfx.queue_free()
	_vfx = null


## Damage of one echo of a weapon hit that dealt [param hit_damage] (after the owner's outgoing
## multiplier [param outgoing] and the struck enemy's target bonus [param target_bonus]) –
## before deal_raw re-applies the multipliers.
static func echo_damage(hit_damage: float, outgoing: float, pct: float, power: float,
		target_bonus: float = 1.0) -> float:
	return maxf(0.0, hit_damage) / maxf(0.01, outgoing) / maxf(0.01, target_bonus) * pct / 100.0 * power


func _on_hit_dealt(damage: float, target: Node3D) -> void:
	if _echoing or not is_active() or _player == null or not is_instance_valid(_player) \
			or not _player.is_alive() or _player.procs == null or target == null \
			or not is_instance_valid(target) or not target.is_inside_tree():
		return
	var school := _player.main_hand.school if _player.main_hand != null else CombatMath.SCHOOL_PHYSICAL
	# The struck enemy's Executioner / Slayer, judged at its HP before the hit (Enemy.take_damage
	# does not clamp, so hp + damage is that HP even after a killing blow).
	var bonus := 1.0
	var hit := target as Enemy
	if hit != null and hit.max_hp > 0.0:
		var before := clampf((hit.hp + damage) / hit.max_hp, 0.0, 1.0)
		bonus = CombatMath.target_damage_mult(_player.stats, before, hit.is_elite())
	var amount := echo_damage(damage, _player.outgoing_damage_mult(target, school, &"weapon"), _pct, _power,
			bonus)
	if amount <= 0.0:
		return
	var skip: Dictionary[int, bool] = {target.get_instance_id(): true}
	var others := RogueUtil.nearest_enemies(_player.get_tree(), target.global_position, _range, _targets, skip)
	if others.is_empty():
		return
	_echoing = true
	var from := target.global_position + Vector3.UP * 0.7
	for e in others:
		if not is_instance_valid(e) or e.is_dead():
			continue
		var at := e.global_position + Vector3.UP * 0.7
		ProcVfx.beam(from, at, ECHO_COLOR)
		Vfx.hit_spark(at, ECHO_COLOR)
		_player.procs.deal_raw(e, amount, CombatMath.SCHOOL_PHYSICAL, true, &"ability")
	_echoing = false


## Relentless Flurry: a kill while the flurry lasts extends it (up to max_extend in total).
func _on_enemy_killed(_enemy: Node3D) -> void:
	if _extend <= 0.0 or not is_active() or _extend_left <= 0.0:
		return
	var add := minf(_extend, _extend_left)
	_extend_left -= add
	_left += add


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		end()
