extends TestCase
## M6 ARTIFACTS: the ten properties (GDD 5.5) as the hero experiences them – the Artifact source
## of PlayerBonuses, and every property's effect: Earthsplitter (Whirlwind quake, Charge
## shockwave), Staff of the Frostwyrm (every 4th Blizzard, frost shards), Dawnbreaker
## (Consecration heals, Word of Glory shields), Fangs of the Shadow (free Fan of Knives every 5th
## crit, 3 crits after Vanish), Skull of the Damned (a second Voidwalker, +25% pet damage and leech).

const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0

var world: Node3D
var arena: EFakesArena


## The enemies-test arena (a bare Arena with an entities root) as a short alias.
class EFakesArena extends Arena:
	func _init() -> void:
		name = "ArtifactTestArena"
		entities = Node3D.new()
		entities.name = "Entities"
		add_child(entities)

	func _enter_tree() -> void:
		Arena.current = self

	func _exit_tree() -> void:
		if Arena.current == self:
			Arena.current = null

	func _ready() -> void:
		pass

	func _process(_delta: float) -> void:
		pass

	func _physics_process(_delta: float) -> void:
		pass

	func get_bounds() -> Rect2:
		return Rect2(-Arena.SIZE / 2.0, Arena.SIZE)

	func clamp_point(p: Vector3, margin: float = 0.5) -> Vector3:
		var b := get_bounds().grow(-margin)
		return Vector3(clampf(p.x, b.position.x, b.end.x), p.y, clampf(p.z, b.position.y, b.end.y))


func before_each() -> void:
	PlayerManager.clear()
	RunState.start_run(2, 777)
	RunState.set_wave(10)
	Enemy.invalidate_player_cache()
	world = Fakes.make_world(tree)
	arena = EFakesArena.new()
	world.add_child(arena)


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	arena = null
	PlayerManager.clear()
	Enemy.invalidate_player_cache()
	EnemyGrid.mark_dirty()
	RunState.start_run(1, 1)


# --- Helpers ----------------------------------------------------------------------------

## A hero of [param class_id] wearing its Artifact with [param waves] wave ends held.
func _hero(class_id: StringName, waves: int, index: int = 0, pos: Vector3 = Vector3.ZERO) -> Player:
	var p := Fakes.spawn_player(world, index, class_id, pos)
	p.stats.set_source(&"tough", {Stats.STAMINA: 500.0})
	p.hp = p.max_hp()
	var item := ItemGenerator.generate_artifact(class_id, 10)
	_set_waves(item, waves)
	p.equipment.backpack.append(item)
	check(p.equipment.equip(item), "%s equips its Artifact" % class_id)
	return p


func _set_waves(item: ItemInstance, waves: int) -> void:
	item.artifact_waves = waves
	if item.companion != null:
		item.companion.artifact_waves = waves


func _artifact_of(p: Player) -> ItemInstance:
	return p.equipment.get_item(Items.EquipSlot.MAIN_HAND)


## Re-applies the equipment after the test changed the wave count.
func _refresh(p: Player) -> void:
	p.equipment.changed.emit()


func _plain(class_id: StringName, index: int = 0, pos: Vector3 = Vector3.ZERO) -> Player:
	var p := Fakes.spawn_player(world, index, class_id, pos)
	p.stats.set_source(&"tough", {Stats.STAMINA: 500.0})
	p.hp = p.max_hp()
	return p


func _fake(pos: Vector3) -> Fakes.FakeEnemy:
	var e := Fakes.spawn_enemy(world, pos)
	EnemyGrid.mark_dirty()
	return e


func _real(pos: Vector3) -> Enemy:
	var e := Enemy.create(Db.get_enemy(&"skeleton_grunt"), 1)
	arena.entities.add_child(e)
	e.global_position = pos
	EnemyGrid.mark_dirty()
	return e


func _areas() -> Array[AbilityArea]:
	var out: Array[AbilityArea] = []
	for node in tree.get_nodes_in_group(&"ability_areas"):
		var a := node as AbilityArea
		if a != null and not a.is_queued_for_deletion():
			out.append(a)
	return out


func _step(p: Player, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		p.abilities._physics_process(DT)
		p.bonuses.tick(DT)
		t += DT


func _ability(p: Player, id: StringName) -> AbilityData:
	return Db.get_ability(id)


func _param(p: Player, id: StringName, key: String) -> float:
	return float(p.abilities.params_for(Db.get_ability(id)).get(key, 0.0))


# --- The engine source -------------------------------------------------------------------

func test_properties_reach_the_bonus_engine_only_when_awake_and_equipped() -> void:
	var p := _hero(&"warrior", 0)
	check(p.bonuses.effects_of(Artifacts.SOURCE).is_empty(), "asleep: nothing in the engine")
	check_eq(_param(p, &"whirlwind", "quake_pct"), 0.0, "no quake yet")
	for i in 3:
		p.end_wave()
	check_eq(p.bonuses.effects_of(Artifacts.SOURCE).size(), 1, "property 1 after three wave ends")
	check_eq(_param(p, &"whirlwind", "quake_pct"), 30.0, "Whirlwind quake: 30% weapon damage")
	check_eq(_param(p, &"whirlwind", "quake_duration"), 3.0, "for 3 sec")
	check_eq(_param(p, &"charge", "shockwave_radius"), 0.0, "Charge unchanged")
	for i in 3:
		p.end_wave()
	check_eq(p.bonuses.effects_of(Artifacts.SOURCE).size(), 2, "property 2 after six")
	check_eq(_param(p, &"charge", "shockwave_radius"), 3.0, "Charge shockwave: 3 m")
	check_eq(_param(p, &"charge", "shockwave_stun"), 1.0, "1 sec")


func test_swapping_the_artifact_out_takes_its_properties_with_it() -> void:
	var p := _hero(&"warrior", 6)
	check_eq(p.bonuses.effects_of(Artifacts.SOURCE).size(), 2, "both awake")
	var axe := ItemInstance.from_weapon(Db.get_weapon(&"two_hand_axe"), Items.Rarity.RARE, 5)
	p.equipment.backpack.append(axe)
	check(p.equipment.equip(axe), "an ordinary axe replaces it")
	check(p.bonuses.effects_of(Artifacts.SOURCE).is_empty(), "the source is empty again")
	check_eq(_param(p, &"whirlwind", "quake_pct"), 0.0, "no quake")
	check_eq(_param(p, &"charge", "shockwave_stun"), 0.0, "no shockwave")


func test_ordinary_heroes_never_get_an_artifact_source() -> void:
	var p := _plain(&"warrior")
	check(p.bonuses.effects_of(Artifacts.SOURCE).is_empty(), "nothing")
	p.end_wave()
	check(p.bonuses.effects_of(Artifacts.SOURCE).is_empty(), "still nothing")


func test_the_growth_raises_the_weapon_a_runner_attacks_with() -> void:
	var p := _hero(&"warrior", 0)
	var weapon := p.main_hand
	var before := weapon.base_damage
	p.end_wave()
	check(p.main_hand == weapon, "the same weapon object stays in hand")
	check_near(p.main_hand.base_damage, before * 1.04, 0.0001, "+4% weapon damage after one wave end")
	check_near(p.weapons[0].weapon.base_damage, before * 1.04, 0.0001, "the runner sees it")


# --- Earthsplitter -----------------------------------------------------------------------

func test_whirlwind_leaves_an_earthquake_zone() -> void:
	var p := _hero(&"warrior", 3)
	_fake(Vector3(1.5, 0.0, 0.0))
	p.abilities.get_resource(&"rage").set_value(100.0)
	var base_areas := _areas().size()
	check(p.abilities.try_cast(0), "Whirlwind")
	var zones := _areas()
	check_eq(zones.size(), base_areas + 1, "an earthquake zone appeared")
	var zone := zones[zones.size() - 1]
	check_near(zone.duration, 3.0, 0.001, "it stays for 3 sec")
	check_near(zone.damage_per_tick, WarriorKit.weapon_damage(p) * 0.30, 0.01, "30% weapon damage per tick")
	check_near(zone.radius, 3.0, 0.001, "the spin's radius")
	check_eq(zone.school, &"physical", "physical")
	check(zone.owner_player == p, "credited to the Warrior")


func test_whirlwind_without_the_artifact_leaves_no_zone() -> void:
	var p := _plain(&"warrior")
	_fake(Vector3(1.5, 0.0, 0.0))
	p.abilities.get_resource(&"rage").set_value(100.0)
	check(p.abilities.try_cast(0), "Whirlwind")
	check(_areas().is_empty(), "no zone")
	var asleep := _hero(&"warrior", 2, 1, Vector3(10.0, 0.0, 10.0))
	asleep.abilities.get_resource(&"rage").set_value(100.0)
	check(asleep.abilities.try_cast(0), "cast")
	check(_areas().is_empty(), "no zone while the property sleeps")


func test_the_earthquake_zone_hurts_the_enemies_in_it_every_tick() -> void:
	var p := _hero(&"warrior", 3)
	var inside := _fake(Vector3(2.0, 0.0, 0.0))
	var outside := _fake(Vector3(9.0, 0.0, 0.0))
	p.abilities.get_resource(&"rage").set_value(100.0)
	p.abilities.try_cast(0)
	var spin_hits := inside.fake_hits()
	for zone in _areas():
		for i in 130:
			zone._physics_process(DT)
	check(inside.fake_hits() > spin_hits, "the zone ticked on the enemy inside")
	check_eq(outside.fake_hits(), 0, "not on the one outside")


func test_charge_ends_in_a_shockwave_that_stuns_within_3_m() -> void:
	var p := _hero(&"warrior", 6)
	(p.slot.input as ScriptedInput).move = Vector2(1.0, 0.0)
	var near_landing := _real(Vector3(7.0, 0.0, 2.6))   # outside the 2 m landing stun, inside 3 m
	var far := _real(Vector3(7.0, 0.0, 6.0))
	check(p.abilities.try_cast(1), "Charge")
	_step(p, 0.7)
	check(near_landing.stun_left > 0.5, "stunned by the shockwave (2.6 m from the landing)")
	check_eq(far.stun_left, 0.0, "6 m away: not")
	var plain := _plain(&"warrior", 1, Vector3(0.0, 0.0, 30.0))
	arena.entities.global_position = Vector3.ZERO
	(plain.slot.input as ScriptedInput).move = Vector2(1.0, 0.0)
	var control := _real(Vector3(7.0, 0.0, 32.6))
	check(plain.abilities.try_cast(1), "a Warrior without the Artifact charges")
	_step(plain, 0.7)
	check_eq(control.stun_left, 0.0, "the same enemy at 2.6 m is not stunned without it")


# --- Staff of the Frostwyrm --------------------------------------------------------------

func test_every_fourth_blizzard_has_double_radius() -> void:
	var p := _hero(&"mage", 3)
	_fake(Vector3(3.0, 0.0, 0.0))
	var blizzard := Db.get_ability(&"blizzard")
	var effect := p.abilities.effect_for(blizzard)
	var radii: Array[float] = []
	for i in 8:
		var ctx := p.abilities.build_context(blizzard)
		check(ctx.target != null, "a target for Blizzard %d" % (i + 1))
		var before := _areas().size()
		check(effect.cast(ctx), "cast %d" % (i + 1))
		var zones := _areas()
		radii.append(zones[zones.size() - 1].radius)
		check_eq(zones.size(), before + 1, "a new storm")
	check_near(radii[0], 3.5, 0.001, "1st: normal")
	check_near(radii[1], 3.5, 0.001, "2nd: normal")
	check_near(radii[2], 3.5, 0.001, "3rd: normal")
	check_near(radii[3], 7.0, 0.001, "4th: double the radius")
	check_near(radii[4], 3.5, 0.001, "5th: normal again")
	check_near(radii[7], 7.0, 0.001, "8th: double")


func test_blizzard_is_normal_without_the_artifact_or_while_asleep() -> void:
	for waves in [-1, 2]:
		var p := _plain(&"mage", 0) if waves < 0 else _hero(&"mage", waves, 1)
		_fake(Vector3(3.0, 0.0, 0.0))
		var blizzard := Db.get_ability(&"blizzard")
		var effect := p.abilities.effect_for(blizzard)
		for i in 5:
			effect.cast(p.abilities.build_context(blizzard))
		for zone in _areas():
			check_near(zone.radius, 3.5, 0.001, "never doubled (waves %d)" % waves)
		for zone in _areas():
			zone.queue_free()


func test_enemies_killed_slowed_or_frozen_burst_into_frost_shards() -> void:
	var p := _hero(&"mage", 6)
	var victim := _real(Vector3(10.0, 0.0, 0.0))
	var neighbour := _real(Vector3(11.5, 0.0, 0.0))
	var far := _real(Vector3(16.0, 0.0, 0.0))
	victim.apply_slow(30.0, 3.0)
	p.notify_kill(victim)
	check(neighbour.is_slowed(), "the neighbour within 3 m is slowed")
	check_near(neighbour.slow_pct, 40.0, 0.001, "by 40%")
	check_near(neighbour.slow_left, 2.0, 0.01, "for 2 sec")
	check(not far.is_slowed(), "the far one is not")
	# A victim that was neither slowed nor frozen makes no shards.
	var calm := _real(Vector3(-10.0, 0.0, 0.0))
	var calm_neighbour := _real(Vector3(-11.0, 0.0, 0.0))
	p.notify_kill(calm)
	check(not calm_neighbour.is_slowed(), "no shards from a healthy corpse")


func test_a_frozen_kill_also_bursts() -> void:
	var p := _hero(&"mage", 6)
	var victim := _real(Vector3(10.0, 0.0, 0.0))
	var neighbour := _real(Vector3(11.0, 0.0, 0.0))
	check(MageSpell.freeze(victim, p, 2.0) != null, "froze the victim")
	check(MageFrozen.is_frozen(victim), "it is frozen")
	check(not victim.is_slowed(), "(frozen, not slowed)")
	p.notify_kill(victim)
	check(neighbour.is_slowed(), "frost shards from a frozen kill")


## The shipped numbers of the Staff of the Frostwyrm's Shatterfrost (GDD 5.5: slow enemies within
## 3 m by 40% for 2 sec) – read from the .tres, not from a test-made effect.
func test_the_shipped_frost_shard_data_is_3_m_40_percent_2_sec() -> void:
	var data := Db.get_artifact(&"staff_of_the_frostwyrm")
	check(data != null and data.properties.size() == 2, "the shipped Staff of the Frostwyrm")
	var entry: Dictionary = (data.properties[1]["effects"] as Array)[0]
	check_eq(entry.get("kind"), "script", "a script effect")
	check_eq(entry.get("script"), "res://scenes/artifacts/mage_frost_shards.gd", "the frost shards script")
	var params: Dictionary = entry.get("params", {})
	check_near(float(params.get("radius", 0.0)), 3.0, 0.0001, "radius 3 m")
	check_near(float(params.get("slow", 0.0)), 40.0, 0.0001, "slow 40%")
	check_near(float(params.get("duration", 0.0)), 2.0, 0.0001, "duration 2 sec")
	check("within 3 m by 40% for 2 sec" in str(data.properties[1]["text"]), "and the tooltip text says the same")


## The 3 m of the shipped data, felt in the world: the burst reaches an enemy 2.7 m from the
## corpse and stops short of one 3.5 m away.
func test_the_frost_shards_reach_3_m_from_the_corpse() -> void:
	var p := _hero(&"mage", 6)
	var victim := _real(Vector3(10.0, 0.0, 0.0))
	var inside := _real(Vector3(12.7, 0.0, 0.0))
	var outside := _real(Vector3(13.5, 0.0, 0.0))
	victim.apply_slow(30.0, 3.0)
	p.notify_kill(victim)
	check(inside.is_slowed(), "2.7 m from the corpse: slowed")
	check_near(inside.slow_pct, 40.0, 0.001, "by 40%")
	check_near(inside.slow_left, 2.0, 0.01, "for 2 sec")
	check(not outside.is_slowed(), "3.5 m from the corpse: not")


func test_frost_shards_wait_for_the_second_property() -> void:
	var p := _hero(&"mage", 3)
	var victim := _real(Vector3(10.0, 0.0, 0.0))
	var neighbour := _real(Vector3(11.0, 0.0, 0.0))
	victim.apply_slow(30.0, 3.0)
	p.notify_kill(victim)
	check(not neighbour.is_slowed(), "property 2 sleeps after three wave ends")


# --- Dawnbreaker -------------------------------------------------------------------------

func test_consecration_heals_the_allies_standing_in_it() -> void:
	var p := _hero(&"paladin", 3)
	var ally := _plain(&"warrior", 1, Vector3(1.0, 0.0, 0.0))
	var away := _plain(&"mage", 2, Vector3(15.0, 0.0, 0.0))
	ally.hp = ally.max_hp() * 0.4
	away.hp = away.max_hp() * 0.4
	var ally_before := ally.hp
	var away_before := away.hp
	_fake(Vector3(2.0, 0.0, 0.0))
	check(p.abilities.try_cast(0), "Consecration")
	_step(p, 2.0)
	var healed := ally.hp - ally_before
	# Heals 2% of max HP per second: about 4 ticks of 1% in 2 s (the first at the cast).
	check(healed >= ally.max_hp() * 0.01 - 0.01, "the ally standing in it heals")
	check_near(healed, ally.max_hp() * 0.02 * 2.0, ally.max_hp() * 0.015, "about 2%% max HP per second (%.1f)" % healed)
	check_eq(away.hp, away_before, "the one outside does not")


func test_consecration_heals_nobody_without_the_artifact() -> void:
	var p := _plain(&"paladin")
	var ally := _plain(&"warrior", 1, Vector3(1.0, 0.0, 0.0))
	ally.hp = ally.max_hp() * 0.4
	var before := ally.hp
	_fake(Vector3(2.0, 0.0, 0.0))
	p.abilities.try_cast(0)
	_step(p, 2.0)
	check_eq(ally.hp, before, "no heal")


func test_word_of_glory_also_shields_its_target_for_15_percent_of_max_hp() -> void:
	var p := _hero(&"paladin", 6)
	var ally := _plain(&"warrior", 1, Vector3(1.0, 0.0, 0.0))
	ally.hp = ally.max_hp() * 0.3
	p.hp = p.max_hp() * 0.3
	var wog := Db.get_ability(&"word_of_glory")
	var ctx := p.abilities.build_context(wog)
	check_eq(ctx.num("shield_max_hp_pct"), 15.0, "the param is on")
	check(p.abilities.effect_for(wog).cast(ctx), "Word of Glory")
	check_near(ally.procs.shield_of(PaladinWordOfGlory.ARTIFACT_SHIELD), ally.max_hp() * 0.15, 0.01, "15% of the ally's max HP")
	check_near(p.procs.shield_of(PaladinWordOfGlory.ARTIFACT_SHIELD), p.max_hp() * 0.15, 0.01, "and of the Paladin's own")
	# A second cast tops up, it does not stack past the 15%.
	p.abilities.effect_for(wog).cast(p.abilities.build_context(wog))
	check_near(ally.procs.shield_of(PaladinWordOfGlory.ARTIFACT_SHIELD), ally.max_hp() * 0.15, 0.01, "never more than 15%")


func test_word_of_glory_also_shields_a_raised_teammate() -> void:
	var p := _hero(&"paladin", 6)
	var ally := _plain(&"warrior", 1, Vector3(1.0, 0.0, 0.0))
	ally.invulnerable_left = 0.0
	ally.hp = 1.0
	ally.take_damage(1000.0)
	check(ally.downed, "down")
	var wog := Db.get_ability(&"word_of_glory")
	check(p.abilities.effect_for(wog).cast(p.abilities.build_context(wog)), "raised")
	check(not ally.downed, "back up")
	check_near(ally.procs.shield_of(PaladinWordOfGlory.ARTIFACT_SHIELD), ally.max_hp() * 0.15, 0.01, "with a shield")


func test_word_of_glory_has_no_shield_without_the_artifact() -> void:
	var p := _plain(&"paladin")
	p.hp = p.max_hp() * 0.3
	var wog := Db.get_ability(&"word_of_glory")
	p.abilities.effect_for(wog).cast(p.abilities.build_context(wog))
	check_eq(p.procs.shield_of(PaladinWordOfGlory.ARTIFACT_SHIELD), 0.0, "none")


# --- Fangs of the Shadow -----------------------------------------------------------------

func test_every_fifth_crit_throws_a_free_fan_of_knives() -> void:
	var p := _hero(&"rogue", 3)
	_fake(Vector3(3.0, 0.0, 0.0))
	var fangs := p.bonuses.script_for(&"artifact:fangs_of_the_shadow:0") as ArtifactRogueFangsFan
	check(fangs != null, "the script is live after three wave ends")
	var energy := p.abilities.get_resource(&"energy")
	var before: float = energy.value
	var cooldown := p.abilities.cooldown_left(Db.get_ability(&"fan_of_knives"))
	for i in 4:
		fangs.on_hit(null, 5.0, true, true)
	check_eq(fangs.fans, 0, "four crits: no fan yet")
	fangs.on_hit(null, 5.0, false, true)
	fangs.on_hit(null, 5.0, true, false)
	check_eq(fangs.crits, 4, "non-crits and non-first hits do not count")
	fangs.on_hit(null, 5.0, true, true)
	check_eq(fangs.fans, 1, "the fifth crit threw a fan")
	check_eq(fangs.crits, 0, "the count starts over")
	check_eq(energy.value, before, "it cost no Energy")
	check_eq(p.abilities.cooldown_left(Db.get_ability(&"fan_of_knives")), cooldown, "and started no cooldown")
	fangs.tick(3.1)
	for i in 5:
		fangs.on_hit(null, 5.0, true, true)
	check_eq(fangs.fans, 2, "every fifth again")


## Final balance 2: the free fans have a cooldown (3 s), a fifth crit inside it waits.
func test_the_free_fan_has_a_cooldown_and_a_waiting_fifth_crit_throws_after_it() -> void:
	var p := _hero(&"rogue", 3)
	_fake(Vector3(3.0, 0.0, 0.0))
	var fangs := p.bonuses.script_for(&"artifact:fangs_of_the_shadow:0") as ArtifactRogueFangsFan
	check_eq(fangs.num("cooldown"), 3.0, "the artifact data says 3 s")
	for i in 5:
		fangs.on_hit(null, 5.0, true, true)
	check_eq(fangs.fans, 1, "the first fan")
	check_near(fangs.cooldown_left, 3.0, 0.0001, "the cooldown runs")
	for i in 12:
		fangs.on_hit(null, 5.0, true, true)
	check_eq(fangs.fans, 1, "twelve more crits inside the cooldown throw nothing")
	check_eq(fangs.crits, 5, "the count waits at 'ready'")
	fangs.tick(2.0)
	fangs.on_hit(null, 5.0, true, true)
	check_eq(fangs.fans, 1, "still 1 s of the cooldown left")
	fangs.tick(1.1)
	check_eq(fangs.cooldown_left, 0.0, "the cooldown is over")
	fangs.on_hit(null, 5.0, false, true)
	check_eq(fangs.fans, 1, "a plain hit does not throw it")
	fangs.on_hit(null, 5.0, true, true)
	check_eq(fangs.fans, 2, "the next crit throws the waiting fan")
	check_eq(fangs.crits, 0, "and the count starts over")
	check(fangs.describe().contains("at most once every 3 sec"), "the description names the cooldown: %s" % fangs.describe())


func test_a_free_fan_really_throws_knives() -> void:
	var p := _hero(&"rogue", 3)
	var before := 0
	for n in arena.entities.get_children():
		if n is RogueBlade:
			before += 1
	var fangs := p.bonuses.script_for(&"artifact:fangs_of_the_shadow:0") as ArtifactRogueFangsFan
	for i in 5:
		fangs.on_hit(null, 5.0, true, true)
	var after := 0
	for n in arena.entities.get_children():
		if n is RogueBlade:
			after += 1
	check(after > before, "knives are in the air (%d new)" % (after - before))


func test_the_fan_property_sleeps_before_three_wave_ends() -> void:
	var p := _hero(&"rogue", 2)
	check(p.bonuses.script_for(&"artifact:fangs_of_the_shadow:0") == null, "no script yet")


func test_vanish_grants_three_crits_with_the_second_property() -> void:
	var p := _hero(&"rogue", 6)
	check_eq(_param(p, &"vanish", "forced_crits"), 3.0, "Vanish: 3 guaranteed crits")
	var vanish := Db.get_ability(&"vanish")
	check(p.abilities.effect_for(vanish).cast(p.abilities.build_context(vanish)), "Vanish")
	check_eq(p.forced_crits, 3, "the next 3 hits are crits")
	var asleep := _hero(&"rogue", 5, 1)
	check_eq(_param(asleep, &"vanish", "forced_crits"), 1.0, "asleep: the normal 1")
	var plain := _plain(&"rogue", 2)
	check_eq(_param(plain, &"vanish", "forced_crits"), 1.0, "ordinary: 1")


# --- Skull of the Damned -----------------------------------------------------------------

func _voidwalkers() -> Array[WarlockVoidwalker]:
	var out: Array[WarlockVoidwalker] = []
	for n in arena.entities.get_children():
		var v := n as WarlockVoidwalker
		if v != null and not v.is_queued_for_deletion() and not v.is_leaving():
			out.append(v)
	return out


func test_a_second_permanent_voidwalker_stands_at_the_warlocks_side() -> void:
	var p := _hero(&"warlock", 3)
	var script := p.bonuses.script_for(&"artifact:skull_of_the_damned:0") as ArtifactWarlockSecondVoidwalker
	check(script != null, "the script is live after three wave ends")
	check_eq(_voidwalkers().size(), 0, "nothing summoned in the market")
	_step(p, 0.1)
	check_eq(_voidwalkers().size(), 1, "a Voidwalker after the first tick of the wave")
	check(script.has_pet(), "the script owns it")
	_step(p, 3.0)
	check_eq(_voidwalkers().size(), 1, "and it stays one")
	var p2 := _plain(&"warlock", 1, Vector3(20.0, 0.0, 0.0))
	check_eq(_voidwalkers().size(), 1, "an ordinary Warlock's Imp is not a Voidwalker")
	p2.free()


func test_the_second_voidwalker_taunts_and_stands_next_to_the_ability_one() -> void:
	var p := _hero(&"warlock", 3)
	p.abilities.learn(Db.get_ability(&"summon_voidwalker"))
	_step(p, 0.2)
	check_eq(_voidwalkers().size(), 2, "the ability's Voidwalker and the Artifact's")
	var enemy := _real(Vector3(3.0, 0.0, 0.0))
	_step(p, 2.0)
	check(enemy.is_taunted(), "an enemy near them is taunted onto a Voidwalker")
	check_eq(p.damage_taken_mults.size(), 0, "no ward from the Artifact's pet")


func test_the_second_voidwalker_leaves_with_the_wave_and_the_warlock() -> void:
	var p := _hero(&"warlock", 3)
	_step(p, 0.1)
	check_eq(_voidwalkers().size(), 1, "stands")
	p.end_wave()
	check_eq(_voidwalkers().size(), 0, "gone at the wave end")
	p.begin_wave()
	_step(p, 0.1)
	check_eq(_voidwalkers().size(), 1, "back in the next wave")
	p.invulnerable_left = 0.0
	p.hp = 1.0
	p.take_damage(10000.0)
	check(p.downed, "down")
	_step(p, 0.1)
	await_pet_gone(p)


func await_pet_gone(p: Player) -> void:
	for v in _voidwalkers():
		v._physics_process(DT)
	check_eq(_voidwalkers().size(), 0, "a downed Warlock loses it")
	p.revive()
	_step(p, 0.1)
	check_eq(_voidwalkers().size(), 1, "and it returns after the revive")


func test_pets_deal_25_percent_more_and_heal_the_warlock_for_10_percent() -> void:
	var plain := _plain(&"warlock", 1, Vector3(20.0, 0.0, 0.0))
	var base := plain.outgoing_damage_mult(null, &"shadow", &"pet")
	var p := _hero(&"warlock", 6)
	check_near(p.outgoing_damage_mult(null, &"shadow", &"pet") / base, 1.25, 0.001, "pets +25%")
	check_near(p.outgoing_damage_mult(null, &"shadow", &"weapon") / plain.outgoing_damage_mult(null, &"shadow", &"weapon"),
			1.0, 0.001, "weapon hits unchanged")
	check_eq(p.pet_leech_pct, 10.0, "10% leech")
	var target := _fake(Vector3(3.0, 0.0, 0.0))
	p.hp = p.max_hp() * 0.5
	var before := p.hp
	var dealt := p.procs.deal_raw(target, 100.0, &"shadow", false, &"pet")
	check_near(p.hp - before, dealt * 0.10, 0.01, "healed for 10%% of the pet damage (%.1f)" % (p.hp - before))
	before = p.hp
	p.procs.deal_raw(target, 100.0, &"shadow", false, &"proc")
	check_eq(p.hp, before, "only pet damage heals")
	check_eq(plain.pet_leech_pct, 0.0, "an ordinary Warlock does not")


func test_the_pet_bonus_goes_with_the_artifact() -> void:
	var p := _hero(&"warlock", 6)
	check_eq(p.pet_leech_pct, 10.0, "on")
	var staff := ItemInstance.from_weapon(Db.get_weapon(&"staff"), Items.Rarity.RARE, 5)
	p.equipment.backpack.append(staff)
	check(p.equipment.equip(staff), "an ordinary staff")
	check_eq(p.pet_leech_pct, 0.0, "the leech is gone")
	check_near(p.outgoing_damage_mult(null, &"shadow", &"pet"), p.outgoing_damage_mult(null, &"shadow", &"pet"), 0.0001, "(sanity)")
