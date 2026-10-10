extends TestCase
## Exotic stats in combat (GDD 2.4.1): CombatMath formulas and their use by WeaponRunner,
## Projectile, Player and Pickup.

const Fakes := preload("res://tests/player_fakes.gd")
const EFakes := preload("res://tests/enemies_fakes.gd")
const DT := 1.0 / 60.0

var world: Node3D


func before_each() -> void:
	RunState.start_run(1, 4242)
	Enemy.invalidate_player_cache()
	world = Fakes.make_world(tree)


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	Enemy.invalidate_player_cache()
	EnemyGrid.mark_dirty()


func _stats(mods: Dictionary) -> StatBlock:
	var s := StatBlock.new()
	s.set_source(&"test", mods)
	return s


func _projectiles() -> Array[Projectile]:
	var out: Array[Projectile] = []
	for node in tree.get_nodes_in_group(&"projectiles"):
		var p := node as Projectile
		if p != null and not p.is_queued_for_deletion():
			out.append(p)
	return out


# --- Pure formulas -------------------------------------------------------------------

func test_attack_power_is_normalised_by_weapon_speed() -> void:
	var sword := Db.get_weapon(&"sword")  # 0.9 s
	var axe := Db.get_weapon(&"two_hand_axe")  # 1.5 s
	var s := _stats({Stats.ATTACK_POWER: 10.0})
	check_eq(CombatMath.weapon_power_bonus(sword, s), 9.0, "sword: 10 AP x 0.9 s")
	check_eq(CombatMath.weapon_power_bonus(axe, s), 15.0, "axe: 10 AP x 1.5 s")
	check_eq(CombatMath.weapon_hit_damage(sword, s), sword.base_damage + 9.0, "added to the hit")
	# Same damage per second for both weapons.
	check_near(CombatMath.weapon_power_bonus(sword, s) / sword.cooldown,
			CombatMath.weapon_power_bonus(axe, s) / axe.cooldown, 0.0001, "equal DPS gain")
	var wand := Db.get_weapon(&"wand")
	check(wand.is_magic() and not sword.is_magic(), "wand is a magic weapon, the sword is not")
	check_eq(CombatMath.weapon_power_bonus(wand, s), 0.0, "Attack Power does not help a wand")


func test_spell_power_feeds_magic_weapons_only() -> void:
	var s := _stats({Stats.SPELL_POWER: 10.0})
	var wand := Db.get_weapon(&"wand")  # 0.6 s, arcane
	var staff := Db.get_weapon(&"staff")  # 1.0 s, fire
	check_eq(wand.school, &"arcane", "wand school")
	check_eq(staff.school, &"fire", "staff school")
	check_eq(Db.get_weapon(&"sword").school, &"physical", "physical by default")
	check_eq(CombatMath.weapon_power_bonus(wand, s), 6.0, "wand: 10 SP x 0.6 s")
	check_eq(CombatMath.weapon_power_bonus(staff, s), 10.0, "staff: 10 SP x 1.0 s")
	check_eq(CombatMath.weapon_power_bonus(Db.get_weapon(&"sword"), s), 0.0, "sword ignores SP")


func test_school_damage_is_additive_with_versatility() -> void:
	var staff := Db.get_weapon(&"staff")
	var base := CombatMath.weapon_hit_damage(staff, _stats({}))
	var s := _stats({Stats.FIRE_DAMAGE: 50.0, Stats.VERSATILITY: 10.0, Stats.FROST_DAMAGE: 100.0})
	check_near(CombatMath.weapon_hit_damage(staff, s), base * 1.6, 0.0001, "1 + 0.5 fire + 0.1 vers")
	var sword := Db.get_weapon(&"sword")
	var p := _stats({Stats.PHYSICAL_DAMAGE: 20.0})
	check_near(CombatMath.weapon_hit_damage(sword, p), sword.base_damage * 1.2, 0.0001, "physical %")
	check_eq(CombatMath.school_pct(s, &"unknown"), 0.0, "unknown school")


func test_crit_damage_raises_the_multiplier() -> void:
	var sword := Db.get_weapon(&"sword")
	var dagger := Db.get_weapon(&"dagger")
	check_eq(CombatMath.crit_multiplier(sword, _stats({})), 2.0, "x2")
	check_eq(CombatMath.crit_multiplier(sword, _stats({Stats.CRIT_DAMAGE: 15.0})), 2.15, "+15% -> x2.15")
	check_eq(CombatMath.crit_multiplier(dagger, _stats({Stats.CRIT_DAMAGE: 50.0})), 3.0, "dagger 2.5 + 0.5")
	check_eq(CombatMath.crit_multiplier(sword, _stats({Stats.CRIT_DAMAGE: -500.0})), 1.0, "never below x1")


func test_executioner_and_slayer() -> void:
	var s := _stats({Stats.EXECUTIONER: 50.0, Stats.SLAYER: 20.0})
	check_eq(CombatMath.target_damage_mult(s, 1.0, false), 1.0, "healthy normal enemy")
	check_eq(CombatMath.target_damage_mult(s, 0.31, false), 1.0, "above 30%")
	check_eq(CombatMath.target_damage_mult(s, 0.29, false), 1.5, "below 30%: +50%")
	check_eq(CombatMath.target_damage_mult(s, 1.0, true), 1.2, "elite: +20%")
	check_near(CombatMath.target_damage_mult(s, 0.1, true), 1.8, 0.0001, "both multiply")


func test_misc_formulas() -> void:
	check_eq(CombatMath.ppm_chance(4.0, 1.5), 0.1, "4 PPM on a 1.5 s weapon: 10% per hit")
	check_eq(CombatMath.ppm_chance(4.0, 0.5), 4.0 * 0.5 / 60.0, "fast weapon: lower chance")
	check_eq(CombatMath.ppm_chance(600.0, 1.0), 1.0, "capped at 100%")
	check_eq(CombatMath.block_absorb(0.0), 0.5, "a block absorbs half")
	check_eq(CombatMath.block_absorb(50.0), 0.75, "+50% Block Value")
	check_eq(CombatMath.block_absorb(300.0), 1.0, "capped at everything")
	check_eq(CombatMath.extra_projectiles(_stats({Stats.EXTRA_PROJECTILE: 1.5})), 1, "whole projectiles")
	check_eq(CombatMath.extra_pierce(_stats({Stats.PIERCE: 2.0})), 2, "pierce")
	check_eq(CombatMath.area_mult(_stats({Stats.AREA_SIZE: 25.0})), 1.25, "Area Size")
	check_eq(CombatMath.xp_with_gain(10.0, 20.0), 12.0, "XP Gain")
	var sp := _stats({Stats.SPELL_POWER: 6.0, Stats.ATTACK_POWER: 4.0, Stats.FIRE_DAMAGE: 50.0})
	check_eq(CombatMath.proc_damage(20.0, &"fire", sp), (20.0 + 6.0) * 1.5, "spell proc: +SP, fire %")
	check_eq(CombatMath.proc_damage(10.0, &"physical", sp), 14.0, "physical proc: +AP")
	check_eq(CombatMath.proc_damage(0.0, &"fire", sp), 0.0, "nothing stays nothing")


# --- In combat ------------------------------------------------------------------------

func test_extra_attack_strikes_again_but_never_chains() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior")
	var enemy := Fakes.spawn_enemy(world, Vector3(1.5, 0, 0))
	EnemyGrid.mark_dirty()
	p.stats.set_source(&"test", {Stats.EXTRA_ATTACK: 100.0})
	var extras: Array[bool] = []
	p.hit_dealt.connect(func(_d: float, _t: Node3D) -> void: extras.append(true))
	p.weapons[0].attack(enemy)
	check_eq(enemy.fake_hits(), 2, "100% Extra Attack: exactly one extra hit, no chain")
	check_eq(extras.size(), 2, "both are weapon hits")
	p.stats.set_source(&"test", {})
	p.weapons[0].attack(enemy)
	check_eq(enemy.fake_hits(), 3, "0%: a single hit")


func test_extra_attack_fires_another_projectile() -> void:
	var p := Fakes.spawn_player(world, 0, &"mage")
	p.equip_weapons(Db.get_weapon(&"wand"), null)
	var enemy := Fakes.spawn_enemy(world, Vector3(0, 0, -5))
	EnemyGrid.mark_dirty()
	p.stats.set_source(&"test", {Stats.EXTRA_ATTACK: 100.0})
	p.weapons[0].attack(enemy)
	var shots := _projectiles()
	check_eq(shots.size(), 2, "the attack and its extra attack")
	if shots.size() == 2:
		check(not shots[0].is_extra and shots[1].is_extra, "the second one is marked as extra")
		check(shots[0].weapon == p.main_hand, "projectiles know their weapon")


func test_extra_projectiles_fan_out_with_pierce_and_area() -> void:
	var p := Fakes.spawn_player(world, 0, &"warlock")
	p.equip_weapons(Db.get_weapon(&"staff"), null)
	var enemy := Fakes.spawn_enemy(world, Vector3(0, 0, -5))
	EnemyGrid.mark_dirty()
	p.stats.set_source(&"test", {Stats.EXTRA_PROJECTILE: 2.0, Stats.PIERCE: 1.0, Stats.AREA_SIZE: 50.0})
	p.weapons[0].attack(enemy)
	var shots := _projectiles()
	check_eq(shots.size(), 3, "1 + 2 projectiles")
	var angles: Array[float] = []
	for s in shots:
		angles.append(rad_to_deg(Vector3.FORWARD.signed_angle_to(s.direction, Vector3.UP)))
		check_eq(s.pierce, Db.get_weapon(&"staff").pierce + 1, "+1 pierce")
		check_near(s.aoe_radius, Db.get_weapon(&"staff").aoe_radius * 1.5, 0.0001, "+50% blast radius")
	angles.sort()
	if angles.size() == 3:
		check_near(angles[1] - angles[0], WeaponRunner.FAN_STEP_DEGREES, 0.5, "fan step")
		check_near(angles[2] - angles[1], WeaponRunner.FAN_STEP_DEGREES, 0.5, "fan step")
		check_near(angles[0] + angles[2], 2.0 * angles[1], 0.5, "symmetric around the aim")


func test_crit_damage_and_executioner_on_hits() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior")
	var enemy := Fakes.spawn_enemy(world, Vector3(1.5, 0, 0))
	EnemyGrid.mark_dirty()
	var base := CombatMath.weapon_hit_damage(p.main_hand, p.stats)
	p.stats.set_source(&"test", {Stats.CRIT: 100.0, Stats.CRIT_DAMAGE: 50.0})
	base = CombatMath.weapon_hit_damage(p.main_hand, p.stats)
	p.weapons[0].attack(enemy)
	check_near(enemy.fake_damage_log[0], base * 2.5, 0.0001, "x2 + 50% Critical Damage")
	p.stats.set_source(&"test", {Stats.EXECUTIONER: 50.0})
	base = CombatMath.weapon_hit_damage(p.main_hand, p.stats)
	enemy.hp = 100.0  # 10% of 1000
	WeaponRunner.apply_hit(p, enemy, base, false, Vector3.ZERO)
	check_near(enemy.fake_damage_log[1], base * 1.5, 0.0001, "Executioner below 30% HP")
	enemy.hp = 900.0
	WeaponRunner.apply_hit(p, enemy, base, false, Vector3.ZERO)
	check_near(enemy.fake_damage_log[2], base, 0.0001, "no Executioner above 30%")
	check(not enemy.is_elite(), "no elites before M5")


func test_parry_negates_melee_and_ripostes() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior")
	var enemy := Fakes.spawn_enemy(world, Vector3(1.0, 0, 0))
	EnemyGrid.mark_dirty()
	p.stats.set_source(&"test", {Stats.STAMINA: 1000.0, Stats.PARRY: 100.0})
	p.hp = p.max_hp()
	var parried := 0
	for i in 200:
		p.invulnerable_left = 0.0
		var before := p.hp
		p.take_damage(2.0, CombatMath.KIND_MELEE, enemy)
		if p.hp == before:
			parried += 1
	check(parried > 70 and parried < 130, "parry capped at %d%% (%d of 200)" % [int(CombatMath.PARRY_CAP), parried])
	check_eq(enemy.fake_hits(), parried, "every parry ripostes once")
	var hits := enemy.fake_hits()
	for i in 40:
		p.invulnerable_left = 0.0
		p.take_damage(2.0, CombatMath.KIND_PROJECTILE, enemy)
	check_eq(enemy.fake_hits(), hits, "projectiles are never parried")


func test_thorns_hit_melee_attackers_only() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior")
	var enemy := Fakes.spawn_enemy(world, Vector3(1.0, 0, 0))
	p.stats.set_source(&"test", {Stats.STAMINA: 100.0, Stats.THORNS: 5.0})
	p.hp = p.max_hp()
	p.take_damage(3.0, CombatMath.KIND_MELEE, enemy)
	check_eq(enemy.fake_damage_log, [5.0] as Array[float], "5 Thorns damage back")
	check(enemy.fake_attacker_log[0] == p, "credited to the player")
	p.invulnerable_left = 0.0
	p.take_damage(3.0, CombatMath.KIND_PROJECTILE, enemy)
	check_eq(enemy.fake_hits(), 1, "no Thorns against projectiles")


func test_block_value_absorbs_more() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior")
	var shield := Db.get_weapon(&"shield").duplicate() as WeaponData
	shield.block_chance = 100.0
	p.equip_weapons(Db.get_weapon(&"sword"), shield)
	p.stats.set_source(&"test", {Stats.STAMINA: 100.0, Stats.BLOCK_VALUE: 50.0})
	p.hp = p.max_hp()
	var before := p.hp
	p.take_damage(10.0, CombatMath.KIND_MELEE, null)
	check_near(before - p.hp, CombatMath.incoming_damage(10.0 * 0.25, p.stats), 0.0001, "75% absorbed")
	p.stats.set_source(&"test", {Stats.STAMINA: 100.0, Stats.BLOCK_VALUE: 100.0})
	p.invulnerable_left = 0.0
	before = p.hp
	p.take_damage(10.0, CombatMath.KIND_MELEE, null)
	check_eq(p.hp, before, "a full block takes nothing")


func test_life_on_kill_and_kill_notification() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior")
	var e := Enemy.create(Db.get_enemy(&"skeleton_grunt"), 1)
	world.add_child(e)
	e.global_position = Vector3(1.4, 0, 0)
	EnemyGrid.mark_dirty()
	p.stats.set_source(&"test", {Stats.STAMINA: 20.0, Stats.LIFE_ON_KILL: 100.0})
	p.hp = 5.0
	var killed: Array[Node3D] = []
	p.enemy_killed.connect(func(en: Node3D) -> void: killed.append(en))
	for i in 30:
		if e.is_dead():
			break
		p.weapons[0].attack(e)
	check(e.is_dead(), "killed")
	check_eq(killed.size(), 1, "enemy_killed once")
	check(killed.size() == 1 and killed[0] == e, "with the enemy")
	check_eq(p.hp, 6.0, "Life on Kill healed 1")


func test_xp_gain_on_pickup_keeps_fractions() -> void:
	var p := EFakes.FakePlayer.new()
	world.add_child(p)
	p.stats.set_source(&"test", {Stats.XP_GAIN: 10.0})
	var start := RunState.xp
	for i in 10:
		var pickup := Pickup.create(0, 1)
		world.add_child(pickup)
		pickup.collect(p)
	# 11 XP at level 1 never levels up (16 needed), so RunState.xp just adds up.
	check_eq(RunState.xp - start, 11, "ten 1-XP orbs with +10% XP Gain give 11")
	var bank := Pickup.create(0, 3)
	world.add_child(bank)
	var before := RunState.xp
	bank.collect_to_bank()
	check_eq(RunState.xp - before, 3, "banked XP has no XP Gain")


func test_slowed_enemy_walks_slower() -> void:
	Fakes.free_world(world)
	world = EFakes.make_world(tree)
	EFakes.spawn_player(world, Vector3(10, 0, 0))
	var data := EFakes.enemy_data()
	var a := EFakes.spawn_enemy(world, data, Vector3(0, 0, -3))
	var b := EFakes.spawn_enemy(world, data, Vector3(0, 0, 3))
	a.move_speed = 3.0
	b.move_speed = 3.0
	b.apply_slow(50.0, 5.0)
	check(b.is_slowed() and not a.is_slowed(), "slowed")
	var both: Array[Node] = [a, b]
	EFakes.step_all(both, 1.0)
	var da := a.global_position.x
	var db := b.global_position.x
	check(da > 0.5, "the free one walks")
	check_near(db, da * 0.5, 0.25, "the slowed one covers about half the distance")
	b.apply_slow(20.0, 10.0)
	check_eq(b.slow_pct, 50.0, "a weaker slow does not replace a stronger one")
	EFakes.step(b, 5.0)
	check(not b.is_slowed(), "the slow wears off")
