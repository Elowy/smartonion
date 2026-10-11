extends TestCase
## Warrior Arms – the reference tree (M5, T-CORE-A; talent_vocabulary.md §6,
## talents_warrior.md §1): every talent through player.talents.add -> PlayerBonuses on a real
## Warrior. The talents the engine alone delivers are checked end to end (Deflection, Tactical
## Mastery's Rage generation, Improved Charge, Two-Handed Specialization, Impale, Mortal
## Strike); the proc / resource halves (Tactical Mastery's start Rage, Deep Wounds, Sweeping
## Blows, Sudden Death) are checked up to the T-CORE-B hand-off (ClassResource.set_bonus,
## ProcSystem.set_extra_procs) – their behaviour is T-CORE-B's tests and Wave 3's.

const Fakes := preload("res://tests/player_fakes.gd")
const EFakes := preload("res://tests/enemies_fakes.gd")
const MS_ID := &"warrior_arms_mortal_strike"


## ProcSystem that records the hand-offs (the real ones still run).
class HandOffProcs extends ProcSystem:
	var last_defs: Dictionary[StringName, Array] = {}

	func set_extra_procs(source: StringName, defs: Array[Dictionary]) -> void:
		last_defs[source] = defs.duplicate(true)
		super(source, defs)


var world: Node3D
var nodes: Array[Node] = []


func before_each() -> void:
	RunState.start_run(1, 31337)
	RunState.set_start_level(31)
	world = EFakes.make_world(tree)


func after_each() -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.free()
	nodes.clear()
	EFakes.free_world(tree, world)
	world = null
	EnemyGrid.mark_dirty()


func _warrior() -> Player:
	return Fakes.spawn_player(world, 0, &"warrior")


func _add(p: Player, short: String, n: int = 1) -> void:
	var id := StringName("warrior_arms_" + short)
	for i in n:
		check(p.talents.add(id), "add %s: %s" % [short, p.talents.add_block_reason(id)])


## The 12 points that open the capstone (talents_warrior.md 5.2 without a two-hander).
func _to_capstone(p: Player) -> void:
	_add(p, "deflection", 3)
	_add(p, "tactical_mastery", 3)
	_add(p, "improved_charge", 3)
	_add(p, "deep_wounds", 3)
	_add(p, "mortal_strike")


func _mortal_strike(p: Player) -> WarriorArmsMortalStrike:
	return p.bonuses.script_for(MS_ID) as WarriorArmsMortalStrike


# --- Tier 1-4 ----------------------------------------------------------------------------------

func test_deflection_adds_dodge_per_rank_and_undo_removes_it() -> void:
	var p := _warrior()
	var dodge := p.stats.get_raw(Stats.DODGE)
	_add(p, "deflection", 3)
	check_eq(p.stats.get_raw(Stats.DODGE), dodge + 6.0, "+2% per rank")
	check(p.talents.remove(&"warrior_arms_deflection"), "X takes a point back")
	check_eq(p.stats.get_raw(Stats.DODGE), dodge + 4.0, "rank 2")
	p.talents.remove(&"warrior_arms_deflection")
	p.talents.remove(&"warrior_arms_deflection")
	check_eq(p.stats.get_raw(Stats.DODGE), dodge, "all back")


func test_tactical_mastery_rage_generation_and_start_rage_hand_off() -> void:
	var p := _warrior()
	var rage := p.abilities.get_resource(&"rage")
	_add(p, "tactical_mastery", 2)
	check_eq(p.stats.get_raw(Stats.RESOURCE_REGEN), 6.0, "+3% Rage generation per rank")
	check_eq(rage.bonus, {"start_value_add": 10.0}, "+5 start Rage per rank reaches ClassResource.set_bonus")
	p.abilities._physics_process(0.001)  # the runner applies Resource Regen to the bar
	rage.set_value(0.0)
	rage.on_weapon_hit(false)
	check_near(rage.value, rage.data.gain_on_hit * 1.06, 0.0001, "a weapon hit gives 6% more Rage")
	p.talents.remove(&"warrior_arms_tactical_mastery")
	p.talents.remove(&"warrior_arms_tactical_mastery")
	check_eq(rage.bonus, {}, "undone")


func test_improved_charge_changes_the_charge_params() -> void:
	var p := _warrior()
	var charge := Db.get_ability(&"charge")
	var base := p.abilities.params_for(charge)
	_add(p, "deflection", 3)
	_add(p, "improved_charge", 3)
	var params := p.abilities.params_for(charge)
	check_near(float(params["stun"]), float(base["stun"]) + 0.9, 0.0001, "+0.3 sec stun per rank")
	check_near(float(params["cooldown"]), float(base["cooldown"]) - 1.5, 0.0001, "-0.5 sec cooldown per rank")
	check_eq(p.talents.tree_of(&"warrior_arms_improved_charge").get_talent(&"warrior_arms_improved_charge").text_for_rank(3),
		"Charge stuns 0.9 sec longer and recharges 1.5 sec faster.", "text at rank 3")


func test_two_handed_specialization_needs_a_two_hander() -> void:
	var p := _warrior()
	_add(p, "deflection", 3)
	_add(p, "tactical_mastery", 3)
	_add(p, "two_handed_specialization", 2)
	check_eq(p.bonuses.damage_mult(null, &"physical", &"weapon"), 1.0, "a sword: nothing")
	var axe := ItemInstance.from_weapon(Db.get_weapon(&"two_hand_axe"), Items.Rarity.COMMON, 1, false)
	p.equipment.add_to_backpack(axe)
	check(p.equipment.equip(axe), "two-hander")
	check_near(p.bonuses.damage_mult(null, &"fire", &"dot"), 1.10, 0.0001, "+5% per rank, every damage")
	check_near(p.outgoing_damage_mult(null, &"physical", &"ability"), 1.10, 0.0001, "in the outgoing multiplier")


func test_impale_needs_deep_wounds_and_adds_crit_damage() -> void:
	var p := _warrior()
	var crit_damage := p.stats.get_raw(Stats.CRIT_DAMAGE)
	_add(p, "deflection", 3)
	_add(p, "tactical_mastery", 3)
	_add(p, "improved_charge", 3)
	_add(p, "deep_wounds", 2)
	check_eq(p.talents.add_block_reason(&"warrior_arms_impale"), "Requires Deep Wounds", "prerequisite")
	_add(p, "deep_wounds")
	_add(p, "impale", 3)
	check_eq(p.stats.get_raw(Stats.CRIT_DAMAGE), crit_damage + 30.0, "+10% crit damage per rank")


func test_proc_talents_reach_the_proc_system() -> void:
	var p := _warrior()
	var procs := HandOffProcs.new()
	procs.player = p
	nodes.append(procs)
	p.procs = procs
	_add(p, "deflection", 3)
	_add(p, "tactical_mastery", 3)
	_add(p, "deep_wounds", 2)
	_add(p, "sweeping_blows")
	_add(p, "improved_charge", 2)
	_add(p, "sudden_death", 3)
	var defs: Array = procs.last_defs.get(PlayerBonuses.SOURCE_TALENTS, [])
	check_eq(defs.size(), 3, "Deep Wounds, Sweeping Blows, Sudden Death")
	var by_id := {}
	for d: Dictionary in defs:
		by_id[d["id"]] = d
	var dw: Dictionary = by_id.get("warrior_arms_deep_wounds", {})
	check(dw.get("trigger") == "on_crit" and dw.get("effect") == "dot" and dw.get("school") == "physical", "Deep Wounds: a bleed on crits")
	check_eq(dw.get("hit_pct"), 20.0, "10% of the hit per rank")
	check_eq(dw.get("duration"), 3.0, "over 3 sec")
	check_eq(dw.get("label"), "Deep Wounds", "named after the talent")
	var sb: Dictionary = by_id.get("warrior_arms_sweeping_blows", {})
	check(sb.get("trigger") == "on_cast" and sb.get("ability") == "whirlwind" and sb.get("effect") == "buff", "Sweeping Blows: after Whirlwind")
	check(sb.get("stats", {}).get("extra_attack") == 25.0 and sb.get("duration") == 5.0, "25% extra attacks for 5 sec")
	check_eq(sb.get("label"), "", "silent")
	var sd: Dictionary = by_id.get("warrior_arms_sudden_death", {})
	check(sd.get("trigger") == "on_hit" and sd.get("effect") == "cooldown" and sd.get("ability") == "execute" and sd.get("reset") == true, "Sudden Death resets Execute")
	check_eq(sd.get("chance"), 9.0, "3% per rank")


# --- Mortal Strike -----------------------------------------------------------------------------

func test_mortal_strike_counts_attacks_and_strikes_every_fifth() -> void:
	var p := _warrior()
	_to_capstone(p)
	var ms := _mortal_strike(p)
	check(ms != null, "the capstone script runs")
	var e := Fakes.spawn_enemy(world, Vector3(1.2, 0, 0))
	for i in 4:
		p.bonuses.on_hit(e, 5.0, false, true)
		for j in 3:
			p.bonuses.on_hit(e, 5.0, false, false)  # further enemies of the same swing
	check_eq(e.fake_hits(), 0, "four attacks (16 hits): no strike yet")
	var state := RunState.rng.state
	p.bonuses.on_hit(e, 5.0, false, true)
	check_eq(e.fake_hits(), 1, "the 5th attack strikes")
	check_near(e.fake_damage_log[0], WarriorKit.weapon_damage(p) * 1.5, 0.0001, "150% weapon damage (built from stats)")
	check_eq(e.fake_attacker_log[0], p, "dealt by the hero")
	check_eq(RunState.rng.state, state, "no RNG")
	check(ms.is_wounded(e), "Mortal Wound")
	check_eq(e.heal_reduction_pct, 50.0, "heals 50% less")
	check_eq(e.heal_reduction_left, 8.0, "for 8 sec")
	e.hp = 500.0
	check_near(e.heal(100.0), 50.0, 0.0001, "Enemy.heal halved (Vampiric elites)")
	check_eq(ms.attacks, 0, "counter restarts")
	for i in 5:
		p.bonuses.on_hit(e, 5.0, false, true)
	check_eq(e.fake_hits(), 2, "every 5th attack")


func test_mortal_wound_raises_your_damage_and_expires() -> void:
	var p := _warrior()
	_to_capstone(p)
	var ms := _mortal_strike(p)
	var e := Fakes.spawn_enemy(world, Vector3(1.2, 0, 0))
	var other := Fakes.spawn_enemy(world, Vector3(-1.2, 0, 0))
	for i in 5:
		p.bonuses.on_hit(e, 5.0, false, true)
	check_near(p.bonuses.damage_mult(e, &"physical", &"ability"), 1.10, 0.0001, "+10% damage taken from you (Execute too)")
	check_near(p.outgoing_damage_mult(e, &"fire", &"dot"), 1.10, 0.0001, "every source")
	check_eq(p.bonuses.damage_mult(other, &"physical", &"weapon"), 1.0, "only the wounded enemy")
	p.bonuses.tick(7.9)
	check(ms.is_wounded(e), "still wounded at 7.9 sec")
	p.bonuses.tick(0.2)
	check(not ms.is_wounded(e), "8 sec later the wound is gone")
	check_eq(p.bonuses.damage_mult(e, &"physical", &"weapon"), 1.0, "bonus gone")


func test_mortal_strike_on_real_swings_counts_attacks_not_enemies() -> void:
	var p := _warrior()
	_to_capstone(p)
	var a := Fakes.spawn_enemy(world, Vector3(1.2, 0, 0))
	var b := Fakes.spawn_enemy(world, Vector3(1.2, 0, 0.5))
	var c := Fakes.spawn_enemy(world, Vector3(1.2, 0, -0.5))
	EnemyGrid.mark_dirty()
	for i in 4:
		p.weapons[0].attack(a)
	check(a.fake_hits() == 4 and b.fake_hits() == 4 and c.fake_hits() == 4, "four swings hit all three")
	p.weapons[0].attack(a)
	check_eq(a.fake_hits(), 6, "the 5th swing + the strike on its target")
	check(b.fake_hits() == 5 and c.fake_hits() == 5, "no strike on the others")
	check_eq(_mortal_strike(p).strikes, 1, "one strike for five swings over three enemies")


func test_mortal_strike_is_held_when_the_target_died() -> void:
	var p := _warrior()
	_to_capstone(p)
	var ms := _mortal_strike(p)
	var dead := Fakes.spawn_enemy(world, Vector3(1.2, 0, 0))
	var alive := Fakes.spawn_enemy(world, Vector3(-1.2, 0, 0))
	for i in 4:
		p.bonuses.on_hit(alive, 5.0, false, true)
	dead.fake_dead = true
	p.bonuses.on_hit(dead, 5.0, false, true)
	check(dead.fake_hits() == 0 and ms.strikes == 0, "no strike on a corpse")
	p.bonuses.on_hit(alive, 5.0, false, true)
	check_eq(alive.fake_hits(), 1, "the held strike lands on the next attack")
	check_eq(ms.attacks, 0, "then the count restarts")


func test_mortal_strike_resets_each_wave_and_goes_away_on_reset() -> void:
	var p := _warrior()
	_to_capstone(p)
	var ms := _mortal_strike(p)
	var e := Fakes.spawn_enemy(world, Vector3(1.2, 0, 0))
	for i in 5:
		p.bonuses.on_hit(e, 5.0, false, true)
	p.bonuses.on_hit(e, 5.0, false, true)
	check(ms.attacks == 1 and ms.is_wounded(e), "one attack counted, one wound")
	p.begin_wave()
	check(ms.attacks == 0 and not ms.is_wounded(e), "a new wave clears both")
	check(_mortal_strike(p) == ms, "the same instance across the wave start (commit does not rebuild)")
	for i in 5:
		p.bonuses.on_hit(e, 5.0, false, true)
	RunState.add_gold(100)
	check(p.talents.try_reset(0), "Reset Talents")
	check(_mortal_strike(p) == null and p.bonuses.scripts().is_empty(), "the capstone is gone")
	check(not ms.is_wounded(e), "torn down: no wounds left")
	check_eq(p.bonuses.damage_mult(e, &"physical", &"weapon"), 1.0, "no bonus left")
