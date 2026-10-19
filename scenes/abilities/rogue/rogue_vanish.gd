class_name RogueVanish
extends AbilityEffect
## Vanish (GDD 3.4, Rogue LT, 15 s cooldown): [code]duration[/code] (2) seconds in the
## shadows – the model turns into a translucent, shadowless silhouette (the ghost material of
## the downed look, tinted) behind a smoke puff, the Rogue recovers
## [code]heal_max_hp_pct[/code] (30) % of its max HP, and the next weapon hit is a guaranteed
## critical strike ([code]forced_crits[/code], Player.forced_crits).
##
## "Enemies lose you": [member Player.stealth_left] – enemies neither chase, touch nor shoot
## a stealthed player. [code]invulnerable[/code] > 0 adds the same window of full
## invulnerability on top (off in the data).
##
## Item mod (Shadowstalker Wraps): [code]cooldown_add[/code] = -5 s (AbilityRunner.cooldown_of
## reads the modded "cooldown" param).
## Ranks (M4): the heal scales with "power"; Rank III +1 s in the shadows; Rank V "Smoke Bomb"
## (enemies within [code]smoke_radius[/code] m are stunned for [code]smoke_stun[/code] s) or
## "Shadow Veil" ([code]invulnerable[/code] while hidden and [code]speed_pct[/code] % x power
## Speed, StatBlock source [constant SPEED_SOURCE], removed when the Vanish ends).
##
## The silhouette survives look changes during the effect: whatever the model puts back on a
## faded mesh (the HP peel of OnionModel.set_hp_ratio on a heal / stat change) becomes the
## mesh's new "own" material and the mesh is faded again (at once on hp_changed and every
## tick). The effect ends early when the player goes down (before the downed ghost look saves
## the materials), and with the wave (begin_wave / end_wave).
##
## M5 talent params (neutral defaults in the data – talents_rogue.md 4.3):
##   [code]end_fan[/code] (0)      – Unseen Blades: when the Vanish runs out on its own (not a
##                                   recast, going down or a wave hook), the hero throws a free
##                                   Fan of Knives (RogueFanOfKnives.throw_free).
##   [code]auto_offense[/code] (0) – bots only (Vanish is a core LT slot humans press): above
##                                   0, a bot also vanishes offensively – HP at least
##                                   AUTO_OFFENSE_HP, AUTO_OFFENSE_MIN enemies within
##                                   AUTO_OFFENSE_RANGE m, Energy at least AUTO_OFFENSE_ENERGY
##                                   and not reviving a teammate. Every Subtlety talent that
##                                   rewards casting Vanish adds it.

const SMOKE_COLOR := Color(0.36, 0.33, 0.46)
const SPEED_SOURCE := &"vanish"
## Silhouette opacity of a shroud (Vanish itself reads the "opacity" param).
const DEFAULT_OPACITY := 0.4
## The silhouette is the class's onion colour pulled towards this shadow tone.
const SHADOW_TONE := Color(0.12, 0.1, 0.26)
const SHADOW_BLEND := 0.7
const TEXT_COLOR := Color(0.74, 0.68, 0.95)
## Bots vanish below this share of their HP when an enemy is this close (m).
const AUTO_HP_RATIO := 0.4
const AUTO_ENEMY_RANGE := 4.0
## Offensive bot rule ("auto_offense" > 0): healthy, in a pack, with Energy for the fans.
const AUTO_OFFENSE_HP := 0.5
const AUTO_OFFENSE_MIN := 3
const AUTO_OFFENSE_RANGE := 5.0
const AUTO_OFFENSE_ENERGY := 50.0
const TIME_EPSILON := 0.0001

var _player: Player
var _left := 0.0
## Unseen Blades: this Vanish throws a free fan when it runs out (cleared by every end).
var _end_fan := false
## Free fans thrown by Unseen Blades (tests).
var end_fans := 0
## The meshes turned into the silhouette, their own materials and the silhouette material.
var _faded: Array[MeshInstance3D] = []
var _originals: Array[Material] = []
var _shadows: Array[int] = []
var _ghost: Material


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_inside_tree() or player.max_hp() <= 0.0:
		return false
	var ratio := player.hp / player.max_hp()
	if ratio < AUTO_HP_RATIO:
		return RogueUtil.enemies_within(player, AUTO_ENEMY_RANGE) >= 1
	if ctx.num("auto_offense", 0.0) <= 0.0 or ratio < AUTO_OFFENSE_HP or player.is_reviving():
		return false
	var energy := player.abilities.get_resource(RogueUtil.ENERGY_ID) if player.abilities != null else null
	if energy == null or energy.value < AUTO_OFFENSE_ENERGY:
		return false
	return RogueUtil.enemies_within(player, AUTO_OFFENSE_RANGE) >= AUTO_OFFENSE_MIN


func cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null:
		return false
	end()  # (a recast while still hidden: the old Vanish throws no Unseen Blades fan)
	_player = player
	_connect(player)
	_left = maxf(0.0, ctx.num("duration", 2.0))
	_end_fan = ctx.num("end_fan", 0.0) > 0.0 and _left > 0.0
	player.forced_crits = maxi(player.forced_crits, int(ctx.num("forced_crits", 1.0)))
	apply_stealth(player, _left, ctx.num("invulnerable", 0.0) > 0.0)
	var power := ctx.num("power", 1.0)
	var heal_pct := ctx.num("heal_max_hp_pct", 0.0) * power
	if heal_pct > 0.0:
		player.heal(player.max_hp() * heal_pct / 100.0)
	var speed := ctx.num("speed_pct", 0.0) * power
	if speed > 0.0 and _left > 0.0:
		player.stats.set_source(SPEED_SOURCE, {Stats.SPEED: speed})
	_fade(clampf(ctx.num("opacity", 0.35), 0.05, 1.0))
	if player.is_inside_tree():
		Vfx.death_puff(player.global_position + Vector3.UP * 0.6, SMOKE_COLOR, 1.3)
		_smoke_bomb(player, ctx.num("smoke_radius", 0.0), ctx.num("smoke_stun", 0.0))
		Vfx.floating_text(player.self_text_position(1.0), "Melt Away", TEXT_COLOR, Player.SELF_TEXT_SIZE, 1.0)
	return true


func tick(_ctx: AbilityContext, delta: float) -> void:
	if _left > 0.0:
		_refade()
		_left -= delta
		if _left <= TIME_EPSILON:
			var fan := _end_fan
			end()
			if fan and RogueFanOfKnives.throw_free(_player):
				end_fans += 1


## A new wave starts visible (Player.begin_wave already dropped the stealth).
func begin_wave(_ctx: AbilityContext) -> void:
	end(false)


## The market shows the solid hero (no smoke puff: the tree is about to pause).
func end_wave(_ctx: AbilityContext) -> void:
	end(false)


## True while the player is vanished.
func is_active() -> bool:
	return _left > TIME_EPSILON


## Seconds of Vanish left.
func time_left() -> float:
	return maxf(0.0, _left)


## Ends the effect now: the model is solid again (with [param puff] a small puff marks the
## reappearing).
func end(puff: bool = true) -> void:
	var was_active := _left > 0.0 or not _faded.is_empty()
	_left = 0.0
	_end_fan = false
	for i in _faded.size():
		var mi := _faded[i]
		if not is_instance_valid(mi):
			continue
		# Only undo the material that is still ours (the silhouette, maybe hit-flash tinted);
		# a look the model put on meanwhile stays. The shadow always comes back.
		if Mats.base_material(mi) == _ghost:
			mi.material_override = _originals[i]
		mi.cast_shadow = _shadows[i] as GeometryInstance3D.ShadowCastingSetting
	_faded.clear()
	_originals.clear()
	_shadows.clear()
	_ghost = null
	if _player != null and is_instance_valid(_player):
		_player.stats.remove_source(SPEED_SOURCE)
	if puff and was_active and _player != null and is_instance_valid(_player) and _player.is_inside_tree():
		Vfx.death_puff(_player.global_position + Vector3.UP * 0.5, SMOKE_COLOR, 0.8)


## Smoke Bomb: every enemy within [param radius] m (Area Size scales it) is stunned for
## [param seconds].
static func _smoke_bomb(player: Player, radius: float, seconds: float) -> void:
	if radius <= 0.0 or seconds <= 0.0:
		return
	var r := radius * CombatMath.area_mult(player.stats)
	for e in RogueUtil.enemies_around(player.get_tree(), player.global_position, r):
		e.apply_stun(seconds)
	Vfx.explosion(player.global_position + Vector3.UP * 0.2, r, SMOKE_COLOR)
	Vfx.death_puff(player.global_position + Vector3.UP * 0.4, SMOKE_COLOR, r * 0.8)


## Hides [param player] like Vanish for [param seconds] – stealth plus the shadow silhouette
## (through the Rogue's Vanish effect, when it has one) – without the heal or the guaranteed
## crit: Cheat Death's Shadow Escape, Killing Spree's Untouchable.
static func shroud(player: Player, seconds: float) -> void:
	if player == null or seconds <= 0.0:
		return
	apply_stealth(player, seconds)
	var vanish := of(player)
	if vanish != null:
		vanish.hide_for(player, seconds)


## The Vanish effect of [param player] (null when it has none).
static func of(player: Player) -> RogueVanish:
	if player == null or player.abilities == null:
		return null
	for a in player.abilities.slots:
		var e := player.abilities.effect_for(a) as RogueVanish
		if e != null:
			return e
	return null


## Shows the silhouette for [param seconds] (a running Vanish is only extended).
func hide_for(player: Player, seconds: float) -> void:
	if is_active():
		_left = maxf(_left, seconds)
		return
	end(false)
	_player = player
	_connect(player)
	_left = seconds
	_fade(DEFAULT_OPACITY)
	if player.is_inside_tree():
		Vfx.death_puff(player.global_position + Vector3.UP * 0.6, SMOKE_COLOR, 1.0)


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


## Fades again every mesh whose silhouette the model replaced (OnionModel.set_hp_ratio puts
## the HP-peel skin on the bulb): that material is the mesh's own one from now on.
func _refade() -> void:
	if _ghost == null or _player == null or not is_instance_valid(_player) or not _player.is_alive():
		return
	for i in _faded.size():
		var mi := _faded[i]
		if not is_instance_valid(mi):
			continue
		var base := Mats.base_material(mi)
		if base == _ghost:
			continue  # still ours (a hit flash only tints it)
		_originals[i] = base
		mi.material_override = _ghost
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _connect(player: Player) -> void:
	if not player.hp_changed.is_connected(_on_hp_changed):
		player.hp_changed.connect(_on_hp_changed)
	if not player.downed_changed.is_connected(_on_downed_changed):
		player.downed_changed.connect(_on_downed_changed)


## Player._hp_updated: after the model's look was refreshed. At 0 HP the player is about to
## go down – end now, so the downed ghost look saves the solid materials, not the silhouette.
func _on_hp_changed(hp: float, _max_hp: float) -> void:
	if _faded.is_empty():
		return
	if hp <= 0.0:
		end(false)
	elif _left > TIME_EPSILON:
		_refade()


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		end(false)

