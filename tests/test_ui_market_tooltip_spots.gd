extends TestCase
## ShopPanel's tooltip spot search on synthetic rects (the layout in the real market:
## test_ui_market_tooltip_layout.gd). One 688 x 688 area, a hovered card at the top left (cursor
## position 0 of a 5-column grid, 124 x 176 at (28, 73)); tooltips are 200 x 200 unscaled, so
## 164 / 144 / 124 / 108 px at the four scales (TOOLTIP_SCALES).

const UiFakes := preload("res://tests/ui_fakes.gd")
const MarketFakes := preload("res://tests/test_ui_market_fakes.gd")

var panel: ShopPanel
var areas: Array[Rect2] = [Rect2(0, 0, 688, 688)]
var card := Rect2(28, 73, 124, 176)
var raw := Vector2(200, 200)


func before_each() -> void:
	UiFakes.reset_players()
	var shop := MarketFakes.FakeShop.new()
	var items: Array[ItemInstance] = []
	var prices: Array[int] = []
	for i in 10:
		items.append(MarketFakes.make_item("Band %d" % i, Items.SlotType.RING))
		prices.append(10)
	shop.stock(items, prices)
	panel = ShopPanel.create(shop)


func after_each() -> void:
	UiFakes.free_node(panel)
	panel = null
	UiFakes.reset_players()


func _spot(placed: Array[Rect2], blocked: Array[Rect2] = [], cap := 0) -> ShopPanel.TooltipSpot:
	return panel._find_spot(raw, card, 0, 0, areas, placed, blocked, cap)


func _is_clear(spot: ShopPanel.TooltipSpot, others: Array[Rect2]) -> bool:
	for o in others:
		if o.intersects(spot.rect):
			return false
	return not spot.rect.intersects(card)


func test_a_free_preferred_spot_is_kept_at_full_scale() -> void:
	var spot := _spot([] as Array[Rect2])
	check_near(spot.scale, ShopPanel.TOOLTIP_SCALES[0], 0.001, "full scale")
	check(spot.rect.position.is_equal_approx(Vector2(card.end.x + ShopPanel.TOOLTIP_GAP, card.position.y)), "beside the card: %s" % spot.rect)
	check_eq(spot.cost, 0.0, "free")


func test_a_taken_preferred_spot_gives_way_to_a_free_one_at_the_same_scale() -> void:
	# Beside the card is taken, below it is free.
	var placed: Array[Rect2] = [Rect2(164, 73, 400, 120)]
	var spot := _spot(placed)
	check_near(spot.scale, ShopPanel.TOOLTIP_SCALES[0], 0.001, "still full scale")
	check(_is_clear(spot, placed), "clear of the other tooltip and the card: %s" % spot.rect)
	check_eq(spot.cost, 0.0, "free")


## No preferred spot (beside, above / below) is free at any scale, but the stall has room at the
## smallest one: the bottom strip y 571..688 (117 px) is left by A and B.
func test_a_free_spot_anywhere_beats_overlapping_a_preferred_one() -> void:
	var placed: Array[Rect2] = [Rect2(164, 73, 600, 190), Rect2(0, 261, 688, 310)]
	var spot := _spot(placed)
	check(_is_clear(spot, placed), "overlaps nothing: %s" % spot.rect)
	check_eq(spot.cost, 0.0, "free")
	check_near(spot.scale, ShopPanel.TOOLTIP_SCALES[-1], 0.001, "only the smallest scale fits the strip")
	check(spot.rect.position.y >= 571.0 and spot.rect.end.y <= 688.0 + 0.01, "in the bottom strip: %s" % spot.rect)
	# A panel tooltip (blocked) counts like the others.
	var blocked: Array[Rect2] = [Rect2(0, 560, 688, 128)]
	var spot2 := _spot(placed, blocked)
	check(spot2.cost > 0.0, "nothing free left: the overlap is accepted (%s)" % spot2.rect)
	check_near(spot2.scale, ShopPanel.TOOLTIP_SCALES[-1], 0.001, "at the smallest scale")


func test_overlap_is_only_accepted_at_the_smallest_scale_and_is_the_least_possible() -> void:
	# 600 px of the 688 are taken: the 108 px tooltip cannot be free anywhere.
	var placed: Array[Rect2] = [Rect2(0, 0, 688, 600)]
	var spot := _spot(placed)
	check_near(spot.scale, ShopPanel.TOOLTIP_SCALES[-1], 0.001, "smallest scale")
	check(spot.cost > 0.0, "overlap accepted")
	check_near(spot.rect.end.y, 688.0, 0.01, "as low as possible: %s" % spot.rect)
	check_near(spot.cost, 20.0 * 108.0, 1.0, "20 px of 108 wide: the least overlap")
	# Capped at a smaller scale nothing larger is tried.
	var capped := _spot([] as Array[Rect2], [] as Array[Rect2], 2)
	check_near(capped.scale, ShopPanel.TOOLTIP_SCALES[2], 0.001, "the cap limits the scale")


func test_a_tooltip_that_fits_nowhere_has_no_rect() -> void:
	raw = Vector2(200, 2000)
	var spot := _spot([] as Array[Rect2])
	check(not spot.rect.has_area(), "too tall for the area even at the smallest scale")
	check_near(spot.scale, ShopPanel.TOOLTIP_SCALES[-1], 0.001, "at the smallest scale")


func test_free_spots_line_up_with_the_edges_inside_the_area() -> void:
	var tsize := Vector2(100, 100)
	var obstacle := Rect2(300, 300, 100, 100)
	var obstacles: Array[Rect2] = [obstacle]
	var spots := ShopPanel._free_spots(tsize, areas, obstacles, 6.0)
	check(not spots.is_empty(), "some spots")
	var right_of := false
	var left_of := false
	for r in spots:
		check(areas[0].grow(0.01).encloses(r), "inside the area: %s" % r)
		right_of = right_of or is_equal_approx(r.position.x, obstacle.end.x + 6.0)
		left_of = left_of or is_equal_approx(r.end.x, obstacle.position.x - 6.0)
	check(right_of and left_of, "spots right and left of the obstacle, 6 px away")
	var big := ShopPanel._free_spots(Vector2(700, 100), areas, obstacles, 6.0)
	check(big.is_empty(), "wider than the area: none")


func test_permutations_list_every_order_once() -> void:
	var orders := ShopPanel._permutations([0, 1, 2, 3] as Array[int])
	check_eq(orders.size(), 24, "4! orders")
	var seen := {}
	for o in orders:
		seen[str(o)] = true
	check_eq(seen.size(), 24, "all different")
	check_eq(ShopPanel._permutations([] as Array[int]).size(), 1, "the empty order")
