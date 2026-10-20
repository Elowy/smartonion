extends TestCase
## M6 METER, the caster credit: every call site that heals or shields SOMEONE ELSE runs its real
## code (ProcSystem blocks, Bandage, the paladin kit, the capstone talents, Unbreakable) and the
## damage meter must credit the CASTER's slot (healing_by_player / absorbed_by_player /
## revives_by_player), never the slot of the hero who was healed or shielded. Each test puts the
## caster and the target on different slots, so a call site that forgets to pass the caster would
## credit the target instead and fail here.

const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0

## The slots used throughout: the caster, and the hero who is healed / shielded.
const CASTER := 0
const TARGET := 2

var world: Node3D


func before_each() -> void:
	PlayerManager.clear()
	RunState.start_run(4, 1234)
	RunState.set_start_level(31)
	Enemy.invalidate_player_cache()
	world = Fakes.make_world(tree)
	EnemyGrid.mark_dirty()


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	Enemy.invalidate_player_cache()
	EnemyGrid.mark_dirty()
	PlayerManager.clear()
	RunState.start_run(1, 1)


# --- Helpers ------------------------------------------------------------------------------------

func _hero(class_id: StringName, index: int, pos: Vector3 = Vector3.ZERO) -> Player:
	var p := Fakes.spawn_player(world, index, class_id, pos)
	p.stats.set_source(&"tough", {Stats.STAMINA: 500.0})
	p.hp = p.max_hp()
	Enemy.invalidate_player_cache()
	return p


func _enemy(pos: Vector3) -> Fakes.FakeEnemy:
	var e := Fakes.spawn_enemy(world, pos)
	EnemyGrid.mark_dirty()
	return e


func _hurt(p: Player, ratio: float) -> void:
	p.hp = p.max_hp() * ratio
	p.invulnerable_left = 0.0


func _healing(index: int) -> float:
	return RunState.healing_by_player.get(index, 0.0)


func _absorbed(index: int) -> float:
	return RunState.absorbed_by_player.get(index, 0.0)


## The meter shows the caster as the healer and nobody else: [param gained] = the HP the healed
## heroes really gained (the sum of their HP deltas).
func _check_healing_credited_to_caster(gained: float, what: String) -> void:
	check(gained > 0.0, "%s: something was healed" % what)
	check_near(_healing(CASTER), gained, 0.001, "%s: the caster (slot %d) is credited with all of it: %s"
			% [what, CASTER, RunState.healing_by_player])
	check(not RunState.healing_by_player.has(TARGET), "%s: the healed hero (slot %d) is not: %s"
			% [what, TARGET, RunState.healing_by_player])


## [param target] soaks a raw hit with its shield on: the caster is credited with the absorb.
func _check_shield_credited_to_caster(target: Player, what: String) -> void:
	check(target.procs.shield_hp > 0.0, "%s: the target has a shield" % what)
	var shield := target.procs.shield_hp
	target.stats.set_source(&"naked", {Stats.ARMOR: -2.0})
	target.invulnerable_left = 0.0
	target.take_damage(shield * 0.5)
	check_near(_absorbed(CASTER), shield * 0.5, 0.001, "%s: the caster (slot %d) is credited with the soaked hit: %s"
			% [what, CASTER, RunState.absorbed_by_player])
	check(not RunState.absorbed_by_player.has(TARGET), "%s: the shielded hero (slot %d) is not: %s"
			% [what, TARGET, RunState.absorbed_by_player])


## Hands a ProcSystem one talent-style proc block (what PlayerBonuses does).
func _give_proc(p: Player, proc: Dictionary) -> void:
	var entry := {"kind": "proc", "proc": proc, "rank": 1, "id": "credit_test", "label": "Credit Test"}
	var entries: Array[Dictionary] = [entry]
	p.procs.set_extra_procs(&"talents", entries)
	p.procs.refresh()


func _learn(p: Player, id: StringName, rank: int = 1, spec: int = -1) -> int:
	var slot := p.abilities.learn(Db.get_ability(id))
	check(slot >= 0, "learned %s" % id)
	while p.abilities.rank_of(id) < rank:
		check(p.abilities.rank_up(id), "rank up %s" % id)
	if spec >= 0:
		check(p.abilities.set_spec(id, spec), "spec %d of %s" % [spec, id])
	return slot


## Raises a core ability (Consecration, Word of Glory: known from the start) to [param rank].
func _rank(p: Player, id: StringName, rank: int, spec: int = -1) -> void:
	while p.abilities.rank_of(id) < rank:
		check(p.abilities.rank_up(id), "rank up %s" % id)
	if spec >= 0:
		check(p.abilities.set_spec(id, spec), "spec %d of %s" % [spec, id])


func _add_talents(p: Player, ids: Array[StringName]) -> void:
	for id in ids:
		check(p.talents.add(id), "add %s: %s" % [id, p.talents.add_block_reason(id)])


func _step_abilities(p: Player, frames: int) -> void:
	for i in frames:
		p.abilities._physics_process(DT)


func _tick_bonuses(p: Player, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		p.bonuses.tick(DT)
		t += DT


# --- ProcSystem blocks (item / talent procs) ---------------------------------------------------

func test_a_heal_proc_on_the_lowest_ally_credits_the_proc_owner() -> void:
	var owner_hero := _hero(&"warrior", CASTER)
	var ally := _hero(&"warrior", TARGET, Vector3(3, 0, 0))
	_hurt(ally, 0.3)
	_give_proc(owner_hero, {"trigger": "on_kill", "effect": "heal", "amount": 7.0,
			"target": "lowest_ally", "label": ""})
	var before := ally.hp
	owner_hero.procs.on_kill(_enemy(Vector3(6, 0, 0)))
	check_near(ally.hp - before, 7.0, 0.001, "the ally got the heal")
	_check_healing_credited_to_caster(ally.hp - before, "heal proc")


func test_a_shield_proc_on_the_lowest_ally_credits_the_proc_owner() -> void:
	var owner_hero := _hero(&"warrior", CASTER)
	var ally := _hero(&"warrior", TARGET, Vector3(3, 0, 0))
	_hurt(ally, 0.3)
	_give_proc(owner_hero, {"trigger": "on_kill", "effect": "shield", "amount": 9.0,
			"target": "lowest_ally", "duration": 6.0, "label": ""})
	owner_hero.procs.on_kill(_enemy(Vector3(6, 0, 0)))
	check_near(ally.procs.shield_hp, 9.0, 0.001, "the ally got the shield")
	check_eq(owner_hero.procs.shield_hp, 0.0, "not the owner")
	_check_shield_credited_to_caster(ally, "shield proc")


func test_a_shield_proc_on_the_owner_itself_credits_the_owner() -> void:
	var owner_hero := _hero(&"warrior", CASTER)
	_give_proc(owner_hero, {"trigger": "on_kill", "effect": "shield", "amount": 9.0, "duration": 6.0, "label": ""})
	owner_hero.procs.on_kill(_enemy(Vector3(6, 0, 0)))
	owner_hero.stats.set_source(&"naked", {Stats.ARMOR: -2.0})
	owner_hero.invulnerable_left = 0.0
	owner_hero.take_damage(4.0)
	check_near(_absorbed(CASTER), 4.0, 0.001, "an own shield credits its owner")


func test_a_smite_heal_proc_credits_the_proc_owner() -> void:
	var owner_hero := _hero(&"warrior", CASTER)
	var ally := _hero(&"warrior", TARGET, Vector3(3, 0, 0))
	_hurt(ally, 0.3)
	_give_proc(owner_hero, {"trigger": "on_hit", "effect": "smite_heal", "damage": 5.0, "heal": 4.0,
			"school": "holy", "label": ""})
	var e := _enemy(Vector3(1.5, 0, 0))
	var before := ally.hp
	owner_hero.procs.on_hit(e, 1.0, owner_hero.main_hand, false)
	check_eq(e.fake_hits(), 1, "the smite struck")
	check_near(ally.hp - before, 4.0, 0.001, "the most wounded ally was healed")
	_check_healing_credited_to_caster(ally.hp - before, "smite heal")


# --- Bandage ------------------------------------------------------------------------------------

func test_a_bandage_over_time_on_an_ally_credits_the_caster() -> void:
	var caster := _hero(&"warrior", CASTER)
	var ally := _hero(&"warrior", TARGET, Vector3(3, 0, 0))
	_learn(caster, &"bandage", 3)  # Rank III: the most wounded ally too
	_hurt(caster, 0.2)
	_hurt(ally, 0.2)
	var hp0 := caster.hp + ally.hp
	check(caster.abilities.try_cast(caster.abilities.slot_of(&"bandage")), "cast")
	var buff := GeneralBuff.find(ally, GeneralBandage.KEY)
	check(buff != null, "the ally is bandaged")
	if buff == null:
		return
	buff.step(3.0)
	var mine := GeneralBuff.find(caster, GeneralBandage.KEY)
	if mine != null:
		mine.step(3.0)
	_check_healing_credited_to_caster(caster.hp + ally.hp - hp0, "bandage ticks")
	check(ally.hp > ally.max_hp() * 0.2, "the ally really gained HP")


func test_an_instant_bandage_on_an_ally_credits_the_caster() -> void:
	var caster := _hero(&"warrior", CASTER)
	var ally := _hero(&"warrior", TARGET, Vector3(3, 0, 0))
	_learn(caster, &"bandage", 5, 0)  # Rank V, Quick Wrap: the whole heal at once; Rank III: an ally
	_hurt(caster, 0.2)
	_hurt(ally, 0.2)
	var hp0 := caster.hp + ally.hp
	check(caster.abilities.try_cast(caster.abilities.slot_of(&"bandage")), "cast")
	check(ally.hp > ally.max_hp() * 0.2, "the ally was bandaged at once")
	_check_healing_credited_to_caster(caster.hp + ally.hp - hp0, "instant bandage")


func test_a_bandage_on_the_caster_credits_the_caster() -> void:
	var caster := _hero(&"warrior", CASTER)
	_learn(caster, &"bandage", 5, 0)
	_hurt(caster, 0.2)
	var hp0 := caster.hp
	check(caster.abilities.try_cast(caster.abilities.slot_of(&"bandage")), "cast")
	check_near(_healing(CASTER), caster.hp - hp0, 0.001, "self-healing counts for the hero itself")
	check_eq(RunState.healing_by_player.size(), 1, "nobody else")


# --- Paladin kit --------------------------------------------------------------------------------

func test_consecration_light_s_hammer_heal_credits_the_paladin() -> void:
	var paladin := _hero(&"paladin", CASTER)
	var ally := _hero(&"warrior", TARGET, Vector3(3, 0, 0))
	_add_talents(paladin, [&"paladin_holy_healing_light", &"paladin_holy_healing_light",
			&"paladin_holy_healing_light", &"paladin_holy_aura_mastery", &"paladin_holy_aura_mastery",
			&"paladin_holy_aura_mastery", &"paladin_holy_lights_hammer"] as Array[StringName])
	_hurt(ally, 0.5)
	var before := ally.hp
	check(paladin.abilities.try_cast(0), "Sacred Circle")
	_step_abilities(paladin, 40)
	check(ally.hp > before, "the ground healed the ally")
	check_near(_healing(CASTER), ally.hp - before, 0.001, "the paladin is credited with all of it: %s" % RunState.healing_by_player)
	check(not RunState.healing_by_player.has(TARGET), "not the ally: %s" % RunState.healing_by_player)


func test_consecration_hallowed_ground_heal_credits_the_paladin() -> void:
	var paladin := _hero(&"paladin", CASTER)
	var ally := _hero(&"warrior", TARGET, Vector3(1, 0, 0))
	_rank(paladin, &"consecration", 5, 0)  # Hallowed Ground: AbilityArea heals the heroes inside
	_hurt(ally, 0.5)
	var before := ally.hp
	check(paladin.abilities.try_cast(0), "Sacred Circle")
	var areas := tree.get_nodes_in_group(&"ability_areas")
	check(not areas.is_empty(), "a ground")
	for a in areas:
		Fakes.step(a, 1.1)
	check(ally.hp > before, "the ground healed the ally")
	_check_healing_credited_to_caster(ally.hp - before, "Healing Circle")


func test_divine_storm_heal_credits_the_paladin() -> void:
	var paladin := _hero(&"paladin", CASTER)
	var ally := _hero(&"warrior", TARGET, Vector3(0, 0, 4))
	var slot := _learn(paladin, &"divine_storm")
	_hurt(ally, 0.4)
	var before := ally.hp
	check(paladin.abilities.try_cast(slot), "Radiant Whirl")
	check(ally.hp > before, "the ally was healed")
	_check_healing_credited_to_caster(ally.hp - before, "Radiant Whirl")


func test_lay_on_hands_heal_credits_the_paladin() -> void:
	var paladin := _hero(&"paladin", CASTER)
	var ally := _hero(&"warrior", TARGET, Vector3(3, 0, 0))
	var slot := _learn(paladin, &"lay_on_hands")
	_hurt(ally, 0.3)
	var before := ally.hp
	check(paladin.abilities.try_cast(slot), "Mending Touch")
	check_eq(ally.hp, ally.max_hp(), "fully healed")
	_check_healing_credited_to_caster(ally.hp - before, "Mending Touch")


func test_lay_on_hands_shield_credits_the_paladin() -> void:
	var paladin := _hero(&"paladin", CASTER)
	var ally := _hero(&"warrior", TARGET, Vector3(3, 0, 0))
	var slot := _learn(paladin, &"lay_on_hands", 3)  # Rank III: + an absorb shield
	_hurt(ally, 0.3)
	check(paladin.abilities.try_cast(slot), "Mending Touch")
	check_eq(paladin.procs.shield_hp, 0.0, "no shield on the paladin")
	_check_shield_credited_to_caster(ally, "Mending Touch shield")


func test_word_of_glory_heal_credits_the_paladin() -> void:
	var paladin := _hero(&"paladin", CASTER)
	var ally := _hero(&"warrior", TARGET, Vector3(2, 0, 0))
	_hurt(ally, 0.3)
	var before := ally.hp
	paladin.abilities.get_resource(&"holy_power").set_value(3.0)
	check(paladin.abilities.try_cast(1), "Call of Valor")
	check(ally.hp > before, "the ally was healed")
	_check_healing_credited_to_caster(ally.hp - before, "Call of Valor")


func test_word_of_glory_shield_share_credits_the_paladin() -> void:
	var paladin := _hero(&"paladin", CASTER)
	var ally := _hero(&"warrior", TARGET, Vector3(2, 0, 0))
	_rank(paladin, &"word_of_glory", 5, 1)  # Holy Bulwark: the healed heroes get a shield too
	_hurt(ally, 0.3)
	var before := ally.hp
	paladin.abilities.get_resource(&"holy_power").set_value(3.0)
	check(paladin.abilities.try_cast(1), "Call of Valor")
	check(ally.hp > before, "the ally was healed")
	_check_healing_credited_to_caster(ally.hp - before, "Call of Valor heal")
	_check_shield_credited_to_caster(ally, "Call of Valor shield share")


func test_word_of_glory_revive_credits_the_paladin() -> void:
	var paladin := _hero(&"paladin", CASTER)
	var ally := _hero(&"warrior", TARGET, Vector3(2, 0, 0))
	ally.invulnerable_left = 0.0
	ally.take_damage(ally.max_hp() * 3.0)
	check(ally.downed, "the ally is down")
	paladin.abilities.get_resource(&"holy_power").set_value(3.0)
	check(paladin.abilities.try_cast(1), "Call of Valor raises the ally")
	check(not ally.downed, "revived")
	check_eq(RunState.revives_by_player, {CASTER: 1} as Dictionary[int, int], "only the caster is credited")


func test_holy_shock_heal_credits_the_paladin() -> void:
	var paladin := _hero(&"paladin", CASTER)
	var holy: Array[StringName] = [
		&"paladin_holy_healing_light", &"paladin_holy_healing_light", &"paladin_holy_healing_light",
		&"paladin_holy_aura_mastery", &"paladin_holy_aura_mastery", &"paladin_holy_aura_mastery",
		&"paladin_holy_lights_hammer",
		&"paladin_holy_eternal_glory", &"paladin_holy_eternal_glory", &"paladin_holy_eternal_glory",
		&"paladin_holy_unyielding_faith", &"paladin_holy_unyielding_faith",
		&"paladin_holy_holy_shock",
	]
	_add_talents(paladin, holy)
	var ally := _hero(&"warrior", TARGET, Vector3(5, 0, 0))
	paladin.begin_wave()
	_hurt(ally, 0.7)
	var before := ally.hp
	_tick_bonuses(paladin, 2.1)
	check(ally.hp > before, "Radiant Pulse healed the ally")
	_check_healing_credited_to_caster(ally.hp - before, "Radiant Pulse")


func test_seal_of_command_heal_credits_the_paladin() -> void:
	var paladin := _hero(&"paladin", CASTER)
	var seal: Array[StringName] = [
		&"paladin_retribution_divine_strength", &"paladin_retribution_divine_strength",
		&"paladin_retribution_divine_strength",
		&"paladin_retribution_conviction", &"paladin_retribution_conviction", &"paladin_retribution_conviction",
		&"paladin_retribution_divine_verdict",
		&"paladin_retribution_art_of_war", &"paladin_retribution_art_of_war", &"paladin_retribution_art_of_war",
		&"paladin_retribution_sanctity_of_battle", &"paladin_retribution_sanctity_of_battle",
		&"paladin_retribution_seal_of_command",
	]
	_add_talents(paladin, seal)
	var ally := _hero(&"warrior", TARGET, Vector3(-3, 0, 0))
	_hurt(ally, 0.5)
	var e := _enemy(Vector3(1.2, 0, 0))
	for s in range(1, 5000):
		RunState.rng.seed = s
		if RunState.rng.randf() * 100.0 < 15.0:
			RunState.rng.seed = s
			break
	var before := ally.hp
	paladin.bonuses.on_hit(e, 10.0, true, true)
	check(ally.hp > before, "the Seal healed the most wounded hero")
	_check_healing_credited_to_caster(ally.hp - before, "Sunbrand")


func test_holy_shield_ally_shield_credits_the_paladin() -> void:
	var paladin := _hero(&"paladin", CASTER)
	var path: Array[StringName] = [
		&"paladin_protection_redoubt", &"paladin_protection_redoubt", &"paladin_protection_redoubt",
		&"paladin_protection_stoicism", &"paladin_protection_stoicism", &"paladin_protection_stoicism",
		&"paladin_protection_righteous_fury",
		&"paladin_protection_consecrated_ground", &"paladin_protection_consecrated_ground",
		&"paladin_protection_consecrated_ground",
		&"paladin_protection_guarded_by_the_light", &"paladin_protection_guarded_by_the_light",
		&"paladin_protection_holy_shield",
	]
	_add_talents(paladin, path)
	var ally := _hero(&"warrior", TARGET, Vector3(3, 0, 0))
	_hurt(ally, 0.5)
	var e := _enemy(Vector3(1.2, 0, 0))
	paladin._avoided(&"block", e)
	var key := PaladinProtectionHolyShield.shield_key(paladin)
	check(ally.procs.shield_of(key) > 0.0, "the ally got the Gleaming Shield")
	_check_shield_credited_to_caster(ally, "Gleaming Shield")


# --- Unbreakable --------------------------------------------------------------------------------

func test_unbreakable_ally_heal_credits_the_warrior() -> void:
	var warrior := _hero(&"warrior", CASTER)
	var ally := _hero(&"warrior", TARGET, Vector3(5, 0, 0))
	var path: Array[StringName] = [
		&"warrior_protection_toughness", &"warrior_protection_toughness", &"warrior_protection_toughness",
		&"warrior_protection_revenge", &"warrior_protection_revenge", &"warrior_protection_revenge",
		&"warrior_protection_defiance", &"warrior_protection_defiance", &"warrior_protection_defiance",
		&"warrior_protection_vitality", &"warrior_protection_vitality",
		&"warrior_protection_challenging_charge",
		&"warrior_protection_unbreakable",
	]
	_add_talents(warrior, path)
	ally.hp = 10.0
	warrior.invulnerable_left = 0.0
	var ally_before := ally.hp
	warrior.take_damage(warrior.hp + warrior.max_hp() + 1000.0, CombatMath.KIND_PROJECTILE, null)
	check(not warrior.downed, "Unbreakable saved the warrior")
	check(ally.hp > ally_before, "the ally was lifted and healed")
	# The warrior's own gain (from the 1 HP the guard leaves) and the ally's: both are the warrior's.
	_check_healing_credited_to_caster((ally.hp - ally_before) + (warrior.hp - 1.0), "Unbreakable")


# --- Ability areas and buffs --------------------------------------------------------------------

func test_an_ability_area_heal_credits_the_area_owner() -> void:
	var owner_hero := _hero(&"warrior", CASTER)
	var ally := _hero(&"warrior", TARGET, Vector3(1, 0, 0))
	_hurt(ally, 0.3)
	var area := AbilityArea.new()
	area.owner_player = owner_hero
	area.heal_per_tick = 2.0
	area.radius = 3.0
	world.add_child(area)
	area.global_position = Vector3(1, 0, 0)
	area._physics_process(1.0)
	check(ally.hp > ally.max_hp() * 0.3, "the ally was healed")
	check(not RunState.healing_by_player.has(TARGET), "not the ally: %s" % RunState.healing_by_player)
	check(_healing(CASTER) >= 2.0, "the area's owner: %s" % RunState.healing_by_player)


# --- ProcSystem and Player bookkeeping ----------------------------------------------------------

func test_shield_hp_and_shield_of_sum_every_caster() -> void:
	var target := _hero(&"warrior", TARGET)
	target.procs.add_shield(2.0, 5.0, &"holy", 0)
	target.procs.add_shield(3.0, 10.0, &"holy", 1)
	target.procs.add_shield(4.0, 10.0, &"other", 3)
	check_eq(target.procs.shield_of(&"holy"), 5.0, "shield_of(source) sums both casters of the source")
	check_eq(target.procs.shield_of(&"other"), 4.0, "another source on its own")
	check_eq(target.procs.shield_hp, 9.0, "shield_hp sums every shield")


func test_a_reviver_listed_twice_is_credited_once() -> void:
	var ghost := _hero(&"warrior", 0)
	ghost.take_damage(ghost.max_hp() * 3.0)
	check(ghost.downed, "down")
	ghost.revive(0.5, [1, 1, 3, 1] as Array[int])
	check(not ghost.downed, "revived")
	check_eq(RunState.revives_by_player, {1: 1, 3: 1} as Dictionary[int, int], "once per reviver")
