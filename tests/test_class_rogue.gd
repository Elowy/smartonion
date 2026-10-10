extends TestCase
## Rogue kit (M3, GDD 3.4): Energy + Combo Points, Fan of Knives, Vanish, bot decisions and the
## class item mods (Blade of the Thousand Cuts, Shadowstalker Wraps).

const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0

var world: Node3D
var rogue: Player


func before_each() -> void:
	PlayerManager.clear()
	RunState.start_run(1, 11)
	world = Fakes.make_world(tree)
	rogue = Fakes.spawn_player(world, 0, &"rogue")
	# Deterministic damage: no random crits unless a test asks for them.
	rogue.stats.set_source(&"test", {Stats.CRIT: -500.0, Stats.DODGE: -500.0})


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	rogue = null
	PlayerManager.clear()
	EnemyGrid.mark_dirty()


func _energy() -> ClassResource:
	return rogue.abilities.get_resource(&"energy")


func _combo() -> ClassResource:
	return rogue.abilities.get_resource(&"combo_points")


func _knives() -> Array[Projectile]:
	var out: Array[Projectile] = []
	for node in tree.get_nodes_in_group(&"projectiles"):
		var p := node as Projectile
		if p != null and p.attacker == rogue and not p.is_queued_for_deletion():
			out.append(p)
	return out


func _equip_unique(id: StringName) -> void:
	var item := ItemGenerator.from_unique(Db.get_unique(id), 1, false, RunState.rng, rogue.class_data)
	check(rogue.equipment.equip(item), "%s equipped" % id)


func _body_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var yaw := rogue.model.get_node_or_null("Yaw")
	if yaw != null:
		for node in yaw.find_children("*", "MeshInstance3D", true, false):
			out.append(node as MeshInstance3D)
	return out


func _vanish_effect() -> RogueVanish:
	return rogue.abilities.effect_for(rogue.abilities.slots[1]) as RogueVanish


## Enemies standing around the rogue on a ring.
func _surround(count: int, distance: float) -> Array[Fakes.FakeEnemy]:
	var out: Array[Fakes.FakeEnemy] = []
	for i in count:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, TAU * float(i) / float(count))
		out.append(Fakes.spawn_enemy(world, rogue.global_position + dir * distance))
	EnemyGrid.mark_dirty()
	return out


func _clear_enemies() -> void:
	for node in tree.get_nodes_in_group(&"enemies"):
		node.get_parent().remove_child(node)
		node.free()
	EnemyGrid.mark_dirty()


# --- Data / wiring ------------------------------------------------------------------------

func test_class_wiring() -> void:
	var c := Db.get_class_data(&"rogue")
	check_eq(c.resources.size(), 2, "two resources")
	check_eq(c.resources[0].id, &"energy", "Energy is the primary resource")
	check_eq(c.resources[1].id, &"combo_points", "Combo Points second")
	check_eq(c.abilities.size(), 2, "two core abilities")
	check_eq(c.abilities[0].id, &"fan_of_knives", "RT")
	check_eq(c.abilities[1].id, &"vanish", "LT")
	check(c.mastery != null and c.mastery_text.begins_with("Deadly Poison"), "Mastery set")
	for a in c.abilities:
		check(a.effect != null and a.effect.can_instantiate(), "%s has an effect script" % a.id)
		check(a.class_id == &"rogue" and a.display_name != "" and a.description != "", "%s texts" % a.id)
	var energy := c.resources[0]
	check_eq(energy.max_value, 100.0, "Energy max")
	check_eq(energy.regen_per_second, 15.0, "Energy regen")
	check(energy.regen_uses_haste, "Energy regen uses Haste")
	var combo := c.resources[1]
	check_eq(combo.max_value, 5.0, "5 Combo Points")
	check_eq(combo.display, ResourceData.Display.PIPS, "Combo Points are pips")
	check_eq(combo.gain_on_crit, 1.0, "+1 per crit")
	check_eq(combo.regen_per_second, 0.0, "no passive combo gain")
	check_eq(rogue.abilities.resource_order, [&"energy", &"combo_points"] as Array[StringName], "runner order")
	check(rogue.abilities.mastery is RogueMastery, "runner builds the Mastery")
	check_eq(rogue.abilities.ranks.size(), 0, "no ranks in M3")


func test_class_items_are_ability_mods() -> void:
	var wraps := Db.get_unique(&"shadowstalker_wraps")
	var blade := Db.get_unique(&"blade_of_the_thousand_cuts")
	for u in [wraps, blade]:
		check_eq(u.unique_effect, &"ability_mod", "%s is an ability mod" % u.id)
		check_eq(u.class_restriction, &"rogue", "%s keeps its class" % u.id)
		check(u.unique_text.begins_with("Equip:"), "%s text" % u.id)
	var ability_ids: Array[StringName] = []
	for a in Db.get_class_data(&"rogue").abilities:
		ability_ids.append(a.id)
	check(StringName(wraps.unique_params["ability"]) in ability_ids, "wraps target a Rogue ability")
	check(StringName(blade.unique_params["ability"]) in ability_ids, "blade targets a Rogue ability")
	check_eq(wraps.unique_params["ability"], "vanish", "wraps target")
	check_eq(wraps.unique_params["mods"]["cooldown_add"], -5.0, "-5 s cooldown")
	check_eq(blade.unique_params["ability"], "fan_of_knives", "blade target")
	check_eq(blade.unique_params["mods"]["knives_add"], 4.0, "+4 knives")
	check_eq(wraps.slot_type, Items.SlotType.WRIST, "wraps slot")
	check(blade.weapon != null and blade.weapon.weapon_type == &"dagger", "blade is a dagger")


# --- Energy / Combo Points ----------------------------------------------------------------

func test_energy_regen_and_haste() -> void:
	check_eq(_energy().value, 100.0, "full at wave start")
	_energy().set_value(0.0)
	for i in 60:
		rogue.abilities._physics_process(DT)
	check_near(_energy().value, 15.0, 0.05, "+15 per second")
	rogue.stats.set_source(&"haste", {Stats.HASTE: 100.0})
	_energy().set_value(0.0)
	for i in 60:
		rogue.abilities._physics_process(DT)
	check_near(_energy().value, 30.0, 0.1, "Haste doubles it")
	rogue.stats.remove_source(&"haste")
	rogue.stats.set_source(&"regen", {Stats.RESOURCE_REGEN: 50.0})
	_energy().set_value(0.0)
	for i in 60:
		rogue.abilities._physics_process(DT)
	check_near(_energy().value, 22.5, 0.1, "Resource Regen scales it")
	_energy().set_value(99.0)
	for i in 60:
		rogue.abilities._physics_process(DT)
	check_eq(_energy().value, 100.0, "capped at 100")


func test_combo_points_from_crits() -> void:
	check_eq(_combo().value, 0.0, "no combo points at the start")
	rogue.abilities.on_weapon_hit(null, 5.0, false)
	check_eq(_combo().value, 0.0, "a normal hit gives none")
	rogue.abilities.on_weapon_hit(null, 5.0, true)
	check_eq(_combo().value, 1.0, "a crit gives one")
	for i in 8:
		rogue.abilities.on_weapon_hit(null, 5.0, true)
	check_eq(_combo().value, 5.0, "capped at 5")
	check_eq(RogueUtil.combo_points(rogue), 5, "helper")
	rogue.begin_wave()
	check_eq(_combo().value, 0.0, "reset with the wave")
	check_eq(_energy().value, 100.0, "Energy back to full")


func test_combo_points_from_real_weapon_hits() -> void:
	var e := Fakes.spawn_enemy(world, Vector3(0, 0, -1.2))
	WeaponRunner.apply_hit(rogue, e, 5.0, false, Vector3.ZERO)
	check_eq(_combo().value, 0.0, "plain weapon hit")
	WeaponRunner.apply_hit(rogue, e, 12.0, true, Vector3.ZERO)
	check_eq(_combo().value, 1.0, "critical weapon hit")


# --- Fan of Knives ------------------------------------------------------------------------

func test_fan_of_knives_throws_ten_knives() -> void:
	check(rogue.abilities.try_cast(0), "cast")
	var knives := _knives()
	check_eq(knives.size(), 10, "ten knives")
	check_eq(_energy().value, 65.0, "35 Energy spent")
	var sum := Vector3.ZERO
	var angles: Array[float] = []
	for k in knives:
		check_eq(k.team, Projectile.TEAM_PLAYERS, "player knife")
		check_eq(k.pierce, 1, "each passes through one enemy")
		check(k.weapon == rogue.main_hand and k.is_extra, "weapon based, no extra-attack chains")
		check_near(k.direction.length(), 1.0, 0.001, "unit direction")
		check_near(k.global_position.y, Player.CHEST_HEIGHT, 0.001, "chest height")
		sum += k.direction
		angles.append(snappedf(rad_to_deg(Vector3.FORWARD.signed_angle_to(k.direction, Vector3.UP)), 1.0))
	check(sum.length() < 0.001, "knives cover every direction evenly")
	var distinct := {}
	for a in angles:
		distinct[a] = true
	check_eq(distinct.size(), 10, "ten distinct angles")


func test_fan_needs_energy() -> void:
	_energy().set_value(34.0)
	check(not rogue.abilities.try_cast(0), "34 Energy is not enough")
	check_eq(_knives().size(), 0, "nothing thrown")
	_energy().set_value(35.0)
	check(rogue.abilities.try_cast(0), "35 is")
	check_near(_energy().value, 0.0, 0.001, "all spent")


func test_fan_damage_is_weapon_based() -> void:
	rogue.abilities.try_cast(0)
	var expected := CombatMath.weapon_hit_damage(rogue.main_hand, rogue.stats) * 1.1
	for k in _knives():
		check_near(k.damage, expected, 0.001, "110% of a weapon hit")
		check(not k.is_crit, "no crit without crit chance")
	check(expected > 1.0, "sane damage")


func test_fan_spends_combo_points_for_damage() -> void:
	_combo().set_value(3.0)
	var base := CombatMath.weapon_hit_damage(rogue.main_hand, rogue.stats) * 1.1
	check(rogue.abilities.try_cast(0), "cast")
	check_eq(_combo().value, 0.0, "every Combo Point spent")
	for k in _knives():
		check_near(k.damage, base * 1.6, 0.001, "+20% per point")
	for k in _knives():
		k.queue_free()
	_combo().set_value(5.0)
	_energy().set_value(100.0)
	rogue.abilities.try_cast(0)
	var after_free := _knives().filter(func(k: Projectile) -> bool: return not k.is_queued_for_deletion())
	check_eq(after_free.size(), 10, "second fan")
	for k: Projectile in after_free:
		check_near(k.damage, base * 2.0, 0.001, "5 points double the damage")


func test_fan_knives_crit_and_hit_each_target_once() -> void:
	rogue.stats.set_source(&"test", {Stats.CRIT: 500.0})
	var enemies := _surround(10, 3.0)
	check(rogue.abilities.try_cast(0), "cast")
	var crit_mult := CombatMath.crit_multiplier(rogue.main_hand, rogue.stats)
	var base := CombatMath.weapon_hit_damage(rogue.main_hand, rogue.stats) * 1.1
	for k in _knives():
		check(k.is_crit, "knives crit at 100% crit chance")
		check_near(k.damage, base * crit_mult, 0.001, "crit damage")
	for i in 40:
		for k in _knives():
			k.advance(DT)
	for e in enemies:
		check_eq(e.fake_hits(), 1, "every enemy takes exactly one knife")
		check(e.fake_crit_log[0], "as a crit")
		check_eq(e.fake_attacker_log[0], rogue, "credited to the rogue")
	check_eq(_combo().value, 5.0, "knife crits refill the Combo Points")
	var mastery := rogue.abilities.mastery as RogueMastery
	check_eq(mastery.poisoned_count(), 10, "and poison everybody")


func test_fan_knives_pierce_one_enemy() -> void:
	rogue.facing = Vector3.FORWARD
	var first := Fakes.spawn_enemy(world, Vector3(0, 0, -2.0))
	var second := Fakes.spawn_enemy(world, Vector3(0, 0, -4.0))
	var third := Fakes.spawn_enemy(world, Vector3(0, 0, -6.0))
	EnemyGrid.mark_dirty()
	check(rogue.abilities.try_cast(0), "cast")
	for i in 40:
		for k in _knives():
			k.advance(DT)
	check_eq(first.fake_hits(), 1, "the first enemy in line is hit")
	check_eq(second.fake_hits(), 1, "the knife passes through to the second")
	check_eq(third.fake_hits(), 0, "and stops there")


func test_blade_of_the_thousand_cuts_adds_four_knives() -> void:
	_equip_unique(&"blade_of_the_thousand_cuts")
	check_eq(rogue.ability_mods(&"fan_of_knives"), {"knives_add": 4.0}, "mod collected")
	rogue.stats.set_source(&"test", {Stats.CRIT: -500.0})
	check(rogue.abilities.try_cast(0), "cast")
	check_eq(_knives().size(), 14, "10 + 4 knives")
	var distinct := {}
	for k in _knives():
		distinct[snappedf(rad_to_deg(Vector3.FORWARD.signed_angle_to(k.direction, Vector3.UP)), 1.0)] = true
	check_eq(distinct.size(), 14, "still evenly spread")


# --- Vanish -------------------------------------------------------------------------------

func test_vanish_guarantees_the_next_crit() -> void:
	var e := Fakes.spawn_enemy(world, Vector3(0, 0, -1.2))
	EnemyGrid.mark_dirty()
	var runner := rogue.runner_for(rogue.main_hand)
	runner.attack(e)
	check(not e.fake_crit_log[-1], "no crit without Vanish (crit chance 0)")
	check(rogue.abilities.try_cast(1), "Vanish")
	check_eq(rogue.forced_crits, 1, "one guaranteed crit")
	runner.attack(e)
	check(e.fake_crit_log[-1], "the next hit crits")
	check_eq(rogue.forced_crits, 0, "used up")
	runner.attack(e)
	check(not e.fake_crit_log[-1], "and only that one")


func test_vanish_hides_the_rogue_for_two_seconds() -> void:
	var effect := _vanish_effect()
	var meshes := _body_meshes()
	var originals: Array[Material] = []
	var shadows := {}
	for mi in meshes:
		originals.append(mi.material_override)
		shadows[mi] = mi.cast_shadow
	check(rogue.abilities.try_cast(1), "cast")
	check(effect.is_active(), "active")
	check_near(effect.time_left(), 2.0, 0.001, "2 seconds")
	check_near(rogue.stealth_left, 2.0, 0.001, "stealthed while hidden")
	check(rogue.is_stealthed(), "enemies lose the rogue")
	check_eq(rogue.invulnerable_left, 0.0, "no extra invulnerability (stealth only)")
	check(meshes.size() > 5, "the model has meshes")
	var ghost: Material = meshes[0].material_override
	check(ghost is ShaderMaterial and (ghost as ShaderMaterial).get_shader_parameter("color").a < 0.5,
			"a translucent silhouette material")
	for mi in meshes:
		check(mi.material_override == ghost, "%s is part of the silhouette" % mi.name)
		check_eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "no shadow while hidden")
	for i in 100:
		rogue.abilities._physics_process(DT)
		rogue._physics_process(DT)
	check(effect.is_active(), "still hidden after 1.7 s")
	check(rogue.is_stealthed(), "and still stealthed")
	for i in 21:
		rogue.abilities._physics_process(DT)
		rogue._physics_process(DT)
	check(not effect.is_active(), "visible again")
	for mi in meshes:
		check(mi.material_override != ghost, "%s solid again" % mi.name)
		check_eq(mi.cast_shadow, shadows[mi], "%s casts its shadow again" % mi.name)
	for i in meshes.size():
		check(meshes[i].material_override == originals[i], "the model's own material is back")
	check(not rogue.is_stealthed(), "the stealth is over too")


func test_vanish_heals_a_share_of_max_hp() -> void:
	var ctx := rogue.abilities.build_context(rogue.abilities.slots[1])
	check_near(ctx.num("heal_max_hp_pct"), 30.0, 0.001, "30% of max HP in the data")
	rogue.hp = rogue.max_hp() * 0.2
	check(rogue.abilities.try_cast(1), "cast")
	check_near(rogue.hp, rogue.max_hp() * 0.5, 0.001, "20% + 30% of max HP")
	rogue.abilities.begin_wave()
	rogue.hp = rogue.max_hp() * 0.9
	check(rogue.abilities.try_cast(1), "cast near full health")
	check_near(rogue.hp, rogue.max_hp(), 0.001, "capped at max HP")


func test_vanish_cooldown_and_cooldown_mod() -> void:
	check(rogue.abilities.try_cast(1), "cast")
	check_near(rogue.abilities.remaining(1), 15.0, 0.001, "15 s cooldown")
	check(not rogue.abilities.try_cast(1), "on cooldown")
	rogue.abilities._physics_process(DT)
	check_near(rogue.abilities.remaining(1), 15.0 - DT, 0.001, "no mod")
	rogue.abilities.begin_wave()
	_equip_unique(&"shadowstalker_wraps")
	check_eq(rogue.ability_mods(&"vanish"), {"cooldown_add": -5.0}, "mod collected")
	var ctx := rogue.abilities.build_context(rogue.abilities.slots[1])
	check_near(ctx.num("cooldown"), 10.0, 0.001, "params carry the shorter cooldown")
	check(rogue.abilities.try_cast(1), "cast with the Wraps")
	rogue.abilities._physics_process(DT)
	check_near(rogue.abilities.remaining(1), 10.0 - DT, 0.001, "5 s shorter")
	for i in 599:
		rogue.abilities._physics_process(DT)
	check(rogue.abilities.remaining(1) <= 0.0, "ready after 10 s")


func test_vanish_cooldown_mod_scales_with_cooldown_reduction() -> void:
	_equip_unique(&"shadowstalker_wraps")
	rogue.stats.set_source(&"cdr", {Stats.COOLDOWN_REDUCTION: 20.0})
	rogue.abilities.try_cast(1)
	rogue.abilities._physics_process(DT)
	check_near(rogue.abilities.remaining(1), 10.0 * 0.8 - DT, 0.01, "(15 - 5) x (1 - 20%)")


func test_vanish_stealth_and_optional_invulnerability() -> void:
	RogueVanish.apply_stealth(rogue, 1.0, false)
	check_near(rogue.stealth_left, 1.0, 0.001, "stealth set")
	check_eq(rogue.invulnerable_left, 0.0, "no invulnerability unless asked")
	RogueVanish.apply_stealth(rogue, 0.5, true)
	check_near(rogue.stealth_left, 1.0, 0.001, "a shorter stealth does not cut the running one")
	check_near(rogue.invulnerable_left, 0.5, 0.001, "optional invulnerability window")
	rogue.take_damage(9999.0)
	rogue.invulnerable_left = 0.0
	rogue.take_damage(9999.0)
	check(rogue.downed, "downed")
	check(not rogue.is_stealthed(), "going down ends the stealth")


func test_vanish_stealth_ends_at_wave_start() -> void:
	check(rogue.abilities.try_cast(1), "cast")
	rogue.begin_wave()
	check(not rogue.is_stealthed(), "no stealth carried into the next wave")


func _bulb() -> MeshInstance3D:
	return rogue.model.find_child("Bulb", true, false) as MeshInstance3D


## The bulb's HP-peel amount at the rogue's HP (Mats.onion_skin quantises it in 1/20 steps).
func _peel() -> float:
	return roundf(OnionModel.damage_amount(rogue.hp / rogue.max_hp()) * 20.0) / 20.0


func _ghost_count(ghost: Material) -> int:
	var n := 0
	for mi in _body_meshes():
		if Mats.base_material(mi) == ghost:
			n += 1
	return n


func test_vanish_silhouette_survives_hp_and_stat_changes() -> void:
	var effect := _vanish_effect()
	var meshes := _body_meshes()
	var shadows := {}
	for mi in meshes:
		shadows[mi] = mi.cast_shadow
	var bulb := _bulb()
	check(bulb != null and bulb in meshes, "the bulb is a body mesh")
	check_eq(shadows[bulb], GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "the bulb casts a shadow")
	rogue.hp = rogue.max_hp() * 0.3
	rogue._hp_updated()
	check(rogue.abilities.try_cast(1), "cast")
	var ghost: Material = bulb.material_override
	check_eq(_ghost_count(ghost), meshes.size(), "every mesh faded")
	rogue.heal(1.0)  # -> OnionModel.set_hp_ratio puts the HP-peel skin on the bulb
	check(bulb.material_override == ghost, "a heal keeps the bulb in the silhouette")
	check_eq(_ghost_count(ghost), meshes.size(), "and every other mesh")
	rogue.stats.set_source(&"aura", {Stats.ARMOR: 3.0})  # stats.changed -> _hp_updated
	check(bulb.material_override == ghost, "so does a stat change")
	# A look change without hp_changed: the next tick fades it again.
	rogue.model.set_hp_ratio(0.6)
	check(bulb.material_override != ghost, "(the model replaced it)")
	rogue.abilities._physics_process(DT)
	check(bulb.material_override == ghost, "re-faded on the next tick")
	check_eq(bulb.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "still no shadow")
	rogue.model.set_hp_ratio(rogue.hp / rogue.max_hp())
	for i in 130:
		rogue.abilities._physics_process(DT)
	check(not effect.is_active(), "over")
	check_eq(_ghost_count(ghost), 0, "solid again")
	for mi in meshes:
		check_eq(mi.cast_shadow, shadows[mi], "%s casts its shadow again" % mi.name)
	check_near(rogue.model.bulb_damage(), _peel(), 0.0001, "the bulb shows the current HP peel")
	# The next Vanish starts from the true materials (the shadow is not lost for the run).
	rogue.abilities.begin_wave()
	rogue.hp = rogue.max_hp() * 0.3
	check(rogue.abilities.try_cast(1), "second cast")
	rogue.heal(1.0)
	effect.end()
	for mi in meshes:
		check_eq(mi.cast_shadow, shadows[mi], "%s shadow after the second Vanish" % mi.name)


func test_vanish_ends_with_the_wave() -> void:
	var effect := _vanish_effect()
	var meshes := _body_meshes()
	var originals: Array[Material] = []
	var shadows: Array[int] = []
	for mi in meshes:
		originals.append(mi.material_override)
		shadows.append(mi.cast_shadow)
	check(rogue.abilities.try_cast(1), "cast")
	rogue.end_wave()
	check(not effect.is_active(), "the market shows no Vanish")
	for i in meshes.size():
		check(meshes[i].material_override == originals[i], "%s solid at the wave end" % meshes[i].name)
	rogue.begin_wave()
	check(rogue.abilities.try_cast(1), "cast again")
	check(effect.is_active(), "active")
	rogue.begin_wave()
	check(not effect.is_active(), "a new wave starts visible")
	for i in meshes.size():
		check(meshes[i].material_override == originals[i], "%s solid at the wave start" % meshes[i].name)
		check_eq(meshes[i].cast_shadow, shadows[i], "%s casts its shadow again" % meshes[i].name)


func test_vanish_ends_when_the_rogue_goes_down() -> void:
	var effect := _vanish_effect()
	var meshes := _body_meshes()
	var originals := {}
	var shadows := {}
	for mi in meshes:
		originals[mi] = mi.material_override
		shadows[mi] = mi.cast_shadow
	var bulb := _bulb()
	check(rogue.abilities.try_cast(1), "cast")
	var ghost: Material = bulb.material_override
	rogue.take_damage(9999.0)
	check(rogue.downed, "downed")
	check(not effect.is_active(), "going down ends Vanish")
	check_eq(_ghost_count(ghost), 0, "the downed look replaced the silhouette")
	rogue.revive()
	check_eq(_ghost_count(ghost), 0, "no silhouette after the revive")
	for mi in meshes:
		if mi != bulb:
			check(mi.material_override == originals[mi], "%s has its own material back" % mi.name)
		check_eq(mi.cast_shadow, shadows[mi], "%s casts its shadow again" % mi.name)
	check_near(rogue.model.bulb_damage(), _peel(), 0.0001, "the bulb shows the revive HP")
	for i in 150:
		rogue.abilities._physics_process(DT)
	check_eq(_ghost_count(ghost), 0, "nothing fades later either")


# --- Bots ---------------------------------------------------------------------------------

func _wants(slot: int) -> bool:
	var a := rogue.abilities.slots[slot]
	return rogue.abilities.effect_for(a).wants_auto_cast(rogue.abilities.build_context(a))


func test_bot_fan_of_knives_decision() -> void:
	check(not _wants(0), "nobody around")
	_surround(2, 3.0)
	check(not _wants(0), "two enemies are not enough")
	_clear_enemies()
	_surround(3, 4.0)
	check(_wants(0), "three enemies within 5 m")
	_clear_enemies()
	_surround(3, 6.0)
	check(not _wants(0), "three enemies out of reach")
	_clear_enemies()
	_surround(5, 4.9)
	check(_wants(0), "a crowd at the edge of the range")


func test_bot_fan_of_knives_on_full_combo() -> void:
	_combo().set_value(5.0)
	check(not _wants(0), "full combo but nothing to hit")
	var lone := Fakes.spawn_enemy(world, Vector3(0, 0, -6.0))
	EnemyGrid.mark_dirty()
	check(_wants(0), "full combo with an enemy in knife range")
	_combo().set_value(4.0)
	check(not _wants(0), "4 points and a single enemy: wait")
	lone.position = Vector3(0, 0, -12.0)
	EnemyGrid.mark_dirty()
	_combo().set_value(5.0)
	check(not _wants(0), "enemy beyond the knives' range")


func test_bot_vanish_decision() -> void:
	var e := Fakes.spawn_enemy(world, Vector3(0, 0, -2.0))
	EnemyGrid.mark_dirty()
	check(not _wants(1), "full health")
	rogue.hp = rogue.max_hp() * 0.39
	check(_wants(1), "below 40% HP with an enemy close")
	rogue.hp = rogue.max_hp() * 0.5
	check(not _wants(1), "50% HP is fine")
	rogue.hp = rogue.max_hp() * 0.3
	e.position = Vector3(0, 0, -9.0)
	EnemyGrid.mark_dirty()
	check(not _wants(1), "no enemy close")


func test_bots_cast_through_the_runner() -> void:
	rogue.abilities.auto_cast = true
	_surround(4, 3.0)
	rogue.abilities._auto_timer = 0.0
	rogue.abilities._physics_process(DT)
	check_eq(_knives().size(), 10, "the auto-cast threw the fan")
	check_near(_energy().value, 65.0, 0.1, "and paid for it")
