extends TestCase
## Paladin kit (GDD 3.3, M3): Holy Power, Consecration, Word of Glory (instant revive / heal),
## the class items (Libram of Devotion, Sabatons of the Dawn), Aura of Devotion, bot casting.

const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0
const RT := 0
const LT := 1

var world: Node3D


func before_each() -> void:
	RunState.start_run(1, 4321)
	world = Fakes.make_world(tree)
	EnemyGrid.mark_dirty()


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	EnemyGrid.mark_dirty()


func _paladin(pos: Vector3 = Vector3.ZERO, index: int = 0) -> Player:
	return Fakes.spawn_player(world, index, &"paladin", pos)


func _enemy(pos: Vector3) -> Fakes.FakeEnemy:
	var e := Fakes.spawn_enemy(world, pos)
	EnemyGrid.mark_dirty()
	return e


func _holy_power(p: Player) -> ClassResource:
	return p.abilities.get_resource(&"holy_power")


func _down(p: Player) -> void:
	p.invulnerable_left = 0.0
	p.hp = 1.0
	p.take_damage(1000.0)


func _areas() -> Array[AbilityArea]:
	var out: Array[AbilityArea] = []
	for node in tree.get_nodes_in_group(&"ability_areas"):
		var a := node as AbilityArea
		if a != null and not a.is_queued_for_deletion():
			out.append(a)
	return out


func _equip_unique(p: Player, id: StringName) -> ItemInstance:
	var item := ItemGenerator.from_unique(Db.get_unique(id), 1, false, RunState.rng, p.class_data)
	check(p.equipment.equip(item), "equipped %s" % id)
	return item


# --- Data -------------------------------------------------------------------------------------

func test_class_data_wiring() -> void:
	var c := Db.get_class_data(&"paladin")
	check_eq(c.resources.size(), 1, "one resource")
	var hp := c.resources[0]
	check_eq(hp.id, &"holy_power", "Holy Power")
	check_eq(hp.display, ResourceData.Display.PIPS, "pips")
	check_eq(hp.max_value, 3.0, "0-3 pips")
	check_eq(hp.gain_per_hits, 5, "+1 every 5th weapon hit")
	check_eq(hp.gain_per_hits_amount, 1.0, "+1")
	check_eq(c.abilities.size(), 2, "two core abilities")
	var cons := c.abilities[RT]
	check_eq(cons.id, &"consecration", "RT = Consecration")
	check_eq(cons.targeting, AbilityData.Targeting.SELF, "under the Paladin")
	check_eq(cons.cooldown, 10.0, "10 s cooldown")
	check_eq(cons.school, &"holy", "holy")
	check_eq(cons.resource, &"", "free")
	var wog := c.abilities[LT]
	check_eq(wog.id, &"word_of_glory", "LT = Word of Glory")
	check_eq(wog.resource, &"holy_power", "spends Holy Power")
	check_eq(wog.cost, 3.0, "3 Holy Power")
	check_eq(wog.targeting, AbilityData.Targeting.ALLY, "ally targeting")
	check(bool(wog.params.get("prefer_downed", false)), "prefers downed allies")
	check_eq(wog.cast_range, 8.0, "8 m")
	check(c.mastery != null and c.mastery_text != "", "Mastery + text")
	var p := _paladin()
	check_eq(p.abilities.cost_of(wog), 3.0, "3 Holy Power without the Libram")
	check_eq(p.abilities.cooldown_of(wog), 0.0, "no cooldown: Holy Power is the limit")
	check(p.abilities.mastery is PaladinAuraOfDevotion, "Aura of Devotion")
	check(p.abilities.effect_for(p.abilities.slots[RT]) is PaladinConsecration, "Consecration effect")
	check(p.abilities.effect_for(p.abilities.slots[LT]) is PaladinWordOfGlory, "Word of Glory effect")
	check(p.abilities.mastery.describe().begins_with("Aura of Devotion"), "describe")


func test_class_items_are_ability_mods() -> void:
	var libram := Db.get_unique(&"libram_of_devotion")
	check_eq(libram.unique_effect, &"ability_mod", "Libram is an ability mod")
	check_eq(libram.class_restriction, &"paladin", "Paladin only")
	check_eq(StringName(libram.unique_params["ability"]), &"word_of_glory", "modifies Word of Glory")
	var sabatons := Db.get_unique(&"sabatons_of_the_dawn")
	check_eq(sabatons.unique_effect, &"ability_mod", "Sabatons are an ability mod")
	check_eq(sabatons.class_restriction, &"paladin", "Paladin only")
	check_eq(StringName(sabatons.unique_params["ability"]), &"consecration", "modifies Consecration")


# --- Holy Power -------------------------------------------------------------------------------

func test_holy_power_every_fifth_hit() -> void:
	var p := _paladin()
	var res := _holy_power(p)
	check_eq(res.value, 0.0, "starts empty")
	for i in 4:
		p.abilities.on_weapon_hit(null, 5.0, false)
	check_eq(res.value, 0.0, "nothing after 4 hits")
	p.abilities.on_weapon_hit(null, 5.0, false)
	check_eq(res.value, 1.0, "+1 on the 5th hit")
	for i in 10:
		p.abilities.on_weapon_hit(null, 5.0, true)
	check_eq(res.value, 3.0, "3 after 15 hits (crits are no bonus)")
	for i in 5:
		p.abilities.on_weapon_hit(null, 5.0, false)
	check_eq(res.value, 3.0, "capped at 3 pips")
	for i in 120:
		p.abilities._physics_process(DT)
	check_eq(res.value, 3.0, "no decay / regen")
	p.begin_wave()
	check_eq(res.value, 0.0, "wave start resets")


func test_weapon_hits_feed_holy_power() -> void:
	var p := _paladin()
	var e := _enemy(Vector3(0, 0, -1))
	for i in 5:
		p.on_hit_dealt(5.0, e, p.main_hand)
	check_eq(_holy_power(p).value, 1.0, "Player.on_hit_dealt feeds the resource")


# --- Consecration -----------------------------------------------------------------------------

func test_consecration_damages_enemies_inside() -> void:
	var p := _paladin()
	p.stats.set_source(&"test", {Stats.STRENGTH: 8.0, Stats.SPELL_POWER: 2.0})
	var near := _enemy(Vector3(1.0, 0, 0))
	var far := _enemy(Vector3(6.0, 0, 0))
	check(p.abilities.try_cast(RT), "cast")
	check_near(p.abilities.remaining(RT), 10.0, 0.001, "10 s cooldown")
	check(not p.abilities.try_cast(RT), "on cooldown")
	var areas := _areas()
	check_eq(areas.size(), 1, "one consecrated area")
	if areas.is_empty():
		return
	var area := areas[0]
	check_eq(area.school, &"holy", "holy damage")
	check_near(area.radius, 3.0, 0.001, "3 m")
	check_near(area.duration, 4.0, 0.001, "4 s")
	check(area.follow == null, "stays put without the Sabatons")
	check(area.get_node_or_null("ConsecrationVfx") != null, "golden ground VFX")
	# (2.5 + 8 Str x 0.25 + 2 SP x 1.0 x 0.5 s) x 0.9 (Paladin -10% damage)
	var expected := (2.5 + 2.0 + 1.0) * 0.9
	check_near(area.damage_per_tick, expected, 0.001, "tick damage from Strength / Spell Power")
	check_near(PaladinConsecration.tick_damage(p.stats, p.abilities.slots[RT].params), expected, 0.001, "helper")
	Fakes.step(area, 4.0)
	check_eq(near.fake_hits(), 8, "8 ticks in 4 s")
	check_eq(far.fake_hits(), 0, "outside the ground")
	if near.fake_hits() > 0:
		check_near(near.fake_damage_log[0], expected, 0.001, "damage per tick")
	var moved := Vector3(4.0, 0, 0)
	p.global_position = moved
	check_near(area.global_position.x, 0.0, 0.001, "the ground does not follow")


func test_consecration_holy_damage_scales() -> void:
	var p := _paladin()
	var params: Dictionary = p.abilities.slots[RT].params
	var base := PaladinConsecration.tick_damage(p.stats, params)
	p.stats.set_source(&"test", {Stats.HOLY_DAMAGE: 50.0})
	check_near(PaladinConsecration.tick_damage(p.stats, params), base / 0.9 * 1.4, 0.001, "Holy damage %")


func test_sabatons_make_consecration_follow() -> void:
	var p := _paladin()
	_equip_unique(p, &"sabatons_of_the_dawn")
	check(bool(p.ability_mods(&"consecration").get("follows", false)), "mod collected")
	check(p.abilities.try_cast(RT), "cast")
	var areas := _areas()
	check_eq(areas.size(), 1, "one area")
	if areas.is_empty():
		return
	var area := areas[0]
	check(area.follow == p, "follows the Paladin")
	p.global_position = Vector3(4.0, 0, -2.0)
	var e := _enemy(Vector3(5.0, 0, -2.0))
	Fakes.step(area, 0.6)
	check_near(area.global_position.x, 4.0, 0.001, "moved with the Paladin (x)")
	check_near(area.global_position.z, -2.0, 0.001, "moved with the Paladin (z)")
	check(e.fake_hits() > 0, "burns enemies at the new place")


func test_consecration_bot_decision() -> void:
	var p := _paladin()
	var cons := p.abilities.slots[RT]
	var effect := p.abilities.effect_for(cons)
	check(not effect.wants_auto_cast(p.abilities.build_context(cons)), "no enemies: wait")
	var e := _enemy(Vector3(5.0, 0, 0))
	check(not effect.wants_auto_cast(p.abilities.build_context(cons)), "enemy too far")
	e.global_position = Vector3(2.0, 0, 0)
	EnemyGrid.mark_dirty()
	check(effect.wants_auto_cast(p.abilities.build_context(cons)), "enemy close: cast")


# --- Word of Glory ----------------------------------------------------------------------------

func test_word_of_glory_instantly_revives_downed_ally() -> void:
	var p := _paladin()
	var ally := Fakes.spawn_player(world, 1, &"warrior", Vector3(6.0, 0, 3.0))
	_down(ally)
	check(ally.downed, "ally downed")
	var res := _holy_power(p)
	res.set_value(2.0)
	check(not p.abilities.try_cast(LT), "needs 3 Holy Power")
	res.set_value(3.0)
	var ctx := p.abilities.build_context(p.abilities.slots[LT])
	check(ctx.target == ally, "targets the downed ally")
	check(p.abilities.try_cast(LT), "cast")
	check(not ally.downed, "instantly revived")
	check_eq(ally.hp, roundf(ally.max_hp() * 0.4), "at 40% HP")
	check_near(ally.invulnerable_left, Player.INVULNERABLE_AFTER_REVIVE, 0.001, "revive invulnerability")
	check_eq(res.value, 0.0, "3 Holy Power spent")
	check_eq(p.hp, p.max_hp(), "Paladin untouched")


func test_word_of_glory_revive_prefers_downed_over_heal() -> void:
	var p := _paladin()
	p.hp = 4.0
	var hurt := Fakes.spawn_player(world, 1, &"warrior", Vector3(2.0, 0, 0))
	hurt.hp = 3.0
	var ally := Fakes.spawn_player(world, 2, &"rogue", Vector3(-5.0, 0, 0))
	_down(ally)
	_holy_power(p).set_value(3.0)
	check(p.abilities.try_cast(LT), "cast")
	check(not ally.downed, "the downed ally is revived")
	check_eq(p.hp, 4.0, "no heal when reviving")
	check_eq(hurt.hp, 3.0, "no heal for the hurt ally either")


func test_word_of_glory_no_revive_beyond_8m() -> void:
	var p := _paladin()
	var ally := Fakes.spawn_player(world, 1, &"warrior", Vector3(8.5, 0, 0))
	_down(ally)
	var res := _holy_power(p)
	res.set_value(3.0)
	var wog := p.abilities.slots[LT]
	check(PaladinWordOfGlory.revive_target(p.abilities.build_context(wog)) == null, "out of range")
	check(not p.abilities.try_cast(LT), "nothing to do: no cast (Holy Power kept)")
	check_eq(res.value, 3.0, "Holy Power kept")
	p.hp = 5.0
	check(p.abilities.try_cast(LT), "heals instead")
	check(ally.downed, "still downed")
	check(p.hp > 5.0, "Paladin healed")
	check_eq(res.value, 0.0, "spent")


func test_word_of_glory_heals_self_and_most_hurt_ally() -> void:
	var p := _paladin()
	p.stats.set_source(&"test", {Stats.SPELL_POWER: 2.0})
	p.hp = 4.0
	var hurt := Fakes.spawn_player(world, 1, &"warrior", Vector3(4.0, 0, 0))
	hurt.hp = 3.0
	var scratched := Fakes.spawn_player(world, 2, &"rogue", Vector3(-3.0, 0, 0))
	scratched.hp = 6.0
	var far := Fakes.spawn_player(world, 3, &"mage", Vector3(0, 0, 12.0))
	far.hp = 1.0
	_holy_power(p).set_value(3.0)
	var ctx := p.abilities.build_context(p.abilities.slots[LT])
	check(ctx.target == hurt, "most hurt ally in range")
	check(p.abilities.try_cast(LT), "cast")
	# 3 + 25% of max HP + 2 Spell Power
	check_near(p.hp, minf(p.max_hp(), 4.0 + 3.0 + p.max_hp() * 0.25 + 2.0), 0.001, "Paladin healed")
	check_near(hurt.hp, minf(hurt.max_hp(), 3.0 + 3.0 + hurt.max_hp() * 0.25 + 2.0), 0.001, "ally healed")
	check_eq(scratched.hp, 6.0, "only one ally")
	check_eq(far.hp, 1.0, "out of range")
	check_eq(_holy_power(p).value, 0.0, "spent")


func test_word_of_glory_never_wastes_holy_power() -> void:
	var p := _paladin()
	Fakes.spawn_player(world, 1, &"warrior", Vector3(3.0, 0, 0))
	_holy_power(p).set_value(3.0)
	check(not p.abilities.can_cast(LT), "everybody healthy: not castable")
	check(not p.abilities.try_cast(LT), "no cast")
	check_eq(_holy_power(p).value, 3.0, "kept")


func test_libram_reduces_word_of_glory_cost() -> void:
	var p := _paladin()
	_equip_unique(p, &"libram_of_devotion")
	var wog := p.abilities.slots[LT]
	check_eq(p.abilities.cost_of(wog, p.abilities.build_context(wog)), 2.0, "costs 1 less")
	var ally := Fakes.spawn_player(world, 1, &"warrior", Vector3(3.0, 0, 0))
	_down(ally)
	_holy_power(p).set_value(2.0)
	check(p.abilities.is_ready(LT), "HUD: ready with 2 Holy Power")
	check(p.abilities.try_cast(LT), "cast with 2 Holy Power")
	check(not ally.downed, "revived")
	check_eq(_holy_power(p).value, 0.0, "2 spent")


func test_word_of_glory_bot_decisions() -> void:
	var p := _paladin()
	var wog := p.abilities.slots[LT]
	var effect := p.abilities.effect_for(wog)
	var ally := Fakes.spawn_player(world, 1, &"warrior", Vector3(5.0, 0, 0))
	check(not effect.wants_auto_cast(p.abilities.build_context(wog)), "everybody healthy")
	ally.hp = ally.max_hp() * 0.7
	check(not effect.wants_auto_cast(p.abilities.build_context(wog)), "ally at 70%: wait")
	ally.hp = ally.max_hp() * 0.4
	check(effect.wants_auto_cast(p.abilities.build_context(wog)), "ally below 50%: heal")
	ally.hp = ally.max_hp()
	p.hp = p.max_hp() * 0.4
	check(effect.wants_auto_cast(p.abilities.build_context(wog)), "self below 50%: heal")
	p.hp = p.max_hp()
	_down(ally)
	check(effect.wants_auto_cast(p.abilities.build_context(wog)), "downed ally in range: revive")
	ally.global_position = Vector3(9.0, 0, 0)
	check(not effect.wants_auto_cast(p.abilities.build_context(wog)), "downed ally beyond 8 m")


func test_bot_paladin_auto_revives() -> void:
	var slot := PlayerSlot.new(0, BotInput.new("bot:paladin", 7), PlayerManager.PLAYER_COLORS[0])
	slot.class_data = Db.get_class_data(&"paladin")
	var p := Player.create(slot)
	world.add_child(p)
	check(p.abilities.auto_cast, "bots auto-cast")
	var ally := Fakes.spawn_player(world, 1, &"warrior", Vector3(4.0, 0, 0))
	_down(ally)
	_holy_power(p).set_value(3.0)
	for i in 30:
		p.abilities._physics_process(DT)
	check(not ally.downed, "bot revived the ally with Word of Glory")
	check_eq(_holy_power(p).value, 0.0, "spent")


# --- Aura of Devotion -------------------------------------------------------------------------

func test_aura_applies_and_removes() -> void:
	var p := _paladin()
	var aura := p.abilities.mastery as PaladinAuraOfDevotion
	var key := aura.source_key()
	check_eq(key, &"aura:paladin0", "per-Paladin source (slot index)")
	var near := Fakes.spawn_player(world, 1, &"warrior", Vector3(4.0, 0, 0))
	var far := Fakes.spawn_player(world, 2, &"rogue", Vector3(0, 0, 7.0))
	aura.refresh()
	check(not near.stats.has_source(key), "no Mastery: no aura")
	p.stats.set_source(&"test", {Stats.MASTERY: 4.0})
	var armor_before := near.stats.get_stat(Stats.ARMOR)
	aura.tick(0.6)
	check(near.stats.has_source(key), "ally within 6 m")
	check(p.stats.has_source(key), "the Paladin too")
	check(not far.stats.has_source(key), "not beyond 6 m")
	check_near(near.stats.get_stat(Stats.ARMOR) - armor_before, 2.0, 0.001, "+0.5 Armor per point")
	check_near(near.stats.get_raw(Stats.SPIRIT), 4.0, 0.001, "+1 Spirit per point")
	check(near.stats.hp_regen_per_second() > 0.0, "regenerates HP")
	check_eq(aura.affected().size(), 2, "two heroes inside")
	# Leaves the circle.
	near.global_position = Vector3(6.5, 0, 0)
	aura.tick(0.6)
	check(not near.stats.has_source(key), "removed out of range")
	near.global_position = Vector3(2.0, 0, 0)
	aura.tick(0.6)
	check(near.stats.has_source(key), "back in range")
	# Mastery changes update the values.
	p.stats.set_source(&"test", {Stats.MASTERY: 6.0})
	aura.tick(0.6)
	check_near(near.stats.get_raw(Stats.SPIRIT), 6.0, 0.001, "follows Mastery")
	# A downed ally loses it.
	_down(near)
	aura.tick(0.6)
	check(not near.stats.has_source(key), "downed ally loses the aura")
	near.revive(0.5)
	aura.tick(0.6)
	check(near.stats.has_source(key), "revived ally gets it back")


func test_aura_ends_when_paladin_goes_down_or_leaves() -> void:
	var p := _paladin()
	p.stats.set_source(&"test", {Stats.MASTERY: 4.0})
	var aura := p.abilities.mastery as PaladinAuraOfDevotion
	var key := aura.source_key()
	var ally := Fakes.spawn_player(world, 1, &"warrior", Vector3(3.0, 0, 0))
	aura.tick(0.6)
	check(ally.stats.has_source(key), "applied")
	_down(p)
	check(not ally.stats.has_source(key), "downed Paladin: aura gone at once")
	check(not p.stats.has_source(key), "also from the Paladin")
	p.abilities._physics_process(1.0)
	check(not ally.stats.has_source(key), "no ticks while downed")
	p.revive(0.5)
	check(ally.stats.has_source(key), "back when revived")
	world.remove_child(p)
	check(not ally.stats.has_source(key), "removed when the Paladin leaves (teardown)")
	p.free()


func test_aura_ends_with_the_wave() -> void:
	var p := _paladin()
	p.stats.set_source(&"test", {Stats.MASTERY: 4.0})
	var aura := p.abilities.mastery as PaladinAuraOfDevotion
	var key := aura.source_key()
	var ally := Fakes.spawn_player(world, 1, &"warrior", Vector3(3.0, 0, 0))
	var own_armor := ally.stats.get_stat(Stats.ARMOR)
	var own_spirit := p.stats.get_raw(Stats.SPIRIT)
	p.abilities._physics_process(DT)
	check(ally.stats.has_source(key) and p.stats.has_source(key), "applied")
	p.end_wave()
	check(not ally.stats.has_source(key), "the market shows the ally's own stats")
	check(not p.stats.has_source(key), "and the Paladin's")
	check_near(ally.stats.get_stat(Stats.ARMOR), own_armor, 0.0001, "no aura Armor in the market")
	check_near(p.stats.get_raw(Stats.SPIRIT), own_spirit, 0.0001, "no aura Spirit in the market")
	check_eq(aura.affected().size(), 0, "nobody inside")
	p.begin_wave()
	p.abilities._physics_process(DT)
	check(ally.stats.has_source(key), "back with the first tick of the next wave")


func test_downed_paladin_grants_no_aura_while_its_mastery_ticks() -> void:
	var p := _paladin()
	p.stats.set_source(&"test", {Stats.MASTERY: 4.0})
	var aura := p.abilities.mastery as PaladinAuraOfDevotion
	var key := aura.source_key()
	_down(p)
	var ally := Fakes.spawn_player(world, 1, &"warrior", Vector3(1.0, 0, 0))
	for i in 120:
		p.abilities._physics_process(DT)
	check(not ally.stats.has_source(key), "an ally next to the downed Paladin gets nothing")
	check(not p.stats.has_source(key), "nor the Paladin")
	aura.refresh()
	check(not ally.stats.has_source(key), "not even on a forced refresh")
	p.revive(0.5)
	check(ally.stats.has_source(key), "back at the revive")


func test_two_paladin_auras_stack() -> void:
	var a := _paladin(Vector3.ZERO, 0)
	var b := _paladin(Vector3(2.0, 0, 0), 1)
	for p: Player in [a, b]:
		p.stats.set_source(&"test", {Stats.MASTERY: 2.0})
	var ally := Fakes.spawn_player(world, 2, &"warrior", Vector3(1.0, 0, 0))
	(a.abilities.mastery as PaladinAuraOfDevotion).refresh()
	(b.abilities.mastery as PaladinAuraOfDevotion).refresh()
	check_near(ally.stats.get_raw(Stats.SPIRIT), 4.0, 0.001, "one source per Paladin")
