extends TestCase
## M8 P0 – the companion choice plumbing (no pet content): ClassData.companion_choices, the slot's
## pick (PlayerSlot.companion / companion_id), the lobby card's "Companion: <Name>" row and its RB / E
## button, bots taking the first choice, Player.companion_id, and the --companion / --classes launch
## flags (unknown ids fail fast as "bad_args"). The class with choices is a fixture ("zz_" id).

const Fakes := preload("res://tests/player_fakes.gd")
const UiFakes := preload("res://tests/ui_fakes.gd")
const Rules := preload("res://tests/content_rules.gd")
const ClassFixtures := preload("res://tests/class_fixtures.gd")

var world: Node3D
var lobby: Lobby
var main: Main
var classes := ClassFixtures.new()


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(1, 88)


func after_each() -> void:
	UiFakes.free_node(lobby)
	lobby = null
	if main != null and is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
	main = null
	if world != null:
		Fakes.free_world(world)
		world = null
	UiFakes.reset_players()
	classes.restore()
	Enemy.invalidate_player_cache()
	EnemyGrid.mark_dirty()


# --- Companion plumbing -----------------------------------------------------------------------

func test_a_class_has_companion_choices_only_when_listed() -> void:
	for id in Db.class_ids:
		var cd := Db.get_class_data(id)
		if id in Rules.LAUNCH_CLASSES:
			check(not cd.has_companions(), "%s: no companion" % id)
			check_eq(cd.default_companion(), &"", "%s: default is none" % id)
	var cd := classes.add_class(&"hunter_hat", [&"wolf", &"boar", &"owl"])
	check(cd.has_companions(), "the fixture has three")
	check_eq(cd.default_companion(), &"wolf", "the first is the default")
	check_eq(cd.pick_companion(&"owl"), &"owl", "an offered choice")
	check_eq(cd.pick_companion(&"dragon"), &"wolf", "an unknown one falls back to the first")
	check_eq(cd.pick_companion(&""), &"wolf", "none picked: the first")
	check_eq(ClassData.companion_name(&"wolf"), "Wolf", "the UI name")
	check_eq(Db.companion_ids(), [&"wolf", &"boar", &"owl"] as Array[StringName], "Db lists the offered companions")


func test_the_slot_keeps_a_valid_companion_when_the_class_changes() -> void:
	var cd := classes.add_class(&"hunter_hat", [&"wolf", &"boar", &"owl"])
	var slot := PlayerSlot.new(0, UiFakes.HumanInput.new("pad:a"), Color.WHITE)
	slot.class_data = cd
	check_eq(slot.companion_id(), &"wolf", "default: the first choice")
	check_eq(slot.cycle_companion(1), &"boar", "next")
	check_eq(slot.cycle_companion(1), &"owl", "next")
	check_eq(slot.cycle_companion(1), &"wolf", "wraps")
	check_eq(slot.cycle_companion(-1), &"owl", "back wraps")
	slot.class_data = Db.get_class_data(&"warrior")
	check_eq(slot.companion_id(), &"", "a class without companions has none, whatever was picked")
	check_eq(slot.cycle_companion(1), &"", "and cycling does nothing")
	slot.class_data = cd
	check_eq(slot.companion_id(), &"owl", "back on the companion class the pick is still there")
	slot.companion = &"dragon"
	check_eq(slot.companion_id(), &"wolf", "a pick the class does not offer falls back to the first")


func test_the_lobby_card_shows_the_companion_row_only_for_a_class_with_choices() -> void:
	var cd := classes.add_class(&"hunter_hat", [&"wolf", &"boar", &"owl"])
	lobby = Lobby.create()
	UiFakes.add_to_root(tree, lobby)
	var plain_input := UiFakes.HumanInput.new("pad:a")
	PlayerManager.join(plain_input, Db.get_class_data(&"warrior"))
	var pet_input := UiFakes.HumanInput.new("pad:b")
	var pet_slot := PlayerManager.join(pet_input, cd)
	UiFakes.step(lobby)
	var plain_card := lobby.cards[0]
	var pet_card := lobby.cards[1]
	check(not plain_card._companion_row.visible, "Warrior: no companion row")
	check(pet_card._companion_row.visible, "the companion class has the row")
	check_eq(pet_card._companion_label.text, "Companion: Wolf", "the default, by name")
	check_eq(pet_card._companion_glyph_holder.get_child_count(), 1, "with the button that cycles it")
	# RB cycles for the player who presses it, and only then.
	UiFakes.tap(lobby, pet_input, PlayerInput.Pad.RB)
	check_eq(pet_slot.companion, &"boar", "RB: next companion")
	check_eq(pet_card._companion_label.text, "Companion: Boar", "the card follows")
	UiFakes.tap(lobby, plain_input, PlayerInput.Pad.RB)
	check_eq(PlayerManager.get_slot(0).companion_id(), &"", "RB on a class without choices changes nothing")
	check_eq(pet_slot.companion, &"boar", "and not the other player's pick")
	# The class arrows keep working and the row follows the class.
	pet_slot.class_data = Db.get_class_data(&"mage")
	UiFakes.step(lobby)
	check(not pet_card._companion_row.visible, "another class: the row is gone")
	pet_slot.class_data = cd
	UiFakes.step(lobby)
	check_eq(pet_card._companion_label.text, "Companion: Boar", "and back: the pick is remembered")
	# Ready locks the choice like the class.
	UiFakes.tap(lobby, pet_input, PlayerInput.Pad.A)
	check(pet_slot.ready, "ready")
	UiFakes.tap(lobby, pet_input, PlayerInput.Pad.RB)
	check_eq(pet_slot.companion, &"boar", "RB while ready: locked")
	check_eq(pet_card._companion_glyph_holder.get_child_count(), 0, "and the button prompt is hidden")


func test_bots_take_the_first_companion_and_the_player_gets_the_pick() -> void:
	var cd := classes.add_class(&"hunter_hat", [&"wolf", &"boar", &"owl"])
	var bot := PlayerManager.add_bot(cd.id, 1)
	check_eq(bot.companion_id(), &"wolf", "a bot takes the first choice")
	world = Fakes.make_world(tree)
	var p := Player.create(bot)
	world.add_child(p)
	check_eq(p.companion_id, &"wolf", "it reaches the player")
	PlayerManager.clear()
	var human := PlayerManager.join(UiFakes.HumanInput.new("pad:h"), cd)
	human.companion = &"owl"
	var q := Player.create(human)
	world.add_child(q)
	check_eq(q.companion_id, &"owl", "a lobby pick reaches the player")
	var warrior := Fakes.spawn_player(world, 1, &"warrior")
	check_eq(warrior.companion_id, &"", "a class without companions plays without one")


# --- Launch flags -----------------------------------------------------------------------------

func test_classes_flag_keeps_validating_ids() -> void:
	var ok := LaunchOptions.parse(PackedStringArray(["--smoke", "--classes=warrior,mage"]))
	check(ok.unknown.is_empty(), "known ids pass")
	check_eq(ok.classes, [&"warrior", &"mage"] as Array[StringName], "in join order")
	var bad := LaunchOptions.parse(PackedStringArray(["--smoke", "--classes=warrior,zz_nobody"]))
	check_eq(bad.unknown, ["--classes=warrior,zz_nobody"] as Array[String], "an unknown id is an unknown argument")
	# The M8 ids are refused until their data exists, and accepted once it does.
	var hunter := LaunchOptions.parse(PackedStringArray(["--classes=hunter"]))
	check_eq(hunter.unknown.is_empty(), Db.classes.has(&"hunter"), "hunter: valid exactly when the class exists")
	classes.add_class()
	var fixture := LaunchOptions.parse(PackedStringArray(["--classes=%s,warrior" % ClassFixtures.FAKE_CLASS]))
	check(fixture.unknown.is_empty(), "a class that exists passes")


func test_companion_flag_is_validated_like_classes() -> void:
	var none := LaunchOptions.parse(PackedStringArray(["--smoke"]))
	check_eq(none.companion, &"", "default: each bot takes its class's first")
	var before := LaunchOptions.parse(PackedStringArray(["--companion=wolf"]))
	check_eq(before.unknown.is_empty(), Db.companion_ids().has(&"wolf"), "wolf: valid exactly when some class offers it")
	classes.add_class(&"hunter_hat", [&"wolf", &"boar", &"owl"])
	var owl := LaunchOptions.parse(PackedStringArray(["--smoke", "--companion=owl"]))
	check(owl.unknown.is_empty(), "an offered companion passes")
	check_eq(owl.companion, &"owl", "and is kept")
	var bad := LaunchOptions.parse(PackedStringArray(["--smoke", "--companion=dragon"]))
	check_eq(bad.unknown, ["--companion=dragon"] as Array[String], "an unknown id is an unknown argument (bad_args in a smoke run)")
	check_eq(bad.companion, &"", "and sets nothing")


## A smoke run with an unknown class or companion ends in Main._ready as "bad_args" (exit 1 at once).
func test_a_smoke_run_with_an_unknown_class_or_companion_fails_fast() -> void:
	for bad in ["--classes=zz_nobody", "--companion=dragon"]:
		UiFakes.reset_players()
		var opts := LaunchOptions.parse(PackedStringArray(["--smoke", bad, "--waves=2"]))
		main = Main.create(opts)
		main.quit_app = false
		tree.root.add_child(main)
		check(main._smoke_done, "%s: the smoke finished during _ready" % bad)
		check_eq(main.quit_code, 1, "%s: exit 1" % bad)
		check_eq(main.smoke_outcome("completed"), "bad_args", "%s: bad_args" % bad)
		check_eq(PlayerManager.count(), 0, "%s: no bot joined" % bad)
		main.get_parent().remove_child(main)
		main.free()
		main = null


func test_the_companion_flag_reaches_the_bots_of_a_class_with_choices() -> void:
	var cd := classes.add_class(&"hunter_hat", [&"wolf", &"boar", &"owl"])
	var opts := LaunchOptions.parse(PackedStringArray(["--players=3", "--classes=%s,warrior,%s" % [cd.id, cd.id], "--companion=owl"]))
	check(opts.unknown.is_empty(), "valid flags")
	main = Main.create(opts)
	tree.root.add_child(main)
	main._add_bots()
	check_eq(PlayerManager.count(), 3, "three bots")
	check_eq(PlayerManager.get_slot(0).companion_id(), &"owl", "the class with choices takes the flag")
	check_eq(PlayerManager.get_slot(1).companion_id(), &"", "a class without choices has none")
	check_eq(PlayerManager.get_slot(2).companion_id(), &"owl", "the second one too")
	# Without the flag every bot takes its class's first choice.
	main.options.companion = &""
	main._add_bots()
	check_eq(PlayerManager.get_slot(0).companion_id(), &"wolf", "no flag: the first choice")
	main.start_run()
	var heroes := _players()
	check_eq(heroes.size(), 3, "three heroes")
	for h in heroes:
		check_eq(h.companion_id, h.slot.companion_id(), "%s: the player has its slot's companion" % h.name)


func _players() -> Array[Player]:
	var out: Array[Player] = []
	for n in tree.get_nodes_in_group(&"players"):
		if n is Player:
			out.append(n)
	return out


