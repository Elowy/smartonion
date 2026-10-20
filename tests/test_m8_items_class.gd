extends "res://tests/shaman_base.gd"
## M8 ITEMS-CLASS: the Hunter's and the Shaman's gear – the two class tier sets (Wildtracker's Garb, Totemkeeper's
## Mail), the two Artifacts (Galestrike Longbow: Gale Volley, Rising Gale; Fist of the Ancestors: Thunderpost,
## Ancestral Chorus), their 16 class items, the look of the sets, the Artifact drop rules for seven classes and the
## content invariants without any pending line for these parts.

const Rules := preload("res://tests/content_rules.gd")
const EFakes := preload("res://tests/enemies_fakes.gd")

const HUNTER_SET := &"wildtracker_garb"
const SHAMAN_SET := &"totemkeeper_mail"
const LONGBOW := &"galestrike_longbow"
const FIST := &"fist_of_the_ancestors"
const SLOTS: Array[int] = [Items.SlotType.HEAD, Items.SlotType.SHOULDERS, Items.SlotType.CHEST,
	Items.SlotType.HANDS, Items.SlotType.LEGS]
const SEVEN: Array[StringName] = [&"warrior", &"mage", &"paladin", &"rogue", &"warlock", &"hunter", &"shaman"]

## The class items: id -> [ability or pseudo id, rarity, slot].
const HUNTER_ITEMS := {
	&"longbow_of_many_feathers": [&"arrow_fan", Items.Rarity.EPIC, Items.SlotType.WEAPON],
	&"hood_of_the_far_mark": [&"long_shot", Items.Rarity.EPIC, Items.SlotType.HEAD],
	&"hauberk_of_the_loyal_heart": [&"hunter_companion", Items.Rarity.EPIC, Items.SlotType.CHEST],
	&"legguards_of_the_arrow_storm": [&"arrow_hail", Items.Rarity.EPIC, Items.SlotType.LEGS],
	&"pauldrons_of_the_hunt_horn": [&"hunt_signal", Items.Rarity.RARE, Items.SlotType.SHOULDERS],
	&"gloves_of_the_steady_draw": [&"quick_draw", Items.Rarity.RARE, Items.SlotType.HANDS],
	&"snaresmiths_belt": [&"blast_snare", Items.Rarity.RARE, Items.SlotType.WAIST],
	&"boots_of_the_quiet_retreat": [&"backstep", Items.Rarity.RARE, Items.SlotType.FEET],
}
const SHAMAN_ITEMS := {
	&"rootbound_bulwark": [&"shaman_totems", Items.Rarity.RARE, Items.SlotType.WEAPON],
	&"mask_of_the_gathering_storm": [&"forking_bolt", Items.Rarity.EPIC, Items.SlotType.HEAD],
	&"pauldrons_of_the_static_crown": [&"thunderbolt", Items.Rarity.RARE, Items.SlotType.SHOULDERS],
	&"hauberk_of_the_restless_hill": [&"rumbling_earth", Items.Rarity.EPIC, Items.SlotType.CHEST],
	&"cinderlash_grips": [&"magma_lash", Items.Rarity.RARE, Items.SlotType.HANDS],
	&"belt_of_gathered_thunder": [&"stormburst", Items.Rarity.RARE, Items.SlotType.WAIST],
	&"greaves_of_the_soft_rain": [&"soothing_downpour", Items.Rarity.EPIC, Items.SlotType.LEGS],
	&"boots_of_the_howling_kin": [&"spirit_pack", Items.Rarity.EPIC, Items.SlotType.FEET],
}
## What each item makes of its ability at Rank I: item id -> {param: value}.
const ITEM_RESULTS := {
	&"longbow_of_many_feathers": {"arrows": 7.0},
	&"hood_of_the_far_mark": {"cooldown": 6.0},
	&"legguards_of_the_arrow_storm": {"radius": 4.0, "duration": 5.0},
	&"pauldrons_of_the_hunt_horn": {"cooldown": 8.0},
	&"gloves_of_the_steady_draw": {"duration": 5.5},
	&"snaresmiths_belt": {"radius": 3.2, "arm_time": 0.3},
	&"boots_of_the_quiet_retreat": {"cooldown": 6.0, "distance": 6.5},
	&"mask_of_the_gathering_storm": {"cost": 22.0},
	&"pauldrons_of_the_static_crown": {"cooldown": 3.5},
	&"hauberk_of_the_restless_hill": {"duration": 7.0, "radius": 5.0},
	&"cinderlash_grips": {"spread_targets": 3.0},
	&"belt_of_gathered_thunder": {"min_enemies": 2.0, "cooldown": 8.0},
	&"greaves_of_the_soft_rain": {"cooldown": 12.0},
	&"boots_of_the_howling_kin": {"duration": 15.0, "bite_pct": 60.0},
}

var _rng := RandomNumberGenerator.new()


func before_each() -> void:
	super()
	_rng.seed = 77
	LootDrops.artifact_chance_override = -1.0
	ItemGenerator.independent_share_override = -1.0


func after_each() -> void:
	LootDrops.artifact_chance_override = -1.0
	ItemGenerator.independent_share_override = -1.0
	super()


# --- Helpers -----------------------------------------------------------------------------------

func _hunter(pos: Vector3 = Vector3.ZERO, index: int = 0) -> Player:
	var p := Fakes.spawn_player(world, index, &"hunter", pos)
	# Deterministic damage: no random crits / dodges unless a test asks for them.
	p.stats.set_source(&"test", {Stats.CRIT: -500.0, Stats.DODGE: -500.0})
	p.facing = Vector3.FORWARD
	p.abilities._physics_process(DT)
	return p


func _foe(pos: Vector3) -> Fakes.FakeEnemy:
	var e := Fakes.spawn_enemy(world, pos)
	EnemyGrid.mark_dirty()
	return e


## Puts the Artifact of [param p]'s class into its hand with [param waves] wave ends held.
func _wield(p: Player, waves: int) -> ItemInstance:
	var item := ItemGenerator.generate_artifact(p.class_data.id, 10)
	item.artifact_waves = waves
	p.equipment.backpack.append(item)
	check(p.equipment.equip(item), "%s wields its Artifact" % p.class_data.id)
	return item


func _piece(set_id: StringName, index: int) -> ItemInstance:
	var data := Db.get_set(set_id)
	return ItemGenerator.from_unique(Db.get_unique(data.piece_ids[index]), 8, false, _rng)


## Wears the first [param count] pieces of [param set_id].
func _wear_set(p: Player, set_id: StringName, count: int) -> void:
	for i in count:
		var item := _piece(set_id, i)
		p.equipment.add_to_backpack(item)
		check(p.equipment.equip(item), "wears %s" % item.display_name)


func _script(p: Player, artifact_id: StringName, index: int) -> TalentEffect:
	return p.bonuses.script_for(StringName("artifact:%s:%d" % [artifact_id, index]))


func _volley(p: Player) -> ArtifactHunterGaleVolley:
	return _script(p, LONGBOW, 0) as ArtifactHunterGaleVolley


func _post_script(p: Player) -> ArtifactShamanThunderpost:
	return _script(p, FIST, 0) as ArtifactShamanThunderpost


## One plain shot of [param p] that hit [param target] (the first hit of an attack of the main hand).
func _shot(p: Player, target: Node3D, damage: float = 10.0, is_crit: bool = false, extra: bool = false,
		first: bool = true) -> void:
	p.on_hit_dealt(damage, target, p.main_hand, is_crit, extra, first, damage)


func _gale_arrows(p: Player) -> Array[ArtifactHunterGaleArrow]:
	var out: Array[ArtifactHunterGaleArrow] = []
	for node in tree.get_nodes_in_group(&"projectiles"):
		var a := node as ArtifactHunterGaleArrow
		if a != null and a.attacker == p and not a.is_queued_for_deletion():
			out.append(a)
	return out


func _hunter_arrows(p: Player) -> Array[HunterArrow]:
	var out: Array[HunterArrow] = []
	for node in tree.get_nodes_in_group(&"projectiles"):
		var a := node as HunterArrow
		if a != null and a.attacker == p and not a.is_queued_for_deletion():
			out.append(a)
	return out


## Flies every projectile of [param p] for [param seconds].
func _fly(p: Player, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		for node in tree.get_nodes_in_group(&"projectiles"):
			var proj := node as Projectile
			if proj != null and proj.attacker == p and not proj.is_queued_for_deletion():
				proj.advance(DT)
		t += DT


## Steps the world's totems / areas / pets for [param seconds] in physics-sized steps (the base's
## _step_world takes one step of the length it is given).
func _run_world(seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		_step_world(DT)
		t += DT


# --- The class sets: data ---------------------------------------------------------------------------

func test_both_class_sets_have_five_epic_mail_pieces_for_their_class() -> void:
	var want := {&"hunter": [HUNTER_SET, "Wildtracker's Garb", Stats.AGILITY],
		&"shaman": [SHAMAN_SET, "Totemkeeper's Mail", Stats.INTELLECT]}
	for class_id: StringName in want:
		var data := Db.set_for_class(class_id)
		check(data != null, "%s has a class set" % class_id)
		if data == null:
			continue
		check_eq(data.id, want[class_id][0], "%s: set id" % class_id)
		check_eq(data.display_name, want[class_id][1], "%s: set name" % class_id)
		check_eq(data.class_id, class_id, "%s: the set's class" % class_id)
		check_eq(data.armor_type, -1, "%s: a class set has no independent armour type" % class_id)
		check(not data.is_independent(), "%s: not independent" % class_id)
		check_eq(Rules.class_sets(class_id).size(), 1, "%s: exactly one class set" % class_id)
		check_eq(data.piece_ids.size(), Rules.PIECES_PER_SET, "%s: five pieces" % class_id)
		var cls := Db.get_class_data(class_id)
		for i in data.piece_ids.size():
			var id := data.piece_ids[i]
			check_eq(String(id), "set_%s_%s" % [class_id, ["head", "shoulders", "chest", "hands", "legs"][i]], "%s: piece id %d" % [class_id, i])
			var u := Db.get_unique(id)
			check(u != null, "%s exists" % id)
			if u == null:
				continue
			check_eq(u.slot_type, SLOTS[i], "%s: slot" % id)
			check_eq(u.armor_type, ClassData.ArmorType.MAIL, "%s: Mail" % id)
			check_eq(u.rarity, Items.Rarity.EPIC, "%s: Epic" % id)
			check_eq(u.class_restriction, class_id, "%s: restricted to the class" % id)
			check_eq(u.set_id, data.id, "%s: set id" % id)
			check(u.display_name != "" and u.flavor != "", "%s: name and flavour" % id)
			check(u.display_name.begins_with(data.display_name.split(" ")[0]), "%s: named after the set" % id)
			check_eq(u.sources, [&"shop", &"loot", &"elite", &"goblin", &"boss"] as Array[StringName], "%s: sources" % id)
			check_eq(u.min_wave, 6, "%s: from wave 6" % id)
			check_eq(u.weight, 0.0, "%s: only the set roll picks it" % id)
			check(u.weapon == null and u.unique_effect == &"", "%s: no weapon, no unique effect" % id)
			check(u.stats.get(want[class_id][2], 0.0) >= 5.0 and u.stats.get(Stats.STAMINA, 0.0) >= 5.0,
					"%s: primary stat and Stamina" % id)
			check(ItemGenerator.unique_usable_by(u, cls), "%s: usable by its class" % id)
			for other in Db.class_ids:
				if other != class_id:
					check(not ItemGenerator.unique_usable_by(u, Db.get_class_data(other)), "%s: not usable by %s" % [id, other])


func test_class_set_bonuses_are_two_and_four_pieces_and_valid() -> void:
	for set_id in [HUNTER_SET, SHAMAN_SET]:
		var data := Db.get_set(set_id)
		var class_id := data.class_id
		var pieces: Array[int] = []
		for b in data.bonuses:
			pieces.append(int(b["pieces"]))
			check(String(b["text"]) != "", "%s: bonus text" % set_id)
			for e: Dictionary in b["effects"]:
				check_eq(BonusVocabulary.validate(e, class_id), "", "%s: %d-piece entry valid: %s" % [set_id, b["pieces"], e])
		check_eq(pieces, [2, 4] as Array[int], "%s: bonuses at 2 and 4 pieces" % set_id)


func test_both_sets_are_in_the_pools_of_their_class() -> void:
	for class_id in [&"hunter", &"shaman"]:
		var cls := Db.get_class_data(class_id)
		check_eq(Db.sets_for_class(class_id, cls)[0].id, Db.set_for_class(class_id).id, "%s: its own set comes first" % class_id)
		# Only class sets: a hit gives a piece of the class's set.
		ItemGenerator.independent_share_override = 0.0
		var slots: Dictionary[int, bool] = {}
		var hits := 0
		var r := RandomNumberGenerator.new()
		r.seed = 5
		for i in 4000:
			var piece := ItemGenerator._roll_set_piece(ItemGenerator.Source.LOOT, 14, -1, cls, [], r)
			if piece == null:
				continue
			hits += 1
			check_eq(piece.set_id, Db.set_for_class(class_id).id, "%s: a class-set piece" % class_id)
			slots[piece.slot_type] = true
		check(hits > 300, "%s: the set rolls (%d hits)" % [class_id, hits])
		check_eq(slots.size(), 5, "%s: all five slots come up" % class_id)
		# The default share: 30% of the hits go to the independent sets of the Mail armour.
		ItemGenerator.independent_share_override = -1.0
		var own := 0
		var all := 0
		r.seed = 6
		for i in 6000:
			var piece := ItemGenerator._roll_set_piece(ItemGenerator.Source.LOOT, 14, -1, cls, [], r)
			if piece == null:
				continue
			all += 1
			if piece.class_restriction == class_id:
				own += 1
		check_near(float(own) / float(all), 1.0 - ItemGenerator.SET_INDEPENDENT_SHARE, 0.06, "%s: ~70%% of the hits are the class set" % class_id)


func test_a_wave_before_six_has_no_class_set_piece() -> void:
	for class_id in [&"hunter", &"shaman"]:
		var r := RandomNumberGenerator.new()
		r.seed = 9
		ItemGenerator.independent_share_override = 0.0
		for i in 1500:
			check(ItemGenerator._roll_set_piece(ItemGenerator.Source.LOOT, 5, -1, Db.get_class_data(class_id), [], r) == null,
					"%s: no set piece before wave 6" % class_id)


# --- The class sets: bonuses ------------------------------------------------------------------------

func test_wildtrackers_garb_two_pieces_boost_the_companion_four_add_two_arrows() -> void:
	var p := _hunter()
	var foe := _foe(Vector3(0, 0, -5))
	var arrow_fan := Db.get_ability(&"arrow_fan")
	# The set's entries alone (the Mastery's Beastbond rides on the set pieces' Mastery stat).
	check_near(p.bonuses.damage_mult(foe, &"physical", &"pet"), 1.0, 0.0001, "no pieces: no bonus")
	check_eq(int(p.abilities.params_at_rank(arrow_fan, 1)["arrows"]), 5, "no pieces: 5 arrows")
	_wear_set(p, HUNTER_SET, 1)
	check_near(p.bonuses.damage_mult(foe, &"physical", &"pet"), 1.0, 0.0001, "one piece: nothing yet")
	p.equipment.unequip(Items.EquipSlot.HEAD)
	_wear_set(p, HUNTER_SET, 2)
	check_near(p.bonuses.damage_mult(foe, &"physical", &"pet"), 1.10, 0.0001, "2 pieces: the companion deals 10% more")
	check_near(p.bonuses.damage_mult(foe, &"physical", &"weapon"), 1.0, 0.0001, "2 pieces: weapon hits are untouched")
	check_near(p.bonuses.damage_mult(foe, &"physical", &"ability"), 1.0, 0.0001, "2 pieces: abilities are untouched")
	check_eq(int(p.abilities.params_at_rank(arrow_fan, 1)["arrows"]), 5, "2 pieces: still 5 arrows")
	for i in range(2, 4):
		var item := _piece(HUNTER_SET, i)
		p.equipment.add_to_backpack(item)
		check(p.equipment.equip(item), "wears piece %d" % i)
	check_eq(int(p.abilities.params_at_rank(arrow_fan, 1)["arrows"]), 7, "4 pieces: 7 arrows")
	check_near(p.bonuses.damage_mult(foe, &"physical", &"pet"), 1.10, 0.0001, "4 pieces keep the 2-piece bonus")
	# The cast really looses seven arrows.
	check(p.abilities.try_cast(p.abilities.slot_of(&"arrow_fan")), "Arrow Fan is cast")
	check_eq(_hunter_arrows(p).size(), 7, "seven arrows in the air")


func test_the_companion_set_bonus_reaches_the_companions_hits() -> void:
	var p := _hunter()
	var foe := _foe(Vector3(0, 0, -3))
	var comp := (p.abilities.mastery as HunterMastery).ensure_companion()
	check(comp != null, "the companion exists")
	var plain := p.procs.deal_raw(foe, 10.0, &"physical", false, &"pet")
	# Head and Hauberk: no Mastery stat on them, so Beastbond stays out of the ratio.
	for i in [0, 2]:
		var item := _piece(HUNTER_SET, i)
		p.equipment.add_to_backpack(item)
		check(p.equipment.equip(item), "wears piece %d" % i)
	var boosted := p.procs.deal_raw(foe, 10.0, &"physical", false, &"pet")
	check_near(boosted / plain, 1.10, 0.0001, "a pet hit deals 10% more with the 2-piece bonus")
	var weapon_hit := p.procs.deal_raw(foe, 10.0, &"physical", false, &"proc")
	check_near(weapon_hit, 10.0 * p.outgoing_damage_mult(foe, &"physical", &"proc"), 0.0001, "other sources are not boosted")


func test_totemkeepers_mail_two_pieces_lengthen_totems_four_add_two_enemies() -> void:
	var p := _shaman()
	p.stats.set_source(&"test", {Stats.INTELLECT: 10.0, Stats.SPELL_POWER: 4.0})
	var rite := Db.get_ability(&"totem_rite")
	var bolt := Db.get_ability(&"forking_bolt")
	check_near(float(ShamanKit.totem_params(p, p.abilities.params_for(rite))["duration"]), 10.0, 0.001, "no pieces: 10 s")
	check_eq(int(p.abilities.params_for(bolt)["targets"]), 4, "no pieces: 4 targets")
	_wear_set(p, SHAMAN_SET, 1)
	check_near(float(ShamanKit.totem_params(p, p.abilities.params_for(rite))["duration"]), 10.0, 0.001, "1 piece: nothing yet")
	p.equipment.unequip(Items.EquipSlot.HEAD)
	_wear_set(p, SHAMAN_SET, 2)
	check_near(float(ShamanKit.totem_params(p, p.abilities.params_for(rite))["duration"]), 13.0, 0.001, "2 pieces: 13 s (+30%)")
	check_eq(int(p.abilities.params_for(bolt)["targets"]), 4, "2 pieces: still 4 targets")
	# A cast plants a totem that stands 13 s.
	check(_cast(p, &"totem_rite"), "Totem Rite is cast")
	var totem := _fx_rite(p).standing()[0]
	check_near(totem.time_left(), 13.0, 0.01, "the totem stands 13 s")
	for i in range(2, 4):
		var item := _piece(SHAMAN_SET, i)
		p.equipment.add_to_backpack(item)
		check(p.equipment.equip(item), "wears piece %d" % i)
	check_eq(int(p.abilities.params_for(bolt)["targets"]), 6, "4 pieces: 6 targets")
	for i in 8:
		_enemy(Vector3(0.0, 0.0, -2.0 - float(i)))
	_full_surge(p)
	check(_cast(p, &"forking_bolt"), "Forking Bolt is cast")
	check_eq(_effect(p, &"forking_bolt").last_hits.size(), 6, "the bolt forks to six enemies")


func test_the_set_bonuses_leave_with_the_pieces() -> void:
	var p := _hunter()
	var foe := _foe(Vector3(0, 0, -5))
	var fan := Db.get_ability(&"arrow_fan")
	_wear_set(p, HUNTER_SET, 4)
	check_eq(int(p.abilities.params_at_rank(fan, 1)["arrows"]), 7, "four pieces: 7 arrows")
	check(p.equipment.unequip(Items.EquipSlot.CHEST), "a piece comes off")
	check_eq(int(p.abilities.params_at_rank(fan, 1)["arrows"]), 5, "three pieces: the 4-piece bonus is gone")
	check_near(p.bonuses.damage_mult(foe, &"physical", &"pet"), 1.10, 0.0001, "three pieces: the 2-piece bonus stays")
	check(p.equipment.unequip(Items.EquipSlot.HEAD), "another piece comes off")
	check_near(p.bonuses.damage_mult(foe, &"physical", &"pet"), 1.10, 0.0001, "two pieces: the 2-piece bonus stays")
	check(p.equipment.unequip(Items.EquipSlot.HANDS), "a third piece comes off")
	check_near(p.bonuses.damage_mult(foe, &"physical", &"pet"), 1.0, 0.0001, "one piece: no bonus")


# --- The set looks -----------------------------------------------------------------------------------

func test_the_class_sets_have_their_own_looks() -> void:
	for id in [HUNTER_SET, SHAMAN_SET]:
		check(OnionArmor.SET_STYLES.has(id), "%s has a style" % id)
		var kit: Dictionary = OnionArmor.SET_STYLES[id]
		for k: String in ["main", "dark", "light", "trim", "glow"]:
			check(kit.has(k) and kit[k] is Color, "%s: %s" % [id, k])
		check(kit["main"] != OnionArmor.GENERIC_SET["main"], "%s: not the generic gold" % id)
		var main: Color = kit["main"]
		for other in OnionArmor.SET_STYLES:
			if other == id:
				continue
			var d := Vector3(main.r, main.g, main.b).distance_to(Vector3(
					(OnionArmor.SET_STYLES[other]["main"] as Color).r, (OnionArmor.SET_STYLES[other]["main"] as Color).g,
					(OnionArmor.SET_STYLES[other]["main"] as Color).b))
			check(d >= 0.25, "%s is clearly different from %s (colour distance %.2f)" % [id, other, d])
		for slot in [EquipLook.Slot.HEAD, EquipLook.Slot.SHOULDERS, EquipLook.Slot.CHEST]:
			var look := EquipLook.make(slot, ClassData.ArmorType.MAIL, 1, Items.Rarity.EPIC, id)
			var pal := OnionArmor.palette(look)
			check_eq(pal.main, kit["main"], "%s: the palette is the kit" % id)
			var part := OnionArmor.part(slot, look, Db.get_class_data(Db.get_set(id).class_id))
			check(part != null and part.solid != null, "%s: draws slot %d" % [id, slot])
	check(OnionArmor.SET_STYLES[HUNTER_SET]["main"] != OnionArmor.SET_STYLES[SHAMAN_SET]["main"], "the two sets differ")
	var hunter_main: Color = OnionArmor.SET_STYLES[HUNTER_SET]["main"]
	check(hunter_main.g > hunter_main.r and hunter_main.g > hunter_main.b, "the Hunter's set is green")
	var shaman_main: Color = OnionArmor.SET_STYLES[SHAMAN_SET]["main"]
	check(shaman_main.b > shaman_main.r and shaman_main.g > shaman_main.r, "the Shaman's set is teal")


# --- The Artifacts: data ------------------------------------------------------------------------------

func test_the_two_artifacts_are_valid_and_belong_to_their_class() -> void:
	var want := {&"hunter": [LONGBOW, &"bow", true], &"shaman": [FIST, &"fist_weapon", false]}
	for class_id: StringName in want:
		var data := Db.artifact_for_class(class_id)
		check(data != null, "%s has an Artifact" % class_id)
		if data == null:
			continue
		check_eq(data.id, want[class_id][0], "%s: the Artifact" % class_id)
		check_eq(Artifacts.validate(data), "", "%s: valid data" % data.id)
		check_eq(data.weapon.weapon_type, want[class_id][1], "%s: its weapon type" % class_id)
		check_eq(data.weapon.is_two_handed(), want[class_id][2], "%s: two-handed" % class_id)
		check(not data.is_pair(), "%s: a single weapon" % class_id)
		check_eq(data.unlock_waves, [3, 6] as Array[int], "%s: properties after 3 and 6 wave ends" % class_id)
		check_eq(data.rarity, Items.Rarity.ARTIFACT, "%s: rarity" % class_id)
		check_eq(data.sources, [&"loot"] as Array[StringName], "%s: loot only" % class_id)
		check_eq(data.weight, 0.0, "%s: no normal pool" % class_id)
		check_eq(Rules.count_of(class_id, "artifact"), 1, "%s: exactly one" % class_id)
		for p in data.properties:
			check(String(p["short"]).length() <= Artifacts.SHORT_TEXT_MAX, "%s: short text fits" % p["name"])
	check_eq(Db.get_artifact(LONGBOW).display_name, "Galestrike Longbow", "name")
	check_eq(Db.get_artifact(FIST).display_name, "Fist of the Ancestors", "name")
	check_eq(Db.get_artifact(LONGBOW).properties[0]["name"], "Gale Volley", "P1")
	check_eq(Db.get_artifact(LONGBOW).properties[1]["name"], "Rising Gale", "P2")
	check_eq(Db.get_artifact(FIST).properties[0]["name"], "Thunderpost", "P1")
	check_eq(Db.get_artifact(FIST).properties[1]["name"], "Ancestral Chorus", "P2")
	check_eq(Artifacts.needs_of(Db.get_artifact(FIST).properties[0]), &"forking_bolt", "Thunderpost needs Forking Bolt")
	check_eq(Artifacts.needs_of(Db.get_artifact(FIST).properties[1]), &"totem_rite", "Ancestral Chorus needs Totem Rite")


func test_the_artifacts_drop_as_items_of_the_right_weapon() -> void:
	var bow := ItemGenerator.generate_artifact(&"hunter", 12)
	check(bow != null and bow.is_artifact(), "the Hunter's Artifact")
	check_eq(bow.source_id, LONGBOW, "the longbow")
	check_eq(bow.weapon.weapon_type, &"bow", "a bow")
	check_eq(bow.class_restriction, &"hunter", "Hunter only")
	check_near(bow.weapon.base_damage, Db.get_weapon(&"bow").base_damage * 3.0, 0.001, "Artifact damage: x3 the base")
	check_eq(bow.enchants.size(), 2, "two fixed enchants")
	var fist := ItemGenerator.generate_artifact(&"shaman", 12)
	check_eq(fist.source_id, FIST, "the fist")
	check_eq(fist.weapon.weapon_type, &"fist_weapon", "a fist weapon")
	check_near(fist.weapon.base_damage, Db.get_weapon(&"fist_weapon").base_damage * 3.0, 0.001, "Artifact damage: x3 the base")
	check_eq(fist.class_restriction, &"shaman", "Shaman only")
	# The weapon and the class: only its own class wields it.
	for class_id in Db.class_ids:
		var cls := Db.get_class_data(class_id)
		check_eq(ItemGenerator.unique_usable_by(Db.get_artifact(LONGBOW), cls), class_id == &"hunter", "%s and the longbow" % class_id)
		check_eq(ItemGenerator.unique_usable_by(Db.get_artifact(FIST), cls), class_id == &"shaman", "%s and the fist" % class_id)


func test_the_properties_awaken_after_three_and_six_wave_ends() -> void:
	var p := _hunter()
	var item := _wield(p, 0)
	check_eq(Artifacts.awake_count(item), 0, "asleep when found")
	check(_volley(p) == null, "no Gale Volley yet")
	item.artifact_waves = 2
	p.equipment.changed.emit()
	check(_volley(p) == null, "two wave ends: still asleep")
	item.artifact_waves = 3
	p.equipment.changed.emit()
	check(_volley(p) != null, "three wave ends: Gale Volley")
	check_near(p.abilities.get_resource(&"focus").gain_on_crit(), 0.0, 0.0001, "Rising Gale still sleeps")
	item.artifact_waves = 6
	p.equipment.changed.emit()
	check_near(p.abilities.get_resource(&"focus").gain_on_crit(), 4.0, 0.0001, "six wave ends: Rising Gale")
	check_eq(Artifacts.awake_count(item), 2, "both awake")
	# The wave end itself grows it: wave ends held 2 -> 3.
	var grown := ItemGenerator.generate_artifact(&"hunter", 10)
	grown.artifact_waves = 2
	check(Artifacts.grow_item(grown), "grows")
	check(Artifacts.is_awake(grown, 0), "Gale Volley awake after the third wave end")


# --- Gale Volley -----------------------------------------------------------------------------------------

func test_gale_volley_looses_five_arrows_on_every_fourth_shot() -> void:
	var p := _hunter()
	_wield(p, 3)
	var foe := _foe(Vector3(0, 0, -1.5))
	var v := _volley(p)
	check(v != null, "the script runs")
	for i in 3:
		_shot(p, foe)
	check_eq(v.shots, 3, "three shots counted")
	check_eq(_gale_arrows(p).size(), 0, "no arrows yet")
	_shot(p, foe)
	check_eq(_gale_arrows(p).size(), 5, "the fourth shot looses five arrows")
	check_eq(v.volleys, 1, "one volley")
	check_eq(v.shots, 0, "the count restarts")
	# Eight more shots: the next volley is the fourth one after, once the cooldown allows it.
	v.tick(1.0)
	for i in 3:
		_shot(p, foe)
	check_eq(_gale_arrows(p).size(), 5, "no second volley after three more shots")
	_shot(p, foe)
	check_eq(_gale_arrows(p).size(), 10, "the eighth shot looses the second volley")
	check_eq(v.volleys, 2, "two volleys")


func test_gale_volley_arrows_fan_out_over_forty_degrees_at_the_target() -> void:
	var p := _hunter()
	_wield(p, 3)
	var foe := _foe(Vector3(0, 0, -6))
	for i in 4:
		_shot(p, foe)
	var arrows := _gale_arrows(p)
	check_eq(arrows.size(), 5, "five arrows")
	var angles: Array[float] = []
	for a in arrows:
		angles.append(rad_to_deg(Vector3.FORWARD.signed_angle_to(a.direction, Vector3.UP)))
		check_eq(a.team, Projectile.TEAM_PLAYERS, "a hero's arrow")
		check_eq(a.style, &"arrow", "looks like an arrow")
	angles.sort()
	check_near(angles[0], -20.0, 0.5, "the left edge of the cone")
	check_near(angles[2], 0.0, 0.5, "the middle arrow flies at the target")
	check_near(angles[4], 20.0, 0.5, "the right edge of the cone")
	check_near(angles[4] - angles[0], 40.0, 1.0, "a 40 degree fan")


func test_gale_volley_arrows_deal_sixty_percent_of_the_shot_as_proc_damage() -> void:
	var p := _hunter()
	_wield(p, 3)
	var foe := _foe(Vector3(0, 0, -1.5))
	foe.hp = 100000.0
	foe.max_hp = 100000.0
	var hits_before := foe.fake_hits()
	for i in 4:
		_shot(p, foe, 20.0)
	var shot_hits := foe.fake_hits()
	check_eq(shot_hits, hits_before, "the on_hit_dealt calls of this test deal no damage themselves")
	_fly(p, 1.0)
	check_eq(foe.fake_hits(), 5, "all five arrows hit an enemy this close")
	var expected := 20.0 * 0.6 * p.outgoing_damage_mult(foe, &"physical", &"proc")
	for amount in foe.fake_damage_log:
		check_near(amount, expected, 0.001, "an arrow deals 60% of the shot")
	for crit in foe.fake_crit_log:
		check(not crit, "a volley arrow never crits")
	check_eq(_gale_arrows(p).size(), 0, "the arrows are used up")


func test_gale_volley_counts_only_first_hits_of_the_weapons_own_shots() -> void:
	var p := _hunter()
	_wield(p, 3)
	var foe := _foe(Vector3(0, 0, -1.5))
	var v := _volley(p)
	# An extra attack / an ability's arrow (HunterArrow: is_extra) is no shot.
	for i in 12:
		_shot(p, foe, 10.0, false, true, true)
	check_eq(v.shots, 0, "hits of extra attacks do not count")
	# The further hits of one piercing shot do not count (not the first hit of the attack).
	for i in 12:
		_shot(p, foe, 10.0, false, false, false)
	check_eq(v.shots, 0, "a pierced hit is not a new shot")
	check_eq(_gale_arrows(p).size(), 0, "no volley")
	_shot(p, foe)
	check_eq(v.shots, 1, "a plain first hit counts")
	check(not p.last_hit_extra, "the flag follows the hit")
	_shot(p, foe, 10.0, false, true, true)
	check(p.last_hit_extra, "the flag is set during an extra hit")
	check_eq(v.shots, 1, "still one")


func test_arrow_fan_and_the_volleys_own_arrows_do_not_count() -> void:
	var p := _hunter()
	_wield(p, 3)
	var foe := _foe(Vector3(0, 0, -1.5))
	foe.hp = 100000.0
	foe.max_hp = 100000.0
	var v := _volley(p)
	# A real Arrow Fan: five HunterArrows whose hits are weapon hits flagged as extra.
	for round in 3:
		p.abilities.set_cooldown(Db.get_ability(&"arrow_fan"), 0.0)
		p.abilities.get_resource(&"focus").set_value(100.0)
		check(p.abilities.try_cast(p.abilities.slot_of(&"arrow_fan")), "Arrow Fan %d" % round)
		_fly(p, 0.5)
	check(foe.fake_hits() >= 3, "the fans did hit (%d hits)" % foe.fake_hits())
	check_eq(v.shots, 0, "Arrow Fan arrows are no shots")
	check_eq(v.volleys, 0, "and loose no volley")
	# The volley's own arrows deal proc damage: no hook, no count, no recursion.
	for i in 4:
		_shot(p, foe)
	check_eq(v.volleys, 1, "a real volley")
	_fly(p, 1.0)
	check_eq(v.shots, 0, "the volley's arrows did not count")
	check_eq(v.volleys, 1, "and did not loose another volley")
	check_eq(_gale_arrows(p).size(), 0, "all arrows are gone")


func test_gale_volley_cooldown_caps_free_volleys() -> void:
	var p := _hunter()
	_wield(p, 3)
	var foe := _foe(Vector3(0, 0, -1.5))
	var v := _volley(p)
	for i in 4:
		_shot(p, foe)
	check_eq(v.volleys, 1, "the first volley")
	check_near(v.cooldown_left, 1.0, 0.001, "one second until the next")
	# A Quick Draw Hunter: four more shots inside the cooldown loose nothing; the count waits at four.
	for i in 8:
		_shot(p, foe)
	check_eq(v.volleys, 1, "no second volley inside the cooldown")
	check_eq(v.shots, 4, "the count waits at 'ready'")
	v.tick(0.5)
	_shot(p, foe)
	check_eq(v.volleys, 1, "half a second later: still cooling down")
	v.tick(0.6)
	_shot(p, foe)
	check_eq(v.volleys, 2, "the next shot after the cooldown looses the volley")
	check_eq(v.shots, 0, "the count restarts")
	check_eq(_gale_arrows(p).size(), 10, "two volleys of five")


func test_gale_volley_carries_across_waves_and_resets_when_the_bow_goes() -> void:
	var p := _hunter()
	var item := _wield(p, 3)
	var foe := _foe(Vector3(0, 0, -1.5))
	_shot(p, foe)
	_shot(p, foe)
	var v := _volley(p)
	check_eq(v.shots, 2, "two shots")
	p.begin_wave()
	p.end_wave()
	check_eq(_volley(p).shots, 2, "the count carries across waves")
	p.equipment.changed.emit()
	check_eq(_volley(p).shots, 2, "and across a re-applied equipment")
	var starter: ItemInstance = p.equipment.backpack[0]
	check(p.equipment.equip(starter), "the starter bow goes back on")
	check(_volley(p) == null, "the property is gone")
	check(p.equipment.equip(item), "the Artifact goes on again")
	check_eq(_volley(p).shots, 0, "a new count")


func test_gale_volley_sleeps_before_three_wave_ends_and_without_a_player_hook() -> void:
	var p := _hunter()
	_wield(p, 2)
	var foe := _foe(Vector3(0, 0, -1.5))
	for i in 8:
		_shot(p, foe)
	check_eq(_gale_arrows(p).size(), 0, "asleep: no arrows")


func test_gale_volley_draws_no_random_numbers() -> void:
	var p := _hunter()
	_wield(p, 3)
	var foe := _foe(Vector3(0, 0, -1.5))
	foe.hp = 100000.0
	foe.max_hp = 100000.0
	var state := RunState.rng.state
	for i in 4:
		_shot(p, foe)
	_fly(p, 1.0)
	check_eq(RunState.rng.state, state, "the volley is deterministic")


# --- Rising Gale ------------------------------------------------------------------------------------------

func test_rising_gale_restores_focus_on_crits_only() -> void:
	var p := _hunter()
	_wield(p, 6)
	var foe := _foe(Vector3(0, 0, -5))
	var focus := p.abilities.get_resource(&"focus")
	focus.set_value(0.0)
	_shot(p, foe, 10.0, false)
	check_near(focus.value, 0.0, 0.0001, "a plain hit gives no Focus")
	_shot(p, foe, 10.0, true)
	check_near(focus.value, 4.0, 0.0001, "a crit restores 4 Focus")
	_shot(p, foe, 10.0, true, true)
	check_near(focus.value, 8.0, 0.0001, "so does the crit of an ability's arrow")
	focus.set_value(98.0)
	_shot(p, foe, 10.0, true)
	check_near(focus.value, 100.0, 0.0001, "capped at the maximum")


func test_rising_gale_sleeps_until_the_sixth_wave_end() -> void:
	var p := _hunter()
	_wield(p, 5)
	var focus := p.abilities.get_resource(&"focus")
	focus.set_value(0.0)
	_shot(p, _foe(Vector3(0, 0, -5)), 10.0, true)
	check_near(focus.value, 0.0, 0.0001, "five wave ends: no Focus yet")


# --- Fist of the Ancestors: Thunderpost ----------------------------------------------------------------------

func _armed_shaman(waves: int, pos: Vector3 = Vector3.ZERO) -> Player:
	var p := _shaman(pos)
	p.stats.set_source(&"test", {Stats.INTELLECT: 10.0, Stats.SPELL_POWER: 4.0})
	_wield(p, waves)
	return p


func test_forking_bolt_plants_a_thunderpost_where_it_first_strikes() -> void:
	var p := _armed_shaman(3)
	var first := _enemy(Vector3(1.5, 0.0, -4.0))
	_enemy(Vector3(3.0, 0.0, -5.0))
	_full_surge(p)
	var script := _post_script(p)
	check(script != null, "the script runs")
	check(_cast(p, &"forking_bolt"), "Forking Bolt is cast")
	var posts := script.standing()
	check_eq(posts.size(), 1, "one post")
	if posts.is_empty():
		return
	var post := posts[0]
	check_eq(post.element, &"storm", "a storm totem")
	check_near(post.global_position.x, first.global_position.x, 0.001, "at the first enemy struck (x)")
	check_near(post.global_position.z, first.global_position.z, 0.001, "at the first enemy struck (z)")
	check_near(post.time_left(), 4.0, 0.001, "for four seconds")
	check(not post.is_in_group(&"enemies"), "no target")
	check(post.is_in_group(&"shaman_totems"), "a totem of the Shaman")
	check_eq(script.planted, 1, "counted")
	check_eq(_fx_rite(p).standing().size(), 0, "it is no Totem Rite totem (the Rite slot is free)")


func test_thunderpost_zaps_the_nearest_enemy_every_point_eight_seconds_for_forty_percent() -> void:
	var p := _armed_shaman(3)
	var near := _enemy(Vector3(0.0, 0.0, -4.0))
	var far := _enemy(Vector3(5.0, 0.0, -4.0))
	_full_surge(p)
	check(_cast(p, &"forking_bolt"), "cast")
	var fork := ShamanKit.last_fork(p)
	var post := _post_script(p).standing()[0]
	var near_before := near.fake_damage_log.size()
	var far_before := far.fake_damage_log.size()
	_run_world(0.2)
	check_eq(post.shots, 0, "nothing in the first 0.3 s")
	_run_world(0.2)
	check_eq(post.shots, 1, "the first zap just after planting")
	check_eq(near.fake_damage_log.size() - near_before, 1, "at the nearest enemy")
	check_eq(far.fake_damage_log.size() - far_before, 0, "not at the far one")
	var expected := float(fork["damage"]) * 0.4 * p.outgoing_damage_mult(near, &"nature", &"ability")
	check_near(near.fake_damage_log.back(), expected, 0.001, "40% of the bolt's first hit as Nature damage")
	_run_world(0.7)
	check_eq(post.shots, 1, "0.7 s later: nothing")
	_run_world(0.15)
	check_eq(post.shots, 2, "0.8 s after the first zap: the second one")
	_run_world(1.6)
	check_eq(post.shots, 4, "one zap every 0.8 s")


func test_thunderposts_zaps_do_not_roll_storm_echo_or_the_random_numbers() -> void:
	var p := _armed_shaman(3)
	p.stats.set_source(&"mastery", {Stats.MASTERY: 200.0})
	var foe := _enemy(Vector3(0.0, 0.0, -4.0))
	_full_surge(p)
	check(_cast(p, &"forking_bolt"), "cast")
	check_near(_mastery(p).echo_chance(), 60.0, 0.001, "a 60% echo chance")
	var echoes := _mastery(p).echoes
	var state := RunState.rng.state
	var before := foe.fake_damage_log.size()
	_run_world(3.6)
	var post_shots := _post_script(p).standing()[0].shots
	check(post_shots >= 4, "the post zapped (%d)" % post_shots)
	check_eq(foe.fake_damage_log.size() - before, post_shots, "exactly one hit per zap: no echo")
	check_eq(_mastery(p).echoes, echoes, "the Mastery did not echo")
	check_eq(RunState.rng.state, state, "no random number drawn")


func test_at_most_two_thunderposts_stand_and_the_oldest_goes_first() -> void:
	var p := _armed_shaman(3)
	_enemy(Vector3(0.0, 0.0, -4.0))
	var script := _post_script(p)
	var planted: Array[ShamanTotem] = []
	for i in 3:
		_full_surge(p)
		p.abilities.set_cooldown(Db.get_ability(&"forking_bolt"), 0.0)
		check(_cast(p, &"forking_bolt"), "cast %d" % i)
		var list := script.standing()
		planted.append(list.back())
		check(list.size() <= 2, "never more than two posts (%d)" % list.size())
	check_eq(script.standing().size(), 2, "two posts")
	check(planted[0].dismissed, "the first post was freed")
	check(not planted[1].dismissed and not planted[2].dismissed, "the newer two stand")
	check_eq(script.planted, 3, "three planted")


func test_thunderposts_end_with_their_time_the_wave_and_the_bolt() -> void:
	var p := _armed_shaman(3)
	_enemy(Vector3(0.0, 0.0, -4.0), 1000000.0)
	var script := _post_script(p)
	_full_surge(p)
	check(_cast(p, &"forking_bolt"), "cast")
	_run_world(3.8)
	check_eq(script.standing().size(), 1, "still there after 3.8 s")
	_run_world(0.4)
	check_eq(script.standing().size(), 0, "gone after four seconds")
	_full_surge(p)
	p.abilities.set_cooldown(Db.get_ability(&"forking_bolt"), 0.0)
	check(_cast(p, &"forking_bolt"), "cast again")
	check_eq(script.standing().size(), 1, "a new one")
	script.begin_wave()
	check_eq(script.standing().size(), 0, "a new wave clears the posts")
	p.abilities.set_cooldown(Db.get_ability(&"forking_bolt"), 0.0)
	_full_surge(p)
	check(_cast(p, &"forking_bolt"), "cast a third time")
	script.end_wave()
	check_eq(script.standing().size(), 0, "so does the wave end")
	p.abilities.set_cooldown(Db.get_ability(&"forking_bolt"), 0.0)
	_full_surge(p)
	check(_cast(p, &"forking_bolt"), "and a fourth time")
	var post := script.standing()[0]
	var fist := p.equipment.get_item(Items.EquipSlot.MAIN_HAND)
	check(p.equipment.take(fist), "the fist comes off")
	check(post.dismissed, "the post goes with the property")


func test_the_totemkeeper_bonus_lengthens_thunderposts_too() -> void:
	var p := _armed_shaman(3)
	_wear_set(p, SHAMAN_SET, 2)
	_enemy(Vector3(0.0, 0.0, -4.0))
	_full_surge(p)
	check(_cast(p, &"forking_bolt"), "cast")
	check_near(_post_script(p).standing()[0].time_left(), 4.0 * 1.3, 0.001, "4 s x 1.3")


func test_thunderpost_sleeps_before_three_wave_ends_and_needs_forking_bolt() -> void:
	var p := _armed_shaman(2)
	_enemy(Vector3(0.0, 0.0, -4.0))
	_full_surge(p)
	check(_post_script(p) == null, "asleep: no script")
	check(_cast(p, &"forking_bolt"), "cast")
	check_eq(tree.get_nodes_in_group(&"shaman_totems").size(), 0, "no post")
	var item := p.equipment.get_item(Items.EquipSlot.MAIN_HAND)
	item.artifact_waves = 3
	p.equipment.changed.emit()
	check(_post_script(p) != null, "awake")
	check_eq(Artifacts.property_rows(item, p)[0]["state"], Artifacts.STATE_AWAKE, "awake in the tooltip")


func test_a_thunderpost_without_an_enemy_in_reach_waits() -> void:
	var p := _armed_shaman(3)
	var foe := _enemy(Vector3(0.0, 0.0, -4.0))
	_full_surge(p)
	check(_cast(p, &"forking_bolt"), "cast")
	foe.global_position = Vector3(30.0, 0.0, -30.0)
	EnemyGrid.mark_dirty()
	var post := _post_script(p).standing()[0]
	var before := foe.fake_damage_log.size()
	_run_world(2.0)
	check_eq(post.shots, 0, "nothing in reach: no zap")
	foe.global_position = post.global_position + Vector3(2.0, 0.0, 0.0)
	EnemyGrid.mark_dirty()
	_run_world(0.1)
	check_eq(post.shots, 1, "an enemy walks up: the post zaps at once")
	check_eq(foe.fake_damage_log.size() - before, 1, "one hit")


# --- Fist of the Ancestors: Ancestral Chorus -------------------------------------------------------------------

func test_ancestral_chorus_gives_heroes_near_the_rite_totem_ten_percent_damage() -> void:
	var p := _armed_shaman(6)
	var near := _ally(1, Vector3(3.0, 0.0, 0.0))
	var far := _ally(2, Vector3(20.0, 0.0, 0.0))
	var base_p := CombatMath.damage_mult_for(p.stats, &"physical")
	var base_n := CombatMath.damage_mult_for(near.stats, &"physical")
	var base_f := CombatMath.damage_mult_for(far.stats, &"physical")
	check(_cast(p, &"totem_rite"), "Totem Rite")
	var totem := _fx_rite(p).standing()[0]
	check_near(totem.num("aura_damage_pct"), 10.0, 0.001, "the totem carries the aura")
	totem.step(0.3)
	check_near(CombatMath.damage_mult_for(p.stats, &"physical"), base_p + 0.10, 0.0001, "the Shaman deals 10% more")
	check_near(CombatMath.damage_mult_for(near.stats, &"physical"), base_n + 0.10, 0.0001, "so does the ally within 6 m")
	check_near(CombatMath.damage_mult_for(far.stats, &"physical"), base_f, 0.0001, "the far ally does not")
	_fx_rite(p).clear()
	check_near(CombatMath.damage_mult_for(p.stats, &"physical"), base_p, 0.0001, "the aura ends with the totem")
	check_near(CombatMath.damage_mult_for(near.stats, &"physical"), base_n, 0.0001, "for the ally too")


func test_ancestral_chorus_sleeps_until_six_wave_ends_and_thunderposts_carry_no_aura() -> void:
	var p := _armed_shaman(5)
	check(p.ability_mods(&"shaman_totems").is_empty(), "five wave ends: no totem mod")
	var item := p.equipment.get_item(Items.EquipSlot.MAIN_HAND)
	item.artifact_waves = 6
	p.equipment.changed.emit()
	check_near(float(p.ability_mods(&"shaman_totems").get("aura_damage_pct_add", 0.0)), 10.0, 0.0001, "six wave ends: the aura mod")
	_enemy(Vector3(0.0, 0.0, -4.0))
	_full_surge(p)
	check(_cast(p, &"forking_bolt"), "cast")
	var post := _post_script(p).standing()[0]
	check_near(post.num("aura_damage_pct"), 0.0, 0.0001, "a Thunderpost gives no aura")


# --- The class items ----------------------------------------------------------------------------------------------

func _items_of(class_id: StringName) -> Dictionary:
	return HUNTER_ITEMS if class_id == &"hunter" else SHAMAN_ITEMS


func test_each_class_has_eight_class_items_four_rare_and_four_epic() -> void:
	for class_id in [&"hunter", &"shaman"]:
		var items := Rules.class_items(class_id)
		check_eq(items.size(), Rules.CLASS_ITEMS_PER_CLASS, "%s: eight class items" % class_id)
		var table := _items_of(class_id)
		var slots: Dictionary[int, bool] = {}
		var rare := 0
		var epic := 0
		for u in items:
			check(table.has(u.id), "%s: %s is in the design" % [class_id, u.id])
			if not table.has(u.id):
				continue
			var row: Array = table[u.id]
			check_eq(u.rarity, row[1], "%s: rarity" % u.id)
			check_eq(u.slot_type, row[2], "%s: slot" % u.id)
			slots[u.slot_type] = true
			if u.rarity == Items.Rarity.RARE:
				rare += 1
			elif u.rarity == Items.Rarity.EPIC:
				epic += 1
		check_eq(rare, 4, "%s: four Rare" % class_id)
		check_eq(epic, 4, "%s: four Epic" % class_id)
		check_eq(slots.size(), 8, "%s: eight different slots" % class_id)
		check_eq(table.size(), 8, "%s: the table lists eight" % class_id)


func test_class_item_data_follows_the_class_item_rules() -> void:
	for class_id in [&"hunter", &"shaman"]:
		var cls := Db.get_class_data(class_id)
		for id: StringName in _items_of(class_id):
			var u := Db.get_unique(id)
			check(u != null, "%s loads" % id)
			if u == null:
				continue
			check_eq(u.id, id, "%s: id is the file name" % id)
			check(ResourceLoader.exists("res://data/uniques/%s.tres" % id), "%s: file exists" % id)
			check_eq(u.class_restriction, class_id, "%s: restricted to the class" % id)
			check_eq(u.unique_effect, &"ability_mod", "%s: an ability mod" % id)
			check(u.unique_text.begins_with("Equip:"), "%s: an Equip line" % id)
			check(u.display_name != "" and u.flavor != "", "%s: name and flavour" % id)
			check_eq(u.set_id, &"", "%s: no set piece" % id)
			check_eq(u.sources, [&"shop", &"loot", &"elite", &"goblin", &"boss"] as Array[StringName], "%s: all five sources" % id)
			check_eq(u.min_wave, 1, "%s: from wave 1" % id)
			check_eq(u.weight, 1.0, "%s: weight 1" % id)
			check(not u.stats.is_empty(), "%s: has stats" % id)
			for stat in u.stats:
				check(stat in Stats.ALL, "%s: known stat %s" % [id, stat])
			check_eq(u.slot_type in Items.ARMOR_SLOTS, u.armor_type != Items.NO_ARMOR, "%s: armour type exactly on armour slots" % id)
			if u.slot_type in Items.ARMOR_SLOTS:
				check_eq(u.armor_type, ClassData.ArmorType.MAIL, "%s: Mail" % id)
			check(u.weapon == null or u.slot_type == Items.SlotType.WEAPON, "%s: a weapon only in the weapon slot" % id)
			check(ItemGenerator.unique_usable_by(u, cls), "%s: usable by its class" % id)
			for other in Db.class_ids:
				if other != class_id:
					check(not ItemGenerator.unique_usable_by(u, Db.get_class_data(other)), "%s: not usable by %s" % [id, other])
	check_eq(Db.get_unique(&"longbow_of_many_feathers").weapon.weapon_type, &"bow", "the longbow is a bow")
	check_eq(Db.get_unique(&"rootbound_bulwark").weapon.weapon_type, &"shield", "the bulwark is a shield")


func test_class_items_name_an_ability_or_pseudo_ability_of_their_class() -> void:
	for class_id in [&"hunter", &"shaman"]:
		for id: StringName in _items_of(class_id):
			var u := Db.get_unique(id)
			var target := StringName(u.unique_params.get("ability", ""))
			var row: Array = _items_of(class_id)[id]
			check_eq(target, row[0], "%s: targets %s" % [id, row[0]])
			var ability := Db.get_ability(target)
			if ability != null:
				check_eq(ability.class_id, class_id, "%s: the ability is the class's" % id)
			else:
				check(BonusVocabulary.PSEUDO_IDS.get(target, &"") == class_id, "%s: %s is the class's pseudo ability" % [id, target])


func test_class_item_mods_change_real_params() -> void:
	for class_id in [&"hunter", &"shaman"]:
		for id: StringName in _items_of(class_id):
			var u := Db.get_unique(id)
			var target := StringName(u.unique_params["ability"])
			var mods: Dictionary = u.unique_params["mods"]
			check(not mods.is_empty(), "%s: has mods" % id)
			var base: Dictionary = {}
			var ability := Db.get_ability(target)
			if ability != null:
				base = {"cooldown": ability.cooldown, "cost": ability.cost, "charges": 1, "power": 1.0}
				base.merge(ability.params, true)
			elif target == &"hunter_companion":
				base = HunterCompanion.base_params(&"wolf")
			else:
				base = Db.get_ability(&"totem_rite").params.duplicate()
			for key in mods:
				var value: Variant = mods[key]
				check(typeof(value) in [TYPE_INT, TYPE_FLOAT], "%s: %s is a number" % [id, key])
				var param := String(key).trim_suffix("_add")
				check(param in base, "%s: %s changes %s, a real param of %s" % [id, key, param, target])
				var changed := AbilityRunner.apply_mods(base, {key: value})
				check(not is_equal_approx(float(changed.get(param, 0.0)), float(base.get(param, 0.0))), "%s: %s changes the value" % [id, key])
			# The Equip line states the numbers the mods have.
			var text_numbers: Array[float] = []
			var re := RegEx.new()
			re.compile("[0-9]+(\\.[0-9]+)?")
			for m in re.search_all(u.unique_text):
				text_numbers.append(m.get_string().to_float())
			for key in mods:
				var v := absf(float(mods[key]))
				check(text_numbers.any(func(n: float) -> bool: return is_equal_approx(n, v)), "%s: the text names %s" % [id, v])


func test_worn_class_items_change_the_abilities_of_the_hero() -> void:
	var heroes := {&"hunter": _hunter(Vector3.ZERO, 0), &"shaman": _shaman(Vector3(30, 0, 0), 1)}
	for id: StringName in ITEM_RESULTS:
		var u := Db.get_unique(id)
		var class_id := u.class_restriction
		var p: Player = heroes[class_id]
		var ability := Db.get_ability(StringName(u.unique_params["ability"]))
		var before := p.abilities.params_at_rank(ability, 1)
		var item := ItemGenerator.from_unique(u, 5, false, _rng, p.class_data)
		p.equipment.add_to_backpack(item)
		check(p.equipment.equip(item), "%s: worn by a %s" % [id, class_id])
		var after := p.abilities.params_at_rank(ability, 1)
		var results: Dictionary = ITEM_RESULTS[id]
		for param: String in results:
			check_near(float(after.get(param, -1.0)), float(results[param]), 0.0001, "%s: %s of %s" % [id, param, ability.id])
			check(not is_equal_approx(float(after.get(param, -1.0)), float(before.get(param, -2.0))), "%s: %s changed" % [id, param])
		check(p.equipment.take(item), "%s: comes off" % id)
		var gone := p.abilities.params_at_rank(ability, 1)
		for param: String in results:
			check_near(float(gone.get(param, -1.0)), float(before.get(param, -2.0)), 0.0001, "%s: %s is back" % [id, param])


func test_the_pseudo_ability_items_reach_the_companion_and_the_totems() -> void:
	var hunter := _hunter()
	var hauberk := ItemGenerator.from_unique(Db.get_unique(&"hauberk_of_the_loyal_heart"), 5, false, _rng, hunter.class_data)
	var comp := (hunter.abilities.mastery as HunterMastery).ensure_companion()
	check_near(float(comp.current_params()["damage_bonus"]), 0.0, 0.0001, "no bonus without the item")
	hunter.equipment.add_to_backpack(hauberk)
	check(hunter.equipment.equip(hauberk), "the hauberk is worn")
	var params := comp.current_params()
	check_near(float(params["damage_bonus"]), 30.0, 0.0001, "the companion deals 30% more")
	check_near(float(params["haste"]), 10.0, 0.0001, "and attacks 10% faster")
	var shaman := _shaman(Vector3(20, 0, 0), 1)
	var bulwark := ItemGenerator.from_unique(Db.get_unique(&"rootbound_bulwark"), 5, false, _rng, shaman.class_data)
	shaman.equipment.add_to_backpack(bulwark)
	check(shaman.equipment.equip(bulwark), "the bulwark is worn")
	check_near(float(ShamanKit.totem_params(shaman, shaman.abilities.params_for(Db.get_ability(&"totem_rite")))["duration"]), 13.0, 0.001, "totems last 3 s longer")
	check(_cast(shaman, &"totem_rite"), "Totem Rite")
	check_near(_fx_rite(shaman).standing()[0].time_left(), 13.0, 0.01, "the planted totem stands 13 s")
	# Bulwark and the 2-piece bonus together: more than either alone (+3 s and +30% in some order).
	_wear_set(shaman, SHAMAN_SET, 2)
	var both := float(ShamanKit.totem_params(shaman, shaman.abilities.params_for(Db.get_ability(&"totem_rite")))["duration"])
	check(both >= 16.0 and both <= 17.0, "bulwark and set bonus together (%.2f s)" % both)


func test_pseudo_ability_items_never_grey_out_in_the_tooltip() -> void:
	var hunter := _hunter()
	var shaman := _shaman(Vector3(30, 0, 0), 1)
	var hauberk := ItemGenerator.from_unique(Db.get_unique(&"hauberk_of_the_loyal_heart"), 5, false, _rng, hunter.class_data)
	var bulwark := ItemGenerator.from_unique(Db.get_unique(&"rootbound_bulwark"), 5, false, _rng, shaman.class_data)
	check_eq(ItemTooltip.unique_needs(hauberk, hunter), &"", "the companion needs nothing learned")
	check_eq(ItemTooltip.unique_needs(bulwark, shaman), &"", "totems need nothing learned")
	# A real ability still does: the Shaman has not learned Stormburst.
	var belt := ItemGenerator.from_unique(Db.get_unique(&"belt_of_gathered_thunder"), 5, false, _rng, shaman.class_data)
	check_eq(ItemTooltip.unique_needs(belt, shaman), &"stormburst", "an unlearned ability is still missing")
	var mask := ItemGenerator.from_unique(Db.get_unique(&"mask_of_the_gathering_storm"), 5, false, _rng, shaman.class_data)
	check_eq(ItemTooltip.unique_needs(mask, shaman), &"", "a core ability is always known")
	# The Warlock's Imp item had the same problem.
	var grimoire := ItemGenerator.from_unique(Db.get_unique(&"grimoire_of_the_imp_lord"), 5, false, _rng, Db.get_class_data(&"warlock"))
	var warlock := Fakes.spawn_player(world, 2, &"warlock", Vector3(60, 0, 0))
	check_eq(ItemTooltip.unique_needs(grimoire, warlock), &"", "the Imp needs nothing learned either")


func test_the_stormburst_belt_lets_two_enemies_trigger_it() -> void:
	var p := _shaman()
	p.stats.set_source(&"test", {Stats.INTELLECT: 10.0, Stats.SPELL_POWER: 4.0})
	_enemy(Vector3(1.0, 0.0, 0.0))
	_enemy(Vector3(-1.0, 0.0, 0.0))
	var slot := _learn(p, &"stormburst")
	var ctx := p.abilities.build_context(Db.get_ability(&"stormburst"))
	check(not _effect(p, &"stormburst").wants_auto_cast(ctx), "two enemies: not enough for the auto-cast")
	var belt := ItemGenerator.from_unique(Db.get_unique(&"belt_of_gathered_thunder"), 5, false, _rng, p.class_data)
	p.equipment.add_to_backpack(belt)
	check(p.equipment.equip(belt), "belt worn")
	ctx = p.abilities.build_context(Db.get_ability(&"stormburst"))
	check(_effect(p, &"stormburst").wants_auto_cast(ctx), "two enemies are enough with the belt")
	check(slot >= 0, "slot")


func test_the_gathering_storm_mask_makes_forking_bolt_cheaper() -> void:
	var p := _shaman()
	p.stats.set_source(&"test", {Stats.INTELLECT: 10.0, Stats.SPELL_POWER: 4.0})
	_enemy(Vector3(0.0, 0.0, -3.0))
	var surge := _surge(p)
	surge.set_value(30.0)
	var mask := ItemGenerator.from_unique(Db.get_unique(&"mask_of_the_gathering_storm"), 5, false, _rng, p.class_data)
	p.equipment.add_to_backpack(mask)
	check(p.equipment.equip(mask), "mask worn")
	check(_cast(p, &"forking_bolt"), "cast")
	# 30 - 22 = 8, +5 for the cast itself.
	check_near(surge.value, 13.0, 0.01, "the bolt cost 22 Surge")


# --- Artifact drop rules for seven classes ---------------------------------------------------------------------------

func _join(class_id: StringName) -> PlayerSlot:
	return PlayerManager.join(ScriptedInput.new("itc:%s" % class_id), Db.get_class_data(class_id))


func test_seven_classes_have_an_artifact_each() -> void:
	check_eq(Db.artifacts.size(), 7, "seven Artifacts")
	check_eq(Db.artifact_classes(), SEVEN, "one per class, in lobby order")
	check_eq(Db.artifact_classes().size(), Db.class_ids.size(), "every class has one")
	check(LootDrops.artifact_candidates(false) == SEVEN, "all seven can still drop")
	for class_id in SEVEN:
		var data := Db.artifact_for_class(class_id)
		check(data != null and Artifacts.validate(data) == "", "%s: valid" % class_id)
		check(ItemGenerator.generate_artifact(class_id, 10) != null, "%s: generates" % class_id)


func test_a_hunter_or_shaman_team_finds_its_own_artifact_about_83_percent_of_the_time() -> void:
	var expected := 0.8 + 0.2 / 7.0
	for class_id in [&"hunter", &"shaman"]:
		PlayerManager.clear()
		_join(class_id)
		var r := RandomNumberGenerator.new()
		r.seed = 321
		var own := 0
		for i in 4000:
			if LootDrops.pick_artifact_class(r) == class_id:
				own += 1
		check_near(float(own) / 4000.0, expected, 0.03, "%s: ~83%% its own Artifact" % class_id)
	PlayerManager.clear()


func test_seven_artifacts_drop_once_each_and_then_stop() -> void:
	_join(&"hunter")
	_join(&"shaman")
	LootDrops.artifact_chance_override = 1.0
	RunState.set_wave(10)
	var w2 := EFakes.make_world(tree)
	var seen: Array[StringName] = []
	for i in 12:
		var data := EFakes.enemy_data()
		data.is_boss = true
		var boss := EFakes.spawn_enemy(w2, data, Vector3(3.0, 0.0, 2.0), 10)
		var bag := LootDrops.roll_artifact(ItemGenerator.Source.BOSS, boss, null)
		if bag == null:
			break
		check(bag.item.class_restriction not in seen, "%s dropped twice" % bag.item.class_restriction)
		check_eq(Db.get_artifact(bag.item.source_id).class_id, bag.item.class_restriction, "the item is its class's Artifact")
		seen.append(bag.item.class_restriction)
	EFakes.free_world(tree, w2)
	tree.current_scene = world
	check_eq(seen.size(), 7, "seven drops")
	check(&"hunter" in seen and &"shaman" in seen, "both new Artifacts are among them")
	check_eq(RunState.artifacts_dropped, 7, "counted")
	check_eq(LootDrops.pick_artifact_class(RunState.rng), &"", "nothing left")


func test_an_artifact_roll_in_a_hunter_shaman_party_hands_out_their_artifacts_first() -> void:
	_join(&"hunter")
	_join(&"shaman")
	var r := RandomNumberGenerator.new()
	r.seed = 99
	var first_two := 0
	for run in 300:
		RunState.artifact_classes.clear()
		var a := LootDrops.pick_artifact_class(r)
		RunState.artifact_classes.append(a)
		var b := LootDrops.pick_artifact_class(r)
		if (a in [&"hunter", &"shaman"]) and (b in [&"hunter", &"shaman"]):
			first_two += 1
	RunState.artifact_classes.clear()
	check(first_two > 300 * 0.6, "the party's classes come up first (%d of 300)" % first_two)


# --- Content invariants without pending lines ------------------------------------------------------------------------------

func test_no_pending_line_is_left_for_the_artifacts_sets_and_items() -> void:
	for line in Rules.PENDING:
		check(not (String(line).ends_with(":artifact") or String(line).ends_with(":set") or String(line).ends_with(":items")),
				"%s should be gone: the content exists" % line)
	for class_id in [&"hunter", &"shaman"]:
		check_eq(Rules.count_of(class_id, "artifact"), 1, "%s: one Artifact" % class_id)
		check_eq(Rules.count_of(class_id, "set"), 1, "%s: one class set" % class_id)
		check_eq(Rules.count_of(class_id, "items"), Rules.CLASS_ITEMS_PER_CLASS, "%s: eight class items" % class_id)
		check(not Rules.pending(class_id, "artifact") and not Rules.pending(class_id, "set") and not Rules.pending(class_id, "items"),
				"%s: nothing pending for the ITEMS parts" % class_id)
	for part in ["artifact", "set", "items"]:
		check(&"hunter" in Rules.classes_with(part) and &"shaman" in Rules.classes_with(part), "both classes count for %s" % part)
	check_eq(Rules.launch_uniques(), Rules.LAUNCH_UNIQUES, "the launch hand-made items are unchanged")


func test_names_of_the_new_items_are_unique_across_the_game() -> void:
	var names: Dictionary[String, String] = {}
	for id in Db.uniques:
		var name: String = Db.uniques[id].display_name
		check(not names.has(name), "'%s' (%s) is also %s" % [name, id, names.get(name, "")])
		names[name] = String(id)
	for id in Db.artifacts:
		var name: String = Db.artifacts[id].display_name
		check(not names.has(name), "'%s' (Artifact %s) is also %s" % [name, id, names.get(name, "")])
		names[name] = String(id)
	for id in Db.sets:
		var name: String = Db.sets[id].display_name
		check(not names.has(name), "'%s' (set %s) is also %s" % [name, id, names.get(name, "")])
		names[name] = String(id)
	var props: Dictionary[String, String] = {}
	for id in Db.artifacts:
		for p in Db.artifacts[id].properties:
			var pname := String(p["name"])
			check(not props.has(pname), "property '%s' of %s is also of %s" % [pname, id, props.get(pname, "")])
			props[pname] = String(id)
