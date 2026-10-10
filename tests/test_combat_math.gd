extends TestCase


func _weapon(base: float, scaling: Dictionary) -> WeaponData:
	var w := WeaponData.new()
	w.base_damage = base
	for k in scaling:
		w.scaling[k] = scaling[k]
	w.cooldown = 1.0
	return w


func test_weapon_damage_scales_with_stats() -> void:
	var s := StatBlock.new()
	s.set_source(&"x", {Stats.STRENGTH: 4.0, Stats.INTELLECT: 10.0})
	var w := _weapon(6.0, {Stats.STRENGTH: 1.0, Stats.INTELLECT: 0.5})
	check_eq(CombatMath.weapon_hit_damage(w, s), 15.0)
	s.set_source(&"vers", {Stats.VERSATILITY: 20.0})
	check_eq(CombatMath.weapon_hit_damage(w, s), 18.0)


func test_weapon_damage_minimum_one() -> void:
	var s := StatBlock.new()
	s.set_source(&"x", {Stats.STRENGTH: -40.0})
	check_eq(CombatMath.weapon_hit_damage(_weapon(6.0, {Stats.STRENGTH: 1.0}), s), 1.0)


func test_haste_shortens_cooldown() -> void:
	var s := StatBlock.new()
	s.set_source(&"x", {Stats.HASTE: 100.0})
	check_eq(CombatMath.weapon_cooldown(_weapon(5.0, {}), s), 0.5)


func test_armor_reduction() -> void:
	check_eq(CombatMath.armor_reduction(0.0), 0.0)
	check_eq(CombatMath.armor_reduction(15.0), 0.5)
	check(CombatMath.armor_reduction(-5.0) < 0.0, "negative armour increases damage")


func test_incoming_damage() -> void:
	var s := StatBlock.new()
	s.set_source(&"x", {Stats.ARMOR: 15.0})
	check_eq(CombatMath.incoming_damage(10.0, s), 5.0, "armour halves")
	s.set_source(&"y", {Stats.AVOIDANCE: 50.0})
	check_eq(CombatMath.incoming_damage(10.0, s, CombatMath.KIND_MELEE), 5.0, "avoidance ignores melee")
	check_eq(CombatMath.incoming_damage(20.0, s, CombatMath.KIND_PROJECTILE), 5.0, "avoidance halves projectiles")
	check_eq(CombatMath.incoming_damage(0.1, s), 1.0, "minimum damage")


func test_incoming_damage_is_not_rounded() -> void:
	# Small armour values count: 1 armour on a 2-damage hit = 2 * (1 - 1/16) = 1.875 (was 2).
	var s := StatBlock.new()
	s.set_source(&"x", {Stats.ARMOR: 1.0})
	check_eq(CombatMath.incoming_damage(2.0, s), 2.0 * (1.0 - 1.0 / 16.0), "1 armour")
	var none := StatBlock.new()
	check_eq(CombatMath.incoming_damage(1.32, none), 1.32, "fractional wave-scaled damage passes through")
	none.set_source(&"v", {Stats.VERSATILITY: 10.0})
	check_eq(CombatMath.incoming_damage(3.0, none), 3.0 * 0.95, "10 versatility = -5%")
	check_eq(CombatMath.incoming_damage(1.05, none), 1.0, "still at least MIN_DAMAGE")


func test_rolls_respect_chance() -> void:
	var s := StatBlock.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	s.set_source(&"x", {Stats.CRIT: 100.0, Stats.DODGE: 0.0})
	check(CombatMath.roll_crit(s, rng), "100% crit always crits")
	check(not CombatMath.roll_dodge(s, rng), "0% dodge never dodges")


func test_gold_find() -> void:
	var s := StatBlock.new()
	s.set_source(&"x", {Stats.GOLD_FIND: 50.0})
	check_eq(CombatMath.gold_with_find(10, s), 15.0)
	s.set_source(&"x", {Stats.GOLD_FIND: 10.0})
	check_eq(CombatMath.gold_with_find(1, s), 1.1, "exact, not rounded")
	check_eq(CombatMath.gold_with_find_pct(4.0, 25.0), 5.0)
	check_eq(CombatMath.gold_with_find_pct(4.0, -150.0), 0.0, "never negative")
