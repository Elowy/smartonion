extends TestCase
## M8 P0 – the class order and the content rules: Db.CLASS_ORDER names the Hunter and Shaman after
## the Warlock (ids without data are skipped), and the pending list of content_rules.gd (class
## content that ships in a later package) names only real parts and nothing that already shipped.
## (Headgear: test_m8_headgear.gd, companions and launch flags: test_m8_companion.gd, pseudo ids and
## dual wield: test_m8_vocabulary.gd, class-independent sets: test_m8_sets.gd.) Classes built here
## are fixtures ("zz_" ids), restored after.

const Rules := preload("res://tests/content_rules.gd")
const ClassFixtures := preload("res://tests/class_fixtures.gd")

var classes := ClassFixtures.new()


func after_each() -> void:
	classes.restore()


# --- Class order ------------------------------------------------------------------------------

func test_the_m8_classes_follow_warlock_in_the_class_order() -> void:
	var order := Db.CLASS_ORDER
	check_eq(order.slice(0, 5), Rules.LAUNCH_CLASSES, "launch order")
	check_eq(order.slice(5), [&"hunter", &"shaman"] as Array[StringName], "Hunter, then Shaman")
	# A fixture class (an id outside the order) lands after every listed class.
	classes.add_class()
	var ids: Array[StringName] = []
	for id in Db.CLASS_ORDER:
		if Db.classes.has(id):
			ids.append(id)
	for id in Db.classes:
		if id not in ids:
			ids.append(id)
	check_eq(ids.find(ClassFixtures.FAKE_CLASS), ids.size() - 1, "an unlisted class comes last")


# --- Content that arrives after its class ------------------------------------------------------

func test_the_pending_list_names_real_parts_and_nothing_that_already_shipped() -> void:
	for line in Rules.PENDING:
		var bits := line.split(":")
		check_eq(bits.size(), 2, "'%s' is <class>:<part>" % line)
		if bits.size() != 2:
			continue
		var class_id := StringName(bits[0])
		check(class_id in Db.CLASS_ORDER, "%s: a class of the game" % line)
		check(bits[1] in ["artifact", "set", "items", "trees"], "%s: a known part" % line)
		# Content that exists for a class makes its line stale: delete it (the checks are strict again).
		if Db.classes.has(class_id):
			check_eq(Rules.count_of(class_id, bits[1]), 0, "%s: the content is already there, delete the PENDING line" % line)
	var seen: Array[String] = []
	for line in Rules.PENDING:
		check(line not in seen, "%s is listed once" % line)
		seen.append(line)


func test_every_class_has_three_full_talent_trees() -> void:
	for class_id in Rules.classes_with("trees"):
		check_eq(Rules.count_of(class_id, "trees"), Rules.TREES_PER_CLASS, "%s: %d talent trees" % [class_id, Rules.TREES_PER_CLASS])
		for t in Db.talent_trees_for(class_id):
			check_eq(t.talents.size(), 9, "%s: nine talents" % t.id)
			var points := 0
			for talent in t.talents:
				points += talent.max_rank
			check_eq(points, 22, "%s: 22 points" % t.id)
