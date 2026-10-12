extends "res://tests/talents_mage_base.gd"
## Mage Frost tree (M5, talents_mage.md 3): every talent through player.talents on a real Mage
## – Frost damage, Armor and Ice Barrier power, Blizzard radius / slow, the slowed / stunned
## multipliers, damage taken – the Deep Freeze modifier and Flash Freeze (BlizzardEffect storm
## tracking: finale, per-tick rolls on RunState.rng, downed, wave end), the O(1) frozen check
## (MageFrozen.is_frozen) and the Ice Lance capstone (MageFrostIceLance: forced weapon crits,
## x2 + Critical Damage for spells / burns / pets, not for weapon / proc hits, teardown).

const ICE_LANCE := &"mage_frost_ice_lance"


func _ice_lance(p: Player) -> MageFrostIceLance:
	return p.bonuses.script_for(ICE_LANCE) as MageFrostIceLance


func _blizzard(p: Player) -> BlizzardEffect:
	return _effect(p, &"blizzard") as BlizzardEffect


## A Mage with the 12 points that open the capstone, then Ice Lance.
func _ice_lance_mage(pos: Vector3 = Vector3.ZERO) -> Player:
	var p := _mage(pos)
	_plan(p, FROST_12)
	_add(p, String(ICE_LANCE))
	check(_ice_lance(p) != null, "Ice Lance script live")
	return p


## Casts Blizzard (RT, slot 0) at the enemies around; the storm must start.
func _storm(p: Player) -> void:
	var mana := p.abilities.get_resource(&"mana")
	mana.set_value(mana.max_value())
	check(p.abilities.try_cast(0), "Blizzard")


## Every enemy of [param pack] carries [param p]'s ice.
func _all_frozen(pack: Array[Fakes.FakeEnemy], p: Player) -> bool:
	for e in pack:
		if _ice(e, p) == null:
			return false
	return true


func _none_frozen(pack: Array[Fakes.FakeEnemy], p: Player) -> bool:
	for e in pack:
		if _ice(e, p) != null:
			return false
	return true


## Gives [param p] a test-only Flash Freeze chance of [param pct] (an extra bonus source).
func _force_tick_freeze(p: Player, pct: float) -> void:
	var entries: Array[Dictionary] = [{"kind": "ability", "match": {"id": "blizzard"},
		"mods": {"tick_freeze_chance_add": pct}, "rank": 1}]
	p.bonuses.set_effects(&"test_flash_freeze", entries)


# --- Tier 1-4 ----------------------------------------------------------------------------------

func test_piercing_ice_raises_frost_damage() -> void:
	var p := _mage()
	_add(p, "mage_frost_piercing_ice", 3)
	check_near(p.bonuses.damage_mult(null, &"frost", &"ability"), 1.09, 0.0001, "+3% Frost per rank")
	check_eq(p.bonuses.damage_mult(null, &"arcane", &"weapon"), 1.0, "not the wand")
	_remove(p, "mage_frost_piercing_ice", 3)
	check_eq(p.bonuses.damage_mult(null, &"frost", &"ability"), 1.0, "undone")


func test_ice_armor_adds_armor_and_barrier_power() -> void:
	var p := _mage()
	var armor := p.stats.get_raw(Stats.ARMOR)
	var barrier := _ability(&"ice_barrier")
	var shield := MageIceBarrier.shield_amount(p.abilities.build_context(barrier))
	_add(p, "mage_frost_ice_armor", 3)
	check_near(p.stats.get_raw(Stats.ARMOR), armor + 6.0, 0.0001, "+2 Armor per rank")
	check_near(float(_params(p, &"ice_barrier")["power"]), 1.24, 0.0001, "+8% barrier per rank")
	check_near(MageIceBarrier.shield_amount(p.abilities.build_context(barrier)), shield * 1.24, 0.0001,
		"the shield absorbs 24% more")
	check_eq(Db.get_talent(&"mage_frost_ice_armor").text_for_rank(3),
		"Increases your Armor by 6, and your Ice Barrier absorbs 24% more damage.", "text")
	_remove(p, "mage_frost_ice_armor", 3)
	check_near(p.stats.get_raw(Stats.ARMOR), armor, 0.0001, "undone")
	check_near(float(_params(p, &"ice_barrier")["power"]), 1.0, 0.0001, "undone")


func test_improved_blizzard_widens_and_slows_more() -> void:
	var p := _mage()
	_cluster(Vector3(6, 0, 0), 4)
	_add(p, "mage_frost_piercing_ice", 3)
	_add(p, "mage_frost_improved_blizzard", 3)
	var params := _params(p, &"blizzard")
	check_near(float(params["radius"]), 3.5 * 1.09, 0.0001, "+3% radius per rank")
	check_near(float(params["slow"]), 70.0, 0.0001, "slow 40 -> 70")
	_storm(p)
	var area := _areas()[0]
	check_near(area.radius, 3.5 * 1.09, 0.0001, "the storm is wider")
	check_near(area.slow_pct, 70.0, 0.0001, "and slows harder")
	check(_blizzard(p).storms.is_empty(), "no freeze talents: the storm is not tracked")


func test_winters_chill_hits_slowed_enemies_harder() -> void:
	var p := _mage()
	_add(p, "mage_frost_piercing_ice", 3)
	_add(p, "mage_frost_winters_chill", 3)
	var e := _enemy(Vector3(3, 0, 0))
	check_eq(p.bonuses.damage_mult(e, &"arcane", &"weapon"), 1.0, "not slowed")
	e.apply_slow(40.0, 2.0)
	check_near(p.bonuses.damage_mult(e, &"arcane", &"weapon"), 1.09, 0.0001, "+3% per rank vs slowed")
	check_near(p.bonuses.damage_mult(e, &"frost", &"ability"), 1.18, 0.0001, "adds to Piercing Ice")


func test_arctic_winds_adds_frost_damage_and_reduces_damage_taken() -> void:
	var p := _mage()
	_plan(p, [["mage_frost_piercing_ice", 3], ["mage_frost_ice_armor", 3]])
	_add(p, "mage_frost_arctic_winds", 2)
	check_near(p.bonuses.damage_mult(null, &"frost", &"ability"), 1.13, 0.0001, "9% + 4% Frost")
	check_near(p.bonuses.damage_taken_mult(CombatMath.KIND_MELEE, null), 0.96, 0.0001, "-2% damage taken per rank")
	_remove(p, "mage_frost_arctic_winds", 2)
	check_eq(p.bonuses.damage_taken_mult(CombatMath.KIND_MELEE, null), 1.0, "undone")


func test_chilled_to_the_bone_needs_winters_chill_and_hits_stunned_enemies() -> void:
	var p := _mage()
	_plan(p, [["mage_frost_piercing_ice", 3], ["mage_frost_ice_armor", 3], ["mage_frost_winters_chill", 2],
		["mage_frost_improved_blizzard", 1]])
	check_eq(p.talents.add_block_reason(&"mage_frost_chilled_to_the_bone"), "Requires Winter's Chill", "prerequisite")
	_add(p, "mage_frost_winters_chill")
	_add(p, "mage_frost_chilled_to_the_bone", 3)
	var e := _enemy(Vector3(3, 0, 0))
	check_eq(p.bonuses.damage_mult(e, &"arcane", &"weapon"), 1.0, "not stunned")
	e.stun_left = 1.0  # a freeze is a stun (any ally's stun counts)
	check_near(p.bonuses.damage_mult(e, &"arcane", &"weapon"), 1.12, 0.0001, "+4% per rank vs stunned")
	e.apply_slow(40.0, 2.0)
	check_near(p.bonuses.damage_mult(e, &"arcane", &"weapon"), 1.21, 0.0001, "+ Winter's Chill when slowed too")


# --- Deep Freeze -------------------------------------------------------------------------------

func test_deep_freeze_params_and_text() -> void:
	var p := _mage()
	check_eq(float(_params(p, &"blizzard")["end_freeze"]), 0.0, "neutral without the talent")
	_plan(p, [["mage_frost_piercing_ice", 3], ["mage_frost_ice_armor", 3]])
	_add(p, "mage_frost_deep_freeze")
	check_eq(float(_params(p, &"blizzard")["end_freeze"]), 1.5, "1.5 sec")
	check_eq(Db.get_talent(&"mage_frost_deep_freeze").text_for_rank(1),
		"When your Blizzard ends, every enemy still inside is frozen for 1.5 sec.", "text")


func test_deep_freeze_freezes_the_enemies_inside_when_the_storm_ends() -> void:
	var p := _mage()
	_plan(p, [["mage_frost_piercing_ice", 3], ["mage_frost_ice_armor", 3]])
	_add(p, "mage_frost_deep_freeze")
	var pack := _cluster(Vector3(6, 0, 0), 4)
	var outside := _enemy(Vector3(6, 0, 6))
	var state := RunState.rng.state
	_storm(p)
	var fx := _blizzard(p)
	check_eq(fx.storms.size(), 1, "the storm is tracked")
	_step(2.9, [p])
	check(_none_frozen(pack, p), "nothing frozen while it hails")
	_step(0.2, [p])
	check(_all_frozen(pack, p), "the finale freezes every enemy inside")
	check_eq(fx.finale_freezes, 4, "four freezes")
	check_near(_ice(pack[0], p).left, 1.5 - (3.1 - 3.0), 0.05, "for 1.5 sec")
	check(pack[0].fake_stun_count > 0 and MageFrozen.is_frozen(pack[0]), "a stun with ice")
	check(_ice(outside, p) == null, "enemies outside are not frozen")
	check(fx.storms.is_empty(), "once per storm")
	_step(1.0, [p])
	check_eq(fx.finale_freezes, 4, "no second finale")
	check_eq(RunState.rng.state, state, "no RNG")


func test_deep_freeze_has_no_finale_when_the_mage_goes_down_or_the_wave_ends() -> void:
	var p := _mage()
	_tough(p)
	_plan(p, [["mage_frost_piercing_ice", 3], ["mage_frost_ice_armor", 3]])
	_add(p, "mage_frost_deep_freeze")
	var pack := _cluster(Vector3(6, 0, 0), 4)
	_storm(p)
	var fx := _blizzard(p)
	p.end_wave()
	check(fx.storms.is_empty(), "wave end drops the pending storm")
	_step(3.2, [p])
	check(_none_frozen(pack, p), "no finale on an empty arena")
	_storm(p)
	check_eq(fx.storms.size(), 1, "a new storm")
	_down(p)
	check(fx.storms.is_empty(), "going down drops it")
	_step(3.2, [p])
	check(_none_frozen(pack, p) and fx.finale_freezes == 0, "no finale for a downed Mage")


# --- Flash Freeze ------------------------------------------------------------------------------

func test_flash_freeze_needs_improved_blizzard_params_and_text() -> void:
	var p := _mage()
	_plan(p, [["mage_frost_piercing_ice", 3], ["mage_frost_ice_armor", 3], ["mage_frost_improved_blizzard", 2],
		["mage_frost_winters_chill", 1]])
	check_eq(p.talents.add_block_reason(&"mage_frost_flash_freeze"), "Requires Improved Blizzard", "prerequisite")
	_add(p, "mage_frost_improved_blizzard")
	check_eq(float(_params(p, &"blizzard")["tick_freeze_chance"]), 0.0, "neutral without the talent")
	_add(p, "mage_frost_flash_freeze", 3)
	check_near(float(_params(p, &"blizzard")["tick_freeze_chance"]), 12.0, 0.0001, "4% per rank")
	check_near(float(_params(p, &"blizzard")["tick_freeze"]), 1.0, 0.0001, "1 sec freezes")
	check_eq(Db.get_talent(&"mage_frost_flash_freeze").text_for_rank(3),
		"Each tick of your Blizzard has a 12% chance to freeze each enemy inside for 1 sec.", "text")


func test_flash_freeze_at_full_chance_freezes_everyone_on_the_first_tick() -> void:
	var p := _mage()
	_force_tick_freeze(p, 100.0)
	var pack := _cluster(Vector3(6, 0, 0), 4)
	var outside := _enemy(Vector3(6, 0, 6))
	_storm(p)
	var fx := _blizzard(p)
	var state := RunState.rng.state
	_step(DT, [p])
	check(_all_frozen(pack, p), "every enemy inside froze on the first tick")
	check_eq(fx.tick_freezes, 4, "four freezes")
	check_near(_ice(pack[0], p).left, 1.0 - DT, 0.0001, "for 1 sec (one frame melted already)")
	check(_ice(outside, p) == null, "not outside")
	check_eq(RunState.rng.state, _state_after(state, 4), "one RunState.rng draw per enemy inside")
	_step(0.5, [p])
	check_eq(RunState.rng.state, _state_after(state, 4), "frozen enemies are not rolled again")
	check_eq(fx.tick_freezes, 4, "no new freezes while frozen")


func test_flash_freeze_without_a_chance_draws_nothing() -> void:
	var p := _mage()
	_add(p, "mage_frost_piercing_ice", 3)
	_add(p, "mage_frost_improved_blizzard", 3)
	var pack := _cluster(Vector3(6, 0, 0), 4)
	var state := RunState.rng.state
	_storm(p)
	_step(3.2, [p])
	check_eq(RunState.rng.state, state, "no draws at 0%")
	check(_none_frozen(pack, p), "no freezes")
	check_eq(_blizzard(p).tick_freezes, 0, "none counted")


## One storm over [param pack] from [param seed]: (freezes, rng state after).
func _flash_storm(p: Player, pack: Array[Fakes.FakeEnemy], seed: int) -> Array[int]:
	var fx := _blizzard(p)
	fx.tick_freezes = 0
	RunState.rng.seed = seed
	_storm(p)
	_step(3.2, [p])
	var out: Array[int] = [fx.tick_freezes, RunState.rng.state]
	_step(1.2, [p])  # every ice melts
	check(_none_frozen(pack, p), "melted")
	return out


func test_flash_freeze_rolls_deterministically_on_the_run_rng() -> void:
	var p := _mage()
	_plan(p, [["mage_frost_piercing_ice", 3], ["mage_frost_ice_armor", 3], ["mage_frost_improved_blizzard", 3]])
	_add(p, "mage_frost_flash_freeze", 3)
	var pack := _cluster(Vector3(6, 0, 0), 8, 1.2)
	var first := _flash_storm(p, pack, 99)
	check(first[0] > 0 and first[0] < 8 * 6, "some enemies froze (%d)" % first[0])
	var second := _flash_storm(p, pack, 99)
	check_eq(second[0], first[0], "the same seed freezes the same enemies")
	check_eq(second[1], first[1], "and draws the same numbers")


# --- Frozen check ------------------------------------------------------------------------------

func test_is_frozen_follows_the_ice_of_any_mage() -> void:
	var p := _mage()
	var q := _mage(Vector3(0, 0, 5), 1)
	var e := _enemy(Vector3(3, 0, 0))
	check(not MageFrozen.is_frozen(e), "not frozen")
	check(not MageFrozen.is_frozen(null), "null is not frozen")
	MageSpell.freeze(e, p, 1.0)
	check(MageFrozen.is_frozen(e), "frozen")
	check_eq(MageFrozen.frozen_count(), 1, "one enemy counted")
	MageSpell.freeze(e, q, 2.0)
	check_eq(MageFrozen.frozen_count(), 1, "still one enemy (two ice nodes)")
	MageSpell.freeze(e, p, 0.5)
	_step(1.1)
	check(_ice(e, p) == null, "the first Mage's ice melted")
	check(MageFrozen.is_frozen(e), "the second Mage's ice still counts")
	_step(1.0)
	check(not MageFrozen.is_frozen(e), "all melted: not frozen")
	check_eq(MageFrozen.frozen_count(), 0, "no key left")


func test_is_frozen_forgets_a_freed_enemy_and_a_new_run() -> void:
	var p := _mage()
	var e := _enemy(Vector3(3, 0, 0))
	MageSpell.freeze(e, p, 2.0)
	check_eq(MageFrozen.frozen_count(), 1, "counted")
	e.free()  # (a freed instance must not be passed to a typed parameter: count only)
	check_eq(MageFrozen.frozen_count(), 0, "a freed enemy leaves no key")
	var f := _enemy(Vector3(4, 0, 0))
	MageSpell.freeze(f, p, 0.5)
	check(MageFrozen.is_frozen(f), "frozen")
	RunState.start_run(1, 4242)
	check(not MageFrozen.is_frozen(f), "a new run starts from an empty count")
	check_eq(MageFrozen.frozen_count(), 0, "empty")
	_step(0.6)
	check_eq(MageFrozen.frozen_count(), 0, "the old run's ice melting does not touch the new count")
	MageSpell.freeze(f, p, 0.5)
	check(MageFrozen.is_frozen(f), "new ice counts again")


# --- Ice Lance ---------------------------------------------------------------------------------

func test_ice_lance_text_and_script() -> void:
	check_eq(Db.get_talent(ICE_LANCE).text_for_rank(1),
		"Frozen enemies take critical damage from everything you do: your weapon hits always crit them, and your spells, burns and other hits deal 2x damage to them (plus your Critical Damage bonus).",
		"text")
	var p := _mage()
	check(_ice_lance(p) == null, "no script before the capstone")
	_ice_lance_mage()


func test_ice_lance_forces_crits_on_frozen_enemies_only() -> void:
	var p := _ice_lance_mage()
	var e := _enemy(Vector3(3, 0, 0))
	check(not p.bonuses.crit_forced(e), "not frozen: no forced crit")
	check(not p.bonuses.crit_forced(null), "null target: false")
	e.stun_left = 1.0
	check(not p.bonuses.crit_forced(e), "a plain stun is not frozen")
	e.stun_left = 0.0
	MageSpell.freeze(e, p, 1.0)
	check(p.bonuses.crit_forced(e), "frozen: every weapon hit crits")
	_step(1.1)
	check(not p.bonuses.crit_forced(e), "melted: back to normal")


func test_ice_lance_doubles_spells_burns_and_pets_but_not_weapon_or_proc_hits() -> void:
	var p := _ice_lance_mage()
	var il := _ice_lance(p)
	var e := _enemy(Vector3(3, 0, 0))
	check_eq(il.damage_mult(e, &"frost", &"ability"), 1.0, "not frozen")
	MageSpell.freeze(e, p, 2.0)
	check_near(il.damage_mult(e, &"frost", &"ability"), 2.0, 0.0001, "Blizzard ticks x2")
	check_near(il.damage_mult(e, &"fire", &"dot"), 2.0, 0.0001, "burns x2")
	check_near(il.damage_mult(e, &"nature", &"pet"), 2.0, 0.0001, "pets x2")
	check_eq(il.damage_mult(e, &"arcane", &"weapon"), 1.0, "weapon hits get the forced crit instead")
	check_eq(il.damage_mult(e, &"arcane", &"proc"), 1.0, "procs derive from the crit already")
	p.stats.set_source(&"test_crit_damage", {Stats.CRIT_DAMAGE: 30.0})
	check_near(il.damage_mult(e, &"frost", &"ability"), 2.3, 0.0001, "+ Critical Damage")
	var other := _enemy(Vector3(-3, 0, 0))
	var frozen := p.procs.deal_raw(e, 10.0, &"frost", true, &"ability")
	var plain := p.procs.deal_raw(other, 10.0, &"frost", true, &"ability")
	check_near(frozen, plain * 2.3, 0.0001, "a spell hit on a frozen enemy")
	check_eq(il.damage_mult(null, &"frost", &"ability"), 1.0, "null target")


func test_ice_lance_crits_a_real_wand_hit_and_counts_another_mages_ice() -> void:
	var p := _ice_lance_mage()
	var q := _mage(Vector3(0, 0, 6), 1)
	var e := _enemy(Vector3(3, 0, 0))
	MageSpell.freeze(e, q, 2.0)
	var state := RunState.rng.state
	p.weapons[0].attack(e)
	_fly()
	check(e.fake_crit_log.size() == 1 and e.fake_crit_log[0], "the wand bolt crit the frozen enemy")
	check_eq(p.forced_crits, 0, "no banked crit used")
	check_eq(RunState.rng.state, state, "no crit roll drawn")
	check_eq(_ice_lance(p).sparks, 1, "a frosty spark")


func test_ice_lance_tears_down_on_reset() -> void:
	var p := _ice_lance_mage()
	var il := _ice_lance(p)
	var e := _enemy(Vector3(3, 0, 0))
	MageSpell.freeze(e, p, 3.0)
	il.on_hit(e, 10.0, true, true)
	il.on_hit(e, 10.0, true, true)
	check_eq(il.sparks, 1, "one spark per 0.15 sec")
	il.tick(0.2)
	il.on_hit(e, 10.0, true, true)
	check_eq(il.sparks, 2, "then another")
	RunState.add_gold(100)
	check(p.talents.try_reset(0), "Reset Talents")
	check(_ice_lance(p) == null and p.bonuses.scripts().is_empty(), "the capstone is gone")
	check(not p.bonuses.crit_forced(e), "no forced crits")
	check_eq(p.bonuses.damage_mult(e, &"frost", &"ability"), 1.0, "no bonus left")
	check(p.damage_mults.is_empty(), "no damage_mults keys")
