extends TestCase
## ProcSystem M5 (T-CORE-B): talent / set procs (set_extra_procs), the new triggers (on_crit,
## on_cast, wave_start, on_dodge / on_parry / on_block, periodic chance), the "every" and
## "hit_pct" keys (the one derived-damage rule), the cooldown / forced_crit / resource-by-id
## blocks, heal / shield max_hp_pct on lowest_ally, "label": "" and the Arms proc talents on
## inline fixtures identical to data/talents/warrior/arms.tres.

const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0

## Arms talents as authored (rank-1 numbers; tests resolve them with BonusVocabulary.resolve).
const DEEP_WOUNDS := {"kind": "proc", "scale": ["hit_pct"], "proc": {
		"trigger": "on_crit", "effect": "dot", "hit_pct": 10.0, "duration": 3.0, "school": "physical"}}
const SWEEPING_BLOWS := {"kind": "proc", "proc": {
		"trigger": "on_cast", "ability": "whirlwind", "effect": "buff", "stats": {"extra_attack": 25.0},
		"duration": 5.0, "label": ""}}
const SUDDEN_DEATH := {"kind": "proc", "scale": ["chance"], "proc": {
		"trigger": "on_hit", "chance": 3.0, "effect": "cooldown", "ability": "execute", "reset": true}}

var world: Node3D


func before_each() -> void:
	PlayerManager.clear()
	RunState.start_run(1, 99)
	Enemy.invalidate_player_cache()
	world = Fakes.make_world(tree)


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	Enemy.invalidate_player_cache()
	EnemyGrid.mark_dirty()


# --- Helpers ------------------------------------------------------------------------------

func _hero(class_id: StringName = &"warrior", index: int = 0, pos: Vector3 = Vector3.ZERO) -> Player:
	var p := Fakes.spawn_player(world, index, class_id, pos)
	p.stats.set_source(&"tough", {Stats.STAMINA: 500.0})
	p.hp = p.max_hp()
	Enemy.invalidate_player_cache()
	return p


func _fake(pos: Vector3) -> Fakes.FakeEnemy:
	var e := Fakes.spawn_enemy(world, pos)
	EnemyGrid.mark_dirty()
	return e


## A talent's proc entry the way PlayerBonuses hands it over (rank-resolved, id, label).
static func _entry(proc: Dictionary, id: String = "test_talent", label: String = "Test Talent") -> Dictionary:
	return {"kind": "proc", "proc": proc, "rank": 1, "id": id, "label": label}


## [param entry] (as authored) at [param rank], with the source's id / label added.
static func _talent(entry: Dictionary, rank: int, id: String, label: String) -> Dictionary:
	var out := BonusVocabulary.resolve(entry, rank)
	out["rank"] = rank
	out["id"] = id
	out["label"] = label
	return out


func _give(p: Player, entries: Array[Dictionary], source: StringName = &"talents") -> void:
	p.procs.set_extra_procs(source, entries)


func _texts(text: String) -> int:
	var n := 0
	for node in world.find_children("*", "Label3D", true, false):
		if (node as Label3D).text == text:
			n += 1
	return n


static func _sum(values: Array[float]) -> float:
	var total := 0.0
	for v in values:
		total += v
	return total


# --- set_extra_procs ------------------------------------------------------------------------

func test_extra_procs_are_built_after_the_items_and_follow_their_source() -> void:
	var p := _hero()
	var ring := ItemInstance.new()
	ring.source_id = &"test_item_bolt"
	ring.display_name = "Test Item Bolt"
	ring.slot_type = Items.SlotType.TRINKET
	ring.rarity = Items.Rarity.LEGENDARY
	ring.unique = true
	ring.unique_effect = &"bolt"
	ring.unique_params = {"trigger": "on_hit", "chance": 100.0, "damage": 1.0}
	p.equipment.equip(ring)
	_give(p, [_entry({"trigger": "on_kill", "effect": "bolt", "damage": 3.0}, "talent_a", "Talent A")] as Array[Dictionary])
	_give(p, [{"trigger": "on_hit", "effect": "gold", "amount": 2.0, "chance": 50.0, "label": "Bare", "id": "set_x:2"}] as Array[Dictionary], &"set_bonus")
	check_eq(p.procs.procs.size(), 3, "the item + one per source")
	check_eq(p.procs.procs[0].id, &"test_item_bolt", "items first")
	var a: ProcSystem.Proc = p.procs.procs[1]
	check_eq(a.id, &"talent_a", "entry shape: the entry's id")
	check_eq(a.label, "Talent A", "the entry's label is the default")
	check(a.extra, "an extra proc")
	check_eq(a.trigger, ProcSystem.TRIGGER_ON_KILL, "trigger")
	check_eq(a.num("damage"), 3.0, "numbers as written (no enchant multiplier)")
	var b: ProcSystem.Proc = p.procs.procs[2]
	check_eq(b.id, &"set_x:2", "bare shape: its own id")
	check_eq(b.label, "Bare", "and label")
	check_eq(b.chance, 50.0, "chance")
	# Unchanged defs: no rebuild (running state is kept).
	var uid := a.uid
	_give(p, [_entry({"trigger": "on_kill", "effect": "bolt", "damage": 3.0}, "talent_a", "Talent A")] as Array[Dictionary])
	check_eq(p.procs.procs[1].uid, uid, "same defs: the list is not rebuilt")
	# An equipment change rebuilds the items and keeps the extras.
	p.equipment.unequip(Items.EquipSlot.TRINKET_1)
	check_eq(p.procs.procs.size(), 2, "item gone, both extras stay")
	check_eq(p.procs.procs[0].id, &"talent_a", "extras in source order")
	# New defs replace the source's; an empty list removes it.
	_give(p, [_entry({"trigger": "on_kill", "effect": "bolt", "damage": 6.0}, "talent_a", "Talent A")] as Array[Dictionary])
	check_eq(p.procs.procs[0].num("damage"), 6.0, "replaced")
	_give(p, [] as Array[Dictionary])
	check_eq(p.procs.procs.size(), 1, "talents removed")
	check(p.procs.extra_defs(&"talents").is_empty(), "nothing stored")
	check_eq(p.procs.extra_defs(&"set_bonus").size(), 1, "the set source stays")
	var unnamed := ProcSystem.proc_from_def({"trigger": "on_kill", "effect": "bolt"}, &"talents", 4)
	check_eq(unnamed.id, &"talents:4", "no id: source:index")


# --- Triggers -------------------------------------------------------------------------------

func test_on_crit_fires_once_per_critical_attack() -> void:
	var p := _hero()
	_give(p, [_entry({"trigger": "on_crit", "effect": "bolt", "damage": 1.0}, "crit_bolt")] as Array[Dictionary])
	var e := _fake(Vector3(1.5, 0, 0))
	p.procs.on_hit(e, 10.0, p.main_hand, false)
	check_eq(p.procs.fire_count(&"crit_bolt"), 0, "no crit: nothing")
	p.procs.on_hit(e, 10.0, p.main_hand, true)
	check_eq(p.procs.fire_count(&"crit_bolt"), 1, "a crit fires it")
	# A swing that crits on all three enemies of the arc is one attack.
	var side_a := _fake(Vector3(1.2, 0, -0.6))
	var side_b := _fake(Vector3(1.2, 0, 0.6))
	p.forced_crits = 3
	var hits: Array[Node3D] = []
	p.hit_dealt.connect(func(_d: float, t: Node3D) -> void: hits.append(t))
	p.weapons[0].attack(e)
	check_eq(hits.size(), 3, "three critical hits")
	check_eq(p.forced_crits, 0, "all forced")
	check_eq(p.procs.fire_count(&"crit_bolt"), 2, "one on_crit for the whole swing")
	check(side_a.fake_hits() == 1 and side_b.fake_hits() == 1, "the bolt went to the attacked enemy")


func test_on_cast_filters_by_ability_or_match() -> void:
	var p := _hero()
	var e := _fake(Vector3(2, 0, 0))
	_give(p, [
		_entry({"trigger": "on_cast", "ability": "whirlwind", "effect": "bolt", "damage": 1.0}, "on_ww"),
		_entry({"trigger": "on_cast", "match": {"tag": "movement"}, "effect": "bolt", "damage": 1.0}, "on_move"),
	] as Array[Dictionary])
	var whirlwind := Db.get_ability(&"whirlwind")
	var charge := Db.get_ability(&"charge")
	p.abilities.ability_cast.emit(0, whirlwind)  # Player._on_ability_cast -> procs.on_ability_cast
	check_eq(p.procs.fire_count(&"on_ww"), 1, "Whirlwind cast")
	check_eq(p.procs.fire_count(&"on_move"), 0, "Whirlwind is no movement ability")
	p.abilities.ability_cast.emit(1, charge)
	check_eq(p.procs.fire_count(&"on_ww"), 1, "not on Charge")
	check_eq(p.procs.fire_count(&"on_move"), 1, "Charge is tagged movement")
	check_eq(e.fake_hits(), 2, "no hit target: the nearest enemy")
	p.downed = true
	p.procs.on_ability_cast(whirlwind)
	check_eq(p.procs.fire_count(&"on_ww"), 1, "nothing while downed")


func test_wave_start_procs_fire_after_the_resource_reset() -> void:
	var p := _hero()
	_give(p, [_entry({"trigger": "wave_start", "effect": "resource", "resource": "rage", "value": 20.0}, "battle_ready")] as Array[Dictionary])
	var rage := p.abilities.get_resource(&"rage")
	rage.set_value(70.0)
	p.begin_wave()
	check_eq(rage.value, 20.0, "reset to 0, then +20 – not wiped by the reset")
	p.begin_wave()
	check_eq(rage.value, 20.0, "every wave")
	check_eq(p.procs.fire_count(&"battle_ready"), 2, "once per wave start")
	p.procs.on_hit(_fake(Vector3(2, 0, 0)), 5.0, p.main_hand, true)
	check_eq(p.procs.fire_count(&"battle_ready"), 2, "no other event fires it")


func test_avoided_hits_fire_their_own_triggers_on_the_attacker() -> void:
	var p := _hero()
	_give(p, [
		_entry({"trigger": "on_dodge", "effect": "bolt", "damage": 1.0}, "on_dodge"),
		_entry({"trigger": "on_parry", "effect": "bolt", "damage": 1.0}, "on_parry"),
		_entry({"trigger": "on_block", "effect": "bolt", "damage": 1.0}, "on_block"),
	] as Array[Dictionary])
	var attacker := _fake(Vector3(6, 0, 0))
	var nearer := _fake(Vector3(1, 0, 0))
	p.procs.on_avoided(&"dodge", attacker)
	check_eq([p.procs.fire_count(&"on_dodge"), p.procs.fire_count(&"on_parry"), p.procs.fire_count(&"on_block")],
			[1, 0, 0], "a dodge fires on_dodge only")
	check_eq(attacker.fake_hits(), 1, "the attacker is the target (not the nearest enemy)")
	check_eq(nearer.fake_hits(), 0, "the nearer enemy is left alone")
	p.procs.on_avoided(&"parry", attacker)
	p.procs.on_avoided(&"block", attacker)
	p.procs.on_avoided(&"nonsense", attacker)
	check_eq([p.procs.fire_count(&"on_dodge"), p.procs.fire_count(&"on_parry"), p.procs.fire_count(&"on_block")],
			[1, 1, 1], "parry / block their own")
	# Through Player.take_damage: every dodge reports.
	p.stats.set_source(&"test", {Stats.DODGE: 60.0})
	var dodged := 0
	for i in 40:
		p.invulnerable_left = 0.0
		var before := p.hp
		p.take_damage(1.0, CombatMath.KIND_PROJECTILE, attacker)
		if p.hp == before:
			dodged += 1
	check(dodged > 0, "some dodges")
	check_eq(p.procs.fire_count(&"on_dodge"), 1 + dodged, "one on_dodge per dodge")


func test_extra_attack_on_an_avoided_hit_strikes_the_attacker_in_reach() -> void:
	var p := _hero()
	_give(p, [_entry({"trigger": "on_block", "effect": "extra_attack", "count": 1, "label": ""}, "revenge")] as Array[Dictionary])
	var attacker := _fake(Vector3(1.5, 0, 0))
	p.procs.on_avoided(&"block", attacker)
	check_eq(attacker.fake_hits(), 1, "struck back with the weapon")
	var far := _fake(Vector3(0, 0, 20))
	p.procs.on_avoided(&"block", far)
	check_eq(far.fake_hits(), 0, "out of reach: simply missed")


func test_periodic_rolls_its_chance_once_per_interval() -> void:
	var p := _hero()
	_give(p, [_entry({"trigger": "periodic", "interval": 1.0, "chance": 25.0, "effect": "resource",
			"resource": "rage", "value": 1.0, "label": ""}, "tick")] as Array[Dictionary])
	p.procs.begin_wave()
	for i in 800:
		p.procs._physics_process(0.5)
	var n := p.procs.fire_count(&"tick")
	check(n > 65 and n < 135, "~25%% of 400 intervals (%d)" % n)


# --- "every" ----------------------------------------------------------------------------------

func test_every_replaces_the_roll_and_resets_at_wave_start() -> void:
	var p := _hero()
	_give(p, [_entry({"trigger": "on_hit", "every": 3, "chance": 0.0, "effect": "bolt", "damage": 1.0}, "third")] as Array[Dictionary])
	var e := _fake(Vector3(2, 0, 0))
	var state := RunState.rng.state
	for i in 7:
		p.procs.on_hit(e, 5.0, p.main_hand, false)
	check_eq(p.procs.fire_count(&"third"), 2, "hits 3 and 6 (chance 0 is not rolled)")
	check_eq(RunState.rng.state, state, "no draws")
	p.procs.begin_wave()
	p.procs.on_hit(e, 5.0, p.main_hand, false)
	p.procs.on_hit(e, 5.0, p.main_hand, false)
	check_eq(p.procs.fire_count(&"third"), 2, "the 7th hit's count was dropped at the wave start")
	p.procs.on_hit(e, 5.0, p.main_hand, false)
	check_eq(p.procs.fire_count(&"third"), 3, "a fresh third hit")


func test_every_waits_out_the_internal_cooldown_and_counts_only_matches() -> void:
	var p := _hero()
	_give(p, [
		_entry({"trigger": "on_hit", "every": 2, "icd": 5.0, "effect": "bolt", "damage": 1.0}, "icd2"),
		_entry({"trigger": "on_cast", "ability": "whirlwind", "every": 2, "effect": "bolt", "damage": 1.0}, "cast2"),
	] as Array[Dictionary])
	var e := _fake(Vector3(2, 0, 0))
	for i in 4:
		p.procs.on_hit(e, 5.0, p.main_hand, false)
	check_eq(p.procs.fire_count(&"icd2"), 1, "hit 2 fired, hit 4 was on cooldown")
	p.procs._physics_process(5.1)
	p.procs.on_hit(e, 5.0, p.main_hand, false)
	check_eq(p.procs.fire_count(&"icd2"), 2, "the held count fires on the next hit off cooldown")
	var whirlwind := Db.get_ability(&"whirlwind")
	var charge := Db.get_ability(&"charge")
	p.procs.on_ability_cast(whirlwind)
	for i in 3:
		p.procs.on_ability_cast(charge)
	check_eq(p.procs.fire_count(&"cast2"), 0, "Charge casts do not count")
	p.procs.on_ability_cast(whirlwind)
	check_eq(p.procs.fire_count(&"cast2"), 1, "the 2nd Whirlwind")


# --- "hit_pct": the one derived-damage rule -----------------------------------------------------

func test_hit_pct_starts_from_the_base_amount_and_multiplies_once() -> void:
	var p := _hero()
	_give(p, [_entry({"trigger": "on_hit", "effect": "bolt", "hit_pct": 50.0, "label": ""}, "half")] as Array[Dictionary])
	p.damage_mults[&"test"] = 2.0
	p.stats.set_source(&"test", {Stats.EXECUTIONER: 100.0})
	var e := _fake(Vector3(2, 0, 0))
	e.hp = 100.0  # 10% HP: Executioner would double a target-bonus hit
	# The weapon dealt 80 (base 20 x Executioner 2 x outgoing 2); procs derive from the base.
	p.on_hit_dealt(80.0, e, p.main_hand, false, false, true, 20.0)
	check_eq(e.fake_hits(), 1, "the bolt")
	check_near(e.fake_damage_log[0], 20.0 * 0.5 * 2.0, 0.0001, "50% of the base x the outgoing multiplier, once; no Executioner")
	# Without a base amount the dealt one is used (callers before M5).
	p.on_hit_dealt(30.0, e, p.main_hand, false)
	check_near(e.fake_damage_log[1], 30.0 * 0.5 * 2.0, 0.0001, "base = dealt when not given")


func test_hit_pct_on_area_and_chain_blocks_hits_each_enemy_for_it() -> void:
	var p := _hero()
	_give(p, [
		_entry({"trigger": "on_hit", "effect": "nova", "hit_pct": 100.0, "radius": 3.0, "at": "target", "label": ""}, "nova"),
		_entry({"trigger": "on_hit", "effect": "chain", "hit_pct": 10.0, "targets": 2, "label": ""}, "chain"),
	] as Array[Dictionary])
	var a := _fake(Vector3(2, 0, 0))
	var b := _fake(Vector3(3, 0, 0))
	p.procs.on_hit(a, 12.0, p.main_hand, false)
	check_eq(a.fake_damage_log.slice(0, 2), [12.0, 1.2] as Array[float], "a: the nova, then the chain")
	check_eq(b.fake_damage_log, [12.0, 1.2] as Array[float], "b: the nova and the chain's jump")


func test_hit_pct_dot_takes_the_total_and_skips_executioner() -> void:
	var p := _hero()
	_give(p, [_entry({"trigger": "on_crit", "effect": "dot", "hit_pct": 30.0, "duration": 3.0, "label": ""}, "bleed")] as Array[Dictionary])
	p.damage_mults[&"test"] = 1.5
	p.stats.set_source(&"test", {Stats.EXECUTIONER: 100.0, Stats.ATTACK_POWER: 50.0})
	var e := _fake(Vector3(2, 0, 0))
	e.hp = 100.0
	p.procs.on_hit(e, 40.0, p.main_hand, true)
	check_eq(p.procs.dot_stacks(e, &"bleed"), 1, "bleeding")
	Fakes.step(p.procs, 3.0)
	check_near(_sum(e.fake_damage_log), 40.0 * 0.3 * 1.5, 0.01,
			"30% of the hit over 3 s, x the outgoing multiplier once; no Attack Power, no Executioner")


func test_hit_pct_drain_heals_what_it_dealt() -> void:
	var p := _hero()
	_give(p, [_entry({"trigger": "on_crit", "effect": "drain", "hit_pct": 20.0, "school": "shadow", "label": ""}, "leech")] as Array[Dictionary])
	p.damage_mults[&"test"] = 2.0
	var e := _fake(Vector3(2, 0, 0))
	p.hp = 100.0
	p.procs.on_hit(e, 50.0, p.main_hand, true)
	check_near(e.fake_damage_log[0], 20.0, 0.0001, "20% of 50 x 2")
	check_near(p.hp, 120.0, 0.0001, "healed by the damage dealt")


# --- Blocks -------------------------------------------------------------------------------------

func test_cooldown_block_reduces_by_match_and_resets_by_id() -> void:
	var m := _hero(&"mage")
	var blink := Db.get_ability(&"blink")
	_give(m, [_entry({"trigger": "on_kill", "effect": "cooldown", "match": {"tag": "movement"}, "reduce": 2.0}, "flow")] as Array[Dictionary])
	m.abilities.spend_charge(blink)
	var full := m.abilities.cooldown_of(blink)
	var corpse := _fake(Vector3(3, 0, 0))
	m.procs.on_kill(corpse)
	check_near(m.abilities.cooldown_left(blink), full - 2.0, 0.0001, "Blink (movement) 2 s faster")
	check_eq(_texts("Test Talent"), 1, "label shown")
	var w := _hero(&"warrior", 1, Vector3(0, 0, 10))
	check(w.abilities.learn(Db.get_ability(&"execute")) >= 0, "learn Execute")
	var execute := Db.get_ability(&"execute")
	w.abilities.set_cooldown(execute, 8.0)
	_give(w, [_entry({"trigger": "on_kill", "effect": "cooldown", "ability": "execute", "reset": true}, "reset")] as Array[Dictionary])
	w.procs.on_kill(corpse)
	check_eq(w.abilities.cooldown_left(execute), 0.0, "Execute ready")
	check_near(w.abilities.cooldown_left(Db.get_ability(&"charge")), 0.0, 0.0001, "nothing else touched")


func test_forced_crit_block_banks_crits() -> void:
	var p := _hero()
	_give(p, [_entry({"trigger": "on_kill", "effect": "forced_crit", "count": 2}, "focus")] as Array[Dictionary])
	var e := _fake(Vector3(1.5, 0, 0))
	p.procs.on_kill(e)
	check_eq(p.forced_crits, 2, "two banked crits")
	p.weapons[0].attack(e)
	check(e.fake_crit_log[0], "the next hit crits")
	check_eq(p.forced_crits, 1, "one left")


func test_resource_by_id_is_scaled_for_bars_and_exact_for_pips() -> void:
	var p := _hero()
	p.stats.set_source(&"test", {Stats.RESOURCE_REGEN: 50.0})
	p.abilities._physics_process(DT)  # gain_mult from Resource Regen
	var rage := p.abilities.get_resource(&"rage")
	rage.set_value(0.0)
	_give(p, [
		_entry({"trigger": "on_kill", "effect": "resource", "resource": "rage", "value": 10.0}, "rage10"),
		_entry({"trigger": "on_kill", "effect": "resource", "resource": "primary", "value": 2.0}, "primary2"),
	] as Array[Dictionary])
	p.procs.on_kill(_fake(Vector3(3, 0, 0)))
	check_near(rage.value, (10.0 + 2.0) * 1.5, 0.0001, "Rage x Resource Regen; primary = Rage")
	var pal := _hero(&"paladin", 1, Vector3(0, 0, 10))
	pal.stats.set_source(&"test", {Stats.RESOURCE_REGEN: 100.0})
	pal.abilities._physics_process(DT)
	_give(pal, [_entry({"trigger": "on_kill", "effect": "resource", "resource": "holy_power", "value": 1.0}, "hp1")] as Array[Dictionary])
	pal.procs.on_kill(_fake(Vector3(0, 0, 12)))
	check_eq(pal.abilities.get_resource(&"holy_power").value, 1.0, "pips: exactly 1")


func test_heal_and_shield_max_hp_pct_go_by_the_receivers_max_hp() -> void:
	var p := _hero()
	var ally := Fakes.spawn_player(world, 1, &"mage", Vector3(3, 0, 0))
	Enemy.invalidate_player_cache()
	check(ally.max_hp() < p.max_hp(), "the ally has less Max HP")
	ally.hp = ally.max_hp() * 0.5
	_give(p, [
		_entry({"trigger": "on_kill", "effect": "heal", "max_hp_pct": 10.0, "target": "lowest_ally", "label": ""}, "mend"),
		_entry({"trigger": "on_kill", "effect": "shield", "max_hp_pct": 20.0, "target": "lowest_ally", "duration": 4.0, "label": ""}, "ward"),
	] as Array[Dictionary])
	var before := ally.hp
	p.procs.on_kill(_fake(Vector3(5, 0, 0)))
	check_near(ally.hp - before, ally.max_hp() * 0.1, 0.0001, "10% of the ally's Max HP")
	check_near(ally.procs.shield_hp, ally.max_hp() * 0.2, 0.0001, "20% of the ally's Max HP as a shield")
	check_eq(p.procs.shield_hp, 0.0, "not on the caster")
	# Everyone full: the caster is the lowest ally (ties / alone).
	ally.hp = ally.max_hp()
	ally.procs.clear_shields()
	p.procs._physics_process(1.0)
	p.procs.on_kill(_fake(Vector3(6, 0, 0)))
	check_near(p.procs.shield_hp, p.max_hp() * 0.2, 0.0001, "the caster's own Max HP")
	check_eq(ally.procs.shield_hp, 0.0, "the ally gets none")


func test_empty_label_silences_every_block() -> void:
	var p := _hero()
	var blocks: Array[Dictionary] = [
		{"effect": "buff", "stats": {"crit": 1.0}, "duration": 2.0},
		{"effect": "shield", "amount": 5.0},
		{"effect": "heal", "amount": 1.0},
		{"effect": "forced_crit", "count": 1},
		{"effect": "resource", "resource": "rage", "value": 1.0},
		{"effect": "cooldown", "ability": "charge", "reduce": 1.0},
	]
	var loud: Array[Dictionary] = []
	var quiet: Array[Dictionary] = []
	for i in blocks.size():
		var b := blocks[i].duplicate(true)
		b["trigger"] = "wave_start"
		loud.append(_entry(b, "loud%d" % i, "Loud"))
		var q := b.duplicate(true)
		q["label"] = ""
		quiet.append(_entry(q, "quiet%d" % i, "Quiet"))
	_give(p, loud)
	p.procs.after_wave_start()
	check_eq(_texts("Loud"), blocks.size(), "every block shows the talent's name by default")
	_give(p, quiet)
	p.procs.after_wave_start()
	check_eq(p.procs.fire_count(&"quiet0") + p.procs.fire_count(&"quiet5"), 2, "they fired")
	check_eq(_texts("Quiet"), 0, "\"label\": \"\" – no text from any block")


# --- Arms proc talents (inline fixtures = arms.tres) -----------------------------------------

func test_deep_wounds_bleeds_for_ten_percent_per_rank_of_the_crit() -> void:
	var p := _hero()
	_give(p, [_talent(DEEP_WOUNDS, 3, "warrior_arms_deep_wounds", "Deep Wounds")] as Array[Dictionary])
	var e := _fake(Vector3(1.5, 0, 0))
	p.forced_crits = 1
	p.weapons[0].attack(e)
	check(e.fake_crit_log[0], "a critical hit")
	var crit := e.fake_damage_log[0]
	check_eq(p.procs.dot_stacks(e, &"warrior_arms_deep_wounds"), 1, "bleeding")
	Fakes.step(p.procs, 3.0)
	check_near(_sum(e.fake_damage_log) - crit, crit * 0.3, 0.01, "30% of the crit over 3 s at rank 3")
	var plain := _fake(Vector3(-1.5, 0, 0))
	p.procs._physics_process(1.0)
	p.procs.on_hit(plain, 40.0, p.main_hand, false)
	check_eq(p.procs.dot_stacks(plain, &"warrior_arms_deep_wounds"), 0, "a normal hit does not bleed")


func test_sweeping_blows_after_whirlwind() -> void:
	var p := _hero()
	_give(p, [_talent(SWEEPING_BLOWS, 1, "warrior_arms_sweeping_blows", "Sweeping Blows")] as Array[Dictionary])
	p.abilities.ability_cast.emit(1, Db.get_ability(&"charge"))
	check_eq(p.stats.get_stat(Stats.EXTRA_ATTACK), 0.0, "not after Charge")
	p.abilities.ability_cast.emit(0, Db.get_ability(&"whirlwind"))
	check_eq(p.stats.get_stat(Stats.EXTRA_ATTACK), 25.0, "25% Extra Attack after Whirlwind")
	check_eq(_texts("Sweeping Blows"), 0, "silent")
	Fakes.step(p.procs, 5.1, 0.1)
	check_eq(p.stats.get_stat(Stats.EXTRA_ATTACK), 0.0, "for 5 sec")


func test_sudden_death_finishes_executes_cooldown() -> void:
	var p := _hero()
	check(p.abilities.learn(Db.get_ability(&"execute")) >= 0, "learn Execute")
	var execute := Db.get_ability(&"execute")
	_give(p, [_talent(SUDDEN_DEATH, 3, "warrior_arms_sudden_death", "Sudden Death")] as Array[Dictionary])
	var proc: ProcSystem.Proc = p.procs.procs[0]
	check_eq(proc.chance, 9.0, "3% per rank")
	var e := _fake(Vector3(30, 0, 0))
	var hits := 3000
	for i in hits:
		p.procs.on_hit(e, 5.0, p.main_hand, false)
	var n := p.procs.fire_count(&"warrior_arms_sudden_death")
	check(n > 210 and n < 330, "~9%% of %d hits (%d)" % [hits, n])
	p.abilities.set_cooldown(execute, 8.0)
	p.procs._run(proc, e, e.global_position, p.main_hand)
	check_eq(p.abilities.cooldown_left(execute), 0.0, "Execute's cooldown finished")
