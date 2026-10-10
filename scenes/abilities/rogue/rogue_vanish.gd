class_name RogueVanish
extends AbilityEffect
## Vanish (GDD 3.4, Rogue LT, 15 s cooldown): [code]duration[/code] (2) seconds in the
## shadows – the model turns into a translucent, shadowless silhouette (the ghost material of
## the downed look, tinted) behind a smoke puff, and the next weapon hit is a guaranteed
## critical strike ([code]forced_crits[/code], Player.forced_crits).
##
## "Enemies lose you": enemies have no aggro / stealth mechanism yet, so for now Vanish makes
## the player untargetable through the core hook [constant STEALTH_PROPERTY] when Player has
## it, and ALWAYS (unless [code]invulnerable[/code] is 0) gives the same window of full
## invulnerability as the fallback.
##
## Item mod (Shadowstalker Wraps): [code]cooldown_add[/code] = -5 s. AbilityRunner.cooldown_of()
## reads AbilityData.cooldown (not the mod-adjusted params), so this effect shortens the
## running cooldown itself on the first tick after the cast – unless the runner already
## applied the mod.

const SMOKE_COLOR := Color(0.36, 0.33, 0.46)
## The silhouette is the class's onion colour pulled towards this shadow tone.
const SHADOW_TONE := Color(0.12, 0.1, 0.26)
const SHADOW_BLEND := 0.7
const TEXT_COLOR := Color(0.74, 0.68, 0.95)
## Property a core "stealth" hook would add to Player (seconds, counted down by the player).
const STEALTH_PROPERTY := &"stealth_left"
## Bots vanish below this share of their HP when an enemy is this close (m).
const AUTO_HP_RATIO := 0.4
const AUTO_ENEMY_RANGE := 4.0
const COOLDOWN_EPSILON := 0.0001
const TIME_EPSILON := 0.0001

var _player: Player
var _left := 0.0
## The meshes turned into the silhouette, their own materials and the silhouette material.
var _faded: Array[MeshInstance3D] = []
var _originals: Array[Material] = []
var _shadows: Array[int] = []
var _ghost: Material
var _cooldown_check_due := false


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
	apply_stealth(player, _left, ctx.num("invulnerable", 1.0) > 0.0)
	_fade(clampf(ctx.num("opacity", 0.35), 0.05, 1.0))
	_cooldown_check_due = true
	if player.is_inside_tree():
		Vfx.death_puff(player.global_position + Vector3.UP * 0.6, SMOKE_COLOR, 1.3)
		Vfx.floating_text(player.self_text_position(1.0), "Vanish", TEXT_COLOR, Player.SELF_TEXT_SIZE, 1.0)
	return true


func tick(ctx: AbilityContext, delta: float) -> void:
	if _cooldown_check_due:
		_cooldown_check_due = false
		_apply_cooldown_mod(ctx)
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


## Hides [param player] from the enemies for [param seconds]: the core stealth hook when
## Player has [constant STEALTH_PROPERTY], and (with [param invulnerable]) the fallback
## invulnerability window.
static func apply_stealth(player: Player, seconds: float, invulnerable: bool = true) -> void:
	if STEALTH_PROPERTY in player:
		player.set(STEALTH_PROPERTY, maxf(float(player.get(STEALTH_PROPERTY)), seconds))
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


## Applies the item mod "cooldown_add" to the cooldown the runner just started (see header).
func _apply_cooldown_mod(ctx: AbilityContext) -> void:
	var runner := ctx.player.abilities if ctx.player != null else null
	var ability := ctx.ability
	if runner == null or ability == null or ability.cooldown <= 0.0:
		return
	var index := runner.slots.find(ability)
	if index < 0:
		return
	var full := runner.cooldown_of(ability)
	var modded := full * maxf(0.0, ctx.num("cooldown", ability.cooldown)) / ability.cooldown
	var left := runner.remaining(index)
	if left > modded + COOLDOWN_EPSILON:
		runner._cooldown_left[ability.id] = maxf(0.0, left - (full - modded))
