class_name AudioIds
extends RefCounted
## Which sound id a weapon or an ability plays (pure functions; the ids live in
## data/audio/sound_bank.tres). tests/test_m7_audio.gd checks that every result exists in the bank.

## Weapon families whose swing is slow and heavy.
const HEAVY_TYPES: Array[StringName] = [&"mace", &"two_hand_mace", &"two_hand_sword", &"axe"]
## Weapon families whose swing is quick and light (the fast weapons).
const LIGHT_TYPES: Array[StringName] = [&"dagger", &"fist_weapon"]
## Magic schools that have a cast sound (everything else casts as arcane).
const CAST_SCHOOLS: Array[StringName] = [&"fire", &"frost", &"arcane", &"holy", &"shadow", &"nature"]
## Ability schools that have a sound; the rest is physical.
const ABILITY_SCHOOLS: Array[StringName] = [&"fire", &"frost", &"arcane", &"holy", &"shadow", &"nature"]


## The swing of a melee weapon.
static func swing(weapon: WeaponData) -> StringName:
	if weapon == null:
		return &"swing_blade"
	if weapon.weapon_type in LIGHT_TYPES:
		return &"swing_light"
	if weapon.hand == WeaponData.Hand.TWO_HAND or weapon.weapon_type in HEAVY_TYPES:
		return &"swing_heavy"
	return &"swing_blade"


## The shot of a projectile weapon: bow, crossbow and gun have their own, wands / staves / orbs cast their school.
static func shot(weapon: WeaponData) -> StringName:
	if weapon == null:
		return &"shot_bow"
	match weapon.weapon_type:
		&"bow":
			return &"shot_bow"
		&"gun":
			return &"shot_gun"
		&"crossbow":
			return &"shot_crossbow"
	if weapon.school != &"physical":
		return cast_for_school(weapon.school)
	if weapon.weapon_type in [&"wand", &"staff", &"orb", &"tome"]:
		return &"cast_arcane"
	return &"shot_bow"


## The weapon-cast sound of a magic school.
static func cast_for_school(school: StringName) -> StringName:
	return StringName("cast_" + String(school)) if school in CAST_SCHOOLS else &"cast_arcane"


## The cast sound of an ability: what it does first (summon, heal, shield, buff, movement), then
## its school.
static func ability(data: AbilityData) -> StringName:
	if data == null:
		return &"ability_physical"
	var tags := data.tags
	if &"pet" in tags:
		return &"ability_summon"
	if &"heal" in tags:
		return &"ability_heal"
	if &"shield" in tags:
		return &"ability_shield"
	if &"buff" in tags:
		return &"ability_buff"
	if &"movement" in tags:
		return &"ability_move"
	if data.school in ABILITY_SCHOOLS:
		return StringName("ability_" + String(data.school))
	if &"aoe" in tags or &"ground" in tags:
		return &"ability_aoe"
	return &"ability_physical"
