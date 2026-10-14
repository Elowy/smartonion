extends TestCase
## M6 METER, the model and the screens: RunSummary (awards, rank, best item, class colours,
## formatting, collect), the Game Over / Victory screen (pages, run time, Damage Meter bars), the run
## card (model, file names, saving, the view) and the SMOKE meter. The card's pixels are checked with
## the xvfb screenshot (the headless renderer draws nothing).

const UiFakes := preload("res://tests/ui_fakes.gd")
const CARD_DIR := "user://cards"

var nodes: Array[Node] = []
var main: Main
var _written: Array[String] = []
var _async := false


func is_async() -> bool:
	return _async


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(4, 7)
	tree.paused = false


func after_each() -> void:
	if main != null and is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
	main = null
	for n in nodes:
		UiFakes.free_node(n)
	nodes.clear()
	for path in _written:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_written.clear()
	tree.paused = false
	UiFakes.reset_players()
	RunState.start_run(1, 1)


func _add(node: Node) -> Node:
	UiFakes.add_to_root(tree, node)
	nodes.append(node)
	return node


## A hero entry for RunSummary (every stat 0 unless given).
func _hero(slot: int, stats: Dictionary = {}, alive: bool = true, item: ItemInstance = null,
		class_id: StringName = &"warrior") -> Dictionary:
	var full := {}
	for id in RunSummary.STAT_IDS:
		full[id] = float(stats.get(id, 0.0))
	var data := Db.get_class_data(class_id)
	return {
		"slot": slot, "label": "P%d" % (slot + 1), "color": PlayerManager.PLAYER_COLORS[slot % 4],
		"class_id": class_id, "class_name": data.display_name, "class_color": RunSummary.class_color(data),
		"alive": alive, "best_item": item, "stats": full,
	}


func _item(rarity: int, level: int, price: int = 0, item_name: String = "Thing") -> ItemInstance:
	var item := ItemInstance.new()
	item.rarity = rarity
	item.item_level = level
	item.buy_price = price
	item.display_name = item_name
	return item


func _humans(classes: Array[StringName]) -> Array[UiFakes.HumanInput]:
	var out: Array[UiFakes.HumanInput] = []
	for i in classes.size():
		var input := UiFakes.HumanInput.new("pad:%d" % i)
		PlayerManager.join(input, Db.get_class_data(classes[i]))
		out.append(input)
	return out


func _four_heroes() -> Array:
	return [
		_hero(0, {&"damage": 100, &"absorbed": 5, &"taken": 10, &"kills": 10}),
		_hero(1, {&"damage": 300, &"healing": 50, &"taken": 4, &"revives": 2, &"downs": 1, &"kills": 30}),
		_hero(2, {&"damage": 200, &"healing": 80, &"absorbed": 20, &"taken": 0, &"revives": 1, &"downs": 3,
				&"kills": 20}, false),
		_hero(3, {&"damage": 50, &"healing": 10, &"absorbed": 20, &"taken": 7, &"kills": 5}),
	]


# --- Awards ------------------------------------------------------------------------------------

func test_awards_go_to_the_best_with_ties_to_the_lower_slot() -> void:
	var won := RunSummary.awards_for(_four_heroes())
	check_eq(won.get(1, []), [&"most_damage", &"guardian_angel", &"exterminator", &"untouchable"] as Array,
			"P2: damage, revives, kills and the least damage taken of the heroes still standing")
	check_eq(won.get(2, []), [&"most_healing", &"most_absorbed", &"floor_inspector"] as Array,
			"P3: healing, absorbed (a tie with P4: the lower slot) and the most downs")
	check(not won.has(0) and not won.has(3), "nothing for P1 / P4: %s" % won)


func test_awards_do_not_depend_on_the_order_of_the_heroes() -> void:
	var heroes := _four_heroes()
	heroes.reverse()
	check_eq(RunSummary.awards_for(heroes), RunSummary.awards_for(_four_heroes()), "same winners")
	var tie := [_hero(2, {&"damage": 50}), _hero(0, {&"damage": 50})]
	check_eq(RunSummary.awards_for(tie).get(0, []), [&"most_damage", &"untouchable"] as Array,
			"equal damage: the lower slot (slot 0) wins whichever comes first in the list")


func test_awards_are_co_op_only() -> void:
	check(RunSummary.awards_for([_hero(0, {&"damage": 99, &"kills": 9})]).is_empty(), "a lone hero wins nothing")
	check(RunSummary.awards_for([]).is_empty(), "nobody, nothing")


func test_a_most_award_needs_a_value_above_zero() -> void:
	var won := RunSummary.awards_for([_hero(0), _hero(1)])
	check(not RunSummary.awards_for([_hero(0), _hero(1)]).has(1), "slot 1 won nothing: %s" % won)
	check_eq(won.get(0, []), [&"untouchable"] as Array, "only Untouchable (0 damage taken) exists for slot 0")


func test_untouchable_is_for_the_heroes_standing_at_the_end() -> void:
	var heroes := [_hero(0, {&"taken": 1}, false), _hero(1, {&"taken": 9}), _hero(2, {&"taken": 5}, false)]
	check_eq(RunSummary.awards_for(heroes).get(1, []), [&"untouchable"] as Array,
			"the only survivor wins it although the fallen took less")
	var wiped := [_hero(0, {&"taken": 1}, false), _hero(1, {&"taken": 9}, false)]
	var untouchable := false
	for ids: Array in RunSummary.awards_for(wiped).values():
		untouchable = untouchable or &"untouchable" in ids
	check(not untouchable, "nobody left standing: nobody is untouchable")


func test_build_lists_the_awards_in_order_and_marks_co_op() -> void:
	var run := {"victory": true, "waves_cleared": 25, "total_waves": 25, "time": 754.0}
	var summary := RunSummary.build(run, _four_heroes())
	check_eq(summary["coop"], true, "four heroes: co-op")
	check_eq(summary["time_text"], "12:34", "the run time")
	var ids: Array[StringName] = []
	for a: Dictionary in summary["awards"]:
		ids.append(a["id"])
	check_eq(ids, [&"most_damage", &"most_healing", &"most_absorbed", &"guardian_angel", &"floor_inspector",
			&"exterminator", &"untouchable"] as Array[StringName], "AWARDS order")
	check_eq((summary["heroes"] as Array)[2]["awards"], [&"most_healing", &"most_absorbed", &"floor_inspector"] as Array,
			"the hero entries carry their awards")
	var solo := RunSummary.build(run, [_hero(0, {&"damage": 1})])
	check_eq(solo["coop"], false, "one hero: not co-op")
	check((solo["awards"] as Array).is_empty(), "and no awards")


func test_rank_sorts_by_the_stat_with_ties_to_the_lower_slot() -> void:
	var ranked := RunSummary.rank(_four_heroes(), &"absorbed")
	var slots: Array[int] = []
	for h in ranked:
		slots.append(h["slot"])
	check_eq(slots, [2, 3, 0, 1] as Array[int], "20, 20 (P3 before P4), 5, 0")
	var kills: Array[int] = []
	for h in RunSummary.rank(_four_heroes(), &"kills"):
		kills.append(h["slot"])
	check_eq(kills, [1, 2, 0, 3] as Array[int], "kills")


# --- Best item, colours, formats ----------------------------------------------------------------

func test_best_item_is_the_highest_rarity_then_level_then_price() -> void:
	var eq := Equipment.new(Db.get_class_data(&"warrior"))
	check(RunSummary.best_item(eq) == null, "no items")
	check(RunSummary.best_item(null) == null, "no equipment")
	var rare_low := _item(Items.Rarity.RARE, 10)
	var epic_low := _item(Items.Rarity.EPIC, 5)
	var epic_high := _item(Items.Rarity.EPIC, 30)
	var epic_high_dear := _item(Items.Rarity.EPIC, 30, 200)
	eq.backpack.append(rare_low)
	check(RunSummary.best_item(eq) == rare_low, "the only item")
	eq.backpack.append(epic_low)
	check(RunSummary.best_item(eq) == epic_low, "rarity first")
	eq.backpack.append(epic_high)
	check(RunSummary.best_item(eq) == epic_high, "then the item level")
	eq.backpack.append(epic_high_dear)
	check(RunSummary.best_item(eq) == epic_high_dear, "then the price")
	var twin := _item(Items.Rarity.EPIC, 30, 200)
	eq.backpack.append(twin)
	check(RunSummary.best_item(eq) == epic_high_dear, "the earlier one wins a tie")
	var legendary := _item(Items.Rarity.LEGENDARY, 1)
	eq.slots[Items.EquipSlot.TRINKET_1] = legendary
	check(RunSummary.best_item(eq) == legendary, "worn items count too, and a rarer one beats any level")


func test_class_colours_stay_readable() -> void:
	for id in Db.class_ids:
		var c := RunSummary.class_color(Db.get_class_data(id))
		check(c.get_luminance() >= RunSummary.MIN_CLASS_LUMINANCE - 0.001, "%s is not too dark: %s" % [id, c.get_luminance()])
		check(c.get_luminance() <= RunSummary.MAX_CLASS_LUMINANCE + 0.001, "%s is not too bright: %s" % [id, c.get_luminance()])
	var warlock := Db.get_class_data(&"warlock")
	check(RunSummary.class_color(warlock).get_luminance() > warlock.onion_color.get_luminance(), "the dark warlock is lightened")
	var rogue := Db.get_class_data(&"rogue")
	check(RunSummary.class_color(rogue).get_luminance() < rogue.onion_color.get_luminance(), "the pale rogue is darkened")
	var mage := Db.get_class_data(&"mage")
	check(RunSummary.class_color(mage).is_equal_approx(Color(mage.onion_color, 1.0)), "a mid colour stays as it is")
	check(RunSummary.class_color(null).a == 1.0, "no class: a neutral colour")


func test_the_formatters() -> void:
	check_eq(RunSummary.format_amount(0.0), "0", "zero")
	check_eq(RunSummary.format_amount(999.4), "999", "small")
	check_eq(RunSummary.format_amount(9999.0), "9,999", "below 10k: whole numbers")
	check_eq(RunSummary.format_amount(12345.0), "12.3k", "from 10k: k")
	check_eq(RunSummary.format_amount(1250000.0), "1.25M", "from a million: M")
	check_eq(RunSummary.format_value(&"kills", 12345.0), "12,345", "a count is never shortened")
	check_eq(RunSummary.format_value(&"damage", 12345.0), "12.3k", "an amount is")
	check_eq(RunSummary.format_time(0.0), "0:00", "no time")
	check_eq(RunSummary.format_time(59.6), "1:00", "rounded to the second")
	check_eq(RunSummary.format_time(754.0), "12:34", "minutes")
	check_eq(RunSummary.format_time(3725.0), "1:02:05", "hours")
	check_eq(RunSummary.format_time(-4.0), "0:00", "never negative")
	check_eq(RunSummary.mode_label(&"normal"), "Normal", "mode")
	check_eq(RunSummary.mode_label(&"hardcore"), "Hardcore", "mode")
	check_eq(RunSummary.mode_label(&""), "Normal", "no mode")


# --- Collecting the run -------------------------------------------------------------------------

func test_collect_reads_the_run_state_and_the_slots() -> void:
	_humans([&"warrior", &"mage"] as Array[StringName])
	RunState.set_wave(7)
	RunState.record_kill(0)
	RunState.record_kill(1)
	RunState.record_kill(1)
	RunState.record_damage(1, 500.0)
	RunState.record_heal(0, 40.0)
	RunState.record_absorb(0, 12.0)
	RunState.record_damage_taken(1, 6.0)
	RunState.record_revive(1)
	RunState.record_down(1)
	RunState.record_special_kill(&"boss", 0)
	RunState.tick_run_time(61.0)
	var item := _item(Items.Rarity.EPIC, 20, 0, "Fine Sword")
	RunState.record_hero_result(0, true, item)
	RunState.record_hero_result(1, false)
	var s := RunSummary.collect(false)
	check_eq(s["victory"], false, "defeat")
	check_eq(s["waves_cleared"], 6, "waves cleared")
	check_eq(s["wave"], 7, "reached")
	check_eq(s["time_text"], "1:01", "the run time")
	check_eq(s["kills"], 3, "kills")
	check_eq(s["mode"], "Normal", "mode")
	var heroes: Array = s["heroes"]
	check_eq(heroes.size(), 2, "both heroes")
	check_eq(heroes[0]["class_name"], "Warrior", "class")
	check_eq(heroes[0]["alive"], true, "P1 stood at the end")
	check(heroes[0]["best_item"] == item, "P1's best item (from the hero results)")
	check_eq(heroes[1]["alive"], false, "P2 was down")
	var a: Dictionary = heroes[0]["stats"]
	check_eq(a[&"healing"], 40.0, "healing")
	check_eq(a[&"absorbed"], 12.0, "absorbed")
	check_eq(a[&"kills"], 1.0, "kills")
	check_eq(a[&"bosses"], 1.0, "bosses")
	var b: Dictionary = heroes[1]["stats"]
	check_eq(b[&"damage"], 500.0, "damage")
	check_eq(b[&"taken"], 6.0, "damage taken")
	check_eq(b[&"revives"], 1.0, "revives")
	check_eq(b[&"downs"], 1.0, "downs")
	check_eq(RunSummary.collect(true)["waves_cleared"], 25, "a victory cleared them all")


func test_meter_dict_is_one_entry_per_slot_with_string_keys() -> void:
	_humans([&"warrior", &"paladin"] as Array[StringName])
	RunState.record_heal(1, 12.34)
	RunState.record_revive(1)
	RunState.record_damage(0, 5.0)
	var meter := RunSummary.meter_dict()
	check_eq(meter.keys(), ["0", "1"] as Array, "string keys (JSON)")
	check_eq(meter["1"]["healing"], 12.3, "amounts to 0.1")
	check_eq(meter["1"]["revives"], 1, "counts are whole")
	check_eq(meter["1"]["class"], "paladin", "the class")
	check_eq(meter["0"]["damage"], 5.0, "damage")
	var lines := Main.meter_lines(meter)
	check_eq(lines.size(), 2, "a log line per hero")
	check(lines[1].begins_with("P2 paladin: damage 0.0, healing 12.3,"), "the line: %s" % lines[1])


func test_main_records_the_hero_results_when_the_run_ends() -> void:
	main = Main.create(LaunchOptions.new())
	tree.root.add_child(main)
	for i in 2:
		PlayerManager.add_bot(Db.class_ids[i], i + 1)
	main.start_run()
	main.players[1].take_damage(999.0)
	check(main.players[1].downed, "P2 is down")
	main.end_run(true)
	check_eq(RunState.hero_results.size(), 2, "a result per hero")
	check_eq(RunState.hero_results[0]["alive"], true, "P1 stands")
	check_eq(RunState.hero_results[1]["alive"], false, "P2 does not")
	var item := RunState.hero_results[0]["best_item"] as ItemInstance
	check(item != null and item.is_weapon(), "the best item of a fresh hero is its starting weapon")
	var s := main.smoke_result("completed")
	check(s.has("meter") and (s["meter"] as Dictionary).has("1"), "SMOKE_RESULT has the meter")
	check_eq(s["meter"]["1"]["downs"], 1, "P2's down is in it")


# --- The end screen -----------------------------------------------------------------------------

func _screen() -> GameOverScreen:
	var screen := _add(GameOverScreen.create()) as GameOverScreen
	return screen


func test_the_screen_starts_on_the_summary_and_shows_the_run_time() -> void:
	_humans([&"warrior"] as Array[StringName])
	RunState.tick_run_time(754.0)
	var screen := _screen()
	screen.open(true)
	check_eq(screen.page, GameOverScreen.Page.SUMMARY, "the Summary first")
	check(screen.summary_page.visible and not screen.meter_page.visible, "only the Summary shows")
	check_eq(screen.time_value.text, "12:34", "run time")
	screen.set_page(GameOverScreen.Page.METER)
	screen.open(false)
	check_eq(screen.page, GameOverScreen.Page.SUMMARY, "a new open starts on the Summary again")


func test_lb_rb_and_left_right_turn_the_page_after_the_input_delay() -> void:
	var pads := _humans([&"warrior", &"mage"] as Array[StringName])
	var screen := _screen()
	screen.open(true)
	UiFakes.tap(screen, pads[1], PlayerInput.Pad.RB)
	check_eq(screen.page, GameOverScreen.Page.SUMMARY, "ignored while the screen is new")
	UiFakes.step(screen, GameOverScreen.INPUT_DELAY)
	UiFakes.tap(screen, pads[1], PlayerInput.Pad.RB)
	check_eq(screen.page, GameOverScreen.Page.METER, "RB (any player's pad) -> the Damage Meter")
	UiFakes.tap(screen, pads[0], PlayerInput.Pad.RB)
	check_eq(screen.page, GameOverScreen.Page.METER, "the end does not wrap")
	UiFakes.tap(screen, pads[0], PlayerInput.Pad.LB)
	check_eq(screen.page, GameOverScreen.Page.SUMMARY, "LB -> back")
	UiFakes.tap(screen, pads[0], PlayerInput.Pad.LB)
	check_eq(screen.page, GameOverScreen.Page.SUMMARY, "the start does not wrap either")
	UiFakes.nudge(screen, pads[0], Vector2(1.0, 0.0))
	check_eq(screen.page, GameOverScreen.Page.METER, "stick right")
	UiFakes.nudge(screen, pads[0], Vector2(-1.0, 0.0))
	check_eq(screen.page, GameOverScreen.Page.SUMMARY, "stick left")
	var backs: Array[int] = [0]
	screen.back_to_menu_requested.connect(func() -> void: backs[0] += 1)
	UiFakes.tap(screen, pads[0], PlayerInput.Pad.A)
	check_eq(backs[0], 1, "A still leaves")


func test_a_bots_last_stick_push_does_not_turn_the_page() -> void:
	var bot := PlayerManager.add_bot(&"warrior", 1)
	(bot.input as ScriptedInput).move = Vector2(1.0, 0.0)  # it was running right when the run ended
	var screen := _screen()
	screen.open(true)
	for _i in 90:
		UiFakes.step(screen, 1.0 / 30.0)
	check_eq(screen.page, GameOverScreen.Page.SUMMARY, "bots never page")


func test_a_stick_still_held_when_the_screen_opens_does_not_turn_the_page() -> void:
	var pads := _humans([&"warrior"] as Array[StringName])
	pads[0].move = Vector2(1.0, 0.0)  # steering right when the last enemy fell
	pads[0].poll(1.0 / 60.0)
	var screen := _screen()
	screen.open(true)
	for _i in 120:
		UiFakes.step(screen, 1.0 / 30.0)
	check_eq(screen.page, GameOverScreen.Page.SUMMARY, "the held stick was swallowed")
	pads[0].move = Vector2.ZERO
	UiFakes.step(screen)
	UiFakes.nudge(screen, pads[0], Vector2(1.0, 0.0))
	check_eq(screen.page, GameOverScreen.Page.METER, "a fresh push does turn it")


func test_the_meter_page_has_a_sorted_bar_per_hero_and_stat_in_class_colours() -> void:
	_humans([&"warrior", &"mage", &"rogue"] as Array[StringName])
	RunState.record_damage(0, 100.0)
	RunState.record_damage(1, 300.0)
	RunState.record_damage(2, 12345.0)
	RunState.record_revive(2)
	var screen := _screen()
	screen.open(true)
	var page := screen.meter_page
	check_eq(page.rows.size(), RunSummary.STAT_IDS.size(), "a panel per stat")
	for id in RunSummary.STAT_IDS:
		check_eq(page.rows[id].get_child_count(), 3, "%s: a bar per hero" % id)
	var damage := page.rows[&"damage"]
	var labels: Array[String] = []
	for bar: MeterBar in damage.get_children():
		labels.append(bar.label_text)
	check_eq(labels, ["P3 Rogue", "P2 Mage", "P1 Warrior"] as Array[String], "the best on top")
	var top := damage.get_child(0) as MeterBar
	check_eq(top.value_text, "12.3k", "the value, shortened")
	check_near(top.ratio, 1.0, 0.0001, "the best fills the bar")
	check_near((damage.get_child(2) as MeterBar).ratio, 100.0 / 12345.0, 0.0001, "the others in proportion")
	check(top.fill_color.is_equal_approx(RunSummary.class_color(Db.get_class_data(&"rogue"))), "the class colour")
	check(top.swatch_color.is_equal_approx(PlayerManager.PLAYER_COLORS[2]), "and the player's colour beside it")
	var empty := page.rows[&"absorbed"].get_child(0) as MeterBar
	check(empty.dimmed and empty.fill_width(300.0) == 0.0, "a 0 is an empty, dimmed bar")
	check(top.fill_width(300.0) > (damage.get_child(2) as MeterBar).fill_width(300.0), "longer bars for more")
	check_eq(page.totals[&"damage"].text, "12.7k", "the team total beside the title")
	check_eq(page.totals[&"revives"].text, "1", "a count total")


func test_a_meter_bar_fills_in_proportion_with_a_minimum_and_a_dimmed_zero() -> void:
	var bar := MeterBar.create()
	bar.setup("P1 Warrior", "5", 0.5, Color.RED, Color.BLUE)
	var inner := 300.0 - 2.0 - MeterBar.SWATCH_WIDTH
	check_near(bar.fill_width(300.0), inner * 0.5, 0.001, "half the best value: half the trough")
	bar.setup("P1 Warrior", "1", 0.0001, Color.RED, Color.BLUE)
	check_near(bar.fill_width(300.0), MeterBar.MIN_FILL, 0.001, "a tiny value still shows a sliver")
	bar.setup("P1 Warrior", "0", 0.0, Color.RED, Color.BLUE, true)
	check_eq(bar.fill_width(300.0), 0.0, "nothing: no fill")
	bar.setup("P1 Warrior", "9", 1.0, Color.RED, Color.BLUE, true)
	check_eq(bar.fill_width(300.0), 0.0, "a dimmed bar is never filled")
	bar.setup("P1 Warrior", "9", 7.5, Color.RED, Color.BLUE)
	check_eq(bar.ratio, 1.0, "the ratio is clamped")
	check_near(bar.fill_width(300.0), inner, 0.001, "to the whole trough")
	bar.free()


## Four heroes and every award won (two rows of chips), the largest numbers.
func _record_worst_case_run() -> void:
	_humans([&"warrior", &"mage", &"paladin", &"rogue"] as Array[StringName])
	var dmg := [1250000.0, 480000.0, 210000.0, 330000.0]
	var heal := [2000.0, 91234.0, 15000.0, 0.0]
	var absorb := [0.0, 0.0, 61234.5, 120.0]
	var revives := [1, 2, 4, 0]
	var downs := [2, 0, 1, 5]
	var kills := [900, 2100, 650, 3100]
	for i in 4:
		RunState.record_damage(i, dmg[i])
		RunState.record_heal(i, heal[i])
		RunState.record_absorb(i, absorb[i])
		RunState.record_damage_taken(i, 100.0 * i)
		for _r in revives[i]:
			RunState.record_revive(i)
		for _d in downs[i]:
			RunState.record_down(i)
		for _k in kills[i]:
			RunState.record_kill(i)
	RunState.record_hero_result(0, true)
	RunState.record_hero_result(1, true)
	RunState.record_hero_result(2, true)
	RunState.record_hero_result(3, true)


func test_the_worst_case_meter_page_fits_the_screen() -> void:
	_record_worst_case_run()
	var screen := _screen()
	screen.open(true)
	check_eq(screen.meter_page.awards_grid.get_child_count(), RunSummary.AWARDS.size(), "all seven awards were won")
	for page in GameOverScreen.PAGE_NAMES.size():
		screen.set_page(page as GameOverScreen.Page)
		var need := screen.panel.get_combined_minimum_size()
		check(need.y <= 1080.0 - 40.0, "page %d: the panel needs %s px of the 1080" % [page, need.y])
		check(need.x <= 1920.0 - 40.0, "page %d: and %s px of the 1920 width" % [page, need.x])
	check_eq(screen.panel.get_combined_minimum_size().x, 1140.0, "the panel keeps its width")


func test_awards_show_in_co_op_only() -> void:
	_humans([&"warrior", &"mage"] as Array[StringName])
	RunState.record_damage(1, 50.0)
	RunState.record_kill(1)
	var screen := _screen()
	screen.open(true)
	check(screen.meter_page.awards_grid.visible and screen.meter_page.awards_title.visible, "two heroes: awards")
	var chip := screen.meter_page.awards_grid.get_node_or_null("Award_most_damage")
	check(chip != null, "Most Damage was won")
	check(screen.meter_page.awards_grid.get_node_or_null("Award_most_healing") == null, "Most Healing was not (nobody healed)")
	UiFakes.reset_players()
	_humans([&"warrior"] as Array[StringName])
	screen.open(true)
	check(not screen.meter_page.awards_grid.visible and not screen.meter_page.awards_title.visible, "one hero: no awards")


func test_x_saves_the_card_or_reports_that_it_could_not() -> void:
	_humans([&"warrior"] as Array[StringName])
	var screen := _screen()
	var paths: Array[String] = []
	screen.card_saved.connect(func(p: String) -> void: paths.append(p))
	screen.save_card()  # not opened yet
	check(paths.is_empty(), "a hidden screen saves nothing")
	screen.open(true)
	UiFakes.step(screen, GameOverScreen.INPUT_DELAY)
	if DisplayServer.get_name() == "headless":
		# The dummy renderer draws nothing: the screen says so instead of writing an empty file.
		UiFakes.tap(screen, PlayerManager.get_slot(0).input, PlayerInput.Pad.X)
		check_eq(paths, [""] as Array[String], "X asked for a card, none could be made")
		check(screen.status_label.text.begins_with("The card could not be saved"), "status: %s" % screen.status_label.text)


# --- The run card -------------------------------------------------------------------------------

func _summary_for_card(victory: bool = true) -> Dictionary:
	var heroes := _four_heroes()
	heroes[0]["best_item"] = _item(Items.Rarity.EPIC, 41, 0, "Fine Sword")
	var run := {"victory": victory, "waves_cleared": 25 if victory else 11, "total_waves": 25, "time": 754.0,
			"mode": "Normal", "kills": 123}
	return RunSummary.build(run, heroes)


func test_the_card_model_is_a_pure_function_of_the_summary() -> void:
	var m := RunCard.model(_summary_for_card(true))
	check_eq(m["title"], "SmartOnion", "title")
	check_eq(m["result"], "Victory", "result")
	check_eq(m["victory"], true, "flag")
	check_eq(m["mode"], "Normal", "mode")
	check_eq(m["waves_text"], "25 / 25 waves", "waves")
	check_eq(m["time_text"], "12:34", "time")
	var heroes: Array = m["heroes"]
	check_eq(heroes.size(), 4, "a card per hero")
	var p1: Dictionary = heroes[0]
	check_eq(p1["label"], "P1", "label")
	check_eq(p1["class_name"], "Warrior", "class")
	check_eq(p1["item_name"], "Fine Sword", "best item")
	check_eq(p1["item_rarity"], Items.Rarity.EPIC, "rarity")
	check_eq(p1["item_line"], "Item level 41", "level line")
	check_eq(p1["award"], "", "P1 won nothing")
	check_eq(p1["stat_line"], "Dmg 100", "damage only: a zero healing is left out")
	var p2: Dictionary = heroes[1]
	check_eq(p2["award"], "Most Damage", "P2's first award")
	check_eq(p2["more_awards"], 3, "and three more")
	check_eq(p2["award_line"], "Most Damage +3", "the line")
	check_eq(p2["stat_line"], "Dmg 300   Heal 50", "damage and healing")
	var p3: Dictionary = heroes[2]
	check_eq(p3["alive"], false, "P3 fell")
	check_eq(p3["item_line"], "No gear", "no item")
	check_eq(p3["item_rarity"], -1, "no rarity")
	var defeat := RunCard.model(_summary_for_card(false))
	check_eq(defeat["result"], "Defeat", "defeat")
	check_eq(defeat["waves_text"], "Fell on wave 12", "a defeat names the wave the party fell on")


func test_the_card_shows_at_most_four_heroes() -> void:
	var heroes: Array = _four_heroes()
	heroes.append(_hero(4))
	var summary := RunSummary.build({"victory": true}, heroes)
	check_eq((RunCard.model(summary)["heroes"] as Array).size(), 4, "capped")


func test_card_file_names_and_unique_paths() -> void:
	check_eq(RunCard.file_name({"year": 2026, "month": 10, "day": 4, "hour": 9, "minute": 5, "second": 3}),
			"run_2026-10-04_09-05-03.png", "run_<yyyy-mm-dd_hh-mm-ss>.png")
	var dir := "user://m6_meter_card_test"
	DirAccess.make_dir_recursive_absolute(dir)
	var first := RunCard.unique_path(dir, "run_x.png")
	check_eq(first, dir + "/run_x.png", "free: the plain name")
	var f := FileAccess.open(first, FileAccess.WRITE)
	f.store_string("x")
	f.close()
	_written.append(first)
	var second := RunCard.unique_path(dir, "run_x.png")
	check_eq(second, dir + "/run_x_2.png", "taken: a counter")
	f = FileAccess.open(second, FileAccess.WRITE)
	f.store_string("x")
	f.close()
	_written.append(second)
	check_eq(RunCard.unique_path(dir, "run_x.png"), dir + "/run_x_3.png", "and on")


func test_save_png_writes_a_1200_by_630_file_under_user_cards() -> void:
	var image := Image.create(RunCard.SIZE.x, RunCard.SIZE.y, false, Image.FORMAT_RGB8)
	image.fill(Color(0.2, 0.4, 0.6))
	var when := {"year": 2031, "month": 1, "day": 2, "hour": 3, "minute": 4, "second": 5}
	var path := RunCard.save_png(image, when)
	_written.append(path)
	check_eq(path, CARD_DIR + "/run_2031-01-02_03-04-05.png", "the path")
	check(FileAccess.file_exists(path), "written")
	var back := Image.load_from_file(ProjectSettings.globalize_path(path))
	check(back != null and back.get_size() == Vector2i(1200, 630), "a 1200 x 630 picture")
	var again := RunCard.save_png(image, when)
	_written.append(again)
	check_eq(again, CARD_DIR + "/run_2031-01-02_03-04-05_2.png", "the same second: a second file")
	check_eq(RunCard.save_png(null), "", "no image, no file")
	check_eq(RunCard.save_png(Image.new()), "", "an empty image, no file")


func test_the_view_lays_out_a_card_per_hero_at_1200_by_630() -> void:
	var view := RunCardView.create(RunCard.model(_summary_for_card(true)))
	_add(view)
	check_eq(view.custom_minimum_size, Vector2(1200, 630), "the card size")
	check_eq(view.hero_cards.size(), 4, "a card per hero")
	check_eq(view.result_label.text, "VICTORY", "the headline")
	check(view.find_child("Hero_P2", true, false) != null, "named per hero")
	var lost := RunCardView.create(RunCard.model(_summary_for_card(false)))
	_add(lost)
	check_eq(lost.result_label.text, "DEFEAT", "defeat")
	check(lost.result_label.get_theme_color(&"font_color") != view.result_label.get_theme_color(&"font_color"), "in another colour")


func test_rendering_without_a_renderer_returns_nothing() -> void:
	_async = true
	if DisplayServer.get_name() == "headless":  # a real renderer: the xvfb screenshot covers the pixels
		var host := _add(Control.new())
		var result: Image = await RunCard.render(host, RunCard.model(_summary_for_card(true)))
		check(result == null, "the headless dummy renderer draws nothing")
		check(host.get_child_count() == 0, "and leaves nothing behind")
	await tree.process_frame
	finished.emit()


# --- Fix-ups after the review: page height, status line, prompt, formats, centring, defeat card -----

## Every UiGlyph below [param node].
func _glyphs(node: Node) -> Array[UiGlyph]:
	var out: Array[UiGlyph] = []
	for c in node.get_children():
		if c is UiGlyph:
			out.append(c as UiGlyph)
		out.append_array(_glyphs(c))
	return out


func test_both_pages_make_the_panel_equally_tall_with_seven_awards() -> void:
	_record_worst_case_run()
	var screen := _screen()
	screen.open(true)
	check_eq(screen.meter_page.awards_grid.get_child_count(), 7, "all seven awards: two rows of chips")
	screen.set_page(GameOverScreen.Page.SUMMARY)
	var summary_height := screen.panel.get_combined_minimum_size().y
	screen.set_page(GameOverScreen.Page.METER)
	var meter_height := screen.panel.get_combined_minimum_size().y
	check_near(summary_height, meter_height, 0.5,
			"the panel keeps its height when the page turns (Summary %s, Damage Meter %s)" % [summary_height, meter_height])
	check(meter_height > 900.0, "and it is the tall one: it holds the two award rows (%s)" % meter_height)


func test_the_panel_height_is_equal_on_both_pages_for_every_number_of_awards() -> void:
	for heroes in [1, 2, 3, 4]:
		UiFakes.reset_players()
		RunState.start_run(4, 7)
		var classes: Array[StringName] = [&"warrior", &"mage", &"paladin", &"rogue"]
		_humans(classes.slice(0, heroes))
		for i in heroes:
			RunState.record_damage(i, 100.0 * (i + 1))
			if i % 2 == 0:
				RunState.record_heal(i, 10.0 * (i + 1))
		var screen := _screen()
		screen.open(true)
		screen.set_page(GameOverScreen.Page.SUMMARY)
		var a := screen.panel.get_combined_minimum_size().y
		screen.set_page(GameOverScreen.Page.METER)
		var b := screen.panel.get_combined_minimum_size().y
		check_near(a, b, 0.5, "%d hero(es): Summary %s / Damage Meter %s" % [heroes, a, b])


func test_the_summary_page_is_centred_in_the_page_box() -> void:
	_async = true
	_record_worst_case_run()
	var screen := _screen()
	screen.open(true)
	await tree.process_frame
	await tree.process_frame
	var box := screen.page_box
	var page := screen.summary_page
	var top := page.position.y
	var bottom := box.size.y - page.position.y - page.size.y
	check(box.size.y - page.size.y > 60.0, "the Summary is the shorter page (%s of %s px)" % [page.size.y, box.size.y])
	check(top > 20.0, "there is room above the content (%s px)" % top)
	check_near(top, bottom, 1.0, "as much above (%s px) as below (%s px): no dead block under the table" % [top, bottom])
	finished.emit()


func test_the_page_prompt_shows_the_keyboard_keys_too() -> void:
	var screen := _screen()
	var caps: Array[String] = []
	var navs := 0
	var pills: Array[String] = []
	for g in _glyphs(screen._prompt):
		match g.style:
			UiGlyph.Style.KEY:
				caps.append(g.text)
			UiGlyph.Style.NAV:
				navs += 1
			UiGlyph.Style.PILL:
				pills.append(g.text)
	check("Q" in caps and "E" in caps, "Q / E turn the page: %s" % [caps])
	check("R" in caps and "Enter" in caps, "the other prompts keep their keys: %s" % [caps])
	check_eq(navs, 1, "and the arrows (stick / arrow keys)")
	check("LB" in pills and "RB" in pills, "next to the pad glyphs: %s" % [pills])


func _path_of(length: int) -> String:
	var tail := "/cards/run_2026-10-14_15-20-11.png"
	var head := "C:/Users/"
	var path := head + "n".repeat(length - head.length() - tail.length()) + tail
	check_eq(path.length(), length, "a %d character path" % length)
	return path


func test_a_long_saved_path_is_shortened_to_its_end() -> void:
	var path := _path_of(114)
	var text := GameOverScreen.saved_text(path)
	check(text.length() <= GameOverScreen.MAX_STATUS_CHARS, "at most %d characters (%d)" % [GameOverScreen.MAX_STATUS_CHARS, text.length()])
	check(text.begins_with("Saved to ..."), "it says where the cut is: %s" % text)
	check(text.ends_with("/cards/run_2026-10-14_15-20-11.png"), "folder and file name stay: %s" % text)
	check_eq(text, "Saved to .../cards/run_2026-10-14_15-20-11.png", "cut at a folder boundary, not in the middle of a name")
	check_eq(GameOverScreen.saved_text("/home/me/cards/run_x.png"), "Saved to /home/me/cards/run_x.png", "a short path stays whole")
	var edge := "/".repeat(1) + "a".repeat(GameOverScreen.MAX_STATUS_CHARS - "Saved to ".length() - 1)
	check_eq(GameOverScreen.saved_text(edge), "Saved to " + edge, "exactly as long as fits: whole")


func test_a_114_character_path_does_not_resize_the_panel() -> void:
	_async = true
	_humans([&"warrior", &"mage"] as Array[StringName])
	var screen := _screen()
	screen.open(true)
	await tree.process_frame
	await tree.process_frame
	var before_min := screen.panel.get_combined_minimum_size()
	var before_size := screen.panel.size
	var path := _path_of(114)
	# The line the screen shows after X ...
	screen._set_status(GameOverScreen.saved_text(path), UiTheme.GREEN)
	await tree.process_frame
	await tree.process_frame
	check_eq(screen.panel.get_combined_minimum_size(), before_min, "shortened: the panel needs the same room")
	check_eq(screen.panel.size, before_size, "and keeps its size")
	var font := screen.status_label.get_theme_font(&"font")
	var width := font.get_string_size(screen.status_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			screen.status_label.get_theme_font_size(&"font_size")).x
	check(width <= screen.status_label.size.x, "the whole line fits its label (%s of %s px)" % [width, screen.status_label.size.x])
	# ... and even the unshortened text could not push the panel (the label ends in "...").
	screen._set_status("Saved to " + path, UiTheme.GREEN)
	await tree.process_frame
	await tree.process_frame
	check_eq(screen.panel.get_combined_minimum_size(), before_min, "the unshortened path: still the same room")
	check_eq(screen.panel.size, before_size, "and the same size")
	finished.emit()


func test_a_thousand_k_is_shown_as_a_million() -> void:
	check_eq(RunSummary.format_amount(999960.0), "1.00M", "999,960 would round to 1000.0k")
	check_eq(RunSummary.format_amount(999950.0), "1.00M", "999.95k is 1000.0k at one decimal")
	check_eq(RunSummary.format_amount(999949.0), "999.9k", "just below: still k")
	check_eq(RunSummary.format_amount(1000000.0), "1.00M", "a million")
	check_eq(RunSummary.format_amount(9999.0), "9,999", "nothing else moved")
	check_eq(RunSummary.format_amount(10000.0), "10.0k", "the k starts at 10,000")
	check_eq(RunSummary.format_value(&"damage", 999960.0), "1.00M", "an amount stat")
	check_eq(RunSummary.format_value(&"kills", 999960.0), "999,960", "a count is never shortened")


func test_awards_and_dimmed_bars_go_by_the_value_the_meter_shows() -> void:
	check_eq(RunSummary.shown_value(0.4), 0.0, "0.4 reads 0")
	check_eq(RunSummary.shown_value(0.6), 1.0, "0.6 reads 1")
	var scratch := RunSummary.awards_for([_hero(0, {&"healing": 0.4}), _hero(1, {&"healing": 0.2})])
	var healer := false
	for ids: Array in scratch.values():
		healer = healer or &"most_healing" in ids
	check(not healer, "healing that reads 0 wins no Most Healing: %s" % scratch)
	var real := RunSummary.awards_for([_hero(0, {&"healing": 0.4}), _hero(1, {&"healing": 0.6})])
	check(&"most_healing" in real.get(1, []), "0.6 reads 1: P2 wins it (%s)" % real)
	# The meter dims exactly those bars.
	_humans([&"warrior", &"mage"] as Array[StringName])
	RunState.record_heal(0, 0.4)
	RunState.record_heal(1, 0.6)
	var screen := _screen()
	screen.open(true)
	var bars := screen.meter_page.rows[&"healing"].get_children()
	check_eq((bars[0] as MeterBar).value_text, "1", "P2 first: reads 1")
	check(not (bars[0] as MeterBar).dimmed, "and is not dimmed")
	check_eq((bars[1] as MeterBar).value_text, "0", "P1: reads 0")
	check((bars[1] as MeterBar).dimmed, "and is dimmed like every other 0")
	check(screen.meter_page.awards_grid.get_node_or_null("Award_most_healing") != null, "the award chip is P2's")
	# The run card leaves a "0" out of the hero's line as well.
	var card := RunCard.model(RunSummary.collect(true))
	check_eq((card["heroes"] as Array)[0]["stat_line"], "", "P1: a healing that reads 0 is left out")
	check_eq((card["heroes"] as Array)[1]["stat_line"], "Heal 1", "P2: reads 1")


func test_a_defeat_card_says_on_which_wave_the_party_fell() -> void:
	var run := {"victory": false, "waves_cleared": 6, "wave": 7, "total_waves": 25}
	check_eq(RunCard.model(RunSummary.build(run, _four_heroes()))["waves_text"], "Fell on wave 7", "the wave of the run")
	run.erase("wave")
	check_eq(RunCard.model(RunSummary.build(run, _four_heroes()))["waves_text"], "Fell on wave 7", "or the one after the last cleared")
	run["victory"] = true
	run["waves_cleared"] = 25
	check_eq(RunCard.model(RunSummary.build(run, _four_heroes()))["waves_text"], "25 / 25 waves", "a victory still counts the waves")
	# From the real run: dying on wave 12 is "Fell on wave 12".
	_humans([&"warrior", &"mage"] as Array[StringName])
	RunState.set_wave(12)
	check_eq(RunCard.model(RunSummary.collect(false))["waves_text"], "Fell on wave 12", "collect: the current wave")
	# And the card shows it.
	var view := RunCardView.create(RunCard.model(_summary_for_card(false)))
	_add(view)
	var texts: Array[String] = []
	for l in view.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	check("Fell on wave 12" in texts, "the picture says so: %s" % [texts])
