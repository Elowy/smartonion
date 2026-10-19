class_name ArtifactWarlockSecondVoidwalker
extends TalentEffect
## Bound Soul – property 1 of the Skull of the Damned (GDD 5.5): a second, permanent pet – a
## Voidwalker (the pet of Summon Voidwalker, [WarlockVoidwalker]) that taunts the enemies around
## it. It is summoned on the first tick of every wave the Warlock is up for (and again after a
## revive), like the Imp, and leaves when the Warlock goes down, at the wave's end and when the
## property goes away. It uses the Summon Voidwalker params of the hero (its rank and Rank V
## choice when the ability is learned, the base params when not), without the Shared Pain ward
## (that damage reduction belongs to the ability's own Voidwalker, which can stand next to this
## one). No RNG.

## Seconds between two refreshes of the pet's params (ranks / talents change them).
const PARAMS_INTERVAL := 1.0

## The pet while it stands (may be freed: check is_instance_valid).
var pet: WarlockVoidwalker

var _params_clock := 0.0


## True while the pet stands.
func has_pet() -> bool:
	return pet != null and is_instance_valid(pet) and not pet.is_queued_for_deletion() and not pet.is_leaving()


func tick(delta: float) -> void:
	if player == null or not is_instance_valid(player) or not player.is_alive() or not player.is_inside_tree():
		return
	if has_pet():
		_params_clock -= delta
		if _params_clock <= 0.0:
			_params_clock = PARAMS_INTERVAL
			pet.params = voidwalker_params()
		return
	pet = null
	var spawned := WarlockVoidwalker.spawn(player, voidwalker_params())
	if not spawned.is_inside_tree():
		spawned.free()
		return
	pet = spawned
	_params_clock = PARAMS_INTERVAL


## The Voidwalker's params for this hero: Summon Voidwalker at the hero's rank (1 when not
## learned), its ability mods applied, the ward off.
func voidwalker_params() -> Dictionary:
	var out := {}
	var ability := Db.get_ability(&"summon_voidwalker")
	if ability != null and player != null and player.abilities != null:
		out = player.abilities.params_at_rank(ability, player.abilities.rank_of(ability.id),
				player.abilities.spec_of(ability.id)).duplicate()
	out["damage_reduction"] = 0.0
	return out


func end_wave() -> void:
	dismiss(true)


func teardown() -> void:
	dismiss(true)


func dismiss(quiet: bool = false) -> void:
	if pet != null and is_instance_valid(pet):
		pet.dismiss(quiet)
	pet = null


func describe() -> String:
	return "A second, permanent Gloomguard fights at your side."
