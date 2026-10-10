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
	var fx := _effects()
	check_eq(fx.size(), 9, "nine effects under Arena.current.entities")
	for e in fx:
		check(e.global_position.distance_to(p) < 1.0, "%s near its world position" % e.name)
		check(e.get_child_count() <= 4, "%s is cheap (%d children)" % [e.name, e.get_child_count()])
	_run_all(0.5)
	check(_effects().size() > 0 and _effects().size() < 9, "short effects already gone, long ones alive")
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
