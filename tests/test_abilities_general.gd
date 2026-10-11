extends TestCase
## General abilities (M4, GDD 6.4 – class_id empty, learnable by every class): Bandage,
## Sprint, Engineer's Bomb, War Stomp, Spirit Wolf, Berserking. Data (ranks / specs), the
## effects with several classes, power scaling, Rank III and both Rank V specs, the auto-cast /
## bot rules and the clean-up on expiry, going down, the wave hooks and forget.

const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0
const IDS: Array[StringName] = [&"bandage", &"sprint", &"engineers_bomb", &"war_stomp",
		&"spirit_wolf", &"berserking"]
const ACTIVE_IDS: Array[StringName] = [&"bandage", &"sprint", &"berserking"]
## Long enough for the runner's next auto-cast decision (every 0.25 s).
const DECIDE := AbilityRunner.AUTO_CAST_INTERVAL + 2.0 * DT


## An enemy that dies when its HP runs out and records hits, stuns and slows (no AI / model).
class MortalEnemy extends Enemy:
	var hits: Array[float] = []
	var attackers: Array[Node3D] = []
	var stuns: Array[float] = []
	var slows: Array[float] = []

	func _init() -> void:
		hp = 1000.0
		max_hp = 1000.0
		radius = 0.45

	func _enter_tree() -> void:
		pass

	func _ready() -> void:
		pass

	func _process(_delta: float) -> void:
		pass

	func _physics_process(_delta: float) -> void:
		pass

	func is_dead() -> bool:
		return hp <= 0.0

	func take_damage(amount: float, _is_crit: bool = false, attacker: Node3D = null,
			_knockback: Vector3 = Vector3.ZERO) -> void:
		hits.append(amount)
		attackers.append(attacker)
		hp -= amount

	func apply_stun(duration: float) -> void:
		stuns.append(duration)

	func apply_slow(pct: float, _duration: float) -> void:
		slows.append(pct)

	func total() -> float:
		var t := 0.0
		for v in hits:
			t += v
		return t


var world: Node3D


func before_each() -> void:
	PlayerManager.clear()
	RunState.start_run(1, 4711)
	Enemy.invalidate_player_cache()
	world = Fakes.make_world(tree)
	EnemyGrid.mark_dirty()


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	PlayerManager.clear()
	Enemy.invalidate_player_cache()
	EnemyGrid.mark_dirty()


# --- Helpers ----------------------------------------------------------------------------------

func _hero(class_id: StringName, pos: Vector3 = Vector3.ZERO, index: int = 0) -> Player:
	return Fakes.spawn_player(world, index, class_id, pos)


func _enemy(pos: Vector3, hp: float = 1000.0) -> MortalEnemy:
	var e := MortalEnemy.new()
	e.hp = hp
	e.max_hp = maxf(hp, 1.0)
	e.add_to_group(&"enemies")
	world.add_child(e)
	e.global_position = pos
	EnemyGrid.mark_dirty()
	return e


func _ability(id: StringName) -> AbilityData:
	return Db.get_ability(id)


## Learns [param id] (Rank I) and raises it to [param rank] with Rank V spec [param spec].
func _learn(p: Player, id: StringName, rank: int = 1, spec: int = -1) -> AbilityData:
	var a := _ability(id)
	check(p.abilities.learn(a) >= 0, "%s learned" % id)
	for i in rank - 1:
		p.abilities.rank_up(id)
	if spec >= 0:
		check(p.abilities.set_spec(id, spec), "%s spec %d" % [id, spec])
	return a


func _ctx(p: Player, a: AbilityData) -> AbilityContext:
	return p.abilities.build_context(a)


func _effect(p: Player, a: AbilityData) -> AbilityEffect:
	return p.abilities.effect_for(a)


## Presses the ability's button (Active slots) / casts it through the runner.
func _cast(p: Player, a: AbilityData) -> bool:
	return p.abilities.try_cast(p.abilities.slot_of(a.id))


## Steps the heroes' ability runners and every general-ability node (buffs, wolves, bombs,
## areas) – the test tree does not run physics frames by itself.
func _run(players: Array[Player], seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		for p in players:
			if is_instance_valid(p):
				p.abilities._physics_process(DT)
		var nodes: Array[Node] = []
		for child in world.get_children():
			nodes.append(child)
			if child is Player:
				nodes.append_array(child.get_children())
		for node in nodes:
			if not is_instance_valid(node) or node.is_queued_for_deletion():
				continue
			if node is GeneralBuff:
				(node as GeneralBuff).step(DT)
			elif node is GeneralSpiritWolfPet:
				(node as GeneralSpiritWolfPet).step(DT)
			elif node is GeneralBombShell:
				(node as GeneralBombShell).advance(DT)
			elif node is AbilityArea:
				(node as AbilityArea)._physics_process(DT)
		t += DT


func _of_type(script: Script) -> Array[Node]:
	var out: Array[Node] = []
	for child in world.get_children():
		if is_instance_of(child, script) and not child.is_queued_for_deletion():
			out.append(child)
	return out


func _hurt(p: Player, ratio: float) -> void:
	p.hp = p.max_hp() * ratio
	p._hp_updated()


func _expected_weapon(p: Player, school: StringName) -> float:
	var w := p.main_hand
	return CombatMath.weapon_base_damage(w, p.stats) / w.cooldown * CombatMath.damage_mult_for(p.stats, school)


# --- Data -------------------------------------------------------------------------------------

func test_general_abilities_are_complete_data() -> void:
	var placeholder := RegEx.create_from_string("\\{([a-z_]+)\\}")
	for id in IDS:
		var a := _ability(id)
		check(a != null, "%s exists" % id)
		if a == null:
			continue
		check_eq(a.class_id, &"", "%s is general" % id)
		var want_kind := AbilityData.Kind.ACTIVE if id in ACTIVE_IDS else AbilityData.Kind.AUTO
		check_eq(a.kind, want_kind, "%s kind" % id)
		check(a.effect != null and a.effect.new() is AbilityEffect, "%s effect" % id)
		check_eq(a.resource, &"", "%s is free" % id)
		check(a.cooldown >= 4.0 and a.cooldown <= 20.0, "%s cooldown 4-20 s" % id)
		check(a.card_weight > 0.0, "%s is offered" % id)
		check(a.display_name != "" and a.description != "" and a.icon == id, "%s texts / icon" % id)
		for m in placeholder.search_all(a.description):
			check(a.params.has(m.get_string(1)), "%s description param {%s}" % [id, m.get_string(1)])
		check(not a.rank3.is_empty() and a.rank3_text != "", "%s Rank III" % id)
		_check_mod_keys(a, a.rank3, "rank3")
		check_eq(a.specs.size(), 2, "%s has two specs" % id)
		for s in a.specs:
			check(String(s.get("name", "")) != "" and String(s.get("text", "")) != "", "%s spec texts" % id)
			var mods: Dictionary = s.get("mods", {})
			check(not mods.is_empty(), "%s spec mods" % id)
			_check_mod_keys(a, mods, String(s.get("name", "")))


## Every key a mod touches must be a param the effect reads (so the data matches the code).
func _check_mod_keys(a: AbilityData, mods: Dictionary, what: String) -> void:
	for key: String in mods:
		var param := key
		if key.ends_with("_add"):
			param = key.trim_suffix("_add")
		elif key.ends_with("_pct"):
			param = key.trim_suffix("_pct")
		check(a.params.has(param), "%s %s: '%s' is a param" % [a.id, what, param])


func test_every_class_is_offered_the_general_pool() -> void:
	for class_id in Db.class_ids:
		var pool := Db.ability_pool(class_id)
		for id in IDS:
			check(pool.has(_ability(id)), "%s offered to %s" % [id, class_id])


func test_two_classes_learn_into_their_slots() -> void:
	for class_id: StringName in [&"warrior", &"mage"]:
		var p := _hero(class_id)
		check_eq(p.abilities.learn(_ability(&"bandage")), 2, "%s: Bandage -> RB" % class_id)
		check_eq(p.abilities.learn(_ability(&"berserking")), 3, "%s: Berserking -> LB" % class_id)
		check_eq(p.abilities.learn(_ability(&"engineers_bomb")), 4, "%s: bomb -> auto" % class_id)
		check_eq(p.abilities.learn(_ability(&"war_stomp")), 5, "%s: stomp -> auto" % class_id)
		check_eq(p.abilities.learn(_ability(&"spirit_wolf")), 6, "%s: wolf -> auto" % class_id)
		check_eq(p.abilities.learn(_ability(&"sprint")), -1, "%s: actives full" % class_id)
		p.queue_free()


# --- Bandage ----------------------------------------------------------------------------------

func test_bandage_heals_30_percent_over_3_seconds() -> void:
	for class_id: StringName in [&"warrior", &"mage"]:
		var p := _hero(class_id)
		var a := _learn(p, &"bandage")
		_hurt(p, 0.1)
		var before := p.hp
		check(_cast(p, a), "%s bandages" % class_id)
		check(GeneralBuff.find(p, GeneralBandage.KEY) != null, "bandaged")
		check_near(p.hp, before, 0.001, "heals over time, not at once")
		_run([p], 1.5)
		check_near(p.hp - before, p.max_hp() * 0.15, 0.01, "%s: half after 1.5 s" % class_id)
		# Taking damage does not interrupt the bandage.
		p.invulnerable_left = 0.0
		p.take_damage(0.5)
		var mid := p.hp
		check(GeneralBuff.find(p, GeneralBandage.KEY) != null, "a hit does not interrupt it")
		_run([p], 1.5)
		check_near(p.hp - mid, p.max_hp() * 0.15, 0.01, "%s: the rest after 3 s" % class_id)
		check(GeneralBuff.find(p, GeneralBandage.KEY) == null, "done")
		check_near(p.abilities.remaining(p.abilities.slot_of(&"bandage")), 20.0 - 3.0, 0.05, "20 s cooldown")
		p.queue_free()


func test_bandage_power_and_rank3_bandages_an_ally() -> void:
	var p := _hero(&"mage")
	var ally := _hero(&"warrior", Vector3(3, 0, 0), 1)
	var far := _hero(&"rogue", Vector3(12, 0, 0), 2)
	var a := _learn(p, &"bandage", 3)
	check_near(float(p.abilities.params_for(a)["power"]), 1.25, 0.0001, "Rank II power")
	_hurt(p, 0.2)
	_hurt(ally, 0.3)
	_hurt(far, 0.1)
	var hp0 := [p.hp, ally.hp, far.hp]
	check(_cast(p, a), "cast")
	_run([p, ally, far], 3.0)
	check_near(p.hp - hp0[0], p.max_hp() * 0.3 * 1.25, 0.01, "caster healed 37.5%")
	check_near(ally.hp - hp0[1], ally.max_hp() * 0.3 * 1.25, 0.01, "Rank III: the wounded ally too")
	check_near(far.hp, hp0[2], 0.001, "out of range")


func test_bandage_specs() -> void:
	var p := _hero(&"warrior")
	var a := _learn(p, &"bandage", 5, 0)
	_hurt(p, 0.1)
	var before := p.hp
	check(_cast(p, a), "Quick Wrap")
	check_near(p.hp - before, p.max_hp() * 0.3 * 1.5, 0.01, "the whole heal lands at once (x1.5 at Rank V)")
	var q := _hero(&"mage", Vector3(20, 0, 0), 1)
	var b := _learn(q, &"bandage", 5, 1)
	_hurt(q, 0.5)
	check(_cast(q, b), "Padded Wraps")
	check_near(float(q.damage_taken_mults.get(GeneralBandage.KEY, 1.0)), 1.0 - 0.25 * 1.5, 0.0001,
			"37.5% less damage taken while bandaged")
	_run([q], 3.0)
	check(not q.damage_taken_mults.has(GeneralBandage.KEY), "removed with the bandage")


func test_bandage_rules_and_cleanup() -> void:
	var p := _hero(&"paladin")
	var a := _learn(p, &"bandage")
	var effect := _effect(p, a)
	check(not p.abilities.can_cast(p.abilities.slot_of(&"bandage")), "nothing to heal at full HP")
	_hurt(p, 0.7)
	check(p.abilities.can_cast(p.abilities.slot_of(&"bandage")), "castable when hurt")
	check(not effect.wants_auto_cast(_ctx(p, a)), "bots wait until below 50%")
	_hurt(p, 0.4)
	check(effect.wants_auto_cast(_ctx(p, a)), "bots bandage below 50%")
	_cast(p, a)
	check(not effect.wants_auto_cast(_ctx(p, a)), "not twice")
	p.end_wave()
	check(GeneralBuff.find(p, GeneralBandage.KEY) == null, "end_wave removes it")
	p.abilities.set_cooldown(a, 0.0)
	_cast(p, a)
	p._go_down()
	check(GeneralBuff.find(p, GeneralBandage.KEY) == null, "going down ends it")


# --- Sprint -----------------------------------------------------------------------------------

func test_sprint_is_a_named_speed_source() -> void:
	for class_id: StringName in [&"rogue", &"warrior"]:
		var p := _hero(class_id)
		var a := _learn(p, &"sprint")
		var base_speed := p.stats.move_speed()
		var speed0 := p.stats.get_raw(Stats.SPEED)
		check(_cast(p, a), "%s sprints" % class_id)
		check(p.stats.has_source(GeneralSprint.KEY), "named stat source")
		check_near(p.stats.move_speed(), Stats.BASE_MOVE_SPEED * (1.0 + (speed0 + 50.0) / 100.0), 0.001, "+50% Speed")
		_run([p], 2.9)
		check(p.stats.has_source(GeneralSprint.KEY), "still sprinting")
		_run([p], 0.15)
		check(not p.stats.has_source(GeneralSprint.KEY), "%s: removed after 3 s" % class_id)
		check_near(p.stats.move_speed(), base_speed, 0.001, "speed back")
		p.queue_free()


func test_sprint_power_and_rank3_dodge() -> void:
	var p := _hero(&"mage")
	var a := _learn(p, &"sprint", 3)
	_cast(p, a)
	var src := p.stats.get_source(GeneralSprint.KEY)
	check_near(float(src.get(Stats.SPEED, 0.0)), 62.5, 0.001, "50% x 1.25")
	check_near(float(src.get(Stats.DODGE, 0.0)), 25.0, 0.001, "Rank III: +20% Dodge x 1.25")


func test_sprint_specs_rally_and_trail() -> void:
	var p := _hero(&"paladin")
	var near := _hero(&"warlock", Vector3(4, 0, 0), 1)
	var far := _hero(&"rogue", Vector3(15, 0, 0), 2)
	var a := _learn(p, &"sprint", 5, 0)
	_cast(p, a)
	check(near.stats.has_source(GeneralSprint.KEY), "Rallying Sprint: the ally within 8 m")
	check(not far.stats.has_source(GeneralSprint.KEY), "not the far one")
	_run([p, near, far], 3.1)
	check(not near.stats.has_source(GeneralSprint.KEY), "the ally's sprint ends too")
	var q := _hero(&"warrior", Vector3(-10, 0, 0), 3)
	var b := _learn(q, &"sprint", 5, 1)
	_cast(q, b)
	var effect := _effect(q, b) as GeneralSprint
	_run([q], 1.0)
	check(effect.trail_areas.size() >= 3, "Trailblazer leaves areas")
	var area := effect.trail_areas[0]
	check_near(area.slow_pct, 40.0 * 1.5, 0.001, "slows 40% x 1.5")
	q.end_wave()
	check(not q.stats.has_source(GeneralSprint.KEY), "end_wave")
	check(effect.trail_areas.is_empty() and not effect.is_trailing(), "trail gone")


func test_sprint_cleanup_down_wave_forget() -> void:
	var p := _hero(&"warlock")
	var a := _learn(p, &"sprint")
	_cast(p, a)
	p._go_down()
	check(not p.stats.has_source(GeneralSprint.KEY), "going down")
	p.revive()
	p.abilities.set_cooldown(a, 0.0)
	_cast(p, a)
	p.begin_wave()
	check(not p.stats.has_source(GeneralSprint.KEY), "begin_wave")
	_cast(p, a)
	p.abilities.forget(p.abilities.slot_of(&"sprint"))
	check(not p.stats.has_source(GeneralSprint.KEY), "forget")


func test_sprint_bot_rule() -> void:
	var p := _hero(&"mage")
	var a := _learn(p, &"sprint")
	var effect := _effect(p, a)
	_enemy(Vector3(0, 0, -2))
	check(not effect.wants_auto_cast(_ctx(p, a)), "healthy: no need to run")
	_hurt(p, 0.3)
	check(effect.wants_auto_cast(_ctx(p, a)), "hurt with an enemy close: run")
	_hurt(p, 1.0)
	_enemy(Vector3(2, 0, 0))
	_enemy(Vector3(-2, 0, 0))
	check(not effect.wants_auto_cast(_ctx(p, a)), "three close: not crowded yet")
	_enemy(Vector3(0, 0, 2))
	check(effect.wants_auto_cast(_ctx(p, a)), "crowded: run")
	var q := _hero(&"warrior", Vector3(30, 0, 0), 2)
	var b := _learn(q, &"sprint")
	check(not _effect(q, b).wants_auto_cast(_ctx(q, b)), "nothing around")
	var ghost := _hero(&"rogue", Vector3(34, 0, 0), 1)
	ghost._go_down()
	check(_effect(q, b).wants_auto_cast(_ctx(q, b)), "rush to a downed teammate")


# --- Berserking -------------------------------------------------------------------------------

func test_berserking_haste_and_own_cooldown() -> void:
	for class_id: StringName in [&"warlock", &"warrior"]:
		var p := _hero(class_id)
		var a := _learn(p, &"berserking")
		var haste0 := p.stats.get_raw(Stats.HASTE)
		var full := p.abilities.cooldown_of(a)
		check(_cast(p, a), "%s goes berserk" % class_id)
		check_near(p.abilities.remaining(p.abilities.slot_of(&"berserking")), full, 0.001,
				"its own cooldown is booked without the Haste")
		_run([p], DT)
		check_near(p.stats.get_raw(Stats.HASTE), haste0 + 20.0, 0.001, "+20% Haste")
		_run([p], 6.0)
		check(not p.stats.has_source(GeneralBerserking.KEY), "%s: gone after 6 s" % class_id)
		p.queue_free()


func test_berserking_specs() -> void:
	var p := _hero(&"rogue")
	var a := _learn(p, &"berserking", 5, 0)
	_cast(p, a)
	_run([p], DT)
	var effect := _effect(p, a) as GeneralBerserking
	var buff := effect.active_buff()
	check(buff != null, "berserking")
	check_near(float(p.stats.get_source(GeneralBerserking.KEY)[Stats.HASTE]), 30.0, 0.001, "20% x 1.5")
	var left := buff.left
	var dummy := _enemy(Vector3(30, 0, 0))
	p.notify_kill(dummy)
	check_near(buff.left, left + 0.5, 0.001, "Feeding Frenzy: +0.5 s per kill")
	for i in 20:
		p.notify_kill(dummy)
	check_near(buff.extended, 6.0, 0.001, "at most +6 s")
	var q := _hero(&"paladin", Vector3(20, 0, 0), 1)
	var b := _learn(q, &"berserking", 5, 1)
	_cast(q, b)
	_run([q], DT)
	check_near(float(q.stats.get_source(GeneralBerserking.KEY)[Stats.HASTE]), (20.0 + 25.0) * 1.5, 0.001,
			"Reckless Fury: +45% x 1.5")
	check_near(float(q.damage_taken_mults[GeneralBerserking.KEY]), 1.15, 0.0001, "takes 15% more damage")
	q._go_down()
	check(not q.damage_taken_mults.has(GeneralBerserking.KEY) and not q.stats.has_source(GeneralBerserking.KEY),
			"going down ends it")


func test_berserking_bot_rule() -> void:
	var p := _hero(&"warrior")
	var a := _learn(p, &"berserking")
	var effect := _effect(p, a)
	_enemy(Vector3(0, 0, -3))
	_enemy(Vector3(2, 0, -2))
	check(not effect.wants_auto_cast(_ctx(p, a)), "two enemies: not yet")
	_enemy(Vector3(-2, 0, 2))
	check(effect.wants_auto_cast(_ctx(p, a)), "three within 6 m")
	_cast(p, a)
	_run([p], DT)
	check(not effect.wants_auto_cast(_ctx(p, a)), "not while berserking")
	p.end_wave()
	check(not p.stats.has_source(GeneralBerserking.KEY), "end_wave")


# --- Engineer's Bomb --------------------------------------------------------------------------

func test_bomb_damage_scales_with_every_class() -> void:
	for class_id in Db.class_ids:
		var p := _hero(class_id, Vector3(float(Db.class_ids.find(class_id)) * 30.0, 0, 0))
		var a := _learn(p, &"engineers_bomb")
		var bare := GeneralEngineersBomb.bomb_damage(_ctx(p, a))
		var primary := GeneralKit.primary_stat(p)
		var p0 := maxf(0.0, p.stats.get_raw(primary))
		check_near(bare, (8.0 + p0 * 0.75) * CombatMath.damage_mult_for(p.stats, &"fire"), 0.001, "%s base" % class_id)
		p.stats.set_source(&"t_ap", {Stats.ATTACK_POWER: 10.0})
		var with_ap := GeneralEngineersBomb.bomb_damage(_ctx(p, a))
		p.stats.remove_source(&"t_ap")
		p.stats.set_source(&"t_sp", {Stats.SPELL_POWER: 10.0})
		var with_sp := GeneralEngineersBomb.bomb_damage(_ctx(p, a))
		check_near(with_ap, with_sp, 0.001, "%s: the better of Attack / Spell Power counts" % class_id)
		check_near(with_sp - bare, 10.0 * CombatMath.damage_mult_for(p.stats, &"fire"), 0.001, "%s: +10 power" % class_id)
		p.stats.set_source(&"t_main", {primary: 4.0})
		check_near(GeneralEngineersBomb.bomb_damage(_ctx(p, a)) - with_sp, 3.0 * CombatMath.damage_mult_for(p.stats, &"fire"),
				0.001, "%s: primary stat x 0.75" % class_id)
		p.queue_free()


func test_bomb_hits_the_densest_group() -> void:
	var p := _hero(&"warrior")
	var a := _learn(p, &"engineers_bomb")
	var group := [_enemy(Vector3(-0.6, 0, -6)), _enemy(Vector3(0.6, 0, -6)), _enemy(Vector3(0, 0, -6.6))]
	var lone := _enemy(Vector3(7, 0, 0))
	var damage := GeneralEngineersBomb.bomb_damage(_ctx(p, a))
	_run([p], DT)
	var effect := _effect(p, a) as GeneralEngineersBomb
	check_eq(effect.bombs.size(), 1, "an auto slot throws by itself")
	var bomb := effect.bombs[0]
	check(GeneralKit.flat_distance(bomb.landing, Vector3(0, 0, -6.2)) < 0.3, "aimed at the group")
	_run([p], 0.3)
	check(group[0].hits.is_empty(), "still in flight")
	_run([p], 0.4)
	check(bomb.exploded, "exploded")
	for e: MortalEnemy in group:
		check_eq(e.hits.size(), 1, "the group is hit")
		check_near(e.hits[0], damage, 0.001, "bomb damage")
		check(e.attackers[0] == p, "kill credit")
	check(lone.hits.is_empty(), "the lone enemy is not")


func test_bomb_auto_rule_and_rank3() -> void:
	var p := _hero(&"mage")
	var a := _learn(p, &"engineers_bomb", 3)
	var effect := _effect(p, a)
	_enemy(Vector3(0, 0, -5))
	check(not effect.wants_auto_cast(_ctx(p, a)), "one enemy: not worth a bomb")
	_enemy(Vector3(0.8, 0, -5))
	check(effect.wants_auto_cast(_ctx(p, a)), "two in the circle")
	_enemy(Vector3(6, 0, 2))
	check(_cast(p, a), "cast")
	var bombs := (effect as GeneralEngineersBomb).bombs
	check_eq(bombs.size(), 2, "Rank III: two bombs")
	check(GeneralKit.flat_distance(bombs[1].landing, Vector3(6, 0, 2)) < 0.01, "the second goes to the next group")
	check_near(bombs[0].damage, GeneralEngineersBomb.bomb_damage(_ctx(p, a)), 0.001, "x1.25 power in the damage")
	p.end_wave()
	check(bombs.is_empty(), "end_wave drops the bombs in flight")


func test_bomb_specs() -> void:
	var p := _hero(&"rogue")
	var a := _learn(p, &"engineers_bomb", 5, 0)
	_enemy(Vector3(0, 0, -5))
	_enemy(Vector3(0.5, 0, -5))
	var effect := _effect(p, a) as GeneralEngineersBomb
	check(_cast(p, a), "Cluster Bomb")
	var damage := effect.bombs[0].damage
	var mains := effect.bombs.duplicate()
	check_eq(mains.size(), 2, "Rank V keeps the Rank III bomb")
	_run([p], 0.6)
	var bomblets := _of_type(GeneralBombShell)
	check_eq(bomblets.size(), 4 * mains.size(), "four bomblets per bomb")
	for b: GeneralBombShell in bomblets:
		check(b.is_bomblet, "small ones")
		check_near(b.damage, damage * 0.4, 0.001, "40% damage each")
		var parent := INF
		for m: GeneralBombShell in mains:
			parent = minf(parent, GeneralKit.flat_distance(b.start, m.landing))
		check(parent < 0.01, "thrown from a blast")
		var d := GeneralKit.flat_distance(b.landing, b.start)
		check(d >= 1.39 and d <= 2.41, "scattered 1.4-2.4 m")
	_run([p], 0.4)
	check(_of_type(GeneralBombShell).is_empty(), "bomblets exploded")
	var q := _hero(&"warlock", Vector3(30, 0, 0), 1)
	var b2 := _learn(q, &"engineers_bomb", 5, 1)
	_enemy(Vector3(30, 0, -5))
	_enemy(Vector3(30.5, 0, -5))
	var e2 := _effect(q, b2) as GeneralEngineersBomb
	check(_cast(q, b2), "Incendiary Bomb")
	var shell := e2.bombs[0]
	_run([q], 0.6)
	var fire := shell.burn_area
	check(fire != null and is_instance_valid(fire), "burning ground")
	check_near(fire.duration, 4.0, 0.001, "4 sec")
	check_near(fire.damage_per_tick, shell.damage * 0.15, 0.001, "15% per tick")
	check_eq(fire.school, &"fire", "fire")


# --- War Stomp --------------------------------------------------------------------------------

func test_war_stomp_stuns_and_hits_the_crowd() -> void:
	for class_id: StringName in [&"paladin", &"rogue"]:
		var x := 0.0 if class_id == &"paladin" else 40.0
		var p := _hero(class_id, Vector3(x, 0, 0))
		var a := _learn(p, &"war_stomp")
		var close := [_enemy(Vector3(x + 1.5, 0, 0)), _enemy(Vector3(x, 0, -2.2))]
		var away := _enemy(Vector3(x + 5, 0, 0))
		var expected := _expected_weapon(p, &"physical") * 0.6
		check_near(GeneralWarStomp.stomp_damage(_ctx(p, a)), expected, 0.001, "60% normalised weapon damage")
		_run([p], DT)
		for e: MortalEnemy in close:
			check_eq(e.stuns, [1.0] as Array[float], "%s: stunned 1 s" % class_id)
			check_near(e.total(), expected, 0.001, "%s: hit once" % class_id)
		check(away.stuns.is_empty() and away.hits.is_empty(), "out of reach")
		check_near(p.abilities.remaining(p.abilities.slot_of(&"war_stomp")), 10.0 - DT, 0.02, "10 s cooldown")
		p.queue_free()


func test_war_stomp_normalises_the_weapon() -> void:
	var p := _hero(&"warrior")
	var a := _learn(p, &"war_stomp")
	check_near(GeneralKit.weapon_damage(p), 6.0 / 0.9, 0.001, "sword 6 per 0.9 s -> 6.67 per second")
	var ctx := _ctx(p, a)
	p.abilities.rank_up(&"war_stomp")
	var ranked := _ctx(p, a)
	check_near(GeneralWarStomp.stomp_damage(ranked), GeneralWarStomp.stomp_damage(ctx) * 1.25, 0.001, "Rank II x1.25")
	p.abilities.rank_up(&"war_stomp")
	check_near(GeneralWarStomp.reach_of(_ctx(p, a)), 3.5, 0.001, "Rank III: +1 m")


func test_war_stomp_auto_rule() -> void:
	var p := _hero(&"mage")
	var a := _learn(p, &"war_stomp")
	var effect := _effect(p, a)
	check(not effect.wants_auto_cast(_ctx(p, a)), "nobody close")
	_enemy(Vector3(1.5, 0, 0))
	check(not effect.wants_auto_cast(_ctx(p, a)), "one enemy: wait")
	_hurt(p, 0.3)
	check(effect.wants_auto_cast(_ctx(p, a)), "one enemy while hurt")
	_hurt(p, 1.0)
	_enemy(Vector3(-1.5, 0, 0))
	check(effect.wants_auto_cast(_ctx(p, a)), "two enemies")


func test_war_stomp_specs() -> void:
	var p := _hero(&"warrior")
	var a := _learn(p, &"war_stomp", 5, 0)
	var e := _enemy(Vector3(1.0, 0, 0))
	_enemy(Vector3(-1.0, 0, 0))
	_run([p], DT)
	check_eq(e.stuns.size(), 1, "first stomp")
	var effect := _effect(p, a) as GeneralWarStomp
	check_eq(effect.pending_aftershocks(), 1, "Aftershock pending")
	_run([p], 0.9)
	check_eq(e.stuns.size(), 1, "not yet")
	_run([p], 0.15)
	check_eq(e.stuns.size(), 2, "the aftershock stuns again")
	check_eq(e.hits.size(), 2, "and hits again")
	var q := _hero(&"paladin", Vector3(30, 0, 0), 1)
	var b := _learn(q, &"war_stomp", 5, 1)
	var f := _enemy(Vector3(31, 0, 0))
	_enemy(Vector3(29, 0, 0))
	_run([q], DT)
	var tremor := (_effect(q, b) as GeneralWarStomp).tremor
	check(tremor != null and is_instance_valid(tremor), "Tremor Field")
	check_near(tremor.duration, 4.0, 0.001, "4 sec")
	check_near(tremor.slow_pct, 75.0, 0.001, "50% x 1.5 slow")
	check(tremor.damage_per_tick > 0.0 and tremor.stun > 0.0, "damage + stun on entry")
	_run([q], 1.0)
	check(not f.slows.is_empty(), "slowed")
	check(f.hits.size() >= 2, "tremor damage")
	q.end_wave()
	check(tremor.is_queued_for_deletion(), "end_wave ends the tremor")


# --- Spirit Wolf ------------------------------------------------------------------------------

func test_spirit_wolf_hunts_and_bites() -> void:
	for class_id: StringName in [&"warrior", &"mage"]:
		var x := 0.0 if class_id == &"warrior" else 40.0
		var p := _hero(class_id, Vector3(x, 0, 0))
		var a := _learn(p, &"spirit_wolf")
		var e := _enemy(Vector3(x, 0, -5))
		_run([p], DT)
		var effect := _effect(p, a) as GeneralSpiritWolf
		check_eq(effect.alive_count(), 1, "%s: a wolf is summoned" % class_id)
		var wolf := effect.wolves[0]
		check(wolf.model != null, "has a model")
		_run([p], 1.0)
		check(e.hits.size() >= 1, "%s: it bites" % class_id)
		if not e.hits.is_empty():
			var expected := _expected_weapon(p, &"nature") * 0.35
			check_near(e.hits[0], expected, 0.001, "35% normalised weapon damage (Nature)")
			check(e.attackers[0] == p, "kill credit to the hero")
		check(GeneralKit.flat_distance(wolf.global_position, e.global_position) < 1.2, "next to its prey")
		var bites := wolf.bites
		_run([p], 2.4)
		check_eq(wolf.bites, bites + 2, "bites every 1.2 s")
		p.queue_free()


func test_spirit_wolf_fades_and_cleans_up() -> void:
	var p := _hero(&"paladin")
	var a := _learn(p, &"spirit_wolf")
	var effect := _effect(p, a) as GeneralSpiritWolf
	_enemy(Vector3(0, 0, -30))
	check(not effect.wants_auto_cast(_ctx(p, a)), "no enemy within 8 m: no wolf")
	_enemy(Vector3(0, 0, -6))
	_run([p], DT)
	check_eq(effect.alive_count(), 1, "summoned")
	check(not effect.wants_auto_cast(_ctx(p, a)), "the pack is complete")
	_run([p], 12.0)
	check_eq(effect.alive_count(), 0, "faded after 12 s")
	p.abilities.set_cooldown(a, 0.0)
	_run([p], DECIDE)
	check_eq(effect.alive_count(), 1, "summoned again")
	p._go_down()
	_run([p], DT)
	check_eq(effect.alive_count(), 0, "gone when the hero goes down")
	p.revive()
	p.abilities.set_cooldown(a, 0.0)
	_run([p], DECIDE)
	check_eq(effect.alive_count(), 1, "back after the revive")
	p.end_wave()
	check_eq(effect.alive_count(), 0, "end_wave")
	p.abilities.set_cooldown(a, 0.0)
	_run([p], DECIDE)
	check_eq(effect.alive_count(), 1, "summoned for the forget check")
	var wolf := effect.wolves[0]
	p.abilities.forget(p.abilities.slot_of(&"spirit_wolf"))
	check(wolf.dismissed, "forget dismisses the pack")
	var q := _hero(&"rogue", Vector3(20, 0, 0), 1)
	var b := _learn(q, &"spirit_wolf")
	_enemy(Vector3(20, 0, -4))
	_run([q], DT)
	var orphan := (_effect(q, b) as GeneralSpiritWolf).wolves[0]
	q.free()
	orphan.step(DT)
	check(orphan.dismissed, "a wolf without its master frees itself")


func test_spirit_wolf_rank3_and_specs() -> void:
	var p := _hero(&"warlock")
	var a := _learn(p, &"spirit_wolf", 3)
	_enemy(Vector3(0, 0, -5))
	_run([p], DT)
	check_eq((_effect(p, a) as GeneralSpiritWolf).alive_count(), 2, "Rank III: two wolves")
	var q := _hero(&"warrior", Vector3(40, 0, 0), 1)
	var b := _learn(q, &"spirit_wolf", 5, 0)
	var e := _enemy(Vector3(40, 0, -3))
	_run([q], DT)
	check_eq((_effect(q, b) as GeneralSpiritWolf).alive_count(), 3, "Feral Pack: three wolves")
	_run([q], 1.0)
	check(not e.slows.is_empty(), "bites slow")
	if not e.slows.is_empty():
		check_near(e.slows[0], 45.0, 0.001, "30% x 1.5")
	var r := _hero(&"mage", Vector3(-40, 0, 0), 2)
	var c := _learn(r, &"spirit_wolf", 5, 1)
	r.stats.set_source(&"t_tough", {Stats.STAMINA: 100.0})
	_enemy(Vector3(-40, 0, -3))
	_hurt(r, 0.5)
	var before := r.hp
	_run([r], DT)
	var wolves := (_effect(r, c) as GeneralSpiritWolf).wolves
	check_eq(wolves.size(), 2, "Spirit Link keeps the Rank III wolves")
	_run([r], 1.0)
	var bites := 0
	for w in wolves:
		bites += w.bites
	check(bites >= 1, "bit")
	var dmg := _expected_weapon(r, &"nature") * 0.35 * 1.5
	check_near(r.hp - before, dmg * 0.3 * float(bites), 0.01, "Spirit Link heals 30% of the bites")


# --- Every class ------------------------------------------------------------------------------

func test_every_class_can_use_every_general_ability() -> void:
	var x := 0.0
	for class_id in Db.class_ids:
		var p := _hero(class_id, Vector3(x, 0, 0))
		var enemies: Array[MortalEnemy] = [_enemy(Vector3(x + 1.2, 0, 0)), _enemy(Vector3(x - 1.2, 0, 0)),
				_enemy(Vector3(x, 0, -1.5))]
		_hurt(p, 0.4)
		for id: StringName in [&"bandage", &"berserking", &"engineers_bomb", &"war_stomp", &"spirit_wolf"]:
			_learn(p, id)
		_run([p], 0.1)
		for i in 2:
			check(_cast(p, p.abilities.slots[2 + i]), "%s: %s" % [class_id, p.abilities.slots[2 + i].id])
		_run([p], 2.0)
		var hit := 0.0
		for e in enemies:
			hit += e.total()
			check(not e.stuns.is_empty(), "%s: War Stomp stuns" % class_id)
		check(hit > 0.0, "%s: damage dealt" % class_id)
		check(p.stats.has_source(GeneralBerserking.KEY), "%s: berserking" % class_id)
		check(p.hp > p.max_hp() * 0.4, "%s: bandaged" % class_id)
		p.end_wave()
		check(not p.stats.has_source(GeneralBerserking.KEY), "%s: cleaned up" % class_id)
		check_eq((p.abilities.effect_for(_ability(&"spirit_wolf")) as GeneralSpiritWolf).alive_count(), 0,
				"%s: no wolves after the wave" % class_id)
		x += 30.0
