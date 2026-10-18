extends "res://tests/test_class_mage_m4_base.gd"
## M6b item effects on the Mage spells (GDD 5.5): checked on what the spell really does (the
## shield amount, the burn an enemy takes), not only on the ability params (see
## test_items_content_m6b.gd for the data checks).


## Equips the unique [param id] on [param p] (Rank-independent: the item's own level 5 roll).
func _wear(p: Player, id: StringName) -> void:
	var data := Db.get_unique(id)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var item := ItemGenerator.from_unique(data, 5, false, rng, Db.get_class_data(data.class_restriction))
	check(p.equipment.equip(item), "%s worn" % id)


func test_robe_of_the_tidewoven_veil_makes_the_ice_barrier_absorb_a_quarter_more() -> void:
	var p := _mage()
	_learn(p, &"ice_barrier")
	var before := MageIceBarrier.shield_amount(_ctx(p, &"ice_barrier"))
	_wear(p, &"robe_of_the_tidewoven_veil")
	# The robe also brings Intellect (the barrier scales with it), so compare with the same stats:
	# the whole absorb (base shield + Intellect + Spell Power) x 1.25, not only the base shield.
	var i := p.stats.get_raw(Stats.INTELLECT)
	var sp := p.stats.get_raw(Stats.SPELL_POWER)
	var worn := MageIceBarrier.shield_amount(_ctx(p, &"ice_barrier"))
	check_near(_ctx(p, &"ice_barrier").num("power"), 1.25, 0.0001, "power x1.25 from the robe")
	check_near(worn, (4.0 + 0.5 * i + 0.5 * sp) * 1.25, 0.001, "the whole absorb x1.25 at Rank I")
	check(worn > before, "the robe makes the barrier stronger")
