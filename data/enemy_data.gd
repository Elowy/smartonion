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
## Max HP at wave 1 (before co-op scaling).
@export var max_hp: float = 8.0
## HP growth per wave after the first, as a fraction of [member max_hp] (GDD 9: +12% per
## wave, additive). A future DifficultyData may override it.
@export var hp_growth: float = 0.12
## Contact damage at wave 1.
@export var contact_damage: float = 1.0
## Contact / projectile damage growth per wave after the first, as a fraction of the base
## value (GDD 9: +8% per wave, additive). A future DifficultyData may override it.
@export var damage_growth: float = 0.08
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


## Max HP at [param wave] before co-op scaling (Enemy multiplies by RunState.coop_hp_mult()):
## max_hp * (1 + hp_growth * (wave - 1)) (GDD 9).
func hp_at_wave(wave: int) -> float:
	return max_hp * hp_mult_at_wave(wave)


## Contact damage at [param wave]: contact_damage * (1 + damage_growth * (wave - 1)) (GDD 9).
func contact_damage_at_wave(wave: int) -> float:
	return contact_damage * damage_mult_at_wave(wave)


## Projectile damage at [param wave]: projectile_damage * (1 + damage_growth * (wave - 1)).
func projectile_damage_at_wave(wave: int) -> float:
	return projectile_damage * damage_mult_at_wave(wave)


## HP multiplier of [param wave] relative to wave 1.
func hp_mult_at_wave(wave: int) -> float:
	return maxf(0.0, 1.0 + hp_growth * maxi(0, wave - 1))


## Damage multiplier of [param wave] relative to wave 1.
func damage_mult_at_wave(wave: int) -> float:
	return maxf(0.0, 1.0 + damage_growth * maxi(0, wave - 1))
