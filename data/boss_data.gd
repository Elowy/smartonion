class_name BossData
extends EnemyData
## A boss definition (GDD chapter 8, M6). Instances live in res://data/bosses/ (loaded by Db
## into Db.bosses, not into Db.enemies: the wave director never picks a boss from the pool).
## A BossData is an EnemyData whose [member EnemyData.is_boss] is true by default, so
## everything that reads an EnemyData (Enemy.setup, hp_at_wave, the model) works unchanged.
##
## The BOSSES package fills this class in. Fields it owns (TODO, nothing here yet):
## - phases: HP ratios of the phase changes (phase 2 at 50%) and what changes in each
## - abilities: the telegraphed attacks (kind, interval, telegraph time, damage in contact
##   multiples, radius / cone angle / range) per phase, plus the add waves (Raise Dead, Imp Swarm)
## - enrage: seconds until the enrage (90 s), the damage / speed bonus and the repeat step
## - rewards: gold (50), loot source, whether it ends the run (Vor'thalax = victory)
## - hud: title shown on the boss frame, the model style ids of the two bosses

## --boss-hp=X (LaunchOptions.boss_hp): multiplies every boss's max HP. 1 = off. Reset to 1 by
## RunState.start_run and re-applied by Main.start_run; the boss spawner reads it.
static var hp_mult := 1.0


func _init() -> void:
	is_boss = true
