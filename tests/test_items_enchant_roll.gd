extends TestCase


func _enchant(stats: Dictionary) -> EnchantData:
	var e := EnchantData.new()
	e.kind = EnchantData.Kind.EQUIP
	for k in stats:
		e.equip_stats[k] = stats[k]
	e.description = "Equip: +{pierce} Pierce, +{crit}% Crit."
	return e


func test_count_stats_are_whole_numbers_per_rank() -> void:
	var e := _enchant({Stats.PIERCE: 1.0, Stats.CRIT: 2.0})
	check_eq(EnchantRoll.new(e, 0).equip_stats()[Stats.PIERCE], 1.0, "rank I")
	check_eq(EnchantRoll.new(e, 1).equip_stats()[Stats.PIERCE], 1.0, "rank II rounds 1.5 down")
	check_eq(EnchantRoll.new(e, 2).equip_stats()[Stats.PIERCE], 2.0, "rank III")
	check_eq(EnchantRoll.new(e, 1).equip_stats()[Stats.CRIT], 3.0, "normal stats keep fractions of the rank multiplier")
	check_eq(EnchantRoll.new(e, 1).description(), "Equip: +1 Pierce, +3% Crit.", "tooltip text")
