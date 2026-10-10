extends TestCase
## A short simulated fight (synchronous ticks, real Player / Enemy / Projectile / Pickup code)
## with two heroes wearing many proc items – every proc enchant of GDD 5.7 plus the unique
## effects of res://data/uniques/ – and exotic stats. Must run without a single engine or
## script error and actually fire procs.

const EFakes := preload("res://tests/enemies_fakes.gd")
const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0
const SECONDS := 20.0
const MAX_ALIVE := 24

var world: Node3D
var logger: ErrorCounter


func before_each() -> void:
	RunState.start_run(2, 2024)
	RunState.set_wave(6)
	world = EFakes.make_world(tree)


func after_each() -> void:
	if logger != null:
		OS.remove_logger(logger)
		logger = null
	EFakes.free_world(tree, world)
	world = null
	EnemyGrid.mark_dirty()


## Every equipment position gets an item with one unique effect (cycled through the Db's
## uniques); the first ring also carries every proc enchant and a few equip enchants.
func _gear_up(p: Player, offset: int) -> void:
	var ids: Array[StringName] = []
	for id in Db.uniques:
		ids.append(id)
	ids.sort()
	var slot_types: Array[Items.SlotType] = [
		Items.SlotType.HEAD, Items.SlotType.NECK, Items.SlotType.SHOULDERS, Items.SlotType.CHEST,
		Items.SlotType.WRIST, Items.SlotType.HANDS, Items.SlotType.WAIST, Items.SlotType.LEGS,
		Items.SlotType.FEET, Items.SlotType.RING, Items.SlotType.RING, Items.SlotType.TRINKET,
		Items.SlotType.TRINKET,
	]
	for i in slot_types.size():
		var item := ItemInstance.new()
		item.slot_type = slot_types[i]
		item.rarity = Items.Rarity.LEGENDARY
		item.display_name = "Smoke %d" % i
		if not ids.is_empty():
			var data := Db.get_unique(ids[(i + offset) % ids.size()])
			item.source_id = data.id
			item.display_name = data.display_name
			item.unique = true
			item.unique_effect = data.unique_effect
			item.unique_params = data.unique_params.duplicate(true)
		if i == 9:
			for id in Db.enchants:
				var e := Db.get_enchant(id)
				if e.is_proc() or id in [&"zealous", &"brutal", &"splitting", &"executioners"]:
					item.enchants.append(EnchantRoll.new(e, 1))
		var equip_slot := Items.equip_slots_for(item.slot_type)[1 if i in [10, 12] else 0]
		check(p.equipment.equip(item, equip_slot), "equipped %s" % item.display_name)
	p.stats.set_source(&"smoke", {
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
		var pos := Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(5.0, 9.0)
		EFakes.spawn_enemy(world, data, pos, RunState.wave)


func test_proc_heavy_fight_has_no_errors() -> void:
	logger = ErrorCounter.new()
	OS.add_logger(logger)
	var entities := EFakes.arena_of(world).entities
	var heroes: Array[Player] = []
	for i in 2:
		var slot := Fakes.make_slot(i, &"warrior" if i == 0 else &"mage")
		var p := Player.create(slot)
		entities.add_child(p)
		p.global_position = Vector3(-1.0 + 2.0 * i, 0.0, 0.0)
		_gear_up(p, i * 7)
		p.begin_wave()
		heroes.append(p)
	check(heroes[0].procs.procs.size() >= 16, "many procs active (%d)" % heroes[0].procs.procs.size())
	Enemy.invalidate_player_cache()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var fired: Dictionary[StringName, int] = {}
	for p in heroes:
		p.procs.proc_fired.connect(func(id: StringName, _effect: StringName) -> void:
			fired[id] = fired.get(id, 0) + 1)
	var kills_before := RunState.kills
	var ticks := int(SECONDS / DT)
	for t in ticks:
		if t % 60 == 0:
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
	check(total > 30, "procs fired (%d)" % total)
	check(fired.size() >= 8, "many different procs fired: %s" % [fired.keys()])
