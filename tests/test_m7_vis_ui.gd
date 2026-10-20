extends TestCase
## M7b VIS-UI: the Cinzel title font (UiTheme.title_font, OFL 1.1) and the game-icons.net pictures
## (data/icons/icon_map.tres, GameIcons): every ability / talent / talent tree / consumable / shrine id
## resolves to a shared 128 px texture, the controls draw them (procedural glyphs stay the fallback),
## and the credits name the font and the icon authors.

const Rules := preload("res://tests/content_rules.gd")

const FONT_PATH := "res://assets/fonts/Cinzel-VariableFont_wght.ttf"
const ICON_DIR := "res://assets/icons"
## Ids that are allowed to have no picture (they keep their procedural glyph). Empty: every shipped id has one.
const GLYPH_ONLY: Array[StringName] = []

var nodes: Array[Node] = []


func after_each() -> void:
	for n in nodes:
		if is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	nodes.clear()


func _add(n: Node) -> Node:
	tree.root.add_child(n)
	nodes.append(n)
	return n


func _all_talents() -> Array[TalentData]:
	var out: Array[TalentData] = []
	for tree_id: StringName in Db.talent_trees:
		for t in Db.talent_trees[tree_id].talents:
			out.append(t)
	return out


# --- Fonts -------------------------------------------------------------------------------------

func test_the_font_and_its_licence_are_in_the_repo() -> void:
	check(ResourceLoader.exists(FONT_PATH), "the Cinzel font file")
	check(FileAccess.file_exists("res://assets/fonts/OFL.txt"), "the OFL text sits next to the font")
	var ofl := FileAccess.get_file_as_string("res://assets/fonts/OFL.txt")
	check("SIL OPEN FONT LICENSE" in ofl.to_upper() and "Cinzel" in ofl, "it is the Cinzel OFL")
	var font := load(FONT_PATH) as FontFile
	check(font != null, "it loads as a FontFile")
	if font != null:
		check(font.has_char("A".unicode_at(0)) and font.has_char("z".unicode_at(0)) and font.has_char("7".unicode_at(0)), "Latin letters and digits")


func test_the_title_font_is_cinzel_at_bold_weight() -> void:
	var f := UiTheme.title_font() as FontVariation
	check(f != null, "a FontVariation (the weight axis of the variable font)")
	if f == null:
		return
	check_eq(f.base_font.resource_path, FONT_PATH, "the base font is Cinzel")
	check(f.variation_opentype.has(UiTheme.WEIGHT_TAG), "the weight axis is set")
	check_eq(float(f.variation_opentype.get(UiTheme.WEIGHT_TAG, 0.0)), UiTheme.TITLE_WEIGHT, "bold weight")
	check_eq(UiTheme.WEIGHT_TAG, TextServerManager.get_primary_interface().name_to_tag("wght"), "the tag is wght")
	check(UiTheme.title_font() == UiTheme.title_font(), "one shared instance")
	# The weight changes the glyphs: bold is wider than the regular weight.
	var regular := FontVariation.new()
	regular.base_font = f.base_font
	check(f.get_string_size("SmartOnion", HORIZONTAL_ALIGNMENT_LEFT, -1, 72).x
			> regular.get_string_size("SmartOnion", HORIZONTAL_ALIGNMENT_LEFT, -1, 72).x, "the bold weight is applied")


func test_the_theme_sets_cinzel_on_titles_headings_numbers_and_buttons_only() -> void:
	var t := UiTheme.get_theme()
	var title := UiTheme.title_font()
	for type: StringName in [UiTheme.TITLE, UiTheme.HEADING, UiTheme.BIG_NUMBER]:
		check(t.get_font(&"font", type) == title, "%s uses the title font" % type)
	check(t.get_font(&"font", &"Button") == title, "buttons use the title font")
	# Body text keeps the default font (layout / fit tests depend on it), names and numbers the bold variation of it.
	check(t.default_font == ThemeDB.fallback_font, "the default font is unchanged")
	for type: StringName in [UiTheme.DIM, UiTheme.SMALL]:
		check(t.get_font(&"font", type) == t.default_font or not t.has_font(&"font", type), "%s keeps the body font" % type)
	var bold := UiTheme.bold_font() as FontVariation
	check(bold != null and bold.base_font == ThemeDB.fallback_font, "the bold font is still the default font, emboldened")
	check(not (UiTheme.bold_font() as FontVariation).base_font.resource_path.contains("Cinzel"), "no Cinzel in the bold font")


func test_the_title_font_falls_back_to_the_default_font_for_missing_glyphs() -> void:
	var f := UiTheme.title_font()
	# "→" (Rank I → II, the level-up ribbons) is in neither font: the fallback list must not break the size.
	check(f.get_string_size("Rank I → II", HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x > 0.0, "text with a missing glyph measures")
	check(not (f as FontVariation).fallbacks.is_empty(), "the default font is the fallback")


func test_titles_fit_their_screens_in_cinzel() -> void:
	# Cinzel is wider than the old title font (up to ~25% on short words): the longest titles of the game
	# at their sizes (1920 x 1080 canvas) still fit the space their screens give them.
	var f := UiTheme.title_font()
	var rows := [
		["SmartOnion", UiTheme.FONT_HUGE, 1200.0], ["Assemble Your Party", 60, 980.0], ["Paused", 84, 452.0],
		["A dungeon portal has opened!", 60, 1100.0], ["Rolling the arena…", 64, 1100.0], ["Loot Roll", 60, 700.0],
		["Victory!", 110, 900.0], ["Wave 25 cleared!", 64, 1000.0], ["A Shrine!", 56, 600.0], ["Level Up!", 46, 600.0],
		["Shrine of the Gambler", 40, 640.0], ["Ready for the market", 30, 520.0],
	]
	for r: Array in rows:
		var w := f.get_string_size(String(r[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(r[1])).x
		check(w <= float(r[2]), "%s at %d px is %d px wide (room %d)" % [r[0], int(r[1]), int(w), int(r[2])])


func test_headings_in_the_wide_font_shrink_to_their_column() -> void:
	var f := UiTheme.title_font()
	check_eq(UiTheme.fitted_font_size(f, "Hi", 500.0, 40), 40, "short text keeps the full size")
	check_eq(UiTheme.fitted_font_size(f, "x".repeat(200), 50.0, 40, 14), 14, "nothing fits: the minimum size")
	var fs := UiTheme.fitted_font_size(f, "Shrine of the Gambler", 400.0, 40, 14)
	check(fs < 40 and fs >= 14, "a long text steps down (%d)" % fs)
	check(f.get_string_size("Shrine of the Gambler", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= 400.0, "and then fits")
	check(f.get_string_size("Shrine of the Gambler", HORIZONTAL_ALIGNMENT_LEFT, -1, fs + 1).x > 400.0, "one size more would not")
	# The shrine card: every shipped name fits the room right of the icon.
	var screen := _add(ShrineScreen.create()) as ShrineScreen
	for id: StringName in Db.shrines:
		screen.data = Db.shrines[id]
		screen._fill_card()
		var size := screen.name_label.get_theme_font_size(&"font_size")
		check(size >= 30 and size <= ShrineScreen.NAME_FONT, "%s: name size %d" % [id, size])
		check(f.get_string_size(screen.data.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= ShrineScreen.NAME_WIDTH,
				"%s: the name fits the card" % id)


func test_the_menu_buttons_keep_their_width_in_cinzel() -> void:
	var menu := _add(MainMenu.create()) as MainMenu
	for b in menu.buttons:
		check(b.get_theme_font(&"font") == UiTheme.title_font(), "%s is set in the title font" % b.text)
		check(b.get_minimum_size().x <= 420.5, "%s fits the 420 px button (%d)" % [b.text, int(b.get_minimum_size().x)])
	# The pause menu's buttons (its panel grows with the widest one, "Are you sure?  Press again" already did).
	for text in ["Resume", PauseMenu.SETTINGS_TEXT, PauseMenu.QUIT_TEXT, "Continue without P4", PauseMenu.QUIT_CONFIRM_TEXT]:
		var w := UiTheme.title_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		check(w + 56.0 <= 520.0, "'%s' (%d px) stays within 520 px with its margins" % [text, int(w)])


# --- The map ------------------------------------------------------------------------------------

func test_the_icon_map_loads_and_every_picture_exists_at_128_px() -> void:
	var map := GameIcons.icon_map()
	check(map != null and not map.abilities.is_empty(), "the shipped map is loaded")
	var paths := map.all_paths()
	check(paths.size() >= 150, "the map uses many pictures (%d)" % paths.size())
	for path in paths:
		check(path.begins_with(ICON_DIR + "/") and path.ends_with(".svg"), "%s is an icon svg" % path)
		var tex := GameIcons.texture_at(path)
		check(tex != null, "%s loads" % path)
		if tex == null:
			continue
		check_eq(tex.get_width(), 128, "%s is imported at 128 px" % path)
		check_eq(tex.get_height(), 128, "%s is square" % path)
		var import := FileAccess.get_file_as_string(path + ".import")
		check("svg/scale=0.25" in import and "mipmaps/generate=true" in import, "%s: imported at 128 px with mipmaps" % path)
		var author := path.trim_prefix(ICON_DIR + "/").get_slice("/", 0)
		check(author in ["lorc", "delapouite"], "%s: an author folder that CREDITS.md names" % path)


func test_every_ability_has_a_picture() -> void:
	var seen := 0
	for id: StringName in Db.abilities:
		var a := Db.abilities[id]
		seen += 1
		if id in GLYPH_ONLY:
			continue
		check(GameIcons.for_ability(a) != null, "ability %s (icon %s) has a picture" % [id, a.icon])
	check(seen >= 46, "all the shipped abilities were checked (%d)" % seen)


func test_every_talent_has_its_own_picture_and_a_class_tells_them_apart() -> void:
	var count := 0
	var map := GameIcons.icon_map()
	for class_id: StringName in Db.class_ids:
		var by_path: Dictionary[String, StringName] = {}
		for tree_data in Db.talent_trees_for(class_id):
			for t in tree_data.talents:
				count += 1
				if t.id in GLYPH_ONLY:
					continue
				check(map.talents.has(t.id), "%s has its own entry" % t.id)
				var tex := GameIcons.for_talent(t)
				check(tex != null, "talent %s has a picture" % t.id)
				var path := String(map.talents.get(t.id, ""))
				check(not by_path.has(path), "%s and %s share %s inside %s" % [t.id, by_path.get(path, &""), path, class_id])
				by_path[path] = t.id
	check_eq(count, Rules.classes_with("trees").size() * Rules.TREES_PER_CLASS * 9, "every class with trees: three trees x nine talents")


func test_abilities_and_trees_tell_themselves_apart_too() -> void:
	var map := GameIcons.icon_map()
	var seen: Dictionary[String, StringName] = {}
	for id: StringName in Db.abilities:
		var path := String(map.abilities.get(Db.abilities[id].icon, ""))
		check(not seen.has(path), "abilities %s and %s share %s" % [id, seen.get(path, &""), path])
		seen[path] = id
	var trees: Dictionary[String, StringName] = {}
	for id: StringName in Db.talent_trees:
		var path := String(map.trees.get(id, ""))
		check(not trees.has(path), "trees %s and %s share %s" % [id, trees.get(path, &""), path])
		trees[path] = id
		check(not seen.has(path), "the tree %s shows the picture of the ability %s" % [id, seen.get(path, &"")])


func test_every_tree_consumable_and_shrine_has_a_picture() -> void:
	check_eq(Db.talent_trees.size(), Rules.classes_with("trees").size() * Rules.TREES_PER_CLASS, "three trees per class")
	for id: StringName in Db.talent_trees:
		check(GameIcons.for_tree(Db.talent_trees[id]) != null, "tree %s has a picture" % id)
	check_eq(Db.consumables.size(), 7, "seven consumables")
	for id: StringName in Db.consumables:
		check(GameIcons.for_consumable(Db.consumables[id]) != null, "consumable %s has a picture" % id)
	check_eq(Db.shrines.size(), 6, "six shrines")
	for id: StringName in Db.shrines:
		check(GameIcons.for_shrine(Db.shrines[id]) != null, "shrine %s has a picture" % id)


func test_the_map_has_no_stale_ids() -> void:
	var map := GameIcons.icon_map()
	var ability_icons: Array[StringName] = []
	for a: AbilityData in Db.abilities.values():
		ability_icons.append(a.icon)
	for key: StringName in map.abilities:
		check(key in ability_icons, "ability entry %s names a shipped icon id" % key)
	var talent_ids: Array[StringName] = []
	for t in _all_talents():
		talent_ids.append(t.id)
	for key: StringName in map.talents:
		check(key in talent_ids, "talent entry %s names a shipped talent" % key)
	for key: StringName in map.trees:
		check(Db.talent_trees.has(key), "tree entry %s" % key)
	for key: StringName in map.consumables:
		check(Db.consumables.has(key), "consumable entry %s" % key)
	for key: StringName in map.shrines:
		check(Db.shrines.has(key), "shrine entry %s" % key)
	for key: StringName in map.schools:
		check(key in AbilityIcon.SCHOOL_COLORS, "school entry %s" % key)
	for key: StringName in map.stats:
		check(TalentGlyph.is_stat(key), "stat entry %s is a stat id" % key)
	for school: StringName in AbilityIcon.SCHOOL_COLORS:
		check(map.schools.has(school), "the school %s has a fallback picture" % school)


func test_the_pictures_are_cached_and_shared() -> void:
	var a := Db.abilities[&"whirlwind"]
	check(GameIcons.for_ability(a) == GameIcons.for_ability(a), "the same texture instance every time")
	check(GameIcons.for_ability(a) == GameIcons.texture_at(GameIcons.icon_map().abilities[&"whirlwind"]), "by path and by id")
	var one := AbilityIcon.create(50.0)
	var two := AbilityIcon.create(36.0, false)
	one.set_ability(a)
	two.set_ability(a)
	nodes.append(one)
	nodes.append(two)
	check(one.icon_texture != null and one.icon_texture == two.icon_texture, "two icons of one ability share the texture")
	# Two ids that share a picture (the stat fallback of &"max_hp" and &"stamina") share the texture too.
	check(GameIcons.for_stat(&"max_hp") == GameIcons.for_stat(&"stamina"), "one texture per path")
	check(GameIcons.texture_at("") == null and GameIcons.texture_at("res://nope.svg") == null, "missing paths give null")


func test_lookups_fall_back_in_order() -> void:
	var t := TalentData.new()
	t.id = &"zz_unknown_talent"
	check(GameIcons.for_talent(t) == null, "an unknown talent without icon: no picture (the kind glyph)")
	t.icon = &"crit"
	check(GameIcons.for_talent(t) == GameIcons.for_stat(&"crit"), "its stat id")
	t.icon = &"whirlwind"
	check(GameIcons.for_talent(t) == GameIcons.for_ability_ids(&"whirlwind"), "its ability id")
	t.icon = &""
	t.ability = &"charge"
	check(GameIcons.for_talent(t) == GameIcons.for_ability_ids(&"charge"), "a modifier: its ability")
	var a := AbilityData.new()
	a.id = &"mage_blink"
	a.class_id = &"mage"
	a.icon = &"zz_unknown_icon"
	check(GameIcons.for_ability(a) == GameIcons.for_ability_ids(&"blink"), "the id without the class prefix")
	a.id = &"zz"
	a.class_id = &""
	check(GameIcons.for_ability(a) == null, "an unknown ability: no picture of its own")
	check(GameIcons.for_ability(null) == null and GameIcons.for_talent(null) == null and GameIcons.for_tree(null) == null, "null in, null out")
	check(GameIcons.for_consumable(null) == null and GameIcons.for_shrine(null) == null, "null in, null out")


# --- The controls ----------------------------------------------------------------------------------

func test_ability_icons_show_the_picture_and_keep_the_glyph_as_the_fallback() -> void:
	for id: StringName in Db.abilities:
		var icon := AbilityIcon.create(50.0)
		icon.set_ability(Db.abilities[id])
		nodes.append(icon)
		check(icon.icon_texture != null, "%s draws its picture" % id)
		check(icon.glyph != AbilityIcon.Glyph.GENERIC, "%s keeps its procedural glyph underneath" % id)
		icon.set_ability(null)
		check(icon.icon_texture == null, "an emptied slot has no picture")
	# New content without a map entry: its glyph rule (id / token), then the school's picture.
	var made_up := AbilityData.new()
	made_up.id = &"zz_firebolt"
	made_up.icon = &"zz_firebolt"
	made_up.school = &"fire"
	var by_rule := AbilityIcon.create(50.0)
	by_rule.set_ability(made_up)
	nodes.append(by_rule)
	check(by_rule.icon_texture == null and by_rule.glyph == AbilityIcon.Glyph.FIRE, "a token rule keeps its glyph (no picture)")
	var plain := AbilityData.new()
	plain.id = &"zz_mystery"
	plain.icon = &"zz_mystery"
	plain.school = &"frost"
	var by_school := AbilityIcon.create(50.0)
	by_school.set_ability(plain)
	nodes.append(by_school)
	check(by_school.icon_texture == GameIcons.for_school(&"frost"), "no rule at all: the school's picture")
	check(AbilityIcon.glyph_is_specific(&"whirlwind") and not AbilityIcon.glyph_is_specific(&"zz_mystery"), "glyph_is_specific")


func test_ability_icons_draw_pictures_and_the_overlays_still_draw() -> void:
	var box := _add(HBoxContainer.new())
	for i in 4:
		var icon := AbilityIcon.create(50.0 - i * 8.0, i < 2)
		icon.set_ability(Db.abilities[[&"whirlwind", &"blink", &"vanish", &"fear"][i]])
		icon.set_prompt("RT")
		icon.set_rank(i + 1)
		icon.set_charges(1, 2)
		icon.set_state(0.5, 4.0, false)
		box.add_child(icon)
		icon.queue_redraw()
	check_eq(box.get_child_count(), 4, "icons of several sizes built")
	# The picture layer filters with mipmaps.
	var layer := (box.get_child(0) as AbilityIcon).get_child(0, true) as CanvasItem
	check(layer != null and layer.texture_filter == GameIcons.FILTER, "the glyph layer uses the mipmap filter")


func test_talent_nodes_carry_the_talents_picture_on_the_existing_frames() -> void:
	var drawn := 0
	for t in _all_talents():
		var g := TalentNode.make_glyph(t, 48.0)
		nodes.append(g)
		var tex: Texture2D = (g as AbilityIcon).icon_texture if g is AbilityIcon else (g as TalentGlyph).texture
		check(tex != null and tex == GameIcons.for_talent(t), "%s draws its own picture" % t.id)
		drawn += 1
	check_eq(drawn, Rules.classes_with("trees").size() * Rules.TREES_PER_CLASS * 9, "every talent")
	# The glyph source (what the existing tests pin) is unchanged: pictures replace the drawing, not the choice.
	var t := TalentData.new()
	t.icon = &"crit"
	check_eq(TalentNode.source_for(t), "stat:crit", "the source of a stat talent")
	var g := TalentNode.make_glyph(t, 40.0) as TalentGlyph
	nodes.append(g)
	check(g != null and g.glyph == TalentGlyph.Glyph.CRIT and g.texture == GameIcons.for_stat(&"crit"), "a talent without entry: its stat picture")


func test_the_tree_view_shows_the_tree_emblem_and_keeps_the_name_fitting() -> void:
	for tree_id: StringName in Db.talent_trees:
		var v := TalentTreeView.create(Db.talent_trees[tree_id])
		nodes.append(v)
		check(v._emblem != null and v._emblem == GameIcons.for_tree(Db.talent_trees[tree_id]), "%s has its emblem" % tree_id)
		check(v.name_label.position.x >= TalentTreeView.PAD_X + TalentTreeView.EMBLEM_SIZE - 2.0, "%s: the name starts right of the emblem" % tree_id)
		check(TalentTreeView.fitted_name_size(v.name_label.text, v.name_label.size.x) >= TalentTreeView.MIN_NAME_FONT,
				"%s: the name still fits next to the emblem" % tree_id)
		var fs := TalentTreeView.fitted_name_size(v.name_label.text, v.name_label.size.x)
		check(UiTheme.bold_font().get_string_size(v.name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= v.name_label.size.x, "%s: the name is not cut" % tree_id)
	var none := TalentTreeView.create(null)
	nodes.append(none)
	check(none._emblem == null, "no tree: no emblem")


func test_consumable_and_shrine_icons_draw_pictures() -> void:
	var box := _add(HBoxContainer.new())
	for id: StringName in Db.consumables:
		var icon := ConsumableIcon.create(Db.consumables[id], 40.0)
		box.add_child(icon)
		icon.queue_redraw()
		check(icon.texture_filter == GameIcons.FILTER, "%s: mipmap filter" % id)
		check(GameIcons.for_consumable(icon.data) != null, "%s has a picture to draw" % id)
	for id: StringName in Db.shrines:
		var icon := ShrineIcon.create(Db.shrines[id], 40.0, 2)
		box.add_child(icon)
		icon.queue_redraw()
		check(GameIcons.for_shrine(icon.data) != null, "%s has a picture to draw" % id)
	# An id without a map entry keeps its procedural picture (no error, nothing to look up).
	var unknown := ConsumableData.new()
	unknown.id = &"zz_potion"
	unknown.icon_id = &"zz_potion"
	var fallback := ConsumableIcon.create(unknown, 40.0)
	box.add_child(fallback)
	fallback.queue_redraw()
	check(GameIcons.for_consumable(unknown) == null, "unknown consumable: the procedural flask")
	var shrine := ShrineData.new()
	shrine.id = &"zz"
	shrine.icon_id = &"zz"
	check(GameIcons.for_shrine(shrine) == null, "unknown shrine: the procedural altar")
	check_eq(box.get_child_count(), Db.consumables.size() + Db.shrines.size() + 1, "all drawn")


# --- Code rules and credits ------------------------------------------------------------------------

func test_the_ui_code_has_no_shaders_or_instance_uniforms() -> void:
	var files: Array[String] = ["res://scenes/ui/game_icons.gd", "res://data/icons/icon_map.gd"]
	_collect("res://scenes/ui", files)
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		check(not text.contains("instance uniform"), "%s: no instance uniforms" % path)
	var icons_code := FileAccess.get_file_as_string("res://scenes/ui/game_icons.gd")
	check(not icons_code.contains("ShaderMaterial") and not icons_code.contains("shader_type"), "the icon drawing uses no shader")
	check(not icons_code.contains("RunState"), "icons never touch the gameplay state")


func _collect(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_collect(dir + "/" + d, out)


func test_the_credits_name_the_font_and_the_icon_authors() -> void:
	var credits := FileAccess.get_file_as_string("res://CREDITS.md")
	check("## Fonts" in credits and "## Icons" in credits, "a Fonts and an Icons section")
	check("Cinzel" in credits and "Open Font License" in credits and "The Cinzel Project Authors" in credits, "Cinzel, OFL 1.1, its authors")
	check("https://github.com/NDISCOVER/Cinzel" in credits, "the font's home")
	check("game-icons.net" in credits and "Attribution 3.0" in credits, "game-icons.net under CC BY 3.0")
	check("https://creativecommons.org/licenses/by/3.0/" in credits, "the licence link")
	check("Lorc" in credits and "Delapouite" in credits, "the icon authors that are used")
	check(FileAccess.file_exists(ICON_DIR + "/LICENSE.txt"), "the icon licence text is committed")
	# Every author folder that holds an icon is credited (and only used authors are shipped).
	for author in DirAccess.get_directories_at(ICON_DIR):
		check(author.to_lower() in credits.to_lower(), "the author folder %s is credited" % author)
	# Every committed svg is used by the map (nothing unused is shipped).
	var used := GameIcons.icon_map().all_paths()
	for author in DirAccess.get_directories_at(ICON_DIR):
		for f in DirAccess.get_files_at(ICON_DIR + "/" + author):
			if f.ends_with(".svg"):
				check((ICON_DIR + "/" + author + "/" + f) in used, "%s/%s is used by the map" % [author, f])
