class_name HunterLongShot
extends AbilityEffect
## Long Shot (GDD 3.7, Hunter Active, 9 s): the Hunter takes aim for [code]windup[/code] (0.7) s
## while it keeps moving and shooting ([HunterAimCharge] shows it), then looses a heavy arrow – a
## weapon hit ([HunterArrow]) of [code]damage_pct[/code] (320) % of the weapon hit "W" x "power"
## – along the best LINE: the line from the hero through an enemy, 1 m wide, that holds the most
## enemies (ties: the line through the enemy with the most health). The arrow pierces everything
## on it ([code]pierce[/code] 99) and flies [code]range[/code] m at [code]speed[/code] m/s.
## Enemies below [code]execute_threshold[/code] (35) % health take [code]execute_bonus[/code] %
## more (Finishing Arrow, Rank V talents). The cooldown starts with the aiming; going down, the
## wave ending / starting or forgetting the ability cancels it. With nobody left in reach at the
## release the arrow flies along the facing.
## Ranks (M4): Rank III [code]arrows[/code] +1 (the extra arrow flies along the next-best line, at
## least [constant MIN_LINE_ANGLE] degrees from the first; without one it repeats the best line);
## Rank V "Snap Shot" ([code]windup[/code] 0, cooldown -30 %: loosed at once) or "Rending Shaft"
## ([code]bleed_pct[/code] +80: a struck enemy bleeds for that % of "W" over
## [code]bleed_duration[/code] s, [HunterBleed]).
## Bots shoot at an elite or boss in reach, or when the best line holds three or more enemies.

const SOUND := &"shot_bow"
## Half the width of a line (m, plus the enemy's radius).
const LINE_HALF_WIDTH := 0.5
## Lines of one shot differ by at least this many degrees.
const MIN_LINE_ANGLE := 8.0
const AUTO_LINE_ENEMIES := 3
## Candidates looked at per search (a crowd is scored by its first MAX_CANDIDATES enemies).
const MAX_CANDIDATES := 64
const ARROW_SCALE := 1.5
const ARROW_COLOR := Color(1.0, 0.62, 0.2)

## Seconds of aiming left (0 = not aiming).
var windup_left := 0.0
## Shots released this wave (tests) and the arrows of the last one.
var released := 0
var last_arrows: Array[HunterArrow] = []

var _charge: HunterAimCharge


func is_winding_up() -> bool:
	return windup_left > 0.0


func can_cast(ctx: AbilityContext) -> bool:
	return ctx.target != null and not is_winding_up()


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_inside_tree() or ctx.target == null or is_winding_up():
		return false
	var reach := ctx.ability.cast_range
	var here := player.global_position
	for node in EnemyGrid.gather_around(player.get_tree(), here, reach):
		var e := node as Enemy
		if HunterKit.is_live(e) and e.is_elite() and GeneralKit.flat_distance(e.global_position, here) <= reach:
			return true
	var lines := best_lines(player, ctx.num("range", 14.0), 1)
	return not lines.is_empty() and int(lines[0]["count"]) >= AUTO_LINE_ENEMIES


func cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_inside_tree() or ctx.target == null:
		return false
	if not player.downed_changed.is_connected(_on_downed_changed):
		player.downed_changed.connect(_on_downed_changed)
	var windup := ctx.num("windup", 0.7)
	if windup <= 0.0:
		release(ctx)
		return true
	windup_left = windup
	_clear_charge()
	_charge = HunterAimCharge.attach(player, windup)
	return true


func tick(ctx: AbilityContext, delta: float) -> void:
	if not is_winding_up():
		return
	windup_left -= delta
	if windup_left <= 0.0001:
		windup_left = 0.0
		release(ctx)


## Looses the arrow(s) now (end of the aiming).
func release(ctx: AbilityContext) -> void:
	_clear_charge()
	var player := ctx.player
	if player == null or not is_instance_valid(player) or not player.is_inside_tree() or player.downed:
		return
	var reach := ctx.num("range", 14.0)
	var count := maxi(1, roundi(ctx.num("arrows", 1.0)))
	var lines := best_lines(player, reach, count)
	var facing := WeaponRunner.flat(player.facing)
	facing = facing.normalized() if facing.length_squared() > 0.0001 else Vector3.FORWARD
	var power := ctx.num("power", 1.0)
	var w := HunterKit.hit_damage(player, HunterKit.PHYSICAL)
	var options := {
		"execute_threshold": ctx.num("execute_threshold", 35.0),
		"execute_bonus": ctx.num("execute_bonus", 0.0),
		"bleed_total": w * ctx.num("bleed_pct", 0.0) / 100.0 * power,
		"bleed_duration": ctx.num("bleed_duration", 4.0),
	}
	last_arrows = []
	for i in count:
		var dir := facing
		if not lines.is_empty():
			dir = lines[mini(i, lines.size() - 1)]["dir"]
		var arrows := HunterArrow.fan(player, dir, 1, 0.0, w * ctx.num("damage_pct", 320.0) / 100.0 * power,
				ctx.num("speed", 36.0), reach, roundi(ctx.num("pierce", 99.0)), null, options, ARROW_COLOR)
		for a in arrows:
			a.scale = Vector3.ONE * ARROW_SCALE
		last_arrows.append_array(arrows)
	if not last_arrows.is_empty():
		Audio.play(SOUND)
		released += 1


## Cancels the aiming (nothing is loosed; the cooldown stays spent).
func cancel() -> void:
	windup_left = 0.0
	_clear_charge()


func begin_wave(_ctx: AbilityContext) -> void:
	cancel()
	released = 0


func end_wave(_ctx: AbilityContext) -> void:
	cancel()


func _clear_charge() -> void:
	if _charge != null and is_instance_valid(_charge) and not _charge.is_queued_for_deletion():
		_charge.finish()
	_charge = null


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		cancel()


## The best lines from the hero through the enemies within [param reach]: up to [param count]
## entries {"dir": unit XZ vector, "count": enemies on the line, "hp": health of the enemy the line
## runs through}, best first (most enemies, then most health). Later entries differ from earlier
## ones by at least MIN_LINE_ANGLE degrees; when fewer such lines exist the list is shorter (an
## empty list: nobody in reach).
static func best_lines(player: Player, reach: float, count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if player == null or not player.is_inside_tree() or count <= 0:
		return out
	var here := player.global_position
	var candidates: Array[Enemy] = []
	for node in EnemyGrid.gather_around(player.get_tree(), here, reach):
		var e := node as Enemy
		if HunterKit.is_live(e) and GeneralKit.flat_distance(e.global_position, here) <= reach:
			candidates.append(e)
			if candidates.size() >= MAX_CANDIDATES:
				break
	var scored: Array[Dictionary] = []
	for c in candidates:
		var dir := HunterKit.dir_to(here, c.global_position)
		var n := 0
		for e in candidates:
			var rel := WeaponRunner.flat(e.global_position - here)
			if rel.dot(dir) < 0.0:
				continue
			if absf(rel.x * dir.z - rel.z * dir.x) <= LINE_HALF_WIDTH + e.radius:
				n += 1
		scored.append({"dir": dir, "count": n, "hp": c.hp, "id": c.get_instance_id()})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["count"] != b["count"]:
			return int(a["count"]) > int(b["count"])
		if not is_equal_approx(float(a["hp"]), float(b["hp"])):
			return float(a["hp"]) > float(b["hp"])
		return int(a["id"]) < int(b["id"]))
	var cos_limit := cos(deg_to_rad(MIN_LINE_ANGLE))
	for s in scored:
		var distinct := true
		for taken in out:
			if (s["dir"] as Vector3).dot(taken["dir"]) > cos_limit:
				distinct = false
				break
		if distinct:
			out.append(s)
			if out.size() >= count:
				break
	return out
