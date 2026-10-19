class_name CreditsPage
extends MenuPage
## The Credits page (M7a), opened from the main menu: res://CREDITS.md (the third-party assets with author,
## URL and licence) rendered as simple formatted text, followed by the Godot Engine licence notice that
## shipping the engine requires. Without that file a short built-in text is shown instead. Scroll with the
## stick / d-pad / arrow keys (or the mouse wheel), B goes back. Input rules (driver, swallowed opening
## press): MenuPage.
##
## [method parse] understands the small subset of Markdown the credits need: # / ## / ### headings, "- " / "* "
## bullets, "> " quotes (small print), --- rules, paragraphs (consecutive lines join into one), tables (the
## header row becomes a sub-heading, the other rows "a  ·  b  ·  c") and the inline **bold**, *italic*, `code`,
## [text](url) and <url> marks, which are reduced to plain text.

enum Line { TITLE, HEADING, SUBHEADING, TEXT, BULLET, QUOTE, RULE, GAP }

const CREDITS_PATH := "res://CREDITS.md"
const PANEL_WIDTH := 1100.0
const VIEW_HEIGHT := 640.0
## Pixels per second while the stick / d-pad is held.
const SCROLL_SPEED := 720.0
const FALLBACK_MARKDOWN := "# SmartOnion\n\nSmartOnion – a fan-made parody game\n\nMade with Godot Engine\n"
const TABLE_CELL_SEPARATOR := "  ·  "

## The lines shown, as {"kind": Line, "text": String} (see [method parse]).
var lines: Array[Dictionary] = []
var scroll: ScrollContainer
var content: VBoxContainer

var _scroll_remainder := 0.0


static func create(dim_alpha: float = 0.45, path: String = CREDITS_PATH) -> CreditsPage:
	var p := CreditsPage.new()
	p.name = "CreditsPage"
	p._build(dim_alpha, path)
	return p


func _build(dim_alpha: float, path: String) -> void:
	_build_frame("Credits", PANEL_WIDTH, dim_alpha)
	scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, VIEW_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(scroll)
	content = UiTheme.vbox(6)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	_finish_frame()
	set_markdown(page_markdown(path))


# --- Text ----------------------------------------------------------------------------------

## The text of the credits file; "" when it is missing or empty.
static func read_markdown(path: String = CREDITS_PATH) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


## The Godot Engine notice (required when shipping the engine): the name and site, then the engine's own
## licence text (Engine.get_license_text, the MIT licence with its copyright lines) as small print.
static func godot_markdown() -> String:
	var text := "## Godot Engine\n\nThis game is made with Godot Engine – godotengine.org\n\n"
	text += "Godot Engine is free and open source software released under the MIT licence.\n\n"
	for line in Engine.get_license_text().strip_edges().split("\n"):
		var row := line.strip_edges()
		text += ("> %s\n" % row) if row != "" else ">\n"
	return text


## Everything the page shows: the credits file (or the built-in text) and the Godot notice.
static func page_markdown(path: String = CREDITS_PATH) -> String:
	var body := read_markdown(path)
	if body.strip_edges() == "":
		body = FALLBACK_MARKDOWN
	return body.rstrip("\n") + "\n\n" + godot_markdown()


## [param markdown] as display lines: {"kind": [enum Line], "text": String}. Pure text work (no nodes).
static func parse(markdown: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rows := markdown.replace("\r\n", "\n").split("\n")
	var paragraph: Array[String] = []
	var paragraph_kind := Line.TEXT
	for i in rows.size():
		var line := rows[i].strip_edges()
		if line == "":
			_flush(out, paragraph, paragraph_kind)
			_add_gap(out)
		elif line.begins_with("#"):
			_flush(out, paragraph, paragraph_kind)
			var level := line.length() - line.lstrip("#").length()
			var kind := Line.TITLE if level == 1 else (Line.HEADING if level == 2 else Line.SUBHEADING)
			out.append({"kind": kind, "text": inline_text(line.lstrip("#").strip_edges())})
		elif _is_rule(line):
			_flush(out, paragraph, paragraph_kind)
			out.append({"kind": Line.RULE, "text": ""})
		elif line.begins_with("- ") or line.begins_with("* ") or line.begins_with("+ "):
			_flush(out, paragraph, paragraph_kind)
			out.append({"kind": Line.BULLET, "text": inline_text(line.substr(2))})
		elif line.begins_with(">"):
			if paragraph_kind != Line.QUOTE:
				_flush(out, paragraph, paragraph_kind)
			paragraph_kind = Line.QUOTE
			var quoted := line.lstrip(">").strip_edges()
			if quoted == "":
				_flush(out, paragraph, paragraph_kind)  # (a ">" alone ends the quoted paragraph)
			else:
				paragraph.append(quoted)
		elif line.begins_with("|"):
			_flush(out, paragraph, paragraph_kind)
			var cells := _table_cells(line)
			if _is_table_separator(cells):
				continue
			var next_is_separator := i + 1 < rows.size() and rows[i + 1].strip_edges().begins_with("|") \
					and _is_table_separator(_table_cells(rows[i + 1].strip_edges()))
			out.append({"kind": Line.SUBHEADING if next_is_separator else Line.TEXT,
					"text": inline_text(TABLE_CELL_SEPARATOR.join(cells))})
		else:
			if paragraph_kind != Line.TEXT:
				_flush(out, paragraph, paragraph_kind)
			paragraph_kind = Line.TEXT
			paragraph.append(line)
	_flush(out, paragraph, paragraph_kind)
	while not out.is_empty() and int(out[-1]["kind"]) == Line.GAP:
		out.pop_back()
	return out


## Adds the pending paragraph as one line (its rows joined by spaces) and clears it.
static func _flush(out: Array[Dictionary], paragraph: Array[String], kind: Line) -> void:
	if paragraph.is_empty():
		return
	out.append({"kind": kind, "text": inline_text(" ".join(paragraph))})
	paragraph.clear()


## One gap between blocks (never first, never twice in a row).
static func _add_gap(out: Array[Dictionary]) -> void:
	if not out.is_empty() and int(out[-1]["kind"]) != Line.GAP:
		out.append({"kind": Line.GAP, "text": ""})


static func _is_rule(line: String) -> bool:
	if line.length() < 3:
		return false
	for c in ["-", "*", "_"]:
		if line.lstrip(c) == "":
			return true
	return false


static func _table_cells(line: String) -> Array[String]:
	var cells: Array[String] = []
	var parts := line.strip_edges().trim_prefix("|").trim_suffix("|").split("|")
	for part in parts:
		cells.append(part.strip_edges())
	return cells


## "|---|:---:|" rows between a table's header and its body.
static func _is_table_separator(cells: Array[String]) -> bool:
	if cells.is_empty():
		return false
	for c in cells:
		if c == "" or c.lstrip(":-").rstrip(":") != "":
			return false
	return true


## [param text] without the inline Markdown marks: **bold**, *italic*, `code`, [name](url) -> name (url), <url>.
static func inline_text(text: String) -> String:
	var out := text
	for pattern in [["\\[([^\\]]+)\\]\\(([^)]+)\\)", "$1 ($2)"], ["<((?:https?://|mailto:)[^>]+)>", "$1"],
			["\\*\\*([^*]+)\\*\\*", "$1"], ["__([^_]+)__", "$1"], ["(?<!\\*)\\*([^*\\n]+)\\*(?!\\*)", "$1"]]:
		out = RegEx.create_from_string(pattern[0]).sub(out, pattern[1], true)
	return out.replace("`", "")


# --- Page ----------------------------------------------------------------------------------

## Replaces the page text by [param markdown].
func set_markdown(markdown: String) -> void:
	for c in content.get_children():
		content.remove_child(c)
		c.queue_free()
	lines = parse(markdown)
	# (the first "# Credits" would only repeat the page title)
	if not lines.is_empty() and int(lines[0]["kind"]) == Line.TITLE and String(lines[0]["text"]).to_lower() == "credits":
		lines.pop_front()
		while not lines.is_empty() and int(lines[0]["kind"]) == Line.GAP:
			lines.pop_front()
	for entry in lines:
		_add_line(int(entry["kind"]) as Line, String(entry["text"]))
	scroll.scroll_vertical = 0


func _add_line(kind: Line, text: String) -> void:
	match kind:
		Line.TITLE:
			var l := UiTheme.centered_label(text, UiTheme.HEADING, 44)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			content.add_child(l)
		Line.HEADING:
			content.add_child(_gap(10.0))
			var l := UiTheme.label(text, UiTheme.GOLD_LABEL, 30)
			content.add_child(l)
			var rule := HSeparator.new()
			rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
			content.add_child(rule)
		Line.SUBHEADING:
			content.add_child(UiTheme.wrapped_label(text, &"", UiTheme.FONT_LARGE - 4, UiTheme.GOLD_BRIGHT))
		Line.TEXT:
			content.add_child(_wrapped(text, UiTheme.FONT_BODY, UiTheme.TEXT))
		Line.BULLET:
			var row := UiTheme.hbox(10)
			var dot := UiTheme.label("•", &"", UiTheme.FONT_BODY, UiTheme.GOLD)
			dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			row.add_child(dot)
			row.add_child(_wrapped(text, UiTheme.FONT_BODY, UiTheme.TEXT))
			content.add_child(row)
		Line.QUOTE:
			content.add_child(_wrapped(text, UiTheme.FONT_SMALL, UiTheme.TEXT_DIM))
		Line.RULE:
			var rule := HSeparator.new()
			rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
			content.add_child(rule)
		Line.GAP:
			content.add_child(_gap(6.0))


func _wrapped(text: String, font_size: int, color: Color) -> Label:
	var l := UiTheme.wrapped_label(text, &"", font_size, color)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _gap(height: float) -> Control:
	var g := Control.new()
	g.custom_minimum_size = Vector2(0, height)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


## The furthest [member ScrollContainer.scroll_vertical] can go.
func max_scroll() -> int:
	return maxi(0, int(content.size.y - scroll.size.y))


## Scrolls by [param pixels] (negative = up); sub-pixel amounts add up over frames.
func scroll_by(pixels: float) -> void:
	_scroll_remainder += pixels
	var whole := int(_scroll_remainder)
	_scroll_remainder -= float(whole)
	scroll.scroll_vertical = clampi(scroll.scroll_vertical + whole, 0, max_scroll())


# --- Input hooks ---------------------------------------------------------------------------

func _on_open() -> void:
	scroll.scroll_vertical = 0
	_scroll_remainder = 0.0


func _on_held(dir: Vector2i, delta: float) -> void:
	if dir.y != 0:
		scroll_by(float(dir.y) * SCROLL_SPEED * delta)


func _prompt_items() -> Array:
	return [
		[UiGlyph.nav(28.0, true), "Scroll"],
		_glyphs(PlayerInput.Pad.B) + ["Back"],
	]
