extends TestCase
## Warrior Fury talents (M5 Wave 2, talents_warrior.md §2): every talent through
## player.talents.add -> PlayerBonuses on a real Warrior (stats, resource bonuses, ability
## params, procs), the Meat Cleaver Whirlwind refund (WarriorWhirlwind / WarriorSpin), the
## Rampage capstone (WarriorFuryRampage: stacks, timer, ally share, cleanup) and the Fury bot
## path (TalentBot over the real Db trees).

const Fakes := preload("res://tests/player_fakes.gd")
const EFakes := preload("res://tests/enemies_fakes.gd")
const DT := 1.0 / 60.0
const RAMPAGE_ID := &"warrior_fury_rampage"

## The Fury bot with a one-handed sword (talents_warrior.md 5.4): Dual Wield Specialization
## is deferred.
const FURY_PATH: Array[StringName] = [
	&"warrior_fury_cruelty", &"warrior_fury_cruelty", &"warrior_fury_cruelty",
	&"warrior_fury_unbridled_wrath", &"warrior_fury_unbridled_wrath", &"warrior_fury_unbridled_wrath",
	&"warrior_fury_meat_cleaver",
	&"warrior_fury_improved_whirlwind", &"warrior_fury_improved_whirlwind", &"warrior_fury_improved_whirlwind",
	&"warrior_fury_blood_craze", &"warrior_fury_blood_craze",
	&"warrior_fury_rampage",
	&"warrior_fury_blood_craze",
	&"warrior_fury_flurry", &"warrior_fury_flurry", &"warrior_fury_flurry",
	&"warrior_fury_death_wish", &"warrior_fury_death_wish", &"warrior_fury_death_wish",
]

var world: Node3D


func before_each() -> void:
	PlayerManager.clear()
	RunState.start_run(1, 31337)
	RunState.set_start_level(31)
	world = EFakes.make_world(tree)


func after_each() -> void:
	EFakes.free_world(tree, world)
	world = null
	PlayerManager.clear()
	EnemyGrid.mark_dirty()


# --- Helpers ------------------------------------------------------------------------------

func _warrior(index: int = 0, pos: Vector3 = Vector3.ZERO) -> Player:
	var p := Fakes.spawn_player(world, index, &"warrior", pos)
	p.stats.set_source(&"tough", {Stats.STAMINA: 90.0})
	p.hp = p.max_hp()
	Enemy.invalidate_player_cache()
	return p


func _add(p: Player, short: String, n: int = 1) -> void:
	var id := StringName("warrior_fury_" + short)
	for i in n:
		check(p.talents.add(id), "add %s: %s" % [short, p.talents.add_block_reason(id)])


func _remove(p: Player, short: String, n: int = 1) -> void:
	var id := StringName("warrior_fury_" + short)
	for i in n:
		check(p.talents.remove(id), "remove %s: %s" % [short, p.talents.remove_block_reason(id)])


## The 12 points that open the capstone without dual wield (talents_warrior.md 5.2) + Rampage.
func _to_capstone(p: Player) -> void:
	_add(p, "cruelty", 3)
	_add(p, "unbridled_wrath", 3)
	_add(p, "improved_whirlwind", 3)
	_add(p, "meat_cleaver")
	_add(p, "flurry", 2)
	_add(p, "rampage")


func _rampage(p: Player) -> WarriorFuryRampage:
	return p.bonuses.script_for(RAMPAGE_ID) as WarriorFuryRampage


func _fake(pos: Vector3) -> Fakes.FakeEnemy:
	var e := Fakes.spawn_enemy(world, pos)
	EnemyGrid.mark_dirty()
	return e


func _ring_of(count: int, radius: float = 1.5) -> Array[Fakes.FakeEnemy]:
	var out: Array[Fakes.FakeEnemy] = []
	for i in count:
		var a := TAU * float(i) / float(count)
		out.append(_fake(Vector3(cos(a) * radius, 0.0, sin(a) * radius)))
	return out


func _rage(p: Player) -> ClassResource:
	return p.abilities.get_resource(&"rage")


func _whirlwind(p: Player) -> WarriorWhirlwind:
	return p.abilities.effect_for(p.abilities.slots[0]) as WarriorWhirlwind


func _step(p: Player, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		p.abilities._physics_process(DT)
		t += DT


func _texts(text: String) -> int:
	var n := 0
	for node in world.find_children("*", "Label3D", true, false):
		if (node as Label3D).text == text:
			n += 1
	return n


func _sword() -> ItemInstance:
	return ItemInstance.from_weapon(Db.get_weapon(&"sword"), Items.Rarity.COMMON, 1, false)


## Resource Regen [param pct] on the hero (the runner copies it into the Rage pool's gain_mult).
func _set_regen(p: Player, pct: float) -> void:
	p.stats.set_source(&"regen", {Stats.RESOURCE_REGEN: pct})
	p.abilities._physics_process(0.0)


## A test-only bonus source (like a set bonus): [param mods] on Whirlwind.
func _whirlwind_mods(p: Player, mods: Dictionary) -> void:
	var entries: Array[Dictionary] = [{"kind": "ability", "match": {"id": "whirlwind"}, "mods": mods, "rank": 1, "id": "test", "label": "Test"}]
	p.bonuses.set_effects(&"test", entries)


# --- Tree data ---------------------------------------------------------------------------

func test_fury_tree_data() -> void:
	var fury := Db.get_talent_tree(&"warrior_fury")
	check(fury != null, "warrior_fury in Db")
	if fury == null:
		return
	check(fury.class_id == &"warrior" and fury.index == 1 and fury.display_name == "Fury", "Warrior tree 2")
	var ids: Array[StringName] = []
	for t in fury.talents:
		ids.append(t.id)
	check_eq(ids, [&"warrior_fury_cruelty", &"warrior_fury_unbridled_wrath", &"warrior_fury_improved_whirlwind",
		&"warrior_fury_blood_craze", &"warrior_fury_dual_wield_specialization", &"warrior_fury_meat_cleaver",
		&"warrior_fury_flurry", &"warrior_fury_death_wish", &"warrior_fury_rampage"] as Array[StringName], "ids")
	check_eq(fury.get_talent(&"warrior_fury_flurry").prerequisite, &"warrior_fury_cruelty", "Flurry needs Cruelty")
	check_eq(fury.get_talent(&"warrior_fury_meat_cleaver").ability, &"whirlwind", "the modifier changes Whirlwind")
	check(fury.get_talent(RAMPAGE_ID).is_capstone(), "Rampage is the capstone")
	check_eq(fury.get_talent(&"warrior_fury_improved_whirlwind").text_for_rank(3),
		"Whirlwind costs 6 less Rage and deals 15% more damage.", "rank text")
	check_eq(fury.get_talent(&"warrior_fury_flurry").text_for_rank(2),
		"After a critical hit, your attack speed is increased by 12% for 3 sec.", "_fixed duration")
	check_eq(Db.talent_trees_for(&"warrior").size(), 3, "Arms, Fury, Protection")


# --- Tier 1-4 ----------------------------------------------------------------------------

func test_cruelty_adds_crit_per_rank_and_undo_removes_it() -> void:
	var p := _warrior()
	var crit := p.stats.get_raw(Stats.CRIT)
	_add(p, "cruelty", 3)
	check_eq(p.stats.get_raw(Stats.CRIT), crit + 6.0, "+2% per rank")
	_remove(p, "cruelty")
	check_eq(p.stats.get_raw(Stats.CRIT), crit + 4.0, "rank 2")
	_remove(p, "cruelty", 2)
	check_eq(p.stats.get_raw(Stats.CRIT), crit, "all back")


func test_unbridled_wrath_gives_rage_on_critical_hits() -> void:
	var p := _warrior()
	var rage := _rage(p)
	_add(p, "unbridled_wrath", 2)
	check_eq(rage.bonus, {"gain_on_crit_add": 6.0}, "+3 per rank reaches ClassResource.set_bonus")
	rage.set_value(0.0)
	rage.on_weapon_hit(true)
	check_near(rage.value, 4.0 + 6.0, 0.0001, "a critical weapon hit: 4 + 6 Rage")
	rage.set_value(0.0)
	rage.on_weapon_hit(false)
	check_near(rage.value, 4.0, 0.0001, "a normal hit: the usual 4")
	_add(p, "unbridled_wrath")
	rage.set_value(0.0)
	var e := _fake(Vector3(1.2, 0, 0))
	p.forced_crits = 1
	p.weapons[0].attack(e)
	check(e.fake_crit_log[0], "a real critical swing")
	check_near(rage.value, 4.0 + 9.0, 0.0001, "4 + 9 Rage at rank 3")
	_remove(p, "unbridled_wrath", 3)
	check_eq(rage.bonus, {}, "undone")


func test_improved_whirlwind_is_cheaper_and_stronger() -> void:
	var p := _warrior()
	var ww := Db.get_ability(&"whirlwind")
	_add(p, "cruelty", 3)
	_add(p, "improved_whirlwind", 3)
	var params := p.abilities.params_for(ww)
	check_near(float(params["cost"]), 34.0, 0.0001, "-2 Rage per rank")
	check_near(float(params["power"]), 1.15, 0.0001, "+5% power per rank")
	var e := _fake(Vector3(1.5, 0, 0))
	_rage(p).set_value(50.0)
	check(p.abilities.try_cast(0), "cast")
	check_near(_rage(p).value, 16.0, 0.0001, "34 Rage paid")
	check_near(e.fake_damage_log[0], WarriorKit.weapon_damage(p) * 1.5 * 1.15 / 4.0, 0.01, "the first hit is 15% stronger")
	_remove(p, "improved_whirlwind", 3)
	check_near(float(p.abilities.params_for(ww)["cost"]), 40.0, 0.0001, "back to 40")


func test_blood_craze_heals_on_kills_once_per_one_and_a_half_seconds() -> void:
	var p := _warrior()
	_add(p, "cruelty", 3)
	_add(p, "blood_craze", 2)
	var defs := p.procs.extra_defs(PlayerBonuses.SOURCE_TALENTS)
	check_eq(defs.size(), 1, "one proc")
	var e := _fake(Vector3(1.5, 0, 0))
	p.hp = 10.0
	p.notify_kill(e)
	check_near(p.hp, 10.0 + p.max_hp() * 0.02, 0.0001, "2% of Max HP at rank 2")
	var hp := p.hp
	p.notify_kill(e)
	check_eq(p.hp, hp, "a second kill within 1.5 sec does not heal")
	Fakes.step(p.procs, 1.55)
	p.notify_kill(e)
	check_near(p.hp, hp + p.max_hp() * 0.02, 0.0001, "after 1.5 sec it heals again")
	check_eq(_texts("Blood Craze"), 0, "no talent-name text (the heal number shows)")
	_remove(p, "blood_craze", 2)
	check(p.procs.extra_defs(PlayerBonuses.SOURCE_TALENTS).is_empty(), "undone")


func test_dual_wield_specialization_needs_two_weapons() -> void:
	var p := _warrior()
	_add(p, "cruelty", 3)
	_add(p, "unbridled_wrath", 3)
	_add(p, "dual_wield_specialization", 2)
	check_eq(p.bonuses.damage_mult(null, &"physical", &"weapon"), 1.0, "one sword: nothing")
	var spare := _sword()
	p.equipment.add_to_backpack(spare)
	check(p.equipment.equip(spare, Items.EquipSlot.OFF_HAND), "a second sword in the off hand")
	check(p.off_hand != null and p.weapons.size() == 2, "dual wielding")
	check_near(p.bonuses.damage_mult(null, &"fire", &"dot"), 1.10, 0.0001, "+5% per rank, every damage")
	check_near(p.outgoing_damage_mult(null, &"physical", &"ability"), 1.10, 0.0001, "in the outgoing multiplier")
	check(p.equipment.unequip(Items.EquipSlot.OFF_HAND), "off hand off")
	check_eq(p.bonuses.damage_mult(null, &"physical", &"weapon"), 1.0, "one weapon again: nothing")


func test_flurry_needs_cruelty_and_hastens_after_crits() -> void:
	var p := _warrior()
	_add(p, "cruelty", 2)
	_add(p, "unbridled_wrath", 3)
	_add(p, "improved_whirlwind", 3)
	_add(p, "blood_craze", 1)
	check_eq(p.talents.add_block_reason(&"warrior_fury_flurry"), "Requires Cruelty", "prerequisite")
	_add(p, "cruelty")
	_add(p, "flurry", 3)
	var e := _fake(Vector3(1.5, 0, 0))
	var haste := p.stats.get_stat(Stats.HASTE)
	p.procs.on_hit(e, 5.0, p.main_hand, false)
	check_eq(p.stats.get_stat(Stats.HASTE), haste, "a normal hit: nothing")
	p.procs.on_hit(e, 5.0, p.main_hand, true)
	check_near(p.stats.get_stat(Stats.HASTE), haste + 18.0, 0.0001, "+6% Haste per rank after a crit")
	p.procs.on_hit(e, 5.0, p.main_hand, true)
	check_near(p.stats.get_stat(Stats.HASTE), haste + 18.0, 0.0001, "a re-proc refreshes, does not stack")
	check_eq(_texts("Flurry"), 0, "silent")
	Fakes.step(p.procs, 3.1, 0.1)
	check_near(p.stats.get_stat(Stats.HASTE), haste, 0.0001, "for 3 sec")


func test_death_wish_raises_mastery_and_battle_fury() -> void:
	var p := _warrior()
	var fury := p.abilities.mastery as WarriorBattleFury
	check(fury != null, "Battle Fury")
	_add(p, "cruelty", 3)
	_add(p, "unbridled_wrath", 3)
	_add(p, "improved_whirlwind", 3)
	_add(p, "death_wish", 3)
	check_near(p.stats.get_stat(Stats.MASTERY), 12.0, 0.0001, "+4 Mastery per rank")
	check_eq(fury.damage_mult(null, &"physical", &"weapon"), 1.0, "full health: no Battle Fury")
	p.hp = p.max_hp() * 0.5
	check_near(fury.damage_mult(null, &"physical", &"weapon"), 1.0 + 12.0 * 0.5 * 5.0 / 100.0, 0.001,
		"+0.5% per Mastery point per 10% missing: +30% at half health")
	_remove(p, "death_wish", 3)
	check_eq(p.stats.get_stat(Stats.MASTERY), 0.0, "undone")


# --- Meat Cleaver ------------------------------------------------------------------------

func test_meat_cleaver_param_is_neutral_without_the_talent() -> void:
	var p := _warrior()
	var ww := Db.get_ability(&"whirlwind")
	check_eq(float(p.abilities.params_for(ww)["rage_per_enemy"]), 0.0, "neutral default")
	check_eq(float(p.abilities.params_for(ww)["rage_per_enemy_max"]), 12.0, "cap 12")
	_ring_of(5)
	_rage(p).set_value(100.0)
	check(p.abilities.try_cast(0), "cast")
	check_near(_rage(p).value, 60.0, 0.0001, "no refund without Meat Cleaver")
	check_eq(_whirlwind(p).refund_gained(), 0.0, "nothing refunded")
	_add(p, "cruelty", 3)
	_add(p, "unbridled_wrath", 3)
	_add(p, "meat_cleaver")
	check_eq(float(p.abilities.params_for(ww)["rage_per_enemy"]), 3.0, "3 Rage per enemy")
	check_eq(float(p.abilities.params_for(Db.get_ability(&"bladestorm")).get("rage_per_enemy", 0.0)), 0.0,
		"Bladestorm shares the spin but not the param")


func test_meat_cleaver_refunds_three_rage_per_enemy_up_to_twelve() -> void:
	var p := _warrior()
	_add(p, "cruelty", 3)
	_add(p, "unbridled_wrath", 3)
	_add(p, "meat_cleaver")
	_ring_of(5)
	_rage(p).set_value(100.0)
	check(p.abilities.try_cast(0), "cast")
	check_near(_whirlwind(p).refund_gained(), 12.0, 0.0001, "5 enemies: 12 (the cap), not 15")
	check_near(_rage(p).value, 72.0, 0.0001, "paid 40 from a full bar, then 12 back (the full bar swallowed nothing)")
	_step(p, 1.2)
	check(not _whirlwind(p).is_spinning(), "the spin is over")
	check_near(_whirlwind(p).refund_gained(), 12.0, 0.0001, "once per enemy, not per tick")


func test_meat_cleaver_refund_follows_the_pack_size_and_the_ticks() -> void:
	var p := _warrior()
	_add(p, "cruelty", 3)
	_add(p, "unbridled_wrath", 3)
	_add(p, "meat_cleaver")
	var pair := _ring_of(2)
	_rage(p).set_value(50.0)
	check(p.abilities.try_cast(0), "cast")
	check_near(_rage(p).value, 16.0, 0.0001, "2 enemies: 50 - 40 + 6")
	var late := _fake(Vector3(0.0, 0.0, 2.0))
	_step(p, 0.3)
	check_near(_whirlwind(p).refund_gained(), 9.0, 0.0001, "an enemy struck later in the spin counts once too")
	_step(p, 1.0)
	check_near(_whirlwind(p).refund_gained(), 9.0, 0.0001, "no more after that")
	check(pair[0].fake_hits() == 4 and late.fake_hits() == 3, "every tick still hits")
	# A lone target, next spin: the per-spin set starts over.
	late.fake_dead = true
	pair[1].fake_dead = true
	EnemyGrid.mark_dirty()
	_rage(p).set_value(40.0)
	check(p.abilities.try_cast(0), "second spin")
	check_near(_rage(p).value, 3.0, 0.0001, "a lone target refunds 3")


func test_meat_cleaver_never_refunds_more_than_the_spin_paid() -> void:
	var p := _warrior()
	_add(p, "cruelty", 3)
	_add(p, "unbridled_wrath", 3)
	_add(p, "meat_cleaver")
	var pack := _ring_of(5)
	_whirlwind_mods(p, {"cost_add": -30.0})
	check_near(float(p.abilities.params_for(Db.get_ability(&"whirlwind"))["cost"]), 10.0, 0.0001, "a 10 Rage spin")
	_rage(p).set_value(10.0)
	check(p.abilities.try_cast(0), "cast")
	check_near(_whirlwind(p).refund_gained(), 10.0, 0.0001, "5 enemies refund at most the 10 paid")
	check_near(_rage(p).value, 10.0, 0.0001, "the spin was free in effect, never a profit")
	_step(p, 1.2)
	# Resource Regen scales a refund, but the cap on what was paid still holds.
	_set_regen(p, 50.0)
	_rage(p).set_value(10.0)
	check(p.abilities.try_cast(0), "cast with +50% Resource Regen")
	check_near(_whirlwind(p).refund_gained(), 10.0, 0.0001, "still 10")
	_step(p, 1.2)
	p.bonuses.set_effects(&"test", [] as Array[Dictionary])
	for i in range(1, pack.size()):
		pack[i].fake_dead = true
	EnemyGrid.mark_dirty()
	_rage(p).set_value(40.0)
	check(p.abilities.try_cast(0), "a 40 Rage spin on one enemy")
	check_near(_whirlwind(p).refund_gained(), 4.5, 0.0001, "Resource Regen scales the 3 Rage (+50%)")
	check_near(_rage(p).value, 4.5, 0.0001, "paid 40, got 4.5 back")


func test_a_free_spin_refunds_nothing() -> void:
	var p := _warrior()
	_add(p, "cruelty", 3)
	_add(p, "unbridled_wrath", 3)
	_add(p, "meat_cleaver")
	_ring_of(5)
	_whirlwind_mods(p, {"free_chance_add": 100.0})
	var ww := Db.get_ability(&"whirlwind")
	var free_seen := 0
	var paid_seen := 0
	for i in 20:
		_rage(p).set_value(50.0)
		check(p.abilities.try_cast(0), "cast %d" % i)
		if p.abilities.last_paid(ww) <= 0.0:
			free_seen += 1
			check_eq(_whirlwind(p).refund_gained(), 0.0, "a free spin refunds nothing")
			check_near(_rage(p).value, 50.0, 0.0001, "and costs nothing")
		else:
			paid_seen += 1
			check_near(_rage(p).value, 22.0, 0.0001, "a paid spin: 50 - 40 + 12")
		_step(p, 1.1)
	check(free_seen > 0 and paid_seen > 0, "both kinds of spin seen (free %d, paid %d; 75%% cap)" % [free_seen, paid_seen])


func test_meat_cleaver_refunds_only_what_the_runner_charged() -> void:
	var p := _warrior()
	_add(p, "cruelty", 3)
	_add(p, "unbridled_wrath", 3)
	_add(p, "meat_cleaver")
	_ring_of(3)
	_rage(p).set_value(60.0)
	var ww := _whirlwind(p)
	var ctx := p.abilities.build_context(p.abilities.slots[0])
	check(ww.cast(ctx), "the effect alone (no runner payment, last_paid 0)")
	check_eq(ww.refund_gained(), 0.0, "nothing paid: nothing refunded")
	p.downed_changed.emit(true)
	check(not ww.is_spinning(), "going down stops the spin")
	p.downed_changed.emit(false)
	_step(p, 0.1)
	check_near(_rage(p).value, 60.0 - 3.0 * 0.1, 0.01, "no stray refund later (only the out-of-combat decay)")


# --- Rampage -----------------------------------------------------------------------------

func test_rampage_stacks_on_kills_up_to_twenty_percent() -> void:
	var p := _warrior()
	_to_capstone(p)
	var r := _rampage(p)
	check(r != null, "the capstone script runs")
	var e := _fake(Vector3(1.5, 0, 0))
	var state := RunState.rng.state
	for i in 9:
		p.notify_kill(e)
	check_eq(r.stacks, 9, "nine kills, nine stacks")
	check_near(p.bonuses.damage_mult(e, &"physical", &"weapon"), 1.18, 0.0001, "+2% per stack")
	check_eq(_texts("Rampage!"), 0, "no shout below the maximum")
	p.notify_kill(e)
	check_near(p.outgoing_damage_mult(e, &"fire", &"dot"), 1.2, 0.0001, "10 kills: +20% on every source")
	check_eq(_texts("Rampage!"), 1, "the shout at 10")
	p.notify_kill(e)
	check_eq(r.stacks, 10, "at most 10 stacks")
	check_near(p.bonuses.damage_mult(null, &"physical", &"ability"), 1.2, 0.0001, "the 11th kill stays at +20%")
	check_eq(_texts("Rampage!"), 1, "no second shout")
	check_eq(r.describe(), "Rampage: 10 stacks (+20% damage)", "describe")
	check_eq(RunState.rng.state, state, "no RNG")


func test_rampage_drops_after_five_seconds_without_a_kill() -> void:
	var p := _warrior()
	_to_capstone(p)
	var r := _rampage(p)
	var e := _fake(Vector3(1.5, 0, 0))
	for i in 6:
		p.notify_kill(e)
	check(p.get_node_or_null("RampageRing") != null, "the ember ring shows from 5 stacks")
	p.bonuses.tick(4.0)
	p.notify_kill(e)
	check_near(r.time_left(), 5.0, 0.0001, "a kill refreshes the timer")
	p.bonuses.tick(4.9)
	check_eq(r.stacks, 7, "still running at 4.9 sec")
	p.bonuses.tick(0.2)
	check_eq(r.stacks, 0, "5 sec without a kill: every stack drops at once")
	check_eq(p.bonuses.damage_mult(e, &"physical", &"weapon"), 1.0, "bonus gone")
	var ring := p.get_node_or_null("RampageRing") as WarriorAuraVfx
	check(ring == null or ring.is_dismissed(), "the ring fades out")


func test_rampage_shares_half_with_allies_in_range() -> void:
	var p := _warrior(0)
	var near := _warrior(1, Vector3(6, 0, 0))
	var far := _warrior(2, Vector3(0, 0, 9))
	_to_capstone(p)
	var r := _rampage(p)
	check_eq(r.key, &"warrior_fury_rampage:0", "one key per Warrior")
	var e := _fake(Vector3(1.5, 0, 0))
	for i in 10:
		p.notify_kill(e)
	p.bonuses.tick(DT)
	check_near(float(near.damage_mults.get(r.key, 0.0)), 1.1, 0.0001, "an ally at 6 m: half the bonus (+10%)")
	check(not far.damage_mults.has(r.key), "an ally at 9 m: none")
	check_near(near.outgoing_damage_mult(e, &"physical", &"weapon"), 1.1, 0.0001, "in the ally's outgoing multiplier")
	check_eq(near.bonuses.damage_mult(e, &"physical", &"weapon"), 1.0, "the ally has no stacks of its own")
	near.global_position = Vector3(8.5, 0, 0)
	far.global_position = Vector3(0, 0, 7)
	p.bonuses.tick(0.3)
	check(not near.damage_mults.has(r.key), "walked out: the share is gone")
	check_near(float(far.damage_mults.get(r.key, 0.0)), 1.1, 0.0001, "walked in: it gets the share")
	far.take_damage(far.hp + 1000.0, CombatMath.KIND_PROJECTILE, null)
	check(far.downed, "the ally is down")
	p.bonuses.tick(0.3)
	check(not far.damage_mults.has(r.key), "a downed ally loses it")
	check_eq(r.allies().size(), 0, "nobody holds it")


func test_rampage_ends_on_down_wave_and_teardown_leaving_no_key() -> void:
	var p := _warrior(0)
	var ally := _warrior(1, Vector3(3, 0, 0))
	_to_capstone(p)
	var r := _rampage(p)
	var e := _fake(Vector3(1.5, 0, 0))
	for i in 5:
		p.notify_kill(e)
	p.bonuses.tick(DT)
	check(ally.damage_mults.has(r.key), "shared")
	# Downed: the next tick drops everything.
	p.take_damage(p.hp + 1000.0, CombatMath.KIND_PROJECTILE, null)
	check(p.downed, "the Warrior is down")
	p.notify_kill(e)
	check_eq(r.stacks, 5, "a downed hero gains no stack")
	p.bonuses.tick(DT)
	check(r.stacks == 0 and not ally.damage_mults.has(r.key), "down: stacks and the share are gone")
	p.revive(1.0)
	for i in 5:
		p.notify_kill(e)
	p.bonuses.tick(DT)
	p.end_wave()
	check(r.stacks == 0 and not ally.damage_mults.has(r.key), "end_wave: the market shows no buff")
	for i in 5:
		p.notify_kill(e)
	p.bonuses.tick(DT)
	p.begin_wave()
	check(r.stacks == 0 and not ally.damage_mults.has(r.key), "begin_wave: a clean start")
	check(_rampage(p) == r, "the same instance across the wave start")
	for i in 5:
		p.notify_kill(e)
	p.bonuses.tick(DT)
	check(ally.damage_mults.has(r.key), "shared again")
	RunState.add_gold(100)
	check(p.talents.try_reset(0), "Reset Talents")
	check(_rampage(p) == null, "the capstone is gone")
	check(not ally.damage_mults.has(r.key), "teardown: no key left on the ally")
	check_eq(p.bonuses.damage_mult(e, &"physical", &"weapon"), 1.0, "no bonus left")


func test_two_fury_warriors_stack_their_shares() -> void:
	var a := _warrior(0)
	var b := _warrior(1, Vector3(2, 0, 0))
	var c := _warrior(2, Vector3(1, 0, 1))
	_to_capstone(a)
	_to_capstone(b)
	var e := _fake(Vector3(1.5, 0, 0))
	for i in 10:
		a.notify_kill(e)
		b.notify_kill(e)
	a.bonuses.tick(DT)
	b.bonuses.tick(DT)
	check_near(c.outgoing_damage_mult(e, &"physical", &"weapon"), 1.1 * 1.1, 0.0001, "two keys, two shares")
	check_near(a.outgoing_damage_mult(e, &"physical", &"weapon"), 1.2 * 1.1, 0.0001, "own stacks x the other's share")


# --- Bot path ----------------------------------------------------------------------------

## The ids TalentBot.next_talent picks for [param p], point by point, until it finds nothing.
static func _path(p: Player, slot_index: int, limit: int = 100) -> Array[StringName]:
	var out: Array[StringName] = []
	for i in limit:
		var t := TalentBot.next_talent(p, slot_index)
		if t == null or not p.talents.add(t.id):
			break
		out.append(t.id)
	return out


func test_fury_bot_path_reaches_rampage_at_13_and_defers_dual_wield() -> void:
	RunState.set_start_level(29)
	var p := _warrior(1)
	check(p.off_hand == null, "a lone sword")
	var path := _path(p, 1)
	check_eq(path, FURY_PATH, "Fury bot path (talents_warrior.md 5.4)")
	check_eq(path.find(&"warrior_fury_meat_cleaver"), 6, "the modifier is point 7")
	check_eq(path.find(RAMPAGE_ID), 12, "the capstone is point 13")
	check(_rampage(p) != null, "Rampage runs")
	RunState.set_start_level(31)
	var more := _path(p, 1)
	check_eq(more, [&"warrior_protection_toughness", &"warrior_protection_toughness"] as Array[StringName],
		"then the next tree, not the deferred Dual Wield Specialization")
	var q := _warrior(2)
	RunState.set_start_level(29)
	check_eq(TalentBot.spend_all(q, 1), 20, "spend_all spends the same 20")
	check_eq(q.talents.rank_of(RAMPAGE_ID), 1, "capstone")


func test_a_dual_wielding_fury_bot_takes_its_specialization_after_blood_craze() -> void:
	var p := _warrior(1)
	var spare := _sword()
	p.equipment.add_to_backpack(spare)
	check(p.equipment.equip(spare, Items.EquipSlot.OFF_HAND), "dual wield")
	var path := _path(p, 1)
	check_eq(path.find(RAMPAGE_ID), 12, "capstone still at 13")
	check_eq(path.find(&"warrior_fury_dual_wield_specialization"), 14, "right after Blood Craze 3 (points 15-16)")
	check_eq(path.size(), 22, "the whole tree")
	check_eq(p.talents.tree_points(&"warrior_fury"), 22, "22 points in Fury")
