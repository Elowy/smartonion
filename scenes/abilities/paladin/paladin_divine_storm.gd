class_name PaladinDivineStorm
extends AbilityEffect
## Divine Storm (GDD 6.4, Paladin Auto): a whirling holy strike around the Paladin – every enemy
## within [code]radius[/code] m (Area Size scales it) takes [code]damage_pct[/code] % of the
## main-hand hit + [code]spell_power_scale[/code] x Spell Power as Holy damage – and a heal for
## the Paladin and every hurt ally within [code]heal_radius[/code] m: [code]heal[/code] +
## [code]heal_max_hp_pct[/code] % of the healed hero's max HP + [code]heal_spell_power_scale[/code]
## x Spell Power. Damage and heal x power.
##
## Params also: pulses / pulse_interval (spec "Divine Tempest": the storm strikes that many
## times; the heal comes with the first strike), heal_per_enemy / heal_enemy_cap (spec
## "Merciful Storm": +% max HP heal per enemy struck by the first strike, up to the cap).

## Bots / auto-cast: an enemy inside the storm.
const AUTO_MIN_ENEMIES := 1
const DEFAULT_RADIUS := 3.0
const SPARK_HEIGHT := 0.6
const MAX_SPARKS := 4

var _player: Player
var _pulses_left := 0
var _pulse_timer := 0.0
var _interval := 0.35
var _radius := DEFAULT_RADIUS
var _damage := 0.0


## Reach of the strike in metres (Area Size included).
static func reach_of(ctx: AbilityContext) -> float:
	var mult := CombatMath.area_mult(ctx.player.stats) if ctx.player != null else 1.0
	return ctx.num("radius", DEFAULT_RADIUS) * mult


static func strike_damage(ctx: AbilityContext) -> float:
	return PaladinKit.strike_damage(ctx.player, ctx.num("damage_pct", 100.0), ctx.num("spell_power_scale", 0.5),
			ctx.num("power", 1.0))


## Heal on [param who] when the first strike hit [param enemies_hit] enemies.
static func heal_for(ctx: AbilityContext, who: Player, enemies_hit: int) -> float:
	var bonus := ctx.num("heal_per_enemy") * float(mini(enemies_hit, roundi(ctx.num("heal_enemy_cap", 8.0))))
	return PaladinKit.heal_amount(ctx.player, who, ctx.num("heal", 1.0), ctx.num("heal_max_hp_pct", 5.0) + bonus,
			ctx.num("heal_spell_power_scale", 0.5), ctx.num("power", 1.0))


## Heroes the storm heals: the Paladin and the hurt living allies within heal_radius.
static func heal_targets(ctx: AbilityContext) -> Array[Player]:
	var out: Array[Player] = []
	var p := ctx.player
	if p == null or not p.is_inside_tree():
		return out
	for hero in PaladinKit.living_heroes_around(p.get_tree(), p.global_position, ctx.num("heal_radius", 6.0)):
		if PaladinKit.is_hurt(hero):
			out.append(hero)
	return out


func is_storming() -> bool:
	return _pulses_left > 0


func can_cast(_ctx: AbilityContext) -> bool:
	return not is_storming()


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree():
		return false
	return PaladinKit.enemies_around(p.get_tree(), p.global_position, reach_of(ctx)).size() >= AUTO_MIN_ENEMIES


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree() or is_storming():
		return false
	_player = p
	PaladinKit.connect_once(p.downed_changed, _on_downed_changed)
	_radius = reach_of(ctx)
	_damage = strike_damage(ctx)
	_interval = maxf(0.05, ctx.num("pulse_interval", 0.35))
	_pulses_left = maxi(1, roundi(ctx.num("pulses", 1.0)))
	_pulse_timer = 0.0
	var hit := _pulse()
	var paladin_chest := p.get_chest_position()
	for hero in heal_targets(ctx):
		hero.heal(heal_for(ctx, hero, hit), p.slot_index())
		Vfx.hit_spark(hero.get_chest_position(), PaladinKit.HOLY_COLOR)
		if hero != p:
			ProcVfx.beam(paladin_chest, hero.get_chest_position(), PaladinKit.HOLY_COLOR)
	return true


func tick(_ctx: AbilityContext, delta: float) -> void:
	if _pulses_left <= 0:
		return
	_pulse_timer += delta
	while _pulses_left > 0 and _pulse_timer >= _interval - 0.0001:
		_pulse_timer -= _interval
		_pulse()


## One strike on everything in reach; returns the number of enemies struck.
func _pulse() -> int:
	_pulses_left -= 1
	if _player == null or not is_instance_valid(_player) or not _player.is_inside_tree() or _player.procs == null:
		_pulses_left = 0
		return 0
	var center := _player.global_position
	PaladinVfx.storm(center, _radius)
	var sparks := 0
	var hit := 0
	for e in PaladinKit.enemies_around(_player.get_tree(), center, _radius):
		if not is_instance_valid(e) or e.is_dead():
			continue
		var spot := e.global_position + Vector3.UP * SPARK_HEIGHT
		_player.procs.deal_raw(e, _damage, PaladinKit.SCHOOL, true, &"ability")
		hit += 1
		if sparks < MAX_SPARKS:
			sparks += 1
			Vfx.hit_spark(spot, PaladinKit.HOLY_COLOR)
	return hit


func stop() -> void:
	_pulses_left = 0
	_pulse_timer = 0.0


func begin_wave(_ctx: AbilityContext) -> void:
	stop()


func end_wave(_ctx: AbilityContext) -> void:
	stop()


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		stop()
