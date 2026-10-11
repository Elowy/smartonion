class_name WarlockSummonInfernal
extends AbilityEffect
## Summon Infernal (GDD 6.4, Warlock, Active, 1 Soul Shard, long cooldown): an Infernal
## ([WarlockInfernal]) crashes down on the densest group of enemies within range – a fire
## burst that stuns everything around the crater – and smashes enemies for
## [code]duration[/code] seconds (pet damage: Demonic Pact boosts it). One at a time.
##
## Params (read by the Infernal): duration, impact_damage / impact_intellect_scale /
## impact_spell_power_scale, impact_radius, impact_stun (s); damage / intellect_scale /
## spell_power_scale (per slam, Spell Power per second), slam_interval, slam_radius;
## immolation_share / immolation_radius (Immolation spec), taunt_radius (Guardian spec);
## radius (cluster radius of the targeting), auto_cast_min (bots: enemies in that circle).
## "power" (Ranks II / IV) scales every damage. Rank III: +3 s. Rank V: Immolation or
## Abyssal Guardian.

var infernal: WarlockInfernal


func has_infernal() -> bool:
	return infernal != null and is_instance_valid(infernal) and not infernal.is_queued_for_deletion() \
			and not infernal.is_leaving()


## Needs a group to land on (no shard is spent into the void) and no Infernal out.
func can_cast(ctx: AbilityContext) -> bool:
	return ctx.target != null and not has_infernal()


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree() or ctx.target == null or has_infernal():
		return false
	var spawned := WarlockInfernal.spawn(p, ctx.point, ctx.params)
	if not spawned.is_inside_tree():
		spawned.free()
		return false
	infernal = spawned
	return true


## Bots: a big enough group in the landing circle.
func wants_auto_cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree() or ctx.target == null or has_infernal():
		return false
	var radius := WarlockSpell.area(p.stats, ctx.num("radius", 3.0))
	return WarlockSpell.count_in_circle(p.get_tree(), ctx.point, radius) >= int(ctx.num("auto_cast_min", 5.0))


func begin_wave(_ctx: AbilityContext) -> void:
	dismiss(true)


func end_wave(_ctx: AbilityContext) -> void:
	dismiss(true)


func dismiss(quiet: bool = false) -> void:
	if infernal != null and is_instance_valid(infernal):
		infernal.dismiss(quiet)
	infernal = null
