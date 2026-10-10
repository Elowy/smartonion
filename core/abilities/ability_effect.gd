class_name AbilityEffect
extends RefCounted
## Behaviour of an AbilityData. One instance per player per ability (may keep state).
## Override cast(); optionally can_cast() / wants_auto_cast() / tick().


## Extra conditions besides cost / cooldown (e.g. "an ally needs healing"). Default: true.
func can_cast(_ctx: AbilityContext) -> bool:
	return true


## Bots (and later an auto-cast option) call this to decide whether casting now is useful.
## Default: an enemy is within the ability's cast range.
func wants_auto_cast(ctx: AbilityContext) -> bool:
	return ctx.target != null or ctx.ability.targeting == AbilityData.Targeting.SELF


## Performs the ability. Return false to refund (nothing happened).
func cast(_ctx: AbilityContext) -> bool:
	return true


## Called every physics frame while the player lives (channels, stateful effects).
func tick(_ctx: AbilityContext, _delta: float) -> void:
	pass
