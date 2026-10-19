class_name ArtifactRogueFangsFan
extends TalentEffect
## Shadow's Bite – property 1 of the Fangs of the Shadow (GDD 5.5): every [code]every[/code]th
## (5) critical strike of the Rogue throws a free Fan of Knives (RogueFanOfKnives.throw_free: no
## Energy, no cooldown, no on-cast procs; Combo Points are spent and multiply it as usual).
## One count per attack: only the first hit of an attack (the ProcGate hit) counts, so an
## arc / fan that crits on several targets is one critical strike. The count carries across
## waves; it resets when the property goes away. No RNG.
## Final balance 2: at most one free fan every [code]cooldown[/code] (3) seconds. With 60-80% crit and Haste the
## fives came faster than one a second, so a Rogue with the Fangs threw 2-3 times the fans of one without (8.7k
## against 3.2k DPS on Vor'thalax, Fan of Knives hits plus an Envenom burst on every throw, the one item that made
## a lone Rogue kill him in 11-24 s). A fifth crit that lands inside the cooldown keeps the count at "ready": the
## next crit after it throws the fan.
##
## Params (not rank-scaled): every (crits per fan), cooldown (s between two free fans, 0 = none).

## Critical strikes counted towards the next fan (stays at `every` while the cooldown runs).
var crits := 0
## Free fans thrown (tests).
var fans := 0
## Seconds until the next free fan may be thrown.
var cooldown_left := 0.0


func on_hit(_target: Node3D, _damage: float, is_crit: bool, first: bool) -> void:
	if not is_crit or not first or player == null or not is_instance_valid(player):
		return
	var every := maxi(1, roundi(num("every", 5.0)))
	crits = mini(crits + 1, every)
	if crits < every or cooldown_left > 0.0:
		return
	crits = 0
	if RogueFanOfKnives.throw_free(player):
		fans += 1
		cooldown_left = maxf(0.0, num("cooldown", 0.0))


func tick(delta: float) -> void:
	if cooldown_left > 0.0:
		cooldown_left = maxf(0.0, cooldown_left - delta)


func describe() -> String:
	var text := "Every %d critical strikes throw a free Fan of Knives" % maxi(1, roundi(num("every", 5.0)))
	var cooldown := num("cooldown", 0.0)
	if cooldown > 0.0:
		text += ", at most once every %s sec" % String.num(cooldown, 1).trim_suffix(".0")
	return text + "."
