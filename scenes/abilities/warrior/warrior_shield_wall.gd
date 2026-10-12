class_name WarriorShieldWall
extends AbilityEffect
## Shield Wall (GDD 6.4, Warrior Active): for [code]duration[/code] seconds the Warrior takes
## [code]reduction[/code] % less damage (times "power", at most MAX_REDUCTION):
## Player.damage_taken_mults[KEY]. A recast refreshes it.
##
## Params (AbilityData.params; items and ranks change them):
##   reduction (%), duration (Rank III +2 s)
##   last_stand     Rank V "Last Stand": while the wall stands a lethal hit leaves the Warrior
##                  at 1 HP (a Player.death_guards entry)
##   retaliate      Rank V "Spiked Wall": every enemy that hits the Warrior takes this %
##                  weapon damage (times "power")
##
## Ends on expiry, when the Warrior goes down, at wave end / start and when forgotten.
## Bots raise it when hurt (below AUTO_HP_RATIO) with an enemy within AUTO_ENEMY_RANGE, or
## when at least AUTO_CROWD enemies press in.

const KEY := &"shield_wall"
const DEFAULT_REDUCTION := 50.0
const MAX_REDUCTION := 80.0
const AUTO_HP_RATIO := 0.5
const AUTO_ENEMY_RANGE := 4.0
const AUTO_CROWD := 6
const AUTO_CROWD_RANGE := 3.5
const TEXT_COLOR := Color(0.65, 0.8, 1.0)
const SPARK_COLOR := Color(1.0, 0.6, 0.45)

var _player: Player
var _left := 0.0
var _last_stand := false
var _retaliate_pct := 0.0
var _school: StringName = &"physical"
var _guard := Callable()
var _look: WarriorShieldWallVfx
## Lethal hits survived / retaliation hits dealt during the current wall (tests).
var saves := 0
var retaliations := 0


func is_active() -> bool:
	return _left > 0.0


func time_left() -> float:
	return maxf(0.0, _left)


## True while a wall with the Rank V "Last Stand" spec stands: its death guard would save a
## lethal hit (Protection's Unbreakable capstone defers to it and stays unused).
func guards_lethal() -> bool:
	return _left > 0.0 and _last_stand


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree() or is_active():
		return false
	var hurt := p.max_hp() > 0.0 and p.hp / p.max_hp() < AUTO_HP_RATIO
	if hurt and not WarriorKit.enemies_within(p, AUTO_ENEMY_RANGE).is_empty():
		return true
	return WarriorKit.enemies_within(p, AUTO_CROWD_RANGE).size() >= AUTO_CROWD


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null:
		return false
	end()
	_player = p
	var reduction := clampf(ctx.num("reduction", DEFAULT_REDUCTION) * ctx.num("power", 1.0), 0.0, MAX_REDUCTION)
	p.damage_taken_mults[KEY] = 1.0 - reduction / 100.0
	_left = maxf(0.1, ctx.num("duration", 4.0))
	_last_stand = ctx.flag("last_stand")
	_retaliate_pct = ctx.num("retaliate") * ctx.num("power", 1.0)
	_school = ctx.ability.school
	saves = 0
	retaliations = 0
	if _last_stand:
		_guard = _on_lethal_hit
		p.death_guards.append(_guard)
	if not p.downed_changed.is_connected(_on_downed_changed):
		p.downed_changed.connect(_on_downed_changed)
	if _retaliate_pct > 0.0 and not p.damage_taken.is_connected(_on_damage_taken):
		p.damage_taken.connect(_on_damage_taken)
	var style := WarriorShieldWallVfx.Style.PLAIN
	if _last_stand:
		style = WarriorShieldWallVfx.Style.LAST_STAND
	elif _retaliate_pct > 0.0:
		style = WarriorShieldWallVfx.Style.SPIKED
	_look = WarriorShieldWallVfx.spawn(p, style)
	WarriorKit.shout_text(p, ctx.ability.display_name, TEXT_COLOR)
	return true


func tick(_ctx: AbilityContext, delta: float) -> void:
	if _left <= 0.0:
		return
	_left -= delta
	if _left <= 0.0:
		end()


func begin_wave(_ctx: AbilityContext) -> void:
	end()


## The market shows no wall (also when the ability is forgotten).
func end_wave(_ctx: AbilityContext) -> void:
	end()


## Drops the wall now: damage reduction, guard, retaliation and the look.
func end() -> void:
	_left = 0.0
	if is_instance_valid(_player):
		_player.damage_taken_mults.erase(KEY)
		if _guard.is_valid():
			_player.death_guards.erase(_guard)
		if _player.damage_taken.is_connected(_on_damage_taken):
			_player.damage_taken.disconnect(_on_damage_taken)
	_guard = Callable()
	_last_stand = false
	_retaliate_pct = 0.0
	if is_instance_valid(_look) and not _look.is_queued_for_deletion():
		_look.dismiss()
	_look = null


## Player.death_guards: survive a lethal hit at 1 HP while the wall stands.
func _on_lethal_hit() -> bool:
	if _left <= 0.0 or not _last_stand:
		return false
	saves += 1
	if is_instance_valid(_player) and _player.is_inside_tree():
		Vfx.floating_text(_player.self_text_position(1.0), "Last Stand", WarriorShieldWallVfx.LAST_STAND_COLOR,
				Player.SELF_TEXT_SIZE, 1.0)
	return true


## Spiked Wall: the attacker takes the retaliation damage.
func _on_damage_taken(_amount: float, source: Node3D) -> void:
	if _left <= 0.0 or _retaliate_pct <= 0.0 or not is_instance_valid(_player) or _player.procs == null:
		return
	var attacker: Enemy = source as Enemy if is_instance_valid(source) else null
	if attacker == null or attacker.is_dead():
		return
	var spot := attacker.global_position + Vector3.UP * WarriorSpin.SPARK_HEIGHT
	_player.procs.deal_raw(attacker, WarriorKit.weapon_damage(_player) * _retaliate_pct / 100.0, _school, true, &"ability")
	retaliations += 1
	Vfx.hit_spark(spot, SPARK_COLOR)


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		end()
