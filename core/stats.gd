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

const ALL: Array[StringName] = [
	STAMINA, STRENGTH, AGILITY, INTELLECT,
	CRIT, HASTE, MASTERY, VERSATILITY,
	ARMOR, DODGE, AVOIDANCE, LEECH, SPEED, SPIRIT,
	FORTUNE, GOLD_FIND, PICKUP_RANGE, DAMAGE_PCT,
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
}

## Stats displayed with a % suffix.
const PERCENT_STATS: Array[StringName] = [
	CRIT, HASTE, VERSATILITY, DODGE, AVOIDANCE, LEECH, SPEED, GOLD_FIND, PICKUP_RANGE, DAMAGE_PCT,
]


static func display_name(stat: StringName) -> String:
	return DISPLAY_NAMES.get(stat, String(stat).capitalize())


static func is_percent(stat: StringName) -> bool:
	return stat in PERCENT_STATS


static func format_value(stat: StringName, value: float) -> String:
	var sign := "+" if value >= 0.0 else ""
	var text := sign + (str(int(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value)
	return text + ("%" if is_percent(stat) else "")
