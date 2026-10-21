extends TestCase
## M9 PATCH, the lobby's Loadout (LT): the three tabs Seasonings / Heirloom / Look, LB / RB to switch them, the Heirloom
## pick and its slot rules, the Look tab embedding WARDROBE's LookPicker when its script exists (a stand-in here), and the
## fit inside the smallest 1080p lobby card.

const UiFakes := preload("res://tests/ui_fakes.gd")
const FAKE_LOOK := "res://tests/fake_look_picker.gd"

var lobby: Lobby
var _saved_profile: Profile
var _saved_path := ""
var _saved_persist := false
var _saved_look_path := ""
var _nodes: Array[Node] = []
var _async := false
var _root_size := Vector2i.ZERO


func before_each() -> void:
	_saved_profile = Meta.profile
	_saved_path = Meta.path
	_saved_persist = Meta.persist
	_saved_look_path = LoadoutScreen.look_picker_path
	_root_size = tree.root.size
	tree.root.size = Vector2i(1920, 1080)  # (the lobby cards are laid out for the 1080p canvas)
	PlayerManager.clear()
	RunState.start_run(1, 43)


func after_each() -> void:
	for n in _nodes:
		UiFakes.free_node(n)
	_nodes.clear()
	lobby = null
	Meta.profile = _saved_profile
	Meta.path = _saved_path
	Meta.persist = _saved_persist
	LoadoutScreen.look_picker_path = _saved_look_path
	tree.root.size = _root_size
	PlayerManager.clear()
	UiFakes.reset_players()


func is_async() -> bool:
	return _async


# --- Helpers ------------------------------------------------------------------------------------------

## A real profile in memory: [param level] for every class.
func _profile(level: int = 1) -> Profile:
	var p := Profile.fresh()
	for cid in Db.class_ids:
		p.set_class_progress(cid, 0, level)
	Meta.profile = p
	Meta.persist = false
	Meta.path = ""
	return p


func _lobby() -> Lobby:
	lobby = Lobby.create()
	UiFakes.add_to_root(tree, lobby)
	_nodes.append(lobby)
	return lobby


func _join(key: String, class_id: StringName) -> UiFakes.HumanInput:
	var input := UiFakes.HumanInput.new(key)
	PlayerManager.join(input, Db.get_class_data(class_id))
	return input


func _loadout(index: int) -> LoadoutScreen:
	return lobby.loadout_of(PlayerManager.get_slot(index))


# --- The Loadout --------------------------------------------------------------------------------------

func test_lt_opens_the_loadout_on_the_seasonings_tab_and_closes_it_again() -> void:
	_lobby()
	var p1 := _join("p1", &"warrior")
	var p2 := _join("p2", &"mage")
	UiFakes.step(lobby)
	check(not _loadout(0).is_open() and not _loadout(1).is_open(), "closed to begin with")
	UiFakes.tap(lobby, p2, PlayerInput.Pad.LT)
	check(_loadout(1).is_open() and not _loadout(0).is_open(), "P2's LT opens P2's Loadout only")
	check_eq(_loadout(1).tab, LoadoutScreen.Tab.SEASONINGS, "on the Seasonings tab")
	check(lobby.picker_of(PlayerManager.get_slot(1)).is_open(), "the Seasoning picker is the open tab")
	check(_loadout(1).picker.visible and not _loadout(1).heirloom_tab.visible and not _loadout(1).look_holder.visible, "only that tab shows")
	UiFakes.tap(lobby, p1, PlayerInput.Pad.A)
	check(PlayerManager.get_slot(0).ready and not PlayerManager.get_slot(1).ready, "P1 readies up meanwhile, P2's A stays in the Loadout")
	UiFakes.tap(lobby, p2, PlayerInput.Pad.LT)
	check(not _loadout(1).is_open(), "LT closes it")
	check(not lobby.picker_of(PlayerManager.get_slot(1)).is_open(), "and the picker with it")


func test_the_tabs_are_named_and_lb_rb_switch_them() -> void:
	_lobby()
	var p1 := _join("p1", &"warrior")
	UiFakes.step(lobby)
	var loadout := _loadout(0)
	check_eq(LoadoutScreen.TAB_NAMES, ["Seasonings", "Heirloom", "Look"] as Array[String], "the three tabs")
	UiFakes.tap(lobby, p1, PlayerInput.Pad.LT)
	UiFakes.tap(lobby, p1, PlayerInput.Pad.RB)
	check_eq(loadout.tab, LoadoutScreen.Tab.HEIRLOOM, "RB: Heirloom")
	check(loadout.heirloom_tab.visible and not loadout.picker.visible, "that tab shows")
	UiFakes.tap(lobby, p1, PlayerInput.Pad.RB)
	check_eq(loadout.tab, LoadoutScreen.Tab.LOOK, "RB: Look")
	UiFakes.tap(lobby, p1, PlayerInput.Pad.RB)
	check_eq(loadout.tab, LoadoutScreen.Tab.SEASONINGS, "RB wraps to the Seasonings")
	UiFakes.tap(lobby, p1, PlayerInput.Pad.LB)
	check_eq(loadout.tab, LoadoutScreen.Tab.LOOK, "LB wraps back")
	UiFakes.tap(lobby, p1, PlayerInput.Pad.LB)
	check_eq(loadout.tab, LoadoutScreen.Tab.HEIRLOOM, "LB: Heirloom")
	UiFakes.nudge(lobby, p1, Vector2(-1, 0))
	check_eq(loadout.tab, LoadoutScreen.Tab.SEASONINGS, "the stick sideways switches too (the Look tab uses it to change a row)")
	check(loadout.is_open(), "it stays open throughout")
	check(PlayerManager.get_slot(0).class_data.id == &"warrior", "the stick did not change the class")


func test_lb_is_the_alternative_weapon_only_while_the_loadout_is_closed() -> void:
	var p := _profile(12)
	_lobby()
	var p1 := _join("p1", &"warrior")
	var slot := PlayerManager.get_slot(0)
	UiFakes.step(lobby)
	check(not slot.alt_weapon, "standard to begin with")
	UiFakes.tap(lobby, p1, PlayerInput.Pad.LT)
	UiFakes.tap(lobby, p1, PlayerInput.Pad.LB)
	check(not slot.alt_weapon, "LB inside the Loadout switches tabs, not weapons")
	UiFakes.tap(lobby, p1, PlayerInput.Pad.LT)
	check(not _loadout(0).is_open(), "closed")
	UiFakes.tap(lobby, p1, PlayerInput.Pad.LB)
	check(slot.alt_weapon, "LB outside it is the alternative weapon, as before")
	check(p != null, "(a real profile at level 12)")


func test_b_closes_the_loadout_from_every_tab_without_leaving_the_lobby() -> void:
	_lobby()
	var p1 := _join("p1", &"warrior")
	var p2 := _join("p2", &"mage")
	UiFakes.step(lobby)
	for tab_index in 3:
		UiFakes.tap(lobby, p1, PlayerInput.Pad.LT)
		_loadout(0).set_tab(tab_index as LoadoutScreen.Tab)
		check(_loadout(0).is_open(), "open on tab %d" % tab_index)
		UiFakes.tap(lobby, p1, PlayerInput.Pad.B)
		check(not _loadout(0).is_open(), "B closes tab %d" % tab_index)
		check_eq(PlayerManager.count(), 2, "and nobody left")
	check(p2 != null, "(a second player)")


func test_an_open_loadout_takes_every_button_of_its_owner() -> void:
	_lobby()
	var p1 := _join("p1", &"warrior")
	var slot := PlayerManager.get_slot(0)
	UiFakes.step(lobby)
	var mode := lobby.run_mode
	UiFakes.tap(lobby, p1, PlayerInput.Pad.LT)
	_loadout(0).set_tab(LoadoutScreen.Tab.HEIRLOOM)
	for b in [PlayerInput.Pad.Y, PlayerInput.Pad.X, PlayerInput.Pad.START, PlayerInput.Pad.SELECT, PlayerInput.Pad.RT]:
		UiFakes.tap(lobby, p1, b)
	check_eq(lobby.run_mode, mode, "Y does not change the mode")
	check(not lobby.hardcore and not slot.ready, "nor X, nor START")
	check(_loadout(0).is_open(), "the Loadout stays open")


func test_a_ready_player_and_a_locked_class_cannot_open_the_loadout() -> void:
	_profile(1)  # a fresh player: Hunter and Shaman are locked
	_lobby()
	var p1 := _join("p1", &"warrior")
	var slot := PlayerManager.get_slot(0)
	UiFakes.step(lobby)
	slot.ready = true
	UiFakes.tap(lobby, p1, PlayerInput.Pad.LT)
	check(not _loadout(0).is_open(), "the picks are locked while ready")
	check(not lobby.open_loadout(slot), "also through the API")
	slot.ready = false
	slot.class_data = Db.get_class_data(&"hunter")
	check(not lobby.open_loadout(slot), "not for a locked class")
	check(not lobby.open_loadout(null), "no slot, no Loadout")
	check(lobby.open_seasoning_picker(PlayerManager.get_slot(0)) == lobby.open_loadout(PlayerManager.get_slot(0)), "the old entry point agrees")


func test_the_heirloom_tab_picks_and_replaces_the_heirloom() -> void:
	_lobby()
	var p1 := _join("p1", &"mage")
	var slot := PlayerManager.get_slot(0)
	UiFakes.step(lobby)
	UiFakes.tap(lobby, p1, PlayerInput.Pad.LT)
	_loadout(0).set_tab(LoadoutScreen.Tab.HEIRLOOM)
	var tab := _loadout(0).heirloom_tab
	check_eq(tab.entries.size(), 10, "the ten Heirlooms")
	check_eq(tab.rows.size(), 10, "ten rows")
	check_eq(tab.cursor, 0, "at the top")
	UiFakes.nudge(lobby, p1, Vector2(0, 1))
	check_eq(tab.cursor, 1, "▼ moves")
	UiFakes.tap(lobby, p1, PlayerInput.Pad.A)
	check_eq(slot.heirloom, &"heir_old_layers", "A takes the Heirloom under the cursor")
	check_eq(tab.last_result, Heirlooms.RESULT_ADDED, "added")
	check(not slot.ready, "and does not ready the player")
	UiFakes.nudge(lobby, p1, Vector2(0, 1))
	UiFakes.tap(lobby, p1, PlayerInput.Pad.A)
	check_eq(slot.heirloom, &"heir_apron", "another one replaces it (one slot)")
	UiFakes.tap(lobby, p1, PlayerInput.Pad.A)
	check_eq(slot.heirloom, &"", "A on the pick removes it")
	UiFakes.nudge(lobby, p1, Vector2(0, -1))
	UiFakes.nudge(lobby, p1, Vector2(0, -1))
	UiFakes.nudge(lobby, p1, Vector2(0, -1))
	check_eq(tab.cursor, 9, "it wraps to the bottom")
	check_eq(tab.state_of(tab.selected()), "", "the dev profile owns the Peeler")


func test_the_heirloom_tab_shows_locks_and_the_slot_of_a_real_profile() -> void:
	var p := _profile(4)
	p.unlock(Profile.KIND_HEIRLOOM, &"heir_sprout_cap")
	_lobby()
	var p1 := _join("p1", &"mage")
	var slot := PlayerManager.get_slot(0)
	UiFakes.step(lobby)
	UiFakes.tap(lobby, p1, PlayerInput.Pad.LT)
	_loadout(0).set_tab(LoadoutScreen.Tab.HEIRLOOM)
	var tab := _loadout(0).heirloom_tab
	check_eq(tab.state_of(tab.entries[0]), "", "the owned one")
	check_eq(tab.state_of(tab.entries[1]), "Locked", "the others are locked")
	check(tab._note.text.contains("Class Level 5"), "the slot opens at Class Level 5: " + tab._note.text)
	check_eq(tab.activate(), Heirlooms.RESULT_NO_SLOT, "A: no slot yet")
	check_eq(slot.heirloom, &"", "nothing was picked")
	p.set_class_progress(&"mage", 0, 5)
	tab.refresh()
	check_eq(tab.activate(), Heirlooms.RESULT_ADDED, "owned and the slot is open")
	check_eq(p.loadout(&"mage")["heirloom"], &"heir_sprout_cap", "remembered for the class")
	tab.cursor = 3
	check_eq(tab.activate(), Heirlooms.RESULT_LOCKED, "a locked one is refused")
	check(tab._detail_status.text.contains("Locked") and tab._detail_status.text.contains("Reach Hunter level 5"), "with its hint: " + tab._detail_status.text)
	check_eq(slot.heirloom, &"heir_sprout_cap", "the pick stays")


func test_the_look_tab_says_coming_soon_without_wardrobes_picker() -> void:
	LoadoutScreen.look_picker_path = "res://scenes/ui/meta/no_such_look_picker.gd"
	check(not LoadoutScreen.look_picker_available(), "no script")
	_lobby()
	var p1 := _join("p1", &"warrior")
	UiFakes.step(lobby)
	UiFakes.tap(lobby, p1, PlayerInput.Pad.LT)
	_loadout(0).set_tab(LoadoutScreen.Tab.LOOK)
	check(_loadout(0).look_holder.visible and _loadout(0).look_picker == null, "the Look tab shows no picker")
	check(_loadout(0).coming_soon.visible and _loadout(0).coming_soon.text.contains(LoadoutScreen.COMING_SOON_TEXT), "a Coming soon note")
	UiFakes.tap(lobby, p1, PlayerInput.Pad.B)
	check(not _loadout(0).is_open(), "B still closes")


func test_the_look_tab_embeds_the_look_picker_when_the_script_exists() -> void:
	LoadoutScreen.look_picker_path = FAKE_LOOK
	check(LoadoutScreen.look_picker_available(), "the stand-in is found")
	_lobby()
	var p1 := _join("p1", &"warrior")
	var slot := PlayerManager.get_slot(0)
	UiFakes.step(lobby)
	UiFakes.tap(lobby, p1, PlayerInput.Pad.LT)
	var loadout := _loadout(0)
	loadout.set_tab(LoadoutScreen.Tab.LOOK)
	var look := loadout.look_picker
	check(look != null and look.get_parent() == loadout.look_holder, "the picker sits in the Look tab")
	check(look.get("slot") == slot, "made for the hero's slot (LookPicker.create(slot))")
	check(not loadout.coming_soon.visible, "no placeholder")
	UiFakes.tap(lobby, p1, PlayerInput.Pad.A)
	check_eq(look.get("pressed"), [PlayerInput.Pad.A] as Array[int], "the hero's input goes to it")
	check(loadout.is_open(), "still open")
	loadout.set_tab(LoadoutScreen.Tab.HEIRLOOM)
	check(loadout.look_picker == null, "leaving the tab drops the picker")
	loadout.set_tab(LoadoutScreen.Tab.LOOK)
	check(loadout.look_picker != null, "and a new one is made when it comes back")
	UiFakes.tap(lobby, p1, PlayerInput.Pad.B)
	check(not loadout.is_open(), "the picker's closed signal closes the Loadout")


func test_the_real_look_picker_takes_the_stick_and_lt_closes_the_loadout() -> void:
	check(LoadoutScreen.look_picker_available(), "WARDROBE's LookPicker is in the project")
	_lobby()
	var p1 := _join("p1", &"warrior")
	var slot := PlayerManager.get_slot(0)
	UiFakes.step(lobby)
	UiFakes.tap(lobby, p1, PlayerInput.Pad.LT)
	var loadout := _loadout(0)
	loadout.set_tab(LoadoutScreen.Tab.LOOK)
	var look := loadout.look_picker
	check(look is LookPicker and not (look as LookPicker).self_driven, "the Loadout routes the input to it")
	check(not slot.looks.has(&"head"), "worn gear to begin with")
	UiFakes.nudge(lobby, p1, Vector2(1, 0))
	check_eq(loadout.tab, LoadoutScreen.Tab.LOOK, "the stick sideways changes the row, not the tab")
	check(slot.looks.has(&"head"), "the Head row took the next collected look (dev profile: all owned)")
	var picked: StringName = slot.looks.get(&"head", &"")
	UiFakes.nudge(lobby, p1, Vector2(1, 0))
	check(slot.looks.get(&"head", &"") != picked, "one step per nudge (the input is read once)")
	UiFakes.tap(lobby, p1, PlayerInput.Pad.LT)
	check(not loadout.is_open(), "LT closes the Loadout from the Look tab too")
	check_eq(PlayerManager.count(), 1, "and nobody left")


func test_the_loadout_fits_inside_the_smallest_card_on_every_tab() -> void:
	_async = true
	LoadoutScreen.look_picker_path = LoadoutScreen.LOOK_PICKER_PATH  # (the REAL LookPicker on the Look tab, no stand-in)
	_lobby()
	var tallest := 0.0
	var widest := 0.0
	var narrowest_card := INF
	var shortest_card := INF
	var by_tab: Array[float] = [0.0, 0.0, 0.0]
	for cid in Db.class_ids:
		var input := _join("p_%s" % cid, cid)
		UiFakes.step(lobby)
		await tree.process_frame
		await tree.process_frame
		var card := lobby.cards[0]
		var closed := card.get_combined_minimum_size().y
		narrowest_card = minf(narrowest_card, card.size.x)
		shortest_card = minf(shortest_card, card.size.y)
		var slot := PlayerManager.get_slot(0)
		check(lobby.open_loadout(slot), "%s: opens" % cid)
		check_eq(card.get_combined_minimum_size().y, closed, "%s: an open Loadout does not change the card's height" % cid)
		for tab_index in 3:
			_loadout(0).set_tab(tab_index as LoadoutScreen.Tab)
			var here := _loadout(0).get_combined_minimum_size()
			if tab_index == LoadoutScreen.Tab.SEASONINGS:
				for i in _loadout(0).picker.entries.size():
					_loadout(0).picker.cursor = i
					_loadout(0).picker.refresh()
					here = here.max(_loadout(0).get_combined_minimum_size())
			elif tab_index == LoadoutScreen.Tab.HEIRLOOM:
				for i in _loadout(0).heirloom_tab.entries.size():
					_loadout(0).heirloom_tab.cursor = i
					_loadout(0).heirloom_tab.refresh()
					here = here.max(_loadout(0).get_combined_minimum_size())
			else:
				var look := _loadout(0).look_picker
				check(look is LookPicker and (look as LookPicker).is_embedded(), "%s: the Look tab holds the real, embedded LookPicker" % cid)
				var picker := look as LookPicker
				for row_index in LookPicker.ROW_DEFS.size():  # (every row under the cursor, then the choose grid of each)
					picker.row = row_index
					picker.refresh()
					here = here.max(_loadout(0).get_combined_minimum_size())
					picker._begin_list()
					picker.refresh()
					here = here.max(_loadout(0).get_combined_minimum_size())
					picker._end_list(false)
			tallest = maxf(tallest, here.y)
			by_tab[tab_index] = maxf(by_tab[tab_index], here.y)
			widest = maxf(widest, here.x)
			check(here.x <= card.size.x, "%s: tab %s needs %d px, the card is %d px wide" % [cid, LoadoutScreen.TAB_NAMES[tab_index], here.x, card.size.x])
		_loadout(0).close()
		PlayerManager.leave(0)
		check(input != null, "joined")
		UiFakes.step(lobby)
	check(tallest <= shortest_card, "the Loadout (%d px at most; per tab %s) fits inside the smallest card (%d px) at 1080p" % [tallest, by_tab, shortest_card])
	check(widest <= narrowest_card, "and its widest tab (%d px) inside the narrowest card (%d px)" % [widest, narrowest_card])
	finished.emit()


## The Loadout of each of the four players, laid out for real at 1920 x 1080: it stays on its own card (not under, over or past
## the neighbour, P4's not off the screen) on every tab, and the Look tab's rows are inside it, not cut off by its clipping.
func test_the_loadout_of_every_player_stays_on_its_card_and_on_screen() -> void:
	_async = true
	LoadoutScreen.look_picker_path = LoadoutScreen.LOOK_PICKER_PATH
	_lobby()
	var classes: Array[StringName] = [&"warrior", &"mage", &"paladin", &"rogue"]
	for i in classes.size():
		_join("p%d" % i, classes[i])
	UiFakes.step(lobby)
	await tree.process_frame
	await tree.process_frame
	var screen := lobby.get_viewport_rect()
	check_eq(screen.size, Vector2(1920, 1080), "the 1920 x 1080 view")
	for i in classes.size():
		var slot := PlayerManager.get_slot(i)
		var card := lobby.cards[i]
		check(lobby.open_loadout(slot), "P%d: opens" % (i + 1))
		var loadout := _loadout(i)
		for tab_index in 3:
			loadout.set_tab(tab_index as LoadoutScreen.Tab)
			await tree.process_frame
			await tree.process_frame
			var what := "P%d, %s tab" % [i + 1, LoadoutScreen.TAB_NAMES[tab_index]]
			var rect := loadout.get_global_rect()
			check(card.get_global_rect().grow(0.5).encloses(rect), "%s: inside its card %s / %s" % [what, rect, card.get_global_rect()])
			check(screen.encloses(rect), "%s: on screen %s" % [what, rect])
			var needs := loadout.get_combined_minimum_size()
			check(needs.x <= rect.size.x + 0.5 and needs.y <= rect.size.y + 0.5, "%s: needs %s, has %s" % [what, needs, rect.size])
			var bar := loadout._tab_bar.get_global_rect()
			check(rect.grow(0.5).encloses(bar), "%s: the tab bar %s is inside %s" % [what, bar, rect])
			if tab_index == LoadoutScreen.Tab.LOOK:
				var picker := loadout.look_picker as LookPicker
				check(picker != null and picker.is_embedded(), "%s: the embedded LookPicker" % what)
				var picker_rect := picker.get_global_rect()
				check(rect.grow(0.5).encloses(picker_rect), "%s: the picker %s is inside %s" % [what, picker_rect, rect])
				for panel in picker.row_panels:
					check(picker_rect.grow(0.5).encloses(panel.get_global_rect()), "%s: row %s is inside the picker" % [what, panel.name])
				check(not picker._head.visible and picker.custom_minimum_size == Vector2.ZERO, "%s: no title, no minimum size" % what)
				var stage := picker._stage.get_global_rect()  # (the Loadout covers the hero's card: the preview is a banner above the rows)
				check(picker._stage.is_visible_in_tree() and stage.end.y <= picker.row_panels[0].get_global_rect().position.y + 0.5,
						"%s: the preview banner %s is above the rows" % [what, stage])
				check(picker_rect.grow(0.5).encloses(stage), "%s: and inside the picker" % what)
		loadout.close()
		UiFakes.step(lobby)
	finished.emit()


func test_the_loadout_view_flags_pick_the_tab_and_the_player() -> void:
	var o := LaunchOptions.parse(["--view=lobby", "--loadout-tab=look", "--loadout-player=4"])
	check_eq(o.loadout_tab, "look", "the tab")
	check_eq(o.loadout_player, 4, "the player")
	check_eq(LaunchOptions.parse(["--loadout-tab=look"]).loadout_player, 0, "the second player's by default")
	check_eq(LaunchOptions.parse(["--loadout-player=9"]).loadout_player, PlayerManager.MAX_PLAYERS, "at most the fourth")
	check_eq(LaunchOptions.parse(["--loadout-player=0"]).loadout_player, 1, "at least the first")


func test_a_class_change_keeps_what_the_class_can_carry_and_prunes_the_rest() -> void:
	var p := _profile(1)
	p.set_class_progress(&"warrior", 0, 5)
	p.unlock(Profile.KIND_HEIRLOOM, &"heir_apron")
	_lobby()
	var p1 := _join("p1", &"warrior")
	var slot := PlayerManager.get_slot(0)
	UiFakes.step(lobby)
	slot.heirloom = &"heir_apron"
	UiFakes.nudge(lobby, p1, Vector2(1, 0))  # the next class: the Mage has no Heirloom slot yet
	check_eq(slot.class_data.id, &"mage", "the Mage")
	check_eq(slot.heirloom, &"", "the Warrior's pick did not follow")
