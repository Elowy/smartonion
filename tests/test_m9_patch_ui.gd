extends TestCase
## M9 PATCH, The Onion Patch (the main menu's meta page): the menu entry, the header, the five tabs (Classes, Seasonings,
## Heirlooms, Achievements, Wardrobe), purchases that save at once, the title picker, the dev profile of the automated runs,
## the Wardrobe embedding (a stand-in for WARDROBE's WardrobePage), and the pure helpers behind them (achievement progress,
## the Seeds shop of Meta). The lobby's Loadout is test_m9_patch_loadout.

const UiFakes := preload("res://tests/ui_fakes.gd")
const FAKE_WARDROBE := "res://tests/fake_wardrobe_page.gd"

var _saved_profile: Profile
var _saved_path := ""
var _saved_persist := false
var _saved_wardrobe_path := ""
var _nodes: Array[Node] = []
var _files: Array[String] = []


func before_each() -> void:
	_saved_profile = Meta.profile
	_saved_path = Meta.path
	_saved_persist = Meta.persist
	_saved_wardrobe_path = PatchWardrobeTab.wardrobe_page_path
	PlayerManager.clear()
	RunState.start_run(1, 43)


func after_each() -> void:
	for n in _nodes:
		UiFakes.free_node(n)
	_nodes.clear()
	Meta.profile = _saved_profile
	Meta.path = _saved_path
	Meta.persist = _saved_persist
	PatchWardrobeTab.wardrobe_page_path = _saved_wardrobe_path
	for f in _files:
		for suffix in ["", ".tmp", ".bak"]:
			if FileAccess.file_exists(f + suffix):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(f + suffix))
	_files.clear()
	PlayerManager.clear()
	UiFakes.reset_players()


# --- Helpers ------------------------------------------------------------------------------------------

func _file(name: String) -> String:
	var path := "user://test_m9_patch_ui_%s.json" % name
	_files.append(path)
	return path


## A real profile in memory: [param level] for every class.
func _profile(level: int = 1) -> Profile:
	var p := Profile.fresh()
	for cid in Db.class_ids:
		p.set_class_progress(cid, 0, level)
	Meta.profile = p
	Meta.persist = false
	Meta.path = ""
	return p


## A saved profile (a temp file) with Seeds: [method Meta.configure] on a fresh profile.
func _saved(name: String, seeds: int = 0) -> Profile:
	Meta.configure(&"fresh", _file(name), true)
	Meta.profile.earn_seeds(seeds)
	return Meta.profile


func _join(key: String, class_id: StringName) -> UiFakes.HumanInput:
	var input := UiFakes.HumanInput.new(key)
	PlayerManager.join(input, Db.get_class_data(class_id))
	return input


func _page(open_for: PlayerSlot = null) -> OnionPatchPage:
	var page := OnionPatchPage.create()
	UiFakes.add_to_root(tree, page)
	_nodes.append(page)
	page.open(open_for)
	UiFakes.step(page)  # (the press that opened it is skipped)
	return page


func _texts(node: Node) -> String:
	var out := ""
	if node is Label:
		out += (node as Label).text + "\n"
	for c in node.get_children():
		out += _texts(c)
	return out


func _bar_texts(node: Node) -> Array[String]:
	var out: Array[String] = []
	if node is UiBar:
		out.append((node as UiBar).text)
	for c in node.get_children():
		out.append_array(_bar_texts(c))
	return out


# --- The Onion Patch ----------------------------------------------------------------------------------

func test_the_main_menu_opens_the_onion_patch_and_b_closes_it() -> void:
	var menu := MainMenu.create()
	UiFakes.add_to_root(tree, menu)
	_nodes.append(menu)
	menu.onion_patch_button.pressed.emit()
	check(menu.onion_patch_page != null and menu.onion_patch_page.visible, "the button opens the page")
	check(menu.is_page_open() and not menu.title_label.is_visible_in_tree(), "the title steps aside")
	menu.open_settings()
	check(menu.settings_page == null or not menu.settings_page.visible, "one page at a time")
	menu._pads.injected.append(JOY_BUTTON_A)
	menu._process(0.016)
	check(menu.onion_patch_page.visible, "the menu does not react to a controller while the page is up")
	menu.onion_patch_page.close()
	check(not menu.is_page_open() and menu.title_label.is_visible_in_tree(), "closing brings the menu back")
	menu.onion_patch_button.grab_focus()
	menu.activate_focused()
	check(menu.onion_patch_page.visible, "a controller's A on the focused button opens it")
	menu.onion_patch_page.close()


func test_the_page_builds_and_switches_tabs_under_the_dev_profile() -> void:
	check(Meta.is_dev(), "the test runner uses the dev profile")
	var page := _page()
	check_eq(page.tabs.size(), 5, "five tabs")
	check_eq(OnionPatchPage.TAB_NAMES, ["Classes", "Seasonings", "Heirlooms", "Achievements", "Wardrobe"] as Array[String], "named")
	check_eq(page.tab, OnionPatchPage.Tab.CLASSES, "opens on Classes")
	for i in 5:
		check(page.tabs[i].visible == (i == page.tab), "tab %d shows only when selected" % i)
		page.switch_tab(1)
	check_eq(page.tab, OnionPatchPage.Tab.CLASSES, "five steps wrap around")
	page.switch_tab(-1)
	check_eq(page.tab, OnionPatchPage.Tab.WARDROBE, "and backwards")
	for t in range(5):
		page.set_tab(t as OnionPatchPage.Tab)
		check(page.tabs[t].visible and page.current() == page.tabs[t], "set_tab(%d)" % t)
		page._on_nav(Vector2i(0, 1))
		page._on_nav(Vector2i(1, 0))
		page._on_accept()
	page.set_tab(99 as OnionPatchPage.Tab)
	check_eq(page.tab, OnionPatchPage.Tab.WARDROBE, "an unknown tab is ignored")
	check(page.seeds_label.text.contains("0"), "the Seeds wallet: " + page.seeds_label.text)
	check(page.points_label.text.contains("0 points"), "the achievement points: " + page.points_label.text)
	check(page.title_text_label.text.contains("none"), "no title")
	page.close()
	check(not page.visible, "closed")


func test_the_page_is_driven_by_the_slot_that_opened_it() -> void:
	var input := _join("p1", &"warrior")
	var slot := PlayerManager.get_slot(0)
	var page := _page(slot)
	check(page.driver_slot() == slot, "driven by P1")
	UiFakes.tap(page, input, PlayerInput.Pad.RB)
	check_eq(page.tab, OnionPatchPage.Tab.SEASONINGS, "RB: next tab")
	UiFakes.tap(page, input, PlayerInput.Pad.RB)
	UiFakes.tap(page, input, PlayerInput.Pad.LB)
	check_eq(page.tab, OnionPatchPage.Tab.SEASONINGS, "RB then LB")
	var before := page.seasonings_tab.class_index
	UiFakes.nudge(page, input, Vector2(1, 0))
	check_eq(page.seasonings_tab.class_index, before + 1, "the d-pad moves inside the tab (Seasonings: the class)")
	UiFakes.tap(page, input, PlayerInput.Pad.B)
	check(not page.visible, "B closes it")


func test_anyone_can_switch_tabs_with_the_shoulders_before_anyone_has_joined() -> void:
	var page := _page()
	page.pads.injected.append(JOY_BUTTON_RIGHT_SHOULDER)
	page._process(0.016)
	check_eq(page.tab, OnionPatchPage.Tab.SEASONINGS, "any controller's RB")
	page._process(0.016)
	page.pads.injected.append(JOY_BUTTON_LEFT_SHOULDER)
	page._process(0.016)
	check_eq(page.tab, OnionPatchPage.Tab.CLASSES, "LB goes back")
	page.pads.injected.append(JOY_BUTTON_B)
	page._process(0.016)
	check(not page.visible, "B closes it")


func test_the_classes_tab_lists_seven_classes_with_their_progress() -> void:
	var p := _profile(1)
	p.set_class_progress(&"warrior", 310 + 95 + 120 + 150 + 180 + 220 + 270 + 320 + 380 + 440 + 510 + 585 + 665 + 750, 14)
	p.counters[&"best_wave:warrior"] = 25
	p.counters[&"wins:warrior:normal"] = 3
	var page := _page()
	var tab := page.classes_tab
	check_eq(tab.rows.size(), 7, "one row per class")
	var warrior := tab.cells[Db.class_ids.find(&"warrior")]
	check((warrior["level"] as Label).text.contains("14"), "the Class Level: " + (warrior["level"] as Label).text)
	check((warrior["best"] as Label).text.contains("25"), "the best wave")
	check((warrior["next"] as Label).text.contains("Lv 15"), "the next rewards start at the next level: " + (warrior["next"] as Label).text)
	check_eq((warrior["next"] as Label).text.count("\n"), 2, "three of them")
	check((warrior["xp"] as Label).text.contains("XP to level 15"), "the XP to the next level: " + (warrior["xp"] as Label).text)
	check(_texts(warrior["wins"] as Node).contains("3"), "wins per tier")
	var hunter := tab.cells[Db.class_ids.find(&"hunter")]
	check(hunter.has("lock") and (hunter["lock"] as Label).text == Meta.unlock_hint(Profile.KIND_CLASS, &"hunter"), "a locked class shows why")
	check_eq((hunter["level"] as Label).text, "Locked", "and says Locked")
	check_eq(tab.cursor, 0, "the cursor starts on the first")
	page._on_nav(Vector2i(0, 1))
	check_eq(tab.selected_class(), Db.class_ids[1], "▼ moves")
	page._on_nav(Vector2i(0, -1))
	page._on_nav(Vector2i(0, -1))
	check_eq(tab.cursor, 6, "and wraps")


func test_the_classes_tab_flips_the_default_alternative_weapon_and_saves() -> void:
	var p := _saved("alt")
	p.set_class_progress(&"warrior", 0, 12)
	p.set_class_progress(&"mage", 0, 11)
	var page := _page()
	var tab := page.classes_tab
	var saves := Meta.save_count
	check_eq(tab.action_text(), "Alt weapon", "A offers it for a class at level 12")
	page._on_accept()
	check(bool(Meta.remembered_loadout(&"warrior")["alt_weapon"]), "the Warrior now starts with it")
	check_eq(Meta.save_count, saves + 1, "saved at once")
	check(Profile.load_file(Meta.path).loadout(&"warrior")["alt_weapon"], "also on disk")
	page._on_accept()
	check(not bool(Meta.remembered_loadout(&"warrior")["alt_weapon"]), "A again turns it off")
	page._on_nav(Vector2i(0, 1))
	check_eq(tab.action_text(), "", "no A for a class below level 12")
	var saves_now := Meta.save_count
	page._on_accept()
	check_eq(Meta.save_count, saves_now, "and nothing happens")
	check(page.message_label.text.contains("Class Level 12"), "the status line says why: " + page.message_label.text)


func test_the_seasonings_tab_shows_the_state_of_every_seasoning_and_buys_them() -> void:
	var p := _saved("ssn", 100)
	p.set_class_progress(&"warrior", 0, 3)
	var page := _page()
	page.set_tab(OnionPatchPage.Tab.SEASONINGS)
	var tab := page.seasonings_tab
	check_eq(tab.current_class(), &"warrior", "starts on the first class")
	check_eq(tab.entries.size(), 8, "eight Seasonings")
	check_eq(tab.rows.size(), 8, "eight rows")
	check_eq(tab.chips.size(), 7, "seven class chips")
	var s0 := tab.entries[0]
	check_eq(Meta.seasoning_state(s0), &"buyable", "a Tier 1 at Class Level 3 with 100 Seeds: buyable")
	check_eq(Meta.seasoning_state(tab.entries[2]), &"locked", "Tier 2 needs level 6")
	check_eq(Meta.seasoning_lock_reason(tab.entries[2]), "Reach Warrior level 6", "and says so")
	check_eq(Meta.seasoning_lock_reason(tab.entries[7]), "Win a Pungent run with the Warrior", "the achievement tier")
	check_eq(tab.action_text(), "Buy", "A buys")
	var saves := Meta.save_count
	var price := s0.price()
	page._on_accept()
	check_eq(Meta.seeds(), 100 - price, "the price was paid")
	check(Meta.is_unlocked(Profile.KIND_SEASONING, s0.id, &"warrior"), "and it is owned")
	check_eq(Meta.save_count, saves + 1, "saved at once, in one write")
	var disk := Profile.load_file(Meta.path)
	check(disk.has_unlock(Profile.KIND_SEASONING, s0.id) and disk.seeds == 100 - price, "on disk too")
	check(page.message_label.text.contains("Bought"), "the status line: " + page.message_label.text)
	check(page.seeds_label.text.contains(str(100 - price)), "the header shows the new wallet: " + page.seeds_label.text)
	check_eq(Meta.seasoning_state(s0), &"owned", "now owned")
	check_eq(tab.action_text(), "Loadout", "A now manages the class loadout")


func test_buying_without_the_seeds_or_the_level_changes_nothing() -> void:
	var p := _saved("poor", 59)
	p.set_class_progress(&"warrior", 0, 3)
	var page := _page()
	page.set_tab(OnionPatchPage.Tab.SEASONINGS)
	var tab := page.seasonings_tab
	var saves := Meta.save_count
	check_eq(Meta.seasoning_state(tab.entries[0]), &"poor", "59 Seeds for a 60 Seeds Seasoning")
	page._on_accept()
	check_eq(Meta.seeds(), 59, "no Seeds taken")
	check(not Meta.is_unlocked(Profile.KIND_SEASONING, tab.entries[0].id), "not owned")
	check(page.message_label.text.contains("Not enough Seeds"), page.message_label.text)
	page._on_nav(Vector2i(0, 1))
	page._on_nav(Vector2i(0, 1))
	check_eq(Meta.seasoning_state(tab.selected()), &"locked", "a locked one")
	page._on_accept()
	check(page.message_label.text.contains("Reach Warrior level 6"), page.message_label.text)
	check_eq(Meta.save_count, saves, "nothing was written")
	check(not Meta.buy_seasoning(&"ssn_nope"), "an unknown id")
	check(not Meta.buy_seasoning(tab.entries[2].id), "a locked one through the API")


func test_the_class_selector_walks_the_seven_classes() -> void:
	var page := _page()
	page.set_tab(OnionPatchPage.Tab.SEASONINGS)
	var tab := page.seasonings_tab
	var seen: Array[StringName] = []
	for i in 7:
		seen.append(tab.current_class())
		check(tab.entries[0].class_id == tab.current_class(), "the list follows the class")
		page._on_nav(Vector2i(1, 0))
	check_eq(seen, Db.class_ids, "every class in lobby order")
	check_eq(tab.current_class(), &"warrior", "and around")
	page._on_nav(Vector2i(-1, 0))
	check_eq(tab.current_class(), &"shaman", "backwards wraps")
	tab.select_class(&"mage")
	check_eq(tab.current_class(), &"mage", "select_class")
	check_eq(tab.cursor, 0, "the cursor starts at the top")


func test_an_owned_seasoning_goes_into_the_class_loadout_up_to_the_slots() -> void:
	var p := _saved("loadout")
	p.set_class_progress(&"warrior", 0, 3)  # one slot
	for s in Db.seasonings_for_class(&"warrior"):
		p.unlock(Profile.KIND_SEASONING, s.id)
	var page := _page()
	page.set_tab(OnionPatchPage.Tab.SEASONINGS)
	var tab := page.seasonings_tab
	var saves := Meta.save_count
	page._on_accept()
	check_eq(Meta.remembered_loadout(&"warrior")["seasonings"], [tab.entries[0].id] as Array[StringName], "the first goes in")
	check_eq(Meta.save_count, saves + 1, "saved")
	page._on_nav(Vector2i(0, 1))
	page._on_accept()
	check_eq(Meta.remembered_loadout(&"warrior")["seasonings"], [tab.entries[0].id] as Array[StringName], "the one slot is taken")
	check(page.message_label.text.contains("slot"), page.message_label.text)
	page._on_nav(Vector2i(0, -1))
	page._on_accept()
	check(Meta.remembered_loadout(&"warrior")["seasonings"].is_empty(), "A on it again takes it out")
	check_eq(Meta.toggle_default_seasoning(&"ssn_nope"), Seasonings.RESULT_INVALID, "an unknown id")


func test_the_dev_profile_owns_every_seasoning_and_selects_nothing() -> void:
	var page := _page()
	page.set_tab(OnionPatchPage.Tab.SEASONINGS)
	var tab := page.seasonings_tab
	for s in tab.entries:
		check_eq(Meta.seasoning_state(s), &"owned", "%s is owned" % s.id)
	check_eq(tab.action_text(), "", "nothing to do with A")
	var saves := Meta.save_count
	page._on_accept()
	check_eq(Meta.save_count, saves, "no disk IO")
	check(Meta.remembered_loadout(&"warrior")["seasonings"].is_empty(), "nothing selected")
	check_eq(Meta.toggle_default_seasoning(tab.entries[0].id), Seasonings.RESULT_INVALID, "refused")


func test_the_heirlooms_tab_shows_ranks_previews_and_perks() -> void:
	var p := _profile(5)
	p.set_heirloom_rank(&"heir_sprout_cap", 3)
	p.unlock(Profile.KIND_HEIRLOOM, &"heir_apron")
	var page := _page()
	page.set_tab(OnionPatchPage.Tab.HEIRLOOMS)
	var tab := page.heirlooms_tab
	check_eq(tab.rows.size(), 10, "ten rows")
	check_eq(tab.preview_class().id, &"mage", "the preview starts on the gift class (Mage)")
	var text := _texts(tab)
	check(text.contains("Sprout Cap") and text.contains("Wave 1:") and text.contains("Wave 10:") and text.contains("Wave 25:"), "the three preview waves")
	check(text.contains("Rank 3:  +3 Haste") and text.contains("Rank 5:  At the start of every wave"), "both perks")
	check(text.contains("Obtained: Reach Mage level 5"), "how it is obtained")
	check(text.contains("Rank 4  ·  240 Seeds"), "the next rank and its price: " + text)
	check(tab._owned_label.text == "Rank 3 of 5", "the rank")
	var dots := tab._dots_slot.get_node("Dots") as RankDots
	check_eq(dots.rank, 3, "three dots filled")
	page._on_nav(Vector2i(0, 1))
	page._on_nav(Vector2i(0, 1))
	check_eq(tab.selected().id, &"heir_apron", "▼ ▼ to the Apron")
	check_eq(tab.preview_class().id, &"warrior", "the preview follows the gift class")
	page._on_nav(Vector2i(1, 0))
	check_eq(tab.preview_class().id, &"mage", "◀ ▶ changes the class of the preview (the next class)")
	check_eq(tab.action_text(), "Rank up", "A ranks it up")
	for i in 4:
		page._on_nav(Vector2i(0, 1))
	check_eq(tab.selected().id, &"heir_garlic_braid", "to a locked one")
	check(_texts(tab).contains("Not owned yet"), "it says it is not owned")
	check_eq(tab.action_text(), "", "nothing to buy")


func test_ranking_up_in_the_patch_pays_and_saves() -> void:
	var p := _saved("rank", 200)
	p.unlock(Profile.KIND_HEIRLOOM, &"heir_sprout_cap")
	var page := _page()
	page.set_tab(OnionPatchPage.Tab.HEIRLOOMS)
	var saves := Meta.save_count
	page._on_accept()
	check_eq(Meta.heirloom_rank(&"heir_sprout_cap"), 2, "rank 2")
	check_eq(Meta.seeds(), 140, "60 Seeds paid")
	check_eq(Meta.save_count, saves + 1, "one write")
	check(page.message_label.text.contains("rank 2"), page.message_label.text)
	page._on_accept()
	check_eq(Meta.heirloom_rank(&"heir_sprout_cap"), 3, "rank 3")
	check_eq(Meta.seeds(), 20, "120 more")
	page._on_accept()
	check_eq(Meta.heirloom_rank(&"heir_sprout_cap"), 3, "rank 4 costs 240: refused")
	check(page.message_label.text.contains("Not enough Seeds"), page.message_label.text)
	check_eq(Meta.seeds(), 20, "no Seeds taken")
	var disk := Profile.load_file(Meta.path)
	check(disk.heirloom_rank(&"heir_sprout_cap") == 3 and disk.seeds == 20, "the file has it: rank %d, %d Seeds" % [disk.heirloom_rank(&"heir_sprout_cap"), disk.seeds])
	check(page.seeds_label.text.contains("20"), "the header follows: " + page.seeds_label.text)


func test_the_dev_profile_cannot_buy_ranks_but_the_tab_works() -> void:
	var page := _page()
	page.set_tab(OnionPatchPage.Tab.HEIRLOOMS)
	var tab := page.heirlooms_tab
	check_eq(tab.rows.size(), 10, "everything is owned")
	var saves := Meta.save_count
	page._on_accept()
	check_eq(Meta.heirloom_rank(&"heir_sprout_cap"), 1, "still rank 1")
	check_eq(Meta.save_count, saves, "no disk IO")
	check(page.message_label.text.contains("Not enough Seeds"), page.message_label.text)


func test_achievement_progress_reads_the_profile_counters() -> void:
	var p := Profile.fresh()
	var regular := Db.get_achievement(&"ach_regular")
	var progress := AchievementProgress.of(regular, p)
	check(progress["known"] and progress["goal"] == 3 and progress["value"] == 0, "Regular: 0 / 3 runs")
	p.counters[&"runs_long"] = 2
	check_eq(AchievementProgress.of(regular, p)["value"], 2, "two runs")
	p.counters[&"runs_long"] = 9
	check_eq(AchievementProgress.of(regular, p)["value"], 3, "capped at the goal")
	var salt := Db.get_achievement(&"ach_salt_of_earth")
	p.counters[&"total:kills"] = 120
	var kills := AchievementProgress.of(salt, p)
	check(kills["goal"] == 500 and kills["value"] == 120, "500 kills in total: 120")
	var gardens := Db.get_achievement(&"ach_five_gardens")
	p.counters[&"env_wins:forest_ruin"] = 1
	p.counters[&"env_wins:swamp"] = 2
	var g := AchievementProgress.of(gardens, p)
	check(g["known"] and g["goal"] == 5 and g["value"] == 2, "five arenas, two won: %s" % str(g))
	var thirty := Db.get_achievement(&"ach_level_thirty")
	p.set_class_progress(&"mage", 0, 18)
	var lv := AchievementProgress.of(thirty, p)
	check(lv["goal"] == 30 and lv["value"] == 18, "the furthest class counts: %s" % str(lv))
	var untouched := AchievementProgress.of(Db.get_achievement(&"ach_untouched"), p)
	check(not untouched["known"], "a condition decided inside one run has no progress")
	p.unlock_achievement(&"ach_untouched", 1)
	var done := AchievementProgress.of(Db.get_achievement(&"ach_untouched"), p)
	check(done["done"] and done["value"] == done["goal"], "an unlocked one is done")
	check(not AchievementProgress.of(null, p)["known"] and not AchievementProgress.of(regular, null)["known"], "no data, no progress")


func test_the_achievements_tab_lists_forty_with_progress_points_and_rewards() -> void:
	var p := _profile(1)
	p.counters[&"runs_long"] = 2
	p.unlock_achievement(&"ach_green_shoot", 100)
	var page := _page()
	page.set_tab(OnionPatchPage.Tab.ACHIEVEMENTS)
	var tab := page.achievements_tab
	check_eq(tab.rows.size(), 40, "forty achievements")
	check(tab._summary.text.contains("1 of 40"), "the summary: " + tab._summary.text)
	check(tab._summary.text.contains("615"), "of 615 points")
	check_eq(tab.entries[0].points, 5, "sorted by points, the easy ones first")
	var regular_row: PanelContainer = null
	for r in tab.rows:
		if r.name == "Row_ach_regular":
			regular_row = r
	check(regular_row != null, "Regular has a row")
	var text := _texts(regular_row)
	check(text.contains("5 pts"), "its points: " + text)
	check_eq(_bar_texts(regular_row), ["2 / 3"] as Array[String], "its progress bar: 2 of 3 runs")
	var legendary_row: PanelContainer = null
	for r in tab.rows:
		if r.name == "Row_ach_tenth_hour":
			legendary_row = r
	check(_texts(legendary_row).contains("Reward: ???"), "a Legendary reward stays hidden until earned")
	var done_row: PanelContainer = null
	for r in tab.rows:
		if r.name == "Row_ach_green_shoot":
			done_row = r
	check(_texts(done_row).contains("Class unlocked: Hunter"), "a reward line of an earned one")
	page._on_nav(Vector2i(0, 1))
	check_eq(tab.cursor, 1, "▼ moves")
	check(tab._detail.text != "", "the full text of the selected one is shown")
	for i in 5:
		page._on_nav(Vector2i(0, 1))
	check_eq(tab.cursor, 6, "scrolls over the list")


func test_the_title_picker_wears_owned_titles_and_clears_them() -> void:
	var p := _saved("titles")
	p.unlock(Profile.KIND_TITLE, &"title_collector")
	var page := _page()
	page.set_tab(OnionPatchPage.Tab.ACHIEVEMENTS)
	var tab := page.achievements_tab
	page._on_nav(Vector2i(1, 0))
	check_eq(tab.pane, PatchAchievementsTab.Pane.TITLES, "▶ moves to the titles")
	check_eq(tab.selected_title(), &"", "the first row is 'No title'")
	check(tab.title_ids.size() > 10, "all the titles are listed")
	page._on_nav(Vector2i(0, 1))
	check_eq(tab.selected_title(), &"title_collector", "the Collector")
	check_eq(tab.action_text(), "Wear", "A wears it")
	var saves := Meta.save_count
	page._on_accept()
	check_eq(Meta.profile.selected_title, &"title_collector", "worn")
	check_eq(Meta.save_count, saves + 1, "saved at once")
	check(page.title_text_label.text.contains("the Collector"), "the header shows it: " + page.title_text_label.text)
	check_eq(tab.action_text(), "Clear", "A on the worn one clears it")
	page._on_accept()
	check_eq(Meta.profile.selected_title, &"", "cleared")
	page._on_nav(Vector2i(0, 1))
	check_eq(tab.selected_title(), &"title_archivist", "the next one")
	page._on_accept()
	check_eq(Meta.profile.selected_title, &"", "a title that is not owned is refused")
	check(page.message_label.text.contains("not earned"), page.message_label.text)
	page._on_nav(Vector2i(-1, 0))
	check_eq(tab.pane, PatchAchievementsTab.Pane.ACHIEVEMENTS, "◀ goes back to the achievements")
	check(not Meta.select_title(&"title_nope"), "an unknown title")
	check(Meta.select_title(&""), "no title is always allowed")


func test_the_wardrobe_tab_is_a_placeholder_without_the_wardrobe_page() -> void:
	PatchWardrobeTab.wardrobe_page_path = "res://scenes/ui/meta/no_such_wardrobe_page.gd"
	var page := _page()
	page.set_tab(OnionPatchPage.Tab.WARDROBE)
	var tab := page.wardrobe_tab
	check(tab.page == null and tab.placeholder.visible, "the placeholder shows")
	check(tab.placeholder.text.contains(PatchWardrobeTab.PLACEHOLDER_TEXT), tab.placeholder.text)
	page._on_nav(Vector2i(0, 1))
	page._on_accept()
	check(page.visible, "input is harmless")


func test_the_wardrobe_tab_embeds_the_wardrobe_page_when_the_script_exists() -> void:
	PatchWardrobeTab.wardrobe_page_path = FAKE_WARDROBE
	var page := _page()
	var tab := page.wardrobe_tab
	check(tab.page != null and tab.page.get_parent() == tab, "WardrobePage.create() is embedded")
	check(not tab.placeholder.visible, "no placeholder")
	page.set_tab(OnionPatchPage.Tab.WARDROBE)
	check(int(tab.page.get("refreshes")) >= 1, "refreshed when the tab opens")
	page._on_nav(Vector2i(1, 0))
	page._on_accept()
	check_eq(tab.page.get("navs"), [Vector2i(1, 0)] as Array[Vector2i], "navigation reaches it")
	check_eq(tab.page.get("accepts"), 1, "and A")


func test_the_header_follows_seeds_points_and_title() -> void:
	var p := _saved("header", 1234)
	p.unlock_achievement(&"ach_green_shoot", 1)
	p.unlock(Profile.KIND_TITLE, &"title_harvester")
	p.selected_title = &"title_harvester"
	var page := _page()
	check(page.seeds_label.text.contains("1,234"), "Seeds with a separator: " + page.seeds_label.text)
	check(page.points_label.text.contains("5 points"), "points: " + page.points_label.text)
	check(page.title_text_label.text.contains("the Harvester"), "title: " + page.title_text_label.text)
	Meta.earn_seeds(66)
	check(page.seeds_label.text.contains("1,300"), "the wallet follows a change: " + page.seeds_label.text)


func test_every_patch_screen_fits_the_1080p_canvas() -> void:
	var page := _page()
	for t in range(5):
		page.set_tab(t as OnionPatchPage.Tab)
		UiFakes.step(page)
		var size := page.panel.get_combined_minimum_size()
		check(size.y <= 1080.0 and size.x <= 1920.0, "tab %d: the panel (%d x %d) fits 1920 x 1080" % [t, size.x, size.y])
