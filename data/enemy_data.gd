class_name EnemyData
extends Resource
## An enemy definition (GDD chapter 8). Instances live in res://data/enemies/.

## CHASE: walk straight at the nearest living player.
## SWARM: like CHASE but faster and weaker, spawns in big groups.
## LUNGE: chase, and when close wind up briefly then leap forward.
## RANGED: keep preferred_distance and throw projectiles.
enum Behavior { CHASE, SWARM, LUNGE, RANGED }

@export var id: StringName
@export var display_name: String
@export var behavior: Behavior = Behavior.CHASE

@export_group("Stats")
@export var max_hp: float = 8.0
## Added to max_hp for every wave after the first (before the global wave multiplier).
@export var hp_per_wave: float = 2.0
@export var contact_damage: float = 1.0
@export var damage_per_wave: float = 0.6
## Metres / second.
@export var move_speed: float = 2.4
## Collision / visual radius in metres.
@export var radius: float = 0.45
@export var knockback_resist: float = 0.0
## Resistance (0..1) to stuns.
@export var stun_resist: float = 0.0

@export_group("Ranged / Lunge")
@export var preferred_distance: float = 7.0
@export var attack_cooldown: float = 2.5
@export var projectile_damage: float = 2.0
@export var projectile_speed: float = 9.0
@export var lunge_speed: float = 9.0
@export var lunge_windup: float = 0.45

@export_group("Spawning")
@export var first_wave: int = 1
@export var spawn_weight: float = 1.0
## Enemies spawned together around one telegraph marker: random in [group_min, group_max].
@export var group_min: int = 1
@export var group_max: int = 1

@export_group("Loot")
@export var gold: int = 1
@export var xp: int = 1

@export_group("Look")
## skeleton, candlekin, gurgler, troll
@export var model_style: StringName
@export var color: Color = Color(0.85, 0.85, 0.8)
@export var model_scale: float = 1.0


## Max HP at [param wave] before co-op scaling (RunState.coop_hp_mult()).
func hp_at_wave(wave: int) -> float:
	return max_hp + hp_per_wave * maxi(0, wave - 1)


func contact_damage_at_wave(wave: int) -> float:
	return contact_damage + damage_per_wave * maxi(0, wave - 1)


func projectile_damage_at_wave(wave: int) -> float:
	return projectile_damage + damage_per_wave * maxi(0, wave - 1)
