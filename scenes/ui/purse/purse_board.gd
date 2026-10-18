class_name PurseBoard
extends PanelContainer
## The purse board (GDD 10 "Coordination tools", M5) in the Intermission header: the shared
## wallet and what the team does with it, so a shared purse does not end in chaos.
##
##   wallet – the coin and the shared gold ([member gold_value]) with the team's Arcane Dust (M6a:
##            the sparkle and [member dust_value], right of the gold, violet); under it the ready pips (one
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
##            III 45 g" on the bottom line, then "+N more". While the ticker needs only one line,
##            the wants may take its second one too (the "Wants" caption moves up a row). Buying
##            the thing or a new round clears a want.
##
## Shop items show as "[Name]" in their rarity colour while the stall still lists the offer
## (sold offers stay until the next round), else in plain text colour. Entries are packed into
## the lines by their measured width ([method pack]), so no line runs out of the board.
## The texts are rebuilt only when something changed: RunState.spent / wants_changed,
## Shop.changed and a player leaving / joining mark them dirty, [method update] (every MARKET
## frame, from the Intermission) or [method refresh] rebuilds them – nothing happens while the
## Intermission waits hidden through a wave. [method refresh] is also how a new round shows
## (RunState.begin_spend_round clears the log without a signal). The per-frame check of the
## players compares the last seen index / colour / ready flag field by field (no strings). No RNG.

## The board's design width (a little wider than the stall: the Dust next to the gold needs the room;
## still fits between the two top corner panels, 732 px apart at 1920 x 1080).
const WIDTH := 722.0
## Wide enough for the gold and the team's Dust side by side (a coin, a gold and a sparkle with
## a Dust of up to three digits fit at the full font size at normal values and, shrunk by
## [method _fit_wallet], at five-digit gold; the text column takes what is left).
const WALLET_WIDTH := 124.0
## The wallet's two numbers: the gold row's font sizes.
const GOLD_FONT := 20
const DUST_FONT := 17
## The gold row's fixed parts: the coin, the sparkle and the gap between its five children.
const COIN_SIZE := 19.0
const SPARKLE_SIZE := 16.0
const ROW_GAP := 3
## Font sizes (gold, Dust) of the wallet row, largest first ([method _fit_wallet]): a five-digit gold
## with a three-digit Dust does not fit WALLET_WIDTH at the first pair, so the numbers shrink.
const WALLET_FONTS: Array[Vector2i] = [
	Vector2i(GOLD_FONT, DUST_FONT), Vector2i(18, 15), Vector2i(17, 14), Vector2i(16, 13), Vector2i(15, 12), Vector2i(14, 11),
]
const CAPTION_WIDTH := 45.0
const TEXT_FONT := 16
const CAPTION_FONT := 15
## Height of one text line and how far neighbouring lines overlap (the font's line box has
## room to spare above the capitals, so the three lines can sit closer).
const LINE_HEIGHT := 23.0
const LINE_OVERLAP := 4
const TICKER_LINES := 2
## Text rows of the board: the ticker's TICKER_LINES and the wants' own bottom row.
const ROWS := TICKER_LINES + 1
const SEPARATOR := " · "
## Room kept free at the end of every line (the text outline).
const LINE_SLACK := 6.0
const EMPTY_TICKER := "Nothing spent yet this round"
const EMPTY_WANTS := "None – ping an offer or a Trainer rank (R3 / Tab)"
const TEAM := "Team"
## Layout: the board's side margins, the gaps around the rule after the wallet, the rule's width
## and the gap between the captions and the lines.
const MARGIN_X := 7.0
const RULE_GAP := 6.0
const RULE_WIDTH := 2.0
const CAPTION_GAP := 5.0

## The shared gold (the Intermission's gold_value).
var gold_value: Label
## The team's Arcane Dust, right of the gold ([method refresh_dust]).
var dust_value: Label
var dust_icon: DustIcon
var pips: ReadyPips
## "2/4 ready".
var ready_label: Label
## The rows the ticker may use (the top TICKER_LINES of [member row_labels]).
var ticker_labels: Array[RichTextLabel] = []
## The bottom row: always the wants' (last) line.
var wants_label: RichTextLabel
## All ROWS text rows, top to bottom, and their captions ("Spent", "", "Wants" – the "Wants"
## caption sits on the wants' first row).
var row_labels: Array[RichTextLabel] = []
var caption_labels: Array[Label] = []
## The Shop whose pings feed the wants line (the Intermission passes RunState.shop).
var shop: Shop

## Plain text of the ticker lines and of the wants lines (tests, screenshots).
var _ticker_plain: Array[String] = []
var _wants_plain: Array[String] = []
var _dirty := true
## What [method update] saw last, per slot in order: index, colour (a change rebuilds the texts)
## and ready flag (a change redraws the pips).
var _seen_index: Array[int] = []
var _seen_color: Array[Color] = []
var _seen_ready: Array[bool] = []


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


## "[Rare Dagger]" for shop items and the Black Market offer ("[Rare Dagger] (forged)" for an
## auto-forge), the label as it is for every other spend (consumables: "Flask of Fury").
static func spend_label(entry: Dictionary) -> String:
	var label := String(entry.get("label", ""))
	var kind := StringName(entry.get("kind", &""))
	if kind == &"shop" or kind == &"shop_forge" or kind == &"black_market":
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
		var listed: Array = p_shop.offers.duplicate()
		if p_shop.black_market != null:
			listed.append(p_shop.black_market)
		for o: Shop.Offer in listed:
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


## The team's Dust as the wallet shows it: whole numbers below 1,000, then "1.2k" (rounded down, one
## decimal; "1k" for a full thousand), "12k" from 10,000 and "1.2M" from a million – the wallet
## column is only [constant WALLET_WIDTH] wide.
static func dust_text(amount: int) -> String:
	if amount < 1000:
		return str(amount)
	if amount < 10000:
		return _tenths(floori(amount / 100.0), "k")
	if amount < 1000000:
		return "%dk" % floori(amount / 1000.0)
	return _tenths(floori(amount / 100000.0), "M")


## [param tenths] / 10 with one decimal ("12" -> "1.2"), "1" instead of "1.0", then [param unit].
static func _tenths(tenths: int, unit: String) -> String:
	if tenths % 10 == 0:
		return "%d%s" % [floori(tenths / 10.0), unit]
	return "%d.%d%s" % [floori(tenths / 10.0), tenths % 10, unit]


# --- Queries --------------------------------------------------------------------------------

## The ticker as plain text, one string per shown line (empty round: the "nothing spent" line).
func ticker_lines() -> Array[String]:
	return _ticker_plain.duplicate()


## The wants as plain text, without the "Wants" caption (both lines joined when they take two).
func wants_text() -> String:
	return SEPARATOR.join(_wants_plain)


## The wants as plain text, one string per shown line (empty: none).
func wants_lines() -> Array[String]:
	return _wants_plain.duplicate()


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


## Rebuilds the gold, the ticker and the wants lines now.
func refresh() -> void:
	_dirty = false
	refresh_gold()
	refresh_dust()
	var used := _fill_ticker()
	_fill_wants(ROWS - used)


func refresh_gold() -> void:
	gold_value.text = UiTheme.format_int(RunState.gold)
	_fit_wallet()


## The team's Arcane Dust next to the gold ([method dust_text]: "1.2k" from 1,000; RunState.dust_changed
## calls it while the board is in the tree); the sparkle dims at 0.
func refresh_dust() -> void:
	dust_value.text = dust_text(RunState.arcane_dust)
	dust_icon.set_dim(RunState.arcane_dust <= 0)
	dust_value.add_theme_color_override(&"font_color",
		DustIcon.COLOR_BRIGHT if RunState.arcane_dust > 0 else UiTheme.TEXT_DIM)
	_fit_wallet()


## Keeps the gold row inside [constant WALLET_WIDTH]: the first of [constant WALLET_FONTS] (largest
## first) whose coin + gold + sparkle + Dust row fits is used – normal values keep the full sizes,
## a five-digit gold with a three-digit Dust shrinks both numbers a little.
func _fit_wallet() -> void:
	var fixed := COIN_SIZE + SPARKLE_SIZE + 4.0 * ROW_GAP
	var chosen: Vector2i = WALLET_FONTS[WALLET_FONTS.size() - 1]
	for pair in WALLET_FONTS:
		if fixed + _text_width_of(gold_value, pair.x) + _text_width_of(dust_value, pair.y) <= WALLET_WIDTH:
			chosen = pair
			break
	if gold_value.get_theme_font_size(&"font_size") != chosen.x:
		gold_value.add_theme_font_size_override(&"font_size", chosen.x)
	if dust_value.get_theme_font_size(&"font_size") != chosen.y:
		dust_value.add_theme_font_size_override(&"font_size", chosen.y)


## Width of [param label]'s text at [param font_size] in the label's own font.
static func _text_width_of(label: Label, font_size: int) -> float:
	return label.get_theme_font(&"font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


## Called every MARKET frame: the pips follow [param slots]' ready flags (redrawn only when one
## changed) and dirty texts are rebuilt. A change in the players themselves (one left or joined,
## a colour changed) marks the texts dirty too: the wants line skips players who left
## ([method merged_wants]) and the tags carry the players' colours.
func update(slots: Array[PlayerSlot]) -> void:
	var players_changed := slots.size() != _seen_index.size()
	var ready_changed := players_changed
	if not players_changed:
		for i in slots.size():
			var s := slots[i]
			if s.index != _seen_index[i] or s.color != _seen_color[i]:
				players_changed = true
				ready_changed = true
				break
			if s.ready != _seen_ready[i]:
				ready_changed = true
	if ready_changed:
		_seen_index.clear()
		_seen_color.clear()
		_seen_ready.clear()
		for s in slots:
			_seen_index.append(s.index)
			_seen_color.append(s.color)
			_seen_ready.append(s.ready)
	if players_changed:
		_dirty = true
	if ready_changed:
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
	var gold_row := UiTheme.hbox(ROW_GAP)
	wallet.add_child(gold_row)
	var coin := UiIcon.create(UiIcon.Kind.COIN, Vector2(COIN_SIZE, COIN_SIZE))
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gold_row.add_child(coin)
	gold_value = UiTheme.label("0", UiTheme.GOLD_LABEL, GOLD_FONT, UiTheme.GOLD)
	gold_value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gold_row.add_child(gold_value)
	gold_row.add_child(UiTheme.spacer())
	dust_icon = DustIcon.create(SPARKLE_SIZE)
	dust_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gold_row.add_child(dust_icon)
	dust_value = UiTheme.label("0", UiTheme.GOLD_LABEL, DUST_FONT, DustIcon.COLOR_BRIGHT)
	dust_value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gold_row.add_child(dust_value)
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

	# Captions and lines: Spent (up to two lines), Wants (the bottom line, or two).
	var lines := UiTheme.hbox(int(CAPTION_GAP))
	row.add_child(lines)
	var captions := UiTheme.vbox(-LINE_OVERLAP)
	captions.custom_minimum_size.x = CAPTION_WIDTH
	lines.add_child(captions)
	var texts := UiTheme.vbox(-LINE_OVERLAP)
	lines.add_child(texts)
	for i in ROWS:
		var c := UiTheme.label("", &"", CAPTION_FONT, UiTheme.GOLD_DARK.lightened(0.45))
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		c.custom_minimum_size.y = LINE_HEIGHT
		c.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		captions.add_child(c)
		caption_labels.append(c)
		var l := _line()
		texts.add_child(l)
		row_labels.append(l)
		if i < TICKER_LINES:
			ticker_labels.append(l)
		else:
			wants_label = l
	_set_captions(TICKER_LINES)


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

## Fills the ticker rows; returns how many it used (at least one: the "nothing spent" line).
func _fill_ticker() -> int:
	var entries: Array[Dictionary] = []
	for i in range(RunState.spend_log.size() - 1, -1, -1):
		entries.append(RunState.spend_log[i])
	_ticker_plain.clear()
	for l in ticker_labels:
		l.text = ""
	if entries.is_empty():
		_ticker_plain.append(EMPTY_TICKER)
		ticker_labels[0].text = _dim(EMPTY_TICKER)
		return 1
	var plain: Array[String] = []
	var bb: Array[String] = []
	for e in entries:
		plain.append(entry_text(e))
		bb.append(_entry_bbcode(e))
	_fill_lines(plain, bb, ticker_labels, _ticker_plain)
	return maxi(1, _ticker_plain.size())


## Fills the wants into the bottom [param free_rows] rows (what the ticker left: one or two),
## bottom-aligned – one line of wants stays on the bottom row – and moves the "Wants" caption
## to their first row.
func _fill_wants(free_rows: int) -> void:
	var rows := clampi(free_rows, 1, ROWS - 1)
	for i in range(ROWS - rows, ROWS):
		row_labels[i].text = ""
	_wants_plain.clear()
	var wants := merged_wants(shop, RunState.wants)
	if wants.is_empty():
		wants_label.text = _dim(EMPTY_WANTS)
		_set_captions(ROWS - 1)
		return
	var plain: Array[String] = []
	var bb: Array[String] = []
	for w in wants:
		plain.append(want_text(w))
		bb.append(_want_bbcode(w))
	# Packed into as many rows as needed, then placed on the bottom ones.
	var probe: Array[RichTextLabel] = []
	for i in rows:
		probe.append(row_labels[ROWS - rows + i])
	_fill_lines(plain, bb, probe, _wants_plain)
	var used := maxi(1, _wants_plain.size())
	if used < rows:
		for i in used:
			row_labels[ROWS - used + i].text = probe[i].text
		for i in rows - used:
			row_labels[ROWS - rows + i].text = ""
	_set_captions(ROWS - used)


## "Spent" on the top row, "Wants" on row [param wants_row], the other captions empty.
func _set_captions(wants_row: int) -> void:
	for i in caption_labels.size():
		var text := ""
		if i == 0:
			text = "Spent"
		elif i == wants_row:
			text = "Wants"
		if caption_labels[i].text != text:
			caption_labels[i].text = text


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
	if kind == &"shop" or kind == &"shop_forge" or kind == &"black_market":
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
	var listed: Array = shop.offers.duplicate()
	if shop.black_market != null:
		listed.append(shop.black_market)
	for o: Shop.Offer in listed:
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


func _on_dust_changed(_dust: int, _delta: int) -> void:
	refresh_dust()


func _enter_tree() -> void:
	if not RunState.spent.is_connected(_mark_dirty):
		RunState.spent.connect(_mark_dirty)
	if not RunState.wants_changed.is_connected(_mark_dirty):
		RunState.wants_changed.connect(_mark_dirty)
	if not RunState.dust_changed.is_connected(_on_dust_changed):
		RunState.dust_changed.connect(_on_dust_changed)
	if shop != null and not shop.changed.is_connected(_mark_dirty):
		shop.changed.connect(_mark_dirty)


func _exit_tree() -> void:
	if RunState.spent.is_connected(_mark_dirty):
		RunState.spent.disconnect(_mark_dirty)
	if RunState.wants_changed.is_connected(_mark_dirty):
		RunState.wants_changed.disconnect(_mark_dirty)
	if RunState.dust_changed.is_connected(_on_dust_changed):
		RunState.dust_changed.disconnect(_on_dust_changed)
	if shop != null and shop.changed.is_connected(_mark_dirty):
		shop.changed.disconnect(_mark_dirty)
