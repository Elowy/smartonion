class_name RogueCheatDeath
extends AbilityEffect
## Cheat Death (GDD 6.4, Rogue Auto – passive): a hit that would bring the Rogue down leaves it
## at 1 HP instead, once per [code]cooldown[/code] (60) s. It then gets
## [code]invulnerable[/code] (1) s of invulnerability and – on the next physics tick, after
## the lethal hit settled – recovers [code]heal_max_hp_pct[/code] (15) % of its max HP x
## "power". The cooldown runs in the AbilityRunner, so the HUD shows it like any other; each
## save spends one charge (AbilityRunner.spend_charge), so item "charges" give extra saves.
## Rank III: +1 s invulnerability. Rank V: "Shadow Escape" ([code]stealth[/code] s of Vanish
## stealth + [code]forced_crits[/code] guaranteed crits) or "Death's Reprisal"
## ([code]burst_pct[/code] % of a weapon hit x power to every enemy within
## [code]burst_radius[/code] m, stunned for [code]burst_stun[/code] s).
##
## Never cast by the runner (can_cast is false): while slotted the effect keeps a guard in
## Player.death_guards (registered on its first tick and at wave start, removed at the wave end
## and when the ability is forgotten – the runner calls end_wave then); the guard asks the
## runner whether the ability is off cooldown and still slotted.

const TEXT_COLOR := Color(0.85, 0.8, 1.0)
const BURST_COLOR := Color(0.6, 0.4, 0.95)

var _player: Player
var _ability: AbilityData
var _guard := Callable()
## Work left for the next tick (the guard runs inside Player.take_damage).
var _pending_heal := 0.0
var _pending_burst := false
## Times it saved the Rogue (tests, debugging).
var saves := 0


func can_cast(_ctx: AbilityContext) -> bool:
	return false


func wants_auto_cast(_ctx: AbilityContext) -> bool:
	return false


func cast(_ctx: AbilityContext) -> bool:
	return false


func tick(ctx: AbilityContext, _delta: float) -> void:
	_bind(ctx)
	if _pending_heal > 0.0:
		var amount := _pending_heal
		_pending_heal = 0.0
		_player.heal(amount)
	if _pending_burst:
		_pending_burst = false
		_burst(ctx.params)


func begin_wave(ctx: AbilityContext) -> void:
	_pending_heal = 0.0
	_pending_burst = false
	_bind(ctx)


## Wave end and forget: the guard goes (the next wave start / tick puts it back while slotted).
func end_wave(_ctx: AbilityContext) -> void:
	_pending_heal = 0.0
	_pending_burst = false
	unregister()


## True while the guard sits in the player's death guards.
func is_registered() -> bool:
	return _player != null and is_instance_valid(_player) and not _guard.is_null() \
			and _guard in _player.death_guards


## True when the next lethal hit would be survived.
func is_ready() -> bool:
	return _usable() and _player.abilities.charges_available(_ability) > 0


func unregister() -> void:
	if _player != null and is_instance_valid(_player) and not _guard.is_null():
		_player.death_guards.erase(_guard)


func _bind(ctx: AbilityContext) -> void:
	if ctx.player == null:
		return
	if _player != ctx.player:
		unregister()
	_player = ctx.player
	_ability = ctx.ability
	if _guard.is_null():
		_guard = Callable(self, &"_on_lethal_hit")
	if not _guard in _player.death_guards:
		_player.death_guards.append(_guard)


func _usable() -> bool:
	return _player != null and is_instance_valid(_player) and _player.abilities != null \
			and _ability != null and _player.abilities.knows(_ability.id)


## Player.death_guards: a lethal hit is about to land. True = survive at 1 HP.
func _on_lethal_hit() -> bool:
	if not _usable():
		unregister()
		return false
	var runner := _player.abilities
	if _player.downed or runner.charges_available(_ability) <= 0:
		return false
	var params := runner.params_for(_ability)
	# Like a cast: one charge goes, the recharge starts unless it already runs.
	runner.spend_charge(_ability)
	runner.ability_cast.emit(runner.slot_of(_ability.id), _ability)
	saves += 1
	var power := float(params.get("power", 1.0))
	_player.invulnerable_left = maxf(_player.invulnerable_left, float(params.get("invulnerable", 1.0)))
	_pending_heal = _player.max_hp() * float(params.get("heal_max_hp_pct", 0.0)) / 100.0 * power
	var stealth := float(params.get("stealth", 0.0))
	if stealth > 0.0:
		RogueVanish.shroud(_player, stealth)
	var crits := roundi(float(params.get("forced_crits", 0.0)))
	if crits > 0:
		_player.forced_crits = maxi(_player.forced_crits, crits)
	_pending_burst = float(params.get("burst_pct", 0.0)) > 0.0
	if _player.is_inside_tree():
		RogueVfx.cheat_death(_player.global_position)
		Vfx.floating_text(_player.self_text_position(1.0) + Vector3.UP * 0.4, "Narrow Escape", TEXT_COLOR,
				Player.SELF_TEXT_SIZE * 1.15, 0.0)
	return true


## Death's Reprisal: weapon damage to everything around the Rogue and a short stun.
func _burst(params: Dictionary) -> void:
	if _player == null or not _player.is_inside_tree() or _player.procs == null:
		return
	var radius := float(params.get("burst_radius", 4.0)) * CombatMath.area_mult(_player.stats)
	var amount := RogueUtil.weapon_damage(_player) * float(params.get("burst_pct", 0.0)) / 100.0 \
			* float(params.get("power", 1.0))
	var stun := float(params.get("burst_stun", 0.0))
	for e in RogueUtil.enemies_around(_player.get_tree(), _player.global_position, radius):
		_player.procs.deal_raw(e, amount, CombatMath.SCHOOL_PHYSICAL, true, &"ability")
		if stun > 0.0 and is_instance_valid(e) and not e.is_dead():
			e.apply_stun(stun)
	Vfx.slash_arc(_player.global_position + Vector3.UP * 0.3, _player.facing, radius, 360.0, BURST_COLOR)
	Vfx.explosion(_player.global_position + Vector3.UP * 0.2, radius, BURST_COLOR)
