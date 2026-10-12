extends "res://tests/talents_mage_base.gd"
## Mage Arcane tree (M5, talents_mage.md 1): every talent through player.talents on a real Mage
## – stats, Blink / Blizzard params, damage multipliers, Arcane Concentration's free Blizzards
## (seeded RNG), Arcane Power – and the Mirror Image modifier (BlinkEffect + MageMirrorImage):
## spawn, lure, burst, cooldown, wave start / end, downed, freed caster, refused Blink.


func _blink_effect(p: Player) -> BlinkEffect:
	return _effect(p, &"blink") as BlinkEffect


## A Mage with Mirror Image (6 points in tier 1, then the modifier).
func _image_mage(pos: Vector3 = Vector3.ZERO) -> Player:
	var p := _mage(pos)
	_add(p, "mage_arcane_arcane_focus", 3)
	_add(p, "mage_arcane_arcane_meditation", 3)
	_add(p, "mage_arcane_mirror_image")
	_tough(p)
	return p


func _blink_east(p: Player) -> bool:
	_move(p, Vector2(1, 0))
	return p.abilities.try_cast(p.abilities.slot_of(&"blink"))


func _images() -> Array[MageMirrorImage]:
	var out: Array[MageMirrorImage] = []
	for n in tree.get_nodes_in_group(MageMirrorImage.GROUP):
		if n is MageMirrorImage and not n.is_queued_for_deletion():
			out.append(n)
	return out


# --- Tier 1-4 ----------------------------------------------------------------------------------

func test_arcane_focus_raises_arcane_damage_per_rank() -> void:
	var p := _mage()
	check_eq(p.main_hand.school, &"arcane", "the Mage's wand is an Arcane weapon")
	check_eq(p.bonuses.damage_mult(null, &"arcane", &"weapon"), 1.0, "nothing yet")
	_add(p, "mage_arcane_arcane_focus", 3)
	check_near(p.bonuses.damage_mult(null, &"arcane", &"weapon"), 1.09, 0.0001, "+3% per rank on a wand hit")
	check_near(p.bonuses.damage_mult(null, &"arcane", &"ability"), 1.09, 0.0001, "Arcane spells too")
	check_eq(p.bonuses.damage_mult(null, &"fire", &"weapon"), 1.0, "a Staff (Fire) does not profit")
	var e := _enemy(Vector3(1.5, 0, 0))
	WeaponRunner.apply_hit(p, e, 10.0, false, Vector3.ZERO, 0.0, 0.5, p.main_hand)
	check_near(e.fake_damage_log[0], 10.0 * p.outgoing_damage_mult(e, &"arcane", &"weapon"), 0.0001, "the wand hit carries it")
	check_near(e.fake_damage_log[0], 10.9, 0.0001, "10 -> 10.9")
	_remove(p, "mage_arcane_arcane_focus")
	check_near(p.bonuses.damage_mult(null, &"arcane", &"weapon"), 1.06, 0.0001, "rank 2")
	_remove(p, "mage_arcane_arcane_focus", 2)
	check_eq(p.bonuses.damage_mult(null, &"arcane", &"weapon"), 1.0, "undone")


func test_arcane_meditation_speeds_up_mana_regen() -> void:
	var p := _mage()
	var mana := p.abilities.get_resource(&"mana")
	mana.set_value(0.0)
	p.abilities._physics_process(1.0)
	var plain := mana.value
	check(plain > 0.0, "Mana regenerates")
	_add(p, "mage_arcane_arcane_meditation", 3)
	check_eq(p.stats.get_raw(Stats.RESOURCE_REGEN), 30.0, "+10% Resource Regen per rank")
	mana.set_value(0.0)
	p.abilities._physics_process(1.0)
	check_near(mana.value, plain * 1.3, 0.001, "30% faster")
	_remove(p, "mage_arcane_arcane_meditation", 3)
	check_eq(p.stats.get_raw(Stats.RESOURCE_REGEN), 0.0, "undone")


func test_improved_blink_shortens_the_cooldown_and_blinks_further() -> void:
	var p := _mage()
	var base := _params(p, &"blink")
	_add(p, "mage_arcane_arcane_focus", 3)
	_add(p, "mage_arcane_improved_blink", 3)
	var params := _params(p, &"blink")
	check_near(float(params["cooldown"]), float(base["cooldown"]) * 0.85, 0.0001, "-5% cooldown per rank")
	check_near(float(params["distance"]), 9.0, 0.0001, "+1 m per rank (6 -> 9)")
	check_eq(params["invulnerable"], base["invulnerable"], "no extra invulnerability (judge B3)")
	check(_blink_east(p), "blink")
	check_near(p.global_position.distance_to(Vector3(9, 0, 0)), 0.0, 0.001, "9 m")
	var t := Db.get_talent(&"mage_arcane_improved_blink")
	check_eq(t.text_for_rank(3), "Blink recharges 15% faster and carries you 3 m further.", "text at rank 3")
	_remove(p, "mage_arcane_improved_blink", 3)
	check_eq(_params(p, &"blink")["distance"], base["distance"], "undone")


func test_arcane_concentration_needs_meditation_and_adds_free_chance() -> void:
	var p := _mage()
	_add(p, "mage_arcane_arcane_focus", 3)
	_add(p, "mage_arcane_arcane_meditation", 2)
	check_eq(p.talents.add_block_reason(&"mage_arcane_arcane_concentration"), "Requires Arcane Meditation", "prerequisite")
	_add(p, "mage_arcane_arcane_meditation")
	_add(p, "mage_arcane_arcane_concentration", 3)
	check_near(float(_params(p, &"blizzard").get("free_chance", 0.0)), 24.0, 0.0001, "8% per rank on Blizzard (Mana)")
	check(not _params(p, &"blink").has("free_chance"), "Blink spends no Mana: untouched")


## [param casts] Blizzards from full Mana; the number that cost nothing.
func _free_blizzards(p: Player, casts: int) -> int:
	var mana := p.abilities.get_resource(&"mana")
	var free := 0
	for i in casts:
		mana.set_value(mana.max_value())
		check(p.abilities.try_cast(0), "Blizzard %d" % i)
		if is_equal_approx(mana.value, mana.max_value()):
			free += 1
	return free


func test_arcane_concentration_rolls_free_blizzards_on_the_run_rng() -> void:
	var p := _mage()
	_cluster(Vector3(6, 0, 0), 4)
	_add(p, "mage_arcane_arcane_focus", 3)
	_add(p, "mage_arcane_arcane_meditation", 3)
	_add(p, "mage_arcane_arcane_concentration", 3)
	RunState.rng.seed = 777
	var state := RunState.rng.state
	var free := _free_blizzards(p, 40)
	check(free > 0 and free < 40, "some Blizzards are free (%d of 40)" % free)
	check_eq(RunState.rng.state, _state_after(state, 40), "one RunState.rng draw per cast")
	RunState.rng.seed = 777
	check_eq(_free_blizzards(p, 40), free, "the same seed frees the same casts")


func test_arcane_mind_adds_intellect_and_mana() -> void:
	var p := _mage()
	var intellect := p.stats.get_raw(Stats.INTELLECT)
	var mana := p.abilities.get_resource(&"mana")
	var max_before := mana.max_value()
	_add(p, "mage_arcane_arcane_focus", 3)
	_add(p, "mage_arcane_arcane_meditation", 3)
	_add(p, "mage_arcane_arcane_mind", 2)
	check_eq(p.stats.get_raw(Stats.INTELLECT), intellect + 6.0, "+3 Intellect per rank")
	p.abilities._physics_process(DT)
	check_near(mana.max_value(), max_before + 12.0, 0.0001, "+2 max Mana per Intellect (MageMastery.sync_mana)")
	_remove(p, "mage_arcane_arcane_mind", 2)
	check_eq(p.stats.get_raw(Stats.INTELLECT), intellect, "undone")


func test_arcane_flows_needs_improved_blink_and_adds_cooldown_reduction() -> void:
	var p := _mage()
	var blink := _ability(&"blink")
	_add(p, "mage_arcane_arcane_focus", 3)
	_add(p, "mage_arcane_arcane_meditation", 3)
	_add(p, "mage_arcane_arcane_concentration", 3)
	_add(p, "mage_arcane_improved_blink", 2)
	check_eq(p.talents.add_block_reason(&"mage_arcane_arcane_flows"), "Requires Improved Blink", "prerequisite")
	_add(p, "mage_arcane_improved_blink")
	var before := p.abilities.cooldown_of(blink)
	_add(p, "mage_arcane_arcane_flows", 3)
	check_eq(p.stats.get_raw(Stats.COOLDOWN_REDUCTION), 12.0, "+4% CDR per rank")
	check(p.abilities.cooldown_of(blink) < before - 0.1, "Blink recharges faster")


func test_arcane_celerity_adds_haste() -> void:
	var p := _mage()
	_plan(p, [["mage_arcane_arcane_focus", 3], ["mage_arcane_arcane_meditation", 3],
		["mage_arcane_arcane_concentration", 3]])
	_add(p, "mage_arcane_arcane_celerity", 3)
	check_eq(p.stats.get_raw(Stats.HASTE), 12.0, "+4% Haste per rank")
	_remove(p, "mage_arcane_arcane_celerity", 3)
	check_eq(p.stats.get_raw(Stats.HASTE), 0.0, "undone")


# --- Arcane Power ------------------------------------------------------------------------------

func test_arcane_power_raises_all_damage_and_mana_costs() -> void:
	var p := _mage()
	_cluster(Vector3(6, 0, 0), 4)
	_plan(p, ARCANE_12)
	var base_mult := p.bonuses.damage_mult(null, &"frost", &"ability")
	check_eq(base_mult, 1.0, "no Frost bonus before the capstone")
	_add(p, "mage_arcane_arcane_power")
	check_near(p.bonuses.damage_mult(null, &"frost", &"dot"), 1.25, 0.0001, "+25% to everything")
	check_near(p.bonuses.damage_mult(null, &"arcane", &"weapon"), 1.34, 0.0001, "adds to Arcane Focus (1 + 0.09 + 0.25)")
	var blizzard := _ability(&"blizzard")
	check_near(p.abilities.cost_of(blizzard), 65.0, 0.0001, "Blizzard costs 65 Mana")
	check_near(float(_params(p, &"blizzard")["free_chance"]), 24.0, 0.0001, "Arcane Concentration still applies")
	check_near(p.abilities.cost_of(_ability(&"blink")), 0.0, 0.0001, "Blink stays free")
	var mana := p.abilities.get_resource(&"mana")
	RunState.rng.seed = 5
	var paid := 0
	for i in 10:
		mana.set_value(mana.max_value())
		check(p.abilities.try_cast(0), "cast %d" % i)
		var spent := mana.max_value() - mana.value
		check(is_equal_approx(spent, 65.0) or is_equal_approx(spent, 0.0), "65 or free (%.2f)" % spent)
		if is_equal_approx(spent, 65.0):
			paid += 1
	check(paid > 0, "most casts pay 65")


# --- Mirror Image ------------------------------------------------------------------------------

func test_mirror_image_params_and_text() -> void:
	var p := _mage()
	check_eq(float(_params(p, &"blink")["image_duration"]), 0.0, "neutral without the talent")
	_plan(p, [["mage_arcane_arcane_focus", 3], ["mage_arcane_arcane_meditation", 3]])
	_add(p, "mage_arcane_mirror_image")
	check_eq(float(_params(p, &"blink")["image_duration"]), 3.0, "3 sec image")
	check_eq(Db.get_talent(&"mage_arcane_mirror_image").text_for_rank(1),
		"When you Blink, a Mirror Image stays behind for 3 sec. Enemies within 4 m chase it instead of you, and it bursts for Arcane damage within 2.5 m when it fades. Once every 6 sec at most.",
		"text")


func test_no_mirror_image_without_the_talent() -> void:
	var p := _mage()
	_enemy(Vector3(1.5, 0, 0))
	check(_blink_east(p), "blink")
	check(_blink_effect(p).images.is_empty() and _images().is_empty(), "no image")


func test_mirror_image_lures_nearby_enemies_and_bursts_when_it_fades() -> void:
	var p := _image_mage()
	var near := _enemy(Vector3(1.5, 0, 0))
	var edge := _enemy(Vector3(0, 0, 4.2))  # body (0.45) touches the 4 m circle
	var far := _enemy(Vector3(-6, 0, 6))
	var boss := FakeBoss.new()
	boss.add_to_group(&"enemies")
	world.add_child(boss)
	boss.global_position = Vector3(-1.5, 0, 0)
	var other := Node3D.new()
	world.add_child(other)
	var busy := _enemy(Vector3(0, 0, -1.5))
	busy.apply_taunt(other, 10.0)
	EnemyGrid.mark_dirty()
	var state := RunState.rng.state
	check(_blink_east(p), "blink")
	var images := _images()
	check_eq(images.size(), 1, "one image")
	var image := images[0]
	check_near(image.global_position.distance_to(Vector3.ZERO), 0.0, 0.001, "where the Mage stood")
	check_near(p.global_position.distance_to(Vector3(6, 0, 0)), 0.0, 0.001, "the Mage blinked away")
	check_near(image.time_left, 3.0, 0.0001, "3 sec")
	check(near.is_taunted() and near.taunt_target == image, "a nearby enemy chases the image")
	check(edge.is_taunted() and edge.taunt_target == image, "4 m reach (bodies)")
	check(not far.is_taunted(), "far enemies are not lured")
	check(not boss.is_taunted(), "bosses are not lured")
	check(busy.taunt_target == other, "an enemy taunted onto another live target is left alone")
	check_near(image.burst_damage, _spell(p, 3.0, 0.4, &"arcane"), 0.0001, "burst: 3 + 0.4 x Intellect + Spell Power")
	var late := _enemy(Vector3(0.5, 0, 1.0))
	_step(0.55)
	check(late.is_taunted() and late.taunt_target == image, "the lure pulses every 0.5 sec")
	_step(2.0)
	check_eq(near.fake_hits(), 0, "no damage while it stands")
	_step(0.5)
	check_eq(image.bursts, 1, "it faded with a burst")
	check(image.is_queued_for_deletion(), "and frees itself")
	check_eq(near.fake_hits(), 1, "the burst hits enemies within 2.5 m")
	check_near(near.fake_damage_log[0], image.burst_damage * p.outgoing_damage_mult(near, &"arcane", &"ability"), 0.0001,
		"Arcane spell damage with the Mage's multipliers (Arcane Focus)")
	check_eq(late.fake_hits(), 1, "every enemy inside")
	check_eq(edge.fake_hits(), 0, "4.2 m away: outside the burst")
	check_eq(far.fake_hits(), 0, "far away: nothing")
	check_eq(RunState.rng.state, state, "no RNG")


func test_mirror_image_once_every_six_seconds() -> void:
	var p := _image_mage()
	var blink := _ability(&"blink")
	check(_blink_east(p), "first blink")
	check_eq(_images().size(), 1, "an image")
	check_near(_blink_effect(p).image_cooldown_left, 6.0, 0.0001, "6 sec image cooldown")
	p.abilities.set_cooldown(blink, 0.0)
	check(_blink_east(p), "second blink right away")
	check_eq(_images().size(), 1, "no second image within 6 sec")
	p.abilities._physics_process(5.9)
	p.abilities.set_cooldown(blink, 0.0)
	check(_blink_east(p), "blink at 5.9 sec")
	check_eq(_blink_effect(p).images.size(), 1, "still none")
	p.abilities._physics_process(0.2)
	p.abilities.set_cooldown(blink, 0.0)
	check(_blink_east(p), "blink after 6 sec")
	check_eq(_blink_effect(p).images.size(), 2, "a new image")


func test_mirror_image_goes_without_a_burst_at_wave_end_and_start() -> void:
	var p := _image_mage()
	var e := _enemy(Vector3(1.0, 0, 0))
	check(_blink_east(p), "blink")
	var image := _images()[0]
	p.end_wave()
	check(image.is_queued_for_deletion() and image.bursts == 0, "wave end: gone, no burst")
	check_eq(e.fake_hits(), 0, "nobody hurt")
	check_eq(_blink_effect(p).image_cooldown_left, 0.0, "the image cooldown is cleared")
	check(_blink_effect(p).images.is_empty(), "list cleared")
	p.abilities.set_cooldown(_ability(&"blink"), 0.0)
	p.global_position = Vector3.ZERO
	check(_blink_east(p), "blink again")
	var second := _images()[0]
	p.begin_wave()
	check(second.is_queued_for_deletion() and second.bursts == 0, "wave start removes it too")


func test_mirror_image_outlives_a_downed_caster_but_not_a_freed_one() -> void:
	var p := _image_mage()
	var e := _enemy(Vector3(1.0, 0, 0))
	check(_blink_east(p), "blink")
	var image := _images()[0]
	_down(p)
	_step(3.1)
	check_eq(image.bursts, 1, "a downed Mage's image still bursts")
	check_eq(e.fake_hits(), 1, "and hurts")
	var q := _image_mage(Vector3(0, 0, 8))
	_enemy(Vector3(0, 0, 9))
	check(_blink_east(q), "another Mage blinks")
	var orphan := _images()[0]
	q.free()
	_step(DT)
	check(not is_instance_valid(orphan) or orphan.is_queued_for_deletion(), "a freed caster's image goes")
	check(not is_instance_valid(orphan) or orphan.bursts == 0, "without a burst")


func test_a_refused_blink_leaves_no_image() -> void:
	var arena := EFakes.TestArena.new()
	world.add_child(arena)
	var margin := Player.RADIUS + Player.WALL_GAP
	var p := _image_mage(Vector3(arena.get_bounds().end.x - margin, 0, 0))
	check(not _blink_east(p), "against the wall: refused")
	check(_images().is_empty(), "no image")
	check_eq(_blink_effect(p).image_cooldown_left, 0.0, "no image cooldown either")
