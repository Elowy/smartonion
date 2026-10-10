class_name EnchantData
extends Resource
## A random enchantment (GDD 5.7). Instances live in res://data/enchants/.
## Effects are built from a small set of reusable building blocks run by ProcSystem.

enum Kind { EQUIP, ON_HIT, ON_KILL, WHEN_STRUCK }

## Value multiplier per rank (I, II, III) – GDD 5.7: rank grows with the item's wave.
const RANK_MULT: Array[float] = [1.0, 1.5, 2.0]

@export var id: StringName
## Name prefix of the item, e.g. "Blazing".
@export var prefix: String
@export var kind: Kind = Kind.EQUIP
## Items.SlotType values this enchant may roll on.
@export var slot_types: Array[int] = []
## Only roll on weapons that fire projectiles (e.g. +1 Extra Projectile).
@export var requires_projectile: bool = false
@export var min_rarity: int = 1
@export var weight: float = 1.0

@export_group("Equip")
## EQUIP kind: flat stat bonuses at rank I (multiplied by RANK_MULT).
@export var equip_stats: Dictionary[StringName, float] = {}

@export_group("Proc")
## Building block run by ProcSystem: projectile, chain, dot, buff, heal, extra_attack, aoe,
## slow, stun, gold, resource, shield, nova, leech_bolt ...
@export var effect: StringName
## Effect parameters at rank I (numbers are multiplied by RANK_MULT where it makes sense).
@export var params: Dictionary = {}
## ON_HIT: procs per minute (chance per hit = ppm * weapon cooldown / 60).
@export var ppm: float = 0.0
## ON_KILL / WHEN_STRUCK: chance in percent.
@export var chance: float = 0.0
## Internal cooldown in seconds.
@export var icd: float = 0.0
## physical, fire, frost, arcane, holy, shadow, nature
@export var school: StringName = &"physical"

@export_group("Text")
## Tooltip line, "{name}" placeholders are filled from params / equip_stats at the rank,
## e.g. "Chance on hit: Hurls a fiery ball that causes {damage} Fire damage."
@export_multiline var description: String


static func rank_mult(rank: int) -> float:
	return RANK_MULT[clampi(rank, 0, RANK_MULT.size() - 1)]


func is_proc() -> bool:
	return kind != Kind.EQUIP
