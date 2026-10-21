extends Control
## A stand-in for WARDROBE's WardrobePage (M9 PATCH tests): a static create() and the optional handle_nav /
## handle_accept / handle_turn / refresh / set_prompts_visible / action_text / x_text the Onion Patch's Wardrobe tab calls.
## Not a test file (no test_ prefix).

var navs: Array[Vector2i] = []
var accepts := 0
var turns := 0
var refreshes := 0
var prompts_shown := true
## What the page says A does ("" = nothing) and X does.
var a_text := "Buy"


static func create() -> Control:
	return load("res://tests/fake_wardrobe_page.gd").new()


func handle_nav(dir: Vector2i) -> void:
	navs.append(dir)


func handle_accept() -> void:
	accepts += 1


func refresh() -> void:
	refreshes += 1


func handle_turn() -> void:
	turns += 1


func set_prompts_visible(shown: bool) -> void:
	prompts_shown = shown


func action_text() -> String:
	return a_text


func x_text() -> String:
	return "Turn"
