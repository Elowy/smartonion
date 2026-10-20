extends TestCase
## Static typing of the loop variables in two hot paths: the bot's rescue safety check (_safe_rescue) and
## the item base draw (ItemGenerator.pick_base). A typing change has no run-time effect, so the test reads
## the sources: every `for` in those functions must name its type.

const BOT_INPUT := "res://core/input/bot_input.gd"
const ITEM_GENERATOR := "res://core/items/item_generator.gd"


## The source text of [param path].
func _source(path: String) -> String:
	return FileAccess.get_file_as_string(path)


## The text of the function [param func_name] in [param source]: from its `func` line to the next top-level
## function (or the end of the file).
func _function_text(source: String, func_name: String) -> String:
	var start := source.find("func %s(" % func_name)
	if start < 0:
		return ""
	var next_func := RegEx.create_from_string("\n(static )?func ").search(source, start + 1)
	var stop := next_func.get_start() if next_func != null else source.length()
	return source.substr(start, stop - start)


## The `for` lines of [param text] without a type (`for x in ...`; `for x: T in ...` is typed).
func _untyped_loops(text: String) -> Array[String]:
	var found: Array[String] = []
	for line in text.split("\n"):
		var code := line.strip_edges()
		if not code.begins_with("for "):
			continue
		var header := code.substr(4, code.find(" in ") - 4)
		if not header.contains(":"):
			found.append(code)
	return found


func test_the_bot_rescue_check_types_its_loops() -> void:
	var body := _function_text(_source(BOT_INPUT), "_safe_rescue")
	check(not body.is_empty(), "_safe_rescue is in bot_input.gd")
	check_eq(_untyped_loops(body), [] as Array[String], "no untyped for in _safe_rescue")
	check(body.contains("for list: Array[Vector2] in [enemies, more]:"), "the list loop names Array[Vector2]")


func test_the_item_base_draw_types_its_loops() -> void:
	var body := _function_text(_source(ITEM_GENERATOR), "pick_base")
	check(not body.is_empty(), "pick_base is in item_generator.gd")
	check_eq(_untyped_loops(body), [] as Array[String], "no untyped for in pick_base")
	check(body.contains("for id: StringName in Db.item_bases:"), "the base loop names StringName")
	check(body.contains("var armor_types: Array[int]"), "armor_types is an Array[int]")
	check(body.contains("for tiers: Array in entries:"), "the entries loop names Array")


func test_the_untyped_loop_finder_tells_typed_from_untyped() -> void:
	var sample := "func f() -> void:\n\tfor a in list:\n\t\tpass\n\tfor b: int in list:\n\t\tpass\n"
	check_eq(_untyped_loops(sample), ["for a in list:"] as Array[String], "only the untyped loop is found")
