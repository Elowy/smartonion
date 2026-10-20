class_name HunterPlayDead
extends AbilityEffect
## Play Dead (GDD 3.7, Hunter Active, 20 s): for [code]duration[/code] (2) s the Hunter collapses
## and plays dead – the onion tips over on its side (OnionModel.set_play_dead; no ghost
## silhouette: that is Melt Away's look). "Enemies lose you": [member Player.stealth_left] –
## enemies neither chase, touch nor shoot a stealthed player (the same hook Vanish uses); AoE
## already on the ground still hurts.
## Rank III: [code]decoy_radius[/code] +4 m – the companion draws the enemies within that radius
## of the Hunter to itself (a taunt, refreshed every [constant TAUNT_REFRESH] s while it lasts and
## released when it ends; needs a living companion).
## Rank V: "Patient Predator" ([code]forced_crits[/code] 3: when the Hunter rises, its next three
## weapon hits are guaranteed critical strikes – Player.forced_crits; not granted when the effect
## is cut short by going down or a wave hook) or "Rest and Recover" ([code]heal_max_hp_pct[/code]
## +30: that share of the Max HP, x "power", is restored evenly while playing dead).
## Bots play dead when badly hurt ([code]auto_hp[/code] % or less) with an enemy within
## [constant AUTO_ENEMY_RANGE] m, or when [code]auto_enemies[/code] (6) enemies crowd within
## [code]auto_radius[/code] (3) m.

const AUTO_ENEMY_RANGE := 4.0
const TAUNT_REFRESH := 0.5
const HEAL_TICK := 0.25
const TIME_EPSILON := 0.0001
const TEXT_COLOR := Color(0.8, 0.76, 0.66)
const DUST := Color(0.74, 0.66, 0.5)

var _player: Player
var _left := 0.0
var _duration := 0.0
var _forced := 0
var _heal_rate := 0.0
var _heal_left := 0.0
## Healing earned but not yet paid out (paid in HEAL_TICK steps, so the numbers do not spam).
var _heal_owed := 0.0
var _heal_timer := HEAL_TICK
var _decoy_radius := 0.0
var _taunt_left := 0.0
## Enemies taunted to the companion by the decoy (values may be freed: untyped).
var _taunted: Dictionary = {}
## Times the Hunter rose on its own (tests).
var risen := 0


func is_active() -> bool:
	return _left > TIME_EPSILON


## Seconds of Play Dead left.
func time_left() -> float:
	return maxf(0.0, _left)


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_inside_tree() or player.max_hp() <= 0.0 or is_active():
		return false
	if player.hp / player.max_hp() * 100.0 <= ctx.num("auto_hp", 40.0) \
			and GeneralKit.enemies_near(player, AUTO_ENEMY_RANGE).size() >= 1:
		return true
	return GeneralKit.enemies_near(player, ctx.num("auto_radius", 3.0)).size() >= int(ctx.num("auto_enemies", 6.0))


func cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_alive():
		return false
	end(false)  # (a recast while still down: the old one grants nothing)
	_player = player
	_connect(player)
	_duration = maxf(0.0, ctx.num("duration", 2.0))
	_left = _duration
	_forced = maxi(0, roundi(ctx.num("forced_crits", 0.0)))
	_decoy_radius = maxf(0.0, ctx.num("decoy_radius", 0.0))
	var heal_total := player.max_hp() * ctx.num("heal_max_hp_pct", 0.0) * ctx.num("power", 1.0) / 100.0
	_heal_left = heal_total
	_heal_owed = 0.0
	_heal_timer = HEAL_TICK
	_heal_rate = heal_total / _duration if _duration > 0.0 else 0.0
	_taunt_left = 0.0
	player.stealth_left = maxf(player.stealth_left, _left)
	LivingPlayers.mark_dirty()  # enemies drop the player this tick
	if player.model != null:
		player.model.set_play_dead(_left > 0.0)
	if player.is_inside_tree():
		Vfx.death_puff(player.global_position + Vector3.UP * 0.4, DUST, 1.0)
		Vfx.floating_text(player.self_text_position(1.0), "Play Dead", TEXT_COLOR, Player.SELF_TEXT_SIZE, 1.0)
	_decoy()
	return true


func tick(_ctx: AbilityContext, delta: float) -> void:
	if _left <= 0.0:
		return
	var step := minf(delta, _left)
	if _heal_rate > 0.0 and _heal_left > 0.0:
		var amount := minf(_heal_rate * step, _heal_left)
		_heal_left -= amount
		_heal_owed += amount
		_heal_timer -= delta
		if _heal_timer <= 0.0:
			_heal_timer = HEAL_TICK
			_pay_heal()
	_taunt_left -= delta
	if _taunt_left <= 0.0:
		_decoy()
	_left -= delta
	if _left <= TIME_EPSILON:
		_rise()


## The Hunter gets up on its own: the guaranteed crits are banked.
func _rise() -> void:
	var player := _player
	var crits := _forced
	_pay_heal()
	end(true)
	if player != null and is_instance_valid(player) and player.is_alive():
		risen += 1
		if crits > 0:
			player.forced_crits = maxi(player.forced_crits, crits)


func begin_wave(_ctx: AbilityContext) -> void:
	end(false)


func end_wave(_ctx: AbilityContext) -> void:
	end(false)


## Ends the effect now without the crit bonus (the model stands again; with [param puff] a small puff
## marks it) and releases the decoy.
func end(puff: bool = true) -> void:
	var was_active := _left > 0.0
	_left = 0.0
	_forced = 0
	_heal_left = 0.0
	_heal_owed = 0.0
	_heal_rate = 0.0
	_release_taunts()
	if _player != null and is_instance_valid(_player):
		if _player.model != null:
			_player.model.set_play_dead(false)
		if puff and was_active and _player.is_inside_tree():
			Vfx.death_puff(_player.global_position + Vector3.UP * 0.3, DUST, 0.7)


## Pays out the healing earned so far.
func _pay_heal() -> void:
	if _heal_owed > 0.0 and _player != null and is_instance_valid(_player):
		_player.heal(_heal_owed)
	_heal_owed = 0.0


## Rank III: the companion draws the enemies near the Hunter to itself.
func _decoy() -> void:
	_taunt_left = TAUNT_REFRESH
	if _decoy_radius <= 0.0 or _player == null or not is_instance_valid(_player):
		return
	var pet := HunterKit.companion(_player)
	if pet == null or not pet.visible:
		return
	for e in GeneralKit.enemies_near(_player, _decoy_radius):
		e.apply_taunt(pet, TAUNT_REFRESH * 2.0)
		_taunted[e.get_instance_id()] = e


## Enemies still taunted to the companion by this effect are let go (another taunt stays).
func _release_taunts() -> void:
	if _taunted.is_empty():
		return
	var pet := HunterKit.companion(_player) if _player != null and is_instance_valid(_player) else null
	for id: int in _taunted:
		var v: Variant = _taunted[id]
		if pet != null and is_instance_valid(v):
			(v as Enemy).release_taunt(pet)
	_taunted.clear()


func _connect(player: Player) -> void:
	if not player.hp_changed.is_connected(_on_hp_changed):
		player.hp_changed.connect(_on_hp_changed)
	if not player.downed_changed.is_connected(_on_downed_changed):
		player.downed_changed.connect(_on_downed_changed)


## At 0 HP the player is about to go down – the effect ends (no crits) so the downed look takes over.
func _on_hp_changed(hp: float, _max_hp: float) -> void:
	if hp <= 0.0 and _left > 0.0:
		end(false)


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		end(false)
