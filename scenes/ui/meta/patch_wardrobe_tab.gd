class_name PatchWardrobeTab
extends PatchTab
## The Wardrobe tab of The Onion Patch: WARDROBE's [code]WardrobePage.create()[/code] (res://scenes/ui/meta/wardrobe_page.gd,
## a read-only collection browser) embedded when that script exists – loaded with ResourceLoader.exists + load, so this
## package builds without it – else a short placeholder. The page's optional [code]handle_nav(dir: Vector2i)[/code],
## [code]handle_accept()[/code], [code]handle_turn()[/code] (X: turns the preview) and [code]refresh()[/code] are called when it
## has them. The page's own prompt row is hidden ([code]set_prompts_visible(false)[/code], when it has it): the Patch's prompt
## row shows the buttons – with the driver's glyphs – for what the page says through [code]action_text()[/code] ("Buy" or "")
## and [code]x_text()[/code] ("Turn").

const WARDROBE_PAGE_PATH := "res://scenes/ui/meta/wardrobe_page.gd"
const PLACEHOLDER_TEXT := "Coming soon"

## Where the tab looks for the WardrobePage script (tests point it at a fake).
static var wardrobe_page_path := WARDROBE_PAGE_PATH

## The embedded WardrobePage (null without the script) and the placeholder label (shown without it).
var page: Control
var placeholder: Label


static func create() -> PatchWardrobeTab:
	var t := PatchWardrobeTab.new()
	t.name = "WardrobeTab"
	t._build()
	return t


func tab_name() -> String:
	return "Wardrobe"


static func page_available() -> bool:
	return ResourceLoader.exists(wardrobe_page_path)


func _build() -> void:
	placeholder = UiTheme.centered_label("Wardrobe\n%s" % PLACEHOLDER_TEXT, UiTheme.DIM, UiTheme.FONT_LARGE)
	placeholder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	placeholder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(placeholder)
	if not page_available():
		return
	var script: Variant = load(wardrobe_page_path)
	if script == null:
		return
	var created: Variant = (script as Object).call(&"create")
	if created is Control:
		page = created as Control
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(page)
		placeholder.visible = false
		if page.has_method(&"set_prompts_visible"):
			page.call(&"set_prompts_visible", false)


func on_open() -> void:
	refresh()


func refresh() -> void:
	if page != null and is_instance_valid(page) and page.has_method(&"refresh"):
		page.call(&"refresh")


func on_nav(dir: Vector2i) -> void:
	if page != null and is_instance_valid(page) and page.has_method(&"handle_nav"):
		page.call(&"handle_nav", dir)


func on_accept() -> void:
	if page != null and is_instance_valid(page) and page.has_method(&"handle_accept"):
		page.call(&"handle_accept")


func on_x() -> void:
	if page != null and is_instance_valid(page) and page.has_method(&"handle_turn"):
		page.call(&"handle_turn")


func action_text() -> String:
	return _page_text(&"action_text")


func x_text() -> String:
	return _page_text(&"x_text")


func _page_text(method: StringName) -> String:
	if page != null and is_instance_valid(page) and page.has_method(method):
		return String(page.call(method))
	return ""
