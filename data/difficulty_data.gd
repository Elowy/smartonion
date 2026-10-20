class_name DifficultyData
extends Resource
## One difficulty tier (GDD 9.1, M9 meta-progression): Normal, Pungent and Tear-Jerker. Instances live in
## res://data/difficulties/ (loaded by Db into [member Db.difficulties]); the rules around them (the tier order, the
## per-class unlocks, the multipliers every system reads) are the static helpers of [Difficulty].
##
## Every field is a plain multiplier (1.0 = unchanged): Normal holds only 1.0s, so a Normal run is the base game bit for
## bit. Where each one is read:
##   enemy_hp_mult        Enemy.setup / Boss.create (next to Shrines.enemy_hp_mult)
##   enemy_damage_mult    Enemy.setup: contact and projectile damage (next to RunState.coop_damage_mult)
##   spawn_density_mult   WaveDirector.spawn_budget_per_second (the cap of 150 enemies stays)
##   elite_rate_mult      EliteAffixes.rate_mult (set at the run's start)
##   shop_price_mult      every gold price of the shop, the Trainer, the Enchanter, the consumables row and the
##                        Black Market (rerolls are exempt)
##   xp_mult / seeds_mult the run-end Class XP and Seeds (read by the Class Level package: Difficulty.xp_mult())
## Tear-Jerker also has [member pressure]: one rotating modifier per wave ([PressureData], [Pressure]).

@export var id: StringName
@export var display_name := ""
## Position in the ladder (0 = Normal): the lobby cycles by it and a higher tier needs more wins.
@export var tier := 0
@export_multiline var description := ""
@export var enemy_hp_mult := 1.0
@export var enemy_damage_mult := 1.0
@export var spawn_density_mult := 1.0
@export var elite_rate_mult := 1.0
@export var shop_price_mult := 1.0
@export var xp_mult := 1.0
@export var seeds_mult := 1.0
## Tear-Jerker: a pressure modifier rolls for every eligible wave.
@export var pressure := false
## Reserved (GDD 9.1 "extra affixes"): nothing reads it in M9.
@export var extra_elite_affixes := 0
## The tier's colour (the HUD chip, the end screen, the lobby and the leaderboard).
@export var color := Color.WHITE
