extends TestCase
## The market's item tooltips in the real 4-player corner layout at 1920 x 1080 (the headless
## root is resized for these tests and restored after): a corner panel's tall tooltip (a
## Legendary with the comparison block) reaches out of its panel over the free band but stops
## before the panel at the other end of its screen column (PlayerPanel.tooltip_column_mate;
## below MIN_INSIDE_TOOLTIP_FIT only when that floor would cross into it) – all the way to the
## screen edge when that corner is empty; when both players of a column show such a tooltip on
## the same half of their panels, the bottom one moves to its panel's other half
## (PlayerPanel.tooltip_obstacle); the shop's tooltips keep clear of them in the band
## (ShopPanel.tooltip_obstacles, fed by Intermission._panel_tooltip_rects).

const UiFakes := preload("res://tests/ui_fakes.gd")
const MarketFakes := preload("res://tests/test_ui_market_fakes.gd")
## P1 top-left, P2 top-right, P3 bottom-left, P4 bottom-right.
const CLASSES: Array[StringName] = [&"warrior", &"warlock", &"paladin", &"mage"]

var world: Node3D
var screen: Intermission
var shop: MarketFakes.FakeShop
var inputs: Array[UiFakes.HumanInput] = []
var rng := RandomNumberGenerator.new()
var _root_size := Vector2i.ZERO


func is_async() -> bool:
	return true


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(4, 9)
	rng.seed = 5
	shop = MarketFakes.FakeShop.new()
	RunState.shop = shop
	var items: Array[ItemInstance] = []
	var prices: Array[int] = []
	for i in 10:
		items.append(MarketFakes.make_item("Band %d" % i, Items.SlotType.RING))
		prices.append(10 + i)
	shop.stock(items, prices)
	world = MarketFakes.make_world(tree)
	screen = Intermission.create()
	tree.root.add_child(screen)
	_root_size = tree.root.size
	tree.root.size = Vector2i(1920, 1080)


func after_each() -> void:
	tree.root.size = _root_size
	Intermission.auto_continue_time = Intermission.AUTO_CONTINUE_TIME
	UiFakes.free_node(screen)
	UiFakes.free_node(world)
	screen = null
	world = null
	inputs.clear()
	RunState.start_run(1, 1)
	UiFakes.reset_players()


## [param classes] join as humans (P1 ...), the market opens; every panel starts with the
## focus on its own side, nothing selected.
func _open_market(classes: Array[StringName]) -> void:
	for i in classes.size():
		inputs.append(MarketFakes.human_with_hero(world, "pad:%d" % i, classes[i]))
	screen.open(12, 0)
	await tree.process_frame
	await tree.process_frame
	check_eq(screen.get_viewport_rect().size, Vector2(1920, 1080), "the 1920 x 1080 view")
	check_eq(screen.phase, Intermission.Phase.MARKET, "market")


func _eq(i: int) -> Equipment:
	return (PlayerManager.get_slot(i).player as Player).equipment


## The scaled panel / tooltip as drawn (global).
static func _rect(c: Control) -> Rect2:
	return c.get_global_transform() * Rect2(Vector2.ZERO, c.size)


## An Epic sword with many stats in each hand [param i] can hold one in: a backpack weapon's
## tooltip gets a long comparison block.
func _wear_rich_weapon(i: int) -> void:
	var eq := _eq(i)
	for hand in eq.target_slots(MarketFakes.make_weapon(&"sword")):
		var weapon := MarketFakes.make_weapon(&"sword", Items.Rarity.EPIC)
		weapon.stats = {Stats.STAMINA: 30.0, Stats.AGILITY: 20.0, Stats.INTELLECT: 20.0, Stats.MASTERY: 9.0,
			Stats.VERSATILITY: 9.0, Stats.DODGE: 6.0, Stats.LEECH: 4.0, Stats.SPEED: 5.0}
		eq.slots[hand] = weapon


## [param item] alone in [param i]'s backpack, selected, with the comparison block.
func _show_from_backpack(i: int, item: ItemInstance) -> void:
	var panel := screen.panels[i]
	_eq(i).backpack.clear()
	_eq(i).add_to_backpack(item)
	panel.refresh()
	panel.select_backpack(0)
	if not panel.comparison:
		panel.toggle_comparison()
	await tree.process_frame
	await tree.process_frame


func _stormcaller(i: int) -> ItemInstance:
	return _unique(i, &"stormcaller")


## A wave-25 looted [param id] rolled for [param i]'s class.
func _unique(i: int, id: StringName) -> ItemInstance:
	return ItemGenerator.from_unique(Db.get_unique(id), 25, true, rng, PlayerManager.get_slot(i).class_data)


## A many-stat Epic piece in every slot of [param i]'s equipment that [param item] could go to:
## the item's tooltip gets a long comparison block.
func _wear_rich_for(i: int, item: ItemInstance) -> void:
	var eq := _eq(i)
	for target in eq.target_slots(item):
		var worn: ItemInstance
		if item.is_weapon():
			worn = ItemInstance.from_weapon(item.weapon, Items.Rarity.EPIC, 20)
		else:
			worn = MarketFakes.make_item("Worn Piece", item.slot_type, item.armor_type, Items.Rarity.EPIC)
		worn.stats = {Stats.STAMINA: 30.0, Stats.AGILITY: 20.0, Stats.INTELLECT: 20.0, Stats.MASTERY: 9.0,
			Stats.VERSATILITY: 9.0, Stats.DODGE: 6.0}
		eq.slots[target] = worn


## [param item] against rich gear, in [param i]'s backpack ([param on_doll]: worn instead),
## selected with the comparison block.
func _show_tall(i: int, item: ItemInstance, on_doll := false) -> void:
	_wear_rich_for(i, item)
	if not on_doll:
		await _show_from_backpack(i, item)
		return
	var panel := screen.panels[i]
	var target: int = _eq(i).target_slots(item)[0]
	_eq(i).backpack.clear()
	_eq(i).slots[target] = item
	panel.refresh()
	panel.select_equip_slot(target)
	if not panel.comparison:
		panel.toggle_comparison()
	await tree.process_frame
	await tree.process_frame


## The selected icon of [param i]'s panel (global).
func _selected_icon(i: int) -> Rect2:
	var panel := screen.panels[i]
	var bag := panel.selected_bag_index()
	return _rect(panel.icon_for_bag_index(bag) if bag >= 0 else panel.icon_for_equip_slot(panel.selected_equip_slot()))


## Both players of the column under [param top] (P1 / P2) show their tooltips: each on screen,
## clear of the other panel and of the other tooltip. Returns whether the bottom one made way
## (its plan without the top one's tooltip would have covered it).
func _check_column_apart(top: int, what: String) -> bool:
	var bottom := top + 2
	var t := _check_clear_of_the_column_mate(top, "%s: P%d" % [what, top + 1])
	var b := _check_clear_of_the_column_mate(bottom, "%s: P%d" % [what, bottom + 1])
	check(not t.intersects(b), "%s: P%d's tooltip %s and P%d's %s keep apart" % [what, top + 1, t, bottom + 1, b])
	var panel := screen.panels[bottom]
	var would := panel._tooltip_plan(false).rect
	if not would.intersects(t):
		check(b.is_equal_approx(would), "%s: P%d's tooltip stays where it would be anyway" % [what, bottom + 1])
		return false
	var own := _rect(panel)
	var icon := _selected_icon(bottom)
	check((b.get_center().x < own.get_center().x) == (icon.get_center().x < own.get_center().x),
		"%s: P%d's tooltip moved to the selected icon's half" % [what, bottom + 1])
	check_near(b.size.y, would.size.y, 0.5, "%s: at the same size" % what)
	var band_top := _rect(screen.panels[top]).end.y + PlayerPanel.TOOLTIP_NEIGHBOUR_GAP
	if b.size.y <= icon.position.y - 6.0 - band_top:
		check(not b.intersects(icon), "%s: P%d's tooltip leaves the selected icon in sight (%s / %s)" % [what, bottom + 1, b, icon])
	return true


## Both players of a column look at a tall item from their own backpacks – the tooltips on the
## same half of their panels, both reaching into the band between them: the top one keeps its
## place, the bottom one moves to its panel's other half (and back once the top one is gone).
func test_two_tall_tooltips_in_one_column_keep_apart() -> void:
	await _open_market(CLASSES)
	for top in 2:
		var bottom := top + 2
		var what := "P%d Stormcaller / P%d Bulwark of the Last Stand" % [top + 1, bottom + 1]
		screen.set_panel_focus(top, true)
		await _show_tall(top, _stormcaller(top))
		var alone := _rect(screen.panels[top].tooltip)
		screen.set_panel_focus(bottom, true)
		await _show_tall(bottom, _unique(bottom, &"bulwark_of_the_last_stand"))
		check(screen.panels[bottom].tooltip.item.display_name == "Bulwark of the Last Stand", "%s shown" % what)
		check(_check_column_apart(top, what), "%s: the bottom one had to make way" % what)
		check(_rect(screen.panels[top].tooltip).is_equal_approx(alone), "%s: P%d's tooltip keeps its place" % [what, top + 1])
		# The top player goes back to the shop: the bottom tooltip returns to the half away
		# from the selected icon.
		screen.set_panel_focus(top, false)
		await tree.process_frame
		await tree.process_frame
		var own := _rect(screen.panels[bottom])
		var b := _rect(screen.panels[bottom].tooltip)
		check((b.get_center().x < own.get_center().x) != (_selected_icon(bottom).get_center().x < own.get_center().x),
			"P%d's tooltip back on the half away from the selected icon" % (bottom + 1))
		var obstacle := screen.panels[bottom].tooltip_obstacle
		check(obstacle.is_valid() and not (obstacle.call() as Rect2).has_area(), "P%d's tooltip has nothing to make way for" % (bottom + 1))
		screen.set_panel_focus(bottom, false)
	# Every Legendary unique against the next one, both from the backpack, then both worn.
	var legendaries: Array[UniqueItemData] = []
	for data: UniqueItemData in Db.uniques.values():
		if data.rarity == Items.Rarity.LEGENDARY:
			legendaries.append(data)
	var made_way := 0
	for on_doll in [false, true]:
		for k in legendaries.size():
			for top in 2:
				var bottom := top + 2
				var a := legendaries[k]
				var z := legendaries[(k + 1) % legendaries.size()]
				screen.set_panel_focus(top, true)
				screen.set_panel_focus(bottom, true)
				await _show_tall(top, ItemGenerator.from_unique(a, 25, true, rng, PlayerManager.get_slot(top).class_data), on_doll)
				await _show_tall(bottom, ItemGenerator.from_unique(z, 25, true, rng, PlayerManager.get_slot(bottom).class_data), on_doll)
				if _check_column_apart(top, "P%d %s / P%d %s%s" % [top + 1, a.display_name, bottom + 1, z.display_name, " (worn)" if on_doll else ""]):
					made_way += 1
				screen.set_panel_focus(top, false)
				screen.set_panel_focus(bottom, false)
	check(made_way >= 8, "the bottom tooltip made way %d times" % made_way)
	finished.emit()


## [param i]'s tooltip: shown, on screen, clear of the panel at the other end of the column.
func _check_clear_of_the_column_mate(i: int, what: String) -> Rect2:
	var panel := screen.panels[i]
	var tip := _rect(panel.tooltip)
	check(panel.tooltip.visible, "%s: shown" % what)
	check(screen.get_viewport_rect().grow(-3.0).encloses(tip), "%s: on screen %s" % [what, tip])
	var mate := _rect(screen.panels[i ^ 2])
	check(not tip.intersects(mate), "%s: clear of P%d's panel (%s / %s)" % [what, (i ^ 2) + 1, tip, mate])
	return tip


func test_a_tall_panel_tooltip_stops_before_the_other_panel_of_its_column() -> void:
	await _open_market(CLASSES)
	for i in 4:
		check(screen.panels[i].tooltip_column_mate, "P%d shares its column" % (i + 1))
		_wear_rich_weapon(i)
	for i in 4:
		var panel := screen.panels[i]
		screen.set_panel_focus(i, true)
		await _show_from_backpack(i, _stormcaller(i))
		var what := "P%d Stormcaller with the comparison block" % (i + 1)
		check(panel.tooltip.comparison_visible and panel.tooltip.item.display_name == "Stormcaller", "%s shown" % what)
		var tip := _check_clear_of_the_column_mate(i, what)
		var own := _rect(panel)
		var mate := _rect(screen.panels[i ^ 2])
		# Too tall for the floor: it fills the room up to the gap before the other panel.
		var room := (mate.position.y - own.position.y) if i < 2 else (own.end.y - mate.end.y)
		var at_floor := panel.tooltip.size.y * own.size.y / panel.size.y * PlayerPanel.MIN_INSIDE_TOOLTIP_FIT
		check(at_floor > room, "%s: at the floor %.0f px would not fit the %.0f px to P%d" % [what, at_floor, room, (i ^ 2) + 1])
		check(panel.tooltip.scale.y < PlayerPanel.MIN_INSIDE_TOOLTIP_FIT, "%s: below the floor (%.3f)" % [what, panel.tooltip.scale.y])
		check(panel.tooltip.scale.y > 0.6, "%s: still %.3f" % [what, panel.tooltip.scale.y])
		if i < 2:
			check_near(tip.position.y, own.position.y, 0.5, "%s: hangs from the panel's top edge" % what)
			check_near(mate.position.y - tip.end.y, PlayerPanel.TOOLTIP_NEIGHBOUR_GAP, 0.5, "%s: ends the gap before P%d" % [what, (i ^ 2) + 1])
		else:
			check_near(tip.end.y, own.end.y, 0.5, "%s: rises from the panel's bottom edge" % what)
			check_near(tip.position.y - mate.end.y, PlayerPanel.TOOLTIP_NEIGHBOUR_GAP, 0.5, "%s: starts the gap after P%d" % [what, (i ^ 2) + 1])
		screen.set_panel_focus(i, false)
	# Every Legendary unique, in each corner, against the same rich weapon.
	var legendaries := 0
	for data: UniqueItemData in Db.uniques.values():
		if data.rarity != Items.Rarity.LEGENDARY:
			continue
		legendaries += 1
		for i in 4:
			screen.set_panel_focus(i, true)
			var item := ItemGenerator.from_unique(data, 25, true, rng, PlayerManager.get_slot(i).class_data)
			await _show_from_backpack(i, item)
			_check_clear_of_the_column_mate(i, "P%d %s" % [i + 1, data.display_name])
			var fit := screen.panels[i].tooltip.scale.y
			check(fit >= PlayerPanel.MIN_INSIDE_TOOLTIP_FIT - 0.001 or _rect(screen.panels[i].tooltip).size.y > 600.0,
				"P%d %s: below the floor only when it fills the column (%.3f)" % [i + 1, data.display_name, fit])
			screen.set_panel_focus(i, false)
	check(legendaries >= 8, "the Legendary uniques: %d" % legendaries)
	finished.emit()


## With nobody in the column's other corner (two players: P1 and P2 at the top) the tooltip
## keeps the floor and may reach further down; when P3 leaves a 3-player market P1's column
## frees up.
func test_an_empty_column_corner_leaves_the_tooltip_at_the_floor() -> void:
	await _open_market([&"warrior", &"paladin"] as Array[StringName])
	for i in 2:
		check(not screen.panels[i].tooltip_column_mate, "P%d has the column to itself" % (i + 1))
		_wear_rich_weapon(i)
		screen.set_panel_focus(i, true)
		await _show_from_backpack(i, _stormcaller(i))
		var panel := screen.panels[i]
		var tip := _rect(panel.tooltip)
		check_near(panel.tooltip.scale.y, PlayerPanel.MIN_INSIDE_TOOLTIP_FIT, 0.001, "P%d keeps the floor" % (i + 1))
		check(screen.get_viewport_rect().grow(-3.0).encloses(tip), "P%d on screen: %s" % [i + 1, tip])
		check(tip.end.y > screen.get_viewport_rect().end.y - Intermission.MARGIN - _rect(panel).size.y,
			"P%d reaches into the empty corner: %s" % [i + 1, tip])
	finished.emit()


func test_the_column_mate_follows_a_player_leaving() -> void:
	await _open_market([&"warrior", &"mage", &"paladin"] as Array[StringName])
	check(screen.panels[0].tooltip_column_mate and screen.panels[2].tooltip_column_mate, "P1 / P3 share the left column")
	check(not screen.panels[1].tooltip_column_mate, "P2 has the right column to itself")
	var slot := PlayerManager.get_slot(2)
	inputs[2].connected = false
	var hero := slot.player as Node
	slot.player = null
	hero.free()
	PlayerManager.leave(2)
	check(not screen.panels.has(2), "P3's panel is gone")
	check(not screen.panels[0].tooltip_column_mate, "P1 has the left column to itself now")
	finished.emit()


## P3 looks at a tall equipped weapon in its own panel: the tooltip rises over the left band.
## P1's shop tooltip – pushed off the stall into that band by P2's (P2 acted last, its tooltip
## takes the spot right of P1's card) – keeps clear of it.
func test_shop_tooltips_keep_clear_of_a_panel_tooltip_in_the_band() -> void:
	await _open_market(CLASSES)
	var sp := screen.shop_panel
	for i in [2, 3]:
		screen.set_panel_focus(i, true)
	sp.set_cursor(0, 0)
	sp.set_cursor(1, 1)
	sp._raise_tooltip(0)
	sp._raise_tooltip(1)
	await tree.process_frame
	await tree.process_frame
	var band := sp.tooltip_areas()[1]
	var p1_tip := sp.tooltip_of(0)
	check(p1_tip.visible, "P1's shop tooltip")
	check(band.grow(1.0).encloses(_rect(p1_tip)), "without a panel tooltip P1's shop tooltip is in the left band: %s / %s"
		% [_rect(p1_tip), band])
	check(not screen.panels[2].outside_tooltip_rect().has_area(), "P3 shows nothing yet")
	# P3: Stormcaller in the main hand, selected (the doll is on the left: the tooltip takes the
	# panel's right half, towards the stall).
	var storm := _stormcaller(2)
	_eq(2).slots[Items.EquipSlot.MAIN_HAND] = storm
	var p3 := screen.panels[2]
	p3.refresh()
	p3.select_equip_slot(Items.EquipSlot.MAIN_HAND)
	await tree.process_frame
	await tree.process_frame
	var panel_tip := p3.outside_tooltip_rect()
	check(p3.tooltip.visible and p3.tooltip.item == storm, "P3 shows the Stormcaller")
	check(panel_tip.has_area() and panel_tip.intersects(band), "P3's tooltip reaches into the left band: %s" % panel_tip)
	check(not panel_tip.intersects(_rect(screen.panels[0])), "and stops before P1's panel")
	var shop_tips: Array[Rect2] = []
	for i in 2:
		var tip := sp.tooltip_of(i)
		check(tip.visible, "P%d's shop tooltip still shows" % (i + 1))
		var r := _rect(tip)
		check(not r.intersects(panel_tip), "P%d's shop tooltip keeps clear of P3's panel tooltip: %s / %s" % [i + 1, r, panel_tip])
		check(not r.intersects(sp.cards[sp.cursor_of(i)].get_global_rect()), "P%d still sees its card" % (i + 1))
		for o in shop_tips:
			check(not r.intersects(o), "P%d does not overlap the other shop tooltip" % (i + 1))
		shop_tips.append(r)
	# Back to the shop: the band is free again.
	screen.set_panel_focus(2, false)
	sp.set_cursor_active(2, false)
	await tree.process_frame
	await tree.process_frame
	check(not p3.outside_tooltip_rect().has_area(), "P3's panel tooltip is gone")
	check(band.grow(1.0).encloses(_rect(p1_tip)), "P1's shop tooltip is back in the band")
	finished.emit()
