extends TestCase
## AbilityIcon: glyph choice from AbilityData.icon / id / school, tint, cooldown sweep polygon and
## text, description formatting, and that every glyph draws.

const Fakes := preload("res://tests/test_ui_m3_fakes.gd")
const UiFakes := preload("res://tests/ui_fakes.gd")

var nodes: Array[Node] = []


func after_each() -> void:
	for n in nodes:
		UiFakes.free_node(n)
	nodes.clear()


func test_core_ability_icon_ids_have_their_own_glyph() -> void:
	var expected := {
		&"whirlwind": AbilityIcon.Glyph.WHIRLWIND, &"charge": AbilityIcon.Glyph.DASH,
		&"blizzard": AbilityIcon.Glyph.BLIZZARD, &"blink": AbilityIcon.Glyph.BLINK,
		&"consecration": AbilityIcon.Glyph.CONSECRATION, &"word_of_glory": AbilityIcon.Glyph.HEAL,
		&"fan_of_knives": AbilityIcon.Glyph.KNIVES, &"vanish": AbilityIcon.Glyph.VANISH,
		&"rain_of_fire": AbilityIcon.Glyph.RAIN_OF_FIRE, &"drain_life": AbilityIcon.Glyph.DRAIN,
	}
	for id: StringName in expected:
		check_eq(AbilityIcon.glyph_for(id, &"physical"), expected[id], "glyph of %s" % id)


func test_every_shipped_ability_gets_a_specific_glyph() -> void:
	# No ability may fall back to the plain rune: its icon id (or id / school) must be known.
	for class_id in Db.class_ids:
		for a in Db.get_class_data(class_id).abilities:
			if a == null:
				continue
			var g := AbilityIcon.glyph_for_ability(a)
			check(g != AbilityIcon.Glyph.GENERIC, "%s has a real glyph" % a.id)


func test_glyph_fallbacks_id_then_school() -> void:
	check_eq(AbilityIcon.glyph_for(&"mystery", &"fire"), AbilityIcon.Glyph.FIRE, "unknown icon: the school")
	check_eq(AbilityIcon.glyph_for(&"mystery", &"frost"), AbilityIcon.Glyph.FROST, "frost")
	check_eq(AbilityIcon.glyph_for(&"mystery", &"shadow"), AbilityIcon.Glyph.SKULL, "shadow")
	check_eq(AbilityIcon.glyph_for(&"", &"holy"), AbilityIcon.Glyph.HOLY, "no icon at all: the school")
	check_eq(AbilityIcon.glyph_for(&"", &""), AbilityIcon.Glyph.GENERIC, "nothing known: the rune")
	check_eq(AbilityIcon.glyph_for(&"mystery", &"nonsense"), AbilityIcon.Glyph.GENERIC, "unknown school")
	check_eq(AbilityIcon.glyph_for(&"", &"physical", &"heroic_leap"), AbilityIcon.Glyph.DASH, "the ability id is the second guess")
	check_eq(AbilityIcon.glyph_for(&"mystery", &"nature", &"shield_wall"), AbilityIcon.Glyph.SHIELD, "id beats the school")
	check_eq(AbilityIcon.glyph_for(&"Fan Of Knives", &""), AbilityIcon.Glyph.KNIVES, "case / spaces do not matter")


func test_token_rules_use_whole_words() -> void:
	check_eq(AbilityIcon.glyph_for(&"ice_barrier"), AbilityIcon.Glyph.SHIELD, "barrier beats ice")
	check_eq(AbilityIcon.glyph_for(&"frost_nova"), AbilityIcon.Glyph.FROST, "frost nova")
	check_eq(AbilityIcon.glyph_for(&"shadow_bolt"), AbilityIcon.Glyph.BOLT, "bolt")
	check_eq(AbilityIcon.glyph_for(&"hammer_of_justice"), AbilityIcon.Glyph.HAMMER, "hammer")
	check_eq(AbilityIcon.glyph_for(&"divine_shield"), AbilityIcon.Glyph.SHIELD, "shield before divine")
	check(AbilityIcon.glyph_for(&"slice") != AbilityIcon.Glyph.FROST, "'slice' is not ice")
	check(AbilityIcon.glyph_for(&"terrain") != AbilityIcon.Glyph.RAIN_OF_FIRE, "'terrain' is not rain")


func test_colour_is_the_ability_colour_or_the_school() -> void:
	var a := AbilityData.new()
	a.school = &"frost"
	check(AbilityIcon.color_for(a).is_equal_approx(AbilityIcon.SCHOOL_COLORS[&"frost"]), "default white: school colour")
	a.color = Color(0.9, 0.3, 0.2)
	check(AbilityIcon.color_for(a).is_equal_approx(Color(0.9, 0.3, 0.2)), "own colour wins")
	check(AbilityIcon.color_for(null).a > 0.0, "null does not crash")


func test_cooldown_text() -> void:
	check_eq(AbilityIcon.format_cooldown(0.0), "", "nothing")
	check_eq(AbilityIcon.format_cooldown(0.04), "", "a last sliver shows nothing")
	check_eq(AbilityIcon.format_cooldown(0.8), "0.8", "one decimal under 3 s")
	check_eq(AbilityIcon.format_cooldown(2.5), "2.5", "2.5")
	check_eq(AbilityIcon.format_cooldown(3.0), "3", "whole seconds from 3")
	check_eq(AbilityIcon.format_cooldown(7.2), "8", "rounded up: the ability is ready after this many seconds")
	check_eq(AbilityIcon.format_cooldown(15.0), "15", "15")
	check_eq(AbilityIcon.format_cooldown(65.0), "1:05", "from a minute")


func _area(poly: PackedVector2Array) -> float:
	var sum := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		sum += a.x * b.y - b.x * a.y
	return absf(sum) * 0.5


func test_sweep_polygon_covers_the_remaining_share() -> void:
	var rect := Rect2(0, 0, 50, 50)
	check(AbilityIcon.sweep_polygon(rect, 0.0).is_empty(), "no sweep when ready")
	for r in [1.0, 0.75, 0.5, 0.25]:
		var poly := AbilityIcon.sweep_polygon(rect, r)
		check_near(_area(poly) / 2500.0, r, 0.002, "sweep area for ratio %s" % r)
		check(poly[0].is_equal_approx(rect.get_center()), "starts at the centre (%s)" % r)
	# The pie is an angle (like WoW's), so its leading edge sits at (1 - ratio) of the circle,
	# clockwise from 12 o'clock.
	for r in [0.9, 0.6, 0.3, 0.1]:
		var poly := AbilityIcon.sweep_polygon(rect, r)
		var d := poly[1] - rect.get_center()
		var angle := fposmod(atan2(d.x, -d.y), TAU)
		check_near(angle, (1.0 - r) * TAU, 0.001, "leading edge for ratio %s" % r)
	# Shrinks clockwise and ends at 12 o'clock: 25% left = the top-left quadrant.
	var quarter := AbilityIcon.sweep_polygon(rect, 0.25)
	for p in quarter:
		check(p.x <= 25.001 and p.y <= 25.001, "the last quarter is the top-left one: %s" % p)
	# Half left = the left half.
	for p in AbilityIcon.sweep_polygon(rect, 0.5):
		check(p.x <= 25.001, "half left is the left half: %s" % p)


func test_set_state_dims_only_when_unusable_and_off_cooldown() -> void:
	var icon := AbilityIcon.create()
	icon.set_ability(Fakes.ability(&"a"))
	icon.set_state(0.0, 0.0, true)
	check(icon.usable and not icon.is_dimmed(), "ready")
	icon.set_state(0.0, 0.0, false)
	check(icon.is_dimmed(), "not usable, no cooldown: dim")
	icon.set_state(0.5, 3.0, false)
	check(not icon.is_dimmed(), "on cooldown: sweep instead")
	check_eq(icon.sweep_ratio, 0.5, "ratio")
	check_eq(icon.cooldown_text(), "3", "text")
	icon.set_state(7.0, 1.0, false)
	check_eq(icon.sweep_ratio, 1.0, "ratio is clamped")
	icon.free()


func test_empty_slot() -> void:
	var icon := AbilityIcon.create()
	check(icon.is_empty(), "no ability: empty socket")
	icon.set_ability(Fakes.ability(&"a", &"rage", 40.0), -1.0)
	check(not icon.is_empty(), "filled")
	check_eq(icon.cost, 40.0, "cost defaults to the ability's")
	icon.set_ability(null)
	check(icon.is_empty() and icon.cost == 0.0, "emptied")
	icon.free()


func test_format_description() -> void:
	var a := AbilityData.new()
	a.description = "Spin for {duration} sec, striking within {radius} m for {damage_pct}% ({n} times, {chance}%). {missing}"
	a.params = {"duration": 2.0, "radius": 3.5, "damage_pct": 150.0, "n": 3, "chance": 0.3333}
	check_eq(AbilityIcon.format_description(a), "Spin for 2 sec, striking within 3.5 m for 150% (3 times, 0.33%). {missing}", "defaults to the data params, trims .0")
	check_eq(AbilityIcon.format_description(a, {"duration": 4.0, "radius": 5.25}), "Spin for 4 sec, striking within 5.25 m for {damage_pct}% ({n} times, {chance}%). {missing}", "explicit (modded) params replace the data params")
	check_eq(AbilityIcon.format_description(null), "", "null")
	check_eq(AbilityIcon.format_number(2.0), "2", "2.0")
	check_eq(AbilityIcon.format_number(2.50), "2.5", "2.50")
	check_eq(AbilityIcon.format_number(0.004), "0", "tiny")
	check_eq(AbilityIcon.format_number(-1.5), "-1.5", "negative")
	check_eq(AbilityIcon.format_number(12), "12", "int")
	check_eq(AbilityIcon.format_number("x"), "x", "string")


func test_every_glyph_draws() -> void:
	# Drawn for real (a frame is processed by the runner): any broken polygon would log an error.
	var box := VBoxContainer.new()
	tree.root.add_child(box)
	nodes.append(box)
	for g in AbilityIcon.Glyph.values():
		var icon := AbilityIcon.create(60.0)
		icon.set_ability(Fakes.ability(&"x", &"rage", 40.0, 5.0))
		icon.glyph = g
		icon.set_prompt("RT")
		icon.set_state(0.6, 3.0, false)
		box.add_child(icon)
		icon.queue_redraw()
	check_eq(box.get_child_count(), AbilityIcon.Glyph.values().size(), "one icon per glyph")
