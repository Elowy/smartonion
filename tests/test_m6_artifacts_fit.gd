extends TestCase
## M6 ARTIFACTS on the loot roll window: an Artifact's tooltip (735-855 px at its normal width,
## far taller than any other item) is fitted into the room between the title block and the
## player chips (LootRollScreen.tooltip_room: wider first, scaled last) so at 1920 x 1080 with
## four players the frame stays on screen, below the "Loot Roll" title and its subtitle and clear
## of the chips, and the winner line – even a two-line Greed result – stays clear of them; and the
## green "Looted" tag an Artifact does not earn (its Item Level has no Looted bonus) is hidden in
## the tooltip and the info row.

const UiFakes := preload("res://tests/ui_fakes.gd")
const MarketFakes := preload("res://tests/test_ui_market_fakes.gd")
## The smallest scale an Artifact tooltip may be shown at in the roll window (about 13 px body
## text at 1920 x 1080). It was 0.85 while the frame could cover the title block; keeping the
## frame below the title costs the tallest Artifact (Skull of the Damned, 676 px at 600 wide) a
## scale of about 0.74.
const READABLE_FIT := 0.7
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


## The five shipped Artifacts, one item each.
func _artifacts() -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	for data: ArtifactData in Db.artifacts.values():
		out.append(ItemGenerator.from_artifact(data, 10))
	return out


func _open(item: ItemInstance) -> void:
	var items: Array[ItemInstance] = [item]
	screen.open(items, PlayerManager.get_slots())
	await tree.process_frame
	await tree.process_frame


## The global rect of [param c] as drawn (scale included).
static func _drawn(c: Control) -> Rect2:
	return c.get_global_transform() * Rect2(Vector2.ZERO, c.size)


## The frame is on screen, holds its tooltip, ends above the chips row; [param what] names the case.
func _check_frame(what: String) -> void:
	var frame := screen.frame.get_global_rect()
	var chips := screen.chips_row.get_global_rect()
	check_eq(screen.get_viewport_rect().size, VIEW.size, "%s: the 1920 x 1080 view" % what)
	check(VIEW.encloses(frame), "%s: the frame is on screen %s" % [what, frame])
	check(frame.end.y <= chips.position.y, "%s: the frame ends above the chips (%.1f / %.1f)" % [what, frame.end.y, chips.position.y])
	var tip := _drawn(screen.tooltip)
	check(frame.grow(0.5).encloses(tip), "%s: the tooltip is inside the frame %s / %s" % [what, tip, frame])
	check(screen.name_label.get_global_rect().position.y >= frame.position.y, "%s: the item name is inside the frame" % what)
	var title_end := maxf(screen.title_label.get_global_rect().end.y, screen.subtitle_label.get_global_rect().end.y)
	check(frame.position.y >= title_end, "%s: the frame starts below the title block (%.1f / %.1f)" % [what, frame.position.y, title_end])


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
	check_eq(seen, 5, "all five Artifacts")
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
## the normal tooltip, and the widest it may be fits the frame's width.
func test_a_tall_tooltip_widens_before_it_shrinks() -> void:
	_async = true
	var widened := 0
	for item in _artifacts():
		await _open(item)
		var what := item.display_name
		check(screen.tooltip.size.x > ItemTooltip.WIDTH, "%s: wider than the normal tooltip (%.0f)" % [what, screen.tooltip.size.x])
		check(screen.tooltip.size.x <= screen.frame.size.x - 2.0 * 26.0 + 0.5, "%s: not wider than the frame's inside (%.0f)" % [what, screen.tooltip.size.x])
		if screen.tooltip.size.x > ItemTooltip.WIDTH:
			widened += 1
	check_eq(widened, 5, "all five widened")
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


## The room follows the frame: a tooltip that did not fit the room at its normal width is
## made to fit it – no Artifact, set piece or unique pokes out of the frame or over the chips.
func test_no_unique_or_set_piece_breaks_the_roll_window() -> void:
	_async = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var checked := 0
	var scaled := 0
	for unique: UniqueItemData in Db.uniques.values():
		var cls_id := unique.class_restriction if unique.class_restriction != &"" else &"warrior"
		var item := ItemGenerator.from_unique(unique, 25, true, rng, Db.get_class_data(cls_id))
		await _open(item)
		var what := item.display_name
		_check_frame(what)
		check(screen.tooltip_fit >= 0.8, "%s: readable scale %.3f" % [what, screen.tooltip_fit])
		if screen.tooltip_fit < 1.0:
			scaled += 1
		checked += 1
	check(checked >= 60, "uniques and set pieces checked: %d (scaled %d)" % [checked, scaled])
	finished.emit()


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

## The title block's bottom edge and the frame's top edge, as drawn.
func _title_end() -> float:
	return maxf(screen.title_label.get_global_rect().end.y, screen.subtitle_label.get_global_rect().end.y)


## "Loot Roll" and its subtitle are centred above the frame, which is as wide as they are: a tall
## tooltip (every Artifact) must not push the frame up over them (LootRollScreen.tooltip_room
## reserves the title block's height; the middle row is centred in the band below it).
func test_the_frame_stays_below_the_title_block_for_every_artifact() -> void:
	_async = true
	var seen := 0
	for item in _artifacts():
		await _open(item)
		var what := item.display_name
		check_eq(screen.slots.size(), 4, "%s: four players" % what)
		check_eq(screen.title_label.text, "Loot Roll", "%s: the party title" % what)
		var frame := screen.frame.get_global_rect()
		var title_end := _title_end()
		check(title_end > 100.0, "%s: the title block is really measured (ends at %.1f)" % [what, title_end])
		check(frame.position.y >= title_end + LootRollScreen.FRAME_TITLE_GAP - 0.5,
				"%s: frame top %.1f is clear of the title block (%.1f + gap)" % [what, frame.position.y, title_end])
		var tip := _drawn(screen.tooltip)
		check(tip.position.y >= title_end, "%s: so is the tooltip (%.1f)" % [what, tip.position.y])
		check(frame.end.y <= screen.chips_row.get_global_rect().position.y - LootRollScreen.FRAME_CHIPS_GAP + 0.5,
				"%s: and the chips still have their gap (%.1f)" % [what, frame.end.y])
		seen += 1
	check_eq(seen, 5, "all five Artifacts")
	finished.emit()


## The same with the two-line Greed result that makes the frame grow (it is centred, so it grows
## both ways): the title block stays uncovered.
func test_the_frame_stays_below_the_title_block_with_a_greed_result() -> void:
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
	finished.emit()


## A solo hero gets the "Loot" title and its own subtitle; a tall tooltip clears them as well.
func test_the_frame_stays_below_the_title_block_for_a_solo_hero() -> void:
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
