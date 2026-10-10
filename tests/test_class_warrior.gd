extends TestCase
## Warrior kit (M3, GDD 3.1): Rage, Whirlwind, Charge, the Battle Fury Mastery, the bot's
## auto-cast decisions.

const Fakes := preload("res://tests/player_fakes.gd")
const EFakes := preload("res://tests/enemies_fakes.gd")
const DT := 1.0 / 60.0

var world: Node3D
var arena: EFakes.TestArena


func before_each() -> void:
	PlayerManager.clear()
	RunState.start_run(1, 31337)
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

func _hero(pos: Vector3 = Vector3.ZERO) -> Player:
	var p := Fakes.spawn_player(world, 0, &"warrior", pos)
	p.stats.set_source(&"tough", {Stats.STAMINA: 500.0})
	p.hp = p.max_hp()
	return p


func _arena() -> void:
	arena = EFakes.TestArena.new()
	world.add_child(arena)


func _fake(pos: Vector3) -> Fakes.FakeEnemy:
	var e := Fakes.spawn_enemy(world, pos)
	EnemyGrid.mark_dirty()
	return e


func _real(pos: Vector3) -> Enemy:
	var e := Enemy.create(Db.get_enemy(&"skeleton_grunt"), 1)
	world.add_child(e)
	e.global_position = pos
	EnemyGrid.mark_dirty()
	return e


func _rage(p: Player) -> ClassResource:
	return p.abilities.get_resource(&"rage")


func _step(p: Player, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		p.abilities._physics_process(DT)
		t += DT


func _total(e: Fakes.FakeEnemy) -> float:
	var sum := 0.0
	for d in e.fake_damage_log:
		sum += d
	return sum


func _unique(id: StringName) -> ItemInstance:
	return ItemGenerator.from_unique(Db.uniques[id], 1, false, RunState.rng, Db.get_class_data(&"warrior"))


func _equip(p: Player, id: StringName) -> void:
	check(p.equipment.equip(_unique(id)), "%s can be equipped" % id)


func _ctx(p: Player, slot_index: int) -> AbilityContext:
	return p.abilities.build_context(p.abilities.slots[slot_index])


func _effect(p: Player, slot_index: int) -> AbilityEffect:
	return p.abilities.effect_for(p.abilities.slots[slot_index])


# --- Data ---------------------------------------------------------------------------------

func test_class_is_wired() -> void:
	var c := Db.get_class_data(&"warrior")
	check_eq(c.resources.size(), 1, "one resource")
	check_eq(c.resources[0].id, &"rage", "Rage")
	check_eq(c.abilities.size(), 2, "two core abilities")
	check_eq(c.abilities[0].id, &"whirlwind", "RT = Whirlwind")
	check_eq(c.abilities[1].id, &"charge", "LT = Charge")
	check(c.mastery == WarriorBattleFury, "Battle Fury")
	check(c.mastery_text.begins_with("Battle Fury"), "Mastery text")
	var ww := c.abilities[0]
	check_eq(ww.resource, &"rage", "Whirlwind costs Rage")
	check_eq(ww.cost, 40.0, "40 Rage")
	check_eq(ww.targeting, AbilityData.Targeting.SELF, "Whirlwind is cast on the hero")
	check(ww.effect == WarriorWhirlwind, "Whirlwind effect")
	var ch := c.abilities[1]
	check_eq(ch.cooldown, 8.0, "Charge: 8 s")
	check_eq(ch.targeting, AbilityData.Targeting.MOVE_DIRECTION, "Charge follows the move direction")
	check(ch.effect == WarriorCharge, "Charge effect")
	var p := _hero()
	check_eq(p.abilities.slots[0].id, &"whirlwind", "slot 0")
	check_eq(p.abilities.slots[1].id, &"charge", "slot 1")
	check(p.abilities.mastery is WarriorBattleFury, "Mastery instance")
	check(p.abilities.primary_resource() == _rage(p), "Rage is primary")


# --- Rage ---------------------------------------------------------------------------------

func test_rage_rules_of_the_gdd() -> void:
	var r := Db.get_class_data(&"warrior").resources[0]
	check_eq(r.max_value, 100.0, "0..100")
	check_eq(r.start_value, 0.0, "starts empty")
	check_eq(r.gain_on_hit, 4.0, "+4 per hit")
	check_eq(r.gain_on_damage_taken, 10.0, "+10 per hit taken")
	check_eq(r.decay_per_second, 3.0, "-3 / s")


func test_rage_gains_on_hit_and_on_damage_taken() -> void:
	var p := _hero()
	var rage := _rage(p)
	p.abilities.on_weapon_hit(null, 5.0, false)
	check_eq(rage.value, 4.0, "+4 per dealt hit")
	p.abilities.on_damage_taken(7.0)
	check_eq(rage.value, 14.0, "+10 per hit taken")
	for i in 40:
		p.abilities.on_weapon_hit(null, 5.0, false)
	check_eq(rage.value, 100.0, "capped at 100")


func test_rage_gains_from_real_weapon_hits_and_damage() -> void:
	var p := _hero()
	var e := _fake(Vector3(1.0, 0.0, 0.0))
	p.on_hit_dealt(5.0, e)
	check_eq(_rage(p).value, 4.0, "a weapon hit feeds Rage")
	p.take_damage(5.0, CombatMath.KIND_MELEE, null)
	check(_rage(p).value >= 4.0, "taking a hit never costs Rage")


func test_rage_decays_out_of_combat() -> void:
	var p := _hero()
	var rage := _rage(p)
	rage.set_value(50.0)
	p.abilities.on_weapon_hit(null, 5.0, false)  # +4, combat timer restarts
	_step(p, 1.5)
	check_eq(rage.value, 54.0, "no decay right after a hit")
	_step(p, 2.5)  # 2 s delay, then 2 s of decay
	check_near(rage.value, 54.0 - 3.0 * 2.0, 0.2, "-3 per second afterwards")
	rage.set_value(1.0)
	_step(p, 2.0)
	check_eq(rage.value, 0.0, "never below 0")


func test_rage_resets_every_wave() -> void:
	var p := _hero()
	_rage(p).set_value(80.0)
	p.begin_wave()
	check_eq(_rage(p).value, 0.0, "a wave starts without Rage")


# --- Whirlwind ----------------------------------------------------------------------------

func test_whirlwind_needs_40_rage() -> void:
	var p := _hero()
	_rage(p).set_value(39.0)
	check(not p.abilities.is_ready(0), "39 Rage: not ready")
	check(not p.abilities.try_cast(0), "39 Rage: no cast")
	check_eq(_rage(p).value, 39.0, "nothing spent")
	_rage(p).set_value(55.0)
	check(p.abilities.is_ready(0), "55 Rage: ready")
	check(p.abilities.try_cast(0), "cast")
	check_eq(_rage(p).value, 15.0, "40 Rage spent")
	check_eq(p.abilities.remaining(0), 0.0, "no cooldown")


func test_whirlwind_hits_everything_around_for_150_percent() -> void:
	var p := _hero()
	var near := [_fake(Vector3(2.0, 0.0, 0.0)), _fake(Vector3(-1.5, 0.0, 1.0)), _fake(Vector3(0.0, 0.0, -2.5))]
	var far := _fake(Vector3(6.0, 0.0, 0.0))
	var weapon_hit := CombatMath.weapon_hit_damage(p.main_hand, p.stats)
	_rage(p).set_value(100.0)
	check(p.abilities.try_cast(0), "cast")
	for e: Fakes.FakeEnemy in near:
		check_eq(e.fake_hits(), 1, "the first hit lands with the cast")
		check_near(e.fake_damage_log[0], weapon_hit * 1.5 / 4.0, 0.01, "a quarter of 150%")
	_step(p, 1.5)
	for e: Fakes.FakeEnemy in near:
		check_eq(e.fake_hits(), 4, "four hits in a 1 s spin")
		check_near(_total(e), weapon_hit * 1.5, 0.05, "150% weapon damage in total")
		check(e.fake_attacker_log[0] == p, "credited to the hero")
	check_eq(far.fake_hits(), 0, "an enemy out of reach is untouched")
	check(_rage(p).value <= 60.0, "ability damage does not feed Rage (it only decays)")


func test_whirlwind_reach_counts_the_enemy_body() -> void:
	var p := _hero()
	var edge := Fakes.spawn_enemy(world, Vector3(3.3, 0.0, 0.0), 0.45)  # 3.3 - 0.45 < 3.0
	var out := Fakes.spawn_enemy(world, Vector3(0.0, 0.0, 3.6), 0.45)
	EnemyGrid.mark_dirty()
	_rage(p).set_value(100.0)
	p.abilities.try_cast(0)
	check_eq(edge.fake_hits(), 1, "touching the circle counts")
	check_eq(out.fake_hits(), 0, "beyond it does not")


func test_whirlwind_area_size_widens_the_spin() -> void:
	var p := _hero()
	p.stats.set_source(&"area", {Stats.AREA_SIZE: 50.0})
	var e := _fake(Vector3(4.0, 0.0, 0.0))
	_rage(p).set_value(100.0)
	p.abilities.try_cast(0)
	check_eq(e.fake_hits(), 1, "3 m x 1.5 reaches 4 m")


func test_whirlwind_spin_shows_vfx_and_cannot_be_stacked() -> void:
	var p := _hero()
	_fake(Vector3(1.0, 0.0, 0.0))
	_rage(p).set_value(100.0)
	check(p.abilities.try_cast(0), "cast")
	var spin := p.get_node_or_null("WhirlwindSpin") as WarriorSpinVfx
	check(spin != null, "the spin is drawn around the hero")
	if spin != null:
		check(spin.get_child_count() > 0, "with parts")
		check_near(spin.duration, 1.0, 0.001, "for the spin's length")
	var ww := _effect(p, 0) as WarriorWhirlwind
	check(ww.is_spinning(), "spinning")
	check(not p.abilities.can_cast(0), "not while spinning")
	check_eq(_rage(p).value, 60.0, "a refused recast costs nothing")
	_step(p, 1.1)
	check(not ww.is_spinning(), "over after a second")
	check(p.abilities.can_cast(0), "ready again")


func test_whirlwind_spin_stops_when_the_hero_goes_down() -> void:
	var p := _hero()
	var e := _fake(Vector3(1.0, 0.0, 0.0))
	_rage(p).set_value(100.0)
	p.abilities.try_cast(0)
	p.downed_changed.emit(true)
	_step(p, 1.0)
	check_eq(e.fake_hits(), 1, "no more hits after going down")


func test_whirlwind_without_a_weapon_still_hurts() -> void:
	var p := _hero()
	p.main_hand = null
	var e := _fake(Vector3(1.0, 0.0, 0.0))
	_rage(p).set_value(100.0)
	check(p.abilities.try_cast(0), "cast")
	check(e.fake_damage_log[0] > 0.0, "fist damage")


func test_whirlwind_item_mods_longer_and_slowing() -> void:
	var p := _hero()
	_equip(p, &"gauntlets_of_the_whirling_blade")
	var e := _fake(Vector3(1.5, 0.0, 0.0))
	var weapon_hit := CombatMath.weapon_hit_damage(p.main_hand, p.stats)
	var ctx := _ctx(p, 0)
	check_near(ctx.num("duration"), 2.0, 0.001, "+1 s")
	check_near(ctx.num("slow"), 30.0, 0.001, "30% slow")
	_rage(p).set_value(100.0)
	check(p.abilities.try_cast(0), "cast")
	check_near(e.slow_pct, 30.0, 0.001, "hit enemies are slowed")
	check(e.slow_left > 0.0, "for a while")
	_step(p, 2.3)
	check_eq(e.fake_hits(), 8, "eight hits in a 2 s spin")
	check_near(_total(e), weapon_hit * 1.5 * 2.0, 0.1, "twice the hits, same hit size")
	var spin_alive := false
	for c in p.get_children():
		if c is WarriorSpinVfx:
			check_near((c as WarriorSpinVfx).duration, 2.0, 0.001, "the spin is drawn longer too")
			spin_alive = true
	check(spin_alive, "spin vfx")


func test_whirlwind_without_the_gauntlets_does_not_slow() -> void:
	var p := _hero()
	var e := _fake(Vector3(1.5, 0.0, 0.0))
	_rage(p).set_value(100.0)
	p.abilities.try_cast(0)
	check_eq(e.slow_pct, 0.0, "no slow by default")


# --- Charge -------------------------------------------------------------------------------

func test_charge_dashes_7_metres_and_stuns() -> void:
	_arena()
	var p := _hero()
	(p.slot.input as ScriptedInput).move = Vector2(1.0, 0.0)
	var on_path := _real(Vector3(3.0, 0.0, 0.3))
	var at_landing := _real(Vector3(8.0, 0.0, 1.0))
	var off_path := _real(Vector3(0.0, 0.0, 6.0))
	var behind := _real(Vector3(-3.0, 0.0, 0.0))
	check(p.abilities.try_cast(1), "cast")
	check_eq(p.abilities.remaining(1), 8.0, "8 s cooldown")
	check(p.invulnerable_left > 0.0, "invulnerable while charging")
	var ch := _effect(p, 1) as WarriorCharge
	check(ch.is_dashing(), "dashing")
	_step(p, 0.05)
	check(p.global_position.x > 1.0 and p.global_position.x < 6.0, "moving fast, not teleporting")
	_step(p, 0.5)
	check(not ch.is_dashing(), "arrived")
	check_near(p.global_position.x, 7.0, 0.05, "7 m forward")
	check_near(p.global_position.z, 0.0, 0.01, "straight")
	check(on_path.stun_left > 0.9, "stunned on the way (and again on landing)")
	check_near(on_path.stun_left, 1.0, 0.1, "for a second from the landing")
	check(at_landing.stun_left > 0.9, "stunned at the landing spot")
	check_eq(off_path.stun_left, 0.0, "off the path: no stun")
	check_eq(behind.stun_left, 0.0, "behind: no stun")
	check(not p.abilities.try_cast(1), "cooling down")


func test_charge_draws_a_streak_along_the_path() -> void:
	_arena()
	var p := _hero()
	(p.slot.input as ScriptedInput).move = Vector2(1.0, 0.0)
	p.abilities.try_cast(1)
	_step(p, 0.6)
	var streak: WarriorChargeVfx
	for c in arena.entities.get_children():
		if c is WarriorChargeVfx:
			streak = c
	check(streak != null, "a streak is left behind")
	if streak != null:
		check_near(streak.global_position.x, 3.5, 0.1, "centred on the path")
		var along := streak.global_transform.basis * Vector3.FORWARD
		check(along.dot(Vector3.RIGHT) > 0.99, "aligned with the dash direction")


func test_charge_goes_where_the_hero_faces_without_input() -> void:
	_arena()
	var p := _hero()
	p.facing = Vector3(0.0, 0.0, -1.0)
	check(p.abilities.try_cast(1), "cast")
	_step(p, 0.6)
	check_near(p.global_position.z, -7.0, 0.05, "screen-up is -Z")
	check_near(p.global_position.x, 0.0, 0.01, "no sideways drift")


func test_charge_stops_at_the_arena_wall() -> void:
	_arena()
	var limit := arena.get_bounds().end.x - (Player.RADIUS + Player.WALL_GAP)
	var p := _hero(Vector3(arena.get_bounds().end.x - 4.0, 0.0, 0.0))
	(p.slot.input as ScriptedInput).move = Vector2(1.0, 0.0)
	check(p.abilities.try_cast(1), "4 m of road is enough")
	_step(p, 0.6)
	check_near(p.global_position.x, limit, 0.02, "stops at the bounds")
	check(arena.is_inside(p.global_position), "still inside")
	check_near(arena.clamp_point(p.global_position, Player.RADIUS).x, p.global_position.x, 0.05, "clamp agrees")


func test_charge_refused_right_at_a_wall() -> void:
	_arena()
	var p := _hero(Vector3(arena.get_bounds().end.x - Player.RADIUS - Player.WALL_GAP, 0.0, 0.0))
	(p.slot.input as ScriptedInput).move = Vector2(1.0, 0.0)
	check(not p.abilities.try_cast(1), "no room")
	check_eq(p.abilities.remaining(1), 0.0, "no cooldown for a refused charge")
	(p.slot.input as ScriptedInput).move = Vector2(-1.0, 0.0)
	check(p.abilities.try_cast(1), "away from the wall it works")


func test_charge_ends_early_at_a_wall_but_still_stuns_there() -> void:
	_arena()
	var p := _hero(Vector3(arena.get_bounds().end.x - 3.0, 0.0, 0.0))
	(p.slot.input as ScriptedInput).move = Vector2(1.0, 0.0)
	var cornered := _real(Vector3(arena.get_bounds().end.x - 1.5, 0.0, 1.2))
	check(p.abilities.try_cast(1), "cast")
	_step(p, 0.6)
	check(cornered.stun_left > 0.9, "the stun lands where the charge ends")


func test_charge_is_not_a_teleport_through_time() -> void:
	_arena()
	var p := _hero()
	(p.slot.input as ScriptedInput).move = Vector2(1.0, 0.0)
	p.abilities.try_cast(1)
	_step(p, 0.1)
	var ch := _effect(p, 1) as WarriorCharge
	check(ch.is_dashing(), "0.1 s of a 7 m charge at 36 m/s: still running")
	check(p.global_position.x < 7.0, "not there yet")


func test_charge_greaves_buff_damage_for_3_seconds() -> void:
	_arena()
	var p := _hero()
	_equip(p, &"warbringers_greaves")
	(p.slot.input as ScriptedInput).move = Vector2(1.0, 0.0)
	var ctx := _ctx(p, 1)
	check_near(ctx.num("buff_damage"), 20.0, 0.001, "+20%")
	check_near(ctx.num("buff_duration"), 3.0, 0.001, "3 s")
	check_eq(p.outgoing_damage_mult(null, &"physical", &"weapon"), 1.0, "no buff before")
	p.abilities.try_cast(1)
	_step(p, 0.1)
	check(not p.damage_mults.has(WarriorCharge.BUFF_KEY), "the buff starts when the charge ends")
	_step(p, 0.4)
	check_near(p.outgoing_damage_mult(null, &"physical", &"weapon"), 1.2, 0.001, "+20% damage")
	check_near(p.outgoing_damage_mult(null, &"fire", &"proc"), 1.2, 0.001, "for every source")
	_step(p, 2.0)
	check(p.damage_mults.has(WarriorCharge.BUFF_KEY), "still on")
	_step(p, 1.2)
	check(not p.damage_mults.has(WarriorCharge.BUFF_KEY), "gone after 3 s")
	check_eq(p.outgoing_damage_mult(null, &"physical", &"weapon"), 1.0, "back to normal")


func test_charge_without_greaves_gives_no_buff() -> void:
	_arena()
	var p := _hero()
	(p.slot.input as ScriptedInput).move = Vector2(1.0, 0.0)
	p.abilities.try_cast(1)
	_step(p, 0.6)
	check(p.damage_mults.is_empty(), "no buff")


func test_charge_buff_ends_with_the_wave_or_a_down() -> void:
	_arena()
	var p := _hero()
	_equip(p, &"warbringers_greaves")
	(p.slot.input as ScriptedInput).move = Vector2(1.0, 0.0)
	p.abilities.try_cast(1)
	_step(p, 0.6)
	check(p.damage_mults.has(WarriorCharge.BUFF_KEY), "buffed")
	p.begin_wave()
	check(not p.damage_mults.has(WarriorCharge.BUFF_KEY), "a new wave clears it")
	p.abilities.begin_wave()
	(p.slot.input as ScriptedInput).move = Vector2(-1.0, 0.0)
	p.abilities.try_cast(1)
	_step(p, 0.6)
	check(p.damage_mults.has(WarriorCharge.BUFF_KEY), "buffed again")
	p.downed_changed.emit(true)
	check(not p.damage_mults.has(WarriorCharge.BUFF_KEY), "going down clears it")


# --- Battle Fury --------------------------------------------------------------------------

func test_battle_fury_scales_with_missing_health() -> void:
	var p := _hero()
	p.stats.set_source(&"mastery", {Stats.MASTERY: 20.0})
	var fury := p.abilities.mastery as WarriorBattleFury
	check_eq(fury.damage_mult(null, &"physical", &"weapon"), 1.0, "full health: nothing")
	p.hp = p.max_hp() * 0.9
	check_near(fury.damage_mult(null, &"physical", &"weapon"), 1.0 + 20.0 * 0.005, 0.0001, "10% missing: +0.5% per point")
	p.hp = p.max_hp() * 0.5
	check_near(p.outgoing_damage_mult(null, &"physical", &"weapon"), 1.0 + 20.0 * 0.005 * 5.0, 0.0001, "50% missing")
	p.hp = p.max_hp() * 0.2
	check_near(fury.damage_mult(null, &"fire", &"proc"), 1.0 + 20.0 * 0.005 * 8.0, 0.0001, "80% missing, every source")
	p.stats.set_source(&"mastery", {Stats.MASTERY: 0.0})
	check_eq(fury.damage_mult(null, &"physical", &"weapon"), 1.0, "no Mastery points: no bonus")


func test_battle_fury_boosts_ability_damage() -> void:
	var p := _hero()
	p.stats.set_source(&"mastery", {Stats.MASTERY: 10.0})
	p.hp = p.max_hp() * 0.4
	var e := _fake(Vector3(1.0, 0.0, 0.0))
	var weapon_hit := CombatMath.weapon_hit_damage(p.main_hand, p.stats)
	_rage(p).set_value(100.0)
	p.abilities.try_cast(0)
	var bonus := 1.0 + 10.0 * 0.005 * 6.0
	check_near(e.fake_damage_log[0], weapon_hit * 1.5 / 4.0 * bonus, 0.01, "+30% at 60% missing health")


func test_battle_fury_text() -> void:
	var p := _hero()
	p.stats.set_source(&"mastery", {Stats.MASTERY: 10.0})
	p.hp = p.max_hp() * 0.5
	var text := p.abilities.mastery.describe()
	check(text.contains("Battle Fury") and text.contains("25"), "describes the current bonus: %s" % text)


# --- Items --------------------------------------------------------------------------------

func test_class_items_are_ability_mods() -> void:
	var g := Db.uniques[&"gauntlets_of_the_whirling_blade"]
	var w := Db.uniques[&"warbringers_greaves"]
	for u: UniqueItemData in [g, w]:
		check_eq(u.unique_effect, &"ability_mod", "%s is an ability mod" % u.id)
		check_eq(u.class_restriction, &"warrior", "%s: Warrior only" % u.id)
		check(u.rarity >= Items.Rarity.RARE or u.id == &"warbringers_greaves", "%s: rarity kept" % u.id)
		var ability := StringName(u.unique_params.get("ability", ""))
		check(Db.get_class_data(&"warrior").abilities.any(func(a: AbilityData) -> bool: return a.id == ability),
				"%s targets a Warrior ability" % u.id)
		check(u.unique_params.get("mods") is Dictionary, "%s has mods" % u.id)
		check(u.unique_text != "" and not u.unique_text.contains("{"), "%s has text" % u.id)
		check(u.unique_text.begins_with("Equip: "), "%s: an Equip: line like the other class items" % u.id)
	check_eq(StringName(g.unique_params["ability"]), &"whirlwind", "gauntlets: Whirlwind")
	check_eq(StringName(w.unique_params["ability"]), &"charge", "greaves: Charge")
	check_eq(g.slot_type, Items.SlotType.HANDS, "gauntlets: Hands")
	check_eq(w.slot_type, Items.SlotType.FEET, "greaves: Feet")


func test_item_mods_only_touch_their_ability() -> void:
	var p := _hero()
	_equip(p, &"gauntlets_of_the_whirling_blade")
	check_eq(p.ability_mods(&"charge"), {}, "no mods for Charge")
	check(not p.ability_mods(&"whirlwind").is_empty(), "mods for Whirlwind")
	check_near(_ctx(p, 1).num("buff_damage"), 0.0, 0.001, "Charge unchanged")
	_equip(p, &"warbringers_greaves")
	check_near(_ctx(p, 1).num("buff_damage"), 20.0, 0.001, "Charge buffed by the greaves")
	check_near(_ctx(p, 0).num("duration"), 2.0, 0.001, "Whirlwind still +1 s")
	check_near(_ctx(p, 0).num("damage_pct"), 150.0, 0.001, "base damage untouched")


# --- Bots ---------------------------------------------------------------------------------

func test_bot_spins_with_three_enemies_in_reach() -> void:
	var p := _hero()
	var ww := _effect(p, 0)
	_rage(p).set_value(100.0)
	check(not ww.wants_auto_cast(_ctx(p, 0)), "nobody around")
	_fake(Vector3(1.0, 0.0, 0.0))
	_fake(Vector3(-1.0, 0.0, 0.0))
	_rage(p).set_value(50.0)
	check(not ww.wants_auto_cast(_ctx(p, 0)), "two enemies are not enough")
	_fake(Vector3(0.0, 0.0, 2.0))
	check(ww.wants_auto_cast(_ctx(p, 0)), "three are")


func test_bot_does_not_count_enemies_out_of_reach() -> void:
	var p := _hero()
	_rage(p).set_value(100.0)
	_fake(Vector3(1.0, 0.0, 0.0))
	_fake(Vector3(8.0, 0.0, 0.0))
	_fake(Vector3(0.0, 0.0, 9.0))
	_rage(p).set_value(50.0)
	check(not _effect(p, 0).wants_auto_cast(_ctx(p, 0)), "far enemies do not count")


func test_bot_spends_a_full_rage_bar_on_a_single_enemy() -> void:
	var p := _hero()
	_fake(Vector3(1.0, 0.0, 0.0))
	_rage(p).set_value(60.0)
	check(not _effect(p, 0).wants_auto_cast(_ctx(p, 0)), "one enemy, room in the bar: wait")
	_rage(p).set_value(100.0)
	check(_effect(p, 0).wants_auto_cast(_ctx(p, 0)), "a full bar is not wasted")


func test_bot_charges_at_a_distant_enemy_it_runs_towards() -> void:
	_arena()
	var p := _hero()
	var input := p.slot.input as ScriptedInput
	var ch := _effect(p, 1)
	check(not ch.wants_auto_cast(_ctx(p, 1)), "no enemy, no charge")
	var e := _real(Vector3(6.0, 0.0, 0.0))
	input.move = Vector2(1.0, 0.0)
	check(ch.wants_auto_cast(_ctx(p, 1)), "an enemy 6 m ahead")
	input.move = Vector2(0.0, 1.0)
	check(not ch.wants_auto_cast(_ctx(p, 1)), "not when running sideways")
	input.move = Vector2(-1.0, 0.0)
	check(not ch.wants_auto_cast(_ctx(p, 1)), "not away from it")
	e.global_position = Vector3(2.5, 0.0, 0.0)
	EnemyGrid.mark_dirty()
	input.move = Vector2(1.0, 0.0)
	check(not ch.wants_auto_cast(_ctx(p, 1)), "no gap to close")


func test_bot_does_not_charge_when_surrounded_or_into_a_wall() -> void:
	_arena()
	var p := _hero()
	var input := p.slot.input as ScriptedInput
	var ch := _effect(p, 1)
	input.move = Vector2(1.0, 0.0)
	_real(Vector3(6.0, 0.0, 0.0))
	check(ch.wants_auto_cast(_ctx(p, 1)), "baseline")
	_real(Vector3(0.0, 0.0, 1.5))
	_real(Vector3(-1.5, 0.0, 0.0))
	_real(Vector3(0.0, 0.0, -1.5))
	check(not ch.wants_auto_cast(_ctx(p, 1)), "three enemies on top of the hero: Whirlwind's job")
	p.global_position = Vector3(arena.get_bounds().end.x - 1.0, 0.0, 5.0)
	check(not ch.wants_auto_cast(_ctx(p, 1)), "no road ahead")


func test_bot_charges_to_escape_when_hurt() -> void:
	_arena()
	var p := _hero()
	var input := p.slot.input as ScriptedInput
	var ch := _effect(p, 1)
	_real(Vector3(1.5, 0.0, 0.0))
	_real(Vector3(1.5, 0.0, 1.0))
	_real(Vector3(0.0, 0.0, 1.5))
	input.move = Vector2(-1.0, 0.0)
	check(not ch.wants_auto_cast(_ctx(p, 1)), "healthy and surrounded: stay and fight")
	p.hp = p.max_hp() * 0.3
	check(ch.wants_auto_cast(_ctx(p, 1)), "hurt and running away: flee")
	input.move = Vector2(1.0, 0.0)
	check(not ch.wants_auto_cast(_ctx(p, 1)), "never charge into them")


func test_bot_does_not_charge_away_from_a_revive() -> void:
	_arena()
	var p := _hero()
	var input := p.slot.input as ScriptedInput
	var ch := _effect(p, 1)
	input.move = Vector2(1.0, 0.0)
	_real(Vector3(6.0, 0.0, 0.0))
	check(ch.wants_auto_cast(_ctx(p, 1)), "baseline: an enemy 6 m ahead")
	var mate := Fakes.spawn_player(world, 1, &"mage", Vector3(-1.0, 0.0, 0.5))
	mate._go_down()
	check(p.is_reviving(), "standing next to a downed teammate")
	check(not ch.wants_auto_cast(_ctx(p, 1)), "no charge while reviving")
	mate.global_position = Vector3(-6.0, 0.0, 0.0)
	check(not p.is_reviving(), "the teammate is out of reach")
	check(ch.wants_auto_cast(_ctx(p, 1)), "charges again")
	mate.global_position = Vector3(-1.0, 0.0, 0.5)
	_real(Vector3(1.5, 0.0, 0.0))
	_real(Vector3(1.5, 0.0, 1.0))
	_real(Vector3(0.0, 0.0, 1.5))
	p.hp = p.max_hp() * 0.3
	input.move = Vector2(-1.0, 0.0)
	check(not ch.wants_auto_cast(_ctx(p, 1)), "not even to flee while reviving")
	p.abilities.auto_cast = true
	p.abilities._auto_timer = 0.0
	var before := p.global_position
	_step(p, 0.3)
	check(p.global_position.distance_to(before) < 0.01, "the bot stayed at the revive")


func test_bots_cast_by_themselves() -> void:
	_arena()
	var p := _hero()
	p.abilities.auto_cast = true
	_fake(Vector3(1.0, 0.0, 0.0))
	_fake(Vector3(-1.0, 0.0, 0.5))
	_fake(Vector3(0.0, 0.0, 2.0))
	_rage(p).set_value(100.0)
	_step(p, 0.3)
	check(_rage(p).value < 61.0 and _rage(p).value > 55.0, "the bot spun: 40 Rage spent, a little decayed")
	check(_effect(p, 0).is_spinning() or p.get_node_or_null("WhirlwindSpin") != null, "spin running")
