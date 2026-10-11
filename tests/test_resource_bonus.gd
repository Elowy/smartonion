extends TestCase
## ClassResource talent / set bonuses (M5, T-CORE-B): ClassResource.bonus ("<field>_add") is
## read wherever the field is used – start value, maximum (bars), regen, decay, gains, gain per
## hits / kills – with the clamps, also on the private ResourceData copies of the Mage (Mana)
## and the Warlock (Soul Shards). Tactical Mastery's start Rage on an inline fixture identical
## to data/talents/warrior/arms.tres.

const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0

## Arms tier 1 "Tactical Mastery" resource half, as authored (rank 1 numbers).
const TACTICAL_MASTERY_RESOURCE := {"kind": "resource", "resource": "rage", "start_value_add": 5.0}

var world: Node3D


func before_each() -> void:
	PlayerManager.clear()
	RunState.start_run(1, 11)
	Enemy.invalidate_player_cache()
	world = Fakes.make_world(tree)


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	Enemy.invalidate_player_cache()


## The "<field>_add" keys of rank-resolved resource entries summed – the dictionary
## PlayerBonuses hands to ClassResource.set_bonus.
static func _bonus_of(entries: Array[Dictionary]) -> Dictionary:
	var out := {}
	for e in entries:
		for key: Variant in e:
			var k := String(key)
			if k.ends_with("_add"):
				out[k] = float(out.get(k, 0.0)) + float(e[key])
	return out


func _res(p: Player, id: StringName) -> ClassResource:
	return p.abilities.get_resource(id)


# --- Neutral ----------------------------------------------------------------------------------

func test_no_bonus_reads_the_data() -> void:
	for cid: StringName in [&"warrior", &"mage", &"paladin", &"rogue", &"warlock"]:
		for data in Db.get_class_data(cid).resources:
			var r := ClassResource.new(data)
			check_eq(r.max_value(), data.max_value, "%s max" % data.id)
			check_eq(r.start_value(), data.start_value, "%s start" % data.id)
			check_eq(r.regen_per_second(), data.regen_per_second, "%s regen" % data.id)
			check_eq(r.decay_per_second(), data.decay_per_second, "%s decay" % data.id)
			check_eq(r.gain_on_hit(), data.gain_on_hit, "%s gain on hit" % data.id)
			check_eq(r.gain_on_damage_taken(), data.gain_on_damage_taken, "%s gain when struck" % data.id)
			check_eq(r.gain_on_crit(), data.gain_on_crit, "%s gain on crit" % data.id)
			check_eq(r.gain_per_hits(), data.gain_per_hits, "%s per hits" % data.id)
			check_eq(r.gain_per_kills(), data.gain_per_kills, "%s per kills" % data.id)


# --- Start value / maximum ---------------------------------------------------------------------

func test_tactical_mastery_start_rage_survives_the_wave_start() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior")
	var rage := _res(p, &"rage")
	var resolved := BonusVocabulary.resolve(TACTICAL_MASTERY_RESOURCE, 3)
	rage.set_bonus(_bonus_of([resolved] as Array[Dictionary]))
	check_eq(rage.start_value(), 15.0, "5 Rage per rank, rank 3")
	rage.set_value(70.0)
	p.begin_wave()
	check_eq(rage.value, 15.0, "every wave starts with 15 Rage")
	rage.set_bonus({"start_value_add": 500.0})
	p.begin_wave()
	check_eq(rage.value, 100.0, "the start value stays within the maximum")
	rage.set_bonus({})
	p.begin_wave()
	check_eq(rage.value, 0.0, "talent removed: back to 0")


func test_max_value_add_on_bars_full_pools_and_fixed_pips() -> void:
	var p := Fakes.spawn_player(world, 0, &"rogue")
	var energy := _res(p, &"energy")
	energy.set_bonus({"max_value_add": 20.0})
	check_eq(energy.max_value(), 120.0, "bar maximum raised")
	p.begin_wave()
	check_eq(energy.value, 120.0, "a pool that starts full starts at the raised maximum")
	energy.set_bonus({"max_value_add": 20.0, "start_value_add": -30.0})
	p.begin_wave()
	check_eq(energy.value, 90.0, "start_value_add on a full pool: below the maximum")
	var seen: Array[float] = []
	energy.changed.connect(func(v: float, m: float) -> void: seen.append_array([v, m]))
	energy.set_bonus({"max_value_add": -50.0})
	check_eq(energy.value, 50.0, "a lower maximum clamps the value")
	check_eq(seen, [50.0, 50.0] as Array[float], "changed tells the HUD the new maximum")
	var combo := _res(p, &"combo_points")
	combo.set_bonus({"max_value_add": 2.0})
	check_eq(combo.max_value(), 5.0, "pips keep their maximum (fixed in M5)")
	combo.set_bonus({"start_value_add": 2.0})
	p.begin_wave()
	check_eq(combo.value, 2.0, "pips may start higher")


# --- Regen, decay, gains -----------------------------------------------------------------------

func test_regen_and_decay_bonuses_never_go_below_zero() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior")
	var rage := _res(p, &"rage")
	rage.set_value(50.0)
	rage.set_bonus({"regen_per_second_add": 2.0, "decay_per_second_add": -10.0})
	check_eq(rage.regen_per_second(), 2.0, "Rage gains a regen")
	check_eq(rage.decay_per_second(), 0.0, "decay clamped at 0")
	for i in 300:  # 5 s, long past the decay delay
		rage.tick(DT)
	check_near(rage.value, 60.0, 0.01, "+2 / s, no decay")
	rage.set_bonus({"decay_per_second_add": 3.0})
	rage.set_value(50.0)
	for i in 60:
		rage.tick(DT)
	check_near(rage.value, 44.0, 0.01, "decay 3 + 3 per second")
	var r := Fakes.spawn_player(world, 1, &"rogue", Vector3(4, 0, 0))
	var energy := _res(r, &"energy")
	energy.set_value(10.0)
	energy.set_bonus({"regen_per_second_add": -100.0})
	check_eq(energy.regen_per_second(), 0.0, "regen clamped at 0")
	for i in 60:
		energy.tick(DT)
	check_eq(energy.value, 10.0, "no regen, no drain")


func test_gain_bonuses_on_hit_struck_and_crit() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior")
	var rage := _res(p, &"rage")
	rage.set_value(0.0)
	rage.set_bonus({"gain_on_hit_add": 2.0, "gain_on_damage_taken_add": -20.0})
	rage.on_weapon_hit(false)
	check_eq(rage.value, 6.0, "4 + 2 Rage per hit")
	rage.on_damage_taken()
	check_eq(rage.value, 6.0, "a negative gain stops at 0 (never drains)")
	var r := Fakes.spawn_player(world, 1, &"rogue", Vector3(4, 0, 0))
	var combo := _res(r, &"combo_points")
	combo.gain_mult = 3.0
	combo.set_bonus({"gain_on_crit_add": 1.0})
	combo.on_weapon_hit(true)
	check_eq(combo.value, 2.0, "two pips per crit (pips exact, Resource Regen ignored)")
	combo.on_weapon_hit(false)
	check_eq(combo.value, 2.0, "nothing without a crit")


func test_gain_per_hits_and_kills_never_below_one() -> void:
	var pal := Fakes.spawn_player(world, 0, &"paladin")
	var hp := _res(pal, &"holy_power")
	hp.set_bonus({"gain_per_hits_add": -2.0})
	check_eq(hp.gain_per_hits(), 3, "5 - 2 hits per Holy Power")
	hp.reset()
	for i in 2:
		hp.on_weapon_hit(false)
	check_eq(hp.value, 0.0, "2 hits: nothing")
	hp.on_weapon_hit(false)
	check_eq(hp.value, 1.0, "3rd hit: +1")
	hp.set_bonus({"gain_per_hits_add": -10.0})
	check_eq(hp.gain_per_hits(), 1, "never below 1")
	hp.on_weapon_hit(false)
	check_eq(hp.value, 2.0, "every hit")
	var war := Fakes.spawn_player(world, 1, &"warrior", Vector3(4, 0, 0))
	var rage := _res(war, &"rage")
	rage.set_bonus({"gain_per_hits_add": -1.0})
	check_eq(rage.gain_per_hits(), 0, "no rule in the data: a negative add keeps it off")
	rage.set_bonus({"gain_per_hits_add": 2.0})
	check_eq(rage.gain_per_hits(), 2, "a positive add creates one")
	var wl := Fakes.spawn_player(world, 2, &"warlock", Vector3(-4, 0, 0))
	var shards := _res(wl, &"soul_shard")
	shards.set_bonus({"gain_per_kills_add": -100.0})
	check_eq(shards.gain_per_kills(), 1, "kills per shard never below 1")


# --- Private ResourceData copies ---------------------------------------------------------------

func test_mana_max_value_add_on_the_mage_private_copy() -> void:
	var p := Fakes.spawn_player(world, 0, &"mage")
	var mana := _res(p, &"mana")
	p.begin_wave()  # MageMastery.sync_mana swaps in the private copy
	var shared: ResourceData = Db.get_class_data(&"mage").resources[0]
	check(mana.data != shared, "Mana runs on a private copy")
	var base := MageMastery.mana_max_for(p.stats.get_raw(Stats.INTELLECT))
	check_near(mana.max_value(), base, 0.001, "100 + 2 x Intellect")
	mana.set_bonus({"max_value_add": 20.0})
	check_near(mana.max_value(), base + 20.0, 0.001, "the bonus applies on the copy")
	mana.set_value(0.0)
	p.begin_wave()
	check_near(mana.value, base + 20.0, 0.001, "full at the wave start, bonus included")
	Fakes.step(p.abilities, 0.5)
	check_near(mana.max_value(), base + 20.0, 0.001, "sync_mana keeps the bonus")
	check_eq(shared.max_value, 100.0, "shared data untouched")


func test_shard_bonus_on_the_warlock_private_copy() -> void:
	var p := Fakes.spawn_player(world, 0, &"warlock")
	var shards := _res(p, &"soul_shard")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var sash := ItemGenerator.from_unique(Db.get_unique(&"soulbinders_sash"), 1, false, rng)
	check(p.equipment.equip(sash), "equip the sash")
	var mastery := p.abilities.mastery as WarlockMastery
	mastery.tick(DT)  # hooks the equipment
	check_eq(shards.data.gain_per_kills, 8, "the sash's private copy")
	shards.set_bonus({"gain_per_kills_add": -2.0})
	check_eq(shards.gain_per_kills(), 6, "8 - 2 kills per shard")
	p.begin_wave()
	var start := shards.value
	for i in 5:
		p.abilities.on_kill(null)
	check_eq(shards.value, start, "5 kills: nothing")
	p.abilities.on_kill(null)
	check_eq(shards.value, start + 1.0, "6th kill: +1 Soul Shard")
	check_eq(Db.get_class_data(&"warlock").resources[0].gain_per_kills, 12, "shared data untouched")
