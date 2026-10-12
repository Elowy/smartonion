extends TestCase
## Warrior Protection talents (M5 Wave 2, talents_warrior.md §3): every talent through
## player.talents.add -> PlayerBonuses on a real Warrior (stats with and without a shield,
## Revenge's counters, Defiance's Rage rules, Blood and Thunder's params and slow), the
## Challenging Charge kit hook (WarriorCharge: taunts, absorb shield, release on down / wave),
## the Unbreakable capstone (WarriorProtectionUnbreakable: the once-per-wave save, Max HP for
## the hero and allies, Shield Wall "Last Stand" priority, cleanup) and the Protection bot paths.

const Fakes := preload("res://tests/player_fakes.gd")
const EFakes := preload("res://tests/enemies_fakes.gd")
const DT := 1.0 / 60.0
const UNBREAKABLE_ID := &"warrior_protection_unbreakable"
const REVENGE_ID := &"warrior_protection_revenge"

## The Protection bot with a sword and no shield (talents_warrior.md 5.4): the two shield
## talents are deferred, then Arms.
const PROTECTION_PATH: Array[StringName] = [
	&"warrior_protection_toughness", &"warrior_protection_toughness", &"warrior_protection_toughness",
	&"warrior_protection_revenge", &"warrior_protection_revenge", &"warrior_protection_revenge",
	&"warrior_protection_challenging_charge",
	&"warrior_protection_defiance", &"warrior_protection_defiance", &"warrior_protection_defiance",
	&"warrior_protection_vitality", &"warrior_protection_vitality",
	&"warrior_protection_unbreakable",
	&"warrior_protection_blood_and_thunder", &"warrior_protection_blood_and_thunder", &"warrior_protection_blood_and_thunder",
	&"warrior_arms_deflection", &"warrior_arms_deflection", &"warrior_arms_deflection",
]
## ... and with a shield: every point in Protection.
const SHIELD_PATH: Array[StringName] = [
	&"warrior_protection_toughness", &"warrior_protection_toughness", &"warrior_protection_toughness",
	&"warrior_protection_shield_specialization", &"warrior_protection_shield_specialization", &"warrior_protection_shield_specialization",
	&"warrior_protection_challenging_charge",
	&"warrior_protection_revenge", &"warrior_protection_revenge", &"warrior_protection_revenge",
	&"warrior_protection_defiance", &"warrior_protection_defiance",
	&"warrior_protection_unbreakable",
	&"warrior_protection_defiance",
	&"warrior_protection_vitality", &"warrior_protection_vitality",
	&"warrior_protection_shield_mastery", &"warrior_protection_shield_mastery", &"warrior_protection_shield_mastery",
	&"warrior_protection_blood_and_thunder", &"warrior_protection_blood_and_thunder", &"warrior_protection_blood_and_thunder",
]

var world: Node3D


func before_each() -> void:
	PlayerManager.clear()
	RunState.start_run(1, 4242)
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
	var id := StringName("warrior_protection_" + short)
	for i in n:
		check(p.talents.add(id), "add %s: %s" % [short, p.talents.add_block_reason(id)])


func _remove(p: Player, short: String, n: int = 1) -> void:
	var id := StringName("warrior_protection_" + short)
	for i in n:
		check(p.talents.remove(id), "remove %s: %s" % [short, p.talents.remove_block_reason(id)])


## The 12 points that open the capstone without a shield (talents_warrior.md 5.2) + Unbreakable.
func _to_capstone(p: Player) -> void:
	_add(p, "toughness", 3)
	_add(p, "revenge", 3)
	_add(p, "defiance", 3)
	_add(p, "vitality", 2)
	_add(p, "challenging_charge")
	_add(p, "unbreakable")


func _unbreakable(p: Player) -> WarriorProtectionUnbreakable:
	return p.bonuses.script_for(UNBREAKABLE_ID) as WarriorProtectionUnbreakable


func _fake(pos: Vector3) -> Fakes.FakeEnemy:
	var e := Fakes.spawn_enemy(world, pos)
	EnemyGrid.mark_dirty()
	return e


func _rage(p: Player) -> ClassResource:
	return p.abilities.get_resource(&"rage")


func _shield() -> ItemInstance:
	return ItemInstance.from_weapon(Db.get_weapon(&"shield"), Items.Rarity.COMMON, 1, false)


func _equip_shield(p: Player) -> void:
	var s := _shield()
	p.equipment.add_to_backpack(s)
	check(p.equipment.equip(s, Items.EquipSlot.OFF_HAND), "a shield in the off hand")
	check(PlayerBonuses.weapon_requirement_met(p, &"shield"), "shield requirement met")


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


## A hit far above the hero's HP (projectile: no parry roll; the hero has no dodge or shield).
func _lethal(p: Player) -> void:
	p.invulnerable_left = 0.0
	p.take_damage(p.hp + p.max_hp() + 1000.0, CombatMath.KIND_PROJECTILE, null)


## Charges along +X and lets the dash land.
func _charge(p: Player) -> void:
	(p.slot.input as ScriptedInput).move = Vector2(1.0, 0.0)
	check(p.abilities.try_cast(1), "Charge")
	_step(p, 0.4)
	var ch := p.abilities.effect_for(p.abilities.slots[1]) as WarriorCharge
	check(not ch.is_dashing(), "landed")


static func _path(p: Player, slot_index: int, limit: int = 100) -> Array[StringName]:
	var out: Array[StringName] = []
	for i in limit:
		var t := TalentBot.next_talent(p, slot_index)
		if t == null or not p.talents.add(t.id):
			break
		out.append(t.id)
	return out


# --- Tree data ---------------------------------------------------------------------------

func test_protection_tree_data() -> void:
	var prot := Db.get_talent_tree(&"warrior_protection")
	check(prot != null, "warrior_protection in Db")
	if prot == null:
		return
	check(prot.class_id == &"warrior" and prot.index == 2 and prot.display_name == "Protection", "Warrior tree 3")
	var ids: Array[StringName] = []
	for t in prot.talents:
		ids.append(t.id)
	check_eq(ids, [&"warrior_protection_toughness", &"warrior_protection_shield_specialization",
		&"warrior_protection_revenge", &"warrior_protection_defiance", &"warrior_protection_vitality",
		&"warrior_protection_challenging_charge", &"warrior_protection_shield_mastery",
		&"warrior_protection_blood_and_thunder", UNBREAKABLE_ID] as Array[StringName], "ids")
	var toughness := prot.get_talent(&"warrior_protection_toughness")
	var spec := prot.get_talent(&"warrior_protection_shield_specialization")
	check(toughness.tier == 1 and toughness.column == 0, "Toughness: tier 1, column 0 (the style-free start)")
	check(spec.tier == 1 and spec.column == 1, "Shield Specialization: column 1")
	check_eq(prot.get_talent(&"warrior_protection_shield_mastery").prerequisite, spec.id, "Shield Mastery needs Shield Specialization")
	check_eq(prot.get_talent(&"warrior_protection_challenging_charge").ability, &"charge", "the modifier changes Charge")
	check(prot.get_talent(UNBREAKABLE_ID).is_capstone(), "Unbreakable is the capstone")
	check_eq(prot.get_talent(&"warrior_protection_defiance").text_for_rank(3),
		"Taking damage generates 6 more Rage, and your Rage decays 3 less per second out of combat.", "rank text")


# --- Tier 1-4 ----------------------------------------------------------------------------

func test_toughness_adds_armor_per_rank() -> void:
	var p := _warrior()
	var armor := p.stats.get_raw(Stats.ARMOR)
	_add(p, "toughness", 3)
	check_eq(p.stats.get_raw(Stats.ARMOR), armor + 6.0, "+2 Armor per rank")
	_remove(p, "toughness", 2)
	check_eq(p.stats.get_raw(Stats.ARMOR), armor + 2.0, "rank 1")
	_remove(p, "toughness")
	check_eq(p.stats.get_raw(Stats.ARMOR), armor, "all back")


func test_shield_specialization_needs_a_shield() -> void:
	var p := _warrior()
	_add(p, "shield_specialization", 3)
	check_eq(p.stats.get_raw(Stats.BLOCK_CHANCE), 0.0, "a sword alone: no block")
	check_eq(p.block_chance(), 0.0, "no block chance")
	_equip_shield(p)
	check_eq(p.stats.get_raw(Stats.BLOCK_CHANCE), 9.0, "+3% block per rank with a shield")
	check_eq(p.stats.get_raw(Stats.BLOCK_VALUE), 30.0, "+10% Block Value per rank")
	check_near(p.block_chance(), 19.0, 0.0001, "the shield's 10% + 9%")
	check(p.equipment.unequip(Items.EquipSlot.OFF_HAND), "shield off")
	check_eq(p.block_chance(), 0.0, "off again")
	check_eq(p.stats.get_raw(Stats.BLOCK_VALUE), 0.0, "no Block Value either")


func test_revenge_adds_parry_and_hands_its_counters_to_the_procs() -> void:
	var p := _warrior()
	_add(p, "toughness", 3)
	_add(p, "revenge", 3)
	check_eq(p.stats.get_raw(Stats.PARRY), 6.0, "+2% Parry per rank")
	var defs := p.procs.extra_defs(PlayerBonuses.SOURCE_TALENTS)
	check_eq(defs.size(), 2, "a block counter and a dodge counter")
	var triggers: Array[String] = []
	for d: Dictionary in defs:
		var proc: Dictionary = d.get("proc", d)
		triggers.append(str(proc.get("trigger")))
		check(proc.get("effect") == "extra_attack" and proc.get("chance") == 45.0 and proc.get("icd") == 0.5,
			"an instant weapon swing, 15% per rank, 0.5 sec internal cooldown")
		check_eq(proc.get("label"), "", "silent")
	triggers.sort()
	check_eq(triggers, ["on_block", "on_dodge"] as Array[String], "on block and on dodge")
	_remove(p, "revenge", 3)
	check_eq(p.stats.get_raw(Stats.PARRY), 0.0, "parry gone")
	check(p.procs.extra_defs(PlayerBonuses.SOURCE_TALENTS).is_empty(), "counters gone")


func test_revenge_strikes_back_at_the_attacker() -> void:
	var p := _warrior()
	_add(p, "toughness", 3)
	_add(p, "revenge", 1)
	var counters := 0
	for proc in p.procs.procs:
		if proc.id == REVENGE_ID:
			counters += 1
			check_eq(proc.chance, 15.0, "rank 1: 15%")
			proc.chance = 100.0  # test override: always
	check_eq(counters, 2, "both counters are live procs")
	var attacker := _fake(Vector3(1.2, 0, 0))
	p.procs.on_avoided(&"block", attacker)
	check_eq(attacker.fake_hits(), 1, "a block: one swing back at the attacker")
	p.procs.on_avoided(&"block", attacker)
	check_eq(attacker.fake_hits(), 1, "not again within 0.5 sec")
	p.procs.on_avoided(&"dodge", attacker)
	check_eq(attacker.fake_hits(), 2, "a dodge has its own counter")
	Fakes.step(p.procs, 0.55)
	p.procs.on_avoided(&"block", attacker)
	check_eq(attacker.fake_hits(), 3, "ready again after 0.5 sec")
	var far := _fake(Vector3(0, 0, 15))
	Fakes.step(p.procs, 0.55)
	p.procs.on_avoided(&"block", far)
	check_eq(far.fake_hits(), 0, "an attacker out of reach is simply missed")
	# Through real blocked hits.
	_equip_shield(p)
	for proc in p.procs.procs:
		if proc.id == REVENGE_ID:
			proc.chance = 100.0
	p.stats.set_source(&"test", {Stats.BLOCK_CHANCE: 40.0})
	var before := attacker.fake_hits()
	var fired := p.procs.fire_count(REVENGE_ID)
	for i in 30:
		p.invulnerable_left = 0.0
		p.hp = p.max_hp()
		p.take_damage(1.0, CombatMath.KIND_PROJECTILE, attacker)
		Fakes.step(p.procs, 0.55, 0.55)
	var counted := p.procs.fire_count(REVENGE_ID) - fired
	check(counted > 5 and counted < 25, "about half of 30 hits blocked (%d)" % counted)
	check_eq(attacker.fake_hits() - before, counted, "every block struck back")


func test_defiance_rage_from_hits_and_no_decay_at_three() -> void:
	var p := _warrior()
	var rage := _rage(p)
	_add(p, "toughness", 3)
	_add(p, "defiance", 2)
	check_eq(rage.bonus, {"decay_per_second_add": -2.0, "gain_on_damage_taken_add": 4.0}, "resource bonus at rank 2")
	check_eq(rage.gain_on_damage_taken(), 14.0, "10 + 2 per rank")
	check_eq(rage.decay_per_second(), 1.0, "3 - 1 per rank")
	_add(p, "defiance")
	check_eq(rage.decay_per_second(), 0.0, "rank 3: no decay")
	rage.set_value(0.0)
	p.take_damage(1.0, CombatMath.KIND_PROJECTILE, null)
	check_near(rage.value, 16.0, 0.0001, "a hit taken: 10 + 6 Rage")
	rage.set_value(50.0)
	rage.tick(10.0)
	check_eq(rage.value, 50.0, "out of combat the Rage stays")
	_remove(p, "defiance", 3)
	check_eq(rage.bonus, {}, "undone")
	check_eq(rage.decay_per_second(), 3.0, "decays again")


func test_vitality_adds_stamina_and_strength() -> void:
	var p := _warrior()
	var max_hp := p.max_hp()
	var strength := p.stats.get_raw(Stats.STRENGTH)
	_add(p, "toughness", 3)
	_add(p, "revenge", 3)
	_add(p, "vitality", 2)
	check_eq(p.max_hp(), max_hp + 8.0, "+4 Stamina per rank = +4 Max HP")
	check_eq(p.stats.get_raw(Stats.STRENGTH), strength + 2.0, "+1 Strength per rank")
	_remove(p, "vitality", 2)
	check_eq(p.max_hp(), max_hp, "undone")


func test_shield_mastery_needs_shield_specialization_and_a_shield() -> void:
	var p := _warrior()
	_add(p, "toughness", 3)
	_add(p, "shield_specialization", 2)
	_add(p, "revenge", 3)
	_add(p, "defiance", 1)
	check_eq(p.talents.add_block_reason(&"warrior_protection_shield_mastery"), "Requires Shield Specialization", "prerequisite")
	_add(p, "shield_specialization")
	_add(p, "shield_mastery", 3)
	check_eq(p.bonuses.damage_taken_mult(CombatMath.KIND_MELEE, null), 1.0, "no shield: nothing")
	_equip_shield(p)
	check_near(p.bonuses.damage_taken_mult(CombatMath.KIND_PROJECTILE, null), 0.88, 0.0001, "-4% per rank with a shield")
	check(p.equipment.unequip(Items.EquipSlot.OFF_HAND), "shield off")
	check_eq(p.bonuses.damage_taken_mult(CombatMath.KIND_MELEE, null), 1.0, "off again")


func test_blood_and_thunder_powers_whirlwind_and_thunder_clap_and_slows() -> void:
	var p := _warrior()
	var ww := Db.get_ability(&"whirlwind")
	var tc := Db.get_ability(&"thunder_clap")
	var tc_slow := float(p.abilities.params_for(tc)["slow"])
	_add(p, "toughness", 3)
	_add(p, "revenge", 3)
	_add(p, "defiance", 3)
	_add(p, "blood_and_thunder", 3)
	var params := p.abilities.params_for(ww)
	check_near(float(params["power"]), 1.15, 0.0001, "Whirlwind +5% power per rank")
	check_near(float(params["slow"]), 30.0, 0.0001, "and a 10% slow per rank")
	check_near(float(params["slow_duration"]), 1.5, 0.0001, "for 1.5 sec")
	check(not p.abilities.knows(&"thunder_clap"), "Thunder Clap not learned")
	var tc_params := p.abilities.params_for(tc)
	check_near(float(tc_params["power"]), 1.15, 0.0001, "Thunder Clap +5% power per rank")
	check_eq(float(tc_params["slow"]), tc_slow, "Thunder Clap's own slow untouched")
	var e := _fake(Vector3(1.5, 0, 0))
	_rage(p).set_value(100.0)
	check(p.abilities.try_cast(0), "spin")
	check_near(e.slow_pct, 30.0, 0.0001, "the spin slows by 30%")
	check_near(e.slow_left, 1.5, 0.0001, "for 1.5 sec")
	check_near(e.fake_damage_log[0], WarriorKit.weapon_damage(p) * 1.5 * 1.15 / 4.0, 0.01, "15% stronger")
	_remove(p, "blood_and_thunder", 3)
	check_eq(float(p.abilities.params_for(ww)["slow"]), 0.0, "no slow without it")


# --- Challenging Charge ------------------------------------------------------------------

func test_charge_without_the_modifier_neither_taunts_nor_shields() -> void:
	var p := _warrior()
	var params := p.abilities.params_for(Db.get_ability(&"charge"))
	check(float(params["taunt"]) == 0.0 and float(params["shield_per_enemy"]) == 0.0, "neutral defaults")
	var e := _fake(Vector3(7.5, 0, 0.3))
	_charge(p)
	check(e.fake_stun_count > 0, "stunned at the landing")
	check(not e.is_taunted(), "no taunt")
	check_eq(p.procs.shield_of(WarriorCharge.SHIELD_SOURCE), 0.0, "no shield")
	check_eq(_texts(WarriorCharge.CHALLENGE_TEXT), 0, "no challenge text")


func test_challenging_charge_taunts_and_shields() -> void:
	var p := _warrior()
	_to_capstone(p)
	var params := p.abilities.params_for(Db.get_ability(&"charge"))
	check(float(params["taunt"]) == 4.0 and float(params["shield_per_enemy"]) == 3.0, "+4 sec taunt, 3% shield per enemy")
	var path := _fake(Vector3(3.0, 0, 0.3))
	var landing := [_fake(Vector3(7.8, 0, 0.6)), _fake(Vector3(8.2, 0, -0.6))]
	var off := _fake(Vector3(0, 0, 8))
	_charge(p)
	var ch := p.abilities.effect_for(p.abilities.slots[1]) as WarriorCharge
	for e: Fakes.FakeEnemy in [path, landing[0], landing[1]]:
		check(e.is_taunted() and e.taunt_target == p, "a stunned enemy is taunted to the Warrior")
		check(e.taunt_left > 4.9 and e.taunt_left <= 5.0, "for the 1 sec stun + 4 sec (%.2f)" % e.taunt_left)
	check(not off.is_taunted(), "an enemy off the path is left alone")
	check_eq(ch.taunted().size(), 3, "three taunted")
	check_near(p.procs.shield_of(WarriorCharge.SHIELD_SOURCE), p.max_hp() * 0.09, 0.0001, "3 enemies x 3% Max HP")
	check_eq(_texts(WarriorCharge.CHALLENGE_TEXT), 1, "\"Challenge!\" once")
	# A second Charge (no cooldown in the test) tops the shield up to the 15% cap, not past it.
	p.abilities.set_cooldown(Db.get_ability(&"charge"), 0.0)
	p.global_position = Vector3(1.0, 0, 0)
	_charge(p)
	check_near(p.procs.shield_of(WarriorCharge.SHIELD_SOURCE), p.max_hp() * 0.15, 0.0001, "at most 15% Max HP")
	var absorbed_before := p.procs.absorbed_total
	p.invulnerable_left = 0.0
	p.take_damage(1.0, CombatMath.KIND_PROJECTILE, null)
	check(p.procs.absorbed_total > absorbed_before, "the shield absorbs hits")


func test_challenging_charge_taunts_end_when_the_warrior_goes_down() -> void:
	var p := _warrior()
	var other := _warrior(1, Vector3(-5, 0, 0))
	_to_capstone(p)
	var a := _fake(Vector3(7.8, 0, 0.6))
	var b := _fake(Vector3(8.2, 0, -0.6))
	_charge(p)
	check(a.is_taunted() and b.is_taunted(), "both taunted")
	b.apply_taunt(other, 10.0)
	check(b.taunt_target == other, "b re-taunted by another hero")
	p.procs.clear_shields()
	_lethal(p)
	check(p.downed or _unbreakable(p).used, "the lethal hit")
	if not p.downed:
		_lethal(p)  # Unbreakable saved the first one
	check(p.downed, "the Warrior is down")
	check(not a.is_taunted() and a.taunt_target == null, "its taunt is released (no crowd camping the body)")
	check(b.is_taunted() and b.taunt_target == other, "another hero's taunt keeps running")


func test_challenging_charge_taunts_end_with_the_wave() -> void:
	var p := _warrior()
	_to_capstone(p)
	var a := _fake(Vector3(7.8, 0, 0.6))
	_charge(p)
	check(a.is_taunted(), "taunted")
	p.end_wave()
	check(not a.is_taunted(), "end_wave releases it")
	p.global_position = Vector3.ZERO
	p.begin_wave()
	_charge(p)
	check(a.is_taunted(), "taunted again")
	check(p.procs.shield_of(WarriorCharge.SHIELD_SOURCE) > 0.0, "shielded")
	p.begin_wave()
	check(not a.is_taunted(), "begin_wave releases it")
	check_eq(p.procs.shield_of(WarriorCharge.SHIELD_SOURCE), 0.0, "and the shield is gone (ProcSystem.begin_wave)")


# --- Unbreakable -------------------------------------------------------------------------

func test_unbreakable_saves_once_per_wave() -> void:
	var p := _warrior()
	_to_capstone(p)
	var u := _unbreakable(p)
	check(u != null, "the capstone script runs")
	check_eq(u.describe(), "Unbreakable: ready", "ready")
	var max_hp := p.max_hp()
	var state := RunState.rng.state
	_lethal(p)
	check(not p.downed, "the lethal hit leaves the Warrior standing")
	check(u.used and u.is_active(), "used, running")
	check_near(p.max_hp(), max_hp * 1.3, 0.0001, "+30% Max HP")
	check_near(p.hp, 1.0 + max_hp * 0.3, 0.0001, "healed by the gain from 1 HP")
	check(p.invulnerable_left >= 1.0, "1 sec invulnerable")
	check_eq(_texts("Unbreakable!"), 1, "the shout")
	check(p.get_node_or_null("UnbreakableRing") != null, "the golden ring")
	check_eq(RunState.rng.state, state, "no RNG of its own")
	check_eq(u.describe(), "Unbreakable: 10 s", "describe while running")
	_lethal(p)
	check(p.downed, "a second lethal hit in the same wave downs")
	p.bonuses.tick(DT)
	check(not u.is_active() and not p.stats.has_source(u.self_key), "down: the bonus ends")
	check_eq(u.describe(), "Unbreakable: used this wave", "used")
	p.begin_wave()
	check(not p.downed and not u.used, "a new wave re-arms it")
	check_near(p.max_hp(), max_hp, 0.0001, "normal Max HP")
	_lethal(p)
	check(not p.downed and u.saves == 2, "saves again")


func test_unbreakable_lasts_ten_seconds_and_lifts_allies_in_range() -> void:
	var p := _warrior(0)
	var near := _warrior(1, Vector3(5, 0, 0))
	var far := _warrior(2, Vector3(0, 0, 9))
	_to_capstone(p)
	var u := _unbreakable(p)
	var near_max := near.max_hp()
	var far_max := far.max_hp()
	near.hp = 10.0
	var max_hp := p.max_hp()
	_lethal(p)
	check_near(near.max_hp(), near_max * 1.15, 0.0001, "an ally at 5 m: +15% Max HP")
	check_near(near.hp, 10.0 + near_max * 0.15, 0.0001, "and healed by it")
	check_eq(far.max_hp(), far_max, "an ally at 9 m: nothing")
	check_eq(u.allies().size(), 1, "one ally")
	check_eq(u.ally_key, &"warrior_protection_unbreakable:0", "its own key per Warrior")
	p.bonuses.tick(9.9)
	check(u.is_active() and p.max_hp() > max_hp, "still running at 9.9 sec")
	p.bonuses.tick(0.2)
	check(not u.is_active(), "over after 10 sec")
	check_near(p.max_hp(), max_hp, 0.0001, "the Warrior's bonus is gone")
	check_near(near.max_hp(), near_max, 0.0001, "the ally's too")
	check(p.hp <= p.max_hp() and near.hp <= near.max_hp(), "HP clamps to the normal maximum")
	check(not p.stats.has_source(u.self_key) and not near.stats.has_source(u.ally_key), "no source left")
	var ring := p.get_node_or_null("UnbreakableRing") as WarriorAuraVfx
	check(ring == null or ring.is_dismissed(), "the ring fades out")


func test_unbreakable_ally_going_down_loses_the_bonus() -> void:
	var p := _warrior(0)
	var ally := _warrior(1, Vector3(3, 0, 0))
	_to_capstone(p)
	var u := _unbreakable(p)
	_lethal(p)
	check(ally.stats.has_source(u.ally_key), "the ally holds it")
	ally.invulnerable_left = 0.0
	ally.take_damage(ally.max_hp() * 3.0, CombatMath.KIND_PROJECTILE, null)
	check(ally.downed, "the ally is down")
	p.bonuses.tick(DT)
	check(not ally.stats.has_source(u.ally_key), "a downed ally loses it")
	check(u.is_active(), "the Warrior keeps its own")
	p.end_wave()
	check(not u.is_active() and not p.stats.has_source(u.self_key), "end_wave: the market shows normal Max HP")


func test_unbreakable_defers_to_shield_walls_last_stand() -> void:
	var p := _warrior()
	_to_capstone(p)
	var u := _unbreakable(p)
	var slot := p.abilities.learn(Db.get_ability(&"shield_wall"))
	check(slot >= 0, "learn Shield Wall")
	var entries: Array[Dictionary] = [{"kind": "ability", "match": {"id": "shield_wall"}, "mods": {"last_stand": true},
		"rank": 1, "id": "test", "label": "Test"}]
	p.bonuses.set_effects(&"test", entries)
	check(p.abilities.try_cast(slot), "Shield Wall with Last Stand")
	var wall := p.abilities.effect_for(p.abilities.slots[slot]) as WarriorShieldWall
	check(wall.guards_lethal(), "the wall guards lethal hits")
	_lethal(p)
	check(not p.downed, "saved")
	check_eq(wall.saves, 1, "by the wall")
	check(not u.used and not u.is_active(), "Unbreakable stays unused")
	wall.end()
	check(not wall.guards_lethal(), "the wall is down")
	_lethal(p)
	check(not p.downed and u.used, "now Unbreakable saves")


func test_unbreakable_teardown_removes_the_guard() -> void:
	var p := _warrior()
	var guards := p.death_guards.size()
	_to_capstone(p)
	var u := _unbreakable(p)
	check_eq(p.death_guards.size(), guards + 1, "one death guard")
	_lethal(p)
	check(p.stats.has_source(u.self_key), "running")
	p.end_wave()
	p.begin_wave()
	RunState.add_gold(100)
	check(p.talents.try_reset(0), "Reset Talents")
	check(_unbreakable(p) == null, "the capstone is gone")
	check_eq(p.death_guards.size(), guards, "the guard is gone")
	check(not p.stats.has_source(u.self_key), "no source left")
	_lethal(p)
	check(p.downed, "no more saves")


# --- Bot paths ---------------------------------------------------------------------------

func test_protection_bot_path_without_a_shield() -> void:
	RunState.set_start_level(28)
	var p := _warrior(2)
	check(p.off_hand == null, "no shield")
	var path := _path(p, 2)
	check_eq(path, PROTECTION_PATH, "Protection bot path (talents_warrior.md 5.4)")
	check_eq(path.find(&"warrior_protection_challenging_charge"), 6, "the modifier is point 7")
	check_eq(path.find(UNBREAKABLE_ID), 12, "the capstone is point 13")
	check_eq(p.talents.rank_of(&"warrior_protection_shield_specialization"), 0, "no dead points in Shield Specialization")
	check_eq(p.talents.rank_of(&"warrior_protection_shield_mastery"), 0, "nor in Shield Mastery")
	check(_unbreakable(p) != null, "Unbreakable runs")


func test_protection_bot_path_with_a_shield() -> void:
	var p := _warrior(2)
	_equip_shield(p)
	var path := _path(p, 2)
	check_eq(path, SHIELD_PATH, "with a shield every point goes to Protection")
	check_eq(path.find(UNBREAKABLE_ID), 12, "the capstone is point 13")
	check_eq(TalentBot.spend_all(p, 2), 0, "nothing left")
