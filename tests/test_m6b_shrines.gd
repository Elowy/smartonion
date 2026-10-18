extends TestCase
## M6b SHRINES: the six ShrineData of the pool, the vote model (ShrineVote), the 5% roll on its own RNG, the card
## texts generated from the numbers, what an accepted shrine does (the multipliers of pickups and enemies, the heroes'
## bonuses, the instant Fortune / Gambler effects through the spend and gain logs), the ShrineScreen's vote (humans,
## bots, unplugged pads, the clock, a player leaving), the Intermission's SHRINE phase, the Main break path over
## several waves (effects expire) and the HUD icons.

const UiFakes := preload("res://tests/ui_fakes.gd")
const MarketFakes := preload("res://tests/test_ui_market_fakes.gd")
const DT := 1.0 / 60.0
const SEED := 4242

var main: Main
var world: Node3D
var nodes: Array[Node] = []
var screen: ShrineScreen
var intermission: Intermission
var _resolved: Array[Array] = []


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(1, SEED)
	tree.paused = false
	_resolved.clear()


func after_each() -> void:
	if main != null and is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
	main = null
	for n in nodes:
		UiFakes.free_node(n)
	nodes.clear()
	UiFakes.free_node(world)
	world = null
	screen = null
	intermission = null
	tree.paused = false
	UiFakes.reset_players()
	Enemy.invalidate_player_cache()
	RunState.start_run(1, SEED)


# --- Helpers -----------------------------------------------------------------------

func _world() -> Node3D:
	if world == null:
		world = MarketFakes.make_world(tree)
	return world


func _shrine(id: StringName) -> ShrineData:
	return Db.get_shrine(id)


func _human(key: String = "pad:a", class_id: StringName = &"warrior") -> UiFakes.HumanInput:
	return MarketFakes.human_with_hero(_world(), key, class_id)


func _bot(key: String = "bot:a", class_id: StringName = &"mage") -> PlayerSlot:
	return MarketFakes.bot_with_hero(_world(), key, class_id)


func _hero_of(slot_index: int) -> Player:
	return PlayerManager.get_slot(slot_index).player as Player


func _screen() -> ShrineScreen:
	screen = ShrineScreen.create()
	tree.root.add_child(screen)
	nodes.append(screen)
	return screen


## One frame of the screen with the inputs polled first (what Intermission._process does for it).
func _step(delta: float = DT) -> void:
	for slot in PlayerManager.get_slots():
		slot.input.poll(delta)
	screen.update(delta)


func _tap(input: UiFakes.HumanInput, button: PlayerInput.Pad) -> void:
	input.press(button)
	_step()
	input.release(button)
	_step(0.0)


## Plays frames until the lockout and the first-frame skip are over.
func _past_lockout() -> void:
	for i in 40:
		_step(0.02)


func _make_intermission() -> void:
	_world()
	RunState.shop = MarketFakes.FakeShop.new()
	intermission = Intermission.create()
	tree.root.add_child(intermission)
	nodes.append(intermission)
	intermission.shrine_resolved.connect(func(id: StringName, accepted: bool, reason: StringName) -> void:
		_resolved.append([id, accepted, reason]))


func _run_intermission(seconds: float, step: float = 0.1) -> void:
	var t := 0.0
	while t < seconds and intermission.is_open():
		for slot in PlayerManager.get_slots():
			slot.input.poll(step)
		intermission._process(step)
		t += step


func _make_main(opts: LaunchOptions = null) -> Main:
	main = Main.create(opts if opts != null else LaunchOptions.new())
	tree.root.add_child(main)
	return main


func _clear_wave_and_wait() -> void:
	main.wave_director.time_left = 0.0
	main.wave_director._physics_process(DT)
	main._physics_process(Main.WAVE_END_DELAY + 0.01)


func _live(on: bool = true) -> void:
	RunState.shrine_effects_live = on


# --- The pool ----------------------------------------------------------------------

func test_the_six_shrines_are_in_the_pool_in_order() -> void:
	check_eq(Db.shrine_ids, [&"greed", &"haste", &"learning", &"blood", &"fortune", &"gambler"] as Array[StringName], "pool order")
	check_eq(Db.SHRINE_DIR, "res://data/shrines/", "data dir")
	for id in Db.shrine_ids:
		var d := Db.get_shrine(id)
		check(d != null and d.id == id, "shrine %s loads" % id)
		check(d.display_name != "" and d.description != "" and d.icon_id != &"", "%s has a name, a flavour line and an icon" % id)
		check(not Shrines.boon_lines(d).is_empty() and not Shrines.bane_lines(d).is_empty(), "%s has a boon and a bane" % id)
	check_eq(Shrines.pool().size(), 6, "six in the pool")
	check(Db.get_shrine(&"nope") == null, "unknown id")


func test_the_plan_numbers() -> void:
	var greed := _shrine(&"greed")
	check_eq(greed.waves, 3, "greed waves")
	check_eq(greed.gold_pct, 30.0, "greed +30% gold")
	check_eq(greed.enemy_damage_pct, 20.0, "greed enemies +20% damage")
	var haste := _shrine(&"haste")
	check_eq(haste.waves, 3, "haste waves")
	check_eq(haste.enemy_speed_pct, 15.0, "haste enemies +15% speed")
	check_eq(haste.hero_effects, [{"kind": "stats", "stats": {"haste": 15.0}}] as Array[Dictionary], "haste +15% haste")
	var learning := _shrine(&"learning")
	check_eq(learning.waves, 3, "learning waves")
	check_eq(learning.xp_pct, 50.0, "learning +50% XP")
	check_eq(learning.enemy_hp_pct, 25.0, "learning enemies +25% HP")
	var blood := _shrine(&"blood")
	check_eq(blood.waves, 3, "blood waves")
	check_eq(blood.hero_effects, [{"kind": "damage", "pct": 20.0}, {"kind": "stats", "stats_pct": {"max_hp": -20.0}}] as Array[Dictionary],
			"blood +20% damage, -20% max HP")
	var fortune := _shrine(&"fortune")
	check(fortune.is_instant() and fortune.give_epic and fortune.purse_loss_pct == 25.0, "fortune: a free Epic for every hero / lose 25% of the purse")
	var gambler := _shrine(&"gambler")
	check(gambler.is_instant() and gambler.gamble_chance == 0.5 and gambler.gamble_win_pct == 50.0 and gambler.gamble_lose_pct == 50.0,
			"gambler: 50% purse x1.5, else x0.5")
	for id in [&"greed", &"haste", &"learning", &"blood"]:
		check(_shrine(id).is_timed(), "%s is timed" % id)


func test_bots_vote_by_the_data() -> void:
	for id in [&"greed", &"haste", &"learning", &"blood"]:
		check(Shrines.bot_accepts(_shrine(id)), "bots accept %s" % id)
	for id in [&"fortune", &"gambler"]:
		check(not Shrines.bot_accepts(_shrine(id)), "bots decline %s" % id)
	check(not Shrines.bot_accepts(null), "nothing to accept")


func test_card_texts_come_from_the_numbers() -> void:
	check_eq(Shrines.boon_lines(_shrine(&"greed")), ["+30% gold from pickups"] as Array[String], "greed boon")
	check_eq(Shrines.bane_lines(_shrine(&"greed")), ["Enemies deal +20% damage"] as Array[String], "greed bane")
	check_eq(Shrines.boon_lines(_shrine(&"haste")), ["+15% haste"] as Array[String], "haste boon")
	check_eq(Shrines.bane_lines(_shrine(&"haste")), ["Enemies move +15% faster"] as Array[String], "haste bane")
	check_eq(Shrines.boon_lines(_shrine(&"learning")), ["+50% XP from pickups"] as Array[String], "learning boon")
	check_eq(Shrines.bane_lines(_shrine(&"learning")), ["Enemies have +25% HP"] as Array[String], "learning bane")
	check_eq(Shrines.boon_lines(_shrine(&"blood")), ["+20% damage"] as Array[String], "blood boon")
	check_eq(Shrines.bane_lines(_shrine(&"blood")), ["-20% max HP"] as Array[String], "blood bane")
	check_eq(Shrines.boon_lines(_shrine(&"fortune")), ["Every hero gets a free Epic item"] as Array[String], "fortune boon")
	check_eq(Shrines.bane_lines(_shrine(&"fortune")), ["The party loses 25% of the purse"] as Array[String], "fortune bane")
	check_eq(Shrines.boon_lines(_shrine(&"gambler")), ["50% chance: the purse x1.5"] as Array[String], "gambler boon")
	check_eq(Shrines.bane_lines(_shrine(&"gambler")), ["50% chance: the purse x0.5"] as Array[String], "gambler bane")
	var copy := _shrine(&"greed").duplicate() as ShrineData
	copy.gold_pct = 45.0
	copy.enemy_damage_pct = 12.5
	check_eq(Shrines.boon_lines(copy), ["+45% gold from pickups"] as Array[String], "the text follows the number")
	check_eq(Shrines.bane_lines(copy), ["Enemies deal +12.5% damage"] as Array[String], "also with a fraction")
	check_eq(Shrines.duration_text(_shrine(&"greed")), "Lasts the next 3 waves", "timed duration")
	check_eq(Shrines.duration_text(_shrine(&"fortune")), "Takes effect at once", "instant")
	check_eq(Shrines.effect_text(&"greed", 1), "Shrine of Greed (1 wave left)", "effect text")


# --- The vote model ----------------------------------------------------------------

func test_vote_needs_everyone() -> void:
	var v := ShrineVote.create([0, 1, 2])
	check_eq(v.outcome(), ShrineVote.Outcome.PENDING, "open")
	v.cast(0, true)
	v.cast(1, true)
	check(not v.is_decided(), "two of three")
	check_eq(v.undecided(), [2] as Array[int], "P3 is missing")
	v.cast(2, true)
	check_eq(v.outcome(), ShrineVote.Outcome.ACCEPTED, "all accepted")
	check_eq(v.reason, &"accepted", "reason")


func test_one_decline_declines_at_once() -> void:
	var v := ShrineVote.create([0, 1, 2])
	v.cast(0, true)
	v.cast(1, false)
	check_eq(v.outcome(), ShrineVote.Outcome.DECLINED, "declined with P3 still undecided")
	check_eq(v.reason, &"declined", "reason")
	check(not v.cast(2, true), "the vote is over")
	check_eq(v.outcome(), ShrineVote.Outcome.DECLINED, "it stays declined")


func test_an_accept_may_turn_into_a_decline_but_not_back() -> void:
	var v := ShrineVote.create([0, 1])
	v.cast(0, true)
	check(v.cast(0, false), "changed my mind")
	check_eq(v.outcome(), ShrineVote.Outcome.DECLINED, "declined")
	check_eq(v.choice_of(0), ShrineVote.Choice.DECLINE, "recorded")
	check(not v.cast(0, true), "a decline is final")


func test_the_clock_declines() -> void:
	var v := ShrineVote.create([0, 1])
	v.cast(0, true)
	v.tick(14.9)
	check(not v.is_decided(), "14.9 s")
	v.tick(0.2)
	check_eq(v.outcome(), ShrineVote.Outcome.DECLINED, "15 s: declined")
	check_eq(v.reason, &"timeout", "timeout")
	check_eq(ShrineVote.VOTE_TIME, 15.0, "the plan's 15 s")


func test_no_clock_when_the_time_is_zero() -> void:
	var v := ShrineVote.create([0], 0.0)
	v.tick(1000.0)
	check(not v.is_decided(), "waits for ever")
	v.cast(0, true)
	check(v.is_accepted(), "then accepts")


func test_a_decided_vote_never_changes() -> void:
	var v := ShrineVote.create([0, 1])
	v.cast(0, true)
	v.cast(1, true)
	v.tick(100.0)
	check(v.is_accepted(), "the clock does not undo an accept")
	v.remove_voter(1)
	check(v.is_accepted(), "nor does a leaver")


func test_a_leaving_voter_may_complete_the_vote() -> void:
	var v := ShrineVote.create([0, 1, 2])
	v.cast(0, true)
	v.cast(1, true)
	v.remove_voter(2)
	check(v.is_accepted(), "the others were unanimous")
	var w := ShrineVote.create([0, 1])
	w.remove_voter(0)
	w.remove_voter(1)
	check_eq(w.outcome(), ShrineVote.Outcome.DECLINED, "nobody left")
	check_eq(w.reason, &"nobody", "reason")
	check(not ShrineVote.create([] as Array[int]).cast(0, true), "no voters, no vote")


func test_cast_by_a_stranger_does_nothing() -> void:
	var v := ShrineVote.create([0, 1])
	check(not v.cast(3, true), "not a voter")
	check_eq(v.undecided(), [0, 1] as Array[int], "nothing changed")


# --- The roll ----------------------------------------------------------------------

func test_the_chance_is_five_percent_unless_overridden() -> void:
	check_eq(Shrines.CHANCE, 0.05, "5%")
	check_eq(Shrines.chance(), 0.05, "default")
	RunState.shrine_chance_override = 0.3
	check_eq(Shrines.chance(), 0.3, "--shrine-chance")
	RunState.shrine_chance_override = 7.0
	check_eq(Shrines.chance(), 1.0, "clamped")


func test_about_five_percent_of_the_breaks_get_a_shrine() -> void:
	var hits := 0
	for i in 4000:
		if Shrines.roll() != &"":
			hits += 1
	check(hits >= 120 and hits <= 290, "about 5%% of 4000 breaks (got %d)" % hits)


func test_the_roll_never_touches_the_gameplay_rng() -> void:
	var before := RunState.rng.state
	RunState.shrine_chance_override = 1.0
	for i in 40:
		Shrines.roll()
	check_eq(RunState.rng.state, before, "RunState.rng is where it was")


func test_the_roll_draws_the_chance_then_the_pick() -> void:
	RunState.shrine_chance_override = 1.0
	var twin := RunState.sub_rng(RunState.SALT_SHRINES)
	var picked := Shrines.roll()
	var all := Shrines.pool()
	check_eq(picked, all[twin.randi_range(0, all.size() - 1)].id, "chance 1: no chance draw, one pick draw")
	RunState.shrine_chance_override = 0.5
	var twin2 := RunState.sub_rng(RunState.SALT_SHRINES)
	twin2.state = RunState.shrine_rng.state
	var expected: StringName = &""
	if twin2.randf() < 0.5:
		expected = all[twin2.randi_range(0, all.size() - 1)].id
	check_eq(Shrines.roll(), expected, "chance < 1: the chance draw first, then the pick")


func test_chance_zero_never_rolls_and_never_draws() -> void:
	RunState.shrine_chance_override = 0.0
	var before := RunState.shrine_rng.state
	for i in 20:
		check_eq(Shrines.roll(), &"", "never")
	check_eq(RunState.shrine_rng.state, before, "no draw either")


func test_the_roll_is_reproducible_per_seed() -> void:
	RunState.shrine_chance_override = 0.5
	RunState.start_run(1, 99)
	RunState.shrine_chance_override = 0.5
	var a: Array[StringName] = []
	for i in 30:
		a.append(Shrines.roll())
	RunState.start_run(1, 99)
	RunState.shrine_chance_override = 0.5
	var b: Array[StringName] = []
	for i in 30:
		b.append(Shrines.roll())
	check_eq(a, b, "the same seed rolls the same shrines")
	check(a.has(&"") and a.size() > a.count(&""), "a mix of breaks with and without")


func test_a_running_timed_shrine_is_not_offered_again() -> void:
	RunState.shrine_chance_override = 1.0
	for id in [&"greed", &"haste", &"learning", &"blood"]:
		RunState.add_shrine_effect(id, 2)
	for i in 60:
		var id := Shrines.roll()
		check(id == &"fortune" or id == &"gambler", "only the instant ones are left (%s)" % id)
	RunState.shrine_effects.clear()
	var seen := {}
	for i in 300:
		seen[Shrines.roll()] = true
	check_eq(seen.size(), 6, "all six come up when nothing runs")


# --- Running effects (RunState) -------------------------------------------------------

func test_effects_count_down_and_expire() -> void:
	var changes: Array[int] = [0]
	RunState.shrines_changed.connect(func() -> void: changes[0] += 1)
	RunState.add_shrine_effect(&"greed", 3)
	RunState.add_shrine_effect(&"haste", 1)
	check_eq(RunState.shrine_waves_left(&"greed"), 3, "greed 3")
	check(RunState.has_shrine_effect(&"haste"), "haste runs")
	check(changes[0] >= 2, "the HUD is told")
	var gone := RunState.tick_shrine_effects()
	check_eq(gone, [&"haste"] as Array[StringName], "haste ran its last wave")
	check_eq(RunState.shrine_waves_left(&"greed"), 2, "greed 2")
	check(not RunState.has_shrine_effect(&"haste"), "haste is gone")
	RunState.tick_shrine_effects()
	check_eq(RunState.tick_shrine_effects(), [&"greed"] as Array[StringName], "greed expires after 3 ticks")
	check(RunState.shrine_effects.is_empty(), "nothing runs")
	check(RunState.tick_shrine_effects().is_empty(), "a tick with nothing running")


func test_accepting_a_running_shrine_again_restarts_it() -> void:
	RunState.add_shrine_effect(&"greed", 3)
	RunState.tick_shrine_effects()
	RunState.add_shrine_effect(&"greed", 3)
	check_eq(RunState.shrine_effects.size(), 1, "one entry")
	check_eq(RunState.shrine_waves_left(&"greed"), 3, "restarted")
	RunState.add_shrine_effect(&"", 3)
	RunState.add_shrine_effect(&"haste", 0)
	check_eq(RunState.shrine_effects.size(), 1, "no empty id, no zero waves")


func test_start_run_clears_the_shrine_state() -> void:
	RunState.add_shrine_effect(&"greed", 3)
	RunState.shrine_effects_live = true
	RunState.shrine_xp_remainder = 0.5
	RunState.add_gold_logged(10, -1, "x")
	RunState.start_run(1, 5)
	check(RunState.shrine_effects.is_empty() and not RunState.shrine_effects_live, "effects and the live flag reset")
	check_eq(RunState.shrine_xp_remainder, 0.0, "xp remainder reset")
	check(RunState.gold_gain_log.is_empty(), "gain log reset")


func test_the_multipliers_are_one_outside_a_wave() -> void:
	RunState.add_shrine_effect(&"greed", 3)
	RunState.add_shrine_effect(&"learning", 3)
	RunState.add_shrine_effect(&"haste", 3)
	check_eq(Shrines.gold_mult(), 1.0, "not live: gold")
	check_eq(Shrines.enemy_damage_mult(), 1.0, "not live: damage")
	check_eq(Shrines.enemy_hp_mult(), 1.0, "not live: hp")
	check_eq(Shrines.enemy_speed_mult(), 1.0, "not live: speed")
	check_eq(Shrines.xp_mult(), 1.0, "not live: xp")
	_live()
	check_eq(Shrines.gold_mult(), 1.3, "live: gold")
	check_eq(Shrines.enemy_damage_mult(), 1.2, "live: damage")
	check_eq(Shrines.enemy_hp_mult(), 1.25, "live: hp")
	check_eq(Shrines.enemy_speed_mult(), 1.15, "live: speed")
	check_eq(Shrines.xp_mult(), 1.5, "live: xp")


func test_several_shrines_multiply() -> void:
	RunState.add_shrine_effect(&"greed", 3)
	_live()
	var copy := _shrine(&"greed").duplicate() as ShrineData
	copy.id = &"greed_twin"
	Db.shrines[copy.id] = copy
	RunState.add_shrine_effect(copy.id, 3)
	check_eq(Shrines.gold_mult(), 1.69, "1.3 x 1.3")
	Db.shrines.erase(copy.id)


# --- Pickups ---------------------------------------------------------------------------

func test_gold_find_with_the_shrine_folded_in() -> void:
	check_eq(Shrines.gold_find_pct(10.0), 10.0, "no shrine: unchanged")
	RunState.add_shrine_effect(&"greed", 3)
	check_eq(Shrines.gold_find_pct(10.0), 10.0, "not live: unchanged")
	_live()
	check_near(Shrines.gold_find_pct(0.0), 30.0, 0.0001, "+30%")
	check_near(Shrines.gold_find_pct(10.0), 43.0, 0.0001, "1.1 x 1.3 = +43%")


func test_a_collected_pickup_pays_the_greed_bonus() -> void:
	_human()
	var hero := _hero_of(0)
	RunState.gold = 0
	var p := Pickup.create(10, 0)
	_world().add_child(p)
	p.collect(hero)
	check_eq(RunState.gold, 10, "plain: 10 gold")
	RunState.add_shrine_effect(&"greed", 3)
	_live()
	var q := Pickup.create(10, 0)
	_world().add_child(q)
	q.collect(hero)
	check_eq(RunState.gold, 23, "greed: 13 more")


func test_banked_pickups_pay_the_greed_bonus_with_the_fraction_kept() -> void:
	RunState.gold = 0
	var p := Pickup.create(10, 0)
	_world().add_child(p)
	p.collect_to_bank()
	check_eq(RunState.gold, 10, "plain bank")
	RunState.add_shrine_effect(&"greed", 3)
	_live()
	RunState.gold = 0
	for i in 10:
		var q := Pickup.create(1, 0)
		_world().add_child(q)
		q.collect_to_bank()
	check_eq(RunState.gold, 13, "ten 1-gold coins pay 13, not 10 or 20")


func test_xp_scaling_keeps_the_fraction() -> void:
	check_eq(RunState.scale_xp(7), 7, "no shrine: unchanged")
	RunState.add_shrine_effect(&"learning", 3)
	check_eq(RunState.scale_xp(7), 7, "not live: unchanged")
	_live()
	check_eq(RunState.scale_xp(1), 1, "1.5 -> 1, half kept")
	check_eq(RunState.scale_xp(1), 2, "1.5 + 0.5 -> 2")
	check_eq(RunState.scale_xp(4), 6, "6")
	var total := 0
	for i in 20:
		total += RunState.scale_xp(3)
	check_eq(total, 90, "twenty 3-XP pickups pay 90 (x1.5)")
	check_eq(RunState.scale_xp(0), 0, "nothing stays nothing")


func test_a_collected_pickup_pays_the_learning_bonus() -> void:
	_human()
	var hero := _hero_of(0)
	RunState.add_shrine_effect(&"learning", 3)
	_live()
	var xp_before := RunState.xp + RunState.level * 1000
	var p := Pickup.create(0, 10)
	_world().add_child(p)
	p.collect(hero)
	var gained := (RunState.xp + RunState.level * 1000) - xp_before
	check(gained >= 14 and gained <= 1000 + 15, "x1.5 XP (got %d)" % gained)
	check_eq(RunState.shrine_xp_remainder, 0.0, "10 x 1.5 is whole")


# --- Enemies ---------------------------------------------------------------------------

func _grunt_at(wave: int) -> Enemy:
	RunState.rng.seed = 11
	var e := Enemy.create(Db.get_enemy(&"skeleton_grunt"), wave)
	nodes.append(e)
	return e


func test_enemies_set_up_during_a_shrine_are_tougher() -> void:
	var plain := _grunt_at(6)
	RunState.add_shrine_effect(&"learning", 3)
	RunState.add_shrine_effect(&"greed", 3)
	RunState.add_shrine_effect(&"haste", 3)
	_live()
	var boosted := _grunt_at(6)
	check_near(boosted.max_hp, plain.max_hp * 1.25, 0.0001, "Learning: +25% HP")
	check_near(boosted.hp, boosted.max_hp, 0.0001, "full HP")
	check_near(boosted.contact_damage, plain.contact_damage * 1.2, 0.0001, "Greed: +20% damage")
	check_near(boosted.move_speed, plain.move_speed * 1.15, 0.0001, "Haste: +15% speed")


func test_ranged_enemies_throw_harder_too() -> void:
	RunState.rng.seed = 3
	var plain := Enemy.create(Db.get_enemy(&"troll_axethrower"), 8)
	nodes.append(plain)
	RunState.add_shrine_effect(&"greed", 3)
	_live()
	RunState.rng.seed = 3
	var boosted := Enemy.create(Db.get_enemy(&"troll_axethrower"), 8)
	nodes.append(boosted)
	check_near(boosted.projectile_damage, plain.projectile_damage * 1.2, 0.0001, "projectile damage +20%")


func test_enemies_are_plain_outside_a_wave_or_without_shrines() -> void:
	var plain := _grunt_at(6)
	RunState.add_shrine_effect(&"learning", 3)
	var not_live := _grunt_at(6)
	check_eq(not_live.max_hp, plain.max_hp, "not live: HP")
	check_eq(not_live.move_speed, plain.move_speed, "not live: speed")
	_live()
	RunState.shrine_effects.clear()
	var none := _grunt_at(6)
	check_eq(none.max_hp, plain.max_hp, "nothing running: HP")
	check_eq(none.contact_damage, plain.contact_damage, "nothing running: damage")


func test_the_boss_gets_the_hp_bonus() -> void:
	var data := BossData.for_wave(10)
	var plain := Boss.create(data, 10)
	nodes.append(plain)
	RunState.add_shrine_effect(&"learning", 3)
	_live()
	var boosted := Boss.create(data, 10)
	nodes.append(boosted)
	check_near(boosted.max_hp, plain.max_hp * 1.25, 0.001, "Learning: +25% boss HP")
	check_near(boosted.hp, boosted.max_hp, 0.001, "full HP")


# --- Heroes ----------------------------------------------------------------------------

func test_blood_trades_max_hp_for_damage_and_leaves_with_the_wave() -> void:
	_human()
	var hero := _hero_of(0)
	var base_hp := hero.max_hp()
	var base_damage := hero.bonuses.damage_mult(null, &"physical", &"weapon")
	RunState.add_shrine_effect(&"blood", 3)
	Shrines.begin_wave([hero])
	check_near(hero.max_hp(), base_hp * 0.8, 0.2, "-20% max HP")
	check_near(hero.bonuses.damage_mult(null, &"physical", &"weapon"), base_damage + 0.2, 0.0001, "+20% damage")
	check(hero.hp <= hero.max_hp() + 0.001, "HP clamped to the smaller maximum")
	var gone := Shrines.end_wave([hero])
	check(gone.is_empty(), "two waves left")
	check_near(hero.max_hp(), base_hp, 0.001, "the maximum is back")
	check_near(hero.bonuses.damage_mult(null, &"physical", &"weapon"), base_damage, 0.0001, "damage back")
	check(hero.bonuses.effects_of(Shrines.SOURCE).is_empty(), "the source is empty")


func test_haste_gives_the_heroes_haste() -> void:
	_human()
	var hero := _hero_of(0)
	var base := hero.stats.get_stat(Stats.HASTE)
	RunState.add_shrine_effect(&"haste", 3)
	Shrines.begin_wave([hero])
	check_near(hero.stats.get_stat(Stats.HASTE), base + 15.0, 0.001, "+15% haste")
	Shrines.end_wave([hero])
	check_near(hero.stats.get_stat(Stats.HASTE), base, 0.001, "gone with the wave")


func test_a_shrine_that_ran_out_leaves_nothing_on_the_hero() -> void:
	_human()
	var hero := _hero_of(0)
	RunState.add_shrine_effect(&"blood", 1)
	Shrines.begin_wave([hero])
	check(not hero.bonuses.effects_of(Shrines.SOURCE).is_empty(), "blood on")
	var gone := Shrines.end_wave([hero])
	check_eq(gone, [&"blood"] as Array[StringName], "expired")
	Shrines.begin_wave([hero])
	check(hero.bonuses.effects_of(Shrines.SOURCE).is_empty(), "the next wave starts clean")


func test_the_effects_do_not_apply_to_a_freed_or_missing_hero() -> void:
	RunState.add_shrine_effect(&"blood", 3)
	Shrines.begin_wave([null])
	Shrines.end_wave([null])
	check(true, "no crash")


# --- Accepting -------------------------------------------------------------------------

func test_accepting_a_timed_shrine_starts_it() -> void:
	_human()
	var result := Shrines.accept(_shrine(&"greed"), PlayerManager.get_slots())
	check_eq(RunState.shrine_waves_left(&"greed"), 3, "three waves")
	check((result["lines"] as Array).size() >= 1, "a line for the card")
	check_eq(RunState.gold, 0, "no gold moved")


func test_fortune_gives_every_hero_an_epic_and_takes_a_quarter_of_the_purse() -> void:
	_human("pad:a", &"warrior")
	_human("pad:b", &"mage")
	RunState.gold = 201
	RunState.set_wave(7)
	var result := Shrines.accept(_shrine(&"fortune"), PlayerManager.get_slots())
	for slot in PlayerManager.get_slots():
		var eq := (slot.player as Player).equipment
		check_eq(eq.backpack.size(), 1, "%s got one item" % slot.label())
		var item := eq.backpack[0]
		check_eq(item.rarity, Items.Rarity.EPIC, "%s: Epic" % slot.label())
		check(item.can_be_used_by(slot.class_data), "%s can use it" % slot.label())
	check_eq(RunState.gold, 151, "a quarter of 201 (50, rounded down) is gone")
	check_eq(RunState.spend_log.size(), 1, "one spend entry")
	var entry := RunState.spend_log[0]
	check(entry["kind"] == &"shrine" and entry["slot"] == -1 and entry["amount"] == 50, "kind shrine, the team, 50 gold")
	check_eq(entry["label"], "Shrine of Fortune", "label")
	check((result["lines"] as Array).size() == 3, "the purse line and one line per hero")


func test_fortune_sells_the_item_when_the_backpack_is_full() -> void:
	_human("pad:a", &"warrior")
	var eq := (_hero_of(0)).equipment
	while eq.has_space():
		eq.add_to_backpack(MarketFakes.make_item("Junk", Items.SlotType.TRINKET))
	RunState.gold = 100
	RunState.set_wave(5)
	Shrines.accept(_shrine(&"fortune"), PlayerManager.get_slots())
	check_eq(eq.backpack.size(), Items.BACKPACK_SIZE, "nothing added")
	check(RunState.gold > 75, "the Greed value of the Epic paid out")
	check_eq(RunState.gold_gain_log.size(), 1, "logged as a gain")
	check_eq(RunState.gold_gain_log[0]["slot"], 0, "for the hero")


func test_fortune_with_an_empty_purse_takes_nothing() -> void:
	_human()
	RunState.gold = 0
	Shrines.accept(_shrine(&"fortune"), PlayerManager.get_slots())
	check(RunState.spend_log.is_empty(), "no spend entry for 0 gold")
	check_eq((_hero_of(0)).equipment.backpack.size(), 1, "the item still comes")


func _gambler_seed(win: bool) -> int:
	for s in 200:
		var r := RandomNumberGenerator.new()
		r.seed = s
		if (r.randf() < 0.5) == win:
			return s
	return 0


func test_the_gambler_wins_half_the_purse() -> void:
	_human()
	RunState.gold = 101
	RunState.shrine_rng.seed = _gambler_seed(true)
	var result := Shrines.accept(_shrine(&"gambler"), PlayerManager.get_slots())
	check_eq(RunState.gold, 151, "+50% (50) -> x1.5 rounded down")
	check_eq(RunState.gold_gain_log.size(), 1, "gain log")
	check(RunState.gold_gain_log[0]["amount"] == 50 and RunState.gold_gain_log[0]["slot"] == -1, "50 gold for the team")
	check(RunState.spend_log.is_empty(), "no spend")
	check_eq((result["lines"] as Array)[0], "The dice favour you: +50 gold!", "result line")


func test_the_gambler_loses_half_the_purse() -> void:
	_human()
	RunState.gold = 101
	RunState.shrine_rng.seed = _gambler_seed(false)
	Shrines.accept(_shrine(&"gambler"), PlayerManager.get_slots())
	check_eq(RunState.gold, 51, "-50 gold")
	check_eq(RunState.spend_log.size(), 1, "spend log")
	check(RunState.spend_log[0]["kind"] == &"shrine" and RunState.spend_log[0]["amount"] == 50, "kind shrine, 50")
	check(RunState.gold_gain_log.is_empty(), "no gain")


func test_the_gambler_flips_the_shrine_rng_not_the_gameplay_rng() -> void:
	_human()
	var before := RunState.rng.state
	RunState.gold = 100
	Shrines.accept(_shrine(&"gambler"), PlayerManager.get_slots())
	check_eq(RunState.rng.state, before, "RunState.rng untouched")
	Shrines.accept(_shrine(&"fortune"), PlayerManager.get_slots())
	check_eq(RunState.rng.state, before, "also by Fortune's items")


func test_the_gambler_coin_is_fair_over_many_flips() -> void:
	_human()
	var wins := 0
	for i in 400:
		RunState.gold = 100
		RunState.gold_gain_log.clear()
		Shrines.accept(_shrine(&"gambler"), PlayerManager.get_slots())
		if not RunState.gold_gain_log.is_empty():
			wins += 1
	check(wins > 150 and wins < 250, "about half (%d of 400)" % wins)


# --- The vote screen ---------------------------------------------------------------------

func test_bots_accept_a_timed_shrine_at_once() -> void:
	_bot("bot:a", &"warrior")
	_bot("bot:b", &"mage")
	_screen()
	var outcome: Array = []
	screen.decided.connect(func(accepted: bool, reason: StringName) -> void: outcome.append([accepted, reason]))
	var done: Array[bool] = [false]
	screen.finished.connect(func() -> void: done[0] = true)
	check(screen.open(_shrine(&"greed"), PlayerManager.get_slots()), "opened")
	check_eq(screen.phase, ShrineScreen.Phase.VOTING, "voting")
	_step()
	check_eq(outcome, [[true, &"accepted"]] as Array[Array], "both bots accepted on the first frame")
	check(done[0], "bots only: no time to read, the break goes on")
	check_eq(screen.result_time(), 0.0, "no lingering")


func test_bots_decline_fortune() -> void:
	_bot("bot:a", &"warrior")
	_screen()
	var outcome: Array = []
	screen.decided.connect(func(accepted: bool, reason: StringName) -> void: outcome.append([accepted, reason]))
	screen.open(_shrine(&"fortune"), PlayerManager.get_slots())
	_step()
	check_eq(outcome, [[false, &"declined"]] as Array[Array], "declined")
	check_eq(screen.headline(), "P1 declined – the shrine fades", "headline")


func test_nothing_to_vote_on_does_not_open() -> void:
	_screen()
	check(not screen.open(_shrine(&"greed"), PlayerManager.get_slots()), "nobody")
	MarketFakes.bot_with_hero(_world(), "bot:a", &"mage")
	check(not screen.open(null, PlayerManager.get_slots()), "no shrine")
	check_eq(screen.phase, ShrineScreen.Phase.IDLE, "idle")
	check(not screen.visible, "hidden")


func test_a_slot_without_a_hero_does_not_vote() -> void:
	_bot("bot:a", &"warrior")
	PlayerManager.join(UiFakes.HumanInput.new("pad:x"), Db.get_class_data(&"rogue"))
	_screen()
	screen.open(_shrine(&"greed"), PlayerManager.get_slots())
	check_eq(screen.voters.size(), 1, "only the hero")
	_step()
	check(screen.vote.is_accepted(), "the heroless slot does not block")


func test_a_human_votes_with_a_and_waits_for_the_lockout() -> void:
	var pad := _human()
	_screen()
	screen.open(_shrine(&"greed"), PlayerManager.get_slots())
	pad.press(PlayerInput.Pad.A)
	_step()
	pad.release(PlayerInput.Pad.A)
	_step(0.0)
	check_eq(screen.vote.undecided(), [0] as Array[int], "the opening frame and the lockout swallow the press")
	_past_lockout()
	_tap(pad, PlayerInput.Pad.A)
	check(screen.vote.is_accepted(), "A accepts")
	check_eq(screen.phase, ShrineScreen.Phase.RESULT, "the result shows")
	check_eq(screen.result_time(), ShrineScreen.RESULT_TIME, "a human reads it for a moment")


func test_b_declines_at_once() -> void:
	var pad := _human("pad:a")
	var pad2 := _human("pad:b", &"mage")
	_screen()
	screen.open(_shrine(&"greed"), PlayerManager.get_slots())
	_past_lockout()
	_tap(pad, PlayerInput.Pad.A)
	check(not screen.vote.is_decided(), "one of two")
	_tap(pad2, PlayerInput.Pad.B)
	check_eq(screen.vote.outcome(), ShrineVote.Outcome.DECLINED, "B declines the shrine")
	check_eq(screen.headline(), "P2 declined – the shrine fades", "who said no")


func test_all_humans_must_accept() -> void:
	var a := _human("pad:a")
	var b := _human("pad:b", &"mage")
	var c := _human("pad:c", &"rogue")
	_screen()
	screen.open(_shrine(&"blood"), PlayerManager.get_slots())
	_past_lockout()
	_tap(a, PlayerInput.Pad.A)
	_tap(b, PlayerInput.Pad.A)
	check(not screen.vote.is_decided(), "two of three")
	_tap(c, PlayerInput.Pad.A)
	check(screen.vote.is_accepted(), "all three")
	check_eq(screen.headline(), "Accepted by everyone", "headline")


func test_an_accept_can_be_taken_back_with_b() -> void:
	var a := _human("pad:a")
	var b := _human("pad:b", &"mage")
	_screen()
	screen.open(_shrine(&"greed"), PlayerManager.get_slots())
	_past_lockout()
	_tap(a, PlayerInput.Pad.A)
	_tap(a, PlayerInput.Pad.B)
	check_eq(screen.vote.outcome(), ShrineVote.Outcome.DECLINED, "changed to a decline")
	check(b != null, "(second voter exists)")


func test_the_clock_declines_the_undecided() -> void:
	var a := _human("pad:a")
	_human("pad:b", &"mage")
	_screen()
	screen.open(_shrine(&"greed"), PlayerManager.get_slots())
	_past_lockout()
	_tap(a, PlayerInput.Pad.A)
	for i in 14:
		_step(1.0)
	check(not screen.vote.is_decided(), "15 s are not over yet")
	check(screen.timer_bar.visible and not screen.result_box.visible, "the timer shows")
	_step(1.5)
	check_eq(screen.vote.reason, &"timeout", "timeout")
	check_eq(screen.headline(), "Time ran out – the shrine fades", "headline")
	check(screen.result_box.visible and not screen.timer_bar.visible, "the result replaces the timer")


func test_an_unplugged_pad_votes_like_a_bot() -> void:
	var a := _human("pad:a")
	a.connected = false
	_screen()
	screen.open(_shrine(&"greed"), PlayerManager.get_slots())
	_step()
	check(screen.vote.is_accepted(), "accepted for the unplugged player")
	_human("pad:b", &"mage").connected = false
	var s2 := ShrineScreen.create()
	tree.root.add_child(s2)
	nodes.append(s2)
	s2.open(_shrine(&"fortune"), PlayerManager.get_slots())
	s2.update(DT)
	check_eq(s2.vote.reason, &"declined", "the bot rule: Fortune is declined")


func test_a_human_with_bots_gets_time_to_read_the_card() -> void:
	var a := _human("pad:a")
	_bot("bot:b", &"mage")
	_screen()
	screen.open(_shrine(&"fortune"), PlayerManager.get_slots())
	_step()
	check(not screen.vote.is_decided(), "the bot has not declined yet")
	check_eq(screen.vote.choice_of(1), ShrineVote.Choice.UNDECIDED, "still thinking")
	for i in 30:
		_step(0.1)
	check_eq(screen.vote.reason, &"declined", "after a moment the bot declines Fortune")
	check(a != null, "(human present)")


func test_demo_bots_think_before_they_vote() -> void:
	_bot("bot:a", &"warrior")
	_bot("bot:b", &"mage")
	_screen()
	screen.bot_think_time = 1.0
	screen.open(_shrine(&"greed"), PlayerManager.get_slots())
	_step()
	check(not screen.vote.is_decided(), "thinking")
	for i in 40:
		_step(0.1)
	check(screen.vote.is_accepted(), "voted after the think time")
	check_eq(screen.result_time(), ShrineScreen.RESULT_TIME, "a watched demo shows the result")


func test_the_result_lingers_then_finishes() -> void:
	var a := _human("pad:a")
	_screen()
	var done: Array[bool] = [false]
	screen.finished.connect(func() -> void: done[0] = true)
	screen.open(_shrine(&"greed"), PlayerManager.get_slots())
	_past_lockout()
	_tap(a, PlayerInput.Pad.A)
	_step(1.0)
	check(not done[0], "still showing")
	_step(1.0)
	check(not done[0], "still showing (2 s)")
	_step(0.6)
	check(done[0], "finished after the result time")
	check_eq(screen.phase, ShrineScreen.Phase.DONE, "done")


func test_a_leaving_player_may_complete_the_vote() -> void:
	var a := _human("pad:a")
	_human("pad:b", &"mage")
	_screen()
	screen.open(_shrine(&"greed"), PlayerManager.get_slots())
	_past_lockout()
	_tap(a, PlayerInput.Pad.A)
	check(not screen.vote.is_decided(), "waiting for P2")
	screen.remove_slot(1)
	check(screen.vote.is_accepted(), "P2 left: the rest was unanimous")
	check_eq(screen.chips_row.get_child_count(), 1, "one chip left")


func test_the_last_voter_leaving_ends_the_vote() -> void:
	_human("pad:a")
	_screen()
	var outcome: Array = []
	screen.decided.connect(func(accepted: bool, reason: StringName) -> void: outcome.append([accepted, reason]))
	screen.open(_shrine(&"greed"), PlayerManager.get_slots())
	screen.remove_slot(0)
	check_eq(outcome, [[false, &"nobody"]] as Array[Array], "nobody left: declined, no effect")


func test_the_card_shows_the_shrine() -> void:
	_human("pad:a")
	_human("pad:b", &"mage")
	_screen()
	screen.open(_shrine(&"blood"), PlayerManager.get_slots())
	check_eq(screen.name_label.text, "Shrine of Blood", "name")
	check_eq(screen.duration_label.text, "Lasts the next 3 waves", "duration")
	check_eq(screen.icon.data, _shrine(&"blood"), "icon")
	check_eq(screen.boon_box.get_child_count(), 1, "one boon line")
	check_eq((screen.boon_box.get_child(0) as Label).text, "+20% damage", "boon text")
	check_eq((screen.bane_box.get_child(0) as Label).text, "-20% max HP", "bane text")
	check(screen.boon_head.visible and screen.bane_head.visible, "both headings")
	check_eq(screen.chips_row.get_child_count(), 2, "one chip per voter")
	check(screen.timer_bar.visible and not screen.result_box.visible, "timer, no result yet")
	check(screen.subtitle_label.text.contains("Everyone must accept"), "the party is told the rule")
	screen.open(_shrine(&"gambler"), PlayerManager.get_slots())
	check_eq((screen.boon_box.get_child(0) as Label).text, "50% chance: the purse x1.5", "the next card replaces the lines")
	check_eq(screen.boon_box.get_child_count(), 1, "no leftovers")


func test_the_chips_follow_the_votes() -> void:
	var a := _human("pad:a")
	_bot("bot:b", &"mage")
	_screen()
	screen.open(_shrine(&"greed"), PlayerManager.get_slots())
	var chip0: PanelContainer = screen.chips_row.get_child(0)
	check(_chip_text(chip0).contains("Choosing"), "the human is choosing")
	var chip1: PanelContainer = screen.chips_row.get_child(1)
	check(_chip_text(chip1).contains("Thinking"), "the bot is thinking")
	_past_lockout()
	_tap(a, PlayerInput.Pad.A)
	for i in 20:
		_step(0.1)
	chip0 = screen.chips_row.get_child(0)
	check(_chip_text(chip0).contains("Accept"), "the human accepted")


func _chip_text(node: Node) -> String:
	var out := ""
	if node is Label:
		out += (node as Label).text + " "
	for c in node.get_children():
		out += _chip_text(c)
	return out


# --- The Intermission's SHRINE phase -----------------------------------------------------------------

func test_a_pending_shrine_opens_the_vote_between_loot_and_level_up() -> void:
	_bot("bot:a", &"warrior")
	_make_intermission()
	RunState.pending_shrine = &"greed"
	RunState.level = 4
	intermission.open(5, 1)
	check_eq(intermission.phase, Intermission.Phase.SHRINE, "the SHRINE phase")
	check(intermission.shrine_screen.visible and intermission.shrine_screen.is_voting(), "the card shows")
	check(not intermission._market_root.visible, "the market waits")
	check_eq(RunState.shrines_offered, 1, "offered")
	_run_intermission(0.05)  # one frame: the bot votes, the decision has no time to show, the break goes on
	check_eq(intermission.phase, Intermission.Phase.LEVEL_UP, "then the level-up cards")
	check(not intermission.shrine_screen.visible, "the card is gone")
	check_eq(RunState.pending_shrine, &"", "consumed")


func test_an_accepted_shrine_takes_effect_and_is_reported() -> void:
	_bot("bot:a", &"warrior")
	_make_intermission()
	RunState.pending_shrine = &"learning"
	intermission.open(5, 0)
	_run_intermission(0.3)
	check_eq(RunState.shrines_accepted, 1, "accepted")
	check_eq(RunState.shrine_waves_left(&"learning"), 3, "running for three waves")
	check_eq(_resolved, [[&"learning", true, &"accepted"]] as Array[Array], "shrine_resolved")
	check_eq(intermission.phase, Intermission.Phase.MARKET, "the market follows (no level-ups)")


func test_a_declined_shrine_leaves_nothing_behind() -> void:
	_bot("bot:a", &"warrior")
	_make_intermission()
	RunState.pending_shrine = &"gambler"
	RunState.gold = 100
	intermission.open(5, 0)
	_run_intermission(0.3)
	check_eq(RunState.shrines_offered, 1, "offered")
	check_eq(RunState.shrines_accepted, 0, "not accepted")
	check(RunState.shrine_effects.is_empty(), "nothing runs")
	check_eq(RunState.gold, 100, "the purse is untouched")
	check_eq(_resolved, [[&"gambler", false, &"declined"]] as Array[Array], "reported")
	check_eq(intermission.phase, Intermission.Phase.MARKET, "the break goes on")


func test_an_instant_shrine_acts_when_accepted() -> void:
	var a := _human("pad:a", &"warrior")
	_make_intermission()
	RunState.pending_shrine = &"fortune"
	RunState.gold = 80
	intermission.open(5, 0)
	for i in 10:
		_run_intermission(0.1)
	check_eq(intermission.phase, Intermission.Phase.SHRINE, "waiting for the human")
	a.press(PlayerInput.Pad.A)
	_run_intermission(0.1)
	a.release(PlayerInput.Pad.A)
	_run_intermission(0.1)
	check_eq(RunState.gold, 60, "a quarter of the purse is gone")
	check_eq((_hero_of(0)).equipment.backpack.size(), 1, "an Epic in the backpack")
	check(intermission.shrine_screen.result_detail.text.contains("P1 gets ["), "the card says what the hero got")
	_run_intermission(3.0)
	check_eq(intermission.phase, Intermission.Phase.MARKET, "then the market")
	check(not RunState.spend_log.is_empty() and RunState.spend_log[0]["kind"] == &"shrine", "the purse board's spend ticker has it")


func test_an_unknown_pending_shrine_never_stalls_the_break() -> void:
	_bot("bot:a", &"warrior")
	_make_intermission()
	RunState.pending_shrine = &"no_such_shrine"
	intermission.open(5, 0)
	check_eq(intermission.phase, Intermission.Phase.MARKET, "straight to the market")
	check_eq(RunState.pending_shrine, &"", "dropped")
	check_eq(RunState.shrines_offered, 0, "not offered")


func test_no_pending_shrine_no_phase() -> void:
	_bot("bot:a", &"warrior")
	_make_intermission()
	intermission.open(5, 0)
	check_eq(intermission.phase, Intermission.Phase.MARKET, "no shrine, no card")
	check_eq(RunState.shrines_offered, 0, "nothing offered")


func test_a_player_leaving_the_vote_hands_it_to_the_rest() -> void:
	var a := _human("pad:a", &"warrior")
	_human("pad:b", &"mage")
	_make_intermission()
	RunState.pending_shrine = &"haste"
	intermission.open(5, 0)
	_run_intermission(0.6)
	a.press(PlayerInput.Pad.A)
	_run_intermission(0.1)
	a.release(PlayerInput.Pad.A)
	_run_intermission(0.1)
	check_eq(intermission.phase, Intermission.Phase.SHRINE, "waiting for P2")
	intermission._on_player_left(PlayerManager.get_slot(1))
	check(intermission.shrine_screen.vote.is_accepted(), "P2 left: the shrine is accepted")
	check_eq(RunState.shrine_waves_left(&"haste"), 3, "and runs")


func test_the_phase_clears_when_the_intermission_reopens() -> void:
	var a := _human("pad:a", &"warrior")
	_make_intermission()
	RunState.pending_shrine = &"greed"
	intermission.open(5, 0)
	check(intermission.shrine_screen.visible, "open")
	RunState.pending_shrine = &""  # (Main._roll_shrine decides this at every break)
	intermission.open(6, 0)
	check(not intermission.shrine_screen.visible, "reopening closes the card (no pending shrine this time)")
	check(a != null, "(human present)")


# --- Main: the break path over several waves -----------------------------------------------------------

func _run_with_bots(count: int, chance: float) -> void:
	var opts := LaunchOptions.new()
	opts.shrine_chance = chance
	_make_main(opts)
	for i in count:
		PlayerManager.add_bot(Db.class_ids[i % Db.class_ids.size()], i + 1)
	main.start_run()


func test_the_break_rolls_a_shrine_and_the_bots_vote_on_it() -> void:
	_run_with_bots(2, 1.0)
	check_eq(RunState.shrine_chance_override, 1.0, "--shrine-chance reaches the run")
	_clear_wave_and_wait()
	check_eq(main.intermission.phase, Intermission.Phase.SHRINE, "the break opens with the shrine")
	check(RunState.pending_shrine != &"", "rolled")
	var id := RunState.pending_shrine
	check_eq(RunState.shrines_offered, 1, "the card opened")
	for i in 5:
		for slot in PlayerManager.get_slots():
			slot.input.poll(0.1)
		main.intermission._process(0.1)
	check_eq(main.intermission.phase, Intermission.Phase.MARKET, "decided by the bots, then the market")
	var bots_accept := Shrines.bot_accepts(Db.get_shrine(id))
	check_eq(RunState.shrines_accepted, 1 if bots_accept else 0, "accepted exactly when the bots' rule says so")
	check_eq(RunState.has_shrine_effect(id), bots_accept and Db.get_shrine(id).is_timed(), "a timed shrine runs")


func test_a_shrine_runs_three_waves_and_expires() -> void:
	_run_with_bots(2, 0.0)
	check(main.hud.shown_shrines().is_empty(), "no icons at the start")
	# Wave 1 is over: the party accepted Learning in the break.
	_clear_wave_and_wait()
	check(RunState.shrine_effects.is_empty(), "nothing rolled at chance 0")
	Shrines.accept(_shrine(&"learning"), PlayerManager.get_slots())
	check_eq(RunState.shrine_waves_left(&"learning"), 3, "three waves")
	main._on_intermission_continue()
	check_eq(main.state, Main.State.WAVE, "wave 2")
	check(RunState.shrine_effects_live, "the effects are live in the wave")
	check_eq(main.hud.shown_shrines(), [_shrine(&"learning")] as Array[ShrineData], "the HUD shows the icon")
	var icon := main.hud.shrine_row.get_child(0) as ShrineIcon
	check_eq(icon.badge, 3, "with 3 waves left")
	check(main.hud.shrine_row.visible, "the row shows")
	_clear_wave_and_wait()
	check(not RunState.shrine_effects_live, "not live in the break")
	check_eq(RunState.shrine_waves_left(&"learning"), 2, "wave 2 counted")
	main._on_intermission_continue()
	check_eq((main.hud.shrine_row.get_child(0) as ShrineIcon).badge, 2, "2 left on wave 3")
	_clear_wave_and_wait()
	check_eq(RunState.shrine_waves_left(&"learning"), 1, "wave 3 counted")
	main._on_intermission_continue()
	check_eq((main.hud.shrine_row.get_child(0) as ShrineIcon).badge, 1, "the last wave")
	_clear_wave_and_wait()
	check(RunState.shrine_effects.is_empty(), "wave 4 was the last one: expired")
	check(main.hud.shown_shrines().is_empty() and not main.hud.shrine_row.visible, "the icon is gone")
	main._on_intermission_continue()
	var grunt := Db.get_enemy(&"skeleton_grunt")
	var e := Enemy.create(grunt, 5)
	nodes.append(e)
	check_near(e.max_hp, grunt.hp_at_wave(5) * RunState.coop_hp_mult(), 0.0001, "wave 5 enemies are plain again")


func test_enemies_of_a_shrine_wave_are_boosted_in_the_real_flow() -> void:
	_run_with_bots(1, 0.0)
	_clear_wave_and_wait()
	Shrines.accept(_shrine(&"learning"), PlayerManager.get_slots())
	main._on_intermission_continue()
	RunState.rng.seed = 11
	var boosted := Enemy.create(Db.get_enemy(&"skeleton_grunt"), 4)
	nodes.append(boosted)
	_live(false)
	RunState.rng.seed = 11
	var plain := Enemy.create(Db.get_enemy(&"skeleton_grunt"), 4)
	nodes.append(plain)
	check_near(boosted.max_hp, plain.max_hp * 1.25, 0.0001, "an enemy made during wave 2 has +25% HP")


func test_hero_effects_start_with_the_wave_and_end_with_it() -> void:
	_run_with_bots(1, 0.0)
	var hero := main.players[0]
	var base_hp := hero.max_hp()
	_clear_wave_and_wait()
	Shrines.accept(_shrine(&"blood"), PlayerManager.get_slots())
	check_near(hero.max_hp(), base_hp, 0.001, "nothing yet in the break")
	main._on_intermission_continue()
	check_near(hero.max_hp(), base_hp * 0.8, 0.2, "wave 2: -20% max HP")
	_clear_wave_and_wait()
	check_near(hero.max_hp(), base_hp, 0.2, "wave over: back")
	check(hero.bonuses.effects_of(Shrines.SOURCE).is_empty(), "no shrine source in the market")


func test_a_one_wave_shrine_expires_at_the_first_break() -> void:
	_run_with_bots(1, 0.0)
	RunState.add_shrine_effect(&"haste", 1)
	_clear_wave_and_wait()
	check(RunState.shrine_effects.is_empty(), "haste ran its one wave and expired before the roll")
	check_eq(RunState.pending_shrine, &"", "chance 0: no new shrine")


func test_the_last_wave_has_no_shrine() -> void:
	_run_with_bots(1, 1.0)
	main.wave = RunState.total_waves()
	RunState.pending_shrine = &""
	main._after_wave_end()
	check_eq(RunState.pending_shrine, &"", "the run ends: no break, no roll")


# --- HUD ----------------------------------------------------------------------------------------------

func test_the_hud_shows_one_icon_per_running_shrine_with_its_waves_left() -> void:
	var hud := Hud.create()
	tree.root.add_child(hud)
	nodes.append(hud)
	check(not hud.shrine_row.visible, "hidden while nothing runs")
	RunState.add_shrine_effect(&"greed", 3)
	RunState.add_shrine_effect(&"blood", 1)
	check_eq(hud.shown_shrines(), [_shrine(&"greed"), _shrine(&"blood")] as Array[ShrineData], "both icons, in order")
	check(hud.shrine_row.visible, "row shown")
	check_eq((hud.shrine_row.get_child(0) as ShrineIcon).badge, 3, "greed: 3")
	check_eq((hud.shrine_row.get_child(1) as ShrineIcon).badge, 1, "blood: 1")
	RunState.tick_shrine_effects()
	check_eq(hud.shown_shrines(), [_shrine(&"greed")] as Array[ShrineData], "blood expired")
	check_eq((hud.shrine_row.get_child(0) as ShrineIcon).badge, 2, "greed: 2")
	RunState.start_run(1, 3)
	check(not hud.shrine_row.visible, "a new run clears the row")


func test_the_icons_have_a_picture_per_shrine() -> void:
	for id in Db.shrine_ids:
		var icon := ShrineIcon.create(Db.get_shrine(id), 64.0, 2)
		nodes.append(icon)
		tree.root.add_child(icon)
		check_eq(icon.main_color(), Db.get_shrine(id).color, "%s colour" % id)
		icon.queue_redraw()
	var bare := ShrineIcon.create(null)
	check_eq(bare.main_color(), Color(0.5, 0.5, 0.5), "grey without data")
	bare.free()
