class_name RunCard
extends RefCounted
## The run card (M6 METER): the shareable 1200 x 630 picture of a finished run – game title, mode,
## victory / defeat and the waves cleared, the run time and, per hero, the portrait, class, best
## item and award. [method model] is the pure data of the card (a function of the
## [RunSummary] dictionary, unit tested); [RunCardView] draws it; [method render] lays it out in a
## SubViewport and returns the pixels; [method save_png] writes them to
## user://cards/run_<yyyy-mm-dd_hh-mm-ss>.png.

const SIZE := Vector2i(1200, 630)
const DIR := "user://cards"
const GAME_TITLE := "SmartOnion"
## Heroes on a card (a party has at most four).
const MAX_HEROES := 4


## The card's content: {"title", "result" ("Victory" / "Defeat"), "victory", "mode", "waves_text"
## ("25 / 25 waves"), "time_text", "heroes": [{"label", "class_name", "class_id",
## "color" (player), "class_color", "alive", "item_name", "item_rarity", "item_level", "item_line",
## "award" (the hero's first award, "" = none), "more_awards" (how many further awards), "award_line",
## "stat_line"}]}. [param summary] = RunSummary.collect / build.
static func model(summary: Dictionary) -> Dictionary:
	var victory := bool(summary.get("victory", false))
	var waves_text := "%d / %d waves" % [int(summary.get("waves_cleared", 0)), int(summary.get("total_waves", 0))]
	var time_text := String(summary.get("time_text", RunSummary.format_time(float(summary.get("time", 0.0)))))
	var mode := String(summary.get("mode", "Normal"))
	var heroes: Array[Dictionary] = []
	for h: Dictionary in summary.get("heroes", []):
		if heroes.size() >= MAX_HEROES:
			break
		heroes.append(_hero_model(h))
	return {
		"title": GAME_TITLE,
		"result": "Victory" if victory else "Defeat",
		"victory": victory,
		"mode": mode,
		"waves_text": waves_text,
		"time_text": time_text,
		"heroes": heroes,
	}


static func _hero_model(h: Dictionary) -> Dictionary:
	var item := h.get("best_item") as ItemInstance
	var awards: Array = h.get("awards", [])
	var award := RunSummary.award_name(awards[0]) if not awards.is_empty() else ""
	var stats: Dictionary = h.get("stats", {})
	var stat_parts: Array[String] = []
	for id: StringName in [&"damage", &"healing"]:
		var v := float(stats.get(id, 0.0))
		if v > 0.0:
			stat_parts.append("%s %s" % [RunSummary.STAT_LABELS[id], RunSummary.format_amount(v)])
	return {
		"label": h.get("label", "?"),
		"class_name": h.get("class_name", "?"),
		"class_id": h.get("class_id", &""),
		"color": h.get("color", Color.WHITE),
		"class_color": h.get("class_color", Color.WHITE),
		"alive": bool(h.get("alive", true)),
		"item_name": item.display_name if item != null else "",
		"item_rarity": item.rarity if item != null else -1,
		"item_level": item.item_level if item != null else 0,
		"item_line": ("Item level %d" % item.item_level) if item != null else "No gear",
		"award": award,
		"more_awards": maxi(0, awards.size() - 1),
		"award_line": award + (" +%d" % (awards.size() - 1) if awards.size() > 1 else ""),
		"stat_line": "   ".join(stat_parts),
	}


## "run_2026-10-14_15-20-11.png" for [param datetime] ({year, month, day, hour, minute, second},
## Time.get_datetime_dict_from_system()).
static func file_name(datetime: Dictionary) -> String:
	return "run_%04d-%02d-%02d_%02d-%02d-%02d.png" % [
		int(datetime.get("year", 1970)), int(datetime.get("month", 1)), int(datetime.get("day", 1)),
		int(datetime.get("hour", 0)), int(datetime.get("minute", 0)), int(datetime.get("second", 0))]


## A path under [param dir] for [param name] that does not exist yet: a second card within the
## same second becomes "run_..._2.png", the third "_3" ...
static func unique_path(dir: String, name: String) -> String:
	var path := dir.path_join(name)
	var n := 2
	var stem := name.get_basename()
	while FileAccess.file_exists(path):
		path = dir.path_join("%s_%d.%s" % [stem, n, name.get_extension()])
		n += 1
	return path


## Lays the card for [param card_model] out in a SubViewport under [param host] (which must be in
## the tree), waits for it to draw and returns the pixels; null when nothing was rendered (the
## headless dummy renderer draws nothing, so it returns at once). Await it.
static func render(host: Node, card_model: Dictionary) -> Image:
	if DisplayServer.get_name() == "headless":
		return null
	var viewport := SubViewport.new()
	viewport.name = "RunCardViewport"
	viewport.size = SIZE
	viewport.transparent_bg = false
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.add_child(RunCardView.create(card_model))
	host.add_child(viewport)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = null
	var texture := viewport.get_texture()
	if texture != null:
		image = texture.get_image()
	if viewport.get_parent() != null:
		viewport.get_parent().remove_child(viewport)
	viewport.queue_free()
	if image == null or image.is_empty():
		return null
	return image


## Saves [param image] as a new card file in [constant DIR] (made on demand) and returns its path
## ("" when it could not be written).
static func save_png(image: Image, datetime: Dictionary = {}) -> String:
	if image == null or image.is_empty():
		return ""
	if DirAccess.make_dir_recursive_absolute(DIR) != OK:
		return ""
	var when := datetime if not datetime.is_empty() else Time.get_datetime_dict_from_system()
	var path := unique_path(DIR, file_name(when))
	return path if image.save_png(path) == OK else ""
