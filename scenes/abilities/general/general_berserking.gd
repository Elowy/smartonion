class_name GeneralBerserking
extends AbilityEffect
## Berserking (GDD 6.4, general Active): +haste % Haste for duration seconds – the named stat
## source [constant KEY] of a [GeneralBuff] (blood-red ring + embers look), removed on expiry,
## when the hero goes down and with the wave.
## The Haste lands on the first physics tick after the cast, so the runner books Berserking's
## own cooldown without it (Haste shortens cooldowns, it must not shorten its own).
##
## Params (rank / spec / item mods change them):
##   haste, duration     +% Haste (x power) and seconds (Rank III: +2 s)
##   kill_extend         Feeding Frenzy (spec): every kill while berserking adds this many
##   max_extend          seconds, at most max_extend in total
##   damage_taken        Reckless Fury (spec): % MORE damage taken while berserking (a
##                       drawback – not scaled by power)
##   auto_enemies, auto_radius   bots go berserk with this many enemies within auto_radius m

const KEY := &"general_berserking"
const TEXT_COLOR := Color(1.0, 0.35, 0.25)

var _player: Player
var _pending := false
var _haste := 0.0
var _duration := 0.0
var _taken := 1.0
var _kill_extend := 0.0
var _max_extend := 0.0


func can_cast(_ctx: AbilityContext) -> bool:
	return not _pending


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_alive() or _pending or GeneralBuff.find(player, KEY) != null:
		return false
	var want := maxi(1, roundi(ctx.num("auto_enemies", 3.0)))
	return GeneralKit.enemies_near(player, ctx.num("auto_radius", 6.0)).size() >= want


func cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_alive():
		return false
	_player = player
	_haste = ctx.num("haste", 20.0) * ctx.num("power", 1.0)
	_duration = maxf(0.1, ctx.num("duration", 6.0))
	_taken = 1.0 + maxf(0.0, ctx.num("damage_taken")) / 100.0
	_kill_extend = maxf(0.0, ctx.num("kill_extend"))
	_max_extend = maxf(0.0, ctx.num("max_extend", 6.0))
	_pending = true
	if not player.downed_changed.is_connected(_on_downed_changed):
		player.downed_changed.connect(_on_downed_changed)
	if not player.enemy_killed.is_connected(_on_enemy_killed):
		player.enemy_killed.connect(_on_enemy_killed)
	if player.is_inside_tree():
		Vfx.floating_text(player.self_text_position(-1.0) + Vector3.UP * 0.8, "Berserking", TEXT_COLOR,
				Player.SELF_TEXT_SIZE, -1.0)
	return true


func tick(_ctx: AbilityContext, _delta: float) -> void:
	if not _pending:
		return
	_pending = false
	if _player == null or not is_instance_valid(_player) or not _player.is_alive():
		return
	GeneralBuff.apply(_player, KEY, _duration, {Stats.HASTE: _haste}, _taken, GeneralAuraVfx.Style.BERSERK)


func begin_wave(ctx: AbilityContext) -> void:
	_stop(ctx)


func end_wave(ctx: AbilityContext) -> void:
	_stop(ctx)


## The running buff on the caster (null = not berserking).
func active_buff() -> GeneralBuff:
	return GeneralBuff.find(_player, KEY) if _player != null and is_instance_valid(_player) else null


func _stop(ctx: AbilityContext) -> void:
	_pending = false
	var player := ctx.player
	if player != null and is_instance_valid(player):
		GeneralBuff.clear_on(player, KEY, false)


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		_pending = false


## Feeding Frenzy: a kill while berserking extends it.
func _on_enemy_killed(_enemy: Node3D) -> void:
	if _kill_extend <= 0.0:
		return
	var buff := active_buff()
	if buff != null:
		buff.extend(_kill_extend, _max_extend)
