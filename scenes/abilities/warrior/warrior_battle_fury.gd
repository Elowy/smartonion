class_name WarriorBattleFury
extends MasteryEffect
## Mastery "Battle Fury" (GDD 3.1): the lower the HP, the more damage – +0.5% outgoing damage
## per Mastery point for every 10% of missing health (smooth, not in steps). Applies to every
## damage source: weapon hits, procs, DoTs, abilities and pets.

## % damage per Mastery point per 10% missing health.
const PCT_PER_POINT := 0.5
const STEP := 0.1


## Missing health as a ratio 0..1 (a downed hero counts as 1).
func missing_ratio() -> float:
	if player == null:
		return 0.0
	var max_hp := player.max_hp()
	if max_hp <= 0.0:
		return 0.0
	return clampf(1.0 - player.hp / max_hp, 0.0, 1.0)


## The bonus in percent at the current health.
func bonus_pct() -> float:
	return maxf(0.0, mastery()) * PCT_PER_POINT * missing_ratio() / STEP


func damage_mult(_target: Node3D, _school: StringName, _source: StringName) -> float:
	return 1.0 + bonus_pct() / 100.0


## A new wave starts clean: an unfinished Charge buff does not carry over.
func begin_wave() -> void:
	if player != null:
		player.damage_mults.erase(WarriorCharge.BUFF_KEY)


func describe() -> String:
	return "Battle Fury: +%.1f%% damage per 10%% missing health (now +%.1f%%)" % [
			maxf(0.0, mastery()) * PCT_PER_POINT, bonus_pct()]
