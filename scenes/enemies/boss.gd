class_name Boss
extends Enemy
## A boss (GDD 8 "Bossok", M6): Lich Commander Morvain (wave 10) and Vor'thalax, the Burning
## Tyrant (wave 25). Built from a [BossData] by [method create]; the [WaveDirector] spawns it at
## the start of a boss wave and the wave lasts until it dies. It walks at the nearest hero like
## a CHASE enemy (contact damage) and runs a scripted ability list on top:
##
## - Abilities ([member BossData.abilities], [BossAbility]): one cooldown timer each; a cast
##   lays down telegraphed hazards ([EnemyHazard]: [FrostCircle], [FrostBreath], [FireField],
##   [MeteorStrike]) or summons adds through the director ([method WaveDirector.summon]). A
##   stunned boss does not cast (the timers stand still); an ability that finds no target (no
##   living hero) retries a moment later. The first casts come after 60% of their interval.
## - Phase 2 at [member BossData.phase_hp_ratio] of its HP ([signal phase_changed]): the running
##   timers are rescaled to the phase-2 intervals, adds / patches come in larger numbers.
## - Enrage ([BossData.enrage_time], 90 s after it arrived): damage x1.5 and speed x1.3
##   ([member Enemy.damage_mult] / [member Enemy.speed_mult], which every contact hit and every
##   hazard it lays reads), then +0.25 damage every further 30 s ([signal enrage_changed]).
## - Crowd control: knockback does nothing (also the Warrior's direct pushes), stuns last
##   [constant STUN_SHARE] of their time, slows are halved (the ghost slow too), taunt and fear
##   are ignored.
## - Death ([method _death_loot]): 50 gold + XP, one [method LootDrops.drop_special] item
##   (Source.BOSS: Epic+, 20% Legendary, the player's own Fortune) per player – the killer first,
##   so the Artifact roll the first call makes uses the killer's Fortune –, then
##   RunState.record_special_kill(&"boss", killer). No normal drop roll and no second Artifact
##   roll.
## Damage numbers (hazards, enrage) are multiples of [member Enemy.contact_damage] (the boss's
## base contact damage at the wave x the party's damage factor).
## RunState.rng: Enemy.setup's draws, the casts that pick heroes (Fire Fields, Meteor) and the
## adds' own setup draws; all of it only on boss waves.

signal phase_changed(phase: int)
## The enrage level changed (1 = enraged, +1 for every further step).
signal enrage_changed(level: int)
signal ability_cast(ability: BossAbility)

## A stun lasts this share of its duration on a boss.
const STUN_SHARE := 0.25
## Slows land at this share of their strength.
const SLOW_SHARE := 0.5
## An ability that found no target tries again after this many seconds.
const RETRY_TIME := 0.5
## Adds appear on a ring of this radius (m) around the boss.
const SUMMON_RING := 2.8
const PHASE_TEXT_COLOR := Color(0.9, 0.75, 1.0)
## Fire Fields beyond the number of heroes land this far (m) from a hero.
const EXTRA_FIELD_OFFSET := 2.6


## The runtime state of one ability.
class AbilityState extends RefCounted:
	var ability: BossAbility
	## Seconds until the next cast.
	var left := 0.0
	var casts := 0


var boss_data: BossData
## The director that spawned it (adds come through it); null in isolated tests.
var director: WaveDirector
var phase := 1
var enrage_level := 0
var abilities: Array[AbilityState] = []
## Casts done so far (all abilities).
var casts_total := 0


## A boss of [param p_data] (a [BossData]; any EnemyData works, without abilities) at wave
## [param p_wave], not in the tree yet. Max HP follows the boss rule (BossData.max_hp_for:
## x(1 + 0.75 (players - 1)), --boss-hp), not Enemy.setup's co-op factor.
static func create(p_data: EnemyData, p_wave: int) -> Boss:
	var b := setup(Boss.new(), p_data, p_wave) as Boss
	b.boss_data = p_data as BossData
	if b.boss_data != null:
		b.max_hp = b.boss_data.max_hp_for(b.wave, RunState.player_count)
		b.hp = b.max_hp
		for a in b.boss_data.abilities:
			if a == null:
				continue
			var st := AbilityState.new()
			st.ability = a
			st.left = a.first_cast_delay()
			b.abilities.append(st)
	# The boss's own model (a lich / demon), replacing the placeholder setup built.
	if p_data != null and p_data.model_style in BossModel.BOSS_STYLES:
		var old := b.model
		b.remove_child(old)
		old.free()
		b.model = BossModel.new()
		b.model.name = "Model"
		b.add_child(b.model)
		b.model.setup(p_data)
	return b


## Seconds since it arrived.
func age() -> float:
	return _age


## The share of its max HP left (0..1).
func hp_ratio() -> float:
	return clampf(hp / maxf(1.0, max_hp), 0.0, 1.0)


## Whether the enrage has begun ([member enrage_level] > 0).
func is_boss_enraged() -> bool:
	return enrage_level > 0


## Contact damage of one of its hits at the current enrage ([member damage_mult] included),
## multiplied by [param mult]: what a hazard of that multiple deals now.
func damage_of(mult: float) -> float:
	return contact_damage * mult * damage_mult


# --- Crowd control -----------------------------------------------------------------------

## Immune to knockback: the hit lands, the push does not.
func take_damage(amount: float, is_crit: bool = false, attacker: Node3D = null,
		_knockback: Vector3 = Vector3.ZERO) -> void:
	super(amount, is_crit, attacker, Vector3.ZERO)


## Stuns last [constant STUN_SHARE] of their time.
func apply_stun(duration: float) -> void:
	super(duration * STUN_SHARE)


## Slows are halved.
func apply_slow(pct: float, duration: float) -> void:
	super(pct * SLOW_SHARE, duration)


## Taunts do not work on a boss.
func apply_taunt(_target: Node3D, _duration: float) -> void:
	pass


## Fear does not work on a boss.
func apply_fear(_duration: float, _from: Vector3) -> void:
	pass


## A ghost's revive circle slows a boss at half strength too: Enemy applies the ghost slow as a
## fixed Player.GHOST_SLOW_PCT in its movement step, so the walking speed it asks for is
## raised by the difference between the full and the halved slow.
func walk_speed() -> float:
	var s := super()
	if ghost_slow_left > 0.0:
		var own := slow_pct if slow_left > 0.0 else 0.0
		var g := Player.GHOST_SLOW_PCT
		if g > own:
			s *= (1.0 - g * SLOW_SHARE / 100.0) / (1.0 - g / 100.0)
	return s


## Pushes that bypass take_damage (the Warrior's direct knockback_velocity writes) end here.
func _apply_movement(delta: float, here: Vector3, stunned: bool) -> void:
	knockback_velocity = Vector3.ZERO
	super(delta, here, stunned)


# --- Frame ---------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	super(delta)
	if is_dead() or boss_data == null or not is_inside_tree():
		return
	_update_enrage()
	_update_phase()
	if stun_left <= 0.0:
		_update_abilities(delta)


func _update_enrage() -> void:
	var level := boss_data.enrage_level_at(_age)
	if level == enrage_level:
		return
	enrage_level = level
	damage_mult = boss_data.enrage_damage_at(level)
	speed_mult = boss_data.enrage_speed_mult if level > 0 else 1.0
	var top := model.head_height if model != null else 2.0
	Vfx.floating_text(global_position + Vector3.UP * (top + 0.6),
			"ENRAGED!" if level == 1 else "ENRAGED x%.2f" % damage_mult, ENRAGE_TEXT_COLOR, 1.3)
	enrage_changed.emit(level)


func _update_phase() -> void:
	if phase == 1 and hp <= max_hp * boss_data.phase_hp_ratio:
		_enter_phase(2)


## Switches to [param new_phase]: the running ability timers keep their progress at the new
## interval, the boss announces it.
func _enter_phase(new_phase: int) -> void:
	var old_phase := phase
	phase = new_phase
	for st in abilities:
		var old_interval := st.ability.interval_at(old_phase, boss_data.phase_cooldown_mult)
		var new_interval := st.ability.interval_at(phase, boss_data.phase_cooldown_mult)
		if old_interval > 0.0:
			st.left *= new_interval / old_interval
	var top := model.head_height if model != null else 2.0
	Vfx.floating_text(global_position + Vector3.UP * (top + 0.6), "Phase %d" % phase, PHASE_TEXT_COLOR, 1.3)
	Vfx.explosion(global_position + Vector3.UP * 0.4, radius * 2.2, PHASE_TEXT_COLOR)
	phase_changed.emit(phase)


func _update_abilities(delta: float) -> void:
	for st in abilities:
		st.left -= delta
		if st.left > 0.0:
			continue
		if _cast(st.ability):
			st.casts += 1
			casts_total += 1
			st.left = st.ability.interval_at(phase, boss_data.phase_cooldown_mult)
			ability_cast.emit(st.ability)
			if is_dead():
				return
		else:
			st.left = RETRY_TIME


## Casts [param a]; false when there was nothing to aim at (no living hero, no adds possible).
func _cast(a: BossAbility) -> bool:
	match a.kind:
		BossAbility.Kind.FROST_CIRCLES:
			return _cast_frost_circles(a)
		BossAbility.Kind.FROST_BREATH:
			return _cast_frost_breath(a)
		BossAbility.Kind.SUMMON:
			return _cast_summon(a)
		BossAbility.Kind.FIRE_FIELDS:
			return _cast_fire_fields(a)
		BossAbility.Kind.METEOR:
			return _cast_meteor(a)
	return false


## One ice circle under every living hero.
func _cast_frost_circles(a: BossAbility) -> bool:
	var heroes := _living_heroes()
	var parent := _world_parent()
	if heroes.is_empty() or parent == null:
		return false
	var dmg := damage_of(a.damage_mult)
	for hero in heroes:
		FrostCircle.spawn(parent, hero.global_position, a.radius, a.telegraph, dmg, a.slow_pct,
				a.slow_time, self)
	return true


## A cone towards the nearest living hero.
func _cast_frost_breath(a: BossAbility) -> bool:
	var parent := _world_parent()
	var target := _nearest_hero()
	if target == null or parent == null:
		return false
	var dir := target.global_position - global_position
	FrostBreath.spawn(parent, global_position, Vector3(dir.x, 0.0, dir.z), a.angle, a.range,
			a.telegraph, damage_of(a.damage_mult), self)
	return true


## Adds around the boss, through the director.
func _cast_summon(a: BossAbility) -> bool:
	var add := Db.get_enemy(a.summon_id)
	if add == null or director == null or not is_instance_valid(director):
		return false
	director.summon(add, a.count_at(phase), global_position, SUMMON_RING)
	return true


## [member BossAbility.count] burning patches, each on another hero (random order; beyond the
## number of heroes next to one).
func _cast_fire_fields(a: BossAbility) -> bool:
	var heroes := _living_heroes()
	var parent := _world_parent()
	if heroes.is_empty() or parent == null:
		return false
	var rng := RunState.rng
	# Fisher-Yates with the gameplay rng.
	for i in range(heroes.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := heroes[i]
		heroes[i] = heroes[j]
		heroes[j] = swap
	var dmg := damage_of(a.damage_mult)
	for i in a.count_at(phase):
		var at := heroes[i % heroes.size()].global_position
		if i >= heroes.size():
			var angle := rng.randf() * TAU
			at += Vector3(cos(angle), 0.0, sin(angle)) * EXTRA_FIELD_OFFSET
			if Arena.current != null and is_instance_valid(Arena.current):
				at = Arena.current.clamp_point(at, a.radius * 0.5)
		FireField.spawn(parent, at, a.radius, a.telegraph, a.duration, a.tick_interval, dmg, self)
	return true


## A meteor marker on a random living hero.
func _cast_meteor(a: BossAbility) -> bool:
	var heroes := _living_heroes()
	var parent := _world_parent()
	if heroes.is_empty() or parent == null:
		return false
	var hero := heroes[RunState.rng.randi_range(0, heroes.size() - 1)]
	MeteorStrike.spawn(parent, hero.global_position, a.radius, a.telegraph,
			damage_of(a.damage_mult), damage_of(a.fallback_damage_mult), self)
	return true


func _living_heroes() -> Array[Player]:
	var out: Array[Player] = []
	for p in Enemy.cached_players(get_tree()):
		if Enemy.is_living_player(p):
			out.append(p)
	return out


func _nearest_hero() -> Player:
	var best: Player = null
	var best_sq := INF
	for p in _living_heroes():
		var d := p.global_position - global_position
		var sq := d.x * d.x + d.z * d.z
		if sq < best_sq:
			best_sq = sq
			best = p
	return best


# --- Death -----------------------------------------------------------------------------------

## The boss's rewards (see the class notes). The items land on a ring around the body.
func _death_loot(pos: Vector3, attacker: Node3D) -> void:
	var killer: Player = null
	if attacker != null and is_instance_valid(attacker):
		killer = attacker as Player
	var killer_index := -1
	if killer != null and killer.slot != null:
		killer_index = killer.slot.index
	_drop_pickup(pos, boss_data.reward_gold if boss_data != null else 50, data.xp if data != null else 0)
	var heroes := _loot_heroes(killer)
	var n := maxi(1, heroes.size())
	for i in n:
		var hero: Node3D = heroes[i] if i < heroes.size() else null
		if n > 1 and is_inside_tree():
			var a := TAU * float(i) / float(n)
			global_position = Vector3(pos.x + cos(a) * 1.2, 0.0, pos.z + sin(a) * 1.2)
		LootDrops.drop_special(ItemGenerator.Source.BOSS, self, hero)
	if is_inside_tree():
		global_position = Vector3(pos.x, 0.0, pos.z)
	RunState.record_special_kill(&"boss", killer_index)
	Vfx.explosion(pos + Vector3.UP * 0.5, radius * 3.0, ENRAGE_TEXT_COLOR if enrage_level > 0 else PHASE_TEXT_COLOR)
	Vfx.pickup_sparkle(pos + Vector3.UP * 1.0)


## The heroes that get an item, the killer first (the Artifact roll the first drop makes is the
## killer's), then the others in slot order. One entry per joined player; entries are null for
## a slot without a hero. Without any joined slot (tests): RunState.player_count nulls.
func _loot_heroes(killer: Player) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var slots := PlayerManager.get_slots()
	if slots.is_empty():
		for i in maxi(1, RunState.player_count):
			out.append(killer if i == 0 else null)
		return out
	for s in slots:
		var hero: Node3D = null
		if is_instance_valid(s.player):
			hero = s.player
		if killer != null and hero == killer:
			out.push_front(hero)
		else:
			out.append(hero)
	if killer != null and not out.has(killer):
		out.push_front(killer)
		if out.size() > slots.size():
			out.pop_back()
	return out
