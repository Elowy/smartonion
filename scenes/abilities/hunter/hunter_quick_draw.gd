class_name HunterQuickDraw
extends AbilityEffect
## Quick Draw (GDD 3.7, Hunter Active, 16 s): +[code]haste[/code] (40) % Haste x "power" for
## [code]duration[/code] (4) s – the named stat source [constant KEY] of a [GeneralBuff] (golden
## ring and motes, [HunterHasteVfx]), removed on expiry, when the hero goes down and with the wave.
## The Haste lands on the first physics tick after the cast, so the runner books Quick Draw's own
## cooldown without it (Haste shortens cooldowns, it must not shorten its own).
## While it lasts the buff also carries [code]pierce[/code] (Rank III +1: Stats.PIERCE) and
## [code]extra_arrows[/code] (Rank V "Hail of Shafts" +2: Stats.EXTRA_PROJECTILE – weapon shots
## and Arrow Fan loose that many more arrows). [code]focus_gain[/code] (Rank V "Focus Rush" 35)
## is added to the Focus pool when it is cast.
## Bots draw fast when [code]auto_enemies[/code] (3) enemies are within [code]auto_radius[/code]
## (8) m and it is not running.

const KEY := &"hunter_quick_draw"
const TEXT_COLOR := Color(1.0, 0.82, 0.35)

var _player: Player
var _pending := false
var _haste := 0.0
var _duration := 0.0
var _pierce := 0.0
var _extra_arrows := 0.0


func can_cast(_ctx: AbilityContext) -> bool:
	return not _pending


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_alive() or _pending or GeneralBuff.find(player, KEY) != null:
		return false
	var want := maxi(1, roundi(ctx.num("auto_enemies", 3.0)))
	return GeneralKit.enemies_near(player, ctx.num("auto_radius", 8.0)).size() >= want


func cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_alive():
		return false
	_player = player
	_haste = ctx.num("haste", 40.0) * ctx.num("power", 1.0)
	_duration = maxf(0.1, ctx.num("duration", 4.0))
	_pierce = maxf(0.0, ctx.num("pierce", 0.0))
	_extra_arrows = maxf(0.0, ctx.num("extra_arrows", 0.0))
	_pending = true
	if not player.downed_changed.is_connected(_on_downed_changed):
		player.downed_changed.connect(_on_downed_changed)
	var gain := ctx.num("focus_gain", 0.0)
	var focus := HunterKit.focus(player)
	if gain > 0.0 and focus != null:
		focus.add(gain, false)
	if player.is_inside_tree():
		Vfx.floating_text(player.self_text_position(-1.0) + Vector3.UP * 0.8, "Quick Draw", TEXT_COLOR,
				Player.SELF_TEXT_SIZE, -1.0)
	return true


func tick(_ctx: AbilityContext, _delta: float) -> void:
	if not _pending:
		return
	_pending = false
	if _player == null or not is_instance_valid(_player) or not _player.is_alive():
		return
	var mods := {Stats.HASTE: _haste}
	if _pierce > 0.0:
		mods[Stats.PIERCE] = _pierce
	if _extra_arrows > 0.0:
		mods[Stats.EXTRA_PROJECTILE] = _extra_arrows
	var fresh := GeneralBuff.find(_player, KEY) == null
	var buff := GeneralBuff.apply(_player, KEY, _duration, mods)
	if buff != null and fresh:
		buff.add_child(HunterHasteVfx.new())


func begin_wave(ctx: AbilityContext) -> void:
	_stop(ctx)


func end_wave(ctx: AbilityContext) -> void:
	_stop(ctx)


## The running buff on the caster (null = not drawing fast).
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
