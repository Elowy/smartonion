extends Control
## A stand-in for WARDROBE's WardrobePage (M9 PATCH tests): a static create() and the optional handle_nav /
## handle_accept / refresh the Onion Patch's Wardrobe tab calls. Not a test file (no test_ prefix).

var navs: Array[Vector2i] = []
var accepts := 0
var refreshes := 0


static func create() -> Control:
	return load("res://tests/fake_wardrobe_page.gd").new()


func handle_nav(dir: Vector2i) -> void:
	navs.append(dir)


func handle_accept() -> void:
	accepts += 1


func refresh() -> void:
	refreshes += 1
