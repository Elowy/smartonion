extends TestCase
## Warrior M4 abilities (GDD 6.4): Thunder Clap, Heroic Leap, Execute, Battle Shout, Shield
## Wall, Bladestorm – data, casting, power (Rank II / IV), Rank III, both Rank V
## specialisations, auto-cast / bot rules and cleanup (down, wave end, forget, freed) – plus
## the ranks of the core abilities Whirlwind and Charge.

const Fakes := preload("res://tests/player_fakes.gd")
const EFakes := preload("res://tests/enemies_fakes.gd")
const DT := 1.0 / 60.0

const LEARNED: Array[StringName] = [&"thunder_clap", &"heroic_leap", &"execute", &"battle_shout",
		&"shield_wall", &"bladestorm"]
const CORE: Array[StringName] = [&"whirlwind", &"charge"]


## A fake enemy that is an elite (Execute, bot rules).
class EliteFake extends Fakes.FakeEnemy:
	func is_elite() -> bool:
		return true


## A fake elite whose Shielding barrier soaks damage first, the way Enemy.take_damage does.
class ShieldingFake extends EliteFake:
	func take_damage(amount: float, is_crit: bool = false, attacker: Node3D = null,
			knockback: Vector3 = Vector3.ZERO) -> void:
		super(_absorb(amount), is_crit, attacker, knockback)


## A fake boss (an elite that Execute never kills outright).
class BossFake extends EliteFake:
	func is_boss() -> bool:
		return true


var world: Node3D
var arena: EFakes.TestArena


func before_each() -> void:
	PlayerManager.clear()
	RunState.start_run(1, 4711)
	Enemy.invalidate_player_cache()
	world = Fakes.make_world(tree)


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	arena = null
	PlayerManager.clear()
	Enemy.invalidate_player_cache()
	EnemyGrid.mark_dirty()


# --- Helpers ------------------------------------------------------------------------------

func _hero(pos: Vector3 = Vector3.ZERO, index: int = 0) -> Player:
	var p := Fakes.spawn_player(world, index, &"warrior", pos)
	p.stats.set_source(&"tough", {Stats.STAMINA: 500.0})
	p.hp = p.max_hp()
	return p


func _arena() -> void:
	arena = EFakes.TestArena.new()
	world.add_child(arena)


func _fake(pos: Vector3, hp: float = 1000.0) -> Fakes.FakeEnemy:
	var e := Fakes.spawn_enemy(world, pos)
	e.max_hp = 1000.0
	e.hp = hp
	EnemyGrid.mark_dirty()
	return e


func _elite(pos: Vector3, hp: float = 1000.0) -> EliteFake:
	return _place(EliteFake.new(), pos, hp)


func _boss(pos: Vector3, hp: float = 1000.0) -> BossFake:
	return _place(BossFake.new(), pos, hp) as BossFake


func _place(e: EliteFake, pos: Vector3, hp: float) -> EliteFake:
	e.add_to_group(&"enemies")
	world.add_child(e)
	e.global_position = pos
	e.max_hp = 1000.0
	e.hp = hp
	EnemyGrid.mark_dirty()
	return e


func _real(pos: Vector3) -> Enemy:
	var e := Enemy.create(Db.get_enemy(&"skeleton_grunt"), 1)
	world.add_child(e)
	e.global_position = pos
	EnemyGrid.mark_dirty()
	return e


## Learns [param id] and brings it to [param rank] (with Rank V specialisation [param spec]).
func _learn(p: Player, id: StringName, rank: int = 1, spec: int = -1) -> int:
	var slot := p.abilities.learn(Db.get_ability(id))
	check(slot >= 0, "%s can be learned" % id)
	_rank(p, id, rank, spec)
	return slot


func _rank(p: Player, id: StringName, rank: int, spec: int = -1) -> void:
	while p.abilities.rank_of(id) < rank:
		check(p.abilities.rank_up(id), "%s ranks up" % id)
	if spec >= 0:
		check(p.abilities.set_spec(id, spec), "%s takes spec %d" % [id, spec])


func _effect(p: Player, slot: int) -> AbilityEffect:
	return p.abilities.effect_for(p.abilities.slots[slot])


func _ctx(p: Player, slot: int) -> AbilityContext:
	return p.abilities.build_context(p.abilities.slots[slot])


func _wants(p: Player, slot: int) -> bool:
	EnemyGrid.mark_dirty()
	var ctx := _ctx(p, slot)
	var effect := _effect(p, slot)
	return effect.can_cast(ctx) and effect.wants_auto_cast(ctx)


func _step(p: Player, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		p.abilities._physics_process(DT)
		t += DT


func _hit(p: Player) -> float:
	return CombatMath.weapon_hit_damage(p.main_hand, p.stats)


func _total(e: Fakes.FakeEnemy) -> float:
	var sum := 0.0
	for d in e.fake_damage_log:
		sum += d
	return sum


func _rage(p: Player) -> ClassResource:
	return p.abilities.get_resource(&"rage")


## The base params of an ability plus the runner's implicit ones.
static func _known_params(a: AbilityData) -> Dictionary:
	var out := {"cooldown": a.cooldown, "cost": a.cost, "charges": 1, "power": 1.0}
	out.merge(a.params, true)
	return out


## The param a mod key changes (AbilityRunner.apply_mods: "<p>_add" -> p; "<p>_pct" -> p when
## p is a param, else the key itself; anything else itself).
static func _mod_target(key: String, value: Variant, params: Dictionary) -> String:
	if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
		if key.ends_with("_add"):
			return key.trim_suffix("_add")
		if key.ends_with("_pct") and params.has(key.trim_suffix("_pct")):
			return key.trim_suffix("_pct")
	return key


# --- Data ---------------------------------------------------------------------------------

func test_learned_abilities_are_wired() -> void:
	var kinds := {
		&"thunder_clap": AbilityData.Kind.AUTO, &"heroic_leap": AbilityData.Kind.ACTIVE,
		&"execute": AbilityData.Kind.ACTIVE, &"battle_shout": AbilityData.Kind.AUTO,
		&"shield_wall": AbilityData.Kind.ACTIVE, &"bladestorm": AbilityData.Kind.AUTO,
	}
	var effects := {
		&"thunder_clap": WarriorThunderClap, &"heroic_leap": WarriorHeroicLeap,
		&"execute": WarriorExecute, &"battle_shout": WarriorBattleShout,
		&"shield_wall": WarriorShieldWall, &"bladestorm": WarriorBladestorm,
	}
	var pool := Db.ability_pool(&"warrior")
	for id in LEARNED:
		var a := Db.get_ability(id)
		check(a != null, "%s exists" % id)
		if a == null:
			continue
		check_eq(a.class_id, &"warrior", "%s: Warrior" % id)
		check_eq(a.kind, kinds[id], "%s kind" % id)
		check(a.effect == effects[id], "%s effect script" % id)
		check_eq(a.icon, id, "%s icon id" % id)
		check_eq(a.resource, &"", "%s is free" % id)
		check(a.cooldown >= 4.0 and a.cooldown <= 30.0, "%s cooldown %s" % [id, a.cooldown])
		check(a.card_weight > 0.0, "%s is offered on cards" % id)
		check(a in pool, "%s in the Warrior pool" % id)
		check(not a.display_name.is_empty(), "%s name" % id)
	for id in CORE:
		var c := Db.get_ability(id)
		check_eq(c.kind, AbilityData.Kind.CORE, "%s is core" % id)
		check(c not in pool, "%s is not offered" % id)
	for a in pool:
		if a.class_id == &"warrior":
			check(a.id in LEARNED, "no stray Warrior ability %s" % a.id)


func test_descriptions_ranks_and_specs_resolve() -> void:
	var placeholder := RegEx.create_from_string("\\{([a-z_]+)\\}")
	for id in LEARNED + CORE:
		var a := Db.get_ability(id)
		var known := _known_params(a)
		for m in placeholder.search_all(a.description):
			check(known.has(m.get_string(1)), "%s description: {%s} is a param" % [id, m.get_string(1)])
		check(not a.rank3.is_empty(), "%s has a Rank III effect" % id)
		check(not a.rank3_text.is_empty() and not a.rank3_text.contains("{"), "%s Rank III text" % id)
		for key: String in a.rank3:
			check(known.has(_mod_target(key, a.rank3[key], known)), "%s rank3 %s targets a param" % [id, key])
		check_eq(a.specs.size(), 2, "%s has two specialisations" % id)
		var names := {}
		for spec in a.specs:
			var spec_name := String(spec.get("name", ""))
			check(not spec_name.is_empty(), "%s spec name" % id)
			names[spec_name] = true
			check(not String(spec.get("text", "")).is_empty(), "%s spec %s text" % [id, spec_name])
			var mods: Dictionary = spec.get("mods", {})
			check(not mods.is_empty(), "%s spec %s mods" % [id, spec_name])
			for key: String in mods:
				check(known.has(_mod_target(key, mods[key], known)), "%s spec %s: %s targets a param" % [id, spec_name, key])
		check_eq(names.size(), 2, "%s: two different specs" % id)


## Every Rank III / Rank V mod really changes the param it is meant for (runner.params_at_rank:
## the same path the effects read), and nothing else besides power / cooldown.
func test_rank_and_spec_mods_change_their_params() -> void:
	var p := _hero()
	var runner := p.abilities
	for id in LEARNED + CORE:
		var a := Db.get_ability(id)
		var known := _known_params(a)
		var r2 := runner.params_at_rank(a, 2)
		var r3 := runner.params_at_rank(a, 3)
		for key: String in a.rank3:
			var target := _mod_target(key, a.rank3[key], known)
			check(r3.get(target) != r2.get(target), "%s Rank III changes %s (%s -> %s)" % [id, target, r2.get(target), r3.get(target)])
		for k: String in r3:
			if k not in ["power", "cooldown"] and r3[k] != r2.get(k):
				check(a.rank3.keys().any(func(m: String) -> bool: return _mod_target(m, a.rank3[m], known) == k),
						"%s Rank III changes only its own params (%s)" % [id, k])
		var r5 := runner.params_at_rank(a, 5)
		for i in a.specs.size():
			var mods: Dictionary = a.specs[i].get("mods", {})
			var spec := runner.params_at_rank(a, 5, i)
			for key: String in mods:
				var target := _mod_target(key, mods[key], known)
				check(spec.get(target) != r5.get(target), "%s spec %d changes %s (%s -> %s)" % [id, i, target, r5.get(target), spec.get(target)])
			for k: String in spec:
				if spec[k] != r5.get(k):
					check(mods.keys().any(func(m: String) -> bool: return _mod_target(m, mods[m], known) == k),
							"%s spec %d changes only its own params (%s)" % [id, i, k])
	check_near(float(runner.params_at_rank(Db.get_ability(&"heroic_leap"), 5, 1)["radius"]), 4.5, 0.001,
			"Shockwave: radius_pct scales the radius")
	check_near(float(runner.params_at_rank(Db.get_ability(&"execute"), 3)["threshold"]), 30.0, 0.001,
			"Execute Rank III: 30% threshold")


func test_every_learned_ability_casts() -> void:
	_arena()
	for id in LEARNED:
		var p := _hero(Vector3.ZERO)
		var e := _fake(Vector3(1.5, 0.0, 0.0))
		_fake(Vector3(2.0, 0.0, 1.0))
		_fake(Vector3(1.0, 0.0, -1.5))
		var slot := _learn(p, id)
		check(p.abilities.try_cast(slot), "%s casts" % id)
		check(p.abilities.remaining(slot) > 0.0, "%s goes on cooldown" % id)
		_step(p, 0.8)
		if id != &"battle_shout" and id != &"shield_wall":
			check(e.fake_hits() > 0, "%s hurts the enemy next to the hero" % id)
		p.free()
		for c in world.get_children():
			if c is Fakes.FakeEnemy:
				c.free()


# --- Thunder Clap -------------------------------------------------------------------------

func test_thunder_clap_strikes_and_slows_around_the_hero() -> void:
	var p := _hero()
	var near := [_fake(Vector3(2.0, 0.0, 0.0)), _fake(Vector3(-1.0, 0.0, 2.5))]
	var far := _fake(Vector3(6.0, 0.0, 0.0))
	var slot := _learn(p, &"thunder_clap")
	check(slot in AbilityRunner.AUTO_SLOTS, "an auto-cast slot")
	check(p.abilities.try_cast(slot), "cast")
	for e: Fakes.FakeEnemy in near:
		check_eq(e.fake_hits(), 1, "hit once")
		check_near(e.fake_damage_log[0], _hit(p) * 1.0, 0.01, "100% weapon damage")
		check_near(e.slow_pct, 50.0, 0.001, "slowed by 50%")
		check_near(e.slow_left, 2.0, 0.001, "for 2 sec")
	check_eq(far.fake_hits(), 0, "out of reach")
	check_near(p.abilities.remaining(slot), 6.0, 0.001, "6 s cooldown")
	var clap := false
	for c in world.get_children():
		clap = clap or c is WarriorClapVfx
	check(clap, "the clap is drawn")


func test_thunder_clap_power_and_rank_three() -> void:
	var p := _hero()
	var e := _fake(Vector3(2.0, 0.0, 0.0))
	var edge := _fake(Vector3(4.6, 0.0, 0.0))  # 4.6 - 0.45 < 4.5
	var slot := _learn(p, &"thunder_clap", 2)
	check(p.abilities.try_cast(slot), "cast at Rank II")
	check_near(e.fake_damage_log[0], _hit(p) * 1.25, 0.01, "Rank II: +25% damage")
	check_near(p.abilities.remaining(slot), 5.4, 0.001, "Rank II: -10% cooldown")
	check_eq(edge.fake_hits(), 0, "Rank II: 3.5 m reach")
	_rank(p, &"thunder_clap", 3)
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	check(p.abilities.try_cast(slot), "cast at Rank III")
	check_eq(edge.fake_hits(), 1, "Rank III: +1 m radius")
	check_near(edge.slow_left, 3.0, 0.001, "Rank III: the slow lasts 3 sec")


func test_thunder_clap_aftershock_echoes() -> void:
	var p := _hero()
	var e := _fake(Vector3(2.0, 0.0, 0.0))
	var slot := _learn(p, &"thunder_clap", 5, 0)
	var clap := _effect(p, slot) as WarriorThunderClap
	check(p.abilities.try_cast(slot), "cast")
	var first := e.fake_damage_log[0]
	check_near(first, _hit(p) * 1.5, 0.01, "Rank V power")
	check_eq(clap.echoes_pending(), 2, "two echoes to come")
	_step(p, 0.5)
	check_eq(e.fake_hits(), 1, "not yet")
	_step(p, 0.2)
	check_eq(e.fake_hits(), 2, "first echo after 0.6 s")
	_step(p, 0.6)
	check_eq(e.fake_hits(), 3, "second echo")
	check_near(e.fake_damage_log[1], first * 0.5, 0.01, "echoes deal half")
	check_eq(clap.echoes_pending(), 0, "done")


func test_thunder_clap_booming_voice_feeds_rage() -> void:
	var p := _hero()
	for i in 3:
		_fake(Vector3(1.0 + 0.5 * i, 0.0, 0.5))
	var slot := _learn(p, &"thunder_clap", 5, 1)
	check(p.abilities.try_cast(slot), "cast")
	check_near(_rage(p).value, 18.0, 0.01, "6 Rage per enemy hit")
	check_eq((_effect(p, slot) as WarriorThunderClap).echoes_pending(), 0, "no echoes with this spec")
	for i in 5:
		_fake(Vector3(-1.0 - 0.4 * i, 0.0, -0.5))
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_rage(p).set_value(0.0)
	check(p.abilities.try_cast(slot), "cast again")
	check_near(_rage(p).value, 30.0, 0.01, "at most 30 Rage per clap")


func test_thunder_clap_auto_rule() -> void:
	var p := _hero()
	var slot := _learn(p, &"thunder_clap")
	check(not _wants(p, slot), "nobody around")
	var lone := _fake(Vector3(2.0, 0.0, 0.0))
	check(_wants(p, slot), "a lone straggler is worth it")
	var coming := _fake(Vector3(5.5, 0.0, 0.0))
	check(not _wants(p, slot), "wait for the second one closing in")
	coming.global_position = Vector3(-2.0, 0.0, 1.0)
	check(_wants(p, slot), "two in reach")
	lone.global_position = Vector3(20.0, 0.0, 0.0)
	coming.global_position = Vector3(20.0, 0.0, 2.0)
	check(not _wants(p, slot), "both far away")
	coming.global_position = Vector3(0.0, 0.0, 2.0)
	lone.global_position = Vector3(1.0, 0.0, -1.0)
	EnemyGrid.mark_dirty()
	_step(p, 0.3)
	check_eq(lone.fake_hits(), 1, "an auto-cast slot fires by itself for a human too")
	check(p.abilities.remaining(slot) > 5.0, "and goes on cooldown")


func test_thunder_clap_echoes_end_on_down_wave_end_and_forget() -> void:
	var p := _hero()
	var e := _fake(Vector3(2.0, 0.0, 0.0))
	var slot := _learn(p, &"thunder_clap", 5, 0)
	var clap := _effect(p, slot) as WarriorThunderClap
	p.abilities.try_cast(slot)
	p.downed_changed.emit(true)
	check_eq(clap.echoes_pending(), 0, "going down cancels the echoes")
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	p.abilities.try_cast(slot)
	p.end_wave()
	check_eq(clap.echoes_pending(), 0, "wave end cancels them")
	p.abilities.begin_wave()
	p.abilities.try_cast(slot)
	check_eq(clap.echoes_pending(), 2, "echoing again")
	p.abilities.forget(slot)
	check_eq(clap.echoes_pending(), 0, "forgetting cancels them")
	var hits := e.fake_hits()
	_step(p, 1.5)
	check_eq(e.fake_hits(), hits, "no more claps")


# --- Heroic Leap --------------------------------------------------------------------------

func _yaw_height(p: Player) -> float:
	var yaw := p.model.get_node_or_null("Yaw") as Node3D
	return yaw.position.y if yaw != null else 0.0


func test_heroic_leap_flies_onto_the_group_and_slams() -> void:
	_arena()
	var p := _hero()
	var group := [_fake(Vector3(7.0, 0.0, 0.0)), _fake(Vector3(7.5, 0.0, 1.0)), _fake(Vector3(6.5, 0.0, -1.0))]
	var lone := _fake(Vector3(-3.0, 0.0, 0.0))
	var slot := _learn(p, &"heroic_leap")
	check(slot in AbilityRunner.ACTIVE_SLOTS, "a button slot")
	var leap := _effect(p, slot) as WarriorHeroicLeap
	check(p.abilities.try_cast(slot), "cast")
	check(leap.is_flying(), "in the air")
	check(p.invulnerable_left > 0.3, "cannot be hurt in the air")
	check_near(p.abilities.remaining(slot), 12.0, 0.001, "12 s cooldown")
	var target := leap.landing_point()
	check(target.distance_to(Vector3(7.0, 0.0, 0.0)) < 1.2, "lands on the group, not on the lone enemy")
	_step(p, 0.2)
	check(p.global_position.x > 1.0 and p.global_position.x < target.x - 0.5, "flying over, not teleporting")
	check(_yaw_height(p) > 0.5, "the model is high up")
	for e: Fakes.FakeEnemy in group:
		check_eq(e.fake_hits(), 0, "nothing hit before landing")
	_step(p, 0.6)
	check(not leap.is_flying(), "landed")
	check(p.global_position.distance_to(target) < 0.01, "at the landing point")
	check_near(_yaw_height(p), 0.0, 0.001, "back on the ground")
	for e: Fakes.FakeEnemy in group:
		check_eq(e.fake_hits(), 1, "the impact hits")
		check_near(e.fake_damage_log[0], _hit(p) * 2.0, 0.01, "200% weapon damage")
		check_eq(e.fake_stun_count, 0, "Rank I does not stun")
	check_eq(lone.fake_hits(), 0, "far from the impact")


func test_heroic_leap_without_a_target_is_refunded() -> void:
	var p := _hero()
	var slot := _learn(p, &"heroic_leap")
	_fake(Vector3(15.0, 0.0, 0.0))
	check(not p.abilities.try_cast(slot), "nothing within 10 m")
	check_eq(p.abilities.remaining(slot), 0.0, "no cooldown")


func test_heroic_leap_power_and_rank_three_stun() -> void:
	var p := _hero()
	var e := _fake(Vector3(5.0, 0.0, 0.0))
	var slot := _learn(p, &"heroic_leap", 2)
	p.abilities.try_cast(slot)
	_step(p, 0.8)
	check_near(e.fake_damage_log[0], _hit(p) * 2.5, 0.01, "Rank II: +25%")
	check_eq(e.fake_stun_count, 0, "no stun before Rank III")
	_rank(p, &"heroic_leap", 3)
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	p.global_position = Vector3(-3.0, 0.0, 0.0)
	check(p.abilities.try_cast(slot), "leap again")
	_step(p, 0.8)
	check_eq(e.fake_stun_count, 1, "Rank III: the impact stuns")
	check_near(_ctx(p, slot).num("stun"), 1.0, 0.001, "for 1 sec")


func test_heroic_leap_crater_slows_and_burns() -> void:
	var p := _hero()
	var e := _fake(Vector3(5.0, 0.0, 0.0))
	var slot := _learn(p, &"heroic_leap", 5, 0)
	var leap := _effect(p, slot) as WarriorHeroicLeap
	p.abilities.try_cast(slot)
	_step(p, 0.8)
	var crater := leap.last_crater
	check(crater != null and is_instance_valid(crater), "a crater is left behind")
	if crater != null and is_instance_valid(crater):
		check(crater.is_in_group(&"ability_areas"), "freed with the wave like other areas")
		check_near(crater.slow_pct, 50.0, 0.001, "slows by 50%")
		check_near(crater.duration, 3.0, 0.001, "for 3 sec")
		check_near(crater.damage_per_tick, _hit(p) * 0.4 * 1.5 * 0.5, 0.01, "40% per second (x power) in 0.5 s ticks")
		check(crater.global_position.distance_to(leap.landing_point()) < 0.01, "where the hero landed")
	check_eq(e.fake_hits(), 1, "the impact itself")


func test_heroic_leap_shockwave_hurls_enemies_away() -> void:
	var p := _hero()
	var e := _fake(Vector3(5.0, 0.0, 0.0))
	var side := _fake(Vector3(5.0, 0.0, 4.4))  # beyond 3 m of the impact, inside 4.5 m
	var slot := _learn(p, &"heroic_leap", 5, 1)
	check_near(_ctx(p, slot).num("radius"), 4.5, 0.001, "50% wider")
	var leap := _effect(p, slot) as WarriorHeroicLeap
	p.abilities.try_cast(slot)
	_step(p, 0.8)
	var land := leap.landing_point()
	check_eq(side.fake_hits(), 1, "the wider impact reaches it")
	var away := Vector3(side.global_position.x - land.x, 0.0, side.global_position.z - land.z).normalized()
	check(side.knockback_velocity.length() > 1.0, "pushed")
	check(side.knockback_velocity.normalized().dot(away) > 0.9, "away from the impact")
	check(e.fake_hits() == 1, "the target is hit too")


func test_heroic_leap_lands_inside_the_arena() -> void:
	_arena()
	var limit := arena.get_bounds().end.x - (Player.RADIUS + Player.WALL_GAP)
	var p := _hero(Vector3(arena.get_bounds().end.x - 8.0, 0.0, 0.0))
	_fake(Vector3(arena.get_bounds().end.x - 0.1, 0.0, 0.0))
	var slot := _learn(p, &"heroic_leap")
	check(p.abilities.try_cast(slot), "cast")
	_step(p, 0.8)
	check(p.global_position.x <= limit + 0.001, "not beyond the wall")
	check(arena.is_inside(p.global_position), "inside the arena")


func test_heroic_leap_bot_rule() -> void:
	var p := _hero()
	var slot := _learn(p, &"heroic_leap")
	check(not _wants(p, slot), "no target")
	_fake(Vector3(6.0, 0.0, 0.0))
	_fake(Vector3(6.5, 0.0, 1.0))
	check(not _wants(p, slot), "two enemies are not worth a leap")
	_fake(Vector3(5.5, 0.0, -1.0))
	check(_wants(p, slot), "a group of three is")
	p.hp = p.max_hp() * 0.2
	check(not _wants(p, slot), "not when badly hurt")
	p.hp = p.max_hp()
	var mate := Fakes.spawn_player(world, 1, &"mage", Vector3(-1.0, 0.0, 0.5))
	mate._go_down()
	check(not _wants(p, slot), "not while reviving")
	mate.free()
	for c in world.get_children():
		if c is Fakes.FakeEnemy:
			c.free()
	_elite(Vector3(4.0, 0.0, 0.0))
	check(_wants(p, slot), "an elite alone is worth it")


func test_heroic_leap_aborts_on_down_wave_end_and_forget() -> void:
	var p := _hero()
	_fake(Vector3(8.0, 0.0, 0.0))
	var slot := _learn(p, &"heroic_leap")
	var leap := _effect(p, slot) as WarriorHeroicLeap
	p.abilities.try_cast(slot)
	_step(p, 0.15)
	check(_yaw_height(p) > 0.1, "airborne")
	p.downed_changed.emit(true)
	check(not leap.is_flying(), "going down ends the leap")
	check_near(_yaw_height(p), 0.0, 0.001, "model back on the ground")
	var x := p.global_position.x
	_step(p, 0.5)
	check_near(p.global_position.x, x, 0.001, "no more movement")
	p.abilities.begin_wave()
	p.abilities.try_cast(slot)
	_step(p, 0.15)
	p.end_wave()
	check(not leap.is_flying() and is_zero_approx(_yaw_height(p)), "wave end lands the hero")
	p.abilities.begin_wave()
	p.abilities.try_cast(slot)
	_step(p, 0.15)
	p.abilities.forget(slot)
	check(not leap.is_flying() and is_zero_approx(_yaw_height(p)), "forgetting lands the hero")


# --- Execute ------------------------------------------------------------------------------

func test_execute_is_a_huge_strike() -> void:
	var p := _hero()
	var e := _fake(Vector3(2.0, 0.0, 0.0))
	var slot := _learn(p, &"execute")
	check(slot in AbilityRunner.ACTIVE_SLOTS, "a button slot")
	check(p.abilities.try_cast(slot), "cast")
	check_eq(e.fake_hits(), 1, "one strike")
	check_near(e.fake_damage_log[0], _hit(p) * 3.0, 0.01, "300% weapon damage")
	check_near(p.abilities.remaining(slot), 8.0, 0.001, "8 s cooldown")
	check(e.fake_attacker_log[0] == p, "credited to the hero")


func test_execute_kills_below_twenty_percent() -> void:
	var p := _hero()
	var e := _fake(Vector3(2.0, 0.0, 0.0), 190.0)
	var slot := _learn(p, &"execute")
	var ex := _effect(p, slot) as WarriorExecute
	check(p.abilities.try_cast(slot), "cast")
	check(e.hp <= 0.0, "dead: %s HP left" % e.hp)
	check_eq(ex.last_executed, 1, "an execution")
	var p2 := _hero(Vector3(0.0, 0.0, 20.0), 1)
	var healthy := _fake(Vector3(2.0, 0.0, 20.0), 210.0)
	var slot2 := _learn(p2, &"execute")
	p2.abilities.try_cast(slot2)
	check_near(_total(healthy), _hit(p2) * 3.0, 0.01, "21% HP: only the strike")
	check(healthy.hp > 0.0, "survives")


func test_execute_prefers_the_enemy_it_can_execute() -> void:
	var p := _hero()
	var near := _fake(Vector3(1.0, 0.0, 0.0))
	var low := _fake(Vector3(-3.0, 0.0, 0.0), 120.0)
	var slot := _learn(p, &"execute")
	p.abilities.try_cast(slot)
	check_eq(near.fake_hits(), 0, "the healthy nearest one is spared")
	check(low.hp <= 0.0, "the low one is executed")


func test_execute_bosses_take_double_damage_instead() -> void:
	var p := _hero()
	var boss := _boss(Vector3(2.0, 0.0, 0.0), 150.0)
	var slot := _learn(p, &"execute")
	var ex := _effect(p, slot) as WarriorExecute
	check(p.abilities.try_cast(slot), "cast")
	check_near(boss.fake_damage_log[0], _hit(p) * 3.0 * 2.0, 0.01, "double damage below the threshold")
	check(boss.hp > 0.0, "a boss is never killed outright")
	check_eq(ex.last_executed, 0, "no execution")
	boss.hp = 900.0
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	p.abilities.try_cast(slot)
	check_near(boss.fake_damage_log[1], _hit(p) * 3.0, 0.01, "normal damage above it")
	var text := AbilityIcon.format_description(Db.get_ability(&"execute"), _ctx(p, slot).params)
	check("bosses take 2x" in text and not "elite" in text, "the text names bosses only: %s" % text)


func test_execute_kills_elites_below_the_threshold() -> void:
	var p := _hero()
	var elite := _elite(Vector3(2.0, 0.0, 0.0), 150.0)
	var slot := _learn(p, &"execute")
	var ex := _effect(p, slot) as WarriorExecute
	check(WarriorExecute.is_executable(elite, 20.0), "an elite below 20% is executable")
	check(p.abilities.try_cast(slot), "cast")
	check(elite.hp <= 0.0, "an elite dies outright: %s HP left" % elite.hp)
	check_eq(ex.last_executed, 1, "an execution")
	var p2 := _hero(Vector3(0.0, 0.0, 20.0), 1)
	_elite(Vector3(2.0, 0.0, 20.0), 900.0)
	var low := _fake(Vector3(-2.0, 0.0, 20.0), 150.0)
	var boss := _boss(Vector3(0.0, 0.0, 22.0), 100.0)
	check(not WarriorExecute.is_executable(boss, 20.0), "a boss below 20% is not")
	check(WarriorExecute.pick_victim(p2, 3.5, 20.0) == low, "an executable enemy goes first")
	low.hp = 900.0
	check(WarriorExecute.pick_victim(p2, 3.5, 20.0) == boss, "then the elite / boss with the lowest HP share")


func test_execute_goes_through_a_shielding_elites_barrier() -> void:
	var p := _hero()
	var elite := _place(ShieldingFake.new(), Vector3(2.0, 0.0, 0.0), 150.0)
	elite.shield_hp = elite.max_hp * EliteAffixes.SHIELD_PCT
	var slot := _learn(p, &"execute")
	check(p.abilities.try_cast(slot), "cast")
	check(elite.hp <= 0.0, "executed despite the barrier: %s HP, %s shield left" % [elite.hp, elite.shield_hp])


func test_execute_power_and_rank_three_threshold() -> void:
	var p := _hero()
	var e := _fake(Vector3(2.0, 0.0, 0.0), 250.0)
	var slot := _learn(p, &"execute", 2)
	p.abilities.try_cast(slot)
	check_near(e.fake_damage_log[0], _hit(p) * 3.75, 0.01, "Rank II: +25%")
	check(e.hp > 0.0, "25% HP is not executable at Rank II")
	_rank(p, &"execute", 3)
	e.hp = 250.0
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	p.abilities.try_cast(slot)
	check(e.hp <= 0.0, "Rank III executes below 30%")


func test_execute_sweeping_strikes_hits_the_arc() -> void:
	var p := _hero()
	var main := _fake(Vector3(2.0, 0.0, 0.0))
	var side := _fake(Vector3(1.5, 0.0, 0.8))
	var behind := _fake(Vector3(-2.0, 0.0, 0.0))
	var low := _fake(Vector3(2.0, 0.0, -1.2), 100.0)
	var slot := _learn(p, &"execute", 5, 0)
	var ex := _effect(p, slot) as WarriorExecute
	check(p.abilities.try_cast(slot), "cast")
	check(low.hp <= 0.0, "the executable one is the main target")
	check_eq(main.fake_hits(), 1, "in front: struck")
	check_eq(side.fake_hits(), 1, "to the side: struck")
	check_eq(behind.fake_hits(), 0, "behind: spared")
	check_eq(ex.last_struck, 3, "three strikes")
	check_near(main.fake_damage_log[0], _hit(p) * 3.0 * 1.5, 0.01, "each a full Rank V strike")


func test_execute_massacre_resets_on_a_kill() -> void:
	var p := _hero()
	var low := _fake(Vector3(2.0, 0.0, 0.0), 100.0)
	var slot := _learn(p, &"execute", 5, 1)
	p.abilities.try_cast(slot)
	check(low.hp <= 0.0, "killed")
	low.fake_dead = true
	_step(p, DT)
	check(p.abilities.remaining(slot) <= 1.0 + 0.001, "back in a second: %s" % p.abilities.remaining(slot))
	check(p.abilities.remaining(slot) > 0.9, "but not at once")
	_step(p, 1.05)
	var e := _fake(Vector3(-2.0, 0.0, 0.0))
	check(p.abilities.try_cast(slot), "ready again")
	_step(p, DT)
	check(p.abilities.remaining(slot) > 6.0, "no kill: the full cooldown (%s)" % p.abilities.remaining(slot))
	check(e.hp > 0.0, "(it survived)")


func test_execute_bot_rule_and_refund() -> void:
	var p := _hero()
	var slot := _learn(p, &"execute")
	check(not _wants(p, slot), "nobody in reach")
	check(not p.abilities.try_cast(slot), "no strike into thin air")
	check_eq(p.abilities.remaining(slot), 0.0, "refunded")
	var scrap := _fake(Vector3(2.0, 0.0, 0.0), 1.0)
	scrap.max_hp = 1.0
	check(not _wants(p, slot), "not worth it on a 1 HP scrap")
	scrap.max_hp = 1000.0
	scrap.hp = 900.0
	check(_wants(p, slot), "a healthy enemy is")
	scrap.hp = _hit(p) * 3.0 * 0.5
	check(_wants(p, slot), "an executable enemy with HP left is")
	scrap.free()
	var boss := _elite(Vector3(2.0, 0.0, 0.0), 1.0)
	boss.max_hp = 1.0
	check(_wants(p, slot), "elites are always worth it")


# --- Battle Shout -------------------------------------------------------------------------

func test_battle_shout_buffs_the_hero_and_nearby_allies() -> void:
	var p := _hero()
	var near := Fakes.spawn_player(world, 1, &"mage", Vector3(6.0, 0.0, 0.0))
	var far := Fakes.spawn_player(world, 2, &"rogue", Vector3(15.0, 0.0, 0.0))
	var slot := _learn(p, &"battle_shout")
	var shout := _effect(p, slot) as WarriorBattleShout
	var key := WarriorBattleShout.buff_key(p)
	check(p.abilities.try_cast(slot), "cast")
	check_near(p.outgoing_damage_mult(null, &"physical", &"weapon"), 1.1, 0.0001, "+10% for the Warrior")
	check_near(near.damage_mults.get(key, 1.0), 1.1, 0.0001, "+10% for an ally in reach")
	check(not far.damage_mults.has(key), "an ally 15 m away gets nothing")
	check_eq(shout.affected().size(), 2, "two heroes buffed")
	check(p.get_node_or_null("BattleShoutMark") != null, "the buff shows under the hero")
	check(near.get_node_or_null("BattleShoutMark") != null, "and under the ally")
	check_near(p.abilities.remaining(slot), 15.0, 0.001, "15 s cooldown")
	_step(p, 5.9)
	check(near.damage_mults.has(key), "still on")
	_step(p, 0.2)
	check(not near.damage_mults.has(key) and not p.damage_mults.has(key), "gone after 6 s")
	check(not shout.is_active(), "over")
	var mark := p.get_node_or_null("BattleShoutMark") as WarriorShoutVfx
	check(mark == null or mark.is_dismissed(), "the mark fades")


func test_battle_shout_power_and_rank_three() -> void:
	var p := _hero()
	var slot := _learn(p, &"battle_shout", 3)
	var key := WarriorBattleShout.buff_key(p)
	p.abilities.try_cast(slot)
	check_near(p.damage_mults[key], 1.125, 0.0001, "Rank II: +12.5%")
	_step(p, 8.9)
	check(p.damage_mults.has(key), "Rank III: lasts 9 sec")
	_step(p, 0.2)
	check(not p.damage_mults.has(key), "and ends")


func test_battle_shout_commanding_shout_guards() -> void:
	var p := _hero()
	var mate := Fakes.spawn_player(world, 1, &"mage", Vector3(3.0, 0.0, 0.0))
	var slot := _learn(p, &"battle_shout", 5, 0)
	var key := WarriorBattleShout.buff_key(p)
	p.abilities.try_cast(slot)
	check_near(p.damage_mults[key], 1.15, 0.0001, "Rank V: +15% damage")
	check_near(mate.damage_taken_mults[key], 1.0 - 0.225, 0.0001, "allies take 22.5% less damage (15% x power)")
	check_near(p.damage_taken_mults[key], 0.775, 0.0001, "the Warrior too")
	p.end_wave()
	check(not mate.damage_taken_mults.has(key) and not mate.damage_mults.has(key), "wave end clears both")


func test_battle_shout_intimidating_shout_fears() -> void:
	_arena()
	var p := _hero()
	var close := _real(Vector3(4.0, 0.0, 0.0))
	var far := _real(Vector3(9.0, 0.0, 0.0))
	var slot := _learn(p, &"battle_shout", 5, 1)
	p.abilities.try_cast(slot)
	check(close.is_feared(), "enemies within 6 m flee")
	check_near(close.fear_left, 2.0, 0.001, "for 2 sec")
	check(not far.is_feared(), "beyond 6 m: no fear")


func test_battle_shout_auto_rule() -> void:
	var p := _hero()
	var slot := _learn(p, &"battle_shout")
	check(not _wants(p, slot), "no enemy: no shout")
	var e := _fake(Vector3(12.0, 0.0, 0.0))
	check(not _wants(p, slot), "enemy far away")
	e.global_position = Vector3(5.0, 0.0, 0.0)
	check(_wants(p, slot), "a fight is on")
	_step(p, 0.3)
	check((_effect(p, slot) as WarriorBattleShout).is_active(), "it shouted by itself")
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	check(not _wants(p, slot), "not while its own buff runs")


func test_battle_shout_cleanup() -> void:
	var p := _hero()
	var mate := Fakes.spawn_player(world, 1, &"mage", Vector3(3.0, 0.0, 0.0))
	var slot := _learn(p, &"battle_shout")
	var key := WarriorBattleShout.buff_key(p)
	p.abilities.try_cast(slot)
	p.downed_changed.emit(true)
	check(not mate.damage_mults.has(key), "the Warrior going down ends it")
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	p.abilities.try_cast(slot)
	check(mate.damage_mults.has(key), "buffed again")
	p.abilities.forget(slot)
	check(not mate.damage_mults.has(key) and not p.damage_mults.has(key), "forgetting ends it")
	slot = _learn(p, &"battle_shout")
	p.abilities.try_cast(slot)
	check(mate.damage_mults.has(key), "buffed once more")
	p.abilities.begin_wave()
	check(not mate.damage_mults.has(key), "a new wave starts clean")
	p.abilities.try_cast(slot)
	check(mate.damage_mults.has(key), "and again")
	p.free()
	check(not mate.damage_mults.has(key), "a Warrior leaving the game takes the buff along")


# --- Shield Wall --------------------------------------------------------------------------

func _hit_taken(p: Player, raw: float, source: Node3D = null) -> float:
	p.invulnerable_left = 0.0
	var before := p.hp
	p.take_damage(raw, CombatMath.KIND_PROJECTILE, source)
	return before - p.hp


func test_shield_wall_halves_damage_taken() -> void:
	var p := _hero()
	var normal := _hit_taken(p, 20.0)
	check(normal > 0.0, "a hit hurts")
	var slot := _learn(p, &"shield_wall")
	check(slot in AbilityRunner.ACTIVE_SLOTS, "a button slot")
	check(p.abilities.try_cast(slot), "cast")
	check_near(p.damage_taken_mults[WarriorShieldWall.KEY], 0.5, 0.0001, "-50% damage taken")
	check_near(_hit_taken(p, 20.0), normal * 0.5, 0.01, "half the damage")
	check(p.get_node_or_null("ShieldWall") is WarriorShieldWallVfx, "the wall is drawn")
	check_near(p.abilities.remaining(slot), 24.0, 0.001, "24 s cooldown")
	_step(p, 3.9)
	check(p.damage_taken_mults.has(WarriorShieldWall.KEY), "4 s ...")
	_step(p, 0.2)
	check(not p.damage_taken_mults.has(WarriorShieldWall.KEY), "... then it drops")
	check_near(_hit_taken(p, 20.0), normal, 0.01, "full damage again")
	var look := p.get_node_or_null("ShieldWall") as WarriorShieldWallVfx
	check(look == null or look.is_dismissed(), "the wall fades away")


func test_shield_wall_power_and_rank_three() -> void:
	var p := _hero()
	var slot := _learn(p, &"shield_wall", 2)
	p.abilities.try_cast(slot)
	check_near(p.damage_taken_mults[WarriorShieldWall.KEY], 0.375, 0.0001, "Rank II: 62.5% less")
	_rank(p, &"shield_wall", 4)
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	p.abilities.try_cast(slot)
	check_near(p.damage_taken_mults[WarriorShieldWall.KEY], 0.25, 0.0001, "Rank IV: 75% less")
	_step(p, 5.9)
	check(p.damage_taken_mults.has(WarriorShieldWall.KEY), "Rank III: 6 sec")
	_step(p, 0.2)
	check(not p.damage_taken_mults.has(WarriorShieldWall.KEY), "and done")


func test_shield_wall_last_stand_survives_lethal_hits() -> void:
	var p := _hero()
	var slot := _learn(p, &"shield_wall", 5, 0)
	var wall := _effect(p, slot) as WarriorShieldWall
	p.abilities.try_cast(slot)
	check_eq(p.death_guards.size(), 1, "a death guard while it stands")
	p.hp = 5.0
	_hit_taken(p, 5000.0)
	check(p.is_alive(), "survived")
	check_near(p.hp, 1.0, 0.001, "at 1 HP")
	check_eq(wall.saves, 1, "one save")
	_step(p, 6.1)
	check(p.death_guards.is_empty(), "the guard ends with the wall")
	_hit_taken(p, 5000.0)
	check(not p.is_alive(), "no wall, no miracle")


func test_shield_wall_last_stand_goes_before_an_item_cheat_death() -> void:
	var p := _hero()
	var shard := ItemGenerator.from_unique(Db.get_unique(&"shard_of_everfrost"), 1, false, RunState.rng,
			p.class_data)
	check(p.equipment.equip(shard), "wears the Shard of Everfrost (Narrow Escape once per wave)")
	var slot := _learn(p, &"shield_wall", 5, 0)
	var wall := _effect(p, slot) as WarriorShieldWall
	p.abilities.try_cast(slot)
	p.hp = 5.0
	_hit_taken(p, 5000.0)
	check(p.is_alive(), "survived")
	check_eq(wall.saves, 1, "the free Last Stand took the lethal hit")
	wall.end()
	p.hp = 5.0
	_hit_taken(p, 5000.0)
	check(p.is_alive(), "the Shard was kept for a lethal hit after the wall")
	p.hp = 5.0
	_hit_taken(p, 5000.0)
	check(not p.is_alive(), "(and then it is spent for the wave)")


func test_shield_wall_spiked_wall_retaliates() -> void:
	var p := _hero()
	var attacker := _fake(Vector3(1.0, 0.0, 0.0))
	var slot := _learn(p, &"shield_wall", 5, 1)
	var wall := _effect(p, slot) as WarriorShieldWall
	_hit_taken(p, 10.0, attacker)
	check_eq(attacker.fake_hits(), 0, "no thorns before the wall")
	p.abilities.try_cast(slot)
	check(p.death_guards.is_empty(), "no Last Stand with this spec")
	_hit_taken(p, 10.0, attacker)
	check_eq(attacker.fake_hits(), 1, "the attacker is struck back")
	check_near(attacker.fake_damage_log[0], _hit(p) * 1.5 * 1.5, 0.01, "150% weapon damage x power")
	check_eq(wall.retaliations, 1, "counted")
	p.end_wave()
	_hit_taken(p, 10.0, attacker)
	check_eq(attacker.fake_hits(), 1, "no spikes after the wave")


func test_shield_wall_bot_rule() -> void:
	var p := _hero()
	var slot := _learn(p, &"shield_wall")
	_fake(Vector3(2.0, 0.0, 0.0))
	check(not _wants(p, slot), "healthy and one enemy: no need")
	p.hp = p.max_hp() * 0.4
	check(_wants(p, slot), "hurt with an enemy close")
	p.hp = p.max_hp()
	for i in 6:
		_fake(Vector3(cos(i) * 2.0, 0.0, sin(i) * 2.0))
	check(_wants(p, slot), "a crowd pressing in")
	p.abilities.try_cast(slot)
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	check(not _wants(p, slot), "not while it already stands")


func test_shield_wall_cleanup() -> void:
	var p := _hero()
	var slot := _learn(p, &"shield_wall", 5, 0)
	p.abilities.try_cast(slot)
	p.downed_changed.emit(true)
	check(not p.damage_taken_mults.has(WarriorShieldWall.KEY) and p.death_guards.is_empty(), "down: gone")
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	p.abilities.try_cast(slot)
	p.end_wave()
	check(not p.damage_taken_mults.has(WarriorShieldWall.KEY) and p.death_guards.is_empty(), "wave end: gone")
	p.abilities.begin_wave()
	p.abilities.try_cast(slot)
	p.abilities.forget(slot)
	check(not p.damage_taken_mults.has(WarriorShieldWall.KEY) and p.death_guards.is_empty(), "forgotten: gone")
	var look := p.get_node_or_null("ShieldWall") as WarriorShieldWallVfx
	check(look == null or look.is_dismissed(), "the look goes too")


# --- Bladestorm ---------------------------------------------------------------------------

func test_bladestorm_storms_for_three_seconds_unstoppable() -> void:
	var p := _hero()
	var near := [_fake(Vector3(2.0, 0.0, 0.0)), _fake(Vector3(-1.5, 0.0, 1.0)), _fake(Vector3(0.0, 0.0, -2.5))]
	var far := _fake(Vector3(7.0, 0.0, 0.0))
	var slot := _learn(p, &"bladestorm")
	check(slot in AbilityRunner.AUTO_SLOTS, "an auto-cast slot")
	var storm := _effect(p, slot) as WarriorBladestorm
	check(p.stats.get_raw(Stats.SPEED) < 0.0, "the Warrior is a little slow (-5%)")
	check(p.abilities.try_cast(slot), "cast")
	check(storm.is_storming() and storm.is_unstoppable(), "storming, unstoppable")
	check(p.stats.get_raw(Stats.SPEED) >= -0.0001, "nothing slows the storm")
	check_near(p.stats.move_speed(), Stats.BASE_MOVE_SPEED, 0.001, "full base speed")
	check(p.get_node_or_null("BladestormSpin") is WarriorSpinVfx, "the storm is drawn")
	_step(p, 3.1)
	for e: Fakes.FakeEnemy in near:
		check_eq(e.fake_hits(), 12, "12 hits in 3 s")
		check_near(_total(e), _hit(p) * 3.0, 0.05, "300% weapon damage in total")
	check_eq(far.fake_hits(), 0, "out of reach")
	check(not storm.is_storming(), "over")
	check(not p.stats.has_source(WarriorBladestorm.UNSTOPPABLE_SOURCE), "the speed source is gone")
	check(p.stats.get_raw(Stats.SPEED) < 0.0, "slow again")
	check_near(p.abilities.remaining(slot), 20.0 - 3.1, 0.05, "20 s cooldown")


func test_bladestorm_power_and_rank_three() -> void:
	var p := _hero()
	var e := _fake(Vector3(2.0, 0.0, 0.0))
	var slot := _learn(p, &"bladestorm", 3)
	p.abilities.try_cast(slot)
	check_near(e.fake_damage_log[0], _hit(p) * 3.0 / 12.0 * 1.25, 0.01, "Rank II: +25% per hit")
	_step(p, 4.1)
	check_eq(e.fake_hits(), 16, "Rank III: 4 s storm")
	check_near(_total(e), _hit(p) * 3.0 * 1.25 * 4.0 / 3.0, 0.05, "more hits, same size")


func test_bladestorm_bloodstorm_heals() -> void:
	var p := _hero()
	var near := [_fake(Vector3(2.0, 0.0, 0.0)), _fake(Vector3(-1.5, 0.0, 1.0))]
	var slot := _learn(p, &"bladestorm", 5, 1)
	var storm := _effect(p, slot) as WarriorBladestorm
	p.hp = p.max_hp() * 0.5
	var before := p.hp
	p.abilities.try_cast(slot)
	_step(p, 1.0)
	var dealt := storm.spin().damage_dealt
	check(dealt > 0.0, "damage dealt")
	check_near(p.hp - before, dealt * 0.2, 0.05, "healed 20% of it")
	check(near.size() == 2, "(two enemies)")


func test_bladestorm_ravager_whirls_on_the_group() -> void:
	_arena()
	var p := _hero()
	var group := [_fake(Vector3(7.0, 0.0, 0.0)), _fake(Vector3(7.5, 0.0, 1.0)), _fake(Vector3(6.5, 0.0, -1.0))]
	var by_hero := _fake(Vector3(-1.0, 0.0, 0.0))
	var slot := _learn(p, &"bladestorm", 5, 0)
	var storm := _effect(p, slot) as WarriorBladestorm
	check(p.abilities.try_cast(slot), "cast")
	check(storm.is_storming(), "storming")
	check(not storm.is_unstoppable(), "the hero itself is not the storm")
	check(not p.stats.has_source(WarriorBladestorm.UNSTOPPABLE_SOURCE), "no speed source")
	var axe: WarriorRavagerAxe
	for c in arena.entities.get_children():
		if c is WarriorRavagerAxe:
			axe = c
	check(axe != null, "an axe was thrown")
	if axe != null:
		check(axe.global_position.distance_to(Vector3(7.0, 0.0, 0.0)) < 1.2, "onto the group")
		check(axe.is_in_group(&"ability_areas"), "freed with the wave")
	_step(p, 4.1)
	for e: Fakes.FakeEnemy in group:
		check_eq(e.fake_hits(), 16, "the group is shredded (4 s with Rank III)")
	check_eq(by_hero.fake_hits(), 0, "the enemy next to the hero is not")


func test_bladestorm_auto_rule() -> void:
	var p := _hero()
	var slot := _learn(p, &"bladestorm")
	_fake(Vector3(2.0, 0.0, 0.0))
	_fake(Vector3(-2.0, 0.0, 0.0))
	check(not _wants(p, slot), "two enemies: wait")
	_fake(Vector3(0.0, 0.0, 2.0))
	check(_wants(p, slot), "three: storm")
	var p2 := _hero(Vector3(0.0, 0.0, 30.0), 1)
	var slot2 := _learn(p2, &"bladestorm")
	_elite(Vector3(1.5, 0.0, 30.0))
	check(_wants(p2, slot2), "an elite alone")
	var p3 := _hero(Vector3(30.0, 0.0, 0.0), 2)
	var slot3 := _learn(p3, &"bladestorm", 5, 0)
	_fake(Vector3(38.0, 0.0, 0.0))
	_fake(Vector3(38.5, 0.0, 1.0))
	check(not _wants(p3, slot3), "Whirling Axe: two far away")
	_fake(Vector3(37.5, 0.0, -1.0))
	check(_wants(p3, slot3), "Whirling Axe: a group of three 8 m away")


func test_bladestorm_cleanup() -> void:
	var p := _hero()
	var e := _fake(Vector3(2.0, 0.0, 0.0))
	var slot := _learn(p, &"bladestorm")
	var storm := _effect(p, slot) as WarriorBladestorm
	p.abilities.try_cast(slot)
	p.downed_changed.emit(true)
	check(not storm.is_storming() and not p.stats.has_source(WarriorBladestorm.UNSTOPPABLE_SOURCE), "down: over")
	var hits := e.fake_hits()
	_step(p, 1.0)
	check_eq(e.fake_hits(), hits, "no more hits")
	p.abilities.begin_wave()
	p.abilities.try_cast(slot)
	p.end_wave()
	check(not storm.is_storming() and not p.stats.has_source(WarriorBladestorm.UNSTOPPABLE_SOURCE), "wave end: over")
	var look := p.get_node_or_null("BladestormSpin")
	check(look == null or look.is_queued_for_deletion(), "the look goes")
	p.abilities.begin_wave()
	p.abilities.try_cast(slot)
	p.abilities.forget(slot)
	check(not storm.is_storming() and not p.stats.has_source(WarriorBladestorm.UNSTOPPABLE_SOURCE), "forgotten: over")


# --- Whirlwind ranks ----------------------------------------------------------------------

func test_whirlwind_ranks() -> void:
	var p := _hero()
	var e := _fake(Vector3(1.5, 0.0, 0.0))
	var edge := _fake(Vector3(4.3, 0.0, 0.0))
	_rank(p, &"whirlwind", 2)
	check_eq(p.abilities.rank_of(&"whirlwind"), 2, "core abilities rank up too")
	_rage(p).set_value(100.0)
	p.abilities.try_cast(0)
	check_near(e.fake_damage_log[0], _hit(p) * 1.5 / 4.0 * 1.25, 0.01, "Rank II: +25%")
	check_eq(edge.fake_hits(), 0, "3 m reach")
	_step(p, 1.1)
	_rank(p, &"whirlwind", 3)
	p.abilities.try_cast(0)
	check_eq(edge.fake_hits(), 1, "Rank III: +1 m reach")


func test_whirlwind_specs() -> void:
	var p := _hero()
	var e := _fake(Vector3(1.5, 0.0, 0.0))
	_rank(p, &"whirlwind", 5, 0)
	_rage(p).set_value(100.0)
	check(p.abilities.try_cast(0), "cast")
	check_near(_rage(p).value, 75.0, 0.001, "Unrelenting: 25 Rage")
	_step(p, 1.1)
	check(p.abilities.set_spec(&"whirlwind", 1), "respec in a test")
	p.hp = p.max_hp() * 0.5
	var before := p.hp
	_rage(p).set_value(100.0)
	p.abilities.try_cast(0)
	check_near(_rage(p).value, 60.0, 0.001, "Bloodbath: the normal 40 Rage")
	var ww := _effect(p, 0) as WarriorWhirlwind
	check_near(p.hp - before, ww.spin().damage_dealt * 0.15, 0.01, "heals 15% of the damage")
	check(e.fake_hits() >= 5, "(hit)")


func test_whirlwind_ends_with_the_wave() -> void:
	var p := _hero()
	_fake(Vector3(1.5, 0.0, 0.0))
	_rage(p).set_value(100.0)
	p.abilities.try_cast(0)
	var ww := _effect(p, 0) as WarriorWhirlwind
	p.end_wave()
	check(not ww.is_spinning(), "no spin in the market")
	var look := p.get_node_or_null("WhirlwindSpin")
	check(look == null or look.is_queued_for_deletion(), "its look goes too")


# --- Charge ranks -------------------------------------------------------------------------

func test_charge_power_lengthens_the_stun() -> void:
	_arena()
	var p := _hero()
	(p.slot.input as ScriptedInput).move = Vector2(1.0, 0.0)
	var target := _real(Vector3(7.5, 0.0, 0.5))
	_rank(p, &"charge", 2)
	check(p.abilities.try_cast(1), "cast")
	check_near(p.abilities.remaining(1), 7.2, 0.001, "Rank II: -10% cooldown")
	_step(p, 0.6)
	check_near(target.stun_left, 1.25, 0.05, "Rank II: 1.25 s stun")


func test_charge_rank_three_two_charges() -> void:
	_arena()
	var p := _hero()
	(p.slot.input as ScriptedInput).move = Vector2(1.0, 0.0)
	_rank(p, &"charge", 3)
	check_eq(p.abilities.charges_max(p.abilities.slots[1]), 2, "two charges")
	check(p.abilities.try_cast(1), "first charge")
	check(not p.abilities.try_cast(1), "not while dashing")
	_step(p, 0.6)
	(p.slot.input as ScriptedInput).move = Vector2(-1.0, 0.0)
	check(p.abilities.try_cast(1), "second charge right away")
	_step(p, 0.6)
	check(not p.abilities.try_cast(1), "then the cooldown")


func test_charge_warbringer_hurts_what_it_stuns() -> void:
	_arena()
	var p := _hero()
	(p.slot.input as ScriptedInput).move = Vector2(1.0, 0.0)
	var on_path := _fake(Vector3(3.0, 0.0, 0.3))
	var landing := _fake(Vector3(9.5, 0.0, 0.0))  # 2.5 m from the landing: +1 m radius reaches it
	var off := _fake(Vector3(0.0, 0.0, 6.0))
	_rank(p, &"charge", 5, 0)
	check_near(_ctx(p, 1).num("stun_radius"), 3.0, 0.001, "+1 m landing radius")
	p.abilities.try_cast(1)
	_step(p, 0.6)
	check_eq(on_path.fake_hits(), 1, "run over: hurt once")
	check_near(on_path.fake_damage_log[0], _hit(p) * 1.5 * 1.5, 0.01, "150% x Rank V power")
	check_eq(landing.fake_hits(), 1, "landing area: hurt")
	check_eq(off.fake_hits(), 0, "off the path: untouched")


func test_charge_furious_charge_gives_rage() -> void:
	_arena()
	var p := _hero()
	(p.slot.input as ScriptedInput).move = Vector2(1.0, 0.0)
	_rank(p, &"charge", 5, 1)
	p.abilities.try_cast(1)
	check_near(_rage(p).value, 0.0, 0.001, "nothing before landing")
	_step(p, 0.25)
	check_near(_rage(p).value, 30.0, 0.5, "20 Rage x Rank V power on landing (minus a little decay)")


func test_charge_ends_with_the_wave() -> void:
	_arena()
	var p := _hero()
	(p.slot.input as ScriptedInput).move = Vector2(1.0, 0.0)
	var ch := _effect(p, 1) as WarriorCharge
	p.abilities.try_cast(1)
	p.end_wave()
	check(not ch.is_dashing(), "no dash in the market")


func test_charge_and_heroic_leap_exclude_each_other() -> void:
	_arena()
	var p := _hero()
	(p.slot.input as ScriptedInput).move = Vector2(1.0, 0.0)
	var ahead := _real(Vector3(6.0, 0.0, 0.0))
	for pos: Vector3 in [Vector3(0.0, 0.0, -8.0), Vector3(0.6, 0.0, -8.5), Vector3(-0.6, 0.0, -7.5)]:
		_fake(pos)
	var slot := _learn(p, &"heroic_leap")
	var leap := _effect(p, slot) as WarriorHeroicLeap
	var charge := _effect(p, 1) as WarriorCharge
	# In the air: a Charge press is refused (and refunded); the leap would throw the dash away.
	check(p.abilities.try_cast(slot), "leap")
	check(not p.abilities.can_cast(1), "no Charge in the air")
	check(not p.abilities.try_cast(1), "a Charge press mid-leap is refused")
	check_eq(p.abilities.remaining(1), 0.0, "and refunded")
	_step(p, 0.8)
	check(not leap.is_flying(), "landed")
	check(p.global_position.distance_to(leap.landing_point()) < 0.01, "where the leap aimed")
	# Mid-dash: the leap waits (a bot's pass casts Charge first, then judges the leap).
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	p.global_position = Vector3.ZERO
	EnemyGrid.mark_dirty()
	check(p.abilities.try_cast(1), "charge")
	check(charge.is_dashing(), "dashing")
	check(not _wants(p, slot), "a bot does not leap mid-dash")
	check(not p.abilities.try_cast(slot), "a leap press mid-dash is refused")
	check_eq(p.abilities.remaining(slot), 0.0, "and refunded")
	_step(p, 0.6)
	check(not charge.is_dashing(), "the dash ends")
	check(ahead.stun_left > 0.0, "the Charge reached its target and stunned it")
	check(p.abilities.can_cast(slot), "the leap is ready again")
