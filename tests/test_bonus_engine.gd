extends TestCase
## PlayerBonuses – the bonus-effect engine (M5, T-CORE-A, architecture §2.1): every entry kind
## on inline entries (stats, ability, damage, damage_taken, resource / proc hand-offs, script),
## rank scaling, the "requires" conditions following equipment and learned abilities, script
## diffing / lifecycle / hooks, on_hit's first flag on a real attack, no RNG on the hot paths.

const Fakes := preload("res://tests/player_fakes.gd")
const EFakes := preload("res://tests/enemies_fakes.gd")
const Probe := preload("res://tests/talent_effect_probe.gd")


## ProcSystem that counts the hand-off calls (the real set_extra_procs / refresh still run).
class CountingProcs extends ProcSystem:
	var refreshes := 0
	var handed: Array[StringName] = []
	## Source -> the defs of its last hand-off.
	var last_defs: Dictionary[StringName, Array] = {}

	func refresh() -> void:
		refreshes += 1
		super()

	func set_extra_procs(source: StringName, defs: Array[Dictionary]) -> void:
		handed.append(source)
		last_defs[source] = defs.duplicate(true)
		super(source, defs)


## An enemy that counts as an elite (target condition "elite").
class EliteDummy extends Enemy:
	func is_elite() -> bool:
		return true


var world: Node3D
var nodes: Array[Node] = []


func before_each() -> void:
	RunState.start_run(1, 4242)
	Probe.reset_counts()
	world = EFakes.make_world(tree)


func after_each() -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.free()
	nodes.clear()
	EFakes.free_world(tree, world)
	world = null
	EnemyGrid.mark_dirty()
	Probe.reset_counts()


func _warrior(index: int = 0) -> Player:
	return Fakes.spawn_player(world, index, &"warrior", Vector3(index * 6.0, 0, 0))


static func _put(p: Player, entries: Array, source: StringName = PlayerBonuses.SOURCE_TALENTS) -> void:
	var typed: Array[Dictionary] = []
	typed.assign(entries)
	p.bonuses.set_effects(source, typed)


func _dummy(hp_pct: float = 100.0, elite: bool = false) -> Enemy:
	var e: Enemy = EliteDummy.new() if elite else Enemy.new()
	e.max_hp = 100.0
	e.hp = hp_pct
	nodes.append(e)
	return e


func _item(weapon_id: StringName) -> ItemInstance:
	return ItemInstance.from_weapon(Db.get_weapon(weapon_id), Items.Rarity.COMMON, 1, false)


func _wear(p: Player, item: ItemInstance) -> void:
	p.equipment.add_to_backpack(item)
	check(p.equipment.equip(item), "equip %s" % item.display_name)


# --- stats -------------------------------------------------------------------------------------

func test_stats_fill_a_source_per_bonus_source_and_go_away() -> void:
	var p := _warrior()
	var crit := p.stats.get_raw(Stats.CRIT)
	var strength := p.stats.get_raw(Stats.STRENGTH)
	_put(p, [{"kind": "stats", "stats": {"crit": 2.0, "primary": 1.0}, "rank": 3, "id": "a", "label": "A"},
		{"kind": "stats", "stats": {"crit": 1.0}, "rank": 1, "id": "b", "label": "B"}])
	check_eq(p.stats.get_source(PlayerBonuses.SOURCE_TALENTS), {Stats.CRIT: 7.0, Stats.STRENGTH: 3.0}, "summed, x rank, primary = Strength")
	check_eq(p.stats.get_raw(Stats.CRIT), crit + 7.0, "on the hero")
	_put(p, [{"kind": "stats", "stats": {"armor": 3.0}, "rank": 1}], PlayerBonuses.SOURCE_SETS)
	check_eq(p.stats.get_source(PlayerBonuses.SOURCE_SETS), {Stats.ARMOR: 3.0}, "set bonuses get their own source")
	check_eq(p.stats.get_source(PlayerBonuses.SOURCE_TALENTS), {Stats.CRIT: 7.0, Stats.STRENGTH: 3.0}, "talents untouched")
	_put(p, [])
	check(not p.stats.has_source(PlayerBonuses.SOURCE_TALENTS), "an empty source is removed")
	check_eq(p.stats.get_raw(Stats.CRIT), crit, "crit back")
	check_eq(p.stats.get_raw(Stats.STRENGTH), strength, "strength back")
	check(p.stats.has_source(PlayerBonuses.SOURCE_SETS), "the other source stays")


func test_armor_specialization_counts_talent_primary() -> void:
	var p := _warrior()
	for st in Items.ARMOR_SLOTS:
		var piece := ItemInstance.new()
		piece.display_name = "Plate %d" % st
		piece.slot_type = st
		piece.armor_type = p.class_data.armor_type
		piece.stats[Stats.STRENGTH] = 2.0
		_wear(p, piece)
	check(p.equipment.armor_spec_active(), "Armor Specialization active")
	_put(p, [{"kind": "stats", "stats": {"primary": 5.0}, "rank": 2}])
	var bonus := float(p.stats.get_source(&"armor_spec").get(Stats.STRENGTH, 0.0))
	var rest := p.stats.get_raw(Stats.STRENGTH) - bonus
	check_near(bonus, rest * Equipment.ARMOR_SPEC_BONUS, 0.0001, "10% of the Strength incl. the talents' 10")
	check(rest >= 26.0, "the talents' Strength is in (%s)" % rest)


# --- ability -----------------------------------------------------------------------------------

func test_ability_mods_change_params_and_invalidate_the_cache() -> void:
	var p := _warrior()
	var ww := Db.get_ability(&"whirlwind")
	var before := p.abilities.params_for(ww)
	_put(p, [{"kind": "ability", "match": {"id": "whirlwind"}, "mods": {"radius_add": 1.0, "power_pct": 10.0}, "rank": 2}])
	var after := p.abilities.params_for(ww)
	check(not is_same(after, before), "params re-built")
	check_eq(after["radius"], float(before["radius"]) + 2.0, "radius +1 per rank")
	check_near(float(after["power"]), 1.2, 0.0001, "power +10% per rank")
	var mods := p.bonuses.ability_mods_for(&"whirlwind")
	check(mods.is_read_only(), "cached result is read-only")
	check(is_same(p.bonuses.ability_mods_for(&"whirlwind"), mods), "cached per id")
	check_eq(p.bonuses.ability_mods_for(&"charge"), {}, "other ids untouched")
	_put(p, [])
	check_eq(p.abilities.params_for(ww)["radius"], before["radius"], "removed again")


func test_ability_generic_matches() -> void:
	var p := _warrior()
	_put(p, [
		{"kind": "ability", "match": {"tag": "aoe"}, "mods": {"cost_pct": -10.0}, "rank": 1},
		{"kind": "ability", "match": {"resource": "rage"}, "mods": {"free_chance_add": 5.0}, "rank": 1},
		{"kind": "ability", "match": {"kind": "active"}, "mods": {"cooldown_pct": -4.0}, "rank": 1},
		{"kind": "ability", "match": {"ids": ["charge", "execute"]}, "mods": {"cooldown_add": -1.0}, "rank": 1},
		{"kind": "ability", "match": {"class": true}, "mods": {"power_pct": 2.0}, "rank": 1},
		{"kind": "ability", "match": {"school": "nature"}, "mods": {"power_pct": 50.0}, "rank": 1},
	])
	check_eq(p.bonuses.ability_mods_for(&"whirlwind"), {"cost_pct": -10.0, "free_chance_add": 5.0, "power_pct": 2.0}, "whirlwind: aoe, rage, class")
	check_eq(p.bonuses.ability_mods_for(&"charge"), {"cooldown_add": -1.0, "power_pct": 2.0}, "charge: ids, class")
	check_eq(p.bonuses.ability_mods_for(&"execute"), {"cooldown_pct": -4.0, "cooldown_add": -1.0, "power_pct": 2.0}, "execute: active, ids, class")
	check_eq(p.bonuses.ability_mods_for(&"spirit_wolf"), {"power_pct": 50.0}, "general nature ability: school only (class: true skips general ones)")
	check_eq(p.bonuses.ability_mods_for(&"fireball"), {}, "another class's ability")
	check_near(float(p.abilities.params_for(Db.get_ability(&"whirlwind"))["cost"]), 36.0, 0.0001, "Whirlwind costs 10% less")


func test_ability_mods_sum_and_merge_after_items() -> void:
	var p := _warrior()
	var item := ItemInstance.new()
	item.slot_type = Items.SlotType.HEAD
	item.armor_type = Items.NO_ARMOR
	item.unique_effect = &"ability_mod"
	item.unique_params = {"ability": "whirlwind", "mods": {"radius_add": 1.0}}
	_wear(p, item)
	# (Equipping re-applies the real set bonuses, so the fixture set entry comes after it.)
	_put(p, [{"kind": "ability", "match": {"id": "whirlwind"}, "mods": {"radius_add": 0.5}, "rank": 1}])
	_put(p, [{"kind": "ability", "match": {"id": "whirlwind"}, "mods": {"radius_add": 0.25, "slow": 30.0}, "rank": 1}], PlayerBonuses.SOURCE_SETS)
	check_eq(p.bonuses.ability_mods_for(&"whirlwind"), {"radius_add": 0.75, "slow": 30.0}, "both sources, numbers summed")
	check_eq(p.ability_mods(&"whirlwind"), {"radius_add": 1.75, "slow": 30.0}, "items + bonuses")
	check_eq(p.abilities.params_for(Db.get_ability(&"whirlwind"))["radius"], 3.0 + 1.75, "params_for")


func test_pseudo_ids_reach_the_kits() -> void:
	var w := Fakes.spawn_player(world, 0, &"warlock")
	_put(w, [{"kind": "ability", "match": {"id": "warlock_imp"}, "mods": {"damage_bonus_add": 10.0}, "rank": 2},
		{"kind": "ability", "match": {"class": true}, "mods": {"power_pct": 1.0}, "rank": 1}])
	check_eq(w.bonuses.ability_mods_for(&"warlock_imp"), {"damage_bonus_add": 20.0}, "pseudo id by id only")
	check_eq(w.ability_mods(&"warlock_imp"), {"damage_bonus_add": 20.0}, "through Player.ability_mods")
	check_eq(w.bonuses.ability_mods_for(&"warlock_shards"), {}, "another pseudo id")
	check_eq(w.bonuses.ability_mods_for(&"whirlwind"), {}, "class: true is the owner's class only")


# --- damage / damage_taken ---------------------------------------------------------------------

func test_damage_entries_add_up_with_their_filters() -> void:
	var p := _warrior()
	_put(p, [
		{"kind": "damage", "pct": 2.0, "rank": 2},
		{"kind": "damage", "pct": 5.0, "source": ["dot", "pet"], "rank": 1},
		{"kind": "damage", "pct": 4.0, "school": "fire", "rank": 1},
		{"kind": "damage", "pct": 10.0, "target": "stunned", "rank": 1},
		{"kind": "damage", "pct": 8.0, "target": "below_pct", "target_pct": 35.0, "rank": 1},
		{"kind": "damage", "pct": 20.0, "target": "above_pct", "target_pct": 90.0, "rank": 1},
		{"kind": "damage", "pct": 3.0, "target": "elite", "rank": 1},
		{"kind": "damage", "pct": 7.0, "target": "slowed", "rank": 1},
		{"kind": "damage", "pct": 9.0, "target": "feared", "rank": 1},
		{"kind": "damage", "pct": 6.0, "self_below_pct": 50.0, "rank": 1},
		{"kind": "damage", "pct": 30.0, "self_above_pct": 99.0, "source": "proc", "rank": 1},
	])
	var b := p.bonuses
	var mid := _dummy(60.0)
	check_near(b.damage_mult(null, &"physical", &"weapon"), 1.04, 0.0001, "unconditional x rank")
	check_near(b.damage_mult(mid, &"physical", &"dot"), 1.09, 0.0001, "source dot")
	check_near(b.damage_mult(mid, &"fire", &"pet"), 1.13, 0.0001, "school fire + source pet")
	check_near(b.damage_mult(_dummy(95.0), &"physical", &"weapon"), 1.24, 0.0001, "above 90%")
	check_near(b.damage_mult(_dummy(30.0), &"physical", &"weapon"), 1.12, 0.0001, "below 35%")
	check_near(b.damage_mult(_dummy(35.0), &"physical", &"weapon"), 1.04, 0.0001, "exactly 35%: not below")
	check_near(b.damage_mult(_dummy(60.0, true), &"physical", &"weapon"), 1.07, 0.0001, "elite")
	var stunned := _dummy(60.0)
	stunned.stun_left = 1.0
	check_near(b.damage_mult(stunned, &"physical", &"weapon"), 1.14, 0.0001, "stunned")
	var slowed := _dummy(60.0)
	slowed.apply_slow(30.0, 2.0)
	check_near(b.damage_mult(slowed, &"physical", &"weapon"), 1.11, 0.0001, "slowed")
	var feared := _dummy(60.0)
	feared.fear_left = 1.0
	check_near(b.damage_mult(feared, &"physical", &"weapon"), 1.13, 0.0001, "feared")
	check_near(b.damage_mult(null, &"physical", &"proc"), 1.34, 0.0001, "self above 99% (full HP), proc")
	p.hp = p.max_hp() * 0.4
	check_near(b.damage_mult(null, &"physical", &"weapon"), 1.10, 0.0001, "self below 50%")
	check_near(b.damage_mult(null, &"physical", &"proc"), 1.10, 0.0001, "no longer above 99%")
	p.hp = p.max_hp()
	check_near(p.outgoing_damage_mult(mid, &"fire", &"weapon"), 1.08, 0.0001, "Player.outgoing_damage_mult multiplies it in")
	_put(p, [])
	check_eq(b.damage_mult(stunned, &"fire", &"dot"), 1.0, "removed")


func test_damage_taken_entries_and_floor() -> void:
	var p := _warrior()
	_put(p, [{"kind": "damage_taken", "pct": -3.0, "rank": 3},
		{"kind": "damage_taken", "pct": -10.0, "kind_filter": "projectile", "rank": 1}])
	check_near(p.bonuses.damage_taken_mult(CombatMath.KIND_MELEE, null), 0.91, 0.0001, "unfiltered x rank")
	check_near(p.bonuses.damage_taken_mult(CombatMath.KIND_PROJECTILE, null), 0.81, 0.0001, "projectile filter adds")
	check_near(p.bonuses.damage_taken_mult(CombatMath.KIND_AOE, null), 0.91, 0.0001, "not aoe")
	# Player.take_damage applies it.
	p.stats.set_source(&"test", {Stats.STAMINA: 200.0})
	p.hp = p.max_hp()
	var before := p.hp
	p.take_damage(10.0, CombatMath.KIND_PROJECTILE)
	var with_bonus := before - p.hp
	_put(p, [])
	p.invulnerable_left = 0.0
	before = p.hp
	p.take_damage(10.0, CombatMath.KIND_PROJECTILE)
	var without := before - p.hp
	check_near(with_bonus, without * 0.81, 0.0001, "19% less damage taken")
	_put(p, [{"kind": "damage_taken", "pct": -50.0, "rank": 3}])
	check_near(p.bonuses.damage_taken_mult(CombatMath.KIND_MELEE, null), PlayerBonuses.MIN_DAMAGE_TAKEN_MULT, 0.0001, "floor 0.1")


# --- resource / proc hand-offs -----------------------------------------------------------------

func test_resource_entries_reach_set_bonus_rank_resolved() -> void:
	var p := _warrior()
	var rage := p.abilities.get_resource(&"rage")
	_put(p, [{"kind": "resource", "resource": "rage", "start_value_add": 5.0, "rank": 3},
		{"kind": "resource", "resource": "primary", "regen_per_second_add": 1.0, "decay_per_second_add": -0.5, "rank": 2},
		{"kind": "resource", "resource": "rage", "start_value_add": 2.0, "rank": 1}])
	check_eq(rage.bonus, {"start_value_add": 17.0, "regen_per_second_add": 2.0, "decay_per_second_add": -1.0}, "summed, x rank, primary = Rage")
	_put(p, [])
	check_eq(rage.bonus, {}, "cleared")
	var r := Fakes.spawn_player(world, 1, &"rogue", Vector3(6, 0, 0))
	_put(r, [{"kind": "resource", "resource": "combo_points", "gain_on_crit_add": 1.0, "rank": 1}])
	check_eq(r.abilities.get_resource(&"combo_points").bonus, {"gain_on_crit_add": 1.0}, "the named resource")
	check_eq(r.abilities.get_resource(&"energy").bonus, {}, "not the other one")


func test_proc_entries_reach_the_proc_system_rank_resolved() -> void:
	var p := _warrior()
	var procs := CountingProcs.new()
	procs.player = p
	nodes.append(procs)
	p.procs = procs
	var a := {"kind": "proc", "scale": ["chance", "stats"], "proc": {"trigger": "on_hit", "chance": 3.0, "effect": "buff",
		"stats": {"crit": 2.0}, "duration": 4.0}, "rank": 3, "id": "t_a", "label": "Talent A"}
	var b := {"kind": "proc", "proc": {"trigger": "on_cast", "ability": "whirlwind", "effect": "buff",
		"stats": {"extra_attack": 25.0}, "duration": 5.0, "label": ""}, "rank": 2, "id": "t_b", "label": "B"}
	var gated := {"kind": "proc", "proc": {"trigger": "on_hit", "chance": 5.0, "effect": "bolt", "damage": 2.0},
		"requires": {"weapon": "shield"}, "rank": 1, "id": "t_c", "label": "C"}
	_put(p, [a, b, gated])
	var defs: Array = procs.last_defs.get(PlayerBonuses.SOURCE_TALENTS, [])
	check_eq(defs.size(), 2, "the shield-gated proc is not handed off")
	check_eq(defs[0]["chance"], 9.0, "scaled key")
	check_eq(defs[0]["stats"]["crit"], 6.0, "scaled stats")
	check_eq(defs[0]["duration"], 4.0, "unlisted key unscaled")
	check(defs[0]["label"] == "Talent A" and defs[0]["id"] == "t_a", "label / id from the entry")
	check(defs[1]["label"] == "" and defs[1]["stats"]["extra_attack"] == 25.0, "an explicit empty label stays; no scale list = unscaled")
	check_eq(procs.refreshes, 1, "procs rebuilt once")
	_put(p, [a, b, gated, {"kind": "stats", "stats": {"crit": 1.0}, "rank": 1}])
	check_eq(procs.refreshes, 1, "unchanged procs: no refresh")
	check_eq(procs.handed.size(), 1, "and no hand-off")
	_put(p, [{"kind": "stats", "stats": {"crit": 1.0}, "rank": 1}])
	check(procs.last_defs[PlayerBonuses.SOURCE_TALENTS].is_empty(), "removed procs are handed off empty")
	check_eq(procs.refreshes, 2, "and rebuilt")


# --- scripts -----------------------------------------------------------------------------------

func test_script_lifecycle_and_diffing() -> void:
	var p := _warrior()
	var entry := {"kind": "script", "script": Probe.PATH, "params": {"mult": 1.5, "k": 2}, "rank": 2, "id": "t_s", "label": "S"}
	_put(p, [entry])
	check_eq(Probe.created, 1, "set up once")
	var s := p.bonuses.script_for(&"t_s")
	check(s != null and s.player == p, "instance for the hero")
	check_eq(s.rank, 2, "rank")
	check_eq(s.params, {"mult": 1.5, "k": 2}, "raw params (not rank-scaled)")
	check_eq(p.bonuses.scripts(), [s] as Array[TalentEffect], "listed")
	_put(p, [entry, {"kind": "stats", "stats": {"crit": 1.0}, "rank": 1, "id": "t_x"}])
	check(p.bonuses.script_for(&"t_s") == s and Probe.created == 1 and Probe.torn_down == 0, "unchanged entry keeps its instance")
	var next := entry.duplicate(true)
	next["rank"] = 3
	_put(p, [next])
	var s2 := p.bonuses.script_for(&"t_s")
	check(s2 != s and s2.rank == 3, "a new rank is a new instance")
	check((s as Probe).down and Probe.torn_down == 1, "the old one was torn down")
	var other := next.duplicate(true)
	other["params"] = {"mult": 2.0}
	_put(p, [other])
	check(p.bonuses.script_for(&"t_s") != s2 and (s2 as Probe).down, "changed params: replaced")
	_put(p, [])
	check(p.bonuses.scripts().is_empty() and Probe.torn_down == 3, "removed: torn down")


func test_scripts_run_talents_first_and_respect_requires() -> void:
	var p := _warrior()
	_put(p, [{"kind": "script", "script": Probe.PATH, "rank": 1, "id": "set_x:2", "label": "Set"}], PlayerBonuses.SOURCE_SETS)
	_put(p, [{"kind": "script", "script": Probe.PATH, "rank": 1, "id": "t_s", "label": "S"},
		{"kind": "script", "script": Probe.PATH, "rank": 1, "id": "t_g", "requires": {"weapon": "two_handed"}}])
	var list := p.bonuses.scripts()
	check_eq(list.size(), 2, "the two-hander script waits")
	check(list[0].source_id == &"t_s" and list[1].source_id == &"set_x:2", "talents before set bonuses")
	var kept := list[0]
	p.equip_weapons(Db.get_weapon(&"two_hand_axe"), null)
	_put(p, [{"kind": "script", "script": Probe.PATH, "rank": 1, "id": "set_x:2", "label": "Set"}], PlayerBonuses.SOURCE_SETS)
	check(p.bonuses.script_for(&"t_g") != null, "a two-hander: set up")
	check(p.bonuses.script_for(&"t_s") == kept and Probe.torn_down == 0, "the others kept their instances")


func test_script_hooks_are_forwarded() -> void:
	var p := _warrior()
	_put(p, [{"kind": "script", "script": Probe.PATH, "params": {"mult": 1.5, "taken_mult": 0.5, "force_crit": true}, "rank": 1, "id": "t_s"},
		{"kind": "damage", "pct": 10.0, "rank": 1}])
	var s := p.bonuses.script_for(&"t_s") as Probe
	check_near(p.bonuses.damage_mult(null, &"physical", &"weapon"), 1.65, 0.0001, "entries x scripts")
	check_near(p.bonuses.damage_taken_mult(CombatMath.KIND_MELEE, null), 0.5, 0.0001, "script damage taken")
	check(p.bonuses.crit_forced(null), "script forces crits (null target)")
	var e := Fakes.spawn_enemy(world, Vector3(1.2, 0, 0))
	p.begin_wave()
	p.bonuses.on_cast(0, Db.get_ability(&"whirlwind"))
	p.bonuses.on_avoided(&"parry", e)
	p.notify_kill(e)
	p.stats.set_source(&"test", {Stats.STAMINA: 100.0})
	p.hp = p.max_hp()
	p.take_damage(2.0, CombatMath.KIND_PROJECTILE)
	p._physics_process(0.5)
	p.end_wave()
	for hook in ["begin_wave", "on_cast", "on_avoided:parry", "on_kill", "on_damage_taken", "end_wave"]:
		check(hook in s.calls, "%s forwarded (%s)" % [hook, s.calls])
	check_near(s.ticked, 0.5, 0.0001, "tick forwarded")
	p.bonuses.teardown()
	check(s.down and p.bonuses.scripts().is_empty(), "teardown tears every script down")
	_put(p, [{"kind": "script", "script": Probe.PATH, "rank": 1, "id": "t_s"}])
	check(p.bonuses.script_for(&"t_s") != null and p.bonuses.script_for(&"t_s") != s, "a later rebuild sets them up again")


func test_freeing_the_hero_tears_scripts_down() -> void:
	var p := _warrior()
	_put(p, [{"kind": "script", "script": Probe.PATH, "rank": 1, "id": "t_s"}])
	EFakes.free_world(tree, world)
	world = null
	check_eq(Probe.torn_down, 1, "Player._exit_tree -> bonuses.teardown")


func test_on_hit_reaches_scripts_with_first_once_per_attack() -> void:
	var p := _warrior()
	p.damage_mults[&"test"] = 2.0
	_put(p, [{"kind": "script", "script": Probe.PATH, "rank": 1, "id": "t_s"}])
	var s := p.bonuses.script_for(&"t_s") as Probe
	var a := Fakes.spawn_enemy(world, Vector3(1.2, 0, 0))
	var b := Fakes.spawn_enemy(world, Vector3(1.2, 0, 0.5))
	var c := Fakes.spawn_enemy(world, Vector3(1.2, 0, -0.5))
	EnemyGrid.mark_dirty()
	p.weapons[0].attack(a)
	check_eq(s.hits.size(), 3, "every enemy of the arc")
	var firsts := 0
	for h in s.hits:
		if h[3]:
			firsts += 1
		var e := h[0] as Fakes.FakeEnemy
		check_near(float(h[1]), e.fake_damage_log[0] / 2.0, 0.0001, "the base amount")
	check_eq(firsts, 1, "first once per attack")
	check(b.fake_hits() == 1 and c.fake_hits() == 1, "the arc hit all three")


# --- requires ----------------------------------------------------------------------------------

func test_weapon_requirements() -> void:
	var p := _warrior()
	var w := func(id: StringName) -> WeaponData: return Db.get_weapon(id)
	var cases: Array[Array] = [
		# main, off, requirements that hold
		[&"two_hand_axe", null, [&"two_handed", &"melee"]],
		[&"sword", null, [&"one_handed", &"melee"]],
		[&"sword", &"shield", [&"one_handed", &"melee", &"shield"]],
		[&"dagger", &"dagger", [&"one_handed", &"melee", &"dual_wield"]],
		[&"bow", null, [&"ranged", &"two_handed"]],
		[&"wand", null, [&"magic", &"one_handed"]],
		[&"staff", null, [&"magic", &"two_handed"]],
	]
	for c in cases:
		var off: WeaponData = w.call(c[1]) if c[1] != null else null
		p.equip_weapons(w.call(c[0]), off)
		for req in BonusVocabulary.WEAPON_REQUIREMENTS:
			var expected: bool = req in c[2]
			check_eq(PlayerBonuses.weapon_requirement_met(p, req), expected, "%s + %s: %s" % [c[0], c[1], req])
	check(PlayerBonuses.requirement_met(p, null) and PlayerBonuses.requirement_met(p, {}), "no condition")
	check(not PlayerBonuses.requirement_met(p, {"weapon": "bogus"}), "unknown weapon requirement")
	check(not PlayerBonuses.requirement_met(p, {"mood": "angry"}), "unknown key")
	check(not PlayerBonuses.requirement_met(null, {"weapon": "melee"}), "no hero")


func test_requires_weapon_follows_equipment() -> void:
	var p := _warrior()
	_put(p, [{"kind": "damage", "pct": 5.0, "requires": {"weapon": "two_handed"}, "rank": 2},
		{"kind": "stats", "stats": {"block_chance": 20.0}, "requires": {"weapon": "shield"}, "rank": 1}])
	check_eq(p.bonuses.damage_mult(null, &"physical", &"weapon"), 1.0, "a sword: no two-hander bonus")
	check_eq(p.stats.get_raw(Stats.BLOCK_CHANCE), 0.0, "no shield: no block")
	var sword := p.equipment.get_item(Items.EquipSlot.MAIN_HAND)
	_wear(p, _item(&"two_hand_axe"))
	check_near(p.bonuses.damage_mult(null, &"physical", &"weapon"), 1.10, 0.0001, "two-hander equipped: +10%")
	check(p.equipment.equip(sword), "back to the sword")
	_wear(p, _item(&"shield"))
	check_eq(p.bonuses.damage_mult(null, &"physical", &"weapon"), 1.0, "bonus gone")
	check_eq(p.stats.get_raw(Stats.BLOCK_CHANCE), 20.0, "shield: +20 block")
	check_near(p.block_chance(), p.off_hand.block_chance + 20.0, 0.0001, "Player.block_chance adds it")


func test_any_source_rebuilds_every_source() -> void:
	var p := _warrior()
	_put(p, [{"kind": "stats", "stats": {"crit": 4.0}, "requires": {"weapon": "two_handed"}, "rank": 1}])
	var crit := p.stats.get_raw(Stats.CRIT)
	p.equip_weapons(Db.get_weapon(&"two_hand_axe"), null)
	check_eq(p.stats.get_raw(Stats.CRIT), crit, "nothing re-evaluated yet")
	_put(p, [], PlayerBonuses.SOURCE_SETS)
	check_eq(p.stats.get_raw(Stats.CRIT), crit + 4.0, "a set-bonus update re-evaluates the talent conditions")


func test_requires_knows_follows_learned_abilities() -> void:
	var p := _warrior()
	var rebuilds := [0]
	p.bonuses.changed.connect(func() -> void: rebuilds[0] += 1)
	p.abilities.learn(Db.get_ability(&"heroic_leap"))
	check_eq(rebuilds[0], 0, "no knows condition: learning does not rebuild")
	_put(p, [{"kind": "stats", "stats": {"crit": 3.0}, "requires": {"knows": "execute"}, "rank": 1}])
	rebuilds[0] = 0
	var crit := p.stats.get_raw(Stats.CRIT)
	p.abilities.learn(Db.get_ability(&"bladestorm"))
	check_eq(rebuilds[0], 0, "an unrelated ability: no rebuild")
	p.abilities.learn(Db.get_ability(&"execute"))
	check_eq(rebuilds[0], 1, "learning Execute rebuilds once")
	check_eq(p.stats.get_raw(Stats.CRIT), crit + 3.0, "condition met")
	p.abilities.forget(p.abilities.slot_of(&"execute"))
	check_eq(p.stats.get_raw(Stats.CRIT), crit, "forgotten: gone")


# --- general -----------------------------------------------------------------------------------

func test_changed_once_per_set_effects_and_neutral_without_entries() -> void:
	var p := _warrior()
	var b := p.bonuses
	check_eq(b.damage_mult(null, &"fire", &"dot"), 1.0, "neutral")
	check_eq(b.damage_taken_mult(CombatMath.KIND_AOE, null), 1.0, "neutral")
	check(not b.crit_forced(null) and b.scripts().is_empty(), "neutral")
	var n := [0]
	b.changed.connect(func() -> void: n[0] += 1)
	_put(p, [{"kind": "stats", "stats": {"crit": 1.0}, "rank": 1}, {"kind": "damage", "pct": 1.0, "rank": 1},
		{"kind": "resource", "resource": "rage", "start_value_add": 1.0, "rank": 1}])
	check_eq(n[0], 1, "one changed per set_effects")
	check_eq(b.effects_of(PlayerBonuses.SOURCE_TALENTS).size(), 3, "entries kept as given")


func test_engine_draws_no_random_numbers() -> void:
	var p := _warrior()
	var e := _dummy(50.0)
	var state := RunState.rng.state
	_put(p, [{"kind": "stats", "stats": {"crit": 1.0}, "rank": 2},
		{"kind": "damage", "pct": 3.0, "target": "below_pct", "target_pct": 60.0, "rank": 1},
		{"kind": "damage_taken", "pct": -2.0, "rank": 1},
		{"kind": "ability", "match": {"id": "charge"}, "mods": {"stun_add": 0.3}, "rank": 1},
		{"kind": "script", "script": Probe.PATH, "rank": 1, "id": "t_s"}])
	for i in 50:
		p.bonuses.damage_mult(e, &"physical", &"weapon")
		p.bonuses.damage_taken_mult(CombatMath.KIND_MELEE, e)
		p.bonuses.crit_forced(e)
		p.bonuses.ability_mods_for(&"charge")
	check_eq(RunState.rng.state, state, "no draws")
