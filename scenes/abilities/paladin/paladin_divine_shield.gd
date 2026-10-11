class_name PaladinDivineShield
extends AbilityEffect
## Divine Shield (GDD 6.4, Paladin Active): [code]duration[/code] (3) x power seconds of full
## invulnerability (Player.invulnerable_left) inside a golden bubble.
##
## Params also: heal_max_hp (Rank III: heals that % of max HP x power at the cast),
## aura_damage / aura_spell_power_scale / aura_radius / aura_tick (spec "Radiant Bubble":
## the bubble burns enemies around the Paladin for weapon-based Holy damage every tick; power
## only lengthens the bubble – more ticks – and never raises a tick, so it counts once),
## share_range (spec "Hand of Protection": the most wounded living ally within that range gets
## the same bubble and invulnerability).
##
## The bubble look ends with the shield, when the Paladin goes down or leaves, and with the wave.
## Bots: below [constant AUTO_HP_RATIO] of max HP with an enemy within
## [constant AUTO_ENEMY_RANGE] m (with the Hand of Protection spec also for a wounded ally).

const AUTO_HP_RATIO := 0.35
const AUTO_ALLY_HP_RATIO := 0.3
const AUTO_ENEMY_RANGE := 4.0
const DEFAULT_AURA_RADIUS := 2.5
const SPARK_HEIGHT := 0.6

var _player: Player
var _left := 0.0
var _ally: Player
var _bubbles: Array[PaladinVfx] = []
var _aura_damage := 0.0
var _aura_radius := DEFAULT_AURA_RADIUS
var _aura_tick := 0.5
var _aura_timer := 0.0


## Seconds of invulnerability a cast grants (power included).
static func duration_of(ctx: AbilityContext) -> float:
	return maxf(0.0, ctx.num("duration", 3.0) * ctx.num("power", 1.0))


## The ally the Hand of Protection spec also shields (null without the spec / nobody near).
static func shared_ally(ctx: AbilityContext) -> Player:
	var reach := ctx.num("share_range")
	var p := ctx.player
	if reach <= 0.0 or p == null or not p.is_inside_tree():
		return null
	return PaladinKit.lowest_hero(p.get_tree(), p.global_position, reach, false, p)


func is_shielded() -> bool:
	return _left > 0.0


func can_cast(ctx: AbilityContext) -> bool:
	return ctx.player != null and ctx.player.is_alive()


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree() or is_shielded():
		return false
	var tree := p.get_tree()
	if PaladinKit.hp_ratio(p) < AUTO_HP_RATIO and p.invulnerable_left < 0.5 \
			and EnemyGrid.nearest(tree, p.global_position, AUTO_ENEMY_RANGE) != null:
		return true
	var ally := shared_ally(ctx)
	return ally != null and PaladinKit.hp_ratio(ally) < AUTO_ALLY_HP_RATIO and ally.invulnerable_left < 0.5 \
			and EnemyGrid.nearest(tree, ally.global_position, AUTO_ENEMY_RANGE) != null


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_alive():
		return false
	end()
	_player = p
	PaladinKit.connect_once(p.downed_changed, _on_downed_changed)
	PaladinKit.connect_once(p.tree_exiting, end)
	var duration := duration_of(ctx)
	_left = duration
	_shield(p, duration)
	var heal_pct := ctx.num("heal_max_hp")
	if heal_pct > 0.0:
		p.heal(p.max_hp() * heal_pct / 100.0 * ctx.num("power", 1.0))
	var ally := shared_ally(ctx)
	if ally != null:
		_ally = ally
		_shield(ally, duration)
		ProcVfx.beam(p.get_chest_position(), ally.get_chest_position(), PaladinKit.HOLY_COLOR)
	_aura_damage = 0.0
	if ctx.num("aura_damage") > 0.0:
		# Power is already in the duration (more ticks): each tick stays at aura_damage %.
		_aura_damage = PaladinKit.strike_damage(p, ctx.num("aura_damage"), ctx.num("aura_spell_power_scale", 0.25))
		_aura_radius = ctx.num("aura_radius", DEFAULT_AURA_RADIUS) * CombatMath.area_mult(p.stats)
		_aura_tick = maxf(0.1, ctx.num("aura_tick", 0.5))
		_aura_timer = 0.0
	Vfx.floating_text(p.get_chest_position() + Vector3.UP * 0.8, "Divine Shield", PaladinKit.HOLY_COLOR, 0.9)
	return true


func tick(_ctx: AbilityContext, delta: float) -> void:
	if _left <= 0.0:
		return
	_left -= delta
	if _left <= 0.0:
		end()
		return
	if _aura_damage > 0.0:
		_aura_timer -= delta
		if _aura_timer <= 0.0:
			_aura_timer += _aura_tick
			_burn()


## Ends the shield's looks and the Radiant burn (the invulnerability itself simply runs out).
func end() -> void:
	_left = 0.0
	_aura_damage = 0.0
	_ally = null
	for b in _bubbles:
		PaladinVfx.finish(b)
	_bubbles.clear()


func begin_wave(_ctx: AbilityContext) -> void:
	end()


func end_wave(_ctx: AbilityContext) -> void:
	end()


func _shield(hero: Player, duration: float) -> void:
	hero.invulnerable_left = maxf(hero.invulnerable_left, duration)
	var b := PaladinVfx.bubble(hero, duration)
	if b != null:
		_bubbles.append(b)


## "Radiant Bubble": Holy damage to every enemy around the Paladin.
func _burn() -> void:
	if _player == null or not is_instance_valid(_player) or not _player.is_inside_tree() or _player.procs == null:
		return
	var sparks := 0
	for e in PaladinKit.enemies_around(_player.get_tree(), _player.global_position, _aura_radius):
		if not is_instance_valid(e) or e.is_dead():
			continue
		var spot := e.global_position + Vector3.UP * SPARK_HEIGHT
		_player.procs.deal_raw(e, _aura_damage, PaladinKit.SCHOOL, true, &"ability")
		if sparks < 3:
			sparks += 1
			Vfx.hit_spark(spot, PaladinKit.HOLY_COLOR)


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		end()
