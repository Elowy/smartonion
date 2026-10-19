class_name RogueFanOfKnives
extends AbilityEffect
## Fan of Knives (GDD 3.4, Rogue RT): throws [code]knives[/code] (10) knives in all directions,
## each a weapon-based hit ([code]damage_pct[/code] (110) % of the main-hand hit x "power",
## able to crit) that passes through [code]pierce[/code] (1) enemies. Every Combo Point held is
## spent and adds [code]combo_bonus_pct[/code] % (20) damage.
## Item mod (Blade of the Thousand Cuts): [code]knives_add[/code] = +4 knives.
## Ranks (M4): Rank III +2 knives; Rank V "Deadly Fan" ([code]poison_hits[/code]: every knife
## hit poisons, not only the crits) or "Returning Blades" ([code]returns[/code] 1: the knives
## fly back from the end of their range, hitting again on the way).
##
## The knives are [RogueBlade]s: their hits count as weapon hits (Combo Points and Deadly
## Poison on a crit, leech, Executioner / Slayer, Mastery multipliers) and roll on-hit procs
## once per cast. Knife crits roll at the throw – Vanish's guaranteed crit is kept for the
## weapons; a talent script that forces crits (Shadow Dance: PlayerBonuses.crit_forced(null))
## is asked before the roll (no RunState.rng draw when it says yes).
##
## M5 talent params (neutral defaults in the data – talents_rogue.md 4.1):
##   [code]envenom_pct[/code] (0)  – Envenom: every knife consumes the Deadly Poison of the
##                                   enemy it hits and deals that % of the poison's undealt
##                                   damage at once as Nature (once per enemy per cast;
##                                   [member RogueBlade.envenom_pct]).
##   [code]cdr_per_combo[/code] (0) – Restless Blades: after the throw, every Combo Point spent
##                                   shortens the running recharges of the other slotted Rogue
##                                   abilities by this many seconds
##                                   ([method RogueUtil.reduce_other_cooldowns]).
##   [code]cold_blood_every[/code] (0), [code]cold_blood_crit_damage[/code] (0, %),
##   [code]cold_blood_slow[/code] (0, %), [code]cold_blood_slow_duration[/code] (0, s) – Cold
##                                   Blood: every Nth fan of the wave ([member fans] counts
##                                   them, free fans too) is "cold": every knife crits (no
##                                   roll) with +crit_damage % on the crit multiplier, and
##                                   slows the living enemies it hits. A crimson ground ring
##                                   under the hero says the next fan is cold.
## Free fans: [method throw_free] (Unseen Blades, Vanish) casts the effect directly – no
## Energy, no cooldown, no ability_cast signal (no on-cast procs) – with the "unseen" flag
## (shadow-purple knives); Combo Points are spent as usual.

const KNIFE_COLOR := Color(0.82, 0.88, 1.0)
const KNIFE_KNOCKBACK := 0.6
## Bots fan when at least this many enemies are within AUTO_RANGE metres ...
const AUTO_MIN_ENEMIES := 3
const AUTO_RANGE := 5.0
## ... or when the Combo Points are full and an enemy is within the knives' reach.
const AUTO_FULL_COMBO := 5
const BURST_RADIUS := 1.7
## Cold Blood look: knives / slash arc / text, and the "next fan is cold" ground ring.
const COLD_KNIFE_COLOR := Color(0.95, 0.3, 0.35)
const COLD_RING_COLOR := Color(0.9, 0.2, 0.25)
const COLD_RING_ALPHA := 0.35
const COLD_RING_RADIUS := 1.1
const COLD_TEXT := "Steel Nerve!"
## Restless Blades: a small gold spark on the hero when a recharge was shortened this much (s).
const RESTLESS_SPARK_MIN := 0.6
const RESTLESS_SPARK_COLOR := Color(1.0, 0.82, 0.3)

## Fans thrown this wave (Cold Blood's counter; reset by begin_wave).
var fans := 0
## True when the last fan was a Cold Blood fan (tests).
var last_cold := false
## Cold Blood's "next fan is cold" ring (a child of the hero; null when not shown).
var _ring: MeshInstance3D


## The Fan of Knives effect of [param player] (null when it has none).
static func of(player: Player) -> RogueFanOfKnives:
	if player == null or player.abilities == null:
		return null
	for a in player.abilities.slots:
		var e := player.abilities.effect_for(a) as RogueFanOfKnives
		if e != null:
			return e
	return null


## Unseen Blades: throws a fan for free (no Energy, no cooldown, no ability_cast signal – so
## no on-cast procs or TalentEffect.on_cast) with the hero's current Fan of Knives params and
## the "unseen" look. Combo Points are spent and multiply it; Cold Blood counts it, Restless
## Blades applies. False when the hero is down / out of the tree or has no Fan of Knives.
static func throw_free(player: Player) -> bool:
	if player == null or not is_instance_valid(player) or not player.is_alive() \
			or not player.is_inside_tree() or player.abilities == null:
		return false
	var index := player.abilities.slot_of(&"fan_of_knives")
	if index < 0:
		return false
	var fan := player.abilities.slots[index]
	var effect := player.abilities.effect_for(fan) as RogueFanOfKnives
	if effect == null:
		return false
	var ctx := player.abilities.build_context(fan)
	var params := ctx.params.duplicate()
	params["unseen"] = true
	ctx.params = params
	return effect.cast(ctx)


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_inside_tree():
		return false
	if RogueUtil.enemies_within(player, AUTO_RANGE) >= AUTO_MIN_ENEMIES:
		return true
	return RogueUtil.combo_points(player) >= AUTO_FULL_COMBO \
			and RogueUtil.enemies_within(player, ctx.num("range", 7.0)) >= 1


func cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	var weapon := _weapon(player)
	if weapon == null or not player.is_inside_tree():
		return false
	var parent := WeaponRunner.effects_parent(player)
	if parent == null:
		return false
	var points := RogueUtil.combo_points(player)
	var combo := player.abilities.get_resource(RogueUtil.COMBO_ID)
	if combo != null:
		combo.set_value(0.0)
	var knives := maxi(1, roundi(ctx.num("knives", 10.0)))
	var damage := knife_damage(player, weapon, ctx.num("damage_pct", 110.0), points,
			ctx.num("combo_bonus_pct", 20.0)) * ctx.num("power", 1.0)
	var every := roundi(ctx.num("cold_blood_every", 0.0))
	var cold := every > 0 and (fans + 1) % every == 0
	var crit_mult := CombatMath.crit_multiplier(weapon, player.stats)
	if cold:
		crit_mult += ctx.num("cold_blood_crit_damage", 0.0) / 100.0
	var slow_pct := ctx.num("cold_blood_slow", 0.0) if cold else 0.0
	var slow_duration := ctx.num("cold_blood_slow_duration", 0.0) if cold else 0.0
	var envenom_pct := maxf(0.0, ctx.num("envenom_pct", 0.0))
	var envenomed: Dictionary[int, bool] = {}
	var boss_hits: Dictionary[int, int] = {}
	var speed := ctx.num("speed", 16.0)
	var reach := ctx.num("range", 7.0)
	var pierce := maxi(0, roundi(ctx.num("pierce", 0.0)))
	var returns := maxi(0, roundi(ctx.num("returns", 0.0)))
	var poison_hits := ctx.flag("poison_hits")
	var unseen := ctx.flag("unseen")
	var color := COLD_KNIFE_COLOR if cold else (RogueVfx.SHADOW_COLOR if unseen else KNIFE_COLOR)
	var facing := Vector3(ctx.direction.x, 0.0, ctx.direction.z)
	facing = facing.normalized() if facing.length_squared() > 0.0001 else Vector3.FORWARD
	var origin := player.global_position
	var gate := WeaponRunner.ProcGate.new()
	for i in knives:
		var dir := facing.rotated(Vector3.UP, TAU * float(i) / float(knives))
		var crit := cold or RogueUtil.bonus_crit(player, null) or CombatMath.roll_crit(player.stats, RunState.rng)
		var knife := RogueBlade.throw(player, weapon, damage * (crit_mult if crit else 1.0), crit, dir,
				speed, reach, pierce, color)
		knife.knockback = KNIFE_KNOCKBACK
		knife.proc_gate = gate
		knife.boss_hits = boss_hits
		knife.returns = returns
		knife.poison_hits = poison_hits
		if envenom_pct > 0.0:
			knife.envenom_pct = envenom_pct
			knife.envenomed = envenomed
		if slow_pct > 0.0 and slow_duration > 0.0:
			knife.slow_pct = slow_pct
			knife.slow_duration = slow_duration
		parent.add_child(knife)
		knife.global_position = origin + Vector3.UP * Player.CHEST_HEIGHT + dir * (Player.RADIUS + 0.15)
	var arc_color := KNIFE_COLOR
	if cold:
		arc_color = COLD_KNIFE_COLOR
	elif unseen:
		arc_color = RogueVfx.SHADOW_COLOR
	elif poison_hits:
		arc_color = RogueVfx.POISON_COLOR
	Vfx.slash_arc(origin + Vector3.UP * 0.3, facing, BURST_RADIUS, 360.0, arc_color)
	if cold:
		Vfx.floating_text(player.self_text_position(1.0), COLD_TEXT, COLD_KNIFE_COLOR, Player.SELF_TEXT_SIZE, 1.0)
	last_cold = cold
	fans += 1
	_update_ring(player, every)
	var cdr := ctx.num("cdr_per_combo", 0.0)
	if cdr > 0.0 and points > 0:
		var seconds := float(points) * cdr
		if RogueUtil.reduce_other_cooldowns(player, ctx.ability, seconds) > 0 and seconds >= RESTLESS_SPARK_MIN:
			Vfx.hit_spark(player.get_chest_position(), RESTLESS_SPARK_COLOR)
	return true


## A removed Cold Blood (talent reset) takes its ring along at once.
func tick(ctx: AbilityContext, _delta: float) -> void:
	if _ring != null and roundi(ctx.num("cold_blood_every", 0.0)) <= 0:
		_free_ring()


## A new wave counts its fans from zero (the ring shows again before the wave's 3rd fan).
func begin_wave(_ctx: AbilityContext) -> void:
	fans = 0
	last_cold = false
	_free_ring()


func end_wave(_ctx: AbilityContext) -> void:
	_free_ring()


## True while the "next fan is cold" ring is shown (tests).
func has_cold_ring() -> bool:
	return _ring != null and is_instance_valid(_ring)


## Damage of one (non-crit) knife: [param pct] % of the weapon hit, +[param bonus_pct] % per
## Combo Point spent (before "power").
static func knife_damage(player: Player, weapon: WeaponData, pct: float, points: int, bonus_pct: float) -> float:
	var hit := CombatMath.weapon_hit_damage(weapon, player.stats)
	return hit * pct / 100.0 * (1.0 + float(points) * bonus_pct / 100.0)


## The weapon the knives are based on: the main hand, else the off hand.
static func _weapon(player: Player) -> WeaponData:
	return RogueUtil.weapon(player)


## Cold Blood: shows the crimson ring when the next fan will be cold, else removes it.
func _update_ring(player: Player, every: int) -> void:
	if every <= 0 or (fans + 1) % every != 0:
		_free_ring()
		return
	if has_cold_ring():
		return
	_ring = RogueVfx.ring(player, COLD_RING_COLOR, COLD_RING_RADIUS, COLD_RING_ALPHA)
	if _ring != null:
		_ring.name = "ColdBloodRing"
		_ring.visible = player.is_alive()
		if not player.downed_changed.is_connected(_on_downed_changed):
			player.downed_changed.connect(_on_downed_changed)


func _free_ring() -> void:
	if _ring != null and is_instance_valid(_ring):
		_ring.queue_free()
	_ring = null


## The ring hides while the hero is down (the counter is kept – no fans while downed).
func _on_downed_changed(is_downed: bool) -> void:
	if has_cold_ring():
		_ring.visible = not is_downed
