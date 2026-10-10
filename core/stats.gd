class_name Stats
extends RefCounted
## Stat identifiers, defaults and caps (GDD chapter 2).
##
## Percent stats are stored as percentage points: crit = 5.0 means 5%.
## Primary stats (strength / agility / intellect) are flat values that weapons scale with.

# Primary
const STAMINA := &"stamina"
const STRENGTH := &"strength"
const AGILITY := &"agility"
const INTELLECT := &"intellect"
# Secondary
const CRIT := &"crit"
const HASTE := &"haste"
const MASTERY := &"mastery"
const VERSATILITY := &"versatility"
# Defensive / tertiary
const ARMOR := &"armor"
const DODGE := &"dodge"
const AVOIDANCE := &"avoidance"
const LEECH := &"leech"
const SPEED := &"speed"
const SPIRIT := &"spirit"
# Custom
const FORTUNE := &"fortune"
const GOLD_FIND := &"gold_find"
# Utility (not shown on items, used by systems)
## Percent: +100 doubles BASE_PICKUP_RANGE (GDD 2.4.1).
const PICKUP_RANGE := &"pickup_range"
const DAMAGE_PCT := &"damage_pct"
# Exotic stats – only from items / enchantments (GDD 2.4.1). Wired into combat in M2.
const ATTACK_POWER := &"attack_power"      ## flat damage per weapon hit (speed-normalised)
const SPELL_POWER := &"spell_power"        ## flat damage for spells, magic weapons and spell procs
const EXTRA_ATTACK := &"extra_attack"      ## % chance a weapon hit strikes again at once
const CRIT_DAMAGE := &"crit_damage"        ## +% critical strike multiplier
const THORNS := &"thorns"                  ## damage returned to melee attackers
const PARRY := &"parry"                    ## % chance to parry a melee hit (+ riposte)
const BLOCK_VALUE := &"block_value"        ## +% damage absorbed by a block
const COOLDOWN_REDUCTION := &"cooldown_reduction"  ## -% ability cooldowns (abilities: M3+)
const RESOURCE_REGEN := &"resource_regen"  ## +% class resource generation (M3+)
const EXTRA_PROJECTILE := &"extra_projectile"  ## +N projectiles in a fan
const PIERCE := &"pierce"                  ## +N projectile pierce
const AREA_SIZE := &"area_size"            ## +% AoE radius
const FIRE_DAMAGE := &"fire_damage"        ## +% damage of that school
const FROST_DAMAGE := &"frost_damage"
const ARCANE_DAMAGE := &"arcane_damage"
const HOLY_DAMAGE := &"holy_damage"
const SHADOW_DAMAGE := &"shadow_damage"
const NATURE_DAMAGE := &"nature_damage"
const PHYSICAL_DAMAGE := &"physical_damage"
const EXECUTIONER := &"executioner"        ## +% damage vs targets below 30% HP
const SLAYER := &"slayer"                  ## +% damage vs elites and bosses
const LIFE_ON_KILL := &"life_on_kill"      ## % chance to heal 1 HP on kill
const XP_GAIN := &"xp_gain"                ## +% XP

## School stat per damage school id (spell / proc schools, GDD 6.4).
const SCHOOL_STATS := {
	&"fire": FIRE_DAMAGE, &"frost": FROST_DAMAGE, &"arcane": ARCANE_DAMAGE,
	&"holy": HOLY_DAMAGE, &"shadow": SHADOW_DAMAGE, &"nature": NATURE_DAMAGE,
	&"physical": PHYSICAL_DAMAGE,
}

const ALL: Array[StringName] = [
	STAMINA, STRENGTH, AGILITY, INTELLECT,
	CRIT, HASTE, MASTERY, VERSATILITY,
	ARMOR, DODGE, AVOIDANCE, LEECH, SPEED, SPIRIT,
	FORTUNE, GOLD_FIND, PICKUP_RANGE, DAMAGE_PCT,
	ATTACK_POWER, SPELL_POWER, EXTRA_ATTACK, CRIT_DAMAGE, THORNS, PARRY, BLOCK_VALUE,
	COOLDOWN_REDUCTION, RESOURCE_REGEN, EXTRA_PROJECTILE, PIERCE, AREA_SIZE,
	FIRE_DAMAGE, FROST_DAMAGE, ARCANE_DAMAGE, HOLY_DAMAGE, SHADOW_DAMAGE, NATURE_DAMAGE,
	PHYSICAL_DAMAGE, EXECUTIONER, SLAYER, LIFE_ON_KILL, XP_GAIN,
]

const BASE_MAX_HP := 10.0
const BASE_MOVE_SPEED := 5.0  ## metres / second at Speed 0
const BASE_PICKUP_RANGE := 3.0  ## metres at Pickup Range 0

const DODGE_CAP := 60.0
const AVOIDANCE_CAP := 50.0
const VERSATILITY_REDUCTION_CAP := 30.0
const CRIT_CAP := 100.0
const LEECH_CAP := 100.0
const MIN_SPEED := -80.0
const MIN_HASTE := -80.0

const DISPLAY_NAMES := {
	STAMINA: "Stamina",
	STRENGTH: "Strength",
	AGILITY: "Agility",
	INTELLECT: "Intellect",
	CRIT: "Critical Strike",
	HASTE: "Haste",
	MASTERY: "Mastery",
	VERSATILITY: "Versatility",
	ARMOR: "Armor",
	DODGE: "Dodge",
	AVOIDANCE: "Avoidance",
	LEECH: "Leech",
	SPEED: "Speed",
	SPIRIT: "Spirit",
	FORTUNE: "Fortune",
	GOLD_FIND: "Gold Find",
	PICKUP_RANGE: "Pickup Range",
	DAMAGE_PCT: "Damage",
	ATTACK_POWER: "Attack Power",
	SPELL_POWER: "Spell Power",
	EXTRA_ATTACK: "Extra Attack",
	CRIT_DAMAGE: "Critical Damage",
	THORNS: "Thorns",
	PARRY: "Parry",
	BLOCK_VALUE: "Block Value",
	COOLDOWN_REDUCTION: "Cooldown Reduction",
	RESOURCE_REGEN: "Resource Regen",
	EXTRA_PROJECTILE: "Extra Projectile",
	PIERCE: "Pierce",
	AREA_SIZE: "Area Size",
	FIRE_DAMAGE: "Fire Damage",
	FROST_DAMAGE: "Frost Damage",
	ARCANE_DAMAGE: "Arcane Damage",
	HOLY_DAMAGE: "Holy Damage",
	SHADOW_DAMAGE: "Shadow Damage",
	NATURE_DAMAGE: "Nature Damage",
	PHYSICAL_DAMAGE: "Physical Damage",
	EXECUTIONER: "Executioner",
	SLAYER: "Slayer",
	LIFE_ON_KILL: "Life on Kill",
	XP_GAIN: "XP Gain",
}

## Stats displayed with a % suffix.
const PERCENT_STATS: Array[StringName] = [
	CRIT, HASTE, VERSATILITY, DODGE, AVOIDANCE, LEECH, SPEED, GOLD_FIND, PICKUP_RANGE, DAMAGE_PCT,
	EXTRA_ATTACK, CRIT_DAMAGE, PARRY, BLOCK_VALUE, COOLDOWN_REDUCTION, RESOURCE_REGEN, AREA_SIZE,
	FIRE_DAMAGE, FROST_DAMAGE, ARCANE_DAMAGE, HOLY_DAMAGE, SHADOW_DAMAGE, NATURE_DAMAGE,
	PHYSICAL_DAMAGE, EXECUTIONER, SLAYER, LIFE_ON_KILL, XP_GAIN,
]


static func display_name(stat: StringName) -> String:
	return DISPLAY_NAMES.get(stat, String(stat).capitalize())


static func is_percent(stat: StringName) -> bool:
	return stat in PERCENT_STATS


static func format_value(stat: StringName, value: float) -> String:
	var sign := "+" if value >= 0.0 else ""
	var text := sign + (str(int(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value)
	return text + ("%" if is_percent(stat) else "")
