class_name PressureData
extends Resource
## One Tear-Jerker pressure modifier (M9 ACHIEVE-DIFF): a short-lived twist that applies to a single wave. Instances
## live in res://data/pressure/ (loaded by Db into [member Db.pressures]); the rotation, the effects and the texts are
## the static helpers of [Pressure].
##
## The percentages are the Shrines plumbing's: the enemy fields scale every enemy that spawns in the wave
## (like ShrineData), [member gold_pct] / [member xp_pct] scale the pickups, [member spawn_rate_pct] multiplies the
## WaveDirector's spawn budget and [member elite_rate_pct] the elites of the wave. [member hero_effects] go to every
## hero for the wave (BonusVocabulary entries, PlayerBonuses source [constant Pressure.SOURCE]; the consumables'
## "stats_pct" extension works too). All of it is live only while a wave runs.

@export var id: StringName
@export var display_name := ""
## One line of what it does ("Spawn rate +30%, enemy HP -12%"), shown on the break screen and the wave banner.
@export_multiline var text := ""
## Max HP / contact and projectile damage / walking speed of every enemy that spawns in the wave (percent).
@export var enemy_hp_pct := 0.0
@export var enemy_damage_pct := 0.0
@export var enemy_speed_pct := 0.0
## The WaveDirector's spawn budget and the wave's elite count (percent).
@export var spawn_rate_pct := 0.0
@export var elite_rate_pct := 0.0
## Gold and XP the pickups give (percent).
@export var gold_pct := 0.0
@export var xp_pct := 0.0
## BonusVocabulary entries every hero gets for the wave.
@export var hero_effects: Array[Dictionary] = []
## The chip's colour on the HUD.
@export var color := Color(0.9, 0.4, 0.35)
