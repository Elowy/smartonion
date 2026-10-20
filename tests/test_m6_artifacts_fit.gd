extends TestCase
## M6 ARTIFACTS on the loot roll window: an Artifact's tooltip (735-855 px at its normal width,
## far taller than any other item) is fitted into the room between the title block and the
## player chips (LootRollScreen.tooltip_room: wider first, then the title block collapses – one
## compact line, none –, scaled last) so at 1920 x 1080 with four players the frame stays on screen,
## clear of the "Loot Roll" title (as far as it is shown) and of the chips, and the winner line –
## even a two-line Greed result – stays clear of them; no ordinary item (unique, set piece, random
## drop of wave 25) is scaled because of the title; and the green "Looted" tag an Artifact does
## not earn (its Item Level has no Looted bonus) is hidden in the tooltip and the info row.

const UiFakes := preload("res://tests/ui_fakes.gd")
const MarketFakes := preload("res://tests/test_ui_market_fakes.gd")
## The smallest scale an Artifact tooltip may be shown at in the roll window (about 17 px body
## text at 1920 x 1080). The title block gives way before the tooltip is scaled (compact line, then
## none), so the tallest Artifact (Skull of the Damned) keeps about 0.99.
const READABLE_FIT := 0.85
const VIEW := Rect2(0.0, 0.0, 1920.0, 1080.0)
const TEAM: Array[StringName] = [&"warrior", &"mage", &"paladin", &"rogue"]

var world: Node3D
var screen: LootRollScreen
var inputs: Array[UiFakes.HumanInput] = []
var _root_size := Vector2i.ZERO
var _async := false


func is_async() -> bool:
	return _async


func before_each() -> void:
	_async = false
	UiFakes.reset_players()
	RunState.start_run(4, 12)
	RunState.set_wave(10)
	inputs.clear()
	_root_size = tree.root.size
	tree.root.size = Vector2i(1920, 1080)
	world = MarketFakes.make_world(tree)
	for i in TEAM.size():
		inputs.append(MarketFakes.human_with_hero(world, "pad:%d" % i, TEAM[i]))
	screen = LootRollScreen.create()
	tree.root.add_child(screen)


func after_each() -> void:
	tree.root.size = _root_size
	UiFakes.free_node(screen)
	UiFakes.free_node(world)
	screen = null
	world = null
	inputs.clear()
	UiFakes.reset_players()


func _artifact(class_id: StringName, wave: int = 10) -> ItemInstance:
	return ItemGenerator.generate_artifact(class_id, wave)


## The shipped Artifacts (one per class), one item each.
func _artifacts(wave: int = 10) -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	for data: ArtifactData in Db.artifacts.values():
		out.append(ItemGenerator.from_artifact(data, wave))
	return out


func _open(item: ItemInstance) -> void:
	var items: Array[ItemInstance] = [item]
	screen.open(items, PlayerManager.get_slots())
	await tree.process_frame
	await tree.process_frame


## The global rect of [param c] as drawn (scale included).
static func _drawn(c: Control) -> Rect2:
	return c.get_global_transform() * Rect2(Vector2.ZERO, c.size)


## The bottom edge of the title block as it is shown now (0 when the title is hidden).
func _title_end() -> float:
	if not screen.title_label.is_visible_in_tree():
		return 0.0
	var end := screen.title_label.get_global_rect().end.y
	if screen.subtitle_label.is_visible_in_tree():
		end = maxf(end, screen.subtitle_label.get_global_rect().end.y)
	return end


## The frame is on screen, holds its tooltip, ends above the chips row and covers neither the title
## block (as far as it is shown) nor a chip; [param what] names the case.
func _check_frame(what: String) -> void:
	var frame := screen.frame.get_global_rect()
	var chips := screen.chips_row.get_global_rect()
	check_eq(screen.get_viewport_rect().size, VIEW.size, "%s: the 1920 x 1080 view" % what)
	check(VIEW.encloses(frame), "%s: the frame is on screen %s" % [what, frame])
	check(frame.end.y <= chips.position.y, "%s: the frame ends above the chips (%.1f / %.1f)" % [what, frame.end.y, chips.position.y])
	var tip := _drawn(screen.tooltip)
	check(frame.grow(0.5).encloses(tip), "%s: the tooltip is inside the frame %s / %s" % [what, tip, frame])
	check(screen.name_label.get_global_rect().position.y >= frame.position.y, "%s: the item name is inside the frame" % what)
	var title_end := _title_end()
	check(frame.position.y >= title_end, "%s: the frame starts below the title block (%.1f / %.1f)" % [what, frame.position.y, title_end])
	for label: Label in [screen.title_label, screen.subtitle_label]:
		if label.is_visible_in_tree():
			check(not frame.intersects(label.get_global_rect()), "%s: the frame does not cover '%s'" % [what, label.text])
	for chip: Control in screen.chips_row.get_children():
		check(not frame.intersects(chip.get_global_rect()), "%s: the frame does not cover a player chip" % what)


func test_every_artifact_fits_the_roll_window_while_choosing() -> void:
	_async = true
	var seen := 0
	for item in _artifacts():
		await _open(item)
		var what := item.display_name
		check_eq(screen.phase, LootRollScreen.Phase.CHOOSING, "%s: waiting for the players" % what)
		_check_frame(what)
		check(screen.tooltip_fit >= READABLE_FIT, "%s: readable scale %.3f (tooltip %.0f px tall, room %.0f)"
				% [what, screen.tooltip_fit, screen.tooltip.size.y, screen.tooltip_room()])
		check(screen.timer_bar.get_global_rect().end.y <= screen.chips_row.get_global_rect().position.y, "%s: the timer bar is clear of the chips" % what)
		seen += 1
	check_eq(seen, Db.artifacts.size(), "every Artifact (one per class)")
	finished.emit()


## A Greed result is the longest winner line ("[Skull of the Damned] sold for 775 g (P2 won the
## Greed roll)" wraps to two lines): the frame grows when it replaces the timer bar and still
## clears the chips.
func test_every_artifact_fits_the_roll_window_with_a_two_line_greed_result() -> void:
	_async = true
	var wraps := 0
	for item in _artifacts():
		await _open(item)
		var what := item.display_name
		var slots := PlayerManager.get_slots()
		for s in slots:
			screen._choose(s, LootRoll.Choice.GREED if s.index == 2 else LootRoll.Choice.PASS)
		screen._process(0.0)
		check_eq(screen.phase, LootRollScreen.Phase.RESULT, "%s: resolved" % what)
		await tree.process_frame
		await tree.process_frame
		check(screen.result_label.visible and "sold for" in screen.result_label.text, "%s: the Greed result shows" % what)
		_check_frame(what + " (result)")
		var result := screen.result_label.get_global_rect()
		var chips := screen.chips_row.get_global_rect()
		check(result.end.y <= chips.position.y, "%s: the winner line is clear of the chips (%.1f / %.1f)" % [what, result.end.y, chips.position.y])
		check(screen.frame.get_global_rect().grow(0.5).encloses(result), "%s: the winner line is inside the frame" % what)
		if result.size.y > 60.0:
			wraps += 1
	check(wraps >= 1, "(at least one Greed line really wrapped to two lines: %d)" % wraps)
	finished.emit()


func test_a_need_result_of_every_artifact_is_clear_of_the_chips() -> void:
	_async = true
	for item in _artifacts():
		await _open(item)
		var what := item.display_name
		var slots := PlayerManager.get_slots()
		for s in slots:
			screen._choose(s, LootRoll.Choice.PASS)
		screen._process(0.0)
		await tree.process_frame
		await tree.process_frame
		_check_frame(what + " (everyone passed)")
		check(screen.result_label.get_global_rect().end.y <= screen.chips_row.get_global_rect().position.y, "%s: the winner line is clear of the chips" % what)
	finished.emit()


## A tall tooltip is made wider before it is scaled: an Artifact in the roll window is wider than
## the normal tooltip, and the frame grows with it (what is drawn fits the frame's inside).
func test_a_tall_tooltip_widens_before_it_shrinks() -> void:
	_async = true
	var widened := 0
	for item in _artifacts():
		await _open(item)
		var what := item.display_name
		check(screen.tooltip.size.x > ItemTooltip.WIDTH, "%s: wider than the normal tooltip (%.0f)" % [what, screen.tooltip.size.x])
		var drawn_w := _drawn(screen.tooltip).size.x
		check(drawn_w <= screen.frame.size.x - 2.0 * 26.0 + 0.5, "%s: not wider than the frame's inside (%.0f drawn)" % [what, drawn_w])
		if screen.tooltip.size.x > ItemTooltip.WIDTH:
			widened += 1
	check_eq(widened, Db.artifacts.size(), "every Artifact widened")
	finished.emit()


func test_an_ordinary_item_keeps_the_normal_tooltip() -> void:
	_async = true
	var neck := MarketFakes.make_item("Stormcaller", Items.SlotType.NECK, Items.NO_ARMOR, Items.Rarity.RARE, 40)
	await _open(neck)
	check_eq(screen.tooltip_fit, 1.0, "no scaling")
	check_eq(screen.tooltip.size.x, ItemTooltip.WIDTH, "the normal width")
	check_near(screen.tooltip.scale.y, 1.0, 0.0001, "drawn at full size")
	_check_frame("Stormcaller")
	finished.emit()


## Every item a wave-25 run can show that is not an Artifact: the 63 hand-made items (uniques, set
## pieces, trinkets) and generated loot drops of every rarity from Rare up (LOOT / ELITE / BOSS
## sources, the party's classes) – none is shown smaller than it is because of the title block:
## the tooltip keeps its full scale, the title stays readable (at least as the compact line), the
## frame stays clear of the title and the chips.
func test_no_ordinary_wave_25_item_is_scaled_or_loses_its_title() -> void:
	_async = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var items: Array[ItemInstance] = []
	for unique: UniqueItemData in Db.uniques.values():
		var cls_id := unique.class_restriction if unique.class_restriction != &"" else &"warrior"
		items.append(ItemGenerator.from_unique(unique, 25, true, rng, Db.get_class_data(cls_id)))
	var hand_made := items.size()
	check(hand_made >= 60, "uniques and set pieces: %d" % hand_made)
	items.append_array(_wave_25_drops(rng, 40))
	check_eq(items.size(), hand_made + 3 * 40, "generated drops: Rare, Epic and Legendary")
	var by_mode: Dictionary[int, int] = {}
	var scaled := 0
	var min_fit := 1.0
	for item in items:
		await _open(item)
		var what := "%s (%s)" % [item.display_name, item.rarity_name()]
		_check_frame(what)
		by_mode[screen.title_mode] = by_mode.get(screen.title_mode, 0) + 1
		min_fit = minf(min_fit, screen.tooltip_fit)
		if screen.tooltip_fit < 1.0:
			scaled += 1
		check_eq(screen.tooltip_fit, 1.0, "%s: not scaled (tooltip %.0f px, room %.0f)" % [what, screen.tooltip.size.y, screen.tooltip_room()])
		check(screen.title_mode != LootRollScreen.TitleMode.HIDDEN and screen.title_label.is_visible_in_tree(),
				"%s: the title stays readable (mode %d)" % [what, screen.title_mode])
		check_eq(screen.title_label.text, "Loot Roll", "%s: the party title" % what)
	check_eq(scaled, 0, "none of %d items scaled (min %.3f)" % [items.size(), min_fit])
	check(by_mode.get(LootRollScreen.TitleMode.FULL, 0) > 0, "(most items keep the full title: %s)" % by_mode)
	check(by_mode.get(LootRollScreen.TitleMode.COMPACT, 0) > 0, "(the tall ones – set pieces – use the compact line: %s)" % by_mode)
	finished.emit()


## [param per_rarity] generated drops of wave 25 for each of Rare, Epic and Legendary, from the
## LOOT / ELITE / BOSS sources in turn for the four heroes of the party in turn.
func _wave_25_drops(rng: RandomNumberGenerator, per_rarity: int) -> Array[ItemInstance]:
	var team: Array[ClassData] = []
	for class_id in TEAM:
		team.append(Db.get_class_data(class_id))
	var sources: Array[ItemGenerator.Source] = [ItemGenerator.Source.LOOT, ItemGenerator.Source.ELITE, ItemGenerator.Source.BOSS]
	var out: Array[ItemInstance] = []
	for rarity: int in [Items.Rarity.RARE, Items.Rarity.EPIC, Items.Rarity.LEGENDARY]:
		for i in per_rarity:
			var drop := ItemGenerator.generate(sources[i % sources.size()], 25, rng,
					{&"rarity": rarity, &"class_data": team[i % team.size()], &"team_classes": team})
			if drop != null:
				out.append(drop)
	return out


func test_the_room_comes_from_the_screen_height() -> void:
	_async = true
	await _open(_artifact(&"warrior"))
	var normal := screen.tooltip_room()
	# 1080 high: the frame fills the band between the title block and the chips, less its own chrome
	# and the result reserve.
	check(normal > 400.0 and normal < 700.0, "room %.0f at 1080 high" % normal)
	screen.size = Vector2(1920.0, 1380.0)
	check(screen.tooltip_room() > normal + 200.0, "a taller screen gives more room (%.0f)" % screen.tooltip_room())
	finished.emit()


# --- The frame stays below the title block ----------------------------------------------------

## "Loot Roll" and its subtitle are centred above the frame, which is as wide as they are: a tall
## tooltip (every Artifact) must not push the frame up over them. The title block gives way first
## (LootRollScreen.title_mode: the compact line, then none) and what is still shown stays uncovered.
func test_the_frame_stays_clear_of_the_title_block_for_every_artifact() -> void:
	_async = true
	var seen := 0
	for item in _artifacts():
		await _open(item)
		var what := item.display_name
		check_eq(screen.slots.size(), 4, "%s: four players" % what)
		check_eq(screen.title_label.text, "Loot Roll", "%s: the party title" % what)
		var frame := screen.frame.get_global_rect()
		var title_end := _title_end()
		if screen.title_mode == LootRollScreen.TitleMode.HIDDEN:
			check(not screen.title_label.is_visible_in_tree() and not screen.subtitle_label.is_visible_in_tree(), "%s: nothing of the title block shows" % what)
		else:
			check(title_end > 40.0, "%s: the title block is really measured (ends at %.1f)" % [what, title_end])
			check(frame.position.y >= title_end + LootRollScreen.FRAME_TITLE_GAP - 0.5,
					"%s: frame top %.1f is clear of the title block (%.1f + gap)" % [what, frame.position.y, title_end])
		var tip := _drawn(screen.tooltip)
		check(tip.position.y >= title_end, "%s: so is the tooltip (%.1f)" % [what, tip.position.y])
		check(frame.end.y <= screen.chips_row.get_global_rect().position.y - LootRollScreen.FRAME_CHIPS_GAP + 0.5,
				"%s: and the chips still have their gap (%.1f)" % [what, frame.end.y])
		seen += 1
	check_eq(seen, Db.artifacts.size(), "every Artifact (one per class)")
	finished.emit()


## Artifacts of wave 10 and wave 25 (their Item Level and stats differ): at least READABLE_FIT, and
## the tooltip is scaled only once nothing is left of the title block to give up.
func test_an_artifact_is_scaled_only_after_the_title_block_is_gone() -> void:
	_async = true
	var min_fit := 1.0
	for wave in [10, 25]:
		for item in _artifacts(wave):
			await _open(item)
			var what := "%s (wave %d)" % [item.display_name, wave]
			_check_frame(what)
			min_fit = minf(min_fit, screen.tooltip_fit)
			check(screen.tooltip_fit >= READABLE_FIT, "%s: readable scale %.3f" % [what, screen.tooltip_fit])
			if screen.tooltip_fit < 1.0:
				check_eq(screen.title_mode, LootRollScreen.TitleMode.HIDDEN, "%s: scaled %.3f only with the title hidden" % [what, screen.tooltip_fit])
	check(min_fit >= READABLE_FIT, "the Artifacts' lowest scale %.3f" % min_fit)
	finished.emit()


## The same with the two-line Greed result that makes the frame grow (it is centred, so it grows
## both ways): the title block (as far as it is shown) stays uncovered.
func test_the_frame_stays_clear_of_the_title_block_with_a_greed_result() -> void:
	_async = true
	for item in _artifacts():
		await _open(item)
		var what := item.display_name
		for s in PlayerManager.get_slots():
			screen._choose(s, LootRoll.Choice.GREED if s.index == 2 else LootRoll.Choice.PASS)
		screen._process(0.0)
		await tree.process_frame
		await tree.process_frame
		check(screen.result_label.visible, "%s: the result shows" % what)
		var frame_top := screen.frame.get_global_rect().position.y
		check(frame_top >= _title_end(), "%s: frame top %.1f below the title block (%.1f)" % [what, frame_top, _title_end()])
		_check_frame(what + " (result)")
	finished.emit()


## A solo hero gets the "Loot" title and its own subtitle; a tall tooltip clears them as well.
func test_the_frame_stays_clear_of_the_title_block_for_a_solo_hero() -> void:
	_async = true
	UiFakes.free_node(screen)
	UiFakes.free_node(world)
	UiFakes.reset_players()
	RunState.start_run(1, 12)
	RunState.set_wave(10)
	world = MarketFakes.make_world(tree)
	MarketFakes.human_with_hero(world, "pad:0", &"warrior")
	screen = LootRollScreen.create()
	tree.root.add_child(screen)
	for item in _artifacts():
		await _open(item)
		var what := item.display_name
		check_eq(screen.title_label.text, "Loot", "%s: the solo title" % what)
		var frame := screen.frame.get_global_rect()
		check(frame.position.y >= _title_end(), "%s: frame top %.1f below the title block (%.1f)" % [what, frame.position.y, _title_end()])
		_check_frame(what + " (solo)")
	finished.emit()


# --- The title block collapses before the tooltip is scaled -----------------------------------

func _set_piece(unique_id: StringName) -> ItemInstance:
	var data: UniqueItemData = Db.uniques[unique_id]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	return ItemGenerator.from_unique(data, 25, true, rng, Db.get_class_data(data.class_restriction))


## The steps: a short tooltip keeps the full block (60 px title and subtitle), a tall set piece gets
## the compact one (a smaller title on one line, no subtitle), an Artifact none – and none of
## them is scaled (an Artifact is only a little, and only with nothing left to collapse).
func test_the_title_block_collapses_in_steps() -> void:
	_async = true
	var neck := MarketFakes.make_item("Stormcaller", Items.SlotType.NECK, Items.NO_ARMOR, Items.Rarity.RARE, 40)
	await _open(neck)
	check_eq(screen.title_mode, LootRollScreen.TitleMode.FULL, "a short tooltip: the full block")
	check(screen.title_label.is_visible_in_tree() and screen.subtitle_label.is_visible_in_tree(), "title and subtitle shown")
	check_eq(screen.title_label.get_theme_font_size(&"font_size"), LootRollScreen.FULL_TITLE_FONT, "the full title size")
	var full_end := _title_end()
	check(full_end > 100.0, "the full block ends at %.1f" % full_end)
	check_eq(screen.tooltip_fit, 1.0, "not scaled")

	await _open(_set_piece(&"set_paladin_chest"))
	check_eq(screen.title_mode, LootRollScreen.TitleMode.COMPACT, "a tall set piece: the compact line")
	check(screen.title_label.is_visible_in_tree() and not screen.subtitle_label.is_visible_in_tree(), "the title alone")
	check_eq(screen.title_label.text, "Loot Roll", "still the title")
	check_eq(screen.title_label.get_theme_font_size(&"font_size"), LootRollScreen.COMPACT_TITLE_FONT, "the compact title size")
	check(_title_end() < full_end - 40.0, "the compact block is much shorter (%.1f / %.1f)" % [_title_end(), full_end])
	check_eq(screen.tooltip_fit, 1.0, "not scaled")
	_check_frame("set piece")

	await _open(_artifact(&"rogue", 25))
	check_eq(screen.title_mode, LootRollScreen.TitleMode.HIDDEN, "an Artifact: no title")
	check(not screen.title_label.is_visible_in_tree() and not screen.subtitle_label.is_visible_in_tree(), "nothing shown")
	check(screen.tooltip_fit >= READABLE_FIT, "readable: %.3f" % screen.tooltip_fit)
	_check_frame("Artifact")
	finished.emit()


## Each step frees height for the tooltip: full < compact < hidden room, and the room of the compact
## block holds the tallest ordinary tooltip of the game (set pieces, 579 px; about 581 for the
## tallest Stormcaller at its widest).
func test_each_title_step_gives_the_tooltip_more_room() -> void:
	_async = true
	await _open(MarketFakes.make_item("Stormcaller", Items.SlotType.NECK, Items.NO_ARMOR, Items.Rarity.RARE, 40))
	var full := screen._room_with_title(LootRollScreen.TitleMode.FULL)
	var compact := screen._room_with_title(LootRollScreen.TitleMode.COMPACT)
	var hidden := screen._room_with_title(LootRollScreen.TitleMode.HIDDEN)
	check(compact > full + 40.0, "compact %.0f over full %.0f" % [compact, full])
	check(hidden > compact + 40.0, "hidden %.0f over compact %.0f" % [hidden, compact])
	check(compact >= 585.0, "the compact block leaves %.0f px: room for the tall set pieces" % compact)
	finished.emit()


## The title block belongs to the item: the next item starts from the full block again, and an item
## that does not fit even without it is scaled (not below MIN_TOOLTIP_FIT) on a screen too low for it.
func test_the_next_item_gets_its_own_title_block_and_a_low_screen_scales() -> void:
	_async = true
	var items: Array[ItemInstance] = [_artifact(&"warrior", 25), MarketFakes.make_item("Stormcaller", Items.SlotType.NECK, Items.NO_ARMOR, Items.Rarity.RARE, 40)]
	screen.open(items, PlayerManager.get_slots())
	await tree.process_frame
	await tree.process_frame
	check_eq(screen.title_mode, LootRollScreen.TitleMode.HIDDEN, "the Artifact first: no title")
	for s in PlayerManager.get_slots():
		screen._choose(s, LootRoll.Choice.PASS)
	screen._process(0.0)
	screen._process(LootRollScreen.RESULT_TIME + 0.1)
	await tree.process_frame
	await tree.process_frame
	check_eq(screen.current, 1, "the next item")
	check_eq(screen.title_mode, LootRollScreen.TitleMode.FULL, "the title is back in full")
	check(screen.title_label.is_visible_in_tree() and screen.subtitle_label.is_visible_in_tree(), "title and subtitle shown again")
	check_eq(screen.title_label.get_theme_font_size(&"font_size"), LootRollScreen.FULL_TITLE_FONT, "the full title size again")
	check_eq(screen.tooltip_fit, 1.0, "not scaled")
	_check_frame("Stormcaller after the Artifact")

	await _open(_artifact(&"warrior", 25))
	screen.size = Vector2(1920.0, 760.0)
	screen._fit_tooltip()
	check_eq(screen.title_mode, LootRollScreen.TitleMode.HIDDEN, "a low screen: no title")
	check(screen.tooltip_fit < 1.0 and screen.tooltip_fit >= LootRollScreen.MIN_TOOLTIP_FIT, "scaled only now: %.3f" % screen.tooltip_fit)
	finished.emit()


# --- The "Looted" tag --------------------------------------------------------------------

func test_an_artifact_tooltip_has_no_looted_tag() -> void:
	var item := _artifact(&"warrior")
	check(item.looted, "(an Artifact is generated with the loot budget: looted is set)")
	var t := ItemTooltip.create()
	tree.root.add_child(t)
	t.show_item(item, Db.get_class_data(&"warrior"))
	check(t.find_line("Looted", true) == null, "no Looted line: %s" % t.line_texts())
	check(t.find_line("Item Level %d" % item.item_level) != null, "the Item Level line stays")
	var plain := ItemGenerator.generate_artifact(&"mage", 10)
	t.show_item(plain, Db.get_class_data(&"mage"))
	check(t.find_line("Looted", true) == null, "none for the staff either")
	UiFakes.free_node(t)


func test_an_ordinary_looted_item_keeps_its_looted_tag() -> void:
	var piece := MarketFakes.make_item("Looted Band", Items.SlotType.RING, Items.NO_ARMOR, Items.Rarity.EPIC, 40)
	piece.looted = true
	var t := ItemTooltip.create()
	tree.root.add_child(t)
	t.show_item(piece, Db.get_class_data(&"warrior"))
	check(t.find_line("Looted", true) != null, "Looted line of an ordinary looted item")
	piece.looted = false
	t.show_item(piece, Db.get_class_data(&"warrior"))
	check(t.find_line("Looted", true) == null, "none when it is not looted")
	UiFakes.free_node(t)


func test_the_roll_info_row_has_no_looted_tag_for_an_artifact() -> void:
	_async = true
	var item := _artifact(&"warrior")
	await _open(item)
	check("Artifact" in screen.info_label.text and "Item Level %d" % item.item_level in screen.info_label.text, "the info row: %s" % screen.info_label.text)
	check("Looted" not in screen.info_label.text, "no Looted tag: %s" % screen.info_label.text)
	var piece := MarketFakes.make_item("Looted Band", Items.SlotType.RING, Items.NO_ARMOR, Items.Rarity.EPIC, 40)
	piece.looted = true
	await _open(piece)
	check("Looted" in screen.info_label.text, "an ordinary looted item keeps it: %s" % screen.info_label.text)
	finished.emit()
