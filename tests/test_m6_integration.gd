extends TestCase
## M6a integration: the seams between the six packages, run through the real code of both sides.
##   - ENEMIES x BOSSES: the Plague Ghoul's poison puddle is a hazard the bots step out of (the
##     interface BotInput._hazard_steer reads: group &"enemy_hazards" + hazard_push), swept by
##     WaveDirector.stop() together with the bosses' hazards; an Acolyte never heals a real Boss.
##   - BOSSES x METER: a boss killed by a hero lands in the damage meter (damage, bosses).
##   - BOSSES x ARTIFACTS: one Artifact roll per boss however many heroes get an item (one drop,
##     one pity step), the signal fires once.
##   - ARTIFACTS x METER: Dawn's Embrace credits the Paladin who cast it.
##   - SHOPSINKS / ENCHANTER x the purse board: consumables, Black Market and enchants are in
##     the Spent ticker.
##   - ARTIFACTS x ENCHANTER x shop: an Artifact is never sold, disenchanted, enchanted or
##     auto-disenchanted after an all-Pass, and the Enchanter tab lists it greyed.

const EFakes := preload("res://tests/enemies_fakes.gd")
const Fakes := preload("res://tests/player_fakes.gd")
const Support := preload("res://tests/test_loot_support.gd")
const UiFakes := preload("res://tests/ui_fakes.gd")
const DT := 1.0 / 60.0

const MORVAIN := &"lich_commander_morvain"
const VORTHALAX := &"vorthalax"

var world: Node3D
var _nodes: Array[Node] = []
var _slots: Array[PlayerSlot] = []
var _panels: Array[Node] = []
var _players: Array[Player] = []


func before_each() -> void:
	RunState.start_run(1, 4242)
	RunState.set_wave(10)
	PlayerManager.clear()
	UiFakes.reset_players()
	LootDrops.artifact_chance_override = -1.0
	LootDrops.artifact_roll_probe = Callable()
	world = EFakes.make_world(tree)


func after_each() -> void:
	LootDrops.artifact_chance_override = -1.0
	LootDrops.artifact_roll_probe = Callable()
	for panel in _panels:
		UiFakes.free_node(panel)
	_panels.clear()
	for n in _nodes:
		if is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	_nodes.clear()
	for p in _players:
		if is_instance_valid(p):
			p.free()
	_players.clear()
	Support.free_slots(_slots)
	_slots.clear()
	EFakes.free_world(tree, world)
	world = null
	PlayerManager.clear()
	UiFakes.reset_players()
	Enemy.invalidate_player_cache()
	tree.paused = false
	RunState.start_run(1, 1)


# --- Helpers -----------------------------------------------------------------------------------

func _entities() -> Node3D:
	return EFakes.arena_of(world).entities


func _boss(id: StringName = MORVAIN, pos: Vector3 = Vector3.ZERO, p_wave: int = 10) -> Boss:
	var b := Boss.create(Db.get_boss(id), p_wave)
	_entities().add_child(b)
	b.global_position = pos
	return b


## A real bot hero (own BotInput) in the arena.
func _bot(pos: Vector3, index: int = 0, class_id: StringName = &"mage") -> Player:
	var slot := PlayerSlot.new(index, BotInput.new("bot:b%d" % index, 3 + index), PlayerManager.PLAYER_COLORS[index])
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


## Joins a bot slot of [param class_id] with a real hero in the arena (slot.player set).
func _team_member(class_id: StringName, pos: Vector3) -> Player:
	var slot := PlayerManager.add_bot(class_id, 5 + PlayerManager.count())
	var p := Player.create(slot)
	_entities().add_child(p)
	p.global_position = pos
	slot.player = p
	Enemy.invalidate_player_cache()
	return p


func _loot_bags() -> Array[LootBag]:
	var out: Array[LootBag] = []
	for n in tree.get_nodes_in_group(&"loot_bags"):
		if not n.is_queued_for_deletion():
			out.append(n as LootBag)
	return out


func _clear_bags() -> void:
	for bag in _loot_bags():
		bag.free()


func _artifact_bags() -> int:
	var n := 0
	for bag in _loot_bags():
		if bag.item.rarity == Items.Rarity.ARTIFACT:
			n += 1
	return n


# --- ENEMIES x BOSSES: the poison puddle is a hazard the bots avoid -------------------------------

func test_a_poison_puddle_is_in_the_hazard_group_with_the_bots_interface() -> void:
	var puddle := PoisonPuddle.spawn(_entities(), Vector3(4.2, 0, 0), 1.6, 3.0, 0.5, 2.0, Color.GREEN)
	check(puddle.is_in_group(EnemyHazard.GROUP), "in the group the bots and WaveDirector.stop() read")
	check(puddle.has_method(&"hazard_push"), "answers hazard_push(from) like an EnemyHazard")
	check(puddle.is_dangerous(), "a fresh puddle hurts")
	var inside := puddle.hazard_push(Vector3(5.0, 0, 0))
	check(inside.x > 0.9 and absf(inside.y) < 0.001, "inside, east of the middle: pushed east (%s)" % inside)
	var west := puddle.hazard_push(Vector3(3.4, 0, 0))
	check(west.x < -0.9, "west of the middle: pushed west (%s)" % west)
	check_eq(puddle.hazard_push(Vector3(12.0, 0, 0)), Vector2.ZERO, "far away: nothing")
	# The same rule as the bosses' circles: radius + margin, 1..2 long.
	var edge := puddle.hazard_push(Vector3(4.2 + 1.6 + EnemyHazard.BOT_MARGIN - 0.05, 0, 0))
	check(edge.length() >= 1.0 and edge.length() < 1.1, "at the margin's edge a push of about 1 (%s)" % edge)
	check_eq(puddle.hazard_push(Vector3(4.2 + 1.6 + EnemyHazard.BOT_MARGIN + 0.05, 0, 0)), Vector2.ZERO,
			"just outside the margin: nothing")
	var circle := EnemyHazard.circle_push(Vector3(4.2, 0, 0), 1.6, Vector3(5.0, 0, 0))
	check_eq(inside, circle, "one shared rule for the circles")


func test_a_bot_steps_out_of_a_poison_puddle() -> void:
	var bot := _bot(Vector3(5, 0, 0))
	var puddle := PoisonPuddle.spawn(_entities(), Vector3(4.0, 0, 0), 1.6, 3.0, 0.5, 2.0, Color.GREEN)
	check(_bot_move(bot).x > 0.5, "the bot east of the middle runs east, out of it")
	puddle.global_position = Vector3(6.0, 0, 0)
	check(_bot_move(bot).x < -0.5, "from the other side it runs the other way")
	puddle.global_position = Vector3(24.0, 0, 0)
	check_eq(puddle.hazard_push(Vector3(5.0, 0, 0)), Vector2.ZERO, "far away the puddle pushes nothing")


func test_a_bot_dead_centre_in_a_puddle_runs_towards_the_arena_middle() -> void:
	var bot := _bot(Vector3(8, 0, 0))
	PoisonPuddle.spawn(_entities(), Vector3(8, 0, 0), 1.6, 3.0, 0.5, 2.0, Color.GREEN)
	check(_bot_move(bot).x < -0.5, "out, towards the middle")


func test_a_harmless_or_gone_puddle_does_not_push() -> void:
	var bot := _bot(Vector3(5, 0, 0))
	var calm := PoisonPuddle.spawn(_entities(), Vector3(4.5, 0, 0), 1.6, 3.0, 0.5, 0.0, Color.GREEN)
	check(not calm.is_dangerous() and calm.hazard_push(Vector3(5, 0, 0)) == Vector2.ZERO, "no damage, no danger")
	calm.remove()
	var puddle := PoisonPuddle.spawn(_entities(), Vector3(4.5, 0, 0), 1.6, 1.0, 0.5, 2.0, Color.GREEN)
	check(puddle.is_dangerous(), "burning")
	EFakes.step(puddle, 1.2)
	check(puddle.is_gone() and not puddle.is_dangerous(), "expired")
	check_eq(puddle.hazard_push(Vector3(5, 0, 0)), Vector2.ZERO, "an expired puddle pushes nothing")
	var move := _bot_move(bot)
	check(move.length() < 5.0, "and the bot is free to go on (%s)" % move)


func test_the_puddle_a_dead_ghoul_leaves_is_avoided_by_the_bot_next_to_it() -> void:
	var bot := _bot(Vector3(5.5, 0, 0))
	var ghoul := EFakes.spawn_enemy(world, Db.get_enemy(&"plague_ghoul"), Vector3(4.5, 0, 0), 7)
	ghoul.take_damage(1000.0)
	var list := PoisonPuddle.alive(tree)
	check_eq(list.size(), 1, "the ghoul left a puddle")
	var move := _bot_move(bot)
	check(move.x > 0.5, "the bot beside the kill steps out of it, east (%s)" % move)


func test_wave_stop_frees_poison_puddles_and_boss_hazards_alike() -> void:
	var d := WaveDirector.create(EFakes.arena_of(world))
	world.add_child(d)
	_nodes.append(d)
	EFakes.spawn_player(world, Vector3(-12, 0, 0))
	var puddle := PoisonPuddle.spawn(_entities(), Vector3(3, 0, 3), 1.6, 3.0, 0.5, 2.0, Color.GREEN)
	var fire := FireField.spawn(_entities(), Vector3(-3, 0, 3), 2.0, 1.0, 8.0, 1.0, 5.0)
	var circle := FrostCircle.spawn(_entities(), Vector3(0, 0, -4), 2.2, 1.2, 1.0, 0.0, 0.0)
	check_eq(tree.get_nodes_in_group(EnemyHazard.GROUP).size(), 3, "three hazards of two packages")
	d.start_wave(3)
	d.stop()
	for h in [puddle, fire, circle]:
		check(not is_instance_valid(h) or h.is_queued_for_deletion(), "%s is gone with the wave" % h)
	check(PoisonPuddle.alive(tree).is_empty(), "no live puddle is left")


# --- ENEMIES x BOSSES: the Acolyte and a real boss --------------------------------------------------

func test_an_acolyte_beside_a_real_boss_never_heals_it() -> void:
	RunState.start_run(1, 99)
	RunState.set_wave(10)
	EFakes.spawn_player(world, Vector3(0, 0, 16))
	var boss := _boss(MORVAIN, Vector3(0, 0, 0), 10)
	check(boss.is_boss(), "a real boss")
	boss.hp = boss.max_hp * 0.3
	var hp_before := boss.hp
	var acolyte := EFakes.spawn_enemy(world, Db.get_enemy(&"cultist_acolyte"), Vector3(3, 0, 0), 10)
	acolyte.attack_cooldown_left = 0.0
	EnemyGrid.mark_dirty()
	EFakes.step(acolyte, 3.0)
	check_eq(boss.hp, hp_before, "the boss's HP did not move: it was not healed")
	check(boss.shield_hp <= boss.max_hp * 0.2 + 0.01, "at most the 20%% refresh shield (%.1f of %.1f)" % [boss.shield_hp, boss.max_hp])
	EFakes.step(acolyte, 12.0)
	check_eq(boss.hp, hp_before, "still not healed after several channels")
	check(boss.shield_hp <= boss.max_hp * 0.2 + 0.01, "the shield never stacks")


func test_an_acolyte_heals_the_hurt_add_beside_a_boss_not_the_boss() -> void:
	RunState.start_run(1, 99)
	RunState.set_wave(10)
	EFakes.spawn_player(world, Vector3(0, 0, 16))
	var boss := _boss(MORVAIN, Vector3(0, 0, 0), 10)
	boss.hp = boss.max_hp * 0.2
	var boss_hp := boss.hp
	var data := EFakes.enemy_data()
	data.max_hp = 40.0
	data.move_speed = 0.0
	var add := EFakes.spawn_enemy(world, data, Vector3(4, 0, 1))
	add.max_hp = 40.0
	add.hp = 10.0
	var acolyte := EFakes.spawn_enemy(world, Db.get_enemy(&"cultist_acolyte"), Vector3(3, 0, 0), 10)
	acolyte.attack_cooldown_left = 0.0
	EnemyGrid.mark_dirty()
	EFakes.step(acolyte, 1.5)
	check(add.hp > 10.0 + 0.1, "the hurt add is healed (%.1f)" % add.hp)
	check_eq(boss.hp, boss_hp, "the more hurt boss is not")


# --- BOSSES x METER: a boss killed by a hero lands in the meter --------------------------------------

func test_a_boss_killed_by_heroes_is_credited_in_the_meter() -> void:
	RunState.start_run(2, 4343)
	RunState.set_wave(10)
	var first := _team_member(&"warrior", Vector3(6, 0, 0))
	var second := _team_member(&"mage", Vector3(-6, 0, 0))
	var boss := _boss(MORVAIN, Vector3(0, 0, 0), 10)
	boss.hp = 100.0
	WeaponRunner.apply_hit(first, boss, 60.0, false, Vector3.ZERO)
	check(not boss.is_dead(), "60 damage leave it standing")
	WeaponRunner.apply_hit(second, boss, 500.0, false, Vector3.ZERO)
	check(boss.is_dead(), "the second hit kills it")
	var a := first.slot.index
	var b := second.slot.index
	var dmg_a := float(RunState.damage_by_player.get(a, 0.0))
	var dmg_b := float(RunState.damage_by_player.get(b, 0.0))
	check(dmg_a > 0.0, "the first hero's damage is in the meter (%.1f)" % dmg_a)
	check_near(dmg_a + dmg_b, 100.0, 0.001, "together exactly what the boss had: overkill does not count (%.1f + %.1f)" % [dmg_a, dmg_b])
	check_eq(RunState.bosses_killed, 1, "one boss killed")
	check_eq(int(RunState.bosses_by_player.get(b, 0)), 1, "credited to the hero who landed the kill")
	check_eq(int(RunState.bosses_by_player.get(a, 0)), 0, "and not to the other")
	var stats := RunSummary.stats_of(b)
	check_eq(float(stats[&"bosses"]), 1.0, "the meter's stats show the boss")
	check_near(float(stats[&"damage"]), dmg_b, 0.001, "and the damage")
	check_eq(int(RunSummary.meter_dict()[str(b)]["bosses"]), 1, "the SMOKE_RESULT meter has it too")


# --- BOSSES x ARTIFACTS: one roll per boss -------------------------------------------------------------

func _four_heroes() -> Array[Player]:
	var out: Array[Player] = []
	for i in 4:
		var p := _team_member(Db.class_ids[i % Db.class_ids.size()], Vector3(-9 + 6 * i, 0, 9))
		out.append(p)
	return out


func test_a_boss_drops_one_artifact_at_most_not_one_per_hero() -> void:
	RunState.start_run(4, 8181)
	RunState.set_wave(25)
	var heroes := _four_heroes()
	LootDrops.artifact_chance_override = 1.0
	var drops: Array[StringName] = []
	var on_drop := func(_item: ItemInstance, source: StringName) -> void: drops.append(source)
	RunState.artifact_dropped.connect(on_drop)
	var boss := _boss(VORTHALAX, Vector3.ZERO, 25)
	boss.take_damage(boss.hp + 1.0, false, heroes[1])
	RunState.artifact_dropped.disconnect(on_drop)
	check(boss.is_dead(), "dead")
	check_eq(_artifact_bags(), 1, "exactly one Artifact bag from four hero drops")
	check_eq(_loot_bags().size(), 5, "plus one item per hero")
	check_eq(RunState.artifacts_dropped, 1, "one counted")
	check_eq(RunState.artifact_classes.size(), 1, "for one class")
	check_eq(drops.size(), 1, "one announcement")
	check_eq(RunState.artifact_pity, 0.0, "a drop resets the pity")
	check_eq(RunState.bosses_killed, 1, "and the boss counts once")


func test_every_boss_makes_exactly_one_artifact_roll_pity_or_drop() -> void:
	RunState.start_run(4, 6161)
	RunState.set_wave(25)
	var heroes := _four_heroes()
	var checked := 0
	for round in 8:
		if LootDrops.artifact_candidates(false).is_empty():
			break
		var dropped := RunState.artifacts_dropped
		var pity := RunState.artifact_pity
		var boss := _boss(VORTHALAX, Vector3.ZERO, 25)
		boss.take_damage(boss.hp + 1.0, false, heroes[round % heroes.size()])
		var drops := RunState.artifacts_dropped - dropped
		if drops == 1:
			check_eq(RunState.artifact_pity, 0.0, "boss %d: a hit resets the pity" % round)
			check_eq(_artifact_bags(), 1, "boss %d: one Artifact bag" % round)
		else:
			check_eq(drops, 0, "boss %d: never two Artifacts" % round)
			check_near(RunState.artifact_pity, pity + LootDrops.ARTIFACT_PITY_STEP, 0.0001,
					"boss %d: a miss adds ONE pity step, not one per hero" % round)
			check_eq(_artifact_bags(), 0, "boss %d: no Artifact bag" % round)
		check_eq(_loot_bags().size() - _artifact_bags(), 4, "boss %d: four items" % round)
		_clear_bags()
		checked += 1
	check(checked >= 4, "several bosses were checked (%d)" % checked)


func test_a_boss_roll_is_the_killers_and_uses_the_boss_chance() -> void:
	RunState.start_run(4, 7272)
	RunState.set_wave(25)
	var heroes := _four_heroes()
	var calls: Array[Array] = []
	LootDrops.artifact_roll_probe = func(source: ItemGenerator.Source, _enemy: Node3D, killer: Node3D) -> LootBag:
		calls.append([source, killer])
		return null
	var boss := _boss(VORTHALAX, Vector3.ZERO, 25)
	boss.take_damage(boss.hp + 1.0, false, heroes[2])
	check_eq(calls.size(), 4, "the four hero drops call the roll (the dedupe is inside it)")
	for c in calls:
		check_eq(c[0], ItemGenerator.Source.BOSS, "always the BOSS source")
	check(calls[0][1] == heroes[2], "the killer's roll comes first: its Fortune counts")
	LootDrops.artifact_roll_probe = Callable()
	check_eq(LootDrops.kill_artifact_source(boss, ItemGenerator.Source.LOOT), ItemGenerator.Source.BOSS,
			"a boss counts as a boss whatever source asks")


# --- ARTIFACTS x METER: Dawn's Embrace credits the Paladin --------------------------------------------

func test_dawns_embrace_shield_is_credited_to_the_casting_paladin() -> void:
	RunState.start_run(4, 1234)
	RunState.set_wave(10)
	var paladin := Fakes.spawn_player(world, 0, &"paladin")
	var ally := Fakes.spawn_player(world, 2, &"warrior", Vector3(1, 0, 0))
	for p in [paladin, ally]:
		p.stats.set_source(&"tough", {Stats.STAMINA: 500.0})
		p.hp = p.max_hp()
	var item := ItemGenerator.generate_artifact(&"paladin", 10)
	item.artifact_waves = 6
	paladin.equipment.backpack.append(item)
	check(paladin.equipment.equip(item), "the Paladin wears Dawnbreaker")
	Enemy.invalidate_player_cache()
	ally.hp = ally.max_hp() * 0.3
	var wog := Db.get_ability(&"word_of_glory")
	check(paladin.abilities.effect_for(wog).cast(paladin.abilities.build_context(wog)), "Word of Glory")
	var shield := ally.procs.shield_of(PaladinWordOfGlory.ARTIFACT_SHIELD)
	check(shield > 0.0, "the ally has Dawn's Embrace")
	ally.stats.set_source(&"naked", {Stats.ARMOR: -2.0})
	ally.invulnerable_left = 0.0
	ally.take_damage(shield * 0.5)
	check_near(float(RunState.absorbed_by_player.get(0, 0.0)), shield * 0.5, 0.001,
			"the Paladin (slot 0) is credited with what the shield soaked")
	check(not RunState.absorbed_by_player.has(2), "the shielded hero (slot 2) is not")


# --- SHOPSINKS / ENCHANTER x the purse board ---------------------------------------------------------------

func test_consumable_black_market_and_enchant_spends_show_in_the_purse_board() -> void:
	RunState.start_run(2, 5151)
	RunState.set_wave(15)
	RunState.add_gold(20000)
	RunState.add_dust(500, -1, "fixture")
	var slot := Support.make_slot(0, &"warrior")
	_slots.append(slot)
	var eq := Support.equipment_of(slot)
	var ring := Support.make_armor(40, ClassData.ArmorType.PLATE, 20, Items.Rarity.EPIC, Items.SlotType.RING)
	ring.display_name = "Blazing Jade Band"
	ring.wave = 15
	ring.buy_price = ItemGenerator.price_for(Items.Rarity.EPIC, 15)
	ring.enchants.append(EnchantRoll.new(Db.get_enchant(&"blazing"), 1))
	eq.add_to_backpack(ring)
	var shop := Shop.new()
	shop.open_round(15, [slot] as Array[PlayerSlot], RunState.rng)
	check(shop.black_market != null and not shop.consumables.is_empty(), "wave 15: the row and the Black Market")
	var board := PurseBoard.create()
	board.set_shop(shop)
	tree.root.add_child(board)
	_nodes.append(board)
	RunState.begin_spend_round()
	board.refresh()
	check_eq(board.ticker_lines(), [PurseBoard.EMPTY_TICKER] as Array[String], "nothing spent yet")
	var consumable_name := shop.consumable_at(0).data.display_name
	check(shop.buy_consumable(0, slot), "a consumable bought")
	check(board.is_dirty(), "the board noticed")
	var market_name := shop.black_market.item.display_name
	check(shop.buy(Shop.BLACK_MARKET, slot), "the Black Market offer bought")
	var out := Enchanter.perform(eq, 0, ring, Enchanter.Action.EMPOWER, 0)
	check(out.ok, "an Empower: %s" % out.reason)
	board.refresh()
	var kinds: Array[StringName] = []
	for entry in RunState.spend_log:
		kinds.append(StringName(entry["kind"]))
	check_eq(kinds, [&"consumable", &"black_market", &"enchant"] as Array[StringName], "the three spend kinds, in order")
	check_eq(PurseBoard.entry_text(RunState.spend_log[0]).begins_with("P1 %s " % consumable_name), true, "consumable: the plain name")
	check_eq(PurseBoard.entry_text(RunState.spend_log[1]).begins_with("P1 [%s] " % market_name), true, "Black Market: the bracketed item")
	check(PurseBoard.entry_text(RunState.spend_log[2]).contains("Empower"), "enchant: the action")
	var lines := board.ticker_lines()
	check(not lines.is_empty() and lines[0] != PurseBoard.EMPTY_TICKER, "the ticker shows spends now")
	check(lines[0].begins_with("P1 Empower"), "newest first: the enchant leads (%s)" % lines[0])
	var shown := " ".join(lines)
	check(shown.contains("more") or (shown.contains(consumable_name) and shown.contains(market_name)),
			"the others follow or are summed up: %s" % shown)
	check_eq(RunState.consumables_bought, 1, "counted")
	check_eq(RunState.enchants_done, 1, "counted")
	check(RunState.dust_spent > 0, "the Dust part of the enchant is on the Dust log")
	check_eq(RunState.dust_spend_log.size(), 1, "one Dust spend")


# --- ARTIFACTS x ENCHANTER x shop -----------------------------------------------------------------------------

func _real_hero(class_id: StringName = &"warrior") -> PlayerSlot:
	var slot := PlayerManager.join(ScriptedInput.new("integ:%d" % PlayerManager.count()), Db.get_class_data(class_id))
	var p := Player.create(slot)
	_players.append(p)
	return slot


func test_an_artifact_cannot_be_sold_disenchanted_enchanted_or_lost_to_dust() -> void:
	RunState.start_run(1, 2020)
	RunState.set_wave(15)
	RunState.add_gold(5000)
	RunState.add_dust(100, -1, "fixture")
	var slot := _real_hero(&"warrior")
	var eq := (slot.player as Player).equipment
	var relic := ItemGenerator.generate_artifact(&"warrior", 12)
	check(relic != null and relic.is_artifact(), "a real Artifact")
	eq.add_to_backpack(relic)
	check(not relic.can_sell(), "never sold")
	check(not relic.can_disenchant(), "the item says so too")
	check(not Enchanter.can_disenchant(relic), "never disenchanted")
	check_eq(Enchanter.dust_for(relic), 0, "no Dust")
	var dust := RunState.arcane_dust
	check_eq(Enchanter.disenchant(eq, relic, 0), 0, "a refused Disenchant")
	check(eq.backpack.has(relic), "it stays in the backpack")
	check_eq(Enchanter.disenchant_lost_item(relic), 0, "an all-Pass turns it into no Dust either")
	check_eq(RunState.arcane_dust, dust, "the pile did not move")
	var gold := RunState.gold
	for action in [Enchanter.Action.REROLL, Enchanter.Action.EMPOWER, Enchanter.Action.IMBUE]:
		var out := Enchanter.perform(eq, 0, relic, action, 0)
		check(not out.ok and out.reason == Enchanter.REASON_ARTIFACT, "action %d refused: %s" % [action, out.reason])
	check_eq(RunState.gold, gold, "nothing was paid")
	check_eq(relic.enchant_uses, 0, "no use counted")
	check(not Enchanter.is_enchantable(relic), "not enchantable")
	check_eq(Forge.blocked_reason(eq, relic), Forge.REASON_ARTIFACT, "and never forged")


func test_an_all_passed_artifact_is_lost_not_dusted_and_an_epic_is_dusted() -> void:
	RunState.start_run(2, 3030)
	RunState.set_wave(15)
	var slots: Array[PlayerSlot] = [Support.make_slot(0, &"mage"), Support.make_slot(1, &"warrior")]
	_slots.append_array(slots)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var dust := RunState.arcane_dust
	var relic := LootRoll.create(ItemGenerator.generate_artifact(&"mage", 12))
	for s in slots:
		relic.choose(s.index, LootRoll.Choice.PASS)
	relic.resolve(rng)
	relic.apply(slots)
	check_eq(relic.outcome, &"pass", "everybody passed")
	check_eq(relic.dust, 0, "an Artifact turns into no Dust")
	check_eq(RunState.arcane_dust, dust, "the pile is unchanged")
	var epic := LootRoll.create(Support.make_armor(40, ClassData.ArmorType.PLATE, 20, Items.Rarity.EPIC, Items.SlotType.RING))
	for s in slots:
		epic.choose(s.index, LootRoll.Choice.PASS)
	epic.resolve(rng)
	epic.apply(slots)
	check_eq(epic.dust, Enchanter.DUST_BY_RARITY[Items.Rarity.EPIC], "an Epic nobody wanted: its Dust")
	check_eq(RunState.arcane_dust, dust + Enchanter.DUST_BY_RARITY[Items.Rarity.EPIC], "in the pile")
	check_eq(relic.item.greed_value(), ItemGenerator.artifact_greed_value(12), "(an Artifact's Greed pays five Epic prices)")


func test_the_panel_offers_neither_sell_nor_disenchant_for_an_artifact_and_the_tab_lists_it_greyed() -> void:
	RunState.start_run(1, 4040)
	RunState.set_wave(15)
	var slot := _real_hero(&"warrior")
	var eq := (slot.player as Player).equipment
	var relic := ItemGenerator.generate_artifact(&"warrior", 12)
	var ring := Support.make_armor(40, ClassData.ArmorType.PLATE, 20, Items.Rarity.EPIC, Items.SlotType.RING)
	ring.display_name = "Blazing Jade Band"
	ring.wave = 15
	ring.buy_price = ItemGenerator.price_for(Items.Rarity.EPIC, 15)
	ring.enchants.append(EnchantRoll.new(Db.get_enchant(&"blazing"), 1))
	eq.add_to_backpack(relic)
	eq.add_to_backpack(ring)
	var panel := PlayerPanel.create(slot)
	tree.root.add_child(panel)
	panel.set_input_focus(true)
	_panels.append(panel)
	panel.select_backpack(0)
	panel.open_menu()
	var labels := Array(panel.menu_labels())
	check(not labels.has("Disenchant"), "no Disenchant for the Artifact: %s" % str(labels))
	check(labels.has("Sell") and not panel.menu_entry_enabled("Sell"), "Sell is there but greyed")
	check_eq(panel.menu_entry_detail("Sell"), "Artifact", "and says why")
	panel.close_menu()
	panel.select_backpack(1)
	panel.open_menu()
	check(Array(panel.menu_labels()).has("Disenchant"), "the Epic ring can be disenchanted")
	panel.close_menu()
	panel.set_tab(PlayerPanel.ENCHANTER_TAB)
	var tab := panel.enchanter
	var relic_index := tab.items.find(relic)
	var ring_index := tab.items.find(ring)
	check(relic_index >= 0 and ring_index >= 0, "both are listed")
	check(not tab.cells[relic_index].enchantable, "the Artifact's cell is greyed")
	check(tab.cells[ring_index].enchantable, "the ring's is not")
	tab.select_item(relic_index)
	check_eq(tab.item_reason(), Enchanter.REASON_ARTIFACT, "the tab says why")
	check(tab.rows.is_empty(), "no enchant rows for an Artifact")
	tab.select_item(ring_index)
	check_eq(tab.item_reason(), "", "the ring can be worked on")
	check(not tab.rows.is_empty(), "and shows its rows")


func test_a_bot_that_holds_an_artifact_weapon_does_not_enchant_it() -> void:
	RunState.start_run(1, 5050)
	RunState.set_wave(15)
	RunState.add_gold(5000)
	RunState.add_dust(100, -1, "fixture")
	var slot := _real_hero(&"warrior")
	var eq := (slot.player as Player).equipment
	var relic := ItemGenerator.generate_artifact(&"warrior", 12)
	eq.add_to_backpack(relic)
	check(eq.equip(relic), "the bot wears the Artifact")
	var gold := RunState.gold
	check_eq(Enchanter.bot_enchant(slot, 5000), 0, "nothing to do on an Artifact")
	check_eq(RunState.gold, gold, "no gold spent")
	check_eq(RunState.enchants_done, 0, "no enchant counted")
