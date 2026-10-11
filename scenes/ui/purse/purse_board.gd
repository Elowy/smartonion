class_name PurseBoard
extends PanelContainer
## The purse board (GDD 10 "Coordination tools", M5) in the Intermission header: the shared
## wallet and what the team does with it, so a shared purse does not end in chaos.
##
##   wallet – the coin and the shared gold ([member gold_value]); under it the ready pips (one
##            diamond per joined player in their colour, filled once that player is ready – the
##            GDD's "ready state next to the wallet") and "2/4 ready".
##   Spent  – this round's spend ticker (RunState.spend_log, newest first): who, what, how much
##            ("P1 [Rare Dagger] 62 · P2 Fireball Rank III 45 · Team Stall reroll 12"), at most
##            [constant TICKER_LINES] lines, the rest summed up as "+N more". Every wallet spend
##            is in it – shop buys, auto-forges, stall rerolls ("Team"), Trainer ranks, level-up
##            rerolls, talent resets: everything that goes through RunState.try_spend_for.
##            Selling and Greed gold are income, not spends.
##   Wants  – the shop pings (Shop.Offer.pinged_by of the unsold offers) and the Trainer pings
##            (RunState.wants) merged in slot order: "P2 [Rare Dagger] 62 g · P4 Fireball Rank
##            III 45 g" on one line, then "+N more". Buying the thing or a new round clears a want.
##
## Shop items show as "[Name]" in their rarity colour while the stall still lists the offer
## (sold offers stay until the next round), else in plain text colour. Entries are packed into
## the lines by their measured width ([method pack]), so no line runs out of the board.
## The texts are rebuilt only when something changed: RunState.spent / wants_changed and
## Shop.changed mark them dirty, [method update] (every MARKET frame, from the Intermission)
## or [method refresh] rebuilds them – nothing happens while the Intermission waits hidden
## through a wave. [method refresh] is also how a new round shows (RunState.begin_spend_round
## clears the log without a signal). No RNG.

## The board's design width (the stall's width; fits between the two top corner panels).
const WIDTH := 712.0
const WALLET_WIDTH := 96.0
const CAPTION_WIDTH := 52.0
const TEXT_FONT := 16
const CAPTION_FONT := 15
## Height of one text line and how far neighbouring lines overlap (the font's line box has
## room to spare above the capitals, so the three lines can sit closer).
const LINE_HEIGHT := 23.0
const LINE_OVERLAP := 4
const TICKER_LINES := 2
const SEPARATOR := " · "
## Room kept free at the end of every line (the text outline).
const LINE_SLACK := 6.0
const EMPTY_TICKER := "Nothing spent yet this round"
const EMPTY_WANTS := "None – ping an offer or a Trainer rank (R3 / Tab)"
const TEAM := "Team"
## Layout: the board's side margins, the gaps around the rule after the wallet, the rule's width
## and the gap between the captions and the lines.
const MARGIN_X := 10.0
const RULE_GAP := 8.0
const RULE_WIDTH := 2.0
const CAPTION_GAP := 6.0

## The shared gold (the Intermission's gold_value).
var gold_value: Label
var pips: ReadyPips
## "2/4 ready".
var ready_label: Label
var ticker_labels: Array[RichTextLabel] = []
var wants_label: RichTextLabel
## The Shop whose pings feed the wants line (the Intermission passes RunState.shop).
var shop: Shop

## Plain text of the ticker lines and of the wants line (tests, screenshots).
var _ticker_plain: Array[String] = []
var _wants_plain := ""
var _dirty := true
var _pip_key := ""


## One diamond per player in their colour, filled while that player is ready.
class ReadyPips extends Control:
	const PIP := 16.0
	const GAP := 6.0
	## {"color": Color, "ready": bool} per joined player, slot order.
	var states: Array[Dictionary] = []

	func set_states(p_states: Array[Dictionary]) -> void:
		states = p_states
		custom_minimum_size = Vector2(maxi(1, states.size()) * (PIP + GAP) - GAP, PIP + 2.0)
		queue_redraw()

	func ready_count() -> int:
		var n := 0
		for s in states:
			if bool(s["ready"]):
				n += 1
		return n

	func _draw() -> void:
		var h := PIP * 0.5
		for i in states.size():
			var c := Vector2(i * (PIP + GAP) + h, size.y * 0.5)
			var col: Color = states[i]["color"]
			var pts := PackedVector2Array([c + Vector2(0, -h), c + Vector2(h, 0), c + Vector2(0, h), c + Vector2(-h, 0)])
			var on := bool(states[i]["ready"])
			draw_colored_polygon(pts, col.lightened(0.1) if on else Color(0.05, 0.04, 0.035, 0.92))
			var ring := pts.duplicate()
			ring.append(pts[0])
			draw_polyline(ring, col.lightened(0.45) if on else col, 2.0, true)
			if on:
				var shine := PackedVector2Array([c + Vector2(0, -h + 3), c + Vector2(h - 4, -1), c + Vector2(0, -1)])
				draw_colored_polygon(shine, Color(1, 1, 1, 0.35))


static func create() -> PurseBoard:
	var b := PurseBoard.new()
	b.name = "PurseBoard"
	b._build()
	return b


# --- Formatting (static, pure: the tests use them too) ------------------------------------

## "P2" for a player slot, "Team" for -1 (a stall reroll the whole team voted for).
static func slot_tag(slot_index: int) -> String:
	return TEAM if slot_index < 0 else "P%d" % (slot_index + 1)


## The player's colour (also after they left: PlayerManager.PLAYER_COLORS by slot).
static func slot_color(slot_index: int) -> Color:
	if slot_index < 0 or slot_index >= PlayerManager.PLAYER_COLORS.size():
		return UiTheme.GOLD_BRIGHT
	var s := PlayerManager.get_slot(slot_index)
	return s.color if s != null else PlayerManager.PLAYER_COLORS[slot_index]


## "[Rare Dagger]" for shop items ("[Rare Dagger] (forged)" for an auto-forge), the label as it
## is for every other spend.
static func spend_label(entry: Dictionary) -> String:
	var label := String(entry.get("label", ""))
	var kind := StringName(entry.get("kind", &""))
	if kind == &"shop":
		return "[%s]" % label
	if kind == &"shop_forge":
		var forged := " (forged)"
		if label.ends_with(forged):
			return "[%s]%s" % [label.trim_suffix(forged), forged]
		return "[%s]" % label
	return label


## One ticker entry as plain text: "P1 [Rare Dagger] 62", "Team Stall reroll 12".
static func entry_text(entry: Dictionary) -> String:
	return "%s %s %s" % [slot_tag(int(entry.get("slot", -1))), spend_label(entry),
		UiTheme.format_int(int(entry.get("amount", 0)))]


## One wants entry as plain text: "P2 [Rare Dagger] 62 g", "P4 Fireball Rank III 45 g".
static func want_text(want: Dictionary) -> String:
	var label := String(want.get("label", ""))
	if want.get("item") != null:
		label = "[%s]" % label
	return "%s %s %s g" % [slot_tag(int(want.get("slot", -1))), label, UiTheme.format_int(int(want.get("price", 0)))]


## The shop pings of [param p_shop] (unsold offers) and the Trainer pings [param p_wants]
## (RunState.wants) as one list in slot order – per player the shop pings first (stall order),
## then their Trainer pings (in the order they were made): {"slot", "label", "price", "item"
## (the offered ItemInstance; null for a Trainer rank)}. Wants of players who left are skipped.
static func merged_wants(p_shop: Shop, p_wants: Array[Dictionary]) -> Array[Dictionary]:
	var by_slot: Dictionary[int, Array] = {}
	if p_shop != null:
		for o in p_shop.offers:
			if o == null or o.item == null or o.sold:
				continue
			for i in o.pinged_by:
				if not by_slot.has(i):
					by_slot[i] = []
				by_slot[i].append({"slot": i, "label": o.item.display_name, "price": o.price, "item": o.item})
	for w in p_wants:
		var i := int(w.get("slot", -1))
		if not by_slot.has(i):
			by_slot[i] = []
		by_slot[i].append({"slot": i, "label": String(w.get("label", "")), "price": int(w.get("price", 0)), "item": null})
	var out: Array[Dictionary] = []
	var keys := by_slot.keys()
	keys.sort()
	for i: int in keys:
		if PlayerManager.get_slot(i) == null:
			continue
		for d: Dictionary in by_slot[i]:
			out.append(d)
	return out


## Packs entries of the given [param widths] (in order) into at most [param max_lines] lines of
## [param max_width], joined by separators [param sep_width] wide. Entries that do not fit are
## summed up at the end of the last line by a "+N more" tag ([param more_width]: Callable(n) ->
## its width); entries are taken back from the last line until the tag fits. Returns the entry
## count per line (the rest is the "+N more"). An entry wider than a line gets a line of its own
## (the label clips it).
static func pack(widths: Array[float], sep_width: float, more_width: Callable, max_width: float, max_lines: int) -> Array[int]:
	var counts: Array[int] = []
	var used: Array[float] = []
	var placed := 0
	for w in widths:
		if counts.is_empty() or (counts[-1] > 0 and used[-1] + sep_width + w > max_width):
			if counts.size() >= max_lines:
				break
			counts.append(0)
			used.append(0.0)
		used[-1] += w if counts[-1] == 0 else sep_width + w
		counts[-1] += 1
		placed += 1
	var rest := widths.size() - placed
	while rest > 0 and not counts.is_empty() and counts[-1] > 0:
		var tag := float(more_width.call(rest))
		if used[-1] + sep_width + tag <= max_width:
			break
		counts[-1] -= 1
		placed -= 1
		rest += 1
		used[-1] -= widths[placed] if counts[-1] == 0 else sep_width + widths[placed]
	return counts


## "+3 more".
static func more_text(n: int) -> String:
	return "+%d more" % n


# --- Queries --------------------------------------------------------------------------------

## The ticker as plain text, one string per shown line (empty round: the "nothing spent" line).
func ticker_lines() -> Array[String]:
	return _ticker_plain.duplicate()


## The wants line as plain text, without the "Wants" caption.
func wants_text() -> String:
	return _wants_plain


func is_dirty() -> bool:
	return _dirty


## Width of [param text] in the board's text font (what [method pack] measures with).
func text_width(text: String) -> float:
	return _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_FONT).x


## Room for the entries of one line.
static func line_width() -> float:
	return text_column_width() - LINE_SLACK


## Width of the ticker / wants column (the board minus the wallet, the captions and the gaps).
static func text_column_width() -> float:
	return WIDTH - 2.0 * MARGIN_X - WALLET_WIDTH - RULE_GAP * 2.0 - RULE_WIDTH - CAPTION_WIDTH - CAPTION_GAP


# --- Actions --------------------------------------------------------------------------------

## The stall whose pings feed the wants line (a new run makes a new Shop).
func set_shop(p_shop: Shop) -> void:
	if p_shop == shop:
		return
	if shop != null and shop.changed.is_connected(_mark_dirty):
		shop.changed.disconnect(_mark_dirty)
	shop = p_shop
	if shop != null and is_inside_tree():
		shop.changed.connect(_mark_dirty)
	_dirty = true


## Rebuilds the gold, the ticker and the wants line now.
func refresh() -> void:
	_dirty = false
	refresh_gold()
	_fill_ticker()
	_fill_wants()


func refresh_gold() -> void:
	gold_value.text = UiTheme.format_int(RunState.gold)


## Called every MARKET frame: the pips follow [param slots]' ready flags (redrawn only when one
## changed) and dirty texts are rebuilt.
func update(slots: Array[PlayerSlot]) -> void:
	var key := ""
	for s in slots:
		key += "%d:%s:%s," % [s.index, s.ready, s.color.to_html()]
	if key != _pip_key:
		_pip_key = key
		var states: Array[Dictionary] = []
		for s in slots:
			states.append({"color": s.color, "ready": s.ready})
		pips.set_states(states)
		ready_label.text = "%d/%d ready" % [pips.ready_count(), slots.size()]
		ready_label.add_theme_color_override(&"font_color",
			UiTheme.GREEN if not slots.is_empty() and pips.ready_count() == slots.size() else UiTheme.TEXT_DIM)
	if _dirty:
		refresh()


# --- Build ----------------------------------------------------------------------------------

func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.x = WIDTH
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var style := UiTheme.inset_style()
	style.fill = Color(0.06, 0.045, 0.035, 0.93)
	style.border = Color(UiTheme.GOLD_DARK, 0.9)
	style.content_margin_left = MARGIN_X
	style.content_margin_right = MARGIN_X
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	add_theme_stylebox_override(&"panel", style.rebuild())
	var row := UiTheme.hbox(int(RULE_GAP))
	add_child(row)

	# The wallet: coin + gold, the ready pips and the count.
	var wallet := UiTheme.vbox(0)
	wallet.custom_minimum_size.x = WALLET_WIDTH
	wallet.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(wallet)
	var gold_row := UiTheme.hbox(6)
	wallet.add_child(gold_row)
	var coin := UiIcon.create(UiIcon.Kind.COIN, Vector2(22, 22))
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gold_row.add_child(coin)
	gold_value = UiTheme.label("0", UiTheme.GOLD_LABEL, 23, UiTheme.GOLD)
	gold_value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gold_row.add_child(gold_value)
	pips = ReadyPips.new()
	pips.name = "ReadyPips"
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips.set_states([])
	var pip_row := UiTheme.hbox(0)
	pip_row.add_child(pips)
	wallet.add_child(pip_row)
	ready_label = UiTheme.label("", &"", 14, UiTheme.TEXT_DIM)
	wallet.add_child(ready_label)

	var rule := ColorRect.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.color = Color(UiTheme.GOLD_DARK, 0.7)
	rule.custom_minimum_size = Vector2(RULE_WIDTH, 0)
	row.add_child(rule)

	# Captions and lines: Spent (two lines), Wants (one line).
	var lines := UiTheme.hbox(int(CAPTION_GAP))
	row.add_child(lines)
	var captions := UiTheme.vbox(-LINE_OVERLAP)
	captions.custom_minimum_size.x = CAPTION_WIDTH
	lines.add_child(captions)
	var texts := UiTheme.vbox(-LINE_OVERLAP)
	lines.add_child(texts)
	for i in TICKER_LINES + 1:
		var caption := ""
		if i == 0:
			caption = "Spent"
		elif i == TICKER_LINES:
			caption = "Wants"
		var c := UiTheme.label(caption, &"", CAPTION_FONT, UiTheme.GOLD_DARK.lightened(0.45))
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		c.custom_minimum_size.y = LINE_HEIGHT
		c.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		captions.add_child(c)
		var l := _line()
		texts.add_child(l)
		if i < TICKER_LINES:
			ticker_labels.append(l)
		else:
			wants_label = l


func _line() -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = false
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.clip_contents = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override(&"normal_font_size", TEXT_FONT)
	l.add_theme_font_size_override(&"bold_font_size", TEXT_FONT)
	l.custom_minimum_size = Vector2(text_column_width(), LINE_HEIGHT)
	return l


static func _font() -> Font:
	return UiTheme.get_theme().default_font


# --- Filling --------------------------------------------------------------------------------

func _fill_ticker() -> void:
	var entries: Array[Dictionary] = []
	for i in range(RunState.spend_log.size() - 1, -1, -1):
		entries.append(RunState.spend_log[i])
	_ticker_plain.clear()
	for l in ticker_labels:
		l.text = ""
	if entries.is_empty():
		_ticker_plain.append(EMPTY_TICKER)
		ticker_labels[0].text = _dim(EMPTY_TICKER)
		return
	var plain: Array[String] = []
	var bb: Array[String] = []
	for e in entries:
		plain.append(entry_text(e))
		bb.append(_entry_bbcode(e))
	_fill_lines(plain, bb, ticker_labels, _ticker_plain)


func _fill_wants() -> void:
	var wants := merged_wants(shop, RunState.wants)
	if wants.is_empty():
		_wants_plain = ""
		wants_label.text = _dim(EMPTY_WANTS)
		return
	var plain: Array[String] = []
	var bb: Array[String] = []
	for w in wants:
		plain.append(want_text(w))
		bb.append(_want_bbcode(w))
	var lines: Array[String] = []
	_fill_lines(plain, bb, [wants_label] as Array[RichTextLabel], lines)
	_wants_plain = lines[0] if not lines.is_empty() else ""


## Packs [param plain] / [param bb] (the same entries as plain text and BBCode) into
## [param labels], one line each; the plain lines go to [param out].
func _fill_lines(plain: Array[String], bb: Array[String], labels: Array[RichTextLabel], out: Array[String]) -> void:
	var widths: Array[float] = []
	for t in plain:
		widths.append(text_width(t))
	var counts := pack(widths, text_width(SEPARATOR), func(n: int) -> float: return text_width(more_text(n)),
		line_width(), labels.size())
	var at := 0
	for li in counts.size():
		var p: Array[String] = []
		var b: Array[String] = []
		for k in counts[li]:
			p.append(plain[at + k])
			b.append(bb[at + k])
		at += counts[li]
		if li == counts.size() - 1 and at < plain.size():
			p.append(more_text(plain.size() - at))
			b.append(_dim(more_text(plain.size() - at)))
		out.append(SEPARATOR.join(p))
		labels[li].text = _dim(SEPARATOR).join(b)


func _entry_bbcode(entry: Dictionary) -> String:
	var slot := int(entry.get("slot", -1))
	var kind := StringName(entry.get("kind", &""))
	var label := spend_label(entry)
	var label_bb := _color(ShopPanel.bb_escape(label), UiTheme.TEXT)
	if kind == &"shop" or kind == &"shop_forge":
		var name := String(entry.get("label", "")).trim_suffix(" (forged)")
		var item := _offer_item(name, int(entry.get("amount", -1)))
		if item != null:
			label_bb = _color(ShopPanel.bb_escape(label), ShopOfferCard.rarity_color(item))
	return "%s %s %s" % [_tag_bbcode(slot), label_bb, _color(UiTheme.format_int(int(entry.get("amount", 0))), UiTheme.GOLD)]


func _want_bbcode(want: Dictionary) -> String:
	var item: ItemInstance = want.get("item")
	var label := String(want.get("label", ""))
	var label_bb := _color(ShopPanel.bb_escape(label), UiTheme.TEXT)
	if item != null:
		label_bb = _color(ShopPanel.bb_escape("[%s]" % label), ShopOfferCard.rarity_color(item))
	return "%s %s %s" % [_tag_bbcode(int(want.get("slot", -1))), label_bb,
		_color("%s g" % UiTheme.format_int(int(want.get("price", 0))), UiTheme.GOLD)]


## The stall's item named [param name] (preferably at [param price]), sold or not; null if the
## stall no longer lists it.
func _offer_item(name: String, price: int) -> ItemInstance:
	if shop == null:
		return null
	var found: ItemInstance = null
	for o in shop.offers:
		if o == null or o.item == null or o.item.display_name != name:
			continue
		if o.price == price:
			return o.item
		if found == null:
			found = o.item
	return found


static func _tag_bbcode(slot_index: int) -> String:
	var col := slot_color(slot_index)
	return _color(slot_tag(slot_index), col.lightened(0.25) if slot_index >= 0 else UiTheme.GOLD_BRIGHT)


static func _color(text: String, col: Color) -> String:
	return "[color=#%s]%s[/color]" % [col.to_html(false), text]


static func _dim(text: String) -> String:
	return _color(text, UiTheme.TEXT_DIM)


# --- Signals --------------------------------------------------------------------------------

func _mark_dirty(_a: Variant = null) -> void:
	_dirty = true


func _enter_tree() -> void:
	if not RunState.spent.is_connected(_mark_dirty):
		RunState.spent.connect(_mark_dirty)
	if not RunState.wants_changed.is_connected(_mark_dirty):
		RunState.wants_changed.connect(_mark_dirty)
	if shop != null and not shop.changed.is_connected(_mark_dirty):
		shop.changed.connect(_mark_dirty)


func _exit_tree() -> void:
	if RunState.spent.is_connected(_mark_dirty):
		RunState.spent.disconnect(_mark_dirty)
	if RunState.wants_changed.is_connected(_mark_dirty):
		RunState.wants_changed.disconnect(_mark_dirty)
	if shop != null and shop.changed.is_connected(_mark_dirty):
		shop.changed.disconnect(_mark_dirty)
