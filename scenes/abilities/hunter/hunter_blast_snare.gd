class_name HunterBlastSnare
extends AbilityEffect
## Blast Snare (GDD 3.7, Hunter Auto, 8 s, Fire): lays [code]traps[/code] (1) [HunterSnare]s
## [code]lay_distance[/code] (3) m from the hero towards the nearest enemy. A snare arms after
## [code]arm_time[/code] (0.5) s and bursts when an enemy body enters its [code]trigger_radius[/code]
## (1.2) m: [code]damage_pct[/code] (220) % of the weapon hit "W" x "power" as Fire damage (no
## crits) to everything in the [code]radius[/code] (2.5) m circle (x Area Size), plus a
## [code]slow[/code] % slow for [code]slow_duration[/code] s. It lasts [code]lifetime[/code] (15) s;
## at most [code]max_traps[/code] (3) of the Hunter's snares live at once – a newer one pushes the
## oldest out (it fizzles). Several snares of one cast stand side by side.
## Ranks (M4): Rank III +1 m blast radius; Rank V "Clinging Net" ([code]slow[/code] +60) or
## "Heavy Charge" ([code]damage_pct[/code] +100, [code]arm_time[/code] +0.5).
## Talent riders (neutral at 0): [code]ember_duration[/code] / [code]ember_pct[/code] /
## [code]ember_tick[/code] – burning ground after the burst; [code]scatter[/code] /
## [code]scatter_pct[/code] / [code]scatter_radius[/code] / [code]scatter_range[/code] – smaller
## bombs round the burst (Firebug Bombs); [code]traps[/code] / [code]max_traps[/code] (Brace of Snares).
## Wave start / end and the Hunter leaving remove the snares.
## Bots lay a snare when an enemy is 2-8 m away, fewer than max_traps snares are out and none of
## them lies within [constant AUTO_CLEAR] m of the new spot.

const AUTO_MIN_DISTANCE := 2.0
const AUTO_CLEAR := 2.0
## Sideways gap between the snares of one cast (m).
const SIDE_GAP := 1.3

## The Hunter's snares, oldest first (tests; pruned lazily).
var snares: Array[HunterSnare] = []


## The numbers one snare carries, from the cast's [param ctx] (final values: Area Size applied).
static func snare_numbers(ctx: AbilityContext) -> Dictionary:
	var player := ctx.player
	var power := ctx.num("power", 1.0)
	var w := HunterKit.hit_damage(player, HunterKit.FIRE)
	var damage := w * ctx.num("damage_pct", 220.0) / 100.0 * power
	var area := CombatMath.area_mult(player.stats)
	return {
		"damage": damage,
		"radius": ctx.num("radius", 2.5) * area,
		"base_radius": ctx.num("radius", 2.5),
		"trigger_radius": ctx.num("trigger_radius", 1.2),
		"arm_time": maxf(0.0, ctx.num("arm_time", 0.5)),
		"lifetime": maxf(0.5, ctx.num("lifetime", 15.0)),
		"slow": clampf(ctx.num("slow", 0.0) * power, 0.0, 90.0),
		"slow_duration": ctx.num("slow_duration", 3.0),
		"ember_duration": maxf(0.0, ctx.num("ember_duration", 0.0)),
		"ember_damage": w * ctx.num("ember_pct", 0.0) / 100.0 * power,
		"ember_tick": ctx.num("ember_tick", 0.5),
		"scatter": maxi(0, roundi(ctx.num("scatter", 0.0))),
		"scatter_damage": damage * ctx.num("scatter_pct", 50.0) / 100.0,
		"scatter_radius": ctx.num("scatter_radius", 1.5) * area,
		"scatter_range": ctx.num("scatter_range", 3.0),
	}


func can_cast(ctx: AbilityContext) -> bool:
	return ctx.target != null


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_inside_tree() or ctx.target == null:
		return false
	var dist := GeneralKit.flat_distance(ctx.target.global_position, player.global_position)
	if dist < AUTO_MIN_DISTANCE or dist > ctx.ability.cast_range:
		return false
	_prune()
	if snares.size() >= maxi(1, roundi(ctx.num("max_traps", 3.0))):
		return false
	var spot := lay_point(player, ctx.target, ctx.num("lay_distance", 3.0))
	for s in snares:
		if GeneralKit.flat_distance(s.global_position, spot) < AUTO_CLEAR:
			return false
	return true


func cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_inside_tree() or ctx.target == null:
		return false
	var numbers := snare_numbers(ctx)
	var base := lay_point(player, ctx.target, ctx.num("lay_distance", 3.0))
	var dir := HunterKit.dir_to(player.global_position, ctx.target.global_position, ctx.direction)
	var side := Vector3(dir.z, 0.0, -dir.x)
	var count := maxi(1, roundi(ctx.num("traps", 1.0)))
	var max_traps := maxi(1, roundi(ctx.num("max_traps", 3.0)))
	_prune()
	var laid := 0
	for i in count:
		var offset := (float(i) - float(count - 1) * 0.5) * SIDE_GAP
		var snare := HunterSnare.lay(player, _inside_arena(base + side * offset), numbers)
		if not snare.is_inside_tree():
			snare.free()
			continue
		snares.append(snare)
		laid += 1
	while snares.size() > max_traps:
		var oldest: HunterSnare = snares.pop_front()
		if is_instance_valid(oldest):
			oldest.fizzle()
	if laid > 0:
		player.face_attack(dir)
	return laid > 0


func begin_wave(_ctx: AbilityContext) -> void:
	_clear()


func end_wave(_ctx: AbilityContext) -> void:
	_clear()


## Living snares of this Hunter (oldest first).
func live_snares() -> Array[HunterSnare]:
	_prune()
	return snares.duplicate()


## Where a snare goes: [param distance] m from the hero towards [param target].
static func lay_point(player: Player, target: Node3D, distance: float) -> Vector3:
	var here := player.global_position
	var dir := HunterKit.dir_to(here, target.global_position, player.facing)
	return Vector3(here.x, 0.0, here.z) + dir * distance


static func _inside_arena(pos: Vector3) -> Vector3:
	var arena := Arena.current
	if arena != null and is_instance_valid(arena):
		return arena.clamp_point(pos, 0.5)
	return pos


func _prune() -> void:
	var kept: Array[HunterSnare] = []
	for s in snares:
		if is_instance_valid(s) and s.is_active():
			kept.append(s)
	snares = kept


func _clear() -> void:
	for s in snares:
		if is_instance_valid(s) and not s.is_queued_for_deletion():
			s.fizzle(true)
	snares.clear()
