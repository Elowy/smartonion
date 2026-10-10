class_name WeaponData
extends Resource
## A weapon definition (GDD chapter 4). Instances live in res://data/weapons/.

enum Hand { ONE_HAND, TWO_HAND, OFF_HAND }
## How the weapon attacks.
## MELEE_ARC: instant hit on every enemy inside a cone in front of the wielder.
## PROJECTILE: fires a projectile at the target.
## NONE: passive off-hand item (shield, tome) – only grants bonus_stats.
enum AttackKind { MELEE_ARC, PROJECTILE, NONE }

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
## sword, axe, mace, dagger, bow, gun, wand, staff, shield, tome
@export var weapon_type: StringName
@export var hand: Hand = Hand.ONE_HAND
@export var attack_kind: AttackKind = AttackKind.MELEE_ARC

@export_group("Damage")
@export var base_damage: float = 5.0
## stat -> multiplier, e.g. { &"strength": 1.0 }
@export var scaling: Dictionary[StringName, float] = {}
## Seconds between attacks at Haste 0.
@export var cooldown: float = 1.0
@export var crit_mult: float = 2.0
@export var knockback: float = 2.0
## 0..1 chance to stun the target for stun_duration seconds.
@export var stun_chance: float = 0.0
@export var stun_duration: float = 0.5

@export_group("Reach")
## Metres. For MELEE_ARC this is the reach of the swing; for PROJECTILE the targeting range.
@export var attack_range: float = 2.0
@export var arc_degrees: float = 100.0
@export var projectile_speed: float = 18.0
## How many extra enemies a projectile passes through.
@export var pierce: int = 0
## Metres; > 0 makes projectiles explode on impact.
@export var aoe_radius: float = 0.0

@export_group("Passive")
## Flat stat bonuses while equipped (shields, tomes, rarity bonuses).
@export var bonus_stats: Dictionary[StringName, float] = {}
## Block chance in percent (shields).
@export var block_chance: float = 0.0

@export_group("Shop")
@export var base_price: int = 20
@export var rarity: int = 0
@export var color: Color = Color(0.8, 0.8, 0.85)


func is_two_handed() -> bool:
	return hand == Hand.TWO_HAND


func is_off_hand_only() -> bool:
	return hand == Hand.OFF_HAND


func attacks() -> bool:
	return attack_kind != AttackKind.NONE
