extends TestCase
## Paladin talents (M5 Wave 2, talents_paladin.md): the three trees in Db, the Holy tree talent
## by talent through player.talents.add -> PlayerBonuses on a real Paladin (Healing Light,
## Aura Mastery, Eternal Glory, Unyielding Faith, Light's Grace, Light's Hammer, Divine
## Guardian, Purifying Power, the Holy Shock capstone), the aura talents of both trees (Divine
## Guardian, Sanctified Retribution) and the bot paths of all three trees (TalentBot reaches
## each capstone at point 13). Every talent is also taken back (player.talents.remove, the
## capstone through Reset Talents) and checked back at neutral. Protection:
## test_talents_paladin_protection.gd; Retribution: test_talents_paladin_retribution.gd; the
## texts in the Talents tab: test_talents_paladin_ui.gd.
##
## Pseudo ability id &"paladin_aura" (BonusVocabulary.PSEUDO_IDS, read by
## PaladinAuraOfDevotion.aura_params): BASE {"radius": 6.0, "guard": 0.0, "might": 0.0} –
## radius in m (Aura Mastery "radius_add"), guard = % less damage taken for every hero inside
## (Divine Guardian "guard_add" -> Player.damage_taken_mults[aura key]), might = % more damage
## for every hero inside (Sanctified Retribution "might_add" -> Player.damage_mults[aura key]).

const Fakes := preload("res://tests/player_fakes.gd")
const EFakes := preload("res://tests/enemies_fakes.gd")
const DT := 1.0 / 60.0
const RT := 0
const LT := 1
const SHOCK_ID := &"paladin_holy_holy_shock"

const HOLY_PATH: Array[StringName] = [
	&"paladin_holy_healing_light", &"paladin_holy_healing_light", &"paladin_holy_healing_light",
	&"paladin_holy_aura_mastery", &"paladin_holy_aura_mastery", &"paladin_holy_aura_mastery",
	&"paladin_holy_lights_hammer",
	&"paladin_holy_eternal_glory", &"paladin_holy_eternal_glory", &"paladin_holy_eternal_glory",
	&"paladin_holy_unyielding_faith", &"paladin_holy_unyielding_faith",
	&"paladin_holy_holy_shock",
	&"paladin_holy_unyielding_faith",
	&"paladin_holy_lights_grace", &"paladin_holy_lights_grace",
	&"paladin_holy_divine_guardian", &"paladin_holy_divine_guardian", &"paladin_holy_divine_guardian",
	&"paladin_holy_purifying_power", &"paladin_holy_purifying_power", &"paladin_holy_purifying_power",
]
const PROTECTION_PATH: Array[StringName] = [
	&"paladin_protection_redoubt", &"paladin_protection_redoubt", &"paladin_protection_redoubt",
	&"paladin_protection_stoicism", &"paladin_protection_stoicism", &"paladin_protection_stoicism",
	&"paladin_protection_righteous_fury",
	&"paladin_protection_consecrated_ground", &"paladin_protection_consecrated_ground", &"paladin_protection_consecrated_ground",
	&"paladin_protection_guarded_by_the_light", &"paladin_protection_guarded_by_the_light",
	&"paladin_protection_holy_shield",
	&"paladin_protection_guarded_by_the_light",
	&"paladin_protection_ardent_defender", &"paladin_protection_ardent_defender",
	&"paladin_protection_shield_of_the_templar", &"paladin_protection_shield_of_the_templar", &"paladin_protection_shield_of_the_templar",
	&"paladin_protection_reckoning", &"paladin_protection_reckoning", &"paladin_protection_reckoning",
]
const RETRIBUTION_PATH: Array[StringName] = [
	&"paladin_retribution_divine_strength", &"paladin_retribution_divine_strength", &"paladin_retribution_divine_strength",
	&"paladin_retribution_conviction", &"paladin_retribution_conviction", &"paladin_retribution_conviction",
	&"paladin_retribution_divine_verdict",
	&"paladin_retribution_art_of_war", &"paladin_retribution_art_of_war", &"paladin_retribution_art_of_war",
	&"paladin_retribution_sanctity_of_battle", &"paladin_retribution_sanctity_of_battle",
	&"paladin_retribution_seal_of_command",
	&"paladin_retribution_sanctity_of_battle",
	&"paladin_retribution_vengeance", &"paladin_retribution_vengeance",
	&"paladin_retribution_sanctified_retribution", &"paladin_retribution_sanctified_retribution", &"paladin_retribution_sanctified_retribution",
	&"paladin_retribution_righteous_vengeance", &"paladin_retribution_righteous_vengeance", &"paladin_retribution_righteous_vengeance",
]

var world: Node3D


func before_each() -> void:
	RunState.start_run(1, 4242)
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


func _add(p: Player, tree_short: String, name: String, n: int = 1) -> void:
	var id := StringName("paladin_%s_%s" % [tree_short, name])
	for i in n:
		check(p.talents.add(id), "add %s: %s" % [id, p.talents.add_block_reason(id)])


func _remove(p: Player, tree_short: String, name: String, n: int = 1) -> void:
	var id := StringName("paladin_%s_%s" % [tree_short, name])
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


## Seeds RunState.rng so its next randf() * 100 is below [param pct] ([param below] true) or
## not (false).
static func _seed_roll(pct: float, below: bool) -> void:
	for s in range(1, 5000):
		RunState.rng.seed = s
		if (RunState.rng.randf() * 100.0 < pct) == below:
			RunState.rng.seed = s
			return


## The ids TalentBot picks for [param p] (bot [param slot_index]), point by point.
static func _bot_path(p: Player, slot_index: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for i in 100:
		var t := TalentBot.next_talent(p, slot_index)
		if t == null or not p.talents.add(t.id):
			break
		out.append(t.id)
	return out


## The 12 Holy points of the bot path, then Holy Shock (talents_paladin.md 5.2).
func _to_holy_capstone(p: Player) -> void:
	_add(p, "holy", "healing_light", 3)
	_add(p, "holy", "aura_mastery", 3)
	_add(p, "holy", "lights_hammer")
	_add(p, "holy", "eternal_glory", 3)
	_add(p, "holy", "unyielding_faith", 2)
	_add(p, "holy", "holy_shock")


func _shock(p: Player) -> PaladinHolyHolyShock:
	return p.bonuses.script_for(SHOCK_ID) as PaladinHolyHolyShock


func _tick_bonuses(p: Player, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		p.bonuses.tick(DT)
		t += DT


func _step_abilities(p: Player, frames: int) -> void:
	for i in frames:
		p.abilities._physics_process(DT)


# --- The trees ---------------------------------------------------------------------------------

func test_the_three_paladin_trees_in_tab_order() -> void:
	var trees := Db.talent_trees_for(&"paladin")
	check_eq(trees.size(), 3, "three trees")
	if trees.size() != 3:
		return
	var ids: Array[StringName] = []
	for t in trees:
		ids.append(t.id)
	check_eq(ids, [&"paladin_holy", &"paladin_protection", &"paladin_retribution"] as Array[StringName], "GDD 7.2 order")
	check_eq([trees[0].display_name, trees[1].display_name, trees[2].display_name], ["Holy", "Protection", "Retribution"], "names")
	check_eq(Db.get_talent(&"paladin_holy_lights_hammer").ability, &"consecration", "Light's Hammer changes Consecration")
	check_eq(Db.get_talent(&"paladin_protection_righteous_fury").ability, &"consecration", "Righteous Fury changes Consecration")
	check_eq(Db.get_talent(&"paladin_retribution_divine_verdict").ability, &"word_of_glory", "Divine Verdict changes Word of Glory")
	check_eq(Db.get_talent(&"paladin_holy_divine_guardian").prerequisite, &"paladin_holy_aura_mastery", "prerequisite")
	check_eq(Db.get_talent(&"paladin_protection_shield_of_the_templar").prerequisite, &"paladin_protection_redoubt", "prerequisite")
	check_eq(Db.get_talent(&"paladin_retribution_vengeance").prerequisite, &"paladin_retribution_conviction", "prerequisite")
	for t in trees:
		var cap := t.talents_in_tier(5)
		check(cap.size() == 1 and cap[0].is_capstone(), "%s has one capstone" % t.id)
	var p := _paladin()
	check_eq(p.talents.trees().size(), 3, "a Paladin's TalentState holds them")
	check_eq(Db.get_talent(&"paladin_holy_holy_shock").text_for_rank(1),
		"Every 4 sec: heals the most wounded hero within 8 m below 90% health (you too) for 6% of max health, else smites the nearest enemy in range for 100% weapon damage as Holy. Haste shortens the interval.",
		"capstone text")


# --- Holy tier 1-2 -----------------------------------------------------------------------------

func test_healing_light_scales_paladin_heals_but_not_the_full_heal() -> void:
	var p := _paladin()
	var ally := _ally(1, Vector3(3.0, 0, 0))
	var wog := Db.get_ability(&"word_of_glory")
	var base := PaladinWordOfGlory.heal_amount(p.abilities.build_context(wog), p, ally)
	var hallowed := {"heal": 0.5, "tick": 0.5, "power": 1.0}
	for n in range(1, 4):
		_add(p, "holy", "healing_light")
		check_eq(p.stats.get_raw(Stats.HEALING_DONE), 4.0 * n, "+4% Healing Done per rank")
		check_near(PaladinKit.healing_mult(p), 1.0 + 0.04 * n, 0.0001, "the kit multiplier")
		check_near(PaladinWordOfGlory.heal_amount(p.abilities.build_context(wog), p, ally), base * (1.0 + 0.04 * n), 0.0001,
			"Word of Glory heal at rank %d" % n)
	check_near(PaladinConsecration.tick_heal(p.stats, hallowed, p), 0.5 * 1.12, 0.0001, "Hallowed Ground heal")
	check_eq(PaladinConsecration.tick_heal(p.stats, hallowed), 0.5, "no caster: no Healing Done")
	ally.hp = 2.0
	_holy_power(p).set_value(3.0)
	var expected := minf(ally.max_hp(), 2.0 + base * 1.12)
	check(p.abilities.try_cast(LT), "Word of Glory")
	check_near(ally.hp, expected, 0.0001, "the real cast heals 12% more")
	var loh := Db.get_ability(&"lay_on_hands")
	var slot := p.abilities.learn(loh)
	check(slot >= 0, "learned Lay on Hands")
	ally.hp = 1.0
	check(p.abilities.try_cast(slot), "Lay on Hands")
	check_eq(ally.hp, ally.max_hp(), "a full heal stays a full heal")
	while p.abilities.rank_of(&"lay_on_hands") < 3:
		check(p.abilities.rank_up(&"lay_on_hands"), "rank up")
	var params := p.abilities.params_for(loh)
	ally.hp = 1.0
	p.abilities.set_cooldown(loh, 0.0)
	check(p.abilities.try_cast(slot), "Lay on Hands rank III")
	check_near(ally.procs.shield_hp, ally.max_hp() * float(params["shield_max_hp"]) / 100.0 * float(params["power"]) * 1.12,
		0.0001, "the Rank III shield grows with Healing Done")
	_remove(p, "holy", "healing_light", 3)
	check_eq(p.stats.get_raw(Stats.HEALING_DONE), 0.0, "undone")
	check_eq(PaladinKit.healing_mult(p), 1.0, "multiplier back to 1")


func test_aura_mastery_raises_mastery_and_widens_the_aura() -> void:
	var p := _paladin()
	p.stats.set_source(&"test", {Stats.MASTERY: 4.0})
	var ally := _ally(1, Vector3(6.5, 0, 0))
	var aura := p.abilities.mastery as PaladinAuraOfDevotion
	var key := aura.source_key()
	check_eq(aura.radius(), 6.0, "6 m without talents")
	aura.refresh()
	check(not ally.stats.has_source(key), "6.5 m is outside")
	_add(p, "holy", "aura_mastery")
	check_eq(p.stats.get_raw(Stats.MASTERY), 5.0, "+1 Mastery")
	check_eq(aura.radius(), 7.0, "+1 m")
	aura.refresh()
	check(ally.stats.has_source(key), "the ally at 6.5 m is inside now")
	check_eq(float(ally.stats.get_source(key).get(Stats.ARMOR, 0.0)), 5.0 * PaladinAuraOfDevotion.ARMOR_PER_POINT, "with the new Mastery")
	_add(p, "holy", "aura_mastery", 2)
	check_eq(p.stats.get_raw(Stats.MASTERY), 7.0, "+3 Mastery at 3/3")
	check_eq(aura.radius(), 9.0, "9 m at 3/3")
	check(aura.describe().begins_with("Aura of Devotion: allies within 9 m"), "describe: %s" % aura.describe())
	_remove(p, "holy", "aura_mastery", 3)
	check_eq(aura.radius(), 6.0, "back to 6 m")
	aura.refresh()
	check(not ally.stats.has_source(key), "the ally drops out again")


func test_eternal_glory_and_lights_grace_change_word_of_glory() -> void:
	var p := _paladin()
	var wog := Db.get_ability(&"word_of_glory")
	var base := p.abilities.params_for(wog)
	check_eq(float(base.get("free_chance", 0.0)), 0.0, "no free casts")
	_add(p, "holy", "healing_light", 3)
	for n in range(1, 4):
		_add(p, "holy", "eternal_glory")
		check_eq(float(p.abilities.params_for(wog).get("free_chance", 0.0)), 8.0 * n, "+8% free chance per rank")
	for n in range(1, 3):
		_add(p, "holy", "lights_grace")
		var params := p.abilities.params_for(wog)
		check_near(float(params["power"]), 1.0 + 0.08 * n, 0.0001, "+8% power per rank")
		check_eq(float(params["allies"]), 1.0 + n, "+1 ally per rank")
	check_eq(Db.get_talent(&"paladin_holy_lights_grace").text_for_rank(2),
		"Word of Glory heals 16% more, and the number of wounded allies it heals is increased by 2.", "text at rank 2")
	p.hp = p.max_hp() * 0.5
	var allies: Array[Player] = [_ally(1, Vector3(3, 0, 0)), _ally(2, Vector3(-3, 0, 0), &"mage"), _ally(3, Vector3(0, 0, 3), &"rogue")]
	for a in allies:
		a.hp = a.max_hp() * 0.5
	_holy_power(p).set_value(3.0)
	_seed_roll(24.0, true)
	check(p.abilities.try_cast(LT), "cast")
	for a in allies:
		check(a.hp > a.max_hp() * 0.5, "%s healed (Light's Grace 2: three allies)" % a.name)
	check(p.hp > p.max_hp() * 0.5, "the Paladin too")
	check_eq(_holy_power(p).value, 3.0, "Eternal Glory: the roll passed, the cast was free")
	_remove(p, "holy", "lights_grace", 2)
	var undone := p.abilities.params_for(wog)
	check(is_equal_approx(float(undone["power"]), 1.0) and is_equal_approx(float(undone["allies"]), 1.0), "Light's Grace undone")
	_remove(p, "holy", "eternal_glory", 3)
	check_eq(float(p.abilities.params_for(wog).get("free_chance", 0.0)), 0.0, "Eternal Glory undone: no free casts")
	allies[0].hp = allies[0].max_hp() * 0.5
	_holy_power(p).set_value(3.0)
	p.abilities.set_cooldown(wog, 0.0)
	_seed_roll(24.0, true)
	check(p.abilities.try_cast(LT), "cast after the take-back")
	check_eq(_holy_power(p).value, 0.0, "the same roll no longer makes it free")


func test_unyielding_faith_grants_holy_power_on_a_timer() -> void:
	var p := _paladin()
	var hp := _holy_power(p)
	_add(p, "holy", "healing_light", 3)
	_add(p, "holy", "unyielding_faith", 3)
	var defs := p.procs.extra_defs(PlayerBonuses.SOURCE_TALENTS)
	check_eq(defs.size(), 1, "one talent proc")
	if defs.is_empty():
		return
	var def: Dictionary = defs[0]
	check(def.get("trigger") == "periodic" and def.get("effect") == "resource" and def.get("resource") == "holy_power", "periodic Holy Power")
	check(def.get("interval") == 4.0 and def.get("chance") == 24.0 and def.get("value") == 1, "every 4 sec, 8% per rank, 1 point")
	check_eq(def.get("label"), "", "silent")
	var gained := 0.0
	for i in 400:
		hp.set_value(0.0)
		p.procs._physics_process(1.0)
		gained += hp.value
	var fired := p.procs.fire_count(&"paladin_holy_unyielding_faith")
	check_eq(gained, float(fired), "one Holy Power per proc")
	check(fired >= 12 and fired <= 36, "about 100 x 24%% = 24 in 400 s, got %d" % fired)
	_down(p)
	hp.set_value(0.0)
	for i in 40:
		p.procs._physics_process(1.0)
	check_eq(p.procs.fire_count(&"paladin_holy_unyielding_faith"), fired, "nothing while downed")
	p.revive(1.0)
	_remove(p, "holy", "unyielding_faith", 3)
	check(p.procs.extra_defs(PlayerBonuses.SOURCE_TALENTS).is_empty(), "undone: no talent procs")
	gained = 0.0
	for i in 100:
		hp.set_value(0.0)
		p.procs._physics_process(1.0)
		gained += hp.value
	check_eq(gained, 0.0, "no Holy Power in 100 s after the take-back")


# --- Light's Hammer ----------------------------------------------------------------------------

func test_lights_hammer_hurls_consecration_at_the_most_wounded_hero() -> void:
	var p := _paladin()
	var cons := Db.get_ability(&"consecration")
	var neutral := p.abilities.params_for(cons)
	check(float(neutral["ally_range"]) == 0.0 and float(neutral["heal_max_hp_pct"]) == 0.0, "neutral params")
	_add(p, "holy", "healing_light", 3)
	_add(p, "holy", "aura_mastery", 3)
	_add(p, "holy", "lights_hammer")
	var params := p.abilities.params_for(cons)
	check_eq(float(params["ally_range"]), 10.0, "10 m")
	check_eq(float(params["heal_max_hp_pct"]), 1.0, "1% per tick")
	var ally := _ally(1, Vector3(7.0, 0, 0))
	var scratched := _ally(2, Vector3(-4.0, 0, 0), &"rogue")
	ally.hp = ally.max_hp() * 0.5
	scratched.hp = scratched.max_hp() * 0.75
	check(p.abilities.try_cast(RT), "cast")
	var areas := _areas()
	check_eq(areas.size(), 1, "one ground")
	if areas.is_empty():
		return
	check_near(areas[0].global_position.x, 7.0, 0.001, "at the most wounded hero's feet")
	var tick := ally.max_hp() * 0.01 * 1.12
	var before := ally.hp
	_step_abilities(p, 1)
	check_near(ally.hp - before, tick, 0.0001, "1% of max HP x Healing Done on the first tick")
	check_eq(scratched.hp, scratched.max_hp() * 0.75, "a hero outside the ground is not healed")
	_step_abilities(p, 299)
	check_near(ally.hp - before, tick * 8.0, 0.0001, "8 ticks in 4 sec")
	check_eq(_consecration(p).ground_count(), 0, "the ground's record ends with it")
	_remove(p, "holy", "lights_hammer")
	var undone := p.abilities.params_for(cons)
	check(float(undone["ally_range"]) == 0.0 and float(undone["heal_max_hp_pct"]) == 0.0, "undone: neutral params")
	for a in _areas():
		a.free()
	check(ally.hp < ally.max_hp() * 0.8, "the ally is still the most wounded hero")
	p.abilities.set_cooldown(cons, 0.0)
	check(p.abilities.try_cast(RT), "cast after the take-back")
	check_near(_areas()[0].global_position.x, 0.0, 0.001, "at your feet again")
	check_eq(_consecration(p).ground_count(), 0, "no rider record")
	before = ally.hp
	_step_abilities(p, 30)
	check_eq(ally.hp, before, "no heal")


func test_lights_hammer_placement_rules_and_power() -> void:
	var p := _paladin()
	var cons := Db.get_ability(&"consecration")
	var effect := _consecration(p)
	var ally := _ally(1, Vector3(7.0, 0, 0))
	ally.hp = ally.max_hp() * 0.5
	check(p.abilities.try_cast(RT), "cast without the talent")
	check_near(_areas()[0].global_position.x, 0.0, 0.001, "no talent: at your feet")
	check_eq(effect.ground_count(), 0, "no talent: no rider record")
	var before := ally.hp
	_step_abilities(p, 30)
	check_eq(ally.hp, before, "no talent: no heal")
	for a in _areas():
		a.free()
	_add(p, "holy", "healing_light", 3)
	_add(p, "holy", "aura_mastery", 3)
	_add(p, "holy", "lights_hammer")
	ally.global_position = Vector3(11.0, 0, 0)
	p.abilities.set_cooldown(cons, 0.0)
	check(p.abilities.try_cast(RT), "ally beyond 10 m")
	check_near(_areas()[0].global_position.x, 0.0, 0.001, "at your feet")
	for a in _areas():
		a.free()
	ally.global_position = Vector3(5.0, 0, 0)
	ally.hp = ally.max_hp() * 0.85
	p.abilities.set_cooldown(cons, 0.0)
	check(p.abilities.try_cast(RT), "everybody above 80%")
	check_near(_areas()[0].global_position.x, 0.0, 0.001, "at your feet")
	for a in _areas():
		a.free()
	while p.abilities.rank_of(&"consecration") < 4:
		check(p.abilities.rank_up(&"consecration"), "rank up")
	check(float(p.abilities.params_for(cons)["power"]) > 1.2, "Rank IV power")
	ally.hp = ally.max_hp() * 0.5
	p.abilities.set_cooldown(cons, 0.0)
	check(p.abilities.try_cast(RT), "Rank IV cast")
	before = ally.hp
	_step_abilities(p, 1)
	check_near(ally.hp - before, ally.max_hp() * 0.01 * 1.12, 0.0001, "power does not scale the heal")


func test_lights_hammer_follows_with_the_sabatons_and_stops_when_downed() -> void:
	var p := _paladin()
	var item := ItemGenerator.from_unique(Db.get_unique(&"sabatons_of_the_dawn"), 1, false, RunState.rng, p.class_data)
	check(p.equipment.equip(item), "Sabatons of the Dawn")
	_add(p, "holy", "healing_light", 3)
	_add(p, "holy", "aura_mastery", 3)
	_add(p, "holy", "lights_hammer")
	var ally := _ally(1, Vector3(6.0, 0, 0))
	ally.hp = ally.max_hp() * 0.4
	check(p.abilities.try_cast(RT), "cast")
	var areas := _areas()
	check(not areas.is_empty() and areas[0].follow == ally, "the ground follows the hero it was hurled at")
	_down(p)
	check_eq(_consecration(p).ground_count(), 0, "downed: the record is dropped")
	var before := ally.hp
	_step_abilities(p, 60)
	check_eq(ally.hp, before, "no heals while the Paladin is down")


func test_lights_hammer_bot_rule() -> void:
	var p := _paladin()
	var cons := Db.get_ability(&"consecration")
	var effect := _consecration(p)
	var ally := _ally(1, Vector3(8.0, 0, 0))
	ally.hp = ally.max_hp() * 0.6
	check(not effect.wants_auto_cast(p.abilities.build_context(cons)), "no talent: only enemies matter")
	_add(p, "holy", "healing_light", 3)
	_add(p, "holy", "aura_mastery", 3)
	_add(p, "holy", "lights_hammer")
	check(effect.wants_auto_cast(p.abilities.build_context(cons)), "a hero in 10 m below 70%")
	ally.hp = ally.max_hp() * 0.75
	check(not effect.wants_auto_cast(p.abilities.build_context(cons)), "75%: wait")
	_enemy(Vector3(1.5, 0, 0))
	check(effect.wants_auto_cast(p.abilities.build_context(cons)), "an enemy at your feet still counts")


# --- The aura talents (Holy Divine Guardian, Retribution Sanctified Retribution) ----------------

func test_divine_guardian_shields_everybody_in_the_aura() -> void:
	var p := _paladin()
	var ally := _ally(1, Vector3(3.0, 0, 0))
	var aura := p.abilities.mastery as PaladinAuraOfDevotion
	var key := aura.source_key()
	_add(p, "holy", "healing_light", 3)
	_add(p, "holy", "aura_mastery", 2)
	_add(p, "holy", "eternal_glory", 3)
	_add(p, "holy", "unyielding_faith", 1)
	check_eq(p.talents.add_block_reason(&"paladin_holy_divine_guardian"), "Requires Aura Mastery", "prerequisite")
	_add(p, "holy", "aura_mastery")
	for n in range(1, 4):
		_add(p, "holy", "divine_guardian")
		aura.refresh()
		check_near(float(ally.damage_taken_mults.get(key, 1.0)), 1.0 - 0.02 * n, 0.0001, "ally: -2% per rank")
		check_near(float(p.damage_taken_mults.get(key, 1.0)), 1.0 - 0.02 * n, 0.0001, "the Paladin too")
	check(aura.describe().ends_with("; -6% damage taken."), "describe: %s" % aura.describe())
	ally.global_position = Vector3(20.0, 0, 0)
	aura.refresh()
	check(not ally.damage_taken_mults.has(key) and not ally.stats.has_source(key), "the ally left: key and source gone")
	ally.global_position = Vector3(3.0, 0, 0)
	aura.refresh()
	_remove(p, "holy", "divine_guardian", 3)
	aura.refresh()
	check(not ally.damage_taken_mults.has(key) and not p.damage_taken_mults.has(key), "undone: the key goes on the next refresh")
	check(ally.stats.has_source(key), "the Armor of the aura stays (Aura Mastery's Mastery)")
	check_eq(p.bonuses.damage_taken_mult(CombatMath.KIND_MELEE, null), 1.0, "nothing left in the engine")
	_add(p, "holy", "divine_guardian", 3)
	aura.refresh()
	check_near(float(ally.damage_taken_mults.get(key, 1.0)), 0.94, 0.0001, "taken again")
	p.end_wave()
	check(not ally.damage_taken_mults.has(key) and not p.damage_taken_mults.has(key), "wave end: nobody keeps it")
	p.begin_wave()
	aura.tick(0.01)
	check(ally.damage_taken_mults.has(key), "back after the wave start (Player.begin_wave cleared the dictionaries)")
	_down(p)
	check(not ally.damage_taken_mults.has(key), "the Paladin went down")


func test_sanctified_retribution_works_at_zero_mastery_and_cleans_up() -> void:
	var p := _paladin()
	var ally := _ally(1, Vector3(3.0, 0, 0))
	var aura := p.abilities.mastery as PaladinAuraOfDevotion
	var key := aura.source_key()
	check_eq(p.stats.get_raw(Stats.MASTERY), 0.0, "0 Mastery (test hero)")
	_add(p, "retribution", "divine_strength", 3)
	_add(p, "retribution", "conviction", 3)
	_add(p, "retribution", "art_of_war", 3)
	for n in range(1, 4):
		_add(p, "retribution", "sanctified_retribution")
		aura.refresh()
		check_near(float(ally.damage_mults.get(key, 1.0)), 1.0 + 0.02 * n, 0.0001, "ally: +2% per rank")
		check_near(ally.outgoing_damage_mult(null, &"physical", &"weapon"), 1.0 + 0.02 * n, 0.0001, "in the ally's outgoing damage")
	check(not ally.stats.has_source(key), "no stat source at 0 Mastery")
	check(aura.describe().ends_with("; +6% damage."), "describe: %s" % aura.describe())
	_remove(p, "retribution", "sanctified_retribution", 3)
	aura.refresh()
	check(not ally.damage_mults.has(key) and not p.damage_mults.has(key), "undone: the key goes on the next refresh")
	_add(p, "retribution", "sanctified_retribution")
	aura.refresh()
	aura.teardown()
	check(not ally.damage_mults.has(key) and not p.damage_mults.has(key), "teardown leaves nothing")


# --- Purifying Power ---------------------------------------------------------------------------

func test_purifying_power_raises_holy_damage() -> void:
	var p := _paladin()
	_add(p, "holy", "healing_light", 3)
	_add(p, "holy", "aura_mastery", 3)
	_add(p, "holy", "eternal_glory", 3)
	for n in range(1, 4):
		_add(p, "holy", "purifying_power")
		check_near(p.bonuses.damage_mult(null, &"holy", &"ability"), 1.0 + 0.05 * n, 0.0001, "+5% Holy per rank")
	check_eq(p.bonuses.damage_mult(null, &"physical", &"weapon"), 1.0, "not physical")
	var e := _enemy(Vector3(1.0, 0, 0))
	check(p.abilities.try_cast(RT), "Consecration")
	var area := _areas()[0]
	Fakes.step(area, DT)
	check_eq(e.fake_hits(), 1, "one tick")
	if e.fake_hits() > 0:
		check_near(e.fake_damage_log[0], area.damage_per_tick * 1.15, 0.0001, "the ground's Holy damage x1.15")
	_remove(p, "holy", "purifying_power", 3)
	check_eq(p.bonuses.damage_mult(null, &"holy", &"ability"), 1.0, "undone")


# --- Holy Shock --------------------------------------------------------------------------------

func test_holy_shock_heals_the_most_wounded_hero_two_seconds_into_the_wave() -> void:
	var p := _paladin()
	_to_holy_capstone(p)
	var shock := _shock(p)
	check(shock != null, "the capstone script runs")
	if shock == null:
		return
	var ally := _ally(1, Vector3(5.0, 0, 0))
	p.begin_wave()
	check_near(shock.time_left(), 2.0, 0.0001, "first shock half an interval into the wave")
	ally.hp = ally.max_hp() * 0.7
	var start := ally.hp
	_tick_bonuses(p, 1.95)
	check_eq(ally.hp, start, "not yet")
	_tick_bonuses(p, 0.1)
	var heal := (1.0 + ally.max_hp() * 0.06) * 1.12
	check_near(ally.hp - start, heal, 0.0001, "1 + 6% of max HP, x Healing Light 3/3")
	check_eq(shock.heals, 1, "one heal")
	check_near(shock.time_left(), 4.0, 0.1, "next in 4 sec")


func test_holy_shock_smites_when_nobody_needs_healing_and_holds_otherwise() -> void:
	var p := _paladin()
	_to_holy_capstone(p)
	var shock := _shock(p)
	var ally := _ally(1, Vector3(5.0, 0, 0))
	ally.hp = ally.max_hp() * 0.95
	_tick_bonuses(p, 2.05)
	check(shock.heals == 0 and shock.smites == 0, "nothing to do: held")
	check(shock.time_left() > 0.15 and shock.time_left() <= 0.25, "retried within 0.25 sec (%s)" % shock.time_left())
	var e := _enemy(Vector3(3.0, 0, 0))
	var far := _enemy(Vector3(8.5, 0, 0))
	var state := RunState.rng.state
	_tick_bonuses(p, 0.3)
	check_eq(shock.smites, 1, "the held shock smites the nearest enemy")
	check_eq(e.fake_hits(), 1, "hit")
	check_eq(far.fake_hits(), 0, "out of range")
	if e.fake_hits() > 0:
		check_near(e.fake_damage_log[0], PaladinKit.strike_damage(p, 100.0, 0.8), 0.0001, "100% weapon damage + 0.8 SP as Holy")
	check_eq(RunState.rng.state, state, "no RNG")


func test_holy_shock_interval_haste_and_downed() -> void:
	var p := _paladin()
	_to_holy_capstone(p)
	var shock := _shock(p)
	check_near(shock.interval_now(), 4.0, 0.0001, "4 sec")
	p.stats.set_source(&"test", {Stats.HASTE: 50.0})
	check_near(shock.interval_now(), 4.0 / 1.25, 0.0001, "Haste at half effect")
	p.stats.set_source(&"test", {Stats.HASTE: 50.0, Stats.COOLDOWN_REDUCTION: 20.0})
	check_near(shock.interval_now(), 4.0 / 1.25 * 0.8, 0.0001, "and Cooldown Reduction")
	check(shock.describe().begins_with("Holy Shock: every 2.6 sec"), shock.describe())
	p.stats.remove_source(&"test")
	var e := _enemy(Vector3(3.0, 0, 0))
	_down(p)
	var left := shock.time_left()
	_tick_bonuses(p, 10.0)
	check_eq(e.fake_hits(), 0, "no shock while downed")
	check_eq(shock.time_left(), left, "the timer holds")
	RunState.add_gold(100)
	check(p.talents.try_reset(0), "Reset Talents")
	check(_shock(p) == null and p.bonuses.scripts().is_empty(), "torn down")


# --- Bots --------------------------------------------------------------------------------------

func test_bots_reach_each_capstone_at_point_13() -> void:
	var holy := _paladin(Vector3.ZERO, 0)
	var path := _bot_path(holy, 0)
	check_eq(path, HOLY_PATH, "Holy bot path (talents_paladin.md 5.4)")
	check_eq(path.find(&"paladin_holy_lights_hammer"), 6, "modifier at point 7")
	check_eq(path.find(SHOCK_ID), 12, "Holy Shock at point 13")
	var prot := _paladin(Vector3(6.0, 0, 0), 1)
	check(prot.off_hand != null and prot.off_hand.weapon_type == &"shield", "bots start with a shield")
	path = _bot_path(prot, 1)
	check_eq(path, PROTECTION_PATH, "Protection bot path")
	check_eq(path.find(&"paladin_protection_holy_shield"), 12, "Holy Shield at point 13")
	var ret := _paladin(Vector3(-6.0, 0, 0), 2)
	path = _bot_path(ret, 2)
	check_eq(path, RETRIBUTION_PATH, "Retribution bot path")
	check_eq(path.find(&"paladin_retribution_seal_of_command"), 12, "Seal of Command at point 13")
	check(holy.bonuses.script_for(SHOCK_ID) != null and prot.bonuses.script_for(&"paladin_protection_holy_shield") != null \
			and ret.bonuses.script_for(&"paladin_retribution_seal_of_command") != null, "every capstone script runs")


func test_a_tome_protection_bot_defers_the_shield_talents() -> void:
	var p := _paladin(Vector3.ZERO, 1)
	var tome := ItemInstance.from_weapon(Db.get_weapon(&"tome"), Items.Rarity.COMMON, 1, false)
	p.equipment.add_to_backpack(tome)
	check(p.equipment.equip(tome), "a Tome instead of the shield")
	var path := _bot_path(p, 1)
	check_eq(path.slice(0, 13), [
		&"paladin_protection_stoicism", &"paladin_protection_stoicism", &"paladin_protection_stoicism",
		&"paladin_protection_consecrated_ground", &"paladin_protection_consecrated_ground", &"paladin_protection_consecrated_ground",
		&"paladin_protection_righteous_fury",
		&"paladin_protection_guarded_by_the_light", &"paladin_protection_guarded_by_the_light", &"paladin_protection_guarded_by_the_light",
		&"paladin_protection_ardent_defender", &"paladin_protection_ardent_defender",
		&"paladin_protection_holy_shield",
	] as Array[StringName], "Tome path to the capstone (talents_paladin.md 5.4)")
	check_eq(path.count(&"paladin_protection_reckoning"), 3, "then Reckoning")
	check_eq(path.count(&"paladin_protection_redoubt"), 0, "Redoubt waits while other trees offer points")
	check_eq(path.size(), 22, "every point spent")
