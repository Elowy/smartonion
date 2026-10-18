class_name EnemyData
extends Resource
## An enemy definition (GDD chapter 8). Instances live in res://data/enemies/.

## CHASE: walk straight at the nearest living player.
## SWARM: like CHASE but faster and weaker, spawns in big groups.
## LUNGE: chase, and when close wind up briefly then leap forward.
## RANGED: keep preferred_distance and throw projectiles.
## SUPPORT (M6): keeps its distance and heals / shields other enemies in a short channel
## (Cultist Acolyte; Enemy._think_support, the "Support" group below).
## BRUTE (M6): slow heavy hitter whose hook line pulls a hero in (Flesh Golem;
## Enemy._think_brute, the "Brute" group below).
## SUPPORT and BRUTE are appended so the stored values of the others stay the same.
enum Behavior { CHASE, SWARM, LUNGE, RANGED, SUPPORT, BRUTE }

@export var id: StringName
@export var display_name: String
@export var behavior: Behavior = Behavior.CHASE
## A boss (M6, [BossData]): Enemy.is_boss() reads it. Execute, Mirror Image and the other
## "not on bosses" rules key on it.
@export var is_boss := false

@export_group("Stats")
## Max HP at wave 1 (before co-op scaling).
@export var max_hp: float = 8.0
## HP growth per wave after the first, as a fraction of [member max_hp] (GDD 9: +12% per
## wave, additive). A future DifficultyData may override it.
@export var hp_growth: float = 0.12
## Compounding HP factor per wave after the first, on top of [member hp_growth] (GDD 9): the
## heroes' power compounds (items, ranks, level cards), so the enemies' HP has to as well.
@export var hp_compound: float = 0.22
## Contact damage at wave 1.
@export var contact_damage: float = 1.0
## Contact / projectile damage growth per wave after the first, as a fraction of the base
## value (GDD 9: +15% per wave, additive). A future DifficultyData may override it.
@export var damage_growth: float = 0.15
## Compounding damage factor per wave after the first, on top of [member damage_growth]
## (GDD 9).
@export var damage_compound: float = 0.1
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

@export_group("Death effect")
## What the enemy leaves where it dies: &"" (nothing) or &"poison_puddle" (Plague Ghoul: a green
## puddle that hurts heroes only, see PoisonPuddle). Not left by a wave-end despawn.
@export var death_effect: StringName = &""
## Puddle radius (m) and how long it stays (s).
@export var death_radius: float = 1.6
@export var death_duration: float = 3.0
## Seconds between two puddle ticks.
@export var death_tick_interval: float = 0.5
## Damage per puddle tick as a fraction of the enemy's contact damage at its wave (party size
## and elite affixes included): 0.5 at 2 ticks / s = the contact damage per second.
@export var death_damage_ratio: float = 0.5
@export var death_color: Color = Color(0.36, 0.78, 0.2)

@export_group("Support")
## SUPPORT keeps this far from the nearest hero: it backs off inside the minimum, closes in
## beyond the maximum (m) and otherwise stays with the other enemies.
@export var support_distance_min: float = 6.0
@export var support_distance_max: float = 9.0
## Heals / shields enemies within this many metres (centre to centre).
@export var support_range: float = 7.0
## Channel time (s); attack_cooldown is the time between two channels.
@export var support_channel: float = 0.6
## A heal restores this fraction of the target's max HP ...
@export var support_heal_pct: float = 0.25
## ... or, when nobody is hurt, a shield of this fraction (never above it: refresh only).
@export var support_shield_pct: float = 0.2
## A "primary target" (GDD 8): bots go for it first (Enemy.is_priority_target).
@export var priority_target := false

@export_group("Brute")
## BRUTE hooks a hero whose distance (m) is within this band; attack_cooldown is the time
## between two hooks.
@export var hook_range_min: float = 4.0
@export var hook_range_max: float = 9.0
## Seconds the hook line shows before the pull (the aim locks for the last part).
@export var hook_telegraph: float = 0.8
## The hero in the line is dragged this many metres towards the brute ...
@export var hook_pull: float = 3.0
## ... and takes this multiple of the brute's contact damage (a Dodge avoids all of it).
@export var hook_damage_ratio: float = 1.0

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
## skeleton, candlekin, gurgler, troll, goblin, ghoul, cultist, golem
@export var model_style: StringName
@export var color: Color = Color(0.85, 0.85, 0.8)
@export var model_scale: float = 1.0


## Max HP at [param wave] before co-op scaling (Enemy multiplies by RunState.coop_hp_mult()):
## max_hp * [method hp_mult_at_wave] (GDD 9).
func hp_at_wave(wave: int) -> float:
	return max_hp * hp_mult_at_wave(wave)


## Contact damage at [param wave] before the party-size factor (Enemy multiplies by
## RunState.coop_damage_mult()): contact_damage * [method damage_mult_at_wave] (GDD 9).
func contact_damage_at_wave(wave: int) -> float:
	return contact_damage * damage_mult_at_wave(wave)


## Projectile damage at [param wave] before the party-size factor (as
## [method contact_damage_at_wave]): projectile_damage * [method damage_mult_at_wave].
func projectile_damage_at_wave(wave: int) -> float:
	return projectile_damage * damage_mult_at_wave(wave)


## HP multiplier of [param wave] relative to wave 1, n = wave - 1:
## (1 + hp_growth * n) * (1 + hp_compound)^n.
func hp_mult_at_wave(wave: int) -> float:
	return growth_mult(wave, hp_growth, hp_compound)


## Damage multiplier of [param wave] relative to wave 1, n = wave - 1:
## (1 + damage_growth * n) * (1 + damage_compound)^n.
func damage_mult_at_wave(wave: int) -> float:
	return growth_mult(wave, damage_growth, damage_compound)


## (1 + [param linear] * n) * (1 + [param compound])^n with n = wave - 1 (at least 0), never
## negative: the additive per-wave growth of GDD 9 times a compounding factor.
static func growth_mult(wave: int, linear: float, compound: float) -> float:
	var n := maxi(0, wave - 1)
	return maxf(0.0, (1.0 + linear * n) * pow(maxf(0.0, 1.0 + compound), n))
