class_name HunterMastery
extends MasteryEffect
## Hunter class hooks (GDD 3.7): Mastery "Beastbond" (+% damage of the companion per Mastery
## point) and the permanent animal companion ([HunterCompanion]: Wolf, Boar or Owl, by
## [member Player.companion_id]).
##
## The companion is spawned lazily from [method tick] (a physics tick – never while a parent is
## busy setting up children) once the Hunter is in the tree and alive, survives waves, hides itself
## while the Hunter is downed, snaps back to the Hunter at every wave start and is freed in
## [method teardown]. Its damage is PET damage (ProcSystem.deal_raw, source &"pet"): Beastbond
## multiplies it – and Hunt Signal's blow, bleed and splash, which are pet damage too.

## Beastbond: % more companion damage per Mastery point.
const PCT_PER_POINT := 2.0

var companion: HunterCompanion


## Damage multiplier of Beastbond for pet damage (1 + Mastery x 2 %).
func bond_mult() -> float:
	return maxf(0.0, 1.0 + mastery() * PCT_PER_POINT / 100.0)


func damage_mult(_target: Node3D, _school: StringName, source: StringName) -> float:
	return bond_mult() if source == &"pet" else 1.0


## Also runs while the Hunter is downed (MasteryEffect.tick): no companion is summoned then (an
## existing one hides itself and stops attacking, HunterCompanion.step).
func tick(_delta: float) -> void:
	if player != null and player.is_alive():
		ensure_companion()


func begin_wave() -> void:
	if has_companion():
		companion.begin_wave()


func teardown() -> void:
	if has_companion():
		companion.dismiss()
	companion = null


func describe() -> String:
	return "Beastbond: +%s%% companion damage" % _fmt(mastery() * PCT_PER_POINT)


func has_companion() -> bool:
	return companion != null and is_instance_valid(companion) and not companion.is_queued_for_deletion()


## Spawns the companion next to the Hunter when it has none (Hunter in the tree). Returns it.
func ensure_companion() -> HunterCompanion:
	if has_companion():
		return companion
	companion = null
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return null
	var spawned := HunterCompanion.spawn(player)
	if not spawned.is_inside_tree():
		spawned.free()
		return null
	companion = spawned
	return companion


static func _fmt(v: float) -> String:
	return str(int(roundf(v))) if is_equal_approx(v, roundf(v)) else "%.1f" % v
