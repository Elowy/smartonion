extends TestCase
## LEVEL UP phase of the intermission (GDD 6.1, 12): LOOT -> LEVEL_UP -> MARKET (skipped
## without level-ups or heroes), every player picks on their own controller in their own
## quarter (LevelUpPanel), level text per pick, several level-ups, reroll price / escalation /
## refusal from the shared wallet, the replacement sub-prompt with its refund, the Rank V
## specialisation, bots / unplugged pads / the countdown pick automatically, deterministic
## hands (per-player streams seeded from RunState.rng), input hygiene and the layout.
## The learned-ability pool is replaced by test abilities (Db.abilities) so the hands do not
## depend on the shipped content.

const UiFakes := preload("res://tests/ui_fakes.gd")
const MarketFakes := preload("res://tests/test_ui_market_fakes.gd")
const DT := 1.0 / 60.0

var world: Node3D
var screen: Intermission
var shop: MarketFakes.FakeShop
var continues := 0
var picked: Array[Array] = []
## Learned abilities of the shipped content, put back after each test.
var _stash: Dictionary[StringName, AbilityData] = {}
var _added: Array[StringName] = []


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(2, 9)
	RunState.wave = 5
	RunState.level = 6
	LevelUpScreen.pick_time = LevelUpScreen.PICK_TIME
	shop = MarketFakes.FakeShop.new()
	RunState.shop = shop
	_stash.clear()
	for id: StringName in Db.abilities.keys():
		if Db.abilities[id].is_learned_kind():
			_stash[id] = Db.abilities[id]
			Db.abilities.erase(id)
	for i in 3:
		_pool(_ability(StringName("t_active_%d" % i), AbilityData.Kind.ACTIVE))
	for i in 5:
		_pool(_ability(StringName("t_auto_%d" % i), AbilityData.Kind.AUTO))
	world = MarketFakes.make_world(tree)
	screen = Intermission.create()
	screen.continue_requested.connect(func() -> void: continues += 1)
	screen.level_card_picked.connect(func(i: int, c: LevelCard) -> void: picked.append([i, c]))
	tree.root.add_child(screen)


func after_each() -> void:
	LevelUpScreen.pick_time = LevelUpScreen.PICK_TIME
	Intermission.auto_continue_time = Intermission.AUTO_CONTINUE_TIME
	UiFakes.free_node(screen)
	UiFakes.free_node(world)
	screen = null
	world = null
	for id in _added:
		Db.abilities.erase(id)
	_added.clear()
	for id in _stash:
		Db.abilities[id] = _stash[id]
	_stash.clear()
	RunState.start_run(1, 1)
	UiFakes.reset_players()


# --- Helpers ---------------------------------------------------------------------------------

func _ability(id: StringName, kind: AbilityData.Kind, cooldown: float = 4.0) -> AbilityData:
	var a := AbilityData.new()
	a.id = id
	a.display_name = String(id).capitalize()
	a.kind = kind
	a.cooldown = cooldown
	a.school = &"fire"
	a.targeting = AbilityData.Targeting.SELF
	a.effect = AbilityEffect
	a.description = "Deals {damage} Fire damage in {radius} m."
	a.params = {"damage": 10.0, "radius": 3.0}
	a.rank3 = {"radius_add": 1.0}
	a.rank3_text = "+1 m radius"
	a.specs = [
		{"name": "Bounce", "text": "Bounces to 2 more enemies.", "mods": {"bounces": 2}},
		{"name": "Explode", "text": "Explodes on impact.", "mods": {"explode": true}},
	]
	return a


func _pool(a: AbilityData) -> AbilityData:
	Db.abilities[a.id] = a
	_added.append(a.id)
	return a


func _hero(key: String, class_id: StringName = &"warrior") -> UiFakes.HumanInput:
	return MarketFakes.human_with_hero(world, key, class_id)


func _player(index: int) -> Player:
	return PlayerManager.get_slot(index).player as Player


func _runner(index: int) -> AbilityRunner:
	return _player(index).abilities


func _panel(index: int) -> LevelUpPanel:
	return screen.level_up_screen.panel_of(index)


func _stat_card(stat: StringName = Stats.STAMINA, amount: float = 3.0) -> LevelCard:
	var stats: Dictionary[StringName, float] = {stat: amount}
	return LevelCard.stat(Items.Rarity.COMMON, stats)


func _hand(cards: Array) -> Array[LevelCard]:
	var out: Array[LevelCard] = []
	for c: LevelCard in cards:
		out.append(c)
	while out.size() < LevelUpDeck.HAND_SIZE:
		out.append(_stat_card(Stats.ARMOR, 1.0))
	return out


func _step(delta: float = DT) -> void:
	MarketFakes.poll_all(delta)
	screen._process(delta)
	if screen.loot_screen.visible:
		screen.loot_screen._process(delta)


func _tap(input: UiFakes.HumanInput, button: PlayerInput.Pad) -> void:
	input.press(button)
	_step()
	input.release(button)
	_step(0.0)


func _nudge(input: UiFakes.HumanInput, dir: Vector2) -> void:
	input.move = dir
	_step()
	input.move = Vector2.ZERO
	_step(0.0)


## Opens with [param level_ups] and steps past the opening frame and the input lockout.
func _open(level_ups: int, wave: int = 5) -> void:
	screen.open(wave, level_ups)
	_step()
	_step(LevelUpScreen.INPUT_LOCKOUT)


func _titles(hand: Array[LevelCard]) -> Array[String]:
	var out: Array[String] = []
	for c in hand:
		out.append("%s|%s" % [c.title(), ", ".join(c.lines())])
	return out


# --- Phase order -----------------------------------------------------------------------------

func test_loot_then_level_up_then_market() -> void:
	var a := _hero("pad:a")
	var b := _hero("pad:b", &"mage")
	RunState.add_team_loot(MarketFakes.make_item("Looted Charm", Items.SlotType.TRINKET, Items.NO_ARMOR, Items.Rarity.RARE))
	screen.open(5, 1)
	check_eq(screen.phase, Intermission.Phase.LOOT, "the loot roll first")
	check(not screen.level_up_screen.visible, "no cards yet")
	_step()
	_step(LootRollScreen.ITEM_INPUT_DELAY)
	_tap(a, PlayerInput.Pad.X)
	_tap(b, PlayerInput.Pad.X)
	_step(LootRollScreen.RESULT_TIME + 0.01)
	check_eq(screen.phase, Intermission.Phase.LEVEL_UP, "then the level-up cards")
	check(screen.level_up_screen.visible and not screen.loot_screen.visible, "card screen shown")
	check(not screen._market_root.visible, "market hidden")
	check_eq(shop.open_calls.size(), 0, "no shop round yet")
	check_eq(screen.time_left, Intermission.AUTO_CONTINUE_TIME, "the market countdown waits")
	_step()
	_step(LevelUpScreen.INPUT_LOCKOUT)
	_tap(a, PlayerInput.Pad.A)
	check_eq(screen.phase, Intermission.Phase.LEVEL_UP, "P2 still picks")
	_tap(b, PlayerInput.Pad.A)
	check_eq(screen.phase, Intermission.Phase.MARKET, "everyone picked: market")
	check(not screen.level_up_screen.visible and screen._market_root.visible, "market shown")
	check_eq(shop.open_calls.size(), 1, "shop round opened")
	check_eq(picked.size(), 2, "one card each")


func test_without_level_ups_or_heroes_the_phase_is_skipped() -> void:
	_hero("pad:a")
	screen.open(5, 0)
	check_eq(screen.phase, Intermission.Phase.MARKET, "no level-ups: straight to the market")
	check(not screen.level_up_screen.visible, "no cards")
	UiFakes.reset_players()
	PlayerManager.join(UiFakes.HumanInput.new("pad:x"), Db.get_class_data(&"rogue"))
	screen.open(6, 2)
	check_eq(screen.phase, Intermission.Phase.MARKET, "nobody with a hero: market")
	check_eq(screen.level_ups_value.text, "+2", "the level-ups still show in the summary")


func test_level_up_without_loot_comes_first() -> void:
	_hero("pad:a")
	screen.open(5, 1)
	check_eq(screen.phase, Intermission.Phase.LEVEL_UP, "level-up cards at once")
	check(screen.level_up_screen.panel_of(0) != null, "P1 has a panel")
	check_eq(screen.level_up_screen.panel_of(0).hand.size(), LevelUpDeck.HAND_SIZE, "5 cards")


# --- Per-player picking ----------------------------------------------------------------------

func test_each_player_drives_only_their_own_cards() -> void:
	var a := _hero("pad:a")
	var b := _hero("pad:b", &"mage")
	_open(1)
	var p1 := _panel(0)
	var p2 := _panel(1)
	p1.set_hand(_hand([_stat_card(Stats.STAMINA), _stat_card(Stats.CRIT), _stat_card(Stats.HASTE, 6.0)]))
	p2.set_hand(_hand([_stat_card(Stats.INTELLECT)]))
	_nudge(a, Vector2.RIGHT)
	_nudge(a, Vector2.RIGHT)
	check_eq(p1.cursor, 2, "P1's stick moves P1's cursor")
	check_eq(p2.cursor, 0, "P2's cursor stays")
	check(p1.cards[2].selected and not p1.cards[0].selected, "the selected card is highlighted")
	var haste_before := _player(0).stats.get_raw(Stats.HASTE)
	_tap(a, PlayerInput.Pad.A)
	check(p1.is_done(), "P1 picked their only card")
	check_near(_player(0).stats.get_raw(Stats.HASTE) - haste_before, 6.0, 0.001, "P1 got +6 Haste")
	check(not p2.is_done(), "P2 still choosing")
	check_eq(p1.history, ["+6% Haste"] as Array[String], "summary line")
	check_eq(screen.phase, Intermission.Phase.LEVEL_UP, "waiting for P2")
	_tap(a, PlayerInput.Pad.A)
	check(not p2.is_done(), "P1's A never picks for P2")
	_nudge(b, Vector2.LEFT)
	_tap(b, PlayerInput.Pad.A)
	check(p2.is_done(), "P2 picked")
	check_eq(screen.phase, Intermission.Phase.MARKET, "market")


func test_level_text_and_several_level_ups() -> void:
	var a := _hero("pad:a")
	RunState.level = 8
	_open(2)
	var p := _panel(0)
	check_eq(p.level_text(), "Level 7 – pick 1 of 5 (2 left)", "first of two picks")
	check_eq(p.level_label.text, "Level 7", "header")
	var first := p.hand.duplicate()
	_tap(a, PlayerInput.Pad.A)
	check_eq(p.picks_done, 1, "one pick done")
	check_eq(p.level_text(), "Level 8 – pick 1 of 5 (1 left)", "second pick")
	check(p.hand[0] != first[0], "a new hand was drawn")
	check_eq(screen.phase, Intermission.Phase.LEVEL_UP, "still picking")
	_tap(a, PlayerInput.Pad.A)
	check_eq(p.picks_done, 1, "A right after the new hand is ignored (PICK_INPUT_DELAY)")
	_step(LevelUpPanel.PICK_INPUT_DELAY)
	_tap(a, PlayerInput.Pad.A)
	check(p.is_done(), "both picks made")
	check_eq(p.history.size(), 2, "two summary lines")
	check_eq(picked.size(), 2, "two cards")
	check_eq(screen.phase, Intermission.Phase.MARKET, "market")


func test_stat_and_ability_cards_apply() -> void:
	var a := _hero("pad:a")
	_open(3)
	var p := _panel(0)
	var r := _runner(0)
	var fire := Db.get_ability(&"t_active_0")
	p.set_hand(_hand([LevelCard.new_ability(fire)]))
	_tap(a, PlayerInput.Pad.A)
	check(r.knows(&"t_active_0"), "learned the new ability")
	check_eq(r.slot_of(&"t_active_0"), 2, "into the first Active slot (RB)")
	check_eq(p.history[0], "Learned T Active 0", "summary")
	_step(LevelUpPanel.PICK_INPUT_DELAY)
	p.set_hand(_hand([LevelCard.rank_up(fire)]))
	_tap(a, PlayerInput.Pad.A)
	check_eq(r.rank_of(&"t_active_0"), 2, "free rank-up")
	check_eq(p.history[1], "T Active 0: Rank II", "summary")
	_step(LevelUpPanel.PICK_INPUT_DELAY)
	var whirl := r.slots[0]
	p.set_hand(_hand([LevelCard.rank_up(whirl)]))
	_tap(a, PlayerInput.Pad.A)
	check_eq(r.rank_of(whirl.id), 2, "core abilities rank up too")


# --- Reroll ----------------------------------------------------------------------------------

func test_reroll_price_escalates_and_is_refused_when_broke() -> void:
	var a := _hero("pad:a")
	var b := _hero("pad:b", &"mage")
	RunState.add_gold(20)
	_open(1, 5)
	var p1 := _panel(0)
	var p2 := _panel(1)
	check_eq(p1.reroll_price(), 7, "wave 5 + 2")
	var before := p1.hand.duplicate()
	_tap(a, PlayerInput.Pad.Y)
	check_eq(RunState.gold, 13, "paid from the shared wallet")
	check_eq(p1.rerolls, 1, "counted")
	check(p1.hand[0] != before[0], "all five cards redrawn")
	check_eq(p1.reroll_price(), 9, "+2 for the next reroll")
	check_eq(p2.reroll_price(), 7, "per player: P2's first reroll is still 7")
	_step(LevelUpPanel.PICK_INPUT_DELAY)
	_tap(a, PlayerInput.Pad.Y)
	check_eq(RunState.gold, 4, "second reroll 9")
	_step(LevelUpPanel.PICK_INPUT_DELAY)
	var hand := p1.hand.duplicate()
	_tap(a, PlayerInput.Pad.Y)
	check_eq(RunState.gold, 4, "11 g: refused")
	check_eq(p1.rerolls, 2, "not counted")
	check(p1.hand[0] == hand[0], "the hand stays")
	check("Not enough gold" in p1.message and p1.message_bad, "says why: %s" % p1.message)
	_tap(b, PlayerInput.Pad.Y)
	check_eq(RunState.gold, 4, "P2 cannot pay 7 either")
	RunState.add_gold(3)
	_tap(b, PlayerInput.Pad.Y)
	check_eq(RunState.gold, 0, "P2 pays 7")
	check_eq(p2.rerolls, 1, "P2 rerolled")
	check(not p1.is_done() and not p2.is_done(), "rerolls never pick")


# --- Replacement -----------------------------------------------------------------------------

func test_new_ability_with_full_slots_asks_what_to_replace() -> void:
	var a := _hero("pad:a")
	_open(1, 5)
	var r := _runner(0)
	for i in 4:
		r.learn(Db.get_ability(StringName("t_auto_%d" % i)))
	r.rank_up(&"t_auto_1")
	r.rank_up(&"t_auto_1")
	var newcomer := Db.get_ability(&"t_auto_4")
	var p := _panel(0)
	p.set_hand(_hand([LevelCard.new_ability(newcomer)]))
	check(p.cards[0].replaces, "the card says it replaces one")
	check(p.cards[0].warning_label.visible, "'Slots full – replaces one' strip")
	check_eq(p.cards[0].warning_label.text, "Slots full – replaces one", "warning text")
	check(not p.cards[1].replaces, "stat cards never do")
	_tap(a, PlayerInput.Pad.A)
	check_eq(p.mode, LevelUpPanel.Mode.REPLACE, "A opens the replacement prompt")
	check_eq(p.replace_slots(), AbilityRunner.AUTO_SLOTS, "the four auto-cast slots")
	_tap(a, PlayerInput.Pad.B)
	check_eq(p.mode, LevelUpPanel.Mode.CARDS, "B goes back to the cards")
	check(not r.knows(&"t_auto_4") and r.knows(&"t_auto_1"), "nothing changed")
	check(not p.is_done(), "still to pick")
	_step(LevelUpPanel.PICK_INPUT_DELAY)
	_tap(a, PlayerInput.Pad.A)
	check_eq(p.mode, LevelUpPanel.Mode.REPLACE, "prompt again")
	_nudge(a, Vector2.RIGHT)
	check_eq(p.replace_cursor, 1, "the stick moves over the slots")
	_step(LevelUpPanel.PICK_INPUT_DELAY)
	var refund := AbilityRanks.replace_refund(3, 5)
	check(refund > 0, "Rank III is worth something: %d" % refund)
	var gold := RunState.gold
	_tap(a, PlayerInput.Pad.A)
	check(r.knows(&"t_auto_4"), "learned the newcomer")
	check(not r.knows(&"t_auto_1"), "the Rank III ability is gone")
	check_eq(r.slot_of(&"t_auto_4"), AbilityRunner.AUTO_SLOTS[1], "into the chosen slot")
	check_eq(RunState.gold - gold, refund, "refund to the shared wallet")
	check(p.is_done(), "the pick is made")
	check_eq(p.history[0], "Learned T Auto 4 (for T Auto 1)", "summary")


# --- Rank V ----------------------------------------------------------------------------------

func test_rank_five_asks_for_a_specialisation() -> void:
	var a := _hero("pad:a")
	_open(1)
	var r := _runner(0)
	var bolt := Db.get_ability(&"t_auto_0")
	r.learn(bolt)
	for i in 3:
		r.rank_up(&"t_auto_0")
	check_eq(r.rank_of(&"t_auto_0"), 4, "Rank IV")
	var p := _panel(0)
	p.set_hand(_hand([LevelCard.rank_up(bolt)]))
	check_eq(p.cards[0].ribbon_text, "Rank IV → V", "ribbon")
	check_eq(p.cards[0].rank_label.text, "Specialization: Bounce or Explode", "names both specs")
	_tap(a, PlayerInput.Pad.A)
	check_eq(r.rank_of(&"t_auto_0"), 5, "Rank V")
	check_eq(p.mode, LevelUpPanel.Mode.SPEC, "asks for the specialisation")
	check(r.needs_spec(&"t_auto_0"), "not chosen yet")
	check(not p.is_done(), "the pick waits for it")
	_tap(a, PlayerInput.Pad.B)
	check_eq(p.mode, LevelUpPanel.Mode.SPEC, "no way back")
	_nudge(a, Vector2.RIGHT)
	check_eq(p.spec_cursor, 1, "the stick picks the second one")
	_step(LevelUpPanel.PICK_INPUT_DELAY)
	_tap(a, PlayerInput.Pad.A)
	check_eq(r.spec_of(&"t_auto_0"), 1, "Explode chosen")
	check(r.params_for(bolt).get("explode", false), "its mods apply")
	check(p.is_done(), "done")
	check_eq(p.history[0], "T Auto 0: Rank V – Explode", "summary names the spec")
	check_eq(screen.phase, Intermission.Phase.MARKET, "market")


# --- Automatic picks -------------------------------------------------------------------------

func test_bots_and_unplugged_pads_pick_by_themselves() -> void:
	var bot := MarketFakes.bot_with_hero(world, "bot:a", &"warrior")
	var gone := _hero("pad:b", &"mage")
	var human := _hero("pad:c", &"rogue")
	gone.connected = false
	screen.open(5, 2)
	check_eq(screen.phase, Intermission.Phase.LEVEL_UP, "cards")
	var bot_panel := screen.level_up_screen.panel_of(bot.index)
	check(bot_panel.automatic and _panel(1).automatic, "bot and unplugged pad pick automatically")
	check(not _panel(2).automatic, "the human picks")
	# The bot's auto-cast slots are full: it never takes a card that needs a replacement.
	var r := (bot.player as Player).abilities
	for i in 4:
		r.learn(Db.get_ability(StringName("t_auto_%d" % i)))
	bot_panel.set_hand(_hand([LevelCard.new_ability(Db.get_ability(&"t_auto_4")), _stat_card(Stats.CRIT)]))
	_step()
	check(bot_panel.is_done() and _panel(1).is_done(), "both done at once")
	check_eq(bot_panel.picks_done, 2, "both levels")
	check_eq(bot_panel.auto_picks, 2, "picked automatically")
	check(not r.knows(&"t_auto_4"), "no replacement for the bot")
	check(not _panel(2).is_done(), "the human still chooses")
	check_eq(screen.phase, Intermission.Phase.LEVEL_UP, "waiting for the human")
	_step(LevelUpScreen.INPUT_LOCKOUT)
	_tap(human, PlayerInput.Pad.A)
	_step(LevelUpPanel.PICK_INPUT_DELAY)
	_tap(human, PlayerInput.Pad.A)
	check_eq(screen.phase, Intermission.Phase.MARKET, "market")
	check_eq(picked.size(), 6, "three players x two levels")


func test_a_pad_unplugged_mid_phase_gets_auto_picks() -> void:
	var a := _hero("pad:a")
	var b := _hero("pad:b", &"mage")
	_open(1)
	b.connected = false
	_step()
	check(_panel(1).is_done(), "unplugged: picked for")
	check(not _panel(0).is_done(), "P1 still picks")
	_tap(a, PlayerInput.Pad.A)
	check_eq(screen.phase, Intermission.Phase.MARKET, "market")


func test_demo_bots_think_and_walk_their_cursor() -> void:
	var bot := MarketFakes.bot_with_hero(world, "bot:a", &"warrior")
	screen.level_up_screen.bot_think_time = 1.0
	screen.open(5, 1)
	var p := screen.level_up_screen.panel_of(bot.index)
	var stats: Dictionary[StringName, float] = {Stats.CRIT: 3.0, Stats.HASTE: 3.0, Stats.ARMOR: 2.0}
	p.set_hand(_hand([_stat_card(), _stat_card(), _stat_card(), LevelCard.stat(Items.Rarity.EPIC, stats)]))
	_step()
	_step(0.5)
	check(not p.is_done(), "still thinking")
	for i in 20:
		_step(0.25)
	check(p.is_done(), "picked")
	check_eq(p.cursor, 3, "the cursor went to the Epic card")
	check_eq(screen.phase, Intermission.Phase.MARKET, "market")


func test_idle_humans_get_auto_picks_when_time_runs_out() -> void:
	var a := _hero("pad:a")
	_hero("pad:b", &"mage")
	screen.open(5, 2)
	var limit := LevelUpScreen.PICK_TIME + LevelUpScreen.EXTRA_PICK_TIME
	check_eq(screen.level_up_screen.time_limit, limit, "40 s + 20 s for the second level")
	check(screen.level_up_screen.timer_bar.visible, "countdown shown")
	_step()
	_step(LevelUpScreen.INPUT_LOCKOUT)
	# P1 is mid-way: first pick made, the second one sits in a specialisation prompt.
	var r := _runner(0)
	var bolt := Db.get_ability(&"t_auto_0")
	r.learn(bolt)
	for i in 3:
		r.rank_up(&"t_auto_0")
	_panel(0).set_hand(_hand([_stat_card()]))
	_tap(a, PlayerInput.Pad.A)
	_step(LevelUpPanel.PICK_INPUT_DELAY)
	_panel(0).set_hand(_hand([LevelCard.rank_up(bolt)]))
	_tap(a, PlayerInput.Pad.A)
	check_eq(_panel(0).mode, LevelUpPanel.Mode.SPEC, "P1 chooses a specialisation")
	_nudge(a, Vector2.RIGHT)
	_step(limit - 2.0)
	check_eq(screen.phase, Intermission.Phase.LEVEL_UP, "not before the time is up")
	check_eq(picked.size(), 2, "only P1's picks so far")
	_step(1.0)
	_step(1.0)
	check_eq(screen.phase, Intermission.Phase.MARKET, "time up: everyone's picks are made")
	check_eq(r.spec_of(&"t_auto_0"), 1, "the highlighted specialisation was taken")
	check_eq(picked.size(), 4, "P2 got both picks automatically")
	check_eq(screen.time_left, Intermission.AUTO_CONTINUE_TIME, "the market gets its full minute")


func test_the_countdown_can_be_switched_off() -> void:
	_hero("pad:a")
	LevelUpScreen.pick_time = 0.0
	screen.open(5, 1)
	check(not screen.level_up_screen.timer_bar.is_visible_in_tree(), "no countdown")
	for i in 10:
		_step(30.0)
	check_eq(screen.phase, Intermission.Phase.LEVEL_UP, "waits for the player")


# --- Determinism -----------------------------------------------------------------------------

## Opens a fresh round with seed [param seed_value]; P1 rerolls [param rerolls] times, then
## P2 picks once. Returns [P1's first hand, P2's first hand, P2's second hand] as titles.
func _round(seed_value: int, rerolls: int) -> Array:
	UiFakes.reset_players()
	UiFakes.free_node(world)
	world = MarketFakes.make_world(tree)
	RunState.start_run(2, seed_value)
	RunState.shop = shop
	RunState.wave = 5
	RunState.level = 7
	RunState.add_gold(100)
	var a := _hero("pad:a")
	var b := _hero("pad:b", &"mage")
	_open(2)
	var out := [_titles(_panel(0).hand), _titles(_panel(1).hand)]
	for i in rerolls:
		_tap(a, PlayerInput.Pad.Y)
		_step(LevelUpPanel.PICK_INPUT_DELAY)
	_tap(b, PlayerInput.Pad.A)
	out.append(_titles(_panel(1).hand))
	return out


func test_hands_are_reproducible_and_independent() -> void:
	var first := _round(1234, 0)
	var again := _round(1234, 0)
	check_eq(again[0], first[0], "P1's hand is the same for the same seed")
	check_eq(again[1], first[1], "P2's hand too")
	check_eq(again[2], first[2], "and P2's next hand")
	var rerolled := _round(1234, 2)
	check_eq(rerolled[2], first[2], "P1's rerolls never change P2's cards")
	var other := _round(4321, 0)
	check(other[0] != first[0] or other[1] != first[1], "another seed, other hands")


# --- Input hygiene ---------------------------------------------------------------------------

func test_held_and_early_presses_never_pick() -> void:
	var a := _hero("pad:a")
	a.press(PlayerInput.Pad.A)
	a.poll(DT)
	screen.open(5, 1)
	var p := _panel(0)
	_step()
	_step()
	a.release(PlayerInput.Pad.A)
	_step()
	check(not p.is_done(), "the A held when the cards opened does nothing")
	_tap(a, PlayerInput.Pad.A)
	check(not p.is_done(), "an A inside the lockout does nothing")
	_tap(a, PlayerInput.Pad.Y)
	check_eq(p.rerolls, 0, "neither does Y")
	_step(LevelUpScreen.INPUT_LOCKOUT)
	_tap(a, PlayerInput.Pad.A)
	check(p.is_done(), "then A picks")


func test_held_stick_does_not_move_the_cursor() -> void:
	var a := _hero("pad:a")
	a.move = Vector2.RIGHT
	a.poll(DT)
	screen.open(5, 1)
	for i in 30:
		_step(0.05)
	check_eq(_panel(0).cursor, 0, "a stick held from the loot roll / wave is swallowed")
	a.move = Vector2.ZERO
	_step()
	_nudge(a, Vector2.RIGHT)
	check_eq(_panel(0).cursor, 1, "a fresh push moves")


# --- Cards and layout ------------------------------------------------------------------------

func test_card_texts() -> void:
	_hero("pad:a")
	_open(1)
	var r := _runner(0)
	var bolt := Db.get_ability(&"t_auto_0")
	var leap := Db.get_ability(&"t_active_0")
	check_eq(LevelCardView.kind_text(LevelCard.new_ability(bolt), r), "New Auto-cast", "auto kind")
	check_eq(LevelCardView.kind_text(LevelCard.new_ability(leap), r), "New Active", "active kind")
	check_eq(LevelCardView.body_text(LevelCard.new_ability(bolt), r), "Deals 10 Fire damage in 3 m.", "description filled")
	check_eq(LevelCardView.info_text(LevelCard.new_ability(bolt), r), "Fire · 4 s cooldown", "school and cooldown")
	r.learn(bolt)
	r.rank_up(&"t_auto_0")
	var up := LevelCard.rank_up(bolt)
	check_eq(LevelCardView.kind_text(up, r), "Rank II → III", "rank-up ribbon")
	check_eq(LevelCardView.rank_change_text(up, r), "+1 m radius", "Rank III text (AbilityRanks.rank_text)")
	check_eq(LevelCardView.body_text(up, r), "Deals 10 Fire damage in 4 m.", "the next rank's numbers")
	check_eq(LevelCardView.body_text(LevelCard.new_ability(bolt), r), "Deals 10 Fire damage in 3 m.", "params_for: the current rank")
	r.rank_up(&"t_auto_0")
	check_eq(LevelCardView.rank_change_text(LevelCard.rank_up(bolt), r), AbilityRanks.rank_text(bolt, 4), "Rank IV text")
	check_eq(LevelCardView.info_text(LevelCard.rank_up(bolt), r), "Fire · 3.6 → 3.2 s cooldown", "the cooldown drop of Rank IV")
	var stats: Dictionary[StringName, float] = {Stats.CRIT: 3.0, Stats.AGILITY: 2.0}
	var stat := LevelCard.stat(Items.Rarity.RARE, stats)
	check_eq(LevelCardView.kind_text(stat, r), "Rare", "stat ribbon")
	check_eq(LevelCardView.body_text(stat, r), "\n".join(stat.lines()), "stat lines")
	var view := _panel(0).cards[0]
	view.set_card(stat, r)
	check_eq(view.accent, UiTheme.RARITY_COLORS[Items.Rarity.RARE], "Items rarity colour")
	check_eq(view.name_label.text, "Rare Training", "title")


func test_four_players_get_their_own_quarters() -> void:
	var inputs: Array[UiFakes.HumanInput] = []
	for i in 4:
		inputs.append(_hero("pad:%d" % i, Db.class_ids[i % Db.class_ids.size()]))
	screen.open(5, 1)
	var lu := screen.level_up_screen
	check_eq(lu.order, [0, 1, 2, 3] as Array[int], "slot order")
	var expect := [[0.0, 0.0], [1.0, 0.0], [0.0, 1.0], [1.0, 1.0]]
	var rects: Array[Rect2] = []
	var view := lu.get_global_rect()
	for i in 4:
		var p := lu.panel_of(i)
		check(p.anchor_left == expect[i][0] and p.anchor_top == expect[i][1], "P%d in its quarter" % (i + 1))
		var r := Rect2(p.get_global_rect().position, LevelUpPanel.DESIGN_SIZE * p.scale)
		check(view.grow(0.5).encloses(r), "P%d on screen: %s in %s" % [i + 1, r, view])
		check(r.position.y >= LevelUpScreen.HEADER_HEIGHT - 0.5 or i >= 2, "P%d below the header" % (i + 1))
		for other in rects:
			check(not r.intersects(other), "P%d overlaps nobody" % (i + 1))
		rects.append(r)
	var span := LevelCardView.CARD_SIZE.x * LevelUpDeck.HAND_SIZE + LevelUpPanel.CARD_GAP * (LevelUpDeck.HAND_SIZE - 1)
	check(span <= LevelUpPanel.DESIGN_SIZE.x - 28.0, "five cards fit the panel: %.0f" % span)


func test_solo_and_duo_layouts() -> void:
	_hero("pad:a")
	screen.open(5, 1)
	var solo := screen.level_up_screen.panel_of(0)
	check_eq(solo.scale, Vector2.ONE * LevelUpScreen.SOLO_SCALE, "solo: larger")
	check_eq(solo.anchor_left, 0.5, "centred")
	_hero("pad:b", &"mage")
	screen.open(6, 1)
	var p1 := screen.level_up_screen.panel_of(0)
	var p2 := screen.level_up_screen.panel_of(1)
	check(p1.anchor_left == 0.0 and p2.anchor_left == 1.0, "two: side by side")
	check(p1.anchor_top == 0.5 and p2.anchor_top == 0.5, "in the middle band")


func test_player_leaving_mid_phase() -> void:
	var a := _hero("pad:a")
	_hero("pad:b", &"mage")
	_open(1)
	_tap(a, PlayerInput.Pad.A)
	check_eq(screen.phase, Intermission.Phase.LEVEL_UP, "waiting for P2")
	PlayerManager.leave(1)
	check(screen.level_up_screen.panel_of(1) == null, "P2's panel is gone")
	check_eq(screen.phase, Intermission.Phase.MARKET, "everyone left is done: market")
