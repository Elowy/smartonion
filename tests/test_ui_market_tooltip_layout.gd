extends TestCase
## The shop tooltips of a 4-player market (ShopPanel.layout_tooltips): they never overlap each
## other, a corner panel's tooltip that reaches into a free band or their own hovered card, and
## always lie on the stall or in a free band – in the real Intermission at 1920 x 1080 and in the
## 1280 x 720 window (the same canvas, scaled). The headless root is resized for these tests and
## restored after.
## The review repro (M6b): `--view=intermission --start-wave=22 --seed=9
## --classes=warrior,mage,paladin,warlock` at 1920 x 1080 – the trinkets' tooltips are 274 – 457 px
## tall, a free band only 232 px, so P3's tooltip had no spot beside its card or in a band that
## was clear of P1's, and the old layout took the least overlap (about 30 px of P1's).
## Overlap is only allowed where it cannot be avoided: when everybody is at the smallest scale
## (TOOLTIP_SCALES[-1]) and the tooltips are too tall to fit the stall together.

const UiFakes := preload("res://tests/ui_fakes.gd")
const MarketFakes := preload("res://tests/test_ui_market_fakes.gd")
const DT := 1.0 / 60.0
const SIZES: Array[Vector2i] = [Vector2i(1920, 1080), Vector2i(1280, 720)]
## Four players each: the class mix changes the compared items and so the tooltips' heights.
const MIXES: Array[Array] = [
	[&"warrior", &"mage", &"paladin", &"warlock"],
	[&"rogue", &"warrior", &"mage", &"paladin"],
	[&"warlock", &"rogue", &"warrior", &"mage"],
	[&"paladin", &"paladin", &"mage", &"warlock"],
]
const SEEDS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]
const WAVES: Array[int] = [15, 18, 22, 25]

var world: Node3D
var screen: Intermission
## What the sweeps saw: layouts inspected, the ones that overlapped, the smallest scale used.
var layouts := 0
var overlapping := 0
var min_scale := 1.0
var _root_size := Vector2i.ZERO


func is_async() -> bool:
	return true


func before_each() -> void:
	_root_size = tree.root.size
	UiFakes.reset_players()


func after_each() -> void:
	tree.root.size = _root_size
	_free_scene()
	RunState.start_run(1, 1)
	UiFakes.reset_players()


func _free_scene() -> void:
	UiFakes.free_node(screen)
	UiFakes.free_node(world)
	screen = null
	world = null


## A fresh 4-player market of [param classes] at [param wave] ([param seed]) in a root of [param size].
func _open_market(wave: int, seed: int, classes: Array, size: Vector2i) -> ShopPanel:
	_free_scene()
	UiFakes.reset_players()
	RunState.start_run(4, seed)
	RunState.set_wave(wave)
	world = MarketFakes.make_world(tree)
	for i in 4:
		MarketFakes.human_with_hero(world, "pad:%d" % i, classes[i])
	screen = Intermission.create()
	tree.root.add_child(screen)
	tree.root.size = size
	screen.open(wave, 0)
	await tree.process_frame
	await tree.process_frame
	return screen.shop_panel


static func _rect(tip: ItemTooltip) -> Rect2:
	return Rect2(tip.global_position, tip.get_combined_minimum_size().max(tip.size) * tip.scale)


## The current frame's tooltips: {"shown": int, "outside": bool (one is not on the stall or in a
## band), "covers": bool (one covers its own card or a corner panel's tooltip), "overlap": bool
## (two tooltips overlap), "all_min": bool (every one is at the smallest scale), "text": what is
## wrong}. Updates the sweep statistics.
func _inspect(sp: ShopPanel) -> Dictionary:
	var areas := sp.tooltip_areas()
	var blocked: Array[Rect2] = []
	if sp.tooltip_obstacles.is_valid():
		blocked.assign(sp.tooltip_obstacles.call())
	var out := {"shown": 0, "outside": false, "covers": false, "overlap": false, "all_min": true, "text": ""}
	var rects: Array[Rect2] = []
	for s in PlayerManager.get_slots():
		var tip := sp._shown_tooltip(s.index)
		if tip == null or not tip.visible:
			continue
		out["shown"] += 1
		var r := _rect(tip)
		min_scale = minf(min_scale, tip.scale.x)
		if tip.scale.x > ShopPanel.TOOLTIP_SCALES[-1] + 0.001:
			out["all_min"] = false
		var inside := false
		for a in areas:
			inside = inside or a.grow(1.0).encloses(r)
		if not inside:
			out["outside"] = true
			out["text"] += " P%d %s is off the stall and the bands;" % [s.index + 1, r]
		if r.intersects(sp.card_at(sp.cursor_of(s.index)).get_global_rect()):
			out["covers"] = true
			out["text"] += " P%d covers its card;" % [s.index + 1]
		for o in blocked:
			if r.intersects(o):
				out["covers"] = true
				out["text"] += " P%d covers a panel tooltip;" % [s.index + 1]
		for k in rects.size():
			if r.intersects(rects[k]):
				out["overlap"] = true
				out["text"] += " P%d overlaps %s (%s);" % [s.index + 1, rects[k], r]
		rects.append(r)
	layouts += 1
	if out["overlap"] or out["covers"]:
		overlapping += 1
	return out


## [param what] says which layout; fails on anything [method _inspect] found.
func _check_clean(sp: ShopPanel, what: String) -> void:
	var r := _inspect(sp)
	check_eq(r["shown"], 4, what + ": four tooltips")
	check(not r["outside"] and not r["covers"] and not r["overlap"], "%s:%s" % [what, r["text"]])


# --- The review's repro ---------------------------------------------------------------------------

## Banner of the Warband (P1, card 0), Wayward Compass (P2 and P4, cards 4 and 9) and Ashfall
## Feather (P3, card 5) as in the repro, at wave 22.
func _repro_offers(sp: ShopPanel) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var picks: Dictionary[int, StringName] = {0: &"banner_of_the_warband", 4: &"wayward_compass",
		5: &"ashfall_feather", 9: &"wayward_compass"}
	for i in picks:
		var offer := sp.shop.offers[i]
		offer.item = ItemGenerator.from_unique(Db.get_unique(picks[i]), 22, false, rng)
		offer.price = offer.item.buy_price
		offer.sold = false
	sp.shop.changed.emit()
	for i in 4:
		sp.set_cursor(i, [0, 4, 5, 9][i])


func test_the_review_repro_has_four_separate_tooltips() -> void:
	var sp := await _open_market(22, 9, MIXES[0], Vector2i(1920, 1080))
	_repro_offers(sp)
	await tree.process_frame
	await tree.process_frame
	sp._process(DT)
	_check_clean(sp, "repro")
	# P1 browses first and keeps the full-size spot beside its card; P3 had no room beside its card
	# any more and shrinks (it has no band either: 457 px raw is 247 px at the smallest scale).
	check_near(sp.tooltip_of(0).scale.x, ShopPanel.TOOLTIP_SCALES[0], 0.001, "P1 at full size")
	check(sp.tooltip_of(2).scale.x < ShopPanel.TOOLTIP_SCALES[0], "P3 at a smaller scale")
	check(sp.tooltip_of(2).scale.x >= ShopPanel.TOOLTIP_SCALES[-1] - 0.001, "but not below the smallest")
	finished.emit()


# --- Sweeps ----------------------------------------------------------------------------------------

## Every seed x wave x size market as it opens (each player's cursor near their own corner): no
## overlap, nothing over a card or a corner panel's tooltip, nothing off the stall / the bands.
func test_four_player_markets_open_with_separate_tooltips() -> void:
	var markets := 0
	for size in SIZES:
		for seed in SEEDS:
			for wave in WAVES:
				var sp := await _open_market(wave, seed, MIXES[(seed + wave) % MIXES.size()], size)
				sp._process(DT)
				_check_clean(sp, "%dx%d seed %d wave %d" % [size.x, size.y, seed, wave])
				markets += 1
	check_eq(markets, SIZES.size() * SEEDS.size() * WAVES.size(), "markets checked")
	check_eq(overlapping, 0, "no layout overlapped")
	check(min_scale >= ShopPanel.TOOLTIP_SCALES[-1] - 0.001, "never below the smallest scale")
	finished.emit()


## The crowded worst cases: every player on a random card, all four on the same card, and one
## player roaming over every card while the others stay. Everything is on the stall or in a band
## and overlap is the rare exception, only with everybody at the smallest scale.
func test_crowded_markets_overlap_only_at_the_smallest_scale() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var above_min := 0
	for seed in SEEDS:
		for wave in WAVES:
			var sp := await _open_market(wave, seed, MIXES[(seed + wave) % MIXES.size()], SIZES[0])
			var n := sp.slot_count()
			var states: Array[Array] = []
			for k in 3:
				states.append([rng.randi() % n, rng.randi() % n, rng.randi() % n, rng.randi() % n])
			var same := rng.randi() % n
			states.append([same, same, same, same])
			for who in 4:
				for pos in n:
					var state: Array = []
					for i in 4:
						state.append(sp.cursor_of(i))
					state[who] = pos
					states.append(state)
			for state in states:
				for i in 4:
					sp.set_cursor(i, state[i])
				sp._raise_tooltip(rng.randi() % 4)
				sp._process(DT)
				var r := _inspect(sp)
				var label := "seed %d wave %d cursors %s" % [seed, wave, state]
				check_eq(r["shown"], 4, label + ": four tooltips")
				check(not r["outside"], "%s: off the stall:%s" % [label, r["text"]])
				if r["overlap"] or r["covers"]:
					above_min += 0 if r["all_min"] else 1
					check(r["all_min"], "%s: overlap above the smallest scale:%s" % [label, r["text"]])
	check(layouts > 2000, "%d crowded layouts" % layouts)
	# A regression guard on today's content: 8 of 2048 overlap (the old layout: 976).
	check(overlapping * 100 < layouts, "overlap is the exception: %d of %d layouts" % [overlapping, layouts])
	check_eq(above_min, 0, "never above the smallest scale")
	finished.emit()
