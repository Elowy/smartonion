class_name ArtifactRogueFangsFan
extends TalentEffect
## Shadow's Bite – property 1 of the Fangs of the Shadow (GDD 5.5): every [code]every[/code]th
## (5) critical strike of the Rogue throws a free Fan of Knives (RogueFanOfKnives.throw_free: no
## Energy, no cooldown, no on-cast procs; Combo Points are spent and multiply it as usual).
## One count per attack: only the first hit of an attack (the ProcGate hit) counts, so an
## arc / fan that crits on several targets is one critical strike. The count carries across
## waves; it resets when the property goes away. No RNG.
##
## Params (not rank-scaled): every (crits per fan).

## Critical strikes counted towards the next fan.
var crits := 0
## Free fans thrown (tests).
var fans := 0


func on_hit(_target: Node3D, _damage: float, is_crit: bool, first: bool) -> void:
	if not is_crit or not first or player == null or not is_instance_valid(player):
		return
	crits += 1
	if crits < maxi(1, roundi(num("every", 5.0))):
		return
	crits = 0
	if RogueFanOfKnives.throw_free(player):
		fans += 1


func describe() -> String:
	return "Every %d critical strikes throw a free Fan of Knives." % maxi(1, roundi(num("every", 5.0)))
