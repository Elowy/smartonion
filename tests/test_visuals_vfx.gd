extends TestCase
## Vfx: every effect spawns under the arena's entities root and frees itself.

var _arena: Arena
var _extra: Array[Node] = []


func before_each() -> void:
	_arena = Arena.create()
	tree.root.add_child(_arena)


func after_each() -> void:
	for n in _extra:
		if is_instance_valid(n):
			n.free()
	_extra.clear()
	if is_instance_valid(_arena):
		_arena.free()
	_arena = null


func _effects() -> Array[VfxEffect]:
	var out: Array[VfxEffect] = []
	for c in _arena.entities.get_children():
		if c is VfxEffect and not c.is_queued_for_deletion():
			out.append(c)
	return out


func _run_all(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		for fx in _effects():
			fx._process(1.0 / 30.0)
		t += 1.0 / 30.0


func test_every_effect_spawns_and_frees_itself() -> void:
	var p := Vector3(2, 0, -3)
	Vfx.floating_text(p, "12", Color.WHITE)
	Vfx.floating_text(p, "37!", Color.YELLOW, 1.5)
	Vfx.slash_arc(p, Vector3(1, 0, 0), 2.0, 110.0, Color.WHITE)
	Vfx.hit_spark(p, Color.ORANGE)
	Vfx.death_puff(p, Color.GRAY, 1.2)
	Vfx.explosion(p, 1.6, Color.PURPLE)
	Vfx.spawn_telegraph(p, 1.0, 1.0)
	Vfx.level_up_burst(p)
	Vfx.pickup_sparkle(p)
	Vfx.resurrect_column(p)
	var fx := _effects()
	check_eq(fx.size(), 10, "ten effects under Arena.current.entities")
	for e in fx:
		check(e.global_position.distance_to(p) < 1.0, "%s near its world position" % e.name)
		check(e.get_child_count() <= 4, "%s is cheap (%d children)" % [e.name, e.get_child_count()])
	_run_all(0.5)
	check(_effects().size() > 0 and _effects().size() < 10, "short effects already gone, long ones alive")
	_run_all(1.5)
	check_eq(_effects().size(), 0, "everything freed itself")


func test_telegraph_lives_for_its_duration() -> void:
	Vfx.spawn_telegraph(Vector3.ZERO, 1.2, 2.0)
	var fx := _effects()[0]
	_run_all(1.5)
	check(not fx.is_queued_for_deletion(), "still warning after 1.5 s")
	var rune := fx.get_node("Rune") as Node3D
	check_near(rune.scale.x, 2.4, 0.01, "rune diameter = 2 x radius")
	_run_all(0.8)
	check(fx.is_queued_for_deletion(), "gone after the warning")


func test_floating_text_rises_and_fades() -> void:
	Vfx.floating_text(Vector3(0, 1, 0), "Dodge", Color.CYAN)
	var fx := _effects()[0]
	var label := fx.get_node("Label") as Label3D
	check_eq(label.text, "Dodge", "text")
	check(label.billboard == BaseMaterial3D.BILLBOARD_ENABLED, "billboard")
	check(label.outline_size > 0, "outlined")
	var y0 := fx.position.y
	fx._process(0.4)
	check(fx.position.y > y0 + 0.5, "rises")
	fx._process(0.3)
	check(label.modulate.a < 1.0, "fades")


func test_crit_text_is_bigger() -> void:
	Vfx.floating_text(Vector3.ZERO, "5", Color.WHITE, 1.0)
	Vfx.floating_text(Vector3.ZERO, "50", Color.WHITE, 1.5)
	var fx := _effects()
	var a := fx[0].get_node("Label") as Label3D
	var b := fx[1].get_node("Label") as Label3D
	check(b.pixel_size > a.pixel_size * 1.4, "crit text larger")


func test_text_cap() -> void:
	var before := Vfx.text_count()
	for i in Vfx.MAX_TEXTS + 20:
		Vfx.floating_text(Vector3.ZERO, str(i), Color.WHITE)
	check_eq(Vfx.text_count(), maxi(before, Vfx.MAX_TEXTS), "normal texts capped")
	Vfx.floating_text(Vector3.ZERO, "CRIT", Color.YELLOW, 1.5)
	check_eq(Vfx.text_count(), maxi(before, Vfx.MAX_TEXTS) + 1, "crits always show")
	_arena.free()
	check_eq(Vfx.text_count(), 0, "counter released when texts are freed")


func test_falls_back_without_arena() -> void:
	_arena.free()
	check(Arena.current == null, "no arena")
	var parent := Vfx.effect_parent()
	check(parent != null, "falls back to the scene / root")
	var before := parent.get_child_count()
	Vfx.pickup_sparkle(Vector3.ZERO)
	check_eq(parent.get_child_count(), before + 1, "spawned under the fallback parent")
	var fx := parent.get_child(parent.get_child_count() - 1)
	_extra.append(fx)
	check(fx is VfxEffect, "effect node")


func test_slash_arc_faces_direction() -> void:
	Vfx.slash_arc(Vector3.ZERO, Vector3(1, 0, 0), 2.0, 90.0, Color.WHITE)
	var fx := _effects()[0]
	var forward := fx.transform.basis * Vector3.FORWARD
	check(forward.x > 0.99, "arc centred on the swing direction")
	check_near((fx.get_node("Arc") as Node3D).scale.x, 2.0, 0.001, "scaled to the reach")
	check_near(fx.global_position.y, Vfx.ARC_LIFT, 0.001, "lifted to mid-body height")


func test_ground_rings_snap_to_the_ground() -> void:
	Vfx.explosion(Vector3(1, 0.9, 2), 1.5, Color.ORANGE)
	Vfx.death_puff(Vector3(-1, 0.5, 0), Color.GRAY, 1.0)
	Vfx.level_up_burst(Vector3(3, 0, 1))
	Vfx.resurrect_column(Vector3(-2, 0.6, 1))
	var fx := _effects()
	check_eq(fx.size(), 4, "four effects")
	for e in fx:
		var ring := e.get_node_or_null("Ring") as Node3D
		check(ring != null, "%s has a shock ring" % e.name)
		if ring != null:
			check_near(ring.global_position.y, Vfx.GROUND_Y, 0.001, "%s ring on the ground" % e.name)


func test_resurrect_column_comes_from_the_sky() -> void:
	Vfx.resurrect_column(Vector3(2, 0, 2))
	var fx := _effects()[0]
	fx._process(0.3)
	var column := fx.get_node("Column") as Node3D
	check(column.scale.y >= Vfx.RESURRECT_HEIGHT - 0.001, "tall shaft of light")
	check(column.global_position.distance_to(Vector3(2, 0, 2)) < 0.001, "standing on the revived player")


func test_damage_numbers_merge_per_target() -> void:
	var a := Node3D.new()
	var b := Node3D.new()
	_extra.append(a)
	_extra.append(b)
	var white := Color(1, 1, 1, 0.75)
	Vfx.damage_number(a, Vector3.ZERO, 3.0, white, 0.6)
	Vfx.damage_number(a, Vector3.ZERO, 4.2, white, 0.6)
	check_eq(_effects().size(), 1, "two quick hits on one enemy -> one number")
	var label := _effects()[0].get_node("Label") as Label3D
	check_eq(label.text, "7", "the number adds up")
	check(label.modulate.a <= 0.75 + 0.001, "normal hits are slightly transparent")
	Vfx.damage_number(b, Vector3.ZERO, 2.0, white, 0.6)
	check_eq(_effects().size(), 2, "another enemy gets its own number")
	# A crit landing on a normal number upgrades it.
	Vfx.damage_number(a, Vector3.ZERO, 10.0, Color.YELLOW, 1.1)
	check_eq(label.text, "17", "crit merged")
	check_near(label.pixel_size, Vfx.TEXT_PIXEL_SIZE * 1.1, 0.000001, "upgraded to the crit size")
	# After the merge window a new number starts.
	for fx in _effects():
		fx._process(Vfx.MERGE_WINDOW + 0.02)
	Vfx.damage_number(a, Vector3.ZERO, 5.0, white, 0.6)
	check_eq(_effects().size(), 3, "late hit -> new number")
	# No target: never merged.
	Vfx.damage_number(null, Vector3.ZERO, 1.0, white, 0.6)
	Vfx.damage_number(null, Vector3.ZERO, 1.0, white, 0.6)
	check_eq(_effects().size(), 5, "untargeted numbers stay separate")
	_arena.free()
	check(Vfx._merge.is_empty(), "merge table released with the numbers")


func test_damage_numbers_are_small_and_capped() -> void:
	check(WeaponRunner.NORMAL_TEXT_SIZE <= 0.7, "normal hits small")
	check(WeaponRunner.CRIT_TEXT_SIZE > WeaponRunner.NORMAL_TEXT_SIZE * 1.5, "crits clearly bigger")
	check(WeaponRunner.NORMAL_TEXT_COLOR.a < 1.0, "normal hits translucent")
	check(Vfx.MAX_TEXTS <= 30, "a busy screen shows at most ~28 numbers")
	var before := Vfx.text_count()
	for i in 60:
		Vfx.floating_text(Vector3.ZERO, "C", Color.YELLOW, WeaponRunner.CRIT_TEXT_SIZE)
	check_eq(Vfx.text_count(), maxi(before, Vfx.MAX_TEXTS + Vfx.CRIT_EXTRA_TEXTS), "even crits have a hard cap")


func test_text_arcs_sideways() -> void:
	Vfx.floating_text(Vector3(0, 1, 0), "9", Color.RED, 0.85, 1.0)
	Vfx.floating_text(Vector3(0, 1, 0), "9", Color.RED, 0.85, -1.0)
	var fx := _effects()
	fx[0]._process(0.5)
	fx[1]._process(0.5)
	check(fx[0].position.x > 0.15, "side +1 arcs to the right (%.2f)" % fx[0].position.x)
	check(fx[1].position.x < -0.15, "side -1 arcs to the left (%.2f)" % fx[1].position.x)
	check(fx[0].position.y > 1.4, "and up")


func test_explosion_flash_is_short_and_faint() -> void:
	Vfx.explosion(Vector3(0, 0.5, 0), 2.0, Color.PURPLE)
	var fx := _effects()[0]
	var flash := fx.get_node("Flash") as GeometryInstance3D
	var c: Variant = (flash.material_override as ShaderMaterial).get_shader_parameter(&"fx_color")
	check(c is Color and (c as Color).a <= 0.5, "flash starts faint")
	fx._process(0.05)
	check(flash.scale.x <= 2.0 * Vfx.EXPLOSION_FLASH_SCALE + 0.001, "flash smaller than the blast radius")
	fx._process(Vfx.EXPLOSION_FLASH_TIME)
	check(not flash.visible, "flash gone after %.2f s" % Vfx.EXPLOSION_FLASH_TIME)
	var ring := fx.get_node("Ring") as Node3D
	check(ring.scale.x > 1.0, "the ground ring carries the blast")
