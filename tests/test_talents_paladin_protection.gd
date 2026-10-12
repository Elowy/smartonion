extends TestCase
## Paladin Protection talents (M5 Wave 2, talents_paladin.md §2) through player.talents.add ->
## PlayerBonuses on a real Paladin: Redoubt, Stoicism, Consecrated Ground, Guarded by the
## Light, Ardent Defender, the Righteous Fury modifier (Consecration taunts + ward), Shield of
## the Templar, Reckoning and the Holy Shield capstone. Proc talents are fired through the real
## ProcSystem (chance forced to 100% where noted – a test override of the built proc).

const Fakes := preload("res://tests/player_fakes.gd")
const EFakes := preload("res://tests/enemies_fakes.gd")
const DT := 1.0 / 60.0
const RT := 0
const SHIELD_ID := &"paladin_protection_holy_shield"

var world: Node3D


func before_each() -> void:
	RunState.start_run(1, 777)
	RunState.set_start_level(31)
	world = EFakes.make_world(tree)
	EnemyGrid.mark_dirty()


func after_each() -> void:
	EFakes.free_world(tree, world)
	world = null
	EnemyGrid.mark_dirty()


func _paladin(pos: Vector3 = Vector3.ZERO, index: int = 0) -> Player:
	return Fakes.spawn_player(world, index, &"paladin", pos)


func _ally(index: int, pos: Vector3, class_id: StringName = &"warrior") -> Player:
	return Fakes.spawn_player(world, index, class_id, pos)


func _enemy(pos: Vector3) -> Fakes.FakeEnemy:
	var e := Fakes.spawn_enemy(world, pos)
	EnemyGrid.mark_dirty()
	return e


func _add(p: Player, name: String, n: int = 1) -> void:
	var id := StringName("paladin_protection_" + name)
	for i in n:
		check(p.talents.add(id), "add %s: %s" % [id, p.talents.add_block_reason(id)])


func _remove(p: Player, name: String, n: int = 1) -> void:
	var id := StringName("paladin_protection_" + name)
	for i in n:
		check(p.talents.remove(id), "remove %s: %s" % [id, p.talents.remove_block_reason(id)])


func _holy_power(p: Player) -> ClassResource:
	return p.abilities.get_resource(&"holy_power")


func _down(p: Player) -> void:
	p.invulnerable_left = 0.0
	p.hp = 1.0
	p.take_damage(1000.0)
	check(p.downed, "%s is down" % p.name)


func _areas() -> Array[AbilityArea]:
	var out: Array[AbilityArea] = []
	for node in tree.get_nodes_in_group(&"ability_areas"):
		var a := node as AbilityArea
		if a != null and not a.is_queued_for_deletion():
			out.append(a)
	return out


func _consecration(p: Player) -> PaladinConsecration:
	return p.abilities.effect_for(Db.get_ability(&"consecration")) as PaladinConsecration


func _step_abilities(p: Player, frames: int) -> void:
	for i in frames:
		p.abilities._physics_process(DT)


## The talent proc def of [param talent_id] as handed to ProcSystem ({} when none).
func _def(p: Player, talent_id: StringName) -> Dictionary:
	for d: Dictionary in p.procs.extra_defs(PlayerBonuses.SOURCE_TALENTS):
		if d.get("id") == String(talent_id):
			return d
	return {}


## Test override: every built proc of [param talent_id] fires on each qualifying event.
func _force(p: Player, talent_id: StringName) -> void:
	var found := false
	for pr in p.procs.procs:
		if pr.id == talent_id:
			pr.chance = 100.0
			found = true
	check(found, "%s is built" % talent_id)


func _swap_to_tome(p: Player) -> void:
	var tome := ItemInstance.from_weapon(Db.get_weapon(&"tome"), Items.Rarity.COMMON, 1, false)
	p.equipment.add_to_backpack(tome)
	check(p.equipment.equip(tome), "a Tome in the off hand")


## The 13-point shield path (talents_paladin.md 5.2): Redoubt 3, Stoicism 3, Consecrated
## Ground 3, Guarded by the Light 3, Holy Shield.
func _to_capstone(p: Player) -> void:
	_add(p, "redoubt", 3)
	_add(p, "stoicism", 3)
	_add(p, "consecrated_ground", 3)
	_add(p, "guarded_by_the_light", 3)
	_add(p, "holy_shield")


# --- Tier 1-2 ----------------------------------------------------------------------------------

func test_redoubt_needs_a_shield() -> void:
	var p := _paladin()
	var block_value := p.stats.get_raw(Stats.BLOCK_VALUE)
	check_eq(p.block_chance(), 10.0, "the shield's 10%")
	for n in range(1, 4):
		_add(p, "redoubt")
		check_eq(p.block_chance(), 10.0 + 3.0 * n, "+3% block per rank")
		check_eq(p.stats.get_raw(Stats.BLOCK_VALUE), block_value + 10.0 * n, "+10% Block Value per rank")
	var shield := p.equipment.get_item(Items.EquipSlot.OFF_HAND)
	_swap_to_tome(p)
	check_eq(p.block_chance(), 0.0, "a Tome: no block at all")
	check_eq(p.stats.get_raw(Stats.BLOCK_VALUE), block_value, "the entry is off")
	check(p.equipment.equip(shield), "the shield back")
	check_eq(p.block_chance(), 19.0, "on again")
	_remove(p, "redoubt", 3)
	check_eq(p.block_chance(), 10.0, "undone")


func test_stoicism_adds_stamina_and_armor() -> void:
	var p := _paladin()
	var max_hp := p.max_hp()
	var armor := p.stats.get_raw(Stats.ARMOR)
	_add(p, "stoicism", 3)
	check_eq(p.max_hp(), max_hp + 6.0, "+2 Stamina per rank")
	check_eq(p.stats.get_raw(Stats.ARMOR), armor + 3.0, "+1 Armor per rank")
	_remove(p, "stoicism", 3)
	check(is_equal_approx(p.max_hp(), max_hp) and is_equal_approx(p.stats.get_raw(Stats.ARMOR), armor), "undone")


func test_consecrated_ground_lengthens_consecration() -> void:
	var p := _paladin()
	var cons := Db.get_ability(&"consecration")
	_add(p, "stoicism", 3)
	for n in range(1, 4):
		_add(p, "consecrated_ground")
		check_eq(float(p.abilities.params_for(cons)["duration"]), 4.0 + 0.5 * n, "+0.5 sec per rank")
	check_eq(Db.get_talent(&"paladin_protection_consecrated_ground").text_for_rank(3),
		"Your Consecration lasts 1.5 sec longer.", "text at rank 3")
	check(p.abilities.try_cast(RT), "cast")
	check_near(_areas()[0].duration, 5.5, 0.0001, "the ground lasts 5.5 sec")


func test_guarded_by_the_light_gives_holy_power_on_blocks() -> void:
	var p := _paladin()
	var id := &"paladin_protection_guarded_by_the_light"
	var hp := _holy_power(p)
	var e := _enemy(Vector3(1.2, 0, 0))
	_add(p, "redoubt", 3)
	_add(p, "guarded_by_the_light", 3)
	var def := _def(p, id)
	check(def.get("trigger") == "on_block" and def.get("effect") == "resource" and def.get("resource") == "holy_power", "on_block Holy Power")
	check(def.get("chance") == 30.0 and def.get("icd") == 2.0 and def.get("value") == 1 and def.get("label") == "", "10% per rank, 2 sec icd, silent")
	_force(p, id)
	hp.set_value(0.0)
	p._avoided(&"dodge", e)
	check_eq(hp.value, 0.0, "a dodge is no block")
	p._avoided(&"block", e)
	check_eq(hp.value, 1.0, "a block: +1 Holy Power")
	p._avoided(&"block", e)
	check_eq(hp.value, 1.0, "within the 2 sec icd: nothing")
	p.procs._physics_process(2.1)
	p._avoided(&"block", e)
	check_eq(hp.value, 2.0, "after the icd again")


# --- Tier 3 ------------------------------------------------------------------------------------

func test_ardent_defender_heals_and_hardens_below_35_percent() -> void:
	var p := _paladin()
	_add(p, "redoubt", 3)
	_add(p, "stoicism", 3)
	_add(p, "ardent_defender", 2)
	var armor := p.stats.get_raw(Stats.ARMOR)
	p.hp = p.max_hp() * 0.3
	p.procs.on_struck(null, 1.0)
	check_near(p.hp, p.max_hp() * 0.46, 0.0001, "heals 8% of max HP per rank")
	check_eq(p.stats.get_raw(Stats.ARMOR), armor + 8.0, "+4 Armor per rank")
	p.procs._physics_process(8.1)
	check_eq(p.stats.get_raw(Stats.ARMOR), armor, "the Armor lasts 8 sec")
	p.hp = p.max_hp() * 0.9
	p.procs._physics_process(0.1)
	p.hp = p.max_hp() * 0.3
	p.procs.on_struck(null, 1.0)
	check_near(p.hp, p.max_hp() * 0.3, 0.0001, "again within 20 sec: nothing")
	p.hp = p.max_hp() * 0.9
	p.procs._physics_process(12.0)
	p.hp = p.max_hp() * 0.3
	p.procs.on_struck(null, 1.0)
	check_near(p.hp, p.max_hp() * 0.46, 0.0001, "20 sec later it is back")
	_remove(p, "ardent_defender", 2)
	check(p.procs.extra_defs(PlayerBonuses.SOURCE_TALENTS).is_empty(), "undone: no talent procs")


func test_righteous_fury_taunts_enemies_in_consecration_and_wards_you() -> void:
	var p := _paladin()
	var key := PaladinConsecration.ward_key(p)
	var cons := Db.get_ability(&"consecration")
	var inside: Array[Fakes.FakeEnemy] = [_enemy(Vector3(1.0, 0, 0)), _enemy(Vector3(-1.0, 0, 1.0)), _enemy(Vector3(0, 0, -2.0))]
	var outside := _enemy(Vector3(5.0, 0, 0))
	check(p.abilities.try_cast(RT), "cast without the talent")
	_step_abilities(p, 1)
	check(not inside[0].is_taunted() and not p.damage_taken_mults.has(key), "no talent: no taunt, no ward")
	for a in _areas():
		a.free()
	_add(p, "redoubt", 3)
	_add(p, "stoicism", 3)
	_add(p, "righteous_fury")
	var params := p.abilities.params_for(cons)
	check(float(params["taunt"]) == 1.0 and float(params["ward"]) == 10.0, "taunt 1 sec, ward 10%")
	p.abilities.set_cooldown(cons, 0.0)
	check(p.abilities.try_cast(RT), "cast")
	_step_abilities(p, 1)
	for e in inside:
		check(e.is_taunted() and e.taunt_target == p, "an enemy in the ground is taunted to the Paladin")
	check(not outside.is_taunted(), "outside: not taunted")
	check_near(float(p.damage_taken_mults.get(key, 1.0)), 0.9, 0.0001, "10% less damage while inside")
	p.global_position = Vector3(8.0, 0, 0)
	_step_abilities(p, 1)
	check(not p.damage_taken_mults.has(key), "outside the ground: no ward")
	p.global_position = Vector3.ZERO
	_step_abilities(p, 1)
	check(p.damage_taken_mults.has(key), "back inside")
	var ally := _ally(1, Vector3(-6.0, 0, 0))
	outside.apply_taunt(ally, 5.0)
	p.begin_wave()
	for e in inside:
		check(not e.is_taunted(), "wave start: released")
	check(not p.damage_taken_mults.has(key) and _consecration(p).ground_count() == 0, "wave start: no ward, no record")
	check(p.abilities.try_cast(RT), "cast again")
	_step_abilities(p, 1)
	check(inside[0].is_taunted(), "taunted again")
	_down(p)
	for e in inside:
		check(not e.is_taunted() and e.taunt_target == null, "the Paladin went down: released")
	check(outside.is_taunted() and outside.taunt_target == ally, "a taunt towards somebody else keeps running")
	check(not p.damage_taken_mults.has(key), "no ward key")
	check_eq(_consecration(p).taunted_count(), 0, "nothing remembered")


# --- Tier 4 ------------------------------------------------------------------------------------

func test_shield_of_the_templar_needs_redoubt_and_a_shield() -> void:
	var p := _paladin()
	var block_value := p.stats.get_raw(Stats.BLOCK_VALUE)
	_add(p, "redoubt", 2)
	_add(p, "stoicism", 3)
	_add(p, "consecrated_ground", 3)
	_add(p, "guarded_by_the_light", 1)
	check_eq(p.talents.add_block_reason(&"paladin_protection_shield_of_the_templar"), "Requires Redoubt", "prerequisite")
	_add(p, "redoubt")
	for n in range(1, 4):
		_add(p, "shield_of_the_templar")
		check_near(p.bonuses.damage_taken_mult(CombatMath.KIND_MELEE, null), 1.0 - 0.03 * n, 0.0001, "-3% damage taken per rank")
		check_eq(p.stats.get_raw(Stats.BLOCK_VALUE), block_value + 30.0 + 10.0 * n, "+10% Block Value per rank")
	_swap_to_tome(p)
	check_eq(p.bonuses.damage_taken_mult(CombatMath.KIND_MELEE, null), 1.0, "a Tome: off")
	check_eq(p.stats.get_raw(Stats.BLOCK_VALUE), block_value, "a Tome: no Block Value")


func test_reckoning_strikes_back_when_struck() -> void:
	var p := _paladin()
	var id := &"paladin_protection_reckoning"
	var e := _enemy(Vector3(1.2, 0, 0))
	_add(p, "redoubt", 3)
	_add(p, "stoicism", 3)
	_add(p, "consecrated_ground", 3)
	_add(p, "reckoning", 3)
	var def := _def(p, id)
	check(def.get("trigger") == "when_struck" and def.get("effect") == "extra_attack" and def.get("count") == 1, "an extra attack when struck")
	check(def.get("chance") == 15.0 and def.get("icd") == 0.5 and def.get("label") == "", "5% per rank, 0.5 sec icd, silent")
	_force(p, id)
	p.procs.on_struck(e, 1.0)
	check_eq(e.fake_hits(), 1, "the attacker is struck at once")
	p.procs.on_struck(e, 1.0)
	check_eq(e.fake_hits(), 1, "icd")
	p.procs._physics_process(0.6)
	p.procs.on_struck(e, 1.0)
	check_eq(e.fake_hits(), 2, "after the icd again")


# --- Holy Shield -------------------------------------------------------------------------------

func test_holy_shield_block_chance_and_cap() -> void:
	var p := _paladin()
	_to_capstone(p)
	check(p.bonuses.script_for(SHIELD_ID) != null, "the capstone script runs")
	check_eq(p.block_chance(), 39.0, "shield 10 + Redoubt 9 + Holy Shield 20")
	p.stats.set_source(&"test", {Stats.BLOCK_CHANCE: 30.0})
	check_eq(p.block_chance(), Stats.BLOCK_CAP, "capped at 50%")
	p.stats.remove_source(&"test")
	_swap_to_tome(p)
	check_eq(p.block_chance(), 0.0, "without a shield the capstone adds nothing")


func test_holy_shield_retaliates_and_shields_the_most_wounded_ally() -> void:
	var p := _paladin()
	_to_capstone(p)
	var hs := p.bonuses.script_for(SHIELD_ID) as PaladinProtectionHolyShield
	var key := PaladinProtectionHolyShield.shield_key(p)
	var e := _enemy(Vector3(1.2, 0, 0))
	var hurt := _ally(1, Vector3(3.0, 0, 0))
	var fine := _ally(2, Vector3(-3.0, 0, 0), &"rogue")
	var far := _ally(3, Vector3(12.0, 0, 0), &"mage")
	hurt.hp = hurt.max_hp() * 0.5
	far.hp = 1.0
	p._avoided(&"block", e)
	check_eq(e.fake_hits(), 1, "the attacker is struck")
	if e.fake_hits() > 0:
		check_near(e.fake_damage_log[0], PaladinKit.strike_damage(p, 60.0, 0.5), 0.0001, "60% weapon damage + 0.5 SP as Holy")
	var step := hurt.max_hp() * 0.02
	check_near(hurt.procs.shield_of(key), step, 0.0001, "2% of max HP shield on the most wounded ally")
	check_eq(fine.procs.shield_of(key) + far.procs.shield_of(key) + p.procs.shield_of(key), 0.0, "nobody else (never yourself)")
	for i in 5:
		p._avoided(&"block", e)
	check_near(hurt.procs.shield_of(key), step * 4.0, 0.0001, "tops up to 8% of max HP")
	check_eq(hs.ally_shields, 4, "four shields given, then the cap")
	p._avoided(&"parry", e)
	check_eq(e.fake_hits(), 6, "only blocks retaliate")
	e.fake_dead = true
	p._avoided(&"block", e)
	check_eq(e.fake_hits(), 6, "no strike on a corpse")
	p.begin_wave()
	check_eq(hurt.procs.shield_of(key), step * 4.0, "the ally's own ProcSystem keeps it until its wave start")
	hurt.begin_wave()
	check_eq(hurt.procs.shield_of(key), 0.0, "gone with the ally's wave start")


func test_holy_shield_solo_and_teardown() -> void:
	var p := _paladin()
	_to_capstone(p)
	var e := _enemy(Vector3(1.2, 0, 0))
	var key := PaladinProtectionHolyShield.shield_key(p)
	p._avoided(&"block", e)
	check_eq(e.fake_hits(), 1, "retaliation works solo")
	check_eq(p.procs.shield_of(key), 0.0, "solo: no ally, no shield")
	_down(p)
	p._avoided(&"block", e)
	check_eq(e.fake_hits(), 1, "a downed hero does not retaliate")
	RunState.add_gold(100)
	check(p.talents.try_reset(0), "Reset Talents")
	check(p.bonuses.script_for(SHIELD_ID) == null and p.bonuses.scripts().is_empty(), "torn down")
	check_eq(p.block_chance(), 10.0, "the block bonus is gone")
