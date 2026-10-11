class_name Player
extends CharacterBody3D
## A local co-op hero (GDD 1, 2, 3). Group &"players". Collision layer 2 ("players"),
## mask 1 ("world") – enemies do NOT physically block players; they deal contact damage.
## Moves on the XZ plane: input Vector2(x, y) -> world Vector3(x, 0, y).
##
## Stats come from a StatBlock with the sources &"base" (Stats.BASE_MASTERY), &"class"
## (ClassData.base_stats), &"weapon:main", &"weapon:off" (WeaponData.bonus_stats), the
## equipped items, &"level" (LEVEL_STAMINA per team level gained) and &"level_cards" (stat
## level-up cards). Every equipped weapon that
## attacks gets its own WeaponRunner child. At 0 HP the player is downed (a ghost that does
## not attack); a living teammate standing within REVIVE_RADIUS for REVIVE_TIME seconds
## revives them (every additional reviver adds REVIVE_SPEED_PER_EXTRA_REVIVER), and so does
## the arena's [SpiritHealer] (its 10 s pulse revives ghosts in its circle at full HP – see
## healer_channel – and gives RES_SICKNESS_TIME of Resurrection Sickness).
## Movement respects the arena walls and, on the shared screen, the camera's walk rect
## (CameraRig.get_walk_rect, GDD 13): the screen edge is an invisible wall.
## M2: the equipped items' enchants / unique effects run in the child [ProcSystem] "Procs"
## (refreshed on equipment.changed); weapon hits report to on_hit_dealt(), kills to
## notify_kill() (Life on Kill, on-kill procs); take_damage() handles Parry (riposte), Block
## Value, proc shields, cheat-death, Thorns and the when-struck / low-HP procs.

signal hp_changed(hp: float, max_hp: float)
signal downed_changed(is_downed: bool)
## Emitted after damage actually landed (not on dodge, i-frames or while downed).
signal damage_taken(amount: float, source: Node3D)
## Emitted from on_hit_dealt() after each successful weapon hit of this player.
signal hit_dealt(damage: float, target: Node3D)
## Emitted from notify_kill() when this player landed the killing blow (weapon, proc, thorns).
signal enemy_killed(enemy: Node3D)

const RADIUS := 0.45
## Height (metres) where projectiles / damage numbers originate.
const CHEST_HEIGHT := 0.7
const REVIVE_RADIUS := 1.8
## Seconds a single living teammate needs to stand next to a ghost to revive it (GDD 1).
const REVIVE_TIME := 5.0
## Every additional living reviver inside REVIVE_RADIUS adds this much revive speed
## (GDD 1: 1 reviver = 1x, 2 = 1.5x, 3 = 2x).
const REVIVE_SPEED_PER_EXTRA_REVIVER := 0.5
const INVULNERABLE_AFTER_HIT := 0.35

## Collision capsule height (the onion is ~1.3 m tall).
const BODY_HEIGHT := 1.2
const COLLISION_LAYER_PLAYERS := 1 << 1
const COLLISION_MASK_WORLD := 1
## m/s^2 while steering / when the stick is released.
const ACCELERATION := 40.0
const DECELERATION := 60.0
const MOVE_DEADZONE := 0.05
## Gap (m) kept between the body and the arena's outer walls (see _clamp_motion_to_arena).
const WALL_GAP := 0.02
## Downed ghosts move at full speed (GDD 1), so the walk to the Spirit Healer is quick.
const GHOST_SPEED_MULT := 1.0
## Resurrection Sickness after a Spirit Healer revive (seconds; GDD 1).
const RES_SICKNESS_TIME := 15.0
const RES_SICKNESS_TEXT_COLOR := Color(0.72, 0.68, 0.95)
## HP fraction after a teammate revive / after a wave starts while downed.
const REVIVE_HP_RATIO := 0.3
const WAVE_START_REVIVE_HP_RATIO := 0.5
## Revive progress (seconds) lost per second while nobody stands next to the ghost.
const REVIVE_DECAY_PER_SECOND := 0.5
const INVULNERABLE_AFTER_REVIVE := 1.0
const BLOCK_DAMAGE_MULT := 0.5
## How long the model keeps looking at its last attack target while standing still.
const ATTACK_LOOK_TIME := 0.4
const HIT_SHAKE := 0.15

const DAMAGE_TEXT_COLOR := Color(1.0, 0.27, 0.22)
const HEAL_TEXT_COLOR := Color(0.35, 1.0, 0.4)
const DODGE_TEXT_COLOR := Color(0.7, 0.88, 1.0)
const BLOCK_TEXT_COLOR := Color(0.88, 0.88, 0.95)
const PARRY_TEXT_COLOR := Color(0.95, 0.9, 0.7)
## Damage-taken / heal numbers start beside the head (alternating sides) instead of on the
## body, so they do not cover the hero or the "P1" marker above it.
const SELF_TEXT_HEIGHT := 1.45
const SELF_TEXT_SIDE := 0.6
const SELF_TEXT_SIZE := 0.85

## Soft player-vs-player separation (no physics collision between heroes): bodies closer than
## SEPARATION_DISTANCE drift apart at up to SEPARATION_SPEED m/s, so heroes never fully
## overlap but can still walk through each other.
const SEPARATION_DISTANCE := 1.15
const SEPARATION_SPEED := 3.0

## Every team level gives every hero +1 Stamina (= +1 Max HP, like Brotato) through the
## StatBlock source LEVEL_SOURCE; the real level-up reward is the card picked after the wave
## (GDD 6.1, CARD_SOURCE).
const LEVEL_SOURCE := &"level"
const LEVEL_STAMINA := 1.0
## Stat level-up cards picked so far (summed).
const CARD_SOURCE := &"level_cards"

var slot: PlayerSlot
var stats := StatBlock.new()
var hp := 10.0
var downed := false
var model: OnionModel
## Last non-zero movement direction (XZ, normalised); weapons fall back to it.
var facing := Vector3.FORWARD

## The class this player was built from (slot.class_data or the default class).
var class_data: ClassData
var main_hand: WeaponData
var off_hand: WeaponData
## One runner per equipped weapon that attacks (main hand first).
var weapons: Array[WeaponRunner] = []
## Equipped items + backpack (GDD 5). Changes re-apply stat sources and weapons.
var equipment: Equipment
## Enchantment / unique-item procs of the equipped items (child node "Procs", GDD 5.7).
var procs: ProcSystem
## Class abilities, resources and Mastery (child node "Abilities", GDD 3).
var abilities: AbilityRunner
## The next N weapon hits are guaranteed critical strikes (Vanish, talents ...).
var forced_crits := 0
## Seconds of revive progress while downed (0 .. REVIVE_TIME).
var revive_progress := 0.0
## Living teammates currently inside REVIVE_RADIUS while downed (0 when alive).
var reviver_count := 0
## Set every tick by the [SpiritHealer] while this ghost waits in its circle: progress
## towards the next pulse (0..1, 0 = not waiting) and the seconds until it (-1 = none). The
## cast bar shows whichever revive – teammates' or the healer's – is closer to completion.
var healer_channel := 0.0
var healer_seconds_left := -1.0
## Resurrection Sickness: seconds the Spirit Healer cannot revive this player again (set
## after each healer revive; teammates and Word of Glory still can). Cleared at wave start.
var res_sickness_left := 0.0
## Remaining invulnerability (i-frames) in seconds.
var invulnerable_left := 0.0
## Remaining stealth (Vanish) in seconds: enemies neither target, touch nor shoot this player.
var stealth_left := 0.0
## Named incoming-damage multipliers (Shield Wall 0.5 ...), applied after armour; cleared at
## wave start.
var damage_taken_mults: Dictionary[StringName, float] = {}
## Callables returning true to survive a lethal hit at 1 HP (Cheat Death, Last Stand ...);
## tried before the item cheat-death procs, which are limited (usually once per wave).
var death_guards: Array[Callable] = []

var _regen_accum := 0.0
## Teammates whose model currently channels a revive beam to this player.
var _channelers: Array[Player] = []
var _attack_look_dir := Vector3.FORWARD
var _attack_look_left := 0.0
## Side (+1 / -1) of the next damage-taken number.
var _text_side := 1.0
## XP Gain fraction carried to this hero's next pickup (see xp_with_gain).
var _xp_carry := 0.0


## Creates and configures a player for [param p_slot]. Not yet in the tree.
static func create(p_slot: PlayerSlot) -> Player:
	var p := Player.new()
	p.slot = p_slot
	p.name = "Player%d" % (p_slot.index + 1) if p_slot != null else "Player"
	p.collision_layer = COLLISION_LAYER_PLAYERS
	p.collision_mask = COLLISION_MASK_WORLD
	p.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	p.add_to_group(&"players")

	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = BODY_HEIGHT
	shape.shape = capsule
	shape.position = Vector3(0.0, BODY_HEIGHT * 0.5, 0.0)
	p.add_child(shape)

	p.class_data = p_slot.class_data if p_slot != null and p_slot.class_data != null else Db.get_default_class()
	p.model = OnionModel.new()
	p.model.name = "Model"
	p.add_child(p.model)
	if p.class_data != null:
		p.model.setup(p.class_data, p_slot.color if p_slot != null else Color.WHITE)
		p.stats.set_source(&"class", p.class_data.base_stats)
	p.stats.set_source(&"base", {Stats.MASTERY: Stats.BASE_MASTERY})
	p.procs = ProcSystem.create(p)
	p.abilities = AbilityRunner.create(p)
	p.add_child(p.abilities)
	p.add_child(p.procs)
	p.equipment = Equipment.new(p.class_data)
	p.equipment.equip_starting_weapons()
	p.apply_equipment()
	p.equipment.changed.connect(p.apply_equipment)
	# "P1" nameplate marker above the head (also marks whose ghost it is).
	p.model.set_tag(p_slot.label() if p_slot != null else "")
	# TEMPORARY (until the M4 level-up cards): the team level's flat bonus, also for heroes
	# created mid-run.
	p._apply_level_bonus(RunState.level)
	p.hp = p.max_hp()
	p.stats.changed.connect(p._on_stats_changed)
	RunState.leveled_up.connect(p._on_team_leveled_up)

	if p_slot != null:
		p_slot.player = p
		var bot := p_slot.input as BotInput
		if bot != null:
			bot.body = p
	return p


func max_hp() -> float:
	return stats.max_hp()


func is_alive() -> bool:
	return not downed


## Hidden from enemies (Vanish): still collects pickups and can be healed / revived.
func is_stealthed() -> bool:
	return stealth_left > 0.0


## A lethal hit is about to land: [member death_guards] first (ability guards are free or
## recharge), then the item cheat-death procs (limited, usually once per wave), so a guard
## that would have saved the hero anyway never uses one up.
func _prevent_death() -> bool:
	for guard in death_guards:
		if guard.is_valid() and guard.call():
			return true
	return procs != null and procs.try_cheat_death()


## Alive and standing next to a downed teammate (reviving it) – bots must not dash away.
func is_reviving() -> bool:
	if downed or not is_inside_tree():
		return false
	var here := global_position
	for node in get_tree().get_nodes_in_group(&"players"):
		var other := node as Player
		if other == null or other == self or not other.downed or not other.is_inside_tree():
			continue
		var d := other.global_position - here
		if Vector2(d.x, d.z).length() <= REVIVE_RADIUS:
			return true
	return false


## Wave cleared (before the intermission): abilities / Mastery drop auras and buffs.
func end_wave() -> void:
	if abilities != null:
		abilities.end_wave()


## Wave start: living players heal to full; downed players come back at 50% HP (GDD 1).
func begin_wave() -> void:
	velocity = Vector3.ZERO
	_regen_accum = 0.0
	_attack_look_left = 0.0
	revive_progress = 0.0
	if downed:
		revive(WAVE_START_REVIVE_HP_RATIO)
	else:
		hp = max_hp()
		_hp_updated()
	invulnerable_left = 0.0
	stealth_left = 0.0
	res_sickness_left = 0.0
	forced_crits = 0
	damage_mults.clear()
	damage_taken_mults.clear()
	for runner in weapons:
		runner.reset()
	if procs != null:
		procs.begin_wave()
	if abilities != null:
		abilities.begin_wave()


## Called by enemies / enemy projectiles. Rolls dodge, parry (melee: negates the hit and
## ripostes) and block (Block Value absorbs more), applies armour etc., then a proc shield,
## a cheat-death effect, Thorns (melee) and the when-struck / low-HP procs.
## [param kind] is one of CombatMath.KIND_*.
func take_damage(raw: float, kind: StringName = CombatMath.KIND_MELEE, source: Node3D = null) -> void:
	if downed or invulnerable_left > 0.0 or raw <= 0.0:
		return
	var rng := RunState.rng
	_text_side = -_text_side
	var text_pos := self_text_position(_text_side)
	if stats.get_stat(Stats.DODGE) > 0.0 and CombatMath.roll_dodge(stats, rng):
		Vfx.floating_text(text_pos, "Dodge", DODGE_TEXT_COLOR, SELF_TEXT_SIZE, _text_side)
		return
	var valid_source: Node3D = source if source != null and is_instance_valid(source) else null
	var attacker: Enemy = valid_source as Enemy
	if kind == CombatMath.KIND_MELEE and stats.get_raw(Stats.PARRY) > 0.0 \
			and CombatMath.roll_parry(stats, rng):
		Vfx.floating_text(text_pos, "Parry", PARRY_TEXT_COLOR, SELF_TEXT_SIZE, _text_side)
		_riposte(attacker)
		return
	var amount := raw
	var block := block_chance()
	if block > 0.0 and CombatMath.roll_block(block, rng):
		amount *= 1.0 - CombatMath.block_absorb(stats.get_raw(Stats.BLOCK_VALUE))
		Vfx.floating_text(self_text_position(-_text_side), "Block", BLOCK_TEXT_COLOR, SELF_TEXT_SIZE, -_text_side)
		if amount <= 0.0001:
			invulnerable_left = INVULNERABLE_AFTER_HIT
			_thorns(attacker, kind)
			return
	var dmg := CombatMath.incoming_damage(amount, stats, kind)
	for m: float in damage_taken_mults.values():
		dmg *= maxf(0.0, m)
	if procs != null:
		dmg = procs.absorb(dmg)
		if dmg <= 0.0:
			invulnerable_left = INVULNERABLE_AFTER_HIT
			_thorns(attacker, kind)
			procs.on_struck(valid_source, 0.0)
			return
	if dmg >= hp and _prevent_death():
		dmg = maxf(0.0, hp - minf(hp, 1.0))  # survive at (up to) 1 HP
	hp = maxf(0.0, hp - dmg)
	invulnerable_left = maxf(invulnerable_left, INVULNERABLE_AFTER_HIT)
	if dmg > 0.0:
		Vfx.floating_text(text_pos, _format_amount(dmg), DAMAGE_TEXT_COLOR, SELF_TEXT_SIZE, _text_side)
	if model != null:
		model.flash_hit()
	_shake_camera(HIT_SHAKE)
	_hp_updated()
	damage_taken.emit(dmg, source)
	if abilities != null:
		abilities.on_damage_taken(dmg)
	if hp <= 0.0:
		_go_down()
	_thorns(attacker, kind)
	if not downed and procs != null:
		procs.on_struck(valid_source, dmg)


func heal(amount: float) -> void:
	if downed or amount <= 0.0:
		return
	var before := hp
	hp = minf(max_hp(), hp + amount)
	var gained := hp - before
	if gained <= 0.0:
		return
	_text_side = -_text_side
	Vfx.floating_text(self_text_position(_text_side), "+" + _format_amount(gained), HEAL_TEXT_COLOR, SELF_TEXT_SIZE, _text_side)
	_hp_updated()


## Called by this player's weapons after each successful hit (leech, on-hit procs). Proc
## damage never calls it (no proc chains). [param weapon] (its cooldown drives the PPM
## chance), [param is_crit], and [param is_extra] (a hit of an extra attack – it cannot
## trigger further extra attacks) are passed on to the procs. On-hit procs roll once per
## attack: the further hits of a melee arc / projectile fan / pierce / explosion pass
## [param roll_procs] = false (leech still rolls per hit).
func on_hit_dealt(damage: float, target: Node3D, weapon: WeaponData = null, is_crit: bool = false,
		is_extra: bool = false, roll_procs: bool = true) -> void:
	if downed:
		return
	hit_dealt.emit(damage, target)
	if stats.get_stat(Stats.LEECH) > 0.0 and CombatMath.roll_leech(stats, RunState.rng):
		heal(1.0)
	if roll_procs and procs != null and target != null and is_instance_valid(target):
		procs.on_hit(target, damage, weapon, is_crit, is_extra)
	if abilities != null:
		abilities.on_weapon_hit(target, damage, is_crit)


## Called by an Enemy this player killed (any damage of this player: weapon, proc, Thorns).
## Life on Kill (% chance to heal 1) and on-kill procs; a downed hero only gets the credit.
func notify_kill(enemy: Node3D) -> void:
	enemy_killed.emit(enemy)
	if abilities != null and not downed:
		abilities.on_kill(enemy)
	if downed:
		return
	if stats.get_raw(Stats.LIFE_ON_KILL) > 0.0 and CombatMath.roll_life_on_kill(stats, RunState.rng):
		heal(1.0)
	if procs != null:
		procs.on_kill(enemy)


# --- Extra public helpers ------------------------------------------------------

## Re-applies [member equipment]: one stat source per equipped position (Items.source_for),
## the equipped weapons (their bonus stats) and then Armor Specialization (+10% of the primary
## stat with every other source – weapons included – in place, GDD 5.3).
func apply_equipment() -> void:
	if equipment == null:
		return
	var sources := equipment.stat_sources()
	for s in Items.EquipSlot.values():
		var source := Items.source_for(s)
		if sources.has(source):
			stats.set_source(source, sources[source])
		else:
			stats.remove_source(source)
	var main := equipment.main_weapon()
	var off := equipment.off_weapon()
	if main != main_hand or off != off_hand:
		equip_weapons(main, off)
	stats.remove_source(&"armor_spec")
	if class_data != null and equipment.armor_spec_active():
		var primary := stats.get_raw(class_data.primary_stat)
		stats.set_source(&"armor_spec", {class_data.primary_stat: primary * Equipment.ARMOR_SPEC_BONUS})
	if procs != null:
		procs.refresh()
	if abilities != null:
		abilities.invalidate_params()  # item ability mods


## The WeaponRunner of [param weapon] (the first runner when [param weapon] is null or not
## equipped; null without attacking weapons).
func runner_for(weapon: WeaponData) -> WeaponRunner:
	if weapon != null:
		for runner in weapons:
			if runner.weapon == weapon:
				return runner
	return weapons[0] if not weapons.is_empty() else null


## XP Gain (GDD 2.4.1): the whole XP this hero adds for picking up [param amount] XP; the
## fraction is kept for this hero's next pickup (so +10% on single XP orbs adds up).
func xp_with_gain(amount: int) -> int:
	var pct := stats.get_raw(Stats.XP_GAIN)
	if pct == 0.0 and _xp_carry == 0.0:
		return amount
	var exact := CombatMath.xp_with_gain(amount, pct) + _xp_carry
	var whole := floori(exact + 0.000001)
	_xp_carry = maxf(0.0, exact - whole)
	return whole


## Equips [param p_main] / [param p_off] (null = empty hand): updates the weapon stat
## sources (WeaponData.bonus_stats), rebuilds the WeaponRunners and the weapon models.
## Normally called by apply_equipment(); tests may call it directly.
func equip_weapons(p_main: WeaponData, p_off: WeaponData) -> void:
	main_hand = p_main
	off_hand = p_off
	if p_main != null:
		stats.set_source(&"weapon:main", p_main.bonus_stats)
	else:
		stats.remove_source(&"weapon:main")
	if p_off != null:
		stats.set_source(&"weapon:off", p_off.bonus_stats)
	else:
		stats.remove_source(&"weapon:off")
	for runner in weapons:
		remove_child(runner)
		runner.queue_free()
	weapons.clear()
	if p_main != null and p_main.attacks():
		_add_runner(WeaponRunner.create(p_main, self, false))
	if p_off != null and p_off.attacks():
		_add_runner(WeaponRunner.create(p_off, self, true))
	if model != null:
		model.set_weapons(p_main, p_off)


## Total block chance (percent) of the equipped weapons (shields).
func block_chance() -> float:
	var total := 0.0
	if main_hand != null:
		total += main_hand.block_chance
	if off_hand != null:
		total += off_hand.block_chance
	return total


## Multiplier on all outgoing damage of this player (Mastery, ability buffs ...).
## [param source]: &"weapon", &"proc", &"dot", &"ability", &"pet". [param target] may be null.
func outgoing_damage_mult(target: Node3D, school: StringName, source: StringName) -> float:
	var m := 1.0
	if abilities != null and abilities.mastery != null:
		m *= abilities.mastery.damage_mult(target, school, source)
	for v in damage_mults.values():
		m *= v
	return maxf(0.0, m)


## Temporary named outgoing-damage multipliers set by abilities / talents (key -> mult).
var damage_mults: Dictionary[StringName, float] = {}


## Consumes one guaranteed critical strike (Vanish ...). Weapon runners call this.
func consume_forced_crit() -> bool:
	if forced_crits <= 0:
		return false
	forced_crits -= 1
	return true


## Item modifiers for ability [param ability_id] from equipped items whose unique_effect is
## &"ability_mod" and unique_params.ability == ability_id (merged "mods" dictionaries; see
## AbilityRunner.apply_mods for the key conventions).
func ability_mods(ability_id: StringName) -> Dictionary:
	var out := {}
	if equipment == null:
		return out
	for item in equipment.equipped_items():
		if item.unique_effect != &"ability_mod" or StringName(item.unique_params.get("ability", "")) != ability_id:
			continue
		var mods: Dictionary = item.unique_params.get("mods", {})
		for key: String in mods:
			var v: Variant = mods[key]
			if typeof(v) in [TYPE_INT, TYPE_FLOAT] and out.has(key) and typeof(out[key]) in [TYPE_INT, TYPE_FLOAT]:
				out[key] = float(out[key]) + float(v)
			else:
				out[key] = v
	return out


## Revives a downed player at [param hp_ratio] of max HP (min 1 HP).
func revive(hp_ratio: float = REVIVE_HP_RATIO) -> void:
	if not downed:
		return
	downed = false
	revive_progress = 0.0
	reviver_count = 0
	healer_channel = 0.0
	healer_seconds_left = -1.0
	_regen_accum = 0.0
	var nobody: Array[Player] = []
	_update_channelers(nobody)
	velocity = Vector3.ZERO
	hp = clampf(roundf(max_hp() * hp_ratio), 1.0, max_hp())
	invulnerable_left = INVULNERABLE_AFTER_REVIVE
	if model != null:
		model.set_revive_progress(0.0)
		model.set_downed(false)
	_hp_updated()
	downed_changed.emit(false)


## Revive speed multiplier for [param revivers] living teammates inside REVIVE_RADIUS
## (0 = nobody: the progress decays instead).
static func revive_speed(revivers: int) -> float:
	if revivers <= 0:
		return 0.0
	return 1.0 + REVIVE_SPEED_PER_EXTRA_REVIVER * float(revivers - 1)


## Seconds until the revive completes at the current speed (-1 when nobody revives).
func revive_seconds_left() -> float:
	var speed := revive_speed(reviver_count)
	if not downed or speed <= 0.0:
		return -1.0
	return maxf(0.0, REVIVE_TIME - revive_progress) / speed


## Current top speed in m/s (GHOST_SPEED_MULT while downed).
func current_max_speed() -> float:
	return stats.move_speed() * (GHOST_SPEED_MULT if downed else 1.0)


func get_chest_position() -> Vector3:
	return global_position + Vector3.UP * CHEST_HEIGHT if is_inside_tree() else position + Vector3.UP * CHEST_HEIGHT


## Where this hero's own numbers (damage taken, heals, Dodge) start: beside the head on
## [param side] (+1 = screen right, -1 = left).
func self_text_position(side: float) -> Vector3:
	var base := global_position if is_inside_tree() else position
	return base + Vector3(SELF_TEXT_SIDE * signf(side if side != 0.0 else 1.0), SELF_TEXT_HEIGHT, 0.0)


## Separation step (XZ metres) that pushes a body at [param here] away from the
## [param others] closer than SEPARATION_DISTANCE during [param delta] seconds. Bodies on
## the exact same spot use [param fallback_angle] so they still part. Pure, unit tested.
static func separation_offset(here: Vector3, others: Array[Vector3], delta: float, fallback_angle: float = 0.0) -> Vector3:
	var push := Vector3.ZERO
	for o in others:
		var d := Vector3(here.x - o.x, 0.0, here.z - o.z)
		var dist := d.length()
		if dist >= SEPARATION_DISTANCE:
			continue
		var dir := d / dist if dist > 0.0001 else Vector3(cos(fallback_angle), 0.0, sin(fallback_angle))
		# Linear falloff: full speed when on top of each other, nothing at the edge.
		push += dir * (1.0 - dist / SEPARATION_DISTANCE)
	if push.length_squared() > 1.0:
		push = push.normalized()
	return push * SEPARATION_SPEED * delta


## Called by weapons: while standing still the model briefly turns towards its target.
func face_attack(direction: Vector3) -> void:
	var d := Vector3(direction.x, 0.0, direction.z)
	if d.length_squared() > 0.0001:
		_attack_look_dir = d.normalized()
		_attack_look_left = ATTACK_LOOK_TIME


# --- Frame update ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	invulnerable_left = maxf(0.0, invulnerable_left - delta)
	stealth_left = maxf(0.0, stealth_left - delta)
	res_sickness_left = maxf(0.0, res_sickness_left - delta)
	_attack_look_left = maxf(0.0, _attack_look_left - delta)
	_update_movement(delta)
	if downed:
		_update_revive(delta)
	else:
		_update_regen(delta)
	if model != null and procs != null:
		model.set_shield_ratio(procs.shield_hp / max_hp())


func _update_movement(delta: float) -> void:
	var move := Vector2.ZERO
	if slot != null and slot.input != null:
		move = slot.input.get_move()
	if move.length() > 1.0:
		move = move.normalized()
	var max_speed := current_max_speed()
	var target := Vector3(move.x, 0.0, move.y) * max_speed
	var rate := ACCELERATION if move.length() > MOVE_DEADZONE else DECELERATION
	velocity = Vector3(velocity.x, 0.0, velocity.z).move_toward(target, rate * delta)
	var arena := Arena.current if is_inside_tree() else null
	var motion := velocity * delta + _separation_motion(delta)
	if arena != null:
		motion = _clamp_motion_to_arena(arena, motion)
	# Shared screen (GDD 13): the screen edge of the fully zoomed-out camera is a wall.
	var walk := _camera_walk_rect(arena)
	var screen_wall := walk.size.x >= 0.0
	var start := global_position if screen_wall else Vector3.ZERO
	if screen_wall:
		motion = _clamp_motion_to_walk_rect(walk, motion)
	_move_body(motion)
	if screen_wall:
		# Sliding along a prop may deflect the motion past the screen edge: undo that part.
		var moved := global_position
		var kept := keep_inside_from(start, moved, walk)
		if kept != moved:
			global_position = kept
	if arena != null:
		# Safety net (spawn outside, physics push-out ...).
		var here := global_position
		var safe := arena.clamp_point(here, RADIUS)
		if safe != here:
			global_position = safe
	if move.length() > MOVE_DEADZONE:
		facing = Vector3(move.x, 0.0, move.y).normalized()
	if model != null:
		var look := facing
		if move.length() <= MOVE_DEADZONE and _attack_look_left > 0.0:
			look = _attack_look_dir
		model.set_facing(look)
		model.set_moving(clampf(velocity.length() / maxf(0.01, max_speed), 0.0, 1.0))


## Gentle push away from teammates standing (almost) on the same spot (see
## [method separation_offset]); ghosts and living heroes part alike.
func _separation_motion(delta: float) -> Vector3:
	if not is_inside_tree():
		return Vector3.ZERO
	var here := global_position
	var others: Array[Vector3] = []
	for node in get_tree().get_nodes_in_group(&"players"):
		var other := node as Node3D
		if other == null or other == self or not other.is_inside_tree():
			continue
		var o := other.global_position
		if absf(o.x - here.x) < SEPARATION_DISTANCE and absf(o.z - here.z) < SEPARATION_DISTANCE:
			others.append(o)
	if others.is_empty():
		return Vector3.ZERO
	# Deterministic split for bodies on the exact same spot: by slot index.
	var idx := slot.index if slot != null else 0
	return separation_offset(here, others, delta, float(idx) * 2.39996)


## Keeps [param motion] inside the arena bounds (shrunk by RADIUS + WALL_GAP) and stops the
## velocity component that pushes into an outer wall. The outer walls' inner faces lie on
## the bounds, so the physics query below never touches them: sliding along a wall costs a
## plain clamp instead of several capsule-vs-box casts per frame.
func _clamp_motion_to_arena(arena: Arena, motion: Vector3) -> Vector3:
	var here := global_position
	var b := arena.get_bounds().grow(-(RADIUS + WALL_GAP))
	if not b.has_area():
		return motion
	var dest := Vector3(here.x + motion.x, here.y + motion.y, here.z + motion.z)
	var cx := clampf(dest.x, minf(b.position.x, here.x), maxf(b.end.x, here.x))
	var cz := clampf(dest.z, minf(b.position.y, here.z), maxf(b.end.y, here.z))
	if cx != dest.x:
		velocity.x = 0.0
	if cz != dest.z:
		velocity.z = 0.0
	return Vector3(cx - here.x, motion.y, cz - here.z)


## Shared screen (GDD 13): the rectangle (XZ) this player may walk in so it never leaves the
## screen once the camera is fully zoomed out ([method CameraRig.get_walk_rect]). A rect with
## a negative size means "no limit" (no arena / camera, e.g. in unit tests).
func _camera_walk_rect(arena: Arena) -> Rect2:
	if arena == null or not is_instance_valid(arena.camera) or not arena.camera.is_inside_tree():
		return Rect2(0.0, 0.0, -1.0, -1.0)
	return arena.camera.get_walk_rect(self)


## Clamps [param motion] to [param walk] (see [method clamp_motion_to_rect]) and stops the
## velocity component that pushes against the screen edge, so the player slides along it.
func _clamp_motion_to_walk_rect(walk: Rect2, motion: Vector3) -> Vector3:
	var clamped := clamp_motion_to_rect(global_position, motion, walk)
	if clamped.x != motion.x:
		velocity.x = 0.0
	if clamped.z != motion.z:
		velocity.z = 0.0
	return clamped


## [param motion] from [param here] limited so the destination stays inside [param rect]
## (XZ). A body already outside the rect (the camera moved, a teleport ...) is never pushed:
## it may stay where it is or walk back in, but not further out. Y is left untouched.
static func clamp_motion_to_rect(here: Vector3, motion: Vector3, rect: Rect2) -> Vector3:
	var to := here + motion
	var dest := keep_inside_from(here, to, rect)
	# Untouched axes keep the exact motion (no float drift from the round trip).
	var mx := motion.x if dest.x == to.x else dest.x - here.x
	var mz := motion.z if dest.z == to.z else dest.z - here.z
	return Vector3(mx, motion.y, mz)


## [param to] limited (per axis, XZ) so it is inside [param rect] or, where [param from] was
## already outside, no further out than [param from].
static func keep_inside_from(from: Vector3, to: Vector3, rect: Rect2) -> Vector3:
	var x := clampf(to.x, minf(rect.position.x, from.x), maxf(rect.end.x, from.x))
	var z := clampf(to.z, minf(rect.position.y, from.z), maxf(rect.end.y, from.z))
	return Vector3(x, to.y, z)


## Moves by [param motion], sliding along walls. Uses move_and_collide so the motion is
## exactly the requested one (deterministic for tests and time-scaled smoke runs).
func _move_body(motion: Vector3) -> void:
	if motion.length_squared() < 1e-10:
		return
	if not is_inside_tree():
		position += motion
		return
	var remaining := motion
	for _i in 3:
		var col := move_and_collide(remaining)
		if col == null:
			break
		var normal := col.get_normal()
		normal.y = 0.0
		if normal.length_squared() < 1e-6:
			break
		normal = normal.normalized()
		remaining = col.get_remainder().slide(normal)
		remaining.y = 0.0
		velocity = velocity.slide(normal)
		if remaining.length_squared() < 1e-10:
			break


func _update_regen(delta: float) -> void:
	var regen := stats.hp_regen_per_second()
	if regen <= 0.0 or hp >= max_hp():
		_regen_accum = 0.0
		return
	_regen_accum += regen * delta
	if _regen_accum >= 1.0:
		var whole := floorf(_regen_accum)
		_regen_accum -= whole
		heal(whole)


func _update_revive(delta: float) -> void:
	var revivers := _revivers()
	reviver_count = revivers.size()
	if not revivers.is_empty():
		# Taking damage does not interrupt the revive (GDD 1): only standing in the circle counts.
		revive_progress = minf(REVIVE_TIME, revive_progress + delta * revive_speed(reviver_count))
	else:
		# The cast bar drains slowly instead of resetting (GDD 1).
		revive_progress = maxf(0.0, revive_progress - REVIVE_DECAY_PER_SECOND * delta)
	_update_channelers(revivers)
	if model != null:
		# GDD 1: "Resurrecting" cast bar in the reviver's colour with the time left.
		var color := OnionModel.REVIVE_COLOR
		if not revivers.is_empty() and revivers[0].slot != null:
			color = revivers[0].slot.color
		var ratio := revive_progress / REVIVE_TIME
		var seconds := revive_seconds_left()
		if healer_channel > ratio:
			# The Spirit Healer's channel is further along: show that one.
			ratio = healer_channel
			color = SpiritHealer.CAST_COLOR
			seconds = healer_seconds_left
		model.set_revive_progress(ratio, color, seconds)
	if revive_progress >= REVIVE_TIME - 0.0001:
		var feet := global_position
		revive(REVIVE_HP_RATIO)
		Vfx.resurrect_column(feet)
		Vfx.floating_text(get_chest_position() + Vector3.UP * 0.6, "Resurrected!", HEAL_TEXT_COLOR, 1.2)


## True when a living teammate stands within REVIVE_RADIUS.
func _has_reviver() -> bool:
	return not _revivers().is_empty()


## Living teammates standing within REVIVE_RADIUS.
func _revivers() -> Array[Player]:
	var out: Array[Player] = []
	if not is_inside_tree():
		return out
	var here := global_position
	for node in get_tree().get_nodes_in_group(&"players"):
		var other := node as Player
		if other == null or other == self or not other.is_alive() or not other.is_inside_tree():
			continue
		var d := other.global_position - here
		if Vector2(d.x, d.z).length() <= REVIVE_RADIUS:
			out.append(other)
	return out


## Reviving teammates raise glowing hands with a light beam to this ghost (GDD 1); the beam
## stops when they step out of the circle or the revive ends. A reviver already channeling
## another ghost keeps that one.
func _update_channelers(revivers: Array[Player]) -> void:
	var mine: Array[Player] = []
	for i in _channelers.size():
		var v: Variant = _channelers[i]
		if not is_instance_valid(v):
			continue  # a freed reviver (typed loop variables reject freed instances)
		var p := v as Player
		if p in revivers:
			mine.append(p)
		elif p.model != null:
			p.model.set_channel_target(null)
	for p in revivers:
		if p not in mine and p.model != null and not p.model.is_channeling():
			p.model.set_channel_target(self)
			mine.append(p)
	_channelers = mine


func _go_down() -> void:
	downed = true
	revive_progress = 0.0
	reviver_count = 0
	_regen_accum = 0.0
	invulnerable_left = 0.0
	stealth_left = 0.0
	if model != null:
		model.set_downed(true)
		model.set_revive_progress(0.0)
	downed_changed.emit(true)


func _hp_updated() -> void:
	var m := max_hp()
	if model != null:
		model.set_hp_ratio(clampf(hp / m, 0.0, 1.0))
	hp_changed.emit(hp, m)


func _on_stats_changed() -> void:
	if hp > max_hp():
		hp = max_hp()
	_hp_updated()


## TEMPORARY placeholder for the M4 level-up cards: sets the LEVEL_SOURCE stat source for
## team [param level] – one step per level gained since RunState.START_LEVEL (nothing at
## the starting level).
func _apply_level_bonus(level: int) -> void:
	var gained := level - RunState.START_LEVEL
	if gained <= 0:
		stats.remove_source(LEVEL_SOURCE)
		return
	stats.set_source(LEVEL_SOURCE, {Stats.STAMINA: LEVEL_STAMINA * gained})


## Adds a stat level-up card's stats (GDD 6.1) to CARD_SOURCE; a living hero's HP rises by
## any Max HP gained.
func add_card_stats(card_stats: Dictionary[StringName, float]) -> void:
	var before := max_hp()
	var total := stats.get_source(CARD_SOURCE) if stats.has_source(CARD_SOURCE) else {}
	for s: StringName in card_stats:
		total[s] = float(total.get(s, 0.0)) + card_stats[s]
	stats.set_source(CARD_SOURCE, total)
	var gained := max_hp() - before
	if not downed and gained > 0.0:
		hp = minf(max_hp(), hp + gained)
		_hp_updated()


## The team levelled up – grow the level bonus; a living hero's current HP rises by the Max
## HP gained (a ghost keeps 0 HP and comes back with its share of the new Max HP).
func _on_team_leveled_up(level: int) -> void:
	var before := max_hp()
	_apply_level_bonus(level)
	var gained := max_hp() - before
	if downed or gained <= 0.0:
		return
	hp = minf(max_hp(), hp + gained)
	_hp_updated()


## Thorns (GDD 2.4.1): a melee attacker takes this much damage back (flat, no multipliers).
func _thorns(attacker: Enemy, kind: StringName) -> void:
	if attacker == null or kind != CombatMath.KIND_MELEE or procs == null:
		return
	var thorns := stats.get_raw(Stats.THORNS)
	if thorns > 0.0 and is_instance_valid(attacker) and not attacker.is_dead():
		procs.deal_raw(attacker, thorns, CombatMath.SCHOOL_PHYSICAL, false)


## Parry (GDD 2.4.1): an immediate counter-strike with the first attacking weapon.
func _riposte(attacker: Enemy) -> void:
	if attacker == null or not is_instance_valid(attacker) or attacker.is_dead():
		return
	var runner := runner_for(null)
	if runner != null:
		runner.riposte(attacker)


func _add_runner(runner: WeaponRunner) -> void:
	weapons.append(runner)
	add_child(runner)


func _shake_camera(strength: float) -> void:
	var arena := Arena.current
	if arena != null and is_instance_valid(arena.camera):
		arena.camera.shake(strength)


## Floating-text number: damage / heal is no longer rounded by the combat math, so show a
## whole number when it is one (to one decimal) and one decimal otherwise ("2", "1.3").
static func _format_amount(value: float) -> String:
	var tenths := roundf(value * 10.0)
	if is_zero_approx(fmod(tenths, 10.0)):
		return str(int(tenths / 10.0))
	return "%.1f" % (tenths / 10.0)


func _exit_tree() -> void:
	if abilities != null:
		abilities.teardown()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and slot != null and slot.player == self:
		slot.player = null
