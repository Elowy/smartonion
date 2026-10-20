class_name PatchTab
extends VBoxContainer
## Base of the tabs of The Onion Patch ([OnionPatchPage]): a content area the page shows while its tab is selected and
## feeds with the navigation steps and the A / X presses of whoever drives the page. A tab builds its widgets once, redraws
## itself in [method refresh] (called when the tab opens and after every purchase) and reports what happened as a
## status line with [signal message_posted]. Subclasses override the hooks; the shared styles live here.

## A line for the page's status row ([param good]: a purchase / pick went through, else a refusal).
signal message_posted(text: String, good: bool)

const ROW_FILL := Color(0.1, 0.09, 0.08, 0.9)
const ROW_FILL_ON := Color(0.2, 0.17, 0.11, 0.95)
const ROW_BORDER := Color(0.2, 0.17, 0.13)
const LOCKED_COLOR := Color(0.62, 0.58, 0.55)
const ERROR_COLOR := Color(1.0, 0.45, 0.35)
const OWNED_COLOR := Color(0.55, 1.0, 0.5)
const SEEDS_COLOR := Color(0.72, 0.95, 0.45)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


# --- Hooks ---------------------------------------------------------------------------------------

## The tab was selected (or the page opened on it): reset transient state and redraw.
func on_open() -> void:
	refresh()


## Redraws from the current profile.
func refresh() -> void:
	pass


## One navigation step (a unit direction per push, with key-repeat while held).
func on_nav(_dir: Vector2i) -> void:
	pass


## A / Enter.
func on_accept() -> void:
	pass


## X (or the R key): the tab's second action – the Wardrobe turns its preview.
func on_x() -> void:
	pass


## What A does on the current selection, for the prompt row ("" = nothing: no A prompt).
func action_text() -> String:
	return ""


## What X does on this tab, for the prompt row ("" = nothing: no X prompt).
func x_text() -> String:
	return ""


## The tab's own name for the status line / tests.
func tab_name() -> String:
	return ""


func post(text: String, good: bool = true) -> void:
	message_posted.emit(text, good)


# --- Shared look ---------------------------------------------------------------------------------

## The panel of one list row (selected = gold border).
static func row_panel(selected: bool, min_height: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(0, min_height)
	panel.add_theme_stylebox_override(&"panel", row_style(selected))
	return panel


static func row_style(selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = ROW_FILL_ON if selected else ROW_FILL
	style.border_color = UiTheme.GOLD if selected else ROW_BORDER
	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style


## A dark inset panel (the detail panes).
static func inset_panel() -> PanelContainer:
	var panel := UiTheme.panel(UiTheme.INSET_PANEL)
	var style := UiTheme.inset_style()
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override(&"panel", style.rebuild())
	return panel


## A label that never widens its row: clipped with an ellipsis.
static func clipped_label(text: String, size: int, color: Color, variation: StringName = &"") -> Label:
	var l := UiTheme.label(text, variation, size, color)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return l


## Removes (and frees) every child of [param box].
static func clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


## Wraps [param step] into 0 .. [param count] - 1 (0 for an empty list).
static func wrap_index(index: int, step: int, count: int) -> int:
	return wrapi(index + step, 0, count) if count > 0 else 0


## Seeds with thousands separators ("1,240").
static func seeds_text(amount: int) -> String:
	return UiTheme.format_int(amount)
