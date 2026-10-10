extends TestCase
## HUD "Team Loot: N" bag counter (GDD 10.1): follows RunState.team_loot by itself, hidden
## while the team loot is empty.

const UiFakes := preload("res://tests/ui_fakes.gd")
const MarketFakes := preload("res://tests/test_ui_market_fakes.gd")

var hud: Hud


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(2, 3)
	hud = Hud.create()
	tree.root.add_child(hud)


func after_each() -> void:
	UiFakes.free_node(hud)
	hud = null
	RunState.start_run(1, 1)


func test_team_loot_counter_follows_run_state() -> void:
	check(not hud.is_team_loot_visible(), "hidden without loot")
	RunState.add_team_loot(MarketFakes.make_item("Charm", Items.SlotType.TRINKET))
	check(hud.is_team_loot_visible(), "shown after a pickup")
	check_eq(hud.team_loot_label.text, "Team Loot: 1", "one bag")
	RunState.add_team_loot(MarketFakes.make_item("Charm 2", Items.SlotType.TRINKET))
	check_eq(hud.team_loot_label.text, "Team Loot: 2", "two bags")
	hud._process(0.1)
	var taken := RunState.take_team_loot()
	check_eq(taken.size(), 2, "the loot roll takes them")
	check(not hud.is_team_loot_visible(), "hidden again")


func test_counter_starts_from_the_current_loot() -> void:
	RunState.add_team_loot(MarketFakes.make_item("Charm", Items.SlotType.TRINKET))
	var other := Hud.create()
	tree.root.add_child(other)
	check(other.is_team_loot_visible(), "a new HUD shows loot already collected")
	check_eq(other.team_loot_label.text, "Team Loot: 1", "count")
	other.free()
	RunState.take_team_loot()
