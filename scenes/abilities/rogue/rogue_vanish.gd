class_name RogueVanish
extends AbilityEffect
## Vanish (GDD 3.4, Rogue LT, 15 s cooldown): [code]duration[/code] (2) seconds in the
## shadows – the model turns into a translucent, shadowless silhouette (the ghost material of
## the downed look, tinted) behind a smoke puff, and the next weapon hit is a guaranteed
## critical strike ([code]forced_crits[/code], Player.forced_crits).
##
## "Enemies lose you": [member Player.stealth_left] – enemies neither chase, touch nor shoot
## a stealthed player. [code]invulnerable[/code] > 0 adds the same window of full
## invulnerability on top (off in the data).
##
## Item mod (Shadowstalker Wraps): [code]cooldown_add[/code] = -5 s (AbilityRunner.cooldown_of
## reads the modded "cooldown" param).

const SMOKE_COLOR := Color(0.36, 0.33, 0.46)
## The silhouette is the class's onion colour pulled towards this shadow tone.
const SHADOW_TONE := Color(0.12, 0.1, 0.26)
const SHADOW_BLEND := 0.7
const TEXT_COLOR := Color(0.74, 0.68, 0.95)
## Bots vanish below this share of their HP when an enemy is this close (m).
const AUTO_HP_RATIO := 0.4
const AUTO_ENEMY_RANGE := 4.0
const TIME_EPSILON := 0.0001

var _player: Player
var _left := 0.0
## The meshes turned into the silhouette, their own materials and the silhouette material.
var _faded: Array[MeshInstance3D] = []
var _originals: Array[Material] = []
var _shadows: Array[int] = []
var _ghost: Material


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_inside_tree() or player.max_hp() <= 0.0:
		return false
	if player.hp / player.max_hp() >= AUTO_HP_RATIO:
		return false
	return RogueUtil.enemies_within(player, AUTO_ENEMY_RANGE) >= 1


func cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null:
		return false
	end()  # (a recast while still hidden)
	_player = player
	_left = maxf(0.0, ctx.num("duration", 2.0))
	player.forced_crits = maxi(player.forced_crits, int(ctx.num("forced_crits", 1.0)))
	apply_stealth(player, _left, ctx.num("invulnerable", 0.0) > 0.0)
	_fade(clampf(ctx.num("opacity", 0.35), 0.05, 1.0))
	if player.is_inside_tree():
		Vfx.death_puff(player.global_position + Vector3.UP * 0.6, SMOKE_COLOR, 1.3)
		Vfx.floating_text(player.self_text_position(1.0), "Vanish", TEXT_COLOR, Player.SELF_TEXT_SIZE, 1.0)
	return true


func tick(_ctx: AbilityContext, delta: float) -> void:
	if _left > 0.0:
		_left -= delta
		if _left <= TIME_EPSILON:
			end()


## True while the player is vanished.
func is_active() -> bool:
	return _left > TIME_EPSILON


## Seconds of Vanish left.
func time_left() -> float:
	return maxf(0.0, _left)


## Ends the effect now: the model is solid again (a small puff marks the reappearing).
func end() -> void:
	var was_active := _left > 0.0 or not _faded.is_empty()
	_left = 0.0
	for i in _faded.size():
		var mi := _faded[i]
		# Only undo what is still ours (a downed look replaced it meanwhile: keep that one).
		if is_instance_valid(mi) and mi.material_override == _ghost:
			mi.material_override = _originals[i]
			mi.cast_shadow = _shadows[i] as GeometryInstance3D.ShadowCastingSetting
	_faded.clear()
	_originals.clear()
	_shadows.clear()
	_ghost = null
	if was_active and _player != null and is_instance_valid(_player) and _player.is_inside_tree():
		Vfx.death_puff(_player.global_position + Vector3.UP * 0.5, SMOKE_COLOR, 0.8)


## Hides [param player] from the enemies for [param seconds] (and with [param invulnerable]
## also makes it invulnerable for that long).
static func apply_stealth(player: Player, seconds: float, invulnerable: bool = false) -> void:
	player.stealth_left = maxf(player.stealth_left, seconds)
	LivingPlayers.mark_dirty()  # enemies drop the player this tick
	if invulnerable:
		player.invulnerable_left = maxf(player.invulnerable_left, seconds)


## Turns every mesh of the model body (not the ground ring / nameplate) into a translucent
## silhouette with [param opacity] and switches its shadow off. The model's own materials
## ([method Mats.base_material]) are kept for [method end].
func _fade(opacity: float) -> void:
	_faded.clear()
	_originals.clear()
	_shadows.clear()
	if _player == null or _player.model == null:
		return
	var yaw := _player.model.get_node_or_null("Yaw")
	if yaw == null:
		return
	var tint := Color(0.85, 0.9, 1.0)
	if _player.class_data != null:
		tint = _player.class_data.onion_color
	tint = tint.lerp(SHADOW_TONE, SHADOW_BLEND)
	_ghost = Mats.ghost(Color(tint.r, tint.g, tint.b, opacity))
	for node in yaw.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null:
			continue
		_faded.append(mi)
		_originals.append(Mats.base_material(mi))
		_shadows.append(mi.cast_shadow)
		mi.material_override = _ghost
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

