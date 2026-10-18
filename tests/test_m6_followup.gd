extends TestCase
## M6a follow-up fixes (after the integration review):
##   - the market header names no seconds before a boss wave (it has no timer);
##   - a bot wearing an Artifact enchants its best non-Artifact item instead (Enchanter.bot_target);
##   - the integration clauses nothing pinned yet: the rescue stand ends inside a hazard
##     (BotInput) and a reroll's redrawn Black Market offer is looked at again by the bots
##     (Intermission._bots_reroll -> _bots_black_market);
##   - the Loot Roll screen keeps a tall tooltip frame below its title block.
## (The party-size division of the normal-kill Artifact chance is in test_m6_artifacts_core.gd.)

const EFakes := preload("res://tests/enemies_fakes.gd")
const Support := preload("res://tests/test_loot_support.gd")
const UiFakes := preload("res://tests/ui_fakes.gd")
const MarketFakes := preload("res://tests/test_ui_market_fakes.gd")
const DT := 1.0 / 60.0

var slots: Array[PlayerSlot] = []
var world: Node3D
var screen: Intermission
var _nodes: Array[Node] = []


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(2, 6161)
	RunState.set_wave(15)
	slots.clear()


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	_nodes.clear()
	UiFakes.free_node(screen)
	screen = null
	Support.free_slots(slots)
	slots.clear()
	UiFakes.free_node(world)
	world = null
	if _ework != null:
		EFakes.free_world(tree, _ework)
		_ework = null
	Enemy.invalidate_player_cache()
	UiFakes.reset_players()
	RunState.start_run(1, 1)


# --- 1. The market header before a boss wave ------------------------------------------------------

func test_next_wave_text_names_no_seconds_before_a_boss_wave() -> void:
	for wave in RunState.BOSS_WAVES:
		var text := Intermission.next_wave_text(wave)
		check_eq(text, "Next up: Wave %d of %d – Boss wave! (ends when the boss falls)" % [wave, RunState.TOTAL_WAVES],
				"wave %d" % wave)
		check("second" not in text and "·" not in text, "no countdown on wave %d: %s" % [wave, text])
	check_eq(Intermission.next_wave_text(10), "Next up: Wave 10 of 25 – Boss wave! (ends when the boss falls)", "the wave 10 line")
	check_eq(Intermission.next_wave_text(25), "Next up: Wave 25 of 25 – Boss wave! (ends when the boss falls)", "the wave 25 line")


func test_the_other_waves_keep_their_timer_line() -> void:
	var normal := Intermission.next_wave_text(4)
	check("Wave 4 of 25" in normal and "%d seconds" % int(RunState.wave_duration(4)) in normal, "a normal wave: %s" % normal)
	check("Boss" not in normal and "Elite" not in normal, "no tag")
	var elite := Intermission.next_wave_text(20)
	check("Wave 20 of 25" in elite and "%d seconds" % int(RunState.wave_duration(20)) in elite, "the elite wave keeps its clock: %s" % elite)
	check("Elite wave!" in elite, "and its tag")
	check_eq(Intermission.next_wave_text(26), "The final battle is won", "after the last wave")


func test_the_open_market_shows_the_boss_line() -> void:
	UiFakes.reset_players()
	RunState.start_run(1, 4)
	world = MarketFakes.make_world(tree)
	MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	screen = Intermission.create()
	UiFakes.add_to_root(tree, screen)
	screen.open(9, 0)
	check_eq(screen.next_label.text, "Next up: Wave 10 of 25 – Boss wave! (ends when the boss falls)", "cleared 9")
	screen.open(24, 0)
	check_eq(screen.next_label.text, "Next up: Wave 25 of 25 – Boss wave! (ends when the boss falls)", "cleared 24")
	screen.open(19, 0)
	check("seconds" in screen.next_label.text and "Elite wave!" in screen.next_label.text, "the elite wave line is as before: %s" % screen.next_label.text)


# --- 2. Bots wearing an Artifact enchant something else --------------------------------------------

func _slot(class_id: StringName = &"warrior") -> PlayerSlot:
	var s := Support.make_slot(slots.size(), class_id)
	Support.equipment_of(s).equip_starting_weapons()
	slots.append(s)
	return s


## A hand-built armour / jewellery piece of [param rarity] with the Db enchants [param ids] at [param rank].
func _piece(rarity: int, slot_type: Items.SlotType, item_level: int, ids: Array[StringName] = [], rank: int = 0) -> ItemInstance:
	var item := Support.make_armor(item_level, ClassData.ArmorType.PLATE, 20, rarity, slot_type)
	item.wave = 15
	item.buy_price = ItemGenerator.price_for(rarity, 15)
	for id in ids:
		item.enchants.append(EnchantRoll.new(Db.get_enchant(id), rank))
	return item


## Puts the warrior Artifact in the slot's main hand.
func _wear_artifact(s: PlayerSlot, class_id: StringName = &"warrior") -> ItemInstance:
	var eq := Support.equipment_of(s)
	var relic := ItemGenerator.generate_artifact(class_id, 12)
	check(relic != null and relic.is_artifact(), "a real %s Artifact" % class_id)
	eq.slots.clear()
	eq.slots[Items.EquipSlot.MAIN_HAND] = relic
	if relic.companion != null:
		eq.slots[Items.EquipSlot.OFF_HAND] = relic.companion
	return relic


func test_best_weapon_skips_an_artifact() -> void:
	var s := _slot(&"warrior")
	var eq := Support.equipment_of(s)
	var relic := _wear_artifact(s)
	check_eq(Enchanter.best_weapon(eq), null, "only an Artifact in hand: no weapon to enchant")
	# The Artifact in one hand, an ordinary attacker in the other: that one.
	var wand := Support.make_weapon(&"dagger", Items.Rarity.RARE)
	eq.slots[Items.EquipSlot.OFF_HAND] = wand
	check_eq(Enchanter.best_weapon(eq), wand, "the other hand's weapon, never the Artifact")
	check(Enchanter.best_weapon(eq) != relic, "not the Artifact")
	# The pair of daggers is two Artifacts.
	var rogue := _slot(&"rogue")
	_wear_artifact(rogue, &"rogue")
	var rogue_eq := Support.equipment_of(rogue)
	check(rogue_eq.get_item(Items.EquipSlot.OFF_HAND) != null and rogue_eq.get_item(Items.EquipSlot.OFF_HAND).is_artifact(), "the off-hand dagger is part of the pair")
	check_eq(Enchanter.best_weapon(rogue_eq), null, "a pair of Artifact daggers: nothing")


func test_bot_target_is_the_weapon_else_the_best_epic_armour_or_off_hand() -> void:
	var s := _slot(&"warrior")
	var eq := Support.equipment_of(s)
	# Without an Artifact the weapon stays the target, whatever else is worn.
	var epic_chest := _piece(Items.Rarity.EPIC, Items.SlotType.CHEST, 90)
	eq.slots[Items.EquipSlot.CHEST] = epic_chest
	check_eq(Enchanter.bot_target(eq), Enchanter.best_weapon(eq), "a weapon in hand: the weapon")
	check(Enchanter.bot_target(eq) != null, "and there is one")
	check_eq(Enchanter.bot_target(null), null, "no equipment")
	# The Artifact replaces it.
	eq.slots.erase(Items.EquipSlot.MAIN_HAND)
	var relic := _wear_artifact(s)
	eq.slots[Items.EquipSlot.CHEST] = epic_chest
	check_eq(Enchanter.bot_target(eq), epic_chest, "the Epic chest piece")
	# Below Epic does not count.
	eq.slots[Items.EquipSlot.RING_1] = _piece(Items.Rarity.RARE, Items.SlotType.RING, 200)
	check_eq(Enchanter.bot_target(eq), epic_chest, "a Rare ring is not worth the Dust")
	# Higher rarity, then Item Level, wins.
	var epic_legs := _piece(Items.Rarity.EPIC, Items.SlotType.LEGS, 120)
	eq.slots[Items.EquipSlot.LEGS] = epic_legs
	check_eq(Enchanter.bot_target(eq), epic_legs, "the higher Item Level of two Epics")
	var legendary := _piece(Items.Rarity.LEGENDARY, Items.SlotType.HEAD, 10)
	eq.slots[Items.EquipSlot.HEAD] = legendary
	check_eq(Enchanter.bot_target(eq), legendary, "a Legendary beats any Epic")
	# A piece with nothing left to do is passed over for the next one.
	legendary.enchants.append(EnchantRoll.new(Db.get_enchant(&"mighty"), 4))
	legendary.enchants.append(EnchantRoll.new(Db.get_enchant(&"brutal"), 4))
	check(Enchanter.bot_plan(legendary, Db.get_class_data(&"warrior")).is_empty(), "a full Legendary of rank V is done")
	check_eq(Enchanter.bot_target(eq), epic_legs, "so the next best Epic")
	# A non-attacking off-hand (a shield) counts too.
	var shield := Support.make_weapon(&"shield", Items.Rarity.EPIC)
	shield.item_level = 300
	shield.wave = 15
	shield.buy_price = ItemGenerator.price_for(Items.Rarity.EPIC, 15)
	eq.slots[Items.EquipSlot.OFF_HAND] = shield
	check(not Equipment.is_attacking_weapon(shield), "the fixture is no attacking weapon")
	check_eq(Enchanter.bot_target(eq), shield, "the off-hand piece")
	# The Artifact itself is never the target.
	check(Enchanter.bot_target(eq) != relic, "not the Artifact")
	eq.slots = {Items.EquipSlot.MAIN_HAND: relic}
	check_eq(Enchanter.bot_target(eq), null, "an Artifact alone: nothing to do")


func test_a_bot_holding_an_artifact_enchants_its_armour() -> void:
	RunState.start_run(1, 5051)
	RunState.set_wave(15)
	RunState.add_gold(5000)
	RunState.add_dust(100, -1, "fixture")
	var s := _slot(&"warrior")
	var eq := Support.equipment_of(s)
	var relic := _wear_artifact(s)
	var chest := _piece(Items.Rarity.EPIC, Items.SlotType.CHEST, 90, [&"mighty"], 1)
	eq.slots[Items.EquipSlot.CHEST] = chest
	var gold := RunState.gold
	var done := Enchanter.bot_enchant(s, 5000)
	check(done >= 1 and done <= Enchanter.BOT_MAX_ACTIONS, "the bot enchanted its armour: %d" % done)
	check_eq(RunState.enchants_done, done, "counted")
	check(RunState.gold < gold, "gold was spent")
	check_eq(chest.enchant_uses, done, "on the Epic chest piece")
	check_eq(relic.enchant_uses, 0, "never on the Artifact")
	check(relic.enchants.is_empty() or relic.enchants.size() == ItemGenerator.generate_artifact(&"warrior", 12).enchants.size(),
			"and the Artifact's enchants are as generated")


func test_a_bot_with_a_weapon_still_enchants_the_weapon_first() -> void:
	RunState.start_run(1, 5052)
	RunState.set_wave(15)
	RunState.add_gold(5000)
	RunState.add_dust(100, -1, "fixture")
	var s := _slot(&"warrior")
	var eq := Support.equipment_of(s)
	var sword := Support.make_weapon(&"sword", Items.Rarity.EPIC)
	sword.wave = 15
	sword.buy_price = ItemGenerator.price_for(Items.Rarity.EPIC, 15)
	eq.slots[Items.EquipSlot.MAIN_HAND] = sword
	var chest := _piece(Items.Rarity.EPIC, Items.SlotType.CHEST, 90, [&"mighty"], 1)
	eq.slots[Items.EquipSlot.CHEST] = chest
	var done := Enchanter.bot_enchant(s, 5000)
	check(done >= 1, "acted")
	check_eq(sword.enchant_uses, done, "the weapon took every action")
	check_eq(chest.enchant_uses, 0, "the armour was left alone")


# --- 4a. The rescue stand ends inside a hazard (BotInput) ------------------------------------------

var _ework: Node3D


func _arena_world() -> Node3D:
	if _ework == null:
		_ework = EFakes.make_world(tree)
	return _ework


func _entities() -> Node3D:
	return EFakes.arena_of(_arena_world()).entities


## A real bot hero (own BotInput) in the arena.
func _bot_hero(pos: Vector3, index: int, class_id: StringName = &"warrior") -> Player:
	var slot := PlayerSlot.new(index, BotInput.new("bot:f%d" % index, 3 + index), PlayerManager.PLAYER_COLORS[index])
	slot.class_data = Db.get_class_data(class_id)
	var p := Player.create(slot)
	_entities().add_child(p)
	p.global_position = pos
	Enemy.invalidate_player_cache()
	return p


func _bot_move(p: Player) -> Vector2:
	var bot := p.slot.input as BotInput
	bot.think(DT)
	return bot.get_move()


func test_a_bot_beside_a_downed_teammate_stands_still_without_a_hazard() -> void:
	var rescuer := _bot_hero(Vector3(6.5, 0, 0), 0)
	var ghost := _bot_hero(Vector3(6.0, 0, 0), 1, &"mage")
	ghost.downed = true
	check(not ghost.is_alive(), "the teammate is down")
	check(6.5 - 6.0 < BotInput.RESCUE_DISTANCE, "inside the revive circle")
	check_eq(_bot_move(rescuer), Vector2.ZERO, "no enemy, no hazard: the rescuer stands still and revives")
	# A hazard far away is no reason to leave the downed teammate.
	PoisonPuddle.spawn(_entities(), Vector3(-14, 0, 8), 1.6, 3.0, 0.5, 2.0, Color.GREEN)
	check_eq(_bot_move(rescuer), Vector2.ZERO, "a puddle far away changes nothing")


func test_a_bot_beside_a_downed_teammate_leaves_a_puddle_it_stands_in() -> void:
	var rescuer := _bot_hero(Vector3(6.5, 0, 0), 0)
	var ghost := _bot_hero(Vector3(6.0, 0, 0), 1, &"mage")
	ghost.downed = true
	PoisonPuddle.spawn(_entities(), Vector3(5.5, 0, 0), 1.6, 3.0, 0.5, 2.0, Color.GREEN)
	var move := _bot_move(rescuer)
	check(move.x > 0.5, "no enemy near, but the puddle under it: the rescuer steps out, east (%s)" % move)


func test_a_bot_beside_a_downed_teammate_leaves_a_boss_circle() -> void:
	var rescuer := _bot_hero(Vector3(6.5, 0, 0), 0)
	var ghost := _bot_hero(Vector3(6.0, 0, 0), 1, &"mage")
	ghost.downed = true
	FrostCircle.spawn(_entities(), Vector3(6.0, 0, 1.0), 2.2, 1.2, 1.0, 0.0, 0.0)
	var move := _bot_move(rescuer)
	check(move.length() > 0.5, "inside the telegraphed circle: the rescuer moves out of it (%s)" % move)
	check(move.y < -0.5, "away from the middle, which lies to the south (%s)" % move)


# --- 4b. A reroll's redrawn Black Market offer is bought (Intermission._bots_reroll) ------------------

func _bot_market(cleared_wave: int, gold: int, p_seed: int) -> PlayerSlot:
	UiFakes.free_node(screen)
	UiFakes.free_node(world)
	UiFakes.reset_players()
	RunState.start_run(1, p_seed)
	RunState.set_wave(cleared_wave)
	RunState.add_gold(gold)
	world = MarketFakes.make_world(tree)
	var slot := MarketFakes.bot_with_hero(world, "bot:0", &"warrior")
	screen = Intermission.create()
	screen.bot_shopping = true
	tree.root.add_child(screen)
	screen.open(cleared_wave, 0)
	return slot


func test_a_bot_reroll_that_redraws_an_affordable_black_market_upgrade_buys_it() -> void:
	var bought_after_reroll := false
	var tried := 0
	for p_seed in [7, 8, 9, 10, 11, 12]:
		var slot := _bot_market(16, 20000, p_seed)
		tried += 1
		var stall := screen.shop_panel.shop
		check(screen.shop_panel.has_black_market(), "the Black Market is open at wave 16")
		var first := stall.black_market.item
		var eq := (slot.player as Player).equipment
		var cheap_rerolls := stall.reroll_cost()
		check(RunState.gold - cheap_rerolls > Intermission.BOT_REROLL_RESERVE_MULT * Intermission.bot_train_reserve(16, 1), "rich enough to reroll")
		var shoppers: Array[PlayerSlot] = [slot]
		var rerolls := screen._bots_reroll(shoppers)
		check(rerolls >= 1, "the bot rerolled the stall (%d)" % rerolls)
		if RunState.black_market_bought == 1:
			# Bought inside _bots_reroll – the pass that only looks at the redrawn offer.
			check(stall.black_market.sold, "the redrawn offer is sold")
			check(stall.black_market.item != first, "and it is the redrawn one, not the first")
			check(eq.equipped_items().has(stall.black_market.item) or eq.backpack.has(stall.black_market.item), "and worn / carried by the bot")
			check(RunState.spend_log.any(func(e: Dictionary) -> bool: return e["kind"] == &"black_market"), "logged")
			bought_after_reroll = true
			break
	check(bought_after_reroll, "a reroll's redrawn Black Market upgrade was bought within %d seeds" % tried)
