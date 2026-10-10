extends TestCase
## LootBag: rarity beam, bob / spin, pickup by living players, banking at wave end.

const EFakes := preload("res://tests/enemies_fakes.gd")
const Support := preload("res://tests/test_loot_support.gd")

var world: Node3D
var arena: EFakes.TestArena


func before_each() -> void:
	RunState.start_run(1, 5)
	world = EFakes.make_world(tree)
	arena = EFakes.arena_of(world)


func after_each() -> void:
	EFakes.free_world(tree, world)
	world = null
	arena = null


func _bag(rarity: int, pos: Vector3 = Vector3.ZERO) -> LootBag:
	var item := Support.make_armor(20, ClassData.ArmorType.CLOTH, 30, rarity)
	item.display_name = "Test Treasure"
	var bag := LootBag.create(item)
	arena.entities.add_child(bag)
	bag.global_position = pos
	return bag


func _beam_of(bag: LootBag) -> MeshInstance3D:
	return bag.get_node(^"Beam") as MeshInstance3D


func test_create_builds_a_bag_with_a_beam() -> void:
	var bag := _bag(Items.Rarity.EPIC)
	check(bag.is_in_group(&"loot_bags"), "group")
	check(not bag.is_collected(), "not collected")
	for part in ["Visual/Body", "Visual/Neck", "Visual/Flare", "Visual/Tie", "Visual/Gem"]:
		check(bag.get_node_or_null(NodePath(part)) is MeshInstance3D, "has %s" % part)
	check(bag.get_node_or_null(^"Beam") is MeshInstance3D, "has a beam")
	check(bag.get_node_or_null(^"GroundGlow") is MeshInstance3D, "has a ground glow")
	check(bag.item != null and bag.item.rarity == Items.Rarity.EPIC, "keeps its item")


func test_beam_uses_the_rarity_colour_and_gets_taller() -> void:
	var last_height := 0.0
	var last_intensity := 0.0
	for rarity in 6:
		var bag := _bag(rarity)
		var beam := _beam_of(bag)
		var mat := beam.material_override as ShaderMaterial
		check_eq(mat.get_shader_parameter("beam_color"), UiTheme.RARITY_COLORS[rarity], "colour of rarity %d" % rarity)
		var height := (beam.mesh as QuadMesh).size.y
		var intensity: float = mat.get_shader_parameter("intensity")
		check(height > last_height, "rarity %d beam is taller" % rarity)
		check(intensity > last_intensity, "rarity %d beam is brighter" % rarity)
		last_height = height
		last_intensity = intensity
		check(LootBag.rarity_color(rarity) == UiTheme.RARITY_COLORS[rarity], "rarity_color helper")
	var common := _beam_of(_bag(Items.Rarity.COMMON))
	check((common.mesh as QuadMesh).size.y <= 3.0, "Common beam is short")
	check(((common.material_override as ShaderMaterial).get_shader_parameter("intensity") as float) < 0.4,
			"Common beam is faint")
	check(LootBag.rarity_color(99) == UiTheme.RARITY_COLORS[5], "out of range clamps")


func test_bags_of_one_rarity_share_materials_and_meshes() -> void:
	var a := _bag(Items.Rarity.RARE)
	var b := _bag(Items.Rarity.RARE)
	check(_beam_of(a).material_override == _beam_of(b).material_override, "shared beam material")
	check(_beam_of(a).mesh == _beam_of(b).mesh, "shared beam mesh")
	check(a.get_node(^"Visual/Body").mesh == b.get_node(^"Visual/Body").mesh, "shared body mesh")


func test_bag_bobs_spins_and_pops_in() -> void:
	var bag := _bag(Items.Rarity.RARE)
	var visual := bag.get_node(^"Visual") as Node3D
	bag._process(0.01)
	check(visual.scale.x < 1.0, "starts small")
	var y0 := visual.position.y
	var yaw0 := visual.rotation.y
	bag._process(0.1)
	check(not is_equal_approx(visual.position.y, y0), "bobs")
	check(not is_equal_approx(visual.rotation.y, yaw0), "spins")
	check(visual.position.y > 0.05, "hovers above the ground")
	bag._process(0.5)
	check_near(visual.scale.x, 1.0, 0.001, "full size after the pop-in")
	check_near(_beam_of(bag).scale.y, 1.0, 0.001, "beam fully grown")


func test_living_player_in_reach_picks_it_up() -> void:
	var bag := _bag(Items.Rarity.RARE, Vector3(3.0, 0.0, 3.0))
	var player := EFakes.spawn_player(world, Vector3(3.8, 0.0, 3.0), 0)
	var loot_signals := Support.count_signal(RunState.team_loot_changed)
	var texts := Vfx.text_count()
	var item := bag.item
	EFakes.step(bag, 0.1)
	check(bag.is_collected(), "collected")
	check(bag.is_queued_for_deletion(), "freed")
	check(not bag.is_in_group(&"loot_bags"), "left the group")
	check_eq(RunState.team_loot.size(), 1, "one item in the team loot")
	check(RunState.team_loot[0] == item, "the very item")
	check_eq(loot_signals[0], 1, "team_loot_changed")
	check(Vfx.text_count() > texts, "the item name floats up")
	check(player.is_inside_tree(), "player unaffected")


func test_out_of_reach_or_downed_players_do_not_collect() -> void:
	var bag := _bag(Items.Rarity.UNCOMMON, Vector3.ZERO)
	var player := EFakes.spawn_player(world, Vector3(1.3, 0.0, 0.0), 0)
	EFakes.step(bag, 0.5)
	check(not bag.is_collected(), "1.3 m is out of reach")
	player.downed = true
	player.global_position = Vector3(0.3, 0.0, 0.0)
	EFakes.step(bag, 0.5)
	check(not bag.is_collected(), "a downed player does not pick up")
	check(RunState.team_loot.is_empty(), "nothing collected")
	player.downed = false
	EFakes.step(bag, 0.1)
	check(bag.is_collected(), "alive again and standing on it")
	player.global_position = Vector3(0.0, 0.0, 0.0)


func test_reach_is_about_one_metre_on_the_ground_plane() -> void:
	var bag := _bag(Items.Rarity.COMMON, Vector3.ZERO)
	var player := EFakes.spawn_player(world, Vector3(0.95, 5.0, 0.0), 0)  # height is ignored
	EFakes.step(bag, 0.1)
	check(bag.is_collected(), "0.95 m counts (ground distance)")
	var far := _bag(Items.Rarity.COMMON, Vector3(10, 0, 0))
	player.global_position = Vector3(10.0 + LootBag.PICKUP_RADIUS + 0.05, 0.0, 0.0)
	EFakes.step(far, 0.1)
	check(not far.is_collected(), "just outside the radius")


func test_collected_only_once() -> void:
	var bag := _bag(Items.Rarity.RARE)
	EFakes.spawn_player(world, Vector3(0.2, 0.0, 0.0), 0)
	EFakes.spawn_player(world, Vector3(-0.2, 0.0, 0.0), 1)
	EFakes.step(bag, 0.2)
	bag.collect(null)
	bag.collect_to_bank()
	check_eq(RunState.team_loot.size(), 1, "the item is only added once")


func test_collect_to_bank_moves_the_item_without_a_collector() -> void:
	var bag := _bag(Items.Rarity.EPIC, Vector3(20, 0, 20))
	var item := bag.item
	var texts := Vfx.text_count()
	bag.collect_to_bank()
	check(bag.is_queued_for_deletion(), "freed")
	check(not bag.is_in_group(&"loot_bags"), "left the group")
	check(RunState.team_loot.size() == 1 and RunState.team_loot[0] == item, "in the team loot")
	check_eq(Vfx.text_count(), texts, "no floating text when banked")
	bag.collect_to_bank()
	check_eq(RunState.team_loot.size(), 1, "banking twice adds once")


func test_wave_end_banks_every_bag() -> void:
	var director := WaveDirector.create(arena)
	world.add_child(director)
	var bags: Array[LootBag] = []
	for i in 3:
		bags.append(_bag(Items.Rarity.UNCOMMON + i, Vector3(10 + i, 0, 10)))
	director.start_wave(1)
	director.stop()
	check_eq(RunState.team_loot.size(), 3, "all three items banked")
	for b in bags:
		check(b.is_queued_for_deletion(), "bag removed")
		check(b.is_collected(), "marked collected")
	check_eq(tree.get_node_count_in_group(&"loot_bags"), 0, "no bags left")
	director.stop()
	check_eq(RunState.team_loot.size(), 3, "stopping again changes nothing")
	var taken := RunState.take_team_loot()
	check_eq(taken.size(), 3, "the loot roll can take them")
