class_name WarlockSummonVoidwalker
extends AbilityEffect
## Summon Voidwalker (GDD 6.4, Warlock, Auto, pet): once learned, a Voidwalker
## ([WarlockVoidwalker]) fights at the Warlock's side – summoned on the first tick of every
## wave the Warlock is up for (and again after a revive), it guards the Warlock, keeps
## enemies near it taunted (threat aura) and punches them (pet damage, Demonic Pact).
## The ability's cast is the Voidwalker's Torment: every enemy around it is taunted onto it
## for a few seconds.
##
## Params (read by the pet): damage, intellect_scale, spell_power_scale, attack_interval,
## attack_range (fists); taunt_radius, taunt_interval, taunt_duration (aura); torment_radius,
## torment_duration, torment_damage_mult (Consuming Shadows: x fist damage), torment_slow (%);
## damage_reduction (Shared Pain, %); auto_cast_min (untaunted enemies around it for the
## auto-cast). "power" (Ranks II / IV) scales its damage.
## Rank III: bigger Torment and aura. Rank V: Shared Pain or Consuming Shadows.

var pet: WarlockVoidwalker


func has_pet() -> bool:
	return pet != null and is_instance_valid(pet) and not pet.is_queued_for_deletion() and not pet.is_leaving()


## Summons the Voidwalker for [param ctx]'s Warlock when it has none (alive, in the tree).
func ensure_pet(ctx: AbilityContext) -> WarlockVoidwalker:
	if has_pet():
		pet.params = ctx.params
		return pet
	pet = null
	var p := ctx.player
	if p == null or not is_instance_valid(p) or not p.is_inside_tree() or not p.is_alive():
		return null
	var spawned := WarlockVoidwalker.spawn(p, ctx.params)
	if not spawned.is_inside_tree():
		spawned.free()
		return null
	pet = spawned
	return pet


## Runs while the Warlock lives: keeps the Voidwalker summoned with the current params.
func tick(ctx: AbilityContext, _delta: float) -> void:
	ensure_pet(ctx)


func can_cast(_ctx: AbilityContext) -> bool:
	return has_pet()


## Torment. False (no cooldown) when no enemy was around.
func cast(ctx: AbilityContext) -> bool:
	if ensure_pet(ctx) == null:
		return false
	return pet.torment() > 0


## Auto-cast: at least auto_cast_min enemies within the Torment radius not taunted yet.
func wants_auto_cast(ctx: AbilityContext) -> bool:
	if not has_pet() or ctx.player == null:
		return false
	var radius := WarlockSpell.area(ctx.player.stats, ctx.num("torment_radius", 5.0))
	return pet.untaunted_near(radius) >= int(ctx.num("auto_cast_min", 1.0))


## Wave start / end and forgetting the ability: the Voidwalker leaves (it comes back on the
## next tick of a wave).
func begin_wave(_ctx: AbilityContext) -> void:
	dismiss(true)


func end_wave(_ctx: AbilityContext) -> void:
	dismiss(true)


func dismiss(quiet: bool = false) -> void:
	if pet != null and is_instance_valid(pet):
		pet.dismiss(quiet)
	pet = null
