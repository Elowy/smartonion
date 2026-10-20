class_name HunterHuntSignal
extends AbilityEffect
## Hunt Signal (GDD 3.7, Hunter Auto, 10 s, tagged pet): the companion dashes at the STRONGEST
## enemy within [code]range[/code] (10) m of the Hunter and strikes it: [code]blow_pct[/code] (250)
## % of the weapon hit "W" x "power" through ProcSystem.deal_raw(..., &"pet") (Beastbond, the pet
## damage mods and Pack Frenzy apply; no crit). "Strongest" = boss, then elite, then any; within a
## tier the most Max HP, then the nearest to the companion. A rider by kind: the Wolf slows the
## target by [code]wolf_slow[/code] (50) % for [code]wolf_slow_duration[/code] (2) s, the Boar stuns it
## for [code]boar_stun[/code] (1) s, the Owl adds [code]owl_bonus[/code] (25) % damage.
## Needs a living companion that is out (the cast is refused without one).
## Ranks (M4): Rank III [code]strikes[/code] +1 (a second strike on the next-strongest enemy); Rank V
## "Mauling Rush" ([code]splash_radius[/code] 2.5: enemies near the target take [code]splash_pct[/code]
## (60) % of the blow) or "Relentless Pursuit" ([code]kill_reset[/code] 2: a kill with the blow brings
## the ability back after 2 s). Talent rider: [code]bleed_pct[/code] % of the blow over
## [code]bleed_duration[/code] s as a pet-damage bleed (Open Wound).
## Bots send the companion when a boss or elite is within range, or [code]min_enemies[/code] (3)
## enemies are within [constant AUTO_RADIUS] m of the Hunter.

const AUTO_RADIUS := 8.0

var _player: Player
var _ability: AbilityData
var _kill_reset := 0.0
## Hunt Signals cast this wave and the targets of the last one (tests).
var casts := 0
var last_targets: Array[Enemy] = []


func can_cast(ctx: AbilityContext) -> bool:
	var pet := HunterKit.companion(ctx.player)
	return ctx.target != null and pet != null and not pet.is_hidden() and not pet.is_signalling()


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_inside_tree() or not player.is_alive():
		return false
	var pet := HunterKit.companion(player)
	if pet == null or pet.is_hidden() or pet.is_signalling():
		return false
	var reach := ctx.num("range", 10.0)
	var here := player.global_position
	for node in EnemyGrid.gather_around(player.get_tree(), here, reach):
		var e := node as Enemy
		if HunterKit.is_live(e) and e.is_elite() and GeneralKit.flat_distance(e.global_position, here) <= reach:
			return true
	return GeneralKit.enemies_near(player, AUTO_RADIUS).size() >= int(ctx.num("min_enemies", 3.0))


func cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	var pet := HunterKit.companion(player)
	if player == null or pet == null or pet.is_hidden() or not player.is_inside_tree():
		return false
	var count := maxi(1, roundi(ctx.num("strikes", 1.0)))
	var targets := strongest(player, pet.global_position, ctx.num("range", 10.0), count)
	if targets.is_empty():
		return false
	_player = player
	_ability = ctx.ability
	_kill_reset = ctx.num("kill_reset", 0.0)
	var power := ctx.num("power", 1.0)
	var blow := {
		"pct": ctx.num("blow_pct", 250.0) * power,
		"wolf_slow": ctx.num("wolf_slow", 0.0) * power,
		"wolf_slow_duration": ctx.num("wolf_slow_duration", 2.0),
		"boar_stun": ctx.num("boar_stun", 0.0),
		"owl_bonus": ctx.num("owl_bonus", 0.0),
		"splash_radius": ctx.num("splash_radius", 0.0),
		"splash_pct": ctx.num("splash_pct", 60.0),
		"bleed_pct": ctx.num("bleed_pct", 0.0),
		"bleed_duration": ctx.num("bleed_duration", 4.0),
		"on_kill": Callable(self, "_on_blow_kill"),
	}
	if not pet.command_strikes(targets, blow):
		return false
	casts += 1
	last_targets = targets
	return true


func begin_wave(_ctx: AbilityContext) -> void:
	casts = 0


## Relentless Pursuit: a kill with the blow brings Hunt Signal back after kill_reset seconds.
func _on_blow_kill(_enemy: Variant) -> void:
	if _kill_reset <= 0.0 or _player == null or not is_instance_valid(_player) or _player.abilities == null \
			or _ability == null:
		return
	var runner := _player.abilities
	if runner.cooldown_left(_ability) > _kill_reset:
		runner.set_cooldown(_ability, _kill_reset)


## The [param count] strongest living enemies within [param reach] m of [param player]: bosses
## first, then elites, then the rest; inside a tier the most Max HP, then the nearest to
## [param from] (the companion), then the oldest instance (a stable order).
static func strongest(player: Player, from: Vector3, reach: float, count: int) -> Array[Enemy]:
	var out: Array[Enemy] = []
	if player == null or not player.is_inside_tree() or count <= 0:
		return out
	var here := player.global_position
	var rows: Array[Array] = []
	for node in EnemyGrid.gather_around(player.get_tree(), here, reach):
		var e := node as Enemy
		if not HunterKit.is_live(e) or GeneralKit.flat_distance(e.global_position, here) > reach:
			continue
		var tier := 2 if e.is_boss() else (1 if e.is_elite() else 0)
		rows.append([tier, e.max_hp, GeneralKit.flat_distance(e.global_position, from), e.get_instance_id(), e])
	rows.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return int(a[0]) > int(b[0])
		if not is_equal_approx(float(a[1]), float(b[1])):
			return float(a[1]) > float(b[1])
		if not is_equal_approx(float(a[2]), float(b[2])):
			return float(a[2]) < float(b[2])
		return int(a[3]) < int(b[3]))
	for row in rows:
		out.append(row[4])
		if out.size() >= count:
			break
	return out
