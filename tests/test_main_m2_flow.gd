extends TestCase
## Main with the M2 intermission: wave cleared -> loot roll of the team loot (bots) -> market
## -> next wave; smoke / demo bots shop; the item statistics of SMOKE_RESULT.

const UiFakes := preload("res://tests/ui_fakes.gd")
const MarketFakes := preload("res://tests/test_ui_market_fakes.gd")
const DT := 1.0 / 60.0

var main: Main


func before_each() -> void:
	UiFakes.reset_players()
	tree.paused = false


func after_each() -> void:
	if main != null and is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
	main = null
	tree.paused = false
	UiFakes.reset_players()
	Enemy.invalidate_player_cache()


func _make_main(opts: LaunchOptions = null) -> Main:
	main = Main.create(opts if opts != null else LaunchOptions.new())
	tree.root.add_child(main)
	return main


func _run_with_bots(count: int) -> void:
	_make_main()
	for i in count:
		PlayerManager.add_bot(Db.class_ids[i % Db.class_ids.size()], i + 1)
	main.start_run()


func _clear_wave_and_wait() -> void:
	main.wave_director.time_left = 0.0
	main.wave_director._physics_process(DT)
	main._physics_process(Main.WAVE_END_DELAY + 0.01)


## Runs the intermission (and its loot roll) for [param seconds] of frames.
func _run_intermission(seconds: float, step: float = 0.25) -> void:
	var t := 0.0
	while t < seconds and main.intermission.is_open():
		for slot in PlayerManager.get_slots():
			slot.input.poll(step)
		main.intermission._process(step)
		if main.intermission.loot_screen.visible:
			main.intermission.loot_screen._process(step)
		t += step


func test_loot_roll_then_market_then_next_wave() -> void:
	_run_with_bots(2)
	RunState.add_team_loot(MarketFakes.make_item("Looted Charm", Items.SlotType.TRINKET, Items.NO_ARMOR, Items.Rarity.RARE, 50))
	RunState.add_team_loot(MarketFakes.make_weapon(&"sword"))
	check_eq(main.items_looted, 2, "picked-up bags are counted")
	_clear_wave_and_wait()
	check_eq(main.state, Main.State.INTERMISSION, "intermission")
	check_eq(main.intermission.phase, Intermission.Phase.LOOT, "the loot roll comes first")
	check(RunState.team_loot.is_empty(), "the loot roll took the team loot")
	check_eq(main.items_looted, 2, "taking the loot is not a pickup")
	_run_intermission(10.0)
	check_eq(main.loot_rolls, 2, "both items rolled")
	check_eq(main.intermission.phase, Intermission.Phase.MARKET, "then the market")
	check(not main.intermission.is_open(), "the bots are ready")
	main._on_intermission_continue()
	check_eq(main.state, Main.State.WAVE, "next wave")
	check_eq(main.wave, 2, "wave 2")


func test_demo_bots_shop_and_roll_slowly() -> void:
	var opts := LaunchOptions.new()
	opts.demo = true
	opts.players = 2
	opts.seed_value = 4
	_make_main(opts)
	check_eq(main.state, Main.State.WAVE, "demo plays at once")
	check(main.intermission.bot_shopping, "demo bots shop")
	check_eq(main.intermission.bot_market_time, Main.DEMO_MARKET_TIME, "the market stays open a while")
	check_eq(main.intermission.loot_screen.bot_think_time, Main.DEMO_BOT_THINK_TIME, "bots think in the loot roll")


func test_plain_runs_have_no_bot_shopping() -> void:
	_run_with_bots(2)
	check(not main.intermission.bot_shopping, "only smoke / demo")
	check_eq(main.intermission.loot_screen.bot_think_time, 0.0, "instant bot rolls")


func test_smoke_result_has_the_item_statistics() -> void:
	_run_with_bots(2)
	main.intermission.item_bought.emit(0, MarketFakes.make_item("Helm", Items.SlotType.HEAD))
	main.intermission.item_bought.emit(1, MarketFakes.make_item("Robe", Items.SlotType.CHEST))
	RunState.add_team_loot(MarketFakes.make_item("Charm", Items.SlotType.TRINKET))
	RunState.need_wins_by_player[0] = 2
	RunState.need_wins_by_player[1] = 1
	RunState.greed_gold = 37
	var data := main.smoke_result("completed")
	for key in ["result", "waves_completed", "kills", "gold", "errors", "perf", "items_bought", "items_looted", "need_wins", "greed_gold"]:
		check(data.has(key), "SMOKE_RESULT has %s" % key)
	check_eq(data["items_bought"], 2, "bought")
	check_eq(data["items_looted"], 1, "looted")
	check_eq(data["need_wins"], 3, "need wins summed over the players")
	check_eq(data["greed_gold"], 37, "greed gold")
	check_eq(data["result"], "completed", "result")
