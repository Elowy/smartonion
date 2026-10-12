class_name ShopPanel
extends Control
## The shared shop in the middle of the between-wave screen (GDD 10, 12): a goblin merchant's
## stall ("The Goblin's Goods", ShopMerchant) showing Shop.offers as item cards
## (ShopOfferCard: icon, name in rarity colour, price, lock / ping markers, usable-by pips per
## player, an anvil above the pip of every player who could forge the offered weapon), one
## colour-coded cursor per player (nested outlines + a corner tag in the player's corner when
## several share a card), reroll vote pips + cost and the shared gold at the top, and a short
## feedback / spending log ("P3 bought [Runed Plate Helm] – 62 g", "Backpack full").
## Forging (GDD 4.1): with a full backpack, buying a weapon the buyer has a forge partner for
## forges at once (Shop.BuyResult.FORGED): no "Backpack full", and the log says
## "P1 bought and forged [Rare Dagger] – 62 g".
##
## Per player (handle_input, called by the Intermission for every slot whose focus is the
## shop): d-pad / stick moves the cursor, A buys (hold A for HOLD_TIME when the price is more
## than HOLD_SHARE of the shared wallet – a fill ring shows the progress; a reroll, a changed
## offer or B cancels it), X locks, R3 / Tab pings, Y votes for a reroll (only humans with a
## working device vote; bots never block it; process_votes re-evaluates standing votes).
## lock_input(seconds) makes A / X ignored for a moment after the market opens.
## Shows an ItemTooltip for each shop-focused player's hovered offer, compared with the item it
## would replace for that player (ItemTooltip.equipped_for_compare). Tooltips never overlap
## each other or the player panels in the screen corners and never hide their own card: each
## goes beside its hovered card on the stall if that spot is free, else on the card's other
## side, above / below it, or into the free band between the corner panels on the player's
## side – at a smaller scale when nothing else fits ([method layout_tooltips]). They also keep
## clear of a corner panel's own item tooltip that reaches out of its panel into such a band
## ([member tooltip_obstacles]).
## The panel only calls the Shop contract (buy / toggle_lock / toggle_ping / vote_reroll) and
## redraws on Shop.changed and RunState.gold_changed (while hidden – the whole wave, the
## Intermission stays in the tree – a wallet change is caught up at the end of the frame the
## panel is shown in, unless refresh() rebuilt it first).

## A purchase went through (also used for bots and the smoke statistics).
signal item_bought(slot_index: int, item: ItemInstance)

const STALL_SIZE := Vector2(704, 800)
## Where the stall body starts below the awning (ShopMerchant draws above it).
const BODY_TOP := 96.0
const MAX_COLUMNS := 5
const CARD_GAP := 8
## GDD 10: a purchase that takes more than HOLD_SHARE of the wallet needs A held this long.
const HOLD_TIME := 1.0
const HOLD_SHARE := 0.5
const FEEDBACK_LINES := 3
const FEEDBACK_TIME := 6.0
const TOOLTIP_GAP := 12.0
## Shop tooltips are drawn a little smaller so they cover fewer neighbouring cards; when no
## free spot is found the next smaller scale is tried.
const TOOLTIP_SCALE := 0.82
const TOOLTIP_SCALES: Array[float] = [0.82, 0.72, 0.62, 0.54]
## Inset of the tooltips from the stall body's edges.
const TOOLTIP_MARGIN := 8.0
## A spot that covers the hovered card or a [member tooltip_obstacles] rect counts this many
## times its overlapping area (another shop tooltip: once).
const COVER_WEIGHT := 4.0

var shop: Shop
## Returns the global rects (Array[Rect2]) the shop tooltips keep clear of besides each other:
## the Intermission hands over its corner panels' item tooltips that reach out of their panel
## into the free bands (PlayerPanel.outside_tooltip_rect). Read once per layout; unset: none.
var tooltip_obstacles: Callable
## Offer grid width (5 for 10 offers, 4 for 8 or 4, 3 for 6).
var columns := MAX_COLUMNS
var cards: Array[ShopOfferCard] = []

var _slots: Array[PlayerSlot] = []
var _cursor: Dictionary[int, int] = {}
## Slot index -> false while that player's focus is their own panel (dim cursor, no tooltip).
var _active: Dictionary[int, bool] = {}
## Slot index -> {"offer": int, "time": float, "uid": int, "price": int} while A is held on an
## expensive offer (the item's uid and the price are checked again before the purchase: a
## reroll that swaps the offer cancels the hold).
var _holds: Dictionary[int, Dictionary] = {}
## B just cancelled a hold in the last handle_input call (the Intermission then does not also
## unready the player with that press).
var last_input_consumed := false
## Seconds A and X (buy / lock) are ignored for (a press that was meant for the previous screen).
var _input_lockout := 0.0
var _tooltips: Dictionary[int, ItemTooltip] = {}
var _tooltip_keys: Dictionary[int, String] = {}
## Slot indices, the player who acted last at the end (tooltip priority and draw order).
var _act_order: Array[int] = []
## Newest last: {"bb": String, "plain": String, "age": float}.
var _feedback: Array[Dictionary] = []
var _feedback_dirty := false
var _frame_delta := -1.0
var _t := 0.0
var _watched: Array[Equipment] = []
var _cards_dirty := false
## The wallet changed while the panel was hidden: price colours and the gold line are updated
## when it is shown again (refresh() clears it: it rebuilds both).
var _gold_stale := false

var _art: ShopMerchant
var _body: PanelContainer
var _grid: GridContainer
var _cursor_layer: Control
var _gold_label: Label
var _reroll_label: Label
var _pips: Control
var _feedback_labels: Array[RichTextLabel] = []
var _tooltip_layer: Control


static func create(p_shop: Shop) -> ShopPanel:
	var panel := ShopPanel.new()
	panel.name = "ShopPanel"
	panel._build()
	panel.set_shop(p_shop)
	return panel


## The Equipment of the hero playing [param slot] (null outside a run / without a hero).
static func equipment_of(slot: PlayerSlot) -> Equipment:
	if slot == null:
		return null
	var p := slot.player as Player
	if p == null or not is_instance_valid(p):
		return null
	return p.equipment


## BBCode-safe text (brackets become [lb] / [rb]).
static func bb_escape(text: String) -> String:
	return text.replace("[", "\u0001").replace("]", "[rb]").replace("\u0001", "[lb]")


## "[Runed Plate Helm]" in the item's rarity colour (BBCode).
static func item_link(item: ItemInstance) -> String:
	if item == null:
		return ""
	return "[color=#%s]%s[/color]" % [ShopOfferCard.rarity_color(item).to_html(false), bb_escape("[%s]" % item.display_name)]


## "P2" in the player's colour (BBCode).
static func player_tag(slot: PlayerSlot) -> String:
	if slot == null:
		return "?"
	return "[color=#%s]%s[/color]" % [slot.color.lightened(0.25).to_html(false), slot.label()]


## Switches to another Shop (RunState.start_run makes a new one per run).
func set_shop(p_shop: Shop) -> void:
	if shop == p_shop:
		return
	if shop != null and shop.changed.is_connected(_on_shop_changed):
		shop.changed.disconnect(_on_shop_changed)
	if shop != null and shop.rerolled.is_connected(_on_shop_rerolled):
		shop.rerolled.disconnect(_on_shop_rerolled)
	shop = p_shop
	if shop != null:
		shop.changed.connect(_on_shop_changed)
		shop.rerolled.connect(_on_shop_rerolled)
	_rebuild_cards()


## Rebuilds the offer cards and cursors for the joined slots (price colours and the gold line
## included, so a pending wallet catch-up is dropped).
func refresh(slots: Array[PlayerSlot]) -> void:
	_gold_stale = false
	_slots.clear()
	for s in slots:
		if s != null:
			_slots.append(s)
	_slots.sort_custom(func(a: PlayerSlot, b: PlayerSlot) -> bool: return a.index < b.index)
	_rebuild_cards()
	var keep: Dictionary[int, bool] = {}
	for s in _slots:
		keep[s.index] = true
		if not _cursor.has(s.index):
			_cursor[s.index] = _start_cursor(s.index)
		if not _active.has(s.index):
			_active[s.index] = true
		if not _tooltips.has(s.index):
			var tip := ItemTooltip.create()
			tip.name = "Tooltip%d" % (s.index + 1)
			tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tip.visible = false
			tip.scale = Vector2(TOOLTIP_SCALE, TOOLTIP_SCALE)
			_tooltip_layer.add_child(tip)
			_tooltips[s.index] = tip
	for i: int in _cursor.keys():
		if not keep.has(i):
			_cursor.erase(i)
			_active.erase(i)
			_holds.erase(i)
	for i: int in _tooltips.keys():
		if not keep.has(i):
			var tip := _tooltips[i]
			_tooltips.erase(i)
			_tooltip_keys.erase(i)
			_tooltip_layer.remove_child(tip)
			tip.queue_free()
	for i: int in _cursor.keys():
		_cursor[i] = clampi(_cursor[i], 0, maxi(0, cards.size() - 1))
	_tooltip_keys.clear()
	_watch_equipment()
	_update_info()
	_cursor_layer.queue_redraw()


## Called once per frame by the Intermission before the handle_input calls (hold timers).
func begin_frame(delta: float) -> void:
	_frame_delta = delta
	_input_lockout = maxf(0.0, _input_lockout - delta)


## A (buy) and X (lock) are ignored for [param seconds] (the Intermission calls it when the
## market opens: a Need / Buy press or a stick push meant for the loot roll must not act in
## the shop). The lockout runs down in [method begin_frame].
func lock_input(seconds: float) -> void:
	_input_lockout = maxf(_input_lockout, seconds)


func is_input_locked() -> bool:
	return _input_lockout > 0.0


## Called every _process frame by the Intermission for a slot whose focus is the shop.
func handle_input(slot: PlayerSlot) -> void:
	last_input_consumed = false
	if slot == null or slot.input == null or shop == null:
		return
	var inp := slot.input
	var i := slot.index
	if not _cursor.has(i):
		_cursor[i] = _start_cursor(i)
	var dt := _frame_delta if _frame_delta >= 0.0 else get_process_delta_time()
	var nav := inp.nav_just_pressed()
	if nav != Vector2i.ZERO:
		_move_cursor(i, nav)
		_raise_tooltip(i)
	var locked := _input_lockout > 0.0
	if _holds.has(i):
		var hold := _holds[i]
		var cancel_b := inp.just_pressed(PlayerInput.Pad.B)
		if cancel_b:
			last_input_consumed = true  # B cancels the hold; it does not also unready
		if not inp.is_pressed(PlayerInput.Pad.A) or int(hold["offer"]) != cursor_of(i) or cancel_b \
				or not _hold_matches_offer(hold):
			_holds.erase(i)
		else:
			hold["time"] = float(hold["time"]) + dt
			if float(hold["time"]) >= HOLD_TIME:
				_holds.erase(i)
				try_buy(slot, int(hold["offer"]))
	elif inp.just_pressed(PlayerInput.Pad.A) and not locked:
		_press_buy(slot)
		_raise_tooltip(i)
	if inp.just_pressed(PlayerInput.Pad.X) and not locked:
		_toggle_lock(slot)
	if inp.just_pressed(PlayerInput.Pad.R3):
		_toggle_ping(slot)
	if inp.just_pressed(PlayerInput.Pad.Y):
		_vote(slot)


# --- Public helpers -------------------------------------------------------------------

func cursor_of(slot_index: int) -> int:
	return _cursor.get(slot_index, -1)


func set_cursor(slot_index: int, offer_index: int) -> void:
	_cursor[slot_index] = clampi(offer_index, 0, maxi(0, offer_count() - 1))
	_cursor_layer.queue_redraw()


## False while the player's focus is their own panel: the cursor is dimmed, the tooltip
## hidden and an unfinished hold-to-buy cancelled.
func set_cursor_active(slot_index: int, active: bool) -> void:
	_active[slot_index] = active
	if not active:
		_holds.erase(slot_index)
	_cursor_layer.queue_redraw()


func is_cursor_active(slot_index: int) -> bool:
	return _active.get(slot_index, true)


func offer_count() -> int:
	return shop.offers.size() if shop != null else 0


func offer_at(index: int) -> Shop.Offer:
	if shop == null or index < 0 or index >= shop.offers.size():
		return null
	return shop.offers[index]


## GDD 10: buying something that takes more than half the wallet needs A held for a second.
func needs_hold(price: int) -> bool:
	return price > RunState.gold * HOLD_SHARE


## 0..1 progress of [param slot_index]'s hold-to-buy (0 when not holding).
func hold_progress(slot_index: int) -> float:
	if not _holds.has(slot_index):
		return 0.0
	return clampf(float(_holds[slot_index]["time"]) / HOLD_TIME, 0.0, 1.0)


## Why [param slot] cannot buy offer [param index] right now ("" = it can).
func buy_block_reason(slot: PlayerSlot, index: int) -> String:
	var o := offer_at(index)
	if o == null or o.item == null:
		return "Nothing there"
	if o.sold:
		return "Already sold"
	if RunState.gold < o.price:
		return "Not enough gold"
	var eq := equipment_of(slot)
	if eq == null:
		return "No hero to carry it"
	if not eq.has_space() and not shop.forges_on_buy(index, slot):
		return "Backpack full"
	return ""


## Buys offer [param index] for [param slot] (no hold check) with feedback. True on success.
## An auto-forge (full backpack, Shop.last_forged) reports and emits the forged weapon.
func try_buy(slot: PlayerSlot, index: int) -> bool:
	var reason := buy_block_reason(slot, index)
	if reason != "":
		_say_to(slot, reason)
		return false
	var o := offer_at(index)
	var item := o.item
	var price := o.price
	if not shop.buy(index, slot):
		_say_to(slot, "The goblin refuses the deal")
		return false
	var forged := shop.last_forged
	if forged != null:
		_say("%s bought and forged %s – %s g" % [player_tag(slot), item_link(forged), UiTheme.format_int(price)],
			"%s bought and forged [%s] – %d g" % [slot.label(), forged.display_name, price])
		item = forged
	else:
		_say("%s bought %s – %s g" % [player_tag(slot), item_link(item), UiTheme.format_int(price)],
			"%s bought [%s] – %d g" % [slot.label(), item.display_name, price])
	item_bought.emit(slot.index, item)
	_update_cards()
	return true


## Index of the cheapest unsold offer [param slot]'s class can use and the wallet can pay
## (-1 = none) – what a bot buys.
func cheapest_offer_for(slot: PlayerSlot) -> int:
	var best := -1
	var best_price := 0
	if slot == null or shop == null:
		return -1
	for i in shop.offers.size():
		var o := shop.offers[i]
		if o == null or o.item == null or o.sold or RunState.gold < o.price:
			continue
		if not o.item.can_be_used_by(slot.class_data):
			continue
		if best < 0 or o.price < best_price:
			best = i
			best_price = o.price
	return best


## Slot indices whose vote a reroll needs: humans with a working device (bots and unplugged
## controllers never block it).
func voter_indices() -> Array[int]:
	var out: Array[int] = []
	for s in _slots:
		if not s.is_bot() and s.input != null and s.input.is_connected_device():
			out.append(s.index)
	return out


## Evaluates the standing reroll votes (the Intermission calls it every frame while there are
## any): votes of players who are no longer voters (left, pad unplugged) are dropped, and the
## reroll fires once every remaining voter has voted and the wallet can pay – also when the
## last missing voter unplugged or the gold arrived after the last vote. True if it rerolled.
func process_votes() -> bool:
	if shop == null or shop.reroll_votes.is_empty():
		return false
	var voters := voter_indices()
	shop.prune_votes(voters)
	var cost := shop.reroll_cost()
	if shop.try_reroll(voters, RunState.rng):
		_say("The goblin restocks the stall (–%d g)" % cost, "Rerolled for %d g" % cost)
		return true
	return false


## An unplugged human pad (bots and working pads are "present"). Its cursor and tooltip are
## hidden: nobody is moving them.
static func is_unplugged(slot: PlayerSlot) -> bool:
	return slot != null and not slot.is_bot() and slot.input != null and not slot.input.is_connected_device()


func _slot_of(slot_index: int) -> PlayerSlot:
	for s in _slots:
		if s.index == slot_index:
			return s
	return null


## The feedback log as plain text, oldest first (tests, screenshots).
func feedback_lines() -> Array[String]:
	var out: Array[String] = []
	for f in _feedback:
		out.append(String(f["plain"]))
	return out


## The tooltip shown for [param slot_index] (null if none).
func tooltip_of(slot_index: int) -> ItemTooltip:
	return _tooltips.get(slot_index)


# --- Build ------------------------------------------------------------------------------

func _build() -> void:
	theme = UiTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = STALL_SIZE
	size = STALL_SIZE

	_body = UiTheme.panel()
	var style := UiTheme.stone_style(UiTheme.GOLD_BORDER, Color(0.15, 0.1, 0.065, 0.97))
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 26
	style.content_margin_bottom = 12
	style.inner_shadow = 18
	_body.add_theme_stylebox_override(&"panel", style.rebuild())
	_body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_body.offset_left = 10
	_body.offset_right = -10
	_body.offset_top = BODY_TOP
	add_child(_body)
	var col := UiTheme.vbox(8)
	_body.add_child(col)

	# Shared gold (left) and the reroll vote (right).
	var info := UiTheme.hbox(10)
	info.custom_minimum_size = Vector2(0, 34)
	col.add_child(info)
	var coin := UiIcon.create(UiIcon.Kind.COIN, Vector2(28, 28))
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_child(coin)
	_gold_label = UiTheme.label("0", UiTheme.GOLD_LABEL, 28)
	_gold_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_child(_gold_label)
	var shared := UiTheme.label("shared gold", UiTheme.SMALL, 15)
	shared.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_child(shared)
	info.add_child(UiTheme.spacer())
	_pips = Control.new()
	_pips.name = "RerollPips"
	_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pips.custom_minimum_size = Vector2(24, 24)
	_pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pips.draw.connect(_draw_pips)
	info.add_child(_pips)
	_reroll_label = UiTheme.label("", &"", 16, UiTheme.TEXT)
	_reroll_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_child(_reroll_label)

	# The counter with the offer grid and the cursor overlay on top of it.
	var counter := UiTheme.panel(UiTheme.INSET_PANEL)
	var cs := UiTheme.inset_style()
	cs.fill = Color(0.06, 0.045, 0.035, 0.9)
	cs.content_margin_left = 10
	cs.content_margin_right = 10
	cs.content_margin_top = 12
	cs.content_margin_bottom = 12
	counter.add_theme_stylebox_override(&"panel", cs.rebuild())
	counter.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(counter)
	var stack := MarginContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	counter.add_child(stack)
	_grid = GridContainer.new()
	_grid.name = "Offers"
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.add_theme_constant_override(&"h_separation", CARD_GAP)
	_grid.add_theme_constant_override(&"v_separation", 12)
	_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stack.add_child(_grid)
	_cursor_layer = Control.new()
	_cursor_layer.name = "Cursors"
	_cursor_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_layer.draw.connect(_draw_cursors)
	stack.add_child(_cursor_layer)

	# Feedback / spending log.
	var log_box := UiTheme.vbox(0)
	log_box.custom_minimum_size = Vector2(0, FEEDBACK_LINES * 25)
	col.add_child(log_box)
	for i in FEEDBACK_LINES:
		var l := RichTextLabel.new()
		l.bbcode_enabled = true
		l.fit_content = true
		l.scroll_active = false
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_size_override(&"normal_font_size", 19)
		l.custom_minimum_size = Vector2(0, 25)
		log_box.add_child(l)
		_feedback_labels.append(l)

	# Controls.
	var r3 := UiGlyph.pad(PlayerInput.Pad.LB, 26.0)
	r3.text = "R3"
	col.add_child(UiTheme.prompt_row([
		[UiGlyph.nav(26.0), "Move"],
		[UiGlyph.pad(PlayerInput.Pad.A, 26.0), "Buy"],
		[UiGlyph.pad(PlayerInput.Pad.X, 26.0), "Lock"],
		[r3, "Ping"],
		[UiGlyph.pad(PlayerInput.Pad.Y, 26.0), "Reroll vote"],
	], 18, UiTheme.TEXT_DIM))
	var keys := UiTheme.centered_label("Keyboard: Enter buy · R lock · Tab ping · C reroll · Q / E panel · P ready",
		UiTheme.SMALL, 16)
	col.add_child(keys)

	# The awning, sign and goblin on top of the body's upper edge.
	_art = ShopMerchant.create()
	_art.anchor_right = 1.0
	_art.offset_bottom = _art.custom_minimum_size.y
	add_child(_art)

	_tooltip_layer = Control.new()
	_tooltip_layer.name = "Tooltips"
	_tooltip_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tooltip_layer.z_index = 10
	add_child(_tooltip_layer)


func _enter_tree() -> void:
	if not RunState.gold_changed.is_connected(_on_gold_changed):
		RunState.gold_changed.connect(_on_gold_changed)


func _exit_tree() -> void:
	if RunState.gold_changed.is_connected(_on_gold_changed):
		RunState.gold_changed.disconnect(_on_gold_changed)


## Wooden posts behind the stall body.
func _draw() -> void:
	for x in [0.0, size.x - 18.0]:
		var r := Rect2(x, ShopMerchant.AWNING_BOTTOM - 20.0, 18.0, size.y - ShopMerchant.AWNING_BOTTOM + 14.0)
		draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(0, 0, 0, 0.4))
		draw_rect(r, ShopMerchant.WOOD)
		draw_rect(Rect2(r.position, Vector2(4, r.size.y)), ShopMerchant.WOOD_LIGHT)
		draw_rect(r, ShopMerchant.LINE, false, 2.0)


# --- Cards --------------------------------------------------------------------------

func _rebuild_cards() -> void:
	if _grid == null:
		return
	var n := offer_count()
	columns = n if n <= 4 else clampi(ceili(n / 2.0), 1, MAX_COLUMNS)
	_grid.columns = maxi(1, columns)
	while cards.size() > n:
		var c: ShopOfferCard = cards.pop_back()
		_grid.remove_child(c)
		c.queue_free()
	while cards.size() < n:
		var c := ShopOfferCard.create(cards.size())
		_grid.add_child(c)
		cards.append(c)
	for i in n:
		cards[i].set_offer(shop.offers[i], _slots)
	_holds.clear()
	_tooltip_keys.clear()
	_cursor_layer.queue_redraw()


## Price colours, locks, pings, sold stamps (and new items after a reroll).
func _update_cards() -> void:
	if offer_count() != cards.size():
		_rebuild_cards()
		return
	for i in cards.size():
		var o := shop.offers[i]
		if cards[i].offer != o or (o != null and cards[i].icon.item != o.item):
			cards[i].set_offer(o, _slots)
		else:
			cards[i].update_state()
	_cursor_layer.queue_redraw()


func _on_shop_changed() -> void:
	_validate_holds()
	_update_cards()
	_update_info()


## A reroll swapped the offers under the cursors: no hold-to-buy may carry over to the new item.
func _on_shop_rerolled(_count: int) -> void:
	_holds.clear()
	_cursor_layer.queue_redraw()


## True while the offer at the hold's cursor position is still the item (and price) the hold
## started on.
func _hold_matches_offer(hold: Dictionary) -> bool:
	var o := offer_at(int(hold["offer"]))
	return o != null and o.item != null and not o.sold and o.item.uid == int(hold["uid"]) \
		and o.price == int(hold["price"])


## Cancels the holds whose offer changed (rerolled, restocked, sold) and those of unplugged pads.
func _validate_holds() -> void:
	for i: int in _holds.keys():
		var s := _slot_of(i)
		if s == null or is_unplugged(s) or not _hold_matches_offer(_holds[i]):
			_holds.erase(i)


func _on_gold_changed(_gold: int, _delta: int) -> void:
	if not is_visible_in_tree():
		_gold_stale = true
		return
	_gold_stale = false
	for c in cards:
		c.update_state()
	_update_info()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and _gold_stale and is_visible_in_tree():
		_catch_up_gold.call_deferred()


## The stale panel was shown: updates the prices and the gold line at the end of the frame,
## unless refresh() did already (the market start refreshes right after showing the panel) or
## the panel was hidden again in the same frame (Intermission.open before the loot roll).
func _catch_up_gold() -> void:
	if _gold_stale and is_visible_in_tree():
		_on_gold_changed(RunState.gold, 0)


func _watch_equipment() -> void:
	for eq in _watched:
		if eq != null and eq.changed.is_connected(_on_equipment_changed):
			eq.changed.disconnect(_on_equipment_changed)
	_watched.clear()
	for s in _slots:
		var eq := equipment_of(s)
		if eq != null:
			eq.changed.connect(_on_equipment_changed)
			_watched.append(eq)


func _on_equipment_changed() -> void:
	_cards_dirty = true


func _update_info() -> void:
	if _gold_label == null:
		return
	_gold_label.text = UiTheme.format_int(RunState.gold)
	if shop == null:
		_reroll_label.text = ""
		return
	var cost := shop.reroll_cost()
	_reroll_label.text = "Reroll: %d g – all players must vote (Y)" % cost
	_reroll_label.add_theme_color_override(&"font_color", UiTheme.TEXT if RunState.gold >= cost else UiTheme.RED.lightened(0.1))
	_pips.custom_minimum_size = Vector2(maxi(1, _slots.size()) * 22.0, 24.0)
	_pips.queue_redraw()


func _start_cursor(slot_index: int) -> int:
	var n := offer_count()
	if n <= 0:
		return 0
	var cols := maxi(1, columns)
	var rows := ceili(float(n) / cols)
	match slot_index:
		1:
			return mini(cols - 1, n - 1)
		2:
			return clampi((rows - 1) * cols, 0, n - 1) if rows > 1 else mini(1, n - 1)
		3:
			return n - 1
	return 0


func _move_cursor(slot_index: int, dir: Vector2i) -> void:
	var n := offer_count()
	if n <= 0:
		return
	var cols := maxi(1, columns)
	var cur := clampi(cursor_of(slot_index), 0, n - 1)
	var col := cur % cols
	var row := cur / cols
	if dir.x != 0:
		var nc := col + dir.x
		if nc >= 0 and nc < cols and row * cols + nc < n:
			cur = row * cols + nc
	if dir.y != 0:
		var nr := row + dir.y
		if nr >= 0 and nr * cols < n:
			cur = mini(nr * cols + col, n - 1)
	if cur != cursor_of(slot_index):
		_holds.erase(slot_index)
	set_cursor(slot_index, cur)


# --- Actions ------------------------------------------------------------------------

func _press_buy(slot: PlayerSlot) -> void:
	var index := cursor_of(slot.index)
	var o := offer_at(index)
	if o == null or o.item == null:
		return
	var reason := buy_block_reason(slot, index)
	if reason != "":
		_say_to(slot, reason)
		return
	if needs_hold(o.price):
		_holds[slot.index] = {"offer": index, "time": 0.0, "uid": o.item.uid, "price": o.price}
		return
	try_buy(slot, index)


func _toggle_lock(slot: PlayerSlot) -> void:
	var index := cursor_of(slot.index)
	var o := offer_at(index)
	if o == null or o.item == null or o.sold:
		return
	shop.toggle_lock(index, slot.index)
	if o.locked_by >= 0:
		_say("%s locked %s for the next round" % [player_tag(slot), item_link(o.item)],
			"%s locked [%s]" % [slot.label(), o.item.display_name])


func _toggle_ping(slot: PlayerSlot) -> void:
	var index := cursor_of(slot.index)
	var o := offer_at(index)
	if o == null or o.item == null or o.sold:
		return
	shop.toggle_ping(index, slot.index)
	if slot.index in o.pinged_by:
		_say("%s wants: %s – %s g" % [player_tag(slot), item_link(o.item), UiTheme.format_int(o.price)],
			"%s wants: [%s] – %d g" % [slot.label(), o.item.display_name, o.price])


func _vote(slot: PlayerSlot) -> void:
	var voters := voter_indices()
	var cost := shop.reroll_cost()
	var had := shop.reroll_votes.has(slot.index)
	if shop.vote_reroll(slot.index, voters, RunState.rng):
		_say("The goblin restocks the stall (–%d g)" % cost, "Rerolled for %d g" % cost)
		return
	if had:
		return
	var all := true
	for i in voters:
		if not shop.reroll_votes.get(i, false):
			all = false
	if all and RunState.gold < cost:
		_say_to(slot, "Not enough gold to reroll")
	_update_info()


func _say(bb: String, plain: String) -> void:
	_feedback.append({"bb": bb, "plain": plain, "age": 0.0})
	while _feedback.size() > FEEDBACK_LINES:
		_feedback.pop_front()
	_feedback_dirty = true


## A message for one player ("P2: Backpack full").
func _say_to(slot: PlayerSlot, text: String) -> void:
	_say("%s: [color=#%s]%s[/color]" % [player_tag(slot), UiTheme.RED.lightened(0.25).to_html(false), bb_escape(text)],
		"%s: %s" % [slot.label() if slot != null else "?", text])


# --- Frame --------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if _cards_dirty:
		_cards_dirty = false
		for i in cards.size():
			cards[i].set_offer(shop.offers[i] if i < offer_count() else null, _slots)
	var expired := false
	for f in _feedback:
		f["age"] = float(f["age"]) + delta
		if float(f["age"]) > FEEDBACK_TIME:
			expired = true
	if expired:
		_feedback = _feedback.filter(func(f: Dictionary) -> bool: return float(f["age"]) <= FEEDBACK_TIME)
		_feedback_dirty = true
	if _feedback_dirty:
		_feedback_dirty = false
		for i in _feedback_labels.size():
			var at := _feedback.size() - _feedback_labels.size() + i
			_feedback_labels[i].text = "[center]%s[/center]" % _feedback[at]["bb"] if at >= 0 else ""
	for i in _feedback_labels.size():
		var at := _feedback.size() - _feedback_labels.size() + i
		if at >= 0:
			var age := float(_feedback[at]["age"])
			_feedback_labels[i].modulate.a = 1.0 - smoothstep(FEEDBACK_TIME - 1.0, FEEDBACK_TIME, age)
	if not _holds.is_empty():
		_validate_holds()
	_update_tooltips()
	if not _holds.is_empty() or is_visible_in_tree():
		_cursor_layer.queue_redraw()


func _update_tooltips() -> void:
	for s in _slots:
		var tip: ItemTooltip = _tooltips.get(s.index)
		if tip == null:
			continue
		var o := offer_at(cursor_of(s.index))
		var show := is_cursor_active(s.index) and not is_unplugged(s) and o != null and o.item != null \
			and not o.sold
		if not show:
			tip.visible = false
			_tooltip_keys.erase(s.index)
			continue
		var compare := ItemTooltip.equipped_for_compare(o.item, equipment_of(s))
		var key := "%d:%d:%d" % [o.item.uid, o.price, compare.uid if compare != null else 0]
		if _tooltip_keys.get(s.index, "") != key:
			_tooltip_keys[s.index] = key
			tip.owner_tag = "P%d" % (s.index + 1)
			tip.owner_color = s.color
			tip.viewer_equipment = equipment_of(s)
			tip.show_item(o.item, s.class_data, compare, o.price)
			tip.reset_size()
		tip.visible = true
	layout_tooltips()


## Places every visible tooltip at the first free candidate spot, largest scale first. The
## player who acted last is placed first (the one browsing gets the best, full-size spot);
## the others take what is left. A corner panel's tooltip that reaches into a free band
## ([member tooltip_obstacles]) is there first: a spot over it counts COVER_WEIGHT times.
func layout_tooltips() -> void:
	var placed: Array[Rect2] = []
	var blocked: Array[Rect2] = []
	if tooltip_obstacles.is_valid():
		blocked.assign(tooltip_obstacles.call())
	var areas := tooltip_areas()
	var order: Array[PlayerSlot] = []
	for i in range(_act_order.size() - 1, -1, -1):
		for s in _slots:
			if s.index == _act_order[i]:
				order.append(s)
	for s in _slots:
		if s not in order:
			order.append(s)
	for s in order:
		var tip: ItemTooltip = _tooltips.get(s.index)
		var index := cursor_of(s.index)
		if tip == null or not tip.visible or index < 0 or index >= cards.size():
			continue
		var raw := tip.get_combined_minimum_size().max(tip.size)
		var card := cards[index].get_global_rect()
		var best := Rect2()
		var best_scale := TOOLTIP_SCALES[-1]
		var best_overlap := INF
		for scale_value in TOOLTIP_SCALES:
			var tsize := raw * scale_value
			for r in _candidates(tsize, card, index, s.index, areas):
				var overlap := _overlap(r, placed) + _overlap(r, blocked) * COVER_WEIGHT \
						+ (r.intersection(card).get_area() * COVER_WEIGHT if r.intersects(card) else 0.0)
				if overlap < best_overlap - 0.5:
					best_overlap = overlap
					best = r
					best_scale = scale_value
				if overlap <= 0.0:
					break
			if best_overlap <= 0.0:
				break
		tip.scale = Vector2.ONE * best_scale
		tip.position = best.position - global_position
		placed.append(best)


## Screen rects tooltips may use: the stall body and the free bands between the top and the
## bottom corner panels on both sides (from the Intermission's panel geometry).
func tooltip_areas() -> Array[Rect2]:
	var out: Array[Rect2] = [Rect2(global_position + Vector2(0.0, BODY_TOP), Vector2(size.x, size.y - BODY_TOP))
			.grow(-TOOLTIP_MARGIN)]
	if not is_inside_tree():
		return out
	var vp := get_viewport_rect().size
	var panel := PlayerPanel.DESIGN_SIZE * Intermission.panel_scale(PlayerPanel.DESIGN_SIZE)
	var top := Intermission.MARGIN + panel.y + TOOLTIP_GAP
	var height := vp.y - 2.0 * (Intermission.MARGIN + panel.y + TOOLTIP_GAP)
	var left_w := global_position.x - Intermission.MARGIN - TOOLTIP_GAP
	if height > 40.0 and left_w > 40.0:
		out.append(Rect2(Intermission.MARGIN, top, left_w, height))
		var right_x := global_position.x + size.x + TOOLTIP_GAP
		out.append(Rect2(right_x, top, vp.x - Intermission.MARGIN - right_x, height))
	return out


## Candidate rects (global) for a tooltip of [param tsize] next to [param card], in order of
## preference, each clamped into one of [param areas] (dropped when it does not fit).
func _candidates(tsize: Vector2, card: Rect2, index: int, slot_index: int, areas: Array[Rect2]) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var stall := areas[0]
	# < 0: left half of the grid, 0: middle column, > 0: right half.
	var side := (index % maxi(1, columns)) * 2 - (columns - 1)
	var right_first := side < 0 or (side == 0 and slot_index % 2 == 0)
	var top_row := index < columns
	var y_row := card.position.y if top_row else card.end.y - tsize.y
	var right_x := card.end.x + TOOLTIP_GAP
	var left_x := card.position.x - TOOLTIP_GAP - tsize.x
	for x in ([right_x, left_x] if right_first else [left_x, right_x]):
		out.append(Rect2(Vector2(x, y_row), tsize))
	# Below a top-row card / above a bottom-row card.
	var y_off := card.end.y + TOOLTIP_GAP if top_row else card.position.y - TOOLTIP_GAP - tsize.y
	out.append(Rect2(Vector2(card.get_center().x - tsize.x * 0.5, y_off), tsize))
	# The free bands between the corner panels: the player's own side first (P1 / P3 left,
	# P2 / P4 right), its outer edge for P1 / P2 and inner edge for P3 / P4 (so the two
	# players of a side sit next to each other), top for P1 / P2, bottom for P3 / P4.
	var own_band := 1 if slot_index % 2 == 0 else 2
	var outer_first := slot_index < 2
	for b in [own_band, 3 - own_band]:
		if b >= areas.size():
			continue
		var band := areas[b]
		var outer_x := band.position.x if b == 1 else band.end.x - tsize.x
		var inner_x := band.end.x - tsize.x if b == 1 else band.position.x
		var top_first := slot_index < 2
		for x in ([outer_x, inner_x] if outer_first else [inner_x, outer_x]):
			for y in ([band.position.y, band.end.y - tsize.y] if top_first else [band.end.y - tsize.y, band.position.y]):
				out.append(Rect2(Vector2(x, y), tsize))
	var fitted: Array[Rect2] = []
	for r in out:
		var area := _area_for(r, areas, stall)
		if area.size.x + 0.5 >= tsize.x and area.size.y + 0.5 >= tsize.y:
			var p := Vector2(clampf(r.position.x, area.position.x, area.end.x - tsize.x),
					clampf(r.position.y, area.position.y, area.end.y - tsize.y))
			fitted.append(Rect2(p, tsize))
	return fitted


## The area [param r] mostly lies in (the stall when none).
static func _area_for(r: Rect2, areas: Array[Rect2], stall: Rect2) -> Rect2:
	var best := stall
	var best_a := -1.0
	for a in areas:
		var share := a.intersection(r).get_area() if a.intersects(r) else 0.0
		if share > best_a:
			best_a = share
			best = a
	return best


static func _overlap(r: Rect2, placed: Array[Rect2]) -> float:
	var total := 0.0
	for o in placed:
		if o.intersects(r):
			total += o.intersection(r).get_area()
	return total


## The tooltip of the player who acted last is drawn on top of the others.
func _raise_tooltip(slot_index: int) -> void:
	_act_order.erase(slot_index)
	_act_order.append(slot_index)
	var tip: ItemTooltip = _tooltips.get(slot_index)
	if tip != null and tip.get_parent() == _tooltip_layer:
		_tooltip_layer.move_child(tip, -1)


# --- Drawing ------------------------------------------------------------------------

func _draw_pips() -> void:
	var x := 12.0
	var cy := _pips.size.y * 0.5
	for s in _slots:
		var c := Vector2(x, cy)
		var voted: bool = shop != null and shop.reroll_votes.get(s.index, false)
		var auto: bool = s.is_bot() or s.input == null or not s.input.is_connected_device()
		_pips.draw_circle(c, 9.0, Color(0.05, 0.04, 0.03, 0.95))
		if voted:
			_pips.draw_circle(c, 8.0, s.color)
			_pips.draw_polyline(PackedVector2Array([c + Vector2(-4, 0), c + Vector2(-1, 3.5), c + Vector2(4.5, -3.5)]), Color.WHITE, 2.0, true)
		elif auto:
			_pips.draw_circle(c, 7.0, Color(s.color, 0.3))
		_pips.draw_arc(c, 9.0, 0.0, TAU, 24, s.color.lightened(0.2), 2.0, true)
		x += 22.0


func _draw_cursors() -> void:
	var layer := _cursor_layer
	var origin := layer.global_position
	var per_card: Dictionary[int, Array] = {}
	for s in _slots:
		var idx := cursor_of(s.index)
		if idx < 0 or idx >= cards.size() or is_unplugged(s):
			continue
		if not per_card.has(idx):
			per_card[idx] = []
		per_card[idx].append(s)
	var font := UiTheme.bold_font()
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	for idx: int in per_card:
		var card := cards[idx]
		var r := Rect2(card.global_position - origin, card.size)
		var list: Array = per_card[idx]
		# Inactive cursors (focus on the own panel) first, so the active ones draw on top.
		list.sort_custom(func(a: PlayerSlot, b: PlayerSlot) -> bool:
			var aa := is_cursor_active(a.index)
			var bb := is_cursor_active(b.index)
			return (not aa and bb) or (aa == bb and a.index < b.index))
		for k in list.size():
			var s: PlayerSlot = list[k]
			var active := is_cursor_active(s.index)
			var col := s.color.lightened(0.15)
			var rr := r.grow(5.0 - 4.0 * k)
			if not active:
				layer.draw_rect(rr, Color(col, 0.35), false, 2.0)
				continue
			layer.draw_rect(rr.grow(2.0), Color(col, 0.18 + 0.12 * pulse), false, 4.0)
			layer.draw_rect(rr, col, false, 3.0)
			_draw_corner_tag(layer, rr, s, col, font)
	for slot_index: int in _holds:
		var idx := cursor_of(slot_index)
		if idx < 0 or idx >= cards.size():
			continue
		var card := cards[idx]
		var s := PlayerManager.get_slot(slot_index)
		var col := s.color.lightened(0.2) if s != null else UiTheme.GOLD
		var c := card.global_position - origin + Vector2(card.size.x * 0.5, 10.0 + ShopOfferCard.ICON_SIZE * 0.5)
		var progress := hold_progress(slot_index)
		layer.draw_circle(c, 46.0, Color(0, 0, 0, 0.45))
		layer.draw_arc(c, 42.0, 0.0, TAU, 48, Color(0, 0, 0, 0.7), 8.0, true)
		layer.draw_arc(c, 42.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 48, col, 6.0, true)
		var text := "Hold"
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		layer.draw_string_outline(font, c + Vector2(-w * 0.5, 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, UiTheme.OUTLINE)
		layer.draw_string(font, c + Vector2(-w * 0.5, 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)


## "P1" tag on the corner of the cursor outline that matches the player's screen corner
## (P1 top-left, P2 top-right, P3 bottom-left, P4 bottom-right), so stacked cursors on one
## card stay distinguishable.
func _draw_corner_tag(layer: Control, r: Rect2, s: PlayerSlot, col: Color, font: Font) -> void:
	var text := s.label()
	var fs := 15
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 10.0
	var h := 19.0
	var right := s.index % 2 == 1
	var bottom := s.index >= 2
	var corner := Vector2(r.end.x if right else r.position.x, r.end.y if bottom else r.position.y)
	# Inside the card's width (neighbouring cards' tags never collide), across the edge.
	var tag := Rect2(corner + Vector2(-w - 3.0 if right else 3.0, -h * 0.5), Vector2(w, h))
	layer.draw_rect(tag, col.darkened(0.25))
	layer.draw_rect(tag, Color(0, 0, 0, 0.7), false, 1.5)
	var base := tag.position + Vector2(5.0, h - 4.5)
	layer.draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, UiTheme.OUTLINE)
	layer.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
