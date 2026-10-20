class_name PatchWardrobeTab
extends PatchTab
## The Wardrobe tab of The Onion Patch: WARDROBE's [code]WardrobePage.create()[/code] (res://scenes/ui/meta/wardrobe_page.gd,
## a read-only collection browser) embedded when that script exists – loaded with ResourceLoader.exists + load, so this
## package builds without it – else a short placeholder. The page's optional [code]handle_nav(dir: Vector2i)[/code],
## [code]handle_accept()[/code] and [code]refresh()[/code] are called when it has them.

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
