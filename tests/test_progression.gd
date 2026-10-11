extends TestCase
## M4 progression core (GDD 6): AbilityRanks, learning into slots, Rank V specialisations,
## auto-cast slots, LevelUpDeck (draw guarantees, apply, reroll price, bots), StatCards and
## the Trainer.

const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0


class CountingEffect extends AbilityEffect:
	var casts := 0
	var last_power := 0.0
	func wants_auto_cast(_ctx: AbilityContext) -> bool:
		return true
	func cast(ctx: AbilityContext) -> bool:
		casts += 1
		last_power = ctx.num("power", 1.0)
		return true


var world: Node3D
var _added: Array[StringName] = []


func before_each() -> void:
	PlayerManager.clear()
	RunState.start_run(1, 4242)
	world = Fakes.make_world(tree)


func after_each() -> void:
	for id in _added:
		Db.abilities.erase(id)
	_added.clear()
	Fakes.free_world(world)
	world = null
	PlayerManager.clear()


func _ability(id: StringName, kind: AbilityData.Kind, class_id: StringName = &"", cooldown: float = 4.0) -> AbilityData:
	var a := AbilityData.new()
	a.id = id
	a.display_name = String(id).capitalize()
	a.kind = kind
	a.class_id = class_id
	a.cooldown = cooldown
	a.targeting = AbilityData.Targeting.SELF
	a.effect = CountingEffect
	a.params = {"damage": 10.0}
	a.rank3 = {"projectiles_add": 1}
	a.rank3_text = "+1 projectile"
	a.specs = [
		{"name": "Bounce", "text": "Bounces", "mods": {"bounces": 2}},
		{"name": "Explode", "text": "Explodes", "mods": {"explode": true}},
	]
	return a


## Registers [param a] in the Db pool for the test.
func _pool(a: AbilityData) -> AbilityData:
	Db.abilities[a.id] = a
	_added.append(a.id)
	return a


func _hero(class_id: StringName = &"warrior") -> Player:
	return Fakes.spawn_player(world, 0, class_id)


# --- AbilityRanks ---------------------------------------------------------------------------

func test_rank_mods_follow_gdd() -> void:
	var a := _ability(&"t_bolt", AbilityData.Kind.AUTO)
	check_eq(AbilityRanks.mods_for(a, 1), {}, "Rank I: nothing")
	check_eq(AbilityRanks.mods_for(a, 2), {"power_pct": 25.0, "cooldown_pct": -10.0}, "Rank II")
	var r3 := AbilityRanks.mods_for(a, 3)
	check_eq(r3["projectiles_add"], 1, "Rank III adds the extra effect")
	var r4 := AbilityRanks.mods_for(a, 4)
	check_eq(r4["power_pct"], 50.0, "Rank IV: +50% in total")
	check_eq(r4["cooldown_pct"], -20.0, "-20% cooldown")
	check(not AbilityRanks.mods_for(a, 5).has("bounces"), "Rank V without a spec")
	check_eq(AbilityRanks.mods_for(a, 5, 0)["bounces"], 2, "spec 0")
	check(AbilityRanks.mods_for(a, 5, 1)["explode"], "spec 1")


func test_trainer_prices_and_refund() -> void:
	check_eq(AbilityRanks.trainer_price(1, 1), 25, "25 x 1 at wave 1")
	check_eq(AbilityRanks.trainer_price(2, 1), 50, "25 x 2")
	check_eq(AbilityRanks.trainer_price(3, 11), roundi(75.0 * 1.8), "25 x 3 x (1 + 0.08 x 10)")
	check_eq(AbilityRanks.trainer_price(5, 1), 0, "no rank above V")
	check_eq(AbilityRanks.gold_value(3, 1), 25 + 50, "ranks II and III")
	check_eq(AbilityRanks.replace_refund(3, 1), 37, "50% of 75, rounded down")
	check_eq(AbilityRanks.replace_refund(1, 9), 0, "Rank I is worth nothing")


# --- Runner: learning, ranks, specs, auto-cast ------------------------------------------------

func test_learn_into_kind_slots_and_forget() -> void:
	var p := _hero()
	var r := p.abilities
	var act := [_ability(&"t_a1", AbilityData.Kind.ACTIVE), _ability(&"t_a2", AbilityData.Kind.ACTIVE),
			_ability(&"t_a3", AbilityData.Kind.ACTIVE)]
	check_eq(r.learn(act[0]), 2, "first active -> RB slot")
	check_eq(r.learn(act[1]), 3, "second -> LB slot")
	check_eq(r.free_slot(AbilityData.Kind.ACTIVE), -1, "actives full")
	check_eq(r.learn(act[2]), -1, "no free slot")
	check_eq(r.learn(act[0]), -1, "already known")
	check_eq(r.learn(_ability(&"t_auto", AbilityData.Kind.AUTO)), 4, "auto -> slot 4")
	r.rank_up(&"t_a1")
	r.rank_up(&"t_a1")
	RunState.set_wave(1)
	check_eq(r.learn(act[2], 2), 2, "replaces RB")
	check(not r.knows(&"t_a1"), "old one forgotten")
	check_eq(r.rank_of(&"t_a3"), 1, "new one at Rank I")
	check_eq(r.forget(0), 0, "core slots cannot be emptied")
	check(r.slots[0] != null, "core kept")


func test_rank_up_power_and_spec() -> void:
	var p := _hero()
	var r := p.abilities
	var a := _ability(&"t_bolt", AbilityData.Kind.AUTO)
	r.learn(a)
	check_eq(r.rank_of(&"t_bolt"), 1, "Rank I")
	check_near(float(r.params_for(a)["power"]), 1.0, 0.0001, "power 1")
	for i in 3:
		check(r.rank_up(&"t_bolt"), "rank up %d" % i)
	check_eq(r.rank_of(&"t_bolt"), 4, "Rank IV")
	check_near(float(r.params_for(a)["power"]), 1.5, 0.0001, "+50% power")
	check_near(r.cooldown_of(a), 4.0 * 0.8, 0.001, "-20% cooldown")
	check_eq(r.params_for(a)["projectiles"], 1.0, "Rank III extra")
	check(r.rank_up(&"t_bolt"), "Rank V")
	check(not r.can_rank_up(&"t_bolt"), "max")
	check(r.needs_spec(&"t_bolt"), "asks for a spec")
	check(r.set_spec(&"t_bolt", 1), "spec chosen")
	check(not r.needs_spec(&"t_bolt"), "done")
	check(r.params_for(a)["explode"], "spec mods applied")


## A spec's "_pct" applies on top of the Rank IV value (Hot Streak's "cooldown 30% shorter"),
## not summed with the rank steps' percentages; item mods come last.
func test_spec_pct_mods_compound_with_the_ranks() -> void:
	var p := _hero()
	var r := p.abilities
	var a := _ability(&"t_hot", AbilityData.Kind.ACTIVE, &"", 10.0)
	a.specs = [{"name": "Hot", "text": "30% shorter cooldown, 20% more damage",
			"mods": {"cooldown_pct": -30.0, "power_pct": 20.0, "projectiles_add": 1}}]
	r.learn(a)
	for i in 4:
		r.rank_up(&"t_hot")
	r.set_spec(&"t_hot", 0)
	var params := r.params_for(a)
	check_near(float(params["cooldown"]), 10.0 * 0.8 * 0.7, 0.0001, "Rank IV cooldown, then 30% shorter")
	check_near(float(params["power"]), 1.5 * 1.2, 0.0001, "Rank IV power, then +20%")
	check_eq(float(params["projectiles"]), 2.0, "_add keys still add up (Rank III + spec)")
	check_eq(AbilityRanks.spec_mods(a, 4, 0), {}, "no spec below Rank V")
	check_eq(AbilityRanks.spec_mods(a, 5, 0)["cooldown_pct"], -30.0, "the spec's own mods")
	check_near(r.cooldown_of(a), 5.6, 0.0001, "the runner's cooldown")


## spec_mods hands out a copy: a caller merging into it must not change the spec of the shared
## (Db-loaded) AbilityData for every hero.
func test_spec_mods_are_a_copy() -> void:
	var a := _ability(&"t_spec", AbilityData.Kind.AUTO)
	a.specs[0]["mods"] = {"bounces": 2, "chain": [1, 2]}
	var mods := AbilityRanks.spec_mods(a, 5, 0)
	mods["bounces"] = 9
	mods["power_pct"] = 50.0
	(mods["chain"] as Array).append(3)
	check_eq(a.specs[0]["mods"], {"bounces": 2, "chain": [1, 2]}, "the resource's spec is untouched")
	check_eq(AbilityRanks.spec_mods(a, 5, 0), {"bounces": 2, "chain": [1, 2]}, "the next call sees the original")
	var summary := AbilityRanks.mods_for(a, 5, 0)
	summary["bounces"] = 7
	(summary["chain"] as Array).append(4)
	check_eq(a.specs[0]["mods"], {"bounces": 2, "chain": [1, 2]}, "nor through mods_for (nested values too)")


func test_auto_slots_cast_by_themselves_for_humans() -> void:
	var p := _hero()
	var r := p.abilities
	check(not r.auto_cast, "human player")
	var a := _ability(&"t_auto", AbilityData.Kind.AUTO)
	r.learn(a)
	r.rank_up(&"t_auto")
	for i in 20:
		r._physics_process(DT)
	var effect := r.effect_for(a) as CountingEffect
	check_eq(effect.casts, 1, "cast once, then on cooldown")
	check_near(effect.last_power, 1.25, 0.0001, "the rank's power reaches the effect")
	var act := _ability(&"t_act", AbilityData.Kind.ACTIVE)
	r.learn(act)
	for i in 20:
		r._physics_process(DT)
	check_eq((r.effect_for(act) as CountingEffect).casts, 0, "an Active slot waits for its button")


## From the wave start, every hero's auto-cast pass runs on its own tick (by slot), exactly
## every 15 ticks at 60 Hz.
func test_auto_cast_passes_are_staggered_by_slot() -> void:
	var runners: Array[AbilityRunner] = []
	var casts_at: Array[Array] = []
	for i in PlayerManager.MAX_PLAYERS:
		var p := Fakes.spawn_player(world, i, &"warrior", Vector3(6.0 * i, 0.0, 0.0))
		# No cooldown: the effect casts on every pass.
		p.abilities.learn(_ability(StringName("t_pass%d" % i), AbilityData.Kind.AUTO, &"", 0.0))
		p.begin_wave()
		runners.append(p.abilities)
		casts_at.append([])
	for tick in 300:
		for i in runners.size():
			var effect := runners[i].effect_for(runners[i].slots[4]) as CountingEffect
			var before := effect.casts
			runners[i]._physics_process(DT)
			if effect.casts > before:
				casts_at[i].append(tick + 1)
	var firsts := {}
	for i in runners.size():
		var ticks: Array = casts_at[i]
		check_eq(ticks.size(), 20, "P%d: 300 ticks / 15 = 20 passes" % (i + 1))
		firsts[ticks[0]] = true
		for k in range(1, ticks.size()):
			check_eq(ticks[k] - ticks[k - 1], 15, "P%d pass %d: every 0.25 s exactly" % [i + 1, k])
	check_eq(firsts.size(), PlayerManager.MAX_PLAYERS, "first passes on different ticks: %s" % [firsts.keys()])
	check_eq(casts_at[0][0], 1, "P1 still checks on the first tick")


# --- LevelUpDeck ----------------------------------------------------------------------------

func test_hand_has_an_ability_and_a_stat_card() -> void:
	var p := _hero()
	_pool(_ability(&"t_w1", AbilityData.Kind.AUTO, &"warrior"))
	_pool(_ability(&"t_g1", AbilityData.Kind.ACTIVE))
	_pool(_ability(&"t_m1", AbilityData.Kind.AUTO, &"mage"))
	var rng := RandomNumberGenerator.new()
	for seed_value in 60:
		rng.seed = seed_value
		var hand := LevelUpDeck.draw(p, rng)
		check_eq(hand.size(), 5, "five cards")
		var abilities := 0
		var stat_cards := 0
		var ids := {}
		for c in hand:
			if c.is_ability_card():
				abilities += 1
				check(not ids.has(c.ability.id), "no duplicate ability in a hand")
				ids[c.ability.id] = true
				check(c.ability.id != &"t_m1", "no other class's ability")
			else:
				stat_cards += 1
				check(not c.stats.is_empty(), "a stat card has stats")
		check(abilities >= 1 and stat_cards >= 1, "seed %d: %d ability, %d stat" % [seed_value, abilities, stat_cards])


func test_draw_is_deterministic() -> void:
	var p := _hero()
	_pool(_ability(&"t_w1", AbilityData.Kind.AUTO, &"warrior"))
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 9
	b.seed = 9
	var h1 := LevelUpDeck.draw(p, a)
	var h2 := LevelUpDeck.draw(p, b)
	for i in 5:
		check_eq(h1[i].title(), h2[i].title(), "card %d" % i)
		check_eq(h1[i].stats, h2[i].stats, "stats %d" % i)


func test_apply_cards() -> void:
	var p := _hero()
	var auto := _ability(&"t_auto", AbilityData.Kind.AUTO)
	var hp := p.max_hp()
	var res := LevelUpDeck.apply(p, LevelCard.stat(0, {Stats.STAMINA: 3.0} as Dictionary[StringName, float]))
	check(res["ok"], "stat card")
	check_eq(p.max_hp(), hp + 3.0, "+3 Stamina")
	LevelUpDeck.apply(p, LevelCard.stat(0, {Stats.STAMINA: 2.0} as Dictionary[StringName, float]))
	check_eq(p.stats.get_source(Player.CARD_SOURCE)[Stats.STAMINA], 5.0, "card stats add up")
	check(LevelUpDeck.apply(p, LevelCard.new_ability(auto))["ok"], "learned")
	check(p.abilities.knows(&"t_auto"), "slotted")
	check(LevelUpDeck.apply(p, LevelCard.rank_up(auto))["ok"], "rank up")
	check_eq(p.abilities.rank_of(&"t_auto"), 2, "Rank II")
	check(LevelUpDeck.apply(p, LevelCard.new_ability(auto))["ok"], "a known ability's card ranks it up")
	check_eq(p.abilities.rank_of(&"t_auto"), 3, "Rank III")


func test_full_slots_need_a_replacement_and_refund() -> void:
	var p := _hero()
	RunState.set_wave(1)
	var r := p.abilities
	r.learn(_ability(&"t_a1", AbilityData.Kind.ACTIVE))
	r.learn(_ability(&"t_a2", AbilityData.Kind.ACTIVE))
	r.rank_up(&"t_a1")
	r.rank_up(&"t_a1")  # Rank III: worth 75 g
	var gold := RunState.gold
	var card := LevelCard.new_ability(_ability(&"t_a3", AbilityData.Kind.ACTIVE))
	var res := LevelUpDeck.apply(p, card)
	check(not res["ok"] and res["needs_replace"], "asks which slot to replace")
	res = LevelUpDeck.apply(p, card, r.slot_of(&"t_a1"))
	check(res["ok"], "replaced")
	check_eq(res["refund"], 37, "50% of 75 g back")
	check_eq(RunState.gold, gold + 37, "into the shared wallet")
	check(r.knows(&"t_a3") and not r.knows(&"t_a1"), "swapped")


func test_full_slots_favour_rank_ups() -> void:
	var p := _hero()
	var r := p.abilities
	for i in 2:
		r.learn(_ability(StringName("t_a%d" % i), AbilityData.Kind.ACTIVE))
	for i in 4:
		r.learn(_ability(StringName("t_u%d" % i), AbilityData.Kind.AUTO))
	var fresh := _pool(_ability(&"t_new", AbilityData.Kind.AUTO, &"warrior"))
	var weights := {}
	for pair: Array in LevelUpDeck.ability_candidates(p):
		weights[(pair[0] as LevelCard).ability.id] = pair[1]
	check_near(weights[fresh.id], LevelUpDeck.FULL_SLOTS_NEW_WEIGHT, 0.0001, "new ability rarer when full")
	check_near(weights[&"t_u0"], LevelUpDeck.RANK_UP_WEIGHT_FULL, 0.0001, "rank-ups more often")


## GDD 6.1: with full slots, stat cards (not rank-ups) take the place of new abilities – a
## maxed hero's hands are mostly stat cards, still with one ability card.
func test_full_slots_shift_the_share_to_stat_cards() -> void:
	var p := _hero()
	var r := p.abilities
	check_near(LevelUpDeck.ability_share(p, LevelUpDeck.ability_candidates(p)), LevelUpDeck.ABILITY_SHARE,
			0.0001, "a fresh hero: half ability cards")
	for i in 2:
		r.learn(_ability(StringName("t_a%d" % i), AbilityData.Kind.ACTIVE))
	for i in 4:
		r.learn(_ability(StringName("t_u%d" % i), AbilityData.Kind.AUTO))
	var candidates := LevelUpDeck.ability_candidates(p)
	var total_weight := 0.0
	var rank_weight := 0.0
	for pair: Array in candidates:
		total_weight += float(pair[1])
		if (pair[0] as LevelCard).kind == LevelCard.Kind.RANK_UP:
			rank_weight += float(pair[1])
	check(rank_weight > 0.0 and rank_weight < total_weight, "rank-ups and replacement cards on offer")
	var full_share := LevelUpDeck.ability_share(p, candidates)
	check(full_share < LevelUpDeck.ABILITY_SHARE, "full slots at Rank I: fewer ability cards (%.2f)" % full_share)
	check_near(full_share, LevelUpDeck.ABILITY_SHARE * (rank_weight + LevelUpDeck.FULL_SLOTS_MIN_SHARE
			* (total_weight - rank_weight)) / total_weight, 0.0001, "only the replacement weight shrinks")
	# Seeded hands: the rank-ups keep the chance they had before full slots shrank the share
	# (ABILITY_SHARE x their weight share; the hand guarantees add a little, sampling noise
	# 0.004); the replacement cards give up most of theirs.
	var rank_ups := 0
	var replacements := 0
	var drawn := 0
	var hand_rng := RandomNumberGenerator.new()
	for seed_value in 4000:
		hand_rng.seed = seed_value
		for c in LevelUpDeck.draw(p, hand_rng):
			drawn += 1
			if c.kind == LevelCard.Kind.RANK_UP:
				rank_ups += 1
			elif c.kind == LevelCard.Kind.NEW_ABILITY:
				replacements += 1
	var rank_floor := LevelUpDeck.ABILITY_SHARE * rank_weight / total_weight
	check(float(rank_ups) / drawn >= rank_floor - 0.01,
			"rank-ups keep their chance: %.3f >= %.3f" % [float(rank_ups) / drawn, rank_floor])
	var replace_before := LevelUpDeck.ABILITY_SHARE * (total_weight - rank_weight) / total_weight
	check(float(replacements) / drawn < replace_before * 0.5,
			"replacement cards come far less often: %.3f < %.3f" % [float(replacements) / drawn, replace_before * 0.5])
	for a in r.slots:
		while r.can_rank_up(a.id):
			r.rank_up(a.id)
	check_near(LevelUpDeck.ability_share(p, LevelUpDeck.ability_candidates(p)),
			LevelUpDeck.ABILITY_SHARE * LevelUpDeck.FULL_SLOTS_MIN_SHARE, 0.0001, "everything at Rank V: the floor")
	var rng := RandomNumberGenerator.new()
	var stat_cards := 0
	var cards := 0
	for seed_value in 200:
		rng.seed = seed_value
		var abilities := 0
		for c in LevelUpDeck.draw(p, rng):
			cards += 1
			if c.is_ability_card():
				abilities += 1
				check_eq(c.kind, LevelCard.Kind.NEW_ABILITY, "only replacements are left")
			else:
				stat_cards += 1
		check(abilities >= 1, "seed %d: still one ability card" % seed_value)
	check(float(stat_cards) / cards > 0.7, "mostly stat cards (%.2f)" % (float(stat_cards) / cards))


func test_reroll_price() -> void:
	check_eq(LevelUpDeck.reroll_price(1, 0), 3, "wave + 2")
	check_eq(LevelUpDeck.reroll_price(5, 0), 7, "wave 5")
	check_eq(LevelUpDeck.reroll_price(5, 2), 11, "+2 per earlier reroll")


func test_bot_pick_prefers_free_slots_then_ranks() -> void:
	var p := _hero()
	var auto := _ability(&"t_auto", AbilityData.Kind.AUTO)
	var hand: Array[LevelCard] = [LevelCard.stat(3, {Stats.CRIT: 3.0} as Dictionary[StringName, float]),
			LevelCard.new_ability(auto)]
	check_eq(LevelUpDeck.bot_pick(p, hand), 1, "new ability into a free slot")
	p.abilities.learn(auto)
	hand = [LevelCard.stat(0, {Stats.CRIT: 1.0} as Dictionary[StringName, float]), LevelCard.rank_up(auto)]
	check_eq(LevelUpDeck.bot_pick(p, hand), 1, "rank-up over a common stat")


func test_stat_cards_use_the_class_primary_only() -> void:
	var rng := RandomNumberGenerator.new()
	var mage := Db.get_class_data(&"mage")
	for seed_value in 200:
		rng.seed = seed_value
		var rarity := StatCards.roll_rarity(rng)
		var stats := StatCards.roll_stats(rng, rarity, mage)
		check_eq(stats.size(), StatCards.RARITY_MULTS[rarity].size(), "stat count by rarity")
		check(not stats.has(Stats.STRENGTH) and not stats.has(Stats.AGILITY), "no other primary")
		for s: StringName in stats:
			check(stats[s] >= 1.0 and stats[s] == floorf(stats[s]), "whole amounts")


# --- Trainer --------------------------------------------------------------------------------

func test_trainer_buys_ranks_with_shared_gold() -> void:
	var p := _hero()
	RunState.set_wave(1)
	var core := p.abilities.slots[0]
	check(not Trainer.try_buy_rank(p, core.id), "no gold")
	RunState.add_gold(100)
	check(Trainer.try_buy_rank(p, core.id), "core abilities train too")
	check_eq(RunState.gold, 75, "25 g")
	check_eq(p.abilities.rank_of(core.id), 2, "Rank II")
	check_eq(Trainer.bot_train(p, 60), 0, "bots keep a reserve (75 - 25 < 60)")
	RunState.add_gold(200)
	check(Trainer.bot_train(p, 0) >= 2, "bots spend on ranks")
