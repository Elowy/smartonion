extends TestCase
## M7b VIS-FX (combat juice, visual only): the enemy spawn rise, the pooled visual-only corpses, the
## school-coloured hit sparks and the crit variant, the loot pop / bounce and the pickup magnet streak,
## the boss entrance and the banner slam. Nothing here may touch gameplay: positions, groups, collision
## and RunState.rng are checked.

const EFakes := preload("res://tests/enemies_fakes.gd")
const DT := 1.0 / 60.0
const SCHOOLS: Array[StringName] = [&"physical", &"fire", &"frost", &"arcane", &"holy", &"shadow", &"nature"]

var _arena: Arena
var _extra: Array[Node] = []
var _frame := 100


func before_each() -> void:
	RunState.start_run(1, 777)
	Enemy.invalidate_player_cache()
	EnemyCorpse.reset()
	_arena = Arena.create()
	tree.root.add_child(_arena)
	_frame = 100
	Vfx.reset_budgets()
	Vfx.frame_override = _frame


func after_each() -> void:
	for n in _extra:
		if is_instance_valid(n):
			n.free()
	_extra.clear()
	if is_instance_valid(_arena):
		_arena.free()
	_arena = null
	EnemyCorpse.reset()
	Vfx.reset_budgets()
	Enemy.invalidate_player_cache()


# --- Helpers ---------------------------------------------------------------------------------

## A new rendered frame for the per-frame budgets.
func _next_frame() -> void:
	_frame += 1
	Vfx.frame_override = _frame


func _enemy(id: StringName = &"skeleton_grunt", pos: Vector3 = Vector3(3, 0, 2)) -> Enemy:
	var e := Enemy.create(Db.get_enemy(id), 1)
	_arena.entities.add_child(e)
	e.global_position = pos
	return e


func _fake_player(pos: Vector3, slot_index: int = -1) -> Player:
	var p := EFakes.FakePlayer.new()
	if slot_index >= 0:
		p.slot = PlayerSlot.new(slot_index, ScriptedInput.new("test:%d" % slot_index),
				PlayerManager.PLAYER_COLORS[slot_index])
	_arena.entities.add_child(p)
	p.global_position = pos
	Enemy.invalidate_player_cache()
	return p


func _effects() -> Array[VfxEffect]:
	var out: Array[VfxEffect] = []
	for c in _arena.entities.get_children():
		if c is VfxEffect and not c.is_queued_for_deletion():
			out.append(c)
	return out


func _run_effects(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		for fx in _effects():
			fx._process(DT)
		t += DT


func _holder() -> Node3D:
	return _arena.entities.get_node_or_null(EnemyCorpse.HOLDER_NAME) as Node3D


func _corpses() -> Array[EnemyCorpse]:
	var out: Array[EnemyCorpse] = []
	var h := _holder()
	if h != null:
		for c in h.get_children():
			out.append(c as EnemyCorpse)
	return out


func _run_corpses(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		for c in _corpses():
			if c.is_processing():
				c._process(DT)
		t += DT


func _pressed_spark(school: StringName, crit: bool = false) -> VfxEffect:
	_next_frame()
	var before := _effects().size()
	Vfx.hit_spark(Vector3(1, 0.6, 1), Color(0.9, 0.8, 0.7), school, crit)
	var fx := _effects()
	check_eq(fx.size(), before + 1, "a %s spark spawned" % school)
	return fx[fx.size() - 1]


func _mesh_of(fx: VfxEffect) -> Mesh:
	for c in fx.get_children():
		if c is CPUParticles3D:
			return (c as CPUParticles3D).mesh
	return null


func _flash_color(fx: VfxEffect) -> Color:
	var flash := fx.get_node("Flash") as GeometryInstance3D
	return (flash.material_override as ShaderMaterial).get_shader_parameter(&"fx_color")


# --- Enemy spawn rise ---------------------------------------------------------------------------

func test_spawn_rise_moves_only_the_model() -> void:
	var e := _enemy()
	var pos := e.global_position
	var layer := e.collision_layer
	var mask := e.collision_mask
	var hp := e.hp
	var cooldown := e.attack_cooldown_left
	e.play_spawn_in()
	check(e.model.is_spawning(), "rising")
	var pivot := e.model.get_node("Pivot") as Node3D
	var scale := Db.get_enemy(&"skeleton_grunt").model_scale
	e.model._process(DT)
	check(pivot.position.y < -0.5 * scale, "starts below the ground (%.2f)" % pivot.position.y)
	check(pivot.scale.y < scale * 0.7, "and squashed (%.2f)" % pivot.scale.y)
	var min_y := pivot.position.y
	var turned := false
	for i in 12:
		e.model._process(DT)
		turned = turned or absf(angle_difference(pivot.rotation.y, 0.0)) > 0.3
	check(pivot.position.y > min_y, "rises")
	check(turned, "swirls while it rises")
	for i in 40:
		e.model._process(DT)
	check(not e.model.is_spawning(), "done after %.2f s" % EnemyModel.SPAWN_TIME)
	check_near(pivot.position.y, 0.0, 0.001, "stands on the ground")
	check_near(pivot.scale.x, scale, 0.001, "full size")
	check_near(pivot.scale.y, scale, 0.001, "full height")
	check_eq(e.global_position, pos, "the enemy never moved")
	check_eq(e.collision_layer, layer, "collision layer untouched")
	check_eq(e.collision_mask, mask, "collision mask untouched")
	check_eq(e.hp, hp, "hp untouched")
	check_eq(e.attack_cooldown_left, cooldown, "AI timers untouched")
	check(e.is_in_group(&"enemies"), "still an enemy")
	check_eq(e.get_node("Shape").position, Vector3(0.0, Enemy.BODY_CENTER_HEIGHT, 0.0), "hit shape untouched")


func test_spawn_rise_is_longer_for_bosses_and_a_model_has_no_extra_nodes() -> void:
	var boss := Boss.create(Db.get_boss(&"lich_commander_morvain"), 10)
	_arena.entities.add_child(boss)
	boss.play_spawn_in()
	var normal := _enemy()
	normal.play_spawn_in()
	for i in int(EnemyModel.SPAWN_TIME / DT) + 2:
		boss.model._process(DT)
		normal.model._process(DT)
	check(boss.model.is_spawning(), "the boss is still rising after %.2f s" % EnemyModel.SPAWN_TIME)
	check(not normal.model.is_spawning(), "a normal enemy is up")
	check_near(boss.model.spawn_progress(), EnemyModel.SPAWN_TIME / EnemyModel.SPAWN_TIME_BOSS, 0.05, "about half way")
	for i in int(EnemyModel.SPAWN_TIME_BOSS / DT):
		boss.model._process(DT)
	check(not boss.model.is_spawning(), "the boss is up too")
	check(normal.model.get_child_count() == 1 and normal.model.get_node("Pivot").get_child_count() <= 3,
			"the rise adds no nodes")


func test_models_without_play_spawn_stay_untouched() -> void:
	var m := EnemyModel.new()
	_extra.append(m)
	m.setup(Db.get_enemy(&"candlekin"))
	m._process(DT)
	var pivot := m.get_node("Pivot") as Node3D
	check_near(pivot.position.y, 0.0, 0.0001, "no offset")
	check(not m.is_spawning(), "not spawning")
	check_eq(m.spawn_progress(), 1.0, "progress 1 when idle")


# --- Corpses ------------------------------------------------------------------------------------

func test_a_death_leaves_a_visual_only_corpse() -> void:
	var e := _enemy(&"skeleton_grunt", Vector3(4, 0, -3))
	e.take_damage(1000.0)
	check(e.is_dead(), "dead")
	check_eq(_corpses().size(), 1, "one corpse")
	var c := _corpses()[0]
	check(c.is_inside_tree() and c.visible, "standing in the world")
	check_near(c.global_position.x, 4.0, 0.001, "at the enemy's x")
	check_near(c.global_position.z, -3.0, 0.001, "at the enemy's z")
	check(not c.is_in_group(&"enemies"), "not an enemy")
	for g in c.get_groups():
		check(String(g).begins_with("_"), "no gameplay group (%s)" % g)
	check(_collision_nodes(c).is_empty(), "no collision objects or shapes on the corpse")
	check(c.get_script() == EnemyCorpse, "a plain EnemyCorpse, not the enemy's script")
	var body := c.get_node("Pivot/Body") as MeshInstance3D
	check(body.mesh == (e.model.get_node("Pivot/Body") as MeshInstance3D).mesh, "shares the enemy's body mesh")
	check((c.get_node("Pivot/Arm") as MeshInstance3D).mesh == (e.model.get_node("Pivot/Arm") as MeshInstance3D).mesh,
			"and its arm mesh")
	check(c.get_node("Pivot").get_child_count() <= 3, "small (%d nodes under the pivot)" % c.get_node("Pivot").get_child_count())
	check(not e.is_in_group(&"enemies"), "the enemy itself left the group as before")
	check(e.is_queued_for_deletion(), "and is freed as before")
	# The corpse does not die with the enemy node.
	e.free()
	check(is_instance_valid(c) and c.is_inside_tree(), "the corpse outlives the enemy")


func _collision_nodes(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CollisionObject3D or n is CollisionShape3D or n is Area3D:
			out.append(n)
		stack.append_array(n.get_children())
	return out


func test_corpse_flashes_tips_over_sinks_and_ends() -> void:
	var e := _enemy()
	e.take_damage(1000.0, false, null)
	var c := _corpses()[0]
	var pivot := c.get_node("Pivot") as Node3D
	var body := c.get_node("Pivot/Body") as GeometryInstance3D
	check(Mats.overlay_amount(body) > 0.5, "starts with a white flash")
	var up0 := pivot.global_transform.basis.y.normalized().y
	check(up0 > 0.99, "upright at first")
	_run_corpses(0.25)
	check(pivot.global_transform.basis.y.normalized().y < 0.3, "tipped over (%.2f)" % pivot.global_transform.basis.y.normalized().y)
	check(Mats.overlay_amount(body) < 0.3, "flash gone")
	var y_lying := pivot.position.y
	_run_corpses(0.25)
	check(pivot.position.y < y_lying - 0.2, "sinking (%.2f -> %.2f)" % [y_lying, pivot.position.y])
	check(Mats.overlay_amount(body) > 0.3, "darkening")
	check(pivot.scale.x < Db.get_enemy(&"skeleton_grunt").model_scale, "shrinking as it sinks")
	check(c.visible and c.is_processing(), "still there at 0.5 s")
	_run_corpses(0.3)
	check(not c.visible and not c.is_processing(), "done after about %.1f s" % EnemyCorpse.LIFE[0])
	check_eq(EnemyCorpse.active_count(), 0, "no active corpse")
	check_eq(EnemyCorpse.idle_count(), 1, "parked for reuse")


func test_a_corpse_tips_away_from_the_killer() -> void:
	var killer := _fake_player(Vector3(-4, 0, 0), 0)
	var e := _enemy(&"skeleton_grunt", Vector3(0, 0, 0))
	e.take_damage(1000.0, false, killer)
	var c := _corpses()[0]
	_run_corpses(0.3)
	var top: Vector3 = c.get_node("Pivot").global_transform.basis.y
	check(top.x > 0.5, "the top fell away from the killer (+X): %s" % top)
	killer.free()


func test_corpse_cap_and_pooling() -> void:
	var model := _enemy().model
	var first: Array[EnemyCorpse] = []
	for i in EnemyCorpse.MAX_CORPSES + 25:
		_next_frame()
		var c := EnemyCorpse.spawn(model, Vector3(float(i), 0, 0))
		check(c != null, "corpse %d spawned" % i)
		if i < EnemyCorpse.MAX_CORPSES:
			first.append(c)
	check_eq(EnemyCorpse.active_count(), EnemyCorpse.MAX_CORPSES, "never more than the cap alive")
	check_eq(_corpses().size(), EnemyCorpse.MAX_CORPSES, "and no more nodes than the cap (recycled, not added)")
	# The oldest were recycled for the newest.
	var newest := _corpses().filter(func(c: EnemyCorpse) -> bool: return c.position.x > float(EnemyCorpse.MAX_CORPSES + 20))
	check(newest.size() >= 1, "the newest corpse is there")
	var ids := {}
	for c in _corpses():
		ids[c.get_instance_id()] = true
	for c in first:
		check(ids.has(c.get_instance_id()), "nodes are reused, none was replaced")
	# Finished corpses are pooled and reused.
	_run_corpses(EnemyCorpse.LIFE[0] + 0.1)
	check_eq(EnemyCorpse.active_count(), 0, "all done")
	check_eq(EnemyCorpse.idle_count(), EnemyCorpse.MAX_CORPSES, "all parked in the pool")
	_next_frame()
	var reused := EnemyCorpse.spawn(model, Vector3(1, 0, 1))
	check(ids.has(reused.get_instance_id()), "a new corpse reuses a pooled node")
	check_eq(_corpses().size(), EnemyCorpse.MAX_CORPSES, "the pool did not grow")
	check(reused.visible and reused.is_processing(), "and plays again")
	check_eq(reused.age, 0.0, "from the start")


func test_corpses_are_throttled_per_frame_but_elites_and_bosses_always_show() -> void:
	var model := _enemy().model
	var made := 0
	for i in 30:
		if EnemyCorpse.spawn(model, Vector3(float(i), 0, 0)) != null:
			made += 1
	check_eq(made, EnemyCorpse.MAX_SPAWNS_PER_FRAME, "ordinary corpses are capped per frame")
	check(EnemyCorpse.spawn(model, Vector3.ZERO, EnemyCorpse.Tier.ELITE) != null, "an elite still gets one")
	check(EnemyCorpse.spawn(model, Vector3.ZERO, EnemyCorpse.Tier.BOSS) != null, "and a boss")
	_next_frame()
	check(EnemyCorpse.spawn(model, Vector3.ZERO) != null, "the next frame has a fresh budget")


func test_elite_and_boss_corpses_are_bigger() -> void:
	var e := _enemy(&"skeleton_grunt")
	e.make_elite(EliteAffixes.ENRAGED)
	e.take_damage(100000.0)
	check_eq(_corpses().size(), 1, "an elite leaves a corpse")
	var c := _corpses()[0]
	check_eq(c.tier, EnemyCorpse.Tier.ELITE, "elite tier")
	check(c.life > EnemyCorpse.LIFE[0], "lasts longer")
	check_near(c.scale.x, EliteAffixes.MODEL_SCALE, 0.001, "keeps the elite's size")
	_next_frame()
	var boss := Boss.create(Db.get_boss(&"vorthalax"), 25)
	_arena.entities.add_child(boss)
	boss.global_position = Vector3(-5, 0, 3)
	boss.take_damage(1.0e9)
	var bossy: Array = _corpses().filter(func(x: EnemyCorpse) -> bool: return x.tier == EnemyCorpse.Tier.BOSS)
	check_eq(bossy.size(), 1, "a boss leaves a corpse")
	if bossy.size() == 1:
		var bc: EnemyCorpse = bossy[0]
		check(bc.life >= 1.5, "lingers (%.1f s)" % bc.life)
		var glow := bc.get_node_or_null("Pivot/Glow") as MeshInstance3D
		check(glow != null and glow.visible, "keeps its glowing parts")
	var remains := _effects().filter(func(f: VfxEffect) -> bool: return f.kind == VfxEffect.Kind.REMAINS)
	check_eq(remains.size(), 1, "and a lingering glow")
	if remains.size() == 1:
		check(remains[0].life >= 1.5 and remains[0].get_child_count() <= 4, "a glow that lasts, cheaply")


func test_normal_corpses_have_no_shadow_and_a_released_corpse_forgets_the_old_glow() -> void:
	var e := _enemy(&"candlekin")
	e.make_elite(EliteAffixes.FRENZIED)
	e.take_damage(100000.0)
	var elite := _corpses()[0]
	check(elite.get_node_or_null("Pivot/Glow") != null and elite.get_node("Pivot/Glow").visible, "the flame stays on an elite")
	_run_corpses(2.0)
	_next_frame()
	var plain := _enemy(&"candlekin", Vector3(6, 0, 6))
	plain.take_damage(1000.0)
	var c := _corpses()[0]
	check(c == elite, "the pooled node was reused")
	check(not c.get_node("Pivot/Glow").visible, "an ordinary corpse shows no flame")
	check_eq((c.get_node("Pivot/Body") as GeometryInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"no shadow pass for short-lived corpses")


func test_wave_end_despawn_leaves_no_corpse() -> void:
	var e := _enemy()
	e.despawn()
	check_eq(_corpses().size(), 0, "despawn is not a death")


func test_corpses_share_cached_overlay_materials() -> void:
	var model := _enemy().model
	var base := Mats.cached_count()
	for i in 6:
		_next_frame()
		EnemyCorpse.spawn(model, Vector3(float(i), 0, 0))
	_run_corpses(1.0)
	var after_first := Mats.cached_count()
	for i in 6:
		_next_frame()
		EnemyCorpse.spawn(model, Vector3(float(i), 0, 2))
	_run_corpses(1.0)
	check_eq(Mats.cached_count(), after_first, "a second batch of corpses creates no new materials")
	check(after_first - base <= 24, "only a handful of overlay variants exist (%d)" % (after_first - base))


# --- School-coloured impacts and crits --------------------------------------------------------------

func test_every_school_has_its_own_colour_and_shape() -> void:
	var colors: Array[Color] = []
	var meshes := {}
	for school in SCHOOLS:
		var fx := _pressed_spark(school)
		colors.append(fx.color)
		meshes[_mesh_of(fx)] = true
		check(fx.get_child_count() <= 4, "%s spark is cheap (%d children)" % [school, fx.get_child_count()])
		var expected := Vfx.spark_color(school, Color(0.9, 0.8, 0.7))
		check_near(fx.color.r, expected.r, 0.001, "%s colour (r)" % school)
		check_near(fx.color.b, expected.b, 0.001, "%s colour (b)" % school)
	for i in colors.size():
		for j in range(i + 1, colors.size()):
			var d := Vector3(colors[i].r, colors[i].g, colors[i].b).distance_to(Vector3(colors[j].r, colors[j].g, colors[j].b))
			check(d > 0.12, "%s and %s sparks differ (%.2f)" % [SCHOOLS[i], SCHOOLS[j], d])
	check(meshes.size() >= 5, "small shape variation per school (%d distinct spark meshes)" % meshes.size())
	check(Vfx.spark_color(&"no_such_school", Color.RED) == Color.RED, "unknown school: the caller's colour")


func test_school_sparks_keep_a_faint_tint_of_the_caller() -> void:
	var a := Vfx.spark_color(&"fire", Color(0.0, 0.0, 1.0))
	var b := Vfx.spark_color(&"fire", Color(1.0, 0.0, 0.0))
	check(a != b, "the tint shows")
	check(a.r > a.b, "but it is still a fire colour")
	check(Vfx.SCHOOL_TINT_KEEP <= 0.25, "faint")


func test_legacy_sparks_without_a_school_still_work() -> void:
	_next_frame()
	Vfx.hit_spark(Vector3.ZERO, Color(0.2, 0.4, 0.3))
	var fx := _effects()[0]
	check_eq(fx.kind, VfxEffect.Kind.SPARK, "spark")
	check_near(fx.color.g, 0.4, 0.001, "the caller's colour stays")
	check(fx.get_child_count() == 2, "flash + sparks")


func test_class_kit_colours_are_recognised_as_schools() -> void:
	check_eq(Vfx.school_for_color(PaladinKit.HOLY_COLOR), &"holy", "paladin holy")
	check_eq(Vfx.school_for_color(MageSpell.FIRE_COLOR), &"fire", "mage fire")
	check_eq(Vfx.school_for_color(MageSpell.FROST_COLOR), &"frost", "mage frost")
	check_eq(Vfx.school_for_color(MageSpell.ARCANE_COLOR), &"arcane", "mage arcane")
	check_eq(Vfx.school_for_color(RogueVfx.SHADOW_COLOR), &"shadow", "rogue shadow")
	check_eq(Vfx.school_for_color(RogueVfx.POISON_COLOR), &"nature", "rogue poison")
	for school in SCHOOLS:
		check_eq(Vfx.school_for_color(ProcVfx.school_color(school)), school, "round trip %s" % school)
	check_eq(Vfx.school_for_color(Color(0.2, 0.3, 0.4)), &"", "an arbitrary colour is no school")
	# A spark in a kit colour gets that school's shape.
	_next_frame()
	Vfx.hit_spark(Vector3.ZERO, MageSpell.FROST_COLOR)
	var frost := _effects()[0]
	var ref := _pressed_spark(&"frost")
	check(_mesh_of(frost) == _mesh_of(ref), "frost-coloured sparks get the frost shape")
	check_near(frost.color.r, MageSpell.FROST_COLOR.r, 0.001, "and keep the ability's own colour")


func test_weapon_hits_pass_their_school_and_crit() -> void:
	# The call sites: a magic weapon's school reaches the spark. WeaponData.school drives it.
	var staff := Db.get_weapon(&"staff")
	check(staff != null and staff.school != &"physical", "the staff is a spell school (%s)" % (staff.school if staff else ""))
	var sword := Db.get_weapon(&"sword")
	check_eq(sword.school, &"physical", "swords are physical")
	_next_frame()
	Vfx.hit_spark(Vector3.ZERO, Color.WHITE, staff.school, false)
	var fx := _effects()[0]
	var expected := Vfx.spark_color(staff.school, Color.WHITE)
	check_near(fx.color.r, expected.r, 0.001, "coloured by the staff's school (r)")
	check_near(fx.color.g, expected.g, 0.001, "coloured by the staff's school (g)")


func test_crit_sparks_are_bigger_and_burst_into_stars() -> void:
	var normal := _pressed_spark(&"fire", false)
	var crit := _pressed_spark(&"fire", true)
	check(crit.size > normal.size * 1.5, "bigger flash (%.2f vs %.2f)" % [crit.size, normal.size])
	check(crit.get_child_count() > normal.get_child_count(), "an extra star burst node")
	check(crit.get_child_count() <= 4, "still cheap (%d children)" % crit.get_child_count())
	check(_flash_color(crit).a >= _flash_color(normal).a, "at least as bright")
	check(crit.life > normal.life, "lasts a little longer")
	var stars := 0
	for c in crit.get_children():
		if c is CPUParticles3D and (c as CPUParticles3D).mesh == Vfx._star_mesh():
			stars += 1
	check_eq(stars, 1, "one star particle node")
	_run_effects(1.0)
	check_eq(_effects().size(), 0, "both free themselves")


func test_sparks_are_throttled_per_frame_and_by_count() -> void:
	var made := 0
	for i in 100:
		var before := _effects().size()
		Vfx.hit_spark(Vector3(i, 0, 0), Color.WHITE, &"physical")
		made += _effects().size() - before
	check_eq(made, Vfx.SPARKS_PER_FRAME, "ordinary sparks capped per frame")
	var crits := 0
	for i in 30:
		var before := _effects().size()
		Vfx.hit_spark(Vector3(i, 0, 0), Color.WHITE, &"physical", true)
		crits += _effects().size() - before
	check_eq(crits, Vfx.CRIT_SPARKS_EXTRA, "crits have a little extra room")
	# Live sparks are capped too: fill the screen over several frames.
	for f in 12:
		_next_frame()
		for i in Vfx.SPARKS_PER_FRAME:
			Vfx.hit_spark(Vector3.ZERO, Color.WHITE, &"fire")
	check(Vfx.spark_count() <= Vfx.MAX_SPARKS_ALIVE + Vfx.CRIT_SPARKS_EXTRA, "live sparks capped (%d)" % Vfx.spark_count())
	_next_frame()
	var before := _effects().size()
	Vfx.hit_spark(Vector3.ZERO, Color.WHITE, &"fire")
	check_eq(_effects().size(), before, "an ordinary spark is dropped while the screen is full")
	Vfx.hit_spark(Vector3.ZERO, Color.WHITE, &"fire", true)
	check_eq(_effects().size(), before + 1, "a crit still shows")
	_arena.free()
	check_eq(Vfx.spark_count(), 0, "the counter is released with the effects")


func test_new_effects_free_themselves() -> void:
	for school in SCHOOLS:
		_next_frame()
		Vfx.hit_spark(Vector3(1, 0.5, 1), Color.WHITE, school, school == &"holy")
	Vfx.boss_entrance(Vector3(2, 0, 2), 1.8, Color(0.9, 0.2, 0.15))
	Vfx.boss_remains(Vector3(-2, 0, 2), Color(0.5, 0.8, 1.0), 1.0)
	check_eq(_effects().size(), SCHOOLS.size() + 2, "nine effects")
	for fx in _effects():
		check(fx.get_child_count() <= 4, "%s is cheap (%d children)" % [fx.name, fx.get_child_count()])
	_run_effects(0.6)
	check(_effects().size() > 0, "the long ones are alive")
	_run_effects(2.5)
	check_eq(_effects().size(), 0, "everything freed itself")
	_arena.free()
	check_eq(Vfx.spark_count(), 0, "spark counter back at 0")


# --- Boss entrance ----------------------------------------------------------------------------------

func test_boss_entrance_flares_rises_and_fades() -> void:
	Vfx.boss_entrance(Vector3(3, 0, -2), 1.9, Color(0.9, 0.2, 0.15))
	var fx := _effects()[0]
	check_eq(fx.kind, VfxEffect.Kind.ENTRANCE, "entrance effect")
	check(fx.get_child_count() <= 4, "cheap (%d children)" % fx.get_child_count())
	check(fx.get_node_or_null("Rune") != null and fx.get_node_or_null("Column") != null and fx.get_node_or_null("Ring") != null,
			"rune, light shaft and shock ring")
	var dust := 0
	for c in fx.get_children():
		if c is CPUParticles3D:
			dust += 1
	check_eq(dust, 1, "rising dust")
	check_near(fx.global_position.x, 3.0, 0.001, "at the boss")
	check_near((fx.get_node("Ring") as Node3D).global_position.y, Vfx.GROUND_Y, 0.001, "ring on the ground")
	var column := fx.get_node("Column") as Node3D
	var rune := fx.get_node("Rune") as Node3D
	fx._process(0.05)
	var h1 := column.scale.y
	var d1 := rune.scale.x
	fx._process(0.2)
	check(column.scale.y > h1 and column.scale.y > 3.0, "the shaft shoots up (%.1f m)" % column.scale.y)
	check(rune.scale.x > d1, "the rune flares open")
	var fade_early: float = (column.material_override as ShaderMaterial).get_shader_parameter(&"fx_fade")
	fx._process(0.9)
	var fade_late: float = (column.material_override as ShaderMaterial).get_shader_parameter(&"fx_fade")
	check(fade_late < fade_early, "and fades")
	fx._process(1.0)
	check(fx.is_queued_for_deletion(), "gone after its life")


func test_banner_slams_in_for_bosses() -> void:
	var hud := Hud.create()
	tree.root.add_child(hud)
	hud.show_banner("The Warden Awakens", UiTheme.RED, [], true)
	check(hud.is_banner_visible(), "shown")
	check(hud.banner_label.scale.x >= Hud.BANNER_SLAM_FROM - 0.001, "starts huge (%.2f)" % hud.banner_label.scale.x)
	hud.show_banner("Wave 3")
	check(hud.banner_label.scale.x < 1.5, "a normal banner starts at its usual size")
	check(Hud.BANNER_SLAM_TIME + Hud.BANNER_SLAM_SETTLE < 0.3, "the slam is short")
	hud.free()


# --- Loot pop and magnet streak ----------------------------------------------------------------------

func test_hop_curve_lands_and_bounces_once() -> void:
	check_near(Vfx.hop_height(0.0), 0.0, 0.0001, "starts on the ground")
	check_near(Vfx.hop_height(Vfx.HOP_SPLIT), 0.0, 0.0001, "lands")
	check_near(Vfx.hop_height(1.0), 0.0, 0.0001, "and rests at the end")
	check_near(Vfx.hop_height(Vfx.HOP_SPLIT * 0.5), Vfx.HOP_PEAK, 0.0001, "peak of the arc")
	check_near(Vfx.hop_height(Vfx.HOP_SPLIT + (1.0 - Vfx.HOP_SPLIT) * 0.5), Vfx.HOP_BOUNCE, 0.0001, "peak of the bounce")
	var rises := 0
	var prev := 0.0
	for i in 101:
		var h := Vfx.hop_height(float(i) / 100.0)
		check(h >= 0.0, "never below the ground")
		if h > prev + 0.0001 and prev <= 0.0001:
			rises += 1
		prev = h
	check_eq(rises, 2, "two rises: the toss and one bounce")
	check_eq(Vfx.hop_travel_left(0.0), 1.0, "the toss offset is all there at the start")
	check_eq(Vfx.hop_travel_left(Vfx.HOP_SPLIT), 0.0, "and gone at the first landing")
	check_eq(Vfx.hop_travel_left(1.0), 0.0, "and stays gone")


func test_a_pickup_pops_out_but_lands_on_its_gameplay_position() -> void:
	var p := Pickup.drop(_arena.entities, 3, 2, Vector3(5, 0, 4))
	check(p != null and p.is_popping(), "popping")
	var node_pos := p.global_position
	var visual := p.get_node("Visual") as Node3D
	p._process(DT)
	var tossed := Vector2(visual.position.x, visual.position.z)
	check(tossed.length() >= Pickup.POP_REACH_MIN * 0.9, "the model starts off to the side (%.2f m)" % tossed.length())
	var peak := 0.0
	var steps := int(Pickup.POP_TIME / DT) + 2
	for i in steps:
		p._process(DT)
		check_eq(p.global_position, node_pos, "the pickup itself never moves")
		peak = maxf(peak, visual.position.y - Pickup.HOVER_HEIGHT)
	check(peak > Pickup.POP_PEAK * 0.7, "arcs up (%.2f m)" % peak)
	check(not p.is_popping(), "done")
	check_near(visual.position.x, 0.0, 0.0001, "the model landed on the node (x)")
	check_near(visual.position.z, 0.0, 0.0001, "and (z)")
	check(absf(visual.position.y - Pickup.HOVER_HEIGHT) <= Pickup.BOB_HEIGHT + 0.001, "and rests at its hover height")
	check_eq(p.gold, 3, "gold untouched")
	check_eq(p.xp, 2, "xp untouched")


func test_a_loot_bag_pops_out_but_lands_on_its_gameplay_position() -> void:
	var item := ItemInstance.new()
	item.rarity = Items.Rarity.EPIC
	var bag := LootDrops.drop_item(item, Vector3(-3, 0, 2))
	check(bag != null and bag.is_popping(), "popping")
	var node_pos := bag.global_position
	var visual := bag.get_node("Visual") as Node3D
	bag._process(DT)
	check(Vector2(visual.position.x, visual.position.z).length() >= LootBag.HOP_REACH_MIN * 0.9, "tossed in from the side")
	var peak := 0.0
	for i in int(LootBag.HOP_TIME / DT) + 3:
		bag._process(DT)
		check_eq(bag.global_position, node_pos, "the bag itself never moves")
		peak = maxf(peak, visual.position.y - LootBag.HOVER_HEIGHT)
	check(peak > LootBag.HOP_PEAK * 0.6, "arcs up (%.2f m)" % peak)
	check(not bag.is_popping(), "done")
	check_near(visual.position.x, 0.0, 0.0001, "landed (x)")
	check_near(visual.position.z, 0.0, 0.0001, "landed (z)")
	check(bag.get_node_or_null("Beam") != null, "the rarity beam stays")
	var player := _fake_player(Vector3(-3, 0, 2))
	bag._physics_process(DT)
	check(bag.is_collected(), "and it is collected at its gameplay position as before")
	player.free()


func test_pickup_merge_does_not_pop_again() -> void:
	var host := Pickup.drop(_arena.entities, 1, 0, Vector3.ZERO)
	for i in 40:
		host._process(DT)
	check(not host.is_popping(), "landed")
	host.absorb(2, 1)
	check(not host.is_popping(), "absorbing loot does not toss it again")


func test_pulled_pickups_leave_a_capped_streak() -> void:
	var player := _fake_player(Vector3(0, 0, 0))
	var pickups: Array[Pickup] = []
	for i in Pickup.TRAIL_MAX + 6:
		var p := Pickup.create(2, 0)
		_arena.entities.add_child(p)
		p.global_position = Vector3(1.0 + float(i % 3) * 0.1, 0.0, float(i) * 0.02)
		pickups.append(p)
		p._physics_process(DT)
	var trails := 0
	for p in pickups:
		p._process(DT)
		if p.has_trail():
			trails += 1
	check_eq(trails, Pickup.TRAIL_MAX, "at most %d streaks at once" % Pickup.TRAIL_MAX)
	check_eq(Pickup.trail_count(), Pickup.TRAIL_MAX, "and the counter agrees")
	var p0 := pickups[0]
	var streak := p0.get_node("Trail") as Node3D
	check(streak.scale.z >= Pickup.TRAIL_MIN - 0.001 and streak.scale.z <= Pickup.TRAIL_LONGEST + 0.001, "short (%.2f m)" % streak.scale.z)
	# The streak trails behind: the target is at -X from the pickup, so the tail points to +X.
	check(streak.position.x > 0.05, "behind the pickup (%.2f)" % streak.position.x)
	check(streak.material_override is ShaderMaterial, "one cached material per colour")
	var p1 := pickups[1]
	check((p1.get_node("Trail") as MeshInstance3D).material_override == streak.material_override, "shared")
	# Collected pickups free their slot.
	for p in pickups:
		if is_instance_valid(p):
			p.free()
	var fresh := Pickup.create(1, 0)
	_arena.entities.add_child(fresh)
	fresh.global_position = Vector3(2, 0, 0)
	fresh._physics_process(DT)
	fresh._process(DT)
	check(fresh.has_trail(), "freed slots are reusable")
	player.free()


func test_an_idle_pickup_shows_no_streak() -> void:
	var p := Pickup.create(1, 0)
	_arena.entities.add_child(p)
	p._process(DT)
	check(not p.has_trail(), "no streak while it lies there")
	check(p.get_node_or_null("Trail") == null, "not even a node")


# --- Determinism ------------------------------------------------------------------------------------------

func test_the_effects_never_touch_the_gameplay_rng() -> void:
	var model := _enemy().model  # (creating an enemy itself draws from the gameplay rng)
	RunState.rng.seed = 424242
	RunState.rng.randi()
	var before := RunState.rng.state
	model.play_spawn()
	for i in 40:
		model._process(DT)
	for school in SCHOOLS:
		_next_frame()
		Vfx.hit_spark(Vector3.ZERO, Color.WHITE, school, true)
	for i in 60:
		_next_frame()
		EnemyCorpse.spawn(model, Vector3.ZERO, EnemyCorpse.Tier.BOSS)
	Vfx.boss_entrance(Vector3.ZERO, 1.5, Color.RED)
	Vfx.boss_remains(Vector3.ZERO, Color.RED, 1.5)
	var p := Pickup.create(1, 1)
	_arena.entities.add_child(p)
	p.start_pop()
	var bag := LootBag.create(ItemInstance.new())
	_arena.entities.add_child(bag)
	for i in 60:
		p._process(DT)
		bag._process(DT)
	_run_effects(2.0)
	_run_corpses(2.0)
	check_eq(RunState.rng.state, before, "RunState.rng state is untouched")
	var expected := RandomNumberGenerator.new()
	expected.seed = 424242
	expected.randi()
	check_eq(RunState.rng.randi(), expected.randi(), "the next gameplay draw is the one a plain run gets")


func test_the_fx_shaders_use_no_instance_uniforms() -> void:
	check(not Vfx._TRAIL_CODE.contains("instance"), "the pickup streak shader has no instance uniform")
	check(not Vfx._TRAIL_CODE.contains("hint_"), "and nothing exotic")
	check(Vfx._TRAIL_CODE.contains("uniform vec4 trail_color"), "its colour is a plain uniform of a per-colour material")
