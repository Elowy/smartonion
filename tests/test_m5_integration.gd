extends TestCase
## M5 integration (architecture §3.4, Wave 3): the packages meeting each other on real content –
## tier-set bonuses applied by the bonus engine (2 / 4 pieces change the hero's stats, ability
## params and procs, and leave with the pieces), forged Legendaries whose "every" / "hit_pct"
## procs fire on real weapon hits, elite and Loot Goblin drops travelling from the kill through
## the wave end into the Intermission's loot roll, the wallet's spend log covering every spender,
## talents + set bonuses + item ability_mods merging in AbilityRunner.params_for, and a talent
## reset refunding everything and logging the payment. Also the integrator's follow-ups: the
## shop's and the loot roll's upgrade badges count set bonuses (the viewer's equipment), and the
## Loot Goblin flees at walk_speed() (per-enemy speed multipliers apply).

const PFakes := preload("res://tests/player_fakes.gd")
const EFakes := preload("res://tests/enemies_fakes.gd")
const UiFakes := preload("res://tests/ui_fakes.gd")
const MarketFakes := preload("res://tests/test_ui_market_fakes.gd")
const Support := preload("res://tests/test_loot_support.gd")
const DT := 1.0 / 60.0

## The wallet spenders (RunState.try_spend_for kinds, architecture "Shared purse"): the six of M5,
## M6a's Enchanter action (&"enchant", whose Dust part is in RunState.dust_spend_log) and M6b's shrines
## (&"shrine": the purse a Shrine of Fortune / of the Gambler takes).
const SPEND_KINDS: Array[StringName] = [&"shop", &"shop_forge", &"shop_reroll", &"trainer",
	&"level_reroll", &"talent_reset", &"enchant", &"shrine"]
## Every game script that pays from the wallet (RunState.try_spend_for). A new spender must
## log its spends and be added here (and to the spend test below).
const SPENDER_FILES: Array[String] = [
	"res://core/items/enchanter.gd",
	"res://core/progression/trainer.gd",
	"res://core/shop/shop.gd",
	"res://core/shrines.gd",
	"res://core/talents/talent_state.gd",
	"res://scenes/ui/level_up/level_up_panel.gd",
]

var world: Node3D
var screen: Intermission
var _nodes: Array[Node] = []


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(2, 2024)
	RunState.set_wave(8)
	world = EFakes.make_world(tree)
	EnemyGrid.mark_dirty()


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	UiFakes.free_node(screen)
	screen = null
	EFakes.free_world(tree, world)
	world = null
	EnemyGrid.mark_dirty()
	Intermission.auto_continue_time = Intermission.AUTO_CONTINUE_TIME
	RunState.start_run(1, 1)
	UiFakes.reset_players()


# --- Helpers -----------------------------------------------------------------------------------

## A real hero of [param class_id] (slot [param index], not joined) at [param pos].
func _hero(index: int, class_id: StringName, pos: Vector3 = Vector3.ZERO) -> Player:
	return PFakes.spawn_player(world, index, class_id, pos)


## The set piece of [param class_id] for [param slot] ("head" ...), as the generator builds it.
static func _piece(class_id: StringName, slot: String) -> ItemInstance:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	return ItemGenerator.from_unique(Db.get_unique(StringName("set_%s_%s" % [class_id, slot])), 8, true, rng)


static func _unique(id: StringName) -> ItemInstance:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	return ItemGenerator.from_unique(Db.get_unique(id), 8, true, rng)


## Into the backpack, then equipped – the way the Character panel does it.
func _wear(p: Player, item: ItemInstance) -> void:
	check(p.equipment.add_to_backpack(item), "room for %s" % item.display_name)
	check(p.equipment.equip(item), "equip %s" % item.display_name)


func _unwear(p: Player, slot: Items.EquipSlot) -> void:
	check(p.equipment.unequip(slot), "unequip %s" % Items.EquipSlot.keys()[slot])


func _add_talents(p: Player, talent_ranks: Array) -> void:
	for pair: Array in talent_ranks:
		for r in int(pair[1]):
			check(p.talents.add(StringName(pair[0])), "add %s (%s)" % [pair[0], p.talents.add_block_reason(StringName(pair[0]))])


## [param stat] summed over the hero's equipped items (their own rolls, no bonuses).
static func _from_items(p: Player, stat: StringName) -> float:
	var sum := 0.0
	for item in p.equipment.equipped_items():
		sum += float(item.equip_stats().get(stat, 0.0))
	return sum


## The Rage [param amount] really adds after a runner tick (Resource Regen -> gain_mult).
static func _rage_gain(p: Player, amount: float) -> float:
	p.abilities._physics_process(DT)
	var rage := p.abilities.get_resource(&"rage")
	rage.set_value(0.0)
	rage.add(amount, true)
	return rage.value


## How many of [param n] casts of [param ability] would be free (AbilityRunner's own roll on
## the context the cast gets).
static func _free_rolls(p: Player, ability: AbilityData, n: int) -> int:
	var ctx := p.abilities.build_context(ability)
	var free := 0
	for i in n:
		if AbilityRunner._rolls_free(ctx):
			free += 1
	return free


## Casts [param ability] as far as the hero's hooks are concerned (the runner's ability_cast).
static func _cast(p: Player, ability: AbilityData) -> void:
	p.abilities.ability_cast.emit(p.abilities.slot_of(ability.id), ability)


## A weapon hit of [param p]'s main hand for [param base] (no crit, no knockback, no stun).
static func _hit(p: Player, e: Enemy, base: float) -> void:
	WeaponRunner.apply_hit(p, e, base, false, Vector3.ZERO, 0.0, 0.5, p.main_hand)


static func _sum_from(log: Array[float], from: int) -> float:
	var s := 0.0
	for i in range(from, log.size()):
		s += log[i]
	return s


## Two [param weapon_id] Epics of the hero forged into the weapon type's Legendary; enchants
## stripped so only the Legendary effect acts on the hits. Equipped. Returns it.
func _forge_legendary(p: Player, weapon_id: StringName) -> ItemInstance:
	var base := Db.get_weapon(weapon_id)
	var a := ItemInstance.from_weapon(base, Items.Rarity.EPIC, 8, true)
	var b := ItemInstance.from_weapon(base, Items.Rarity.EPIC, 8, false)
	check(p.equipment.add_to_backpack(a) and p.equipment.add_to_backpack(b), "two Epic %ss" % weapon_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var forged := Forge.forge(p.equipment, a, rng)
	check(forged != null, "forged")
	if forged == null:
		return null
	var legendary := Forge.legendary_for(weapon_id)
	check_eq(forged.rarity, Items.Rarity.LEGENDARY, "two Epics make a Legendary")
	check_eq(forged.display_name, legendary.display_name, "the weapon type's Legendary")
	check_eq(forged.unique_effect, legendary.unique_effect, "with its effect")
	check(p.equipment.backpack.has(forged) and not p.equipment.backpack.has(a) and not p.equipment.backpack.has(b),
		"both Epics became the Legendary")
	forged.enchants.clear()
	check(p.equipment.equip(forged, Items.EquipSlot.MAIN_HAND), "the Legendary in hand")
	check(p.main_hand == forged.weapon, "the hero swings it")
	return forged


# --- Tier sets through the bonus engine ---------------------------------------------------------

func test_warrior_set_bonuses_change_stats_and_params_and_leave_with_the_pieces() -> void:
	var w := _hero(0, &"warrior")
	var whirlwind := Db.get_ability(&"whirlwind")
	var regen := w.stats.get_raw(Stats.RESOURCE_REGEN)
	check_eq(_from_items(w, Stats.RESOURCE_REGEN), 0.0, "no Resource Regen on the gear (the numbers below)")
	check_near(_rage_gain(w, 10.0), 10.0 * (1.0 + regen / 100.0), 0.001, "no set: plain Rage gain")
	check_eq(_free_rolls(w, whirlwind, 50), 0, "no free Whirlwinds")
	_wear(w, _piece(&"warrior", "head"))
	check_eq(w.stats.get_raw(Stats.RESOURCE_REGEN), regen, "one piece: nothing")
	_wear(w, _piece(&"warrior", "shoulders"))
	check_eq(w.stats.get_raw(Stats.RESOURCE_REGEN), regen + 10.0, "2 pieces: +10% Resource Regen on the hero")
	check_near(_rage_gain(w, 10.0), 10.0 * (1.0 + (regen + 10.0) / 100.0), 0.001, "and Rage really comes faster")
	check(not w.abilities.params_for(whirlwind).has("free_chance"), "the 4-piece bonus not yet")
	_wear(w, _piece(&"warrior", "chest"))
	_wear(w, _piece(&"warrior", "legs"))
	check_eq(float(w.abilities.params_for(whirlwind).get("free_chance", 0.0)), 30.0, "4 pieces: Whirlwind free_chance 30")
	var free := _free_rolls(w, whirlwind, 600)
	check(free > 130 and free < 230, "about 30%% of the casts are free: %d / 600" % free)
	check_eq(w.stats.get_raw(Stats.RESOURCE_REGEN), regen + 10.0, "the 2-piece bonus stays at 4 (not doubled)")
	_unwear(w, Items.EquipSlot.CHEST)
	check(not w.abilities.params_for(whirlwind).has("free_chance"), "3 pieces: the 4-piece bonus left")
	check_eq(_free_rolls(w, whirlwind, 50), 0, "no free casts any more")
	check_eq(w.stats.get_raw(Stats.RESOURCE_REGEN), regen + 10.0, "the 2-piece bonus is still there")
	_unwear(w, Items.EquipSlot.HEAD)
	_unwear(w, Items.EquipSlot.LEGS)
	check_eq(w.stats.get_raw(Stats.RESOURCE_REGEN), regen, "1 piece: the stat is gone")
	check_near(_rage_gain(w, 10.0), 10.0 * (1.0 + regen / 100.0), 0.001, "plain Rage gain again")
	check(w.bonuses.effects_of(PlayerBonuses.SOURCE_SETS).is_empty(), "nothing left in the engine")


func test_mage_set_bonus_proc_fires_on_blink_and_leaves_with_the_pieces() -> void:
	var m := _hero(1, &"mage")
	var blink := Db.get_ability(&"blink")
	var proc_id := &"regalia_of_the_arcane:4"
	var haste := m.stats.get_raw(Stats.HASTE) - _from_items(m, Stats.HASTE)  # (the pieces roll Haste too)
	var dmg := m.stats.get_raw(Stats.DAMAGE_PCT)
	var mult := m.stats.damage_mult()
	for s in ["head", "shoulders"]:
		_wear(m, _piece(&"mage", s))
	check_eq(m.stats.get_raw(Stats.HASTE), haste + _from_items(m, Stats.HASTE) + 10.0, "2 pieces: +10% Haste")
	_cast(m, blink)
	check_eq(m.procs.fire_count(proc_id), 0, "no Blink proc with 2 pieces")
	check_eq(m.stats.get_raw(Stats.DAMAGE_PCT), dmg, "no damage buff")
	for s in ["chest", "hands"]:
		_wear(m, _piece(&"mage", s))
	_cast(m, Db.get_ability(&"blizzard"))
	check_eq(m.procs.fire_count(proc_id), 0, "another spell does not trigger it")
	_cast(m, blink)
	check_eq(m.procs.fire_count(proc_id), 1, "4 pieces: Blink fires the set proc")
	check_eq(m.stats.get_raw(Stats.DAMAGE_PCT), dmg + 30.0, "+30% damage")
	check_near(m.stats.damage_mult() - mult, 0.3, 0.0001, "the hero really hits 30% harder")
	m.procs._physics_process(3.05)
	check_eq(m.stats.get_raw(Stats.DAMAGE_PCT), dmg, "for 3 sec")
	_cast(m, blink)
	check_eq(m.procs.fire_count(proc_id), 1, "once every 6 sec")
	m.procs._physics_process(3.0)
	_cast(m, blink)
	check_eq(m.procs.fire_count(proc_id), 2, "again after the icd")
	_unwear(m, Items.EquipSlot.HANDS)
	check(m.procs.extra_defs(PlayerBonuses.SOURCE_SETS).is_empty(), "3 pieces: the proc left ProcSystem")
	check_eq(m.stats.get_raw(Stats.DAMAGE_PCT), dmg, "its running buff ended with it")
	m.procs._physics_process(7.0)
	_cast(m, blink)
	check_eq(m.stats.get_raw(Stats.DAMAGE_PCT), dmg, "Blink does nothing now")
	check_eq(m.stats.get_raw(Stats.HASTE), haste + _from_items(m, Stats.HASTE) + 10.0, "the 2-piece Haste stays")
	_unwear(m, Items.EquipSlot.CHEST)
	check_eq(m.stats.get_raw(Stats.HASTE), haste + _from_items(m, Stats.HASTE) + 10.0, "2 pieces: the Haste stays")
	_unwear(m, Items.EquipSlot.SHOULDERS)
	check_eq(m.stats.get_raw(Stats.HASTE), haste + _from_items(m, Stats.HASTE), "1 piece: the bonus is gone")
	check(m.bonuses.effects_of(PlayerBonuses.SOURCE_SETS).is_empty(), "nothing left in the engine")


func test_upgrade_badges_in_the_shop_and_the_loot_roll_count_set_bonuses() -> void:
	var slot := MarketFakes.bot_with_hero(world, "test:a", &"warrior")
	var hero := slot.player as Player
	_wear(hero, _piece(&"warrior", "head"))
	# Worn: the same shoulders without the set and 15% stronger; offered: the set's shoulders.
	var worn := _piece(&"warrior", "shoulders")
	worn.set_id = &""
	worn.display_name = "Gilded Pauldrons"
	for k in worn.stats:
		worn.stats[k] *= 1.15
	_wear(hero, worn)
	var offered := _piece(&"warrior", "shoulders")
	var current := ItemTooltip.equipped_for_compare(offered, hero.equipment)
	check(current == worn, "compared with the worn shoulders")
	check_eq(ItemTooltip.upgrade_direction(offered, current, slot.class_data), -1, "on its stats alone: worse")
	check_eq(ItemTooltip.upgrade_direction(offered, current, slot.class_data, hero.equipment), 1,
		"completing the 2-piece bonus: an upgrade (what bots Need and buy)")
	var slots := PlayerManager.get_slots()
	var card := ShopOfferCard.create(0)
	_nodes.append(card)
	var o := Shop.Offer.new()
	o.item = offered
	o.price = 50
	card.set_offer(o, slots)
	check_eq(card._usable.get(slot.index, 0), 2, "the stall's pip shows the upgrade arrow")
	var loot := LootRollScreen.create()
	_nodes.append(loot)
	tree.root.add_child(loot)
	loot.open([offered] as Array[ItemInstance], slots)
	check_eq(loot._upgrade_direction(slot), 1, "the loot roll's chip shows it too")


# --- Forged Legendaries ------------------------------------------------------------------------

func test_a_forged_knell_of_stone_rings_every_5th_hit_for_80_percent_of_it() -> void:
	var w := _hero(0, &"warrior")
	var forged := _forge_legendary(w, &"mace")
	if forged == null:
		return
	var target := PFakes.spawn_enemy(world, Vector3(1.2, 0.0, 0.0))
	var near := PFakes.spawn_enemy(world, Vector3(2.7, 0.0, 0.0))  # 1.5 m from the target
	var far := PFakes.spawn_enemy(world, Vector3(1.2, 0.0, 6.0))
	EnemyGrid.mark_dirty()
	w.damage_mults[&"m5_integration"] = 1.5  # an outgoing multiplier: it must apply only once
	var base := 30.0
	for i in 4:
		_hit(w, target, base)
	check_eq(target.fake_hits(), 4, "hits 1-4: the weapon only")
	check_near(target.fake_damage_log[0], base * w.outgoing_damage_mult(target, &"physical", &"weapon"), 0.001,
		"the weapon hit carries the multiplier")
	check_eq(near.fake_hits() + target.fake_stun_count, 0, "nothing rang yet")
	_hit(w, target, base)
	check_eq(target.fake_hits(), 6, "hit 5: the weapon + the toll")
	var share := base * 0.8
	check_near(target.fake_damage_log[5], share * w.outgoing_damage_mult(target, &"physical", &"proc"), 0.001,
		"80% of the hit's base amount (the derived-damage rule)")
	check_eq(near.fake_hits(), 1, "every enemy within 2 m of the target is struck")
	check_near(near.fake_damage_log[0], share * w.outgoing_damage_mult(near, &"physical", &"proc"), 0.001, "for the same share")
	check_eq(far.fake_hits(), 0, "not the ones further away")
	check_eq([target.fake_stun_count, near.fake_stun_count], [1, 1], "and stunned")
	check_eq(w.procs.fire_count(forged.source_id), 1, "fired once")
	for i in 4:
		_hit(w, target, base)
	check_eq(target.fake_hits(), 10, "hits 6-9: the weapon only")
	_hit(w, target, 50.0)
	check_eq(target.fake_hits(), 12, "hit 10 rings again")
	check_near(target.fake_damage_log[11], 40.0 * w.outgoing_damage_mult(target, &"physical", &"proc"), 0.001,
		"80% of that hit")
	check_eq(w.procs.fire_count(forged.source_id), 2, "every 5th hit")


func test_a_forged_pyrewillow_burns_every_4th_bolt_for_120_percent_of_it() -> void:
	var m := _hero(1, &"mage")
	var forged := _forge_legendary(m, &"staff")
	if forged == null:
		return
	var target := PFakes.spawn_enemy(world, Vector3(0.0, 0.0, -4.0))
	EnemyGrid.mark_dirty()
	var base := 25.0
	for i in 3:
		_hit(m, target, base)
	check_eq(m.procs.dot_stacks(target, forged.source_id), 0, "bolts 1-3: no burn")
	_hit(m, target, base)
	check_eq(m.procs.dot_stacks(target, forged.source_id), 1, "bolt 4 sets it ablaze")
	check_eq(target.fake_hits(), 4, "the burn deals nothing up front")
	var t := 0.0
	while t < 4.3:
		m.procs._physics_process(DT)
		t += DT
	check_near(_sum_from(target.fake_damage_log, 4), base * 1.2 * m.outgoing_damage_mult(target, &"fire", &"dot"), 0.01,
		"120% of the hit's base amount over 4 sec")
	check_eq(m.procs.dot_stacks(target, forged.source_id), 0, "then it ends")
	check_eq(m.procs.fire_count(forged.source_id), 1, "one burn for four bolts")


# --- Elite and goblin drops reach the loot roll ------------------------------------------------

func _step_intermission(delta: float = DT) -> void:
	MarketFakes.poll_all(delta)
	screen._process(delta)
	if screen.loot_screen.visible:
		screen.loot_screen._process(delta)


func _tap(input: UiFakes.HumanInput, button: PlayerInput.Pad) -> void:
	input.press(button)
	_step_intermission()
	input.release(button)
	_step_intermission(0.0)


func test_elite_and_goblin_drops_reach_the_loot_roll() -> void:
	RunState.start_run(1, 2025)
	RunState.set_wave(8)
	var input := MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	var hero := PlayerManager.get_slot(0).player as Player
	hero.global_position = Vector3(-8.0, 0.0, 0.0)
	var entities := EFakes.arena_of(world).entities
	var director := WaveDirector.create(EFakes.arena_of(world))
	world.add_child(director)
	RunState.loot_drops_this_wave = LootDrops.max_drops_per_wave()  # only the guaranteed drops
	var elite := Enemy.create(EFakes.enemy_data(), 8)
	elite.make_elite(EliteAffixes.FRENZIED)
	entities.add_child(elite)
	elite.global_position = Vector3(2.0, 0.0, 0.0)
	var goblin := LootGoblin.create(LootGoblin.goblin_data(), 8)
	entities.add_child(goblin)
	goblin.global_position = Vector3(-2.0, 0.0, 3.0)
	_hit(hero, elite, 1.0e6)
	_hit(hero, goblin, 1.0e6)
	check(elite.is_dead() and goblin.is_dead(), "the hero's weapon killed both")
	check_eq([RunState.elites_killed, RunState.goblins_killed], [1, 1], "counted")
	var dropped: Array[ItemInstance] = []
	for node in EFakes.live_children_of_type(world, LootBag):
		dropped.append((node as LootBag).item)
	check_eq(dropped.size(), 2, "one guaranteed bag each")
	for item in dropped:
		check(item.rarity >= Items.Rarity.RARE and item.looted, "%s: a looted Rare+" % item.display_name)
	director.stop()
	check_eq(RunState.team_loot, dropped, "the wave end banks both bags into the team loot")
	screen = Intermission.create()
	tree.root.add_child(screen)
	screen.open(8, 0)
	check_eq(screen.phase, Intermission.Phase.LOOT, "the loot roll opens first")
	check_eq(screen.loot_screen.items, dropped, "with the elite's and the goblin's items")
	check(RunState.team_loot.is_empty(), "taken from the team loot")
	var gold := RunState.gold
	var greed := 0
	for i in dropped.size():
		_step_intermission()
		_step_intermission(LootRollScreen.ITEM_INPUT_DELAY)
		check(screen.loot_screen.roll != null and screen.loot_screen.roll.item == dropped[i], "rolling item %d" % (i + 1))
		_tap(input, PlayerInput.Pad.X)
		greed += dropped[i].greed_value()
		_step_intermission(LootRollScreen.RESULT_TIME + 0.01)
	check_eq(RunState.gold - gold, greed, "both sold into the shared wallet")
	check_eq(screen.phase, Intermission.Phase.MARKET, "then the market")


func test_the_loot_goblin_runs_at_its_walk_speed() -> void:
	EFakes.spawn_player(world, Vector3(-6.0, 0.0, 0.0))
	var g := LootGoblin.create(LootGoblin.goblin_data(), 8)
	EFakes.arena_of(world).entities.add_child(g)
	g.global_position = Vector3.ZERO
	g.speed_mult = 0.5  # a per-enemy speed multiplier (like the elite affixes use)
	EFakes.step(g, 0.6)
	check_near(g.walk_speed(), g.move_speed * 0.5, 0.0001, "walk_speed includes the multiplier")
	check_near(g._move_velocity.length(), g.walk_speed(), 0.05, "the flight steers at walk_speed()")


# --- The spend log covers every spender ---------------------------------------------------------

## Every .gd under [param dir] (recursive).
static func _scripts_in(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		out.append_array(_scripts_in(dir.path_join(sub)))
	return out


func test_every_wallet_spender_goes_through_the_spend_log() -> void:
	var payers: Array[String] = []
	for path in _scripts_in("res://core") + _scripts_in("res://scenes") + _scripts_in("res://autoload"):
		var text := FileAccess.get_file_as_string(path)
		if path == "res://autoload/run_state.gd":
			continue
		check(not text.contains("try_spend("), "%s spends without logging (RunState.try_spend)" % path)
		if text.contains("try_spend_for("):
			payers.append(path)
	payers.sort()
	check_eq(payers, SPENDER_FILES, "the known spenders (a new one: log it and cover it below)")


func test_the_spend_log_covers_every_spender() -> void:
	RunState.start_run(2, 77)
	RunState.set_start_level(12)
	RunState.set_wave(6)
	var s1 := MarketFakes.bot_with_hero(world, "test:a", &"warrior")
	var s2 := MarketFakes.bot_with_hero(world, "test:b", &"paladin")
	var warrior := s1.player as Player
	var paladin := s2.player as Player
	RunState.add_gold(5000)
	var gold := RunState.gold
	var shop := RunState.shop
	var slots := PlayerManager.get_slots()
	var joined: Array[int] = [0, 1]
	shop.open_round(6, slots, RunState.rng)
	var prices: Array[int] = []
	# Shop buy (P1).
	prices.append(shop.offers[0].price)
	check_eq(shop.try_buy(0, s1), Shop.BuyResult.OK, "P1 buys")
	# Stall reroll (the team).
	prices.append(shop.reroll_cost())
	check(not shop.vote_reroll(0, joined, RunState.rng), "P1 votes")
	check(shop.vote_reroll(1, joined, RunState.rng), "P2's vote rerolls")
	# Shop buy that forges (P2: full backpack, the offered mace pairs with the starting mace).
	Support.fill_backpack(s2)
	shop.offers[1].item = ItemInstance.from_weapon(Db.get_weapon(&"mace"))
	shop.offers[1].price = 33
	prices.append(33)
	check_eq(shop.try_buy(1, s2), Shop.BuyResult.FORGED, "P2 buys and forges")
	# Trainer rank (P1).
	prices.append(warrior.abilities.trainer_price(&"whirlwind"))
	check(Trainer.try_buy_rank(warrior, &"whirlwind"), "P1 trains Whirlwind")
	# Talent reset (P1).
	check(warrior.talents.add(&"warrior_fury_cruelty"), "P1 spends a talent point")
	prices.append(warrior.talents.reset_price())
	check(warrior.talents.try_reset(0), "P1 resets")
	# Level-up reroll (P2).
	var panel := LevelUpPanel.create(s2)
	_nodes.append(panel)
	panel.begin(1, 2, 6, RunState.rng)
	prices.append(panel.reroll_price())
	check(panel.try_reroll(), "P2 rerolls the cards")
	# Enchanter action (P1: an Epic ring in the backpack, Dust in the team pile).
	RunState.add_dust(40, 0, "fixture")
	var ring := Support.make_armor(40, ClassData.ArmorType.PLATE, 20, Items.Rarity.EPIC, Items.SlotType.RING)
	ring.enchants.append(EnchantRoll.new(Db.get_enchant(&"mighty"), 0))
	ring.buy_price = ItemGenerator.price_for(Items.Rarity.EPIC, 6)
	warrior.equipment.add_to_backpack(ring)
	prices.append(Enchanter.gold_price(ring))
	check(Enchanter.perform(warrior.equipment, 0, ring, Enchanter.Action.EMPOWER, 0).ok, "P1 empowers a ring")
	# A shrine takes a share of the purse (the team): a tithe of 25%, no items.
	var tithe := ShrineData.new()
	tithe.id = &"tithe"
	tithe.display_name = "Tithe"
	tithe.waves = 0
	tithe.purse_loss_pct = 25.0
	prices.append(floori(RunState.gold * 0.25))
	Shrines.accept(tithe, slots)
	var kinds: Array[StringName] = []
	var who: Array[int] = []
	var amounts: Array[int] = []
	var total := 0
	for e: Dictionary in RunState.spend_log:
		kinds.append(e["kind"])
		who.append(int(e["slot"]))
		amounts.append(int(e["amount"]))
		total += int(e["amount"])
	check_eq(kinds, [&"shop", &"shop_reroll", &"shop_forge", &"trainer", &"talent_reset", &"level_reroll", &"enchant", &"shrine"] as Array[StringName],
		"one entry per spend, in order")
	var sorted_kinds := kinds.duplicate()
	sorted_kinds.sort()
	var expected_kinds := SPEND_KINDS.duplicate()
	expected_kinds.sort()
	check_eq(sorted_kinds, expected_kinds, "every spender kind")
	check_eq(who, [0, -1, 1, 0, 0, 1, 0, -1] as Array[int], "who paid (the reroll and the shrine: the team)")
	check_eq(amounts, prices, "what each cost")
	check_eq(RunState.gold_spent, total, "the run's gold spent")
	check_eq(gold - RunState.gold, total, "is exactly what left the wallet")
	check(paladin.equipment.get_item(Items.EquipSlot.MAIN_HAND).rarity == Items.Rarity.UNCOMMON, "the forge happened")


# --- Talents + sets + items merge in params_for ------------------------------------------------

func test_talent_set_and_item_mods_merge_in_whirlwinds_params() -> void:
	RunState.set_start_level(22)  # 13 talent points
	var w := _hero(0, &"warrior")
	var ww := Db.get_ability(&"whirlwind")
	check(w.abilities.rank_up(&"whirlwind") and w.abilities.rank_up(&"whirlwind"), "Rank III")
	var base := w.abilities.params_for(ww).duplicate()
	check_eq(base["radius"], 4.0, "Rank III: +1 m")
	_add_talents(w, [["warrior_fury_cruelty", 3], ["warrior_fury_unbridled_wrath", 3],
		["warrior_fury_improved_whirlwind", 3], ["warrior_fury_meat_cleaver", 1]])
	for s in ["head", "shoulders", "chest", "legs"]:
		_wear(w, _piece(&"warrior", s))
	_wear(w, _unique(&"gauntlets_of_the_whirling_blade"))
	var p := w.abilities.params_for(ww)
	check_eq(p["cost"], 34.0, "talent: 40 - 3 x 2 Rage")
	check_near(float(p["power"]), float(base["power"]) * 1.15, 0.0001, "talent: +3 x 5% power on top of the rank")
	check_eq(p["rage_per_enemy"], 3.0, "talent (modifier): Meat Cleaver")
	check_eq(p["free_chance"], 30.0, "set: 4-piece free chance")
	check_eq(p["duration"], 2.0, "item: +1 sec")
	check_eq(p["slow"], 30.0, "item: 30% slow")
	check_eq(p["radius"], 4.0, "rank: still Rank III's reach")
	check_eq(p["damage_pct"], base["damage_pct"], "untouched keys stay")
	var ctx := w.abilities.build_context(ww)
	check_eq(w.abilities.cost_of(ww, ctx), 34.0, "the cast pays the merged cost")
	check(ctx.num("free_chance") == 30.0 and ctx.num("duration") == 2.0, "the cast reads the merged params")
	_unwear(w, Items.EquipSlot.HANDS)
	p = w.abilities.params_for(ww)
	check(p["duration"] == 1.0 and p["slow"] == 0.0, "the gauntlets took their mods along")
	check(p["cost"] == 34.0 and p["free_chance"] == 30.0, "the talents and the set stay")
	_unwear(w, Items.EquipSlot.HEAD)
	p = w.abilities.params_for(ww)
	check(not p.has("free_chance") and p["cost"] == 34.0, "3 pieces: the set mod left, the talents stay")
	RunState.add_gold(100)
	check(w.talents.try_reset(0), "reset")
	p = w.abilities.params_for(ww)
	check(p["cost"] == 40.0 and p["power"] == base["power"] and p["rage_per_enemy"] == 0.0, "the talent mods left with the reset")
	check_eq(p["radius"], 4.0, "the rank stays")


func test_item_and_talent_mods_on_the_same_key_add_up() -> void:
	RunState.set_start_level(15)  # 6 talent points
	var m := _hero(1, &"mage")
	var blizzard := Db.get_ability(&"blizzard")
	var radius := float(m.abilities.params_for(blizzard)["radius"])
	_wear(m, _unique(&"frostweave_cowl"))
	check_near(float(m.abilities.params_for(blizzard)["radius"]), radius * 1.3, 0.0001, "item: +30% area")
	_add_talents(m, [["mage_frost_piercing_ice", 3], ["mage_frost_improved_blizzard", 3]])
	check_near(float(m.abilities.params_for(blizzard)["radius"]), radius * 1.39, 0.0001,
		"item 30% + talent 3 x 3%: one +39% (summed, not compounded)")
	check_eq(float(m.abilities.params_for(blizzard)["slow"]), 70.0, "talent: +3 x 10 slow")


# --- Talent reset: refund and log ---------------------------------------------------------------

func test_talent_reset_refunds_every_point_removes_every_effect_and_logs_the_payment() -> void:
	RunState.set_start_level(22)  # 13 talent points
	var w := _hero(2, &"warrior")
	var ww := Db.get_ability(&"whirlwind")
	var rage := w.abilities.get_resource(&"rage")
	var crit := w.stats.get_raw(Stats.CRIT)
	_add_talents(w, [["warrior_fury_cruelty", 3], ["warrior_fury_unbridled_wrath", 3],
		["warrior_fury_improved_whirlwind", 3], ["warrior_fury_blood_craze", 1]])
	check_eq(w.talents.points_free(), 3, "10 of 13 points spent")
	check_eq(w.stats.get_raw(Stats.CRIT), crit + 6.0, "stats: +6% crit")
	check_eq(rage.bonus_of("gain_on_crit"), 9.0, "resource: +9 Rage per crit")
	check_eq(w.abilities.params_for(ww)["cost"], 34.0, "ability: cheaper Whirlwind")
	check_eq(w.procs.extra_defs(PlayerBonuses.SOURCE_TALENTS).size(), 1, "proc: Blood Craze")
	RunState.add_gold(50)
	var gold := RunState.gold
	var price := w.talents.reset_price()
	check_eq(price, TalentState.RESET_BASE_PRICE, "the first reset costs 20 g")
	check(w.talents.try_reset(2), "reset")
	check_eq(w.talents.points_free(), 13, "every point back")
	check(w.talents.ranks.is_empty() and w.talents.pending.is_empty(), "no ranks left")
	check_eq(w.stats.get_raw(Stats.CRIT), crit, "the crit left")
	check_eq(rage.bonus_of("gain_on_crit"), 0.0, "the Rage bonus left")
	check_eq(w.abilities.params_for(ww)["cost"], 40.0, "Whirlwind costs 40 again")
	check(w.procs.extra_defs(PlayerBonuses.SOURCE_TALENTS).is_empty(), "the proc left")
	check(w.bonuses.effects_of(PlayerBonuses.SOURCE_TALENTS).is_empty(), "nothing in the engine")
	check_eq(gold - RunState.gold, price, "paid from the shared wallet")
	check_eq(RunState.spend_log.back(), {"slot": 2, "kind": TalentState.RESET_SPEND_KIND,
		"label": TalentState.RESET_SPEND_LABEL, "amount": price, "wave": RunState.wave}, "logged for P3")
	check_eq(RunState.gold_spent, price, "counted as gold spent")
	check_eq(RunState.talent_resets, 1, "run statistic")
	check_eq(w.talents.reset_price(), 2 * price, "the next one costs twice as much")
	check(w.talents.add(&"warrior_fury_cruelty"), "the refunded points can be spent again")
	check_eq(w.stats.get_raw(Stats.CRIT), crit + 2.0, "and work again")
	RunState.gold = 0
	check(not w.talents.try_reset(2), "no gold: refused")
	check_eq(RunState.spend_log.size(), 1, "a refused reset logs nothing")
	check_eq(w.talents.rank_of(&"warrior_fury_cruelty"), 1, "and changes nothing")
