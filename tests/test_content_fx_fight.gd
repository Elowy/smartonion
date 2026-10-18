extends TestCase
## M6b CONTENT-FX: a short simulated fight (the same engine as test_procs_smoke.gd) with three
## heroes wearing all 37 new trinkets and Legendaries at once and all 26 new enchantments. It must
## run without one engine or script error and actually fire many of the new procs.

const EFakes := preload("res://tests/enemies_fakes.gd")
const Fakes := preload("res://tests/player_fakes.gd")
const TestUniques := preload("res://tests/test_content_fx_uniques.gd")
const TestEnchants := preload("res://tests/test_content_fx_enchants.gd")
const DT := 1.0 / 60.0
const SECONDS := 24.0
const MAX_ALIVE := 26

## The 13 equipment positions of a hero (two rings, two trinkets).
const SLOT_TYPES: Array[Items.SlotType] = [
	Items.SlotType.HEAD, Items.SlotType.NECK, Items.SlotType.SHOULDERS, Items.SlotType.CHEST,
	Items.SlotType.WRIST, Items.SlotType.HANDS, Items.SlotType.WAIST, Items.SlotType.LEGS,
	Items.SlotType.FEET, Items.SlotType.RING, Items.SlotType.RING, Items.SlotType.TRINKET,
	Items.SlotType.TRINKET,
]

var world: Node3D
var logger: ErrorCounter


func before_each() -> void:
	RunState.start_run(3, 2025)
	RunState.set_wave(12)
	world = EFakes.make_world(tree)


func after_each() -> void:
	if logger != null:
		OS.remove_logger(logger)
		logger = null
	EFakes.free_world(tree, world)
	world = null
	EnemyGrid.mark_dirty()


## Puts [param ids] (new hand-made items, in order) on [param p]'s 13 positions; the first ring
## also carries every new proc enchant and the equip enchants.
func _gear_up(p: Player, ids: Array[StringName], with_enchants: bool) -> void:
	for i in SLOT_TYPES.size():
		var item := ItemInstance.new()
		item.slot_type = SLOT_TYPES[i]
		item.rarity = Items.Rarity.LEGENDARY
		item.display_name = "Fight %d" % i
		if i < ids.size():
			var data := Db.get_unique(ids[i])
			item.source_id = data.id
			item.display_name = data.display_name
			item.unique = true
			item.unique_effect = data.unique_effect
			item.unique_params = data.unique_params.duplicate(true)
		if with_enchants and i == 9:
			for id in TestEnchants.NEW_ON_HIT + TestEnchants.NEW_ON_KILL + TestEnchants.NEW_WHEN_STRUCK:
				item.enchants.append(EnchantRoll.new(Db.get_enchant(id), 1))
		if with_enchants and i == 10:
			for id in TestEnchants.NEW_EQUIP:
				item.enchants.append(EnchantRoll.new(Db.get_enchant(id), 1))
		var equip_slot := Items.equip_slots_for(item.slot_type)[1 if i in [10, 12] else 0]
		check(p.equipment.equip(item, equip_slot), "equipped %s" % item.display_name)
	p.stats.set_source(&"fight", {
		Stats.STAMINA: 400.0, Stats.CRIT: 20.0, Stats.EXTRA_ATTACK: 20.0, Stats.PARRY: 15.0,
		Stats.THORNS: 2.0, Stats.AREA_SIZE: 30.0, Stats.PIERCE: 1.0, Stats.LIFE_ON_KILL: 10.0,
		Stats.XP_GAIN: 10.0, Stats.SPELL_POWER: 4.0, Stats.ATTACK_POWER: 4.0,
	})
	p.hp = p.max_hp()


func _spawn_enemies(rng: RandomNumberGenerator) -> void:
	var ids: Array[StringName] = [&"skeleton_grunt", &"marsh_gurgler", &"candlekin", &"troll_axethrower"]
	var alive := tree.get_node_count_in_group(&"enemies")
	for i in mini(3, MAX_ALIVE - alive):
		var data := Db.get_enemy(ids[rng.randi() % ids.size()])
		if data == null:
			continue
		var angle := rng.randf() * TAU
		var pos := Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(4.0, 8.0)
		EFakes.spawn_enemy(world, data, pos, RunState.wave)


func test_all_new_uniques_and_enchants_survive_a_fight() -> void:
	logger = ErrorCounter.new()
	OS.add_logger(logger)
	var entities := EFakes.arena_of(world).entities
	var all_new := TestUniques._all_new()
	check_eq(all_new.size(), 37, "37 new hand-made items")
	var classes: Array[StringName] = [&"warrior", &"mage", &"rogue"]
	var heroes: Array[Player] = []
	for i in 3:
		var slot := Fakes.make_slot(i, classes[i])
		var p := Player.create(slot)
		entities.add_child(p)
		p.global_position = Vector3(-2.0 + 2.0 * i, 0.0, 0.0)
		var mine: Array[StringName] = []
		for k in range(i * 13, mini(all_new.size(), i * 13 + 13)):
			mine.append(all_new[k])
		_gear_up(p, mine, true)
		p.begin_wave()
		heroes.append(p)
	var total_procs := 0
	for p in heroes:
		total_procs += p.procs.procs.size()
	check(total_procs >= 37 + 3 * 15, "many procs active (%d)" % total_procs)
	Enemy.invalidate_player_cache()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var fired: Dictionary[StringName, int] = {}
	for p in heroes:
		p.procs.proc_fired.connect(func(id: StringName, _effect: StringName) -> void:
			fired[id] = fired.get(id, 0) + 1)
	var kills_before := RunState.kills
	var ticks := int(SECONDS / DT)
	for t in ticks:
		if t % 45 == 0:
			_spawn_enemies(rng)
		EnemyGrid.mark_dirty()
		LivingPlayers.mark_dirty()
		Enemy.invalidate_player_cache()
		for p in heroes:
			if is_instance_valid(p):
				p._physics_process(DT)
				for runner in p.weapons:
					runner.tick(DT)
				p.procs._physics_process(DT)
		for node in tree.get_nodes_in_group(&"enemies"):
			if is_instance_valid(node) and not node.is_queued_for_deletion():
				node._physics_process(DT)
		for node in tree.get_nodes_in_group(&"projectiles"):
			if is_instance_valid(node) and not node.is_queued_for_deletion():
				(node as Projectile).advance(DT)
		for node in tree.get_nodes_in_group(&"pickups"):
			if is_instance_valid(node) and not node.is_queued_for_deletion():
				node._physics_process(DT)
		if t % 300 == 299:
			for p in heroes:  # keep the fight going (a wipe would stop the procs)
				if p.downed:
					p.revive(1.0)
	var total := 0
	for id in fired:
		total += fired[id]
	check_eq(logger.error_count(), 0, "no errors: %s" % [logger.error_samples()])
	check(RunState.kills - kills_before > 10, "enemies died (%d)" % (RunState.kills - kills_before))
	check(total > 100, "procs fired (%d)" % total)
	var new_fired := 0
	for id in all_new + TestEnchants._all_new():
		if fired.has(id):
			new_fired += 1
	check(new_fired >= 25, "many different new procs fired (%d): %s" % [new_fired, fired.keys()])
